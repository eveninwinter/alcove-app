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
            ? WindowPaper(paper: Color(red: 0.10, green: 0.09, blue: 0.08), paperDeep: Color(red: 0.07, green: 0.06, blue: 0.05),
                          ink: Color(red: 0.91, green: 0.87, blue: 0.80), inkSoft: Color(red: 0.63, green: 0.58, blue: 0.51),
                          rubric: Color(red: 0.80, green: 0.55, blue: 0.43), rule: Color(red: 0.91, green: 0.87, blue: 0.80).opacity(0.18))
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
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @StateObject private var store = WindowStore()
    @State private var page = 0
    @State private var opened: WindowCard?
    @State private var showDays = false
    private var paper: WindowPaper { .of(AlcoveTheme.named(themeName).isDark) }

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
                if store.cards.isEmpty {
                    emptyState
                } else {
                    TabView(selection: $page) {
                        ForEach(Array(store.cards.enumerated()), id: \.element.id) { i, card in
                            WindowPlate(card: card, paper: paper)
                                .contentShape(Rectangle())
                                .onTapGesture { opened = card }
                                .padding(.horizontal, 18)
                                .padding(.bottom, 14)
                                .tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    folio
                }
            }
        }
        .task {
            WindowFont.requestSongti()
            await store.load()
        }
        .fullScreenCover(item: $opened) { card in
            WindowCardPage(store: store, cardId: card.id, paper: paper)
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
