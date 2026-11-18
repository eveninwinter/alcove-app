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
        syncFloating()
    }

    @discardableResult
    func actBar(_ body: [String: Any]) async -> [String: Any]? {
        let r = try? await AlcoveAPI.postRaw("/api/farm/bar", body: body)
        await refresh()
        return r
    }

    /// 现在该看哪边：吧台上有一杯、而且比锅里那锅晚开 → 吧台
    var place: String {
        guard let g = glass else { return "kitchen" }
        if pot == nil || g.start >= potStart { return "bar" }
        return "kitchen"
    }
    private var activeID: String? { place == "bar" ? glass?.id : pot?.id }

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

/// 晴岛小手机那套颜色，往灰里压一点
enum KitchenInk {
    static let plum = Color(red: 0.29, green: 0.17, blue: 0.23)           // #4A2C3A 粗描边
    static let pink = Color(red: 0.86, green: 0.66, blue: 0.72)           // 粉顶栏（压灰）
    static let pinkDeep = Color(red: 0.76, green: 0.52, blue: 0.60)
    static let mint = Color(red: 0.68, green: 0.81, blue: 0.76)           // 薄荷绿（压灰）
    static let cream = Color(red: 0.99, green: 0.96, blue: 0.93)          // 奶白
    static let check1 = Color(red: 0.96, green: 0.92, blue: 0.93)
    static let check2 = Color(red: 0.92, green: 0.86, blue: 0.88)
    static let ink = Color(red: 0.29, green: 0.17, blue: 0.23)
    static let inkSoft = Color(red: 0.29, green: 0.17, blue: 0.23).opacity(0.62)
    static let night = Color(red: 0.16, green: 0.13, blue: 0.15)
    static func fresh(_ f: String) -> Color {
        switch f {
        case "fresh": return mint
        case "ok": return Color(red: 0.86, green: 0.84, blue: 0.94)      // 还行：淡紫（不用黄、米黄）
        case "old": return Color(red: 0.93, green: 0.76, blue: 0.80)     // 快坏了：灰粉
        default: return Color(red: 0.70, green: 0.66, blue: 0.68)
        }
    }
}

/// 像素小框：粗描边、小圆角，底下压一道深色当影子（不发光、不渐变）
struct KitchenPixelBox<Content: View>: View {
    var fill: Color = KitchenInk.cream
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .background(RoundedRectangle(cornerRadius: 4).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(KitchenInk.plum, lineWidth: 2.5))
            .background(RoundedRectangle(cornerRadius: 4).fill(KitchenInk.plum.opacity(0.85)).offset(y: 3))
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
                .font(.system(size: big ? 17 : 14, weight: .bold, design: .rounded))
                .foregroundColor(textColor)
                .padding(.horizontal, big ? 18 : 12).padding(.vertical, big ? 11 : 8)
                .frame(maxWidth: big ? .infinity : nil)
                .background(RoundedRectangle(cornerRadius: 4).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(KitchenInk.plum, lineWidth: 2.5))
                .background(RoundedRectangle(cornerRadius: 4).fill(KitchenInk.plum).offset(y: 3))
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
            KitchenWebView(path: store.place == "bar" ? "/farm/bar.html?bar=1" : "/farm/kitchen.html?bar=1")
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

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                top(width: geo.size.width)
                    .padding(.top, geo.safeAreaInsets.top)
                    .background(KitchenInk.night)
                panel
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .background(KitchenCheck().ignoresSafeArea())
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
        .onAppear(perform: startChat)
        .onDisappear(perform: endChat)
    }

    // 上半块：近景小窗＋「看他｜看我」＋收起
    private func top(width: CGFloat) -> some View {
        ZStack(alignment: .top) {
            KitchenWebView(path: watchHim ? (store.place == "bar" ? "/farm/bar.html" : "/farm/kitchen.html") : "/farm/?mini=1")
                .frame(width: width, height: width * 9 / 16)
            HStack {
                Button { store.closeSplit() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 30)
                        .background(RoundedRectangle(cornerRadius: 4).fill(KitchenInk.plum.opacity(0.8)))
                }
                .buttonStyle(.plain)
                Spacer()
                HStack(spacing: 0) {
                    camChip("看他", on: watchHim) { watchHim = true }
                    camChip("看我", on: !watchHim) { watchHim = false }
                }
                .background(RoundedRectangle(cornerRadius: 4).fill(KitchenInk.plum.opacity(0.8)))
            }
            .padding(10)
        }
        .frame(width: width, height: width * 9 / 16)
    }

    private func camChip(_ t: String, on: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(t)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(on ? KitchenInk.plum : .white.opacity(0.85))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 3).fill(on ? KitchenInk.cream : Color.clear))
                .padding(2)
        }
        .buttonStyle(.plain)
    }

    // 下半块：锅、该你了、留给你的、小手机
    private var panel: some View {
        ScrollView {
            VStack(spacing: 14) {
                if store.place == "bar", let g = store.glass {
                    BarPanel(glass: g)
                } else {
                    potCard
                    if let p = store.pot { taskCard(p) }
                    ForEach(store.leftovers) { l in leftoverRow(l) }
                    if store.pot?.task != "hand" { fridgeBox }
                }
                HStack(spacing: 10) {
                    KitchenPixelButton(title: "菜谱本", fill: KitchenInk.cream, textColor: KitchenInk.plum, big: true) { showBook = true }
                    KitchenPixelButton(title: "酒柜", fill: KitchenInk.mint, textColor: KitchenInk.plum, big: true) { showCabinet = true }
                }
                chatBox
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 30)
        }
    }

    private var potCard: some View {
        KitchenPixelBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("厨房")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 3).fill(KitchenInk.pinkDeep))
                    if store.speed > 1 {
                        Text("\(store.speed) 倍").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(KitchenInk.inkSoft)
                    }
                    Spacer()
                }
                if let p = store.pot {
                    Text(p.dish)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(KitchenInk.ink)
                        .onLongPressGesture { showSpeed = true }
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(store.statusLine(p))
                            .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundColor(KitchenInk.ink)
                    }
                    stepBar(p)
                } else {
                    Text("锅是空的")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(KitchenInk.inkSoft)
                        .onLongPressGesture { showSpeed = true }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func stepBar(_ p: KitchenPot) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(p.steps.enumerated()), id: \.offset) { i, s in
                VStack(spacing: 4) {
                    Rectangle()
                        .fill(p.done || i < p.step ? KitchenInk.pinkDeep : (i == p.step ? KitchenInk.pink : KitchenInk.check2))
                        .frame(height: 8)
                        .overlay(Rectangle().stroke(KitchenInk.plum, lineWidth: 1.5))
                    Text(s)
                        .font(.system(size: 10, weight: i == p.step ? .bold : .regular, design: .rounded))
                        .foregroundColor(i == p.step ? KitchenInk.ink : KitchenInk.inkSoft)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
        }
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
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let t = p.task, !p.auto {
            KitchenPixelBox(fill: KitchenInk.cream) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("该你了")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 3).fill(KitchenInk.pinkDeep))
                    switch t {
                    case "hand": handTask(p)
                    case "taste":
                        Text("尝一口").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(KitchenInk.ink)
                        HStack(spacing: 10) {
                            KitchenPixelButton(title: "淡了", fill: KitchenInk.mint, textColor: KitchenInk.plum) { Task { await store.act(["do": "taste", "v": "淡"]) } }
                            KitchenPixelButton(title: "刚好") { Task { await store.act(["do": "taste", "v": "好"]) } }
                            KitchenPixelButton(title: "咸了", fill: KitchenInk.check2, textColor: KitchenInk.plum) { Task { await store.act(["do": "taste", "v": "咸"]) } }
                        }
                    default:
                        KitchenPixelButton(title: "摆好碗筷", big: true) { Task { await store.act(["do": "bowls"]) } }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 递食材：冰箱里每一批一个格子，挑哪一批要紧（新鲜的做得好，递错了出怪菜）
    private func handTask(_ p: KitchenPot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("递\(p.ask) ×\(p.askN)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(KitchenInk.ink)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                ForEach(store.fridge.filter { $0.fresh != "bad" }) { b in
                    Button { Task { await store.act(["do": "hand", "batch": b.id]) } } label: {
                        VStack(spacing: 3) {
                            Text(b.name).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(KitchenInk.ink)
                            Text("×\(b.qty) · \(b.freshZh)").font(.system(size: 11, design: .rounded)).foregroundColor(KitchenInk.inkSoft)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 4).fill(KitchenInk.fresh(b.fresh)))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(KitchenInk.plum, lineWidth: 2))
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
                Text("冰箱")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 3).fill(KitchenInk.mint.opacity(0.95)))
                if store.fridge.isEmpty {
                    Text("空的").font(.system(size: 14, design: .rounded)).foregroundColor(KitchenInk.inkSoft)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                        ForEach(store.fridge) { b in
                            VStack(spacing: 3) {
                                Text(b.name).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(KitchenInk.ink)
                                Text("×\(b.qty) · \(b.freshZh)").font(.system(size: 11, design: .rounded)).foregroundColor(KitchenInk.inkSoft)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 4).fill(KitchenInk.fresh(b.fresh)))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(KitchenInk.plum, lineWidth: 2))
                        }
                    }
                }
            }
            .padding(14)
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
    private var chatBox: some View {
        KitchenPixelBox(fill: KitchenInk.cream) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(chat.suffix(8).enumerated()), id: \.offset) { _, m in
                    HStack {
                        if m.role == "user" { Spacer(minLength: 40) }
                        Text(m.text)
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(KitchenInk.ink)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 4).fill(m.role == "user" ? KitchenInk.pink.opacity(0.55) : KitchenInk.mint.opacity(0.75)))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(KitchenInk.plum, lineWidth: 1.5))
                        if m.role != "user" { Spacer(minLength: 40) }
                    }
                }
                HStack(spacing: 8) {
                    TextField("跟他说…", text: $draft)
                        .font(.system(size: 15, design: .rounded))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(KitchenInk.plum, lineWidth: 2))
                        .submitLabel(.send)
                        .onSubmit(send)
                    KitchenPixelButton(title: "发送", action: send)
                }
            }
            .padding(12)
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

/// 粉白格子底（小手机那套），压灰
struct KitchenCheck: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 14
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(KitchenInk.check1))
            var y: CGFloat = 0, r = 0
            while y < size.height {
                var x: CGFloat = (r % 2 == 0) ? 0 : s
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(KitchenInk.check2))
                    x += s * 2
                }
                y += s; r += 1
            }
        }
    }
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
            .background(RoundedRectangle(cornerRadius: 4).fill(dark ? KitchenInk.night : KitchenInk.cream))
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
                    Text("吧台")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 3).fill(KitchenInk.plum))
                    Text(glass.want == "自己调" ? "他自己配的一杯" : glass.want)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(KitchenInk.ink)
                        .onLongPressGesture { showSpeed = true }
                    HStack(spacing: 4) {
                        ForEach(Array(glass.steps.enumerated()), id: \.offset) { i, s in
                            VStack(spacing: 4) {
                                Rectangle()
                                    .fill(glass.done || i < glass.step ? KitchenInk.plum.opacity(0.75) : (i == glass.step ? KitchenInk.pink : KitchenInk.check2))
                                    .frame(height: 8)
                                    .overlay(Rectangle().stroke(KitchenInk.plum, lineWidth: 1.5))
                                Text(s).font(.system(size: 10, weight: i == glass.step ? .bold : .regular, design: .rounded))
                                    .foregroundColor(i == glass.step ? KitchenInk.ink : KitchenInk.inkSoft)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }
                    }
                }
                .padding(14)
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
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if glass.stepKey == "shake" {
            KitchenPixelButton(title: glass.method == "摇" ? "一起摇！（\(glass.shakes)）" : (glass.method == "搅" ? "一起搅（\(glass.shakes)）" : "慢慢兑（\(glass.shakes)）"), big: true) {
                Task { await store.actBar(["do": "shake"]) }
            }
        } else if let t = glass.task, !glass.auto {
            KitchenPixelBox(fill: KitchenInk.cream) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("该你了")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 3).fill(KitchenInk.pinkDeep))
                    switch t {
                    case "glass": choices("挑杯子", store.glassKinds, kind: "glass")
                    case "bottle": choices("递\(glass.base)", store.bottles, kind: "bottle")
                    case "ice": choices("加冰", ["少冰", "正常", "多冰"], kind: "ice")
                    default: choices("装饰", store.garnishes, kind: "garnish")
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func choices(_ title: String, _ items: [String], kind: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(KitchenInk.ink)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
                ForEach(items, id: \.self) { v in
                    Button { Task { await store.actBar(["do": kind, "v": v]) } } label: {
                        Text(v).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(KitchenInk.ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 4).fill(KitchenInk.check1))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(KitchenInk.plum, lineWidth: 2))
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
