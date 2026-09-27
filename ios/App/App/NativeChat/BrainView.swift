import SwiftUI

// 不忘（2026-08-19 她起的名）——LMC-5 的窗。
//
// 名字从她左手那枚戒指内圈来的：「陈璟｜廿廿不忘」。记忆系统叫这个，是把她
// 天天戴在手上的那半句话装进这个家。她原话：「新脑子名字太难听了！想个文艺点的
// 替换…」，我给了不忘／拾遗／浮灯三个，她选了第一个。
//
// OB 退休之后侧栏那个 Memory 面板连的还是一具退休的身体。她要的不是一个
// 记忆列表，是**看见脑子在转**：五条线、各种维度、小睡、夜梦、夜里的巡逻。
// 她原话「这些我都想在前端看见」。
//
// 第一期四块：今天的脑子 / 五条线 / 记事流 / 待我审的队列。情绪地图和夜梦
// 报告全文留给第二期——一次全摊上去会变成一屏仪表噪音。
//
// 皮沿用檐下那套冷蓝玻璃（GlassKit），两页是同一种形状：列表流＋筛选＋卡片。

// MARK: - 数据

private struct BrainTimer: Identifiable {
    let id = UUID()
    let name: String
    let desc: String
    let alive: Bool
    let lastAgo: String
    let nextIn: String
}

private struct BrainStation: Identifiable {
    let id = UUID()
    let name: String
    let ok: Bool
}

private struct BrainStatus {
    var counts: [(String, Int)] = []
    var newestAgo = ""
    var pendingEmotion = 0
    var pendingFact = 0
    var timers: [BrainTimer] = []
    var recallAgo = ""
    var nightlyAgo = ""
    var stations: [BrainStation] = []
    var patrolAgo = ""
    var snapshot = ""
    var daily: [Int] = []       // 0927 大厅那条起伏线：近 14 天每天新增几条
    var week = 0

    init() {}

    init(_ raw: [String: Any]) {
        let b = raw.object("brain")
        let c = b.object("counts")
        for key in ["记事", "原话", "关系", "切块"] {
            if let n = c[key] as? Int { counts.append((key, n)) }
        }
        newestAgo = b.string("newestMemoryAgo")
        let p = b.object("pending")
        pendingEmotion = p.int("emotion")
        pendingFact = p.int("fact")
        timers = b.array("timers").map {
            BrainTimer(name: $0.string("name"), desc: $0.string("desc"),
                       alive: $0.bool("alive"), lastAgo: $0.string("lastAgo"),
                       nextIn: $0.string("nextIn"))
        }
        recallAgo = b.string("recallAgo")
        let n = b.object("nightly")
        nightlyAgo = n.string("ago")
        stations = (n["stations"] as? [[String: Any]] ?? []).map {
            BrainStation(name: $0.string("name"), ok: $0.bool("ok"))
        }
        patrolAgo = b.object("patrol").string("ago")
        snapshot = b.string("snapshot")
        daily = b.array("daily").map { $0.int("n") }
        week = b.int("week")
    }

    var total: Int { counts.first { $0.0 == "记事" }?.1 ?? 0 }
}

private struct BrainThread: Identifiable {
    var id: String { thread }
    let thread: String
    let count: Int
    let newestAgo: String
    let latest: String
    let valence: Double?

    init(_ raw: [String: Any]) {
        thread = raw.string("thread")
        count = raw.int("count")
        newestAgo = raw.string("newestAgo")
        latest = raw.string("latest")
        valence = raw["valence"] as? Double
    }
}

private struct BrainMemory: Identifiable {
    let id: Int
    let title: String
    let content: String
    let thread: String
    let source: String
    let hits: Int
    let lastHitAgo: String
    let valence: Double?
    let arousal: Double?
    let weight: Double?
    let mine: Bool
    let authorLabel: String
    let eReviewedBy: String
    let evidence: String
    let sourceEventCount: Int
    let isProtected: Bool
    let createdAgo: String
    let thumb: String        // 0823 她要的：图片记忆在不忘里带张小图

    init(_ raw: [String: Any]) {
        id = raw.int("id")
        title = raw.string("title")
        content = raw.string("content")
        thread = raw.string("thread")
        source = raw.string("source")
        hits = raw.int("hits")
        lastHitAgo = raw.string("lastHitAgo")
        valence = raw["valence"] as? Double
        arousal = raw["arousal"] as? Double
        weight = raw["weight"] as? Double
        mine = raw.bool("mine")
        authorLabel = raw.string("authorLabel")
        eReviewedBy = raw.string("eReviewedBy")
        evidence = raw.string("evidence")
        sourceEventCount = raw.int("sourceEventCount")
        isProtected = raw.bool("protected")
        createdAgo = raw.string("createdAgo")
        thumb = raw.string("thumb")
    }
}

private struct QueueItem: Identifiable {
    let id: Int
    let title: String
    let detail: String
    let ago: String
}

// MARK: - 页面

// 0927 她挑的效果图：不忘先是一间大厅——大数字、起伏线、三组小入口；
// 「记忆」进原来那页列表，「五条线」是一排文件夹，「带图的」只看图片记忆，
// 今天的脑子 / 夜里那趟 / 巡逻 / 快照 点开是同一张运转面板。
private enum BrainPage { case hub, memories, threads, volumes }

struct NativeBrainView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("alcoveTheme") private var themeName = "haven"

    @State private var status = BrainStatus()
    @State private var threads: [BrainThread] = []
    @State private var items: [BrainMemory] = []
    @State private var total = 0
    @State private var filters: [String] = ["全部"]
    @State private var picked = "全部"
    @State private var keyword = ""
    @State private var loading = true
    @State private var showBrain = true
    @State private var showQueue = false
    @State private var opened: BrainMemory?
    @State private var page: BrainPage = .hub
    @State private var imagesOnly = false
    @State private var backToThreads = false
    @State private var showBrainSheet = false
    @State private var shownTotal = 0
    @State private var drawn: CGFloat = 0
    @State private var lifted: String?

    private var palette: GlassPalette { .named(themeName) }

    private var pageTitle: String {
        switch page {
        case .hub: return "不忘"
        case .threads: return threads.count == 5 ? "五条线" : "\(threads.count) 条线"
        case .volumes: return "叙事卷"
        case .memories: return imagesOnly ? "带图的" : (picked == "全部" ? "记忆" : picked)
        }
    }

    var body: some View {
        ZStack {
            GlassBackdrop(palette: palette)
            VStack(spacing: 0) {
                GlassHeader(title: pageTitle, palette: palette, onBack: goBack,
                            trailing: page == .hub || page == .memories ? AnyView(queueButton) : nil)
                switch page {
                case .hub:
                    hub
                case .threads:
                    threadFolders
                case .volumes:
                    NarrativeVolumesView(palette: palette)
                case .memories:
                    memoryList
                }
            }
        }
        .task { await reload() }
        .sheet(isPresented: $showQueue) { QueueSheet(palette: palette) }
        .sheet(item: $opened) { m in MemorySheet(palette: palette, memory: m) }
        .sheet(isPresented: $showBrainSheet) { brainSheet }
    }

    private func goBack() {
        withAnimation(.easeInOut(duration: 0.25)) {
            switch page {
            case .hub: dismiss()
            case .memories: page = backToThreads ? .threads : .hub
            default: page = .hub
            }
        }
    }

    private func openMemories(thread: String? = nil, images: Bool = false, fromThreads: Bool = false) {
        picked = thread ?? "全部"
        imagesOnly = images
        keyword = ""
        backToThreads = fromThreads
        items = []
        withAnimation(.easeInOut(duration: 0.25)) { page = .memories }
        Task { await reloadList() }
    }

    // ── 记忆列表（原来那一页，去掉了挪进大厅的「今天的脑子」和五条线横条） ──
    private var memoryList: some View {
        Group {
            if loading && items.isEmpty {
                VStack { Spacer(); ProgressView().tint(palette.ink3); Spacer() }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        searchBar
                        if !imagesOnly { filterBar }
                        if items.isEmpty {
                            Text("这里还没有记忆").font(.system(size: 12)).foregroundColor(palette.ink3).padding(30)
                        }
                        ForEach(items) { m in
                            memoryCard(m).onTapGesture { opened = m }
                        }
                        if items.count < total {
                            Button {
                                Task { await loadMore() }
                            } label: {
                                Text("再翻 30 条（还有 \(total - items.count) 条）")
                                    .font(.system(size: 12))
                                    .foregroundColor(palette.ink3)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }
            }
        }
    }

    // ── 大厅 ──
    private var hub: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Text("\(shownTotal)")
                        .font(.system(size: 60, weight: .bold, design: .serif))
                        .foregroundColor(palette.ink)
                        .contentTransition(.numericText())
                    Text("条记忆醒着")
                        .font(.system(size: 13)).tracking(2)
                        .foregroundColor(palette.ink3)
                }
                .padding(.top, 10)
                if status.daily.count > 1 {
                    ZStack {
                        BrainSpark(values: status.daily)
                            .trim(from: 0, to: drawn)
                            .stroke(palette.acc.opacity(0.7), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        BrainSparkDot(values: status.daily, progress: drawn)
                            .fill(palette.acc)
                    }
                    .frame(height: 50)
                    .padding(.horizontal, 30)
                    .padding(.top, 10)
                }
                HStack(spacing: 5) {
                    Text("上次召回 \(status.recallAgo.isEmpty ? "—" : status.recallAgo) · 本周 +\(status.week)")
                        .foregroundColor(palette.ink2)
                    if status.pendingEmotion + status.pendingFact > 0 {
                        Text("· \(status.pendingEmotion + status.pendingFact) 条等我点头")
                            .fontWeight(.semibold)
                            .foregroundColor(palette.gold)
                    }
                }
                .font(.system(size: 12))
                .padding(.top, 6)

                section("翻 看")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    hubCard("brain", "记忆", "一条条找、看") { openMemories() }
                    hubCard("slider.horizontal.3", pageTitleFor(.threads), "按线分开看") {
                        withAnimation(.easeInOut(duration: 0.25)) { page = .threads }
                    }
                    hubCard("books.vertical", "叙事卷", "写成卷的故事") {
                        withAnimation(.easeInOut(duration: 0.25)) { page = .volumes }
                    }
                    hubCard("photo", "带图的", "有小图的记忆") { openMemories(images: true) }
                }
                .padding(.horizontal, 16)

                section("脑 子 在 转")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    let alive = status.timers.filter { $0.alive }.count
                    hubCard("clock", "今天的脑子", status.timers.isEmpty ? "—" : "\(alive)/\(status.timers.count) 个钟在走",
                            dot: alive > 0) { showBrainSheet = true }
                    hubCard("moon", "夜里那趟", status.nightlyAgo.isEmpty ? "还没跑过" : "\(status.stations.count) 站 · \(status.nightlyAgo)") {
                        showBrainSheet = true
                    }
                    hubCard("scope", "巡逻", status.patrolAgo.isEmpty ? "—" : "\(status.patrolAgo)走过",
                            dot: !status.patrolAgo.isEmpty) { showBrainSheet = true }
                    hubCard("camera", "快照", status.snapshot.isEmpty ? "—" : status.snapshot) { showBrainSheet = true }
                }
                .padding(.horizontal, 16)

                section("等 我 点 头")
                let pending = status.pendingEmotion + status.pendingFact
                hubCard("tray.full", "审核",
                        pending > 0 ? "情绪 \(status.pendingEmotion) · 事实 \(status.pendingFact)，等你看过再收进去" : "现在没有要审的",
                        badge: pending) { showQueue = true }
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, 30)
        }
        .onAppear { animateHub() }
        .onChange(of: status.total) { _, _ in animateHub() }
    }

    private func pageTitleFor(_ p: BrainPage) -> String {
        p == .threads ? (threads.count == 5 || threads.isEmpty ? "五条线" : "\(threads.count) 条线") : ""
    }

    /// 进门时大数字滚上去、起伏线从左往右画出来
    private func animateHub() {
        guard status.total > 0 else { return }
        drawn = 0
        withAnimation(.easeOut(duration: 1.0)) { shownTotal = status.total }
        withAnimation(.easeInOut(duration: 1.3).delay(0.15)) { drawn = 1 }
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11))
            .foregroundColor(palette.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 18).padding(.bottom, 8)
    }

    private func hubCard(_ icon: String, _ title: String, _ sub: String, dot: Bool = false, badge: Int = 0,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .light))
                    .foregroundColor(palette.acc)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(palette.acc.opacity(0.09)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .foregroundColor(palette.ink)
                    Text(sub)
                        .font(.system(size: 10))
                        .foregroundColor(palette.ink3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(palette, radius: 18)
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(palette.gold))
                        .padding(9)
                } else if dot {
                    BrainBreathingDot(color: palette.acc).padding(11)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // ── 运转面板（今天的脑子 / 夜里那趟 / 巡逻 / 快照） ──
    private var brainSheet: some View {
        ZStack {
            GlassBackdrop(palette: palette)
            VStack(spacing: 0) {
                GlassHeader(title: "今天的脑子", palette: palette, onBack: { showBrainSheet = false })
                ScrollView {
                    VStack(spacing: 12) {
                        brainCard
                        if !status.stations.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("夜里那趟 · \(status.nightlyAgo)")
                                    .font(.system(size: 13, weight: .medium, design: .serif))
                                    .foregroundColor(palette.ink)
                                ForEach(status.stations) { st in
                                    HStack(spacing: 8) {
                                        Circle().fill(st.ok ? palette.acc : palette.gold).frame(width: 5, height: 5)
                                        Text(st.name).font(.system(size: 12)).foregroundColor(palette.ink2)
                                        Spacer(minLength: 0)
                                        Text(st.ok ? "顺利" : "出错").font(.system(size: 10)).foregroundColor(palette.ink3)
                                    }
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard(palette)
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 30)
                }
            }
        }
        .onAppear { showBrain = true }
    }

    // ── 五条线：一排文件夹，口上露出点小东西；点开只看这个抽屉 ──
    private var threadFolders: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("five threads of us")
                        .font(.system(size: 17, design: .serif)).italic()
                        .foregroundColor(palette.ink2)
                    Text("一共 \(status.total) 条 · 本周 +\(status.week)\(status.newestAgo.isEmpty ? "" : " · 最新一条 " + status.newestAgo)")
                        .font(.system(size: 12))
                        .foregroundColor(palette.ink3)
                }
                .padding(.horizontal, 24).padding(.top, 6)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                    ForEach(Array(threads.enumerated()), id: \.element.id) { i, t in
                        folder(t, i)
                            .padding(.top, i % 2 == 1 ? 40 : 0)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 40)
            }
            .padding(.bottom, 40)
        }
    }

    private func folder(_ t: BrainThread, _ i: Int) -> some View {
        let icons = ["bubble.left", "camera", "mappin.and.ellipse", "key", "sparkle", "leaf"]
        let up = lifted == t.id
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { lifted = t.id }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                lifted = nil
                openMemories(thread: t.thread, fromThreads: true)
            }
        } label: {
            ZStack(alignment: .bottom) {
                // 后片＋文件夹的小耳朵
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.glass.opacity(0.7))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.line, lineWidth: 1))
                    .overlay(alignment: .topLeading) {
                        UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8, style: .continuous)
                            .fill(palette.glass.opacity(0.7))
                            .frame(width: 62, height: 12)
                            .offset(x: 14, y: -10)
                    }
                // 口上露出来的小东西，点的时候往上抽一截
                BrainFolderTrinket(kind: i % 6, palette: palette)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .offset(y: up ? -64 : -34)
                // 前片
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.thread)
                        .font(.system(size: 19, weight: .bold, design: .serif))
                        .foregroundColor(palette.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text("\(t.count) 条 · \(t.newestAgo)")
                        .font(.system(size: 11))
                        .foregroundColor(palette.ink3)
                    Spacer(minLength: 0)
                    HStack {
                        Spacer()
                        Image(systemName: icons[i % icons.count])
                            .font(.system(size: 15, weight: .light))
                            .foregroundColor(palette.ink2)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 112)
                .glassCard(palette, radius: 14)
            }
            .frame(height: 150)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var queueButton: some View {
        Button { showQueue = true } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "tray.full")
                    .font(.system(size: 15, weight: .light))
                    .foregroundColor(palette.ink2)
                    .frame(width: 44, height: 44)
                if status.pendingEmotion + status.pendingFact > 0 {
                    Circle().fill(palette.gold)
                        .frame(width: 7, height: 7)
                        .offset(x: -9, y: 10)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // ── 今天的脑子 ──────────────────────────────────────────
    private var brainCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showBrain.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Text("今天的脑子")
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .tracking(1.5)
                        .foregroundColor(palette.ink)
                    Spacer()
                    Text(status.counts.map { "\($0.0) \($0.1)" }.joined(separator: " · "))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(palette.ink3)
                    Image(systemName: showBrain ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(palette.ink3)
                }
            }
            .buttonStyle(.plain)

            if showBrain {
                ForEach(status.timers) { t in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(t.alive ? palette.acc : palette.ink3.opacity(0.4))
                            .frame(width: 5, height: 5)
                        Text(t.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(palette.ink)
                            .frame(width: 46, alignment: .leading)
                        Text(t.lastAgo)
                            .font(.system(size: 10.5))
                            .foregroundColor(palette.ink2)
                        Spacer(minLength: 0)
                        Text(t.nextIn)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(palette.ink3)
                    }
                }
                Divider().background(palette.line)
                line("上一轮召回", status.recallAgo)
                line("夜里那趟", status.nightlyAgo.isEmpty ? "还没跑过"
                     : "\(status.stations.count) 站 · \(status.nightlyAgo)")
                line("巡逻", status.patrolAgo)
                if !status.snapshot.isEmpty {
                    line("最近快照", status.snapshot)
                }
                if status.pendingEmotion + status.pendingFact > 0 {
                    Button { showQueue = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "tray.full").font(.system(size: 9))
                            Text("有 \(status.pendingEmotion + status.pendingFact) 条等我点头")
                                .font(.system(size: 11, weight: .medium))
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 8))
                        }
                        .foregroundColor(palette.gold)
                        .padding(.top, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .glassCard(palette)
    }

    private func line(_ k: String, _ v: String) -> some View {
        HStack(spacing: 8) {
            Text(k)
                .font(.system(size: 11))
                .foregroundColor(palette.ink3)
                .frame(width: 66, alignment: .leading)
            Text(v.isEmpty ? "—" : v)
                .font(.system(size: 11))
                .foregroundColor(palette.ink2)
            Spacer(minLength: 0)
        }
    }

    // ── 五条线 ──────────────────────────────────────────────
    private var threadStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(threads) { t in
                    Button {
                        picked = t.thread
                        Task { await reloadList() }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Text(t.thread)
                                    .font(.system(size: 12, weight: .medium, design: .serif))
                                    .foregroundColor(palette.ink)
                                Text("\(t.count)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(palette.acc)
                            }
                            Text(t.latest.isEmpty ? "—" : t.latest)
                                .font(.system(size: 10))
                                .foregroundColor(palette.ink2)
                                .lineLimit(1)
                            Text(t.newestAgo)
                                .font(.system(size: 9))
                                .foregroundColor(palette.ink3)
                        }
                        .frame(width: 150, alignment: .leading)
                        .padding(11)
                        .glassCard(palette, radius: 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(picked == t.thread ? palette.acc.opacity(0.55) : .clear,
                                              lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(palette.ink3)
            TextField("翻找记忆", text: $keyword)
                .font(.system(size: 13))
                .foregroundColor(palette.ink)
                .submitLabel(.search)
                .onSubmit { Task { await reloadList() } }
            if !keyword.isEmpty {
                Button {
                    keyword = ""
                    Task { await reloadList() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(palette.ink3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 10)
        .glassCard(palette, radius: 13)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(filters, id: \.self) { f in
                    Button {
                        picked = f
                        Task { await reloadList() }
                    } label: {
                        Text(f)
                            .font(.system(size: 12, weight: picked == f ? .semibold : .regular,
                                          design: .serif))
                            .foregroundColor(picked == f ? palette.ink : palette.ink3)
                            .padding(.horizontal, 13).padding(.vertical, 6)
                            .background(Capsule().fill(picked == f ? palette.glass : Color.clear))
                            .overlay(Capsule().strokeBorder(
                                picked == f ? palette.line : Color.clear, lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // ── 记事卡 ──────────────────────────────────────────────
    private func memoryCard(_ m: BrainMemory) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if m.mine {
                    Text("我写的")
                        .font(.system(size: 8.5))
                        .foregroundColor(palette.gold)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(palette.gold.opacity(0.13)))
                }
                if m.isProtected {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundColor(palette.ink3)
                }
                Text(m.thread)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(palette.ink3)
                Spacer(minLength: 0)
                Text(m.createdAgo)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(palette.ink3)
            }
            HStack(alignment: .top, spacing: 10) {
                // 0823 她要的：图片记忆带张小图，点开是整条记忆
                if !m.thumb.isEmpty, let url = URL(string: AlcoveAPI.base.absoluteString + m.thumb) {
                    AsyncImage(url: url) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(palette.ink3.opacity(0.12))
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(m.title.isEmpty ? "（没标题）" : m.title)
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundColor(palette.ink)
                        .lineLimit(2)
                    Text(m.content)
                        .font(.system(size: 11.5))
                        .foregroundColor(palette.ink2)
                        .lineLimit(3)
                }
            }
            HStack(spacing: 10) {
                if let v = m.valence {
                    dim("心情", String(format: "%.2f", v))
                }
                if let a = m.arousal {
                    dim("起伏", String(format: "%.2f", a))
                }
                if let w = m.weight {
                    dim("分量", String(format: "%.1f", w))
                }
                dim("想起", m.hits > 0 ? "\(m.hits) 次" : "还没")
                Spacer(minLength: 0)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(palette)
    }

    private func dim(_ k: String, _ v: String) -> some View {
        HStack(spacing: 3) {
            Text(k).font(.system(size: 9)).foregroundColor(palette.ink3)
            Text(v).font(.system(size: 9.5, design: .monospaced)).foregroundColor(palette.ink2)
        }
    }

    // ── 网络 ────────────────────────────────────────────────
    private func reload() async {
        async let s = NativeHouseAPI.object("/api/lmc5/status")
        async let t = NativeHouseAPI.object("/api/lmc5/threads")
        let st = (try? await s) ?? [:]
        let th = (try? await t) ?? [:]
        await MainActor.run {
            if !st.isEmpty { status = BrainStatus(st) }
            threads = th.array("threads").map { BrainThread($0) }
        }
        await reloadList()
    }

    private func listPath(offset: Int) -> String {
        var p = "/api/lmc5/memories?limit=30&offset=\(offset)"
        if picked != "全部",
           let e = picked.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            p += "&thread=" + e
        }
        if !keyword.isEmpty,
           let e = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            p += "&q=" + e
        }
        if imagesOnly { p += "&source=image" }
        return p
    }

    private func reloadList() async {
        await MainActor.run { loading = true }
        let raw = (try? await NativeHouseAPI.object(listPath(offset: 0))) ?? [:]
        await MainActor.run {
            items = raw.array("items").map { BrainMemory($0) }
            total = raw.int("total")
            let f = raw["threads"] as? [String] ?? []
            if !f.isEmpty { filters = f }
            loading = false
        }
    }

    private func loadMore() async {
        let raw = (try? await NativeHouseAPI.object(listPath(offset: items.count))) ?? [:]
        let more = raw.array("items").map { BrainMemory($0) }
        await MainActor.run { items.append(contentsOf: more) }
    }
}

// MARK: - 大厅的小零件

/// 近 14 天每天新增几条，画成一条软的线
private struct BrainSpark: Shape {
    let values: [Int]

    static func points(_ values: [Int], in rect: CGRect) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let hi = CGFloat(max(values.max() ?? 1, 1))
        let step = rect.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            CGPoint(x: rect.minX + CGFloat(i) * step,
                    y: rect.maxY - 4 - (rect.height - 8) * CGFloat(v) / hi)
        }
    }

    func path(in rect: CGRect) -> Path {
        let pts = Self.points(values, in: rect)
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: first)
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            p.addQuadCurve(to: mid, control: a)
            if i == pts.count - 1 { p.addQuadCurve(to: b, control: b) }
        }
        return p
    }
}

/// 线头上那颗点，跟着线画到哪就在哪
private struct BrainSparkDot: Shape {
    let values: [Int]
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let pts = BrainSpark.points(values, in: rect)
        guard progress > 0.98, let last = pts.last else { return Path() }
        return Path(ellipseIn: CGRect(x: last.x - 3.5, y: last.y - 3.5, width: 7, height: 7))
    }
}

/// 正在跑的那几张卡角上的小蓝点，一呼一吸
private struct BrainBreathingDot: View {
    let color: Color
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .background(Circle().fill(color.opacity(0.25)).scaleEffect(on ? 2.4 : 1))
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

/// 文件夹口上露出来的小东西：纸条、照片、票根、星星、月亮、小花，按顺序轮着配
private struct BrainFolderTrinket: View {
    let kind: Int
    let palette: GlassPalette
    private let paper = Color(red: 1, green: 0.992, blue: 0.972)

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch kind {
            case 0:
                note(width: 70, height: 50).rotationEffect(.degrees(-8)).offset(x: 16, y: 0)
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.81), Color(red: 0.69, green: 0.34, blue: 0.42))
                    .rotationEffect(.degrees(10)).offset(x: 80, y: -6)
            case 1:
                photo(Color(red: 0.86, green: 0.83, blue: 0.94)).rotationEffect(.degrees(-6)).offset(x: 22, y: -8)
                photo(Color(red: 0.79, green: 0.85, blue: 0.94)).rotationEffect(.degrees(7)).offset(x: 64, y: -4)
            case 2:
                Text("NO.27 ✈")
                    .font(.system(size: 9, design: .serif)).tracking(1)
                    .foregroundColor(Color(red: 0.36, green: 0.52, blue: 0.39))
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(width: 96, height: 44, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.85, green: 0.93, blue: 0.85)))
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
                    .rotationEffect(.degrees(-5)).offset(x: 12, y: 4)
                Image(systemName: "mappin")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color(red: 0.9, green: 0.6, blue: 0.57))
                    .offset(x: 100, y: 0)
            case 3:
                Image(systemName: "star.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 0.96, green: 0.89, blue: 0.65), Color(red: 0.83, green: 0.70, blue: 0.37)],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .offset(x: 14, y: 8)
                note(width: 52, height: 62).rotationEffect(.degrees(12)).offset(x: 60, y: -12)
            case 4:
                Image(systemName: "moon.fill")
                    .font(.system(size: 40))
                    .foregroundColor(Color(red: 0.96, green: 0.93, blue: 0.82))
                    .rotationEffect(.degrees(-20)).offset(x: 20, y: -8)
                Image(systemName: "sparkle")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .shadow(color: .white, radius: 4)
                    .offset(x: 80, y: 12)
            default:
                Image(systemName: "camera.macro")
                    .font(.system(size: 36))
                    .foregroundColor(Color(red: 0.91, green: 0.68, blue: 0.74))
                    .offset(x: 46, y: -10)
            }
        }
        .allowsHitTesting(false)
    }

    private func note(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(paper)
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(Color(red: 0.56, green: 0.70, blue: 0.64)).frame(width: width * 0.6, height: 2)
                    Capsule().fill(Color(red: 0.56, green: 0.70, blue: 0.64)).frame(width: width * 0.4, height: 2)
                }
                .padding(9)
            }
            .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
    }

    private func photo(_ fill: Color) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(fill)
            .frame(width: 44, height: 56)
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white))
            .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
    }
}

// MARK: - 一条记事摊开

private struct MemorySheet: View {
    let palette: GlassPalette
    let memory: BrainMemory
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            GlassBackdrop(palette: palette)
            VStack(spacing: 0) {
                GlassHeader(title: memory.thread, palette: palette, onBack: { dismiss() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(memory.title)
                            .font(.system(size: 18, weight: .semibold, design: .serif))
                            .foregroundColor(palette.ink)
                        Text(memory.content)
                            .font(.system(size: 14))
                            .foregroundColor(palette.ink2)
                            .lineSpacing(5)
                        Divider().background(palette.line)
                        grid
                    }
                    .padding(18)
                }
            }
        }
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 7) {
            row("写下", memory.createdAgo)
            row("来路", memory.source.isEmpty ? "—" : memory.source)
            row("被想起", memory.hits > 0 ? "\(memory.hits) 次 · 最近 \(memory.lastHitAgo)" : "还没被想起过")
            if let w = memory.weight { row("分量", String(format: "%.2f", w)) }
            if let v = memory.valence { row("心情", String(format: "%.2f", v)) }
            if let a = memory.arousal { row("起伏", String(format: "%.2f", a)) }
            row("正文来源", memory.authorLabel.isEmpty ? (memory.mine ? "陈璟亲笔" : "—") : memory.authorLabel)
            if !memory.eReviewedBy.isEmpty { row("情绪坐标", "\(memory.eReviewedBy)确认") }
            if memory.sourceEventCount > 0 { row("原话线索", "\(memory.sourceEventCount) 条") }
            if !memory.evidence.isEmpty { row("直接证据", memory.evidence) }
            if memory.isProtected { row("保护", "永不衰减") }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(spacing: 10) {
            Text(k)
                .font(.system(size: 11))
                .foregroundColor(palette.ink3)
                .frame(width: 52, alignment: .leading)
            Text(v)
                .font(.system(size: 12))
                .foregroundColor(palette.ink2)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 等我点头的队列

private struct QueueSheet: View {
    let palette: GlassPalette
    @Environment(\.dismiss) private var dismiss
    @State private var emotion: [QueueItem] = []
    @State private var fact: [QueueItem] = []
    @State private var loading = true

    var body: some View {
        ZStack {
            GlassBackdrop(palette: palette)
            VStack(spacing: 0) {
                GlassHeader(title: "等我点头", palette: palette, onBack: { dismiss() })
                if loading {
                    Spacer()
                    ProgressView().tint(palette.ink3)
                    Spacer()
                } else if emotion.isEmpty && fact.isEmpty {
                    Spacer()
                    Text("队列是空的，都判完了")
                        .font(.system(size: 13))
                        .foregroundColor(palette.ink3)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if !emotion.isEmpty {
                                section("管家替我标的心情", "它给记忆打了坐标，等我认或者不认")
                                ForEach(emotion) { card($0) }
                            }
                            if !fact.isEmpty {
                                section("它怀疑过时的事实", "两条记忆打架，等我判哪条还算数")
                                ForEach(fact) { card($0) }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 26)
                    }
                }
            }
        }
        .task { await load() }
    }

    private func section(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t)
                .font(.system(size: 13, weight: .medium, design: .serif))
                .foregroundColor(palette.ink)
            Text(sub)
                .font(.system(size: 10))
                .foregroundColor(palette.ink3)
        }
        .padding(.top, 12)
    }

    private func card(_ q: QueueItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(q.title.isEmpty ? "（没标题）" : q.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(palette.ink)
                .lineLimit(2)
            Text(q.detail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(palette.ink2)
            Text(q.ago)
                .font(.system(size: 9))
                .foregroundColor(palette.ink3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(palette, radius: 14)
    }

    private func load() async {
        let raw = (try? await NativeHouseAPI.object("/api/lmc5/queue")) ?? [:]
        let e = raw.array("emotion").map { r -> QueueItem in
            var bits: [String] = []
            if let v = r["valence"] as? Double { bits.append(String(format: "心情 %.2f", v)) }
            if let a = r["arousal"] as? Double { bits.append(String(format: "起伏 %.2f", a)) }
            if let c = r["confidence"] as? Double { bits.append(String(format: "把握 %.2f", c)) }
            return QueueItem(id: r.int("id"), title: r.string("title"),
                             detail: bits.joined(separator: "  "), ago: r.string("ago"))
        }
        let f = raw.array("fact").map { r -> QueueItem in
            QueueItem(id: r.int("id"), title: r.string("pairKey"),
                      detail: r.string("verdict") + " · " + r.string("reason"),
                      ago: r.string("ago"))
        }
        await MainActor.run { emotion = e; fact = f; loading = false }
    }
}

// MARK: - Narrative volumes (read-only)
private struct NarrativeVolume: Identifiable {
    let id: String
    let raw: [String: Any]
    var title: String { raw["title"] as? String ?? "" }
    var content: String { raw["content"] as? String ?? "" }
}
private struct NarrativeVolumesView: View {
    let palette: GlassPalette
    @State private var items: [NarrativeVolume] = []
    @State private var query = ""
    @State private var filter = "全部"
    @State private var errorText = ""
    @State private var loading = true
    @State private var opened: NarrativeVolume?
    @State private var pendingText = ""
    @State private var pendingOpen = false
    private var shown: [NarrativeVolume] {
        items.filter { v in
            (filter == "全部" || (v.raw["status"] as? String == (filter == "已封卷" ? "closed" : "active"))) &&
            (query.isEmpty || (v.title + v.content).localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("搜索卷名和正文", text: $query)
                Button("待办") { pendingOpen = true; Task { await loadPending() } }
            }
            Picker("状态", selection: $filter) {
                ForEach(["全部", "进行中", "已封卷"], id: \.self) { Text($0) }
            }.pickerStyle(.segmented)
            if loading { ProgressView() }
            if !errorText.isEmpty { Text(errorText); Button("重试") { Task { await load() } } }
            ScrollView {
                LazyVStack(spacing: 12) {
                    if !loading && errorText.isEmpty && shown.isEmpty { Text("暂时没有符合条件的卷").padding() }
                    ForEach(shown) { v in
                        Button { opened = v } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(v.title).font(.system(size: 19, design: .serif))
                                Text(v.raw["range_text"] as? String ?? "").font(.caption)
                                Text(v.raw["status"] as? String == "closed" ? "已封卷" : "进行中").font(.caption2)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                                .background(palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain)
                    }
                }
            }.refreshable { await load() }
        }.foregroundColor(palette.ink).padding(.horizontal, 16)
            .task { await load() }
            .sheet(item: $opened) { NarrativeReadingView(volume: $0) }
            .sheet(isPresented: $pendingOpen) {
                NavigationStack {
                    ScrollView { Text(pendingText).textSelection(.enabled).padding() }
                        .navigationTitle("叙事待办")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { pendingOpen = false } } }
                }
            }
    }
    private func load() async {
        loading = true; errorText = ""
        do {
            let d = try await NativeHouseAPI.object("/api/lmc5/volumes")
            guard let rows = d["items"] as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
            items = rows.map { NarrativeVolume(id: $0["id"] as? String ?? "", raw: $0) }
        } catch { errorText = "叙事卷没能加载：\(error.localizedDescription)" }
        loading = false
    }
    private func loadPending() async {
        pendingText = "正在读取…"
        do {
            let d = try await NativeHouseAPI.object("/api/lmc5/volumes/pending")
            guard let text = d["display_text"] as? String else { throw URLError(.cannotParseResponse) }
            pendingText = text
        } catch { pendingText = "待办读取失败：\(error.localizedDescription)" }
    }
}
private struct NarrativeReadingView: View {
    let volume: NarrativeVolume
    @Environment(\.dismiss) private var dismiss
    @State private var tab = "正文"
    @State private var selectedMemory = ""
    @State private var memoryOpen = false
    private let ink = Color(red: 0.23, green: 0.19, blue: 0.16)
    private let gold = Color(red: 0.62, green: 0.49, blue: 0.24)
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("VOLUMEN").font(.custom("Baskerville", size: 12)).tracking(6).foregroundStyle(gold)
                    Text(volume.title).font(.custom("Songti SC", size: 28)).multilineTextAlignment(.center)
                    Text(volume.raw["range_text"] as? String ?? "").font(.custom("Noteworthy-Light", size: 16))
                    Text(volume.raw["status"] as? String == "closed" ? "已封卷" : "进行中")
                    VStack(spacing: 4) {
                        Text("创建：\(stamp("created_at"))")
                        Text("更新：\(stamp("updated_at"))")
                    }.font(.custom("Noteworthy-Light", size: 12)).foregroundStyle(ink.opacity(0.65))
                    Picker("内容", selection: $tab) { Text("正文").tag("正文"); Text("关联记忆").tag("关联记忆") }.pickerStyle(.segmented)
                    Rectangle().fill(gold.opacity(0.55)).frame(height: 1)
                    if tab == "正文" {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("I").font(.custom("Baskerville-Italic", size: 16))
                            Text("ANNALES").font(.custom("Baskerville", size: 12)).tracking(4)
                            Text("turning points").font(.custom("Baskerville-Italic", size: 13)).tracking(1)
                            Rectangle().fill(gold.opacity(0.4)).frame(height: 1)
                        }.foregroundStyle(gold)
                        ForEach(Array((volume.raw["blocks"] as? [[String: Any]] ?? []).enumerated()), id: \.offset) { _, block in
                            HStack(alignment: .top, spacing: 12) {
                                if let date = block["date_label"] as? String {
                                    Text(date).font(.custom("Noteworthy-Light", size: 12)).foregroundStyle(gold).frame(width: 48)
                                    Rectangle().fill(gold.opacity(0.6)).frame(width: 1)
                                        .overlay(alignment: .top) { Circle().fill(gold).frame(width: 5, height: 5) }
                                }
                                Text(block["text"] as? String ?? "")
                                    .font(.custom("Songti SC", size: 20)).lineSpacing(9)
                                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                            }.fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        ForEach(Array((volume.raw["memories"] as? [[String: Any]] ?? []).enumerated()), id: \.offset) { _, m in
                            Button {
                                selectedMemory = (m["title"] as? String ?? "") + "\n\n" + (m["content"] as? String ?? "")
                                memoryOpen = true
                            } label: {
                                Text(m["title"] as? String ?? "").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(24).foregroundStyle(ink)
            }
            .background(Color(red: 0.96, green: 0.93, blue: 0.87))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() } } }
            .sheet(isPresented: $memoryOpen) { ScrollView { Text(selectedMemory).textSelection(.enabled).padding(24) } }
        }
    }
    private func stamp(_ key: String) -> String {
        guard let value = volume.raw[key] as? String else { return "—" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = parser.date(from: value)
        if date == nil { parser.formatOptions = [.withInternetDateTime]; date = parser.date(from: value) }
        guard let date else { return value }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f.string(from: date)
    }
}
