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
private enum BrainPage { case hub, memories, threads, volumes, surface, stopwords, wrongbook }

/// 0929：聊天页「不忘」小卡点「打开这条记忆」→ 先记下要找的标题，再开不忘；不忘一进门就按它搜
enum BuwangDeepLink {
    static var search: String?
}

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
    @State private var hubQuery = ""
    @State private var tune: [String: Any] = [:]      // 0928 调参那组卡片上的小字（/lmc5/recall/overview）
    @State private var hubToast = ""
    @ObservedObject private var fontStore = KakaoPackStore.shared

    private var palette: GlassPalette { .named(themeName) }
    private var ink: BuwangInk { BuwangInk(dark: palette.isDark) }

    private var pageTitle: String {
        switch page {
        case .hub, .surface, .stopwords, .wrongbook: return ""      // 0928 这几页的手写标题画在页面里
        case .threads: return threads.count == 5 ? "五条线" : "\(threads.count) 条线"
        case .volumes: return "叙事卷"
        case .memories: return imagesOnly ? "带图的" : (picked == "全部" ? "记忆" : picked)
        }
    }

    var body: some View {
        ZStack {
            BuwangPaper(ink: ink)      // 0928 她要的：纸面、蓝粉白紫、手写体（照 Kakao 那套的温度，不要 AI 味）
            VStack(spacing: 0) {
                GlassHeader(title: pageTitle, palette: palette, onBack: goBack,
                            trailing: page == .memories ? AnyView(queueButton) : nil)
                switch page {
                case .hub:
                    hub
                case .threads:
                    threadFolders
                case .volumes:
                    NarrativeVolumesView(palette: palette)
                case .memories:
                    memoryList
                case .surface:
                    BuwangSurfaceView(ink: ink)
                case .stopwords:
                    BuwangStopwordsView(ink: ink)
                case .wrongbook:
                    BuwangWrongbookView(ink: ink)
                }
            }
            if !hubToast.isEmpty {
                VStack {
                    Spacer()
                    Text(hubToast)
                        .font(BuwangFont.hand(15))
                        .foregroundColor(ink.ink)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Capsule().fill(ink.card).shadow(color: ink.shadow, radius: 8, x: 0, y: 4))
                        .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            await reload()
            if let q = BuwangDeepLink.search, !q.isEmpty {
                BuwangDeepLink.search = nil
                openMemories(search: q)
            }
        }
        .onAppear { BuwangFont.warm() }
        .onReceive(KakaoPackStore.shared.objectWillChange) { _ in KakaoPackStore.shared.ensureFont(id: BuwangFont.handID) }
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

    /// 0927 她抓的：运转面板开着的时候审核页叠不上去，点了没反应——先收面板，再开审核
    private func openQueue() {
        guard showBrainSheet else { showQueue = true; return }
        showBrainSheet = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showQueue = true }
    }

    private func openMemories(thread: String? = nil, images: Bool = false, fromThreads: Bool = false, search: String = "") {
        picked = thread ?? "全部"
        imagesOnly = images
        keyword = search
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
    // 0928 她给的两张参考（梗辞典文件夹 / 别人的不忘大厅）＋效果图 ①：手写标题、大数字、起伏线，
    // 下面「翻看 / 运转 / 调参」三组小卡片；纸面、蓝粉白紫、贴一点胶带。
    private var hub: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                BuwangTitle(ink: ink, zh: "不忘", en: "what we keep")
                    .padding(.top, -6)
                hubSearch
                VStack(spacing: 0) {
                    Text("\(shownTotal)")
                        .font(.system(size: 62, weight: .semibold, design: .serif))
                        .foregroundColor(ink.ink)
                        .contentTransition(.numericText())
                    Text("条记忆醒着")
                        .font(BuwangFont.hand(17)).tracking(2)
                        .foregroundColor(ink.ink2)
                        .padding(.top, -6)
                }
                .padding(.top, 8)
                if status.daily.count > 1 {
                    ZStack {
                        BrainSpark(values: status.daily)
                            .trim(from: 0, to: drawn)
                            .stroke(ink.cherry.opacity(0.75), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        BrainSparkDot(values: status.daily, progress: drawn)
                            .fill(ink.cherry)
                    }
                    .frame(height: 46)
                    .padding(.horizontal, 30)
                    .padding(.top, 6)
                }
                hubStat
                hubGroups
            }
            .padding(.bottom, 34)
        }
        .onAppear { animateHub() }
        .onChange(of: status.total) { _, _ in animateHub() }
    }

    private var hubSearch: some View {
        // 0927 她要的：第一页顶上就能搜，回车进「记忆」页带着这个词
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(ink.ink3)
            TextField("翻找记忆", text: $hubQuery)
                .font(.system(size: 13))
                .foregroundColor(ink.ink)
                .submitLabel(.search)
                .onSubmit {
                    let q = hubQuery.trimmingCharacters(in: .whitespaces)
                    guard !q.isEmpty else { return }
                    hubQuery = ""
                    openMemories(search: q)
                }
            if !hubQuery.isEmpty {
                Button { hubQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(ink.ink3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ink.card)
            .shadow(color: ink.shadow, radius: 6, x: 0, y: 3))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var hubStat: some View {
        let surfaced = tune.int("surfaced_7d")
        let pending = status.pendingEmotion + status.pendingFact
        return HStack(spacing: 4) {
            Text("上次召回 \(status.recallAgo.isEmpty ? "—" : status.recallAgo)")
            Text("·")
            Text("7 天浮现")
            Text("\(surfaced)").foregroundColor(ink.cherry).fontWeight(.semibold)
            Text("· 本周 +\(status.week)")
            if pending > 0 {
                Text("· \(pending) 条等我点头").foregroundColor(ink.cherry)
            }
        }
        .font(.system(size: 11.5))
        .foregroundColor(ink.ink2)
        .padding(.top, 4)
    }

    private var hubGroups: some View {
        let cols = [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)]
        let alive = status.timers.filter { $0.alive }.count
        let pending = status.pendingEmotion + status.pendingFact
        let wrongOpen = tune.int("wrong_open")
        let brainSub = (status.timers.isEmpty ? "—" : "\(alive)/\(status.timers.count) 个钟在走")
            + (status.nightlyAgo.isEmpty ? "" : " · 夜里 \(status.nightlyAgo)")
        let patrolSub = "巡逻 " + (status.patrolAgo.isEmpty ? "—" : status.patrolAgo) + " · 快照 " + (status.snapshot.isEmpty ? "—" : status.snapshot)
        return VStack(spacing: 0) {
            BuwangSection(ink: ink, zh: "翻看", en: "READ")
            LazyVGrid(columns: cols, spacing: 9) {
                BuwangCard(ink: ink, icon: "book", tint: ink.blue, title: "记忆", sub: "一条条找、看") { openMemories() }
                BuwangCard(ink: ink, icon: "line.3.horizontal", tint: ink.pink, title: pageTitleFor(.threads), sub: "按线分开看") {
                    withAnimation(.easeInOut(duration: 0.25)) { page = .threads }
                }
                BuwangCard(ink: ink, icon: "books.vertical", tint: ink.lilac, title: "叙事卷", sub: "写成卷的故事") {
                    withAnimation(.easeInOut(duration: 0.25)) { page = .volumes }
                }
                BuwangCard(ink: ink, icon: "photo", tint: ink.mint, title: "带图的", sub: "有小图的记忆") { openMemories(images: true) }
            }
            .padding(.horizontal, 16)

            BuwangSection(ink: ink, zh: "运转", en: "RUNNING")
            LazyVGrid(columns: cols, spacing: 9) {
                BuwangCard(ink: ink, icon: "clock", tint: ink.blue, title: "今天的脑子", sub: brainSub) { showBrainSheet = true }
                BuwangCard(ink: ink, icon: "tray.full", tint: ink.pink, title: "审核",
                           sub: pending > 0 ? "情绪 \(status.pendingEmotion) · 事实 \(status.pendingFact)" : "现在没有要审的",
                           badge: pending) { openQueue() }
                BuwangCard(ink: ink, icon: "scope", tint: ink.mint, title: "巡逻·快照", sub: patrolSub) { showBrainSheet = true }
            }
            .padding(.horizontal, 16)

            BuwangSection(ink: ink, zh: "调参", en: "TUNING")
            LazyVGrid(columns: cols, spacing: 9) {
                BuwangCard(ink: ink, icon: "water.waves", tint: ink.lilac, title: "浮现", sub: "试问 · 阈值 · 他最近的", tape: ink.lilac) {
                    withAnimation(.easeInOut(duration: 0.25)) { page = .surface }
                }
                BuwangCard(ink: ink, icon: "text.magnifyingglass", tint: ink.mint, title: "召回", sub: "不看的停用词") {
                    withAnimation(.easeInOut(duration: 0.25)) { page = .stopwords }
                }
                BuwangCard(ink: ink, icon: "xmark.square", tint: ink.pink, title: "错题本",
                           sub: wrongOpen > 0 ? "召错的，\(wrongOpen) 道待修" : "召错的记在这", badge: wrongOpen) {
                    withAnimation(.easeInOut(duration: 0.25)) { page = .wrongbook }
                }
                BuwangCard(ink: ink, icon: "character.book.closed", tint: ink.faint, title: "专名库", sub: "等你来写", dashed: true) {
                    showHubToast("专名库等你写好表格，我再开这一页")
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func showHubToast(_ text: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { hubToast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeOut(duration: 0.3)) { hubToast = "" }
        }
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
                    if !t.latest.isEmpty {
                        Text(t.latest)
                            .font(.system(size: 10.5))
                            .foregroundColor(palette.ink2)
                            .lineLimit(1)
                            .padding(.top, 2)
                    }
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
                    Button { openQueue() } label: {
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
        let tu = (try? await NativeHouseAPI.object("/api/lmc5/recall/overview")) ?? [:]
        await MainActor.run {
            if !st.isEmpty { status = BrainStatus(st) }
            threads = th.array("threads").map { BrainThread($0) }
            tune = tu
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

// MARK: - 0928 不忘·调参（试问 / 阈值 / 他最近的 / 停用词 / 错题本）
//
// 她 0928 递了两张参考（梗辞典文件夹、别人的不忘大厅），要：停用词、阈值调试、手动试问、错题本，
// 「有点击互动」「做得好看一点」「参考 Kakao 那套的美化，不要生硬不要像 AI」「字体多用手写体」。
// 效果图 /root/workroom/mock/buwang2/mock.png 她点了头。配色按她 0927 定的：冷白纸、宝宝蓝、樱花粉、
// 淡紫、薄荷，樱桃粉点缀，绝不要黄；夜里中性炭灰。手写字＝字体架上的「淋湿爱」，点开才下，下好之前用圆体。
// 后端：/api/lmc5/recall/*（alcove-backend/recall_admin.py），试问跟线上召回走同一条路。

struct BuwangInk {
    let dark: Bool
    private func c(_ day: String, _ night: String) -> Color { Color.kakaoHex(dark ? night : day, .gray) }
    var paper: Color { c("#f7f8fc", "#1c1d23") }
    var card: Color { c("#ffffff", "#26272f") }
    var ink: Color { c("#3a3550", "#e6e3f0") }
    var ink2: Color { c("#6b6685", "#b4b0c8") }
    var ink3: Color { c("#a3a0b8", "#7d7a92") }
    var cherry: Color { c("#d95c80", "#e27f9c") }
    var blue: Color { c("#cfe0f5", "#2e3a4d") }
    var pink: Color { c("#f8dbe4", "#4a3440") }
    var lilac: Color { c("#e3dcf3", "#3a3450") }
    var mint: Color { c("#d6efe8", "#2c4440") }
    var faint: Color { c("#f1eef8", "#2a2a33") }
    var line: Color { c("#dcd9ea", "#3a3a46") }
    var route: Color { c("#8fb0da", "#6f90bd") }
    var shadow: Color { dark ? Color.black.opacity(0.35) : Color(red: 90 / 255, green: 80 / 255, blue: 140 / 255).opacity(0.14) }
}

enum BuwangFont {
    static let handID = "linshiai"
    /// 手写字：「淋湿爱」注册好了就用，还没下到就先用圆体
    static func hand(_ size: CGFloat) -> Font {
        if let name = KakaoPackStore.shared.registeredName(handID) {
            return .custom(name, fixedSize: size)
        }
        return .system(size: size, weight: .medium, design: .rounded)
    }
    /// 英文那一行小花体：手机自带，不用下
    static func script(_ size: CGFloat) -> Font { .custom("SnellRoundhand", fixedSize: size) }
    static func warm() {
        let store = KakaoPackStore.shared
        if store.fonts.isEmpty { store.refresh() }
        store.ensureFont(id: handID)
    }
}

private func buwangBuzz(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

private func buwangTime(_ ts: Double) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.timeZone = TimeZone(identifier: "Asia/Shanghai")
    f.dateFormat = "MM-dd HH:mm"
    return f.string(from: Date(timeIntervalSince1970: ts))
}

/// 纸：冷白底、三团水彩晕、一层很淡的纸纹颗粒
struct BuwangPaper: View {
    let ink: BuwangInk
    var body: some View {
        ZStack {
            ink.paper
            Circle().fill(ink.blue).frame(width: 320, height: 260).blur(radius: 70).opacity(0.55).offset(x: -150, y: -220)
            Circle().fill(ink.pink).frame(width: 300, height: 240).blur(radius: 70).opacity(0.5).offset(x: 160, y: 60)
            Circle().fill(ink.lilac).frame(width: 280, height: 220).blur(radius: 70).opacity(0.5).offset(x: -60, y: 340)
            Canvas { ctx, size in
                var seed: UInt64 = 20260928
                for _ in 0..<1400 {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let x = CGFloat(seed >> 33 % 10000) / 10000 * size.width
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let y = CGFloat(seed >> 33 % 10000) / 10000 * size.height
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.1, height: 1.1)),
                             with: .color(ink.ink.opacity(0.05)))
                }
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

/// 按下去轻轻一沉再弹回来
struct BuwangPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

/// 一截纸胶带
struct BuwangTape: View {
    let color: Color
    var body: some View {
        Rectangle()
            .fill(color.opacity(0.85))
            .overlay(
                HStack(spacing: 4) {
                    ForEach(0..<6, id: \.self) { _ in
                        Rectangle().fill(Color.white.opacity(0.45)).frame(width: 3)
                    }
                }
            )
            .frame(width: 44, height: 13)
            .rotationEffect(.degrees(-8))
    }
}

struct BuwangTitle: View {
    let ink: BuwangInk
    let zh: String
    let en: String
    @ObservedObject private var fontStore = KakaoPackStore.shared
    var body: some View {
        VStack(spacing: -2) {
            Text(zh).font(BuwangFont.hand(32)).tracking(2).foregroundColor(ink.ink)
            Text(en).font(BuwangFont.script(17)).foregroundColor(ink.ink3)
        }
        .frame(maxWidth: .infinity)
    }
}

struct BuwangSection: View {
    let ink: BuwangInk
    let zh: String
    let en: String
    @ObservedObject private var fontStore = KakaoPackStore.shared
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(zh).font(BuwangFont.hand(18)).foregroundColor(ink.ink)
            Text(en).font(.system(size: 9)).tracking(3.5).foregroundColor(ink.ink3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18).padding(.bottom, 8)
    }
}

struct BuwangCard: View {
    let ink: BuwangInk
    let icon: String
    let tint: Color
    let title: String
    let sub: String
    var badge: Int = 0
    var tape: Color? = nil
    var dashed: Bool = false
    var action: () -> Void
    @State private var wiggle = false
    @ObservedObject private var fontStore = KakaoPackStore.shared

    var body: some View {
        Button {
            buwangBuzz()
            action()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .light))
                    .foregroundColor(ink.ink2)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(BuwangFont.hand(17))
                        .foregroundColor(dashed ? ink.ink3 : ink.ink)
                    Text(sub)
                        .font(.system(size: 9.5))
                        .foregroundColor(ink.ink3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBack)
            .overlay(alignment: .topLeading) { tapeView }
            .overlay(alignment: .topTrailing) { badgeView }
        }
        .buttonStyle(BuwangPress())
        .onAppear {
            guard badge > 0 else { return }
            withAnimation(.easeInOut(duration: 0.12).repeatCount(5, autoreverses: true).delay(0.7)) { wiggle = true }
        }
    }

    @ViewBuilder private var cardBack: some View {
        if dashed {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(ink.ink3.opacity(0.5), style: StrokeStyle(lineWidth: 1.3, dash: [4, 3]))
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ink.card)
                .shadow(color: ink.shadow, radius: 7, x: 0, y: 4)
        }
    }

    @ViewBuilder private var tapeView: some View {
        if let tape {
            BuwangTape(color: tape).offset(x: 12, y: -6)
        }
    }

    @ViewBuilder private var badgeView: some View {
        if badge > 0 {
            Text("\(badge)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 7).padding(.vertical, 1)
                .background(Capsule().fill(ink.cherry))
                .rotationEffect(.degrees(wiggle ? 9 : 3))
                .offset(x: -6, y: -6)
        }
    }
}

/// 樱桃粉的小药丸标签
struct BuwangPill: View {
    let text: String
    let fill: Color
    let ink: BuwangInk
    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundColor(ink.ink2)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(fill))
    }
}

/// 盖章：出现时从大到小砸下来
struct BuwangStamp: View {
    let text: String
    let color: Color
    @State private var landed = false
    @ObservedObject private var fontStore = KakaoPackStore.shared
    var body: some View {
        Text(text)
            .font(BuwangFont.hand(14))
            .foregroundColor(color)
            .padding(.horizontal, 7).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.7), lineWidth: 1.5))
            .rotationEffect(.degrees(8))
            .scaleEffect(landed ? 1 : 1.8)
            .opacity(landed ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { landed = true }
            }
    }
}

// ── 数据 ──

struct BWStation: Identifiable {
    let id = UUID()
    let name: String
    let state: String       // ok / stop / skip / end
    let text: String
    let detail: [String: Any]
    init(_ d: [String: Any]) {
        name = d.string("name")
        state = d.string("state")
        text = d.string("text")
        detail = (d["detail"] as? [String: Any]) ?? [:]
    }
}

struct BWItem: Identifiable {
    let id: String
    let kind: String
    let title: String
    let body: String
    let day: String
    let volume: String
    let her: String
    let score: Double
    let fullLen: Int
    let thumb: String   // 0928：图召回那样带小图地址（/api/...）
    init(_ d: [String: Any]) {
        id = d.string("key")
        thumb = d.string("thumb")
        kind = d.string("kind")
        title = d.string("title")
        body = d.string("body")
        day = d.string("day")
        volume = d.string("volume")
        her = d.string("her")
        score = d.double("score")
        fullLen = d.int("full_len")
    }
}

// ── 地铁线：一站一站亮起来，点有细节的站能展开 ──

struct BuwangRouteView: View {
    let ink: BuwangInk
    let stations: [BWStation]
    @State private var lit = 0
    @State private var opened: UUID?
    @ObservedObject private var fontStore = KakaoPackStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(stations.enumerated()), id: \.element.id) { pair in
                row(pair.element, on: pair.offset < lit)
            }
        }
        .padding(.vertical, 4)
        .background(alignment: .topLeading) {
            GeometryReader { geo in
                let share = stations.isEmpty ? 0 : CGFloat(lit) / CGFloat(stations.count)
                Capsule()
                    .fill(ink.route.opacity(0.45))
                    .frame(width: 2, height: max(0, geo.size.height - 14) * share)
                    .offset(x: 6, y: 8)
            }
        }
        .onAppear { light() }
        .onChange(of: stations.map { $0.id }) { _, _ in light() }
    }

    private func light() {
        lit = 0
        opened = nil
        for i in 0..<stations.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2 * Double(i + 1)) {
                withAnimation(.easeOut(duration: 0.25)) { lit = i + 1 }
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
    }

    private func dotColor(_ st: BWStation) -> Color {
        if st.state == "end" { return ink.cherry }
        if st.state == "stop" { return ink.ink3 }
        return ink.route
    }

    @ViewBuilder
    private func row(_ st: BWStation, on: Bool) -> some View {
        let hasDetail = !st.detail.isEmpty
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(on ? (st.state == "end" ? ink.cherry : ink.blue) : ink.card)
                    .overlay(Circle().stroke(on ? dotColor(st) : ink.line, lineWidth: 2))
                    .frame(width: 14, height: 14)
                    .scaleEffect(on ? 1 : 0.7)
                    .padding(.top, 2)
                Text(st.name)
                    .font(BuwangFont.hand(15))
                    .foregroundColor(st.state == "end" ? ink.cherry : ink.ink)
                    .frame(width: 50, alignment: .leading)
                Text(st.text)
                    .font(.system(size: 11.5))
                    .foregroundColor(st.state == "stop" ? ink.ink3 : ink.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if hasDetail {
                    Image(systemName: opened == st.id ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(ink.ink3)
                        .padding(.top, 3)
                }
            }
            if opened == st.id {
                BuwangStationDetail(ink: ink, detail: st.detail)
                    .padding(.leading, 24)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .opacity(on ? 1 : 0.35)
        .contentShape(Rectangle())
        .onTapGesture {
            guard hasDetail else { return }
            buwangBuzz(.soft)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                opened = (opened == st.id) ? nil : st.id
            }
        }
    }
}

/// 展开一站：两张榜各排了谁、闸门挡了谁
struct BuwangStationDetail: View {
    let ink: BuwangInk
    let detail: [String: Any]

    private func pairs(_ key: String) -> [(String, Double)] {
        let raw = (detail[key] as? [Any]) ?? []
        var out: [(String, Double)] = []
        for x in raw {
            if let p = x as? [Any], p.count >= 2 {
                let k = (p[0] as? String) ?? ""
                let v = (p[1] as? NSNumber)?.doubleValue ?? 0
                out.append((k, v))
            }
        }
        return out
    }

    private func short(_ key: String) -> String {
        key.replacingOccurrences(of: "curated:", with: "#")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            let vec = pairs("vector")
            let kw = pairs("kw")
            if !vec.isEmpty {
                Text("意思榜：" + vec.enumerated().map { "\($0.offset + 1). \(short($0.element.0)) \(String(format: "%.2f", $0.element.1))" }.joined(separator: "  "))
            }
            if !kw.isEmpty {
                Text("关键词榜：" + kw.enumerated().map { "\($0.offset + 1). \(short($0.element.0))" }.joined(separator: "  "))
            }
            let cooled = (detail["cooled"] as? [String]) ?? []
            if !cooled.isEmpty {
                Text("冷却挡掉：" + cooled.map { short($0) }.joined(separator: "、"))
            }
            let pruned = (detail["pruned"] as? [String: String]) ?? [:]
            ForEach(pruned.keys.sorted(), id: \.self) { k in
                Text("\(short(k))：\(pruned[k] ?? "")")
            }
            let tier = (detail["tier_drop"] as? [String]) ?? []
            if !tier.isEmpty {
                Text("第二三条不够格：" + tier.map { short($0) }.joined(separator: "、"))
            }
        }
        .font(.system(size: 10.5))
        .foregroundColor(ink.ink3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ink.faint))
    }
}

/// 浮上来的一样东西：纸片卡，贴胶带；点开看全文，右下角「✕ 这条不对」
struct BuwangMemoryCard: View {
    let ink: BuwangInk
    let item: BWItem
    let rank: Int
    var onOpen: () -> Void
    var onWrong: (() -> Void)? = nil
    @ObservedObject private var fontStore = KakaoPackStore.shared

    private var meta: String {
        var parts: [String] = []
        if !item.day.isEmpty { parts.append(item.day) }
        if !item.volume.isEmpty { parts.append(item.volume == "整卷" ? "一整卷" : "属于「\(item.volume)」那卷") }
        if item.score > 0 { parts.append("意思 " + String(format: "%.2f", item.score)) }
        if item.kind == "image" { parts.append("图") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title.isEmpty ? "无题" : item.title)
                .font(BuwangFont.hand(17))
                .foregroundColor(ink.ink)
            Text(meta)
                .font(.system(size: 10))
                .foregroundColor(ink.ink3)
            if !item.thumb.isEmpty, let url = URL(string: AlcoveAPI.base.absoluteString + item.thumb) {
                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(ink.ink3.opacity(0.12))
                }
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.vertical, 4)
            }
            if !item.her.isEmpty {
                Text("她当时：" + item.her)
                    .font(.system(size: 11))
                    .foregroundColor(ink.ink2)
            }
            Text(item.body)
                .font(.system(size: 11.5))
                .foregroundColor(ink.ink2)
                .lineSpacing(3)
                .lineLimit(4)
            HStack {
                Text("第 \(rank) 样")
                    .font(.system(size: 10))
                    .foregroundColor(ink.ink3)
                Spacer()
                if let onWrong {
                    Button {
                        buwangBuzz()
                        onWrong()
                    } label: {
                        Text("✕ 这条不对")
                            .font(BuwangFont.hand(14))
                            .foregroundColor(ink.cherry)
                            .padding(.horizontal, 10).padding(.vertical, 2)
                            .overlay(Capsule().stroke(ink.cherry.opacity(0.45), lineWidth: 1.2))
                    }
                    .buttonStyle(BuwangPress())
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 13).padding(.top, 13).padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ink.card)
            .shadow(color: ink.shadow, radius: 7, x: 0, y: 4))
        .overlay(alignment: .topLeading) {
            if rank == 1 { BuwangTape(color: ink.pink).offset(x: 14, y: -6) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            buwangBuzz(.soft)
            onOpen()
        }
    }
}

/// 点开一样东西：全文
struct BuwangTextSheet: View {
    let ink: BuwangInk
    let item: BWItem
    @ObservedObject private var fontStore = KakaoPackStore.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title.isEmpty ? "无题" : item.title)
                    .font(BuwangFont.hand(24))
                    .foregroundColor(ink.ink)
                Text([item.day, item.volume.isEmpty ? "" : "属于「\(item.volume)」那卷"].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundColor(ink.ink3)
                if !item.her.isEmpty {
                    Text("她当时：" + item.her).font(.system(size: 13)).foregroundColor(ink.ink2)
                }
                Text(item.body)
                    .font(.system(size: 14))
                    .foregroundColor(ink.ink)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                if item.fullLen > 600 {
                    Text("（后面还有 \(item.fullLen - 600) 字，他那边能用命令看全文）")
                        .font(.system(size: 11))
                        .foregroundColor(ink.ink3)
                }
            }
            .padding(24)
        }
        .background(ink.paper.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}

/// 记进错题本的小框：选错在哪、写一句
struct BuwangWrongSheet: View {
    let ink: BuwangInk
    let q: String
    let itemTitle: String
    let kinds: [String]
    var onSubmit: (String, String) async -> Void
    @State private var kind = ""
    @State private var note = ""
    @State private var sending = false
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var fontStore = KakaoPackStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("记进错题本")
                .font(BuwangFont.hand(24))
                .foregroundColor(ink.ink)
            if !q.isEmpty {
                Text("「\(q)」")
                    .font(BuwangFont.hand(16))
                    .foregroundColor(ink.ink2)
            }
            if !itemTitle.isEmpty {
                Text("浮了：《\(itemTitle)》")
                    .font(.system(size: 12))
                    .foregroundColor(ink.ink3)
            }
            HStack(spacing: 8) {
                ForEach(kinds, id: \.self) { k in
                    Button {
                        buwangBuzz(.soft)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { kind = k }
                    } label: {
                        Text(k)
                            .font(BuwangFont.hand(15))
                            .foregroundColor(kind == k ? .white : ink.ink2)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill(kind == k ? ink.cherry : ink.faint))
                    }
                    .buttonStyle(BuwangPress())
                }
            }
            TextField("说一句哪里不对（可以不写）", text: $note, axis: .vertical)
                .lineLimit(2...4)
                .font(.system(size: 13))
                .padding(11)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ink.card))
            Button {
                guard !sending, !kind.isEmpty else { return }
                sending = true
                buwangBuzz(.medium)
                Task {
                    await onSubmit(kind, note)
                    dismiss()
                }
            } label: {
                Text(sending ? "记着……" : "记下")
                    .font(BuwangFont.hand(17))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(kind.isEmpty ? ink.ink3 : ink.cherry))
            }
            .buttonStyle(BuwangPress())
            Spacer(minLength: 0)
        }
        .padding(24)
        .background(ink.paper.ignoresSafeArea())
        .presentationDetents([.medium])
        .onAppear { if kind.isEmpty { kind = kinds.first ?? "" } }
    }
}

// ── 浮现：试问 / 阈值 / 他最近的 ──

struct BuwangSurfaceView: View {
    let ink: BuwangInk
    @State private var tab = 0
    @Namespace private var tabNS
    @ObservedObject private var fontStore = KakaoPackStore.shared
    private let names = ["试问", "阈值", "他最近的"]
    private let subs = ["say a line, see what surfaces", "how picky he is", "his last few turns"]

    var body: some View {
        VStack(spacing: 0) {
            BuwangTitle(ink: ink, zh: "浮现", en: subs[tab])
                .padding(.top, -6)
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Button {
                        buwangBuzz(.soft)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { tab = i }
                    } label: {
                        Text(names[i])
                            .font(BuwangFont.hand(15))
                            .foregroundColor(tab == i ? ink.ink : ink.ink2)
                            .padding(.horizontal, 12).padding(.vertical, 4)
                            .background {
                                if tab == i {
                                    Capsule().fill(ink.lilac).matchedGeometryEffect(id: "tab", in: tabNS)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            Group {
                switch tab {
                case 0: BuwangAskView(ink: ink)
                case 1: BuwangTuningView(ink: ink)
                default: BuwangRecentView(ink: ink)
                }
            }
            .transition(.opacity)
        }
    }
}

struct BuwangAskView: View {
    let ink: BuwangInk
    @State private var q = ""
    @State private var asked = ""
    @State private var running = false
    @State private var error = ""
    @State private var stations: [BWStation] = []
    @State private var rawStations: [[String: Any]] = []
    @State private var items: [BWItem] = []
    @State private var names: [String] = []
    @State private var shown = 0
    @State private var ms = 0
    @State private var opened: BWItem?
    @State private var wrongFor: BWItem?
    @State private var missSheet = false
    @State private var flown: Set<String> = []
    @State private var toast = ""
    @FocusState private var focused: Bool
    @ObservedObject private var fontStore = KakaoPackStore.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                askBox
                if running {
                    HStack(spacing: 8) {
                        ProgressView().tint(ink.cherry)
                        Text("他在想……").font(BuwangFont.hand(15)).foregroundColor(ink.ink2)
                    }
                    .padding(.top, 20)
                }
                if !error.isEmpty {
                    Text(error).font(.system(size: 12)).foregroundColor(ink.cherry).padding(.top, 10)
                }
                if !stations.isEmpty && !running {
                    BuwangRouteView(ink: ink, stations: stations)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ink.card.opacity(0.75)))
                    if ms > 0 {
                        Text("整轮 \(String(format: "%.1f", Double(ms) / 1000)) 秒")
                            .font(.system(size: 10)).foregroundColor(ink.ink3)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    ForEach(Array(items.prefix(shown).enumerated()), id: \.element.id) { pair in
                        let gone = flown.contains(pair.element.id)
                        BuwangMemoryCard(ink: ink, item: pair.element, rank: pair.offset + 1,
                                         onOpen: { opened = pair.element },
                                         onWrong: { wrongFor = pair.element })
                            .scaleEffect(gone ? 0.15 : 1)
                            .offset(x: gone ? 150 : 0, y: gone ? -420 : 0)
                            .opacity(gone ? 0 : 1)
                            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                    }
                    Button {
                        buwangBuzz()
                        missSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("该浮的没浮？").foregroundColor(ink.ink2)
                            Text("记进错题本").foregroundColor(ink.cherry).underline(true, pattern: .dash)
                        }
                        .font(BuwangFont.hand(15))
                    }
                    .buttonStyle(BuwangPress())
                    .padding(.top, 4)
                }
                if stations.isEmpty && !running {
                    Text("随便说一句你平时会跟他说的话，看看他这句会想起什么、每一站是怎么判的。只是试试，不会推给他。")
                        .font(.system(size: 11.5))
                        .foregroundColor(ink.ink3)
                        .lineSpacing(4)
                        .padding(.horizontal, 8)
                        .padding(.top, 14)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .overlay(alignment: .top) {
            if !toast.isEmpty {
                Text(toast)
                    .font(BuwangFont.hand(15))
                    .foregroundColor(ink.ink)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(ink.card).shadow(color: ink.shadow, radius: 8, x: 0, y: 4))
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(item: $opened) { it in BuwangTextSheet(ink: ink, item: it) }
        .sheet(item: $wrongFor) { it in
            BuwangWrongSheet(ink: ink, q: asked, itemTitle: it.title, kinds: ["召错了", "记忆写错了"]) { kind, note in
                await submitWrong(kind: kind, note: note, item: it)
            }
        }
        .sheet(isPresented: $missSheet) {
            BuwangWrongSheet(ink: ink, q: asked, itemTitle: "", kinds: ["该召没召"]) { kind, note in
                await submitWrong(kind: kind, note: note, item: nil)
            }
        }
    }

    private var askBox: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField("说一句话，看看他会想起什么", text: $q, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 13.5))
                .foregroundColor(ink.ink)
                .focused($focused)
                .submitLabel(.go)
                .onSubmit { Task { await ask() } }
            Button {
                Task { await ask() }
            } label: {
                Text("试问")
                    .font(BuwangFont.hand(16))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(Capsule().fill(q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ink.ink3 : ink.cherry))
            }
            .buttonStyle(BuwangPress())
            .disabled(running)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(ink.card)
            .shadow(color: ink.shadow, radius: 7, x: 0, y: 4))
    }

    private func ask() async {
        let text = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !running else { return }
        buwangBuzz(.medium)
        focused = false
        await MainActor.run {
            running = true
            error = ""
            stations = []
            items = []
            shown = 0
            flown = []
        }
        let d = (try? await NativeHouseAPI.object("/api/lmc5/recall/test", method: "POST", body: ["q": text])) ?? [:]
        await MainActor.run {
            running = false
            asked = text
            guard (d["ok"] as? Bool) == true else {
                error = d.string("error").isEmpty ? "没问成，网络或者后端出了点事" : d.string("error")
                return
            }
            rawStations = d.array("stations")
            stations = rawStations.map { BWStation($0) }
            items = d.array("items").map { BWItem($0) }
            names = (d["names"] as? [String]) ?? []
            ms = d.int("ms")
        }
        // 地铁线一站站亮完，纸片再一张张落下来
        let wait = 0.2 * Double(stations.count) + 0.25
        for i in 0..<items.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + wait + 0.22 * Double(i)) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { shown = i + 1 }
                buwangBuzz(.soft)
            }
        }
    }

    private func submitWrong(kind: String, note: String, item: BWItem?) async {
        let picked: [[String: Any]] = items.map { ["key": $0.id, "title": $0.title] }
        var payload: [String: Any] = ["q": asked, "kind": kind, "note": note, "source": "试问",
                                      "route": ["stations": rawStations, "items": picked]]
        if let item { payload["memory_key"] = item.id }
        let d = (try? await NativeHouseAPI.object("/api/lmc5/recall/wrongbook", method: "POST", body: payload)) ?? [:]
        await MainActor.run {
            let ok = (d["ok"] as? Bool) == true
            if ok, let item {
                withAnimation(.easeIn(duration: 0.55)) { _ = flown.insert(item.id) }
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { toast = ok ? "记下了，在错题本里" : "没记上，再试一次" }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeOut(duration: 0.3)) { toast = "" }
        }
    }
}

// ── 阈值：手画滑杆，拖一格震一下；先跑测评看分数，满意再存 ──

struct BWKnob: Identifiable {
    let id: String
    let name: String
    let note: String
    let def: Double
    let lo: Double
    let hi: Double
    let step: Double
    var value: Double
    init(_ d: [String: Any]) {
        id = d.string("key")
        name = d.string("name")
        note = d.string("note")
        def = d.double("default")
        lo = d.double("min")
        hi = d.double("max")
        step = max(0.001, d.double("step"))
        value = d.double("value")
    }
    var text: String { step >= 1 ? "\(Int(value.rounded()))" : String(format: "%.2f", value) }
}

struct BuwangKnobRow: View {
    let ink: BuwangInk
    @Binding var knob: BWKnob
    @State private var axis = 0   // 这一下拖：0 还没定 / 1 横着（调） / 2 竖着（让页面滑）
    @ObservedObject private var fontStore = KakaoPackStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(knob.name).font(BuwangFont.hand(15.5)).foregroundColor(ink.ink)
                Spacer()
                Text(knob.text)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundColor(ink.cherry)
                    .contentTransition(.numericText())
            }
            Text(knob.note).font(.system(size: 9.5)).foregroundColor(ink.ink3)
            GeometryReader { geo in
                let w = geo.size.width - 16
                let share = CGFloat((knob.value - knob.lo) / max(0.0001, knob.hi - knob.lo))
                ZStack(alignment: .leading) {
                    Capsule().fill(ink.lilac).frame(height: 5)
                    Capsule().fill(ink.pink).frame(width: max(5, 8 + w * share), height: 5)
                    Circle()
                        .fill(ink.card)
                        .overlay(Circle().stroke(ink.cherry, lineWidth: 2))
                        .frame(width: 16, height: 16)
                        .offset(x: w * share)
                }
                .frame(height: 24)
                .contentShape(Rectangle())
                // 0928 她报：页面上下滑不动、一碰就拖到横条。原来是 minimumDistance 0 的 .gesture 把整页滑动吃了。
                // 改成跟页面一起认手势，头几点判方向：横着拖才调，竖着的放给页面滑。
                .simultaneousGesture(DragGesture(minimumDistance: 6).onChanged { g in
                    if axis == 0 { axis = abs(g.translation.width) > abs(g.translation.height) ? 1 : 2 }
                    guard axis == 1 else { return }
                    let raw = knob.lo + Double(min(max(0, (g.location.x - 8) / max(1, w)), 1)) * (knob.hi - knob.lo)
                    let snapped = (raw / knob.step).rounded() * knob.step
                    let clamped = min(knob.hi, max(knob.lo, snapped))
                    if abs(clamped - knob.value) > knob.step / 2 {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.snappy(duration: 0.15)) { knob.value = clamped }
                    }
                }.onEnded { _ in axis = 0 })
            }
            .frame(height: 24)
        }
        .padding(.horizontal, 13).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ink.card)
            .shadow(color: ink.shadow, radius: 5, x: 0, y: 3))
    }
}

struct BuwangTuningView: View {
    let ink: BuwangInk
    @State private var knobs: [BWKnob] = []
    @State private var loading = true
    @State private var evalRunning = false
    @State private var evalText = ""
    @State private var evalStamp = 0
    @State private var savedStamp = 0
    @State private var resetStamp = 0
    @State private var fails: [String] = []
    @ObservedObject private var fontStore = KakaoPackStore.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 9) {
                if loading {
                    ProgressView().tint(ink.cherry).padding(.top, 30)
                }
                if !knobs.isEmpty {
                    // 0928 她要的一键默认：全部拨回默认并直接存，放最上面一眼看得见
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        if resetStamp > 0 {
                            BuwangStamp(text: "已回默认", color: ink.cherry).id(resetStamp)
                        }
                        Button {
                            Task { await resetAll() }
                        } label: {
                            Text("一键默认")
                                .font(BuwangFont.hand(15))
                                .foregroundColor(ink.cherry)
                                .padding(.horizontal, 14).padding(.vertical, 5)
                                .background(Capsule().fill(ink.card))
                                .overlay(Capsule().stroke(ink.cherry.opacity(0.45), lineWidth: 1.2))
                        }
                        .buttonStyle(BuwangPress())
                    }
                }
                ForEach($knobs) { $k in
                    BuwangKnobRow(ink: ink, knob: $k)
                }
                if !knobs.isEmpty {
                    HStack(spacing: 10) {
                        Button {
                            Task { await runEval() }
                        } label: {
                            Text(evalRunning ? "跑着呢……" : "用测评跑一遍")
                                .font(BuwangFont.hand(15))
                                .foregroundColor(ink.ink)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(Capsule().fill(ink.card))
                                .overlay(Capsule().stroke(ink.line, lineWidth: 1.2))
                        }
                        .buttonStyle(BuwangPress())
                        .disabled(evalRunning)
                        if evalStamp > 0 && !evalText.isEmpty {
                            BuwangStamp(text: evalText, color: fails.isEmpty ? Color.kakaoHex("#6aa894", .green) : ink.cherry)
                                .id(evalStamp)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 6)
                    ForEach(fails, id: \.self) { f in
                        Text(f).font(.system(size: 10.5)).foregroundColor(ink.cherry)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 10) {
                        Button {
                            Task { await save() }
                        } label: {
                            Text("存下来")
                                .font(BuwangFont.hand(16))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16).padding(.vertical, 6)
                                .background(Capsule().fill(ink.cherry))
                        }
                        .buttonStyle(BuwangPress())
                        Text("他下一句就用新的").font(.system(size: 10.5)).foregroundColor(ink.ink3)
                        if savedStamp > 0 {
                            BuwangStamp(text: "已存", color: ink.cherry).id(savedStamp)
                        }
                        Spacer(minLength: 0)
                    }
                    Text("先拖、先跑测评看分数，满意了再存。测评是我编的 28 句话：闲聊不该召、该召的要召到。")
                        .font(.system(size: 10.5))
                        .foregroundColor(ink.ink3)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .task { await load() }
    }

    private func values() -> [String: Any] {
        var out: [String: Any] = [:]
        for k in knobs { out[k.id] = k.value }
        return out
    }

    private func load() async {
        let d = (try? await NativeHouseAPI.object("/api/lmc5/recall/tuning")) ?? [:]
        let ev = (d["eval"] as? [String: Any]) ?? [:]
        await MainActor.run {
            knobs = d.array("knobs").map { BWKnob($0) }
            loading = false
            if (ev["running"] as? Bool) != true {
                evalText = shortSummary(ev.string("summary"))
            }
        }
    }

    private func shortSummary(_ s: String) -> String {
        // 「通过 25/25（另有 3 题不计分）· 平均每句 0.21 条 · 平均 1.2 秒」→「25/25 · 0.21 条」
        let parts = s.components(separatedBy: " · ")
        guard let first = parts.first, !first.isEmpty else { return "" }
        let score = first.replacingOccurrences(of: "通过 ", with: "").components(separatedBy: "（").first ?? first
        let per = parts.count > 1 ? parts[1].replacingOccurrences(of: "平均每句 ", with: "") : ""
        return per.isEmpty ? score : "\(score) · \(per)"
    }

    private func runEval() async {
        buwangBuzz()
        await MainActor.run { evalRunning = true; fails = [] }
        _ = try? await NativeHouseAPI.object("/api/lmc5/recall/eval", method: "POST", body: ["values": values()])
        var last: [String: Any] = [:]
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            last = (try? await NativeHouseAPI.object("/api/lmc5/recall/eval")) ?? [:]
            if (last["running"] as? Bool) != true { break }
        }
        await MainActor.run {
            evalRunning = false
            evalText = shortSummary(last.string("summary"))
            fails = (last["fails"] as? [String]) ?? []
            evalStamp += 1
            buwangBuzz(.medium)
        }
    }

    private func save() async {
        buwangBuzz(.medium)
        let d = (try? await NativeHouseAPI.object("/api/lmc5/recall/tuning", method: "POST", body: ["values": values()])) ?? [:]
        await MainActor.run {
            if (d["ok"] as? Bool) == true { savedStamp += 1 }
        }
    }

    private func resetAll() async {
        buwangBuzz(.medium)
        await MainActor.run {
            withAnimation(.snappy) {
                for i in knobs.indices { knobs[i].value = knobs[i].def }
            }
        }
        let d = (try? await NativeHouseAPI.object("/api/lmc5/recall/tuning", method: "POST", body: ["values": values()])) ?? [:]
        await MainActor.run {
            if (d["ok"] as? Bool) == true { resetStamp += 1 }
        }
    }
}

// ── 他最近的：一轮一行，点开看地铁线，往左滑记错题 ──

struct BWRouteRow: Identifiable {
    let id: Int
    let ts: Double
    let q: String
    let why: String
    let n: Int
    init(_ d: [String: Any]) {
        id = d.int("id")
        ts = d.double("ts")
        q = d.string("q")
        why = d.string("why")
        n = d.int("n")
    }
}

struct BuwangRecentView: View {
    let ink: BuwangInk
    @State private var rows: [BWRouteRow] = []
    @State private var loading = true
    @State private var opened: BWRouteRow?
    @State private var wrongFor: BWRouteRow?
    @State private var toast = ""
    @ObservedObject private var fontStore = KakaoPackStore.shared

    var body: some View {
        List {
            if loading {
                ProgressView().tint(ink.cherry).frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if rows.isEmpty {
                Text("还没有记录。从 0928 起，他每一轮召回都会记在这里。")
                    .font(.system(size: 11.5)).foregroundColor(ink.ink3)
                    .listRowBackground(Color.clear)
            }
            ForEach(rows) { r in
                Button {
                    buwangBuzz(.soft)
                    opened = r
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Text(buwangTime(r.ts))
                            .font(.system(size: 10))
                            .foregroundColor(ink.ink3)
                            .frame(width: 62, alignment: .leading)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r.q.isEmpty ? "（没有字）" : "「\(r.q)」")
                                .font(BuwangFont.hand(15))
                                .foregroundColor(ink.ink)
                                .lineLimit(2)
                            Text(r.why)
                                .font(.system(size: 10.5))
                                .foregroundColor(r.n > 0 ? ink.cherry : ink.ink3)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(ink.line)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        wrongFor = r
                    } label: {
                        Label("记错题", systemImage: "xmark.square")
                    }
                    .tint(ink.cherry)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await load() }
        .task { await load() }
        .overlay(alignment: .top) {
            if !toast.isEmpty {
                Text(toast)
                    .font(BuwangFont.hand(15))
                    .foregroundColor(ink.ink)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(ink.card).shadow(color: ink.shadow, radius: 8, x: 0, y: 4))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(item: $opened) { r in BuwangRouteSheet(ink: ink, routeID: r.id, q: r.q) }
        .sheet(item: $wrongFor) { r in
            BuwangWrongSheet(ink: ink, q: r.q, itemTitle: "", kinds: ["召错了", "该召没召", "记忆写错了"]) { kind, note in
                let payload: [String: Any] = ["q": r.q, "kind": kind, "note": note, "source": "他的一轮",
                                              "route": ["route_id": r.id]]
                let d = (try? await NativeHouseAPI.object("/api/lmc5/recall/wrongbook", method: "POST", body: payload)) ?? [:]
                await MainActor.run {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        toast = (d["ok"] as? Bool) == true ? "记下了，在错题本里" : "没记上，再试一次"
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                    withAnimation(.easeOut(duration: 0.3)) { toast = "" }
                }
            }
        }
    }

    private func load() async {
        let d = (try? await NativeHouseAPI.object("/api/lmc5/recall/routes?limit=40")) ?? [:]
        await MainActor.run {
            rows = d.array("routes").map { BWRouteRow($0) }
            loading = false
        }
    }
}

/// 某一轮的地铁线（他最近的 / 错题本点开都用它）
struct BuwangRouteSheet: View {
    let ink: BuwangInk
    let routeID: Int
    let q: String
    @State private var stations: [BWStation] = []
    @State private var items: [BWItem] = []
    @State private var loading = true
    @State private var opened: BWItem?
    @ObservedObject private var fontStore = KakaoPackStore.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Text(q.isEmpty ? "这一轮" : "「\(q)」")
                    .font(BuwangFont.hand(20))
                    .foregroundColor(ink.ink)
                if loading {
                    ProgressView().tint(ink.cherry).frame(maxWidth: .infinity).padding(.top, 20)
                } else if stations.isEmpty {
                    Text("这一轮的路线没找到").font(.system(size: 12)).foregroundColor(ink.ink3)
                } else {
                    BuwangRouteView(ink: ink, stations: stations)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ink.card.opacity(0.75)))
                    ForEach(Array(items.enumerated()), id: \.element.id) { pair in
                        BuwangMemoryCard(ink: ink, item: pair.element, rank: pair.offset + 1, onOpen: { opened = pair.element })
                    }
                }
            }
            .padding(20)
        }
        .background(BuwangPaper(ink: ink))
        .presentationDetents([.large])
        .task { await load() }
        .sheet(item: $opened) { it in BuwangTextSheet(ink: ink, item: it) }
    }

    private func load() async {
        let d = (try? await NativeHouseAPI.object("/api/lmc5/recall/route?id=\(routeID)")) ?? [:]
        await MainActor.run {
            stations = d.array("stations").map { BWStation($0) }
            items = d.array("items").map { BWItem($0) }
            loading = false
        }
    }
}

// ── 召回：不看的停用词 ──

struct BuwangStopwordsView: View {
    let ink: BuwangInk
    @State private var user: [String] = []
    @State private var highDf: [String] = []
    @State private var function: [String] = []
    @State private var aliasNames: [String] = []
    @State private var editing: String?
    @State private var adding = false
    @State private var newWord = ""
    @State private var showHigh = false
    @State private var showFunc = false
    @State private var showNames = false
    @State private var wiggle = false
    @FocusState private var addFocus: Bool
    @ObservedObject private var fontStore = KakaoPackStore.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                BuwangTitle(ink: ink, zh: "召回", en: "words he won't look at")
                    .padding(.top, -6)
                Text("你们的称呼、昵称、口头禅，写在这里就不会被拿来当「关键词」去翻记忆——一个常用称呼就能把整张榜喊乱。点一个词可以删，改完他下一句就用。")
                    .font(.system(size: 11.5))
                    .foregroundColor(ink.ink3)
                    .lineSpacing(4)
                BuwangSection(ink: ink, zh: "你加的", en: "YOURS")
                    .padding(.horizontal, -22)
                FlowLayout(spacing: 7, lineSpacing: 8) {
                    ForEach(user, id: \.self) { w in userChip(w) }
                    addChip
                }
                foldHeader("程序自己挑出的高频词", count: highDf.count, isOpen: $showHigh)
                if showHigh { greyChips(highDf) }
                foldHeader("别名表里的名字", count: aliasNames.count, isOpen: $showNames)
                if showNames { greyChips(aliasNames) }
                foldHeader("虚词", count: function.count, isOpen: $showFunc)
                if showFunc { greyChips(function) }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .task { await load() }
        .onTapGesture { if editing != nil { withAnimation { editing = nil } } }
    }

    private func userChip(_ w: String) -> some View {
        HStack(spacing: 4) {
            Text(w).font(BuwangFont.hand(15)).foregroundColor(ink.ink)
            if editing == w {
                Button {
                    Task { await remove(w) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(ink.cherry)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 4)
        .background(Capsule().fill(ink.pink))
        .rotationEffect(.degrees(editing == w ? (wiggle ? 3 : -3) : 0))
        .onTapGesture {
            buwangBuzz(.soft)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { editing = (editing == w) ? nil : w }
            wiggle = false
            withAnimation(.easeInOut(duration: 0.1).repeatCount(6, autoreverses: true)) { wiggle = true }
        }
    }

    @ViewBuilder private var addChip: some View {
        if adding {
            TextField("新词", text: $newWord)
                .font(BuwangFont.hand(15))
                .frame(width: 90)
                .focused($addFocus)
                .submitLabel(.done)
                .onSubmit { Task { await add() } }
                .padding(.horizontal, 11).padding(.vertical, 4)
                .background(Capsule().stroke(ink.cherry.opacity(0.6), lineWidth: 1.2))
                .onAppear { addFocus = true }
        } else {
            Button {
                buwangBuzz(.soft)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { adding = true }
            } label: {
                Text("＋ 加一个")
                    .font(BuwangFont.hand(15))
                    .foregroundColor(ink.ink3)
                    .padding(.horizontal, 11).padding(.vertical, 4)
                    .overlay(Capsule().stroke(ink.ink3.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])))
            }
            .buttonStyle(BuwangPress())
        }
    }

    private func foldHeader(_ title: String, count: Int, isOpen: Binding<Bool>) -> some View {
        Button {
            buwangBuzz(.soft)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isOpen.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(title).font(BuwangFont.hand(16)).foregroundColor(ink.ink)
                Text("\(count) 个").font(.system(size: 10.5)).foregroundColor(ink.ink3)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(ink.ink3)
                    .rotationEffect(.degrees(isOpen.wrappedValue ? 180 : 0))
            }
            .padding(.top, 14)
        }
        .buttonStyle(.plain)
    }

    private func greyChips(_ words: [String]) -> some View {
        FlowLayout(spacing: 5, lineSpacing: 5) {
            ForEach(words, id: \.self) { w in
                Text(w)
                    .font(.system(size: 11))
                    .foregroundColor(ink.ink2)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(ink.faint))
            }
        }
        .transition(.opacity)
    }

    private func load() async {
        let d = (try? await NativeHouseAPI.object("/api/lmc5/recall/stopwords")) ?? [:]
        await MainActor.run {
            user = (d["user"] as? [String]) ?? []
            highDf = (d["high_df"] as? [String]) ?? []
            function = (d["function"] as? [String]) ?? []
            aliasNames = (d["names"] as? [String]) ?? []
        }
    }

    private func add() async {
        let w = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        await MainActor.run { newWord = ""; withAnimation { adding = false } }
        guard !w.isEmpty else { return }
        buwangBuzz(.medium)
        let d = (try? await NativeHouseAPI.object("/api/lmc5/recall/stopwords", method: "POST", body: ["add": [w]])) ?? [:]
        await MainActor.run {
            if let list = d["user"] as? [String] {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { user = list }
            }
        }
    }

    private func remove(_ w: String) async {
        buwangBuzz(.medium)
        let d = (try? await NativeHouseAPI.object("/api/lmc5/recall/stopwords", method: "POST", body: ["remove": [w]])) ?? [:]
        await MainActor.run {
            if let list = d["user"] as? [String] {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { user = list; editing = nil }
            }
        }
    }
}

// ── 错题本：待修 / 已修，左右滑着切；点开看那一轮的路线；长按标已修 ──

struct BWWrong: Identifiable {
    let id: Int
    let ts: Double
    let source: String
    let q: String
    let kind: String
    let memoryTitle: String
    let note: String
    let fixed: Bool
    let fixedNote: String
    let by: String
    let routeID: Int
    init(_ d: [String: Any]) {
        id = d.int("id")
        ts = d.double("ts")
        source = d.string("source")
        q = d.string("q")
        kind = d.string("kind")
        memoryTitle = d.string("memory_title")
        note = d.string("note")
        fixed = d.string("status") == "fixed"
        fixedNote = d.string("fixed_note")
        by = d.string("by")
        routeID = d.int("route_id")
    }
}

struct BuwangWrongbookView: View {
    let ink: BuwangInk
    @State private var items: [BWWrong] = []
    @State private var tab = 0
    @State private var loading = true
    @State private var opened: BWWrong?
    @Namespace private var tabNS
    @ObservedObject private var fontStore = KakaoPackStore.shared

    private var openList: [BWWrong] { items.filter { !$0.fixed } }
    private var doneList: [BWWrong] { items.filter { $0.fixed } }

    var body: some View {
        VStack(spacing: 0) {
            BuwangTitle(ink: ink, zh: "错题本", en: "where he got it wrong")
                .padding(.top, -6)
            HStack(spacing: 6) {
                tabButton(0, "待修 \(openList.count)")
                tabButton(1, "已修 \(doneList.count)")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.top, 10)
            TabView(selection: $tab) {
                page(openList, empty: "现在没有待修的。试问或者「他最近的」里看到不对的，点一下就记进来。").tag(0)
                page(doneList, empty: "还没有修好的题。").tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .task { await load() }
        .sheet(item: $opened) { w in BuwangWrongDetail(ink: ink, item: w) }
    }

    private func tabButton(_ i: Int, _ title: String) -> some View {
        Button {
            buwangBuzz(.soft)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { tab = i }
        } label: {
            Text(title)
                .font(BuwangFont.hand(15))
                .foregroundColor(tab == i ? ink.ink : ink.ink2)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background {
                    if tab == i { Capsule().fill(ink.lilac).matchedGeometryEffect(id: "wtab", in: tabNS) }
                }
        }
        .buttonStyle(.plain)
    }

    private func page(_ list: [BWWrong], empty: String) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                if loading {
                    ProgressView().tint(ink.cherry).padding(.top, 30)
                } else if list.isEmpty {
                    Text(empty).font(.system(size: 11.5)).foregroundColor(ink.ink3).lineSpacing(4).padding(.top, 30)
                }
                ForEach(Array(list.enumerated()), id: \.element.id) { pair in
                    card(pair.element, first: pair.offset == 0)
                }
                if !list.isEmpty {
                    Text("攒几道叫我「看错题」：召错的、没召的我去改规矩；记忆本身写错的，你们定怎么改。修好的会收进测评，以后改坏了会报。长按一道可以自己标已修。")
                        .font(.system(size: 10.5))
                        .foregroundColor(ink.ink3)
                        .lineSpacing(4)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
    }

    private func kindColor(_ k: String) -> Color {
        if k == "该召没召" { return ink.blue }
        if k == "记忆写错了" { return ink.lilac }
        return ink.pink
    }

    private func card(_ w: BWWrong, first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(w.q.isEmpty ? (w.by.isEmpty ? "（没有原句）" : "\(w.by)交的修正") : "「\(w.q)」")
                .font(BuwangFont.hand(16.5))
                .foregroundColor(ink.ink)
                .lineLimit(3)
                .padding(.trailing, w.fixed ? 44 : 0)
            if !w.memoryTitle.isEmpty {
                Text((w.kind == "记忆写错了" ? "那条：" : "浮了：") + "《\(w.memoryTitle)》")
                    .font(.system(size: 11))
                    .foregroundColor(ink.ink2)
            }
            if !w.note.isEmpty {
                Text((w.by.isEmpty ? "你说：" : "\(w.by)说：") + w.note)
                    .font(.system(size: 11))
                    .foregroundColor(ink.cherry)
            }
            if w.fixed && !w.fixedNote.isEmpty {
                Text("修法：" + w.fixedNote).font(.system(size: 10.5)).foregroundColor(ink.ink3)
            }
            HStack(spacing: 6) {
                BuwangPill(text: w.kind, fill: kindColor(w.kind), ink: ink)
                Text("\(buwangTime(w.ts)) · \(w.source)").font(.system(size: 10)).foregroundColor(ink.ink3)
                Spacer()
                Text("看路线 ›").font(.system(size: 10)).foregroundColor(ink.ink3)
            }
            .padding(.top, 3)
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ink.card)
            .shadow(color: ink.shadow, radius: 7, x: 0, y: 4))
        .overlay(alignment: .topLeading) {
            if first && !w.fixed { BuwangTape(color: ink.pink).offset(x: 14, y: -6) }
        }
        .overlay(alignment: .topTrailing) {
            if w.fixed {
                BuwangStamp(text: "已修", color: Color.kakaoHex("#6aa894", .green)).padding(10)
            }
        }
        .opacity(w.fixed ? 0.8 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            buwangBuzz(.soft)
            opened = w
        }
        .contextMenu {
            if w.fixed {
                Button { Task { await setFixed(w, fixed: false) } } label: { Label("重开这道", systemImage: "arrow.uturn.backward") }
            } else {
                Button { Task { await setFixed(w, fixed: true) } } label: { Label("标成已修", systemImage: "checkmark.seal") }
            }
        }
    }

    private func load() async {
        let d = (try? await NativeHouseAPI.object("/api/lmc5/recall/wrongbook")) ?? [:]
        await MainActor.run {
            items = d.array("items").map { BWWrong($0) }
            loading = false
        }
    }

    private func setFixed(_ w: BWWrong, fixed: Bool) async {
        buwangBuzz(.medium)
        _ = try? await NativeHouseAPI.object("/api/lmc5/recall/wrongbook/fix", method: "POST",
                                             body: ["id": w.id, "status": fixed ? "fixed" : "open"])
        await load()
    }
}

/// 点开一道错题：她当时那句、错在哪；是「他的一轮」的就摊开那一轮的地铁线，是试问记的就摊开当时存下的那几站
struct BuwangWrongDetail: View {
    let ink: BuwangInk
    let item: BWWrong
    @ObservedObject private var fontStore = KakaoPackStore.shared

    var body: some View {
        if item.routeID > 0 {
            BuwangRouteSheet(ink: ink, routeID: item.routeID, q: item.q)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.q.isEmpty ? "\(item.by)交的修正" : "「\(item.q)」")
                        .font(BuwangFont.hand(20))
                        .foregroundColor(ink.ink)
                    HStack(spacing: 6) {
                        BuwangPill(text: item.kind, fill: ink.pink, ink: ink)
                        Text("\(buwangTime(item.ts)) · \(item.source)").font(.system(size: 10.5)).foregroundColor(ink.ink3)
                    }
                    if !item.memoryTitle.isEmpty {
                        Text("那条记忆：《\(item.memoryTitle)》").font(.system(size: 12.5)).foregroundColor(ink.ink2)
                    }
                    if !item.note.isEmpty {
                        Text(item.note).font(.system(size: 13)).foregroundColor(ink.cherry)
                    }
                    Text("试问时记下的错题，当时每一站怎么判的我都存着，叫我「看错题」时我会一站站查。")
                        .font(.system(size: 11))
                        .foregroundColor(ink.ink3)
                        .lineSpacing(3)
                        .padding(.top, 8)
                }
                .padding(24)
            }
            .background(BuwangPaper(ink: ink))
            .presentationDetents([.medium, .large])
        }
    }
}
