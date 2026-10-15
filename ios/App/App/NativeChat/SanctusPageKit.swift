import SwiftUI

// MARK: - 1015 #3896 Sanctus 页面零件（她：「统一每一个页面的美化」，先做公用零件，再挑几页换上看效果）
// 规矩照 /root/.claude/skills/sanctus-style：冷白纸、银灰字、花体只写英文小注、宋体中文、细线、不堆装饰、黑夜冷炭灰。
// 样子照现成的：分组标题＝侧边栏「他的世界 out there」；条目＝侧边栏圆角玻璃卡（drawerGlass）；颜色＝聊天小卡 SanctusCardInk；
// 顶栏＝远游页定下的那条（返回键安全区下第一行、44 高、离左 8；标题同一行竖着居中）。
// 用法：
//   SanctusPage(title: "设置", onBack: { dismiss() }) {
//       SanctusSection("外观", note: "how it looks")
//       SanctusGroup {
//           SanctusRow(icon: "paintbrush", title: "主题", detail: "Sanctus · 圣哉") { … }
//           SanctusToggleRow(icon: "bell", title: "通知", isOn: $on)
//       }
//       SanctusFootnote("说明文字")
//   }
// 页面本身铺满全屏（自己画底色）的，传 topInset: 窗口安全区高度；放在 sheet / fullScreenCover 里的不用传。

/// 页面颜色：在聊天小卡那套上加页面底色和条目玻璃
struct SanctusPageInk {
    let dark: Bool
    init() { dark = AlcoveAppearance.isDark }
    init(dark: Bool) { self.dark = dark }
    private func rgb(_ hex: Int, _ a: Double = 1) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: a)
    }
    /// 页面底：白天水彩纸色（远游定的）、黑夜冷炭灰
    var page: Color { dark ? rgb(0x1B1C20) : rgb(0xF1F2F4) }
    /// 条目玻璃（侧边栏同款：白天半透白、黑夜一层很薄的白）
    var row: Color { dark ? Color.white.opacity(0.06) : Color.white.opacity(0.62) }
    var rowEdge: Color { dark ? Color.white.opacity(0.10) : Color.white.opacity(0.95) }
    var rowFrame: Color { dark ? Color.white.opacity(0.06) : rgb(0x969AA4, 0.20) }
    var title: Color { dark ? rgb(0xE4E4E7) : rgb(0x2A2A2E) }
    var body: Color { dark ? rgb(0xE3E4E8) : rgb(0x3E4048) }
    var script: Color { dark ? rgb(0xC3C6CE) : rgb(0x6F7480) }
    var sub: Color { dark ? rgb(0x8B8F99) : rgb(0x9A9EA8) }
    var link: Color { dark ? rgb(0xA3A7B0) : rgb(0x7D818C) }
    var icon: Color { dark ? rgb(0xA3A7B0) : rgb(0x7D818C) }
    var hair: Color { dark ? Color.white.opacity(0.12) : rgb(0x969AA4, 0.30) }
    /// 开关打开时的颜色：银灰墨，不用绿色
    var on: Color { dark ? rgb(0xC3C6CE) : rgb(0x3E4048) }
    /// 输入框底
    var field: Color { dark ? Color.white.opacity(0.04) : Color.white.opacity(0.85) }
}

enum SanctusPageFont {
    static func title(_ s: CGFloat = 17) -> Font { .system(size: s, weight: .medium, design: .serif) }
    static func cn(_ s: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: s, weight: w, design: .serif) }
    static func script(_ s: CGFloat) -> Font { .custom("PinyonScript-Regular", size: s) }
    static func corm(_ s: CGFloat) -> Font { .custom("CormorantGaramond-Medium", size: s) }
    static func ital(_ s: CGFloat) -> Font { .custom("CormorantGaramondItalic-MediumItalic", size: s) }
}

// MARK: 页面和顶栏

/// 整页：底色＋顶栏＋可滚动的内容（左右 18 的边距，组和组之间的空由零件自己带）
struct SanctusPage<Content: View, Trailing: View>: View {
    let title: String
    let topInset: CGFloat
    let onBack: () -> Void
    let trailing: () -> Trailing
    let content: () -> Content
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""

    init(title: String, topInset: CGFloat = 0, onBack: @escaping () -> Void,
         @ViewBuilder trailing: @escaping () -> Trailing, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.topInset = topInset
        self.onBack = onBack
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        let ink: SanctusPageInk = { _ = houseAppearance; return SanctusPageInk() }()
        VStack(spacing: 0) {
            SanctusTopBar(title: title, onBack: onBack, trailing: trailing)
                .padding(.top, topInset)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) { content() }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 40)
            }
        }
        .background(ink.page.ignoresSafeArea())
        .environment(\.sanctusInk, ink)
    }
}

extension SanctusPage where Trailing == EmptyView {
    init(title: String, topInset: CGFloat = 0, onBack: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, topInset: topInset, onBack: onBack, trailing: { EmptyView() }, content: content)
    }
}

/// 顶栏：返回键在安全区下第一行（44 高、44 宽的点按区、离左 8），标题同一行居中；右边可以放一个小操作
struct SanctusTopBar<Trailing: View>: View {
    let title: String
    let onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.sanctusInk) private var ink

    var body: some View {
        ZStack {
            Text(title).font(SanctusPageFont.title()).tracking(1).foregroundColor(ink.title).lineLimit(1)
                .padding(.horizontal, 60)
            HStack(spacing: 0) {
                SanctusBackButton(color: ink.link, action: onBack)
                Spacer(minLength: 0)
                trailing().padding(.trailing, 12)
            }
        }
        .frame(height: 44)
    }
}

/// 标准返回键（所有页面都用这一个）
struct SanctusBackButton: View {
    var color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left").font(.system(size: 17, weight: .regular)).foregroundColor(color)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 8)
        .accessibilityLabel("返回")
    }
}

// MARK: 分组

/// 分组小标题：中文宋体＋一句花体英文小注（侧边栏「他的世界 out there」那种）
struct SanctusSection: View {
    let title: String
    var note: String? = nil
    @Environment(\.sanctusInk) private var ink
    init(_ title: String, note: String? = nil) { self.title = title; self.note = note }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(SanctusPageFont.cn(13, .semibold)).foregroundColor(ink.body)
            if let note { Text(note).font(SanctusPageFont.script(16)).foregroundColor(ink.sub.opacity(0.8)) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, 22).padding(.bottom, 9)
    }
}

/// 一组条目装在一张玻璃卡里，条目之间一根缩进的细线（像系统设置那样分组，但是这套的质感）
struct SanctusGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.sanctusInk) private var ink
    var body: some View {
        VStack(spacing: 0) {
            // iOS 18 起的正式接口：把里面的每一行拆出来，行和行之间插细线
            Group(subviews: content()) { rows in
                ForEach(rows) { row in
                    row
                    if row.id != rows.last?.id {
                        Rectangle().fill(ink.hair).frame(height: 0.5).padding(.leading, 51).padding(.trailing, 14)
                    }
                }
            }
        }
        .background(ink.row, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(ink.rowEdge, lineWidth: 0.7))
    }
}

// MARK: 条目

/// 一行：图标、标题、小字说明，右边一个值或箭头；整行可点
struct SanctusRow: View {
    var icon: String? = nil
    let title: String
    var detail: String? = nil
    var value: String? = nil
    var showsChevron = true
    let action: () -> Void
    @Environment(\.sanctusInk) private var ink

    var body: some View {
        Button(action: action) {
            SanctusRowBody(icon: icon, title: title, detail: detail) {
                HStack(spacing: 6) {
                    if let value { Text(value).font(SanctusPageFont.cn(12)).foregroundColor(ink.sub).lineLimit(1) }
                    if showsChevron {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundColor(ink.sub.opacity(0.7))
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// 带开关的一行；开关打开是银灰墨色，不是系统绿
struct SanctusToggleRow: View {
    var icon: String? = nil
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool
    @Environment(\.sanctusInk) private var ink

    var body: some View {
        SanctusRowBody(icon: icon, title: title, detail: detail) {
            Toggle("", isOn: $isOn).labelsHidden().tint(ink.on).scaleEffect(0.86)
        }
    }
}

/// 条目的骨架（左图标、中间两行字、右边随便放），给上面几种和各页自定义的行共用
struct SanctusRowBody<Trailing: View>: View {
    var icon: String?
    let title: String
    var detail: String?
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.sanctusInk) private var ink

    var body: some View {
        HStack(spacing: 11) {
            if let icon {
                Image(systemName: icon).font(.system(size: 15, weight: .light)).foregroundColor(ink.icon).frame(width: 28)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(SanctusPageFont.cn(14.5, .medium)).foregroundColor(ink.body)
                if let detail, !detail.isEmpty {
                    Text(detail).font(SanctusPageFont.cn(11)).foregroundColor(ink.sub).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: 输入

/// 单行输入框：上面一行小号大写的标签，下面一张白卡
struct SanctusField: View {
    let label: String
    var placeholder: String = ""
    @Binding var text: String
    @Environment(\.sanctusInk) private var ink
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SanctusKicker(label)
            TextField(placeholder, text: $text)
                .font(SanctusPageFont.cn(14.5)).foregroundColor(ink.body)
                .padding(.horizontal, 13).padding(.vertical, 11)
                .background(ink.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ink.rowFrame, lineWidth: 0.6))
        }
        .padding(.vertical, 6)
    }
}

/// 多行编辑（心跳文案、说话方式这种长 prompt）：宋体、行距宽一点、最小高度可调
struct SanctusEditor: View {
    let label: String
    @Binding var text: String
    var minHeight: CGFloat = 160
    @Environment(\.sanctusInk) private var ink
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SanctusKicker(label)
            TextEditor(text: $text)
                .font(SanctusPageFont.cn(14)).foregroundColor(ink.body).lineSpacing(5)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 9).padding(.vertical, 7)
                .frame(minHeight: minHeight)
                .background(ink.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ink.rowFrame, lineWidth: 0.6))
        }
        .padding(.vertical, 6)
    }
}

// MARK: 小件

/// 小号大写眉标（Cormorant，字距拉开）；中文也能用，自动退回宋体
struct SanctusKicker: View {
    let text: String
    @Environment(\.sanctusInk) private var ink
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(SanctusPageFont.corm(10)).tracking(2.2).foregroundColor(ink.sub).padding(.horizontal, 4)
    }
}

/// 组下面的说明小字
struct SanctusFootnote: View {
    let text: String
    @Environment(\.sanctusInk) private var ink
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(SanctusPageFont.cn(11)).foregroundColor(ink.sub).lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6).padding(.top, 8)
    }
}

/// 两头淡出的发丝线
struct SanctusHairline: View {
    @Environment(\.sanctusInk) private var ink
    var body: some View {
        LinearGradient(stops: [.init(color: ink.hair.opacity(0), location: 0), .init(color: ink.hair, location: 0.12),
                               .init(color: ink.hair, location: 0.88), .init(color: ink.hair.opacity(0), location: 1)],
                       startPoint: .leading, endPoint: .trailing)
            .frame(height: 0.6)
    }
}

/// 按钮：细线胶囊（保存、发送这种）；primary 是实心墨色
struct SanctusButton: View {
    let title: String
    var primary = false
    let action: () -> Void
    @Environment(\.sanctusInk) private var ink
    var body: some View {
        Button(action: action) {
            Text(title).font(SanctusPageFont.cn(13.5, .medium)).tracking(2)
                .foregroundColor(primary ? ink.page : ink.body)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(primary ? ink.on : Color.clear))
                .overlay(Capsule().stroke(primary ? Color.clear : ink.sub.opacity(0.6), lineWidth: 0.7))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
    }
}

/// 小胶囊标签（分类、状态）
struct SanctusPill: View {
    let text: String
    @Environment(\.sanctusInk) private var ink
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(SanctusPageFont.cn(10.5)).tracking(1.2).foregroundColor(ink.link)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .overlay(Capsule().stroke(ink.sub.opacity(0.55), lineWidth: 0.6))
    }
}

// MARK: 颜色往下传

private struct SanctusInkKey: EnvironmentKey {
    static let defaultValue = SanctusPageInk(dark: false)
}

extension EnvironmentValues {
    var sanctusInk: SanctusPageInk {
        get { self[SanctusInkKey.self] }
        set { self[SanctusInkKey.self] = newValue }
    }
}
