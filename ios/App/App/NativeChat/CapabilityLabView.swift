import SwiftUI
import ReplayKit
import ActivityKit

// 已经通过真机验证的系统联动入口。诊断信息不再暴露给日常设置页。
struct SystemFeaturesView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled = true
    @State private var liveActivityStatus: String?
    @ObservedObject private var screenShare = ScreenShareCoordinator.shared

    var body: some View {
        NavigationStack {
            List {
                Section("灵动岛") {
                    Toggle(isOn: $liveActivityEnabled) {
                        Label("同步陈璟的工作状态", systemImage: "rectangle.inset.filled.and.person.filled")
                    }
                    .onChange(of: liveActivityEnabled) { enabled in
                        Task {
                            if enabled {
                                liveActivityStatus = await AlcoveLiveActivityController.start()
                            } else {
                                await AlcoveLiveActivityController.stop()
                                liveActivityStatus = "灵动岛已关闭。"
                            }
                        }
                    }
                    Text("聊天时把“正在思考、读文件、修改代码”等状态同步到灵动岛；关闭后会立即结束现有活动。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let liveActivityStatus {
                        Text(liveActivityStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("屏幕控制") {
                    Button {
                        screenShare.beginManualShare()
                    } label: {
                        Label("开始共享屏幕", systemImage: "rectangle.on.rectangle")
                            .foregroundStyle(.pink)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .disabled(screenShare.preparing)
                    if !screenShare.message.isEmpty {
                        Text(screenShare.message).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("由你亲手在系统面板中开始或停止。开启期间 iOS 会持续显示录屏提示。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("系统联动")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                if liveActivityEnabled {
                    liveActivityStatus = await AlcoveLiveActivityController.start()
                }
            }
        }
    }

}

struct BroadcastPicker: UIViewRepresentable {
    let trigger: Int

    final class Coordinator { var lastTrigger = 0 }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView()
        // 有些免费重签工具会改写子扩展 Bundle ID，不能写死构建时的地址。
        picker.preferredExtension = installedBroadcastBundleIdentifier
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        guard trigger > 0, trigger != context.coordinator.lastTrigger else { return }
        context.coordinator.lastTrigger = trigger
        DispatchQueue.main.async {
            uiView.subviews.compactMap { $0 as? UIButton }.first?.sendActions(for: .touchUpInside)
        }
    }
}

var installedBroadcastBundleIdentifier: String? {
    guard let directory = Bundle.main.builtInPlugInsURL else { return nil }
    let URLs = ((try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    )) ?? []).filter { $0.pathExtension == "appex" }
    return URLs
            .first { $0.deletingPathExtension().lastPathComponent == "BroadcastUpload" }
            .flatMap { Bundle(url: $0)?.bundleIdentifier }
}

@MainActor
final class ScreenShareCoordinator: ObservableObject {
    static let shared = ScreenShareCoordinator()
    @Published var pickerTrigger = 0
    @Published var preparing = false
    @Published var message = ""
    @Published var request: AlcoveAPI.ScreenShareStatus?
    private var pollTask: Task<Void, Never>?
    private var lastPromptedID = ""

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func pollOnce() async {
        guard let status = try? await AlcoveAPI.screenShareStatus(),
              status.status == "requested", status.expiresIn > 0,
              status.id != lastPromptedID else { return }
        lastPromptedID = status.id
        request = status
    }

    func decline() {
        guard request != nil else { return }
        request = nil
        Task {
            do {
                try await AlcoveAPI.declineScreenShare()
            } catch {
                message = "拒绝状态没有送达：\(error.localizedDescription)"
            }
        }
    }

    func acceptRequest() {
        request = nil
        armAndOpen()
    }

    func beginManualShare() { armAndOpen() }

    private func armAndOpen() {
        guard !preparing else { return }
        preparing = true
        message = "正在创建一次性截图任务…"
        Task {
            do {
                try await AlcoveAPI.armScreenShare()
                message = "请在系统面板中确认开始共享；只会上传第一张画面。"
                pickerTrigger += 1
            } catch {
                message = "创建截图任务失败：\(error.localizedDescription)"
            }
            preparing = false
        }
    }
}

struct RemoteScreenSharePrompt: View {
    @ObservedObject private var coordinator = ScreenShareCoordinator.shared

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .background(BroadcastPicker(trigger: coordinator.pickerTrigger).opacity(0.01))
            .onAppear { coordinator.startPolling() }
            .alert("想看一眼你的屏幕", isPresented: Binding(
                get: { coordinator.request != nil },
                set: { if !$0 { coordinator.decline() } }
            )) {
                Button("暂不共享", role: .cancel) { coordinator.decline() }
                Button("确认并选择屏幕") { coordinator.acceptRequest() }
            } message: {
                Text("\(coordinator.request?.requester ?? "陈璟")发来一次性查看请求。确认后仍需在 iOS 系统面板亲手开始；只上传第一张画面。")
            }
    }
}

@MainActor
enum AlcoveLiveActivityController {
    private static var pulseTask: Task<Void, Never>?
    private static var starting = false
    private static var retryTask: Task<Void, Never>?

    private static func currentBPM() async -> Int {
        guard let raw = try? await AlcoveAPI.getRaw("/pulse/now") else { return 0 }
        if let value = raw["bpm"] as? Int { return value }
        if let value = raw["bpm"] as? NSNumber { return value.intValue }
        return 0
    }

    private static func ensurePulseUpdates() {
        guard pulseTask == nil else { return }
        pulseTask = Task {
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { break }
                guard UserDefaults.standard.object(forKey: "liveActivityEnabled") == nil
                        || UserDefaults.standard.bool(forKey: "liveActivityEnabled") else {
                    break
                }
                let bpm = await currentBPM()
                let activities = Activity<AlcoveLabAttributes>.activities
                if activities.isEmpty {
                    // 开关仍开着但活动被 iOS 清掉：App 还活着时直接重建。
                    _ = await start()
                    continue
                }
                // 0922 任务#2585 她报的「胶囊有时自己消失、不更新」：
                // ① 系统给一次实时活动最多 8 小时，到点就自己没了。快到点（7.5h）App 还醒着就先结束再开一块新的。
                // ② 原来只在心率变了才写；现在每 15 拍（一分钟）不管变没变都写一次，防止某一块漏掉。
                // ③ 原来 start()/sync() 只写 activities.first，多出来的那块永远是旧字——这里和下面都改成全写。
                let expired = activities.filter { Date().timeIntervalSince($0.content.state.startedAt) > 7.5 * 3600 }
                if !expired.isEmpty {
                    for activity in expired { await activity.end(nil, dismissalPolicy: .immediate) }
                    _ = await start()
                    continue
                }
                tick += 1
                guard bpm > 0 else { continue }
                for activity in activities where activity.content.state.bpm != bpm || tick % 15 == 0 {
                    var state = activity.content.state
                    state.bpm = bpm
                    await activity.update(ActivityContent(state: state, staleDate: nil))
                }
            }
            pulseTask = nil
        }
    }

    static func start() async -> String {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return "系统未允许实时活动，请在 iPhone 设置中开启。"
        }
        guard !starting else { return "灵动岛正在刷新。" }
        starting = true
        defer { starting = false }

        let state = AlcoveLabAttributes.ContentState(
            message: "等待任务", startedAt: .now, bpm: await currentBPM()
        )
        let existing = Activity<AlcoveLabAttributes>.activities
        if !existing.isEmpty {
            for activity in existing {   // 0922：全写，别只写 first
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
            ensurePulseUpdates()
            return "灵动岛已开启。"
        }

        do {
            _ = try Activity.request(
                attributes: AlcoveLabAttributes(
                    name: UserDefaults.standard.string(forKey: "assistantName") ?? "陈璟"
                ),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            ensurePulseUpdates()
            // 0819 她点刷新一路显示「已开启」，锁屏和灵动岛却都是空的。
            // request 不抛错 ≠ 系统真的收下了：配额满、僵尸活动占位的时候
            // 它照样安静返回。ensureRunning() 那条路早就不信这个返回值了
            // （会回头读 activities 再补试），手点刷新这条却一直在说假话。
            // 回头看一眼真实的活动列表再开口。
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Activity<AlcoveLabAttributes>.activities.isEmpty {
                scheduleRetry()
                return "系统收下了请求，但活动没出现——正在补试三次。还是不出来的话：先把这个开关关掉等两秒再开，仍然没有就重启一次手机。"
            }
            return "灵动岛已开启。"
        } catch {
            return "灵动岛启动失败：\(error.localizedDescription)"
        }
    }

    static func ensureRunning() async {
        guard UserDefaults.standard.object(forKey: "liveActivityEnabled") == nil
                || UserDefaults.standard.bool(forKey: "liveActivityEnabled") else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let existing = Activity<AlcoveLabAttributes>.activities
        if !existing.isEmpty {
            let bpm = await currentBPM()
            for activity in existing where bpm > 0 {   // 0922：回前台每块都刷一遍
                var state = activity.content.state
                state.bpm = bpm
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
            ensurePulseUpdates()
        } else {
            let result = await start()
            // 冷启动时 ActivityKit 偶尔尚未接纳首个 request。不要只相信返回文案，
            // 重新读取系统活动列表；仍为空就继续补试，直到真的出现或 App 被挂起。
            if Activity<AlcoveLabAttributes>.activities.isEmpty,
               !result.contains("系统未允许") {
                scheduleRetry()
            }
        }
    }

    private static func scheduleRetry() {
        guard retryTask == nil else { return }
        retryTask = Task {
            defer { retryTask = nil }
            for delay in [1.5, 3.0, 6.0] {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled,
                      UserDefaults.standard.object(forKey: "liveActivityEnabled") == nil
                        || UserDefaults.standard.bool(forKey: "liveActivityEnabled") else { return }
                if !Activity<AlcoveLabAttributes>.activities.isEmpty {
                    ensurePulseUpdates()
                    return
                }
                _ = await start()
            }
        }
    }

    static func sync(_ live: AlcoveAPI.LiveState?) async {
        guard UserDefaults.standard.object(forKey: "liveActivityEnabled") == nil
                || UserDefaults.standard.bool(forKey: "liveActivityEnabled") else {
            await stop()
            return
        }
        guard let live, live.active || live.finishing else {
            // 实时工作流结束只代表陈璟回到空闲，不代表用户关闭了灵动岛。
            // 保留活动并切回等待态；真正结束只允许走设置开关的 stop()。
            _ = await start()
            return
        }

        let message: String
        if !live.tool.isEmpty {
            message = "正在\(live.tool)…"
        } else if !live.pendingSay.isEmpty || !live.say.isEmpty {
            message = "正在回复你…"
        } else {
            message = "正在思考…"
        }

        let state = AlcoveLabAttributes.ContentState(
            message: message, startedAt: .now, bpm: await currentBPM()
        )
        let existing = Activity<AlcoveLabAttributes>.activities
        if !existing.isEmpty {
            for activity in existing {   // 0922：全写，别只写 first
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
            ensurePulseUpdates()
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        _ = try? Activity.request(
            attributes: AlcoveLabAttributes(name: UserDefaults.standard.string(forKey: "assistantName") ?? "陈璟"),
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
        ensurePulseUpdates()
    }

    static func stop() async {
        retryTask?.cancel()
        retryTask = nil
        pulseTask?.cancel()
        pulseTask = nil
        for activity in Activity<AlcoveLabAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
