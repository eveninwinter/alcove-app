import SwiftUI
import UIKit

// 0921 任务#2505 她要的 iMessage 式「文字效果」。
//
// 标记直接写在消息文本里：[摇晃]亲亲[/摇晃]。八种动画（放大 缩小 摇晃 点头 爆炸 波纹 绽放 抖动）
// 加四种样式（粗体 斜体 下划线 删除线），可以套着写。老消息没标记照旧走 SelectableMessageText，
// 有标记的气泡换成 EffectText 逐字画。他那边不用改代码，回复里写同样的标记就会动。
//
// 打字框这头：选中几个字 → 长按菜单里多一项「文字效果」（AppDelegate.buildMenu 全局挂的，
// 只在聊天打字框聚焦时出现）→ 升起 TextEffectPanel → 点一个就把标记套到选中的字上。
// 什么都没选就套整条。

enum TextEffectKind: String, CaseIterable, Identifiable {
    case big = "放大", small = "缩小", shake = "摇晃", nod = "点头"
    case explode = "爆炸", ripple = "波纹", bloom = "绽放", jitter = "抖动"
    case bold = "粗体", italic = "斜体", underline = "下划线", strike = "删除线"

    var id: String { rawValue }
    var open: String { "[\(rawValue)]" }
    var close: String { "[/\(rawValue)]" }
    var isStyle: Bool { Self.styles.contains(self) }
    static let animated: [TextEffectKind] = [.big, .small, .shake, .nod, .explode, .ripple, .bloom, .jitter]
    static let styles: [TextEffectKind] = [.bold, .italic, .underline, .strike]
}

enum TextEffects {
    struct Segment: Identifiable {
        let id: Int
        let text: String
        let effects: [TextEffectKind]
    }

    static let tagRegex = try! NSRegularExpression(
        pattern: "\\[(/?)(放大|缩小|摇晃|点头|爆炸|波纹|绽放|抖动|粗体|斜体|下划线|删除线)\\]")

    /// 有没有成对的标记（先用 "[/" 粗筛，省得每条消息都跑正则）
    static func contains(_ s: String) -> Bool {
        guard s.contains("[/") else { return false }
        return tagRegex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    static func wrap(_ text: String, in kind: TextEffectKind) -> String {
        kind.open + text + kind.close
    }

    /// 剥掉所有标记，给复制/引用/预览这种不该看见标记的地方用
    static func strip(_ s: String) -> String {
        guard contains(s) else { return s }
        return tagRegex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }

    /// 解析成段落；一个标记都没有返回 nil，调用方走老路
    static func segments(_ s: String) -> [Segment]? {
        guard contains(s) else { return nil }
        let ns = s as NSString
        var out: [Segment] = []
        var stack: [TextEffectKind] = []
        var cursor = 0
        func emit(_ t: String) {
            guard !t.isEmpty else { return }
            out.append(Segment(id: out.count, text: t, effects: stack))
        }
        for m in tagRegex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            emit(ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)))
            let closing = ns.substring(with: m.range(at: 1)) == "/"
            if let kind = TextEffectKind(rawValue: ns.substring(with: m.range(at: 2))) {
                if closing {
                    if let i = stack.lastIndex(of: kind) { stack.remove(at: i) }
                } else {
                    stack.append(kind)
                }
            }
            cursor = m.range.location + m.range.length
        }
        emit(ns.substring(from: cursor))
        return out
    }

    // 逐字画的时候的最小单位：中文一个字一个格，英文一个词一个格，空格粘在前一个格后面，换行另起一段
    struct Token: Identifiable {
        let id: Int
        let text: String
        let effects: [TextEffectKind]
        let index: Int          // 在同一段动画里排第几个（波纹用来错相位）
    }

    static func paragraphs(_ segments: [Segment]) -> [[Token]] {
        var paras: [[Token]] = [[]]
        var counter = 0
        var runIndex = 0
        var lastEffects: [TextEffectKind] = []
        for seg in segments {
            if seg.effects != lastEffects { runIndex = 0; lastEffects = seg.effects }
            var word = ""
            func flush() {
                guard !word.isEmpty else { return }
                paras[paras.count - 1].append(Token(id: counter, text: word, effects: seg.effects, index: runIndex))
                counter += 1; runIndex += 1; word = ""
            }
            for ch in seg.text {
                if ch == "\n" {
                    flush(); paras.append([])
                } else if ch == " " {
                    word.append(ch); flush()
                } else if ch.isASCII && (ch.isLetter || ch.isNumber || "'’-".contains(ch)) {
                    word.append(ch)
                } else {
                    flush(); word = String(ch); flush()
                }
            }
            flush()
        }
        return paras
    }
}

// MARK: - 气泡里画

struct EffectText: View {
    let segments: [TextEffects.Segment]
    let fontSize: CGFloat
    let color: Color
    var lineSpacing: CGFloat = 5
    /// 面板预览用：一直动。气泡里默认照 iMessage：出现时动一阵就停，点一下再动一遍
    var loop = false

    static let playDuration: TimeInterval = 2.6
    @State private var playStart: Date?
    @State private var stopTask: Task<Void, Never>?

    var body: some View {
        let paras = TextEffects.paragraphs(segments)
        VStack(alignment: .leading, spacing: lineSpacing) {
            ForEach(Array(paras.enumerated()), id: \.offset) { _, tokens in
                if tokens.isEmpty {
                    Text(" ").font(.system(size: fontSize))
                } else {
                    EffectFlowLayout(lineSpacing: lineSpacing) {
                        ForEach(tokens) { tok in
                            EffectToken(token: tok, fontSize: fontSize, color: color,
                                        start: loop ? Date(timeIntervalSinceReferenceDate: 0) : playStart, loop: loop)
                        }
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onTapGesture { if !loop { play() } }
        // 0921 她抓的：面板里八个预览字是 loop 模式，这层点击把 Button 的点击吃掉了，按钮点不动。预览不接点击
        .allowsHitTesting(!loop)
        // 0921 她抓的「发出去没动」：气泡刚插进列表那一帧 onAppear 可能先于真正露面，稍等一下再起跳
        .onAppear { if !loop { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { play() } } }
        .onDisappear { stopTask?.cancel() }
    }

    private func play() {
        playStart = Date()
        stopTask?.cancel()
        stopTask = Task {
            try? await Task.sleep(nanoseconds: UInt64((Self.playDuration + 0.1) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            playStart = nil
        }
    }
}

private struct EffectToken: View {
    let token: TextEffects.Token
    let fontSize: CGFloat
    let color: Color
    let start: Date?        // nil = 停着不动
    let loop: Bool

    private var styled: Text {
        var size = fontSize
        if token.effects.contains(.big) { size = fontSize * 1.45 }
        if token.effects.contains(.small) { size = fontSize * 0.72 }
        var t = Text(token.text).font(.system(size: size))
        if token.effects.contains(.bold) { t = t.bold() }
        if token.effects.contains(.italic) { t = t.italic() }
        if token.effects.contains(.underline) { t = t.underline() }
        if token.effects.contains(.strike) { t = t.strikethrough() }
        return t
    }

    private var motion: TextEffectKind? {
        token.effects.last { [.shake, .nod, .explode, .ripple, .bloom, .jitter].contains($0) }
    }

    var body: some View {
        if let motion, let start {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                let t = ctx.date.timeIntervalSince(start)
                if loop || t < EffectText.playDuration {
                    styled.foregroundColor(color).modifier(Motion(kind: motion, t: t, index: token.index))
                } else {
                    styled.foregroundColor(color)
                }
            }
        } else {
            styled.foregroundColor(color)
        }
    }

    private struct Motion: ViewModifier {
        let kind: TextEffectKind
        let t: Double
        let index: Int

        private func loopPhase(_ t: Double, period: Double) -> Double {
            t.truncatingRemainder(dividingBy: period)
        }

        func body(content: Content) -> some View {
            switch kind {
            case .shake:
                // 0921 她描述的 iMessage 摇晃：像贴在半个圆柱上，一道波从左往右扫，每个字依次绕竖轴翻过去
                let phase = t * 5.5 - Double(index) * 0.55
                content
                    .rotation3DEffect(.degrees(sin(phase) * 38), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    .offset(x: sin(phase) * 2.5)
            case .nod:
                content.offset(y: sin(t * 7) * 3)
            case .ripple:
                content.offset(y: sin(t * 5 - Double(index) * 0.7) * 3.5)
            case .bloom:
                let s = 1 + 0.12 * sin(t * 2.2)
                content.scaleEffect(s).opacity(0.85 + 0.15 * sin(t * 2.2 + 1))
            case .jitter:
                let step = floor(t * 14)
                let h = sin(step * 12.9898 + Double(index) * 78.233) * 43758.5453
                let f = h - floor(h)
                let h2 = sin(step * 4.1414 + Double(index) * 7.919) * 22578.145
                let f2 = h2 - floor(h2)
                content.offset(x: (f - 0.5) * 3, y: (f2 - 0.5) * 3)
            case .explode:
                let p = loopPhase(t, period: 4)
                let burst = p < 0.55 ? (1 - p / 0.55) : 0
                content.scaleEffect(1 + burst * 1.3).opacity(1 - burst * 0.75)
            default:
                content
            }
        }
    }
}

// MARK: - 选效果的面板

struct TextEffectPanel: View {
    let selection: String
    let onPick: (TextEffectKind) -> Void
    @Environment(\.dismiss) private var dismiss

    private var sample: String {
        let s = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "Aa" }
        return s.count > 6 ? String(s.prefix(6)) : s
    }

    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 36, height: 5).padding(.top, 8)
            HStack(spacing: 8) {
                ForEach(TextEffectKind.styles) { kind in
                    Button { onPick(kind); dismiss() } label: {
                        styleLabel(kind)
                            .font(.system(size: 22, weight: .medium, design: .serif))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(TextEffectKind.animated) { kind in
                    Button { onPick(kind); dismiss() } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.secondary.opacity(0.12))
                            EffectText(
                                segments: [.init(id: 0, text: kind.rawValue, effects: [kind])],
                                fontSize: 19, color: .primary, loop: true
                            )
                            .padding(.horizontal, 10)
                        }
                        .frame(height: 72)
                        .clipped()
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(selection.isEmpty ? "没选字：效果套在整条消息上" : "套在：\(sample)\(selection.count > 6 ? "…" : "")")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func styleLabel(_ kind: TextEffectKind) -> Text {
        switch kind {
        case .bold: return Text("B").bold()
        case .italic: return Text("I").italic()
        case .underline: return Text("U").underline()
        case .strike: return Text("S").strikethrough()
        default: return Text(kind.rawValue)
        }
    }
}

// MARK: - 长按菜单那一项（AppDelegate 挂，ChatView 收）

enum TextEffectBridge {
    /// 聊天打字框有没有聚焦。没聚焦就不往菜单里塞，免得设置页的输入框也冒出来
    static var chatInputFocused = false
    static let requested = Notification.Name("alcoveTextEffectRequested")

    static func menuAction() -> UIAction? {
        guard chatInputFocused else { return nil }
        return UIAction(title: "文字效果", image: UIImage(systemName: "textformat")) { _ in
            guard let r = UIResponder.alcoveCurrentFirstResponder else { return }
            var text = ""
            var range = NSRange(location: 0, length: 0)
            if let tv = r as? UITextView {
                text = tv.text ?? ""
                range = tv.selectedRange
            } else if let tf = r as? UITextField {
                text = tf.text ?? ""
                if let sr = tf.selectedTextRange {
                    range = NSRange(location: tf.offset(from: tf.beginningOfDocument, to: sr.start),
                                    length: tf.offset(from: sr.start, to: sr.end))
                }
            }
            NotificationCenter.default.post(name: requested, object: nil,
                                            userInfo: ["text": text, "location": range.location, "length": range.length])
        }
    }
}

extension UIResponder {
    private static weak var alcoveCaptured: UIResponder?
    static var alcoveCurrentFirstResponder: UIResponder? {
        alcoveCaptured = nil
        UIApplication.shared.sendAction(#selector(UIResponder.alcoveCaptureFirstResponder), to: nil, from: nil, for: nil)
        return alcoveCaptured
    }
    @objc private func alcoveCaptureFirstResponder() {
        UIResponder.alcoveCaptured = self
    }
}


// 0921 她抓的「怎么这么长一条」：GlassKit 的 FlowLayout 有多宽占多宽，气泡被撑成整行。
// 这份按实际最长的一行算宽，气泡就跟普通文字一样贴着字走。
private struct EffectFlowLayout: Layout {
    var lineSpacing: CGFloat = 5

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        var lineStart = 0
        func closeLine() {
            // 同一行里字号不同（放大/缩小）时贴行底对齐
            for i in lineStart..<frames.count { frames[i].origin.y = y + lineHeight - frames[i].height }
            lineStart = frames.count
        }
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                closeLine()
                widest = max(widest, x)
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width
            lineHeight = max(lineHeight, size.height)
        }
        closeLine()
        widest = max(widest, x)
        return (frames, CGSize(width: min(widest, maxWidth), height: y + lineHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, maxWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (frames, _) = arrange(subviews, maxWidth: bounds.width)
        for (view, f) in zip(subviews, frames) {
            view.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: .unspecified)
        }
    }
}
