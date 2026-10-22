import SwiftUI
import AVFoundation

// 搜索与收藏（2026-08-19 她要的四件）：
//   · 收藏分单条和整段聊天记录——聊天页多选几条就收成一段，选一条还是单条
//   · 语音、链接也能搜能收——类型筛选下沉到服务端，不打关键词只点"语音"也能捞
//   · 搜索框下面加选项
//
// 1016 #3981–3994 她：两页换成 Sanctus，照「只给你听」那页的做法（效果图 /root/workroom/mock/search-fav/fav2/）：
//   · 顶上标题就是切换：「kept | search」两个花体字跟返回键一行，当前那页大、深，另一页小、淡，点淡的切过去
//   · 下面一行眉标；左边是「我收藏的 / 他收藏的」＋一排筛选（搜索页是搜索框＋一排筛选），右边并排一张淡淡斜着的狼兔吊坠
//   · 收藏分「我的 / 他的」两栏，不混；卡片底下是收的时候写的那句话（她的能写能改，他的只看）
//   · 搜索页月历平时只露一周，点「整月 ›」才铺开；结果按时间并成一张卡，名字和时间只出一次
//
// 跳转高亮走的还是老路子：.alcoveJumpToMessage 带 ts 发出去，ChatView 收到后
// loadAround + 滚过去 + 闪一下。这条链是她点名要守的，换皮不许撞断。

// MARK: - 两页共用的 Sanctus 零件

@MainActor
private enum SF {
    static func script(_ s: CGFloat) -> Font { .custom("PinyonScript-Regular", size: s) }
    static func corm(_ s: CGFloat) -> Font { .custom("CormorantGaramond-Medium", size: s) }
    static func ital(_ s: CGFloat) -> Font { .custom("CormorantGaramondItalic-MediumItalic", size: s) }
    static func song(_ s: CGFloat) -> Font { .system(size: s, design: .serif) }
    static var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0 }
    static var safeBottom: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.bottom ?? 0 }
}

/// 跟「只给你听」同一种磨砂白卡（黑夜深炭灰）
private struct SFGlass: ViewModifier {
    let ink: SanctusCardInk
    var radius: CGFloat = 12.5
    func body(content: Content) -> some View {
        content
            .background(LinearGradient(colors: [ink.fillTop, ink.fillBottom], startPoint: .top, endPoint: .bottom))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius - 4, style: .continuous).stroke(ink.frame, lineWidth: 0.6).padding(5))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(ink.edge, lineWidth: 0.8))
    }
}

/// 底：聊天壁纸糊一下、压一层冷白（跟「只给你听」一样）
private struct SFBackdrop: View {
    let ink: SanctusCardInk
    @ObservedObject private var wall = ChatWallpaperStore.shared
    var body: some View {
        ZStack {
            (ink.dark ? Color(red: 0.10, green: 0.105, blue: 0.125) : Color(red: 0.95, green: 0.953, blue: 0.96))
            ChatWallpaperRenderer(descriptor: wall.descriptor).blur(radius: 14)
            (ink.dark ? Color.black.opacity(0.62) : Color(red: 0.965, green: 0.97, blue: 0.976).opacity(0.5))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// 发丝线：两头淡出
private struct SFHair: View {
    let ink: SanctusCardInk
    var body: some View {
        LinearGradient(stops: [.init(color: ink.hair.opacity(0), location: 0), .init(color: ink.hair, location: 0.12),
                               .init(color: ink.hair, location: 0.88), .init(color: ink.hair.opacity(0), location: 1)],
                       startPoint: .leading, endPoint: .trailing)
            .frame(height: 0.6)
    }
}

/// 顶栏：返回键｜「kept | search」切换｜多选
private struct SFHeader: View {
    let ink: SanctusCardInk
    let onKept: Bool
    let onBack: () -> Void
    let onSwitch: () -> Void
    let picking: Bool
    let onPick: () -> Void

    var body: some View {
        ZStack {
            HStack(alignment: .center, spacing: 19) {
                word("kept", on: onKept)
                Rectangle().fill(ink.hair.opacity(0.9)).frame(width: 0.6, height: 17)
                word("search", on: !onKept)
            }
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .light)).foregroundColor(ink.script)
                        .frame(width: 29, height: 29)
                        .background((ink.dark ? Color.white.opacity(0.08) : Color.white.opacity(0.6)), in: Circle())
                        .overlay(Circle().stroke(ink.edge, lineWidth: 0.7))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: onPick) {
                    Image(systemName: picking ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 15, weight: .light))
                        .foregroundColor(picking ? ink.body : ink.link)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("多选")
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 44)
    }

    @ViewBuilder private func word(_ w: String, on: Bool) -> some View {
        if on {
            Text(w).font(SF.script(31)).foregroundColor(ink.dark ? ink.script : Color(red: 0.31, green: 0.325, blue: 0.37))
                .offset(y: 2)
        } else {
            Button(action: onSwitch) {
                Text(w).font(SF.script(19)).foregroundColor(ink.sub.opacity(0.8))
                    .padding(.vertical, 8).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(y: 4)
        }
    }
}

/// 右边那张淡淡斜着的狼兔吊坠
private struct SFLocket: View {
    let ink: SanctusCardInk
    var body: some View {
        Image("MaskLocket").resizable().scaledToFit()
            .frame(width: 137)
            .colorMultiply(ink.dark ? Color(white: 0.82) : .white)
            .opacity(0.42)
            .rotationEffect(.degrees(-8))
            .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .topTrailing, endPoint: .bottomLeading))
            .allowsHitTesting(false)
    }
}

/// 一排淡淡的小字筛选：选中的深一点，中间小圆点隔开；spread＝铺满整行
private struct SFFilterRow: View {
    let ink: SanctusCardInk
    let options: [(String, String)]
    @Binding var selection: String
    var spread = false
    var onChange: (String) -> Void = { _ in }

    var body: some View {
        HStack(spacing: spread ? 0 : 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, opt in
                if i > 0 {
                    if spread { Spacer(minLength: 2) }
                    Text("·").font(SF.song(8.7)).foregroundColor(ink.sub.opacity(0.6))
                    if spread { Spacer(minLength: 2) }
                }
                Button {
                    selection = opt.0
                    onChange(opt.0)
                } label: {
                    Text(opt.1).font(SF.song(8.7)).tracking(1.2)
                        .foregroundColor(selection == opt.0 ? ink.script : ink.sub.opacity(0.85))
                        .padding(.vertical, 6).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private func sfStamp(_ raw: String) -> String {
    // 「10.15 · 13:01」
    guard raw.count >= 16 else { return raw }
    return "\(raw.dropFirst(5).prefix(2)).\(raw.dropFirst(8).prefix(2)) · \(raw.dropFirst(11).prefix(5))"
}

// MARK: - 搜索

struct GlassSearchView: View {
    var openFavorites: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    @AppStorage("userName") private var userName = "Luna"
    @AppStorage("assistantName") private var assistantName = "陈璟"

    @State private var query = ""
    @State private var results: [ChatMessage] = []
    @State private var filterType = "all"
    @State private var searching = false
    @State private var searched = false
    @State private var selectedDay = ""
    @State private var month = Date()
    @State private var focus = Date()          // 收起来时露的那一周按它算
    @State private var showMonth = false
    @State private var dayCounts: [String: Int] = [:]
    @State private var loadedMonths: Set<String> = []
    @State private var picking = false
    @State private var picked: Set<UUID> = []
    @State private var toast = ""

    private var ink: SanctusCardInk { _ = houseAppearance; return SanctusCardInk() }
    private let types: [(String, String)] = [
        ("all", "全部"), ("text", "文字"), ("image", "图片"), ("audio", "语音"), ("link", "链接")
    ]
    private let calendar = Calendar(identifier: .gregorian)
    private let weekdays = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        let ink = self.ink
        ZStack(alignment: .bottom) {
            SFBackdrop(ink: ink)
            VStack(spacing: 0) {
                SFHeader(ink: ink, onKept: false, onBack: { dismiss() }, onSwitch: openFavorites,
                         picking: picking, onPick: {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        picking.toggle()
                        if !picking { picked.removeAll() }
                    }
                })
                .padding(.top, SF.safeTop + 14)
                Text("SEARCH · 搜索").font(SF.corm(8)).tracking(2.9).foregroundColor(ink.kicker)
                    .padding(.top, 8)
                ZStack(alignment: .topTrailing) {
                    SFLocket(ink: ink).offset(x: 6, y: 2)
                    VStack(alignment: .leading, spacing: 4) {
                        searchField(ink)
                        SFFilterRow(ink: ink, options: types, selection: $filterType, spread: true) { _ in
                            Task { await search() }
                        }
                        .padding(.horizontal, 9)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 130)
                    .padding(.top, 34)
                }
                .padding(.horizontal, 18)
                list(ink)
            }
            if picking && !picked.isEmpty { pickBar(ink) }
            if !toast.isEmpty { toastBar(ink) }
        }
        .task { await loadMonth(Date()) }
    }

    private func searchField(_ ink: SanctusCardInk) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .light)).foregroundColor(ink.sub)
            TextField("", text: $query, prompt: Text("搜聊天记录").foregroundColor(ink.sub))
                .font(SF.song(11.5)).tracking(1.2)
                .foregroundColor(ink.body)
                .submitLabel(.search)
                .onSubmit { Task { await search() } }
            if searching {
                ProgressView().scaleEffect(0.6).tint(ink.sub)
            } else if !query.isEmpty {
                Button { query = ""; results = []; searched = false } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundColor(ink.sub)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background((ink.dark ? Color.white.opacity(0.06) : Color.white.opacity(0.62)), in: Capsule())
        .overlay(Capsule().stroke(ink.edge, lineWidth: 0.7))
        .overlay(Capsule().stroke(ink.frame, lineWidth: 0.5).padding(-0.6))
    }

    private func list(_ ink: SanctusCardInk) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 12) {
                if !searched || !selectedDay.isEmpty { calendarCard(ink) }
                if !selectedDay.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        (Text(dayDots(selectedDay)).font(SF.corm(13)).tracking(1.2)
                         + Text(" · " + weekdayName(selectedDay)).font(SF.song(11)).tracking(1.6))
                            .foregroundColor(ink.body)
                        Spacer()
                        Text("\(results.count) messages").font(SF.ital(10.4)).foregroundColor(ink.sub)
                    }
                    .padding(.horizontal, 4).padding(.top, 6)
                }
                ForEach(groups) { g in group(g, ink: ink) }
                if searched && results.isEmpty && !searching {
                    Text(query.isEmpty ? "这一类还没有" : "没有找到")
                        .font(SF.song(11)).tracking(1.2).foregroundColor(ink.sub)
                        .padding(.top, 40)
                }
                Color.clear.frame(height: SF.safeBottom + 70)
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
        }
    }

    // —— 结果并成卡：同一个人、隔不到五分钟、同一天的连着放 ——
    private struct ResultGroup: Identifiable {
        let id: UUID
        let items: [ChatMessage]
    }

    private var groups: [ResultGroup] {
        var out: [[ChatMessage]] = []
        for m in results {
            if let last = out.last?.last, last.role == m.role,
               abs(m.date.timeIntervalSince(last.date)) < 300,
               calendar.isDate(m.date, inSameDayAs: last.date) {
                out[out.count - 1].append(m)
            } else {
                out.append([m])
            }
        }
        return out.map { ResultGroup(id: $0[0].uid, items: $0) }
    }

    private func group(_ g: ResultGroup, ink: SanctusCardInk) -> some View {
        let first = g.items[0]
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(first.role == "user" ? userName : assistantName).font(SF.ital(12.4)).foregroundColor(ink.script)
                Spacer()
                Text(selectedDay.isEmpty ? sfStamp(first.ts) : String(first.ts.dropFirst(11).prefix(5)))
                    .font(SF.corm(8.3)).tracking(1.6).foregroundColor(ink.sub)
            }
            VStack(alignment: .leading, spacing: 7) {
                ForEach(g.items) { m in line(m, ink: ink) }
            }
            .padding(.top, 9)
        }
        .padding(.horizontal, 18).padding(.top, 15).padding(.bottom, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SFGlass(ink: ink))
    }

    private func line(_ m: ChatMessage, ink: SanctusCardInk) -> some View {
        let isPicked = picked.contains(m.uid)
        return Button {
            if picking {
                if isPicked { picked.remove(m.uid) } else { picked.insert(m.uid) }
            } else {
                NotificationCenter.default.post(name: .alcoveRequestJumpToMessage, object: m.ts)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if picking {
                    Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(isPicked ? ink.body : ink.sub)
                }
                VStack(alignment: .leading, spacing: 3) {
                    if let kind = badge(m) {
                        Text(kind).font(SF.corm(6.6)).tracking(1.6).foregroundColor(ink.link)
                            .padding(.horizontal, 5).padding(.vertical, 0.5)
                            .overlay(Capsule().stroke(ink.pill, lineWidth: 0.6))
                    }
                    if !m.displayText.isEmpty {
                        Text(m.displayText).font(SF.song(12)).tracking(0.6).foregroundColor(ink.body)
                            .lineSpacing(5).lineLimit(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func badge(_ message: ChatMessage) -> String? {
        if message.attachmentType == "audio" { return "VOICE" }
        if message.attachmentType == "image" { return "IMAGE" }
        if message.text.contains("http://") || message.text.contains("https://") { return "LINK" }
        return nil
    }

    // —— 月历：平时一周，「整月 ›」铺开 ——
    private func calendarCard(_ ink: SanctusCardInk) -> some View {
        VStack(spacing: 0) {
            HStack {
                if showMonth {
                    Button { changeMonth(-1) } label: {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .light)).foregroundColor(ink.link)
                            .frame(width: 26, height: 26).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Text(monthTitle(showMonth ? month : focus)).font(SF.corm(8)).tracking(2.9).foregroundColor(ink.kicker)
                if showMonth {
                    Button { changeMonth(1) } label: {
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .light)).foregroundColor(ink.link)
                            .frame(width: 26, height: 26).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showMonth.toggle()
                        if showMonth { month = focus }
                    }
                } label: {
                    Text(showMonth ? "收起 ›" : "整月 ›").font(SF.song(8.7)).tracking(1.6).foregroundColor(ink.link)
                        .padding(.vertical, 6).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 26)
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { w in
                    Text(w).font(SF.song(7.9)).tracking(0.8).foregroundColor(ink.sub).frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 8)
            let cells = showMonth ? monthCells : weekCells
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date { dayCell(date, ink: ink) } else { Color.clear.frame(height: 46) }
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
        .modifier(SFGlass(ink: ink))
    }

    private func dayCell(_ date: Date, ink: SanctusCardInk) -> some View {
        let key = dayKey(date)
        let count = dayCounts[key]
        let on = key == selectedDay
        return Button {
            focus = date
            Task { await showDay(key) }
        } label: {
            VStack(spacing: 0) {
                Text("\(calendar.component(.day, from: date))")
                    .font(SF.corm(19))
                    .foregroundColor(count == nil ? ink.sub.opacity(0.6) : ink.body)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(on ? ink.script.opacity(0.7) : .clear, lineWidth: 0.7))
                Text(count.map { "\($0)" } ?? " ").font(SF.ital(7.9)).foregroundColor(ink.sub)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(count == nil)
    }

    private var weekCells: [Date?] {
        let start = calendar.date(byAdding: .day, value: -(calendar.component(.weekday, from: focus) - 1), to: focus) ?? focus
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.map(Optional.some)
    }

    private var monthCells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let days = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let offset = calendar.component(.weekday, from: interval.start) - 1
        return Array(repeating: nil, count: offset)
            + days.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }
                  .map(Optional.some)
    }

    private func monthTitle(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "MMMM · yyyy"
        return f.string(from: d).uppercased()
    }

    private func dayKey(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.string(from: date)
    }

    private func monthKey(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"; f.timeZone = .current
        return f.string(from: date)
    }

    private func dayDots(_ key: String) -> String {
        // 2026-10-01 → 10.01
        guard key.count >= 10 else { return key }
        return "\(key.dropFirst(5).prefix(2)).\(key.dropFirst(8).prefix(2))"
    }

    private func weekdayName(_ key: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        guard let d = f.date(from: key) else { return "" }
        return "周" + weekdays[calendar.component(.weekday, from: d) - 1]
    }

    private func changeMonth(_ delta: Int) {
        if let d = calendar.date(byAdding: .month, value: delta, to: month) {
            month = d
            Task { await loadMonth(d) }
        }
    }

    /// 一周可能跨两个月：两个月的条数都要
    @MainActor private func loadMonth(_ d: Date) async {
        var keys = [monthKey(d)]
        for c in weekCells.compactMap({ $0 }) where !keys.contains(monthKey(c)) { keys.append(monthKey(c)) }
        for k in keys where !loadedMonths.contains(k) {
            let got = (try? await AlcoveAPI.calendarCounts(month: k)) ?? [:]
            dayCounts.merge(got) { _, new in new }
            loadedMonths.insert(k)
        }
    }

    @MainActor private func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // 不打关键词、只点一类，也要能翻——这是她要的"语音链接也能搜"
        guard !q.isEmpty || filterType != "all" else {
            results = []; searched = false; selectedDay = ""; return
        }
        searching = true
        defer { searching = false }
        results = (try? await AlcoveAPI.searchHistory(
            query: q, type: filterType, limit: 800)) ?? []
        selectedDay = ""
        searched = true
    }

    @MainActor private func showDay(_ day: String) async {
        searching = true
        defer { searching = false }
        filterType = "all"
        query = ""
        results = (try? await AlcoveAPI.searchHistory(day: day, limit: 2000)) ?? []
        selectedDay = day
        searched = true
        await loadMonth(focus)
    }

    @MainActor private func keep() async {
        let chosen = results.filter { picked.contains($0.uid) }
            .sorted { $0.ts < $1.ts }
        guard !chosen.isEmpty else { return }
        try? await AlcoveAPI.favoriteAdd(chosen)
        withAnimation {
            picking = false
            picked.removeAll()
            toast = chosen.count > 1 ? "收成一段了 · \(chosen.count) 条" : "收起来了"
        }
        try? await Task.sleep(nanoseconds: 1_600_000_000)
        withAnimation { toast = "" }
    }

    // 挑几条收起来：多于一条就收成一段聊天记录
    private func pickBar(_ ink: SanctusCardInk) -> some View {
        HStack(spacing: 16) {
            Text("已挑 \(picked.count) 条").font(SF.song(11)).tracking(1.2).foregroundColor(ink.body)
            Spacer()
            Button("取消") { withAnimation { picking = false; picked.removeAll() } }
                .font(SF.song(11)).foregroundColor(ink.sub)
            Button(picked.count > 1 ? "收成一段" : "收起来") { Task { await keep() } }
                .font(SF.song(11)).foregroundColor(ink.script)
        }
        .padding(.horizontal, 20).padding(.vertical, 13)
        .modifier(SFGlass(ink: ink))
        .padding(.horizontal, 18)
        .padding(.bottom, SF.safeBottom + 12)
    }

    private func toastBar(_ ink: SanctusCardInk) -> some View {
        Text(toast).font(SF.song(11)).tracking(1.2).foregroundColor(ink.body)
            .padding(.horizontal, 18).padding(.vertical, 11)
            .modifier(SFGlass(ink: ink))
            .padding(.bottom, SF.safeBottom + 80)
            .transition(.opacity)
    }
}

// MARK: - 收藏

private struct FavoriteMember: Identifiable {
    let id = UUID()
    let ts: String
    let text: String
    let role: String
    let attachmentURL: String
    let attachmentType: String

    init(_ raw: [String: Any]) {
        ts = raw.string("ts")
        text = raw.string("text")
        role = raw.string("role")
        attachmentURL = raw.string("attachment_url")
        attachmentType = raw.string("attachment_type")
    }
}

private struct FavoriteEntry: Identifiable {
    let id: Int
    let ts: String
    let text: String
    let role: String
    let kind: String        // single | thread
    let title: String
    let atype: String       // text | image | audio | link
    let attURL: String
    let members: [FavoriteMember]
    let created: String
    /// 0912：语音收藏带上他自己写的中文翻译（后端按 ts 从原消息里捞）
    let audioZh: String
    /// 1016：谁收的（user＝她 / assistant＝他）、收的时候写的那句话
    let byWho: String
    let note: String
    /// 1022 #4175：他收藏的每条配一张图（后端从她挑的 34 张里按 id 轮着分）＋他收之前说的那句
    let pic: String
    let context: String

    var isThread: Bool { kind == "thread" }
    var isPlayableAudio: Bool { !isThread && atype == "audio" && !attURL.isEmpty }

    init(_ raw: [String: Any]) {
        id = raw.int("id")
        ts = raw.string("ts")
        text = raw.string("text")
        role = raw.string("role")
        kind = raw.string("kind").isEmpty ? "single" : raw.string("kind")
        title = raw.string("title")
        atype = raw.string("atype").isEmpty ? "text" : raw.string("atype")
        attURL = raw.string("att_url")
        members = raw.array("members").map(FavoriteMember.init)
        created = raw.string("created")
        audioZh = raw.string("audio_zh")
        byWho = raw.string("by_who").isEmpty ? "user" : raw.string("by_who")
        note = raw.string("note")
        pic = raw.string("pic")
        context = raw.string("context")
    }
}

/// 收藏页的语音：点圆键直接放，同一时间只放一条
@MainActor
private final class FavAudio: ObservableObject {
    static let shared = FavAudio()
    @Published var playingID: Int?
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    func toggle(_ id: Int, url: URL) {
        if playingID == id { stop(); return }
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        let p = AVPlayer(url: url)
        player = p
        playingID = id
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                             object: p.currentItem, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        p.play()
    }

    func stop() {
        player?.pause()
        player = nil
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
        endObserver = nil
        playingID = nil
    }
}

struct GlassFavoritesView: View {
    var openSearch: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    @AppStorage("userName") private var userName = "Luna"
    @AppStorage("assistantName") private var assistantName = "陈璟"
    @StateObject private var audio = FavAudio.shared

    @State private var entries: [FavoriteEntry] = []
    @State private var by = "user"
    @State private var filter = "all"
    @State private var hisCount = 0
    @State private var loading = true
    @State private var opened: FavoriteEntry?
    @State private var picking = false
    @State private var picked: Set<Int> = []
    @State private var deleting = false
    @State private var sending = false
    @State private var sendError: String?
    @State private var forwardRequest: (ids: [Int], key: String)?
    @State private var noteFor: FavoriteEntry?
    @State private var noteDraft = ""
    /// 1022 #4175「他收藏的」两种看法：grid 胶片格子 / big 大图往下刷（记住上次选的）
    @AppStorage("favHisMode") private var hisMode = "grid"
    @State private var hisFocus: Int?

    private var ink: SanctusCardInk { _ = houseAppearance; return SanctusCardInk() }
    private let filters: [(String, String)] = [
        ("all", "全部"), ("text", "文字"), ("audio", "语音"), ("image", "图片"), ("thread", "聊天记录")
    ]

    var body: some View {
        let ink = self.ink
        ZStack(alignment: .bottom) {
            SFBackdrop(ink: ink)
            VStack(spacing: 0) {
                SFHeader(ink: ink, onKept: true, onBack: { dismiss() }, onSwitch: openSearch,
                         picking: picking, onPick: {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        picking.toggle()
                        if !picking { picked.removeAll() }
                    }
                })
                .padding(.top, SF.safeTop + 14)
                Text("KEPT · 收藏").font(SF.corm(8)).tracking(2.9).foregroundColor(ink.kicker)
                    .padding(.top, 8)
                Text(countLine).font(SF.ital(10)).foregroundColor(ink.sub).padding(.top, 4)
                ZStack(alignment: .topTrailing) {
                    SFLocket(ink: ink).offset(x: 6, y: -6)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 26) {
                            seg("我收藏的", "user", ink)
                            seg("他收藏的", "assistant", ink)
                        }
                        SFFilterRow(ink: ink, options: filters, selection: $filter) { _ in Task { await load() } }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 9)
                    .padding(.top, 34)
                }
                .padding(.horizontal, 18)
                content(ink)
            }
            if picking && !picked.isEmpty { deleteBar(ink) }
        }
        .task { await load() }
        .onDisappear { audio.stop() }
        .alert("发送收藏", isPresented: Binding(get: { sendError != nil }, set: { if !$0 { sendError = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: { Text(sendError ?? "") }
        .alert("为什么收它", isPresented: Binding(get: { noteFor != nil }, set: { if !$0 { noteFor = nil } })) {
            TextField("写一句", text: $noteDraft)
            Button("取消", role: .cancel) {}
            Button("好") { Task { await saveNote() } }
        }
        .sheet(item: $opened) { entry in
            FavoriteThreadSheet(entry: entry, userName: userName, assistantName: assistantName)
        }
    }

    private var countLine: String {
        guard !loading else { return " " }
        let mine = by == "user" ? entries.count : 0
        return by == "user" ? "\(mine) kept · \(hisCount) by him" : "\(entries.count) kept by him"
    }

    private func seg(_ title: String, _ value: String, _ ink: SanctusCardInk) -> some View {
        Button {
            guard by != value else { return }
            by = value
            picked.removeAll(); picking = false
            Task { await load() }
        } label: {
            Text(title).font(SF.song(12)).tracking(2.9)
                .foregroundColor(by == value ? ink.body : ink.sub.opacity(0.85))
                .overlay(alignment: .bottom) {
                    if by == value {
                        Rectangle().fill(ink.script.opacity(0.6)).frame(height: 0.6).padding(.horizontal, 6).offset(y: 6)
                    }
                }
                .padding(.vertical, 4).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func content(_ ink: SanctusCardInk) -> some View {
        if loading {
            Spacer(); ProgressView().tint(ink.sub); Spacer()
        } else if entries.isEmpty {
            Spacer()
            Text(emptyText).font(SF.song(11)).tracking(1.2).foregroundColor(ink.sub)
                .multilineTextAlignment(.center).lineSpacing(5)
            Spacer()
        } else if by == "assistant" {
            hisContent(ink)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                        card(entry, no: entries.count - i, ink: ink)
                    }
                    Color.clear.frame(height: SF.safeBottom + 40)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
            }
        }
    }

    private var emptyText: String {
        if by == "assistant" { return "他还没收过东西" }
        return filter == "thread" ? "还没收过整段的\n在搜索里挑几条就能收成一段" : "还没有收藏"
    }

    private func kindLabel(_ e: FavoriteEntry) -> String {
        if e.isThread { return "THREAD" }
        switch e.atype {
        case "audio": return "VOICE"
        case "image": return "IMAGE"
        case "link": return "LINK"
        default: return "WORDS"
        }
    }

    private func card(_ entry: FavoriteEntry, no: Int, ink: SanctusCardInk) -> some View {
        let isPicked = picked.contains(entry.id)
        let transcript = ChatMessage.stripVoiceTags(entry.text)
        let (en1, en2) = splitFirst(transcript)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if picking {
                    Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: .light)).foregroundColor(isPicked ? ink.body : ink.sub)
                }
                Text("No. \(no)").font(SF.ital(11.6)).foregroundColor(ink.sub)
                Text(kindLabel(entry)).font(SF.corm(6.6)).tracking(1.6).foregroundColor(ink.link)
                    .padding(.horizontal, 5).padding(.vertical, 0.5)
                    .overlay(Capsule().stroke(ink.pill, lineWidth: 0.6))
                Spacer()
                Text(sfStamp(entry.ts)).font(SF.corm(8.3)).tracking(1.6).foregroundColor(ink.sub)
                    .padding(.trailing, entry.isPlayableAudio ? 40 : 0)
            }
            Group {
                if entry.isThread {
                    Text(entry.title.isEmpty ? "聊天记录" : entry.title).font(SF.song(12.8)).tracking(1.2).foregroundColor(ink.body)
                        .padding(.top, 8)
                    Text(entry.text).font(SF.song(10.4)).tracking(0.6).foregroundColor(ink.sub)
                        .lineSpacing(4).lineLimit(3).padding(.top, 5)
                    Text("\(entry.members.count) messages").font(SF.ital(10)).foregroundColor(ink.sub).padding(.top, 4)
                } else if entry.isPlayableAudio {
                    Text(en1.isEmpty ? "a voice note" : en1).font(SF.ital(16.6)).foregroundColor(ink.body)
                        .lineLimit(2).padding(.top, 5).padding(.trailing, 46)
                    let second = entry.audioZh.isEmpty ? en2 : entry.audioZh
                    if !second.isEmpty {
                        Text(second).font(entry.audioZh.isEmpty ? SF.ital(10.4) : SF.song(9.6))
                            .tracking(entry.audioZh.isEmpty ? 0 : 1).foregroundColor(ink.sub)
                            .lineLimit(1).padding(.top, 3).padding(.trailing, 46)
                    }
                } else {
                    if entry.atype == "image", !entry.attURL.isEmpty {
                        AsyncImage(url: AlcoveAPI.attachmentURL(entry.attURL)) { phase in
                            if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) }
                            else { Rectangle().fill(ink.frame) }
                        }
                        .frame(maxWidth: .infinity).frame(height: 150).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8.5, style: .continuous))
                        .padding(.top, 9)
                    }
                    if !entry.text.isEmpty {
                        Text(entry.text).font(SF.song(12.8)).tracking(0.8).foregroundColor(ink.body)
                            .lineSpacing(6).lineLimit(5).padding(.top, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if !entry.note.isEmpty {
                (Text("—  ").foregroundColor(ink.sub.opacity(0.7)) + Text(entry.note).foregroundColor(ink.script))
                    .font(SF.song(10)).tracking(0.8).lineSpacing(4)
                    .padding(.top, 11)
            }
            SFHair(ink: ink).padding(.top, 13).padding(.horizontal, -6)
            HStack {
                Text(entry.byWho == "assistant" ? "kept by him" : "kept by you").font(SF.ital(10.4)).foregroundColor(ink.sub)
                Spacer()
                if entry.byWho == "user" && !picking {
                    Button {
                        noteDraft = entry.note
                        noteFor = entry
                    } label: {
                        Text(entry.note.isEmpty ? "写一句为什么 ›" : "改一改 ›").font(SF.song(8.7)).tracking(1.6).foregroundColor(ink.link)
                            .padding(.vertical, 6).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 18).padding(.top, 15).padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            if entry.isPlayableAudio && !picking {
                Button {
                    audio.toggle(entry.id, url: AlcoveAPI.attachmentURL(entry.attURL))
                } label: {
                    Image(systemName: audio.playingID == entry.id ? "pause.fill" : "play.fill")
                        .font(.system(size: 10)).foregroundColor(ink.script)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(ink.dark ? Color.white.opacity(0.28) : Color(red: 0.47, green: 0.49, blue: 0.53).opacity(0.5), lineWidth: 0.7))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 9).padding(.top, 22)
            }
        }
        .modifier(SFGlass(ink: ink))
        .overlay(RoundedRectangle(cornerRadius: 12.5, style: .continuous)
            .stroke(isPicked ? ink.script.opacity(0.55) : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            if picking {
                if isPicked { picked.remove(entry.id) } else { picked.insert(entry.id) }
            } else if entry.isThread {
                opened = entry
            } else {
                NotificationCenter.default.post(name: .alcoveRequestJumpToMessage, object: entry.ts)
            }
        }
        .contextMenu {
            Button { Task { await forward([entry.id]) } } label: {
                Label("发送到聊天", systemImage: "paperplane")
            }.disabled(sending)
            if entry.byWho == "user" {
                Button(role: .destructive) { Task { await remove(entry) } } label: {
                    Label("不收了", systemImage: "trash")
                }
            }
        }
    }

    // MARK: 他收藏的（1022 #4175，照她点头的效果图 mock-favpics：左格子、右大图）

    private func hisModeRow(_ ink: SanctusCardInk) -> some View {
        HStack(spacing: 14) {
            Spacer()
            ForEach([("grid", "格子"), ("big", "大图")], id: \.0) { key, label in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { hisMode = key }
                } label: {
                    Text(label).font(SF.song(11)).tracking(2.2)
                        .foregroundColor(hisMode == key ? ink.body : ink.sub)
                        .overlay(alignment: .bottom) {
                            if hisMode == key { Rectangle().fill(ink.body).frame(height: 0.7).offset(y: 3) }
                        }
                        .padding(.vertical, 4).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 26).padding(.top, 10)
    }

    /// 按天分组（ts 前 10 位），新的在上
    private var hisDays: [(day: String, items: [FavoriteEntry])] {
        var order: [String] = []
        var map: [String: [FavoriteEntry]] = [:]
        for e in entries {
            let d = String(e.ts.prefix(10))
            if map[d] == nil { order.append(d) }
            map[d, default: []].append(e)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private func dayTitle(_ d: String) -> String {
        guard d.count == 10, let m = Int(d.dropFirst(5).prefix(2)), let dd = Int(d.suffix(2)) else { return d }
        return "\(m)月\(dd)日"
    }

    /// 图右上角那行橙色日期「26 10 21」
    private func filmStamp(_ ts: String) -> String {
        guard ts.count >= 10 else { return "" }
        return "\(ts.dropFirst(2).prefix(2)) \(ts.dropFirst(5).prefix(2)) \(ts.dropFirst(8).prefix(2))"
    }

    private func hisText(_ e: FavoriteEntry) -> String {
        let t = ChatMessage.stripVoiceTags(e.text).trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return e.atype == "audio" ? "一段语音" : (e.atype == "image" ? "一张图" : "")
    }

    private func hisPic(_ e: FavoriteEntry, height: CGFloat?) -> some View {
        AsyncImage(url: AlcoveAPI.attachmentURL(e.pic.isEmpty ? e.attURL : e.pic)) { phase in
            if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) }
            else { Rectangle().fill(ink.frame) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
    }

    @ViewBuilder private func hisContent(_ ink: SanctusCardInk) -> some View {
        hisModeRow(ink)
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                if hisMode == "grid" {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(hisDays, id: \.day) { group in
                            HStack(alignment: .firstTextBaseline) {
                                Text(dayTitle(group.day)).font(SF.song(17)).tracking(1).foregroundColor(ink.dark ? ink.body : Color(red: 0.165, green: 0.165, blue: 0.18))
                                Spacer()
                                Text("\(group.items.count) kept").font(SF.ital(11)).foregroundColor(ink.sub)
                            }
                            .padding(.horizontal, 8).padding(.top, 20).padding(.bottom, 10)
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                ForEach(group.items) { e in hisFrame(e, ink: ink) }
                            }
                        }
                        Color.clear.frame(height: SF.safeBottom + 40)
                    }
                    .padding(.horizontal, 18)
                } else {
                    LazyVStack(spacing: 22) {
                        ForEach(entries) { e in hisBig(e, ink: ink).id(e.id) }
                        Color.clear.frame(height: SF.safeBottom + 40)
                    }
                    .padding(.top, 14)
                }
            }
            .onChange(of: hisMode) { _ in
                guard hisMode == "big", let id = hisFocus else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { proxy.scrollTo(id, anchor: .top) }
            }
        }
    }

    /// 格子：白卡里一张 4:3 的图（右上角橙色日期）、她那句、时间｜kept by him。点一格跳到大图看法的那一条
    private func hisFrame(_ e: FavoriteEntry, ink: SanctusCardInk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.aspectRatio(4.0 / 3.0, contentMode: .fit)
                .overlay(hisPic(e, height: nil))
                .overlay(alignment: .topTrailing) {
                    Text(filmStamp(e.ts)).font(.system(size: 8.5, design: .monospaced)).tracking(1)
                        .foregroundColor(Color(red: 0.91, green: 0.53, blue: 0.35).opacity(0.85))
                        .padding(.top, 6).padding(.trailing, 7)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(hisText(e)).font(SF.song(11.5)).foregroundColor(ink.body)
                .lineSpacing(4).lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
                .padding(.top, 8).padding(.horizontal, 4)
            HStack {
                Text(String(e.ts.dropFirst(11).prefix(5))).font(SF.corm(11)).foregroundColor(ink.sub)
                Spacer()
                Text("kept by him").font(SF.ital(10)).foregroundColor(ink.sub)
            }
            .padding(.top, 6).padding(.horizontal, 4)
        }
        .padding(.horizontal, 7).padding(.top, 7).padding(.bottom, 9)
        .modifier(SFGlass(ink: ink))
        .contentShape(Rectangle())
        .overlay(RoundedRectangle(cornerRadius: 12.5, style: .continuous)
            .stroke(picked.contains(e.id) ? ink.script.opacity(0.55) : .clear, lineWidth: 1))
        .onTapGesture {
            if picking {
                if picked.contains(e.id) { picked.remove(e.id) } else { picked.insert(e.id) }
                return
            }
            hisFocus = e.id
            withAnimation(.easeInOut(duration: 0.18)) { hisMode = "big" }
        }
        .contextMenu { hisMenu(e) }
    }

    /// 大图：整宽一张图往下淡进底色；日期时间、「他：……」、她那句大字、发丝线、why he kept it
    private func hisBig(_ e: FavoriteEntry, ink: SanctusCardInk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            hisPic(e, height: 300)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.6),
                                             .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .bottomTrailing) {
                    Text(filmStamp(e.ts)).font(.system(size: 11, design: .monospaced)).tracking(1.3)
                        .foregroundColor(Color(red: 0.91, green: 0.53, blue: 0.35).opacity(0.85))
                        .padding(.trailing, 22).padding(.bottom, 128)
                }
            VStack(alignment: .leading, spacing: 0) {
                Text(sfStamp(e.ts)).font(SF.corm(10)).tracking(2.5).foregroundColor(ink.sub)
                if !e.context.isEmpty {
                    Text("他：\(e.context)").font(SF.song(12)).foregroundColor(ink.sub)
                        .lineLimit(2).padding(.top, 10)
                }
                HStack(alignment: .top, spacing: 10) {
                    Text(hisText(e)).font(SF.song(19)).foregroundColor(ink.dark ? ink.body : Color(red: 0.165, green: 0.165, blue: 0.18))
                        .lineSpacing(8).frame(maxWidth: .infinity, alignment: .leading)
                    if e.isPlayableAudio {
                        Button { audio.toggle(e.id, url: AlcoveAPI.attachmentURL(e.attURL)) } label: {
                            Image(systemName: audio.playingID == e.id ? "pause.fill" : "play.fill")
                                .font(.system(size: 10)).foregroundColor(ink.script)
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(ink.pill, lineWidth: 0.7))
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 6)
                if !e.note.isEmpty {
                    SFHair(ink: ink).padding(.top, 14)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("why he kept it").font(SF.ital(11)).foregroundColor(ink.sub).fixedSize()
                        Text(e.note).font(SF.song(12)).foregroundColor(ink.script).lineSpacing(4)
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, -22)
        }
        .contentShape(Rectangle())
        .overlay(alignment: .topLeading) {
            if picking {
                Image(systemName: picked.contains(e.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .light)).foregroundColor(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2).padding(16)
            }
        }
        .onTapGesture {
            if picking {
                if picked.contains(e.id) { picked.remove(e.id) } else { picked.insert(e.id) }
                return
            }
            NotificationCenter.default.post(name: .alcoveRequestJumpToMessage, object: e.ts)
        }
        .contextMenu { hisMenu(e) }
    }

    @ViewBuilder private func hisMenu(_ e: FavoriteEntry) -> some View {
        Button { Task { await forward([e.id]) } } label: {
            Label("发送到聊天", systemImage: "paperplane")
        }.disabled(sending)
    }

    /// 语音转文字拆成「第一句（大号斜体）＋后面（小一行）」
    private func splitFirst(_ s: String) -> (String, String) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return ("", "") }
        let enders: Set<Character> = [".", "!", "?", "。", "！", "？", "…"]
        var idx = t.startIndex
        var cut: String.Index?
        while idx < t.endIndex {
            if enders.contains(t[idx]) {
                var j = t.index(after: idx)
                while j < t.endIndex, enders.contains(t[j]) { j = t.index(after: j) }
                if t.distance(from: t.startIndex, to: j) >= 8 { cut = j; break }
                idx = j
                continue
            }
            idx = t.index(after: idx)
        }
        guard let c = cut else { return (t, "") }
        return (String(t[..<c]).trimmingCharacters(in: .whitespaces),
                String(t[c...]).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func deleteBar(_ ink: SanctusCardInk) -> some View {
        HStack(spacing: 16) {
            Text("已选 \(picked.count) 条").font(SF.song(11)).tracking(1.2).foregroundColor(ink.body)
            Spacer()
            Button("取消") { withAnimation { picking = false; picked.removeAll() } }
                .foregroundColor(ink.sub)
            Button(sending ? "发送中" : "发送到聊天") {
                Task { await forward(entries.filter { picked.contains($0.id) }.sorted { $0.ts < $1.ts }.map(\.id)) }
            }
            .foregroundColor(ink.script)
            .disabled(sending || deleting)
            if by == "user" {
                Button(deleting ? "删除中" : "删除", role: .destructive) { Task { await removePicked() } }
                    .disabled(deleting)
            }
        }
        .font(SF.song(11))
        .padding(.horizontal, 20).padding(.vertical, 13)
        .modifier(SFGlass(ink: ink))
        .padding(.horizontal, 18)
        .padding(.bottom, SF.safeBottom + 12)
    }

    @MainActor private func forward(_ ids: [Int]) async {
        guard !sending else { return }
        sending = true
        defer { sending = false }
        if forwardRequest?.ids != ids { forwardRequest = (ids, UUID().uuidString) }
        do {
            let response = try await AlcoveAPI.forwardFavorites(ids: ids, requestID: forwardRequest!.key)
            guard response["ok"] as? Bool == true else {
                sendError = response.string("error"); return
            }
            let record = response["record"] as? [String: Any] ?? [:]
            forwardRequest = nil
            picked.removeAll(); picking = false
            NotificationCenter.default.post(name: .alcoveRequestJumpToMessage, object: record.string("ts"))
        } catch { sendError = "发送未确认，请先查看主聊天。\n" + error.localizedDescription }
    }

    @MainActor private func load() async {
        loading = true
        let kind = filter == "thread" ? "thread" : "all"
        let type = (filter == "thread" || filter == "all") ? "all" : filter
        let raw = (try? await AlcoveAPI.favorites(kind: kind, type: type, by: by)) ?? []
        entries = raw.map(FavoriteEntry.init)
        if by == "user" {
            hisCount = ((try? await AlcoveAPI.favorites(by: "assistant")) ?? []).count
        }
        loading = false
    }

    @MainActor private func saveNote() async {
        guard let e = noteFor else { return }
        let text = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        noteFor = nil
        try? await AlcoveAPI.favoriteNote(id: e.id, note: text)
        await load()
    }

    @MainActor private func remove(_ entry: FavoriteEntry) async {
        try? await AlcoveAPI.favoriteRemove(id: entry.id)
        await load()
    }

    @MainActor private func removePicked() async {
        guard !picked.isEmpty, !deleting else { return }
        deleting = true
        for id in picked { try? await AlcoveAPI.favoriteRemove(id: id) }
        picked.removeAll()
        picking = false
        deleting = false
        await load()
    }
}

// MARK: - 收藏的整段聊天记录，点开逐条排

private struct FavoriteThreadSheet: View {
    let entry: FavoriteEntry
    let userName: String
    let assistantName: String
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    private var ink: SanctusCardInk { _ = houseAppearance; return SanctusCardInk() }

    var body: some View {
        let ink = self.ink
        ZStack {
            SFBackdrop(ink: ink)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .light)).foregroundColor(ink.script)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    VStack(spacing: 4) {
                        Text(entry.title.isEmpty ? "聊天记录" : entry.title).font(SF.song(13)).tracking(3).foregroundColor(ink.body)
                        Text("\(entry.members.count) messages").font(SF.ital(10)).foregroundColor(ink.sub)
                    }
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 8)
                .padding(.top, 18)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(entry.members.enumerated()), id: \.element.id) { index, m in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(m.role == "user" ? userName : assistantName).font(SF.ital(12.4)).foregroundColor(ink.script)
                                    Spacer()
                                    Text(sfStamp(m.ts)).font(SF.corm(8.3)).tracking(1.6).foregroundColor(ink.sub)
                                }
                                if m.attachmentType == "image", !m.attachmentURL.isEmpty {
                                    AsyncImage(url: AlcoveAPI.attachmentURL(m.attachmentURL)) { phase in
                                        if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) }
                                        else { Rectangle().fill(ink.frame) }
                                    }
                                    .frame(maxWidth: .infinity).frame(height: 168).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8.5, style: .continuous))
                                } else if m.attachmentType == "audio" {
                                    Text("VOICE").font(SF.corm(6.6)).tracking(1.6).foregroundColor(ink.link)
                                        .padding(.horizontal, 5).padding(.vertical, 0.5)
                                        .overlay(Capsule().stroke(ink.pill, lineWidth: 0.6))
                                }
                                if !m.text.isEmpty {
                                    Text(m.text).font(SF.song(12.8)).tracking(0.6).foregroundColor(ink.body)
                                        .lineSpacing(5)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.vertical, 13)
                            if index < entry.members.count - 1 { SFHair(ink: ink) }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 24)
                }
            }
        }
    }
}
