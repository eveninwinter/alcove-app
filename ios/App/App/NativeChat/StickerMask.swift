import SwiftUI
import UIKit

// 1016 她：「我要做这个」——miya-tonya/sticker-mask（MIT, © 2026 Miya）贴纸打码，原生重写，只放主聊天，入口在加号里。
// 截图前把贴纸盖在要遮的地方：拖＝挪，角上把手＝缩放＋旋转，边上小胶囊＝单独拉宽 / 拉高，×＝删这一张，双指捏＝缩放＋旋转。
// 点「完成」右边那列和所有框、把手都消失，直接系统截图。贴纸只在本机内存里，不发到任何地方。
// 跟网页版一样跟着消息走（她 #3917「要跟网页一起走啊」）：每张贴纸认在它盖住的那条消息上，记离那条消息左上角多远，
// 列表滚到哪它跟到哪；落在顶栏 / 输入栏那一截的钉在屏幕上不动。
// 演示素材（两种胶带、两种星星）是仓库作者 AI 生成、说明可随意用的；她自己的从相册加（透明底 PNG 直接能用）。

/// 盖在屏幕上的一张贴纸
struct MaskSticker: Identifiable, Equatable {
    let id = UUID()
    var assetID: String
    /// 认在哪条消息上（ChatMessage.id）；nil＝钉在屏幕上
    var anchor: String?
    /// anchor 有：贴纸中心离那条消息左上角多远；anchor 没有：贴纸中心的屏幕坐标
    var offset: CGPoint
    var w: CGFloat
    var h: CGFloat
    /// 弧度
    var r: Double
}

/// 右边那列里的一张素材：内置的（素材库图名）或她从相册加的（Documents/MaskStickers 里的 png）
struct MaskStickerAsset: Identifiable {
    let id: String
    let builtin: Bool
    let image: UIImage
}

/// 消息行的位置（全局坐标）。行自己报、只有贴纸层盯着它，聊天列表不订阅，免得一滚就整页重算
final class StickerMaskFrames: ObservableObject {
    static let shared = StickerMaskFrames()
    private(set) var frames: [String: CGRect] = [:]

    func set(_ id: String, _ rect: CGRect) {
        frames[id] = rect
        if StickerMaskStore.shared.active { objectWillChange.send() }
    }

    func remove(_ id: String) {
        frames[id] = nil
        if StickerMaskStore.shared.active { objectWillChange.send() }
    }
}

/// 聊天页每条消息套这个：把自己在屏幕上的位置报给贴纸层
struct StickerMaskAnchor: ViewModifier {
    let id: String
    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { StickerMaskFrames.shared.set(id, $0) }
            .onDisappear { StickerMaskFrames.shared.remove(id) }
    }
}

final class StickerMaskStore: ObservableObject {
    static let shared = StickerMaskStore()

    static let baseWidth: CGFloat = 96
    static let minWidth: CGFloat = 32       // 初始的三分之一（照原作）
    static let maxWidth: CGFloat = 640
    static let minEdge: CGFloat = 16        // 单独拉宽 / 拉高最窄到这
    static let stretchHandleMinEdge: CGFloat = 56   // 边比这短就藏起边上的小胶囊（会和角把手叠在一起）

    // 1016 #3919 她：「先把我们有的那几张放进去吧」——Sanctus 素材库里能盖得住东西的六张（透明边裁掉了）；
    // 数字星星、seen this Angel 那两张太淡太透，盖不住字，没放
    private static let builtins = ["MaskTapePink", "MaskTapeBlue", "MaskStarPink", "MaskStarBlue",
                                   "MaskLocket", "MaskRabbit", "MaskFairies", "MaskNotes", "MaskWing", "MaskButterfly"]
    private static let userKey = "maskStickerUserAssets"        // 她加的素材文件名，按加进来的顺序
    private static let hiddenKey = "maskStickerHiddenBuiltins"  // 她删掉的内置素材

    /// 贴纸层在不在（在编辑，或者完成了但屏幕上还有贴纸）
    @Published var active = false
    /// 编辑中：右边那列、虚线框、把手都在
    @Published var editing = false
    @Published var stickers: [MaskSticker] = []
    @Published var selected: UUID?
    @Published private(set) var assets: [MaskStickerAsset] = []
    private var loaded = false

    private static var userDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MaskStickers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 加号里「贴纸打码」
    func enter() {
        if !loaded { reloadAssets() }
        active = true
        editing = true
    }

    /// 「完成」：框和把手全收起来，只剩贴纸；一张都没有就整层撤掉
    func done() {
        editing = false
        selected = nil
        if stickers.isEmpty { active = false }
    }

    func clear() {
        stickers.removeAll()
        selected = nil
    }

    func remove(_ id: UUID) {
        stickers.removeAll { $0.id == id }
        if selected == id { selected = nil }
    }

    func image(for assetID: String) -> UIImage? {
        assets.first { $0.id == assetID }?.image ?? Self.loadImage(assetID)
    }

    /// 点素材：放到屏幕正中（连着放几张错开一点），跟原作一样宽 96、高按图的比例
    func add(_ asset: MaskStickerAsset, center: CGPoint) {
        let n = stickers.count
        let c = CGPoint(x: center.x + CGFloat(n % 3 - 1) * 24, y: center.y + CGFloat((n / 3) % 3 - 1) * 24)
        let ratio = asset.image.size.width > 0 ? asset.image.size.height / asset.image.size.width : 1
        var s = MaskSticker(assetID: asset.id, anchor: nil, offset: c,
                            w: Self.baseWidth, h: Self.baseWidth * ratio, r: 0)
        settle(&s, screenCenter: c)
        stickers.append(s)
        selected = s.id
    }

    /// 贴纸此刻的中心（贴纸层坐标）；认的那条消息不在屏幕上（懒加载收掉了）就是 nil，不画
    func center(of s: MaskSticker, layerOrigin: CGPoint) -> CGPoint? {
        guard let anchor = s.anchor else { return s.offset }
        guard let f = StickerMaskFrames.shared.frames[anchor] else { return nil }
        return CGPoint(x: f.minX - layerOrigin.x + s.offset.x, y: f.minY - layerOrigin.y + s.offset.y)
    }

    /// 放手以后重新认消息：中心落在哪条消息上就认哪条；落在两条之间认最近那条；
    /// 顶栏 / 输入栏那一截（pinTop 以上、pinBottom 以下）钉在屏幕上
    var pinTop: CGFloat = 140
    var pinBottom: CGFloat = 10_000
    var layerOrigin: CGPoint = .zero

    func settle(_ s: inout MaskSticker, screenCenter c: CGPoint) {
        if c.y < pinTop || c.y > pinBottom {
            s.anchor = nil
            s.offset = c
            return
        }
        let global = CGPoint(x: c.x + layerOrigin.x, y: c.y + layerOrigin.y)
        var best: (String, CGRect, CGFloat)?
        for (id, f) in StickerMaskFrames.shared.frames {
            let d: CGFloat = global.y < f.minY ? f.minY - global.y : (global.y > f.maxY ? global.y - f.maxY : 0)
            if best == nil || d < best!.2 { best = (id, f, d) }
        }
        if case let (id, f, _)? = best {
            s.anchor = id
            s.offset = CGPoint(x: global.x - f.minX, y: global.y - f.minY)
        } else {
            s.anchor = nil
            s.offset = c
        }
    }

    func update(_ id: UUID, _ change: (inout MaskSticker) -> Void) {
        guard let i = stickers.firstIndex(where: { $0.id == id }) else { return }
        change(&stickers[i])
    }

    /// 挪到最上面一层（选中谁谁在上）
    func lift(_ id: UUID) {
        guard let i = stickers.firstIndex(where: { $0.id == id }), i != stickers.count - 1 else { return }
        let s = stickers.remove(at: i)
        stickers.append(s)
    }

    // MARK: 素材

    func reloadAssets() {
        loaded = true
        let hidden = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? [])
        var out: [MaskStickerAsset] = []
        for name in Self.builtins where !hidden.contains(name) {
            if let img = UIImage(named: name) { out.append(MaskStickerAsset(id: name, builtin: true, image: img)) }
        }
        for file in UserDefaults.standard.stringArray(forKey: Self.userKey) ?? [] {
            if let img = Self.loadImage(file) { out.append(MaskStickerAsset(id: file, builtin: false, image: img)) }
        }
        assets = out
    }

    private static func loadImage(_ id: String) -> UIImage? {
        if builtins.contains(id) { return UIImage(named: id) }
        return UIImage(contentsOfFile: userDir.appendingPathComponent(id).path)
    }

    /// 从相册加：最长边缩到 800，存成 png（透明底保住）
    func addFromLibrary(_ images: [UIImage]) {
        var files = UserDefaults.standard.stringArray(forKey: Self.userKey) ?? []
        for img in images {
            let scaled = Self.downscale(img, maxSide: 800)
            guard let data = scaled.pngData() else { continue }
            let name = UUID().uuidString + ".png"
            do {
                try data.write(to: Self.userDir.appendingPathComponent(name), options: .atomic)
                files.append(name)
            } catch { continue }
        }
        UserDefaults.standard.set(files, forKey: Self.userKey)
        reloadAssets()
    }

    /// 长按素材删：她加的连文件一起删；内置的记进隐藏名单（不删包里的图）。已经贴在屏幕上的那几张一起撤掉
    func deleteAsset(_ asset: MaskStickerAsset) {
        if asset.builtin {
            var hidden = UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? []
            if !hidden.contains(asset.id) { hidden.append(asset.id) }
            UserDefaults.standard.set(hidden, forKey: Self.hiddenKey)
        } else {
            var files = UserDefaults.standard.stringArray(forKey: Self.userKey) ?? []
            files.removeAll { $0 == asset.id }
            UserDefaults.standard.set(files, forKey: Self.userKey)
            try? FileManager.default.removeItem(at: Self.userDir.appendingPathComponent(asset.id))
        }
        stickers.removeAll { $0.assetID == asset.id }
        if let sel = selected, !stickers.contains(where: { $0.id == sel }) { selected = nil }
        reloadAssets()
    }

    /// 内置的删掉了想要回来
    var hasHiddenBuiltins: Bool { !(UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? []).isEmpty }

    func restoreBuiltins() {
        UserDefaults.standard.removeObject(forKey: Self.hiddenKey)
        reloadAssets()
    }

    private static func downscale(_ img: UIImage, maxSide: CGFloat) -> UIImage {
        let w = img.size.width * img.scale, h = img.size.height * img.scale
        let k = min(1, maxSide / max(w, h, 1))
        let size = CGSize(width: max(1, (w * k).rounded()), height: max(1, (h * k).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// 盖在整个聊天页上的那一层（RootView 里挂在顶栏上面）：贴纸 ＋ 编辑时右边那列
struct StickerMaskLayer: View {
    @ObservedObject private var store = StickerMaskStore.shared
    @ObservedObject private var frames = StickerMaskFrames.shared
    /// 顶栏多高（顶栏这一截落下的贴纸钉住不动）
    var topBarHeight: CGFloat = 84
    @State private var showPicker = false
    @State private var confirmClear = false

    private static let accent = Color(red: 0x0B / 255, green: 0x1B / 255, blue: 0xFF / 255)

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            ZStack(alignment: .topLeading) {
                ForEach(store.stickers) { s in
                    if let c = store.center(of: s, layerOrigin: origin), let img = store.image(for: s.assetID) {
                        StickerMaskItem(sticker: s, image: img, center: c,
                                        editing: store.editing, selected: store.selected == s.id,
                                        accent: Self.accent)
                    }
                }
                if store.editing {
                    palette(geo)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .coordinateSpace(name: "stickerMask")
            .onAppear { syncGeometry(geo) }
            .onChange(of: geo.size) { _ in syncGeometry(geo) }
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.2), value: store.editing)
        .sheet(isPresented: $showPicker) {
            PhotoLibraryPicker(maxCount: 9) { images in store.addFromLibrary(images) }
        }
    }

    // 整层 ignoresSafeArea，量出来的安全区是 0；问 app 主窗（全屏房间的老规矩）
    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0 }
    private var safeBottom: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.bottom ?? 0 }

    private func syncGeometry(_ geo: GeometryProxy) {
        store.layerOrigin = geo.frame(in: .global).origin
        store.pinTop = safeTop + topBarHeight
        store.pinBottom = geo.size.height - safeBottom - 64
    }

    /// 右边那列：素材（点＝放一张，长按＝删）、从相册加、全清、完成
    @ViewBuilder private func palette(_ geo: GeometryProxy) -> some View {
        let top = safeTop + topBarHeight + 8
        let bottom = safeBottom + 90
        let height = max(160, geo.size.height - top - bottom)
        let center = CGPoint(x: geo.size.width / 2 - 20, y: geo.size.height / 2)
        VStack(spacing: 10) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(store.assets) { a in
                        Image(uiImage: a.image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                            .padding(4)
                            .contentShape(Rectangle())
                            .onTapGesture { store.add(a, center: center) }
                            .contextMenu {
                                Button(role: .destructive) { store.deleteAsset(a) } label: {
                                    Label("删掉这张", systemImage: "trash")
                                }
                            }
                    }
                    Button { showPicker = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .light))
                            .frame(width: 44, height: 44)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("从相册加贴纸")
                    .contextMenu {
                        if store.hasHiddenBuiltins {
                            Button { store.restoreBuiltins() } label: { Label("找回删掉的自带贴纸", systemImage: "arrow.uturn.backward") }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            Divider().frame(width: 30)
            if confirmClear {
                Button {
                    store.clear()
                    confirmClear = false
                } label: {
                    Text("全清").font(.system(size: 12, weight: .medium)).foregroundColor(.red)
                        .frame(width: 44, height: 32)
                }
                .buttonStyle(.plain)
            } else {
                Button { confirmClear = true } label: {
                    Image(systemName: "trash").font(.system(size: 15, weight: .light)).frame(width: 44, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("全部清掉")
                .disabled(store.stickers.isEmpty)
            }
            Button {
                confirmClear = false
                store.done()
            } label: {
                Text("完成")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 32)
                    .background(Capsule().fill(Color.primary.opacity(0.85)))
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(.primary)
        .padding(.vertical, 10)
        .frame(width: 64)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .frame(height: height)
        .position(x: geo.size.width - 12 - 32, y: top + height / 2)
        .onChange(of: store.stickers.count) { _ in confirmClear = false }
    }
}

/// 一张贴纸：图 ＋（编辑时）虚线框；选中了实线框 ＋ 角上把手、×、两条边上的小胶囊
private struct StickerMaskItem: View {
    let sticker: MaskSticker
    let image: UIImage
    let center: CGPoint
    let editing: Bool
    let selected: Bool
    let accent: Color

    @State private var dragStart: CGPoint?
    @State private var pinchBase: (w: CGFloat, h: CGFloat, r: Double)?
    @State private var handleBase: (c: CGPoint, len: CGFloat, ang: Double, w: CGFloat, h: CGFloat, r: Double)?
    @State private var stretchBase: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, c: CGPoint)?

    private var store: StickerMaskStore { .shared }

    var body: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(width: sticker.w, height: sticker.h)
                .shadow(color: .black.opacity(0.14), radius: 1, y: 1)
            if editing {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(accent.opacity(selected ? 0.9 : 0.55),
                            style: StrokeStyle(lineWidth: 1, dash: selected ? [] : [4, 3]))
                    .frame(width: sticker.w + 8, height: sticker.h + 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: sticker.w, height: sticker.h)
        .contentShape(Rectangle())
        .gesture(moveGesture)
        .simultaneousGesture(pinchGesture)
        .onTapGesture { if editing { store.selected = selected ? nil : sticker.id; store.lift(sticker.id) } }
        .overlay { if editing && selected { handles } }
        .rotationEffect(.radians(sticker.r))
        .position(center)
        .allowsHitTesting(editing)
    }

    // MARK: 把手

    @ViewBuilder private var handles: some View {
        ZStack {
            // 角上：缩放 ＋ 旋转（右下）
            Circle().fill(accent)
                .overlay(Circle().stroke(.white, lineWidth: 1.2))
                .overlay(Image(systemName: "arrow.clockwise").font(.system(size: 8, weight: .bold)).foregroundColor(.white))
                .frame(width: 18, height: 18)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
                .position(x: sticker.w + 4, y: sticker.h + 4)
                .gesture(cornerGesture)
            // ×（右上）
            Circle().fill(.white)
                .overlay(Circle().stroke(accent, lineWidth: 1.2))
                .overlay(Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundColor(accent))
                .frame(width: 18, height: 18)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
                .position(x: sticker.w + 4, y: -4)
                .onTapGesture { store.remove(sticker.id) }
            // 右边：单独拉宽
            if sticker.h >= StickerMaskStore.stretchHandleMinEdge {
                Capsule().fill(accent)
                    .overlay(Capsule().stroke(.white, lineWidth: 1))
                    .frame(width: 5, height: 16)
                    .frame(width: 30, height: 34)
                    .contentShape(Rectangle())
                    .position(x: sticker.w + 4, y: sticker.h / 2)
                    .gesture(stretchGesture(axisX: true))
            }
            // 下边：单独拉高
            if sticker.w >= StickerMaskStore.stretchHandleMinEdge {
                Capsule().fill(accent)
                    .overlay(Capsule().stroke(.white, lineWidth: 1))
                    .frame(width: 16, height: 5)
                    .frame(width: 34, height: 30)
                    .contentShape(Rectangle())
                    .position(x: sticker.w / 2, y: sticker.h + 4)
                    .gesture(stretchGesture(axisX: false))
            }
        }
        .frame(width: sticker.w, height: sticker.h)
    }

    // MARK: 手势（坐标一律用贴纸层的 stickerMask 空间，跟旋转无关）

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("stickerMask"))
            .onChanged { v in
                if dragStart == nil {
                    dragStart = center
                    store.selected = sticker.id
                    store.lift(sticker.id)
                }
                guard let start = dragStart else { return }
                let c = CGPoint(x: start.x + v.translation.width, y: start.y + v.translation.height)
                store.update(sticker.id) { $0.anchor = nil; $0.offset = c }
            }
            .onEnded { _ in
                dragStart = nil
                settle()
            }
    }

    private var pinchGesture: some Gesture {
        SimultaneousGesture(MagnifyGesture(), RotateGesture())
            .onChanged { v in
                if pinchBase == nil {
                    pinchBase = (sticker.w, sticker.h, sticker.r)
                    store.selected = sticker.id
                }
                guard let base = pinchBase else { return }
                let k = clampScale(v.first?.magnification ?? 1, w: base.w, h: base.h)
                let rot = v.second?.rotation.radians ?? 0
                store.update(sticker.id) {
                    $0.w = base.w * k
                    $0.h = base.h * k
                    $0.r = base.r + rot
                }
            }
            .onEnded { _ in pinchBase = nil }
    }

    private var cornerGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("stickerMask"))
            .onChanged { v in
                if handleBase == nil {
                    let vx = v.startLocation.x - center.x, vy = v.startLocation.y - center.y
                    handleBase = (center, hypot(vx, vy), atan2(Double(vy), Double(vx)), sticker.w, sticker.h, sticker.r)
                    store.lift(sticker.id)
                }
                guard let b = handleBase, b.len > 0 else { return }
                let vx = v.location.x - b.c.x, vy = v.location.y - b.c.y
                let len = hypot(vx, vy)
                guard len > 0 else { return }
                let k = clampScale(len / b.len, w: b.w, h: b.h)
                store.update(sticker.id) {
                    $0.w = b.w * k
                    $0.h = b.h * k
                    $0.r = b.r + (atan2(Double(vy), Double(vx)) - b.ang)
                }
            }
            .onEnded { _ in
                handleBase = nil
                settle()
            }
    }

    /// 拉一条边：对边不动（中心顺着贴纸自己那根轴挪一半）
    private func stretchGesture(axisX: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("stickerMask"))
            .onChanged { v in
                let r = sticker.r
                let ux = axisX ? cos(r) : -sin(r)
                let uy = axisX ? sin(r) : cos(r)
                if stretchBase == nil {
                    stretchBase = (CGFloat(ux), CGFloat(uy), sticker.w, sticker.h, center)
                    store.lift(sticker.id)
                }
                guard let b = stretchBase else { return }
                let d = v.translation.width * b.x + v.translation.height * b.y
                let base = axisX ? b.w : b.h
                let maxV = axisX ? StickerMaskStore.maxWidth : StickerMaskStore.maxWidth * 2
                let value = min(maxV, max(StickerMaskStore.minEdge, base + d))
                let shift = (value - base) / 2
                let c = CGPoint(x: b.c.x + shift * b.x, y: b.c.y + shift * b.y)
                store.update(sticker.id) {
                    if axisX { $0.w = value } else { $0.h = value }
                    $0.anchor = nil
                    $0.offset = c
                }
            }
            .onEnded { _ in
                stretchBase = nil
                settle()
            }
    }

    private func clampScale(_ k: CGFloat, w: CGFloat, h: CGFloat) -> CGFloat {
        let lo = max(StickerMaskStore.minWidth / max(w, 1), StickerMaskStore.minEdge / max(min(w, h), 1))
        let hi = StickerMaskStore.maxWidth / max(w, 1)
        return min(max(k, lo), max(hi, lo))
    }

    /// 放手：按此刻在屏幕上的位置重新认消息（或者钉住）
    private func settle() {
        guard let s = store.stickers.first(where: { $0.id == sticker.id }) else { return }
        let c = store.center(of: s, layerOrigin: store.layerOrigin) ?? center
        store.update(sticker.id) { store.settle(&$0, screenCenter: c) }
    }
}
