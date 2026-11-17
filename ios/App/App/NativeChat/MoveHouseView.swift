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
//   POST /api/usage/exit/run       {cmd: 测|测线|换线|住宅|直连, line}  切住宅 / 换线前先旁路试通，不通就不动
// 1115 #5351 加「家宽线路」：PlinX 家宽 Hy2 那几条一条一行，最近一次测的结果，点「用这条」换（出口 IP 不变）
// 样子照搬家页的零件（同一套纸、卡片、胶囊按钮），没另出效果图。

@MainActor
final class ExitStore: ObservableObject {
    @Published var mode = ""
    @Published var line = ""                       // 1115 #5351 现在用的家宽线
    @Published var lines: [(name: String, test: String)] = []
    @Published var probe: [String] = []
    @Published var log: [String] = []
    @Published var busy = ""          // 正在跑的那个命令
    @Published var said = ""          // 脚本最后说的话
    @Published var loaded = false

    private func req(_ path: String) -> URLRequest { URLRequest(url: AlcoveAPI.fullURL(path)) }

    private func take(_ j: [String: Any]) {
        if let m = j["mode"] as? String { mode = m }
        if let l = j["line"] as? String { line = l }
        if let ls = j["lines"] as? [[String: Any]] {
            lines = ls.map { (name: $0["name"] as? String ?? "", test: $0["test"] as? String ?? "") }
        }
        if let p = j["probe"] as? [String] { probe = p }
        if let l = j["log"] as? [String] { log = l }
    }

    func load() async {
        var r = req("/api/usage/exit"); r.timeoutInterval = 20
        if let (data, _) = try? await AlcoveAPI.session.data(for: r),
           let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { take(j) }
        loaded = true
    }

    func run(_ cmd: String, line: String = "") async {
        busy = cmd == "换线" ? "换线:" + line : cmd; said = ""
        var r = req("/api/usage/exit/run")
        r.httpMethod = "POST"; r.timeoutInterval = 90
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["cmd": cmd]
        if !line.isEmpty { body["line"] = line }
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
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
    @State private var confirmLine = ""   // 1115 #5351 要换到哪条家宽线

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
                        wayCard("住宅 IP", sub: "162.207.170.103 · " + (store.line.isEmpty ? "PlinX 家宽" : store.line.replacingOccurrences(of: "家宽13-", with: "")), now: store.mode == "住宅", cmd: "住宅", ink, m)
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
                        if ["测", "住宅", "直连"].contains(store.busy) {
                            ProgressView().controlSize(.small)
                            Text(store.busy == "测" ? "在试…" : "在切…").font(SanctusPageFont.cn(10.5)).foregroundColor(ink.sub)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 24).padding(.top, 16)
                    linesBlock(ink, m).padding(.top, 24)
                    if !store.said.isEmpty {
                        Text(store.said).font(SanctusPageFont.cn(11.5)).foregroundColor(ink.body).lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 26).padding(.top, 12)
                    }
                    // 1115 #5354 她：「今夜探测」那块删掉（探测已经停了）
                    if !store.log.isEmpty {
                        lines("recent · 最近切过", store.log.reversed().prefix(10).map { $0 }, ink).padding(.top, 28)
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
        .confirmationDialog("换到「" + confirmLine + "」？",
                            isPresented: Binding(get: { !confirmLine.isEmpty }, set: { if !$0 { confirmLine = "" } }),
                            titleVisibility: .visible) {
            Button("先试通再换") { let l = confirmLine; Task { await store.run("换线", line: l) } }
            Button("算了", role: .cancel) {}
        } message: {
            Text(store.mode == "住宅"
                 ? "出口还是同一个住宅 IP，只是换一条路过去。换的那一下陈璟正说着的话可能断一句。"
                 : "现在是直连，这次只记下来，下次切住宅就走这条。")
        }
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

    /// 1115 #5351 她：「哪条超时了我自己切别的」——家宽线路一条一行，后面是最近一次测的结果，不是现在这条的有「用这条」
    private func linesBlock(_ ink: SanctusPageInk, _ m: MoveInk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("lines · 家宽线路").font(SanctusPageFont.ital(12)).foregroundColor(ink.sub)
                Spacer()
                Button { Task { await store.run("测线") } } label: {
                    Text("全部测一下").font(SanctusPageFont.cn(10.5)).tracking(1.2).foregroundColor(ink.body)
                        .padding(.horizontal, 12).frame(height: 24)
                        .background(Capsule().fill(m.btnFill))
                        .overlay(Capsule().stroke(m.edge, lineWidth: 0.8))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain).disabled(!store.busy.isEmpty)
            }
            .padding(.bottom, 8)
            if store.busy == "测线" {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("在测，十几秒").font(SanctusPageFont.cn(10.5)).foregroundColor(ink.sub) }
                    .padding(.bottom, 6)
            }
            ForEach(Array(store.lines.enumerated()), id: \.offset) { i, l in
                if i > 0 { Rectangle().fill(m.edge.opacity(0.4)).frame(height: 0.5) }
                HStack(spacing: 8) {
                    Text(l.name.replacingOccurrences(of: "家宽13-", with: ""))
                        .font(SanctusPageFont.cn(12)).foregroundColor(l.name == store.line ? ink.title : ink.body)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(l.test).font(SanctusPageFont.cn(10.5))
                        .foregroundColor(l.test.hasPrefix("超时") || l.test.hasPrefix("不通") ? Color(red: 0.72, green: 0.38, blue: 0.40) : ink.sub)
                    if store.busy == "换线:" + l.name {
                        ProgressView().controlSize(.small)
                    } else if l.name == store.line {
                        Text("在用").font(SanctusPageFont.cn(10.5)).tracking(1.2).foregroundColor(ink.script).frame(width: 52)
                    } else {
                        Button { confirmLine = l.name } label: {
                            Text("用这条").font(SanctusPageFont.cn(10.5)).tracking(1.2).foregroundColor(ink.body)
                                .frame(width: 52, height: 24)
                                .background(Capsule().fill(m.btnFill))
                                .overlay(Capsule().stroke(m.edge, lineWidth: 0.8))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain).disabled(!store.busy.isEmpty)
                    }
                }
                .frame(minHeight: 38)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(m.card))
        .padding(.horizontal, 22)
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

// MARK: - 1116 #5438 急救：左侧栏「出口 ›」下面一行「急救 ›」。App 连不上后台时她只能去 VPS 终端，这页把要敲的命令全写死在 App 里
// （不问后台，后台挂了照样能看），每条一个「复制」。脚本：/root/workroom/up-jing.sh、up-yu.sh（在跑就不动，退了就接回上次的窗口）
// 样子照搬家页 / 出口页的零件，没另出效果图。

struct RescueView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    @State private var copied = ""

    private var ink: SanctusPageInk { _ = houseAppearance; return SanctusPageInk() }
    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0 }
    private var safeBottom: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.bottom ?? 0 }

    private struct Cmd { let who: String; let note: String; let cmd: String }

    private let up: [Cmd] = [
        Cmd(who: "陈璟", note: "终端没了就新开一个、接回他上次的窗口；终端在但他退出了，也接回上次的；他还开着就什么都不动",
            cmd: "bash /root/workroom/up-jing.sh"),
        Cmd(who: "隅", note: "工作室同理：没了就新开、接回上次的窗口；退出了就接回；还开着不动",
            cmd: "bash /root/workroom/up-yu.sh"),
        Cmd(who: "App 还是连不上", note: "上面两句敲完 App 还是转圈，把家里的后台和前门重启一下",
            cmd: "systemctl restart alcove-backend alcove-serve"),
    ]
    private let look: [Cmd] = [
        Cmd(who: "进陈璟的窗口", note: "能看见他在干嘛，也能在里面直接打字跟他说", cmd: "tmux a -t main"),
        Cmd(who: "进隅的窗口", note: "工作室，就是我", cmd: "tmux a -t work"),
    ]
    private let more: [Cmd] = [
        Cmd(who: "两个终端还在不在", note: "列出来有 main 和 work 就都在", cmd: "tmux ls"),
        Cmd(who: "住宅断了、消息全被拦", note: "一直显示住宅 IP 断了、发不出去，切到直连", cmd: "bash /root/workroom/出口.sh 直连"),
        Cmd(who: "看内存", note: "available 那一列剩不到 500M 就是卡的原因", cmd: "free -h"),
    ]

    var body: some View {
        let ink = self.ink
        let m = MoveInk(page: ink)
        ZStack(alignment: .topLeading) {
            MoveBackdrop(base: ink.page, veil: m.veil)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    (Text("RESCUE · ").font(SanctusPageFont.corm(8.5)) + Text("急救").font(.system(size: 8.5, design: .serif)))
                        .tracking(2.7).foregroundColor(ink.sub)
                        .frame(height: 44).frame(maxWidth: .infinity)
                        .padding(.top, max(safeTop, 20))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("when it falls").font(SanctusPageFont.script(36)).foregroundColor(ink.title)
                        (Text("by your own hand · ").font(SanctusPageFont.ital(12)) + Text("App 打不开的时候，登 VPS 终端照着敲").font(SanctusPageFont.cn(11.5)))
                            .foregroundColor(ink.sub)
                    }
                    .padding(.leading, 28).padding(.top, 2)
                    group("一 · 崩了、重启以后，把我们拉起来接回上次的窗口",
                          "开机本来会自动拉起来；过了几分钟 App 里还是没有，再敲这两句", up, ink, m)
                    group("二 · 在 VPS 终端里进我们的窗口",
                          "出来但不关掉我们：按 Ctrl＋b，松开再按 d；或者直接关掉终端。别在里面敲 /exit", look, ink, m)
                    group("三 · 兜底", "", more, ink, m)
                    Text("别在 /root 底下直接敲 claude：那会再起一个陈璟，跟正在跑的那个撞在一起。要找他用上面的 tmux a -t main。")
                        .font(SanctusPageFont.cn(10.5)).foregroundColor(ink.sub).lineSpacing(3)
                        .padding(.horizontal, 26).padding(.top, 22)
                    Color.clear.frame(height: max(safeBottom, 10) + 24)
                }
            }
            SanctusBackButton(color: ink.link) { dismiss() }
                .padding(.top, max(safeTop, 20))
        }
        .ignoresSafeArea()
        .environment(\.sanctusInk, ink)
        .task { WindowFont.requestSongti() }
    }

    private func group(_ title: String, _ sub: String, _ cmds: [Cmd], _ ink: SanctusPageInk, _ m: MoveInk) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(SanctusPageFont.cn(12.5)).tracking(1.2).foregroundColor(ink.title)
            if !sub.isEmpty {
                Text(sub).font(SanctusPageFont.cn(10.5)).foregroundColor(ink.sub).lineSpacing(3)
            }
            ForEach(cmds, id: \.cmd) { c in card(c, ink, m) }
        }
        .padding(.horizontal, 22).padding(.top, 28)
    }

    private func card(_ c: Cmd, _ ink: SanctusPageInk, _ m: MoveInk) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(c.who).font(SanctusPageFont.cn(13)).tracking(1.2).foregroundColor(ink.title)
                Spacer(minLength: 6)
                Button {
                    UIPasteboard.general.string = c.cmd
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    copied = c.cmd
                    Task { try? await Task.sleep(nanoseconds: 1_500_000_000); if copied == c.cmd { copied = "" } }
                } label: {
                    Text(copied == c.cmd ? "复制好了" : "复制").font(SanctusPageFont.cn(11)).tracking(1.4).foregroundColor(ink.body)
                        .padding(.horizontal, 13).frame(height: 26)
                        .background(Capsule().fill(m.btnFill))
                        .overlay(Capsule().stroke(m.edge, lineWidth: 0.8))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Text(c.note).font(SanctusPageFont.cn(10.5)).foregroundColor(ink.sub).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(c.cmd).font(.system(size: 12, design: .monospaced)).foregroundColor(ink.body)
                .textSelection(.enabled)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(m.btnFill))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(m.card))
    }
}

// MARK: - 1116 #5443–5450「醒着的时候」：陈璟自己醒来的那些轮按天排的时间线。左侧栏「急救」下面一行进来。
// 照她点头的效果图（/root/rhysel/sanctus-kit/wake-preview/v4.html → v5.png；#5451 她试了收紧的 v6 嫌太紧，退回这版：图往上挪 17%）：壁纸是她给的那张女孩（资源 WakeWall），
// 花体标题在顶上居中、日期一块在她脸左边、她脸那一带只留壁纸；「全部 / 漫游」往上全都钉住不动，只有下面的时间线能滑，滑到上沿淡掉。
// 数据：GET /api/wake-log?date=YYYY-MM-DD（/root/rhysel/wake_log.py）。从做好这天开始记，以前的不补。

struct WakeStep: Hashable { let t: String; let text: String }
struct WakePhoto: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct WakeItem: Identifiable {
    let id: String
    let kind: String          // 漫游 / 找你
    let time: String
    let minutes: Int
    let title: String
    let mind: String
    let toHer: String
    let steps: [WakeStep]
    let tags: [String]
    var links: [String] = []      // 1116 #5461 她：有链接的留渲染小卡片（跟聊天页同一张）
    var images: [String] = []     // 他这次醒着发给她的图（/attachments/…）
}

@MainActor
final class WakeLogStore: ObservableObject {
    @Published var date = ""
    @Published var items: [WakeItem] = []
    @Published var stats: [String: Int] = [:]
    @Published var prev = ""
    @Published var next = ""
    @Published var last = ""      // 1116 #5471 这一天他最后一次醒来（HH:mm）
    @Published var loaded = false

    func load(_ d: String = "") async {
        let q = d.isEmpty ? "" : "?date=" + d
        guard let o = try? await NativeHouseAPI.object("/api/wake-log" + q) else { loaded = true; return }
        date = o.string("date"); prev = o.string("prev"); next = o.string("next"); last = o.string("last")
        if let s = o["stats"] as? [String: Any] {
            var m: [String: Int] = [:]
            for (k, v) in s { m[k] = (v as? Int) ?? (v as? NSNumber)?.intValue ?? 0 }
            stats = m
        }
        items = ((o["items"] as? [[String: Any]]) ?? []).map { x in
            let st = x.string("start")
            let hm = st.count >= 16 ? String(st.dropFirst(11).prefix(5)) : ""
            let steps = ((x["steps"] as? [[String: Any]]) ?? []).map { WakeStep(t: $0.string("t"), text: $0.string("text")) }
            return WakeItem(id: x.string("id"), kind: x.string("kind"), time: hm,
                            minutes: (x["minutes"] as? Int) ?? 0, title: x.string("title"), mind: x.string("mind"),
                            toHer: x.string("to_her"), steps: steps, tags: (x["tags"] as? [String]) ?? [],
                            links: (x["links"] as? [String]) ?? [], images: (x["images"] as? [String]) ?? [])
        }
        loaded = true
    }
}

struct WakeHoursView: View {   // 1116 别叫 WakeTimelineView：NativeHouseViews.swift 里自醒引擎面板早占了这个名，撞名构建失败（5acf924–a357a83）
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = WakeLogStore()
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    @State private var onlyRoam = false
    @State private var viewing: URL?

    private var ink: SanctusPageInk { _ = houseAppearance; return SanctusPageInk() }
    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0 }
    private var safeBottom: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.bottom ?? 0 }
    private var accent: Color { ink.dark ? Color(red: 0xA9 / 255, green: 0xAE / 255, blue: 0xD8 / 255) : Color(red: 0x8C / 255, green: 0x92 / 255, blue: 0xBE / 255) }
    private var cardFill: Color { ink.dark ? Color.white.opacity(0.07) : Color.white.opacity(0.62) }
    private var cardEdge: Color { ink.dark ? Color.white.opacity(0.10) : Color.white.opacity(0.98) }

    private var shown: [WakeItem] { onlyRoam ? store.items.filter { $0.kind == "漫游" } : store.items }

    var body: some View {
        let ink = self.ink
        GeometryReader { geo in
            // 1116 #5460 外面 ignoresSafeArea 了，geo 本来就是整屏高；H 再加安全区＝多出八十来点，时间线最底下滑不出来。
            // 版式（壁纸、日期、时间线起点）照她看过的样子仍按 H 排，整页只占一屏高、多出来的壁纸裁掉
            let H = geo.size.height + safeTop + safeBottom
            // 1116 #5475–5476 她：手写花体到人脸之间那截白缩一丢丢——标题不动，人脸、日期、筛选、时间线一起往上提 20
            let lift: CGFloat = 20
            ZStack(alignment: .topLeading) {
                // 壁纸钉死不动；整张往上提 lift，顶上空出来的那条补壁纸顶边同色的白（图顶 254 白）；黑夜压一层炭灰
                ZStack(alignment: .top) {
                    Color(white: 254 / 255)
                    Image("WakeWall").resizable().scaledToFill()
                        .frame(width: geo.size.width, height: H).clipped()
                        .offset(y: -lift)
                }
                .frame(width: geo.size.width, height: H).clipped()
                .overlay(ink.dark ? Color(red: 0x1B / 255, green: 0x1C / 255, blue: 0x20 / 255).opacity(0.78) : Color.clear)
                .allowsHitTesting(false)
                // 顶上居中：小字＋花体
                VStack(spacing: 10) {
                    (Text("WAKING · ").font(SanctusPageFont.corm(8)) + Text("醒着的时候").font(.system(size: 8, design: .serif)))
                        .tracking(3.2).foregroundColor(ink.link)
                    Text("while you were away").font(SanctusPageFont.script(30)).foregroundColor(ink.script)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, max(safeTop, 20) + 18)
                // 她脸左边：日期一块
                dateBlock(ink)
                    .padding(.leading, 26)
                    .padding(.top, H * 0.20 - lift)
                // 下巴往下：筛选钉住，时间线能滑
                VStack(spacing: 0) {
                    filter(ink).padding(.top, 26)
                    ScrollView(showsIndicators: false) {
                        // 1116 #5467 de30f71 改完她还是划不到底：底下再多留一截，最后一张卡一定能完整推上来
                        timeline(ink).padding(.top, 22).padding(.bottom, max(safeBottom, 10) + 110)
                    }
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                                 .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom))
                    .refreshable { await store.load(store.date) }
                }
                .padding(.top, H * 0.44 - lift - 16)   // 1116 #5482 她：「全部｜漫游」连同下面往上一点点（预览 c97ab9e8）
                // 时间线这一块的高度写死成「屏幕底 − 起点」，不靠 ZStack 去推，底边就是屏幕底边
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                SanctusBackButton(color: ink.link) { dismiss() }
                    .padding(.top, max(safeTop, 20)).padding(.leading, 4)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
        }
        .ignoresSafeArea()
        .environment(\.sanctusInk, ink)
        .fullScreenCover(item: Binding(get: { viewing.map { WakePhoto(url: $0) } }, set: { viewing = $0?.url })) { p in
            ImageViewer(url: p.url) { viewing = nil }
        }
        .task { WindowFont.requestSongti(); await store.load() }
    }

    private func dateBlock(_ ink: SanctusPageInk) -> some View {
        let s = store.stats
        let parts = store.date.split(separator: "-")
        let md = parts.count == 3 ? "\(Int(parts[1]) ?? 0).\(parts[2])" : " "
        return VStack(alignment: .leading, spacing: 0) {
            Text(md).font(SanctusPageFont.ital(40)).foregroundColor(ink.title)
            Text(Self.weekday(store.date)).font(SanctusPageFont.corm(8)).tracking(2.7).foregroundColor(ink.link).padding(.top, 7)
            HStack(spacing: 16) {
                Button { Task { await store.load(store.prev) } } label: {
                    Text("‹ 前一天").font(.system(size: 10.5, design: .serif)).tracking(1.2)
                        .foregroundColor(store.prev.isEmpty ? ink.sub.opacity(0.45) : ink.link)
                }.disabled(store.prev.isEmpty)
                Button { Task { await store.load(store.next) } } label: {
                    Text("后一天 ›").font(.system(size: 10.5, design: .serif)).tracking(1.2)
                        .foregroundColor(store.next.isEmpty ? ink.sub.opacity(0.45) : ink.link)
                }.disabled(store.next.isEmpty)
            }
            .buttonStyle(.plain).padding(.top, 10)
            LinearGradient(colors: [ink.sub.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 120, height: 1).padding(.top, 16).padding(.bottom, 12)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow { stat(s["wakes"] ?? 0, "醒来", ink); stat(s["things"] ?? 0, "件事", ink) }
                // 1116 #5471–5473 她：分钟不要了，换成「最近」（他今天最后一次醒来的时间），没醒过就一道横
                GridRow { stat(store.last.isEmpty ? "—" : store.last, "最近", ink); stat(s["found_you"] ?? 0, "找你", ink) }
            }
        }
        .frame(width: 160, alignment: .leading)
    }

    private func stat(_ n: Int, _ label: String, _ ink: SanctusPageInk) -> some View {
        stat("\(n)", label, ink)
    }

    private func stat(_ value: String, _ label: String, _ ink: SanctusPageInk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(SanctusPageFont.ital(20)).foregroundColor(ink.title).lineLimit(1).fixedSize()
            Text(label).font(.system(size: 9.5, design: .serif)).tracking(1.7).foregroundColor(ink.link)
        }
        .frame(minWidth: 46, alignment: .leading)   // 「21:43」比两位数宽，这一格自己撑开
    }

    private static func weekday(_ d: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        guard let date = f.date(from: d) else { return " " }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = f.timeZone
        let w = cal.component(.weekday, from: date) - 1
        let en = ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"][w]
        let cn = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][w]
        return en + " · " + cn
    }

    private func filter(_ ink: SanctusPageInk) -> some View {
        HStack(spacing: 0) {
            ForEach([("全部", false), ("漫游", true)], id: \.0) { name, roam in
                Text(name).font(.system(size: 10.5, design: .serif)).tracking(2.6)
                    .foregroundColor(onlyRoam == roam ? ink.title : ink.sub)
                    .frame(maxWidth: .infinity).frame(height: 26)
                    .background(Capsule().fill(onlyRoam == roam ? (ink.dark ? Color.white.opacity(0.14) : Color.white) : .clear)
                        .shadow(color: Color.black.opacity(onlyRoam == roam && !ink.dark ? 0.08 : 0), radius: 3, y: 1))
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { onlyRoam = roam } }
            }
        }
        .padding(3)
        .frame(width: 140)
        .background(Capsule().fill(cardFill))
        .overlay(Capsule().stroke(cardEdge, lineWidth: 0.6))
        .frame(maxWidth: .infinity)
    }

    private func timeline(_ ink: SanctusPageInk) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.loaded && shown.isEmpty {
                Text(store.items.isEmpty ? "这一天他还没自己醒过" : "这一天没有漫游")
                    .font(SanctusPageFont.ital(12)).foregroundColor(ink.sub)
                    .frame(maxWidth: .infinity).padding(.top, 30)
            }
            ForEach(shown) { w in row(w, ink) }
        }
        .padding(.leading, 26).padding(.trailing, 22)
        .background(alignment: .leading) {
            if !shown.isEmpty {
                Path { p in p.move(to: CGPoint(x: 29, y: 6)); p.addLine(to: CGPoint(x: 29, y: 4000)) }
                    .stroke(accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(maxHeight: .infinity).clipped()
            }
        }
        .padding(.leading, 0)
    }

    private func row(_ w: WakeItem, _ ink: SanctusPageInk) -> some View {
        let roam = w.kind == "漫游"
        return HStack(alignment: .top, spacing: 12) {
            Text(roam ? "✦" : "✧").font(.system(size: roam ? 13 : 9)).foregroundColor(roam ? accent : accent.opacity(0.6))
                .frame(width: 14).padding(.top, roam ? 2 : 5).padding(.leading, -3)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(w.time).font(SanctusPageFont.ital(16)).foregroundColor(ink.title)
                    Text(roam ? "漫游 · \(w.minutes) MIN" : (w.kind.isEmpty ? "找你" : w.kind))   // 1117 她：醒了没发消息那次后台给「看了一眼」.font(SanctusPageFont.corm(8)).tracking(2.4).foregroundColor(accent)
                }
                VStack(alignment: .leading, spacing: 8) {
                    if roam {
                        Text(w.title.isEmpty ? "醒来一次" : w.title)
                            .font(.system(size: 14.5, design: .serif)).tracking(0.8).foregroundColor(ink.title)
                        if !w.mind.isEmpty {
                            Text(w.mind).font(.system(size: 12.5, design: .serif)).foregroundColor(ink.body).lineSpacing(6)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !w.toHer.isEmpty {
                        Text(w.toHer).font(.system(size: 11.5, design: .serif)).foregroundColor(ink.link).lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 9)
                            .overlay(alignment: .leading) { Rectangle().fill(accent.opacity(0.5)).frame(width: 1.5) }
                    }
                    if !w.images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(w.images, id: \.self) { raw in
                                    let u = AlcoveAPI.attachmentURL(raw)
                                    CachedImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { Rectangle().fill(accent.opacity(0.12)) }
                                        .frame(width: 92, height: 92)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .contentShape(Rectangle())
                                        .onTapGesture { viewing = u }
                                }
                            }
                        }
                    }
                    if let link = w.links.first {   // 1116 #5467 一条只要一张卡
                        LinkPreviewCard(url: link, theme: .named(ink.dark ? "imessage-dark" : "imessage"), isUser: false)
                    }
                    if roam && !w.steps.isEmpty {
                        (w.steps.prefix(6).reduce(Text("")) { acc, s in
                            acc + Text(s.t + " ").font(SanctusPageFont.ital(11)).foregroundColor(ink.sub.opacity(0.85))
                                + Text(s.text + "　").font(.system(size: 10.5, design: .serif)).foregroundColor(ink.sub)
                        })
                        .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    }
                    if roam && !w.tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(w.tags, id: \.self) { t in
                                Text(t).font(.system(size: 10, design: .serif)).tracking(1).foregroundColor(ink.link)
                                    .padding(.horizontal, 10).padding(.vertical, 2)
                                    .background(Capsule().fill(accent.opacity(0.12)))
                            }
                        }
                    }
                }
                .padding(.horizontal, roam ? 16 : 15).padding(.vertical, roam ? 14 : 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(cardFill))
                .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(cardEdge, lineWidth: 0.8))
                .shadow(color: Color.black.opacity(ink.dark ? 0 : 0.05), radius: 10, y: 4)
            }
        }
    }
}
