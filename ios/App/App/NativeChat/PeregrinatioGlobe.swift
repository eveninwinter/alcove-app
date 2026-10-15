import SwiftUI
import SceneKit
import UIKit
import simd

// MARK: - 1015 远游 · 地球（#3879）
// 她点头的样子：/root/workroom/mock/peregrinatio/page2.html（白天）、page_night.html（黑夜），出图脚本 globe2.py / globe_night.py。
// - 球面贴图（海、陆、海岸线、经纬线、雾）是服务器按他的足迹画的：/root/rhysel/peregrinatio_globe.py，每交完一趟重画。
// - 这里画的：光（左上主光、右下阴影、背光一侧边缘一圈白光，写在 shader 里照效果图的公式，光跟着镜头不跟球转）、
//   球外的柔光、落脚点、最近九次远跳的拱形虚线、意犹未尽的细圈、几处坐标小字。
// - 正交相机：跟效果图一样是正投影，球半径占视图边长 47%（效果图 1000 见方、半径 470）。
// - 拖动转（北永远朝上），两指放大，点一个点 → 回邮册抽出那一趟。白天黑夜跟全屋按钮。
// 数据：前门 /api/nowhere/peregrinatio/globe 和 /globe/{day|night}.jpg?v=版本（/root/rhysel/peregrinatio_api.py）。

struct PGGlobePlace: Decodable, Hashable { let trip: Int; let name: String; let lat: Double; let lon: Double; let day: String; let at: String? }
/// i：到达那一站在 places 里的下标（时间滑条拖到那儿才画）
struct PGGlobeHop: Decodable, Hashable { let from: [Double]; let to: [Double]; let km: Int; let i: Int? }
struct PGGlobeNamedLat: Decodable, Hashable { let name: String; let lat: Double }
struct PGGlobeFar: Decodable, Hashable { let name: String; let km: Int }
struct PGGlobeStats: Decodable, Hashable { let km: Int; let laps: Double; let north: PGGlobeNamedLat; let south: PGGlobeNamedLat; let far: PGGlobeFar }
struct PGGlobeLatest: Decodable, Hashable {
    let trip: Int; let title: String; let place: String; let start: String; let end: String
    let stops: Int; let km: Double; let hero: String; let open: Bool
}
struct PGGlobeNow: Decodable, Hashable { let name: String; let lat: Double; let lon: Double }
struct PGGlobeLinger: Decodable, Hashable { let id: Int; let trip: Int; let lat: Double; let lon: Double; let question: String }
struct PGGlobeLabel: Decodable, Hashable { let name: String; let lat: Double; let lon: Double }
struct PGGlobeCenter: Decodable, Hashable { let lat: Double; let lon: Double }
struct PGGlobeCounts: Decodable, Hashable { let places: Int; let postcards: Int }
struct PGGlobeData: Decodable, Equatable {
    let version: String
    let center: PGGlobeCenter
    let places: [PGGlobePlace]
    let hops: [PGGlobeHop]
    let lingers: [PGGlobeLinger]
    let labels: [PGGlobeLabel]
    let counts: PGGlobeCounts
    let stats: PGGlobeStats?
    let latest: PGGlobeLatest?
    let now: PGGlobeNow?
}

extension PGAPI {
    static func globe() async -> PGGlobeData? {
        guard let o = try? await NativeHouseAPI.object("/api/nowhere/peregrinatio/globe") else { return nil }
        return decode(o, as: PGGlobeData.self)
    }
    static func globeTextureURL(dark: Bool, version: String) -> URL {
        AlcoveAPI.fullURL("/api/nowhere/peregrinatio/globe/\(dark ? "night" : "day").jpg?v=\(version)")
    }
}

/// 地球页的颜色：照 globe2.py / globe_night.py / page*.html 原样抄
private struct PGGlobeInk {
    let dark: Bool
    static func c(_ r: Int, _ g: Int, _ b: Int, _ a: Double = 1) -> UIColor {
        UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a))
    }
    /// 白天用水彩纸色（她 1015 定的远游底色）；黑夜照效果图近黑
    var bg: Color { dark ? Color(Self.c(17, 18, 21)) : Color(Self.c(241, 242, 244)) }
    var title: Color { dark ? Color(Self.c(216, 220, 228)) : Color(Self.c(62, 64, 72)) }
    var kicker: Color { dark ? Color(Self.c(139, 143, 153)) : Color(Self.c(154, 158, 168)) }
    var sub: Color { dark ? Color(Self.c(139, 143, 153)) : Color(Self.c(154, 158, 168)) }
    var hint: Color { Color(Self.c(154, 158, 168)) }
    var link: Color { dark ? Color(Self.c(163, 167, 176)) : Color(Self.c(125, 129, 140)) }
    var arc: UIColor { dark ? Self.c(210, 216, 228, 150.0 / 255) : Self.c(96, 100, 110, 150.0 / 255) }
    var ring: (UIColor, UIColor) {
        dark ? (Self.c(210, 216, 228, 150.0 / 255), Self.c(210, 216, 228, 80.0 / 255))
             : (Self.c(96, 100, 110, 150.0 / 255), Self.c(96, 100, 110, 80.0 / 255))
    }
    var leader: UIColor { dark ? Self.c(180, 186, 198, 120.0 / 255) : Self.c(120, 124, 134, 140.0 / 255) }
    var coord: UIColor { dark ? Self.c(196, 202, 214, 230.0 / 255) : Self.c(110, 114, 124, 230.0 / 255) }
    var place: UIColor { dark ? Self.c(150, 156, 168, 230.0 / 255) : Self.c(140, 144, 154, 230.0 / 255) }
    var fog: UIColor { dark ? Self.c(30, 31, 36) : Self.c(244, 245, 248) }
}

// MARK: 页面

struct PGGlobePage: View {
    /// 点了一个地方：回邮册抽出这一趟
    let onPick: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    @State private var data: PGGlobeData?
    @State private var texture: UIImage?
    @State private var failed = false
    /// 时间滑条：nil＝全部（拖到头），否则只显示 places[0...timeIdx]
    @State private var timeIdx: Int?

    private var dark: Bool { _ = houseAppearance; return AlcoveAppearance.isDark }

    var body: some View {
        let ink = PGGlobeInk(dark: dark)
        // 1015 #3888 她：「我是 iOS 全屏，你上下那么多空干嘛」——GeometryReader 本来就在安全区里面，原来又加了一遍 safeTop。
        // #3889 她：字太小、空的地方舒展一下；旅行数字、最近一趟、时间滑条、他正在哪「全都做你试一下」。
        // 从上到下：标题（返回键同一行）→ 他正在哪 → 旅行数字 → 地球 → 时间滑条 → 最近一趟 → 图例和提示。
        GeometryReader { geo in
            let k = geo.size.width / 942
            // 地球照效果图 1000 见方；屏幕矮的手机让一让，别把下面挤出去
            let side = max(240, min(1000 * k, geo.size.height - 352 - (data?.now == nil ? 0 : 22)))
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Text("Peregrinatio").font(PGFont.script(34)).foregroundColor(ink.title)
                    Text("远游 · \(data?.counts.places ?? 0) PLACES · \(data?.counts.postcards ?? 0) POSTCARDS")
                        .font(PGFont.corm(11)).tracking(2.6).foregroundColor(ink.kicker)
                        .padding(.top, 6)
                        .opacity(data == nil ? 0 : 1)
                    if let now = data?.now {
                        Text("he is in \(now.name) now").font(PGFont.ital(14)).foregroundColor(ink.title)
                            .padding(.top, 6)
                    }
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .regular)).foregroundColor(ink.link)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 8)
                }
                .padding(.top, 6)
                if let st = data?.stats { statsRow(st, ink: ink).padding(.top, 16).padding(.horizontal, 18) }
                Spacer(minLength: 0)
                ZStack {
                    if let data {
                        PGGlobeSCN(data: data, texture: texture, dark: dark, timeIdx: timeIdx) { trip in
                            dismiss()
                            onPick(trip)
                        }
                    } else if failed {
                        Text("地球还没画好，过一会儿再来").font(PGFont.ital(14)).foregroundColor(ink.sub)
                    }
                }
                .frame(width: side, height: side)
                .frame(width: geo.size.width)
                Spacer(minLength: 0)
                if let data, data.places.count > 1 { timeSlider(data, ink: ink).padding(.horizontal, 30) }
                if let l = data?.latest { latestCard(l, ink: ink).padding(.horizontal, 22).padding(.top, 14) }
                legend(ink).padding(.top, 16)
                Text("拖动转一转 · 两指放大看地名 · 点一个地方看那天")
                    .font(.system(size: 11, design: .serif)).tracking(1.6).foregroundColor(ink.hint)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
            }
        }
        .background {
            ZStack {
                ink.bg
                if dark { PGStars() }
            }
            .ignoresSafeArea()
        }
        .task {
            if let d = await PGAPI.globe() { data = d } else { failed = true }
        }
        // 贴图跟版本和深浅走：换了才重新拿（磁盘有缓存）
        .task(id: "\(data?.version ?? "")-\(dark)") {
            guard let v = data?.version, !v.isEmpty else { return }
            texture = await ImageDiskCache.shared.image(for: PGAPI.globeTextureURL(dark: dark, version: v))
        }
    }

    /// 旅行数字：像护照内页，大数字＋小号说明，四格细竖线隔开
    private func statsRow(_ st: PGGlobeStats, ink: PGGlobeInk) -> some View {
        func cell(_ big: String, _ unit: String, _ cap: String) -> some View {
            VStack(spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(big).font(PGFont.corm(22)).foregroundColor(ink.title)
                    if !unit.isEmpty { Text(unit).font(PGFont.ital(11)).foregroundColor(ink.sub) }
                }
                .lineLimit(1).minimumScaleFactor(0.7)
                Text(cap).font(.system(size: 10, design: .serif)).foregroundColor(ink.sub)
                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        let km = NumberFormatter.localizedString(from: NSNumber(value: st.km), number: .decimal)
        let far = NumberFormatter.localizedString(from: NSNumber(value: st.far.km), number: .decimal)
        let lat = { (v: Double) in String(format: "%.0f°%@", abs(v), v >= 0 ? "N" : "S") }
        return HStack(spacing: 0) {
            cell(km, "km", "一共走了\n约 \(String(format: "%.0f", st.laps)) 圈地球")
            sep(ink)
            cell(lat(st.north.lat), "", "最北\n\(st.north.name)")
            sep(ink)
            cell(lat(st.south.lat), "", "最南\n\(st.south.name)")
            sep(ink)
            cell(far, "km", "离家最远\n\(st.far.name)")
        }
    }

    private func sep(_ ink: PGGlobeInk) -> some View {
        Rectangle().fill(ink.sub.opacity(0.35)).frame(width: 0.6, height: 30)
    }

    /// 时间滑条：从他第一次出门拖到今天，足迹一个个亮起来、航线一段段画出来；拖到头＝全部
    private func timeSlider(_ d: PGGlobeData, ink: PGGlobeInk) -> some View {
        let n = d.places.count
        let idx = timeIdx ?? (n - 1)
        let cur = d.places[min(max(idx, 0), n - 1)]
        return VStack(spacing: 4) {
            HStack {
                Text(d.places.first?.day ?? "").font(PGFont.ital(11)).foregroundColor(ink.sub)
                Spacer()
                Text(timeIdx == nil ? "today" : "\(cur.day) · \(cur.name)")
                    .font(PGFont.ital(12)).foregroundColor(ink.title).lineLimit(1)
                Spacer()
                Text(d.places.last?.day ?? "").font(PGFont.ital(11)).foregroundColor(ink.sub)
            }
            GeometryReader { g in
                let w = g.size.width
                let x = n > 1 ? CGFloat(idx) / CGFloat(n - 1) * w : w
                ZStack(alignment: .leading) {
                    Capsule().fill(ink.sub.opacity(0.3)).frame(height: 1)
                    Capsule().fill(ink.title.opacity(0.7)).frame(width: x, height: 1)
                    Circle().fill(ink.title).frame(width: 9, height: 9)
                        .background(Circle().fill(ink.bg).frame(width: 15, height: 15))
                        .offset(x: x - 4.5)
                }
                .frame(height: 22)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let i = Int((min(max(v.location.x / max(w, 1), 0), 1) * CGFloat(n - 1)).rounded())
                    timeIdx = i >= n - 1 ? nil : i
                })
            }
            .frame(height: 22)
        }
    }

    /// 最近一趟：左边那一趟的照片（白边小邮票），右边标题、日期、几站、走了多远；点了回邮册抽出那一枚
    private func latestCard(_ l: PGGlobeLatest, ink: PGGlobeInk) -> some View {
        Button {
            dismiss()
            onPick(l.trip)
        } label: {
            HStack(spacing: 14) {
                CachedImage(url: PGAPI.imageURL(l.hero)) { img in
                    img.resizable().scaledToFill()
                } placeholder: { Color.gray.opacity(0.15) }
                .frame(width: 48, height: 56).clipped()
                .padding(4).background(Color.white)
                .shadow(color: .black.opacity(0.12), radius: 1.5, x: 0, y: 1)
                .opacity(dark ? 0.85 : 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(l.open ? "正在路上 · ON THE ROAD" : "最近一趟 · LATEST").font(PGFont.corm(10)).tracking(2).foregroundColor(ink.kicker)
                    Text(l.title.isEmpty ? l.place : l.title).font(PGFont.ital(18)).foregroundColor(ink.title).lineLimit(1)
                    Text("\(l.place) · \(l.start)\(l.end.isEmpty || l.end == l.start ? "" : " — " + l.end) · \(l.stops) 站 · \(String(format: l.km >= 100 ? "%.0f" : "%.1f", l.km)) km")
                        .font(.system(size: 12, design: .serif)).foregroundColor(ink.sub).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(ink.sub)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(dark ? Color.white.opacity(0.04) : Color.white.opacity(0.7))
            .overlay(Rectangle().stroke(ink.sub.opacity(0.35), lineWidth: 0.6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func legend(_ ink: PGGlobeInk) -> some View {
        HStack(spacing: 24) {
            HStack(spacing: 7) {
                Circle().fill(dark ? Color(PGGlobeInk.c(245, 247, 251)) : Color(PGGlobeInk.c(62, 64, 72)))
                    .frame(width: 6, height: 6)
                    .padding(2)
                    .background(Circle().fill(dark ? Color(PGGlobeInk.c(225, 232, 245, 0.25)) : .white))
                Text("where he stood")
            }
            HStack(spacing: 6) {
                Circle().stroke(dark ? Color(PGGlobeInk.c(210, 216, 228, 0.6)) : Color(PGGlobeInk.c(150, 154, 164, 0.6)), lineWidth: 1)
                    .frame(width: 11, height: 11)
                Text("not done yet")
            }
        }
        .font(PGFont.ital(13))
        .foregroundColor(ink.sub)
    }
}

/// 黑夜的底上零星几颗很暗的星（效果图：千分之 0.7 的像素、亮度随机）
private struct PGStars: View {
    var body: some View {
        Canvas { ctx, size in
            var rng = PGSeeded(seed: 11)
            let n = Int(size.width * size.height * 0.004)
            for _ in 0..<n {
                let x = rng.next() * size.width, y = rng.next() * size.height
                let a = rng.next() * 0.47
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 0.6, height: 0.6)), with: .color(.white.opacity(a)))
            }
        }
        .allowsHitTesting(false)
    }
}

private struct PGSeeded {
    var s: UInt64
    init(seed: UInt64) { s = seed &* 0x9E3779B97F4A7C15 }
    mutating func next() -> CGFloat {
        s ^= s << 13; s ^= s >> 7; s ^= s << 17
        return CGFloat(s % 1_000_000) / 1_000_000
    }
}

// MARK: SceneKit

private struct PGGlobeSCN: UIViewRepresentable {
    let data: PGGlobeData
    let texture: UIImage?
    let dark: Bool
    var timeIdx: Int?
    let onPick: (Int) -> Void

    func makeCoordinator() -> PGGlobeController { PGGlobeController() }
    func makeUIView(context: Context) -> SCNView { context.coordinator.makeView() }
    func updateUIView(_ v: SCNView, context: Context) {
        let c = context.coordinator
        c.onPick = onPick
        c.apply(data: data, texture: texture, dark: dark)
        c.setTime(timeIdx)
    }
}

final class PGGlobeController: NSObject, UIGestureRecognizerDelegate {
    /// 效果图：球图 1000 见方、半径 470 → 正交相机半高 = 500/470
    static let baseScale: Double = 500.0 / 470.0
    /// 效果图里 1 像素合多少球面单位（球半径 = 1）
    static let px: CGFloat = 1.0 / 470.0

    let scene = SCNScene()
    private let cameraNode = SCNNode()
    private let globe = SCNNode()          // 跟着转：球、点、弧、圈、字
    private let sphere = SCNNode()
    private let marks = SCNNode()
    private let halo = SCNNode()           // 球外柔光，不跟着转
    private weak var view: SCNView?
    var onPick: ((Int) -> Void)?

    private var built: (version: String, dark: Bool)?
    private weak var texSet: UIImage?
    private var centerLat: Float = 26 * .pi / 180
    private var centerLon: Float = 70 * .pi / 180
    private var zoom: Float = 1
    private var pinchStart: Float = 1
    private var velocity = SIMD2<Float>(0, 0)
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0

    private enum Kind { case dot(trip: Int), ring, label, name }
    /// w：地名那种字条在效果图像素里有多宽（算挤不挤）；t：这一处在 places 里最早的下标（时间滑条用，-1＝跟时间无关）
    private struct Mark { let node: SCNNode; let pos: SIMD3<Float>; let kind: Kind; var w: CGFloat = 0; var t: Int = -1 }
    private var markList: [Mark] = []
    private var arcs: [(node: SCNNode, t: Int)] = []
    private var places: [PGGlobePlace] = []
    /// 时间滑条：nil＝全部
    private var timeIdx: Int?
    /// 跟着时间滑条转过去的目标（纬度、经度，弧度）
    private var follow: SIMD2<Float>?
    /// 坐标小字、地名在效果图字号上再放大这么多（她 #3889：字太小）
    static let labelScale: Float = 1.3

    func makeView() -> SCNView {
        let v = SCNView(frame: .zero)
        v.scene = scene
        // 1015 #3888 她截图里地球背后一整块白方块：SCNView 默认白底，三处都要清掉才透明
        v.backgroundColor = .clear
        v.isOpaque = false
        scene.background.contents = UIColor.clear
        v.antialiasingMode = .multisampling4X
        v.allowsCameraControl = false
        v.isJitteringEnabled = false

        let cam = SCNCamera()
        cam.usesOrthographicProjection = true
        cam.orthographicScale = Self.baseScale
        cam.zNear = 0.1
        cam.zFar = 20
        cameraNode.camera = cam
        cameraNode.position = SCNVector3(0, 0, 5)
        scene.rootNode.addChildNode(cameraNode)
        v.pointOfView = cameraNode

        scene.rootNode.addChildNode(halo)
        scene.rootNode.addChildNode(globe)
        sphere.geometry = Self.sphereGeometry()
        globe.addChildNode(sphere)
        globe.addChildNode(marks)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
        pan.delegate = self; pinch.delegate = self
        [pan, pinch, tap].forEach { v.addGestureRecognizer($0) }
        view = v
        return v
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }

    func apply(data: PGGlobeData, texture: UIImage?, dark: Bool) {
        if built?.version != data.version || built?.dark != dark {
            let first = built == nil
            built = (data.version, dark)
            if first {
                centerLat = Float(data.center.lat) * .pi / 180
                centerLon = Float(data.center.lon) * .pi / 180
            }
            sphere.geometry?.firstMaterial = Self.globeMaterial(dark: dark, texture: texture)
            texSet = texture
            halo.geometry = Self.haloPlane(dark: dark)
            halo.position = SCNVector3(0, 0, -3)
            halo.renderingOrder = -10
            buildMarks(data, ink: PGGlobeInk(dark: dark))
            updatePose()
        } else if texture !== texSet {
            texSet = texture
            sphere.geometry?.firstMaterial?.diffuse.contents = texture ?? PGGlobeInk(dark: dark).fog
        }
    }

    // MARK: 球

    static func unit(_ latDeg: Double, _ lonDeg: Double) -> SIMD3<Float> {
        let la = Float(latDeg * .pi / 180), lo = Float(lonDeg * .pi / 180)
        return SIMD3(cos(la) * sin(lo), sin(la), cos(la) * cos(lo))
    }

    /// 自己拼的球：经度 0 朝镜头（+Z），东经朝右（+X），北朝上（+Y）；贴图等距投影，u 从西经 180 到东经 180，v 从北到南
    static func sphereGeometry(segLon: Int = 180, segLat: Int = 90) -> SCNGeometry {
        var pos: [SCNVector3] = [], uv: [CGPoint] = []
        pos.reserveCapacity((segLon + 1) * (segLat + 1)); uv.reserveCapacity(pos.capacity)
        for j in 0...segLat {
            let lat = 90.0 - Double(j) / Double(segLat) * 180
            for i in 0...segLon {
                let lon = -180.0 + Double(i) / Double(segLon) * 360
                let p = unit(lat, lon)
                pos.append(SCNVector3(p.x, p.y, p.z))
                uv.append(CGPoint(x: Double(i) / Double(segLon), y: Double(j) / Double(segLat)))
            }
        }
        var idx: [UInt32] = []
        idx.reserveCapacity(segLon * segLat * 6)
        let row = UInt32(segLon + 1)
        for j in 0..<UInt32(segLat) {
            for i in 0..<UInt32(segLon) {
                let a = j * row + i, b = a + row
                idx += [a, b, a + 1, a + 1, b, b + 1]
            }
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(normals: pos), SCNGeometrySource(textureCoordinates: uv)],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        return g
    }

    /// 光照照 globe2.py / globe_night.py 的公式原样写：法线在相机空间，xy 就是效果图里的屏幕坐标（正投影）。
    /// 效果图是在 sRGB 里算的，SceneKit 在线性空间里，先转回 sRGB 算完再转回去。
    static let lightShader = """
    #pragma arguments
    float pgNight;
    #pragma body
    float3 n = normalize(_surface.normal);
    float3 c = pow(clamp(_output.color.rgb, 0.0, 1.0), float3(1.0 / 2.2));
    float3 L = normalize(float3(-0.55, 0.55, 0.63));
    float nd = clamp(dot(n, L), -1.0, 1.0);
    float lit = 0.62 + 0.38 * pow(clamp(nd * 0.5 + 0.5, 0.0, 1.0), 1.4);
    float k = clamp(1.0 - lit, 0.0, 1.0) * 1.6;
    float3 sh = mix(float3(170.0, 175.0, 186.0), float3(14.0, 15.0, 18.0), pgNight) / 255.0;
    c = c * (1.0 - k) + sh * k;
    float rho = clamp(length(n.xy), 0.0, 1.0);
    float rimD = pow(clamp(rho - 0.82, 0.0, 1.0) / 0.18, 2.2) * clamp(-(n.x * 0.3 + n.y) * 0.9 + 0.4, 0.0, 1.0);
    float rimN = pow(clamp(rho - 0.80, 0.0, 1.0) / 0.20, 2.0) * clamp(-(n.x * 0.25 + n.y) * 1.1 + 0.2, 0.0, 1.0);
    c = mix(c, float3(1.0), rimD * 0.7 * (1.0 - pgNight));
    c = mix(c, float3(236.0, 240.0, 248.0) / 255.0, rimN * 0.85 * pgNight);
    _output.color = float4(pow(clamp(c, 0.0, 1.0), float3(2.2)), 1.0);
    """

    static func globeMaterial(dark: Bool, texture: UIImage?) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = texture ?? PGGlobeInk(dark: dark).fog
        m.diffuse.mipFilter = .linear
        m.diffuse.minificationFilter = .linear
        m.diffuse.magnificationFilter = .linear
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .clamp
        m.shaderModifiers = [.fragment: lightShader]
        m.setValue(NSNumber(value: dark ? 1.0 : 0.0), forKey: "pgNight")
        return m
    }

    /// 球外一圈柔光（效果图 halo 0.09 + halo2 0.35；黑夜只亮背光那一侧）
    static func haloPlane(dark: Bool) -> SCNGeometry {
        let reach: CGFloat = 1.7, n = 512
        var px = [UInt8](repeating: 0, count: n * n * 4)
        let (cr, cg, cb): (Double, Double, Double) = dark ? (200, 206, 220) : (255, 255, 255)
        for yy in 0..<n {
            for xx in 0..<n {
                let x = (Double(xx) + 0.5) / Double(n) * 2 * Double(reach) - Double(reach)
                let y = Double(reach) - (Double(yy) + 0.5) / Double(n) * 2 * Double(reach)
                let rho = (x * x + y * y).squareRoot()
                guard rho > 1 else { continue }
                let h1 = exp(-pow((rho - 1) / 0.09, 2)), h2 = exp(-pow((rho - 1) / 0.35, 2))
                var a: Double
                if dark {
                    let glow = min(max(-(x * 0.25 + y) * 1.1 + 0.2, 0), 1)
                    a = (0.55 * h1 + 0.30 * h2) * (0.25 + 0.75 * glow)
                } else {
                    a = 0.75 * h1 + 0.35 * h2
                }
                a = min(max(a, 0), 1)
                let o = (yy * n + xx) * 4
                px[o] = UInt8(cr * a); px[o + 1] = UInt8(cg * a); px[o + 2] = UInt8(cb * a); px[o + 3] = UInt8(255 * a)
            }
        }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let img = px.withUnsafeMutableBytes { buf -> CGImage? in
            CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        let plane = SCNPlane(width: reach * 2, height: reach * 2)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = img
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false
        m.blendMode = .alpha
        plane.firstMaterial = m
        return plane
    }

    // MARK: 点、弧、圈、字

    private func buildMarks(_ d: PGGlobeData, ink: PGGlobeInk) {
        marks.childNodes.forEach { $0.removeFromParentNode() }
        markList = []
        arcs = []
        places = d.places

        // 远跳：从球面拱起来的虚线弧（效果图：最近九次、120 步、三步一段隔一段、线宽 2 像素）
        for h in d.hops where h.from.count == 2 && h.to.count == 2 {
            let a = Self.unit(h.from[0], h.from[1]), b = Self.unit(h.to[0], h.to[1])
            let om = acos(min(max(simd_dot(a, b), -1), 1))
            guard om > 0.001 else { continue }
            let hmax = Float(min(0.32, 0.05 + Double(h.km) / 40000))
            let arc = SCNNode()
            var prev: SIMD3<Float>?
            for i in 0...120 {
                let t = Float(i) / 120
                let dir = (sin((1 - t) * om) * a + sin(t * om) * b) / sin(om)
                let p = simd_normalize(dir) * (1 + hmax * sin(.pi * t))
                if let q = prev, (i / 3) % 2 == 0 { arc.addChildNode(Self.dash(q, p, color: ink.arc)) }
                prev = p
            }
            let flat = arc.flattenedClone()
            marks.addChildNode(flat)
            arcs.append((flat, h.i ?? 0))
        }

        // 落脚点
        let dotImg = Self.dotImage(dark: ink.dark)
        for (i, p) in d.places.enumerated() {
            let u = Self.unit(p.lat, p.lon)
            let n = Self.billboard(dotImg, sizePx: 28, at: u * 1.002, order: 20)
            marks.addChildNode(n)
            markList.append(Mark(node: n, pos: u, kind: .dot(trip: p.trip), t: i))
        }
        // 他正在路上：那个点外面一圈光一下一下往外散
        if let now = d.now {
            let u = Self.unit(now.lat, now.lon)
            let n = SCNNode()
            n.simdPosition = u * 1.002
            let pulse = Self.billboard(Self.ringImage((ink.ring.0, .clear)), sizePx: 50, at: .zero, order: 21)
            pulse.constraints = nil
            n.constraints = [SCNBillboardConstraint()]
            n.addChildNode(pulse)
            pulse.runAction(.repeatForever(.sequence([
                .group([.scale(to: 1.8, duration: 1.4), .fadeOut(duration: 1.4)]),
                .run { $0.simdScale = SIMD3(repeating: 1); $0.opacity = 1 },
            ])))
            marks.addChildNode(n)
            markList.append(Mark(node: n, pos: u, kind: .ring))
        }
        // 意犹未尽：两道细圈
        let ringImg = Self.ringImage(ink.ring)
        for l in d.lingers {
            let u = Self.unit(l.lat, l.lon)
            let n = Self.billboard(ringImg, sizePx: 50, at: u * 1.002, order: 19)
            marks.addChildNode(n)
            markList.append(Mark(node: n, pos: u, kind: .ring))
        }
        // 坐标小字：默认写在点的右上；北边 15° 以内已经有一处字了，这处就写到右下，两处一上一下错开
        // （原来按从北到南一上一下交替，宫之浦和富士山挨着，一个往下一个往上正好撞在一起）
        var placed: [SIMD3<Float>] = []
        for l in d.labels.sorted(by: { $0.lat > $1.lat }) {
            let u = Self.unit(l.lat, l.lon)
            let crowded = placed.contains { simd_dot($0, u) > cos(Float(15) * .pi / 180) }
            placed.append(u)
            let n = labelNode(l, up: !crowded, ink: ink, at: u * 1.002)
            marks.addChildNode(n)
            markList.append(Mark(node: n, pos: u, kind: .label))
        }
        // 地名：放大以后像地图那样显示（她 #3888），最近去的优先，挤的地方只留一个；已经有坐标小字的不重复写
        var named = Set(d.labels.map(\.name))
        var first: [String: Int] = [:]
        for (i, p) in d.places.enumerated() where first[p.name] == nil { first[p.name] = i }
        for p in d.places.reversed() where !p.name.isEmpty && !named.contains(p.name) {
            named.insert(p.name)
            let u = Self.unit(p.lat, p.lon)
            let (n, w) = nameNode(p.name, ink: ink, at: u * 1.002)
            marks.addChildNode(n)
            markList.append(Mark(node: n, pos: u, kind: .name, w: w, t: first[p.name] ?? 0))
        }
    }

    private static func dash(_ a: SIMD3<Float>, _ b: SIMD3<Float>, color: UIColor) -> SCNNode {
        let len = simd_length(b - a)
        let cyl = SCNCylinder(radius: px, height: CGFloat(len))
        cyl.radialSegmentCount = 6
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.writesToDepthBuffer = false
        m.blendMode = .alpha
        cyl.firstMaterial = m
        let n = SCNNode(geometry: cyl)
        n.simdPosition = (a + b) / 2
        n.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(b - a))
        n.renderingOrder = 5
        return n
    }

    private static func billboard(_ img: UIImage, sizePx: CGFloat, at p: SIMD3<Float>, order: Int) -> SCNNode {
        let plane = SCNPlane(width: sizePx * px, height: sizePx * px)
        plane.firstMaterial = flatMaterial(img)
        let n = SCNNode(geometry: plane)
        n.simdPosition = p
        n.constraints = [SCNBillboardConstraint()]
        n.renderingOrder = order
        return n
    }

    private static func flatMaterial(_ img: UIImage) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = img
        m.readsFromDepthBuffer = false   // 背面的自己按位置藏（效果图：Z ≤ 0.02 不画）
        m.writesToDepthBuffer = false
        m.blendMode = .alpha
        return m
    }

    /// 效果图白天：白底圈 r7（不透明度 170）＋深点 r3.6；黑夜：三层光晕 r14/9/6＋白点 r3.4
    private static func dotImage(dark: Bool) -> UIImage {
        draw(CGSize(width: 28, height: 28)) { ctx in
            let c = CGPoint(x: 14, y: 14)
            func disc(_ r: CGFloat, _ col: UIColor) { col.setFill(); ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
            if dark {
                disc(14, PGGlobeInk.c(225, 232, 245, 22.0 / 255))
                disc(9, PGGlobeInk.c(225, 232, 245, 45.0 / 255))
                disc(6, PGGlobeInk.c(225, 232, 245, 90.0 / 255))
                disc(3.4, PGGlobeInk.c(250, 252, 255))
            } else {
                disc(7, PGGlobeInk.c(255, 255, 255, 170.0 / 255))
                disc(3.6, PGGlobeInk.c(52, 54, 62, 240.0 / 255))
            }
        }
    }

    /// 效果图：r15（不透明度 150）、r23（80），线宽 2
    private static func ringImage(_ cols: (UIColor, UIColor)) -> UIImage {
        draw(CGSize(width: 50, height: 50)) { ctx in
            ctx.setLineWidth(2)
            for (r, col) in [(CGFloat(15), cols.0), (CGFloat(23), cols.1)] {
                col.setStroke()
                ctx.strokeEllipse(in: CGRect(x: 25 - r, y: 25 - r, width: r * 2, height: r * 2))
            }
        }
    }

    /// 坐标小字（效果图：引线＋Cormorant 斜体 22「35.23°N  139.59°E」＋地名 19，字在点右边 28 像素，上排 -44 / 下排 +6）
    private func labelNode(_ l: PGGlobeLabel, up: Bool, ink: PGGlobeInk, at p: SIMD3<Float>) -> SCNNode {
        let coordFont = UIFont(name: "CormorantGaramondItalic-MediumItalic", size: 22) ?? .italicSystemFont(ofSize: 22)
        let nameFont = UIFont(name: "STSongti-SC-Regular", size: 19)
            ?? UIFont.systemFont(ofSize: 19).fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: 19) }
            ?? .systemFont(ofSize: 19)
        let coord = String(format: "%.2f°%@  %.2f°%@", abs(l.lat), l.lat >= 0 ? "N" : "S", abs(l.lon), l.lon >= 0 ? "E" : "W")
        let a1: [NSAttributedString.Key: Any] = [.font: coordFont, .foregroundColor: ink.coord]
        let a2: [NSAttributedString.Key: Any] = [.font: nameFont, .foregroundColor: ink.place]
        let w = max((coord as NSString).size(withAttributes: a1).width, (l.name as NSString).size(withAttributes: a2).width)
        let dx: CGFloat = 28, dy: CGFloat = up ? -44 : 6
        // 画布：锚点（落脚点）在 (pad, ay)
        let pad: CGFloat = 4
        let top = min(dy, 0) - pad, bottom = max(dy + 52, 0) + pad
        let size = CGSize(width: pad + dx + w + pad, height: bottom - top)
        let anchor = CGPoint(x: pad, y: -top)
        let img = Self.draw(size) { ctx in
            ctx.setStrokeColor(ink.leader.cgColor)
            ctx.setLineWidth(1)
            ctx.move(to: anchor)
            ctx.addLine(to: CGPoint(x: anchor.x + dx, y: anchor.y + dy + 14))
            ctx.strokePath()
            (coord as NSString).draw(at: CGPoint(x: anchor.x + dx, y: anchor.y + dy), withAttributes: a1)
            (l.name as NSString).draw(at: CGPoint(x: anchor.x + dx, y: anchor.y + dy + 24), withAttributes: a2)
        }
        let plane = SCNPlane(width: size.width * Self.px, height: size.height * Self.px)
        plane.firstMaterial = Self.flatMaterial(img)
        let child = SCNNode(geometry: plane)
        // 平面中心挪开，让锚点落在节点原点上
        child.position = SCNVector3(Float((size.width / 2 - anchor.x) * Self.px), Float(-(size.height / 2 - anchor.y) * Self.px), 0)
        child.renderingOrder = 18
        let n = SCNNode()
        n.simdPosition = p
        n.constraints = [SCNBillboardConstraint()]
        n.addChildNode(child)
        return n
    }

    /// 地名字条：点右边 12 像素起，竖着居中在点上（效果图像素，跟坐标小字同一个字号 19）
    private func nameNode(_ name: String, ink: PGGlobeInk, at p: SIMD3<Float>) -> (SCNNode, CGFloat) {
        let font = UIFont(name: "STSongti-SC-Regular", size: 19)
            ?? UIFont.systemFont(ofSize: 19).fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: 19) }
            ?? .systemFont(ofSize: 19)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink.coord]
        let tw = ceil((name as NSString).size(withAttributes: attrs).width)
        let gap: CGFloat = 12, h: CGFloat = 28
        let size = CGSize(width: gap + tw + 4, height: h)
        let img = Self.draw(size) { _ in
            (name as NSString).draw(at: CGPoint(x: gap, y: (h - font.lineHeight) / 2), withAttributes: attrs)
        }
        let plane = SCNPlane(width: size.width * Self.px, height: size.height * Self.px)
        plane.firstMaterial = Self.flatMaterial(img)
        let child = SCNNode(geometry: plane)
        child.position = SCNVector3(Float(size.width / 2 * Self.px), 0, 0)   // 锚点在字条左边中间
        child.renderingOrder = 17
        let n = SCNNode()
        n.simdPosition = p
        n.constraints = [SCNBillboardConstraint()]
        n.addChildNode(child)
        n.opacity = 0
        return (n, size.width)
    }

    private static func draw(_ size: CGSize, _ body: (CGContext) -> Void) -> UIImage {
        let f = UIGraphicsImageRendererFormat()
        f.scale = 2
        f.opaque = false
        return UIGraphicsImageRenderer(size: size, format: f).image { body($0.cgContext) }
    }

    // MARK: 转、放大、点

    /// 北永远朝上：先绕竖轴把中心经度转到正面，再绕横轴把中心纬度压到正中
    private func updatePose() {
        let q = simd_quatf(angle: centerLat, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: -centerLon, axis: SIMD3(0, 1, 0))
        globe.simdOrientation = q
        (cameraNode.camera)?.orthographicScale = Self.baseScale / Double(zoom)
        let s = 1 / zoom   // 点和字在屏幕上一直一样大
        // 地名放大到 1.5 倍开始浮出来，1.9 倍全显；屏幕上挤在一起的，先到先得（最近去的排在前面）
        let nameFade = CGFloat(min(max((zoom - 1.5) / 0.4, 0), 1))
        let ptPerPx = (view?.bounds.width ?? 400) / 1000   // 效果图 1 像素在屏幕上合多少点（字条不跟着放大）
        let ls = CGFloat(Self.labelScale)
        let scrubbing = timeIdx != nil
        var taken: [CGRect] = []
        for m in markList {
            let w = q.act(m.pos)
            var isText = false
            let cut: Float = { if case .label = m.kind { return 0 } else { return 0.02 } }()
            var o = CGFloat(min(max((w.z - cut) / 0.06, 0), 1))
            switch m.kind {
            case .label:
                isText = true
                if scrubbing { o = 0 }   // 拖时间的时候坐标小字先收起来
            case .ring:
                if scrubbing { o = 0 }
            case .dot:
                if let ti = timeIdx, m.t > ti { o = 0 }
            case .name:
                isText = true
                o *= nameFade
                if let ti = timeIdx, m.t > ti { o = 0 }
                if o > 0, let v = view {
                    let sp = v.projectPoint(SCNVector3(w.x * 1.002, w.y * 1.002, w.z * 1.002))
                    let r = CGRect(x: CGFloat(sp.x) + 4, y: CGFloat(sp.y) - 9 * ls, width: m.w * ptPerPx * ls, height: 18 * ls)
                    if taken.contains(where: { $0.intersects(r) }) { o = 0 } else { taken.append(r) }
                }
            }
            m.node.opacity = o
            m.node.simdScale = SIMD3(repeating: isText ? s * Self.labelScale : s)
        }
        for a in arcs { a.node.opacity = (timeIdx.map { a.t <= $0 } ?? true) ? 1 : 0 }
    }

    /// 时间滑条拖动：只亮到这一站为止，地球慢慢转过去对着这一站
    func setTime(_ idx: Int?) {
        guard idx != timeIdx else { return }
        timeIdx = idx
        if let i = idx, places.indices.contains(i) {
            let p = places[i]
            follow = SIMD2(Float(min(max(p.lat, -60), 60)) * .pi / 180, Float(p.lon) * .pi / 180)
            startFollow()
        }
        updatePose()
    }

    private func startFollow() {
        guard link == nil else { return }
        lastTick = CACurrentMediaTime()
        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
    }

    /// 屏幕上一个点（pt）合多少弧度
    private var radPerPoint: Float {
        let side = Float(view?.bounds.width ?? 400)
        return 1 / max(side * 0.47 * zoom, 1)
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        guard let v = view else { return }
        switch g.state {
        case .began:
            follow = nil
            stopInertia()
        case .changed:
            let t = g.translation(in: v)
            g.setTranslation(.zero, in: v)
            turn(dx: Float(t.x), dy: Float(t.y))
        case .ended, .cancelled:
            let vel = g.velocity(in: v)
            velocity = SIMD2(Float(vel.x), Float(vel.y))
            startInertia()
        default: break
        }
    }

    private func turn(dx: Float, dy: Float) {
        let r = radPerPoint
        centerLon -= dx * r
        centerLat = min(max(centerLat + dy * r, -80 * .pi / 180), 80 * .pi / 180)
        updatePose()
    }

    private func startInertia() {
        guard simd_length(velocity) > 40 else { return }
        startFollow()
    }

    private func stopInertia() { link?.invalidate(); link = nil }

    /// 一个钟两件事：松手后顺着转一下（惯性），时间滑条拖的时候慢慢转到那一站（follow）
    @objc private func tick() {
        let now = CACurrentMediaTime()
        let dt = Float(min(now - lastTick, 1.0 / 30))
        lastTick = now
        if let f = follow {
            var dLon = f.y - centerLon
            dLon = atan2(sin(dLon), cos(dLon))   // 走近的那一边
            let k = min(1, dt * 5)
            centerLon += dLon * k
            centerLat += (f.x - centerLat) * k
            updatePose()
            if abs(dLon) < 0.002 && abs(f.x - centerLat) < 0.002 { follow = nil }
        } else {
            turn(dx: velocity.x * dt, dy: velocity.y * dt)
            velocity *= pow(0.04, dt)
            if simd_length(velocity) < 8 { velocity = .zero }
        }
        if follow == nil && simd_length(velocity) < 8 { stopInertia() }
    }

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began: pinchStart = zoom; stopInertia()
        case .changed:
            zoom = min(max(pinchStart * Float(g.scale), 1), 3.5)
            updatePose()
        default: break
        }
    }

    @objc private func onTap(_ g: UITapGestureRecognizer) {
        guard let v = view else { return }
        let at = g.location(in: v)
        var best: (trip: Int, d: CGFloat)?
        for m in markList {
            guard case .dot(let trip) = m.kind, m.node.opacity > 0.5 else { continue }
            let w = v.projectPoint(m.node.worldPosition)
            let d = hypot(CGFloat(w.x) - at.x, CGFloat(w.y) - at.y)
            if d < 24, d < (best?.d ?? .infinity) { best = (trip, d) }
        }
        if let b = best {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onPick?(b.trip)
        }
    }

    deinit { link?.invalidate() }
}
