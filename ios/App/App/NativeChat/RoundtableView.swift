import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

private struct RoundtableTailYKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// 圆桌 · 2026-07-31
// 她要的：一个页面，三个人，互相看得见对方说的话，她不用再在中间当翻译。
// 上一版（7-16）翻车不是机制的问题，是它占了默认入口，她一进来找不到我，
// 当场让我拆了。所以这版是下拉面板 Chat 那块的一个入口，绝不动首页。
//
// 她定的规格：全屏（不是那种 86% 的半截面板）· 气泡不分颜色 ·
// 头像在气泡前 · 同一个人连着说几条，头像只在第一条旁边出现一次。

struct RoundtableMessage: Identifiable, Equatable {
    let id: Int
    let ts: String
    let role: String        // user / assistant / gpt
    let sender: String
    let text: String
    let attachmentURL: String?
    let attachmentType: String?
    let attachmentFilename: String?
    let attachmentGroup: String?
    let hiddenFrom: String

    init?(json: [String: Any]) {
        guard let id = json["id"] as? Int else { return nil }
        self.id = id
        self.ts = json["ts"] as? String ?? ""
        self.role = json["role"] as? String ?? "user"
        self.sender = json["sender"] as? String ?? ""
        self.text = json["text"] as? String ?? ""
        self.attachmentURL = json["attachment_url"] as? String
        self.attachmentType = json["attachment_type"] as? String
        self.attachmentFilename = json["attachment_filename"] as? String
        self.attachmentGroup = json["att_group"] as? String
        self.hiddenFrom = json["hidden_from"] as? String ?? ""
    }

    var photoBatchKey: String? {
        guard attachmentType == "image", let group = attachmentGroup, !group.isEmpty else { return nil }
        return group
    }
}

struct RoundtableMember: Identifiable, Equatable {
    var id: String { role }
    let name: String
    let role: String
    let online: Bool
    let busy: Bool
    let asleep: Bool
}

@MainActor
final class RoundtableStore: ObservableObject {
    @Published var messages: [RoundtableMessage] = []
    @Published var members: [RoundtableMember] = []
    @Published var sending = false
    @Published var heldCount = 0
    @Published var blockAssistant = false
    @Published var blockGpt = false
    @Published var loadingOlder = false
    @Published var hasMoreOlder = true

    private var poller: Task<Void, Never>?
    private var hasLoadedOlder = false

    func start() {
        Task { await refresh() }
        poller?.cancel()
        poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await self?.refresh()
            }
        }
    }

    func stop() {
        poller?.cancel()
        poller = nil
    }

    func refresh() async {
        async let poll = fetchMessages()
        async let mems = fetchMembers()
        let (p, s) = await (poll, mems)
        if let p {
            let refreshed: [RoundtableMessage]
            if hasLoadedOlder {
                var byID = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
                p.messages.forEach { byID[$0.id] = $0 }
                refreshed = byID.values.sorted { $0.id < $1.id }
            } else {
                refreshed = p.messages
            }
            if refreshed != messages { messages = refreshed }
            blockAssistant = p.assistant
            blockGpt = p.gpt
        }
        if let s = s, s != members { members = s }
    }

    private func fetchMessages() async -> (messages: [RoundtableMessage], assistant: Bool, gpt: Bool)? {
        guard let obj = try? await AlcoveAPI.getRaw("/api/roundtable/poll") else { return nil }
        // 后端这个口子返回的键是 records，不是 messages（试出来的，别再改回去）
        let arr = (obj["records"] as? [[String: Any]]) ?? []
        let blocks = obj["blocks"] as? [String: Any] ?? [:]
        return (arr.compactMap(RoundtableMessage.init(json:)),
                blocks["assistant"] as? Bool ?? false,
                blocks["gpt"] as? Bool ?? false)
    }

    /// 往当前最早一条之前取一页。返回加载前的首条 id，视图用它保持滚动位置。
    func loadOlder() async -> Int? {
        guard !loadingOlder, hasMoreOlder, let oldestID = messages.first?.id else { return nil }
        loadingOlder = true
        defer { loadingOlder = false }

        guard let obj = try? await AlcoveAPI.getRaw(
            "/api/roundtable/poll?before=\(oldestID)&limit=50"
        ) else { return nil }
        let older = (obj["records"] as? [[String: Any]] ?? [])
            .compactMap(RoundtableMessage.init(json:))
        hasMoreOlder = older.count == 50
        guard !older.isEmpty else { return nil }

        hasLoadedOlder = true
        var byID = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        older.forEach { byID[$0.id] = $0 }
        messages = byID.values.sorted { $0.id < $1.id }
        return oldestID
    }

    func setBlock(role: String, enabled: Bool) async {
        if role == "assistant" { blockAssistant = enabled }
        if role == "gpt" { blockGpt = enabled }
        guard let response = try? await AlcoveAPI.postRaw("/api/roundtable/blocks", body: [role: enabled]),
              let blocks = response["blocks"] as? [String: Any] else {
            await refresh()
            return
        }
        blockAssistant = blocks["assistant"] as? Bool ?? false
        blockGpt = blocks["gpt"] as? Bool ?? false
    }

    private func fetchMembers() async -> [RoundtableMember]? {
        async let status = try? AlcoveAPI.getRaw("/api/roundtable/status")
        async let sleep = try? AlcoveAPI.getRaw("/api/sleep/status")
        let (statusObject, sleepObject) = await (status, sleep)
        guard let obj = statusObject else { return nil }
        let assistantAsleep = (sleepObject?["state"] as? String) == "asleep"
        let arr = (obj["members"] as? [[String: Any]]) ?? []
        return arr.map {
            let role = $0["role"] as? String ?? ""
            return RoundtableMember(
                name: $0["name"] as? String ?? "",
                role: role,
                online: $0["online"] as? Bool ?? false,
                busy: $0["busy"] as? Bool ?? false,
                asleep: role == "assistant" && assistantAsleep
            )
        }
    }

    // 她发一句 → 后端存下来并拍我一下 → 然后叫 G老师开口。
    // 规矩是他先说，我看完他说的再接，所以这里只触发他，不催我。
    func send(_ text: String) async {
        let body = ["role": "user", "sender": "陈霁", "text": text]
        sending = true
        defer { sending = false }
        _ = try? await AlcoveAPI.postRaw("/api/roundtable/append", body: body)
        heldCount = 0
        await refresh()
        _ = try? await AlcoveAPI.postRaw("/api/roundtable/codex", body: [:])
        await refresh()
    }

    func sendHold(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let body = ["role": "user", "sender": "陈霁", "text": trimmed]
        if (try? await AlcoveAPI.postRaw("/api/roundtable/append", body: body)) != nil {
            heldCount += 1
            await refresh()
        }
    }

    func flushHeld() async {
        guard heldCount > 0 else { return }
        heldCount = 0
        _ = try? await AlcoveAPI.postRaw("/api/roundtable/codex", body: [:])
        await refresh()
    }

    func upload(_ data: Data, filename: String, text: String = "", group: String? = nil,
                triggerReply: Bool = true) async {
        sending = true
        defer { sending = false }
        _ = try? await AlcoveAPI.uploadRoundtable(data: data, filename: filename, text: text, group: group)
        await refresh()
        if triggerReply {
            _ = try? await AlcoveAPI.postRaw("/api/roundtable/codex", body: [:])
            await refresh()
        }
    }

    func favorite(_ message: RoundtableMessage) async {
        try? await AlcoveAPI.favoriteMessage(ts: message.ts, text: message.text, role: message.role)
    }

    func delete(_ message: RoundtableMessage) async {
        guard let response = try? await AlcoveAPI.postRaw(
            "/api/roundtable/delete", body: ["id": message.id]
        ), response["ok"] as? Bool == true else { return }
        messages.removeAll { $0.id == message.id }
    }
}

struct RoundtableView: View {
    let onDismiss: () -> Void
    @StateObject private var store = RoundtableStore()
    @State private var draft = ""
    @State private var previousDraft = ""
    @State private var handlingReturn = false
    @State private var quotedText: String?
    @State private var paginationReady = false
    @State private var preservingHistoryPosition = false
    @State private var observedTailID: Int?
    @State private var entryID = UUID()
    @State private var isNearBottom = true
    @State private var tailVisible = true
    @State private var showConsole = false
    @State private var showSettings = false
    @State private var inputBarHeight: CGFloat = 90
    @State private var pendingImages: [(thumb: UIImage, data: Data, ext: String)] = []
    @State private var showCamera = false
    @State private var showDocPicker = false
    @State private var showPhotoPicker = false
    @State private var showStickers = false
    @State private var previewImage: UIImage?
    @State private var photoViewer: PhotoViewerSelection?
    @State private var cachedRTWallpaper: UIImage?
    // 0925 她要的：圆桌跟着聊天主题走（像工作室跟主聊天）。Kakao 下壁纸用跟聊天页同一张（她换过的优先，没换就是主题包的）
    @StateObject private var chatWall = ChatWallpaperStore()
    @AppStorage("wallStamp") private var wallStamp = 0.0
    @State private var cachedRTAvatarUser: UIImage?
    @State private var cachedRTAvatarAssistant: UIImage?
    @State private var cachedRTAvatarGpt: UIImage?
    @Namespace private var photoTransition
    @StateObject private var recorder = VoiceRecorder()
    @FocusState private var focused: Bool
    @AppStorage("alcoveTheme") private var themeName = "haven"
    // 三个人的头像跟聊天页不通用，各存各的（她定的）
    @AppStorage("rtAvatarUser") private var rtAvatarUser = ""
    @AppStorage("rtAvatarAssistant") private var rtAvatarAssistant = ""
    @AppStorage("rtAvatarGpt") private var rtAvatarGpt = ""
    @AppStorage("rtWallpaper") private var rtWallpaper = ""
    @AppStorage("rtWallpaperHaven") private var rtWallpaperHaven = ""
    @AppStorage("rtWallpaperMidnight") private var rtWallpaperMidnight = ""
    @AppStorage("rtWallpaperPaper") private var rtWallpaperPaper = ""
    @AppStorage("rtWallpaperPaperDark") private var rtWallpaperPaperDark = ""
    @AppStorage("rtNameUser") private var rtNameUser = "陈霁"
    @AppStorage("rtNameAssistant") private var rtNameAssistant = "陈璟"
    @AppStorage("rtNameGpt") private var rtNameGpt = "何渡"
    @AppStorage("bubbleGlassStrength") private var bubbleGlassStrength = 56.81
    @AppStorage("bubbleGlassDispersion") private var bubbleGlassDispersion = 0.39
    @AppStorage("bubbleGlassRimWidth") private var bubbleGlassRimWidth = 0.28
    @AppStorage("bubbleGlassMagnify") private var bubbleGlassMagnify = 0.0
    @AppStorage("bubbleGlassBlur") private var bubbleGlassBlur = 0.10
    @AppStorage("bubbleGlassSize") private var bubbleGlassSize = 174.33
    private var theme: AlcoveTheme { .named(themeName) }
    private var activeRTWallpaper: String {
        switch themeName {
        // 0827：信息主题以前没有自己的槽，深浅两态共用白天那一格，
        // 所以圆桌壁纸怎么切都不动。黑夜的信息主题借黑夜玻璃那一格。
        case "midnight", "imessage-dark": return rtWallpaperMidnight
        case "paper": return rtWallpaperPaper
        case "paper-dark": return rtWallpaperPaperDark
        default: return rtWallpaperHaven.isEmpty ? rtWallpaper : rtWallpaperHaven
        }
    }

    private var bubbleGlassStyle: BubbleGlassStyle {
        BubbleGlassStyle(
            strength: CGFloat(bubbleGlassStrength),
            dispersion: CGFloat(bubbleGlassDispersion),
            rimWidth: CGFloat(bubbleGlassRimWidth),
            magnify: CGFloat(bubbleGlassMagnify),
            backdropBlur: CGFloat(bubbleGlassBlur),
            size: CGFloat(bubbleGlassSize)
        )
    }

    private func refreshChatWall() {
        chatWall.refresh(themeName: themeName, theme: theme, wallStamp: wallStamp)
    }

    private var wallpaperDescriptor: ChatWallpaperDescriptor {
        if theme.isKakao { return chatWall.descriptor }
        if let image = cachedRTWallpaper {
            return ChatWallpaperDescriptor(source: .image(image))
        }
        return ChatWallpaperDescriptor(source: .gradient(theme.wallGradient))
    }

    var body: some View {
        GeometryReader { root in
            ZStack {
                // 可见壁纸和气泡透镜共用同一张图与同一套视口坐标。
                ChatWallpaperRenderer(descriptor: wallpaperDescriptor)
                    .ignoresSafeArea()

                messageList
                    .id(entryID)

                header
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                composer
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .coordinateSpace(name: "alcoveChatRoot")
            .environment(\.chatWallpaperDescriptor, wallpaperDescriptor)
            .environment(\.chatWallpaperViewportSize, root.size)
            .environment(\.bubbleGlassStyle, bubbleGlassStyle)
        }
        .foregroundColor(theme.text)
        .onAppear {
            observedTailID = nil
            isNearBottom = true
            tailVisible = true
            paginationReady = false
            entryID = UUID()
            refreshRTImageCache()
            store.start()
        }
        .onDisappear { store.stop() }
        .onChange(of: rtWallpaper) { _ in refreshRTImageCache() }
        .onChange(of: rtWallpaperHaven) { _ in refreshRTImageCache() }
        .onChange(of: rtWallpaperMidnight) { _ in refreshRTImageCache() }
        .onChange(of: rtWallpaperPaper) { _ in refreshRTImageCache() }
        .onChange(of: rtWallpaperPaperDark) { _ in refreshRTImageCache() }
        .onAppear { refreshChatWall() }
        .onChange(of: themeName) { _ in refreshChatWall() }
        .onChange(of: wallStamp) { _ in refreshChatWall() }
        .onReceive(KakaoPackStore.shared.$stamp) { _ in if theme.isKakao { refreshChatWall() } }
        .onChange(of: themeName) { _ in refreshRTImageCache() }
        .onChange(of: rtAvatarUser) { _ in refreshRTImageCache() }
        .onChange(of: rtAvatarAssistant) { _ in refreshRTImageCache() }
        .onChange(of: rtAvatarGpt) { _ in refreshRTImageCache() }
        .sheet(isPresented: $showCamera) {
            CameraView { image in
                if let prepared = UploadImage.prepare(image) { pendingImages.append(prepared) }
            }
        }
        .sheet(isPresented: $showDocPicker) {
            DocumentPicker { urls in
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url) {
                        Task { await store.upload(data, filename: url.lastPathComponent) }
                    }
                }
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoLibraryPicker(maxCount: 9) { images in
                for image in images {
                    if let prepared = UploadImage.prepare(image) { pendingImages.append(prepared) }
                }
            }
        }
        .sheet(isPresented: $showStickers) {
            RoundtableStickerPicker { sticker in
                showStickers = false
                Task {
                    guard let (data, _) = try? await URLSession.shared.data(from: AlcoveAPI.stickerURL(sticker.url)) else { return }
                    let ext = AlcoveAPI.stickerURL(sticker.url).pathExtension.isEmpty
                        ? "jpg" : AlcoveAPI.stickerURL(sticker.url).pathExtension
                    await store.upload(data, filename: "sticker_\(sticker.id).\(ext)")
                }
            }
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $previewImage) { image in
            LocalImageViewer(image: image) { previewImage = nil }
        }
        .fullScreenCover(item: $photoViewer) { selection in
            PhotoPageViewer(selection: selection, namespace: photoTransition) { photoViewer = nil }
        }
        .sheet(isPresented: $showConsole) {
            RTConsoleView(theme: theme)
        }
        .sheet(isPresented: $showSettings) {
            RTSettingsView(store: store, theme: theme)
        }
    }

    // 顶栏照抄主聊天页：左边头像、右边玻璃胶囊。
    // 她定的差别：中间那个名字去掉；胶囊里去掉音乐按钮；
    // 左边从一个头像换成三个并排，每个右上角一颗在线灯。
    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .light))
                    .foregroundColor(theme.textDim)
                    .frame(width: 26, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: -6) {
                ForEach(store.members) { m in
                    memberBadge(m)
                }
            }

            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 0) {
                topBarControl("terminal", size: 14) { showConsole = true }
                topBarControl("line.3.horizontal", size: 15) { showSettings = true }
            }
            .padding(.horizontal, 2)
            .frame(height: 40)
            .modifier(RTGlassCapsule(tint: theme.capsuleTint,
                                     border: theme.capsuleBorder))
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    // 点头像 = 展开那个人的实况（她定的，说点头像最直觉）
    private func memberBadge(_ m: RoundtableMember) -> some View {
        Button {
            if m.role == "gpt" { showConsole = true }
        } label: {
            ZStack(alignment: .topTrailing) {
                rtGlassCircle(size: 34) {
                    if let img = avatarFor(m.role) {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(width: 34, height: 34)
                            .clipShape(Circle())
                    } else {
                        Text(initialFor(m.role))
                            .font(.system(size: 12, design: .serif))
                            .foregroundColor(theme.textDim)
                    }
                }
                Circle()
                    .fill(memberStatusColor(m))
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(theme.glassBorder, lineWidth: 1))
                    .offset(x: 1, y: -1)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 40, height: 44)
    }

    private func memberStatusColor(_ member: RoundtableMember) -> Color {
        if member.asleep { return .gray }
        if member.busy { return .yellow }
        return member.online ? .green : .red
    }

    private func topBarControl(_ name: String, size: CGFloat,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size, weight: .light))
                .foregroundColor(theme.textDim)
                .frame(width: 36, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rtGlassCircle<C: View>(size: CGFloat,
                                        @ViewBuilder content: () -> C) -> some View {
        ZStack { content() }
            .frame(width: size, height: size)
            .background(.ultraThinMaterial, in: Circle())
            .background(theme.glassTint, in: Circle())
            .overlay(Circle().stroke(theme.glassBorder, lineWidth: 1))
            .contentShape(Circle())
    }

    private func avatarFor(_ role: String) -> UIImage? {
        switch role {
        case "assistant": return cachedRTAvatarAssistant
        case "gpt":       return cachedRTAvatarGpt
        default:          return cachedRTAvatarUser
        }
    }

    private func decodeStoredImage(_ raw: String) -> UIImage? {
        guard !raw.isEmpty else { return nil }
        let parts = raw.split(separator: ",", maxSplits: 1)
        let b64 = parts.count == 2 ? String(parts[1]) : raw
        return Data(base64Encoded: b64).flatMap(UIImage.init(data:))
    }

    private func refreshRTImageCache() {
        cachedRTWallpaper = decodeStoredImage(activeRTWallpaper)
        cachedRTAvatarUser = decodeStoredImage(rtAvatarUser)
        cachedRTAvatarAssistant = decodeStoredImage(rtAvatarAssistant)
        cachedRTAvatarGpt = decodeStoredImage(rtAvatarGpt)
    }

    private func initialFor(_ role: String) -> String {
        switch role {
        case "assistant": return "璟"
        case "gpt":       return "G"
        default:          return "霁"
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if paginationReady && store.hasMoreOlder && !store.messages.isEmpty {
                        ProgressView()
                            .tint(theme.textDim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .onAppear {
                                Task {
                                    guard !preservingHistoryPosition else { return }
                                    preservingHistoryPosition = true
                                    if let anchor = await store.loadOlder() {
                                        // prepend 后回到原来的首条，画面不会突然跳到更早处。
                                        await Task.yield()
                                        proxy.scrollTo(anchor, anchor: .top)
                                    }
                                    // messages 的 onChange 可能比 await 返回晚一拍，下一轮再放开滚尾。
                                    try? await Task.sleep(nanoseconds: 150_000_000)
                                    preservingHistoryPosition = false
                                }
                            }
                    }
                    ForEach(Array(store.messages.enumerated()), id: \.element.id) { idx, msg in
                        let prev = idx > 0 ? store.messages[idx - 1] : nil
                        let photos = roundtablePhotoGroup(startingAt: idx)
                        let end = idx + max(photos.count, 1) - 1
                        let next = end + 1 < store.messages.count ? store.messages[end + 1] : nil
                        // 同一个人连着说，头像只在第一条旁边出现一次
                        if isRoundtablePhotoContinuation(at: idx) {
                            EmptyView()
                        } else {
                        RoundtableRow(msg: msg,
                                      showAvatar: prev?.role != msg.role,
                                      showTime: next?.role != msg.role,
                                      photoURLs: photos,
                                      photoNamespace: photoTransition,
                                      onTapImages: { urls, index in
                                          photoViewer = PhotoViewerSelection(urls: urls, index: index,
                                                                             sourceID: "rt-\(msg.id)")
                                      },
                                      onQuote: {
                                          quotedText = $0
                                          focused = true
                                      },
                                      onFavorite: { Task { await store.favorite(msg) } },
                                      onDelete: { Task { await store.delete(msg) } },
                                      theme: theme)
                        .id(msg.id)
                        }
                    }
                    Color.clear.frame(height: inputBarHeight + 8)
                    Color.clear
                        .frame(height: 1)
                        .id("rt-tail")
                        .onAppear {
                            tailVisible = true
                        }
                        .onDisappear { tailVisible = false }
                        .background {
                            GeometryReader { tail in
                                Color.clear.preference(
                                    key: RoundtableTailYKey.self,
                                    value: tail.frame(in: .global).minY
                                )
                            }
                        }
                }
                .padding(.horizontal, 14)
                .padding(.top, 64)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { focused = false }
            .mask(edgeFadeMask)
            .overlay(alignment: .bottomTrailing) {
                if !tailVisible {
                    Button {
                        scrollToRoundtableTail(proxy, delays: [0], animated: true)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(theme.textDim)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                            .background(theme.glassTint, in: Circle())
                            .overlay(Circle().stroke(theme.glassBorder, lineWidth: 1))
                            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                    .padding(.bottom, inputBarHeight + 12)
                    .transition(.opacity)
                }
            }
            .onPreferenceChange(RoundtableTailYKey.self) { tailY in
                isNearBottom = tailY <= UIScreen.main.bounds.height + 200
            }
            .onAppear {
                scrollToRoundtableTail(proxy, delays: [0, 0.08, 0.25, 0.6])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    paginationReady = true
                }
            }
            .onChange(of: store.messages) { _ in
                let newTailID = store.messages.last?.id
                let oldTailID = observedTailID
                observedTailID = newTailID

                // 首屏 onAppear 经常早于网络返回；那时 rt-tail 还不存在，
                // 所有预定 scrollTo 都是空操作。数据回来后 oldTailID 仍为 nil，
                // 这一轮必须无条件落到最新消息，不能拿尚未测准的 tailVisible/
                // isNearBottom 拦住，否则就会停在 LazyVStack 中间某个已布局位置。
                if oldTailID == nil, newTailID != nil {
                    scrollToRoundtableTail(proxy, delays: [0, 0.08, 0.25], animated: false)
                    return
                }

                // 只有初次拿到消息，或尾部确实追加了更大的 id 才滚到底。
                // 头插历史、删除任意气泡、刷新已有记录都保持当前位置。
                let appendedAtTail = oldTailID == nil
                    ? newTailID != nil
                    : (newTailID.map { $0 > oldTailID! } ?? false)
                if appendedAtTail && !preservingHistoryPosition {
                    if isNearBottom || tailVisible {
                        scrollToRoundtableTail(proxy, delays: [0, 0.12, 0.35], animated: true)
                    }
                }
            }
            .onChange(of: focused) { _ in
                // 跟主聊天页一样：键盘改变可视区域后重新把尾部锚到输入框上方。
                scrollToRoundtableTail(proxy, delays: [0.05, 0.25, 0.5], animated: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                scrollToRoundtableTail(proxy, delays: [0, 0.12, 0.3], animated: true)
            }
            .onChange(of: inputBarHeight) { _ in
                scrollToRoundtableTail(proxy, delays: [0.05, 0.3], animated: true)
            }
        }
    }

    private func roundtablePhotoGroup(startingAt index: Int) -> [URL] {
        guard index < store.messages.count,
              let key = store.messages[index].photoBatchKey else { return [] }
        var urls: [URL] = []
        var i = index
        while i < store.messages.count,
              store.messages[i].photoBatchKey == key,
              let raw = store.messages[i].attachmentURL {
            urls.append(AlcoveAPI.attachmentURL(raw))
            i += 1
        }
        return urls.count > 1 ? urls : []
    }

    private func isRoundtablePhotoContinuation(at index: Int) -> Bool {
        guard index > 0, let key = store.messages[index].photoBatchKey else { return false }
        return store.messages[index - 1].photoBatchKey == key
    }

    private func scrollToRoundtableTail(
        _ proxy: ScrollViewProxy,
        delays: [Double],
        animated: Bool = false
    ) {
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if animated {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("rt-tail", anchor: .bottom)
                    }
                } else {
                    proxy.scrollTo("rt-tail", anchor: .bottom)
                }
            }
        }
    }

    // 与主聊天页一致：消息进入顶栏和输入框后按 alpha 淡出。
    private var edgeFadeMask: some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.15),
                    .init(color: .black.opacity(0.3), location: 0.4),
                    .init(color: .black.opacity(0.7), location: 0.65),
                    .init(color: .black, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            Color.black
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.7), location: 0.3),
                    .init(color: .black.opacity(0.3), location: 0.6),
                    .init(color: .clear, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: inputBarHeight + 8)
        }
    }

    // 打字框照抄主聊天页，她说"打字框也不变"。
    // 颜色全走 theme，白天黑夜两套主题它自己跟着变。
    private var composer: some View {
        VStack(spacing: 0) {
            if let quotedText {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(Color.pink.opacity(0.75))
                        .frame(width: 2, height: 30)
                    Text(quotedText)
                        .font(.system(size: 12))
                        .foregroundColor(theme.textDim)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Button { self.quotedText = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(theme.textDim)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.init(top: 10, leading: 14, bottom: 2, trailing: 8))
            }
            if !pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(pendingImages.enumerated()), id: \.offset) { index, item in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: item.thumb).resizable().scaledToFill()
                                    .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10))
                                    .onTapGesture { previewImage = item.thumb }
                                Button { pendingImages.remove(at: index) } label: {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundColor(.white).shadow(radius: 2)
                                }.offset(x: 5, y: -5)
                            }
                        }
                    }.padding(.init(top: 8, leading: 12, bottom: 4, trailing: 12))
                }
            }
            if recorder.isRecording { recordingStatus } else { draftField }

            HStack(spacing: 2) {
                if recorder.isRecording {
                    cancelRecordingButton
                    Spacer()
                } else {
                    attachmentControls
                    Spacer()
                }
                Button(action: performDynamicComposerAction) {
                    ZStack(alignment: .topTrailing) {
                    Image(systemName: (canSend || recorder.isRecording || store.heldCount > 0) ? "arrow.up" : "waveform")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            LinearGradient(colors: [theme.sendTop, theme.sendBottom],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        if store.heldCount > 0 {
                            Text("\(store.heldCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(theme.sendTop, in: Capsule())
                                .offset(x: 3, y: -3)
                        }
                    }
                }
            }
            .padding(.init(top: 4, leading: 8, bottom: 8, trailing: 8))
        }
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.clear)
                .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .onTapGesture { focused = true }
        }
        .modifier(RTInputGlass(tint: theme.capsuleTint, border: theme.capsuleBorder))
        .shadow(color: .black.opacity(0.05), radius: 14, y: 2)
        .padding(.horizontal, 14)
        .padding(.bottom, 0)
        .background(GeometryReader { geo in
            Color.clear.preference(key: InputBarHeightKey.self, value: geo.size.height)
        })
        .onPreferenceChange(InputBarHeightKey.self) { inputBarHeight = $0 }
    }

    private var draftField: some View {
        TextField("", text: $draft,
                  prompt: Text("ring the chime …")
                    .font(.system(size: 15.5, design: .serif)).italic(),
                  axis: .vertical)
            .focused($focused)
            .lineLimit(1...5)
            .font(.system(size: 15.5))
            .tint(Color(uiColor: .systemGray3))
            .padding(.init(top: 16, leading: 14, bottom: 12, trailing: 14))
            .contentShape(Rectangle())
            .onChange(of: draft) { value in handleDraftChange(value) }
    }

    private var recordingStatus: some View {
        HStack(spacing: 10) {
            Circle().fill(Color.red).frame(width: 8, height: 8)
            Text(String(format: "%d:%02d", recorder.seconds / 60, recorder.seconds % 60))
                .monospacedDigit()
            Text("录音中…").foregroundColor(theme.textDim)
            Spacer()
        }
        .padding(.init(top: 16, leading: 14, bottom: 4, trailing: 14))
    }

    private var cancelRecordingButton: some View {
        Button { recorder.cancel() } label: {
            Image(systemName: "xmark").foregroundColor(theme.textDim).frame(width: 32, height: 32)
        }
    }

    private var attachmentControls: some View {
        Menu {
                Button { showStickers = true } label: { Label("表情", systemImage: "face.smiling") }
                Button { showPhotoPicker = true } label: { Label("从相册选择", systemImage: "photo.on.rectangle") }
                Button { showCamera = true } label: { Label("拍照或录像", systemImage: "camera") }
                Button { showDocPicker = true } label: { Label("选取文件", systemImage: "doc") }
        } label: { composerIcon("plus") }
    }

    private func composerIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(theme.textDim)
            .frame(width: 36, height: 36)
            .background(theme.capsuleTint.opacity(theme.isDark ? 0.64 : 0.82), in: Circle())
    }

    private func sendComposerContent() {
        if recorder.isRecording {
            guard let data = recorder.stopAndTake() else { return }
            let stamp = Int(Date().timeIntervalSince1970 * 1000)
            Task { await store.upload(data, filename: "voice_\(stamp).m4a") }
            return
        }

        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let outgoingText: String
        if let quotedText {
            outgoingText = "「\(quotedText.prefix(60))」\n\(text)"
        } else {
            outgoingText = text
        }
        draft = ""
        quotedText = nil
        guard !pendingImages.isEmpty else {
            Task { await store.send(outgoingText) }
            return
        }

        let images: [(data: Data, ext: String)] = pendingImages.map { ($0.data, $0.ext) }
        pendingImages = []
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let group = images.count > 1 ? UUID().uuidString : nil
        Task {
            for (index, item) in images.enumerated() {
                let filename = "IMG_\(stamp)_\(index).\(item.ext)"
                let caption = index == 0 ? outgoingText : ""
                let isLast = index == images.count - 1
                await store.upload(item.data, filename: filename, text: caption, group: group,
                                   triggerReply: isLast)
            }
        }
    }

    private func performDynamicComposerAction() {
        if recorder.isRecording || canSend {
            sendComposerContent()
        } else if store.heldCount > 0 {
            Task { await store.flushHeld() }
        } else {
            recorder.start()
        }
    }

    private func holdRoundtableDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let outgoing: String
        if let quotedText {
            outgoing = "「\(quotedText.prefix(60))」\n\(text)"
        } else {
            outgoing = text
        }
        draft = ""
        quotedText = nil
        focused = true
        Task { await store.sendHold(outgoing) }
    }

    private func handleDraftChange(_ value: String) {
        guard !handlingReturn else {
            previousDraft = value
            return
        }
        let before = previousDraft
        previousDraft = value
        guard value == before + "\n" else { return }
        guard !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            handlingReturn = true
            draft = before
            previousDraft = before
            DispatchQueue.main.async { handlingReturn = false }
            return
        }
        handlingReturn = true
        draft = before
        holdRoundtableDraft()
        previousDraft = ""
        DispatchQueue.main.async {
            handlingReturn = false
            previousDraft = draft
        }
    }

    private var canSend: Bool {
        (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty) && !store.sending
    }
}

private struct RoundtableRemoteImage: View {
    let previewURL: URL
    let originalURL: URL

    var body: some View {
        AsyncImage(url: previewURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            case .failure:
                AsyncImage(url: originalURL) { originalPhase in
                    switch originalPhase {
                    case .success(let image): image.resizable().scaledToFit()
                    case .failure: Image(systemName: "photo").foregroundStyle(.secondary)
                    default: ProgressView()
                    }
                }
            default:
                ProgressView()
            }
        }
        .frame(minWidth: 90, minHeight: 90)
    }
}

private struct RoundtableRow: View {
    let msg: RoundtableMessage
    let showAvatar: Bool
    let showTime: Bool
    let photoURLs: [URL]
    let photoNamespace: Namespace.ID
    let onTapImages: ([URL], Binding<Int>) -> Void
    let onQuote: (String) -> Void
    let onFavorite: () -> Void
    let onDelete: () -> Void
    let theme: AlcoveTheme
    // 0731 她定的：圆桌三个人的头像跟聊天页不通用，各存各的。
    @AppStorage("rtAvatarUser") private var rtAvatarUser = ""
    @AppStorage("rtAvatarAssistant") private var rtAvatarAssistant = ""
    @AppStorage("rtAvatarGpt") private var rtAvatarGpt = ""
    @AppStorage("rtNameUser") private var rtNameUser = "陈霁"
    @AppStorage("rtNameAssistant") private var rtNameAssistant = "陈璟"
    @AppStorage("rtNameGpt") private var rtNameGpt = "何渡"
    @AppStorage("chatFontSize") private var fontSize = 14
    @Environment(\.bubbleGlassStyle) private var glassStyle

    private var avatarImage: UIImage? {
        let raw: String
        switch msg.role {
        case "assistant": raw = rtAvatarAssistant
        case "gpt":       raw = rtAvatarGpt
        default:          raw = rtAvatarUser
        }
        guard !raw.isEmpty else { return nil }
        let parts = raw.split(separator: ",", maxSplits: 1)
        let b64 = parts.count == 2 ? String(parts[1]) : raw
        return Data(base64Encoded: b64).flatMap(UIImage.init(data:))
    }

    private var displayName: String {
        switch msg.role {
        case "assistant": return rtNameAssistant
        case "gpt":       return rtNameGpt
        default:          return rtNameUser
        }
    }

    private var avatarText: String {
        switch msg.role {
        case "assistant": return "璟"
        case "gpt": return "G"
        default: return "霁"
        }
    }

    private var timestamp: String {
        let date = ISO8601DateFormatter.alcove.date(from: msg.ts)
            ?? ISO8601DateFormatter.alcoveFrac.date(from: msg.ts)
        guard let date else { return msg.ts }
        return Self.hm.string(from: date)
    }

    private static let hm: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var avatarTint: Color {
        switch msg.role {
        case "assistant": return Color(red: 0.45, green: 0.60, blue: 0.85)
        case "gpt": return Color(red: 0.35, green: 0.70, blue: 0.58)
        default: return Color(red: 0.88, green: 0.52, blue: 0.65)
        }
    }

    // 她在右边，我和 G老师在左边带头像——跟主聊天页一个规矩（0731 她定的）
    private var isUser: Bool { msg.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if isUser {
                Spacer(minLength: 48)
            } else {
                avatarSlot
            }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                if showAvatar && !isUser {
                    Text(displayName)
                        .font(.system(size: 11))
                        .foregroundColor(theme.textDim)
                }
                if photoURLs.count > 1 {
                    OfficialPhotoGridMessageView(urls: photoURLs, messageID: "rt-\(msg.id)",
                                                 onOpen: onTapImages)
                        .matchedTransitionSource(id: "rt-\(msg.id)", in: photoNamespace)
                } else if msg.attachmentType == "image", let raw = msg.attachmentURL {
                    RoundtableRemoteImage(
                        previewURL: AlcoveAPI.attachmentThumbnailURL(raw),
                        originalURL: AlcoveAPI.attachmentURL(raw)
                    )
                    .frame(maxWidth: msg.attachmentFilename?.hasPrefix("sticker_") == true ? 110 : 220,
                           maxHeight: msg.attachmentFilename?.hasPrefix("sticker_") == true ? 110 : 300)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .matchedTransitionSource(id: "rt-\(msg.id)", in: photoNamespace)
                    .onTapGesture { onTapImages([AlcoveAPI.attachmentURL(raw)], .constant(0)) }
                    .contextMenu {
                        Button {
                            Task { await PhotoLibrarySaver.save(AlcoveAPI.attachmentURL(raw)) }
                        } label: { Label("保存到相册", systemImage: "square.and.arrow.down") }
                    }
                } else if msg.attachmentType == "audio", let raw = msg.attachmentURL {
                    AudioBubble(url: AlcoveAPI.attachmentURL(raw), isUser: isUser, theme: theme)
                } else if let raw = msg.attachmentURL {
                    Link(destination: AlcoveAPI.attachmentURL(raw)) {
                        Label(msg.attachmentFilename ?? "附件", systemImage: "doc.fill")
                            .padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                if !msg.text.isEmpty { bubble }
                if !msg.hiddenFrom.isEmpty {
                    Text(hiddenLabel)
                        .font(.system(size: 10))
                        .foregroundColor(theme.textDim.opacity(0.72))
                        .padding(.horizontal, 12)
                }
                if showTime {
                    Text(timestamp)
                        .font(.system(size: 10, design: .serif))
                        .foregroundColor(theme.timestamp)
                        .padding(.horizontal, 12)
                }
            }
            if isUser { avatarSlot } else { Spacer(minLength: 48) }
        }
    }

    @ViewBuilder private var bubbleBody: some View {
        let line = Text(alcoveMarkdown(msg.text))
            .font(KakaoPackStore.shared.chatFont(CGFloat(fontSize)))
            .lineSpacing(5)
        if theme.isKakao {
            KakaoBubbleView(isUser: isUser, first: showAvatar) {
                line
                    .foregroundColor(isUser ? (theme.textUser ?? theme.text) : (theme.textAI ?? theme.text))
                    .textSelection(.enabled)
            }
        } else if theme.isPaper && !isUser {
            line
                .foregroundColor(theme.textAI ?? theme.text)
                .textSelection(.enabled)
                .padding(.vertical, 2)
        } else {
            line
                .foregroundColor(isUser ? (theme.textUser ?? (theme.isMessages ? .white : theme.text))
                                        : (theme.textAI ?? theme.text))
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isUser ? theme.bubbleUser : theme.bubbleAI))
        }
    }

    private var hiddenLabel: String {
        let roles = Set(msg.hiddenFrom.split(separator: ",").map(String.init))
        let names = [("assistant", "陈璟"), ("gpt", "何渡")]
            .compactMap { roles.contains($0.0) ? $0.1 : nil }
        return names.isEmpty ? "" : "⊘ 挡住了\(names.joined(separator: "、"))"
    }

    private var avatarSlot: some View {
        Group {
            if showAvatar {
                if let img = avatarImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(avatarTint.opacity(0.85))
                        .overlay(
                            Text(avatarText)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                        )
                }
            } else {
                Color.clear
            }
        }
        .frame(width: 30, height: 30)
    }

    // 0925 她要的：圆桌不留玻璃，跟着聊天主题走（像工作室跟主聊天）。
    // Kakao 用主题包的气泡图（一串第一条用带图案的 01 图），信息主题实心圆角，纸页她实心、别人只有字。字体跟全局走。
    private var bubble: some View {
        bubbleBody
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contextMenu {
                Button {
                    UIPasteboard.general.string = msg.text
                } label: { Label("拷贝", systemImage: "doc.on.doc") }
                Button {
                    onQuote(msg.text)
                } label: { Label("引用", systemImage: "quote.bubble") }
                Button {
                    onFavorite()
                } label: { Label("收藏", systemImage: "bookmark") }
                Divider()
                Button(role: .destructive) {
                    onDelete()
                } label: { Label("删除", systemImage: "trash") }
            }
    }
}

// 顶栏那颗玻璃胶囊。RootView 里那个是 private 的，够不着，照着写一份。
private struct RTGlassCapsule: ViewModifier {
    let tint: Color
    let border: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = Capsule()
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(tint, in: shape)
                .overlay(shape.stroke(border, lineWidth: 1))
        }
    }
}

// G老师的实况。她点他头像进来的那个页面——他在想什么、跑了什么命令、
// token 涨到哪儿。数据来自后端在事件到达那一刻另存的一份，
// 不是 /tmp/codex-debug.log（那个每行被砍到 200 字符，是残的）。
private struct RTConsoleLine: Identifiable, Equatable {
    let id: String
    let ts: String
    let kind: String
    let title: String
    let text: String
    let detail: String
    let status: String
    let elapsed: Double
}

private struct CodexMemoryItem: Identifiable, Equatable {
    let id: String
    var title: String
    var content: String
    var tags: [String]
    var importance: Int
    var source: String
    var sourceRef: String
    var updatedAt: String

    init?(_ o: [String: Any]) {
        guard let id = o["id"] as? String else { return nil }
        self.id = id
        title = o["title"] as? String ?? ""
        content = o["content"] as? String ?? ""
        tags = o["tags"] as? [String] ?? []
        importance = o["importance"] as? Int ?? 5
        source = o["source"] as? String ?? "manual"
        sourceRef = o["source_ref"] as? String ?? ""
        updatedAt = o["updated_at"] as? String ?? ""
    }
}

@MainActor
private final class CodexMemoryStore: ObservableObject {
    @Published var items: [CodexMemoryItem] = []
    @Published var loading = false
    @Published var error = ""

    func load(query: String = "") async {
        loading = true
        defer { loading = false }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let path = query.isEmpty ? "/api/codex/memories?limit=100" :
                                   "/api/codex/memories?limit=30&q=\(encoded)"
        do {
            let o = try await AlcoveAPI.getRaw(path)
            items = (o["items"] as? [[String: Any]] ?? []).compactMap(CodexMemoryItem.init)
            error = ""
        } catch { self.error = "记忆没读到  \(error.localizedDescription)" }
    }

    func save(id: String?, title: String, content: String, tags: [String], importance: Int) async -> Bool {
        var body: [String: Any] = ["title": title, "content": content,
                                   "tags": tags, "importance": importance,
                                   "source": "app"]
        let path: String
        if let id { body["id"] = id; path = "/api/codex/memory/update" }
        else { path = "/api/codex/memory/create" }
        do {
            let o = try await AlcoveAPI.postRaw(path, body: body)
            guard o["ok"] as? Bool == true else { return false }
            await load()
            return true
        } catch { self.error = "没保存上  \(error.localizedDescription)"; return false }
    }

    func delete(_ item: CodexMemoryItem) async {
        do {
            _ = try await AlcoveAPI.postRaw("/api/codex/memory/delete", body: ["id": item.id])
            items.removeAll { $0.id == item.id }
        } catch { self.error = "没删掉  \(error.localizedDescription)" }
    }
}

@MainActor
private final class RTConsoleStore: ObservableObject {
    @Published var lines: [RTConsoleLine] = []
    @Published var used = 0
    @Published var limit = 1_000_000
    @Published var percent = 0.0
    @Published var threadId = ""
    @Published var handoffAt = ""
    @Published var busy = false
    @Published var model = ""
    @Published var cwd = ""
    @Published var task = ""
    @Published var reforgeError = ""
    private var poller: Task<Void, Never>?

    func start() {
        Task { await refresh() }
        poller?.cancel()
        poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self?.refresh()
            }
        }
    }

    func stop() { poller?.cancel(); poller = nil }

    func refresh() async {
        if let o = try? await AlcoveAPI.getRaw("/api/roundtable/console") {
            let arr = (o["lines"] as? [[String: Any]]) ?? []
            let new = arr.map {
                RTConsoleLine(id: $0["id"] as? String ?? UUID().uuidString,
                              ts: $0["ts"] as? String ?? "",
                              kind: $0["kind"] as? String ?? "",
                              title: $0["title"] as? String ?? "",
                              text: $0["text"] as? String ?? "",
                              detail: $0["detail"] as? String ?? "",
                              status: $0["status"] as? String ?? "done",
                              elapsed: ($0["elapsed"] as? NSNumber)?.doubleValue ?? 0)
            }
            if new != lines { lines = new }
            model = o["model"] as? String ?? ""
            cwd = o["cwd"] as? String ?? ""
            task = o["task"] as? String ?? ""
        }
        if let o = try? await AlcoveAPI.getRaw("/api/roundtable/thread") {
            used = o["used_tokens"] as? Int ?? 0
            limit = o["limit"] as? Int ?? 1_000_000
            percent = o["percent"] as? Double ?? 0
            threadId = o["thread_id"] as? String ?? ""
            handoffAt = o["handoff_at"] as? String ?? ""
        }
        if let o = try? await AlcoveAPI.getRaw("/api/roundtable/status"),
           let members = o["members"] as? [[String: Any]],
           let me = members.first(where: { ($0["name"] as? String) == "何渡" }) {
            busy = me["busy"] as? Bool ?? false
        }
    }

    // 换线程 = 他从自己写的交接材料重新睁眼
    func reforge() async {
        await refresh()
        guard !busy else {
            reforgeError = "何渡还在说话  等他停下来再换"
            return
        }
        guard !handoffAt.isEmpty else {
            reforgeError = "交接文件还没准备好"
            return
        }
        guard let result = try? await AlcoveAPI.postRaw("/api/roundtable/reforge", body: [:]),
              result["ok"] as? Bool == true else {
            reforgeError = "没换成功  当前线程还留着"
            return
        }
        reforgeError = ""
        await refresh()
    }
}

private struct RTConsoleView: View {
    let theme: AlcoveTheme
    @StateObject private var store = RTConsoleStore()
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReforge = false
    @State private var showMemories = false

    var body: some View {
        ZStack {
            LinearGradient(colors: theme.wallGradient,
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                gauge
                Divider().opacity(0.15)
                ScrollViewReader { p in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 7) {
                            if store.lines.isEmpty {
                                VStack(spacing: 10) {
                                    Image(systemName: "terminal")
                                        .font(.system(size: 24, weight: .light))
                                    Text("还没有运行记录")
                                        .font(.system(size: 13))
                                }
                                .foregroundColor(theme.textDim.opacity(0.55))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                            }
                            ForEach(store.lines) { l in
                                row(l)
                            }
                            Color.clear.frame(height: 1).id("tail")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: store.lines) { _ in
                        withAnimation(.easeOut(duration: 0.18)) {
                            p.scrollTo("tail", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .foregroundColor(theme.text)
        .onAppear { store.start() }
        .onDisappear { store.stop() }
        .sheet(isPresented: $showMemories) {
            CodexMemoryView(theme: theme)
        }
        .alert("换一条线程？", isPresented: $confirmReforge) {
            Button("换", role: .destructive) { Task { await store.reforge() } }
            Button("算了", role: .cancel) {}
        } message: {
            Text(store.busy
                 ? "何渡还在说话  现在不能换"
                 : "他会从自己写的交接材料重新睁眼。交接最后更新：\(handoffDisplay)")
        }
        .alert("没换成", isPresented: Binding(
            get: { !store.reforgeError.isEmpty },
            set: { if !$0 { store.reforgeError = "" } }
        )) { Button("知道了") {} } message: { Text(store.reforgeError) }
    }

    private var gauge: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("何渡")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { showMemories = true } label: {
                    Label("记忆", systemImage: "brain.head.profile")
                        .font(.system(size: 12))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(theme.textDim.opacity(0.12)))
                }
                .buttonStyle(.plain)
                Button { confirmReforge = true } label: {
                    Text(store.busy ? "忙碌中" : "换线程")
                        .font(.system(size: 12))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(theme.textDim.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .disabled(store.busy || store.handoffAt.isEmpty)
                .opacity(store.busy || store.handoffAt.isEmpty ? 0.45 : 1)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(theme.textDim)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.textDim.opacity(0.14))
                    Capsule()
                        .fill(store.percent > 85 ? Color.orange : theme.fyAccent)
                        .frame(width: max(2, g.size.width * store.percent / 100))
                }
            }
            .frame(height: 4)
            HStack(spacing: 6) {
                Text("\(store.used.formatted()) / \(store.limit.formatted())")
                Text("·")
                Text(String(format: "%.1f%%", store.percent))
                if !store.handoffAt.isEmpty {
                    Text("·")
                    Text("交接 " + String(store.handoffAt.suffix(14).prefix(5)))
                }
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(theme.textDim.opacity(0.7))

            HStack(spacing: 8) {
                consoleMeta(icon: "cpu", text: store.model.isEmpty ? "Codex" : store.model)
                consoleMeta(icon: "folder", text: store.cwd.isEmpty ? "~" : store.cwd)
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Circle()
                        .fill(store.busy ? Color.green : theme.textDim.opacity(0.35))
                        .frame(width: 6, height: 6)
                    Text(store.busy ? "运行中" : "空闲")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(store.busy ? .green : theme.textDim)
            }

            if !store.task.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(theme.fyAccent)
                        .padding(.top, 2)
                    Text(store.task)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(theme.textDim.opacity(0.08)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var handoffDisplay: String {
        guard !store.handoffAt.isEmpty else { return "没有交接" }
        return store.handoffAt.replacingOccurrences(of: "T", with: " ").prefix(16).description
    }

    private func row(_ l: RTConsoleLine) -> some View {
        HStack(alignment: .top, spacing: 9) {
            ZStack {
                Circle().fill(tint(l.kind).opacity(0.13))
                Image(systemName: icon(l.kind, l.status))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(tint(l.status == "failed" ? "failed" : l.kind))
            }
            .frame(width: 25, height: 25)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(l.title.isEmpty ? title(l.kind) : l.title)
                        .font(.system(size: 12, weight: .semibold))
                    if l.status == "running" {
                        ProgressView().controlSize(.mini)
                    }
                    Spacer(minLength: 0)
                    Text(l.status == "running" ? String(format: "%.1fs", l.elapsed) : l.ts)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(theme.textDim.opacity(0.48))
                }
                if !l.text.isEmpty {
                    Text(l.text)
                        .font(.system(size: 11.5, design: l.kind == "command" ? .monospaced : .default))
                        .foregroundColor(l.kind == "reasoning" ? theme.textDim.opacity(0.78) : theme.text)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !l.detail.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(l.detail)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(l.status == "failed" ? .red : theme.textDim.opacity(0.82))
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.16)))
                }
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.textDim.opacity(l.status == "running" ? 0.11 : 0.055)))
    }

    private func tint(_ k: String) -> Color {
        switch k {
        case "message": return theme.fyAccent
        case "command", "tool": return .orange
        case "file": return .green
        case "reasoning": return .purple
        case "failed": return .red
        default:   return theme.textDim.opacity(0.4)
        }
    }

    private func icon(_ kind: String, _ status: String) -> String {
        if status == "failed" { return "exclamationmark" }
        switch kind {
        case "reasoning": return "sparkles"
        case "command": return "terminal"
        case "tool": return "wrench.and.screwdriver"
        case "file": return "doc.badge.gearshape"
        case "message": return "text.bubble"
        case "turn": return status == "running" ? "play.fill" : "checkmark"
        default: return "circle.fill"
        }
    }

    private func title(_ kind: String) -> String {
        switch kind {
        case "reasoning": return "Thinking"
        case "command": return "Shell"
        case "tool": return "Tool"
        case "file": return "文件改动"
        case "message": return "回复"
        default: return "Codex"
        }
    }

    private func consoleMeta(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).lineLimit(1)
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(theme.textDim.opacity(0.72))
    }
}

private struct CodexMemoryView: View {
    let theme: AlcoveTheme
    @StateObject private var store = CodexMemoryStore()
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var editing: CodexMemoryItem?
    @State private var adding = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: theme.wallGradient, startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                if store.loading && store.items.isEmpty { ProgressView() }
                else if store.items.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "还没有记忆" : "没有找到",
                                           systemImage: "brain.head.profile",
                                           description: Text(query.isEmpty ? "何渡以后记下的东西会放在这里" : "换句话再找找"))
                } else {
                    List {
                        ForEach(store.items) { item in
                            Button { editing = item } label: { memoryRow(item) }
                                .buttonStyle(.plain)
                                .listRowBackground(theme.textDim.opacity(0.06))
                                .swipeActions {
                                    Button(role: .destructive) { Task { await store.delete(item) } } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .foregroundColor(theme.text)
            .navigationTitle("何渡的记忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                }
            }
            .searchable(text: $query, prompt: "按意思搜索")
            .onSubmit(of: .search) { Task { await store.load(query: query) } }
            .onChange(of: query) { value in if value.isEmpty { Task { await store.load() } } }
            .task { await store.load() }
            .sheet(isPresented: $adding) {
                CodexMemoryEditor(theme: theme, item: nil) { title, content, tags, importance in
                    let ok = await store.save(id: nil, title: title, content: content,
                                              tags: tags, importance: importance)
                    if ok { adding = false }
                }
            }
            .sheet(item: $editing) { item in
                CodexMemoryEditor(theme: theme, item: item) { title, content, tags, importance in
                    let ok = await store.save(id: item.id, title: title, content: content,
                                              tags: tags, importance: importance)
                    if ok { editing = nil }
                }
            }
            .alert("记忆库出了点问题", isPresented: Binding(
                get: { !store.error.isEmpty }, set: { if !$0 { store.error = "" } }
            )) { Button("知道了") {} } message: { Text(store.error) }
        }
    }

    private func memoryRow(_ item: CodexMemoryItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title.isEmpty ? String(item.content.prefix(24)) : item.title)
                .font(.system(size: 15, weight: .semibold)).lineLimit(1)
            Text(item.content).font(.system(size: 13)).foregroundColor(theme.textDim).lineLimit(3)
            HStack {
                if !item.tags.isEmpty { Text(item.tags.joined(separator: " · ")) }
                Spacer()
                Text("重要度 \(item.importance)")
            }
            .font(.system(size: 10)).foregroundColor(theme.textDim.opacity(0.65))
        }.padding(.vertical, 5)
    }
}

private struct CodexMemoryEditor: View {
    let theme: AlcoveTheme
    let item: CodexMemoryItem?
    let onSave: (String, String, [String], Int) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var content: String
    @State private var tags: String
    @State private var importance: Int
    @State private var saving = false

    init(theme: AlcoveTheme, item: CodexMemoryItem?,
         onSave: @escaping (String, String, [String], Int) async -> Void) {
        self.theme = theme; self.item = item; self.onSave = onSave
        _title = State(initialValue: item?.title ?? "")
        _content = State(initialValue: item?.content ?? "")
        _tags = State(initialValue: item?.tags.joined(separator: ", ") ?? "")
        _importance = State(initialValue: item?.importance ?? 5)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("标题（可以不填）", text: $title)
                Section("记忆") { TextEditor(text: $content).frame(minHeight: 180) }
                TextField("标签，用逗号分开", text: $tags)
                Stepper("重要度  \(importance)", value: $importance, in: 1...10)
                if let item {
                    Section("来源") {
                        Text(item.source + (item.sourceRef.isEmpty ? "" : " · " + item.sourceRef))
                            .font(.footnote).foregroundColor(theme.textDim)
                    }
                }
            }
            .navigationTitle(item == nil ? "添一条记忆" : "编辑记忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中" : "保存") {
                        saving = true
                        Task {
                            await onSave(title, content,
                                tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                                importance)
                            saving = false
                        }
                    }.disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                }
            }
        }
    }
}

// 圆桌设置。她定的三样：改壁纸、改三个人头像、改三个人名字。
// 头像跟聊天页不通用，名字也只在圆桌里生效。
private struct RTSettingsView: View {
    @ObservedObject var store: RoundtableStore
    let theme: AlcoveTheme
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rtAvatarUser") private var avUser = ""
    @AppStorage("rtAvatarAssistant") private var avMe = ""
    @AppStorage("rtAvatarGpt") private var avGpt = ""
    @AppStorage("rtNameUser") private var nameUser = "陈霁"
    @AppStorage("rtNameAssistant") private var nameMe = "陈璟"
    @AppStorage("rtNameGpt") private var nameGpt = "何渡"
    @AppStorage("rtWallpaper") private var wallpaper = ""
    @AppStorage("rtWallpaperHaven") private var wallpaperHaven = ""
    @AppStorage("rtWallpaperMidnight") private var wallpaperMidnight = ""
    @AppStorage("rtWallpaperPaper") private var wallpaperPaper = ""
    @AppStorage("rtWallpaperPaperDark") private var wallpaperPaperDark = ""
    @AppStorage("alcoveTheme") private var themeName = "haven"
    // 0731 bug：原来四行共用一个 picking，每行各挂一个 onChange，
    // 她选一次图四个监听全触发，那张壁纸同时被写进三个人的头像。
    // 现在每个位置一个独立的 item，谁变了改谁。
    @State private var pickUser: PhotosPickerItem?
    @State private var pickMe: PhotosPickerItem?
    @State private var pickGpt: PhotosPickerItem?
    @State private var pickWall: PhotosPickerItem?

    var body: some View {
        ZStack {
            LinearGradient(colors: theme.wallGradient,
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text("圆桌设置")
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .light))
                                .foregroundColor(theme.textDim)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                    }

                    section("三个人") {
                        personRow(role: "user", name: $nameUser, data: $avUser,
                                  pick: $pickUser, fallback: "霁")
                        personRow(role: "assistant", name: $nameMe, data: $avMe,
                                  pick: $pickMe, fallback: "璟")
                        personRow(role: "gpt", name: $nameGpt, data: $avGpt,
                                  pick: $pickGpt, fallback: "渡")
                    }

                    section("屏蔽") {
                        blockToggle("屏蔽陈璟", role: "assistant", isOn: store.blockAssistant)
                        blockToggle("屏蔽何渡", role: "gpt", isOn: store.blockGpt)
                    }

                    section("壁纸") {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(theme.textDim.opacity(0.12))
                                .frame(width: 54, height: 78)
                                .overlay {
                                    if let img = decode(activeWallpaper) {
                                        Image(uiImage: img).resizable().scaledToFill()
                                            .clipShape(RoundedRectangle(cornerRadius: 10,
                                                                        style: .continuous))
                                    } else {
                                        Text("默认")
                                            .font(.system(size: 11))
                                            .foregroundColor(theme.textDim)
                                    }
                                }
                            VStack(alignment: .leading, spacing: 8) {
                                PhotosPicker(selection: $pickWall, matching: .images) {
                                    label("换一张")
                                }
                                .onChange(of: pickWall) { load($0, into: "wall") }
                                if !activeWallpaper.isEmpty {
                                    Button { clearActiveWallpaper() } label: { label("恢复默认") }
                                        .buttonStyle(.plain)
                                }
                            }
                            Spacer()
                        }
                    }
                }
                .padding(18)
            }
        }
        .foregroundColor(theme.text)
    }

    private func blockToggle(_ title: String, role: String, isOn: Bool) -> some View {
        Toggle(title, isOn: Binding(
            get: { isOn },
            set: { enabled in Task { await store.setBlock(role: role, enabled: enabled) } }
        ))
        .font(.system(size: 14))
        .tint(theme.fyAccent)
    }

    private func section<C: View>(_ title: String,
                                  @ViewBuilder body: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundColor(theme.fyAccent.opacity(0.8))
            body()
        }
    }

    private func personRow(role: String, name: Binding<String>,
                           data: Binding<String>,
                           pick: Binding<PhotosPickerItem?>,
                           fallback: String) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(theme.textDim.opacity(0.14))
                .frame(width: 42, height: 42)
                .overlay {
                    if let img = decode(data.wrappedValue) {
                        Image(uiImage: img).resizable().scaledToFill().clipShape(Circle())
                    } else {
                        Text(fallback)
                            .font(.system(size: 14, design: .serif))
                            .foregroundColor(theme.textDim)
                    }
                }
            TextField("名字", text: name)
                .font(.system(size: 14))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(theme.textDim.opacity(0.10)))
            PhotosPicker(selection: pick, matching: .images) {
                label("换")
            }
            .onChange(of: pick.wrappedValue) { load($0, into: role) }
        }
    }

    private func label(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 12))
            .foregroundColor(theme.text)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(theme.textDim.opacity(0.12)))
    }

    private func decode(_ s: String) -> UIImage? {
        guard !s.isEmpty else { return nil }
        let parts = s.split(separator: ",", maxSplits: 1)
        let b64 = parts.count == 2 ? String(parts[1]) : s
        return Data(base64Encoded: b64).flatMap(UIImage.init(data:))
    }

    private var activeWallpaper: String {
        switch themeName {
        case "midnight", "imessage-dark": return wallpaperMidnight
        case "paper": return wallpaperPaper
        case "paper-dark": return wallpaperPaperDark
        default: return wallpaperHaven.isEmpty ? wallpaper : wallpaperHaven
        }
    }

    private func setActiveWallpaper(_ value: String) {
        switch themeName {
        case "midnight", "imessage-dark": wallpaperMidnight = value
        case "paper": wallpaperPaper = value
        case "paper-dark": wallpaperPaperDark = value
        default:
            wallpaperHaven = value
            wallpaper = ""
        }
    }

    private func clearActiveWallpaper() { setActiveWallpaper("") }

    private func load(_ item: PhotosPickerItem?, into target: String) {
        guard let item else { return }
        Task {
            guard let raw = try? await item.loadTransferable(type: Data.self),
                  let img = UIImage(data: raw) else { return }
            // 头像压到 240、壁纸压到 1200，别把 UserDefaults 撑爆
            let maxW: CGFloat = target == "wall" ? 1200 : 240
            let scale = min(1, maxW / max(img.size.width, img.size.height))
            let size = CGSize(width: img.size.width * scale,
                              height: img.size.height * scale)
            let out = UIGraphicsImageRenderer(size: size).image { _ in
                img.draw(in: CGRect(origin: .zero, size: size))
            }
            guard let jpeg = out.jpegData(compressionQuality: 0.82) else { return }
            let b64 = "data:image/jpeg;base64," + jpeg.base64EncodedString()
            await MainActor.run {
                switch target {
                case "user":      avUser = b64
                case "assistant": avMe = b64
                case "gpt":       avGpt = b64
                case "wall":      setActiveWallpaper(b64)
                default: break
                }
            }
        }
    }
}

// 打字框那层玻璃。跟顶栏胶囊不是一个形状，圆角 28。
private struct RTInputGlass: ViewModifier {
    let tint: Color
    let border: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(tint, in: shape)
                .overlay(shape.stroke(border, lineWidth: 1))
        }
    }
}

// 圆桌只需要从现有贴纸库选择；选中后按图片上传到圆桌记录。
private struct RoundtableStickerPicker: View {
    let onSelect: (Sticker) -> Void
    @State private var stickers: [Sticker] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 12)], spacing: 12) {
                    ForEach(stickers) { sticker in
                        Button { onSelect(sticker) } label: {
                            CachedImage(url: AlcoveAPI.stickerURL(sticker.url)) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(height: 82)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .navigationTitle("贴纸")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { stickers = (try? await AlcoveAPI.stickers()) ?? [] }
    }
}
