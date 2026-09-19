import Foundation

// Alcove 后端网络层。所有请求走 https://alcove.ob-memory.uk，
// 鉴权由服务端代理层注入，客户端无需登录态。
enum AlcoveAPI {
    static let base = URL(string: "https://alcove.ob-memory.uk")!

    static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 35
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    /// ISO-8601 timestamps contain `+08:00`. `urlQueryAllowed` leaves `+`
    /// untouched, but form-style query decoders read it as a space. Exclude the
    /// query separators explicitly so exact history lookups survive the trip.
    private static func timestampQueryValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    struct PollResult {
        var records: [ChatMessage]
        var lastTs: String?
        var isTyping: Bool
        var currentTool: String?
        // 0829 原生来电：poll 捎带的通话状态（idle/ringing/accepted/declined）
        var callState: String = "idle"
        var callId: String = ""
    }

    // 0730 实时预览：他一说完一段就先给她看，不等整轮工具跑完。
    // 数据来自服务器上 stream_watcher 盯 transcript，永不落库（手册K）。
    struct LiveState: Equatable {
        var active: Bool = false
        var turnID: String = ""
        var lastSeq: Int = -1
        var thinking: String = ""
        var nativeThinking: String = ""
        var say: String = ""
        // 最新正文先扣住：后续还有动作时才证明它不是最终答案。
        var pendingSay: String = ""
        var tool: String = ""
        var tools: [LiveTool] = []
        var timeline: [LiveProcessItem] = []
        var said: Int = 0
        var thinkingParagraphs: Int = 0
        var elapsed: Int = 0
        var error: String?
        var finishing: Bool = false
        var messageID: String?

        var isEmpty: Bool {
            say.isEmpty && thinking.isEmpty && nativeThinking.isEmpty && tools.isEmpty && error == nil
        }

        var shouldShowPreview: Bool {
            let hasTool = !tool.isEmpty || timeline.contains { $0.kind == "tool" }
            let hasProcess = hasTool || thinkingParagraphs > 1
            return hasProcess && (!thinking.isEmpty || !say.isEmpty || hasTool)
        }
    }

    struct LiveTool: Identifiable, Equatable {
        let id: String
        var name: String
        var done: Bool = false
        var ok: Bool?
    }

    struct LiveProcessItem: Identifiable, Equatable {
        let id: String
        var kind: String
        var text: String
        var done: Bool = false
        var ok: Bool?

        var icon: String {
            guard kind == "tool" else { return "quote.bubble" }
            // 实时预览那条带子跟落库的轨迹用同一套词（tool_names.py），图标也同一套
            let c = text
            if c.contains("记忆") || c.contains("OB") || c.contains("记了一笔") || c.contains("备忘") { return "brain.head.profile" }
            if c.contains("日记") || c.contains("信") || c.contains("情书") { return "book.closed" }
            if c.contains("图") || c.contains("截") || c.contains("相册") || c.contains("表情") || c.contains("照片") { return "photo" }
            if c.contains("语音") { return "waveform" }
            if c.contains("网页") || c.contains("搜") || c.contains("浏览器") || c.contains("小红书") || c.contains("标签") { return "globe" }
            if c.contains("花园") || c.contains("论坛") || c.contains("社区") || c.contains("帖") || c.contains("漂流瓶") { return "leaf" }
            if c.contains("丧尸") || c.contains("桌游") || c.contains("大富翁") || c.contains("牌") || c.contains("骰") || c.contains("beside you") { return "gamecontroller" }
            if c.contains("小镇") || c.contains("乌有乡") || c.contains("明信片") || c.contains("走") || c.contains("门") || c.contains("小院") { return "map" }
            if c.contains("提交") || c.contains("代码") { return "chevron.left.forwardslash.chevron.right" }
            if c.contains("服务") || c.contains("机器") || c.contains("容器") { return "gearshape" }
            if c.contains("接口") || c.contains("消息") || c.contains("聊天") || c.contains("工作室") { return "antenna.radiowaves.left.and.right" }
            if c.contains("文件") || c.contains("文档") || c.contains("PDF") { return "doc.text" }
            if c.contains("脚本") || c.contains("命令") || c.contains("终端") || c.contains("测试") { return "terminal" }
            if c.contains("旅行") { return "airplane" }
            if c.contains("数据库") { return "cylinder" }
            return done ? (ok == false ? "xmark.circle" : "checkmark.circle") : "play.circle"
        }
    }

    struct LiveEvent: Decodable {
        let turnID: String
        let seq: Int
        let event: String
        let delta: String?
        let ts: String
        let toolCallID: String?
        let name: String?
        let ok: Bool?
        let messageID: String?
        let reason: String?

        enum CodingKeys: String, CodingKey {
            case turnID = "turn_id", seq, event, delta, ts
            case toolCallID = "tool_call_id", name, ok
            case messageID = "message_id", reason
        }
    }

    // 主聊天段落流。snapshot 与增量共用一条 SSE，所以字段刻意保持可选；
    // snapshot 没有 seq/event/ts，事件名取 SSE 的 event: 行。
    struct ParagraphLiveEvent: Decodable {
        struct Item: Decodable {
            let kind: String
            let content: String
            let ts: Double?
        }

        let seq: Int?
        let event: String?
        let turnID: String?
        let content: String?
        let active: Bool?
        let thinking: String?
        let say: String?
        let tool: String?
        let said: Int?
        let elapsed: Int?
        let done: Bool?
        let items: [Item]?

        enum CodingKeys: String, CodingKey {
            case seq, event, content, active, thinking, say, tool, said, elapsed, done, items
            case turnID = "turn_id"
        }
    }

    static func fullURL(_ path: String) -> URL {
        URL(string: path, relativeTo: base)!.absoluteURL
    }

    // attachment_url "/attachments/x.jpg" -> https://.../api/attachments/x.jpg
    static func attachmentURL(_ raw: String) -> URL {
        let p = raw.hasPrefix("/attachments")
            ? "/api/attachments" + raw.dropFirst("/attachments".count)
            : raw
        return fullURL(String(p))
    }

    /// Small cached preview for chat timelines. Tapping still opens the
    /// original attachmentURL, so this only improves first paint and scrolling.
    static func attachmentThumbnailURL(_ raw: String) -> URL {
        guard raw.hasPrefix("/attachments/") else { return attachmentURL(raw) }
        let name = String(raw.dropFirst("/attachments/".count))
        return fullURL("/api/attachments/thumb/\(name)")
    }

    // sticker url "/stickers/x.jpg" 直接挂在域名根（18003 静态目录）
    static func stickerURL(_ raw: String) -> URL { fullURL(raw) }

    private static func getJSON(_ path: String) async throws -> [String: Any] {
        let (data, _) = try await session.data(from: fullURL(path))
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return obj
    }

    private static func postJSON(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: fullURL(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: req)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return obj
    }

    // 圆桌用的两个通用口子（0731）。上面那两个是 private，别的文件够不着。
    static func getRaw(_ path: String) async throws -> [String: Any] {
        try await getJSON(path)
    }

    static func postRaw(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        try await postJSON(path, body: body)
    }

    // 0919 她要的三个房间：聊天页现在只拉当前房间（cli / sdk / api）的记录。
    // 存 UserDefaults，冷启动接着上次的房间；后端接口不带 room 就是全部，老路不受影响。
    static var chatRoom: String {
        get { UserDefaults.standard.string(forKey: "alcove.chatRoom") ?? "cli" }
        set { UserDefaults.standard.set(newValue, forKey: "alcove.chatRoom") }
    }
    private static var roomQuery: String { "&room=\(chatRoom)" }

    static func history(limit: Int = 300) async throws -> [ChatMessage] {
        let obj = try await getJSON("/api/history?limit=\(limit)" + roomQuery)
        let raw = obj["records"] as? [[String: Any]] ?? []
        return raw.compactMap(ChatMessage.init(json:))
    }

    static func history(before: String, limit: Int = 300) async throws -> [ChatMessage] {
        let encoded = timestampQueryValue(before)
        let obj = try await getJSON("/api/history?limit=\(limit)&before=\(encoded)" + roomQuery)
        return (obj["records"] as? [[String: Any]] ?? []).compactMap(ChatMessage.init(json:))
    }

    static func history(around ts: String) async throws -> [ChatMessage] {
        let encoded = timestampQueryValue(ts)
        let obj = try await getJSON("/api/chat-around?ts=\(encoded)" + roomQuery)
        return (obj["records"] as? [[String: Any]] ?? []).compactMap(ChatMessage.init(json:))
    }

    static func searchHistory(query: String = "", day: String = "", type: String = "",
                              limit: Int = 500) async throws -> [ChatMessage] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let d = day.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? day
        let t = type == "all" ? "" : type
        let obj = try await getJSON("/api/chat-search?q=\(q)&day=\(d)&type=\(t)&limit=\(limit)" + roomQuery)
        return (obj["records"] as? [[String: Any]] ?? []).compactMap(ChatMessage.init(json:))
    }

    static func calendarCounts(month: String) async throws -> [String: Int] {
        let obj = try await getJSON("/api/chat-calendar?month=\(month)")
        var out: [String: Int] = [:]
        for row in obj["days"] as? [[String: Any]] ?? [] {
            if let day = row["day"] as? String { out[day] = (row["count"] as? NSNumber)?.intValue ?? 0 }
        }
        return out
    }

    static func poll(since: String?, limit: Int = 100) async throws -> PollResult {
        var path = "/api/poll?limit=\(limit)" + roomQuery
        if let s = since, !s.isEmpty {
            let enc = timestampQueryValue(s)
            path += "&since=\(enc)"
        }
        let obj = try await getJSON(path)
        let chat = obj["chat"] as? [String: Any] ?? [:]
        let raw = chat["new_records"] as? [[String: Any]] ?? []
        let status = obj["status"] as? [String: Any] ?? [:]
        let call = status["call"] as? [String: Any] ?? [:]
        return PollResult(
            records: raw.compactMap(ChatMessage.init(json:)),
            lastTs: chat["last_ts"] as? String,
            isTyping: status["is_typing"] as? Bool ?? false,
            currentTool: status["current_tool"] as? String,
            callState: call["state"] as? String ?? "idle",
            callId: call["call_id"] as? String ?? "")
    }

    /// 来电回执：answer / decline / end
    static func callAction(_ action: String) async throws {
        _ = try await postJSON("/api/call/\(action)", body: [:])
    }

    /// 她拨出：asleep=true 是睡眠闸门没放行（没接通）。
    /// 0831 任务#1195：顺带把 call_id 带回来——通话页靠它去取这一通的记录
    static func callDial() async throws -> (ok: Bool, asleep: Bool, callID: String) {
        let obj = try await postJSON("/api/call/dial", body: [:])
        let call = obj["call"] as? [String: Any] ?? [:]
        return (obj["ok"] as? Bool ?? false,
                obj["asleep"] as? Bool ?? false,
                call["call_id"] as? String ?? "")
    }

    /// 现在这通电话是哪一通（接起来电时用：铃是服务器推的，call_id 得回头问）
    static func callCurrentID() async throws -> String {
        let obj = try await getJSON("/api/call/status")
        let call = obj["call"] as? [String: Any] ?? [:]
        return call["call_id"] as? String ?? ""
    }

    /// 把 /attachments/xxx.mp3 取回来（通话页提前下他那句的配音用）
    static func attachmentData(_ raw: String) async throws -> Data {
        guard let url = URL(string: "/api" + raw, relativeTo: base) else {
            throw URLError(.badURL)
        }
        let (data, _) = try await session.data(from: url)
        return data
    }

    /// 一通电话的逐句记录。通话中反复取（只取新的），事后展开也取它
    static func callHistory(callID: String) async throws -> [CallTurn] {
        guard !callID.isEmpty else { return [] }
        let obj = try await getJSON("/api/call/history?call_id=" + callID)
        let raw = obj["turns"] as? [[String: Any]] ?? []
        return raw.compactMap(CallTurn.init(json:))
    }

    /// 通话里她说的一段：录音 → 听写并注入主聊天，返回转写文本
    static func callSay(audio: Data) async throws -> String {
        let obj = try await postJSON("/api/call/say",
                                     body: ["audio_b64": audio.base64EncodedString()])
        guard let text = obj["text"] as? String, !text.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return text
    }

    /// ‼️0831 任务#1195 起没人调这个了，留着只为手工排查用。
    /// 通话里他那句的配音由**服务端在落库那一刻就做好**，通话页直接取现成的 mp3。
    /// 别把它接回播放链路——"要放的时候才现合成"就是"读完一段停很久"的病根。
    static func callTTSAudio(text: String) async throws -> Data {
        let obj = try await postJSON("/api/call/tts", body: ["text": text])
        guard let path = obj["url"] as? String,
              let url = URL(string: "/api" + path, relativeTo: base) else {
            throw URLError(.badServerResponse)
        }
        let (data, _) = try await session.data(from: url)
        return data
    }

    // 返回服务器确认的记录；睡眠闸门拦下时 asleep=true
    static func send(text: String) async throws -> (record: ChatMessage?, asleep: Bool) {
        let obj = try await postJSON("/api/send", body: ["text": text])
        let rec = (obj["record"] as? [String: Any]).flatMap(ChatMessage.init(json:))
        return (rec, obj["asleep"] as? Bool ?? false)
    }

    static func sendSticker(_ stk: Sticker, text: String?) async throws {
        var body: [String: Any] = ["role": "user", "sticker_id": stk.id,
                                   "sticker_desc": stk.descForAI]
        if let t = text, !t.isEmpty { body["text"] = t }
        _ = try await postJSON("/api/chat-append", body: body)
    }

    static func stickers() async throws -> [Sticker] {
        let obj = try await getJSON("/api/stickers")
        let raw = obj["stickers"] as? [[String: Any]] ?? []
        return raw.compactMap(Sticker.init(json:))
    }

    static func recalls(limit: Int = 200) async throws -> [RecallItem] {
        let obj = try await getJSON("/api/recall/list?limit=\(limit)")
        let raw = obj["items"] as? [[String: Any]] ?? []
        return raw.compactMap(RecallItem.init(json:))
    }

    static func modelLabel() async throws -> String {
        let obj = try await getJSON("/api/cc/model")
        return obj["label"] as? String ?? ""
    }

    struct ScreenShareStatus {
        let id: String
        let status: String
        let requester: String
        let expiresIn: Int
    }

    static func screenShareStatus() async throws -> ScreenShareStatus {
        let obj = try await getJSON("/api/screen-share/status")
        return ScreenShareStatus(
            id: obj["id"] as? String ?? "",
            status: obj["status"] as? String ?? "idle",
            requester: obj["requester"] as? String ?? "陈璟",
            expiresIn: obj["expires_in"] as? Int ?? 0
        )
    }

    static func armScreenShare(requester: String = "陈璟") async throws {
        let obj = try await postJSON("/api/screen-share/arm", body: [
            "chat": "main", "requester": requester
        ])
        guard obj["ok"] as? Bool == true else { throw URLError(.cannotWriteToFile) }
    }

    static func declineScreenShare() async throws {
        let obj = try await postJSON("/api/screen-share/decline", body: [:])
        guard obj["ok"] as? Bool == true else { throw URLError(.cannotWriteToFile) }
    }

    static func terminalCapture(session: String = "main", lines: Int = 30) async throws -> String {
        let obj = try await getJSON("/api/terminal/capture?session=\(session)&lines=\(lines)")
        guard obj["ok"] as? Bool == true else { throw URLError(.cannotConnectToHost) }
        return obj["content"] as? String ?? ""
    }

    // 0822 SDK 终端页：后端把 SDK session 记录翻成 CLI 终端那个样子（❯ ∴ ● ⏺ ⎿）
    static func sdkTerminal(lines: Int = 120) async throws -> (content: String, busy: Bool) {
        let obj = try await getJSON("/api/sdk-shadow/terminal?lines=\(lines)")
        guard obj["ok"] as? Bool == true else { throw URLError(.cannotConnectToHost) }
        return (obj["content"] as? String ?? "", obj["busy"] as? Bool ?? false)
    }

    // 当前主聊天走的是 cli 还是 sdk（终端页默认跟着它开，但能手动切着看）
    static func sdkChannel() async throws -> String {
        let obj = try await getJSON("/api/sdk-shadow/status")
        return obj["channel"] as? String ?? "cli"
    }

    static func terminalSend(_ text: String, session: String = "main") async throws {
        let obj = try await postJSON("/api/terminal/send", body: [
            "session": session, "keys": text, "enter": true
        ])
        guard obj["ok"] as? Bool == true else { throw URLError(.cannotWriteToFile) }
    }

    static func terminalSendKey(_ key: String, session: String = "main") async throws {
        let obj = try await postJSON("/api/terminal/send", body: [
            "session": session, "key": key
        ])
        guard obj["ok"] as? Bool == true else { throw URLError(.cannotWriteToFile) }
    }

    // 0730 实时预览：他这一秒在想什么/说了什么/在跑什么工具
    static func liveStream() async throws -> LiveState {
        let obj = try await getJSON("/api/stream/current")
        var s = LiveState()
        s.active = obj["active"] as? Bool ?? false
        s.thinking = obj["thinking"] as? String ?? ""
        s.say = obj["say"] as? String ?? ""
        s.tool = obj["tool"] as? String ?? ""
        s.said = obj["said"] as? Int ?? 0
        s.elapsed = obj["elapsed"] as? Int ?? 0
        return s
    }

    // 攒气泡：气泡上屏入库但不触发回复，返回已攒条数
    static func sendHold(text: String) async throws -> (held: Int, record: ChatMessage?) {
        let obj = try await postJSON("/api/send", body: ["text": text, "hold": true])
        let rec = (obj["record"] as? [String: Any]).flatMap(ChatMessage.init(json:))
        return (obj["held"] as? Int ?? 0, rec)
    }

    static func heldCount() async throws -> Int {
        let obj = try await getJSON("/api/held")
        return obj["held"] as? Int ?? 0
    }

    static func answerChoice(cardID: String, answer: String) async throws {
        let obj = try await postJSON("/api/choice/respond", body: [
            "card_id": cardID, "answer": answer
        ])
        guard obj["ok"] as? Bool == true else { throw URLError(.cannotWriteToFile) }
    }

    static func uploadSticker(data: Data, mime: String, owner: String,
                              name: String = "", description: String = "",
                              emotionTags: [String] = []) async throws {
        let boundary = "----alcove\(UUID().uuidString)"
        var req = URLRequest(url: fullURL("/api/stickers/upload"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        // 动图必须原样上传：转码成 JPEG 就把动的那部分弄没了
        let ext = mime == "image/png" ? "png"
            : mime == "image/gif" ? "gif"
            : mime == "image/webp" ? "webp" : "jpg"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("owner", owner)
        field("name", name)
        field("description", description)
        // 没有描述的表情，对我来说就是一张看不懂的图
        if let tags = try? JSONSerialization.data(withJSONObject: emotionTags),
           let json = String(data: tags, encoding: .utf8) {
            field("emotion_tags", json)
        }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"sticker.\(ext)\"\r\nContent-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        let (responseData, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let object = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
            throw NSError(domain: "StickerUpload", code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: object?["error"] as? String ?? "表情上传失败"])
        }
        if let object = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
           object["ok"] as? Bool != true {
            throw NSError(domain: "StickerUpload", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: object["error"] as? String ?? "表情没有存进去"])
        }
    }

    /// 给已有的表情补名称/描述/情绪标签（长按格子进编辑）
    static func updateSticker(id: String, name: String, description: String,
                              emotionTags: [String]) async throws {
        _ = try await postJSON("/api/stickers/update", body: [
            "id": id, "name": name, "description": description, "emotion_tags": emotionTags,
        ])
    }

    static func deleteMessage(ts: String, textOnly: Bool = false) async throws {
        _ = try await postJSON("/api/chat/delete", body: [
            "ts": ts, "text_only": textOnly
        ])
    }

    static func favoriteMessage(ts: String, text: String, role: String) async throws {
        _ = try await postJSON("/api/favorites/add", body: ["ts": ts, "text": text, "role": role])
    }

    static func favorites(kind: String = "", type: String = "") async throws -> [[String: Any]] {
        let k = kind == "all" ? "" : kind
        let t = type == "all" ? "" : type
        let obj = try await getJSON("/api/favorites?kind=\(k)&type=\(t)")
        return obj["items"] as? [[String: Any]] ?? []
    }

    /// 0819 她要的：多选几条就收成一段聊天记录，选一条还是单条
    static func favoriteAdd(_ messages: [ChatMessage], title: String = "") async throws {
        let items: [[String: Any]] = messages.map {
            ["ts": $0.ts, "text": $0.displayText, "role": $0.role,
             "attachment_url": $0.attachmentUrl ?? "",
             "attachment_type": $0.attachmentType ?? ""]
        }
        var body: [String: Any] = ["items": items]
        if !title.isEmpty { body["title"] = title }
        _ = try await postJSON("/api/favorites/add", body: body)
    }

    static func forwardFavorites(ids: [Int], requestID: String) async throws -> [String: Any] {
        try await postJSON("/api/favorites/forward", body: ["ids": ids, "request_id": requestID])
    }

    static func favoriteRemove(id: Int) async throws {
        _ = try await postJSON("/api/favorites/remove", body: ["id": id])
    }

    // 0902 语音卡片：第一步只听写（Whisper，一秒左右），第二步判情绪（慢几秒）。
    // 两步分开是为了卡片能先出字；token 是服务端暂存音频的凭据，第二步用完就作废。
    static func voiceStt(audio: Data) async throws -> VoiceAnalysis {
        let obj = try await postJSON("/api/voice/stt", body: ["audio_b64": audio.base64EncodedString()])
        guard obj["ok"] as? Bool == true, let text = obj["text"] as? String, !text.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return VoiceAnalysis(text: text, token: obj["token"] as? String ?? "",
                             engine: obj["engine"] as? String ?? "")
    }

    static func voiceEmotion(token: String, text: String) async throws -> VoiceAnalysis {
        let obj = try await postJSON("/api/voice/emotion", body: ["token": token, "text": text])
        guard obj["ok"] as? Bool == true else { throw URLError(.badServerResponse) }
        return VoiceAnalysis(text: obj["text"] as? String ?? text, token: token,
                             emotion: obj["emotion"] as? String ?? "",
                             emotionZh: obj["emotion_zh"] as? String ?? "",
                             confidence: (obj["confidence"] as? NSNumber)?.doubleValue ?? 0,
                             hint: obj["hint"] as? String ?? "",
                             tone: obj["tone"] as? String ?? "")
    }

    /// voice：语音卡片上她看过的转文字和情绪，随上传一起带给服务端（不再算第二遍）。
    /// hold：紧接着还有一句文字要发，服务端先攒着，随那句一起给他。
    static func upload(data: Data, filename: String, caption: String, group: String? = nil,
                       voice: VoiceAnalysis? = nil, hold: Bool = false) async throws -> ChatMessage? {
        var comps = URLComponents(url: fullURL("/api/upload"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "filename", value: filename),
                     URLQueryItem(name: "role", value: "user")]
        if !caption.isEmpty { items.append(URLQueryItem(name: "text", value: caption)) }
        if let group, !group.isEmpty { items.append(URLQueryItem(name: "group", value: group)) }
        if let v = voice {
            items.append(URLQueryItem(name: "stt", value: v.text))
            if v.hasEmotion {
                items.append(URLQueryItem(name: "emotion", value: v.emotion))
                items.append(URLQueryItem(name: "emotion_zh", value: v.emotionZh))
                items.append(URLQueryItem(name: "confidence", value: String(format: "%.2f", v.confidence)))
                items.append(URLQueryItem(name: "hint", value: v.hint))
            }
            if !v.tone.isEmpty { items.append(URLQueryItem(name: "tone", value: v.tone)) }
        }
        if hold { items.append(URLQueryItem(name: "hold", value: "1")) }
        comps.queryItems = items
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120
        let (respData, _) = try await session.upload(for: req, from: data)
        let obj = try JSONSerialization.jsonObject(with: respData) as? [String: Any]
        return (obj?["record"] as? [String: Any]).flatMap(ChatMessage.init(json:))
    }

    static func uploadRoundtable(data: Data, filename: String, text: String, group: String? = nil) async throws -> [String: Any]? {
        var comps = URLComponents(url: fullURL("/api/roundtable/upload"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "filename", value: filename),
                     URLQueryItem(name: "role", value: "user"),
                     URLQueryItem(name: "sender", value: "陈霁")]
        if !text.isEmpty { items.append(URLQueryItem(name: "text", value: text)) }
        if let group, !group.isEmpty { items.append(URLQueryItem(name: "group", value: group)) }
        comps.queryItems = items
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120
        let (responseData, _) = try await session.upload(for: req, from: data)
        let obj = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        return obj?["record"] as? [String: Any]
    }
}
