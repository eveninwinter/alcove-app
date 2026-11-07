import SwiftUI
import HealthKit
import CoreMotion

// MARK: - 1019 #4081–4082 健康页
// 她要单独一页，入口先放侧边栏（她说待会侧边栏要整个改版）。效果图 /root/rhysel/sanctus-kit/mock-health/a b c.html，她「可以」：
// - 平时：页头人像往下化开，花体 be well；「今天」一张大卡（蝴蝶），下面两排小卡：昨晚、心率、经期、身体。一屏看完。
// - 点哪张就在原地展开，别的缩成只剩花体名字的小条（今天那条带步数）；点「－」或「收起」收回去。
// - 昨晚展开：睡眠分段条＋前七晚柱子（圣母，很淡）；经期展开：月历＋这次几天＋平均周期＋下次大约（贝壳）。
// - 今天、心率、身体展开的样子效果图里没画，照同一套零件排的。
// 素材是她 1019 给的四张，抠成只有透明度的图，颜色在这里上（白天冷灰、黑夜白）。
// 数据当场从苹果健康读（只读）；步数、距离、楼层用手机计步（她：「走了多少步还是用现在的」）。心率那些要手表，没有就写空的那句。
// 1024 #4262–4264 她 AirPods Pro 3 到了：加第六张「运动」（moved，翅膀）。效果图 mock-health/d.html 她「可以」：
// 今天每一次（时长 · 千卡 · 心率 平均/最高），点哪次在那行下面展开这次的心率线（虚线平均、蓝点最高）；这一周每天几分钟。
// 原来身体卡里那段「今天的运动」挪过来了，身体卡只留体重、喝水、正念。
// 1107 #4871 她戴上小米手表：「以后不走苹果健康读了全部数据都走小米，缺的也按照小米有的加」。
// 心率、静息、血氧、压力、睡眠分段、活动、运动改从后端 /api/health/mi 拿（mi_sync.py 每 15 分钟从小米云拉）；
// 苹果健康只剩小米没有的：经期、体重、喝水、正念。步数、距离、楼层、每小时步数用手机计步（她 1019 定的）。
// 小米不给的走路心率、心率变异性、呼吸那几行拿掉了；心率卡展开加了血氧线和压力。

enum HPCard: String, CaseIterable, Identifiable {
    case today, sleep, heart, cycle, body, workout
    var id: String { rawValue }
    var script: String {
        switch self {
        case .today: return "today"
        case .sleep: return "slept"
        case .heart: return "heartbeat"
        case .cycle: return "cycle"
        case .body: return "body"
        case .workout: return "moved"
        }
    }
    var kickerEN: String {
        switch self {
        case .today: return "TODAY"
        case .sleep: return "SLEEP"
        case .heart: return "HEART"
        case .cycle: return "CYCLE"
        case .body: return "BODY"
        case .workout: return "WORKOUT"
        }
    }
    var kickerCN: String {
        switch self {
        case .today: return "今天"
        case .sleep: return "昨晚"
        case .heart: return "心率"
        case .cycle: return "经期"
        case .body: return "身体"
        case .workout: return "运动"
        }
    }
}

struct HPSeg { let a: Double; let b: Double; let kind: Int }

/// 一觉。kind / value：0 在床上 1 睡着（没分段）2 醒着 3 核心 4 深睡 5 快速眼动
struct HPNight {
    let start: Date
    let end: Date
    let asleep: TimeInterval
    let inBed: TimeInterval
    let staged: Bool
    let segs: [HPSeg]
    let deep: TimeInterval
    let core: TimeInterval
    let rem: TimeInterval
    let awake: TimeInterval
    var shown: TimeInterval { asleep > 0 ? asleep : inBed }
}

struct HPNightBar: Identifiable {
    let id: Int
    let label: String
    let hours: TimeInterval
    let isLast: Bool
    let start: Date?
    let end: Date?
}

struct HPWorkout: Identifiable {
    let id = UUID()
    let name: String
    let minutes: Double
    let kcal: Double?
    let start: Date
    var end: Date
    // 这次运动里的心率（耳机 / 手表测的），没测到就是空
    var hrAvg: Double?
    var hrMax: Double?
    var hrMaxAt: Date?
    var curve: [CGPoint] = []   // x：这次运动从头到尾的位置（0…1），y：心率
}

/// 这一周每天动了几分钟
struct HPMinuteBar: Identifiable {
    let id: Int
    let label: String
    let minutes: Double
    let isLast: Bool
}

struct HPCycle {
    let lastStart: Date
    let runDays: Int
    let flow: String?
    let avgLen: Int?
    let next: Date?
    let flowDays: Set<Date>
}

/// 每小时步数：二十几个计步查询各自在后台线程回来，攒在这儿
final class HPHourBox {
    private var v = Array(repeating: 0.0, count: 24)
    private let lock = NSLock()
    func set(_ i: Int, _ n: Double) { lock.lock(); if i >= 0 && i < 24 { v[i] = n }; lock.unlock() }
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return v }
}

final class HealthPageModel: ObservableObject {
    @Published var steps: Int?
    @Published var distanceKm: Double?
    @Published var floors: Int?
    @Published var activeKcal: Double?
    @Published var exerciseMin: Double?
    @Published var hourly: [Double] = Array(repeating: 0, count: 24)
    @Published var night: HPNight?
    @Published var week: [HPNightBar] = []
    @Published var hrLatest: Double?
    @Published var hrLatestAt: Date?
    @Published var hrMin: Double?
    @Published var hrMax: Double?
    @Published var hrAvg: Double?
    @Published var hrCurve: [CGPoint] = []   // x：今天 0 点到现在的位置（0…1），y：那半小时的平均心率
    @Published var resting: Double?
    @Published var spo2: Double?
    @Published var spo2At: Date?
    @Published var spo2Min: Double?
    @Published var spo2Max: Double?
    @Published var spo2Curve: [CGPoint] = []   // 同 hrCurve，十分钟一个点
    @Published var stressAvg: Double?
    @Published var stressMin: Double?
    @Published var stressMax: Double?
    @Published var stressBands: [(name: String, minutes: Double)] = []   // 放松 / 轻度 / 中度 / 重度 各几分钟
    @Published var miAt: Date?   // 后端那次从小米云拉的时间
    @Published var cycle: HPCycle?
    @Published var workouts: [HPWorkout] = []
    @Published var workoutWeek: [HPMinuteBar] = []
    @Published var weekLongest: (minutes: Double, label: String)?
    @Published var weight: Double?
    @Published var water: Double?
    @Published var mindful: Double?
    @Published var loadedAt: Date?
    let available = HKHealthStore.isHealthDataAvailable()

    private let store = HKHealthStore()
    private let pedometer = CMPedometer()

    func load() {
        loadedAt = Date()
        loadPedometer()
        loadMi()
        guard available else { return }
        // 问过的类型系统不再弹，直接回来；没问过的（直接从侧边栏进来）这里弹一次
        store.requestAuthorization(toShare: nil, read: HealthReporter.readTypes) { [weak self] _, _ in
            DispatchQueue.main.async { self?.query() }
        }
    }

    private func loadPedometer() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        let now = Date()
        pedometer.queryPedometerData(from: Calendar.current.startOfDay(for: now), to: now) { [weak self] d, _ in
            DispatchQueue.main.async {
                guard let self = self, let d = d else { return }
                self.steps = d.numberOfSteps.intValue
                if let m = d.distance?.doubleValue { self.distanceKm = m / 1000 }
                if let f = d.floorsAscended?.intValue { self.floors = f }
            }
        }
        // 每小时的步数也用手机计步（原来从苹果健康拿，1107 起不走苹果健康）
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        let box = HPHourBox()
        let group = DispatchGroup()
        for i in 0...cal.component(.hour, from: now) {
            guard let a = cal.date(byAdding: .hour, value: i, to: dayStart) else { continue }
            group.enter()
            pedometer.queryPedometerData(from: a, to: min(now, a.addingTimeInterval(3600))) { d, _ in
                if let n = d?.numberOfSteps.doubleValue { box.set(i, n) }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in self?.hourly = box.values }
    }

    // MARK: 小米（后端 /api/health/mi）

    private func loadMi() {
        var req = URLRequest(url: AlcoveAPI.fullURL("/api/health/mi"))
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue(Bundle.main.object(forInfoDictionaryKey: "AlcoveLocToken") as? String ?? "", forHTTPHeaderField: "X-Auth-Token")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let data = data,
                  let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  d["ok"] as? Bool == true else { return }
            DispatchQueue.main.async { self?.applyMi(d) }
        }.resume()
    }

    private static func num(_ x: Any?) -> Double? { (x as? NSNumber)?.doubleValue }

    private func applyMi(_ d: [String: Any]) {
        let num = HealthPageModel.num
        func dict(_ k: String) -> [String: Any] { d[k] as? [String: Any] ?? [:] }
        func pairs(_ k: String) -> [(Date, Double)] {
            (d[k] as? [[Any]] ?? []).compactMap { p -> (Date, Double)? in
                guard p.count == 2, let t = num(p[0]), let v = num(p[1]) else { return nil }
                return (Date(timeIntervalSince1970: t), v)
            }
        }
        let now = Date()
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        let span = max(1, now.timeIntervalSince(dayStart))
        func curve(_ pts: [(Date, Double)]) -> [CGPoint] {
            pts.filter { $0.0 >= dayStart }.map { CGPoint(x: min(1, $0.0.timeIntervalSince(dayStart) / span), y: $0.1) }
        }
        if let t = d["synced_at"] as? String { miAt = ISO8601DateFormatter().date(from: t) }
        let hr = pairs("hr_series")
        // 这份要是昨天的（过了零点还没拉到今天的），今天的数一律空着，别把昨天的当今天
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        if (d["date"] as? String) == f.string(from: now) {
            hrLatest = hr.last?.1
            hrLatestAt = hr.last?.0
            hrCurve = curve(hr)
            let h = dict("hr_daily")
            hrMin = num(h["min_bpm"]); hrMax = num(h["max_bpm"]); hrAvg = num(h["avg_bpm"])
            resting = num(h["resting_bpm"])
            let sp = pairs("spo2_series")
            spo2 = sp.last?.1
            spo2At = sp.last?.0
            spo2Curve = curve(sp)
            let s = dict("spo2_daily")
            spo2Min = num(s["min_spo2_pct"]); spo2Max = num(s["max_spo2_pct"])
            let st = dict("stress_daily")
            stressAvg = num(st["avg_stress_level"]); stressMin = num(st["min_stress_level"]); stressMax = num(st["max_stress_level"])
            stressBands = [("放松", "relaxed_min"), ("轻度", "mild_min"), ("中度", "moderate_min"), ("重度", "severe_min")]
                .map { (name: $0.0, minutes: num(st[$0.1]) ?? 0) }
            let a = dict("activity")
            activeKcal = num(a["active_kcal"])
            exerciseMin = num(a["activity_min"])
        }
        applySleep(HealthPageModel.miNights(d["sleep"] as? [[String: Any]] ?? []))
        applyWorkouts(d["workouts"] as? [[String: Any]] ?? [], hr)
    }

    /// 小米的睡眠一天一条，里面一段段 session（一觉，或者午睡），每段带 deep / light / rem / awake 分段。
    /// 换成页面原来那套 HPNight：kind 4 深睡、3 浅睡（苹果那时叫核心）、5 快速眼动、2 醒着、1 没分段
    static func miNights(_ days: [[String: Any]]) -> [HPNight] {
        let kinds = ["deep": 4, "light": 3, "rem": 5, "awake": 2]
        var out: [HPNight] = []
        for day in days {
            for s in day["sessions"] as? [[String: Any]] ?? [] {
                guard let a = num(s["start_epoch_s"]), let b = num(s["end_epoch_s"]), b > a else { continue }
                let asleep = (num(s["asleep_min"]) ?? 0) * 60
                guard asleep >= 1800 else { continue }   // 半小时以下的不算一觉
                let dur = b - a
                let segs = (s["stages"] as? [[String: Any]] ?? []).compactMap { x -> HPSeg? in
                    guard let p = num(x["start_epoch_s"]), let q = num(x["end_epoch_s"]) else { return nil }
                    return HPSeg(a: (p - a) / dur, b: (q - a) / dur, kind: kinds[x["stage"] as? String ?? ""] ?? 1)
                }
                func mins(_ k: String) -> TimeInterval { (num(s[k]) ?? 0) * 60 }
                out.append(HPNight(start: Date(timeIntervalSince1970: a), end: Date(timeIntervalSince1970: b),
                                   asleep: asleep, inBed: 0, staged: segs.contains { $0.kind != 1 },
                                   segs: segs.isEmpty ? [HPSeg(a: 0, b: 1, kind: 1)] : segs,
                                   deep: mins("deep_min"), core: mins("light_min"), rem: mins("rem_min"), awake: mins("awake_min")))
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    static func sportName(_ s: String?) -> String {
        switch s {
        case "running": return "跑步"
        case "biking": return "骑车"
        case "stair_climbing_machine": return "爬楼机"
        case "strength_training": return "力量训练"
        default: return "运动"   // 小米还有好多种，mifit 只认出这四种，别的一律叫运动
        }
    }

    /// 运动：拿这一周的，今天的列出来，七天按天加起来画柱子。
    /// 小米的运动摘要里只有平均、最高心率，没有心率线，就拿当天十分钟一条的心率凑这次运动时间里的点
    private func applyWorkouts(_ ws: [[String: Any]], _ hr: [(Date, Double)]) {
        let num = HealthPageModel.num
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: Date())
        let all: [HPWorkout] = ws.compactMap { w -> HPWorkout? in
            guard let a = num(w["start_epoch_s"]) else { return nil }
            let start = Date(timeIntervalSince1970: a)
            let secs = num(w["duration_s"]) ?? max(0, (num(w["end_epoch_s"]) ?? a) - a)
            let end = num(w["end_epoch_s"]).map { Date(timeIntervalSince1970: $0) } ?? start.addingTimeInterval(secs)
            var x = HPWorkout(name: HealthPageModel.sportName(w["sport"] as? String), minutes: secs / 60,
                              kcal: num(w["active_kcal"]) ?? num(w["total_kcal"]), start: start, end: end)
            x.hrAvg = num(w["avg_hr_bpm"])
            x.hrMax = num(w["max_hr_bpm"])
            let span = max(1, end.timeIntervalSince(start))
            x.curve = hr.filter { $0.0 >= start && $0.0 <= end }.map { CGPoint(x: $0.0.timeIntervalSince(start) / span, y: $0.1) }
            return x
        }.sorted { $0.start < $1.start }
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        workouts = all.filter { $0.start >= dayStart }
        workoutWeek = (0..<7).reversed().compactMap { i -> HPMinuteBar? in
            guard let day = cal.date(byAdding: .day, value: -i, to: dayStart) else { return nil }
            let mins = all.filter { cal.isDate($0.start, inSameDayAs: day) }.reduce(0.0) { $0 + $1.minutes }
            return HPMinuteBar(id: i, label: names[cal.component(.weekday, from: day) - 1], minutes: mins, isLast: i == 0)
        }
        weekLongest = all.max(by: { $0.minutes < $1.minutes }).map {
            (minutes: $0.minutes, label: names[cal.component(.weekday, from: $0.start) - 1])
        }
    }

    private func qt(_ id: HKQuantityTypeIdentifier) -> HKQuantityType? { HKObjectType.quantityType(forIdentifier: id) }

    private func sum(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ pred: NSPredicate, _ set: @escaping (Double) -> Void) {
        guard let t = qt(id) else { return }
        store.execute(HKStatisticsQuery(quantityType: t, quantitySamplePredicate: pred, options: .cumulativeSum) { _, s, _ in
            guard let v = s?.sumQuantity()?.doubleValue(for: unit) else { return }
            DispatchQueue.main.async { set(v) }
        })
    }

    private func latest(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, days: Double, _ set: @escaping (Double, Date) -> Void) {
        guard let t = qt(id) else { return }
        let now = Date()
        // 手表 App 写进健康的样本，时间可能比现在还晚（1107 小米 09:45 写的心率记成 10:00），只查到「现在」会漏，往后放一天
        let pred = HKQuery.predicateForSamples(withStart: now.addingTimeInterval(-days * 86400), end: now.addingTimeInterval(86400), options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        store.execute(HKSampleQuery(sampleType: t, predicate: pred, limit: 1, sortDescriptors: [sort]) { _, ss, _ in
            guard let s = ss?.first as? HKQuantitySample else { return }
            let v = s.quantity.doubleValue(for: unit)
            DispatchQueue.main.async { set(v, s.endDate) }
        })
    }

    /// 苹果健康里只读小米没有的：喝水、正念、体重、经期（1107 起别的都走小米）
    private func query() {
        let now = Date()
        let today = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: now), end: now, options: .strictStartDate)

        sum(.dietaryWater, .literUnit(with: .milli), today) { [weak self] v in self?.water = v }
        latest(.bodyMass, .gramUnit(with: .kilo), days: 90) { [weak self] v, _ in self?.weight = v }
        if let ft = HKObjectType.categoryType(forIdentifier: .menstrualFlow) {
            let pred = HKQuery.predicateForSamples(withStart: now.addingTimeInterval(-200 * 86400), end: now, options: [])
            store.execute(HKSampleQuery(sampleType: ft, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { [weak self] _, ss, _ in
                let c = HealthPageModel.cycle((ss as? [HKCategorySample]) ?? [])
                DispatchQueue.main.async { self?.cycle = c }
            })
        }
        if let mt = HKObjectType.categoryType(forIdentifier: .mindfulSession) {
            store.execute(HKSampleQuery(sampleType: mt, predicate: today, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { [weak self] _, ss, _ in
                let total = (ss ?? []).reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                DispatchQueue.main.async { self?.mindful = total > 0 ? total / 60 : nil }
            })
        }
    }

    // MARK: 睡眠

    private func applySleep(_ nights: [HPNight]) {
        night = nights.last
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        week = (0..<7).reversed().compactMap { i -> HPNightBar? in
            guard let day = cal.date(byAdding: .day, value: -i, to: today) else { return nil }
            let ns = nights.filter { cal.isDate($0.end, inSameDayAs: day) }   // 哪天早上醒的就算哪天
            let total = ns.reduce(0.0) { $0 + $1.shown }
            return HPNightBar(id: i, label: names[cal.component(.weekday, from: day) - 1], hours: total, isLast: i == 0,
                              start: ns.map { $0.start }.min(), end: ns.map { $0.end }.max())
        }
    }

    // MARK: 经期

    static func cycle(_ all: [HKCategorySample]) -> HPCycle? {
        let cal = Calendar.current
        let flow = all.filter { $0.value != 5 }.sorted { $0.startDate < $1.startDate }   // 5＝记了「没有」
        guard let last = flow.last else { return nil }
        let days = Set(flow.map { cal.startOfDay(for: $0.startDate) })
        var starts: [Date] = []
        var prev: Date?
        for d in days.sorted() {
            let gap = prev.map { cal.dateComponents([.day], from: $0, to: d).day ?? 99 } ?? 99
            if gap > 2 { starts.append(d) }   // 隔超过 2 天算下一次
            prev = d
        }
        guard let lastStart = starts.last else { return nil }
        let runDays = days.filter { $0 >= lastStart }.count
        var gaps: [Int] = []
        for i in starts.indices.dropFirst() {
            gaps.append(cal.dateComponents([.day], from: starts[i - 1], to: starts[i]).day ?? 0)
        }
        let recent = gaps.suffix(3).filter { $0 >= 15 && $0 <= 60 }
        let avg: Int? = recent.isEmpty ? nil : Int((Double(recent.reduce(0, +)) / Double(recent.count)).rounded())
        let next = avg.flatMap { cal.date(byAdding: .day, value: $0, to: lastStart) }
        let names = [1: "没写多少", 2: "少", 3: "中", 4: "多"]
        return HPCycle(lastStart: lastStart, runDays: runDays, flow: names[last.value], avgLen: avg, next: next, flowDays: days)
    }
}

// MARK: - 页面

struct HealthRoomView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var m = HealthPageModel()
    @State private var open: HPCard?
    @State private var pickedWorkout: UUID?
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    private var ink: SanctusCardInk { _ = houseAppearance; return SanctusCardInk() }
    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0 }
    private var safeBottom: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.bottom ?? 0 }

    var body: some View {
        let ink = self.ink
        ZStack(alignment: .topLeading) {
            (ink.dark ? HP.rgb(0x1B1C20) : HP.rgb(0xEFEFED)).ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    ZStack(alignment: .top) {
                        if open == nil { hero(ink) }
                        VStack(spacing: 10) {
                            if open == nil { header(ink) } else { miniHeader(ink) }
                            cards(ink)
                            Text("这一页上的数字，陈璟也看得到")
                                .font(.system(size: 10, design: .serif)).tracking(0.8).foregroundColor(ink.sub)
                                .padding(.top, 6)
                            Color.clear.frame(height: safeBottom + 24)
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .ignoresSafeArea(edges: .top)
                .onChange(of: open) { o in
                    guard o != nil else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo("hp-open", anchor: .top) }
                    }
                }
            }
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .regular))
                    .foregroundColor(open == nil ? .white : ink.link)
                    .shadow(color: .black.opacity(open == nil ? 0.25 : 0), radius: 3)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 8).padding(.top, safeTop)
            .accessibilityLabel("返回")
        }
        .onAppear { m.load() }
    }

    // MARK: 页头

    private func hero(_ ink: SanctusCardInk) -> some View {
        Color.clear
            .frame(height: safeTop + 205)
            .frame(maxWidth: .infinity)
            .overlay {
                Image("HealthPortrait").resizable().scaledToFill()
                    .saturation(0)
                    .brightness(ink.dark ? -0.28 : 0.2)
                    .contrast(ink.dark ? 0.9 : 0.62)
            }
            .clipped()
            .opacity(0.8)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.3), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
    }

    private func header(_ ink: SanctusCardInk) -> some View {
        VStack(spacing: 0) {
            Text("be well").font(SanctusCardFont.script(36)).foregroundColor(ink.dark ? HP.rgb(0xE4E4E7) : HP.rgb(0x2A2A2E))
            (Text("HEALTH · ").font(SanctusPageFont.corm(8.5)) + Text("健康").font(.system(size: 8.5, design: .serif)))
                .tracking(2.6).foregroundColor(ink.kicker).padding(.top, 9)
            Text("from your mi watch · \((m.miAt ?? m.loadedAt).map(HP.clock) ?? "")")
                .font(SanctusCardFont.ital(10.5)).foregroundColor(ink.sub).padding(.top, 5)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, safeTop + 66)
        .padding(.bottom, 16)
    }

    private func miniHeader(_ ink: SanctusCardInk) -> some View {
        (Text("HEALTH · ").font(SanctusPageFont.corm(8)) + Text("健康").font(.system(size: 8, design: .serif)))
            .tracking(2.6).foregroundColor(ink.kicker)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .padding(.top, safeTop)
            .padding(.bottom, 2)
    }

    // MARK: 卡片排法

    @ViewBuilder private func cards(_ ink: SanctusCardInk) -> some View {
        if let o = open {
            let order = HPCard.allCases
            let idx = order.firstIndex(of: o) ?? 0
            minis(Array(order[..<idx]), ink)
            expanded(o, ink).id("hp-open")
            minis(Array(order[(idx + 1)...]), ink)
        } else {
            todaySmall(ink)
            HStack(alignment: .top, spacing: 10) {
                sleepSmall(ink)
                heartSmall(ink)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 10) {
                cycleSmall(ink)
                bodySmall(ink)
            }
            .fixedSize(horizontal: false, vertical: true)
            workoutSmall(ink)
        }
    }

    private func toggle(_ c: HPCard?) {
        withAnimation(.easeInOut(duration: 0.25)) { open = c }
    }

    @ViewBuilder private func minis(_ list: [HPCard], _ ink: SanctusCardInk) -> some View {
        if list.contains(.today) { mini(.today, ink) }
        let rest = list.filter { $0 != .today }
        ForEach(Array(stride(from: 0, to: rest.count, by: 2)), id: \.self) { i in
            HStack(spacing: 10) {
                mini(rest[i], ink)
                if i + 1 < rest.count { mini(rest[i + 1], ink) } else { Color.clear.frame(maxWidth: .infinity) }
            }
        }
    }

    /// 别的卡展开时，这张缩成只剩花体名字的小条（今天那条带步数）
    private func mini(_ c: HPCard, _ ink: SanctusCardInk) -> some View {
        HPShell(ink: ink) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(c.script).font(SanctusCardFont.script(19)).foregroundColor(ink.script)
                if c == .today, let s = m.steps {
                    Text("\(HP.grouped(s)) steps").font(SanctusCardFont.ital(11)).foregroundColor(ink.sub)
                }
                Spacer(minLength: 0)
                Text("＋").font(SanctusPageFont.corm(15)).foregroundColor(ink.kicker)
            }
            .padding(.vertical, 4)
        }
        .opacity(0.72)
        .contentShape(Rectangle())
        .onTapGesture { toggle(c) }
    }

    private func head(_ c: HPCard, _ ink: SanctusCardInk, opened: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(c.script).font(SanctusCardFont.script(opened ? 23 : 21)).foregroundColor(ink.script)
                (Text("\(c.kickerEN) · ").font(SanctusCardFont.kicker()) + Text(c.kickerCN).font(.system(size: 7.5, design: .serif)))
                    .tracking(2.25).foregroundColor(ink.kicker)
            }
            Spacer(minLength: 0)
            Button { toggle(opened ? nil : c) } label: {
                Text(opened ? "－" : "＋").font(SanctusPageFont.corm(15)).foregroundColor(ink.kicker)
                    .frame(width: 30, height: 26, alignment: .topTrailing).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func big(_ value: String, _ unit: String, _ ink: SanctusCardInk, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value).font(SanctusPageFont.corm(size)).foregroundColor(ink.body)
            if !unit.isEmpty { Text(unit).font(SanctusCardFont.ital(10.5)).foregroundColor(ink.sub) }
        }
        .padding(.top, 9)
    }

    /// 中文宋体小字里夹 Cormorant 数字：mix(["走路 ", "31", " 分钟"])，奇数位是数字
    private func mix(_ parts: [String], _ ink: SanctusCardInk, size: CGFloat = 10.5) -> Text {
        parts.enumerated().reduce(Text("")) { t, p in
            p.offset % 2 == 1
                ? t + Text(p.element).font(SanctusPageFont.corm(size + 2.5)).foregroundColor(ink.body)
                : t + Text(p.element).font(.system(size: size, design: .serif)).foregroundColor(ink.sub)
        }
    }

    private func foot(_ note: String, _ link: String, _ ink: SanctusCardInk, action: (() -> Void)? = nil) -> some View {
        VStack(spacing: 8) {
            SanctusHair(ink: ink)
            HStack {
                Text(note).font(SanctusCardFont.ital(9.5)).foregroundColor(ink.sub)
                Spacer(minLength: 0)
                if !link.isEmpty {
                    Text(link).font(.system(size: 9, design: .serif)).tracking(1.6).foregroundColor(ink.link)
                        .contentShape(Rectangle())
                        .onTapGesture { action?() }
                }
            }
        }
        .padding(.top, 10)
    }

    private func art(_ name: String, _ ink: SanctusCardInk, width: CGFloat, dayOpacity: Double, nightOpacity: Double) -> some View {
        Image(name).renderingMode(.template).resizable().scaledToFit()
            .foregroundColor(ink.dark ? HP.rgb(0xECEEF2) : HP.rgb(0x5C606C))
            .frame(width: width)
            .opacity(ink.dark ? nightOpacity : dayOpacity)
            .allowsHitTesting(false)
    }

    // MARK: 平时（收着）

    private func todaySmall(_ ink: SanctusCardInk) -> some View {
        HPShell(ink: ink) {
            VStack(alignment: .leading, spacing: 0) {
                head(.today, ink, opened: false)
                big(m.steps.map(HP.grouped) ?? "—", "steps", ink, size: 38)
                VStack(alignment: .leading, spacing: 4) {
                    mix(["", m.distanceKm.map { String(format: "%.1f", $0) } ?? "—", " 公里 · 爬 ", m.floors.map { String($0) } ?? "—", " 层"], ink)
                    mix(["活动 ", m.activeKcal.map(HP.int) ?? "—", " 千卡 · 锻炼 ", m.exerciseMin.map(HP.int) ?? "—", " 分"], ink)
                }
                .padding(.top, 8)
                .frame(maxWidth: 210, alignment: .leading)
                foot("counted by your phone", "", ink)
            }
        } art: {
            art("HealthButterfly", ink, width: 140, dayOpacity: 0.85, nightOpacity: 0.9)
                .offset(x: 6, y: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle(.today) }
    }

    private func sleepSmall(_ ink: SanctusCardInk) -> some View {
        HPShell(ink: ink) {
            VStack(alignment: .leading, spacing: 0) {
                head(.sleep, ink, opened: false)
                if let n = m.night {
                    big(HP.hm(n.shown), "", ink, size: 27)
                    mix(["", HP.clock(n.start), " — ", HP.clock(n.end), ""], ink).padding(.top, 6)
                    HPSleepBar(night: n, ink: ink, height: 8).padding(.top, 12)
                } else {
                    big("—", "", ink, size: 27)
                    Text("还没有睡眠记录").font(.system(size: 10.5, design: .serif)).foregroundColor(ink.sub).padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 128, alignment: .top)
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle(.sleep) }
    }

    private func heartSmall(_ ink: SanctusCardInk) -> some View {
        HPShell(ink: ink) {
            VStack(alignment: .leading, spacing: 0) {
                head(.heart, ink, opened: false)
                big(m.hrLatest.map(HP.int) ?? "—", "bpm", ink, size: 27)
                if m.hrLatest != nil {
                    mix(["静息 ", m.resting.map(HP.int) ?? "—", " · 血氧 ", m.spo2.map(HP.int) ?? "—", "%"], ink).padding(.top, 6)
                    HPCurve(points: m.hrCurve, ink: ink).frame(height: 22).padding(.top, 8)
                } else {
                    Text("戴上手表以后就有").font(.system(size: 10.5, design: .serif)).foregroundColor(ink.sub).padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 128, alignment: .top)
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle(.heart) }
    }

    private func cycleSmall(_ ink: SanctusCardInk) -> some View {
        HPShell(ink: ink) {
            VStack(alignment: .leading, spacing: 0) {
                head(.cycle, ink, opened: false)
                if let c = m.cycle {
                    let day = HP.dayOfCycle(c)
                    let len = c.avgLen ?? 28
                    if day <= len + 10 {
                        big("\(day)", "day of \(len)", ink, size: 27)
                        HPCycleDots(day: day, length: len, runDays: c.runDays, ink: ink).padding(.top, 14)
                    } else {
                        // 1019 她截图：健康里最后记的那次是 71 天前，「第 71 天 / 28」没意义，71 个点还把整页撑出屏幕。
                        // 隔得比一个周期还久很多，就只说离上次多少天、上次哪天开始
                        big("\(day)", "days since", ink, size: 27)
                        mix(["上次 ", HP.md(c.lastStart), " 开始"], ink).padding(.top, 6)
                    }
                } else {
                    big("—", "", ink, size: 27)
                    Text("健康里还没记过").font(.system(size: 10.5, design: .serif)).foregroundColor(ink.sub).padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 112, alignment: .top)
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle(.cycle) }
    }

    private func bodySmall(_ ink: SanctusCardInk) -> some View {
        HPShell(ink: ink) {
            VStack(alignment: .leading, spacing: 0) {
                head(.body, ink, opened: false)
                VStack(alignment: .leading, spacing: 7) {
                    // 1024：运动挪去「运动」卡了，这里只留身体本身的
                    mix(["体重 ", m.weight.map { String(format: "%.1f", $0) } ?? "—", " 公斤"], ink)
                    mix(["水 ", m.water.map(HP.int) ?? "—", " · 正念 ", m.mindful.map(HP.int) ?? "—", " 分"], ink)
                }
                .padding(.top, 12)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 112, alignment: .top)
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle(.body) }
    }

    private func workoutSmall(_ ink: SanctusCardInk) -> some View {
        HPShell(ink: ink) {
            VStack(alignment: .leading, spacing: 0) {
                head(.workout, ink, opened: false)
                if m.workouts.isEmpty {
                    big("—", "minutes today", ink, size: 27)
                    Text("今天还没运动").font(.system(size: 10.5, design: .serif)).foregroundColor(ink.sub).padding(.top, 6)
                } else {
                    big(HP.int(m.workouts.reduce(0.0) { $0 + $1.minutes }), "minutes today", ink, size: 27)
                    mix(workoutCountLine, ink).padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 96, alignment: .top)
        } art: {
            art("HealthWing", ink, width: 96, dayOpacity: 0.55, nightOpacity: 0.6)
                .offset(x: -40, y: 4)
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle(.workout) }
    }

    /// 「2 次 · 消耗 286 千卡」（mix 用：奇数位是数字）
    private var workoutCountLine: [String] {
        let kcal = m.workouts.compactMap { $0.kcal }
        // 奇数位是数字：拼的时候字和数字要一格一格交替，不然字会套成数字的字体
        if kcal.isEmpty { return ["", "\(m.workouts.count)", " 次"] }
        return ["", "\(m.workouts.count)", " 次 · 消耗 ", HP.int(kcal.reduce(0, +)), " 千卡"]
    }

    // MARK: 展开

    @ViewBuilder private func expanded(_ c: HPCard, _ ink: SanctusCardInk) -> some View {
        switch c {
        case .today: todayOpen(ink)
        case .sleep: sleepOpen(ink)
        case .heart: heartOpen(ink)
        case .cycle: cycleOpen(ink)
        case .body: bodyOpen(ink)
        case .workout: workoutOpen(ink)
        }
    }

    private func todayOpen(_ ink: SanctusCardInk) -> some View {
        HPShell(ink: ink) {
            VStack(alignment: .leading, spacing: 0) {
                head(.today, ink, opened: true)
                big(m.steps.map(HP.grouped) ?? "—", "steps", ink, size: 40)
                mix(["走了 ", m.distanceKm.map { String(format: "%.1f", $0) } ?? "—", " 公里 · 爬了 ", m.floors.map { String($0) } ?? "—", " 层"], ink)
                    .padding(.top, 8)
                    .frame(maxWidth: 210, alignment: .leading)
                SanctusHair(ink: ink).padding(.top, 16)
                (Text("BY THE HOUR · ").font(SanctusCardFont.kicker()) + Text("每小时").font(.system(size: 7.5, design: .serif)))
                    .tracking(2.25).foregroundColor(ink.kicker).padding(.top, 14)
                HPHourBars(values: m.hourly, ink: ink).frame(height: 90).padding(.top, 12)
                HPFacts(ink: ink, rows: [
                    ("活动消耗", ["", m.activeKcal.map(HP.int) ?? "—", " 千卡"]),
                    ("锻炼", ["", m.exerciseMin.map(HP.int) ?? "—", " 分钟"]),
                ]).padding(.top, 12)
                foot("counted by your phone", "收起 －", ink) { toggle(nil) }
            }
        } art: {
            art("HealthButterfly", ink, width: 140, dayOpacity: 0.85, nightOpacity: 0.9)
                .offset(x: 6, y: 2)
        }
    }

    private func sleepOpen(_ ink: SanctusCardInk) -> some View {
        HPShell(ink: ink) {
            VStack(alignment: .leading, spacing: 0) {
                head(.sleep, ink, opened: true)
                if let n = m.night {
                    big(HP.hm(n.shown), n.asleep > 0 ? "asleep" : "in bed", ink, size: 40)
                    mix(["", HP.clock(n.start), " 睡 · ", HP.clock(n.end), " 醒"], ink).padding(.top, 6)
                    HPSleepBar(night: n, ink: ink, height: 10).padding(.top, 16)
                    HStack {
                        ForEach(0..<4, id: \.self) { i in
                            if i > 0 { Spacer(minLength: 0) }
                            Text(HP.clock(n.start.addingTimeInterval(n.end.timeIntervalSince(n.start) * Double(i) / 3)))
                                .font(SanctusPageFont.corm(9.5)).foregroundColor(ink.sub)
                        }
                    }
                    .padding(.top, 6)
                    HPSleepLegend(night: n, ink: ink).padding(.top, 10)
                } else {
                    Text("还没有睡眠记录。戴着小米手表睡一晚，这里就有几点睡、几点醒，深睡、浅睡、快速眼动各多久。")
                        .font(.system(size: 11.5, design: .serif)).foregroundColor(ink.sub).lineSpacing(4).padding(.top, 12)
                }
                SanctusHair(ink: ink).padding(.top, 14)
                (Text("LAST SEVEN NIGHTS · ").font(SanctusCardFont.kicker()) + Text("前七晚").font(.system(size: 7.5, design: .serif)))
                    .tracking(2.25).foregroundColor(ink.kicker).padding(.top, 14)
                HPWeekBars(bars: m.week, ink: ink).frame(height: 130).padding(.top, 10)
                if let s = HP.weekSummary(m.week) {
                    mix(s, ink).padding(.top, 12)
                }
                foot("kept by the night", "收起 －", ink) { toggle(nil) }
            }
        } art: {
            art("HealthMadonna", ink, width: 118, dayOpacity: 0.38, nightOpacity: 0.55)
                .offset(x: -18, y: 6)
        }
    }

    private func heartOpen(_ ink: SanctusCardInk) -> some View {
        HPShell(ink: ink) {
            VStack(alignment: .leading, spacing: 0) {
                head(.heart, ink, opened: true)
                if let hr = m.hrLatest {
                    big(HP.int(hr), "bpm · \(m.hrLatestAt.map(HP.clock) ?? "")", ink, size: 40)
                    mix(["今天 ", m.hrMin.map(HP.int) ?? "—", " — ", m.hrMax.map(HP.int) ?? "—", " · 平均 ", m.hrAvg.map(HP.int) ?? "—", ""], ink)
                        .padding(.top, 6)
                    HPCurve(points: m.hrCurve, ink: ink).frame(height: 70).padding(.top, 14)
                } else {
                    big("—", "bpm", ink, size: 40)
                    Text("今天手表的数据还没拉到。小米运动健康跟手表同步过以后，十五分钟内这里就有。")
                        .font(.system(size: 11.5, design: .serif)).foregroundColor(ink.sub).lineSpacing(4).padding(.top, 10)
                }
                HPFacts(ink: ink, rows: [
                    ("静息心率", ["", m.resting.map(HP.int) ?? "—", ""]),
                ]).padding(.top, 12)
                // 1107：小米有、苹果那时没有的两样——血氧一天的线、压力
                SanctusHair(ink: ink).padding(.top, 14)
                (Text("BLOOD OXYGEN · ").font(SanctusCardFont.kicker()) + Text("血氧").font(.system(size: 7.5, design: .serif)))
                    .tracking(2.25).foregroundColor(ink.kicker).padding(.top, 14)
                big(m.spo2.map(HP.int) ?? "—", "%" + (m.spo2At.map { " · " + HP.clock($0) } ?? ""), ink, size: 30)
                mix(["今天 ", m.spo2Min.map(HP.int) ?? "—", " — ", m.spo2Max.map(HP.int) ?? "—", "%"], ink).padding(.top, 6)
                if m.spo2Curve.count >= 2 {
                    HPCurve(points: m.spo2Curve, ink: ink, dot: false).frame(height: 44).padding(.top, 10)
                }
                SanctusHair(ink: ink).padding(.top, 14)
                (Text("STRESS · ").font(SanctusCardFont.kicker()) + Text("压力").font(.system(size: 7.5, design: .serif)))
                    .tracking(2.25).foregroundColor(ink.kicker).padding(.top, 14)
                big(m.stressAvg.map(HP.int) ?? "—", "today · of 100", ink, size: 30)
                mix(["最低 ", m.stressMin.map(HP.int) ?? "—", " · 最高 ", m.stressMax.map(HP.int) ?? "—", " · 越高越紧绷"], ink).padding(.top, 6)
                if !m.stressBands.isEmpty {
                    HPFacts(ink: ink, rows: m.stressBands.map { ($0.name, ["", HP.int($0.minutes), " 分钟"]) }).padding(.top, 8)
                }
                foot("from your mi watch", "收起 －", ink) { toggle(nil) }
            }
        }
    }

    private func cycleOpen(_ ink: SanctusCardInk) -> some View {
        HPShell(ink: ink) {
            VStack(alignment: .leading, spacing: 0) {
                head(.cycle, ink, opened: true)
                if let c = m.cycle {
                    let day = HP.dayOfCycle(c)
                    let len = c.avgLen ?? 28
                    big("\(day)", day <= len + 10 ? "day of \(len)" : "days since", ink, size: 40)
                    mix(["上次 ", HP.md(c.lastStart), " 开始"], ink).padding(.top, 6)
                    SanctusHair(ink: ink).padding(.top, 22)
                    (Text("\(HP.monthEN()) · ").font(SanctusCardFont.kicker()) + Text(HP.monthCN()).font(.system(size: 7.5, design: .serif)))
                        .tracking(2.25).foregroundColor(ink.kicker).padding(.top, 12)
                    HPMonth(cycle: c, ink: ink).padding(.top, 10)
                    HPFacts(ink: ink, rows: [
                        ("这一次", ["", "\(c.runDays)", " 天" + (c.flow.map { " · 流量\($0)" } ?? "")]),
                        ("平均周期", c.avgLen.map { ["", "\($0)", " 天（最近几次）"] } ?? ["", "—", " 记满两次才算得出"]),
                        ("下次大约", ["", c.next.map(HP.md) ?? "—", ""]),
                    ]).padding(.top, 8)
                } else {
                    Text("健康里还没记过经期。在健康 App 的「周期跟踪」里记，这里就会有月历和下次大约哪天。")
                        .font(.system(size: 11.5, design: .serif)).foregroundColor(ink.sub).lineSpacing(4).padding(.top, 12)
                        .frame(maxWidth: 220, alignment: .leading)
                }
                foot("kept in apple health", "去健康里记 ›", ink) {
                    if let url = URL(string: "x-apple-health://") { UIApplication.shared.open(url) }
                }
            }
        } art: {
            art("HealthShell", ink, width: 92, dayOpacity: 0.85, nightOpacity: 0.8)
                .offset(x: -24, y: 10)
        }
    }

    private func bodyOpen(_ ink: SanctusCardInk) -> some View {
        HPShell(ink: ink) {
            VStack(alignment: .leading, spacing: 0) {
                head(.body, ink, opened: true)
                HPFacts(ink: ink, rows: [
                    ("体重", ["", m.weight.map { String(format: "%.1f", $0) } ?? "—", " 公斤"]),
                    ("喝水", ["", m.water.map(HP.int) ?? "—", " 毫升"]),
                    ("正念", ["", m.mindful.map(HP.int) ?? "—", " 分钟"]),
                ]).padding(.top, 12)
                foot("kept in apple health", "收起 －", ink) { toggle(nil) }
            }
        }
    }
    private func workoutOpen(_ ink: SanctusCardInk) -> some View {
        let picked = pickedWorkout ?? m.workouts.last?.id   // 没点过就看最近那一次
        return HPShell(ink: ink) {
            VStack(alignment: .leading, spacing: 0) {
                head(.workout, ink, opened: true)
                if m.workouts.isEmpty {
                    big("—", "minutes today", ink, size: 40)
                    Text("今天还没运动。在小米手表上开始一次运动，练完这里就有这次的时长、消耗和心率。")
                        .font(.system(size: 11.5, design: .serif)).foregroundColor(ink.sub).lineSpacing(4).padding(.top, 10)
                        .frame(maxWidth: 230, alignment: .leading)
                } else {
                    big(HP.int(m.workouts.reduce(0.0) { $0 + $1.minutes }), "minutes today", ink, size: 40)
                    mix(workoutCountLine, ink).padding(.top, 6)
                    VStack(spacing: 0) {
                        ForEach(m.workouts) { w in
                            workoutRow(w, on: w.id == picked, ink)
                            if w.id == picked { workoutHeart(w, ink) }
                        }
                    }
                    .padding(.top, 12)
                }
                SanctusHair(ink: ink).padding(.top, 14)
                (Text("THIS WEEK · ").font(SanctusCardFont.kicker()) + Text("这一周").font(.system(size: 7.5, design: .serif)))
                    .tracking(2.25).foregroundColor(ink.kicker).padding(.top, 14)
                HPMinuteBars(bars: m.workoutWeek, ink: ink).frame(height: 112).padding(.top, 10)
                if let s = weekLine { mix(s, ink).padding(.top, 12) }
                foot("kept by the body", "收起 －", ink) { toggle(nil) }
            }
        } art: {
            art("HealthWing", ink, width: 118, dayOpacity: 0.55, nightOpacity: 0.6)
                .offset(x: -44, y: 6)
        }
    }

    /// 一次运动一行：左边名字＋几点，右边「28 分 · 210 千卡 · 心率 142/168」；点一下在下面看这次的心率
    private func workoutRow(_ w: HPWorkout, on: Bool, _ ink: SanctusCardInk) -> some View {
        // 字和数字一格一格交替（偶数位字、奇数位数字），最后补上收尾的字
        var right = ["", HP.int(w.minutes)]
        var tail = " 分"
        if let k = w.kcal { right += [tail + " · ", HP.int(k)]; tail = " 千卡" }
        if let a = w.hrAvg, let x = w.hrMax { right += [tail + " · 心率 ", HP.int(a), "/", HP.int(x)]; tail = "" }
        right.append(tail)
        return HStack(alignment: .firstTextBaseline) {
            (Text(w.name).font(.system(size: 11.5, design: .serif)).foregroundColor(on ? (ink.dark ? HP.rgb(0xE4E4E7) : HP.rgb(0x2A2A2E)) : ink.body)
                + Text("  " + HP.clock(w.start)).font(SanctusPageFont.corm(13)).foregroundColor(ink.sub))
            Spacer(minLength: 8)
            right.enumerated().reduce(Text("")) { t, p in
                p.offset % 2 == 0
                    ? t + Text(p.element).font(.system(size: 10.5, design: .serif)).foregroundColor(ink.sub)
                    : t + Text(p.element).font(SanctusPageFont.corm(13.5)).foregroundColor(ink.dark ? HP.rgb(0xE4E4E7) : HP.rgb(0x2A2A2E))
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(ink.frame).frame(height: 0.6) }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { pickedWorkout = w.id } }
    }

    @ViewBuilder private func workoutHeart(_ w: HPWorkout, _ ink: SanctusCardInk) -> some View {
        if w.curve.count >= 2, let avg = w.hrAvg, let top = w.hrMax {
            VStack(spacing: 6) {
                HPWorkoutCurve(points: w.curve, avg: avg, ink: ink).frame(height: 74)
                HStack(alignment: .firstTextBaseline) {
                    Text(HP.clock(w.start)).font(SanctusPageFont.corm(12.5)).foregroundColor(ink.body)
                    Spacer(minLength: 4)
                    mix(["平均 ", HP.int(avg), "（虚线）· 最高 ", HP.int(top), w.hrMaxAt.map { " 在 " + HP.clock($0) } ?? ""], ink, size: 10)
                    Spacer(minLength: 4)
                    Text(HP.clock(w.end)).font(SanctusPageFont.corm(12.5)).foregroundColor(ink.body)
                }
            }
            .padding(.top, 12).padding(.bottom, 6)
        } else {
            Text("这次的心率线画不出来（手表平时十分钟才记一次心率，运动太短就没几个点）")
                .font(.system(size: 10.5, design: .serif)).foregroundColor(ink.sub)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
        }
    }

    /// 这一周底下那行：动了几天、一共多少分、最长一次哪天（mix 用：奇数位是数字）
    private var weekLine: [String]? {
        let days = m.workoutWeek.filter { $0.minutes > 0 }
        guard !days.isEmpty else { return nil }
        let head = ["这周动了 ", "\(days.count)", " 天 · 共 ", HP.int(days.reduce(0.0) { $0 + $1.minutes })]
        guard let l = m.weekLongest else { return head + [" 分"] }
        return head + [" 分 · 最长一次 ", HP.int(l.minutes), " 分（周\(l.label)）"]
    }
}

// MARK: - 零件

enum HP {
    static func rgb(_ hex: Int, _ a: Double = 1) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: a)
    }
    private static let clockF: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()
    static func clock(_ d: Date) -> String { clockF.string(from: d) }
    static func md(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.month, .day], from: d)
        return String(format: "%d · %02d", c.month ?? 0, c.day ?? 0)
    }
    static func hm(_ t: TimeInterval) -> String {
        let m = Int((t / 60).rounded())
        return String(format: "%d:%02d", m / 60, m % 60)
    }
    static func int(_ v: Double) -> String { String(Int(v.rounded())) }
    static func grouped(_ v: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }
    static func dayOfCycle(_ c: HPCycle) -> Int {
        let cal = Calendar.current
        return (cal.dateComponents([.day], from: c.lastStart, to: cal.startOfDay(for: Date())).day ?? 0) + 1
    }
    static func monthEN() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM"
        return f.string(from: Date()).uppercased()
    }
    static func monthCN() -> String {
        let names = ["一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月"]
        return names[Calendar.current.component(.month, from: Date()) - 1]
    }
    /// 前七晚底下那行：平均、最晚睡、最早起（mix 用：奇数位是数字）
    static func weekSummary(_ bars: [HPNightBar]) -> [String]? {
        let slept = bars.filter { $0.hours > 0 }
        guard !slept.isEmpty else { return nil }
        let avg = slept.reduce(0.0) { $0 + $1.hours } / Double(slept.count)
        let cal = Calendar.current
        // 睡觉时间从傍晚 6 点起算，过了半夜的往后排
        func late(_ d: Date) -> Int { (cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d) + 6 * 60) % (24 * 60) }
        var out = ["平均 ", hm(avg), ""]
        if let b = slept.filter({ $0.start != nil }).max(by: { late($0.start!) < late($1.start!) }), let s = b.start {
            out += [" · 最晚睡 ", clock(s), "（周\(b.label)）"]
        }
        if let e = slept.compactMap({ $0.end }).min(by: { (cal.component(.hour, from: $0) * 60 + cal.component(.minute, from: $0)) < (cal.component(.hour, from: $1) * 60 + cal.component(.minute, from: $1)) }) {
            out += [" · 最早起 ", clock(e), ""]
        }
        return out
    }
}

/// 页面里的卡壳：跟聊天小卡同一套（磨砂底、外白边、往里 5 一圈细框），铺满宽
struct HPShell<Content: View, Art: View>: View {
    let ink: SanctusCardInk
    @ViewBuilder var content: () -> Content
    @ViewBuilder var art: () -> Art
    var body: some View {
        content()
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 11)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(alignment: .topTrailing) { art() }
            .background(LinearGradient(colors: [ink.fillTop, ink.fillBottom], startPoint: .top, endPoint: .bottom))
            .clipShape(RoundedRectangle(cornerRadius: 12.5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8.5, style: .continuous).stroke(ink.frame, lineWidth: 0.6).padding(5))
            .overlay(RoundedRectangle(cornerRadius: 12.5, style: .continuous).stroke(ink.edge, lineWidth: 0.8))
    }
}

extension HPShell where Art == EmptyView {
    init(ink: SanctusCardInk, @ViewBuilder content: @escaping () -> Content) {
        self.ink = ink
        self.content = content
        self.art = { EmptyView() }
    }
}

/// 睡眠分段条：越深睡得越沉；没分段时浅灰是在床上、中灰是睡着
struct HPSleepBar: View {
    let night: HPNight
    let ink: SanctusCardInk
    let height: CGFloat
    static func color(_ kind: Int, dark: Bool) -> Color {
        switch kind {
        case 4: return HP.rgb(0x6F7480)
        case 3, 1: return HP.rgb(0xA9ADB6)
        case 5, 0: return dark ? HP.rgb(0x5A5D66) : HP.rgb(0xD3D6DC)
        default: return dark ? Color.white.opacity(0.85) : .white   // 醒着
        }
    }
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                (ink.dark ? Color.white.opacity(0.06) : HP.rgb(0xE6E8EC))
                ForEach(Array(night.segs.enumerated()), id: \.offset) { _, s in
                    Rectangle().fill(HPSleepBar.color(s.kind, dark: ink.dark))
                        .frame(width: max(1, CGFloat(s.b - s.a) * g.size.width))
                        .offset(x: CGFloat(s.a) * g.size.width)
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(ink.frame, lineWidth: 0.6))
    }
}

struct HPSleepLegend: View {
    let night: HPNight
    let ink: SanctusCardInk
    var body: some View {
        let items: [(Int, String, TimeInterval)] = night.staged
            ? [(4, "深睡", night.deep), (3, "浅睡", night.core), (5, "快速眼动", night.rem), (2, "醒着", night.awake)]
            : [(0, "在床上", night.inBed), (1, "睡着", night.asleep)]
        HStack(spacing: 12) {
            ForEach(Array(items.filter { $0.2 > 0 }.enumerated()), id: \.offset) { _, it in
                HStack(spacing: 4) {
                    Circle().fill(HPSleepBar.color(it.0, dark: ink.dark)).frame(width: 7, height: 7)
                        .overlay(Circle().stroke(ink.frame, lineWidth: 0.6))
                    Text(it.1).font(.system(size: 10, design: .serif)).foregroundColor(ink.body)
                    Text(HP.hm(it.2)).font(SanctusPageFont.corm(12)).foregroundColor(ink.body)
                }
            }
        }
    }
}

/// 前七晚：每晚一根，最后一根（昨晚）深一点
struct HPWeekBars: View {
    let bars: [HPNightBar]
    let ink: SanctusCardInk
    var body: some View {
        let top = max(bars.map { $0.hours }.max() ?? 0, 6 * 3600)
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(bars) { b in
                VStack(spacing: 4) {
                    Text(b.hours > 0 ? HP.hm(b.hours) : "—").font(SanctusPageFont.corm(11)).foregroundColor(ink.body)
                    Capsule()
                        .fill(LinearGradient(colors: b.isLast ? [HP.rgb(0x6F7480), HP.rgb(0x3E4048)] : [HP.rgb(0xA9ADB6), HP.rgb(0x6F7480)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 12, height: max(4, 94 * CGFloat(b.hours / top)))
                        .opacity(b.hours > 0 ? 1 : 0.3)
                    Text(b.label).font(.system(size: 10, design: .serif)).foregroundColor(ink.sub)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

/// 今天每小时的步数：24 根细柱
struct HPHourBars: View {
    let values: [Double]
    let ink: SanctusCardInk
    var body: some View {
        let top = max(values.max() ?? 0, 1)
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<values.count, id: \.self) { i in
                    Capsule().fill(HP.rgb(0xA9ADB6))
                        .frame(width: 4, height: max(2, 70 * CGFloat(values[i] / top)))
                        .opacity(values[i] > 0 ? 1 : 0.35)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            HStack {
                ForEach(["0", "6", "12", "18", "24"], id: \.self) { t in
                    if t != "0" { Spacer(minLength: 0) }
                    Text(t).font(SanctusPageFont.corm(9.5)).foregroundColor(ink.sub)
                }
            }
        }
    }
}

/// 今天的心率线：灰线，最新那一点是整页唯一的电光蓝
struct HPCurve: View {
    let points: [CGPoint]
    let ink: SanctusCardInk
    var dot = true   // 末尾那颗电光蓝；一页只许一处，心率线用了，血氧线就不点
    var body: some View {
        GeometryReader { g in
            let ys = points.map { $0.y }
            let lo = (ys.min() ?? 0) - 3
            let hi = (ys.max() ?? 1) + 3
            let pos: (CGPoint) -> CGPoint = { p in
                CGPoint(x: p.x * g.size.width, y: g.size.height * (1 - (p.y - lo) / max(1, hi - lo)))
            }
            if points.count >= 2 {
                Path { path in
                    path.move(to: pos(points[0]))
                    for p in points.dropFirst() { path.addLine(to: pos(p)) }
                }
                .stroke(HP.rgb(0x6F7480, 0.75), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
            }
            if dot, let last = points.last {
                Circle().fill(ink.dark ? HP.rgb(0x3A55FF) : HP.rgb(0x0B1BFF))
                    .frame(width: 5, height: 5)
                    .position(pos(last))
            }
        }
    }
}

/// 收着的经期卡：一个周期一排小点，来的那几天涂灰，今天画圈
struct HPCycleDots: View {
    let day: Int
    let length: Int
    let runDays: Int
    let ink: SanctusCardInk
    // 1019：原来一个点一个 View、各自占最小宽度，点一多（她那次 71 个）整行比卡还宽，把整页撑出屏幕。
    // 改成按给的宽度画，点再多也只铺满这一行
    var body: some View {
        Canvas { ctx, size in
            let n = max(1, length)
            let step = size.width / CGFloat(n)
            let r: CGFloat = min(2, step * 0.36)
            let y = size.height / 2
            for d in 1...n {
                let x = step * (CGFloat(d) - 0.5)
                if d == day {
                    let rr = r + 1.2
                    ctx.stroke(Path(ellipseIn: CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2)),
                               with: .color(ink.dark ? HP.rgb(0xE3E4E8) : HP.rgb(0x2A2A2E)), lineWidth: 1)
                } else if d <= runDays {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(HP.rgb(0x6F7480)))
                } else {
                    ctx.stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(ink.hair), lineWidth: 0.6)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 8)
    }
}

/// 这个月的月历：来的那几天涂灰、今天画圈、下次大约那几天虚线圈
struct HPMonth: View {
    let cycle: HPCycle
    let ink: SanctusCardInk
    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let first = cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let lead = (cal.component(.weekday, from: first) + 5) % 7   // 周一打头
        let predicted: Set<Date> = {
            guard let n = cycle.next else { return [] }
            return Set((0..<max(1, cycle.runDays)).compactMap { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: n)) })
        }()
        let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        LazyVGrid(columns: cols, spacing: 6) {
            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { w in
                Text(w).font(.system(size: 9, design: .serif)).foregroundColor(ink.sub)
            }
            ForEach(0..<(lead + count), id: \.self) { i in
                if i < lead {
                    Color.clear.frame(height: 26)
                } else {
                    let d = cal.date(byAdding: .day, value: i - lead, to: first) ?? first
                    let flow = cycle.flowDays.contains(d)
                    Text("\(i - lead + 1)").font(SanctusPageFont.corm(13))
                        .foregroundColor(flow ? .white : ink.body)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(flow ? HP.rgb(0x6F7480) : .clear))
                        .overlay(Circle().stroke(ink.dark ? HP.rgb(0xE3E4E8) : HP.rgb(0x2A2A2E), lineWidth: 1.1).opacity(d == today ? 1 : 0))
                        .overlay(Circle().stroke(ink.hair, style: StrokeStyle(lineWidth: 0.8, dash: [2, 2])).opacity(predicted.contains(d) && !flow ? 1 : 0))
                }
            }
        }
    }
}

/// 一行一项：左边宋体名字，右边文字夹数字（values 奇数位是数字，第一位是数字前面的字，没有就写 ""）
struct HPFacts: View {
    let ink: SanctusCardInk
    let rows: [(String, [String])]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack {
                    Text(r.0).font(.system(size: 11, design: .serif)).foregroundColor(ink.sub)
                    Spacer(minLength: 8)
                    r.1.enumerated().reduce(Text("")) { t, p in
                        p.offset % 2 == 0
                            ? t + Text(p.element).font(.system(size: 11.5, design: .serif)).foregroundColor(ink.body)
                            : t + Text(p.element).font(SanctusPageFont.corm(14)).foregroundColor(ink.dark ? HP.rgb(0xE4E4E7) : HP.rgb(0x2A2A2E))
                    }
                }
                .padding(.vertical, 7)
                .overlay(alignment: .bottom) { Rectangle().fill(ink.frame).frame(height: 0.6) }
            }
        }
    }
}

/// 这一周每天动了几分钟：一天一根，今天那根深一点；没动的那天只画一道短横
struct HPMinuteBars: View {
    let bars: [HPMinuteBar]
    let ink: SanctusCardInk
    var body: some View {
        let top = max(bars.map { $0.minutes }.max() ?? 0, 30)
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(bars) { b in
                VStack(spacing: 4) {
                    Text(b.minutes > 0 ? HP.int(b.minutes) : " ").font(SanctusPageFont.corm(11)).foregroundColor(ink.body)
                    if b.minutes > 0 {
                        Capsule()
                            .fill(LinearGradient(colors: b.isLast ? [HP.rgb(0x6F7480), HP.rgb(0x3E4048)] : [HP.rgb(0xC6C9D0), HP.rgb(0x8A8F9A)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 12, height: max(6, 74 * CGFloat(b.minutes / top)))
                    } else {
                        Capsule().fill(ink.frame).frame(width: 12, height: 3)
                    }
                    Text(b.label).font(.system(size: 10, design: .serif)).foregroundColor(ink.sub)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

/// 一次运动的心率线：灰线、平均是一道虚线，最高那一刻是电光蓝的点
struct HPWorkoutCurve: View {
    let points: [CGPoint]
    let avg: Double
    let ink: SanctusCardInk
    var body: some View {
        GeometryReader { g in
            let ys = points.map { $0.y }
            let lo = (ys.min() ?? 0) - 4
            let hi = (ys.max() ?? 1) + 4
            let pos: (CGPoint) -> CGPoint = { p in
                CGPoint(x: p.x * g.size.width, y: g.size.height * (1 - (p.y - lo) / max(1, hi - lo)))
            }
            let ay = g.size.height * (1 - (avg - lo) / max(1, hi - lo))
            Path { p in
                p.move(to: CGPoint(x: 0, y: ay))
                p.addLine(to: CGPoint(x: g.size.width, y: ay))
            }
            .stroke(ink.hair, style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            Path { path in
                path.move(to: pos(points[0]))
                for p in points.dropFirst() { path.addLine(to: pos(p)) }
            }
            .stroke(HP.rgb(0x6F7480, 0.85), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            if let top = points.max(by: { $0.y < $1.y }) {
                Circle().fill(ink.dark ? HP.rgb(0x3A55FF) : HP.rgb(0x0B1BFF))
                    .frame(width: 5.5, height: 5.5)
                    .position(pos(top))
            }
        }
    }
}
