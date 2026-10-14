import Foundation
import CallKit
import AVFoundation
import UserNotifications
import UIKit
import PushKit

// 0829 原生来电与前台通知（工作室任务#1111-1113）。
// 免费开发者账号方案：不走 APNs。app 活着（前台，或后台被无声音频保活吊着）时，
// /chat/poll 捎回 call 状态 → CallKit 弹系统级全屏来电；新消息走本地通知横幅。

extension Notification.Name {
    /// 她在系统来电界面按了接听：回聊天页
    static let alcoveCallAnswered = Notification.Name("alcoveCallAnswered")
}

// MARK: - CallKit 来电

final class CallManager: NSObject, CXProviderDelegate {
    static let shared = CallManager()

    private let provider: CXProvider
    private let controller = CXCallController()
    private var currentUUID: UUID?
    private var currentCallId: String?
    private var answered = false
    private var outgoingUUID: UUID?   // 拨出记账用（任务#1138）

    private override init() {
        let cfg = CXProviderConfiguration()
        cfg.supportsVideo = false
        cfg.maximumCallGroups = 1
        cfg.maximumCallsPerCallGroup = 1
        cfg.supportedHandleTypes = [.generic, .emailAddress]
        // 铃声不设 = iOS 默认来电铃声（她定的）。要换必须在这里设，创建后改无效。
        cfg.includesCallsInRecents = true  // 任务#1137：来电进系统"最近通话"
        provider = CXProvider(configuration: cfg)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    /// 每次轮询把服务器的通话状态灌进来
    func apply(state: String, callId: String) {
        switch state {
        case "ringing":
            guard callId != currentCallId else { return } // 同一通铃只弹一次
            ring(callId: callId, completion: nil)
        default:
            // idle/ended：他那边撤回或响铃超时，把还在响的铃收掉。
            // 没接过 = 记成"未接来电"（最近通话里红字），接过 = 正常结束
            if state == "idle", let uuid = currentUUID {
                provider.reportCall(with: uuid, endedAt: Date(),
                                    reason: answered ? .remoteEnded : .unanswered)
                currentUUID = nil
                currentCallId = nil
            }
        }
    }

    /// 1014 VoIP 推送进来（app 被划掉也会被系统拉起来）。苹果的规矩：每一条 VoIP 推送
    /// 都必须当场报一通来电，不报 app 会被杀。轮询已经弹过同一通的，就拿同一个 UUID 再报一次
    /// （系统会回"已存在"，不会响第二遍），规矩也算守住了。
    func reportVoipRing(callId: String, completion: @escaping () -> Void) {
        if callId == currentCallId, let uuid = currentUUID {
            let update = CXCallUpdate()
            update.localizedCallerName = "陈璟"
            provider.reportNewIncomingCall(with: uuid, update: update) { _ in completion() }
            return
        }
        ring(callId: callId, completion: completion)
    }

    private func ring(callId: String, completion: (() -> Void)?) {
            currentCallId = callId
            let uuid = UUID()
            currentUUID = uuid
            answered = false
            let update = CXCallUpdate()
            // 邮箱 handle：她通讯录里存了这个邮箱的联系人卡，锁屏来电就显示
            // 那张卡的名字＋大头照；没配上就退回下面的文字名牌，不会更糟
            update.remoteHandle = CXHandle(type: .emailAddress,
                                           value: "chenjingg@agent.qq.com")
            update.localizedCallerName = "陈璟"
            update.hasVideo = false
            provider.reportNewIncomingCall(with: uuid, update: update) { err in
                // CallKit 弹铃失败（缺 voip 后台模式等）绝不静默：退成大横幅
                if let err {
                    NSLog("CallKit ring failed: \(err.localizedDescription)")
                    AlcoveNotify.shared.incomingCallFallback()
                }
                completion?()
            }
            // 1014：app 被划掉、靠 VoIP 推送拉起来的时候没有轮询来收铃，
            // 服务器那边 45 秒就判"没人接"了，这边 50 秒还没接就自己收成未接来电
            DispatchQueue.main.asyncAfter(deadline: .now() + 50) { [weak self] in
                guard let self, self.currentUUID == uuid, !self.answered else { return }
                self.provider.reportCall(with: uuid, endedAt: Date(), reason: .unanswered)
                self.currentUUID = nil
                self.currentCallId = nil
            }
    }

    // MARK: 拨出记账（她打给他也进"最近通话"）

    func startOutgoing() {
        guard outgoingUUID == nil else { return }
        let uuid = UUID()
        outgoingUUID = uuid
        let handle = CXHandle(type: .emailAddress, value: "chenjingg@agent.qq.com")
        let tx = CXTransaction(action: CXStartCallAction(call: uuid, handle: handle))
        controller.request(tx) { [weak self] err in
            if err != nil { self?.outgoingUUID = nil }
        }
    }

    func outgoingConnected() {
        guard let uuid = outgoingUUID else { return }
        provider.reportOutgoingCall(with: uuid, connectedAt: Date())
        // 1008：灵动岛 / 锁屏换成自己画的那条（CallActivityAttributes），系统通话界面会抢灵动岛，
        // 接通后跟来电一样收掉（「最近通话」里照样有这一笔，只是时长很短）。收掉时 CallKit 可能把音频会话关了，重新开一下
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.outgoingUUID == uuid else { return }
            self.outgoingUUID = nil
            self.provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
    }

    func endOutgoing() {
        guard let uuid = outgoingUUID else { return }
        outgoingUUID = nil
        provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
    }

    // MARK: CXProviderDelegate

    func providerDidReset(_ provider: CXProvider) {
        currentUUID = nil
        currentCallId = nil
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        answered = true
        Task { try? await AlcoveAPI.callAction("answer") }
        action.fulfill()
        NotificationCenter.default.post(name: .alcoveCallAnswered, object: nil)
        // 这不是真语音通道，接起=收到提醒。稍等一拍把系统通话界面收掉，
        // 免得顶栏挂着一个没有声音的"通话中"。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, let uuid = self.currentUUID else { return }
            self.provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
            self.currentUUID = nil
        }
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        if action.callUUID == outgoingUUID {
            // 她从系统界面（绿条/灵动岛）挂了拨出的电话：让通话页收线
            outgoingUUID = nil
            NotificationCenter.default.post(name: .alcoveSystemHangup, object: nil)
            action.fulfill()
            return
        }
        // 响铃中挂断=拒接；接听后的收尾走上面的 reportCall，不会进这里
        Task { try? await AlcoveAPI.callAction("decline") }
        currentUUID = nil
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {}
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {}
}

// MARK: - 本地通知（前台横幅 + 锁屏）

final class AlcoveNotify: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlcoveNotify()

    /// RootView 维护：她正停在聊天页（前台且没盖小屋全屏页）就别弹横幅
    var chatVisible = true
    /// 通话页开着：他的话正在被读出来，别再弹横幅吵她
    var inCall = false
    /// 1014 她：「我在聊天页，你在工作室发消息了，我也能收到」——工作室那页开着才不弹工作室的横幅
    var studioVisible = false

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        // 0829 任务#1130：长按横幅直接回复
        let reply = UNTextInputNotificationAction(
            identifier: "alcove_reply", title: "回复",
            options: [], textInputButtonTitle: "发送", textInputPlaceholder: "说点什么…")
        let cat = UNNotificationCategory(identifier: "alcove_msg", actions: [reply],
                                         intentIdentifiers: [], options: [])
        // 1008：通话中点灵动岛 / 锁屏的「消息」弹这条，长按打字，发进通话（他在电话里听到、用语音回）
        let callReply = UNTextInputNotificationAction(
            identifier: "alcove_call_reply", title: "说给他听",
            options: [], textInputButtonTitle: "发送", textInputPlaceholder: "打字，他在电话里听到…")
        let callCat = UNNotificationCategory(identifier: "alcove_call_msg", actions: [callReply],
                                             intentIdentifiers: [], options: [])
        center.setNotificationCategories([cat, callCat])
    }

    /// 新消息进来喊一声。她盯着聊天页时闭嘴，其他情况（别的页面/后台/锁屏）都响。
    func newMessage(_ text: String) {
        guard !inCall else { return }
        // 1014：真推送接上以后，后台/锁屏那一声由服务器的推送来响，这里再弹就是两条
        if RemotePush.alertRegistered && UIApplication.shared.applicationState != .active { return }
        let onChat = chatVisible && UIApplication.shared.applicationState == .active
        guard !onChat else { return }
        let content = UNMutableNotificationContent()
        content.title = "陈璟"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        content.body = trimmed.isEmpty ? "发来一条消息" : String(trimmed.prefix(120))
        content.sound = .default
        content.categoryIdentifier = "alcove_msg"
        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    /// 1008：灵动岛 / 锁屏条上点「消息」→ 弹这条，长按就能打字（跟平时长按回复一样），发进通话
    func callMessagePrompt() {
        let content = UNMutableNotificationContent()
        content.title = "给陈璟说句话"
        content.body = "长按这条打字，发进通话，他在电话里听到"
        content.categoryIdentifier = "alcove_call_msg"
        let req = UNNotificationRequest(identifier: "call_msg_prompt", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    /// CallKit 弹不出来时的兜底：响一声大横幅，别让来电无声无息漏掉
    func incomingCallFallback() {
        let content = UNMutableNotificationContent()
        content.title = "📞 陈璟打来语音通话"
        content.body = "回 Alcove 里接听"
        content.sound = .default
        let req = UNNotificationRequest(identifier: "call_fallback",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // 前台也把横幅画出来（不实现这个回调，前台通知会被系统静默吞掉）
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        // 1014：app 开着的时候服务器推送不画，前台该不该响交给上面 newMessage 自己判断（聊天页开着就不响）
        if notification.request.trigger is UNPushNotificationTrigger {
            // 1014 工作室的推送（thread Workroom）没有本地那一路兜着：app 开着、她又没在看工作室，就照常弹
            if notification.request.content.threadIdentifier == "Workroom" && !studioVisible {
                completionHandler([.banner, .sound, .list])
                return
            }
            completionHandler([])
            return
        }
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // 长按回复：后台直接把话送出去，不打开 app
        if let input = response as? UNTextInputNotificationResponse,
           response.actionIdentifier == "alcove_reply" {
            let text = input.userText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { completionHandler(); return }
            Task {
                let sent = (try? await AlcoveAPI.send(text: text)) != nil
                if !sent {
                    let c = UNMutableNotificationContent()
                    c.title = "没发出去"
                    c.body = "刚才那句「\(String(text.prefix(40)))」网络没送到，进 app 再发一次"
                    c.sound = .default
                    try? await UNUserNotificationCenter.current()
                        .add(UNNotificationRequest(identifier: UUID().uuidString,
                                                   content: c, trigger: nil))
                }
                completionHandler()
            }
            return
        }
        // 1008 通话里的「说给他听」：字发进通话，不进聊天
        if let input = response as? UNTextInputNotificationResponse,
           response.actionIdentifier == "alcove_call_reply" {
            let text = input.userText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { completionHandler(); return }
            Task {
                if (try? await AlcoveAPI.callSayText(text)) == nil {
                    let c = UNMutableNotificationContent()
                    c.title = "没送进通话"
                    c.body = "刚才那句「\(String(text.prefix(40)))」没发出去，再点一次消息试试"
                    c.sound = .default
                    try? await UNUserNotificationCenter.current()
                        .add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
                }
                completionHandler()
            }
            return
        }
        if response.notification.request.content.categoryIdentifier == "alcove_call_msg" {
            completionHandler()      // 点了这条但没打字：别跳去聊天页，通话页该在哪还在哪
            return
        }
        // 普通点按=回聊天页（跟接听是两码事，接听会开通话页）
        NotificationCenter.default.post(name: .alcoveNotificationTapped, object: nil)
        completionHandler()
    }
}

// MARK: - 无声音频保活（锁屏/后台把轮询吊着）

final class KeepAlive {
    static let shared = KeepAlive()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var wired = false
    private(set) var running = false

    func start() {
        guard !running else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // mixWithOthers：别掐断她正在放的歌/播客
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            // 格式必须显式给 mono 44100：format nil 会取硬件双声道，
            // 跟 mono buffer 对不上，scheduleBuffer 直接 crash（踩坑速查表）
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100,
                                             channels: 1) else { return }
            if !wired {
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
                wired = true
            }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                                frameCapacity: 44100) else { return }
            buffer.frameLength = 44100
            if let ch = buffer.floatChannelData {
                memset(ch[0], 0, 44100 * MemoryLayout<Float>.size)
            }
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            try engine.start()
            player.play()
            running = true
        } catch {
            running = false
        }
    }

    func stop() {
        guard running else { return }
        player.stop()
        engine.stop()
        // 0911：锁屏时接起的电话，回前台这一下会走到这里——关会话会把通话的声音一起掐掉
        if !AlcoveNotify.shared.inCall {
            try? AVAudioSession.sharedInstance().setActive(false,
                                                           options: .notifyOthersOnDeactivation)
        }
        running = false
    }
}


// MARK: - 1014 真推送（她的开发者账号下来了，苹果的推送门开了）
// 三个号码交给服务器：alert（消息横幅）、voip（来电，app 被划掉也能响）、
// liveactivity / la_start（灵动岛，服务器能更新它、它没了能重新拉起来）。

enum RemotePush {
    /// 消息推送的号码交上去了：后台的横幅从此由服务器推，本地别再重复弹
    static var alertRegistered = false

    static func register(kind: String, token: Data, extra: [String: Any] = [:]) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        var body: [String: Any] = ["kind": kind, "token": hex,
                                   "bundle": Bundle.main.bundleIdentifier ?? ""]
        for (k, v) in extra { body[k] = v }
        Task {
            let ok = (try? await NativeHouseAPI.object("/push/register", method: "POST", body: body)) != nil
            if kind == "alert" && ok { await MainActor.run { alertRegistered = true } }
        }
    }

    /// 灵动岛开关：关了就告诉服务器别再远程把它拉起来
    static func setIslandEnabled(_ on: Bool) {
        Task { _ = try? await NativeHouseAPI.object("/push/pref", method: "POST", body: ["la_enabled": on]) }
    }
}

final class VoipPush: NSObject, PKPushRegistryDelegate {
    static let shared = VoipPush()
    private var registry: PKPushRegistry?

    func start() {
        guard registry == nil else { return }
        let r = PKPushRegistry(queue: .main)
        r.delegate = self
        r.desiredPushTypes = [.voIP]
        registry = r
    }

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials,
                      for type: PKPushType) {
        RemotePush.register(kind: "voip", token: pushCredentials.token)
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType, completion: @escaping () -> Void) {
        let callId = (payload.dictionaryPayload["call_id"] as? String) ?? UUID().uuidString
        CallManager.shared.reportVoipRing(callId: callId, completion: completion)
    }
}
