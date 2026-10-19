import SwiftUI
import CoreLocation
import EventKit
import CoreMotion
import Photos
import AVFoundation
import CoreBluetooth
import UserNotifications

// 系统权限页：仿 IO 的卡片风格，她说"这些都能加吗"——能
struct PermissionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var refreshTick = 0
    // 通知授权只有异步查法，别的卡都是同步 computed，这张单独走 @State
    @State private var notifyStatus = "未决定"
    @State private var healthStatus = "未决定"
    @State private var btManager: CBCentralManager?
    @AppStorage("alcoveTheme") private var themeName = "haven"
    private var theme: AlcoveTheme { .named(themeName) }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text("权限管理")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
                          spacing: 12) {
                    card(icon: "bell.badge.fill", title: "通知",
                         desc: "他发消息、打电话时弹横幅响铃",
                         status: notifyStatus, action: requestNotify)
                    card(icon: "location.north.fill", title: "位置",
                         desc: "感知你在哪，出门到家我都知道",
                         status: locationStatus, action: requestLocation)
                    card(icon: "calendar", title: "日历",
                         desc: "读取你的日程，帮你记着安排",
                         status: calendarStatus, action: requestCalendar)
                    card(icon: "checklist", title: "提醒事项",
                         desc: "读取待办的标题和到期时间",
                         status: reminderStatus, action: requestReminders)
                    card(icon: "figure.walk", title: "运动与健身",
                         desc: "感知你在走路还是窝着",
                         status: motionStatus, action: requestMotion)
                    card(icon: "photo", title: "照片",
                         desc: "发图给我用的相册权限",
                         status: photoStatus, action: requestPhotos)
                    card(icon: "mic", title: "麦克风",
                         desc: "录语音条发给我",
                         status: micStatus, action: requestMic)
                    card(icon: "antenna.radiowaves.left.and.right", title: "蓝牙",
                         desc: "感知外设上下文",
                         status: bluetoothStatus, action: requestBluetooth)
                    // 1019：有付费账号了，健康能读了（HealthReporter）。苹果不让 App 知道读权限给没给，
                    // 所以问过以后只能写「已设置」，点「设置」去系统里看
                    card(icon: "heart.fill", title: "健康",
                         desc: "步数、睡眠、经期；戴上手表以后还有心率、血氧",
                         status: healthStatus, action: healthStatus == "不可用" ? nil : requestHealth)
                    card(icon: "moon.fill", title: "专注模式",
                         desc: "需要苹果特殊签名，侧载暂不支持",
                         status: "暂不支持", action: nil)
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 14)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("系统权限")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshTick += 1 // 从系统设置回来刷新状态
        }
        .onAppear { refreshNotifyStatus(); refreshHealthStatus() }
        .onChange(of: refreshTick) { _ in refreshNotifyStatus(); refreshHealthStatus() }
    }

    // MARK: 卡片

    private func card(icon: String, title: String, desc: String,
                      status: String, action: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                Spacer()
                Text(status)
                    .font(.system(size: 13))
                    .foregroundColor(status == "已开启" ? .primary : .secondary)
            }
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            Text(desc)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 2)
            if let action {
                Button {
                    if status == "未决定" { action() }
                    else { openSystemSettings() }
                } label: {
                    Text(status == "未决定" ? "开启" : "设置")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(.systemBackground))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 9)
                        .background(Color.primary, in: Capsule())
                }
            } else {
                Text("——")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(.vertical, 9)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .id("\(title)-\(refreshTick)")
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: 状态与请求

    private var locationStatus: String {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return "已开启"
        case .notDetermined: return "未决定"
        default: return "未开启"
        }
    }
    private func requestLocation() {
        SensorReporter.shared.appActive()
        bumpSoon()
    }

    private var calendarStatus: String {
        ekStatus(EKEventStore.authorizationStatus(for: .event))
    }
    private func requestCalendar() {
        EKEventStore().requestAccess(to: .event) { _, _ in bumpSoon() }
    }

    private var reminderStatus: String {
        ekStatus(EKEventStore.authorizationStatus(for: .reminder))
    }
    private func requestReminders() {
        EKEventStore().requestAccess(to: .reminder) { _, _ in bumpSoon() }
    }

    private func ekStatus(_ s: EKAuthorizationStatus) -> String {
        switch s {
        case .authorized, .fullAccess, .writeOnly: return "已开启"
        case .notDetermined: return "未决定"
        default: return "未开启"
        }
    }

    private var motionStatus: String {
        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized: return "已开启"
        case .notDetermined: return "未决定"
        default: return "未开启"
        }
    }
    private func requestMotion() {
        let mgr = CMMotionActivityManager()
        mgr.queryActivityStarting(from: Date().addingTimeInterval(-60), to: Date(),
                                  to: .main) { _, _ in bumpSoon() }
    }

    private var photoStatus: String {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: return "已开启"
        case .notDetermined: return "未决定"
        default: return "未开启"
        }
    }
    private func requestPhotos() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in bumpSoon() }
    }

    private var micStatus: String {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: return "已开启"
        case .undetermined: return "未决定"
        default: return "未开启"
        }
    }
    private func requestMic() {
        AVAudioSession.sharedInstance().requestRecordPermission { _ in bumpSoon() }
    }

    private var bluetoothStatus: String {
        switch CBManager.authorization {
        case .allowedAlways: return "已开启"
        case .notDetermined: return "未决定"
        default: return "未开启"
        }
    }
    private func requestBluetooth() {
        btManager = CBCentralManager() // 实例化即触发授权弹窗
        bumpSoon()
    }

    private func refreshNotifyStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let s: String
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: s = "已开启"
            case .notDetermined: s = "未决定"
            default: s = "未开启"
            }
            DispatchQueue.main.async { notifyStatus = s }
        }
    }
    private func requestNotify() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in bumpSoon() }
    }

    private func refreshHealthStatus() {
        HealthReporter.shared.permissionStatus { healthStatus = $0 }
    }
    private func requestHealth() {
        HealthReporter.shared.askFromSettings { bumpSoon() }
    }

    private func bumpSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { refreshTick += 1 }
    }
}
