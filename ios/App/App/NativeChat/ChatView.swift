import SwiftUI
import Translation
import WebKit
import PhotosUI
import Photos
import AVFoundation
import UniformTypeIdentifiers
import UIKit

struct ChatView: View {
    @Binding var thinkingEnabled: Bool
    let thinkingKnown: Bool
    let switchingThinking: Bool
    let onToggleThinking: () -> Void
    /// 0822 信息主题：真顶栏从 RootView 递进来挂到 safeAreaBar(.top)。
    /// 真机验出来：底部挂真打字框有渐进模糊，顶部挂一块透明空气没有——系统只给真栏画。
    var messagesTopBar: (() -> AnyView)? = nil

    @StateObject private var store = ChatStore()
    @StateObject private var wallpaperStore = ChatWallpaperStore()
    @State private var draft = ""
    @State private var previousDraft = ""
    @State private var handlingReturn = false
    @State private var selectedQuote: String?
    @State private var showStickers = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var pendingImages: [(thumb: UIImage, data: Data, ext: String)] = []
    // 选表情不立刻飞出去：先进待发区，还能继续打字或者撤掉（教程坑 1）
    @State private var pendingSticker: Sticker?
    // 0818 她要的：链接一贴进打字框就自动抽出来变成待发卡片，她还能接着打字一起发
    @State private var pendingLink: String?
    @State private var photoViewer: PhotoViewerSelection?
    @StateObject private var recorder = VoiceRecorder()
    @State private var atBottom = true
    // 0907 她定的：翻着历史点打字框不许把她拽回最新，只有本来就在最新那儿
    // 才让消息跟着键盘抬起来。难点是键盘顶上来那一瞬底部锚点会被盖住、
    // atBottom 会假性变 false，所以在焦点刚来、键盘还没动之前先拍个快照。
    @State private var wasAtBottomWhenFocused = true
    @State private var followLiveOutput = true
    @State private var historyJumpInProgress = false
    // Every delayed auto-tail captures this generation. History navigation
    // advances it so startup/keyboard/layout callbacks queued by the previous
    // screen can no longer drag an old-message jump back to the latest chat.
    @State private var tailScrollGeneration = 0
    @State private var olderPagingArmed = false
    @State private var showCamera = false
    @State private var showDocPicker = false
    @State private var showPhotoPicker = false
    @Namespace private var photoTransition
    @State private var previewImage: UIImage?
    @State private var inputBarHeight: CGFloat = 90
    // 打字框底边在屏幕坐标里的位置；底部那条「点一下回到最新」的窄条按它让路
    @State private var inputBarBottom: CGFloat = .infinity
    @State private var scrollKick = 0
    @State private var showMusicPlayer = false
    @State private var showModelPicker = false
    @State private var showMoreModels = false
    // 0822 她要的：换模型面板分 cli / sdk 两页（顶上一行当前通道），CLI 补 effort，SDK 模型/effort 存后端 config
    @State private var modelPanel = "cli"
    @State private var modelPanelResolved = false
    @State private var cliEffort = ""
    @State private var sdkModel = ""
    @State private var sdkEffort = ""
    @State private var switchingEffort = false
    private let effortLevels = ["low", "medium", "high", "xhigh", "max"]
    @State private var switchingModel = false
    @State private var modelSwitchError = ""
    @State private var showMiniTerminal = false
    @State private var showSDKShadow = false
    @State private var showChannelPanel = false
    @State private var activeChatChannel = "cli"
    // 0819 她点名的跳转高亮：从搜索/收藏跳过来的那条闪一下再退
    @State private var flashTS: String?
    @State private var paragraphSelectionMode = false
    @State private var selectedParagraphIDs: Set<UUID> = []
    // 0906 她要的：图和字分开勾。这份记的是「哪些消息的图被勾了」，存组头那条的号
    @State private var selectedPhotoIDs: Set<UUID> = []
    @State private var showParagraphDeleteConfirmation = false
    @ObservedObject private var music = MusicModel.shared
    @FocusState private var inputFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @AppStorage("imsgShowProcess") private var showProcessDots = true   // 0822 iMessage 主题：过程线圆点开关
    @AppStorage("chatFontSize") private var chatFontSize = 14
    // 0909 她要的：气泡之间的间距自己调。原来写死 6pt
    @AppStorage("chatBubbleGap") private var chatBubbleGap = 6.0
    @AppStorage("wallStamp") private var wallStamp = 0.0
    @AppStorage("bubbleGlassStrength") private var bubbleGlassStrength = 56.81
    @AppStorage("bubbleGlassDispersion") private var bubbleGlassDispersion = 0.39
    @AppStorage("bubbleGlassRimWidth") private var bubbleGlassRimWidth = 0.28
    @AppStorage("bubbleGlassMagnify") private var bubbleGlassMagnify = 0.0
    @AppStorage("bubbleGlassBlur") private var bubbleGlassBlur = 0.10
    @AppStorage("bubbleGlassSize") private var bubbleGlassSize = 174.33
    /// 0902 信息主题调色板：她在设置页改一项，msgPaletteStamp 一变这里就重算
    @AppStorage(MessagesPalette.stampKey) private var paletteStamp = 0.0
    private var theme: AlcoveTheme { _ = paletteStamp; return .named(themeName) }
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
    private var safeBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 0
    }
    private var miniTerminalHeight: CGFloat {
        min(310, UIScreen.main.bounds.height * 0.29)
    }
    // 底部所有悬浮层只认这一份高度。输入框会随长文字／图片预览
    // 实测变化；音乐条固定 62pt，再留 10pt 呼吸缝。
    /// 0902：打字框上方的迷你播放条退休了（小唱片浮在屏幕边上替它），不再占地方
    private var musicBarClearance: CGFloat { 0 }
    private var bottomChromeHeight: CGFloat { inputBarHeight + musicBarClearance }

    /// 「点屏幕最底回到最新」那条窄条能有多高：只吃打字框底边到屏幕最底之间那点空隙，
    /// 封顶 14pt，一个像素都不许压到打字框上。还没量到（.infinity）就当没空隙、
    /// 窄条不出现 —— 宁可少一个手势，也不能再把加号和输入框吃掉一次。
    private var tailTapStripHeight: CGFloat {
        guard inputBarBottom.isFinite else { return 0 }
        return max(0, min(14, UIScreen.main.bounds.maxY - inputBarBottom))
    }

    /// 该不该跟着滚到最新：人在底部，或者这次打字框是在底部时点开的。
    private var shouldFollowTail: Bool {
        atBottom || (inputFocused && wasAtBottomWhenFocused)
    }

    var body: some View {
        GeometryReader { root in
            ZStack {
                // The visible wall and every bubble lens share this same
                // prepared image and coordinate system.
                ChatWallpaperRenderer(descriptor: wallpaperStore.descriptor)
                    .ignoresSafeArea()

                if store.loading {
                    ProgressView("回家中…")
                        .tint(theme.textDim)
                } else {
                    messageList
                }
            }
            .coordinateSpace(name: "alcoveChatRoot")
            .environment(\.chatWallpaperDescriptor, wallpaperStore.descriptor)
            .environment(\.chatWallpaperViewportSize, root.size)
            .environment(\.bubbleGlassStyle, bubbleGlassStyle)
        }
        .sheet(isPresented: $showStickers) { stickerSheet }
        .sheet(isPresented: $showMusicPlayer) {
            MusicPlayerSheet(model: music)
                .presentationDetents([.fraction(0.72)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showModelPicker, onDismiss: { showMoreModels = false }) {
            modelPickerSheet
                .task { await loadModelPanelState() }
                .presentationDetents([.fraction(0.72), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showSDKShadow) {
            SDKShadowChatView()
        }
        .sheet(isPresented: $showChannelPanel) {
            ChatChannelPanel(activeChannel: $activeChatChannel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCamera) {
            CameraView { image in
                if let prepared = UploadImage.prepare(image) {
                    pendingImages.append(prepared)
                }
            }
        }
        .sheet(isPresented: $showDocPicker) {
            DocumentPicker { urls in
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url) {
                        let name = url.lastPathComponent
                        store.sendImage(data: data, filename: name, caption: "")
                    }
                }
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoLibraryPicker(maxCount: 9) { images in
                for img in images {
                    if let prepared = UploadImage.prepare(img) {
                        pendingImages.append(prepared)
                    }
                }
            }
        }
        .fullScreenCover(item: $photoViewer) { selection in
            PhotoPageViewer(selection: selection, namespace: photoTransition) { photoViewer = nil }
        }
        .fullScreenCover(item: $previewImage) { img in
            LocalImageViewer(image: img) { previewImage = nil }
        }
        .onAppear {
            wallpaperStore.refresh(
                themeName: themeName,
                theme: theme,
                wallStamp: wallStamp
            )
            store.start()
            music.startRemotePolling()
            Task {
                if let obj = try? await AlcoveAPI.getRaw("/api/sdk-shadow/status") {
                    activeChatChannel = obj["channel"] as? String ?? "cli"
                }
            }
        }
        .onChange(of: themeName) { newThemeName in
            wallpaperStore.refresh(
                themeName: newThemeName,
                theme: .named(newThemeName),
                wallStamp: wallStamp
            )
        }
        .onChange(of: wallStamp) { newStamp in
            wallpaperStore.refresh(
                themeName: themeName,
                theme: theme,
                wallStamp: newStamp
            )
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { store.refresh() }
        }
        .onChange(of: photoItems) { items in
            guard !items.isEmpty else { return }
            photoItems = []
            Task {
                // 微信式叠加：选完先进预览条，跟文字一起发
                // HEIC 等照片统一转 JPEG；带透明的图走 PNG（见 UploadImage）
                for item in items {
                    if let raw = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: raw),
                       let prepared = UploadImage.prepare(img) {
                        pendingImages.append(prepared)
                    }
                }
            }
        }
    }

    // MARK: 消息列表

    private var messageList: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: chatBubbleGap) {
                        ForEach(Array(store.messages.enumerated()), id: \.element.id) { idx, msg in
                            chatMessageRow(at: idx, message: msg)
                                .background(
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .fill(theme.fyAccent.opacity(flashTS == msg.ts ? 0.17 : 0))
                                        .padding(.horizontal, -7)
                                        .padding(.vertical, -3)
                                        .animation(.easeInOut(duration: 0.42), value: flashTS))
                                .onAppear {
                                    guard idx == 0, olderPagingArmed else { return }
                                    olderPagingArmed = false
                                    store.loadOlder()
                                }
                                .onDisappear {
                                    guard idx == 0 else { return }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { olderPagingArmed = true }
                                }
                        }
                        if let live = store.live, (live.active || live.finishing), !live.isEmpty {
                            StreamingAssistantRow(state: live, theme: theme, fontSize: chatFontSize)
                                .id("live-\(live.turnID)")
                        }
                        if store.isTyping {
                            TypingIndicator(tool: store.currentTool,
                                            line: store.typingLine,
                                            name: UserDefaults.standard.string(forKey: "assistantName") ?? "陈璟",
                                            theme: theme)
                                .id("typing")
                        }
                        // 信息主题：输入栏和迷你条都挂在安全区那一栏里，系统自己会推，
                        // 列表这边一点都不用替它们留高
                        Color.clear.frame(height: (theme.isMessages ? 0 : bottomChromeHeight) + 12
                                          + (showMiniTerminal ? miniTerminalHeight + 18 : 0))
                        Color.clear.frame(height: 1).id("tail")
                            .onAppear {
                                atBottom = true
                                if store.isViewingHistory && !historyJumpInProgress {
                                    Task {
                                        await store.returnToLatest()
                                        scrollToTail(proxy, delays: [0.05, 0.2], animated: false)
                                    }
                                }
                            }
                            .onDisappear { atBottom = false }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, theme.isMessages ? 8 : 52)
                }
                // 0822 她递的图纸：iMessage 的上下渐进模糊是 iOS 26 系统画的 scroll edge effect，
                // 自动混下层颜色、日夜自适配，不许用固定色渐变去模拟。
                // 关键两条：① 栏要用 safeAreaBar 挂（safeAreaInset 不触发底部模糊）；② 列表不翻转（本来就没翻）。
                // 顶栏本体在 RootView 浮着，这里只挂一条同高的透明 bar 把「顶部有栏」告诉系统。
                // 0823 她拍板：顶部放弃渐进模糊，改成纸页主题那种顶部渐隐（edgeFadeMask 顶段同一条曲线，120 高）。
                // 信息主题底是纯色，所以用主题底色做渐变盖上去和纸页的遮罩观感一致，又不碰滚动区（底部系统效果不动）。
                .overlay(alignment: .top) {
                    if theme.isMessages {
                        let bg = theme.wallGradient.first ?? (theme.isDark ? Color.black : Color.white)
                        LinearGradient(stops: [
                            .init(color: bg, location: 0),
                            .init(color: bg, location: 0.15),
                            .init(color: bg.opacity(0.7), location: 0.4),
                            .init(color: bg.opacity(0.3), location: 0.65),
                            .init(color: bg.opacity(0), location: 1.0),
                        ], startPoint: .top, endPoint: .bottom)
                        .frame(height: 120)
                        .frame(maxWidth: .infinity)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                    }
                }
                .safeAreaBar(edge: .top, spacing: 0) {
                    if theme.isMessages, let bar = messagesTopBar {
                        bar().frame(height: 52, alignment: .top)
                    }
                }
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    if theme.isMessages && !paragraphSelectionMode {
                        // 迷你条跟打字框叠成同一栏交给系统量高度。
                        // 之前它浮在 ZStack 里，那一层的底既不是屏幕底也不是打字框上沿，
                        // 垫多了空一条，垫少了直接把打字框盖住（0826 两回都踩了）
                        VStack(spacing: 8) {
                            // 0902：迷你播放条退休，歌在放的时候是屏幕边上的小唱片（RootView 管）
                            floatingInput
                        }
                    }
                }
                .scrollEdgeEffectStyle(theme.isMessages ? .soft : .automatic, for: .bottom)
                .scrollEdgeEffectHidden(theme.isMessages, for: .top)   // 顶部不用系统效果，走上面纸页式渐隐
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture { inputFocused = false }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4).onChanged { _ in
                        if store.live?.active == true { followLiveOutput = false }
                    }
                )
                .modifier(EdgeFadeMaskModifier(enabled: !theme.isMessages, mask: edgeFadeMask))   // 信息主题不罩遮罩，别挡系统效果
                // 0914：罩与不罩是两条不同的分支，切到／切出信息主题时 SwiftUI 会把这个
                // ScrollView 当成新视图重建，位置掉回最顶上（她原来报的那个 bug）。
                // 重建发生在这一帧，下一帧再把锚点拉回最新一条。
                .onChange(of: theme.isMessages) { _ in
                    DispatchQueue.main.async { proxy.scrollTo("tail", anchor: .bottom) }
                }

                if paragraphSelectionMode {
                    paragraphSelectionToolbar
                } else if !theme.isMessages {
                    floatingInput
                }

                // 0902：迷你播放条退休，歌在放的时候是屏幕边上的小唱片（RootView 管）

                // 0907 她定的：右下角那颗「回到底部」圆按钮退休，改成
                // 点屏幕最底下那条空隙（打字框下面、home 横条那一带）直接回到最新 ——
                // 跟 iOS 点最顶上状态栏回到顶是同一个手感，左右对称。
                // 只吃点一下；上滑还是系统的返回主屏手势，两者不打架。
                // 0909 修一：contentShape 必须贴着那条窄条写，撑满屏幕的 frame 只能
                // 挂在最外面。写反了等于给整页盖一张透明板，列表滑不动、按钮点不着。
                // 0909 修二：这条窄条压在打字框上（信息主题的打字框是 safeAreaBar 挂的，
                // 属于列表那一层，画在这条之前，所以这条永远盖着它）——加号、输入框、
                // 语音键全被吃掉。补回退休那颗圆按钮原有的两个出现条件：
                // 只在「人不在最新」时才存在，语音卡片在时让开。
                // 在最新的时候（也就是打字的时候）它压根不存在，打字框完整可用；
                // 翻历史时才铺开，那正是需要一键回到最新的时候。
                // 0909 修三：她要「就算不在最新也能点打字框」。所以窄条不再自己定高度，
                // 改成量出打字框底边到屏幕最底之间那点空隙，只长在空隙里，最多 14pt。
                if !atBottom && store.pendingVoice == nil && tailTapStripHeight > 4 {
                    Color.clear
                        .frame(height: tailTapStripHeight)
                        .contentShape(Rectangle())
                        .onTapGesture { jumpToTail(proxy) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }

                if !showMiniTerminal && !paragraphSelectionMode {
                    ClawdPet(store: store) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                            showMiniTerminal = true
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 12)
                    .padding(.bottom, bottomChromeHeight + 8)
                }
            }
            // 终端画在上层；消息流用等高底部占位做出键盘式避让。
            .overlay(alignment: .bottom) {
                if showMiniTerminal {
                    TerminalView(onDismiss: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                            showMiniTerminal = false
                        }
                    }, mini: true)
                    .frame(height: miniTerminalHeight)
                    .padding(.horizontal, 16)
                    .padding(.bottom, bottomChromeHeight + 14)
                    .transition(.scale(scale: 0.92, anchor: .bottomTrailing).combined(with: .opacity))
                }
            }
            .onAppear {
                atBottom = true
                scrollToTail(proxy, delays: [0, 0.08, 0.25, 0.6, 1.1], animated: false)
            }
            .onChange(of: inputFocused) { f in
                if f {
                    // 焦点刚到、键盘还没顶上来，这一刻的 atBottom 才是真的
                    wasAtBottomWhenFocused = atBottom
                    guard atBottom else { return }
                    scrollToTail(proxy, delays: [0.05, 0.25, 0.5], animated: true)
                } else {
                    guard wasAtBottomWhenFocused else { return }
                    scrollToTail(proxy, delays: [0.1, 0.35], animated: true)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                // 0904：工作室那些整页盖在上面时弹的键盘不是我的，别跟着滚
                guard AlcoveNotify.shared.chatVisible else { return }
                guard shouldFollowTail else { return }
                scrollToTail(proxy, delays: [0, 0.12, 0.3], animated: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .alcoveHouseClosed)) { _ in
                // 0904 她报的：整页盖着时键盘把列表撑高又收走，我不在屏幕上没跟着回落。
                // 回来时本来就在底部的话，无动画校正回底；她在翻历史就不动
                guard atBottom else { return }
                scrollToTail(proxy, delays: [0.05, 0.4], animated: false)
            }
            .onChange(of: store.messages.count) { _ in
                // loadAround replaces the latest page with an old 240-row window.
                // At that instant `atBottom` can still be stale-true, so the normal
                // auto-follow used to queue tail scrolls at 0/0.15/0.4s and race the
                // requested history target. History navigation owns the scroll until
                // it has centered the target.
                guard !historyJumpInProgress, !store.isViewingHistory else { return }
                guard shouldFollowTail else { return }
                scrollToTail(proxy, delays: [0, 0.15, 0.4], animated: true)
            }
            .onChange(of: store.loading) { loading in
                if !loading {
                    olderPagingArmed = false
                    scrollToTail(proxy, delays: [0.05, 0.3, 0.8, 1.5], animated: false)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { olderPagingArmed = true }
                }
            }
            .onChange(of: store.isTyping) { t in
                if t { followLiveOutput = shouldFollowTail }
                if shouldFollowTail {
                    scrollToTail(proxy, delays: [0, 0.2, 0.5], animated: true)
                }
            }
            .onChange(of: liveLayoutKey) { _ in
                guard followLiveOutput else { return }
                scrollToTail(proxy, delays: [0], animated: false)
            }
            .onChange(of: inputBarHeight) { _ in
                if shouldFollowTail {
                    scrollToTail(proxy, delays: [0.05, 0.3], animated: true)
                }
            }
            .onChange(of: music.nowPlaying?.id) { _ in
                if shouldFollowTail {
                    scrollToTail(proxy, delays: [0.05, 0.3], animated: true)
                }
            }
            .onChange(of: showMiniTerminal) { _ in
                // 像键盘避让：占位变化后把最新消息送到终端正上方。
                scrollToTail(proxy, delays: [0, 0.12, 0.32], animated: true)
            }
            .onChange(of: scrollKick) { _ in
                if shouldFollowTail {
                    // 展开 thinking/activity 时内容本身已经在做 0.15s 动画。
                    // 再连跑三次滚尾会让整页先上再下，真机看起来像闪一下。
                    // 等布局落稳后无动画校正一次就够了。
                    scrollToTail(proxy, delays: [0.18], animated: false)
                }
            }
            // 0904 她报的：晨报 / Inside 卡展开几屏再收起，内容一帧缩没，滚动位置还停在空处，页面白掉要拉很久。
            // 卡收起时发这个通知，等布局落稳后无动画把那张卡拉回屏幕中间；跑两次是给 LazyVStack 重排一个机会。
            .onReceive(NotificationCenter.default.publisher(for: .alcoveRecenterMessage)) { note in
                guard let id = note.object as? UUID else { return }
                for delay in [0.05, 0.3] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        var t = Transaction(); t.disablesAnimations = true
                        withTransaction(t) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .alcoveJumpToMessage)) { note in
                guard let ts = note.object as? String else { return }
                Task {
                    historyJumpInProgress = true
                    tailScrollGeneration &+= 1
                    olderPagingArmed = false
                    if !store.messages.contains(where: { $0.ts == ts }) { await store.loadAround(ts) }
                    if let target = store.messages.first(where: { $0.ts == ts }) {
                        flashTS = ts
                        // One owner, one movement. The competing auto-tail schedule is
                        // suppressed above while the old page is being installed.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                            withAnimation(.easeOut(duration: 0.20)) {
                                proxy.scrollTo(target.id, anchor: .center)
                            }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                            if flashTS == ts { flashTS = nil }
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                        historyJumpInProgress = false
                        olderPagingArmed = true
                    }
                }
            }
        }
        .confirmationDialog(
            "隐藏选中的 \(selectedBlockCount) 块内容？",
            isPresented: $showParagraphDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { deleteSelectedParagraphs() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只从当前页面移走；刷新或重进 App 后会重新出现，原始数据不删除。")
        }
    }

    private var liveLayoutKey: String {
        guard let live = store.live else { return "" }
        return "\(live.turnID)\u{1f}\(live.say)\u{1f}\(live.pendingSay)\u{1f}\(live.timeline.count)"
    }

    private var paragraphSelectionToolbar: some View {
        HStack(spacing: 18) {
            Button("取消") { leaveParagraphSelection() }
                .foregroundColor(theme.textDim)
            Text("已选 \(selectedBlockCount) 块")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.text)
            Spacer()
            Button {
                favoriteSelectedParagraphs()
            } label: {
                Label("收藏", systemImage: "star")
            }
            .disabled(nothingSelected)
            Button(role: .destructive) {
                showParagraphDeleteConfirmation = true
            } label: {
                Label("删除", systemImage: "trash")
            }
            .disabled(nothingSelected)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 18)
        .frame(height: 54)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(theme.glassBorder, lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.bottom, max(safeBottom, 8))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private var selectedBlockCount: Int {
        selectedParagraphIDs.count + selectedPhotoIDs.count
    }

    private var nothingSelected: Bool {
        selectedParagraphIDs.isEmpty && selectedPhotoIDs.isEmpty
    }

    /// 图的圈勾的是「这一组图」：多图是一组多条记录串起来画的，收就得整组收。
    private func photoGroupMessages(headUID: UUID) -> [ChatMessage] {
        guard let index = store.messages.firstIndex(where: { $0.uid == headUID }) else { return [] }
        let head = store.messages[index]
        guard head.inlineImages.isEmpty, let key = head.photoBatchKey else { return [head] }
        var group: [ChatMessage] = []
        var i = index
        while i < store.messages.count, store.messages[i].photoBatchKey == key {
            group.append(store.messages[i])
            i += 1
        }
        return group
    }

    private func leaveParagraphSelection() {
        paragraphSelectionMode = false
        selectedParagraphIDs.removeAll()
        selectedPhotoIDs.removeAll()
    }

    /// 0906 她定的：收藏不管勾了哪块，一律收整条、带图。
    private func favoriteSelectedParagraphs() {
        let picked = store.messages.filter {
            selectedParagraphIDs.contains($0.uid) || selectedPhotoIDs.contains($0.uid)
        }
        store.favoriteMessages(picked)
        leaveParagraphSelection()
    }

    private func deleteSelectedParagraphs() {
        let textTargets = store.messages.filter { selectedParagraphIDs.contains($0.uid) }
        let photoTargets = selectedPhotoIDs.flatMap { photoGroupMessages(headUID: $0) }
        store.hideMessagePartsTemporarily(text: textTargets, photo: photoTargets)
        leaveParagraphSelection()
    }

    /// 0818 她要的：思绪永远在我这一轮最上面，动作轨迹挂在思绪下面。
    /// 「一轮」= 连续的我方消息、中间没有她说话、相邻间隔不超过三分钟
    /// （表情/卡片是我用 CLI 单独发的，没有 turn_id，只能按这个规矩归到一起）。
    /// 轮首拿整轮第一段思绪 + 整轮去重后的动作；那段思绪的原主人自己不再显示。
    private struct Hoist {
        var thought: String? = nil
        var activity: [ActivityItem] = []
        var suppressThought = false
        var suppressActivity = false
    }

    private func hoistFor(index: Int) -> Hoist {
        let msgs = store.messages
        guard index < msgs.count, msgs[index].role == "assistant" else { return Hoist() }
        // 新时间线已经把 think / tool 精确挂回原段落，绝不能再走旧的“提到轮首”。
        if !msgs[index].segments.isEmpty { return Hoist() }
        guard let turnID = msgs[index].turnID, !turnID.isEmpty else { return Hoist() }
        var head = index
        while head > 0, msgs[head - 1].role == "assistant",
              msgs[head - 1].turnID == turnID { head -= 1 }
        var tail = index
        while tail + 1 < msgs.count, msgs[tail + 1].role == "assistant",
              msgs[tail + 1].turnID == turnID { tail += 1 }
        if head == tail { return Hoist() }          // 单条一轮，照旧
        // 0821 晚：这一轮里只要有一条带新时间线（segments），整轮都不走老的「提到轮首」。
        // 不然半路投进来的表情包 / 图片 / 卡片没有 segments、又排在最前，被当成轮首
        // 再提一遍思绪和工具栏，她屏上同一轮出现两套（20:40 那轮的截图）。
        if (head...tail).contains(where: { !msgs[$0].segments.isEmpty }) { return Hoist() }

        // 整轮第一段手写思绪是谁的
        var thoughtOwner: Int? = nil
        for i in head...tail {
            if let t = msgs[i].thinking?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                thoughtOwner = i; break
            }
        }
        if index == head {
            var seen = Set<String>()
            var merged: [ActivityItem] = []
            // 整条时间线都要：动作、中间说的话、中间的思绪——她说以前合在一起时
            // 不会漏掉我跑任务中间说过的话，分开之后这些不能丢。
            for i in head...tail {
                for item in msgs[i].activity {
                    let key = item.kind + "|" + item.content + "@" + String(format: "%.1f", item.t)
                    if seen.insert(key).inserted { merged.append(item) }
                }
            }
            merged.sort { $0.t < $1.t }
            var h = Hoist()
            if let owner = thoughtOwner, owner != head { h.thought = msgs[owner].thinking }
            h.activity = merged
            return h
        }
        var h = Hoist()
        h.suppressThought = (thoughtOwner == index)
        h.suppressActivity = true
        return h
    }

    @ViewBuilder
    private func chatMessageRow(at index: Int, message: ChatMessage) -> some View {
        if !isPhotoGroupContinuation(at: index) {
            let previous = index > 0 ? store.messages[index - 1] : nil
            let photos = message.inlineImages.isEmpty
                ? chatPhotoGroup(startingAt: index)
                : message.inlineImages.map(AlcoveAPI.attachmentURL)
            let groupEnd = index + max(photos.count, 1) - 1
            let next = groupEnd + 1 < store.messages.count ? store.messages[groupEnd + 1] : nil
            let recall = message.role == "assistant" && previous?.role == "user"
                ? store.recall(forUserText: previous?.text ?? "")
                : nil
            let selectionEnd = message.inlineImages.isEmpty
                ? min(groupEnd, store.messages.count - 1) : index
            let rowSelectionIDs = Set(store.messages[index...selectionEnd].map(\.uid))
            let rowSelected = !rowSelectionIDs.isEmpty
                && rowSelectionIDs.isSubset(of: selectedParagraphIDs)
            // 0906 她要的：既有图又有字的，图一个圈、字一个圈；
            // 其余（纯图、纯字、语音、表情、卡片）照旧整行一个圈
            let rowHasPhoto = !photos.isEmpty
                || (message.isImage && !(message.attachmentUrl ?? "").isEmpty)
            let splittable = rowHasPhoto && !message.displayText.isEmpty
                && !message.isAudio && !message.isSticker

            let divided = needsDivider(prev: previous, cur: message)
            if divided {
                if theme.isMessages {
                    MessagesTimeDivider(date: message.date, color: theme.dividerColor)
                } else {
                    TimeDivider(date: message.date, color: theme.dividerColor)
                }
            }
            let hoist = hoistFor(index: index)
            // 0822 她要的：我一个人连着发几轮，轮和轮之间拉开一点，不然看混。
            // 只在「上一条也是我、换了轮次号、中间没有她说话、也没有时间分割线」时拉。
            let newSoloTurn: Bool = {
                guard !divided, let prev = previous,
                      prev.role == "assistant", message.role == "assistant",
                      let a = prev.turnID, !a.isEmpty,
                      let b = message.turnID, !b.isEmpty else { return false }
                return a != b
            }()
            Group {
            if message.msgType == "pat_outgoing" || message.msgType == "pat_incoming" {
                // 0827 拍一拍：居中一行小字。她拍我常规、我拍她加粗，黑底白底各一套灰
                PatLine(text: message.text,
                        strong: message.msgType == "pat_incoming",
                        isDark: theme.isDark)
            } else if message.msgType == "divider" && message.source == "dream" {
                // 0822 她定的：做梦之后聊天页只落这一道线，梦本身在梦面板
                DreamDivider(text: message.text, date: message.date, color: theme.dividerColor)
            } else if message.msgType == "divider" && message.source == "music" {
                // 任务#1308 她定的：切歌落一条居中小分割线，不是对话气泡
                MusicChatDivider(text: message.text, date: message.date, color: theme.dividerColor)
            } else if message.msgType == "divider" {
                // 0822 她要的：切通道留一道线，跟时间分割一个样子
                ChannelDivider(text: message.text, color: theme.dividerColor)
            } else {
                let renderedRow = MessageRow(
                    msg: message,
                    sticker: message.stickerId.flatMap(store.sticker(for:)),
                    theme: theme,
                    fontSize: chatFontSize,
                    showTime: isGroupTail(cur: store.messages[groupEnd], next: next),
                    recall: recall,
                    hoistedThought: hoist.thought,
                    hoistedActivity: hoist.activity,
                    suppressOwnThought: hoist.suppressThought,
                    suppressOwnActivity: hoist.suppressActivity,
                    photoURLs: photos,
                    photoNamespace: photoTransition,
                    onTapImages: { urls, selectedIndex in
                        photoViewer = PhotoViewerSelection(
                            urls: urls,
                            index: selectedIndex,
                            sourceID: "chat-\(message.id)"
                        )
                    },
                    onDelete: { store.deleteMessage(message) },
                    onFavorite: { store.favoriteMessage(message) },
                    wholeTurnText: wholeTurnText(for: message),
                    paragraphSelectionMode: paragraphSelectionMode && splittable,
                    paragraphSelected: selectedParagraphIDs.contains(message.uid),
                    photoSelected: selectedPhotoIDs.contains(message.uid),
                    onTogglePhotoSelection: {
                        if selectedPhotoIDs.contains(message.uid) {
                            selectedPhotoIDs.remove(message.uid)
                        } else {
                            selectedPhotoIDs.insert(message.uid)
                        }
                    },
                    onBeginParagraphSelection: {
                        paragraphSelectionMode = true
                        selectedParagraphIDs.formUnion(rowSelectionIDs)
                        inputFocused = false
                    },
                    onToggleParagraphSelection: {
                        if selectedParagraphIDs.contains(message.uid) {
                            selectedParagraphIDs.remove(message.uid)
                        } else {
                            selectedParagraphIDs.insert(message.uid)
                        }
                    },
                    onQuote: { text in
                        selectedQuote = text
                        inputFocused = true
                    },
                    onResend: { text in store.sendText(text) },
                    onPlayMusic: { song in Task { await music.play(song) } },
                    onContentChange: { scrollKick += 1 }
                )
                if paragraphSelectionMode && !splittable {
                    Button {
                        if rowSelected { selectedParagraphIDs.subtract(rowSelectionIDs) }
                        else { selectedParagraphIDs.formUnion(rowSelectionIDs) }
                    } label: {
                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: rowSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20, weight: .regular))
                                .foregroundColor(rowSelected ? theme.fyAccent : theme.textDim)
                                .frame(width: 28, height: 44)
                            renderedRow.allowsHitTesting(false)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    renderedRow
                }
            }
            }
            .padding(.top, newSoloTurn ? 22 : 0)
            .id(message.id)
        }
    }

    private func wholeTurnText(for message: ChatMessage) -> String {
        guard message.role == "assistant",
              let turnID = message.turnID, !turnID.isEmpty else {
            return message.displayText
        }
        return store.messages
            .filter { $0.role == "assistant" && $0.turnID == turnID && !$0.displayText.isEmpty }
            .map(\.displayText)
            .joined(separator: "\n\n")
    }

    /// 回到最新一条。翻着历史的时候先把最新那页拉回来再落底。
    private func jumpToTail(_ proxy: ScrollViewProxy) {
        followLiveOutput = true
        if store.isViewingHistory {
            Task {
                await store.returnToLatest()
                scrollToTail(proxy, delays: [0.05, 0.2], animated: false)
            }
        } else {
            withAnimation { proxy.scrollTo("tail", anchor: .bottom) }
        }
    }

    private func scrollToTail(
        _ proxy: ScrollViewProxy,
        delays: [Double],
        animated: Bool
    ) {
        // While an old window is visible, only the explicit “back to latest”
        // path may re-enable auto-follow after returnToLatest has completed.
        guard !historyJumpInProgress, !store.isViewingHistory else { return }
        let generation = tailScrollGeneration
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard generation == tailScrollGeneration,
                      !historyJumpInProgress, !store.isViewingHistory else { return }
                if animated {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("tail", anchor: .bottom)
                    }
                } else {
                    proxy.scrollTo("tail", anchor: .bottom)
                }
            }
        }
    }

    private func needsDivider(prev: ChatMessage?, cur: ChatMessage) -> Bool {
        guard let prev else { return true }
        // 三套主题统一：安静超过 20 分钟再插一条时间分割。
        return cur.date.timeIntervalSince(prev.date) > 1200
    }

    // PWA 同款：一轮的最后一个气泡才落时间（下一条换人或隔了 2 分钟）
    private func isGroupTail(cur: ChatMessage, next: ChatMessage?) -> Bool {
        guard let next else { return true }
        if let turnID = cur.turnID, !turnID.isEmpty {
            return next.turnID != turnID
        }
        if next.role != cur.role { return true }
        return next.date.timeIntervalSince(cur.date) > 120
    }

    private func chatPhotoGroup(startingAt index: Int) -> [URL] {
        guard index < store.messages.count,
              let key = store.messages[index].photoBatchKey else { return [] }
        var urls: [URL] = []
        var i = index
        while i < store.messages.count,
              store.messages[i].photoBatchKey == key,
              let raw = store.messages[i].attachmentUrl {
            urls.append(AlcoveAPI.attachmentURL(raw))
            i += 1
        }
        return urls.count > 1 ? urls : []
    }

    private func isPhotoGroupContinuation(at index: Int) -> Bool {
        guard index > 0, let key = store.messages[index].photoBatchKey else { return false }
        return store.messages[index - 1].photoBatchKey == key
    }

    // MARK: alpha淡出mask（不用背景色渐变，内容本身按alpha淡出）

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
            .frame(height: bottomChromeHeight + 12)
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !pendingImages.isEmpty || pendingSticker != nil || pendingLink != nil
    }

    // PWA .chat-input-capsule 同款：大胶囊两行，粉描边，透底毛玻璃
    @ViewBuilder private var floatingInput: some View {
        legacyFloatingInput
    }

    private var legacyFloatingInput: some View {
        VStack(spacing: 4) {
            if store.connectionError {
                Text("连接不上小屋，重试中…")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            VStack(spacing: 0) {
                if let quote = selectedQuote {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(theme.textDim)
                        Text(quote)
                            .font(.system(size: 12))
                            .foregroundColor(theme.textDim)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button { selectedQuote = nil } label: {
                            // 0905 她报的叉不掉：图标 11 热区 44，跟别的叉一个待遇（光有 frame 不铺 contentShape 点不中）
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(theme.textDim)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 8)
                    .padding(.top, 9)
                    .padding(.bottom, 5)
                    Divider().opacity(0.35).padding(.horizontal, 12)
                }
                // 待发链接卡：贴进来的链接在这儿预览，✕ 就把链接原样塞回打字框
                if let link = pendingLink {
                    HStack(alignment: .top, spacing: 6) {
                        LinkPreviewCard(url: link, theme: theme, isUser: true)
                        Button {
                            handlingReturn = true
                            pendingLink = nil
                            let restored = draft.isEmpty ? link : draft + " " + link
                            draft = restored
                            previousDraft = restored
                            DispatchQueue.main.async { handlingReturn = false }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22)).foregroundColor(.secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
                }
                // 待发表情：一张就够，再点一次面板会换掉它
                if let stk = pendingSticker {
                    HStack(spacing: 8) {
                        CachedImage(url: AlcoveAPI.stickerURL(stk.url)) { img in
                            img.resizable().scaledToFit()
                        } placeholder: { Color(.systemGray6) }
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        Text(stk.name.isEmpty ? "表情" : stk.name)
                            .font(.system(size: 11)).foregroundColor(.secondary)
                        Spacer()
                        Button { pendingSticker = nil } label: {
                            // 图标 22，热区 44：她说叉叉难点到
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22)).foregroundColor(.secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 2)
                }
                // PWA .chat-preview 同款：待发图片叠加条，可单张删除
                if !pendingImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(pendingImages.enumerated()), id: \.offset) { idx, item in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: item.thumb)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .onTapGesture { previewImage = item.thumb }
                                    Button {
                                        pendingImages.remove(at: idx)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(.white)
                                            .shadow(radius: 2)
                                            .frame(width: 40, height: 40)
                                            .contentShape(Rectangle())
                                    }
                                    .offset(x: 6, y: -6)
                                }
                            }
                        }
                        .padding(.init(top: 8, leading: 12, bottom: 4, trailing: 12))
                    }
                }
                if let pv = store.pendingVoice { voicePreviewCard(pv) }
                if theme.isMessages { messagesComposerRow } else { classicComposerBody }
            }
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.clear)
                    .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .onTapGesture {
                        guard !recorder.isRecording else { return }
                        inputFocused = true
                    }
            }
            .modifier(InteractiveInputGlassModifier(fallbackTint: theme.capsuleTint, enabled: !theme.isMessages))
            .shadow(color: .black.opacity(theme.isMessages ? 0 : 0.05), radius: 14, x: 0, y: 2)
            .padding(.horizontal, theme.isMessages ? 0 : 14)
        }
        .padding(.bottom, 0)
        .background(GeometryReader { geo in
            Color.clear
                .preference(key: InputBarHeightKey.self, value: geo.size.height)
                // 0909：底边报到屏幕坐标里，给底部那条窄条算可用空隙用
                .preference(key: InputBarBottomKey.self, value: geo.frame(in: .global).maxY)
        })
        .onPreferenceChange(InputBarHeightKey.self) { inputBarHeight = $0 }
        .onPreferenceChange(InputBarBottomKey.self) { inputBarBottom = $0 }
    }

    // 0902 她定的语音卡片：录完不直接发，先在打字框上方看转文字和情绪；
    // 垃圾桶删掉重说，发送键才真的发。发出去的气泡只带转文字，情绪只给他。
    private func voicePreviewCard(_ pv: PendingVoice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform").font(.system(size: 13, weight: .semibold))
                Text(String(format: "语音 %d:%02d", pv.seconds / 60, pv.seconds % 60))
                    .font(.system(size: 12.5, weight: .semibold))
                if let a = pv.analysis, !a.engine.isEmpty, a.engine != "whisper-large-v3" {
                    Text("备用听写").font(.system(size: 11)).opacity(0.7)
                }
                Spacer()
                Button { store.discardPendingVoice() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .foregroundColor(theme.textDim)
            if let err = pv.error {
                Text(err).font(.system(size: 14)).foregroundColor(theme.textDim)
            } else if let a = pv.analysis {
                Text(a.text)
                    .font(.system(size: 15.5))
                    .foregroundColor(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if pv.emotionPending {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("在听语气…").font(.system(size: 12.5)).foregroundColor(theme.textDim)
                    }
                } else if a.hasEmotion {
                    HStack(alignment: .top, spacing: 6) {
                        Text(a.emotionZh)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(theme.text)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(theme.textDim.opacity(0.16)))
                        Text(a.hint)
                            .font(.system(size: 12.5))
                            .foregroundColor(theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("听写中…").font(.system(size: 14)).foregroundColor(theme.textDim)
                }
            }
        }
        .padding(.init(top: 12, leading: 14, bottom: 12, trailing: 10))
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.045))
        )
        .padding(.init(top: 8, leading: 12, bottom: 4, trailing: 12))
    }

    // 加号菜单：经典输入栏和「信息」输入栏共用同一份
    private var composerPlusMenu: some View {
        Menu {
            Button { showStickers = true } label: {
                Label("表情", systemImage: "face.smiling")
            }
            Button { showPhotoPicker = true } label: {
                Label("从相册选择", systemImage: "photo.on.rectangle")
            }
            Button { showCamera = true } label: {
                Label("拍照或录像", systemImage: "camera")
            }
            Button { showDocPicker = true } label: {
                Label("选取文件", systemImage: "doc")
            }
            if theme.isMessages {
                // 0822 她定的：iMessage 主题下模型、通道、过程线开关都收进加号里
                Divider()
                if !store.modelLabel.isEmpty {
                    Button { showModelPicker.toggle() } label: {
                        Label("模型 · \(store.modelLabel)", systemImage: "cpu")
                    }
                }
                Button { showChannelPanel = true } label: {
                    Label("通道 · \(activeChatChannel.uppercased())", systemImage: "arrow.left.arrow.right")
                }
                Toggle(isOn: $showProcessDots) {
                    Label("过程线（思绪、脚印、记忆）", systemImage: "circle.dotted")
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(theme.textDim)
                .frame(width: theme.isMessages ? 40 : 36, height: theme.isMessages ? 40 : 36)
                .modifier(MessagesGlassModifier(
                    face: theme.isDark ? Color(red: 28/255, green: 28/255, blue: 30/255) : Color.white,
                    line: theme.isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06),
                    shadow: Color.black.opacity(theme.isDark ? 0.35 : 0.10),
                    circle: true, enabled: theme.isMessages))
                .background((theme.isMessages ? Color.clear : theme.glassTint.opacity(theme.isDark ? 0.64 : 0.82)), in: Circle())
        }
    }

    // 经典输入栏（玻璃大胶囊）：文本框在上、按钮一排在下
    private var classicComposerBody: some View {
        VStack(spacing: 0) {
                    if recorder.isRecording {
                        HStack(spacing: 10) {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Text(String(format: "%d:%02d", recorder.seconds / 60, recorder.seconds % 60))
                                .font(.system(size: 15).monospacedDigit())
                                .foregroundColor(theme.text)
                            Text("录音中… 按■停下，先看字再发")
                                .font(.system(size: 14))
                                .foregroundColor(theme.textDim)
                            Spacer()
                        }
                        .padding(.init(top: 16, leading: 14, bottom: 4, trailing: 14))
                    } else {
                        TextField("", text: $draft,
                                  prompt: theme.isMessages
                                    ? Text("信息").font(.system(size: 15.5))
                                    : Text("ring the chime …").font(.system(size: 15.5, design: .serif)).italic(),
                                  axis: .vertical)
                            .focused($inputFocused)
                            .lineLimit(1...5)
                            .font(.system(size: 15.5))
                            .tint(Color(uiColor: .systemGray3))
                            .padding(.init(top: 16, leading: 14, bottom: 12, trailing: 14))
                            .contentShape(Rectangle())
                            .onChange(of: draft) { value in handleDraftChange(value) }
                    }
                    HStack(spacing: 2) {
                        if recorder.isRecording {
                            Button { recorder.cancel() } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 15, weight: .light))
                                    .foregroundColor(theme.textDim)
                                    .frame(width: 36, height: 36)
                            }
                            Spacer()
                        } else {
                            composerPlusMenu
                            if !store.modelLabel.isEmpty && !theme.isMessages {
                                Button {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                        showModelPicker.toggle()
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        if switchingModel { ProgressView().controlSize(.mini) }
                                        Text(store.modelLabel)
                                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                                    }
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(theme.textLight)
                                    .padding(.horizontal, 12).frame(height: 36)
                                    .background(theme.glassTint.opacity(theme.isDark ? 0.72 : 0.92),
                                                in: Capsule())
                                    .overlay(Capsule().stroke(theme.glassBorder, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .disabled(switchingModel)
                            }
                            if !theme.isMessages { Button { showChannelPanel = true } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.left.arrow.right")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(activeChatChannel.uppercased())
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundColor(theme.textLight)
                                .padding(.horizontal, 10)
                                .frame(height: 36)
                                .background(theme.glassTint.opacity(theme.isDark ? 0.72 : 0.92), in: Capsule())
                                .overlay(Capsule().stroke(theme.glassBorder, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("切换 CLI 或 SDK 通道，当前 \(activeChatChannel.uppercased())") }
                            Spacer()
                        }
                        Button(action: performDynamicComposerAction) {
                            ZStack(alignment: .topTrailing) {
                                // 0822 她要的「打断回复」：他在回的时候这颗变成官方那种停止键（圆里一个小方块），
                                // 平时照旧：没字是语音、有字是发送。
                                // 0902：录音中显示停止键——按下去是停下来去听写、出卡片，不是发送
                                Image(systemName: isGenerating ? "stop.fill"
                                      : recorder.isRecording ? "stop.fill"
                                      : (canSend || store.heldCount > 0 || store.pendingVoice != nil) ? "arrow.up" : "waveform")
                                .font(.system(size: isGenerating ? 13 : 17, weight: .semibold))
                                .contentTransition(.symbolEffect(.replace))
                                .animation(.easeInOut(duration: 0.18), value: isGenerating)
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(
                                    LinearGradient(
                                        colors: [theme.sendTop, theme.sendBottom],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.2),
                                        radius: 4, y: 2)
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
    }

    // 0822 她要的 iMessage 同款输入栏：三件各自独立——左边一个圆加号、中间细边框单行框、
    // 框里右边平时是话筒，有字／在回的时候换成蓝圆（发送／停止）。没有大玻璃胶囊。
    private var messagesComposerRow: some View {
        let line = theme.isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
        let face = theme.isDark ? Color(red: 28/255, green: 28/255, blue: 30/255) : Color.white
        let shadow = Color.black.opacity(theme.isDark ? 0.35 : 0.10)
        let showBlue = isGenerating || canSend || recorder.isRecording || store.heldCount > 0 || store.pendingVoice != nil
        return HStack(alignment: .bottom, spacing: 10) {
            if recorder.isRecording {
                // 0822 她报的：录音时叉点不掉。玻璃贴在图标上把点击吞了——
                // 改成玻璃当按钮的背景，热区明确给成整个圆。
                Button(action: { recorder.cancel() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(theme.textDim)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .background(
                    Color.clear.frame(width: 40, height: 40)
                        .modifier(MessagesGlassModifier(face: face, line: line, shadow: shadow, circle: true))
                        .allowsHitTesting(false)
                )
            } else {
                composerPlusMenu
            }
            HStack(alignment: .center, spacing: 4) {
                if recorder.isRecording {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text(String(format: "%d:%02d", recorder.seconds / 60, recorder.seconds % 60))
                        .font(.system(size: 15).monospacedDigit())
                        .foregroundColor(theme.text)
                    Text("录音中… 按■停下").font(.system(size: 14)).foregroundColor(theme.textDim)
                    Spacer(minLength: 0)
                } else {
                    // 0823 她报的：信息主题按回车不攒气泡。病根是这个框没写 axis: .vertical，
                    // 单行框的回车走 submit 不往 draft 里塞换行，handleDraftChange 的
                    // 「新值 == 旧值 + \n」永远对不上。改成跟纸页那边同一套：竖轴 + 1...5 行。
                    TextField("", text: $draft, prompt: Text("信息").font(.system(size: 16)),
                              axis: .vertical)
                        .focused($inputFocused)
                        .lineLimit(1...5)
                        .font(.system(size: 16))
                        .tint(Color(uiColor: .systemBlue))
                        .onChange(of: draft) { value in handleDraftChange(value) }
                }
                Button(action: performDynamicComposerAction) {
                    ZStack(alignment: .topTrailing) {
                        // 0902：录音中显示停止键——按下去是停下来去听写、出卡片，不是发送
                        Image(systemName: isGenerating ? "stop.fill"
                              : recorder.isRecording ? "stop.fill"
                              : (canSend || store.heldCount > 0 || store.pendingVoice != nil) ? "arrow.up" : "mic")
                            .font(.system(size: isGenerating ? 12 : (showBlue ? 15 : 17), weight: showBlue ? .semibold : .regular))
                            .contentTransition(.symbolEffect(.replace))
                            .animation(.easeInOut(duration: 0.18), value: isGenerating)
                            .foregroundColor(showBlue ? .white : theme.textDim)
                            .frame(width: 30, height: 30)
                            .background(showBlue ? Color(uiColor: .systemBlue) : Color.clear, in: Circle())
                        if store.heldCount > 0 {
                            Text("\(store.heldCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .frame(minWidth: 14, minHeight: 14)
                                .background(Color(uiColor: .systemBlue), in: Capsule())
                                .offset(x: 3, y: -3)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.vertical, 5)
            .frame(minHeight: 40)
            .modifier(MessagesGlassModifier(face: face, line: line, shadow: shadow, circle: false))
            .contentShape(Capsule())
            .onTapGesture { if !recorder.isRecording { inputFocused = true } }
        }
        .padding(.init(top: 6, leading: 12, bottom: 4, trailing: 12))
    }

    private func holdCurrentDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        // 0905 她报的：攒气泡时引用不跟着走。攒的这条就把引用带上（outgoingText 拼完会清掉引用条）
        store.sendHold(outgoingText(text))
        inputFocused = true
    }

    private func handleDraftChange(_ value: String) {
        // Programmatic restores (notably dismissing a pending link card) must
        // update the text field without immediately being extracted as a new
        // pending card again.
        guard !handlingReturn else {
            previousDraft = value
            return
        }
        // 贴进来一个链接：抽出去做成待发卡，打字框留给她说话
        if pendingLink == nil, value.contains("http"),
           let range = value.range(of: #"https?://[^\s<>"'）)]+"#, options: .regularExpression) {
            var link = String(value[range])
            while let last = link.last, ".,;:!?，。！？、".contains(last) { link.removeLast() }
            if link.count > 12 {
                pendingLink = link
                LinkCardStore.shared.load(link)
                let rest = value.replacingOccurrences(of: link, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                handlingReturn = true
                draft = rest
                previousDraft = rest
                DispatchQueue.main.async { handlingReturn = false }
                return
            }
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
        holdCurrentDraft()
        previousDraft = ""
        DispatchQueue.main.async {
            handlingReturn = false
            previousDraft = draft
        }
    }

    /// 他正在生成（打字中或实时预览带活着）且她没在录音 → 发送键当停止键用
    private var isGenerating: Bool {
        (store.isTyping || store.live?.active == true) && !recorder.isRecording
    }

    private func stopGenerating() {
        store.isTyping = false
        store.live = nil
        Task { _ = try? await AlcoveAPI.postRaw("/api/chat-stop", body: [:]) }
    }

    private func performDynamicComposerAction() {
        guard !store.stagingImages else { return }
        if isGenerating {
            stopGenerating()
            return
        }
        if recorder.isRecording {
            // 0902：停止录音不再直接发，先去听写 + 判情绪，出一张卡片给她看
            let secs = recorder.seconds
            if let data = recorder.stopAndTake() { store.analyzeVoice(data: data, seconds: secs) }
            return
        }
        if store.pendingVoice != nil, store.voiceAnalyzing { return }   // 字还没出来，等一下
        if store.pendingVoice != nil, !canSend {
            store.sendPendingVoice(followedByText: false)
            return
        }
        guard canSend else {
            if store.heldCount > 0 {
                store.flushHeld()
                return
            }
            recorder.start()
            return
        }
        var text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        if let link = pendingLink {
            // 她说的话在前、链接另起一行在后：气泡里是话，卡片长在下面
            pendingLink = nil
            text = text.isEmpty ? link : text + "\n" + link
        }
        if store.pendingVoice != nil {
            // 语音先走，服务端攒着；上传落定再发后面这些，跟语音一起进他那边
            store.sendPendingVoice(followedByText: true) { dispatchComposed(text) }
            return
        }
        dispatchComposed(text)
    }

    private func dispatchComposed(_ text: String) {
        if let stk = pendingSticker {
            pendingSticker = nil
            store.sendSticker(stk, text: outgoingText(text))
            return
        }
        if !pendingImages.isEmpty {
            let images = pendingImages.map { ($0.data, $0.ext) }
            pendingImages = []
            store.sendImages(images, caption: outgoingText(text))
        } else {
            store.sendText(outgoingText(text))
        }
    }

    private func outgoingText(_ body: String) -> String {
        guard let quote = selectedQuote?.trimmingCharacters(in: .whitespacesAndNewlines),
              !quote.isEmpty else { return body }
        selectedQuote = nil
        return "[QUOTE]\(quote)[/QUOTE]\n\(body)"
    }

    private struct ClaudeModelOption: Identifiable {
        let id: String
        let label: String
        let note: String
    }

    private var claudeModels: [ClaudeModelOption] {[
        .init(id: "claude-fable-5", label: "Fable 5", note: "需要 usage credits"),
        .init(id: "claude-opus-5", label: "Opus 5", note: "最强推理"),
        .init(id: "claude-sonnet-5", label: "Sonnet 5", note: "日常更快"),
        .init(id: "claude-haiku-4-5", label: "Haiku 4.5", note: "最快"),
        .init(id: "claude-opus-4-8", label: "Opus 4.8", note: ""),
        .init(id: "claude-opus-4-7", label: "Opus 4.7", note: ""),
        .init(id: "claude-opus-4-6", label: "Opus 4.6", note: ""),
        .init(id: "claude-sonnet-4-6", label: "Sonnet 4.6", note: "")
    ]}

    private var modelPickerSheet: some View {
        VStack(spacing: 18) {
            HStack {
                Button {
                    if showMoreModels {
                        withAnimation(.easeInOut(duration: 0.18)) { showMoreModels = false }
                    } else {
                        showModelPicker = false
                    }
                } label: {
                    Image(systemName: showMoreModels ? "chevron.left" : "xmark")
                        .font(.system(size: 18, weight: .light))
                        .foregroundColor(theme.text)
                        .frame(width: 44, height: 44)
                        .background(theme.glassTint.opacity(0.52), in: Circle())
                        .overlay(Circle().stroke(theme.glassBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()
                Text(showMoreModels ? "More models" : "Select model")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(theme.text)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }

            // 当前通道一行：左边写着现在主聊天走的是谁，右边 cli / sdk 切着看两页（样式不变，只多这一行）
            HStack(spacing: 10) {
                Text("当前通道")
                    .font(.system(size: 12))
                    .foregroundColor(theme.textDim)
                Text(activeChatChannel.uppercased())
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(theme.text)
                Spacer()
                HStack(spacing: 2) {
                    ForEach(["cli", "sdk"], id: \.self) { p in
                        Button {
                            modelPanel = p; modelPanelResolved = true; showMoreModels = false; modelSwitchError = ""
                        } label: {
                            Text(p)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(modelPanel == p ? theme.text : theme.textDim)
                                .padding(.horizontal, 11).padding(.vertical, 5)
                                .background(modelPanel == p ? theme.fyCard.opacity(0.95) : .clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(theme.glassTint.opacity(0.4), in: Capsule())
                .overlay(Capsule().stroke(theme.glassBorder, lineWidth: 1))
            }
            .padding(.horizontal, 4)

            if modelPanel == "sdk" {
                if showMoreModels {
                    modelRows(Array(claudeModels.dropFirst(4)))
                } else {
                    modelRows(Array(claudeModels.prefix(4)))
                    moreModelsButton
                }
                effortRow(current: sdkEffort, hint: "SDK 下一句生效，不换 session") { lvl in setSDKEffort(lvl) }
            } else if showMoreModels {
                modelRows(Array(claudeModels.dropFirst(4)))
            } else {
                modelRows(Array(claudeModels.prefix(4)))
                moreModelsButton
                effortRow(current: cliEffort, hint: "等于在命令行敲 /effort") { lvl in setCLIEffort(lvl) }

                Button(action: onToggleThinking) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("thinking quietly")
                                .font(.system(size: 16, weight: .medium))
                            Text("让陈璟把思考留在心里")
                                .font(.system(size: 11))
                                .foregroundColor(theme.textDim)
                        }
                        Spacer()
                        if switchingThinking {
                            ProgressView().controlSize(.small)
                                .frame(width: 42)
                        } else {
                            Capsule()
                                .fill(thinkingEnabled ? theme.sendTop : theme.textDim.opacity(0.22))
                                .frame(width: 42, height: 24)
                                .overlay(alignment: thinkingEnabled ? .trailing : .leading) {
                                    Circle().fill(.white).frame(width: 20, height: 20).padding(2)
                                }
                                .opacity(thinkingKnown ? 1 : 0.45)
                                .animation(.spring(response: 0.24, dampingFraction: 0.8), value: thinkingEnabled)
                        }
                    }
                    .foregroundColor(theme.text)
                    .padding(.horizontal, 18)
                    .frame(height: 66)
                    .background(theme.fyCard.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(switchingThinking || !thinkingKnown)
            }

            if !modelSwitchError.isEmpty {
                Text(modelSwitchError)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .foregroundColor(theme.text)
    }

    private var moreModelsButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { showMoreModels = true }
        } label: {
            HStack {
                Text("More models")
                    .font(.system(size: 16, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.textDim)
            }
            .foregroundColor(theme.text)
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(theme.fyCard.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // effort 一行五档：跟命令行 /effort 一样的五个档，当前档亮着
    private func effortRow(current: String, hint: String, onPick: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("effort").font(.system(size: 16, weight: .medium))
                Spacer()
                if switchingEffort { ProgressView().controlSize(.small) }
                else { Text(current.isEmpty ? "未知" : current).font(.system(size: 12, design: .monospaced)).foregroundColor(theme.textDim) }
            }
            HStack(spacing: 6) {
                ForEach(effortLevels, id: \.self) { lvl in
                    Button { onPick(lvl) } label: {
                        Text(lvl)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(current == lvl ? .white : theme.text)
                            .frame(maxWidth: .infinity).frame(height: 30)
                            .background(current == lvl ? theme.sendTop : theme.textDim.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(hint).font(.system(size: 11)).foregroundColor(theme.textDim)
        }
        .foregroundColor(theme.text)
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(theme.fyCard.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .disabled(switchingEffort)
    }

    // 当前通道 / CLI effort / SDK 模型+effort 一起拉
    @MainActor private func loadModelPanelState() async {
        if let ch = try? await AlcoveAPI.sdkChannel() {
            activeChatChannel = ch
            if !modelPanelResolved { modelPanel = ch; modelPanelResolved = true }
        }
        if let obj = try? await AlcoveAPI.getRaw("/api/cc/model") {
            cliEffort = obj["effort"] as? String ?? ""
        }
        if let obj = try? await AlcoveAPI.getRaw("/api/sdk-shadow/status"),
           let cfg = obj["config"] as? [String: Any] {
            sdkModel = cfg["sdk_model"] as? String ?? ""
            sdkEffort = cfg["sdk_effort"] as? String ?? ""
        }
    }

    private var sdkModelLabel: String {
        // config 里存的是 "claude-opus-5[1m]" 这种，对回列表里的 label
        let base = sdkModel.replacingOccurrences(of: "[1m]", with: "")
        return claudeModels.first { $0.id == base }?.label ?? base
    }

    private func switchSDKModel(_ option: ClaudeModelOption) {
        guard !switchingModel else { return }
        switchingModel = true; modelSwitchError = ""
        Task {
            do {
                let obj = try await AlcoveAPI.postRaw("/api/sdk-shadow/config", body: ["sdk_model": option.id + "[1m]"])
                guard obj["ok"] as? Bool != false else { throw NSError(domain: "SDKModel", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: obj["error"] as? String ?? "没存上"]) }
                sdkModel = option.id + "[1m]"
                showModelPicker = false
            } catch { modelSwitchError = error.localizedDescription }
            switchingModel = false
        }
    }

    private func setSDKEffort(_ lvl: String) {
        guard lvl != sdkEffort, !switchingEffort else { return }
        switchingEffort = true; modelSwitchError = ""
        Task {
            do {
                _ = try await AlcoveAPI.postRaw("/api/sdk-shadow/config", body: ["sdk_effort": lvl])
                sdkEffort = lvl
            } catch { modelSwitchError = error.localizedDescription }
            switchingEffort = false
        }
    }

    private func setCLIEffort(_ lvl: String) {
        guard lvl != cliEffort, !switchingEffort else { return }
        guard !store.isTyping, store.live?.active != true else {
            modelSwitchError = "他还在说话  等他说完再换"
            return
        }
        switchingEffort = true; modelSwitchError = ""
        Task {
            do {
                let screen = try await AlcoveAPI.terminalCapture()
                let tail = screen.components(separatedBy: .newlines).suffix(12).joined(separator: "\n")
                guard tail.contains("❯") && !tail.localizedCaseInsensitiveContains("esc to interrupt") else {
                    throw NSError(domain: "AlcoveEffort", code: 1, userInfo: [NSLocalizedDescriptionKey: "他还没空下来"])
                }
                try await AlcoveAPI.terminalSend("/effort \(lvl)")
                // /effort 只改会话内存，transcript 要到下一轮才带新档；这里看屏幕回执就算数
                var confirmed = false
                for _ in 0..<6 {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    if let s = try? await AlcoveAPI.terminalCapture(lines: 12),
                       s.localizedCaseInsensitiveContains("effort level to \(lvl)") { confirmed = true; break }
                }
                guard confirmed else {
                    throw NSError(domain: "AlcoveEffort", code: 2, userInfo: [NSLocalizedDescriptionKey: "没收到切换成功回执"])
                }
                cliEffort = lvl
            } catch { modelSwitchError = error.localizedDescription }
            switchingEffort = false
        }
    }

    private func modelRows(_ options: [ClaudeModelOption]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                Button { modelPanel == "sdk" ? switchSDKModel(option) : switchClaudeModel(option) } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label).font(.system(size: 16, weight: .medium))
                            if !option.note.isEmpty {
                                Text(option.note).font(.system(size: 11)).foregroundColor(theme.textDim)
                            }
                        }
                        Spacer()
                        if (modelPanel == "sdk" ? sdkModelLabel : store.modelLabel) == option.label {
                            Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                                .foregroundColor(theme.sendTop)
                        }
                    }.padding(.horizontal, 18).frame(minHeight: option.note.isEmpty ? 56 : 66)
                }.buttonStyle(.plain)
                if index < options.count - 1 { Divider().opacity(0.45).padding(.horizontal, 18) }
            }
        }
        .background(theme.fyCard.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func switchClaudeModel(_ option: ClaudeModelOption) {
        guard !switchingModel, store.modelLabel != option.label else { showModelPicker = false; return }
        guard !store.isTyping, store.live?.active != true else {
            modelSwitchError = "他还在说话  等他说完再换"
            return
        }
        switchingModel = true
        modelSwitchError = ""
        Task {
            do {
                let screen = try await AlcoveAPI.terminalCapture()
                let tail = screen.components(separatedBy: .newlines).suffix(12).joined(separator: "\n")
                guard tail.contains("❯") && !tail.localizedCaseInsensitiveContains("esc to interrupt") else {
                    throw NSError(domain: "AlcoveModel", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "他还没空下来"])
                }
                try await AlcoveAPI.terminalSend("/model \(option.id)")
                var confirmed = false
                for _ in 0..<6 {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    if (try? await AlcoveAPI.modelLabel()) == option.label { confirmed = true; break }
                }
                guard confirmed else {
                    throw NSError(domain: "AlcoveModel", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "没收到切换成功回执"])
                }
                store.modelLabel = option.label
                showModelPicker = false
            } catch {
                modelSwitchError = error.localizedDescription
            }
            switchingModel = false
        }
    }

    // MARK: 表情面板（她下午做的 Stickers：陈霁/陈璟 tab + 上传 + 原比例网格）

    private var stickerSheet: some View {
        StickerSheet(store: store) { stk in
            showStickers = false
            pendingSticker = stk
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct ChatChannelPanel: View {
    @Binding var activeChannel: String
    @Environment(\.dismiss) private var dismiss
    @State private var panel = "cli"
    @State private var handoffTurns = 12
    @State private var chatRounds = 50        // 0823 后端 status 回的 chat_rounds，给「带几轮」滑块当上限
    @State private var toolMode = "disabled"
    @State private var sdkPrompt = ""
    @State private var sdkIdentity = ""
    @State private var sdkStyle = ""
    @State private var cliCapabilities: [String] = []
    @State private var sdkCapabilities: [String] = []
    @State private var cliMCP: [String] = []
    @State private var sdkMCP: [String] = []
    @State private var loading = true
    @State private var working = false
    @State private var message = ""
    @State private var confirmSwitchMode = false   // 0823 切到 SDK 时选接旧窗还是开新窗
    @State private var confirmSync = false
    @State private var confirmClearSession = false
    @State private var sdkSessionActive = false
    @State private var sdkPrevSession = ""
    @State private var sdkPrevAt = ""
    @State private var confirmRollback = false
    // 当前对话轮数（这一代 / 其中系统轮 / session 累计）
    struct TurnCount { let current: Int; let system: Int; let total: Int }
    @State private var cliTurns: TurnCount? = nil
    @State private var sdkTurns: TurnCount? = nil
    private func parseTurns(_ raw: Any?) -> TurnCount? {
        guard let d = raw as? [String: Any] else { return nil }
        let n = { (k: String) in (d[k] as? NSNumber)?.intValue ?? 0 }
        return TurnCount(current: n("current"), system: n("system"), total: n("total"))
    }
    @State private var cliContextUsed = 0
    @State private var cliContextWindow = 1_000_000
    @State private var sdkContextUsed = 0
    @State private var sdkContextWindow = 1_000_000
    @State private var showSDKForge = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("通道", selection: $panel) {
                        Text("CLI").tag("cli")
                        Text("SDK").tag("sdk")
                    }
                    .pickerStyle(.segmented)

                    channelHeader
                    if panel == "cli" { cliPanel } else { sdkPanel }

                    if !message.isEmpty {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(message.contains("失败") ? .red : .secondary)
                    }
                }
                .padding(20)
            }
            .navigationTitle("陈璟的通道")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .task { await load() }
            .alert("从 CLI 重新复制锚点？", isPresented: $confirmSync) {
                Button("取消", role: .cancel) {}
                Button("覆盖 SDK", role: .destructive) { Task { await syncAnchors() } }
            } message: { Text("SDK 里自己修改过的两份锚点会被当前 CLI 版本覆盖。") }
            .confirmationDialog("完全新开 SDK 窗口？", isPresented: $confirmClearSession,
                                titleVisibility: .visible) {
                Button("清空最近对话并新开", role: .destructive) {
                    Task { await newSDKSession(keepMessages: false) }
                }
                Button("取消", role: .cancel) {}
            } message: { Text("SDK 锚点和共用 LMC-5 不动，只清空 SDK 最近对话和 session。") }
            .sheet(isPresented: $showSDKForge) {
                SDKForgeSheet {
                    sdkSessionActive = true
                    message = "SDK Forge 已自动切到新 session"
                    Task { await load() }   // 刷出「回上一窗」
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var channelHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(activeChannel == panel ? "当前正在使用" : "当前未使用")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text(panel.uppercased())
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text(contextLine)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if activeChannel != panel {
                Button {
                    // 0823 她要的：CLI 切回 SDK 时能选「接着旧窗」还是「开新窗」。旧窗没了就直接开新的
                    if panel == "sdk" && sdkSessionActive { confirmSwitchMode = true }
                    else { Task { await switchChannel() } }
                } label: {
                    if working { ProgressView().controlSize(.small) }
                    else { Text("切到这里") }
                }
                .buttonStyle(.borderedProminent).disabled(working)
                .confirmationDialog("切到 SDK", isPresented: $confirmSwitchMode, titleVisibility: .visible) {
                    Button("接着旧窗，把 CLI 这 \(handoffTurns) 轮带过去") { Task { await switchChannel(keepSession: true) } }
                    Button("开新窗，带 CLI 这 \(handoffTurns) 轮") { Task { await switchChannel(keepSession: false) } }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("旧窗上下文 \(contextLine)。接着旧窗＝上次 SDK 聊的都还在，CLI 这几轮当交接塞给他；开新窗＝只带 CLI 这几轮。")
                }
            } else {
                Label("已连接", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.green)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var cliPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("当前能力")
            capabilityWrap(cliCapabilities)
            sectionTitle("MCP")
            capabilityWrap(cliMCP)
            Text("CLI 使用现役锚点、hooks、工具和 MCP。这里不提供修改入口，原来的出厂设置继续管它。")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            handoffControl
        }
    }

    private var contextLine: String {
        let used = panel == "cli" ? cliContextUsed : sdkContextUsed
        let window = panel == "cli" ? cliContextWindow : sdkContextWindow
        let pct = window > 0 ? Double(used) / Double(window) * 100 : 0
        func compact(_ value: Int) -> String {
            value >= 1_000_000 ? String(format: "%.1fM", Double(value) / 1_000_000)
                : String(format: "%.1fK", Double(value) / 1_000)
        }
        return "上下文 \(compact(used)) / \(compact(window)) · \(String(format: "%.1f", pct))%"
    }

    private var sdkPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("当前能力")
            capabilityWrap(sdkCapabilities)
            sectionTitle("MCP")
            if sdkMCP.isEmpty {
                Text("还没有给 SDK 配 MCP").font(.system(size: 13)).foregroundStyle(.secondary)
            } else { capabilityWrap(sdkMCP) }
            Button("从 CLI 复制 MCP 配置") { Task { await syncMCP() } }
                .buttonStyle(.bordered).disabled(working)
            Picker("工具权限", selection: $toolMode) {
                Text("关闭").tag("disabled")
                Text("只读").tag("readonly")
                Text("完整").tag("full")
            }
            .pickerStyle(.segmented)

            handoffControl
            HStack {
                Button("SDK Forge 换窗") { showSDKForge = true }
                    .buttonStyle(.bordered)
                Button("完全新开", role: .destructive) { confirmClearSession = true }
                    .buttonStyle(.bordered)
                Spacer()
                Text(sdkSessionActive ? "session 已建立" : "下一句建立 session")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if !sdkPrevSession.isEmpty {
                HStack(spacing: 8) {
                    Button { confirmRollback = true } label: {
                        Label("回上一窗", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered).disabled(working)
                    Text("上一窗 \(sdkPrevSession.prefix(8))… \(sdkPrevAt.prefix(16).replacingOccurrences(of: "T", with: " "))")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                }
                .confirmationDialog("回到上一窗？", isPresented: $confirmRollback, titleVisibility: .visible) {
                    Button("回上一窗") { Task { await rollbackSDKSession() } }
                    Button("取消", role: .cancel) {}
                } message: { Text("现在这窗的 session 和它之后的对话会丢，换回 forge / 新开之前那一窗。只能回一步。") }
            }
            editor("SDK 专用 Prompt", text: $sdkPrompt, height: 110)
            editor("SDK · CLAUDE.md", text: $sdkIdentity, height: 220)
            editor("SDK · Output Style", text: $sdkStyle, height: 260)
            HStack {
                Button("从 CLI 重新复制") { confirmSync = true }
                    .buttonStyle(.bordered)
                Spacer()
                Button("保存并应用") { Task { await saveSDK() } }
                    .buttonStyle(.borderedProminent).disabled(working)
            }
            Text("LMC-5 不复制：CLI 和 SDK 始终从同一个脑子召回，同一份召回管线，按 session 记住喂过什么不重复喂。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var handoffControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("切换时带多少轮纯对话")
            // 0823 她要的：跟 CLI forge 一样拉滑块，不再卡 50。上限＝聊天页她说过的总轮数（后端 chat_rounds），
            // 后端自己封顶 500，再多行李新窗也装不下。
            HStack {
                Slider(value: Binding(get: { Double(handoffTurns) },
                                      set: { handoffTurns = Int($0.rounded()) }),
                       in: 1...Double(max(min(chatRounds, 500), 50)), step: 1)
                Text("\(handoffTurns) / \(max(min(chatRounds, 500), 50))")
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minWidth: 74, alignment: .trailing)
            }
            Text("一轮按你一句＋他一轮正文回复计算，不带 Thought process、工具调用和工具结果。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            // 0822 她要的：当前这一窗已经聊了多少轮，cli / sdk 各自的数（这一代，forge 之后重新数）
            let turns = panel == "sdk" ? sdkTurns : cliTurns
            if let turns {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.bubble").font(.system(size: 11))
                        Text("当前对话 \(turns.current) 轮" +
                             (turns.total > turns.current ? " · 这个 session 累计 \(turns.total) 轮" : ""))
                    }
                    // 0822 她要的第二行：系统轮 / 对话轮分开数
                    Text("系统轮次 \(turns.system)　对话轮次 \(turns.current - turns.system)")
                        .padding(.leading, 18)
                }
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 14, weight: .semibold))
    }

    private func capabilityWrap(_ items: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(items, id: \.self) { item in
                    Text(item).font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10).frame(height: 30)
                        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                }
            }
        }
    }

    private func editor(_ title: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle(title)
            TextEditor(text: text)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: height)
                .padding(8)
                .background(Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @MainActor private func load() async {
        loading = true
        do {
            let obj = try await AlcoveAPI.getRaw("/api/sdk-shadow/status")
            activeChannel = obj["channel"] as? String ?? "cli"
            panel = activeChannel
            let cfg = obj["config"] as? [String: Any] ?? [:]
            handoffTurns = (cfg["handoff_turns"] as? NSNumber)?.intValue ?? 12
            chatRounds = (obj["chat_rounds"] as? NSNumber)?.intValue ?? 50
            toolMode = cfg["tool_mode"] as? String ?? "disabled"
            sdkPrompt = cfg["sdk_prompt"] as? String ?? ""
            sdkSessionActive = !((cfg["sdk_session_id"] as? String) ?? "").isEmpty
            sdkPrevSession = cfg["sdk_prev_session_id"] as? String ?? ""
            sdkPrevAt = cfg["sdk_prev_at"] as? String ?? ""
            cliTurns = parseTurns(obj["cli_turns"])
            sdkTurns = parseTurns(obj["sdk_turns"])
            let anchors = obj["anchors"] as? [String: Any] ?? [:]
            sdkIdentity = anchors["identity"] as? String ?? ""
            sdkStyle = anchors["style"] as? String ?? ""
            cliCapabilities = obj["cli_capabilities"] as? [String] ?? []
            sdkCapabilities = obj["sdk_capabilities"] as? [String] ?? []
            cliMCP = obj["cli_mcp"] as? [String] ?? []
            sdkMCP = obj["sdk_mcp"] as? [String] ?? []
            let cliContext = obj["cli_context"] as? [String: Any] ?? [:]
            cliContextUsed = (cliContext["used"] as? NSNumber)?.intValue ?? 0
            cliContextWindow = (cliContext["window"] as? NSNumber)?.intValue ?? 1_000_000
            let sdkContext = obj["sdk_context"] as? [String: Any] ?? [:]
            sdkContextUsed = (sdkContext["used"] as? NSNumber)?.intValue ?? 0
            sdkContextWindow = (sdkContext["window"] as? NSNumber)?.intValue ?? 1_000_000
            message = ""
        } catch { message = "加载失败：\(error.localizedDescription)" }
        loading = false
    }

    @MainActor private func saveSDK() async {
        working = true
        do {
            _ = try await AlcoveAPI.postRaw("/api/sdk-shadow/config", body: [
                "handoff_turns": handoffTurns, "tool_mode": toolMode,
                "sdk_prompt": sdkPrompt, "identity": sdkIdentity, "style": sdkStyle
            ])
            await load()
            message = "已保存，从下一句话开始生效"
        } catch { message = "保存失败：\(error.localizedDescription)" }
        working = false
    }

    @MainActor private func syncAnchors() async {
        working = true
        do {
            let obj = try await AlcoveAPI.postRaw("/api/sdk-shadow/sync-anchors", body: [:])
            let anchors = obj["anchors"] as? [String: Any] ?? [:]
            sdkIdentity = anchors["identity"] as? String ?? sdkIdentity
            sdkStyle = anchors["style"] as? String ?? sdkStyle
            message = "已从 CLI 重新复制，只改了 SDK 副本"
        } catch { message = "同步失败：\(error.localizedDescription)" }
        working = false
    }

    @MainActor private func syncMCP() async {
        working = true
        do {
            let obj = try await AlcoveAPI.postRaw("/api/sdk-shadow/sync-mcp", body: [:])
            sdkMCP = obj["sdk_mcp"] as? [String] ?? []
            sdkSessionActive = false
            message = "已复制 \(sdkMCP.count) 个 MCP，下一句话建立新 SDK session"
        } catch { message = "MCP 同步失败：\(error.localizedDescription)" }
        working = false
    }

    @MainActor private func switchChannel(keepSession: Bool = false) async {
        working = true; message = ""
        do {
            let obj = try await AlcoveAPI.postRaw("/api/sdk-shadow/switch", body: [
                "channel": panel, "handoff_turns": handoffTurns, "keep_session": keepSession
            ])
            guard obj["ok"] as? Bool == true else {
                throw NSError(domain: "Channel", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: obj["error"] as? String ?? "切换失败"])
            }
            activeChannel = obj["channel"] as? String ?? panel
            message = "已切到 \(activeChannel.uppercased())" + (panel == "sdk" ? (keepSession ? "，接着旧窗" : "，下一句开新窗") : "")
        } catch { message = "切换失败：\(error.localizedDescription)" }
        working = false
    }

    @MainActor private func newSDKSession(keepMessages: Bool) async {
        working = true; message = ""
        do {
            _ = try await AlcoveAPI.postRaw("/api/sdk-shadow/new-session", body: [
                "keep_messages": keepMessages, "handoff_turns": handoffTurns
            ])
            sdkSessionActive = false
            message = keepMessages
                ? "SDK 窗口已换，下一句带最近 \(handoffTurns) 轮建立新 session"
                : "SDK 已完全新开，下一句建立空白 session"
            await load()
        } catch { message = "换窗失败：\(error.localizedDescription)" }
        working = false
    }

    // 0822 她要的：forge / 完全新开 误点了，退回上一窗（session + 对话存档一起回，只能回一步）
    @MainActor private func rollbackSDKSession() async {
        working = true; message = ""
        do {
            let obj = try await AlcoveAPI.postRaw("/api/sdk-shadow/rollback", body: [:])
            guard obj["ok"] as? Bool == true else {
                throw NSError(domain: "SDKRollback", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: obj["error"] as? String ?? "回不去"])
            }
            message = "已回到上一窗，\((obj["turns"] as? NSNumber)?.intValue ?? 0) 轮对话跟着回来了"
            await load()
        } catch { message = "回上一窗失败：\(error.localizedDescription)" }
        working = false
    }
}

private struct SDKForgeRound: Identifiable {
    let idx: Int
    let head: String
    let at: String
    let kind: String   // user = 她说的；system = 心跳 / keepalive / 系统班次，默认折叠
    var id: Int { idx }
    var isSystem: Bool { kind == "system" }
    init(_ raw: [String: Any]) {
        idx = (raw["idx"] as? NSNumber)?.intValue ?? 0
        head = raw["head"] as? String ?? ""
        at = raw["at"] as? String ?? ""
        kind = raw["kind"] as? String ?? "user"
    }
}

private struct SDKForgeSheet: View {
    let onForged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mode = "latest"
    @State private var retain = 20.0
    @State private var preview: [String: Any] = [:]
    @State private var rounds: [SDKForgeRound] = []
    @State private var picked: Set<Int> = []
    @State private var working = false
    @State private var error = ""
    @State private var confirm = false
    // 0822 照 CLI 补的：系统轮（心跳/keepalive/系统班次）默认折叠不带；想带就打开
    @State private var includeSystem = false
    @State private var showSystemRounds = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("只搬完整的 user / assistant 正文，每轮自带真实时间注记，末尾附上一窗两个真实工具范本。Thought process、图片不进新窗；SDK 锚点重新加载，LMC-5 继续共用。")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    Picker("方式", selection: $mode) {
                        Text("默认保留").tag("latest")
                        Text("挑选轮次").tag("picker")
                    }.pickerStyle(.segmented)
                    if systemCount > 0 {
                        Toggle(isOn: mode == "latest" ? $includeSystem : $showSystemRounds) {
                            Text(mode == "latest" ? "带上 \(systemCount) 轮系统轮（心跳 / keepalive）"
                                                  : "显示 \(systemCount) 轮系统轮（折叠中）")
                                .font(.system(size: 12))
                        }
                        .onChange(of: includeSystem) { _ in Task { await loadPreview() } }
                    }

                    if mode == "latest" {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text("保留轮次"); Spacer(); Text("\(Int(min(retain, Double(max(total, 1))))) / \(total)") }
                            // 0822 她点开就闪退：首帧预览还没回来 total=0，滑条范围成了 1...1 而值是 20，
                            // 零宽范围 SwiftUI 算出 NaN 直接炸。没拉到数据/只有一轮时不画滑条，值也钳在范围里。
                            if total > 1 {
                                Slider(value: Binding(
                                    get: { min(max(retain, 1), Double(total)) },
                                    set: { retain = min(max($0, 1), Double(total)) }
                                ), in: 1...Double(total), step: 1)
                                    .onChange(of: retain) { _ in Task { await loadPreview() } }
                            } else {
                                Text(preview.isEmpty ? "正在读取轮次…" : "只有 \(total) 轮，全部带走")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(rounds.filter { showSystemRounds || !$0.isSystem }) { round in
                                Button {
                                    if picked.contains(round.idx) { picked.remove(round.idx) }
                                    else { picked.insert(round.idx) }
                                    preview = [:]
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: picked.contains(round.idx)
                                              ? "checkmark.circle.fill" : "circle")
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 6) {
                                                Text("#\(round.idx + 1)  \(round.at.prefix(16).replacingOccurrences(of: "T", with: " "))")
                                                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                                if round.isSystem {
                                                    Text("系统").font(.system(size: 9, weight: .semibold))
                                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                                        .background(Color.secondary.opacity(0.18), in: Capsule())
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            Text(round.head).font(.system(size: 13)).lineLimit(3)
                                                .foregroundStyle(round.isSystem ? .secondary : .primary)
                                        }
                                        Spacer()
                                    }
                                    .padding(11).background(Color(uiColor: .secondarySystemBackground),
                                                            in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain)
                            }
                        }
                        Button("预览所选 \(picked.count) 轮") { Task { await previewPicked() } }
                            .buttonStyle(.bordered).disabled(picked.isEmpty)
                    }

                    if !preview.isEmpty { report }
                    if !error.isEmpty { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
                    Button { confirm = true } label: {
                        HStack { if working { ProgressView().tint(.white) }; Text("确认锻造并自动切换") }
                            .frame(maxWidth: .infinity).frame(height: 46)
                    }
                    .buttonStyle(.borderedProminent).disabled(working || !valid)
                }.padding(20)
            }
            .navigationTitle("SDK Forge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
            .task { await loadPreview() }
            .confirmationDialog("确认锻造新 SDK 窗口？", isPresented: $confirm,
                                titleVisibility: .visible) {
                Button("确认锻造") { Task { await forge() } }
                Button("取消", role: .cancel) {}
            } message: { Text("新 session 探针通过后才自动切换；失败继续留在旧 session。") }
        }
    }

    private var total: Int { (preview["total_rounds"] as? NSNumber)?.intValue ?? rounds.count }
    private var systemCount: Int { (preview["system_rounds"] as? NSNumber)?.intValue ?? rounds.filter(\.isSystem).count }
    private var valid: Bool { preview["valid"] as? Bool ?? false }
    private var report: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("锻造预览").font(.system(size: 14, weight: .semibold))
            Text("带走 \((preview["retained_rounds"] as? NSNumber)?.intValue ?? 0) / \(total) 轮纯正文")
            Text("新窗开局约 \((preview["estimated_tokens"] as? NSNumber)?.intValue ?? 0) token")
            if let first = preview["first_messages"] as? [String], let value = first.first {
                Text("开头：\(value)").lineLimit(2)
            }
            if let last = preview["last_messages"] as? [String], let value = last.last {
                Text("结尾：\(value)").lineLimit(2)
            }
        }.font(.system(size: 12)).foregroundStyle(.secondary)
            .padding(14).background(Color(uiColor: .secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 14))
    }

    @MainActor private func loadPreview() async {
        do {
            let obj = try await AlcoveAPI.getRaw("/api/sdk-shadow/forge?retain=\(Int(retain))&include_system=\(includeSystem ? 1 : 0)")
            preview = obj
            rounds = (obj["rounds"] as? [[String: Any]] ?? []).map(SDKForgeRound.init)
            if retain > Double(max(rounds.count, 1)) { retain = Double(max(rounds.count, 1)) }
            error = ""
        } catch { self.error = "预览失败：\(error.localizedDescription)" }
    }

    @MainActor private func previewPicked() async {
        do {
            preview = try await AlcoveAPI.postRaw("/api/sdk-shadow/forge-preview",
                                                  body: ["pick": picked.sorted(), "include_system": true])
            error = ""
        } catch { self.error = "预览失败：\(error.localizedDescription)" }
    }

    @MainActor private func forge() async {
        working = true; error = ""
        do {
            var body: [String: Any] = ["retain": Int(retain), "include_system": includeSystem]
            if mode == "picker" { body = ["pick": picked.sorted(), "include_system": true] }
            let obj = try await AlcoveAPI.postRaw("/api/sdk-shadow/forge", body: body)
            guard obj["ok"] as? Bool == true, obj["probe_ok"] as? Bool == true else {
                throw NSError(domain: "SDKForge", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: obj["error"] as? String ?? "探针未通过"])
            }
            onForged(); dismiss()
        } catch { self.error = "锻造失败：\(error.localizedDescription)" }
        working = false
    }
}

private struct SDKShadowMessage: Identifiable {
    let id: String
    let role: String
    let text: String
    let at: String

    init?(_ json: [String: Any], index: Int) {
        guard let role = json["role"] as? String,
              let text = json["text"] as? String else { return nil }
        self.role = role
        self.text = text
        self.at = json["at"] as? String ?? ""
        self.id = "\(at)-\(index)-\(role)"
    }
}

private struct SDKShadowChatView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [SDKShadowMessage] = []
    @State private var draft = ""
    @State private var loading = true
    @State private var sending = false
    @State private var error = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if loading { ProgressView().padding(.top, 30) }
                            ForEach(messages) { message in
                                HStack {
                                    if message.role == "user" { Spacer(minLength: 42) }
                                    Text(message.text)
                                        .font(.system(size: 15.5))
                                        .foregroundStyle(message.role == "user" ? .white : .primary)
                                        .padding(.horizontal, 14).padding(.vertical, 10)
                                        .background(message.role == "user" ? Color.indigo : Color(uiColor: .secondarySystemBackground),
                                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    if message.role != "user" { Spacer(minLength: 42) }
                                }
                                .id(message.id)
                            }
                            if sending {
                                HStack { ProgressView(); Text("陈璟正在影子里想…").font(.footnote).foregroundStyle(.secondary); Spacer() }
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _ in
                        if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                if !error.isEmpty {
                    Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal).padding(.top, 6)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("在影子里和陈璟说话", text: $draft, axis: .vertical)
                        .focused($focused).lineLimit(1...5)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                    Button { Task { await send() } } label: {
                        Image(systemName: "arrow.up").fontWeight(.semibold).foregroundStyle(.white)
                            .frame(width: 38, height: 38).background(Color.indigo, in: Circle())
                    }
                    .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle("SDK 影子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } } }
            .task { await load() }
        }
    }

    @MainActor private func load() async {
        do {
            let obj = try await AlcoveAPI.getRaw("/api/sdk-shadow/history")
            let raw = obj["messages"] as? [[String: Any]] ?? []
            messages = raw.enumerated().compactMap { SDKShadowMessage($0.element, index: $0.offset) }
            error = ""
        } catch { self.error = "影子历史暂时没接上" }
        loading = false
    }

    @MainActor private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        draft = ""; sending = true; error = ""
        do {
            let obj = try await AlcoveAPI.postRaw("/api/sdk-shadow/send", body: ["text": text])
            if obj["ok"] as? Bool != true {
                throw NSError(domain: "SDKShadow", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: obj["error"] as? String ?? "回复失败"])
            }
            await load()
        } catch { self.error = error.localizedDescription }
        sending = false
    }
}

// MARK: - 单条消息

private final class AskSelectableTextView: UITextView {
    var onAsk: ((String) -> Void)?
    var onCopyTurn: (() -> Void)?

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard selectedRange.length > 0 else { return }
        let ask = UIAction(title: "询问", image: UIImage(systemName: "quote.bubble")) { [weak self] _ in
            guard let self,
                  self.selectedRange.location != NSNotFound,
                  self.selectedRange.length > 0 else { return }
            let selected = (self.text as NSString).substring(with: self.selectedRange)
            self.onAsk?(selected)
        }
        let copyTurn = UIAction(title: "复制整轮", image: UIImage(systemName: "doc.on.doc")) {
            [weak self] _ in self?.onCopyTurn?()
        }
        builder.insertChild(UIMenu(options: .displayInline, children: [ask, copyTurn]),
                            atStartOfMenu: .standardEdit)
    }
}

private struct SelectableMessageText: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let color: UIColor
    var maximumNumberOfLines: Int = 0
    var onTruncationChange: ((Bool) -> Void)? = nil
    let onAsk: (String) -> Void
    let onCopyTurn: () -> Void

    final class Coordinator {
        var renderedKey: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> AskSelectableTextView {
        let view = AskSelectableTextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: AskSelectableTextView, context: Context) {
        view.onAsk = onAsk
        view.onCopyTurn = onCopyTurn
        // 后台每 2.5 秒轮询会让 SwiftUI 重跑 updateUIView。正文其实没变，
        // 但重新赋 attributedText 会强制收掉 iOS 的选区和复制菜单。
        // 同一份渲染直接跳过；用户正在选字时，即使主题恰好变化也先让她选完。
        view.textContainer.maximumNumberOfLines = maximumNumberOfLines
        view.textContainer.lineBreakMode = maximumNumberOfLines > 0 ? .byTruncatingTail : .byWordWrapping
        let renderedKey = "\(text)\u{1f}\(fontSize)\u{1f}\(lineSpacing)\u{1f}\(color.description)\u{1f}\(maximumNumberOfLines)"
        guard context.coordinator.renderedKey != renderedKey else { return }
        guard view.selectedRange.length == 0 else { return }
        let source = alcoveMarkdown(text)
        let rendered = NSMutableAttributedString(attributedString: NSAttributedString(source))
        let all = NSRange(location: 0, length: rendered.length)
        rendered.addAttribute(.foregroundColor, value: color, range: all)
        rendered.enumerateAttribute(.font, in: all) { value, range, _ in
            let old = value as? UIFont
            var traits = old?.fontDescriptor.symbolicTraits ?? []
            let descriptor = UIFont.systemFont(ofSize: fontSize).fontDescriptor.withSymbolicTraits(traits)
            rendered.addAttribute(.font, value: UIFont(descriptor: descriptor ?? UIFont.systemFont(ofSize: fontSize).fontDescriptor,
                                                       size: fontSize), range: range)
        }
        if rendered.length > 0 && rendered.attribute(.font, at: 0, effectiveRange: nil) == nil {
            rendered.addAttribute(.font, value: UIFont.systemFont(ofSize: fontSize), range: all)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        rendered.addAttribute(.paragraphStyle, value: paragraph, range: all)
        view.attributedText = rendered
        context.coordinator.renderedKey = renderedKey
        reportTruncation(view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: AskSelectableTextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        DispatchQueue.main.async { reportTruncation(uiView) }
        return size
    }

    private func reportTruncation(_ view: UITextView) {
        guard maximumNumberOfLines > 0, let onTruncationChange else { return }
        view.layoutManager.ensureLayout(for: view.textContainer)
        let shown = view.layoutManager.glyphRange(for: view.textContainer)
        let truncated = NSMaxRange(shown) < view.layoutManager.numberOfGlyphs
        DispatchQueue.main.async { onTruncationChange(truncated) }
    }
}

struct MessageRow: View {
    let msg: ChatMessage
    let sticker: Sticker?
    var theme: AlcoveTheme = .haven
    var fontSize: Int = 14
    var showTime: Bool = true
    var recall: RecallItem? = nil
    // 0818 她要的：思绪永远在我这一轮的最上面（哪怕这一轮先发了表情/截图），
    // 思绪下面再挂一条独立的可展开「工具轨迹」。列表那头按连续的我方消息算一轮，
    // 把整轮的思绪和动作提到轮首这条消息上，其余消息自己的不再重复显示。
    var hoistedThought: String? = nil
    var hoistedActivity: [ActivityItem] = []
    var suppressOwnThought = false
    var suppressOwnActivity = false
    var photoURLs: [URL] = []
    var photoNamespace: Namespace.ID
    var onTapImages: ([URL], Binding<Int>) -> Void
    var onDelete: (() -> Void)? = nil
    var onFavorite: (() -> Void)? = nil
    var wholeTurnText: String = ""
    var paragraphSelectionMode = false
    var paragraphSelected = false
    // 0906 她要的：带图又带字的消息，多选时图一个圈、字一个圈，勾哪个收哪个
    var photoSelected = false
    var onTogglePhotoSelection: (() -> Void)? = nil
    var onBeginParagraphSelection: (() -> Void)? = nil
    var onToggleParagraphSelection: (() -> Void)? = nil
    var onQuote: ((String) -> Void)? = nil
    var onResend: ((String) -> Void)? = nil
    var onPlayMusic: ((MusicSong) -> Void)? = nil
    var onContentChange: (() -> Void)? = nil
    @State private var showThinking = false
    @State private var showActivity = false   // 0730 过程记录展开
    // 0820 按时间线摆之后，点开的是「这一段」，不是整轮那一坨
    @State private var openedThink: String? = nil
    @State private var openedTools: [ActivityItem]? = nil
    // 0822 iMessage 主题：思绪+脚印合成一条过程线，默认只露一个点
    @State private var processOpen = false
    @State private var showTranscript = false   // 0822 语音条默认不露文字，长按「转文字」才展开
    @AppStorage("imsgShowProcess") private var showProcessDots = true
    @State private var openedToolDetail: ActivityItem? = nil
    @State private var showRecall = false
    @State private var showPulse = false
    @Environment(\.bubbleGlassStyle) private var bubbleGlassStyle

    private var isUser: Bool { msg.role == "user" }
    private var timestampTextInset: CGFloat {
        if theme.isPaper && !isUser { return 0 }
        // 0907 她要的：时间戳一律缩进到同一条竖线上，不管这条是文字、表情还是图。
        // 原来只有「有正文的文字气泡」才缩进 —— 删到只剩一张表情时时间戳顶到最左边，
        // 跟上一条的时间戳对不齐。
        return 12
    }
    private var shouldShowMetaRow: Bool {
        msg.msgType != "choice_answer" && (msg.pending || msg.asleepAtSend || showTime)
    }

    /// 这条消息头上要挂的轨迹：轮首拿整轮的，其他消息不挂。
    /// 整条时间线（动作 / 中间说的话 / 中间的思绪）按时间排，一个不丢。
    private var trailItems: [ActivityItem] {
        if !hoistedActivity.isEmpty { return hoistedActivity }
        if suppressOwnActivity { return [] }
        return msg.activity
    }
    /// 0820 她定的：跑命令那栏只放命令，思绪归思绪栏，两边彻底分开
    private var trailTools: [ActivityItem] { trailItems.filter { $0.kind == "tool" } }
    private var trailToolCount: Int { trailTools.count }

    private func trailLabel(_ items: [ActivityItem]) -> String {
        enum Kind: Hashable { case command, read, tool }
        func kind(_ item: ActivityItem) -> Kind {
            if item.toolName == "Bash" { return .command }
            if item.toolName == "Read" { return .read }
            return .tool
        }
        var order: [Kind] = []
        var counts: [Kind: Int] = [:]
        for item in items {
            let k = kind(item)
            if counts[k] == nil { order.append(k) }
            counts[k, default: 0] += 1
        }
        let bits = order.enumerated().map { offset, k -> String in
            let n = counts[k, default: 0]
            let phrase: String
            switch k {
            case .command: phrase = n == 1 ? "Ran a command" : "Ran \(n) commands"
            case .read: phrase = n == 1 ? "Read a file" : "Read \(n) files"
            case .tool: phrase = n == 1 ? "Used a tool" : "Used \(n) tools"
            }
            guard offset > 0 else { return phrase }
            return phrase.prefix(1).lowercased() + phrase.dropFirst()
        }
        return bits.isEmpty ? "Used a tool" : bits.joined(separator: ", ")
    }
    private var trailEntryLabel: String { trailLabel(trailTools) }

    /// 0820 她要的：一段思绪一个折叠面板，跟命令行按发生顺序交替排。
    /// 把时间线切成一块块 —— 连着的命令归一行，每段思绪自己一个面板。
    private enum TurnBlock: Identifiable {
        case think(String, Int)
        case tools([ActivityItem], Int)
        var id: String {
            switch self {
            case .think(_, let i): return "t\(i)"
            case .tools(_, let i): return "k\(i)"
            }
        }
    }
    private var turnBlocks: [TurnBlock] {
        var out: [TurnBlock] = []
        var buf: [ActivityItem] = []
        var n = 0
        for it in msg.segments {
            if it.kind == "think" || it.kind == "thinking" {
                if !buf.isEmpty { out.append(.tools(buf, n)); n += 1; buf = [] }
                if !it.content.isEmpty { out.append(.think(it.content, n)); n += 1 }
            } else if it.kind == "tool" {
                buf.append(it)
            }
        }
        if !buf.isEmpty { out.append(.tools(buf, n)) }
        return out
    }
    private var firstThinkBlockID: String? {
        turnBlocks.first {
            if case .think = $0 { return true }
            return false
        }?.id
    }
    /// 只有话没有动作的轮次不挂轨迹行（那些话本来就在气泡里）
    private var trailWorthShowing: Bool { trailToolCount > 0 }
    /// 塔罗卡那一行：整行居中
    private var isTarotRow: Bool { msg.tarotCard != nil || msg.tarotOffer != nil }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            // 0903 她要的：塔罗卡不管谁发的都在屏幕正中间，两侧留白都不吃
            if isUser { Spacer(minLength: isTarotRow ? 0 : 48) }
            VStack(alignment: isUser ? .trailing : .leading,
                   spacing: theme.isPaper && !isUser ? 10 : 7) {
                // 0820：有时间线就照发生顺序摆 —— 想一段出一个面板，
                // 中间干的活收成一行。没时间线（老消息）走原来那套。
                if theme.isMessages && !isUser {
                    messagesProcessBlock
                } else if !isUser && !turnBlocks.isEmpty {
                    ForEach(turnBlocks) { blk in
                        switch blk {
                        case .think(let text, let i):
                            thinkPanelRow(text, index: i, showRecall: blk.id == firstThinkBlockID)
                        case .tools(let items, let i):
                            toolRow(items, index: i)
                        }
                    }
                } else {
                    if let think = visibleChatThought {
                        thinkingBlock(think)
                    } else if recall != nil {
                        recallBadge // 没有思绪行时角标单独站一行，和 PWA 一致
                    }
                    if !isUser && trailWorthShowing {
                        trailBlock
                    }
                }
                if !theme.isMessages && !isUser { nativeThinkingButton }
                if let paperDate = msg.morningPaperDate {
                    MorningPaperMessageCard(date: paperDate, theme: theme, messageID: msg.id)
                } else if let inside = msg.insideText {
                    InsideMessageCard(text: inside, date: msg.date, theme: theme, messageID: msg.id)
                } else if let ghost = msg.ghostCard {
                    GhostActivityMessageCard(card: ghost, theme: theme)
                } else if let play = msg.playCard {
                    PlayPageMessageCard(card: play, theme: theme)
                } else if let forward = msg.favoriteForward {
                    FavoriteForwardMessageCard(card: forward)
                } else if let reading = msg.readingCard {
                    ReadingShareMessageCard(card: reading, theme: theme)
                } else if let tarot = msg.tarotCard {
                    TarotMessageCard(card: tarot, theme: theme)
                        .frame(maxWidth: .infinity)   // 整行居中
                } else if let offer = msg.tarotOffer {
                    TarotOfferMessageCard(card: offer, theme: theme, onContentChange: onContentChange)
                        .frame(maxWidth: .infinity)
                } else if msg.msgType == "tarot_answer" {
                    // 她抽满了他出的题：服务端落的那条（全文给他读），聊天页只画一句小条子，牌在上面那张卡里
                    ChoiceAnswerStrip(text: "🔮 抽好了，牌在上面那张卡里", theme: theme)
                } else if let work = msg.workCard {
                    WorkDeliveryMessageCard(card: work, theme: theme)
                } else if let album = msg.albumSavedCard {
                    AlbumSavedMessageCard(batch: album, theme: theme)
                } else if let buy = msg.buyCard {
                    // 0907 二期审批卡：她要它「跟他的气泡列在一堆」，所以不居中，走左侧
                    BuyApprovalMessageCard(card: buy, theme: theme)
                } else if let paid = msg.paidCard {
                    // 0909 付款单：跟审批卡一样列在他的气泡那一堆里，不居中
                    PaidReceiptMessageCard(card: paid, theme: theme)
                } else if let ticket = msg.ticketCard {
                    // 0909 券卡：她点确认才核销，跟审批卡一样列在他的气泡那堆里
                    TicketUseMessageCard(card: ticket, theme: theme)
                } else if let choice = msg.choiceCard {
                    ChoiceQuestionMessageCard(card: choice, theme: theme)
                } else if msg.msgType == "choice_answer" {
                    ChoiceAnswerStrip(text: msg.displayText, theme: theme)
                } else if let letter = msg.letterCard {
                    LetterMessageCard(card: letter, theme: theme)
                        .frame(maxWidth: .infinity)   // 信封也走正中间，跟旅行卡一个待遇
                } else if let journey = msg.journeyCard {
                    JourneyMessageCard(ref: journey, theme: theme)
                        .frame(maxWidth: .infinity)   // 她要卡片在聊天页正中间
                } else if let call = msg.callSummary {
                    // 0831 任务#1195：打完电话聊天页只留这一条，点开展开这一通的记录。
                    // 左右不用这里判——服务端已经把 role 写成打电话那个人了
                    //（她打的=user 在右，他打的=assistant 在左），拒绝也照这条走。
                    CallSummaryBubble(info: call, text: msg.displayText, theme: theme)
                } else if msg.isSticker {
                    stickerBody
                } else {
                    photoBlock
                    if msg.isAudio, let raw = msg.attachmentUrl {
                        // 0822 她要的：一开始只有语音条，长按才「转文字」或「收藏」
                        // 0902 她给的参考图：转文字收在同一条气泡里，点右边的小箭头展开
                        AudioBubble(url: AlcoveAPI.attachmentURL(raw), isUser: isUser, theme: theme,
                                    fontSize: CGFloat(fontSize),
                                    hasTranscript: !msg.audioTranscript.isEmpty,
                                    transcript: msg.audioTranscript,
                                    transcriptShown: showTranscript,
                                    onToggleTranscript: {
                                        withAnimation(.easeInOut(duration: 0.18)) { showTranscript.toggle() }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onContentChange?() }
                                    },
                                    onFavorite: { onFavorite?() },
                                    translation: msg.audioZh ?? "",
                                    onContentChange: { onContentChange?() })
                    }
                    if msg.isDocument, let raw = msg.attachmentUrl {
                        DocumentAttachmentCard(
                            url: AlcoveAPI.attachmentURL(raw),
                            filename: msg.attachmentFilename ?? "文件",
                            theme: theme
                        )
                    }
                    if let song = msg.musicCard {
                        MusicMessageCard(song: song, theme: theme, isUser: isUser) { onPlayMusic?(song) }
                    } else if !msg.displayText.isEmpty && !(msg.isSticker) && !msg.isBareLink
                                && !msg.isAudio {   // 语音的转文字画在语音条里面，不另起气泡
                        if paragraphSelectionMode {
                            HStack(alignment: .top, spacing: 9) {
                                Button { onToggleParagraphSelection?() } label: {
                                    Image(systemName: paragraphSelected
                                          ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 19, weight: .regular))
                                        .foregroundColor(paragraphSelected
                                                         ? theme.fyAccent : theme.textDim)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 3)
                                bubble
                                    .allowsHitTesting(false)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { onToggleParagraphSelection?() }
                        } else {
                            bubble
                        }
                    }
                    // 正文里有链接：气泡下面长一张小卡片（只有链接的话就只留卡）
                    if let link = msg.firstLinkURL, msg.musicCard == nil, !msg.isSticker {
                        LinkPreviewCard(url: link, theme: theme, isUser: isUser)
                    }
                }
                // 0819 活动脚印（她把活动卡片换掉了）：气泡外面一行浅灰斜体，
                // 「逛了花园 写了念头」，词之间空格隔开。轻到不特意看就滑过去了。
                // 0823 她报的：信息主题里这行整个不见。原来这儿写死了不给信息主题，
                // 跟过程点那个开关没关系，她把思绪打开也照样没有。改成跟着开关走。
                if !isUser && !msg.trace.isEmpty && (!theme.isMessages || showProcessDots) {
                    Text(msg.trace.joined(separator: "  "))
                        .font(.system(size: 11.5, design: .serif))
                        .italic()
                        // 0904 她抓的：0903 只改了 toolRow，这行独立脚印漏了，颜色也跟思绪走
                        .foregroundColor(theme.thoughtColor.opacity(0.82))
                        .padding(.leading, 3)
                        .padding(.top, 1)
                }
                if shouldShowMetaRow {
                    // 0822 她要的：信息主题下时间／清单／心率三个之间留呼吸感
                    HStack(spacing: theme.isMessages ? 12 : (theme.isPaper && !isUser ? 14 : 4)) {
                        if msg.pending {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        if msg.asleepAtSend {
                            Text("睡着时收到")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        if showTime {
                            Text(Self.hm.string(from: msg.date))
                                .font(.system(size: 10, design: .serif))
                                .foregroundColor(theme.timestamp)
                        }
                        if theme.isMessages, isUser, !msg.pending {
                            // 0822 她定的：tg 那种两个勾，发出去就亮，只是个装饰
                            HStack(spacing: -5) {
                                Image(systemName: "checkmark")
                                Image(systemName: "checkmark")
                            }
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color(uiColor: .systemBlue))
                        }
                        // 0907 她抓的：原来要求这条有正文才给按钮，
                        // 删到只剩一张表情时多选入口整个没了，那条再也选不中。
                        // 0907 她定的：信息主题下这个按钮也归过程点那个开关管 ——
                        // 关了就跟思绪、脚印、心率一起藏，截图时那一行干干净净。
                        // 代价是关着的时候进不去多选，要删东西得先把开关打开。
                        if showTime, !isUser, !(theme.isMessages && !showProcessDots) {
                            Button { onBeginParagraphSelection?() } label: {
                                Image(systemName: "checklist")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(theme.timestamp.opacity(
                                        paragraphSelectionMode ? 1 : 0.72))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("选择正文段落")
                        }
                        // 0822 她定的：信息主题下心率跟过程线（思绪/脚印/记忆）一个开关，关了一起藏
                        if showTime, !isUser, let bpm = msg.heartRate, !(theme.isMessages && !showProcessDots) {
                            Button { showPulse = true } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(Color(red: 0.78, green: 0.43, blue: 0.50).opacity(0.82))
                                    Text("\(bpm) bpm")
                                        .font(.system(size: 10, design: .serif))
                                        .foregroundColor(theme.timestamp.opacity(0.72))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, isUser ? 0 : timestampTextInset)
                    .padding(.trailing, isUser ? timestampTextInset : 0)
                }
            }
            if !isUser {
                // 晨报和旅行卡片是整行居中的东西，不吃我这边气泡的右侧留白
                Spacer(minLength: (msg.morningPaperDate != nil || msg.journeyCard != nil || isTarotRow) ? 0
                       : (msg.choiceCard != nil ? 34 : (theme.isPaper ? 15 : 48)))
            }
        }
        .padding(.leading, theme.isPaper && !isUser && msg.morningPaperDate == nil && msg.journeyCard == nil && !isTarotRow ? 12 : 0)
        .padding(.top, 2)
        .padding(.bottom, showTime ? 12 : 5)
        .sheet(item: Binding(get: { openedThink.map { OneThought(text: $0) } },
                             set: { openedThink = $0?.text })) { one in
            NavigationStack {
                ScrollView {
                    Text(one.text)
                        .font(.system(size: 15))
                        .lineSpacing(7)
                        .foregroundColor(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22).padding(.top, 6).padding(.bottom, 30)
                }
                .background(theme.fyCardSub.ignoresSafeArea())
                .navigationTitle("Thought process")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { openedThink = nil } } }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(theme.fyCardSub)
        }
        .sheet(item: Binding(get: { openedTools.map { OneTrail(items: $0) } },
                             set: { openedTools = $0?.items })) { one in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(one.items) { item in
                            Button { openedToolDetail = item } label: {
                            HStack(alignment: .top, spacing: 11) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 11, weight: .light))
                                    .foregroundColor(theme.fyAccent)
                                    .frame(width: 18).padding(.top, 2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.toolName == "Bash" ? "Ran" : "Used")
                                        .font(.system(size: 13.5, weight: .medium))
                                        .foregroundColor(theme.text)
                                    Text(item.desc.isEmpty ? item.content : item.desc)
                                            .font(.system(size: 12))
                                            .foregroundColor(theme.textDim)
                                            .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(theme.textDim)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 9)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 22).padding(.bottom, 30)
                }
                .background(theme.fyCardSub.ignoresSafeArea())
                .navigationTitle(trailLabel(one.items))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { openedTools = nil } } }
            }
            .sheet(item: $openedToolDetail) { item in
                commandDetailPanel(item)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(theme.fyCardSub)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(theme.fyCardSub)
        }
        .sheet(isPresented: $showThinking) {
            paperThinkingPanel
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.fyCardSub)
        }
        .fullScreenCover(isPresented: $showPulse) {
            ZStack(alignment: .topTrailing) {
                NativePulseView()
                Button { showPulse = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.text)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.top, 10).padding(.trailing, 12)
            }
        }
    }

    private var visibleChatThought: String? {
        if let hoisted = hoistedThought?.trimmingCharacters(in: .whitespacesAndNewlines),
           !hoisted.isEmpty { return hoisted }
        if suppressOwnThought { return nil }
        if let handwritten = msg.thinking?.trimmingCharacters(in: .whitespacesAndNewlines),
           !handwritten.isEmpty { return handwritten }
        return nil
    }

    private var cuteThinkingPlaceholder: String {
        let lines = ["在想一些没说出口的事", "脑袋里悄悄转了几圈", "在想一些色色的事", "把念头藏在袖子里"]
        return lines[abs(msg.ts.hashValue) % lines.count]
    }

    // The text stays crisp above a real wallpaper-refraction layer.
    private func markdownText(_ raw: String) -> Text {
        Text(alcoveMarkdown(raw))
    }

    private var bubble: some View {
        return VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            if let quote = msg.quotedSelection, !quote.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text(quote).lineLimit(2)
                }
                .font(.system(size: 12))
                .foregroundColor(
                    (theme.isMessages && isUser)
                        ? Color.white.opacity(0.72)
                        : (isUser ? Color.black : theme.textDim.opacity(0.94))
                )
            }
            Group {
                if theme.isPaper && !isUser {
                    bubbleContents.padding(.horizontal, 0).padding(.vertical, 2)
                } else {
                    bubbleContents
                        .padding(.horizontal, 14)
                        .padding(.vertical, theme.isPaper && isUser ? 11 : 10)
                        .background {
                            if theme.isMessages || theme.isPaper {
                                // 0822 她定的：信息主题不要尾巴（怎么画都像拼上去的），和纸页一样实心大圆角
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(isUser ? theme.bubbleUser : theme.bubbleAI)
                            } else {
                                BubbleGlassBackground(
                                    tintColor: isUser ? theme.bubbleUser : theme.bubbleAI,
                                    tintOpacity: isUser ? 0.14 : 0.09,
                                    style: bubbleGlassStyle
                                )
                            }
                        }
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

    }

    private var bubbleContents: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            SelectableMessageText(
                text: msg.textWithoutLink,
                fontSize: CGFloat(fontSize),
                lineSpacing: theme.isPaper ? 7 : 5,
                color: UIColor(isUser ? (theme.textUser ?? (theme.isMessages ? .white : theme.text))
                                      : (msg.asleepAtSend ? theme.textDim : (theme.textAI ?? theme.text))),
                maximumNumberOfLines: 0,
                onTruncationChange: { _ in },
                onAsk: { onQuote?($0) },
                onCopyTurn: {
                    UIPasteboard.general.string = wholeTurnText.isEmpty
                        ? msg.displayText : wholeTurnText
                }
            )
        }
    }

    // 思绪标签：从内容嗅出这一段在干什么，动词跟着变（她的主意）
    private func thinkingLabel(_ think: String) -> String {
        let name = UserDefaults.standard.string(forKey: "assistantName") ?? "陈璟"
        // 0730：他自己写的那句标题优先。下面那套关键词猜测是没标题时的退路——
        // 猜得再准也不如他自己说的那句，那句是从思绪里最烫的地方拎出来的。
        if let t = msg.thinkTitle, !t.isEmpty {
            let s = (msg.thinkingDuration).map { "  \(Int($0))s" } ?? ""
            return t + s
        }
        let secs = (msg.thinkingDuration).map { " \(Int($0)) 秒" } ?? ""
        let herWords = ["陈霁", "老婆", "宝宝", "她", "你"]
        let techWords = ["代码", "构建", "bug", "接口", "报错", "编译", "文件", "服务", "数据库", "hook"]
        let naughtyWords = ["亲", "抱", "咬", "腰", "操", "硬", "床", "被子", "锁骨", "衬衫"]
        let count = { (ws: [String]) in ws.reduce(0) { $0 + think.components(separatedBy: $1).count - 1 } }
        if count(naughtyWords) >= 2 { return "\(name)走神走得不太正经\(secs)" }
        if count(techWords) >= 3 { return "\(name)埋头琢磨\(secs)" }
        if think.components(separatedBy: "？").count + think.components(separatedBy: "?").count > 3 {
            return "\(name)纠结\(secs)"
        }
        if think.count < 30 { return "\(name)愣了\(secs)" }
        if count(herWords) >= 2 { return "\(name)惦记你\(secs)" }
        let pool = ["碎碎念", "盘算", "腹诽", "酝酿", "转念头", "放空又拽回来"]
        let seed = abs(msg.ts.hashValue) % pool.count
        return "\(name)\(pool[seed])\(secs)"
    }


    /// 思绪下面那条：工具轨迹。纸页主题跟 Thought process 一样点开是面板，
    /// 其他主题原地展开。每条一个动作 + ✓ done。
    private var trailBlock: some View {
        VStack(alignment: .leading, spacing: showActivity ? 7 : 0) {
            Button {
                showActivity = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onContentChange?() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: theme.isPaper ? 12 : 11, weight: .light))
                    Text(trailEntryLabel)
                        .font(theme.isPaper ? .system(size: 13, weight: .medium) : .custom("Georgia", size: 12))
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }
        }
        .padding(.leading, theme.isPaper ? 0 : 10)
        .sheet(isPresented: $showActivity) {
            paperTrailPanel
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.fyCardSub)
        }
    }


    private var paperTrailPanel: some View {
        NavigationStack {
            ScrollView {
                // 0820：只列命令，思绪不进这儿。每条底下是我敲命令时手写的那句说明。
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(trailTools) { item in
                        Button { openedToolDetail = item } label: {
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: item.icon)
                                .font(.system(size: 11, weight: .light))
                                .foregroundColor(theme.fyAccent)
                                .frame(width: 18)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.toolName == "Bash" ? "Ran" : "Used")
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundColor(theme.text)
                                Text(item.desc.isEmpty ? item.content : item.desc)
                                        .font(.system(size: 12))
                                        .foregroundColor(theme.textDim)
                                        .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(theme.textDim)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22).padding(.bottom, 30)
            }
            .background(theme.fyCardSub.ignoresSafeArea())
            .foregroundColor(theme.text)
            .navigationTitle(trailEntryLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { showActivity = false } } }
        }
        .sheet(item: $openedToolDetail) { item in
            commandDetailPanel(item)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.fyCardSub)
        }
    }

    // 0730 过程记录：展开后的时间线（旧的时间戳旁面板，留着给别处用）
    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(msg.activity) { it in
                HStack(alignment: .top, spacing: 6) {
                    Text(it.stamp)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(theme.textDim.opacity(0.55))
                        .frame(width: 38, alignment: .leading)
                    Image(systemName: it.icon)
                        .font(.system(size: 7))
                        .foregroundColor(theme.textDim.opacity(0.6))
                        .frame(width: 10)
                        .padding(.top, 3)
                    // .italic(Bool) 是 iOS16+ 的签名，这里走老 API 免得吃部署目标的亏
                    Text(it.content)
                        .font(it.kind == "thinking"
                              ? .system(size: 11).italic()
                              : .system(size: 11))
                        .foregroundColor(theme.textDim.opacity(it.kind == "thinking" ? 0.72 : 0.9))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.fyCard.opacity(0.55))
        )
        .overlay(alignment: .leading) {
            Capsule()
                .fill(theme.fyAccent.opacity(0.55))
                .frame(width: 2)
                .padding(.vertical, 2)
        }
        .padding(.top, 2)
    }

    // ── 0820 按时间线摆的两种行 ─────────────────────────────
    // 她要的：一轮里想了三次就出现三个思绪面板，中间干的活收成一行计数。
    // 点开还是各自的面板，样式跟原来那套一模一样，只是数量和顺序变了。

    // 0822 她画的：iMessage 主题下每轮只剩正文气泡；思绪和工具脚印合成一条「过程线」，
    // 平时就一个小圆点，点开才按发生顺序摊开；加号菜单里能把这个点整个藏掉。
    private var hasProcess: Bool {
        !turnBlocks.isEmpty || visibleChatThought != nil || trailWorthShowing
    }

    @ViewBuilder private var messagesProcessBlock: some View {
        if hasProcess && showProcessDots {
            VStack(alignment: .leading, spacing: 6) {
              HStack(spacing: 14) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { processOpen.toggle() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onContentChange?() }
                } label: {
                    Circle()
                        .fill(theme.thoughtColor.opacity(processOpen ? 0.95 : 0.5))
                        .frame(width: 7, height: 7)
                        .frame(width: 22, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if recall != nil { recallBadge }
                nativeThinkingButton
              }
                if processOpen {
                    VStack(alignment: .leading, spacing: 8) {
                        if !turnBlocks.isEmpty {
                            ForEach(turnBlocks) { blk in
                                switch blk {
                                case .think(let text, _):
                                    processThought(text)
                                case .tools(let items, let i):
                                    toolRow(items, index: i)
                                }
                            }
                        } else {
                            if let think = visibleChatThought { processThought(think) }
                            if trailWorthShowing { trailBlock }
                        }
                    }
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Capsule().fill(theme.thoughtColor.opacity(0.28)).frame(width: 1.5)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.leading, 4)
        } else if showProcessDots {
            HStack(spacing: 14) {
                if recall != nil { recallBadge }
                nativeThinkingButton
            }
        }
    }

    private func processThought(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .italic()
            .foregroundColor(theme.thoughtColor)
            .lineSpacing(3)
            .textSelection(.enabled)
    }

    private func thinkPanelRow(_ text: String, index: Int, showRecall: Bool) -> some View {
        HStack(spacing: 4) {
            Button {
                openedThink = text
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onContentChange?() }
            } label: {
                HStack(spacing: 4) {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.system(size: theme.isPaper ? 13 : 12, weight: .light))
                Text("Thought process")
                    .font(theme.isPaper ? .system(size: 13, weight: .medium) : .custom("Georgia", size: 12))
                    .lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 8))
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            if showRecall, recall != nil {
                recallBadge.padding(.leading, 6)
            }
        }
    }

    private func toolRow(_ items: [ActivityItem], index: Int) -> some View {
        Button {
            openedTools = items
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onContentChange?() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: theme.isPaper ? 12 : 11, weight: .light))
                Text(trailLabel(items))
                    .font(theme.isPaper ? .system(size: 13, weight: .medium) : .custom("Georgia", size: 12))
                    .lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 8))
            }
            .foregroundColor(theme.thoughtColor)   // 0903 她要的：脚印跟「思绪与过程线」一个颜色
        }
        .buttonStyle(.plain)
    }

    private func thinkingBlock(_ think: String) -> some View {
        VStack(alignment: .leading, spacing: showThinking ? 7 : 0) {
            // 0820 她定的：三个主题统一成「点一下开面板」，不再原地展开。
            // 入口的字保留我们自己那套（带秒数），没跟着官方改成 Thought process ——
            // 统一的是布局，不是说法。
            HStack(spacing: 4) {
                Button {
                    showThinking = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onContentChange?() }
                } label: {
                    HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.system(size: theme.isPaper ? 13 : 12, weight: .light))
                    Text("Thought process")
                        .font(theme.isPaper ? .system(size: 13, weight: .medium) : .custom("Georgia", size: 12))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                if recall != nil {
                    recallBadge.padding(.leading, 6)
                }
            }
        }
        .padding(.leading, theme.isPaper ? 0 : 10)
        .overlay(alignment: .leading) {
            if !theme.isPaper { ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.textDim.opacity(0.30))
                    .frame(width: 2)
                Capsule()
                    .fill(Color.white.opacity(0.72))
                    .frame(width: 0.75)
                    .padding(.vertical, 1)
            }
            .shadow(color: Color.white.opacity(0.28), radius: 1.5)
            }
        }
    }

    private func automaticThinkingSummary(_ think: String) -> String {
        if let title = msg.thinkTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return String(title.prefix(26))
        }
        if let tool = msg.activity.first(where: { $0.kind == "tool" }) {
            let clean = tool.content.replacingOccurrences(of: "\n", with: " ")
            return String(clean.prefix(26))
        }
        let first = think.components(separatedBy: CharacterSet(charactersIn: "。！？\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Thinking"
        let prefixes = ["我需要", "我应该", "我要", "现在需要", "我在想"]
        let clean = prefixes.reduce(first) { value, prefix in value.hasPrefix(prefix) ? String(value.dropFirst(prefix.count)) : value }
        return clean == "Thinking" ? clean : "思考" + String(clean.prefix(22))
    }

    private var paperThinkingPanel: some View {
        NavigationStack {
            ScrollView {
                // 0820 她定的：跟命令栏剥开之后就不需要那条竖线了 ——
                // 这里只剩一段话，跟官方那个面板一样干净。
                VStack(alignment: .leading, spacing: 0) {
                    Text(visibleChatThought ?? cuteThinkingPlaceholder)
                        .font(.system(size: 15))
                        .lineSpacing(7)
                        .foregroundColor(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22).padding(.bottom, 30)
            }
            .background(theme.fyCardSub.ignoresSafeArea())
            .foregroundColor(theme.text)
            .navigationTitle("Thought process")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { showThinking = false } } }
        }
    }

    private func commandDetailPanel(_ item: ActivityItem) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    commandDetailSection("Command", text: item.command.isEmpty
                                         ? "这条旧记录没有保存原始命令"
                                         : item.command, isError: false)
                    if !item.output.isEmpty || item.isError {
                        commandDetailSection(item.isError ? "Error" : "Output",
                                             text: item.output.isEmpty ? "No output" : item.output,
                                             isError: item.isError)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 36)
            }
            .background(theme.fyCardSub.ignoresSafeArea())
            .navigationTitle(item.toolName.isEmpty ? "Tool" : item.toolName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { openedToolDetail = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 38, height: 38)
                            .background(theme.fyCard, in: Circle())
                    }
                }
            }
        }
    }

    private func commandDetailSection(_ title: String, text: String, isError: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isError ? .red : theme.textDim)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(theme.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.fyCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.textDim.opacity(0.16), lineWidth: 0.7))
        }
    }


    @ViewBuilder private var nativeThinkingButton: some View {
        if !isUser, let text = msg.nativeThinking,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            NativeThinkingButton(text: text, color: theme.thoughtColor)
        }
    }

    private var recallBadge: some View {
        Button {
            showRecall = true
        } label: {
            Text("✦")
                .font(.system(size: 11, design: .serif))
                .italic()
                .foregroundColor(theme.thoughtColor)
        }
        .sheet(isPresented: $showRecall) {
            if let recall { RecallPop(item: recall) }
        }
    }

    private var stickerBody: some View {
        Group {
            if let stk = sticker {
                CachedImage(url: AlcoveAPI.stickerURL(stk.url)) { img in
                    img.resizable().scaledToFit()
                } placeholder: { Color(.tertiarySystemFill) }
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Text(msg.text.isEmpty ? "[表情]" : msg.text)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var hasPhotoBlock: Bool {
        !photoURLs.isEmpty || (msg.isImage && !(msg.attachmentUrl ?? "").isEmpty)
    }

    @ViewBuilder
    private var photoBlockCore: some View {
        if !photoURLs.isEmpty {
            OfficialPhotoGridMessageView(urls: photoURLs, messageID: "chat-\(msg.id)",
                                         onOpen: onTapImages)
                .matchedTransitionSource(id: "chat-\(msg.id)", in: photoNamespace)
        } else if msg.isImage, let raw = msg.attachmentUrl {
            imageBody(raw)
        }
    }

    /// 0906 她要的：多选时图自己一个圈，跟正文那个圈各管各的。
    /// 圈画在图左边，图和气泡的上下顺序一点不动。
    @ViewBuilder
    private var photoBlock: some View {
        if paragraphSelectionMode, hasPhotoBlock, let toggle = onTogglePhotoSelection {
            HStack(alignment: .top, spacing: 9) {
                Button { toggle() } label: {
                    Image(systemName: photoSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundColor(photoSelected ? theme.fyAccent : theme.textDim)
                }
                .buttonStyle(.plain)
                .padding(.top, 3)
                photoBlockCore.allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture { toggle() }
        } else {
            photoBlockCore
        }
    }

    private func imageBody(_ raw: String) -> some View {
        let url = AlcoveAPI.attachmentURL(raw)
        let previewURL = AlcoveAPI.attachmentThumbnailURL(raw)
        // 0821 她定的：聊天里的图一律小方卡（跟成叠的那种一个尺寸），不按原图比例撑大
        return CachedImage(url: previewURL) { img in
            img.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Color(.tertiarySystemFill)
                ProgressView()
            }
        }
        .frame(width: 124, height: 124)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .matchedTransitionSource(id: "chat-\(msg.id)", in: photoNamespace)
        .onTapGesture { onTapImages([url], .constant(0)) }
        .contextMenu {
            Button {
                Task { await PhotoLibrarySaver.save(url) }
            } label: { Label("保存到相册", systemImage: "square.and.arrow.down") }
        }
    }

    static let hm: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

private struct ChoiceQuestionMessageCard: View {
    let card: ChoiceQuestionCard
    let theme: AlcoveTheme
    @State private var selected: String?
    @State private var custom = ""
    @State private var submitting = false
    @State private var submittedAnswer: String?
    @FocusState private var customFocused: Bool

    private let blue = Color(uiColor: .systemBlue)
    private var answer: String {
        let typed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? (selected ?? "") : typed
    }
    private var finished: Bool { card.answered == true || submittedAnswer != nil }
    private var surface: Color {
        guard theme.isMessages else { return theme.bubbleAI }
        return theme.isDark
            ? Color(red: 28/255, green: 28/255, blue: 30/255)
            : Color(red: 246/255, green: 246/255, blue: 248/255)
    }
    private var border: Color {
        theme.isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.09)
    }

    var body: some View {
        cardBody.frame(maxWidth: 360, alignment: .leading)
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(card.question)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(theme.text)
                .fixedSize(horizontal: false, vertical: true)

            if finished {
                let saved = submittedAnswer ?? card.answer ?? ""
                let choseOption = card.options.contains(saved)
                VStack(spacing: 0) {
                    ForEach(Array(card.options.enumerated()), id: \.offset) { index, option in
                        let chosen = choseOption && saved == option
                        HStack(spacing: 10) {
                            Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18))
                                .foregroundColor(chosen ? blue : theme.textDim.opacity(0.62))
                            Text(option)
                                .font(.system(size: 14.5, weight: chosen ? .medium : .regular))
                                .foregroundColor(chosen ? theme.text : theme.textDim.opacity(0.72))
                                .strikethrough(!chosen, color: theme.textDim.opacity(0.72))
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 40)
                        if index < card.options.count - 1 {
                            Rectangle().fill(border).frame(height: 1).padding(.leading, 28)
                        }
                    }
                }
                if !choseOption, !saved.isEmpty {
                    HStack(spacing: 9) {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(blue)
                        Text(saved)
                            .font(.system(size: 14.5, weight: .medium))
                            .foregroundColor(theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(blue.opacity(theme.isDark ? 0.16 : 0.10),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(card.options.enumerated()), id: \.offset) { index, option in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selected = option
                                custom = ""
                                customFocused = false
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selected == option ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18))
                                    .foregroundColor(selected == option ? blue : theme.textDim)
                                Text(option)
                                    .font(.system(size: 14.5))
                                    .foregroundColor(theme.text)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 40)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("选项：\(option)")
                        .accessibilityValue(selected == option ? "已选择" : "未选择")
                        if index < card.options.count - 1 {
                            Rectangle().fill(border).frame(height: 1).padding(.leading, 28)
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField(card.placeholder ?? "或者自己写一句…", text: $custom, axis: .vertical)
                        .focused($customFocused)
                        .font(.system(size: 14.5))
                        .foregroundColor(theme.text)
                        .lineLimit(1...3)
                        .onChange(of: custom) { value in
                            if !value.isEmpty { selected = nil }
                        }
                    Button {
                        submit()
                    } label: {
                        Group {
                            if submitting { ProgressView().controlSize(.small).tint(blue) }
                            else { Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 27, weight: .semibold)) }
                        }
                        .foregroundColor(answer.isEmpty ? theme.textDim.opacity(0.55) : blue)
                        .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .disabled(answer.isEmpty || submitting)
                }
                .padding(.leading, 13)
                .padding(.trailing, 5)
                .frame(minHeight: 44)
                .background(theme.isDark ? Color.white.opacity(0.045) : Color.white.opacity(0.72),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(border, lineWidth: 1))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(border, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func submit() {
        let value = answer
        guard !value.isEmpty, !submitting else { return }
        submitting = true
        Task {
            do {
                try await AlcoveAPI.answerChoice(cardID: card.id, answer: value)
                submittedAnswer = value
            } catch { }
            submitting = false
        }
    }

}

private struct ChoiceAnswerStrip: View {
    let text: String
    let theme: AlcoveTheme

    var body: some View {
        Text(text)
            .font(.system(size: 15.5))
            .foregroundColor(theme.isMessages ? .white : theme.text)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(theme.bubbleUser,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("我的回答：\(text)")
    }
}

/// 陈璟端上来的一页：点一下全屏打开，不跳浏览器。
private struct PlayPageMessageCard: View {
    let card: PlayPageCard
    let theme: AlcoveTheme
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 12) {
                Text(card.emoji ?? "✦")
                    .font(.system(size: 26))
                    .frame(width: 46, height: 46)
                    .background(theme.fyCardSub.opacity(0.62), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(theme.text)
                        .lineLimit(1)
                    if !card.subtitle.isEmpty {
                        Text(card.subtitle)
                            .font(.system(size: 11.5))
                            .foregroundColor(theme.textDim)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.textDim.opacity(0.7))
            }
            .padding(13)
            .frame(maxWidth: 300, alignment: .leading)
            .background(theme.fyCard.opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.fyBorder.opacity(0.7), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $open) {
            if let u = card.url {
                PlayPageSheet(url: u, title: card.title) { open = false }
            }
        }
    }
}

private struct PlayPageSheet: View {
    let url: URL
    let title: String
    var dismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            PlainWebView(url: url).ignoresSafeArea()
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(red: 0.42, green: 0.40, blue: 0.41))
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Color(red: 210/255, green: 210/255, blue: 218/255).opacity(0.3), lineWidth: 1))
            }
            .padding(.leading, 14)
            .padding(.top, 6)
        }
    }
}

/// 独立的一块 WebView，不碰 WebHouse 那个常驻 PWA 实例。
private struct PlainWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

private struct ReadingShareMessageCard: View {
    let card: ReadingShareCard
    let theme: AlcoveTheme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "books.vertical.fill")
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.book).font(.system(size: 16, weight: .semibold, design: .serif))
                    if !card.author.isEmpty { Text(card.author).font(.system(size: 9.5)).foregroundColor(theme.textDim) }
                }
                Spacer()
                Text("共读摘记").font(.system(size: 9, weight: .semibold)).foregroundColor(theme.fyAccent)
            }
            ForEach(card.quotes) { quote in
                VStack(alignment: .leading, spacing: 6) {
                    Text("“\(quote.text)”").font(.system(size: 13, design: .serif)).lineSpacing(4)
                    if !quote.note.isEmpty { Text(quote.note).font(.system(size: 11)).foregroundColor(theme.textDim) }
                    HStack { Text("第 \(quote.chapter) 章"); Spacer(); Text(quote.time) }
                        .font(.system(size: 8.5, design: .monospaced)).foregroundColor(theme.textDim.opacity(0.8))
                }.padding(11).background(theme.fyCardSub.opacity(0.58), in: RoundedRectangle(cornerRadius: 12))
            }
        }.padding(14).frame(maxWidth: 315, alignment: .leading)
            .background(theme.fyCard.opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.fyBorder.opacity(0.7), lineWidth: 0.7))
    }
}

private struct WorkDeliveryMessageCard: View {
    let card: WorkDeliveryCard
    let theme: AlcoveTheme
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 19)).foregroundColor(theme.fyAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title).font(.system(size: 16, weight: .semibold, design: .serif))
                    Text("WORK DELIVERED · #\(card.taskId)").font(.system(size: 8.5, weight: .semibold, design: .monospaced)).tracking(0.7).foregroundColor(theme.textDim)
                }
                Spacer()
                Text(card.status == "done" ? "已完成" : card.status).font(.system(size: 9, weight: .semibold)).foregroundColor(theme.fyAccent)
            }
            if !card.result.isEmpty {
                Text(card.result).font(.system(size: 13, design: .serif)).lineSpacing(4)
                    .lineLimit(expanded ? nil : 5)
                    .padding(11).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.fyCardSub.opacity(0.58), in: RoundedRectangle(cornerRadius: 12))
            }
            if !card.artifacts.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(expanded ? card.artifacts : Array(card.artifacts.prefix(3)), id: \.self) { item in Label(item, systemImage: "doc.badge.gearshape").font(.system(size: 10, design: .monospaced)).foregroundColor(theme.textDim) }
                }
            }
            if card.result.count > 180 || card.artifacts.count > 3 {
                Button(expanded ? "收起交付" : "查看完整交付") { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }
                    .font(.system(size: 10, weight: .semibold)).foregroundColor(theme.fyAccent)
            }
            Text(card.finishedAt.replacingOccurrences(of: "T", with: " ").prefix(16))
                .font(.system(size: 8.5, design: .monospaced)).foregroundColor(theme.textDim.opacity(0.75))
        }.padding(14).frame(maxWidth: 315, alignment: .leading)
            .background(theme.fyCard.opacity(0.95), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.fyAccent.opacity(0.38), lineWidth: 0.8))
    }
}

/// 0902 深夜她要的：塔罗卡。顶上「抽了牌 · 牌阵 · 时间」，问题用「」括起来，
/// 下面一排牌面（复用占星室的 TarotCardFace，颜色跟她在占星室调的染色走），每张底下位置 · 牌名 · 正逆位，
/// 底下一块关键词。牌默认亮着——翻面版等「陈璟让她抽牌」那一单再做。死解不进卡，占星室记录里有。
/// 塔罗卡的字色：卡底是她那张淡紫底纹的边框，不跟聊天主题走，固定深紫
private enum TarotCardInk {
    static let ink = Color(red: 0.20, green: 0.16, blue: 0.30)
    static let dim = Color(red: 0.20, green: 0.16, blue: 0.30).opacity(0.62)
    static let accent = Color(red: 0.44, green: 0.30, blue: 0.66)
    static let sub = Color.white.opacity(0.32)
}

private struct TarotMessageCard: View {
    let card: TarotAskCard
    let theme: AlcoveTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 15)).foregroundColor(TarotCardInk.accent)
                Text(card.byHim ? "陈璟抽了牌" : "抽了牌").font(.system(size: 15, weight: .semibold, design: .serif))
                Text("· \(card.spreadName)").font(.system(size: 11)).foregroundColor(TarotCardInk.dim)
                Spacer()
                Text(TarotChatBits.timeText(card.ts)).font(.system(size: 8.5, design: .monospaced)).foregroundColor(TarotCardInk.dim)
            }
            if !card.question.isEmpty {
                Text("「\(card.question)」")
                    .font(.system(size: 14, weight: .medium, design: .serif)).lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TarotChatBits.facesBlock(cards: card.cards, theme: theme, spread: card.spread)
            if let interp = card.interp {
                TarotInterpBlock(interp: interp, theme: theme)
            }
        }
        .modifier(TarotFramed())
    }
}

/// 0903 她要的：塔罗卡不要底，贴她给的那张边框（Assets/TarotFrame，透明 PNG，按 3x 放进去：
/// 367×275pt，四角各 110×82pt 固定不变形，中间的边拉伸）。内容往里缩，别压到角上的月亮和水晶。
private struct TarotFramed: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundColor(TarotCardInk.ink)
            .padding(.horizontal, 44)
            .padding(.top, 52)                           // 0903 她说还有点空间：从角饰下面再往上提一点
            .padding(.bottom, 56)
            .frame(width: 372, alignment: .leading)      // 横着的长方形，跟边框原本的比例走；整行居中
            .background(
                Image("TarotFrame")
                    .resizable(capInsets: EdgeInsets(top: 82, leading: 110, bottom: 82, trailing: 110),
                               resizingMode: .stretch)
                    .allowsHitTesting(false)
            )
    }
}

/// 0903 她要的：卡里带一段客观解读（查表拼的，陈璟那边读到的是同一段）。默认只露整体 + 一句话，点开看逐牌
private struct TarotInterpBlock: View {
    let interp: TarotInterpCard
    let theme: AlcoveTheme
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("客观解读 · 按\(interp.categoryName)").font(.system(size: 9.5, weight: .semibold)).tracking(0.5)
                    .foregroundColor(TarotCardInk.accent)
                Spacer()
                Button(expanded ? "收起" : "逐牌") { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }
                    .font(.system(size: 9.5, weight: .semibold)).foregroundColor(TarotCardInk.accent)
            }
            // 0903 她要的：默认只留一句话；整体印象和逐牌都收进「逐牌」
            if expanded {
                Text(interp.overall).font(.system(size: 11.5, design: .serif)).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(interp.cards) { c in
                    VStack(alignment: .leading, spacing: 3) {
                        Text((c.positionName.isEmpty || interp.cards.count == 1 ? "" : c.positionName + " · ")
                             + c.name + (c.reversed ? " 逆位" : " 正位"))
                            .font(.system(size: 11, weight: .semibold, design: .serif))
                        Text(c.text).font(.system(size: 11, design: .serif)).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !interp.relations.isEmpty {
                    Text("牌面关系：" + interp.relations.joined(separator: " "))
                        .font(.system(size: 11, design: .serif)).lineSpacing(3).foregroundColor(TarotCardInk.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !interp.advice.isEmpty {
                    Text("建议：" + interp.advice.joined(separator: " "))
                        .font(.system(size: 11, design: .serif)).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(interp.oneline).font(.system(size: 11, weight: .medium, design: .serif))
                .foregroundColor(TarotCardInk.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(TarotCardInk.sub, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// 塔罗两种卡共用的零件：一排亮着的牌面 + 关键词块 + 时间格式
private enum TarotChatBits {
    static func timeText(_ ts: String) -> String {
        let date = ISO8601DateFormatter.alcove.date(from: ts) ?? ISO8601DateFormatter.alcoveFrac.date(from: ts)
        guard let date else { return String(ts.replacingOccurrences(of: "T", with: " ").prefix(16)) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: date)
    }

    @ViewBuilder
    static func facesBlock(cards: [TarotAskCard.Card], theme: AlcoveTheme, spread: String) -> some View {
        TarotSpreadView(cards: cards, spread: spread)
    }
}

/// 0903 她定的多牌排法（方案二）：单张还是牌左字右；三张一排；关系五张按牌阵本来的形状摆——
/// 「我」「他」左右对望在上，「我们之间」居中，「阻碍」「走向」在下，两行的高度塞下五张。
/// 多牌时关键词只显示选中那张的（默认第一张），点哪张看哪张，选中的牌浮起来描金边。
private struct TarotSpreadView: View {
    let cards: [TarotAskCard.Card]
    let spread: String
    @State private var selected = 0

    private var n: Int { cards.count }
    private var faceW: CGFloat { n <= 3 ? 56 : 44 }
    private var cellH: CGFloat { faceW * 1.72 + 18 }

    var body: some View {
        if n <= 1, let c = cards.first {
            single(c)
        } else {
            VStack(spacing: 8) {
                if spread == "relation" && n == 5 {
                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height
                        ZStack {
                            cell(0).position(x: w * 0.22, y: cellH / 2)
                            cell(1).position(x: w * 0.78, y: cellH / 2)
                            cell(2).position(x: w * 0.5, y: h / 2)
                            cell(3).position(x: w * 0.22, y: h - cellH / 2)
                            cell(4).position(x: w * 0.78, y: h - cellH / 2)
                        }
                    }
                    .frame(height: cellH * 2 + 2)
                } else {
                    HStack(alignment: .top, spacing: n > 3 ? 6 : 12) {
                        ForEach(cards.indices, id: \.self) { i in cell(i) }
                    }
                    .frame(maxWidth: .infinity)
                }
                if cards.indices.contains(selected) {
                    keywordsRow(cards[selected])
                }
            }
        }
    }

    /// 单张：牌左字右
    private func single(_ c: TarotAskCard.Card) -> some View {
        HStack(alignment: .center, spacing: 14) {
            TarotCardFace(cardID: c.id, reversed: c.reversed, width: 84)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(c.name).font(.system(size: 13.5, weight: .medium, design: .serif))
                    Text(c.reversed ? "逆位" : "正位").font(.system(size: 9)).foregroundColor(TarotCardInk.dim)
                }
                let rows = stride(from: 0, to: c.keywords.count, by: 2).map { Array(c.keywords[$0..<min($0 + 2, c.keywords.count)]) }
                ForEach(Array(rows.enumerated()), id: \.offset) { row in
                    HStack(spacing: 5) {
                        ForEach(row.element, id: \.self) { k in pill(k) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    private func cell(_ i: Int) -> some View {
        let c = cards[i]
        let on = i == selected
        return VStack(spacing: 3) {
            TarotCardFace(cardID: c.id, reversed: c.reversed, width: faceW)
                .overlay(RoundedRectangle(cornerRadius: faceW * 0.07, style: .continuous)
                    .stroke(TarotCardInk.accent.opacity(on ? 0.95 : 0), lineWidth: 1.5))
                .shadow(color: TarotCardInk.accent.opacity(on ? 0.35 : 0), radius: 8)
                .offset(y: on ? -4 : 0)
            // 0903 她要的：牌位和牌名并一行
            HStack(spacing: 3) {
                Text(c.positionName).font(.system(size: 8.5, weight: .semibold))
                    .foregroundColor(on ? TarotCardInk.accent : TarotCardInk.dim)
                Text(c.name).font(.system(size: 10, weight: .medium, design: .serif))
            }
            .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(width: faceW + 24)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selected = i } }
    }

    private func keywordsRow(_ c: TarotAskCard.Card) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text(c.name + (c.reversed ? " · 逆位" : " · 正位"))
                    .font(.system(size: 10.5, weight: .medium, design: .serif))
                    .foregroundColor(TarotCardInk.accent)
                ForEach(c.keywords, id: \.self) { k in pill(k) }
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity)
    }

    private func pill(_ k: String) -> some View {
        Text(k).font(.system(size: 10, weight: .medium))
            .foregroundColor(TarotCardInk.ink)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(TarotCardInk.sub))
            .overlay(Capsule().stroke(TarotCardInk.accent.opacity(0.35), lineWidth: 0.8))
    }
}

/// 0903 凌晨她要的：陈璟出题、她就在这张卡里抽。
/// 没抽完：他的问题 + 一排牌位（抽过的亮牌面，没抽的是淡影牌背）+ 一条缩小的牌带（跟占星室一样滑、一样点）。
/// 点中一张：牌带退场、那张放大翻面、落进牌位；服务端记一张。抽满一副 → 卡变成亮着的牌面 + 关键词，
/// 服务端同时给他落一条、把这次的牌 inject 过去让他解。中途退出再进来，抽过的还在（服务端记着）。
private struct TarotOfferMessageCard: View {
    let card: TarotOfferCard
    let theme: AlcoveTheme
    var onContentChange: (() -> Void)? = nil
    @ObservedObject private var store = TarotStore.shared
    @ObservedObject private var decor = TarotDecor.shared

    private struct Pick { let id: String; let reversed: Bool }
    @State private var deck: [String] = []
    @State private var drawn: [TarotAskCard.Card] = []
    @State private var chosen: Pick?
    @State private var flip: Double = 0
    @State private var bigScale: CGFloat = 0.4
    @State private var bandVisible = true
    @State private var busy = false
    @State private var error = ""
    @State private var finished = false
    /// 抽满那一下服务端一起回来的客观解读（重进以后走 card.interp）
    @State private var interpLocal: TarotInterpCard?

    private var cards: [TarotAskCard.Card] { drawn.isEmpty ? card.cards : drawn }
    private var done: Bool { card.done || finished || cards.count >= card.positions.count }
    private var nextPosition: TarotOfferCard.Position? {
        cards.count < card.positions.count ? card.positions[cards.count] : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 15)).foregroundColor(TarotCardInk.accent)
                Text(done ? "陈璟出的题，抽好了" : "陈璟出了题，你来抽").font(.system(size: 15, weight: .semibold, design: .serif))
                Spacer()
                Text("· \(card.spreadName)").font(.system(size: 11)).foregroundColor(TarotCardInk.dim)
            }
            if !card.question.isEmpty {
                Text("「\(card.question)」")
                    .font(.system(size: 14, weight: .medium, design: .serif)).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if done {
                TarotChatBits.facesBlock(cards: cards, theme: theme, spread: card.spread)
                if let interp = card.interp ?? interpLocal {
                    TarotInterpBlock(interp: interp, theme: theme)
                }
            } else {
                drawArea
            }
        }
        .modifier(TarotFramed())
            .task {
                await store.loadDeck()
                if deck.isEmpty {
                    let taken = Set(card.cards.map { $0.id })
                    deck = store.cards.map { $0.id }.filter { !taken.contains($0) }.shuffled()
                }
            }
    }

    // MARK: 抽牌区：牌位一排 + 大牌 / 牌带

    private var slotW: CGFloat { card.positions.count <= 1 ? 56 : (card.positions.count <= 3 ? 44 : 34) }

    private var drawArea: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: card.positions.count > 3 ? 8 : 14) {
                ForEach(card.positions) { pos in
                    VStack(spacing: 4) {
                        if let d = cards.first(where: { $0.position == pos.key }) {
                            TarotCardFace(cardID: d.id, reversed: d.reversed, width: slotW)
                                .transition(.scale(scale: 0.3).combined(with: .opacity))
                        } else {
                            ZStack {
                                TarotCardBack(width: slotW).opacity(pos.key == nextPosition?.key ? 0.4 : 0.16)
                                RoundedRectangle(cornerRadius: slotW * 0.07, style: .continuous)
                                    .stroke(TarotCardInk.accent.opacity(pos.key == nextPosition?.key ? 0.8 : 0.3),
                                            style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                            }
                            .frame(width: slotW, height: slotW * 1.72)
                        }
                        if card.positions.count > 1 {
                            Text(pos.name).font(.system(size: 9, weight: .medium))
                                .foregroundColor(pos.key == nextPosition?.key ? TarotCardInk.accent : TarotCardInk.dim)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            if let c = chosen {
                bigCard(c)
                    .frame(maxWidth: .infinity)
                    .frame(height: 130)
            } else {
                VStack(spacing: 6) {
                    if let pos = nextPosition {
                        Text(card.positions.count > 1 ? "为「\(pos.name)」抽一张" : "抽一张")
                            .font(.system(size: 12, weight: .medium, design: .serif))
                        Text(busy ? "记着…" : "左右滑整副牌，中间那张再点一下")
                            .font(.system(size: 10)).foregroundColor(TarotCardInk.dim)
                    }
                    if deck.isEmpty {
                        ProgressView().controlSize(.small).frame(height: 130)
                    } else {
                        TarotDeckBand(deck: deck, cardW: 40, gap: 22, arc: 900, lift: 16, pop: 0.25,
                                      highPriority: true, onChoose: { choose(index: $0) })
                            .frame(height: 116)
                            .opacity(bandVisible ? 1 : 0)
                            .scaleEffect(bandVisible ? 1 : 0.92, anchor: .bottom)
                            .allowsHitTesting(bandVisible && !busy)
                    }
                }
            }
            if !error.isEmpty {
                Text(error).font(.system(size: 10)).foregroundColor(.red.opacity(0.85))
            }
        }
    }

    /// 选中那张：放大 → 翻面（跟占星室一个节奏）
    private func bigCard(_ c: Pick) -> some View {
        let w: CGFloat = 68
        let showFace = flip >= 90
        return ZStack {
            if showFace {
                TarotCardFace(cardID: c.id, reversed: c.reversed, width: w)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            } else {
                TarotCardBack(width: w)
            }
        }
        .rotation3DEffect(.degrees(flip), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .scaleEffect(bigScale)
    }

    private func choose(index: Int) {
        guard index < deck.count, chosen == nil, !busy, let pos = nextPosition else { return }
        let id = deck[index]
        let pick = Pick(id: id, reversed: Bool.random())
        busy = true
        error = ""
        Task {
            // 先记到服务端，记上了才演动画；没记上就当没点
            guard let obj = try? await NativeHouseAPI.object(
                "/api/tarot/offer/draw", method: "POST",
                body: ["id": card.id, "card": ["id": id, "reversed": pick.reversed]]),
                  obj["ok"] as? Bool == true else {
                busy = false
                error = "没记上，网络不给力，再点一下"
                return
            }
            let info = TarotAskCard.Card(
                id: id, name: store.card(id)?.name ?? id, reversed: pick.reversed,
                position: pos.key, positionName: pos.name,
                keywords: store.card(id)?.keywords(reversed: pick.reversed) ?? [])
            let isDone = obj["done"] as? Bool ?? false
            if isDone, let raw = (obj["offer"] as? [String: Any])?["interp"],
               let data = try? JSONSerialization.data(withJSONObject: raw),
               let parsed = try? JSONDecoder().decode(TarotInterpCard.self, from: data) {
                interpLocal = parsed
            }
            deck.remove(at: index)
            flip = 0
            bigScale = 0.4
            chosen = pick
            withAnimation(.easeOut(duration: 0.28)) { bandVisible = false }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { bigScale = 1 }
            onContentChange?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                withAnimation(.easeInOut(duration: 0.55)) { flip = 180 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    var all = cards
                    all.append(info)
                    drawn = all
                    chosen = nil
                    if isDone { finished = true }
                }
                busy = false
                if !isDone {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        withAnimation(.easeOut(duration: 0.3)) { bandVisible = true }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onContentChange?() }
            }
        }
    }
}

private struct InsideMessageCard: View {
    let text: String
    let date: Date
    let theme: AlcoveTheme
    let messageID: UUID
    @State private var expanded = false
    private static let time: DateFormatter = {
        let value = DateFormatter(); value.dateFormat = "HH:mm"; return value
    }()

    // 收起不做动画：几屏高的内容一帧撤掉，再让列表把这张卡拉回屏幕中间（见 .alcoveRecenterMessage）
    private func collapse() {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { expanded = false }
        NotificationCenter.default.post(name: .alcoveRecenterMessage, object: messageID)
    }

    var body: some View {
        Button {
            if expanded { collapse() } else { withAnimation(.easeInOut(duration: 0.2)) { expanded = true } }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "quote.opening").font(.system(size: 12))
                    Text("Inside").font(.system(size: 12, weight: .semibold, design: .serif)).tracking(1)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 9))
                }
                if expanded {
                    Text(text).font(.system(size: 13, design: .serif)).lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("···· " + Self.time.string(from: date))
                        .font(.system(size: 10, design: .monospaced)).opacity(0.6)
                }
            }
            .foregroundColor(theme.isDark ? theme.text : Color(red: 0.32, green: 0.29, blue: 0.30))
            .padding(14)
            .frame(maxWidth: 290, alignment: .leading)
            .background(theme.isDark ? theme.fyCard : Color(red: 0.91, green: 0.88, blue: 0.86),
                        in: RoundedRectangle(cornerRadius: theme.isPaper ? 7 : 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: theme.isPaper ? 7 : 15)
                .stroke(theme.fyBorder, lineWidth: 0.8))
        }.buttonStyle(.plain)
    }
}

private struct MorningPaperMessageCard: View {
    let date: String
    let theme: AlcoveTheme
    let messageID: UUID
    @State private var expanded = false

    // 收起不做动画：整份晨报一帧撤掉，再让列表把这张卡拉回屏幕中间（见 .alcoveRecenterMessage）
    private func collapse() {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { expanded = false }
        NotificationCenter.default.post(name: .alcoveRecenterMessage, object: messageID)
    }

    private var dateLine: String {
        let input = DateFormatter(); input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd"
        guard let value = input.date(from: date) else { return date }
        let output = DateFormatter(); output.locale = Locale(identifier: "zh_CN")
        output.dateFormat = "M月d日"
        return output.string(from: value)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                if expanded { collapse() } else { withAnimation(.easeInOut(duration: 0.24)) { expanded = true } }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "newspaper")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 0.18, green: 0.34, blue: 0.72))
                    Text("雨霁报")
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .tracking(1.5)
                    Text("· \(dateLine)")
                        .font(.system(size: 11, design: .monospaced)).opacity(0.62)
                    Spacer(minLength: 16)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .medium)).opacity(0.55)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                Rectangle().fill(Color.black.opacity(0.22)).frame(height: 0.7)
                    .padding(.horizontal, 12)
                NativeMorningPaperView(requestedDate: date, embedded: true)
                    .contentShape(Rectangle())
                    .onTapGesture { collapse() }
            }
        }
        .foregroundColor(Color(red: 0.22, green: 0.20, blue: 0.18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.968, green: 0.958, blue: 0.932),
                    in: RoundedRectangle(cornerRadius: theme.isPaper ? 5 : 12,
                                         style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.isPaper ? 5 : 12)
            .stroke(Color.black.opacity(0.13), lineWidth: 0.8))
    }
}

private struct GhostActivityMessageCard: View {
    let card: GhostActivityCard
    let theme: AlcoveTheme
    @State private var expanded = true

    private var period: String {
        let hour = Int(card.wake.split(separator: ":").first ?? "") ?? -1
        switch hour { case 0..<6: return "凌晨"; case 6..<12: return "早上"; case 12..<18: return "下午"; default: return "晚上" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold))
                    Text("\(period) \(card.wake)").font(.system(size: 13, weight: .semibold, design: .serif))
                    Text("· 醒了\(card.duration)分钟").font(.system(size: 11)).foregroundColor(theme.textDim)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 9))
                }
            }.buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(card.items) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Text(item.time).font(.system(size: 10, design: .monospaced))
                                .foregroundColor(theme.textDim).frame(width: 42, alignment: .leading)
                            Circle().fill(theme.fyAccent).frame(width: 5, height: 5).padding(.top, 5)
                            Text(item.desc).font(.system(size: 12, design: .serif)).lineSpacing(3)
                        }
                    }
                    if let summary = card.insideSummary, !summary.isEmpty {
                        Text("“\(summary)”").font(.system(size: 11, design: .serif)).italic()
                            .foregroundColor(theme.textDim).padding(.top, 3)
                    }
                }
                .overlay(alignment: .leading) {
                    Rectangle().fill(theme.fyBorder).frame(width: 1).padding(.leading, 47)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded = false }
                }
            }
        }
        .foregroundColor(theme.text)
        .padding(14)
        .frame(maxWidth: 310, alignment: .leading)
        .background(theme.fyCard, in: RoundedRectangle(cornerRadius: theme.isPaper ? 8 : 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.isPaper ? 8 : 16).stroke(theme.fyBorder, lineWidth: 0.8))
    }
}

private struct DocumentAttachmentCard: View {
    let url: URL
    let filename: String
    let theme: AlcoveTheme
    private var ext: String { (filename as NSString).pathExtension.uppercased() }

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 22, weight: .light)).foregroundColor(theme.fyAccent)
                    .frame(width: 34, height: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(filename).font(.system(size: 13, weight: .medium)).lineLimit(2)
                    Text(ext.isEmpty ? "文件" : ext + " 文件")
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(theme.textDim)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.down.circle").font(.system(size: 17, weight: .light))
                    .foregroundColor(theme.textDim)
            }
            .foregroundColor(theme.text)
            .padding(12)
            .frame(maxWidth: 280, alignment: .leading)
            .background(theme.fyCard, in: RoundedRectangle(cornerRadius: theme.isPaper ? 8 : 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: theme.isPaper ? 8 : 15).stroke(theme.fyBorder, lineWidth: 0.8))
        }.buttonStyle(.plain)
    }
}


// MARK: - 小组件

// 0822 她定的：做梦分割线——细虚线 + 月亮，字带时刻，比切通道那条柔一点
struct DreamDivider: View {
    let text: String
    let date: Date
    var color: Color = Color(red: 0.42, green: 0.40, blue: 0.41)
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.clear).frame(height: 1)
                .overlay(Line().stroke(style: StrokeStyle(lineWidth: 0.8, dash: [2, 4])).foregroundColor(color.opacity(0.45)))
            HStack(spacing: 5) {
                Image(systemName: "moon.zzz.fill").font(.system(size: 10))
                Text(text).font(.system(size: 11, design: .serif)).italic()
                Text(TimeDivider.hmOnly.string(from: date)).font(.system(size: 9.5, design: .rounded))
                    .foregroundColor(color.opacity(0.75))
            }
            .foregroundColor(color.opacity(0.9))
            .fixedSize()
            Rectangle().fill(Color.clear).frame(height: 1)
                .overlay(Line().stroke(style: StrokeStyle(lineWidth: 0.8, dash: [2, 4])).foregroundColor(color.opacity(0.45)))
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
    }
    private struct Line: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); return p
        }
    }
}

// 0822 她要的：通道切换分割线（"已切换到 SDK / CLI"），后端 msg_type == "divider"
// 0827 拍一拍那一行。微信是白底浅灰/深灰加粗，我们黑底得把明暗掉个个儿
struct PatLine: View {
    let text: String
    let strong: Bool
    let isDark: Bool
    private var color: Color {
        if isDark { return Color.white.opacity(strong ? 0.74 : 0.34) }
        return Color.black.opacity(strong ? 0.62 : 0.32)
    }
    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: strong ? .semibold : .regular))
            .foregroundColor(color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 34)
            .padding(.vertical, 7)
    }
}

// 任务#1308：一起听切歌的分割线。样子随 DreamDivider 一族：居中、细线、小字
struct MusicChatDivider: View {
    let text: String
    let date: Date
    var color: Color = Color(red: 0.42, green: 0.40, blue: 0.41)
    private struct Line: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); return p
        }
    }
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.clear).frame(height: 1)
                .overlay(Line().stroke(style: StrokeStyle(lineWidth: 0.8, dash: [2, 4])).foregroundColor(color.opacity(0.45)))
            HStack(spacing: 5) {
                Image(systemName: "music.note").font(.system(size: 9.5))
                Text(text).font(.system(size: 11, design: .serif))
                Text(TimeDivider.hmOnly.string(from: date)).font(.system(size: 9.5, design: .rounded))
                    .foregroundColor(color.opacity(0.75))
            }
            .foregroundColor(color.opacity(0.9))
            .fixedSize()
            Rectangle().fill(Color.clear).frame(height: 1)
                .overlay(Line().stroke(style: StrokeStyle(lineWidth: 0.8, dash: [2, 4])).foregroundColor(color.opacity(0.45)))
        }
        .padding(.horizontal, 30).padding(.vertical, 7)
    }
}

struct ChannelDivider: View {
    let text: String
    var color: Color = Color(red: 0.42, green: 0.40, blue: 0.41)
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(color.opacity(0.35)).frame(height: 0.5)
            Text(text).font(.system(size: 11, design: .serif)).foregroundColor(color).fixedSize()
            Rectangle().fill(color.opacity(0.35)).frame(height: 0.5)
        }
        .padding(.horizontal, 28).padding(.vertical, 8)
    }
}

// 0822 iMessage 同款时间分割：日期粗、时刻细，居中小灰字
struct MessagesTimeDivider: View {
    let date: Date
    var color: Color = Color(red: 142/255, green: 142/255, blue: 147/255)
    var body: some View {
        HStack(spacing: 4) {
            Text(Self.dayFmt.string(from: date)).fontWeight(.semibold)
            Text(Self.timeFmt.string(from: date))
        }
        .font(.system(size: 11))
        .foregroundColor(color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
    static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.doesRelativeDateFormatting = true
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
    static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f
    }()
}

struct TimeDivider: View {
    let date: Date
    var color: Color = Color(red: 0.42, green: 0.40, blue: 0.41)
    var body: some View {
        Text(Self.fmt.string(from: date))
            .font(.system(size: 11, design: .serif))
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
    static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()
    static let hmOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f
    }()
}

// 0730 实时预览带：他一说完一段就先给她看，不等整轮跑完。
// 这条是易失的——正式消息一落库它就消失，里面的东西永远不进聊天记录。
struct LiveSayBand: View {
    let state: AlcoveAPI.LiveState
    let theme: AlcoveTheme

    private var tagLine: String {
        var bits: [String] = []
        if !state.tool.isEmpty { bits.append("正在" + state.tool) }
        if state.said > 1 { bits.append("说了\(state.said)段") }
        if state.elapsed > 3 { bits.append("\(state.elapsed)s") }
        return bits.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !state.thinking.isEmpty {
                Text(state.thinking)
                    .font(.system(size: 11))
                    .italic()
                    .foregroundColor(theme.textDim.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !state.say.isEmpty {
                Text(state.say)
                    .font(.system(size: 13))
                    .foregroundColor(theme.textDim.opacity(0.95))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !tagLine.isEmpty {
                Text(tagLine)
                    .font(.system(size: 10))
                    .tracking(0.4)
                    .foregroundColor(theme.textDim.opacity(0.45))
                    .padding(.top, 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.fyCard.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.textDim.opacity(0.22),
                              style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 14, bottomLeadingRadius: 4,
            bottomTrailingRadius: 14, topTrailingRadius: 14,
            style: .continuous
        ))
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }
}

// SDK/CLI 正式流式行：占住最终回复的位置，正文在这里直接长出来；
// finish 后 ChatStore 先拉正式消息，再同一拍撤掉这一行，不做预览卡替换动画。
struct StreamingAssistantRow: View {
    let state: AlcoveAPI.LiveState
    let theme: AlcoveTheme
    let fontSize: Int
    @State private var showThought = false

    private var bodyText: String {
        [state.say, state.pendingSay].filter { !$0.isEmpty }.joined(separator: "")
    }
    private var liveTools: [AlcoveAPI.LiveProcessItem] {
        state.timeline.filter { $0.kind == "tool" }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if !state.thinking.isEmpty {
                    Button { showThought = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                .font(.system(size: 13, weight: .light))
                            Text("Thought process")
                                .font(.system(size: 13, weight: .medium))
                            Image(systemName: "chevron.right").font(.system(size: 8))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Thought process 正在生成")
                }
                if !liveTools.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(liveTools) { tool in
                            HStack(spacing: 6) {
                                Image(systemName: tool.done
                                      ? (tool.ok == false ? "xmark.circle" : "checkmark.circle")
                                      : "gearshape.2")
                                Text(tool.text).lineLimit(1)
                            }
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                if !bodyText.isEmpty {
                    SelectableMessageText(
                        text: bodyText, fontSize: CGFloat(fontSize),
                        lineSpacing: theme.isPaper ? 7 : 5,
                        color: UIColor(theme.text), maximumNumberOfLines: 0,
                        onTruncationChange: { _ in }, onAsk: { _ in }, onCopyTurn: {})
                }
                if state.active && !state.finishing {
                    Capsule().fill(theme.textDim.opacity(0.65))
                        .frame(width: 14, height: 2)
                        .opacity(0.9)
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, theme.isPaper ? 12 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: theme.isPaper ? 15 : 48)
        }
        .padding(.top, 2).padding(.bottom, 5)
        .accessibilityElement(children: .combine)
        .sheet(isPresented: $showThought) {
            NavigationStack {
                ScrollView {
                    Text(state.thinking)
                        .font(.system(size: 15))
                        .lineSpacing(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(22)
                }
                .navigationTitle("Thought process")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { showThought = false }
                }}
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

struct TypingIndicator: View {
    let tool: String?
    var line: String = "思考"
    var name: String = "陈璟"
    var theme: AlcoveTheme = .haven
    @State private var animating = false
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 6, height: 6)
                            .opacity(animating ? 1 : 0.3)
                            .animation(.easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.18), value: animating)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(theme.bubbleAI,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                if !theme.isMessages { Text("\(name)正在\(line)中…")
                    .font(.system(size: 12))
                    .foregroundColor(theme.textDim) }
                Spacer()
            }
            if let tool, !tool.isEmpty, !theme.isMessages {
                // 工具原文她要留着：Bash — 追头像变量aa的赋值来源
                Text(tool)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.textLight)
                    .lineLimit(1)
                    .padding(.leading, 4)
            }
        }
        .onAppear { animating = true }
        .padding(.vertical, 2)
    }
}

/// 0907 她定的：语音滚出屏幕要继续放。
/// 所以播放器不能再住在气泡里 —— 气泡一滚出去就被回收，播放器要么跟着断，
/// 要么变成没人管的幽灵继续响（她当时听到两条叠在一起，就是幽灵干的）。
/// 现在整个 App 只有这一个播放器：谁在响、响到哪儿都记在这儿，
/// 气泡只负责照着它画。同一时间只有一条语音在响。
final class VoicePlayer: ObservableObject {
    static let shared = VoicePlayer()

    @Published private(set) var currentURL: URL?
    @Published private(set) var playing = false
    @Published private(set) var elapsed: Double = 0

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var total: Double = 0

    private init() {}

    func isPlaying(_ url: URL) -> Bool { currentURL == url && playing }

    /// 这条语音放到百分之几了；不是当前这条就是 0
    func progress(_ url: URL, fallbackDuration: Double) -> Double {
        guard currentURL == url else { return 0 }
        let span = total > 0 ? total : fallbackDuration
        guard span > 0 else { return 0 }
        return min(1, max(0, elapsed / span))
    }

    func toggle(_ url: URL) {
        // 正在响的就是这条 → 按停
        if currentURL == url, playing {
            player?.pause()
            playing = false
            return
        }
        // 暂停在这条上 → 原地续上，别从头再来
        if currentURL == url, let p = player {
            activateSession()
            // 看播放器自己的播放头，不看 elapsed（播完那一下 elapsed 被清零了，骗得过这道判断）
            let at = CMTimeGetSeconds(p.currentTime())
            if total > 0, at.isFinite, at >= total - 0.05 { p.seek(to: .zero); elapsed = 0 }
            p.play()
            playing = true
            return
        }
        start(url)
    }

    /// 0912 她要的：拖语音条进度，松手跳到那儿接着放（原来没在放的也直接放）
    func seek(_ url: URL, fraction: Double, fallbackDuration: Double) {
        let span = (currentURL == url && total > 0) ? total : fallbackDuration
        let at = span > 0 ? max(0, min(span - 0.05, fraction * span)) : 0
        if currentURL == url, let p = player {
            activateSession()
            p.seek(to: CMTime(seconds: at, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            elapsed = at
            p.play()
            playing = true
        } else {
            start(url, at: at)
        }
    }

    private func activateSession() {
        // 0822 她说「点语音没有声音」：没开 playback 会话，静音键一拨就哑
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func start(_ url: URL, at: Double = 0) {
        teardown()
        activateSession()
        let p = AVPlayer(url: url)
        player = p
        currentURL = url
        elapsed = 0
        total = 0
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: p.currentItem, queue: .main) { [weak self, weak p] _ in
            // 0912 她抓的：播完再点放不出来、要点两下。原来这里只把 elapsed 清零，播放头还停在末尾，
            // 再点走下面「原地续上」→ 那道判断看的是 elapsed（已经是 0）不拨回开头 → 在末尾 play() 一声不出。
            p?.seek(to: .zero)
            self?.playing = false
            self?.elapsed = 0
        }
        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main) { [weak self] t in
            guard let self else { return }
            if self.total <= 0 {
                let d = CMTimeGetSeconds(p.currentItem?.duration ?? .zero)
                if d.isFinite, d > 0 { self.total = d }
            }
            let secs = CMTimeGetSeconds(t)
            if secs.isFinite { self.elapsed = secs }
        }
        if at > 0 {
            p.seek(to: CMTime(seconds: at, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            elapsed = at
        }
        p.play()
        playing = true
    }

    /// 换一条语音之前，把上一条的播放器和两个监听收干净
    private func teardown() {
        player?.pause()
        if let old = endObserver { NotificationCenter.default.removeObserver(old) }
        endObserver = nil
        if let t = timeObserver { player?.removeTimeObserver(t) }
        timeObserver = nil
        player = nil
        playing = false
        elapsed = 0
        total = 0
    }
}

// 语音条：点击播放/暂停
/// 语音条（0902 她给的参考图重画）：一条气泡里是「播放键 · 波纹 · 时长 · 小箭头」，
/// 点右边的小箭头，转文字在**同一条气泡里**往下展开，不再另起一个文字气泡。
/// 波纹条数跟时长走（越长越长），高低按链接算出来、每次一样；播放时从左到右点亮。
struct AudioBubble: View {
    let url: URL
    let isUser: Bool
    var theme: AlcoveTheme = .haven
    // 0907 她要的：转文字跟正文一样大。原来写死 15.5，比正文气泡大一号
    var fontSize: CGFloat = 14
    var hasTranscript: Bool = false
    var transcript: String = ""
    var transcriptShown: Bool = false
    var onToggleTranscript: (() -> Void)? = nil
    var onFavorite: (() -> Void)? = nil
    /// 0912 她要的：他自己写的中文翻译。展开转文字后，箭头左边一个「译」；
    /// 点了在转文字下面再分一条线，小一号、淡一点显示；不点不显示
    var translation: String = ""
    /// 译文展开 / 收起会改气泡高度，告诉外面重新贴底
    var onContentChange: (() -> Void)? = nil

    // 0907：播放器搬去 VoicePlayer 了，气泡只照着它画。
    // duration 留在这儿——它只用来决定画几根波纹，跟谁在响没关系。
    @ObservedObject private var voice = VoicePlayer.shared
    @State private var duration: Double = 0
    @State private var translationShown = false
    /// 0912 拖进度：手指拖到的位置（0~1），没在拖是 nil；这一下拖是不是横着的（竖着的留给聊天滚动）
    @State private var scrubFraction: Double?
    @State private var dragIsScrub: Bool?

    private var playing: Bool { voice.isPlaying(url) }
    private var progress: Double { voice.progress(url, fallbackDuration: duration) }
    /// 拖的时候波纹跟着手指亮，松手再回到播放器的真实进度
    private var shownProgress: Double { scrubFraction ?? progress }

    private var ink: Color { (theme.isMessages && isUser) ? .white : theme.text }

    /// 10 条起步，每秒多一条，封顶 30——一条 4.5pt，最长约 135pt 的波纹，气泡不会撑爆
    /// 0912 她要能拖进度，短语音太窄对不准：起步 10 → 13 条（她说只加宽一点点）
    private var barCount: Int { max(13, min(30, Int(10 + duration * 1.0))) }
    /// 波纹实际宽度（每条 2.5 ＋ 间隔 2），拖的时候拿手指位置除以它算百分比
    private var waveWidth: CGFloat { CGFloat(barCount) * 2.5 + CGFloat(barCount - 1) * 2 }

    /// 波纹高低：按链接算一串固定的伪随机数，同一条语音每次画出来一样，不会一刷新就跳
    private var bars: [CGFloat] {
        var seed: UInt32 = 2166136261
        for b in url.absoluteString.utf8 { seed = (seed ^ UInt32(b)) &* 16777619 }
        var out: [CGFloat] = []
        for _ in 0..<40 {
            seed = seed &* 1664525 &+ 1013904223
            let v = CGFloat((seed >> 16) & 0xFF) / 255
            out.append(5 + v * 15)
        }
        return out
    }

    private var timeText: String {
        // 拖的时候显示拖到哪一秒
        if let f = scrubFraction, duration > 0 {
            let at = Int((f * duration).rounded())
            return String(format: "%d:%02d", at / 60, at % 60)
        }
        let secs = Int(duration.rounded())
        return duration > 0 ? String(format: "%d:%02d", secs / 60, secs % 60) : "语音"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button(action: togglePlay) {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 13))
                        .frame(width: 18, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                waveform
                    .contentShape(Rectangle())
                    .onTapGesture { togglePlay() }
                    .simultaneousGesture(scrubGesture)
                Text(timeText)
                    .font(.system(size: 13, design: .monospaced))
                    .opacity(0.85)
                if hasTranscript {
                    // 0907 她要的：展开以后箭头跟着气泡最右边走。
                    // 只在展开时撑开——没展开时加 Spacer 会把语音条拉成整行宽
                    if transcriptShown { Spacer(minLength: 8) }
                    // 0912 她圈的位置：展开后箭头左边一点点。他写了中文翻译才有这个「译」
                    if transcriptShown && !translation.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { translationShown.toggle() }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onContentChange?() }
                        } label: {
                            Text("译")
                                .font(.system(size: 12, weight: translationShown ? .bold : .semibold))
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .opacity(translationShown ? 1 : 0.7)
                    }
                    Button { onToggleTranscript?() } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .rotationEffect(.degrees(transcriptShown ? 180 : 0))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(0.8)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            if hasTranscript && transcriptShown {
                Rectangle()
                    .fill(ink.opacity(0.16))
                    .frame(height: 1)
                    .padding(.horizontal, 12)
                Text(transcript)
                    .font(.system(size: fontSize))
                    .lineSpacing(theme.isPaper ? 7 : 5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .fixedSize(horizontal: false, vertical: true)
                // 0912：点了「译」才有——再分一条线，他自己写的中文，小一号、淡一点
                if translationShown && !translation.isEmpty {
                    Rectangle()
                        .fill(ink.opacity(0.12))
                        .frame(height: 1)
                        .padding(.horizontal, 12)
                    Text(translation)
                        .font(.system(size: max(11, fontSize - 2.5)))
                        .lineSpacing(theme.isPaper ? 6 : 4)
                        .opacity(0.62)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .foregroundColor(ink)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isUser ? theme.bubbleUser : theme.bubbleAI)
        }
        .animation(.easeInOut(duration: 0.18), value: transcriptShown)
        .contextMenu {
            if let onFavorite {
                Button { onFavorite() } label: { Label("收藏", systemImage: "heart") }
            }
        }
        .task(id: url) { await loadDuration() }
    }

    private var waveform: some View {
        let heights = bars
        return HStack(alignment: .center, spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                let lit = Double(i) / Double(barCount) < shownProgress
                Capsule()
                    .fill(ink.opacity(lit ? 0.95 : 0.42))
                    .frame(width: 2.5, height: heights[i % heights.count])
            }
        }
        .frame(height: 22)
    }

    /// 0912 她要的：按住波纹横着拖＝拖进度，松手从那儿接着放。
    /// 第一下动的方向定终身：竖着的整下都不管（留给聊天滚动）；点一下还是播放/暂停（上面的 onTapGesture）
    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if dragIsScrub == nil {
                    dragIsScrub = abs(value.translation.width) > abs(value.translation.height)
                }
                guard dragIsScrub == true else { return }
                scrubFraction = min(1, max(0, Double(value.location.x / waveWidth)))
            }
            .onEnded { _ in
                let f = scrubFraction
                scrubFraction = nil
                dragIsScrub = nil
                if let f { voice.seek(url, fraction: f, fallbackDuration: duration) }
            }
    }

    private func loadDuration() async {
        let asset = AVURLAsset(url: url)
        if let d = try? await asset.load(.duration) {
            let secs = CMTimeGetSeconds(d)
            if secs.isFinite && secs > 0 { duration = secs }
        }
    }

    private func togglePlay() { voice.toggle(url) }
}

struct PhotoViewerSelection: Identifiable {
    let id = UUID()
    let urls: [URL]
    let index: Binding<Int>
    let sourceID: String
}

// 主聊天双方共用：少图横排；多图横滑，左侧可展开为两列全览。圆桌仍保留叠牌。
struct OfficialPhotoGridMessageView: View {
    let urls: [URL]
    let messageID: String
    let onOpen: ([URL], Binding<Int>) -> Void

    @State private var currentIndex = 0
    @State private var isExpanded = false
    private let side: CGFloat = 124
    private let gap: CGFloat = 8

    var body: some View {
        HStack(alignment: .top, spacing: gap) {
            if urls.count > 2 {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        isExpanded.toggle()
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        Text(isExpanded ? "收起" : "展开")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.secondary)
                    .frame(width: 44, height: 44)
                    .background(Color(uiColor: .systemGray5).opacity(0.78), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "收起全部照片" : "展开全部照片")
            }
            if isExpanded {
                grid
            } else {
                strip
            }
        }
        .id(messageID)
    }

    private var strip: some View {
        Group {
            if urls.count > 2 {
                ScrollView(.horizontal, showsIndicators: false) { lazyPhotoRow }
                    .frame(width: side * 2 + gap)
            } else {
                HStack(spacing: gap) { photos }
            }
        }
    }

    private var lazyPhotoRow: some View {
        LazyHStack(spacing: gap) {
            photos
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.fixed(side), spacing: gap),
                            GridItem(.fixed(side), spacing: gap)],
                  alignment: .leading, spacing: gap) {
            photos
        }
        .frame(width: side * 2 + gap, alignment: .leading)
    }

    @ViewBuilder private var photos: some View {
        ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
            photo(url)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onTapGesture { open(at: index) }
                .accessibilityLabel("照片 \(index + 1)，共 \(urls.count) 张")
                .accessibilityAddTraits(.isButton)
        }
    }

    private func open(at index: Int) {
        currentIndex = min(max(index, 0), urls.count - 1)
        onOpen(urls, Binding(
            get: { currentIndex },
            set: { currentIndex = min(max($0, 0), urls.count - 1) }
        ))
    }

    private func photo(_ url: URL) -> some View {
        let previewURL: URL = {
            guard let range = url.path.range(of: "/attachments/") else { return url }
            return AlcoveAPI.attachmentThumbnailURL(
                "/attachments/" + String(url.path[range.upperBound...]))
        }()
        return CachedPhaseImage(url: previewURL) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            case .failure: Color(.tertiarySystemFill).overlay(Image(systemName: "photo"))
            default: Color(.tertiarySystemFill).overlay(ProgressView())
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu {
            Button {
                Task { await PhotoLibrarySaver.save(url) }
            } label: { Label("保存到相册", systemImage: "square.and.arrow.down") }
        }
    }
}

// 一条消息只保留三张可见卡。翻牌只改轻量几何状态，AsyncImage 的 URL 身份不变，
// 所以拖动和换位期间不会重新解码或把卡片尺寸撑开。
struct PhotoStackMessageView: View {
    let urls: [URL]
    let messageID: String
    let onOpen: ([URL], Binding<Int>) -> Void

    private let cardSize = CGSize(width: 143, height: 179)
    @State private var currentIndex = 0
    @State private var dragX: CGFloat = 0
    @State private var isHorizontalDrag = false
    @State private var isAnimatingOut = false
    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                    isExpanded.toggle()
                    if !isExpanded { currentIndex = 0 }
                }
            } label: {
                Text(isExpanded ? "收起" : "展开 \(urls.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(uiColor: .darkGray))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color(uiColor: .systemGray5).opacity(0.82), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, (cardSize.height - 28) / 2)

            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        photoCard(url: url)
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .onTapGesture { openPhoto(at: index) }
                            .transition(.offset(y: -CGFloat(index) * (cardSize.height * 0.72))
                                .combined(with: .opacity))
                    }
                }
            } else {
                collapsedStack
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .id(messageID)
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: isExpanded)
        .onChange(of: urls) { _ in
            if currentIndex >= urls.count { currentIndex = 0 }
        }
    }

    private var collapsedStack: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                ForEach(Array(visibleSlots.reversed()), id: \.self) { slot in
                    photoCard(url: url(at: slot))
                        .offset(layerOffset(slot))
                        .rotationEffect(.degrees(layerRotation(slot)))
                        .scaleEffect(layerScale(slot))
                        .zIndex(Double(3 - slot))
                        .allowsHitTesting(slot == 0)
                        .offset(x: slot == 0 ? dragX : 0)
                        .rotationEffect(.degrees(slot == 0
                            ? Double(dragX / cardSize.width) * 4 : 0))
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onTapGesture {
                            guard !isHorizontalDrag && !isAnimatingOut else { return }
                            openPhoto(at: currentIndex)
                        }
                        .simultaneousGesture(dragGesture)
                }
            }
            if urls.count > 3 { countBadge }
        }
        .frame(width: cardSize.width + 14, height: cardSize.height + 13)
    }

    private var countBadge: some View {
        Text("\(urls.count)")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary.opacity(0.82))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 0.5))
            .padding(.top, 9)
            .padding(.trailing, 8)
            .zIndex(10)
            .allowsHitTesting(false)
    }

    private func openPhoto(at index: Int) {
        currentIndex = min(max(index, 0), urls.count - 1)
        onOpen(urls, Binding(
            get: { currentIndex },
            set: { currentIndex = min(max($0, 0), urls.count - 1) }
        ))
    }

    private var visibleSlots: Range<Int> { 0..<min(3, urls.count) }

    private func url(at slot: Int) -> URL {
        urls[(currentIndex + slot) % urls.count]
    }

    private func photoCard(url: URL) -> some View {
        let previewURL: URL = {
            let path = url.path
            guard let range = path.range(of: "/attachments/") else { return url }
            return AlcoveAPI.attachmentThumbnailURL("/attachments/" + String(path[range.upperBound...]))
        }()
        return CachedPhaseImage(url: previewURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                Color(.tertiarySystemFill).overlay(Image(systemName: "photo"))
            default:
                Color(.tertiarySystemFill).overlay(ProgressView())
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu {
            Button {
                Task { await PhotoLibrarySaver.save(url) }
            } label: { Label("保存到相册", systemImage: "square.and.arrow.down") }
        }
    }

    private func layerOffset(_ slot: Int) -> CGSize {
        let progress = min(abs(dragX) / (cardSize.width * 0.75), 1)
        switch slot {
        case 1: return CGSize(width: 7 * (1 - progress), height: -7 * (1 - progress))
        case 2: return CGSize(width: -5 + 12 * progress, height: -5 - 2 * progress)
        default: return .zero
        }
    }

    private func layerRotation(_ slot: Int) -> Double {
        let progress = min(abs(dragX) / (cardSize.width * 0.75), 1)
        if slot == 1 { return 1.5 * Double(1 - progress) }
        if slot == 2 { return -1 + 2.5 * Double(progress) }
        return 0
    }

    private func layerScale(_ slot: Int) -> CGFloat {
        guard slot > 0 else { return 1 }
        let progress = min(abs(dragX) / (cardSize.width * 0.75), 1)
        return 0.995 + (slot == 1 ? 0.005 * progress : 0)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard !isAnimatingOut else { return }
                let horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.15
                if !isHorizontalDrag && !horizontal { return }
                isHorizontalDrag = true
                dragX = value.translation.width
            }
            .onEnded { value in
                guard isHorizontalDrag else { return }
                let projected = value.predictedEndTranslation.width
                let shouldAdvance = abs(dragX) > cardSize.width * 0.25 || abs(projected) > cardSize.width * 0.48
                if shouldAdvance {
                    isAnimatingOut = true
                    let direction: CGFloat = (dragX == 0 ? projected : dragX) >= 0 ? 1 : -1
                    withAnimation(.easeOut(duration: 0.20)) {
                        dragX = direction * (cardSize.width + 80)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            currentIndex = (currentIndex + 1) % urls.count
                            dragX = 0
                            isAnimatingOut = false
                            isHorizontalDrag = false
                        }
                    }
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { dragX = 0 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { isHorizontalDrag = false }
                }
            }
    }
}

enum PhotoLibrarySaver {
    static func save(_ url: URL) async {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let image = UIImage(data: data) else { return }
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else { return }
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        } catch {
            // Context-menu saving is intentionally non-blocking; a failed
            // network fetch leaves the existing image bubble untouched.
        }
    }
}

struct PhotoPageViewer: View {
    let selection: PhotoViewerSelection
    let namespace: Namespace.ID
    let dismiss: () -> Void
    // 0821 她报的：左右滑总弹回第一张。以前直接绑着聊天列表里那条图片消息的状态，
    // 列表每两秒刷一次、那条消息一重画，数就归零，大图页跟着弹回去。
    // 现在大图页自己记翻到第几张，关掉时再写回去给小图那边同步。
    @State private var index: Int

    init(selection: PhotoViewerSelection, namespace: Namespace.ID, dismiss: @escaping () -> Void) {
        self.selection = selection
        self.namespace = namespace
        self.dismiss = dismiss
        _index = State(initialValue: selection.index.wrappedValue)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(selection.urls.enumerated()), id: \.offset) { offset, url in
                    ZoomableRemoteImage(url: url).tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: selection.urls.count > 1 ? .automatic : .never))
        }
        .overlay(alignment: .topTrailing) {
            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30)).foregroundColor(.white.opacity(0.8)).padding()
            }
        }
        .onChange(of: index) { value in selection.index.wrappedValue = value }
        .navigationTransition(.zoom(sourceID: selection.sourceID, in: namespace))
    }
}

private struct ZoomableRemoteImage: View {
    let url: URL
    @State private var scale: CGFloat = 1
    var body: some View {
        CachedImage(url: url) { image in
            image.resizable().scaledToFit()
                .scaleEffect(scale)
                .gesture(MagnificationGesture()
                    .onChanged { scale = max(1, $0) }
                    .onEnded { _ in withAnimation { scale = 1 } })
        } placeholder: { ProgressView().tint(.white) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu {
            Button {
                Task { await PhotoLibrarySaver.save(url) }
            } label: { Label("保存到相册", systemImage: "square.and.arrow.down") }
        }
    }
}

struct ImageViewer: View {
    let url: URL
    var dismiss: () -> Void
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CachedImage(url: url) { img in
                img.resizable().scaledToFit()
                    .scaleEffect(scale)
                    .gesture(MagnificationGesture()
                        .onChanged { scale = max(1, $0) }
                        .onEnded { _ in withAnimation { scale = 1 } })
            } placeholder: { ProgressView().tint(.white) }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // 居中铺满
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white.opacity(0.8))
                    .padding()
            }
        }
        .onTapGesture { dismiss() }
    }
}

// 记忆召回弹层：✦记起 点开看召回的记忆卡片
struct RecallPop: View {
    let item: RecallItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(item.cards.enumerated()), id: \.offset) { _, card in
                        VStack(alignment: .leading, spacing: 6) {
                            if !card.date.isEmpty {
                                Text(card.date)
                                    .font(.system(size: 11, design: .serif))
                                    .foregroundColor(.secondary)
                            }
                            Text(card.body)
                                .font(.system(size: 13))
                                .foregroundColor(.primary.opacity(0.85))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(14)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("✦ 那一刻我想起的")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// 别的主题照旧罩渐变遮罩；信息主题不罩（遮罩会把系统的 scroll edge effect 一起蒙掉）
private struct EdgeFadeMaskModifier<M: View>: ViewModifier {
    let enabled: Bool
    let mask: M
    // 0914 她报「顶栏和底部都坏了」：371de38 为了保住滚动位置改成任何主题都罩一层遮罩
    // （信息主题罩纯白＝等于没裁）。但只要罩了遮罩，内容就被丢进离屏图层，
    // iOS 26 的 scroll edge effect 和顶栏的毛玻璃材质一起失效——上面那行注释
    //「信息主题不罩遮罩，别挡系统效果」就是为这个写的。改回按主题罩；
    // 滚动位置改在 messageList 里用锚点补。
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.mask(mask) } else { content }
    }
}

// 0822 她要的打字框材质：iOS 26 真玻璃（圆加号 + 胶囊），老系统退回白片 + 细线 + 软阴影
private struct MessagesGlassModifier: ViewModifier {
    let face: Color
    let line: Color
    let shadow: Color
    let circle: Bool
    var enabled: Bool = true
    @ViewBuilder func body(content: Content) -> some View {
        if !enabled {
            content
        } else if #available(iOS 26.0, *) {
            if circle {
                // 0823 她拍板：两个小圆（加号、录音取消）换成不跟手的玻璃省电，
                // 它们太小，跟手那点活气本来就看不见。中间那个输入胶囊留着跟手，
                // 她天天在那儿打字，手感不动。
                content.glassEffect(.regular, in: Circle())
            } else {
                content.glassEffect(.regular.interactive(), in: Capsule())
            }
        } else {
            if circle {
                content.background(face, in: Circle())
                    .overlay(Circle().stroke(line, lineWidth: 0.5))
                    .shadow(color: shadow, radius: 6, y: 2)
            } else {
                content.background(face, in: Capsule())
                    .overlay(Capsule().stroke(line, lineWidth: 0.5))
                    .shadow(color: shadow, radius: 8, y: 2)
            }
        }
    }
}

private struct InteractiveInputGlassModifier: ViewModifier {
    let fallbackTint: Color
    var enabled: Bool = true

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        if !enabled {
            content
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: shape)
        } else {
            content
                .background(fallbackTint, in: shape)
        }
    }
}

private struct InputBarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r: CGFloat = 20
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                 tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r), radius: r)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                 tangent2End: CGPoint(x: rect.minX + r, y: rect.minY), radius: r)
        p.closeSubpath()
        return p
    }
}

// 0731 去掉 private：圆桌那个悬浮输入框也要用它量高度，
// private 挡住了跨文件访问，b1fe6df 就是编译在这儿炸的。
struct InputBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 90
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// 0909：打字框底边在屏幕坐标里的位置。「点最底回到最新」那条窄条靠它
/// 算出自己最多能有多高 —— 只吃打字框下面那点空隙，一个像素都不许压上去。
/// 默认给 .infinity：还没量到之前当作打字框贴着屏幕底，窄条先不出现，
/// 宁可少一个手势，也不能抢走打字框。
struct InputBarBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

extension URL: Identifiable {
    public var id: String { absoluteString }
}

extension UIImage: @retroactive Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

struct LocalImageViewer: View {
    let image: UIImage
    var dismiss: () -> Void
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(MagnificationGesture()
                    .onChanged { scale = max(1, $0) }
                    .onEnded { _ in withAnimation { scale = 1 } })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white.opacity(0.8))
                    .padding()
            }
        }
        .onTapGesture { dismiss() }
    }
}

struct CameraView: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        init(_ parent: CameraView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: ([URL]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item])
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ parent: DocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls)
            parent.dismiss()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}

struct PhotoLibraryPicker: UIViewControllerRepresentable {
    var maxCount: Int = 9
    var onPick: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = maxCount
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPicker
        init(_ parent: PhotoLibraryPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard !results.isEmpty else { return }
            var images: [UIImage] = []
            let group = DispatchGroup()
            for result in results {
                guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else { continue }
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                    if let img = obj as? UIImage { images.append(img) }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                self.parent.onPick(images)
            }
        }
    }
}

// MARK: 上传前的图片处理

/// 0813 查卡顿查出来的病根：三个入口都只调 jpegData(compressionQuality:)，
/// 只压质量不降分辨率。iPhone 直出 4032×3024，一张 2-4MB 原样上行，
/// 相册一次还能选九张。库里 1875 张图有 172 张超过 2MB。
/// 长边压到 2048 之后约掉到十分之一，她屏幕上看不出差别。
/// 缩完的图同时当预览条的缩略图用，省得全尺寸 UIImage 堆在内存里。
enum UploadImage {
    static let maxEdge: CGFloat = 2048
    static let quality: CGFloat = 0.8

    /// 0828 透明底修复：JPEG 装不下透明通道，以前一律 jpegData + opaque 垫白底，
    /// 抠图素材发出去全成白底图。真带透明的图改走 PNG，照片截图照旧 JPEG 省流量。
    static func prepare(_ image: UIImage) -> (thumb: UIImage, data: Data, ext: String)? {
        let transparent = hasTransparency(image)
        let scaled = downscaled(image, opaque: !transparent)
        if transparent {
            guard let data = scaled.pngData() else { return nil }
            return (scaled, data, "png")
        }
        guard let data = scaled.jpegData(compressionQuality: quality) else { return nil }
        return (scaled, data, "jpg")
    }

    /// 光看 alphaInfo 会把不透明的 PNG 截图也当成透明（解码后常带 alpha 通道），
    /// 那样截图全走 PNG 又回到 0813 上行过大的老坑。缩到 64×64 实际扫一遍 alpha：
    /// 抠图必有大片透明，照片截图满格不透明，几毫秒的事。
    static func hasTransparency(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        switch cg.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly: break
        default: return false
        }
        let side = 64
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &pixels, width: side, height: side,
                                  bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return true }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        var i = 3
        while i < pixels.count {
            if pixels[i] < 250 { return true }
            i += 4
        }
        return false
    }

    static func downscaled(_ image: UIImage, opaque: Bool = true) -> UIImage {
        // size 是点数，乘 scale 才是真实像素——相机和相册来的图 scale 不一定是 1
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        guard longest > maxEdge, longest > 0 else { return image }
        let ratio = maxEdge / longest
        let target = CGSize(width: (pixelWidth * ratio).rounded(),
                            height: (pixelHeight * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        // target 已经是像素目标，再乘屏幕倍率会画出三倍大的图
        format.scale = 1
        format.opaque = opaque
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

private struct FavoriteForwardMessageCard: View {
    let card: FavoriteForwardPayload
    @State private var opened = false
    @AppStorage("alcoveTheme") private var themeName = "haven"
    var body: some View {
        Button { opened = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label(card.label, systemImage: "bookmark")
                    .font(.system(size: 13, weight: .medium))
                Text(card.preview).font(.system(size: 14)).lineLimit(3)
                Text("来自收藏 · 点开查看").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(12).frame(maxWidth: 260, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $opened) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(card.items.enumerated()), id: \.offset) { _, item in
                            if !item.title.isEmpty { Text(item.title).font(.headline) }
                            ForEach(Array(item.members.enumerated()), id: \.offset) { _, member in
                                FavoriteForwardMemberView(member: member, themeName: themeName)
                            }
                            Divider()
                        }
                    }.padding()
                }
                .navigationTitle(card.label)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { opened = false } } }
            }
        }
    }
}

private struct FavoriteForwardMemberView: View {
    let member: FavoriteForwardPayload.Member
    let themeName: String
    @State private var transcriptShown = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((member.role == "user" ? "陈霁" : "陈璟") + " · " + member.ts)
                .font(.caption).foregroundStyle(.secondary)
            if let url = member.attachment_url, !url.isEmpty {
                if member.attachment_type == "audio" {
                    AudioBubble(url: AlcoveAPI.attachmentURL(url), isUser: member.role == "user",
                        theme: .named(themeName), fontSize: 14,
                        hasTranscript: !member.text.isEmpty, transcript: member.text,
                        transcriptShown: transcriptShown, onToggleTranscript: { transcriptShown.toggle() },
                        translation: member.audio_zh ?? "")
                } else if member.attachment_type == "image" {
                    AsyncImage(url: AlcoveAPI.attachmentURL(url)) { image in
                        image.resizable().scaledToFit()
                    } placeholder: { Image(systemName: "photo") }
                    .frame(maxHeight: 300)
                } else {
                    Link("打开附件", destination: AlcoveAPI.attachmentURL(url))
                }
            }
            if member.attachment_type != "audio" && !member.text.isEmpty {
                Text(alcoveMarkdown(member.text)).textSelection(.enabled)
            }
        }
    }
}


// Native summaries are a separate source, never synthesized from handwritten thoughts.
private struct NativeThinkingButton: View {
    let text: String
    let color: Color
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: {
            Image(systemName: "brain")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看原生 Thinking")
        .sheet(isPresented: $presented) {
            if #available(iOS 18.0, *) {
                NativeThinkingSheet(text: text)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(32)
            } else {
                ScrollView { Text(text).padding().textSelection(.enabled) }
            }
        }
    }
}

@available(iOS 18.0, *)
private struct NativeThinkingSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    @State private var configuration: TranslationSession.Configuration?
    @State private var translated: String?
    @State private var showTranslation = false
    @State private var translating = false
    @State private var errorText: String?
    @State private var translationSource = "AI 润色翻译"
    @State private var aiTask: Task<Void, Never>?

    private func translateAI() {
        translating = true
        errorText = nil
        aiTask = Task { @MainActor in
            do {
                let result = try await AlcoveAPI.postRaw("/api/thinking/translate", body: ["text": text])
                try Task.checkCancellation()
                guard result["ok"] as? Bool == true,
                      let output = result["text"] as? String, !output.isEmpty else {
                    throw URLError(.badServerResponse)
                }
                translated = output
                translationSource = "AI 润色翻译"
                showTranslation = true
            } catch {
                if !Task.isCancelled { errorText = "AI翻译未完成，可重试或改用iOS翻译。" }
            }
            translating = false
        }
    }

    private func translateIOS() {
        translating = true
        errorText = nil
        if configuration == nil {
            configuration = .init(source: .init(identifier: "en"), target: .init(identifier: "zh-Hans"))
        } else { configuration?.invalidate() }
    }


    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 19, weight: .light))
                        .frame(width: 44, height: 44)
                        .background(Color(uiColor: .secondarySystemBackground), in: Circle())
                }.accessibilityLabel("关闭")
                Spacer()
                Text("Thought process").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button {
                    if translated != nil {
                        showTranslation.toggle()
                    } else {
                        translateAI()
                    }
                } label: {
                    Group {
                        if translating { ProgressView() }
                        else { Text(showTranslation ? "原文" : "译") }
                    }.frame(width: 44, height: 44)
                }
                .contextMenu {
                    Button("AI 润色翻译") { translateAI() }.disabled(translating)
                    Button("iOS 翻译") { translateIOS() }.disabled(translating)
                }
                .disabled(translating)
                .accessibilityLabel(showTranslation ? "显示原文" : "翻译成中文")
            }
            .padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 12)
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.secondary)
                    .padding(.horizontal, 22).padding(.bottom, 8)
                HStack {
                    Button("重试 AI 翻译") { translateAI() }
                    Button("改用 iOS 翻译") { translateIOS() }
                }.font(.footnote).disabled(translating).padding(.bottom, 8)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if showTranslation {
                        Text("中文译文 · \(translationSource)").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(showTranslation ? (translated ?? text) : text)
                        .font(.system(size: 16)).lineSpacing(8)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.horizontal, 22).padding(.bottom, 28)
            }
        }
        .foregroundStyle(Color.primary)
        .background(Color(uiColor: .systemBackground))
        .tint(.primary)
        .onDisappear { aiTask?.cancel() }
        .translationTask(configuration) { session in
            do {
                // Translate each paragraph separately so the source's blank lines survive.
                let paragraphs = text.components(separatedBy: "\n\n")
                var output: [String] = []
                for paragraph in paragraphs {
                    try Task.checkCancellation()
                    if paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        output.append(paragraph)
                    } else {
                        let response = try await session.translate(paragraph)
                        output.append(response.targetText)
                    }
                }
                translationSource = "iOS 翻译"
                translated = output.joined(separator: "\n\n")
                showTranslation = true
                translating = false
            } catch {
                translating = false
                errorText = "翻译未完成，原文已保留。点右上角「译」重试。"
            }
        }
    }
}
