import SwiftUI

// 冷蓝玻璃（2026-08-18 檐下先用上，0819 她要搜索和收藏也照这套做）。
//
// 皮的来源是她给的四张参考图（Sui-IB/InternalBeyond-Mobile）：磨砂玻璃、
// 强噪点、光从下面照上来、衬线正文＋等宽元信息。
// 这套配色不进主题引擎，只给用它的那几页；深浅跟着 alcoveTheme 的 isDark 走。
//
// 用它的页面都自己铺满、自己做头——她0819 明说了不要透壁纸、要全屏。

struct GlassPalette {
    let isDark: Bool
    let ink: Color          // 正文
    let ink2: Color         // 次要
    let ink3: Color         // 三级/元信息
    let acc: Color          // 强调蓝
    let gold: Color         // 收了尾的那个金
    let glass: Color        // 玻璃填充
    let line: Color         // 玻璃描边（内高光）
    let bgTop: Color
    let bgMid: Color
    let bgBottom: Color
    let glow: Color         // 底部那团光

    static func named(_ themeName: String) -> GlassPalette {
        AlcoveTheme.named(themeName).isDark ? .dark : .light
    }

    static let light = GlassPalette(
        isDark: false,
        ink: Color(red: 0x0A/255, green: 0x1E/255, blue: 0x42/255),
        ink2: Color(red: 0x3D/255, green: 0x57/255, blue: 0x88/255),
        ink3: Color(red: 0x7D/255, green: 0x92/255, blue: 0xB5/255),
        acc: Color(red: 0x2A/255, green: 0x6B/255, blue: 0xB0/255),
        gold: Color(red: 0xC9/255, green: 0xA8/255, blue: 0x6A/255),
        glass: Color.white.opacity(0.40),
        line: Color.white.opacity(0.74),
        bgTop: Color(red: 0xFA/255, green: 0xFC/255, blue: 0xFE/255),
        bgMid: Color(red: 0xEC/255, green: 0xF1/255, blue: 0xF7/255),
        bgBottom: Color(red: 0xCF/255, green: 0xDA/255, blue: 0xE8/255),
        glow: Color(red: 0x9E/255, green: 0xC2/255, blue: 0xEC/255).opacity(0.42))

    static let dark = GlassPalette(
        isDark: true,
        ink: Color(red: 0xE0/255, green: 0xE6/255, blue: 0xF2/255),
        ink2: Color(red: 0xAD/255, green: 0xB8/255, blue: 0xD0/255),
        ink3: Color(red: 0x7E/255, green: 0x90/255, blue: 0xB2/255),
        acc: Color(red: 0x72/255, green: 0xA8/255, blue: 0xD8/255),
        gold: Color(red: 0xD0/255, green: 0xA4/255, blue: 0x4E/255),
        glass: Color(red: 20/255, green: 28/255, blue: 52/255).opacity(0.46),
        line: Color(red: 165/255, green: 188/255, blue: 230/255).opacity(0.26),
        bgTop: Color(red: 0x4A/255, green: 0x4E/255, blue: 0x56/255),
        bgMid: Color(red: 0x1A/255, green: 0x1D/255, blue: 0x24/255),
        bgBottom: Color(red: 0x12/255, green: 0x1B/255, blue: 0x33/255),
        glow: Color(red: 0x1E/255, green: 0x5F/255, blue: 0xD0/255).opacity(0.55))
}

// MARK: - 噪点（参考图那层胶片颗粒，把渐变的台阶打碎）

struct GlassGrain: View {
    var opacity: Double = 0.055
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> Double {
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                return Double(seed % 1000) / 1000.0
            }
            let step: CGFloat = 2
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let v = next()
                    if v > 0.55 {
                        context.fill(
                            Path(CGRect(x: x, y: y, width: step, height: step)),
                            with: .color(.white.opacity(v * 0.5)))
                    } else if v < 0.16 {
                        context.fill(
                            Path(CGRect(x: x, y: y, width: step, height: step)),
                            with: .color(.black.opacity(0.35)))
                    }
                    x += step
                }
                y += step
            }
        }
        .opacity(opacity)
        .blendMode(.overlay)
        .allowsHitTesting(false)
    }
}

// MARK: - 整页背景：光从下面照上来

struct GlassBackdrop: View {
    let palette: GlassPalette
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [palette.bgTop, palette.bgMid, palette.bgBottom],
                startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [palette.glow, .clear],
                center: UnitPoint(x: 0.5, y: 1.05),
                startRadius: 10, endRadius: 420)
            GlassGrain(opacity: palette.isDark ? 0.05 : 0.075)
        }
        .ignoresSafeArea()
    }
}

// MARK: - 玻璃卡

struct GlassCard: ViewModifier {
    let palette: GlassPalette
    var radius: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(palette.glass))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(palette.line, lineWidth: 0.7))
                    .shadow(color: palette.isDark
                            ? Color.black.opacity(0.32)
                            : Color(red: 90/255, green: 120/255, blue: 170/255).opacity(0.14),
                            radius: 12, y: 5))
    }
}

extension View {
    func glassCard(_ palette: GlassPalette, radius: CGFloat = 18) -> some View {
        modifier(GlassCard(palette: palette, radius: radius))
    }
}

// MARK: - 玻璃珠头像（参考图里那颗蓝珠子，纯代码画，不吃图片资源）

struct GlassBead: View {
    let isHers: Bool
    var size: CGFloat = 38

    private var core: Color {
        isHers
            ? Color(red: 0xE8/255, green: 0xC6/255, blue: 0xD2/255)   // 她：暖粉珠
            : Color(red: 0x3C/255, green: 0x74/255, blue: 0xC8/255)   // 我：蓝珠
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [core.opacity(0.30), core, core.opacity(0.72)],
                        center: UnitPoint(x: 0.34, y: 0.28),
                        startRadius: size * 0.04,
                        endRadius: size * 0.72))
            // 底部反光：光从下面照上来，跟整页光源一致
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(isHers ? 0.55 : 0.42), .clear],
                        center: UnitPoint(x: 0.62, y: 0.86),
                        startRadius: 0,
                        endRadius: size * 0.42))
            Ellipse()
                .fill(Color.white.opacity(0.72))
                .frame(width: size * 0.34, height: size * 0.22)
                .offset(x: -size * 0.13, y: -size * 0.26)
                .blur(radius: size * 0.045)
            Circle().strokeBorder(Color.white.opacity(0.42), lineWidth: 0.6)
        }
        .frame(width: size, height: size)
        .shadow(color: core.opacity(0.35), radius: size * 0.16, y: size * 0.08)
    }
}

// MARK: - 全屏页面的顶栏（她0819：不要透壁纸，要全屏）

struct GlassHeader: View {
    let title: String
    let palette: GlassPalette
    var onBack: () -> Void
    var switchTitle: String? = nil
    var onSwitch: (() -> Void)? = nil
    var trailing: AnyView? = nil

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 18, weight: .medium, design: .serif))
                .tracking(7)
                .foregroundColor(palette.ink)
                .padding(.leading, 7)   // 抵掉字距在右边多出来的那一格
            HStack(spacing: 0) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .light))
                        .foregroundColor(palette.ink2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")
                Spacer()
                if let switchTitle, let onSwitch {
                    Button(action: onSwitch) {
                        Text(switchTitle)
                            .font(.system(size: 12.5, weight: .medium, design: .serif))
                            .tracking(1.4)
                            .foregroundColor(palette.ink3)
                            .frame(minWidth: 76, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if let trailing {
                    trailing.frame(width: 44, height: 44)
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 54)
    }
}

// MARK: - 筛选胶囊（搜索框下面那排选项）

struct GlassChips<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    let palette: GlassPalette
    var onPick: (T) -> Void = { _ in }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(options, id: \.0) { value, label in
                    let on = selection == value
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) { selection = value }
                        onPick(value)
                    } label: {
                        Text(label)
                            .font(.system(size: 12.5, weight: on ? .semibold : .regular,
                                          design: .serif))
                            .tracking(1.2)
                            .foregroundColor(on ? palette.ink : palette.ink3)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(on ? palette.glass : Color.clear)
                                    .overlay(Capsule().strokeBorder(
                                        on ? palette.line : Color.clear, lineWidth: 0.7)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - 自动换行的标签墙（0819 情绪标要"多一点"，单行横滚看不全）

struct FlowLayout: Layout {
    var spacing: CGFloat = 7
    var lineSpacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - 0902 悬浮小卡（微信通话那种）：每个悬浮件一扇刚好一样大的小窗
//
// 陈霁 0902 定的：通话页能缩小成胶囊、一起听能缩成小唱片，吸在屏幕边上，拖着走，点一下展开。
//
// ‼️第一版是一层全屏透明窗 + 悬浮件自己上报"我在哪块"、窗只在那块接触摸。
// 当天晚上就出事：她录了条语音之后整颗唱片对触摸失灵，重启才好——上报那条链路
// 只要漏掉一次，悬浮件就变成一张看得见摸不着的贴纸。她说"不想以后再遇到"。
// 现在改成**每个悬浮件自己一扇窗，窗的大小就是内容的大小**：手指落在窗里就是落在
// 悬浮件上，窗外面自然归底下的页面，没有任何"猜哪块该接"的环节。拖的时候是整扇窗
// 在挪（UIKit 的 pan，按屏幕坐标算，不受窗自己移动的影响），松手窗吸到最近的边。
// 内容变大变小（唱片长按展开成长条）→ 窗跟着改尺寸，贴着原来那条边。
//
// 用法：FloatingOverlay.shared.show(id: "call", defaultY: 120) { 你的内容 }
//       FloatingOverlay.shared.hide(id: "call")
//       FloatingOverlay.shared.present { 任何 SwiftUI 页 }   // 从 app 最上面那页弹 sheet，
//                                                            // 盖在共读室/工作室之上也不顶掉谁

@MainActor
final class FloatingOverlay {
    static let shared = FloatingOverlay()
    private var windows: [String: FloatingItemWindow] = [:]

    func show<V: View>(id: String, defaultY: CGFloat = 120, @ViewBuilder content: () -> V) {
        let body = AnyView(content())
        if let w = windows[id] {
            w.update(content: body)
            w.isHidden = false
            return
        }
        let w = FloatingItemWindow(itemID: id, defaultY: defaultY, content: body)
        windows[id] = w
        w.isHidden = false
    }

    func hide(id: String) {
        guard let w = windows.removeValue(forKey: id) else { return }
        w.isHidden = true
        w.rootViewController = nil
    }

    func isShowing(_ id: String) -> Bool { windows[id] != nil }

    /// app 的主窗（不是我们这些小窗）
    static func appWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { !($0 is FloatingItemWindow) && $0.isKeyWindow }
        ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { !($0 is FloatingItemWindow) }
    }

    /// 从主窗最上面那个正在展示的页面弹一个 sheet。共读室/工作室是 fullScreenCover，
    /// 从它们的头上弹，才不会把它们顶掉（0902 她抓的「点唱片工作室就退出」）。
    func present<V: View>(fraction: CGFloat = 0.75, @ViewBuilder content: () -> V) {
        guard let win = Self.appWindow(), var top = win.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        let host = UIHostingController(rootView: content())
        host.modalPresentationStyle = .pageSheet
        host.view.backgroundColor = .clear
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.custom { ctx in ctx.maximumDetentValue * fraction }]
            sheet.prefersGrabberVisible = true
        }
        top.present(host, animated: true)
    }
}

/// 一扇刚好包住内容的小窗。永远在最上面（alert 之上），拖、吸边、记位置都是它自己的事。
final class FloatingItemWindow: UIWindow {
    let itemID: String
    private let defaultY: CGFloat
    private var host: UIHostingController<FloatingItemRoot>!
    private var contentSize = CGSize(width: 62, height: 62)
    private var grabOffset: CGPoint = .zero
    private let margin: CGFloat = 10

    private var sideKey: String { "float.\(itemID).side" }
    private var yKey: String { "float.\(itemID).y" }

    init(itemID: String, defaultY: CGFloat, content: AnyView) {
        self.itemID = itemID
        self.defaultY = defaultY
        // 跟 AppDelegate 一个起法：这个 app 没有 SceneDelegate，UIWindow(frame:) 自己挂到主场景
        super.init(frame: CGRect(x: 0, y: defaultY, width: 62, height: 62))
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            windowScene = scene
        }
        windowLevel = .alert + 1
        backgroundColor = .clear
        let root = FloatingItemRoot(content: content) { [weak self] size in self?.resize(to: size) }
        host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        rootViewController = host
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        if itemID == "call" {
            // Own the call pill's gestures at the window, rather than competing
            // with the hosted SwiftUI button. A drag must never restore the call.
            pan.cancelsTouchesInView = true
            addGestureRecognizer(pan)
            let tap = UITapGestureRecognizer(target: self, action: #selector(restoreCall))
            tap.require(toFail: pan)
            addGestureRecognizer(tap)
        } else {
            pan.cancelsTouchesInView = false
            host.view.addGestureRecognizer(pan)
        }
        place(animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(content: AnyView) {
        host.rootView = FloatingItemRoot(content: content) { [weak self] size in self?.resize(to: size) }
    }

    // MARK: 尺寸 / 位置

    /// 别叫 screen——UIWindow 自带一个 screen: UIScreen，撞名编译不过（0902 构建报的）
    private var screenBounds: CGRect { UIScreen.main.bounds }
    private var safe: UIEdgeInsets { FloatingOverlay.appWindow()?.safeAreaInsets ?? .zero }

    /// 内容变了尺寸：窗跟着变，贴着原来那条边
    private func resize(to size: CGSize) {
        guard size.width > 1, size.height > 1, size != contentSize else { return }
        contentSize = size
        place(animated: true)
    }

    /// 按记住的边和高度摆好
    private func place(animated: Bool) {
        let side = UserDefaults.standard.string(forKey: sideKey) ?? "right"
        let savedY = UserDefaults.standard.double(forKey: yKey)
        let y = savedY > 0 ? CGFloat(savedY) : defaultY
        let target = snapped(CGPoint(x: side == "left" ? 0 : screenBounds.width, y: y + contentSize.height / 2))
        setCenter(target, animated: animated)
    }

    /// 吸到最近的左/右边，上下别出安全区。传入和返回的都是**中心点**（屏幕坐标）
    private func snapped(_ c: CGPoint) -> CGPoint {
        let halfW = contentSize.width / 2, halfH = contentSize.height / 2
        let x = c.x < screenBounds.width / 2 ? margin + halfW : screenBounds.width - margin - halfW
        let minY = safe.top + margin + halfH
        let maxY = screenBounds.height - safe.bottom - margin - halfH
        return CGPoint(x: x, y: min(max(c.y, minY), max(minY, maxY)))
    }

    private func setCenter(_ c: CGPoint, animated: Bool) {
        let f = CGRect(x: c.x - contentSize.width / 2, y: c.y - contentSize.height / 2,
                       width: contentSize.width, height: contentSize.height)
        if animated {
            UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.82,
                           initialSpringVelocity: 0.4) { self.frame = f }
        } else {
            frame = f
        }
    }

    // MARK: 拖

    @objc private func restoreCall() {
        guard itemID == "call" else { return }
        NotificationCenter.default.post(name: .alcoveCallRestore, object: nil)
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        // 手指的屏幕坐标：窗自己在动，所以不能用窗坐标
        let inWindow = g.location(in: nil)
        let p = coordinateSpace.convert(inWindow, to: UIScreen.main.coordinateSpace)
        switch g.state {
        case .began:
            grabOffset = CGPoint(x: p.x - frame.midX, y: p.y - frame.midY)
        case .changed:
            let c = CGPoint(x: p.x - grabOffset.x, y: p.y - grabOffset.y)
            setCenter(c, animated: false)
        case .ended, .cancelled:
            let c = snapped(CGPoint(x: frame.midX, y: frame.midY))
            setCenter(c, animated: true)
            UserDefaults.standard.set(c.x < screenBounds.width / 2 ? "left" : "right", forKey: sideKey)
            UserDefaults.standard.set(Double(c.y - contentSize.height / 2), forKey: yKey)
        default: break
        }
    }
}

/// 小窗里的根视图：内容按它自己的天然尺寸摆，量出来告诉窗
struct FloatingItemRoot: View {
    let content: AnyView
    let onSize: (CGSize) -> Void

    var body: some View {
        content
            .fixedSize()
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { onSize(g.size) }
                    .onChange(of: g.size) { onSize($0) }
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
    }
}
