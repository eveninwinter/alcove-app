import SwiftUI
import AVFoundation
import UIKit

// 语音通话页。0831 任务#1195 大改：通话的对话搬出主聊天，只在这一页显示。
//
// 链路（改完之后）：
//   她按住说 → 录音 → /call/say 听写 + 语气分析 → 照旧注入他的会话（他一个字不少）
//              → 同时落进服务端的**通话记录**，聊天页那条藏掉
//   他回话   → stop hook 投过来，服务端看见电话正接着，整段拐进通话记录（不进主聊天）
//              → **落库那一刻就在后台把配音做好**
//   这一页   → 反复取通话记录，新的画成气泡；他那句的 mp3 已经现成，取回来就放
//   挂断     → 聊天页留**一条**摘要气泡，在打电话那个人那一侧，点开展开这一通
//
// ‼️为什么不再走「聊天页轮询 → /call/tts 现合成」那条老路：
// 合成一段要 2~3.5 秒（实测），而老代码在播放期间根本不开始合成下一段
//（pumpTTS 里那句 player?.isPlaying != true），于是每段之间干听 3~5 秒。
// 现在合成在服务端提前做完、下载在这边提前拉好，播完一段接着响下一段。
// **别改回"播完再去取"**，那就是那个老毛病本身。
//
// 陈璟的上下文一点没受影响：注入那一步一个字没改，他的记忆本来就在他自己会话的
// transcript 里，不在 alcove.db。搬走的只是"给 app 看的那份副本"。

enum CallKind: String, Identifiable {
    case incoming, outgoing
    var id: String { rawValue }
}

extension Notification.Name {
    /// 点了通知横幅：只回聊天页，不开通话
    static let alcoveNotificationTapped = Notification.Name("alcoveNotificationTapped")
    /// 系统"最近通话"里点了条目回拨 → 开拨出页
    static let alcoveDialRequested = Notification.Name("alcoveDialRequested")
    /// 她从系统界面（绿条/灵动岛）挂断了拨出的电话
    static let alcoveSystemHangup = Notification.Name("alcoveSystemHangup")
    /// 0902 缩小成胶囊之后点了胶囊 → RootView 把通话页再展开
    static let alcoveCallRestore = Notification.Name("alcoveCallRestore")
    /// 0902 通话结束（挂断/对方挂断）→ RootView 收掉通话页
    static let alcoveCallEnded = Notification.Name("alcoveCallEnded")
    /// 0902 点了小唱片（一起听开着、主聊天露着）→ RootView 把大卡叫回来
    static let alcoveListenRestore = Notification.Name("alcoveListenRestore")
}

// MARK: - 0902 通话总机：通话的命不再绑在通话页上

/// 她 0902 要的「缩小成胶囊，通话不断」。以前 CallSessionModel 是通话页的 @StateObject，
/// 页一关（fullScreenCover 一收）录音、轮询、播放全跟着死。现在通话的状态住在这里，
/// 通话页只是它的一张脸：页收起来 → 胶囊浮出来；点胶囊 → 页再展开；挂断 → 都收。
@MainActor
final class CallHub: ObservableObject {
    static let shared = CallHub()
    @Published private(set) var session: CallSessionModel?
    private(set) var kind: CallKind = .outgoing
    private var pageVisible = false

    /// 通话页要一个会话：有活着的就给它，没有就新建
    func session(for kind: CallKind) -> CallSessionModel {
        if let s = session { return s }
        let s = CallSessionModel()
        self.kind = kind
        session = s
        s.onEnded = { [weak self] in self?.ended() }
        return s
    }

    func pageShown() {
        pageVisible = true
        FloatingOverlay.shared.hide(id: "call")
    }

    /// 通话页收起来了（缩小）：通话还活着就浮出胶囊
    func pageHidden() {
        pageVisible = false
        guard let s = session else { return }
        FloatingOverlay.shared.show(id: "call", defaultY: 120) { CallPill(session: s) }
    }

    private func ended() {
        session = nil
        FloatingOverlay.shared.hide(id: "call")
        NotificationCenter.default.post(name: .alcoveCallEnded, object: nil)
    }
}

/// 吸在屏幕边上的那颗胶囊：微信那个线条电话 + 走动的时长（她 0902 定的：只要这两样）
struct CallPill: View {
    @ObservedObject var session: CallSessionModel

    var body: some View {
        Group {
            HStack(spacing: 6) {
                CallGlyph(size: 13, color: .white, down: false)
                Text(String(format: "%02d:%02d", session.seconds / 60, session.seconds % 60))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(session.speaking ? CallSkin.accent : CallSkin.pillGreen))
            .overlay(Capsule().stroke(.white.opacity(0.55), lineWidth: 1))
            .shadow(color: CallSkin.ink.opacity(0.28), radius: 6, y: 3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("返回通话")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            NotificationCenter.default.post(name: .alcoveCallRestore, object: nil)
        }
    }
}

// MARK: - 通话页配色（白瓷波点，她定的：这一页不做黑夜模式）

enum CallSkin {
    static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255,
              green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255)
    }
    static let ground   = hex(0xF4F1F2)   // 白瓷底
    static let dot      = hex(0xDCD5D8)   // 波点
    static let panel    = hex(0xFBF8F9)   // 气泡底（他）
    static let mine     = hex(0xF2DCE0)   // 气泡底（她）·藕粉
    static let ink      = hex(0x585F6E)
    static let inkDim   = hex(0x9A93A0)
    static let line     = hex(0xE4DDE0)
    static let hangup   = hex(0xC97F86)
    static let accent   = hex(0xB08A94)
    static let pillGreen = hex(0x5FB878)  // 缩小后那颗胶囊：微信通话绿
    // 0911 通话页换成她发的雨夜壁纸（深蓝黑），上面的字和键改用这一组；
    // 0912 通话记录弹窗也换到壁纸上，一起用这组（上面那组白瓷色现在只剩阴影色、电话线条图标默认色这些零碎在用）
    static let onWall    = Color.white
    static let onWallDim = Color.white.opacity(0.62)
    static let glass     = Color.white.opacity(0.16)   // 平时的键：半透明玻璃圆
    static let glassLine = Color.white.opacity(0.32)
}

/// 白瓷上那层波点。自己画一份不借棋牌室那个——那边跟着日夜开关走，
/// 她要这一页固定白天。
struct CallDots: View {
    var spacing: CGFloat = 16
    var radius: CGFloat = 1.7

    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = spacing / 2
            var row = 0
            while y < size.height + spacing {
                var x: CGFloat = (row % 2 == 0) ? spacing / 2 : spacing
                while x < size.width + spacing {
                    let r = CGRect(x: x - radius, y: y - radius,
                                   width: radius * 2, height: radius * 2)
                    ctx.fill(Path(ellipseIn: r), with: .color(CallSkin.dot))
                    x += spacing
                }
                y += spacing * 0.86
                row += 1
            }
        }
        .opacity(0.55)
        .allowsHitTesting(false)
    }
}

/// 圆头像，里面是名字第一个字（跟横屏麻将那套一个思路，以后换真图只改这儿）
struct CallAvatar: View {
    let name: String
    var size: CGFloat = 62
    var active: Bool = false

    private var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1))
    }

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(
                colors: [CallSkin.accent.opacity(0.30), CallSkin.accent.opacity(0.62)],
                startPoint: .top, endPoint: .bottom))
            Circle().fill(LinearGradient(colors: [.white.opacity(0.55), .clear],
                                         startPoint: .top, endPoint: .center))
            Text(initial)
                .font(.system(size: size * 0.42, weight: .medium, design: .serif))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
        .overlay(Circle().stroke(CallSkin.accent.opacity(active ? 0.9 : 0.3),
                                 lineWidth: active ? 2.2 : 1))
        .shadow(color: CallSkin.ink.opacity(active ? 0.22 : 0.12),
                radius: active ? 7 : 3, y: 2)
    }
}

/// 微信那个线条电话（她给的参考图）。不用 emoji——她点名的。
struct CallGlyph: View {
    var size: CGFloat = 15
    var color: Color = CallSkin.ink
    /// 挂断那种（听筒朝下）；false = 正常听筒
    var down: Bool = true

    var body: some View {
        Image(systemName: down ? "phone.down.fill" : "phone.fill")
            .font(.system(size: size, weight: .regular))
            .foregroundColor(color)
    }
}

// MARK: - 会话

@MainActor
final class CallSessionModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var line = "接通中…"
    @Published var seconds = 0
    @Published var recording = false
    @Published var busy = false
    @Published var speaking = false
    @Published var turns: [CallTurn] = []
    /// 0911 她报的：一直没有扬声器，音量开到最大也是听筒。记住她上次的选择
    @Published var speakerOn = UserDefaults.standard.bool(forKey: "callSpeakerOn")
    /// 正在念的那一句（通话页只显示「当下那一段」要用）
    @Published var playingID: Int?

    var onEnded: (() -> Void)?

    private var timer: Timer?
    private var pollTask: Task<Void, Never>?
    private var recorder: AVAudioRecorder?
    private var recURL: URL?
    private var player: AVAudioPlayer?
    private var hangupObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private var isOutgoing = false
    private var closed = false
    /// 0902：通话页可以收起再展开，start 只准跑一次
    private var started = false

    private var callID = ""
    /// 已经念过的（按通话记录的行号）。反复取记录不会把念过的再念一遍
    private var playedIDs: Set<Int> = []
    /// 提前下好的配音。合成在服务端已经做完，这边把下载也提前做掉
    private var audioCache: [Int: Data] = [:]
    private var downloading: Set<Int> = []

    func start(kind: CallKind) {
        guard !started else { return }
        started = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat,
                                 options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
        applySpeaker()
        // 插拔耳机、连蓝牙、CallKit 接管会话都会把扬声器覆盖冲掉，路线一变就按她的选择再按一次。
        // 覆盖本身也会发一次路线变化，跳过那一种，别自己跟自己打转。
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard reason != AVAudioSession.RouteChangeReason.override.rawValue else { return }
            Task { @MainActor in self?.applySpeaker() }
        }
        armRecorder()            // 0902：通话一开始就把第一只录音机备好
        AlcoveNotify.shared.inCall = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.seconds += 1 }
        }
        hangupObserver = NotificationCenter.default.addObserver(
            forName: .alcoveSystemHangup, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.end() }
        }
        if kind == .outgoing {
            isOutgoing = true
            line = "拨号中…"
            Task {
                do {
                    let r = try await AlcoveAPI.callDial()
                    if r.asleep {
                        line = "他睡着了，没接通"
                        try? await Task.sleep(nanoseconds: 2_200_000_000)
                        end()
                    } else if !r.ok {
                        line = "没打通，占线？"
                    } else {
                        line = "通了，等他开口…"
                        callID = r.callID
                        CallManager.shared.startOutgoing()
                        CallManager.shared.outgoingConnected()
                        startPolling()
                    }
                } catch {
                    line = "没打通，网络不给力"
                }
            }
        } else {
            line = "已接听，等他开口…"
            // 来电的铃是服务器推的，call_id 得回头问一次
            Task {
                callID = (try? await AlcoveAPI.callCurrentID()) ?? ""
                startPolling()
            }
        }
    }

    // MARK: 取通话记录

    private func startPolling() {
        guard !callID.isEmpty, pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshTurns()
                try? await Task.sleep(nanoseconds: 1_400_000_000)
            }
        }
    }

    private func refreshTurns() async {
        guard !closed, !callID.isEmpty else { return }
        guard let fresh = try? await AlcoveAPI.callHistory(callID: callID) else { return }
        // 0902 她报的「他的声音总慢一拍」：他那句的文字先落库、声音晚两三秒才回填地址，
        // 条数没变。以前只比条数，回填的地址永远看不见，要等他下一句条数变了才整份重拿。
        // 改成内容不同就更新（CallTurn 是 Equatable），声音一到就能响。
        if fresh != turns { turns = fresh }
        prefetchAudio()
        pump()
    }

    /// 他的每句话一出现就先把 mp3 下下来——哪怕上一句还在放。
    /// 合成服务端已经做完了，这边再把下载也提前做掉，两段之间就彻底没有空档。
    private func prefetchAudio() {
        for t in turns where !t.isMine {
            guard let raw = t.audioURL, audioCache[t.id] == nil,
                  !downloading.contains(t.id), !playedIDs.contains(t.id) else { continue }
            downloading.insert(t.id)
            let tid = t.id
            Task { [weak self] in
                let data = try? await AlcoveAPI.attachmentData(raw)
                await MainActor.run {
                    guard let self else { return }
                    self.downloading.remove(tid)
                    if let data { self.audioCache[tid] = data }
                    self.pump()
                }
            }
        }
    }

    // MARK: 放他的话

    private func pump() {
        guard !closed, player?.isPlaying != true else { return }
        let pending = turns.first { !$0.isMine && !playedIDs.contains($0.id) }
        guard let next = pending else {
            speaking = false
            playingID = nil
            if !recording && !busy { line = "到你说" }
            return
        }
        // 配音还没到（服务端在做 / 还在下载）：等下一轮，别把这句跳过去
        guard let data = audioCache[next.id] else { return }
        playedIDs.insert(next.id)
        audioCache[next.id] = nil
        guard let p = try? AVAudioPlayer(data: data) else { pump(); return }
        p.delegate = self
        player = p
        speaking = true
        playingID = next.id
        line = "他在说…"
        applySpeaker()
        p.play()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer,
                                                 successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            self.playingID = nil
            self.pump()          // 下一句多半已经下好了，接着响
        }
    }

    // MARK: 她说话（按住说，松开发）

    /// 0902 她报的「一句话说好几遍都认不出」：以前按下去那一刻才建录音机、才 record()，
    /// iOS 从建到真正收声要一两百毫秒，她开口快的话第一个字就没了，短句掉一个字听写直接崩。
    /// 现在录音机**提前建好并 prepareToRecord**（通话一开始、每次说完立刻备下一只），
    /// 按下去只剩 record() 这一步，几乎零延迟。
    private var armed: AVAudioRecorder?
    private var armedURL: URL?

    private static let recordSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 24000,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]

    private func armRecorder() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("call_\(Int(Date().timeIntervalSince1970 * 1000)).m4a")
        guard let rec = try? AVAudioRecorder(url: url, settings: Self.recordSettings) else { return }
        rec.prepareToRecord()
        armed = rec
        armedURL = url
    }

    func beginTalk() {
        guard !recording, !closed else { return }
        if armed == nil { armRecorder() }
        guard let rec = armed, let url = armedURL else { return }
        armed = nil
        armedURL = nil
        recorder = rec
        recURL = url
        rec.record()
        recording = true
        applySpeaker()           // 开录音系统会把路线拨回听筒
    }

    func endTalk() {
        guard recording else { return }
        recorder?.stop()
        recorder = nil
        recording = false
        applySpeaker()
        armRecorder()            // 立刻备好下一只，她连着说也不掉字
        guard let url = recURL, let data = try? Data(contentsOf: url),
              data.count > 3000 else { return }   // 手滑碰一下不算话
        recURL = nil
        busy = true
        line = "听写中…"
        Task {
            defer { busy = false }
            if (try? await AlcoveAPI.callSay(audio: data)) != nil {
                line = "他听到了，等回话…"
                await refreshTurns()      // 自己那句立刻上屏，不等下一轮轮询
            } else {
                line = "没听清，再说一遍？"
            }
        }
    }

    // MARK: 扬声器（0911 新做的）

    /// .voiceChat 模式下系统默认走听筒，start 里那个 .defaultToSpeaker 在这儿不作数，
    /// 所以一直都是听筒。必须显式 overrideOutputAudioPort；而且录音开关、开始播放、
    /// 路线变化都会把覆盖冲掉，那几处都会再调一次这里。
    func toggleSpeaker() {
        speakerOn.toggle()
        UserDefaults.standard.set(speakerOn, forKey: "callSpeakerOn")
        applySpeaker()
    }

    private func applySpeaker() {
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(speakerOn ? .speaker : .none)
    }

    // MARK: 当下那一段

    /// 0911 她要的：通话页只显示当下这一段。他正在念 → 念的那句；
    /// 否则最近一句已经出过声的——他那句文字比声音先落库，还没念到的别提前露出来。
    var currentTurn: CallTurn? {
        if let pid = playingID, let t = turns.first(where: { $0.id == pid }) { return t }
        return turns.last { $0.isMine || playedIDs.contains($0.id) }
    }

    // MARK: 收线

    func end() {
        guard !closed else { return }
        closed = true
        Task { try? await AlcoveAPI.callAction("end") }
        pollTask?.cancel(); pollTask = nil
        player?.stop()
        recorder?.stop()
        timer?.invalidate()
        if let o = hangupObserver { NotificationCenter.default.removeObserver(o) }
        if let o = routeObserver { NotificationCenter.default.removeObserver(o) }
        if isOutgoing { CallManager.shared.endOutgoing() }
        AlcoveNotify.shared.inCall = false
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
        onEnded?()
    }
}

// MARK: - 一条对话气泡（通话页 / 聊天页展开共用）

struct CallTurnBubble: View {
    let turn: CallTurn
    var mineName: String = "我"

    // 0912 她说通话记录没换成新版：跟通话页一样放在雨夜壁纸上——半透明玻璃气泡、白字；
    // 他那句底下带他自己写的中文（小字淡色），跟通话页一致
    var body: some View {
        VStack(alignment: turn.isMine ? .trailing : .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 5) {
                Text(turn.text)
                    .font(.system(size: 14.5))
                    .foregroundColor(CallSkin.onWall)
                if !turn.isMine && !turn.zh.isEmpty {
                    Text(turn.zh)
                        .font(.system(size: 12.5))
                        .foregroundColor(CallSkin.onWallDim)
                }
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 13).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(turn.isMine ? CallSkin.accent.opacity(0.45) : CallSkin.glass))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(CallSkin.glassLine, lineWidth: 1))
            if let tone = turn.toneLabel {
                Text(tone)
                    .font(.system(size: 10.5))
                    .foregroundColor(CallSkin.onWallDim)
                    .padding(.horizontal, 9).padding(.vertical, 3.5)
                    .background(Capsule().fill(CallSkin.glass))
                    .overlay(Capsule().stroke(CallSkin.glassLine, lineWidth: 0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: turn.isMine ? .trailing : .leading)
    }
}

// MARK: - 聊天页那条摘要气泡（打完电话只留这一条）

/// 她定的：**谁打过去的就显示在谁那边**，没有例外——拒绝也一样。
/// 左右由外面的 MessageRow 按 role 决定（服务端已经把 role 写成打电话那个人了），
/// 这里只管长相：一行字 + 微信那种线条电话，点一下展开这一通的记录。
struct CallSummaryBubble: View {
    let info: CallSummaryInfo
    let text: String
    let theme: AlcoveTheme
    @State private var showLog = false

    var body: some View {
        Button {
            showLog = true
        } label: {
            HStack(spacing: 8) {
                Text(text)
                    .font(.system(size: 14.5))
                    .foregroundColor(theme.text)
                CallGlyph(size: 15, color: theme.text.opacity(0.75),
                          down: !info.connected)
            }
            .padding(.horizontal, 13).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(theme.fyCardSub))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showLog) {
            CallLogSheet(info: info)
        }
    }
}

/// 点开摘要看到的：这一通的逐句记录，长相跟通话页一致（她要的）
struct CallLogSheet: View {
    let info: CallSummaryInfo
    @Environment(\.dismiss) private var dismiss
    @State private var turns: [CallTurn] = []
    @State private var loading = true

    private var title: String {
        info.kind == "out" ? "我打给他" : "他打给我"
    }

    var body: some View {
        ZStack {
            // 0912：换成通话页那张雨夜壁纸，压一层淡黑，气泡里的白字才看得清
            CallWallpaper()
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(CallSkin.onWall)
                        Text(info.connected ? "通话 " + info.duration : summaryWord)
                            .font(.system(size: 11.5))
                            .foregroundColor(CallSkin.onWallDim)
                    }
                    Spacer()
                    Button("完成") { dismiss() }
                        .font(.system(size: 14))
                        .foregroundColor(CallSkin.onWall)
                }
                .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 10)
                Rectangle().fill(CallSkin.glassLine).frame(height: 1)
                    .padding(.horizontal, 18)
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 11) {
                        if loading {
                            ProgressView().tint(.white).padding(.top, 34)
                        } else if turns.isEmpty {
                            Text("这一通没说上话")
                                .font(.system(size: 12.5))
                                .foregroundColor(CallSkin.onWallDim)
                                .padding(.top, 34)
                        }
                        ForEach(turns) { t in CallTurnBubble(turn: t) }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 16)
                }
            }
        }
        .task {
            turns = (try? await AlcoveAPI.callHistory(callID: info.callID)) ?? []
            loading = false
        }
    }

    private var summaryWord: String {
        switch info.outcome {
        case "declined":  return "已拒绝"
        case "cancelled": return "已取消"
        default:          return "未接通"
        }
    }
}

// MARK: - 通话页

struct CallView: View {
    let kind: CallKind
    /// 缩小：页收起来、通话继续、胶囊浮出来
    var onMinimize: () -> Void
    /// 0902 起会话由 CallHub 发，页只是它的脸——收起再展开还是同一通
    @ObservedObject var session: CallSessionModel

    private var hisName: String {
        UserDefaults.standard.string(forKey: "assistantName") ?? "陈璟"
    }

    // 0911 她要的新样子：壁纸上自己落雨（不用手）、头顶只有他的头像、
    // 对话只显示当下那一段、底下 按住说 / 挂断 / 扬声器 三个圆键。这一页不做黑夜模式。
    @AppStorage("assistantAvatarDataURL") private var avatarDataURL = ""
    @State private var avatar: UIImage?

    var body: some View {
        ZStack {
            CallWallpaper()
            VStack(spacing: 0) {
                header
                Spacer(minLength: 16)
                subtitle
                Spacer(minLength: 16)
                controls
            }
            // 0902 她要的缩小键：左上角，跟微信一个位置；计时挪到右上角
            VStack {
                HStack {
                    Button(action: onMinimize) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(CallSkin.onWall)
                            .frame(width: 40, height: 40)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(String(format: "%02d:%02d", session.seconds / 60, session.seconds % 60))
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(CallSkin.onWall)
                        .padding(.trailing, 20)
                }
                .padding(.leading, 10)
                .padding(.top, 6)
                Spacer()
            }
        }
        .onAppear {
            CallHub.shared.pageShown()
            session.start(kind: kind)
            // 头像是一大串 base64，别每秒跟着计时重新解一遍
            if avatar == nil { avatar = Self.decodeAvatar(avatarDataURL) }
        }
        .interactiveDismissDisabled()
    }

    private static func decodeAvatar(_ dataURL: String) -> UIImage? {
        guard !dataURL.isEmpty else { return nil }
        let parts = dataURL.split(separator: ",", maxSplits: 1)
        let b64 = parts.count == 2 ? String(parts[1]) : dataURL
        guard let data = Data(base64Encoded: b64) else { return nil }
        return UIImage(data: data)
    }

    // MARK: 上面：他的头像 + 名字 + 状态 + 声音竖条

    private var header: some View {
        VStack(spacing: 10) {
            hisAvatar
                .padding(.top, 76)
            Text(hisName)
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .foregroundColor(CallSkin.onWall)
            Text(session.line)
                .font(.system(size: 13))
                .foregroundColor(CallSkin.onWallDim)
            CallVoiceBars(active: session.speaking || session.recording)
                .padding(.top, 8)
        }
    }

    private var hisAvatar: some View {
        Group {
            if let img = avatar {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 92, height: 92)   // 0912 她要缩小一点：118 → 92
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1.5))
            } else {
                CallAvatar(name: hisName, size: 92, active: session.speaking)
            }
        }
        .overlay(Circle()
            .stroke(CallSkin.accent.opacity(session.speaking ? 0.85 : 0), lineWidth: 2.5)
            .padding(-5))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .animation(.easeInOut(duration: 0.25), value: session.speaking)
    }

    // MARK: 中间：当下那一段

    /// 他说的：大字（以后换英文声音、接上翻译，就是大字英文 + 小字中文）；
    /// 她说的：只有中文。她按住说的时候先写「在听你说…」，听写回来换成她那句。
    /// 一段很长时才出滚动，短的就安安静静居中。
    private var subtitle: some View {
        ViewThatFits(in: .vertical) {
            subtitleContent
            ScrollView(showsIndicators: false) { subtitleContent }
        }
        .frame(maxHeight: 320)
        .animation(.easeInOut(duration: 0.25), value: session.currentTurn?.id)
        .animation(.easeInOut(duration: 0.25), value: session.recording)
    }

    @ViewBuilder private var subtitleContent: some View {
        VStack(spacing: 10) {
            if session.recording {
                Text("在听你说…")
                    .font(.system(size: 17, design: .serif))
                    .foregroundColor(CallSkin.onWallDim)
            } else if let t = session.currentTurn {
                // 壁纸下半截有路灯和亮水珠，白字压一层淡黑影，免得糊进去
                VStack(spacing: 8) {
                    Text(t.text)
                        // 0912 她要他的字缩小一点：24 → 20；她那句跟着从 20 → 17，保持比他小一号
                        .font(.system(size: t.isMine ? 17 : 20, design: .serif))
                        .foregroundColor(CallSkin.onWall)
                        .lineSpacing(5)
                        .multilineTextAlignment(.center)
                    // 0912：他那句底下是他自己写的中文（<译>…</译>），小字淡色；她说的只有中文，不显示这行
                    if !t.isMine && !t.zh.isEmpty {
                        Text(t.zh)
                            .font(.system(size: 14, design: .serif))
                            .foregroundColor(CallSkin.onWallDim)
                            .lineSpacing(3)
                            .multilineTextAlignment(.center)
                    }
                }
                .shadow(color: .black.opacity(0.45), radius: 6)
                .id(t.id)
                .transition(.opacity)
            } else {
                Text("说话就开始")
                    .font(.system(size: 15, design: .serif))
                    .foregroundColor(CallSkin.onWallDim)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
    }

    // MARK: 下面：按住说 + 挂断 + 扬声器

    private var controls: some View {
        HStack(alignment: .top, spacing: 0) {
            controlSlot(session.busy ? "等一下…" : (session.recording ? "松开发送" : "按住说话")) {
                micButton
            }
            controlSlot("挂断") { hangupButton }
            controlSlot(session.speakerOn ? "扬声器已开" : "扬声器已关") { speakerButton }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 30)
    }

    private func controlSlot<Content: View>(_ label: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 9) {
            content()
                .frame(height: 76)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(CallSkin.onWallDim)
        }
        .frame(maxWidth: .infinity)
    }

    /// 暗壁纸上的键：平时是半透明玻璃圆 + 白图标，按住说话时填满
    private var micButton: some View {
        Circle()
            .fill(session.recording ? CallSkin.accent : CallSkin.glass)
            .frame(width: 66, height: 66)
            .overlay(Circle().stroke(CallSkin.glassLine, lineWidth: 1))
            .overlay(Image(systemName: "mic.fill")
                .font(.system(size: 24))
                .foregroundColor(.white))
            .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
            .scaleEffect(session.recording ? 1.1 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: session.recording)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !session.recording && !session.busy { session.beginTalk() } }
                .onEnded { _ in session.endTalk() })
    }

    private var hangupButton: some View {
        Button {
            session.end()
        } label: {
            Circle()
                .fill(CallSkin.hangup)
                .frame(width: 74, height: 74)
                .overlay(CallGlyph(size: 26, color: .white, down: true))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    /// 开着：白底深喇叭（亮起来）；关着：半透明玻璃 + 白喇叭。一眼分得清是开是关
    private var speakerButton: some View {
        Button {
            session.toggleSpeaker()
        } label: {
            Circle()
                .fill(session.speakerOn ? Color.white : CallSkin.glass)
                .frame(width: 66, height: 66)
                .overlay(Circle().stroke(CallSkin.glassLine, lineWidth: session.speakerOn ? 0 : 1))
                .overlay(Image(systemName: session.speakerOn ? "speaker.wave.2.fill" : "speaker.fill")
                    .font(.system(size: 22))
                    .foregroundColor(session.speakerOn ? CallSkin.ink : .white))
                .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 名字下面那排声音竖条

/// 他在说、或她按住说的时候轻轻起伏；不接真音量（她说跟参考图差不多就行）
struct CallVoiceBars: View {
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !active)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<18, id: \.self) { i in
                    Capsule()
                        .fill(CallSkin.onWall.opacity(0.75))
                        .frame(width: 3, height: barHeight(i, t))
                }
            }
            .frame(height: 18)
        }
    }

    private func barHeight(_ i: Int, _ t: Double) -> CGFloat {
        guard active else { return 6 }
        let phase: Double = t * 5.2 + Double(i) * 0.7
        let wobble: Double = abs(sin(phase) * cos(t * 2.3 + Double(i) * 0.31))
        return CGFloat(6 + 12 * wobble)
    }
}

// MARK: - 0911 通话页壁纸

/// 她发的雨夜窗户。原本打算在上面做雨滴水波，她说「算了，不做动效了，直接替换这张壁纸」，就放静态图。
/// 图在 MistSplash 文件夹里：那是工程里整个打包的文件夹，往里放文件不用登记工程文件。
enum CallWallpaperAsset {
    static let image: UIImage? = Bundle.main
        .path(forResource: "call-wallpaper", ofType: "jpg", inDirectory: "MistSplash")
        .flatMap(UIImage.init(contentsOfFile:))
}

struct CallWallpaper: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let img = CallWallpaperAsset.image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
