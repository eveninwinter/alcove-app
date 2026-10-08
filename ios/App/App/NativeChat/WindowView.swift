import SwiftUI
import UIKit
import CoreText

// 世界之窗（0923 工作室任务#2650~2663）
// 她看到别人做的「每天从开放图库抽漂亮照片和讲解」，说「开新页面呗」「全要吧先」，
// 又说「第一个字放大，后面正常，用衬线字做，页面要像一个图书馆的感觉，要有艺术美感」。
// 后端 window_api.py：每天北京 6 点后抓 9 张，中文讲解；/api/window/day、/card、/comment。
// 一张卡占一屏左右划；点开是一页「图录」：大图、NO.xx · 馆名、衬线标题、首字下沉的讲解、两个人的留言。

// MARK: - 模型

struct WindowComment: Identifiable, Equatable {
    let id: String
    let author: String
    let text: String
    let createdAt: String

    init?(json: [String: Any]) {
        guard let id = json["comment_id"] as? String else { return nil }
        self.id = id
        author = json["author"] as? String ?? ""
        text = json["text"] as? String ?? ""
        createdAt = json["created_at"] as? String ?? ""
    }

    var shortTime: String {
        // 2026-09-23T21:05:00+08:00 → 09·23 21:05
        guard createdAt.count >= 16 else { return createdAt }
        let s = Array(createdAt)
        return "\(String(s[5...6]))·\(String(s[8...9])) \(String(s[11...15]))"
    }
}

struct WindowCard: Identifiable, Equatable {
    let id: String
    let day: String
    let seq: Int
    let categoryZh: String
    let sourceName: String
    let title: String
    let titleZh: String
    let body: String
    let bodyZh: String
    let meta: String
    let metaZh: String
    let credit: String
    let link: String
    let imageUrl: String
    let thumbUrl: String
    let width: Int
    let height: Int
    var comments: [WindowComment]

    init?(json: [String: Any]) {
        guard let id = json["card_id"] as? String else { return nil }
        self.id = id
        day = json["day"] as? String ?? ""
        seq = json["seq"] as? Int ?? 0
        categoryZh = json["category_zh"] as? String ?? ""
        sourceName = json["source_name"] as? String ?? ""
        title = json["title"] as? String ?? ""
        titleZh = json["title_zh"] as? String ?? ""
        body = json["body"] as? String ?? ""
        bodyZh = json["body_zh"] as? String ?? ""
        meta = json["meta"] as? String ?? ""
        metaZh = json["meta_zh"] as? String ?? ""
        credit = json["credit"] as? String ?? ""
        link = json["link"] as? String ?? ""
        imageUrl = json["image_url"] as? String ?? ""
        thumbUrl = json["thumb_url"] as? String ?? ""
        width = json["width"] as? Int ?? 0
        height = json["height"] as? Int ?? 0
        comments = (json["comments"] as? [[String: Any]] ?? []).compactMap(WindowComment.init(json:))
    }

    var displayTitle: String { titleZh.isEmpty ? title : titleZh }
    var displayBody: String { bodyZh.isEmpty ? body : bodyZh }
    var displayMeta: String { metaZh.isEmpty ? meta : metaZh }
    var number: String { String(format: "NO.%02d", seq) }
    /// 后端给的是 /window/media/…，App 走 18003 的 /api 转发（转发层自己补 token）
    var imageURL: URL? { AlbumAPI.imageURL("/api" + imageUrl) }
    var thumbURL: URL? { AlbumAPI.imageURL("/api" + thumbUrl) }
}

struct WindowDay: Identifiable, Equatable {
    let day: String
    let count: Int
    var id: String { day }
}

@MainActor
final class WindowStore: ObservableObject {
    @Published var day = ""
    @Published var cards: [WindowCard] = []
    @Published var days: [WindowDay] = []
    @Published var loading = false
    @Published var failed = false

    func load(day: String? = nil) async {
        loading = true
        defer { loading = false }
        let q = (day ?? "").isEmpty ? "" : "?day=\(day!)"
        do {
            let d = try await NativeHouseAPI.object("/api/window/day\(q)")
            self.day = d["day"] as? String ?? ""
            cards = (d["cards"] as? [[String: Any]] ?? []).compactMap(WindowCard.init(json:))
            failed = false
        } catch {
            failed = cards.isEmpty
        }
    }

    func loadDays() async {
        guard let d = try? await NativeHouseAPI.object("/api/window/days") else { return }
        days = (d["days"] as? [[String: Any]] ?? []).compactMap {
            guard let day = $0["day"] as? String else { return nil }
            return WindowDay(day: day, count: $0["count"] as? Int ?? 0)
        }
    }

    func refreshCard(_ id: String) async {
        guard let d = try? await NativeHouseAPI.object("/api/window/card?id=\(id)"),
              let json = d["card"] as? [String: Any], let card = WindowCard(json: json),
              let idx = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[idx] = card
    }

    func comment(_ id: String, text: String) async -> Bool {
        let body: [String: Any] = ["card_id": id, "author": "陈霁", "text": text]
        guard (try? await NativeHouseAPI.object("/api/window/comment", method: "POST", body: body)) != nil else { return false }
        await refreshCard(id)
        return true
    }
}

// MARK: - 纸张与字体

/// 图书馆的纸：日间是象牙色的书页、墨色字、牛血红的小字；夜里是深褐的阅览室、灯下的米色字。
struct WindowPaper {
    let paper: Color
    let paperDeep: Color
    let ink: Color
    let inkSoft: Color
    let rubric: Color        // 古书里用红墨写的小标题（rubric），首字和 NO.xx 用它
    let rule: Color

    static func of(_ dark: Bool) -> WindowPaper {
        dark
            // 1001 她挑的黑夜 B「炭灰」：中性灰，不要深黑别太沉、不带棕；小标题淡紫
            ? WindowPaper(paper: Color(red: 0x32/255, green: 0x32/255, blue: 0x38/255),
                          paperDeep: Color(red: 0x2A/255, green: 0x2A/255, blue: 0x30/255),
                          ink: Color(red: 0xEF/255, green: 0xEE/255, blue: 0xF2/255),
                          inkSoft: Color(red: 0xA9/255, green: 0xA8/255, blue: 0xB3/255),
                          rubric: Color(red: 0xC9/255, green: 0xB4/255, blue: 0xEC/255),
                          rule: Color(red: 0xEF/255, green: 0xEE/255, blue: 0xF2/255).opacity(0.18))
            : WindowPaper(paper: Color(red: 0.96, green: 0.94, blue: 0.90), paperDeep: Color(red: 0.92, green: 0.89, blue: 0.84),
                          ink: Color(red: 0.17, green: 0.15, blue: 0.13), inkSoft: Color(red: 0.49, green: 0.45, blue: 0.40),
                          rubric: Color(red: 0.49, green: 0.18, blue: 0.16), rule: Color(red: 0.17, green: 0.15, blue: 0.13).opacity(0.16))
    }

    var uiInk: UIColor { UIColor(ink) }
    var uiRubric: UIColor { UIColor(rubric) }
}

enum WindowFont {
    /// 宋体（系统可下载字体）。没下好之前用系统衬线（New York），中文会退回苹方。
    static let songti = "STSongti-SC-Regular"
    static let songtiBold = "STSongti-SC-Bold"

    static func ui(_ size: CGFloat, bold: Bool = false) -> UIFont {
        if let f = UIFont(name: bold ? songtiBold : songti, size: size) { return f }
        let base = UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        if let d = base.fontDescriptor.withDesign(.serif) { return UIFont(descriptor: d, size: size) }
        return base
    }

    static func swiftUI(_ size: CGFloat, bold: Bool = false) -> Font { Font(ui(size, bold: bold) as CTFont) }

    /// 西文小字（NO.xx · 馆名）：衬线小型大写 + 字距
    static func smallCaps(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .serif) }

    /// 宋体是 iOS 的按需下载字体：第一次进来后台请求一次，下好以后再开页面就是宋体
    static func requestSongti() {
        guard UIFont(name: songti, size: 12) == nil else { return }
        let descs = [songti, songtiBold].map {
            CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: $0] as CFDictionary)
        } as CFArray
        _ = CTFontDescriptorMatchFontDescriptorsWithProgressHandler(descs, nil) { _, _ in true }
    }
}

// MARK: - 首字下沉

/// SwiftUI 的 Text 绕不了排：首字画成一个大字贴在左上，正文用 exclusionPath 让出那一块。
struct DropCapText: UIViewRepresentable {
    let text: String
    let paper: WindowPaper
    var bodySize: CGFloat = 16.5
    var lines: Int = 3

    func makeUIView(context: Context) -> DropCapTextView {
        let v = DropCapTextView()
        v.isEditable = false
        v.isScrollEnabled = false
        v.isSelectable = true
        v.backgroundColor = .clear
        v.textContainerInset = .zero
        v.textContainer.lineFragmentPadding = 0
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return v
    }

    func updateUIView(_ v: DropCapTextView, context: Context) {
        v.configure(text: text, paper: paper, bodySize: bodySize, lines: lines)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: DropCapTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 48
        return CGSize(width: width, height: uiView.height(for: width))
    }
}

/// 首字（大字）自己画：量字形墨迹摆位置，不靠字号猜。
/// 0925 她抓的「第一个大字位置不对、偏下」：原来是 UILabel 按字号摆，宋体字身上方留白大，
/// 字形被往下推了一截，顶比第一行矮、底压到第四行。
final class DropCapGlyphView: UIView {
    var line: CTLine?
    var baseline: CGFloat = 0   // 基线离本 view 顶边多远
    var inkLeft: CGFloat = 0    // 画的时候往左挪多少，让墨迹左边落在 pad 处

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let line, let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: -inkLeft, y: bounds.height - baseline)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}

final class DropCapTextView: UITextView {
    private let cap = DropCapGlyphView()
    private var capSize: CGSize = .zero
    private var key = ""
    private var bodyAscender: CGFloat = 0
    private var bodyInkTop: CGFloat = 0     // 正文一个汉字的墨迹顶离基线多高
    private let capPad: CGFloat = 4

    /// 一串字的墨迹框（基线坐标，y 朝上）
    private static func ink(_ line: CTLine) -> CGRect {
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        return CTLineGetImageBounds(line, ctx)
    }

    private static func ink(of text: String, font: UIFont) -> CGRect {
        ink(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]) as CFAttributedString))
    }

    func configure(text: String, paper: WindowPaper, bodySize: CGFloat, lines: Int) {
        let newKey = "\(text.hashValue)|\(bodySize)|\(lines)|\(paper.uiInk.hash)"
        guard newKey != key else { return }
        key = newKey
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 开头是引号/括号的，连同后面那个字一起当首字，不然首字是个孤零零的「“」
        var capCount = 1
        if let f = trimmed.first, "“\"‘'「『（(《".contains(f), trimmed.count > 1 { capCount = 2 }
        let first = String(trimmed.prefix(capCount))
        let rest = String(trimmed.dropFirst(capCount))

        let body = WindowFont.ui(bodySize)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = bodySize * 0.62
        para.paragraphSpacing = bodySize * 0.9
        para.alignment = .justified
        let lineHeight = body.lineHeight + para.lineSpacing
        attributedText = NSAttributedString(string: rest, attributes: [
            .font: body, .foregroundColor: paper.uiInk, .paragraphStyle: para, .kern: 0.4,
        ])
        bodyAscender = body.ascender

        // 首字的大小：墨迹从第一行汉字的顶，一直到第 lines 行汉字的底（拿「国」量正文汉字的墨迹）
        let probe = Self.ink(of: "国", font: body)
        bodyInkTop = probe.maxY
        let target = lineHeight * CGFloat(lines - 1) + probe.maxY - probe.minY
        let ref = Self.ink(of: first, font: WindowFont.ui(100))
        let capPt = ref.height > 0 ? 100 * target / ref.height : lineHeight * CGFloat(lines) * 0.92
        let capLine = CTLineCreateWithAttributedString(NSAttributedString(string: first, attributes: [
            .font: WindowFont.ui(capPt),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): paper.uiRubric.cgColor,
        ]) as CFAttributedString)
        let capInk = Self.ink(capLine)
        cap.line = capLine
        cap.inkLeft = capInk.minX - capPad
        cap.baseline = capPad + capInk.maxY
        cap.frame.size = CGSize(width: ceil(capInk.width) + capPad * 2, height: ceil(capInk.height) + capPad * 2)
        cap.setNeedsDisplay()
        if cap.superview == nil { addSubview(cap) }
        capSize = CGSize(width: ceil(capInk.width) + bodySize * 0.7,
                         height: lineHeight * CGFloat(lines) - para.lineSpacing * 0.5)
        textContainer.exclusionPaths = [UIBezierPath(rect: CGRect(origin: .zero, size: capSize))]
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 第一行的基线问排版器要（宋体上沿留白大，自己按字号算会偏）；没正文就按字体上沿兜底
        var baseline1 = bodyAscender
        if layoutManager.numberOfGlyphs > 0 {
            let frag = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
            baseline1 = frag.minY + layoutManager.location(forGlyphAt: 0).y
        }
        // 大字墨迹顶对齐第一行汉字墨迹顶，左边贴正文左边
        cap.frame.origin = CGPoint(x: -capPad, y: baseline1 - bodyInkTop - capPad)
    }

    func height(for width: CGFloat) -> CGFloat {
        if bounds.width != width { frame.size.width = width }
        textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer).height
        return ceil(max(used, capSize.height)) + 2
    }
}

// MARK: - 主页面

struct NativeWindowView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""   // 1001：黑白跟全屋那一个开关走
    @StateObject private var store = WindowStore()
    @State private var page = 0
    @State private var opened: WindowCard?
    @State private var showDays = false
    // 0927 她挑的效果图：一幅一屏 / 目录 两种看法；目录里分 今天 / 往期 / 我们留过言的
    @State private var gridMode = false
    // 1008 她要的第三栏「审美积累」：Are.na 图板里每天挑九张（后端 aesthetic.py）
    @State private var aestheticMode = false
    @StateObject private var aesthetic = AestheticStore()
    @State private var tab = 0
    @State private var commented: [WindowCard] = []
    /// 读过的记在手机本地就够了（不上后端），留最近 400 张
    @AppStorage("windowReadIDs") private var readRaw = ""
    @Namespace private var zoomNS
    private var paper: WindowPaper { _ = houseAppearance; return .of(AlcoveAppearance.isDark) }
    private var readIDs: Set<String> { Set(readRaw.split(separator: ",").map(String.init)) }

    /// 0925 她抓的「世界之窗又没做安全区」：这间屋是 ownsFullScreen，外面那层把安全区全吃了，
    /// 头顶到灵动岛、页码贴着 Home 横条。全屏房间第一件事：安全区问 app 主窗（跟占星室、育儿室一样）。
    private var safeTop: CGFloat {
        FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0
    }
    private var safeBottom: CGFloat {
        FloatingOverlay.appWindow()?.safeAreaInsets.bottom ?? 0
    }

    var body: some View {
        ZStack(alignment: .top) {
            paper.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if store.cards.isEmpty && !gridMode && !aestheticMode {
                    emptyState
                } else {
                    dateline
                    if aestheticMode {
                        AestheticBoard(store: aesthetic, paper: paper, bottomPad: max(safeBottom, 10) + 20)
                    } else if gridMode {
                        catalog
                    } else {
                        TabView(selection: $page) {
                            ForEach(Array(store.cards.enumerated()), id: \.element.id) { i, card in
                                WindowPlate(card: card, paper: paper)
                                    .contentShape(Rectangle())
                                    .matchedTransitionSource(id: card.id, in: zoomNS)
                                    .onTapGesture { open(card) }
                                    .padding(.horizontal, 18)
                                    .padding(.bottom, 8)
                                    .tag(i)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        thumbStrip
                        folio
                    }
                }
            }
        }
        .task {
            WindowFont.requestSongti()
            await store.load()
        }
        .fullScreenCover(item: $opened) { card in
            WindowCardPage(store: store, cardId: card.id, paper: paper)
                .navigationTransition(.zoom(sourceID: card.id, in: zoomNS))
        }
        .sheet(isPresented: $showDays) { daysSheet }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("返回")
            Spacer()
            VStack(spacing: 3) {
                Text("世界之窗").font(WindowFont.swiftUI(21, bold: true)).tracking(4)
                Text("A WINDOW ON THE WORLD").font(WindowFont.smallCaps(8.5)).tracking(2.6).foregroundColor(paper.inkSoft)
            }
            Spacer()
            Button { showDays = true; Task { await store.loadDays() } } label: {
                Image(systemName: "books.vertical").font(.system(size: 16, weight: .regular))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("往期")
        }
        .foregroundColor(paper.ink)
        .padding(.horizontal, 8)
        .padding(.top, max(safeTop, 20))
        .padding(.bottom, 6)
    }

    // MARK: 0927 丰富版：日期行＋看法切换、缩略图条、目录

    private func markRead(_ id: String) {
        var ids = readRaw.split(separator: ",").map(String.init).filter { $0 != id }
        ids.append(id)
        readRaw = ids.suffix(400).joined(separator: ",")
    }

    /// 点开一张：今天这批里有就直接开；「留过言的」可能是往期的，先把那天翻出来再开
    private func open(_ card: WindowCard) {
        markRead(card.id)
        if store.cards.contains(where: { $0.id == card.id }) {
            opened = card
            return
        }
        Task {
            await store.load(day: card.day)
            if let i = store.cards.firstIndex(where: { $0.id == card.id }) {
                page = i
                opened = store.cards[i]
            }
        }
    }

    private static func cn(_ n: Int) -> String {
        let d = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        if n < 10 { return d[max(0, n)] }
        if n < 20 { return "十" + (n % 10 == 0 ? "" : d[n % 10]) }
        if n < 100 { return d[n / 10] + "十" + (n % 10 == 0 ? "" : d[n % 10]) }
        return "\(n)"
    }

    /// 九月廿七
    private func cnDay(_ day: String) -> String {
        let p = day.split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]) else { return day }
        let month = Self.cn(m) + "月"
        let date: String
        switch d {
        case 20: date = "二十"
        case 21...29: date = "廿" + Self.cn(d - 20)
        case 30: date = "三十"
        case 31: date = "卅一"
        default: date = Self.cn(d)
        }
        return month + date
    }

    private var dateline: some View {
        HStack {
            Text(aestheticMode ? (aesthetic.day.isEmpty ? "" : cnDay(aesthetic.day))
                 : (store.day.isEmpty ? "" : "\(cnDay(store.day)) · 今天\(Self.cn(store.cards.count))幅"))
                .font(WindowFont.swiftUI(12)).tracking(1.5).foregroundColor(paper.inkSoft)
            Spacer()
            HStack(spacing: 0) {
                modeButton("一幅一屏", on: !gridMode && !aestheticMode) { gridMode = false; aestheticMode = false }
                modeButton("目录", on: gridMode && !aestheticMode) { gridMode = true; aestheticMode = false }
                modeButton("审美积累", on: aestheticMode) { aestheticMode = true }
            }
            .overlay(Capsule().stroke(paper.rule, lineWidth: 1))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private func modeButton(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) { action() }
        } label: {
            Text(title).font(WindowFont.swiftUI(11))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .foregroundColor(on ? paper.paper : paper.inkSoft)
                .background(on ? paper.ink : Color.clear)
        }
        .buttonStyle(.plain)
    }

    /// 大图下面一排小图：现在这张红框圈着，点哪张跳哪张
    private var thumbStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(store.cards.enumerated()), id: \.element.id) { i, c in
                        CachedPhaseImage(url: c.thumbURL) { phase in
                            switch phase {
                            case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                            default: paper.paperDeep
                            }
                        }
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .opacity(i == page ? 1 : 0.55)
                        .padding(3)
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(paper.rubric, lineWidth: i == page ? 1.5 : 0))
                        .id(i)
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.35)) { page = i } }
                    }
                }
                .padding(.horizontal, 20)
                .frame(minWidth: UIScreen.main.bounds.width)
            }
            .onChange(of: page) { _, p in
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(p, anchor: .center) }
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    // ── 目录 ──
    private var catalog: some View {
        VStack(spacing: 0) {
            HStack(spacing: 22) {
                tabButton("今天", 0)
                tabButton("往期", 1)
                tabButton("我们留过言的", 2)
                Spacer()
            }
            .padding(.horizontal, 22)
            .overlay(alignment: .bottom) { Rectangle().fill(paper.rule).frame(height: 0.6) }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    switch tab {
                    case 1: pastDays
                    case 2:
                        if commented.isEmpty {
                            Text("还没有留过言的画").font(WindowFont.swiftUI(14)).foregroundColor(paper.inkSoft)
                                .frame(maxWidth: .infinity).padding(.top, 60)
                        } else {
                            masonry(commented).padding(.top, 16)
                        }
                    default:
                        todayLead
                        masonry(store.cards)
                    }
                }
                .padding(.bottom, max(safeBottom, 10) + 20)
            }
        }
        .task(id: tab) {
            if tab == 1 { await store.loadDays() }
            if tab == 2 { await loadCommented() }
        }
    }

    private func tabButton(_ title: String, _ i: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { tab = i }
        } label: {
            Text(title).font(WindowFont.swiftUI(14))
                .foregroundColor(tab == i ? paper.ink : paper.inkSoft)
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(paper.rubric).frame(height: 2).opacity(tab == i ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
    }

    private var todayLead: some View {
        let isLatest = store.days.first.map { $0.day == store.day } ?? true
        var kinds: [(String, Int)] = []
        for c in store.cards {
            if let i = kinds.firstIndex(where: { $0.0 == c.categoryZh }) { kinds[i].1 += 1 } else { kinds.append((c.categoryZh, 1)) }
        }
        let summary = kinds.map { "\($0.0)\(Self.cn($0.1))幅" }.joined(separator: " · ")
        let read = store.cards.filter { readIDs.contains($0.id) }.count
        let his = store.cards.reduce(0) { $0 + $1.comments.filter { $0.author == "陈璟" }.count }
        var note = "你读过\(Self.cn(read))幅"
        if his > 0 { note += "，他留了\(Self.cn(his))句话" }
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(isLatest ? "今天" : cnDay(store.day))，世界送来\(Self.cn(store.cards.count))幅。")
                .font(WindowFont.swiftUI(26, bold: true)).tracking(1)
            Text(summary).font(WindowFont.swiftUI(12)).foregroundColor(paper.inkSoft).lineSpacing(5)
            Text(note + "。").font(WindowFont.swiftUI(12)).foregroundColor(paper.inkSoft)
        }
        .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 16)
    }

    /// 两列错落：高矮按图本身的比例来（拿不到就按位置错开）
    private func masonry(_ cards: [WindowCard]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 12) {
                ForEach(Array(cards.enumerated()).filter { $0.offset % 2 == 0 }, id: \.element.id) { i, c in tile(c, i) }
            }
            VStack(spacing: 12) {
                ForEach(Array(cards.enumerated()).filter { $0.offset % 2 == 1 }, id: \.element.id) { i, c in tile(c, i) }
            }
        }
        .padding(.horizontal, 16)
    }

    private func tile(_ c: WindowCard, _ i: Int) -> some View {
        let fallback: [CGFloat] = [1.2, 0.9, 1.05, 1.3, 0.95, 1.15, 1.0, 0.85, 1.25]
        let ratio: CGFloat = (c.width > 0 && c.height > 0)
            ? min(1.45, max(0.75, CGFloat(c.height) / CGFloat(c.width)))
            : fallback[i % fallback.count]
        return Color.clear
            .aspectRatio(1 / ratio, contentMode: .fit)
            .overlay {
                CachedPhaseImage(url: c.thumbURL ?? c.imageURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                    default: paper.paperDeep
                    }
                }
            }
            .overlay {
                LinearGradient(stops: [.init(color: .clear, location: 0.4), .init(color: .black.opacity(0.62), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(c.number) · \(c.categoryZh)")
                        .font(WindowFont.smallCaps(9)).tracking(2).opacity(0.85)
                    Text(c.displayTitle).font(WindowFont.swiftUI(15, bold: true)).lineLimit(2)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.bottom, 11)
            }
            .overlay(alignment: .topLeading) {
                if readIDs.contains(c.id) {
                    Text("读过").font(.system(size: 9)).foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1.5)
                        .overlay(Capsule().stroke(.white.opacity(0.7), lineWidth: 1))
                        .padding(10)
                }
            }
            .overlay(alignment: .topTrailing) {
                if !c.comments.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "text.bubble").font(.system(size: 9))
                        Text("\(c.comments.count)").font(.system(size: 10))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.35)))
                    .padding(10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .matchedTransitionSource(id: c.id, in: zoomNS)
            .onTapGesture { open(c) }
    }

    private var pastDays: some View {
        VStack(spacing: 0) {
            ForEach(store.days) { d in
                Button {
                    page = 0
                    Task {
                        await store.load(day: d.day)
                        withAnimation(.easeInOut(duration: 0.25)) { tab = 0 }
                    }
                } label: {
                    HStack {
                        Text(cnDay(d.day)).font(WindowFont.swiftUI(16)).foregroundColor(paper.ink)
                        Text(dayText(d.day)).font(WindowFont.smallCaps(10)).tracking(1.5).foregroundColor(paper.inkSoft)
                        Spacer()
                        Text("\(d.count) 幅").font(WindowFont.swiftUI(13)).foregroundColor(paper.inkSoft)
                        if d.day == store.day { Image(systemName: "bookmark.fill").foregroundColor(paper.rubric) }
                    }
                    .padding(.horizontal, 22).padding(.vertical, 14)
                    .overlay(alignment: .bottom) { Rectangle().fill(paper.rule).frame(height: 0.6).padding(.horizontal, 22) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func loadCommented() async {
        guard let d = try? await NativeHouseAPI.object("/api/window/commented") else { return }
        commented = (d["cards"] as? [[String: Any]] ?? []).compactMap(WindowCard.init(json:))
    }

    /// 页脚：像书的页码
    private var folio: some View {
        HStack(spacing: 10) {
            Rectangle().fill(paper.rule).frame(height: 0.6)
            Text("\(dayText(store.day))  ·  \(page + 1) / \(store.cards.count)")
                .font(WindowFont.smallCaps(10)).tracking(1.8).foregroundColor(paper.inkSoft).fixedSize()
            Rectangle().fill(paper.rule).frame(height: 0.6)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, max(safeBottom, 10))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            if store.loading {
                ProgressView().tint(paper.inkSoft)
            } else {
                Text("❦").font(.system(size: 28, design: .serif)).foregroundColor(paper.rubric)
                Text(store.failed ? "书架暂时打不开" : "今天的画册还没到").font(WindowFont.swiftUI(17)).foregroundColor(paper.ink)
                Text(store.failed ? "下拉再试一次" : "每天早上六点以后送来").font(WindowFont.swiftUI(13)).foregroundColor(paper.inkSoft)
            }
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private var daysSheet: some View {
        NavigationStack {
            List(store.days) { d in
                Button {
                    showDays = false
                    page = 0
                    Task { await store.load(day: d.day) }
                } label: {
                    HStack {
                        Text(dayText(d.day)).font(WindowFont.swiftUI(16)).foregroundColor(paper.ink)
                        Spacer()
                        Text("\(d.count) 幅").font(WindowFont.swiftUI(13)).foregroundColor(paper.inkSoft)
                        if d.day == store.day { Image(systemName: "bookmark.fill").foregroundColor(paper.rubric) }
                    }
                }
                .listRowBackground(paper.paper)
            }
            .scrollContentBackground(.hidden)
            .background(paper.paper)
            .navigationTitle("往期")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func dayText(_ day: String) -> String {
        let p = day.split(separator: "-")
        guard p.count == 3 else { return day }
        return "\(p[0]) · \(p[1]) · \(p[2])"
    }
}

/// 一屏一幅：上面是图，往下化进纸里；底下是馆名小字和标题。
private struct WindowPlate: View {
    let card: WindowCard
    let paper: WindowPaper

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottom) {
                    CachedPhaseImage(url: card.imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .empty:
                            paper.paperDeep.overlay(ProgressView().tint(paper.inkSoft))
                        case .failure:
                            paper.paperDeep.overlay(Image(systemName: "photo").foregroundColor(paper.inkSoft))
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height * 0.72)
                    .clipped()
                    LinearGradient(colors: [paper.paper.opacity(0), paper.paper.opacity(0.85), paper.paper],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: geo.size.height * 0.2)
                }
                .frame(height: geo.size.height * 0.72)

                VStack(alignment: .leading, spacing: 10) {
                    Capsule().fill(paper.rule).frame(width: 30, height: 2.5)
                        .frame(maxWidth: .infinity)
                    Text("\(card.number)  ·  \(card.sourceName)")
                        .font(WindowFont.smallCaps(9.5)).tracking(2.2).foregroundColor(paper.rubric)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(card.displayTitle)
                        .font(WindowFont.swiftUI(24, bold: true)).foregroundColor(paper.ink)
                        .lineLimit(2).minimumScaleFactor(0.75).lineSpacing(3)
                    HStack(spacing: 6) {
                        Text(card.categoryZh).font(WindowFont.swiftUI(12)).foregroundColor(paper.inkSoft)
                        if !card.comments.isEmpty {
                            Text("·").foregroundColor(paper.inkSoft)
                            Image(systemName: "text.bubble").font(.system(size: 10)).foregroundColor(paper.inkSoft)
                            Text("\(card.comments.count)").font(WindowFont.swiftUI(12)).foregroundColor(paper.inkSoft)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 2)
                Spacer(minLength: 0)
            }
            .background(paper.paper)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(paper.rule, lineWidth: 0.6))
            .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
        }
    }
}

// MARK: - 一页图录

private struct WindowCardPage: View {
    @ObservedObject var store: WindowStore
    let cardId: String
    let paper: WindowPaper
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var sending = false
    @State private var zoom = false
    @State private var showOriginal = false
    @FocusState private var focused: Bool

    private var card: WindowCard? { store.cards.first { $0.id == cardId } }

    var body: some View {
        ZStack(alignment: .topLeading) {
            paper.paper.ignoresSafeArea()
            if let card {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        CachedPhaseImage(url: card.imageURL) { phase in
                            switch phase {
                            case .success(let image): image.resizable().aspectRatio(contentMode: .fit)
                            default: paper.paperDeep.frame(height: 280).overlay(ProgressView().tint(paper.inkSoft))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { zoom = true }

                        VStack(alignment: .leading, spacing: 14) {
                            Text("\(card.number)  ·  \(card.sourceName)")
                                .font(WindowFont.smallCaps(10)).tracking(2.2).foregroundColor(paper.rubric)
                            Text(card.displayTitle)
                                .font(WindowFont.swiftUI(27, bold: true)).foregroundColor(paper.ink).lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                            if !card.titleZh.isEmpty && card.titleZh != card.title {
                                Text(card.title).font(.system(size: 14, design: .serif).italic()).foregroundColor(paper.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if !card.displayMeta.isEmpty {
                                Text(card.displayMeta).font(WindowFont.swiftUI(13)).foregroundColor(paper.inkSoft).lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            ornament
                            DropCapText(text: showOriginal ? card.body : card.displayBody, paper: paper)
                            if !card.bodyZh.isEmpty {
                                Button { showOriginal.toggle() } label: {
                                    Text(showOriginal ? "看译文" : "看原文")
                                        .font(WindowFont.swiftUI(12)).foregroundColor(paper.rubric)
                                        .underline(true, color: paper.rubric.opacity(0.4))
                                }.buttonStyle(.plain)
                            }
                            colophon(card)
                            ornament
                            marginalia(card)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 22)
                        .padding(.bottom, 40)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) { commentBar(card) }
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                    .foregroundColor(paper.ink)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 16).padding(.top, 8)
            .accessibilityLabel("合上")
        }
        .fullScreenCover(isPresented: $zoom) {
            WindowZoomView(url: card?.imageURL)
        }
    }

    private var ornament: some View {
        HStack(spacing: 12) {
            Rectangle().fill(paper.rule).frame(height: 0.6)
            Text("❦").font(.system(size: 15, design: .serif)).foregroundColor(paper.rubric.opacity(0.8))
            Rectangle().fill(paper.rule).frame(height: 0.6)
        }
        .padding(.vertical, 6)
    }

    /// 书末版权页那种小字：出处、授权、原页面
    private func colophon(_ card: WindowCard) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if !card.credit.isEmpty {
                Text(card.credit).font(.system(size: 11, design: .serif)).foregroundColor(paper.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = URL(string: card.link), !card.link.isEmpty {
                Link(destination: url) {
                    Text("查看原页面 ↗").font(WindowFont.swiftUI(12)).foregroundColor(paper.rubric)
                }
            }
        }
        .padding(.top, 4)
    }

    /// 页边批注：两个人的留言
    private func marginalia(_ card: WindowCard) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("批 注").font(WindowFont.swiftUI(15, bold: true)).tracking(6).foregroundColor(paper.ink)
            if card.comments.isEmpty {
                Text("还没有人在这一页留字。").font(WindowFont.swiftUI(13)).foregroundColor(paper.inkSoft)
            }
            ForEach(card.comments) { c in
                HStack(alignment: .top, spacing: 12) {
                    Rectangle().fill(c.author == "陈璟" ? paper.rubric : paper.inkSoft.opacity(0.6)).frame(width: 1.5)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(c.author).font(WindowFont.swiftUI(13, bold: true)).foregroundColor(paper.ink)
                            Text(c.shortTime).font(.system(size: 10.5, design: .serif)).foregroundColor(paper.inkSoft)
                        }
                        Text(c.text).font(WindowFont.swiftUI(15)).foregroundColor(paper.ink).lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func commentBar(_ card: WindowCard) -> some View {
        HStack(spacing: 10) {
            TextField("在这一页留字……", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .font(WindowFont.swiftUI(15))
                .foregroundColor(paper.ink)
                .focused($focused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(paper.paperDeep, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Button {
                let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, !sending else { return }
                sending = true
                Task {
                    if await store.comment(card.id, text: text) { draft = ""; focused = false }
                    sending = false
                }
            } label: {
                Group {
                    if sending { ProgressView().tint(paper.paper) }
                    else { Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)) }
                }
                .foregroundColor(paper.paper)
                .frame(width: 38, height: 38)
                .background(paper.rubric.opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("留字")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(paper.paper.opacity(0.96))
        .overlay(alignment: .top) { Rectangle().fill(paper.rule).frame(height: 0.6) }
    }
}

// MARK: - 1008 审美积累（效果图 /root/workroom/mock/aesthetic/mock.jpg，她说「行」）

struct AestheticPin: Identifiable, Equatable {
    let id: String
    let caption: String
    let boardTitle: String
    let boardZh: String
    let imageUrl: String
    let thumbUrl: String
    let width: Int
    let height: Int

    init?(json: [String: Any]) {
        guard let id = json["pin_id"] as? String, let image = json["image_url"] as? String else { return nil }
        self.id = id
        caption = json["caption"] as? String ?? ""
        boardTitle = json["board_title"] as? String ?? ""
        boardZh = json["board_zh"] as? String ?? ""
        imageUrl = image
        thumbUrl = json["thumb_url"] as? String ?? image
        width = json["width"] as? Int ?? 0
        height = json["height"] as? Int ?? 0
    }

    var imageURL: URL? { AlbumAPI.imageURL("/api" + imageUrl) }
    var thumbURL: URL? { AlbumAPI.imageURL("/api" + thumbUrl) }
    /// 高 / 宽，压在 0.5～2.2 之间，免得超长图把一列撑爆
    var ratio: CGFloat {
        guard width > 0, height > 0 else { return 1.2 }
        return min(2.2, max(0.5, CGFloat(height) / CGFloat(width)))
    }
}

final class AestheticStore: ObservableObject {
    @Published var day = ""
    @Published var pins: [AestheticPin] = []
    @Published var loaded = false

    func load(day: String? = nil) async {
        let q = (day ?? "").isEmpty ? "" : "?day=\(day!)"
        if let d = try? await NativeHouseAPI.object("/api/window/aesthetic\(q)") {
            self.day = d["day"] as? String ?? ""
            pins = (d["pins"] as? [[String: Any]] ?? []).compactMap(AestheticPin.init(json:))
        }
        loaded = true
    }
}

private struct AestheticBoard: View {
    @ObservedObject var store: AestheticStore
    let paper: WindowPaper
    let bottomPad: CGFloat
    @State private var zoomed: AestheticPin?

    private static func cn(_ n: Int) -> String {
        let d = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        if n < 10 { return d[max(0, n)] }
        if n < 20 { return "十" + (n % 10 == 0 ? "" : d[n % 10]) }
        return "\(n)"
    }

    /// 两列按图的高矮贪心分：每张放进当前更矮的那列（跟效果图一样错落）
    private var columns: ([AestheticPin], [AestheticPin]) {
        var l: [AestheticPin] = [], r: [AestheticPin] = []
        var hl: CGFloat = 0, hr: CGFloat = 0
        for p in store.pins {
            if hl <= hr { l.append(p); hl += p.ratio + 0.25 } else { r.append(p); hr += p.ratio + 0.25 }
        }
        return (l, r)
    }

    private var boardLine: String {
        var names: [String] = []
        for p in store.pins where !p.boardZh.isEmpty && !names.contains(p.boardZh) { names.append(p.boardZh) }
        return names.prefix(4).joined(separator: "、")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    (Text("审美积累") + Text("。").foregroundColor(paper.rubric))
                        .font(WindowFont.swiftUI(26, bold: true)).tracking(1)
                    Text("A CABINET OF PRETTY THINGS").font(WindowFont.smallCaps(8.5)).tracking(2.6)
                        .foregroundColor(paper.rubric)
                    Group {
                        if store.pins.isEmpty {
                            Text(store.loaded ? "今天的还在挑，过一会儿再来。" : "")
                        } else {
                            Text("今天从\(boardLine)几个图板里，挑了\(Self.cn(store.pins.count))幅。\n点开看大图，长按收进相册。")
                        }
                    }
                    .font(WindowFont.swiftUI(12)).foregroundColor(paper.inkSoft).lineSpacing(5)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 22).padding(.top, 14)
                Text("❦").font(.system(size: 14)).foregroundColor(paper.rubric)
                    .frame(maxWidth: .infinity).padding(.top, 12).padding(.bottom, 12)
                let cols = columns
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 16) { ForEach(cols.0) { pin($0) } }
                    VStack(spacing: 16) { ForEach(cols.1) { pin($0) } }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, bottomPad)
        }
        .task { if !store.loaded { await store.load() } }
        .refreshable { await store.load() }
        .fullScreenCover(item: $zoomed) { p in WindowZoomView(url: p.imageURL) }
    }

    private func pin(_ p: AestheticPin) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(1 / p.ratio, contentMode: .fit)
                .overlay {
                    CachedPhaseImage(url: p.thumbURL ?? p.imageURL) { phase in
                        switch phase {
                        case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                        default: paper.paperDeep
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onTapGesture { zoomed = p }
                .contextMenu {
                    Button {
                        if let u = p.imageURL { Task { await PhotoLibrarySaver.save(u) } }
                    } label: { Label("存到手机相册", systemImage: "square.and.arrow.down") }
                }
            if !p.caption.isEmpty {
                Text(p.caption).font(WindowFont.swiftUI(12.5)).tracking(0.5).foregroundColor(paper.ink)
                    .lineLimit(2).padding(.top, 7)
            }
            if !p.boardTitle.isEmpty {
                Text("FROM · \(p.boardTitle.uppercased())").font(WindowFont.smallCaps(7)).tracking(1.8)
                    .foregroundColor(paper.inkSoft).lineLimit(1).padding(.top, 3)
            }
        }
    }
}

/// 点图全屏：黑底、双指放大、双击复原
private struct WindowZoomView: View {
    let url: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            CachedPhaseImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().aspectRatio(contentMode: .fit)
                default: ProgressView().tint(.white)
                }
            }
            .scaleEffect(scale)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gesture(
                MagnifyGesture()
                    .onChanged { v in scale = max(1, min(base * v.magnification, 6)) }
                    .onEnded { _ in base = scale; if scale == 1 { offset = .zero; lastOffset = .zero } }
                    .simultaneously(with: DragGesture()
                        .onChanged { v in
                            guard scale > 1 else { return }
                            offset = CGSize(width: lastOffset.width + v.translation.width,
                                            height: lastOffset.height + v.translation.height)
                        }
                        .onEnded { _ in lastOffset = offset })
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeOut(duration: 0.2)) { scale = 1; base = 1; offset = .zero; lastOffset = .zero }
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                    .frame(width: 40, height: 40).background(.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 18).padding(.top, 10)
        }
    }
}
