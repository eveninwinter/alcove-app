import Foundation
import CoreLocation
import CoreMotion
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
        lm.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func appActive() {
        inBackground = false
        startSignificantMonitoring()
        askAlwaysIfNeeded()
        startMotionUpdates()
        startStreaming()
        if !bgUpdatesOn { startTicker(fgInterval) }   // 没开成持续定位才靠定时器顶着
        requestNow()
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

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        lastLocation = loc
        guard !secret.isEmpty else { return }
        // 后台持续定位会一直往回丢点，这里再挡一道，节奏由 minGap 说了算
        guard Date().timeIntervalSince(lastReport) > minGap else { return }
        lastReport = Date()
        collectAndSend(loc)
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
