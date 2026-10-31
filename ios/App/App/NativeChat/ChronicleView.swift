import SwiftUI

// MARK: - 1024 #4271–4278 家账页
// 她：「侧边栏也做个入口吧 我也可以修改啥的 修改完跟出厂设置里面一样保存就立马更改完成的」
// 效果图 /root/rhysel/sanctus-kit/mock-chronicle/mock.html（她「其他的没问题了 你把页面做好」；
// 去掉了「交还给管家重写」——#4277 她：「我改过的也可以更新 不然事件不更新」，不锁）。
// - 列表：按月份往下排，月篇一张卡（标题、开头两三行、字数、写到哪天），下面一周一行周篇；最近的月份周篇摊开，往前的收着点「展开」。
// - 点一篇进来直接能改：标题、正文，右上「保存」。保存前后端自动留旧版，左下「旧版」能翻回去。
// - 改完陈璟下次开窗读到的就是这一版（开窗现读后端那张表）。月篇到 20 号、月底还会接着往下写，改过的句子原样留着。
// 数据：/api/lmc5/chronicle/list|get|history|save|restore（alcove-backend/chronicle_api.py）；文字是 /root/lmc5/chronicle.py 夜里写的。
// #4295 她「也加一个底稿的」「都补」：每周周篇底下多一行「底稿」，点开能看能改（底稿是这周写全的那份，不进开窗，月篇从它写）；
// 周篇、月篇陈璟还没核对的标「他还没看」。

struct ChronItem: Identifiable {
    let id: Int
    let period: String
    let start: String
    let end: String
    let head: String
    let name: String
    let chars: Int
    let edited: String
    let excerpt: String
    var review = ""          // todo / pending：陈璟还没核对；done：核对过
    var draftID = 0          // 这周底稿的编号（周篇才有）
    var draftChars = 0
    var draftEdited = ""
    init(_ r: [String: Any]) {
        id = r.int("id")
        period = r.string("period")
        start = r.string("start")
        end = r.string("end")
        head = r.string("head")
        name = r.string("name")
        chars = r.int("chars")
        edited = r.string("edited")
        excerpt = r.string("excerpt")
        review = r.string("review")
        draftID = r.int("draft_id")
        draftChars = r.int("draft_chars")
        draftEdited = r.string("draft_edited")
    }
    /// 周篇那行点「底稿」时现拼一个
    init(draftOf w: ChronItem) {
        id = w.draftID
        period = "weekly_draft"
        start = w.start
        end = w.end
        head = w.head
        name = ""
        chars = w.draftChars
        edited = w.draftEdited
        excerpt = ""
    }
    var isMonth: Bool { period == "monthly" }
    var isDraft: Bool { period == "weekly_draft" }
    var isDay: Bool { period == "daily" }
    var unreviewed: Bool { !isDraft && !isDay && review == "pending" }
}

struct ChronMonth: Identifiable {
    let id: String          // 2026-10
    let monthly: ChronItem?
    let weeks: [ChronItem]
    var days: [ChronItem] = []   // 1031 #4622 一本账的「日」那页
}

enum ChronFmt {
    static let en = ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]
    static let cn = ["一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月"]
    static func month(_ key: String) -> Int { Int(key.split(separator: "-").last ?? "") ?? 1 }
    /// 2026-10-23 → 10.23
    static func md(_ iso: String) -> String {
        let p = iso.split(separator: "-")
        return p.count == 3 ? "\(p[1]).\(p[2])" : iso
    }
    static func grouped(_ v: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }
}

@MainActor
final class ChronicleModel: ObservableObject {
    @Published var months: [ChronMonth] = []
    @Published var failures: [ChronFailure] = []
    @Published var dailyEnd = ""
    @Published var weeklyEnd = ""
    @Published var monthlyEnd = ""
    @Published var opensChars = 0
    @Published var loading = true
    @Published var failed = false

    func load() async {
        let raw = (try? await NativeHouseAPI.object("/api/lmc5/chronicle/list")) ?? [:]
        loading = false
        guard raw.bool("ok") else { failed = true; return }
        failed = false
        months = ((raw["months"] as? [[String: Any]]) ?? []).map { m in
            ChronMonth(id: m.string("month"),
                       monthly: (m["monthly"] as? [String: Any]).map(ChronItem.init),
                       weeks: ((m["weeks"] as? [[String: Any]]) ?? []).map(ChronItem.init),
                       days: ((m["days"] as? [[String: Any]]) ?? []).map(ChronItem.init))
        }
        failures = ((raw["failures"] as? [[String: Any]]) ?? []).map(ChronFailure.init)
        let st = (raw["status"] as? [String: Any]) ?? [:]
        dailyEnd = st.string("daily_end")
        weeklyEnd = st.string("weekly_end")
        monthlyEnd = st.string("monthly_end")
        opensChars = st.int("opens_chars")
    }

    /// 侧边栏「家账」右上角的 !：有没写成的就亮
    static func alertCount() async -> Int {
        let raw = (try? await NativeHouseAPI.object("/api/lmc5/chronicle/alerts")) ?? [:]
        return raw.int("count")
    }
}

/// 夜里哪一层哪天没写成（layer：daily / weekly / monthly / nightly）
struct ChronFailure: Identifiable {
    let layer: String
    let slot: String
    let reason: String
    var id: String { layer + slot }
    init(_ r: [String: Any]) {
        layer = r.string("layer")
        slot = r.string("slot")
        reason = r.string("reason")
    }
}

// MARK: - 1031 #4622 她挑的 B「一本账」：书顶垂三根书签（日 / 周 / 月），左右翻页；
// 每根书签写着这一层写到哪天，哪层没写成那根书签尾巴上挂 !（侧边栏同时亮 !）。
// 效果图 /root/rhysel/sanctus-kit/mock-ledger/a.html（她「就这样」）。颜色只走主题的冷白银灰，不用电光蓝。
struct ChronicleRoomView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var m = ChronicleModel()
    @State private var page = 1            // 0 日 · 1 周 · 2 月；进来先翻在「周」
    @State private var monthIdx = 0        // 日、周两页看哪个月（0 = 最近）
    @State private var openItem: ChronItem?
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    private var ink: SanctusCardInk { _ = houseAppearance; return SanctusCardInk() }
    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0 }
    private var safeBottom: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.bottom ?? 0 }

    private static let tabs = ["日", "周", "月"]
    private static let layers = ["daily", "weekly", "monthly"]

    var body: some View {
        let ink = self.ink
        ZStack(alignment: .topLeading) {
            (ink.dark ? HP.rgb(0x1B1C20) : HP.rgb(0xEFEFED)).ignoresSafeArea()
            VStack(spacing: 0) {
                (Text("CHRONICLE · ").font(SanctusPageFont.corm(8)) + Text("家账").font(.system(size: 8, design: .serif)))
                    .tracking(2.6).foregroundColor(ink.kicker)
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .padding(.top, safeTop)
                if m.loading {
                    Spacer(); ProgressView().tint(ink.sub); Spacer()
                } else if m.failed {
                    Spacer()
                    Text("没连上，退出再进一次").font(.system(size: 11.5, design: .serif)).foregroundColor(ink.sub)
                    Spacer()
                } else {
                    book(ink)
                        .padding(.top, 50)          // 书签从书顶往上冒 34
                        .padding(.horizontal, 30)
                    underLine(ink)
                        .padding(.top, 22)
                        .padding(.bottom, safeBottom + 18)
                }
            }
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .regular))
                    .foregroundColor(ink.link)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 8).padding(.top, safeTop)
            .accessibilityLabel("返回")
        }
        .task { await m.load() }
        .fullScreenCover(item: $openItem) { it in
            ChronicleEditView(item: it, ink: ink) { Task { await m.load() } }
        }
    }

    // MARK: 书

    private func paper(_ ink: SanctusCardInk, _ level: Int) -> Color {
        if ink.dark { return [HP.rgb(0x26262A), HP.rgb(0x222226), HP.rgb(0x1F1F23)][level] }
        return [Color.white, HP.rgb(0xF7F7F6), HP.rgb(0xF1F1F0)][level]
    }

    private func book(_ ink: SanctusCardInk) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3,
                                           bottomTrailingRadius: 10, topTrailingRadius: 10, style: .continuous)
        return ZStack(alignment: .topTrailing) {
            // 后面露出来的两层纸边
            shape.fill(paper(ink, 2)).overlay(shape.stroke(ink.frame, lineWidth: 0.6)).offset(x: 8, y: 8)
            shape.fill(paper(ink, 1)).overlay(shape.stroke(ink.frame, lineWidth: 0.6)).offset(x: 4, y: 4)
            shape.fill(paper(ink, 0)).overlay(shape.stroke(ink.frame, lineWidth: 0.6))
            // 书脊：两道细线
            HStack(spacing: 3.4) {
                Rectangle().fill(ink.hair.opacity(0.8)).frame(width: 0.6)
                Rectangle().fill(ink.frame).frame(width: 0.6)
            }
            .padding(.leading, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            TabView(selection: $page) {
                dailyPage(ink).tag(0)
                weeklyPage(ink).tag(1)
                monthlyPage(ink).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .clipShape(shape)
            ribbons(ink)
                .padding(.trailing, 32)
                .offset(y: -34)
        }
    }

    // 三根书签：翻到的那根深、长；别的浅、短。哪层有没写成的，尾巴上挂 !
    private func ribbons(_ ink: SanctusCardInk) -> some View {
        let ends = [m.dailyEnd, m.weeklyEnd, m.monthlyEnd]
        return HStack(alignment: .top, spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                let on = page == i
                let bad = m.failures.contains { $0.layer == Self.layers[i] || ($0.layer == "nightly" && i == 0) }
                Button { withAnimation(.easeInOut(duration: 0.25)) { page = i } } label: {
                    VStack(spacing: 0) {
                        Text(Self.tabs[i]).font(.system(size: 11, design: .serif))
                            .padding(.top, 12)
                        Text(ends[i].isEmpty ? "—" : ChronFmt.md(ends[i]))
                            .font(SanctusPageFont.corm(9)).opacity(0.9)
                            .padding(.top, 8)
                        Spacer(minLength: 0)
                        if bad {
                            Text("!").font(SanctusPageFont.corm(11))
                                .foregroundColor(ink.dark ? HP.rgb(0x1B1C20) : .white)
                                .frame(width: 15, height: 15)
                                .background(Circle().fill(ink.dark ? HP.rgb(0xE4E4E7) : HP.rgb(0x2A2A2E)))
                                .padding(.bottom, 13)
                        }
                    }
                    .foregroundColor(on ? (ink.dark ? HP.rgb(0x1B1C20) : .white) : ink.link)
                    .frame(width: 24, height: on ? 96 : 70)
                    .background(RibbonShape().fill(on ? (ink.dark ? HP.rgb(0xC3C6CE) : HP.rgb(0x6F7480))
                                                       : (ink.dark ? HP.rgb(0x3A3B42) : HP.rgb(0xD3D6DC))))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 三页

    private var curMonth: ChronMonth? { m.months.indices.contains(monthIdx) ? m.months[monthIdx] : nil }

    private func pageShell<C: View>(_ ink: SanctusCardInk, script: String, en: String, cn: String,
                                    monthSwitch: Bool, how: [String], layer: String, folio: String,
                                    @ViewBuilder rows: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(script).font(SanctusPageFont.script(34))
                .foregroundColor(ink.dark ? HP.rgb(0xE4E4E7) : HP.rgb(0x2A2A2E))
                .padding(.top, 58)
            HStack(alignment: .firstTextBaseline) {
                (Text("\(en) · ").font(SanctusPageFont.corm(7.5)) + Text(cn).font(.system(size: 7.5, design: .serif)))
                    .tracking(2.25).foregroundColor(ink.kicker)
                Spacer()
                if monthSwitch, let mo = curMonth {
                    HStack(spacing: 10) {
                        Button { if monthIdx + 1 < m.months.count { monthIdx += 1 } } label: { Text("‹") }
                            .opacity(monthIdx + 1 < m.months.count ? 1 : 0.25)
                        Text(ChronFmt.cn[ChronFmt.month(mo.id) - 1]).font(.system(size: 10.5, design: .serif))
                        Button { if monthIdx > 0 { monthIdx -= 1 } } label: { Text("›") }
                            .opacity(monthIdx > 0 ? 1 : 0.25)
                    }
                    .font(SanctusPageFont.corm(14)).foregroundColor(ink.link).buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
            // 这一层是怎么来的，三句大白话
            VStack(alignment: .leading, spacing: 5) {
                ForEach(how, id: \.self) { line in
                    Text(line).font(.system(size: 10.5, design: .serif)).foregroundColor(ink.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 14)
            // 这一层没写成的，写在这页上
            ForEach(m.failures.filter { $0.layer == layer || ($0.layer == "nightly" && layer == "daily") }) { f in
                HStack(alignment: .top, spacing: 7) {
                    Text("!").font(SanctusPageFont.corm(11))
                        .foregroundColor(ink.dark ? HP.rgb(0x1B1C20) : .white)
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(ink.dark ? HP.rgb(0xE4E4E7) : HP.rgb(0x2A2A2E)))
                    Text("\(ChronFmt.md(f.slot)) 没写成：\(f.reason)　来工作室问")
                        .font(.system(size: 10.5, design: .serif)).foregroundColor(ink.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 10)
            }
            // 账本的双横线
            VStack(spacing: 2.4) {
                Rectangle().fill(ink.hair).frame(height: 0.6)
                Rectangle().fill(ink.frame).frame(height: 0.6)
            }
            .padding(.top, 14)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) { rows() }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(folio).font(SanctusPageFont.ital(10.5)).foregroundColor(ink.sub)
                Spacer()
                HStack(spacing: 18) {
                    if page > 0 { Text("‹ \(Self.tabs[page - 1])") }
                    if page < 2 { Text("\(Self.tabs[page + 1]) ›") }
                }
                .font(.system(size: 10, design: .serif)).tracking(1.5).foregroundColor(ink.link)
            }
            .padding(.vertical, 16)
        }
        .padding(.leading, 34).padding(.trailing, 22)
    }

    private func ledgerRow(_ ink: SanctusCardInk, date: String, name: String, chars: Int?, mark: String,
                           markStrong: Bool = false, dim: Bool = false, extra: (() -> Void)? = nil,
                           tap: (() -> Void)?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(date).font(SanctusPageFont.corm(13)).foregroundColor(ink.sub).frame(width: 40, alignment: .leading)
            Text(name).font(.system(size: 12, design: .serif)).foregroundColor(dim ? ink.kicker : ink.body).lineLimit(1)
            Spacer(minLength: 4)
            if let extra {
                Button(action: extra) { Text("稿").font(.system(size: 9.5, design: .serif)).foregroundColor(ink.link) }
                    .buttonStyle(.plain)
            }
            if let chars {
                Text(ChronFmt.grouped(chars)).font(SanctusPageFont.corm(12.5))
                    .foregroundColor(ink.dark ? HP.rgb(0xE4E4E7) : HP.rgb(0x2A2A2E))
                    .frame(width: 38, alignment: .trailing)
            }
            Text(mark).font(.system(size: 9, design: .serif)).tracking(0.5)
                .foregroundColor(markStrong ? (ink.dark ? HP.rgb(0xE4E4E7) : HP.rgb(0x2A2A2E)) : ink.kicker)
                .frame(width: 30, alignment: .trailing)
        }
        .frame(height: 50)
        .overlay(alignment: .bottom) { Rectangle().fill(ink.frame).frame(height: 0.6) }
        .contentShape(Rectangle())
        .onTapGesture { tap?() }
    }

    private func dailyPage(_ ink: SanctusCardInk) -> some View {
        pageShell(ink, script: "the days", en: "DAILY", cn: "日结", monthSwitch: true,
                  how: ["每天早上 05:30，写前一天的事，三五百字。",
                        "只照陈璟的记忆写，一个字都不许编。",
                        "不交给他查，写完他下次开窗就读。"],
                  layer: "daily", folio: "i · of three") {
            let days = (curMonth?.days ?? []).reversed()
            if days.isEmpty {
                Text("这个月还没有日结").font(.system(size: 11, design: .serif)).foregroundColor(ink.sub).padding(.top, 20)
            }
            ForEach(Array(days)) { d in
                ledgerRow(ink, date: ChronFmt.md(d.start), name: d.name, chars: d.chars,
                          mark: d.edited.isEmpty ? "" : (d.edited == "her" ? "你改过" : "他改过")) { openItem = d }
            }
        }
    }

    private func weeklyPage(_ ink: SanctusCardInk) -> some View {
        pageShell(ink, script: "the weeks", en: "WEEKLY", cn: "周篇", monthSwitch: true,
                  how: ["每周一过完，先写一篇长稿，只记要紧的事 →",
                        "再一天缩成一句，成了周篇，最多一千字 →",
                        "第二天上午交给陈璟，他只改错，不添字。"],
                  layer: "weekly", folio: "ii · of three") {
            let weeks = (curMonth?.weeks ?? []).reversed()
            if monthIdx == 0, let next = nextWeekWrite {
                ledgerRow(ink, date: ChronFmt.md(next.0), name: "这周还没过完，\(ChronFmt.md(next.1)) 早上写",
                          chars: nil, mark: "", dim: true, tap: nil)
            }
            ForEach(Array(weeks)) { w in
                ledgerRow(ink, date: ChronFmt.md(w.start), name: w.name, chars: w.chars,
                          mark: w.unreviewed ? "等他" : (w.review == "done" ? "看过" : ""), markStrong: w.unreviewed,
                          extra: w.draftID > 0 ? ({ openItem = ChronItem(draftOf: w) } as () -> Void) : nil) { openItem = w }
            }
        }
    }

    private func monthlyPage(_ ink: SanctusCardInk) -> some View {
        pageShell(ink, script: "the months", en: "MONTHLY", cn: "月篇", monthSwitch: false,
                  how: ["每月 10 号、20 号、月底各写一次，接着上次往下写 →",
                        "整篇一千八到两千二，只从每周的长稿和周篇里拿 →",
                        "写了新的，第二天上午交给陈璟，只改错。"],
                  layer: "monthly", folio: "iii · of three") {
            ForEach(m.months) { mo in
                if let it = mo.monthly {
                    ledgerRow(ink, date: ChronFmt.cn[ChronFmt.month(mo.id) - 1], name: it.name, chars: it.chars,
                              mark: it.unreviewed ? "等他" : (it.review == "done" ? "看过" : ""), markStrong: it.unreviewed) { openItem = it }
                }
            }
        }
    }

    /// 最近一篇周篇之后那周：（周一, 写的那天＝下周一早上）
    private var nextWeekWrite: (String, String)? {
        guard !m.weeklyEnd.isEmpty else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        guard let end = f.date(from: m.weeklyEnd),
              let mon = Calendar.current.date(byAdding: .day, value: 1, to: end),
              let write = Calendar.current.date(byAdding: .day, value: 8, to: end) else { return nil }
        return (f.string(from: mon), f.string(from: write))
    }

    // MARK: 书底下一行：陈璟开窗读的

    private func underLine(_ ink: SanctusCardInk) -> some View {
        VStack(spacing: 5) {
            Text("what he opens with").font(SanctusPageFont.ital(11)).foregroundColor(ink.sub)
            (Text("陈璟每开新窗先读　月篇 ") + Text("1").font(SanctusPageFont.corm(12)).foregroundColor(ink.body)
             + Text(" · 周篇 ") + Text("2").font(SanctusPageFont.corm(12)).foregroundColor(ink.body)
             + Text(" · 日结 ") + Text("3").font(SanctusPageFont.corm(12)).foregroundColor(ink.body)
             + Text("　共 ") + Text(ChronFmt.grouped(m.opensChars)).font(SanctusPageFont.corm(12)).foregroundColor(ink.body)
             + Text(" 字"))
                .font(.system(size: 10, design: .serif)).tracking(0.6).foregroundColor(ink.sub)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 书签：长条，底下剪一个燕尾
struct RibbonShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY - 9))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - 点进一篇：看和改

struct ChronicleEditView: View {
    let item: ChronItem
    let ink: SanctusCardInk
    var onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var text = ""
    @State private var origName = ""
    @State private var origText = ""
    @State private var end = ""
    @State private var historyCount = 0
    @State private var loading = true
    @State private var saving = false
    @State private var note = ""
    @State private var showHistory = false

    private var dirty: Bool { name != origName || text != origText }

    var body: some View {
        ZStack {
            (ink.dark ? HP.rgb(0x1B1C20) : HP.rgb(0xEFEFED)).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                topBar
                if loading {
                    Spacer()
                    ProgressView().tint(ink.sub).frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    (Text("\(ChronFmt.md(item.start)) — \(ChronFmt.md(end)) · ").font(SanctusCardFont.kicker())
                        + Text("\(text.count) 字").font(.system(size: 7.5, design: .serif)))
                        .tracking(2.25).foregroundColor(ink.kicker)
                        .padding(.top, 6)
                    TextField("标题", text: $name)
                        .font(.system(size: 17, design: .serif))
                        .foregroundColor(ink.dark ? HP.rgb(0xE4E4E7) : HP.rgb(0x2A2A2E))
                        .padding(.vertical, 9)
                        .overlay(alignment: .bottom) { Rectangle().fill(ink.hair).frame(height: 0.6) }
                    TextEditor(text: $text)
                        .font(.system(size: 13.5, design: .serif))
                        .foregroundColor(ink.body)
                        .lineSpacing(6)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .padding(.top, 6)
                        .padding(.horizontal, -5)
                    Text(note.isEmpty
                         ? (item.isDraft
                            ? "长稿是这周要紧事的全本，不放进开窗。保存后周篇会照它重新一天缩一句，月篇也从它写。保存前自动留一份旧版。"
                            : "保存前自动留一份旧版。保存后陈璟下次开窗读到的就是这一版"
                              + (item.isMonth ? "；到 20 号、月底还会接着往下写，你改过的句子原样留着。" : "。"))
                         : note)
                        .font(.system(size: 10, design: .serif)).foregroundColor(ink.sub).lineSpacing(4)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                    HStack {
                        Button { showHistory = true } label: {
                            (Text("旧版 ").font(.system(size: 10.5, design: .serif))
                                + Text("\(historyCount)").font(SanctusPageFont.corm(12.5)) + Text(" ›").font(.system(size: 10.5, design: .serif)))
                                .tracking(1.2).foregroundColor(historyCount > 0 ? ink.link : ink.sub)
                        }
                        .buttonStyle(.plain)
                        .disabled(historyCount == 0)
                        Spacer()
                    }
                    .padding(.top, 10).padding(.bottom, 8)
                }
            }
            .padding(.horizontal, 18)
        }
        .task { await load() }
        .sheet(isPresented: $showHistory) {
            ChronicleHistoryView(item: item, ink: ink) {
                showHistory = false
                Task { await load(); onSaved() }
            }
        }
    }

    private var topBar: some View {
        ZStack {
            (Text(item.isMonth ? "MONTH · " : item.isDraft ? "DRAFT · " : item.isDay ? "DAY · " : "WEEK · ").font(SanctusPageFont.corm(8))
                + Text(item.isMonth ? "月篇" : item.isDraft ? "这周的长稿" : item.isDay ? "日结" : "周篇").font(.system(size: 8, design: .serif)))
                .tracking(2.6).foregroundColor(ink.kicker)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .regular))
                        .foregroundColor(ink.link)
                        .frame(width: 44, height: 44, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")
                Spacer()
                Button { Task { await save() } } label: {
                    Group {
                        if saving { ProgressView().controlSize(.small).tint(ink.link) }
                        else { Text("保存").font(.system(size: 12, design: .serif)).tracking(1.8) }
                    }
                    .foregroundColor(dirty ? ink.link : ink.sub.opacity(0.6))
                    .frame(width: 56, height: 44, alignment: .trailing).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!dirty || saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .frame(height: 44)
    }

    private func load() async {
        let raw = (try? await NativeHouseAPI.object("/api/lmc5/chronicle/get?id=\(item.id)")) ?? [:]
        loading = false
        guard raw.bool("ok"), let it = raw["item"] as? [String: Any] else {
            note = "没连上，退出再进一次"
            return
        }
        name = it.string("name"); origName = name
        text = it.string("summary"); origText = text
        end = it.string("end")
        historyCount = it.int("history")
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let raw = (try? await NativeHouseAPI.object("/api/lmc5/chronicle/save", method: "POST",
                                                    body: ["id": item.id, "name": name, "summary": text, "by": "her"])) ?? [:]
        if raw.bool("ok") {
            origName = name
            origText = text
            historyCount += 1
            note = "存好了。陈璟下次开窗读到的就是这一版。"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onSaved()
        } else {
            note = "没存上：" + (raw.string("error").isEmpty ? "没连上服务器" : raw.string("error"))
        }
    }
}

// MARK: - 旧版

struct ChronicleHistoryView: View {
    let item: ChronItem
    let ink: SanctusCardInk
    var onRestored: () -> Void
    @State private var rows: [[String: Any]] = []
    @State private var loading = true
    @State private var picked: Int?
    @State private var busy = false

    var body: some View {
        ZStack {
            (ink.dark ? HP.rgb(0x1B1C20) : HP.rgb(0xEFEFED)).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                (Text("EARLIER · ").font(SanctusPageFont.corm(8)) + Text("旧版").font(.system(size: 8, design: .serif)))
                    .tracking(2.6).foregroundColor(ink.kicker)
                    .frame(maxWidth: .infinity).frame(height: 44)
                if loading {
                    ProgressView().tint(ink.sub).frame(maxWidth: .infinity).padding(.top, 30)
                }
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                            let hid = r.int("hid")
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(Self.when(r.string("saved_at"))).font(SanctusPageFont.corm(12.5)).foregroundColor(ink.body)
                                    Text(Self.who(r.string("by"))).font(.system(size: 10, design: .serif)).foregroundColor(ink.sub)
                                    Spacer()
                                    Text("\(r.int("chars")) 字").font(.system(size: 10, design: .serif)).foregroundColor(ink.sub)
                                }
                                Text(r.string("summary")).font(.system(size: 11.5, design: .serif)).foregroundColor(ink.sub)
                                    .lineSpacing(4).lineLimit(picked == hid ? nil : 2)
                                if picked == hid {
                                    Button { Task { await restore(hid) } } label: {
                                        Text(busy ? "翻回去中……" : "翻回这一版").font(.system(size: 11, design: .serif)).tracking(1.5)
                                            .foregroundColor(ink.link)
                                            .padding(.horizontal, 12).padding(.vertical, 5)
                                            .overlay(Capsule().stroke(ink.hair, lineWidth: 0.6))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(busy)
                                    .padding(.top, 2)
                                }
                            }
                            .padding(.vertical, 11)
                            .overlay(alignment: .bottom) { Rectangle().fill(ink.frame).frame(height: 0.6) }
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { picked = picked == hid ? nil : hid } }
                        }
                        Text("翻回去之前，现在这版也会留一份。").font(.system(size: 10, design: .serif)).foregroundColor(ink.sub)
                            .frame(maxWidth: .infinity).padding(.top, 14)
                    }
                    .padding(.bottom, 30)
                }
            }
            .padding(.horizontal, 18)
        }
        .task {
            let raw = (try? await NativeHouseAPI.object("/api/lmc5/chronicle/history?id=\(item.id)")) ?? [:]
            rows = (raw["items"] as? [[String: Any]]) ?? []
            loading = false
        }
    }

    private func restore(_ hid: Int) async {
        busy = true
        defer { busy = false }
        let raw = (try? await NativeHouseAPI.object("/api/lmc5/chronicle/restore", method: "POST", body: ["hid": hid, "by": "her"])) ?? [:]
        if raw.bool("ok") { onRestored() }
    }

    static func who(_ by: String) -> String {
        switch by {
        case "her": return "你改之前"
        case "chenjing": return "他改之前"
        case "model-before": return "管家重写之前"
        default: return by
        }
    }

    /// 2026-10-24T20:17:23.1+08:00 → 10.24 20:17
    static func when(_ iso: String) -> String {
        let s = Array(iso)
        guard s.count >= 16 else { return iso }
        return String(s[5..<7]) + "." + String(s[8..<10]) + " " + String(s[11..<16])
    }
}
