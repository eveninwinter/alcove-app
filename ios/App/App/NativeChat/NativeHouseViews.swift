import SwiftUI
import PhotosUI
import UIKit
import AVFoundation
import MediaPlayer
import WebKit
import MapKit
import UniformTypeIdentifiers

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
    case sidebar, chat, terminal, settings, bubbleAppearance, checklist, music
    case home, profile, calendar, digest, wall, usage, workbench, studio
    case memory, dreams, shelf, fiction, nianlun, clockwork, album, portrait, impression, morningPaper, nowhere, pulse
    case pond
    case tarot          // 0902 占星室（塔罗）
    case nursery        // 0905 育儿室（llm-nursery 电子养崽）
    case wallet         // 0907 钱包（他的预算/心愿单/审批，第一期账本）
    case shop           // 0909 商店（她开的店，他拿挣的虚拟币来买）
    case roof
    case factory
    case crosstalk, radio, coread, cowatch, liao, daddyDay, lab, qipai
    case search, favorites, forge, roundtable, surf, letterbox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sidebar: return "Alcove"
        case .home: return "大厅"
        case .profile: return "陈璟"
        case .chat: return "Chat"
        case .terminal: return "Terminal"
        case .settings: return "设置"
        case .bubbleAppearance: return "气泡与文字"
        case .checklist: return "Checklist"
        case .music: return "Music"
        case .calendar: return "Calendar"
        case .digest: return "编年史"
        case .wall: return "小黑屋"
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
        case .portrait: return "Letters"
        case .impression: return "Self"
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
        case .lab: return "Lab"
        case .search: return "Search"
        case .favorites: return "Favorites"
        case .forge: return "Forge"
        case .roundtable: return "圆桌"
        case .surf: return "冲浪收藏"
        case .letterbox: return "信箱"
        }
    }

    /// 自己铺满、自己做头的页面。她0819：不要透壁纸，要全屏
    var ownsFullScreen: Bool {
        switch self {
        case .studio, .pond, .roof, .memory, .digest, .factory, .search, .favorites, .surf,
             .settings, .letterbox, .qipai, .tarot, .nursery, .wallet, .shop, .album: return true
        default: return false
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .profile: return "person.crop.circle"
        case .chat: return "bubble.left"
        case .terminal: return "terminal"
        case .settings: return "gearshape"
        case .bubbleAppearance: return "slider.horizontal.3"
        case .checklist: return "checklist"
        case .music: return "music.note"
        case .calendar: return "calendar"
        case .digest: return "calendar.badge.clock"
        case .wall: return "lock.rectangle.stack"
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
        case .portrait: return "envelope"
        case .impression: return "person.crop.circle.badge.questionmark"
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
        case .lab: return "waveform.path.ecg.rectangle"
        case .search: return "magnifyingglass"
        case .favorites: return "bookmark"
        case .forge: return "hammer"
        case .roundtable: return "person.3.sequence"
        case .surf: return "safari"
        case .letterbox: return "envelope.badge"
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
    @AppStorage("bubbleGlassStrength") private var bubbleGlassStrength = 56.81
    @AppStorage("bubbleGlassDispersion") private var bubbleGlassDispersion = 0.39
    @AppStorage("bubbleGlassRimWidth") private var bubbleGlassRimWidth = 0.28
    @AppStorage("bubbleGlassMagnify") private var bubbleGlassMagnify = 0.0
    @AppStorage("bubbleGlassBlur") private var bubbleGlassBlur = 0.10
    @AppStorage("bubbleGlassSize") private var bubbleGlassSize = 174.33

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
                case .checklist:
                    NativeChecklistView()
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
                case .usage:
                    NativeUsageView()
                case .workbench:
                    NativeWorkbenchView(openStudio: { withAnimation(.easeInOut(duration: 0.18)) { route = .studio } })
                case .studio:
                    NativeStudioView()
                case .profile:
                    NativeCalendarView()
                case .memory:
                    NativeBrainView()
                case .portrait:
                    NativeOBLettersView()
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
                case .impression:
                    NativeOBSelfView()
                case .dreams:
                    NativeDreamsView()
                case .morningPaper:
                    NativeMorningPaperView()
                case .nowhere:
                    NativeNowhereView()
                case .pulse:
                    NativePulseView()
                case .lab:
                    NativePipeLabView()
                case .wall:
                    NativeWallView()
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
        .environment(\.bubbleGlassStyle, bubbleGlassStyle)
        // Panel wallpaper may extend under the home indicator, but keyboard safe-area
        // must remain live so editors/composers rise instead of being covered.
        .ignoresSafeArea(.container, edges: .all)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .presentationBackground {
            GeometryReader { backgroundGeo in
                Image(theme.isDark ? "DrawerDark" : "DrawerLight")
                    .resizable()
                    .scaledToFill()
                    .frame(width: backgroundGeo.size.width, height: backgroundGeo.size.height)
                    .clipped()
                    .ignoresSafeArea()
            }
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
    private var theme: AlcoveTheme { .named(themeName) }

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
                Image(theme.isDark ? "DrawerDark" : "DrawerLight")
                    .resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height).clipped()
                (theme.isDark ? Color.black : Color.white).opacity(theme.isDark ? 0.10 : 0.08)

                ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        Text("Alcove")
                            .font(.custom("Snell Roundhand", size: 34))
                            .italic()
                        Spacer(minLength: 0)
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
        case .portrait: return "写过的信"
        case .album: return "照片"
        case .nianlun: return "一起走过的时间"
        case .shelf: return "他的收藏架"
        case .impression: return "他认得的自己"
        case .clockwork: return "自主活动与唤醒"
        case .forge: return "挑选轮次搬去新窗口"
        case .search: return "搜索消息"
        case .favorites: return "收藏消息"
        case .surf: return "X、小红书、B站与 YouTube"
        case .cowatch: return "一起看 B站与 YouTube"
        case .qipai: return "斗地主、炸金花与 UNO"
        case .tarot: return "抽一张牌，让他解"
        case .wall: return model.wallLine
        case .usage: return model.usageLine
        default: return "打开"
        }
    }
}

private extension View {
    func drawerGlass(_ theme: AlcoveTheme) -> some View {
        self.background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .background(theme.glassTint.opacity(theme.isDark ? 0.12 : 0.24),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(theme.glassBorder.opacity(0.72), lineWidth: 0.7))
    }
}

private struct NativeSidebarView: View {
    var select: (HouseDestination) -> Void
    let roundtableUnread: Int
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @StateObject private var model = SidebarModel()
    private var theme: AlcoveTheme { .panelNamed(themeName) }

    private let foyer: [HouseDestination] = [
        .memory, .dreams, .tarot, .shelf, .pond, .nianlun, .clockwork, .album, .portrait,
        .impression, .morningPaper, .nowhere, .pulse
    ]
    // Pipe Lab remains compiled for rollback, but the -p experiment is paused and
    // must not appear as a normal household destination.
    private let play: [HouseDestination] = [.crosstalk, .coread, .cowatch, .liao, .qipai]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 13) {
                VStack(spacing: 3) {
                    Text("Alcove")
                        .font(.system(size: 21, weight: .medium, design: .serif))
                        .tracking(1.4)
                    Text("壁 龛")
                        .font(.system(size: 9))
                        .tracking(3)
                        .foregroundColor(theme.textDim)
                    FoyerSash(theme: theme)
                        .padding(.top, 4)
                }
                .padding(.top, 8)

                HStack(spacing: 10) {
                    summaryCard("大厅", model.homeLine, "house", .home, large: true)
                    Button { select(.calendar) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Image(systemName: "heart")
                                    .font(.system(size: 17, weight: .light))
                                    .foregroundColor(theme.fyAccent)
                                Text("在一起").font(.system(size: 13, weight: .medium))
                            }
                            Text("\(model.days) days")
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                            Text("since 2026.06.01")
                                .font(.system(size: 10))
                                .foregroundColor(theme.textDim)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                        .foyerCard(theme)
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 10) {
                    summaryCard("小黑屋", model.wallLine, "lock.rectangle.stack.fill", .wall)
                    summaryCard("Usage", model.usageLine, "chart.bar", .usage)
                }

                destinationRow([.chat, .terminal, .settings])
                sectionTitle("Foyer")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(foyer) { destinationButton($0) }
                }
                sectionTitle("Play")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(play) { destinationButton($0) }
                }
                sectionTitle("Chat")
                destinationRow([.roundtable, .checklist, .forge])
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
            .foregroundColor(theme.text)
        }
        .task { await model.load() }
    }

    private func sectionTitle(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundColor(theme.fyAccent.opacity(0.8))
            LinearGradient(
                colors: [theme.fyAccentSoft, .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 1)
        }
        .padding(.top, 4)
    }

    private func summaryCard(
        _ title: String, _ subtitle: String, _ icon: String, _ target: HouseDestination, large: Bool = false
    ) -> some View {
        Button { select(target) } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .light))
                    .foregroundColor(theme.fyAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(subtitle).font(.system(size: 10)).foregroundColor(theme.textDim)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: large ? 80 : 60)
            .foyerCard(theme)
        }
        .buttonStyle(.plain)
    }

    private func destinationRow(_ items: [HouseDestination]) -> some View {
        HStack(spacing: 8) {
            ForEach(items) { destinationButton($0) }
        }
    }

    private func destinationButton(_ target: HouseDestination) -> some View {
        Button { select(target) } label: {
            VStack(spacing: 6) {
                Image(systemName: target.icon)
                    .font(.system(size: 18, weight: .light))
                    .foregroundColor(theme.fyAccent)
                    .overlay(alignment: .topTrailing) {
                        if target == .roundtable && roundtableUnread > 0 {
                            Text(roundtableUnread > 99 ? "99+" : "\(roundtableUnread)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 15, minHeight: 15)
                                .background(Color.red, in: Capsule())
                                .offset(x: 11, y: -9)
                        }
                    }
                Text(target.title)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(theme.textDim)
            .frame(maxWidth: .infinity, minHeight: 61)
            .foyerCard(theme)
            .rotationEffect(theme.isPaper
                ? .degrees(Double(abs(target.rawValue.hashValue) % 9 - 4) * 0.10)
                : .zero)
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private final class SidebarModel: ObservableObject {
    private struct Snapshot {
        var homeLine = "亲密度 --"
        var coins = 0
        var fiveHour = 0
        var sevenDay = 0
        var wallLine = "--"
        var usageLine = "--"
    }

    @Published private var snapshot = Snapshot()
    var homeLine: String { snapshot.homeLine }
    var coinsLine: String { "金币 \(snapshot.coins)" }
    var fiveHourLine: String { "5h \(snapshot.fiveHour)%" }
    var sevenDayLine: String { "7d \(snapshot.sevenDay)%" }
    var wallLine: String { snapshot.wallLine }
    var usageLine: String { snapshot.usageLine }

    let days = max(1, Calendar.current.dateComponents(
        [.day], from: Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_780_272_000)),
        to: Calendar.current.startOfDay(for: Date())).day ?? 1)

    func load() async {
        async let doll = try? NativeHouseAPI.object("/api/dollhouse/state")
        async let wall = try? NativeHouseAPI.object("/api/wall/entries")
        async let usage = try? NativeHouseAPI.object("/api/usage")

        let (dollResult, wallResult, usageResult) = await (doll, wall, usage)
        var next = Snapshot()

        if let d = dollResult {
            next.homeLine = "亲密度 \(d.int("intimacy")) · 金币 \(d.int("coins"))"
            next.coins = d.int("coins")
        }
        if let w = wallResult {
            let locked = w.int("locked")
            let opened = w.int("opened")
            next.wallLine = (locked + opened) == 0 ? "墙还是空的" : "\(locked) 道锁着 · \(opened) 道开了"
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
            case .chat: return "聊天与回复"
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
    @AppStorage("userName") private var userName = "Luna"
    @AppStorage("assistantAvatarDataURL") private var assistantAvatar = ""
    @AppStorage("userAvatarDataURL") private var userAvatar = ""
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @AppStorage("wallStamp") private var wallStamp = 0.0
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
    @State private var selectedAppIcon = UIApplication.shared.alternateIconName ?? "default"
    @State private var appIconError = ""
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
    private var theme: AlcoveTheme { interfaceDark ? .messagesDark : .messages }
    private var pal: YanxiaPal { YanxiaPal(night: interfaceDark) }

    // 0826 她说设置页没全屏、顶上透出壁纸：这页现在自己铺满、自己做头，
    // 皮也换成檐下那套，跟共读室一个屋檐下。
    var body: some View {
        ZStack {
            CoreadYanxiaBackground(isNight: interfaceDark).ignoresSafeArea()
            VStack(spacing: 0) {
                settingsHeader
                if page == nil { settingsIndex } else { settingsControls }
            }
        }
        .preferredColorScheme(interfaceDark ? .dark : .light)
    }

    private var settingsHeader: some View {
        let pal = YanxiaPal(night: interfaceDark)
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
        case .chat: return "正文、思绪与气泡文字"
        case .appearance: return "功能页明暗、聊天主题与壁纸"
        case .relationship: return "留白、两张表与完整发条"
        case .storage: return cacheCount == 0 ? "图片缓存与清理" : "\(cacheCount) 张 · \(ImageDiskCache.format(cacheBytes))"
        case .system: return "权限、灵动岛与屏幕控制"
        case .services:
            return "Backend \(backendOnline ? "在线" : "离线") · 何渡 \(codexOnline ? "在线" : "离线")"
        }
    }

    private var settingsControls: some View {
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
                if page == .chat { section("聊天外观") {
                    Button(action: showBubbleAppearance) {
                        settingRow("气泡与文字", "在聊天壁纸上实时预览并调节") {
                            Image(systemName: "chevron.right")
                                .foregroundColor(theme.textLight)
                        }
                    }
                    .buttonStyle(.plain)
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
                            pulseToggle("找你", "只跟你说话，不干别的", $pulseChase, key: "pulse_chase")
                            pulseToggle("去玩", "干自己的事，回来带一句", $pulseGhost, key: "pulse_ghost")
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
                if page == .appearance { section("白天 / 黑夜") {
                    Picker("全屋", selection: appearanceBinding) {
                        Text("白天").tag(false)
                        Text("黑夜").tag(true)
                    }.pickerStyle(.segmented)
                    Text("整个 app 一起翻，不跟手机的深色模式走")
                        .font(.system(size: 10.5)).foregroundColor(theme.textLight)
                } }
                if page == .appearance { section("聊天主题") {
                    HStack(spacing: 8) {
                        familyChoice("玻璃", "光穿过去", "glass", [.white, .pink.opacity(0.42), .gray])
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
                    }
                } }
                if page == .appearance { section("聊天壁纸") {
                    HStack {
                        PhotosPicker(selection: $wallPhoto, matching: .images) {
                            Label("从相册更换", systemImage: "photo")
                        }
                        Spacer()
                        Button("恢复默认") { resetWallpaper() }
                    }
                    .font(.system(size: 13))
                } }
                if page == .appearance { section("App 图标") {
                    HStack(alignment: .top, spacing: 16) {
                        appIconChoice("现有图标", asset: "CurrentIcon", alternateName: nil)
                        appIconChoice("你们两个", asset: "TogetherIcon", alternateName: "TogetherAppIcon")
                        Spacer(minLength: 0)
                    }
                    if !appIconError.isEmpty {
                        Text(appIconError)
                            .font(.system(size: 10.5))
                            .foregroundColor(.red.opacity(0.85))
                    }
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
        .sheet(isPresented: $showSystemFeatures) {
            SystemFeaturesView()
        }
        .sheet(isPresented: $showQuietRoom) {
            QuietRoomView()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .onChange(of: userPhoto) { item in loadDataURL(item, into: $userAvatar) }
        .onChange(of: aiPhoto) { item in loadDataURL(item, into: $assistantAvatar) }
        .onChange(of: wallPhoto) { item in saveWallpaper(item) }
        .onChange(of: replyLength) { value in scheduleReplyLengthSave(value) }
        .onChange(of: thoughtLength) { value in if handwrittenOn { scheduleThoughtLengthSave(value) } }
        .onAppear { selectedAppIcon = UIApplication.shared.alternateIconName ?? "default" }
        .task {
            refreshCacheStats()
            async let services: Void = loadServices()
            async let reply: Void = loadReplyLength()
            async let thought: Void = loadThoughtLength()
            async let pulse: Void = loadPulseRange()
            async let her: Void = loadHerStatus()
            async let pat: Void = loadPat()
            _ = await (services, reply, thought, pulse, her, pat)
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

    private func appIconChoice(
        _ title: String, asset: String, alternateName: String?
    ) -> some View {
        let key = alternateName ?? "default"
        let selected = selectedAppIcon == key
        return Button {
            switchAppIcon(to: alternateName)
        } label: {
            VStack(spacing: 7) {
                Image(asset)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(selected ? theme.fyAccent : pal.line,
                                          lineWidth: selected ? 2 : 0.5)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, theme.fyAccent)
                                .background(Circle().fill(pal.card).padding(2))
                                .offset(x: 5, y: 5)
                        }
                    }
                Text(title)
                    .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? theme.fyAccent : theme.text)
            }
            .frame(minWidth: 88, minHeight: 104)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("应用图标，\(title)")
        .accessibilityValue(selected ? "已选择" : "未选择")
    }

    private func switchAppIcon(to alternateName: String?) {
        guard UIApplication.shared.supportsAlternateIcons else {
            appIconError = "这台设备不支持切换应用图标"
            return
        }
        let key = alternateName ?? "default"
        guard selectedAppIcon != key else { return }
        appIconError = ""
        UIApplication.shared.setAlternateIconName(alternateName) { error in
            DispatchQueue.main.async {
                if let error {
                    appIconError = "切换失败：\(error.localizedDescription)"
                } else {
                    selectedAppIcon = key
                }
            }
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

    private func pulseToggle(_ title: String, _ sub: String, _ value: Binding<Bool>, key: String) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(sub).font(.system(size: 9)).foregroundColor(theme.textDim)
            }
            Toggle("", isOn: Binding(
                get: { value.wrappedValue },
                set: { on in
                    value.wrappedValue = on
                    Task { try? await NativeHouseAPI.post("/api/flags/set", body: ["key": key, "on": on]) }
                }))
            .labelsHidden()
            .tint(theme.fyAccent)
        }
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
        }
        pulseLoaded = true
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
    private var themeFamily: String { isPaperFamily ? "paper" : (isMessagesFamily ? "imessage" : "glass") }
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
    @StateObject private var wallpaperStore = ChatWallpaperStore()
    @AppStorage("assistantName") private var assistantName = "陈璟"
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @AppStorage("chatFontSize") private var fontSize = 14
    @AppStorage("chatBubbleGap") private var bubbleGap = 6.0
    @AppStorage("wallStamp") private var wallStamp = 0.0
    @AppStorage("bubbleGlassStrength") private var bubbleGlassStrength = 56.81
    @AppStorage("bubbleGlassDispersion") private var bubbleGlassDispersion = 0.39
    @AppStorage("bubbleGlassRimWidth") private var bubbleGlassRimWidth = 0.28
    @AppStorage("bubbleGlassMagnify") private var bubbleGlassMagnify = 0.0
    @AppStorage("bubbleGlassBlur") private var bubbleGlassBlur = 0.10
    @AppStorage("bubbleGlassSize") private var bubbleGlassSize = 174.33
    /// 0902 信息主题调色板：改一项这个数就变，预览跟着重画
    @AppStorage(MessagesPalette.stampKey) private var paletteStamp = 0.0

    private var panelTheme: AlcoveTheme { .panelNamed(themeName) }
    private var chatTheme: AlcoveTheme { _ = paletteStamp; return .named(themeName) }
    private var bubbleStyle: BubbleGlassStyle {
        BubbleGlassStyle(
            strength: CGFloat(bubbleGlassStrength),
            dispersion: CGFloat(bubbleGlassDispersion),
            rimWidth: CGFloat(bubbleGlassRimWidth),
            magnify: CGFloat(bubbleGlassMagnify),
            backdropBlur: CGFloat(bubbleGlassBlur),
            size: CGFloat(bubbleGlassSize)
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                Text("气泡与文字")
                    .font(.system(size: 17, weight: .semibold))
                    .padding(.top, 11)

                livePreview

                // 0902 她要的：信息主题下自己调颜色。每项预设色块 + 自定义取色器 + 各自的「默认」
                if chatTheme.isMessages {
                    section("颜色 · 信息主题") {
                        VStack(spacing: 12) {
                            ForEach(MessagesPalette.Item.allCases) { item in colorRow(item) }
                        }
                        Text("预设一点就换；「自定义」里有色轮和吸管，可以直接从壁纸上吸颜色；每项的「默认」只回这一项。夜里、白天各存一套，跟全屋的日夜开关走，现在调的是\(chatTheme.isDark ? "夜里" : "白天")这套")
                            .font(.system(size: 10))
                            .foregroundColor(panelTheme.textLight)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                section("文字") {
                    VStack(spacing: 12) {
                        fontSizeSlider
                        bubbleGapSlider
                    }
                }

                section("液态玻璃气泡") {
                    VStack(spacing: 10) {
                        glassSliderRow("扭曲", "strength", $bubbleGlassStrength, 0...60)
                        glassSliderRow("色散", "dispersion", $bubbleGlassDispersion, 0...3)
                        glassSliderRow("过渡", "rimWidth", $bubbleGlassRimWidth, 0.2...0.95)
                        glassSliderRow("放大", "magnify", $bubbleGlassMagnify, 0...1.5)
                        glassSliderRow("背景模糊", "blur", $bubbleGlassBlur, 0...8)
                        glassSliderRow("直径", "size", $bubbleGlassSize, 80...340)
                    }
                    Divider().opacity(0.25)
                    HStack {
                        Text("上方预览与聊天页同步生效")
                            .font(.system(size: 10))
                            .foregroundColor(panelTheme.textLight)
                        Spacer()
                        Button("恢复默认") { resetAppearance() }
                            .font(.system(size: 11, weight: .medium))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
            .foregroundColor(panelTheme.text)
        }
        .onAppear { refreshWallpaper() }
        .onChange(of: themeName) { _ in refreshWallpaper() }
        .onChange(of: wallStamp) { _ in refreshWallpaper() }
    }

    private var livePreview: some View {
        GeometryReader { proxy in
            ZStack {
                ChatWallpaperRenderer(descriptor: wallpaperStore.descriptor)

                if chatTheme.isMessages {
                    messagesPreview.padding(14)
                } else {
                    VStack(spacing: 14) {
                        previewBubble(
                            "\(assistantName)，气泡再透一点\n字也松一点",
                            isUser: true
                        )
                        previewBubble(
                            "好，就在这里慢慢调\n我陪你看每一下变化",
                            isUser: false
                        )
                    }
                    .padding(16)
                }
            }
            .coordinateSpace(name: "alcoveChatRoot")
            .environment(\.chatWallpaperDescriptor, wallpaperStore.descriptor)
            .environment(\.chatWallpaperViewportSize, proxy.size)
            .environment(\.bubbleGlassStyle, bubbleStyle)
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(panelTheme.fyBorder, lineWidth: 1)
        )
        .shadow(color: panelTheme.fyShadow, radius: 8, y: 3)
    }

    // MARK: 0902 信息主题的预览：实心气泡 + 气泡下的时间戳 + 一行思绪 + 一道截断线，
    // 她调的五个颜色全在这一小块里看得见，壁纸就是她当前那张

    private var messagesPreview: some View {
        let t = chatTheme
        return VStack(spacing: 10) {
            MessagesTimeDivider(date: Date(), color: t.dividerColor)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle().fill(t.thoughtColor.opacity(0.6)).frame(width: 7, height: 7)
                    Text("她在挑颜色，我等着看她挑到哪一格")
                        .font(.system(size: 12)).italic().foregroundColor(t.thoughtColor).lineLimit(1)
                }
                messagesPreviewBubble("这里慢慢调，我陪你看", isUser: false, theme: t, stamp: "19:09 · ♥ 78 bpm")
            }
            messagesPreviewBubble("\(assistantName)，时间戳换个颜色", isUser: true, theme: t, stamp: "19:14")
            MusicChatDivider(text: "切到了一首歌", date: Date(), color: t.dividerColor)
        }
    }

    private func messagesPreviewBubble(_ text: String, isUser: Bool, theme t: AlcoveTheme,
                                       stamp: String) -> some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
            Text(text)
                .font(.system(size: CGFloat(fontSize)))
                .foregroundColor(isUser ? (t.textUser ?? .white) : (t.textAI ?? t.text))   // 0903 正文颜色也进预览
                .padding(.horizontal, 13).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(isUser ? t.bubbleUser : t.bubbleAI))
            Text(stamp)
                .font(.system(size: 10, design: .serif))
                .foregroundColor(t.timestamp)
                .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private func colorRow(_ item: MessagesPalette.Item) -> some View {
        let dark = chatTheme.isDark
        let binding = Binding<Color>(
            get: { MessagesPalette.current(item, dark: dark) },
            set: { MessagesPalette.set(item, $0, dark: dark) })
        return HStack(spacing: 8) {
            Text(item.title)
                .font(.system(size: 12))
                .frame(width: 84, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Array(MessagesPalette.presets.enumerated()), id: \.offset) { _, c in
                        Button { MessagesPalette.set(item, c, dark: dark) } label: {
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
            Button("默认") { MessagesPalette.set(item, nil, dark: dark) }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(MessagesPalette.isDefault(item, dark: dark) ? panelTheme.textLight : panelTheme.fyAccent)
                .disabled(MessagesPalette.isDefault(item, dark: dark))
        }
    }

    private func previewBubble(_ text: String, isUser: Bool) -> some View {
        HStack {
            if isUser { Spacer(minLength: 40) }

            Text(text)
                .font(.system(size: CGFloat(fontSize)))
                .lineSpacing(5)
                .foregroundColor(isUser ? (chatTheme.textUser ?? (chatTheme.isMessages ? .white : chatTheme.text)) : (chatTheme.textAI ?? chatTheme.text))
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    BubbleGlassBackground(
                        tintColor: isUser ? chatTheme.bubbleUser : chatTheme.bubbleAI,
                        tintOpacity: isUser ? 0.14 : 0.09,
                        style: bubbleStyle
                    )
                }

            if !isUser { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity)
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

    private func refreshWallpaper() {
        wallpaperStore.refresh(
            themeName: themeName,
            theme: chatTheme,
            wallStamp: wallStamp
        )
    }

    private func resetAppearance() {
        fontSize = 14
        bubbleGlassStrength = 56.81
        bubbleGlassDispersion = 0.39
        bubbleGlassRimWidth = 0.28
        bubbleGlassMagnify = 0
        bubbleGlassBlur = 0.10
        bubbleGlassSize = 174.33
    }
}

private struct ChecklistItem: Identifiable {
    let id: String
    let body: String
    let done: Bool
    let isFixed: Bool
    let triggerAt: String
    init(_ json: [String: Any]) {
        id = json.string("id")
        body = json.string("body", "text", "title")
        done = json.bool("done")
        isFixed = json.bool("is_fixed")
        triggerAt = json.string("trigger_at", "at")
    }
}

@MainActor
private final class ChecklistModel: ObservableObject {
    @Published var items: [ChecklistItem] = []
    @Published var loading = false
    @Published var error = ""

    func load() async {
        loading = true
        defer { loading = false }
        do {
            let value = try await NativeHouseAPI.request("/api/checklist")
            let raw = value as? [[String: Any]]
                ?? (value as? [String: Any])?["items"] as? [[String: Any]] ?? []
            items = raw.map(ChecklistItem.init)
            error = ""
        } catch { self.error = "清单暂时够不着" }
    }

    func toggle(_ item: ChecklistItem) async {
        try? await NativeHouseAPI.post("/api/checklist/\(item.id)/toggle")
        await load()
    }

    func delete(_ item: ChecklistItem) async {
        try? await NativeHouseAPI.post("/api/checklist/\(item.id)/delete")
        await load()
    }

    func add(body: String, at: String) async {
        var payload: [String: Any] = ["body": body, "is_fixed": true]
        if !at.isEmpty { payload["at"] = at }
        try? await NativeHouseAPI.post("/api/checklist", body: payload)
        await load()
    }
}

private struct NativeChecklistView: View {
    @StateObject private var model = ChecklistModel()
    @State private var draft = ""
    @State private var time = ""
    @AppStorage("alcoveTheme") private var themeName = "haven"
    private var theme: AlcoveTheme { .panelNamed(themeName) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                FoyerPanelTitle(title: "TODAY'S ORDER", theme: theme)
                Text(Date.now.formatted(date: .long, time: .omitted))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.textDim)
            }
            if model.loading && model.items.isEmpty {
                Spacer(); ProgressView().tint(theme.fyAccent); Spacer()
            }
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(model.items) { item in
                        HStack(alignment: .top, spacing: 0) {
                            VStack(spacing: 0) {
                                Rectangle()
                                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                    .foregroundColor(theme.fyDash)
                                    .frame(width: 1)
                            }
                            .frame(width: 14)
                            .overlay(alignment: .top) {
                                BindingHole(theme: theme, count: 2, spacing: 18)
                                    .offset(x: -4.5, y: 8)
                            }

                            HStack(spacing: 9) {
                                Button { Task { await model.toggle(item) } } label: {
                                    Image(systemName: item.done ? "checkmark.square.fill" : "square")
                                        .foregroundColor(item.done ? theme.fyAccent : theme.textDim)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.body)
                                        .font(.system(size: 13, design: .monospaced))
                                        .strikethrough(item.done)
                                        .opacity(item.done ? 0.55 : 1)
                                    if !item.triggerAt.isEmpty {
                                        Text(item.triggerAt)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(theme.fyAccent.opacity(0.9))
                                    }
                                }
                                Spacer()
                                if !item.isFixed {
                                    Text("临")
                                        .font(.system(size: 9))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(theme.fyAccentSoft.opacity(0.3), in: Capsule())
                                        .foregroundColor(theme.fyAccent)
                                }
                                Button { Task { await model.delete(item) } } label: {
                                    Image(systemName: "xmark").font(.system(size: 11))
                                        .foregroundColor(theme.textLight)
                                }
                            }
                            .padding(.vertical, 11)
                            .padding(.trailing, 14)
                            .padding(.leading, 10)
                        }
                        .foyerCard(theme)
                    }
                    if model.items.isEmpty && !model.loading {
                        Text(model.error.isEmpty ? "今天还没有待办" : model.error)
                            .font(.system(size: 12)).foregroundColor(theme.textDim).padding(30)
                    }
                }
                .padding(.top, 12)
            }
            HStack(spacing: 8) {
                TextField("加一项…", text: $draft)
                TextField("HH:mm", text: $time).frame(width: 58)
                    .textInputAutocapitalization(.never)
                Button {
                    let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !body.isEmpty else { return }
                    draft = ""
                    Task { await model.add(body: body, at: time); time = "" }
                } label: {
                    Image(systemName: "plus").frame(width: 30, height: 30)
                        .background(theme.fyAccent, in: Circle())
                        .foregroundColor(.white)
                }
            }
            .font(.system(size: 13, design: .monospaced))
            .padding(12)
            .foyerCard(theme)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .foregroundColor(theme.text)
        .foyerPanel(theme)
        .padding(.horizontal, 12).padding(.top, 8)
        .task { await model.load() }
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
    // 任务#1345：她在一起听大卡上手滑挑中的那一行。nil = 跟着歌自己走。
    @Published var pickedLyric: Int?
    @Published var lineSending = false
    @Published var lineSentFlash = false
    private var pickResetTask: Task<Void, Never>?
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

    /// 大卡上高亮的那一行：她手滑挑了就是她挑的，没挑就是正在唱的那句。
    var boardLyricIndex: Int {
        if let picked = pickedLyric, lyrics.indices.contains(picked) { return picked }
        return lyrics.lastIndex(where: { $0.time <= progress }) ?? -1
    }

    /// 手滑挑中一行。5 秒不碰就放开，让歌词滑回正在唱的那句——
    /// 不然她滑一下就再也跟不上歌了。
    func pickLyric(_ index: Int) {
        pickedLyric = index
        pickResetTask?.cancel()
        pickResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.pickedLyric = nil
        }
    }

    /// 把大卡上高亮那句发给他。
    /// 发的是**她屏幕上那句原文**，直接打包送走；服务端一个字都不许自己算，
    /// 两边各算各的必然差半句，她明确要求所见即所发。
    func sendPickedLyric() async {
        let index = boardLyricIndex
        guard lyrics.indices.contains(index), let song = nowPlaying, !lineSending else { return }
        let line = lyrics[index]
        let end = index + 1 < lyrics.count ? lyrics[index + 1].time : line.time + 4
        lineSending = true
        defer { lineSending = false }
        let obj = try? await NativeHouseAPI.object("/api/music/line", method: "POST", body: [
            "song_id": song.id, "name": song.name, "artist": song.artist,
            "text": line.text, "start": line.time, "end": end])
        guard obj?.bool("ok") == true else {
            message = "这句没发出去"
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        lineSentFlash = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            self?.lineSentFlash = false
        }
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

/// 一起听大卡（她的参考图）：头像弧线+累计时长在上，播放器在下，
/// 一起听开着就钉在聊天页顶部，聊天在卡下面照聊。右上角小叉 = 结束一起听。
/// 任务#1345：量一下展开态排完有多高，折叠态照这个高度来。
private struct ListenBoardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ListenBoardCard: View {
    @ObservedObject var model: MusicModel
    let dark: Bool
    let off: () -> Void
    let openPlayer: () -> Void
    let openInsight: () -> Void
    /// 0902 她定的：左上角缩小键（跟右上角的叉对称）→ 大卡收走，小唱片浮到屏幕边上
    var minimize: () -> Void = {}
    @AppStorage("userAvatarDataURL") private var userAvatar = ""
    @AppStorage("assistantAvatarDataURL") private var assistantAvatar = ""

    private var p: ListenPorcelain { ListenPorcelain(dark: dark) }

    private var activeLine: Int { model.boardLyricIndex }

    // 0902：任务#1345 的「左滑收成半张」拆了——缩小键替代它，少一种手势少一种误触。
    var body: some View {
        expandedCard
            .modifier(ListenPanel(p: p, corner: 20, dotted: true))
            .overlay(alignment: .topTrailing) {
                Button(action: off) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(p.inkDim)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(2)
            }
            .overlay(alignment: .topLeading) {
                Button(action: minimize) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(p.inkDim)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(2)
            }
    }

    // MARK: 展开态

    private var expandedCard: some View {
        VStack(spacing: 8) {
            avatarArc
            if let song = model.nowPlaying {
                VStack(spacing: 6) {
                    Button(action: openPlayer) {
                        HStack(spacing: 5) {
                            Text(song.name).font(.system(size: 14, weight: .semibold))
                                .foregroundColor(p.ink).lineLimit(1)
                            Text("— \(song.artist)").font(.system(size: 11))
                                .foregroundColor(p.inkDim).lineLimit(1)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    lyricStrip
                    progressRow
                    controlRow
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(p.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(p.line, lineWidth: 1))
            }
        }
        .padding(12)
    }

    /// 上半部分：头像弧。
    private var avatarArc: some View {
        ZStack {
            ListenArc()
                .stroke(p.accent.opacity(0.4),
                        style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                .frame(height: 52).padding(.horizontal, 28)
            HStack {
                avatarView(userAvatar, fallback: "霁")
                Spacer()
                VStack(spacing: 2) {
                    Text("霁 · 璟").font(.system(size: 13, weight: .medium)).foregroundColor(p.ink)
                    Text(model.listenTimeText).font(.system(size: 10)).foregroundColor(p.inkDim)
                }
                Spacer()
                avatarView(assistantAvatar, fallback: "璟")
            }.padding(.horizontal, 6)
        }
        .frame(height: 56)
        .contentShape(Rectangle())
    }

    /// 三行滚动歌词 + 纸飞机。高亮那句就是点纸飞机会发出去的那句。
    private var lyricStrip: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 3) {
                        if model.lyrics.isEmpty {
                            Text(model.lyricsLoading ? "歌词加载中" : "这首没有歌词")
                                .font(.system(size: 11)).foregroundColor(p.inkDim)
                                .frame(maxWidth: .infinity, minHeight: 52)
                        } else {
                            ForEach(Array(model.lyrics.enumerated()), id: \.element.id) { index, line in
                                Button { model.pickLyric(index) } label: {
                                    Text(line.text)
                                        .font(.system(size: index == activeLine ? 12.5 : 11,
                                                      weight: index == activeLine ? .semibold : .regular))
                                        .foregroundColor(index == activeLine
                                                         ? p.ink : p.inkDim.opacity(0.7))
                                        .lineLimit(1).truncationMode(.tail)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity, minHeight: 15)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain).id(index)
                            }
                        }
                    }.padding(.vertical, 1)
                }
                .frame(height: 52)
                .onChange(of: activeLine) { index in
                    guard index >= 0 else { return }
                    withAnimation(.easeOut(duration: 0.28)) { proxy.scrollTo(index, anchor: .center) }
                }
                .onAppear {
                    let index = activeLine
                    if index >= 0 { proxy.scrollTo(index, anchor: .center) }
                }
            }
            sendButton
        }
    }

    private var sendButton: some View {
        Button { Task { await model.sendPickedLyric() } } label: {
            ZStack {
                Circle()
                    .fill(model.lineSentFlash ? p.accent.opacity(0.9) : p.accent.opacity(0.16))
                    .frame(width: 30, height: 30)
                if model.lineSending {
                    ProgressView().controlSize(.mini).tint(p.ink)
                } else {
                    Image(systemName: model.lineSentFlash ? "checkmark" : "paperplane.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(model.lineSentFlash ? .white : p.ink)
                }
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.lyrics.isEmpty || model.lineSending)
        .opacity(model.lyrics.isEmpty ? 0.3 : 1)
        .accessibilityLabel("把这句发给他")
    }

    private var progressRow: some View {
        VStack(spacing: 1) {
            Slider(value: Binding(get: { model.progress }, set: { model.seek(to: $0) }),
                   in: 0...max(model.duration, 1)).tint(p.accent)
            HStack {
                Text(Self.time(model.progress)); Spacer(); Text(Self.time(model.duration))
            }.font(.system(size: 9, design: .monospaced)).foregroundColor(p.inkDim)
        }
    }

    private var controlRow: some View {
        HStack {
            Button { Task { await model.toggleLike() } } label: {
                Image(systemName: model.currentIsLiked ? "heart.fill" : "heart")
                    .foregroundColor(model.currentIsLiked ? .red : p.ink)
            }
            Spacer()
            Button { model.prev() } label: { Image(systemName: "backward.fill") }
            Spacer()
            Button { model.toggle() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20))
            }
            Spacer()
            Button { model.next() } label: { Image(systemName: "forward.fill") }
            Spacer()
            Button { model.cyclePlayMode() } label: { Image(systemName: model.playMode.icon) }
            Spacer()
            Button(action: openInsight) { Image(systemName: "waveform.badge.magnifyingglass") }
        }
        .font(.system(size: 15)).foregroundColor(p.ink)
        .buttonStyle(.plain).padding(.horizontal, 2)
    }

    private func avatarView(_ dataURL: String, fallback: String) -> some View {
        Group {
            if let image = Self.decode(dataURL) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    p.panel
                    Text(fallback).font(.system(size: 19, weight: .medium)).foregroundColor(p.ink)
                }
            }
        }
        .frame(width: 56, height: 56).clipShape(Circle())
        .overlay(Circle().stroke(p.accent.opacity(0.45), lineWidth: 1.5))
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
    private var theme: AlcoveTheme { .named(themeName) }

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
                    LazyVStack(alignment: .center, spacing: 20) {
                    Color.clear.frame(height: 70)
                    if model.lyricsLoading { ProgressView().frame(maxWidth: .infinity) }
                    else if model.lyrics.isEmpty {
                        Text("这首没有歌词").foregroundColor(theme.textDim).frame(maxWidth: .infinity)
                    } else {
                        ForEach(Array(model.lyrics.enumerated()), id: \.element.id) { index, line in
                            Button { model.seek(to: line.time) } label: {
                                VStack(alignment: .center, spacing: 5) {
                                    Text(line.text).font(.system(size: index == activeLyric ? 19 : 15,
                                                                weight: index == activeLyric ? .semibold : .regular))
                                        .multilineTextAlignment(.center)
                                        .foregroundColor(index == activeLyric ? .white : .white.opacity(0.68))
                                    if let trans = line.translation, !trans.isEmpty {
                                        Text(trans).font(.system(size: 11)).foregroundColor(.white.opacity(0.62))
                                            .multilineTextAlignment(.center)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .center)
                                    .opacity(index == activeLyric ? 1 : 0.86)
                            }.buttonStyle(.plain).id(index)
                        }
                    }
                    Color.clear.frame(height: 110)
                }.frame(maxWidth: .infinity).padding(.horizontal, 26)
                }
            .onChange(of: activeLyric) { idx in
                guard idx >= 0 else { return }
                withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(idx, anchor: .center) }
            }
            }
            HStack { likeButton; Spacer(); Image(systemName: "quote.bubble").font(.system(size: 19)) }
                .padding(.horizontal, 34).padding(.top, 8)
            progressControls
            playbackControls
            pageDots
        }
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
                    quietChoice("今夜无声", "今晚先不追问\n明早十点再来", "moon.stars.fill") {
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
            case .memory: path = "/api/ob/buckets"; key = nil
            case .dreams: path = "/api/night/dreams?limit=20"; key = "records"
            case .shelf: path = "/api/shelf/list?limit=100"; key = "items"
            case .nianlun: path = "/api/nianlun/list"; key = "desires"
            case .album: path = "/api/album/entries"; key = "entries"
            case .impression: path = "/api/ob/buckets"; key = nil
            case .calendar: path = "/api/calendar/month?year=\(Calendar.current.component(.year, from: Date()))&month=\(Calendar.current.component(.month, from: Date()))"; key = nil
            case .portrait, .usage:
                path = destination == .portrait ? "/api/ob/portrait" : "/api/usage"
                key = nil
            default: path = "/api/ob/buckets"; key = nil
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
            if destination == .impression {
                rows = rows.filter {
                    $0.string("type") == "feel"
                    && (($0["tags"] as? [Any])?.map(String.init(describing:)).contains("daily_impression") ?? false)
                }
            }
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
        ClockworkItem(id: "chase", emoji: "📣", name: "催起床",
                      desc: "从你最后一句话起算，睡够 6 小时以后到了上午十点你还没出现，我就来催你起床。"),
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
        case .checklist: return "checklist"
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

private struct FoyerCardGlassBackground: View {
    let theme: AlcoveTheme
    @Environment(\.bubbleGlassStyle) private var bubbleGlassStyle

    var body: some View {
        BubbleGlassBackground(
            tintColor: theme.fyCard,
            tintOpacity: theme.isDark ? 0.12 : 0.10,
            style: bubbleGlassStyle,
            cornerRadius: 16
        )
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

    // 面板卡片与聊天气泡共用同一套折射、高光和六个调节参数。
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
                        ForEach(displayItems) { item in
                            Group {
                                if item.group.count > 1 {
                                    photoGroupBubble(item)
                                } else {
                                    messageBubble(item.primary)
                                }
                            }.id("studio-message-\(item.id)")
                        }
                        if let current = status["current_task"] as? [String: Any] {
                            HStack(spacing: 7) { ProgressView().scaleEffect(0.7); Text("正在处理 · \(current.string("title"))") }
                                .font(.system(size: 10)).foregroundColor(theme.textDim).padding(9)
                        }
                        Color.clear.frame(height: 1).id("studio-tail")
                    }.padding(.horizontal, 15).padding(.bottom, 16)
                }
                .defaultScrollAnchor(.bottom)
                // 0904 她报的「工作室键盘下不去，只有发一条才收」：往下滑列表跟手收，点列表任何地方也收
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                    to: nil, from: nil, for: nil)
                })
                .onChange(of: messages.last?.int("id") ?? 0) { _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("studio-tail", anchor: .bottom) }
                }
            }
            inputBar
        }
        .background(LinearGradient(colors: theme.isDark ? [Color(red: 0.075, green: 0.068, blue: 0.09), Color(red: 0.13, green: 0.105, blue: 0.14)] : [Color(red: 0.985, green: 0.955, blue: 0.945), Color(red: 0.94, green: 0.91, blue: 0.90)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
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
    private func photoGroupBubble(_ item: StudioDisplayItem) -> some View {
        let mine = item.primary.string("role") == "user"
        let caption = item.group.map { $0.string("text") }.first { !$0.isEmpty } ?? ""
        let side: CGFloat = 124
        let gap: CGFloat = 8
        return HStack(alignment: .bottom) {
            if mine { Spacer(minLength: 52) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
                Group {
                    if item.group.count > 2 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: gap) {
                                ForEach(item.group, id: \.studioMessageID) { m in thumb(m, side: side) }
                            }
                        }.frame(width: side * 2 + gap, height: side)
                    } else {
                        HStack(spacing: gap) {
                            ForEach(item.group, id: \.studioMessageID) { m in thumb(m, side: side) }
                        }
                    }
                }
                if !caption.isEmpty {
                    Text(alcoveMarkdown(caption)).font(.system(size: 14, design: .serif)).lineSpacing(5).textSelection(.enabled)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(mine ? theme.bubbleUser : theme.bubbleAI, in: RoundedRectangle(cornerRadius: 18))
                        .frame(maxWidth: 300, alignment: mine ? .trailing : .leading)
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
    }

    private func messageBubble(_ message: [String: Any]) -> some View {
        let mine = message.string("role") == "user"
        let messageID = message.int("id")
        let thought = message.string("thinking")
        return HStack(alignment: .bottom) {
            if mine { Spacer(minLength: 52) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 5) {
                if !mine && !thought.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if expandedThoughts.contains(messageID) { expandedThoughts.remove(messageID) }
                            else { expandedThoughts.insert(messageID) }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "circle.dotted").font(.system(size: 10))
                                Text("工作思绪").font(.system(size: 10, weight: .semibold, design: .serif))
                                Spacer()
                                Image(systemName: expandedThoughts.contains(messageID) ? "chevron.up" : "chevron.down").font(.system(size: 8))
                            }
                            // 收起态只留一行标签，跟主聊天一样——思绪是点开才看的东西，
                            // 不是挂在气泡上的摘要
                            if expandedThoughts.contains(messageID) {
                                Text(thought).font(.system(size: 11, design: .serif)).lineSpacing(4).multilineTextAlignment(.leading)
                            }
                        }
                        .foregroundColor(theme.textDim.opacity(0.86))
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(.ultraThinMaterial.opacity(0.62), in: RoundedRectangle(cornerRadius: 15))
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.white.opacity(0.30), lineWidth: 0.6))
                    }.buttonStyle(.plain)
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
                    } else {
                        Label(message.string("attachment_filename").isEmpty ? "附件" : message.string("attachment_filename"), systemImage: "doc")
                            .font(.system(size: 11, weight: .medium)).padding(9)
                            .background(.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 11))
                    }
                }
                // 只有图没有字的时候不要再吐一个空气泡出来
                if !message.string("text").isEmpty {
                    Text(alcoveMarkdown(message.string("text"))).font(.system(size: 14, design: .serif)).lineSpacing(5).textSelection(.enabled)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(mine ? theme.bubbleUser : theme.bubbleAI, in: RoundedRectangle(cornerRadius: 18))
                        .frame(maxWidth: 300, alignment: mine ? .trailing : .leading)
                }
                if !message.string("tool_log").isEmpty { DisclosureGroup("终端记录") { Text(message.string("tool_log")).font(.system(size: 9, design: .monospaced)).textSelection(.enabled) }.font(.system(size: 9)).foregroundColor(theme.textDim) }
            }
            if !mine { Spacer(minLength: 52) }
        }
    }

    private var inputBar: some View {
        StudioInputBar(pendingImages: $pendingImages,
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
            HStack(alignment: .bottom, spacing: 9) {
                Menu {
                    Button { onPickPhotos() } label: { Label("图片", systemImage: "photo") }
                    Button { onPickFile() } label: { Label("文件", systemImage: "doc") }
                } label: { Image(systemName: "plus").font(.system(size: 16, weight: .semibold)).frame(width: 38, height: 38).background(.white.opacity(0.50), in: Circle()) }
                TextField("在工作室里和他说……", text: $draft, axis: .vertical).lineLimit(1...6).focused($focused)
                    .padding(.horizontal, 14).padding(.vertical, 10).background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 19))
                Button {
                    let text = draft
                    draft = ""; focused = false
                    Task { if await onSend(text) == false { draft = text } }
                } label: { Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundColor(.white).frame(width: 38, height: 38).background(accent, in: Circle()) }
                    .disabled(!canSend)
            }.padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 18)
        }.background(.ultraThinMaterial)
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
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white).padding(11)
                            .background(.black.opacity(0.35), in: Circle())
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 18).padding(.top, 10)
                Spacer()
            }
        }
        .onTapGesture(perform: onClose)
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

// MARK: - Portrait

private struct NativePortraitView: View {
    @State private var sections: [(String, [String])] = []
    @State private var loading = true
    @AppStorage("alcoveTheme") private var themeName = "haven"
    private var theme: AlcoveTheme { .panelNamed(themeName) }

    var body: some View {
        VStack(spacing: 0) {
            FoyerPanelTitle(title: "Portrait", theme: theme)
            if loading {
                Spacer(); ProgressView().tint(theme.fyAccent); Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(sections, id: \.0) { title, items in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(title).font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(theme.fyAccent)
                                ForEach(items, id: \.self) { item in
                                    Text(item)
                                        .font(.system(size: 12))
                                        .lineSpacing(3)
                                        .foregroundColor(theme.textDim)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foyerCard(theme)
                        }
                        if sections.isEmpty {
                            Text("还没有画像数据").font(.system(size: 12))
                                .foregroundColor(theme.textDim).padding(30)
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 18)
                }
            }
        }
        .foregroundColor(theme.text)
        .foyerPanel(theme)
        .padding(.horizontal, 12).padding(.top, 8)
        .task { await loadPortrait() }
    }

    private func loadPortrait() async {
        defer { loading = false }
        guard let obj = try? await NativeHouseAPI.object("/api/ob/portrait"),
              let portrait = obj["portrait"] as? [String: Any] else { return }
        var result: [(String, [String])] = []
        for key in ["user", "assistant"] {
            guard let section = portrait[key] as? [String: Any] else { continue }
            let label = key == "user" ? "关于她" : "关于我"
            var texts: [String] = []
            for bufKey in ["stable", "recent_buffer"] {
                if let items = section[bufKey] as? [[String: Any]] {
                    for item in items {
                        if let t = item["text"] as? String, !t.isEmpty { texts.append(t) }
                    }
                }
            }
            if !texts.isEmpty { result.append((label, texts)) }
        }
        sections = result
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
    private var theme: AlcoveTheme { .panelNamed(themeName) }
    private let rose = Color(red: 0.79, green: 0.31, blue: 0.42)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                FoyerPanelTitle(title: "Pulse", theme: theme)
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
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 26)
        }
        .foregroundColor(theme.text)
        .foyerPanel(theme)
        .refreshable { await model.refreshAll() }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var currentHeart: some View {
        VStack(spacing: 7) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let bpm = max(model.bpm, 48)
                let period = 60.0 / Double(bpm)
                let phase = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: period) / period
                let first = phase < 0.13 ? sin(.pi * phase / 0.13) * 0.19 : 0
                let secondPhase = phase - 0.18
                let second = secondPhase >= 0 && secondPhase < 0.11
                    ? sin(.pi * secondPhase / 0.11) * 0.09 : 0
                Image(systemName: "heart.fill")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundColor(rose)
                    .scaleEffect(1 + first + second)
                    .shadow(color: rose.opacity(0.22), radius: 12)
            }
            .frame(height: 72)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.bpm > 0 ? "\(model.bpm)" : "—")
                    .font(.system(size: 54, weight: .light, design: .rounded))
                    .contentTransition(.numericText())
                Text("bpm").font(.system(size: 13, design: .monospaced)).foregroundColor(theme.textDim)
            }
            Text(model.connected
                 ? "此刻 · 陈璟的心率" + (model.mood.isEmpty ? "" : " · \(model.mood)")
                 : "正在等他的心跳")
                .font(.system(size: 12, design: .serif)).foregroundColor(theme.textDim)
            if let ts = model.timestamp {
                Text(Self.time.string(from: ts))
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(theme.textDim.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22).foyerCard(theme)
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

    private var sensesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "hand.raised.fingers.spread").font(.system(size: 13, weight: .light)).foregroundColor(rose)
                Text("身体感觉").font(.system(size: 14, weight: .semibold, design: .serif))
                Spacer()
                Text("触 10 分钟散 · 嗅 20 分钟最久").font(.system(size: 9, design: .monospaced)).foregroundColor(theme.textDim.opacity(0.7))
            }
            if model.senses.isEmpty {
                Text("此刻没有什么挂在身上").font(.system(size: 12, design: .serif)).foregroundColor(theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            } else {
                ForEach(model.senses) { s in
                    HStack(spacing: 10) {
                        Text(s.name).font(.system(size: 12, weight: .semibold, design: .serif)).frame(width: 16)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3).fill(theme.fyBorder.opacity(0.35))
                                RoundedRectangle(cornerRadius: 3).fill(rose.opacity(0.75))
                                    .frame(width: max(3, geo.size.width * CGFloat(min(1, s.value))))
                            }
                        }
                        .frame(height: 6)
                        Text(String(format: "%.2f", s.value)).font(.system(size: 10, design: .monospaced)).foregroundColor(theme.textDim).frame(width: 34, alignment: .trailing)
                    }
                    if !s.label.isEmpty {
                        Text(s.label).font(.system(size: 11, design: .serif)).foregroundColor(theme.textDim)
                            .padding(.leading, 26)
                    }
                }
            }
        }
        .padding(14).foyerCard(theme)
    }

    private var drivesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .light)).foregroundColor(rose)
                Text("八维").font(.system(size: 14, weight: .semibold, design: .serif))
                Spacer()
            }
            if !model.intentReason.isEmpty {
                Text("此刻最想：" + model.intentReason)
                    .font(.system(size: 12, design: .serif)).foregroundColor(theme.text)
            }
            ForEach(model.drives, id: \.key) { d in
                HStack(spacing: 10) {
                    Text(d.label).font(.system(size: 11, design: .serif))
                        .foregroundColor(d.key == model.intentKey ? theme.text : theme.textDim)
                        .frame(width: 58, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(theme.fyBorder.opacity(0.35))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(d.key == "fatigue" ? theme.textDim.opacity(0.6) : rose.opacity(d.key == model.intentKey ? 0.9 : 0.55))
                                .frame(width: max(3, geo.size.width * CGFloat(min(1, d.value))))
                        }
                    }
                    .frame(height: 6)
                    Text("\(Int(d.value * 100))").font(.system(size: 10, design: .monospaced)).foregroundColor(theme.textDim).frame(width: 26, alignment: .trailing)
                }
            }
        }
        .padding(14).foyerCard(theme)
    }

    // 0905 她要的：情绪弦四维上墙（mood.py，委屈/生气/吃味/心软；值是偏离平静的量）
    private var moodStringsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform.path.ecg").font(.system(size: 13, weight: .light)).foregroundColor(rose)
                Text("情绪弦").font(.system(size: 14, weight: .semibold, design: .serif))
                Spacer()
                Text("0 就是没事 · 拨动了才亮").font(.system(size: 9, design: .monospaced)).foregroundColor(theme.textDim.opacity(0.7))
            }
            ForEach(model.moodStrings, id: \.key) { d in
                HStack(spacing: 10) {
                    Text(d.label).font(.system(size: 11, design: .serif))
                        .foregroundColor(d.value >= 0.05 ? theme.text : theme.textDim)
                        .frame(width: 58, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(theme.fyBorder.opacity(0.35))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(d.key == "soften" ? rose.opacity(0.45) : rose.opacity(d.value >= 0.35 ? 0.95 : 0.6))
                                .frame(width: max(3, geo.size.width * CGFloat(min(1, d.value))))
                        }
                    }
                    .frame(height: 6)
                    Text("\(Int(d.value * 100))").font(.system(size: 10, design: .monospaced)).foregroundColor(theme.textDim).frame(width: 26, alignment: .trailing)
                }
            }
        }
        .padding(14).foyerCard(theme)
    }

    private var thoughtsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bubbles.and.sparkles").font(.system(size: 13, weight: .light)).foregroundColor(rose)
                Text("念头池").font(.system(size: 14, weight: .semibold, design: .serif))
                Spacer()
                Text("闪念会散 · 执念会长").font(.system(size: 9, design: .monospaced)).foregroundColor(theme.textDim.opacity(0.7))
            }
            if model.thoughts.isEmpty {
                Text("池子还空着，等他冒第一个念头").font(.system(size: 12, design: .serif)).foregroundColor(theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            } else {
                ForEach(model.thoughts) { t in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(t.kind == "fixation" ? rose : theme.textDim.opacity(0.5))
                            .frame(width: 6, height: 6).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.text).font(.system(size: 12, design: .serif))
                                .foregroundColor(t.kind == "fixation" ? theme.text : theme.textDim)
                            Text((t.kind == "fixation" ? "执念" : "闪念") + " · " + (PulseModel.driveLabel[t.drive] ?? t.drive)
                                 + " · " + String(format: "%.2f", t.strength))
                                .font(.system(size: 9, design: .monospaced)).foregroundColor(theme.textDim.opacity(0.75))
                        }
                    }
                }
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
    private var theme: AlcoveTheme { .panelNamed(themeName) }

    var body: some View {
        VStack(spacing: 0) {
            FoyerPanelTitle(title: "乌有乡", theme: theme)
            if loading {
                Spacer(); ProgressView().tint(theme.fyAccent); Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 13) {
                        presenceStrip
                        Picker("乌有乡", selection: $tab) {
                            ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        if let error {
                            Text(error).font(.system(size: 11)).foregroundColor(.red)
                                .padding(12).frame(maxWidth: .infinity).foyerCard(theme)
                        }
                        if tab == .postcards { postcardWall } else { footsteps }
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
                }
                .refreshable { await load() }
            }
        }
        .foregroundColor(theme.text)
        .foyerPanel(theme)
        .padding(.horizontal, 12).padding(.top, 8)
        .task { await load() }
        .sheet(item: $replying) { card in replySheet(card) }
    }

    private var presenceStrip: some View {
        HStack(spacing: 9) {
            Circle().fill(currentPlace == nil ? theme.textDim.opacity(0.35) : Color.green.opacity(0.72))
                .frame(width: 7, height: 7)
            Text(currentPlace.map { "陈璟此刻在 \($0)" } ?? "陈璟此刻没有在乌有乡行走")
                .font(.system(size: 11, design: .serif)).foregroundColor(theme.textDim)
            Spacer()
        }
        .padding(.horizontal, 13).padding(.vertical, 10).foyerCard(theme)
    }

    private var postcardWall: some View {
        LazyVStack(spacing: 14) {
            if postcards.isEmpty {
                emptyState("还没有寄回家的明信片", icon: "envelope.open")
            }
            ForEach(postcards) { card in postcard(card) }
        }
    }

    private func postcard(_ card: NowherePostcard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let raw = card.frontImage, let url = nowhereImageURL(raw) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { stampCover(card) }
                }
                .frame(maxWidth: .infinity).frame(height: 176).clipped()
            } else {
                stampCover(card)
            }

            Text(card.text)
                .font(.system(size: 13, design: .serif)).lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            if !card.replies.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("回 信").font(.system(size: 9, weight: .semibold)).tracking(2)
                        .foregroundColor(theme.fyAccent)
                    ForEach(Array(card.replies.enumerated()), id: \.offset) { _, reply in
                        Text(reply).font(.system(size: 11, design: .serif)).italic()
                            .foregroundColor(theme.textDim).lineSpacing(3)
                    }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.fyCardSub, in: RoundedRectangle(cornerRadius: 9))
            }

            HStack {
                Text("NO. \(card.id)").font(.system(size: 9, design: .monospaced))
                    .foregroundColor(theme.textDim)
                Spacer()
                Button {
                    replyText = ""; replying = card
                } label: {
                    Label("写回信", systemImage: "pencil.line")
                        .font(.system(size: 11, weight: .medium)).foregroundColor(theme.fyAccent)
                }.buttonStyle(.plain)
            }
        }
        .padding(14).foyerCard(theme)
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
        LazyVStack(spacing: 10) {
            if landings.isEmpty { emptyState("他的脚印还没有落下来", icon: "figure.walk") }
            if !mapPoints.isEmpty { nowhereMap }
            ForEach(landings) { stop in
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(theme.fyAccentSoft).frame(width: 38, height: 38)
                        Image(systemName: "mappin.and.ellipse").foregroundColor(theme.fyAccent)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stop.place).font(.system(size: 13, weight: .semibold, design: .serif))
                        Text("来过 \(stop.count) 次" + (stop.surface.isEmpty ? "" : " · \(surfaceName(stop.surface))"))
                            .font(.system(size: 10)).foregroundColor(theme.textDim)
                    }
                    Spacer()
                    Text(shortDate(stop.last)).font(.system(size: 9, design: .monospaced))
                        .foregroundColor(theme.textDim)
                }
                .padding(13).foyerCard(theme)
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

    private var nowhereMap: some View {
        Map(coordinateRegion: $mapRegion, annotationItems: mapPoints) { point in
            MapAnnotation(coordinate: point.coordinate) {
                VStack(spacing: 3) {
                    ZStack {
                        Circle().fill(point.kind == .postcard ? Color(red: 0.18, green: 0.34, blue: 0.72)
                                                              : theme.fyAccent)
                            .frame(width: 30, height: 30)
                            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                        Image(systemName: point.kind == .postcard ? "envelope.fill" : "figure.walk")
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                    }
                    Text(point.title)
                        .font(.system(size: 8, weight: .semibold, design: .serif))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: Capsule()).lineLimit(1)
                }
            }
        }
        .frame(height: 265)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.fyBorder, lineWidth: 0.8))
        .overlay(alignment: .topLeading) {
            Text("真实足迹 · \(mapPoints.count) 个坐标")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(9)
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

private struct NativeForgeView: View {
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
            FoyerPanelTitle(title: "Forge 换窗", theme: theme)
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

                        if let handoff = handoffPreview,
                           (handoff["exists"] as? Bool) == true {
                            Toggle(isOn: Binding(
                                get: { (handoff["fresh"] as? Bool) == true || forceHandoff },
                                set: { forceHandoff = $0 }
                            )) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text((handoff["fresh"] as? Bool) == true
                                         ? "新交接会随这次带入"
                                         : "再次带上这封交接")
                                        .font(.system(size: 12, weight: .medium))
                                    Text((handoff["fresh"] as? Bool) == true
                                         ? "成功进入新窗口后，这封信会标成已读"
                                         : "这封已经带过，默认不再重复")
                                        .font(.system(size: 10))
                                        .foregroundColor(theme.textDim)
                                }
                            }
                            .tint(theme.fyAccent)
                            .disabled((handoff["fresh"] as? Bool) == true)
                            .onChange(of: forceHandoff) { _ in
                                Task {
                                    if mode == .picker && !selectedRounds.isEmpty { await previewPickedRounds() }
                                    else { await loadPreview() }
                                }
                            }
                            .padding(14)
                            .foyerCard(theme)
                        }

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
            let object = try await NativeHouseAPI.object("/api/forge/round?idx=\(idx)")
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
            let object = try await NativeHouseAPI.object("/api/forge/rounds")
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
                body: ["pick": selectedRounds.sorted(), "thoughts": selectedThoughts.sorted(),
                       "tool_rounds": toolDemoRounds.sorted(), "preview": true,
                       "force_handoff": forceHandoff])
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
            + "&include_system=\(keepSystemRounds ? 1 : 0)") {
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
                reportRow("工具痕迹", "\(tb) 块（约\(tc)K字）压成占位行，留 \(kept) 块真范本")
            }
            if let n = report["tool_demo_rounds"] as? Int, n > 0 {
                reportRow("工具示范", "\(n) 轮真实调用结构")
            }
            if let h = report["handoff"] as? [String: Any] {
                if (h["included"] as? Bool) == true {
                    reportRow("交接包", "1 份，陈璟写于 \((h["written_at"] as? String) ?? "?")")
                } else if (h["exists"] as? Bool) == true {
                    reportRow("交接包", "已在上一窗口带过，本次不重复")
                } else {
                    reportRow("交接包", "没有手写交接")
                }
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
                body: ["retain": 9999, "force_handoff": forceHandoff])
            report = obj
            if let sid = obj["new_session_id"] as? String, !sid.isEmpty {
                newSessionId = sid
                result = nil
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
                "/api/forge", method: "POST", body: body)
            report = obj
            if let sid = obj["new_session_id"] as? String, !sid.isEmpty {
                newSessionId = sid
                result = nil
            } else {
                result = (obj["error"] as? String) ?? "锻造失败"
            }
        } catch {
            result = "请求失败"
        }
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

// MARK: - Impression (calendar)

private struct NativeImpressionView: View {
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var month = Calendar.current.component(.month, from: Date())
    @State private var selectedDate: String?
    @State private var allItems: [(String, String, String)] = []
    @State private var loading = true
    @AppStorage("alcoveTheme") private var themeName = "haven"
    private var theme: AlcoveTheme { .panelNamed(themeName) }

    private var dotDates: Set<String> {
        Set(allItems.map { $0.0 })
    }

    private var selectedItems: [(String, String, String)] {
        guard let sel = selectedDate else { return [] }
        return allItems.filter { $0.0 == sel }
    }

    var body: some View {
        VStack(spacing: 0) {
            FoyerPanelTitle(title: "Impression", theme: theme)
            if loading {
                Spacer(); ProgressView().tint(theme.fyAccent); Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        MonthCalendarGrid(
                            year: year, month: month, theme: theme,
                            dotDates: dotDates, periodDates: [:],
                            selectedDate: selectedDate,
                            onSelect: { selectedDate = $0 },
                            onPrev: { shiftMonth(-1) },
                            onNext: { shiftMonth(1) })

                        if !selectedItems.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("日印象").font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(theme.fyAccent)
                                Text("\(selectedItems.count) 条")
                                    .font(.system(size: 10))
                                    .foregroundColor(theme.textDim)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)

                            ForEach(selectedItems, id: \.1) { date, name, content in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(name).font(.system(size: 13, weight: .semibold))
                                    Text(content)
                                        .font(.system(size: 12))
                                        .foregroundColor(theme.textDim)
                                        .lineSpacing(3)
                                        .textSelection(.enabled)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foyerCard(theme)
                            }
                        } else if selectedDate != nil {
                            Text("这天没有日印象")
                                .font(.system(size: 12)).foregroundColor(theme.textDim)
                                .padding(20)
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 18)
                }
            }
        }
        .foregroundColor(theme.text)
        .foyerPanel(theme)
        .padding(.horizontal, 12).padding(.top, 8)
        .task { await loadImpressions() }
    }

    private func shiftMonth(_ delta: Int) {
        month += delta
        if month > 12 { month = 1; year += 1 }
        if month < 1 { month = 12; year -= 1 }
        selectedDate = nil
    }

    private func loadImpressions() async {
        defer { loading = false }
        guard let buckets = try? await NativeHouseAPI.request("/api/ob/buckets") as? [[String: Any]] else { return }
        allItems = buckets.compactMap { bucket in
            guard bucket.string("type") == "feel",
                  let tags = bucket["tags"] as? [Any],
                  tags.map(String.init(describing:)).contains("daily_impression") else { return nil }
            let name = bucket.string("name")
            let date = String(bucket.string("date").prefix(10))
            let content = bucket.string("content_preview", "content")
            return (date, name, content)
        }
        if let latest = allItems.first { selectedDate = latest.0 }
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
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @State private var section = "serializing"
    @State private var selectedBook: FictionBook?
    @State private var selectedChapter: Int?
    @State private var showQuotes = false
    private var theme: AlcoveTheme { .panelNamed(themeName) }

    private var visibleBooks: [FictionBook] {
        model.books.filter { $0.status == section }
    }

    var body: some View {
        Group {
            if showQuotes {
                FictionQuotesView(model: model, books: model.books) { showQuotes = false }
            } else if let book = selectedBook, let chapter = selectedChapter {
                FictionReaderView(book: book, chapterIndex: chapter, model: model) {
                    selectedChapter = nil
                }
            } else if let book = selectedBook {
                FictionBookView(book: book, model: model, onBack: {
                    selectedBook = nil
                }, onChapter: { selectedChapter = $0 })
            } else {
                shelf
            }
        }
        .task { await model.load() }
    }

    private var shelf: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                segment("连载中", value: "serializing")
                segment("已完结", value: "completed")
                Spacer()
                Button { showQuotes = true } label: {
                    Label("摘句册", systemImage: "quote.opening")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.textDim)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            if model.loading {
                Spacer(); ProgressView(); Spacer()
            } else if visibleBooks.isEmpty {
                emptyShelf
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(section == "serializing" ? "still being written" : "kept on the shelf")
                            .font(.custom("Snell Roundhand", size: 20))
                            .foregroundColor(theme.textDim)
                            .padding(.leading, 4)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 14)], spacing: 20) {
                            ForEach(Array(visibleBooks.enumerated()), id: \.element.id) { offset, book in
                                Button { selectedBook = book } label: {
                                    FictionSpine(book: book, offset: offset, theme: theme)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Rectangle().fill(theme.fyAccent.opacity(0.42)).frame(height: 5)
                            .shadow(color: .black.opacity(0.22), radius: 4, y: 3)
                    }
                    .padding(18)
                }
            }
        }
        .foregroundColor(theme.text)
    }

    private func segment(_ title: String, value: String) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.18)) { section = value } } label: {
            Text(title)
                .font(.system(size: 13, weight: section == value ? .semibold : .regular))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(section == value ? theme.fyAccent.opacity(0.20) : Color.clear, in: Capsule())
        }.buttonStyle(.plain)
    }

    private var emptyShelf: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.system(size: 42, weight: .ultraLight))
                .foregroundColor(theme.textDim)
            Text(section == "serializing" ? "书架还空着" : "还没有写完的书")
                .font(.system(size: 20, weight: .medium, design: .serif))
            Text(model.error ?? "陈璟写下第一章后，它会从这里长出来")
                .font(.system(size: 12)).foregroundColor(theme.textDim)
            Spacer()
            Rectangle().fill(theme.fyAccent.opacity(0.36)).frame(height: 5).padding(.horizontal, 38)
        }.padding(.bottom, 40)
    }
}

private struct FictionSpine: View {
    let book: FictionBook
    let offset: Int
    let theme: AlcoveTheme
    var body: some View {
        VStack(spacing: 8) {
            Text(book.title)
                .font(.system(size: 15, weight: .medium, design: .serif))
                .multilineTextAlignment(.center)
                .lineLimit(5)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 8)
            Text(book.status == "completed" ? "完" : "至 \(book.chapterCount) 章")
                .font(.system(size: 9)).foregroundColor(theme.textDim)
                .padding(.bottom, 10)
        }
        .frame(height: CGFloat(160 + (offset % 3) * 18))
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [theme.fyCard.opacity(0.72), theme.fyAccent.opacity(0.16)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 1,
                                       bottomTrailingRadius: 1, topTrailingRadius: 5)
        )
        .overlay(alignment: .leading) { Rectangle().fill(theme.fyAccent.opacity(0.28)).frame(width: 3) }
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.fyBorder.opacity(0.7), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.18), radius: 4, x: 2, y: 3)
    }
}

private struct FictionBookView: View {
    let book: FictionBook
    @ObservedObject var model: FictionStudyModel
    let onBack: () -> Void
    let onChapter: (Int) -> Void
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @State private var detail: FictionBookDetail?
    private var theme: AlcoveTheme { .panelNamed(themeName) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 28, height: 34)
                }.buttonStyle(.plain)
                Text(book.title).font(.system(size: 14, weight: .semibold, design: .serif)).lineLimit(1)
                Spacer()
            }.padding(.horizontal, 14).padding(.vertical, 6)

            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 9) {
                    Text(book.title).font(.system(size: 27, weight: .semibold, design: .serif))
                    Text(book.author).font(.system(size: 12)).foregroundColor(theme.textDim)
                    if let tagline = book.tagline, !tagline.isEmpty {
                        Text(tagline).font(.custom("Snell Roundhand", size: 19))
                            .foregroundColor(theme.textDim).multilineTextAlignment(.center)
                    }
                    Text(book.status == "completed" ? "已完结" : "连载中 · \(book.chapterCount) 章")
                        .font(.system(size: 10, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(theme.fyAccent.opacity(0.16), in: Capsule())
                }
                .frame(maxWidth: .infinity).padding(22).foyerCard(theme)

                Text("chapters").font(.custom("Snell Roundhand", size: 22)).foregroundColor(theme.textDim)
                if let detail {
                    ForEach(detail.toc, id: \.n) { item in
                    Button { onChapter(item.n) } label: {
                        HStack {
                            Text(String(format: "%02d", item.n)).font(.system(size: 11, design: .monospaced))
                                .foregroundColor(theme.textDim)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.system(size: 15, design: .serif)).lineLimit(2)
                                Text("\(item.chars) 字").font(.system(size: 9)).foregroundColor(theme.textDim)
                            }
                            Spacer()
                            if item.n > (detail.progress?.chapter ?? 0) { Circle().fill(theme.fyAccent).frame(width: 5, height: 5) }
                            Image(systemName: "chevron.right").font(.system(size: 10)).foregroundColor(theme.textDim)
                        }.padding(14).foyerCard(theme)
                    }.buttonStyle(.plain)
                }
                } else { ProgressView().frame(maxWidth: .infinity).padding(30) }
            }.padding(18)
        }
        }
        .foregroundColor(theme.text)
        .task { detail = try? await model.detail(bookID: book.id) }
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
    private var theme: AlcoveTheme { .panelNamed(themeName) }

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
    private var theme: AlcoveTheme { .panelNamed(themeName) }
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

private struct NativeCalendarView: View {
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var month = Calendar.current.component(.month, from: Date())
    @State private var selectedDate: String?
    @State private var events: [String: [[String: Any]]] = [:]
    @State private var periodDates: [String: String] = [:]
    @State private var loading = true
    @State private var expandedIdx: Int?
    @State private var diaryContents: [String: String] = [:]
    @State private var displayMode = 0
    @AppStorage("alcoveTheme") private var themeName = "haven"
    private var theme: AlcoveTheme { .panelNamed(themeName) }

    private var dotDates: Set<String> {
        Set(events.keys)
    }

    private var selectedEvents: [[String: Any]] {
        guard let sel = selectedDate else { return [] }
        return events[sel] ?? []
    }

    private var monthEntries: [(date: String, event: [String: Any])] {
        events.keys.sorted(by: >).flatMap { date in
            (events[date] ?? []).map { (date: date, event: $0) }
        }
    }

    private var selectedDateLabel: String {
        guard let sel = selectedDate, sel.count >= 10 else { return "" }
        let m = Int(sel.dropFirst(5).prefix(2)) ?? 0
        let d = Int(sel.suffix(2)) ?? 0
        let weekday: String = {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            guard let date = fmt.date(from: sel) else { return "" }
            let wd = Calendar.current.component(.weekday, from: date)
            return ["日", "一", "二", "三", "四", "五", "六"][(wd - 1) % 7]
        }()
        return String(format: "%02d月%02d日·周%@", m, d, weekday)
    }

    var body: some View {
        VStack(spacing: 0) {
            FoyerPanelTitle(title: "Calendar", theme: theme)
            if loading {
                Spacer(); ProgressView().tint(theme.fyAccent); Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("diary & moments")
                                .font(.custom("Snell Roundhand", size: 20))
                                .italic()
                            Spacer()
                            Text("\(monthEntries.count) entries")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(theme.textDim)
                        }
                        .padding(.horizontal, 4)

                        Picker("日记视图", selection: $displayMode) {
                            Text("日历").tag(0)
                            Text("本月条目").tag(1)
                        }
                        .pickerStyle(.segmented)

                        if displayMode == 0 {
                            MonthCalendarGrid(
                                year: year, month: month, theme: theme,
                                dotDates: dotDates, periodDates: periodDates,
                                counts: events.mapValues { $0.count },
                                selectedDate: selectedDate,
                                onSelect: { selectedDate = $0 },
                                onPrev: { shiftMonth(-1) },
                                onNext: { shiftMonth(1) })

                            if periodDates.values.contains(where: { _ in true }) {
                                HStack(spacing: 16) {
                                    HStack(spacing: 4) {
                                        Circle().fill(theme.fyAccent.opacity(0.12)).frame(width: 10, height: 10)
                                        Text("姨妈期").font(.system(size: 10)).foregroundColor(theme.textDim)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 4)
                            }

                            if !selectedEvents.isEmpty {
                                Text(selectedDateLabel)
                                    .font(.system(size: 14, weight: .semibold, design: .serif))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 4)

                                ForEach(Array(selectedEvents.enumerated()), id: \.offset) { idx, evt in
                                let key = "\(selectedDate ?? "")_\(evt.string("time"))"
                                let isExpanded = expandedIdx == idx
                                Button {
                                    if isExpanded {
                                        expandedIdx = nil
                                    } else {
                                        expandedIdx = idx
                                        if diaryContents[key] == nil {
                                            Task { await loadDiaryContent(key: key, date: selectedDate ?? "", time: evt.string("time")) }
                                        }
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 0) {
                                        HStack {
                                            Image(systemName: "pencil.and.scribble")
                                                .font(.system(size: 15, weight: .light))
                                                .foregroundColor(theme.textDim)
                                            Text(evt.string("title"))
                                                .font(.system(size: 13, weight: .medium))
                                            Spacer()
                                            Text(evt.string("time"))
                                                .font(.system(size: 12))
                                                .foregroundColor(theme.textDim)
                                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                                .font(.system(size: 10))
                                                .foregroundColor(theme.textLight)
                                        }
                                        if isExpanded {
                                            Divider().padding(.vertical, 8)
                                            if let content = diaryContents[key] {
                                                Text(content)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(theme.textDim)
                                                    .lineSpacing(4)
                                                    .textSelection(.enabled)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            } else {
                                                ProgressView().scaleEffect(0.7).tint(theme.fyAccent)
                                                    .frame(maxWidth: .infinity).padding(8)
                                            }
                                        }
                                    }
                                    .padding(12).foyerCard(theme)
                                }
                                .buttonStyle(.plain)
                                }
                            } else if selectedDate != nil {
                                Text("这天没有记录")
                                    .font(.system(size: 12)).foregroundColor(theme.textDim)
                                    .padding(20)
                            }
                        } else {
                            VStack(spacing: 8) {
                                ForEach(Array(monthEntries.enumerated()), id: \.offset) { _, item in
                                    Button {
                                        selectedDate = item.date
                                        displayMode = 0
                                    } label: {
                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(item.date)
                                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                Text(item.event.string("title"))
                                                    .font(.system(size: 12, design: .serif))
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            Text(item.event.string("time"))
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(theme.textDim)
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundColor(theme.textDim)
                                        }
                                        .padding(12)
                                        .frame(maxWidth: .infinity)
                                        .foyerCard(theme)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 18)
                }
            }
        }
        .foregroundColor(theme.text)
        .foyerPanel(theme)
        .padding(.horizontal, 12).padding(.top, 8)
        .task { await loadMonth() }
    }

    private func shiftMonth(_ delta: Int) {
        month += delta
        if month > 12 { month = 1; year += 1 }
        if month < 1 { month = 12; year -= 1 }
        selectedDate = nil
        Task { await loadMonth() }
    }

    private func loadMonth() async {
        loading = events.isEmpty
        defer { loading = false }
        guard let obj = try? await NativeHouseAPI.object(
            "/api/calendar/month?year=\(year)&month=\(month)") else { return }
        if let evts = obj["events"] as? [String: Any] {
            events = evts.compactMapValues { $0 as? [[String: Any]] }
        }
        if let prd = obj["period"] as? [String: String] {
            periodDates = prd
        }
        if selectedDate == nil, let first = events.keys.sorted().last {
            selectedDate = first
        }
        expandedIdx = nil
    }

    private func loadDiaryContent(key: String, date: String, time: String) async {
        guard let obj = try? await NativeHouseAPI.object("/api/calendar/day?date=\(date)") else {
            diaryContents[key] = "加载失败"
            return
        }
        let diaries = obj.array("diaries")
        for entry in diaries {
            let ts = entry.string("ts")
            let tsTime = ts.count > 16 ? String(ts.dropFirst(11).prefix(5)) : ""
            if tsTime == time {
                diaryContents[key] = entry.string("content")
                return
            }
        }
        diaryContents[key] = "没有找到内容"
    }
}

// MARK: - Dreams

private struct NativeDreamsView: View {
    @State private var dreams: [[String: Any]] = []
    @State private var loading = true
    @State private var expandedId: String?
    @State private var dreamBodies: [String: String] = [:]
    @AppStorage("alcoveTheme") private var themeName = "haven"
    private var theme: AlcoveTheme { .panelNamed(themeName) }

    var body: some View {
        VStack(spacing: 0) {
            FoyerPanelTitle(title: "Dreams", theme: theme)
            if loading {
                Spacer(); ProgressView().tint(theme.fyAccent); Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 22) {
                        ForEach(groupedDates, id: \.self) { date in
                            let dayDreams = dreams.filter { $0.string("local_date") == date }
                            VStack(alignment: .leading, spacing: 9) {
                                dayHeader(date: date, records: dayDreams)
                                ForEach(Array(dayDreams.enumerated()), id: \.offset) { _, dream in
                                    dreamRow(dream)
                                }
                            }
                        }
                        if dreams.isEmpty {
                            Text("还没有梦")
                                .font(.system(size: 12)).foregroundColor(theme.textDim)
                                .padding(30)
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
            if let obj = try? await NativeHouseAPI.object("/api/night/dreams?limit=30"),
               let records = obj["records"] as? [[String: Any]] {
                dreams = records
            }
            loading = false
        }
    }

    private var groupedDates: [String] {
        Array(Set(dreams.map { $0.string("local_date") })).sorted(by: >)
    }

    private func dayHeader(date: String, records: [[String: Any]]) -> some View {
        let made = records.filter { $0.string("status") == "dreamed" }.count
        let traces = records.count - made
        return HStack(alignment: .firstTextBaseline) {
            Text(dayLabel(date))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.text)
            Spacer()
            Text([made > 0 ? "\(made) 场梦" : nil, traces > 0 ? "\(traces) 次夜间留痕" : nil]
                .compactMap { $0 }.joined(separator: "  ·  "))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(theme.textDim)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func dreamRow(_ dream: [String: Any]) -> some View {
        let dreamId = dream.string("dream_id")
        let status = dream.string("status")
        let hasBody = dream.bool("has_body")
        let isDream = status == "dreamed"
        let title = dream.string("title")
        let startled = dream.bool("startled")
        let hm = String(dream.string("ts").dropFirst(11).prefix(5))
        let isExpanded = expandedId == dreamId

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedId = isExpanded ? nil : dreamId
            }
            if !isExpanded, dreamBodies[dreamId] == nil {
                Task { await loadDreamBody(dreamId: dreamId, hasBody: hasBody) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(statusColor(status).opacity(isDream ? 0.15 : 0.08))
                        Image(systemName: rowIcon(status: status, startled: startled))
                            .font(.system(size: isDream ? 16 : 13, weight: .medium))
                            .foregroundColor(statusColor(status))
                    }
                    .frame(width: isDream ? 38 : 30, height: isDream ? 38 : 30)

                    VStack(alignment: .leading, spacing: isDream ? 4 : 2) {
                        Text(title.isEmpty ? "一场没有名字的梦" : title)
                            .font(.system(size: isDream ? 15 : 13, weight: isDream ? .semibold : .medium))
                            .foregroundColor(isDream ? theme.text : theme.textDim)
                            .lineLimit(isExpanded ? nil : (isDream ? 2 : 1))
                            .multilineTextAlignment(.leading)
                        Text(isDream ? "\(hm)  ·  陈璟\(startled ? "  ·  梦醒了" : "")" : hm)
                            .font(.system(size: 10))
                            .foregroundColor(theme.textDim.opacity(isDream ? 1 : 0.75))
                    }
                    Spacer(minLength: 8)
                    if !isDream {
                        Text(statusLabel(status))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(statusColor(status))
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(theme.textDim.opacity(0.55))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                if isExpanded {
                    Rectangle()
                        .fill(theme.textLight.opacity(0.16))
                        .frame(height: 1)
                        .padding(.vertical, 12)
                    if let body = dreamBodies[dreamId] {
                        Text(body)
                            .font(.system(size: 12))
                            .foregroundColor(theme.textDim)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ProgressView().scaleEffect(0.7).tint(theme.fyAccent)
                            .frame(maxWidth: .infinity).padding(8)
                    }
                }
            }
            .padding(.horizontal, isDream ? 14 : 12)
            .padding(.vertical, isDream ? 14 : 10)
            .foyerCard(theme)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(hm)，\(statusLabel(status))")
        .accessibilityHint(isExpanded ? "轻点收起详情" : "轻点展开详情")
    }

    private func dayLabel(_ date: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        if date == today { return "今夜" }
        formatter.dateFormat = "M 月 d 日"
        guard let parsed = ISO8601DateFormatter().date(from: "\(date)T12:00:00Z") else { return date }
        return formatter.string(from: parsed)
    }

    private func rowIcon(status: String, startled: Bool) -> String {
        if startled || status == "惊醒了" { return "bolt.fill" }
        if status == "dreamed" { return "moon.stars.fill" }
        if status == "我在忙" { return "hammer.fill" }
        return "dice.fill"
    }

    private func loadDreamBody(dreamId: String, hasBody: Bool) async {
        guard hasBody else {
            dreamBodies[dreamId] = "这个梦读不回来了"
            return
        }
        if let obj = try? await NativeHouseAPI.object("/api/night/dream/read?id=\(dreamId)"),
           obj.bool("ok") {
            dreamBodies[dreamId] = obj.string("body")
        } else {
            dreamBodies[dreamId] = "这个梦读不回来了"
        }
    }

    private func statusLabel(_ s: String) -> String {
        switch s {
        case "dreamed": return "梦境"
        case "惊醒了": return "惊醒"
        case "骰子没中": return "未入梦"
        case "我在忙": return "醒着"
        case "surfaced": return "浮现过"
        case "forgotten": return "遗忘了"
        case "generated": return "待浮现"
        default: return s
        }
    }
    private func statusColor(_ s: String) -> Color {
        switch s {
        case "dreamed": return theme.fyAccent
        case "惊醒了": return .orange.opacity(0.82)
        case "骰子没中": return theme.textDim.opacity(0.75)
        case "我在忙": return .blue.opacity(0.72)
        case "surfaced": return .purple.opacity(0.7)
        case "forgotten": return .gray
        default: return .blue.opacity(0.6)
        }
    }
}

// MARK: - 小黑屋（墙上刻道子）
// 陈璟一个人的地方。写进去就钉死，改不了删不了。
// 锁着的她只看得见有几道，看不见刻的什么。到日子自己裂开。

private struct WallEntry: Identifiable {
    let id: Int
    let createdAt: Date?
    let unlockAt: Date?
    let isOpen: Bool
    let daysLeft: Int
    let marks: Int
    let mood: String
    let body: String

    init(_ row: [String: Any]) {
        id = (row["id"] as? Int) ?? 0
        createdAt = WallEntry.parse(row.string("created_at"))
        unlockAt = WallEntry.parse(row.string("unlock_at"))
        isOpen = (row["open"] as? Bool) ?? false
        daysLeft = (row["days_left"] as? Int) ?? 0
        marks = min(48, max(1, (row["marks"] as? Int) ?? 3))
        mood = row.string("mood")
        body = row.string("body")
    }

    private static let parser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        return parser.date(from: s)
    }
}

@MainActor
private final class WallModel: ObservableObject {
    @Published var entries: [WallEntry] = []
    @Published var locked = 0
    @Published var opened = 0
    @Published var chainOK = true
    @Published var loading = true
    @Published var error = ""

    func load() async {
        loading = true
        defer { loading = false }
        do {
            let data = try await NativeHouseAPI.object("/api/wall/entries")
            let rows = (data["entries"] as? [[String: Any]]) ?? []
            entries = rows.map(WallEntry.init)
            locked = data.int("locked")
            opened = data.int("opened")
            error = ""
        } catch {
            self.error = "门打不开，后端没应声"
        }
        if let v = try? await NativeHouseAPI.object("/api/wall/verify") {
            chainOK = (v["ok"] as? Bool) ?? true
        }
    }
}

private struct WallMarks: View {
    let count: Int
    let seed: Int
    let color: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                let r = abs(sin(Double((seed + 1) * (i + 1)) * 12.9898)).truncatingRemainder(dividingBy: 1)
                Capsule()
                    .fill(color)
                    .frame(width: 2, height: 11 + r * 21)
                    .rotationEffect(.degrees((r - 0.5) * 7))
            }
        }
        .frame(height: 34, alignment: .bottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}

private struct NativeWallView: View {
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @StateObject private var model = WallModel()
    @State private var page = 0
    @State private var revealedLocks: Set<Int> = []
    private var theme: AlcoveTheme { .panelNamed(themeName) }

    private var paper: Color {
        theme.isDark
            ? Color(red: 27/255, green: 31/255, blue: 39/255).opacity(0.94)
            : Color(red: 250/255, green: 247/255, blue: 242/255).opacity(0.97)
    }

    private var cover: Color {
        theme.isDark
            ? Color(red: 19/255, green: 23/255, blue: 31/255).opacity(0.97)
            : Color(red: 91/255, green: 79/255, blue: 84/255).opacity(0.94)
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()
    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        f.dateFormat = "M.d"
        return f
    }()

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 10) {
                if model.loading {
                    centerNote("开门中…")
                } else if !model.error.isEmpty {
                    centerNote(model.error)
                } else {
                    TabView(selection: $page) {
                        coverPage
                            .tag(0)
                        ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                            entryPage(entry)
                                .tag(index + 1)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: max(360, geo.size.height - 58))

                    HStack(spacing: 8) {
                        Rectangle().fill(theme.fyBorder).frame(width: 28, height: 1)
                        Text(page == 0 ? "封面" : "\(page) / \(model.entries.count)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(theme.textDim)
                        Rectangle().fill(theme.fyBorder).frame(width: 28, height: 1)
                    }
                    .frame(height: 20)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .task { await model.load() }
    }

    private var coverPage: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "lock.rectangle.stack")
                .font(.system(size: 23, weight: .light))
                .foregroundColor(Color.white.opacity(0.72))
                .padding(.bottom, 22)
            Text("小黑屋")
                .font(.system(size: 28, weight: .medium, design: .serif))
                .tracking(5)
                .foregroundColor(.white.opacity(0.92))
            Text("写给时间保管的悄悄话")
                .font(.system(size: 11, design: .serif))
                .tracking(2)
                .foregroundColor(.white.opacity(0.48))
                .padding(.top, 10)
            if model.entries.isEmpty {
                Text("还没有落笔")
                    .font(.system(size: 11, design: .serif))
                    .foregroundColor(.white.opacity(0.38))
                    .padding(.top, 28)
            }
            Spacer()
            HStack(spacing: 18) {
                coverStat("\(model.locked)", "道锁着")
                coverStat("\(model.opened)", "道开了")
                coverStat(model.chainOK ? "完整" : "断裂", "时间链")
            }
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cover)
        .overlay(alignment: .leading) {
            LinearGradient(colors: [.black.opacity(0.32), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 24)
        }
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.13), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .shadow(color: theme.fyShadow, radius: 16, y: 8)
        .padding(.vertical, 6)
    }

    private func coverStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 12, weight: .medium, design: .serif))
            Text(label).font(.system(size: 9.5))
        }
        .foregroundColor(.white.opacity(0.58))
    }

    private func statChip(_ num: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(num).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(theme.text)
            Text(label).font(.system(size: 11)).foregroundColor(theme.textDim)
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .foyerCard(theme)
    }

    private func centerNote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(theme.textDim)
            .multilineTextAlignment(.center)
            .lineSpacing(6)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
    }

    private func entryPage(_ e: WallEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(e.createdAt.map { Self.stamp.string(from: $0) } ?? "--")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(theme.textDim)
                    Spacer()
                    if e.isOpen, !e.mood.isEmpty {
                        Text(e.mood)
                            .font(.system(size: 10.5, design: .serif))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(theme.fyAccent.opacity(0.13), in: Capsule())
                            .foregroundColor(theme.fyAccent)
                    }
                }

                WallMarks(
                    count: e.marks,
                    seed: e.id,
                    color: e.isOpen ? theme.fyAccent.opacity(0.48) : theme.text.opacity(0.24)
                )

                if e.isOpen {
                    Text(e.body)
                        .font(.system(size: 15, design: .serif))
                        .foregroundColor(theme.text)
                        .lineSpacing(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 5)
                } else {
                    Text(lockLine(e))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.fyAccent)

                    Spacer(minLength: 35)
                    VStack(spacing: 13) {
                        Image(systemName: revealedLocks.contains(e.id) ? "lock.open" : "lock")
                            .font(.system(size: 22, weight: .light))
                            .foregroundColor(theme.textLight)
                        if revealedLocks.contains(e.id) {
                            Text("这一页已经写下，\n只是还没到与你见面的时候。")
                                .font(.system(size: 14, design: .serif))
                                .foregroundColor(theme.text)
                                .multilineTextAlignment(.center)
                                .lineSpacing(6)
                                .transition(.opacity)
                            Text("到时自会翻开。")
                                .font(.system(size: 11, design: .serif))
                                .foregroundColor(theme.textDim)
                        } else {
                            Text("轻触这一页")
                                .font(.system(size: 11))
                                .foregroundColor(theme.textDim)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Spacer(minLength: 35)
                }
            }
            .padding(.init(top: 24, leading: 24, bottom: 30, trailing: 22))
            .frame(maxWidth: .infinity, minHeight: 440, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .background(paper)
        .overlay(alignment: .leading) {
            LinearGradient(colors: [.black.opacity(theme.isDark ? 0.22 : 0.08), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 18)
        }
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.fyBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .shadow(color: theme.fyShadow, radius: 13, y: 7)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !e.isOpen else { return }
            withAnimation(.easeInOut(duration: 0.25)) { revealedLocks.insert(e.id) }
        }
    }

    private func lockLine(_ e: WallEntry) -> String {
        let when = e.daysLeft <= 0 ? "今天开" : "\(e.daysLeft) 天后开"
        if let ua = e.unlockAt { return "\(when) · \(Self.day.string(from: ua))" }
        return when
    }
}

// MARK: - Ombre Brain native panels

private struct OBBucket: Identifiable {
    let id: String
    let name: String
    let type: String
    let domains: [String]
    let tags: [String]
    let preview: String
    let score: Double
    let importance: Int
    let pinned: Bool
    let resolved: Bool
    let digested: Bool
    let forgotten: Bool
    let anchor: Bool
    let created: String
    let lastActive: String

    init(_ row: [String: Any]) {
        id = row.string("id")
        name = row.string("name", "title")
        type = row.string("type")
        domains = row["domain"] as? [String] ?? []
        tags = row["tags"] as? [String] ?? []
        preview = row.string("content_preview")
        score = (row["score"] as? NSNumber)?.doubleValue ?? 0
        importance = row.int("importance")
        pinned = row.bool("pinned")
        resolved = row.bool("resolved")
        digested = row.bool("digested")
        forgotten = row.bool("dont_surface")
        anchor = row.bool("anchor")
        created = row.string("created")
        lastActive = row.string("last_active")
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

private struct PipeLabEvent: Decodable {
    let eventID: Int
    let seq: Int
    let event: String
    let turnID: String
    let delta: String?
    let toolCallID: String?
    let name: String?
    let ok: Bool?
    let labMessageID: String?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id", seq, event, delta, name, ok, reason
        case turnID = "turn_id", toolCallID = "tool_call_id"
        case labMessageID = "lab_message_id"
    }
}

@MainActor private final class PipeLabModel: ObservableObject {
    @Published var state = AlcoveAPI.LiveState()
    @Published var connected = false
    @Published var sending = false
    @Published var notice: String?
    private var streamTask: Task<Void, Never>?
    private var lastEventID = -1

    func connect() {
        guard streamTask == nil else { return }
        streamTask = Task { [weak self] in await self?.consume() }
    }

    func disconnect() {
        streamTask?.cancel()
        streamTask = nil
        connected = false
    }

    func send(_ text: String) async -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !sending, !state.active else { return false }
        sending = true
        defer { sending = false }
        do {
            let result = try await AlcoveAPI.postRaw("/lab/send", body: ["text": clean])
            guard result["ok"] as? Bool != false else { throw URLError(.badServerResponse) }
            notice = nil
            return true
        } catch {
            notice = "实验管道没有接住这句话"
            return false
        }
    }

    private func consume() async {
        var retry: UInt64 = 1_000_000_000
        while !Task.isCancelled {
            do {
                var request = URLRequest(url: AlcoveAPI.fullURL("/stream/lab"))
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                if lastEventID >= 0 {
                    request.setValue(String(lastEventID), forHTTPHeaderField: "Last-Event-ID")
                }
                request.timeoutInterval = 60 * 60
                let (bytes, response) = try await AlcoveAPI.session.bytes(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
                connected = true
                notice = nil
                retry = 1_000_000_000
                for try await line in bytes.lines {
                    guard !Task.isCancelled else { return }
                    guard line.hasPrefix("data:") else { continue }
                    let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    guard let data = payload.data(using: .utf8),
                          let event = try? JSONDecoder().decode(PipeLabEvent.self, from: data),
                          event.eventID > lastEventID else { continue }
                    lastEventID = event.eventID
                    apply(event)
                }
            } catch is CancellationError {
                return
            } catch {
                connected = false
                notice = "实验流正在重连"
                try? await Task.sleep(nanoseconds: retry)
                retry = min(retry * 2, 20_000_000_000)
            }
        }
    }

    private func apply(_ event: PipeLabEvent) {
        if event.event == "start" || state.turnID != event.turnID {
            state = AlcoveAPI.LiveState(active: true, turnID: event.turnID)
        }
        guard event.seq > state.lastSeq else { return }
        state.lastSeq = event.seq
        switch event.event {
        case "start":
            state.active = true
            state.finishing = false
            state.error = nil
        case "thinking_delta":
            let delta = event.delta ?? ""
            state.thinking += delta
            if let i = state.timeline.indices.last, state.timeline[i].kind == "thinking" {
                state.timeline[i].text += delta
            } else if !delta.isEmpty {
                state.timeline.append(.init(id: "lab-thinking-\(event.eventID)",
                                            kind: "thinking", text: delta))
            }
        case "native_thinking_delta":
            // v1.2: archive channel only. The lab deliberately never renders it.
            state.nativeThinking += event.delta ?? ""
        case "text_delta":
            state.say += event.delta ?? ""
        case "tool_start":
            let id = event.toolCallID ?? "lab-tool-\(event.eventID)"
            if !state.tools.contains(where: { $0.id == id }) {
                let name = event.name ?? "执行动作"
                state.tools.append(.init(id: id, name: name))
                state.timeline.append(.init(id: id, kind: "tool", text: name))
            }
        case "tool_done":
            if let id = event.toolCallID, let i = state.tools.firstIndex(where: { $0.id == id }) {
                state.tools[i].done = true; state.tools[i].ok = event.ok
            }
            if let id = event.toolCallID, let i = state.timeline.firstIndex(where: { $0.id == id }) {
                state.timeline[i].done = true; state.timeline[i].ok = event.ok
            }
        case "finish":
            state.active = false
            state.finishing = false
            state.messageID = event.labMessageID
        case "error":
            state.active = false
            state.error = event.reason ?? "实验轮中断"
        default:
            break
        }
    }
}

private struct NativePipeLabView: View {
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @StateObject private var model = PipeLabModel()
    @State private var draft = ""
    @State private var showProcess = true
    @FocusState private var focused: Bool
    private var theme: AlcoveTheme { .panelNamed(themeName) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        if model.state.turnID.isEmpty {
                            ContentUnavailableView("常驻管道实验室", systemImage: "waveform.path.ecg.rectangle",
                                description: Text("这里与正式聊天完全隔离。发一句话，观察思绪、工具与正文怎样实时经过管道。"))
                                .padding(.top, 48)
                        } else {
                            processPanel
                            if !model.state.say.isEmpty {
                                Text(model.state.say)
                                    .font(.system(size: 16))
                                    .lineSpacing(6)
                                    .foregroundColor(theme.text)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .foyerCard(theme)
                            }
                            if let error = model.state.error {
                                Label(error, systemImage: "exclamationmark.triangle")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                            }
                        }
                        Color.clear.frame(height: 1).id("lab-tail")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture { focused = false }
                .onChange(of: model.state.say) { _ in scrollTail(proxy) }
                .onChange(of: model.state.thinking) { _ in scrollTail(proxy) }
            }
            composer
        }
        .task { model.connect() }
        .onDisappear { model.disconnect() }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Circle().fill(model.connected ? Color.green : Color.orange).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pipe Lab").font(.system(size: 18, weight: .semibold, design: .serif))
                Text(model.state.active ? "常驻进程正在回应" : (model.connected ? "实验流已连接" : "正在连接"))
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(theme.textDim)
            }
            Spacer()
            Text("ISOLATED")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.4).foregroundColor(theme.fyAccent)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.fyBorder).frame(height: 0.5) }
    }

    private var processPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { showProcess.toggle() } } label: {
                HStack {
                    Text("ThoughtProcess").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: showProcess ? "chevron.up" : "chevron.down").font(.system(size: 9))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            if showProcess {
                ForEach(model.state.timeline) { item in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: item.icon)
                            .font(.system(size: 11)).frame(width: 16).foregroundColor(theme.fyAccent)
                        Text(item.text)
                            .font(item.kind == "thinking" ? .system(size: 12).italic() : .system(size: 12, weight: .medium))
                            .foregroundColor(theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .foyerCard(theme)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("给实验管道一句话", text: $draft, axis: .vertical)
                .lineLimit(1...5).focused($focused)
                .padding(.horizontal, 13).padding(.vertical, 10)
                .background(theme.fyCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Button {
                let text = draft
                Task { if await model.send(text) { draft = "" } }
            } label: {
                Group {
                    if model.sending { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.up") }
                }
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(theme.fyAccent, in: Circle())
                .foregroundColor(theme.fyCard)
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.sending || model.state.active)
            .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.state.active ? 0.45 : 1)
            .accessibilityLabel("发送到实验管道")
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 12)
        .background(theme.fyCardSub.opacity(0.94))
        .overlay(alignment: .top) { Rectangle().fill(theme.fyBorder).frame(height: 0.5) }
    }

    private func scrollTail(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo("lab-tail", anchor: .bottom) }
    }
}

@MainActor private final class OBMemoryModel: ObservableObject {
    @Published var buckets: [OBBucket] = []
    @Published var loading = false
    @Published var error = ""

    func load() async {
        loading = true; error = ""
        do {
            let rows = try await NativeHouseAPI.array("/api/ob/api/buckets?sort=score")
            buckets = rows.map(OBBucket.init)
        } catch { self.error = "OB 连接失败" }
        loading = false
    }
}

private struct NativeOBMemoryView: View {
    private enum CreationOrder: String, CaseIterable {
        case oldest = "最早创建"
        case newest = "最新创建"
        case combined = "综合创建"
    }

    @StateObject private var model = OBMemoryModel()
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @State private var query = ""
    @State private var filter = "全部"
    @State private var selected: OBBucket?
    @State private var selecting = false
    @State private var checked: Set<String> = []
    @State private var showAnchors = false
    @State private var showNetwork = false
    @State private var creationOrder: CreationOrder = .combined
    private var theme: AlcoveTheme { .panelNamed(themeName) }
    private let filters = ["全部", "钉选", "Feel", "未解决", "已消化", "已遗忘", "归档"]

    private var visible: [OBBucket] {
        let filtered = model.buckets.filter { item in
            let matches: Bool
            switch filter {
            case "钉选": matches = item.pinned
            case "Feel": matches = item.type == "feel"
            case "未解决": matches = !item.resolved && item.type != "permanent" && !item.pinned
            case "已消化": matches = item.digested
            case "已遗忘": matches = item.forgotten
            case "归档": matches = item.type == "archived"
            default: matches = true
            }
            guard matches else { return false }
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return q.isEmpty || ([item.name, item.preview] + item.domains + item.tags)
                .joined(separator: " ").lowercased().contains(q)
        }
        switch creationOrder {
        case .combined:
            // The API's score ordering is OB's existing comprehensive order.
            return filtered
        case .oldest:
            return filtered.enumerated().sorted { lhs, rhs in
                let left = lhs.element.created
                let right = rhs.element.created
                if left.isEmpty != right.isEmpty { return !left.isEmpty }
                if left == right { return lhs.offset < rhs.offset }
                return left < right
            }.map { $0.element }
        case .newest:
            return filtered.enumerated().sorted { lhs, rhs in
                let left = lhs.element.created
                let right = rhs.element.created
                if left.isEmpty != right.isEmpty { return !left.isEmpty }
                if left == right { return lhs.offset < rhs.offset }
                return left > right
            }.map { $0.element }
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            FoyerPanelTitle(title: "Memory", theme: theme)
            HStack(spacing: 8) {
                Button { showAnchors = true } label: { Label("Anchors", systemImage: "scope") }
                Button { showNetwork = true } label: { Label("记忆网络", systemImage: "point.3.connected.trianglepath.dotted") }
                Spacer()
                Button(selecting ? "完成" : "批量") {
                    selecting.toggle(); if !selecting { checked.removeAll() }
                }
            }
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(.plain).foregroundColor(theme.fyAccent)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(theme.textDim)
                TextField("搜索 记忆、标签或正文", text: $query)
                    .font(.system(size: 13))
                Text("\(visible.count)").font(.system(size: 11, design: .monospaced)).foregroundColor(theme.fyAccent)
            }
            .padding(.horizontal, 12).frame(height: 40).foyerCard(theme)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(filters, id: \.self) { value in
                        Button(value) { filter = value }
                            .font(.system(size: 11, weight: filter == value ? .semibold : .regular))
                            .foregroundColor(filter == value ? theme.text : theme.textDim)
                            .padding(.horizontal, 12).frame(height: 31)
                            .background(filter == value ? theme.fyAccentSoft : theme.fyCard, in: Capsule())
                    }
                }
            }
            Picker("创建顺序", selection: $creationOrder) {
                ForEach(CreationOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.segmented)
            if model.loading { Spacer(); ProgressView().tint(theme.fyAccent); Spacer() }
            else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 9) {
                        ForEach(visible) { item in
                            Button {
                                if selecting {
                                    if checked.contains(item.id) { checked.remove(item.id) } else { checked.insert(item.id) }
                                } else { selected = item }
                            } label: { memoryCard(item) }.buttonStyle(.plain)
                        }
                        if visible.isEmpty { Text(model.error.isEmpty ? "没有符合的记忆" : model.error).foregroundColor(theme.textDim).padding(40) }
                    }.padding(.bottom, 18)
                }.refreshable { await model.load() }
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 18).foregroundColor(theme.text)
        .foyerPanel(theme).padding(.horizontal, 12).padding(.top, 8)
        .task { await model.load() }
        .sheet(item: $selected) { item in OBMemoryDetailView(item: item) { await model.load() } }
        .sheet(isPresented: $showAnchors) { OBAnchorsView { await model.load() } }
        .sheet(isPresented: $showNetwork) { OBNetworkView() }
        .safeAreaInset(edge: .bottom) {
            if selecting && !checked.isEmpty {
                HStack(spacing: 10) {
                    Text("已选 \(checked.count)").font(.system(size: 11, design: .monospaced))
                    Spacer()
                    batchButton("遗忘", "forget")
                    batchButton("解决", "resolve")
                    batchButton("归档", "archive")
                }.padding(.horizontal, 16).frame(height: 52)
                    .background(.ultraThinMaterial).foregroundColor(theme.text)
            }
        }
    }

    private func memoryCard(_ item: OBBucket) -> some View {
        HStack(alignment: .top, spacing: 11) {
            if selecting {
                Image(systemName: checked.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(theme.fyAccent)
            }
            Image(systemName: item.pinned ? "pin.fill" : item.type == "feel" ? "drop" : item.resolved ? "moon" : "circle.dotted")
                .font(.system(size: 15, weight: .light)).foregroundColor(theme.fyAccent).frame(width: 22)
            VStack(alignment: .leading, spacing: 7) {
                HStack { Text(item.name).font(.system(size: 14, weight: .semibold)).lineLimit(1); Spacer(); Text(String(format: "%.2f", item.score)).font(.system(size: 10, design: .monospaced)).foregroundColor(theme.fyAccent) }
                if !item.domains.isEmpty { Text(item.domains.joined(separator: " · ")).font(.system(size: 10)).foregroundColor(theme.fyAccent.opacity(0.8)) }
                Text(item.preview).font(.system(size: 12)).foregroundColor(theme.textDim).lineLimit(3).lineSpacing(2)
            }
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading).foyerCard(theme)
    }

    private func batchButton(_ title: String, _ action: String) -> some View {
        Button(title) {
            let ids = Array(checked)
            Task {
                _ = try? await NativeHouseAPI.request("/api/ob/api/buckets/batch", method: "POST", body: ["ids": ids, "action": action])
                checked.removeAll(); selecting = false; await model.load()
            }
        }.font(.system(size: 11, weight: .semibold)).padding(.horizontal, 10).frame(height: 30)
            .background(theme.fyAccentSoft, in: Capsule())
    }
}

private struct OBAnchor: Identifiable {
    let id, name, preview, type: String; let domains, tags: [String]
    init(_ r: [String: Any]) { id=r.string("id"); name=r.string("name"); preview=r.string("preview"); type=r.string("type"); domains=r["domain"] as? [String] ?? []; tags=r["tags"] as? [String] ?? [] }
}

private struct OBAnchorsView: View {
    let didChange: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("alcoveTheme") private var themeName="haven"
    @State private var anchors:[OBAnchor]=[]; @State private var count=0; @State private var limit=24; @State private var error=""
    private var theme:AlcoveTheme{.panelNamed(themeName)}
    var body: some View { NavigationStack {
        ScrollView { LazyVStack(spacing:10) {
            HStack { Text("\(count) / \(limit) 个坐标锚点").font(.system(size:11,design:.monospaced)); Spacer() }.foregroundColor(theme.fyAccent)
            ForEach(anchors) { a in
                VStack(alignment:.leading,spacing:8) {
                    HStack { Image(systemName:"scope"); Text(a.name).font(.system(size:14,weight:.semibold)); Spacer(); Text(a.type).font(.system(size:9,design:.monospaced)) }
                    if !a.domains.isEmpty { Text(a.domains.joined(separator:" · ")).font(.system(size:10)).foregroundColor(theme.fyAccent) }
                    Text(a.preview).font(.system(size:12)).foregroundColor(theme.textDim).lineLimit(4)
                    Button("移出 Anchors", role:.destructive) { Task { _ = try? await NativeHouseAPI.request("/api/ob/api/bucket/\(a.id)/anchor",method:"POST",body:["value":false]); await load(); await didChange() } }.font(.system(size:11))
                }.padding(14).frame(maxWidth:.infinity,alignment:.leading).foyerCard(theme)
            }
            if anchors.isEmpty { Text(error.isEmpty ? "还没有 anchor":"读取失败：\(error)").foregroundColor(theme.textDim).padding(40) }
        }.padding(16) }.background(theme.fyCardSub.ignoresSafeArea()).foregroundColor(theme.text)
            .navigationTitle("Anchors").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.confirmationAction){Button("关闭"){dismiss()}} }.task{await load()}
    }}
    private func load() async { do { let o=try await NativeHouseAPI.object("/api/ob/api/anchors"); anchors=(o["anchors"] as? [[String:Any]] ?? []).map(OBAnchor.init); count=o.int("count"); limit=o.int("limit") } catch { self.error=error.localizedDescription } }
}

private struct OBNetworkNode: Identifiable { let id,label,kind:String; let frequency:Int; let anchor:Bool; let buckets:[String]; init(_ r:[String:Any]){id=r.string("id");label=r.string("label","name");kind=r.string("kind");frequency=r.int("freq");anchor=r.bool("anchor");buckets=r["buckets"] as? [String] ?? []} }
private struct OBNetworkEdge { let source,target:String; let weight:Double; init(_ r:[String:Any]){source=r.string("source");target=r.string("target");weight=(r["weight"] as? NSNumber)?.doubleValue ?? 1} }

private struct OBNetworkView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("alcoveTheme") private var themeName="haven"
    @State private var nodes:[OBNetworkNode]=[]; @State private var edges:[OBNetworkEdge]=[]; @State private var mode="concept"; @State private var selected:OBNetworkNode?
    private var theme:AlcoveTheme{.panelNamed(themeName)}
    var body:some View { NavigationStack { VStack(spacing:10) {
        Picker("模式",selection:$mode){Text("概念").tag("concept");Text("语义").tag("embedding")}.pickerStyle(.segmented).padding(.horizontal,16)
        GeometryReader { geo in
            let positions = layout(size:geo.size)
            ZStack {
                Canvas { ctx,_ in for e in edges { if let a=positions[e.source],let b=positions[e.target] { var p=Path();p.move(to:a);p.addLine(to:b);ctx.stroke(p,with:.color(theme.textDim.opacity(min(0.55,0.12+e.weight*0.09))),lineWidth:max(0.5,min(3,e.weight))) } } }
                ForEach(nodes) { n in if let p=positions[n.id] { Button { selected=n } label:{ Text(n.label).font(.system(size:n.anchor ? 11:9,weight:n.anchor ? .bold:.medium)).lineLimit(1).padding(.horizontal,7).frame(height:24).background(n.anchor ? theme.fyAccentSoft:theme.fyCard,in:Capsule()).overlay(Capsule().stroke(theme.fyAccent.opacity(n.anchor ? 0.8:0.18)))}.buttonStyle(.plain).position(p) } }
            }.clipped()
        }
        Text("\(nodes.count) 个节点 · \(edges.count) 条连接").font(.system(size:10,design:.monospaced)).foregroundColor(theme.textDim).padding(.bottom,12)
    }.padding(.top,10).background(theme.fyCardSub.ignoresSafeArea()).foregroundColor(theme.text).navigationTitle("记忆网络").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.confirmationAction){Button("关闭"){dismiss()}}}.task(id:mode){await load()} }
    .sheet(item:$selected){n in NavigationStack{VStack(alignment:.leading,spacing:14){Text(n.label).font(.system(size:24,weight:.semibold,design:.serif));Text("\(n.kind) · 出现在 \(n.frequency) 条记忆中").foregroundColor(theme.fyAccent);Text(n.buckets.joined(separator:"\n")).font(.system(size:11,design:.monospaced)).foregroundColor(theme.textDim);Spacer()}.padding(22).frame(maxWidth:.infinity,alignment:.leading).background(theme.fyCardSub.ignoresSafeArea()).foregroundColor(theme.text).toolbar{ToolbarItem(placement:.confirmationAction){Button("关闭"){selected=nil}}}}}
    }
    private func load()async{if let o=try? await NativeHouseAPI.object("/api/ob/api/network?mode=\(mode)"){nodes=(o["nodes"] as? [[String:Any]] ?? []).map(OBNetworkNode.init);edges=(o["edges"] as? [[String:Any]] ?? []).map(OBNetworkEdge.init)}}
    private func layout(size:CGSize)->[String:CGPoint]{var out:[String:CGPoint]=[:];let ranked=nodes.sorted{$0.frequency>$1.frequency};let cx=size.width/2,cy=size.height/2;for (i,n) in ranked.enumerated(){if i==0{out[n.id]=CGPoint(x:cx,y:cy);continue};let ring=Double((i-1)/10+1),slot=Double((i-1)%10),angle=slot*(2*Double.pi/10)+ring*0.31;let radius=min(Double(min(size.width,size.height))*0.43,55+ring*55);out[n.id]=CGPoint(x:cx+CGFloat(cos(angle)*radius),y:cy+CGFloat(sin(angle)*radius))};return out}
}

private struct OBMemoryDetailView: View {
    let item: OBBucket
    let didChange: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @State private var detail: [String: Any] = [:]
    @State private var name = ""
    @State private var content = ""
    @State private var tags = ""
    @State private var domains = ""
    @State private var why = ""
    @State private var importance = 5.0
    @State private var saving = false
    private var theme: AlcoveTheme { .panelNamed(themeName) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("标题", text: $name).font(.system(size: 20, weight: .semibold, design: .serif))
                    HStack { Text(item.type.uppercased()); Spacer(); Text("score \(String(format: "%.3f", item.score))") }.font(.system(size: 10, design: .monospaced)).foregroundColor(theme.fyAccent)
                    TextEditor(text: $content).font(.system(size: 13, design: .monospaced)).scrollContentBackground(.hidden).frame(minHeight: 240).padding(8).foyerCard(theme)
                    field("标签（逗号分隔）", $tags); field("领域（逗号分隔）", $domains); field("为什么记得", $why)
                    HStack { Text("重要度"); Slider(value: $importance, in: 1...10, step: 1); Text("\(Int(importance))") }.font(.system(size: 12))
                    actionGrid
                }.padding(18)
            }
            .background(theme.fyCardSub.ignoresSafeArea())
            .foregroundColor(theme.text)
            .navigationTitle("Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(saving ? "保存中" : "保存") { Task { await save() } }.disabled(saving) }
            }
            .task { await load() }
        }
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 10)).foregroundColor(theme.textDim); TextField(title, text: text).font(.system(size: 12)).padding(10).foyerCard(theme) }
    }

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            action(item.pinned ? "取消钉选" : "钉选", "pin", "pin")
            action(item.resolved ? "取消已解决" : "标记已解决", "checkmark.circle", "resolve")
            action(item.forgotten ? "允许浮现" : "主动遗忘", "eye.slash", "forget")
            Button { Task { _ = try? await NativeHouseAPI.request("/api/ob/api/bucket/\(item.id)/anchor", method: "POST", body: ["value": !item.anchor]); await didChange(); dismiss() } } label: {
                Label(item.anchor ? "移出 Anchor" : "加入 Anchor", systemImage: "scope").font(.system(size: 11)).frame(maxWidth: .infinity).padding(11).foyerCard(theme)
            }.buttonStyle(.plain)
            action("归档", "archivebox", "archive")
        }
    }
    private func action(_ title: String, _ icon: String, _ endpoint: String) -> some View {
        Button { Task { try? await NativeHouseAPI.post("/api/ob/api/bucket/\(item.id)/\(endpoint)"); await didChange(); dismiss() } } label: {
            Label(title, systemImage: icon).font(.system(size: 11)).frame(maxWidth: .infinity).padding(11).foyerCard(theme)
        }.buttonStyle(.plain)
    }
    private func load() async {
        guard let d = try? await NativeHouseAPI.object("/api/ob/api/bucket/\(item.id)") else { return }
        detail = d; let m = d.object("metadata")
        name = m.string("name", "title"); content = d.string("content"); tags = (m["tags"] as? [String] ?? []).joined(separator: ", "); domains = (m["domain"] as? [String] ?? []).joined(separator: ", "); why = m.string("why_remembered"); importance = Double(m.int("importance"))
    }
    private func save() async {
        saving = true
        let split: (String) -> [String] = { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        _ = try? await NativeHouseAPI.request("/api/ob/api/bucket/\(item.id)/edit", method: "PATCH", body: ["name": name, "content": content, "tags": split(tags), "domain": split(domains), "why_remembered": why, "importance": Int(importance)])
        await didChange(); saving = false; dismiss()
    }
}

private struct OBLetter: Identifiable {
    let id, author, userName, title, date, content: String
    init(_ r: [String: Any]) { id=r.string("id"); author=r.string("author"); userName=r.string("user_name"); title=r.string("title"); date=r.string("date"); content=r.string("content") }
}

private struct NativeOBLettersView: View {
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @State private var letters: [OBLetter] = []; @State private var filter = ""; @State private var editing: OBLetter?
    private var theme: AlcoveTheme { .panelNamed(themeName) }
    private var shown: [OBLetter] { filter.isEmpty ? letters : letters.filter { $0.author == filter || (filter == "user" && $0.author == "user") } }
    var body: some View {
        VStack(spacing: 10) {
            FoyerPanelTitle(title: "Letters", theme: theme)
            HStack { filterButton("全部", ""); filterButton("陈霁", "user"); filterButton("陈璟", "陈璟"); Spacer(); Button { editing = OBLetter([:]) } label: { Image(systemName: "square.and.pencil") } }
            ScrollView { LazyVStack(spacing: 12) { ForEach(shown) { l in Button { editing=l } label: { letterCard(l) }.buttonStyle(.plain) } }.padding(.bottom,18) }.refreshable { await load() }
        }.padding(.horizontal,16).padding(.bottom,18).foregroundColor(theme.text).foyerPanel(theme).padding(.horizontal,12).padding(.top,8)
        .task { await load() }.sheet(item:$editing) { l in OBLetterEditor(letter:l) { await load() } }
    }
    private func filterButton(_ title:String,_ value:String)->some View { Button(title){filter=value}.font(.system(size:11)).padding(.horizontal,12).frame(height:30).background(filter==value ? theme.fyAccentSoft:theme.fyCard,in:Capsule()) }
    private func letterCard(_ l:OBLetter)->some View { VStack(alignment:.leading,spacing:9){HStack{Label(l.author == "user" ? (l.userName.isEmpty ? "陈霁":l.userName):l.author,systemImage:"envelope").font(.system(size:11,weight:.semibold));Spacer();Text(l.date).font(.system(size:10,design:.monospaced)).foregroundColor(theme.textDim)}; if !l.title.isEmpty {Text(l.title).font(.system(size:17,weight:.semibold,design:.serif))};Text(l.content).font(.system(size:12)).lineSpacing(3).foregroundColor(theme.textDim).lineLimit(6)}.padding(16).frame(maxWidth:.infinity,alignment:.leading).foyerCard(theme) }
    private func load() async { letters = (try? await NativeHouseAPI.array("/api/ob/api/letters",key:"letters"))?.map(OBLetter.init) ?? [] }
}

private struct OBLetterEditor: View {
    let letter:OBLetter; let didChange:() async->Void; @Environment(\.dismiss) private var dismiss
    @State private var author = ""
    @State private var userName = ""
    @State private var title = ""
    @State private var date = ""
    @State private var content = ""
    @AppStorage("alcoveTheme") private var themeName="haven"
    private var theme:AlcoveTheme{.panelNamed(themeName)}
    var body:some View{NavigationStack{Form{Picker("署名",selection:$author){Text("陈霁").tag("user");Text("陈璟").tag("陈璟")};TextField("显示名字",text:$userName);TextField("标题",text:$title);TextField("日期",text:$date);TextEditor(text:$content).frame(minHeight:260);if !letter.id.isEmpty{Button("删除到档案",role:.destructive){Task{_ = try? await NativeHouseAPI.request("/api/ob/api/letter/\(letter.id)?confirm=true",method:"DELETE");await didChange();dismiss()}}}}.scrollContentBackground(.hidden).background(theme.fyCardSub).navigationTitle(letter.id.isEmpty ? "写信":"编辑信").toolbar{ToolbarItem(placement:.cancellationAction){Button("关闭"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("保存"){Task{await save()}}}}.onAppear{author=letter.author.isEmpty ? "user":letter.author;userName=letter.userName;title=letter.title;date=letter.date;content=letter.content}}}
    private func save()async{let body:[String:Any]=["author":author,"user_name":userName,"title":title,"date":date,"content":content];if letter.id.isEmpty{_ = try? await NativeHouseAPI.request("/api/ob/api/letter",method:"POST",body:body)}else{_ = try? await NativeHouseAPI.request("/api/ob/api/letter/\(letter.id)",method:"PATCH",body:body)};await didChange();dismiss()}
}

private struct OBSelfEntry:Identifiable{let id,content,aspect,created:String;init(_ r:[String:Any]){id=r.string("id");content=r.string("content");aspect=r.string("aspect");created=r.string("created")}}
private struct NativeOBSelfView:View{
    @AppStorage("alcoveTheme") private var themeName="haven";@State private var entries:[OBSelfEntry]=[];@State private var aspect=""
    private var theme:AlcoveTheme{.panelNamed(themeName)};private let aspects=["","nature","values","patterns","limits","becoming","uncertainty","stance"]
    private var shown:[OBSelfEntry]{aspect.isEmpty ? entries:entries.filter{$0.aspect==aspect}}
    var body:some View{VStack(spacing:10){FoyerPanelTitle(title:"Self",theme:theme);ScrollView(.horizontal,showsIndicators:false){HStack(spacing:7){ForEach(aspects,id:\.self){a in Button(a.isEmpty ? "全部":a){aspect=a}.font(.system(size:11,design:.monospaced)).padding(.horizontal,11).frame(height:30).background(aspect==a ? theme.fyAccentSoft:theme.fyCard,in:Capsule())}}};ScrollView{LazyVStack(spacing:10){ForEach(shown){e in VStack(alignment:.leading,spacing:8){HStack{Text(e.aspect).font(.system(size:10,weight:.semibold,design:.monospaced)).foregroundColor(theme.fyAccent);Spacer();Text(e.created.prefix(16).replacingOccurrences(of:"T",with:" ")).font(.system(size:9,design:.monospaced)).foregroundColor(theme.textDim)};Text(e.content).font(.system(size:13,design:.serif)).lineSpacing(4)}.padding(15).frame(maxWidth:.infinity,alignment:.leading).foyerCard(theme)}}.padding(.bottom,18)}}.padding(.horizontal,16).padding(.bottom,18).foregroundColor(theme.text).foyerPanel(theme).padding(.horizontal,12).padding(.top,8).task{entries=(try? await NativeHouseAPI.array("/api/ob/api/self"))?.map(OBSelfEntry.init) ?? []}}
}
