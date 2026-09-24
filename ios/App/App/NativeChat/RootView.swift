import SwiftUI

// App 根视图：原生聊天页 + 原生小屋页面。
struct RootView: View {
    @State private var housePage: HouseDestination?
    @State private var activeCall: CallKind?
    /// 0902 一起听大卡缩成小唱片。故意不持久化：每次新开一起听都是展开的
    @State private var listenMinimized = false
    @State private var showHouseDrawer = false
    @State private var showSplash = true
    @State private var showPermissions = false
    @State private var showTerminal = false
    @State private var showRoundtable = false   // 0731 圆桌：她要全屏，所以不走面板那条 sheet
    // 任务#1309/#1310：一起听开着且在放歌，大卡就钉在聊天页顶部，一直在；
    // 聊天在卡下面照聊。卡右上角小叉 = 结束一起听。
    @State private var showChatPlayer = false
    @State private var showChatInsight = false
    @ObservedObject private var listenMusic = MusicModel.shared
    @State private var roundtableUnread = 0
    @State private var latestRoundtableID = 0
    @State private var thinkingEnabled = false
    @State private var thinkingKnown = false
    @State private var switchingThinking = false
    @State private var assistantAsleep = false
    @AppStorage("roundtableLastReadID") private var roundtableLastReadID = 0
    @AppStorage("roundtableReadInitialized") private var roundtableReadInitialized = false
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled = true
    @State private var preparedPanelTexture: UIImage?
    @State private var preparedPanelTextureName = ""
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("assistantAvatarDataURL") private var avatarDataURL = ""
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @ObservedObject private var kakaoPacks = KakaoPackStore.shared   // 0924 Kakao 换包重画顶栏颜色
    @AppStorage(MessagesPalette.stampKey) private var paletteStamp = 0.0
    private var theme: AlcoveTheme { _ = paletteStamp; return .named(themeName) }

    private var avatarImage: UIImage? {
        guard !avatarDataURL.isEmpty else { return nil }
        let parts = avatarDataURL.split(separator: ",", maxSplits: 1)
        let b64 = parts.count == 2 ? String(parts[1]) : avatarDataURL
        guard let data = Data(base64Encoded: b64) else { return nil }
        return UIImage(data: data)
    }

    private var glassStroke: Color { theme.glassBorder }
    private var textDim: Color { theme.textDim }

    // 0827 拍一拍：双击顶栏头像。名字跟着设置走，所以每次把当前设置名一起递过去，
    // 后端拿它生成那行字并存进消息里，以后改名不会倒改旧记录。
    private func sendPat() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            _ = try? await NativeHouseAPI.object(
                "/api/pat/send",
                method: "POST",
                body: ["actor": "chenji",
                       "assistant_name": UserDefaults.standard.string(forKey: "assistantName") ?? "陈璟"])
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            floatingHooks
            ChatView(
                thinkingEnabled: $thinkingEnabled,
                thinkingKnown: thinkingKnown,
                switchingThinking: switchingThinking,
                onToggleThinking: toggleThinking,
                messagesTopBar: theme.isMessages ? { AnyView(messagesTopBar) } : nil
            )
                .blur(radius: showHouseDrawer ? 5.0 : 0)
                .animation(.easeOut(duration: 0.22), value: showHouseDrawer)
            // 信息主题的顶栏挂在 ChatView 的 safeAreaBar 里（系统才给它画顶部渐进模糊），这里不再叠一份
            if !theme.isMessages {
                topBar
                    .blur(radius: showHouseDrawer ? 5.0 : 0)
                    .animation(.easeOut(duration: 0.22), value: showHouseDrawer)
            }
            // 任务#1309/#1310：一起听开着且在放歌 → 大卡常驻聊天页顶部（她的参考图）
            if listenMusic.nowPlaying != nil && listenMusic.togetherOn && !listenMinimized
                && !showTerminal && !showRoundtable && !showHouseDrawer {
                ListenBoardCard(
                    model: listenMusic, dark: theme.isDark,
                    off: { withAnimation(.easeOut(duration: 0.22)) { listenMusic.togetherOn = false } },
                    openPlayer: { showChatPlayer = true },
                    openInsight: { showChatInsight = true },
                    minimize: { withAnimation(.easeOut(duration: 0.22)) { listenMinimized = true } })
                    .padding(.horizontal, 12)
                    // 任务#1345：她要卡顶到灵动岛正下方、把整条顶栏盖住。
                    // 左滑收起后卡只占左半边，右边那排按钮就露出来能点了。
                    .padding(.top, 2)
                    .zIndex(6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if showTerminal {
                ZStack {
                    Color(red: 0.1, green: 0.1, blue: 0.12).ignoresSafeArea()
                    TerminalView(onDismiss: {
                        withAnimation(.easeOut(duration: 0.15)) { showTerminal = false }
                    })
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .zIndex(20)
            }
            if showRoundtable {
                RoundtableView(onDismiss: {
                    markRoundtableRead()
                    withAnimation(.easeOut(duration: 0.15)) { showRoundtable = false }
                })
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .zIndex(21)
            }
            if showHouseDrawer {
                Color.black.opacity(theme.isDark ? 0.045 : 0.025)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeOut(duration: 0.22)) { showHouseDrawer = false } }
                    .transition(.opacity)
                    .zIndex(18)
                GeometryReader { drawerGeo in
                    let drawerWidth = drawerGeo.size.width * 0.80
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: drawerGeo.size.width - drawerWidth)
                        NativeHouseDrawer(
                            drawerWidth: drawerWidth,
                            onClose: { withAnimation(.easeOut(duration: 0.22)) { showHouseDrawer = false } },
                            select: openFromDrawer,
                            roundtableUnread: roundtableUnread
                        )
                        .frame(width: drawerWidth, height: drawerGeo.size.height)
                    }
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        SpatialTapGesture().onEnded { value in
                            guard value.location.x < drawerGeo.size.width - drawerWidth else { return }
                            withAnimation(.easeOut(duration: 0.22)) { showHouseDrawer = false }
                        }
                    )
                }
                .ignoresSafeArea(.container, edges: .all)
                .transition(.move(edge: .trailing))
                .zIndex(19)
            }
            if showSplash {
                SplashView(onEnter: {
                    withAnimation(.easeOut(duration: 0.6)) { showSplash = false }
                })
                    .transition(.opacity)
                    .zIndex(90)
            }
            RemoteScreenSharePrompt()
                .zIndex(100)
        }
        .blur(radius: housePage == nil || theme.isPaper ? 0 : 2.2)
        .animation(.easeOut(duration: 0.20), value: housePage != nil)
        .onAppear {
            prewarmPanelTexture()
            // 0829 原生来电与推送：要通知权限、把前台横幅代理挂上
            AlcoveNotify.shared.setup()
            Task { await refreshThinkingState() }
            // 0821 她要的图片缓存：开门就把最近三天的图悄悄存进手机
            Task.detached(priority: .utility) { await ImageDiskCache.shared.prewarmRecent(days: 3) }
            restoreLiveActivityIfEnabled()
            // 雾玻璃开屏一直停留；只有右下角 Enter 才进入聊天。
        }
        .task {
            while !Task.isCancelled {
                await refreshRoundtableUnread()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
        .task {
            // 0828 心跳降频：这个循环只驱动「他睡着没」的小图标，3s 一问烫手机；
            // 30s 足够——回前台（scenePhase）立刻补刷，消息气泡的沉睡标记走 send 的返回值，不靠它。
            while !Task.isCancelled {
                await refreshSleepState()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
        .onChange(of: themeName) { _ in prewarmPanelTexture() }
        .preferredColorScheme(theme.isDark ? .dark : .light) // 跟 PWA 主题走，不跟系统
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                SensorReporter.shared.appActive()
                Task { await refreshThinkingState() }
                Task { await refreshSleepState() }
                // iOS 杀掉后台进程后，重新进入 Alcove 就把灵动岛恢复到
                // 当前状态，不必再去设置页手动关开一次。
                restoreLiveActivityIfEnabled()
                // 0829 回前台：不用无声音频吊着了
                KeepAlive.shared.stop()
                AlcoveNotify.shared.chatVisible = (housePage == nil)
            }
            else {
                AlcoveLiveActivityController.report("background", ["phase": "\(phase)"])   // 0922 灵动岛日志
                SensorReporter.shared.appBackground()
                AlcoveNotify.shared.chatVisible = false
                // 0829 锁屏保活：进后台瞬间起无声音频，轮询不断，来电和横幅照收
                // 0911 通话中不起：它会把声音会话改成 .playback（只放不录），锁屏打着电话就录不进声、
                // 扬声器也被冲回去。通话自己的录放已经把 App 吊着了，用不着它。
                if phase == .background && !AlcoveNotify.shared.inCall { KeepAlive.shared.start() }
            }
        }
        .onChange(of: housePage) { page in
            AlcoveNotify.shared.chatVisible = (page == nil)
            if page == nil {
                // 0904 她报的：工作室里键盘开着关页，主聊天列表被顶上去半屏不回落。
                // 先把还挂着的键盘收掉，再让主聊天列表无动画回到底（ChatView 收这个通知）。
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                to: nil, from: nil, for: nil)
                NotificationCenter.default.post(name: .alcoveHouseClosed, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .alcoveCallAnswered)) { _ in
            housePage = nil
            activeCall = .incoming   // CallKit 接听 → 进通话页
        }
        .onReceive(NotificationCenter.default.publisher(for: .alcoveNotificationTapped)) { _ in
            housePage = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .alcoveDialRequested)) { _ in
            housePage = nil
            if activeCall == nil { activeCall = .outgoing }
        }
        // 0902 通话可缩小：页收起（activeCall=nil）通话不断，CallHub 浮出胶囊；点胶囊再展开。
        // 其余的 onChange/onReceive 挂在 floatingHooks 那个零尺寸视图上——这条链已经长到
        // 编译器算不动了（0902 第一次构建就报「无法在合理时间内进行类型校验」）。
        .fullScreenCover(item: $activeCall, onDismiss: { CallHub.shared.pageHidden() }, content: callPage)
        .onReceive(NotificationCenter.default.publisher(for: .alcoveShowPermissions)) { _ in
            housePage = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showPermissions = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .alcoveJumpToMessage)) { _ in
            housePage = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .alcoveRequestJumpToMessage)) { note in
            guard let ts = note.object as? String, !ts.isEmpty else { return }
            housePage = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
                NotificationCenter.default.post(name: .alcoveJumpToMessage, object: ts)
            }
        }
        .sheet(isPresented: $showPermissions) {
            PermissionsView()
        }
        .sheet(isPresented: $showChatPlayer) {
            MusicPlayerSheet(model: listenMusic)
                .presentationDetents([.fraction(0.75)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showChatInsight) {
            if let song = listenMusic.nowPlaying {
                SongInsightSheet(song: song)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .fullScreenCover(item: $housePage) { target in
            if target == .album {
                NativeAlbumView()
            } else {
                NativeHouseSheet(
                    initial: target,
                    preparedTexture: preparedPanelTexture,
                    preparedTextureName: preparedPanelTextureName,
                    showTerminal: { showTerminal = true },
                    showRoundtable: { markRoundtableRead(); showRoundtable = true },
                    roundtableUnread: roundtableUnread
                )
            }
        }
        .tint(Color(red: 0.86, green: 0.44, blue: 0.57))
    }

    private func restoreLiveActivityIfEnabled() {
        guard liveActivityEnabled else { return }
        Task {
            // 首次回前台时 ActivityKit 偶尔仍在恢复旧活动列表。短间隔复查两次，
            // 没有活动就重建，有活动则只刷新，不会生成重复灵动岛。
            for delay in [0.0, 0.7, 2.0] {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                guard liveActivityEnabled else { return }
                await AlcoveLiveActivityController.ensureRunning()
            }
        }
    }

    private func refreshRoundtableUnread() async {
        guard let obj = try? await AlcoveAPI.getRaw("/api/roundtable/poll") else { return }
        let records = obj["records"] as? [[String: Any]] ?? []
        let newest = records.compactMap { $0["id"] as? Int }.max() ?? 0
        latestRoundtableID = newest
        if !roundtableReadInitialized {
            roundtableLastReadID = newest
            roundtableReadInitialized = true
            roundtableUnread = 0
            return
        }
        if showRoundtable {
            roundtableLastReadID = newest
            roundtableUnread = 0
        } else {
            roundtableUnread = records.reduce(into: 0) { count, record in
                guard let id = record["id"] as? Int, id > roundtableLastReadID else { return }
                count += 1
            }
        }
    }

    private func markRoundtableRead() {
        roundtableLastReadID = max(roundtableLastReadID, latestRoundtableID)
        roundtableUnread = 0
    }

    // 左头像｜中间留空｜右侧三枚按钮共用一块清透玻璃胶囊
    @ViewBuilder private var topBar: some View {
        if theme.isMessages { messagesTopBar } else { legacyTopBar }
    }

    // 0822 她要的 iMessage 同款顶栏：大头像居中（点了照样进终端页），名字在下；
    // 左上角不放东西，右上角还是那三个胶囊。
    private var messagesTopBar: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 4) {
                if theme.isKakao {
                    // 0924 Kakao 聊天室顶栏：中间只有名字，没有大头像
                    kakaoTitle
                } else {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let img = avatarImage {
                            Image(uiImage: img).resizable().scaledToFill()
                        } else {
                            Circle().fill(theme.bubbleAI)
                                .overlay(Text("R").font(.system(size: 18, design: .serif)).foregroundColor(textDim))
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                    if assistantAsleep {
                        Text("💤").font(.system(size: 15)).offset(x: 6, y: -4)
                    }
                }
                HStack(spacing: 2) {
                    Text(UserDefaults.standard.string(forKey: "assistantName") ?? "陈璟")
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                }
                .foregroundColor(theme.text)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(theme.capsuleTint.opacity(theme.isDark ? 0.9 : 0.7), in: Capsule())
                }
            }
            // 双击先声明才抢得到，单击照旧进终端页
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { sendPat() }
            .onTapGesture { showTerminal = true }
            .frame(maxWidth: .infinity)
            HStack {
                // 0919 她要的：左上角一颗跟右边同款的玻璃胶囊，一扇门，点开挑房间（tmux / SDK / API）
                HStack(alignment: .center, spacing: 0) {
                    topBarControl("door.left.hand.open", size: 15) {
                        NotificationCenter.default.post(name: .alcoveOpenRoomPicker, object: nil)
                    }
                }
                .padding(.horizontal, 2)
                .frame(height: 40)
                .modifier(InteractiveTopBarGlassModifier(
                    fallbackTint: theme.capsuleTint,
                    fallbackBorder: glassStroke
                ))
                .shadow(color: .black.opacity(0.05), radius: 14, x: 0, y: 2)
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 0) {
                    // 0917 她要的「按钮少一点」：搜索、听歌的入口搬到侧边栏 Alcove 右边；
                    // 音符只在正在放歌时冒出来（放起来之后切歌还是一下到位），歌停了就缩回去。
                    topBarControl("phone", size: 14) { activeCall = .outgoing }
                    if listenMusic.nowPlaying != nil {
                        topBarControl("music.note", size: 14) { presentHouse(.music) }
                            .transition(.opacity.combined(with: .scale(scale: 0.7)))
                    }
                    topBarControl("line.3.horizontal", size: 15) { presentHouse(.sidebar) }
                }
                .padding(.horizontal, 2)
                .frame(height: 40)
                .animation(.easeInOut(duration: 0.2), value: listenMusic.nowPlaying != nil)
                .modifier(InteractiveTopBarGlassModifier(
                    fallbackTint: theme.capsuleTint,
                    fallbackBorder: glassStroke
                ))
                .shadow(color: .black.opacity(0.05), radius: 14, x: 0, y: 2)
            }
            .padding(.leading, 12)
            .padding(.trailing, 12)
        }
        .frame(height: theme.isKakao ? 44 : 84)   // 0924 Kakao 顶栏矮一截，贴灵动岛下面
    }

    private var kakaoTitle: some View {
        HStack(spacing: 4) {
            Text(UserDefaults.standard.string(forKey: "assistantName") ?? "陈璟")
                .font(.system(size: 16, weight: .semibold))
            if assistantAsleep { Text("💤").font(.system(size: 13)) }
        }
        .foregroundColor(theme.text)
        .frame(height: 40)
    }

    private var legacyTopBar: some View {
        HStack(alignment: .center, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    glassCircle(size: 40) {
                        if let img = avatarImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                        } else {
                            Text("R")
                                .font(.system(size: 14, design: .serif))
                                .foregroundColor(textDim)
                        }
                    }
                    if assistantAsleep {
                        Text("💤")
                            .font(.system(size: 15))
                            .offset(x: 7, y: -5)
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityLabel("陈璟正在睡觉")
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { sendPat() }
                .onTapGesture { showTerminal = true }
                .frame(width: 44, height: 44)

                // 0919 同上：门，挑房间
                HStack(alignment: .center, spacing: 0) {
                    topBarControl("door.left.hand.open", size: 15) {
                        NotificationCenter.default.post(name: .alcoveOpenRoomPicker, object: nil)
                    }
                }
                .padding(.horizontal, 2)
                .frame(height: 40)
                .modifier(InteractiveTopBarGlassModifier(
                    fallbackTint: theme.capsuleTint,
                    fallbackBorder: glassStroke
                ))
                .shadow(color: .black.opacity(0.05), radius: 14, x: 0, y: 2)
                .padding(.leading, 8)

                Spacer(minLength: 0)

                HStack(alignment: .center, spacing: 0) {
                    topBarControl("phone", size: 14) {
                        activeCall = .outgoing
                    }
                    if listenMusic.nowPlaying != nil {   // 0917 同上：放歌时才冒出来
                        topBarControl("music.note", size: 14) {
                            presentHouse(.music)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                    }
                    topBarControl("line.3.horizontal", size: 15) {
                        presentHouse(.sidebar)
                    }
                }
                .padding(.horizontal, 2)
                .frame(height: 40)
                .animation(.easeInOut(duration: 0.2), value: listenMusic.nowPlaying != nil)
                .modifier(InteractiveTopBarGlassModifier(
                    fallbackTint: theme.capsuleTint,
                    fallbackBorder: glassStroke
                ))
                .shadow(color: .black.opacity(0.05), radius: 14, x: 0, y: 2)
                .frame(height: 44)
        }
        .frame(height: 44)
        .padding(.leading, 15)
        .padding(.trailing, 12)
    }

    private func refreshThinkingState() async {
        if let screen = try? await AlcoveAPI.terminalCapture(lines: 12),
           let enabled = thinkingState(in: screen) {
            thinkingEnabled = enabled
            thinkingKnown = true
        }
    }

    @MainActor private func refreshSleepState() async {
        guard let value = try? await NativeHouseAPI.object("/api/sleep/status") else { return }
        let asleep = value.string("state") == "asleep"
        if asleep != assistantAsleep {
            withAnimation(.easeInOut(duration: 0.2)) { assistantAsleep = asleep }
        }
    }

    private func thinkingState(in screen: String) -> Bool? {
        if screen.contains("thinking:on") { return true }
        if screen.contains("thinking:off") { return false }
        return nil
    }

    private func callPage(_ kind: CallKind) -> some View {
        CallView(kind: kind, onMinimize: { activeCall = nil },
                 session: CallHub.shared.session(for: kind))
    }

    /// 0902 通话胶囊 + 小唱片的联动都挂在这个看不见的零尺寸视图上，
    /// 不往 body 那条主链上再加修饰符（加一条编译器就多算一倍）。
    private var floatingHooks: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .onAppear { syncListenPill() }
            .onChange(of: listenMusic.nowPlaying?.id) { _ in syncListenPill() }
            .onChange(of: listenMusic.togetherOn) { on in
                if on { listenMinimized = false }   // 新开一起听：大卡展开
                syncListenPill()
            }
            .onChange(of: listenMinimized) { _ in syncListenPill() }
            .onChange(of: housePage) { _ in syncListenPill() }
            .onChange(of: showTerminal) { _ in syncListenPill() }
            .onChange(of: showRoundtable) { _ in syncListenPill() }
            .onReceive(NotificationCenter.default.publisher(for: .alcoveListenRestore)) { _ in
                withAnimation(.easeOut(duration: 0.22)) { listenMinimized = false }
            }
            .onReceive(NotificationCenter.default.publisher(for: .alcoveCallRestore)) { _ in
                guard CallHub.shared.session != nil, activeCall == nil else { return }
                activeCall = CallHub.shared.kind
            }
            .onReceive(NotificationCenter.default.publisher(for: .alcoveCallEnded)) { _ in
                activeCall = nil
            }
    }

    /// 0902 小唱片的显示规则：歌在放 && （没开一起听 || 大卡缩小了）
    private func syncListenPill() {
        let show = listenMusic.nowPlaying != nil && (!listenMusic.togetherOn || listenMinimized)
        if show {
            // 只有主聊天页露着（没盖工作室/共读室那些整页）时，点唱片才把大卡叫回来；
            // 否则播放器从最上面那页弹，不顶掉正在看的页
            let canRestore = housePage == nil && !showTerminal && !showRoundtable
            FloatingOverlay.shared.show(id: "listen", defaultY: 230) {
                ListenRecordPill(model: listenMusic, canRestoreCard: canRestore)
            }
        } else {
            FloatingOverlay.shared.hide(id: "listen")
        }
    }

    private func toggleThinking() {
        guard thinkingKnown, !switchingThinking else { return }
        switchingThinking = true
        let oldValue = thinkingEnabled
        Task {
            defer { switchingThinking = false }
            guard let live = try? await AlcoveAPI.liveStream(), !live.active,
                  let screen = try? await AlcoveAPI.terminalCapture() else { return }
            let tail = screen.components(separatedBy: .newlines).suffix(12).joined(separator: "\n")
            guard tail.contains("❯") && !tail.localizedCaseInsensitiveContains("esc to interrupt") else { return }
            do {
                try await AlcoveAPI.terminalSendKey("M-t")
                try? await Task.sleep(nanoseconds: 350_000_000)
                // The picker focuses the current value: Enabled is row one,
                // Disabled row two. Move once toward the requested value.
                try await AlcoveAPI.terminalSendKey(oldValue ? "Down" : "Up")
                try await AlcoveAPI.terminalSendKey("Enter")
                // Mid-conversation changes add a second confirmation screen.
                // Wait for it instead of assuming the terminal renders instantly.
                for _ in 0..<6 {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    if let confirm = try? await AlcoveAPI.terminalCapture(lines: 20),
                       confirm.contains("Do you want to proceed?") {
                        try await AlcoveAPI.terminalSendKey("Enter")
                        break
                    }
                }
            } catch { return }
            for _ in 0..<12 {
                try? await Task.sleep(nanoseconds: 600_000_000)
                if let screen = try? await AlcoveAPI.terminalCapture(lines: 12),
                   let current = thinkingState(in: screen), current != oldValue {
                    thinkingEnabled = current
                    return
                }
            }
        }
    }

    private func topBarControl(
        _ systemName: String,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .light))
                .foregroundColor(textDim)
                .frame(width: 36, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openFromDrawer(_ target: HouseDestination) {
        switch target {
        case .chat:
            withAnimation(.easeOut(duration: 0.2)) { showHouseDrawer = false }
        case .terminal: showTerminal = true
        case .roundtable: markRoundtableRead(); showRoundtable = true
        default:
            presentHouse(target)
        }
    }

    private func presentHouse(_ target: HouseDestination) {
        if target == .sidebar {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) { showHouseDrawer = true }
            return
        }
        let asset = AlcoveTheme.panelNamed(themeName).panelTextureAsset

        if preparedPanelTextureName == asset, preparedPanelTexture != nil {
            housePage = target
            return
        }

        preparePanelTexture(named: asset) { image in
            guard AlcoveTheme.panelNamed(themeName).panelTextureAsset == asset else { return }
            preparedPanelTexture = image
            preparedPanelTextureName = asset
            housePage = target
        }
    }

    private func prewarmPanelTexture() {
        let asset = AlcoveTheme.panelNamed(themeName).panelTextureAsset
        guard preparedPanelTextureName != asset || preparedPanelTexture == nil else { return }

        preparePanelTexture(named: asset) { image in
            guard AlcoveTheme.panelNamed(themeName).panelTextureAsset == asset else { return }
            preparedPanelTexture = image
            preparedPanelTextureName = asset
        }
    }

    private func preparePanelTexture(
        named asset: String,
        completion: @escaping (UIImage?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let prepared = UIImage(named: asset)?.preparingForDisplay()
            DispatchQueue.main.async {
                completion(prepared)
            }
        }
    }

    private func glassCircle<Content: View>(size: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        ZStack { content() }
            .frame(width: size, height: size)
            .background(.ultraThinMaterial, in: Circle())
            .background(theme.glassTint, in: Circle())
            .overlay(Circle().stroke(glassStroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
            .contentShape(Circle())
    }
}

private struct InteractiveTopBarGlassModifier: ViewModifier {
    let fallbackTint: Color
    let fallbackBorder: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = Capsule()
        if #available(iOS 26.0, *) {
            // 0917 她要的：跟打字框同一种原生玻璃。以前多染了一层 tint，深色下糊成一块黑；
            // 打字框是不染色的 .regular.interactive()，这里对齐。
            content
                .glassEffect(.regular.interactive(), in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(fallbackTint, in: shape)
                .overlay(shape.stroke(fallbackBorder, lineWidth: 1))
        }
    }
}
