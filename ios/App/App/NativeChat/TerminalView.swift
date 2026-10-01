import SwiftUI
import UIKit

private enum CCWorkState: Equatable {
    case disconnected
    case thinking
    case resting
}

// 0822 她要的：终端页分两种看法。cli = tmux 真终端；sdk = 后端把 SDK session 翻成同款样子。
// 默认跟着主聊天当前 channel 开，但不焊死，顶上能切着看。
enum TerminalMode: String {
    case cli, sdk
}

// 原生终端页：点头像进来看我干活的地方
// tabs/红绿灯/工具键/命令行 全套照 PWA 搬
// 1001 她定的换皮：白天＝薄荷粉淡紫像素 Y2K（mock/terminal/term-day-v2），黑夜＝E 灰颗粒·泡泡糖粉（term-night3-E）。
// 跟全屋黑白开关走。图标全是代码画的像素小图；字用架子上的 Silkscreen（像素）/ Pinyon（花体），没下到先用系统字。
// 三盏灯还在：标题栏右边那三个小方块，亮哪个＝断线 / 在想 / 在线休息。
struct TerminalView: View {
    @Environment(\.dismiss) private var dismiss
    var onDismiss: (() -> Void)? = nil
    var mini = false
    var initialSession = "main"
    var availableSessions = ["main", "assistant", "gemini", "ghost"]
    @State private var session = "main"
    @State private var output = ""
    @State private var cmd = ""
    @State private var workState: CCWorkState = .resting
    @State private var pollTask: Task<Void, Never>?
    @State private var mode: TerminalMode = .cli
    @State private var modeResolved = false   // 第一次按 channel 定默认；之后她切了就听她的
    @State private var sdkSending = false
    @FocusState private var cmdFocused: Bool
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = "dark"
    @ObservedObject private var fontStore = KakaoPackStore.shared

    private var night: Bool { houseAppearance != "light" }
    private var p: TermPalette { night ? .night : .day }

    var body: some View {
        VStack(spacing: 0) {
            if mini {
                miniBar
            } else {
                topBar
                tabRow
            }
            window
            if !mini {
                if mode == .cli { toolbar } else { sdkToolbar }
                inputBar
            }
        }
        .padding(.bottom, mini ? 0 : 6)
        .background(TermPaper(p: p))
        .clipShape(RoundedRectangle(cornerRadius: mini ? 24 : 0, style: .continuous))
        .overlay {
            if mini {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(p.line, lineWidth: 1)
            }
        }
        .shadow(color: mini ? .black.opacity(0.2) : .clear, radius: 16, y: 6)
        .preferredColorScheme(night ? .dark : .light)
        .onAppear {
            session = initialSession
            resolveMode()
            startPoll()
            if fontStore.fonts.isEmpty { fontStore.refresh() }
            ensureFonts()
        }
        .onReceive(fontStore.$fonts) { _ in ensureFonts() }
        .onDisappear { pollTask?.cancel() }
    }

    private func ensureFonts() {
        fontStore.ensureFont(id: TermPalette.pixelFontID)
        if night { fontStore.ensureFont(id: TermPalette.scriptFontID) }
    }
    private func pixel(_ size: CGFloat) -> Font {
        fontStore.registeredName(TermPalette.pixelFontID).map { Font.custom($0, fixedSize: size) }
            ?? .system(size: size - 0.5, weight: .semibold, design: .monospaced)
    }
    private func script(_ size: CGFloat) -> Font {
        fontStore.registeredName(TermPalette.scriptFontID).map { Font.custom($0, fixedSize: size) }
            ?? .system(size: size * 0.7, design: .serif).italic()
    }

    // 工作室那页传的是 work 会话，SDK 跟它没关系，不给切换
    private var canSwitchMode: Bool { availableSessions.contains("main") }

    private func resolveMode() {
        guard canSwitchMode, !modeResolved else { return }
        Task {
            if let ch = try? await AlcoveAPI.sdkChannel(), !modeResolved {
                mode = (ch == "sdk") ? .sdk : .cli
                modeResolved = true
                output = ""
                capture()
            }
        }
    }

    // MARK: 顶栏

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                if let onDismiss { onDismiss() } else { dismiss() }
            } label: {
                Text("<").font(pixel(14)).foregroundColor(p.accent)
                    .frame(width: 32, height: 32)
                    .background(keycap(radius: 8, accent: false))
            }
            .buttonStyle(.plain)
            HStack(spacing: 6) {
                PixelIcon(rows: PX.crt, ink: p.icon(.quiet), scale: 2)
                (Text("alcove").foregroundColor(p.sub) + Text(".term").foregroundColor(p.accent))
                    .font(pixel(12))
                    .tracking(1)
            }
            Spacer(minLength: 4)
            if canSwitchMode { modeSwitch }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    /// 浮在聊天页上的小终端：一行装下图标、会话、开关、收起
    private var miniBar: some View {
        HStack(spacing: 8) {
            PixelIcon(rows: PX.crt, ink: p.icon(.quiet), scale: 1.6)
            sessionTabs(compact: true)
            Spacer(minLength: 2)
            if canSwitchMode { modeSwitch }
            Button { onDismiss?() } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(p.sub)
                    .frame(width: 28, height: 28)
                    .background(keycap(radius: 8, accent: false))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("收起终端")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var modeSwitch: some View {
        HStack(spacing: 2) {
            ForEach([TerminalMode.cli, .sdk], id: \.self) { m in
                Button {
                    guard mode != m else { return }
                    modeResolved = true
                    mode = m
                    output = ""
                    capture()
                } label: {
                    Text(m.rawValue)
                        .font(pixel(10.5))
                        .foregroundColor(mode == m ? p.switchOnText : p.sub)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(mode == m ? p.switchOn : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(p.panel, in: Capsule())
        .overlay(Capsule().stroke(p.line, lineWidth: 1.5))
    }

    private var tabRow: some View {
        sessionTabs(compact: false)
            .padding(.horizontal, 14)
            .padding(.top, 10)
    }

    /// 文件夹样的会话标签；SDK 只有一个
    private func sessionTabs(compact: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 6) {
                if mode == .sdk {
                    folderTab("sdk", on: true, compact: compact)
                } else {
                    ForEach(availableSessions, id: \.self) { s in
                        Button {
                            session = s
                            output = ""
                            capture()
                        } label: { folderTab(s, on: session == s, compact: compact) }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func folderTab(_ name: String, on: Bool, compact: Bool) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: compact ? 6 : 0,
                                           bottomTrailingRadius: compact ? 6 : 0, topTrailingRadius: 6)
        return HStack(spacing: 5) {
            PixelIcon(rows: PX.folder, ink: on ? p.icon(.accent) : p.icon(.quiet), scale: 1.4)
            Text(name).font(pixel(11)).foregroundColor(on ? p.accent : p.sub)
        }
        .padding(.horizontal, 9)
        .padding(.top, 5)
        .padding(.bottom, on && !compact ? 7 : 4)
        .background(on ? p.panel : p.tabOff, in: shape)
        .overlay(shape.stroke(on ? p.frame : p.line,
                              style: StrokeStyle(lineWidth: 1.5, dash: night && on ? [4, 3] : [])))
    }

    // MARK: 终端窗

    private var window: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: mini ? 10 : 0, bottomLeadingRadius: 10,
                                           bottomTrailingRadius: 10, topTrailingRadius: 10)
        let parts = TermParse.split(output)
        return VStack(spacing: 0) {
            HStack(spacing: 7) {
                PixelIcon(rows: PX.crt, ink: p.icon(.accent), scale: 1.3)
                Text("c:\\alcove\\\(mode == .sdk ? "sdk" : session)>")
                    .font(pixel(10))
                    .foregroundColor(p.accent)
                    .lineLimit(1)
                Spacer(minLength: 4)
                lampBox(.disconnected)
                lampBox(.thinking)
                lampBox(.resting)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            dashedRule(p.frameSoft)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if parts.body.isEmpty {
                            Text("…").font(.system(size: 11.5, design: .monospaced)).foregroundColor(p.sub)
                        }
                        ForEach(Array(parts.body.enumerated()), id: \.offset) { _, line in lineView(line) }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
                    .textSelection(.enabled)
                    .id("out")
                }
                .background(alignment: .bottomTrailing) { if night && !mini { ghostWords } }
                .onTapGesture { cmdFocused = false }
                .onChange(of: output) { _ in
                    proxy.scrollTo("out", anchor: .bottom)
                }
            }
            if !parts.status.isEmpty && !mini { statusLabel(parts.status) }
        }
        .background(p.panel, in: shape)
        .overlay(shape.stroke(p.frame, style: StrokeStyle(lineWidth: 1.5, dash: night ? [4, 3] : [])))
        .background(shape.fill(night ? .clear : p.frameShadow).offset(y: 4))
        .overlay(alignment: .topTrailing) { if !mini { stickerTop } }
        .overlay(alignment: .bottomLeading) { if !mini { stickerSide } }
        .padding(.horizontal, mini ? 8 : 12)
        .padding(.bottom, mini ? 8 : 0)
    }

    /// 三盏灯：亮的那个填色（断线粉红 / 在想淡紫 / 休息薄荷），另外两个空框
    private func lampBox(_ lamp: CCWorkState) -> some View {
        let on = workState == lamp
        let c: Color = lamp == .disconnected ? p.lampOff : (lamp == .thinking ? p.lampThink : p.lampRest)
        return Rectangle()
            .fill(on ? c : p.panel)
            .frame(width: 11, height: 11)
            .overlay(Rectangle().stroke(on ? c : p.line, lineWidth: 1.5))
    }

    private func dashedRule(_ c: Color) -> some View {
        Rectangle().fill(.clear).frame(height: 1.5)
            .overlay(Line().stroke(c, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
    }

    @ViewBuilder private func lineView(_ l: TermLine) -> some View {
        let mono = Font.system(size: 11.5, design: .monospaced)
        switch l.kind {
        case .rule:
            Line().stroke(p.ruleDots, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 6]))
                .frame(height: 2).padding(.vertical, 6)
        case .thought:
            HStack(spacing: 6) {
                PixelIcon(rows: PX.hourglass, ink: p.icon(.quiet), scale: 1.3)
                Text(l.text)
                    .font(night ? .system(size: 12, design: .serif).italic() : .system(size: 11, design: .monospaced))
                    .foregroundColor(p.sub)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(night ? .clear : p.tabOff, in: Capsule())
                    .overlay(Capsule().stroke(night ? p.frameSoft : .clear, style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
            }
            .padding(.vertical, 3)
        case .tool:
            Text(l.text).font(.system(size: 11, design: .monospaced)).foregroundColor(p.sub)
                .padding(.leading, 21)
        case .me, .him:
            HStack(alignment: .top, spacing: 7) {
                Group {
                    if l.kind == .me { PixelIcon(rows: PX.cursor, ink: p.icon(.accent), scale: 1.3) }
                    else { PixelIcon(rows: PX.bubble, ink: p.icon(.second), scale: 1.3) }
                }
                .frame(width: 14).padding(.top, 2)
                Text(l.text).font(mono).foregroundColor(l.kind == .me ? p.meText : p.ink)
            }
        case .meMore, .himMore, .plain:
            Text(l.text).font(mono)
                .foregroundColor(l.kind == .meMore ? p.meText : (l.kind == .plain ? p.plain : p.ink))
                .padding(.leading, l.kind == .plain ? 0 : 21)
        }
    }

    /// 最后一道横线下面那几行（模型、上下文、用量、保活…）收进一张软盘标签
    private func statusLabel(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                PixelIcon(rows: PX.floppy, ink: p.icon(.quiet), scale: 1.2)
                Text("status.dat").font(pixel(10)).foregroundColor(p.labelHeadText)
                Spacer()
                PixelIcon(rows: PX.bolt, ink: p.icon(.accent), scale: 1.1)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(p.labelHead)
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.system(size: 10.5, design: .monospaced)).foregroundColor(p.sub)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                        .overlay(alignment: .bottom) { Rectangle().fill(p.line.opacity(0.6)).frame(height: 1) }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .textSelection(.enabled)
        }
        .background(p.panel2)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(p.line, style: StrokeStyle(lineWidth: 1.5, dash: night ? [2, 2] : [])))
        .padding(.horizontal, 10).padding(.bottom, 10).padding(.top, 2)
    }

    // 白天：光盘＋软盘＋笑脸贴纸；黑夜：半调像素花＋点线花茎（她递的参考）。都不吃触摸
    @ViewBuilder private var stickerTop: some View {
        if night {
            HalftoneFlower(pink: p.accent, big: true).frame(width: 96, height: 120).offset(x: 20, y: 30)
        } else {
            PixelDisc(colors: [p.pinkSoft, p.lilacSoft, p.mintSoft, .white], rim: p.sub).frame(width: 38, height: 38)
                .offset(x: 14, y: 30)
        }
    }
    @ViewBuilder private var stickerSide: some View {
        if night {
            HalftoneFlower(pink: p.accent, big: false).frame(width: 64, height: 72).offset(x: -16, y: -150)
        } else {
            PixelIcon(rows: PX.floppy, ink: p.icon(.second), scale: 2.6)
                .background(Rectangle().fill(.white).padding(-2))
                .rotationEffect(.degrees(-10))
                .offset(x: -12, y: -140)
        }
    }
    private var ghostWords: some View {
        VStack(alignment: .trailing, spacing: 18) {
            Text("trust the process").font(script(26))
            Text("don't rush it").font(script(21)).padding(.trailing, 70)
        }
        .foregroundColor(p.sub.opacity(0.32))
        .padding(.trailing, 18).padding(.bottom, 24)
        .allowsHitTesting(false)
    }

    // MARK: 键帽 / 命令行

    private func keycap(radius: CGFloat, accent: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let edge = accent ? p.keyAccentEdge : p.keyEdge
        return shape.fill(p.panel)
            .overlay(shape.stroke(edge, style: StrokeStyle(lineWidth: 1.5, dash: night && !accent ? [2, 2] : [])))
            .background(shape.fill(accent ? p.keyAccentShadow : p.keyShadow).offset(y: 3.5))
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            termKey("esc", accent: true) {
                if session == "main" {
                    stopMainGeneration()
                } else {
                    sendKey("Escape")
                }
            }
            termKey("↑") { sendKey("Up") }
            termKey("↑↑") { sendKey("Up"); sendKey("Up") }
            termKey("↓") { sendKey("Down") }
            termKey("tab") { sendKey("Tab") }
            termKey("enter", accent: true, wide: true) { sendKey("Enter") }
            termKey("clear", wide: true) { sendKeys("clear", enter: true) }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    // SDK 没有按键可发，给两个真有用的：刷新、回到底部
    private var sdkToolbar: some View {
        HStack(spacing: 6) {
            termKey("刷新", accent: true) { capture() }
            termKey("清屏") { output = "" }
            Text(sdkSending ? "发送中…" : (workState == .thinking ? "陈璟在想…" : "session 空闲"))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(p.sub)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func termKey(_ label: String, accent: Bool = false, wide: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(label.unicodeScalars.allSatisfy(\.isASCII) ? pixel(10.5) : .system(size: 12, weight: .medium))
                .foregroundColor(accent ? p.accent : p.sub)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(keycap(radius: 7, accent: accent))
        }
        .buttonStyle(.plain)
        .layoutPriority(wide ? 1.4 : 1)
        .frame(minWidth: wide ? 52 : 36)
    }

    private var inputBar: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return HStack(spacing: 8) {
            Text(">_").font(pixel(12)).foregroundColor(p.promptMark)
            TextField("", text: $cmd, prompt: Text("命令").foregroundColor(p.sub))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(p.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($cmdFocused)
                .onSubmit(sendCmd)
            Button(action: sendCmd) {
                PixelIcon(rows: PX.enter, ink: p.icon(.onGo), scale: 1.8)
                    .frame(width: 38, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(p.go))
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(p.goShadow).offset(y: 3))
                    .opacity(cmd.isEmpty ? 0.6 : 1)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(p.panel, in: shape)
        .overlay(shape.stroke(p.inputEdge, style: StrokeStyle(lineWidth: 1.5, dash: night ? [4, 3] : [])))
        .background(shape.fill(night ? .clear : p.inputShadow).offset(y: 4))
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    // MARK: 网络

    private func startPoll() {
        pollTask = Task {
            capture()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                capture()
            }
        }
    }

    private func capture() {
        if mode == .sdk { captureSDK(); return }
        Task {
            var comps = URLComponents(url: AlcoveAPI.fullURL("/api/terminal/capture"),
                                      resolvingAgainstBaseURL: false)!
            var query = [URLQueryItem(name: "session", value: session),
                         URLQueryItem(name: "lines", value: "120"),
                         URLQueryItem(name: "columns", value: "80")]
            if mini { query.append(URLQueryItem(name: "clean", value: "1")) }
            comps.queryItems = query
            guard let (data, _) = try? await AlcoveAPI.session.data(from: comps.url!),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                workState = .disconnected
                return
            }
            if let content = obj["content"] as? String {
                output = content
                // /api/poll 是聊天页已经在用的 CC 实时状态，不靠终端文字猜。
                if let status = try? await AlcoveAPI.poll(since: nil, limit: 1) {
                    workState = status.isTyping ? .thinking : .resting
                } else {
                    workState = .disconnected
                }
            } else {
                workState = .disconnected
            }
        }
    }

    // SDK 终端：session 记录 + 正在进行的这一轮（实时流）拼在一起，两秒一刷跟 tmux 一个节奏
    private func captureSDK() {
        Task {
            guard let r = try? await AlcoveAPI.sdkTerminal(lines: mini ? 60 : 120) else {
                workState = .disconnected
                return
            }
            let busy = r.busy
            var text = r.content
            if busy, let live = try? await AlcoveAPI.liveStream(), live.active {
                // 正在跑的这轮 jsonl 还没落全，把实时流接在转轮后面，像 CLI 边想边打字那样
                var tail: [String] = []
                if !live.thinking.isEmpty {
                    tail.append("∴ " + live.thinking.replacingOccurrences(of: "\n", with: "\n  "))
                }
                for t in live.tools where !t.name.isEmpty { tail.append("⏺ " + t.name) }
                let say = live.say.isEmpty ? live.pendingSay : live.say
                if !say.isEmpty { tail.append("● " + say.replacingOccurrences(of: "\n", with: "\n  ")) }
                if !tail.isEmpty { text += tail.joined(separator: "\n") + "\n" }
            }
            output = text
            workState = busy ? .thinking : .resting
        }
    }

    private func sendCmd() {
        let c = cmd.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { return }
        cmd = ""
        if mode == .sdk {
            // SDK 没有命令行可敲：这里敲的就是一句话，走主聊天同一条路（会落进聊天页，跟 tmux 里打字一个效果）
            sdkSending = true
            Task {
                _ = try? await AlcoveAPI.send(text: c)
                sdkSending = false
                capture()
            }
            return
        }
        sendKeys(c, enter: true)
    }

    private func sendKeys(_ keys: String, enter: Bool) {
        post(["keys": keys, "session": session, "enter": enter])
    }

    private func sendKey(_ key: String) {
        post(["key": key, "session": session])
    }

    private func stopMainGeneration() {
        Task {
            _ = try? await AlcoveAPI.postRaw("/api/chat-stop", body: [:])
            try? await Task.sleep(nanoseconds: 200_000_000)
            capture()
        }
    }

    private func post(_ body: [String: Any]) {
        Task {
            var req = URLRequest(url: AlcoveAPI.fullURL("/api/terminal/send"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await AlcoveAPI.session.data(for: req)
            try? await Task.sleep(nanoseconds: 400_000_000)
            capture()
        }
    }
}

// MARK: - 1001 终端页换皮用的零件

/// 白天 / 黑夜两套颜色。白天＝薄荷粉淡紫纸面；黑夜＝她挑的 E：灰颗粒底＋泡泡糖粉
struct TermPalette {
    static let pixelFontID = "silkscreen"   // 后端字体架子上，hidden 不进她的字体栏
    static let scriptFontID = "pinyon"

    enum IconRole { case quiet, accent, second, onGo }

    let night: Bool
    let bg: Color, panel: Color, panel2: Color, line: Color
    let ink: Color, plain: Color, sub: Color, accent: Color, meText: Color
    let frame: Color, frameSoft: Color, frameShadow: Color, tabOff: Color
    let switchOn: Color, switchOnText: Color
    let lampOff: Color, lampThink: Color, lampRest: Color
    let ruleDots: Color, labelHead: Color, labelHeadText: Color
    let keyEdge: Color, keyShadow: Color, keyAccentEdge: Color, keyAccentShadow: Color
    let promptMark: Color, go: Color, goShadow: Color, inputEdge: Color, inputShadow: Color
    let pinkSoft: Color, lilacSoft: Color, mintSoft: Color
    let icons: [IconRole: [Character: Color]]

    func icon(_ r: IconRole) -> [Character: Color] { icons[r] ?? [:] }

    private static func h(_ s: String) -> Color { Color(hexString: s) ?? .gray }
    private static func inks(o: String, f: String, h hi: String, s: String, w: String) -> [Character: Color] {
        ["o": h(o), "f": h(f), "h": h(hi), "s": h(s), "w": h(w)]
    }

    static let day = TermPalette(
        night: false,
        bg: h("#F3F2F7"), panel: .white, panel2: h("#FBFAFF"), line: h("#C9BDEC"),
        ink: h("#5C566B"), plain: h("#6B6579"), sub: h("#A49EB2"), accent: h("#C46AAE"), meText: h("#C46AAE"),
        frame: h("#EAB3DC"), frameSoft: h("#EAB3DC"), frameShadow: h("#F8D3EC"), tabOff: h("#E4DDF6"),
        switchOn: h("#F8D3EC"), switchOnText: h("#C46AAE"),
        lampOff: h("#F19BB8"), lampThink: h("#B9A6F0"), lampRest: h("#86DCBF"),
        ruleDots: h("#C9BDEC"), labelHead: h("#E4DDF6"), labelHeadText: h("#8D7FC0"),
        keyEdge: h("#C9BDEC"), keyShadow: h("#C9BDEC"), keyAccentEdge: h("#EAB3DC"), keyAccentShadow: h("#EAB3DC"),
        promptMark: h("#3FAE88"), go: h("#A9F0D6"), goShadow: h("#86DCBF"), inputEdge: h("#86DCBF"), inputShadow: h("#A9F0D6"),
        pinkSoft: h("#F8D3EC"), lilacSoft: h("#E4DDF6"), mintSoft: h("#B6F2DC"),
        icons: [.quiet: inks(o: "#8D7FC0", f: "#E4DDF6", h: "#FFFFFF", s: "#C9BDEC", w: "#FFFFFF"),
                .accent: inks(o: "#D77FBD", f: "#F8D3EC", h: "#FFFFFF", s: "#EAB3DC", w: "#FFFFFF"),
                .second: inks(o: "#4FBF98", f: "#B6F2DC", h: "#FFFFFF", s: "#86DCBF", w: "#FFFFFF"),
                .onGo: inks(o: "#FFFFFF", f: "#FFFFFF", h: "#FFFFFF", s: "#FFFFFF", w: "#FFFFFF")])

    static let night = TermPalette(
        night: true,
        bg: h("#4B4A4F"), panel: h("#323136"), panel2: h("#3A3940"), line: h("#55525A"),
        ink: h("#ECE7EC"), plain: h("#D6D0D6"), sub: h("#A59FA8"), accent: h("#F6B4DC"), meText: h("#F6B4DC"),
        frame: h("#F6B4DC"), frameSoft: h("#B97AA2"), frameShadow: .clear, tabOff: h("#3A3940"),
        switchOn: h("#F6B4DC"), switchOnText: h("#323136"),
        lampOff: h("#F08AA8"), lampThink: h("#C9A8E0"), lampRest: h("#9FD8C2"),
        ruleDots: h("#F6B4DC"), labelHead: h("#4D3A47"), labelHeadText: h("#F6B4DC"),
        keyEdge: h("#B97AA2"), keyShadow: h("#3F343C"), keyAccentEdge: h("#F6B4DC"), keyAccentShadow: h("#4D3A47"),
        promptMark: h("#F6B4DC"), go: h("#F6B4DC"), goShadow: h("#B97AA2"), inputEdge: h("#F6B4DC"), inputShadow: .clear,
        pinkSoft: h("#4D3A47"), lilacSoft: h("#3A3940"), mintSoft: h("#3F343C"),
        icons: [.quiet: inks(o: "#A59FA8", f: "#3A3940", h: "#ECE7EC", s: "#55525A", w: "#ECE7EC"),
                .accent: inks(o: "#F6B4DC", f: "#4D3A47", h: "#ECE7EC", s: "#B97AA2", w: "#ECE7EC"),
                .second: inks(o: "#F6B4DC", f: "#3F343C", h: "#ECE7EC", s: "#8F7387", w: "#ECE7EC"),
                .onGo: inks(o: "#323136", f: "#323136", h: "#323136", s: "#323136", w: "#323136")])
}

/// 页面底：白天淡紫小格纸，黑夜胶片颗粒（都是开门时画一次的小图铺满）
private struct TermPaper: View {
    let p: TermPalette
    var body: some View {
        ZStack {
            p.bg
            Image(uiImage: p.night ? Self.grain : Self.checker)
                .resizable(resizingMode: .tile)
                .opacity(p.night ? 1 : 0.9)
        }
        .ignoresSafeArea()
    }

    static let checker: UIImage = {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: fmt).image { c in
            UIColor(red: 201/255, green: 189/255, blue: 236/255, alpha: 0.13).setFill()
            c.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            c.fill(CGRect(x: 8, y: 8, width: 8, height: 8))
        }
    }()

    static let grain: UIImage = {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        var rng = SystemRandomNumberGenerator()
        return UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128), format: fmt).image { c in
            for y in 0..<128 { for x in 0..<128 {
                let a = CGFloat(Double.random(in: 0...1, using: &rng))
                guard a > 0.45 else { continue }
                UIColor(white: a > 0.8 ? 1 : 0, alpha: (a - 0.45) * 0.42).setFill()
                c.fill(CGRect(x: x, y: y, width: 1, height: 1))
            } }
        }
    }()
}

/// 像素小图：一行一串字，o 描边 / f 填色 / h 高光 / s 阴影 / w 白，「.」是空
struct PixelIcon: View {
    let rows: [String]
    let ink: [Character: Color]
    var scale: CGFloat = 1.4

    var body: some View {
        let w = CGFloat(rows.first?.count ?? 0), h = CGFloat(rows.count)
        Canvas { ctx, _ in
            for (y, row) in rows.enumerated() {
                for (x, c) in row.enumerated() where c != "." {
                    let r = CGRect(x: CGFloat(x) * scale, y: CGFloat(y) * scale, width: scale + 0.02, height: scale + 0.02)
                    ctx.fill(Path(r), with: .color(ink[c] ?? ink["f"] ?? .gray))
                }
            }
        }
        .frame(width: w * scale, height: h * scale)
        .allowsHitTesting(false)
    }
}

enum PX {
    static let crt = [".ooooooooo.", "offfffffffo", "ofsssssssfo", "ofsssssssfo", "ofsshssssfo", "ofsssssssfo",
                      "offfffffffo", ".ooooooooo.", "....ofo....", "..ooooooo.."]
    static let floppy = ["oooooooo..", "ofhhhhfoo.", "ofhhhhfoo.", "offffffffo", "offffffffo", "ofwwwwwwfo",
                         "ofwsswssfo", "ofwwwwwwfo", "oooooooooo"]
    static let cursor = ["o......", "oo.....", "ofo....", "offo...", "offfo..", "offffo.", "offfffo", "offoooo",
                         "oo.ofo.", "o..ofo.", "....o.."]
    static let hourglass = ["ooooooo", "offfffo", ".ohhho.", "..oho..", "...o...", "..ofo..", ".offfo.", "ohhhhho", "ooooooo"]
    static let bolt = ["...oo", "..ofo", ".ofo.", "offoo", "ooffo", "..ofo", ".ofo.", ".oo..", "o...."]
    static let bubble = [".ooooooo.", "offfffffo", "ofhfhfhfo", "offfffffo", ".oofoooo.", "..oo.....", ".o......."]
    static let folder = ["oooo......", "offfoooooo", "offffffffo", "offffffffo", "offffffffo", "oooooooooo"]
    static let enter = [".......ooo", "...o...ofo", "..ofo..ofo", ".offoooofo", "offfffffo.", ".offoooo..", "..ofo.....", "...o......"]
}

/// 白天贴纸：像素光盘（一圈圈粉 / 淡紫 / 薄荷 / 白，中间一个孔）
private struct PixelDisc: View {
    let colors: [Color]
    let rim: Color
    var body: some View {
        Canvas { ctx, size in
            let n = 15.0, c = 7.0, s = size.width / n
            for y in 0..<15 { for x in 0..<15 {
                let d = hypot(Double(x) - c, Double(y) - c)
                guard d <= 7.3, !(d < 1.4) else { continue }
                let col: Color
                if d > 6.4 || d < 2.4 { col = rim }
                else {
                    let i = Int((atan2(Double(y) - c, Double(x) - c) + .pi) / (.pi / 3) + d / 2) % colors.count
                    col = colors[i]
                }
                ctx.fill(Path(CGRect(x: Double(x) * s, y: Double(y) * s, width: s + 0.02, height: s + 0.02)), with: .color(col))
            } }
        }
        .allowsHitTesting(false)
    }
}

/// 黑夜贴纸：半调像素花（点越靠花心越大）＋点线花茎，照她递的参考
private struct HalftoneFlower: View {
    let pink: Color
    let big: Bool
    var body: some View {
        Canvas { ctx, size in
            let W = Double(size.width), H = Double(size.height)
            let flowers: [(Double, Double, Double)] = big
                ? [(W * 0.55, H * 0.28, W * 0.33), (W * 0.25, H * 0.62, W * 0.17)]
                : [(W * 0.5, H * 0.42, W * 0.36)]
            let step = 3.5
            var y = 0.0
            while y < H {
                var x = 0.0
                while x < W {
                    var v = 0.0
                    for (cx, cy, r) in flowers {
                        let dx = x - cx, dy = y - cy, a = atan2(dy, dx), d = hypot(dx, dy)
                        let pr = r * (0.55 + 0.45 * abs(cos(a * 2.5)))
                        if d < pr { v = max(v, 1 - d / pr * 0.75) }
                    }
                    if v > 0 {
                        let rr = max(0.55, 1.8 * v)
                        ctx.fill(Path(ellipseIn: CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2)), with: .color(pink))
                    }
                    x += step
                }
                y += step
            }
            for (cx, cy, r) in flowers {
                let rr = r * 0.22
                ctx.fill(Path(ellipseIn: CGRect(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2)),
                         with: .color(Color(hexString: "#FFE3F3") ?? .white))
            }
            if big {
                var t = 0.0
                while t < 1 {
                    let x = W * 0.55 - t * W * 0.25 + sin(t * 6) * 3, y = H * 0.45 + t * H * 0.55
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(pink))
                    t += 0.035
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// tmux 抓下来的一行：按开头的记号分类上色（她 ❯ / 他 ● ⏺ / 工具结果 ⎿ / 想了多久 ✻ / 横线 ───）
struct TermLine {
    enum Kind { case me, meMore, him, himMore, tool, thought, rule, plain }
    let kind: Kind
    let text: String
}

enum TermParse {
    private static func isRule(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.count >= 8 && t.allSatisfy { $0 == "─" || $0 == "━" }
    }
    private static func strip(_ t: String) -> String {
        String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    /// 最后一道横线下面不超过 6 行的算状态行（模型 / 上下文 / 用量 / 保活），收进软盘标签；其余是正文
    static func split(_ output: String) -> (body: [TermLine], status: [String]) {
        var lines = output.components(separatedBy: "\n")
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        var status: [String] = []
        if let last = lines.lastIndex(where: isRule), lines.count - last - 1 <= 6, last < lines.count - 1 {
            status = lines[(last + 1)...].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            lines = Array(lines[...last])
        }
        var out: [TermLine] = []
        var kind: TermLine.Kind = .plain
        for raw in lines {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if isRule(raw) {
                if out.last?.kind != .rule { out.append(TermLine(kind: .rule, text: "")) }
                kind = .plain
                continue
            }
            if t.hasPrefix("❯") {
                kind = .me; out.append(TermLine(kind: .me, text: strip(t))); continue
            }
            if t.hasPrefix("●") || t.hasPrefix("⏺") {
                kind = .him; out.append(TermLine(kind: .him, text: strip(t))); continue
            }
            if t.hasPrefix("⎿") {
                out.append(TermLine(kind: .tool, text: "▸ " + strip(t))); continue
            }
            if (t.hasPrefix("✻") || t.hasPrefix("✽") || t.hasPrefix("✶") || t.hasPrefix("* ")) && t.contains(" for ") {
                kind = .plain; out.append(TermLine(kind: .thought, text: strip(t))); continue
            }
            if t.isEmpty { out.append(TermLine(kind: .plain, text: "")); continue }
            switch kind {
            case .me: out.append(TermLine(kind: .meMore, text: t))
            case .him: out.append(TermLine(kind: .himMore, text: t))
            default: out.append(TermLine(kind: .plain, text: raw))
            }
        }
        return (out, status)
    }
}
