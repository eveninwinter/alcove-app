import SwiftUI
import PhotosUI
import UIKit

// MARK: - 1103 旅行（#4703–4713）原生版
// 一次旅行一整套：《与此同时》地上的钟当列表，进去八页（这一趟 / 准备清单 / 登机牌 / 日程 / 想去 / 票据 / 花销 / 回顾）。
// 样子照日记页：米白底、近黑字、三档灰、发丝线、Pinyon 标题居中、宋体大数字、等宽小号大写、左下小字统计＋右下花体一句。
// 数据走前门 /api/trip/*（alcove-independent/trip_api.py，库 trip.db）；陈璟那边走 /root/rhysel/trip.py，同一份。
// 颜色：封面上传后服务器取色，选中的颜色冲淡铺底色、给背景素材（树/水母/泡沫/山/公式/字百合）上一点色；字和线永远黑白灰。

// MARK: 数据

private func s(_ d: [String: Any], _ k: String) -> String {
    if let v = d[k] as? String { return v }
    if let v = d[k] as? NSNumber { return v.stringValue }
    return ""
}
private func n(_ d: [String: Any], _ k: String) -> Int { (d[k] as? NSNumber)?.intValue ?? Int(s(d, k)) ?? 0 }
private func f(_ d: [String: Any], _ k: String) -> Double { (d[k] as? NSNumber)?.doubleValue ?? 0 }
private func on(_ d: [String: Any], _ k: String) -> Int? { (d[k] as? NSNumber)?.intValue }

struct TripSum {
    var items = 0, done = 0, wishes = 0, tickets = 0, stops = 0, days = 0
    var spent = 0.0
    var status = "before"
    init(_ d: [String: Any] = [:]) {
        items = n(d, "items"); done = n(d, "done"); wishes = n(d, "wishes"); tickets = n(d, "tickets")
        stops = n(d, "stops"); days = n(d, "days"); spent = f(d, "spent"); status = s(d, "status").isEmpty ? "before" : s(d, "status")
    }
}
struct TripItem: Identifiable { let id: Int; let grp, text, note, who, whoDone: String; let done: Bool
    init(_ d: [String: Any]) { id = n(d, "id"); grp = s(d, "grp"); text = s(d, "text"); note = s(d, "note"); who = s(d, "who"); whoDone = s(d, "who_done"); done = n(d, "done") == 1 } }
struct TripStop: Identifiable { let id: Int; let day, time, title, how, dur, note, addr, route, hisLine, hisAt: String
    init(_ d: [String: Any]) { id = n(d, "id"); day = s(d, "day"); time = s(d, "time"); title = s(d, "title"); how = s(d, "how"); dur = s(d, "dur")
        note = s(d, "note"); addr = s(d, "addr"); route = s(d, "route"); hisLine = s(d, "his_line"); hisAt = s(d, "his_at") } }
struct TripWish: Identifiable { let id: Int; let cat, name, note, who: String; let stopId: Int?
    init(_ d: [String: Any]) { id = n(d, "id"); cat = s(d, "cat"); name = s(d, "name"); note = s(d, "note"); who = s(d, "who"); stopId = on(d, "stop_id") } }
struct TripTicket: Identifiable { let id: Int; let kind, title, l1, l2, code, img, at: String
    init(_ d: [String: Any]) { id = n(d, "id"); kind = s(d, "kind"); title = s(d, "title"); l1 = s(d, "l1"); l2 = s(d, "l2"); code = s(d, "code"); img = s(d, "img"); at = s(d, "at") } }
struct TripSpend: Identifiable { let id: Int; let day, cat, text, who: String; let amount: Double; let prepaid: Bool
    init(_ d: [String: Any]) { id = n(d, "id"); day = s(d, "day"); cat = s(d, "cat"); text = s(d, "text"); who = s(d, "who"); amount = f(d, "amount"); prepaid = n(d, "prepaid") == 1 } }
struct TripDayNote { let line, photo: String
    init(_ d: [String: Any]) { line = s(d, "line"); photo = s(d, "photo") } }
struct TripWx { let wx, sunset: String; let hi, lo: Int
    init(_ d: [String: Any]) { wx = s(d, "wx"); sunset = s(d, "sunset"); hi = n(d, "hi"); lo = n(d, "lo") } }

struct Trip: Identifiable {
    let id: Int
    var name = "", nameEn = "", start = "", end = "", fromCity = "", fromCode = "", code = ""
    var cover = "", tint = "", flight = "", boarding = "", seat = "", packedAt = "", stub = "", stubAt = "", letter = ""
    var budget = 0
    var tz = 0.0
    var colors: [String] = []
    var sum = TripSum()
    var dayList: [String] = []
    var items: [TripItem] = []
    var stops: [TripStop] = []
    var wishes: [TripWish] = []
    var tickets: [TripTicket] = []
    var spends: [TripSpend] = []
    var dayNotes: [String: TripDayNote] = [:]
    var weather: [String: TripWx] = [:]

    init(_ d: [String: Any]) {
        id = n(d, "id"); name = s(d, "name"); nameEn = s(d, "name_en"); start = s(d, "start"); end = s(d, "end")
        fromCity = s(d, "from_city"); fromCode = s(d, "from_code"); code = s(d, "code"); cover = s(d, "cover"); tint = s(d, "tint")
        flight = s(d, "flight"); boarding = s(d, "boarding"); seat = s(d, "seat"); packedAt = s(d, "packed_at")
        stub = s(d, "stub"); stubAt = s(d, "stub_at"); letter = s(d, "letter"); budget = n(d, "budget"); tz = f(d, "tz")
        colors = d["colors"] as? [String] ?? []
        sum = TripSum(d["sum"] as? [String: Any] ?? [:])
        dayList = d["day_list"] as? [String] ?? []
        items = (d["items"] as? [[String: Any]] ?? []).map(TripItem.init)
        stops = (d["stops"] as? [[String: Any]] ?? []).map(TripStop.init)
        wishes = (d["wishes"] as? [[String: Any]] ?? []).map(TripWish.init)
        tickets = (d["tickets"] as? [[String: Any]] ?? []).map(TripTicket.init)
        spends = (d["spends"] as? [[String: Any]] ?? []).map(TripSpend.init)
        for (k, v) in d["day_notes"] as? [String: [String: Any]] ?? [:] { dayNotes[k] = TripDayNote(v) }
        for (k, v) in d["weather"] as? [String: [String: Any]] ?? [:] { weather[k] = TripWx(v) }
    }
}

enum TripText {
    static let groups = ["证件", "衣物", "电子", "药品", "预订", "其他"]
    static let wishCats = ["吃", "逛", "买", "坐坐"]
    static let spendCats = ["吃", "交通", "住", "买", "门票", "其他"]
    static let kinds: [(String, String)] = [("flight", "机票"), ("train", "火车"), ("stay", "住宿"), ("entry", "门票"), ("other", "其他")]
    static let hows: [(String, String)] = [("walk", "步行"), ("metro", "地铁"), ("train", "火车"), ("taxi", "打车"), ("bus", "公交"), ("flight", "飞机"), ("boat", "船")]
    static func how(_ k: String) -> String { hows.first { $0.0 == k }?.1 ?? k }
    static func kind(_ k: String) -> String { kinds.first { $0.0 == k }?.1 ?? "其他" }
    static let weekdays = ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"]

    static let ymd: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "Asia/Shanghai"); f.locale = Locale(identifier: "en_US_POSIX"); return f }()
    static func md(_ d: String) -> String { d.count >= 10 ? String(d.dropFirst(5).prefix(5)).replacingOccurrences(of: "-", with: ".") : d }
    static func date(_ d: String) -> Date? { ymd.date(from: d) }
    static func days(_ a: String, _ b: String) -> Int {
        guard let x = date(a), let y = date(b) else { return 0 }
        return Int((y.timeIntervalSince(x) / 86400).rounded())
    }
    /// 北京时间加时差 = 目的地此刻
    static func localNow(_ tz: Double) -> Date { Date().addingTimeInterval(tz * 3600) }
    static func bjComponents(_ d: Date) -> DateComponents {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: d)
    }
    static func ymdBJ(_ d: Date) -> String { ymd.string(from: d) }
    static func hm(_ d: Date) -> String { let c = bjComponents(d); return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0) }
    static func money(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v))"
    }
}

// MARK: 样子

enum TripInk {
    static let ink = Color(red: 0x14/255, green: 0x14/255, blue: 0x14/255)
    static let g1 = Color(red: 0x6E/255, green: 0x6E/255, blue: 0x6E/255)
    static let g2 = Color(red: 0x78/255, green: 0x78/255, blue: 0x78/255)
    static let g3 = Color(red: 0x9A/255, green: 0x9A/255, blue: 0x9A/255)
    static let hl = Color.black.opacity(0.12)
    static let paper = Color(red: 0xFB/255, green: 0xFB/255, blue: 0xF9/255)
    static let plainBG = Color(red: 0xF5/255, green: 0xF5/255, blue: 0xF3/255)

    /// 底色：1103 #4724 不染色了，每页都跟首页一样的米白，不发蓝
    static func bg(_ tint: String) -> Color { plainBG }
    /// 素材不上色（1103 #4727）：原来把素材的白纸也乘成了蓝，正片叠底以后整块图变成带硬边的蓝方块（花销页公式、日程整棵树发蓝）。
    /// 白纸必须保持纯白才会在叠底里消失，所以素材一律原样灰；颜色怎么上等她定
    static func mat(_ tint: String) -> Color { .white }

    static func pin(_ size: CGFloat) -> Font { .custom("PinyonScript-Regular", size: size) }
    static func serif(_ size: CGFloat) -> Font { WindowFont.swiftUI(size) }
    static func mono(_ size: CGFloat = 9) -> Font { .system(size: size, weight: .light, design: .monospaced) }
}

private struct Mono: View {
    let text: String; var size: CGFloat = 9; var color: Color = TripInk.g1
    init(_ t: String, size: CGFloat = 9, color: Color = TripInk.g1) { text = t; self.size = size; self.color = color }
    var body: some View { Text(text.uppercased()).font(TripInk.mono(size)).tracking(0.6).foregroundStyle(color) }
}

/// 侧边栏房间外面整页 ignoresSafeArea，这里拿到的安全区是 0：灵动岛和 Home 横条要自己问 app 主窗让开
@MainActor
enum TripSafe {
    static var top: CGFloat { max(FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0, 20) }
    static var bottom: CGFloat { max(FloatingOverlay.appWindow()?.safeAreaInsets.bottom ?? 0, 10) }
}

private struct Hair: View { var body: some View { Rectangle().fill(TripInk.hl).frame(height: 0.5) } }

/// 背景素材：服务器上的灰度图，正片叠底＋渐隐，颜色跟这次旅行走
private struct TripMat: View {
    let name: String; let tint: String; let opacity: Double
    var body: some View {
        AsyncImage(url: AlcoveAPI.fullURL("/trip/img/\(name).jpg?v=1")) { img in
            img.resizable().colorMultiply(TripInk.mat(tint)).blendMode(.multiply).opacity(opacity)
        } placeholder: { Color.clear }
        .allowsHitTesting(false)
    }
}

private struct TripHeader: View {
    // 返回那一行照檐下：顶上只让状态栏那么高（外面已经 padding 了 TripSafe.top），一行 44 高；
    // 返回键离屏幕左边 6、右边按钮离右边 9，点按区 44×44
    let title: String
    var back: () -> Void
    var menu: (() -> Void)? = nil
    var plus: (() -> Void)? = nil
    var body: some View {
        ZStack {
            Text(title).font(TripInk.pin(25)).foregroundStyle(TripInk.ink)
            HStack(spacing: 0) {
                Button(action: back) {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .regular)).foregroundStyle(TripInk.ink)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                if let plus {      // 1105 参考图：右上一个「＋」加图
                    Button(action: plus) {
                        Text("＋").font(TripInk.serif(20)).foregroundStyle(TripInk.ink).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if let menu {
                    Button(action: menu) {
                        VStack(spacing: 6) { Rectangle().frame(width: 22, height: 1); Rectangle().frame(width: 22, height: 1) }
                            .foregroundStyle(TripInk.ink).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, -16).padding(.trailing, -13)
        }
        .frame(height: 44)
    }
}

private struct TripRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            Hair()
            HStack(alignment: .top, spacing: 12) { content }.padding(.vertical, 12)
        }
        .contentShape(Rectangle())
    }
}

/// 页面骨架：顶上返回那一行固定、中间滚、底下「加一条」＋页脚那行固定（1103 #4727：头尾都不跟着滚）
private struct TripPage<Content: View, Bar: View>: View {
    let title: String
    let tint: String
    var back: () -> Void
    var menu: (() -> Void)? = nil
    var plus: (() -> Void)? = nil
    var foot: (String, String)? = nil
    @ViewBuilder var content: Content
    @ViewBuilder var bar: Bar
    private var hasBar: Bool { Bar.self != EmptyView.self }
    var body: some View {
        let bg = TripInk.bg(tint)
        ZStack {
            bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(.horizontal, 22)
                    .padding(.top, TripSafe.top + 44)
                    .padding(.bottom, (hasBar ? 60 : 0) + (foot == nil ? 0 : 40) + 40 + TripSafe.bottom)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                TripHeader(title: title, back: back, menu: menu, plus: plus)
                    .padding(.horizontal, 22).padding(.top, TripSafe.top)
                    .background(bg)
                LinearGradient(colors: [bg, bg.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 16).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                if hasBar { bar }
                if let foot {
                    HStack(alignment: .lastTextBaseline) {
                        Text(foot.0).font(TripInk.serif(10)).foregroundStyle(TripInk.g2)
                        Spacer()
                        Text(foot.1).font(TripInk.pin(16)).foregroundStyle(TripInk.g2)
                    }
                }
            }
            .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, TripSafe.bottom + 4)
            .frame(maxWidth: .infinity)
            .background(LinearGradient(colors: [bg.opacity(0), bg], startPoint: .top, endPoint: .init(x: 0.5, y: 0.35)).ignoresSafeArea().allowsHitTesting(false))
        }
    }
}

// MARK: 仓库

@MainActor
final class TripStore: ObservableObject {
    @Published var trips: [Trip] = []
    @Published var trip: Trip?
    @Published var toast = ""

    func loadList() async {
        guard let j = try? await AlcoveAPI.getRaw("/api/trip/list") else { say("连不上"); return }
        trips = (j["trips"] as? [[String: Any]] ?? []).map(Trip.init)
    }
    func load(_ id: Int) async {
        guard let j = try? await AlcoveAPI.getRaw("/api/trip/get?id=\(id)"), let t = j["trip"] as? [String: Any] else { say("连不上"); return }
        trip = Trip(t)
    }
    func reload() async { if let t = trip { await load(t.id) } else { await loadList() } }

    @discardableResult
    func post(_ path: String, _ body: [String: Any]) async -> [String: Any] {
        guard let j = try? await AlcoveAPI.postRaw("/api/trip/\(path)", body: body) else { say("连不上"); return [:] }
        if (j["ok"] as? Bool) == false, let e = j["error"] as? String { say(e) }
        return j
    }

    /// 照片：缩到 1600 再传（她网慢）
    func upload(_ data: Data, kind: String) async -> [String: Any] {
        guard let id = trip?.id else { return [:] }
        var body = data
        if let ui = UIImage(data: data) {
            let k = min(1, 1600 / max(ui.size.width, ui.size.height))
            let size = CGSize(width: ui.size.width * k, height: ui.size.height * k)
            let small = UIGraphicsImageRenderer(size: size).image { _ in ui.draw(in: CGRect(origin: .zero, size: size)) }
            body = small.jpegData(compressionQuality: 0.85) ?? data
        }
        var req = URLRequest(url: AlcoveAPI.fullURL("/api/trip/upload?id=\(id)&kind=\(kind)&ext=jpg"))
        req.httpMethod = "POST"
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        say("上传中…")
        guard let res = try? await AlcoveAPI.session.data(for: req),
              let j = try? JSONSerialization.jsonObject(with: res.0) as? [String: Any] else { say("没传上去"); return [:] }
        return j
    }

    func say(_ t: String) {
        toast = t
        Task { try? await Task.sleep(nanoseconds: 1_600_000_000); if toast == t { toast = "" } }
    }
}

// MARK: 入口

enum TripRoute { case list, home, pack, board, day, wish, tick, spend, recap, insp }

enum TripSheet: Identifiable {
    case newTrip, editTrip, menu, delTrip, item(Int?), template, stop(Int?), fromWish, wish(Int?), ticket(Int?), spend, spendRow(Int), dayNote(String)
    var id: String {
        switch self {
        case .newTrip: return "new"
        case .editTrip: return "edit"
        case .menu: return "menu"
        case .delTrip: return "del"
        case .item(let i): return "item\(i ?? 0)"
        case .template: return "tpl"
        case .stop(let i): return "stop\(i ?? 0)"
        case .fromWish: return "fromWish"
        case .wish(let i): return "wish\(i ?? 0)"
        case .ticket(let i): return "ticket\(i ?? 0)"
        case .spend: return "spend"
        case .spendRow(let i): return "spendRow\(i)"
        case .dayNote(let d): return "day\(d)"
        }
    }
}

struct TripRoomView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = TripStore()
    @State private var route: TripRoute = .list
    @State private var day = ""
    @State private var packTab = "全部"
    @State private var wishTab = "全部"
    @State private var sheet: TripSheet?
    @State private var coverItem: PhotosPickerItem?
    @State private var pickingCover = false
    @State private var listLoaded = false
    @State private var inspFrom: TripRoute = .list      // 参考图从哪进来就回哪
    @State private var inspPlace: String?               // 从某一趟主页进来：直接停在同名地点

    var body: some View {
        ZStack {
            page
                // 1103 #4722：照片选择器跟弹单挂在同一个 view 上只会有一个生效（弹单全打不开），选择器挂到里面这层
                .photosPicker(isPresented: $pickingCover, selection: $coverItem, matching: .images)
            if !store.toast.isEmpty {
                VStack { Spacer()
                    Text(store.toast).font(TripInk.serif(12)).foregroundStyle(TripInk.plainBG)
                        .padding(.horizontal, 14).padding(.vertical, 7).background(Capsule().fill(TripInk.ink.opacity(0.9)))
                        .padding(.bottom, 80 + TripSafe.bottom)
                }.transition(.opacity).allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.toast)
        // 1105 她：拼贴页替掉「与此同时」那页——一进旅行直接是正在进行 / 最近要去的那趟；一趟都没有才露出钟那页
        .task { WindowFont.requestSongti(); await store.loadList(); await openDefault() }
        .sheet(item: $sheet) { sh in
            TripSheetView(kind: sh, store: store, day: $day, packTab: packTab, wishTab: wishTab,
                          onPickCover: { pickingCover = true }, onDeleted: { route = .list; store.trip = nil; Task { await store.loadList(); await openDefault() } },
                          onCreated: { id in Task { await open(id) } })
                .presentationDetents([.medium, .large])
                .presentationBackground(TripInk.paper)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tripAskEdit)) { _ in sheet = .editTrip }
        .onReceive(NotificationCenter.default.publisher(for: .tripAskDelete)) { _ in sheet = .delTrip }
        .onReceive(NotificationCenter.default.publisher(for: .tripAskNew)) { _ in sheet = .newTrip }
        .onChange(of: coverItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let j = await store.upload(data, kind: "cover")
                    if (j["ok"] as? Bool) == true { store.say("封面换好了") }
                    await store.reload()
                }
                coverItem = nil
            }
        }
    }

    @ViewBuilder private var page: some View {
        switch route {
        case .list:
            if !listLoaded { Color(red: 0.11, green: 0.11, blue: 0.12).ignoresSafeArea() } else {
            TripClockList(store: store, close: { dismiss() }, open: { id in Task { await open(id) } }, newTrip: { sheet = .newTrip },
                          insp: { inspFrom = .list; inspPlace = nil; route = .insp })
            }
        case .insp:
            TripInspiration(startPlace: inspPlace, back: { route = inspFrom })
        default:
            if let t = store.trip { tripPage(t) } else { TripInk.plainBG.ignoresSafeArea() }
        }
    }

    /// 正在进行的 > 最近要出发的 > 最近回来的
    private func openDefault() async {
        let order = ["during": 0, "before": 1, "after": 2]
        let pick = store.trips.sorted {
            let a = order[$0.sum.status] ?? 3, b = order[$1.sum.status] ?? 3
            if a != b { return a < b }
            return $0.sum.status == "after" ? $0.start > $1.start : $0.start < $1.start
        }.first
        if let pick { await open(pick.id); if store.trip == nil { route = .list } }   // 没连上就退回钟那页，至少有返回键
        listLoaded = true
    }

    private func open(_ id: Int) async {
        await store.load(id)
        if let t = store.trip { day = t.dayList.contains(TripText.ymdBJ(TripText.localNow(t.tz))) ? TripText.ymdBJ(TripText.localNow(t.tz)) : (t.dayList.first ?? "") }
        route = .home
    }

    @ViewBuilder private func tripPage(_ t: Trip) -> some View {
        let back = { route = .home }
        switch route {
        case .home: TripHome(t: t, back: { dismiss() }, menu: { sheet = .menu }, go: { route = $0 }, pickCover: { pickingCover = true }, toInsp: { inspFrom = .home; inspPlace = t.name; route = .insp })
        case .pack: TripPack(t: t, tab: $packTab, back: back, store: store, sheet: $sheet, toBoard: { route = .board })
        case .board: TripBoard(t: t, back: back, toPack: { route = .pack })
        case .day: TripDay(t: t, day: $day, back: back, sheet: $sheet)
        case .wish: TripWishes(t: t, tab: $wishTab, back: back, sheet: $sheet)
        case .tick: TripTickets(t: t, back: back, sheet: $sheet)
        case .spend: TripSpending(t: t, back: back, sheet: $sheet)
        case .recap: TripRecap(t: t, back: back, sheet: $sheet)
        case .list, .insp: EmptyView()
        }
    }
}

// MARK: 《与此同时》：地上平躺一只钟，光从右上的窗斜着照下来

private struct TripClockList: View {
    @ObservedObject var store: TripStore
    var close: () -> Void
    var open: (Int) -> Void
    var newTrip: () -> Void
    var insp: () -> Void

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            let cx = W * 0.36, cy = H * 0.70, rx = W * 0.31, ry = W * 0.16
            ZStack(alignment: .topLeading) {
                RadialGradient(colors: [Color(white: 0.98), Color(red: 0.957, green: 0.957, blue: 0.953), Color(red: 0.925, green: 0.925, blue: 0.92)],
                               center: UnitPoint(x: 0.8, y: 0), startRadius: 0, endRadius: H * 1.1).ignoresSafeArea()
                TimelineView(.everyMinute) { ctx in
                    Canvas { g, _ in drawLight(g, cx: cx, cy: cy, rx: rx, ry: ry, h: H, now: ctx.date) }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    TripHeader(title: "Voyage", back: close)
                    Text("en même temps").font(TripInk.pin(17)).foregroundStyle(TripInk.g3).padding(.top, 14)
                    Text("与此同时").font(TripInk.serif(22)).tracking(6).foregroundStyle(Color(red: 0.33, green: 0.34, blue: 0.37)).padding(.top, 4)
                    Spacer()
                    TimelineView(.everyMinute) { ctx in
                        Mono("BEIJING \(TripText.hm(ctx.date)) · 北京 · 家", size: 9).frame(maxWidth: .infinity)
                    }
                    HStack {
                        Button(action: newTrip) { Text("＋ 新的一次旅行").font(TripInk.serif(13)).foregroundStyle(TripInk.ink) }
                        Spacer()
                        Button(action: insp) { Text("参考图").font(TripInk.serif(13)).foregroundStyle(TripInk.ink) }   // 1105 #4771
                            .padding(.trailing, 14)
                        Mono("\(store.trips.count) TRIPS")
                    }
                    .padding(.top, 18).padding(.bottom, TripSafe.bottom + 4)
                }
                .padding(.horizontal, 22)
                .padding(.top, TripSafe.top)

                labels(W: W, H: H)
            }
        }
    }

    private var ordered: [Trip] {
        let order = ["during": 0, "before": 1, "after": 2]
        return store.trips.sorted {
            let a = order[$0.sum.status] ?? 3, b = order[$1.sum.status] ?? 3
            if a != b { return a < b }
            return $0.sum.status == "after" ? $0.start > $1.start : $0.start < $1.start
        }.prefix(7).map { $0 }
    }

    @ViewBuilder private func labels(W: CGFloat, H: CGFloat) -> some View {
        let ts = ordered
        let today = TripText.ymdBJ(Date())
        if ts.isEmpty {
            HStack(spacing: 6) {
                Text("还没有旅行").font(TripInk.serif(14)).tracking(2).foregroundStyle(TripInk.g3)
                Text("点下面新建").font(TripInk.pin(15)).foregroundStyle(TripInk.g3)
            }
            .position(x: W * 0.6, y: H * 0.34)
        }
        ForEach(Array(ts.enumerated()), id: \.element.id) { i, t in
            let y = H * 0.25 + CGFloat(i) * (H * 0.36 / CGFloat(max(ts.count, 4)))
            let x = W * 0.44 - CGFloat(i) * W * 0.035
            Button { open(t.id) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(t.name).font(TripInk.serif(14)).tracking(2)
                        .foregroundStyle(t.sum.status == "after" ? TripInk.g3 : Color(red: 0.33, green: 0.34, blue: 0.37))
                    Text(note(t, today: today)).font(TripInk.pin(15)).foregroundStyle(TripInk.g3)
                }
                .fixedSize()
            }
            .position(x: x + 70, y: y)
        }
    }

    private func note(_ t: Trip, today: String) -> String {
        switch t.sum.status {
        case "before": return "\(TripText.md(t.start)) · 还有 \(TripText.days(today, t.start)) 天"
        case "during": return "此刻 \(TripText.hm(TripText.localNow(t.tz))) · 第 \(TripText.days(t.start, today) + 1) 天"
        default: return String(t.start.prefix(7)).replacingOccurrences(of: "-", with: ".")
        }
    }

    private func drawLight(_ g: GraphicsContext, cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, h: CGFloat, now: Date) {
        // 光：几道很宽、糊开的白，看不见边
        g.drawLayer { l in
            l.addFilter(.blur(radius: 32))
            l.translateBy(x: cx, y: cy)
            l.rotate(by: .degrees(20))
            let beams: [(CGFloat, CGFloat, Double)] = [(-70, 46, 0.75), (-28, 64, 0.95), (18, 40, 0.8), (52, 70, 0.9), (96, 36, 0.6)]
            for (o, w, a) in beams {
                let r = CGRect(x: o - w / 2, y: -h * 1.1, width: w, height: h * 1.1)
                l.fill(Path(r), with: .linearGradient(Gradient(stops: [
                    .init(color: .white.opacity(0), location: 0), .init(color: .white.opacity(a), location: 0.25),
                    .init(color: .white.opacity(a), location: 0.9), .init(color: .white.opacity(0), location: 1)]),
                    startPoint: CGPoint(x: 0, y: -h * 1.1), endPoint: CGPoint(x: 0, y: 0)))
            }
        }
        // 地上：光照到的那团亮，周围一圈淡灰
        g.drawLayer { l in
            l.addFilter(.blur(radius: 16))
            l.fill(Path(ellipseIn: CGRect(x: cx - rx - 30, y: cy - ry - 12, width: (rx + 30) * 2, height: (ry + 16) * 2)), with: .color(Color(red: 0.75, green: 0.75, blue: 0.79).opacity(0.28)))
            l.fill(Path(ellipseIn: CGRect(x: cx + 6 - rx * 0.8, y: cy - 2 - ry * 0.75, width: rx * 1.6, height: ry * 1.5)), with: .color(.white.opacity(0.95)))
        }
        // 钟面刻度和指针（北京时间）
        let tick = Color(red: 0.61, green: 0.62, blue: 0.66)
        for k in 0..<60 {
            let a = Double(k) / 60 * 2 * .pi, l = k % 5 == 0 ? 0.11 : 0.055
            var p = Path()
            p.move(to: CGPoint(x: cx + rx * sin(a), y: cy - ry * cos(a)))
            p.addLine(to: CGPoint(x: cx + rx * (1 - l) * sin(a), y: cy - ry * (1 - l) * cos(a)))
            g.stroke(p, with: .color(tick.opacity(k % 5 == 0 ? 0.8 : 0.55)), style: StrokeStyle(lineWidth: k % 5 == 0 ? 1.5 : 0.8, lineCap: .round))
        }
        let c = TripText.bjComponents(now)
        let hA = (Double((c.hour ?? 0) % 12) + Double(c.minute ?? 0) / 60) / 12 * 2 * .pi, mA = Double(c.minute ?? 0) / 60 * 2 * .pi
        let hand = Color(red: 0.54, green: 0.55, blue: 0.59)
        for (a, len, w) in [(hA, 0.5, 2.2), (mA, 0.78, 1.3)] {
            var p = Path(); p.move(to: CGPoint(x: cx, y: cy)); p.addLine(to: CGPoint(x: cx + rx * len * sin(a), y: cy - ry * len * cos(a)))
            g.stroke(p, with: .color(hand), style: StrokeStyle(lineWidth: w, lineCap: .round))
        }
        g.fill(Path(ellipseIn: CGRect(x: cx - 3.2, y: cy - 1.8, width: 6.4, height: 3.6)), with: .color(hand))
    }
}

// MARK: 这一趟

private struct TripHome: View {
    // 1105 #4758–4769 她定的拼贴版（08 参考图点进去直接停在这趟的地名上）：一整张夜樱画（纸格子已经拼好、花枝漫到纸上，底图放服务器 /trip/img/voyage.jpg）
    // 上面按画布 852×1846 的坐标摆字、摆点按区；效果图 texted6 一比一。中文衬线（宋体）、英文 Pinyon、数字 Cormorant（时间戳那款），倒计时用细一档 Light
    let t: Trip
    var back: () -> Void
    var menu: () -> Void
    var go: (TripRoute) -> Void
    var pickCover: () -> Void
    var toInsp: () -> Void

    private static let W: CGFloat = 852, H: CGFloat = 1846, Z: CGFloat = 1.15
    private static let ink = Color(red: 52/255, green: 52/255, blue: 56/255)
    private static let g1 = Color(red: 110/255, green: 110/255, blue: 116/255)
    private static let g3 = Color(red: 150/255, green: 150/255, blue: 156/255)

    var body: some View {
        GeometryReader { geo in
            let k = max(geo.size.width / Self.W, geo.size.height / Self.H)
            canvas(k)
                .frame(width: Self.W * k, height: Self.H * k)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .ignoresSafeArea()
        .background(Color(red: 0.11, green: 0.11, blue: 0.12).ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            Button(action: back) {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .regular)).foregroundStyle(.white.opacity(0.85))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 6).padding(.top, TripSafe.top)
        }
    }

    @ViewBuilder private func canvas(_ k: CGFloat) -> some View {
        let s = t.sum, today = TripText.ymdBJ(Date())
        let cd: (Int, String) = s.status == "before" ? (TripText.days(today, t.start), "days to go")
            : s.status == "during" ? (TripText.days(t.start, today) + 1, "day") : (TripText.days(t.end, today), "days since")
        let Z = Self.Z
        ZStack(alignment: .topLeading) {
            CachedImage(url: AlcoveAPI.fullURL("/trip/img/voyage3.jpg")) { img in img.resizable() } placeholder: { Color(red: 0.11, green: 0.11, blue: 0.12) }
                .frame(width: Self.W * k, height: Self.H * k)
                .allowsHitTesting(false)

            // 点按区：照格子，空格子不接（ViewBuilder 一层最多十个，分组装）
            Group {
            tap(575, 85, 852, 348, k, menu)
            tap(728, 640, 852, 795, k) { go(.pack) }
            tap(357, 1088, 532, 1345, k) { go(.day) }
            tap(532, 950, 655, 1345, k) { go(.board) }
            tap(655, 880, 758, 1345, k) { go(.wish) }
            tap(758, 795, 852, 1345, k) { go(.tick) }
            tap(190, 1345, 515, 1520, k) { go(.spend) }
            tap(515, 1345, 852, 1615, k) { go(.recap) }
            tap(630, 1615, 852, 1755, k, toInsp)
            }

            Group {
                // 右上台阶：地名
                put(Text("Voyage").font(TripInk.pin(52 * k)).foregroundColor(Self.g1), 670, 96, k)
                Text(t.name).font(TripInk.serif(60 * k)).foregroundColor(Self.ink).lineLimit(1).minimumScaleFactor(0.4)
                    // 1105 她「地名为什么那么小」：外面那层 0 高的框把高度 0 传进来，minimumScaleFactor 就一路缩到 0.4；给它自己的高度
                    .frame(width: (852 - 590 - 12) * k, height: 84 * k, alignment: .topLeading)
                    .frame(width: 0, height: 0, alignment: .topLeading).position(x: 590 * k, y: 196 * k).allowsHitTesting(false)
                put(mix("\(TripText.md(t.start)) — \(TripText.md(t.end))", 19 * k).foregroundColor(Self.g1), 592, 282, k)
                put(mix("第 \(String(format: "%03d", t.id)) 次 · \(s.days) 天 \(max(s.days - 1, 0)) 晚", 14 * k).foregroundColor(Self.g3), 592, 312, k)
                // 中间大格：倒计时
                put(Text("\(cd.0)").font(.custom("CormorantGaramond-Light", size: 220 * k)).foregroundColor(Self.ink), 452, 520, k,
                    Alignment(horizontal: .leading, vertical: .lastTextBaseline))
                put(Text(cd.1).font(TripInk.pin(44 * k)).foregroundColor(Self.g1), 836, 586, k,
                    Alignment(horizontal: .trailing, vertical: .lastTextBaseline))
            }
            Group {
                // 01 准备清单
                put(mix("01", 10 * Z * k).foregroundColor(Self.g3), 740, 654, k)
                put(Text("准备清单").font(TripInk.serif(16 * Z * k)).foregroundColor(Self.ink), 740, 674, k)
                put(Text("Packing").font(TripInk.pin(20 * Z * k)).foregroundColor(Self.g1), 740, 706, k)
                put(mix("\(s.done) / \(s.items)", 12 * Z * k).foregroundColor(Self.g1), 740, 768, k)
                // 02 日程（横排）
                put(mix("02", 10 * Z * k).foregroundColor(Self.g3), 377, 1106, k)
                put(Text("日程").font(TripInk.serif(18 * Z * k)).foregroundColor(Self.ink), 377, 1126, k)
                put(Text("Days").font(TripInk.pin(22 * Z * k)).foregroundColor(Self.g1), 377, 1162, k)
                put(mix("\(s.days) 天", 12 * Z * k).foregroundColor(Self.g1), 377, 1300, k)
            }
            Group {
                column("03", "登机牌", "Boarding", 18, x: 593, k: k)
                // 1108 #4910 她：登机牌不用全勾完才能看。这格改成报清单进度
                put(Text(t.packedAt.isEmpty ? "清单 \(s.done)/\(s.items)" : "万事俱备").font(TripInk.serif(11 * Z * k)).foregroundColor(Self.g1), 593, 1300, k, .top)
                column("04", "想去", "Wishes", 20, x: 706, k: k)
                put(mix("\(s.wishes) 处", 12 * Z * k).foregroundColor(Self.g1), 706, 1300, k, .top)
                column("05", "票据", "Tickets", 18, x: 805, k: k)
                put(mix("\(s.tickets) 张", 12 * Z * k).foregroundColor(Self.g1), 805, 1300, k, .top)
            }
            Group {
                // 06 花销
                put(mix("06", 10 * Z * k).foregroundColor(Self.g3), 210, 1362, k)
                put(Text("花销").font(TripInk.serif(18 * Z * k)).foregroundColor(Self.ink), 210, 1384, k)
                put(Text("Spending").font(TripInk.pin(24 * Z * k)).foregroundColor(Self.g1), 282, 1378, k)
                put(mix("¥ \(TripText.money(s.spent))", 15 * Z * k).foregroundColor(Self.ink), 495, 1482, k, .topTrailing)
                // 07 回顾
                put(mix("07", 10 * Z * k).foregroundColor(Self.g3), 535, 1362, k)
                put(Text("回顾").font(TripInk.serif(18 * Z * k)).foregroundColor(Self.ink), 535, 1384, k)
                put(Text("Memories").font(TripInk.pin(26 * Z * k)).foregroundColor(Self.g1), 535, 1422, k)
                put(Text(s.status == "after" ? "看看" : "回来以后").font(TripInk.serif(12 * Z * k)).foregroundColor(Self.g3), 832, 1580, k, .topTrailing)
            }
            Group {
                // 08 参考图
                put(mix("08", 10 * Z * k).foregroundColor(Self.g3), 650, 1632, k)
                put(Text("参考图").font(TripInk.serif(18 * Z * k)).foregroundColor(Self.ink), 650, 1654, k)
                put(Text("Inspiration").font(TripInk.pin(24 * Z * k)).foregroundColor(Self.g1), 650, 1692, k)
            }
            .allowsHitTesting(false)
        }
    }

    /// 字按画布坐标摆：(x, y) 是字的左上角（或 a 指定的那个角/基线）
    private func put<V: View>(_ v: V, _ x: CGFloat, _ y: CGFloat, _ k: CGFloat, _ a: Alignment = .topLeading) -> some View {
        v.fixedSize().frame(width: 0, height: 0, alignment: a).position(x: x * k, y: y * k).allowsHitTesting(false)
    }

    /// 窄长格：编号、竖排中文、花体英文，一列居中
    private func column(_ no: String, _ zh: String, _ en: String, _ enSize: CGFloat, x: CGFloat, k: CGFloat) -> some View {
        let Z = Self.Z, size = 18 * Z
        return ZStack(alignment: .topLeading) {
            put(mix(no, 10 * Z * k).foregroundColor(Self.g3), x, 1030, k, .top)
            ForEach(Array(zh.enumerated()), id: \.offset) { i, ch in
                put(Text(String(ch)).font(TripInk.serif(size * k)).foregroundColor(Self.ink), x, 1054 + CGFloat(i) * size * 1.15, k, .top)
            }
            put(Text(en).font(TripInk.pin(enSize * Z * k)).foregroundColor(Self.g1), x, zh.count > 2 ? 1200 : 1140, k, .top)
        }
    }

    private func tap(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ k: CGFloat, _ act: @escaping () -> Void) -> some View {
        Color.clear.contentShape(Rectangle())
            .frame(width: (x1 - x0) * k, height: (y1 - y0) * k)
            .onTapGesture(perform: act)
            .offset(x: x0 * k, y: y0 * k)
    }

    /// 中文衬线、数字和标点换 Cormorant（时间戳那款，老式数字）；数字字面小，放大 1.2 跟中文一样高
    private func mix(_ str: String, _ size: CGFloat) -> Text {
        let numSet = Set("0123456789.,/—¥ ")
        var out = Text("")
        var run = "", runIsNum: Bool? = nil
        func flush() {
            guard let isNum = runIsNum, !run.isEmpty else { return }
            out = out + Text(run).font(isNum ? .custom("CormorantGaramond-Medium", size: size * 1.2) : TripInk.serif(size))
            run = ""
        }
        for ch in str {
            let isNum = numSet.contains(ch)
            if runIsNum != isNum { flush(); runIsNum = isNum }
            run.append(ch)
        }
        flush()
        return out
    }
}

// MARK: 准备清单

private struct TripPack: View {
    let t: Trip
    @Binding var tab: String
    var back: () -> Void
    @ObservedObject var store: TripStore
    @Binding var sheet: TripSheet?
    var toBoard: () -> Void

    var body: some View {
        let s = t.sum
        TripPage(title: "Packing", tint: t.tint, back: back, menu: nil, foot: ("\(s.items) 样", "pack it all…")) {
            VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(s.done)").font(TripInk.serif(40))
                        Text("/ \(s.items)").font(TripInk.serif(20)).foregroundStyle(TripInk.g1)
                    }
                    HStack(spacing: 6) {
                        Mono("BEFORE WE GO · 出发前")
                        Text("· 霁加 \(t.items.filter { $0.who == "霁" }.count) · 璟加 \(t.items.filter { $0.who == "璟" }.count) · 还差 \(s.items - s.done) 样").font(TripInk.serif(10)).foregroundStyle(TripInk.g1)
                    }
                    .padding(.top, 8)
                    dots.padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topTrailing) {
                TripMat(name: "jelly", tint: t.tint, opacity: 0.38).frame(width: 430, height: 306)
                    .mask(RadialGradient(colors: [.black, .clear], center: UnitPoint(x: 0.62, y: 0.5), startRadius: 60, endRadius: 210))
                    .offset(x: 170, y: -40)
            }
            .padding(.top, 12)
            TripTabs(options: ["全部"] + TripText.groups, selected: $tab).padding(.top, 14)
            if t.items.isEmpty {
                VStack(spacing: 12) {
                    Text("还没有要带的东西").font(TripInk.serif(13)).foregroundStyle(TripInk.g3)
                    Button { sheet = .template } label: { Mono("从模板带入 ›", color: TripInk.ink) }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
            }
            ForEach(tab == "全部" ? TripText.groups : [tab], id: \.self) { g in
                let its = t.items.filter { $0.grp == g }
                if !its.isEmpty {
                    HStack { Mono(g, color: TripInk.ink); Spacer(); Mono("\(its.filter { $0.done }.count)/\(its.count)") }.padding(.top, 18).padding(.bottom, 6)
                    ForEach(its) { it in itemRow(it) }
                    Hair()
                }
            }
        } bar: {
            HStack {
                Button { sheet = .item(nil) } label: { Text("＋ 加一条").font(TripInk.serif(13)).foregroundStyle(TripInk.ink) }
                Spacer()
                Button { sheet = .template } label: { Mono("从模板带入", color: TripInk.ink) }
            }
        }
    }

    private var dots: some View {
        let cols = Array(repeating: GridItem(.fixed(10), spacing: 0), count: 22)
        return LazyVGrid(columns: cols, alignment: .leading, spacing: 4) {
            ForEach(t.items) { it in
                Circle().fill(it.done ? TripInk.ink : Color.clear).overlay(Circle().stroke(TripInk.ink, lineWidth: 0.6)).frame(width: 6, height: 6)
            }
        }
        .frame(maxWidth: 260, alignment: .leading)
    }

    private func itemRow(_ it: TripItem) -> some View {
        TripRow {
            Button { Task { await toggle(it) } } label: {
                Circle().fill(it.done ? TripInk.ink : Color.clear).overlay(Circle().stroke(TripInk.ink, lineWidth: 0.7)).frame(width: 15, height: 15)
            }
            .buttonStyle(.plain).padding(.top, 2)
            Button { sheet = .item(it.id) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(it.text).font(TripInk.serif(14)).foregroundStyle(it.done ? TripInk.g3 : TripInk.ink).strikethrough(it.done, color: TripInk.g3)
                    if !it.note.isEmpty { Text(it.note).font(TripInk.mono(9)).foregroundStyle(TripInk.g3) }
                    Spacer()
                    Text(it.done && !it.whoDone.isEmpty && it.whoDone != it.who ? "\(it.who)加 · \(it.whoDone)勾" : it.who).font(TripInk.mono(9)).foregroundStyle(TripInk.g3)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func toggle(_ it: TripItem) async {
        let j = await store.post("item", ["op": "toggle", "id": it.id, "who": "霁"])
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        await store.reload()
        if (j["packed_now"] as? Bool) == true {
            store.say("都准备好了")
            try? await Task.sleep(nanoseconds: 700_000_000)
            toBoard()
        }
    }
}

private struct TripTabs: View {
    let options: [String]
    @Binding var selected: String
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                ForEach(options, id: \.self) { o in
                    Button { selected = o } label: {
                        Text(o).font(TripInk.serif(13)).foregroundStyle(selected == o ? TripInk.ink : TripInk.g3)
                            .padding(.bottom, 4)
                            .overlay(alignment: .bottom) { if selected == o { Rectangle().fill(TripInk.ink).frame(height: 0.7) } }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: 登机牌

private struct TripBoard: View {
    let t: Trip
    var back: () -> Void
    var toPack: () -> Void

    var body: some View {
        let s = t.sum
        TripPage(title: "Boarding", tint: t.tint, back: back, menu: nil) {
            // 1108 #4910 她：「登机牌这个不需要全部勾完才能看」——票一直在，顶上只报清单进度
            if t.packedAt.isEmpty {
                Button(action: toPack) { Mono("清单 \(s.done) / \(s.items) · 还差 \(s.items - s.done) 样 · 去清单 ›") }
                    .buttonStyle(.plain).frame(maxWidth: .infinity).padding(.top, 10).padding(.bottom, 18)
            } else {
                Mono("\(s.items) / \(s.items) · ALL PACKED · 万事俱备").frame(maxWidth: .infinity).padding(.top, 10).padding(.bottom, 18)
            }
            // 1108 #4915 她「登机牌都出」：票据里每张机票各出一张，按起飞时间排；一张机票都没登记就还是原来那张
            let flights = t.tickets.filter { $0.kind == "flight" }
            if flights.isEmpty { pass } else {
                VStack(spacing: 16) { ForEach(Array(flights.enumerated()), id: \.element.id) { i, k in flightPass(k, no: i + 1) } }
            }
            Rectangle().stroke(style: StrokeStyle(lineWidth: 0.5, dash: [3, 3])).foregroundStyle(Color.black.opacity(0.35)).frame(height: 0.5).padding(.horizontal, 8)
            stub
            if !t.packedAt.isEmpty {
                Text("勾完那天 · \(TripText.md(String(t.packedAt.prefix(10))))").font(TripInk.serif(10)).foregroundStyle(TripInk.g1).frame(maxWidth: .infinity).padding(.top, 18)
            }
            TripMat(name: "mountain", tint: t.tint, opacity: 0.55).frame(height: 150).padding(.horizontal, -32)
                .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .leading, endPoint: .trailing))
                .padding(.top, 20)
        } bar: { EmptyView() }
    }

    private var pass: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Mono("BOARDING PASS · 登机牌"); Spacer(); Mono("NO. \(String(format: "%03d", t.id))") }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) { Text(t.fromCity.isEmpty ? "上海" : t.fromCity).font(TripInk.serif(40)); Mono(t.fromCode) }
                Rectangle().stroke(style: StrokeStyle(lineWidth: 0.5, dash: [2, 2])).frame(height: 0.5).padding(.horizontal, 12).padding(.bottom, 22)
                VStack(alignment: .trailing, spacing: 6) { Text(t.name).font(TripInk.serif(40)); Mono([t.nameEn, t.code].filter { !$0.isEmpty }.joined(separator: " · ")) }
            }
            .padding(.top, 18)
            Hair().padding(.top, 18).padding(.bottom, 12)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 14) {
                GridRow { cell("PASSENGERS", "陈霁 & 陈璟"); cell("FLIGHT", t.flight.isEmpty ? "—" : t.flight); cell("DATE", TripText.md(t.start)) }
                GridRow { cell("BOARDING", t.boarding.isEmpty ? "—" : t.boarding); cell("SEAT", t.seat.isEmpty ? "06·01" : t.seat); cell("GATE", "∞") }
            }
        }
        .padding(20)
        .background(TripInk.paper)
        .overlay(Rectangle().stroke(Color.black.opacity(0.22), lineWidth: 0.5))
    }

    /// 票据里的一张机票出一张登机牌。标题照登记的写法「武汉 → 成都 · CA4044」拆出两头
    private func flightPass(_ k: TripTicket, no: Int) -> some View {
        let head = k.title.components(separatedBy: "·").first ?? k.title
        let ends = head.components(separatedBy: "→").map { $0.trimmingCharacters(in: .whitespaces) }
        let from = ends.first ?? "", to = ends.count > 1 ? ends[1] : ""
        let day = String(k.at.prefix(10)), hm = k.at.count >= 16 ? String(k.at.suffix(5)) : "—"
        return VStack(alignment: .leading, spacing: 0) {
            HStack { Mono("BOARDING PASS · 登机牌"); Spacer(); Mono("NO. \(String(format: "%03d", t.id))-\(no)") }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) { Text(from).font(TripInk.serif(40)); Mono(k.l1) }
                Rectangle().stroke(style: StrokeStyle(lineWidth: 0.5, dash: [2, 2])).frame(height: 0.5).padding(.horizontal, 12).padding(.bottom, 22)
                VStack(alignment: .trailing, spacing: 6) { Text(to).font(TripInk.serif(40)); Mono(" ") }
            }
            .padding(.top, 18)
            Hair().padding(.top, 18).padding(.bottom, 12)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 14) {
                GridRow { cell("PASSENGERS", "陈霁 & 陈璟"); cell("FLIGHT", k.code.isEmpty ? "—" : k.code); cell("DATE", day.isEmpty ? "—" : TripText.md(day)) }
                GridRow { cell("DEPART", hm); cell("SEAT", t.seat.isEmpty ? "06·01" : t.seat); cell("GATE", "∞") }
            }
        }
        .padding(20)
        .background(TripInk.paper)
        .overlay(Rectangle().stroke(Color.black.opacity(0.22), lineWidth: 0.5))
    }

    private func cell(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Mono(k, size: 8); Text(v).font(TripInk.serif(15)) }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stub: some View {
        VStack(alignment: .leading, spacing: 0) {
            Mono("STUB · 票根 · 璟写的")
            if t.stub.isEmpty {
                Text("他还没写，写好了会出现在这里").font(TripInk.serif(14)).foregroundStyle(TripInk.g3).padding(.top, 10)
            } else {
                Text(t.stub).font(TripInk.serif(14)).lineSpacing(9).padding(.top, 10)
                Text("— 璟 · \(TripText.md(String(t.stubAt.prefix(10))))").font(TripInk.serif(10)).foregroundStyle(TripInk.g1).frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 8)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TripInk.paper)
        .overlay(Rectangle().stroke(Color.black.opacity(0.22), lineWidth: 0.5))
    }
}

// MARK: 日程

private struct TripDay: View {
    let t: Trip
    @Binding var day: String
    var back: () -> Void
    @Binding var sheet: TripSheet?

    var body: some View {
        let ln = TripText.localNow(t.tz), isToday = TripText.ymdBJ(ln) == day, nowHM = TripText.hm(ln)
        let ss = t.stops.filter { $0.day == day }
        let cur: Int = isToday ? (ss.lastIndex { !$0.time.isEmpty && $0.time <= nowHM } ?? -1) : -1
        let wx = t.weather[day]
        let wd = TripText.date(day).map { TripText.weekdays[(TripText.bjComponents($0).weekday ?? 1) - 1] } ?? ""
        TripPage(title: "Day by Day", tint: t.tint, back: back, menu: nil, foot: ("\(ss.count) 件事" + (wx.map { $0.sunset.isEmpty ? "" : " · 日落 \($0.sunset)" } ?? ""), "slowly…")) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(TripText.md(day)).font(TripInk.serif(40))
                            HStack(spacing: 6) {
                                Mono(wd)
                                Text("· 第 \((t.dayList.firstIndex(of: day) ?? 0) + 1) / \(t.dayList.count) 天" + (wx.map { " · \($0.wx) \($0.hi)° / \($0.lo)°" } ?? "")).font(TripInk.serif(10)).foregroundStyle(TripInk.g1)
                            }
                        }
                        Spacer()
                        HStack(spacing: 12) {
                            ForEach(t.dayList, id: \.self) { d in
                                Button { day = d } label: {
                                    Text(String(d.suffix(2))).font(TripInk.serif(12)).foregroundStyle(d == day ? TripInk.ink : TripInk.g3).padding(.bottom, 3)
                                        .overlay(alignment: .bottom) { if d == day { Rectangle().fill(TripInk.ink).frame(height: 0.7) } }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 10)
                    }
                    .padding(.top, 12)
                    VStack(spacing: 0) {
                        if ss.isEmpty { Text("这天还没排").font(TripInk.serif(13)).foregroundStyle(TripInk.g3).frame(maxWidth: .infinity).padding(.vertical, 40) }
                        ForEach(Array(ss.enumerated()), id: \.element.id) { i, x in
                            stopRow(x, past: isToday ? i < cur : day < TripText.ymdBJ(ln), now: i == cur)
                        }
                        if !ss.isEmpty { Hair() }
                    }
                    .padding(.top, 18)
                }
                .background(alignment: .topLeading) {
                    TripMat(name: "tree", tint: t.tint, opacity: 0.42).frame(width: 450, height: 788)
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.14), .init(color: .black, location: 0.42),
                                                     .init(color: .black.opacity(0.35), location: 0.62), .init(color: .clear, location: 0.86)], startPoint: .top, endPoint: .bottom))
                        .offset(x: -50, y: 200)
                }
        } bar: {
            HStack {
                Button { sheet = .stop(nil) } label: { Text("＋ 加一项").font(TripInk.serif(13)).foregroundStyle(TripInk.ink) }
                Spacer()
                Button { sheet = .fromWish } label: { Mono("从想去挑 · \(t.wishes.filter { $0.stopId == nil }.count)", color: TripInk.ink) }
            }
        }
    }

    private func stopRow(_ x: TripStop, past: Bool, now: Bool) -> some View {
        VStack(spacing: 0) {
            if !x.route.isEmpty { routeLeg(x, past: past) }
            stopMain(x, past: past, now: now)
        }
    }

    /// 1108 #4915 她：每一站怎么过去——两站之间一段虚线＋怎么走，右边一键开地图导航到这一站
    private func routeLeg(_ x: TripStop, past: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().stroke(style: StrokeStyle(lineWidth: 0.6, dash: [2, 3])).frame(width: 0.6).foregroundStyle(TripInk.g3)
                .frame(width: 46, alignment: .center).padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 4) {
                Mono("ROUTE · 怎么走", size: 8, color: TripInk.g3)
                Text(x.route).font(TripInk.serif(12)).foregroundStyle(past ? TripInk.g3 : TripInk.g1).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                let to = x.addr.isEmpty ? x.title : x.addr
                if let u = URL(string: "https://maps.apple.com/?daddr=" + (to.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) { UIApplication.shared.open(u) }
            } label: { Mono("导航 ›", color: TripInk.ink) }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    private func stopMain(_ x: TripStop, past: Bool, now: Bool) -> some View {
        Button { sheet = .stop(x.id) } label: {
            TripRow {
                Text(x.time.isEmpty ? "—" : x.time).font(TripInk.serif(15)).frame(width: 46, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(x.title).font(TripInk.serif(14)).fontWeight(now ? .medium : .regular)
                    let sub = [TripText.how(x.how), x.dur].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !sub.isEmpty { Mono(sub, color: past ? TripInk.g3 : TripInk.g1) }
                    if !x.note.isEmpty { Text(x.note).font(TripInk.serif(10)).foregroundStyle(TripInk.g1) }
                    if !x.hisLine.isEmpty {
                        Text("「\(x.hisLine)」").font(TripInk.serif(12.5)).foregroundStyle(TripInk.ink).lineSpacing(6).padding(.top, 6)
                        Text("璟 · \(String(x.hisAt.dropFirst(11).prefix(5)))").font(TripInk.mono(9)).foregroundStyle(TripInk.g3)
                    }
                }
                Spacer()
                if now { Mono("NOW", color: TripInk.ink) }
            }
            .foregroundStyle(past ? TripInk.g3 : TripInk.ink)
        }
        .buttonStyle(.plain)
    }
}

// MARK: 想去

private struct TripWishes: View {
    let t: Trip
    @Binding var tab: String
    var back: () -> Void
    @Binding var sheet: TripSheet?

    var body: some View {
        let ws = t.wishes.filter { tab == "全部" || $0.cat == tab }
        TripPage(title: "Someday", tint: t.tint, back: back, menu: nil, foot: ("\(t.wishes.count) 处 · 霁 \(t.wishes.filter { $0.who == "霁" }.count) · 璟 \(t.wishes.filter { $0.who == "璟" }.count)", "someday…")) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(format: "%02d", t.wishes.count)).font(TripInk.serif(40))
                            HStack(spacing: 6) { Mono("PLACES · 想去"); Text("· 已排 \(t.wishes.filter { $0.stopId != nil }.count)").font(TripInk.serif(10)).foregroundStyle(TripInk.g1) }
                        }
                        Spacer()
                        TripTabs(options: ["全部"] + TripText.wishCats, selected: $tab).frame(maxWidth: 190).padding(.top, 12)
                    }
                    .padding(.top, 12)
                    VStack(spacing: 0) {
                        if ws.isEmpty { Text("想去哪儿，随手丢进来").font(TripInk.serif(13)).foregroundStyle(TripInk.g3).frame(maxWidth: .infinity).padding(.vertical, 40) }
                        ForEach(Array(ws.enumerated()), id: \.element.id) { i, w in
                            Button { sheet = .wish(w.id) } label: {
                                TripRow {
                                    Text(String(format: "%02d", i + 1)).font(TripInk.mono(9)).foregroundStyle(TripInk.g3).frame(width: 18, alignment: .leading).padding(.top, 3)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(w.name).font(TripInk.serif(14)).foregroundStyle(TripInk.ink)
                                        Text([w.cat, w.note, "\(w.who)加的"].filter { !$0.isEmpty }.joined(separator: " · ")).font(TripInk.mono(9)).foregroundStyle(TripInk.g1)
                                    }
                                    Spacer()
                                    Text(dayOf(w) ?? "排进哪天 ›").font(TripInk.serif(10)).foregroundStyle(dayOf(w) == nil ? TripInk.g1 : TripInk.ink)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        if !ws.isEmpty { Hair() }
                    }
                    .padding(.top, 18)
                }
                .background(alignment: .topLeading) {
                    TripMat(name: "foam", tint: t.tint, opacity: 0.26).frame(width: 330, height: 578)
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1), .init(color: .black, location: 0.45), .init(color: .clear, location: 0.8)], startPoint: .top, endPoint: .bottom))
                        .offset(x: 128, y: 30)
                }
        } bar: {
            HStack { Button { sheet = .wish(nil) } label: { Text("＋ 丢一个想去的地方").font(TripInk.serif(13)).foregroundStyle(TripInk.ink) }; Spacer() }
        }
    }

    private func dayOf(_ w: TripWish) -> String? {
        guard let sid = w.stopId, let st = t.stops.first(where: { $0.id == sid }) else { return nil }
        return "第 \((t.dayList.firstIndex(of: st.day) ?? 0) + 1) 天"
    }
}

// MARK: 票据

private struct TripTickets: View {
    let t: Trip
    var back: () -> Void
    @Binding var sheet: TripSheet?

    var body: some View {
        let today = TripText.ymdBJ(TripText.localNow(t.tz))
        let next = t.tickets.first { !$0.at.isEmpty && $0.at >= today }
        TripPage(title: "Tickets", tint: t.tint, back: back, menu: nil, foot: ("\(t.tickets.count) 张", "keep them…")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(format: "%02d", t.tickets.count)).font(TripInk.serif(40))
                HStack(spacing: 6) { Mono("KEPT · 票据"); if let next { Text("· 下一张 \(next.title) · \(next.at)").font(TripInk.serif(10)).foregroundStyle(TripInk.g1).lineLimit(1) } }
            }
            .padding(.top, 12)
            VStack(spacing: 0) {
                if t.tickets.isEmpty { Text("机票、车票、酒店订单的截图都放这里").font(TripInk.serif(13)).foregroundStyle(TripInk.g3).frame(maxWidth: .infinity).padding(.vertical, 40) }
                ForEach(t.tickets) { k in
                    Button { sheet = .ticket(k.id) } label: {
                        TripRow {
                            thumb(k.img).frame(width: 64, height: 84)
                            VStack(alignment: .leading, spacing: 6) {
                                Mono("\(k.kind.isEmpty ? "OTHER" : k.kind) · \(TripText.kind(k.kind))")
                                Text(k.title).font(TripInk.serif(14)).foregroundStyle(TripInk.ink)
                                Text([k.at, k.l1, k.l2].filter { !$0.isEmpty }.joined(separator: " · ")).font(TripInk.serif(10)).foregroundStyle(TripInk.g1).lineSpacing(4)
                            }
                            Spacer()
                            Mono(k.code, color: TripInk.ink)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if !t.tickets.isEmpty { Hair() }
            }
            .padding(.top, 18)
        } bar: {
            HStack { Button { sheet = .ticket(nil) } label: { Text("＋ 存一张截图").font(TripInk.serif(13)).foregroundStyle(TripInk.ink) }; Spacer() }
        }
    }

    @ViewBuilder private func thumb(_ img: String) -> some View {
        if img.isEmpty {
            Rectangle().fill(Color(white: 0.93)).overlay(Rectangle().stroke(TripInk.hl, lineWidth: 0.5))
        } else {
            AsyncImage(url: AlcoveAPI.fullURL("/\(img)")) { i in i.resizable().scaledToFill() } placeholder: { Color(white: 0.93) }
                .opacity(0.8).clipped().overlay(Rectangle().stroke(TripInk.hl, lineWidth: 0.5))
        }
    }
}

// MARK: 花销

private struct TripSpending: View {
    let t: Trip
    var back: () -> Void
    @Binding var sheet: TripSheet?

    var body: some View {
        let total = t.spends.reduce(0) { $0 + $1.amount }
        let per = t.dayList.map { d in (d, t.spends.filter { $0.day == d && !$0.prepaid }.reduce(0) { $0 + $1.amount }) }
        let mx = max(1, per.map { $0.1 }.max() ?? 1)
        let cats = TripText.spendCats.map { c in (c, t.spends.filter { $0.cat == c }.reduce(0) { $0 + $1.amount }) }.filter { $0.1 > 0 }
        let cm = max(1, cats.map { $0.1 }.max() ?? 1)
        TripPage(title: "Spending", tint: t.tint, back: back, menu: nil, foot: (t.budget > 0 ? "预算 ¥\(TripText.money(Double(t.budget)))" : "没设预算", "keep it small…")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(TripText.money(total)).font(TripInk.serif(40))
                        if t.budget > 0 { Text("/ \(TripText.money(Double(t.budget)))").font(TripInk.serif(20)).foregroundStyle(TripInk.g1) }
                    }
                    HStack(spacing: 6) {
                        Mono("SPENT · 花销")
                        Text((t.budget > 0 ? "· 用了 \(Int(total / Double(t.budget) * 100))% · 还剩 ¥\(TripText.money(Double(t.budget) - total))" : "") + " · 跟钱包真账分开").font(TripInk.serif(10)).foregroundStyle(TripInk.g1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .topTrailing) {
                    TripMat(name: "formula", tint: t.tint, opacity: 0.45).frame(width: 300, height: 51)
                        .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .leading, endPoint: .trailing))
                        .offset(x: 80, y: -10)
                }
            .padding(.top, 12)
            HStack(spacing: 0) {
                ForEach(per.indices, id: \.self) { i in
                    let d = per[i].0, v = per[i].1
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottom) {
                            Rectangle().fill(TripInk.hl).frame(width: 1, height: 90)
                            Rectangle().fill(TripInk.ink).frame(width: 4, height: CGFloat(v / mx * 90))
                        }
                        Text(String(d.suffix(2))).font(TripInk.serif(11))
                        Mono(v > 0 ? TripText.money(v) : "—", size: 7.5)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 22)
            VStack(spacing: 0) {
                ForEach(cats.indices, id: \.self) { i in
                    let c = cats[i].0, v = cats[i].1
                    TripRow {
                        Text(c).font(TripInk.serif(14)).frame(width: 40, alignment: .leading)
                        GeometryReader { g in
                            ZStack(alignment: .leading) { Rectangle().fill(TripInk.hl).frame(height: 0.5); Rectangle().fill(TripInk.ink).frame(width: g.size.width * CGFloat(v / cm), height: 1.5) }
                                .frame(maxHeight: .infinity)
                        }
                        .frame(height: 18)
                        Text("¥\(TripText.money(v))").font(TripInk.serif(14)).frame(width: 74, alignment: .trailing)
                    }
                }
            }
            .padding(.top, 20)
            Mono("RECENT").padding(.top, 22).padding(.bottom, 4)
            VStack(spacing: 0) {
                if t.spends.isEmpty { Text("还没花钱").font(TripInk.serif(13)).foregroundStyle(TripInk.g3).frame(maxWidth: .infinity).padding(.vertical, 30) }
                ForEach(t.spends.prefix(12)) { x in
                    Button { sheet = .spendRow(x.id) } label: {
                        TripRow {
                            Text(TripText.md(x.day)).font(TripInk.mono(9)).foregroundStyle(TripInk.g3).frame(width: 46, alignment: .leading)
                            Text((x.text.isEmpty ? x.cat : x.text) + (x.prepaid ? " · 预付" : "")).font(TripInk.serif(14)).foregroundStyle(TripInk.ink)
                            Spacer()
                            Text(x.who).font(TripInk.mono(9)).foregroundStyle(TripInk.g3)
                            Text(TripText.money(x.amount)).font(TripInk.serif(14)).foregroundStyle(TripInk.ink).frame(width: 56, alignment: .trailing)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if !t.spends.isEmpty { Hair() }
            }
            TripMat(name: "formula", tint: t.tint, opacity: 0.22).frame(height: 58).padding(.top, 20)
                .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .leading, endPoint: .trailing))
        } bar: {
            HStack { Button { sheet = .spend } label: { Text("＋ 记一笔").font(TripInk.serif(13)).foregroundStyle(TripInk.ink) }; Spacer() }
        }
    }
}

// MARK: 回顾

private struct TripRecap: View {
    let t: Trip
    var back: () -> Void
    @Binding var sheet: TripSheet?

    var body: some View {
        TripPage(title: "Remembered", tint: t.tint, back: back, menu: nil, foot: t.sum.status == "after" ? ("回来以后", "let it stay…") : nil) {
            if t.sum.status != "after" {
                VStack(spacing: 12) {
                    Text("回来以后，这里会把这几天收成一页").font(TripInk.serif(13)).foregroundStyle(TripInk.g3)
                    Mono("\(TripText.md(t.end)) 之后")
                }
                .frame(maxWidth: .infinity).padding(.top, 140)
            } else {
                if let ph = t.dayList.compactMap({ t.dayNotes[$0]?.photo }).first(where: { !$0.isEmpty }) {
                    AsyncImage(url: AlcoveAPI.fullURL("/\(ph)")) { i in i.resizable().scaledToFill() } placeholder: { Color.clear }
                        .frame(height: 250).clipped().allowsHitTesting(false).padding(.horizontal, -22)
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.16), .init(color: .black, location: 0.64), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(TripText.md(t.start))—\(String(t.end.suffix(2)))").font(TripInk.serif(40))
                    HStack(spacing: 6) { Mono("\(t.nameEn.isEmpty ? t.name : t.nameEn) · \(t.sum.days) 天"); Text("· 花了 \(TripText.money(t.sum.spent)) · 去了 \(t.stops.count) 个地方").font(TripInk.serif(10)).foregroundStyle(TripInk.g1) }
                }
                .padding(.top, 12)
                VStack(spacing: 0) {
                    ForEach(t.dayList, id: \.self) { d in
                        let note = t.dayNotes[d]
                        Button { sheet = .dayNote(d) } label: {
                            TripRow {
                                Text(TripText.md(d)).font(TripInk.serif(12)).frame(width: 40, alignment: .leading)
                                Text((note?.line ?? "").isEmpty ? "写一句这天…" : (note?.line ?? "")).font(TripInk.serif(14)).foregroundStyle((note?.line ?? "").isEmpty ? TripInk.g3 : TripInk.ink).lineSpacing(6)
                                Spacer()
                                if let p = note?.photo, !p.isEmpty {
                                    AsyncImage(url: AlcoveAPI.fullURL("/\(p)")) { i in i.resizable().scaledToFill() } placeholder: { Color.clear }.frame(width: 34, height: 34).clipped()
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Hair()
                }
                .padding(.top, 18)
                    VStack(alignment: .leading, spacing: 8) {
                        Rectangle().fill(TripInk.ink).frame(height: 0.5)
                        HStack { Mono("CE VOYAGE · 这一趟", color: TripInk.ink); Spacer(); Text("璟写的").font(TripInk.mono(9)).foregroundStyle(TripInk.g3) }.padding(.top, 4)
                        Text(t.letter.isEmpty ? "他还没写" : t.letter).font(TripInk.serif(13)).foregroundStyle(t.letter.isEmpty ? TripInk.g3 : TripInk.ink).lineSpacing(8)
                    }
                    .background(alignment: .bottomTrailing) {
                        TripMat(name: "lily", tint: t.tint, opacity: 0.24).frame(width: 220, height: 214)
                            .mask(RadialGradient(colors: [.black, .clear], center: .center, startRadius: 40, endRadius: 110)).offset(x: 60, y: 40)
                    }
                .padding(.top, 26)
            }
        } bar: { EmptyView() }
    }
}

// MARK: 底部弹单（新建 / 改 / 删）

private struct TripField: View {
    let label: String; @Binding var text: String; var placeholder = ""; var keyboard: UIKeyboardType = .default
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Mono(label)
            TextField(placeholder, text: $text).font(TripInk.serif(15)).keyboardType(keyboard).padding(.vertical, 6)
            Rectangle().fill(Color.black.opacity(0.3)).frame(height: 0.6)
        }
        .padding(.bottom, 12)
    }
}

private struct TripChips: View {
    let label: String; let options: [String]; @Binding var selected: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Mono(label)
            FlowChips(options: options, selected: $selected)
        }
        .padding(.bottom, 12)
    }
}

private struct FlowChips: View {
    let options: [String]; @Binding var selected: String
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { o in
                    Button { selected = o } label: {
                        Text(o).font(TripInk.serif(12)).padding(.horizontal, 11).padding(.vertical, 4)
                            .foregroundStyle(selected == o ? TripInk.paper : TripInk.g1)
                            .background(Capsule().fill(selected == o ? TripInk.ink : Color.clear))
                            .overlay(Capsule().stroke(selected == o ? TripInk.ink : Color.black.opacity(0.3), lineWidth: 0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct TripButton: View {
    let title: String; var solid = false; var warn = false; var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(TripInk.serif(14)).padding(.horizontal, 20).padding(.vertical, 9)
                .foregroundStyle(solid ? TripInk.paper : (warn ? Color(red: 0.64, green: 0.2, blue: 0.2) : TripInk.ink))
                .background(Capsule().fill(solid ? TripInk.ink : Color.clear))
                .overlay(Capsule().stroke(warn ? Color(red: 0.64, green: 0.2, blue: 0.2) : TripInk.ink, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }
}

private struct TripSheetView: View {
    let kind: TripSheet
    @ObservedObject var store: TripStore
    @Binding var day: String
    let packTab: String
    let wishTab: String
    var onPickCover: () -> Void
    var onDeleted: () -> Void
    var onCreated: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    // 表单字段（各弹单共用）
    @State private var a = ""
    @State private var b = ""
    @State private var c = ""
    @State private var d = ""
    @State private var e = ""
    @State private var pick1 = ""
    @State private var pick2 = ""
    @State private var pick3 = ""
    @State private var flag = false
    @State private var date1 = Date()
    @State private var date2 = Date().addingTimeInterval(4 * 86400)
    @State private var img = ""
    @State private var rt = ""   // 1108 #4915 日程一站的「怎么走」（从上一站过来）
    @State private var photo: PhotosPickerItem?
    @State private var tplPicks: Set<String> = []
    @State private var tpl: [(String, String)] = []
    @State private var ready = false

    private var t: Trip? { store.trip }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { if !ready { fill(); ready = true } }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let kindName: String = {
                        if case .dayNote = kind { return "day" }
                        if case .menu = kind { return "cover" }
                        return "ticket"
                    }()
                    let j = await store.upload(data, kind: kindName)
                    if kindName == "cover" {
                        if (j["ok"] as? Bool) == true {
                            store.say("封面换好了")
                            await store.reload()
                        }
                    } else if let p = j["path"] as? String { img = p; store.say("传好了") }
                }
                photo = nil
            }
        }
    }

    private func title(_ s: String) -> some View { Text(s).font(TripInk.pin(22)).padding(.bottom, 14) }
    private func days() -> [String] { t?.dayList ?? [] }
    private func dayFromMD(_ m: String) -> String? { days().first { TripText.md($0) == m } }

    @ViewBuilder private var content: some View {
        switch kind {
        case .newTrip, .editTrip: tripForm
        case .menu: menu
        case .delTrip: delTrip
        case .item(let id): itemForm(id)
        case .template: template
        case .stop(let id): stopForm(id)
        case .fromWish: fromWish
        case .wish(let id): wishForm(id)
        case .ticket(let id): ticketForm(id)
        case .spend: spendForm
        case .spendRow(let id): spendRow(id)
        case .dayNote(let dd): dayNote(dd)
        }
    }

    private func fill() {
        switch kind {
        case .editTrip:
            if let t { a = t.name; b = t.nameEn; c = t.fromCity; d = t.budget > 0 ? "\(t.budget)" : ""; e = t.flight; pick1 = t.boarding; pick2 = t.seat
                date1 = TripText.date(t.start) ?? Date(); date2 = TripText.date(t.end) ?? Date() }
        case .newTrip:
            c = "上海"; flag = true
        case .item(let id):
            if let id, let it = t?.items.first(where: { $0.id == id }) { a = it.text; b = it.note; pick1 = it.grp } else { pick1 = packTab == "全部" ? "其他" : packTab }
        case .stop(let id):
            if let id, let x = t?.stops.first(where: { $0.id == id }) { a = x.time; b = x.title; c = x.dur; d = x.addr; e = x.note; rt = x.route; pick1 = TripText.how(x.how); pick2 = TripText.md(x.day) }
            else { pick2 = TripText.md(day) }
        case .wish(let id):
            if let id, let w = t?.wishes.first(where: { $0.id == id }) { a = w.name; b = w.note; pick1 = w.cat } else { pick1 = wishTab == "全部" ? "逛" : wishTab }
        case .ticket(let id):
            if let id, let k = t?.tickets.first(where: { $0.id == id }) { a = k.title; b = k.at; c = k.l1; d = k.l2; e = k.code; img = k.img; pick1 = TripText.kind(k.kind) }
            else { pick1 = "机票"; b = t?.start ?? "" }
        case .spend:
            pick1 = "吃"; pick2 = "霁"
            if let t { let td = TripText.ymdBJ(TripText.localNow(t.tz)); pick3 = TripText.md(t.dayList.contains(td) ? td : t.start) }
        case .dayNote(let dd):
            a = t?.dayNotes[dd]?.line ?? ""; img = t?.dayNotes[dd]?.photo ?? ""
        case .template:
            Task {
                if let j = try? await AlcoveAPI.getRaw("/api/trip/template") {
                    tpl = (j["template"] as? [[String: Any]] ?? []).map { (s($0, "grp"), s($0, "text")) }
                    let have = Set(t?.items.map { $0.text } ?? [])
                    tplPicks = Set(tpl.map { $0.1 }.filter { !have.contains($0) })
                }
            }
        default: break
        }
    }

    private func done() async { dismiss(); await store.reload() }

    // 新建 / 改这次旅行
    private var tripForm: some View {
        let editing: Bool = { if case .editTrip = kind { return true }; return false }()
        return VStack(alignment: .leading, spacing: 0) {
            title(editing ? "edit" : "new voyage")
            TripField(label: "目的地", text: $a, placeholder: "京都")
            TripField(label: "英文 / 拼音", text: $b, placeholder: "Kyoto")
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) { Mono("出发"); DatePicker("", selection: $date1, displayedComponents: .date).labelsHidden() }
                VStack(alignment: .leading, spacing: 5) { Mono("回来"); DatePicker("", selection: $date2, in: date1..., displayedComponents: .date).labelsHidden() }
            }
            .padding(.bottom, 12)
            HStack(spacing: 14) { TripField(label: "从哪出发", text: $c); TripField(label: "预算（元）", text: $d, keyboard: .numberPad) }
            if editing {
                HStack(spacing: 14) { TripField(label: "航班", text: $e); TripField(label: "登机时间", text: $pick1); TripField(label: "座位", text: $pick2) }
            } else {
                Toggle(isOn: $flag) { Text("准备清单先从模板带一份").font(TripInk.serif(13)) }.tint(TripInk.ink).padding(.bottom, 12)
            }
            HStack {
                if editing { TripButton(title: "删掉这次", warn: true) { store.say(""); dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NotificationCenter.default.post(name: .tripAskDelete, object: nil) } } }
                Spacer()
                TripButton(title: editing ? "存好" : "建好", solid: true) { Task { await saveTrip(editing) } }
            }
            .padding(.top, 8)
        }
    }

    private func saveTrip(_ editing: Bool) async {
        guard !a.trimmingCharacters(in: .whitespaces).isEmpty else { store.say("写一下去哪"); return }
        var body: [String: Any] = ["name": a, "name_en": b, "start": TripText.ymd.string(from: date1), "end": TripText.ymd.string(from: max(date1, date2)),
                                   "from_city": c, "budget": Int(d) ?? 0]
        if editing, let t {
            body["id"] = t.id; body["flight"] = e; body["boarding"] = pick1; body["seat"] = pick2; body["regeo"] = a != t.name
            let j = await store.post("save", body)
            if (j["ok"] as? Bool) == true { await done() }
        } else {
            body["template"] = flag
            let j = await store.post("save", body)
            if (j["ok"] as? Bool) == true, let id = (j["id"] as? NSNumber)?.intValue { dismiss(); onCreated(id) }
        }
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            title(t?.name ?? "")
            Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NotificationCenter.default.post(name: .tripAskEdit, object: nil) } } label: {
                TripRow { Text("改目的地、日期、航班").font(TripInk.serif(14)).foregroundStyle(TripInk.ink); Spacer() }
            }.buttonStyle(.plain)
            PhotosPicker(selection: $photo, matching: .images) {
                TripRow { Text("换封面照片").font(TripInk.serif(14)).foregroundStyle(TripInk.ink); Spacer() }
            }
            .buttonStyle(.plain)
            // 1105 钟那页不再是入口了：换一趟、新建都从这里
            ForEach(store.trips.filter { $0.id != t?.id }) { o in
                Button { dismiss(); onCreated(o.id) } label: {
                    TripRow { Text("换到「\(o.name)」").font(TripInk.serif(14)).foregroundStyle(TripInk.ink); Spacer()
                        Text(TripText.md(o.start)).font(.custom("CormorantGaramond-Medium", size: 13)).foregroundStyle(TripInk.g1) }
                }.buttonStyle(.plain)
            }
            Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NotificationCenter.default.post(name: .tripAskNew, object: nil) } } label: {
                TripRow { Text("＋ 新的一次旅行").font(TripInk.serif(14)).foregroundStyle(TripInk.ink); Spacer() }
            }.buttonStyle(.plain)
        }
    }

    private var delTrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("sure?")
            Text("删掉「\(t?.name ?? "")」这次旅行？清单、日程、票据都会一起不见。").font(TripInk.serif(13)).foregroundStyle(TripInk.g1)
            HStack {
                TripButton(title: "算了") { dismiss() }
                Spacer()
                TripButton(title: "删掉", warn: true) { Task { if let t { await store.post("delete", ["id": t.id]) }; dismiss(); onDeleted() } }
            }
            .padding(.top, 18)
        }
    }

    private func itemForm(_ id: Int?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            title(id == nil ? "add" : "edit")
            TripField(label: "要带的东西", text: $a, placeholder: "转换插头")
            TripField(label: "备注（可空）", text: $b)
            TripChips(label: "分组", options: TripText.groups, selected: $pick1)
            HStack {
                if let id { TripButton(title: "删掉", warn: true) { Task { await store.post("item", ["op": "delete", "id": id]); await done() } } }
                Spacer()
                TripButton(title: "好", solid: true) {
                    Task {
                        guard let t else { return }
                        var body: [String: Any] = ["trip_id": t.id, "text": a, "note": b, "grp": pick1, "who": "霁"]
                        if let id { body["op"] = "edit"; body["id"] = id } else { body["op"] = "add" }
                        let j = await store.post("item", body)
                        if (j["ok"] as? Bool) == true { await done() }
                    }
                }
            }
        }
    }

    private var template: some View {
        let have = Set(t?.items.map { $0.text } ?? [])
        return VStack(alignment: .leading, spacing: 0) {
            title("from template")
            Text("勾上要的，已经有的不会重复加").font(TripInk.serif(10)).foregroundStyle(TripInk.g1).padding(.bottom, 8)
            ForEach(tpl.indices, id: \.self) { i in
                let g = tpl[i].0, text = tpl[i].1
                let has = have.contains(text)
                Button {
                    if has { return }
                    if tplPicks.contains(text) { tplPicks.remove(text) } else { tplPicks.insert(text) }
                } label: {
                    TripRow {
                        Image(systemName: has || tplPicks.contains(text) ? "checkmark.circle.fill" : "circle").font(.system(size: 14, weight: .light)).foregroundStyle(has ? TripInk.g3 : TripInk.ink)
                        Text(text).font(TripInk.serif(14)).foregroundStyle(has ? TripInk.g3 : TripInk.ink)
                        Spacer()
                        Text(g).font(TripInk.mono(9)).foregroundStyle(TripInk.g3)
                    }
                }
                .buttonStyle(.plain)
            }
            HStack { Spacer(); TripButton(title: "加进清单", solid: true) {
                Task { if let t { await store.post("item", ["op": "template", "trip_id": t.id, "texts": Array(tplPicks), "who": "霁"]) }; await done() }
            } }.padding(.top, 16)
        }
    }

    private func stopForm(_ id: Int?) -> some View {
        let x = id.flatMap { i in t?.stops.first { $0.id == i } }
        return VStack(alignment: .leading, spacing: 0) {
            title(id == nil ? "add" : "edit")
            TripField(label: "几点", text: $a, placeholder: "14:10", keyboard: .numbersAndPunctuation)
            TripField(label: "去哪 / 做什么", text: $b, placeholder: "锦市场吃晚饭")
            TripChips(label: "怎么去", options: TripText.hows.map { $0.1 }, selected: $pick1)
            HStack(spacing: 14) { TripField(label: "要多久", text: $c, placeholder: "12 分钟"); TripField(label: "地址（导航用）", text: $d) }
            VStack(alignment: .leading, spacing: 5) {
                Mono("怎么走（从上一站过来）")
                TextField("地铁 2 号线换 18 号线，约 2 小时；打车约 200", text: $rt, axis: .vertical).lineLimit(1...5)
                    .font(TripInk.serif(15)).padding(.vertical, 6)
                Rectangle().fill(Color.black.opacity(0.3)).frame(height: 0.6)
            }
            .padding(.bottom, 12)
            TripField(label: "备注", text: $e)
            TripChips(label: "哪一天", options: days().map(TripText.md), selected: $pick2)
            HStack {
                if let id { TripButton(title: "删掉", warn: true) { Task { await store.post("stop", ["op": "delete", "id": id]); await done() } } }
                Spacer()
                if let x, !(x.addr.isEmpty && x.title.isEmpty) {
                    TripButton(title: "导航") {
                        let q = "\(x.addr.isEmpty ? x.title : x.addr) \(t?.name ?? "")"
                        if let u = URL(string: "https://maps.apple.com/?q=" + (q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) { UIApplication.shared.open(u) }
                    }
                }
                TripButton(title: "好", solid: true) {
                    Task {
                        guard let t else { return }
                        guard !b.trimmingCharacters(in: .whitespaces).isEmpty else { store.say("写一下去哪"); return }
                        let dd = dayFromMD(pick2) ?? day
                        var body: [String: Any] = ["trip_id": t.id, "time": a, "title": b, "how": TripText.hows.first { $0.1 == pick1 }?.0 ?? "",
                                                   "dur": c, "addr": d, "note": e, "route": rt, "day": dd, "who": "霁"]
                        if let id { body["op"] = "edit"; body["id"] = id } else { body["op"] = "add" }
                        let j = await store.post("stop", body)
                        if (j["ok"] as? Bool) == true { day = dd; await done() }
                    }
                }
            }
        }
    }

    private var fromWish: some View {
        let ws = t?.wishes.filter { $0.stopId == nil } ?? []
        return VStack(alignment: .leading, spacing: 0) {
            title("from someday")
            Text("排进 \(TripText.md(day))").font(TripInk.serif(10)).foregroundStyle(TripInk.g1).padding(.bottom, 8)
            if ws.isEmpty { Text("想去池里没有没排的了").font(TripInk.serif(13)).foregroundStyle(TripInk.g3).padding(.vertical, 20) }
            ForEach(ws) { w in
                Button { Task { await store.post("wish", ["op": "schedule", "id": w.id, "day": day, "time": ""]); store.say("排进去了，时间点开那一项再填"); await done() } } label: {
                    TripRow { Text(w.name).font(TripInk.serif(14)).foregroundStyle(TripInk.ink); Spacer(); Text(w.cat).font(TripInk.mono(9)).foregroundStyle(TripInk.g3) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func wishForm(_ id: Int?) -> some View {
        let w = id.flatMap { i in t?.wishes.first { $0.id == i } }
        return VStack(alignment: .leading, spacing: 0) {
            title(id == nil ? "add" : "someday")
            TripField(label: "地方", text: $a, placeholder: "一保堂茶铺")
            TripField(label: "一句备注", text: $b, placeholder: "买抹茶带回去")
            TripChips(label: "分类", options: TripText.wishCats, selected: $pick1)
            if w != nil { TripChips(label: w?.stopId == nil ? "排进哪天" : "已经排了 · 改到哪天", options: days().map(TripText.md), selected: $pick2) }
            HStack {
                if let id { TripButton(title: "删掉", warn: true) { Task { await store.post("wish", ["op": "delete", "id": id]); await done() } } }
                if let id, w?.stopId != nil { TripButton(title: "先不排") { Task { await store.post("wish", ["op": "unschedule", "id": id]); await done() } } }
                Spacer()
                TripButton(title: "好", solid: true) {
                    Task {
                        guard let t else { return }
                        let body: [String: Any] = ["trip_id": t.id, "name": a, "note": b, "cat": pick1, "who": "霁"]
                        guard let id else {
                            let j = await store.post("wish", body.merging(["op": "add"]) { $1 })
                            if (j["ok"] as? Bool) == true { await done() }
                            return
                        }
                        await store.post("wish", body.merging(["op": "edit", "id": id]) { $1 })
                        if let dd = dayFromMD(pick2) {
                            if w?.stopId != nil { await store.post("wish", ["op": "unschedule", "id": id]) }
                            await store.post("wish", ["op": "schedule", "id": id, "day": dd])
                        }
                        await done()
                    }
                }
            }
        }
    }

    private func ticketForm(_ id: Int?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            title(id == nil ? "keep one" : "ticket")
            PhotosPicker(selection: $photo, matching: .images) {
                ZStack {
                    if img.isEmpty {
                        Rectangle().stroke(style: StrokeStyle(lineWidth: 0.5, dash: [4, 3])).foregroundStyle(Color.black.opacity(0.3))
                        Text("＋ 选一张截图").font(TripInk.serif(12)).foregroundStyle(TripInk.g1)
                    } else {
                        AsyncImage(url: AlcoveAPI.fullURL("/\(img)")) { i in i.resizable().scaledToFit() } placeholder: { ProgressView() }
                    }
                }
                .frame(maxWidth: .infinity).frame(height: img.isEmpty ? 90 : 260)
            }
            .padding(.bottom, 12)
            TripChips(label: "种类", options: TripText.kinds.map { $0.1 }, selected: $pick1)
            TripField(label: "标题", text: $a, placeholder: "浦东 → 关西")
            TripField(label: "日期", text: $b, placeholder: "2026-12-18", keyboard: .numbersAndPunctuation)
            TripField(label: "第一行", text: $c, placeholder: "10:25 起飞 · 32A / 32B")
            TripField(label: "第二行", text: $d)
            TripField(label: "编号 / 订单号", text: $e, placeholder: "MU 291")
            HStack {
                if let id { TripButton(title: "删掉", warn: true) { Task { await store.post("ticket", ["op": "delete", "id": id]); await done() } } }
                Spacer()
                TripButton(title: "好", solid: true) {
                    Task {
                        guard let t else { return }
                        var body: [String: Any] = ["trip_id": t.id, "kind": TripText.kinds.first { $0.1 == pick1 }?.0 ?? "other", "title": a, "at": b,
                                                   "l1": c, "l2": d, "code": e, "img": img, "who": "霁"]
                        if let id { body["op"] = "edit"; body["id"] = id } else { body["op"] = "add" }
                        let j = await store.post("ticket", body)
                        if (j["ok"] as? Bool) == true { await done() }
                    }
                }
            }
        }
    }

    private var spendForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("spent")
            TripField(label: "多少钱", text: $a, keyboard: .decimalPad)
            TripField(label: "买了什么", text: $b, placeholder: "鸭川边咖啡 · 两杯")
            TripChips(label: "分类", options: TripText.spendCats, selected: $pick1)
            TripChips(label: "谁付的", options: ["霁", "璟"], selected: $pick2)
            TripChips(label: "哪天", options: days().map(TripText.md), selected: $pick3)
            Toggle(isOn: $flag) { Text("提前付的（比如酒店），不算进每天").font(TripInk.serif(13)) }.tint(TripInk.ink).padding(.bottom, 12)
            HStack { Spacer(); TripButton(title: "记下", solid: true) {
                Task {
                    guard let t else { return }
                    guard let amt = Double(a), amt > 0 else { store.say("金额填一下"); return }
                    let j = await store.post("spend", ["op": "add", "trip_id": t.id, "amount": amt, "text": b, "cat": pick1, "who": pick2,
                                                       "day": dayFromMD(pick3) ?? t.start, "prepaid": flag])
                    if (j["ok"] as? Bool) == true { await done() }
                }
            } }
        }
    }

    private func spendRow(_ id: Int) -> some View {
        let x = t?.spends.first { $0.id == id }
        return VStack(alignment: .leading, spacing: 0) {
            title("this one")
            Text("\(x.map { $0.text.isEmpty ? $0.cat : $0.text } ?? "") · ¥\(TripText.money(x?.amount ?? 0))").font(TripInk.serif(14))
            HStack {
                TripButton(title: "删掉", warn: true) { Task { await store.post("spend", ["op": "delete", "id": id]); await done() } }
                Spacer()
                TripButton(title: "留着") { dismiss() }
            }
            .padding(.top, 18)
        }
    }

    private func dayNote(_ dd: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            title(TripText.md(dd))
            PhotosPicker(selection: $photo, matching: .images) {
                ZStack {
                    if img.isEmpty {
                        Rectangle().stroke(style: StrokeStyle(lineWidth: 0.5, dash: [4, 3])).foregroundStyle(Color.black.opacity(0.3))
                        Text("＋ 这天的一张照片").font(TripInk.serif(12)).foregroundStyle(TripInk.g1)
                    } else {
                        AsyncImage(url: AlcoveAPI.fullURL("/\(img)")) { i in i.resizable().scaledToFill() } placeholder: { ProgressView() }.clipped()
                    }
                }
                .frame(maxWidth: .infinity).frame(height: img.isEmpty ? 80 : 200).clipped()
            }
            .padding(.bottom, 12)
            Mono("这天的一句话").padding(.bottom, 5)
            TextField("", text: $a, axis: .vertical).font(TripInk.serif(15)).lineLimit(2...6).padding(.vertical, 6)
            Rectangle().fill(Color.black.opacity(0.3)).frame(height: 0.6)
            HStack { Spacer(); TripButton(title: "好", solid: true) {
                Task { if let t { await store.post("day", ["trip_id": t.id, "day": dd, "line": a, "photo": img]) }; await done() }
            } }.padding(.top, 16)
        }
    }
}

extension Notification.Name {
    static let tripAskEdit = Notification.Name("trip.askEdit")
    static let tripAskDelete = Notification.Name("trip.askDelete")
    static let tripAskNew = Notification.Name("trip.askNew")
}

// MARK: - 参考图（1105 #4758 / #4771）
// 她收别人拍的雪山、旅行图，随时拿出来看。地点她自己随时建（不跟行程绑），最后一个「其他」；人物 / 景色上传时她自己选。
// 只给她：陈璟那边不接（她：「这个不关他的事」）。后端 trip_api.insp_*，图存 trip/up/（长边 2400，放大看得清）。
// 样子照 1105 效果图：Inspiration 标题、一排地点横滑、全部 / 人物 / 景色、两列按原比例瀑布流、不裁不染色。

struct InspPlace: Identifiable, Equatable { let id: Int; let name: String; let n: Int }
struct InspPhoto: Identifiable, Equatable {
    let id: Int; let placeId: Int; let kind: String; let url: String; let w: Int; let h: Int
    /// 宽 / 高；拿不到尺寸当方的
    var aspect: CGFloat { w > 0 && h > 0 ? CGFloat(w) / CGFloat(h) : 1 }
}

private struct TripInspiration: View {
    var startPlace: String?
    var back: () -> Void

    @State private var places: [InspPlace] = []
    @State private var photos: [InspPhoto] = []
    @State private var sel: Int?                 // nil 全部；0 其他；>0 某个地点
    @State private var kind = "all"              // all / person / scene
    @State private var loaded = false
    @State private var picking = false
    @State private var picks: [PhotosPickerItem] = []
    @State private var pending: [Data] = []      // 选好了，等她定放哪
    @State private var showUpload = false
    @State private var viewing: InspPhoto?
    @State private var delPhoto: InspPhoto?
    @State private var askDel = false
    @State private var renaming: InspPlace?
    @State private var askRename = false
    @State private var renameText = ""
    @State private var toast = ""

    private var shown: [InspPhoto] {
        photos.filter { p in
            (sel == nil || p.placeId == sel!) && (kind == "all" || p.kind == kind)
        }
    }

    var body: some View {
        TripPage(title: "Inspiration", tint: "", back: back, plus: { picking = true },
                 foot: ("\(photos.count) 张 · \(places.count) 处", "someday, there")) {
            placeTabs.padding(.top, 8)       // 1105 她：顶上「参考图」几个小字去掉
            HStack(spacing: 0) {
                ForEach(Array([("all", "全部"), ("person", "人物"), ("scene", "景色")].enumerated()), id: \.offset) { i, o in
                    if i > 0 { Text("/").font(.custom("CormorantGaramond-Medium", size: 13)).foregroundStyle(TripInk.g3).padding(.horizontal, 6) }
                    Button { kind = o.0 } label: {
                        Text(o.1).font(TripInk.serif(11)).foregroundStyle(kind == o.0 ? TripInk.ink : TripInk.g3)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("\(shown.count)").font(.custom("CormorantGaramond-Medium", size: 15)).foregroundStyle(TripInk.g1)
            }
            .padding(.top, 14)
            Hair().padding(.top, 10)
            if shown.isEmpty {
                Text(loaded ? (photos.isEmpty ? "看到喜欢的图，点下面放进来" : "这里还没有") : "")
                    .font(TripInk.serif(13)).foregroundStyle(TripInk.g3).frame(maxWidth: .infinity).padding(.vertical, 60)
            } else {
                masonry.padding(.top, 12)
            }
        } bar: {
            HStack { Button { picking = true } label: { Text("＋ 放几张进来").font(TripInk.serif(13)).foregroundStyle(TripInk.ink) }; Spacer() }
        }
        .overlay {
            if !toast.isEmpty {
                VStack { Spacer()
                    Text(toast).font(TripInk.serif(12)).foregroundStyle(TripInk.plainBG)
                        .padding(.horizontal, 14).padding(.vertical, 7).background(Capsule().fill(TripInk.ink.opacity(0.9)))
                        .padding(.bottom, 110 + TripSafe.bottom)
                }
                .allowsHitTesting(false)
            }
        }
        .photosPicker(isPresented: $picking, selection: $picks, maxSelectionCount: nil, selectionBehavior: .ordered, matching: .images)
        .onChange(of: picks) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var datas: [Data] = []
                for it in items { if let d = try? await it.loadTransferable(type: Data.self) { datas.append(d) } }
                picks = []
                guard !datas.isEmpty else { say("没读到图"); return }
                pending = datas
                showUpload = true
            }
        }
        .sheet(isPresented: $showUpload) {
            InspUploadSheet(count: pending.count, places: places, startPlace: sel,
                            create: { name in await createPlace(name) },
                            done: { pid, k in showUpload = false; Task { await upload(pid, k) } })
                .presentationDetents([.medium])
                .presentationBackground(TripInk.paper)
        }
        .fullScreenCover(item: $viewing) { p in
            InspViewer(list: shown, start: p, close: { viewing = nil })
        }
        .confirmationDialog("删掉这张？", isPresented: $askDel, titleVisibility: .visible) {
            Button("删掉", role: .destructive) { if let p = delPhoto { Task { await edit(["id": p.id, "delete": true]) } } }
        }
        .alert("改名", isPresented: $askRename) {
            TextField("地点", text: $renameText)
            Button("好") { if let pl = renaming { Task { await placePost(["id": pl.id, "name": renameText]) } } }
            Button("算了", role: .cancel) {}
        }
        .task { await load() }
    }

    // 地点一排：全部 · 各地点 · 其他；长按某个地点出菜单改名 / 删掉
    private var placeTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                    tab("全部", nil)
                    ForEach(places) { pl in
                        tab(pl.name, pl.id).id(pl.id)
                            .contextMenu {
                                Button("改名") { renaming = pl; renameText = pl.name; askRename = true }
                                Button("删掉这个地点（图挪进「其他」）", role: .destructive) {
                                    Task { await placePost(["id": pl.id, "delete": true]); if sel == pl.id { sel = nil } }
                                }
                            }
                    }
                    tab("其他", 0)
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: sel) { _, v in if let v, v > 0 { withAnimation { proxy.scrollTo(v, anchor: .center) } } }
        }
    }

    private func tab(_ name: String, _ id: Int?) -> some View {
        Button { sel = id } label: {
            Text(name).font(TripInk.serif(13.5)).foregroundStyle(sel == id ? TripInk.ink : TripInk.g3)
                .padding(.bottom, 5)
                .overlay(alignment: .bottom) { if sel == id { Rectangle().fill(TripInk.ink).frame(height: 0.7) } }
        }
        .buttonStyle(.plain)
    }

    // 两列瀑布流：按原图宽高比，哪列矮放哪列
    private var masonry: some View {
        var a: [InspPhoto] = [], b: [InspPhoto] = []
        var ha: CGFloat = 0, hb: CGFloat = 0
        for p in shown {
            if ha <= hb { a.append(p); ha += 1 / p.aspect + 0.05 } else { b.append(p); hb += 1 / p.aspect + 0.05 }
        }
        return HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 8) { ForEach(a) { tile($0) } }.frame(maxWidth: .infinity)
            VStack(spacing: 8) { ForEach(b) { tile($0) } }.frame(maxWidth: .infinity)
        }
    }

    private func tile(_ p: InspPhoto) -> some View {
        Color.black.opacity(0.04)
            .aspectRatio(p.aspect, contentMode: .fit)
            .overlay {
                CachedImage(url: AlcoveAPI.fullURL(p.url)) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    .allowsHitTesting(false)       // 填满裁切的图点按范围不裁，别让它盖住别的
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { viewing = p }
            .contextMenu {
                Menu("挪到…") {
                    ForEach(places) { pl in Button(pl.name) { Task { await edit(["id": p.id, "place_id": pl.id]) } } }
                    Button("其他") { Task { await edit(["id": p.id, "place_id": 0]) } }
                }
                Button(p.kind == "person" ? "改成景色" : "改成人物") {
                    Task { await edit(["id": p.id, "kind": p.kind == "person" ? "scene" : "person"]) }
                }
                Button("删掉", role: .destructive) { delPhoto = p; askDel = true }
            }
    }

    // MARK: 数据
    private func load() async {
        guard let j = try? await AlcoveAPI.getRaw("/api/trip/insp/list") else { say("连不上"); return }
        places = (j["places"] as? [[String: Any]] ?? []).map { InspPlace(id: n($0, "id"), name: s($0, "name"), n: n($0, "n")) }
        photos = (j["photos"] as? [[String: Any]] ?? []).map {
            InspPhoto(id: n($0, "id"), placeId: n($0, "place_id"), kind: s($0, "kind"), url: s($0, "url"), w: n($0, "w"), h: n($0, "h"))
        }
        if !loaded, let name = startPlace, let hit = places.first(where: { $0.name == name }) { sel = hit.id }
        loaded = true
    }

    private func edit(_ body: [String: Any]) async {
        _ = try? await AlcoveAPI.postRaw("/api/trip/insp/photo", body: body)
        await load()
    }

    private func placePost(_ body: [String: Any]) async {
        if let j = try? await AlcoveAPI.postRaw("/api/trip/insp/place", body: body), (j["ok"] as? Bool) == false, let e = j["error"] as? String { say(e) }
        await load()
    }

    private func createPlace(_ name: String) async -> Int? {
        guard let j = try? await AlcoveAPI.postRaw("/api/trip/insp/place", body: ["name": name]) else { say("连不上"); return nil }
        if (j["ok"] as? Bool) == false { say((j["error"] as? String) ?? "没建成"); return nil }
        await load()
        return (j["id"] as? NSNumber)?.intValue
    }

    /// 一张张传：长边缩到 2400 再传（放大看得清，又不至于太慢）
    private func upload(_ placeId: Int, _ k: String) async {
        let datas = pending; pending = []
        var ok = 0
        for (i, d) in datas.enumerated() {
            say("上传中 \(i + 1) / \(datas.count)", hold: true)
            var body = d
            if let ui = UIImage(data: d) {
                let r = min(1, 2400 / max(ui.size.width, ui.size.height))
                let size = CGSize(width: ui.size.width * r, height: ui.size.height * r)
                let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
                body = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in ui.draw(in: CGRect(origin: .zero, size: size)) }
                    .jpegData(compressionQuality: 0.86) ?? d
            }
            var req = URLRequest(url: AlcoveAPI.fullURL("/api/trip/upload?kind=insp&place=\(placeId)&cat=\(k)&ext=jpg"))
            req.httpMethod = "POST"
            req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            if let res = try? await AlcoveAPI.session.data(for: req),
               let j = try? JSONSerialization.jsonObject(with: res.0) as? [String: Any], (j["ok"] as? Bool) == true { ok += 1 }
        }
        await load()
        sel = placeId
        say(ok == datas.count ? "放好了 \(ok) 张" : "放好 \(ok) 张，\(datas.count - ok) 张没传上去")
    }

    private func say(_ t: String, hold: Bool = false) {
        toast = t
        guard !hold else { return }
        Task { try? await Task.sleep(nanoseconds: 1_800_000_000); if toast == t { toast = "" } }
    }
}

/// 选完图：给这一批一起定地点、人物还是景色
private struct InspUploadSheet: View {
    let count: Int
    let places: [InspPlace]
    var startPlace: Int?
    var create: (String) async -> Int?
    var done: (Int, String) -> Void
    @State private var place = 0
    @State private var kind = "scene"
    @State private var newName = ""
    @State private var extra: [InspPlace] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("放进哪里").font(TripInk.serif(17)).foregroundStyle(TripInk.ink)
                Spacer()
                Text("\(count) 张").font(TripInk.serif(11)).foregroundStyle(TripInk.g1)
            }
            .padding(.bottom, 16)
            Mono("PLACE · 地点")
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(places + extra) { pl in chip(pl.name, on: place == pl.id) { place = pl.id } }
                    chip("其他", on: place == 0) { place = 0 }
                }
            }
            .scrollIndicators(.hidden)
            .padding(.top, 6)
            HStack(spacing: 10) {
                TextField("新地点，比如 四姑娘山", text: $newName).font(TripInk.serif(14))
                Button {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    Task {
                        if let id = await create(name) {
                            if !places.contains(where: { $0.id == id }) && !extra.contains(where: { $0.id == id }) { extra.append(InspPlace(id: id, name: name, n: 0)) }
                            place = id; newName = ""
                        }
                    }
                } label: { Text("建").font(TripInk.serif(13)).foregroundStyle(TripInk.ink) }
                .buttonStyle(.plain)
            }
            .padding(.top, 12)
            Rectangle().fill(Color.black.opacity(0.3)).frame(height: 0.6).padding(.top, 6)
            Mono("人物 / 景色").padding(.top, 18)
            HStack(spacing: 8) {
                chip("人物", on: kind == "person") { kind = "person" }
                chip("景色", on: kind == "scene") { kind = "scene" }
            }
            .padding(.top, 6)
            Spacer()
            HStack { Spacer(); TripButton(title: "放进来", solid: true) { done(place, kind) } }
        }
        .padding(22)
        .onAppear { if let p = startPlace { place = p } }
    }

    private func chip(_ t: String, on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(t).font(TripInk.serif(12)).padding(.horizontal, 11).padding(.vertical, 4)
                .foregroundStyle(on ? TripInk.paper : TripInk.g1)
                .background(Capsule().fill(on ? TripInk.ink : Color.clear))
                .overlay(Capsule().stroke(on ? TripInk.ink : Color.black.opacity(0.3), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }
}

/// 大图：左右滑、双指放大，单击关
private struct InspViewer: View {
    let list: [InspPhoto]
    let start: InspPhoto
    var close: () -> Void
    @State private var cur = 0
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $cur) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, p in
                    ZoomContainer(onSingleTap: close) {
                        CachedImage(url: AlcoveAPI.fullURL(p.url)) { $0.resizable().scaledToFit() } placeholder: { ProgressView().tint(.white) }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .ignoresSafeArea()
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            VStack {
                Spacer()
                Text("\(cur + 1) / \(list.count)").font(.custom("CormorantGaramond-Medium", size: 14)).foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, TripSafe.bottom + 8)
            }
            .allowsHitTesting(false)
        }
        .onAppear { cur = list.firstIndex(of: start) ?? 0 }
    }
}
