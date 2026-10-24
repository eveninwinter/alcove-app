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
    var unreviewed: Bool { !isDraft && review != "done" && !review.isEmpty }
}

struct ChronMonth: Identifiable {
    let id: String          // 2026-10
    let monthly: ChronItem?
    let weeks: [ChronItem]
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
                       weeks: ((m["weeks"] as? [[String: Any]]) ?? []).map(ChronItem.init))
        }
    }
}

struct ChronicleRoomView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var m = ChronicleModel()
    @State private var expanded: Set<String> = []
    @State private var openItem: ChronItem?
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    private var ink: SanctusCardInk { _ = houseAppearance; return SanctusCardInk() }
    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0 }
    private var safeBottom: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.bottom ?? 0 }

    var body: some View {
        let ink = self.ink
        ZStack(alignment: .topLeading) {
            (ink.dark ? HP.rgb(0x1B1C20) : HP.rgb(0xEFEFED)).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header(ink)
                    if m.loading {
                        ProgressView().tint(ink.sub).frame(maxWidth: .infinity).padding(.top, 40)
                    } else if m.failed || m.months.isEmpty {
                        Text(m.failed ? "没连上，下拉或者退出再进一次" : "还没有月篇和周篇")
                            .font(.system(size: 11.5, design: .serif)).foregroundColor(ink.sub)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        ForEach(Array(m.months.enumerated()), id: \.element.id) { i, mo in
                            monthBlock(mo, open: i == 0 || expanded.contains(mo.id), ink)
                        }
                    }
                    Color.clear.frame(height: safeBottom + 24)
                }
                .padding(.horizontal, 16)
            }
            .ignoresSafeArea(edges: .top)
            .refreshable { await m.load() }
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

    // MARK: 页头

    private func header(_ ink: SanctusCardInk) -> some View {
        VStack(spacing: 0) {
            (Text("CHRONICLE · ").font(SanctusPageFont.corm(8)) + Text("家账").font(.system(size: 8, design: .serif)))
                .tracking(2.6).foregroundColor(ink.kicker)
                .frame(height: 44)
            Text("kept, month by month").font(SanctusCardFont.script(34))
                .foregroundColor(ink.dark ? HP.rgb(0xE4E4E7) : HP.rgb(0x2A2A2E))
                .padding(.top, 12)
            Text("月篇 10 号、20 号、月底各写一次 · 周篇周日过完写")
                .font(.system(size: 10.5, design: .serif)).foregroundColor(ink.sub).padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, safeTop)
        .padding(.bottom, 18)
    }

    // MARK: 一个月

    @ViewBuilder private func monthBlock(_ mo: ChronMonth, open: Bool, _ ink: SanctusCardInk) -> some View {
        let n = ChronFmt.month(mo.id)
        (Text("\(ChronFmt.en[n - 1]) · ").font(SanctusCardFont.kicker()) + Text(ChronFmt.cn[n - 1]).font(.system(size: 7.5, design: .serif)))
            .tracking(2.25).foregroundColor(ink.kicker)
            .padding(.horizontal, 2).padding(.bottom, 8).padding(.top, 6)
        if let it = mo.monthly {
            monthCard(it, ink).padding(.bottom, 4)
        }
        if open {
            ForEach(Array(mo.weeks.enumerated()), id: \.element.id) { i, w in
                weekRow(w, last: i == mo.weeks.count - 1, ink)
            }
        } else if !mo.weeks.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text("这个月的周篇 ").font(.system(size: 10.5, design: .serif)).foregroundColor(ink.sub)
                    + Text("\(mo.weeks.count)").font(SanctusPageFont.corm(12.5)).foregroundColor(ink.body)
                    + Text(" 篇").font(.system(size: 10.5, design: .serif)).foregroundColor(ink.sub)
                Spacer(minLength: 0)
                Text("展开 ＋").font(.system(size: 10.5, design: .serif)).foregroundColor(ink.link)
            }
            .padding(.horizontal, 2).padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { _ = expanded.insert(mo.id) } }
        }
        Color.clear.frame(height: 18)
    }

    private func monthCard(_ it: ChronItem, _ ink: SanctusCardInk) -> some View {
        HPShell(ink: ink) {
            VStack(alignment: .leading, spacing: 0) {
                (Text("MONTH · ").font(SanctusCardFont.kicker()) + Text("月篇").font(.system(size: 7.5, design: .serif)))
                    .tracking(2.25).foregroundColor(ink.kicker)
                Text(it.name).font(.system(size: 15, design: .serif))
                    .foregroundColor(ink.dark ? HP.rgb(0xE4E4E7) : HP.rgb(0x2A2A2E))
                    .lineSpacing(3).padding(.top, 7)
                    .fixedSize(horizontal: false, vertical: true)
                if !it.excerpt.isEmpty {
                    Text(it.excerpt + "……").font(.system(size: 11, design: .serif)).foregroundColor(ink.sub)
                        .lineSpacing(5).lineLimit(3).padding(.top, 7)
                }
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(ChronFmt.grouped(it.chars)).font(SanctusPageFont.corm(12.5)).foregroundColor(ink.body)
                    Text(" 字").font(.system(size: 10, design: .serif)).foregroundColor(ink.sub)
                    if !it.edited.isEmpty { editedPill(it.edited, ink).padding(.leading, 8) }
                    if it.unreviewed { pendingPill(ink).padding(.leading, 6) }
                    Spacer(minLength: 0)
                    Text("写到 ").font(.system(size: 10, design: .serif)).foregroundColor(ink.sub)
                    Text(ChronFmt.md(it.end)).font(SanctusPageFont.corm(12.5)).foregroundColor(ink.body)
                }
                .padding(.top, 10)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { openItem = it }
    }

    private func weekRow(_ w: ChronItem, last: Bool, _ ink: SanctusCardInk) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(ChronFmt.md(w.start)) — \(ChronFmt.md(w.end))").font(SanctusPageFont.corm(12.5)).foregroundColor(ink.sub)
                    .frame(width: 84, alignment: .leading)
                Text(w.name).font(.system(size: 12, design: .serif)).foregroundColor(ink.body).lineLimit(1)
                Spacer(minLength: 4)
                if !w.edited.isEmpty { editedPill(w.edited, ink) }
                if w.unreviewed { pendingPill(ink) }
                Text("\(w.chars)").font(SanctusPageFont.corm(11.5)).foregroundColor(ink.sub)
            }
            .contentShape(Rectangle())
            .onTapGesture { openItem = w }
            if w.draftID > 0 {
                // #4295：这周写全的底稿，单独点
                HStack(spacing: 6) {
                    Text("底稿").font(.system(size: 10.5, design: .serif)).tracking(1).foregroundColor(ink.link)
                    Text(ChronFmt.grouped(w.draftChars)).font(SanctusPageFont.corm(11.5)).foregroundColor(ink.sub)
                    Text("字 ›").font(.system(size: 10, design: .serif)).foregroundColor(ink.sub)
                    if !w.draftEdited.isEmpty { editedPill(w.draftEdited, ink) }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 94)
                .contentShape(Rectangle())
                .onTapGesture { openItem = ChronItem(draftOf: w) }
            }
        }
        .padding(.horizontal, 2).padding(.vertical, 10)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(ink.frame).frame(height: 0.6) } }
    }

    private func pendingPill(_ ink: SanctusCardInk) -> some View {
        Text("他还没看").font(.system(size: 9, design: .serif)).tracking(1)
            .foregroundColor(ink.sub)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .overlay(Capsule().stroke(ink.frame, style: StrokeStyle(lineWidth: 0.8, dash: [2, 2])))
    }

    private func editedPill(_ by: String, _ ink: SanctusCardInk) -> some View {
        Text(by == "her" ? "你改过" : "他改过").font(.system(size: 9, design: .serif)).tracking(1)
            .foregroundColor(ink.link)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .overlay(Capsule().stroke(ink.hair, lineWidth: 0.6))
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
                            ? "底稿是这周写全的那份，不放进开窗，月篇从它写。保存前自动留一份旧版；改完下次写月篇就用你改的。"
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
            (Text(item.isMonth ? "MONTH · " : item.isDraft ? "DRAFT · " : "WEEK · ").font(SanctusPageFont.corm(8))
                + Text(item.isMonth ? "月篇" : item.isDraft ? "这周的底稿" : "周篇").font(.system(size: 8, design: .serif)))
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
