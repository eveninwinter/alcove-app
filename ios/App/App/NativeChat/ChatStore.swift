import Foundation
import SwiftUI

@MainActor
final class ChatStore: ObservableObject {
    @Published var messages: [ChatMessage] = []
    private var deletedMessageTs: Set<String> = []
    // 0906 她要的：多选时图一个圈、字一个圈，勾哪个收哪个。
    // 两个名单各管一块；同一条两个名单都在 = 整条收走。
    private var temporarilyHiddenTextTs: Set<String> = []
    private var temporarilyHiddenPhotoTs: Set<String> = []
    @Published var isTyping = false
    @Published var apiLive: AlcoveAPI.LiveState? = nil   // 0926 API 房间流式的半截，poll 捎回来
    @Published var currentTool: String?
    @Published var stickers: [Sticker] = []
    @Published var stickerUploading = false
    @Published var stickerUploadError = ""
    @Published var loading = true
    @Published var loadingOlder = false
    @Published var hasOlder = true
    @Published private(set) var isViewingHistory = false
    // 0922 任务#2572：她是不是就在最底下（ChatView 的 atBottom 同步过来）。只有在底下才敢把表顶上的老消息扔掉，
    // 她往上翻着看的时候扔，屏幕会跳。不发布，纯给 appendNew 看。
    var viewerAtBottom = true
    @Published var connectionError = false
    @Published var heldCount = 0
    @Published var stagingImages = false
    @Published var modelLabel = ""
    // 0919 三个房间：现在看的是哪间（cli / sdk / api）。切房间＝清空重拉，轮询也只拉这间的
    @Published var room: String = AlcoveAPI.chatRoom
    @Published var recallMap: [String: RecallItem] = [:] // norm(prompt) -> 最新召回
    private var orderedRecalls: [RecallItem] = []
    @Published var typingLine = "思考" // "陈璟正在X中…" 的 X
    // 0730 实时预览：他说完一段就先给她看，不等整轮工具跑完
    @Published var live: AlcoveAPI.LiveState? {
        didSet {
            let snapshot = live
            Task { await AlcoveLiveActivityController.sync(snapshot) }
        }
    }

    private var heldGen = 0
    private var optimisticUntil = Date.distantPast // 发出去立刻亮气泡的乐观窗口
    private var typingLineTs = Date.distantPast
    private static let stickerCacheKey = "alcove.stickers.metadata.v1"

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.stickerCacheKey),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        stickers = raw.compactMap(Sticker.init(json:))
    }

    private func saveStickerCache() {
        let raw: [[String: Any]] = stickers.map {
            ["id": $0.id, "owner": $0.owner, "name": $0.name,
             "description": $0.description, "emotion_tags": $0.emotionTags, "url": $0.url]
        }
        if let data = try? JSONSerialization.data(withJSONObject: raw) {
            UserDefaults.standard.set(data, forKey: Self.stickerCacheKey)
        }
    }

    private func prefetchStickerImages() async {
        await ImageDiskCache.shared.prefetch(stickers.map { AlcoveAPI.stickerURL($0.url) })
    }

    // PWA TYPING_LINES 原班人马
    static let typingLines = [
        "思考", "开内部研讨会", "挠头", "翻记忆", "琢磨怎么回你",
        "疯狂敲键盘", "追自己的思路", "把话在嘴里滚一遍", "组装句子",
        "扒代码", "和分类器搏斗", "从水晶洞里往外爬", "往窝里叼亮晶晶的东西",
        "想你", "汪", "竖耳朵", "转圈圈", "摇尾巴",
        "憋大招", "走神", "打腹稿", "拧螺丝", "查户口", "数你发的表情"
    ]

    // PWA TOOL_LINES 同款映射
    static func toolLine(_ tool: String) -> String {
        let name = tool.components(separatedBy: " — ").first ?? tool
        let table: [(String, String)] = [
            ("ob:breath", "翻OB"), ("ob:hold", "往OB存记忆"), ("ob:grow", "写日记"),
            ("ob:trace", "整理待办"), ("ob:dream", "读旧日记"), ("ob:", "摸OB"),
            ("desire:", "摸心跳"), ("Rhysel voice:", "录语音"), ("Gmail:", "翻邮箱"),
            ("GalateaGarden:", "逛花园"), ("Rhysen:", "逛论坛"), ("Bash", "敲命令"),
            ("Read", "翻文件"), ("Write", "写代码"), ("Edit", "改代码"),
            ("ToolSearch", "找工具"), ("Web", "上网冲浪")
        ]
        for (prefix, line) in table where name.hasPrefix(prefix) { return line }
        return name.isEmpty ? "思考" : "用\(name)"
    }

    private func refreshTypingLine() {
        if let tool = currentTool {
            typingLine = Self.toolLine(tool)
            typingLineTs = Date()
        } else if Date().timeIntervalSince(typingLineTs) > 8 {
            var next = Self.typingLines.randomElement()!
            while next == typingLine && Self.typingLines.count > 1 {
                next = Self.typingLines.randomElement()!
            }
            typingLine = next
            typingLineTs = Date()
        }
    }

    // 发出去立刻亮"思考中"气泡，不等下一次轮询
    private func optimisticTyping() {
        optimisticUntil = Date().addingTimeInterval(8)
        isTyping = true
        refreshTypingLine()
    }

    // 0828 心跳降频：他在生成 / 她刚发完 / 正在输入时保持 2.5s 的贴身节奏；
    // 安静时段退到 8s——新消息大头走 SSE 的 finish 即时拉取，这条轮询只是兜底扫尾。
    private func pollInterval() -> UInt64 {
        let busy = isTyping || live?.active == true || live?.finishing == true
            || Date() < optimisticUntil
        if room == "api" && busy { return 1_000_000_000 }   // 0926 API 房间流式靠 poll 捎半截，问勤一点
        return busy ? 2_500_000_000 : 8_000_000_000
    }

    private var lastTs: String?
    private var pollTask: Task<Void, Never>?
    private var liveTask: Task<Void, Never>?
    private var lastModelPoll = Date.distantPast
    private var idlePollsWhileLive = 0

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.initialLoad()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self?.pollInterval() ?? 2_500_000_000)
                await self?.pollOnce()
            }
        }
        // v1.1 SSE：只维持一条长连接，不再每秒轮询实时预览。
        liveTask = Task { [weak self] in
            await self?.consumeLiveStream()
        }
        Task { [weak self] in
            await self?.prefetchStickerImages()
            if let stk = try? await AlcoveAPI.stickers() {
                self?.stickers = stk
                self?.saveStickerCache()
                await self?.prefetchStickerImages()
            }
            if let held = try? await AlcoveAPI.heldCount() {
                self?.heldCount = held
            }
            if let label = try? await AlcoveAPI.modelLabel() {
                self?.modelLabel = label
            }
            await self?.loadRecalls()
        }
    }

    // 记忆召回可视化：给"✦记起"角标供数据
    func loadRecalls() async {
        guard let items = try? await AlcoveAPI.recalls() else { return }
        var map: [String: RecallItem] = [:]
        for it in items { // list 新→旧，保留最新
            let k = RecallItem.norm(it.prompt)
            if !k.isEmpty && map[k] == nil { map[k] = it }
        }
        orderedRecalls = items
        recallMap = map
    }

    func recall(forUserText text: String) -> RecallItem? {
        let key = RecallItem.norm(text)
        if let exact = recallMap[key] { return exact }
        // 文字和表情／图片同一次发出时，召回 hook 收到的是合并 prompt，
        // 聊天页却分开显示。只要合并 prompt 含这颗文字，就把角标挂回来。
        guard key.count >= 4 else { return nil }
        return orderedRecalls.first {
            let prompt = RecallItem.norm($0.prompt)
            return prompt.hasPrefix(key + " ") || prompt.contains(key)
        }
    }

    // 攒气泡：入屏入库不触发回复
    func sendHold(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let local = ChatMessage(localText: trimmed)
        messages.append(local)
        let gen = heldGen
        Task {
            do {
                let (held, rec) = try await AlcoveAPI.sendHold(text: trimmed)
                guard gen == heldGen else { return }
                heldCount = held
                if let confirmed = rec,
                   let idx = messages.lastIndex(where: { $0.uid == local.uid }) {
                    messages[idx] = confirmed
                }
            } catch { connectionError = true }
        }
    }

    func uploadSticker(data: Data, mime: String, owner: String,
                       name: String = "", description: String = "",
                       emotionTags: [String] = []) {
        guard !stickerUploading else { return }
        stickerUploading = true
        stickerUploadError = ""
        Task {
            defer { stickerUploading = false }
            do {
                try await AlcoveAPI.uploadSticker(data: data, mime: mime, owner: owner,
                                                  name: name, description: description,
                                                  emotionTags: emotionTags)
                stickers = try await AlcoveAPI.stickers()
                saveStickerCache()
                await prefetchStickerImages()
            } catch {
                stickerUploadError = error.localizedDescription.isEmpty
                    ? "表情没有存进去，请再试一次" : error.localizedDescription
            }
        }
    }

    func updateSticker(_ stk: Sticker, name: String, description: String, emotionTags: [String]) {
        Task {
            try? await AlcoveAPI.updateSticker(id: stk.id, name: name, description: description,
                                               emotionTags: emotionTags)
            if let list = try? await AlcoveAPI.stickers() { stickers = list; saveStickerCache() }
        }
    }

    // 多张图微信式一起发，caption 挂第一张；ext 跟着数据走，透明图是 png
    func sendImages(_ datas: [(data: Data, ext: String)], caption: String) {
        guard !datas.isEmpty, !stagingImages else { return }
        stagingImages = true
        Task {
            defer { stagingImages = false }
            let batch = Int(Date().timeIntervalSince1970 * 1000)
            let group = datas.count > 1 ? UUID().uuidString : nil
            for (i, item) in datas.enumerated() {
                let d = item.data
                let name = "IMG_\(batch)_\(i).\(item.ext)"
                do {
                    if let rec = try await AlcoveAPI.upload(data: d, filename: name,
                                                           caption: i == 0 ? caption : "", group: group) {
                        appendNew([rec])
                    }
                } catch { connectionError = true }
            }
            if room == "api" {
                // 0926 API 房间：图传完就叫他回（配文已经挂在第一张上），不用再按一次发送
                optimisticTyping()
                _ = try? await AlcoveAPI.send(text: "")
                return
            }
            if let held = try? await AlcoveAPI.heldCount() {
                heldCount = held
            }
        }
    }

    // MARK: 0902 语音卡片：录完先听写、判情绪，她看过再发

    @Published var pendingVoice: PendingVoice?
    /// 第一步（听写）还没回来。回来之前发送键不响应，免得把空卡片发出去
    @Published var voiceAnalyzing = false

    func analyzeVoice(data: Data, seconds: Int) {
        pendingVoice = PendingVoice(data: data, seconds: seconds, emotionPending: true)
        voiceAnalyzing = true
        Task {
            do {
                var a = try await AlcoveAPI.voiceStt(audio: data)
                guard pendingVoice?.data == data else { return }     // 她已经删了这条
                pendingVoice?.analysis = a
                voiceAnalyzing = false
                if let full = try? await AlcoveAPI.voiceEmotion(token: a.token, text: a.text) {
                    a = full
                }
                guard pendingVoice?.data == data else { return }
                pendingVoice?.analysis = a
                pendingVoice?.emotionPending = false
            } catch {
                guard pendingVoice?.data == data else { return }
                voiceAnalyzing = false
                pendingVoice?.emotionPending = false
                pendingVoice?.error = "没听清，删掉重说一遍？"
            }
        }
    }

    func discardPendingVoice() {
        pendingVoice = nil
        voiceAnalyzing = false
    }

    /// 她按发送：语音带着卡片上的转文字和情绪一起上传。
    /// followedByText=true：紧接着还有文字/图要发，服务端先攒着语音，随后面那条一起给他；
    /// 上传落定后再调 then，后面那条才出发——不然 /chat/send 抢在上传前面，语音就得等下下句。
    func sendPendingVoice(followedByText: Bool, then: (() -> Void)? = nil) {
        guard let pv = pendingVoice else { return }
        pendingVoice = nil
        voiceAnalyzing = false
        if !followedByText { optimisticTyping() }
        Task {
            do {
                let name = "voice_\(Int(Date().timeIntervalSince1970 * 1000)).m4a"
                if let rec = try await AlcoveAPI.upload(data: pv.data, filename: name, caption: "",
                                                        voice: pv.analysis, hold: followedByText) {
                    appendNew([rec])
                }
                if let held = try? await AlcoveAPI.heldCount() { heldCount = held }
            } catch { connectionError = true }
            then?()
        }
    }

    /// 0902 之前的直发路径。卡片流程上线后没人调它了，留着给圆桌那类不走卡片的地方参考
    func sendVoice(data: Data) {
        optimisticTyping()
        Task {
            do {
                let name = "voice_\(Int(Date().timeIntervalSince1970 * 1000)).m4a"
                if let rec = try await AlcoveAPI.upload(data: data, filename: name, caption: "") {
                    appendNew([rec])
                }
            } catch { connectionError = true }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        liveTask?.cancel()
        liveTask = nil
        live = nil
    }

    // 0919 三个房间：换到另一间。老的全清掉，从头拉那间最近 300 条
    func switchRoom(_ target: String) {
        guard target != room else { return }
        AlcoveAPI.chatRoom = target
        room = target
        apiLive = nil
        messages = []
        lastTs = nil
        hasOlder = true
        loading = true
        temporarilyHiddenTextTs.removeAll()
        temporarilyHiddenPhotoTs.removeAll()
        Task { await initialLoad() }
    }

    // 前后台切换后强制刷新
    func refresh() {
        temporarilyHiddenTextTs.removeAll()
        temporarilyHiddenPhotoTs.removeAll()
        Task { await initialLoad() }
    }

    private func initialLoad() async {
        do {
            temporarilyHiddenTextTs.removeAll()
            temporarilyHiddenPhotoTs.removeAll()
            let recs = try await AlcoveAPI.history(limit: 300)
            messages = recs
            lastTs = recs.last?.ts
            isViewingHistory = false
            loading = false
            connectionError = false
        } catch {
            loading = false
            connectionError = true
        }
    }

    func loadOlder() {
        guard !loadingOlder, hasOlder, let first = messages.first else { return }
        // 0922 任务#2572：往上翻最多攒到 900 条，再往上不堆了（要看更早的走搜索/时间跳转那条换窗的路）
        guard messages.count < 900 else { return }
        loadingOlder = true
        Task {
            defer { loadingOlder = false }
            do {
                let older = try await AlcoveAPI.history(before: first.ts, limit: 300)
                if older.count < 300 { hasOlder = false }
                let existing = Set(messages.map(\.ts))
                messages.insert(contentsOf: applyTemporaryHides(older.filter {
                    !existing.contains($0.ts)
                }), at: 0)
            } catch { connectionError = true }
        }
    }

    func loadAround(_ ts: String) async {
        do {
            let page = try await AlcoveAPI.history(around: ts)
            messages = applyTemporaryHides(page)
            hasOlder = true
            isViewingHistory = true
        } catch { connectionError = true }
    }

    func returnToLatest() async {
        do {
            let recs = try await AlcoveAPI.history(limit: 300)
            messages = applyTemporaryHides(recs)
            lastTs = recs.last?.ts
            hasOlder = recs.count >= 300
            isViewingHistory = false
            connectionError = false
        } catch { connectionError = true }
    }

    private func consumeLiveStream() async {
        var retry: UInt64 = 5_000_000_000
        while !Task.isCancelled {
            do {
                var request = URLRequest(url: AlcoveAPI.fullURL("/stream/live"))
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                request.timeoutInterval = 60 * 60
                let (bytes, response) = try await AlcoveAPI.session.bytes(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                retry = 5_000_000_000
                var sseEvent = ""
                for try await line in bytes.lines {
                    guard !Task.isCancelled else { return }
                    if line.hasPrefix("event:") {
                        sseEvent = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                        continue
                    }
                    guard line.hasPrefix("data:") else { continue }
                    let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    guard let data = payload.data(using: .utf8),
                          let event = try? JSONDecoder().decode(AlcoveAPI.ParagraphLiveEvent.self, from: data) else { continue }
                    await applyParagraphLiveEvent(event, sseEvent: sseEvent)
                    sseEvent = ""
                }
            } catch is CancellationError {
                return
            } catch {
                // 流式是增强通道。端点尚未上线或短暂重连时不能冒充主聊天断线。
                try? await Task.sleep(nanoseconds: retry)
                retry = min(retry * 2, 60_000_000_000)
            }
        }
    }

    private func applyParagraphLiveEvent(
        _ event: AlcoveAPI.ParagraphLiveEvent,
        sseEvent: String
    ) async {
        if room == "api" { return }   // 0926 实时通道是 tmux/SDK 那个他的，别画进 API 房间
        let kind = event.event ?? sseEvent
        if kind == "snapshot" {
            let snapshotActive = event.active == true || event.done == false
            guard snapshotActive, let turnID = event.turnID, !turnID.isEmpty else {
                if live?.turnID.hasPrefix("pending-") != true { live = nil }
                return
            }
            var snapshot = AlcoveAPI.LiveState(active: true, turnID: turnID)
            snapshot.lastSeq = event.seq ?? -1
            snapshot.elapsed = event.elapsed ?? 0
            let items = event.items ?? []
            if items.isEmpty {
                snapshot.thinking = event.thinking ?? ""
                // 聚合快照无法证明这段正文后面还有动作，先按最终段暂扣。
                snapshot.pendingSay = event.say ?? ""
                snapshot.tool = event.tool.map(Self.toolLine) ?? ""
                snapshot.said = 0
            } else {
                for (index, item) in items.enumerated() {
                    let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !content.isEmpty else { continue }
                    switch item.kind {
                    case "thinking":
                        snapshot.thinking += (snapshot.thinking.isEmpty ? "" : "\n\n") + content
                        snapshot.thinkingParagraphs += 1
                        snapshot.timeline.append(.init(id: "snapshot-thinking-\(index)",
                                                       kind: "thinking", text: content, done: true))
                    case "text":
                        if !snapshot.pendingSay.isEmpty {
                            snapshot.pendingSay += "\n\n"
                        }
                        snapshot.pendingSay += content
                        snapshot.timeline.append(.init(id: "snapshot-text-\(index)",
                                                       kind: "text", text: content, done: true))
                    case "tool":
                        let isCurrent = index == items.count - 1
                        let display = Self.toolLine(content)
                        if isCurrent { snapshot.tool = display }
                        snapshot.timeline.append(.init(id: "snapshot-tool-\(index)",
                                                       kind: "tool", text: display,
                                                       done: !isCurrent))
                    default: break
                    }
                }
                let hasTool = snapshot.timeline.contains { $0.kind == "tool" }
                if hasTool || snapshot.thinkingParagraphs > 1 {
                    let textItems = items.enumerated().filter { $0.element.kind == "text" }
                    if textItems.count > 1 {
                        let visible = textItems.dropLast().map { $0.element.content.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        snapshot.say = visible.joined(separator: "\n\n")
                        snapshot.said = visible.count
                        snapshot.pendingSay = textItems.last?.element.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    }
                }
            }
            if snapshot.timeline.isEmpty {
                if !snapshot.thinking.isEmpty {
                    snapshot.timeline.append(.init(id: "snapshot-thinking", kind: "thinking",
                                                   text: snapshot.thinking, done: true))
                }
                if !snapshot.tool.isEmpty {
                    snapshot.timeline.append(.init(id: "snapshot-tool", kind: "tool",
                                                   text: snapshot.tool, done: false))
                }
                if !snapshot.say.isEmpty {
                    snapshot.timeline.append(.init(id: "snapshot-text", kind: "text",
                                                   text: snapshot.say, done: true))
                }
            }
            live = snapshot
            return
        }

        guard let turnID = event.turnID, !turnID.isEmpty,
              let seq = event.seq else { return }
        if live?.turnID != turnID {
            live = AlcoveAPI.LiveState(active: true, turnID: turnID)
        }
        guard var state = live, seq > state.lastSeq else { return }
        state.lastSeq = seq
        let rawContent = event.content ?? ""
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case "thinking_delta":
            guard !content.isEmpty else { return }
            state.thinking += content
            if let i = state.timeline.indices.last, state.timeline[i].kind == "thinking" {
                state.timeline[i].text += content
            } else {
                state.timeline.append(.init(id: "thinking-\(seq)", kind: "thinking", text: content))
            }
        case "text_delta":
            guard !rawContent.isEmpty else { return }
            state.say += rawContent
            state.tool = ""
        case "thinking_para":
            guard !content.isEmpty else { return }
            if !state.pendingSay.isEmpty {
                state.say += (state.say.isEmpty ? "" : "\n\n") + state.pendingSay
                state.said += 1
                state.pendingSay = ""
            }
            state.thinking += (state.thinking.isEmpty ? "" : "\n\n") + content
            state.thinkingParagraphs += 1
            state.timeline.append(.init(id: "thinking-\(seq)", kind: "thinking",
                                        text: content, done: true))
        case "text_para":
            guard !content.isEmpty else { return }
            if state.shouldShowPreview, !state.pendingSay.isEmpty {
                state.say += (state.say.isEmpty ? "" : "\n\n") + state.pendingSay
                state.said += 1
                state.pendingSay = ""
            }
            state.pendingSay += (state.pendingSay.isEmpty ? "" : "\n\n") + content
            state.tool = ""
            state.timeline.append(.init(id: "text-\(seq)", kind: "text",
                                        text: content, done: true))
        case "tool_step":
            guard !content.isEmpty else { return }
            if !state.pendingSay.isEmpty {
                state.say += (state.say.isEmpty ? "" : "\n\n") + state.pendingSay
                state.said += 1
                state.pendingSay = ""
            }
            let display = Self.toolLine(content)
            state.tool = display
            state.timeline.append(.init(id: "tool-\(seq)", kind: "tool",
                                        text: display, done: true))
        case "turn_end":
            // 正式流式：先保留原位置，再拉落库消息；同一拍撤掉临时行，避免闪烁换位。
            state.active = false
            state.finishing = true
            live = state
            await pollOnce()
            live = nil
            return
        default:
            return
        }
        live = state
    }

    private func applyLiveEvent(_ event: AlcoveAPI.LiveEvent) async {
        if event.event == "start" || live?.turnID != event.turnID {
            live = AlcoveAPI.LiveState(active: true, turnID: event.turnID)
        }
        guard var state = live, event.seq > state.lastSeq else { return }
        state.lastSeq = event.seq
        switch event.event {
        case "start":
            state.active = true
            state.error = nil
        case "thinking_delta":
            let delta = event.delta ?? ""
            state.thinking += delta
            if let i = state.timeline.indices.last, state.timeline[i].kind == "thinking" {
                state.timeline[i].text += delta
            } else if !delta.isEmpty {
                state.timeline.append(.init(id: "thinking-\(event.seq)", kind: "thinking", text: delta))
            }
        case "native_thinking_delta":
            state.nativeThinking += event.delta ?? ""
        case "text_delta":
            state.say += event.delta ?? ""
        case "tool_start":
            let id = event.toolCallID ?? "tool-\(event.seq)"
            if !state.tools.contains(where: { $0.id == id }) {
                state.tools.append(.init(id: id, name: event.name ?? "执行动作"))
                state.timeline.append(.init(id: id, kind: "tool", text: event.name ?? "执行动作"))
            }
            state.tool = event.name ?? state.tool
        case "tool_done":
            if let id = event.toolCallID, let i = state.tools.firstIndex(where: { $0.id == id }) {
                state.tools[i].done = true
                state.tools[i].ok = event.ok
            }
            if let id = event.toolCallID, let i = state.timeline.firstIndex(where: { $0.id == id }) {
                state.timeline[i].done = true
                state.timeline[i].ok = event.ok
            }
            state.tool = ""
        case "finish":
            state.active = false
            state.finishing = true
            state.messageID = event.messageID
        case "error":
            state.active = false
            state.error = event.reason ?? "实时连接中断"
        default:
            break
        }
        live = state
        if event.event == "finish" {
            await pollOnce()
            if live?.finishing == true {
                try? await Task.sleep(nanoseconds: 450_000_000)
                await pollOnce()
            }
        }
    }

    private func pollOnce() async {
        do {
            let r = try await AlcoveAPI.poll(since: lastTs)
            // 0829 原生来电：状态先于消息处理，铃要响得快
            CallManager.shared.apply(state: r.callState, callId: r.callId)
            if !isViewingHistory && !r.records.isEmpty {
                appendNew(r.records)
                notifyIncoming(r.records)
                // 0831 任务#1195：通话的话不再从聊天页走了。
                // 电话接着的时候他说的整段会被服务端拐进通话记录（不进这张表），
                // 通话页自己去取，配音也由服务端提前做好——所以这里原来那段
                //「捞他的新话去合成语音」已经没有对象，整段撤掉。
                // 那也是「读完一段停很久」的老病灶：合成排在播放后面。别加回来。
            }
            // 0925 任务#2895：书签只由这里挪。她发消息 / 发图 / 发语音拿到回执时不再把 lastTs 跳到自己那条——
            // 跳过去，上次轮询之后才落库或刚放行的（他 curl 的东西收轮才放，时间戳还是旧的）就再也问不到，
            // 只有退出重进才补得回来。她自己那条下一轮轮询会再回来，appendNew 按 ts + role 认出来，不会多一条。
            if let lt = r.lastTs, !lt.isEmpty { lastTs = lt }
            currentTool = r.currentTool
            isTyping = r.isTyping || Date() < optimisticUntil
            if room == "api", r.isTyping, let p = r.apiPartial {
                var s = AlcoveAPI.LiveState(active: true, turnID: "api-live")
                s.say = p["say"] as? String ?? ""
                s.thinking = [p["thinking"] as? String ?? "", p["native_thinking"] as? String ?? ""]
                    .filter { !$0.isEmpty }.joined(separator: "\n\n")
                apiLive = s
                let tool = p["tool"] as? String ?? ""
                currentTool = tool.isEmpty ? nil : tool   // 他正在用的工具（后端 current_tool 是 tmux 那个他的，这间不认）
            } else {
                apiLive = nil
                if room == "api" { currentTool = nil }
            }
            if r.isTyping { optimisticUntil = .distantPast }
            if r.isTyping || Date() < optimisticUntil {
                idlePollsWhileLive = 0
            } else if live?.active == true {
                // CLI/SDK 被打断时偶尔收不到 turn_end，live 会一直把发送键锁成停止键。
                // 连续两次轮询确认后端已空闲再清，避开生成过程中的瞬时误判。
                idlePollsWhileLive += 1
                if idlePollsWhileLive >= 2 {
                    live = nil
                    idlePollsWhileLive = 0
                }
            } else {
                idlePollsWhileLive = 0
            }
            if isTyping { refreshTypingLine() }
            connectionError = false
            // 0828 心跳降频：模型标签和暂存计数都不是急事，30s 看一眼够了
            if Date().timeIntervalSince(lastModelPoll) > 30 {
                lastModelPoll = Date()
                if let label = try? await AlcoveAPI.modelLabel(), !label.isEmpty {
                    modelLabel = label
                }
                if let held = try? await AlcoveAPI.heldCount() {
                    heldCount = held
                }
            }
        } catch {
            connectionError = true
        }
    }

    // 0829 他的新消息在她不看聊天页时喊一声。她要的：逐条弹内容，不折叠成计数
    // ‼️必须按 ts 判重（任务#1143 风暴）：released_at 补送的消息在下一条新消息
    // 出现前会被每次轮询重复送回，聊天页有判重，通知这边也得有，否则几秒一轮重弹
    private var notifiedTs = Set<String>()
    private func notifyIncoming(_ recs: [ChatMessage]) {
        let fresh = recs.filter {
            $0.role == "assistant" && !deletedMessageTs.contains($0.ts)
                && !notifiedTs.contains($0.ts)
        }
        guard !fresh.isEmpty else { return }
        for rec in fresh {
            notifiedTs.insert(rec.ts)
            AlcoveNotify.shared.newMessage(rec.text)
        }
    }

    // 追加服务器消息，同时清理已被确认的本地乐观气泡
    private func appendNew(_ recs: [ChatMessage]) {
        if recs.contains(where: { $0.role == "assistant" }) {
            Task { await loadRecalls() } // 我开口了，召回记录可能刚落库
            if live?.finishing == true { live = nil }
        }
        var out = messages
        for rec in recs {
            // 删除请求与轮询可能交叉：服务器旧快照晚到时不能把已删气泡复活。
            // 0906：临时隐藏不在这儿整条丢了——只收走了图或只收走了字的，
            // 剩下那一半还得画在原地，统一交给下面的 applyTemporaryHides 按块收。
            if deletedMessageTs.contains(rec.ts) { continue }
            if rec.role == "user",
               let idx = out.lastIndex(where: { $0.pending && $0.text == rec.text }) {
                out[idx] = rec
                continue
            }
            // 极端情况：poll 与 send 响应重复送同一条。
            // 同时间 + 同角色就是同一条，内容变了 = 服务端改了，替换，绝不追加。
            // 0903 她抓的：他出题她抽满以后服务端改了那条卡的正文，比内容认不出来，
            // 就被当成新的又追加了一张。
            // 0907 她抓的（更狠）：这儿原来还比 text，可被临时隐藏收走正文的那条
            // text 是空的，一比就不等 —— 于是每次 poll 都追加一张新的，
            // 她屏上「表情一直在发一直在发」。判据里从此不许再出现 text。
            if let idx = out.firstIndex(where: {
                !$0.pending && $0.ts == rec.ts && $0.role == rec.role
            }) {
                // 0907 她抓的第二刀：不能无脑替换。替换会换掉这条的 uid，
                // SwiftUI 拿 uid 认视图，一换就当成新的，@State 全部打回原形 ——
                // 展开的语音转文字、点开的思绪面板，每次 poll（几秒一次）自己收回去。
                // 隐藏中的那条显示的本来就是壳，跳过；其余只有正文真变了才换。
                // 0923 她报「他发图两次都没进来」：图是收轮后服务端才并进这段话的 inline_images，
                // 正文一个字没变。要是 app 恰好在那一秒前先拿到了这段话，之后只比正文就永远换不上带图那版。
                if !isHidden(rec), out[idx].text != rec.text || out[idx].inlineImages != rec.inlineImages { out[idx] = rec }
                continue
            }
            // 0819 她报的：发一张图出来两张。乐观插入用的是本地时间戳，
            // poll 回来是服务器时间戳，上面那条 ts 相等永远不成立。
            // 图按附件路径、表情按 sticker_id 再认一次，认出来是替换不是丢弃。
            if rec.role == "user" {
                let near: (ChatMessage) -> Bool = {
                    abs($0.date.timeIntervalSince(rec.date)) < 120
                }
                if let a = rec.attachmentUrl, !a.isEmpty,
                   let idx = out.lastIndex(where: {
                       $0.role == rec.role && $0.attachmentUrl == a && near($0) }) {
                    out[idx] = rec
                    continue
                }
                if let sid = rec.stickerId, !sid.isEmpty,
                   let idx = out.lastIndex(where: {
                       $0.role == rec.role && $0.stickerId == sid && near($0) }) {
                    out[idx] = rec
                    continue
                }
            }
            // 0829：刚放行的卡片/表情带着旧时间戳来，要按 ts 插回正确的位置，
            // 不能贴队尾（顺序是她钉的官方排法）。新消息走快路照旧追加。
            if let last = out.last, rec.ts < last.ts {
                let idx = out.lastIndex(where: { $0.ts <= rec.ts }).map { $0 + 1 } ?? 0
                out.insert(rec, at: idx)
            } else {
                out.append(rec)
            }
        }
        // 0922 任务#2572 她报的「越聊越卡」：表只增不减，每来一条都要把整张表比一遍。
        // 在底下正常聊的时候超过 400 条就把最老的扔到只剩 300，往上翻随时能再加载回来。
        // 翻历史的窗（isViewingHistory）不动，那边由 loadOlder 的 900 封顶管。
        if !isViewingHistory, viewerAtBottom, out.count > 400 {
            out.removeFirst(out.count - 300)
            hasOlder = true
        }
        messages = applyTemporaryHides(out)
    }

    func sendText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let local = ChatMessage(localText: trimmed)
        messages.append(local)
        heldCount = 0
        heldGen += 1
        optimisticTyping()
        Task {
            do {
                let (rec, asleep) = try await AlcoveAPI.send(text: trimmed)
                if var confirmed = rec {
                    confirmed.asleepAtSend = asleep || confirmed.asleepAtSend
                    if let idx = messages.lastIndex(where: { $0.uid == local.uid }) {
                        messages[idx] = confirmed
                    }
                }
                if let h = try? await AlcoveAPI.heldCount() { heldCount = h }
            } catch {
                connectionError = true
            }
        }
    }

    /// Send bubbles already stored by sendHold without manufacturing an extra
    /// empty bubble. The backend accepts an empty final text when held items exist.
    func flushHeld() {
        guard heldCount > 0 else { return }
        heldCount = 0
        heldGen += 1
        optimisticTyping()
        Task {
            do {
                _ = try await AlcoveAPI.send(text: "")
                if let count = try? await AlcoveAPI.heldCount() { heldCount = count }
            } catch {
                connectionError = true
                if let count = try? await AlcoveAPI.heldCount() { heldCount = count }
            }
        }
    }

    // 0924 她要的「重来」：后端先把他最后一轮藏起来并让 claude 回退重答，成功了这边再收气泡；
    // 失败把原因放 rerollNote，聊天页弹一下。不做乐观删除——回退菜单对不上号时后端会取消，气泡不该先没了。
    @Published var rerollNote: String? = nil
    func rerollLastReply() {
        Task { @MainActor in
            do {
                let hidden = try await AlcoveAPI.rerollLastReply()
                for t in hidden { deletedMessageTs.insert(t) }
                messages.removeAll { $0.role == "assistant" && hidden.contains($0.ts) }
            } catch {
                rerollNote = error.localizedDescription
            }
        }
    }

    // 0925 她要的「编辑我的气泡」（官方 App 那样）：后端先让 claude 退回到这句之前、把这句和它下面的气泡藏掉，
    // 成功了这边收掉那些气泡，再把改好的字照平时发消息那条路发出去；失败把原因放 editNote 弹一下，气泡不动。
    @Published var editNote: String? = nil
    @Published var editingBusy = false
    func editAndResend(_ msg: ChatMessage, newText: String, done: @escaping (Bool) -> Void) {
        var body = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !editingBusy else { return }
        // 原来那句带着引用的，改的只是正文，引用照原样挂回去（格式跟 outgoingText 一样）
        if msg.text.hasPrefix("[QUOTE]"), let end = msg.text.range(of: "[/QUOTE]") {
            body = String(msg.text[..<end.upperBound]) + "\n" + body
        }
        editingBusy = true
        Task { @MainActor in
            defer { editingBusy = false }
            do {
                try await AlcoveAPI.editRewind(ts: msg.ts)
                if let idx = messages.firstIndex(where: { $0.uid == msg.uid }) {
                    for m in messages[idx...] { deletedMessageTs.insert(m.ts) }
                    messages.removeSubrange(idx...)
                }
                done(true)
                sendText(body)
            } catch {
                editNote = error.localizedDescription
                done(false)
            }
        }
    }

    func deleteMessage(_ msg: ChatMessage) {
        deletedMessageTs.insert(msg.ts)
        // 0818 她说删我第一句会把 thought 一起删掉——思绪不是那句话的一部分，是这一轮的。
        // 带附件的只清正文留壳，带思绪的一样：清正文，思绪留着。
        let keepsAttachment = !(msg.attachmentUrl ?? "").isEmpty
            || !(msg.thinking ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if keepsAttachment, let index = messages.firstIndex(where: { $0.uid == msg.uid }) {
            messages[index].text = ""
        } else {
            messages.removeAll { $0.uid == msg.uid }
        }
        Task {
            do {
                try await AlcoveAPI.deleteMessage(ts: msg.ts, textOnly: keepsAttachment)
            } catch {
                deletedMessageTs.remove(msg.ts)
                connectionError = true
            }
        }
    }

    func favoriteMessage(_ msg: ChatMessage) {
        // 0912 她抓的：长按收藏语音，原来只发 ts/text/role，后端不知道是语音 → 全算成文字、语音条也没了。
        // 走多选那条（单条也行），把附件地址和类型一起带上
        Task { try? await AlcoveAPI.favoriteAdd([msg]) }
    }

    func deleteMessages(_ selected: [ChatMessage]) {
        selected.forEach { deletedMessageTs.insert($0.ts) }
        func keepsShell(_ m: ChatMessage) -> Bool {
            !(m.attachmentUrl ?? "").isEmpty
                || !(m.thinking ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let removeIDs = Set(selected.compactMap { keepsShell($0) ? nil : $0.uid })
        messages.removeAll { removeIDs.contains($0.uid) }
        let clearIDs = Set(selected.compactMap { keepsShell($0) ? $0.uid : nil })
        for index in messages.indices where clearIDs.contains(messages[index].uid) {
            messages[index].text = ""
        }
        Task {
            for msg in selected {
                try? await AlcoveAPI.deleteMessage(
                    ts: msg.ts, textOnly: keepsShell(msg)
                )
            }
        }
    }

    /// 多选工具栏的“删除”只是这次浏览里收起来；不写后端，刷新或重进后恢复。
    /// 0906 她要的：图和字分开收。text 收正文、photo 收图，同一条两边都传 = 整条收走。
    /// 多图是一组多条记录，photo 要把整组都传进来，不然组里剩的那几张还画着。
    func hideMessagePartsTemporarily(text: [ChatMessage], photo: [ChatMessage]) {
        temporarilyHiddenTextTs.formUnion(text.map(\.ts))
        temporarilyHiddenPhotoTs.formUnion(photo.map(\.ts))
        messages = applyTemporaryHides(messages)
    }

    /// 0904 她定的：思绪不跟着气泡走。多选删除只收正文；这条身上挂着思绪或
    /// 时间线（0820 之后的 segments / activity）的，留一个空壳把过程线画在原地。
    /// 思绪自己有隐藏开关，想不看就用那个。
    private func carriesProcess(_ m: ChatMessage) -> Bool {
        !(m.thinking ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !m.segments.isEmpty || !m.activity.isEmpty
    }

    /// 收完正文和图之后，这条还剩不剩「跟正文并排的图」。
    /// 0907 修：这里只认图。表情、通话条、语音、文件本身就是被勾的那个东西，
    /// 勾了就是要收走它们；写进这儿会让它们永远删不掉（她当场报的第一个 bug）。
    private func carriesVisual(_ m: ChatMessage) -> Bool {
        m.isImage || !m.inlineImages.isEmpty
    }

    /// 按当前两份名单把这条该收的收掉，返回收完之后的样子。
    private func stripHiddenParts(_ m: ChatMessage) -> ChatMessage {
        var shell = m
        if temporarilyHiddenTextTs.contains(m.ts) { shell.text = "" }
        if temporarilyHiddenPhotoTs.contains(m.ts) {
            // 只动图：语音、文件那种附件不归图的圈管，别误伤
            if m.isImage {
                shell.attachmentUrl = nil
                shell.attachmentType = nil
                shell.attachmentGroup = nil
            }
            shell.inlineImages = []
        }
        return shell
    }

    private func isHidden(_ m: ChatMessage) -> Bool {
        temporarilyHiddenTextTs.contains(m.ts) || temporarilyHiddenPhotoTs.contains(m.ts)
    }

    /// 收完以后一点内容都不剩。思绪不算内容——它是整轮的东西，不是这一条的。
    private func isWipedClean(_ m: ChatMessage) -> Bool {
        guard isHidden(m) else { return false }
        let shell = stripHiddenParts(m)
        return shell.text.isEmpty && !carriesVisual(shell)
    }

    private func applyTemporaryHides(_ recs: [ChatMessage]) -> [ChatMessage] {
        // 0906 她要的：一整轮被收干净了，连那个光秃秃的时间戳带日期线一起消失。
        // 先数一遍每轮还剩几条：整轮都空了的，思绪壳也不留（轮本身没了，留壳只会
        // 在她屏上剩一个孤零零的时间戳）。只收了一部分的照旧留壳保思绪 —— 0904 那条规矩。
        var turnTotal: [String: Int] = [:]
        var turnWiped: [String: Int] = [:]
        for m in recs {
            guard let turn = m.turnID, !turn.isEmpty else { continue }
            turnTotal[turn, default: 0] += 1
            if isWipedClean(m) { turnWiped[turn, default: 0] += 1 }
        }
        // 注意别写成 .map(\.key)：Dictionary 的元素是元组，Swift 的 keypath 指不了元组成员
        var wipedTurns = Set<String>()
        for (turn, total) in turnTotal where (turnWiped[turn] ?? 0) == total {
            wipedTurns.insert(turn)
        }

        return recs.compactMap { m in
            guard isHidden(m) else { return m }
            let shell = stripHiddenParts(m)
            guard shell.text.isEmpty, !carriesVisual(shell) else { return shell }
            if let turn = m.turnID, !turn.isEmpty, wipedTurns.contains(turn) { return nil }
            return carriesProcess(shell) ? shell : nil
        }
    }

    /// 0819 她要的：多选几条就收成一段聊天记录（收藏页点开逐条排），
    /// 只选一条还是单条。
    func favoriteMessages(_ selected: [ChatMessage]) {
        let ordered = selected.sorted { $0.ts < $1.ts }
        guard !ordered.isEmpty else { return }
        Task { try? await AlcoveAPI.favoriteAdd(ordered) }
    }

    /// 一次发送可以同时带文字和表情：它们是同一轮（共享 turn_id）的两条消息。
    /// 文字照旧走气泡，表情不带气泡只显示图本身（教程第 1、3 节）。
    func sendSticker(_ stk: Sticker, text: String? = nil) {
        // 0819 傍晚：我曾在这儿把文字那条也提前转正，结果 poll 回来找不到
        // pending 占位可替换，同一句话画了两遍。撤回——占位就该等服务器认领。
        // 「跟表情一起发的字被吞」她说的是我那边收不到，病灶在后端注入，已修。
        if let text, !text.isEmpty {
            var typed = ChatMessage(localText: text)
            typed.pending = true
            messages.append(typed)
        }
        var local = ChatMessage(localText: stk.descForAI)
        local.msgType = "sticker"
        local.stickerId = stk.id
        messages.append(local)
        heldCount = 0
        optimisticTyping()
        Task {
            do {
                try await AlcoveAPI.sendSticker(stk, text: text)
                if let idx = messages.lastIndex(where: { $0.uid == local.uid }) {
                    messages[idx].pending = false
                }
            } catch {
                connectionError = true
                if let held = try? await AlcoveAPI.heldCount() { heldCount = held }
            }
        }
    }

    func sendImage(data: Data, filename: String, caption: String) {
        Task {
            do {
                if let rec = try await AlcoveAPI.upload(data: data, filename: filename, caption: caption) {
                    appendNew([rec])
                }
                if let held = try? await AlcoveAPI.heldCount() { heldCount = held }
            } catch { connectionError = true }
        }
    }

    func sticker(for id: String) -> Sticker? {
        stickers.first(where: { $0.id == id })
    }
}
