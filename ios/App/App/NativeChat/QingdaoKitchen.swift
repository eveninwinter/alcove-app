import SwiftUI
import WebKit

// MARK: - 1118 #5623–5667 晴岛厨房：他掌勺，她打下手
// 后台 alcove-independent/kitchen.py（/api/farm/kitchen）；上半块画面是网页 farm/kitchen.html（跟晴岛同一套像素）。
// - 锅在烧：App 里任何页面都浮着一扇大浮窗（几乎跟屏幕一样宽、横的，能拖），点一下进上下分屏。
// - 上下分屏：上面是厨房近景（「看他」）或岛上的她（「看我」，farm/?mini=1），下面是打下手的面板，能收起来（收起＝回到浮窗）。
// - 聊天页：他开锅时落一张做饭小卡（[KITCHEN_CARD]），点了也进分屏。
// 面板照晴岛小手机那套：深紫红粗描边、粉顶、薄荷绿、奶白，饱和度往灰里压一点（#5626）。

struct KitchenBatch: Identifiable, Equatable {
    let id: String
    let name: String
    let qty: Int
    let fresh: String      // fresh / ok / old / bad
    let freshZh: String
}

struct KitchenPot: Equatable {
    let id: String
    let dish: String
    let ask: String
    let askN: Int
    let step: Int
    let steps: [String]
    let task: String?       // hand / taste / bowls
    let fireOn: Bool
    let done: Bool
    let auto: Bool
    let resultName: String?
    let quality: String?
    let weird: Bool
    let bookID: String?
    let leftGame: Double
    let bubble: String?
}

struct KitchenLeftover: Identifiable, Equatable {
    let id: String
    let dish: String
    let note: String
}

/// 1118 #5675 吧台上那一杯（alcove-independent/bar.py）
struct BarGlass: Equatable {
    let id: String
    let want: String
    let base: String
    let method: String
    let step: Int
    let stepKey: String
    let steps: [String]
    let task: String?        // glass / bottle / ice / garnish
    let gotGlass: String?
    let shakes: Int
    let done: Bool
    let auto: Bool
    let cheered: Bool
    let resultKey: String?
    let resultName: String?
    let resultKind: String?  // classic / hidden / bad / custom
    let first: Bool
    let start: Double
}

/// 酒柜里的一格
struct BarCell: Identifiable, Equatable {
    let id: String           // key，图片 /farm/bar/glass/<key>.png（没调过的用 _lock）
    let name: String?
    let group: String        // classic / hidden / bad / custom
    let got: Bool
    let count: Int
    let note: String
}

/// 菜谱本里的一道
struct KitchenBookEntry: Identifiable, Equatable {
    let id: String
    let name: String?
    let weird: Bool
    let ings: [String]
    let colors: [String]
    let count: Int
    let taste: [String: Int]
    let salt: String
    let notes: [String]
    let left: Int
    let first: Double
    let namedBy: String
}

/// 聊天页调酒小卡（bar.py 开调时落库）
struct BarChatCard: Decodable, Equatable {
    let glass: String
    let want: String
    let en: String?
}

/// 聊天页那张小卡（kitchen.py 开锅时落库）
struct KitchenChatCard: Decodable, Equatable {
    let pot: String
    let dish: String
    let ings: [String]?
}

@MainActor
final class KitchenStore: ObservableObject {
    static let shared = KitchenStore()
    @Published var pot: KitchenPot?
    @Published var fridge: [KitchenBatch] = []
    @Published var leftovers: [KitchenLeftover] = []
    @Published var speed = 1
    @Published var splitOpen = false
    @Published var glass: BarGlass?
    @Published var barCells: [BarCell] = []
    @Published var barCustom: [BarCell] = []
    @Published var hiddenLeft = 0
    @Published var barGot = 0
    @Published var barTotal = 0
    @Published var bottles: [String] = []
    @Published var glassKinds: [String] = []
    @Published var garnishes: [String] = []
    @Published var book: [KitchenBookEntry] = []
    @Published var potStart: Double = 0
    /// 1127 #6239 调酒屋上班接单（shift.py）
    @Published var shift: ShiftInfo?
    @Published var shiftBook: [ShiftPage] = []
    @Published var shiftRep: Double?
    var serverOffset: Double = 0
    private weak var splitHost: UIViewController?
    private(set) var fetchedAt = Date()
    private var loop: Task<Void, Never>?
    /// 她在浮窗上点了叉：这一锅不再浮（下一锅照样出来）
    private var closedPot: String? {
        get { UserDefaults.standard.string(forKey: "kitchen.closedPot") }
        set { UserDefaults.standard.set(newValue, forKey: "kitchen.closedPot") }
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let open = self?.splitOpen ?? false
                try? await Task.sleep(nanoseconds: UInt64((open ? 1.5 : 4.0) * 1_000_000_000))
            }
        }
    }

    func refresh() async {
        if let o = try? await AlcoveAPI.getRaw("/api/farm/kitchen") { apply(o) }
        if let b = try? await AlcoveAPI.getRaw("/api/farm/bar") { applyBar(b) }
        if let sh = try? await AlcoveAPI.getRaw("/api/farm/shift") { applyShift(sh) }
        syncFloating()
    }

    @discardableResult
    func actBar(_ body: [String: Any]) async -> [String: Any]? {
        let r = try? await AlcoveAPI.postRaw("/api/farm/bar", body: body)
        await refresh()
        return r
    }

    @discardableResult
    func actShift(_ body: [String: Any]) async -> [String: Any]? {
        let r = try? await AlcoveAPI.postRaw("/api/farm/shift", body: body)
        await refresh()
        return r
    }

    /// 现在该看哪边：他在上班 → 上班；吧台上有一杯、而且比锅里那锅晚开 → 吧台
    var place: String {
        if shift != nil { return "shift" }
        guard let g = glass else { return "kitchen" }
        if pot == nil || g.start >= potStart { return "bar" }
        return "kitchen"
    }
    private var activeID: String? { place == "shift" ? shift?.id : (place == "bar" ? glass?.id : pot?.id) }

    private func applyShift(_ o: [String: Any]) {
        let num: (Any?) -> Double = { ($0 as? NSNumber)?.doubleValue ?? 0 }
        serverOffset = num(o["now"]) - Date().timeIntervalSince1970
        shiftRep = (o["rep"] as? NSNumber)?.doubleValue
        shiftBook = (o["book"] as? [[String: Any]] ?? []).compactMap { pg in
            guard let id = pg["id"] as? String else { return nil }
            let rows = (pg["orders"] as? [[String: Any]] ?? []).enumerated().map { i, r in
                ShiftOrderRow(id: "\(id)-\(i)", cust: r["cust"] as? String ?? "", her: r["her"] as? Bool ?? false,
                              said: r["said"] as? String ?? "", ask: r["ask"] as? String, ans: r["ans"] as? String,
                              drink: r["drink"] as? String, mishap: r["mishap"] as? String, words: r["words"] as? String,
                              stars: r["stars"] as? Int, money: (r["money"] as? Int ?? 0) + (r["tip"] as? Int ?? 0),
                              reply: r["reply"] as? String, herComment: r["her_comment"] as? String, angry: r["angry"] as? Bool ?? false)
            }
            return ShiftPage(id: id, start: num(pg["start"]), earned: pg["earned"] as? Int ?? 0,
                             avg: (pg["avg"] as? NSNumber)?.doubleValue, orders: rows)
        }
        guard o["open"] as? Bool == true, let sh = o["shift"] as? [String: Any], let id = sh["id"] as? String else { shift = nil; return }
        let custs = (sh["custs"] as? [[String: Any]] ?? []).compactMap { c -> ShiftCust? in
            guard let cid = c["id"] as? String else { return nil }
            let d = c["drink"] as? [String: Any]
            let sv = c["served"] as? [String: Any]
            return ShiftCust(id: cid, name: c["name"] as? String ?? "", who: c["who"] as? String ?? "",
                             regular: c["regular"] as? Bool ?? false, her: c["her"] as? Bool ?? false,
                             said: c["said"] as? String ?? "", ask: c["ask"] as? String, ans: c["ans"] as? String,
                             status: c["status"] as? String ?? "", sat: num(c["sat"]), pat: max(1, num(c["pat"])),
                             drink: d?["name"] as? String, ice: d?["ice"] as? String, mishap: d?["mishap"] as? String,
                             first: d?["first"] as? Bool ?? false, stars: sv?["stars"] as? Int,
                             money: (sv?["money"] as? Int ?? 0) + (sv?["tip"] as? Int ?? 0),
                             reply: sv?["reply"] as? String, herComment: sv?["her_comment"] as? String, bye: c["bye"] as? String)
        }
        shift = ShiftInfo(id: id, max: sh["max"] as? Int ?? 3, earned: sh["earned"] as? Int ?? 0,
                          soldOut: sh["sold_out"] as? [String] ?? [], custs: custs, cur: sh["cur"] as? String,
                          served: sh["served"] as? Int ?? 0, start: num(sh["start"]))
    }

    private func applyBar(_ o: [String: Any]) {
        bottles = o["bottles"] as? [String] ?? []
        glassKinds = o["glasses"] as? [String] ?? []
        garnishes = o["garnish"] as? [String] ?? []
        hiddenLeft = o["hidden_left"] as? Int ?? 0
        barGot = o["got"] as? Int ?? 0
        barTotal = o["total"] as? Int ?? 0
        barCells = (o["menu"] as? [[String: Any]] ?? []).compactMap { m in
            guard let k = m["key"] as? String else { return nil }
            return BarCell(id: k, name: m["name"] as? String, group: m["group"] as? String ?? "classic",
                           got: m["got"] as? Bool ?? false, count: m["count"] as? Int ?? 0, note: m["of"] as? String ?? "")
        }
        barCustom = (o["custom"] as? [[String: Any]] ?? []).compactMap { m in
            guard let k = m["key"] as? String else { return nil }
            return BarCell(id: k, name: m["name"] as? String, group: "custom", got: true, count: m["count"] as? Int ?? 0,
                           note: (m["ings"] as? [String] ?? []).joined(separator: "、"))
        }
        guard let g = o["glass"] as? [String: Any], let id = g["id"] as? String else { glass = nil; return }
        let steps = g["steps"] as? [[String: Any]] ?? []
        let step = g["step"] as? Int ?? 0
        let res = g["result"] as? [String: Any]
        glass = BarGlass(id: id, want: g["want"] as? String ?? "", base: g["base"] as? String ?? "",
                         method: g["method"] as? String ?? "摇", step: step,
                         stepKey: step < steps.count ? (steps[step]["key"] as? String ?? "") : "",
                         steps: steps.map { $0["label"] as? String ?? "" },
                         task: (g["task"] as? [String: Any])?["kind"] as? String,
                         gotGlass: g["got_glass"] as? String, shakes: g["shakes"] as? Int ?? 0,
                         done: g["done"] as? Bool ?? false, auto: g["auto"] as? Bool ?? false,
                         cheered: g["cheered"] as? Bool ?? false,
                         resultKey: res?["key"] as? String, resultName: res?["name"] as? String,
                         resultKind: res?["kind"] as? String, first: res?["first"] as? Bool ?? false,
                         start: (g["start"] as? NSNumber)?.doubleValue ?? 0)
    }

    @discardableResult
    func act(_ body: [String: Any]) async -> [String: Any]? {
        let r = try? await AlcoveAPI.postRaw("/api/farm/kitchen", body: body)
        await refresh()
        return r
    }

    private func apply(_ o: [String: Any]) {
        fetchedAt = Date()
        speed = o["speed"] as? Int ?? 1
        fridge = (o["fridge"] as? [[String: Any]] ?? []).compactMap { b in
            guard let id = b["id"] as? String, let n = b["name"] as? String else { return nil }
            return KitchenBatch(id: id, name: n, qty: b["qty"] as? Int ?? 0,
                                fresh: b["fresh"] as? String ?? "ok", freshZh: b["fresh_zh"] as? String ?? "")
        }
        leftovers = (o["left"] as? [[String: Any]] ?? []).compactMap { x in
            guard let id = x["id"] as? String else { return nil }
            return KitchenLeftover(id: id, dish: x["dish"] as? String ?? "", note: x["note"] as? String ?? "")
        }
        book = (o["book"] as? [[String: Any]] ?? []).compactMap { e in
            guard let id = e["id"] as? String else { return nil }
            let cols = (e["colors"] as? [String: Any] ?? [:]).values.compactMap { $0 as? String }
            return KitchenBookEntry(id: id, name: e["name"] as? String, weird: e["weird"] as? Bool ?? false,
                                    ings: e["ings"] as? [String] ?? [], colors: cols, count: e["count"] as? Int ?? 0,
                                    taste: e["taste"] as? [String: Int] ?? [:], salt: e["salt"] as? String ?? "",
                                    notes: (e["notes"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String },
                                    left: e["left"] as? Int ?? 0, first: (e["first"] as? NSNumber)?.doubleValue ?? 0,
                                    namedBy: e["named_by"] as? String ?? "")
        }
        guard let p = o["pot"] as? [String: Any], let id = p["id"] as? String else { pot = nil; return }
        potStart = (p["start"] as? NSNumber)?.doubleValue ?? 0
        let ask = p["ask"] as? [Any] ?? []
        let steps = (p["steps"] as? [[String: Any]] ?? []).map { $0["label"] as? String ?? "" }
        let task = (p["task"] as? [String: Any])?["kind"] as? String
        let res = p["result"] as? [String: Any]
        let bub = (p["bubble"] as? [String: Any])?["text"] as? String
        pot = KitchenPot(id: id, dish: p["dish"] as? String ?? "",
                         ask: ask.first as? String ?? "", askN: ask.count > 1 ? (ask[1] as? Int ?? 1) : 1,
                         step: p["step"] as? Int ?? 0, steps: steps, task: task,
                         fireOn: p["fire_on"] as? Bool ?? false, done: p["done"] as? Bool ?? false,
                         auto: p["auto"] as? Bool ?? false,
                         resultName: res?["name"] as? String, quality: res?["quality"] as? String,
                         weird: res?["weird"] as? Bool ?? false, bookID: p["book_id"] as? String,
                         leftGame: (p["left_game"] as? NSNumber)?.doubleValue ?? 0, bubble: bub)
    }

    /// 还剩几秒出锅（游戏时间按倍速换成真秒；等她的时候不走）
    var secondsLeft: Double {
        guard let p = pot else { return 0 }
        if p.task != nil || p.done { return p.leftGame / Double(max(1, speed)) }
        return max(0, (p.leftGame - Date().timeIntervalSince(fetchedAt) * Double(speed)) / Double(max(1, speed)))
    }

    func statusLine(_ p: KitchenPot) -> String {
        if p.done { return (p.resultName ?? "一道还没名字的菜") + " · 出锅了" }
        if p.task != nil && !p.auto { return "等你帮忙" }
        return "还有 " + Self.mmss(secondsLeft) + " 出锅"
    }

    static func mmss(_ s: Double) -> String {
        let t = max(0, Int(s.rounded(.up)))
        return String(format: "%02d:%02d", t / 60, t % 60)
    }

    // MARK: 浮窗：锅里有东西、她没开分屏、没点过叉 → 浮着
    func syncFloating() {
        let want = activeID != nil && !splitOpen && closedPot != activeID
            && UIApplication.shared.applicationState == .active
        if want {
            if !FloatingOverlay.shared.isShowing("kitchen") {
                FloatingOverlay.shared.show(id: "kitchen", defaultY: 140) { KitchenFloatView() }
            }
        } else if FloatingOverlay.shared.isShowing("kitchen") {
            FloatingOverlay.shared.hide(id: "kitchen")
        }
    }

    func closeFloating() {
        closedPot = activeID
        syncFloating()
    }

    // MARK: 上下分屏：从 app 最上面那页整页盖上去（共读室、工作室开着也不顶掉谁）
    func openSplit() {
        guard !splitOpen, let win = FloatingOverlay.appWindow(), var top = win.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        splitOpen = true
        syncFloating()
        let host = UIHostingController(rootView: KitchenSplitView())
        host.modalPresentationStyle = .fullScreen
        host.view.backgroundColor = UIColor(KitchenInk.night)
        splitHost = host
        top.present(host, animated: true)
        Task { await refresh() }
    }

    func closeSplit() {
        splitHost?.dismiss(animated: true)
        splitOpen = false
        syncFloating()
    }
}

/// 晴岛小手机那套：深紫红粗描边＋淡粉（#5676 她要可爱、粉一点；#5677「太粉了」→ 白卡、淡粉底，粉只做点缀）
enum KitchenInk {
    static let plum = Color(red: 0.353, green: 0.200, blue: 0.275)        // #5A3346 粗描边、字
    static let pink = Color(red: 1.0, green: 0.718, blue: 0.812)          // #FFB7CF 小飘带、主按钮
    static let pinkDeep = Color(red: 0.957, green: 0.604, blue: 0.725)    // #F49AB9
    static let pinkSoft = Color(red: 1.0, green: 0.910, blue: 0.937)      // #FFE8EF 次按钮
    static let blush = Color(red: 1.0, green: 0.945, blue: 0.961)         // #FFF1F5 他的气泡、新鲜的格子
    static let mint = Color(red: 0.918, green: 0.965, blue: 0.945)        // #EAF6F1
    static let cream = Color.white                                        // 卡片
    static let check1 = Color(red: 1.0, green: 0.969, blue: 0.980)        // #FFF7FA 整页底
    static let check2 = Color(red: 0.953, green: 0.890, blue: 0.918)      // #F3E3EA 没走到的步子
    static let ink = Color(red: 0.353, green: 0.200, blue: 0.275)
    static let inkSoft = Color(red: 0.353, green: 0.200, blue: 0.275).opacity(0.6)
    static let night = Color(red: 0.992, green: 0.933, blue: 0.953)       // #FDEEF3 上半块的底
    static func fresh(_ f: String) -> Color {
        switch f {
        case "fresh": return blush
        case "ok": return Color(red: 0.965, green: 0.941, blue: 1.0)      // 还行：淡紫（不用黄、米黄）
        case "old": return Color(red: 0.984, green: 0.890, blue: 0.910)   // 快坏了：灰粉
        default: return Color(red: 0.902, green: 0.878, blue: 0.890)
        }
    }
}

/// 粉色小飘带（「厨房」「该你了」）：像素小爱心＋白字
struct KitchenRibbon: View {
    let text: String
    var fill: Color = KitchenInk.pink
    var body: some View {
        HStack(spacing: 4) {
            KitchenPixelHeart(on: true, outline: .white, fillColor: .white).frame(width: 9, height: 8)
            Text(text).font(.system(size: 10.5, weight: .heavy, design: .rounded)).foregroundColor(.white)
        }
        .padding(.leading, 6).padding(.trailing, 8).padding(.vertical, 1.5)
        .background(Capsule().fill(fill))
        .overlay(Capsule().stroke(KitchenInk.plum, lineWidth: 1.5))
    }
}

/// 晴岛那颗像素小爱心（7×6 格），亮的粉、暗的灰
struct KitchenPixelHeart: View {
    var on = true
    var outline: Color = KitchenInk.plum
    var fillColor: Color = Color(red: 1.0, green: 0.56, blue: 0.75)
    private static let cells: [(Int, Int)] = [(1,0),(2,0),(4,0),(5,0),(0,1),(1,1),(2,1),(3,1),(4,1),(5,1),(6,1),
                                              (0,2),(1,2),(2,2),(3,2),(4,2),(5,2),(6,2),(1,3),(2,3),(3,3),(4,3),(5,3),(2,4),(3,4),(4,4),(3,5)]
    var body: some View {
        Canvas { ctx, size in
            let u = min(size.width / 7, size.height / 6)
            let set = Set(Self.cells.map { $0.0 * 10 + $0.1 })
            for (x, y) in Self.cells {
                let edge = !set.contains((x - 1) * 10 + y) || !set.contains((x + 1) * 10 + y) || !set.contains(x * 10 + y - 1) || !set.contains(x * 10 + y + 1)
                let c: Color = edge ? (on ? outline : Color(red: 0.78, green: 0.72, blue: 0.75)) : (on ? fillColor : Color(red: 0.95, green: 0.92, blue: 0.93))
                ctx.fill(Path(CGRect(x: CGFloat(x) * u, y: CGFloat(y) * u, width: u + 0.3, height: u + 0.3)), with: .color(c))
            }
        }
    }
}

/// 像素小框：粗描边、小圆角，底下压一道深色当影子（不发光、不渐变）
struct KitchenPixelBox<Content: View>: View {
    var fill: Color = KitchenInk.cream
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(KitchenInk.plum, lineWidth: 2))
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(KitchenInk.plum).offset(y: 2))
    }
}

struct KitchenPixelButton: View {
    let title: String
    var fill: Color = KitchenInk.pink
    var textColor: Color = .white
    var big = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: big ? 13 : 12, weight: .heavy, design: .rounded))
                .foregroundColor(textColor)
                .padding(.horizontal, big ? 16 : 11).padding(.vertical, big ? 6 : 5)
                .frame(maxWidth: big ? .infinity : nil)
                .background(Capsule().fill(fill))
                .overlay(Capsule().stroke(KitchenInk.plum, lineWidth: 2))
                .background(Capsule().fill(KitchenInk.plum).offset(y: 2))
        }
        .buttonStyle(.plain)
    }

}

// MARK: - 网页：厨房近景 / 岛上的她
struct KitchenWebView: UIViewRepresentable {
    let path: String
    var interactive = false
    final class Coordinator { var loaded = "" }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.allowsInlineMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.isOpaque = false
        web.backgroundColor = UIColor(KitchenInk.night)
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.isUserInteractionEnabled = interactive
        load(web, context.coordinator)
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {
        if context.coordinator.loaded != path { load(web, context.coordinator) }
    }
    private func load(_ web: WKWebView, _ c: Coordinator) {
        c.loaded = path
        web.load(URLRequest(url: AlcoveAPI.fullURL(path)))
    }
}

// MARK: - 浮窗（锅在烧，App 里哪一页都浮着；回桌面变画中画是下一批）
struct KitchenFloatView: View {
    @ObservedObject private var store = KitchenStore.shared
    private var width: CGFloat { UIScreen.main.bounds.width - 20 }
    var body: some View {
        ZStack(alignment: .topTrailing) {
            KitchenWebView(path: store.place != "kitchen" ? "/farm/bar.html?bar=1" : "/farm/kitchen.html?bar=1")
                .frame(width: width, height: width * 9 / 16)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(KitchenInk.plum, lineWidth: 2.5))
                .overlay(Color.white.opacity(0.001).onTapGesture { store.openSplit() })
                .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
            Button { store.closeFloating() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(KitchenInk.plum.opacity(0.78)))
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .frame(width: width, height: width * 9 / 16)
    }
}

// MARK: - 上下分屏
struct KitchenSplitView: View {
    @ObservedObject private var store = KitchenStore.shared
    @State private var watchHim = true
    @State private var showSpeed = false
    @State private var naming = false
    @State private var nameText = ""
    @State private var session: String?
    @State private var chat: [(role: String, text: String)] = []
    @State private var draft = ""
    @State private var chatLoop: Task<Void, Never>?
    @State private var showBook = false
    @State private var showCabinet = false
    @State private var showShiftBook = false
    @State private var cardsHeight: CGFloat = 200

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                top(width: geo.size.width)
                    .padding(.top, geo.safeAreaInsets.top + 6)
                    .padding(.bottom, 10)
                    .background(KitchenInk.night)
                panel(height: geo.size.height - geo.size.width * 9 / 16)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .background(KitchenInk.check1.ignoresSafeArea())
        .confirmationDialog("倍速（录视频用）", isPresented: $showSpeed, titleVisibility: .visible) {
            ForEach([1, 10, 60], id: \.self) { s in
                Button(s == store.speed ? "\(s) 倍 ✓" : "\(s) 倍") { Task { await store.act(["do": "speed", "speed": s]) } }
            }
        }
        .alert("给它起个名字", isPresented: $naming) {
            TextField("名字", text: $nameText)
            Button("好") {
                let n = nameText.trimmingCharacters(in: .whitespaces)
                if let id = store.pot?.bookID, !n.isEmpty { Task { await store.act(["do": "name", "id": id, "name": n]) } }
            }
            Button("算了", role: .cancel) {}
        }
        .sheet(isPresented: $showBook) { KitchenBookSheet() }
        .sheet(isPresented: $showCabinet) { BarCabinetSheet() }
        .sheet(isPresented: $showShiftBook) { ShiftBookSheet() }
        .onAppear(perform: startChat)
        .onDisappear(perform: endChat)
    }

    // 上半块：近景小窗（淡粉底上一个圆角框）＋「看他｜看我」＋收起
    private func top(width: CGFloat) -> some View {
        let w = width - 20
        return ZStack(alignment: .top) {
            KitchenWebView(path: watchHim ? (store.place != "kitchen" ? "/farm/bar.html" : "/farm/kitchen.html") : "/farm/?mini=1")
                .frame(width: w, height: w * 9 / 16)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(KitchenInk.plum, lineWidth: 2))
            HStack {
                Button { store.closeSplit() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundColor(KitchenInk.plum)
                        .frame(width: 32, height: 26)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(KitchenInk.plum, lineWidth: 2))
                }
                .buttonStyle(.plain)
                Spacer()
                HStack(spacing: 0) {
                    camChip("看他", on: watchHim) { watchHim = true }
                    camChip("看我", on: !watchHim) { watchHim = false }
                }
                .background(Capsule().fill(Color.white))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(KitchenInk.plum, lineWidth: 2))
            }
            .padding(10)
        }
        .frame(width: width)
    }

    private func camChip(_ t: String, on: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(t)
                .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                .foregroundColor(on ? .white : KitchenInk.plum)
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(on ? Color(red: 1.0, green: 0.77, blue: 0.84) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // 下半块：锅、该你了、留给你的、冰箱、两个按钮（照内容高，太高就在里面滚），小手机铺满剩下的
    private func panel(height: CGFloat) -> some View {
        VStack(spacing: 8) {
            ScrollView {
                VStack(spacing: 9) {
                    if store.place == "shift", let sh = store.shift {
                        ShiftPanel(shift: sh)
                    } else if store.place == "bar", let g = store.glass {
                        BarPanel(glass: g)
                    } else {
                        potCard
                        if let p = store.pot { taskCard(p) }
                        ForEach(store.leftovers) { l in leftoverRow(l) }
                        if store.pot?.task != "hand" { fridgeBox }
                    }
                    HStack(spacing: 10) {
                        if store.place == "shift" {
                            KitchenPixelButton(title: "上班小本子", fill: KitchenInk.cream, textColor: KitchenInk.plum, big: true) { showShiftBook = true }
                        } else {
                            KitchenPixelButton(title: "菜谱本", fill: KitchenInk.cream, textColor: KitchenInk.plum, big: true) { showBook = true }
                        }
                        KitchenPixelButton(title: "酒柜", fill: KitchenInk.pinkSoft, textColor: KitchenInk.plum, big: true) { showCabinet = true }
                    }
                }
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
                .background(GeometryReader { g in Color.clear.preference(key: KitchenCardsHeight.self, value: g.size.height) })
            }
            .frame(height: min(cardsHeight, max(160, height - 230)))
            .onPreferenceChange(KitchenCardsHeight.self) { cardsHeight = $0 }
            chatBox
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }

    private var potCard: some View {
        KitchenPixelBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    KitchenRibbon(text: "厨房")
                    if let p = store.pot {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(store.statusLine(p))
                                .font(.system(size: 11, weight: .heavy, design: .rounded).monospacedDigit())
                                .foregroundColor(KitchenInk.plum)
                                .padding(.horizontal, 8).padding(.vertical, 1)
                                .background(Capsule().fill(Color(red: 1.0, green: 0.95, blue: 0.965)))
                                .overlay(Capsule().stroke(KitchenInk.plum, lineWidth: 1.5))
                        }
                    }
                    if store.speed > 1 {
                        Text("\(store.speed) 倍").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(KitchenInk.inkSoft)
                    }
                    Spacer()
                    Text("✿").font(.system(size: 12)).foregroundColor(KitchenInk.pink)
                }
                if let p = store.pot {
                    Text(p.dish)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(KitchenInk.ink)
                        .onLongPressGesture { showSpeed = true }
                    stepBar(p)
                } else {
                    Text("锅是空的")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(KitchenInk.inkSoft)
                        .onLongPressGesture { showSpeed = true }
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 五颗小爱心：走过的亮粉，没走到的灰
    private func stepBar(_ p: KitchenPot) -> some View {
        KitchenHeartSteps(steps: p.steps, step: p.step, done: p.done)
    }

    @ViewBuilder
    private func taskCard(_ p: KitchenPot) -> some View {
        if p.fireOn {
            KitchenPixelButton(title: "火太大了！关小火", fill: Color(red: 0.86, green: 0.44, blue: 0.52), big: true) {
                Task { await store.act(["do": "fire"]) }
            }
        }
        if p.done {
            KitchenPixelBox(fill: KitchenInk.cream) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(p.resultName ?? "还没有名字")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(KitchenInk.ink)
                    Text(["good": "做得好", "ok": "还行", "meh": "一般", "burnt": "糊了"][p.quality ?? ""] ?? "")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(KitchenInk.inkSoft)
                    HStack(spacing: 10) {
                        if p.weird && p.resultName == nil {
                            KitchenPixelButton(title: "我来取", fill: KitchenInk.mint, textColor: KitchenInk.plum) { nameText = ""; naming = true }
                            KitchenPixelButton(title: "让他取") {
                                if let id = p.bookID { Task { await store.act(["do": "ask_name", "id": id]) } }
                            }
                        }
                        KitchenPixelButton(title: "吃") { Task { await store.act(["do": "eat"]) } }
                    }
                }
                .padding(.horizontal, 11).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let t = p.task, !p.auto {
            KitchenPixelBox(fill: KitchenInk.cream) {
                VStack(alignment: .leading, spacing: 10) {
                    KitchenRibbon(text: "该你了")
                    switch t {
                    case "hand": handTask(p)
                    case "taste":
                        Text("尝一口").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(KitchenInk.ink)
                        HStack(spacing: 10) {
                            KitchenPixelButton(title: "淡了", fill: KitchenInk.mint, textColor: KitchenInk.plum) { Task { await store.act(["do": "taste", "v": "淡"]) } }
                            KitchenPixelButton(title: "刚好") { Task { await store.act(["do": "taste", "v": "好"]) } }
                            KitchenPixelButton(title: "咸了", fill: KitchenInk.check2, textColor: KitchenInk.plum) { Task { await store.act(["do": "taste", "v": "咸"]) } }
                        }
                    default:
                        KitchenPixelButton(title: "摆好碗筷", big: true) { Task { await store.act(["do": "bowls"]) } }
                    }
                }
                .padding(.horizontal, 11).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 递食材：冰箱里每一批一个格子，挑哪一批要紧（新鲜的做得好，递错了出怪菜）
    private func handTask(_ p: KitchenPot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("递\(p.ask) ×\(p.askN)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(KitchenInk.ink)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 5)], spacing: 6) {
                ForEach(store.fridge.filter { $0.fresh != "bad" }) { b in
                    Button { Task { await store.act(["do": "hand", "batch": b.id]) } } label: {
                        VStack(spacing: 3) {
                            Text(b.name).font(.system(size: 11.5, weight: .heavy, design: .rounded)).foregroundColor(KitchenInk.ink)
                            Text("×\(b.qty) · \(b.freshZh)").font(.system(size: 9, design: .rounded)).foregroundColor(KitchenInk.inkSoft)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(KitchenInk.fresh(b.fresh)))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(KitchenInk.plum, lineWidth: 1.5))
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(KitchenInk.plum).offset(y: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 冰箱：每一批几个、新不新鲜（锅空着也能看）
    private var fridgeBox: some View {
        KitchenPixelBox(fill: KitchenInk.cream) {
            VStack(alignment: .leading, spacing: 10) {
                KitchenRibbon(text: "冰箱", fill: Color(red: 0.80, green: 0.74, blue: 0.95))
                if store.fridge.isEmpty {
                    Text("空的").font(.system(size: 14, design: .rounded)).foregroundColor(KitchenInk.inkSoft)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 5)], spacing: 6) {
                        ForEach(store.fridge) { b in
                            VStack(spacing: 3) {
                                Text(b.name).font(.system(size: 11.5, weight: .heavy, design: .rounded)).foregroundColor(KitchenInk.ink)
                                Text("×\(b.qty) · \(b.freshZh)").font(.system(size: 9, design: .rounded)).foregroundColor(KitchenInk.inkSoft)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(KitchenInk.fresh(b.fresh)))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(KitchenInk.plum, lineWidth: 1.5))
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(KitchenInk.plum).offset(y: 1.5))
                        }
                    }
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func leftoverRow(_ l: KitchenLeftover) -> some View {
        KitchenPixelBox(fill: KitchenInk.cream) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(l.dish).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(KitchenInk.ink)
                    Text(l.note).font(.system(size: 12, design: .rounded)).foregroundColor(KitchenInk.inkSoft)
                }
                Spacer()
                KitchenPixelButton(title: "吃掉", fill: KitchenInk.mint, textColor: KitchenInk.plum) {
                    Task { await store.act(["do": "dismiss_left", "id": l.id]) }
                }
            }
            .padding(12)
        }
    }

    // 小手机：跟岛上那只一样走 /api/farm/chat，一次打开＝一段，关掉时聊天页落那张小手机卡
    // #5676 照晴岛小手机的样子：粉头栏＋他的像素头像，两边头像气泡，底下胶囊输入框＋爱心发送；铺满下面剩下的地方
    private var chatBox: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                KitchenAvatar(name: "avatar_cj").frame(width: 21, height: 21)
                Text("陈璟").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundColor(KitchenInk.plum)
                Spacer()
                Text(store.place == "shift" ? "在上班" : store.place == "bar" ? "在吧台" : (store.pot != nil ? "在厨房" : ""))
                    .font(.system(size: 9.5, design: .rounded)).foregroundColor(KitchenInk.inkSoft)
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Color(red: 1.0, green: 0.933, blue: 0.953))
            Rectangle().fill(KitchenInk.plum).frame(height: 2)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(chat.enumerated()), id: \.offset) { i, m in
                            chatRow(m.role == "user", m.text).id(i)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: chat.count) { n in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(n - 1, anchor: .bottom) }
                }
            }
            .frame(maxHeight: .infinity)
            .background(Color.white)
            Rectangle().fill(KitchenInk.plum).frame(height: 2)
            HStack(spacing: 8) {
                TextField("跟他说…", text: $draft)
                    .font(.system(size: 12.5, design: .rounded))
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(Capsule().fill(Color.white))
                    .overlay(Capsule().stroke(KitchenInk.plum, lineWidth: 1.5))
                    .submitLabel(.send)
                    .onSubmit(send)
                Button(action: send) {
                    AsyncImage(url: AlcoveAPI.fullURL("/farm/ui/phone/btn_send.png")) { img in
                        img.interpolation(.none).resizable().scaledToFit()
                    } placeholder: { Circle().fill(KitchenInk.pink) }
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(KitchenInk.check1)
        }
        .frame(minHeight: 180, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(KitchenInk.plum, lineWidth: 2))
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KitchenInk.plum).offset(y: 2))
    }

    private func chatRow(_ mine: Bool, _ text: String) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            if mine { Spacer(minLength: 40) } else { KitchenAvatar(name: "avatar_cj").frame(width: 21, height: 21) }
            Text(text)
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(KitchenInk.ink)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(mine ? Color.white : KitchenInk.blush))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(KitchenInk.plum, lineWidth: 1.5))
            if mine { KitchenAvatar(name: "avatar_me").frame(width: 21, height: 21) } else { Spacer(minLength: 40) }
        }
    }

    private func startChat() {
        Task {
            if let o = try? await AlcoveAPI.postRaw("/api/farm/chat/start", body: [:]) { session = o["session"] as? String }
        }
        chatLoop = Task {
            while !Task.isCancelled {
                if let s = session, let o = try? await AlcoveAPI.getRaw("/api/farm/chat?session=\(s)") {
                    let rows = o["messages"] as? [[String: Any]] ?? []
                    chat = rows.map { (role: $0["role"] as? String ?? "", text: $0["text"] as? String ?? "") }
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func endChat() {
        chatLoop?.cancel()
        if let s = session { Task { _ = try? await AlcoveAPI.postRaw("/api/farm/chat/end", body: ["session": s]) } }
        if KitchenStore.shared.splitOpen { KitchenStore.shared.splitOpen = false; KitchenStore.shared.syncFloating() }
    }

    private func send() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let s = session else { return }
        draft = ""
        chat.append((role: "user", text: t))
        Task { _ = try? await AlcoveAPI.postRaw("/api/farm/chat", body: ["session": s, "text": t]) }
    }
}

/// 晴岛小手机里两个人的像素头像
struct KitchenAvatar: View {
    let name: String
    var body: some View {
        AsyncImage(url: AlcoveAPI.fullURL("/farm/ui/phone/\(name).png")) { img in
            img.interpolation(.none).resizable().scaledToFit()
        } placeholder: { Circle().fill(KitchenInk.blush) }
    }
}

/// 分屏下半块：量卡片那一摞有多高（照内容高，太高才在里面滚）
struct KitchenCardsHeight: PreferenceKey {
    static var defaultValue: CGFloat = 200
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// 五颗小爱心当进度：走过的亮粉、这一步加粗、没到的灰
struct KitchenHeartSteps: View {
    let steps: [String]
    let step: Int
    let done: Bool
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                VStack(spacing: 3) {
                    KitchenPixelHeart(on: done || i <= step).frame(width: 15, height: 13)
                    Text(s).font(.system(size: 9.5, weight: i == step && !done ? .heavy : .regular, design: .rounded))
                        .foregroundColor(done || i <= step ? KitchenInk.ink : KitchenInk.inkSoft)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 2)
    }
}

/// 整页底（#5677 淡粉，不铺格子）
struct KitchenCheck: View {
    var body: some View { KitchenInk.check1 }
}

// MARK: - 聊天页做饭小卡：像素奶白描边框，左边厨房近景小窗，右边菜名、大字倒计时、五格进度
struct KitchenChatMessageCard: View {
    let card: KitchenChatCard
    @ObservedObject private var store = KitchenStore.shared
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""

    var body: some View {
        let dark: Bool = { _ = houseAppearance; return AlcoveAppearance.isDark }()
        let live = store.pot?.id == card.pot ? store.pot : nil
        return Button { store.openSplit() } label: {
            HStack(spacing: 12) {
                AsyncImage(url: AlcoveAPI.fullURL("/farm/kitchen/kitchen_thumb.png")) { img in
                    img.interpolation(.none).resizable().scaledToFill()
                } placeholder: { KitchenInk.check2 }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(KitchenInk.plum, lineWidth: 2))
                VStack(alignment: .leading, spacing: 4) {
                    Text("晴岛厨房")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(dark ? KitchenInk.pink : KitchenInk.pinkDeep)
                    Text(card.dish)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(dark ? KitchenInk.cream : KitchenInk.ink)
                        .lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(live.map { store.statusLine($0) } ?? "做好了")
                            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundColor(dark ? KitchenInk.cream.opacity(0.75) : KitchenInk.inkSoft)
                    }
                    if let p = live {
                        HStack(spacing: 3) {
                            ForEach(0..<max(1, p.steps.count), id: \.self) { i in
                                Rectangle()
                                    .fill(p.done || i < p.step ? KitchenInk.pinkDeep : (i == p.step ? KitchenInk.pink : KitchenInk.check2))
                                    .frame(width: 22, height: 6)
                                    .overlay(Rectangle().stroke(KitchenInk.plum, lineWidth: 1))
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 270)
            .background(RoundedRectangle(cornerRadius: 4).fill(dark ? Color(red: 0.16, green: 0.13, blue: 0.15) : KitchenInk.cream))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(dark ? KitchenInk.cream.opacity(0.8) : KitchenInk.plum, lineWidth: 2.5))
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

}

// MARK: - 1118 #5675 吧台：她打下手的面板
struct BarPanel: View {
    let glass: BarGlass
    @ObservedObject private var store = KitchenStore.shared
    @State private var naming = false
    @State private var nameText = ""
    @State private var showSpeed = false

    var body: some View {
        VStack(spacing: 14) {
            KitchenPixelBox(fill: KitchenInk.cream) {
                VStack(alignment: .leading, spacing: 8) {
                    KitchenRibbon(text: "吧台", fill: Color(red: 0.80, green: 0.74, blue: 0.95))
                    Text(glass.want == "自己调" ? "他自己配的一杯" : glass.want)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(KitchenInk.ink)
                        .onLongPressGesture { showSpeed = true }
                    KitchenHeartSteps(steps: glass.steps, step: glass.step, done: glass.done)
                }
                .padding(.horizontal, 11).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            taskView
        }
        .confirmationDialog("倍速（录视频用）", isPresented: $showSpeed, titleVisibility: .visible) {
            ForEach([1, 10, 60], id: \.self) { s in
                Button("\(s) 倍") { Task { await store.actBar(["do": "speed", "speed": s]) } }
            }
        }
        .alert("给这杯起个名字", isPresented: $naming) {
            TextField("名字", text: $nameText)
            Button("好") {
                let n = nameText.trimmingCharacters(in: .whitespaces)
                if let k = glass.resultKey, !n.isEmpty { Task { await store.actBar(["do": "name", "key": k, "name": n]) } }
            }
            Button("算了", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var taskView: some View {
        if glass.done {
            KitchenPixelBox(fill: KitchenInk.cream) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        if let k = glass.resultKey {
                            AsyncImage(url: AlcoveAPI.fullURL("/farm/bar/glass/\(k).png")) { img in
                                img.interpolation(.none).resizable().scaledToFit()
                            } placeholder: { Color.clear }
                            .frame(width: 56, height: 60)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(glass.resultName ?? "还没有名字")
                                .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundColor(KitchenInk.ink)
                            Text(["classic": "经典", "hidden": "隐藏", "bad": "难喝", "custom": "没对上配方"][glass.resultKind ?? ""] ?? "")
                                .font(.system(size: 12, design: .rounded)).foregroundColor(KitchenInk.inkSoft)
                            if glass.first {
                                Text("第一杯").font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(red: 0.72, green: 0.55, blue: 0.25))
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        if glass.resultKind == "custom" && glass.resultName == nil {
                            KitchenPixelButton(title: "我来取", fill: KitchenInk.mint, textColor: KitchenInk.plum) { nameText = ""; naming = true }
                            KitchenPixelButton(title: "让他取") {
                                if let k = glass.resultKey { Task { await store.actBar(["do": "ask_name", "key": k]) } }
                            }
                        }
                        if !glass.cheered {
                            KitchenPixelButton(title: "碰杯") { Task { await store.actBar(["do": "cheers"]) } }
                        }
                        KitchenPixelButton(title: "喝掉", fill: KitchenInk.check2, textColor: KitchenInk.plum) { Task { await store.actBar(["do": "drink"]) } }
                    }
                }
                .padding(.horizontal, 11).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if glass.stepKey == "shake" {
            KitchenPixelButton(title: glass.method == "摇" ? "一起摇！（\(glass.shakes)）" : (glass.method == "搅" ? "一起搅（\(glass.shakes)）" : "慢慢兑（\(glass.shakes)）"), big: true) {
                Task { await store.actBar(["do": "shake"]) }
            }
        } else if let t = glass.task, !glass.auto {
            KitchenPixelBox(fill: KitchenInk.cream) {
                VStack(alignment: .leading, spacing: 10) {
                    KitchenRibbon(text: "该你了")
                    switch t {
                    case "glass": choices("挑杯子", store.glassKinds, kind: "glass")
                    case "bottle": choices("递\(glass.base)", store.bottles, kind: "bottle")
                    case "ice": choices("加冰", ["少冰", "正常", "多冰"], kind: "ice")
                    default: choices("装饰", store.garnishes, kind: "garnish")
                    }
                }
                .padding(.horizontal, 11).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func choices(_ title: String, _ items: [String], kind: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(KitchenInk.ink)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 5)], spacing: 6) {
                ForEach(items, id: \.self) { v in
                    Button { Task { await store.actBar(["do": kind, "v": v]) } } label: {
                        Text(v).font(.system(size: 11.5, weight: .heavy, design: .rounded)).foregroundColor(KitchenInk.ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(KitchenInk.plum, lineWidth: 1.5))
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(KitchenInk.plum).offset(y: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - 酒柜（深色吧台那套：木框、黄铜线、琥珀暗光）
enum BarInk {
    static let night = Color(red: 0.09, green: 0.06, blue: 0.10)
    static let wood = Color(red: 0.23, green: 0.14, blue: 0.12)
    static let inner = Color(red: 0.13, green: 0.10, blue: 0.16)
    static let brass = Color(red: 0.79, green: 0.63, blue: 0.38)
    static let text = Color(red: 0.95, green: 0.88, blue: 0.80)
    static let dim = Color(red: 0.55, green: 0.50, blue: 0.62)
    static let pink = Color(red: 1.0, green: 0.74, blue: 0.86)
}

struct BarCabinetSheet: View {
    @ObservedObject private var store = KitchenStore.shared
    @State private var naming: BarCell?
    @State private var nameText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("酒柜 · HOUSE CABINET").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(BarInk.text)
                    Spacer()
                    Text("\(store.barGot) / \(store.barTotal)").font(.system(size: 13, design: .rounded).monospacedDigit()).foregroundColor(BarInk.dim)
                }
                shelf("经典", store.barCells.filter { $0.group == "classic" })
                if store.barCells.contains(where: { $0.group == "hidden" }) {
                    shelf("隐藏", store.barCells.filter { $0.group == "hidden" })
                }
                if store.hiddenLeft > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill").font(.system(size: 12)).foregroundColor(BarInk.brass)
                        Text("隐藏 × \(store.hiddenLeft)").font(.system(size: 13, design: .rounded)).foregroundColor(BarInk.pink)
                    }
                }
                shelf("难喝", store.barCells.filter { $0.group == "bad" })
                if !store.barCustom.isEmpty { shelf("起名的", store.barCustom) }
            }
            .padding(18)
        }
        .background(BarInk.night.ignoresSafeArea())
        .alert("给这杯起个名字", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("名字", text: $nameText)
            Button("好") {
                let n = nameText.trimmingCharacters(in: .whitespaces)
                if let c = naming, !n.isEmpty { Task { await store.actBar(["do": "name", "key": c.id, "name": n]) } }
                naming = nil
            }
            Button("算了", role: .cancel) { naming = nil }
        }
        .presentationDetents([.large])
    }

    private func shelf(_ title: String, _ cells: [BarCell]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(BarInk.brass)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 6)], spacing: 10) {
                ForEach(cells) { c in cell(c) }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 4).fill(BarInk.inner))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(BarInk.wood, lineWidth: 4))
            .overlay(Rectangle().fill(BarInk.brass).frame(height: 3), alignment: .bottom)
        }
    }

    private func cell(_ c: BarCell) -> some View {
        VStack(spacing: 4) {
            AsyncImage(url: AlcoveAPI.fullURL("/farm/bar/glass/\(c.id)\(c.got ? "" : "_lock").png")) { img in
                img.interpolation(.none).resizable().scaledToFit()
            } placeholder: { Color.clear }
            .frame(width: 56, height: 60)
            .overlay(Text(c.got ? "" : "?").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(BarInk.dim))
            Text(c.got ? (c.name ?? "还没有名字") : "？？？")
                .font(.system(size: 11, weight: c.got ? .semibold : .regular, design: .rounded))
                .foregroundColor(c.got ? BarInk.text : BarInk.dim)
                .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.7)
            if c.group == "custom" && c.name == nil {
                HStack(spacing: 6) {
                    Button("我来取") { nameText = ""; naming = c }.foregroundColor(BarInk.pink)
                    Button("让他取") { Task { await store.actBar(["do": "ask_name", "key": c.id]) } }.foregroundColor(BarInk.brass)
                }
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 菜谱本（小手机那套：奶白纸、深紫红描边）
struct KitchenBookSheet: View {
    @ObservedObject private var store = KitchenStore.shared
    @State private var naming: KitchenBookEntry?
    @State private var nameText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("菜谱本").font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundColor(KitchenInk.ink)
                    Spacer()
                    Text("\(store.book.count) 道").font(.system(size: 13, design: .rounded)).foregroundColor(KitchenInk.inkSoft)
                }
                let dishes = store.book.filter { !$0.weird }, weird = store.book.filter { $0.weird }
                if !dishes.isEmpty {
                    Text("做过的菜").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(KitchenInk.pinkDeep)
                    ForEach(dishes) { e in page(e) }
                }
                if !weird.isEmpty {
                    Text("怪菜").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(KitchenInk.pinkDeep)
                    ForEach(weird) { e in page(e) }
                }
                if store.book.isEmpty {
                    Text("空的").font(.system(size: 14, design: .rounded)).foregroundColor(KitchenInk.inkSoft)
                }
            }
            .padding(18)
        }
        .background(KitchenCheck().ignoresSafeArea())
        .alert("给这道起个名字", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("名字", text: $nameText)
            Button("好") {
                let n = nameText.trimmingCharacters(in: .whitespaces)
                if let e = naming, !n.isEmpty { Task { await store.act(["do": "name", "id": e.id, "name": n]) } }
                naming = nil
            }
            Button("算了", role: .cancel) { naming = nil }
        }
        .presentationDetents([.large])
    }

    private func page(_ e: KitchenBookEntry) -> some View {
        KitchenPixelBox(fill: KitchenInk.cream) {
            HStack(alignment: .top, spacing: 12) {
                KitchenPlate(colors: e.colors).frame(width: 64, height: 40)
                VStack(alignment: .leading, spacing: 5) {
                    Text(e.name ?? "还没有名字").font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundColor(KitchenInk.ink)
                    Text("做过 \(e.count) 次 · " + e.ings.joined(separator: "、"))
                        .font(.system(size: 11.5, design: .rounded)).foregroundColor(KitchenInk.inkSoft)
                    if !e.taste.isEmpty {
                        HStack(spacing: 8) {
                            ForEach([("淡", "淡了"), ("好", "刚好"), ("咸", "咸了")], id: \.0) { k, label in
                                if let n = e.taste[k], n > 0 {
                                    Text("\(label) \(n)").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(KitchenInk.plum)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(RoundedRectangle(cornerRadius: 3).fill(k == "好" ? KitchenInk.pink.opacity(0.6) : KitchenInk.mint.opacity(0.7)))
                                }
                            }
                        }
                    }
                    if !e.salt.isEmpty { Text(e.salt).font(.system(size: 12, design: .rounded)).foregroundColor(KitchenInk.ink) }
                    if e.left > 0 { Text("给曈曈留过 \(e.left) 次").font(.system(size: 11.5, design: .rounded)).foregroundColor(KitchenInk.inkSoft) }
                    ForEach(e.notes, id: \.self) { n in
                        Text(n).font(.system(size: 12.5, design: .rounded)).foregroundColor(KitchenInk.ink)
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 4).fill(KitchenInk.check1))
                    }
                    if e.weird && e.name == nil {
                        HStack(spacing: 10) {
                            KitchenPixelButton(title: "我来取", fill: KitchenInk.mint, textColor: KitchenInk.plum) { nameText = ""; naming = e }
                            KitchenPixelButton(title: "让他取") { Task { await store.act(["do": "ask_name", "id": e.id]) } }
                        }
                    } else if e.weird && e.namedBy == "ji" {
                        Text("曈曈 起").font(.system(size: 11, design: .rounded)).foregroundColor(KitchenInk.inkSoft)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
        }
    }
}

/// 一只白盘子，上面几小块菜（颜色照用了的食材）
struct KitchenPlate: View {
    let colors: [String]
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let plate = Path(ellipseIn: CGRect(x: 2, y: h * 0.25, width: w - 4, height: h * 0.62))
            ctx.fill(plate, with: .color(.white))
            ctx.stroke(plate, with: .color(KitchenInk.plum), lineWidth: 2)
            let cols = colors.isEmpty ? ["#e8483f"] : colors
            let pts: [(CGFloat, CGFloat)] = [(-0.22, -0.05), (-0.08, -0.12), (0.06, -0.06), (0.18, -0.1), (-0.14, 0.05), (0.0, 0.03), (0.14, 0.04)]
            for (i, p) in pts.enumerated() {
                let r = CGRect(x: w / 2 + p.0 * w - 4, y: h * 0.52 + p.1 * h - 3, width: 8, height: 6)
                ctx.fill(Path(r), with: .color(Color(kitchenHex: cols[i % cols.count])))
            }
        }
    }
}

extension Color {
    /// "#e8483f" → Color
    init(kitchenHex s: String) {
        let h = s.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt64(h, radix: 16) ?? 0xcccccc
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

// MARK: - 聊天页调酒小卡：深紫底、粉色细描边，左边吧台近景，右边酒名
struct BarChatMessageCard: View {
    let card: BarChatCard
    @ObservedObject private var store = KitchenStore.shared

    var body: some View {
        let live = store.glass?.id == card.glass ? store.glass : nil
        return Button { store.openSplit() } label: {
            HStack(spacing: 12) {
                AsyncImage(url: AlcoveAPI.fullURL("/farm/bar/bar_thumb.png")) { img in
                    img.interpolation(.none).resizable().scaledToFill()
                } placeholder: { BarInk.inner }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(BarInk.brass, lineWidth: 2))
                VStack(alignment: .leading, spacing: 4) {
                    Text("调酒屋").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(BarInk.brass)
                    Text(card.want == "自己调" ? "他自己配的一杯" : card.want)
                        .font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundColor(BarInk.pink).lineLimit(1)
                    if let en = card.en, !en.isEmpty {
                        Text(en).font(.system(size: 12, design: .serif).italic()).foregroundColor(BarInk.dim)
                    }
                    Text(status(live))
                        .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(BarInk.text.opacity(0.8))
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 270)
            .background(RoundedRectangle(cornerRadius: 4).fill(BarInk.night))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(BarInk.pink.opacity(0.85), lineWidth: 2))
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func status(_ g: BarGlass?) -> String {
        guard let g else { return "调好了" }
        if g.done { return (g.resultName ?? "还没有名字") + " · 调好了" }
        if g.task != nil && !g.auto { return "等你帮忙" }
        return g.steps.indices.contains(g.step) ? g.steps[g.step] : ""
    }
}

// MARK: - 1127 #6234–6239 调酒屋上班接单（alcove-independent/shift.py）
// 他开店，客人一个个进店说一句心情，他问一句、做、端上去，客人打星给钱；每单截图＋小票自己落进聊天页。
// ‼️她不打下手（#6236）：这里只看。她能做的只有当客人——点一杯、回他那一句、喝完自己打星写评价。

struct ShiftCust: Identifiable, Equatable {
    let id: String
    let name: String
    let who: String
    let regular: Bool
    let her: Bool
    let said: String
    let ask: String?
    let ans: String?
    let status: String      // waiting / making / made / paid / angry / wait_rate / rated
    let sat: Double
    let pat: Double
    let drink: String?
    let ice: String?
    let mishap: String?
    let first: Bool
    let stars: Int?
    let money: Int
    let reply: String?
    let herComment: String?
    let bye: String?
}

struct ShiftInfo: Equatable {
    let id: String
    let max: Int
    let earned: Int
    let soldOut: [String]
    let custs: [ShiftCust]
    let cur: String?
    let served: Int
    let start: Double
}

struct ShiftOrderRow: Identifiable, Equatable {
    let id: String
    let cust: String
    let her: Bool
    let said: String
    let ask: String?
    let ans: String?
    let drink: String?
    let mishap: String?
    let words: String?
    let stars: Int?
    let money: Int
    let reply: String?
    let herComment: String?
    let angry: Bool
}

struct ShiftPage: Identifiable, Equatable {
    let id: String
    let start: Double
    let earned: Int
    let avg: Double?
    let orders: [ShiftOrderRow]
}

/// 聊天页上班小卡（shift.py 开店时落库）
struct ShiftChatCard: Decodable, Equatable {
    let shift: String
    let shop: String?
}

/// 小星星：亮的金、暗的灰
struct ShiftStars: View {
    let n: Int
    var size: CGFloat = 11
    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: "star.fill").font(.system(size: size))
                    .foregroundColor(i < n ? Color(red: 0.95, green: 0.74, blue: 0.25) : Color(red: 0.85, green: 0.80, blue: 0.83))
            }
        }
    }
}

struct ShiftPanel: View {
    let shift: ShiftInfo
    @ObservedObject private var store = KitchenStore.shared
    @State private var ordering = false
    @State private var orderText = ""
    @State private var answerText = ""
    @State private var rateStars = 5
    @State private var rateText = ""

    private var cur: ShiftCust? { shift.custs.first { $0.id == shift.cur } }
    private var queue: [ShiftCust] { shift.custs.filter { ["waiting", "making", "made"].contains($0.status) && $0.id != shift.cur } }
    private var done: [ShiftCust] { shift.custs.filter { ["paid", "angry", "rated"].contains($0.status) } }
    private var herWaitRate: ShiftCust? { shift.custs.first { $0.her && $0.status == "wait_rate" } }
    private var herIn: Bool { shift.custs.contains { $0.her && !["rated", "paid", "angry", "gone"].contains($0.status) } }

    var body: some View {
        VStack(spacing: 12) {
            KitchenPixelBox(fill: KitchenInk.cream) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        KitchenRibbon(text: "上班中", fill: Color(red: 0.80, green: 0.74, blue: 0.95))
                        Text("调酒屋").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundColor(KitchenInk.plum)
                        Spacer()
                        Text("G \(shift.earned)").font(.system(size: 12, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundColor(Color(red: 0.69, green: 0.48, blue: 0.06))
                    }
                    Text("已经招呼了 \(shift.served) / \(shift.max) 位" + (shift.soldOut.isEmpty ? "" : " · 今天卖完：" + shift.soldOut.joined(separator: "、")))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded)).foregroundColor(KitchenInk.inkSoft)
                }
                .padding(.horizontal, 11).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let c = cur { curCard(c) } else {
                KitchenPixelBox(fill: KitchenInk.cream) {
                    Text(shift.served >= shift.max ? "这班的客人都招呼完了" : "吧台前还没人，下一位快到了")
                        .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(KitchenInk.inkSoft)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let h = herWaitRate { rateCard(h) }
            ForEach(queue) { q in
                HStack {
                    Text("门口在等：" + q.name).font(.system(size: 12.5, weight: .bold, design: .rounded)).foregroundColor(KitchenInk.plum)
                    Spacer()
                    if !q.her { patience(q).frame(width: 90) }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(KitchenInk.plum, lineWidth: 1.5))
            }
            ForEach(done.reversed()) { d in doneRow(d) }
            if !herIn {
                KitchenPixelButton(title: "我也点一杯", fill: KitchenInk.pink, big: true) { orderText = ""; ordering = true }
            }
        }
        .alert("想喝什么样的？", isPresented: $ordering) {
            TextField("写一句心情", text: $orderText)
            Button("点") {
                let t = orderText.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { Task { await store.actShift(["do": "order", "text": t]) } }
            }
            Button("算了", role: .cancel) {}
        } message: { Text("像客人那样说一句，他来猜。这杯你自己打分") }
    }

    private func curCard(_ c: ShiftCust) -> some View {
        KitchenPixelBox(fill: KitchenInk.cream) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(c.her ? "你" : c.name).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundColor(KitchenInk.ink)
                    if c.regular { tag("熟客") }
                    if !c.her && !c.who.isEmpty { Text(c.who).font(.system(size: 11, design: .rounded)).foregroundColor(KitchenInk.inkSoft) }
                    Spacer()
                }
                Text("“\(c.said)”").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(KitchenInk.plum.opacity(0.85))
                if let q = c.ask {
                    Text("问：“\(q)”" + (c.ans.map { "  答：“\($0)”" } ?? ""))
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundColor(KitchenInk.ink)
                }
                if c.her, c.ask != nil, c.ans == nil {
                    HStack(spacing: 8) {
                        TextField("回他一句", text: $answerText)
                            .font(.system(size: 13, design: .rounded))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(KitchenInk.blush))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(KitchenInk.plum, lineWidth: 1.5))
                        KitchenPixelButton(title: "回") {
                            let t = answerText.trimmingCharacters(in: .whitespaces)
                            answerText = ""
                            if !t.isEmpty { Task { await store.actShift(["do": "answer", "text": t]) } }
                        }
                    }
                }
                if let d = c.drink {
                    HStack(spacing: 6) {
                        Text((c.status == "making" ? "在做：" : "做好了：") + d + ((c.ice ?? "正常") == "正常" ? "" : " · " + (c.ice ?? "")))
                            .font(.system(size: 12.5, weight: .bold, design: .rounded)).foregroundColor(KitchenInk.ink)
                        if c.first { tag("第一次做") }
                    }
                    if let m = c.mishap, c.status != "making" {
                        Text("失手：" + m).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(Color(red: 0.75, green: 0.38, blue: 0.50))
                    }
                }
                if !c.her { patience(c) }
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rateCard(_ h: ShiftCust) -> some View {
        KitchenPixelBox(fill: KitchenInk.blush) {
            VStack(alignment: .leading, spacing: 8) {
                Text("你的那杯：" + (h.drink ?? "他自己配的")).font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundColor(KitchenInk.ink)
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { i in
                        Button { rateStars = i } label: {
                            Image(systemName: "star.fill").font(.system(size: 22))
                                .foregroundColor(i <= rateStars ? Color(red: 0.95, green: 0.74, blue: 0.25) : Color(red: 0.85, green: 0.80, blue: 0.83))
                        }.buttonStyle(.plain)
                    }
                }
                TextField("写一句评价（可以不写）", text: $rateText)
                    .font(.system(size: 13, design: .rounded))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(KitchenInk.plum, lineWidth: 1.5))
                KitchenPixelButton(title: "打好了", big: true) {
                    let t = rateText; rateText = ""
                    Task { await store.actShift(["do": "rate", "stars": rateStars, "comment": t]) }
                }
            }
            .padding(11).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func doneRow(_ d: ShiftCust) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(d.her ? "你" : d.name).font(.system(size: 12.5, weight: .heavy, design: .rounded)).foregroundColor(KitchenInk.plum)
                Text(d.status == "angry" ? "等太久，走了" : (d.drink ?? "他自己配的"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(KitchenInk.inkSoft)
                Spacer()
                if let n = d.stars { ShiftStars(n: n) }
                if d.money > 0 { Text("+G \(d.money)").font(.system(size: 11, weight: .heavy, design: .rounded).monospacedDigit()).foregroundColor(Color(red: 0.69, green: 0.48, blue: 0.06)) }
            }
            if let m = d.mishap { Text("失手：" + m).font(.system(size: 11, design: .rounded)).foregroundColor(Color(red: 0.75, green: 0.38, blue: 0.50)) }
            if let r = d.herComment ?? d.reply ?? (d.status == "angry" ? d.bye : nil), !r.isEmpty {
                Text("“\(r)”").font(.system(size: 11.5, design: .rounded)).foregroundColor(KitchenInk.inkSoft)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(KitchenInk.plum, lineWidth: 1.5))
    }

    private func tag(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundColor(.white)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(KitchenInk.pinkDeep))
    }

    /// 耐心条：跟画面上那条一样，绿→黄→红
    private func patience(_ c: ShiftCust) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let now = Date().timeIntervalSince1970 + store.serverOffset
            let v = max(0, min(1, 1 - (now - c.sat) / c.pat))
            HStack(spacing: 6) {
                Text("耐心").font(.system(size: 10.5, weight: .bold, design: .rounded)).foregroundColor(KitchenInk.inkSoft)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.white)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(v > 0.6 ? Color(red: 0.56, green: 0.84, blue: 0.63) : v > 0.3 ? Color(red: 0.95, green: 0.80, blue: 0.42) : Color(red: 0.91, green: 0.42, blue: 0.42))
                            .frame(width: g.size.width * v)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(KitchenInk.plum, lineWidth: 1.5))
                }
                .frame(height: 9)
            }
        }
    }
}

/// 上班小本子：每一班一页
struct ShiftBookSheet: View {
    @ObservedObject private var store = KitchenStore.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("上班小本子").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundColor(KitchenInk.ink)
                    Spacer()
                    if let r = store.shiftRep {
                        Text(String(format: "口碑 ★%.1f", r)).font(.system(size: 12.5, weight: .bold, design: .rounded)).foregroundColor(KitchenInk.inkSoft)
                    }
                }
                if store.shiftBook.isEmpty {
                    Text("还没上过班").font(.system(size: 13, design: .rounded)).foregroundColor(KitchenInk.inkSoft)
                }
                ForEach(store.shiftBook) { pg in page(pg) }
            }
            .padding(18)
        }
        .background(KitchenInk.check1.ignoresSafeArea())
        .presentationDetents([.large])
    }

    private func page(_ pg: ShiftPage) -> some View {
        KitchenPixelBox(fill: KitchenInk.cream) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(Self.fmt(pg.start)).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(KitchenInk.plum)
                    Spacer()
                    if let a = pg.avg { Text(String(format: "平均 ★%.1f", a)).font(.system(size: 11.5, design: .rounded)).foregroundColor(KitchenInk.inkSoft) }
                    Text("G \(pg.earned)").font(.system(size: 12, weight: .heavy, design: .rounded).monospacedDigit()).foregroundColor(Color(red: 0.69, green: 0.48, blue: 0.06))
                }
                ForEach(pg.orders) { o in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(o.her ? "你" : o.cust).font(.system(size: 12.5, weight: .heavy, design: .rounded)).foregroundColor(KitchenInk.ink)
                            Text(o.angry ? "等太久，走了" : (o.drink ?? "他自己配的")).font(.system(size: 12, design: .rounded)).foregroundColor(KitchenInk.inkSoft)
                            Spacer()
                            if let n = o.stars { ShiftStars(n: n, size: 10) }
                        }
                        if !o.said.isEmpty { Text("“\(o.said)”").font(.system(size: 11.5, design: .rounded)).foregroundColor(KitchenInk.plum.opacity(0.8)) }
                        if let q = o.ask { Text("问：“\(q)”" + (o.ans.map { " 答：“\($0)”" } ?? "")).font(.system(size: 11, design: .rounded)).foregroundColor(KitchenInk.inkSoft) }
                        if let m = o.mishap { Text("失手：" + m).font(.system(size: 11, design: .rounded)).foregroundColor(Color(red: 0.75, green: 0.38, blue: 0.50)) }
                        if let w = o.words, !w.isEmpty { Text("他说：“\(w)”").font(.system(size: 11, design: .rounded)).foregroundColor(KitchenInk.inkSoft) }
                        if let r = o.herComment ?? o.reply, !r.isEmpty { Text((o.her ? "你写：" : "客人：") + "“\(r)”").font(.system(size: 11, design: .rounded)).foregroundColor(KitchenInk.inkSoft) }
                    }
                    if o.id != pg.orders.last?.id { Rectangle().fill(KitchenInk.check2).frame(height: 1) }
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    static func fmt(_ t: Double) -> String {
        let f = DateFormatter()
        f.dateFormat = "M月d日 HH:mm"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f.string(from: Date(timeIntervalSince1970: t))
    }
}

/// 聊天页上班小卡：开店时落一张，点了进上下分屏
struct ShiftChatMessageCard: View {
    let card: ShiftChatCard
    @ObservedObject private var store = KitchenStore.shared

    var body: some View {
        let live = store.shift?.id == card.shift ? store.shift : nil
        let page = store.shiftBook.first { $0.id == card.shift }
        return Button { if live != nil { store.openSplit() } } label: {
            HStack(spacing: 12) {
                AsyncImage(url: AlcoveAPI.fullURL("/farm/bar/bar_thumb.png")) { img in
                    img.interpolation(.none).resizable().scaledToFill()
                } placeholder: { BarInk.inner }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(BarInk.brass, lineWidth: 2))
                VStack(alignment: .leading, spacing: 4) {
                    Text("调酒屋").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(BarInk.brass)
                    Text(live != nil ? "他在上班" : "收店了")
                        .font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundColor(BarInk.pink)
                    if let l = live {
                        Text("已经招呼了 \(l.served) / \(l.max) 位 · G \(l.earned)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(BarInk.text.opacity(0.8))
                    } else if let p = page {
                        Text("这班赚了 G \(p.earned)" + (p.avg.map { String(format: " · 平均 ★%.1f", $0) } ?? ""))
                            .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(BarInk.text.opacity(0.8))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 270)
            .background(RoundedRectangle(cornerRadius: 4).fill(BarInk.night))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(BarInk.pink.opacity(0.85), lineWidth: 2))
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}
