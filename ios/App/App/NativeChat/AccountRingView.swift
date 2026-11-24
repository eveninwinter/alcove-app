import SwiftUI
import UIKit
import LocalAuthentication
import UniformTypeIdentifiers

// MARK: - 1113 钥匙串换号页（#5068–5076）
// 她：「换号我这边直接操作」——号被封了、找不到隅的时候，自己在手机上登新号、换上去。
// 样子照她点头的效果图（sanctus-kit/mock-keys/a.jpg）：上面两个挂钩（陈璟＝主聊天、隅＝工作室）各挂着现在用的号，
// 下面所有的号一张一张钥匙牌，最底下「登新号」。入口在聊天页左侧栏额度下面那行「换号 ›」。
// 后台走前门 /api/usage/ring（alcove-independent/acct_ring.py）：
//   GET  /api/usage/ring          两个挂钩＋所有的号＋额度
//   POST /api/usage/ring/login    {kind: key|full}  开一次登录，回授权链接
//   POST /api/usage/ring/code     {code, name}      填她粘回来的授权码，登好就记下
//   POST /api/usage/ring/cancel   关掉登录
//   POST /api/usage/ring/switch   {account, who: main|work|both}  等那边说完自动重开接回（聊天不丢）

struct RingAccount: Identifiable, Equatable {
    let name: String
    let kind: String          // key / full
    let until: String
    let inUse: [String]
    let ok: Bool
    let error: String
    let verify: Bool
    let five: Int?
    let seven: Int?
    let sevenReset: Int
    var id: String { name }

    init(_ d: [String: Any]) {
        name = d["name"] as? String ?? ""
        kind = d["kind"] as? String ?? "key"
        until = d["until"] as? String ?? ""
        inUse = d["in_use"] as? [String] ?? []
        ok = d["ok"] as? Bool ?? false
        error = d["error"] as? String ?? ""
        verify = d["verify"] as? Bool ?? false
        let f = d["five_hour"] as? [String: Any]
        let s = d["seven_day"] as? [String: Any]
        five = (f?["used_percent"] as? NSNumber)?.intValue
        seven = (s?["used_percent"] as? NSNumber)?.intValue
        sevenReset = (s?["reset_at"] as? NSNumber)?.intValue ?? 0
    }

    var kindText: String { kind == "full" ? "完整登录" : "钥匙" }

    /// 牌子上那个小胶囊
    var pill: String? {
        if verify { return "要验证" }
        if !ok && !error.isEmpty { return error.contains("额度") ? nil : "要重登" }
        let main = inUse.contains("main"), work = inUse.contains("work")
        if main && work { return "两边在用" }
        if main { return "陈璟在用" }
        if work { return "隅在用" }
        return nil
    }

    var usable: Bool { ok }

    private static let md: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM.dd"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai"); f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    var sevenResetText: String {
        sevenReset > 0 ? Self.md.string(from: Date(timeIntervalSince1970: TimeInterval(sevenReset))) + " 重置" : ""
    }
    var untilText: String { until.replacingOccurrences(of: "-", with: ".").prefix(7).description }
}

/// 1124 #5962–5973 账号本里的一条：挂在哪个 Claude 号下面（空＝其他）、类别、账号全文；密码只在刷脸后单独要
struct BookItem: Identifiable, Equatable {
    let id: String
    let owner: String
    let kind: String
    let label: String
    let account: String
    let purpose: String
    let note: String
    let hasSecret: Bool

    init(_ d: [String: Any]) {
        id = d["id"] as? String ?? ""
        owner = d["owner"] as? String ?? ""
        kind = d["kind"] as? String ?? "other"
        label = d["label"] as? String ?? ""
        account = d["account"] as? String ?? ""
        purpose = d["purpose"] as? String ?? ""
        note = d["note"] as? String ?? ""
        hasSecret = d["has_secret"] as? Bool ?? false
    }
}

@MainActor
final class RingStore: ObservableObject {
    @Published var accounts: [RingAccount] = []
    @Published var hooks: [String: String] = [:]
    @Published var loading = true
    @Published var failed = false
    @Published var toast = ""
    @Published var bookClaude: [String] = []
    @Published var book: [BookItem] = []
    @Published var renew: [String: String] = [:]

    func loadBook() async {
        guard let j = try? await RingStore.call("/api/usage/book", method: "GET", body: nil) else { return }
        bookClaude = j["claude"] as? [String] ?? []
        book = (j["items"] as? [[String: Any]] ?? []).map(BookItem.init)
        renew = j["renew"] as? [String: String] ?? [:]
    }

    func load() async {
        async let b: Void = loadBook()
        do {
            let j = try await RingStore.call("/api/usage/ring", method: "GET", body: nil)
            accounts = (j["accounts"] as? [[String: Any]] ?? []).map(RingAccount.init)
            hooks = j["hooks"] as? [String: String] ?? [:]
            failed = false
        } catch {
            if accounts.isEmpty { failed = true }
        }
        loading = false
        _ = await b
    }

    func account(_ name: String?) -> RingAccount? { accounts.first { $0.name == name } }

    func say(_ t: String) {
        toast = t
        Task { try? await Task.sleep(nanoseconds: 4_000_000_000); if toast == t { toast = "" } }
    }

    func switchTo(_ name: String, who: String) async {
        let whoText = who == "main" ? "陈璟" : (who == "work" ? "隅" : "两边")
        do {
            let j = try await RingStore.call("/api/usage/ring/switch", body: ["account": name, "who": who])
            if j["ok"] as? Bool == true {
                say("\(whoText)换成 \(name) 了：等那边这一轮说完会自动重开，一两分钟")
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await load()
            } else {
                say(j["error"] as? String ?? "没换成")
            }
        } catch {
            say("没连上，再点一次")
        }
    }

    /// 登录、填码要等对面，最长一分钟，超时给宽一点
    static func call(_ path: String, method: String = "POST", body: [String: Any]?) async throws -> [String: Any] {
        var req = URLRequest(url: AlcoveAPI.fullURL(path))
        req.httpMethod = method
        req.timeoutInterval = 90
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, _) = try await AlcoveAPI.session.data(for: req)
        guard let v = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return v
    }
}

// MARK: 颜色

private struct RingInk {
    let page: SanctusPageInk
    var dark: Bool { page.dark }
    private func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255, opacity: a) }
    /// 钥匙牌的面：半透白，透一点后面
    var tag: Color { dark ? rgb(44, 45, 52, 0.80) : Color.white.opacity(0.86) }
    var hole: Color { dark ? rgb(27, 28, 32) : rgb(239, 239, 237) }
    var holeEdge: Color { dark ? Color.white.opacity(0.25) : rgb(150, 154, 164, 0.75) }
    var string: Color { dark ? Color.white.opacity(0.22) : rgb(150, 154, 164, 0.6) }
    var rail: Color { dark ? Color.white.opacity(0.16) : rgb(150, 154, 164, 0.55) }
    var pillEdge: Color { dark ? Color.white.opacity(0.22) : rgb(150, 154, 164, 0.6) }
    var addFill: Color { dark ? Color.white.opacity(0.05) : Color.white.opacity(0.7) }
    /// 壁纸上压的那层：效果图里壁纸只淡淡透出来
    var veil: Color { dark ? rgb(27, 28, 32, 0.86) : rgb(239, 239, 237, 0.84) }
}

/// 背景跟主聊天壁纸走（跟工作台一样），上面压一层让它只淡淡透出来
private struct RingBackdrop: View {
    let base: Color
    let veil: Color
    @ObservedObject private var wall = ChatWallpaperStore.shared
    var body: some View {
        ZStack {
            base
            ChatWallpaperRenderer(descriptor: wall.descriptor)
            veil
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: 页面

struct AccountRingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = RingStore()
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    @State private var hookPick: String?            // 点了哪个挂钩的「换一把」：main / work
    @State private var tagPick: RingAccount?        // 点了哪张钥匙牌
    @State private var showLogin = false
    @State private var editing: BookDraft?           // 1124 账号本：新记 / 改一条
    @State private var deleting: BookItem?
    @State private var renewing: String?             // 改哪个号的续费日
    @State private var shown: [String: String] = [:] // 刷过脸、正露着的密码（30 秒自己收回）
    @State private var unlockedUntil = Date.distantPast

    private var ink: SanctusPageInk { _ = houseAppearance; return SanctusPageInk() }
    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0 }
    private var safeBottom: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.bottom ?? 0 }

    var body: some View {
        let ink = self.ink
        let r = RingInk(page: ink)
        ZStack(alignment: .topLeading) {
            RingBackdrop(base: ink.page, veil: r.veil)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    (Text("ACCOUNTS · ").font(SanctusPageFont.corm(8.5)) + Text("账号").font(.system(size: 8.5, design: .serif)))
                        .tracking(2.7).foregroundColor(ink.sub)
                        .frame(height: 44).frame(maxWidth: .infinity)
                        .padding(.top, max(safeTop, 20))
                    titleBlock(ink)
                    hooksRow(ink, r).padding(.top, 34)
                    ringHeader(ink).padding(.top, 40)
                    tagList(ink, r)
                    addButton(ink, r).padding(.top, 24)
                    footer(ink).padding(.top, 12)
                    // 1124 #5962 账号本：钥匙串下面，往下滑
                    bookSection(ink, r).padding(.top, 46)
                        .padding(.bottom, max(safeBottom, 10) + 20)
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
        .confirmationDialog(hookPickTitle, isPresented: Binding(get: { hookPick != nil }, set: { if !$0 { hookPick = nil } }),
                            titleVisibility: .visible) {
            ForEach(store.accounts.filter { $0.usable }) { a in
                Button(a.name + "（" + a.kindText + "）") {
                    let who = hookPick ?? "main"
                    Task { await store.switchTo(a.name, who: who) }
                }
            }
            Button("登一个新号") { showLogin = true }
            Button("算了", role: .cancel) {}
        } message: {
            Text("换完会等那边这一轮说完再自动重开、接回原来的窗口，聊天不丢。")
        }
        .confirmationDialog(tagPick.map { "\($0.name) 挂给谁" } ?? "", isPresented: Binding(get: { tagPick != nil }, set: { if !$0 { tagPick = nil } }),
                            titleVisibility: .visible) {
            if let a = tagPick {
                if a.usable {
                    Button("陈璟（主聊天）") { Task { await store.switchTo(a.name, who: "main") } }
                    Button("隅（工作室）") { Task { await store.switchTo(a.name, who: "work") } }
                    Button("两个都换") { Task { await store.switchTo(a.name, who: "both") } }
                } else {
                    Button("重新登这个号") { showLogin = true }
                }
                Button("算了", role: .cancel) {}
            }
        } message: {
            if let a = tagPick {
                if !a.usable {
                    Text(a.error.isEmpty ? "这个号现在用不了。" : "这个号现在用不了：\(a.error)。")
                } else if a.kind == "full" {
                    Text("完整登录整台机器只能挂一个：另一边要是也在用完整登录，会一起换、一起重开。")
                } else {
                    Text("换完会等那边这一轮说完再自动重开、接回原来的窗口，聊天不丢。")
                }
            }
        }
        .sheet(item: $editing) { d in
            BookEditor(draft: d, claudeNames: store.bookClaude) { await store.loadBook() }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: renewBinding) { t in
            RenewSheet(name: t.name, current: store.renew[t.name] ?? "") { await store.loadBook() }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(deletingTitle,
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            if let it = deleting {
                Button("删掉", role: .destructive) {
                    Task {
                        _ = try? await RingStore.call("/api/usage/book/delete", body: ["id": it.id])
                        shown[it.id] = nil
                        await store.loadBook()
                    }
                }
                Button("算了", role: .cancel) {}
            }
        } message: { Text("密码也一起删，找不回来。") }
        .onDisappear { shown = [:] }
        .sheet(isPresented: $showLogin, onDismiss: { Task { await store.load() } }) {
            RingLoginSheet(store: store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(false)
        }
    }

    private var deletingTitle: String {
        guard let it = deleting else { return "" }
        return "删掉 " + (it.account.isEmpty ? it.label : it.account) + "？"
    }

    private var renewBinding: Binding<RenewTarget?> {
        Binding(get: { renewing.map { RenewTarget(name: $0) } }, set: { renewing = $0?.name })
    }

    private var hookPickTitle: String {
        guard let h = hookPick else { return "" }
        return h == "main" ? "给陈璟换一个号" : "给隅换一个号"
    }

    // MARK: 头

    private func titleBlock(_ ink: SanctusPageInk) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("the key ring").font(SanctusPageFont.script(36)).foregroundColor(ink.title)
            (Text("whose key, on whose hook · ").font(SanctusPageFont.ital(12)) + Text("谁在用哪个号").font(SanctusPageFont.cn(11.5)))
                .foregroundColor(ink.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 28)
        .padding(.top, 2)
    }

    // MARK: 两个挂钩

    private func hooksRow(_ ink: SanctusPageInk, _ r: RingInk) -> some View {
        ZStack(alignment: .top) {
            // 横着那根细杆，两头淡出
            Rectangle()
                .fill(LinearGradient(colors: [r.rail.opacity(0), r.rail, r.rail, r.rail.opacity(0)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
                .padding(.horizontal, 40)
                .padding(.top, 10)
            HStack(alignment: .top, spacing: 0) {
                hook(who: "main", name: "陈璟", note: "main", ink, r).frame(maxWidth: .infinity)
                hook(who: "work", name: "隅", note: "workroom", ink, r).frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
        }
    }

    private func hook(who: String, name: String, note: String, _ ink: SanctusPageInk, _ r: RingInk) -> some View {
        let accName = store.hooks[who]
        let a = store.account(accName)
        return VStack(spacing: 0) {
            HookShape().stroke(ink.sub, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                .frame(width: 22, height: 26)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(name).font(SanctusPageFont.cn(12.5)).tracking(1.5).foregroundColor(ink.title)
                Text(note).font(SanctusPageFont.ital(10.5)).foregroundColor(ink.sub)
            }
            .padding(.top, 2)
            Rectangle().fill(r.string).frame(width: 1, height: 16).padding(.top, 4)
            Button { hookPick = who } label: {
                VStack(spacing: 0) {
                    Circle().fill(r.hole).overlay(Circle().stroke(r.holeEdge, lineWidth: 0.8)).frame(width: 7, height: 7)
                    Text(accName?.isEmpty == false ? accName! : (store.loading ? "…" : "没挂号"))
                        .font(SanctusPageFont.corm(15)).foregroundColor(ink.title)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.top, 6).padding(.horizontal, 8)
                    Text(a.map { $0.kindText.map { String($0) }.joined(separator: " ") } ?? " ")
                        .font(SanctusPageFont.cn(9.5)).foregroundColor(ink.sub).padding(.top, 3)
                    usageLine(a, ink).padding(.top, 8)
                    Text("换 一 把 ›").font(SanctusPageFont.cn(10)).foregroundColor(ink.link).padding(.top, 8)
                }
                .padding(.top, 7).padding(.bottom, 12)
                .frame(width: 132)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(r.tag))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func usageLine(_ a: RingAccount?, _ ink: SanctusPageInk) -> some View {
        if let a, a.ok, let f = a.five, let s = a.seven {
            (Text("5h ") + Text("\(f)%").foregroundColor(ink.title) + Text(" · 7d ") + Text("\(s)%").foregroundColor(ink.title))
                .font(SanctusPageFont.corm(11)).foregroundColor(ink.script).tracking(0.6)
        } else if let a, !a.error.isEmpty {
            Text(a.error).font(SanctusPageFont.cn(10)).foregroundColor(ink.sub).lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 6)
        } else {
            Text("—").font(SanctusPageFont.corm(11)).foregroundColor(ink.sub)
        }
    }

    // MARK: 钥匙串

    private func ringHeader(_ ink: SanctusPageInk) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("所有的号").font(SanctusPageFont.cn(13)).tracking(1.3).foregroundColor(ink.title)
            Text("ON THE RING").font(SanctusPageFont.corm(8.5)).tracking(2.7).foregroundColor(ink.sub)
            Spacer(minLength: 0)
            Text("\(store.accounts.count) keys").font(SanctusPageFont.ital(11)).foregroundColor(ink.sub)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 12)
    }

    private func tagList(_ ink: SanctusPageInk, _ r: RingInk) -> some View {
        VStack(spacing: 10) {
            if store.loading && store.accounts.isEmpty {
                ProgressView().controlSize(.small).tint(ink.sub).padding(.vertical, 20)
            } else if store.failed {
                Text("没连上，下拉再试一次").font(SanctusPageFont.cn(12)).foregroundColor(ink.sub).padding(.vertical, 20)
            }
            ForEach(store.accounts) { a in
                Button { tagPick = a } label: { tagRow(a, ink, r) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
    }

    private func tagRow(_ a: RingAccount, _ ink: SanctusPageInk, _ r: RingInk) -> some View {
        HStack(spacing: 0) {
            // 牌子左头：一个穿绳的小孔，虚线隔开
            ZStack {
                Circle().fill(r.hole).overlay(Circle().stroke(r.holeEdge, lineWidth: 0.8)).frame(width: 8, height: 8)
            }
            .frame(width: 40)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .trailing) {
                Rectangle().fill(.clear).frame(width: 0.7)
                    .overlay(RingDashLine().stroke(r.pillEdge, style: StrokeStyle(lineWidth: 0.7, dash: [3, 3])))
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(a.name).font(SanctusPageFont.corm(15)).foregroundColor(ink.title).lineLimit(1).minimumScaleFactor(0.75)
                    if let p = a.pill {
                        Text(p).font(SanctusPageFont.cn(9.5)).tracking(1).foregroundColor(ink.script)
                            .padding(.horizontal, 7).frame(height: 16)
                            .overlay(Capsule().stroke(r.pillEdge, lineWidth: 0.7))
                    }
                }
                subLine(a, ink)
            }
            .padding(.leading, 14)
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                if a.ok, let s = a.seven {
                    Text("7d \(s)%").font(SanctusPageFont.corm(12)).foregroundColor(ink.script)
                    Text(a.sevenResetText).font(SanctusPageFont.cn(10)).foregroundColor(ink.sub)
                } else {
                    Text("—").font(SanctusPageFont.corm(12)).foregroundColor(ink.script)
                    Text("暂时用不了").font(SanctusPageFont.cn(10)).foregroundColor(ink.sub)
                }
            }
            .padding(.trailing, 16)
        }
        .frame(height: 62)
        .background(UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8, bottomTrailingRadius: 12,
                                           topTrailingRadius: 12, style: .continuous).fill(r.tag))
        .opacity(a.ok ? 1 : 0.62)
        .contentShape(Rectangle())
    }

    private func subLine(_ a: RingAccount, _ ink: SanctusPageInk) -> some View {
        let text: Text
        if !a.ok && !a.error.isEmpty {
            text = Text(a.kindText + " · " + a.error).font(SanctusPageFont.cn(10.5))
        } else if a.kind == "key" && !a.until.isEmpty {
            text = Text("钥匙 · 一年期，到 ").font(SanctusPageFont.cn(10.5)) + Text(a.untilText).font(SanctusPageFont.ital(11))
        } else {
            text = Text(a.kindText + " · 凭证过期自己续").font(SanctusPageFont.cn(10.5))
        }
        return text.foregroundColor(ink.sub).lineLimit(1).minimumScaleFactor(0.8)
    }

    // MARK: 底下

    private func addButton(_ ink: SanctusPageInk, _ r: RingInk) -> some View {
        Button { showLogin = true } label: {
            Text("＋　登新号").font(SanctusPageFont.cn(14)).tracking(2.8).foregroundColor(ink.body)
                .padding(.horizontal, 34).frame(height: 38)
                .background(Capsule().fill(r.addFill))
                .overlay(Capsule().stroke(r.pillEdge, lineWidth: 0.8))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func footer(_ ink: SanctusPageInk) -> some View {
        VStack(spacing: 4) {
            Text("key · full login").font(SanctusPageFont.ital(11))
            Text("两种都能登，跟着步骤点，不用找隅").font(SanctusPageFont.cn(10.5))
        }
        .foregroundColor(ink.sub)
        .frame(maxWidth: .infinity)
    }

    // MARK: 账号本（1124 #5962–5973，效果图 sanctus-kit/mock-keys/d.jpg）

    private static let blood = Color(red: 0x9B / 255, green: 0x1B / 255, blue: 0x2A / 255)

    private func bookSection(_ ink: SanctusPageInk, _ r: RingInk) -> some View {
        let others = store.book.filter { $0.owner.isEmpty || !store.bookClaude.contains($0.owner) }
        return VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("账号本").font(SanctusPageFont.cn(13)).tracking(1.3).foregroundColor(ink.title)
                Text("ALL OUR KEYS").font(SanctusPageFont.corm(8.5)).tracking(2.7).foregroundColor(ink.sub)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            ForEach(store.bookClaude, id: \.self) { name in
                bookCard(name: name, items: store.book.filter { $0.owner == name }, ink, r)
            }
            if !others.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    (Text("ELSEWHERE · ").font(SanctusPageFont.corm(8)) + Text("其他").font(.system(size: 9, design: .serif)))
                        .tracking(2.4).foregroundColor(ink.sub)
                        .padding(.bottom, 2)
                    ForEach(others) { it in bookRow(it, bead: false, ink, r) }
                }
                .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(r.tag))
            }
            Button { editing = BookDraft(owner: "") } label: {
                Text("＋ 记 一 个").font(SanctusPageFont.cn(12.5)).tracking(3).foregroundColor(ink.link)
                    .frame(height: 40).frame(maxWidth: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    private func bookCard(name: String, items: [BookItem], _ ink: SanctusPageInk, _ r: RingInk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(SanctusPageFont.corm(19)).foregroundColor(ink.title).lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 8)
                Button { renewing = name } label: { renewLabel(name, ink) }.buttonStyle(.plain)
            }
            Text("CLAUDE").font(SanctusPageFont.corm(8)).tracking(2.4).foregroundColor(ink.sub).padding(.top, 2)
            LinearGradient(colors: [.clear, r.rail, r.rail, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 0.7).padding(.top, 12).padding(.horizontal, -4)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { it in bookRow(it, bead: true, ink, r) }
                Button { editing = BookDraft(owner: name) } label: {
                    Text(items.isEmpty ? "＋ 挂一个账号" : "＋ 再挂一个").font(SanctusPageFont.cn(10.5)).tracking(1.6)
                        .foregroundColor(ink.link).frame(height: 34).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, items.isEmpty ? 0 : 20)
            .background(alignment: .topLeading) {
                // 一根银线把挂着的账号串起来
                if !items.isEmpty {
                    Rectangle().fill(r.string).frame(width: 0.7)
                        .padding(.top, 14).padding(.bottom, 46)
                        .offset(x: 3.5)
                }
            }
        }
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(r.tag))
    }

    /// 续费日：她自己填；七天内（含过了的）前面一滴暗红
    @ViewBuilder private func renewLabel(_ name: String, _ ink: SanctusPageInk) -> some View {
        if let s = store.renew[name], let d = Self.ymd.date(from: s) {
            let soon = d.timeIntervalSinceNow < 7 * 86400
            HStack(spacing: 5) {
                if soon { Circle().fill(Self.blood).frame(width: 5, height: 5) }
                (Text("续费 ").font(SanctusPageFont.cn(9.5)) + Text(Self.md.string(from: d)).font(SanctusPageFont.ital(11)))
                    .foregroundColor(soon ? ink.script : ink.sub)
            }
        } else {
            Text("填续费日").font(SanctusPageFont.cn(9.5)).tracking(1).foregroundColor(ink.sub)
        }
    }

    private func bookRow(_ it: BookItem, bead: Bool, _ ink: SanctusPageInk, _ r: RingInk) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(it.label.isEmpty ? "账号" : it.label).font(SanctusPageFont.cn(9.5)).tracking(2).foregroundColor(ink.sub)
                Text(it.account.isEmpty ? "—" : it.account)
                    .font(.system(size: 14.5, design: .serif)).foregroundColor(ink.title)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .onTapGesture { copy(it.account, what: "账号") }
                if !it.note.isEmpty || !it.purpose.isEmpty {
                    Text([it.purpose, it.note].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(SanctusPageFont.cn(9.5)).foregroundColor(ink.sub).lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            secretPill(it, ink, r)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .topLeading) {
            if bead {
                Circle().fill(r.hole).overlay(Circle().stroke(r.holeEdge, lineWidth: 0.8))
                    .frame(width: 7, height: 7).offset(x: -20, y: 14)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button { editing = BookDraft(it) } label: { Label("改", systemImage: "pencil") }
            Button { copy(it.account, what: "账号") } label: { Label("复制账号", systemImage: "doc.on.doc") }
            Button(role: .destructive) { deleting = it } label: { Label("删掉", systemImage: "trash") }
        }
    }

    /// 密码：圆点；点一下刷脸露出来，露着的时候再点＝复制
    @ViewBuilder private func secretPill(_ it: BookItem, _ ink: SanctusPageInk, _ r: RingInk) -> some View {
        if !it.hasSecret {
            Button { editing = BookDraft(it) } label: {
                Text("填密码").font(SanctusPageFont.cn(9.5)).tracking(1).foregroundColor(ink.sub)
                    .padding(.horizontal, 9).frame(height: 24)
                    .overlay(Capsule().stroke(r.pillEdge, lineWidth: 0.6))
            }
            .buttonStyle(.plain)
        } else if let sec = shown[it.id] {
            Button { copy(sec, what: "密码") } label: {
                Text(sec).font(.system(size: 12, design: .monospaced)).foregroundColor(ink.title)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.horizontal, 9).frame(height: 24).frame(maxWidth: 150)
                    .overlay(Capsule().stroke(r.pillEdge, lineWidth: 0.6))
            }
            .buttonStyle(.plain)
        } else {
            Button { Task { await reveal(it) } } label: {
                Text("••••••").font(.system(size: 9)).tracking(3).foregroundColor(ink.link)
                    .padding(.leading, 9).padding(.trailing, 6).frame(height: 24)
                    .overlay(Capsule().stroke(r.pillEdge, lineWidth: 0.6))
            }
            .buttonStyle(.plain)
        }
    }

    private func reveal(_ it: BookItem) async {
        if Date() > unlockedUntil {
            let ctx = LAContext()
            var err: NSError?
            guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { store.say("这台手机没设密码或面容，看不了"); return }
            guard (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "看账号本里存的密码")) == true else { return }
            unlockedUntil = Date().addingTimeInterval(60)     // 一分钟内再点别的不用再刷
        }
        guard let j = try? await RingStore.call("/api/usage/book/reveal", body: ["id": it.id]),
              let sec = j["secret"] as? String else { store.say("没连上，再点一次"); return }
        shown[it.id] = sec
        Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if shown[it.id] == sec { shown[it.id] = nil }
        }
    }

    /// 复制：只在这台手机上（不同步到别的设备），两分钟后剪贴板自己清掉
    private func copy(_ text: String, what: String) {
        guard !text.isEmpty else { return }
        UIPasteboard.general.setItems([[UTType.plainText.identifier: text]],
                                      options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
        store.say("复制了\(what)")
    }

    private static let ymd: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai"); f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    private static let md: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM.dd"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai"); f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    private func toastLayer(_ ink: SanctusPageInk) -> some View {
        VStack {
            Spacer()
            if !store.toast.isEmpty {
                Text(store.toast).font(SanctusPageFont.cn(12)).foregroundColor(ink.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .padding(.horizontal, 24)
                    .padding(.bottom, max(safeBottom, 10) + 30)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }
}

/// 挂钩：从杆子上垂下来一截，底下弯个钩
private struct HookShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX
        p.move(to: CGPoint(x: cx, y: 0))
        p.addLine(to: CGPoint(x: cx, y: rect.height * 0.35))
        let r = rect.width * 0.27
        p.addArc(center: CGPoint(x: cx, y: rect.height * 0.35 + r), radius: r,
                 startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: false)
        return p
    }
}

/// 竖着的一根线（牌子左头的虚线）
private struct RingDashLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: 0))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.height))
        return p
    }
}

// MARK: - 登新号（一步一步）

private struct RingLoginSheet: View {
    @ObservedObject var store: RingStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    @State private var kind = ""          // key / full
    @State private var url: URL?
    @State private var code = ""
    @State private var name = ""
    @State private var busy = false
    @State private var err = ""
    @State private var done: String?      // 登好的号名
    @State private var doneKind = ""

    private var ink: SanctusPageInk { _ = houseAppearance; return SanctusPageInk() }
    private var step: Int { done != nil ? 3 : (url == nil ? 1 : 2) }

    var body: some View {
        let ink = self.ink
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("a new key").font(SanctusPageFont.script(30)).foregroundColor(ink.title)
                Text("登新号 · 三步").font(SanctusPageFont.cn(11.5)).foregroundColor(ink.sub).padding(.top, 4)
                stepRow(1, "选哪一种", ink).padding(.top, 26)
                if step == 1 { stepOne(ink) }
                stepRow(2, "去网页登录，把授权码粘回来", ink).padding(.top, 22)
                if step == 2 { stepTwo(ink) }
                stepRow(3, "挂给谁", ink).padding(.top, 22)
                if step == 3 { stepThree(ink) }
                if !err.isEmpty {
                    Text(err).font(SanctusPageFont.cn(12)).foregroundColor(ink.body)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 18)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 34)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ink.page.ignoresSafeArea())
        .onDisappear {
            if done == nil && url != nil {
                Task { _ = try? await RingStore.call("/api/usage/ring/cancel", body: [:]) }
            }
        }
    }

    private func stepRow(_ n: Int, _ t: String, _ ink: SanctusPageInk) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(SanctusPageFont.ital(18)).foregroundColor(step == n ? ink.title : ink.sub)
            Text(t).font(SanctusPageFont.cn(13.5)).tracking(1).foregroundColor(step == n ? ink.title : ink.sub)
            Spacer(minLength: 0)
            if step > n { Image(systemName: "checkmark").font(.system(size: 11)).foregroundColor(ink.sub) }
        }
    }

    private func choice(_ title: String, _ sub: String, _ value: String, _ ink: SanctusPageInk) -> some View {
        Button { Task { await start(value) } } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(SanctusPageFont.cn(14)).foregroundColor(ink.title)
                    Spacer()
                    if busy && kind == value { ProgressView().controlSize(.small) }
                    else { Text("›").foregroundColor(ink.link) }
                }
                Text(sub).font(SanctusPageFont.cn(11)).foregroundColor(ink.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ink.field))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func stepOne(_ ink: SanctusPageInk) -> some View {
        VStack(spacing: 10) {
            choice("钥匙", "一年期，像 chenjichenjing 那样。主聊天、工作室能各用各的。拿不准就选这个。", "key", ink)
            choice("完整登录", "像 overjingji 那样，能查 Fable 额度，凭证自己续。整台机器只能挂一个。", "full", ink)
        }
        .padding(.top, 14)
    }

    private func stepTwo(_ ink: SanctusPageInk) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { if let url { openURL(url) } } label: {
                Text("打开登录网页").font(SanctusPageFont.cn(13.5)).tracking(1.5).foregroundColor(ink.body)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .overlay(Capsule().stroke(ink.sub.opacity(0.6), lineWidth: 0.8))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            Text("在网页上登你要换上的那个号，点授权。登完网页会给一串授权码，整串复制，回到这里。")
                .font(SanctusPageFont.cn(11.5)).foregroundColor(ink.sub).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField("粘授权码", text: $code)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 12).frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 8).fill(ink.field))
                Button("粘贴") { code = (UIPasteboard.general.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
                    .font(SanctusPageFont.cn(12)).foregroundColor(ink.link)
            }
            TextField("给这个号起个名字（小写英文，比如 newjing）", text: $name)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(.system(size: 13))
                .padding(.horizontal, 12).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 8).fill(ink.field))
            Button { Task { await submit() } } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().controlSize(.small) }
                    Text(busy ? "在登，最多一分钟" : "填好了").font(SanctusPageFont.cn(13.5)).tracking(1.5)
                }
                .foregroundColor(ink.body)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(Capsule().fill(ink.field))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(busy || code.isEmpty || name.isEmpty)
            Button("重新选") { Task { await cancel() } }
                .font(SanctusPageFont.cn(11.5)).foregroundColor(ink.sub)
                .disabled(busy)
        }
        .padding(.top, 14)
    }

    private func stepThree(_ ink: SanctusPageInk) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(done ?? "") 登好了，已经挂到钥匙串上。现在挂给谁？")
                .font(SanctusPageFont.cn(12.5)).foregroundColor(ink.body).fixedSize(horizontal: false, vertical: true)
            if doneKind == "full" {
                Text("完整登录整台机器只能挂一个：另一边要是也在用完整登录，会一起换。")
                    .font(SanctusPageFont.cn(11)).foregroundColor(ink.sub).fixedSize(horizontal: false, vertical: true)
            }
            hangButton("陈璟（主聊天）", "main", ink)
            hangButton("隅（工作室）", "work", ink)
            hangButton("两个都换", "both", ink)
            Button("先不挂，放着") { dismiss() }
                .font(SanctusPageFont.cn(11.5)).foregroundColor(ink.sub).padding(.top, 4)
        }
        .padding(.top, 14)
    }

    private func hangButton(_ t: String, _ who: String, _ ink: SanctusPageInk) -> some View {
        Button {
            guard let n = done else { return }
            dismiss()
            Task { await store.switchTo(n, who: who) }
        } label: {
            Text(t).font(SanctusPageFont.cn(13.5)).tracking(1).foregroundColor(ink.body)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(Capsule().fill(ink.field))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 动作

    private func start(_ k: String) async {
        kind = k; busy = true; err = ""
        defer { busy = false }
        do {
            let j = try await RingStore.call("/api/usage/ring/login", body: ["kind": k])
            if let s = j["url"] as? String, let u = URL(string: s) {
                url = u
                openURL(u)
            } else {
                err = j["error"] as? String ?? "没拿到登录链接，再点一次"
            }
        } catch {
            err = "没连上服务器，再点一次"
        }
    }

    private func submit() async {
        busy = true; err = ""
        defer { busy = false }
        let n = name.trimmingCharacters(in: .whitespaces).lowercased()
        do {
            let j = try await RingStore.call("/api/usage/ring/code", body: ["code": code.trimmingCharacters(in: .whitespacesAndNewlines), "name": n])
            if j["ok"] as? Bool == true {
                done = j["name"] as? String ?? n
                doneKind = j["kind"] as? String ?? kind
                if let e = j["error"] as? String, !e.isEmpty { err = "登上了，不过：\(e)" }
                await store.load()
            } else {
                err = j["error"] as? String ?? "没登上"
                if err.contains("重来") || err.contains("重新开始") { url = nil; code = "" }
            }
        } catch {
            err = "等太久没回音。回钥匙串看看有没有多出这个号，没有就重来一次。"
        }
    }

    private func cancel() async {
        _ = try? await RingStore.call("/api/usage/ring/cancel", body: [:])
        url = nil; code = ""; err = ""; kind = ""
    }
}

// MARK: - 账号本：新记 / 改一条（1124 #5962–5973）

/// 编辑框里的草稿。改旧的：密码框空着＝不动原来的密码
struct BookDraft: Identifiable {
    var id = UUID()
    var itemId: String? = nil
    var owner: String
    var preset: String = "苹果 · 邮箱"
    var customLabel = ""
    var account = ""
    var secret = ""
    var note = ""

    struct Preset: Hashable {
        let label: String
        let kind: String
    }
    /// 类别：显示的字 → 后台 kind
    static let presets: [Preset] = [
        .init(label: "登录", kind: "claude"), .init(label: "苹果 · 邮箱", kind: "apple"), .init(label: "苹果", kind: "apple"),
        .init(label: "邮箱", kind: "email"), .init(label: "币安", kind: "exchange"), .init(label: "卡", kind: "card"),
        .init(label: "其他", kind: "other"),
    ]

    init(owner: String) {
        self.owner = owner
        preset = owner.isEmpty ? "其他" : "苹果 · 邮箱"
    }

    init(_ it: BookItem) {
        itemId = it.id
        owner = it.owner
        account = it.account
        note = [it.purpose, it.note].filter { !$0.isEmpty }.joined(separator: " · ")
        if Self.presets.contains(where: { $0.label == it.label && $0.label != "其他" }) {
            preset = it.label
        } else {
            preset = "其他"
            customLabel = it.label
        }
    }

    var label: String { preset == "其他" ? (customLabel.isEmpty ? "其他" : customLabel) : preset }
    var kind: String { Self.presets.first { $0.label == preset }?.kind ?? "other" }
}

private struct BookEditor: View {
    @State var draft: BookDraft
    let claudeNames: [String]
    let done: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    @State private var showSecret = false
    @State private var busy = false
    @State private var err = ""

    private var ink: SanctusPageInk { _ = houseAppearance; return SanctusPageInk() }
    private var isNew: Bool { draft.itemId == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("挂在哪个号下面") {
                    Picker("挂在", selection: $draft.owner) {
                        Text("不挂（放进其他）").tag("")
                        ForEach(claudeNames, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("是什么") {
                    Picker("类别", selection: $draft.preset) {
                        ForEach(BookDraft.presets, id: \.label) { Text($0.label).tag($0.label) }
                    }
                    if draft.preset == "其他" {
                        TextField("写个名字，比如 Infini", text: $draft.customLabel)
                    }
                }
                Section("账号") {
                    TextField("邮箱、手机号、卡号尾号…", text: $draft.account)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                }
                Section {
                    HStack {
                        Group {
                            if showSecret {
                                TextField(isNew ? "密码" : "不改就空着", text: $draft.secret)
                            } else {
                                SecureField(isNew ? "密码" : "不改就空着", text: $draft.secret)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        Button { showSecret.toggle() } label: {
                            Image(systemName: showSecret ? "eye.slash" : "eye").foregroundColor(ink.sub)
                        }
                        .buttonStyle(.plain)
                    }
                } header: { Text("密码") } footer: { Text("加密存着，页面上看要刷脸。") }
                Section("备注") {
                    TextField("干嘛用的、绑了什么", text: $draft.note, axis: .vertical)
                }
                if !err.isEmpty {
                    Text(err).foregroundColor(.red).font(.footnote)
                }
            }
            .navigationTitle(isNew ? "记一个账号" : "改一下")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("算了") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "存…" : "存") { Task { await save() } }
                        .disabled(busy || (draft.account.trimmingCharacters(in: .whitespaces).isEmpty && draft.preset == "其他" && draft.customLabel.isEmpty))
                }
            }
        }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        var body: [String: Any] = [
            "owner": draft.owner, "kind": draft.kind, "label": draft.label,
            "account": draft.account.trimmingCharacters(in: .whitespacesAndNewlines),
            "purpose": "", "note": draft.note.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        if let id = draft.itemId { body["id"] = id }
        if !draft.secret.isEmpty { body["secret"] = draft.secret }
        do {
            let j = try await RingStore.call("/api/usage/book/save", body: body)
            guard j["ok"] as? Bool == true else { err = j["error"] as? String ?? "没存上"; return }
            await done()
            dismiss()
        } catch {
            err = "没连上，再点一次"
        }
    }
}

// MARK: - 续费日

private struct RenewTarget: Identifiable {
    let name: String
    var id: String { name }
}

private struct RenewSheet: View {
    let name: String
    let current: String
    let done: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var busy = false

    private static let ymd: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai"); f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("续费日", selection: $date, displayedComponents: .date)
                    .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
                if !current.isEmpty {
                    Button("清掉续费日", role: .destructive) { Task { await send("") } }
                }
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("算了") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("存") { Task { await send(Self.ymd.string(from: date)) } }.disabled(busy)
                }
            }
        }
        .onAppear { if let d = Self.ymd.date(from: current) { date = d } }
    }

    private func send(_ s: String) async {
        busy = true
        defer { busy = false }
        _ = try? await RingStore.call("/api/usage/book/renew", body: ["name": name, "date": s])
        await done()
        dismiss()
    }
}
