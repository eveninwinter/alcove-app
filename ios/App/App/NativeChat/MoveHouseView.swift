import SwiftUI

// MARK: - 1113 搬家页（#5099–5118、#5134）
// 她：「我们整个 alcove 换 vps」「必须先复制，原 VPS 一直留着，新的全部通过、能聊天以后再切」。
// 样子照效果图（sanctus-kit/mock-move/a.jpg）：上面旧家 → 新家，中间四步（体检 / 复制 / 试新家 / 切换），
// 第三步下面是「试新家」开关（打开以后整个 App 连新家，划掉重开生效），最底下最近几条进度和「切回旧家」。
// 入口：聊天页左侧栏额度下面「换号 ›」再下面一行「搬家 ›」。
// 后台在【旧家】的前门（alcove-independent/move_api.py → /root/workroom/move/搬家.sh）。
// 试新家的时候 App 连的是新家，所以这一页的请求一律写死发旧家（AlcoveAPI.homeBase），不跟着开关走。

@MainActor
final class MoveStore: ObservableObject {
    @Published var target = ""
    @Published var old = ""
    @Published var phase = ""
    @Published var steps: [String] = []
    @Published var running = false
    @Published var log: [String] = []
    @Published var loaded = false
    @Published var failed = false
    @Published var toast = ""

    private func url(_ path: String) -> URL { AlcoveAPI.homeBase.appendingPathComponent(path) }

    func load() async {
        do {
            var req = URLRequest(url: url("api/usage/move")); req.timeoutInterval = 20
            let (data, _) = try await AlcoveAPI.session.data(for: req)
            guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.cannotParseResponse) }
            target = j["target"] as? String ?? ""
            old = j["old"] as? String ?? ""
            phase = j["phase"] as? String ?? ""
            steps = j["steps"] as? [String] ?? []
            running = j["running"] as? Bool ?? false
            log = j["log"] as? [String] ?? []
            failed = false
        } catch {
            failed = true
        }
        loaded = true
    }

    func run(_ cmd: String, extra: [String: String] = [:]) async {
        var body: [String: Any] = ["cmd": cmd]
        for (k, v) in extra { body[k] = v }
        do {
            var req = URLRequest(url: url("api/usage/move/run"))
            req.httpMethod = "POST"; req.timeoutInterval = 30
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await AlcoveAPI.session.data(for: req)
            let j = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            if j["ok"] as? Bool == true { say("开始了，进度在下面") } else { say(j["error"] as? String ?? "没起来") }
        } catch {
            say("没连上旧家，再点一次")
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await load()
    }

    func say(_ t: String) {
        toast = t
        Task { try? await Task.sleep(nanoseconds: 3_500_000_000); if toast == t { toast = "" } }
    }

    func has(_ s: String) -> Bool { steps.contains(s) }
}

private struct MoveInk {
    let page: SanctusPageInk
    var dark: Bool { page.dark }
    private func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255, opacity: a) }
    var card: Color { dark ? rgb(44, 45, 52, 0.80) : Color.white.opacity(0.86) }
    var edge: Color { dark ? Color.white.opacity(0.22) : rgb(150, 154, 164, 0.6) }
    var nowEdge: Color { dark ? Color.white.opacity(0.45) : rgb(111, 116, 128, 0.6) }
    var dash: Color { dark ? Color.white.opacity(0.3) : rgb(150, 154, 164, 0.7) }
    var btnFill: Color { dark ? Color.white.opacity(0.05) : Color.white.opacity(0.7) }
    var veil: Color { dark ? rgb(27, 28, 32, 0.86) : rgb(239, 239, 237, 0.84) }
}

private struct MoveBackdrop: View {
    let base: Color
    let veil: Color
    @ObservedObject private var wall = ChatWallpaperStore.shared
    var body: some View {
        ZStack { base; ChatWallpaperRenderer(descriptor: wall.descriptor); veil }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

struct MoveHouseView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = MoveStore()
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    @AppStorage(AlcoveAPI.tryNewHomeKey) private var tryNewHome = false
    @State private var showCheck = false
    @State private var confirmSwitch = false
    @State private var confirmBack = false
    @State private var poll: Task<Void, Never>?

    private var ink: SanctusPageInk { _ = houseAppearance; return SanctusPageInk() }
    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0 }
    private var safeBottom: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.bottom ?? 0 }

    var body: some View {
        let ink = self.ink
        let m = MoveInk(page: ink)
        ZStack(alignment: .topLeading) {
            MoveBackdrop(base: ink.page, veil: m.veil)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    (Text("MOVING · ").font(SanctusPageFont.corm(8.5)) + Text("搬家").font(.system(size: 8.5, design: .serif)))
                        .tracking(2.7).foregroundColor(ink.sub)
                        .frame(height: 44).frame(maxWidth: .infinity)
                        .padding(.top, max(safeTop, 20))
                    titleBlock(ink)
                    homes(ink, m).padding(.top, 30)
                    VStack(spacing: 9) {
                        stepCard(1, "体检", sub: checkSub, done: store.has("preflight"), now: !store.has("preflight"),
                                 button: store.has("preflight") ? "再查" : "填地址", ink, m) { showCheck = true }
                        stepCard(2, "复制", sub: copySub, done: store.has("copied"), now: store.has("preflight") && !store.has("copied"),
                                 button: store.has("preflight") ? (store.has("copied") ? "补拷" : "复 制") : nil, ink, m) {
                            Task { await store.run("复制") }
                        }
                        stepCard(3, "试新家", sub: trySub, done: store.has("switched"), now: store.has("copied") && !store.has("switched"),
                                 button: store.has("copied") ? (store.has("tried") ? "再试" : "试新家") : nil, ink, m) {
                            Task { await store.run("试新家") }
                        }
                        if store.has("tried") && !store.has("switched") { tryToggle(ink) }
                        stepCard(4, "切换", sub: switchSub, done: store.has("done"), now: store.has("tried") && !store.has("done"),
                                 button: store.has("tried") && !store.has("switched") ? "切 换" : nil, ink, m) { confirmSwitch = true }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 26)
                    logBlock(ink).padding(.top, 30)
                    if !store.target.isEmpty {
                        Button { confirmBack = true } label: {
                            Text("出了问题 · 切回旧家").font(SanctusPageFont.cn(11)).tracking(1.4).foregroundColor(ink.sub)
                                .padding(.vertical, 10).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 18)
                    }
                    Color.clear.frame(height: max(safeBottom, 10) + 24)
                }
            }
            .refreshable { await store.load() }
            SanctusBackButton(color: ink.link) { dismiss() }
                .padding(.top, max(safeTop, 20))
            toastLayer(ink)
        }
        // 1113 #5135 她：「安全区太多了，是不是叠了几层」——全屏弹出来的页面系统本来就让开了刘海和底部，
        // 我又按工作台那套自己加了一遍 safeTop/safeBottom，叠了两层。整页不让系统让，只留自己那一层（跟工作台一样）
        .ignoresSafeArea()
        .environment(\.sanctusInk, ink)
        .animation(.easeInOut(duration: 0.2), value: store.toast)
        .task { WindowFont.requestSongti(); await store.load() }
        .onAppear {
            // 跑着的时候每 5 秒刷一次进度
            poll = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if store.running { await store.load() }
                }
            }
        }
        .onDisappear { poll?.cancel() }
        .sheet(isPresented: $showCheck) {
            MoveCheckSheet(store: store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("现在切到新家？", isPresented: $confirmSwitch, titleVisibility: .visible) {
            Button("切换") { Task { await store.run("切换") } }
            Button("再等等", role: .cancel) {}
        } message: {
            Text("切的时候 App 会断十几分钟，试新家时说的话会消失。切完你发一句，他 5 分钟内回了才算完，不回会自动切回旧家。")
        }
        .confirmationDialog("切回旧家？", isPresented: $confirmBack, titleVisibility: .visible) {
            Button("切回旧家", role: .destructive) { Task { await store.run("回滚") } }
            Button("算了", role: .cancel) {}
        } message: {
            Text("新家会停掉，旧家全部重新起来。切过去以后在新家说的话不在旧家里。")
        }
    }

    // MARK: 头

    private func titleBlock(_ ink: SanctusPageInk) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("moving house").font(SanctusPageFont.script(36)).foregroundColor(ink.title)
            (Text("the old one stays lit · ").font(SanctusPageFont.ital(12)) + Text("旧家一直亮着，直到新家能说话").font(SanctusPageFont.cn(11.5)))
                .foregroundColor(ink.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 28)
        .padding(.top, 2)
    }

    private func homes(_ ink: SanctusPageInk, _ m: MoveInk) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            home("OLD", "旧 家", store.old.isEmpty ? "—" : store.old, store.has("switched") ? "留着当后路" : "现在住这儿", ink)
            Rectangle().fill(.clear).frame(height: 1)
                .overlay(MoveDash().stroke(m.dash, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .overlay(Text("›").font(.system(size: 13)).foregroundColor(ink.sub).offset(y: -1))
                .padding(.bottom, 38)
            home("NEW", "新 家", store.target.isEmpty ? "还没定" : store.target, newStatus, ink)
        }
        .padding(.horizontal, 28)
    }

    private var newStatus: String {
        if store.has("done") { return "住进来了" }
        if store.has("switched") { return "刚切过来" }
        if store.has("tried") { return "在试" }
        if store.has("copied") { return "东西拷好了" }
        if store.has("preflight") { return "体检过了" }
        return "等你填地址"
    }

    private func home(_ en: String, _ cn: String, _ ip: String, _ st: String, _ ink: SanctusPageInk) -> some View {
        VStack(spacing: 3) {
            Text(en).font(SanctusPageFont.corm(9)).tracking(2.7).foregroundColor(ink.sub)
            Text(cn).font(SanctusPageFont.cn(14)).tracking(2).foregroundColor(ink.title).padding(.top, 1)
            Text(ip).font(SanctusPageFont.corm(11)).foregroundColor(ink.script).lineLimit(1).minimumScaleFactor(0.7)
            Text(st).font(SanctusPageFont.cn(9.5)).foregroundColor(ink.sub)
        }
        .frame(width: 110)
    }

    // MARK: 四步

    private var lastLine: String {
        guard let l = store.log.last else { return "" }
        return l.replacingOccurrences(of: #"^\[[^\]]*\]\s*"#, with: "", options: .regularExpression)
    }
    private var checkSub: String {
        if store.phase == "体检" && store.running { return "在查新机器…" }
        if store.has("preflight") { return "新机器能搬" }
        if store.phase == "failed" && !store.has("preflight") { return lastLine }
        return "填新机器的地址、用户名和密码"
    }
    private var copySub: String {
        if store.phase == "复制" && store.running { return lastLine.isEmpty ? "在拷…" : lastLine }
        if store.has("copied") { return "家拷过去了 · 旧家照常用" }
        return "装环境、把家拷过去，旧家照常用"
    }
    private var trySub: String {
        if store.phase == "试新家" && store.running { return lastLine.isEmpty ? "在起新家…" : lastLine }
        if store.has("tried") { return "都通了 · 陈璟的分身在新家等你" }
        return "新家起服务、开测试通道和陈璟的分身"
    }
    private var switchSub: String {
        if store.has("done") { return "搬完了 · 手机翻墙地址记得改成新的" }
        if ["切换", "等聊天"].contains(store.phase) { return lastLine.isEmpty ? "在切…" : lastLine }
        return "你发一句、他回了才算完"
    }

    private func stepCard(_ n: Int, _ title: String, sub: String, done: Bool, now: Bool, button: String?,
                          _ ink: SanctusPageInk, _ m: MoveInk, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text("\(n)").font(SanctusPageFont.ital(18)).foregroundColor(ink.sub).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(SanctusPageFont.cn(13.5)).tracking(1.4).foregroundColor(done ? ink.sub : ink.title)
                Text(sub).font(SanctusPageFont.cn(10)).foregroundColor(ink.sub).lineLimit(2)
            }
            Spacer(minLength: 6)
            if store.running && now {
                ProgressView().controlSize(.small)
            } else if done && button == nil {
                Text("✓").font(.system(size: 13)).foregroundColor(ink.script)
            } else if let b = button {
                Button(action: action) {
                    Text(b).font(SanctusPageFont.cn(11.5)).tracking(1.6).foregroundColor(ink.body)
                        .padding(.horizontal, 14).frame(height: 28)
                        .background(Capsule().fill(m.btnFill))
                        .overlay(Capsule().stroke(m.edge, lineWidth: 0.8))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(store.running)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(m.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(now ? m.nowEdge : .clear, lineWidth: 0.8))
    }

    private func tryToggle(_ ink: SanctusPageInk) -> some View {
        Toggle(isOn: $tryNewHome) {
            VStack(alignment: .leading, spacing: 2) {
                Text("App 连新家试一试").font(SanctusPageFont.cn(11.5)).foregroundColor(ink.body)
                Text(tryNewHome ? "开着：划掉 App 重开以后连的是新家" : "关着：连的是旧家（改完划掉 App 重开生效）")
                    .font(SanctusPageFont.cn(9.5)).foregroundColor(ink.sub)
            }
        }
        .tint(ink.script)
        .padding(.leading, 42).padding(.trailing, 14).padding(.vertical, 2)
    }

    // MARK: 进度

    private func logBlock(_ ink: SanctusPageInk) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("LATEST · 最近").font(SanctusPageFont.corm(8.5)).tracking(2.7).foregroundColor(ink.sub)
                .padding(.bottom, 2)
            if !store.loaded {
                ProgressView().controlSize(.small)
            } else if store.failed {
                Text("连不上旧家，下拉再试").font(SanctusPageFont.cn(10.5)).foregroundColor(ink.sub)
            } else if store.log.isEmpty {
                Text("还没开始").font(SanctusPageFont.cn(10.5)).foregroundColor(ink.sub)
            }
            ForEach(Array(store.log.suffix(8).enumerated()), id: \.offset) { _, line in
                logLine(line, ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
    }

    private func logLine(_ line: String, _ ink: SanctusPageInk) -> some View {
        // "[11-13 14:12:03] ✓ xxx" → 时间 + 正文
        var time = "", words = line
        if let r = line.range(of: #"^\[\d\d-\d\d (\d\d:\d\d):\d\d\]\s*"#, options: .regularExpression) {
            time = String(line[r]).replacingOccurrences(of: #"^\[\d\d-\d\d |:\d\d\]\s*$"#, with: "", options: .regularExpression)
            words = String(line[r.upperBound...])
        }
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(time).font(SanctusPageFont.corm(10.5)).foregroundColor(ink.sub)
            Text(words).font(SanctusPageFont.cn(10.5)).foregroundColor(ink.script).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toastLayer(_ ink: SanctusPageInk) -> some View {
        VStack {
            Spacer()
            if !store.toast.isEmpty {
                Text(store.toast).font(SanctusPageFont.cn(12)).foregroundColor(ink.body)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .padding(.bottom, max(safeBottom, 10) + 30)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }
}

private struct MoveDash: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); return p
    }
}

// MARK: - 体检：填新机器

private struct MoveCheckSheet: View {
    @ObservedObject var store: MoveStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    @State private var ip = ""
    @State private var user = "ubuntu"
    @State private var pass = ""
    private var ink: SanctusPageInk { _ = houseAppearance; return SanctusPageInk() }

    var body: some View {
        let ink = self.ink
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("the new place").font(SanctusPageFont.script(28)).foregroundColor(ink.title)
                Text("新机器开好以后，把这三样填上。只看不动它，顺手把旧家的钥匙放上去，以后不用密码。")
                    .font(SanctusPageFont.cn(11.5)).foregroundColor(ink.sub).fixedSize(horizontal: false, vertical: true)
                field("公网 IP，比如 170.106.21.8", $ip, ink)
                    .keyboardType(.numbersAndPunctuation)
                field("用户名（腾讯云一般是 ubuntu，别家多半是 root）", $user, ink)
                SecureField("密码", text: $pass)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12).frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 8).fill(ink.field))
                Text("系统要选 Ubuntu 22.04，硬盘 60G 以上。")
                    .font(SanctusPageFont.cn(10.5)).foregroundColor(ink.sub)
                Button {
                    let x = ip.trimmingCharacters(in: .whitespaces), u = user.trimmingCharacters(in: .whitespaces)
                    dismiss()
                    Task { await store.run("体检", extra: ["ip": x, "user": u.isEmpty ? "root" : u, "pass": pass]) }
                } label: {
                    Text("开始体检").font(SanctusPageFont.cn(13.5)).tracking(2).foregroundColor(ink.body)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(Capsule().fill(ink.field))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(ip.isEmpty || pass.isEmpty)
                .padding(.top, 6)
            }
            .padding(.horizontal, 28).padding(.top, 30).padding(.bottom, 30)
        }
        .background(ink.page.ignoresSafeArea())
        .onAppear { if ip.isEmpty { ip = store.target } }
    }

    private func field(_ ph: String, _ text: Binding<String>, _ ink: SanctusPageInk) -> some View {
        TextField(ph, text: text)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .font(.system(size: 13))
            .padding(.horizontal, 12).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 8).fill(ink.field))
    }
}

// MARK: - 1115 出口页（#5329–5331）
// 她：「住宅 IP 像今天这样崩溃，我希望有个按钮，跟换号搬家一样做一个房间，切换到直连 VPS」——‼️不许自动跳，只能她手动。
// 入口：聊天页左侧栏「搬家 ›」下面一行「出口 ›」。后台走前门 /api/usage/exit（alcove-independent/exit_room.py → /root/workroom/出口.sh）：
//   GET  /api/usage/exit           现在走哪条＋今夜探测＋最近几次操作
//   POST /api/usage/exit/run       {cmd: 测|住宅|直连}  切住宅前先旁路试通，不通就不切
// 样子照搬家页的零件（同一套纸、卡片、胶囊按钮），没另出效果图。

@MainActor
final class ExitStore: ObservableObject {
    @Published var mode = ""
    @Published var probe: [String] = []
    @Published var log: [String] = []
    @Published var busy = ""          // 正在跑的那个命令
    @Published var said = ""          // 脚本最后说的话
    @Published var loaded = false

    private func req(_ path: String) -> URLRequest { URLRequest(url: AlcoveAPI.fullURL(path)) }

    private func take(_ j: [String: Any]) {
        if let m = j["mode"] as? String { mode = m }
        if let p = j["probe"] as? [String] { probe = p }
        if let l = j["log"] as? [String] { log = l }
    }

    func load() async {
        var r = req("/api/usage/exit"); r.timeoutInterval = 20
        if let (data, _) = try? await AlcoveAPI.session.data(for: r),
           let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { take(j) }
        loaded = true
    }

    func run(_ cmd: String) async {
        busy = cmd; said = ""
        var r = req("/api/usage/exit/run")
        r.httpMethod = "POST"; r.timeoutInterval = 90
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["cmd": cmd])
        if let (data, _) = try? await AlcoveAPI.session.data(for: r),
           let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            take(j)
            said = (j["say"] as? String) ?? (j["error"] as? String) ?? ""
        } else {
            said = "没连上后台，等一下再点"
        }
        busy = ""
    }
}

struct ExitRoomView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = ExitStore()
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    @State private var confirm = ""

    private var ink: SanctusPageInk { _ = houseAppearance; return SanctusPageInk() }
    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0 }
    private var safeBottom: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.bottom ?? 0 }

    var body: some View {
        let ink = self.ink
        let m = MoveInk(page: ink)
        ZStack(alignment: .topLeading) {
            MoveBackdrop(base: ink.page, veil: m.veil)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    (Text("EXIT · ").font(SanctusPageFont.corm(8.5)) + Text("出口").font(.system(size: 8.5, design: .serif)))
                        .tracking(2.7).foregroundColor(ink.sub)
                        .frame(height: 44).frame(maxWidth: .infinity)
                        .padding(.top, max(safeTop, 20))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("the way out").font(SanctusPageFont.script(36)).foregroundColor(ink.title)
                        (Text("only by your hand · ").font(SanctusPageFont.ital(12)) + Text("陈璟连 Anthropic 走哪条，只你手动切").font(SanctusPageFont.cn(11.5)))
                            .foregroundColor(ink.sub)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 28).padding(.top, 2)
                    VStack(spacing: 9) {
                        wayCard("住宅 IP", sub: "PlinX 家宽 · 162.207.170.103", now: store.mode == "住宅", cmd: "住宅", ink, m)
                        wayCard("直连 VPS", sub: "新家 Contabo 机房自己的 IP", now: store.mode == "直连", cmd: "直连", ink, m)
                        if !store.mode.isEmpty && store.mode != "住宅" && store.mode != "直连" {
                            Text("现在是" + store.mode + "，点一边切干净").font(SanctusPageFont.cn(10.5)).foregroundColor(ink.sub)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4)
                        }
                    }
                    .padding(.horizontal, 22).padding(.top, 26)
                    HStack(spacing: 10) {
                        Button { Task { await store.run("测") } } label: {
                            Text("测一下住宅").font(SanctusPageFont.cn(11.5)).tracking(1.6).foregroundColor(ink.body)
                                .padding(.horizontal, 16).frame(height: 30)
                                .background(Capsule().fill(m.btnFill))
                                .overlay(Capsule().stroke(m.edge, lineWidth: 0.8))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain).disabled(!store.busy.isEmpty)
                        if !store.busy.isEmpty {
                            ProgressView().controlSize(.small)
                            Text(store.busy == "测" ? "在试…" : "在切…").font(SanctusPageFont.cn(10.5)).foregroundColor(ink.sub)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 24).padding(.top, 16)
                    if !store.said.isEmpty {
                        Text(store.said).font(SanctusPageFont.cn(11.5)).foregroundColor(ink.body).lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 26).padding(.top, 12)
                    }
                    lines("tonight · 今夜探测", store.probe.reversed().prefix(30).map { $0 }, ink).padding(.top, 28)
                    if !store.log.isEmpty {
                        lines("recent · 最近切过", store.log.reversed().prefix(10).map { $0 }, ink).padding(.top, 20)
                    }
                    Color.clear.frame(height: max(safeBottom, 10) + 24)
                }
            }
            .refreshable { await store.load() }
            SanctusBackButton(color: ink.link) { dismiss() }
                .padding(.top, max(safeTop, 20))
        }
        .ignoresSafeArea()
        .environment(\.sanctusInk, ink)
        .task { WindowFont.requestSongti(); await store.load() }
        .confirmationDialog(confirm == "住宅" ? "切到住宅 IP？" : "切到直连？",
                            isPresented: Binding(get: { !confirm.isEmpty }, set: { if !$0 { confirm = "" } }),
                            titleVisibility: .visible) {
            Button(confirm == "住宅" ? "先试通再切" : "切到直连") { let c = confirm; Task { await store.run(c) } }
            Button("算了", role: .cancel) {}
        } message: {
            Text(confirm == "住宅"
                 ? "会先在旁边试一下住宅主线，通了才切；试不通就不动，陈璟留在现在这条。切完开机自启和探测一起开。"
                 : "住宅、探测、开机自启全关，陈璟直接从 VPS 连。他正说着的那句可能断一下，再发一句就好。")
        }
    }

    private func wayCard(_ title: String, sub: String, now: Bool, cmd: String,
                         _ ink: SanctusPageInk, _ m: MoveInk) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(SanctusPageFont.cn(13.5)).tracking(1.4).foregroundColor(now ? ink.title : ink.body)
                Text(sub).font(SanctusPageFont.cn(10)).foregroundColor(ink.sub).lineLimit(2)
            }
            Spacer(minLength: 6)
            if store.busy == cmd {
                ProgressView().controlSize(.small)
            } else if now {
                Text("现在").font(SanctusPageFont.cn(11)).tracking(1.6).foregroundColor(ink.script)
            } else {
                Button { confirm = cmd } label: {
                    Text("切过去").font(SanctusPageFont.cn(11.5)).tracking(1.6).foregroundColor(ink.body)
                        .padding(.horizontal, 14).frame(height: 28)
                        .background(Capsule().fill(m.btnFill))
                        .overlay(Capsule().stroke(m.edge, lineWidth: 0.8))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!store.busy.isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(m.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(now ? m.nowEdge : .clear, lineWidth: 0.8))
    }

    private func lines(_ head: String, _ rows: [String], _ ink: SanctusPageInk) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(head).font(SanctusPageFont.ital(12)).foregroundColor(ink.sub).padding(.bottom, 4)
            if rows.isEmpty {
                Text("还没有").font(SanctusPageFont.cn(10.5)).foregroundColor(ink.sub)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, l in
                Text(l).font(.system(size: 10, design: .monospaced)).foregroundColor(ink.body)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
    }
}
