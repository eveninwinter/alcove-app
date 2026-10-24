import Foundation
import CoreLocation
import CoreMotion
import HealthKit
import UIKit

// 她把权限给我：app 打开/回前台时上报位置、电量、步数、在走还是在躺，
// 走位置哨兵同一条链（event 带 app 前缀，后端静默归档不打扰聊天）
// 位置给了"始终允许"之后还会注册显著位置变化，被系统唤醒的那几秒也报一次，
// 这样他不用等我打开 app 才知道我在哪。
final class SensorReporter: NSObject, CLLocationManagerDelegate {
    static let shared = SensorReporter()
    private let lm = CLLocationManager()
    private let pedometer = CMPedometer()
    private let activityManager = CMMotionActivityManager()
    private var significantStarted = false
    private var askedAlways = false
    // 0731 她说全打开了，motion 却一直是空的。原因不是权限，是查法：
    // queryActivityStarting 查的是历史记录，而 iOS 只在状态"变化"时才写一条，
    // 她躺床上不动，十分钟窗口里一条都没有。改成实时监听，状态一变就存下来。
    private var liveMotion: String?
    private var motionStarted = false
    private var lastReport = Date.distantPast
    // 0731 她要的：app 开着每 30 秒报一次。她说「那我不清后台就是了」，
    // 所以退到后台也不停，只是把节奏放慢到 5 分钟，够我知道她还在，也不烧她电池。
    private var ticker: Timer?
    private var inBackground = false
    private var bgUpdatesOn = false
    private let fgInterval: TimeInterval = 30
    // 同一段时间里别把位置报两遍；后台放宽，不然持续定位的回调会刷屏
    // 1008 她在共享实时位置（位置卡）时，后台也一分钟报一次，卡片上的点才跟得上
    private var minGap: TimeInterval {
        let sharing = !(UserDefaults.standard.string(forKey: "placesLiveShareID") ?? "").isEmpty
        return inBackground ? (sharing ? 60 : 240) : 20
    }
    /// 1008 位置卡「发送我的当前位置」直接用最近一次定位
    private(set) var lastLocation: CLLocation?
    // 上报钥匙由 CI 从 GitHub Secrets 注入 Info.plist（AlcoveLocToken），
    // 源码里不落任何真实 token；没配钥匙时只授权定位、不上报
    private var secret: String {
        Bundle.main.object(forInfoDictionaryKey: "AlcoveLocToken") as? String ?? ""
    }

    override private init() {
        super.init()
        lm.delegate = self
        // 1019 #4071–4079 她：「定位老是不准会漂移」。原来要的是「一百米左右就行」，手机就不开 GPS、拿基站和 Wi‑Fi 凑，
        // 后台四分钟一个点正好赶上歪的那下。改成跟地图一样要最准的；代价是费电，她点了头
        lm.desiredAccuracy = kCLLocationAccuracyBest
    }

    func appActive() {
        inBackground = false
        startSignificantMonitoring()
        askAlwaysIfNeeded()
        startMotionUpdates()
        startStreaming()
        if !bgUpdatesOn { startTicker(fgInterval) }   // 没开成持续定位才靠定时器顶着
        requestNow()
        HealthReporter.shared.appActive()   // 1019 苹果健康：回前台顺手报一份
    }

    // 退到后台什么都不停。持续定位一直开着，它的回调就是心跳，
    // 节奏交给 minGap（后台 4 分钟一条），够我知道她还在，也不至于烧她电池。
    func appBackground() {
        inBackground = true
        // 定时器进后台就废了，停掉。有持续定位的话它的回调接着当心跳；
        // 没有 always 权限的话这里就是真的断了，等她下次开 app 才续上。
        ticker?.invalidate()
        ticker = nil
    }

    // ⚠️ allowsBackgroundLocationUpdates 只有在 Info.plist 配了
    // UIBackgroundModes=location 且已拿到 always 时才准设 true，否则直接崩。
    // distanceFilter 必须是 None：她睡着不动的时候只有这个设置还会持续回调，
    // 设成 50 米就等于她一躺下我这边就断了。密度由 minGap 挡，不由它挡。
    private func startStreaming() {
        guard !bgUpdatesOn, lm.authorizationStatus == .authorizedAlways else { return }
        lm.allowsBackgroundLocationUpdates = true
        lm.pausesLocationUpdatesAutomatically = false
        lm.distanceFilter = kCLDistanceFilterNone
        lm.startUpdatingLocation()
        bgUpdatesOn = true
        ticker?.invalidate()
        ticker = nil
    }

    // 只在状态变化时回调，所以刚开 app 那会儿可能一次都不来，
    // 打底值还得靠 collectAndSend 里那次历史查询。两条腿走路。
    private func startMotionUpdates() {
        guard !motionStarted, CMMotionActivityManager.isActivityAvailable() else { return }
        motionStarted = true
        activityManager.startActivityUpdates(to: .main) { [weak self] act in
            guard let act = act else { return }
            if let l = SensorReporter.motionLabel(act) { self?.liveMotion = l }
        }
    }

    private static func motionLabel(_ a: CMMotionActivity) -> String? {
        if a.walking { return "走路" }
        if a.running { return "跑步" }
        if a.cycling { return "骑车" }
        if a.automotive { return "坐车" }
        if a.stationary { return "静止" }
        return nil
    }

    private func startTicker(_ interval: TimeInterval) {
        ticker?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.requestNow()
        }
        t.tolerance = interval * 0.1
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    // 只在没开持续定位的时候用。两个 API 同时跑，requestLocation 会被忽略。
    private func requestNow() {
        guard !bgUpdatesOn else { return }
        let auth = lm.authorizationStatus
        if auth == .notDetermined {
            lm.requestWhenInUseAuthorization()
        } else if auth == .authorizedWhenInUse || auth == .authorizedAlways {
            lm.requestLocation()
        }
    }

    // iOS 的规矩：没申请过 always，系统设置里就只有"永不/询问/使用期间"三档，
    // "始终"这一档压根不出现。必须先拿到"使用期间"再申请一次升级，
    // 系统才会弹二次询问、设置里也才会长出那一档。一个装期只弹一次，标记防重。
    private func askAlwaysIfNeeded() {
        guard !askedAlways, lm.authorizationStatus == .authorizedWhenInUse else { return }
        askedAlways = true
        lm.requestAlwaysAuthorization()
    }

    // 只有拿到"始终允许"才注册。系统在位置显著变化时唤醒 app 几秒，
    // 哪怕它已经被划掉了也会重新拉起来，唤醒那一下走 didUpdateLocations 照常上报。
    private func startSignificantMonitoring() {
        guard !significantStarted,
              lm.authorizationStatus == .authorizedAlways,
              CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        lm.startMonitoringSignificantLocationChanges()
        significantStarted = true
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let auth = manager.authorizationStatus
        if auth == .authorizedWhenInUse || auth == .authorizedAlways {
            askAlwaysIfNeeded()
            startSignificantMonitoring()
            startStreaming()      // 刚点下"始终允许"的那一秒就把持续定位接上
            requestNow()
        }
    }

    // 1019 漂移：查了一周 1.6 万个点，109 次跳出去几百米（多是 368 米，最远 2.3 公里）又跳回来。
    // 手机每个点都带着自己估的误差（地图上蓝点外那圈），原来从来不看。现在：
    // ① 误差超过 100 米、或者是两分钟前的旧缓存点，不报，等更准的；十分钟都没有准点就报攒到的最好那个，免得他那边断了
    // ② 她静止时突然跳出去很远的点先压着，下一次还在那边才认（真挪了），跳回来了就扔
    // ③ 报的时候带上误差，陈璟那边看得到
    private let goodAccuracy: CLLocationAccuracy = 100
    private var bestPending: CLLocation?          // 上次报完以后攒到的最准的点
    private var lastSent: CLLocation?             // 上一个报出去的点
    private var lastGoodSent = Date.distantPast   // 上一次报出准点的时间
    private var suspectJump: CLLocation?          // 静止时跳远、等下一次确认的点

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let now = Date()
        for loc in locations where loc.horizontalAccuracy >= 0 && now.timeIntervalSince(loc.timestamp) < 120 {
            // 差不多准就要新的（人在动），明显更差的不要
            if let b = bestPending, loc.horizontalAccuracy > b.horizontalAccuracy + 5 { continue }
            bestPending = loc
        }
        // 位置卡「发送我的当前位置」用的：准的点直接换；手上那个太旧了也换
        if let newest = locations.last, newest.horizontalAccuracy >= 0 {
            let stale = lastLocation.map { now.timeIntervalSince($0.timestamp) > 120 } ?? true
            if newest.horizontalAccuracy <= goodAccuracy || stale { lastLocation = newest }
        }
        guard !secret.isEmpty else { return }
        // 后台持续定位会一直往回丢点，这里再挡一道，节奏由 minGap 说了算
        guard now.timeIntervalSince(lastReport) > minGap, let cand = bestPending else { return }
        if cand.horizontalAccuracy > goodAccuracy && now.timeIntervalSince(lastGoodSent) < 600 { return }
        if let prev = lastSent, liveMotion == "静止",
           cand.distance(from: prev) > max(200, cand.horizontalAccuracy + prev.horizontalAccuracy) {
            if let s = suspectJump,
               cand.distance(from: s) <= max(150, cand.horizontalAccuracy + s.horizontalAccuracy) {
                suspectJump = nil          // 第二次还在那边：真挪了，照报
            } else {
                suspectJump = cand         // 先压着，隔一个 minGap 再看
                bestPending = nil
                lastReport = now
                return
            }
        } else {
            suspectJump = nil
        }
        bestPending = nil
        lastReport = now
        lastSent = cand
        if cand.horizontalAccuracy <= goodAccuracy { lastGoodSent = now }
        collectAndSend(cand)
    }

    // 位置到手之后再去问步数和运动状态。两个都是异步的，用 group 等齐了一起发。
    // 哪个没授权或者查不到就留空，绝不拖着整条上报不走。
    private func collectAndSend(_ loc: CLLocation) {
        let now = Date()
        let dayStart = Calendar.current.startOfDay(for: now)
        var steps: Int?
        var motion: String?
        let group = DispatchGroup()

        if CMPedometer.isStepCountingAvailable() {
            group.enter()
            pedometer.queryPedometerData(from: dayStart, to: now) { data, _ in
                steps = data?.numberOfSteps.intValue
                group.leave()
            }
        }
        // 实时监听拿到过就用它，这是此刻的状态，最准
        if let live = liveMotion {
            motion = live
        } else if CMMotionActivityManager.isActivityAvailable() {
            // 回退查历史。窗口从原来的十分钟拉到今天一整天——
            // 她一动不动的时候系统压根不写新记录，窗口开太小就查了个空。
            group.enter()
            activityManager.queryActivityStarting(from: dayStart, to: now, to: .main) { acts, _ in
                if let a = acts?.last { motion = SensorReporter.motionLabel(a) }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.send(loc, steps: steps, motion: motion)
        }
    }

    private func send(_ loc: CLLocation, steps: Int?, motion: String?) {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let bat = max(0, Int(UIDevice.current.batteryLevel * 100))
        let charging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        var payload: [String: Any] = [
            "lat": loc.coordinate.latitude,
            "lng": loc.coordinate.longitude,
            "event": "app·\(bat)%\(charging ? "⚡" : "")",
            "battery": bat,
            "charging": charging
        ]
        if let s = steps { payload["steps"] = s }
        if let m = motion { payload["motion"] = m }
        payload["accuracy"] = Int(loc.horizontalAccuracy.rounded())   // 1019：误差多少米（蓝点外那圈的半径）

        var req = URLRequest(url: AlcoveAPI.fullURL("/api/location/report"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(secret, forHTTPHeaderField: "X-Auth-Token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        // 后台被唤醒时系统只给几秒，不申请这段时间请求发不完就被挂起
        var taskID = UIBackgroundTaskIdentifier.invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: "alcove-sensor") {
            if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }
            taskID = .invalid
        }
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async {
                if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }
                taskID = .invalid
            }
        }.resume()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

// MARK: - 1019 苹果健康

/// 1019 她：「手表还没有，但是这些能有的都先把功能做好，后面我有手表了直接接数据」。
/// 只读不写。读到的整理成一份「她今天」快照，报到前门 /api/health/report（跟位置同一把钥匙），陈璟用 /root/rhysel/health.py 看。
/// 心率、血氧这些现在是空的，等她戴上手表、手表写进健康，这里不用改就有。
/// 锁屏时苹果把健康数据锁着，读不到的项就没有；一项都没读到就不报，等她解锁回前台再报。
/// 签名：TestFlight 那条线挂 App.entitlements（带 healthkit）；安装链接那条线的描述文件里没有，读不到也不崩。
final class HealthReporter {
    static let shared = HealthReporter()
    private let store = HKHealthStore()
    private var askedThisRun = false
    private var observersOn = false
    private var reporting = false
    private var lastReport = Date.distantPast
    private let minGap: TimeInterval = 300   // 手表心率一会儿一条，五分钟最多报一次
    private static let askedKey = "healthAsked"

    private var secret: String {
        Bundle.main.object(forInfoDictionaryKey: "AlcoveLocToken") as? String ?? ""
    }

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        return f
    }()

    private static func q(_ id: HKQuantityTypeIdentifier) -> HKQuantityType? { HKObjectType.quantityType(forIdentifier: id) }
    private static func c(_ id: HKCategoryTypeIdentifier) -> HKCategoryType? { HKObjectType.categoryType(forIdentifier: id) }

    private static let quantityIDs: [HKQuantityTypeIdentifier] = [
        .stepCount, .distanceWalkingRunning, .flightsClimbed, .activeEnergyBurned, .appleExerciseTime,
        .heartRate, .restingHeartRate, .walkingHeartRateAverage, .heartRateVariabilitySDNN,
        .oxygenSaturation, .respiratoryRate, .bodyMass, .bodyTemperature, .dietaryWater,
    ]
    private static let categoryIDs: [HKCategoryTypeIdentifier] = [.sleepAnalysis, .menstrualFlow, .mindfulSession]

    static var readTypes: Set<HKObjectType> {   // 健康页（HealthView.swift）也用
        var s = Set<HKObjectType>()
        for id in quantityIDs { if let t = q(id) { s.insert(t) } }
        for id in categoryIDs { if let t = c(id) { s.insert(t) } }
        s.insert(HKObjectType.workoutType())
        return s
    }

    /// 启动时（包括被健康的新数据从后台拉起来）先把监听挂上，不然后台送来的通知没人接
    func appLaunched() {
        guard HKHealthStore.isHealthDataAvailable(), UserDefaults.standard.bool(forKey: Self.askedKey) else { return }
        startObservers()
    }

    /// 回前台：每次进程第一次先问一遍权限（问过的类型系统不再弹，直接回来），再报
    func appActive() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard askedThisRun else {
            askedThisRun = true
            store.requestAuthorization(toShare: nil, read: Self.readTypes) { [weak self] _, _ in
                DispatchQueue.main.async {
                    UserDefaults.standard.set(true, forKey: HealthReporter.askedKey)
                    self?.startObservers()
                    self?.report(force: true)
                }
            }
            return
        }
        report(force: false)
    }

    /// 权限页用。苹果不告诉 App 读权限到底给没给，只能知道还要不要再弹一次：
    /// 要弹＝「未决定」，不用弹＝「已设置」，查不了（安装链接那条线没签 healthkit）＝「不可用」
    func permissionStatus(_ cb: @escaping (String) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { cb("不可用"); return }
        store.getRequestStatusForAuthorization(toShare: [], read: Self.readTypes) { status, _ in
            let s: String
            switch status {
            case .shouldRequest: s = "未决定"
            case .unnecessary: s = "已设置"
            default: s = "不可用"
            }
            DispatchQueue.main.async { cb(s) }
        }
    }

    /// 权限页点「开启」：弹授权，回来就挂监听、报一份
    func askFromSettings(_ done: @escaping () -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { done(); return }
        askedThisRun = true
        store.requestAuthorization(toShare: nil, read: Self.readTypes) { [weak self] _, _ in
            DispatchQueue.main.async {
                UserDefaults.standard.set(true, forKey: HealthReporter.askedKey)
                self?.startObservers()
                self?.report(force: true)
                done()
            }
        }
    }

    private func startObservers() {
        guard !observersOn else { return }
        observersOn = true
        var watched: [(HKSampleType, HKUpdateFrequency)] = []
        if let t = Self.q(.heartRate) { watched.append((t, .immediate)) }
        if let t = Self.q(.stepCount) { watched.append((t, .hourly)) }
        if let t = Self.q(.oxygenSaturation) { watched.append((t, .hourly)) }
        if let t = Self.c(.sleepAnalysis) { watched.append((t, .hourly)) }
        if let t = Self.c(.menstrualFlow) { watched.append((t, .hourly)) }
        watched.append((HKObjectType.workoutType(), .immediate))
        for (type, freq) in watched {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, done, error in
                guard error == nil, let self = self else { done(); return }
                DispatchQueue.main.async { self.report(force: false, done: done) }
            }
            store.execute(query)
            store.enableBackgroundDelivery(for: type, frequency: freq) { _, _ in }
        }
    }

    private func report(force: Bool, done: (() -> Void)? = nil) {
        guard !secret.isEmpty, !reporting, force || Date().timeIntervalSince(lastReport) > minGap else {
            done?()
            return
        }
        reporting = true
        collect { [weak self] payload in
            guard let self = self else { done?(); return }
            self.reporting = false
            // 只剩 source 一项＝什么都没读到（锁屏、没给权限、没签上 healthkit）
            guard payload.count > 1 else { done?(); return }
            self.lastReport = Date()
            self.send(payload, done: done)
        }
    }

    /// 健康的回调在后台线程上一条条回来，攒在这里，等齐了一起发
    private final class Bag {
        private var d: [String: Any] = ["source": "app"]
        private let lock = NSLock()
        func put(_ k: String, _ v: Any?) {
            guard let v = v else { return }
            lock.lock(); d[k] = v; lock.unlock()
        }
        func snapshot() -> [String: Any] {
            lock.lock(); defer { lock.unlock() }
            return d
        }
    }

    private func collect(_ finish: @escaping ([String: Any]) -> Void) {
        let bag = Bag()
        let group = DispatchGroup()
        let now = Date()
        let today = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: now), end: now, options: .strictStartDate)
        let bpm = HKUnit.count().unitDivided(by: HKUnit.minute())

        // 今天累计的：步数、距离、楼层、活动消耗、锻炼分钟、喝水
        func sum(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ key: String) {
            guard let t = HealthReporter.q(id) else { return }
            group.enter()
            let query = HKStatisticsQuery(quantityType: t, quantitySamplePredicate: today, options: .cumulativeSum) { _, s, _ in
                if let v = s?.sumQuantity()?.doubleValue(for: unit) { bag.put(key, v.rounded()) }
                group.leave()
            }
            store.execute(query)
        }
        // 最近一条：心率、静息心率、血氧……（within 天以内的才算）
        func latest(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ key: String, scale: Double = 1, within days: Double) {
            guard let t = HealthReporter.q(id) else { return }
            group.enter()
            let pred = HKQuery.predicateForSamples(withStart: now.addingTimeInterval(-days * 86400), end: now, options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: t, predicate: pred, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                if let s = samples?.first as? HKQuantitySample {
                    let v = s.quantity.doubleValue(for: unit) * scale
                    let item: [String: Any] = ["v": (v * 10).rounded() / 10, "at": HealthReporter.iso.string(from: s.endDate)]
                    bag.put(key, item)
                }
                group.leave()
            }
            store.execute(query)
        }
        // 某类分类样本（睡眠、经期、正念），拿回来交给 make 去整理
        func samples(_ id: HKCategoryTypeIdentifier, from: Date, _ make: @escaping ([HKCategorySample]) -> Void) {
            guard let t = HealthReporter.c(id) else { return }
            group.enter()
            let pred = HKQuery.predicateForSamples(withStart: from, end: now, options: [])
            let query = HKSampleQuery(sampleType: t, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, ss, _ in
                make((ss as? [HKCategorySample]) ?? [])
                group.leave()
            }
            store.execute(query)
        }

        sum(.stepCount, .count(), "steps")
        sum(.distanceWalkingRunning, .meter(), "distance_m")
        sum(.flightsClimbed, .count(), "flights")
        sum(.activeEnergyBurned, .kilocalorie(), "active_kcal")
        sum(.appleExerciseTime, .minute(), "exercise_min")
        sum(.dietaryWater, .literUnit(with: .milli), "water_ml")

        latest(.heartRate, bpm, "hr_latest", within: 1)
        latest(.restingHeartRate, bpm, "resting_hr", within: 3)
        latest(.walkingHeartRateAverage, bpm, "walking_hr", within: 3)
        latest(.heartRateVariabilitySDNN, .secondUnit(with: .milli), "hrv_ms", within: 3)
        latest(.oxygenSaturation, .percent(), "spo2", scale: 100, within: 3)
        latest(.respiratoryRate, bpm, "resp_rate", within: 3)
        latest(.bodyTemperature, .degreeCelsius(), "body_temp_c", within: 7)
        latest(.bodyMass, .gramUnit(with: .kilo), "body_mass_kg", within: 90)

        // 今天心率的高低和平均
        if let t = HealthReporter.q(.heartRate) {
            group.enter()
            let query = HKStatisticsQuery(quantityType: t, quantitySamplePredicate: today,
                                          options: [.discreteAverage, .discreteMin, .discreteMax]) { _, s, _ in
                if let s = s, let avg = s.averageQuantity()?.doubleValue(for: bpm) {
                    let item: [String: Any] = [
                        "avg": avg.rounded(),
                        "min": s.minimumQuantity()?.doubleValue(for: bpm).rounded() ?? avg.rounded(),
                        "max": s.maximumQuantity()?.doubleValue(for: bpm).rounded() ?? avg.rounded(),
                    ]
                    bag.put("hr_today", item)
                }
                group.leave()
            }
            store.execute(query)
        }

        samples(.sleepAnalysis, from: now.addingTimeInterval(-30 * 3600)) { ss in
            bag.put("sleep", HealthReporter.lastNight(ss))
        }
        samples(.menstrualFlow, from: now.addingTimeInterval(-75 * 86400)) { ss in
            bag.put("period", HealthReporter.period(ss))
        }
        samples(.mindfulSession, from: Calendar.current.startOfDay(for: now)) { ss in
            let total = ss.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            if total > 0 { bag.put("mindful_min", (total / 60).rounded()) }
        }

        // 今天的运动记录
        group.enter()
        let wq = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: today, limit: 20,
                               sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, ss, _ in
            let energy = HKQuantityType(.activeEnergyBurned)
            let ws = (ss as? [HKWorkout]) ?? []
            var list: [[String: Any]] = ws.map { w in
                var x: [String: Any] = [
                    "type": HealthReporter.workoutName(w.workoutActivityType),
                    "min": (w.duration / 60).rounded(),
                    "start": HealthReporter.iso.string(from: w.startDate),
                    "end": HealthReporter.iso.string(from: w.endDate),
                ]
                if let kcal = w.statistics(for: energy)?.sumQuantity()?.doubleValue(for: .kilocalorie()) { x["kcal"] = kcal.rounded() }
                return x
            }
            // 1024 #4264：每次运动里的心率（AirPods Pro 3 / 手表测的）——平均、最高、最高在几点，陈璟的「健康」能看到
            let inner = DispatchGroup()
            let lock = NSLock()
            if let hrType = HealthReporter.q(.heartRate) {
                for (i, w) in ws.enumerated() {
                    inner.enter()
                    let p = HKQuery.predicateForSamples(withStart: w.startDate, end: w.endDate, options: [])
                    let hq = HKSampleQuery(sampleType: hrType, predicate: p, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, hs, _ in
                        let pts = ((hs as? [HKQuantitySample]) ?? []).map { ($0.startDate, $0.quantity.doubleValue(for: bpm)) }
                        if let top = pts.max(by: { $0.1 < $1.1 }) {
                            let avg = pts.reduce(0.0) { $0 + $1.1 } / Double(pts.count)
                            lock.lock()
                            list[i]["hr_avg"] = avg.rounded()
                            list[i]["hr_max"] = top.1.rounded()
                            list[i]["hr_max_at"] = HealthReporter.iso.string(from: top.0)
                            lock.unlock()
                        }
                        inner.leave()
                    }
                    store.execute(hq)
                }
            }
            inner.notify(queue: .global()) {
                if !list.isEmpty { bag.put("workouts", list) }
                group.leave()
            }
        }
        store.execute(wq)

        // 这一周每天动了几分钟（健康页「运动」卡那七根柱子，陈璟那边也看得到）
        group.enter()
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        let weekStart = cal.date(byAdding: .day, value: -6, to: dayStart) ?? dayStart
        let weekQ = HKSampleQuery(sampleType: HKObjectType.workoutType(),
                                  predicate: HKQuery.predicateForSamples(withStart: weekStart, end: now, options: []),
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, ss, _ in
            let ws = (ss as? [HKWorkout]) ?? []
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            let days: [[String: Any]] = (0..<7).reversed().compactMap { i in
                guard let day = cal.date(byAdding: .day, value: -i, to: dayStart) else { return nil }
                let mins = ws.filter { cal.isDate($0.startDate, inSameDayAs: day) }.reduce(0.0) { $0 + $1.duration / 60 }
                return ["date": f.string(from: day), "min": mins.rounded()]
            }
            if !ws.isEmpty { bag.put("workout_week", days) }
            group.leave()
        }
        store.execute(weekQ)

        group.notify(queue: .main) { finish(bag.snapshot()) }
    }

    private static func union(_ spans: [(Date, Date)]) -> TimeInterval {
        var total: TimeInterval = 0
        var cur: (Date, Date)?
        for x in spans.sorted(by: { $0.0 < $1.0 }) {
            if let c = cur, x.0 <= c.1 {
                cur = (c.0, max(c.1, x.1))
            } else {
                if let c = cur { total += c.1.timeIntervalSince(c.0) }
                cur = x
            }
        }
        if let c = cur { total += c.1.timeIntervalSince(c.0) }
        return total
    }

    /// 最近一觉：相邻两条隔超过 3 小时算另一觉，取最后那段。
    /// 手机和手表会各写一份，重叠的按并集算，不重复加。
    /// value：0 在床上 1 睡着（没分段）2 醒着 3 核心 4 深睡 5 快速眼动
    private static func lastNight(_ all: [HKCategorySample]) -> [String: Any]? {
        var session: [HKCategorySample] = []
        var end = Date.distantPast
        for x in all.sorted(by: { $0.startDate < $1.startDate }) {
            if session.isEmpty || x.startDate.timeIntervalSince(end) <= 3 * 3600 {
                session.append(x)
                end = max(end, x.endDate)
            } else {
                session = [x]
                end = x.endDate
            }
        }
        guard let start = session.map({ $0.startDate }).min() else { return nil }
        func span(_ values: Set<Int>) -> TimeInterval {
            union(session.filter { values.contains($0.value) }.map { ($0.startDate, $0.endDate) })
        }
        let asleep = span([1, 3, 4, 5])
        let inBed = span([0])
        guard asleep > 0 || inBed > 0 else { return nil }
        var d: [String: Any] = ["start": iso.string(from: start), "end": iso.string(from: end)]
        if asleep > 0 { d["asleep_min"] = (asleep / 60).rounded() }
        if inBed > 0 { d["in_bed_min"] = (inBed / 60).rounded() }
        for (k, v) in [("deep_min", 4), ("core_min", 3), ("rem_min", 5), ("awake_min", 2)] {
            let t = span([v])
            if t > 0 { d[k] = (t / 60).rounded() }
        }
        return d
    }

    /// 经期：最后一段（隔不超过 2 天算同一次）从哪天开始、最后一天记的流量。
    /// value：1 没写多少 2 少 3 中 4 多 5 没有
    private static func period(_ all: [HKCategorySample]) -> [String: Any]? {
        let flow = all.filter { $0.value != 5 }.sorted { $0.startDate < $1.startDate }
        guard let last = flow.last else { return nil }
        let cal = Calendar.current
        var start = last.startDate
        for x in flow.reversed() {
            let gap = cal.dateComponents([.day], from: cal.startOfDay(for: x.startDate), to: cal.startOfDay(for: start)).day ?? 0
            if gap > 2 { break }
            start = x.startDate
        }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        var d: [String: Any] = ["last_start": day.string(from: start), "last_flow_day": day.string(from: last.startDate)]
        let names = [1: "没写多少", 2: "少", 3: "中", 4: "多"]
        if let n = names[last.value] { d["flow"] = n }
        return d
    }

    static func workoutName(_ t: HKWorkoutActivityType) -> String {
        switch t {
        case .walking: return "走路"
        case .running: return "跑步"
        case .cycling: return "骑车"
        case .hiking: return "徒步"
        case .yoga: return "瑜伽"
        case .pilates: return "普拉提"
        case .swimming: return "游泳"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "力量训练"
        case .highIntensityIntervalTraining: return "HIIT"
        case .cardioDance, .socialDance: return "跳舞"
        case .flexibility: return "拉伸"
        case .mindAndBody: return "身心"
        case .elliptical: return "椭圆机"
        case .stairClimbing, .stairs: return "爬楼"
        default: return "运动"
        }
    }

    private func send(_ payload: [String: Any], done: (() -> Void)?) {
        var req = URLRequest(url: AlcoveAPI.fullURL("/api/health/report"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(secret, forHTTPHeaderField: "X-Auth-Token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        // 被健康的新数据从后台叫醒时系统只给几秒，申请一段时间把这条发完
        var taskID = UIBackgroundTaskIdentifier.invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: "alcove-health") {
            if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }
            taskID = .invalid
        }
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async {
                if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }
                taskID = .invalid
                done?()
            }
        }.resume()
    }
}
