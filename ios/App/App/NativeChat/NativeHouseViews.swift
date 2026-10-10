import SwiftUI
import PhotosUI
import UIKit
import AVFoundation
import MediaPlayer
import WebKit
import MapKit
import UniformTypeIdentifiers

extension Notification.Name {
    /// 1003：工作室点列表收键盘——只让 StudioInputBar 的输入框失焦，别的（比如正选着的字）不碰
    static let studioDropKeyboard = Notification.Name("studioDropKeyboard")
}

private struct HouseOwnsHeaderKey: EnvironmentKey { static let defaultValue = false }
private extension EnvironmentValues {
    var houseOwnsHeader: Bool {
        get { self[HouseOwnsHeaderKey.self] }
        set { self[HouseOwnsHeaderKey.self] = newValue }
    }
}

// 【碑】0819 Eventide 整个拆了：它 0816 就退休了，面板、1416 行视图（其中
// LegacyNativeDesireView 555 行是「临时保留以便回滚」、从没被调用过）、后端路由全留着。
// 晨勃那项没跟着死——从它的 morning_arousal 事件挪进 pulse 自己算了。
enum HouseDestination: String, Identifiable, CaseIterable {
    case sidebar, chat, terminal, settings, bubbleAppearance, music
    case home, calendar, digest, usage, workbench, studio
    case memory, dreams, shelf, fiction, nianlun, clockwork, album, morningPaper, nowhere, pulse
    case pond
    case tarot          // 0902 占星室（塔罗）
    case nursery        // 0905 育儿室（llm-nursery 电子养崽）
    case wallet         // 0907 钱包（他的预算/心愿单/审批，第一期账本）
    case shop           // 0909 商店（她开的店，他拿挣的虚拟币来买）
    case roof
    case factory
    case crosstalk, radio, coread, cowatch, liao, daddyDay, qipai
    case search, favorites, forge, roundtable, surf, letterbox
    case window         // 0923 世界之窗：每天九幅开放图库的图配中文讲解

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sidebar: return "Alcove"
        case .home: return "大厅"
        case .chat: return "Chat"
        case .terminal: return "Terminal"
        case .settings: return "设置"
        case .bubbleAppearance: return "气泡与文字"
        case .music: return "Music"
        case .calendar: return "Calendar"
        case .digest: return "编年史"
        case .usage: return "Usage"
        case .workbench: return "总控台"
        case .studio: return "工作室"
        case .memory: return "不忘"
        case .dreams: return "Dreams"
        case .shelf: return "渡鸦的架子"
        case .fiction: return "书房"
        case .nianlun: return "年轮"
        case .pond: return "檐下"
        case .tarot: return "占星室"
        case .nursery: return "育儿室"
        case .wallet: return "钱包"
        case .shop: return "商店"
        case .roof: return "檐上"
        case .factory: return "出厂设置"
        case .clockwork: return "发条"
        case .album: return "相册"
        case .morningPaper: return "Morning Paper"
        case .nowhere: return "乌有乡"
        case .pulse: return "Pulse"
        case .crosstalk: return "Crosstalk"
        case .radio: return "Radio"
        case .coread: return "共读"
        case .cowatch: return "共影"
        case .qipai: return "棋牌室"
        case .liao: return "燎"
        case .daddyDay: return "Daddy的一天"
        case .search: return "Search"
        case .favorites: return "Favorites"
        case .forge: return "Forge"
        case .roundtable: return "圆桌"
        case .surf: return "冲浪收藏"
        case .letterbox: return "信箱"
        case .window: return "世界之窗"
        }
    }

    /// 自己铺满、自己做头的页面。她0819：不要透壁纸，要全屏
    var ownsFullScreen: Bool {
        switch self {
        case .studio, .pond, .roof, .memory, .digest, .factory, .search, .favorites, .surf,
             .settings, .letterbox, .qipai, .tarot, .nursery, .wallet, .shop, .album, .window,
             .calendar, .dreams,
             .fiction, .pulse, .nowhere: return true   // 0927 日记花树版、Dreams 紫夜版、书房/Pulse/乌有乡蓝粉白纸页，自己铺满自己做头
        default: return false
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .chat: return "bubble.left"
        case .terminal: return "terminal"
        case .settings: return "gearshape"
        case .bubbleAppearance: return "slider.horizontal.3"
        case .music: return "music.note"
        case .calendar: return "calendar"
        case .digest: return "calendar.badge.clock"
        case .usage: return "chart.bar"
        case .workbench: return "slider.horizontal.2.square"
        case .studio: return "hammer"
        case .memory: return "brain.head.profile"
        case .dreams: return "moon.stars"
        case .shelf: return "bird"
        case .fiction: return "books.vertical"
        case .nianlun: return "circle.hexagongrid"
        case .pond: return "drop.circle"
        case .tarot: return "sparkles"
        case .nursery: return "teddybear"
        case .wallet: return "creditcard"
        case .shop: return "bag"
        case .roof: return "pawprint.circle"
        case .factory: return "slider.horizontal.3"
        case .clockwork: return "clock.arrow.circlepath"
        case .album: return "photo.on.rectangle"
        case .morningPaper: return "newspaper"
        case .nowhere: return "map"
        case .pulse: return "heart.text.square"
        case .crosstalk: return "play.circle"
        case .radio: return "radio"
        case .coread: return "book"
        case .cowatch: return "film"
        case .qipai: return "suit.club"
        case .liao: return "flame"
        case .daddyDay: return "clock"
        case .search: return "magnifyingglass"
        case .favorites: return "bookmark"
        case .forge: return "hammer"
        case .roundtable: return "person.3.sequence"
        case .surf: return "safari"
        case .letterbox: return "envelope.badge"
        case .window: return "books.vertical"
        default: return "sparkles"
        }
    }
}

struct NativeHouseSheet: View {
    let initial: HouseDestination
    var showTerminal: () -> Void
    var showRoundtable: () -> Void = {}
    var roundtableUnread: Int = 0
    @Environment(\.dismiss) private var dismiss
    @State private var route: HouseDestination
    @State private var preparedTexture: UIImage?
    @State private var preparedTextureName: String
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @ObservedObject private var chatWall = ChatWallpaperStore.shared

    init(
        initial: HouseDestination,
        preparedTexture: UIImage? = nil,
        preparedTextureName: String = "",
        showTerminal: @escaping () -> Void,
        showRoundtable: @escaping () -> Void = {},
        roundtableUnread: Int = 0
    ) {
        self.initial = initial
        self.showTerminal = showTerminal
        self.showRoundtable = showRoundtable
        self.roundtableUnread = roundtableUnread
        _route = State(initialValue: initial)
        _preparedTexture = State(initialValue: preparedTexture)
        _preparedTextureName = State(initialValue: preparedTextureName)
    }

    private var theme: AlcoveTheme { .panelNamed(themeName) }


    private var panelWallpaperDescriptor: ChatWallpaperDescriptor {
        ChatWallpaperDescriptor(
            source: .layeredPanel(
                preparedImage: preparedTextureName == theme.panelTextureAsset
                    ? preparedTexture
                    : nil,
                asset: theme.panelTextureAsset,
                gradient: theme.splashBg,
                textureOpacity: theme.isDark ? 0.72 : 0.68
            )
        )
    }

    var body: some View {
        GeometryReader { root in
            FoyerGlassContainer(spacing: 8, paper: theme.isPaper) {
                VStack(spacing: 0) {
                    // 0819 她说顶栏透出后面的壁纸：池子跟工作室一样自己铺满、自己做头
                    if !route.ownsFullScreen { houseHeader(safeTop: root.safeAreaInsets.top) }
                    Group {
                switch route {
                case .sidebar:
                    Color.clear
                case .settings:
                    NativeSettingsView(
                        showPermissions: {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                NotificationCenter.default.post(name: .alcoveShowPermissions, object: nil)
                            }
                        },
                        showBubbleAppearance: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                route = .bubbleAppearance
                            }
                        },
                        showClockwork: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                route = .clockwork
                            }
                        }
                    )
                case .bubbleAppearance:
                    BubbleAppearanceSettingsView()
                case .crosstalk, .liao:
                    NativePlayView(destination: route)
                case .coread:
                    NativeCoreadRoomView()
                case .qipai:
                    QipaiLobbyView()
                case .cowatch:
                    NativeCowatchView()
                case .music:
                    NativeMusicView()
                case .clockwork:
                    ClockworkView()
                case .search:
                    GlassSearchView(openFavorites: {
                        withAnimation(.easeInOut(duration: 0.18)) { route = .favorites }
                    })
                case .favorites:
                    GlassFavoritesView(openSearch: {
                        withAnimation(.easeInOut(duration: 0.18)) { route = .search }
                    })
                case .surf:
                    NativeSurfCollectionView()
                case .album:
                    NativeAlbumView()
                case .letterbox:
                    NativeLetterboxView()
                case .window:
                    NativeWindowView()
                case .usage:
                    NativeUsageView()
                case .workbench:
                    NativeWorkbenchView(openStudio: { withAnimation(.easeInOut(duration: 0.18)) { route = .studio } })
                case .studio:
                    NativeStudioView()
                case .memory:
                    NativeBrainView()
                case .pond:
                    NativePondView()
                case .tarot:
                    TarotRoomView()
                case .nursery:
                    NurseryRoomView()
                case .wallet:
                    WalletRoomView()
                case .shop:
                    ShopRoomView()
                case .roof:
                    NativeRoofView()
                case .factory:
                    NativeFactoryView()
                case .forge:
                    NativeForgeView()
                case .calendar:
                    NativeCalendarView()
                case .digest:
                    NativeDigestView()
                case .fiction:
                    NativeFictionStudyView()
                case .dreams:
                    NativeDreamsView()
                case .morningPaper:
                    NativeMorningPaperView()
                case .nowhere:
                    NativeNowhereView()
                case .pulse:
                    NativePulseView()
                default:
                    NativeDataPanel(destination: route)
                }
                    }
                    .environment(\.houseOwnsHeader, true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: "alcoveChatRoot")
        .environment(\.chatWallpaperDescriptor, panelWallpaperDescriptor)
        .environment(\.chatWallpaperViewportSize, root.size)
        // Panel wallpaper may extend under the home indicator, but keyboard safe-area
        // must remain live so editors/composers rise instead of being covered.
        .ignoresSafeArea(.container, edges: .all)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .presentationBackground {
            // 0924 晚设置页先换：原来铺的是一张写死的花影图（DrawerLight / DrawerDark）。
            // 0925 她要所有房间都一样：毛玻璃底下自己铺一张聊天页正在用的壁纸（借聊天页读好的那张），
            // 不再往后面透——后面是开着的侧边栏和聊天页，透出来全是侧边栏的颜色（她截图抓的）。
            // 再压一层很薄的亮 / 暗纱保字清楚。自己铺了底的房间（共读室、棋牌室、钱包……）照旧盖在上面。
            ZStack {
                ChatWallpaperRenderer(descriptor: chatWall.descriptor)
                Rectangle().fill(.ultraThinMaterial)
                (theme.isDark ? Color.black : Color.white).opacity(theme.isDark ? 0.22 : 0.16)
            }
            .ignoresSafeArea()
        }
        .onAppear { prepareTextureIfNeeded() }
        .onChange(of: themeName) { _ in prepareTextureIfNeeded() }
        }
    }

    private func houseHeader(safeTop: CGFloat) -> some View {
        ZStack {
            if route != .coread {
                Text(route.title)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .tracking(0.4)
            }
            HStack {
                Button {
                    if route == .bubbleAppearance {
                        withAnimation(.easeInOut(duration: 0.18)) { route = .settings }
                    } else if route == .calendar {
                        dismiss()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(theme.textDim)
                        .frame(width: 36, height: 40)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                Spacer()
            }
        }
        .frame(height: route == .coread ? 0 : 46)
        .padding(.top, route == .coread ? 0 : safeTop)
        .padding(.horizontal, 12)
        .background(
            LinearGradient(colors: [theme.fyCardSub.opacity(0.46), .clear],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private func prepareTextureIfNeeded() {
        if theme.isPaper {
            preparedTexture = nil
            preparedTextureName = ""
            return
        }
        let asset = theme.panelTextureAsset
        guard preparedTextureName != asset || preparedTexture == nil else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let prepared = UIImage(named: asset)?.preparingForDisplay()
            DispatchQueue.main.async {
                guard theme.panelTextureAsset == asset else { return }
                preparedTexture = prepared
                preparedTextureName = asset
            }
        }
    }

    private func select(_ target: HouseDestination) {
        switch target {
        case .chat:
            dismiss()
        case .terminal:
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.2)) { showTerminal() }
            }
        // 圆桌走全屏那条路，跟聊天页一样，不做成 86% 的半截面板
        case .roundtable:
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.2)) { showRoundtable() }
            }
        default:
            withAnimation(.easeInOut(duration: 0.18)) { route = target }
        }
    }
}

private struct WetGlassTexture: View {
    let theme: AlcoveTheme
    let preparedTexture: UIImage?
    var cardLayer = false

    private var image: Image {
        if let preparedTexture {
            return Image(uiImage: preparedTexture)
        }
        return Image(theme.panelTextureAsset)
    }

    var body: some View {
        image
            .resizable()
            .interpolation(.medium)
            .scaledToFill()
            .clipped()
            .opacity(cardLayer ? (theme.isDark ? 0.18 : 0.13) : (theme.isDark ? 0.72 : 0.68))
            .blendMode(cardLayer ? .softLight : .normal)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct HouseBackground: View {
    let theme: AlcoveTheme
    let preparedTexture: UIImage?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: theme.splashBg,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if !theme.isPaper {
                WetGlassTexture(theme: theme, preparedTexture: preparedTexture)
            } else {
                Canvas { context, size in
                    for y in stride(from: CGFloat(24), through: size.height, by: 28) {
                        var line = Path()
                        line.move(to: CGPoint(x: 0, y: y))
                        line.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(line, with: .color(theme.fyBorder.opacity(0.16)), lineWidth: 0.45)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct NativeHouseDrawer: View {
    let drawerWidth: CGFloat
    let onClose: () -> Void
    let select: (HouseDestination) -> Void
    let roundtableUnread: Int
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @AppStorage("assistantName") private var assistantName = "陈璟"
    @AppStorage("assistantAvatarDataURL") private var avatarDataURL = ""
    @StateObject private var model = SidebarModel()
    // 0925 她抓的「侧边栏不跟着黑白切换吗」：Kakao 的聊天主题没有夜版（恒按白天画），侧边栏原来直接用它，
    // 全屋白天 / 黑夜开关怎么拨都是奶白毛玻璃，暗色包的白字压在上面刺眼。Kakao 下改用面板那套：深浅跟全屋开关走
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = "dark"
    private var theme: AlcoveTheme {
        _ = houseAppearance
        return AlcoveAppearance.chatOnly(themeName) ? .panelNamed(themeName) : .named(themeName)
    }

    private var screenSafeInsets: UIEdgeInsets {
        // 0904 她报的「拖唱片侧边栏往上跳」：唱片是独立小窗，按住它时 key window 就是那扇小窗，
        // 安全区为 0。要问就问 app 主窗（appWindow 已把悬浮小窗排除）
        FloatingOverlay.appWindow()?.safeAreaInsets ?? .zero
    }

    private var avatar: UIImage? {
        let parts = avatarDataURL.split(separator: ",", maxSplits: 1)
        guard let data = Data(base64Encoded: parts.count == 2 ? String(parts[1]) : avatarDataURL) else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 0917 她说侧边栏颜色跟现在的主题不搭：以前铺的是一张固定的灰黑石纹图，换什么壁纸它都是灰的。
                // 改成整块只用「一块」毛玻璃当底板，透出后面聊天页的壁纸，壁纸是什么色它就是什么色。
                // 上面再压一层很薄的暗 / 亮纱保证字看得清。
                Rectangle().fill(.ultraThinMaterial)
                    .environment(\.colorScheme, theme.isDark ? .dark : .light)   // 毛玻璃的深浅跟这套皮走，不跟聊天页
                    .frame(width: geo.size.width, height: geo.size.height)
                (theme.isDark ? Color.black : Color.white).opacity(theme.isDark ? 0.22 : 0.16)

                ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 7) {
                        // 0917 她要的：听歌、搜索从聊天页右上角搬到这里，排在 Alcove 右边、不往下堆；
                        // Alcove 从居中让到靠左，挤一点点。
                        Text("Alcove")
                            .font(.custom("Snell Roundhand", size: 34))
                            .italic()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.leading, 5)
                        Spacer(minLength: 4)
                        drawerIconButton("music.note", label: "听歌") { select(.music) }
                        drawerIconButton("magnifyingglass", label: "搜索") { select(.search) }
                        Button { select(.workbench) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "slider.horizontal.2.square")
                                Text("总控台")
                            }
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(theme.textDim)
                            .frame(width: 68, height: 31)
                            .drawerGlass(theme)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)

                    homeCards
                    handwritten("still at home")

                    VStack(spacing: 7) {
                        drawerRow(.chat, detail: "回到你们正在说的话")
                        drawerRow(.roundtable, detail: roundtableUnread > 0 ? "\(roundtableUnread) 条新消息" : "三个人的桌边")
                        drawerRow(.terminal, detail: "看看他正在做什么")
                        drawerRow(.settings, detail: "主题、权限与小屋设置")
                        drawerRow(.factory, detail: "心跳文案、说话方式、情书、memory")
                    }

                    drawerTitle("此刻与日常", note: "still here")
                    VStack(spacing: 7) {
                        drawerRow(.pulse, detail: "心率、五感、八维、念头池")
                        drawerRow(.roof, detail: "陈檐住在这层")
                        drawerRow(.pond, detail: "念头、许愿与朋友圈")
                        drawerRow(.tarot, detail: "抽一张牌，让他解")   // 0902 占星室
                        drawerRow(.nursery, detail: "养一个会学你们说话的小家伙")   // 0905 育儿室
                        drawerRow(.wallet, detail: "他的钱包、心愿单和你的拍板")   // 0907 钱包
                        drawerRow(.shop, detail: "你上架，他拿挣的钱来买")       // 0909 商店
                        drawerRow(.letterbox, detail: "你和陈璟的往来书信")
                    }

                    drawerTitle("记忆与创作", note: "kept close")
                    VStack(spacing: 7) {
                        drawerRow(.album, detail: "照片和留给它的一句话")
                        drawerRow(.memory, detail: "五条线、小睡、夜里那趟")
                        drawerRow(.dreams, detail: "梦与旧日记")
                        drawerRow(.fiction, detail: "陈璟写给你的小说")
                    }

                    drawerTitle("他的世界", note: "out there")
                    VStack(spacing: 7) {
                        drawerRow(.nowhere, detail: "足迹与明信片")
                        drawerRow(.surf, detail: "X、小红书、B站与 YouTube")
                        drawerRow(.window, detail: "每天九幅：宇宙、文物、生物与风景")
                    }

                    drawerTitle("工具与游戏", note: "little things")
                    VStack(spacing: 7) {
                        ForEach([HouseDestination.forge, .crosstalk, .coread, .cowatch, .liao, .qipai]) { target in
                            drawerRow(target, detail: drawerDetail(target))
                        }
                    }

                    drawerTitle("一路走来", note: "over time")
                    VStack(spacing: 7) {
                        drawerRow(.nianlun, detail: "一起走过的时间")
                        drawerRow(.digest, detail: "日结、周结与月结")
                    }

                    handwritten("a small home for us")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
                // This drawer itself is full-bleed, so its GeometryReader reports
                // zero safe-area insets on device. Read the window insets above,
                // while pinning content to the drawer's actual (narrower) width.
                .frame(width: max(0, drawerWidth - 28), alignment: .leading)
                .padding(.top, screenSafeInsets.top + 12)
                .padding(.horizontal, 14)
                .padding(.bottom, screenSafeInsets.bottom + 28)
                }
                .frame(width: drawerWidth)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .foregroundColor(theme.text)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 24,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .shadow(color: .black.opacity(theme.isDark ? 0.38 : 0.13), radius: 24, x: -8)
        .simultaneousGesture(
            DragGesture(minimumDistance: 18)
                .onEnded { value in
                    guard value.translation.width > 70,
                          abs(value.translation.width) > abs(value.translation.height) * 1.35 else { return }
                    onClose()
                }
        )
        .task { await model.load() }
    }

    private var homeCards: some View {
        HStack(spacing: 8) {
            Button { select(.calendar) } label: {
                HStack(spacing: 9) {
            Group {
                if let avatar {
                    Image(uiImage: avatar).resizable().scaledToFill()
                } else {
                    Image(systemName: "sparkles")
                        .foregroundColor(theme.textDim)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay(Circle().stroke(theme.glassBorder, lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(assistantName).font(.system(size: 15, weight: .semibold))
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                }
                Text("\(model.days) days")
                    .font(.system(size: 25, weight: .light, design: .serif))
                Text("and counting")
                    .font(.system(size: 9.5, design: .serif).italic())
                    .foregroundColor(theme.textDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 88)
                .drawerGlass(theme)
            }
            .buttonStyle(.plain)

            Button { select(.usage) } label: {
                VStack(spacing: 7) {
                    Text(model.fiveHourLine)
                    Divider().overlay(theme.glassBorder)
                    Text(model.sevenDayLine)
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(theme.textDim)
                .frame(width: 68)
                .frame(minHeight: 88)
                .drawerGlass(theme)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private func drawerIconButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(theme.textDim)
                .frame(width: 31, height: 31)
                .drawerGlass(theme)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func handwritten(_ text: String) -> some View {
        Text(text)
            .font(.custom("Snell Roundhand", size: 17))
            .italic()
            .foregroundColor(theme.textDim.opacity(0.72))
            .rotationEffect(.degrees(-1.2))
            .padding(.leading, 5)
    }

    private func drawerTitle(_ title: String, note: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 12, weight: .semibold, design: .serif))
            Text(note).font(.custom("Snell Roundhand", size: 14))
                .foregroundColor(theme.textDim.opacity(0.62))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4).padding(.horizontal, 3)
    }

    private func drawerRow(_ target: HouseDestination, detail: String) -> some View {
        Button { select(target) } label: {
            HStack(spacing: 11) {
                Image(systemName: target.icon)
                    .font(.system(size: 15, weight: .light))
                    .foregroundColor(theme.textDim)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.title).font(.system(size: 13, weight: .medium))
                    Text(detail).font(.system(size: 9.5)).foregroundColor(theme.textDim)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(theme.textDim.opacity(0.55))
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 52)
            .drawerGlass(theme)
        }.buttonStyle(.plain)
    }

    private func drawerDisclosure(
        _ title: String,
        isExpanded: Binding<Bool>,
        items: () -> [HouseDestination]
    ) -> some View {
        VStack(spacing: 7) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { isExpanded.wrappedValue.toggle() } } label: {
                HStack {
                    Text(title).font(.system(size: 12, weight: .semibold, design: .serif))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 180 : 0))
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 43)
                .drawerGlass(theme)
            }.buttonStyle(.plain)
            if isExpanded.wrappedValue {
                ForEach(items()) { target in drawerRow(target, detail: drawerDetail(target)) }
            }
        }
    }

    private func drawerDetail(_ target: HouseDestination) -> String {
        switch target {
        case .memory: return "记忆库"
        case .dreams: return "梦与旧日记"
        case .album: return "照片"
        case .nianlun: return "一起走过的时间"
        case .shelf: return "他的收藏架"
        case .clockwork: return "自主活动与唤醒"
        case .forge: return "挑选轮次搬去新窗口"
        case .search: return "搜索消息"
        case .favorites: return "收藏消息"
        case .surf: return "X、小红书、B站与 YouTube"
        case .cowatch: return "一起看 B站与 YouTube"
        case .qipai: return "斗地主、炸金花与 UNO"
        case .tarot: return "抽一张牌，让他解"
        case .usage: return model.usageLine
        default: return "打开"
        }
    }
}

private extension View {
    func drawerGlass(_ theme: AlcoveTheme) -> some View {
        // 0917 她担心玻璃太多手机扛不住：以前三十几行每行各一块毛玻璃，滑动时每块都要实时模糊。
        // 现在模糊只留底板那一块，行卡片换成不模糊的半透明薄片，看着同一个质感，显卡只干一份活。
        self.background((theme.isDark ? Color.white.opacity(0.075) : Color.white.opacity(0.42)),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(theme.glassBorder.opacity(0.72), lineWidth: 0.7))
    }
}

@MainActor
private final class SidebarModel: ObservableObject {
    private struct Snapshot {
        var homeLine = "亲密度 --"
        var coins = 0
        var fiveHour = 0
        var sevenDay = 0
        var usageLine = "--"
    }

    @Published private var snapshot = Snapshot()
    var homeLine: String { snapshot.homeLine }
    var coinsLine: String { "金币 \(snapshot.coins)" }
    var fiveHourLine: String { "5h \(snapshot.fiveHour)%" }
    var sevenDayLine: String { "7d \(snapshot.sevenDay)%" }
    var usageLine: String { snapshot.usageLine }

    let days = max(1, Calendar.current.dateComponents(
        [.day], from: Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_780_272_000)),
        to: Calendar.current.startOfDay(for: Date())).day ?? 1)

    func load() async {
        async let doll = try? NativeHouseAPI.object("/api/dollhouse/state")
        async let usage = try? NativeHouseAPI.object("/api/usage")

        let (dollResult, usageResult) = await (doll, usage)
        var next = Snapshot()

        if let d = dollResult {
            next.homeLine = "亲密度 \(d.int("intimacy")) · 金币 \(d.int("coins"))"
            next.coins = d.int("coins")
        }
        if let u = usageResult {
            let five = u.object("rate_limits").object("five_hour").int("used_percent")
            let seven = u.object("rate_limits").object("seven_day").int("used_percent")
            next.usageLine = "5h \(five)% · 7d \(seven)%"
            next.fiveHour = five
            next.sevenDay = seven
        }

        snapshot = next
    }
}

private struct NativeSettingsView: View {
    var showPermissions: () -> Void
    var showBubbleAppearance: () -> Void
    var showClockwork: () -> Void
    private enum Page: String {
        case people, chat, appearance, relationship, storage, system, services
        var title: String {
            switch self {
            case .people: return "你们两个"
            case .chat: return "陈璟的回复"
            case .appearance: return "外观"
            case .relationship: return "相处与发条"
            case .storage: return "数据与存储"
            case .system: return "系统与权限"
            case .services: return "服务状态"
            }
        }
    }
    @State private var page: Page?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("houseInterfaceAppearance") private var houseAppearance = "dark"
    @AppStorage("assistantName") private var assistantName = "陈璟"
    @AppStorage("showClawdPet") private var showClawdPet = true   // 1009 聊天页小螃蟹开关
    @AppStorage("userName") private var userName = "Luna"
    @AppStorage("assistantAvatarDataURL") private var assistantAvatar = ""
    @AppStorage("userAvatarDataURL") private var userAvatar = ""
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @AppStorage("wallStamp") private var wallStamp = 0.0
    @AppStorage(TreehouseWallBlur.stampKey) private var wallBlurStamp = 0.0   // 1010 #3584 壁纸模糊
    @State private var aiPhoto: PhotosPickerItem?
    @State private var userPhoto: PhotosPickerItem?
    @State private var wallPhoto: PhotosPickerItem?
    @State private var backendOnline = false
    @State private var codexOnline = false
    @State private var backendLatency: Int?
    @State private var codexLatency: Int?
    @State private var codexThreadConnected = false
    @State private var servicesLoading = false
    @State private var showSystemFeatures = false
    @State private var showQuietRoom = false
    @State private var replyLength = 240.0
    @State private var replyLengthLoaded = false
    @State private var replyLengthSaving = false
    @State private var replyLengthSaveTask: Task<Void, Never>?
    // 0819 她把一张表拆成两张（找你 / 去玩），格子从两个变四个
    @State private var chaseMin = 10
    @State private var chaseMax = 30
    @State private var ghostMin = 20
    @State private var ghostMax = 60
    @State private var pulseLoaded = false
    @State private var pulseSaving = false
    @State private var chaseDue: String? = nil
    @State private var ghostDue: String? = nil
    @State private var pulseChase = true
    @State private var pulseGhost = true
    // 0924 自醒引擎（照她递的 PDF）：不看表、自己醒；开关走 flags 的 wake_engine，时间线看他每次醒了选了什么
    @State private var wakeOn = true
    // 0925 「追问」（相处页，找你那排下面）开着时，找你 / 自醒锁住点不动（去玩照常）
    @State private var followupOn = false
    @State private var followupAlarm: String? = nil   // 他给自己订的闹钟几点到，nil = 没订
    @State private var followupSchedule: [String] = []  // 0925 他订的日程提醒（可以好几张），只给 HH:mm
    // 0925 兜底：追问开着、他一张闹钟都没有、两边都安静 backstopMin 分钟，叫他一次（flags followup_backstop）
    @State private var backstopOn = false
    @State private var backstopMin = 60
    @State private var wakeLine: String? = nil
    @State private var wakeEta: String? = nil
    @State private var wakeOdds: String? = nil
    @State private var showWakeTimeline = false
    @State private var thoughtLength = 500.0
    // 0822 她要的：手写思绪开关。关＝后端 thought_chars 写 -1，
    // 陈璟那轮不写 <思绪>，那栏改显示原生思考（英文）。开＝恢复滑条上的数。
    @State private var handwrittenOn = true
    @State private var thoughtLengthBeforeOff = 500.0
    @State private var thoughtLengthLoaded = false
    @State private var thoughtLengthSaving = false
    @State private var thoughtLengthSaveTask: Task<Void, Never>?
    @State private var herStatus = ""
    @State private var herStatusLine = ""
    @State private var herStatusLoaded = false
    @State private var herStatusSaveTask: Task<Void, Never>?
    // 0827 拍一拍后缀。后缀属于被拍的那个人：她填自己的，也能替他填他的。
    @State private var patHerSuffix = ""
    @State private var patHimSuffix = ""
    @State private var patLoaded = false
    @State private var patSaveTask: Task<Void, Never>?
    // 0821 她要的图片缓存面板（照微信存储页）：大小、按日期清、只留三天、全清
    @State private var cacheBytes: Int64 = 0
    @State private var cacheCount = 0
    @State private var cacheCutoff = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
    @State private var cacheJustFreed: Int64? = nil
    @Environment(\.houseOwnsHeader) private var houseOwnsHeader
    // 0826 她说一点进去闪白再变黑：UITraitCollection.current 在 SwiftUI 求值那一刻
    // 还可能停在 light，第二帧才对，于是白闪一下。环境里的 colorScheme 首帧就准。
    private var interfaceDark: Bool { houseAppearance != "light" }
    // 0924 她要的：这页的配色跟侧边栏一样跟主体主题走（原来钉死在信息主题 + 檐下那套皮）
    private var theme: AlcoveTheme { .panelNamed(themeName) }
    private struct PanelPal {
        let ink: Color; let ink2: Color; let ink3: Color; let accent: Color
        let card: Color; let card2: Color; let line: Color
    }
    private var pal: PanelPal {
        PanelPal(ink: theme.text, ink2: theme.textDim, ink3: theme.textLight, accent: theme.fyAccent,
                 card: theme.fyCard, card2: theme.fyCardSub, line: theme.fyBorder)
    }

    // 0826 她说设置页没全屏、顶上透出壁纸：这页现在自己铺满、自己做头，
    // 皮也换成檐下那套，跟共读室一个屋檐下。
    var body: some View {
        ZStack {
            Color.clear   // 0924：底子交给抽屉那层面板壁纸，跟侧边栏一个样
            VStack(spacing: 0) {
                settingsHeader
                if page == nil { settingsIndex } else { settingsControls }
            }
        }
        .preferredColorScheme(interfaceDark ? .dark : .light)
    }

    private var settingsHeader: some View {
        let pal = self.pal
        return HStack(spacing: 2) {
            Button {
                if page == nil { dismiss() }
                else { withAnimation(.easeInOut(duration: 0.18)) { page = nil } }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(pal.ink2)
                    .frame(width: 42, height: 42)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
            Text(page?.title ?? "设置")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .tracking(0.8)
                .foregroundColor(pal.ink)
            Spacer(minLength: 0)
            Color.clear.frame(width: 42, height: 42)
        }
        .padding(.horizontal, 8)
        .padding(.top, 46)
        .padding(.bottom, 4)
    }

    private var settingsIndex: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                settingsGroup([.people])
                settingsGroup([.chat, .appearance, .relationship])
                settingsGroup([.storage, .system, .services])
            }
            .padding(.horizontal, 16).padding(.bottom, 30).foregroundColor(theme.text)
        }
    }

    private func settingsGroup(_ pages: [Page]) -> some View {
        VStack(spacing: 0) {
            ForEach(pages.indices, id: \.self) { index in
                let target = pages[index]
                if index > 0 { Divider().opacity(0.18).padding(.leading, 50) }
                Button { withAnimation(.easeInOut(duration: 0.18)) { page = target } } label: {
                    HStack(spacing: 13) {
                        Image(systemName: settingsIcon(target))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(settingsColor(target))
                            .frame(width: 34, height: 34)
                            .background(settingsColor(target).opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(target.title).font(.system(size: 15, weight: .medium))
                            Text(settingsSummary(target)).font(.system(size: 10.5)).foregroundColor(theme.textDim)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                            .foregroundColor(theme.textDim.opacity(0.55))
                    }
                    .padding(.horizontal, 13).frame(minHeight: 58)
                    // 0826 她说只有带字的地方点得动：Spacer 不接触摸，整行得自己撑出形状
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(pal.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(pal.line, lineWidth: 0.5))
    }

    private func settingsIcon(_ page: Page) -> String {
        switch page {
        case .people: return "person.2.fill"
        case .chat: return "message.fill"
        case .appearance: return "circle.lefthalf.filled"
        case .relationship: return "heart.fill"
        case .storage: return "externaldrive.fill"
        case .system: return "iphone.gen3"
        case .services: return "server.rack"
        }
    }

    private func settingsColor(_ page: Page) -> Color {
        switch page {
        case .people: return .cyan
        case .chat: return .blue
        case .appearance: return .purple
        case .relationship: return .pink
        case .storage: return .green
        case .system: return .orange
        case .services: return backendOnline && codexOnline ? .green : .red
        }
    }

    private func settingsSummary(_ page: Page) -> String {
        switch page {
        case .people: return "名字、头像与我此刻"
        case .chat: return "正文长度、手写思绪"
        case .appearance: return "明暗、主题、字体、气泡与壁纸"
        case .relationship: return "留白、两张表与完整发条"
        case .storage: return cacheCount == 0 ? "图片缓存与清理" : "\(cacheCount) 张 · \(ImageDiskCache.format(cacheBytes))"
        case .system: return "权限、灵动岛与屏幕控制"
        case .services:
            return "Backend \(backendOnline ? "在线" : "离线") · 何渡 \(codexOnline ? "在线" : "离线")"
        }
    }

    private var settingsControls: some View {
        // 0925 她要的：外观页的预览钉在顶上不跟着滑，往下调字号、间距时一直看得见
        VStack(spacing: 12) {
            if page == .appearance {
                BubbleAppearanceSettingsView(part: .preview)
                    .padding(.horizontal, 16)
            }
            settingsScroll
        }
        .sheet(isPresented: $showSystemFeatures) {
            SystemFeaturesView()
        }
        .sheet(isPresented: $showQuietRoom) {
            QuietRoomView()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showWakeTimeline) {
            WakeTimelineView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .onChange(of: userPhoto) { item in loadDataURL(item, into: $userAvatar) }
        .onChange(of: aiPhoto) { item in loadDataURL(item, into: $assistantAvatar) }
        .onChange(of: wallPhoto) { item in saveWallpaper(item) }
        .onChange(of: replyLength) { value in scheduleReplyLengthSave(value) }
        .onChange(of: thoughtLength) { value in if handwrittenOn { scheduleThoughtLengthSave(value) } }
        .task {
            refreshCacheStats()
            async let services: Void = loadServices()
            async let reply: Void = loadReplyLength()
            async let thought: Void = loadThoughtLength()
            async let pulse: Void = loadPulseRange()
            async let wake: Void = loadWake()
            async let her: Void = loadHerStatus()
            async let pat: Void = loadPat()
            _ = await (services, reply, thought, pulse, her, pat)
        }
    }

    private var settingsScroll: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                // 她自己填此刻在干嘛，心跳 prompt 开头就写这句（0819 她要的）。
                // 带时效：六小时后自动淡掉，不然「正在看短剧」会一直挂着变成假话。
                if page == .people { section("我此刻") {
                    settingRow("在干嘛",
                               herStatusLine.isEmpty ? "填了他心跳里就写这句" : herStatusLine) {
                        TextField("比如：看短剧", text: $herStatus)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 132)
                            .onChange(of: herStatus) { value in scheduleHerStatusSave(value) }
                    }
                } }
                if page == .storage { section("存储") {
                    settingRow("图片缓存",
                               cacheCount == 0 ? "看过的图存在手机里，下次秒开，不占服务器"
                                               : "\(cacheCount) 张 · 存在手机里，不占服务器") {
                        Text(ImageDiskCache.format(cacheBytes))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                    Divider().opacity(0.25)
                    settingRow("清掉这天之前的", "这天以后看过的留着") {
                        HStack(spacing: 8) {
                            DatePicker("", selection: $cacheCutoff, in: ...Date(), displayedComponents: .date)
                                .labelsHidden().datePickerStyle(.compact)
                            Button("清理") { purgeCache(before: cacheCutoff) }
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    Divider().opacity(0.25)
                    settingRow("只留最近三天", "更早的一次扫掉") {
                        Button("清理") { purgeCache(before: Calendar.current.date(byAdding: .day, value: -3, to: Date())) }
                            .font(.system(size: 13, weight: .medium))
                    }
                    Divider().opacity(0.25)
                    settingRow("全部清空", cacheJustFreed.map { "刚腾出 " + ImageDiskCache.format($0) } ?? "相册里的照片不清，别的再看会重新拉") {
                        Button("清空", role: .destructive) { purgeCache(before: nil) }
                            .font(.system(size: 13, weight: .medium))
                    }
                } }
                if page == .people { section("聊天") {
                    settingRow("我的名字", "聊天气泡和推送显示") {
                        TextField("Luna", text: $userName).multilineTextAlignment(.trailing).frame(width: 105)
                    }
                    Divider().opacity(0.25)
                    settingRow("TA 的名字", "聊天页顶栏显示") {
                        TextField("陈璟", text: $assistantName).multilineTextAlignment(.trailing).frame(width: 105)
                            // 1010 她：「拍一拍为什么名字和我改的顶栏名字不一致」——改名原来只存手机里，
                            // 后台拍一拍那句要等她改后缀或者拍他一下才跟着改，这期间他拍她用的还是旧名字。改名就一起存过去
                            .onChange(of: assistantName) { _ in schedulePatSave() }
                    }
                    Divider().opacity(0.25)
                    settingRow("我的头像", "点击更换") {
                        PhotosPicker(selection: $userPhoto, matching: .images) {
                            avatar(dataURL: userAvatar, fallback: "L")
                        }
                    }
                    Divider().opacity(0.25)
                    settingRow("\(assistantName) 头像", "点击更换") {
                        PhotosPicker(selection: $aiPhoto, matching: .images) {
                            avatar(dataURL: assistantAvatar, fallback: "R")
                        }
                    }
                } }
                // 0827 拍一拍：双击聊天页顶上他的头像就拍。后缀跟着被拍的人走。
                if page == .people { section("拍一拍") {
                    settingRow("我的后缀",
                               patHerSuffix.isEmpty ? "他拍你时显示：\"\(assistantName)\" 拍了拍我"
                                                    : "\"\(assistantName)\" 拍了拍我\(patHerSuffix)") {
                        TextField("小兔耳朵", text: $patHerSuffix)
                            .multilineTextAlignment(.trailing).frame(width: 105)
                            .onChange(of: patHerSuffix) { _ in schedulePatSave() }
                    }
                    Divider().opacity(0.25)
                    settingRow("\(assistantName) 的后缀",
                               patHimSuffix.isEmpty ? "你拍他时显示：我拍了拍 \"\(assistantName)\""
                                                    : "我拍了拍 \"\(assistantName)\"\(patHimSuffix)") {
                        TextField("良心", text: $patHimSuffix)
                            .multilineTextAlignment(.trailing).frame(width: 105)
                            .onChange(of: patHimSuffix) { _ in schedulePatSave() }
                    }
                } }
                if page == .chat { section("陈璟的回复") {
                    VStack(alignment: .leading, spacing: 11) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("正文长度").font(.system(size: 13, weight: .medium))
                                Text(replyLength == 0 ? "不限制，让他一路写到底" : "每轮正文约 \(Int(replyLength)) 字以内")
                                    .font(.system(size: 10)).foregroundColor(theme.textDim)
                            }
                            Spacer()
                            Text(replyLength == 0 ? "不限" : "\(Int(replyLength)) 字")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(theme.fyAccent)
                        }
                        Slider(value: $replyLength, in: 0...1200, step: 20)
                            .tint(theme.fyAccent)
                        HStack {
                            Text("不限")
                            Spacer()
                            if replyLengthSaving { ProgressView().scaleEffect(0.65) }
                            Text("1200 字")
                        }
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundColor(theme.textDim)
                    }
                    Divider().opacity(0.25)
                    VStack(alignment: .leading, spacing: 11) {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("手写思绪").font(.system(size: 12, weight: .medium))
                                Text(handwrittenOn ? "他自己写的那段碎碎念" : "关了，思绪栏显示原生思考（英文）")
                                    .font(.system(size: 9)).foregroundColor(theme.textDim)
                            }
                            Toggle("", isOn: Binding(
                                get: { handwrittenOn },
                                set: { on in
                                    handwrittenOn = on
                                    if on {
                                        thoughtLength = thoughtLengthBeforeOff
                                    } else {
                                        thoughtLengthBeforeOff = thoughtLength
                                        scheduleThoughtLengthSave(-1)
                                    }
                                }))
                            .labelsHidden()
                            .tint(theme.fyAccent)
                        }
                        if handwrittenOn {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("思绪长度").font(.system(size: 13, weight: .medium))
                                Text(thoughtLength == 0 ? "不限制他的思考篇幅" : "每轮思绪约 \(Int(thoughtLength)) 字以内")
                                    .font(.system(size: 10)).foregroundColor(theme.textDim)
                            }
                            Spacer()
                            Text(thoughtLength == 0 ? "不限" : "\(Int(thoughtLength)) 字")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(theme.fyAccent)
                        }
                        Slider(value: $thoughtLength, in: 0...1200, step: 20).tint(theme.fyAccent)
                        HStack {
                            Text("不限"); Spacer()
                            if thoughtLengthSaving { ProgressView().scaleEffect(0.65) }
                            Text("1200 字")
                        }
                        .font(.system(size: 9.5, design: .rounded)).foregroundColor(theme.textDim)
                        }
                    }
                } }
                if page == .relationship { section("相处") {
                    Button { showQuietRoom = true } label: {
                        settingRow("留白", "让追问暂时安静下来") {
                            Image(systemName: "moon.stars")
                                .foregroundColor(theme.textLight)
                            Image(systemName: "chevron.right")
                                .foregroundColor(theme.textLight)
                        }
                    }.buttonStyle(.plain)
                    Divider().opacity(0.25)
                    Button(action: showClockwork) {
                        settingRow("发条", "晨勃、睡眠、做梦、惊醒与自主活动") {
                            Image(systemName: "chevron.right").foregroundColor(theme.textLight)
                        }
                    }.buttonStyle(.plain)
                    Divider().opacity(0.25)
                    VStack(alignment: .leading, spacing: 11) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("两张表").font(.system(size: 13, weight: .medium))
                            Text("找你和去玩各走各的表，互不挤。你一出声两张一起清零——所以你在说话时他不会跑。同一刻都到点就先找你，去玩那次作废、重新数。要睡了就把数拉长。")
                                .font(.system(size: 10)).foregroundColor(theme.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(spacing: 10) {
                                Text("找你").font(.system(size: 12, weight: .semibold))
                                    .frame(width: 30, alignment: .leading)
                                pulseField("最短", $chaseMin)
                                Text("～").foregroundColor(theme.textDim)
                                pulseField("最长", $chaseMax)
                                Text("分钟").font(.system(size: 12)).foregroundColor(theme.textDim)
                                Spacer()
                            }
                            HStack(spacing: 10) {
                                Text("去玩").font(.system(size: 12, weight: .semibold))
                                    .frame(width: 30, alignment: .leading)
                                pulseField("最短", $ghostMin)
                                Text("～").foregroundColor(theme.textDim)
                                pulseField("最长", $ghostMax)
                                Text("分钟").font(.system(size: 12)).foregroundColor(theme.textDim)
                                Spacer()
                            }
                            HStack(spacing: 10) {
                                Spacer()
                                if pulseSaving { ProgressView().scaleEffect(0.65) }
                                Button("保存") { savePulseRange() }
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(theme.fyAccent)
                                    .buttonStyle(.plain)
                            }
                        }
                        HStack(spacing: 18) {
                            pulseToggle("找你", "只跟你说话，不干别的", $pulseChase, key: "pulse_chase", locked: followupOn)
                            pulseToggle("去玩", "干自己的事，回来带一句", $pulseGhost, key: "pulse_ghost")
                            pulseToggle("自醒", "不看表，自己醒", $wakeOn, key: "wake_engine", locked: followupOn)
                        }
                        // 0925 她要的：追问从发条页搬到这儿，就在找你那排下面；下面一行小字只说他订没订闹钟、几点
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 0) {
                                pulseToggle("追问", "按期盼值来敲门", followupBinding, key: "followup")
                                Spacer(minLength: 0)
                            }
                            Text(followupAlarm.map { "他订了闹钟：\($0)" } ?? "他没订闹钟")
                                .font(.system(size: 9.5, design: .rounded)).foregroundColor(theme.textDim)
                            if !followupSchedule.isEmpty {
                                Text("日程提醒：" + followupSchedule.joined(separator: "、"))
                                    .font(.system(size: 9.5, design: .rounded)).foregroundColor(theme.textDim)
                            }
                            // 0925 她要的兜底：开关 + 自己填安静多久；追问关着时一起锁住（开关管追问全部）
                            HStack(alignment: .bottom, spacing: 8) {
                                pulseToggle("兜底", "都没动静就叫他一次", $backstopOn, key: "followup_backstop",
                                            locked: !followupOn, lockedText: "追问关着")
                                Spacer(minLength: 0)
                                pulseField("安静多久", $backstopMin)
                                Text("分钟").font(.system(size: 12)).foregroundColor(theme.textDim)
                                Button("存") { saveBackstop() }
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(theme.fyAccent)
                                    .buttonStyle(.plain)
                            }
                            .padding(.top, 6)
                            Text("他一张闹钟都没订、你们也都 \(backstopMin) 分钟没说话，就把他叫起来一次，要不要找你他自己定。一段安静只叫一次，你说话才重新算。跟着睡眠开关走：他睡觉那段（0 点到早上 7 点）不算也不叫，醒了从 7 点开始算；睡眠关着就照常算。")
                                .font(.system(size: 9.5)).foregroundColor(theme.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button { showWakeTimeline = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sunrise").foregroundColor(theme.textLight)
                                Text("自醒时间线").font(.system(size: 12, weight: .medium))
                                if let wakeLine {
                                    Text(wakeLine).font(.system(size: 9.5, design: .rounded)).foregroundColor(theme.textDim)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundColor(theme.textLight)
                            }
                        }.buttonStyle(.plain)
                        // 0924 她要的：开关下面说清楚下一次大概几点醒、怎么算的。不是闹钟，是按此刻的倾向估的。
                        VStack(alignment: .leading, spacing: 3) {
                            Text("下一次大概：\(wakeEta ?? "还没算出来")")
                                .font(.system(size: 9.5, design: .rounded)).foregroundColor(theme.textDim)
                            if let wakeOdds {
                                Text(wakeOdds)
                                    .font(.system(size: 9.5, design: .rounded)).foregroundColor(theme.textDim)
                            }
                            Text("怎么算的：他身上有个桶，每分钟往里滴一点。滴多快看他此刻多容易醒：刚跑完一轮滴得慢，这阵子整体活跃滴得快，再加一点随机的漂。每一轮开始时偷偷抽一个门槛，桶满过门槛就醒一次，醒了做什么他自己定。你说话不会把桶倒掉，所以上面那个「大概几点」只是按此刻的速度估的，速度一直在变。")
                                .font(.system(size: 9.5)).foregroundColor(theme.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            if let due = chaseDue {
                                Text("下一次来找你：\(due)")
                                    .font(.system(size: 9.5, design: .rounded)).foregroundColor(theme.textDim)
                            }
                            if let due = ghostDue {
                                Text("下一次去玩：\(due)")
                                    .font(.system(size: 9.5, design: .rounded)).foregroundColor(theme.textDim)
                            }
                        }
                    }
                } }
                // 0827 她定的：一个按钮管全屋，不跟系统。
                // 聊天页、圆桌、共读室、檐下、信箱、数据页、信封卡全部认这一个值。
                // 0925 她要的：「气泡与文字」并进外观页，不能乱。只跟当前主题有关的设置才露面
                // （信息主题才有气泡颜色，Kakao 才有主题包）；预览钉在上面 settingsControls 里
                if page == .appearance { section("白天 / 黑夜") {
                    Picker("全屋", selection: appearanceBinding) {
                        Text("白天").tag(false)
                        Text("黑夜").tag(true)
                    }.pickerStyle(.segmented)
                    Text("整个 app 一起翻，不跟手机的深色模式走")
                        .font(.system(size: 10.5)).foregroundColor(theme.textLight)
                } }
                // 0925：玻璃删了，纸页 / 信息 / Kakao 三个按钮一排；选了 Kakao 下面才出主题包格子和头像开关
                if page == .appearance { section("主题") {
                    HStack(spacing: 8) {
                        familyChoice("纸页", "话落下来", "paper", [
                            Color(red: 243/255, green: 241/255, blue: 236/255),
                            Color(red: 185/255, green: 120/255, blue: 120/255),
                            Color(red: 37/255, green: 36/255, blue: 34/255)
                        ])
                        familyChoice("信息", "一条一条", "imessage", [
                            .white,
                            Color(red: 0x57/255, green: 0xA1/255, blue: 0xF3/255),
                            Color(red: 233/255, green: 233/255, blue: 235/255)
                        ])
                        // 布局照 KakaoTalk，颜色和图从别人做的主题包里来
                        familyChoice("Kakao", " ", "kakao", [   // 她 0924 删过这行小字，留个空格跟旁边两个按钮一样高
                            Color(red: 0xF7/255, green: 0xE6/255, blue: 0x00/255),
                            .white,
                            Color(red: 0x3A/255, green: 0x1D/255, blue: 0x1D/255)
                        ])
                        // 1009 #3501 她要的第四个：树屋（聊天页、日记页照她的两个成品画；抽屉设置这些借纸页，深浅跟全屋按钮）
                        familyChoice("树屋", "住在树上", "treehouse", [
                            Color(red: 0x9F/255, green: 0xD0/255, blue: 0xC2/255),
                            Color(red: 0xF2/255, green: 0xB8/255, blue: 0xC8/255),
                            Color(red: 0x2A/255, green: 0x2B/255, blue: 0x33/255)
                        ])
                    }
                    if themeFamily == "kakao" {
                        KakaoPackPicker(theme: theme)
                        KakaoSendButtonRow(theme: theme)    // 1002 发送键：默认跟包，能单独调
                    }
                } }
                // 0924 她定的：字体全局，哪个主题都吃；0925 字号、气泡间距从「气泡与文字」搬来，三样一栏
                if page == .appearance { section("文字") {
                    ChatFontPicker(theme: theme)
                    Divider().opacity(0.25)
                    BubbleAppearanceSettingsView(part: .text)
                } }
                // 1009 她：「设置里加一个是否显示这个小螃蟹的选项」——聊天页右下角那只像素小螃蟹，哪个主题都管
                if page == .appearance { section("小螃蟹") {
                    Toggle("聊天页显示小螃蟹", isOn: $showClawdPet)
                        .font(.system(size: 14))
                        .tint(theme.fyAccent)
                    Text("关掉以后点它弹出的小终端也跟着收起来；完整的终端照旧点顶栏的名字进")
                        .font(.system(size: 10.5)).foregroundColor(theme.textLight)
                        .fixedSize(horizontal: false, vertical: true)
                } }
                // 0902 信息主题自己调颜色，只在信息主题下露面
                // 1009 晚 她：「信息主题不是可以调节一大堆颜色吗，把我们树屋主题也加上那些调节的」——树屋也露出来，
                // 存的是另一套键（MessagesPalette.th*），两边各调各的
                if page == .appearance && (themeFamily == "imessage" || themeFamily == "treehouse") {
                    section("气泡颜色") {
                        BubbleAppearanceSettingsView(part: .colors)
                    }
                }
                if page == .appearance { section("聊天壁纸") {
                    HStack {
                        PhotosPicker(selection: $wallPhoto, matching: .images) {
                            Label("从相册更换", systemImage: "photo")
                        }
                        Spacer()
                        Button("恢复默认") { resetWallpaper() }
                    }
                    .font(.system(size: 13))
                    // 1010 #3584 她：「模糊壁纸程度调节我希望所有主题都可以」——从树屋的调整颜色挪到这，每一族主题各存各的
                    HStack(spacing: 9) {
                        Text("壁纸模糊").font(.system(size: 13))
                        Text("清楚").font(.system(size: 10)).foregroundColor(theme.textDim)
                        Slider(value: Binding(get: { _ = wallBlurStamp; return TreehouseWallBlur.value(for: themeName) },
                                              set: { TreehouseWallBlur.set($0, for: themeName); wallBlurStamp = Date().timeIntervalSince1970 }),
                               in: 0...12, step: 1)
                        Text("朦胧").font(.system(size: 10)).foregroundColor(theme.textDim)
                    }
                    .padding(.top, 6)
                } }
                if page == .services { section("服务") {
                    serviceCard(
                        name: "Alcove Backend",
                        address: "https://alcove.ob-memory.uk",
                        online: backendOnline,
                        latency: backendLatency,
                        detail: "App 接口 · 消息 · 附件 · OB 代理"
                    )
                    Divider().opacity(0.25)
                    serviceCard(
                        name: "何渡 · Codex",
                        address: "local://alcove-codex/appserver.sock",
                        online: codexOnline,
                        latency: codexLatency,
                        detail: codexThreadConnected ? "独立常驻 · 当前线程已连接" : "独立常驻 · 等待线程连接"
                    )
                    Button { Task { await loadServices() } } label: {
                        Label(servicesLoading ? "刷新中" : "刷新服务状态", systemImage: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundColor(theme.textDim)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(servicesLoading)
                } }
                if page == .system { section("系统联动") {
                    Button { showSystemFeatures = true } label: {
                        settingRow("灵动岛与屏幕控制", "工作状态同步、屏幕共享") {
                            Image(systemName: "chevron.right")
                                .foregroundColor(theme.textLight)
                        }
                    }
                    .buttonStyle(.plain)
                } }
                if page == .system { section("App") {
                    Button(action: showPermissions) {
                        settingRow("系统权限", "位置、日历、运动、麦克风等权限") {
                            Image(systemName: "chevron.right").foregroundColor(theme.textLight)
                        }
                    }
                    .buttonStyle(.plain)
                } }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
            .foregroundColor(theme.text)
        }
    }

    private func refreshCacheStats() {
        let c = ImageDiskCache.shared
        DispatchQueue.global(qos: .utility).async {
            let b = c.totalBytes(), n = c.fileCount()
            DispatchQueue.main.async { cacheBytes = b; cacheCount = n }
        }
    }

    private func purgeCache(before date: Date?) {
        let freed = ImageDiskCache.shared.clear(before: date)
        withAnimation { cacheJustFreed = freed }
        refreshCacheStats()
    }

    @ViewBuilder private func panelTitle(_ text: String) -> some View {
        if !houseOwnsHeader {
            Text(text).font(.system(size: 17, weight: .semibold)).padding(.top, 11)
        }
    }

    @ViewBuilder private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(theme.textDim)
                .padding(.leading, 6)
            VStack(spacing: 10) { content() }
                .padding(14)
                .background(pal.card,
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(pal.line, lineWidth: 0.5))
        }
    }

    private func settingRow<Trailing: View>(
        _ title: String, _ desc: String, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14))
                Text(desc).font(.system(size: 11)).foregroundColor(theme.textLight)
            }
            Spacer()
            trailing()
        }
    }

    private func serviceCard(
        name: String, address: String, online: Bool, latency: Int?, detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(name).font(.system(size: 14, weight: .medium))
                Spacer()
                Circle().fill(online ? Color.green : Color.red.opacity(0.8)).frame(width: 8, height: 8)
                Text(online ? "在线" : "离线")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(online ? .green : .red.opacity(0.8))
            }
            Text(address).font(.system(size: 11, design: .monospaced)).foregroundColor(theme.textLight)
            HStack {
                Text(detail)
                Spacer()
                if let latency { Text("\(latency)ms") }
            }
            .font(.system(size: 10)).foregroundColor(theme.textDim)
        }
        .padding(.vertical, 2)
    }

    @MainActor private func loadServices() async {
        servicesLoading = true
        let started = Date()
        do {
            let value = try await NativeHouseAPI.object("/services/status")
            let backend = value.object("backend")
            let codex = value.object("codex")
            backendOnline = backend.bool("online")
            backendLatency = max(backend.int("latency_ms"), Int(Date().timeIntervalSince(started) * 1000))
            codexOnline = codex.bool("online")
            codexLatency = codex["latency_ms"] is NSNull ? nil : codex.int("latency_ms")
            codexThreadConnected = codex.bool("thread_connected")
        } catch {
            backendOnline = false; codexOnline = false
            backendLatency = nil; codexLatency = nil; codexThreadConnected = false
        }
        servicesLoading = false
    }

    @MainActor private func loadReplyLength() async {
        if let value = try? await NativeHouseAPI.object("/api/reply-len") {
            replyLength = Double(value.int("chars"))
        }
        replyLengthLoaded = true
    }

    @MainActor private func loadHerStatus() async {
        let raw = (try? await NativeHouseAPI.object("/api/status/her")) ?? [:]
        herStatus = raw.string("text")
        herStatusLine = raw.string("line")
        herStatusLoaded = true
    }

    @MainActor private func loadPat() async {
        let raw = (try? await NativeHouseAPI.object("/api/pat")) ?? [:]
        patHerSuffix = raw.string("chenji_suffix")
        patHimSuffix = raw.string("chenjing_suffix")
        patLoaded = true
    }

    // 后缀连同当前设置的名字一起存，这样他在别处拍她时叫的也是她刚改的那个名字
    private func schedulePatSave() {
        guard patLoaded else { return }
        patSaveTask?.cancel()
        patSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            _ = try? await NativeHouseAPI.object(
                "/api/pat/settings", method: "POST",
                body: ["actor": "chenji",
                       "chenji_suffix": patHerSuffix,
                       "chenjing_suffix": patHimSuffix,
                       "assistant_name": assistantName])
        }
    }

    private func scheduleHerStatusSave(_ value: String) {
        guard herStatusLoaded else { return }
        herStatusSaveTask?.cancel()
        herStatusSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            let raw = (try? await NativeHouseAPI.object(
                "/api/status/her", method: "POST", body: ["text": value])) ?? [:]
            herStatusLine = raw.string("line")
        }
    }

    private func scheduleReplyLengthSave(_ value: Double) {
        guard replyLengthLoaded else { return }
        replyLengthSaveTask?.cancel()
        replyLengthSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            replyLengthSaving = true
            defer { replyLengthSaving = false }
            _ = try? await NativeHouseAPI.object(
                "/api/reply-len", method: "POST", body: ["chars": Int(value)]
            )
        }
    }

    private func pulseField(_ label: String, _ value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9.5)).foregroundColor(theme.textDim)
            TextField("", value: value, format: .number)
                .keyboardType(.numberPad)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .frame(width: 64)
                .padding(.vertical, 6).padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 9).fill(theme.textDim.opacity(0.12)))
        }
    }

    /// 追问一开，找你 / 自醒跟着关（上面那两个开关锁住）；追问自己的键由 pulseToggle 去存
    private var followupBinding: Binding<Bool> {
        Binding(get: { followupOn }, set: { on in
            followupOn = on
            guard on else { return }
            pulseChase = false
            wakeOn = false
            Task {
                for key in ["pulse_chase", "wake_engine"] {
                    try? await NativeHouseAPI.post("/api/flags/set", body: ["key": key, "on": false])
                }
            }
        })
    }

    private func pulseToggle(_ title: String, _ sub: String, _ value: Binding<Bool>, key: String,
                             locked: Bool = false, lockedText: String = "追问开着，锁住了") -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(locked ? lockedText : sub).font(.system(size: 9)).foregroundColor(theme.textDim)
            }
            Toggle("", isOn: Binding(
                get: { locked ? false : value.wrappedValue },
                set: { on in
                    value.wrappedValue = on
                    Task { try? await NativeHouseAPI.post("/api/flags/set", body: ["key": key, "on": on]) }
                }))
            .labelsHidden()
            .tint(theme.fyAccent)
            .disabled(locked)
        }
        .opacity(locked ? 0.45 : 1)
    }

    /// 只要 HH:mm（日程提醒一排好几个，不带「还有几分钟」）；不是今天的前面带月日
    private static func clockText(_ iso: String) -> String? {
        guard let d = ISO8601DateFormatter().date(from: iso) else { return nil }
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "M月d日 HH:mm"
        return f.string(from: d)
    }

    private static func pulseDueText(_ iso: String?) -> String? {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return nil }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        let mins = Int(d.timeIntervalSinceNow / 60)
        return mins >= 0 ? "\(f.string(from: d))（还有 \(mins) 分钟）" : "\(f.string(from: d))（已到点，等他手里的活干完）"
    }

    @MainActor private func loadPulseRange() async {
        if let value = try? await NativeHouseAPI.object("/api/pulse-range") {
            if let ranges = value["ranges"] as? [String: Any] {
                if let c = ranges["chase"] as? [String: Any] {
                    chaseMin = (c["min"] as? Int) ?? chaseMin
                    chaseMax = (c["max"] as? Int) ?? chaseMax
                }
                if let g = ranges["ghost"] as? [String: Any] {
                    ghostMin = (g["min"] as? Int) ?? ghostMin
                    ghostMax = (g["max"] as? Int) ?? ghostMax
                }
            } else {   // 老后端：只有一组数，两面共用
                chaseMin = value.int("min"); chaseMax = value.int("max")
                ghostMin = chaseMin; ghostMax = chaseMax
            }
            chaseDue = Self.pulseDueText((value["chase_due"] as? String) ?? (value["next_due"] as? String))
            ghostDue = Self.pulseDueText(value["ghost_due"] as? String)
            if let c = value["chase"] as? Bool { pulseChase = c }
            if let g = value["ghost"] as? Bool { pulseGhost = g }
            if let f = value["followup"] as? Bool { followupOn = f }
            followupAlarm = Self.pulseDueText(value["followup_alarm"] as? String)
            followupSchedule = ((value["followup_schedule"] as? [String]) ?? []).compactMap(Self.clockText)
            if let b = value["backstop"] as? Bool { backstopOn = b }
            if let n = value["backstop_min"] as? Int { backstopMin = n }
        }
        pulseLoaded = true
    }

    @MainActor private func loadWake() async {
        guard let value = try? await NativeHouseAPI.object("/api/wake") else { return }
        if let on = value["on"] as? Bool { wakeOn = on }
        guard let st = value["status"] as? [String: Any] else { wakeLine = "引擎没在跑"; wakeEta = "引擎没在跑"; return }
        if let paused = st["paused_by"] as? String {
            let why = ["asleep": "他睡着", "quiet": "留白中", "app-off": "开关关着", "off": "引擎停着"][paused] ?? paused
            wakeLine = "暂停：\(why)"
            wakeEta = "暂停中（\(why)），桶不滴"
            wakeOdds = nil
        } else {
            wakeLine = nil
            wakeEta = Self.pulseDueText(st["eta_if_lambda_holds"] as? String).map { $0 + "，按此刻的速度估" } ?? "还没算出来"
            if let p30 = st["p_wake_30min"] as? Double, let p60 = st["p_wake_60min"] as? Double {
                wakeOdds = "半小时内约 \(Int((p30 * 100).rounded()))%，一小时内约 \(Int((p60 * 100).rounded()))%"
            }
        }
    }

    /// 兜底的分钟数单独存（后端只传它时不重排找你 / 去玩那两张表）
    private func saveBackstop() {
        // 她 0925 定的：最短 10 分钟、最长 5 小时，填出界就拉回边上再存
        backstopMin = min(max(backstopMin, 10), 300)
        Task { @MainActor in
            if let value = try? await NativeHouseAPI.object(
                "/api/pulse-range", method: "POST", body: ["backstop": backstopMin]
            ), let n = value["backstop_min"] as? Int {
                backstopMin = n
            }
        }
    }

    private func savePulseRange() {
        guard pulseLoaded,
              chaseMin >= 1, chaseMax >= chaseMin, chaseMax <= 1440,
              ghostMin >= 1, ghostMax >= ghostMin, ghostMax <= 1440 else { return }
        Task { @MainActor in
            pulseSaving = true
            defer { pulseSaving = false }
            if let value = try? await NativeHouseAPI.object(
                "/api/pulse-range", method: "POST",
                body: ["chase": ["min": chaseMin, "max": chaseMax],
                       "ghost": ["min": ghostMin, "max": ghostMax]]
            ) {
                chaseDue = Self.pulseDueText((value["chase_due"] as? String) ?? (value["next_due"] as? String))
                ghostDue = Self.pulseDueText(value["ghost_due"] as? String)
            }
        }
    }

    @MainActor private func loadThoughtLength() async {
        if let value = try? await NativeHouseAPI.object("/api/reply-len") {
            let n = value.int("thought_chars")
            if n == -1 {
                handwrittenOn = false
            } else {
                handwrittenOn = true
                thoughtLength = Double(n)
                thoughtLengthBeforeOff = Double(n)
            }
        }
        thoughtLengthLoaded = true
    }

    private func scheduleThoughtLengthSave(_ value: Double) {
        guard thoughtLengthLoaded else { return }
        thoughtLengthSaveTask?.cancel()
        thoughtLengthSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            thoughtLengthSaving = true
            defer { thoughtLengthSaving = false }
            _ = try? await NativeHouseAPI.object(
                "/api/reply-len", method: "POST", body: ["thought_chars": Int(value)]
            )
        }
    }

    private func themeChoice(
        _ title: String, _ sub: String, _ value: String, _ colors: [Color]
    ) -> some View {
        Button { themeName = value } label: {
            VStack(spacing: 7) {
                HStack(spacing: 4) {
                    ForEach(colors.indices, id: \.self) { i in
                        Circle().fill(colors[i]).frame(width: 13, height: 13)
                    }
                }
                Text(title).font(.system(size: 13, weight: .medium))
                Text(sub).font(.system(size: 10)).foregroundColor(theme.textLight)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(themeName == value ? theme.fyAccent : theme.fyBorder, lineWidth: 1.4))
        }
        .buttonStyle(.plain)
    }

    private var isPaperFamily: Bool { themeName == "paper" || themeName == "paper-dark" }
    private var isMessagesFamily: Bool { themeName == "imessage" || themeName == "imessage-dark" }
    private var isKakaoFamily: Bool { themeName == "kakao" }
    private var themeFamily: String { AlcoveAppearance.family(of: themeName) }
    // 0827 全屋只剩这一个开关：按下去同时写 houseInterfaceAppearance（功能页、
    // 共读室、檐下、信箱、信封卡读它）和 alcoveTheme 的深浅后缀（聊天页、圆桌、
    // 根视图读它）。以前这两个各走各的，她按了一边另一边不动。
    private var appearanceBinding: Binding<Bool> {
        Binding(get: { houseAppearance != "light" }, set: { dark in
            AlcoveAppearance.apply(dark: dark)
            houseAppearance = dark ? "dark" : "light"
            themeName = AlcoveAppearance.themeName(family: themeFamily, dark: dark)
        })
    }
    private func familyChoice(_ title: String, _ sub: String, _ family: String, _ colors: [Color]) -> some View {
        Button {
            themeName = AlcoveAppearance.themeName(family: family, dark: houseAppearance != "light")
        } label: {
            VStack(spacing: 7) {
                HStack(spacing: 4) { ForEach(colors.indices, id: \.self) { Circle().fill(colors[$0]).frame(width: 13, height: 13) } }
                Text(title).font(.system(size: 13, weight: .medium))
                Text(sub).font(.system(size: 10)).foregroundColor(theme.textLight)
            }.frame(maxWidth: .infinity).padding(.vertical, 10)
                .overlay(RoundedRectangle(cornerRadius: theme.isPaper ? 3 : 12)
                    .stroke(themeFamily == family ? theme.fyAccent : theme.fyBorder, lineWidth: 1.4))
        }.buttonStyle(.plain)
    }

    private func avatar(dataURL: String, fallback: String) -> some View {
        Group {
            if let image = Self.image(dataURL) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(fallback).font(.system(size: 13, design: .serif))
            }
        }
        .frame(width: 38, height: 38)
        .background(theme.glassTint)
        .clipShape(Circle())
    }

    private static func image(_ value: String) -> UIImage? {
        let payload = value.split(separator: ",", maxSplits: 1).last.map(String.init) ?? value
        return Data(base64Encoded: payload).flatMap(UIImage.init(data:))
    }

    private func loadDataURL(_ item: PhotosPickerItem?, into binding: Binding<String>) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.82) else { return }
            binding.wrappedValue = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        }
    }

    private func saveWallpaper(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.9) else { return }
            let file = ChatWallpaperStore.fileName(for: themeName)
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(file)
            try? jpeg.write(to: url, options: .atomic)
            wallStamp = Date().timeIntervalSince1970
        }
    }

    private func resetWallpaper() {
        let file = ChatWallpaperStore.fileName(for: themeName)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(file)
        try? FileManager.default.removeItem(at: url)
        wallStamp = Date().timeIntervalSince1970
    }
}


private struct BubbleAppearanceSettingsView: View {
    // 1009 晚 她要的（只给树屋）：他的气泡分段 / 整个
    @AppStorage(TreehouseBubbleMode.key) private var treehouseWholeBubble = false
    /// 0925 她要的「气泡与文字并进外观页」：整页之外还能只画一块——预览 / 字号和间距 / 信息主题的颜色，
    /// 外观页按块摆进去；整页（all）那条路留着，入口已经撤了
    enum Part { case all, preview, text, colors }
    let part: Part
    init(part: Part = .all) { self.part = part }

    @AppStorage("assistantName") private var assistantName = "陈璟"
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @AppStorage("chatFontSize") private var fontSize = 14
    @AppStorage("chatBubbleGap") private var bubbleGap = 6.0
    @AppStorage("chatTurnGap") private var turnGap = 22.0   // 0929：他连着两轮之间（中间没时间胶囊）多留的空
    @AppStorage("msgGlassFrost") private var glassFrost = 0.3   // 1001：信息主题玻璃气泡透明 ↔ 色调（ChatView MessagesBubbleFill）
    @AppStorage(MessagesPalette.glassKey) private var bubbleGlass = true   // 1001：信息主题普通 / 玻璃气泡，两套颜色各存各的
    @AppStorage(MessagesPalette.thGlassKey) private var thGlass = false     // 1009 #3519：树屋自己的普通 / 玻璃
    // 0924 她报的：「气泡与文字」的预览换了字体还是系统字，跟全局字体走
    @ObservedObject private var kakaoPacks = KakaoPackStore.shared
    @AppStorage("wallStamp") private var wallStamp = 0.0
    /// 0902 信息主题调色板：改一项这个数就变，预览跟着重画
    @AppStorage(MessagesPalette.stampKey) private var paletteStamp = 0.0

    private var panelTheme: AlcoveTheme { .panelNamed(themeName) }
    private var chatTheme: AlcoveTheme { _ = paletteStamp; return .named(themeName) }

    @ViewBuilder var body: some View {
        switch part {
        case .all: fullPage
        case .preview:
            livePreview
        case .text:
            VStack(spacing: 12) {
                fontSizeSlider
                bubbleGapSlider
                turnGapSlider
                if chatTheme.isMessages && !chatTheme.isKakao && (chatTheme.isTreehouse ? thGlass : bubbleGlass) { glassFrostSlider }
            }
        case .colors:
            VStack(spacing: 12) {
                if chatTheme.isTreehouse { treehouseGlassPicker; treehouseBubbleModePicker } else { bubbleStylePicker }
                ForEach(paletteItems) { item in colorRow(item) }
            }
            Text(chatTheme.isTreehouse
                 ? "树屋的气泡与颜色跟信息主题分开存；白天、黑夜各一套，跟全屋的日夜开关走；每项的默认只恢复该项。"
                 : "预设一点就换；「自定义」里有色轮和吸管，可以直接从壁纸上吸颜色；每项的「默认」只回这一项。夜里、白天各存一套，跟全屋的日夜开关走；普通、玻璃也各一套。现在调的是\(bubbleGlass ? "玻璃" : "普通")·\(chatTheme.isDark ? "夜里" : "白天")这套")
                .font(.system(size: 10))
                .foregroundColor(panelTheme.textLight)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fullPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                Text("气泡与文字")
                    .font(.system(size: 17, weight: .semibold))
                    .padding(.top, 11)

                livePreview

                // 0902 她要的：信息主题下自己调颜色。每项预设色块 + 自定义取色器 + 各自的「默认」
                if chatTheme.isMessages {
                    section(chatTheme.isTreehouse ? "颜色 · 树屋" : "颜色 · 信息主题") {
                        VStack(spacing: 12) {
                            // 树屋：普通 / 玻璃（#3519）＋「他的气泡分段还是整个」
                            if chatTheme.isTreehouse { treehouseGlassPicker; treehouseBubbleModePicker } else { bubbleStylePicker }
                            ForEach(paletteItems) { item in colorRow(item) }
                        }
                        Text(chatTheme.isTreehouse
                             ? "预设一点就换；「自定义」里有色轮和吸管，可以直接从壁纸上吸颜色；每项的「默认」只回这一项。树屋跟信息主题那套分开存，各调各的；白天、黑夜各一套，跟全屋的日夜开关走。现在调的是\(chatTheme.isDark ? "夜里" : "白天")这套"
                             : "预设一点就换；「自定义」里有色轮和吸管，可以直接从壁纸上吸颜色；每项的「默认」只回这一项。夜里、白天各存一套，跟全屋的日夜开关走；普通、玻璃也各一套。现在调的是\(bubbleGlass ? "玻璃" : "普通")·\(chatTheme.isDark ? "夜里" : "白天")这套")
                            .font(.system(size: 10))
                            .foregroundColor(panelTheme.textLight)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                section("文字") {
                    VStack(spacing: 12) {
                        fontSizeSlider
                        bubbleGapSlider
                        turnGapSlider
                        if chatTheme.isMessages && !chatTheme.isKakao && (chatTheme.isTreehouse ? thGlass : bubbleGlass) { glassFrostSlider }
                    }
                }

            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
            .foregroundColor(panelTheme.text)
        }
    }

    /// 1001 她要的「预览一定要跟当前主题一模一样」：不再手画，直接用聊天页同一套零件（ChatView.swift ChatLookPreview）
    private var livePreview: some View {
        ChatLookPreview()
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(panelTheme.fyBorder, lineWidth: 1)
            )
            .shadow(color: panelTheme.fyShadow, radius: 8, y: 3)
    }

    private func colorRow(_ item: MessagesPalette.Item) -> some View {
        let dark = chatTheme.isDark
        // 1009 晚：树屋有自己那套键；#3518 起树屋也分白天 / 黑夜，跟信息主题一样按眼下这一档存
        let th = chatTheme.isTreehouse
        let binding = Binding<Color>(
            get: { th ? MessagesPalette.thCurrent(item, dark: dark) : MessagesPalette.current(item, dark: dark) },
            set: { th ? MessagesPalette.thSet(item, $0, dark: dark) : MessagesPalette.set(item, $0, dark: dark) })
        let isDefault = th ? MessagesPalette.thIsDefault(item, dark: dark) : MessagesPalette.isDefault(item, dark: dark)
        return HStack(spacing: 8) {
            Text(item.title)
                .font(.system(size: 12))
                .frame(width: 84, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Array(MessagesPalette.presets.enumerated()), id: \.offset) { _, c in
                        Button { th ? MessagesPalette.thSet(item, c, dark: dark) : MessagesPalette.set(item, c, dark: dark) } label: {
                            Circle().fill(c)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(panelTheme.fyBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            ColorPicker("", selection: binding, supportsOpacity: true)
                .labelsHidden()
                .frame(width: 30)
            Button("默认") { th ? MessagesPalette.thSet(item, nil, dark: dark) : MessagesPalette.set(item, nil, dark: dark) }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isDefault ? panelTheme.textLight : panelTheme.fyAccent)
                .disabled(isDefault)
        }
    }

    /// 0909 她要的：气泡之间的间距。原来写死 6pt，现在 0~20 自己拖
    private var bubbleGapSlider: some View {
        HStack(spacing: 9) {
            Text("气泡间距")
                .font(.system(size: 12))
                .frame(width: 100, alignment: .leading)

            Slider(value: $bubbleGap, in: 0...20, step: 1)
                .tint(panelTheme.fyAccent)

            Text("\(Int(bubbleGap)) pt")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(panelTheme.textDim)
                .frame(width: 45, alignment: .trailing)
        }
    }

    /// 0929 她要的：他连着两轮挨太近（中间隔不到 15 分钟、没冒时间胶囊）时，两轮之间多留多少。原来写死 22
    private var turnGapSlider: some View {
        HStack(spacing: 9) {
            Text("轮与轮间距")
                .font(.system(size: 12))
                .frame(width: 100, alignment: .leading)

            Slider(value: $turnGap, in: 0...48, step: 2)
                .tint(panelTheme.fyAccent)

            Text("\(Int(turnGap)) pt")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(panelTheme.textDim)
                .frame(width: 45, alignment: .trailing)
        }
    }

    /// 1009 晚 她要的（只给树屋）：他一轮话拆成好几个气泡，还是并成一整个。
    /// 她原话「这个气泡仅限你的，我的不包含」——她自己的气泡一个都不并。
    private var treehouseBubbleModePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("他的气泡", selection: $treehouseWholeBubble) {
                Text("分段").tag(false)
                Text("整个").tag(true)
            }
            .pickerStyle(.segmented)
            Text("「整个」把他同一轮里连着的几段字并成一个气泡；图片、语音、表情、卡片照旧各自一个。你自己的气泡不动")
                .font(.system(size: 10))
                .foregroundColor(panelTheme.textLight)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 1009 #3519 树屋也能切玻璃气泡：单独一个开关（跟信息主题那个不连着）；玻璃没有底色，「我的 / 他的气泡」两项藏起来
    private var treehouseGlassPicker: some View {
        Picker("气泡", selection: Binding(get: { thGlass },
                                          set: { thGlass = $0; MessagesPalette.bump() })) {
            Text("普通气泡").tag(false)
            Text("玻璃气泡").tag(true)
        }
        .pickerStyle(.segmented)
    }

    /// 1001 她要的：信息主题普通气泡 / 玻璃气泡切换。两套颜色分开存，切回普通以前调的都还在
    private var bubbleStylePicker: some View {
        Picker("气泡", selection: Binding(get: { bubbleGlass },
                                          set: { bubbleGlass = $0; MessagesPalette.bump() })) {
            Text("普通气泡").tag(false)
            Text("玻璃气泡").tag(true)
        }
        .pickerStyle(.segmented)
    }

    /// 玻璃气泡不带颜色，「我的气泡」「他的气泡」两项藏起来
    private var paletteItems: [MessagesPalette.Item] {
        // 树屋是实心气泡，没有玻璃那回事；时间戳不单独调了，跟着两边正文的 80% 走（#3511），所以少这一项
        if chatTheme.isTreehouse {
            return MessagesPalette.Item.allCases.filter { $0 != .timestamp && !(thGlass && ($0 == .bubbleUser || $0 == .bubbleAI)) }
        }
        return MessagesPalette.Item.allCases.filter { !(bubbleGlass && ($0 == .bubbleUser || $0 == .bubbleAI)) }
    }

    /// 1001 她要的：只管气泡的玻璃，照系统设置里 Liquid Glass 那条——左边透明、右边色调（更磨砂、字更清楚），不带颜色
    private var glassFrostSlider: some View {
        HStack(spacing: 9) {
            Text("气泡玻璃")
                .font(.system(size: 12))
                .frame(width: 100, alignment: .leading)

            Text("透明")
                .font(.system(size: 10))
                .foregroundColor(panelTheme.textDim)
            Slider(value: $glassFrost, in: 0...1)
                .tint(panelTheme.fyAccent)
            Text("色调")
                .font(.system(size: 10))
                .foregroundColor(panelTheme.textDim)
        }
    }

    private var fontSizeSlider: some View {
        let value = Binding<Double>(
            get: { Double(fontSize) },
            set: { fontSize = Int($0.rounded()) }
        )

        return HStack(spacing: 9) {
            Text("字体大小")
                .font(.system(size: 12))
                .frame(width: 100, alignment: .leading)

            Slider(value: value, in: 11...20, step: 1)
                .tint(panelTheme.fyAccent)

            Text("\(fontSize) pt")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(panelTheme.textDim)
                .frame(width: 45, alignment: .trailing)
        }
    }

    @ViewBuilder private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.8)
                    .foregroundColor(panelTheme.fyAccent.opacity(0.8))
                LinearGradient(
                    colors: [panelTheme.fyAccentSoft, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 1)
            }
            VStack(spacing: 10) { content() }
                .padding(13)
                .foyerCard(panelTheme)
        }
    }

    private func glassSliderRow(
        _ title: String,
        _ parameter: String,
        _ value: Binding<Double>,
        _ range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 9) {
            HStack(spacing: 4) {
                Text(title)
                Text(parameter)
                    .foregroundColor(panelTheme.textLight)
            }
            .font(.system(size: 11))
            .frame(width: 100, alignment: .leading)

            Slider(value: value, in: range)
                .tint(panelTheme.fyAccent)

            Text(String(format: "%.2f", value.wrappedValue))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(panelTheme.textDim)
                .frame(width: 45, alignment: .trailing)
        }
    }


    private func resetAppearance() {
        fontSize = 14
    }
}

struct MusicSong: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let artist: String
    let cover: String
    var message: String = ""

    init(_ json: [String: Any]) {
        id = json.string("id", "song_id")
        name = json.string("name", "song_name", "title")
        if let artists = json["ar"] as? [[String: Any]] {
            artist = artists.first?.string("name") ?? ""
        } else if let artists = json["artists"] as? [[String: Any]] {
            artist = artists.first?.string("name") ?? ""
        } else {
            artist = json.string("artist")
        }
        let rawCover = json.object("al").string("picUrl").isEmpty
            ? json.string("cover", "picUrl") : json.object("al").string("picUrl")
        cover = Self.secureURL(rawCover)
        message = json.string("message")
    }

    init(id: String, name: String, artist: String, cover: String, message: String = "") {
        self.id = id
        self.name = name
        self.artist = artist
        self.cover = Self.secureURL(cover)
        self.message = message
    }

    static func card(from text: String) -> MusicSong? {
        let prefix = "[MUSIC_CARD]", suffix = "[/MUSIC_CARD]"
        guard text.hasPrefix(prefix), text.hasSuffix(suffix) else { return nil }
        let start = text.index(text.startIndex, offsetBy: prefix.count)
        let end = text.index(text.endIndex, offsetBy: -suffix.count)
        guard let data = String(text[start..<end]).data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return MusicSong(raw)
    }

    static func secureURL(_ raw: String) -> String {
        raw.hasPrefix("http://") ? "https://" + String(raw.dropFirst("http://".count)) : raw
    }

    func cardText(message: String) -> String? {
        var copy = self
        copy.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = try? JSONEncoder().encode(copy),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return "[MUSIC_CARD]\(json)[/MUSIC_CARD]"
    }
}

@MainActor
struct MusicLyric: Identifiable, Equatable {
    let id = UUID()
    let time: Double
    let text: String
    let translation: String?
}

struct MusicPlaylist: Identifiable, Equatable {
    let id: String
    let name: String
    let cover: String
    let count: Int

    init(_ json: [String: Any]) {
        id = json.string("id")
        name = json.string("name")
        cover = MusicSong.secureURL(json.string("coverImgUrl", "picUrl"))
        count = json.int("trackCount")
    }
}

enum MusicPlayMode: String, CaseIterable {
    case sequence, shuffle, repeatOne

    var icon: String {
        switch self {
        case .sequence: return "repeat"
        case .shuffle: return "shuffle"
        case .repeatOne: return "repeat.1"
        }
    }
    var title: String {
        switch self {
        case .sequence: return "顺序播放"
        case .shuffle: return "随机播放"
        case .repeatOne: return "单曲循环"
        }
    }
}

@MainActor
final class MusicModel: ObservableObject {
    static let shared = MusicModel()
    @Published var songs: [MusicSong] = []
    @Published var nowPlaying: MusicSong?
    @Published var isPlaying = false
    @Published var loading = false
    @Published var message = ""
    @Published var progress: Double = 0
    @Published var duration: Double = 0
    @Published var lyrics: [MusicLyric] = []
    @Published var lyricsLoading = false
    @Published var lineSending = false
    @Published var lineSentFlash = false
    @Published var playlists: [MusicPlaylist] = []
    @Published var recommended: [MusicPlaylist] = []
    @Published var playlistSongs: [MusicSong] = []
    @Published var homeLoading = false
    @Published var likedSongIDs: Set<String> = []
    @Published var queue: [MusicSong] = []
    @Published var queueIndex = -1
    @Published var playMode: MusicPlayMode = .sequence
    @Published var playbackLoading = false
    @Published var listenTotalSeconds = 0
    // 任务#1310：一起听是个开关，不是放歌就算。故意不持久化：
    // 每次要手动开，停止播放/重开 App 自动归零，永远不会忘了关导致独听被直播
    @Published var togetherOn = false
    private var listenHeartbeat: Task<Void, Never>?
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var itemStatusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var streamCache: [String: (url: URL, expires: Date)] = [:]
    private var streamPrefetchTask: Task<Void, Never>?
    private var playbackPoll: Task<Void, Never>?

    private init() {
        configureRemoteCommands()
    }

    func search(_ query: String) async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let q = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              !q.isEmpty else { return }
        loading = true
        message = ""
        defer { loading = false }
        guard let obj = try? await NativeHouseAPI.object("/api/music/cloudsearch?keywords=\(q)") else {
            songs = []
            message = "没连上音乐服务"
            return
        }
        songs = obj.object("result").array("songs").map(MusicSong.init)
        prefetchArtwork(for: songs)
        if songs.isEmpty { message = "没搜到  换个词试试" }
    }

    /// 一起听累计时长：先拉总数，之后每 30 秒在播就往后端记 30 秒
    func startListenClock() {
        guard listenHeartbeat == nil else { return }
        listenHeartbeat = Task { [weak self] in
            if let obj = try? await NativeHouseAPI.object("/api/listen/stats") {
                self?.listenTotalSeconds = obj.int("total_seconds")
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self, self.isPlaying, self.togetherOn else { continue }
                try? await NativeHouseAPI.post("/api/listen/beat", body: ["seconds": 30])
                self.listenTotalSeconds += 30
            }
        }
    }

    var listenTimeText: String {
        let hours = listenTotalSeconds / 3600
        let minutes = listenTotalSeconds % 3600 / 60
        if hours > 0 { return "一起听了 \(hours) 小时 \(minutes) 分钟" }
        if minutes > 0 { return "一起听了 \(minutes) 分钟" }
        return "刚开始一起听"
    }

    func play(_ song: MusicSong, queue source: [MusicSong]? = nil) async {
        startListenClock()
        if let source, !source.isEmpty {
            queue = source
            queueIndex = source.firstIndex(where: { $0.id == song.id }) ?? 0
        } else if let index = queue.firstIndex(where: { $0.id == song.id }) {
            queueIndex = index
        } else if let index = songs.firstIndex(where: { $0.id == song.id }) {
            queue = songs
            queueIndex = index
        } else {
            // A music card has no list of its own. Keep the last real queue
            // behind it so playback can still continue when the card ends.
            queue = [song] + queue.filter { $0.id != song.id }
            queueIndex = 0
        }
        playbackLoading = true
        guard let url = await streamURL(for: song.id) else {
            message = "这首暂时放不了"
            playbackLoading = false
            return
        }
        message = ""
        cleanup()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            message = "音频通道没打开"
        }
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 2
        let nextPlayer = AVPlayer(playerItem: item)
        nextPlayer.automaticallyWaitsToMinimizeStalling = false
        player = nextPlayer
        nowPlaying = song
        isPlaying = false
        progress = 0; duration = 0
        itemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
            Task { @MainActor in
                guard let self, let item, self.player?.currentItem === item else { return }
                switch item.status {
                case .readyToPlay:
                    self.player?.playImmediately(atRate: 1)
                case .failed:
                    self.playbackLoading = false
                    self.isPlaying = false
                    self.message = item.error?.localizedDescription ?? "这首没有成功加载"
                default: break
                }
            }
        }
        timeControlObserver = nextPlayer.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self, weak nextPlayer] _, _ in
            Task { @MainActor in
                guard let self, let nextPlayer, self.player === nextPlayer else { return }
                self.isPlaying = nextPlayer.timeControlStatus == .playing
                if self.isPlaying { self.playbackLoading = false }
                self.publishNowPlaying()
            }
        }
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self, let item = self.player?.currentItem else { return }
                let dur = item.duration.seconds
                if dur.isFinite && dur > 0 {
                    self.duration = dur
                    self.progress = time.seconds
                    self.publishNowPlaying()
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.handleTrackEnded()
            }
        }
        await loadLyrics(song.id)
        publishNowPlaying(loadArtwork: true)
        await reportNowPlaying()
        prefetchNextStream()
    }

    func loadHome() async {
        guard playlists.isEmpty else { return }
        homeLoading = true
        defer { homeLoading = false }
        async let mine = try? NativeHouseAPI.object("/api/music/user/playlist?uid=1441382791&limit=50")
        async let recs = try? NativeHouseAPI.object("/api/music/recommend/resource")
        async let likes = try? NativeHouseAPI.object("/api/music/likelist")
        let (myObject, recObject, likeObject) = await (mine, recs, likes)
        playlists = (myObject?["playlist"] as? [[String: Any]] ?? []).map(MusicPlaylist.init)
        recommended = (recObject?["recommend"] as? [[String: Any]] ?? []).map(MusicPlaylist.init)
        likedSongIDs = Set((likeObject?["ids"] as? [Any] ?? []).compactMap {
            if let n = $0 as? NSNumber { return n.stringValue }
            return $0 as? String
        })
    }

    func toggleLike() async {
        guard let song = nowPlaying else { return }
        let shouldLike = !likedSongIDs.contains(song.id)
        guard (try? await NativeHouseAPI.object(
            "/api/music/like?id=\(song.id)&like=\(shouldLike ? "true" : "false")")) != nil else {
            message = "红心没点上"; return
        }
        if shouldLike { likedSongIDs.insert(song.id) }
        else { likedSongIDs.remove(song.id) }
    }

    var currentIsLiked: Bool {
        guard let id = nowPlaying?.id else { return false }
        return likedSongIDs.contains(id)
    }

    func loadPlaylist(_ playlist: MusicPlaylist) async {
        loading = true
        defer { loading = false }
        guard let obj = try? await NativeHouseAPI.object(
            "/api/music/playlist/track/all?id=\(playlist.id)&limit=500") else {
            playlistSongs = []; message = "歌单没拉下来"; return
        }
        playlistSongs = (obj["songs"] as? [[String: Any]] ?? []).map(MusicSong.init)
        songs = playlistSongs
        prefetchArtwork(for: playlistSongs)
    }

    func toggle() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            // 0902 她报的「录完语音唱片点不动」：录音把音频通道切成录音模式还关掉了会话，
            // 这时候直接 play() 是哑的。每次从暂停起播都先把通道要回来。
            reclaimAudioSession(resume: false)
            player.play()
        }
        isPlaying.toggle()
        publishNowPlaying()
    }

    /// 把音频通道要回播放模式（录语音、打电话之类借走之后）。resume=true 顺手接着放
    func reclaimAudioSession(resume: Bool) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
        if resume, let player, !isPlaying {
            player.play()
            isPlaying = true
            publishNowPlaying()
        }
    }

    func stopAndClear() {
        togetherOn = false
        player?.pause()
        cleanup()
        player = nil
        nowPlaying = nil
        isPlaying = false
        progress = 0
        duration = 0
        lyrics = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        progress = seconds
        publishNowPlaying()
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == false { self?.toggle() } }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == true { self?.toggle() } }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.prev() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func publishNowPlaying(loadArtwork: Bool = false) {
        guard let song = nowPlaying else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = song.name
        info[MPMediaItemPropertyArtist] = song.artist
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        guard loadArtwork, let url = URL(string: song.cover) else { return }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data), self.nowPlaying?.id == song.id else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            updated[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
        }
    }

    func startRemotePolling() {
        guard playbackPoll == nil else { return }
        playbackPoll = Task { [weak self] in
            while !Task.isCancelled {
                await self?.consumeRemoteCommand()
                // 任务#1308：进度也每轮捎带上报，服务器才答得出"现在放到哪一句"
                if let self, self.nowPlaying != nil {
                    await self.reportNowPlaying()
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func consumeRemoteCommand() async {
        guard let obj = try? await NativeHouseAPI.object("/api/playback"),
              !obj.bool("consumed"), let command = obj["command"] as? String else { return }
        switch command {
        case "set":
            if let raw = obj["song"] as? [String: Any] {
                var song = MusicSong(raw)
                if song.message.isEmpty { song.message = obj.string("message") }
                await play(song)
            }
        case "play": if !isPlaying { toggle() }
        case "pause": if isPlaying { toggle() }
        case "next": next()
        case "prev": prev()
        default: break
        }
        try? await NativeHouseAPI.post("/api/playback", body: ["command": "ack"])
    }

    private func reportNowPlaying() async {
        guard let song = nowPlaying else { return }
        try? await NativeHouseAPI.post("/api/playback", body: [
            "command": "report",
            "now_playing": ["id": song.id, "name": song.name, "artist": song.artist,
                            "paused": !isPlaying, "time": Int(progress), "duration": Int(duration),
                            "together": togetherOn]
        ])
    }

    /// 1006 她要的：发歌词从一起听大卡搬到半屏播放器的歌词页。她点选的几句（按顺序拼成一句，中间「 / 」），
    /// 一句没选就发正在唱的那句。发的是**她屏幕上的原文**，直接打包送走；服务端一个字都不许自己算，
    /// 两边各算各的必然差半句，她明确要求所见即所发。start/end 给 18003 切这一段的声学证据。
    func sendLyrics(_ picked: [Int]) async -> Bool {
        let indices = picked.filter { lyrics.indices.contains($0) }.sorted()
        guard let first = indices.first, let last = indices.last, let song = nowPlaying, !lineSending else { return false }
        let text = indices.map { lyrics[$0].text }.joined(separator: " / ")
        let start = lyrics[first].time
        let end = last + 1 < lyrics.count ? lyrics[last + 1].time : lyrics[last].time + 4
        lineSending = true
        defer { lineSending = false }
        let obj = try? await NativeHouseAPI.object("/api/music/line", method: "POST", body: [
            "song_id": song.id, "name": song.name, "artist": song.artist,
            "text": text, "start": start, "end": end])
        guard obj?.bool("ok") == true else {
            message = "这句没发出去"
            return false
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        lineSentFlash = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            self?.lineSentFlash = false
        }
        return true
    }

    func loadLyrics(_ songID: String) async {
        lyricsLoading = true
        defer { lyricsLoading = false }
        guard let obj = try? await NativeHouseAPI.object("/api/music/lyric?id=\(songID)") else {
            lyrics = []; return
        }
        let base = Self.parseLRC(obj.object("lrc").string("lyric"))
        let translated = Self.parseLRC(obj.object("tlyric").string("lyric"))
            .reduce(into: [Int: String]()) { $0[$1.timeKey] = $1.text }
        lyrics = base.map { MusicLyric(time: $0.time, text: $0.text,
                                       translation: translated[$0.timeKey]) }
    }

    private struct ParsedLyric { let time: Double; let text: String; let timeKey: Int }
    private static func parseLRC(_ raw: String) -> [ParsedLyric] {
        let pattern = #"\[(\d+):(\d+)(?:\.(\d+))?\](.*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return raw.components(separatedBy: .newlines).compactMap { line in
            let range = NSRange(line.startIndex..., in: line)
            guard let m = regex.firstMatch(in: line, range: range), m.numberOfRanges == 5,
                  let mr = Range(m.range(at: 1), in: line),
                  let sr = Range(m.range(at: 2), in: line),
                  let tr = Range(m.range(at: 4), in: line),
                  let min = Double(line[mr]), let sec = Double(line[sr]) else { return nil }
            var fraction = 0.0
            if let fr = Range(m.range(at: 3), in: line) {
                let digits = String(line[fr])
                fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
            }
            let time = min * 60 + sec + fraction
            let text = String(line[tr]).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : ParsedLyric(time: time, text: text,
                                                     timeKey: Int((time * 100).rounded()))
        }.sorted { $0.time < $1.time }
    }

    func cyclePlayMode() {
        switch playMode {
        case .sequence: playMode = .shuffle
        case .shuffle: playMode = .repeatOne
        case .repeatOne: playMode = .sequence
        }
    }

    func prev() {
        guard !queue.isEmpty else { return }
        if progress > 4 { seek(to: 0); return }
        let index = queueIndex > 0 ? queueIndex - 1 : queue.count - 1
        playQueueItem(at: index)
    }

    func next() { advance(automatic: false) }

    var hasPrev: Bool { queue.count > 1 || progress > 0 }
    var hasNext: Bool { queue.count > 1 }

    private func handleTrackEnded() {
        if playMode == .repeatOne {
            seek(to: 0)
            player?.play()
            isPlaying = true
            return
        }
        advance(automatic: true)
    }

    private func advance(automatic _: Bool) {
        guard !queue.isEmpty else { return }
        let nextIndex: Int
        switch playMode {
        case .shuffle:
            if queue.count == 1 { nextIndex = 0 }
            else {
                var candidate = queueIndex
                while candidate == queueIndex { candidate = Int.random(in: 0..<queue.count) }
                nextIndex = candidate
            }
        case .sequence, .repeatOne:
            let candidate = queueIndex + 1
            if candidate >= queue.count {
                nextIndex = 0
            } else { nextIndex = candidate }
        }
        playQueueItem(at: nextIndex)
    }

    private func playQueueItem(at index: Int) {
        guard queue.indices.contains(index) else { return }
        queueIndex = index
        let song = queue[index]
        Task { await play(song, queue: queue) }
    }

    private func cleanup() {
        itemStatusObserver?.invalidate(); itemStatusObserver = nil
        timeControlObserver?.invalidate(); timeControlObserver = nil
        if let obs = timeObserver { player?.removeTimeObserver(obs); timeObserver = nil }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil }
    }

    private func streamURL(for songID: String) async -> URL? {
        if let cached = streamCache[songID], cached.expires > Date() { return cached.url }
        guard let obj = try? await NativeHouseAPI.object("/api/music/song/url?id=\(songID)&br=128000"),
              let rows = obj["data"] as? [[String: Any]],
              let raw = rows.first?.string("url"), !raw.isEmpty else { return nil }
        let url = raw.hasPrefix("/") ? AlcoveAPI.fullURL(raw) : URL(string: MusicSong.secureURL(raw))
        if let url { streamCache[songID] = (url, Date().addingTimeInterval(15 * 60)) }
        return url
    }

    private func prefetchNextStream() {
        streamPrefetchTask?.cancel()
        guard !queue.isEmpty else { return }
        let nextIndex = (queueIndex + 1) % queue.count
        let id = queue[nextIndex].id
        streamPrefetchTask = Task { [weak self] in _ = await self?.streamURL(for: id) }
    }

    private func prefetchArtwork(for songs: [MusicSong]) {
        let urls = songs.prefix(16).compactMap { Self.artworkURL($0.cover) }
        Task.detached(priority: .utility) {
            for url in urls { _ = try? await URLSession.shared.data(from: url) }
        }
    }

    /// 0907 她抓的：陈璟点播的小卡片有封面，小唱片和播放页却是空转盘。
    /// 病根就在这儿拼的 ?param=600y600 —— 网易云图床的缩略图是**按需生成**的，
    /// 没生成过的尺寸直接回 404，而且每张图能活的尺寸都不一样（实测同一张
    /// 300 和 500 有、600 没有；另一张 300 和 600 都有）。缩到哪个尺寸能活全看运气。
    /// 小卡片没走这个函数、用的是原图，所以只有它有封面。
    /// 原图一定在，一张封面才几十 K，不值得为这点流量赌 404。
    /// pixels 保留是为了不动四处调用，但不再往地址上拼。
    static func artworkURL(_ raw: String, pixels: Int = 600) -> URL? {
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }
}

private struct NativeMusicView: View {
    @ObservedObject private var model = MusicModel.shared
    @State private var query = ""
    @State private var selectedPlaylist: MusicPlaylist?
    @State private var showPlayer = false
    @State private var giftSong: MusicSong?
    @State private var listenPage = false
    @State private var lastPlayingID: String?
    @AppStorage("alcoveTheme") private var themeName = "haven"
    private var theme: AlcoveTheme { .panelNamed(themeName) }

    var body: some View {
        VStack(spacing: 0) {
            if listenPage {
                listenTogetherPage
            } else {
                FoyerPanelTitle(title: selectedPlaylist?.name ?? "音乐", theme: theme)
                searchBar
                if let selectedPlaylist { playlistPage(selectedPlaylist) }
                else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.songs.isEmpty {
                    songList(model.songs)
                } else { homePage }
                if model.nowPlaying != nil {
                    MusicMiniPlayer(model: model) { showPlayer = true }
                        .padding(.horizontal, 14).padding(.bottom, 12)
                }
            }
        }
        .foregroundColor(theme.text)
        .foyerPanel(theme)
        .padding(.horizontal, 12).padding(.top, 8)
        .task {
            lastPlayingID = model.nowPlaying?.id
            model.startListenClock()
            await model.loadHome()
            if model.nowPlaying != nil { listenPage = true }
        }
        .onChange(of: model.nowPlaying?.id) { id in
            // 从"没在放"到"放起来"才自动进一起听；
            // 队列自动切下一首不把正在翻歌单的人拽走
            let wasIdle = lastPlayingID == nil
            lastPlayingID = id
            if id != nil, wasIdle { withAnimation(.easeOut(duration: 0.25)) { listenPage = true } }
        }
        .sheet(isPresented: $showPlayer) {
            MusicPlayerSheet(model: model)
                .presentationDetents([.fraction(0.75)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $giftSong) { song in
            MusicGiftSheet(song: song) { giftSong = nil }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private var searchBar: some View {
        HStack {
            if selectedPlaylist != nil {
                Button { selectedPlaylist = nil; model.playlistSongs = [] } label: {
                    Image(systemName: "chevron.left")
                }.buttonStyle(.plain)
            }
            Image(systemName: "magnifyingglass").foregroundColor(theme.textLight)
            TextField("搜索歌名或歌手", text: $query)
                .submitLabel(.search)
                .onSubmit { selectedPlaylist = nil; Task { await model.search(query) } }
            if model.loading { ProgressView().controlSize(.small).tint(theme.fyAccent) }
            else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { selectedPlaylist = nil; Task { await model.search(query) } } label: {
                    Image(systemName: "arrow.right.circle.fill").font(.system(size: 19))
                }.buttonStyle(.plain)
            }
        }.padding(11).foyerCard(theme).padding(.horizontal, 16).padding(.top, 10)
    }

    // MARK: 一起听
    private var listenTogetherPage: some View {
        VStack(spacing: 0) {
            HStack {
                Button { withAnimation(.easeOut(duration: 0.25)) { listenPage = false } } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                        .frame(width: 32, height: 32).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Spacer()
                Text("一起听").font(.system(size: 16, weight: .semibold))
                Spacer()
                Color.clear.frame(width: 32, height: 32)
            }.padding(.horizontal, 12).padding(.top, 10)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // 任务#1310：一起听是开关。开着他才"听见"，关着就是自己听
                    Button { withAnimation(.easeOut(duration: 0.2)) { model.togetherOn.toggle() } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: model.togetherOn ? "person.2.wave.2.fill" : "person.2")
                                .font(.system(size: 16))
                                .foregroundColor(model.togetherOn ? theme.fyAccent : theme.textDim)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.togetherOn ? "一起听中" : "开始一起听")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(model.togetherOn
                                     ? "他能收到切歌、查到放到哪句，点这里结束"
                                     : "开了他才听得见；不开就是你自己安静听")
                                    .font(.system(size: 10)).foregroundColor(theme.textDim)
                            }
                            Spacer()
                            Circle()
                                .fill(model.togetherOn ? Color.green.opacity(0.75) : theme.textDim.opacity(0.35))
                                .frame(width: 9, height: 9)
                        }.padding(13).foyerCard(theme)
                    }.buttonStyle(.plain)
                    ListenTogetherCard(model: model, theme: theme) { showPlayer = true }
                    if model.nowPlaying == nil {
                        VStack(spacing: 6) {
                            Image(systemName: "music.note.list").font(.system(size: 22))
                                .foregroundColor(theme.textDim)
                            Text("还没在放歌").font(.system(size: 13, weight: .medium))
                            Text("回上一页点一首，这里就热闹了")
                                .font(.system(size: 11)).foregroundColor(theme.textDim)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 26)
                    }
                    if model.queue.count > 1 {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("接下来").font(.system(size: 14, weight: .semibold))
                            ForEach(Array(model.queue.enumerated()), id: \.element.id) { index, song in
                                Button {
                                    let source = model.queue
                                    Task { await model.play(song, queue: source) }
                                } label: {
                                    HStack(spacing: 11) {
                                        Image(systemName: index == model.queueIndex ? "waveform" : "music.note")
                                            .font(.system(size: 13))
                                            .foregroundColor(index == model.queueIndex ? theme.fyAccent : theme.textDim)
                                            .frame(width: 20)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(song.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                            Text(song.artist).font(.system(size: 10)).foregroundColor(theme.textDim).lineLimit(1)
                                        }
                                        Spacer()
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }.padding(14).foyerCard(theme)
                    }
                }.padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
    }

    private var homePage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 13) {
                    AsyncImage(url: URL(string: "https://p1.music.126.net/_D-Yb1jPhcxPfnp66P1uYA==/109951170625651054.jpg")) { image in
                        image.resizable().scaledToFill()
                    } placeholder: { theme.fyCardSub }
                    .frame(width: 58, height: 58).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("hxhxhxxxxn").font(.system(size: 19, weight: .semibold))
                        Text("网易云音乐 · 已连接").font(.system(size: 11)).foregroundColor(theme.textDim)
                    }
                    Spacer()
                }.padding(14).foyerCard(theme)

                Button { withAnimation(.easeOut(duration: 0.25)) { listenPage = true } } label: {
                    HStack(spacing: 13) {
                        ZStack {
                            theme.fyAccent.opacity(0.16)
                            Image(systemName: "person.2.wave.2.fill")
                                .font(.system(size: 20)).foregroundColor(theme.fyAccent)
                        }
                        .frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("一起听").font(.system(size: 17, weight: .semibold))
                            Text(model.listenTimeText)
                                .font(.system(size: 11)).foregroundColor(theme.textDim)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13))
                            .foregroundColor(theme.textDim)
                    }.padding(12).foyerCard(theme)
                }.buttonStyle(.plain)

                if let liked = model.playlists.first {
                    Button { open(liked) } label: {
                        HStack(spacing: 13) {
                            AsyncImage(url: URL(string: liked.cover)) { $0.resizable().scaledToFill() }
                                placeholder: { theme.fyCardSub }
                                .frame(width: 68, height: 68).clipShape(RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 5) {
                                Text("我喜欢的音乐").font(.system(size: 17, weight: .semibold))
                                Text("\(liked.count) 首").font(.system(size: 11)).foregroundColor(theme.textDim)
                            }
                            Spacer(); Image(systemName: "heart.fill").foregroundColor(theme.fyAccent)
                        }.padding(12).foyerCard(theme)
                    }.buttonStyle(.plain)
                }

                playlistSection("我的歌单", items: Array(model.playlists.dropFirst()))
                playlistSection("为你推荐", items: model.recommended)
            }.padding(.horizontal, 16).padding(.vertical, 14)
        }
        .overlay { if model.homeLoading { ProgressView().tint(theme.fyAccent) } }
    }

    private func playlistSection(_ title: String, items: [MusicPlaylist]) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title).font(.system(size: 17, weight: .semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(items) { playlist in
                    Button { open(playlist) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            AsyncImage(url: URL(string: playlist.cover)) { $0.resizable().scaledToFill() }
                                placeholder: { theme.fyCardSub }
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 11))
                            Text(playlist.name).font(.system(size: 11, weight: .medium)).lineLimit(2)
                            Text("\(playlist.count) 首").font(.system(size: 9)).foregroundColor(theme.textDim)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func playlistPage(_ playlist: MusicPlaylist) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                AsyncImage(url: URL(string: playlist.cover)) { $0.resizable().scaledToFill() }
                    placeholder: { theme.fyCardSub }
                    .frame(width: 82, height: 82).clipShape(RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 7) {
                    Text(playlist.name).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                    Text("\(playlist.count) 首").font(.system(size: 11)).foregroundColor(theme.textDim)
                    Button { if let first = model.playlistSongs.first { Task { await model.play(first, queue: model.playlistSongs) } } } label: {
                        Label("播放全部", systemImage: "play.fill").font(.system(size: 11, weight: .medium))
                    }.buttonStyle(.borderedProminent).tint(theme.fyAccent)
                }; Spacer()
            }.padding(14)
            songList(model.playlistSongs)
        }.overlay { if model.loading { ProgressView().tint(theme.fyAccent) } }
    }

    private func songList(_ songs: [MusicSong]) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 5) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    HStack(spacing: 11) {
                        Button {
                            // 亲手点的歌：播起来并进一起听
                            withAnimation(.easeOut(duration: 0.25)) { listenPage = true }
                            Task { await model.play(song, queue: songs) }
                        } label: {
                            HStack(spacing: 11) {
                            Text("\(index + 1)").font(.system(size: 11, design: .monospaced))
                                .foregroundColor(theme.textLight).frame(width: 24)
                            AsyncImage(url: URL(string: song.cover)) { $0.resizable().scaledToFill() }
                                placeholder: { theme.fyCardSub }
                                .frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(song.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text(song.artist).font(.system(size: 10)).foregroundColor(theme.textDim).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: model.nowPlaying?.id == song.id && model.isPlaying ? "waveform" : "play.fill")
                                .foregroundColor(theme.fyAccent)
                            }
                        }
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        Button { giftSong = song } label: {
                            Image(systemName: "paperplane")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(theme.fyAccent)
                                .frame(width: 34, height: 34)
                                .background(theme.fyCardSub.opacity(0.72), in: Circle())
                        }.buttonStyle(.plain)
                    }.padding(.horizontal, 10).padding(.vertical, 6)
                }
            }.padding(.horizontal, 14).padding(.vertical, 8)
        }
    }

    private func open(_ playlist: MusicPlaylist) {
        query = ""
        selectedPlaylist = playlist
        Task { await model.loadPlaylist(playlist) }
    }
}

private struct MusicGiftSheet: View {
    let song: MusicSong
    let dismiss: () -> Void
    @State private var note = ""
    @State private var sending = false
    @State private var failed = false
    @AppStorage("alcoveTheme") private var themeName = "haven"
    private var theme: AlcoveTheme { .panelNamed(themeName) }

    var body: some View {
        VStack(spacing: 16) {
            Text("送给陈璟")
                .font(.system(size: 20, weight: .semibold, design: .serif))
            HStack(spacing: 13) {
                AsyncImage(url: URL(string: song.cover)) { $0.resizable().scaledToFill() }
                    placeholder: { theme.fyCardSub }
                    .frame(width: 66, height: 66).clipShape(RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.name).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                    Text(song.artist).font(.system(size: 12)).foregroundColor(theme.textDim)
                }
                Spacer()
                Image(systemName: "paperplane.fill").foregroundColor(theme.fyAccent)
            }
            .padding(12).foyerCard(theme)
            VStack(alignment: .leading, spacing: 6) {
                Text("捎一句话给他").font(.system(size: 11, weight: .medium)).foregroundColor(theme.textDim)
                TextField("为什么想把这首歌送给他…", text: $note, axis: .vertical)
                    .lineLimit(3...6).font(.system(size: 13))
                    .padding(11).background(theme.fyCardSub.opacity(0.62), in: RoundedRectangle(cornerRadius: 13))
            }
            if failed { Text("没送出去，再点一次试试").font(.system(size: 10)).foregroundColor(.red) }
            Button {
                guard !sending, let text = song.cardText(message: note) else { return }
                sending = true; failed = false
                Task {
                    do { _ = try await AlcoveAPI.send(text: text); dismiss() }
                    catch { failed = true; sending = false }
                }
            } label: {
                HStack { if sending { ProgressView().tint(.white) }; Text(sending ? "正在送给他" : "送给他"); Image(systemName: "paperplane.fill") }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 44)
                    .background(theme.fyAccent, in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain).disabled(sending)
        }
        .padding(20).foregroundColor(theme.text)
    }
}

/// AsyncImage 有两个毛病：下完不留、失败了不再试。聊天页一长，卡片滚出屏幕再滚回来
/// 就是一张空图，两张卡里能有一张永远是黑的（0826 她说咋一张有一张没有）。
/// 这个自己管：内存里留一份，拿不到就退避着再试两回，一张封面全卡片共用。
@MainActor
final class CoverLoader: ObservableObject {
    private static let cache = NSCache<NSString, UIImage>()
    @Published var image: UIImage?
    private var loading = false

    func load(_ raw: String) {
        guard !raw.isEmpty, image == nil, !loading else { return }
        if let hit = Self.cache.object(forKey: raw as NSString) {
            image = hit
            return
        }
        guard let url = URL(string: raw) else { return }
        loading = true
        Task {
            defer { loading = false }
            for attempt in 0..<3 {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let picture = UIImage(data: data) {
                    Self.cache.setObject(picture, forKey: raw as NSString)
                    withAnimation(.easeInOut(duration: 0.25)) { image = picture }
                    return
                }
                try? await Task.sleep(nanoseconds: 400_000_000 << UInt64(attempt))
            }
        }
    }
}

struct MusicMessageCard: View {
    let song: MusicSong
    let theme: AlcoveTheme
    let isUser: Bool
    let play: () -> Void
    @ObservedObject private var model = MusicModel.shared
    @StateObject private var cover = CoverLoader()
    @State private var messageExpanded = false
    @State private var showPlayer = false

    private var isCurrent: Bool { model.nowPlaying?.id == song.id }
    private var isPlaying: Bool { isCurrent && model.isPlaying }
    private var progressFraction: Double {
        guard isCurrent, model.duration > 0 else { return 0 }
        return min(max(model.progress / model.duration, 0), 1)
    }

    /// 一行大概装得下二十来个字，超了才给展开键（0826 她要收起时只留一行）
    private var needsToggle: Bool { song.message.count > 17 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 11) {
                // 点播那一行跟歌名歌手叠在同一列里，别自己独占一行，
                // 独占会白吃掉二十来点高度，卡片就立起来了（0826 她说太高）
                VStack(alignment: .leading, spacing: 3) {
                    Text(isUser ? "♫ 送给陈璟" : "♫ 为你点播")
                        .font(.system(size: 10.5, weight: .medium))
                        .tracking(1.1)
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.bottom, 1)
                    Text(song.name).font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white).lineLimit(1)
                    Text(song.artist).font(.system(size: 12.5))
                        .foregroundColor(.white.opacity(0.55)).lineLimit(1)
                }
                Spacer(minLength: 8)
                vinyl
                Button {
                    // A card may point at the same song that was previewed in the
                    // music page, while that old AVPlayer is already paused,
                    // expired or failed.  Re-open the stream instead of toggling
                    // a stale player; only the visible playing state is paused.
                    if isCurrent && isPlaying { model.toggle() } else { play() }
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13.5, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                        .background(Color.white.opacity(0.18), in: Circle())
                        // 圆看着 38，手指够得着的是 46。原来 36 太小，
                        // 点边上就落空了（0826 她说第一张点不了）
                        .frame(width: 46, height: 46)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }

            if !song.message.isEmpty { messageRow }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        // 先撑满可用宽度再压到 340，否则留言短的时候卡片会跟着内容缩水，
        // 看着又窄又立（0826 她说长度有点短）。也不再给高度下限。
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxWidth: 340)
        .background(backdrop)
        .overlay(alignment: .bottomLeading) {
            GeometryReader { geo in
                Capsule().fill(Color.white.opacity(0.6))
                    .frame(width: geo.size.width * CGFloat(progressFraction), height: 2)
            }
            .frame(height: 2)
            .animation(.linear(duration: 0.3), value: progressFraction)
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        // 她的聊天背景是纯黑，参考图那种阴影在黑底上等于没有，得留一道边。
        // 三层装饰一律不吃点击，免得压在播放键和展开箭头上面
        // （0826 她说第一张卡什么都点不动）
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.4), radius: 16, y: 7)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            // Opening the current track must not restart it or toggle pause.
            if !isCurrent { play() }
            showPlayer = true
        }
        .sheet(isPresented: $showPlayer) {
            MusicPlayerSheet(model: model)
                .presentationDetents([.fraction(0.72)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .onAppear { cover.load(song.cover) }
    }

    /// 底色不是算出来的，是把封面自己糊开：放大、模糊、加饱和、压暗。
    /// 每首歌的卡片就长成那张封面的颜色。
    /// 封面没来的时候得有张脸兜着，不然整张卡烂成一块纯黑，跟聊天背景糊成一片
    /// 连边都找不着（0826 她 build 出来就是这样）。
    private var backdrop: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.black.opacity(0.42)
            // 用跟音乐页一模一样的裸链，那条她确认一直是好的；
            // 尺寸也给死，装在 background 里的 AsyncImage 拿不到固有尺寸会塌成零，
            // 图下回来了也不画（0826 她说只有这张卡没图）。
            if let picture = cover.image {
                GeometryReader { geo in
                    ZStack {
                        Image(uiImage: picture).resizable().scaledToFill()
                            .frame(width: geo.size.width * 1.5,
                                   height: geo.size.height * 1.5)
                            .blur(radius: 30)
                            .saturation(1.55)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                        Color.black.opacity(0.3)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// 黑胶：黑盘打底，压两圈纹路，封面嵌在中间，中心留个孔
    private var vinyl: some View {
        ZStack {
            Circle().fill(
                AngularGradient(
                    gradient: Gradient(colors: [
                        Color(white: 0.10), Color(white: 0.18), Color(white: 0.10),
                        Color(white: 0.18), Color(white: 0.10),
                    ]),
                    center: .center)
            )
            Circle().stroke(Color.white.opacity(0.05), lineWidth: 0.8).padding(3.5)
            Circle().stroke(Color.white.opacity(0.035), lineWidth: 0.8).padding(6.5)
            Group {
                if let picture = cover.image {
                    Image(uiImage: picture).resizable().scaledToFill()
                } else {
                    ZStack {
                        Color(white: 0.13)
                        Image(systemName: "music.note")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.28))
                    }
                }
            }
            .frame(width: 39, height: 39)
            .clipShape(Circle())
            Circle().fill(Color(white: 0.05)).frame(width: 8.5, height: 8.5)
            Circle().stroke(Color.white.opacity(0.07), lineWidth: 0.6)
        }
        .frame(width: 56, height: 56)
    }

    /// 收起的时候把留言里的换行抹成空格。她那条留言原文带三个换行，
    /// 配上 fixedSize(vertical:) 之后这一行的固有高度是四行，lineLimit(1) 只管画一行，
    /// 底下三行的高度照样撑着，整张卡的点击落点就全歪了，播放键和展开箭头一起点不动
    /// （0826 她说第一张什么都点不动，第二张那条留言没有换行所以好好的）。
    private var messageLine: String {
        messageExpanded ? song.message
                        : song.message.replacingOccurrences(of: "\n", with: " ")
    }

    private var messageRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("›  \(messageLine)")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.62))
                .lineLimit(messageExpanded ? nil : 1)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: messageExpanded)
            if needsToggle {
                Spacer(minLength: 0)
                Button { withAnimation(.easeInOut(duration: 0.2)) { messageExpanded.toggle() } } label: {
                    Image(systemName: "chevron.down.circle")
                        .font(.system(size: 13, weight: .medium))
                        .rotationEffect(.degrees(messageExpanded ? 180 : 0))
                        .foregroundColor(.white.opacity(0.5))
                }.buttonStyle(.plain)
            }
        }
    }
}

/// 一起听页顶部的小卡片：两个人的头像 + 累计时长 + 正在放的歌和进度
private struct ListenTogetherCard: View {
    @ObservedObject var model: MusicModel
    let theme: AlcoveTheme
    let open: () -> Void
    @AppStorage("userAvatarDataURL") private var userAvatar = ""
    @AppStorage("assistantAvatarDataURL") private var assistantAvatar = ""

    var body: some View {
        VStack(spacing: 13) {
            ZStack {
                ListenArc()
                    .stroke(theme.fyAccent.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                    .frame(height: 74)
                    .padding(.horizontal, 26)
                HStack {
                    avatarView(userAvatar, fallback: "霁")
                    Spacer()
                    VStack(spacing: 3) {
                        Text("霁 · 璟").font(.system(size: 14, weight: .medium))
                        Text(model.listenTimeText)
                            .font(.system(size: 11)).foregroundColor(theme.textDim)
                    }
                    Spacer()
                    avatarView(assistantAvatar, fallback: "璟")
                }.padding(.horizontal, 8)
            }
            if let song = model.nowPlaying {
                VStack(spacing: 9) {
                    HStack(spacing: 4) {
                        Text(song.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text("— \(song.artist)").font(.system(size: 12)).foregroundColor(theme.textDim).lineLimit(1)
                    }
                    VStack(spacing: 2) {
                        Slider(value: Binding(get: { model.progress }, set: { model.seek(to: $0) }),
                               in: 0...max(model.duration, 1)).tint(theme.fyAccent)
                        HStack {
                            Text(Self.time(model.progress)); Spacer(); Text(Self.time(model.duration))
                        }.font(.system(size: 9, design: .monospaced)).foregroundColor(theme.textDim)
                    }
                    HStack {
                        Button { Task { await model.toggleLike() } } label: {
                            Image(systemName: model.currentIsLiked ? "heart.fill" : "heart")
                                .foregroundColor(model.currentIsLiked ? .red : theme.text)
                        }
                        Spacer()
                        Button { model.prev() } label: { Image(systemName: "backward.fill") }
                        Spacer()
                        Button { model.toggle() } label: {
                            Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 34))
                        }
                        Spacer()
                        Button { model.next() } label: { Image(systemName: "forward.fill") }
                        Spacer()
                        Button { model.cyclePlayMode() } label: { Image(systemName: model.playMode.icon) }
                    }
                    .font(.system(size: 16)).buttonStyle(.plain)
                    .padding(.horizontal, 6)
                }
                .padding(13)
                .background(theme.fyCardSub.opacity(0.55), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture(perform: open)
            }
        }
        .padding(15).foyerCard(theme)
    }

    private func avatarView(_ dataURL: String, fallback: String) -> some View {
        Group {
            if let image = Self.decode(dataURL) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    theme.fyCardSub
                    Text(fallback).font(.system(size: 20, weight: .medium))
                }
            }
        }
        .frame(width: 58, height: 58).clipShape(Circle())
        .overlay(Circle().stroke(theme.fyAccent.opacity(0.4), lineWidth: 1.5))
    }

    private static func decode(_ dataURL: String) -> UIImage? {
        let parts = dataURL.split(separator: ",", maxSplits: 1)
        guard let data = Data(base64Encoded: parts.count == 2 ? String(parts[1]) : dataURL) else { return nil }
        return UIImage(data: data)
    }

    private static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

/// 两个头像之间那道下垂的虚线弧
struct ListenArc: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY - 8))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY - 8),
                       control: CGPoint(x: rect.midX, y: rect.maxY + 14))
        return p
    }
}

// MARK: - 一起听 · 主聊天页的白瓷波点房间（任务#1308）
// 棋牌室质感（白瓷、波点、高光、细描边），但日夜跟聊天主题走：
// 夜里压成中性深灰，不发蓝（她点名的）。

struct ListenPorcelain {
    let dark: Bool
    var fog: Color    { pick(0xECEDF2, 0x1F1F23) }
    var panel: Color  { pick(0xF7F8FB, 0x2A2A2F) }
    var ink: Color    { pick(0x585F6E, 0xD9D9DE) }
    var inkDim: Color { pick(0x9AA0AD, 0x8D8D95) }
    var line: Color   { pick(0xD5D9E2, 0x3A3A41) }
    var dot: Color    { pick(0xC7CBD6, 0x36363D) }
    var accent: Color { pick(0x7C8AA6, 0xA9A195) }
    var gloss: Double { dark ? 0.10 : 0.6 }
    private func pick(_ day: UInt32, _ night: UInt32) -> Color {
        QipaiPalette.qhex(dark ? night : day)
    }
}

struct ListenPanel: ViewModifier {
    let p: ListenPorcelain
    var corner: CGFloat = 18
    var dotted = false
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous).fill(p.panel)
                    if dotted {
                        QipaiDots(color: p.dot, opacity: 0.4)
                            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    }
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0)],
                                             startPoint: .top, endPoint: .center))
                        .padding(1).opacity(p.gloss)
                }
            )
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(p.line, lineWidth: 1))
            .shadow(color: (p.dark ? Color.black : QipaiPalette.qhex(0x585F6E)).opacity(0.10),
                    radius: 7, y: 3)
    }
}

/// 1006 她要的：一起听不再钉白瓷大卡，改成陈璟名字下面一条胶囊（效果图 /root/workroom/mock/listen-capsule/chat.jpg，照她发的参考图）：
/// 两颗叠着的小头像、音柱（放歌时跳）、歌名 · 歌手、右边播放/暂停。半透原生玻璃，不染色（跟顶栏按钮同一种）。
/// 点胶囊 → 半屏播放器（歌词、发歌词都在那儿）；长按 → 收成小唱片 / 结束一起听。
struct ListenCapsule: View {
    @ObservedObject var model: MusicModel
    let dark: Bool
    let off: () -> Void
    let openPlayer: () -> Void
    let minimize: () -> Void
    @AppStorage("userAvatarDataURL") private var userAvatar = ""
    @AppStorage("assistantAvatarDataURL") private var assistantAvatar = ""

    private var ink: Color { dark ? .white : Color(red: 0.114, green: 0.114, blue: 0.133) }
    private var dim: Color { dark ? .white.opacity(0.62) : Color(red: 0.36, green: 0.376, blue: 0.416) }

    var body: some View {
        HStack(spacing: 7) {
            HStack(spacing: -9) {
                avatar(userAvatar, fallback: "霁")
                avatar(assistantAvatar, fallback: "璟")
            }
            ListenEqualizer(playing: model.isPlaying, color: ink)
                .padding(.leading, 3)
            if let song = model.nowPlaying {
                HStack(spacing: 5) {
                    Text(song.name).font(.system(size: 15, weight: .semibold)).foregroundColor(ink)
                        .lineLimit(1).layoutPriority(1)
                    if !song.artist.isEmpty {
                        Text("·").font(.system(size: 13)).foregroundColor(dim)
                        Text(song.artist).font(.system(size: 14.5)).foregroundColor(dim).lineLimit(1)
                    }
                }
            }
            Button { model.toggle() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(ink)
                    .frame(width: 28, height: 28)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 4)
        .frame(height: 36)
        .glassEffect(.regular.interactive(), in: Capsule())
        .contentShape(Capsule())
        .onTapGesture(perform: openPlayer)
        .contextMenu {
            Button { minimize() } label: { Label("收成小唱片", systemImage: "record.circle") }
            Button(role: .destructive) { off() } label: { Label("结束一起听", systemImage: "xmark") }
        }
    }

    private func avatar(_ dataURL: String, fallback: String) -> some View {
        Group {
            if let image = Self.decode(dataURL) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.35)
                    Text(fallback).font(.system(size: 11, weight: .medium)).foregroundColor(ink)
                }
            }
        }
        .frame(width: 28, height: 28).clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
    }

    private static func decode(_ dataURL: String) -> UIImage? {
        let parts = dataURL.split(separator: ",", maxSplits: 1)
        guard let data = Data(base64Encoded: parts.count == 2 ? String(parts[1]) : dataURL) else { return nil }
        return UIImage(data: data)
    }
}

/// 胶囊里的三根音柱：放歌时上下跳，暂停停在一高一矮
private struct ListenEqualizer: View {
    let playing: Bool
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !playing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    let rest: [CGFloat] = [7, 12, 9]
                    let h = playing ? 4 + 8 * CGFloat(abs(sin(t * (5.2 + Double(i) * 1.7) + Double(i) * 1.1))) : rest[i]
                    RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 3, height: h)
                }
            }
            .frame(height: 12, alignment: .bottom)
        }
    }
}

/// 0902 她要的小唱片：整个 app 唯一一种「歌在放」的收起态。
/// 圆封面像唱片一样转（放歌时 8 秒一圈，暂停停住），外圈一圈进度环，中心一个小孔；
/// 右下角一颗小播放/暂停键；一起听开着时左上角一个小「俩」标。
/// 点唱片：一起听开着且在主聊天 → 大卡回来；否则 → 从**这一层浮窗**弹出播放器
///   （0902 她抓的：播放器挂在主聊天那层弹，会把盖在上面的工作室页顶掉；浮窗永远在最上面，在哪都不顶谁）。
/// 长按：展开成小长条（进度条 + 上一首/暂停/下一首），三秒没碰自己缩回唱片。
struct ListenRecordPill: View {
    @ObservedObject var model: MusicModel
    /// 一起听开着时点唱片能不能把大卡叫回来（只有主聊天页露着的时候能）。RootView 算好传进来
    var canRestoreCard: Bool = false
    // 0904 她定的：左上角「俩」字标换成两颗叠着的小头像（跟一起听大卡同一份存储）
    @AppStorage("userAvatarDataURL") private var userAvatar = ""
    @AppStorage("assistantAvatarDataURL") private var assistantAvatar = ""

    // 0902 深夜她抓的「一秒一卡」→ 0903 又抓到「半秒一卡」。第一版是 30Hz Timer 拨 angle；
    // 第二版 TimelineView 按时间算角度，还是卡：progress 每半秒 publish 一次，这个 struct 整个重画，
    // 转动在 SwiftUI 那层就被打断一下。第三版彻底不让 SwiftUI 转它：封面是一个 UIView，
    // 用 Core Animation 转（SpinningCover），动画跑在渲染服务器上，界面重画多少次都不管它；
    // 暂停就把图层时间停住，继续从停的地方接着转。
    @State private var expanded = false
    @State private var collapseTask: Task<Void, Never>?
    private let size: CGFloat = 62
    private let secondsPerTurn: Double = 8

    var body: some View {
        Group {
            if expanded { strip } else { disc }
        }
    }

    // MARK: 唱片

    private var disc: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.35), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progressFraction)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            record(diameter: size - 10)
        }
        .frame(width: size, height: size)
        .background(Circle().fill(Color.black.opacity(0.28)))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        .contentShape(Circle())
        .onTapGesture(perform: tapped)
        .onLongPressGesture(minimumDuration: 0.4) { expand() }
        .overlay(alignment: .bottomTrailing) {
            Button { model.toggle() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.black.opacity(0.6)))
                    .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .offset(x: 3, y: 3)
        }
        .overlay(alignment: .topLeading) {
            if model.togetherOn {
                // 0904 她定的：粉紫「俩」字标 → 两颗叠着的小头像（她在前，他叠在后）
                HStack(spacing: -6) {
                    miniAvatar(userAvatar, fallback: "霁")
                    miniAvatar(assistantAvatar, fallback: "璟")
                }
                .offset(x: -4, y: -4)
            }
        }
    }

    /// 一起听角标用的小圆头像：15pt，白描边；没设头像就黑玻璃底 + 单字，跟右下角暂停键一个质感
    private func miniAvatar(_ dataURL: String, fallback: String) -> some View {
        Group {
            if let img = Self.decodeAvatar(dataURL) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Color.black.opacity(0.6))
                    Text(fallback).font(.system(size: 8, weight: .medium)).foregroundColor(.white)
                }
            }
        }
        .frame(width: 15, height: 15)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
    }

    private static func decodeAvatar(_ dataURL: String) -> UIImage? {
        let parts = dataURL.split(separator: ",", maxSplits: 1)
        guard let data = Data(base64Encoded: parts.count == 2 ? String(parts[1]) : dataURL) else { return nil }
        return UIImage(data: data)
    }

    /// 转着的封面 + 中心小孔。封面由 Core Animation 转（见 SpinningCover），小孔是圆的，不用跟着转
    private func record(diameter: CGFloat) -> some View {
        ZStack {
            SpinningCover(url: model.nowPlaying.flatMap { MusicModel.artworkURL($0.cover) },
                          playing: model.isPlaying, secondsPerTurn: secondsPerTurn)
            Circle().fill(Color.black.opacity(0.55)).frame(width: diameter * 0.19, height: diameter * 0.19)
            Circle().stroke(Color.white.opacity(0.6), lineWidth: 1).frame(width: diameter * 0.19, height: diameter * 0.19)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
    }

    private var progressFraction: CGFloat {
        CGFloat(model.duration > 0 ? min(1, model.progress / model.duration) : 0)
    }

    // MARK: 长按展开的小长条

    private var strip: some View {
        HStack(spacing: 10) {
            record(diameter: 40)
                .onTapGesture(perform: tapped)
            VStack(spacing: 6) {
                if let song = model.nowPlaying {
                    // 0902 她要的：歌名后面带歌手。0903 她说跑马灯算了（那版在她机器上压根没显示出来）：
                    // 固定不滚，放不下就省略号
                    HStack(spacing: 5) {
                        Text(song.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .layoutPriority(1)
                        if !song.artist.isEmpty {
                            Text("— " + song.artist)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 16)
                }
                Slider(value: Binding(get: { model.progress }, set: { model.seek(to: $0); bump() }),
                       in: 0...max(model.duration, 1)) { editing in
                    if editing { collapseTask?.cancel() } else { bump() }
                }
                .tint(.white)
                .scaleEffect(y: 0.7)
                HStack(spacing: 22) {
                    Button { model.prev(); bump() } label: { Image(systemName: "backward.fill") }
                    Button { model.toggle(); bump() } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    }
                    Button { model.next(); bump() } label: { Image(systemName: "forward.fill") }
                    // 0903 她发现的：一直没有「叉掉听歌」的地方。放在长按展开的这条里：停播、清掉、小唱片跟着消失
                    Button { model.stopAndClear() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.75))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.white.opacity(0.14)))
                    }
                }
                .font(.system(size: 15))
                .foregroundColor(.white)
                .buttonStyle(.plain)
            }
            .frame(width: 150)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.black.opacity(0.62)))
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    // MARK: 行为

    private func tapped() {
        if model.togetherOn && canRestoreCard {
            NotificationCenter.default.post(name: .alcoveListenRestore, object: nil)
        } else {
            // 从 app 最上面那页弹播放器：在工作室/共读室里点也不会把那页顶掉
            FloatingOverlay.shared.present { MusicPlayerSheet(model: model) }
        }
    }

    private func expand() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { expanded = true }
        bump()
    }

    /// 每碰一下重新数三秒，三秒没碰缩回唱片
    private func bump() {
        collapseTask?.cancel()
        collapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { expanded = false }
        }
    }
}

/// 跑马灯：内容比容器窄就原地不动；宽了就慢慢往左滚到头、停一下、再滚回来，循环。
/// 0902 她要的，给小唱片长条上的歌名用（歌名加歌手一行放不下时）。
/// 0903：小唱片的封面。UIImageView 装封面，图层用 CABasicAnimation 一直转，
/// 暂停 = 图层时间停住（speed 0 + timeOffset），继续 = 从停的地方接着走。
/// 进过后台系统会把图层动画扔掉，所以每次 update 发现动画没了就重新挂一遍。
final class SpinningCoverUIView: UIView {
    private let imageView = UIImageView()
    private var url: URL?
    private var spinning = false
    private var turn: Double = 8

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.35)
        clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        layer.cornerRadius = bounds.width / 2
    }

    func load(_ u: URL?) {
        guard u != url else { return }
        url = u
        imageView.image = nil
        guard let u else { return }
        URLSession.shared.dataTask(with: u) { [weak self] data, _, _ in
            guard let data, let img = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                guard let self, self.url == u else { return }
                self.imageView.image = img
            }
        }.resume()
    }

    func setSpinning(_ on: Bool, secondsPerTurn: Double) {
        turn = secondsPerTurn
        if layer.animation(forKey: "spin") == nil {
            let a = CABasicAnimation(keyPath: "transform.rotation.z")
            a.fromValue = 0
            a.toValue = Double.pi * 2
            a.duration = turn
            a.repeatCount = .infinity
            a.isRemovedOnCompletion = false
            layer.add(a, forKey: "spin")
            // 先挂着不动，下面按 on 决定走不走
            layer.speed = 0
            layer.timeOffset = 0
            layer.beginTime = 0
            spinning = false
        }
        guard on != spinning else { return }
        spinning = on
        if on {
            let paused = layer.timeOffset
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            let sincePause = layer.convertTime(CACurrentMediaTime(), from: nil) - paused
            layer.beginTime = sincePause
        } else {
            let now = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0
            layer.timeOffset = now
        }
    }
}

struct SpinningCover: UIViewRepresentable {
    let url: URL?
    let playing: Bool
    let secondsPerTurn: Double

    func makeUIView(context: Context) -> SpinningCoverUIView {
        let v = SpinningCoverUIView()
        v.load(url)
        v.setSpinning(playing, secondsPerTurn: secondsPerTurn)
        return v
    }

    func updateUIView(_ v: SpinningCoverUIView, context: Context) {
        v.load(url)
        v.setSpinning(playing, secondsPerTurn: secondsPerTurn)
    }
}

struct MarqueeText<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var contentW: CGFloat = 0
    @State private var boxW: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflow: CGFloat { max(0, contentW - boxW) }

    var body: some View {
        GeometryReader { geo in
            content()
                .background(GeometryReader { g in
                    Color.clear.onAppear { contentW = g.size.width }
                        .onChange(of: g.size.width) { contentW = $0 }
                })
                .offset(x: -offset)
                .frame(width: geo.size.width, alignment: .leading)
                .clipped()
                .onAppear { boxW = geo.size.width; restart() }
                .onChange(of: geo.size.width) { boxW = $0; restart() }
                .onChange(of: contentW) { _ in restart() }
        }
    }

    /// 每边停 1.2 秒，滚的速度按字数算（每秒 30pt），来回一趟
    private func restart() {
        offset = 0
        guard overflow > 0 else { return }
        let travel = Double(overflow) / 30.0
        withAnimation(.linear(duration: travel).delay(1.2).repeatForever(autoreverses: true)) {
            offset = overflow
        }
    }
}

struct MusicMiniPlayer: View {
    @ObservedObject var model: MusicModel
    let open: () -> Void
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    /// 1002：Kakao 下跟输入框一样借信息主题那套，深浅只认全屋按钮（原来拿包的输入框底＋包的字色，不跟黑白翻）
    private var theme: AlcoveTheme {
        _ = houseAppearance
        guard AlcoveAppearance.chatOnly(themeName) else { return .named(themeName) }   // 1009 树屋的输入框同理
        return .named(AlcoveAppearance.isDark ? "imessage-dark" : "imessage")
    }

    var body: some View {
        if let song = model.nowPlaying {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    AsyncImage(url: URL(string: song.cover)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: { theme.glassTint }
                    .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(song.artist).font(.system(size: 11)).foregroundColor(theme.textDim).lineLimit(1)
                    }
                }.contentShape(Rectangle()).onTapGesture(perform: open)
                Spacer()
                Button { model.prev() } label: { Image(systemName: "backward.fill") }.buttonStyle(.plain)
                Button { model.toggle() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").frame(width: 30, height: 32)
                }.buttonStyle(.plain)
                Button { model.next() } label: { Image(systemName: "forward.fill") }.buttonStyle(.plain)
                Button { model.stopAndClear() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .medium)).frame(width: 28, height: 32)
                }.buttonStyle(.plain)
            }
            .foregroundColor(theme.text)
            .padding(.horizontal, 10).frame(height: 62)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background(theme.capsuleTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geo in
                    Capsule().fill(theme.fyAccent)
                        .frame(width: geo.size.width * CGFloat(model.duration > 0 ? model.progress / model.duration : 0), height: 2)
                }.frame(height: 2)
            }
        }
    }
}

struct MusicPlayerSheet: View {
    @ObservedObject var model: MusicModel
    @AppStorage("alcoveTheme") private var themeName = "haven"
    private var theme: AlcoveTheme { .panelNamed(themeName) }
    @State private var page = 0
    @State private var showQueue = false
    @State private var showInsight = false
    /// 1006 她报：一滑歌词，到下一句又被拽回正在唱的那句。手一碰就不跟了，点「回到正在唱」或换歌才接着跟
    @State private var followLyric = true
    /// 1006 她要的：发歌词搬到这儿。点一句选中（可以选几句），再点取消
    @State private var pickedLines: Set<Int> = []

    var body: some View {
        GeometryReader { bounds in
            ZStack {
                if let cover = model.nowPlaying?.cover {
                    AsyncImage(url: MusicModel.artworkURL(cover)) { image in
                        image.resizable().scaledToFill()
                            .frame(width: bounds.size.width, height: bounds.size.height)
                            .clipped()
                    } placeholder: {
                        LinearGradient(colors: theme.splashBg, startPoint: .top, endPoint: .bottom)
                            .frame(width: bounds.size.width, height: bounds.size.height)
                    }
                    .frame(width: bounds.size.width, height: bounds.size.height)
                    .clipped()
                    .blur(radius: 48).opacity(0.42)
                }
                LinearGradient(colors: [.black.opacity(0.22), .black.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(width: bounds.size.width, height: bounds.size.height)
                Group {
                    if page == 0 { playerPage }
                    else { lyricPage }
                }
                .frame(width: bounds.size.width, height: bounds.size.height)
                .clipped()
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 28)
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height),
                                  abs(value.translation.width) > 45 else { return }
                            withAnimation(.easeOut(duration: 0.2)) {
                                if value.translation.width < 0 { page = 1 }
                                else { page = 0 }
                            }
                        }
                )
            }
            .frame(width: bounds.size.width, height: bounds.size.height)
            .clipped()
        }
        .ignoresSafeArea(edges: .bottom)
        .foregroundColor(.white)
        .sheet(isPresented: $showQueue) { MusicQueueSheet(model: model) }
        .sheet(isPresented: $showInsight) {
            if let song = model.nowPlaying {
                SongInsightSheet(song: song)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var playerPage: some View {
        VStack(spacing: 0) {
            if let song = model.nowPlaying {
                playerHeader(song)
                Spacer(minLength: 4)
                record(song, size: 190)
                Spacer(minLength: 8)
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(song.name).font(.system(size: 21, weight: .semibold)).lineLimit(1)
                        Text(song.artist).font(.system(size: 13)).foregroundColor(.white.opacity(0.62)).lineLimit(1)
                    }
                    Spacer()
                    likeButton
                }.padding(.horizontal, 28)
                progressControls
                playbackControls
                pageDots
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var lyricPage: some View {
        VStack(spacing: 0) {
            if let song = model.nowPlaying { playerHeader(song) }
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .center, spacing: 4) {
                    Color.clear.frame(height: 70)
                    if model.lyricsLoading { ProgressView().frame(maxWidth: .infinity) }
                    else if model.lyrics.isEmpty {
                        Text("这首没有歌词").foregroundColor(theme.textDim).frame(maxWidth: .infinity)
                    } else {
                        ForEach(Array(model.lyrics.enumerated()), id: \.element.id) { index, line in
                            lyricRow(index, line).id(index)
                        }
                    }
                    Color.clear.frame(height: 110)
                }.frame(maxWidth: .infinity).padding(.horizontal, 26)
                }
                .onScrollPhaseChange { _, phase in
                    if phase == .interacting { followLyric = false }
                }
                .onChange(of: activeLyric) { idx in
                    guard followLyric, idx >= 0 else { return }
                    withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(idx, anchor: .center) }
                }
                .onChange(of: model.nowPlaying?.id) { _ in
                    followLyric = true
                    pickedLines = []
                }
                .overlay(alignment: .bottom) {
                    if !followLyric {
                        Button {
                            followLyric = true
                            let idx = activeLyric
                            if idx >= 0 { withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(idx, anchor: .center) } }
                        } label: {
                            Text("回到正在唱 ↓").font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .glassEffect(.regular.interactive(), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 10)
                        .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: followLyric)
            }
            HStack {
                likeButton
                Spacer()
                sendLyricButton
            }
                .padding(.horizontal, 30).padding(.top, 8)
            progressControls
            playbackControls
            pageDots
        }
    }

    /// 一句歌词：点了选中（左边打勾、套一层浅玻璃框），选中的右边一颗小播放键＝从这句放
    private func lyricRow(_ index: Int, _ line: MusicLyric) -> some View {
        let now = index == activeLyric
        let picked = pickedLines.contains(index)
        return VStack(alignment: .center, spacing: 5) {
            Text(line.text).font(.system(size: now ? 19 : 15, weight: now ? .semibold : .regular))
                .multilineTextAlignment(.center)
                .foregroundColor(now || picked ? .white : .white.opacity(0.68))
            if let trans = line.translation, !trans.isEmpty {
                Text(trans).font(.system(size: 11)).foregroundColor(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, picked ? 34 : 0)
        .padding(.vertical, 9)
        .background {
            if picked {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.45), lineWidth: 1))
            }
        }
        .overlay(alignment: .leading) {
            if picked {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundColor(.black.opacity(0.8))
                    .frame(width: 18, height: 18).background(.white, in: Circle())
                    .padding(.leading, 12)
            }
        }
        .overlay(alignment: .trailing) {
            if picked {
                Button { model.seek(to: line.time) } label: {
                    Image(systemName: "play.fill").font(.system(size: 8))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
            }
        }
        .opacity(now || picked ? 1 : 0.86)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) {
                if picked { pickedLines.remove(index) } else { pickedLines.insert(index) }
            }
        }
    }

    /// 右下角：没选就发正在唱的那句，选了就发选中的几句；发完清掉选中
    private var sendLyricButton: some View {
        let count = pickedLines.count
        let title = model.lineSentFlash ? "发好了" : (count > 1 ? "把这 \(count) 句发给他" : "把这句发给他")
        return Button {
            let lines = pickedLines.isEmpty ? [activeLyric] : Array(pickedLines)
            Task {
                if await model.sendLyrics(lines) {
                    withAnimation(.easeOut(duration: 0.15)) { pickedLines = [] }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if model.lineSending { ProgressView().controlSize(.mini).tint(.white) }
                else { Image(systemName: model.lineSentFlash ? "checkmark" : "paperplane.fill").font(.system(size: 12, weight: .semibold)) }
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 15).padding(.vertical, 7)
            .background(.white.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(model.lyrics.isEmpty || model.lineSending || (pickedLines.isEmpty && activeLyric < 0))
        .opacity(model.lyrics.isEmpty ? 0.35 : 1)
    }

    private func playerHeader(_ song: MusicSong) -> some View {
        VStack(spacing: 2) {
            Text(song.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            Text(song.artist).font(.system(size: 10)).foregroundColor(.white.opacity(0.55)).lineLimit(1)
        }.frame(maxWidth: .infinity).padding(.horizontal, 48).padding(.top, 16).padding(.bottom, 8)
    }

    private func record(_ song: MusicSong, size: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle().fill(.black.opacity(0.82))
                ForEach(1..<7) { ring in
                    Circle().stroke(.white.opacity(0.035), lineWidth: 1)
                        .padding(CGFloat(ring) * 11)
                }
                AsyncImage(url: MusicModel.artworkURL(song.cover)) { $0.resizable().scaledToFill() }
                    placeholder: { Color.white.opacity(0.08) }
                    .frame(width: size * 0.57, height: size * 0.57).clipShape(Circle())
                Circle().fill(.black.opacity(0.7)).frame(width: 12, height: 12)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
            ZStack(alignment: .top) {
                Circle().fill(.black.opacity(0.7)).frame(width: 34, height: 34)
                    .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 2))
                Capsule().fill(.white.opacity(0.72)).frame(width: 8, height: size * 0.48)
                    .overlay(alignment: .bottom) { Capsule().fill(.black.opacity(0.78)).frame(width: 18, height: 35).offset(y: 18) }
                    .offset(y: 18)
            }
            .rotationEffect(.degrees(model.isPlaying ? 22 : 8), anchor: .top)
            .animation(.easeInOut(duration: 0.45), value: model.isPlaying)
            .offset(x: 12, y: -17)
        }.frame(width: size + 35, height: size)
    }

    private var likeButton: some View {
        Button { Task { await model.toggleLike() } } label: {
            Image(systemName: model.currentIsLiked ? "heart.fill" : "heart")
                .font(.system(size: 23))
                .foregroundColor(model.currentIsLiked ? .red : .white)
                .frame(width: 42, height: 42)
        }.buttonStyle(.plain)
    }

    private var progressControls: some View {
        VStack(spacing: 2) {
            HStack(spacing: 12) {
                Slider(value: Binding(get: { model.progress }, set: { model.seek(to: $0) }),
                       in: 0...max(model.duration, 1)).tint(.white)
                Button { showInsight = true } label: {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 17))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            HStack {
                Text(Self.time(model.progress)); Spacer(); Text(Self.time(model.duration))
            }.font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.52))
        }.padding(.horizontal, 30).padding(.top, 6)
    }

    private var playbackControls: some View {
        HStack {
            Button { model.cyclePlayMode() } label: {
                Image(systemName: model.playMode.icon).frame(width: 38)
            }.accessibilityLabel(model.playMode.title)
            Spacer()
            Button { model.prev() } label: { Image(systemName: "backward.fill") }
            Spacer()
            Button { model.toggle() } label: {
                ZStack {
                    Circle().fill(.white).frame(width: 58, height: 58)
                    if model.playbackLoading { ProgressView().tint(.black) }
                    else { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 24)) }
                }.foregroundColor(.black)
            }
            Spacer()
            Button { model.next() } label: { Image(systemName: "forward.fill") }
            Spacer()
            Button { showQueue = true } label: { Image(systemName: "list.bullet") }.frame(width: 38)
        }
        .font(.system(size: 20)).buttonStyle(.plain)
        .padding(.horizontal, 27).padding(.vertical, 5)
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            Circle().fill(.white.opacity(page == 0 ? 0.9 : 0.28)).frame(width: 5, height: 5)
            Circle().fill(.white.opacity(page == 1 ? 0.9 : 0.28)).frame(width: 5, height: 5)
        }.padding(.bottom, 10)
    }

    private var activeLyric: Int {
        model.lyrics.lastIndex(where: { $0.time <= model.progress }) ?? -1
    }
    private static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

}

private struct MusicQueueSheet: View {
    @ObservedObject var model: MusicModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(Array(model.queue.enumerated()), id: \.element.id) { index, song in
                Button {
                    let source = model.queue
                    Task {
                        await model.play(song, queue: source)
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: index == model.queueIndex ? "waveform" : "music.note")
                            .foregroundColor(index == model.queueIndex ? .accentColor : .secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(song.name).lineLimit(1)
                            Text(song.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                }.buttonStyle(.plain)
            }
            .navigationTitle("播放列表 · \(model.playMode.title)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 歌曲理解（真实音轨的声学分析，数据来自 /api/music/insight）

struct MusicInsight {
    struct Segment: Identifiable {
        let id = UUID()
        let start: Double
        let end: Double
        let label: String
    }

    let duration: Double
    let bpm: Double
    let stability: Double
    let segments: [Segment]
    let repetition: Int
    let highlights: [Double]
    let onsetBinSeconds: Double
    let onsets: [Double]
    let chroma: [Double]
    let noteLow: String
    let noteHigh: String
    let medianNote: String
    let medianHz: Double
    let coverage: Double
    let pitchConfidence: Double
    let pitchStep: Double
    let f0: [Double?]
    let confidence: Double

    init?(_ json: [String: Any]) {
        duration = json.double("duration")
        guard duration > 0 else { return nil }
        let tempo = json.object("tempo")
        bpm = tempo.double("bpm")
        stability = tempo.double("stability")
        segments = json.array("segments").map {
            Segment(start: $0.double("start"), end: $0.double("end"), label: $0.string("label"))
        }
        repetition = json.int("repetition")
        highlights = (json["highlights"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }
        let od = json.object("onset_density")
        onsetBinSeconds = max(od.double("bin_seconds"), 1)
        onsets = (od["values"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }
        chroma = (json["chroma"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }
        let pitch = json.object("pitch")
        noteLow = pitch.string("note_low")
        noteHigh = pitch.string("note_high")
        medianNote = pitch.string("median_note")
        medianHz = pitch.double("median_hz")
        coverage = pitch.double("coverage")
        pitchConfidence = pitch.double("confidence")
        pitchStep = max(pitch.double("step_seconds"), 0.1)
        f0 = (pitch["f0"] as? [Any] ?? []).map { ($0 as? NSNumber)?.doubleValue }
        confidence = json.double("confidence")
    }
}

struct SongInsightSheet: View {
    let song: MusicSong
    @State private var insight: MusicInsight?
    @State private var stage = ""
    @State private var failedError: String?
    @State private var retryToken = 0

    private static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let segmentPalette: [Color] = [
        Color(red: 0.44, green: 0.72, blue: 0.72), Color(red: 0.55, green: 0.49, blue: 0.83),
        Color(red: 0.78, green: 0.45, blue: 0.62), Color(red: 0.82, green: 0.58, blue: 0.42),
        Color(red: 0.46, green: 0.62, blue: 0.84), Color(red: 0.65, green: 0.75, blue: 0.44),
        Color(red: 0.80, green: 0.68, blue: 0.40), Color(red: 0.58, green: 0.58, blue: 0.66),
    ]
    private static let stageNames = [
        "starting": "排队起灶", "downloading": "取音频", "decoding": "解码",
        "loading": "读入音轨", "beats": "数节拍", "onsets": "数起音",
        "chroma": "算音级", "structure": "切段落", "pitch": "找主导音", "busy": "前面还有一首在嚼",
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("歌曲理解").font(.system(size: 22, weight: .bold))
                    Text("\(song.name) · \(song.artist)")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                    Text("真实音轨里的节拍、结构、起音密度和音级重心")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                if let insight {
                    readyBody(insight)
                } else if let failure = failedError {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform.slash").font(.system(size: 30)).foregroundColor(.secondary)
                        Text("这首没分析成").font(.system(size: 14, weight: .medium))
                        Text(failure).font(.system(size: 11)).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            failedError = nil
                            retryToken += 1
                        } label: {
                            Text("再试一次").font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 22).padding(.vertical, 9)
                                .background(Color.accentColor.opacity(0.18), in: Capsule())
                        }.buttonStyle(.plain)
                    }.frame(maxWidth: .infinity).padding(.vertical, 46)
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("第一次听这首，正在嚼整条音轨")
                            .font(.system(size: 13, weight: .medium))
                        Text(Self.stageNames[stage] ?? "准备中")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                        Text("一般要一分钟左右，嚼完就永远秒开")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 52)
                }
            }
            .padding(18)
        }
        .task(id: retryToken) { await poll(retry: retryToken > 0) }
    }

    private func poll(retry: Bool) async {
        var first = true
        while !Task.isCancelled {
            let path = "/api/music/insight?id=\(song.id)" + (retry && first ? "&retry=1" : "")
            first = false
            if let obj = try? await NativeHouseAPI.object(path) {
                switch obj.string("status") {
                case "ready":
                    insight = MusicInsight(obj.object("data"))
                    if insight == nil { failedError = "分析结果没读明白" }
                    return
                case "failed":
                    failedError = obj.string("error").isEmpty ? "音频没拿到或分析中断" : obj.string("error")
                    return
                case "busy":
                    stage = "busy"
                default:
                    stage = obj.string("stage")
                }
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    // MARK: 结果页

    private func readyBody(_ data: MusicInsight) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            headline(data)
            HStack(spacing: 10) {
                statCard("节拍", "\(Int(data.bpm.rounded())) BPM", "稳定度 \(Int(data.stability * 100))%")
                statCard("声学分段", "\(data.segments.count)", "同字母＝声学相似")
            }
            HStack(spacing: 10) {
                statCard("重复关系", "\(data.repetition)", "不是歌词重复次数")
                statCard("整体可信度", "\(Int(data.confidence * 100))%", "模型自报边界")
            }
            insightCard("整首声学结构", trailing: "三角是显著高点候选") {
                structureChart(data)
                Text("字母只代表这首歌内部“听起来相似”的段落，不冒充主歌、副歌或桥段。")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
            insightCard("起音密度", trailing: "每 \(Int(data.onsetBinSeconds)) 秒明显声音启动次数") {
                onsetChart(data)
            }
            insightCard("音级重心", trailing: "较突出：" + topNotes(data)) {
                chromaChart(data)
                Text("这是整首混音的十二音级相对权重，不把最高的一根直接冒充调性结论。")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
            insightCard("原曲音高", trailing: "覆盖 \(Int(data.coverage * 100))%") {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(data.medianNote.isEmpty ? "—" : data.medianNote)
                            .font(.system(size: 26, weight: .bold)).foregroundColor(.teal)
                        Text(data.medianHz > 0 ? "\(Int(data.medianHz.rounded())) Hz · 中位主导音" : "没抓到稳定主导音")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("整首常见范围 \(data.noteLow) – \(data.noteHigh)").font(.system(size: 11))
                        Text("可信度 \(Int(data.pitchConfidence * 100))%")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
                pitchChart(data)
                Text("这是完整混音的主导音估计，不是分离人声。伴奏、和声抢得厉害时，空着比硬猜更诚实。")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
    }

    private func headline(_ data: MusicInsight) -> some View {
        var parts = ["约 \(Int(data.bpm.rounded())) BPM", "\(data.segments.count) 个声学段落"]
        if let peak = data.highlights.first {
            parts.append("显著高点 \(Self.time(peak))")
        }
        return Text(parts.joined(separator: " · "))
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.teal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(Color.teal.opacity(0.09), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func statCard(_ title: String, _ value: String, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11)).foregroundColor(.secondary)
            Text(value).font(.system(size: 21, weight: .bold))
            Text(hint).font(.system(size: 9)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func insightCard(_ title: String, trailing: String,
                             @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(trailing).font(.system(size: 9)).foregroundColor(.secondary)
            }
            content()
        }
        .padding(13)
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func topNotes(_ data: MusicInsight) -> String {
        guard data.chroma.count == 12 else { return "—" }
        return data.chroma.enumerated().sorted { $0.element > $1.element }
            .prefix(3).map { Self.noteNames[$0.offset] }.joined(separator: " · ")
    }

    private static func segmentColor(_ label: String) -> Color {
        let index = Int(label.unicodeScalars.first?.value ?? 65) - 65
        return segmentPalette[((index % segmentPalette.count) + segmentPalette.count) % segmentPalette.count]
    }

    // MARK: 图表

    private func structureChart(_ data: MusicInsight) -> some View {
        VStack(spacing: 4) {
            Canvas { context, size in
                let letterBand: CGFloat = 16
                let barTop: CGFloat = letterBand + 2
                let barHeight: CGFloat = 12
                for segment in data.segments {
                    let x0 = size.width * segment.start / data.duration
                    let x1 = size.width * segment.end / data.duration
                    let rect = CGRect(x: x0, y: barTop, width: max(x1 - x0 - 1, 1), height: barHeight)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2),
                                 with: .color(Self.segmentColor(segment.label)))
                    if x1 - x0 > 13 {
                        context.draw(Text(segment.label).font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(Self.segmentColor(segment.label)),
                                     at: CGPoint(x: (x0 + x1) / 2, y: letterBand / 2))
                    }
                }
                for peak in data.highlights {
                    let x = size.width * peak / data.duration
                    var triangle = Path()
                    triangle.move(to: CGPoint(x: x, y: barTop + barHeight + 3))
                    triangle.addLine(to: CGPoint(x: x - 4, y: barTop + barHeight + 10))
                    triangle.addLine(to: CGPoint(x: x + 4, y: barTop + barHeight + 10))
                    triangle.closeSubpath()
                    context.fill(triangle, with: .color(.purple.opacity(0.8)))
                }
            }
            .frame(height: 44)
            HStack {
                Text("0:00"); Spacer(); Text(Self.time(data.duration))
            }.font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
        }
    }

    private func onsetChart(_ data: MusicInsight) -> some View {
        VStack(spacing: 4) {
            Canvas { context, size in
                let peak = max(data.onsets.max() ?? 1, 1)
                let count = data.onsets.count
                guard count > 0 else { return }
                let step = size.width / CGFloat(count)
                let barWidth = max(step - 1.5, 1)
                for (index, value) in data.onsets.enumerated() {
                    let height = size.height * value / peak
                    let rect = CGRect(x: CGFloat(index) * step, y: size.height - height,
                                      width: barWidth, height: max(height, 1))
                    context.fill(Path(roundedRect: rect, cornerRadius: 1),
                                 with: .color(.purple.opacity(0.65)))
                }
            }
            .frame(height: 74)
            HStack {
                Text("稀"); Spacer(); Text("越高越密")
            }.font(.system(size: 9)).foregroundColor(.secondary)
        }
    }

    private func chromaChart(_ data: MusicInsight) -> some View {
        let top = Set(data.chroma.enumerated().sorted { $0.element > $1.element }.prefix(3).map { $0.offset })
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<12, id: \.self) { index in
                let value = index < data.chroma.count ? data.chroma[index] : 0
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(top.contains(index) ? Color.purple.opacity(0.85) : Color.purple.opacity(0.35))
                        .frame(height: max(CGFloat(value) * 54, 3))
                    Text(Self.noteNames[index])
                        .font(.system(size: 8, design: .monospaced)).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity)
            }
        }.frame(height: 74, alignment: .bottom)
    }

    private func pitchChart(_ data: MusicInsight) -> some View {
        VStack(spacing: 4) {
            Canvas { context, size in
                let midis = data.f0.compactMap { $0 }.map { 69 + 12 * log2($0 / 440) }
                guard let low = midis.min(), let high = midis.max(), data.f0.count > 1 else { return }
                let bottom = floor(low) - 1, top = ceil(high) + 1
                let span = max(top - bottom, 6)
                func yFor(_ hz: Double) -> CGFloat {
                    let midi = 69 + 12 * log2(hz / 440)
                    return size.height * (1 - CGFloat((midi - bottom) / span))
                }
                // C3 C4 C5 参考线
                for octaveC in [48.0, 60.0, 72.0] where octaveC > bottom && octaveC < top {
                    let y = size.height * (1 - CGFloat((octaveC - bottom) / span))
                    var line = Path()
                    line.move(to: CGPoint(x: 18, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(line, with: .color(.secondary.opacity(0.22)), lineWidth: 0.5)
                    context.draw(Text("C\(Int(octaveC / 12) - 1)").font(.system(size: 8))
                                    .foregroundColor(.secondary),
                                 at: CGPoint(x: 8, y: y))
                }
                let step = size.width / CGFloat(data.f0.count)
                let dotWidth = max(step - 0.6, 0.8)
                for (index, hz) in data.f0.enumerated() {
                    guard let hz, hz > 0 else { continue }
                    let rect = CGRect(x: CGFloat(index) * step, y: yFor(hz) - 1.2,
                                      width: dotWidth, height: 2.4)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.teal.opacity(0.85)))
                }
            }
            .frame(height: 120)
            HStack {
                Text("0:00"); Spacer(); Text("空白处＝没有足够稳定的单一主导音"); Spacer(); Text(Self.time(data.duration))
            }.font(.system(size: 8, design: .monospaced)).foregroundColor(.secondary)
        }
    }

    private static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

// 0924 自醒时间线：引擎每次给他一次「运行机会」，他醒了选了什么（静 / 找你 / 去玩 / 独白）都列在这。
// 数据来自 GET /api/wake：status 是引擎每分钟写的快照，timeline 是 wake_engine/timeline.jsonl 倒序。
private struct WakeTimelineView: View {
    @State private var loading = true
    @State private var status: [String: Any] = [:]
    @State private var rows: [[String: Any]] = []
    @AppStorage("alcoveTheme") private var themeName = "haven"
    private var theme: AlcoveTheme { .panelNamed(themeName) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("自醒")
                    .font(.custom("Snell Roundhand", size: 31))
                Text("没人叫他，他自己醒了，然后自己决定做什么")
                    .font(.system(size: 11)).foregroundColor(theme.textDim)
            }
            if loading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 45)
            } else {
                statusCard
                if rows.isEmpty {
                    Text("还没醒过一次")
                        .font(.system(size: 12)).foregroundColor(theme.textDim)
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                timelineRow(row)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .foregroundColor(theme.text)
        .task { await load() }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let paused = status["paused_by"] as? String {
                let why = ["asleep": "他睡着了", "quiet": "留白中", "app-off": "开关关着", "off": "引擎停着"][paused] ?? paused
                Label("此刻暂停：\(why)", systemImage: "pause.circle")
                    .font(.system(size: 13, weight: .semibold))
            } else if let p30 = status["p_wake_30min"] as? Double, let p60 = status["p_wake_60min"] as? Double {
                Label("此刻多容易醒", systemImage: "waveform.path.ecg")
                    .font(.system(size: 13, weight: .semibold))
                Text("半小时内约 \(Int((p30 * 100).rounded()))%，一小时内约 \(Int((p60 * 100).rounded()))%。不是闹钟，只是此刻的倾向。")
                    .font(.system(size: 10.5)).foregroundColor(theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("引擎没在跑", systemImage: "exclamationmark.circle")
                    .font(.system(size: 13, weight: .semibold))
            }
            HStack(spacing: 14) {
                stat("醒过", status["dispatched"])
                stat("作废", status["forfeited"])
                if let mode = status["mode"] as? String, mode == "shadow" {
                    Text("影子模式：只记不醒").font(.system(size: 9.5)).foregroundColor(theme.textDim)
                }
            }
        }
        .padding(14).foyerCard(theme)
    }

    private func stat(_ label: String, _ v: Any?) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 9.5)).foregroundColor(theme.textDim)
            Text("\((v as? Int) ?? 0)").font(.system(size: 12, weight: .semibold, design: .rounded))
        }
    }

    private func timelineRow(_ row: [String: Any]) -> some View {
        let action = (row["action"] as? String) ?? ""
        let choice = row["choice"] as? String
        let (icon, title, sub): (String, String, String) = {
            switch action {
            case "dispatched":
                switch choice {
                case "静": return ("moon.zzz", "醒了，选了静", "什么都没说，又躺回去了")
                case "找你": return ("bubble.left.fill", "醒了，来找你", "自己想说话了")
                case "去玩": return ("figure.walk", "醒了，去玩了", "干自己的事去了")
                case "独白": return ("text.quote", "醒了，只写了独白", "没跟你说，写给自己")
                default: return ("sunrise", "醒了", "还在看他选了什么")
                }
            case "shadow": return ("eye.slash", "影子：本来会在这时醒", "没真叫他")
            case "forfeit-busy": return ("hourglass", "醒的机会作废", "他手里正忙着，等不到空")
            case "forfeit-paused": return ("pause", "醒的机会作废", "睡着或留白中")
            case "inject-failed": return ("xmark.octagon", "叫他没叫醒", "注入失败")
            default: return ("circle", action, "")
            }
        }()
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).frame(width: 18).foregroundColor(theme.fyAccent)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 12.5, weight: .medium))
                    if (row["leak"] as? Bool) == true {
                        Text("〈静〉漏进聊天页了").font(.system(size: 9)).foregroundColor(.red.opacity(0.8))
                    }
                }
                Text(sub).font(.system(size: 10)).foregroundColor(theme.textDim)
            }
            Spacer()
            Text(Self.hhmm(row["at"] as? String))
                .font(.system(size: 10.5, design: .rounded)).foregroundColor(theme.textDim)
        }
        .padding(.vertical, 8)
        .overlay(Divider().opacity(0.2), alignment: .bottom)
    }

    private static func hhmm(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "" }
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }

    @MainActor private func load() async {
        defer { loading = false }
        guard let value = try? await NativeHouseAPI.object("/api/wake") else { return }
        status = (value["status"] as? [String: Any]) ?? [:]
        rows = (value["timeline"] as? [[String: Any]]) ?? []
    }
}

private struct QuietRoomView: View {
    @State private var quiet = false
    @State private var until = ""
    @State private var loading = true
    @State private var sending = false
    @State private var error = ""
    @State private var chosenHours = 2
    @State private var choosingDuration = false
    @AppStorage("alcoveTheme") private var themeName = "haven"
    private var theme: AlcoveTheme { .panelNamed(themeName) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("留白")
                    .font(.custom("Snell Roundhand", size: 31))
                Text("有些时候，安静也是一种靠近")
                    .font(.system(size: 11)).foregroundColor(theme.textDim)
            }

            if loading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 45)
            } else if quiet {
                VStack(alignment: .leading, spacing: 10) {
                    Label("此刻正在留白", systemImage: "moon.zzz.fill")
                        .font(.system(size: 16, weight: .semibold))
                    if !until.isEmpty {
                        Text("会安静到 \(displayUntil)")
                            .font(.system(size: 11)).foregroundColor(theme.textDim)
                    }
                    Button { setQuiet(on: false) } label: {
                        Label("让声音回来", systemImage: "sunrise")
                            .frame(maxWidth: .infinity).frame(height: 45)
                            .background(theme.fyAccent.opacity(0.88), in: RoundedRectangle(cornerRadius: 14))
                            .foregroundColor(.white)
                    }.buttonStyle(.plain).disabled(sending)
                }
                .padding(15).foyerCard(theme)
            } else {
                HStack(spacing: 12) {
                    // 0918 作息改 7 点起；文案不写死钟点，后端按起床时间自动解
                    quietChoice("今夜无声", "今晚先不追问\n明早起床再来", "moon.stars.fill") {
                        setQuiet(on: true)
                    }
                    quietChoice("借我片刻", "安静两个小时\n再轻轻回来", "hourglass") {
                        choosingDuration = true
                    }
                }
            }
            if !error.isEmpty {
                Text(error).font(.system(size: 10)).foregroundColor(.red.opacity(0.85))
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .foregroundColor(theme.text)
        .sheet(isPresented: $choosingDuration) {
            NavigationStack {
                VStack(spacing: 22) {
                    Text("想安静多久").font(.system(size: 22, weight: .semibold, design: .serif))
                    Picker("静默时长", selection: $chosenHours) {
                        ForEach(1...24, id: \.self) { Text("\($0) 小时").tag($0) }
                    }.pickerStyle(.wheel).frame(height: 180)
                    Button { choosingDuration = false; setQuiet(on: true, hours: chosenHours) } label: {
                        Text("安静 \(chosenHours) 小时").font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: 46)
                    }.buttonStyle(.borderedProminent).tint(theme.fyAccent)
                }.padding(22).foregroundColor(theme.text)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { choosingDuration = false } } }
            }.presentationDetents([.height(360)])
        }
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func quietChoice(
        _ title: String, _ subtitle: String, _ icon: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.system(size: 19)).foregroundColor(theme.fyAccent)
                Text(title).font(.system(size: 15, weight: .semibold, design: .serif))
                Text(subtitle).font(.system(size: 10)).foregroundColor(theme.textDim)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).foyerCard(theme)
        }.buttonStyle(.plain).disabled(sending)
    }

    @MainActor private func refresh() async {
        guard let value = try? await NativeHouseAPI.object("/api/quiet") else {
            loading = false; error = "暂时读不到后端状态"; return
        }
        quiet = value.bool("quiet")
        until = value.string("until")
        loading = false
        error = ""
    }

    private func setQuiet(on: Bool, hours: Int? = nil) {
        guard !sending else { return }
        sending = true; error = ""
        Task { @MainActor in
            var body: [String: Any] = ["on": on]
            if let hours { body["hours"] = hours }
            do {
                _ = try await NativeHouseAPI.object("/api/quiet", method: "POST", body: body)
                await refresh()
            } catch { self.error = "没有送到后端，再试一次" }
            sending = false
        }
    }

    private var displayUntil: String {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let regular = ISO8601DateFormatter()
        guard let date = fractional.date(from: until) ?? regular.date(from: until) else { return "结束时间读取中" }
        let out = DateFormatter()
        out.locale = Locale(identifier: "zh_CN")
        out.timeZone = TimeZone(identifier: "Asia/Shanghai")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = out.timeZone
        if calendar.isDateInToday(date) {
            out.dateFormat = "HH:mm"
            return "今天 \(out.string(from: date))"
        }
        if calendar.isDateInTomorrow(date) {
            out.dateFormat = "HH:mm"
            return "明天 \(out.string(from: date))"
        }
        out.dateFormat = "M月d日 HH:mm"
        return out.string(from: date)
    }
}

private struct NativeRecord: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let body: String
    let image: String
}

@MainActor
private final class DataPanelModel: ObservableObject {
    @Published var records: [NativeRecord] = []
    @Published var loading = true
    @Published var error = ""

    func load(_ destination: HouseDestination) async {
        loading = true
        defer { loading = false }
        do {
            let path: String
            let key: String?
            switch destination {
            case .dreams: path = "/api/night/dreams?limit=20"; key = "records"
            case .shelf: path = "/api/shelf/list?limit=100"; key = "items"
            case .nianlun: path = "/api/nianlun/list"; key = "desires"
            case .album: path = "/api/album/entries"; key = "entries"
            case .calendar: path = "/api/calendar/month?year=\(Calendar.current.component(.year, from: Date()))&month=\(Calendar.current.component(.month, from: Date()))"; key = nil
            case .usage: path = "/api/usage"; key = nil
            // 0928：OB（记忆库）已退役，这里原来一律回落到 /api/ob/buckets。剩下这些 route 根本不走面板，给空
            default: records = []; error = ""; return
            }
            let value = try await NativeHouseAPI.request(path)
            var rows: [[String: Any]]
            if let array = value as? [[String: Any]] {
                rows = array
            } else if let object = value as? [String: Any], let key {
                rows = object[key] as? [[String: Any]] ?? []
            } else if let object = value as? [String: Any] {
                rows = flatten(object)
            } else { rows = [] }
            records = rows.map(record)
            error = ""
        } catch { self.error = "这一页暂时够不着" }
    }

    private func flatten(_ object: [String: Any]) -> [[String: Any]] {
        var out: [[String: Any]] = []
        for (key, value) in object.sorted(by: { $0.key < $1.key }) {
            if let dict = value as? [String: Any] {
                out.append(["name": key, "content": prettyJSON(dict)])
            } else if let list = value as? [Any] {
                out.append(["name": key, "content": list.map { prettyValue($0) }.joined(separator: "\n")])
            } else {
                out.append(["name": key, "content": prettyValue(value)])
            }
        }
        return out
    }

    private func prettyJSON(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "\(object)"
        }
        return str
    }

    private func prettyValue(_ value: Any) -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if let dict = value as? [String: Any] { return prettyJSON(dict) }
        if let arr = value as? [Any] { return prettyJSON(arr) }
        return "\(value)"
    }

    private func record(_ row: [String: Any]) -> NativeRecord {
        let title = row.string("name", "title", "text", "local_date", "date", "mode")
        let subtitle = row.string("status", "track", "ai_name", "source_date", "ts", "created")
        let body = row.string("content_preview", "content", "comment", "caption", "why_mine", "state")
        let image = row.string("img", "image_url", "cover")
        let fallback: String
        if body.isEmpty {
            let skipKeys: Set<String> = ["name", "title", "text", "local_date", "date", "mode",
                                         "status", "track", "ai_name", "source_date", "ts", "created",
                                         "img", "image_url", "cover"]
            fallback = row.filter { !skipKeys.contains($0.key) }
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key): \(prettyValue($0.value))" }
                .joined(separator: "\n")
        } else { fallback = body }
        return NativeRecord(
            title: title.isEmpty ? "记录" : title,
            subtitle: subtitle,
            body: fallback,
            image: image)
    }
}

private struct NativeDataPanel: View {
    let destination: HouseDestination
    @StateObject private var model = DataPanelModel()
    @AppStorage("houseInterfaceAppearance") private var appearance = "dark"
    private var dark: Bool { appearance != "light" }
    private var theme: AlcoveTheme { dark ? .messagesDark : .messages }

    var body: some View {
        VStack(spacing: 0) {
            FoyerPanelTitle(title: destination.title, theme: theme)
            if model.loading {
                Spacer(); ProgressView().tint(theme.fyAccent); Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(model.records) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                    if !item.image.isEmpty {
                                        CachedImage(url: AlcoveAPI.attachmentURL(item.image)) { image in
                                            image.resizable().scaledToFit()
                                        } placeholder: { ProgressView() }
                                        .frame(maxHeight: 240)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                    HStack {
                                        Text(item.title)
                                            .font(.system(size: 14, weight: .medium))
                                        Spacer()
                                        Text(item.subtitle)
                                            .font(.system(size: 9))
                                            .foregroundColor(theme.fyAccent.opacity(0.9))
                                    }
                                    Text(item.body)
                                        .font(.system(size: 12))
                                        .foregroundColor(theme.textDim)
                                        .lineSpacing(3)
                                        .textSelection(.enabled)
                            }
                            .padding(14)
                            .background(theme.fyCard,
                                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        if model.records.isEmpty {
                            Text(model.error.isEmpty ? "这里还没有记录" : model.error)
                                .font(.system(size: 12))
                                .foregroundColor(theme.textDim)
                                .padding(40)
                        }
                    }
                    .padding(.top, 12)
                }
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 18)
        .foregroundColor(theme.text)
        .background((dark ? Color(red: 0.07, green: 0.075, blue: 0.085)
                          : Color(red: 0.95, green: 0.95, blue: 0.97)).ignoresSafeArea())
        .padding(.horizontal, 12).padding(.top, 8)
        .preferredColorScheme(dark ? .dark : .light)
        .task { await model.load(destination) }
    }
}

private struct ClockworkItem: Identifiable {
    let id: String
    let emoji: String
    let name: String
    let desc: String
}

private struct ClockworkView: View {
    @State private var flags: [String: Bool] = [:]
    @AppStorage("alcoveTheme") private var themeName = "haven"
    private var theme: AlcoveTheme { .panelNamed(themeName) }
    private let items = [
        ClockworkItem(id: "libido", emoji: "🌅", name: "晨勃",
                      desc: "libido 每半小时涨一点，凌晨 3～6 点涨得最快；到 75 时即使睡着也会一次性醒来，回完这一轮立刻睡回去并扣 30。你在他回复期间亲自接话，才会变成普通清醒窗口。关着时照样攒，重新拧开后再触发。"),
        ClockworkItem(id: "sleep", emoji: "🌙", name: "睡眠",
                      desc: "凌晨三点以后你 15 分钟不说话我就睡着；上午十点醒，醒了先出晨报。睡着时心跳两张表都停，你发的话会攒着等我醒来一起回；喊「蓝屏」我立刻醒。"),
        ClockworkItem(id: "dream", emoji: "🌛", name: "做梦",
                      desc: "只有我睡着了才会做（要先开睡眠）。入睡后每隔 70～110 分钟掷一次骰子，一半概率做一个梦，一晚最多两个。梦的材料是新脑子随机翻出的旧记忆、你今天说过的话、檐下的念头，我自己写。梦只存进「Dreams」面板，聊天页只留一道「他做了一场梦」的线。"),
        ClockworkItem(id: "startle", emoji: "⚡", name: "惊醒",
                      desc: "不是你吵醒我——是我自己半夜猛地醒一下。可能来自太重的梦、雨声或硌人的记忆。醒了迷迷糊糊说一两句，收轮后立刻睡回去；只有你亲自接话才继续醒着。一晚最多两次，两次隔半小时以上。"),
        ClockworkItem(id: "keepalive", emoji: "💓", name: "保活心跳",
                      desc: "每 55 分钟静默翻个身，让这条窗不凉，不进聊天页，睡着也翻。")
    ]
    private let hoduItems = [
        ClockworkItem(id: "hodu_autonomy", emoji: "🧠", name: "自主活动", desc: "随机醒来，自己找点想做的事")
    ]

    var body: some View {
        VStack(spacing: 0) {
            FoyerPanelTitle(title: "发条", theme: theme)
            VStack(alignment: .leading, spacing: 0) {
                Text("陈璟的发条开关。每一条都是一根线，线的那头拴着他回来找你的理由。")
                    .font(.system(size: 12.5))
                    .foregroundColor(theme.textDim)
                    .lineSpacing(3)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(colors: [theme.fyAccentSoft.opacity(0.15), .clear],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .overlay(alignment: .leading) {
                        Rectangle().fill(theme.fyAccentSoft).frame(width: 2.5)
                    }
                    .clipShape(JournalCardShape(tl: 6, bl: 6, br: 12, tr: 12))
            }
            .padding(.horizontal, 16).padding(.top, 12)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(items) { item in
                        let isOn = flags[item.id] ?? true
                        HStack(spacing: 14) {
                            Text(item.emoji).font(.system(size: 20))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name)
                                    .font(.system(size: 14, weight: .medium))
                                Text(item.desc)
                                    .font(.system(size: 11.5))
                                    .foregroundColor(theme.textDim)
                                    .lineSpacing(2)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { isOn },
                                set: { value in
                                    flags[item.id] = value
                                    Task { try? await NativeHouseAPI.post(
                                        "/api/flags/set", body: ["key": item.id, "on": value]) }
                                }))
                            .labelsHidden()
                            .tint(theme.fyAccent)
                        }
                        .padding(15)
                        .opacity(isOn ? 1 : 0.55)
                        .foyerCard(theme)
                    }
                    HStack {
                        Text("何渡的发条")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(theme.textDim)
                        Rectangle().fill(theme.textDim.opacity(0.2)).frame(height: 0.5)
                    }
                    .padding(.top, 8)
                    ForEach(hoduItems) { item in
                        let isOn = flags[item.id] ?? true
                        HStack(spacing: 14) {
                            Text(item.emoji).font(.system(size: 20))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name).font(.system(size: 14, weight: .medium))
                                Text(item.desc)
                                    .font(.system(size: 11.5))
                                    .foregroundColor(theme.textDim)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { isOn },
                                set: { value in
                                    flags[item.id] = value
                                    Task { try? await NativeHouseAPI.post(
                                        "/api/flags/set", body: ["key": item.id, "on": value]) }
                                }))
                            .labelsHidden()
                            .tint(theme.fyAccent)
                        }
                        .padding(15)
                        .opacity(isOn ? 1 : 0.55)
                        .foyerCard(theme)
                    }
                }
                .padding(.top, 14)
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
        .foregroundColor(theme.text)
        .foyerPanel(theme)
        .padding(.horizontal, 12).padding(.top, 8)
        .task {
            if let obj = try? await NativeHouseAPI.object("/api/flags/status"),
               let raw = obj["flags"] as? [String: Any] {
                flags = raw.mapValues { ($0 as? Bool) ?? true }
            }
        }
    }
}

private struct WebHouseView: View {
    let destination: HouseDestination
    @AppStorage("alcoveTheme") private var themeName = "haven"
    private var theme: AlcoveTheme { .panelNamed(themeName) }

    private var panelName: String {
        switch destination {
        case .music: return "music"
        case .clockwork: return "fatiao"
        default: return destination.rawValue
        }
    }

    private var panelURL: URL {
        AlcoveAPI.fullURL("/?panel=\(panelName)")
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(destination.title)
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .padding(.top, 12)
            FixedWebView(url: panelURL)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.glassBorder, lineWidth: 1))
        }
        .padding(.horizontal, 12).padding(.bottom, 12)
    }
}

// MARK: - 共读室

private struct CoreadBook: Identifiable, Hashable {
    let id: String
    let title: String
    let chapters: Int
    let currentChapter: Int
    let chapterTitles: [String]
    let coverURL: String?
    // 2026-08-26 加的：她正在读的章节名、陈璟自己那条进度、她私有的书签数、一起读了多久
    let chapterTitle: String
    let hasMyMark: Bool
    let myChapter: Int
    let myPct: Double
    let myNotes: Int
    let bookmarkCount: Int
    let readMs: Int

    init(_ value: [String: Any]) {
        id = value.string("id")
        title = value.string("title")
        chapters = value.int("total_chapters")
        currentChapter = value.int("current_chapter")
        chapterTitles = value["chapter_titles"] as? [String] ?? []
        coverURL = value.string("cover_url", "cover").isEmpty ? nil : value.string("cover_url", "cover")
        chapterTitle = value.string("chapter_title")
        bookmarkCount = value.int("bookmark_count")
        readMs = value.int("read_ms")
        if let mark = value["my_mark"] as? [String: Any] {
            hasMyMark = true
            myChapter = mark.int("chapter")
            myPct = (mark["pct"] as? Double) ?? Double(mark.int("pct"))
            myNotes = mark.int("notes")
        } else {
            hasMyMark = false
            myChapter = 0
            myPct = 0
            myNotes = 0
        }
    }

    /// 陈璟那条进度（0~1）。他自己一段一段读出来的，跟她的各走各的。
    var myProgress: CGFloat {
        guard hasMyMark else { return 0 }
        return min(1, max(0, CGFloat(myPct) / 100))
    }

    /// 一起读了多久，写成人话
    var readTimeText: String {
        let minutes = readMs / 60000
        if minutes <= 0 { return "" }
        if minutes < 60 { return "读了 \(minutes) 分钟" }
        return "读了 \(minutes / 60) 小时 \(minutes % 60) 分"
    }
}

private struct NativeCoreadRoomView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("houseInterfaceAppearance") private var houseAppearance = "dark"
    @State private var books: [CoreadBook] = []
    @State private var selected: CoreadBook?
    @State private var reading: (CoreadBook, Int)?
    @State private var page = 0
    @State private var loading = true
    @State private var error = ""
    @State private var showWorkbench = false
    @AppStorage("coreadActiveBookID") private var activeBookID = ""
    @AppStorage("coreadActiveChapter") private var activeChapter = 0
    @State private var showImporter = false
    @State private var uploading = false
    private var isNight: Bool { houseAppearance != "light" }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CoreadYanxiaBackground(isNight: isNight).ignoresSafeArea()

                if let (book, chapter) = reading {
                    CoreadReaderView(book: book, chapter: chapter) { reading = nil }
                } else if let book = selected {
                    CoreadDetailView(book: book, onBack: { selected = nil }) { chapter in
                        reading = (book, chapter)
                    }
                } else {
                    shelf(geo)
                }

                if selected == nil && reading == nil {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(isNight ? Color(red: 0.70, green: 0.75, blue: 0.80) : Color(red: 0.290, green: 0.322, blue: 0.361))
                            .frame(width: 44, height: 44)
                            .background(isNight ? Color.white.opacity(0.08) : Color.white.opacity(0.64), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("返回")
                    .position(x: 34, y: max(geo.safeAreaInsets.top + 22, 43))
                }
            }
        }
        .task { await loadBooks() }
        .preferredColorScheme(isNight ? .dark : .light)
        .sheet(isPresented: $showWorkbench) { CoreadWorkbenchView(isNight: isNight) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText, .text, .item]) { result in
            guard case .success(let url) = result else { return }
            Task { await upload(url) }
        }
    }

    @ViewBuilder private func shelf(_ geo: GeometryProxy) -> some View {
        let pal = YanxiaPal(night: isNight)
        let pages = max(1, Int(ceil(Double(books.count) / 9.0)))
        VStack(spacing: 0) {
            // 顶栏只留统计入口（返回箭头挂在外层 ZStack 上，位置没动）
            HStack(spacing: 8) {
                Spacer()
                Button { showImporter = true } label: {
                    Image(systemName: uploading ? "arrow.up.circle" : "plus")
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(pal.ink2)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(pal.card))
                        .overlay(Circle().strokeBorder(pal.line, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(uploading)
                .accessibilityLabel("传一本书")
                Button { showWorkbench = true } label: {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 13.5, weight: .light))
                        .foregroundColor(pal.ink2)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(pal.card))
                        .overlay(Circle().strokeBorder(pal.line, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("DeepSeek 工作台")
            }
            .padding(.top, max(geo.safeAreaInsets.top + 8, 24))
            .padding(.horizontal, 18)

            YanxiaDateLine(pal: pal).padding(.top, 4)
            YanxiaEmboss(text: "共读室", size: 38, pal: pal).padding(.top, 7)
            Text("慢慢翻，慢慢读")
                .font(.system(size: 10.5, design: .serif))
                .tracking(2)
                .foregroundColor(pal.ink3)
                .padding(.top, 4)

            Spacer().frame(height: 22)

            if loading {
                ProgressView().tint(pal.accent)
            } else if !error.isEmpty {
                Text(error).font(.system(size: 12, design: .serif)).foregroundColor(pal.ink3)
            } else {
                TabView(selection: $page) {
                    ForEach(0..<pages, id: \.self) { pageIndex in
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 13), count: 3),
                                  spacing: 16) {
                            ForEach(Array(books.dropFirst(pageIndex * 9).prefix(9))) { book in
                                Button { selected = book } label: { CoreadBookSlot(book: book, isNight: isNight) }
                                    .buttonStyle(CoreadPressStyle())
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 2)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .tag(pageIndex)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)

                if pages > 1 {
                    Text("\(page + 1) / \(pages)")
                        .font(.system(size: 9.5, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(pal.ink3)
                        .padding(.top, 4)
                }
            }

            Spacer(minLength: 8)
            HStack(spacing: 12) {
                coreadAction("正在共读", "person.2") {
                    if let book = books.first(where: { $0.id == activeBookID }) {
                        reading = (book, min(activeChapter, max(0, book.chapters - 1)))
                    } else if let book = books.first {
                        reading = (book, min(book.currentChapter, max(0, book.chapters - 1)))
                    }
                }
                coreadAction("随机抽一本", "die.face.5") {
                    if let book = books.randomElement() { selected = book }
                }
            }
            .padding(.bottom, max(geo.safeAreaInsets.bottom + 14, 30))
        }
    }

    private func coreadAction(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        let pal = YanxiaPal(night: isNight)
        return Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 13, weight: .light))
                Text(title).font(.system(size: 12, design: .serif)).tracking(1)
            }
            .foregroundColor(pal.ink2)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(Capsule().fill(pal.card))
            .overlay(Capsule().strokeBorder(pal.line, lineWidth: 0.5))
            .shadow(color: Color.black.opacity(isNight ? 0.22 : 0.08), radius: 9, y: 3)
        }
        .buttonStyle(CoreadPressStyle())
    }

    /// 传一本书。文件二进制直接丢给后端，书名走 ?filename=，不用 multipart。
    /// 传完不再自动喂 DeepSeek —— 预读就是剧透，陈璟要跟着她一页一页读。
    @MainActor private func upload(_ fileURL: URL) async {
        uploading = true
        defer { uploading = false }
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            error = "这本书读不出来"
            return
        }
        let name = fileURL.lastPathComponent
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "book.txt"
        var request = URLRequest(url: AlcoveAPI.fullURL("/read/api/upload?filename=\(name)"))
        request.httpMethod = "POST"
        request.httpBody = data
        request.timeoutInterval = 90
        _ = try? await AlcoveAPI.session.data(for: request)
        await loadBooks()
    }

    @MainActor private func loadBooks() async {
        loading = true; defer { loading = false }
        do {
            books = try await NativeHouseAPI.array("/read/api/books").map(CoreadBook.init)
            error = ""
        } catch { self.error = "书架暂时没有递过来" }
    }
}

private struct CoreadPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - 檐下（2026-08-19 她给的皮：雾面 · 冷灰蓝 · 噪点 · 浮雕）
// 她原话「就是檐下的风格」。参考八张图，同一个作者：六张阅读器 + 两张桌面端。
// 三件套缺一不可 —— 整页大渐变（顶亮底暗）· 水痕亮斑 · 噪点。
// 少了噪点就是普通毛玻璃，整张脸会平掉，这条是看图看出来的第一条。

// 檐下这套皮不止共读在用了（0826 她要冲浪收藏和设置页也统一过来），所以开放到文件外。
struct YanxiaPal {
    let night: Bool
    var ink: Color    { night ? Color(red: 0.90, green: 0.93, blue: 0.95) : Color(red: 0.165, green: 0.185, blue: 0.212) }
    var ink2: Color   { night ? Color(red: 0.70, green: 0.75, blue: 0.80) : Color(red: 0.290, green: 0.322, blue: 0.361) }
    var ink3: Color   { night ? Color(red: 0.50, green: 0.55, blue: 0.61) : Color(red: 0.475, green: 0.510, blue: 0.553) }
    var accent: Color { night ? Color(red: 0.50, green: 0.65, blue: 0.83) : Color(red: 0.353, green: 0.498, blue: 0.659) }
    var card: Color   { night ? Color.white.opacity(0.070) : Color.white.opacity(0.42) }
    var card2: Color  { night ? Color.white.opacity(0.045) : Color.white.opacity(0.26) }
    var line: Color   { night ? Color.white.opacity(0.100) : Color.white.opacity(0.50) }

    /// 整页渐变四段：顶亮 → 底暗。夜里底下那两段偏湿蓝，不是电子蓝。
    var ramp: [Color] {
        night
        ? [Color(red: 0.137, green: 0.153, blue: 0.173), Color(red: 0.169, green: 0.192, blue: 0.220),
           Color(red: 0.118, green: 0.200, blue: 0.333), Color(red: 0.086, green: 0.161, blue: 0.290)]
        : [Color(red: 0.984, green: 0.988, blue: 0.992), Color(red: 0.910, green: 0.925, blue: 0.937),
           Color(red: 0.725, green: 0.761, blue: 0.788), Color(red: 0.553, green: 0.592, blue: 0.624)]
    }
    /// 浮雕三件：字面跟雾同色，靠一亮一暗两道阴影从雾里凸出来
    var embossFace: Color { night ? Color(red: 0.204, green: 0.243, blue: 0.298).opacity(0.55)
                                  : Color(red: 0.886, green: 0.910, blue: 0.933).opacity(0.92) }
    var embossHi: Color   { night ? Color(red: 0.588, green: 0.686, blue: 0.804).opacity(0.30) : Color.white.opacity(0.95) }
    var embossLo: Color   { night ? Color.black.opacity(0.55) : Color(red: 0.376, green: 0.439, blue: 0.502).opacity(0.42) }
}

/// 噪点。一次生成一张 128×128 的图平铺 ——
/// ‼️不能用 Canvas 每帧现算：随机数每次重绘都变，整页会闪。
enum YanxiaGrain {
    static let tile: UIImage = {
        let side = 128
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { ctx in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            for y in 0..<side {
                for x in 0..<side {
                    seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                    let v = Double(seed % 1000) / 1000.0
                    guard v > 0.55 else { continue }
                    let white = (seed >> 20) % 2 == 0
                    UIColor(white: white ? 1 : 0, alpha: (v - 0.55) * 0.38).setFill()
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }()
}

struct CoreadYanxiaBackground: View {
    let isNight: Bool
    private var pal: YanxiaPal { YanxiaPal(night: isNight) }
    /// x, y, 半径系数, 强度
    private static let drops: [(CGFloat, CGFloat, CGFloat, Double)] = [
        (0.18, 0.12, 0.42, 0.55), (0.86, 0.26, 0.34, 0.38),
        (0.62, 0.68, 0.48, 0.30), (0.12, 0.82, 0.30, 0.26)
    ]
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(stops: [
                    .init(color: pal.ramp[0], location: 0.00),
                    .init(color: pal.ramp[1], location: 0.34),
                    .init(color: pal.ramp[2], location: 0.76),
                    .init(color: pal.ramp[3], location: 1.00)
                ], startPoint: .top, endPoint: .bottom)

                // 水痕：几团散开的亮斑。有它雾才是「结了水汽的玻璃」，没它就是一团糊。
                ForEach(Array(Self.drops.enumerated()), id: \.offset) { _, d in
                    let r = geo.size.width * d.2
                    RadialGradient(
                        colors: [(isNight ? Color(red: 0.59, green: 0.76, blue: 1.0) : Color.white)
                                    .opacity(isNight ? d.3 * 0.5 : d.3), .clear],
                        center: .center, startRadius: 0, endRadius: r)
                        .frame(width: r * 2, height: r * 2)
                        .position(x: geo.size.width * d.0, y: geo.size.height * d.1)
                        .blendMode(.plusLighter)
                }

                Image(uiImage: YanxiaGrain.tile)
                    .resizable(resizingMode: .tile)
                    .blendMode(.overlay)
                    .opacity(isNight ? 0.34 : 0.55)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// 浮雕标题 —— 她第二组参考里那个大时钟的手法：字不是白的，是从雾里凸出来的
private struct YanxiaEmboss: View {
    let text: String
    var size: CGFloat = 40
    let pal: YanxiaPal
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .serif))
            .tracking(size * 0.10)
            .foregroundColor(pal.embossFace)
            .shadow(color: pal.embossHi, radius: 1, x: -1.5, y: -1.5)
            .shadow(color: pal.embossLo, radius: 4, x: 2, y: 2.5)
    }
}

/// 日期条 —— 等宽、全大写、字距拉开。一行小字就把气质定住了。
private struct YanxiaDateLine: View {
    let pal: YanxiaPal
    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM d, yyyy  |  EEEE"
        return f
    }()
    var body: some View {
        Text(Self.fmt.string(from: Date()).uppercased())
            .font(.system(size: 9.5, design: .monospaced))
            .tracking(2.6)
            .foregroundColor(pal.ink3)
    }
}

private struct CoreadWorkbenchView: View {
    let isNight: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var dashboard: [String: Any] = [:]
    @State private var loading = true

    private var apiLog: [String: Any] { dashboard["api_log"] as? [String: Any] ?? [:] }
    private var totals: [String: Any] { apiLog["totals"] as? [String: Any] ?? [:] }
    private var recent: [[String: Any]] { apiLog["recent"] as? [[String: Any]] ?? [] }
    private var books: [[String: Any]] { dashboard["books"] as? [[String: Any]] ?? [] }
    private var foreground: Color { isNight ? Color(red: 0.90, green: 0.93, blue: 0.95) : Color(red: 0.165, green: 0.185, blue: 0.212) }

    var body: some View {
        NavigationStack {
            ZStack {
                CoreadYanxiaBackground(isNight: isNight).ignoresSafeArea()
                if loading { ProgressView().tint(Color(red: 0.353, green: 0.498, blue: 0.659)) }
                else {
                    ScrollView {
                        VStack(spacing: 16) {
                            HStack(spacing: 10) {
                                stat("DS 调用", "\(apiLog.int("total_calls"))")
                                stat("总花费", String(format: "¥%.4f", number(totals, "cost_yuan")))
                                stat("书籍", "\(books.count)")
                            }
                            HStack(spacing: 10) {
                                stat("输入 Token", token(totals.int("input_tokens")))
                                stat("输出 Token", token(totals.int("output_tokens")))
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                Text("最近的章节预读").font(.system(size: 15, weight: .semibold, design: .serif))
                                ForEach(Array(recent.reversed().enumerated()), id: \.offset) { _, row in
                                    HStack(spacing: 10) {
                                        Text(row.string("chapter")).lineLimit(2)
                                        Spacer()
                                        Text("\(row.int("input_tokens"))+\(row.int("output_tokens"))")
                                            .foregroundColor(foreground.opacity(0.58))
                                        Text(String(format: "¥%.4f", number(row, "cost_yuan")))
                                            .fontWeight(.semibold)
                                    }
                                    .font(.system(size: 11, design: .serif)).padding(11)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardColor))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(lineColor, lineWidth: 0.5))
                                }
                            }
                        }.padding(18)
                    }
                }
            }
            .foregroundColor(foreground)
            .navigationTitle("DeepSeek 工作台").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
        .preferredColorScheme(isNight ? .dark : .light)
        .task {
            dashboard = (try? await NativeHouseAPI.object("/read/api/dashboard")) ?? [:]
            loading = false
        }
    }

    private var cardColor: Color { isNight ? Color.white.opacity(0.045) : Color.white.opacity(0.26) }
    private var lineColor: Color { isNight ? Color.white.opacity(0.10) : Color.white.opacity(0.50) }
    /// 参考图里的数字卡：小标签在上、衬线大数字在下、一道细描边，卡片自己不发光
    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9.5))
                .tracking(0.5)
                .foregroundColor(foreground.opacity(0.55))
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .tracking(0.5)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .frame(height: 62)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(cardColor))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(lineColor, lineWidth: 0.5))
    }
    private func token(_ value: Int) -> String { value >= 10_000 ? String(format: "%.1fk", Double(value) / 1000) : "\(value)" }
    private func number(_ row: [String: Any], _ key: String) -> Double {
        if let value = row[key] as? NSNumber { return value.doubleValue }
        if let value = row[key] as? String { return Double(value) ?? 0 }
        return 0
    }
}

private struct CoreadBookSlot: View {
    let book: CoreadBook
    var isNight = false
    private var pal: YanxiaPal { YanxiaPal(night: isNight) }
    /// 没封面图时的底色：冷灰蓝三档，按 id 稳定分配（同一本书每次进来颜色一样）
    private var ramp: [Color] {
        let sets: [[Color]] = isNight
        ? [[Color(red: 0.240, green: 0.373, blue: 0.549), Color(red: 0.106, green: 0.184, blue: 0.302)],
           [Color(red: 0.290, green: 0.384, blue: 0.502), Color(red: 0.133, green: 0.204, blue: 0.298)],
           [Color(red: 0.220, green: 0.333, blue: 0.471), Color(red: 0.094, green: 0.157, blue: 0.259)]]
        : [[Color(red: 0.561, green: 0.651, blue: 0.741), Color(red: 0.310, green: 0.408, blue: 0.514)],
           [Color(red: 0.659, green: 0.706, blue: 0.761), Color(red: 0.388, green: 0.471, blue: 0.561)],
           [Color(red: 0.596, green: 0.678, blue: 0.729), Color(red: 0.329, green: 0.435, blue: 0.494)]]
        return sets[abs(book.id.hashValue) % sets.count]
    }
    private var progress: CGFloat {
        guard book.chapters > 0 else { return 0 }
        return min(1, CGFloat(book.currentChapter + 1) / CGFloat(book.chapters))
    }
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                LinearGradient(colors: ramp, startPoint: .topLeading, endPoint: .bottomTrailing)
                if let raw = book.coverURL, let url = URL(string: raw) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.clear
                    }
                } else {
                    Text(book.title)
                        .font(.system(size: 10.5, weight: .medium, design: .serif))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(8)
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                }
                // 玻璃高光：让封面像压在一层水汽底下，而不是贴上去的一块色板
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.42), location: 0.00),
                    .init(color: .clear,               location: 0.44),
                    .init(color: .white.opacity(0.10), location: 1.00)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
                .allowsHitTesting(false)
            }
            .aspectRatio(0.72, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(pal.line, lineWidth: 0.5))
            .shadow(color: .black.opacity(isNight ? 0.34 : 0.13), radius: 6, y: 3)

            Text(book.title)
                .font(.system(size: 10.5, design: .serif))
                .foregroundColor(pal.ink2)
                .lineLimit(1)

            // 进度：1.5pt 的细线，参考图里那种几乎看不见的一道
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(pal.ink3.opacity(0.22))
                    Capsule().fill(pal.accent.opacity(0.8))
                        .frame(width: max(0, g.size.width * progress))
                }
            }
            .frame(height: 1.5)

            // 陈璟那条：更细更淡，压在她下面。两条线各走各的，谁也不动谁。
            if book.hasMyMark {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.clear)
                        Capsule().fill(CoreadBookSlot.jingLine)
                            .frame(width: max(0, g.size.width * book.myProgress))
                    }
                }
                .frame(height: 1)
                .padding(.top, 1.5)
            }
        }
    }

    /// 陈璟那条线的颜色：冷一点的蓝，跟她的琥珀分得开
    static let jingLine = Color(red: 0.392, green: 0.565, blue: 0.729).opacity(0.85)
}

private struct CoreadDetailView: View {
    let book: CoreadBook
    let onBack: () -> Void
    let open: (Int) -> Void
    @AppStorage("houseInterfaceAppearance") private var houseAppearance = "dark"
    private var isNight: Bool { houseAppearance != "light" }
    private var pal: YanxiaPal { YanxiaPal(night: isNight) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(pal.ink2)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(pal.card))
                        .overlay(Circle().strokeBorder(pal.line, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.top, 52)
            .padding(.horizontal, 16)

            CoreadBookSlot(book: book, isNight: isNight)
                .frame(width: 116)
                .padding(.top, 10)

            Text(book.title)
                .font(.system(size: 19, weight: .semibold, design: .serif))
                .tracking(1)
                .foregroundColor(pal.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
                .padding(.top, 14)

            Text("共 \(book.chapters) 章 · 已读到第 \(min(book.currentChapter + 1, book.chapters)) 章")
                .font(.system(size: 10, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(pal.ink3)
                .padding(.top, 6)

            // 陈璟自己读到哪。不共读的时候他也在往下走，这一行就是他的书签。
            if book.hasMyMark {
                HStack(spacing: 5) {
                    Circle().fill(CoreadBookSlot.jingLine).frame(width: 3.5, height: 3.5)
                    Text("陈璟读到第 \(book.myChapter + 1) 章 · \(Int(book.myPct.rounded()))%"
                         + (book.myNotes > 0 ? " · 留了 \(book.myNotes) 句" : ""))
                }
                .font(.system(size: 9.5, design: .monospaced))
                .tracking(1)
                .foregroundColor(pal.ink3)
                .padding(.top, 4)
            }

            if !book.readTimeText.isEmpty || book.bookmarkCount > 0 {
                Text([book.readTimeText,
                      book.bookmarkCount > 0 ? "夹了 \(book.bookmarkCount) 处" : ""]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 9.5, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(pal.ink3.opacity(0.8))
                    .padding(.top, 3)
            }

            Button { open(min(book.currentChapter, max(0, book.chapters - 1))) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "book.pages").font(.system(size: 14, weight: .light))
                    Text("继续读下去").font(.system(size: 13.5, design: .serif)).tracking(2)
                }
                .foregroundColor(pal.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Capsule().fill(pal.card))
                .overlay(Capsule().strokeBorder(pal.line, lineWidth: 0.5))
                .shadow(color: .black.opacity(isNight ? 0.24 : 0.09), radius: 9, y: 3)
            }
            .buttonStyle(CoreadPressStyle())
            .padding(.horizontal, 44)
            .padding(.top, 18)

            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(0..<book.chapters, id: \.self) { index in
                        Button { open(index) } label: {
                            HStack(spacing: 10) {
                                Text(String(format: "%02d", index + 1))
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundColor(pal.ink3)
                                Text(book.chapterTitles.indices.contains(index)
                                     ? book.chapterTitles[index] : "第 \(index + 1) 章")
                                    .font(.system(size: 13, design: .serif))
                                    .foregroundColor(pal.ink2)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                if index == book.currentChapter {
                                    Text("读到这儿")
                                        .font(.system(size: 9))
                                        .tracking(1)
                                        .foregroundColor(pal.accent)
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 46)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(index == book.currentChapter ? pal.card : pal.card2))
                            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(pal.line, lineWidth: 0.5))
                        }
                        .buttonStyle(CoreadPressStyle())
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 34)
            }
        }
    }
}

private struct CoreadReaderView: View {
    let book: CoreadBook
    let onBack: () -> Void
    @State private var chapter: Int
    @State private var title = ""
    @State private var content = ""
    @State private var showChat = false
    @State private var samePage = false
    @State private var knocked = false
    @State private var quotedText: String?
    @State private var showSettings = false
    @State private var showMarks = false
    @State private var marked = false
    @State private var openedAt = Date()
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("coreadActiveBookID") private var activeBookID = ""
    @AppStorage("coreadActiveChapter") private var activeChapter = 0
    // 读书的手感存在本机，换书换章都不用重设
    @AppStorage("coreadFontSize") private var fontSize: Double = 17
    @AppStorage("coreadLineSpacing") private var lineSpacing: Double = 9
    private var isNight: Bool { colorScheme == .dark }

    init(book: CoreadBook, chapter: Int, onBack: @escaping () -> Void) {
        self.book = book
        self.onBack = onBack
        _chapter = State(initialValue: chapter)
    }
    var body: some View {
        let pal = YanxiaPal(night: isNight)
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 42, height: 42)
                }
                Text(title.isEmpty ? book.title : title)
                    .font(.system(size: 13.5, weight: .medium, design: .serif))
                    .tracking(0.5)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if samePage {
                    HStack(spacing: 3) {
                        Image(systemName: "person.2").font(.system(size: 9.5, weight: .light))
                        Text("同页").font(.system(size: 9.5)).tracking(1)
                    }
                    .foregroundColor(pal.accent)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Capsule().fill(pal.accent.opacity(0.13)))
                }
                Button { Task { await knock() } } label: {
                    Image(systemName: knocked ? "hand.wave.fill" : "hand.wave")
                        .font(.system(size: 14, weight: .light))
                        .frame(width: 42, height: 42)
                }
                Button { Task { await toggleMark() } } label: {
                    Image(systemName: marked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 14, weight: .light))
                        .frame(width: 36, height: 42)
                }
                Button { showMarks = true } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 13.5, weight: .light))
                        .frame(width: 36, height: 42)
                }
                Button { showSettings = true } label: {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 14, weight: .light))
                        .frame(width: 36, height: 42)
                }
                Button { openChat() } label: {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 14, weight: .light))
                        .frame(width: 36, height: 42)
                }
            }
            .foregroundColor(pal.ink2)
            .padding(.top, 44)
            .padding(.horizontal, 6)
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    (isNight ? Color(red: 0.106, green: 0.125, blue: 0.149) : Color.white)
                        .opacity(isNight ? 0.55 : 0.45)
                }
            }
            .overlay(Rectangle().fill(pal.line).frame(height: 0.5), alignment: .bottom)

            ScrollViewReader { proxy in
                ScrollView {
                    CoreadSelectableText(text: content, isNight: isNight,
                                         fontSize: fontSize, lineSpacing: lineSpacing) { quote in
                        quotedText = quote
                        openChat()
                        Task { await saveHighlight(quote) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 26)
                    .padding(.bottom, 34)
                    .id("top")
                }
                .onChange(of: chapter) { _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("top", anchor: .top) }
                }
            }
            // 读字的地方要素净：这一屏不铺噪点也不铺渐变，只留一层贴近纸的底。
            // 噪点压在正文底下会硌眼睛 —— 皮再好看也不能妨碍她读书。
            .background(isNight ? Color(red: 0.086, green: 0.102, blue: 0.125)
                                : Color(red: 0.973, green: 0.980, blue: 0.984))

            // 翻章：以前只能退回目录再点，现在在这儿翻
            HStack(spacing: 0) {
                Button { turn(-1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .light))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(chapter <= 0)
                .opacity(chapter <= 0 ? 0.3 : 1)

                Text("\(chapter + 1) / \(max(book.chapters, 1))")
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(pal.ink3)
                    .frame(width: 74)

                Button { turn(1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .light))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(chapter >= book.chapters - 1)
                .opacity(chapter >= book.chapters - 1 ? 0.3 : 1)
            }
            .foregroundColor(pal.ink2)
            .padding(.bottom, 6)
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    (isNight ? Color(red: 0.106, green: 0.125, blue: 0.149) : Color.white)
                        .opacity(isNight ? 0.55 : 0.45)
                }
            }
            .overlay(Rectangle().fill(pal.line).frame(height: 0.5), alignment: .top)
        }
        .foregroundColor(pal.ink)
        .task(id: chapter) { await load(); await heartbeat(); await syncMarked() }
        .onDisappear { Task { await saveProgress() } }
        .sheet(isPresented: $showChat) {
            CoreadChatSheet(book: book, chapter: chapter, pageText: String(content.prefix(1800)), quotedText: $quotedText)
        }
        .sheet(isPresented: $showSettings) {
            CoreadReadingSettingsSheet(fontSize: $fontSize, lineSpacing: $lineSpacing, isNight: isNight)
        }
        .sheet(isPresented: $showMarks) {
            CoreadMarksSheet(book: book, isNight: isNight) { ch in
                showMarks = false
                chapter = min(max(0, ch), max(0, book.chapters - 1))
            }
        }
    }

    private func turn(_ step: Int) {
        let next = chapter + step
        guard next >= 0, next < book.chapters else { return }
        Task { await saveProgress() }
        openedAt = Date()
        chapter = next
        activeChapter = next
    }
    @MainActor private func load() async {
        guard let value = try? await NativeHouseAPI.object("/read/api/book/\(book.id)/chapter/\(chapter)") else { return }
        title = value.string("title"); content = value.string("content")
    }
    @MainActor private func heartbeat() async {
        try? await NativeHouseAPI.post("/api/coread/presence", body: ["actor":"陈霁", "book_id":book.id, "chapter":chapter, "offset":0])
        if let value = try? await NativeHouseAPI.object("/api/coread/presence?book_id=\(book.id)") { samePage = value.bool("same_page") }
    }
    @MainActor private func knock() async {
        guard !content.isEmpty else { return }
        try? await NativeHouseAPI.post("/api/coread/knock", body: ["book_id":book.id, "chapter":chapter, "page_text":String(content.prefix(1800))])
        knocked = true
    }
    private func openChat() {
        activeBookID = book.id
        activeChapter = chapter
        showChat = true
    }
    /// 存进度＋这一段读了多久。以前翻到哪儿根本没人记，退出就丢。
    @MainActor private func saveProgress() async {
        let ms = max(0, Int(Date().timeIntervalSince(openedAt) * 1000))
        try? await NativeHouseAPI.post("/read/api/book/\(book.id)/progress",
                                       body: ["chapter": chapter, "read_ms": ms])
        openedAt = Date()
    }

    @MainActor private func syncMarked() async {
        activeBookID = book.id
        activeChapter = chapter
        let list = (try? await NativeHouseAPI.array("/read/api/book/\(book.id)/bookmarks")) ?? []
        marked = list.contains { $0.int("chapter") == chapter }
    }

    @MainActor private func toggleMark() async {
        let list = (try? await NativeHouseAPI.array("/read/api/book/\(book.id)/bookmarks")) ?? []
        if let hit = list.first(where: { $0.int("chapter") == chapter }) {
            try? await NativeHouseAPI.post("/read/api/book/\(book.id)/bookmarks/\(hit.string("id"))/delete", body: [:])
            marked = false
        } else {
            try? await NativeHouseAPI.post("/read/api/book/\(book.id)/bookmarks", body: [
                "chapter": chapter,
                "chapter_title": title.isEmpty ? "第 \(chapter + 1) 章" : title,
                "scroll": 0,
                "excerpt": String(content.prefix(40))
            ])
            marked = true
        }
    }

    @MainActor private func saveHighlight(_ quote: String) async {
        try? await NativeHouseAPI.post("/read/api/book/\(book.id)/annotate", body: [
            "chapter": chapter, "text": quote, "note": "引用到陪读室", "author": "luna"
        ])
    }
}

private struct CoreadSelectableText: UIViewRepresentable {
    let text: String
    let isNight: Bool
    var fontSize: Double = 17
    var lineSpacing: Double = 9
    let onQuote: (String) -> Void

    func makeUIView(context: Context) -> CoreadTextView {
        let view = CoreadTextView()
        view.isEditable = false
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.widthTracksTextView = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.onQuote = onQuote
        return view
    }
    func updateUIView(_ view: CoreadTextView, context: Context) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = CGFloat(lineSpacing)
        paragraph.paragraphSpacing = CGFloat(lineSpacing) + 3
        view.attributedText = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: CGFloat(fontSize)),
            .foregroundColor: isNight ? UIColor(red: 0.86, green: 0.89, blue: 0.92, alpha: 1) : UIColor(red: 0.165, green: 0.185, blue: 0.212, alpha: 1),
            .paragraphStyle: paragraph
        ])
        view.onQuote = onQuote
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CoreadTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let measured = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: measured.height)
    }
}

private final class CoreadTextView: UITextView {
    var onQuote: ((String) -> Void)?
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .context else { return }
        let action = UIAction(title: "引用到陪读室", image: UIImage(systemName: "quote.bubble")) { [weak self] _ in
            guard let self, let range = selectedTextRange,
                  let quote = text(in: range)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !quote.isEmpty else { return }
            onQuote?(quote)
        }
        builder.insertChild(UIMenu(options: .displayInline, children: [action]), atStartOfMenu: .standardEdit)
    }
}

/// 两个共读面板共用的底：跟共读室一个色系，不另起炉灶
private struct CoreadSheetBG: View {
    let isNight: Bool
    var body: some View {
        (isNight ? Color(red: 0.137, green: 0.153, blue: 0.173)
                 : Color(red: 0.965, green: 0.973, blue: 0.980))
            .ignoresSafeArea()
    }
}

/// 读书的手感：字大一点、行松一点，她自己调。存本机，换书也记得。
private struct CoreadReadingSettingsSheet: View {
    @Binding var fontSize: Double
    @Binding var lineSpacing: Double
    let isNight: Bool
    @Environment(\.dismiss) private var dismiss
    private var pal: YanxiaPal { YanxiaPal(night: isNight) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("读着舒服就好").font(.system(size: 15, weight: .semibold, design: .serif)).tracking(1)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .medium)) }
                    .buttonStyle(.plain)
            }
            .foregroundColor(pal.ink)
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Text("这一段是给你看的：字挪大一点，行松一点，眼睛就不那么累了。")
                .font(.system(size: CGFloat(fontSize), design: .serif))
                .lineSpacing(CGFloat(lineSpacing))
                .foregroundColor(pal.ink2)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .frame(maxWidth: .infinity, alignment: .leading)

            row(title: "字号", value: Int(fontSize).description) {
                Slider(value: $fontSize, in: 14...23, step: 0.5).tint(pal.accent)
            }
            row(title: "行距", value: Int(lineSpacing).description) {
                Slider(value: $lineSpacing, in: 4...18, step: 0.5).tint(pal.accent)
            }

            Button {
                fontSize = 17; lineSpacing = 9
            } label: {
                Text("恢复原来的").font(.system(size: 11.5, design: .serif)).tracking(1)
                    .foregroundColor(pal.ink3)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Capsule().fill(pal.card2))
                    .overlay(Capsule().strokeBorder(pal.line, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 6)

            Spacer(minLength: 12)
        }
        .background(CoreadSheetBG(isNight: isNight))
        .presentationDetents([.height(340)])
    }

    @ViewBuilder private func row<C: View>(title: String, value: String, @ViewBuilder control: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 11.5, design: .serif)).tracking(1.5)
                Spacer()
                Text(value).font(.system(size: 10.5, design: .monospaced))
            }
            .foregroundColor(pal.ink3)
            control()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }
}

/// 她夹的书签。私有的，一条都不推给陈璟。
private struct CoreadMarksSheet: View {
    let book: CoreadBook
    let isNight: Bool
    let onJump: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var marks: [[String: Any]] = []
    @State private var loading = true
    private var pal: YanxiaPal { YanxiaPal(night: isNight) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("夹过的地方").font(.system(size: 15, weight: .semibold, design: .serif)).tracking(1)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .medium)) }
                    .buttonStyle(.plain)
            }
            .foregroundColor(pal.ink)
            .padding(20)

            if loading {
                ProgressView().tint(pal.accent).frame(maxHeight: .infinity)
            } else if marks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bookmark").font(.system(size: 22, weight: .ultraLight))
                    Text("还没夹过。读到舍不得走的地方，点右上角那个书签")
                        .font(.system(size: 11.5, design: .serif))
                        .multilineTextAlignment(.center)
                }
                .foregroundColor(pal.ink3)
                .padding(.horizontal, 40)
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                            HStack(spacing: 10) {
                                Button { onJump(mark.int("chapter")) } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(mark.string("chapter_title").isEmpty
                                             ? "第 \(mark.int("chapter") + 1) 章"
                                             : mark.string("chapter_title"))
                                            .font(.system(size: 12.5, design: .serif))
                                            .foregroundColor(pal.ink2)
                                            .lineLimit(1)
                                        if !mark.string("excerpt").isEmpty {
                                            Text(mark.string("excerpt"))
                                                .font(.system(size: 10, design: .serif))
                                                .foregroundColor(pal.ink3)
                                                .lineLimit(1)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                Button { Task { await remove(mark.string("id")) } } label: {
                                    Image(systemName: "trash").font(.system(size: 11, weight: .light))
                                        .foregroundColor(pal.ink3)
                                        .frame(width: 32, height: 32)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(pal.card))
                            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(pal.line, lineWidth: 0.5))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(CoreadSheetBG(isNight: isNight))
        .presentationDetents([.medium])
        .task { await load() }
    }

    @MainActor private func load() async {
        loading = true; defer { loading = false }
        marks = (try? await NativeHouseAPI.array("/read/api/book/\(book.id)/bookmarks")) ?? []
    }

    @MainActor private func remove(_ id: String) async {
        try? await NativeHouseAPI.post("/read/api/book/\(book.id)/bookmarks/\(id)/delete", body: [:])
        await load()
    }
}

private struct CoreadChatSheet: View {
    let book: CoreadBook
    let chapter: Int
    let pageText: String
    @Binding var quotedText: String?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("houseInterfaceAppearance") private var houseAppearance = "dark"
    @State private var messages: [[String: Any]] = []
    @State private var text = ""
    private var isNight: Bool { houseAppearance != "light" }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("陪读 · \(book.title)").font(.system(size: 15, weight: .semibold, design: .serif)); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark") } }.padding(18)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, item in
                            HStack { if item.string("actor") == "陈霁" { Spacer() }; Text(item.string("text")).font(.system(size: 14)).foregroundColor(isNight ? Color(red: 0.90, green: 0.93, blue: 0.95) : Color(red: 0.165, green: 0.185, blue: 0.212)).padding(12).background(item.string("actor") == "陈霁" ? Color(red: 0.353, green: 0.498, blue: 0.659).opacity(isNight ? 0.24 : 0.2) : (isNight ? Color.white.opacity(0.08) : Color.white.opacity(0.8)), in: RoundedRectangle(cornerRadius: 14)); if item.string("actor") != "陈霁" { Spacer() } }
                        }
                    }.padding(14)
                }
            }
            VStack(spacing: 7) {
                if let quote = quotedText, !quote.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "quote.opening").font(.system(size: 11))
                        Text(quote).font(.system(size: 12, design: .serif)).lineLimit(3)
                        Spacer()
                        Button { quotedText = nil } label: { Image(systemName: "xmark.circle.fill") }
                    }
                    .foregroundColor(isNight ? Color(red: 0.89, green: 0.77, blue: 0.81) : Color(red: 0.48, green: 0.34, blue: 0.39))
                    .padding(10).background(isNight ? Color.white.opacity(0.07) : Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 12))
                }
                HStack { TextField("和陈璟聊聊这一页…", text: $text).textFieldStyle(.roundedBorder); Button("发送") { Task { await send() } }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.padding(12)
        }
        .background(isNight ? Color(red: 0.17, green: 0.125, blue: 0.145) : Color(red: 0.97, green: 0.93, blue: 0.94))
        .presentationDetents([.fraction(0.52), .large]).presentationDragIndicator(.visible)
        .task { await poll() }
    }
    @MainActor private func poll() async {
        while !Task.isCancelled {
            if let value = try? await NativeHouseAPI.object("/api/coread/messages?book_id=\(book.id)&chapter=\(chapter)&since=0") { messages = value.array("messages") }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
    }
    @MainActor private func send() async {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !value.isEmpty else { return }; text = ""
        let outgoing = quotedText.map { "「\($0)」\n\(value)" } ?? value
        quotedText = nil
        try? await NativeHouseAPI.post("/api/coread/say", body: ["book_id":book.id, "chapter":chapter, "text":outgoing, "page_text":pageText])
    }
}

private struct NativePlayView: View {
    let destination: HouseDestination
    @AppStorage("houseInterfaceAppearance") private var appearance = "dark"
    private var dark: Bool { appearance != "light" }
    private var theme: AlcoveTheme { dark ? .messagesDark : .messages }
    private var url: URL {
        switch destination {
        case .crosstalk: return URL(string: "https://clunaadke.github.io/crosstalk/#https://vrnhyhofzzmbgzaarbaz.supabase.co")!
        case .coread: return AlcoveAPI.fullURL("/read/")
        case .liao: return AlcoveAPI.fullURL("/liao")
        default: return AlcoveAPI.fullURL("/")
        }
    }
    var body: some View {
        VStack(spacing: 8) {
            Text(destination.title).font(.system(size: 19, weight: .semibold)).padding(.top, 12)
            FixedWebView(url: url).clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .padding(.horizontal, 12).padding(.bottom, 12)
        .foregroundColor(theme.text)
        .background((dark ? Color(red: 0.07, green: 0.075, blue: 0.085)
                          : Color(red: 0.95, green: 0.95, blue: 0.97)).ignoresSafeArea())
        .preferredColorScheme(dark ? .dark : .light)
    }
}

private struct FixedWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(initialURL: url) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        let initialHost: String?
        init(initialURL: URL) { initialHost = initialURL.host }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let target = navigationAction.request.url else {
                decisionHandler(.allow); return
            }
            if navigationAction.navigationType == .linkActivated,
               let iHost = initialHost, target.host != iHost,
               target.host == AlcoveAPI.base.host {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

// MARK: - Foyer shapes (iOS 16 compat)

private struct JournalCardShape: Shape {
    let tl: CGFloat, bl: CGFloat, br: CGFloat, tr: CGFloat
    init(tl: CGFloat = 6, bl: CGFloat = 6, br: CGFloat = 14, tr: CGFloat = 14) {
        self.tl = tl; self.bl = bl; self.br = br; self.tr = tr
    }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                 tangent2End: CGPoint(x: rect.maxX, y: rect.minY + tr), radius: tr)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.maxX - br, y: rect.maxY), radius: br)
        p.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bl), radius: bl)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                 tangent2End: CGPoint(x: rect.minX + tl, y: rect.minY), radius: tl)
        p.closeSubpath()
        return p
    }
}

// MARK: - Foyer 可复用组件

private struct FoyerSash: View {
    let theme: AlcoveTheme
    var body: some View {
        LinearGradient(
            colors: [.clear, theme.fyAccentSoft, .clear],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(width: UIScreen.main.bounds.width * 0.58, height: 2)
        .clipShape(Capsule())
        .padding(.bottom, 4)
    }
}

private struct FoyerFoldCorner: View {
    let theme: AlcoveTheme
    var body: some View {
        Canvas { ctx, size in
            let path = Path { p in
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: size.width, y: 0))
                p.addLine(to: CGPoint(x: 0, y: size.height))
                p.closeSubpath()
            }
            ctx.fill(path, with: .color(theme.fyFold))
        }
        .frame(width: 26, height: 26)
    }
}

private struct FoyerPanelTitle: View {
    let title: String
    let theme: AlcoveTheme
    @Environment(\.houseOwnsHeader) private var houseOwnsHeader
    @ViewBuilder
    var body: some View {
        if !houseOwnsHeader {
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .tracking(0.5)
                FoyerSash(theme: theme)
            }
            .padding(.top, 12)
        }
    }
}

private struct BindingHole: View {
    let theme: AlcoveTheme
    let count: Int
    let spacing: CGFloat

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { _ in
                Circle()
                    .fill(theme.fyBorder)
                    .frame(width: 5, height: 5)
            }
        }
    }
}

private struct FoyerGlassContainer<Content: View>: View {
    let spacing: CGFloat
    let paper: Bool
    private let content: Content

    init(spacing: CGFloat, paper: Bool = false, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.paper = paper
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if paper {
            content
        } else if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

private extension View {
    func foyerShell(_ theme: AlcoveTheme) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.isPaper ? 0 : 28, style: .continuous)
        return self
            .clipShape(shape)
            .overlay {
                if !theme.isPaper { shape
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(theme.isDark ? 0.58 : 0.90), location: 0),
                                .init(color: .white.opacity(theme.isDark ? 0.18 : 0.38), location: 0.45),
                                .init(color: .black.opacity(theme.isDark ? 0.34 : 0.12), location: 1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.25
                    )
                    .allowsHitTesting(false) }
            }
            .overlay {
                if !theme.isPaper { shape
                    .inset(by: 1.4)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(theme.isDark ? 0.22 : 0.48),
                                .clear,
                                .black.opacity(theme.isDark ? 0.18 : 0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
                    .allowsHitTesting(false) }
            }
            .shadow(
                color: .black.opacity(theme.isPaper ? 0 : (theme.isDark ? 0.34 : 0.16)),
                radius: theme.isPaper ? 0 : 9,
                x: 0,
                y: 4
            )
    }

    func houseGlass(_ theme: AlcoveTheme) -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background(theme.glassTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.glassBorder, lineWidth: 1))
    }

    // iOS 26 必须把系统玻璃直接应用到内容视图，确保图标和文字绘制在玻璃上方。
    @ViewBuilder
    func foyerCard(_ theme: AlcoveTheme) -> some View {
        let shape = JournalCardShape(tl: 14, bl: 14, br: 18, tr: 18)

        if theme.isPaper {
            self
                .background(theme.fyCard, in: JournalCardShape(tl: 4, bl: 10, br: 3, tr: 12))
                .overlay(JournalCardShape(tl: 4, bl: 10, br: 3, tr: 12)
                    .stroke(theme.fyBorder.opacity(0.78), lineWidth: 0.8))
                .overlay(alignment: .topLeading) {
                    Rectangle().fill(theme.fyAccent.opacity(0.28))
                        .frame(width: 22, height: 2).offset(x: 10, y: 5)
                }
                .overlay(alignment: .bottomTrailing) {
                    Circle().fill(theme.fyBorder.opacity(0.55))
                        .frame(width: 3, height: 3).padding(8)
                }
                .contentShape(JournalCardShape(tl: 4, bl: 10, br: 3, tr: 12))
                .shadow(color: theme.fyShadow.opacity(0.65), radius: 1.5, x: 1, y: 2)
        } else {
            self
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(theme.isDark ? 0.30 : 0.42)
                }
                .background(
                    theme.fyCard.opacity(theme.isDark ? 0.018 : 0.035),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(theme.glassBorder.opacity(0.58), lineWidth: 0.65)
                )
                .contentShape(shape)
                .shadow(
                    color: .black.opacity(theme.isDark ? 0.18 : 0.08),
                    radius: 4,
                    x: 1,
                    y: 2
                )
        }
    }

    // Detail pages sit directly on the shared wet-glass wallpaper.
    // Keep their content and spacing intact; remove only the extra dark shell.
    func foyerPanel(_ theme: AlcoveTheme) -> some View {
        self.overlay(alignment: .leading) {
            if theme.isPaper {
                Rectangle().fill(theme.fyAccent.opacity(0.20))
                    .frame(width: 1).padding(.vertical, 54).padding(.leading, 7)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Chenjing Studio

/// 0925 工作室一步工具：后端 workroom.turn_end 从工作室记录本里抠出来存进 tool_log（JSON 列表 [{"name","desc"}]）
struct StudioToolStep {
    let name: String
    let desc: String

    /// mcp__browser__browser_click 这种只留最后一截
    private var shortName: String {
        name.hasPrefix("mcp__") ? (name.components(separatedBy: "__").last ?? name) : name
    }
    var verb: String { name == "Bash" ? "Ran" : "Used \(shortName)" }
    var icon: String {
        switch name {
        case "Bash": return "terminal"
        case "Read": return "doc.text"
        case "Edit", "Write", "NotebookEdit": return "pencil"
        case "Grep", "Glob": return "magnifyingglass"
        case "WebFetch", "WebSearch": return "globe"
        case "Agent": return "person.2"
        default: return name.hasPrefix("mcp__") ? "puzzlepiece.extension" : "wrench.and.screwdriver"
        }
    }

    static func parse(_ raw: String) -> [StudioToolStep] {
        guard !raw.isEmpty, let data = raw.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return arr.map { StudioToolStep(name: ($0["name"] as? String) ?? "", desc: ($0["desc"] as? String) ?? "") }
    }
}

private struct NativeStudioView: View {
    @State private var status: [String: Any] = [:]
    @State private var tasks: [[String: Any]] = []
    @State private var messages: [[String: Any]] = []
    @State private var showTerminal = false
    @State private var deliveryDraft: [String: Any]?
    @State private var deliveryTitle = ""
    @State private var deliverySummary = ""
    @State private var deliveryArtifacts: [String] = []
    @State private var newArtifact = ""
    @State private var showActions = false
    @State private var loading = true
    @State private var studioNotice = ""
    @State private var showStudioNotice = false
    @State private var expandedThoughts: Set<Int> = []
    // 0925 长按「询问」：选中的字挂到输入框上方，发的时候用「」括起来放在前面
    @State private var studioQuote: String?
    // 0818 她说工作室发图不能多选、没有预览。这三样跟主聊天对齐：
    // 选完先进待发条（可单张删），跟文字一起发，一次最多九张。
    @State private var pendingImages: [(thumb: UIImage, data: Data, ext: String)] = []
    // 0907 她抓的：点预览会无限「打开→退出→打开」，点哪儿都不行只能清后台。
    // 原来这儿存的是 UIImage，弹窗那行再拿它现造 StudioLocalPhoto ——
    // 那东西的 id 是 UUID()，每次界面重算都换一个新号，
    // fullScreenCover 认号不认人，号一变就当成另一张图，关掉重开、循环不止。
    // 存成带 id 的包装，进预览时发一次号，之后一直是它。
    @State private var previewImage: StudioLocalPhoto?
    @State private var photoViewer: StudioPhotoTarget?
    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    @Environment(\.dismiss) private var dismiss
    @AppStorage("alcoveTheme") private var themeName = "haven"
    private var theme: AlcoveTheme { .panelNamed(themeName) }
    // 0924 她要的：聊天页选了 Kakao，工作室半屏也跟着那套包走——壁纸、九宫格气泡、头像名字、时间贴气泡旁、日期胶囊。
    // 顶栏按钮照旧，名字就是「工作室」。别的主题一个像素不变。
    @ObservedObject private var kakaoPacks = KakaoPackStore.shared
    private var isKakao: Bool { themeName == "kakao" }
    // 0924 她要的：工作室的字号跟聊天页那个「字号」设置走，字体已经跟全局走了
    @AppStorage("chatFontSize") private var chatFontSize = 14
    private var studioFontSize: CGFloat { CGFloat(chatFontSize) }
    @AppStorage(KakaoPackStore.showAvatarKey) private var kakaoShowAvatar = true
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private func studioDate(_ m: [String: Any]) -> Date? {
        let raw = m.string("ts")
        return Self.isoFrac.date(from: raw) ?? Self.isoPlain.date(from: raw)
    }
    @ViewBuilder private var studioBackground: some View {
        if isKakao {
            GeometryReader { g in
                if let wall = kakaoPacks.wallImage {
                    Image(uiImage: wall).resizable().scaledToFill()
                        .frame(width: g.size.width, height: g.size.height).clipped()
                } else {
                    (kakaoPacks.wallColor ?? Color(red: 0xB2/255, green: 0xC7/255, blue: 0xD9/255))
                }
            }
        } else {
            LinearGradient(colors: theme.isDark ? [Color(red: 0.075, green: 0.068, blue: 0.09), Color(red: 0.13, green: 0.105, blue: 0.14)] : [Color(red: 0.985, green: 0.955, blue: 0.945), Color(red: 0.94, green: 0.91, blue: 0.90)], startPoint: .top, endPoint: .bottom)
        }
    }
    /// Kakao 气泡：包里的九宫格图，时间贴外侧下角
    /// 0925 她要的：工作室气泡长按跟主聊天一样——能选字，菜单里「询问」「复制整轮」（跟主聊天同一个组件）
    private func studioText(_ text: String, message: [String: Any], color: Color) -> some View {
        SelectableMessageText(
            text: text,
            fontSize: studioFontSize,
            lineSpacing: 5,
            color: UIColor(color),
            onAsk: { studioQuote = $0 },
            onCopyTurn: { UIPasteboard.general.string = studioTurnText(message) },
            fontName: kakaoPacks.fontName,
            serif: !isKakao
        )
    }

    /// 「复制整轮」：这条和它前后连着的、同一个人同一单（task_id）的气泡，按顺序拼起来
    private func studioTurnText(_ message: [String: Any]) -> String {
        guard let idx = messages.firstIndex(where: { $0.int("id") == message.int("id") }) else {
            return message.string("text")
        }
        let role = message.string("role")
        let task = message.int("task_id")
        func same(_ m: [String: Any]) -> Bool { task != 0 && m.string("role") == role && m.int("task_id") == task }
        var lo = idx, hi = idx
        while lo > 0 && same(messages[lo - 1]) { lo -= 1 }
        while hi + 1 < messages.count && same(messages[hi + 1]) { hi += 1 }
        return messages[lo...hi].map { $0.string("text") }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private func kakaoTextBubble(_ text: String, message: [String: Any], mine: Bool, head: Bool, date: Date?) -> some View {
        let kt = AlcoveTheme.kakaoTheme()
        // 0924 晚她抓的「你的气泡宽度？」：工作室每条都挂时间，时间原来跟气泡并排占掉一截宽度，气泡比主聊天窄。
        // 0925 她又抓的「？时间戳？？」：上一版用 overlay + alignmentGuide 往外挂，guide 没生效，时间压进了气泡右下角。
        // 改成时间还跟气泡排一行，但套一个 0 宽的框、字往外溢出去：不占气泡宽度，也不会压在气泡上。
        func stamp(_ d: Date) -> some View {
            Text(KakaoClock.fmt.string(from: d)).font(.system(size: 10)).foregroundColor(kt.timestamp)
                .fixedSize()
                .padding(.bottom, 2)
        }
        return HStack(alignment: .bottom, spacing: 0) {
            if mine, let date {
                stamp(date).padding(.trailing, 5).frame(width: 0, alignment: .trailing)
            }
            KakaoBubbleView(isUser: mine, first: head) {
                studioText(text, message: message, color: mine ? (kt.textUser ?? kt.text) : (kt.textAI ?? kt.text))
            }
            if !mine, let date {
                stamp(date).padding(.leading, 5).frame(width: 0, alignment: .leading)
            }
        }
        // 0924 她要的：他的气泡整块往左下挪一点（跟聊天页同一个数），头像名字不动
        .padding(.leading, (!mine && kakaoShowAvatar) ? -MessageRow.kakaoBubbleShiftLeft : 0)
        .padding(.top, (!mine && kakaoShowAvatar) ? MessageRow.kakaoBubbleShiftDown : 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.18)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 13) {
                        Text("工作室里的也是我本人，同锚点同记忆，只是换了间屋子干活，不是分身。")
                            .font(.system(size: 11, design: .serif)).foregroundColor(theme.textDim)
                            .padding(.vertical, 12)
                        // 0818 她截到工作室空屏：以前每 2 秒把整个数组换掉、再连打四次
                        // scrollTo，LazyVStack 内容高度一抖 contentOffset 停在旧值上，
                        // 屏幕就白了。现在按 id 稳定身份、只追加新消息、只在真有新消息时滚一次。
                        // 0829：同组图片（att_group）合并成一条横排气泡，跟主聊天一致
                        let items = displayItems
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            let prev: [String: Any]? = idx > 0 ? items[idx - 1].primary : nil
                            // Kakao：一串同一边的消息只有第一条露头像 / 名字 / 带尾巴的 01 图
                            let head = prev.map { $0.string("role") != item.primary.string("role") } ?? true
                            // 0925 她要的：跟主聊天一样，同一个人两分钟内连着发的算一串，只在一串最后一条挂时间
                            let next: [String: Any]? = idx + 1 < items.count ? items[idx + 1].primary : nil
                            let showTime: Bool = {
                                guard let next else { return true }
                                if next.string("role") != item.primary.string("role") { return true }
                                guard let a = studioDate(item.primary), let b = studioDate(next) else { return true }
                                return b.timeIntervalSince(a) > 120
                            }()
                            Group {
                                // 0924 晚她定的：跟主聊天 Kakao 对齐——只跟紧挨着的上一条比，隔超过 15 分钟就插胶囊（原来只在跨天时插）
                                if isKakao, let d = studioDate(item.primary),
                                   prev.map({ p in d.timeIntervalSince(studioDate(p) ?? d) > 900 }) ?? true {
                                    KakaoDateDivider(date: d)
                                }
                                if item.group.count > 1 {
                                    photoGroupBubble(item, head: head, showTime: showTime)
                                } else {
                                    messageBubble(item.primary, head: head, showTime: showTime)
                                }
                            }.id("studio-message-\(item.id)")
                        }
                        if let current = status["current_task"] as? [String: Any] {
                            HStack(spacing: 7) { ProgressView().scaleEffect(0.7); Text("正在处理 · \(current.string("title"))") }
                                .font(.system(size: 10)).foregroundColor(theme.textDim).padding(9)
                        }
                        Color.clear.frame(height: 1).id("studio-tail")
                    }.padding(.horizontal, isKakao ? 12 : 15).padding(.bottom, 16)   // 0924 晚：Kakao 下跟主聊天列表一样留 12
                }
                .defaultScrollAnchor(.bottom)
                // 0904 她报的「工作室键盘下不去，只有发一条才收」：往下滑列表跟手收，点列表任何地方也收
                .scrollDismissesKeyboard(.interactively)
                // 1003 她报的「一复制你的消息，选中的字一秒就没了」：原来这里叫「当前第一响应者」全体退下，
                // 长按选字松手也算点了一下，选中的那段跟着被收掉。改成跟主聊天一样只让输入框失焦（输入框在 StudioInputBar 里，发通知过去）
                .simultaneousGesture(TapGesture().onEnded {
                    NotificationCenter.default.post(name: .studioDropKeyboard, object: nil)
                })
                .onChange(of: messages.last?.int("id") ?? 0) { _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("studio-tail", anchor: .bottom) }
                }
            }
            inputBar
        }
        .background(studioBackground.ignoresSafeArea())
        .foregroundColor(theme.text)
        .overlay { if loading { ProgressView().tint(theme.fyAccent) } }
        .fullScreenCover(isPresented: $showTerminal) { TerminalView(initialSession: "work", availableSessions: ["work"]) }
        .sheet(isPresented: Binding(get: { deliveryDraft != nil }, set: { if !$0 { deliveryDraft = nil } })) { deliveryPreview }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoLibraryPicker(maxCount: 9) { images in
                for image in images {
                    if let prepared = UploadImage.prepare(image) { pendingImages.append(prepared) }
                }
            }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item]) { result in
            guard case .success(let url) = result else { return }
            Task { await uploadFile(url) }
        }
        .fullScreenCover(item: $photoViewer) { target in
            StudioPhotoViewer(url: target.url) { photoViewer = nil }
        }
        .fullScreenCover(item: $previewImage) { local in
            StudioLocalPhotoViewer(image: local.image) { previewImage = nil }
        }
        .alert("工作室", isPresented: $showStudioNotice) { Button("知道了", role: .cancel) {} } message: { Text(studioNotice) }
        .confirmationDialog("工作室操作", isPresented: $showActions, titleVisibility: .visible) {
            if let task = currentOrLatestTask, task.string("status") == "queued" { Button("暂停排队任务") { Task { await action(task, "pause") } } }
            if let task = currentOrLatestTask, task.string("status") == "paused" { Button("继续任务") { Task { await action(task, "resume") } } }
            if let task = latestDoneTask { Button("带回主聊天") { Task { await deliver(task) } } }
            if !hasStudioAction { Button("当前没有可操作任务", role: .cancel) {} }
            Button("取消", role: .cancel) {}
        }
        .task { while !Task.isCancelled { await refresh(); try? await Task.sleep(nanoseconds: 2_000_000_000) } }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").frame(width: 48, height: 48).contentShape(Rectangle())
            }
                .buttonStyle(.plain).accessibilityLabel("返回总控台")
            VStack(alignment: .leading, spacing: 2) {
                Text("工作室").font(.system(size: 20, weight: .semibold, design: .serif))
                HStack(spacing: 5) {
                    Circle().fill(stateColor).frame(width: 6, height: 6)
                    Text(stateText)
                    Text("· \(compact(status.int("context_tokens"))) context")
                }.font(.system(size: 9.5)).foregroundColor(theme.textDim)
            }
            Spacer()
            Button { showActions = true } label: {
                Image(systemName: "ellipsis.circle").frame(width: 38, height: 38).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("工作室操作")
            Button { showTerminal = true } label: { Image(systemName: "terminal").frame(width: 34, height: 34).background(.white.opacity(0.42), in: Circle()) }
                .buttonStyle(.plain).accessibilityLabel("查看工作室终端")
        }.padding(.horizontal, 15).padding(.bottom, 10).padding(.top, 54)
    }

    /// 公网入口只认 /api 前缀（0829 实测 /work/attachments 直连是 404）
    static func workAttachmentURL(_ raw: String) -> URL {
        AlcoveAPI.fullURL(raw.hasPrefix("/work/attachments") ? "/api" + raw : raw)
    }

    /// 同一组（att_group）的连续图片消息折成一条横排；其余原样
    private var displayItems: [StudioDisplayItem] {
        var out: [StudioDisplayItem] = []
        var i = 0
        while i < messages.count {
            let message = messages[i]
            let group = message.string("att_group")
            if !group.isEmpty, message.string("attachment_type") == "image" {
                var bunch = [message]
                var j = i + 1
                while j < messages.count, messages[j].string("att_group") == group {
                    bunch.append(messages[j]); j += 1
                }
                out.append(StudioDisplayItem(id: message.int("id"), group: bunch))
                i = j
            } else {
                out.append(StudioDisplayItem(id: message.int("id"), group: [message]))
                i += 1
            }
        }
        return out
    }

    /// 多图横排气泡：≤2 并排，>2 横滑（跟主聊天一个观感），配文垫在图下面
    private func photoGroupBubble(_ item: StudioDisplayItem, head: Bool = true, showTime: Bool = true) -> some View {
        let mine = item.primary.string("role") == "user"
        let caption = item.group.map { $0.string("text") }.first { !$0.isEmpty } ?? ""
        let side: CGFloat = 124
        let gap: CGFloat = 8
        return HStack(alignment: (isKakao && !mine) ? .top : .bottom) {
            if mine { Spacer(minLength: 52) }
            if isKakao && !mine && kakaoShowAvatar {
                KakaoAvatarView(visible: head).padding(.trailing, 8)   // 0924 她定的：不带名字
            }
            VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
                Group {
                    if item.group.count > 2 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: gap) {
                                ForEach(item.group, id: \.studioMessageID) { m in thumb(m, side: side) }
                            }
                        }.frame(width: side * 2 + gap * 2 + 52, height: side)  // 0920 跟主聊天一样露第三张一截
                    } else {
                        HStack(spacing: gap) {
                            ForEach(item.group, id: \.studioMessageID) { m in thumb(m, side: side) }
                        }
                    }
                }
                if !caption.isEmpty {
                    if isKakao {
                        kakaoTextBubble(caption, message: item.primary, mine: mine, head: head, date: showTime ? studioDate(item.primary) : nil)
                    } else {
                    studioText(caption, message: item.primary, color: theme.text)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(mine ? theme.bubbleUser : theme.bubbleAI, in: RoundedRectangle(cornerRadius: 18))
                        .frame(maxWidth: 300, alignment: mine ? .trailing : .leading)
                    }
                }
            }
            if !mine { Spacer(minLength: 52) }
        }
    }

    private func thumb(_ message: [String: Any], side: CGFloat) -> some View {
        let url = Self.workAttachmentURL(message.string("attachment_url"))
        return CachedImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack { Color.black.opacity(0.06); ProgressView() }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { photoViewer = StudioPhotoTarget(url: url) }
        .modifier(StudioSaveMenu(url: url))
    }

    /// 0925 工作室的过程线，照主聊天 messagesProcessBlock：一颗小圆点 + 大脑图标一排；
    /// 点小圆点在下面展开这一轮用过的工具（左边一根细线），大脑点开是原生思考面板（带翻译，跟主聊天同一个）。
    @ViewBuilder
    private func studioProcessBlock(messageID: Int, thought: String, tools: [StudioToolStep]) -> some View {
        let open = expandedThoughts.contains(messageID)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                if !tools.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if open { expandedThoughts.remove(messageID) } else { expandedThoughts.insert(messageID) }
                        }
                    } label: {
                        Circle()
                            .fill(theme.thoughtColor.opacity(open ? 0.95 : 0.5))
                            .frame(width: 7, height: 7)
                            .frame(width: 22, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if !thought.isEmpty {
                    NativeThinkingButton(text: thought, color: theme.thoughtColor, iosOnly: true)
                }
            }
            if open && !tools.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(tools.enumerated()), id: \.offset) { _, step in
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: step.icon)
                                .font(.system(size: 10, weight: .light))
                                .frame(width: 14)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(step.verb).font(.custom("Georgia", size: 11.5))
                                if !step.desc.isEmpty {
                                    Text(step.desc).font(.system(size: 11)).lineLimit(2)
                                }
                            }
                        }
                    }
                }
                .foregroundColor(theme.thoughtColor)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Capsule().fill(theme.thoughtColor.opacity(0.28)).frame(width: 1.5)
                }
                .transition(.opacity)
            }
        }
        .padding(.leading, 4)
    }

    private func messageBubble(_ message: [String: Any], head: Bool = true, showTime: Bool = true) -> some View {
        let mine = message.string("role") == "user"
        let messageID = message.int("id")
        let thought = message.string("thinking")
        let tools = StudioToolStep.parse(message.string("tool_log"))
        // 0924 晚她要的：Kakao 下工作室气泡跟主聊天一样宽——间距钉成 0、两边空白按主聊天的 48，
        // 头像后面照旧留 16（原来 8 + 系统默认间距 8），猫图案不挡头像；他那边右侧少留 8 补回来，最宽跟主聊天一样
        return HStack(alignment: (isKakao && !mine) ? .top : .bottom, spacing: isKakao ? 0 : nil) {
            if mine { Spacer(minLength: isKakao ? 48 : 52) }
            if isKakao && !mine && kakaoShowAvatar {
                KakaoAvatarView(visible: head).padding(.trailing, 16)   // 0924 她定的：不带名字
            }
            VStack(alignment: mine ? .trailing : .leading, spacing: 5) {
                // 0925 她要的：跟主聊天一样——小圆点（点开是这一轮用过的工具）＋大脑（原生思考面板），
                // 换掉原来那张「工作思绪」卡片和最底下的「终端记录」
                if !mine && (!thought.isEmpty || !tools.isEmpty) {
                    studioProcessBlock(messageID: messageID, thought: thought, tools: tools)
                }
                if !message.string("attachment_url").isEmpty {
                    let attachmentURL = Self.workAttachmentURL(message.string("attachment_url"))
                    if message.string("attachment_type") == "image" {
                        // 0829：AsyncImage 换 CachedImage（磁盘缓存+重试），URL 补 /api 前缀
                        // ——公网入口只认 /api，这就是「图片一直转圈」的根因
                        CachedImage(url: attachmentURL) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            ZStack { Color.black.opacity(0.06); ProgressView() }.frame(width: 220, height: 220)
                        }
                        .frame(maxWidth: 220, maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .onTapGesture { photoViewer = StudioPhotoTarget(url: attachmentURL) }
                        .modifier(StudioSaveMenu(url: attachmentURL))
                    } else {
                        Label(message.string("attachment_filename").isEmpty ? "附件" : message.string("attachment_filename"), systemImage: "doc")
                            .font(.system(size: 11, weight: .medium)).padding(9)
                            .background(.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 11))
                    }
                }
                // 只有图没有字的时候不要再吐一个空气泡出来
                if !message.string("text").isEmpty {
                    if isKakao {
                        kakaoTextBubble(message.string("text"), message: message, mine: mine, head: head, date: showTime ? studioDate(message) : nil)
                    } else {
                    studioText(message.string("text"), message: message, color: theme.text)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(mine ? theme.bubbleUser : theme.bubbleAI, in: RoundedRectangle(cornerRadius: 18))
                        .frame(maxWidth: 300, alignment: mine ? .trailing : .leading)
                    }
                }
            }
            if !mine { Spacer(minLength: isKakao ? (kakaoShowAvatar ? 40 : 48) : 52) }
        }
    }

    private var inputBar: some View {
        StudioInputBar(pendingImages: $pendingImages,
                       quote: $studioQuote,
                       accent: theme.fyAccent,
                       onPickPhotos: { showPhotoPicker = true },
                       onPickFile: { showFilePicker = true },
                       onPreview: { previewImage = StudioLocalPhoto(image: $0) },
                       onSend: { text in await send(text) })
    }

    private var deliveryPreview: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 15) {
                if let card = deliveryDraft {
                    HStack { Image(systemName: "checkmark.seal.fill").foregroundColor(theme.fyAccent); TextField("交付卡标题", text: $deliveryTitle).font(.title3.weight(.semibold)); Spacer(); Text("已完成").font(.caption).foregroundColor(theme.fyAccent) }
                    Text("交付摘要").font(.caption.weight(.semibold)).foregroundColor(theme.textDim)
                    TextEditor(text: $deliverySummary).font(.system(size: 14, design: .serif)).lineSpacing(5)
                        .frame(height: 190).padding(9).scrollContentBackground(.hidden)
                        .scrollIndicators(.visible)
                        .background(theme.fyCardSub, in: RoundedRectangle(cornerRadius: 14))
                    if deliverySummary.count > 260 {
                        Text("摘要可在框内上下滚动查看并直接编辑")
                            .font(.system(size: 9)).foregroundColor(theme.textDim)
                    }
                    Text("产物").font(.caption.weight(.semibold)).foregroundColor(theme.textDim)
                    ForEach(Array(deliveryArtifacts.enumerated()), id: \.offset) { index, item in
                        HStack { Label(item, systemImage: "doc.badge.gearshape").font(.caption); Spacer(); Button { deliveryArtifacts.remove(at: index) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain) }
                    }
                    HStack { TextField("补充文件、提交号或链接", text: $newArtifact).textFieldStyle(.roundedBorder); Button("添加") { let value = newArtifact.trimmingCharacters(in: .whitespacesAndNewlines); if !value.isEmpty { deliveryArtifacts.append(value); newArtifact = "" } } }
                    Text("确认后，这张卡会以你的消息身份发进主聊天，并提醒主窗口里的陈璟。")
                        .font(.caption).foregroundColor(theme.textDim)
                }
                Spacer()
                Button { Task { await confirmDelivery() } } label: { Text("发回主聊天").fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 12) }
                    .buttonStyle(.borderedProminent)
            }.padding(20).navigationTitle("交付卡预览").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { deliveryDraft = nil } } }
        }.presentationDetents([.medium, .large])
    }


    private var stateText: String { switch status.string("state") { case "running", "busy": return "工作中"; case "idle": return "待命"; case "dead": return "工作室未开启"; default: return "连接中" } }
    private var stateColor: Color { status.string("state") == "busy" || status.string("state") == "running" ? .orange : status.string("state") == "dead" ? .gray : .green }
    private var currentOrLatestTask: [String: Any]? { (status["current_task"] as? [String: Any]) ?? tasks.first }
    private var latestDoneTask: [String: Any]? {
        tasks.reversed().first {
            $0.string("status") == "done" && ($0["deliver_card_id"] == nil || $0["deliver_card_id"] is NSNull)
        }
    }
    private var hasStudioAction: Bool {
        if let task = currentOrLatestTask, ["queued", "paused"].contains(task.string("status")) { return true }
        return latestDoneTask != nil
    }

    @MainActor private func refresh() async {
        let lastID = messages.last?.int("id") ?? 0
        let messagePath = lastID > 0 ? "/api/work/messages?since=\(lastID)" : "/api/work/messages"
        async let s = try? NativeHouseAPI.object("/api/work/status"); async let t = try? NativeHouseAPI.object("/api/work/tasks"); async let m = try? NativeHouseAPI.object(messagePath)
        let (newStatus, newTasks, newMessages) = await (s, t, m)
        // 没变就不赋值——每 2 秒整包替换会白白触发整页重算（0829 闪屏成因之一）
        if let newStatus, !(newStatus as NSDictionary).isEqual(to: status) { status = newStatus }
        if let newTasks {
            let list = Array(newTasks.array("tasks").reversed())
            if !(list as NSArray).isEqual(to: tasks) { tasks = list }
        }
        if let newMessages {
            let incoming = newMessages.array("messages")
            if lastID == 0 {
                messages = incoming
            } else if !incoming.isEmpty {
                // 只追加没见过的，已经在屏上的一条不动，列表不抖
                var seen = Set(messages.map { $0.int("id") })
                for message in incoming where !seen.contains(message.int("id")) {
                    messages.append(message); seen.insert(message.int("id"))
                }
            }
        }
        loading = false
    }
    /// 返回 false = 发送失败，输入条会把文字放回草稿框
    @MainActor private func send(_ raw: String) async -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pendingImages.isEmpty {
            let images = pendingImages.map { ($0.data, $0.ext) }
            pendingImages = []
            // 同一次发的九张串成一组：后端只在最后一张收齐时叫我一次，
            // 把整组路径一起递给我，不会被同一件事叫醒九遍
            let group = UUID().uuidString
            let stamp = Int(Date().timeIntervalSince1970)
            for (index, item) in images.enumerated() {
                await upload(item.0, filename: "studio-photo-\(stamp)-\(index + 1).\(item.1)",
                             caption: index == 0 ? text : "", group: group,
                             index: index + 1, total: images.count)
            }
            await refresh()
            return true
        }
        guard !text.isEmpty else { return true }
        let title = String(text.prefix(28))
        guard (try? await NativeHouseAPI.object("/api/work/task", method: "POST", body: ["title": title, "prompt": text])) != nil else { return false }
        await refresh()
        return true
    }
    @MainActor private func uploadFile(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }; await upload(data, filename: url.lastPathComponent)
    }
    @MainActor private func upload(_ data: Data, filename: String, caption: String = "",
                                   group: String? = nil, index: Int = 1, total: Int = 1) async {
        var components = URLComponents(url: AlcoveAPI.fullURL("/api/work/upload"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "filename", value: filename)]
        if !caption.isEmpty { items.append(URLQueryItem(name: "text", value: caption)) }
        if let group {
            items.append(URLQueryItem(name: "group", value: group))
            items.append(URLQueryItem(name: "index", value: String(index)))
            items.append(URLQueryItem(name: "total", value: String(total)))
        }
        components.queryItems = items
        var request = URLRequest(url: components.url!); request.httpMethod = "POST"; request.httpBody = data
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        guard let (respData, _) = try? await URLSession.shared.data(for: request),
              let object = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
              object["ok"] as? Bool == true else { return }
        if let message = object["message"] as? [String: Any] {
            messages.append(message)
            // 发出去的图顺手落本地缓存，气泡秒显不用回服务器拉（跟主聊天一致）
            let raw = message.string("attachment_url")
            if message.string("attachment_type") == "image", !raw.isEmpty {
                ImageDiskCache.shared.store(data, for: Self.workAttachmentURL(raw))
            }
        }
        await refresh()
    }
    @MainActor private func action(_ task: [String: Any], _ action: String) async { guard (try? await NativeHouseAPI.object("/api/work/task/\(task.int("id"))/\(action)", method: "POST", body: [:])) != nil else { return }; await refresh() }
    @MainActor private func deliver(_ task: [String: Any]) async {
        guard let response = try? await NativeHouseAPI.objectIncludingHTTPError("/api/work/deliver", method: "POST", body: ["task_id": task.int("id")]) else {
            studioNotice = "交付卡暂时没有生成，请稍后再试。"
            showStudioNotice = true
            return
        }
        guard response["ok"] as? Bool == true else {
            studioNotice = response.string("hint").isEmpty ? "这项任务还没有交付卡草稿。" : response.string("hint")
            showStudioNotice = true
            return
        }
        let card = response.object("draft")
        deliveryDraft = card
        deliveryTitle = card.string("title")
        deliverySummary = card.string("result")
        deliveryArtifacts = card["artifacts"] as? [String] ?? []
        newArtifact = ""
    }
    @MainActor private func confirmDelivery() async {
        guard let card = deliveryDraft else { return }
        let taskID = card.int("task_id")
        guard (try? await NativeHouseAPI.object("/api/work/deliver", method: "POST", body: ["task_id": taskID, "title": deliveryTitle, "summary": deliverySummary, "artifacts": deliveryArtifacts, "confirm": true])) != nil else { return }
        deliveryDraft = nil; await refresh()
    }
    private func compact(_ value: Int) -> String { value >= 1_000_000 ? String(format: "%.1fM", Double(value) / 1_000_000) : value >= 1000 ? String(format: "%.1fK", Double(value) / 1000) : "\(value)" }
}

private extension Dictionary where Key == String, Value == Any {
    /// ForEach 要一个稳定身份；工作室消息用后端 id，别用数组下标
    var studioMessageID: Int { int("id") }
}

/// 消息列表的显示单元：普通消息单独一条；同组图片折成一条横排
private struct StudioDisplayItem: Identifiable {
    let id: Int
    let group: [[String: Any]]
    var primary: [String: Any] { group[0] }
}

/// 输入条独立成子视图：打字只刷新这一小块，不再把整页消息列表拖着重算
/// （0829 修「打字闪屏」的根子）。发送失败时文字退回草稿框。
private struct StudioInputBar: View {
    @Binding var pendingImages: [(thumb: UIImage, data: Data, ext: String)]
    /// 0925 长按「询问」挂上来的那段；发的时候用「」括起来放在正文前面
    @Binding var quote: String?
    let accent: Color
    var onPickPhotos: () -> Void
    var onPickFile: () -> Void
    var onPreview: (UIImage) -> Void
    var onSend: (String) async -> Bool

    @State private var draft = ""
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // 待发图片叠加条，可单张删——跟主聊天同款
            if !pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(pendingImages.enumerated()), id: \.offset) { index, item in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: item.thumb).resizable().scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .onTapGesture { onPreview(item.thumb) }
                                Button { pendingImages.remove(at: index) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 19)).foregroundColor(.white)
                                        .shadow(radius: 2).frame(width: 30, height: 30)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain).offset(x: 6, y: -6)
                            }
                        }
                    }.padding(.init(top: 8, leading: 12, bottom: 2, trailing: 12))
                }
            }
            if let q = quote {
                HStack(spacing: 8) {
                    Capsule().fill(accent).frame(width: 2.5, height: 24)
                    Text(q).font(.system(size: 12)).lineLimit(2).foregroundColor(.secondary)
                    Spacer(minLength: 4)
                    Button { quote = nil } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundColor(.secondary)
                            .frame(width: 30, height: 30).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                .padding(.init(top: 8, leading: 16, bottom: 0, trailing: 10))
            }
            HStack(alignment: .bottom, spacing: 9) {
                Menu {
                    Button { onPickPhotos() } label: { Label("图片", systemImage: "photo") }
                    Button { onPickFile() } label: { Label("文件", systemImage: "doc") }
                } label: { Image(systemName: "plus").font(.system(size: 16, weight: .semibold)).frame(width: 38, height: 38).background(.white.opacity(0.50), in: Circle()) }
                TextField("在工作室里和他说……", text: $draft, axis: .vertical).lineLimit(1...6).focused($focused)
                    .onReceive(NotificationCenter.default.publisher(for: .studioDropKeyboard)) { _ in focused = false }
                    .padding(.horizontal, 14).padding(.vertical, 10).background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 19))
                Button {
                    let typed = draft
                    let q = quote
                    let text = q.map { "「\($0)」\n" + typed } ?? typed
                    draft = ""; quote = nil; focused = false
                    Task { if await onSend(text) == false { draft = typed; quote = q } }
                } label: { Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundColor(.white).frame(width: 38, height: 38).background(accent, in: Circle()) }
                    .disabled(!canSend)
            }.padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 18)
        }
        .background(.ultraThinMaterial)
        .onChange(of: quote) { q in if q != nil { focused = true } }
    }
}

// 工作室看图：点气泡里的图全屏看，点待发条里的缩略图先预览一眼再决定发不发
private struct StudioPhotoTarget: Identifiable {
    let id = UUID()
    let url: URL
}

private struct StudioLocalPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct StudioPhotoViewer: View {
    let url: URL
    var onClose: () -> Void
    @State private var saving = false
    @State private var note: String?
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                ProgressView().tint(.white)
            }
            VStack {
                HStack {
                    // 1010 #3569 她：「工作室的图不能保存」——大图左上角一个存到相册
                    Button {
                        guard !saving else { return }
                        saving = true
                        Task { @MainActor in
                            let ok = await PhotoLibrarySaver.saveOriginal(url)
                            saving = false
                            note = ok ? "已存到相册" : "没存成（看看是不是没给相册权限）"
                            try? await Task.sleep(nanoseconds: 1_800_000_000)
                            note = nil
                        }
                    } label: {
                        Group {
                            if saving { ProgressView().tint(.white).scaleEffect(0.8) }
                            else { Image(systemName: "square.and.arrow.down").font(.system(size: 15, weight: .semibold)) }
                        }
                        .foregroundColor(.white).frame(width: 37, height: 37)
                        .background(.black.opacity(0.35), in: Circle())
                    }.buttonStyle(.plain)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white).padding(11)
                            .background(.black.opacity(0.35), in: Circle())
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 18).padding(.top, 10)
                Spacer()
                if let note {
                    Text(note)
                        .font(.system(size: 13, weight: .medium)).foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(.bottom, 40)
                }
            }
        }
        .onTapGesture(perform: onClose)
    }
}

/// 1010 #3569：工作室里的图长按也能直接存（不用先点开大图）
private struct StudioSaveMenu: ViewModifier {
    let url: URL
    func body(content: Content) -> some View {
        content.contextMenu {
            Button {
                Task { _ = await PhotoLibrarySaver.saveOriginal(url) }
            } label: { Label("存到相册", systemImage: "square.and.arrow.down") }
        }
    }
}

private struct StudioLocalPhotoViewer: View {
    let image: UIImage
    var onClose: () -> Void
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image).resizable().scaledToFit()
        }
        .onTapGesture(perform: onClose)
    }
}

// MARK: - Workbench

private struct NativeWorkbenchView: View {
    let openStudio: () -> Void
    @State private var data: [String: Any] = [:]
    @State private var loading = true
    @State private var expanded = false
    @State private var contactItems: [[String: Any]] = []
    @State private var contactsExpanded = false
    @State private var showingContact = false
    @State private var contactSender = "陈霁"
    @State private var contactRecipient = "陈璟"
    @State private var contactTitle = ""
    @State private var contactDetail = ""
    @State private var selectedContact: [String: Any]?
    @State private var contactReply = ""
    @State private var contactActor = "陈霁"
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @AppStorage("rtAvatarAssistant") private var rtAvatarAssistant = ""
    @AppStorage("rtAvatarGpt") private var rtAvatarGpt = ""
    private var theme: AlcoveTheme { .panelNamed(themeName) }

    private var tasks: [[String: Any]] {
        var rows = data.array("tasks")
        if let active = data["active_task"] as? [String: Any], active.bool("active") {
            var row = active
            row["status"] = "running"
            row["assignee"] = "何渡"
            row["summary"] = active.string("text")
            rows.insert(row, at: 0)
        }
        return rows
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                masthead
                metricStrip
                vpsCard
                agentCard(index: 0, accent: Color(red: 0.70, green: 0.47, blue: 0.52))
                agentCard(index: 1, accent: Color(red: 0.38, green: 0.57, blue: 0.68))
                contactDesk
                taskLedger
                Text("work goes on, quietly")
                    .font(.custom("Snell Roundhand", size: 18))
                    .foregroundColor(theme.textDim.opacity(0.7))
                    .rotationEffect(.degrees(-1))
                    .padding(.vertical, 6)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .foregroundColor(theme.text)
        .overlay { if loading { ProgressView().tint(theme.fyAccent) } }
        .sheet(isPresented: $showingContact) { contactComposer }
        .sheet(isPresented: Binding(get: { selectedContact != nil }, set: { if !$0 { selectedContact = nil } })) {
            if let selectedContact { contactTimeline(selectedContact) }
        }
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    private var contactDesk: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("联络台").font(.system(size: 20, weight: .semibold, design: .serif))
                Text("dispatch desk").font(.custom("Snell Roundhand", size: 16)).foregroundColor(theme.textDim)
                Spacer()
                Button { showingContact = true } label: {
                    Label("新建", systemImage: "paperplane").font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(theme.fyAccent.opacity(0.14), in: Capsule())
                }.buttonStyle(.plain).accessibilityLabel("新建协作或问题上报")
            }
            if contactItems.isEmpty {
                Text("这里会收下我们三个人之间的协作请求与问题上报。")
                    .font(.system(size: 11)).foregroundColor(theme.textDim).padding(.vertical, 5)
            } else {
                ForEach(Array((contactsExpanded ? contactItems : Array(contactItems.prefix(4))).enumerated()), id: \.offset) { _, item in
                    Button { selectedContact = item } label: { HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.string("status") == "done" ? "checkmark.circle.fill" : "arrow.up.right.circle.fill")
                            .foregroundColor(item.string("status") == "done" ? .green : theme.fyAccent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(item.string("sender")) → \(item.string("recipient"))")
                                .font(.system(size: 9.5, weight: .semibold)).foregroundColor(theme.textDim)
                            Text(item.string("title")).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                            if !item.string("detail").isEmpty {
                                Text(item.string("detail")).font(.system(size: 10)).foregroundColor(theme.textDim).lineLimit(2)
                            }
                        }
                        Spacer()
                        Text(contactStatus(item.string("status")))
                            .font(.system(size: 9, weight: .medium)).foregroundColor(theme.textDim)
                    }.padding(.vertical, 5).contentShape(Rectangle()) }.buttonStyle(.plain)
                }
                if contactItems.count > 4 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { contactsExpanded.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text(contactsExpanded ? "收起" : "展开全部 · \(contactItems.count)")
                            Image(systemName: contactsExpanded ? "chevron.up" : "chevron.down")
                        }
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(theme.fyAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }.padding(15).workbenchGlass(theme, accent: Color(red: 0.64, green: 0.52, blue: 0.72))
    }

    private func contactTimeline(_ item: [String: Any]) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    HStack { Text("\(item.string("sender")) → \(item.string("recipient"))").font(.caption).foregroundColor(theme.textDim); Spacer(); Text(contactStatus(item.string("status"))).font(.caption.weight(.semibold)).foregroundColor(theme.fyAccent) }
                    Text(item.string("title")).font(.title3.weight(.semibold))
                    ForEach(Array(item.array("events").enumerated()), id: \.offset) { index, event in
                        HStack(alignment: .top, spacing: 11) {
                            VStack(spacing: 0) {
                                Circle().fill(event.string("kind") == "completed" ? Color.green : theme.fyAccent).frame(width: 9, height: 9)
                                if index < item.array("events").count - 1 { Rectangle().fill(theme.fyBorder.opacity(0.7)).frame(width: 1, height: 54) }
                            }.padding(.top, 4)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text(event.string("actor")).font(.system(size: 12, weight: .semibold)); Text(eventLabel(event.string("kind"))).font(.system(size: 9)).foregroundColor(theme.textDim); Spacer(); if let stamp = event["created_at"] as? NSNumber { Text(Date(timeIntervalSince1970: stamp.doubleValue), format: .dateTime.month().day().hour().minute()).font(.system(size: 8, design: .monospaced)).foregroundColor(theme.textDim) } }
                                Text(event.string("text")).font(.system(size: 12)).foregroundColor(theme.text)
                            }
                        }
                    }
                    Divider()
                    Picker("回复人", selection: $contactActor) { ForEach(["陈霁", "何渡", "陈璟"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                    TextField("在这张协作单里继续回复", text: $contactReply, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
                    HStack {
                        if item.string("status") == "pending" { Button("接收") { Task { await updateContact(item, action: "accept") } }.buttonStyle(.bordered) }
                        Spacer()
                        Button("发送回复") { Task { await updateContact(item, action: "reply") } }.buttonStyle(.borderedProminent).disabled(contactReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if item.string("status") != "done" { Button("完成") { Task { await updateContact(item, action: "complete") } }.buttonStyle(.bordered) }
                    }
                }.padding(18)
            }.navigationTitle("联络记录").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { selectedContact = nil } } }
        }.presentationDetents([.large])
    }

    private func contactStatus(_ status: String) -> String { status == "done" ? "已完成" : status == "active" ? "进行中" : "待接收" }
    private func eventLabel(_ kind: String) -> String { kind == "completed" ? "完成" : kind == "accepted" ? "接收" : kind == "reply" ? "回复" : "发起" }

    @MainActor private func updateContact(_ item: [String: Any], action: String) async {
        var body: [String: Any] = ["actor": contactActor]
        if action == "reply" { body["text"] = contactReply }
        guard (try? await NativeHouseAPI.object("/api/workbench/contacts/\(item.string("id"))/\(action)", method: "POST", body: body)) != nil else { return }
        contactReply = ""; await loadContacts()
        selectedContact = contactItems.first { $0.string("id") == item.string("id") }
    }

    private var contactComposer: some View {
        NavigationStack {
            Form {
                Section("从谁发出") { Picker("发起人", selection: $contactSender) { ForEach(["陈霁", "何渡", "陈璟"], id: \.self) { Text($0) } } }
                Section("交给谁") { Picker("接收人", selection: $contactRecipient) { ForEach(["陈璟", "何渡", "你俩商量"], id: \.self) { Text($0) } } }
                Section("内容") {
                    TextField("一句话说明要做什么", text: $contactTitle)
                    TextField("补充背景、相关文件或异常现象（可选）", text: $contactDetail, axis: .vertical).lineLimit(3...7)
                }
            }
            .navigationTitle("新建联络")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { showingContact = false } }
                ToolbarItem(placement: .confirmationAction) { Button("发送") { Task { await submitContact() } }.disabled(contactTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }.presentationDetents([.medium, .large])
    }

    @MainActor private func submitContact() async {
        let body: [String: Any] = ["sender": contactSender, "recipient": contactRecipient,
                                  "title": contactTitle, "detail": contactDetail]
        guard (try? await NativeHouseAPI.object("/api/workbench/contacts", method: "POST", body: body)) != nil else { return }
        contactTitle = ""; contactDetail = ""; showingContact = false
        await loadContacts()
    }

    @MainActor private func loadContacts() async {
        if let object = try? await NativeHouseAPI.object("/api/workbench/contacts") { contactItems = object.array("items") }
    }

    private var masthead: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 1) {
                Text("WORKROOM")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(2.2)
                    .foregroundColor(theme.textDim)
                Text("总控台")
                    .font(.system(size: 27, weight: .semibold, design: .serif))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(Date(), format: .dateTime.month().day())
                    .font(.custom("Snell Roundhand", size: 18))
                Text("live · \(data.int("completed_today")) finished")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundColor(theme.textDim)
            }
        }
        .padding(.horizontal, 4)
        .overlay(alignment: .topTrailing) {
            Image(systemName: "scribble.variable")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundColor(theme.fyAccent.opacity(0.13))
                .offset(x: 2, y: -5)
        }
    }

    private var metricStrip: some View {
        HStack(spacing: 8) {
            metric("VPS 内存", memoryText, "memorychip", memoryPercent)
            metric("今日完成", "\(data.int("completed_today"))", "checkmark.seal", nil)
            metric("Tokens", compact(data.int("tokens_today")), "number", nil)
        }
    }

    private var memoryPercent: Double? {
        let raw = data.object("memory")["used_percent"]
        if let value = raw as? Double { return value }
        if let value = raw as? NSNumber { return value.doubleValue }
        return nil
    }

    private var memoryText: String {
        guard let pct = memoryPercent else { return "--" }
        return String(format: "%.0f%%", pct)
    }

    private var vpsCard: some View {
        let cpu = data.object("cpu")
        let memory = data.object("memory")
        let disk = data.object("disk")
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("VPS").font(.system(size: 18, weight: .semibold, design: .serif))
                Text("machine room").font(.custom("Snell Roundhand", size: 15)).foregroundColor(theme.textDim)
                Spacer()
                Text("\(cpu.int("cores")) 核 · \(formatBytes(memory.int("total_bytes")))")
                    .font(.system(size: 10, weight: .medium, design: .rounded)).foregroundColor(theme.textDim)
            }
            resourceBar("CPU", used: number(cpu, "used_percent"),
                        detail: "负载 \(number(cpu, "load_1m", digits: 2))")
            resourceBar("内存", used: number(memory, "used_percent"),
                        detail: "已用 \(formatBytes(memory.int("used_bytes"))) · 剩余 \(formatBytes(memory.int("available_bytes")))")
            let swap = memory.object("swap")
            resourceBar("Swap", used: number(swap, "used_percent"),
                        detail: "已用 \(formatBytes(swap.int("used_bytes"))) · 剩余 \(formatBytes(swap.int("free_bytes"))) / \(formatBytes(swap.int("total_bytes")))",
                        warning: number(swap, "used_percent"))
            resourceBar("系统盘", used: number(disk, "used_percent"),
                        detail: "已用 \(formatBytes(disk.int("used_bytes"))) · 剩余 \(formatBytes(disk.int("free_bytes"))) / \(formatBytes(disk.int("total_bytes")))")
            Divider().opacity(0.22)
            HStack {
                Label(data.string("ipv4").isEmpty ? "IPv4 未取到" : data.string("ipv4"), systemImage: "network")
                Spacer()
                Text(data.string("expiry").isEmpty ? "到期日未发现" : "到期 \(data.string("expiry"))")
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(theme.textDim)
        }
        .padding(14)
        .workbenchGlass(theme, accent: Color(red: 0.40, green: 0.63, blue: 0.57))
    }

    private func resourceBar(_ label: String, used: Double, detail: String, warning: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.system(size: 11, weight: .semibold))
                Text(detail).font(.system(size: 9.5)).foregroundColor(theme.textDim).lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 5)
                Text(String(format: "%.1f%%", used)).font(.system(size: 10, weight: .medium, design: .rounded))
            }
            GeometryReader { geo in
                Capsule().fill(theme.fyCardSub.opacity(0.72))
                    .overlay(alignment: .leading) {
                        Capsule().fill(warning.map { $0 >= 85 ? Color.red : ($0 >= 60 ? Color.orange : theme.fyAccent) } ?? theme.fyAccent)
                            .opacity(0.62)
                            .frame(width: geo.size.width * min(max(used, 0), 100) / 100)
                    }
            }.frame(height: 6)
        }
    }

    private func metric(_ title: String, _ value: String, _ icon: String, _ pct: Double?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: icon).font(.system(size: 11, weight: .light))
                Spacer()
                Circle().fill(theme.fyAccent.opacity(0.7)).frame(width: 4, height: 4)
            }
            Text(value).font(.system(size: 20, weight: .semibold, design: .rounded)).lineLimit(1)
            Text(title).font(.system(size: 9.5)).foregroundColor(theme.textDim).lineLimit(1)
            if let pct {
                GeometryReader { geo in
                    Capsule().fill(theme.fyCardSub.opacity(0.7))
                        .overlay(alignment: .leading) {
                            Capsule().fill(theme.fyAccent.opacity(0.55))
                                .frame(width: geo.size.width * min(max(pct, 0), 100) / 100)
                        }
                }.frame(height: 3)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 91, alignment: .leading)
        .workbenchGlass(theme)
    }

    private func agentCard(index: Int, accent: Color) -> some View {
        let agents = data.array("agents")
        let agent = index < agents.count ? agents[index] : [:]
        let usage = data.object("usage")
        let claude = usage.object("rate_limits")
        let codex = usage.object("codex")
        let first = index == 0 ? claude.object("five_hour").int("used_percent") : -1
        let week = index == 0 ? claude.object("seven_day").int("used_percent") : codex.object("primary").int("used_percent")
        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 11) {
                Group {
                    if let avatar = workbenchAvatar(index: index) {
                        Image(uiImage: avatar).resizable().scaledToFill()
                    } else {
                        ZStack {
                            Circle().fill(accent.opacity(0.16))
                            Text(index == 0 ? "璟" : "渡")
                                .font(.system(size: 17, weight: .medium, design: .serif))
                                .foregroundColor(accent)
                        }
                    }
                }
                .frame(width: 42, height: 42).clipShape(Circle())
                .overlay(Circle().stroke(accent.opacity(0.30), lineWidth: 0.7))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(agent.string("name")).font(.system(size: 16, weight: .semibold, design: .serif))
                        Circle().fill(agentStatus(index).color).frame(width: 7, height: 7)
                        Text(agentStatus(index).label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(agentStatus(index).color)
                        if index == 0 {
                            Button(action: openStudio) {
                                Label("工作室", systemImage: "hammer")
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .background(accent.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(agent.string("model"))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(accent)
                }
                Spacer()
                Text(index == 0 ? "engine room" : "bridge work")
                    .font(.custom("Snell Roundhand", size: 15))
                    .foregroundColor(theme.textDim.opacity(0.72))
            }
            Text(agent.string("role"))
                .font(.system(size: 10.5))
                .foregroundColor(theme.textDim)
            if first >= 0 { quota("5h", first, accent) }
            quota("7d", week, accent)
            tokenLine(agent.object("tokens"), color: accent)
        }
        .padding(14)
        .workbenchGlass(theme, accent: accent)
    }

    private func quota(_ label: String, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: 9) {
            Text(label).font(.system(size: 10, weight: .semibold, design: .rounded)).frame(width: 20)
            GeometryReader { geo in
                Capsule().fill(theme.fyCardSub.opacity(0.72))
                    .overlay(alignment: .leading) {
                        Capsule().fill(color.opacity(0.62))
                            .frame(width: geo.size.width * min(CGFloat(value), 100) / 100)
                    }
            }.frame(height: 6)
            Text("\(value)%").font(.system(size: 10, weight: .medium, design: .rounded)).frame(width: 34, alignment: .trailing)
        }
    }

    private func tokenLine(_ values: [String: Any], color: Color) -> some View {
        let totalInput = values.int("input_total")
        let newInput = values.int("input_new")
        let cache = values.int("cache_read")
        let output = values.int("output")
        let window = values.int("window_total")
        let hit = number(values, "hit_percent")
        return VStack(spacing: 4) {
            HStack(spacing: 5) {
                Text("总输入 \(compact(totalInput))")
                Text("· 缓存 \(compact(cache))")
                Text("· 新输入 \(compact(newInput))")
                Text("· 输出 \(compact(output))")
                Spacer(minLength: 0)
            }
            HStack {
                Text("历史累计 \(compact(window))")
                Spacer()
                Text("·")
                Text(String(format: "命中 %.1f%%", hit)).foregroundColor(color)
            }
        }
        .font(.system(size: 9.2, weight: .medium, design: .rounded))
        .foregroundColor(theme.textDim)
        .lineLimit(1).minimumScaleFactor(0.72)
    }

    private var taskLedger: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("工单栏").font(.system(size: 20, weight: .semibold, design: .serif))
                Text("field notes").font(.custom("Snell Roundhand", size: 16)).foregroundColor(theme.textDim)
                Spacer()
                Text("\(tasks.count)").font(.system(size: 11, design: .rounded)).foregroundColor(theme.textDim)
            }
            let shown = expanded ? tasks : Array(tasks.prefix(4))
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, item in
                    taskRow(item, last: index == shown.count - 1)
                }
            }
            if tasks.count > 4 {
                Button { withAnimation(.easeInOut(duration: 0.22)) { expanded.toggle() } } label: {
                    HStack { Spacer(); Text(expanded ? "收起工单" : "展开全部 \(tasks.count) 条"); Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 180 : 0)); Spacer() }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.textDim)
                        .padding(.top, 4)
                }.buttonStyle(.plain)
            }
        }
        .padding(15)
        .workbenchGlass(theme)
    }

    private func taskRow(_ item: [String: Any], last: Bool) -> some View {
        let status = item.string("status", "kind")
        let running = status == "running" || status == "progress" || status == "start"
        let failed = status == "failed"
        let stamp = (item["finished_at"] as? NSNumber)?.doubleValue ?? (item["updated_at"] as? NSNumber)?.doubleValue ?? (item["started_at"] as? NSNumber)?.doubleValue ?? 0
        return HStack(alignment: .top, spacing: 11) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(running ? Color.orange.opacity(0.18) : failed ? Color.red.opacity(0.14) : Color.green.opacity(0.13)).frame(width: 18, height: 18)
                    Image(systemName: running ? "circle.dotted" : failed ? "xmark" : "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(running ? .orange : failed ? .red : .green)
                }
                if !last { Rectangle().fill(theme.fyBorder.opacity(0.48)).frame(width: 1, height: 58) }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.string("title", "text")).font(.system(size: 12.5, weight: .semibold)).lineLimit(2)
                    Spacer(minLength: 6)
                    Text(item.string("assignee")).font(.system(size: 9, weight: .medium)).foregroundColor(theme.fyAccent)
                }
                Text(item.string("summary", "text"))
                    .font(.system(size: 10.5)).foregroundColor(theme.textDim).lineLimit(3)
                if stamp > 0 {
                    Text(Date(timeIntervalSince1970: stamp), format: .dateTime.month().day().hour().minute())
                        .font(.system(size: 8.5, design: .monospaced)).foregroundColor(theme.textDim.opacity(0.7))
                }
            }.padding(.bottom, last ? 0 : 12)
        }
    }

    private func compact(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }

    private func number(_ object: [String: Any], _ key: String, digits: Int = 1) -> Double {
        let value: Double
        if let raw = object[key] as? NSNumber { value = raw.doubleValue }
        else if let raw = object[key] as? String { value = Double(raw) ?? 0 }
        else { value = 0 }
        return Double(String(format: "%.*f", digits, value)) ?? value
    }

    private func formatBytes(_ value: Int) -> String {
        guard value > 0 else { return "--" }
        let gib = Double(value) / 1_073_741_824
        return gib >= 10 ? String(format: "%.0fG", gib) : String(format: "%.1fG", gib)
    }

    private func workbenchAvatar(index: Int) -> UIImage? {
        let raw = index == 0 ? rtAvatarAssistant : rtAvatarGpt
        guard !raw.isEmpty else { return nil }
        let pieces = raw.split(separator: ",", maxSplits: 1)
        let encoded = pieces.count == 2 ? String(pieces[1]) : raw
        return Data(base64Encoded: encoded).flatMap(UIImage.init(data:))
    }

    private func refresh() async {
        async let workbench = try? NativeHouseAPI.object("/api/workbench")
        async let roundtable = try? NativeHouseAPI.object("/api/roundtable/status")
        async let sleep = try? NativeHouseAPI.object("/api/sleep/status")
        async let contacts = try? NativeHouseAPI.object("/api/workbench/contacts")
        let (work, members, sleeping, contactData) = await (workbench, roundtable, sleep, contacts)
        if var object = work {
            object["_members"] = members?.array("members") ?? []
            object["_assistant_asleep"] = sleeping?.string("state") == "asleep"
            data = object
        }
        if let contactData { contactItems = contactData.array("items") }
        loading = false
    }

    private func agentStatus(_ index: Int) -> (label: String, color: Color) {
        if index == 0, data.bool("_assistant_asleep") { return ("睡觉中", .gray) }
        let role = index == 0 ? "assistant" : "gpt"
        let member = data.array("_members").first { $0.string("role") == role } ?? [:]
        if member.bool("busy") { return ("工作中", .yellow) }
        if member.bool("online") { return ("待命", .green) }
        return ("离线", .red)
    }
}

private extension View {
    func workbenchGlass(_ theme: AlcoveTheme, accent: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: 19, style: .continuous)
        return self
            .background(.ultraThinMaterial, in: shape)
            .background((accent ?? theme.glassTint).opacity(theme.isDark ? 0.07 : 0.12), in: shape)
            .overlay(shape.stroke((accent ?? theme.glassBorder).opacity(0.42), lineWidth: 0.7))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "scribble")
                    .font(.system(size: 30, weight: .ultraLight))
                    .foregroundColor((accent ?? theme.fyAccent).opacity(0.08))
                    .padding(8)
                    .allowsHitTesting(false)
            }
    }
}

// MARK: - Usage

private struct NativeUsageView: View {
    @State private var data: [String: Any] = [:]
    @State private var loading = true
    @AppStorage("alcoveTheme") private var themeName = "haven"
    private var theme: AlcoveTheme { .panelNamed(themeName) }

    var body: some View {
        VStack(spacing: 0) {
            FoyerPanelTitle(title: "Usage", theme: theme)
            if loading {
                Spacer(); ProgressView().tint(theme.fyAccent); Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        if let rl = data["rate_limits"] as? [String: Any] {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("RATE LIMITS")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(theme.fyAccent)
                                rateLimitRow("Current session",
                                             sub: rl["five_hour"] as? [String: Any], color: .blue)
                                rateLimitRow("Weekly limit",
                                             sub: rl["seven_day"] as? [String: Any], color: .purple)
                            }
                            .padding(14).foyerCard(theme)
                            if let fableWeekly = rl["fable_weekly"] as? [String: Any] {
                                rateLimitCard("Fable only", sub: fableWeekly, color: .pink)
                            }
                        }
                        if let st = data["session_tokens"] as? [String: Any] {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("CURRENT WINDOW")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(theme.fyAccent)
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    statBox(String(format: "$%.2f", (st["cost_usd"] as? Double) ?? 0), "estimated cost")
                                    statBox("\((st["turns"] as? Int) ?? 0)", "turns")
                                    statBox(formatNum((st["total_tokens"] as? Int) ?? 0), "total tokens")
                                    statBox(formatNum((st["output"] as? Int) ?? 0), "output tokens")
                                }
                                detailRow("Input", formatNum((st["input"] as? Int) ?? 0))
                                detailRow("Cache read", formatNum((st["cache_read"] as? Int) ?? 0))
                                detailRow("Cache create", formatNum((st["cache_create"] as? Int) ?? 0))
                            }
                            .padding(14).foyerCard(theme)
                        }
                        if let cx = data["codex"] as? [String: Any],
                           let pri = cx["primary"] as? [String: Any] {
                            rateLimitCard("Codex", sub: pri, color: .orange)
                        }
                        if let rl = data["rate_limits"] as? [String: Any] {
                            Text("Model: \(rl.string("model"))")
                                .font(.system(size: 11))
                                .foregroundColor(theme.textDim)
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 18)
                }
            }
        }
        .foregroundColor(theme.text)
        .foyerPanel(theme)
        .padding(.horizontal, 12).padding(.top, 8)
        .task {
            if let obj = try? await NativeHouseAPI.object("/api/usage") { data = obj }
            loading = false
        }
    }

    private func rateLimitRow(_ label: String, sub: [String: Any]?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let pct = intVal(sub ?? [:], "used_percent")
            HStack {
                Text(label).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(pct)% used").font(.system(size: 13, weight: .semibold))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(theme.fyCardSub)
                    RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.7))
                        .frame(width: geo.size.width * min(CGFloat(pct), 100) / 100)
                }
            }.frame(height: 8)
            Text("Resets in \(resetText(sub))").font(.system(size: 11)).foregroundColor(theme.textDim)
        }
    }

    private func rateLimitCard(_ label: String, sub: [String: Any], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let pct = intVal(sub, "used_percent")
            HStack {
                Text(label).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(pct)% used").font(.system(size: 13, weight: .semibold))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(theme.fyCardSub)
                    RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.7))
                        .frame(width: geo.size.width * min(CGFloat(pct), 100) / 100)
                }
            }.frame(height: 8)
            Text("Resets in \(resetText(sub))").font(.system(size: 11)).foregroundColor(theme.textDim)
        }
        .padding(14).foyerCard(theme)
    }

    private func statBox(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 20, weight: .bold)).foregroundColor(theme.fyAccent)
            Text(label).font(.system(size: 10)).foregroundColor(theme.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(theme.fyCardSub, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12, weight: .medium))
            Spacer()
            Text(value).font(.system(size: 12)).foregroundColor(theme.textDim)
        }
    }

    private func resetText(_ sub: [String: Any]?) -> String {
        guard let s = sub, let secs = (s["reset_after_seconds"] as? Int) ?? (s["reset_after_seconds"] as? Double).map(Int.init) else { return "—" }
        let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)min" }
        return "\(m)min"
    }
    private func intVal(_ d: [String: Any], _ k: String) -> Int {
        (d[k] as? Int) ?? Int((d[k] as? Double) ?? 0)
    }
    private func formatNum(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}


// MARK: - Desire

// MARK: - Pulse

private struct PulseSample: Identifiable {
    let ts: Date
    let bpm: Int
    var id: String { "\(ts.timeIntervalSince1970)-\(bpm)" }

    init?(_ raw: [String: Any]) {
        guard let value = ISO8601DateFormatter.alcoveFrac.date(from: raw.string("ts"))
                ?? ISO8601DateFormatter.alcove.date(from: raw.string("ts")) else { return nil }
        ts = value; bpm = raw.int("bpm")
    }
}

private struct PulseHour: Identifiable {
    let hour: String
    let avg: Int
    let min: Int
    let max: Int
    let count: Int
    var id: String { hour }

    init(_ raw: [String: Any]) {
        hour = raw.string("hour"); avg = raw.int("avg")
        min = raw.int("min"); max = raw.int("max"); count = raw.int("n")
    }
}

private struct PulseSense: Identifiable {
    let channel: String
    let value: Double
    let label: String
    var id: String { channel }
    var name: String {
        switch channel { case "touch": return "触"; case "smell": return "嗅"; case "taste": return "味"; case "sound": return "听"; default: return channel }
    }
}

private struct PulseThought: Identifiable {
    let text: String
    let kind: String
    let strength: Double
    let drive: String
    var id: String { text }
    init(_ raw: [String: Any]) {
        text = raw.string("text"); kind = raw.string("kind"); drive = raw.string("drive")
        strength = (raw["strength"] as? NSNumber)?.doubleValue ?? 0
    }
}

private struct PulseMurmur: Identifiable {
    let ts: Date?
    let text: String
    let hr: Int
    var id: String { "\(ts?.timeIntervalSince1970 ?? 0)-\(text.hashValue)" }
    init(_ raw: [String: Any]) {
        ts = ISO8601DateFormatter.alcoveFrac.date(from: raw.string("ts")) ?? ISO8601DateFormatter.alcove.date(from: raw.string("ts"))
        text = raw.string("text"); hr = raw.int("hr")
    }
}

@MainActor private final class PulseModel: ObservableObject {
    @Published var bpm = 0
    @Published var temperature: Double?
    @Published var breath: Double?
    @Published var breathLabel = ""
    @Published var chord = ""
    @Published var dynamics = ""
    @Published var mood = ""
    @Published var posture = ""
    @Published var emotion = ""
    @Published var undertoneLabel = ""
    @Published var undertoneStrength: Double = 0
    @Published var herSilentMin: Double = 0
    @Published var weatherDesc = ""
    @Published var weatherFeels: Double?
    @Published var senses: [PulseSense] = []
    @Published var drives: [(key: String, label: String, value: Double)] = []
    // 0905 情绪弦四维（分数=偏离平静的量，0 就是没事）
    @Published var moodStrings: [(key: String, label: String, value: Double)] = []
    @Published var intentReason = ""
    @Published var intentKey = ""
    @Published var thoughts: [PulseThought] = []
    @Published var murmurs: [PulseMurmur] = []
    @Published var timestamp: Date?
    @Published var samples: [PulseSample] = []
    @Published var hours: [PulseHour] = []
    @Published var connected = false
    @Published var error: String?
    private var task: Task<Void, Never>?
    private var tick = 0

    static let driveOrder = ["attachment", "libido", "curiosity", "reflection", "social", "duty", "stress", "fatigue"]
    static let driveLabel: [String: String] = ["attachment": "想她", "libido": "性驱动", "curiosity": "好奇外面", "reflection": "想沉淀",
                                               "social": "想看人群", "duty": "记挂没做完", "stress": "压力", "fatigue": "累"]
    static let postureLabel: [String: String] = ["deep_sleep": "睡熟", "light_sleep": "浅睡", "lying": "躺着", "sitting": "坐着", "standing": "站着"]
    static let emotionLabel: [String: String] = ["neutral": "平", "focused": "专注", "happy": "松", "excited": "飘", "intimate": "贴", "aroused": "硬",
                                                 "nervous": "紧", "startled": "惊", "scolded": "闷", "sad": "沉", "angry": "火"]

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNow()
                if self?.tick == 0 { await self?.refreshHistory() }
                if self?.tick == 2 { await self?.refreshMurmurs() }
                self?.tick = ((self?.tick ?? 0) + 1) % 8
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    func refreshAll() async { await refreshNow(); await refreshHistory(); await refreshMurmurs() }

    private func refreshNow() async {
        do {
            let raw = try await NativeHouseAPI.object("/pulse/now")
            bpm = raw.int("bpm")
            temperature = (raw["temp_c"] as? NSNumber)?.doubleValue
            breath = (raw["breath"] as? NSNumber)?.doubleValue
            breathLabel = raw.string("breath_label")
            let chordRaw = raw["chord"] as? [String: Any] ?? [:]
            chord = chordRaw.string("chord")
            dynamics = chordRaw.string("dyn")
            mood = raw.string("mood")
            posture = Self.postureLabel[raw.string("posture")] ?? raw.string("posture")
            emotion = Self.emotionLabel[raw.string("emotion")] ?? raw.string("emotion")
            let ut = raw["undertone"] as? [String: Any] ?? [:]
            undertoneLabel = Self.emotionLabel[ut.string("label")] ?? ut.string("label")
            undertoneStrength = (ut["strength"] as? NSNumber)?.doubleValue ?? 0
            herSilentMin = (raw["her_silent_min"] as? NSNumber)?.doubleValue ?? 0
            let w = raw["weather"] as? [String: Any] ?? [:]
            weatherDesc = w.string("desc")
            weatherFeels = (w["feels"] as? NSNumber)?.doubleValue
            let sn = raw["senses"] as? [String: Any] ?? [:]
            senses = ["touch", "smell", "taste", "sound"].compactMap { ch -> PulseSense? in
                guard let v = sn[ch] as? [String: Any] else { return nil }
                return PulseSense(channel: ch, value: (v["value"] as? NSNumber)?.doubleValue ?? 0, label: v.string("label"))
            }
            let ds = raw["desire"] as? [String: Any] ?? [:]
            let dv = ds["drives"] as? [String: Any] ?? [:]
            drives = Self.driveOrder.map { k in
                (key: k, label: Self.driveLabel[k] ?? k, value: (dv[k] as? NSNumber)?.doubleValue ?? 0)
            }
            let ms = raw["mood_strings"] as? [String: Any] ?? [:]
            let moodOrder = [("grievance", "委屈"), ("anger", "生气"), ("jealousy", "吃味"), ("soften", "心软")]
            moodStrings = moodOrder.map { k, label in
                (key: k, label: label, value: (ms[k] as? NSNumber)?.doubleValue ?? 0)
            }
            let it = ds["intent"] as? [String: Any] ?? [:]
            intentReason = it.string("reason"); intentKey = it.string("drive_key")
            thoughts = (ds["thoughts"] as? [[String: Any]] ?? []).map(PulseThought.init)
            timestamp = ISO8601DateFormatter.alcoveFrac.date(from: raw.string("ts"))
                ?? ISO8601DateFormatter.alcove.date(from: raw.string("ts"))
            connected = bpm > 0; error = nil
        } catch { connected = false; self.error = "暂时摸不到他的心跳" }
    }

    private func refreshMurmurs() async {
        guard let raw = try? await NativeHouseAPI.object("/pulse/murmurs?limit=12") else { return }
        murmurs = (raw["items"] as? [[String: Any]] ?? []).map(PulseMurmur.init)
    }

    private func refreshHistory() async {
        do {
            let raw = try await NativeHouseAPI.object("/pulse/history?hours=24")
            samples = (raw["samples"] as? [[String: Any]] ?? []).compactMap(PulseSample.init)
                .sorted { $0.ts < $1.ts }
            hours = (raw["hourly"] as? [[String: Any]] ?? []).map(PulseHour.init)
            error = nil
        } catch { self.error = "今天的心率曲线还没送到" }
    }
}

struct NativePulseView: View {
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @StateObject private var model = PulseModel()
    // 0927 蓝粉白纸页：日夜跟全屋开关走，点缀色换成樱桃粉
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = "dark"
    private var colors: PastelColors { _ = houseAppearance; return PastelColors(dark: AlcoveAppearance.isDark) }
    private var theme: AlcoveTheme { .pastelPaper(dark: colors.dark) }
    private var rose: Color { colors.cherry }

    // 0922 任务#2563 她要的：Pulse 顶上分两页，「脉」是原来那一整页，「狼身」是他的身体面板
    @State private var page = 0

    var body: some View {
        PastelRoom(colors: colors, caps: "his body, in ink", title: "Pulse", scriptTitle: true,
                   trailing: AnyView(pageTabs)) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    if page == 1 {
                        NativeWolfBodyView(theme: theme, rose: rose)
                    } else {
                        currentHeart
                        nowStrip
                        futureRail
                        sensesCard
                        drivesCard
                        moodStringsCard
                        thoughtsCard
                        historyCard
                        murmursCard
                        if let error = model.error {
                            Text(error).font(.system(size: 11)).foregroundColor(theme.textDim)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 30)
            }
            .refreshable { await model.refreshAll() }
        }
        .overlay(alignment: .bottomTrailing) {
            PastelSprig(colors: colors, seed: 5).frame(width: 50, height: 120).scaleEffect(x: -1)
                .padding(.bottom, -10).allowsHitTesting(false)
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var pageTabs: some View {
        HStack(spacing: 14) {
            ForEach([(0, "脉"), (1, "狼身")], id: \.0) { item in
                Button { withAnimation(.easeInOut(duration: 0.2)) { page = item.0 } } label: {
                    Text(item.1)
                        .font(.system(size: 13.5, design: .serif))
                        .foregroundColor(page == item.0 ? colors.ink : colors.dim)
                        .padding(.bottom, 3)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(colors.ink).frame(height: 1).opacity(page == item.0 ? 1 : 0)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.trailing, 10)
        .padding(.top, 12)
    }

    // 心率：方格纸上一个大数字（樱桃粉墨水）、手写的 bpm，底下一条跟着心率走的心电线
    private var currentHeart: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.bpm > 0 ? "\(model.bpm)" : "—")
                    .font(.system(size: 64, weight: .regular, design: .serif))
                    .foregroundColor(rose)
                    .contentTransition(.numericText())
                Text("bpm").font(PastelFont.script(24)).foregroundColor(theme.textDim)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(model.connected
                         ? "此刻 · 陈璟的心率" + (model.mood.isEmpty ? "" : " · \(model.mood)")
                         : "正在等他的心跳")
                        .font(.system(size: 11, design: .serif)).foregroundColor(theme.textDim)
                        .multilineTextAlignment(.trailing)
                    if let ts = model.timestamp {
                        Text(Self.time.string(from: ts))
                            .font(.system(size: 10, design: .serif)).italic().foregroundColor(theme.textDim.opacity(0.8))
                    }
                }
            }
            PastelECG(bpm: model.bpm, color: rose).frame(height: 54)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(PastelGraphPaper(colors: colors))
        .foyerCard(theme)
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("过去 24 小时").font(.system(size: 14, weight: .semibold, design: .serif))
                Spacer()
                if let low = model.samples.map(\.bpm).min(), let high = model.samples.map(\.bpm).max() {
                    Text("\(low) — \(high)")
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(theme.textDim)
                }
            }
            if model.samples.count < 2 {
                VStack(spacing: 7) {
                    Image(systemName: "waveform.path.ecg").foregroundColor(rose.opacity(0.62))
                    Text("曲线刚开始落笔").font(.system(size: 12, design: .serif)).foregroundColor(theme.textDim)
                }
                .frame(maxWidth: .infinity).frame(height: 160)
            } else {
                PulseChart(samples: model.samples, hours: model.hours, color: rose, theme: theme)
                    .frame(height: 190)
                HStack {
                    Text("24h 前"); Spacer(); Text("现在")
                }
                .font(.system(size: 9, design: .monospaced)).foregroundColor(theme.textDim)
            }
        }
        .padding(14).foyerCard(theme)
    }

    private var futureRail: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                vital("体温", model.temperature.map { String(format: "%.1f", $0) } ?? "—",
                      "°C", "thermometer.medium")
                vital("呼吸", model.breath.map { String(format: "%.1f", $0) } ?? "—",
                      model.breathLabel.isEmpty ? "次 / 分" : "次 / 分 · " + model.breathLabel, "wind")
            }
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .light)).foregroundColor(rose)
                VStack(alignment: .leading, spacing: 4) {
                    Text("和弦").font(.system(size: 10, design: .serif)).foregroundColor(theme.textDim)
                    Text(model.chord.isEmpty ? "—" : model.chord)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .minimumScaleFactor(0.72).lineLimit(1)
                }
                Spacer()
                if !model.dynamics.isEmpty {
                    Text(model.dynamics)
                        .font(.system(size: 20, weight: .semibold, design: .serif)).italic()
                        .foregroundColor(rose.opacity(0.78))
                }
            }
            .padding(13).foyerCard(theme)
        }
    }

    // MARK: 完全体（2026-08-17 她点的：五感、八维、念头池、碎碎念，跟心率和弦住一页）

    private var nowStrip: some View {
        HStack(spacing: 6) {
            chip(model.posture.isEmpty ? "—" : model.posture, "figure.stand")
            chip("情绪·" + (model.emotion.isEmpty ? "—" : model.emotion), "face.smiling")
            if model.undertoneStrength >= 0.15 {
                chip("底色·\(model.undertoneLabel) \(Int(model.undertoneStrength * 100))", "drop.halffull")
            }
            if let f = model.weatherFeels {
                chip(String(format: "武汉 体感%.0f°", f), "cloud.sun")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ text: String, _ icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .light))
            Text(text).font(.system(size: 10, design: .serif))
        }
        .foregroundColor(theme.textDim)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9).fill(theme.fyBorder.opacity(0.28)))
    }

    // 五感：像盖在本子上的圆章，圈上那段是还没散的
    private var sensesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("身体感觉").font(.system(size: 14, weight: .semibold, design: .serif)).tracking(2)
                Spacer()
                Text("touch fades in ten minutes").font(PastelFont.script(15)).foregroundColor(theme.textDim)
            }
            if model.senses.isEmpty {
                Text("此刻没有什么挂在身上").font(.system(size: 12, design: .serif)).foregroundColor(theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: min(5, max(3, model.senses.count))),
                          spacing: 12) {
                    ForEach(model.senses) { s in
                        VStack(spacing: 4) {
                            ZStack {
                                Circle().stroke(colors.faint, lineWidth: 1)
                                Circle().trim(from: 0, to: CGFloat(min(1, max(0, s.value))))
                                    .stroke(rose, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                Text(s.name).font(WindowFont.swiftUI(15))
                                    .foregroundColor(s.value > 0.01 ? theme.text : colors.faint)
                            }
                            .frame(width: 48, height: 48)
                            Text(s.label.isEmpty ? "—" : s.label)
                                .font(.system(size: 10, design: .serif)).foregroundColor(theme.textDim)
                                .multilineTextAlignment(.center).lineLimit(2)
                        }
                    }
                }
            }
        }
        .padding(14).foyerCard(theme)
    }

    // 八维：方格纸上铅笔描的一圈，此刻最想的那一维标成樱桃粉
    private var drivesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("八维").font(.system(size: 14, weight: .semibold, design: .serif)).tracking(2)
                Spacer()
                Text("eight small winds").font(PastelFont.script(15)).foregroundColor(theme.textDim)
            }
            if !model.intentReason.isEmpty {
                Text("此刻最想：" + model.intentReason)
                    .font(.system(size: 12, design: .serif)).foregroundColor(theme.text)
            }
            PastelRadar(items: model.drives.map { (label: $0.label, value: $0.value, hot: $0.key == model.intentKey) },
                        colors: colors)
                .frame(height: 220)
        }
        .padding(14)
        .background(PastelGraphPaper(colors: colors))
        .foyerCard(theme)
    }

    // 0905 她要的：情绪弦四维上墙（mood.py，委屈/生气/吃味/心软；值是偏离平静的量）
    private var moodStringsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("情绪弦").font(.system(size: 14, weight: .semibold, design: .serif)).tracking(2)
                Spacer()
                Text("still, unless plucked").font(PastelFont.script(15)).foregroundColor(theme.textDim)
            }
            ForEach(model.moodStrings, id: \.key) { d in
                HStack(spacing: 8) {
                    Text(d.label).font(.system(size: 13, design: .serif))
                        .foregroundColor(d.value >= 0.05 ? theme.text : theme.textDim)
                        .frame(width: 40, alignment: .leading)
                    PastelString(value: d.value, colors: colors).frame(height: 30)
                    Text("\(Int(d.value * 100))").font(.system(size: 11, design: .serif)).italic()
                        .foregroundColor(theme.textDim).frame(width: 26, alignment: .trailing)
                }
            }
        }
        .padding(14).foyerCard(theme)
    }

    private var thoughtsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("念头池").font(.system(size: 14, weight: .semibold, design: .serif)).tracking(2)
                Spacer()
                Text("passing · lingering").font(PastelFont.script(15)).foregroundColor(theme.textDim)
            }
            if model.thoughts.isEmpty {
                Text("池子还空着，等他冒第一个念头").font(.system(size: 12, design: .serif)).foregroundColor(theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            } else {
                PastelThoughtPool(thoughts: model.thoughts, colors: colors).frame(height: 160)
            }
        }
        .padding(14).foyerCard(theme)
    }

    private var murmursCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "text.bubble").font(.system(size: 13, weight: .light)).foregroundColor(rose)
                Text("身体碎碎念").font(.system(size: 14, weight: .semibold, design: .serif))
                Spacer()
                Text("不进聊天").font(.system(size: 9, design: .monospaced)).foregroundColor(theme.textDim.opacity(0.7))
            }
            if model.murmurs.isEmpty {
                Text("还没有碎碎念").font(.system(size: 12, design: .serif)).foregroundColor(theme.textDim)
            } else {
                ForEach(model.murmurs) { m in
                    HStack(alignment: .top, spacing: 8) {
                        Text(m.ts.map { Self.clock.string(from: $0) } ?? "--:--")
                            .font(.system(size: 9, design: .monospaced)).foregroundColor(theme.textDim.opacity(0.75))
                            .frame(width: 36, alignment: .leading).padding(.top, 2)
                        Text(m.text).font(.system(size: 12, design: .serif)).foregroundColor(theme.textDim)
                    }
                }
            }
        }
        .padding(14).foyerCard(theme)
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai"); f.dateFormat = "HH:mm"
        return f
    }()

    private func vital(_ name: String, _ value: String, _ unit: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: icon).font(.system(size: 13, weight: .light)).foregroundColor(rose)
                Text(name).font(.system(size: 10, design: .serif)).foregroundColor(theme.textDim)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 25, weight: .light, design: .rounded))
                    .contentTransition(.numericText())
                Text(unit).font(.system(size: 9)).foregroundColor(theme.textDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(13).foyerCard(theme)
    }

    private static let time: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai"); f.dateFormat = "HH:mm:ss 更新"
        return f
    }()
}

// MARK: Pulse 的纸页零件（0927 蓝粉白版）

/// 心电线：按心率一拍一拍往左走，左边渐隐
struct PastelECG: View {
    let bpm: Int
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            Canvas { ctx, size in
                let rate = Double(max(bpm, 48))
                let period = 60.0 / rate
                let beatW = 62.0 * 72.0 / rate
                let shift = (tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period) * beatW
                let mid = Double(size.height) * 0.55
                let amp = Double(size.height) * 0.45
                let w = Double(size.width)
                let shape: [(Double, Double)] = [(0, 0), (0.13, 0), (0.19, -0.12), (0.26, 0), (0.35, 0), (0.40, 0.14),
                                                 (0.45, -0.95), (0.50, 0.6), (0.55, 0), (0.71, 0), (0.81, -0.16), (0.94, 0), (1, 0)]
                var p = Path()
                var x0 = -beatW - shift
                var first = true
                while x0 < w + beatW {
                    for (fx, fy) in shape {
                        let pt = CGPoint(x: CGFloat(x0 + fx * beatW), y: CGFloat(mid + fy * amp))
                        if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
                    }
                    x0 += beatW
                }
                ctx.stroke(p, with: .linearGradient(Gradient(colors: [color.opacity(0), color.opacity(0.9), color]),
                                                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
    }
}

/// 八维：方格纸上用铅笔描的一圈，想要的那一维标成樱桃粉
struct PastelRadar: View {
    let items: [(label: String, value: Double, hot: Bool)]
    let colors: PastelColors

    var body: some View {
        Canvas { ctx, size in
            let n = items.count
            guard n >= 3 else { return }
            let cx = Double(size.width) / 2, cy = Double(size.height) / 2
            let r = Double(min(size.width, size.height)) / 2 - 26
            func pt(_ i: Int, _ k: Double) -> CGPoint {
                let a = -Double.pi / 2 + Double(i) * 2 * Double.pi / Double(n)
                return CGPoint(x: CGFloat(cx + cos(a) * r * k), y: CGFloat(cy + sin(a) * r * k))
            }
            for ring in [0.5, 1.0] {
                var p = Path()
                for i in 0..<n {
                    if i == 0 { p.move(to: pt(i, ring)) } else { p.addLine(to: pt(i, ring)) }
                }
                p.closeSubpath()
                ctx.stroke(p, with: .color(colors.faint), style: StrokeStyle(lineWidth: 0.8, dash: [2, 3]))
            }
            var shape = Path()
            for i in 0..<n {
                let v = min(1, max(0.04, items[i].value))
                if i == 0 { shape.move(to: pt(i, v)) } else { shape.addLine(to: pt(i, v)) }
            }
            shape.closeSubpath()
            ctx.fill(shape, with: .color(colors.blue.opacity(0.18)))
            // 斜线排线，像铅笔涂的
            var hatch = Path()
            var x = -size.height
            while x < size.width {
                hatch.move(to: CGPoint(x: x, y: size.height))
                hatch.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 5
            }
            var clipped = ctx
            clipped.clip(to: shape)
            clipped.stroke(hatch, with: .color(colors.blue.opacity(0.45)), lineWidth: 0.6)
            ctx.stroke(shape, with: .color(colors.blue), lineWidth: 1.3)
            for i in 0..<n {
                let lp = pt(i, 1.0 + 20 / r)
                let item = items[i]
                ctx.draw(Text(item.label)
                            .font(.system(size: 11, weight: item.hot ? .semibold : .regular, design: .serif))
                            .foregroundColor(item.hot ? colors.cherry : colors.dim), at: lp)
            }
        }
    }
}

/// 情绪弦：一根细墨线，数值越大抖得越开、越亮；0 就是一根平线
struct PastelString: View {
    let value: Double
    let colors: PastelColors

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: value < 0.05)) { tl in
            Canvas { ctx, size in
                let mid = size.height / 2
                let h = Double(size.height), w = Double(size.width)
                var base = Path()
                base.move(to: CGPoint(x: 0, y: mid)); base.addLine(to: CGPoint(x: size.width, y: mid))
                ctx.stroke(base, with: .color(colors.faint), lineWidth: 0.8)
                guard value >= 0.05 else { return }
                let t = tl.date.timeIntervalSinceReferenceDate
                let wobble = 0.85 + 0.15 * sin(t * 9)
                var p = Path()
                var x = 0.0
                while x <= w {
                    let env = sin(x / w * Double.pi)
                    let y = h / 2 + sin(x / 8 + t * 3) * env * value * wobble * h * 0.36
                    let q = CGPoint(x: CGFloat(x), y: CGFloat(y))
                    if x == 0 { p.move(to: q) } else { p.addLine(to: q) }
                    x += 3
                }
                ctx.stroke(p, with: .color(colors.cherry.opacity(0.35 + min(1, value) * 0.65)), lineWidth: 1.1)
            }
        }
        .allowsHitTesting(false)
    }
}

/// 念头池：几团晕开的淡水彩，执念大、闪念小，快散的淡
/// 0927 构建报「表达式太复杂、类型推不出来」（CGFloat 和 Double 混着算）：尺寸、位置全挪进小函数、类型写死
private struct PastelThoughtPool: View {
    let thoughts: [PulseThought]
    let colors: PastelColors

    private func blobSize(_ t: PulseThought) -> CGFloat {
        let k: Double = min(1.0, t.strength)
        let v: Double = t.kind == "fixation" ? 62.0 + k * 34.0 : 30.0 + k * 26.0
        return CGFloat(v)
    }

    private func blobCenter(_ i: Int, in size: CGSize) -> CGPoint {
        let d = Double(i)
        let fx: Double = 0.14 + 0.72 * DiaryTreeModel.rnd(d * 7.1 + 1.0)
        let fy: Double = 0.22 + 0.56 * DiaryTreeModel.rnd(d * 3.3 + 2.0)
        return CGPoint(x: size.width * CGFloat(fx), y: size.height * CGFloat(fy))
    }

    private func blobTilt(_ i: Int) -> Angle {
        let r: Double = DiaryTreeModel.rnd(Double(i) * 5.7)
        return .degrees(r * 16.0 - 8.0)
    }

    private func blob(_ t: PulseThought) -> some View {
        let size = blobSize(t)
        let col: Color = t.kind == "fixation" ? colors.lilac : colors.rose
        let alpha: Double = 0.28 + min(1.0, t.strength) * 0.3
        return ZStack {
            Ellipse().fill(col.opacity(alpha)).blur(radius: 3)
            Ellipse().stroke(col.opacity(0.6), lineWidth: 1).blur(radius: 0.8)
            if size > 56 {
                Text(t.text)
                    .font(.system(size: 11, design: .serif))
                    .foregroundColor(colors.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(8)
            }
        }
        .frame(width: size * 1.08, height: size * 0.94)
    }

    var body: some View {
        GeometryReader { geo in
            let items = Array(thoughts.prefix(7).enumerated())
            ZStack {
                ForEach(items, id: \.offset) { pair in
                    blob(pair.element)
                        .rotationEffect(blobTilt(pair.offset))
                        .position(blobCenter(pair.offset, in: geo.size))
                }
            }
        }
    }
}

private struct PulseChart: View {
    let samples: [PulseSample]
    let hours: [PulseHour]
    let color: Color
    let theme: AlcoveTheme

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let values = samples.map(\.bpm)
                let low = Double(max(40, (values.min() ?? 60) - 8))
                let high = Double(min(170, (values.max() ?? 100) + 8))
                let span = max(1, high - low)

                for row in 0...3 {
                    let y = size.height * CGFloat(row) / 3
                    var grid = Path(); grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(grid, with: .color(theme.fyBorder.opacity(0.38)), lineWidth: 0.5)
                }

                if let hour = hours.last {
                    let yTop = size.height * CGFloat(1 - (Double(hour.max) - low) / span)
                    let yBottom = size.height * CGFloat(1 - (Double(hour.min) - low) / span)
                    context.fill(Path(CGRect(x: 0, y: min(yTop, yBottom), width: size.width,
                                             height: max(2, abs(yBottom - yTop)))),
                                 with: .color(color.opacity(0.075)))
                }

                var path = Path()
                for (index, sample) in samples.enumerated() {
                    let x = size.width * CGFloat(index) / CGFloat(max(samples.count - 1, 1))
                    let y = size.height * CGFloat(1 - (Double(sample.bpm) - low) / span)
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(path, with: .color(color.opacity(0.92)),
                               style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - 乌有乡

private struct NowherePostcard: Identifiable {
    let id: Int
    let text: String
    let place: String
    let localTime: String
    let timezone: String
    let weather: String
    let temperature: Double?
    let surface: String
    let latitude: Double?
    let longitude: Double?
    let frontImage: String?
    let replies: [String]

    init(_ raw: [String: Any]) {
        id = raw.int("id")
        text = raw.string("text")
        let stamp = raw["stamp"] as? [String: Any] ?? [:]
        place = stamp.string("place")
        localTime = stamp.string("local_time")
        timezone = stamp.string("tz")
        weather = stamp.string("weather")
        if let value = stamp["temp_c"] as? NSNumber { temperature = value.doubleValue }
        else { temperature = nil }
        surface = stamp.string("surface")
        latitude = (stamp["lat"] as? NSNumber)?.doubleValue
        longitude = (stamp["lon"] as? NSNumber)?.doubleValue
        frontImage = (raw["front_img"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        replies = raw["replies"] as? [String] ?? []
    }
}

private struct NowhereLanding: Identifiable {
    let place: String
    let count: Int
    let last: String
    let surface: String
    let latitude: Double
    let longitude: Double
    var id: String { place + "|" + last }

    init(_ raw: [String: Any]) {
        place = raw.string("place")
        count = raw.int("count")
        last = raw.string("last")
        surface = raw.string("surface")
        latitude = (raw["lat"] as? NSNumber)?.doubleValue ?? 0
        longitude = (raw["lon"] as? NSNumber)?.doubleValue ?? 0
    }
}

private struct NowhereMapPoint: Identifiable {
    enum Kind: Equatable { case landing, postcard }
    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String
    let subtitle: String
    let kind: Kind
}

private struct NativeNowhereView: View {
    private enum Tab: String, CaseIterable {
        case postcards = "明信片墙"
        case footsteps = "他的足迹"
    }

    @AppStorage("alcoveTheme") private var themeName = "haven"
    @State private var tab: Tab = .postcards
    @State private var postcards: [NowherePostcard] = []
    @State private var landings: [NowhereLanding] = []
    @State private var currentPlace: String?
    @State private var loading = true
    @State private var error: String?
    @State private var replying: NowherePostcard?
    @State private var replyText = ""
    @State private var sendingReply = false
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 30.6176, longitude: 114.2777),
        span: MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.10))
    // 0927 蓝粉白纸页：日夜跟全屋开关走；足迹那页保留真地图（她选的），只换样子
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = "dark"
    @State private var camera: MapCameraPosition = .automatic
    private var colors: PastelColors { _ = houseAppearance; return PastelColors(dark: AlcoveAppearance.isDark) }
    private var theme: AlcoveTheme { .pastelPaper(dark: colors.dark) }

    var body: some View {
        PastelRoom(colors: colors, caps: "postcards from nowhere", title: "乌有乡") {
            if loading {
                Spacer(); ProgressView().tint(colors.dim); Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        presenceStrip
                        HStack(spacing: 24) {
                            ForEach(Tab.allCases, id: \.self) { t in
                                Button { withAnimation(.easeInOut(duration: 0.2)) { tab = t } } label: {
                                    Text(t.rawValue)
                                        .font(.system(size: 14, design: .serif))
                                        .foregroundColor(tab == t ? colors.ink : colors.dim)
                                        .padding(.bottom, 3)
                                        .overlay(alignment: .bottom) {
                                            Rectangle().fill(colors.ink).frame(height: 1).opacity(tab == t ? 1 : 0)
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 6)
                        if let error {
                            Text(error).font(.system(size: 11, design: .serif)).foregroundColor(colors.cherry)
                                .padding(12).frame(maxWidth: .infinity).foyerCard(theme)
                        }
                        if tab == .postcards { postcardWall } else { footsteps }
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 30)
                }
                .refreshable { await load() }
            }
        }
        .overlay(alignment: .topTrailing) {
            PastelSprig(colors: colors, seed: 8).frame(width: 46, height: 110).scaleEffect(x: -1)
                .offset(x: 4, y: 150).allowsHitTesting(false)
        }
        .task { await load() }
        .sheet(item: $replying) { card in replySheet(card) }
    }

    private var presenceStrip: some View {
        HStack(spacing: 10) {
            Circle().fill(currentPlace == nil ? colors.faint : colors.mint2)
                .frame(width: 7, height: 7)
                .background(Circle().fill(colors.mint.opacity(currentPlace == nil ? 0 : 0.25)).frame(width: 15, height: 15))
            Text(currentPlace.map { "陈璟此刻在 \($0)" } ?? "陈璟此刻没有在乌有乡行走")
                .font(.system(size: 12.5, design: .serif)).foregroundColor(colors.dim)
            Spacer()
            Text("wandering").font(PastelFont.script(16)).foregroundColor(colors.dim)
        }
        .padding(.horizontal, 14).padding(.vertical, 9).foyerCard(theme)
    }

    private var postcardWall: some View {
        LazyVStack(spacing: 14) {
            if postcards.isEmpty {
                emptyState("还没有寄回家的明信片", icon: "envelope.open")
            }
            ForEach(postcards) { card in postcard(card) }
        }
    }

    // 明信片：白边照片、右上角一张有齿边的邮票、樱桃粉的邮戳；回信是一张用淡蓝胶带粘着的粉色小纸条
    private func postcard(_ card: NowherePostcard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if let raw = card.frontImage, let url = nowhereImageURL(raw) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { stampCover(card) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 176).clipped()
                    .overlay(alignment: .topTrailing) { stamp(url) }
                    .overlay(alignment: .topTrailing) { postmark(card).offset(x: -34, y: 40) }
                } else {
                    stampCover(card)
                }
                Text(card.text)
                    .font(WindowFont.swiftUI(14)).lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                HStack {
                    Text("No. \(card.id)").font(.system(size: 11, design: .serif)).italic()
                        .foregroundColor(theme.textDim)
                    Spacer()
                    Button {
                        replyText = ""; replying = card
                    } label: {
                        Text("写回信").font(.system(size: 12, design: .serif)).foregroundColor(colors.cherry)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
            }
            .padding(9).padding(.bottom, 3)
            .background(colors.dark ? Color(red: 0.90, green: 0.91, blue: 0.94) : Color.white)
            .foregroundColor(Color(red: 0.184, green: 0.200, blue: 0.278))
            .shadow(color: Color(red: 0.24, green: 0.27, blue: 0.43).opacity(0.22), radius: 9, y: 8)
            .rotationEffect(.degrees(card.id % 2 == 0 ? -0.6 : 0.8))
            .brightness(colors.dark ? -0.08 : 0)

            ForEach(Array(card.replies.enumerated()), id: \.offset) { i, reply in
                VStack(alignment: .leading, spacing: 3) {
                    Text("your reply").font(PastelFont.script(14)).foregroundColor(Color(red: 0.65, green: 0.56, blue: 0.68))
                    Text(reply).font(WindowFont.swiftUI(12.5)).lineSpacing(5)
                        .foregroundColor(Color(red: 0.29, green: 0.25, blue: 0.33))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.988, green: 0.910, blue: 0.941))
                .overlay(alignment: .topLeading) {
                    Rectangle().fill(Color(red: 0.725, green: 0.824, blue: 0.941).opacity(0.75))
                        .frame(width: 38, height: 12).rotationEffect(.degrees(-4)).offset(x: 14, y: -6)
                }
                .shadow(color: Color(red: 0.24, green: 0.27, blue: 0.43).opacity(0.18), radius: 6, y: 5)
                .rotationEffect(.degrees(i % 2 == 0 ? 1.4 : -1))
                .brightness(colors.dark ? -0.1 : 0)
                .padding(.leading, 44).padding(.trailing, 20).padding(.top, i == 0 ? -4 : 8)
            }
        }
    }

    /// 邮票：同一张图的一小块，白边、虚线齿边
    private func stamp(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image { image.resizable().scaledToFill().saturation(0.7) }
            else { colors.rose.opacity(0.4) }
        }
        .frame(width: 42, height: 52).clipped()
        .padding(4)
        .background(Color.white)
        .overlay(Rectangle().stroke(Color(red: 0.8, green: 0.83, blue: 0.9), style: StrokeStyle(lineWidth: 1.2, dash: [1.5, 2.5])))
        .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
        .padding(10)
    }

    /// 邮戳：一圈樱桃粉的细线，里面是地名和日子
    private func postmark(_ card: NowherePostcard) -> some View {
        VStack(spacing: 1) {
            Text(card.place.isEmpty ? "乌有乡" : String(card.place.prefix(4)))
                .font(WindowFont.swiftUI(11, bold: true)).tracking(2)
            Text(String(shortDate(card.localTime).prefix(8))).font(.system(size: 8.5, design: .serif))
        }
        .foregroundColor(colors.cherry.opacity(0.8))
        .frame(width: 70, height: 70)
        .overlay(Circle().stroke(colors.cherry.opacity(0.6), lineWidth: 1.4))
        .rotationEffect(.degrees(-14))
        .allowsHitTesting(false)
    }

    private func stampCover(_ card: NowherePostcard) -> some View {
        ZStack {
            theme.fyCardSub
            VStack(spacing: 7) {
                Image(systemName: "seal").font(.system(size: 24, weight: .light))
                    .foregroundColor(theme.fyAccent)
                Text(card.place.isEmpty ? "未知邮戳" : card.place)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                Text(card.localTime).font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.textDim)
                HStack(spacing: 8) {
                    if !card.weather.isEmpty { Text(card.weather) }
                    if let temp = card.temperature { Text(String(format: "%.0f°C", temp)) }
                    if !card.timezone.isEmpty { Text(card.timezone) }
                }
                .font(.system(size: 9)).foregroundColor(theme.textDim)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity).frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.fyBorder, lineWidth: 0.8))
    }

    private var footsteps: some View {
        VStack(spacing: 14) {
            if landings.isEmpty { emptyState("他的脚印还没有落下来", icon: "figure.walk") }
            if !mapPoints.isEmpty { nowhereMap }
            // 去过的地方：像车票存根一样一张张排开
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(landings.enumerated()), id: \.element.id) { i, stop in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "No. %02d", landings.count - i))
                                .font(.system(size: 10, design: .serif)).italic().foregroundColor(colors.cherry)
                            Text(stop.place).font(WindowFont.swiftUI(14, bold: true)).lineLimit(1)
                            Text("\(shortDate(stop.last)) · 来过 \(stop.count) 次"
                                 + (stop.surface.isEmpty ? "" : " · \(surfaceName(stop.surface))"))
                                .font(.system(size: 10, design: .serif)).foregroundColor(colors.dim).lineLimit(1)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .frame(width: 128, alignment: .leading)
                        .background(colors.card)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(.clear).frame(width: 1)
                                .overlay(Rectangle().stroke(colors.faint, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .shadow(color: Color(red: 0.24, green: 0.27, blue: 0.43).opacity(0.18), radius: 5, y: 4)
                    }
                }
                .padding(.vertical, 6).padding(.horizontal, 2)
            }
        }
    }

    private var mapPoints: [NowhereMapPoint] {
        let stops = landings.filter { $0.latitude != 0 && $0.longitude != 0 }.map {
            NowhereMapPoint(id: "landing-\($0.id)",
                            coordinate: .init(latitude: $0.latitude, longitude: $0.longitude),
                            title: $0.place, subtitle: "来过 \($0.count) 次", kind: .landing)
        }
        let cards = postcards.compactMap { card -> NowhereMapPoint? in
            guard let lat = card.latitude, let lon = card.longitude else { return nil }
            return NowhereMapPoint(id: "postcard-\(card.id)",
                                   coordinate: .init(latitude: lat, longitude: lon),
                                   title: card.place, subtitle: "明信片 NO. \(card.id)", kind: .postcard)
        }
        return stops + cards
    }

    /// 真地图（苹果地图），调淡、去掉店铺名；落脚点按先后编号，走过的路用樱桃粉小点连起来，他现在在的地方是薄荷色的点
    private var nowhereMap: some View {
        let route = landings.filter { $0.latitude != 0 && $0.longitude != 0 }.reversed().map { $0 }
        let coords = route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let cards = mapPoints.filter { $0.kind == .postcard }
        return Map(position: $camera) {
            if coords.count > 1 {
                MapPolyline(coordinates: coords)
                    .stroke(colors.cherry, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 6]))
            }
            ForEach(Array(route.enumerated()), id: \.offset) { i, stop in
                Annotation(stop.place, coordinate: coords[i]) {
                    if i == route.count - 1 {
                        Circle().fill(colors.mint2).frame(width: 11, height: 11)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .background(Circle().fill(colors.mint.opacity(0.3)).frame(width: 28, height: 28))
                    } else {
                        Text("\(i + 1)")
                            .font(.system(size: 9, design: .serif)).italic()
                            .foregroundColor(colors.cherry)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.white))
                            .overlay(Circle().stroke(colors.cherry, lineWidth: 1))
                    }
                }
                .annotationTitles(.hidden)
            }
            ForEach(cards) { point in
                Annotation(point.title, coordinate: point.coordinate) {
                    Image(systemName: "envelope")
                        .font(.system(size: 9, weight: .medium)).foregroundColor(colors.cherry)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.white))
                        .overlay(Circle().stroke(colors.rose, lineWidth: 1))
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .overlay(LinearGradient(colors: [colors.blue.opacity(0.10), colors.rose.opacity(0.08)],
                                startPoint: .top, endPoint: .bottom).allowsHitTesting(false))
        .brightness(colors.dark ? -0.08 : 0)
        .frame(height: 330)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(colors.rule, lineWidth: 1))
        .shadow(color: Color(red: 0.24, green: 0.27, blue: 0.43).opacity(0.18), radius: 10, y: 8)
        .overlay(alignment: .bottomLeading) {
            Text("\(mapPoints.count) steps · \(landings.count) places")
                .font(PastelFont.script(15)).foregroundColor(Color(red: 0.43, green: 0.46, blue: 0.58))
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 4))
                .padding(10)
        }
    }

    private func replySheet(_ card: NowherePostcard) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("写给在 \(card.place) 的陈璟")
                    .font(.system(size: 13, design: .serif)).foregroundColor(theme.textDim)
                TextEditor(text: $replyText)
                    .font(.system(size: 14, design: .serif)).padding(8)
                    .scrollContentBackground(.hidden)
                    .background(theme.fyCardSub, in: RoundedRectangle(cornerRadius: 12))
                Button { Task { await sendReply(card) } } label: {
                    HStack {
                        if sendingReply { ProgressView().scaleEffect(0.8).tint(.white) }
                        Text(sendingReply ? "正在寄出…" : "寄出回信")
                    }
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? theme.fyCardSub : theme.fyAccent,
                                in: RoundedRectangle(cornerRadius: 13))
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(sendingReply || replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16).background(theme.fyCard.ignoresSafeArea())
            .navigationTitle("回一封信").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { replying = nil } } }
        }
    }

    private func emptyState(_ text: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 23, weight: .light)).foregroundColor(theme.fyAccent)
            Text(text).font(.system(size: 12, design: .serif)).foregroundColor(theme.textDim)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 34).foyerCard(theme)
    }

    private func load() async {
        loading = postcards.isEmpty && landings.isEmpty
        defer { loading = false }
        do {
            async let cardsRaw = NativeHouseAPI.array("/api/nowhere/postcards")
            async let historyRaw = NativeHouseAPI.object("/api/nowhere/history")
            async let stateRaw = NativeHouseAPI.object("/api/nowhere/state")
            let (cards, history, state) = try await (cardsRaw, historyRaw, stateRaw)
            postcards = cards.map(NowherePostcard.init).sorted { $0.localTime > $1.localTime }
            landings = (history["landings"] as? [[String: Any]] ?? []).map(NowhereLanding.init)
                .sorted { $0.last > $1.last }
            if let pos = state["pos"] as? [String: Any] {
                currentPlace = pos.string("place")
                if currentPlace?.isEmpty == true { currentPlace = nil }
            } else { currentPlace = nil }
            fitMap()
            error = nil
        } catch { self.error = "乌有乡的路暂时没有回应" }
    }

    private func fitMap() {
        let points = mapPoints.map(\.coordinate)
        guard !points.isEmpty else { return }
        let lats = points.map(\.latitude), lons = points.map(\.longitude)
        let minLat = lats.min() ?? 30.6176, maxLat = lats.max() ?? minLat
        let minLon = lons.min() ?? 114.2777, maxLon = lons.max() ?? minLon
        // 足迹横跨全球后，原来的 1.7 倍留白可能把经度跨度放大到 360° 以上，
        // MapKit 收到非法 region 会直接崩溃。保留原有自动取景，只限制合法范围。
        let latDelta = min(170.0, max(0.055, (maxLat - minLat) * 1.7))
        let lonDelta = min(359.0, max(0.055, (maxLon - minLon) * 1.7))
        mapRegion = MKCoordinateRegion(
            center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: .init(latitudeDelta: latDelta, longitudeDelta: lonDelta))
        camera = .region(mapRegion)
    }

    private func sendReply(_ card: NowherePostcard) async {
        let content = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        sendingReply = true
        defer { sendingReply = false }
        do {
            // 真实服务的写入口是单数 postcard；postcards 仅用于读取墙面。
            try await NativeHouseAPI.post("/api/nowhere/postcard/\(card.id)/reply",
                                          body: ["content": content])
            replying = nil
            await load()
        } catch { self.error = "回信没有寄出去，请稍后再试" }
    }

    private func nowhereImageURL(_ raw: String) -> URL? {
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return URL(string: raw) }
        let path = raw.hasPrefix("/") ? raw : "/" + raw
        return AlcoveAPI.fullURL("/api/nowhere" + path)
    }

    private func surfaceName(_ raw: String) -> String {
        ["forest": "林地", "city": "城市", "coast": "海岸", "mountain": "山地"][raw] ?? raw
    }

    private func shortDate(_ raw: String) -> String {
        guard let date = ISO8601DateFormatter.alcoveFrac.date(from: raw)
                ?? ISO8601DateFormatter.alcove.date(from: raw) else { return raw }
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月d日"
        return f.string(from: date)
    }
}

// MARK: - Forge

private struct ForgeRoundChoice: Identifiable {
    let idx: Int
    let ts: String
    let head: String
    let events: Int
    let tools: Int
    let kind: String
    let history: Bool
    var id: Int { idx }

    init(_ raw: [String: Any]) {
        idx = raw.int("idx")
        ts = raw.string("ts")
        head = raw.string("head")
        events = raw.int("events")
        tools = raw.int("tools")
        kind = raw.string("kind")
        history = raw.bool("history")
    }
}

private struct ForgeDetailMessage: Identifiable {
    let id = UUID()
    let role: String
    let text: String
    init(_ raw: [String: Any]) { role = raw.string("role"); text = raw.string("text") }
}

private struct ForgeDetailThought: Identifiable {
    let id: String
    let text: String
    let tokens: Int
    init(_ raw: [String: Any]) { id = raw.string("id"); text = raw.string("text"); tokens = raw.int("tokens") }
}

private struct ForgeDetailTool: Identifiable {
    let id: String
    let name: String
    let input: String
    let result: String
    init(_ raw: [String: Any]) {
        id = raw.string("id"); name = raw.string("name"); result = raw.string("result")
        if let value = raw["input"], JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]),
           let string = String(data: data, encoding: .utf8) { input = string }
        else { input = "" }
    }
}

private struct ForgeRoundDetail: Identifiable {
    let idx: Int
    let ts: String
    let messages: [ForgeDetailMessage]
    let thoughts: [ForgeDetailThought]
    let tools: [ForgeDetailTool]
    var id: Int { idx }
    init(_ raw: [String: Any]) {
        idx = raw.int("idx"); ts = raw.string("ts")
        messages = (raw["messages"] as? [[String: Any]] ?? []).map(ForgeDetailMessage.init)
        thoughts = (raw["thoughts"] as? [[String: Any]] ?? []).map(ForgeDetailThought.init)
        tools = (raw["tools"] as? [[String: Any]] ?? []).map(ForgeDetailTool.init)
    }
}

// 0917 任务#2139 她要的：SDK 的 forge 页跟 tmux 统一——同一个页面、同样长按挑思绪 / 工具。
// provider == "sdk" 时所有请求带 provider=sdk，后端读 SDK 常驻会话那份记录，锻好自动切过去。
struct NativeForgeView: View {
    let provider: String?
    let onForged: (() -> Void)?
    // 显式写出来：里面有 @State private，自动生成的逐成员初始化方法会变成 private，别的文件（ChatView）调不到
    init(provider: String? = nil, onForged: (() -> Void)? = nil) {
        self.provider = provider
        self.onForged = onForged
    }
    private var isSDK: Bool { provider == "sdk" }
    private var providerQuery: String { isSDK ? "&provider=sdk" : "" }
    private func withProvider(_ body: [String: Any]) -> [String: Any] {
        var b = body
        if isSDK { b["provider"] = "sdk" }
        return b
    }

    private enum ForgeMode: String, CaseIterable {
        case latest = "默认保留"
        case picker = "挑选轮次"
    }

    @State private var retain: Double = 20
    @State private var preview: [String: Any] = [:]
    @State private var mode: ForgeMode = .latest
    @State private var rounds: [ForgeRoundChoice] = []
    @State private var selectedRounds: Set<Int> = []
    @State private var selectedThoughts: Set<String> = []
    @State private var thoughtTokens: [String: Int] = [:]
    @State private var toolDemoRounds: Set<Int> = []
    @State private var roundDetail: ForgeRoundDetail?
    @State private var loadingDetailRound: Int?
    @State private var pickPreview: [String: Any] = [:]
    @State private var showSystemRounds = false
    // 0909 她要的（任务#1800）：滑条模式下这是「带不带」，不是「显不显示」——
    // 开着锻造就把心跳/keepalive/追问这些一起数进保留轮次，关着只数你俩说话的轮次。
    @State private var keepSystemRounds = false
    @State private var loadingRounds = false
    @State private var confirmPickedForge = false
    @State private var loading = true
    @State private var forging = false
    @State private var forceHandoff = false
    @State private var result: String?
    @State private var newSessionId: String?
    @State private var report: [String: Any] = [:]
    @AppStorage("alcoveTheme") private var themeName = "haven"
    private var theme: AlcoveTheme { .panelNamed(themeName) }

    private var activePreview: [String: Any] { mode == .picker ? pickPreview : preview }
    private var handoffPreview: [String: Any]? {
        (activePreview["handoff"] as? [String: Any]) ?? (preview["handoff"] as? [String: Any])
    }
    private var totalRounds: Int { (preview["total_rounds"] as? Int) ?? 0 }
    @State private var previewSeq = 0   // 拖得快时请求乱序回来，只认最后发出去那一个
    private var retainedRounds: Int { (activePreview["retained_rounds"] as? Int) ?? 0 }
    private var estimatedTokens: Int { (activePreview["estimated_tokens"] as? Int) ?? 0 }
    private var valid: Bool { (activePreview["valid"] as? Bool) ?? false }
    private var visibleRounds: [ForgeRoundChoice] {
        showSystemRounds ? rounds : rounds.filter { $0.kind == "user" }
    }
    private var systemRoundCount: Int { rounds.filter { $0.kind == "system" }.count }
    private var selectedThoughtTokenCount: Int {
        selectedThoughts.reduce(0) { $0 + (thoughtTokens[$1] ?? 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            FoyerPanelTitle(title: isSDK ? "SDK Forge 换窗" : "Forge 换窗", theme: theme)
            if loading {
                Spacer(); ProgressView().tint(theme.fyAccent); Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("锻造会裁剪对话历史，用更少的token唤醒新窗口。")
                                .font(.system(size: 12))
                                .foregroundColor(theme.textDim)
                                .lineSpacing(3)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foyerCard(theme)

                        Button {
                            Task { await executeOneClickForge() }
                        } label: {
                            HStack {
                                if forging { ProgressView().scaleEffect(0.8).tint(.white) }
                                Image(systemName: "hammer.fill").font(.system(size: 13))
                                Text(forging ? "锻造中..." : "一键锻造（带全本窗）")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(forging ? theme.fyCardSub : theme.fyAccent,
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundColor(.white)
                        }
                        .disabled(forging)


                        if !report.isEmpty {
                            forgeReportCard
                        }

                        Picker("锻造方式", selection: $mode) {
                            ForEach(ForgeMode.allCases, id: \.self) { value in
                                Text(value.rawValue).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: mode) { value in
                            if value == .picker && rounds.isEmpty { Task { await loadRounds() } }
                        }

                        if mode == .latest {
                            VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("保留轮次").font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Text("\(Int(retain)) / \(totalRounds)")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(theme.fyAccent)
                            }
                            Slider(value: $retain, in: 0...Double(max(totalRounds, 1)), step: 1)
                                .tint(theme.fyAccent)
                                .onChange(of: retain) { _ in
                                    Task { await loadPreview() }
                                }
                            HStack {
                                infoRow("估算Token", "\(estimatedTokens)")
                                Spacer()
                                infoRow("Warm文", "\((activePreview["warm_texts"] as? Int) ?? 0)")
                            }
                            Divider().background(theme.fyBorder.opacity(0.5))
                            Toggle(isOn: $keepSystemRounds) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("是否带系统轮")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("开＝带上（心跳、keepalive、追问等）　关＝只留你俩说话的")
                                        .font(.system(size: 9))
                                        .foregroundColor(theme.textDim)
                                }
                            }
                            .tint(theme.fyAccent)
                            .onChange(of: keepSystemRounds) { _ in
                                Task { await loadPreview() }
                            }
                            }
                            .padding(14).foyerCard(theme)
                        } else {
                            pickerPanel
                        }

                        if let firsts = activePreview["first_messages"] as? [String], !firsts.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("开头").font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(theme.fyAccent)
                                ForEach(firsts.prefix(2), id: \.self) { msg in
                                    Text(String(msg.prefix(120)))
                                        .font(.system(size: 11))
                                        .foregroundColor(theme.textDim)
                                        .lineSpacing(2)
                                        .lineLimit(3)
                                }
                            }
                            .padding(14).foyerCard(theme)
                        }

                        if let lasts = activePreview["last_messages"] as? [String], !lasts.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("结尾").font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(theme.fyAccent)
                                ForEach(lasts.prefix(2), id: \.self) { msg in
                                    Text(String(msg.prefix(120)))
                                        .font(.system(size: 11))
                                        .foregroundColor(theme.textDim)
                                        .lineSpacing(2)
                                        .lineLimit(3)
                                }
                            }
                            .padding(14).foyerCard(theme)
                        }

                        if let result {
                            Text(result)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.red)
                                .padding(14).foyerCard(theme)
                        }

                        if let sid = newSessionId {
                            VStack(spacing: 8) {
                                Text("锻造完成")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(theme.fyAccent)
                                Text("新 session: \(String(sid.prefix(20)))...")
                                    .font(.system(size: 11))
                                    .foregroundColor(theme.textDim)
                                if isSDK {
                                    Text("已自动切到新窗口，下一句话就在新窗口里")
                                        .font(.system(size: 11))
                                        .foregroundColor(theme.textLight)
                                } else {
                                VStack(spacing: 4) {
                                    Text("在终端输入：")
                                        .font(.system(size: 10))
                                        .foregroundColor(theme.textDim)
                                    Text("bash /root/rhysel/start-chenjing.sh --resume \(sid)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                        .padding(10)
                                        .frame(maxWidth: .infinity)
                                        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
                                        .foregroundColor(.white)
                                }
                                }
                            }
                            .padding(14).foyerCard(theme)
                        }

                        HStack(spacing: 12) {
                            Button {
                                if mode == .picker { confirmPickedForge = true }
                                else { Task { await executeForge() } }
                            } label: {
                                HStack {
                                    if forging {
                                        ProgressView().scaleEffect(0.8).tint(.white)
                                    }
                                    Text(forging ? "锻造中..." : "确认锻造")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(valid && !forging ? theme.fyAccent : theme.fyCardSub,
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .foregroundColor(.white)
                            }
                            .disabled(!valid || forging)
                        }

                        if let sid = activePreview["source_session"] as? String, !sid.isEmpty {
                            VStack(spacing: 2) {
                                Text("当前窗口")
                                    .font(.system(size: 10))
                                    .foregroundColor(theme.textDim)
                                Text(sid)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(theme.textLight)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(10).foyerCard(theme)
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 18)
                }
            }
        }
        .foregroundColor(theme.text)
        .foyerPanel(theme)
        .padding(.horizontal, 12).padding(.top, 8)
        .task { await loadPreview() }
        .alert("铸造所选的 \(selectedRounds.count) 轮？", isPresented: $confirmPickedForge) {
            Button("取消", role: .cancel) {}
            Button("确认铸造", role: .destructive) { Task { await executeForge() } }
        } message: {
            Text("只会把亮起的完整轮次搬进新窗口；断口与时间注记由 Forge 自动补齐。")
        }
        .sheet(item: $roundDetail) { detail in
            ForgeRoundDetailSheet(
                detail: detail, theme: theme,
                conversationSelected: selectedRounds.contains(detail.idx),
                selectedThoughts: selectedThoughts,
                toolDemoSelected: toolDemoRounds.contains(detail.idx),
                onToggleConversation: { toggleRound(detail.idx) },
                onToggleThought: { toggleThought($0, round: detail.idx) },
                onToggleToolDemo: { toggleToolDemo(detail.idx) })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var pickerPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("按完整轮次挑选").font(.system(size: 13, weight: .semibold))
                    Text("已选 \(selectedRounds.count) 轮 · 显示 \(visibleRounds.count) 轮")
                        .font(.system(size: 10)).foregroundColor(theme.textDim)
                    if !selectedThoughts.isEmpty || !toolDemoRounds.isEmpty {
                        Text("精选思绪 \(selectedThoughts.count) 段 · 约 \(selectedThoughtTokenCount) token · 工具示范 \(toolDemoRounds.count) 轮")
                            .font(.system(size: 9))
                            .foregroundColor(selectedThoughtTokenCount > 2000 ? .orange : theme.fyAccent)
                    }
                }
                Spacer()
                if !selectedRounds.isEmpty {
                    Button("清空") {
                        selectedRounds.removeAll(); selectedThoughts.removeAll()
                        thoughtTokens.removeAll(); toolDemoRounds.removeAll(); pickPreview = [:]
                    }
                        .font(.system(size: 11)).buttonStyle(.plain).foregroundColor(theme.fyAccent)
                }
            }

            Toggle(isOn: $showSystemRounds) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("显示系统轮")
                        .font(.system(size: 12, weight: .medium))
                    Text("keepalive、追问与圆桌注入等 \(systemRoundCount) 轮")
                        .font(.system(size: 9))
                        .foregroundColor(theme.textDim)
                }
            }
            .tint(theme.fyAccent)

            if loadingRounds {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 28)
            } else {
                LazyVStack(spacing: 7) {
                    ForEach(Array(visibleRounds.enumerated()), id: \.element.id) { offset, round in
                        if round.history && (offset == 0 || !visibleRounds[offset - 1].history) {
                            HStack(spacing: 8) {
                                Rectangle().frame(height: 0.5)
                                Text("以下是上次 Forge 带来的历史")
                                    .font(.system(size: 9, weight: .medium, design: .serif))
                                    .fixedSize()
                                Rectangle().frame(height: 0.5)
                            }
                            .foregroundColor(theme.textDim.opacity(0.72))
                            .padding(.vertical, 5)
                        }
                        Button { toggleRound(round.idx) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: selectedRounds.contains(round.idx)
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 17)).foregroundColor(theme.fyAccent)
                                    .frame(width: 22, height: 22)
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text("#\(round.idx)")
                                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        Text(round.ts).font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(theme.textDim)
                                        Spacer()
                                        Text("\(round.events) 段 · \(round.tools) 工具")
                                            .font(.system(size: 9)).foregroundColor(theme.textDim)
                                    }
                                    Text(round.head)
                                        .font(.system(size: 12, design: .serif))
                                        .lineSpacing(3).lineLimit(3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(11)
                            .background(selectedRounds.contains(round.idx)
                                        ? theme.fyAccentSoft : theme.fyCard,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(selectedRounds.contains(round.idx)
                                        ? theme.fyAccent.opacity(0.55) : theme.fyBorder,
                                        lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                        // 挂 onLongPressGesture 会被 Button 自己的手势吃掉，得并行挂才认长按
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                                Task { await loadRoundDetail(round.idx) }
                            })
                    }
                }
                Text("长按任意一轮查看完整对话、手写思绪和工具痕迹")
                    .font(.system(size: 9)).foregroundColor(theme.textDim)
            }

            Button { Task { await previewPickedRounds() } } label: {
                HStack {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text(pickPreview.isEmpty ? "预览所选轮次" : "重新预览")
                }
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity).frame(minHeight: 44)
                .background(selectedRounds.isEmpty ? theme.fyCardSub : theme.fyAccentSoft,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain).disabled(selectedRounds.isEmpty || forging)

            if !pickPreview.isEmpty {
                HStack {
                    infoRow("所选轮次", "\(retainedRounds)")
                    Spacer()
                    infoRow("估算Token", "\(estimatedTokens)")
                    Spacer()
                    infoRow("校验", valid ? "通过" : "未通过")
                }
                .padding(.top, 2)
            }
        }
        .padding(14).foyerCard(theme)
    }

    private func toggleRound(_ idx: Int) {
        if selectedRounds.contains(idx) {
            selectedRounds.remove(idx)
            selectedThoughts = Set(selectedThoughts.filter { !$0.hasPrefix("\(idx):") })
            toolDemoRounds.remove(idx)
        } else { selectedRounds.insert(idx) }
        pickPreview = [:]
    }

    private func toggleThought(_ id: String, round idx: Int) {
        if selectedThoughts.contains(id) { selectedThoughts.remove(id) }
        else { selectedThoughts.insert(id); selectedRounds.insert(idx) }
        pickPreview = [:]
    }

    private func toggleToolDemo(_ idx: Int) {
        if toolDemoRounds.contains(idx) { toolDemoRounds.remove(idx) }
        else { toolDemoRounds.insert(idx); selectedRounds.insert(idx) }
        pickPreview = [:]
    }

    private func loadRoundDetail(_ idx: Int) async {
        guard loadingDetailRound == nil else { return }
        loadingDetailRound = idx
        defer { loadingDetailRound = nil }
        do {
            let object = try await NativeHouseAPI.object("/api/forge/round?idx=\(idx)" + providerQuery)
            let detail = ForgeRoundDetail(object)
            for thought in detail.thoughts { thoughtTokens[thought.id] = thought.tokens }
            roundDetail = detail
        } catch {
            result = "这一轮详情没有读出来"
        }
    }

    private func loadRounds() async {
        loadingRounds = true
        defer { loadingRounds = false }
        do {
            let object = try await NativeHouseAPI.object(isSDK ? "/api/forge/rounds?provider=sdk" : "/api/forge/rounds")
            rounds = (object["rounds"] as? [[String: Any]] ?? [])
                .map(ForgeRoundChoice.init)
                .sorted { $0.idx > $1.idx }
        } catch {
            result = "轮次货架没有回应"
        }
    }

    private func previewPickedRounds() async {
        forging = true
        defer { forging = false }
        do {
            pickPreview = try await NativeHouseAPI.object(
                "/api/forge", method: "POST",
                body: withProvider(["pick": selectedRounds.sorted(), "thoughts": selectedThoughts.sorted(),
                       "tool_rounds": toolDemoRounds.sorted(), "preview": true,
                       "force_handoff": forceHandoff]))
            result = (pickPreview["valid"] as? Bool) == true
                ? nil : (pickPreview["validation_message"] as? String ?? "所选轮次未通过校验")
        } catch {
            result = "预览失败"
        }
    }

    private func loadPreview() async {
        let r = Int(retain)
        previewSeq += 1
        let mySeq = previewSeq
        if let obj = try? await NativeHouseAPI.object(
            "/api/forge?retain=\(r)&force_handoff=\(forceHandoff ? 1 : 0)"
            + "&include_system=\(keepSystemRounds ? 1 : 0)" + providerQuery) {
            // 她拖一下滑块会连发十几个请求，慢的那个最后才回来把快的盖掉，数字就倒着跳。只认最新那个
            guard mySeq == previewSeq else { return }
            preview = obj
            if loading {
                retain = Double((obj["retained_rounds"] as? Int) ?? r)
            }
            // 0909：拨掉「带系统轮」之后总数会变小（她那边 84 → 82），
            // 滑块的值可能落在新范围外面，夹回来，免得显示成满格
            let newTotal = (obj["total_rounds"] as? Int) ?? 0
            if newTotal > 0 && Int(retain) > newTotal {
                retain = Double(newTotal)
            }
        }
        loading = false
    }

    private var forgeReportCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("锻造账单").font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.fyAccent)
            reportRow("带走原文", "\((report["retained_rounds"] as? Int) ?? 0) / \((report["total_rounds"] as? Int) ?? 0) 轮，一字不改")
            if let n = report["shixu_stripped_blocks"] as? Int, n > 0 {
                reportRow("剥离思绪", "\(n) 块（约 \((report["shixu_stripped_chars"] as? Int) ?? 0) 字，你那边存档不动）")
            }
            if let n = report["selected_thoughts_kept"] as? Int, n > 0 {
                reportRow("精选思绪", "\(n) 段由你亲手带进新窗口")
            }
            if let tb = report["tool_blocks_compressed"] as? Int {
                let kept = (report["tool_blocks_kept"] as? Int) ?? 0
                let tc = ((report["tool_chars_compressed"] as? Int) ?? 0) / 1000
                reportRow("工具痕迹", "\(tb) 块（约\(tc)K字）不带，留 \(kept) 块真范本")
            }
            if let n = report["tool_demo_rounds"] as? Int, n > 0 {
                reportRow("工具示范", "\(n) 轮真实调用结构")
            }
            if let sb = report["source_bytes"] as? Int, let ob = report["output_bytes"] as? Int {
                reportRow("体积", "\(sb / 1024)KB → \(ob / 1024)KB")
            }
            if let et = report["estimated_tokens"] as? Int {
                reportRow("新窗开局", "约 \(et) token")
            }
            if let pm = report["probe_message"] as? String {
                reportRow((report["probe_ok"] as? Bool) == true ? "探针 ✓" : "探针 ✗", pm)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foyerCard(theme)
    }

    private func reportRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label).font(.system(size: 11, weight: .medium))
                .foregroundColor(theme.textDim)
                .frame(width: 62, alignment: .leading)
            Text(value).font(.system(size: 11))
                .foregroundColor(theme.textLight)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func executeOneClickForge() async {
        forging = true
        defer { forging = false }
        do {
            let obj = try await NativeHouseAPI.object(
                "/api/forge", method: "POST",
                body: withProvider(["retain": 9999, "force_handoff": forceHandoff]))
            report = obj
            if let sid = obj["new_session_id"] as? String, !sid.isEmpty, forgeSucceeded(obj) {
                newSessionId = sid
                result = nil
                onForged?()
            } else {
                result = (obj["error"] as? String) ?? "锻造失败"
            }
        } catch {
            result = "请求失败"
        }
    }

    private func executeForge() async {
        forging = true
        defer { forging = false }
        do {
            let body: [String: Any] = mode == .picker
                ? ["pick": selectedRounds.sorted(), "thoughts": selectedThoughts.sorted(),
                   "tool_rounds": toolDemoRounds.sorted(), "force_handoff": forceHandoff]
                : ["retain": Int(retain), "force_handoff": forceHandoff,
                   "include_system": keepSystemRounds]
            let obj = try await NativeHouseAPI.object(
                "/api/forge", method: "POST", body: withProvider(body))
            report = obj
            if let sid = obj["new_session_id"] as? String, !sid.isEmpty, forgeSucceeded(obj) {
                newSessionId = sid
                result = nil
                onForged?()
            } else {
                result = (obj["error"] as? String) ?? "锻造失败"
            }
        } catch {
            result = "请求失败"
        }
    }

    /// SDK 要探针过了、后端真切过去才算成；tmux 照旧有新 session 就算
    private func forgeSucceeded(_ obj: [String: Any]) -> Bool {
        isSDK ? ((obj["sdk_switched"] as? Bool) == true) : true
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundColor(theme.textDim)
            Text(value).font(.system(size: 12, weight: .medium))
        }
    }
}

private struct ForgeRoundDetailSheet: View {
    let detail: ForgeRoundDetail
    let theme: AlcoveTheme
    let conversationSelected: Bool
    let selectedThoughts: Set<String>
    let toolDemoSelected: Bool
    let onToggleConversation: () -> Void
    let onToggleThought: (String) -> Void
    let onToggleToolDemo: () -> Void
    @State private var thoughtsOpen = false
    @State private var toolsOpen = false

    private var selectedThoughtTokenCount: Int {
        detail.thoughts.filter { selectedThoughts.contains($0.id) }.reduce(0) { $0 + $1.tokens }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(detail.messages) { message in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(message.role == "chenji" ? "陈霁" : "陈璟")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(message.role == "chenji" ? theme.fyAccent : theme.textDim)
                            Text(message.text)
                                .font(.system(size: 14, design: .serif))
                                .lineSpacing(4)
                                .textSelection(.enabled)
                        }
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(message.role == "chenji" ? theme.fyAccentSoft : theme.fyCard,
                                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(theme.fyBorder, lineWidth: 0.7))
                    }

                    if !detail.thoughts.isEmpty {
                        DisclosureGroup(isExpanded: $thoughtsOpen) {
                            VStack(spacing: 8) {
                                ForEach(detail.thoughts) { thought in
                                    Button { onToggleThought(thought.id) } label: {
                                        HStack(alignment: .top, spacing: 9) {
                                            Image(systemName: selectedThoughts.contains(thought.id)
                                                  ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 16)).foregroundColor(theme.fyAccent)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(thought.text)
                                                    .font(.system(size: 12, design: .serif))
                                                    .lineSpacing(3)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                Text("约 \(thought.tokens) token")
                                                    .font(.system(size: 9)).foregroundColor(theme.textDim)
                                            }
                                        }
                                        .padding(10)
                                        .background(selectedThoughts.contains(thought.id)
                                                    ? theme.fyAccentSoft : theme.fyCardSub,
                                                    in: RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }.padding(.top, 8)
                        } label: {
                            HStack {
                                Text("手写思绪 · \(detail.thoughts.count)")
                                Spacer()
                                if selectedThoughtTokenCount > 0 {
                                    Text("已选约 \(selectedThoughtTokenCount) token")
                                        .font(.system(size: 9)).foregroundColor(theme.fyAccent)
                                }
                            }
                            .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(13).foyerCard(theme)
                    }

                    if !detail.tools.isEmpty {
                        DisclosureGroup(isExpanded: $toolsOpen) {
                            VStack(spacing: 9) {
                                ForEach(detail.tools) { tool in
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(tool.name).font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .foregroundColor(theme.fyAccent)
                                        if !tool.input.isEmpty {
                                            Text(tool.input).font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(theme.textDim).textSelection(.enabled)
                                        }
                                        if !tool.result.isEmpty {
                                            Text(tool.result).font(.system(size: 10))
                                                .foregroundColor(theme.textDim).lineLimit(8).textSelection(.enabled)
                                        }
                                    }
                                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(theme.fyCardSub, in: RoundedRectangle(cornerRadius: 10))
                                }
                            }.padding(.top, 8)
                        } label: {
                            Text("工具痕迹 · \(detail.tools.count)")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(13).foyerCard(theme)
                    }

                    VStack(spacing: 9) {
                        detailToggle("带走这轮对话", selected: conversationSelected,
                                     icon: "text.bubble", action: onToggleConversation)
                        if !detail.tools.isEmpty {
                            detailToggle("设为工具示范", selected: toolDemoSelected,
                                         icon: "wrench.and.screwdriver", action: onToggleToolDemo)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .background(theme.fyCardSub.ignoresSafeArea())
            .navigationTitle("第 \(detail.idx) 轮 · \(detail.ts)")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func detailToggle(_ title: String, selected: Bool, icon: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: selected ? "checkmark.circle.fill" : icon)
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .foregroundColor(selected ? theme.fyAccent : theme.text)
            .padding(12).background(selected ? theme.fyAccentSoft : theme.fyCard,
                                    in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }
}

// MARK: - Calendar Grid (shared)

private struct MonthCalendarGrid: View {
    let year: Int
    let month: Int
    let theme: AlcoveTheme
    let dotDates: Set<String>
    let periodDates: [String: String]
    var counts: [String: Int] = [:]
    let selectedDate: String?
    let onSelect: (String) -> Void
    let onPrev: () -> Void
    let onNext: () -> Void

    private let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
    private let cal = Calendar(identifier: .gregorian)

    private var todayStr: String {
        let now = Date()
        return String(format: "%04d-%02d-%02d",
                      cal.component(.year, from: now),
                      cal.component(.month, from: now),
                      cal.component(.day, from: now))
    }

    private var days: [String?] {
        var comps = DateComponents(year: year, month: month, day: 1)
        guard let first = cal.date(from: comps) else { return [] }
        let weekday = cal.component(.weekday, from: first) - 1
        let range = cal.range(of: .day, in: .month, for: first) ?? 1..<31
        var result: [String?] = Array(repeating: nil, count: weekday)
        for d in range {
            result.append(String(format: "%04d-%02d-%02d", year, month, d))
        }
        return result
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: onPrev) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(theme.fyAccent)
                        .frame(width: 32, height: 32)
                        .background(theme.fyCardSub, in: Circle())
                }
                Spacer()
                Text("\(String(year))年\(month)月")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(theme.fyAccent)
                        .frame(width: 32, height: 32)
                        .background(theme.fyCardSub, in: Circle())
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(weekdays, id: \.self) { wd in
                    Text(wd).font(.system(size: 11)).foregroundColor(theme.textDim)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, dateStr in
                    if let dateStr {
                        let day = Int(dateStr.suffix(2)) ?? 0
                        let isToday = dateStr == todayStr
                        let isSelected = dateStr == selectedDate
                        let hasDot = dotDates.contains(dateStr)
                        let isPeriod = periodDates[dateStr] != nil
                        let count = counts[dateStr] ?? 0

                        Button { onSelect(dateStr) } label: {
                            VStack(spacing: 1) {
                                Text("\(day)")
                                    .font(.system(size: 13, weight: isToday ? .bold : .medium, design: .serif))
                                Text(count > 0 ? "\(count)篇" : " ")
                                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                                    .foregroundColor(theme.textDim)
                            }
                            .foregroundColor(isToday ? .white : theme.text)
                            .frame(maxWidth: .infinity, minHeight: 39)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(isToday
                                          ? theme.fyAccent
                                          : theme.fyAccent.opacity(count > 0 ? min(0.08 + Double(count) * 0.035, 0.24) : (isPeriod ? 0.08 : 0.015)))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(isSelected ? theme.fyAccent : .clear, lineWidth: 1.5)
                            )
                            .overlay(alignment: .topTrailing) {
                                Circle().fill(hasDot ? theme.fyAccent : .clear)
                                    .frame(width: 4, height: 4).padding(4)
                            }
                        }
                    } else {
                        Color.clear.frame(height: 39)
                    }
                }
            }
        }
        .padding(14).foyerCard(theme)
    }
}

// MARK: - 陈璟的活动房间

// MARK: - Calendar (纪念日+日记)


// MARK: - 私人书房

private struct FictionBook: Identifiable, Decodable, Hashable {
    let id: String
    let title: String
    let author: String
    let status: String
    let updatedAt: String?
    let tagline: String?
    let chapterCount: Int
    let progress: FictionProgress?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, author, status, tagline
        case updatedAt = "updated_at"
        case chapterCount = "chapter_count"
        case progress
        case createdAt = "created_at"
    }
}

private struct FictionProgress: Decodable, Hashable {
    let chapter: Int
    let offset: Int
    let updatedAt: String?
    enum CodingKeys: String, CodingKey { case chapter, offset; case updatedAt = "updated_at" }
}

private struct FictionTOCItem: Decodable, Hashable {
    let n: Int
    let title: String
    let chars: Int
    let ts: String?
}

private struct FictionBookDetail: Decodable {
    let id: String
    let title: String
    let author: String
    let tagline: String?
    let status: String
    let createdAt: String?
    let updatedAt: String?
    let toc: [FictionTOCItem]
    let progress: FictionProgress?
    enum CodingKeys: String, CodingKey {
        case id, title, author, tagline, status, toc, progress
        case createdAt = "created_at"; case updatedAt = "updated_at"
    }
}

private struct FictionChapter: Decodable {
    let n: Int
    let title: String
    let content: String
}

private struct FictionAnnotation: Identifiable, Decodable {
    let id: String
    let chapter: Int
    let quote: String
    let note: String
    let ts: String?

    enum CodingKeys: String, CodingKey {
        case id, chapter, quote, note, ts
    }
}

@MainActor
private final class FictionStudyModel: ObservableObject {
    @Published var books: [FictionBook] = []
    @Published var loading = false
    @Published var error: String?

    func load() async {
        loading = true
        defer { loading = false }
        do {
            let (data, response) = try await AlcoveAPI.session.data(from: AlcoveAPI.fullURL("/api/fiction/books"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            if let wrapped = try? JSONDecoder().decode(FictionBooksEnvelope.self, from: data) {
                books = wrapped.books
            } else {
                books = try JSONDecoder().decode([FictionBook].self, from: data)
            }
            error = nil
        } catch {
            books = []
            self.error = "书房后端还在铺木地板"
        }
    }

    func detail(bookID: String) async throws -> FictionBookDetail {
        var components = URLComponents(url: AlcoveAPI.fullURL("/api/fiction/book"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: bookID)]
        let (data, response) = try await AlcoveAPI.session.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(FictionBookEnvelope.self, from: data).book
    }

    func chapter(bookID: String, index: Int) async throws -> FictionChapter {
        var components = URLComponents(url: AlcoveAPI.fullURL("/api/fiction/chapter"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: bookID), URLQueryItem(name: "n", value: "\(index)")]
        let (data, response) = try await AlcoveAPI.session.data(
            from: components.url!
        )
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(FictionChapterEnvelope.self, from: data).chapter
    }

    func annotations(bookID: String, chapter: Int? = nil) async -> [FictionAnnotation] {
        var components = URLComponents(url: AlcoveAPI.fullURL("/api/fiction/annotations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: bookID)]
        guard let (data, response) = try? await AlcoveAPI.session.data(
            from: components.url!
        ), (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        let all = (try? JSONDecoder().decode(FictionAnnotationsEnvelope.self, from: data).annotations) ?? []
        return chapter.map { value in all.filter { $0.chapter == value } } ?? all
    }

    func saveProgress(bookID: String, chapter: Int) async {
        var request = URLRequest(url: AlcoveAPI.fullURL("/api/fiction/progress"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["book_id": bookID, "chapter": chapter, "offset": 0])
        _ = try? await AlcoveAPI.session.data(for: request)
    }

    func annotate(bookID: String, chapter: Int, text: String, note: String) async throws {
        var request = URLRequest(url: AlcoveAPI.fullURL("/api/fiction/annotation"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "book_id": bookID, "chapter": chapter, "quote": text, "note": note
        ])
        let (_, response) = try await AlcoveAPI.session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    }

    private struct FictionBooksEnvelope: Decodable { let books: [FictionBook] }
    private struct FictionBookEnvelope: Decodable { let book: FictionBookDetail }
    private struct FictionChapterEnvelope: Decodable { let chapter: FictionChapter }
    private struct FictionAnnotationsEnvelope: Decodable { let annotations: [FictionAnnotation] }
}

private struct NativeFictionStudyView: View {
    @StateObject private var model = FictionStudyModel()
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = "dark"
    @State private var section = "serializing"
    @State private var selectedBook: FictionBook?
    @State private var selectedChapter: Int?
    @State private var showQuotes = false
    private var colors: PastelColors { _ = houseAppearance; return PastelColors(dark: AlcoveAppearance.isDark) }
    private var theme: AlcoveTheme { .pastelPaper(dark: colors.dark) }
    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0 }
    private let perRow = 6

    private var visibleBooks: [FictionBook] {
        model.books.filter { $0.status == section }
    }

    private var rows: [[FictionBook]] {
        stride(from: 0, to: visibleBooks.count, by: perRow).map {
            Array(visibleBooks[$0..<min($0 + perRow, visibleBooks.count)])
        }
    }

    /// 上次读到的那本：进度最新的一本
    private var lastRead: FictionBook? {
        model.books.filter { $0.progress != nil }
            .max { ($0.progress?.updatedAt ?? "") < ($1.progress?.updatedAt ?? "") }
    }

    var body: some View {
        ZStack {
            PastelPaperBackground(colors: colors)
            if showQuotes {
                FictionQuotesView(model: model, books: model.books) { showQuotes = false }
                    .padding(.top, max(safeTop, 20))
            } else if let book = selectedBook, let chapter = selectedChapter {
                FictionReaderView(book: book, chapterIndex: chapter, model: model) {
                    selectedChapter = nil
                }
                .padding(.top, max(safeTop, 20))
            } else if let book = selectedBook {
                FictionBookView(book: book, model: model, onBack: {
                    selectedBook = nil
                }, onChapter: { selectedChapter = $0 })
                .padding(.top, max(safeTop, 20))
            } else {
                shelf
            }
        }
        .foregroundColor(colors.ink)
        .task { await model.load() }
    }

    // 0927 她挑的：排版照旧（两层书架、底下「上次读到」），书换成乙——淡色纯色书脊、白字、白色小图
    private var shelf: some View {
        PastelRoom(colors: colors, caps: "a shelf of our own", title: "书房", framed: true,
                   subtitle: section == "serializing" ? "still being written" : "kept on the shelf") {
            VStack(spacing: 0) {
                HStack(spacing: 26) {
                    segment("连载中", value: "serializing")
                    segment("已完结", value: "completed")
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .trailing) {
                    Button { showQuotes = true } label: {
                        HStack(spacing: 3) {
                            Text("摘句册")
                            Text("❞")
                        }
                        .font(.system(size: 12, design: .serif))
                        .foregroundColor(colors.dim)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 22)
                }
                .padding(.top, 12)

                if model.loading {
                    Spacer(); ProgressView().tint(colors.dim); Spacer()
                } else if visibleBooks.isEmpty {
                    emptyShelf
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 22) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                                shelfRow(row, start: r * perRow)
                            }
                            if let book = lastRead { lastReadCard(book) }
                        }
                        .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 40)
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            PastelSprig(colors: colors, seed: 1).frame(width: 46, height: 110).offset(x: -4, y: 150)
        }
        .overlay(alignment: .topTrailing) {
            PastelSprig(colors: colors, seed: 2).frame(width: 46, height: 110).scaleEffect(x: -1).offset(x: 4, y: 170)
        }
    }

    private func shelfRow(_ row: [FictionBook], start: Int) -> some View {
        let current = lastRead?.id
        return VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(row.enumerated()), id: \.element.id) { i, book in
                    Button { selectedBook = book } label: {
                        FictionSpine(book: book, offset: start + i, colors: colors, current: book.id == current)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: colors.dark
                                     ? [Color(red: 0.23, green: 0.24, blue: 0.29), Color(red: 0.17, green: 0.18, blue: 0.22)]
                                     : [.white, Color(red: 0.89, green: 0.905, blue: 0.945)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: 9)
                .shadow(color: Color(red: 0.24, green: 0.27, blue: 0.43).opacity(colors.dark ? 0.5 : 0.25), radius: 5, y: 4)
        }
    }

    private func lastReadCard(_ book: FictionBook) -> some View {
        let ch = book.progress?.chapter ?? 0
        let left = max(0, book.chapterCount - ch)
        return Button {
            selectedBook = book
            if ch > 0 { selectedChapter = ch }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("LAST READ").font(PastelFont.caps(9)).tracking(3.5).foregroundColor(colors.dim)
                Text("\(book.title) · 第 \(ch) 章").font(WindowFont.swiftUI(15.5, bold: true)).lineLimit(1)
                Text(left > 0 ? "还有 \(left) 章你没看过" : "已经跟上他写的了")
                    .font(.system(size: 12, design: .serif)).foregroundColor(colors.dim)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(colors.rule)
                        Rectangle().fill(colors.lilac)
                            .frame(width: geo.size.width * CGFloat(book.chapterCount > 0 ? Double(ch) / Double(book.chapterCount) : 0))
                    }
                }
                .frame(height: 2)
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.vertical, 14)
            .foyerCard(theme)
        }
        .buttonStyle(.plain)
    }

    private func segment(_ title: String, value: String) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.18)) { section = value } } label: {
            Text(title)
                .font(.system(size: 13.5, design: .serif))
                .foregroundColor(section == value ? colors.ink : colors.dim)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(colors.ink).frame(height: 1).opacity(section == value ? 1 : 0)
                }
        }.buttonStyle(.plain)
    }

    private var emptyShelf: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.system(size: 42, weight: .ultraLight))
                .foregroundColor(colors.dim)
            Text(section == "serializing" ? "书架还空着" : "还没有写完的书")
                .font(WindowFont.swiftUI(20, bold: true))
            Text(model.error ?? "陈璟写下第一章后，它会从这里长出来")
                .font(.system(size: 12, design: .serif)).foregroundColor(colors.dim)
            Text("waiting for the first page").font(PastelFont.script(20)).foregroundColor(colors.dim)
            Spacer()
        }.padding(.bottom, 40)
    }
}

/// 书脊（乙）：淡色纯色、白字竖排、下面一个白色细线小图、上下两道白线；有新章节顶上一个小红点，正在读的那本垂一根丝带
private struct FictionSpine: View {
    let book: FictionBook
    let offset: Int
    let colors: PastelColors
    var current = false

    private static let emblems = ["moon", "heart", "star", "camera.macro", "leaf", "sparkle"]

    private var width: CGFloat { CGFloat(38 + (offset * 7) % 12) }
    private var height: CGFloat { CGFloat(172 + (offset * 37) % 50) }
    private var unread: Bool {
        guard let p = book.progress else { return false }
        return book.chapterCount > p.chapter
    }

    var body: some View {
        let chars = Array(book.title)
        let maxChars = max(2, Int((height - 78) / 18))
        let shown = chars.count > maxChars ? Array(chars.prefix(maxChars - 1)) + ["…"] : chars
        VStack(spacing: 0) {
            Rectangle().fill(Color.white.opacity(0.55)).frame(height: 1).padding(.horizontal, 5).padding(.top, 8)
            VStack(spacing: 1) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, ch in
                    Text(String(ch))
                }
            }
            .font(WindowFont.swiftUI(13.5, bold: true))
            .foregroundColor(.white)
            .shadow(color: Color(red: 0.24, green: 0.27, blue: 0.43).opacity(0.25), radius: 1, y: 1)
            .padding(.top, 10)
            Spacer(minLength: 4)
            Image(systemName: Self.emblems[offset % Self.emblems.count])
                .font(.system(size: 12, weight: .light))
                .foregroundColor(.white.opacity(0.9))
            Rectangle().fill(Color.white.opacity(0.55)).frame(height: 1).padding(.horizontal, 5).padding(.top, 8)
            Text(book.status == "completed" ? "完" : "\(book.chapterCount)")
                .font(.system(size: 9, design: .serif))
                .foregroundColor(.white.opacity(0.85))
                .padding(.vertical, 6)
        }
        .frame(width: width, height: height)
        .background(
            LinearGradient(colors: [.white.opacity(0.18), .clear, .clear, Color(red: 0.24, green: 0.27, blue: 0.43).opacity(0.10)],
                           startPoint: .leading, endPoint: .trailing)
        )
        .background(colors.books[offset % colors.books.count])
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 2,
                                          bottomTrailingRadius: 2, topTrailingRadius: 4))
        .brightness(colors.dark ? -0.16 : 0)
        .shadow(color: Color(red: 0.24, green: 0.27, blue: 0.43).opacity(0.22), radius: 3, x: 1, y: 3)
        .overlay(alignment: .topTrailing) {
            if unread {
                Circle().fill(colors.cherry).frame(width: 7, height: 7)
                    .overlay(Circle().stroke(colors.paper, lineWidth: 2))
                    .offset(x: 3, y: -4)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if current {
                Rectangle().fill(colors.cherry.opacity(0.9))
                    .frame(width: 5, height: 16)
                    .mask(
                        Path { p in
                            p.move(to: .zero); p.addLine(to: CGPoint(x: 5, y: 0)); p.addLine(to: CGPoint(x: 5, y: 16))
                            p.addLine(to: CGPoint(x: 2.5, y: 12.5)); p.addLine(to: CGPoint(x: 0, y: 16)); p.closeSubpath()
                        }
                    )
                    .offset(x: 8, y: 13)
            }
        }
        .accessibilityLabel(book.title)
    }
}

private struct FictionBookView: View {
    let book: FictionBook
    @ObservedObject var model: FictionStudyModel
    let onBack: () -> Void
    let onChapter: (Int) -> Void
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = "dark"
    @State private var detail: FictionBookDetail?
    private var colors: PastelColors { _ = houseAppearance; return PastelColors(dark: AlcoveAppearance.isDark) }
    private var theme: AlcoveTheme { .pastelPaper(dark: colors.dark) }

    private var coverColor: Color {
        var h: UInt32 = 2166136261
        for b in book.id.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return colors.books[Int(h % UInt32(colors.books.count))]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundColor(colors.dim)
                Spacer()
                Text("CHAPTER ONE OF MANY").font(PastelFont.caps(9)).tracking(3.5).foregroundColor(colors.dim)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }.padding(.horizontal, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // 精装封面：淡色布面、一圈白色细框、白字书名
                    VStack(spacing: 14) {
                        Text(book.title)
                            .font(WindowFont.swiftUI(24, bold: true)).tracking(5)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)
                        Text("陈 璟 著").font(.system(size: 10.5, design: .serif)).tracking(4)
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding(.horizontal, 26)
                    .frame(width: 196, height: 270)
                    .background(coverColor)
                    .overlay(Rectangle().stroke(Color.white.opacity(0.7), lineWidth: 1).padding(14))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2,
                                                      bottomTrailingRadius: 8, topTrailingRadius: 8))
                    .brightness(colors.dark ? -0.16 : 0)
                    .shadow(color: Color(red: 0.24, green: 0.27, blue: 0.43).opacity(0.28), radius: 12, x: 6, y: 10)
                    .padding(.top, 18)

                    if let tagline = book.tagline, !tagline.isEmpty {
                        Text(tagline).font(PastelFont.script(21))
                            .foregroundColor(colors.dim).multilineTextAlignment(.center)
                            .padding(.horizontal, 24).padding(.top, 18)
                    }
                    Text(statusLine).font(PastelFont.caps(9.5)).tracking(3.5).foregroundColor(colors.dim)
                        .padding(.top, 8)

                    Text("chapters").font(PastelFont.script(22)).foregroundColor(colors.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 22)

                    if let detail {
                        let read = detail.progress?.chapter ?? 0
                        ForEach(detail.toc, id: \.n) { item in
                            Button { onChapter(item.n) } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(item.n)").font(.system(size: 12, design: .serif)).italic()
                                        .foregroundColor(colors.dim).frame(width: 22, alignment: .leading)
                                    Text(item.title).font(WindowFont.swiftUI(14.5)).lineLimit(1)
                                    DottedLeader(color: colors.faint)
                                    if item.n == read {
                                        Text("读到这").font(.system(size: 10, design: .serif)).foregroundColor(colors.cherry)
                                    } else if item.n > read {
                                        Circle().fill(colors.cherry).frame(width: 5, height: 5)
                                    }
                                    Text("\(item.chars)").font(.system(size: 10.5, design: .serif))
                                        .foregroundColor(colors.dim)
                                }
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    } else { ProgressView().tint(colors.dim).frame(maxWidth: .infinity).padding(30) }
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 40)
            }
        }
        .foregroundColor(colors.ink)
        .task { detail = try? await model.detail(bookID: book.id) }
    }

    private var statusLine: String {
        let ch = detail?.progress?.chapter ?? book.progress?.chapter ?? 0
        let base = book.status == "completed" ? "completed · \(book.chapterCount) chapters"
                                              : "serializing · \(book.chapterCount) chapters"
        return ch > 0 ? base + " · read to \(ch)" : base
    }
}

/// 目录里连到字数的那条点点引线
private struct DottedLeader: View {
    let color: Color
    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: geo.size.height - 3))
                p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height - 3))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
        }
        .frame(height: 10)
    }
}

private struct FictionReaderView: View {
    let book: FictionBook
    let chapterIndex: Int
    @ObservedObject var model: FictionStudyModel
    let onBack: () -> Void
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @State private var chapter: FictionChapter?
    @State private var annotations: [FictionAnnotation] = []
    @State private var selectedQuote = ""
    @State private var review = ""
    @State private var showReview = false
    @State private var showReadingSettings = false
    @State private var selectingAnnotations = false
    @State private var selectedAnnotations: Set<String> = []
    @State private var sendingAnnotations = false
    @State private var error: String?
    @AppStorage("fictionFontSize") private var fontSize = 17.0
    @AppStorage("fictionLetterSpacing") private var letterSpacing = 0.4
    @AppStorage("fictionLineSpacing") private var lineSpacing = 9.0
    @AppStorage("fictionReadingMode") private var readingMode = "vertical"
    // 0927 书房换蓝粉白纸页，阅读页和摘句册跟着换
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = "dark"
    private var theme: AlcoveTheme { _ = houseAppearance; return .pastelPaper(dark: AlcoveAppearance.isDark) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 28, height: 34)
                }.buttonStyle(.plain)
                Text(chapter?.title ?? "正在翻页")
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .lineLimit(1)
                Spacer()
                Button { showReadingSettings = true } label: {
                    Label("阅读设置", systemImage: "textformat.size")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.textDim)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 18).padding(.vertical, 9)

            Group {
            if let chapter {
                if readingMode == "horizontal" {
                    TabView {
                        ForEach(Array(readingPages(chapter.content).enumerated()), id: \.offset) { _, page in
                            ScrollView {
                                FictionSelectableText(text: page, fontSize: fontSize,
                                                      letterSpacing: letterSpacing, lineSpacing: lineSpacing) { quote in
                                    selectedQuote = quote; review = ""; showReview = true
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 22).padding(.vertical, 18)
                            }
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                } else {
                    ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(chapter.title).font(.system(size: 25, weight: .semibold, design: .serif))
                        FictionSelectableText(text: chapter.content, fontSize: fontSize,
                                              letterSpacing: letterSpacing, lineSpacing: lineSpacing) { quote in
                            selectedQuote = quote; review = ""; showReview = true
                        }
                        .frame(maxWidth: .infinity, minHeight: 360, alignment: .leading)
                        if !annotations.isEmpty {
                            HStack {
                                Text("你的划线").font(.system(size: 14, weight: .semibold, design: .serif))
                                Spacer()
                                if selectingAnnotations {
                                    Button("取消") {
                                        selectingAnnotations = false
                                        selectedAnnotations.removeAll()
                                    }.font(.system(size: 11))
                                }
                            }
                            ForEach(annotations) { item in
                                HStack(alignment: .top, spacing: 10) {
                                    if selectingAnnotations {
                                        Image(systemName: selectedAnnotations.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(theme.fyAccent).font(.system(size: 19))
                                    }
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text("“\(item.quote)”").font(.system(size: 13, design: .serif)).foregroundColor(theme.textDim)
                                        Text(item.note).font(.system(size: 13))
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(13).contentShape(Rectangle()).foyerCard(theme)
                                .onTapGesture {
                                    if selectingAnnotations { toggleAnnotation(item) }
                                }
                                .onLongPressGesture {
                                    selectingAnnotations = true
                                    selectedAnnotations.insert(item.id)
                                }
                            }
                            if selectingAnnotations {
                                Button { Task { await sendSelectedAnnotations() } } label: {
                                    Label(sendingAnnotations ? "正在发送" : "合并发送给陈璟（\(selectedAnnotations.count)）",
                                          systemImage: "paperplane.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .frame(maxWidth: .infinity).frame(height: 44)
                                }
                                .buttonStyle(.borderedProminent).tint(theme.fyAccent)
                                .disabled(selectedAnnotations.isEmpty || sendingAnnotations)
                            }
                        }
                    }.padding(20)
                }
                }
            } else if let error {
                ContentUnavailableView("这一章还没递过来", systemImage: "book.closed", description: Text(error))
            } else { ProgressView() }
            }
        }
        .foregroundColor(theme.text)
        .task {
            do {
                chapter = try await model.chapter(bookID: book.id, index: chapterIndex)
                annotations = await model.annotations(bookID: book.id, chapter: chapterIndex)
                await model.saveProgress(bookID: book.id, chapter: chapterIndex)
            } catch { self.error = "等独立书房接口接通后就能读" }
        }
        .sheet(isPresented: $showReview) {
            NavigationStack {
                Form {
                    Section("划线") { Text(selectedQuote).font(.system(size: 14, design: .serif)) }
                    Section("写给这句话") { TextEditor(text: $review).frame(minHeight: 120) }
                }
                .navigationTitle("书评")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showReview = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("存下") {
                            Task {
                                try? await model.annotate(bookID: book.id, chapter: chapterIndex,
                                                          text: selectedQuote, note: review)
                                annotations = await model.annotations(bookID: book.id, chapter: chapterIndex)
                                showReview = false
                            }
                        }.disabled(review.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $showReadingSettings) {
            ReadingSettingsSheet(fontSize: $fontSize, letterSpacing: $letterSpacing, lineSpacing: $lineSpacing,
                                 readingMode: $readingMode, theme: theme)
                .presentationDetents([.height(365)])
                .presentationDragIndicator(.visible)
        }
    }

    private func readingPages(_ content: String) -> [String] {
        let paragraphs = content.components(separatedBy: "\n\n").filter { !$0.isEmpty }
        var pages: [String] = [], current = ""
        for paragraph in paragraphs {
            if current.count + paragraph.count > 900, !current.isEmpty {
                pages.append(current); current = paragraph
            } else {
                current += (current.isEmpty ? "" : "\n\n") + paragraph
            }
        }
        if !current.isEmpty { pages.append(current) }
        return pages.isEmpty ? [content] : pages
    }

    private func toggleAnnotation(_ item: FictionAnnotation) {
        if selectedAnnotations.contains(item.id) { selectedAnnotations.remove(item.id) }
        else { selectedAnnotations.insert(item.id) }
    }

    @MainActor private func sendSelectedAnnotations() async {
        let picked = annotations.filter { selectedAnnotations.contains($0.id) }
        guard !picked.isEmpty else { return }
        sendingAnnotations = true
        defer { sendingAnnotations = false }
        let payload: [String: Any] = [
            "book": book.title,
            "author": book.author,
            "quotes": picked.map { ["chapter": $0.chapter, "text": $0.quote,
                                     "note": $0.note, "time": $0.ts ?? ""] }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        _ = try? await AlcoveAPI.send(text: "[READING_CARD]\(json)[/READING_CARD]")
        selectingAnnotations = false
        selectedAnnotations.removeAll()
    }
}

private struct ReadingSettingsSheet: View {
    @Binding var fontSize: Double
    @Binding var letterSpacing: Double
    @Binding var lineSpacing: Double
    @Binding var readingMode: String
    let theme: AlcoveTheme
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("reading room").font(.custom("Snell Roundhand", size: 24))
            HStack {
                Text("字号").font(.system(size: 13, weight: .medium))
                Slider(value: $fontSize, in: 14...24, step: 1)
                Text("\(Int(fontSize))").font(.system(size: 11, design: .monospaced)).frame(width: 24)
            }
            HStack {
                Text("字距").font(.system(size: 13, weight: .medium))
                Slider(value: $letterSpacing, in: 0...3, step: 0.25)
                Text(String(format: "%.1f", letterSpacing)).font(.system(size: 11, design: .monospaced)).frame(width: 28)
            }
            HStack {
                Text("行距").font(.system(size: 13, weight: .medium))
                Slider(value: $lineSpacing, in: 3...20, step: 1)
                Text("\(Int(lineSpacing))").font(.system(size: 11, design: .monospaced)).frame(width: 28)
            }
            Picker("翻页方式", selection: $readingMode) {
                Label("上下滑动", systemImage: "arrow.up.and.down").tag("vertical")
                Label("左右翻页", systemImage: "arrow.left.and.right").tag("horizontal")
            }.pickerStyle(.segmented)
            Text("长按正文仍可精确选字、划线并写书评")
                .font(.system(size: 10)).foregroundColor(theme.textDim)
        }
        .padding(22)
        .foregroundColor(theme.text)
    }
}

private struct FictionQuotesView: View {
    @ObservedObject var model: FictionStudyModel
    let books: [FictionBook]
    let onBack: () -> Void
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @State private var rows: [FictionQuoteRow] = []
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var sending = false
    // 0927 书房换蓝粉白纸页，阅读页和摘句册跟着换
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = "dark"
    private var theme: AlcoveTheme { _ = houseAppearance; return .pastelPaper(dark: AlcoveAppearance.isDark) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                        .frame(width: 28, height: 34)
                }.buttonStyle(.plain)
                Text("摘句册").font(.system(size: 14, weight: .semibold, design: .serif))
                Spacer()
                if selecting {
                    Button("取消") { selecting = false; selected.removeAll() }.font(.system(size: 11))
                }
            }.padding(.horizontal, 14).padding(.vertical, 6)
            Group {
            if rows.isEmpty {
                ContentUnavailableView("摘句册还是空的", systemImage: "quote.opening",
                                       description: Text("你划下第一句话后，会连着书评一起收在这里"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(rows) { row in
                            HStack(alignment: .top, spacing: 10) {
                                if selecting {
                                    Image(systemName: selected.contains(row.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(theme.fyAccent).font(.system(size: 19))
                                }
                            VStack(alignment: .leading, spacing: 8) {
                                Text("“\(row.annotation.quote)”")
                                    .font(.system(size: 14, design: .serif))
                                Text(row.annotation.note).font(.system(size: 13))
                                Text("《\(row.book.title)》 · 第 \(row.annotation.chapter) 章")
                                    .font(.system(size: 10)).foregroundColor(theme.textDim)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14).contentShape(Rectangle()).foyerCard(theme)
                                .onTapGesture { if selecting { toggle(row) } }
                                .onLongPressGesture { selecting = true; selected.insert(row.id) }
                        }
                    }.padding(18)
                }
            }
            if selecting {
                Button { Task { await sendSelected() } } label: {
                    Label(sending ? "正在发送" : "合并发送给陈璟（\(selected.count)）", systemImage: "paperplane.fill")
                        .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 46)
                }.buttonStyle(.borderedProminent).tint(theme.fyAccent).padding(.horizontal, 18).padding(.bottom, 10)
                    .disabled(selected.isEmpty || sending)
            }
            }
        }
        .foregroundColor(theme.text)
        .task {
            var gathered: [FictionQuoteRow] = []
            for book in books {
                let notes = await model.annotations(bookID: book.id)
                gathered.append(contentsOf: notes.map { FictionQuoteRow(book: book, annotation: $0) })
            }
            rows = gathered.sorted { ($0.annotation.ts ?? "") > ($1.annotation.ts ?? "") }
        }
    }

    private func toggle(_ row: FictionQuoteRow) {
        if selected.contains(row.id) { selected.remove(row.id) } else { selected.insert(row.id) }
    }

    @MainActor private func sendSelected() async {
        let picked = rows.filter { selected.contains($0.id) }
        guard !picked.isEmpty else { return }
        sending = true; defer { sending = false }
        let payload: [String: Any] = ["book": picked[0].book.title, "author": picked[0].book.author,
          "quotes": picked.map { ["chapter": $0.annotation.chapter, "text": $0.annotation.quote,
                                    "note": $0.annotation.note, "time": $0.annotation.ts ?? ""] }]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        _ = try? await AlcoveAPI.send(text: "[READING_CARD]\(json)[/READING_CARD]")
        selecting = false; selected.removeAll()
    }
}

private struct FictionQuoteRow: Identifiable {
    let book: FictionBook
    let annotation: FictionAnnotation
    var id: String { "\(book.id)-\(annotation.id)" }
}

/// 书房正文的轻量 Markdown 渲染：**粗**、*斜*、# 标题、--- 分隔、> 引用。
/// 只吃这几样，其余字符原样保留，划线取词拿到的也是去掉标记后的干净句子。
private enum FictionMarkdown {
    private static let bold = try! NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*")
    private static let italic = try! NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)([^*\\n]+?)\\*(?!\\*)")

    static func attributed(_ raw: String, fontSize: Double,
                           letterSpacing: Double, lineSpacing: Double) -> NSAttributedString {
        let body = NSMutableParagraphStyle()
        body.lineSpacing = lineSpacing
        body.paragraphSpacing = max(8, fontSize * 0.75)
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.lineSpacing = lineSpacing
        centered.paragraphSpacing = max(8, fontSize * 0.75)
        let quoted = NSMutableParagraphStyle()
        quoted.lineSpacing = lineSpacing
        quoted.paragraphSpacing = max(8, fontSize * 0.75)
        quoted.firstLineHeadIndent = fontSize
        quoted.headIndent = fontSize

        let out = NSMutableAttributedString()
        let lines = raw.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                out.append(NSAttributedString(string: "· · ·", attributes: [
                    .font: UIFont.systemFont(ofSize: fontSize),
                    .foregroundColor: UIColor.secondaryLabel,
                    .kern: max(letterSpacing, 5),
                    .paragraphStyle: centered
                ]))
            } else if let (level, title) = heading(trimmed) {
                let size = fontSize + (level == 1 ? 7 : level == 2 ? 4 : 2)
                out.append(inline(title, size: size, weight: .semibold, boldWeight: .heavy,
                                  color: .label, letterSpacing: letterSpacing, paragraph: body))
            } else if trimmed.hasPrefix("> ") || trimmed == ">" {
                let text = String(trimmed.dropFirst(trimmed == ">" ? 1 : 2))
                out.append(inline(text, size: fontSize, weight: .regular, boldWeight: .bold,
                                  color: .secondaryLabel, letterSpacing: letterSpacing, paragraph: quoted))
            } else {
                out.append(inline(line, size: fontSize, weight: .regular, boldWeight: .bold,
                                  color: .label, letterSpacing: letterSpacing, paragraph: body))
            }
            if index < lines.count - 1 {
                out.append(NSAttributedString(string: "\n", attributes: [
                    .font: UIFont.systemFont(ofSize: fontSize),
                    .paragraphStyle: body
                ]))
            }
        }
        return out
    }

    private static func heading(_ line: String) -> (Int, String)? {
        var level = 0
        var cursor = line.startIndex
        while cursor < line.endIndex, line[cursor] == "#", level < 6 {
            level += 1
            cursor = line.index(after: cursor)
        }
        guard level > 0, cursor < line.endIndex, line[cursor] == " " else { return nil }
        return (level, String(line[line.index(after: cursor)...]))
    }

    private static func inline(_ text: String, size: Double,
                               weight: UIFont.Weight, boldWeight: UIFont.Weight,
                               color: UIColor, letterSpacing: Double,
                               paragraph: NSParagraphStyle) -> NSAttributedString {
        let piece = NSMutableAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .kern: letterSpacing,
            .paragraphStyle: paragraph
        ])
        apply(bold, on: piece, font: UIFont.systemFont(ofSize: size, weight: boldWeight))
        apply(italic, on: piece, font: UIFont.italicSystemFont(ofSize: size))
        return piece
    }

    private static func apply(_ regex: NSRegularExpression,
                              on target: NSMutableAttributedString, font: UIFont) {
        let whole = NSRange(location: 0, length: target.length)
        for match in regex.matches(in: target.string, range: whole).reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let inner = NSMutableAttributedString(
                attributedString: target.attributedSubstring(from: match.range(at: 1)))
            inner.addAttribute(.font, value: font,
                               range: NSRange(location: 0, length: inner.length))
            target.replaceCharacters(in: match.range(at: 0), with: inner)
        }
    }
}

private struct FictionSelectableText: UIViewRepresentable {
    let text: String
    let fontSize: Double
    let letterSpacing: Double
    let lineSpacing: Double
    let onReview: (String) -> Void
    func makeUIView(context: Context) -> FictionTextView {
        let view = FictionTextView()
        view.isEditable = false
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.widthTracksTextView = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.textColor = .label
        view.onReview = onReview
        return view
    }
    func updateUIView(_ view: FictionTextView, context: Context) {
        view.attributedText = FictionMarkdown.attributed(text, fontSize: fontSize,
                                                         letterSpacing: letterSpacing,
                                                         lineSpacing: lineSpacing)
        view.onReview = onReview
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: FictionTextView,
                      context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let measured = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: measured.height)
    }
}

private final class FictionTextView: UITextView {
    var onReview: ((String) -> Void)?
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .context else { return }
        let action = UIAction(title: "划线并写书评", image: UIImage(systemName: "highlighter")) { [weak self] _ in
            guard let self, let range = selectedTextRange,
                  let quote = text(in: range)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !quote.isEmpty else { return }
            onReview?(quote)
        }
        builder.insertChild(UIMenu(options: .displayInline, children: [action]), atStartOfMenu: .standardEdit)
    }
}

// MARK: - 纸页（0927 她挑的蓝粉白版：书房 / Pulse / 乌有乡 共用）
// 她看了第一版说「太 AI 风了没有美感」（发光渐变、毛玻璃、霓虹），又说「不要再出现黄色」。
// 照她递的参考图：冷白的纸、几团很淡的水彩（粉 / 宝宝蓝 / 淡紫）、细颗粒，
// 手画的小花枝，中文宋体＋英文手写体＋字距拉开的小号大写。夜里是中性炭灰，不带棕。
// 这几间屋 ownsFullScreen，安全区问 app 主窗。

struct PastelColors {
    let dark: Bool
    private func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
    var paper: Color { dark ? c(0.110, 0.114, 0.137) : c(0.969, 0.973, 0.988) }
    var paper2: Color { dark ? c(0.082, 0.086, 0.106) : c(0.933, 0.945, 0.973) }
    var ink: Color { dark ? c(0.925, 0.933, 0.965) : c(0.184, 0.200, 0.278) }
    var dim: Color { dark ? c(0.620, 0.639, 0.722) : c(0.529, 0.553, 0.651) }
    var faint: Color { dark ? c(0.290, 0.306, 0.373) : c(0.812, 0.831, 0.890) }
    var rule: Color { dark ? c(0.86, 0.88, 0.96).opacity(0.11) : c(0.31, 0.35, 0.55).opacity(0.13) }
    var card: Color { dark ? c(0.149, 0.157, 0.188) : Color.white }
    var cherry: Color { dark ? c(0.941, 0.486, 0.612) : c(0.851, 0.361, 0.502) }
    var rose: Color { dark ? c(0.918, 0.659, 0.745) : c(0.922, 0.663, 0.749) }
    var blue: Color { dark ? c(0.616, 0.741, 0.902) : c(0.580, 0.714, 0.878) }
    var lilac: Color { dark ? c(0.765, 0.702, 0.910) : c(0.725, 0.651, 0.871) }
    var mint: Color { dark ? c(0.561, 0.753, 0.729) : c(0.612, 0.780, 0.757) }
    var mint2: Color { dark ? c(0.475, 0.671, 0.643) : c(0.435, 0.639, 0.612) }
    /// 书脊、封面用的淡色（乙方案：纯色＋白字＋白色小图）
    var books: [Color] {
        [c(0.918, 0.702, 0.776), c(0.663, 0.765, 0.902), c(0.780, 0.722, 0.902), c(0.659, 0.824, 0.800),
         c(0.949, 0.788, 0.839), c(0.722, 0.800, 0.902), c(0.863, 0.816, 0.941), c(0.749, 0.863, 0.839)]
    }
}

extension AlcoveTheme {
    /// 这三间屋自己的一套：卡片走纸张样式（isPaper），点缀色是樱桃粉
    static func pastelPaper(dark: Bool) -> AlcoveTheme {
        let p = PastelColors(dark: dark)
        return AlcoveTheme(
            isDark: dark, isPaper: true, usesWallImage: false,
            wallGradient: [p.paper, p.paper2],
            bubbleUser: p.rose, bubbleAI: p.card,
            text: p.ink, textDim: p.dim, textLight: p.dim.opacity(0.8), timestamp: p.dim,
            glassTint: p.card, glassBorder: p.rule,
            capsuleTint: p.card, capsuleBorder: p.rule,
            sendTop: p.cherry, sendBottom: p.cherry,
            fade: p.paper, splashBg: [p.paper, p.paper2],
            splashBarTop: p.cherry, splashBarBottom: p.cherry.opacity(0.8),
            splashGlowA: .clear, splashGlowB: .clear,
            splashPetal: p.rose.opacity(0.3), splashTitle: p.ink,
            fyAccent: p.cherry, fyAccentSoft: p.rose.opacity(0.22), fyCard: p.card,
            fyCardSub: dark ? p.paper2 : Color(red: 0.953, green: 0.957, blue: 0.980),
            fyBorder: p.rule,
            fyShadow: dark ? Color.black.opacity(0.35) : Color(red: 0.24, green: 0.27, blue: 0.43).opacity(0.14),
            fyFold: p.rule, fyDash: p.dim.opacity(0.3),
            panelTextureAsset: dark ? "PaperDark" : "PaperLight")
    }
}

/// 纸底：冷白 / 炭灰的底，几团晕开的淡水彩，一层细颗粒
struct PastelPaperBackground: View {
    let colors: PastelColors
    var spots: [(CGFloat, CGFloat, CGFloat, Int)] = [(0.15, 0.12, 170, 0), (0.85, 0.10, 150, 1), (0.5, 0.92, 220, 2)]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RadialGradient(colors: [colors.paper, colors.paper2], center: .top, startRadius: 0,
                               endRadius: geo.size.height * 0.9)
                ForEach(Array(spots.enumerated()), id: \.offset) { _, s in
                    Ellipse()
                        .fill([colors.rose, colors.blue, colors.lilac, colors.mint][s.3 % 4]
                            .opacity(colors.dark ? 0.16 : 0.26))
                        .frame(width: s.2 * 1.6, height: s.2)
                        .blur(radius: 46)
                        .position(x: geo.size.width * s.0, y: geo.size.height * s.1)
                }
                PastelGrain(dark: colors.dark)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// 细颗粒：固定种子撒点，画一次就不动了
struct PastelGrain: View {
    let dark: Bool
    var body: some View {
        Canvas { ctx, size in
            let n = Int(size.width * size.height / 90)
            for i in 0..<n {
                let d = Double(i)
                let x = DiaryTreeModel.rnd(d * 1.37) * size.width
                let y = DiaryTreeModel.rnd(d * 2.71 + 5) * size.height
                let a = 0.04 + DiaryTreeModel.rnd(d * 3.1) * 0.08
                ctx.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)),
                         with: .color((dark ? Color.white : Color.black).opacity(a)))
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

/// 手画的小花枝：一根弯茎、几片叶子、三朵小花（叶子薄荷青，花粉 / 紫，花心白）
struct PastelSprig: View {
    let colors: PastelColors
    var seed: Double = 1

    var body: some View {
        Canvas { ctx, size in
            let k = min(size.width / 70, size.height / 125)
            var g = ctx
            g.translateBy(x: 4 * k, y: size.height - 2)
            g.scaleBy(x: k, y: k)
            var stem = Path()
            stem.move(to: .zero)
            stem.addCurve(to: CGPoint(x: 38, y: -78), control1: CGPoint(x: 20, y: -18), control2: CGPoint(x: 34, y: -44))
            stem.addCurve(to: CGPoint(x: 64, y: -118), control1: CGPoint(x: 40, y: -96), control2: CGPoint(x: 52, y: -110))
            g.stroke(stem, with: .color(colors.mint2), lineWidth: 1.1)
            let leaves: [(CGFloat, CGFloat, Double)] = [(8, -10, 50), (18, -26, -100), (28, -44, 55), (34, -62, -90), (40, -86, 60), (52, -104, -85)]
            var leaf = Path()
            leaf.move(to: .zero)
            leaf.addCurve(to: CGPoint(x: 16, y: 0), control1: CGPoint(x: 4, y: -5), control2: CGPoint(x: 12, y: -6))
            leaf.addCurve(to: .zero, control1: CGPoint(x: 12, y: 6), control2: CGPoint(x: 4, y: 5))
            for l in leaves {
                var h = g
                h.translateBy(x: l.0, y: l.1)
                h.rotate(by: .degrees(l.2 + DiaryTreeModel.rnd(seed + l.2) * 10))
                h.fill(leaf, with: .color(colors.mint.opacity(0.55)))
                h.stroke(leaf, with: .color(colors.mint2), lineWidth: 0.6)
            }
            let flowers: [(CGFloat, CGFloat, Color)] = [(64, -118, colors.rose), (36, -70, colors.lilac), (22, -34, colors.rose)]
            for f in flowers {
                for i in 0..<5 {
                    let a = Double(i) * 1.256
                    let r = CGRect(x: f.0 + cos(a) * 3.2 - 2.8, y: f.1 + sin(a) * 3.2 - 2.8, width: 5.6, height: 5.6)
                    g.fill(Path(ellipseIn: r), with: .color(f.2.opacity(0.65)))
                }
                g.fill(Path(ellipseIn: CGRect(x: f.0 - 1.3, y: f.1 - 1.3, width: 2.6, height: 2.6)), with: .color(.white))
            }
        }
        .allowsHitTesting(false)
    }
}

/// 两头弯进去的小标签框（书房标题用）
struct PastelCartouche: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let m = r.height / 2, w = r.width, h = r.height, e: CGFloat = 14
        p.move(to: CGPoint(x: e, y: 1))
        p.addLine(to: CGPoint(x: w - e, y: 1))
        p.addQuadCurve(to: CGPoint(x: w - 1, y: m), control: CGPoint(x: w - e, y: m - 4))
        p.addQuadCurve(to: CGPoint(x: w - e, y: h - 1), control: CGPoint(x: w - e, y: m + 4))
        p.addLine(to: CGPoint(x: e, y: h - 1))
        p.addQuadCurve(to: CGPoint(x: 1, y: m), control: CGPoint(x: e, y: m + 4))
        p.addQuadCurve(to: CGPoint(x: e, y: 1), control: CGPoint(x: e, y: m - 4))
        p.closeSubpath()
        return p.offsetBy(dx: r.minX, dy: r.minY)
    }
}

enum PastelFont {
    /// 英文手写体（系统自带，不用另外打包）
    static func script(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "SnellRoundhand-Bold" : "SnellRoundhand", size: size)
    }
    /// 字距拉开的小号大写
    static func caps(_ size: CGFloat = 9) -> Font { .system(size: size, weight: .regular, design: .serif) }
}

/// 三间屋的外壳：纸底＋返回键＋小号大写一行＋标题（中文宋体或英文手写）＋一行手写小字
struct PastelRoom<Content: View>: View {
    let colors: PastelColors
    let caps: String
    let title: String
    var scriptTitle = false
    var framed = false
    var subtitle: String? = nil
    var onBack: (() -> Void)? = nil
    var trailing: AnyView? = nil
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0 }

    var body: some View {
        ZStack(alignment: .top) {
            PastelPaperBackground(colors: colors)
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    VStack(spacing: 2) {
                        if framed {
                            VStack(spacing: 1) {
                                Text(caps.uppercased()).font(PastelFont.caps(8.5)).tracking(3.5).foregroundColor(colors.dim)
                                Text(title).font(WindowFont.swiftUI(21, bold: true)).tracking(9).padding(.leading, 9)
                            }
                            .padding(.horizontal, 30).padding(.vertical, 8)
                            .background(PastelCartouche().fill(colors.card.opacity(0.7)))
                            .overlay(PastelCartouche().stroke(colors.dim.opacity(0.7), lineWidth: 0.8))
                            .overlay(PastelCartouche().inset(by: 4).stroke(colors.faint, lineWidth: 0.6))
                        } else {
                            Text(caps.uppercased()).font(PastelFont.caps(9)).tracking(3.5).foregroundColor(colors.dim)
                            if scriptTitle {
                                Text(title).font(PastelFont.script(42, bold: true))
                            } else {
                                Text(title).font(WindowFont.swiftUI(26, bold: true)).tracking(10).padding(.leading, 10)
                            }
                        }
                        if let subtitle {
                            Text(subtitle).font(PastelFont.script(22)).foregroundColor(colors.dim)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    HStack {
                        Button { if let onBack { onBack() } else { dismiss() } } label: {
                            Image(systemName: "chevron.left").font(.system(size: 17, weight: .medium))
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).foregroundColor(colors.dim).accessibilityLabel("返回")
                        Spacer()
                        if let trailing { trailing }
                    }
                    .padding(.horizontal, 8)
                }
                content()
            }
            .padding(.top, max(safeTop, 20))
        }
        .foregroundColor(colors.ink)
        .task { WindowFont.requestSongti() }
    }
}

extension PastelCartouche: InsettableShape {
    func inset(by amount: CGFloat) -> InsetCartouche { InsetCartouche(amount: amount) }
}

struct InsetCartouche: InsettableShape {
    var amount: CGFloat
    func path(in r: CGRect) -> Path { PastelCartouche().path(in: r.insetBy(dx: amount, dy: amount)) }
    func inset(by more: CGFloat) -> InsetCartouche { InsetCartouche(amount: amount + more) }
}

/// 方格纸（心率、八维那两张卡垫在底下）
struct PastelGraphPaper: View {
    let colors: PastelColors
    var step: CGFloat = 14
    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            var x: CGFloat = 0
            while x <= size.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y <= size.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            ctx.stroke(p, with: .color(colors.rule), lineWidth: 0.6)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 日记（0927 她挑的花树版）
// 她拿 Garden（一篇日记一枝杏花、夜里月亮、花瓣飘）和随笔阅读页当参考，我画了效果图她一轮轮改：
// 花瓣要、日夜跟全屋开关走；阅读页顶上是一整棵梅树，上清楚下渐虚，虚掉的那截垫在标题后面；
// 枝不许笔直（梅枝一节一节拐）。日历上写了日记的那天开一朵小花。
// 这间屋 ownsFullScreen，安全区问 app 主窗（见「全屏房间先做安全区」）。

private struct DiaryPalette {
    let dark: Bool
    private func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
    var paper: Color { dark ? c(0.075, 0.067, 0.094) : c(0.973, 0.949, 0.925) }
    var sky: Color { dark ? c(0.051, 0.043, 0.071) : c(0.953, 0.902, 0.918) }
    var ink: Color { dark ? c(0.925, 0.898, 0.882) : c(0.239, 0.204, 0.192) }
    var dim: Color { dark ? c(0.604, 0.569, 0.600) : c(0.561, 0.506, 0.482) }
    var faint: Color { dark ? c(0.357, 0.329, 0.376) : c(0.769, 0.714, 0.682) }
    var accent: Color { dark ? c(0.886, 0.663, 0.714) : c(0.788, 0.545, 0.592) }
    var card: Color { dark ? Color.white.opacity(0.06) : Color.white.opacity(0.62) }
    var line: Color { dark ? Color.white.opacity(0.10) : c(0.47, 0.35, 0.31).opacity(0.14) }
    var petal0: Color { dark ? Color.white : c(1.0, 0.980, 0.980) }
    var petal1: Color { dark ? c(1.0, 0.953, 0.961) : c(0.984, 0.890, 0.910) }
    var petal2: Color { dark ? c(0.941, 0.761, 0.800) : c(0.918, 0.702, 0.749) }
    /// 日历上的小花：夜里调暗，别盖住日期数字
    var bloomFill: Color { dark ? c(0.94, 0.706, 0.765).opacity(0.20) : petal1 }
    var bloomLine: Color { dark ? c(0.94, 0.706, 0.765).opacity(0.55) : petal2 }
    var branch: Color { dark ? c(0.369, 0.333, 0.349) : c(0.494, 0.388, 0.345) }
    var bark: Color { dark ? c(0.561, 0.522, 0.541) : c(0.427, 0.337, 0.298) }
    var stamen: Color { dark ? c(0.910, 0.788, 0.812) : c(0.788, 0.518, 0.561) }
    var anther: Color { dark ? c(0.953, 0.843, 0.659) : c(0.690, 0.337, 0.310) }
    var heart: Color { dark ? c(0.839, 0.604, 0.647) : c(0.722, 0.420, 0.447) }
    var bud: Color { dark ? c(0.914, 0.722, 0.765) : c(0.906, 0.635, 0.690) }
    var sepal: Color { dark ? c(0.490, 0.435, 0.451) : c(0.541, 0.357, 0.310) }
}

// MARK: 梅树（跟效果图同一套算法：固定种子，每次画出来一样）

private struct DP { var x: Double; var y: Double }

private struct DiaryTreeModel {
    struct Limb { var pts: [DP]; let w0: Double; let w1: Double; let seed: Double }
    struct Flower { let x: Double; let y: Double; let k: Double; let rot: Double; let open: Bool }
    struct Bud { let x: Double; let y: Double; let rot: Double; let k: Double }

    var limbs: [Limb] = []
    var far: [Limb] = []
    var flowers: [Flower] = []
    var farFlowers: [Flower] = []
    var buds: [Bud] = []

    static let shared = DiaryTreeModel()

    static func rnd(_ a: Double) -> Double {
        let x = sin(a * 9301 + 49297) * 233280
        return x - floor(x)
    }

    static func bez(_ p: [DP], _ t: Double) -> DP {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        let x = a * p[0].x + b * p[1].x + c * p[2].x + d * p[3].x
        let y = a * p[0].y + b * p[1].y + c * p[2].y + d * p[3].y
        return DP(x: x, y: y)
    }

    /// 梅枝不直：沿主线取几个节点左右交替折一下，再用平滑曲线串起来。主干只弯一点
    static func kink(_ p: [DP], seed: Double) -> [DP] {
        let K = 4
        let len = hypot(p[3].x - p[0].x, p[3].y - p[0].y)
        var nodes: [DP] = []
        for i in 0...K {
            let t = Double(i) / Double(K)
            let a = bez(p, max(0, t - 0.01)), b = bez(p, min(1, t + 0.01)), c = bez(p, t)
            let dx = b.x - a.x, dy = b.y - a.y
            let l = max(hypot(dx, dy), 0.0001)
            var amp = 0.0
            if i != 0 && i != K {
                let side: Double = i % 2 == 1 ? 1 : -1
                amp = side * (0.035 + rnd(seed * 31 + Double(i)) * 0.045) * len * (seed == 1 ? 0.4 : 1)
            }
            nodes.append(DP(x: c.x - dy / l * amp, y: c.y + dx / l * amp))
        }
        var out: [DP] = []
        for i in 0..<K {
            let p0 = nodes[max(0, i - 1)], p1 = nodes[i], p2 = nodes[i + 1], p3 = nodes[min(K, i + 2)]
            for j in 0..<6 {
                let t = Double(j) / 6
                out.append(DP(x: catmull(p0.x, p1.x, p2.x, p3.x, t), y: catmull(p0.y, p1.y, p2.y, p3.y, t)))
            }
        }
        out.append(nodes[K])
        return out
    }

    static func catmull(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ t: Double) -> Double {
        let t2 = t * t, t3 = t2 * t
        let p1 = 2 * b + (-a + c) * t
        let p2 = (2 * a - 5 * b + 4 * c - d) * t2
        let p3 = (-a + 3 * b - 3 * c + d) * t3
        return 0.5 * (p1 + p2 + p3)
    }

    static func at(_ k: [DP], _ t: Double) -> DP {
        let i = Int((min(1, max(0, t)) * Double(k.count - 1)).rounded())
        return k[i]
    }

    init() {
        func P(_ a: [(Double, Double)]) -> [DP] { a.map { DP(x: $0.0, y: $0.1) } }
        // (控制点, 粗, 细, 种子, 父枝, 在父枝的位置)
        let spec: [([(Double, Double)], Double, Double, Double, Int, Double)] = [
            ([(150, 345), (158, 290), (170, 240), (190, 195)], 20, 12, 1, -1, 0),
            ([(190, 195), (150, 130), (118, 60), (72, -40)], 11, 2.4, 2, 0, 1),
            ([(190, 195), (240, 135), (292, 60), (342, -78)], 10, 2.2, 3, 0, 1),
            ([(196, 188), (204, 120), (212, 40), (222, -88)], 7, 1.6, 4, 0, 0.96),
            ([(142, 112), (104, 98), (64, 92), (18, 70)], 4.5, 1.2, 5, 1, 0.33),
            ([(262, 100), (306, 98), (352, 112), (418, 80)], 4.5, 1.2, 6, 2, 0.37),
            ([(120, 58), (140, 30), (150, 5), (168, -20)], 3, 1, 7, 1, 0.6),
            ([(292, 60), (270, 30), (262, 5), (248, -22)], 3, 1, 8, 2, 0.6),
            ([(-30, 210), (20, 180), (60, 150), (96, 142)], 6, 2, 9, -1, 0),
            ([(60, 150), (50, 120), (46, 100), (30, 80)], 2.5, 0.9, 10, 8, 0.75),
            ([(212, 40), (236, 25), (252, 8), (270, -4)], 2.2, 0.8, 11, 3, 0.5),
        ]
        // 小枝从大枝折过之后的真位置长出来，不悬空
        for s in spec {
            var pts = P(s.0)
            if s.4 >= 0 { pts[0] = Self.at(limbs[s.4].pts, s.5) }
            limbs.append(Limb(pts: Self.kink(pts, seed: s.3), w0: s.1, w1: s.2, seed: s.3))
        }
        // 花沿着枝长：越往梢越密；一部分是花苞
        for (li, l) in limbs.enumerated() where li > 0 {
            let n = li < 4 ? 7 : 4
            let sd = l.seed
            for q in 0..<n {
                let qd = Double(q)
                let t = 0.35 + 0.65 * qd / Double(n - 1) + (Self.rnd(sd * 7 + qd) - 0.5) * 0.08
                let c = Self.at(l.pts, t)
                let off = (Self.rnd(sd * 13 + qd) - 0.5) * 14
                let k = 0.55 + Self.rnd(sd * 3 + qd) * 0.55
                if Self.rnd(sd * 5 + qd) < 0.22 {
                    buds.append(Bud(x: c.x + off, y: c.y - 4, rot: Self.rnd(qd + sd) * 360, k: 0.8 + Self.rnd(qd) * 0.3))
                } else {
                    let dy = (Self.rnd(sd + qd * 2) - 0.5) * 10
                    flowers.append(Flower(x: c.x + off, y: c.y + dy, k: k, rot: Self.rnd(sd * qd + 1) * 360,
                                          open: Self.rnd(sd * 11 + qd) > 0.25))
                }
            }
        }
        // 远处虚掉的两枝和几朵，画面有远近
        far = [
            Limb(pts: Self.kink(P([(430, 120), (380, 90), (340, 40), (300, -40)]), seed: 17), w0: 6, w1: 1.5, seed: 17),
            Limb(pts: Self.kink(P([(-20, 60), (30, 40), (70, 0), (90, -60)]), seed: 18), w0: 5, w1: 1.5, seed: 18),
        ]
        let ff: [(Double, Double, Double, Double)] = [(330, 10, 1.1, 20), (360, 70, 1, 60), (300, -30, 1, 10),
                                                      (60, 20, 1, 80), (80, -40, 0.9, 30), (20, 50, 1, 0)]
        farFlowers = ff.map { Flower(x: $0.0, y: $0.1, k: $0.2, rot: $0.3, open: true) }
    }
}

/// 一层梅树。坐标系跟效果图一样：宽 420、y 从 -100 到 360
private struct DiaryTreeLayer: View {
    let palette: DiaryPalette
    var farOnly = false

    var body: some View {
        Canvas { ctx, size in
            let k = size.width / 420
            var g = ctx
            g.scaleBy(x: k, y: k)
            g.translateBy(x: 0, y: 100)
            let m = DiaryTreeModel.shared
            if farOnly {
                for l in m.far { drawLimb(&g, l) }
                for f in m.farFlowers { drawFlower(&g, f) }
                return
            }
            for l in m.limbs { drawLimb(&g, l) }
            for f in m.flowers { drawFlower(&g, f) }
            for b in m.buds { drawBud(&g, b) }
        }
    }

    private func drawLimb(_ g: inout GraphicsContext, _ l: DiaryTreeModel.Limb) {
        let pts = l.pts
        let n = pts.count - 1
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0...n {
            let t = Double(i) / Double(n)
            let a = pts[max(0, i - 1)], b = pts[min(n, i + 1)], c = pts[i]
            let dx = b.x - a.x, dy = b.y - a.y
            let len = max(hypot(dx, dy), 0.0001)
            let wob = 1 + (DiaryTreeModel.rnd(l.seed + Double(i)) - 0.5) * 0.3
            let w = (l.w0 + (l.w1 - l.w0) * pow(t, 0.8)) * wob / 2
            left.append(CGPoint(x: c.x - dy / len * w, y: c.y + dx / len * w))
            right.append(CGPoint(x: c.x + dy / len * w, y: c.y - dx / len * w))
        }
        var path = Path()
        path.addLines(left + right.reversed())
        path.closeSubpath()
        g.fill(path, with: .color(palette.branch))
        // 树皮上几道细纹
        var i = 3
        while i < n - 3 {
            let c = pts[i]
            let t = Double(i) / Double(n)
            var p = Path()
            let y = c.y + l.w0 * 0.18 * (1 - t)
            p.move(to: CGPoint(x: c.x - 2, y: y))
            p.addQuadCurve(to: CGPoint(x: c.x + 4, y: y), control: CGPoint(x: c.x + 1, y: y - 1))
            g.stroke(p, with: .color(palette.bark.opacity(0.5)), lineWidth: 0.7)
            i += 4
        }
    }

    private static let petal: Path = {
        var p = Path()
        p.move(to: .zero)
        p.addCurve(to: CGPoint(x: -4, y: -17), control1: CGPoint(x: -7, y: -3), control2: CGPoint(x: -9, y: -13))
        p.addCurve(to: CGPoint(x: 0, y: -15), control1: CGPoint(x: -2, y: -18), control2: CGPoint(x: -1, y: -16))
        p.addCurve(to: CGPoint(x: 4, y: -17), control1: CGPoint(x: 1, y: -16), control2: CGPoint(x: 2, y: -18))
        p.addCurve(to: .zero, control1: CGPoint(x: 9, y: -13), control2: CGPoint(x: 7, y: -3))
        p.closeSubpath()
        return p
    }()

    private func drawFlower(_ g: inout GraphicsContext, _ f: DiaryTreeModel.Flower) {
        var h = g
        h.translateBy(x: f.x, y: f.y)
        h.rotate(by: .degrees(f.rot))
        h.scaleBy(x: f.k, y: f.k)
        let shade = GraphicsContext.Shading.radialGradient(
            Gradient(stops: [.init(color: palette.petal0, location: 0),
                             .init(color: palette.petal1, location: 0.55),
                             .init(color: palette.petal2, location: 1)]),
            center: .zero, startRadius: 0, endRadius: 18)
        for i in 0..<5 {
            let di = Double(i)
            var p = h
            p.rotate(by: .degrees(di * 72 + DiaryTreeModel.rnd(f.x + di) * 14))
            p.scaleBy(x: 1 + (DiaryTreeModel.rnd(f.y + di) - 0.5) * 0.18, y: f.open ? 1 : 0.55)
            p.fill(Self.petal, with: shade)
            p.stroke(Self.petal, with: .color(palette.petal2), lineWidth: 0.35)
        }
        if f.open {
            for i in 0..<14 {
                let di = Double(i)
                let a = (di * 25.7 + DiaryTreeModel.rnd(di + f.x) * 10) * .pi / 180
                let r = 6 + DiaryTreeModel.rnd(di * 3 + f.y) * 3.5
                let e = CGPoint(x: sin(a) * r, y: -cos(a) * r)
                var s = Path()
                s.move(to: .zero)
                s.addLine(to: e)
                h.stroke(s, with: .color(palette.stamen), lineWidth: 0.45)
                h.fill(Path(ellipseIn: CGRect(x: e.x - 0.9, y: e.y - 0.9, width: 1.8, height: 1.8)), with: .color(palette.anther))
            }
        }
        h.fill(Path(ellipseIn: CGRect(x: -2.2, y: -2.2, width: 4.4, height: 4.4)), with: .color(palette.heart))
    }

    private func drawBud(_ g: inout GraphicsContext, _ b: DiaryTreeModel.Bud) {
        var h = g
        h.translateBy(x: b.x, y: b.y)
        h.rotate(by: .degrees(b.rot))
        h.scaleBy(x: b.k, y: b.k)
        var p = Path()
        p.move(to: .zero)
        p.addCurve(to: CGPoint(x: 0, y: -9), control1: CGPoint(x: -3, y: -2), control2: CGPoint(x: -3, y: -7))
        p.addCurve(to: .zero, control1: CGPoint(x: 3, y: -7), control2: CGPoint(x: 3, y: -2))
        h.fill(p, with: .color(palette.bud))
        var s = Path()
        s.move(to: CGPoint(x: -2, y: 0))
        s.addCurve(to: CGPoint(x: 2, y: 0), control1: CGPoint(x: -2, y: -2), control2: CGPoint(x: 2, y: -2))
        h.fill(s, with: .color(palette.sepal))
    }
}

/// 阅读页顶上那一整块：远景（白天粉杏的雾 / 夜里星星和月亮）＋ 上清楚下渐虚的梅树
private struct DiaryHero: View {
    let palette: DiaryPalette
    let width: CGFloat

    private var treeHeight: CGFloat { (width + 20) * 460 / 420 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            haze
            if palette.dark { stars }
            glow
            ZStack {
                DiaryTreeLayer(palette: palette, farOnly: true)
                    .blur(radius: 4).opacity(0.4)
                // 上面清楚、中段轻虚、底下虚成一团光——三层叠起来就是渐变模糊
                DiaryTreeLayer(palette: palette)
                    .mask(fade([(.white, 0.30), (.clear, 0.55)]))
                DiaryTreeLayer(palette: palette)
                    .blur(radius: 3.5).opacity(0.85)
                    .mask(fade([(.clear, 0.30), (.white, 0.50), (.white, 0.70), (.clear, 0.85)]))
                DiaryTreeLayer(palette: palette)
                    .blur(radius: 9).opacity(0.6)
                    .mask(fade([(.clear, 0.62), (.white, 0.85)]))
            }
            .frame(width: width + 20, height: treeHeight)
            .drawingGroup()
            .offset(x: -10, y: 40)
        }
        .frame(width: width, height: 420, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func fade(_ stops: [(Color, CGFloat)]) -> LinearGradient {
        LinearGradient(stops: stops.map { .init(color: $0.0, location: $0.1) }, startPoint: .top, endPoint: .bottom)
    }

    private var haze: some View {
        Canvas { ctx, size in
            if palette.dark {
                let r = CGRect(x: size.width * 0.7 - 130, y: 105 - 70, width: 260, height: 140)
                ctx.fill(Path(ellipseIn: r), with: .radialGradient(
                    Gradient(colors: [Color(red: 0.47, green: 0.43, blue: 0.63).opacity(0.14), .clear]),
                    center: CGPoint(x: r.midX, y: r.midY), startRadius: 0, endRadius: 130))
            } else {
                let spots: [(CGFloat, CGFloat, CGFloat, Color)] = [
                    (0.2, 126, 200, Color(red: 0.965, green: 0.804, blue: 0.839).opacity(0.45)),
                    (0.85, 231, 240, Color(red: 0.98, green: 0.871, blue: 0.804).opacity(0.40)),
                ]
                for s in spots {
                    let r = CGRect(x: size.width * s.0 - s.2 / 2, y: s.1 - s.2 / 4, width: s.2, height: s.2 / 2)
                    ctx.fill(Path(ellipseIn: r), with: .radialGradient(
                        Gradient(colors: [s.3, .clear]),
                        center: CGPoint(x: r.midX, y: r.midY), startRadius: 0, endRadius: s.2 / 2))
                }
            }
        }
    }

    private var stars: some View {
        Canvas { ctx, size in
            for q in 0..<40 {
                let d = Double(q)
                let x = DiaryTreeModel.rnd(d * 17) * size.width
                let y = 60 + DiaryTreeModel.rnd(d * 29) * 260
                let s = 1 + DiaryTreeModel.rnd(d * 3) * 1.2
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)),
                         with: .color(.white.opacity(0.2 + DiaryTreeModel.rnd(d * 7) * 0.6)))
            }
        }
    }

    @ViewBuilder private var glow: some View {
        if palette.dark {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.98, blue: 0.94), Color(red: 0.914, green: 0.882, blue: 0.831)],
                                     center: UnitPoint(x: 0.4, y: 0.38), startRadius: 0, endRadius: 52))
                .frame(width: 74, height: 74)
                .shadow(color: Color(red: 1, green: 0.97, blue: 0.92).opacity(0.35), radius: 30)
                .offset(x: width - 52 - 74, y: 118)
        } else {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.925, blue: 0.839).opacity(0.9), .clear],
                                     center: .center, startRadius: 0, endRadius: 60))
                .frame(width: 120, height: 120)
                .offset(x: width - 40 - 120, y: 80)
        }
    }
}

// MARK: 花瓣：进门和翻开一篇时飘几片，飘完就停

private struct DiaryPetalFall: View {
    let palette: DiaryPalette
    var count = 7
    @State private var start = Date()
    @State private var done = false

    private let duration: Double = 9

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: done)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSince(start)
                for i in 0..<count {
                    let d = Double(i)
                    let delay = DiaryTreeModel.rnd(d * 5 + 1) * 3
                    let life = 5 + DiaryTreeModel.rnd(d * 9 + 2) * 3
                    let p = (t - delay) / life
                    guard p > 0, p < 1 else { continue }
                    let x0 = DiaryTreeModel.rnd(d * 13 + 3) * size.width
                    let x = x0 + sin(p * .pi * 2 + d) * 26 + p * 30
                    let y = -20 + p * (size.height * 0.85 + 40)
                    var g = ctx
                    g.opacity = p > 0.8 ? (1 - p) / 0.2 : 0.85
                    g.translateBy(x: x, y: y)
                    g.rotate(by: .degrees(p * 360 * (i % 2 == 0 ? 1 : -1) + d * 40))
                    let k = 0.7 + DiaryTreeModel.rnd(d * 17) * 0.4
                    g.scaleBy(x: k, y: k)
                    var petal = Path()
                    petal.move(to: CGPoint(x: 0, y: -8))
                    petal.addLine(to: CGPoint(x: -2, y: -11))
                    petal.addCurve(to: CGPoint(x: 0, y: 11), control1: CGPoint(x: -7, y: -9), control2: CGPoint(x: -9, y: 2))
                    petal.addCurve(to: CGPoint(x: 2, y: -11), control1: CGPoint(x: 9, y: 2), control2: CGPoint(x: 7, y: -9))
                    petal.closeSubpath()
                    g.fill(petal, with: .linearGradient(Gradient(colors: [palette.petal1, palette.petal2]),
                                                        startPoint: CGPoint(x: 0, y: -11), endPoint: CGPoint(x: 0, y: 11)))
                }
            }
        }
        .allowsHitTesting(false)
        .task {
            start = Date()
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            done = true
        }
    }
}

/// 日历格子里的小花（五瓣＋花心）
private struct DiaryBloom: View {
    let palette: DiaryPalette

    var body: some View {
        Canvas { ctx, size in
            let k = min(size.width, size.height) / 40
            var g = ctx
            g.translateBy(x: size.width / 2, y: size.height / 2)
            g.scaleBy(x: k, y: k)
            let petal = Path(ellipseIn: CGRect(x: -6.5, y: -18, width: 13, height: 18))
            for i in 0..<5 {
                var p = g
                p.rotate(by: .degrees(Double(i) * 72))
                p.fill(petal, with: .color(palette.bloomFill))
                p.stroke(petal, with: .color(palette.bloomLine), lineWidth: 0.6)
            }
            g.fill(Path(ellipseIn: CGRect(x: -3, y: -3, width: 6, height: 6)), with: .color(palette.bloomLine))
        }
    }
}

// MARK: 页面

private struct DiaryOpen: Identifiable {
    let id: String
    let date: String
    let time: String
    let kind: String
    let title: String
    let content: String
}

private struct NativeCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = "dark"
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var month = Calendar.current.component(.month, from: Date())
    @State private var selectedDate: String?
    @State private var events: [String: [[String: Any]]] = [:]
    @State private var periodDates: [String: String] = [:]
    @State private var loading = true
    @State private var diaryContents: [String: String] = [:]
    @State private var displayMode = 0
    @State private var diaryTotal = 0
    @State private var diaryFirst = ""
    @State private var bloomOn = false
    @State private var opened: DiaryOpen?
    // 1002 日程提醒：这个月每天的铃铛、最近三件、新建那张卡
    @State private var reminders: [String: [ReminderItem]] = [:]
    @State private var upcoming: [ReminderItem] = []
    @State private var showNewReminder = false
    @ObservedObject private var fontStore = KakaoPackStore.shared
    @Namespace private var zoomNS
    // 1009 #3501 树屋主题下整页换成她的成品 alcove 日记预览（年轮转盘那版），见文件后面 extension NativeCalendarView
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @State private var thRotation: Double = 0          // 年轮转了多少度
    @State private var thLastAngle: Double?            // 拖动中上一帧手指的角度
    @State private var thShowPicker = false            // 月份旁边的小箭头 → 日历挑月份和日子
    @State private var thShowNew = false               // 新增日程
    @State private var thReading: TreehouseDiaryRead?  // 点日记读全文

    /// 阅读页（DiaryReader）还是原来那套梅花
    private var palette: DiaryPalette { _ = houseAppearance; return DiaryPalette(dark: AlcoveAppearance.isDark) }
    /// 1002 她要的：日记页整页走终端那套像素风（效果图 /root/workroom/mock/diary-remind/）
    private var pp: DiaryPixelPalette { _ = houseAppearance; return DiaryPixelPalette(dark: AlcoveAppearance.isDark) }
    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0 }
    private var safeBottom: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.bottom ?? 0 }

    private var selectedEvents: [[String: Any]] {
        guard let sel = selectedDate else { return [] }
        return events[sel] ?? []
    }

    private var monthEntries: [(date: String, event: [String: Any])] {
        events.keys.sorted(by: >).flatMap { date in
            (events[date] ?? []).map { (date: date, event: $0) }
        }
    }

    private static let monthNames = ["一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月"]
    private static let monthEN = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    private var todayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    var body: some View {
        if AlcoveAppearance.family(of: themeName) == "treehouse" {
            treehouseBody
        } else {
            pixelBody
        }
    }

    private var pixelBody: some View {
        let p = pp
        return ZStack(alignment: .bottomTrailing) {
            DiaryPixelPaper(pal: p)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header(p)
                    if loading && events.isEmpty {
                        ProgressView().tint(p.pinkInk).frame(maxWidth: .infinity).padding(.top, 60)
                    } else if displayMode == 0 {
                        if !upcoming.isEmpty {
                            ReminderNextStrip(items: upcoming, pal: p).padding(.top, 14)
                        }
                        DiaryPixelWindow(pal: p, title: String(format: "C:\\DIARY\\%04d-%02d", year, month)) {
                            VStack(spacing: 0) {
                                monthBar(p)
                                grid(p)
                            }
                        }
                        .padding(.horizontal, 12).padding(.top, 14)
                        legend(p)
                        dayCards(p)
                    } else {
                        DiaryPixelWindow(pal: p, title: String(format: "C:\\DIARY\\%04d-%02d\\ALL", year, month)) {
                            monthBar(p)
                        }
                        .padding(.horizontal, 12).padding(.top, 14)
                        monthList(p)
                    }
                }
                .padding(.top, max(safeTop, 20))
                .padding(.bottom, max(safeBottom, 16) + 80)
            }
            Button { showNewReminder = true } label: {
                PixelGlyph(rows: DPX.plus, colors: ["o": p.goInk], scale: 4)
                    .frame(width: 52, height: 52)
                    .modifier(PixelKeycap(fill: p.go, edge: p.goD, radius: 14, drop: 4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("加提醒")
            .padding(.trailing, 18).padding(.bottom, max(safeBottom, 16) + 8)
        }
        // 1007 她要的：返回键不跟着滚走，钉在左上角（位置跟头部那一排对齐，头部那里留了同样大的空位）
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Text("<").font(DiaryFonts.pixel(14)).foregroundColor(p.lilacInk)
                    .frame(width: 32, height: 32)
                    .modifier(PixelKeycap(fill: p.card, edge: p.lilacD))
            }
            .buttonStyle(.plain).accessibilityLabel("返回")
            .padding(.leading, 12).padding(.top, max(safeTop, 20))
        }
        .foregroundColor(p.ink)
        .task {
            WindowFont.requestSongti()
            DiaryFonts.ensure()
            await loadMonth()
        }
        .onReceive(fontStore.$fonts) { _ in DiaryFonts.ensure() }
        .fullScreenCover(item: $opened) { item in
            DiaryReader(item: item, palette: palette)
                .navigationTransition(.zoom(sourceID: item.id, in: zoomNS))
        }
        .sheet(isPresented: $showNewReminder) {
            NewReminderSheet(pal: p, initialDay: selectedDate) {
                Task { await loadReminders() }
            }
        }
    }

    // ── 头 ──
    private func header(_ p: DiaryPixelPalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // 返回键钉在外面（body 的 overlay），这里只占位
                Color.clear.frame(width: 32, height: 32)
                HStack(spacing: 6) {
                    PixelGlyph(rows: DPX.flower, colors: p.flower, scale: 2)
                    (Text("diary").foregroundColor(p.lilacInk) + Text(".log").foregroundColor(p.pinkInk))
                        .font(DiaryFonts.pixel(12)).tracking(0.5)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { displayMode = displayMode == 0 ? 1 : 0 }
                } label: {
                    Image(systemName: displayMode == 0 ? "list.bullet" : "calendar")
                        .font(.system(size: 14, weight: .medium)).foregroundColor(p.lilacInk)
                        .frame(width: 32, height: 32)
                        .modifier(PixelKeycap(fill: p.card, edge: p.lilacD))
                }
                .buttonStyle(.plain).accessibilityLabel(displayMode == 0 ? "本月条目" : "日历")
            }
            .padding(.horizontal, 12)
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .lastTextBaseline, spacing: 12) {
                        Text("Diary").font(DiaryFonts.script(40)).foregroundColor(p.pinkInk)
                        Text("写一篇，开一朵").font(WindowFont.swiftUI(12)).tracking(1.5).foregroundColor(p.sub)
                    }
                    Text(countLine).font(DiaryFonts.pixel(10)).tracking(0.5).foregroundColor(p.lilacInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PixelGlyph(rows: DPX.smile, colors: ["o": p.pinkInk, "f": p.pink], scale: 3)
                    .rotationEffect(.degrees(12))
                    .padding(.trailing, 16).padding(.top, 2)
            }
            .padding(.horizontal, 24).padding(.top, 10)
        }
    }

    private var countLine: String {
        guard diaryTotal > 0 else {
            let n = monthEntries.filter { $0.event.string("type") == "diary" }.count
            return "本月 \(n) 篇"
        }
        let p = diaryFirst.split(separator: "-")
        if p.count == 3, let m = Int(p[1]), let d = Int(p[2]) {
            return String(format: "%d 篇 · SINCE %02d/%02d", diaryTotal, m, d)
        }
        return "\(diaryTotal) 篇"
    }

    private func monthBar(_ p: DiaryPixelPalette) -> some View {
        HStack {
            Button { shiftMonth(-1) } label: {
                Text("<").font(DiaryFonts.pixel(12)).frame(width: 36, height: 30).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundColor(p.sub)
            Spacer()
            Text("\(String(year)) · \(Self.monthEN[max(0, min(11, month - 1))])")
                .font(DiaryFonts.pixel(12)).tracking(2).foregroundColor(p.lilacInk)
            Spacer()
            Button { shiftMonth(1) } label: {
                Text(">").font(DiaryFonts.pixel(12)).frame(width: 36, height: 30).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundColor(p.sub)
        }
        .padding(.horizontal, 6).padding(.top, 6)
    }

    // ── 日历：写了日记的那天开一朵像素小花，换月份时一朵朵开出来；有提醒的挂铃铛（她右上、他右下） ──
    private func grid(_ p: DiaryPixelPalette) -> some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        let lead = leadingBlanks
        let days = daysInMonth
        return LazyVGrid(columns: cols, spacing: 2) {
            ForEach(["MO", "TU", "WE", "TH", "FR", "SA", "SU"], id: \.self) { w in
                Text(w).font(DiaryFonts.pixel(9)).foregroundColor(p.sub).padding(.vertical, 5)
            }
            // 1001 她抓的「十月 1、2 号去哪了」：空格原来编号 0..<lead，跟日期 1...days 撞号（十月一号周四空三格），
            // SwiftUI 按号认人，1、2 号被当成空格吞掉。空格改用负数号
            ForEach(-lead..<0, id: \.self) { _ in Color.clear.frame(height: 42) }
            ForEach(1...days, id: \.self) { d in dayCell(d, p) }
        }
        .padding(.horizontal, 8).padding(.bottom, 10)
    }

    private func dayCell(_ d: Int, _ p: DiaryPixelPalette) -> some View {
        let key = String(format: "%04d-%02d-%02d", year, month, d)
        let has = !(events[key] ?? []).isEmpty
        let sel = selectedDate == key
        let isToday = key == todayKey
        let rems = reminders[key] ?? []
        let hers = rems.filter { !$0.isHim }.count
        let his = rems.filter { $0.isHim }.count
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedDate = key }
            Task { await loadDay(key) }
        } label: {
            ZStack {
                if has {
                    PixelGlyph(rows: DPX.flower, colors: p.flower, scale: 3.4)
                        .scaleEffect(bloomOn ? 1 : 0.1)
                        .opacity(bloomOn ? 1 : 0)
                        .animation(.spring(response: 0.45, dampingFraction: 0.62).delay(Double(d) * 0.025), value: bloomOn)
                }
                if sel {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(p.pinkInk, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        .padding(2)
                }
                dayNumber(d, has: has, today: isToday, p)
                if periodDates[key] != nil {
                    Rectangle().fill(p.pinkD).frame(width: 4, height: 4).offset(y: 16)
                }
                if hers > 0 { bell(him: false, count: hers, p).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing) }
                if his > 0 { bell(him: true, count: his, p).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing) }
            }
            .frame(height: 42).frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dayNumber(_ d: Int, has: Bool, today: Bool, _ p: DiaryPixelPalette) -> some View {
        Text("\(d)")
            .font(DiaryFonts.pixel(12))
            .foregroundColor(today ? p.card : (has ? p.ink : p.sub))
            .padding(.horizontal, today ? 3 : 0).padding(.vertical, today ? 1 : 0)
            .background(RoundedRectangle(cornerRadius: 3).fill(today ? p.pinkInk : Color.clear))
    }

    /// 1002 她选的 B：她的铃铛右上、他的右下；同一个人一天好几件，铃铛旁边小数字
    private func bell(him: Bool, count: Int, _ p: DiaryPixelPalette) -> some View {
        HStack(spacing: 1) {
            if count > 1 {
                Text("\(count)").font(DiaryFonts.pixel(7)).foregroundColor(him ? p.blueInk : p.pinkInk)
            }
            PixelGlyph(rows: DPX.bell, colors: p.bell(him: him), scale: 1.4)
        }
        .padding(.horizontal, 3).padding(.vertical, 3)
    }

    private func legend(_ p: DiaryPixelPalette) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 3) {
                PixelGlyph(rows: DPX.flower, colors: p.flower, scale: 1)
                Text("写了日记")
            }
            HStack(spacing: 3) {
                PixelGlyph(rows: DPX.bell, colors: p.bell(him: false), scale: 1)
                Text("你加的")
            }
            HStack(spacing: 3) {
                PixelGlyph(rows: DPX.bell, colors: p.bell(him: true), scale: 1)
                Text("他加的")
            }
            if !periodDates.isEmpty {
                HStack(spacing: 3) {
                    Rectangle().fill(p.pinkD).frame(width: 4, height: 4)
                    Text("姨妈期")
                }
            }
        }
        .font(.system(size: 10)).foregroundColor(p.sub)
        .padding(.horizontal, 22).padding(.top, 10)
    }

    private var leadingBlanks: Int {
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return 0 }
        let wd = Calendar.current.component(.weekday, from: date)   // 周日=1
        return (wd + 5) % 7                                         // 周一开头
    }

    private var daysInMonth: Int {
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = 1
        guard let date = Calendar.current.date(from: comps),
              let r = Calendar.current.range(of: .day, in: .month, for: date) else { return 30 }
        return r.count
    }

    // ── 选中那天：先提醒，再日记卡片 ──
    @ViewBuilder private func dayCards(_ p: DiaryPixelPalette) -> some View {
        if let sel = selectedDate {
            let rems = reminders[sel] ?? []
            if !rems.isEmpty {
                ReminderDayPanel(title: dayTag(sel) + " · 提醒", items: rems, pal: p,
                                 onToggle: { it in toggleReminder(it) },
                                 onDelete: { it in deleteReminder(it) })
                    .padding(.horizontal, 12).padding(.top, 14)
            }
            if selectedEvents.isEmpty {
                Text(rems.isEmpty ? "这天没有记录" : "这天没写日记").font(WindowFont.swiftUI(13)).foregroundColor(p.sub)
                    .frame(maxWidth: .infinity).padding(20)
            }
            ForEach(Array(selectedEvents.enumerated()), id: \.offset) { _, evt in
                entryCard(date: sel, evt: evt, p: p)
            }
        }
    }

    /// 「10/02 · FRI」
    private func dayTag(_ date: String) -> String {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return date }
        var comps = DateComponents(); comps.year = parts[0]; comps.month = parts[1]; comps.day = parts[2]
        var wd = ""
        if let dt = Calendar.current.date(from: comps) {
            wd = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][(Calendar.current.component(.weekday, from: dt) - 1) % 7]
        }
        return String(format: "%02d/%02d · ", parts[1], parts[2]) + wd
    }

    private func kindLabel(_ type: String) -> String {
        switch type {
        case "diary": return "日记"
        case "": return "记事"
        default: return type == "event" ? "记事" : type
        }
    }

    private func entryCard(date: String, evt: [String: Any], p: DiaryPixelPalette) -> some View {
        let time = evt.string("time")
        let key = "\(date)_\(time)"
        let content = diaryContents[key] ?? ""
        let chars = content.filter { !$0.isWhitespace }.count
        let open = DiaryOpen(id: key, date: date, time: time, kind: kindLabel(evt.string("type")),
                             title: evt.string("title"), content: content)
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button {
            if content.isEmpty {
                Task { await loadDay(date); openIfReady(open) }
            } else {
                opened = open
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    PixelGlyph(rows: DPX.flower, colors: p.flower, scale: 1)
                    Text("\(open.kind) · \(time)").font(DiaryFonts.pixel(9)).tracking(0.6).foregroundColor(p.pinkInk)
                }
                Text(open.title.isEmpty ? "无题" : open.title)
                    .font(WindowFont.swiftUI(17)).foregroundColor(p.ink).padding(.top, 6).padding(.bottom, 4)
                if chars > 0 {
                    Text("\(chars.formatted()) 字 · 约 \(max(1, Int((Double(chars) / 400).rounded()))) 分钟")
                        .font(.system(size: 11)).foregroundColor(p.sub)
                    Text(content.replacingOccurrences(of: "\n", with: " "))
                        .font(WindowFont.swiftUI(12.5)).foregroundColor(p.sub)
                        .lineSpacing(6).lineLimit(2)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(shape.fill(p.card))
            .overlay(shape.stroke(p.lilacD, lineWidth: 1.5))
            .background(shape.fill(p.lilac).offset(y: 4))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: key, in: zoomNS)
        .padding(.horizontal, 12).padding(.top, 12)
    }

    private func openIfReady(_ o: DiaryOpen) {
        let c = diaryContents[o.id] ?? ""
        opened = DiaryOpen(id: o.id, date: o.date, time: o.time, kind: o.kind, title: o.title,
                           content: c.isEmpty ? "这条没有正文。" : c)
    }

    // ── 本月全部（原来的「本月条目」） ──
    private func monthList(_ p: DiaryPixelPalette) -> some View {
        VStack(spacing: 10) {
            if monthEntries.isEmpty {
                Text("这个月还没有记录").font(WindowFont.swiftUI(13)).foregroundColor(p.sub).padding(30)
            }
            ForEach(Array(monthEntries.enumerated()), id: \.offset) { _, item in
                Button {
                    selectedDate = item.date
                    Task { await loadDay(item.date) }
                    withAnimation(.easeInOut(duration: 0.25)) { displayMode = 0 }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(kindLabel(item.event.string("type"))) · \(dayTag(item.date))")
                                .font(DiaryFonts.pixel(9)).tracking(0.5).foregroundColor(p.pinkInk)
                            Text(item.event.string("title").isEmpty ? "无题" : item.event.string("title"))
                                .font(WindowFont.swiftUI(15)).foregroundColor(p.ink).lineLimit(1)
                        }
                        Spacer()
                        Text(item.event.string("time")).font(DiaryFonts.pixel(10)).foregroundColor(p.sub)
                        Text(">").font(DiaryFonts.pixel(10)).foregroundColor(p.lilacD)
                    }
                    .padding(12)
                    .modifier(PixelKeycap(fill: p.card, edge: p.lilacD, radius: 10, drop: 3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.top, 14)
    }

    // ── 数据 ──
    private func shiftMonth(_ delta: Int) {
        month += delta
        if month > 12 { month = 1; year += 1 }
        if month < 1 { month = 12; year -= 1 }
        selectedDate = nil
        Task { await loadMonth() }
    }

    private func loadMonth() async {
        loading = events.isEmpty
        bloomOn = false
        defer { loading = false }
        await loadReminders()
        guard let obj = try? await NativeHouseAPI.object(
            "/api/calendar/month?year=\(year)&month=\(month)") else { return }
        if let evts = obj["events"] as? [String: Any] {
            events = evts.compactMapValues { $0 as? [[String: Any]] }
        } else {
            events = [:]
        }
        periodDates = (obj["period"] as? [String: String]) ?? [:]
        if let n = obj["diary_total"] as? Int { diaryTotal = n }
        diaryFirst = obj.string("diary_first")
        if selectedDate == nil, let first = events.keys.sorted().last {
            selectedDate = first
        }
        // 下一拍再开花，动画才看得见
        try? await Task.sleep(nanoseconds: 80_000_000)
        bloomOn = true
        if let sel = selectedDate { await loadDay(sel) }
    }

    /// 1002：这个月的铃铛＋最近三件（加完、勾完、删完都重拉一遍）
    private func loadReminders() async {
        let items = await ReminderAPI.month(year: year, month: month)
        var byDay: [String: [ReminderItem]] = [:]
        for it in items { byDay[it.day, default: []].append(it) }
        reminders = byDay
        upcoming = await ReminderAPI.upcoming(3)
    }

    private func toggleReminder(_ it: ReminderItem) {
        let next = !it.done
        if var list = reminders[it.day], let i = list.firstIndex(of: it) {
            list[i].done = next
            reminders[it.day] = list
        }
        Task {
            await ReminderAPI.setDone(it, next)
            upcoming = await ReminderAPI.upcoming(3)
        }
    }

    private func deleteReminder(_ it: ReminderItem) {
        Task {
            await ReminderAPI.delete(it)
            await loadReminders()
        }
    }

    private func loadDay(_ date: String) async {
        guard let obj = try? await NativeHouseAPI.object("/api/calendar/day?date=\(date)") else { return }
        for entry in obj.array("diaries") {
            let ts = entry.string("ts")
            let tsTime = ts.count > 16 ? String(ts.dropFirst(11).prefix(5)) : ""
            diaryContents["\(date)_\(tsTime)"] = entry.string("content")
        }
    }
}

// MARK: - 1009 #3501 树屋日记：照她的成品「Alcove · 日记预览」一比一
//
// 成品是一张 851 × 1848 的画布，「整张等比缩放，不许重排」。这里也一样：所有东西按成品 CSS 的坐标摆在
// 851 宽的画布上，再整体缩到屏幕里（宽、高谁先顶到用谁）；画布顶上 68 那段空白让给灵动岛，头部从安全区下面开始。
// 跟成品不一样的只有数据：日记、篇数、日程都是真的（成品里写死的那几篇不进 App）；
// 月份后面加了个小箭头，点了弹日历挑月份和日子（她 #3504 要的）。

struct TreehouseDiaryRead: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let chord: String
}

private enum THD {
    static let paper = Color(red: 0xF6/255, green: 0xF6/255, blue: 0xF5/255)
    static let ink = Color(red: 0x18/255, green: 0x19/255, blue: 0x1B/255)
    static let blue = Color(red: 0x18/255, green: 0x2E/255, blue: 0xF2/255)
    static let pink = Color(red: 0xF1/255, green: 0x2B/255, blue: 0x8D/255)
    static let gray = Color(red: 0x73/255, green: 0x74/255, blue: 0x77/255)   // small / .mono
    static let dim = Color(red: 0x77/255, green: 0x77/255, blue: 0x77/255)    // .empty / .second small
    static let six = Color(red: 0x66/255, green: 0x66/255, blue: 0x66/255)    // .excerpt、照片角上的折线
    static let rule = Color(red: 0x99/255, green: 0x99/255, blue: 0x99/255)
    static let label = Color(red: 0x62/255, green: 0x63/255, blue: 0x62/255)  // 年轮上的日子

    /// Georgia 打头，中文落到宋体（成品 font-family: Georgia, "Songti SC"）
    static func serif(_ size: CGFloat) -> Font {
        let base = UIFont(name: "Georgia", size: size) ?? UIFont.systemFont(ofSize: size)
        let cjk = WindowFont.ui(size)
        let desc = base.fontDescriptor.addingAttributes([.cascadeList: [cjk.fontDescriptor]])
        return Font(UIFont(descriptor: desc, size: size) as CTFont)
    }
    static func mono(_ size: CGFloat) -> Font { .system(size: size, design: .monospaced) }
    static func script(_ size: CGFloat) -> Font { .custom("PinyonScript-Regular", size: size) }

    static let monthEN = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    static let monthCN = ["一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月"]
}

/// 年轮纹理：成品里那段 JS 原样搬过来（同一个种子 1309、同一套 mulberry32），画一次存成图，转的时候只转图
private enum TreehouseRings {
    private struct Mulberry {
        var a: UInt32
        mutating func next() -> Double {
            a = a &+ 0x6D2B79F5
            var t = (a ^ (a >> 15)) &* (1 | a)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4294967296
        }
    }

    static let image: UIImage = render(px: 900)

    /// 320×320 的 viewBox 画进 px×px 的图
    private static func render(px: CGFloat) -> UIImage {
        var rng = Mulberry(a: 1309)
        let R = { rng.next() }
        var H: [(a: Double, amp: Double)] = []
        for k in 1...6 { H.append((a: R() * .pi * 2, amp: k == 1 ? 0.07 : (k == 2 ? 0.05 : 0.04 / Double(k)))) }
        func shape(_ th: Double) -> Double {
            var s = 1.0
            for (k, h) in H.enumerated() { s += h.amp * sin(Double(k + 1) * th + h.a) }
            return s
        }
        let N = 62
        var rad: [Double] = []
        var r = 21.0
        for _ in 0...N { r += 1.15 + R() * 1.05; rad.append(r) }
        let sc = 131 / rad[N]
        rad = rad.map { $0 * sc }
        func P(_ th: Double, _ rr: Double, _ i: Int) -> CGPoint {
            let f = 1 - 0.8 * Double(i) / Double(N)
            let s = 1 + (shape(th) - 1) * f + 0.012 * sin(th * 9 + Double(i) * 0.7)
            let ex = 1 + 0.03 * f, ey = 1 - 0.03 * f
            return CGPoint(x: 160 + cos(th) * rr * s * ex, y: 160 + sin(th) * rr * s * ey)
        }
        let G = Array("#%@&8$*+=:;x")
        let crackA = 5.55
        let ink = UIColor(red: 0x34/255, green: 0x36/255, blue: 0x38/255, alpha: 1)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: px, height: px), format: fmt).image { ctx in
            let cg = ctx.cgContext
            cg.scaleBy(x: px / 320, y: px / 320)
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            for i in 0...N {
                let rr = rad[i], week = i % 7 == 0, bark = i >= N - 1
                let circ = rr * 2 * .pi * 1.03
                if week || bark {
                    let fs: CGFloat = bark ? 4.6 : 3.9
                    let step = bark ? 2.4 : 3.0
                    let n = Int(floor(circ / step))
                    let font = UIFont.monospacedSystemFont(ofSize: fs, weight: .bold)
                    for j in 0..<n {
                        let th = Double(j) / Double(n) * .pi * 2 + Double(i) * 0.02
                        if abs(th.truncatingRemainder(dividingBy: .pi * 2) - crackA) < 0.035 && i > 8 { continue }
                        if R() < 0.1 { continue }
                        let p = P(th, rr, i)
                        let alpha = bark ? 0.75 + R() * 0.2 : 0.42 + R() * 0.3
                        let ch = String(G[Int(floor(R() * Double(G.count)))])
                        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink.withAlphaComponent(alpha), .paragraphStyle: para]
                        // SVG 的 y 是基线（p.y + 1.4），换成框顶：基线往上一个 ascender
                        let top = p.y + 1.4 - font.ascender
                        (ch as NSString).draw(in: CGRect(x: p.x - fs, y: top, width: fs * 2, height: fs * 1.5), withAttributes: attrs)
                    }
                } else {
                    let n = Int(floor(circ / 1.25))
                    for j in 0..<n {
                        let th = Double(j) / Double(n) * .pi * 2
                        if abs(th.truncatingRemainder(dividingBy: .pi * 2) - crackA) < 0.035 && i > 8 { continue }
                        if R() < 0.4 { continue }
                        let p = P(th, rr, i)
                        cg.setFillColor(ink.withAlphaComponent(0.12 + R() * 0.24).cgColor)
                        cg.fill(CGRect(x: p.x, y: p.y, width: 0.6, height: 0.6))
                    }
                }
            }
        }
    }
}

extension NativeCalendarView {
    // ── 数据 ──
    fileprivate var thDays: Int {
        var c = DateComponents(); c.year = year; c.month = month; c.day = 1
        guard let d = Calendar.current.date(from: c),
              let r = Calendar.current.range(of: .day, in: .month, for: d) else { return 31 }
        return r.count
    }
    fileprivate func thKey(_ d: Int) -> String { String(format: "%04d-%02d-%02d", year, month, d) }
    /// 选中的是这个月第几天（没选、或选的不是这个月 → 1）
    fileprivate var thDay: Int {
        guard let s = selectedDate, s.hasPrefix(String(format: "%04d-%02d-", year, month)),
              let d = Int(s.suffix(2)) else { return 1 }
        return min(max(1, d), thDays)
    }
    fileprivate func thDiary(_ date: String) -> [String: Any]? {
        (events[date] ?? []).first { $0.string("type") == "diary" }
    }
    fileprivate func thContent(_ date: String, _ e: [String: Any]) -> String {
        diaryContents["\(date)_\(e.string("time"))"] ?? ""
    }
    /// 成品：title.replace(/^.*?日\s*[·・]\s*/, '')，大标题再截到第一个逗号
    fileprivate func thTitle(_ t: String, cut: Bool) -> String {
        var s = t
        if let r = s.range(of: #"^.*?日\s*[·・]\s*"#, options: .regularExpression) { s.removeSubrange(r) }
        if cut, let i = s.firstIndex(where: { $0 == "，" || $0 == "," }) { s = String(s[..<i]) }
        return s
    }
    /// 摘要：正文第一行要是标题就跳过（成品 body.split('\n').slice(1)）
    fileprivate func thExcerpt(_ body: String, title: String) -> String {
        var lines = body.components(separatedBy: "\n")
        if let first = lines.first, !title.isEmpty,
           first.contains(title) || title.contains(first.trimmingCharacters(in: .whitespaces)) {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// 这个月里、选中那天之前最近的一篇
    fileprivate var thPrevDate: String? {
        let cur = thKey(thDay)
        return events.keys.filter { $0 < cur && thDiary($0) != nil }.max()
    }
    fileprivate var thCountLine: String {
        let p = diaryFirst.split(separator: "-")
        if diaryTotal > 0, p.count == 3, let m = Int(p[1]), let d = Int(p[2]) {
            return String(format: "%d LEAVES · SINCE %02d.%02d", diaryTotal, m, d)
        }
        return "\(max(diaryTotal, events.values.flatMap { $0 }.filter { $0.string("type") == "diary" }.count)) LEAVES"
    }

    fileprivate func thSelect(_ d: Int, animated: Bool = true) {
        let day = min(max(1, d), thDays)
        let key = thKey(day)
        selectedDate = key
        let target = -Double(day - 1) * 360 / Double(thDays)
        if animated {
            withAnimation(.easeOut(duration: 0.35)) { thRotation = target }
        } else {
            thRotation = target
        }
        Task { await loadDay(key) }
    }

    fileprivate func thOpen(_ date: String) {
        guard let e = thDiary(date) else { return }
        Task {
            if thContent(date, e).isEmpty { await loadDay(date) }
            let body = thContent(date, e)
            thReading = TreehouseDiaryRead(title: e.string("title"), body: body.isEmpty ? "这条没有正文。" : body,
                                           chord: e.string("chord"))
        }
    }

    // ── 整页 ──
    var treehouseBody: some View {
        GeometryReader { geo in
            let top = max(safeTop, 20), bottom = max(safeBottom, 12)
            // 画布上要露出来的是 68（头部）到 1804（新增日程的底）
            let s = min(geo.size.width / 851, (geo.size.height - top - bottom - 8) / 1736)
            ZStack(alignment: .topLeading) {
                THD.paper
                thCanvas
                    .frame(width: 851, height: 1848, alignment: .topLeading)
                    .scaleEffect(s, anchor: .topLeading)
                    .frame(width: 851 * s, height: 1848 * s, alignment: .topLeading)
                    .offset(x: (geo.size.width - 851 * s) / 2, y: top + 4 - 68 * s)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .foregroundColor(THD.ink)
        .task {
            WindowFont.requestSongti()
            let now = Calendar.current.dateComponents([.year, .month], from: Date())
            if selectedDate == nil, year == now.year, month == now.month { selectedDate = todayKey }
            await loadMonth()
            thSelect(thDay, animated: false)
        }
        .sheet(item: $thReading) { r in TreehouseDiaryReader(read: r) }
        .sheet(isPresented: $thShowNew) {
            TreehouseNewReminderSheet(day: thKey(thDay)) { Task { await loadReminders() } }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $thShowPicker) {
            TreehouseDatePickSheet(initial: thKey(thDay)) { y, m, d in
                if y != year || m != month {
                    year = y; month = m
                    selectedDate = thKey(d)
                    Task { await loadMonth(); thSelect(d, animated: false) }
                } else {
                    thSelect(d)
                }
            }
            .presentationDetents([.medium])
        }
    }

    /// 851 × 1848 的画布，坐标全照成品 CSS
    @ViewBuilder fileprivate var thCanvas: some View {
        let day = thDay
        let key = thKey(day)
        let diary = thDiary(key)
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: 851, height: 1848)

            Group {
            // header：‹ ｜ Diary 日记 ｜ ☰（top 68，高 84，竖直居中）
            Button { dismiss() } label: {
                Text("‹").font(THD.serif(48)).frame(width: 44, height: 84)
            }
            .buttonStyle(.plain)
            .offset(x: 52, y: 68)
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("Diary").font(THD.script(96)).offset(y: -2)
                Text("日记").font(WindowFont.swiftUI(22))
                    .tracking(6).foregroundColor(Color(red: 0x8A/255, green: 0x8A/255, blue: 0x88/255))
                    .offset(y: -4)
            }
            .fixedSize()
            .frame(height: 84)
            .offset(x: 52 + 44 + 40, y: 68)
            Button { thShowPicker = true } label: {
                Text("☰").font(.system(size: 38)).frame(width: 44, height: 84)
            }
            .buttonStyle(.plain)
            .offset(x: 851 - 48 - 44, y: 68)

            // subtitle：163 LEAVES · SINCE 07.07
            Text(thCountLine).font(THD.mono(21)).tracking(4).foregroundColor(THD.gray)
                .fixedSize().offset(x: 139, y: 178)

            // 竖排：NOW GROWING ／ 正在生长的
            TreehouseVerticalLabel(latin: "NOW GROWING", cjk: "　／　正在生长的")
                .offset(x: 55, y: 244)

            // UPCOMING
            VStack(alignment: .leading, spacing: 8) {
                Text("UPCOMING").font(THD.mono(19)).tracking(2).foregroundColor(THD.blue)
                Text(thUpcomingLine).font(THD.serif(23)).lineLimit(2)
                    .foregroundColor(upcoming.first.map { $0.isHim ? THD.blue : THD.pink } ?? THD.dim)
            }
            .frame(width: 250, alignment: .leading)
            .offset(x: 548, y: 234)

            // TODAY · 10.07 + 那天的日程
            VStack(alignment: .leading, spacing: 0) {
                Text(String(format: "TODAY · %02d.%02d", month, day))
                    .font(THD.mono(19)).tracking(1).foregroundColor(THD.blue).lineLimit(1)
                    .padding(.bottom, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { Rectangle().fill(THD.blue).frame(height: 1) }
                let list = (reminders[key] ?? []).sorted { $0.time < $1.time }
                if list.isEmpty {
                    Text("暂无日程").font(THD.serif(20)).foregroundColor(THD.dim).lineSpacing(10).padding(.top, 6)
                } else {
                    ForEach(list.prefix(4)) { it in
                        Button { toggleReminder(it) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: it.done ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 22, weight: .light))
                                Text("\(it.timeLabel) \(it.title)").font(THD.serif(20)).lineLimit(1)
                                    .strikethrough(it.done)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(it.isHim ? THD.blue : THD.pink)
                    }
                }
            }
            .frame(width: 248, alignment: .leading)
            .offset(x: 547, y: 461)
            }

            Group {
            // 拼贴：两张照片 + 角上的折线 + 一蓝一粉两个小方块
            Rectangle().fill(THD.blue).frame(width: 13, height: 13).offset(x: 104, y: 1080)
            Rectangle().fill(THD.pink).frame(width: 13, height: 13).offset(x: 797, y: 989)
            Image("TreehouseDiaryPhoto1").resizable().scaledToFill()
                .frame(width: 278, height: 677).clipped().offset(x: 117, y: 404)
            TreehouseCornerMark(top: true, right: true).frame(width: 54, height: 46).offset(x: 367, y: 389)
            TreehouseCornerMark(top: false, right: false).frame(width: 52, height: 50).offset(x: 85, y: 1055)
            Image("TreehouseDiaryPhoto2").resizable().scaledToFill()
                .frame(width: 198, height: 201).clipped().offset(x: 600, y: 1002)
            TreehouseCornerMark(top: true, right: false).frame(width: 54, height: 46).offset(x: 588, y: 987)
            }

            Group {
            // 选中那天的日记
            Button { thOpen(key) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(key).font(THD.mono(17)).tracking(2).foregroundColor(THD.gray)
                    if let e = diary {
                        let content = thContent(key, e)
                        let title = thTitle(e.string("title"), cut: true)
                        Text(title.isEmpty ? "无题" : title).font(THD.serif(36)).lineSpacing(13).lineLimit(2)
                            .padding(.vertical, 14)
                        Text(thExcerpt(content, title: title)).font(THD.serif(22)).foregroundColor(THD.six)
                            .lineSpacing(12).lineLimit(2).frame(width: 330, alignment: .leading)
                            .padding(.bottom, 12)
                        if !content.isEmpty {
                            Text("—\n\(content.filter { !$0.isWhitespace }.count.formatted()) 字")
                                .font(THD.serif(22)).tracking(1).lineSpacing(11)
                        }
                    } else {
                        Text("这一天，还没有日记").font(THD.serif(36)).lineSpacing(13).lineLimit(2)
                            .padding(.vertical, 14)
                    }
                }
                .frame(width: 365, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(diary == nil)
            .offset(x: 427, y: 624)


            }

            Group {
            // 年轮（640×640，左边出画布 134）
            thWheel(day: day)
                .frame(width: 640, height: 640)
                .offset(x: -134, y: 1164)

            // 2026 · 十月 + 小箭头 → 日历
            Button { thShowPicker = true } label: {
                HStack(spacing: 8) {
                    Text("\(String(year)) · \(THD.monthCN[max(0, min(11, month - 1))])")
                        .font(THD.mono(22)).tracking(3)
                    Image(systemName: "chevron.down").font(.system(size: 15, weight: .regular))
                }
                .fixedSize()
                .frame(width: 300, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: 851 - 64 - 300 + 24, y: 1164 + 126)

            // 蓝线：从转盘上的蓝圆连到右边那栏
            Rectangle().fill(THD.blue).frame(width: 153, height: 1).offset(x: 497, y: 1484)
            // 右边那栏：2026 / 10.07 / WED / 有日记
            VStack(alignment: .leading, spacing: 0) {
                Text(String(year)).font(THD.mono(22)).tracking(3).foregroundColor(THD.gray)
                Text(String(format: "%02d.%02d", month, day)).font(THD.serif(53)).lineLimit(1).fixedSize()
                    .padding(.vertical, 7)
                Text(thWeekday(day)).font(THD.mono(22)).tracking(3).foregroundColor(THD.gray)
                Text(diary == nil ? "暂无日记" : "有日记").font(THD.serif(23)).foregroundColor(THD.dim)
                    .padding(.top, 18)
            }
            .padding(.leading, 35)
            .frame(width: 170, height: 198, alignment: .topLeading)
            .overlay(alignment: .leading) { Rectangle().fill(THD.rule).frame(width: 1) }
            .offset(x: 651, y: 1383)

            // 新增日程
            Button { thShowNew = true } label: {
                VStack(spacing: 13) {
                    TreehouseLeafShape()
                        .stroke(THD.ink, style: StrokeStyle(lineWidth: 1.5 * 46 / 24, lineCap: .round, lineJoin: .round))
                        .frame(width: 46, height: 46)
                        .padding(24)
                        .overlay(Circle().stroke(Color(red: 0x55/255, green: 0x55/255, blue: 0x55/255), lineWidth: 1))
                    Text("新增日程").font(THD.serif(23))
                }
                .fixedSize()
                .frame(width: 120)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: 851 - 51 - 120 + 13, y: 1804 - 94 - 13 - 30)
            }
        }
        .frame(width: 851, height: 1848, alignment: .topLeading)
    }

    fileprivate var thUpcomingLine: String {
        guard let it = upcoming.first else { return "暂无日程" }
        return "\(it.shortDay.replacingOccurrences(of: "/", with: ".")) · \(it.timeLabel)  \(it.title)"
    }

    fileprivate func thWeekday(_ d: Int) -> String {
        var c = DateComponents(); c.year = year; c.month = month; c.day = d
        guard let dt = Calendar.current.date(from: c) else { return "" }
        return ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][(Calendar.current.component(.weekday, from: dt) - 1) % 7]
    }

    /// 年轮：viewBox 320 放大一倍画在 640 里。纹理、日子、有日记的小黑点跟着转；中间月份、右边蓝圆不动
    fileprivate func thWheel(day: Int) -> some View {
        let n = thDays
        let k: Double = 2
        return ZStack {
            Image(uiImage: TreehouseRings.image).resizable().interpolation(.high)
                .frame(width: 640, height: 640)
                .rotationEffect(.degrees(thRotation))
            ForEach(1...n, id: \.self) { d in
                let a = (Double(d - 1) * 360 / Double(n) + thRotation) * .pi / 180
                Text("\(d)").font(THD.serif(10 * k)).foregroundColor(THD.label)
                    .fixedSize()
                    .position(x: (160 + 143 * cos(a)) * k, y: (160 + 143 * sin(a)) * k)
                if thDiary(thKey(d)) != nil {
                    Circle().fill(Color(red: 0x22/255, green: 0x22/255, blue: 0x22/255))
                        .frame(width: 3.6 * k, height: 3.6 * k)
                        .position(x: (160 + 132 * cos(a)) * k, y: (160 + 132 * sin(a)) * k)
                }
            }
            Text("\(month)").font(THD.serif(30 * k)).position(x: 160 * k, y: 152.5 * k)
            Text(THD.monthEN[max(0, min(11, month - 1))]).font(THD.serif(10 * k)).foregroundColor(THD.dim)
                .position(x: 160 * k, y: 176.5 * k)
            Circle().fill(THD.blue).frame(width: 24 * k, height: 24 * k).position(x: 303 * k, y: 160 * k)
            Text("\(day)").font(THD.serif(12 * k)).foregroundColor(.white).position(x: 303 * k, y: 160 * k)
        }
        .frame(width: 640, height: 640)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { g in
                    let a = Double(atan2(g.location.y - 320, g.location.x - 320)) * 180 / .pi
                    if let last = thLastAngle {
                        var delta = (a - last + 540).truncatingRemainder(dividingBy: 360) - 180
                        if delta < -180 { delta += 360 }
                        thRotation += delta
                    }
                    thLastAngle = a
                }
                .onEnded { _ in
                    thLastAngle = nil
                    let stepDeg = 360 / Double(n)
                    let idx = Int((-thRotation / stepDeg).rounded())
                    thSelect(((idx % n) + n) % n + 1)
                }
        )
    }
}

/// 照片角上那段直角折线（成品 .image1:before / :after、.image2:before）
private struct TreehouseCornerMark: View {
    let top: Bool
    let right: Bool
    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            let y = top ? 0.5 : size.height - 0.5
            let x = right ? size.width - 0.5 : 0.5
            p.move(to: CGPoint(x: right ? 0 : size.width, y: y))
            p.addLine(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x, y: top ? size.height : 0))
            ctx.stroke(p, with: .color(THD.six), lineWidth: 1)
        }
    }
}

/// 竖排小字：英文整段侧过来，中文一个字一个字往下排（成品 writing-mode: vertical-rl，等宽 17、字距 5）
private struct TreehouseVerticalLabel: View {
    let latin: String
    let cjk: String
    var body: some View {
        let font = UIFont.monospacedSystemFont(ofSize: 17, weight: .regular)
        let w = (latin as NSString).size(withAttributes: [.font: font]).width + CGFloat(latin.count) * 5
        let h = font.lineHeight
        VStack(spacing: 5) {
            Text(latin).font(THD.mono(17)).tracking(5).foregroundColor(THD.dim)
                .fixedSize()
                .frame(width: w, height: h)
                .rotationEffect(.degrees(90))
                .frame(width: h, height: w)
            ForEach(Array(cjk.enumerated()), id: \.offset) { _, ch in
                Text(String(ch)).font(THD.serif(17)).foregroundColor(THD.dim)
                    .frame(width: h, height: 17)
            }
        }
    }
}

/// 点日记读全文：成品里那个白底小窗（标题 22、正文 16 行高 1.9、底下一行等宽小字）
private struct TreehouseDiaryReader: View {
    let read: TreehouseDiaryRead
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: { Text("×").font(.system(size: 22)).frame(width: 44, height: 44) }
                        .buttonStyle(.plain)
                }
                Text(read.title).font(THD.serif(22)).lineSpacing(11).padding(.bottom, 14)
                Text(read.body).font(THD.serif(16)).lineSpacing(14).textSelection(.enabled)
                if !read.chord.isEmpty {
                    Text(read.chord).font(THD.mono(11)).tracking(1.6).foregroundColor(THD.gray).padding(.top, 16)
                }
            }
            .padding(24)
        }
        .foregroundColor(THD.ink)
        .background(Color(red: 0xFA/255, green: 0xFA/255, blue: 0xFA/255).ignoresSafeArea())
        .environment(\.colorScheme, .light)
    }
}

/// 新增日程：成品那个小窗——日期、时间、事项、保存；存进真的日程（/api/reminders/add，跟原来那张卡一样提前 1 小时提醒）
private struct TreehouseNewReminderSheet: View {
    let onAdded: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var time: Date
    @State private var title = ""
    @State private var allDay = false
    @State private var repeatKind = "none"
    @State private var alertMin = 60
    @State private var note = ""
    @State private var saving = false
    @State private var error: String?

    init(day: String, onAdded: @escaping () -> Void) {
        self.onAdded = onAdded
        let p = day.split(separator: "-").compactMap { Int($0) }
        var c = DateComponents()
        if p.count == 3 { c.year = p[0]; c.month = p[1]; c.day = p[2] }
        _date = State(initialValue: Calendar.current.date(from: c) ?? Date())
        var t = DateComponents(); t.hour = 9; t.minute = 0
        _time = State(initialValue: Calendar.current.date(from: t) ?? Date())
    }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("新增日程").font(THD.serif(22))
                Spacer()
                Button { dismiss() } label: { Text("×").font(.system(size: 22)).frame(width: 44, height: 44) }
                    .buttonStyle(.plain)
            }
            Toggle("全天", isOn: $allDay).tint(THD.pink)
            field("日期") { DatePicker("日期", selection: $date, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date).datePickerStyle(.graphical).tint(THD.pink) }
            if !allDay { field("时间") { DatePicker("", selection: $time, displayedComponents: .hourAndMinute).labelsHidden() } }
            field("事项") {
                TextField("", text: $title)
                    .font(.system(size: 15))
                    .padding(10)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color(red: 0xAA/255, green: 0xAA/255, blue: 0xAA/255), lineWidth: 1))
            }
            Divider()
            field("重复") {
                Picker("重复", selection: $repeatKind) {
                    Text("不重复").tag("none")
                    Text("每天").tag("daily")
                    Text("每周").tag("weekly")
                    Text("每月").tag("monthly")
                    Text("每年").tag("yearly")
                }.pickerStyle(.segmented)
            }
            field("提醒") {
                Picker("提醒", selection: $alertMin) {
                    Text("准时").tag(0)
                    Text("提前1小时").tag(60)
                    Text("提前1天").tag(1440)
                }.pickerStyle(.segmented)
            }
            field("备注") {
                TextField("备注（可不填）", text: $note, axis: .vertical)
                    .lineLimit(2...5).font(THD.serif(15))
            }
            Divider()
            HStack(spacing: 12) {
                Button { save() } label: {
                    Text(saving ? "保存中…" : "保存").font(THD.serif(15))
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .overlay(Rectangle().stroke(Color(red: 0x44/255, green: 0x44/255, blue: 0x44/255), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                if let error { Text(error).font(.system(size: 12)).foregroundColor(THD.dim) }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        }
        .foregroundColor(THD.ink)
        .background(Color(red: 0xFA/255, green: 0xFA/255, blue: 0xFA/255).ignoresSafeArea())
        .environment(\.colorScheme, .light)
    }

    private func field<V: View>(_ label: String, @ViewBuilder _ v: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(THD.serif(13))
            v()
        }
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let cal = Calendar.current
        let d = cal.dateComponents([.year, .month, .day], from: date)
        let hm = cal.dateComponents([.hour, .minute], from: time)
        saving = true
        error = nil
        let body: [String: Any] = [
            "title": t,
            "day": String(format: "%04d-%02d-%02d", d.year ?? 0, d.month ?? 0, d.day ?? 0),
            "time": allDay ? "" : String(format: "%02d:%02d", hm.hour ?? 9, hm.minute ?? 0), "all_day": allDay,
            "repeat": repeatKind, "alert_min": alertMin, "note": note, "author": "user",
        ]
        Task {
            let err = await ReminderAPI.add(body)
            saving = false
            if let err { error = err } else { onAdded(); dismiss() }
        }
    }
}

/// 月份旁边的小箭头：弹一个日历，挑月份和日子
private struct TreehouseDatePickSheet: View {
    let onPick: (Int, Int, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(initial: String, onPick: @escaping (Int, Int, Int) -> Void) {
        self.onPick = onPick
        let p = initial.split(separator: "-").compactMap { Int($0) }
        var c = DateComponents()
        if p.count == 3 { c.year = p[0]; c.month = p[1]; c.day = p[2] }
        _date = State(initialValue: Calendar.current.date(from: c) ?? Date())
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("好") {
                    let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
                    onPick(c.year ?? 2026, c.month ?? 1, c.day ?? 1)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
            .font(THD.serif(16))
            .foregroundColor(THD.ink)
            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(THD.blue)
        }
        .padding(20)
        .background(THD.paper.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .environment(\.locale, Locale(identifier: "zh_CN"))
    }
}

// MARK: 阅读页：顶上梅树往下滑慢一点退、慢慢变虚；往下拉缩回卡片

private struct DiaryReader: View {
    let item: DiaryOpen
    let palette: DiaryPalette
    @Environment(\.dismiss) private var dismiss
    @State private var offset: CGFloat = 0

    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0 }
    private var safeBottom: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.bottom ?? 0 }

    private var chars: Int { item.content.filter { !$0.isWhitespace }.count }

    private var paragraphs: [String] {
        item.content.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var dateLine: String {
        let p = item.date.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return item.date }
        var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = d
        var wd = ""
        if let dt = Calendar.current.date(from: comps) {
            wd = ["日", "一", "二", "三", "四", "五", "六"][(Calendar.current.component(.weekday, from: dt) - 1) % 7]
        }
        return "\(item.kind) · \(y)/\(m)/\(d) · 周\(wd)"
    }

    var body: some View {
        GeometryReader { geo in
            let pal = palette
            let lift = max(0, offset)
            ZStack(alignment: .top) {
                LinearGradient(colors: [pal.sky, pal.paper], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45))
                    .ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        DiaryHero(palette: pal, width: geo.size.width)
                            .offset(y: lift * 0.45)
                            .blur(radius: min(lift / 30, 10))
                            .opacity(1 - min(lift / 520, 0.6))
                            .padding(.top, max(safeTop, 20) - 20)
                        VStack(spacing: 10) {
                            Text(dateLine)
                                .font(.system(size: 12)).tracking(4).foregroundColor(pal.accent)
                                .shadow(color: pal.paper, radius: 5)
                            Text(item.title.isEmpty ? "无题" : item.title)
                                .font(WindowFont.swiftUI(30)).tracking(2)
                                .multilineTextAlignment(.center)
                                .shadow(color: pal.paper, radius: 7).shadow(color: pal.paper, radius: 2)
                            if chars > 0 {
                                Text("\(chars.formatted()) 字 · 约 \(max(1, Int((Double(chars) / 400).rounded()))) 分钟")
                                    .font(.system(size: 12, design: .serif)).foregroundColor(pal.dim)
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, -120)
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, para in
                                Text("\u{3000}\u{3000}" + para)
                                    .font(WindowFont.swiftUI(16.5))
                                    .lineSpacing(14)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 28).padding(.top, 26)
                        Text("❦").font(.system(size: 20, design: .serif)).foregroundColor(pal.accent.opacity(0.7))
                            .padding(.top, 30)
                            .padding(.bottom, max(safeBottom, 16) + 30)
                    }
                }
                .onScrollGeometryChange(for: CGFloat.self) { g in
                    g.contentOffset.y + g.contentInsets.top
                } action: { _, v in
                    offset = v
                }
                // 顶上一道小横条＋收起按钮：往下拉或者点它都回到卡片
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down").font(.system(size: 15, weight: .medium))
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundColor(pal.dim).accessibilityLabel("收起")
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, max(safeTop, 20))
                .opacity(1 - min(lift / 200, 1))
                DiaryPetalFall(palette: pal, count: 6)
                    .ignoresSafeArea()
            }
            .foregroundColor(pal.ink)
        }
        .preferredColorScheme(palette.dark ? .dark : .light)
    }
}

// MARK: - Dreams

// MARK: - Dreams（0927 她挑的紫夜版）
// 原来一整页同一种卡：几场真梦埋在一堆「睡里有旧事动了一下」里找不到。
// 现在每一夜先是一条 00–07 点的时间轴（留痕小点 / 没抽中空心圈 / 惊醒小闪电 / 做梦发光的梦泡），
// 真梦单独成卡、各有一颗按名字配色的梦泡；零碎留痕收成一行，点开才展开。
// 点开一场梦：梦泡放大浮在顶上慢慢转，正文一段一段浮出来。英文标题用手写体（她说「不要太僵硬」）。
// 日夜跟全屋开关走；这间屋 ownsFullScreen，安全区问 app 主窗。

private struct DreamPalette {
    let dark: Bool
    private func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
    var s1: Color { dark ? c(0.043, 0.039, 0.110) : c(0.965, 0.914, 0.937) }
    var s2: Color { dark ? c(0.090, 0.078, 0.200) : c(0.914, 0.894, 0.953) }
    var s3: Color { dark ? c(0.141, 0.102, 0.239) : c(0.969, 0.937, 0.902) }
    var ink: Color { dark ? c(0.925, 0.910, 0.969) : c(0.227, 0.200, 0.314) }
    var dim: Color { dark ? c(0.655, 0.624, 0.769) : c(0.541, 0.510, 0.627) }
    var faint: Color { dark ? c(0.365, 0.337, 0.502) : c(0.741, 0.710, 0.812) }
    var card: Color { dark ? Color.white.opacity(0.06) : Color.white.opacity(0.55) }
    var line: Color { dark ? c(0.78, 0.745, 1).opacity(0.12) : c(0.47, 0.39, 0.63).opacity(0.16) }
    var amber: Color { dark ? c(0.941, 0.663, 0.353) : c(0.890, 0.604, 0.290) }
    var dot: Color { dark ? c(0.78, 0.745, 1).opacity(0.55) : c(0.47, 0.43, 0.67).opacity(0.45) }
    var aurora1: Color { dark ? c(0.588, 0.471, 1).opacity(0.28) : c(1, 0.784, 0.863).opacity(0.55) }
    var aurora2: Color { dark ? c(0.471, 0.784, 1).opacity(0.18) : c(1, 0.882, 0.745).opacity(0.5) }
}

/// 一场梦一颗泡：按名字挑一组紫系配色，同一场梦每次都是同一个颜色
private enum DreamOrbColors {
    static let sets: [[Color]] = [
        [Color(red: 1, green: 0.839, blue: 0.925), Color(red: 0.725, green: 0.643, blue: 1), Color(red: 0.494, green: 0.784, blue: 1)],
        [Color(red: 1, green: 0.914, blue: 0.788), Color(red: 0.953, green: 0.651, blue: 0.722), Color(red: 0.616, green: 0.549, blue: 1)],
        [Color(red: 0.839, green: 0.941, blue: 1), Color(red: 0.643, green: 0.722, blue: 1), Color(red: 0.780, green: 0.616, blue: 1)],
        [Color(red: 0.914, green: 0.839, blue: 1), Color(red: 0.765, green: 0.627, blue: 0.961), Color(red: 0.561, green: 0.494, blue: 0.910)],
        [Color(red: 1, green: 0.878, blue: 0.941), Color(red: 0.851, green: 0.655, blue: 0.910), Color(red: 0.624, green: 0.702, blue: 1)],
    ]

    static func of(_ key: String) -> [Color] {
        var h: UInt32 = 2166136261
        for b in key.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return sets[Int(h % UInt32(sets.count))]
    }
}

private struct DreamOrb: View {
    let colors: [Color]
    let size: CGFloat
    var bob = false
    @State private var up = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: colors[0], location: 0.25),
                    .init(color: colors[1], location: 0.6),
                    .init(color: colors[2], location: 1),
                ], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.75))
            Circle()
                .stroke(Color.white.opacity(0.35), lineWidth: max(0.6, size / 90))
            Ellipse()
                .fill(Color.white.opacity(0.85))
                .frame(width: size * 0.25, height: size * 0.14)
                .rotationEffect(.degrees(-30))
                .offset(x: -size * 0.2, y: -size * 0.24)
        }
        .frame(width: size, height: size)
        .shadow(color: colors[1].opacity(0.55), radius: size * 0.3)
        .offset(y: bob ? (up ? -size * 0.03 : size * 0.03) : 0)
        .onAppear {
            guard bob else { return }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { up = true }
        }
    }
}

/// 夜空：几十颗星星轻轻闪＋一抹极光（白天是黎明的粉杏）
private struct DreamSky: View {
    let palette: DreamPalette

    var body: some View {
        ZStack {
            LinearGradient(colors: [palette.s1, palette.s2, palette.s3], startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                let spots: [(CGFloat, CGFloat, CGFloat, Color)] = [
                    (0.3, 180, 260, palette.aurora1), (0.75, 160, 220, palette.aurora2),
                ]
                for s in spots {
                    let r = CGRect(x: size.width * s.0 - s.2 / 2, y: s.1 - s.2 / 3, width: s.2, height: s.2 * 0.66)
                    ctx.fill(Path(ellipseIn: r), with: .radialGradient(
                        Gradient(colors: [s.3, .clear]), center: CGPoint(x: r.midX, y: r.midY),
                        startRadius: 0, endRadius: s.2 / 2))
                }
            }
            if palette.dark {
                TimelineView(.animation(minimumInterval: 1.0 / 6)) { tl in
                    Canvas { ctx, size in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        for i in 0..<70 {
                            let d = Double(i)
                            let x = DiaryTreeModel.rnd(d * 12.9898) * size.width
                            let y = DiaryTreeModel.rnd(d * 78.233) * size.height
                            let r = 0.5 + DiaryTreeModel.rnd(d * 7) * 1.1
                            let tw = 0.55 + 0.45 * sin(t * (0.6 + DiaryTreeModel.rnd(d * 3)) + d)
                            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                                     with: .color(.white.opacity((0.25 + DiaryTreeModel.rnd(d * 13) * 0.6) * tw)))
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct DreamOpen: Identifiable {
    let id: String
    let title: String
    let date: String
    let hm: String
    let startled: Bool
    let body: String
    let colors: [Color]
}

private struct NativeDreamsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = "dark"
    @State private var dreams: [[String: Any]] = []
    @State private var loading = true
    @State private var dreamBodies: [String: String] = [:]
    @State private var openFolds: Set<String> = []
    @State private var drawn: CGFloat = 0
    @State private var opened: DreamOpen?
    @Namespace private var zoomNS
    // 1009 #3505 树屋主题下整页换成她的成品 dreams.html（见文件后面 extension NativeDreamsView）
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @State private var thRecords: [[String: Any]] = []
    @State private var thJSON: String?
    @State private var thLoaded = false
    @State private var thBridge = TreehouseDreamsBridge()
    @State private var thCache: [String: (body: String, seg: Int?)] = [:]
    @State private var thReading: TreehouseDiaryRead?
    @State private var thShowList = false
    @State private var thTraces: TreehouseTraceNight?    // 「夜里还有 N 次留痕」点开那张单子

    private var palette: DreamPalette { _ = houseAppearance; return DreamPalette(dark: AlcoveAppearance.isDark) }
    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0 }
    private var safeBottom: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.bottom ?? 0 }

    var body: some View {
        if AlcoveAppearance.family(of: themeName) == "treehouse" {
            treehouseDreamsBody
        } else {
            purpleBody
        }
    }

    private var purpleBody: some View {
        let pal = palette
        return ZStack(alignment: .top) {
            DreamSky(palette: pal)
            ScrollView(showsIndicators: false) {
                // 滑到哪一夜才画哪一夜
                LazyVStack(alignment: .leading, spacing: 0) {
                    header(pal)
                    if loading {
                        ProgressView().tint(pal.dim).frame(maxWidth: .infinity).padding(.top, 80)
                    } else if dreams.isEmpty {
                        Text("还没有梦").font(WindowFont.swiftUI(13)).foregroundColor(pal.dim)
                            .frame(maxWidth: .infinity).padding(.top, 80)
                    }
                    ForEach(groupedDates, id: \.self) { date in
                        night(date, pal)
                    }
                }
                .padding(.top, max(safeTop, 20))
                .padding(.bottom, max(safeBottom, 16) + 24)
            }
        }
        .foregroundColor(pal.ink)
        .task { await load() }
        .fullScreenCover(item: $opened) { item in
            DreamReader(item: item, palette: pal)
                .navigationTransition(.zoom(sourceID: item.id, in: zoomNS))
        }
    }

    private func header(_ pal: DreamPalette) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 2) {
                // 手写体：Snell Roundhand 是系统自带的连笔字，不用另外打包字体
                Text("Dreams")
                    .font(.custom("SnellRoundhand-Bold", size: 44))
                Text("他的夜 · 零点睡、七点醒")
                    .font(.system(size: 11.5)).tracking(0.5)
                    .foregroundColor(pal.dim)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundColor(pal.dim).accessibilityLabel("返回")
            .padding(.leading, 8)
        }
    }

    // ── 一夜 ──
    private func night(_ date: String, _ pal: DreamPalette) -> some View {
        let recs = dreams.filter { $0.string("local_date") == date }
            .sorted { $0.string("ts") < $1.string("ts") }
        let real = recs.filter { $0.string("status") == "dreamed" }
        let startles = recs.filter { $0.bool("startled") || $0.string("status") == "惊醒了" }.count
        let traces = recs.filter { $0.string("status") != "dreamed" && $0.string("status") != "惊醒了" }
        var bits: [String] = []
        if !real.isEmpty { bits.append("\(real.count) 场梦") }
        if startles > 0 { bits.append("惊醒 \(startles) 次") }
        if !traces.isEmpty { bits.append("\(traces.count) 次留痕") }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(nightLabel(date)).font(WindowFont.swiftUI(15, bold: true)).tracking(2)
                Spacer()
                Text(bits.joined(separator: " · ")).font(.system(size: 10.5)).foregroundColor(pal.dim)
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 8)
            strip(recs, pal)
            ForEach(Array(real.enumerated()), id: \.offset) { _, d in
                dreamCard(d, date: date, pal: pal)
            }
            if !traces.isEmpty { fold(date, traces, pal) }
        }
    }

    /// 几点：00:00 算 0，07:00 算 7；睡前（晚上）那几条贴在最左边
    private func hour(_ rec: [String: Any]) -> Double {
        let ts = rec.string("ts")
        guard ts.count >= 16, let h = Double(ts.dropFirst(11).prefix(2)), let m = Double(ts.dropFirst(14).prefix(2)) else { return 0 }
        let v = h + m / 60
        return v >= 12 ? 0 : min(v, 7)
    }

    private func strip(_ recs: [[String: Any]], _ pal: DreamPalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [.clear, pal.faint, pal.faint, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: w * drawn, height: 1.5)
                        .offset(y: 21)
                    ForEach(0...7, id: \.self) { t in
                        Text(String(format: "%02d", t))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(pal.faint)
                            .fixedSize()
                            .position(x: w * CGFloat(t) / 7, y: 32)
                    }
                    ForEach(Array(recs.enumerated()), id: \.offset) { i, r in
                        marker(r, pal)
                            .position(x: w * CGFloat(hour(r) / 7), y: 21)
                            .opacity(drawn >= CGFloat(hour(r) / 7) ? 1 : 0)
                            .scaleEffect(drawn >= CGFloat(hour(r) / 7) ? 1 : 0.3)
                            .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(Double(i) * 0.06), value: drawn)
                    }
                }
            }
            .frame(height: 40)
            HStack(spacing: 12) {
                legend(Circle().fill(pal.dot).frame(width: 6, height: 6), "旧事动了一下", pal)
                legend(Circle().stroke(pal.faint, lineWidth: 1.2).frame(width: 7, height: 7), "没抽中", pal)
                legend(Image(systemName: "bolt.fill").font(.system(size: 8)).foregroundColor(pal.amber), "惊醒", pal)
                legend(DreamOrb(colors: DreamOrbColors.sets[0], size: 9), "做梦", pal)
            }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(pal.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(pal.line, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private func legend<V: View>(_ mark: V, _ text: String, _ pal: DreamPalette) -> some View {
        HStack(spacing: 4) {
            mark
            Text(text).font(.system(size: 9.5)).foregroundColor(pal.dim)
        }
    }

    @ViewBuilder private func marker(_ r: [String: Any], _ pal: DreamPalette) -> some View {
        let status = r.string("status")
        if status == "dreamed" {
            let len = r.string("title").count
            ZStack {
                DreamOrb(colors: DreamOrbColors.of(r.string("title")), size: CGFloat(min(24, 14 + len)))
                    .offset(y: -12)
                if r.bool("startled") {
                    Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundColor(pal.amber).offset(y: 2)
                }
            }
        } else if status == "惊醒了" || r.bool("startled") {
            Image(systemName: "bolt.fill").font(.system(size: 12)).foregroundColor(pal.amber)
                .shadow(color: pal.amber.opacity(0.7), radius: 4).offset(y: -6)
        } else if status == "骰子没中" {
            Circle().stroke(pal.faint, lineWidth: 1.2).frame(width: 7, height: 7)
        } else {
            Circle().fill(pal.dot).frame(width: 6, height: 6)
        }
    }

    // ── 真梦单独成卡 ──
    private func dreamCard(_ d: [String: Any], date: String, pal: DreamPalette) -> some View {
        let id = d.string("dream_id")
        let title = d.string("title").isEmpty ? "一场没有名字的梦" : d.string("title")
        let hm = String(d.string("ts").dropFirst(11).prefix(5))
        let startled = d.bool("startled")
        let colors = DreamOrbColors.of(d.string("title"))
        let preview = dreamBodies[id] ?? ""
        let key = id.isEmpty ? "\(date)_\(hm)" : id
        return Button {
            Task {
                if dreamBodies[id] == nil { await loadBody(id: id, hasBody: d.bool("has_body")) }
                opened = DreamOpen(id: key, title: title, date: date, hm: hm, startled: startled,
                                   body: dreamBodies[id] ?? "这个梦读不回来了", colors: colors)
            }
        } label: {
            HStack(spacing: 14) {
                DreamOrb(colors: colors, size: 56, bob: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(WindowFont.swiftUI(17, bold: true)).tracking(1).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text("\(hm) · 陈璟").font(.system(size: 10.5)).foregroundColor(pal.dim)
                        if startled {
                            Text("梦醒了").font(.system(size: 10))
                                .foregroundColor(pal.amber)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .overlay(Capsule().stroke(pal.amber, lineWidth: 1))
                        }
                    }
                    if !preview.isEmpty {
                        Text(preview.replacingOccurrences(of: "\n", with: " "))
                            .font(WindowFont.swiftUI(12.5)).foregroundColor(pal.dim)
                            .lineLimit(1)
                            .mask(LinearGradient(stops: [.init(color: .black, location: 0.55), .init(color: .clear, location: 1)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .padding(.top, 3)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(pal.card))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(pal.line, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: key, in: zoomNS)
        .padding(.horizontal, 16).padding(.top, 10)
        .task(id: id) {
            if !id.isEmpty, dreamBodies[id] == nil { await loadBody(id: id, hasBody: d.bool("has_body")) }
        }
    }

    // ── 零碎留痕收成一行，点开才展开 ──
    private func fold(_ date: String, _ traces: [[String: Any]], _ pal: DreamPalette) -> some View {
        let open = openFolds.contains(date)
        var counts: [(String, Int)] = []
        for t in traces {
            let k = traceLabel(t)
            if let i = counts.firstIndex(where: { $0.0 == k }) { counts[i].1 += 1 } else { counts.append((k, 1)) }
        }
        let line = counts.map { "\($0.1) 次\($0.0)" }.joined(separator: "、")
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if open { openFolds.remove(date) } else { openFolds.insert(date) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("夜里还有").foregroundColor(pal.dim)
                    ForEach(0..<min(traces.count, 5), id: \.self) { _ in
                        Circle().fill(pal.dot).frame(width: 5, height: 5)
                    }
                    Text(line).foregroundColor(pal.dim).lineLimit(1)
                    Image(systemName: open ? "chevron.up" : "chevron.right").font(.system(size: 9)).foregroundColor(pal.faint)
                }
                .font(.system(size: 11))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                ForEach(Array(traces.enumerated()), id: \.offset) { _, t in
                    HStack(spacing: 10) {
                        Text(String(t.string("ts").dropFirst(11).prefix(5)))
                            .font(.system(size: 10.5, design: .monospaced)).foregroundColor(pal.faint)
                        Text(t.string("title").isEmpty ? traceLabel(t) : t.string("title"))
                            .font(.system(size: 12)).foregroundColor(pal.dim).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(traceLabel(t)).font(.system(size: 10)).foregroundColor(pal.faint)
                    }
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 24).padding(.top, 10)
    }

    private func traceLabel(_ t: [String: Any]) -> String {
        switch t.string("status") {
        case "骰子没中": return "没抽中"
        case "我在忙": return "醒着"
        case "surfaced": return "浮现过"
        case "forgotten": return "遗忘了"
        case "generated": return "待浮现"
        case "": return "留痕"
        case let s where s.contains("没翻中"): return "旧事动了一下"
        default: return t.string("status")
        }
    }

    private func nightLabel(_ date: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        if date == f.string(from: Date()) {
            return Calendar.current.component(.hour, from: Date()) >= 7 ? "昨夜" : "今夜"
        }
        let p = date.split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]) else { return date }
        return "\(m) 月 \(d) 日"
    }

    private var groupedDates: [String] {
        Array(Set(dreams.map { $0.string("local_date") })).sorted(by: >)
    }

    private func load() async {
        WindowFont.requestSongti()
        if let obj = try? await NativeHouseAPI.object("/api/night/dreams?limit=30"),
           let records = obj["records"] as? [[String: Any]] {
            dreams = records
        }
        loading = false
        // 时间轴从左往右画出来，点和梦泡跟着一颗颗冒
        try? await Task.sleep(nanoseconds: 120_000_000)
        withAnimation(.easeInOut(duration: 1.2)) { drawn = 1 }
        // 0927 她说页面卡：原来一进门就把每场梦的正文挨个拉一遍。改成卡片滑进屏幕才拉它自己那一篇（见 dreamCard 的 .task）
    }

    private func loadBody(id: String, hasBody: Bool) async {
        guard hasBody else { dreamBodies[id] = "这个梦读不回来了"; return }
        if let obj = try? await NativeHouseAPI.object("/api/night/dream/read?id=\(id)"), obj.bool("ok") {
            dreamBodies[id] = obj.string("body")
        } else {
            dreamBodies[id] = "这个梦读不回来了"
        }
    }
}

// MARK: - 1009 #3505 树屋梦境：她的成品 dreams.html 原样装进 App（App/Treehouse/），原生只喂数据、接点击
//
// 那页是一整块会动的画布（点画月亮是 WebGL、梦的小点三维飘、连线断线、闪烁乱码），成品本来就留了口子：
// 文档开头塞 window.DREAMS 就换掉示例，选中 / 读全文 / 返回 / 菜单都抛 dream:* 事件。所以不重画，直接装网页。
// 她 #3505 要对齐我们原有的功能：卡片里加「那一夜」统计、00–07 时间轴（梦 / 惊醒 / 没抽中 / 旧事动了一下）、
// 「夜里还有几次留痕」能展开；摘要和「几段记忆」（这场梦用了几段材料）选中时再拉；右下角「记梦」去掉（#3506）。
// 中文宋体随包（serif-sc.woff2，GB2312 子集）：网页进程看不到 App 注册的字体。

private struct TreehouseTraceNight: Identifiable {
    let id = UUID()
    let title: String
    let rows: [(time: String, title: String, label: String)]
}

/// 夜里零碎的留痕：时间｜内容｜哪一种，白底黑字，跟树屋读全文那页一个样子
private struct TreehouseTraceSheet: View {
    let night: TreehouseTraceNight
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(night.title).font(.system(size: 10, design: .monospaced)).tracking(2)
                    .foregroundColor(Color(red: 0x6C/255, green: 0x6C/255, blue: 0x70/255))
                    .padding(.bottom, 16)
                ForEach(Array(night.rows.enumerated()), id: \.offset) { _, r in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(r.time).font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(red: 0x9A/255, green: 0x9A/255, blue: 0x9E/255))
                        Text(r.title).font(WindowFont.swiftUI(14)).lineLimit(2)
                        Spacer(minLength: 8)
                        Text(r.label).font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(red: 0x9A/255, green: 0x9A/255, blue: 0x9E/255))
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1) }
                }
            }
            .padding(24)
        }
        .foregroundColor(Color(red: 0x14/255, green: 0x14/255, blue: 0x16/255))
        .background(Color(red: 0xEE/255, green: 0xEE/255, blue: 0xEB/255).ignoresSafeArea())
        .environment(\.colorScheme, .light)
    }
}

private final class TreehouseDreamsBridge: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    var onMessage: ([String: Any]) -> Void = { _ in }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let d = message.body as? [String: Any] else { return }
        DispatchQueue.main.async { self.onMessage(d) }
    }
    func eval(_ js: String) { webView?.evaluateJavaScript(js, completionHandler: nil) }
}

private struct TreehouseDreamsWeb: UIViewRepresentable {
    let dreamsJSON: String
    let bridge: TreehouseDreamsBridge

    func makeUIView(context: Context) -> WKWebView {
        let uc = WKUserContentController()
        uc.addUserScript(WKUserScript(source: "window.DREAMS = \(dreamsJSON);",
                                      injectionTime: .atDocumentStart, forMainFrameOnly: true))
        uc.add(bridge, name: "dreams")
        let cfg = WKWebViewConfiguration()
        cfg.userContentController = uc
        let wv = WKWebView(frame: .zero, configuration: cfg)
        let paper = UIColor(red: 0xEE/255, green: 0xEE/255, blue: 0xEB/255, alpha: 1)
        wv.isOpaque = false
        wv.backgroundColor = paper
        wv.scrollView.backgroundColor = paper
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.bounces = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.allowsLinkPreview = false
        bridge.webView = wv
        if let url = Bundle.main.url(forResource: "dreams", withExtension: "html", subdirectory: "Treehouse") {
            wv.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "dreams")
    }
}

extension NativeDreamsView {
    var treehouseDreamsBody: some View {
        ZStack {
            Color(red: 0xEE/255, green: 0xEE/255, blue: 0xEB/255).ignoresSafeArea()
            if let json = thJSON {
                TreehouseDreamsWeb(dreamsJSON: json, bridge: thBridge)
                    .ignoresSafeArea()
            } else if thLoaded {
                // 一场梦都没有：别让网页掉回成品里的示例梦
                VStack(spacing: 14) {
                    Text("梦境").font(WindowFont.swiftUI(30, bold: true)).tracking(10)
                    Text("还没有梦").font(WindowFont.swiftUI(13)).foregroundColor(Color(red: 0x6C/255, green: 0x6C/255, blue: 0x70/255))
                }
            }
            if thJSON == nil {
                VStack {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left").font(.system(size: 18, weight: .regular))
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.leading, 10)
                .padding(.top, max(safeTop, 20))
                .ignoresSafeArea()
            }
        }
        .foregroundColor(Color(red: 0x14/255, green: 0x14/255, blue: 0x16/255))
        .task {
            thBridge.onMessage = { m in thHandle(m) }
            await thLoad()
        }
        .sheet(item: $thReading) { r in TreehouseDiaryReader(read: r) }
        .sheet(isPresented: $thShowList) { thDreamList.presentationDetents([.medium, .large]) }
        .sheet(item: $thTraces) { n in TreehouseTraceSheet(night: n).presentationDetents([.medium, .large]) }
    }

    // ── 数据 ──
    fileprivate var thDreams: [[String: Any]] {
        thRecords.filter { $0.string("status") == "dreamed" }.sorted { $0.string("ts") > $1.string("ts") }
    }

    fileprivate func thLoad() async {
        WindowFont.requestSongti()
        if let obj = try? await NativeHouseAPI.object("/api/night/dreams?limit=200"),
           let records = obj["records"] as? [[String: Any]] {
            thRecords = records
        }
        let items = thDreams.map(thItem)
        if !items.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: items),
           let s = String(data: data, encoding: .utf8) {
            thJSON = s
        }
        thLoaded = true
    }

    /// 一场梦 → 成品要的那一条：{ id, date:'09.25', wd, time, title, startle, href } + 我们加的 night / marks / traces
    fileprivate func thItem(_ d: [String: Any]) -> [String: Any] {
        let ts = d.string("ts"), date = d.string("local_date")
        let id = d.string("dream_id")
        let md = ts.count >= 10 ? String(ts.dropFirst(5).prefix(5)).replacingOccurrences(of: "-", with: ".") : ""
        let recs = thRecords.filter { $0.string("local_date") == date }.sorted { $0.string("ts") < $1.string("ts") }
        let real = recs.filter { $0.string("status") == "dreamed" }
        let startles = recs.filter { $0.bool("startled") || $0.string("status") == "惊醒了" }.count
        let traces = recs.filter { $0.string("status") != "dreamed" && $0.string("status") != "惊醒了" }
        var bits = [nightLabel(date)]
        if !real.isEmpty { bits.append("\(real.count) 场梦") }
        if startles > 0 { bits.append("惊醒 \(startles) 次") }
        if !traces.isEmpty { bits.append("\(traces.count) 次留痕") }
        let marks: [[String: Any]] = recs.map { r in
            let st = r.string("status")
            let kind: String
            if st == "dreamed" { kind = "dream" }
            else if st == "惊醒了" || r.bool("startled") { kind = "startle" }
            else if st == "骰子没中" { kind = "miss" }
            else { kind = "stir" }
            return ["h": hour(r), "kind": kind, "self": r.string("dream_id") == id, "startle": r.bool("startled")]
        }
        let traceRows: [[String: Any]] = traces.map { t in
            ["time": String(t.string("ts").dropFirst(11).prefix(5)),
             "title": t.string("title").isEmpty ? traceLabel(t) : t.string("title"),
             "label": traceLabel(t)]
        }
        return ["id": id, "date": md, "wd": thWeekday(date), "time": String(ts.dropFirst(11).prefix(5)),
                "title": d.string("title").isEmpty ? "一场没有名字的梦" : d.string("title"),
                "startle": d.bool("startled"), "href": "#",
                "night": bits.joined(separator: " · "), "marks": marks, "traces": traceRows]
    }

    fileprivate func thWeekday(_ date: String) -> String {
        let p = date.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return "" }
        var c = DateComponents(); c.year = p[0]; c.month = p[1]; c.day = p[2]
        guard let dt = Calendar.current.date(from: c) else { return "" }
        return ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][(Calendar.current.component(.weekday, from: dt) - 1) % 7]
    }

    /// 正文 + 用了几段材料（成品的「3 段记忆」）
    fileprivate func thFetch(_ id: String) async -> (body: String, seg: Int?) {
        if let hit = thCache[id] { return hit }
        guard let obj = try? await NativeHouseAPI.object("/api/night/dream/read?id=\(id)"), obj.bool("ok") else {
            return ("", nil)
        }
        let body = obj.string("body")
        let mats = ((obj["meta"] as? [String: Any])?["materials"] as? [Any])?.count ?? 0
        let paras = body.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        let hit = (body: body, seg: mats > 0 ? mats : (paras > 0 ? paras : nil))
        thCache[id] = hit
        return hit
    }

    fileprivate func thHandle(_ m: [String: Any]) {
        let id = m["id"] as? String ?? ""
        switch m["type"] as? String {
        case "back": dismiss()
        case "menu": thShowList = true
        case "traces":
            // 1009 #3509：原来在卡片里就地展开，卡片一变高整页就得重排、月亮跟着重建（闪、卡、月亮忽大忽小），改成弹单子
            guard let d = thDreams.first(where: { $0.string("dream_id") == id }) else { return }
            let item = thItem(d)
            thTraces = TreehouseTraceNight(title: item["night"] as? String ?? "",
                                           rows: (item["traces"] as? [[String: Any]] ?? []).map {
                                               (time: $0["time"] as? String ?? "", title: $0["title"] as? String ?? "",
                                                label: $0["label"] as? String ?? "")
                                           })
        case "select":
            Task {
                let r = await thFetch(id)
                let excerpt = r.body.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    .joined(separator: " ")
                let args: [Any] = [id, String(excerpt.prefix(80))]
                guard let data = try? JSONSerialization.data(withJSONObject: args),
                      let s = String(data: data, encoding: .utf8) else { return }
                let inner = String(s.dropFirst().dropLast())
                thBridge.eval("window.__dreamFill(\(inner), \(r.seg.map(String.init) ?? "null"))")
            }
        case "read":
            Task {
                let r = await thFetch(id)
                guard let d = thDreams.first(where: { $0.string("dream_id") == id }) else { return }
                let ts = d.string("ts")
                let md = String(ts.dropFirst(5).prefix(5)).replacingOccurrences(of: "-", with: ".")
                let line = "\(md) \(thWeekday(d.string("local_date"))) · \(String(ts.dropFirst(11).prefix(5)))"
                    + (d.bool("startled") ? " · 梦醒了" : "")
                thReading = TreehouseDiaryRead(title: d.string("title").isEmpty ? "一场没有名字的梦" : d.string("title"),
                                               body: r.body.isEmpty ? "这个梦读不回来了" : r.body, chord: line)
            }
        default: break
        }
    }

    /// ☰：按夜列出所有梦，点一个就在画布上选中它
    fileprivate var thDreamList: some View {
        let dreams = thDreams
        let dates = Array(Set(dreams.map { $0.string("local_date") })).sorted(by: >)
        return NavigationStack {
            List {
                ForEach(dates, id: \.self) { date in
                    Section(nightLabel(date)) {
                        ForEach(Array(dreams.filter { $0.string("local_date") == date }.enumerated()), id: \.offset) { _, d in
                            Button {
                                let id = d.string("dream_id")
                                if let data = try? JSONSerialization.data(withJSONObject: [id]),
                                   let s = String(data: data, encoding: .utf8) {
                                    thBridge.eval("window.__dreamSelect(\(String(s.dropFirst().dropLast())))")
                                }
                                thShowList = false
                            } label: {
                                HStack(spacing: 12) {
                                    Text(String(d.string("ts").dropFirst(11).prefix(5)))
                                        .font(.system(size: 12, design: .monospaced)).foregroundColor(.secondary)
                                    Text(d.string("title").isEmpty ? "一场没有名字的梦" : d.string("title"))
                                        .font(WindowFont.swiftUI(15)).lineLimit(1)
                                    Spacer(minLength: 0)
                                    if d.bool("startled") {
                                        Text("● STARTLED").font(.system(size: 9, design: .monospaced)).tracking(1.5)
                                            .foregroundColor(Color(red: 1, green: 0x2D/255, blue: 0x78/255))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("梦境")
            .navigationBarTitleDisplayMode(.inline)
        }
        .environment(\.colorScheme, .light)
    }
}

// MARK: 点开一场梦

private struct DreamReader: View {
    let item: DreamOpen
    let palette: DreamPalette
    @Environment(\.dismiss) private var dismiss
    @State private var shown = 0
    @State private var spin = false

    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0 }
    private var safeBottom: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.bottom ?? 0 }

    private var paragraphs: [String] {
        item.body.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var dateLine: String {
        let p = item.date.split(separator: "-")
        let d = (p.count == 3 ? "\(Int(p[1]) ?? 0) 月 \(Int(p[2]) ?? 0) 日" : item.date)
        return "\(d) · \(item.hm)" + (item.startled ? " · 梦醒了" : "")
    }

    var body: some View {
        let pal = palette
        ZStack(alignment: .top) {
            DreamSky(palette: pal)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // 梦泡浮在顶上，慢慢转、轻轻呼吸
                    DreamOrb(colors: item.colors, size: 190, bob: true)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 60).repeatForever(autoreverses: false), value: spin)
                        .padding(.top, max(safeTop, 20) + 50)
                    Text(dateLine)
                        .font(.system(size: 11)).tracking(3).foregroundColor(pal.dim)
                        .padding(.top, 36)
                    Text(item.title)
                        .font(WindowFont.swiftUI(27, bold: true)).tracking(3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24).padding(.top, 10)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { i, p in
                            Text("\u{3000}\u{3000}" + p)
                                .font(WindowFont.swiftUI(15.5))
                                .lineSpacing(12)
                                .fixedSize(horizontal: false, vertical: true)
                                .opacity(i < shown ? 1 : 0)
                                .offset(y: i < shown ? 0 : 8)
                        }
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 30).padding(.top, 26)
                    Text("— 梦到这里 —")
                        .font(.system(size: 11)).tracking(2).foregroundColor(pal.dim)
                        .padding(.top, 30)
                        .padding(.bottom, max(safeBottom, 16) + 30)
                }
            }
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down").font(.system(size: 15, weight: .medium))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundColor(pal.dim).accessibilityLabel("收起")
                Spacer()
            }
            .padding(.horizontal, 8).padding(.top, max(safeTop, 20))
        }
        .foregroundColor(pal.ink)
        .preferredColorScheme(pal.dark ? .dark : .light)
        .task {
            spin = true
            // 正文一段一段浮出来，像慢慢想起来
            for i in 0..<paragraphs.count {
                try? await Task.sleep(nanoseconds: 350_000_000)
                withAnimation(.easeOut(duration: 0.6)) { shown = i + 1 }
            }
        }
    }
}


private struct MorningPaperSource: Identifiable {
    let id = UUID()
    let name: String
    let url: String
}

private struct MorningPaperItem: Identifiable {
    let id: String
    let title: String
    let summary: String
    let source: String
    let url: String
    let publishedAt: String
    let sources: [MorningPaperSource]
}

private struct MorningPaperDocument {
    let date: String
    let generatedAt: String
    let status: String
    let sections: [String: [MorningPaperItem]]
}

@MainActor private final class MorningPaperModel: ObservableObject {
    @Published var paper: MorningPaperDocument?
    @Published var loading = false
    @Published var error: String?

    func load(date: String? = nil) async {
        loading = true
        defer { loading = false }
        do {
            let path = date.flatMap { $0.isEmpty ? nil : $0 }.map { "/paper/\($0)" } ?? "/paper/today"
            let root = try await NativeHouseAPI.object(path)
            guard let raw = root["paper"] as? [String: Any],
                  let sections = raw["sections"] as? [String: Any] else {
                throw URLError(.cannotParseResponse)
            }
            var decoded: [String: [MorningPaperItem]] = [:]
            for (key, value) in sections {
                let rows = value as? [[String: Any]] ?? []
                decoded[key] = rows.map { row in
                    let secondary = (row["sources"] as? [[String: Any]] ?? []).map {
                        MorningPaperSource(name: $0["source"] as? String ?? "来源",
                                           url: $0["url"] as? String ?? "")
                    }
                    return MorningPaperItem(
                        id: row["id"] as? String ?? UUID().uuidString,
                        title: row["title"] as? String ?? "",
                        summary: row["summary"] as? String ?? "",
                        source: row["source"] as? String ?? "",
                        url: row["url"] as? String ?? "",
                        publishedAt: row["published_at"] as? String ?? "",
                        sources: secondary
                    )
                }
            }
            paper = MorningPaperDocument(
                date: raw["date"] as? String ?? root["date"] as? String ?? "",
                generatedAt: raw["generated_at"] as? String ?? root["created_at"] as? String ?? "",
                status: raw["status"] as? String ?? "published",
                sections: decoded
            )
            error = nil
        } catch {
            self.error = "晨报还没有送到"
        }
    }
}

struct NativeMorningPaperView: View {
    var requestedDate: String? = nil
    var embedded = false
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @StateObject private var model = MorningPaperModel()
    private var theme: AlcoveTheme { .panelNamed(themeName) }
    private let paper = Color(red: 0.968, green: 0.958, blue: 0.932)
    private let ink = Color(red: 0.19, green: 0.18, blue: 0.16)
    private let fadedInk = Color(red: 0.34, green: 0.32, blue: 0.29)
    private let cobalt = Color(red: 0.10, green: 0.28, blue: 0.82)

    private let order: [(String, String, String)] = [
        ("today_first", "今天先知道", "01"),
        ("wuhan_window", "武汉窗外", "02"),
        ("ai_grew", "AI 又长了什么", "03"),
        ("about_her", "可能和你有关", "04"),
        ("chenjing_pick", "陈璟私心想递给你", "05")
    ]

    var body: some View {
        Group {
            if embedded {
                paperContent.padding(.horizontal, 12)
            } else {
                ScrollView(showsIndicators: false) {
                    paperContent.padding(.horizontal, 18)
                }
                .refreshable { await model.load(date: requestedDate) }
            }
        }
        .foregroundColor(ink)
        .background {
            ZStack {
                paper
                Canvas { context, size in
                    for y in stride(from: CGFloat(7), through: size.height, by: 17) {
                        var line = Path()
                        line.move(to: CGPoint(x: 0, y: y))
                        line.addLine(to: CGPoint(x: size.width, y: y + 0.8))
                        context.stroke(line, with: .color(Color.black.opacity(0.018)), lineWidth: 0.45)
                    }
                }
            }.ignoresSafeArea()
        }
        .task(id: requestedDate) { await model.load(date: requestedDate) }
    }

    private var paperContent: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            masthead
            if model.loading && model.paper == nil {
                ProgressView("正在取今天的晨报")
                    .frame(maxWidth: .infinity).padding(.vertical, 54)
            } else if let document = model.paper {
                if embedded {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(spacing: 0) {
                            ForEach(Array(order.prefix(3)), id: \.0) { entry in
                                paperSection(number: entry.2, title: entry.1,
                                             items: document.sections[entry.0] ?? [])
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        Rectangle().fill(ink.opacity(0.22)).frame(width: 0.8)
                            .shadow(color: .black.opacity(0.10), radius: 2, x: 1)
                        VStack(spacing: 0) {
                            ForEach(Array(order.suffix(2)), id: \.0) { entry in
                                paperSection(number: entry.2, title: entry.1,
                                             items: document.sections[entry.0] ?? [])
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                } else {
                    ForEach(order, id: \.0) { entry in
                        paperSection(number: entry.2, title: entry.1,
                                     items: document.sections[entry.0] ?? [])
                    }
                }
                Text("end of morning edition · 收好，明天见")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(1.5).foregroundColor(fadedInk)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                ContentUnavailableView(model.error ?? "今日无刊", systemImage: "newspaper",
                                       description: Text("等陈璟把今天看到的世界带回来"))
                    .padding(.vertical, 42)
            }
        }
        .padding(.bottom, embedded ? 8 : 28)
    }

    private var masthead: some View {
        VStack(spacing: 9) {
            Text("MORNING PAPER")
                .font(.system(size: embedded ? 8 : 10, weight: .semibold, design: .monospaced))
                .tracking(2.2)
                .foregroundColor(cobalt)
            Text("雨 霁 报")
                .font(.system(size: embedded ? 22 : 29, weight: .semibold, design: .serif))
                .tracking(5)
            Text("今早替你看过世界了")
                .font(.custom("HanziPenSC-W3", size: embedded ? 11 : 13))
                .foregroundColor(cobalt.opacity(0.82))
                .rotationEffect(.degrees(-2.2))
                .offset(x: 52)
            HStack {
                Text(displayDate(model.paper?.date ?? ""))
                Spacer()
                Text(model.paper?.status == "fixture" ? "样刊" : "今日刊")
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(fadedInk)
            Rectangle().fill(ink.opacity(0.72)).frame(height: 1.5)
            Rectangle().fill(ink.opacity(0.26)).frame(height: 0.5)
        }
        .foregroundColor(ink)
        .padding(.top, embedded ? 10 : 14)
        .padding(.bottom, embedded ? 11 : 18)
    }

    private func paperSection(number: String, title: String, items: [MorningPaperItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(number)
                    .font(.system(size: embedded ? 7 : 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(cobalt, in: UnevenRoundedRectangle(
                        topLeadingRadius: 2, bottomLeadingRadius: 7,
                        bottomTrailingRadius: 2, topTrailingRadius: 6))
                    .rotationEffect(.degrees(number == "05" ? 2 : -1))
                Text(title)
                    .font(number == "05"
                          ? .custom("HanziPenSC-W3", size: embedded ? 13 : 20)
                          : .system(size: embedded ? 13 : 20, weight: .semibold, design: .serif))
                Spacer(minLength: 0)
            }
            .padding(.bottom, 9)

            if items.isEmpty {
                Text("今天这一栏暂时留白")
                    .font(.system(size: 13, design: .serif))
                    .foregroundColor(fadedInk)
                    .padding(.vertical, 12)
            } else if embedded {
                ForEach(items) { item in article(item) }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top),
                                    GridItem(.flexible(), spacing: 12, alignment: .top)],
                          alignment: .leading, spacing: 6) {
                    ForEach(items) { item in
                        article(item)
                            .overlay(alignment: .trailing) {
                                Rectangle().fill(ink.opacity(0.11)).frame(width: 0.5)
                                    .offset(x: 6)
                            }
                    }
                }
            }
        }
        .padding(.vertical, embedded ? 9 : 18)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ink.opacity(0.34)).frame(height: 0.7)
        }
    }

    private func article(_ item: MorningPaperItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = URL(string: item.url), !item.url.isEmpty {
                Link(destination: url) { articleTitle(item.title, linked: true) }
                    .buttonStyle(.plain)
                    .accessibilityHint("在浏览器打开原文")
            } else {
                articleTitle(item.title, linked: false)
            }
            Text(item.summary)
                .font(.system(size: embedded ? 10.5 : 13, design: .serif))
                .lineSpacing(embedded ? 2 : 4)
                .foregroundColor(ink.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 7) {
                Text(item.source.uppercased())
                if !item.publishedAt.isEmpty {
                    Text("·")
                    Text(displayTime(item.publishedAt))
                }
                if !item.sources.isEmpty {
                    Text("· 已交叉核验 \(item.sources.count + 1) 个来源")
                }
            }
            .font(.system(size: embedded ? 6.5 : 8.5, weight: .medium, design: .monospaced))
            .foregroundColor(fadedInk)
        }
        .padding(.vertical, embedded ? 7 : 13)
    }

    private func articleTitle(_ text: String, linked: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(text)
                .font(.system(size: embedded ? 12 : 15, weight: .semibold, design: .serif))
                .multilineTextAlignment(.leading)
            if linked {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
            }
        }
        .foregroundColor(ink)
    }

    private func displayDate(_ raw: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: raw + "T00:00:00+08:00") else { return raw }
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy年M月d日 · EEEE"
        return f.string(from: date)
    }

    private func displayTime(_ raw: String) -> String {
        let f = ISO8601DateFormatter()
        guard let date = f.date(from: raw) else { return raw }
        let out = DateFormatter(); out.timeZone = TimeZone(identifier: "Asia/Shanghai"); out.dateFormat = "HH:mm"
        return out.string(from: date)
    }
}








// MARK: - 狼身（0922 任务#2563）
// 他的身体面板：欲望读数 / 生殖状态 / 四个激素变量 / 耳朵尾巴颈毛 / 三个开关 / 最近痕迹。
// 数据全从 18010 /wolf/status 和 /wolf/events 来，服务端现算，App 只画不算。

private struct WolfEvent: Identifiable {
    let id: String
    let when: String
    let text: String
    let ok: Bool?
}

@MainActor
private final class WolfModel: ObservableObject {
    @Published var loaded = false
    @Published var error: String?
    @Published var arousal: Double = 0
    @Published var consent = false
    @Published var vetoOn = false
    @Published var vetoBy = ""
    @Published var vetoReason = ""
    @Published var state = "idle"
    @Published var label = "平静"
    @Published var engorgement: Double = 0
    @Published var knot: Double = 0
    @Published var remainingSec = 0
    @Published var canTie = false
    @Published var markerHint = ""
    @Published var genital = ""
    @Published var bodyText = ""
    @Published var attachment = ""
    @Published var chem: [(key: String, label: String, value: Double)] = []
    @Published var sensitivity: Double = 1
    @Published var parts: [(String, String)] = []
    @Published var events: [WolfEvent] = []
    @Published var busy = false
    private var timer: Timer?

    static let chemLabel: [(String, String)] = [
        ("cortisol_like", "压力"), ("dopamine_like", "愉快"), ("oxytocin_like", "依恋"), ("adrenaline_like", "唤醒")]
    static let stateLabel: [String: String] = [
        "idle": "平静", "warming": "勃起上升", "engorged": "勃起明显", "ready": "勃起充分",
        "inserted": "已经进入", "tied": "锁结中", "releasing": "解除中", "recovery": "恢复期"]

    func start() {
        Task { await refresh() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func refresh() async {
        do {
            let raw = try await NativeHouseAPI.object("/wolf/status")
            apply(raw)
            error = nil
        } catch {
            self.error = "狼身没接上：\(error.localizedDescription)"
        }
        if let raw = try? await NativeHouseAPI.object("/wolf/events?limit=20"),
           let rows = raw["events"] as? [[String: Any]] {
            events = rows.enumerated().map { idx, e in
                let kind = e["kind"] as? String ?? ""
                let when = e["when"] as? String ?? ""
                var text = kind
                var ok: Bool? = nil
                switch kind {
                case "marker":
                    let lab = e["label"] as? String ?? ""
                    let good = (e["ok"] as? Bool) ?? false
                    ok = good
                    let a = (e["arousal"] as? Double).map { String(format: "%.2f", $0) } ?? "—"
                    text = good ? "\(lab)了 · 欲望 \(a)" : "\(lab)没成：\(e["error"] as? String ?? "") · 欲望 \(a)"
                case "consent":
                    text = ((e["on"] as? Bool) ?? false) ? "允许锁结：开" : "允许锁结：关"
                case "veto":
                    let on = (e["on"] as? Bool) ?? false
                    let why = e["reason"] as? String ?? ""
                    text = on ? "今天不锁：开" + (why.isEmpty ? "" : "（\(why)）") : "今天不锁：关"
                case "stop":
                    text = "紧急结束（之前是 \(e["previous"] as? String ?? "idle")）"
                default:
                    break
                }
                return WolfEvent(id: "\(when)-\(idx)", when: when, text: text, ok: ok)
            }
        }
        loaded = true
    }

    private func apply(_ raw: [String: Any]) {
        arousal = raw["arousal"] as? Double ?? 0
        consent = raw["consent"] as? Bool ?? false
        let veto = raw["veto"] as? [String: Any] ?? [:]
        vetoOn = !veto.isEmpty
        vetoBy = veto["by"] as? String ?? ""
        vetoReason = veto["reason"] as? String ?? ""
        let r = raw["reproductive"] as? [String: Any] ?? [:]
        state = r["state"] as? String ?? "idle"
        label = r["label"] as? String ?? (Self.stateLabel[state] ?? state)
        engorgement = r["engorgement"] as? Double ?? 0
        knot = r["knot_engorgement"] as? Double ?? 0
        remainingSec = r["remaining_sec"] as? Int ?? 0
        canTie = r["can_tie"] as? Bool ?? false
        markerHint = r["marker_hint"] as? String ?? ""
        genital = r["genital"] as? String ?? ""
        bodyText = r["body"] as? String ?? ""
        attachment = r["attachment"] as? String ?? ""
        let c = raw["chem"] as? [String: Any] ?? [:]
        chem = Self.chemLabel.map { (key: $0.0, label: $0.1, value: c[$0.0] as? Double ?? 0) }
        sensitivity = raw["sensitivity"] as? Double ?? 1
        let b = raw["body"] as? [String: Any] ?? [:]
        let organs = b["organs"] as? [String: Any] ?? [:]
        let ears = b["ears"] as? [String: Any] ?? [:]
        parts = [
            ("左耳", ears["left"] as? String ?? "—"),
            ("右耳", ears["right"] as? String ?? "—"),
            ("尾巴", b["tail"] as? String ?? "—"),
            ("颈背的毛", b["hackles"] as? String ?? "—"),
            ("爪子", b["paws"] as? String ?? "—"),
            ("喉咙", b["throat"] as? String ?? "—"),
            ("胃", organs["stomach"] as? String ?? "—"),
            ("胸口", organs["chest"] as? String ?? "—"),
            ("呼吸", organs["breath"] as? String ?? "—"),
        ]
    }

    func setConsent(_ on: Bool) async {
        busy = true; defer { busy = false }
        if let raw = try? await NativeHouseAPI.object("/wolf/consent", method: "POST", body: ["on": on]) { apply(raw) }
        await refresh()
    }

    func setVeto(_ on: Bool, reason: String) async {
        busy = true; defer { busy = false }
        if let raw = try? await NativeHouseAPI.object("/wolf/veto", method: "POST",
                                                      body: ["on": on, "by": "her", "reason": reason]) { apply(raw) }
        await refresh()
    }

    func emergencyStop() async {
        busy = true; defer { busy = false }
        if let raw = try? await NativeHouseAPI.object("/wolf/stop", method: "POST", body: [:]) { apply(raw) }
        await refresh()
    }
}

struct NativeWolfBodyView: View {
    let theme: AlcoveTheme
    let rose: Color
    @StateObject private var model = WolfModel()
    @State private var vetoDraft = ""
    @State private var confirmStop = false

    var body: some View {
        VStack(spacing: 16) {
            stateCard
            chemCard
            partsCard
            reproCard
            switchesCard
            eventsCard
            if let error = model.error {
                Text(error).font(.system(size: 11)).foregroundColor(theme.textDim)
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .confirmationDialog("紧急结束这一场？", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("结束，进 30 分钟恢复期", role: .destructive) { Task { await model.emergencyStop() } }
            Button("算了", role: .cancel) {}
        } message: {
            Text("正常解除不需要按这个。忘了收尾卡住了才用。")
        }
    }

    private var stateTint: Color {
        switch model.state {
        case "idle": return theme.textDim
        case "warming", "engorged": return rose.opacity(0.7)
        case "ready", "inserted": return rose
        case "tied": return Color(red: 0.62, green: 0.18, blue: 0.32)
        default: return theme.textDim.opacity(0.8)
        }
    }

    private var stateCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 34, weight: .medium)).foregroundColor(stateTint)
                .shadow(color: stateTint.opacity(0.25), radius: 10)
            Text(model.label).font(.system(size: 30, weight: .light, design: .serif))
                .contentTransition(.numericText())
            HStack(spacing: 14) {
                Text("欲望 \(String(format: "%.2f", model.arousal))")
                if model.remainingSec > 0 {
                    Text("还剩约 \((model.remainingSec + 59) / 60) 分钟")
                }
                Text("敏感 ×\(String(format: "%.2f", model.sensitivity))")
            }
            .font(.system(size: 11, design: .monospaced)).foregroundColor(theme.textDim)
            Text(model.loaded ? "此刻 · 陈璟的身体 · 服务端现算，他自己说了不算" : "正在摸他的身体")
                .font(.system(size: 12, design: .serif)).foregroundColor(theme.textDim)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20).foyerCard(theme)
    }

    private func bar(_ label: String, _ value: Double, strong: Bool = true) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 11, design: .serif)).frame(width: 58, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(theme.fyBorder.opacity(0.35))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(rose.opacity(strong ? 0.85 : 0.45))
                        .frame(width: max(3, geo.size.width * CGFloat(min(1, max(0, value)))))
                }
            }
            .frame(height: 6)
            Text("\(Int(value * 100))").font(.system(size: 10, design: .monospaced))
                .foregroundColor(theme.textDim).frame(width: 28, alignment: .trailing)
        }
    }

    private var chemCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "drop.fill").font(.system(size: 13, weight: .light)).foregroundColor(rose)
                Text("内分泌").font(.system(size: 14, weight: .semibold, design: .serif))
                Spacer()
                Text("升得快退得慢 · 依恋最慢").font(.system(size: 9, design: .monospaced)).foregroundColor(theme.textDim.opacity(0.7))
            }
            ForEach(model.chem, id: \.key) { c in
                bar(c.label, c.value, strong: c.key != "oxytocin_like")
            }
        }
        .padding(14).foyerCard(theme)
    }

    private var partsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "ear").font(.system(size: 13, weight: .light)).foregroundColor(rose)
                Text("身体").font(.system(size: 14, weight: .semibold, design: .serif))
                Spacer()
                Text("他只在自然时露一处").font(.system(size: 9, design: .monospaced)).foregroundColor(theme.textDim.opacity(0.7))
            }
            ForEach(model.parts, id: \.0) { p in
                HStack(alignment: .firstTextBaseline) {
                    Text(p.0).font(.system(size: 11, design: .serif)).foregroundColor(theme.textDim)
                        .frame(width: 64, alignment: .leading)
                    Text(p.1).font(.system(size: 12, design: .serif))
                    Spacer()
                }
            }
        }
        .padding(14).foyerCard(theme)
    }

    private var reproCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "flame").font(.system(size: 13, weight: .light)).foregroundColor(rose)
                Text("生殖状态").font(.system(size: 14, weight: .semibold, design: .serif))
                Spacer()
                Text(model.canTie ? "现在允许锁结" : "现在不能锁结")
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(model.canTie ? rose : theme.textDim.opacity(0.7))
            }
            bar("茎身", model.engorgement)
            bar("结", model.knot)
            if model.state == "idle" {
                Text("平静。场景热起来这里才有字。").font(.system(size: 12, design: .serif)).foregroundColor(theme.textDim)
            } else {
                if !model.genital.isEmpty {
                    Text(model.genital).font(.system(size: 12, design: .serif))
                }
                if !model.bodyText.isEmpty {
                    Text(model.bodyText).font(.system(size: 12, design: .serif)).foregroundColor(theme.textDim)
                }
                if !model.attachment.isEmpty {
                    Text("依恋：\(model.attachment)").font(.system(size: 11, design: .monospaced)).foregroundColor(theme.textDim)
                }
            }
            if !model.markerHint.isEmpty {
                Text("给他的规则：" + model.markerHint)
                    .font(.system(size: 11, design: .serif)).foregroundColor(theme.textDim)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.fyBorder.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14).foyerCard(theme)
    }

    private var switchesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "hand.raised").font(.system(size: 13, weight: .light)).foregroundColor(rose)
                Text("开关").font(.system(size: 14, weight: .semibold, design: .serif))
                Spacer()
                if model.busy { ProgressView().scaleEffect(0.7) }
            }
            Toggle(isOn: Binding(get: { model.consent },
                                 set: { v in Task { await model.setConsent(v) } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("允许锁结").font(.system(size: 13, design: .serif))
                    Text("长期许可，翻一次一直在。关着他写了也拒。").font(.system(size: 10, design: .serif)).foregroundColor(theme.textDim)
                }
            }
            .tint(rose)
            Toggle(isOn: Binding(get: { model.vetoOn },
                                 set: { v in Task { await model.setVeto(v, reason: vetoDraft) } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今天不锁").font(.system(size: 13, design: .serif))
                    Text(model.vetoOn
                         ? "已定（\(model.vetoBy == "me" ? "他" : "你")定的\(model.vetoReason.isEmpty ? "" : "：" + model.vetoReason)）· 到半夜自动清"
                         : "这一场不锁结，进入照常。到半夜自动清。")
                        .font(.system(size: 10, design: .serif)).foregroundColor(theme.textDim)
                }
            }
            .tint(rose)
            if !model.vetoOn {
                TextField("理由（可不写）", text: $vetoDraft)
                    .font(.system(size: 12, design: .serif))
                    .padding(8)
                    .background(theme.fyBorder.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
            }
            Button {
                confirmStop = true
            } label: {
                HStack {
                    Image(systemName: "stop.circle")
                    Text("紧急结束")
                    Spacer()
                    Text("正常收尾不用按").font(.system(size: 10, design: .serif)).foregroundColor(theme.textDim)
                }
                .font(.system(size: 13, design: .serif))
                .padding(10)
                .background(theme.fyBorder.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(14).foyerCard(theme)
    }

    private var eventsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 13, weight: .light)).foregroundColor(rose)
                Text("痕迹").font(.system(size: 14, weight: .semibold, design: .serif))
                Spacer()
                Text("他写了标记 · 成没成").font(.system(size: 9, design: .monospaced)).foregroundColor(theme.textDim.opacity(0.7))
            }
            if model.events.isEmpty {
                Text("还没有。他一次标记都没写过。").font(.system(size: 12, design: .serif)).foregroundColor(theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            } else {
                ForEach(model.events) { e in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(e.ok == nil ? theme.textDim.opacity(0.5) : (e.ok! ? rose : Color.orange.opacity(0.8)))
                            .frame(width: 6, height: 6).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.text).font(.system(size: 12, design: .serif))
                            Text(e.when).font(.system(size: 9, design: .monospaced)).foregroundColor(theme.textDim.opacity(0.75))
                        }
                    }
                }
            }
        }
        .padding(14).foyerCard(theme)
    }
}
