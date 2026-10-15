import SwiftUI
import UIKit
import CoreText

// MARK: - 1015 远游 Peregrinatio（原乌有乡）
// 她定的（#3838–3873，效果图 /root/workroom/mock/album/、/root/workroom/mock/angel-cards/pccard2.html）：
// - 邮册：一枚邮票＝一趟旅程（图只用那趟的标题图），一页 3×3、最新在前；地名写在插袋上；新的有 NEW；
//   有没看够的那趟别一根别针；页底只放最近一条意犹未尽。翻页只留小圆点。
// - 点邮票：抽出来放大；再点：翻面（他寄的明信片＋邮戳＋右下「去看看他的旅程…」）；再点翻回；点邮票外面任意处插回去。
// - 旅行日记：顶上一张图下沿淡出，下面图文混排，图一右一左、字绕图（TextKit exclusionPaths）。
// - 手写字体（她给的「萌味小猫慵懒手书」100 版）只用在明信片背面和旅行日记正文；走字体架下载注册，不进包。
// - 底色是水彩纸的颜色 #F1F2F4（材质不要），黑夜 Sanctus 炭灰；日夜跟全屋按钮。
// 数据：前门 /api/nowhere/peregrinatio/trips|linger|img/<名>（乌有乡 web 口上挂的 /root/rhysel/peregrinatio_api.py）。
// 地球在 PeregrinatioGlobe.swift，入口是标题右下「在地球上看 ›」。

enum PGDeepLink { static var tripID: Int? }

struct PGStop: Decodable, Hashable {
    let n: Int
    let name: String
    let local_time: String?
    let image: String
}

struct PGStamp: Decodable, Hashable {
    let place: String?
    let local_time: String?
    let weather: String?
    let temp_c: Double?
}

struct PGPostcard: Decodable, Hashable, Identifiable {
    let id: Int
    let text: String
    let stamp: PGStamp?
}

struct PGLingerRef: Decodable, Hashable {
    let id: Int
    let question: String
    let open: Bool
}

struct PGTrip: Decodable, Hashable, Identifiable {
    let id: Int
    let title: String
    let legacy: Bool
    let started_at: String
    let ended_at: String
    let open: Bool
    let place: String
    let hero: String
    let diary: String
    let stops: [PGStop]
    let postcards: [PGPostcard]
    let linger: [PGLingerRef]

    /// 邮票上、插袋上的名字：有英文标题的写地名（标题留给日记页），旧的只有地名
    var label: String { place.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? place }
    var day: String { String(started_at.dropFirst(5).prefix(5)).replacingOccurrences(of: "-", with: ".") }
    var hasOpenLinger: Bool { linger.contains { $0.open } }
}

struct PGLingerRound: Decodable, Hashable { let at: String; let text: String }
struct PGLingerItem: Decodable, Hashable, Identifiable {
    let id: Int
    let trip: Int
    let place: String?
    let question: String
    let at: String
    let rounds: [PGLingerRound]
    let closed_at: String?
}

enum PGAPI {
    static func imageURL(_ name: String) -> URL? {
        name.isEmpty ? nil : AlcoveAPI.fullURL("/api/nowhere/peregrinatio/img/" + name)
    }
    static func decode<T: Decodable>(_ any: Any?, as: T.Type) -> T? {
        guard let any, JSONSerialization.isValidJSONObject(any),
              let data = try? JSONSerialization.data(withJSONObject: any) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    static func trips() async -> [PGTrip]? {
        guard let o = try? await NativeHouseAPI.object("/api/nowhere/peregrinatio/trips") else { return nil }
        return decode(o["trips"], as: [PGTrip].self)
    }
    static func linger() async -> [PGLingerItem]? {
        guard let o = try? await NativeHouseAPI.object("/api/nowhere/peregrinatio/linger") else { return nil }
        return decode(o["items"], as: [PGLingerItem].self)
    }
}

/// 颜色：白天水彩纸色 #F1F2F4，黑夜 Sanctus 炭灰（图不改色只压暗）
struct PGInk {
    let dark: Bool
    init() { dark = AlcoveAppearance.isDark }
    private func rgb(_ hex: Int, _ a: Double = 1) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: a)
    }
    var paper: Color { dark ? rgb(0x1B1C20) : rgb(0xF1F2F4) }
    var dot: Color { dark ? Color.white.opacity(0.035) : rgb(0x969AA4, 0.07) }
    var script: Color { dark ? rgb(0xC3C6CE) : rgb(0x3E4048) }
    var scriptSoft: Color { dark ? rgb(0xC3C6CE) : rgb(0x6F7480) }
    var kicker: Color { dark ? rgb(0x8B8F99) : rgb(0x9A9EA8) }
    var body: Color { dark ? rgb(0xD8DAE0) : rgb(0x3E4048) }
    var sub: Color { dark ? rgb(0x8B8F99) : rgb(0x9A9EA8) }
    var link: Color { dark ? rgb(0xA3A7B0) : rgb(0x7D818C) }
    var stampInk: Color { dark ? rgb(0xA3A7B0) : rgb(0x4E688C) }
    var hair: Color { dark ? Color.white.opacity(0.14) : rgb(0x969AA4, 0.45) }
    var sleeveTop: Color { dark ? Color.white.opacity(0.07) : Color.white.opacity(0.42) }
    var sleeveBottom: Color { dark ? Color.white.opacity(0.05) : rgb(0xFAFBFD, 0.5) }
    var sleeveEdge: Color { dark ? Color.white.opacity(0.12) : rgb(0x969AA4, 0.35) }
    var stampPaper: Color { rgb(0xFDFDFC) }
    var stampDim: Double { dark ? 0.8 : 1 }
    var photoDim: Double { dark ? 0.82 : 1 }
    var note: Color { dark ? Color.white.opacity(0.04) : Color.white.opacity(0.7) }
    var noteEdge: Color { dark ? Color.white.opacity(0.1) : rgb(0x969AA4, 0.35) }
    var veil: Color { dark ? rgb(0x1B1C20, 0.78) : rgb(0xEFEFED, 0.72) }
}

enum PGFont {
    static func script(_ s: CGFloat) -> Font { .custom("PinyonScript-Regular", size: s) }
    static func corm(_ s: CGFloat) -> Font { .custom("CormorantGaramond-Medium", size: s) }
    static func ital(_ s: CGFloat) -> Font { .custom("CormorantGaramondItalic-MediumItalic", size: s) }
    /// 手写字：远游自己下载注册好了用它，没好之前先用宋体顶着
    static func handName() -> String? { PGHandFont.shared.name }
    static func hand(_ s: CGFloat) -> Font { handName().map { .custom($0, size: s) } ?? .system(size: s, design: .serif) }
    static func handUI(_ s: CGFloat) -> UIFont {
        if let n = handName(), let f = UIFont(name: n, size: s) { return f }
        let base = UIFont.systemFont(ofSize: s)
        return base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: s) } ?? base
    }
    static func ensureHand() { PGHandFont.shared.ensure() }
}

/// 1015 她：「手写字体咋没有」——原来借设置里那套字体名单，名单还没拿到就放弃了、之后不再试。
/// 改成远游自己下：字体架上那份 /api/kakao/fonts/peregrinatio-hand.ttf，存进 Application Support，CoreText 当场注册，不进安装包
final class PGHandFont: ObservableObject {
    static let shared = PGHandFont()
    @Published private(set) var name: String?
    private var loading = false

    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("peregrinatio", isDirectory: true)
            .appendingPathComponent("hand.ttf")
    }

    private static func register(_ url: URL) -> String? {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)   // 重复注册会报错，忽略，名字照样取得到
        guard let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let d = descs.first else { return nil }
        return CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute) as? String
    }

    func ensure() {
        guard name == nil, !loading else { return }
        let f = Self.file
        if FileManager.default.fileExists(atPath: f.path), let n = Self.register(f) {
            name = n
            return
        }
        loading = true
        Task {
            var got: String?
            if let (data, resp) = try? await URLSession.shared.data(from: AlcoveAPI.fullURL("/api/kakao/fonts/peregrinatio-hand.ttf")),
               (resp as? HTTPURLResponse)?.statusCode == 200, data.count > 100_000 {
                try? FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: f, options: .atomic)
                got = Self.register(f)
            }
            await MainActor.run {
                self.loading = false
                if let got { self.name = got }
            }
        }
    }
}

// MARK: - 邮票：照片＋白纸＋四边齿孔（只在边上打孔）

struct PGStampShape: Shape {
    var hole: CGFloat = 2.6
    var step: CGFloat = 8
    func path(in r: CGRect) -> Path {
        var p = Path(r)
        // 角上的孔只让上下两条边打；竖边再打一次会跟它叠成两层，奇偶填充又把孔补回去
        func holes(along len: CGFloat, corners: Bool = true, _ at: (CGFloat) -> CGPoint) {
            let n = max(2, Int((len / step).rounded()))
            let gap = len / CGFloat(n)
            for i in (corners ? 0 : 1)...(corners ? n : n - 1) {
                let c = at(CGFloat(i) * gap)
                p.addEllipse(in: CGRect(x: c.x - hole, y: c.y - hole, width: hole * 2, height: hole * 2))
            }
        }
        holes(along: r.width) { CGPoint(x: r.minX + $0, y: r.minY) }
        holes(along: r.width) { CGPoint(x: r.minX + $0, y: r.maxY) }
        holes(along: r.height, corners: false) { CGPoint(x: r.minX, y: r.minY + $0) }
        holes(along: r.height, corners: false) { CGPoint(x: r.maxX, y: r.minY + $0) }
        return p
    }
}

struct PGStampView: View {
    let trip: PGTrip
    let ink: PGInk
    var scale: CGFloat = 1      // 邮册里 1，抽出来放大
    var body: some View {
        let pad = 9 * scale
        ZStack {
            ink.stampPaper
            // 1015 她：邮票固定大小，照片裁进框里（原来 scaledToFill 按原比例把邮票撑得参差不齐）
            Color.clear
                .overlay(
                    CachedImage(url: PGAPI.imageURL(trip.hero)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color(white: 0.9)
                    }
                )
                .clipped()
                .overlay(Rectangle().stroke(ink.stampInk.opacity(0.45), lineWidth: 0.6).padding(-3 * scale))
                .padding(pad)
        }
        .clipShape(PGStampShape(hole: 2.6 * scale, step: 8 * scale), style: FillStyle(eoFill: true))
        .brightness(ink.dark ? -0.2 : 0)
        .shadow(color: ink.dark ? .black.opacity(0.5) : Color(white: 0.47).opacity(0.22), radius: 1.5, x: 0, y: 1)
    }
}

/// 别针：意犹未尽的那趟
struct PGPin: View {
    let ink: PGInk
    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(ink.link).frame(width: 0.8, height: 9).offset(y: 5)
            Circle().fill(ink.dark ? Color(white: 0.17) : .white).frame(width: 6.4, height: 6.4)
                .overlay(Circle().stroke(ink.link, lineWidth: 0.8))
        }
        .frame(width: 8, height: 15)
    }
}

// MARK: - 远游主页面：邮册

struct PeregrinatioRoom: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    @ObservedObject private var handFont = PGHandFont.shared
    @State private var trips: [PGTrip] = []
    @State private var lingers: [PGLingerItem] = []
    @State private var loaded = false
    @State private var page = 0
    @State private var pulled: PGTrip?
    @State private var flipped = false
    @State private var diary: PGTrip?
    @State private var showGlobe = false

    private var ink: PGInk { _ = houseAppearance; return PGInk() }
    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0 }
    private var pages: [[PGTrip]] { stride(from: 0, to: trips.count, by: 9).map { Array(trips[$0..<min($0 + 9, trips.count)]) } }
    private var latestLinger: PGLingerItem? { lingers.filter { ($0.closed_at ?? "").isEmpty }.max { $0.at < $1.at } }

    var body: some View {
        let ink = self.ink
        ZStack {
            ink.paper.ignoresSafeArea()
            PGDots(ink: ink).ignoresSafeArea()
            VStack(spacing: 0) {
                header(ink)
                if !loaded {
                    Spacer()
                } else if trips.isEmpty {
                    Spacer()
                    Text("他还没出过门").font(PGFont.ital(14)).foregroundColor(ink.sub)
                    Spacer()
                } else {
                    TabView(selection: $page) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { i, items in
                            albumPage(items, ink: ink).tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    if let l = latestLinger { lingerNote(l, ink: ink).padding(.horizontal, 22).padding(.bottom, 12) }
                    pageDots(ink).padding(.bottom, 14)
                }
            }
            .padding(.top, max(safeTop, 20))
            if let t = pulled { pulledLayer(t, ink: ink) }
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .regular)).foregroundColor(ink.link)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 8).padding(.top, max(safeTop, 20))
            .opacity(pulled == nil ? 1 : 0)
        }
        .fullScreenCover(item: $diary) { t in PGDiaryView(trip: t) }
        .task {
            PGFont.ensureHand()
            await reload()
        }
    }

    private func reload() async {
        async let t = PGAPI.trips()
        async let l = PGAPI.linger()
        let (tt, ll) = await (t, l)
        trips = tt ?? trips
        lingers = ll ?? lingers
        loaded = true
        if let want = PGDeepLink.tripID, let hit = trips.first(where: { $0.id == want }) {
            PGDeepLink.tripID = nil
            if let idx = trips.firstIndex(of: hit) { page = idx / 9 }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { pulled = hit; flipped = false }
        }
    }

    private func header(_ ink: PGInk) -> some View {
        VStack(spacing: 6) {
            Text("Peregrinatio").font(PGFont.script(34)).foregroundColor(ink.script)
            Text("远游 · 邮册 · \(trips.count) 趟旅程").font(PGFont.corm(11)).tracking(2.6).foregroundColor(ink.kicker)
        }
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) { PGHair(ink: ink).padding(.horizontal, 30) }
        // 效果图 album_top.html：右边、细线正上方
        .overlay(alignment: .bottomTrailing) {
            if !trips.isEmpty {
                Button { showGlobe = true } label: {
                    Text("在地球上看 ›").font(.system(size: 12, design: .serif)).tracking(1.5).foregroundColor(ink.link)
                        .padding(.vertical, 8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 26)
                .padding(.bottom, -2)
            }
        }
        .fullScreenCover(isPresented: $showGlobe) {
            PGGlobePage { id in
                // 地球上点了一个地方：等地球收起来，翻到那一页把那枚抽出来
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { pull(id) }
            }
        }
    }

    private func pull(_ id: Int) {
        guard let t = trips.first(where: { $0.id == id }), let idx = trips.firstIndex(of: t) else { return }
        page = idx / 9
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { pulled = t; flipped = false }
    }

    /// 一页 3×3：每排邮票下半截插在透明插袋里，地名写在插袋上
    /// 1015 #3889 她：字太小、空的地方舒展一下 → 邮票 94×108 放到 100×120，插袋上的字 6.6 放到 9.5，行距拉开（104×124 三排放不下，压到便签）
    private func albumPage(_ items: [PGTrip], ink: PGInk) -> some View {
        let rows = stride(from: 0, to: items.count, by: 3).map { Array(items[$0..<min($0 + 3, items.count)]) }
        let newest = trips.first?.id
        let sw: CGFloat = 100, sh: CGFloat = 120, gap: CGFloat = 16, labW: CGFloat = 110
        return VStack(spacing: 22) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                ZStack(alignment: .top) {
                    HStack(spacing: gap) {
                        ForEach(row) { t in
                            VStack(spacing: 0) {
                                ZStack(alignment: .topTrailing) {
                                    PGStampView(trip: t, ink: ink)
                                        .frame(width: sw, height: sh)
                                        .opacity(pulled?.id == t.id ? 0 : 1)
                                    if t.hasOpenLinger { PGPin(ink: ink).offset(x: -8, y: -8) }
                                }
                                .overlay(alignment: .topLeading) {
                                    if t.id == newest {
                                        Text("NEW").font(PGFont.corm(9)).tracking(1.8).foregroundColor(ink.kicker).offset(x: 2, y: -16)
                                    }
                                }
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { pulled = t; flipped = false }
                                }
                                Color.clear.frame(height: 26)
                            }
                            .frame(width: sw)
                        }
                        ForEach(0..<(3 - row.count), id: \.self) { _ in Color.clear.frame(width: sw, height: sh + 26) }
                    }
                    // 插袋：盖住邮票下半截，地名写在袋子上
                    VStack(spacing: 0) {
                        Spacer().frame(height: 77)
                        ZStack(alignment: .bottom) {
                            LinearGradient(colors: [ink.sleeveTop, ink.sleeveBottom], startPoint: .top, endPoint: .bottom)
                                .background(.ultraThinMaterial.opacity(0.35))
                                .overlay(alignment: .top) { Rectangle().fill(ink.sleeveEdge).frame(height: 0.6) }
                                .overlay(alignment: .bottom) { Rectangle().fill(ink.sleeveEdge.opacity(0.7)).frame(height: 0.6) }
                            HStack(spacing: gap + sw - labW) {
                                ForEach(row) { t in
                                    HStack {
                                        Text(t.label.uppercased()).font(PGFont.corm(9.5)).tracking(0.8).lineLimit(1).minimumScaleFactor(0.75)
                                        Spacer(minLength: 2)
                                        Text(t.day).font(PGFont.ital(9.5))
                                    }
                                    .foregroundColor(ink.stampInk)
                                    .frame(width: labW)
                                }
                                ForEach(0..<(3 - row.count), id: \.self) { _ in Color.clear.frame(width: labW, height: 1) }
                            }
                            .padding(.bottom, 7)
                        }
                        .frame(height: 70)
                        .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 18)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 24)
    }

    private func lingerNote(_ l: PGLingerItem, ink: PGInk) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("意犹未尽 · 最近一次").font(PGFont.corm(10)).tracking(2.2).foregroundColor(ink.kicker)
            Text(l.question).font(.system(size: 15, design: .serif)).foregroundColor(ink.body).lineLimit(2)
            Text("\(l.place ?? "") · \(String(l.at.dropFirst(5).prefix(5)).replacingOccurrences(of: "-", with: ".")) · 续了 \(l.rounds.count) / 3 次")
                .font(PGFont.ital(12)).foregroundColor(ink.sub)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ink.note)
        .overlay(Rectangle().stroke(ink.noteEdge, lineWidth: 0.6))
    }

    private func pageDots(_ ink: PGInk) -> some View {
        HStack(spacing: 7) {
            ForEach(0..<max(1, pages.count), id: \.self) { i in
                Circle().fill(ink.sub.opacity(i == page ? 1 : 0.6)).frame(width: i == page ? 7 : 2.5, height: i == page ? 7 : 2.5)
            }
        }
    }

    /// 抽出来的那一枚：再点翻面，背面是明信片；点外面插回去
    private func pulledLayer(_ t: PGTrip, ink: PGInk) -> some View {
        ZStack {
            Rectangle().fill(ink.veil).background(.ultraThinMaterial.opacity(0.6)).ignoresSafeArea()
                .onTapGesture { putBack() }
            ZStack {
                PGStampView(trip: t, ink: ink, scale: 1.7)
                    .frame(width: 282, height: 350)
                    .opacity(flipped ? 0 : 1)
                PGPostcardBack(trip: t, ink: ink) { open(t) }
                    .frame(width: 300)
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.72)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .opacity(flipped ? 1 : 0)
            }
            .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.5)) { flipped.toggle() }
            }
            .transition(.scale(scale: 0.35).combined(with: .opacity))
            VStack {
                Spacer()
                Text(flipped ? "再点一下翻回去 · 点空白处放回去" : "点一下翻面 · 点空白处放回去")
                    .font(.system(size: 10.5, design: .serif)).foregroundColor(ink.sub)
                    .padding(.bottom, 90)
            }
            .allowsHitTesting(false)
        }
        .transition(.opacity)
    }

    private func putBack() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { flipped = false; pulled = nil }
    }

    private func open(_ t: PGTrip) { diary = t }
}

private struct PGDots: View {
    let ink: PGInk
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(ink.dot))
                    x += 5
                }
                y += 5
            }
        }
        .allowsHitTesting(false)
    }
}

struct PGHair: View {
    let ink: PGInk
    var body: some View {
        LinearGradient(stops: [.init(color: ink.hair.opacity(0), location: 0), .init(color: ink.hair, location: 0.12),
                               .init(color: ink.hair, location: 0.88), .init(color: ink.hair.opacity(0), location: 1)],
                       startPoint: .leading, endPoint: .trailing)
            .frame(height: 0.6)
    }
}

/// 邮票背面＝他寄来的明信片：手写字，右上角盖邮戳，右下「去看看他的旅程…」
/// 明信片背面（1015 #3881 她改：字放大到 17、高度跟着他写了多少字走，下面别空一大片；
/// 效果图 /root/workroom/mock/postcard-back/back_new.jpg）。第一张的头几行让开右上的邮戳，往下排满整行；
/// 字多到超过屏幕四分之三就封顶，在卡里滑。一趟寄了好几张的，细线隔开往下排。
struct PGPostcardBack: View {
    let trip: PGTrip
    let ink: PGInk
    let onOpen: () -> Void
    @ObservedObject private var handFont = PGHandFont.shared

    private var card: PGPostcard? { trip.postcards.last }
    private static let textColor = UIColor(red: 0x3E / 255, green: 0x40 / 255, blue: 0x48 / 255, alpha: 1)

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView(showsIndicators: false) { content }
        }
        .background(ink.stampPaper)
        .clipShape(PGStampShape(hole: 2.6, step: 8), style: FillStyle(eoFill: true))
        .brightness(ink.dark ? -0.2 : 0)
        .shadow(color: .black.opacity(ink.dark ? 0.5 : 0.18), radius: 2, x: 0, y: 1)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if trip.postcards.isEmpty {
                PGPostcardText(text: "这一趟他没寄明信片。", color: UIColor(white: 0.5, alpha: 1), avoidPostmark: true, fontName: handFont.name)
            }
            ForEach(Array(trip.postcards.enumerated()), id: \.element.id) { i, c in
                if i > 0 { PGHair(ink: PGInk.light).padding(.vertical, 14) }
                PGPostcardText(text: c.text, color: Self.textColor, avoidPostmark: i == 0, fontName: handFont.name)
            }
            HStack {
                Spacer()
                Button(action: onOpen) {
                    Text("去看看他的旅程…").font(PGFont.ital(13)).foregroundColor(Color(white: 0.55))
                        .padding(.vertical, 8).padding(.leading, 6).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 10)
        .overlay(alignment: .topTrailing) {
            PGPostmark(stamp: card?.stamp, place: trip.label)
                .frame(width: 80, height: 80)
                .opacity(0.55)
                .padding(.top, 16).padding(.trailing, 16)
                .allowsHitTesting(false)
        }
    }
}

/// 明信片正文：手写 17 号；avoidPostmark 时右上角挖掉邮戳那块（卡宽 300、邮戳 80 离边 16、字离边 24 → 字区右边 82×76 让开）
struct PGPostcardText: UIViewRepresentable {
    let text: String
    let color: UIColor
    let avoidPostmark: Bool
    let fontName: String?

    func makeUIView(context: Context) -> PGPostcardTextView { PGPostcardTextView() }
    func updateUIView(_ v: PGPostcardTextView, context: Context) { v.configure(text: text, color: color, avoid: avoidPostmark) }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PGPostcardTextView, context: Context) -> CGSize? {
        let w = proposal.width ?? 252
        return CGSize(width: w, height: uiView.height(for: w))
    }
}

final class PGPostcardTextView: UIView {
    static let markW: CGFloat = 82, markH: CGFloat = 76
    private let tv = UITextView()
    private var avoid = false
    private var key = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.isSelectable = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        addSubview(tv)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(text: String, color: UIColor, avoid: Bool) {
        let k = "\(text)|\(avoid)|\(PGFont.handName() ?? "")|\(color.description)"
        guard k != key else { return }
        key = k
        self.avoid = avoid
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 8.5
        tv.attributedText = NSAttributedString(string: text, attributes: [
            .font: PGFont.handUI(17), .foregroundColor: color, .paragraphStyle: ps])
        setNeedsLayout()
    }

    private func apply(width w: CGFloat) {
        tv.textContainer.size = CGSize(width: w, height: .greatestFiniteMagnitude)
        tv.textContainer.exclusionPaths = avoid
            ? [UIBezierPath(rect: CGRect(x: w - Self.markW, y: 0, width: Self.markW + 20, height: Self.markH))] : []
    }

    func height(for w: CGFloat) -> CGFloat {
        apply(width: w)
        let lm = tv.layoutManager
        lm.ensureLayout(for: tv.textContainer)
        let h = ceil(lm.usedRect(for: tv.textContainer).height) + 2
        return avoid ? max(h, Self.markH) : h   // 字少也要把邮戳那块撑出来，「去看看」别顶上去
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        apply(width: bounds.width)
        tv.frame = bounds
    }
}

extension PGInk {
    /// 明信片背面永远是白纸（黑夜整张压暗），里面的线按白天配
    static var light: PGInk { PGInk(forceDark: false) }
    init(forceDark: Bool) { dark = forceDark }
}

/// 圆邮戳：两圈，上面地名，中间当地日期，下面当地时间
struct PGPostmark: View {
    let stamp: PGStamp?
    let place: String
    private let c = Color(red: 0x4E / 255, green: 0x68 / 255, blue: 0x8C / 255)
    var body: some View {
        let lt = stamp?.local_time ?? ""
        let date = lt.count >= 10 ? String(lt.prefix(10)).replacingOccurrences(of: "-", with: " · ") : ""
        let time = lt.count >= 16 ? String(lt.dropFirst(11).prefix(5)) + " local" : ""
        ZStack {
            Circle().stroke(c, lineWidth: 1)
            Circle().stroke(c, lineWidth: 0.8).padding(7)
            VStack(spacing: 2) {
                Text((stamp?.place ?? place).components(separatedBy: ",").first?.uppercased() ?? "")
                    .font(PGFont.corm(9)).tracking(1.2).lineLimit(1).minimumScaleFactor(0.6)
                Text(date).font(PGFont.corm(10))
                Text(time).font(PGFont.ital(9))
            }
            .foregroundColor(c)
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - 旅行日记页：顶图淡出＋图文混排（图一右一左，字绕图）

struct PGDiaryView: View {
    let trip: PGTrip
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    @ObservedObject private var handFont = PGHandFont.shared
    private var ink: PGInk { _ = houseAppearance; return PGInk() }
    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0 }

    /// 没写日记的旧旅程：用他那趟寄的明信片当正文
    private var bodyText: String {
        let d = trip.diary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !d.isEmpty { return d }
        return trip.postcards.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "\n\n")
    }
    private var inlineStops: [PGStop] { trip.stops.filter { !$0.image.isEmpty && $0.image != trip.hero } }
    private var dateRange: String {
        let a = trip.day
        let b = String(trip.ended_at.dropFirst(5).prefix(5)).replacingOccurrences(of: "-", with: ".")
        return (b.isEmpty || b == a) ? a : "\(a) — \(b)"
    }

    var body: some View {
        let ink = self.ink
        ZStack(alignment: .topLeading) {
            ink.paper.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        CachedImage(url: PGAPI.imageURL(trip.hero)) { img in
                            img.resizable().scaledToFill()
                        } placeholder: { ink.paper }
                        .frame(height: 330)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .brightness(ink.dark ? -0.12 : 0)
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0.55), .init(color: .clear, location: 1)],
                                             startPoint: .top, endPoint: .bottom))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(trip.title.isEmpty ? trip.label : trip.title).font(PGFont.script(32)).foregroundColor(ink.script)
                                .lineLimit(2).minimumScaleFactor(0.6)
                            Text("陈璟旅行日记 · \(trip.label) · \(dateRange)").font(PGFont.corm(8)).tracking(2.2).foregroundColor(ink.kicker)
                        }
                        .padding(.horizontal, 28).padding(.bottom, 2)
                    }
                    PGFlowText(text: bodyText, stops: inlineStops, ink: ink, fontName: handFont.name)
                        .padding(.horizontal, 28).padding(.top, 14)
                    if let l = trip.linger.first {
                        PGHair(ink: ink).padding(.horizontal, 28).padding(.top, 14)
                        Text("意犹未尽 · \(l.question)").font(.system(size: 10, design: .serif)).foregroundColor(ink.link)
                            .padding(.horizontal, 28).padding(.top, 10)
                    }
                    Color.clear.frame(height: 60)
                }
            }
            .ignoresSafeArea(edges: .top)
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17)).foregroundColor(.white)
                    .shadow(color: .black.opacity(0.35), radius: 3)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 8).padding(.top, max(safeTop, 20))
        }
        .task { PGFont.ensureHand() }
    }
}

/// 图文混排：UITextView 的 exclusionPaths 让字绕开图；图从右上开始，一右一左往下排
struct PGFlowText: UIViewRepresentable {
    let text: String
    let stops: [PGStop]
    let ink: PGInk
    let fontName: String?

    func makeUIView(context: Context) -> PGFlowView { PGFlowView() }

    func updateUIView(_ v: PGFlowView, context: Context) {
        v.configure(text: text, stops: stops, ink: ink)
    }

    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PGFlowView, context: Context) -> CGSize? {
        let w = proposal.width ?? UIScreen.main.bounds.width - 56
        return CGSize(width: w, height: uiView.height(for: w))
    }
}

final class PGFlowView: UIView {
    private let tv = UITextView()
    private var figs: [(UIImageView, UILabel, PGStop)] = []
    private var key = ""
    private let figW: CGFloat = 142, figH: CGFloat = 110, capH: CGFloat = 16, gap: CGFloat = 14
    private var lastWidth: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.isSelectable = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        addSubview(tv)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(text: String, stops: [PGStop], ink: PGInk) {
        let k = text + "|" + stops.map(\.image).joined(separator: ",") + "|\(ink.dark)|\(PGFont.handName() ?? "")"
        guard k != key else { return }
        key = k
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 9
        ps.paragraphSpacing = 9
        ps.alignment = .justified
        let bodyColor = UIColor(ink.body)
        tv.attributedText = NSAttributedString(string: text, attributes: [
            .font: PGFont.handUI(17), .foregroundColor: bodyColor, .paragraphStyle: ps])
        figs.forEach { $0.0.removeFromSuperview(); $0.1.removeFromSuperview() }
        figs = stops.map { s in
            let iv = UIImageView()
            iv.contentMode = .scaleAspectFill
            iv.clipsToBounds = true
            iv.backgroundColor = UIColor(white: ink.dark ? 0.2 : 0.9, alpha: 1)
            iv.alpha = ink.dark ? 0.82 : 1
            let cap = UILabel()
            cap.font = UIFont(name: "CormorantGaramondItalic-MediumItalic", size: 9) ?? .italicSystemFont(ofSize: 9)
            cap.textColor = UIColor(ink.sub)
            let lt = (s.local_time ?? "")
            let when = lt.count >= 16 ? String(lt.dropFirst(5).prefix(11)).replacingOccurrences(of: "-", with: ".") : ""
            cap.text = [s.name.components(separatedBy: ",").first ?? s.name, when].filter { !$0.isEmpty }.joined(separator: " · ")
            addSubview(iv); addSubview(cap)
            if let url = PGAPI.imageURL(s.image) {
                Task { @MainActor in iv.image = await ImageDiskCache.shared.image(for: url) }
            }
            return (iv, cap, s)
        }
        lastWidth = 0
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    /// 第 i 张图的框：一右一左，每张往下错开（字少时也不会叠在一起）
    private func figFrames(width w: CGFloat, textHeight th: CGFloat) -> [CGRect] {
        let n = figs.count
        guard n > 0 else { return [] }
        let step = max(figH + capH + 60, (th - figH) / CGFloat(max(1, n)))
        return (0..<n).map { i in
            let x: CGFloat = i % 2 == 0 ? w - figW : 0
            return CGRect(x: x, y: 4 + CGFloat(i) * step, width: figW, height: figH)
        }
    }

    private func layoutText(width w: CGFloat) -> CGFloat {
        tv.textContainer.size = CGSize(width: w, height: .greatestFiniteMagnitude)
        // 先不排图量一次字高，再按字高定图的位置、让字绕开（两遍就稳）
        tv.textContainer.exclusionPaths = []
        var th = tv.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height
        for _ in 0..<2 {
            let frames = figFrames(width: w, textHeight: th)
            // 右边的图往左让出 gap，左边的图往右让出 gap；图下面那行小字也让开
            tv.textContainer.exclusionPaths = frames.map { f in
                let x = f.minX == 0 ? 0 : f.minX - gap
                return UIBezierPath(rect: CGRect(x: x, y: f.minY, width: figW + gap, height: figH + capH + 6))
            }
            th = tv.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height
        }
        return th
    }

    func height(for w: CGFloat) -> CGFloat {
        let th = layoutText(width: w)
        let figBottom = figFrames(width: w, textHeight: th).map { $0.maxY + capH + 4 }.max() ?? 0
        return ceil(max(th, figBottom))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        guard w > 0 else { return }
        let th = layoutText(width: w)
        tv.frame = CGRect(x: 0, y: 0, width: w, height: th)
        for (f, item) in zip(figFrames(width: w, textHeight: th), figs) {
            item.0.frame = f
            item.1.frame = CGRect(x: f.minX, y: f.maxY + 3, width: figW, height: capH)
        }
    }
}

// MARK: - 聊天里的明信片小卡：框＋「他寄来了一张明信片」＋同一枚邮票；点邮票＝跟邮册里一样抽出来

struct PostcardChatCard: Decodable {
    let trip: Int
    let id: Int?
    let place: String?
    let local_time: String?
    let weather: String?
    let temp_c: Double?
    let image: String?
}

struct SanctusPostcardCard: View {
    let card: PostcardChatCard
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    private var ink: SanctusCardInk { _ = houseAppearance; return SanctusCardInk() }
    private var pg: PGInk { _ = houseAppearance; return PGInk() }
    private var place: String { (card.place ?? "").components(separatedBy: ",").first ?? "" }
    private var foot: String {
        let lt = card.local_time ?? ""
        let when = lt.count >= 16 ? String(lt.dropFirst(5).prefix(11)).replacingOccurrences(of: "-", with: ".") : ""
        let w = [card.temp_c.map { String(format: "%.1f°C", $0) }, card.weather].compactMap { $0 }.joined(separator: ", ")
        return [place, when, w].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        let ink = self.ink
        Button {
            PGDeepLink.tripID = card.trip
            NotificationCenter.default.post(name: .alcoveOpenHouse, object: HouseDestination.nowhere.rawValue)
        } label: {
            SanctusCardShell(ink: ink) {
                ZStack {
                    pg.stampPaper
                    CachedImage(url: PGAPI.imageURL(card.image ?? "")) { img in
                        img.resizable().scaledToFill()
                    } placeholder: { Color(white: 0.9) }
                    .frame(width: 58, height: 72).clipped()
                    .overlay(Rectangle().stroke(pg.stampInk.opacity(0.45), lineWidth: 0.5).padding(-2))
                }
                .frame(width: 70, height: 86)
                .clipShape(PGStampShape(hole: 2, step: 6.4), style: FillStyle(eoFill: true))
                .brightness(pg.dark ? -0.2 : 0)
                .shadow(color: .black.opacity(pg.dark ? 0.45 : 0.15), radius: 1.2, y: 1)
                .padding(.top, 15).padding(.trailing, 26)
            } content: {
                VStack(alignment: .leading, spacing: 0) {
                    Text("a postcard").font(SanctusCardFont.script(21)).foregroundColor(ink.script)
                    Text("POSTCARD · 明信片").font(SanctusCardFont.kicker()).tracking(2.4).foregroundColor(ink.kicker)
                        .padding(.top, 8)
                    Text("他寄来了一张明信片").font(.system(size: 13, design: .serif)).tracking(1).foregroundColor(ink.body)
                        .padding(.top, 9)
                    if !place.isEmpty {
                        Text("from \(card.place ?? "")").font(SanctusCardFont.ital(10.5)).foregroundColor(ink.sub)
                            .lineLimit(1).frame(maxWidth: 190, alignment: .leading).padding(.top, 3)
                    }
                    SanctusHair(ink: ink).padding(.top, 13)
                    HStack(alignment: .firstTextBaseline) {
                        Text(foot).font(SanctusCardFont.ital(9.5)).foregroundColor(ink.sub).lineLimit(1)
                        Spacer(minLength: 6)
                        Text("点邮票看看 ›").font(.system(size: 8.5, design: .serif)).tracking(1.6).foregroundColor(ink.link)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
