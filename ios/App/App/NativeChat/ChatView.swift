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
    @ObservedObject private var wallpaperStore = ChatWallpaperStore.shared
    @ObservedObject private var kakaoPacks = KakaoPackStore.shared   // 0924 Kakao 主题包换了/图到了就重画
    @State private var draft = ""
    @State private var previousDraft = ""
    // 0921 任务#2505 文字效果：长按菜单点「文字效果」时记下选中的范围，面板选完套标记
    @State private var effectRange: NSRange?
    @State private var showEffectPanel = false
    @State private var handlingReturn = false
    @State private var selectedQuote: String?
    /// 1001 贴表情：正被长按的那条（整屏那层盖在上面）；点了「选择文字」的那条（只有它能逐字选）
    @State private var reactTarget: ReactTarget?
    @State private var selectingTs: String?
    // 0925「编辑」：正在编辑哪条（她那条的 ts）和输入框里的字
    @State private var editingTs: String?
    @State private var rerollConfirmShown = false   // 0928 她要的：点重来先问一句是否（误触过一次，见下面 alert）
    @State private var editDraft = ""
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
    // 0924 她要的：「回到最新」那颗药丸别一动就冒出来。atBottom（离底 120pt）继续管跟不跟流式输出，
    // 药丸另看这个：往上翻超过 tailPillRevealScreens 屏才出现。想改灵敏度只动这个数。
    @State private var farFromTail = false
    private let tailPillRevealScreens: CGFloat = 1.0
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
    @State private var showLocationPicker = false   // 1008 加号里的「位置」
    @State private var showPhotoPicker = false
    @Namespace private var photoTransition
    @State private var previewImage: UIImage?
    @State private var inputBarHeight: CGFloat = 90
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
    @State private var showRoomPicker = false        // 0919 左上角的门：挑房间
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
    @AppStorage("chatTurnGap") private var chatTurnGap = 22.0   // 0929 她要的：他连着两轮之间的空，设置里「轮与轮间距」
    // 1009 晚 她要的（只给树屋）：他一轮话是拆成好几个气泡，还是并成一整个。她的气泡一概不动。
    @AppStorage(TreehouseBubbleMode.key) private var treehouseWholeBubble = false
    @AppStorage(KakaoPackStore.showAvatarKey) private var listKakaoShowAvatar = true   // 0924 晚：换人那截空隙要知道他那边气泡是不是挪过
    @AppStorage("wallStamp") private var wallStamp = 0.0
    /// 0902 信息主题调色板：她在设置页改一项，msgPaletteStamp 一变这里就重算
    @AppStorage(MessagesPalette.stampKey) private var paletteStamp = 0.0
    private var theme: AlcoveTheme { _ = paletteStamp; return .named(themeName) }
    /// 0925：弹出的面板用这套——Kakao 下跟全屋白天 / 黑夜开关走（聊天主题恒白天），别的主题就是聊天主题本身
    private var sheetTheme: AlcoveTheme { theme.isKakao ? .kakaoSheet(dark: AlcoveAppearance.isDark) : theme }
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

                // 1001：长按贴表情那层挪进来，跟气泡同一套环境（玻璃气泡的折射要认 alcoveChatRoot），浮起来那份才画得一样
                reactOverlay
            }
            .coordinateSpace(name: "alcoveChatRoot")
            .environment(\.chatWallpaperDescriptor, wallpaperStore.descriptor)
            .environment(\.chatWallpaperViewportSize, root.size)
        }
        .sheet(isPresented: $showStickers) { stickerSheet.modifier(HouseColorScheme()) }
        .sheet(isPresented: $showEffectPanel) {
            TextEffectPanel(selection: effectSelectionText, onPick: applyTextEffect)
                .modifier(HouseColorScheme())
                .presentationDetents([.fraction(0.55)])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.ultraThinMaterial)
        }
        .onReceive(NotificationCenter.default.publisher(for: TextEffectBridge.requested)) { note in
            // 只认聊天打字框：菜单回来的整段文本必须就是眼前的草稿
            guard let text = note.userInfo?["text"] as? String, text == draft,
                  let loc = note.userInfo?["location"] as? Int,
                  let len = note.userInfo?["length"] as? Int else { return }
            effectRange = NSRange(location: loc, length: len)
            showEffectPanel = true
        }
        .onChange(of: inputFocused) { focused in TextEffectBridge.chatInputFocused = focused }
        .sheet(isPresented: $showMusicPlayer) {
            MusicPlayerSheet(model: music)
                .modifier(HouseColorScheme())
                .presentationDetents([.fraction(0.72)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showModelPicker, onDismiss: { showMoreModels = false }) {
            modelPickerSheet
                .modifier(HouseColorScheme())
                .task { await loadModelPanelState() }
                .presentationDetents([.fraction(0.72), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showSDKShadow) {
            SDKShadowChatView().modifier(HouseColorScheme())
        }
        .sheet(isPresented: $showChannelPanel) {
            ChatChannelPanel(activeChannel: $activeChatChannel)
                .modifier(HouseColorScheme())
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        // 0919 她要的三个房间：门打开挑一间。cli / sdk 就是拨开关（同时换房间），api 只换房间先看着
        .sheet(isPresented: $showRoomPicker) {
            ChatRoomPicker(activeChannel: $activeChatChannel, currentRoom: store.room,
                           onPickRoom: { store.switchRoom($0) },
                           onOpenChannelPanel: { showRoomPicker = false; showChannelPanel = true })
                .modifier(HouseColorScheme())
                .presentationDetents([.height(320), .medium])
                .presentationDragIndicator(.visible)
        }
        .onReceive(NotificationCenter.default.publisher(for: .alcoveOpenRoomPicker)) { _ in
            showRoomPicker = true
        }
        // 房间跟着开关走：开关拨到哪边，看的就是哪间（api 是只看不拨，留在原地）
        .onChange(of: activeChatChannel) { ch in
            if store.room != "api" && store.room != ch { store.switchRoom(ch) }
        }
        .sheet(isPresented: $showCamera) {
            CameraView { image in
                if let prepared = UploadImage.prepare(image) {
                    pendingImages.append(prepared)
                }
            }
        }
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerSheet { text in store.sendText(text) }
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
            if theme.isKakao || !KakaoPackStore.shared.selectedFontID.isEmpty { KakaoPackStore.shared.refresh() }   // 0924 开门就把主题包 / 字体名单拉一遍
            music.startRemotePolling()
            Task {
                if let obj = try? await AlcoveAPI.getRaw("/api/sdk-shadow/status") {
                    let ch = obj["channel"] as? String ?? "cli"
                    activeChatChannel = ch
                    if store.room != "api" && store.room != ch { store.switchRoom(ch) }
                }
            }
        }
        // 1009 树屋顶栏要他的模型名：顶栏在 RootView 拿不到 store，这里递过去。
        // 心率不走这儿了——她 1009 晚要求顶栏那颗跟「脉」面板对齐、一直跳，
        // 改由 TreehouseHeaderModel 自己每 10 秒问 /api/pulse-now（见 startLivePulse）。
        .task { TreehouseHeaderModel.shared.startLivePulse() }
        .onReceive(store.$modelLabel) { label in
            if TreehouseHeaderModel.shared.model != label { TreehouseHeaderModel.shared.model = label }
        }
        .onChange(of: themeName) { newThemeName in
            if newThemeName == "kakao" { KakaoPackStore.shared.refresh() }
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
        .onReceive(KakaoPackStore.shared.$stamp) { _ in
            guard theme.isKakao else { return }
            wallpaperStore.refresh(themeName: themeName, theme: theme, wallStamp: wallStamp)
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
                        // 0926：正文已经画进临时气泡了，这行只在「还没开口、只有思考/工具」时出来
                        if let live = store.live, (live.active || live.finishing), !live.isEmpty,
                           (live.say + live.pendingSay).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            StreamingAssistantRow(state: live, theme: theme, fontSize: chatFontSize)
                                .id("live-\(live.turnID)")
                        }
                        if let al = store.apiLive, !al.isEmpty {
                            // 0926 API 房间流式：半截话从 poll 捎回来，照 tmux 那边的实时气泡画
                            StreamingAssistantRow(state: al, theme: theme, fontSize: chatFontSize)
                                .id("api-live")
                        }
                        if store.isTyping, (store.apiLive?.isEmpty ?? true)
                            || (store.room == "api" && store.currentTool != nil) {
                            TypingIndicator(tool: store.currentTool,
                                            line: store.typingLine,
                                            name: UserDefaults.standard.string(forKey: "assistantName") ?? "陈璟",
                                            theme: theme)
                                .id("typing")
                        }
                        // 信息主题：输入栏和迷你条都挂在安全区那一栏里，系统自己会推，
                        // 列表这边一点都不用替它们留高
                        // 0927 她截图：多选时打字框收起、换成底部那条多选栏，信息主题这里原来只留 12，
                        // 最后一条气泡被栏压住。多选时按栏的高度（54 ＋ 底下 8）留
                        Color.clear.frame(height: (paragraphSelectionMode ? 54 + 8
                                                   : (theme.isMessages ? 0 : bottomChromeHeight)) + 12
                                          + (showMiniTerminal ? miniTerminalHeight + 18 : 0))
                        Color.clear.frame(height: 1).id("tail")
                            .onAppear {
                                atBottom = true
                                farFromTail = false
                                if store.isViewingHistory && !historyJumpInProgress {
                                    Task {
                                        await store.returnToLatest()
                                        scrollToTail(proxy, delays: [0.05, 0.2], animated: false)
                                    }
                                }
                            }
                            // 0919：离底判断改由上面的滚动几何回调管，这里不再抢着写 false
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, theme.isMessages ? 8 : 52)
                }
                // 0919 她报的：他流式说话时页面不跟着往上走。以前「在不在底部」只靠 tail 那 1pt 空气
                // 的 onAppear/onDisappear，懒加载列表里它经常不吭声，followLiveOutput 一开始就是 false。
                // 改成看滚动几何：离最底 120pt 以内算在底部。人翻上去就不跟；翻回底部自动再跟。
                .onScrollGeometryChange(for: Bool.self) { g in
                    g.contentOffset.y + g.containerSize.height >= g.contentSize.height - 120
                } action: { _, near in
                    if near != atBottom { atBottom = near }
                    if near && (store.live?.active == true || store.isTyping) { followLiveOutput = true }
                }
                // 0924：药丸的门槛单独算——离最底超过一整屏才算「翻远了」
                .onScrollGeometryChange(for: Bool.self) { g in
                    let distance = g.contentSize.height - (g.contentOffset.y + g.containerSize.height)
                    return distance > g.containerSize.height * tailPillRevealScreens
                } action: { _, far in
                    if far != farFromTail { farFromTail = far }
                }
                // 0924 她抓的：Kakao 的渐隐罩在整个 ScrollView 外面，把顶栏和打字框一起罩淡了。
                // 改成挂在 safeAreaBar 之前（只罩列表本体），而且只罩顶部那一截，底下不动。
                .modifier(EdgeFadeMaskModifier(enabled: theme.isKakao || theme.isTreehouse, mask: topOnlyFadeMask.ignoresSafeArea()))
                // 0822 她递的图纸：iMessage 的上下渐进模糊是 iOS 26 系统画的 scroll edge effect，
                // 自动混下层颜色、日夜自适配，不许用固定色渐变去模拟。
                // 关键两条：① 栏要用 safeAreaBar 挂（safeAreaInset 不触发底部模糊）；② 列表不翻转（本来就没翻）。
                // 顶栏本体在 RootView 浮着，这里只挂一条同高的透明 bar 把「顶部有栏」告诉系统。
                // 0823 她拍板：顶部放弃渐进模糊，改成纸页主题那种顶部渐隐（edgeFadeMask 顶段同一条曲线，120 高）。
                // 信息主题底是纯色，所以用主题底色做渐变盖上去和纸页的遮罩观感一致，又不碰滚动区（底部系统效果不动）。
                .overlay(alignment: .top) {
                    if theme.isMessages && !theme.isKakao && !theme.isTreehouse {
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
                // 0919：信息主题的「一键到底」挂在这里。这个 overlay 在下面 safeAreaBar 的里面，
                // 打字框占掉的那块系统会替它让开，按钮永远落在打字框正上方，不压发送键。
                .overlay(alignment: .bottomTrailing) {
                    if theme.isMessages && farFromTail && store.pendingVoice == nil {
                        tailPill(proxy)
                            .padding(.trailing, 16)
                            .padding(.bottom, 12)
                            .transition(.opacity)
                    }
                }
                .safeAreaBar(edge: .top, spacing: 0) {
                    if theme.isMessages, let bar = messagesTopBar {
                        if theme.isKakao {
                            // 0924 她选的：Kakao 顶栏透明、矮一点贴灵动岛下面，消息滑到顶部像圆桌那样渐隐（edgeFadeMask）
                            bar().frame(height: 44, alignment: .top)
                        } else if theme.isTreehouse {
                            // 1009 树屋：头像名字一排 + 底下那根上下文进度线，消息从线下面开始
                            // 1009 晚 她报「卡片从顶栏后面透出来跟名字糊一起」：顶栏本体（RootView.treehouseTopBar）
                            // frame 是 84，这里只挂了 80，差的 4 点让顶栏最下沿压在消息上，遮罩也跟着错位。三处对齐到 84。
                            bar().frame(height: 84, alignment: .top)
                        } else {
                            bar().frame(height: 52, alignment: .top)
                        }
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
                        // 0927 任务#2982：API 房间的流式不走 store.live（走 apiLive），原来这里认不出来，
                        // 她往上翻，followLiveOutput 还是 true，每冒一段字就把她拽回底
                        if store.live?.active == true || store.apiLive != nil || store.isTyping {
                            followLiveOutput = false
                        }
                    }
                )
                .modifier(EdgeFadeMaskModifier(enabled: !theme.isMessages, mask: edgeFadeMask))   // 信息主题不罩遮罩，别挡系统效果（Kakao 的顶部渐隐在上面单独罩）
                // 0914：罩与不罩是两条不同的分支，切到／切出信息主题时 SwiftUI 会把这个
                // ScrollView 当成新视图重建，位置掉回最顶上（她原来报的那个 bug）。
                // 重建发生在这一帧，下一帧再把锚点拉回最新一条。
                // 1001 她报「切换主题每次都飞到最顶上」：列表外面两层遮罩，一层看是不是信息主题、一层看是不是 Kakao，
                // 哪层一翻都会重建；原来只盯了前一层，Kakao ↔ 信息就漏了。改成主题名一变就拉回最新（多拉两次等懒加载排好）
                .onChange(of: themeName) { _ in
                    scrollToTail(proxy, delays: [0, 0.1, 0.3], animated: false)
                }
                // 0927：进多选时底下多留了一截给多选栏；本来在最底的话跟着滚下去，最后一条别被栏盖住
                .onChange(of: paragraphSelectionMode) { on in
                    guard on, atBottom else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("tail", anchor: .bottom) }
                    }
                }

                if paragraphSelectionMode {
                    paragraphSelectionToolbar
                } else if !theme.isMessages {
                    floatingInput
                }

                // 0902：迷你播放条退休，歌在放的时候是屏幕边上的小唱片（RootView 管）

                // 1001 她要的：打字框下面那条「点一下回到最新」的窄缝（0907 起）删了，常误触；回最新只留下面那颗药丸。

                // 0917 她要的：重新做一颗「一键到底」。0907 退休的那颗是圆的、她嫌丑；这次是小椭圆、
                // iOS 原生玻璃（跟打字框同一种），不做大。出现条件跟以前那颗一样：人不在最新才有，
                // 语音卡片在时让开（不然压着卡片右上角的垃圾桶）。
                // 0919 她看真机：0918 那版把信息主题的底部留白改成 0，结果这颗直接压在发送键上——
                // 这个 ZStack 浮层不归 safeAreaBar 管，它铺的是整屏。信息主题改挂在列表自己的 overlay 上
                //（见下面 tailPillOverlay），那层在 safeAreaBar 里面，系统会替它避开打字框。这里只画其他主题的。
                if !theme.isMessages && farFromTail && store.pendingVoice == nil {
                    tailPill(proxy)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 16)
                    .padding(.bottom, bottomChromeHeight + 12)
                    .transition(.opacity)
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
                // 0922 任务#2572：原来 0/0.12/0.3 秒连滚三次，整张表跟着重排三回；只留键盘快到位的那一次
                scrollToTail(proxy, delays: [0.12], animated: true)
            }
            .onChange(of: atBottom) { store.viewerAtBottom = $0 }   // 0922：给 appendNew 的封顶看，她在底下才扔老消息
            // 0924「重来」没成时说一声为什么（他正忙、回退菜单对不上号、SDK 通道……）
            // 0928 她要的确认弹窗：点重来先问是否，别再误触
            .alert("重来这一轮？", isPresented: $rerollConfirmShown) {
                Button("取消", role: .cancel) {}
                Button("重来", role: .destructive) { store.rerollLastReply() }
            } message: {
                Text("他这一轮的话会被藏起来，他自己也会忘掉说过，然后重新答一遍。")
            }
            .alert("重来没成", isPresented: rerollAlertShown) {
                Button("好", role: .cancel) {}
            } message: {
                Text(store.rerollNote ?? "")
            }
            .alert("编辑没成", isPresented: editAlertShown) {
                Button("好", role: .cancel) {}
            } message: {
                Text(store.editNote ?? "")
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
                guard !store.switchingRoom else { return }   // 0927：切房间整批换记录，下面 roomSwitchTick 那条管滚
                guard shouldFollowTail else { return }
                scrollToTail(proxy, delays: [0, 0.15, 0.4], animated: true)
            }
            .onChange(of: store.roomSwitchTick) { _ in
                // 0927 任务#2985：切房间记录换好了，无动画直接落到底，只这一处滚
                atBottom = true
                followLiveOutput = true
                // 懒加载列表远处高度是估的，一次落不准；全是无动画的，已经在底了再喊也看不出来
                scrollToTail(proxy, delays: [0, 0.1, 0.3, 0.6], animated: false)
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
            .onChange(of: store.live?.turnID) { id in
                guard id != nil else { return }
                followLiveOutput = shouldFollowTail
            }
            .onChange(of: liveLayoutKey) { _ in
                guard followLiveOutput, !store.isViewingHistory else { return }
                scrollToTail(proxy, delays: [0, 0.05], animated: false)
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
                guard let id = note.object as? String else { return }   // 0922：消息 id 改成 ts|role 字符串
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
        // 0926 她报的「API 流式不会自动滚」：API 房间没有 store.live，靠临时气泡的版本号跟着滚
        guard let live = store.live else { return "api\u{1f}\(store.liveBubbleRev)" }
        return "\(live.turnID)\u{1f}\(live.say)\u{1f}\(live.pendingSay)\u{1f}\(live.timeline.count)\u{1f}\(store.liveBubbleRev)"
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
        // 0927 她说「框太上了」：这一层本来就让着安全区，再垫一个 safeBottom 等于底下空了两截 home 条
        .padding(.bottom, 8)
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
    /// 0924「重来」只挂在他最后一轮上：这条是 assistant，且排在她最后一句后面；翻历史时不给
    private func isLatestAssistantTurn(_ message: ChatMessage) -> Bool {
        guard message.role == "assistant", !store.isViewingHistory else { return false }
        // 0924 她截到两轮尾巴都有箭头：原来是「她最后一句之后的都算」，他自己醒来连说两轮就两个箭头。
        // 改成只认他最后一轮（turn_id 相同的那串；老消息没 turn_id 就只认最后一条）
        guard !message.isLive,
              let last = store.messages.last(where: { $0.role == "assistant" && $0.msgType != "api_error" && !$0.isLive })
        else { return false }
        if let t = last.turnID, !t.isEmpty { return message.turnID == t }
        return message.uid == last.uid
    }

    /// 0924：给 MessageRow 的「重来」回调。抽成函数是为了别在那个几百行的构造里塞三目＋闭包（编译器算不过来，c5bdd8d/72e3404 两笔红）
    private func rerollAction(for message: ChatMessage) -> (() -> Void)? {
        guard store.room != "api", isLatestAssistantTurn(message) else { return nil }   // 0926 重来走的是 tmux，API 房间不给
        // 0928 她误触过一次（任务#3110：他那轮被藏、他自己也退掉不记得了），现在先弹一句问清楚再真重来
        return { rerollConfirmShown = true }
    }

    /// 1001 贴表情：长按文字气泡 → 整屏那层。还没落库的、流式临时气泡不给（1002 起表情包也能贴）
    private func reactLongPress(for message: ChatMessage) -> ((ReactTarget) -> Void)? {
        guard !message.pending, !message.isLive else { return nil }
        return { target in
            inputFocused = false
            selectingTs = nil
            reactTarget = target
        }
    }

    private func exitTextSelection() { selectingTs = nil }

    @ViewBuilder private var reactOverlay: some View {
        if let t = reactTarget {
            ReactionOverlay(target: t, theme: theme,
                            canCopyTurn: t.msg.role == "assistant",
                            canEdit: editAction(for: t.msg) != nil,
                            onPick: { store.react(t.msg, emoji: $0) },
                            onAction: { handleReactAction($0, t) },
                            onDismiss: { reactTarget = nil })
        }
    }

    private func handleReactAction(_ action: ReactionOverlay.Action, _ t: ReactTarget) {
        let m = t.msg
        switch action {
        case .copy: UIPasteboard.general.string = m.displayText
        case .ask:
            selectedQuote = m.displayText
            inputFocused = true
        case .copyTurn: UIPasteboard.general.string = wholeTurnText(for: m)
        case .edit: editAction(for: m)?()
        case .select: selectingTs = m.ts
        case .save:
            let urls = t.urls
            Task { for u in urls { await PhotoLibrarySaver.save(u) } }
        case .favorite: store.favoriteMessage(m)
        }
    }

    /// 0925 她要的「编辑」：只给她自己的文字气泡（CLI 房间、没在翻历史、已经落库的）。
    /// 跟 rerollAction 一样抽成函数，别在 MessageRow 那一长串参数里内联，编译器扛不住
    private func editAction(for message: ChatMessage) -> (() -> Void)? {
        guard message.role == "user", store.room == "cli", !store.isViewingHistory, !message.pending,
              (message.msgType ?? "text") == "text", (message.attachmentUrl ?? "").isEmpty,
              !message.isSticker, !message.isAudio, !message.displayText.isEmpty else { return nil }
        return {
            editDraft = message.displayText
            editingTs = message.ts
        }
    }

    private func sendEdit(_ message: ChatMessage) {
        store.editAndResend(message, newText: editDraft) { ok in
            if ok { editingTs = nil }
        }
    }

    /// 0925：「编辑没成」弹窗的开关
    private var editAlertShown: Binding<Bool> {
        Binding(get: { store.editNote != nil },
                set: { if !$0 { store.editNote = nil } })
    }

    /// 0924：「重来没成」弹窗的开关，抽出来别在 body 链里内联 Binding
    private var rerollAlertShown: Binding<Bool> {
        Binding(get: { store.rerollNote != nil },
                set: { if !$0 { store.rerollNote = nil } })
    }

    // 0924 构建红了「function declares an opaque return type, but has no return statements」：
    // 这个函数体里全是 if / let / Group，本来就该是 ViewBuilder，加了 kakaoHead 那段之后编译器不再替它兜底
    /// 能不能并：树屋 + 整个模式 + 他说的 + 干干净净一段字（没图、没语音、没表情、不是卡片）
    private func thPlainText(_ m: ChatMessage) -> Bool {
        guard theme.isTreehouse, treehouseWholeBubble, m.role == "assistant" else { return false }
        let t = m.msgType ?? ""
        guard t.isEmpty || t == "text" else { return false }
        guard m.stickerId == nil, m.inlineImages.isEmpty, (m.attachmentUrl ?? "").isEmpty,
              !m.isImage, !m.isAudio, !m.isSticker else { return false }
        let body = m.displayText
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        // 卡片（记忆 / 旅行 / 位置 / 选择 / 便签…）正文里带方括号标记，各自成泡
        if body.contains("_CARD]") || body.contains("[INSIDE]") { return false }
        return true
    }

    /// 从这条起，同一轮里连着能并的有几条
    private func thMergeRun(from index: Int) -> Int {
        let first = store.messages[index]
        guard thPlainText(first), let turn = first.turnID, !turn.isEmpty else { return 1 }
        var n = 1
        while index + n < store.messages.count {
            let m = store.messages[index + n]
            guard thPlainText(m), m.turnID == turn else { break }
            n += 1
        }
        return n
    }

    /// 这条是不是已经被前面那条吃进去了（吃进去就不画）
    private func thMergedAway(at index: Int) -> Bool {
        guard index > 0 else { return false }
        let cur = store.messages[index]
        guard thPlainText(cur), let turn = cur.turnID, !turn.isEmpty else { return false }
        let prev = store.messages[index - 1]
        return thPlainText(prev) && prev.turnID == turn
    }

    @ViewBuilder
    private func chatMessageRow(at index: Int, message rawMessage: ChatMessage) -> some View {
        if thMergedAway(at: index) {
            EmptyView()
        } else if !isPhotoGroupContinuation(at: index) {
            // 1009 晚「整个」模式：他同一轮里连着的几段字并成一个气泡，时间那行落在并完的尾巴上
            let mergeRun = thMergeRun(from: index)
            let message: ChatMessage = {
                guard mergeRun > 1 else { return rawMessage }
                var m = rawMessage
                m.text = store.messages[index..<(index + mergeRun)]
                    .map(\.displayText)
                    .joined(separator: "\n\n")
                return m
            }()
            let previous = index > 0 ? store.messages[index - 1] : nil
            let photos = message.inlineImages.isEmpty
                ? chatPhotoGroup(startingAt: index)
                : message.inlineImages.map(AlcoveAPI.attachmentURL)
            let groupEnd = index + max(photos.count, mergeRun, 1) - 1
            let next = groupEnd + 1 < store.messages.count ? store.messages[groupEnd + 1] : nil
            let recall = recallFor(index: index)
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

            // 0925 她定的：三个主题一样，只跟紧挨着的上一条比，不管上一条是什么消息，隔超过 15 分钟就插时间
            // （0924 那套「跳过拍一拍往前找」让互相拍一拍中间插了三次截断，删了）。
            let divided = needsDivider(prev: previous, cur: message, gap: 900)
            if divided {
                if theme.isKakao {
                    KakaoDateDivider(date: message.date)
                } else if theme.isTreehouse {
                    TreehouseTimeDivider(date: message.date, color: theme.dividerColor)
                } else if theme.isMessages {
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
            // 0924 晚她骂的「谁要你改我跟他之间的间距」：bef772f 只该动同一个人连着的气泡，换人那截被一起缩了。
            // 换人（她 ↔ 他、中间没有时间线）的这一行顶上把原来那截补回来：原来行上下各垫 2 + 一串末尾 12，
            // Kakao 他那边气泡还往下挪过 6。同一个人连着的照旧只有设置里的间距。
            let roleGap: CGFloat = {
                guard !divided, let prev = previous,
                      prev.role != message.role,
                      prev.role == "user" || prev.role == "assistant",
                      message.role == "user" || message.role == "assistant" else { return 0 }
                let quiet: Set<String> = ["pat_incoming", "pat_outgoing", "divider", "api_error"]
                if quiet.contains(prev.msgType ?? "") || quiet.contains(message.msgType ?? "") { return 0 }
                if theme.isKakao {
                    return 12 + 2 + ((message.role == "assistant" && listKakaoShowAvatar) ? 6 : 0)
                }
                return 2   // 非 Kakao 一串末尾那 12 还在行底，只补上下各垫的那 2
            }()
            // 0924 Kakao：一串消息的第一条露头像、名字、带尾巴的 01 图；后面几条用 02 图、头像位留空
            let kakaoHead: Bool = {
                guard let prev = previous else { return true }
                // 0925 她抓的「这轮怎么没头像」：前面是「他做了一场梦」那种分隔行（也算他发的、隔不到两分钟），
                // 这条被当成接着上一串。分隔行 / 拍一拍 / 报错行后面那条一律算新一串，露头像
                if Self.kakaoGroupBreakers.contains(prev.msgType ?? "") { return true }
                return divided || isGroupTail(cur: prev, next: message)
            }()
            Group {
            if message.msgType == "pat_outgoing" || message.msgType == "pat_incoming" {
                // 0827 拍一拍：居中一行小字。她拍我常规、我拍她加粗，黑底白底各一套灰
                PatLine(text: message.text,
                        strong: message.msgType == "pat_incoming",
                        isDark: theme.isDark && !theme.isKakao)   // 1002：这行直接压在 Kakao 包的壁纸上，壁纸不分黑白，字色照旧不跟按钮翻
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
                    onReroll: rerollAction(for: message),
                    onEdit: editAction(for: message),
                    isEditing: editingTs == message.ts,
                    editDraft: $editDraft,
                    editBusy: store.editingBusy,
                    onEditCancel: { editingTs = nil },
                    onEditSend: { sendEdit(message) },
                    kakaoHead: kakaoHead,
                    kakaoFirstBubble: theme.isKakao ? kakaoFirstBubble(at: index) : kakaoHead,
                    kakaoUnread: message.role == "user" && next == nil,
                    onPlayMusic: { song in Task { await music.play(song) } },
                    onContentChange: { scrollKick += 1 },
                    onReactLongPress: reactLongPress(for: message),
                    reactLifted: reactTarget?.msg.id == message.id,
                    textSelectable: selectingTs == message.ts,
                    onExitTextSelection: exitTextSelection
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
            .padding(.top, (newSoloTurn ? CGFloat(chatTurnGap) : 0) + roleGap)
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

    /// 0917 她要的那颗小椭圆玻璃「一键到底」本体；信息主题挂列表 overlay，其他主题挂 ZStack 浮层
    private func tailPill(_ proxy: ScrollViewProxy) -> some View {
        Button { jumpToTail(proxy) } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.textDim)
                .frame(width: 46, height: 28)
                .modifier(TailPillGlassModifier(fallbackTint: theme.glassTint,
                                                fallbackBorder: theme.glassBorder))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("回到最新")
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
            // 0917 她报的老毛病：翻得很远时点了回不去。列表是懒加载的，远处的高度是估的，
            // 只喊一次「滚到 tail」会停在半路。开页时是连喊几次才落到底的，这里照办：
            // 动画那一下之后再无动画补几次，让它收敛到真正的最底。
            scrollToTail(proxy, delays: [0.35, 0.7], animated: false)
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

    private func needsDivider(prev: ChatMessage?, cur: ChatMessage, gap: TimeInterval = 900) -> Bool {
        guard let prev else { return true }
        // 只跟紧挨着的上一行比，隔超过 15 分钟就插（三个主题一样）
        return cur.date.timeIntervalSince(prev.date) > gap
    }

    /// 0925 她要的：记忆召回的「✦」尽量跟思绪（圆点、小脑袋）在同一行。
    /// 召回属于她那句话后面他这一轮的第一条；新时间线的轮次里思绪常挂在后面某条（想在哪段就挂哪段），
    /// 「✦」就挪到这一轮第一条带思绪的消息上。老格式的轮次思绪本来就提到轮首，不挪。找不到带思绪的也不挪。
    private func recallFor(index k: Int) -> RecallItem? {
        let msgs = store.messages
        guard k < msgs.count, msgs[k].role == "assistant" else { return nil }
        let turn = msgs[k].turnID ?? ""
        func sameTurn(_ i: Int) -> Bool {
            i >= 0 && i < msgs.count && msgs[i].role == "assistant" && !turn.isEmpty && msgs[i].turnID == turn
        }
        var first = k
        while first > 0 && sameTurn(first - 1) { first -= 1 }
        guard first > 0, msgs[first - 1].role == "user" else { return nil }
        var last = first
        while sameTurn(last + 1) { last += 1 }
        var host = first
        if (first...last).contains(where: { !msgs[$0].segments.isEmpty }) {
            func showsProcess(_ m: ChatMessage) -> Bool {
                if m.segments.contains(where: { ($0.kind == "think" || $0.kind == "thinking") ? !$0.content.isEmpty : $0.kind == "tool" }) { return true }
                if !(m.thinking ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
                return !(m.nativeThinking ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if let j = (first...last).first(where: { showsProcess(msgs[$0]) }) { host = j }
        }
        guard host == k else { return nil }
        return store.recall(forUserText: msgs[first - 1].text, sentAt: msgs[first - 1].date)
    }

    /// 0924 晚她要的：带图案的「第一条」气泡（01 图）给这一串里第一条真画气泡的消息。卡片、照片、语音、表情不算，
    /// 不然图案被卡片吞了；删了第一条（整条拿掉或只清正文）也按眼下还画气泡的算，图案自己顺移到下一条。
    /// 一串的边界跟 kakaoHead 同一条规矩（换人 / 换轮 / 中间有时间胶囊）。
    private func kakaoFirstBubble(at index: Int) -> Bool {
        var k = index
        while k > 0 && !kakaoStartsGroup(k) {
            k -= 1
            if Self.kakaoDrawsBubble(store.messages[k]) { return false }
        }
        return true
    }

    private func kakaoStartsGroup(_ k: Int) -> Bool {
        guard k > 0 else { return true }
        let prev = store.messages[k - 1], cur = store.messages[k]
        if Self.kakaoGroupBreakers.contains(prev.msgType ?? "") { return true }
        return needsDivider(prev: prev, cur: cur, gap: 900) || isGroupTail(cur: prev, next: cur)
    }

    /// 这几种行后面那条算新一串的开头（分隔线、拍一拍、报错行）
    static let kakaoGroupBreakers: Set<String> = ["divider", "pat_incoming", "pat_outgoing", "api_error"]

    /// 跟消息行里那一长串 if / else 对齐：这些卡片、贴纸、语音、音乐都不画九宫格气泡
    static func kakaoDrawsBubble(_ m: ChatMessage) -> Bool {
        let t = m.msgType ?? "text"
        if t == "pat_incoming" || t == "pat_outgoing" || t == "divider" || t == "api_error"
            || t == "tarot_answer" || t == "choice_answer" { return false }
        if m.morningPaperDate != nil || m.insideText != nil || m.ghostCard != nil || m.playCard != nil
            || m.favoriteForward != nil || m.readingCard != nil || m.tarotCard != nil || m.tarotOffer != nil
            || m.workCard != nil || m.albumSavedCard != nil || m.buyCard != nil || m.paidCard != nil
            || m.pondCard != nil || m.memoryCard != nil
            || m.ticketCard != nil || m.choiceCard != nil || m.letterCard != nil || m.journeyCard != nil
            || m.callSummary != nil || m.musicCard != nil { return false }
        if m.reminderCard != nil { return false }   // 1002 单独一行，上面那串够长了，别再让编译器算超时
        if m.locationCard != nil { return false }   // 1008 位置卡
        if m.isSticker || m.isAudio || m.isBareLink { return false }
        return !m.displayText.isEmpty
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

    /// Kakao / 树屋共用：只有顶部那一截渐隐，底下全亮。
    /// 她抓的「圆桌有这么长吗」：圆桌那 120 有一大半藏在顶栏后面，露出来五十来点；
    /// 这里列表从顶栏底下起，整段都露着，所以只给 60。
    private var topOnlyFadeMask: some View {
        // 0924 她抓的「底下被截断」：遮罩默认只铺在安全区里，打字框底下那块不在里面，滑到打字框后面的消息
        // 直接被切掉。遮罩得铺满整屏（ignoresSafeArea），顶栏那段留空白（隐藏），再接 60 的渐隐，底下全亮，
        // 消息照常从半透明的打字框后面滑过去。
        // 树屋顶栏含上下文进度线，高 80；Kakao 仍为 44。
        let chromeTop = Self.topSafeInset + (theme.isTreehouse ? 84 : 44)
        return VStack(spacing: 0) {
            Color.clear.frame(height: chromeTop)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.3), location: 0.35),
                    .init(color: .black.opacity(0.7), location: 0.65),
                    .init(color: .black, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 60)
            Color.black
        }
    }

    private static var topSafeInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.safeAreaInsets.top ?? 59
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
                if theme.isTreehouse { treehouseComposerRow }
                else if theme.isMessages { messagesComposerRow } else { classicComposerBody }
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
        })
        .onPreferenceChange(InputBarHeightKey.self) { inputBarHeight = $0 }
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
    /// 0929 她要的：Kakao 的输入框整体跟信息主题一模一样（白天 / 黑夜、调色板都走信息主题那套）
    private var composerTheme: AlcoveTheme {
        guard theme.isKakao else { return theme }
        var t = AlcoveTheme.named(AlcoveAppearance.isDark ? "imessage-dark" : "imessage")
        t.sendButton = KakaoSendButton.fill     // 1002：Kakao 发送键跟主题包 / 她单独调的走，不借信息主题那份
        return t
    }

    private var sendArrowColor: Color { theme.isKakao ? KakaoSendButton.arrow : .white }

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
            Button { showLocationPicker = true } label: {
                Label("位置", systemImage: "location")       // 1008 iMessage 那样发位置 / 共享实时位置 / 搜地点
            }
            if composerTheme.isMessages {
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
            if composerTheme.isTreehouse {
                // 1009 树屋：光秃秃一个细加号，不垫玻璃圆（她成品里就是这样）
                Image(systemName: "plus")
                    .font(.system(size: 21, weight: .light))
                    .foregroundColor(TreehouseInk.ink)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            } else {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(composerTheme.textDim)
                .frame(width: composerTheme.isMessages ? 40 : 36, height: composerTheme.isMessages ? 40 : 36)
                .modifier(MessagesGlassModifier(
                    face: composerTheme.isDark ? Color(red: 28/255, green: 28/255, blue: 30/255) : Color.white,
                    line: composerTheme.isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06),
                    shadow: Color.black.opacity(composerTheme.isDark ? 0.35 : 0.10),
                    circle: true, enabled: composerTheme.isMessages))
                .background((composerTheme.isMessages ? Color.clear : composerTheme.glassTint.opacity(composerTheme.isDark ? 0.64 : 0.82)), in: Circle())
            }
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
        let line = composerTheme.isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
        let face = composerTheme.isDark ? Color(red: 28/255, green: 28/255, blue: 30/255) : Color.white
        let shadow = Color.black.opacity(composerTheme.isDark ? 0.35 : 0.10)
        let showBlue = isGenerating || canSend || recorder.isRecording || store.heldCount > 0 || store.pendingVoice != nil
        return HStack(alignment: .bottom, spacing: 10) {
            if recorder.isRecording {
                // 0822 她报的：录音时叉点不掉。玻璃贴在图标上把点击吞了——
                // 改成玻璃当按钮的背景，热区明确给成整个圆。
                Button(action: { recorder.cancel() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(composerTheme.textDim)
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
                        .foregroundColor(composerTheme.text)
                    Text("录音中… 按■停下").font(.system(size: 14)).foregroundColor(composerTheme.textDim)
                    Spacer(minLength: 0)
                } else {
                    // 0823 她报的：信息主题按回车不攒气泡。病根是这个框没写 axis: .vertical，
                    // 单行框的回车走 submit 不往 draft 里塞换行，handleDraftChange 的
                    // 「新值 == 旧值 + \n」永远对不上。改成跟纸页那边同一套：竖轴 + 1...5 行。
                    // 0925 凌晨 Kakao 下占位字改成跟加号 / 话筒一样用包里的次要字色；当天中午她说「太丑了，改回信息主题那样」，
                    // 所以哪个主题都是系统灰的占位字，别再给 Kakao 单独染色。
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
                            .foregroundColor(showBlue ? sendArrowColor : composerTheme.textDim)
                            .frame(width: 30, height: 30)
                            .background(showBlue ? composerTheme.sendButtonColor : Color.clear, in: Circle())
                        if store.heldCount > 0 {
                            Text("\(store.heldCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .frame(minWidth: 14, minHeight: 14)
                                .background(composerTheme.sendButtonColor, in: Capsule())
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

    /// 1009 树屋输入栏，照她成品：细加号｜雾白半透明胶囊（墨线描边，占位字斜体「drop a leaf…」，右边一支话筒）｜
    /// 外面一颗同材质的圆，里面一片叶子＝发送。叶子只管发 / 停；空着的时候按它不录音，录音走胶囊里的话筒。
    private var treehouseComposerRow: some View {
        let ink = TreehouseInk.ink
        let hasPayload = canSend || store.heldCount > 0 || store.pendingVoice != nil
        return HStack(alignment: .bottom, spacing: 2) {
            if recorder.isRecording {
                Button(action: { recorder.cancel() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .light))
                        .foregroundColor(ink)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                composerPlusMenu
            }
            HStack(alignment: .center, spacing: 6) {
                if recorder.isRecording {
                    Circle().fill(TreehouseInk.blue).frame(width: 7, height: 7)
                    Text(String(format: "%d:%02d", recorder.seconds / 60, recorder.seconds % 60))
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundColor(ink)
                    Text("录音中… 按叶子停下").font(.system(size: 13)).foregroundColor(ink.opacity(0.55))
                    Spacer(minLength: 0)
                } else {
                    TextField("", text: $draft,
                              prompt: Text("drop a leaf…").font(.system(size: 16, design: .serif).italic())
                                .foregroundColor(ink.opacity(0.6)),
                              axis: .vertical)
                        .focused($inputFocused)
                        .lineLimit(1...5)
                        .font(.system(size: 15))
                        .foregroundColor(ink)
                        .tint(ink)
                        .onChange(of: draft) { value in handleDraftChange(value) }
                    if !hasPayload && !isGenerating {
                        Button { recorder.start() } label: {
                            Image(systemName: "mic")
                                .font(.system(size: 15, weight: .light))
                                .foregroundColor(ink.opacity(0.55))
                                .frame(width: 28, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .padding(.vertical, 5)
            .frame(minHeight: 40)
            .modifier(TreehouseFogGlass(shape: Capsule(), border: 0.55))
            .contentShape(Capsule())
            .onTapGesture { if !recorder.isRecording { inputFocused = true } }
            .padding(.trailing, 8)
            Button {
                if hasPayload || isGenerating || recorder.isRecording { performDynamicComposerAction() }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if isGenerating || recorder.isRecording {
                            Image(systemName: "stop.fill").font(.system(size: 13))
                                .foregroundColor(composerTheme.sendButtonColor)
                        } else {
                            TreehouseLeafShape()
                                .stroke(composerTheme.sendButtonColor, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                                .frame(width: 19, height: 19)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .modifier(TreehouseFogGlass(shape: Circle(), border: 0.7))
                    if store.heldCount > 0 {
                        Text("\(store.heldCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(TreehouseInk.white)
                            .frame(minWidth: 14, minHeight: 14)
                            .background(ink, in: Capsule())
                            .offset(x: 2, y: -2)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, -2)
        }
        .padding(.init(top: 6, leading: 14, bottom: 6, trailing: 18))
    }

    private func holdCurrentDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        // 0905 她报的：攒气泡时引用不跟着走。攒的这条就把引用带上（outgoingText 拼完会清掉引用条）
        store.sendHold(outgoingText(text))
        inputFocused = true
    }

    /// 文字效果：面板要预览的那几个字（没选就是空，面板会写「套整条」）
    private var effectSelectionText: String {
        guard let r = effectRange, r.length > 0, NSMaxRange(r) <= (draft as NSString).length else { return "" }
        return (draft as NSString).substring(with: r)
    }

    /// 文字效果：把标记套到选中的字上；没选就套整条。走 handlingReturn 免得被当成回车/链接处理
    private func applyTextEffect(_ kind: TextEffectKind) {
        let ns = draft as NSString
        var r = effectRange ?? NSRange(location: 0, length: ns.length)
        if r.length == 0 || NSMaxRange(r) > ns.length { r = NSRange(location: 0, length: ns.length) }
        guard ns.length > 0 else { return }
        let wrapped = TextEffects.wrap(ns.substring(with: r), in: kind)
        handlingReturn = true
        draft = ns.replacingCharacters(in: r, with: wrapped)
        previousDraft = draft
        effectRange = nil
        DispatchQueue.main.async { handlingReturn = false }
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
    /// 0917 任务#2209 插话：她框里一有东西（字 / 图 / 表情 / 链接）就让回发送键，跟「语音键一打字变发送」同一个道理；
    /// 框空着才是停止键。
    private var isGenerating: Bool {
        (store.isTyping || store.live?.active == true) && !recorder.isRecording && !canSend
    }

    private func stopGenerating() {
        store.isTyping = false
        store.live = nil
        Task { _ = try? await AlcoveAPI.postRaw("/api/chat-stop", body: [:]) }
    }

    private func performDynamicComposerAction() {
        guard !store.stagingImages else { return }
        // 0926 API 房间：字 / 图 / 语音都能发（任务#2954），但不给停止键——停止那条路掐的是 tmux 的他
        if store.room == "api" && isGenerating { return }
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
            if store.heldCount > 0 && store.room != "api" {   // 攒着的是 tmux 那边的，API 房间别去放
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
            // 0926 任务#2963：API 房间也走这一条（跟 tmux 统一，气泡里是表情图），AlcoveAPI 会带上 room=api
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
        .init(id: "claude-fable-5-1", label: "Fable 5.1", note: "最新，需要 usage credits"),
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
                        .foregroundColor(sheetTheme.text)
                        .frame(width: 44, height: 44)
                        .background(sheetTheme.glassTint.opacity(0.52), in: Circle())
                        .overlay(Circle().stroke(sheetTheme.glassBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()
                Text(showMoreModels ? "More models" : "Select model")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(sheetTheme.text)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }

            // 当前通道一行：左边写着现在主聊天走的是谁，右边 cli / sdk 切着看两页（样式不变，只多这一行）
            HStack(spacing: 10) {
                Text("当前通道")
                    .font(.system(size: 12))
                    .foregroundColor(sheetTheme.textDim)
                Text(activeChatChannel.uppercased())
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(sheetTheme.text)
                Spacer()
                HStack(spacing: 2) {
                    ForEach(["cli", "sdk"], id: \.self) { p in
                        Button {
                            modelPanel = p; modelPanelResolved = true; showMoreModels = false; modelSwitchError = ""
                        } label: {
                            Text(p)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(modelPanel == p ? sheetTheme.text : sheetTheme.textDim)
                                .padding(.horizontal, 11).padding(.vertical, 5)
                                .background(modelPanel == p ? sheetTheme.fyCard.opacity(0.95) : .clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(sheetTheme.glassTint.opacity(0.4), in: Capsule())
                .overlay(Capsule().stroke(sheetTheme.glassBorder, lineWidth: 1))
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
                                .foregroundColor(sheetTheme.textDim)
                        }
                        Spacer()
                        if switchingThinking {
                            ProgressView().controlSize(.small)
                                .frame(width: 42)
                        } else {
                            Capsule()
                                .fill(thinkingEnabled ? sheetTheme.sendTop : sheetTheme.textDim.opacity(0.22))
                                .frame(width: 42, height: 24)
                                .overlay(alignment: thinkingEnabled ? .trailing : .leading) {
                                    Circle().fill(.white).frame(width: 20, height: 20).padding(2)
                                }
                                .opacity(thinkingKnown ? 1 : 0.45)
                                .animation(.spring(response: 0.24, dampingFraction: 0.8), value: thinkingEnabled)
                        }
                    }
                    .foregroundColor(sheetTheme.text)
                    .padding(.horizontal, 18)
                    .frame(height: 66)
                    .background(sheetTheme.fyCard.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        .foregroundColor(sheetTheme.text)
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
                    .foregroundColor(sheetTheme.textDim)
            }
            .foregroundColor(sheetTheme.text)
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(sheetTheme.fyCard.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                else { Text(current.isEmpty ? "未知" : current).font(.system(size: 12, design: .monospaced)).foregroundColor(sheetTheme.textDim) }
            }
            HStack(spacing: 6) {
                ForEach(effortLevels, id: \.self) { lvl in
                    Button { onPick(lvl) } label: {
                        Text(lvl)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(current == lvl ? .white : sheetTheme.text)
                            .frame(maxWidth: .infinity).frame(height: 30)
                            .background(current == lvl ? sheetTheme.sendTop : sheetTheme.textDim.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(hint).font(.system(size: 11)).foregroundColor(sheetTheme.textDim)
        }
        .foregroundColor(sheetTheme.text)
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(sheetTheme.fyCard.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

extension Notification.Name {
    /// 0919 左上角的门：RootView 顶栏发这个，ChatView 弹房间选择
    static let alcoveOpenRoomPicker = Notification.Name("alcove.openRoomPicker")
}

/// 0919 她要的三个房间：tmux（cli）/ SDK / API。开关还是那一个，挑 cli 或 sdk 就拨开关，
/// 聊天页只拉那间的记录；api 后端还没做，先只能看。
private struct ChatRoomPicker: View {
    @Binding var activeChannel: String
    let currentRoom: String
    let onPickRoom: (String) -> Void
    let onOpenChannelPanel: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var working = ""
    @State private var message = ""
    @State private var handoffTurns = 12

    private let rooms: [(id: String, name: String, icon: String, note: String)] = [
        ("cli", "tmux", "terminal", "老路，hook 和工具最全"),
        ("sdk", "SDK", "bolt.horizontal", "常驻会话，回得快"),
        ("api", "API", "antenna.radiowaves.left.and.right", "纯 API 走中转站，跟上面两间不相干"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rooms, id: \.id) { r in
                        Button { Task { await pick(r.id) } } label: {
                            HStack(spacing: 12) {
                                Image(systemName: r.icon).frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.name).font(.system(size: 16, weight: .medium))
                                    Text(r.note).font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if working == r.id { ProgressView().controlSize(.small) }
                                else if currentRoom == r.id {
                                    Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.tint)
                                }
                                if activeChannel == r.id {
                                    Text("开关在这").font(.system(size: 11)).foregroundStyle(.secondary)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.15), in: Capsule())
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!working.isEmpty)
                    }
                } footer: {
                    Text(message.isEmpty ? "挑 tmux 或 SDK 会把开关一起拨过去，带 \(handoffTurns) 轮接着聊。" : message)
                        .foregroundStyle(message.contains("失败") ? .red : .secondary)
                }
                Section {
                    Button { onOpenChannelPanel() } label: {
                        Label("通道设置", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink { ApiRelayPanel() } label: {
                        Label("API 中转站", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
            }
            .navigationTitle("房间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .task {
                if let obj = try? await AlcoveAPI.getRaw("/api/sdk-shadow/status"),
                   let cfg = obj["config"] as? [String: Any],
                   let n = (cfg["handoff_turns"] as? NSNumber)?.intValue, n > 0 { handoffTurns = n }
            }
        }
    }

    @MainActor private func pick(_ id: String) async {
        message = ""
        if id == "api" || id == activeChannel {
            onPickRoom(id); dismiss(); return
        }
        working = id
        do {
            let obj = try await AlcoveAPI.postRaw("/api/sdk-shadow/switch", body: [
                "channel": id, "handoff_turns": handoffTurns, "keep_session": true
            ])
            guard obj["ok"] as? Bool == true else {
                throw NSError(domain: "Room", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: obj["error"] as? String ?? "切换失败"])
            }
            activeChannel = obj["channel"] as? String ?? id
            onPickRoom(activeChannel)
            working = ""
            dismiss()
        } catch {
            working = ""
            message = "切换失败：\(error.localizedDescription)"
        }
    }
}

/// 0926 她要的 API 房间：中转站可以存好几家，点一家就用那家。key 只回尾巴四位，改的时候留空就不动原来的。
/// 任务#2945 照她给的 Polaris 截图加了：常用模板、四种接口格式、自定义路径、测试连接、拉模型列表、每家三个开关。
private func apiFormatLabel(_ f: String) -> String {
    switch f {
    case "anthropic": return "Anthropic 兼容"
    case "responses": return "Responses API"
    case "gemini": return "Gemini 原生"
    default: return "OpenAI 兼容"
    }
}

private struct ApiRelayPanel: View {
    struct Relay: Identifiable {
        let id: Int
        var name: String, baseURL: String, model: String, format: String, apiPath: String, keyTail: String
        var image: Bool, stream: Bool, thinking: Bool, tools: Bool, contextK: Int, active: Bool
    }
    @State private var relays: [Relay] = []
    @State private var editing: Relay? = nil
    @State private var adding = false
    @State private var message = ""

    var body: some View {
        List {
            Section {
                if relays.isEmpty {
                    Text("还没有，点右上角 + 添一家").foregroundStyle(.secondary)
                }
                ForEach(relays) { r in
                    HStack(spacing: 10) {
                        Button { Task { await apply(r) } } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).font(.system(size: 16, weight: .medium))
                                Text(r.model.isEmpty ? "还没填模型" : r.model)
                                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                                Text(apiFormatLabel(r.format))
                                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if r.active {
                            Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(.tint)
                        }
                        Button { editing = r } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless)
                    }
                    .swipeActions {
                        Button(role: .destructive) { Task { await remove(r) } } label: { Label("删除", systemImage: "trash") }
                    }
                }
            } footer: {
                Text(message.isEmpty ? "点一家就用那家，打勾的是现在在用的。API 房间里说的话会发给这家中转站。" : message)
                    .foregroundStyle(message.contains("失败") ? .red : .secondary)
            }
        }
        .navigationTitle("API 中转站")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") } } }
        .task { await load() }
        .sheet(item: $editing) { r in ApiRelayForm(relay: r) { Task { await load() } } }
        .sheet(isPresented: $adding) { ApiRelayForm(relay: nil) { Task { await load() } } }
    }

    @MainActor private func load() async {
        guard let obj = try? await AlcoveAPI.getRaw("/api/apiconfigs/list") else { message = "读取失败"; return }
        relays = (obj["configs"] as? [[String: Any]] ?? []).compactMap { c in
            guard let id = (c["id"] as? NSNumber)?.intValue else { return nil }
            return Relay(id: id, name: c["name"] as? String ?? "", baseURL: c["base_url"] as? String ?? "",
                         model: c["model"] as? String ?? "", format: c["api_format"] as? String ?? "openai",
                         apiPath: c["api_path"] as? String ?? "", keyTail: c["key_tail"] as? String ?? "",
                         image: c["supports_image"] as? Bool ?? false, stream: c["stream"] as? Bool ?? true,
                         thinking: c["thinking"] as? Bool ?? false, tools: c["tools"] as? Bool ?? true,
                         contextK: ((c["context_window"] as? NSNumber)?.intValue ?? 200000) / 1000,
                         active: c["active"] as? Bool ?? false)
        }
    }

    @MainActor private func apply(_ r: Relay) async {
        _ = try? await AlcoveAPI.postRaw("/api/apiconfigs/apply", body: ["id": r.id])
        message = "现在用：\(r.name)"
        await load()
    }

    @MainActor private func remove(_ r: Relay) async {
        _ = try? await AlcoveAPI.postRaw("/api/apiconfigs/delete", body: ["id": r.id])
        await load()
    }
}

private struct ApiRelayForm: View {
    let relay: ApiRelayPanel.Relay?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var baseURL = ""
    @State private var key = ""
    @State private var model = ""
    @State private var format = "openai"
    @State private var apiPath = ""
    @State private var image = false
    @State private var stream = true
    @State private var thinking = false
    @State private var tools = true
    @State private var contextK = "200"
    @State private var saving = false
    @State private var message = ""
    @State private var testing = false
    @State private var testNote = ""
    @State private var testOK = false
    @State private var models: [String] = []
    @State private var loadingModels = false
    @State private var showModels = false

    // 常用的几家：选了自动填地址和格式，只剩 key 和模型要她填
    private let templates: [(name: String, url: String, format: String)] = [
        ("OpenAI", "https://api.openai.com/v1", "openai"),
        ("Anthropic", "https://api.anthropic.com/v1", "anthropic"),
        ("Gemini", "https://generativelanguage.googleapis.com", "gemini"),
        ("OpenRouter", "https://openrouter.ai/api/v1", "openai"),
        ("DeepSeek", "https://api.deepseek.com/v1", "openai"),
        ("硅基流动", "https://api.siliconflow.cn/v1", "openai"),
        ("Moonshot（Kimi）", "https://api.moonshot.cn/v1", "openai"),
        ("智谱 GLM", "https://open.bigmodel.cn/api/paas/v4", "openai"),
        ("通义千问", "https://dashscope.aliyuncs.com/compatible-mode/v1", "openai"),
        ("xAI（Grok）", "https://api.x.ai/v1", "openai"),
    ]

    private var defaultPath: String {
        switch format {
        case "anthropic": return "/v1/messages"
        case "responses": return "/v1/responses"
        case "gemini": return "/v1beta/models/{model}:generateContent"
        default: return "/v1/chat/completions"
        }
    }

    private var formBody: [String: Any] {
        var body: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespaces),
            "base_url": baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            "api_key": key.trimmingCharacters(in: .whitespacesAndNewlines),
            "model": model.trimmingCharacters(in: .whitespacesAndNewlines),
            "api_format": format,
            "api_path": apiPath.trimmingCharacters(in: .whitespacesAndNewlines),
            "supports_image": image, "stream": stream, "thinking": thinking, "tools": tools,
            "context_window": (Int(contextK.trimmingCharacters(in: .whitespaces)) ?? 200) * 1000,
        ]
        if let r = relay { body["id"] = r.id }
        return body
    }

    var body: some View {
        NavigationStack {
            Form {
                basicSection
                formatSection
                modelSection
                switchSection
                testSection
            }
            .navigationTitle(relay == nil ? "添一家" : "改一下")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("存") { Task { await save() } }
                        .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let r = relay {
                    name = r.name; baseURL = r.baseURL; model = r.model; format = r.format; apiPath = r.apiPath
                    image = r.image; stream = r.stream; thinking = r.thinking
                    tools = r.tools; contextK = String(r.contextK)
                }
            }
            .sheet(isPresented: $showModels) {
                ApiModelPicker(models: models) { picked in model = picked }
            }
        }
    }

    private var basicSection: some View {
        Section {
            Menu {
                ForEach(templates, id: \.name) { t in
                    Button(t.name) {
                        baseURL = t.url; format = t.format; apiPath = ""
                        if name.trimmingCharacters(in: .whitespaces).isEmpty { name = t.name }
                    }
                }
            } label: {
                HStack {
                    Text("从常用的里挑").foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            TextField("名字（自己认得就行）", text: $name)
            TextField("地址，比如 https://xxx.com", text: $baseURL)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            SecureField(relay == nil ? "Key" : "Key（留空就不改，现在是 …\(relay?.keyTail ?? "")）", text: $key)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
        } footer: {
            Text("用中转站就选「手动」：直接填中转站给你的地址和 key。")
        }
    }

    private var formatSection: some View {
        Section {
            Picker("接口格式", selection: $format) {
                Text("OpenAI 兼容").tag("openai")
                Text("Anthropic 兼容").tag("anthropic")
                Text("Responses API").tag("responses")
                Text("Gemini 原生").tag("gemini")
            }
            .pickerStyle(.menu)
            TextField("路径（不填就用 \(defaultPath)）", text: $apiPath)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(.system(size: 14))
        } footer: {
            Text("拿不准就选 OpenAI 兼容。路径一般空着，中转站说明里写了怪路径才填。")
        }
    }

    private var modelSection: some View {
        Section {
            TextField("模型，比如 claude-opus-4-6", text: $model)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button {
                Task { await fetchModels() }
            } label: {
                HStack {
                    Text("从中转站拉模型列表")
                    Spacer()
                    if loadingModels { ProgressView().controlSize(.small) }
                }
            }
            .disabled(loadingModels || baseURL.isEmpty)
        }
    }

    private var switchSection: some View {
        Section {
            Toggle("支持图片", isOn: $image)
            Toggle("流式输出", isOn: $stream)
            Toggle("思考 / 推理", isOn: $thinking)
            Toggle("工具", isOn: $tools)
            HStack {
                Text("上下文上限")
                Spacer()
                TextField("200", text: $contextK)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text("K").foregroundStyle(.secondary)
            }
        } footer: {
            Text("图片：模型看得懂图才开，开了你发的图他能看见。流式：开了字会一段段冒出来，关了等他说完一整段才出来。思考：让模型先想再说；有的模型不认，开了报错就关掉。工具：记忆、日记、檐下、书房、语音、表情、相册这些本事，模型不会用工具就关掉。上下文上限：这个模型一窗能装多少，Claude 一般 200K，只用来画上下文条。")
        }
    }

    private var testSection: some View {
        Section {
            Button {
                Task { await runTest() }
            } label: {
                HStack {
                    Text("测试连接")
                    Spacer()
                    if testing { ProgressView().controlSize(.small) }
                }
            }
            .disabled(testing || baseURL.isEmpty || model.isEmpty)
        } footer: {
            Text(testNote.isEmpty ? "按这页填的发一句最短的话，看通不通。不用先存。" : testNote)
                .foregroundStyle(testNote.isEmpty ? Color.secondary : (testOK ? Color.green : Color.red))
        }
    }

    @MainActor private func runTest() async {
        testing = true
        testNote = ""
        defer { testing = false }
        guard let obj = try? await AlcoveAPI.postRaw("/api/apiconfigs/test", body: formBody) else {
            testOK = false; testNote = "测试失败：连不上小屋"; return
        }
        let secs = (obj["secs"] as? NSNumber)?.doubleValue ?? 0
        if obj["ok"] as? Bool == true {
            testOK = true
            let reply = obj["reply"] as? String ?? ""
            testNote = "通了，\(String(format: "%.1f", secs)) 秒" + (reply.isEmpty ? "" : "，它回：\(reply)")
        } else {
            testOK = false
            testNote = "没通：\(obj["error"] as? String ?? "不知道为啥")"
        }
    }

    @MainActor private func fetchModels() async {
        loadingModels = true
        defer { loadingModels = false }
        guard let obj = try? await AlcoveAPI.postRaw("/api/apiconfigs/models", body: formBody) else {
            testOK = false; testNote = "拉列表失败：连不上小屋"; return
        }
        if obj["ok"] as? Bool == true, let list = obj["models"] as? [String], !list.isEmpty {
            models = list
            showModels = true
        } else {
            testOK = false
            testNote = "拉列表失败：\(obj["error"] as? String ?? "中转站没给")"
        }
    }

    @MainActor private func save() async {
        saving = true
        defer { saving = false }
        do {
            let obj = try await AlcoveAPI.postRaw("/api/apiconfigs/save", body: formBody)
            guard obj["ok"] as? Bool == true else { message = "存失败：\(obj["error"] as? String ?? "")"; testNote = message; return }
            onSaved()
            dismiss()
        } catch {
            testOK = false
            testNote = "存失败：\(error.localizedDescription)"
        }
    }
}

private struct ApiModelPicker: View {
    let models: [String]
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var shown: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? models : models.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List(shown, id: \.self) { m in
                Button { onPick(m); dismiss() } label: {
                    Text(m).font(.system(size: 14)).foregroundStyle(.primary)
                }
            }
            .searchable(text: $query, prompt: "搜模型")
            .navigationTitle("挑一个模型（\(models.count)）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } } }
        }
    }
}

/// 0926 任务#2954：API 房间输入框上面那根上下文条。显示「这一窗已经用了多少 / 上限」，点开看明细、换窗。
struct ApiContext {
    var limit = 200000, system = 0, tools = 0, chat = 0, images = 0, estimate = 0
    var lastInput: Int? = nil
    var windowStarted = "", carried = false, messages = 0, herMessages = 0
    var used: Int { lastInput ?? estimate }
    var ratio: Double { limit > 0 ? min(1, Double(used) / Double(limit)) : 0 }

    init() {}
    init(_ o: [String: Any]) {
        func i(_ k: String) -> Int { (o[k] as? NSNumber)?.intValue ?? 0 }
        limit = max(1, i("limit")); system = i("system"); tools = i("tools"); chat = i("chat")
        images = i("images"); estimate = i("estimate")
        lastInput = (o["last_input"] as? NSNumber)?.intValue
        windowStarted = o["window_started"] as? String ?? ""
        carried = o["carried"] as? Bool ?? false
        messages = i("messages"); herMessages = i("her_messages")
    }

    static func k(_ n: Int) -> String { n < 1000 ? "\(n)" : String(format: "%.1fK", Double(n) / 1000) }
}

func apiContextColor(_ r: Double) -> Color {
    r < 0.6 ? .green : (r < 0.85 ? .orange : .red)
}

/// 0926 任务#2959：API 房间顶栏名字下面那根进度条（「15.2K/8%」），点名字 / 头像弹上下文和换窗面板。
/// 顶栏拿不到聊天页的 store，所以自己隔几秒问一次后端。
struct ApiContextHeaderBar: View {
    let textColor: Color
    @State private var ctx = ApiContext()
    @State private var loaded = false

    var body: some View {
        HStack(spacing: 5) {
            ZStack(alignment: .leading) {
                Capsule().fill(textColor.opacity(0.18)).frame(width: 54, height: 3)
                Capsule().fill(apiContextColor(ctx.ratio)).frame(width: max(2, 54 * ctx.ratio), height: 3)
            }
            Text(loaded ? "\(ApiContext.k(ctx.used))/\(Int((ctx.ratio * 100).rounded()))%" : "…")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundColor(textColor.opacity(0.75))
        }
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(.ultraThinMaterial, in: Capsule())
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: 6_000_000_000)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .alcoveApiContextChanged)) { _ in
            Task { await load() }
        }
    }

    @MainActor private func load() async {
        if let o = try? await AlcoveAPI.getRaw("/api/api-room/context"), o["ok"] as? Bool == true {
            ctx = ApiContext(o)
            loaded = true
        }
    }
}

extension Notification.Name {
    static let alcoveApiContextChanged = Notification.Name("alcoveApiContextChanged")
}

/// 点顶栏名字弹出来的面板：自己拉一次数，磨砂毛玻璃底
struct ApiContextPanel: View {
    @State private var ctx = ApiContext()
    @State private var loaded = false

    var body: some View {
        ApiContextSheet(ctx: ctx) {
            NotificationCenter.default.post(name: .alcoveApiContextChanged, object: nil)
        }
        .task {
            if let o = try? await AlcoveAPI.getRaw("/api/api-room/context"), o["ok"] as? Bool == true {
                ctx = ApiContext(o)
                loaded = true
            }
        }
        .presentationBackground(.ultraThinMaterial)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct ApiContextSheet: View {
    let ctx: ApiContext
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var carry = 0
    @State private var working = false
    @State private var message = ""

    private var startedText: String {
        guard !ctx.windowStarted.isEmpty else { return "还没换过窗" }
        let s = ctx.windowStarted.replacingOccurrences(of: "T", with: " ")
        return String(s.prefix(16)) + (ctx.carried ? "（带了上一窗几句）" : "")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(ApiContext.k(ctx.used)).font(.system(size: 28, weight: .semibold, design: .rounded))
                            Text("/ \(ApiContext.k(ctx.limit))").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(ctx.ratio * 100))%").font(.system(size: 15, weight: .medium))
                                .foregroundColor(apiContextColor(ctx.ratio))
                        }
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.secondary.opacity(0.18))
                                Capsule().fill(apiContextColor(ctx.ratio)).frame(width: max(4, g.size.width * ctx.ratio))
                            }
                        }
                        .frame(height: 8)
                        Text(ctx.lastInput != nil ? "上一轮中转站报的真实数" : "还没有中转站报的数，这是估的")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.primary.opacity(0.06))
                Section {
                    row("锚点（人格、记忆索引）", ctx.system)
                    row("工具说明", ctx.tools)
                    row("这一窗的聊天", ctx.chat)
                    row("图片", ctx.images)
                    row("估算合计", ctx.estimate)
                    if let li = ctx.lastInput { row("上一轮实际发出去", li) }
                } header: { Text("都占在哪") } footer: {
                    Text("估算是按字数粗算的，跟中转站报的会差一点。每轮还会临时带一段记忆召回，不算在里面。")
                }
                .listRowBackground(Color.primary.opacity(0.06))
                Section {
                    LabeledContent("这一窗从", value: startedText)
                    LabeledContent("这一窗气泡", value: "\(ctx.messages) 条（你说了 \(ctx.herMessages) 句）")
                }
                .listRowBackground(Color.primary.opacity(0.06))
                Section {
                    Stepper(value: $carry, in: 0...30) {
                        Text(carry == 0 ? "什么都不带，从头来" : "带上你最近 \(carry) 句起的对话")
                    }
                    Button {
                        Task { await newWindow() }
                    } label: {
                        HStack {
                            Text("开新窗口").fontWeight(.medium)
                            Spacer()
                            if working { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(working)
                } header: { Text("换窗") } footer: {
                    Text(message.isEmpty ? "换窗以后他只记得线下面的话（加上你选择带过去的那几句），聊天记录不会删，往上翻都还在。锚点和记忆照旧。" : message)
                        .foregroundStyle(message.contains("失败") ? .red : .secondary)
                }
                .listRowBackground(Color.primary.opacity(0.06))
            }
            .scrollContentBackground(.hidden)          // 0926 她要磨砂毛玻璃：列表底透掉，格子半透
            .navigationTitle("API 房间上下文")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .background(Color.clear)
    }

    private func row(_ title: String, _ n: Int) -> some View {
        LabeledContent(title, value: ApiContext.k(n))
    }

    @MainActor private func newWindow() async {
        working = true
        defer { working = false }
        guard let o = try? await AlcoveAPI.postRaw("/api/api-room/new-window", body: ["carry": carry]),
              o["ok"] as? Bool == true else {
            message = "换窗失败：连不上小屋"; return
        }
        onChanged()
        dismiss()
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
                // 0917 任务#2139：换成跟 tmux 同一个 forge 页（长按挑思绪 / 工具、账单、真实用量校准的 token）
                NativeForgeView(provider: "sdk", onForged: {
                    sdkSessionActive = true
                    message = "SDK Forge 已自动切到新 session"
                    Task { await load() }   // 刷出「回上一窗」
                })
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

/// 0925 工作室气泡也用这套长按选字（询问 / 复制整轮），放开成 internal
final class AskSelectableTextView: UITextView, UIGestureRecognizerDelegate {
    var onAsk: ((String) -> Void)?
    /// 1001 她报的「选完字点别的地方，选中的不消失」：点在字框外面 UITextView 自己不收选区。
    /// 「选择文字」打开时在窗口上挂一个不抢点按的轻点识别，点在框外就收掉，再告诉外面退出选字
    var onOutsideTap: (() -> Void)?
    private var outsideTap: UITapGestureRecognizer?

    func watchOutsideTaps(_ on: Bool) {
        if on {
            guard outsideTap == nil, let window else { return }
            let g = UITapGestureRecognizer(target: self, action: #selector(outsideTapped(_:)))
            g.cancelsTouchesInView = false
            g.delegate = self
            window.addGestureRecognizer(g)
            outsideTap = g
        } else if let g = outsideTap {
            g.view?.removeGestureRecognizer(g)
            outsideTap = nil
        }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { watchOutsideTaps(false) }
    }

    @objc private func outsideTapped(_ g: UITapGestureRecognizer) {
        guard !bounds.contains(g.location(in: self)) else { return }
        selectedRange = NSRange(location: 0, length: 0)
        _ = resignFirstResponder()
        watchOutsideTaps(false)
        let done = onOutsideTap
        DispatchQueue.main.async { done?() }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    /// 点在复制 / 询问那排菜单上不算「点别处」（菜单的动作还要读选区）
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var v = touch.view
        while let cur = v {
            let name = NSStringFromClass(type(of: cur))
            if name.contains("Menu") || name.contains("Callout") { return false }
            v = cur.superview
        }
        return true
    }
    var onCopyTurn: (() -> Void)?
    /// 0925 她要的「编辑」：只有她自己的文字气泡才给，长按选字冒出来的那排菜单里跟「询问」挨着
    var onEdit: (() -> Void)?

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
        var children: [UIMenuElement] = [ask, copyTurn]
        if onEdit != nil {
            children.append(UIAction(title: "编辑", image: UIImage(systemName: "pencil")) { [weak self] _ in
                guard let self else { return }
                self.selectedRange = NSRange(location: 0, length: 0)   // 收掉选区再进编辑，菜单不留在屏幕上
                self.onEdit?()
            })
        }
        builder.insertChild(UIMenu(options: .displayInline, children: children),
                            atStartOfMenu: .standardEdit)
    }
}

struct SelectableMessageText: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let color: UIColor
    var maximumNumberOfLines: Int = 0
    var onTruncationChange: ((Bool) -> Void)? = nil
    let onAsk: (String) -> Void
    let onCopyTurn: () -> Void
    /// 0924 Kakao 主题的字体（PostScript 名）：nil = 系统字
    var fontName: String? = nil
    /// 0925 她的气泡才传：长按菜单里多一个「编辑」
    var onEdit: (() -> Void)? = nil
    /// 0925 工作室非 Kakao 的气泡是系统衬线字（New York）；没指定字体时用它
    var serif = false
    /// 1001 聊天页：长按要留给贴表情，平时不让逐字选；点了菜单里的「选择文字」才打开（并直接全选）
    var selectionEnabled = true
    var selectAllOnEnable = false
    /// 选区收掉（点了别处）就回到不能选字
    var onSelectionEnded: (() -> Void)? = nil

    final class Coordinator: NSObject, UITextViewDelegate {
        var renderedKey: String?
        var hadSelection = false
        var onSelectionEnded: (() -> Void)?

        func textViewDidChangeSelection(_ textView: UITextView) {
            if textView.selectedRange.length > 0 {
                hadSelection = true
            } else if hadSelection {
                hadSelection = false
                let done = onSelectionEnded
                DispatchQueue.main.async { done?() }
            }
        }
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
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: AskSelectableTextView, context: Context) {
        view.onAsk = onAsk
        view.onCopyTurn = onCopyTurn
        view.onEdit = onEdit
        context.coordinator.onSelectionEnded = onSelectionEnded
        view.onOutsideTap = onSelectionEnded
        if view.isUserInteractionEnabled != selectionEnabled {
            view.isSelectable = selectionEnabled
            view.isUserInteractionEnabled = selectionEnabled
            context.coordinator.hadSelection = false
            if !selectionEnabled {
                view.selectedRange = NSRange(location: 0, length: 0)
                view.watchOutsideTaps(false)
            } else if selectAllOnEnable {
                DispatchQueue.main.async {
                    _ = view.becomeFirstResponder()
                    view.selectedRange = NSRange(location: 0, length: (view.text as NSString).length)
                    view.watchOutsideTaps(true)
                }
            }
        }
        // 后台每 2.5 秒轮询会让 SwiftUI 重跑 updateUIView。正文其实没变，
        // 但重新赋 attributedText 会强制收掉 iOS 的选区和复制菜单。
        // 同一份渲染直接跳过；用户正在选字时，即使主题恰好变化也先让她选完。
        view.textContainer.maximumNumberOfLines = maximumNumberOfLines
        view.textContainer.lineBreakMode = maximumNumberOfLines > 0 ? .byTruncatingTail : .byWordWrapping
        let renderedKey = "\(text)\u{1f}\(fontSize)\u{1f}\(lineSpacing)\u{1f}\(color.description)\u{1f}\(maximumNumberOfLines)\u{1f}\(fontName ?? "")\u{1f}\(serif)"
        guard context.coordinator.renderedKey != renderedKey else { return }
        guard view.selectedRange.length == 0 else { return }
        let source = alcoveMarkdown(text)
        let rendered = NSMutableAttributedString(attributedString: NSAttributedString(source))
        let all = NSRange(location: 0, length: rendered.length)
        rendered.addAttribute(.foregroundColor, value: color, range: all)
        let systemFont = UIFont.systemFont(ofSize: fontSize)
        let plainFont = serif
            ? (systemFont.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: fontSize) } ?? systemFont)
            : systemFont
        let baseFont = fontName.flatMap { UIFont(name: $0, size: fontSize) } ?? plainFont
        rendered.enumerateAttribute(.font, in: all) { value, range, _ in
            let old = value as? UIFont
            let traits = old?.fontDescriptor.symbolicTraits ?? []
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
            rendered.addAttribute(.font, value: UIFont(descriptor: descriptor ?? baseFont.fontDescriptor,
                                                       size: fontSize), range: range)
        }
        if rendered.length > 0 && rendered.attribute(.font, at: 0, effectiveRange: nil) == nil {
            rendered.addAttribute(.font, value: baseFont, range: all)
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
    /// 0925：思绪 / 工具这些弹出面板用这套——Kakao 下跟全屋白天 / 黑夜开关走，别的主题就是聊天主题本身
    private var sheetTheme: AlcoveTheme { theme.isKakao ? .kakaoSheet(dark: AlcoveAppearance.isDark) : theme }
    /// 1002：聊天里的卡片（选择卡、页面卡、券卡……）Kakao 下一律用信息主题那套——深浅只认全屋按钮，
    /// 不借主题包的字色（豹纹黑包的白字配卡片浅底，整张选择卡白字白底看不见）。输入框 composerTheme 是同一个做法
    private var cardTheme: AlcoveTheme {
        theme.isKakao ? .named(AlcoveAppearance.isDark ? "imessage-dark" : "imessage") : theme
    }
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
    // 0924 她要的「重来」：只有他最后一轮的消息才传这个；按了撤这一轮、claude 回退到她上一句之前重答
    var onReroll: (() -> Void)? = nil
    // 0925 她要的「编辑」（官方 App 那样）：她的文字气泡才传 onEdit；编辑中这条气泡原地变成输入框，下面取消 / 发送
    var onEdit: (() -> Void)? = nil
    var isEditing: Bool = false
    var editDraft: Binding<String>? = nil
    var editBusy: Bool = false
    var onEditCancel: (() -> Void)? = nil
    var onEditSend: (() -> Void)? = nil
    // 0924 Kakao：这条是不是一串的头（露头像 / 名字 / 01 图）；她最后一条没被他读过就挂个小「1」
    var kakaoHead: Bool = true
    // 0924 晚：这条用不用带图案的 01 图——一串里第一条真画气泡的才用（kakaoHead 管头像，这个管气泡图）
    var kakaoFirstBubble: Bool = true
    var kakaoUnread: Bool = false
    var onPlayMusic: ((MusicSong) -> Void)? = nil
    var onContentChange: (() -> Void)? = nil
    /// 1001 贴表情：长按文字气泡的回调（带气泡在屏幕上的位置）；这条是不是正浮起来；是不是点了「选择文字」
    var onReactLongPress: ((ReactTarget) -> Void)? = nil
    var reactLifted = false
    var textSelectable = false
    var onExitTextSelection: (() -> Void)? = nil
    @State private var reactPressing = false
    @State private var treehouseMetaHeight: CGFloat = 24
    @State private var showThinking = false
    @State private var showActivity = false   // 0730 过程记录展开
    // 0820 按时间线摆之后，点开的是「这一段」，不是整轮那一坨
    @State private var openedThink: String? = nil
    @State private var openedTools: [ActivityItem]? = nil
    // 0822 iMessage 主题：思绪+脚印合成一条过程线，默认只露一个点
    @State private var processOpen = false
    @State private var showTranscript = false   // 0822 语音条默认不露文字，长按「转文字」才展开
    @FocusState private var editFocused: Bool
    @AppStorage("imsgShowProcess") private var showProcessDots = true
    // 0924 她报的「气泡间距有的贴在一起」：一条消息里图 / 语音 / 正文 / 链接卡之间原来是 0，
    // 脚印那行又是另一个数。现在一律用设置里那个「气泡间距」，跟列表里气泡和气泡之间同一个数。
    @AppStorage("chatBubbleGap") private var chatBubbleGap = 6.0
    @AppStorage(KakaoPackStore.showAvatarKey) private var kakaoShowAvatar = true   // 0924 她要的：Kakao 下他的消息带不带头像
    @State private var openedToolDetail: ActivityItem? = nil
    @State private var showRecall = false
    @State private var showPulse = false

    private var isUser: Bool { msg.role == "user" }
    private var timestampTextInset: CGFloat {
        if theme.isPaper && !isUser { return 0 }
        // 0907 她要的：时间戳一律缩进到同一条竖线上，不管这条是文字、表情还是图。
        // 原来只有「有正文的文字气泡」才缩进 —— 删到只剩一张表情时时间戳顶到最左边，
        // 跟上一条的时间戳对不齐。
        return 12
    }
    /// 0924 晚她抓的：Kakao 下时间贴在气泡旁边，小按钮又跟着思绪开关藏了，这一行里一个东西都没有，
    /// 却还占着一截高度（空 HStack + 上边距），卡片和下一条中间空一大块。改成里面真有东西才画这一行；
    /// 别的主题里时间本来就在这一行，行为不变。条件跟下面那一行里每个元素的条件一一对上。

    /// 1009 晚 她要的：树屋下这一行搬进气泡里（壁纸太杂，放外面看不清）；别的主题还挂在气泡下面。
    /// 心率在树屋里去掉——顶栏已经有一颗活的了。

    /// 树屋把这一行搬进了气泡，颜色得跟气泡底走：她的墨色泡用浅字，他的纸白泡用墨字。
    private var metaTint: Color {
        guard theme.isTreehouse else { return theme.timestamp }
        // 1009 #3511 她：「树屋的时间戳颜色直接跟着双方正文颜色的百分之80走 不单独调节了」
        return ((isUser ? theme.textUser : theme.textAI) ?? theme.text).opacity(0.8)
    }

    @ViewBuilder private var metaRow: some View {
        HStack(spacing: theme.isKakao ? 16 : (theme.isMessages ? 12 : (theme.isPaper && !isUser ? 14 : 4))) {
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
                        if showTime && !theme.isKakao {   // Kakao 的时间贴在气泡旁边（kakaoSideMeta）
                            Text(Self.hm.string(from: msg.date))
                                .font(.system(size: 10, design: .serif))
                                .foregroundColor(metaTint)
                        }
                        if theme.isMessages, !theme.isKakao, isUser, !msg.pending {
                            // 0822 她定的：tg 那种两个勾，发出去就亮，只是个装饰
                            HStack(spacing: -5) {
                                Image(systemName: "checkmark")
                                Image(systemName: "checkmark")
                            }
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(theme.isTreehouse ? MessagesPalette.thCurrent(.readTick, dark: theme.isDark) : metaTint)
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
                                    .foregroundColor(metaTint.opacity(
                                        paragraphSelectionMode ? 1 : 0.72))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("选择正文段落")
                        }
                        // 0924 她要的「重来」（像官方 app 那种重 roll）：只在他最后一轮的尾巴上出现
                        // 0924 她要的：重来箭头跟过程点一个开关，思绪藏了它也藏
                        if showTime, !isUser, let onReroll = onReroll, !(theme.isMessages && !showProcessDots) {
                            Button { onReroll() } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(metaTint.opacity(0.72))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("重来")
                        }
                        // 0822 她定的：信息主题下心率跟过程线（思绪/脚印/记忆）一个开关，关了一起藏
                        // 1009 晚 她：「时间戳那一行的心率可以删掉，因为现在顶栏有你的心率」
                        if showTime, !isUser, !theme.isTreehouse, let bpm = msg.heartRate,
                           !(theme.isMessages && !showProcessDots) {
                            Button { showPulse = true } label: {
                                HStack(spacing: 3) {
                                    // 0925 她要的：Kakao 下爱心实心、不带颜色（跟旁边清单 / 重来一个色），去掉「bpm」只留数字
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(theme.isKakao ? metaTint.opacity(0.72)
                                                         : Color(red: 0.78, green: 0.43, blue: 0.50).opacity(0.82))
                                    Text(theme.isKakao ? "\(bpm)" : "\(bpm) bpm")
                                        .font(.system(size: 10, design: .serif))
                                        .foregroundColor(metaTint.opacity(0.72))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        if showTime, !isUser, let usage = msg.apiUsage {
                            apiUsageLine(usage)
                        }
        }
        .padding(.leading, theme.isTreehouse ? 0 : (isUser ? 0 : (theme.isKakao ? kakaoTextLeading() : timestampTextInset)))
        .padding(.trailing, theme.isTreehouse ? 0 : (isUser ? timestampTextInset : 0))
        .padding(.top, theme.isTreehouse ? 0 : rowPartGap)
    }

    private var shouldShowMetaRow: Bool {
        guard msg.msgType != "choice_answer" else { return false }
        let dotsOK = !(theme.isMessages && !showProcessDots)
        // 非 Kakao：跟原来一样（pending / 睡着 / 有时间就画）；Kakao：只有他那排小按钮真露出来才画
        return msg.pending
            || msg.asleepAtSend
            || (showTime && (!theme.isKakao || (!isUser && dotsOK)))
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
    /// 塔罗卡那一行：整行居中（两侧留白都不吃）。0929 她要檐下 / 不忘 / Inside 三张小卡也在屏幕正中，一并走这条
    private var isTarotRow: Bool {
        msg.tarotCard != nil || msg.tarotOffer != nil
            || msg.insideText != nil || msg.pondCard != nil || msg.memoryCard != nil || msg.reminderCard != nil
    }

    var body: some View {
        HStack(alignment: (theme.isKakao && !isUser) ? .top : .bottom, spacing: 0) {
            // 0903 她要的：塔罗卡不管谁发的都在屏幕正中间，两侧留白都不吃
            if isUser { Spacer(minLength: isTarotRow ? 0 : 48) }
            // 0924 Kakao：他的消息左边一个圆角方头像，一串只有第一条露脸
            if theme.isKakao && !isUser && !isTarotRow && kakaoShowAvatar {
                // 0924 她定的：不带名字，只有头像
                // 0924 晚她要的：跟工作室一样头像后面留 16，左挪 14 之后猫图案不压头像（右侧少留 8 补回来，最宽不变）
                // 0924 晚：头像不占排版高度（原来看不见的头像位也撑 40 高，短气泡下面多出空），往上挪 6 代替气泡往下挪 6，
                // 气泡跟头像的相对位置不变，气泡之间的空隙不再被撑大
                KakaoAvatarView(visible: kakaoHead)
                    .frame(width: 40, height: 0, alignment: .top)
                    .offset(y: -Self.kakaoBubbleShiftDown)
                    .padding(.trailing, 16)
            }
            if kakaoCardIndent > 0 {
                // 0925 她定的：不管有没有头像，他的截图 / 卡片左边跟思绪那颗圆点对齐，思绪不动。
                // 整列往右让开这么多，气泡自己和思绪 / 小按钮再往回挪同样的量，位置不变。
                Color.clear.frame(width: kakaoCardIndent, height: 0)
            }
            VStack(alignment: isUser ? .trailing : .leading,
                   spacing: 0) {
                // 0820：有时间线就照发生顺序摆 —— 想一段出一个面板，
                // 中间干的活收成一行。没时间线（老消息）走原来那套。
                if theme.isMessages && !isUser {
                    messagesProcessBlock
                        // 1001 Kakao：看得见的圆点对齐气泡边框（块里自带 4 的左距、圆点在按钮框里还往里 7.5，都扣掉）
                        .padding(.leading, theme.isKakao ? kakaoTextLeading() - 4 - Self.kakaoDotInset : 0)
                } else if !isUser && !turnBlocks.isEmpty {
                    ForEach(turnBlocks) { blk in
                        switch blk {
                        case .think(let text, let i):
                            thinkPanelRow(text, index: i, showRecall: blk.id == firstThinkBlockID)
                                .padding(.bottom, rowPartGap)
                        case .tools(let items, let i):
                            toolRow(items, index: i)
                                .padding(.bottom, rowPartGap)
                        }
                    }
                } else {
                    if let think = visibleChatThought {
                        thinkingBlock(think).padding(.bottom, rowPartGap)
                    } else if recall != nil {
                        recallBadge.padding(.bottom, rowPartGap) // 没有思绪行时角标单独站一行，和 PWA 一致
                    }
                    if !isUser && trailWorthShowing {
                        trailBlock.padding(.bottom, rowPartGap)
                    }
                }
                if !theme.isMessages && !isUser { nativeThinkingButton.padding(.bottom, rowPartGap) }
                if let paperDate = msg.morningPaperDate {
                    MorningPaperMessageCard(date: paperDate, theme: cardTheme, messageID: msg.id)
                } else if let inside = msg.insideText {
                    InsideMessageCard(text: inside, date: msg.date, theme: cardTheme, messageID: msg.id)
                        .frame(maxWidth: .infinity)   // 0929 她要的：整行居中
                } else if let ghost = msg.ghostCard {
                    GhostActivityMessageCard(card: ghost, theme: cardTheme)
                } else if let play = msg.playCard {
                    PlayPageMessageCard(card: play, theme: cardTheme)
                } else if let forward = msg.favoriteForward {
                    FavoriteForwardMessageCard(card: forward)
                } else if let reading = msg.readingCard {
                    ReadingShareMessageCard(card: reading, theme: cardTheme)
                } else if let tarot = msg.tarotCard {
                    TarotMessageCard(card: tarot, theme: cardTheme)
                        .frame(maxWidth: .infinity)   // 整行居中
                } else if let offer = msg.tarotOffer {
                    TarotOfferMessageCard(card: offer, theme: cardTheme, onContentChange: onContentChange)
                        .frame(maxWidth: .infinity)
                } else if msg.msgType == "tarot_answer" {
                    // 她抽满了他出的题：服务端落的那条（全文给他读），聊天页只画一句小条子，牌在上面那张卡里
                    ChoiceAnswerStrip(text: "🔮 抽好了，牌在上面那张卡里", theme: theme)
                } else if let work = msg.workCard {
                    WorkDeliveryMessageCard(card: work, theme: cardTheme)
                } else if let album = msg.albumSavedCard {
                    AlbumSavedMessageCard(batch: album, theme: cardTheme)
                } else if let pond = msg.pondCard {
                    PondChatMessageCard(card: pond)
                        .frame(maxWidth: .infinity)
                } else if let mem = msg.memoryCard {
                    MemoryChatMessageCard(card: mem)
                        .frame(maxWidth: .infinity)
                } else if let rem = msg.reminderCard {
                    ReminderMessageCard(card: rem)      // 1002 日程提醒到点
                        .frame(maxWidth: .infinity)
                } else if let loc = msg.locationCard {
                    LocationMessageCard(card: loc, isUser: isUser)   // 1008 位置卡：iMessage 那样的圆角地图卡，跟着说话的人那一边
                } else if let buy = msg.buyCard {
                    // 0907 二期审批卡：她要它「跟他的气泡列在一堆」，所以不居中，走左侧
                    BuyApprovalMessageCard(card: buy, theme: cardTheme)
                } else if let paid = msg.paidCard {
                    // 0909 付款单：跟审批卡一样列在他的气泡那一堆里，不居中
                    PaidReceiptMessageCard(card: paid, theme: cardTheme)
                } else if let ticket = msg.ticketCard {
                    // 0909 券卡：她点确认才核销，跟审批卡一样列在他的气泡那堆里
                    TicketUseMessageCard(card: ticket, theme: cardTheme)
                } else if let choice = msg.choiceCard {
                    ChoiceQuestionMessageCard(card: choice, theme: cardTheme)
                } else if msg.msgType == "choice_answer" {
                    ChoiceAnswerStrip(text: msg.displayText, theme: theme)
                } else if let letter = msg.letterCard {
                    LetterMessageCard(card: letter, theme: cardTheme)
                        .frame(maxWidth: .infinity)   // 信封也走正中间，跟旅行卡一个待遇
                } else if let journey = msg.journeyCard {
                    JourneyMessageCard(ref: journey, theme: cardTheme)
                        .frame(maxWidth: .infinity)   // 她要卡片在聊天页正中间
                } else if let call = msg.callSummary {
                    // 0831 任务#1195：打完电话聊天页只留这一条，点开展开这一通的记录。
                    // 左右不用这里判——服务端已经把 role 写成打电话那个人了
                    //（她打的=user 在右，他打的=assistant 在左），拒绝也照这条走。
                    CallSummaryBubble(info: call, text: msg.displayText, theme: cardTheme)   // 1003：Kakao 黑夜白字白底，跟卡片一样走 cardTheme
                } else if msg.isSticker {
                    // 0928 她抓的：一串最后一条是表情时 Kakao 的时间没了——时间贴在气泡旁边（kakaoSideMeta），
                    // 表情原来不挂。照语音条那样两边挂上
                    // 1002 她要的：表情包也能长按贴表情（原来她定过不行），小片挂在表情包下面，跟图一样
                    VStack(alignment: isUser ? .trailing : .leading, spacing: 0) {
                        HStack(alignment: .bottom, spacing: 0) {
                            if theme.isKakao && isUser {
                                kakaoSideMeta.padding(.trailing, 5).fixedSize().frame(width: 0, alignment: .trailing)
                            }
                            reactable(stickerBody, kind: .image, urls: stickerSaveURLs)
                            if theme.isKakao && !isUser {
                                kakaoSideMeta.padding(.leading, 5).fixedSize().frame(width: 0, alignment: .leading)
                            }
                        }
                        // 1002 她要的：Kakao 下她的表情包右边对齐看得见的粉框（跟图片一样扣 body_right），不对齐框外的小人图案
                        .padding(.trailing, kakaoUserPhotoInset)
                        if !msg.reactions.isEmpty { mediaChips(inset: 8 + kakaoUserPhotoInset) }
                    }
                } else {
                  VStack(alignment: isUser ? .trailing : .leading, spacing: CGFloat(chatBubbleGap)) {
                    photoBlock
                        .padding(.trailing, kakaoUserPhotoInset)
                    if hasPhotoBlock && !showsTextBubble && !msg.isAudio && !msg.reactions.isEmpty {
                        mediaChips(inset: 8 + kakaoUserPhotoInset)
                    }
                    if msg.isAudio, let raw = msg.attachmentUrl {
                      // 0927 她要的：Kakao 的时间是贴在气泡旁边的（kakaoSideMeta），原来只有正文气泡挂，
                      // 这一串最后一条是语音（比如她把后面那条字删了）时间就没了。语音条两边照正文气泡一样挂
                      HStack(alignment: .bottom, spacing: 0) {
                        if theme.isKakao && isUser {
                            kakaoSideMeta.padding(.trailing, 5).fixedSize().frame(width: 0, alignment: .trailing)
                        }
                        // 0822 她要的：一开始只有语音条，长按才「转文字」或「收藏」
                        // 0902 她给的参考图：转文字收在同一条气泡里，点右边的小箭头展开
                        reactable(AudioBubble(url: AlcoveAPI.attachmentURL(raw), isUser: isUser, theme: theme,
                                    fontSize: CGFloat(fontSize),
                                    hasTranscript: !msg.audioTranscript.isEmpty,
                                    transcript: msg.audioTranscript,
                                    transcriptShown: showTranscript,
                                    onToggleTranscript: {
                                        withAnimation(.easeInOut(duration: 0.18)) { showTranscript.toggle() }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onContentChange?() }
                                    },
                                    onFavorite: audioNativeFavorite,
                                    translation: msg.audioZh ?? "",
                                    onContentChange: { onContentChange?() }), kind: .voice)
                        if theme.isKakao && !isUser {
                            kakaoSideMeta.padding(.leading, 5).fixedSize().frame(width: 0, alignment: .leading)
                        }
                      }
                            // 0927 她要的「语音跟正常正文气泡对齐」：Kakao 下语音条套的也是包里的气泡图（带小人），
                            // 可它跟截图 / 卡片一起让开了 kakaoCardIndent，比正文气泡往右缩一截。照正文气泡（bubble）抵回来
                            .padding(.leading, (theme.isKakao && !isUser)
                                     ? (kakaoShowAvatar ? -Self.kakaoBubbleShiftLeft : 0) - kakaoCardIndent : 0)
                        if !msg.reactions.isEmpty { mediaChips(inset: reactChipInset) }
                    }
                    if msg.isDocument, let raw = msg.attachmentUrl {
                        DocumentAttachmentCard(
                            url: AlcoveAPI.attachmentURL(raw),
                            filename: msg.attachmentFilename ?? "文件",
                            theme: cardTheme
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
                        } else if isEditing, let editDraft = editDraft {
                            editBox(editDraft)
                        } else {
                            reactBubble
                        }
                    }
                    // 正文里有链接：气泡下面长一张小卡片（只有链接的话就只留卡）
                    if let link = msg.firstLinkURL, msg.musicCard == nil, !msg.isSticker {
                        LinkPreviewCard(url: link, theme: cardTheme, isUser: isUser)
                    }
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
                        .padding(.leading, theme.isKakao ? kakaoTextLeading() : 3)
                        .padding(.top, CGFloat(chatBubbleGap))
                }
                // 1009 晚 她：「时间戳那一行想加到每个人最后一条气泡里面，现在壁纸比较杂不放气泡里看不清」
                // 树屋下这一行搬进气泡（见 bubbleCore），外面不再画。
                if shouldShowMetaRow && !(theme.isTreehouse && showsTextBubble) {
                    metaRow
                }
            }
            if !isUser {
                // 晨报和旅行卡片是整行居中的东西，不吃我这边气泡的右侧留白
                Spacer(minLength: (msg.morningPaperDate != nil || msg.journeyCard != nil || isTarotRow) ? 0
                       : (msg.choiceCard != nil ? 34 : (theme.isPaper ? 15
                          : ((theme.isKakao && kakaoShowAvatar) ? 40 : 48))))
            }
        }
        .padding(.leading, theme.isPaper && !isUser && msg.morningPaperDate == nil && msg.journeyCard == nil && !isTarotRow ? 12 : 0)
        // 0924 晚她定的：所有主题气泡之间看得见的空隙 = 设置里的「气泡间距」，行上下不再各垫 2 / 5。
        // （0922 那 3 点差的源头是他每条头上那个空的过程点占位行，0924 下午 7651dba 已经不画了。）
        // 只剩非 Kakao 主题一串末尾（底下有时间那行）照旧留 12；Kakao 的时间在气泡旁边，不留。
        .padding(.bottom, (showTime && !theme.isKakao) ? 12 : 0)
        .sheet(item: Binding(get: { openedThink.map { OneThought(text: $0) } },
                             set: { openedThink = $0?.text })) { one in
            NavigationStack {
                ScrollView {
                    ObliqueText(text: one.text, size: 15, color: UIColor(sheetTheme.text), lineSpacing: 7)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22).padding(.top, 6).padding(.bottom, 30)
                }
                .background(sheetTheme.fyCardSub.ignoresSafeArea())
                .navigationTitle("Thought process")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { openedThink = nil } } }
            }
            .modifier(HouseColorScheme())
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(sheetTheme.fyCardSub)
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
                                    .foregroundColor(sheetTheme.fyAccent)
                                    .frame(width: 18).padding(.top, 2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.toolName == "Bash" ? "Ran" : "Used")
                                        .font(.system(size: 13.5, weight: .medium))
                                        .foregroundColor(sheetTheme.text)
                                    Text(item.desc.isEmpty ? item.content : item.desc)
                                            .font(.system(size: 12))
                                            .foregroundColor(sheetTheme.textDim)
                                            .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(sheetTheme.textDim)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 9)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 22).padding(.bottom, 30)
                }
                .background(sheetTheme.fyCardSub.ignoresSafeArea())
                .navigationTitle(trailLabel(one.items))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { openedTools = nil } } }
            }
            .sheet(item: $openedToolDetail) { item in
                commandDetailPanel(item)
                    .modifier(HouseColorScheme())
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(sheetTheme.fyCardSub)
            }
            .modifier(HouseColorScheme())
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(sheetTheme.fyCardSub)
        }
        .sheet(isPresented: $showThinking) {
            paperThinkingPanel
                .modifier(HouseColorScheme())
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(sheetTheme.fyCardSub)
        }
        .fullScreenCover(isPresented: $showPulse) {
            // 0927 Pulse 换纸页后自己带返回键（左上角，点了关掉这一层），右上角是「脉 / 狼身」，原来的 × 会压在上面
            NativePulseView()
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

    /// 0924 Kakao：时间（和未读的小「1」）贴在气泡外侧的下角，不在气泡底下另起一行
    /// 0924 她要的：头像显示时，他的气泡整块往左下挪一点（头像、名字不动，气泡右边到屏幕的距离不动，所以能更宽一点）
    static let kakaoBubbleShiftLeft: CGFloat = 14
    static let kakaoBubbleShiftDown: CGFloat = 6

    /// 1001 贴表情：气泡＋底下贴的小片。按住先缩一点，触发那一下弹起来（跟 iOS 长按一样）
    private var reactBubble: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 0) {
            bubble
                .scaleEffect(reactPressing ? ReactFeel.pressScale : 1, anchor: isUser ? .trailing : .leading)
                .animation(reactPressing ? ReactFeel.pressAnimation : ReactFeel.releaseAnimation, value: reactPressing)
                // 浮起来的是整屏那层上另画的一份，这份藏起来（收回时那份落回原位再换回这份）
                .opacity(reactLifted ? 0 : 1)
                .overlay(reactPressLayer)
            if !msg.reactions.isEmpty {
                ReactionChips(reactions: msg.reactions, theme: theme)
                    .padding(.top, -5)
                    .padding(isUser ? .trailing : .leading, reactChipInset + reactEdgeInset)
                    .transition(.scale(scale: 0.5, anchor: isUser ? .topTrailing : .topLeading).combined(with: .opacity))
            }
        }
    }

    /// 图 / 语音 / 表情包也能长按贴（表情包 1002 她改口要了）。图片和语音条里有自己的点按，所以长按挂在它们本身上，不盖一层
    @ViewBuilder
    private func reactable<V: View>(_ v: V, kind: ReactTarget.Kind, urls: [URL] = []) -> some View {
        if let cb = onReactLongPress {
            let a: UnitPoint = isUser ? .trailing : .leading
            v.modifier(ReactPressable(lifted: reactLifted, anchor: a) { f in
                cb(ReactTarget(msg: msg, frame: f, kind: kind, urls: urls, ghost: AnyView(v), anchor: a))
            })
        } else {
            v
        }
    }

    /// 有正文气泡的，小片挂在正文气泡下；没有的（纯图、语音）挂在图 / 语音条下
    private var showsTextBubble: Bool {
        msg.musicCard == nil && !msg.displayText.isEmpty && !msg.isSticker && !msg.isBareLink && !msg.isAudio
    }

    /// 表情包长按菜单的「保存到相册」存的就是这张表情
    private var stickerSaveURLs: [URL] {
        guard let stk = sticker else { return [] }
        return [AlcoveAPI.stickerURL(stk.url)]
    }

    private var photoSaveURLs: [URL] {
        if !photoURLs.isEmpty { return photoURLs }
        if let raw = msg.attachmentUrl, msg.isImage { return [AlcoveAPI.attachmentURL(raw)] }
        return []
    }

    private func mediaChips(inset: CGFloat) -> some View {
        ReactionChips(reactions: msg.reactions, theme: theme)
            .padding(.top, -5)
            .padding(isUser ? .trailing : .leading, inset)
            .transition(.scale(scale: 0.5, anchor: isUser ? .topTrailing : .topLeading).combined(with: .opacity))
    }

    /// 语音条长按走贴表情那层，原来系统那个「收藏」菜单就不挂了（收藏挪进那层的菜单里）
    private var audioNativeFavorite: (() -> Void)? { onReactLongPress == nil ? onFavorite : nil }

    /// Kakao 他那边气泡整块往左挪过（头像让位），小片跟着看得见的气泡左边走
    private var reactChipInset: CGFloat {
        if isUser || !theme.isKakao { return 8 }
        return kakaoTextLeading() + 6   // 1001 基准从「边往里 4」改成边框本身，小片位置照旧（边往里 6）
    }

    /// 1001 她要的：Kakao 下她那边（没头像）图片右边对齐看得见的粉框——气泡图右边带透明边 / 图案，按 02 图（不带小人那张）的 body_right 让开
    private var kakaoUserPhotoInset: CGFloat {
        guard theme.isKakao, isUser else { return 0 }
        let pack = KakaoPackStore.shared.current
        return CGFloat((pack?.bubbles["send2"] ?? pack?.bubbles["send1"])?.body_right ?? 0)
    }

    /// 1001 她要的：气泡上面那行引用（↪ …）对齐框里的字，不对齐框边。
    /// 信息主题：字离色块边 14（bubbleCore 里那个 padding）；Kakao 她那边：包里写的字离右边多少
    private var quoteTextInset: CGFloat {
        if theme.isMessages && !theme.isKakao { return 14 }
        guard theme.isKakao, isUser else { return 0 }
        let pack = KakaoPackStore.shared.current
        let spec = pack?.bubbles[kakaoFirstBubble ? "send1" : "send2"] ?? pack?.bubbles["send1"]
        return spec?.textInsets.trailing ?? 0
    }

    /// 1001 她抓的「小片跑到小鼯鼠底下」：Kakao 她那边的气泡图右边常带图案，框的右边不是看得见的气泡右边。
    /// 按后端量的 body_right 让开（文字气泡的小片、表情条、菜单都用）；别的主题、他那边是 0
    private var reactEdgeInset: CGFloat {
        guard theme.isKakao, isUser else { return 0 }
        let pack = KakaoPackStore.shared.current
        let spec = pack?.bubbles[kakaoFirstBubble ? "send1" : "send2"] ?? pack?.bubbles["send1"]
        return CGFloat(spec?.body_right ?? 0)
    }

    @ViewBuilder private var reactPressLayer: some View {
        if let onReactLongPress, !textSelectable {
            GeometryReader { geo in
                Color.clear
                    // 时间行已移入树屋气泡：长按透明层只覆盖正文，不拦底部按钮。
                    .frame(height: max(0, geo.size.height -
                        (theme.isTreehouse && shouldShowMetaRow ? treehouseMetaHeight + 12 : 0)))
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .onLongPressGesture(minimumDuration: ReactFeel.hold, maximumDistance: 12, perform: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        reactPressing = false
                        let a: UnitPoint = isUser ? .trailing : .leading
                        onReactLongPress(ReactTarget(msg: msg, frame: geo.frame(in: .global),
                                                     ghost: AnyView(bubble), anchor: a, edgeInset: reactEdgeInset))
                    }, onPressingChanged: { reactPressing = $0 })
            }
        }
    }

    private var bubble: some View {
        Group {
            if theme.isKakao {
                // 0925 她觉得他的气泡比工作室窄一点：时间原来跟气泡并排、中间固定垫 5，不显示时间也占着那 5，
                // 带时间的那条还要再让出时间那么宽。改成跟工作室一样：时间套 0 宽的框往外溢，不占气泡宽度
                HStack(alignment: .bottom, spacing: 0) {
                    if isUser {
                        kakaoSideMeta.padding(.trailing, 5).fixedSize().frame(width: 0, alignment: .trailing)
                    }
                    bubbleCore
                    if !isUser {
                        kakaoSideMeta.padding(.leading, 5).fixedSize().frame(width: 0, alignment: .leading)
                    }
                }
                .padding(.leading, ((!isUser && kakaoShowAvatar) ? -Self.kakaoBubbleShiftLeft : 0) - kakaoCardIndent)
            } else {
                bubbleCore
            }
        }
    }

    /// 0924 她定的：Kakao 下思绪块和气泡底下那排小图标，左边在「看得见的气泡左边」往里缩 4（头像开关都一样）。
    /// 0924 晚她抓的「小按钮在气泡外面」：气泡图四周有透明边、有的左边带小人，图片左边不是看得见的左边。
    /// 看得见的左边由后端拆包时量好（body_left，按这条用的 01 / 02 图取）；老缓存没有这个数就按 2 算（等于原来的 6）。
    /// 0926 她给的样子：↑ 32.2K tokens (32.1K cached) ↓ 180 tokens，后面再跟缓存命中率（秒数她说不要）
    private func apiUsageLine(_ u: ChatMessage.ApiUsage) -> some View {
        func k(_ n: Int) -> String { n < 1000 ? "\(n)" : String(format: "%.1fK", Double(n) / 1000) }
        var t = Text("")
        if let i = u.input, i > 0 {
            t = t + Text(Image(systemName: "arrow.up.square")) + Text(" \(k(i)) tokens")
                + (u.cached > 0 ? Text(" (\(k(u.cached)) cached)") : Text(""))
        }
        if let o = u.output, o > 0 {
            t = t + Text("  ") + Text(Image(systemName: "arrow.down.square")) + Text(" \(k(o)) tokens")
        }
        // 0926 她要「缓存」两个字换成简约图标：闪电＝命中率；中转站没报就一道横线
        t = t + Text("  ") + Text(Image(systemName: "bolt")) + Text(u.hit.map { " \($0)%" } ?? " –")
        return t
            .font(.system(size: 10, design: .serif))
            .foregroundColor(theme.timestamp.opacity(0.72))
            .lineLimit(1)                // 0926 她说两行不好看：只许一行，挤不下就整行等比缩小
            .minimumScaleFactor(0.7)
    }

    private func kakaoTextLeading() -> CGFloat {
        kakaoThoughtBase - kakaoCardIndent   // 整列让开过 kakaoCardIndent，这里扣回来
    }

    /// 1001 她定的：他那边脚印、思绪那行、小按钮那排、截图 / 卡片，左边一律对齐看得见的气泡边框——
    /// 是气泡本体的边，不是站在左边的小人 / 图案（body_edge，后端量的；老缓存没有退 body_left，再没有按 2）。
    /// 从头像后面那一列的左边算，有头像再减左挪的 14。（0924 原来是 body_left 往里 4）
    private var kakaoThoughtBase: CGFloat {
        let shift = kakaoShowAvatar ? Self.kakaoBubbleShiftLeft : 0
        let pack = KakaoPackStore.shared.current
        let spec = pack?.bubbles[kakaoFirstBubble ? "recv1" : "recv2"] ?? pack?.bubbles["recv1"]
        return CGFloat(spec?.body_edge ?? spec?.body_left ?? 2) - shift
    }

    /// 过程点那颗圆点 7 宽、在 22 宽的按钮框里居中，看得见的左边比框往里 7.5
    static let kakaoDotInset: CGFloat = 7.5

    /// 0925 起他的截图 / 卡片 / 语音左边跟思绪那颗圆点对齐；1001 圆点挪到气泡边框上，卡片跟着对齐边框。
    /// 她的消息、整行居中的东西（晨报、旅行卡、塔罗）是 0；算出来是负的（极少数包）就按 0，卡片贴列左边
    private var kakaoCardIndent: CGFloat {
        guard theme.isKakao, !isUser, !isTarotRow,
              msg.morningPaperDate == nil, msg.journeyCard == nil else { return 0 }
        return max(0, kakaoThoughtBase)
    }

    private var kakaoSideMeta: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
            if kakaoUnread && isUser {
                Text("1")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(KakaoPackStore.shared.unreadColor)
            }
            if showTime {
                Text(KakaoClock.fmt.string(from: msg.date))
                    .font(.system(size: 10))
                    .foregroundColor(theme.timestamp)
            }
        }
        .padding(.bottom, 2)
    }

    private var bubbleCore: some View {
        return VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            if let quote = msg.quotedSelection, !quote.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text(quote).lineLimit(2)
                }
                .font(.system(size: 12))
                .foregroundColor(theme.thoughtColor)
                .padding(isUser ? .trailing : .leading, quoteTextInset)
            }
            Group {
                if theme.isKakao {
                    // 0924 Kakao：气泡是主题包里的九宫格图，字离四边按包里写的来
                    KakaoBubbleView(isUser: isUser, first: kakaoFirstBubble) { bubbleContents }
                } else if theme.isPaper && !isUser {
                    bubbleContents.padding(.horizontal, 0).padding(.vertical, 2)
                } else if theme.isTreehouse {
                    // 1009 树屋：照她成品——实心，18 圆角、贴边那个角收成 5；他的白泡外面一圈很淡的墨线
                    // 1009 晚 她要的：一串最后那条，时间那一行收进气泡里（左下角，与正文左缘对齐），壁纸太杂放外面看不清。
                    // 顺移是白送的：showTime 由列表现算（isGroupTail 看下一条是不是同一个人），
                    // 她删掉最后一条，下一帧新的尾巴自己长出这一行。
                    // 1009 #3510 她：「我的时间戳是跟我最右边的文字对齐 陈璟跟最左边对齐」
                    VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {   // #3511 时间和正文之间再空一丢丢（3 → 6）
                        bubbleContents
                        if shouldShowMetaRow {
                            metaRow
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                                    treehouseMetaHeight = $0
                                }
                        }
                    }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .modifier(TreehouseBubbleFill(isUser: isUser, fill: isUser ? theme.bubbleUser : theme.bubbleAI, showsCorner: isUser || showTime,
                                                      glass: MessagesPalette.thGlass))
                } else {
                    bubbleContents
                        .padding(.horizontal, 14)
                        .padding(.vertical, theme.isPaper && isUser ? 11 : 10)
                        // 0822 她定的：信息主题不要尾巴（怎么画都像拼上去的），和纸页一样实心大圆角
                        // 1001 她要试的：信息主题换成跟打字框同一种系统玻璃（纸页照旧实心），大小排版一点不动
                        .modifier(MessagesBubbleFill(fill: isUser ? theme.bubbleUser : theme.bubbleAI,
                                                     glass: theme.isMessages && MessagesPalette.glass))
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

    }

    /// 0925「编辑」：她这条气泡原地变成输入框（白 / 深底、主题点缀色描边），下面一排取消 / 发送。
    /// 发送 = 后端先把他退回到这句之前、这句和下面的气泡藏掉，再把改好的字照常发出去。
    private func editBox(_ draft: Binding<String>) -> some View {
        let face = theme.isDark ? Color(red: 28/255, green: 28/255, blue: 30/255) : Color.white
        let ink = theme.isDark ? Color.white : Color.black
        let empty = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .trailing, spacing: 8) {
            TextField("", text: draft, axis: .vertical)
                .focused($editFocused)
                .lineLimit(1...10)
                .font(.system(size: CGFloat(fontSize)))
                .foregroundColor(ink)
                .tint(theme.fyAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minWidth: 200, alignment: .leading)
                .background(face, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(theme.fyAccent, lineWidth: 1.2))
                .disabled(editBusy)
                .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { editFocused = true } }
            HStack(spacing: 10) {
                Button { onEditCancel?() } label: {
                    Text("取消")
                        .foregroundColor(theme.isDark ? Color.white.opacity(0.75) : Color.black.opacity(0.6))
                        .padding(.horizontal, 16).frame(height: 32)
                        .background(face, in: Capsule())
                }
                .disabled(editBusy)
                Button { onEditSend?() } label: {
                    Group {
                        if editBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("发送").fontWeight(.semibold)
                        }
                    }
                    .foregroundColor(theme.textUser ?? (theme.isMessages ? .white : theme.text))
                    .padding(.horizontal, 16).frame(height: 32)
                    .background(theme.bubbleUser, in: Capsule())
                    .opacity(empty ? 0.45 : 1)
                }
                .disabled(editBusy || empty)
            }
            .font(.system(size: 14))
            .buttonStyle(.plain)
        }
    }

    private var bubbleContents: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            // 0921 任务#2505：带 [摇晃]…[/摇晃] 这类标记的正文逐字画、会动；没标记照旧
            if let segs = TextEffects.segments(msg.textWithoutLink) {
                EffectText(
                    segments: segs,
                    fontSize: CGFloat(fontSize),
                    color: isUser ? (theme.textUser ?? (theme.isMessages ? .white : theme.text))
                                  : (msg.asleepAtSend ? theme.textDim : (theme.textAI ?? theme.text)),
                    lineSpacing: theme.isPaper ? 7 : 5,
                    playKey: msg.ts,
                    fontName: KakaoPackStore.shared.fontName   // 0924 她定的：字体全局，哪个主题都吃
                )
            } else {
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
                },
                fontName: KakaoPackStore.shared.fontName,
                onEdit: isUser ? onEdit : nil,
                selectionEnabled: textSelectable || onReactLongPress == nil,
                selectAllOnEnable: textSelectable,
                onSelectionEnded: onExitTextSelection
            )
            }
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
                .modifier(HouseColorScheme())
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(sheetTheme.fyCardSub)
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
                                .foregroundColor(sheetTheme.fyAccent)
                                .frame(width: 18)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.toolName == "Bash" ? "Ran" : "Used")
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundColor(sheetTheme.text)
                                Text(item.desc.isEmpty ? item.content : item.desc)
                                        .font(.system(size: 12))
                                        .foregroundColor(sheetTheme.textDim)
                                        .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(sheetTheme.textDim)
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
            .background(sheetTheme.fyCardSub.ignoresSafeArea())
            .foregroundColor(sheetTheme.text)
            .navigationTitle(trailEntryLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { showActivity = false } } }
        }
        .sheet(item: $openedToolDetail) { item in
            commandDetailPanel(item)
                .modifier(HouseColorScheme())
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(sheetTheme.fyCardSub)
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
                    Group {
                        if it.kind == "thinking" {
                            ObliqueText(text: it.content, size: 11, color: UIColor(theme.textDim.opacity(0.72)))
                        } else {
                            Text(it.content).font(.system(size: 11)).foregroundColor(theme.textDim.opacity(0.9))
                        }
                    }
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
    /// 0914 她定的：气泡跟气泡之间只听设置里那根滑块；零件（过程点、脚印、时间戳）
    /// 跟气泡之间的缝写死。所以外层竖排的 spacing 归零，缝改由各个零件自己带 ——
    /// 一行里只有光气泡时就一点也不多占，两边看起来才一样齐。
    private var rowPartGap: CGFloat { theme.isPaper && !isUser ? 10 : 7 }

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
                    .padding(theme.isTreehouse ? 10 : 0)
                    .background {
                        if theme.isTreehouse {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(TreehouseInk.white)
                                .allowsHitTesting(false)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(.leading, 4)
            .padding(.bottom, rowPartGap)
        } else if showProcessDots,
                  recall != nil || !(msg.nativeThinking ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // 0924 她报的「他的气泡间距跟我的不一样」：这一支原来不管有没有东西都画一个空 HStack
            // 再垫 rowPartGap，他每条消息头上都多出 7 的空白。现在没角标、没原生思考就整块不画。
            HStack(spacing: 14) {
                if recall != nil { recallBadge }
                nativeThinkingButton
            }
            .padding(.bottom, rowPartGap)
        }
    }

    private func processThought(_ text: String) -> some View {
        // 0924 她要的：思绪用宋体斜体（中文也真斜，走 UIKit obliqueness）
        ObliqueText(text: text, size: 12.5, color: UIColor(theme.thoughtColor), lineSpacing: 3)
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
                    ObliqueText(text: visibleChatThought ?? cuteThinkingPlaceholder, size: 15, color: UIColor(sheetTheme.text), lineSpacing: 7)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22).padding(.bottom, 30)
            }
            .background(sheetTheme.fyCardSub.ignoresSafeArea())
            .foregroundColor(sheetTheme.text)
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
            .background(sheetTheme.fyCardSub.ignoresSafeArea())
            .navigationTitle(item.toolName.isEmpty ? "Tool" : item.toolName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { openedToolDetail = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 38, height: 38)
                            .background(sheetTheme.fyCard, in: Circle())
                    }
                }
            }
        }
    }

    private func commandDetailSection(_ title: String, text: String, isError: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isError ? .red : sheetTheme.textDim)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(sheetTheme.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(sheetTheme.fyCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(sheetTheme.textDim.opacity(0.16), lineWidth: 0.7))
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
            if let recall { RecallPop(item: recall).modifier(HouseColorScheme()) }
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

    private var photoBlockCore: some View {
        photoBlockInner.modifier(TreehousePhotoFrame(on: theme.isTreehouse))
    }

    @ViewBuilder
    private var photoBlockInner: some View {
        if !photoURLs.isEmpty {
            OfficialPhotoGridMessageView(urls: photoURLs, messageID: "chat-\(msg.id)",
                                         onOpen: onTapImages, nativeMenu: onReactLongPress == nil)
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
        } else if hasPhotoBlock {
            reactable(photoBlockCore, kind: .image, urls: photoSaveURLs)
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
        .chatPhotoRim()
        .matchedTransitionSource(id: "chat-\(msg.id)", in: photoNamespace)
        .onTapGesture { onTapImages([url], .constant(0)) }
        .contextMenu {
            // 1001：长按改走贴表情那层（「保存到相册」在那层的菜单里）；没接那层时还是系统菜单
            if onReactLongPress == nil {
                Button {
                    Task { await PhotoLibrarySaver.save(url) }
                } label: { Label("保存到相册", systemImage: "square.and.arrow.down") }
            }
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
            .foregroundColor((theme.isMessages && !theme.isKakao) ? .white : theme.text)
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

/// 1004 她要的：塔罗小卡改成像素铁艺蕾丝风。她点头的效果图 /root/workroom/mock/tarot-card/v2/day.jpg、night.jpg（施工图），
/// 花纹原图和生成脚本在同一个目录（gen2.py）。灰颗粒卡底、粉色像素卷草角花＋心形冠饰、实线＋虚线两道边、底下一排小旋花边、
/// 两行像素小字；卡后面伸出半调花枝和碎闪卷草。客观解读不进卡（她：只留关键词），没有「去占星室」按钮。
/// 花枝和冠饰伸出去的部分算进卡自己的高度，不压上下消息（她 1004 点名）。深浅只认全屋黑白开关；牌面颜色仍跟占星室的染色走。
private struct TarotLaceInk {
    let dark: Bool
    var lace: Color { dark ? cardRGB(0xF6B4DC) : cardRGB(0xDE8CC8) }
    var laceSoft: Color { dark ? cardRGB(0x7A5A70) : cardRGB(0xEFC3E2) }
    var lilac: Color { dark ? cardRGB(0x6F6A76) : cardRGB(0xC4B8E8) }
    var lilacInk: Color { dark ? cardRGB(0xC9C2CF) : cardRGB(0x8D7FC0) }
    var laceRow: Color { dark ? cardRGB(0x96909C) : cardRGB(0xC4B8E8) }
    var ink: Color { dark ? cardRGB(0xECE7EC) : cardRGB(0x5C566B) }
    var sub: Color { dark ? cardRGB(0xA59FA8) : cardRGB(0xA49EB2) }
    var tag: Color { dark ? cardRGB(0x3B3A40) : .white }
    var tagInk: Color { dark ? cardRGB(0xF6B4DC) : cardRGB(0xC46AAE) }
    var mat: Color { dark ? cardRGB(0x3B3A40) : .white }
    var spark2: Color { dark ? cardRGB(0xECE7EC) : cardRGB(0x86DCBF) }
    var rose: Color { dark ? cardRGB(0xB97AA2) : cardRGB(0xE8AAD6) }
    var vine: Color { dark ? cardRGB(0xECE7EC) : cardRGB(0xC4B8E8) }
    var glitter: Color { dark ? cardRGB(0xECE7EC) : cardRGB(0xAAA6BA) }
    var grain: String { dark ? "TarotChatGrainNight" : "TarotChatGrainDay" }
}

/// 塔罗卡外框：304 宽，四角卷草（58 格画成 72pt）、顶上冠饰（72 格 × 1.5）、两道边；卡后面三枝花
private struct TarotLaceFramed: ViewModifier {
    let ink: TarotLaceInk

    private var corner: some View {
        CardPixelArt(rows: TarotLacePixels.corner, px: 72.0 / 58, colors: ["o": ink.lace]).allowsHitTesting(false)
    }

    private func tinted(_ name: String, _ color: Color, _ w: CGFloat) -> some View {
        Image(name).renderingMode(.template).resizable().scaledToFit()
            .frame(width: w, height: w).foregroundColor(color).allowsHitTesting(false)
    }

    func body(content: Content) -> some View {
        content
            .foregroundColor(ink.ink)
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 16)
            .frame(width: 304)
            .background(Image(ink.grain).resizable(resizingMode: .tile))
            .overlay(Rectangle().stroke(ink.lace, lineWidth: 1).padding(6.5).allowsHitTesting(false))
            .overlay(Rectangle().stroke(ink.lilac, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).padding(9.5).allowsHitTesting(false))
            .overlay(alignment: .topLeading) { corner }
            .overlay(alignment: .topTrailing) { corner.scaleEffect(x: -1, y: 1) }
            .overlay(alignment: .bottomLeading) { corner.scaleEffect(x: 1, y: -1) }
            .overlay(alignment: .bottomTrailing) { corner.scaleEffect(x: -1, y: -1) }
            .overlay(alignment: .top) {
                CardPixelArt(rows: TarotLacePixels.crest, px: 1.5, colors: ["o": ink.lace]).offset(y: -22).allowsHitTesting(false)
            }
            .background(alignment: .bottomLeading) { tinted("TarotChatRose", ink.rose, 150).rotationEffect(.degrees(-8)).offset(x: -39, y: 61) }
            .background(alignment: .topTrailing) { tinted("TarotChatVine", ink.vine, 118).rotationEffect(.degrees(12)).offset(x: 31, y: -30) }
            .background(alignment: .bottomTrailing) { tinted("TarotChatGlitter", ink.glitter, 130).offset(x: 41, y: -29) }
            .padding(.top, 42).padding(.bottom, 72)   // 冠饰、花枝伸出去的那截留出位置，不压上下消息
    }
}

/// 卡头（像素字牌阵＋时间、谁抽的、问题）和卡尾（小旋花边、两行像素小字、just now）
private enum TarotLaceBits {
    static func meta(spread: String, question: String, ts: String) -> String {
        let name: String
        if question == "每日一牌" {
            name = "DAILY CARD"
        } else {
            switch spread {
            case "one": name = "ONE CARD"
            case "three": name = "THREE CARDS"
            case "week": name = "THIS WEEK"
            case "relation": name = "RELATIONSHIP"
            case "desire": name = "SECRET DESIRE"
            case "yesno": name = "YES OR NO"
            default: name = "TAROT"
            }
        }
        let date = ISO8601DateFormatter.alcove.date(from: ts) ?? ISO8601DateFormatter.alcoveFrac.date(from: ts)
        guard let date else { return "· \(name) ·" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM.dd · HH:mm"
        return "· \(name) · \(f.string(from: date)) ·"
    }

    static func head(meta: String, who: String, question: String, ink: TarotLaceInk) -> some View {
        VStack(spacing: 0) {
            Text(meta).font(DiaryFonts.pixel(9)).tracking(1.3).foregroundColor(ink.lilacInk)
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.top, 22)
            Text(who).font(.system(size: 11)).foregroundColor(ink.sub).padding(.top, 4)
            if !question.isEmpty {
                Text("「\(question)」")
                    .font(.system(size: 13.5, weight: .medium, design: .serif)).lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4).padding(.top, 9)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 13)
    }

    static func foot(ink: TarotLaceInk) -> some View {
        VStack(spacing: 0) {
            TarotLaceRow(color: ink.laceRow).frame(height: 12).padding(.horizontal, -4)
                .padding(.top, 14).padding(.bottom, 6)
            Text("A CARD DRAWN IN THE ALCOVE\nPLEASE HANDLE GENTLY · THANK YOU")
                .font(DiaryFonts.pixel(7.5)).tracking(0.9).lineSpacing(2.5)
                .multilineTextAlignment(.center).foregroundColor(ink.sub)
            HStack {
                Text("just now").font(DiaryFonts.script(14)).foregroundColor(ink.lace)
                Spacer()
            }
            .padding(.leading, 30).padding(.top, 8)
        }
    }

    static func roman(_ n: Int) -> String {
        guard n > 0 else { return "0" }
        let table: [(Int, String)] = [(10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var n = n, out = ""
        for (v, s) in table { while n >= v { out += s; n -= v } }
        return out
    }
}

/// 一排连环小旋（12×8 格一节，1.5pt 一格），横着铺满
private struct TarotLaceRow: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let rows = TarotLacePixels.laceTile
            let px: CGFloat = 1.5
            let tw = CGFloat(rows.first?.count ?? 12) * px
            var path = Path()
            var x0: CGFloat = 0
            while x0 < size.width {
                for (y, row) in rows.enumerated() {
                    for (x, ch) in row.enumerated() where ch == "o" {
                        path.addRect(CGRect(x: x0 + CGFloat(x) * px, y: CGFloat(y) * px, width: px + 0.2, height: px + 0.2))
                    }
                }
                x0 += tw
            }
            ctx.fill(path, with: .color(color))
        }
        .allowsHitTesting(false)
    }
}

/// 关键词小方签：四角各缺 2pt 的像素方块
private struct TarotNotch: Shape {
    func path(in r: CGRect) -> Path {
        let n: CGFloat = 2
        var p = Path()
        p.addLines([
            CGPoint(x: r.minX + n, y: r.minY), CGPoint(x: r.maxX - n, y: r.minY), CGPoint(x: r.maxX - n, y: r.minY + n),
            CGPoint(x: r.maxX, y: r.minY + n), CGPoint(x: r.maxX, y: r.maxY - n), CGPoint(x: r.maxX - n, y: r.maxY - n),
            CGPoint(x: r.maxX - n, y: r.maxY), CGPoint(x: r.minX + n, y: r.maxY), CGPoint(x: r.minX + n, y: r.maxY - n),
            CGPoint(x: r.minX, y: r.maxY - n), CGPoint(x: r.minX, y: r.minY + n), CGPoint(x: r.minX + n, y: r.minY + n)
        ])
        p.closeSubpath()
        return p
    }
}

/// 一张牌：白衬纸（黑夜深灰）＋一圈细粉边＋右下错开的一块浅粉实影；单张时左上、右下各贴一颗像素星芒
private struct TarotLaceMat: View {
    let card: TarotAskCard.Card
    let width: CGFloat
    let ink: TarotLaceInk
    var on = true
    var sparkles = false
    @ObservedObject private var decor = TarotDecor.shared

    var body: some View {
        Image("Tarot_" + card.id)
            .resizable()
            .scaledToFill()
            .saturation(decor.saturation)
            .colorMultiply(decor.multiply)
            .brightness(ink.dark ? -0.05 : 0)
            .frame(width: width, height: width * 1.72)
            .clipped()
            .rotationEffect(.degrees(card.reversed ? 180 : 0))
            .padding(4)
            .background(ink.mat)
            .overlay(Rectangle().stroke(on ? ink.lace : ink.lilac, lineWidth: 1).padding(-0.5))
            .background(Rectangle().fill(ink.laceSoft).padding(-1).offset(x: 3, y: 3))
            .overlay(alignment: .topLeading) {
                if sparkles {
                    CardPixelArt(rows: TarotLacePixels.sparkBig, px: 18.0 / 7, colors: ["o": ink.lace, "w": .white]).offset(x: -9, y: -9)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if sparkles {
                    CardPixelArt(rows: TarotLacePixels.sparkSmall, px: 2.6, colors: ["o": ink.spark2]).offset(x: 8, y: 8)
                }
            }
    }
}

private struct TarotMessageCard: View {
    let card: TarotAskCard
    let theme: AlcoveTheme
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    private var ink: TarotLaceInk { _ = houseAppearance; return TarotLaceInk(dark: AlcoveAppearance.isDark) }

    var body: some View {
        VStack(spacing: 0) {
            TarotLaceBits.head(meta: TarotLaceBits.meta(spread: card.spread, question: card.question, ts: card.ts),
                               who: card.byHim ? "陈璟抽了牌" : "陈霁抽了牌", question: card.question, ink: ink)
            TarotSpreadView(cards: card.cards, spread: card.spread, ink: ink)
            TarotLaceBits.foot(ink: ink)
        }
        .modifier(TarotLaceFramed(ink: ink))
        .onAppear { DiaryFonts.ensure() }
    }
}

/// 0903 她定的多牌排法（方案二）：单张牌左字右；三张一排；关系五张按牌阵本来的形状摆——
/// 「我」「他」左右对望在上，「我们之间」居中，「阻碍」「走向」在下。
/// 多牌时牌名和关键词只显示选中那张的（默认第一张），点哪张看哪张，选中的牌浮起来、描粉边。
private struct TarotSpreadView: View {
    let cards: [TarotAskCard.Card]
    let spread: String
    let ink: TarotLaceInk
    @ObservedObject private var store = TarotStore.shared
    @State private var selected = 0

    private var n: Int { cards.count }
    private var faceW: CGFloat { n <= 3 ? 60 : 42 }
    private var cellH: CGFloat { faceW * 1.72 + 8 + 20 }

    var body: some View {
        Group {
            if n <= 1, let c = cards.first {
                single(c)
            } else {
                VStack(spacing: 12) {
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
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(cards.indices, id: \.self) { i in cell(i) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    if cards.indices.contains(selected) {
                        let c = cards[selected]
                        VStack(spacing: 0) {
                            info(c, align: .center)
                            tags(c.keywords, columns: c.keywords.allSatisfy { $0.count <= 3 } ? 4 : 2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .task { await store.loadDeck() }
    }

    /// 单张：牌左字右
    private func single(_ c: TarotAskCard.Card) -> some View {
        HStack(alignment: .center, spacing: 16) {
            TarotLaceMat(card: c, width: 92, ink: ink, sparkles: true)
            VStack(alignment: .leading, spacing: 0) {
                info(c, align: .leading)
                tags(c.keywords, columns: 2)
            }
            .frame(width: 128, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    /// 花体英文牌名 / 中文牌名＋UPRIGHT / ARCANA · XIX
    private func info(_ c: TarotAskCard.Card, align: HorizontalAlignment) -> some View {
        let meta = store.card(c.id)
        let line: String? = meta.map {
            $0.arcana == "major" ? "ARCANA · \(TarotLaceBits.roman($0.number))"
                                 : "\($0.suit == "pents" ? "PENTACLES" : $0.suit.uppercased()) · \(TarotLaceBits.roman($0.number))"
        }
        return VStack(alignment: align, spacing: 0) {
            if let en = meta?.en, !en.isEmpty {
                Text(en).font(DiaryFonts.script(27)).foregroundColor(ink.lace)
                    .lineLimit(1).minimumScaleFactor(0.5)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(c.name).font(.system(size: 16, weight: .semibold, design: .serif)).foregroundColor(ink.ink)
                Text(c.reversed ? "REVERSED" : "UPRIGHT").font(DiaryFonts.pixel(9)).tracking(0.9).foregroundColor(ink.lilacInk)
            }
            .padding(.top, 3)
            if let line {
                Text(line).font(DiaryFonts.pixel(9)).tracking(1.26).foregroundColor(ink.sub).padding(.top, 2)
            }
        }
    }

    private func tags(_ words: [String], columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: columns), spacing: 7) {
            ForEach(words, id: \.self) { k in
                Text(k).font(.system(size: 11, weight: .medium)).foregroundColor(ink.tagInk)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.leading, 8).padding(.vertical, 3)
                    .frame(maxWidth: .infinity)
                    .background(ink.tag)
                    .overlay(alignment: .leading) {
                        CardPixelArt(rows: TarotLacePixels.heart, px: 1, colors: ["o": ink.lace]).padding(.leading, 7)
                    }
                    .clipShape(TarotNotch())
                    .overlay(TarotNotch().stroke(ink.lace, lineWidth: 3).clipShape(TarotNotch()))
            }
        }
        .padding(.top, 10)
    }

    private func cell(_ i: Int) -> some View {
        let c = cards[i]
        let on = i == selected
        return VStack(spacing: 6) {
            TarotLaceMat(card: c, width: faceW, ink: ink, on: on)
                .offset(y: on ? -3 : 0)
            // 0903 她要的：牌位和牌名并一行
            HStack(spacing: 3) {
                Text(c.positionName).font(.system(size: 8.5, weight: .semibold))
                    .foregroundColor(on ? ink.lace : ink.sub)
                Text(c.name).font(.system(size: 10, weight: .medium, design: .serif)).foregroundColor(ink.ink)
            }
            .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(width: faceW + 16)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selected = i } }
    }
}

/// 像素花纹：corner / crest / laceTile 由 /root/workroom/mock/tarot-card/v2/gen2.py 画出来再按格导出，改花纹去那儿重导
private enum TarotLacePixels {
    static let heart = [".oo.oo.", "ooooooo", "ooooooo", ".ooooo.", "..ooo..", "...o..."]
    static let sparkBig = ["...o...", "...o...", "..ooo..", "ooowooo", "..ooo..", "...o...", "...o..."]
    static let sparkSmall = ["..o..", "..o..", "ooooo", "..o..", "..o.."]
    static let corner: [String] = [
        "..........................................................",
        "....oo....................................................",
        "...oooo...................................................",
        "..oo..oo.ooooooooooooo............oooooooo.........ooooooo",
        ".oo.oo.oo..........oooooooooooooooo.......ooo....oo.......",
        ".oo.oo.oo...........o......ooo..............oo..o.........",
        "..oo..oo............o.............oo..........o...........",
        "...oooo.............oo...........oo.ooo........o..........",
        "....oo.........o.....o...........o.....o...oooo.o...o.....",
        "...o......oo..........o...........o....o..o...o.o.........",
        "...o.....oo.oooo.......oooooo.....o....o..o...o.o.........",
        "...o.....o......o............o....o.....o.oo...o..........",
        "...o......o......o........ooooo....ooo.oo..oooo...........",
        "...o......o.......o.......o...o.......oo..................",
        "...o......o.......o.......o..oo...........................",
        "...o....o.o.......o........ooo............................",
        "...o.......o......o.......................................",
        "...o........o......o..................o...................",
        "...o.........oooo.oo......................................",
        "...oo............oo.......................................",
        "...ooooo..................................................",
        "...oo..oo.................................................",
        "....o....o............o...................................",
        "....o.....o...............................................",
        "....o.....o...............................................",
        "....o.....o..............o................................",
        "....o.....o.ooo...........................................",
        "....oo....o.o..o..........................................",
        "....oo....o.o..o..........................................",
        "....oo.....oo.oo..........................................",
        "....o.......ooo...........................................",
        "....o.....................................................",
        "....o.....................................................",
        "....o..oo.................................................",
        "...oo.oo.ooo..............................................",
        "...o..o.....o.............................................",
        "...o...o....o.............................................",
        "...o...o....o.............................................",
        "...o...o.....o...o........................................",
        "...o....ooo.oo............................................",
        "...o.......oo.............................................",
        "...o......................................................",
        "....o....ooo..............................................",
        "....o...o..oo.............................................",
        "....oo..o...o.............................................",
        ".....o..o...o.............................................",
        "......o.ooo.o.............................................",
        ".......o...o..............................................",
        ".....o..ooo...............................................",
        "....o.....................................................",
        "....o.....................................................",
        "...o......................................................",
        "...o....o.................................................",
        "...o......................................................",
        "...o......................................................",
        "...o......................................................",
        "...o......................................................",
        "...o......................................................"
    ]
    static let crest: [String] = [
        "........................................................................",
        "...................................oo...................................",
        "........................................................................",
        "..........................oooooo........oooooo..........................",
        "...............oo.......ooo....ooo....ooo....ooo.......oo...............",
        ".......................oo........oo..oo........oo.......................",
        "......................oo..........oooo..........oo......................",
        "......................o............oo............o......................",
        "......................o..........................o......................",
        "..........oooo.......oo......oo..........oo......oo.......oooo..........",
        "........oo...oooo....o......ooooooo..ooooooo......o....oooo...oo........",
        ".......oo.......oo...oo.....oo..oooooooo..oo.....oo...oo.......oo.......",
        ".......o.oooo.....oo.oo.....o...oooooooo...o.....oo.oo.....oooo.o.......",
        ".........o...o.....oo.o.....o...oooooooo...o.....o.oo.....o...o.........",
        "........oo...o......o.o......oooo.oooo.oooo......o.o......o...oo........",
        ".......ooo...o.........o......o....oo....o......o.........o...ooo.......",
        "........oo..oo.........o....o..............o....o.........oo..oo........",
        ".........oooooooo.......o...o..............o...o.......oooooooo.........",
        "...o........o...o.......oo...o............o...oo.......o...o........o...",
        "............o....o.......o...oo..........oo...o.......o....o............",
        ".............o...o........o....o........o....o........o...o.............",
        ".............ooooo.........o....o......o....o.........ooooo.............",
        ".......................o...oo....o....o....oo...o.......................",
        ".....................oo.....oo....o..o....oo.....oo.....................",
        ".......oo.......ooooo........oo..........oo........ooooo.......oo.......",
        ".....oooooooooooo.............oo........oo.............oooooooooooo.....",
        "....ooo..o.....................oo......oo.....................o..ooo....",
        "...o.o..o.......................oo....oo.......................o..o.o...",
        "......oo.........................oo..oo.........................oo......",
        "..................................oooo..................................",
        "...................................oo...................................",
        "........................................................................",
        "...........................o................o...........................",
        "........................................................................"
    ]
    static let laceTile: [String] = [
        "............",
        ".....ooo....",
        "....o..oo...",
        "...o.o..o...",
        "....oo..o...",
        ".....oooo...",
        "............",
        "oooooooooooo"
    ]
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
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    private var ink: TarotLaceInk { _ = houseAppearance; return TarotLaceInk(dark: AlcoveAppearance.isDark) }

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

    private var cards: [TarotAskCard.Card] { drawn.isEmpty ? card.cards : drawn }
    private var done: Bool { card.done || finished || cards.count >= card.positions.count }
    private var nextPosition: TarotOfferCard.Position? {
        cards.count < card.positions.count ? card.positions[cards.count] : nil
    }

    var body: some View {
        // 1004：跟 TarotMessageCard 同一套蕾丝外框；抽满以后只留牌和关键词（解读不进卡）
        VStack(spacing: 0) {
            TarotLaceBits.head(meta: TarotLaceBits.meta(spread: card.spread, question: card.question, ts: card.ts),
                               who: done ? "陈璟出的题，抽好了" : "陈璟出了题，你来抽", question: card.question, ink: ink)
            if done {
                TarotSpreadView(cards: cards, spread: card.spread, ink: ink)
            } else {
                drawArea
            }
            TarotLaceBits.foot(ink: ink)
        }
        .modifier(TarotLaceFramed(ink: ink))
            .onAppear { DiaryFonts.ensure() }
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
                            TarotLaceMat(card: d, width: slotW, ink: ink)
                                .transition(.scale(scale: 0.3).combined(with: .opacity))
                        } else {
                            ZStack {
                                TarotCardBack(width: slotW).opacity(pos.key == nextPosition?.key ? 0.4 : 0.16)
                                RoundedRectangle(cornerRadius: slotW * 0.07, style: .continuous)
                                    .stroke(ink.lace.opacity(pos.key == nextPosition?.key ? 0.9 : 0.4),
                                            style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                            }
                            .frame(width: slotW, height: slotW * 1.72)
                            .padding(4)   // 跟抽好的牌（TarotLaceMat 带 4pt 衬纸）一样大
                        }
                        if card.positions.count > 1 {
                            Text(pos.name).font(.system(size: 9, weight: .medium))
                                .foregroundColor(pos.key == nextPosition?.key ? ink.lace : ink.sub)
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
                            .font(.system(size: 10)).foregroundColor(ink.sub)
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

// MARK: - 0929 聊天小卡：Inside 便签 / 檐下 / 不忘
// 她拍的效果图：/root/workroom/mock/cards3/mint3-day.png。薄荷＋偏紫淡粉＋雾灰，细线蝴蝶结、别针、小星、圆点。
// 深浅只认全屋黑白开关（AlcoveAppearance），不看主题。黑夜那套她还没看过效果图，先按同样的冷色压暗。

extension Notification.Name {
    /// object = HouseDestination.rawValue；RootView 收到就打开那间屋子（聊天小卡的跳转按钮用）
    static let alcoveOpenHouse = Notification.Name("alcoveOpenHouse")
}

private func cardRGB(_ h: UInt32) -> Color {
    Color(red: Double((h >> 16) & 0xff) / 255, green: Double((h >> 8) & 0xff) / 255, blue: Double(h & 0xff) / 255)
}

struct ChatCardInk {
    let dark: Bool
    var mint: Color { dark ? cardRGB(0x4FAF90) : cardRGB(0xB4F0DA) }
    var mintLine: Color { dark ? cardRGB(0x5BBF9F) : cardRGB(0xA9F0D6) }
    var mintD: Color { dark ? cardRGB(0x6FCFAE) : cardRGB(0x86DCBF) }
    var mintInk: Color { dark ? cardRGB(0x8FE3C6) : cardRGB(0x4CB892) }
    var mintShade: Color { dark ? cardRGB(0x2F7A63) : cardRGB(0x6FD6B2) }
    var pink: Color { dark ? cardRGB(0x463A52) : cardRGB(0xF5DAF1) }
    var pinkD: Color { dark ? cardRGB(0x7E5F86) : cardRGB(0xE9B9E2) }
    var pinkInk: Color { dark ? cardRGB(0xF0B3DD) : cardRGB(0xC67DBB) }
    var loadPink: Color { dark ? cardRGB(0xF2A9D8) : cardRGB(0xCF78B6) }   // 她嫌「正在记住」太浅，挑深
    var progPink: Color { dark ? cardRGB(0xC98AB6) : cardRGB(0xF6C8E6) }
    var silver: Color { dark ? cardRGB(0x55535E) : cardRGB(0xC7C6D0) }
    var silverD: Color { dark ? cardRGB(0x8A8795) : cardRGB(0x9D9BAA) }
    var ink: Color { dark ? cardRGB(0xE8E4EF) : cardRGB(0x6C6679) }
    var sub: Color { dark ? cardRGB(0x9A95A8) : cardRGB(0xA29CAF) }
    var page: Color { dark ? cardRGB(0x2A2930) : .white }
    var gray1: Color { dark ? cardRGB(0x3A3842) : cardRGB(0xB3B1BA) }
    var gray2: Color { dark ? cardRGB(0x34323C) : cardRGB(0xC9C6CF) }
    var gray3: Color { dark ? cardRGB(0x2C2B33) : cardRGB(0xDDD7E0) }
    var outline: Color { dark ? cardRGB(0x1B1A21) : .white }   // 贴纸外面那圈边
}

private enum CardScript {
    static func font(_ size: CGFloat) -> Font { .custom("SnellRoundhand", size: size) }
}

/// 像素小图：一行一个字符串，字符查颜色表，查不到的留空
private struct CardPixelArt: View {
    let rows: [String]
    let px: CGFloat
    let colors: [Character: Color]
    var body: some View {
        let cols = rows.first?.count ?? 0
        Canvas { ctx, _ in
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() {
                    guard let c = colors[ch] else { continue }
                    ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px + 0.3, height: px + 0.3)), with: .color(c))
                }
            }
        }
        .frame(width: CGFloat(cols) * px, height: CGFloat(rows.count) * px)
    }
}

private enum CardPixels {
    static let heart = ["..ooo.ooo..", ".offfofffo.", "ofhhffffffo", "ofhfffffffo", "offfffffffo",
                        ".offfffffo.", "..offfffo..", "...offfo...", "....ofo....", ".....o....."]
    static let bow = [".oo.......oo.", "ofho.....ohfo", "offfo...offfo", "offffoooffffo", "offffofoffffo",
                      "offffoooffffo", "offfo.o.offfo", "ofo..ofo..ofo", ".o...o.o...o."]
    static let sparkle = ["....o....", "...ofo...", "...ofo...", "..offfo..", "offfwfffo",
                          "..offfo..", "...ofo...", "...ofo...", "....o...."]
    static let tiny = ["0110110", "1111111", "1111111", "0111110", "0011100", "0001000"]
}

/// 像素贴纸：外面描一圈边（白天白边，夜里深边）
private struct CardSticker: View {
    let rows: [String]
    let px: CGFloat
    let colors: [Character: Color]
    let edge: Color
    var body: some View {
        CardPixelArt(rows: rows, px: px, colors: colors)
            .shadow(color: edge, radius: 0, x: 1.5, y: 0)
            .shadow(color: edge, radius: 0, x: -1.5, y: 0)
            .shadow(color: edge, radius: 0, x: 0, y: 1.5)
            .shadow(color: edge, radius: 0, x: 0, y: -1.5)
    }
}

/// 细线蝴蝶结
private struct CardThinBow: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 34
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            var path = Path()
            path.move(to: p(17, 10))
            path.addCurve(to: p(3, 7), control1: p(12, 3), control2: p(4, 2))
            path.addCurve(to: p(17, 10), control1: p(2, 12), control2: p(11, 13))
            path.move(to: p(17, 10))
            path.addCurve(to: p(31, 7), control1: p(22, 3), control2: p(30, 2))
            path.addCurve(to: p(17, 10), control1: p(32, 12), control2: p(23, 13))
            path.move(to: p(16, 12)); path.addCurve(to: p(9, 22), control1: p(14, 16), control2: p(12, 19))
            path.move(to: p(18, 12)); path.addCurve(to: p(25, 22), control1: p(20, 16), control2: p(22, 19))
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: 15 * s, y: 8 * s, width: 4.2 * s, height: 4.8 * s)), with: .color(.white))
            ctx.stroke(Path(ellipseIn: CGRect(x: 15 * s, y: 8 * s, width: 4.2 * s, height: 4.8 * s)), with: .color(color), lineWidth: 1)
        }
        .frame(width: 30, height: 21)
    }
}

/// 银色别针
private struct CardSafetyPin: View {
    var body: some View {
        Canvas { ctx, _ in
            var wire = Path()
            wire.move(to: CGPoint(x: 4, y: 7)); wire.addLine(to: CGPoint(x: 36, y: 7))
            wire.addArc(center: CGPoint(x: 36, y: 5), radius: 2, startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: true)
            wire.addLine(to: CGPoint(x: 8, y: 3))
            ctx.stroke(wire, with: .color(cardRGB(0xB9B8C3)), lineWidth: 1.2)
            let head = Path(roundedRect: CGRect(x: 1, y: 1.5, width: 9, height: 7), cornerRadius: 2)
            ctx.fill(head, with: .color(cardRGB(0xDCDBE3)))
            ctx.stroke(head, with: .color(cardRGB(0xA9A8B4)), lineWidth: 0.8)
        }
        .frame(width: 42, height: 11)
    }
}

/// 两颗四角小星＋一个小圈
private struct CardTwinStars: View {
    let a: Color
    let b: Color
    var body: some View {
        Canvas { ctx, _ in
            func star(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
                var p = Path(); let k = r * 0.3
                p.move(to: CGPoint(x: cx, y: cy - r)); p.addLine(to: CGPoint(x: cx + k, y: cy - k))
                p.addLine(to: CGPoint(x: cx + r, y: cy)); p.addLine(to: CGPoint(x: cx + k, y: cy + k))
                p.addLine(to: CGPoint(x: cx, y: cy + r)); p.addLine(to: CGPoint(x: cx - k, y: cy + k))
                p.addLine(to: CGPoint(x: cx - r, y: cy)); p.addLine(to: CGPoint(x: cx - k, y: cy - k)); p.closeSubpath()
                return p
            }
            let s1 = star(9, 9, 7), s2 = star(22, 17, 4)
            ctx.fill(s1, with: .color(.white)); ctx.stroke(s1, with: .color(a), lineWidth: 0.7)
            ctx.fill(s2, with: .color(.white)); ctx.stroke(s2, with: .color(b), lineWidth: 0.6)
            let dot = Path(ellipseIn: CGRect(x: 22.6, y: 3.6, width: 2.8, height: 2.8))
            ctx.fill(dot, with: .color(.white)); ctx.stroke(dot, with: .color(a), lineWidth: 0.5)
        }
        .frame(width: 30, height: 26)
    }
}

/// 竖条形码
private struct CardBarcode: View {
    let ink: Color
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            for (i, y) in [2, 4, 5, 8, 10, 11, 13, 17, 19, 20, 23, 26, 27, 30, 33, 34, 36, 39, 41, 42, 45, 48, 49, 52].enumerated() {
                ctx.fill(Path(CGRect(x: 3, y: CGFloat(y), width: 10, height: i % 3 == 0 ? 1.6 : 0.8)), with: .color(ink))
            }
        }
        .frame(width: 16, height: 56)
    }
}

/// 圆点底纹
private struct CardDots: View {
    let color: Color
    let spacing: CGFloat
    let radius: CGFloat
    var body: some View {
        Canvas { ctx, size in
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
                    x += spacing
                }
                y += spacing
            }
        }
    }
}

// ── ① Inside：粉框笔记页，默认两行，点一下展开 / 收起 ──

private struct InsideMessageCard: View {
    let text: String
    let date: Date
    let theme: AlcoveTheme
    let messageID: String
    @State private var expanded = false
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    private var ink: ChatCardInk { _ = houseAppearance; return ChatCardInk(dark: AlcoveAppearance.isDark) }
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
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("inside").font(CardScript.font(24)).foregroundColor(ink.mintD)
                    Text("THINGS LEFT UNSAID").font(.system(size: 8, weight: .medium, design: .serif))
                        .tracking(2.2).foregroundColor(ink.pinkInk)
                    Spacer(minLength: 34)
                }
                Text(text)
                    .font(.system(size: 13, design: .serif))
                    .underline(true, pattern: .dot, color: ink.silver)
                    .lineSpacing(9)
                    .foregroundColor(ink.ink)
                    .lineLimit(expanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Text(Self.time.string(from: date)).foregroundColor(ink.sub)
                    Spacer()
                    Text(expanded ? "收起 ⌃" : "展开 ⌄").foregroundColor(ink.pinkInk)
                }
                .font(.system(size: 10))
                .padding(.top, 4)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
            .background(ink.page)
            .padding(9)
            .background(ink.pink)
            .overlay(alignment: .topTrailing) {
                CardThinBow(color: ink.silverD).padding(.top, 14).padding(.trailing, 16)
            }
            .overlay(alignment: .topTrailing) {
                VStack(spacing: 24) { CardSafetyPin().rotationEffect(.degrees(-8)); CardSafetyPin().rotationEffect(.degrees(-4)) }
                    .offset(x: 26, y: 48)
            }
            .overlay(alignment: .bottomLeading) { CardTwinStars(a: ink.pinkD, b: ink.mintD).offset(x: -12, y: 10) }
            .frame(maxWidth: 272, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

// ── ② 檐下：淡粉灰点卡，默认两行，展开 / 收起 ＋ 去檐下看看 ──

struct PondChatMessageCard: View {
    let card: PondChatCard
    @State private var expanded = false
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    private var ink: ChatCardInk { _ = houseAppearance; return ChatCardInk(dark: AlcoveAppearance.isDark) }
    private var foldable: Bool { card.text.count > 36 || card.text.contains("\n") }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("under the eaves").font(CardScript.font(19)).foregroundColor(ink.pinkInk)
                    Spacer(minLength: 6)
                    Text(card.kind == "wish" ? "檐下 · 许愿" : "檐下")
                        .font(.system(size: 9.5, design: .serif)).tracking(2).foregroundColor(ink.mintInk)
                }
                Text(card.text)
                    .font(.system(size: 13, design: .serif))
                    .lineSpacing(5)
                    .foregroundColor(ink.ink)
                    .lineLimit(expanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(ink.page.opacity(0.9))
            .overlay(Rectangle().stroke(ink.pinkD, lineWidth: 1))
            .overlay(Rectangle().stroke(ink.pinkD.opacity(0.5), lineWidth: 1).padding(3))
            HStack {
                // 0929 她定的：左下角一直是 just now；要折叠时后面跟个小三角，点这一行展开/收起；不用折叠就没三角、点不动
                if foldable {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text("just now").font(CardScript.font(13))
                            Text(expanded ? "▴" : "▾").font(.system(size: 9))
                        }
                        .foregroundColor(ink.pinkInk)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("just now").font(CardScript.font(13)).foregroundColor(ink.pinkInk)
                }
                Spacer()
                Button {
                    NotificationCenter.default.post(name: .alcoveOpenHouse, object: HouseDestination.pond.rawValue)
                } label: {
                    Text("去檐下看看")
                        .font(.system(size: 11.5))
                        .foregroundColor(ink.mintInk)
                        .padding(.horizontal, 14).padding(.vertical, 4)
                        .background(Capsule().fill(ink.page))
                        .overlay(Capsule().stroke(ink.mintD, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(ZStack { ink.pink; CardDots(color: ink.silver, spacing: 11, radius: 1.2) })
        .overlay(alignment: .topTrailing) { CardThinBow(color: ink.silverD).rotationEffect(.degrees(6)).offset(x: -10, y: -11) }
        .overlay(alignment: .topLeading) { CardBarcode(ink: ink.ink).offset(x: -17, y: 18) }
        .overlay(alignment: .trailing) { CardTwinStars(a: ink.pinkD, b: ink.mintD).offset(x: 13, y: 12) }
        .frame(width: 252, alignment: .leading)
    }
}

// ── ③ 不忘：像素小窗，只放标题＋哪条线＋跳转 ──

struct MemoryChatMessageCard: View {
    let card: MemoryChatCard
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    private var ink: ChatCardInk { _ = houseAppearance; return ChatCardInk(dark: AlcoveAppearance.isDark) }

    private var stickerPink: [Character: Color] {
        ink.dark ? ["o": cardRGB(0xB77FA8), "f": cardRGB(0xE6A9D2), "h": cardRGB(0xF8DDEE), "w": .white]
                 : ["o": cardRGB(0xE7A3CF), "f": cardRGB(0xF8CDE9), "h": .white, "w": .white]
    }
    private var stickerMint: [Character: Color] {
        ink.dark ? ["o": cardRGB(0x4FAF90), "f": cardRGB(0x8FDFC3), "h": cardRGB(0xD2F6EA), "w": .white]
                 : ["o": cardRGB(0x7FDCBC), "f": cardRGB(0xB9F5DF), "h": .white, "w": .white]
    }
    private var stickerWhite: [Character: Color] {
        ["o": ink.dark ? cardRGB(0xB77FA8) : cardRGB(0xE7A3CF), "f": .white, "h": cardRGB(0xFDEEF8), "w": cardRGB(0xF8CDE9)]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                CardPixelArt(rows: CardPixels.tiny, px: 1.6, colors: ["1": .white])
                Text("MEMORY V1.1")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.2)
                    .foregroundColor(.white).shadow(color: ink.mintShade, radius: 0, x: 1, y: 1)
                Spacer()
                Text("×").font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white).shadow(color: ink.mintShade, radius: 0, x: 1, y: 1)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(ink.mintLine)
            VStack(alignment: .leading, spacing: 0) {
                Text("正在记住……").font(.system(size: 12)).foregroundColor(ink.loadPink)
                    .padding(.horizontal, 3).padding(.top, 2).padding(.bottom, 5)
                HStack(spacing: 2) {
                    ForEach(0..<18, id: \.self) { _ in Rectangle().fill(ink.progPink) }
                }
                .padding(2)
                .frame(height: 14)
                .background(ink.page.opacity(0.55))
                .overlay(Rectangle().stroke(ink.mintLine, lineWidth: 2))
                .padding(.horizontal, 3).padding(.bottom, 8)
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.title)
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundColor(ink.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let thread = card.thread, !thread.isEmpty {
                        Text(thread).font(.system(size: 10)).foregroundColor(ink.pinkInk)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(Rectangle().stroke(ink.pinkD, lineWidth: 1.5))
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ink.page.opacity(0.84))
                .overlay(Rectangle().stroke(ink.mintLine, lineWidth: 2))
                .padding(3)
                .overlay(Rectangle().stroke(ink.page.opacity(0.9), lineWidth: 1))
                .padding(.horizontal, 3)
                HStack {
                    Spacer()
                    Button {
                        BuwangDeepLink.search = card.title
                        NotificationCenter.default.post(name: .alcoveOpenHouse, object: HouseDestination.memory.rawValue)
                    } label: {
                        Text("打开这条记忆")
                            .font(.system(size: 12))
                            .foregroundColor(ink.pinkInk)
                            .padding(.horizontal, 14).padding(.vertical, 3)
                            .background(ink.page.opacity(0.88))
                            .overlay(Rectangle().stroke(ink.mintLine, lineWidth: 2))
                            .background(Rectangle().fill(ink.progPink).offset(x: 2, y: 2))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
            }
            .padding(8)
            .background(
                ZStack {
                    LinearGradient(colors: [ink.gray1, ink.gray2, ink.gray3], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [ink.pinkD.opacity(ink.dark ? 0.18 : 0.45), .clear], center: UnitPoint(x: 0.85, y: 0.2), startRadius: 0, endRadius: 150)
                }
            )
            HStack {
                Spacer()
                Text("No." + String(format: "%04d", card.id % 10000))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white).shadow(color: ink.mintShade, radius: 0, x: 1, y: 1)
                    .padding(.leading, 8).padding(.trailing, 2)
                    .frame(maxHeight: .infinity)
                    .background(ink.mintLine)
            }
            .padding(.trailing, 8)
            .frame(height: 24)
            .background(ZStack { ink.mintLine; CardDots(color: .white, spacing: 13, radius: 2) })
        }
        .overlay(Rectangle().stroke(ink.mintLine, lineWidth: 2))
        .background(Rectangle().fill(ink.progPink.opacity(0.9)).offset(x: 3, y: 3))
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 3) {
                Image(systemName: "heart.fill").font(.system(size: 8, weight: .bold))
                Text("1").font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(cardRGB(0xF3B9DD)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(ink.outline, lineWidth: 1.5))
            .offset(x: -22, y: -12)
        }
        .overlay(alignment: .topTrailing) {
            CardSticker(rows: CardPixels.heart, px: 2.5, colors: stickerPink, edge: ink.outline)
                .rotationEffect(.degrees(14)).offset(x: 13, y: 52)
        }
        .overlay(alignment: .bottomLeading) {
            CardSticker(rows: CardPixels.sparkle, px: 1.85, colors: stickerWhite, edge: ink.outline)
                .offset(x: -10, y: -56)
        }
        .overlay(alignment: .bottomLeading) {
            CardSticker(rows: CardPixels.bow, px: 1.95, colors: stickerMint, edge: ink.outline)
                .rotationEffect(.degrees(6)).offset(x: 30, y: 10)
        }
        .frame(width: 252)
    }
}

private struct MorningPaperMessageCard: View {
    let date: String
    let theme: AlcoveTheme
    let messageID: String
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
/// 1001 她要的「预览一定要跟当前主题一模一样（字体、气泡、壁纸等等）」：原来设置里三份手画的仿品（普通 / 信息 / Kakao 各一份），
/// 聊天页一改就对不上。这里直接用聊天页同一个 MessageRow、同一张壁纸（ChatWallpaperStore.shared）、同样的分隔线和左右边距，
/// 只是消息是写死的两条示例。整块不吃触摸。
struct ChatLookPreview: View {
    @ObservedObject private var wallpaper = ChatWallpaperStore.shared
    @ObservedObject private var packs = KakaoPackStore.shared
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @AppStorage("chatFontSize") private var fontSize = 14
    @AppStorage("chatBubbleGap") private var bubbleGap = 6.0
    @AppStorage("wallStamp") private var wallStamp = 0.0
    @AppStorage(MessagesPalette.stampKey) private var paletteStamp = 0.0
    @AppStorage("msgGlassFrost") private var glassFrost = 0.3
    @AppStorage("assistantName") private var assistantName = "陈璟"
    @Namespace private var ns

    private var theme: AlcoveTheme { _ = paletteStamp; return .named(themeName) }

    private func sample(_ role: String, _ text: String, minutesAgo: Double, extra: [String: Any] = [:]) -> ChatMessage? {
        let ts = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-minutesAgo * 60))
        var json: [String: Any] = ["ts": ts, "role": role, "text": text, "turn_id": "preview-\(role)"]
        json.merge(extra) { _, b in b }
        return ChatMessage(json: json)
    }

    var body: some View {
        let t = theme
        let ai = sample("assistant", "这里慢慢调，我陪你看", minutesAgo: 3,
                        extra: ["thinking": "她在挑颜色，我等着看她挑到哪一格", "heart_rate": 78])
        let me = sample("user", "\(assistantName)，气泡再透一点", minutesAgo: 1)
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                ChatWallpaperRenderer(descriptor: wallpaper.descriptor)
                VStack(alignment: .leading, spacing: CGFloat(bubbleGap)) {
                    if t.isKakao {
                        KakaoDateDivider(date: Date())
                    } else if t.isTreehouse {
                        TreehouseTimeDivider(date: Date(), color: t.dividerColor)
                    } else if t.isMessages {
                        MessagesTimeDivider(date: Date(), color: t.dividerColor)
                    } else {
                        TimeDivider(date: Date(), color: t.dividerColor)
                    }
                    if let ai {
                        MessageRow(msg: ai, sticker: nil, theme: t, fontSize: fontSize,
                                   photoNamespace: ns, onTapImages: { _, _ in },
                                   kakaoHead: true, kakaoFirstBubble: true)
                    }
                    if let me {
                        MessageRow(msg: me, sticker: nil, theme: t, fontSize: fontSize,
                                   photoNamespace: ns, onTapImages: { _, _ in },
                                   kakaoHead: true, kakaoFirstBubble: true, kakaoUnread: true)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .coordinateSpace(name: "alcoveChatRoot")
            .environment(\.chatWallpaperDescriptor, wallpaper.descriptor)
            .environment(\.chatWallpaperViewportSize, proxy.size)
        }
        .allowsHitTesting(false)
        .onAppear { refresh() }
        .onChange(of: themeName) { _ in refresh() }
        .onChange(of: wallStamp) { _ in refresh() }
        .onReceive(packs.$stamp) { _ in refresh() }
    }

    /// 跟聊天页同一份壁纸：主题、相册换图、Kakao 换包 / 图到了都重读（同一把钥匙读过就不重复读）
    private func refresh() {
        wallpaper.refresh(themeName: themeName, theme: theme, wallStamp: wallStamp)
    }
}

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

/// 1009 树屋的时间：打字机字、字距拉开，衬一块半透明的雾白小底（照她成品 stamp()）
struct TreehouseTimeDivider: View {
    let date: Date
    var color: Color = TreehouseInk.ink
    var body: some View {
        Text(Self.text(date))
            .font(.system(size: 10.5, design: .monospaced))
            .tracking(1.5)
            .foregroundColor(color)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(TreehouseInk.fog.opacity(0.9), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }
    /// 今天只写几点；别的日子前面加月.日
    static func text(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? hm.string(from: d) : md.string(from: d) + "  " + hm.string(from: d)
    }
    static let hm: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
    static let md: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MM.dd"; return f }()
}

/// 树屋的几样颜色（她成品 alcove chat page.html 里的 BG / INK / BLUE / WHITE / DARK）

/// 1009 晚 她：「在调整颜色那边加一个切换气泡（分段／整个），仅限树屋这个主题」
/// 「这个气泡仅限你的，我的不包含」——所以只并他的，她的气泡一个都不动。
enum TreehouseBubbleMode {
    static let key = "treehouseWholeBubble"
    static var whole: Bool { UserDefaults.standard.bool(forKey: key) }
}

/// #3518 起分白天 / 黑夜，跟全屋那个按钮走（树屋 themeName 也跟着在 treehouse / treehouse-dark 之间翻）。
/// fog＝底色，ink＝字和线，white＝他的泡 / 图的纸边 / 思绪底，dark＝她的泡
enum TreehouseInk {
    static var night: Bool { AlcoveAppearance.isDark }
    static var fog: Color { night ? Color(red: 0x1B/255, green: 0x1C/255, blue: 0x20/255) : Color(red: 0xEF/255, green: 0xEF/255, blue: 0xED/255) }
    static var ink: Color { night ? Color(red: 0xE9/255, green: 0xE8/255, blue: 0xE4/255) : Color(red: 0x14/255, green: 0x14/255, blue: 0x14/255) }
    static var blue: Color { night ? Color(red: 0x3A/255, green: 0x55/255, blue: 0xFF/255) : Color(red: 0x0B/255, green: 0x1B/255, blue: 0xFF/255) }
    static var white: Color { night ? Color(red: 0x2A/255, green: 0x2B/255, blue: 0x31/255) : Color(red: 0xFB/255, green: 0xFA/255, blue: 0xF7/255) }
    static var dark: Color { night ? Color(red: 0xE4/255, green: 0xE3/255, blue: 0xDE/255) : Color(red: 0x2A/255, green: 0x28/255, blue: 0x26/255) }
    static var gray: Color { night ? Color(red: 0x8E/255, green: 0x8E/255, blue: 0x94/255) : Color(red: 0x7A/255, green: 0x79/255, blue: 0x75/255) }
}

/// 树屋顶栏要的两样：他最近一次心率（「● 88」）、模型名（名字底下那行斜体）
final class TreehouseHeaderModel: ObservableObject {
    static let shared = TreehouseHeaderModel()
    @Published var bpm: Int?
    @Published var model = ""

    // 1009 晚 她：「这个心率跟脉那个面板要对齐，要一直更新，现在一直都不动」
    // 原来 bpm 是从最后一条消息上扒下来的，消息不来就永远停着。改成自己去问活的那份
    // （/api/pulse-now → pulse_core.compute()，跟「脉」面板同一个源），10 秒一次。
    private var ticker: Task<Void, Never>?

    func startLivePulse() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                if let o = try? await AlcoveAPI.getRaw("/api/pulse-range/now"),   // #3519 /api/pulse-now 外网门不放行，换别名
                   o["ok"] as? Bool == true,
                   let n = (o["bpm"] as? NSNumber)?.intValue, n > 0 {
                    await MainActor.run {
                        if self?.bpm != n { self?.bpm = n }
                    }
                }
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }
}

/// 树屋顶栏底下那根线：细灰轨道、黑色实心段＝上下文用了多少、头上一颗电光蓝圆点（她成品 progress line）。
/// tmux / SDK 读 /api/sdk-shadow/status 里当前通道那份，API 房间读 /api/api-room/context；隔 8 秒问一次
struct TreehouseContextLine: View {
    let room: String
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""   // #3518 白天 / 黑夜一翻就重画
    @State private var ratio: Double = 0
    // 1009 晚 她要的：线最右边写「230k/1m」，手写花体
    @State private var used: Double = 0
    @State private var window: Double = 0

    /// 230000 → 230k；1000000 → 1m；1200000 → 1.2m
    private func short(_ n: Double) -> String {
        if n >= 1_000_000 {
            let m = n / 1_000_000
            return m >= 10 || m == m.rounded() ? "\(Int(m.rounded()))m" : String(format: "%.1fm", m)
        }
        if n >= 1_000 { return "\(Int((n / 1_000).rounded()))k" }
        return "\(Int(n))"
    }

    private var tokenText: String {
        guard window > 0 else { return "" }
        return "\(short(used))/\(short(window))"
    }

    var body: some View {
        let _ = houseAppearance
        HStack(alignment: .center, spacing: 9) {
            line
            if !tokenText.isEmpty {
                // 1009 #3510 她：「换成手写字体 现在的太丑了 用一小块雾玻璃小胶囊做边框」——回到 Diary 那个 Pinyon 花体，套一颗雾玻璃小胶囊
                Text(tokenText)
                    .font(.custom("PinyonScript-Regular", size: 15))
                    .foregroundColor(TreehouseInk.ink.opacity(0.9))
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.top, 1)
                    .padding(.bottom, 2)
                    .modifier(TreehouseFogGlass(shape: Capsule(), border: 0.3))
                    .animation(.easeOut(duration: 0.4), value: tokenText)
            }
        }
        .frame(height: 8)
        .task(id: room) {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: 8_000_000_000)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .alcoveApiContextChanged)) { _ in
            Task { await load() }
        }
    }

    private var line: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x = max(4, w * ratio)
            ZStack(alignment: .leading) {
                Rectangle().fill(TreehouseInk.ink.opacity(0.22)).frame(height: 1)
                Capsule().fill(TreehouseInk.ink).frame(width: x, height: 3)
                Circle().fill(TreehouseInk.blue)
                    .frame(width: 8, height: 8)
                    .shadow(color: TreehouseInk.blue.opacity(0.55), radius: 3)
                    .offset(x: x - 4)
            }
            .frame(height: 8)
            .animation(.easeOut(duration: 0.4), value: ratio)
        }
        .frame(height: 8)
    }

    @MainActor private func load() async {
        if room == "api" {
            if let o = try? await AlcoveAPI.getRaw("/api/api-room/context"), o["ok"] as? Bool == true {
                let c = ApiContext(o)
                ratio = c.ratio
                used = Double(c.used)
                window = Double(c.limit)
            }
            return
        }
        guard let o = try? await AlcoveAPI.getRaw("/api/sdk-shadow/status") else { return }
        let ch = o["channel"] as? String ?? "cli"
        let ctx = o[ch == "sdk" ? "sdk_context" : "cli_context"] as? [String: Any] ?? [:]
        let u = (ctx["used"] as? NSNumber)?.doubleValue ?? 0
        let w = (ctx["window"] as? NSNumber)?.doubleValue ?? 0
        if w > 0 {
            ratio = min(1, max(0, u / w))
            used = u
            window = w
        }
    }
}

struct TreehouseBubbleFill: ViewModifier {
    let isUser: Bool
    let fill: Color
    var showsCorner: Bool = true
    /// #3519 树屋也能切玻璃：跟信息主题那种一样——系统玻璃，上面薄薄一层白（夜里黑），浓淡跟「玻璃」那根滑条走
    var glass: Bool = false
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    @AppStorage("msgGlassFrost") private var frost = 0.3

    @ViewBuilder
    func body(content: Content) -> some View {
        let _ = houseAppearance
        let shape = UnevenRoundedRectangle(topLeadingRadius: 18,
                                           bottomLeadingRadius: !isUser && showsCorner ? 5 : 18,
                                           bottomTrailingRadius: isUser && showsCorner ? 5 : 18,
                                           topTrailingRadius: 18, style: .continuous)
        if glass {
            if #available(iOS 26.0, *) {
                content
                    .background((TreehouseInk.night ? Color.black : Color.white).opacity(frost * 0.6), in: shape)
                    .glassEffect(.clear, in: shape)
            } else {
                solid(content, shape)
            }
        } else {
            solid(content, shape)
        }
    }

    private func solid(_ content: Content, _ shape: UnevenRoundedRectangle) -> some View {
        content
            .background(fill, in: shape)
            .overlay(shape.stroke(TreehouseInk.ink.opacity(isUser ? 0 : 0.06), lineWidth: 1).allowsHitTesting(false))
    }
}

/// 树屋的图：外面垫一圈白纸边（6），12 圆角，跟她成品里那张图一样
struct TreehousePhotoFrame: ViewModifier {
    let on: Bool
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    @ViewBuilder func body(content: Content) -> some View {
        let _ = houseAppearance
        if on {
            content
                .padding(6)
                .background(TreehouseInk.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            content
        }
    }
}

/// 树屋那层雾玻璃：rgba(239,239,237,.42) 再垫一点点模糊，外面一圈墨线（她成品的输入框 / 叶子圆）
struct TreehouseFogGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let border: Double
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    func body(content: Content) -> some View {
        let _ = houseAppearance
        return content
            .background { shape.fill(.ultraThinMaterial).opacity(0.55) }
            .background(TreehouseInk.fog.opacity(0.42), in: shape)
            .overlay(shape.strokeBorder(TreehouseInk.ink.opacity(border), lineWidth: 1))
    }
}

/// 她成品 ICON.leaf：一片叶子 + 一道叶脉，24×24 的画法按框缩放
struct TreehouseLeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.move(to: p(4.5, 19.5))
        path.addCurve(to: p(19.5, 4.5), control1: p(4.5, 10), control2: p(10.5, 4.5))
        path.addCurve(to: p(4.5, 19.5), control1: p(19.5, 13.5), control2: p(14, 19.5))
        path.closeSubpath()
        path.move(to: p(4.5, 19.5))
        path.addLine(to: p(13.5, 10.5))
        return path
    }
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
                ObliqueText(text: state.thinking, size: 11, color: UIColor(theme.textDim.opacity(0.62)))
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
            .modifier(HouseColorScheme())
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
                // 0921 任务#2485 她要的：信息主题也把「正在X中…」和工具原文显示回来（原来只留三个点）
                Text("\(name)正在\(line)中…")
                    .font(.system(size: 12))
                    .foregroundColor(theme.timestamp)   // 0924 她要的：跟时间戳一个色（设置里能调的那个），不再跟他正文走
                Spacer()
            }
            if let tool, !tool.isEmpty {
                // 工具原文她要留着：Bash — 追头像变量aa的赋值来源
                Text(tool)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.timestamp.opacity(0.8))   // 0924 她要的：跟上面那行一起走时间戳色
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

    private var ink: Color {
        // 0925：Kakao 下套的是包里的气泡图，字色跟正文气泡一样用包里写的收 / 发字色
        if theme.isKakao { return (isUser ? theme.textUser : theme.textAI) ?? theme.text }
        // 树屋：两边各用各的正文色（夜里她的泡是浅底，原来写死白字会看不见；玻璃时也一样）
        if theme.isTreehouse { return (isUser ? theme.textUser : theme.textAI) ?? theme.text }
        // 1001 信息主题玻璃气泡不带颜色，白字看不见：玻璃时她这边跟正文一样用调色里「我的正文」
        if theme.isMessages && isUser && MessagesPalette.glass { return theme.textUser ?? theme.text }
        return (theme.isMessages && isUser) ? .white : theme.text
    }
    // 转文字跟正文一样吃全局字体（她 0924 定的「字体全局，哪个主题都吃」）；换了字体这里跟着重画
    @ObservedObject private var packs = KakaoPackStore.shared

    /// 10 条起步，每秒多一条，封顶 30——一条 4.5pt，最长约 135pt 的波纹，气泡不会撑爆
    /// 0912 她要能拖进度，短语音太窄对不准：起步 10 → 13 条（她说只加宽一点点）
    private var barCount: Int { max(13, min(30, Int(10 + duration * 1.0))) }
    /// 波纹实际宽度（每条 2.5 ＋ 间隔 2），拖的时候拿手指位置除以它算百分比
    private func waveWidth(bars n: Int) -> CGFloat { CGFloat(n) * 2.5 + CGFloat(n - 1) * 2 }

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
        Group {
            if theme.isKakao {
                // 0925 她要的：Kakao 下语音条也套包里的气泡图，跟正文一样，字离四边按包里写的来。
                // 带图案的 01 那张还是只给一串里第一条真说话的气泡（0924 她定的规矩），语音一律用 02
                KakaoBubbleView(isUser: isUser, first: false) { card(kakao: true) }
            } else if theme.isTreehouse {
                card(kakao: false)
                    .modifier(TreehouseBubbleFill(isUser: isUser, fill: isUser ? theme.bubbleUser : theme.bubbleAI,
                                                  glass: MessagesPalette.thGlass))
            } else {
                // 1001 她抓的「语音的气泡呢」：跟正文气泡同一个开关，信息主题选玻璃就是玻璃
                card(kakao: false)
                    .modifier(MessagesBubbleFill(fill: isUser ? theme.bubbleUser : theme.bubbleAI,
                                                 glass: theme.isMessages && MessagesPalette.glass))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: transcriptShown)
        .contextMenu {
            if let onFavorite {
                Button { onFavorite() } label: { Label("收藏", systemImage: "heart") }
            }
        }
        .task(id: url) { await loadDuration() }
    }

    /// 语音条本体。Kakao 的气泡图自己带了离四边的距离，这里就不再垫那圈 14 / 10
    private func card(kakao: Bool) -> some View {
        let padH: CGFloat = kakao ? 0 : 14
        let padV: CGFloat = kakao ? 2 : 10
        return VStack(alignment: .leading, spacing: 0) {
            // 0927 她截图：展开后多了「译」，一行挤不下，时长被压成竖排 0 / : / 4 / 5。
            // 时长不许折行；挤不下时波纹少画几条让位（没展开时照旧满条，观感不变）
            ViewThatFits(in: .horizontal) {
                ForEach(barFallbacks, id: \.self) { n in headerRow(bars: n) }
            }
            .padding(.horizontal, padH)
            .padding(.vertical, padV)
            if hasTranscript && transcriptShown {
                Rectangle()
                    .fill(ink.opacity(0.16))
                    .frame(height: 1)
                    .padding(.horizontal, kakao ? 0 : 12)
                    .padding(.vertical, kakao ? 6 : 0)
                // 0919 她要的：点「译」不再另起一条线挂小字，中文直接顶替英文原文，同字号同样式；再点回原文
                Text(translationShown && !translation.isEmpty ? translation : transcript)
                    .font(packs.chatFont(fontSize))
                    .lineSpacing(theme.isPaper ? 7 : 5)
                    .padding(.horizontal, padH)
                    .padding(.vertical, padV)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundColor(ink)
    }

    /// 波纹条数的退路：满条 → 每次少 4 条，最少 8 条
    private var barFallbacks: [Int] {
        var out = [barCount]
        while let last = out.last, last - 4 >= 8 { out.append(last - 4) }
        return out
    }

    private func headerRow(bars n: Int) -> some View {
        HStack(spacing: 10) {
            Button(action: togglePlay) {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 13))
                    .frame(width: 18, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            waveform(bars: n)
                .contentShape(Rectangle())
                .onTapGesture { togglePlay() }
                .simultaneousGesture(scrubGesture(width: waveWidth(bars: n)))
            Text(timeText)
                .font(.system(size: 13, design: .monospaced))
                .lineLimit(1)
                .fixedSize()
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
                        Text(translationShown ? "原" : "译")
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
    }

    private func waveform(bars n: Int) -> some View {
        let heights = bars
        return HStack(alignment: .center, spacing: 2) {
            ForEach(0..<n, id: \.self) { i in
                let lit = Double(i) / Double(n) < shownProgress
                Capsule()
                    .fill(ink.opacity(lit ? 0.95 : 0.42))
                    .frame(width: 2.5, height: heights[i % heights.count])
            }
        }
        .frame(height: 22)
    }

    /// 0912 她要的：按住波纹横着拖＝拖进度，松手从那儿接着放。
    /// 第一下动的方向定终身：竖着的整下都不管（留给聊天滚动）；点一下还是播放/暂停（上面的 onTapGesture）
    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if dragIsScrub == nil {
                    dragIsScrub = abs(value.translation.width) > abs(value.translation.height)
                }
                guard dragIsScrub == true else { return }
                scrubFraction = min(1, max(0, Double(value.location.x / width)))
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

// 主聊天双方共用：少图横排；多图一横排横滑（0920 她要的：不再有展开成两列那套）。圆桌仍保留叠牌。
struct OfficialPhotoGridMessageView: View {
    let urls: [URL]
    let messageID: String
    let onOpen: ([URL], Binding<Int>) -> Void
    /// 1001：聊天页的长按给贴表情了，这里就不挂系统菜单
    var nativeMenu = true

    @State private var currentIndex = 0
    private let side: CGFloat = 124
    private let gap: CGFloat = 8
    /// 第三张露出来的一截，提示还能往右滑
    private let peek: CGFloat = 52

    var body: some View {
        Group {
            if urls.count > 2 {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: gap) { photos }
                }
                .frame(width: side * 2 + gap * 2 + peek)
            } else {
                HStack(spacing: gap) { photos }
            }
        }
        .id(messageID)
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
        .chatPhotoRim()
        .contextMenu {
            if nativeMenu {
                Button {
                    Task { await PhotoLibrarySaver.save(url) }
                } label: { Label("保存到相册", systemImage: "square.and.arrow.down") }
            }
        }
    }
}

/// 1001 她要的：图跟壁纸一个色就融进去了（Kakao 小猪灰点壁纸＋白底图）。
/// 照 iOS 信息：所有主题发的图一律描一圈细线，白天淡黑、黑夜淡白；表情包不描。
private struct ChatPhotoRim: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(scheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.14),
                              lineWidth: 1)
                .allowsHitTesting(false)
        )
    }
}

extension View {
    func chatPhotoRim() -> some View { modifier(ChatPhotoRim()) }
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
// 0928 她要的：标题改成「那一刻他想起的」；里面原来整段召回原文糊成一张卡（## 和开头那句说明都露着）
// 「排版太杂了也有点丑」——按新召回的格式一样东西一张纸片，跟不忘一套纸面、手写字；
// 卷很长，先收着给几行，点了再展开。老格式（OB 那套 [bucket_id:）照旧走原来的切法。
struct RecallPop: View {
    let item: RecallItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var expanded: Set<Int> = []
    @ObservedObject private var fontStore = KakaoPackStore.shared

    private var ink: BuwangInk { BuwangInk(dark: scheme == .dark) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            BuwangPaper(ink: ink)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: -2) {
                        Text("那一刻他想起的").font(BuwangFont.hand(24)).foregroundColor(ink.ink)
                        Text("what surfaced").font(BuwangFont.script(15)).foregroundColor(ink.ink3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 22)
                    if !item.prompt.isEmpty {
                        Text("你说「\(item.prompt)」")
                            .font(BuwangFont.hand(15))
                            .foregroundColor(ink.ink2)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.bottom, 4)
                    }
                    let cards = item.lmcCards
                    if cards.isEmpty {
                        ForEach(Array(item.cards.enumerated()), id: \.offset) { _, card in
                            oldCard(date: card.date, text: card.body)
                        }
                    } else {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { pair in
                            if pair.offset == 0 || cards[pair.offset - 1].section != pair.element.section {
                                Text(pair.element.section)
                                    .font(BuwangFont.hand(16))
                                    .foregroundColor(ink.ink3)
                                    .padding(.top, pair.offset == 0 ? 0 : 6)
                            }
                            card(pair.element, first: pair.offset == 0)
                        }
                        Text("这些是递给他的背景：相关就自然融进话里，不相关就忽略。")
                            .font(.system(size: 10.5))
                            .foregroundColor(ink.ink3)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(ink.cherry)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(ink.card).shadow(color: ink.shadow, radius: 5, x: 0, y: 2))
            }
            .buttonStyle(BuwangPress())
            .padding(14)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func tint(_ section: String) -> Color {
        switch section {
        case "她在说的": return ink.mint
        case "一整卷": return ink.lilac
        case "图": return ink.blue
        case "原话片段": return ink.faint
        default: return ink.pink
        }
    }

    private func card(_ c: RecallCard, first: Bool) -> some View {
        let long = c.section == "一整卷" || c.body.count > 260
        let isOpen = expanded.contains(c.id)
        return HStack(alignment: .top, spacing: 10) {
          VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(c.title.isEmpty ? "无题" : c.title)
                    .font(BuwangFont.hand(c.section == "原话片段" ? 15 : 17))
                    .foregroundColor(ink.ink)
                Spacer(minLength: 0)
            }
            if !c.meta.isEmpty {
                Text(c.meta)
                    .font(.system(size: 10.5))
                    .foregroundColor(ink.ink3)
            }
            if !c.body.isEmpty {
                Text(c.body)
                    .font(.system(size: 13))
                    .foregroundColor(ink.ink2)
                    .lineSpacing(4)
                    .lineLimit(long && !isOpen ? 5 : nil)
                    .textSelection(.enabled)
            }
            if long {
                Text(isOpen ? "收起" : "展开全文")
                    .font(BuwangFont.hand(14))
                    .foregroundColor(ink.cherry)
                    .padding(.top, 2)
            }
          }
          // 0928：图那段右边一张小圆角方图
          if !c.thumb.isEmpty, let url = URL(string: AlcoveAPI.base.absoluteString + c.thumb) {
              AsyncImage(url: url) { img in
                  img.resizable().aspectRatio(contentMode: .fill)
              } placeholder: {
                  Rectangle().fill(ink.ink3.opacity(0.12))
              }
              .frame(width: 64, height: 64)
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
          }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ink.card)
            .shadow(color: ink.shadow, radius: 6, x: 0, y: 3))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(tint(c.section)).frame(width: 4).padding(.vertical, 12)
        }
        .overlay(alignment: .topLeading) {
            if first { BuwangTape(color: tint(c.section)).offset(x: 16, y: -6) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard long else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                if isOpen { expanded.remove(c.id) } else { expanded.insert(c.id) }
            }
        }
    }

    private func oldCard(date: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !date.isEmpty {
                Text(date).font(.system(size: 11)).foregroundColor(ink.ink3)
            }
            Text(text).font(.system(size: 13)).foregroundColor(ink.ink2).lineSpacing(4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ink.card))
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

/// 0917「一键到底」小椭圆的玻璃：iOS 26 用原生玻璃（不染色，跟打字框一致），老系统退回毛玻璃。
private struct TailPillGlassModifier: ViewModifier {
    let fallbackTint: Color
    let fallbackBorder: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .background(fallbackTint, in: Capsule())
                .overlay(Capsule().stroke(fallbackBorder, lineWidth: 1))
        }
    }
}

/// 1001 她要试的玻璃气泡：iOS 26 系统液态玻璃（跟打字框同一种），跟系统一模一样不带颜色（她：「不需要颜色！」）。
/// 设置里「气泡玻璃」滑条照系统那个「透明 ↔ 色调」：0 是最透的 .clear，往右在玻璃上垫一层白（夜里黑）越来越磨砂。
/// 不用 .interactive()，免得跟长按贴表情的缩放打架。系统低于 26 或纸页主题：照旧实心圆角
private struct MessagesBubbleFill: ViewModifier {
    let fill: Color
    let glass: Bool
    @AppStorage("msgGlassFrost") private var frost = 0.3
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        if !glass {
            content.background(fill, in: shape)
        } else if #available(iOS 26.0, *) {
            content
                .background((scheme == .dark ? Color.black : Color.white).opacity(frost * 0.6), in: shape)
                .glassEffect(.clear, in: shape)
        } else {
            content.background(fill, in: shape)
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
            .modifier(HouseColorScheme())
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
/// 0925 工作室也用这个大脑按钮（原生思考面板），放开成 internal
struct NativeThinkingButton: View {
    let text: String
    let color: Color
    /// 0925 工作室用：面板右上角「译」单点直接走 iOS 自带翻译，不调 AI、没有长按菜单
    var iosOnly = false
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: {
            Image(systemName: "brain")
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(color)
                .frame(width: 22, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看原生 Thinking")
        .sheet(isPresented: $presented) {
            if #available(iOS 18.0, *) {
                NativeThinkingSheet(text: text, iosOnly: iosOnly)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(32)
            } else {
                ScrollView { Text(text).padding().textSelection(.enabled) }
            }
        }
    }
}

/// 0925 她问「黑夜模式的这个面板怎么不变黑」：这类面板用的是系统白 / 黑，跟着整页的深浅走；
/// Kakao 的聊天主题没有夜版，整页恒按白天，面板就一直是白的。改成跟全屋白天 / 黑夜开关走（侧边栏同一个开关）。
private struct HouseColorScheme: ViewModifier {
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = "dark"
    private var dark: Bool { _ = houseAppearance; return AlcoveAppearance.isDark }

    func body(content: Content) -> some View {
        content.preferredColorScheme(dark ? .dark : .light)
    }
}

@available(iOS 18.0, *)
private struct NativeThinkingSheet: View {
    let text: String
    var iosOnly = false
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
                let result = try await AlcoveAPI.postRaw("/thinking/translate", body: ["text": text])
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


    /// 右上角「译」。主聊天：单点 AI 润色翻译，长按可选 AI / iOS；
    /// 0925 工作室（iosOnly）：单点直接 iOS 自带翻译，不调 AI，没有长按菜单
    @ViewBuilder private var translateButton: some View {
        let button = Button {
            if translated != nil {
                showTranslation.toggle()
            } else if iosOnly {
                translateIOS()
            } else {
                translateAI()
            }
        } label: {
            Group {
                if translating { ProgressView() }
                else { Text(showTranslation ? "原文" : "译") }
            }.frame(width: 44, height: 44)
        }
        .disabled(translating)
        .accessibilityLabel(showTranslation ? "显示原文" : "翻译成中文")
        if iosOnly {
            button
        } else {
            button.contextMenu {
                Button("AI 润色翻译") { translateAI() }.disabled(translating)
                Button("iOS 翻译") { translateIOS() }.disabled(translating)
            }
        }
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
                translateButton
            }
            .padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 12)
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.secondary)
                    .padding(.horizontal, 22).padding(.bottom, 8)
                HStack {
                    if iosOnly {
                        Button("重试") { translateIOS() }
                    } else {
                        Button("重试 AI 翻译") { translateAI() }
                        Button("改用 iOS 翻译") { translateIOS() }
                    }
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
        .modifier(HouseColorScheme())
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

// MARK: - 1001 贴表情（照 tg：长按气泡 → 一排 emoji ＋ 菜单，能展开全部苹果 emoji；贴上挂在气泡下角，头像在表情左边）

struct ReactTarget: Equatable {
    enum Kind { case text, image, voice }
    let msg: ChatMessage
    let frame: CGRect
    var kind: Kind = .text
    var urls: [URL] = []
    /// 1001 她要「就单独一个气泡」：整屏毛玻璃上面另画一份这条（不再挖洞，洞里会露壁纸）；按哪边缩放；
    /// 看得见的气泡外侧边离框边多远（Kakao 她那边图右边带图案）
    var ghost: AnyView? = nil
    var anchor: UnitPoint = .center
    var edgeInset: CGFloat = 0
    var isUser: Bool { msg.role == "user" }
    static func == (a: ReactTarget, b: ReactTarget) -> Bool { a.msg.id == b.msg.id && a.frame == b.frame }
}

/// 1001 她要的手感：按住全程一直在缩（跟等待一样长），缩满那一刻接弹簧浮起来，中间不停
enum ReactFeel {
    static let hold: Double = 0.38
    static let pressScale: CGFloat = 0.93
    static let liftScale: CGFloat = 1.04
    static var pressAnimation: Animation { .linear(duration: hold) }
    static var releaseAnimation: Animation { .spring(response: 0.3, dampingFraction: 0.62) }
}

/// 全部苹果 emoji（后端 /chat/emoji-list：emoji-datasource 15.1 ＋ CLDR 中文名），拿一次存进 Caches
final class EmojiCatalog: ObservableObject {
    static let shared = EmojiCatalog()
    static let quick = ["❤️", "🥺", "😂", "🫣", "😡", "🐰", "🫶"]
    static let groupIcons = ["😀", "🐻", "🍔", "⚽️", "🚗", "💡", "❤️", "🏳️"]

    struct Item: Identifiable, Hashable {
        let id: Int
        let c: String
        let g: Int
        let k: String
    }

    @Published private(set) var groups: [String] = []
    @Published private(set) var byGroup: [[Item]] = []
    private(set) var items: [Item] = []
    private var loading = false

    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("emoji_zh.json")
    }

    func load() {
        guard items.isEmpty, !loading else { return }
        loading = true
        if let data = try? Data(contentsOf: cacheURL), apply(data) {
            loading = false
            return
        }
        Task {
            let obj = try? await AlcoveAPI.getRaw("/api/chat/emoji-list")
            let data = obj.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            await MainActor.run {
                if let data, self.apply(data) { try? data.write(to: self.cacheURL) }
                self.loading = false
            }
        }
    }

    @discardableResult
    private func apply(_ data: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let g = obj["groups"] as? [String],
              let arr = obj["emoji"] as? [[String: Any]], !arr.isEmpty else { return false }
        var out: [Item] = []
        out.reserveCapacity(arr.count)
        for (i, e) in arr.enumerated() {
            guard let c = e["c"] as? String else { continue }
            out.append(Item(id: i, c: c, g: (e["g"] as? NSNumber)?.intValue ?? 0, k: e["k"] as? String ?? ""))
        }
        var grouped = Array(repeating: [Item](), count: g.count)
        for it in out where it.g >= 0 && it.g < g.count { grouped[it.g].append(it) }
        items = out
        groups = g
        byGroup = grouped
        return true
    }

    func search(_ q: String) -> [Item] {
        let key = q.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return [] }
        return items.filter { $0.c == key || $0.k.lowercased().contains(key) }
    }
}

/// 贴在气泡下角的小片：头像在左、表情在右；两个人都贴了就横着排开（她在前）
struct ReactionChips: View {
    let reactions: [String: String]
    let theme: AlcoveTheme
    @AppStorage("userAvatarDataURL") private var userAvatar = ""
    @AppStorage("assistantAvatarDataURL") private var assistantAvatar = ""
    @AppStorage(KakaoPackStore.usePackAvatarKey) private var usePackAvatar = true

    var body: some View {
        HStack(spacing: 4) {
            ForEach(["user", "assistant"], id: \.self) { who in
                if let e = reactions[who] {
                    HStack(spacing: 3) {
                        avatar(who)
                            .frame(width: 18, height: 18)
                            .clipShape(Circle())
                        Text(e)
                            .font(.system(size: 14))
                            .id(e)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                    .padding(.leading, 3)
                    .padding(.trailing, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(theme.isDark ? Color(red: 44/255, green: 44/255, blue: 46/255) : .white))
                    .overlay(Capsule().stroke(theme.isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 0.8))
                    .shadow(color: .black.opacity(theme.isDark ? 0.25 : 0.07), radius: 2, y: 1)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.55), value: reactions)
    }

    @ViewBuilder
    private func avatar(_ who: String) -> some View {
        if let img = image(who) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            ZStack {
                Circle().fill(who == "user" ? Color(red: 240/255, green: 170/255, blue: 196/255)
                                            : Color(red: 150/255, green: 170/255, blue: 210/255))
                Text(who == "user" ? "霁" : "璟")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
            }
        }
    }

    private func image(_ who: String) -> UIImage? {
        if who == "user" { return Self.decode(userAvatar) }
        let mine = Self.decode(assistantAvatar)
        if theme.isKakao {
            if !usePackAvatar, let m = mine { return m }
            return KakaoPackStore.shared.profileImage ?? mine
        }
        return mine
    }

    private static var cache: [Int: UIImage] = [:]
    private static func decode(_ value: String) -> UIImage? {
        guard !value.isEmpty else { return nil }
        let key = value.hashValue
        if let hit = cache[key] { return hit }
        let payload = value.split(separator: ",", maxSplits: 1).last.map(String.init) ?? value
        guard let img = Data(base64Encoded: payload).flatMap(UIImage.init(data:)) else { return nil }
        cache[key] = img
        return img
    }
}

/// 长按那一下要知道它在屏幕上的位置：背后垫一个不吃点按的 UIView，触发时现量（滚动中也准）
final class ReactFrameProbe {
    weak var view: UIView?
    var globalFrame: CGRect {
        guard let v = view else { return .zero }
        return v.convert(v.bounds, to: nil)
    }
}

private struct ReactFrameProbeView: UIViewRepresentable {
    let probe: ReactFrameProbe
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        probe.view = v
        return v
    }
    func updateUIView(_ v: UIView, context: Context) { probe.view = v }
}

/// 图 / 语音条用：长按直接挂在它本身上（里面的点按照常用），按住先缩、触发时震一下弹起来
struct ReactPressable: ViewModifier {
    let lifted: Bool
    let anchor: UnitPoint
    let onTrigger: (CGRect) -> Void
    @State private var pressing = false
    @State private var probe = ReactFrameProbe()

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressing ? ReactFeel.pressScale : 1, anchor: anchor)
            .animation(pressing ? ReactFeel.pressAnimation : ReactFeel.releaseAnimation, value: pressing)
            .opacity(lifted ? 0 : 1)
            // 垫在缩放外面：量到的是没缩的那个框，整屏那层另画的一份按它摆
            .background(ReactFrameProbeView(probe: probe))
            .onLongPressGesture(minimumDuration: ReactFeel.hold, maximumDistance: 12, perform: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                pressing = false
                onTrigger(probe.globalFrame)
            }, onPressingChanged: { pressing = $0 })
    }
}

private struct ReactPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

/// 长按之后整屏这一层：毛玻璃（被按的气泡那块挖空、它自己在列表里弹起来）＋ 一排 emoji ＋ 菜单；
/// 点 ⌄ 那一排顺着变形成大面板（搜索 ＋ 分类 ＋ 全部 emoji）
struct ReactionOverlay: View {
    enum Action { case copy, ask, copyTurn, edit, select, save, favorite }

    let target: ReactTarget
    let theme: AlcoveTheme
    let canCopyTurn: Bool
    let canEdit: Bool
    let onPick: (String) -> Void
    let onAction: (Action) -> Void
    let onDismiss: () -> Void

    @ObservedObject private var catalog = EmojiCatalog.shared
    @State private var shown = false
    @State private var popped = false
    /// 浮起来那份的大小：从按住缩满的地方起跳，弹到 1.04；收的时候落回 1 再换回列表里那份
    @State private var ghostScale: CGFloat = ReactFeel.pressScale
    @State private var expanded = false
    @State private var picked: String?
    @State private var query = ""
    @State private var jump: Int?
    @Namespace private var ns

    private let barW: CGFloat = 8 * 40 + 16
    private let barH: CGFloat = 52
    private let menuW: CGFloat = 230
    private let rowH: CGFloat = 44

    private var cardFill: Color { theme.isDark ? Color(red: 38/255, green: 38/255, blue: 40/255) : .white }
    private var ink: Color { theme.isDark ? .white : Color(red: 0.2, green: 0.19, blue: 0.2) }
    private var softFill: Color { theme.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05) }
    private var selFill: Color { theme.isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.1) }
    private var mine: String? { target.msg.reactions["user"] }

    private var menuItems: [(Action, String, String)] {
        switch target.kind {
        case .image: return [(.save, "保存到相册", "square.and.arrow.down")]
        case .voice: return [(.favorite, "收藏", "heart")]
        case .text: break
        }
        var out: [(Action, String, String)] = [(.copy, "复制", "doc.on.doc"), (.ask, "询问", "quote.bubble")]
        if canCopyTurn { out.append((.copyTurn, "复制整轮", "doc.on.clipboard")) }
        if canEdit { out.append((.edit, "编辑", "pencil")) }
        out.append((.select, "选择文字", "character.cursor.ibeam"))
        return out
    }

    private static var insets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.safeAreaInsets ?? .zero
    }

    var body: some View {
        GeometryReader { geo in
            let o = geo.frame(in: .global).origin
            let f = target.frame.offsetBy(dx: -o.x, dy: -o.y)
            ZStack(alignment: .topLeading) {
                // 1001 她要「气泡不要带壁纸」：有另画的那份就整屏糊满不挖洞；万一没带（老路）才照旧挖
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(theme.isDark ? 0.28 : 0.06))
                    .mask(holeMask(size: geo.size, hole: target.ghost == nil ? f.insetBy(dx: -8, dy: -8) : .zero))
                    .opacity(shown ? 1 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                if let ghost = target.ghost {
                    ghost
                        .frame(width: f.width, height: f.height)
                        .scaleEffect(ghostScale, anchor: target.anchor)
                        .position(x: f.midX, y: f.midY)
                        .allowsHitTesting(false)
                }
                if shown {
                    if expanded {
                        panel(size: geo.size, f: f)
                    } else {
                        bar(size: geo.size, f: f)
                        menu(size: geo.size, f: f)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            catalog.load()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) { shown = true }
            // 接着按住时的缩，一路弹上去（阻尼小一点，过头再落回 1.04＝弹一弹）
            withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { ghostScale = ReactFeel.liftScale }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { popped = true }
        }
    }

    private func holeMask(size: CGSize, hole: CGRect) -> some View {
        ZStack {
            Rectangle().fill(Color.black)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black)
                .frame(width: max(0, hole.width), height: max(0, hole.height))
                .position(x: hole.midX, y: hole.midY)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .frame(width: size.width, height: size.height)
    }

    private var menuHeight: CGFloat { rowH * CGFloat(menuItems.count) }

    /// 1001 她抓的「最新那条长按，表情条被菜单挡住」：三样谁也不压谁。
    /// 先试「条在上、菜单在下」；下面放不下（贴着底的最新一条）就「菜单、条、气泡」自上而下都摆上面；
    /// 上面也放不下（最顶上那条）就都摆下面；气泡高得哪边都不够，才条贴顶、菜单贴底。
    /// 返回表情条中心的 y、菜单顶的 y
    private func layout(size: CGSize, f: CGRect) -> (barY: CGFloat, menuTop: CGFloat) {
        let top = Self.insets.top + 8
        let bottom = size.height - Self.insets.bottom - 8
        let gap: CGFloat = 10
        let lift = f.height * (ReactFeel.liftScale - 1) / 2   // 浮起来放大，上下各多出这么点
        let up = f.minY - lift, down = f.maxY + lift
        let room = (above: up - top, below: bottom - down)
        let needBar = barH + gap, needMenu = menuHeight + gap
        if room.above >= needBar && room.below >= needMenu {
            return (up - gap - barH / 2, down + gap)
        }
        if room.above >= needBar + needMenu {
            let barY = up - gap - barH / 2
            return (barY, barY - barH / 2 - gap - menuHeight)
        }
        if room.below >= needBar + needMenu {
            let barY = down + gap + barH / 2
            return (barY, barY + barH / 2 + gap)
        }
        return (top + barH / 2, bottom - menuHeight)
    }

    /// 横着：对齐看得见的气泡外侧边（Kakao 她那边扣掉图案那截），出不了屏
    private func edgeX(width w: CGFloat, size: CGSize, f: CGRect) -> CGFloat {
        let pad: CGFloat = 10
        let x0 = target.isUser ? f.maxX - target.edgeInset - w : f.minX + target.edgeInset
        return min(max(x0, pad), size.width - pad - w) + w / 2
    }

    private func barCenter(size: CGSize, f: CGRect) -> CGPoint {
        CGPoint(x: edgeX(width: barW, size: size, f: f), y: layout(size: size, f: f).barY)
    }

    private func bar(size: CGSize, f: CGRect) -> some View {
        let c = barCenter(size: size, f: f)
        return HStack(spacing: 0) {
            ForEach(Array(EmojiCatalog.quick.enumerated()), id: \.element) { i, e in
                Button { pick(e) } label: {
                    Text(e)
                        .font(.system(size: 28))
                        .frame(width: 40, height: 44)
                        .background(Circle().fill(mine == e ? selFill : .clear).frame(width: 38, height: 38))
                        .scaleEffect(picked == e ? 1.4 : (popped ? 1 : 0.2))
                        .opacity(popped ? 1 : 0)
                        .animation(.spring(response: 0.36, dampingFraction: 0.55).delay(Double(i) * 0.025), value: popped)
                        .animation(.spring(response: 0.24, dampingFraction: 0.45), value: picked)
                }
                .buttonStyle(ReactPressStyle())
            }
            Button { expand() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ink.opacity(0.55))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(softFill))
                    .frame(width: 40, height: 44)
                    .scaleEffect(popped ? 1 : 0.2)
                    .opacity(popped ? 1 : 0)
                    .animation(.spring(response: 0.36, dampingFraction: 0.55).delay(7 * 0.025), value: popped)
            }
            .buttonStyle(ReactPressStyle())
        }
        .padding(.horizontal, 8)
        .frame(width: barW, height: barH)
        .background(
            RoundedRectangle(cornerRadius: barH / 2, style: .continuous)
                .fill(cardFill)
                .matchedGeometryEffect(id: "reactCard", in: ns)
                .shadow(color: .black.opacity(theme.isDark ? 0.4 : 0.12), radius: 14, y: 6)
        )
        .position(c)
        .transition(.scale(scale: 0.5, anchor: target.isUser ? .bottomTrailing : .bottomLeading).combined(with: .opacity))
    }

    private func menu(size: CGSize, f: CGRect) -> some View {
        let items = menuItems
        let h = menuHeight
        let top = layout(size: size, f: f).menuTop
        let x = edgeX(width: menuW, size: size, f: f)
        return VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                if i > 0 { Divider().padding(.leading, 16) }
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    let act = item.0
                    close { onAction(act) }
                } label: {
                    HStack {
                        Text(item.1).font(.system(size: 16))
                        Spacer()
                        Image(systemName: item.2).font(.system(size: 15))
                    }
                    .foregroundColor(ink)
                    .padding(.horizontal, 16)
                    .frame(height: rowH)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: menuW)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
                .shadow(color: .black.opacity(theme.isDark ? 0.4 : 0.12), radius: 14, y: 6)
        )
        .position(x: x, y: top + h / 2)
        .transition(.scale(scale: 0.6, anchor: target.isUser ? .topTrailing : .topLeading).combined(with: .opacity))
    }

    private func panel(size: CGSize, f: CGRect) -> some View {
        let w = min(size.width - 20, 380)
        let h: CGFloat = min(360, size.height * 0.5)
        let roomAbove = f.minY - Self.insets.top - 20
        let cy = roomAbove >= h ? f.minY - 12 - h / 2 : Self.insets.top + 8 + h / 2
        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundColor(ink.opacity(0.45))
                TextField("搜索", text: $query)
                    .font(.system(size: 15))
                    .foregroundColor(ink)
                    .submitLabel(.search)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Capsule().fill(softFill))
            if query.isEmpty && !catalog.groups.isEmpty {
                HStack(spacing: 0) {
                    ForEach(0..<min(catalog.groups.count, EmojiCatalog.groupIcons.count), id: \.self) { gi in
                        Button { jump = gi } label: {
                            Text(EmojiCatalog.groupIcons[gi])
                                .font(.system(size: 18))
                                .grayscale(0.7)
                                .opacity(0.75)
                                .frame(maxWidth: .infinity, minHeight: 28)
                        }
                        .buttonStyle(ReactPressStyle())
                    }
                }
            }
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 8)
                    if catalog.groups.isEmpty {
                        LazyVGrid(columns: cols, spacing: 6) {
                            ForEach(EmojiCatalog.quick, id: \.self) { cell($0) }
                        }
                        ProgressView().padding(.top, 12)
                    } else if !query.isEmpty {
                        LazyVGrid(columns: cols, spacing: 6) {
                            ForEach(catalog.search(query)) { cell($0.c) }
                        }
                    } else {
                        LazyVGrid(columns: cols, spacing: 6, pinnedViews: []) {
                            ForEach(Array(catalog.byGroup.enumerated()), id: \.offset) { gi, list in
                                Section(header: groupHeader(gi)) {
                                    ForEach(list) { cell($0.c) }
                                }
                            }
                        }
                    }
                }
                .onChange(of: jump) { gi in
                    guard let gi else { return }
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo("emoji-group-\(gi)", anchor: .top) }
                    jump = nil
                }
            }
        }
        .padding(12)
        .frame(width: w, height: h)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(cardFill)
                .matchedGeometryEffect(id: "reactCard", in: ns)
                .shadow(color: .black.opacity(theme.isDark ? 0.4 : 0.14), radius: 18, y: 8)
        )
        .position(x: size.width / 2, y: cy)
        .transition(.opacity)
    }

    private func groupHeader(_ gi: Int) -> some View {
        Text(gi < catalog.groups.count ? catalog.groups[gi] : "")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(ink.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, gi == 0 ? 0 : 8)
            .padding(.leading, 4)
            .id("emoji-group-\(gi)")
    }

    private func cell(_ e: String) -> some View {
        Button { pick(e) } label: {
            Text(e)
                .font(.system(size: 28))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(mine == e ? selFill : .clear))
                .scaleEffect(picked == e ? 1.35 : 1)
                .animation(.spring(response: 0.24, dampingFraction: 0.45), value: picked)
        }
        .buttonStyle(ReactPressStyle())
    }

    private func expand() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { expanded = true }
    }

    private func pick(_ e: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        picked = e
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            close { onPick(e) }
        }
    }

    private func close(_ then: (() -> Void)? = nil) {
        withAnimation(.easeOut(duration: 0.18)) {
            shown = false
            popped = false
        }
        // 浮起来那份落回原大小，落稳了再换回列表里那份（看不出换过）
        withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) { ghostScale = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.19) {
            onDismiss()
            then?()
        }
    }
}
