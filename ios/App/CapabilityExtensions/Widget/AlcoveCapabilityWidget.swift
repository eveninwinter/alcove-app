import ActivityKit
import AppIntents
import SwiftUI
import UIKit
import WidgetKit

@main
struct AlcoveCapabilityWidgetBundle: WidgetBundle {
    var body: some Widget {
        AlcoveHomeWidget()
        AlcoveLabLiveActivity()
        AlcoveCallLiveActivity()
    }
}

private struct LabEntry: TimelineEntry {
    let date: Date
}

private struct LabProvider: TimelineProvider {
    func placeholder(in context: Context) -> LabEntry { LabEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (LabEntry) -> Void) {
        completion(LabEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LabEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        let nextMidnight = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        ) ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: [LabEntry(date: now)], policy: .after(nextMidnight)))
    }
}

private struct AlcoveHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AlcoveCapabilityWidget", provider: LabProvider()) { entry in
            AlcoveWidgetView(entry: entry)
        }
        .configurationDisplayName("Alcove")
        .description("看看家里此刻正在发生什么。")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
        .contentMarginsDisabled()
    }
}

private struct AlcoveWidgetView: View {
    let entry: LabEntry

    @Environment(\.widgetFamily) private var family

    @Environment(\.colorScheme) private var scheme

    @ViewBuilder
    var body: some View {
        switch family {
        case .systemSmall, .systemMedium:
            // 1015 #3834–3837 她：换成吊坠图、纯白底；黑夜（跟手机深色模式走，小组件读不到 App 的日夜按钮）深炭灰底、吊坠压暗一点。
            // 效果图 /root/workroom/mock/island/widgets.jpg（白天）、widgets-dark.jpg（黑夜）
            widgetContent
                .containerBackground(for: .widget) { sp.card }
        default:
            widgetContent
                .containerBackground(.clear, for: .widget)
        }
    }

    private var sp: SPal { SPal(dark: scheme == .dark) }

    @ViewBuilder
    private var widgetContent: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 0) {
                LocketImage(dark: sp.dark)
                    .frame(height: 90)
                    .padding(.leading, 18)
                Spacer(minLength: 10)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Time, gently kept.")
                        .font(WFont.script(21))
                        .foregroundStyle(sp.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(togetherDays)")
                            .font(WFont.corm(49))
                            .foregroundStyle(sp.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("DAYS")
                            .font(WFont.corm(10))
                            .tracking(2.5)
                            .foregroundStyle(sp.gray)
                    }
                    .padding(.leading, 7).padding(.top, 6)
                    Text("SINCE 2026 · 06 · 01")
                        .font(WFont.corm(8.5))
                        .tracking(2)
                        .foregroundStyle(sp.gray)
                        .padding(.leading, 9).padding(.top, 8)
                }
                .padding(.trailing, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .accessoryCircular:
            // 锁屏：苹果统一染成半透明白，吊坠黑的地方会透过去（白天黑夜一样）
            ZStack {
                AccessoryWidgetBackground()
                Image("Locket").resizable().scaledToFit().padding(.horizontal, 8)
            }
            .widgetAccentable()

        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image("Locket").resizable().scaledToFit().frame(width: 62)
                VStack(alignment: .leading, spacing: 3) {
                    Text("still here")
                        .font(WFont.script(24))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("NEAR, ALWAYS")
                        .font(WFont.corm(9))
                        .tracking(2)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .widgetAccentable()

        case .accessoryInline:
            Label("Still here", systemImage: "heart.fill")

        default:
            VStack(spacing: 0) {
                LocketImage(dark: sp.dark)
                    .frame(width: 104)
                    .padding(.top, 4)
                Text("still here")
                    .font(WFont.script(23))
                    .foregroundStyle(sp.ink)
                    .lineLimit(1)
                    .padding(.top, 8)
                Text("CHEN JING")
                    .font(WFont.corm(8.5))
                    .tracking(2.5)
                    .foregroundStyle(sp.gray)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var togetherDays: Int {
        let calendar = Calendar.autoupdatingCurrent
        guard let startDate = calendar.date(
            from: DateComponents(year: 2026, month: 6, day: 1)
        ) else { return 0 }

        let start = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: entry.date)
        return max(0, calendar.dateComponents([.day], from: start, to: today).day ?? 0)
    }
}

/// 1015 Sanctus 那套：白天纯白，黑夜深炭灰（冷，不带棕）
private struct SPal {
    let dark: Bool
    var card: Color { dark ? Color(red: 0x26 / 255, green: 0x26 / 255, blue: 0x2A / 255) : .white }
    var ink: Color { dark ? Color(red: 0xE4 / 255, green: 0xE4 / 255, blue: 0xE7 / 255) : Color(red: 0x2A / 255, green: 0x2A / 255, blue: 0x2E / 255) }
    var gray: Color { dark ? Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255) : Color(red: 0x8C / 255, green: 0x8C / 255, blue: 0x90 / 255) }
    var msg: Color { dark ? Color(red: 0xC9 / 255, green: 0xC9 / 255, blue: 0xCD / 255) : Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3F / 255) }
}

/// 她给的吊坠（狼＋兔子）；黑夜不改颜色，只压暗到八成多
private struct LocketImage: View {
    var dark = false
    var body: some View {
        Image("Locket").resizable().scaledToFit()
            .colorMultiply(dark ? Color(white: 0.82) : .white)
            .accessibilityHidden(true)
    }
}

private struct SleepingRavenMark: View {
    let size: CGFloat

    var body: some View {
        Image("RavenSleeping", bundle: .main)
            .resizable()
            .renderingMode(.original)
            .interpolation(.none)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipped()
            .accessibilityHidden(true)
    }
}

private struct RavenMark: View {
    let size: CGFloat

    var body: some View {
        Image("RavenOutlined", bundle: .main)
            .resizable()
            .renderingMode(.original)
            .interpolation(.none)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipped()
            .accessibilityHidden(true)
    }
}

private struct AlcoveLabLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlcoveLabAttributes.self) { context in
            // 1015 锁屏那一条：跟展开的岛同一张卡（白天白、黑夜深炭灰）
            LiveBanner(message: context.state.message, bpm: context.state.bpm)
        } dynamicIsland: { context in
            // 1015 #3824–3834 她：灵动岛换成她给的吊坠图（狼＋兔子，/root/workroom/mock/island/locket.png 抠的）。
            // 收起：岛照旧黑，左边吊坠装进一枚白色小胶囊（圆角跟岛同心），右边心率用聊天页顶栏那个 Cormorant 数字；
            // 展开：本来整块铺白，真机上四周一圈黑边盖不住，1015 她让换黑底
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    // 1015 她：铺白盖不住苹果留的那圈黑边，四周一圈黑、摄像头两边两小块白很难看 → 展开也用黑底
                    IslandCard(message: context.state.message, bpm: context.state.bpm, dark: true, onIsland: true)
                }
            } compactLeading: {
                LocketTag()
            } compactTrailing: {
                Text(context.state.bpm > 0 ? "\(context.state.bpm)" : "—")
                    .font(WFont.corm(19))
                    .foregroundStyle(Color(white: 0.95))
                    .contentTransition(.numericText())
            } minimal: {
                LocketTag(minimal: true)
            }
            .keylineTint(.white)
        }
    }
}

/// 收起时左边那枚：白色小胶囊里一个吊坠。吊坠右边挂着扣环、右边那颗心也大，摆正中看着往右偏，往左挪一点（她 #3833「左移动一点居中」）
private struct LocketTag: View {
    var minimal = false

    var body: some View {
        if minimal {
            Image("Locket").resizable().scaledToFit().frame(width: 21)
                .offset(x: -0.6)
                .frame(width: 27, height: 27)
                .background(Circle().fill(Color.white))
        } else {
            Image("Locket").resizable().scaledToFit().frame(height: 21)
                .offset(x: -1.7)
                .frame(width: 53, height: 27)
                .background(Capsule().fill(Color.white))
        }
    }
}

/// 灵动岛展开那块（1015 改黑底，onIsland）／锁屏通知条（白天白、黑夜深炭灰）：左边大吊坠；右边花体 still here、小号大写 CHEN JING · ONLINE、他那句话；右上角心率。
/// 锁屏那条通知也是它（1015 #3836–3837 她点头：白天纯白，黑夜深炭灰、吊坠压暗）；灵动岛永远用白的
private struct IslandCard: View {
    let message: String
    let bpm: Int
    var dark = false
    var onIsland = false

    var body: some View {
        let sp = SPal(dark: dark)
        HStack(alignment: .top, spacing: 14) {
            LocketImage(dark: dark && !onIsland)
                .frame(height: 83)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text("still here")
                        .font(WFont.script(27))
                        .foregroundStyle(sp.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: -2) {
                        Text(bpm > 0 ? "\(bpm)" : "—")
                            .font(WFont.corm(24))
                            .foregroundStyle(sp.ink)
                            .contentTransition(.numericText())
                        Text("bpm")
                            .font(WFont.cormItalic(9.5))
                            .foregroundStyle(sp.gray)
                    }
                    .accessibilityLabel(bpm > 0 ? "心率 \(bpm)" : "心率暂无数据")
                }
                Text("CHEN JING · ONLINE")
                    .font(WFont.corm(8.5))
                    .tracking(2)
                    .foregroundStyle(sp.gray)
                    .lineLimit(1)
                if !message.isEmpty {
                    Text(message)
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(sp.msg)
                        .lineSpacing(2)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.leading, onIsland ? 4 : 18).padding(.trailing, onIsland ? 6 : 22)
        .padding(.top, 2).padding(.bottom, onIsland ? 8 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(onIsland ? Color.clear : sp.card)
    }
}

private struct LiveBanner: View {
    let message: String
    let bpm: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        IslandCard(message: message, bpm: bpm, dark: dark)
            .padding(.top, 16)
            .background(SPal(dark: dark).card)
            .activityBackgroundTint(SPal(dark: dark).card)
            .activitySystemActionForegroundColor(SPal(dark: dark).ink)
    }
}

/// 小乌鸦＋STILL HERE＋名字＋后端那句话＋右边心率
private struct LiveRow: View {
    let pal: WPal
    let name: String
    let message: String
    let bpm: Int
    let raven: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            RavenMark(size: raven)
                .modifier(WRavenEdge(pal: pal))
            VStack(alignment: .leading, spacing: 3) {
                Text("STILL HERE")
                    .font(WFont.pixel(13))
                    .tracking(0.8)
                    .foregroundStyle(pal.pinkInk)
                HStack(spacing: 5) {
                    Rectangle().fill(pal.goD).frame(width: 6, height: 6)
                    Text("\(name) · ONLINE")
                        .font(WFont.pixel(9))
                        .foregroundStyle(pal.sub)
                        .lineLimit(1)
                }
                if !message.isEmpty {
                    Text(message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(pal.ink)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            VStack(spacing: 2) {
                WPixel(rows: WPX.heart, colors: ["o": pal.pinkInk], scale: 3)
                Text(bpm > 0 ? "\(bpm)" : "—")
                    .font(WFont.pixel(19))
                    .foregroundStyle(pal.pinkInk)
                    .contentTransition(.numericText())
                    .accessibilityLabel(bpm > 0 ? "心率 \(bpm)" : "心率暂无数据")
                Text("PULSE")
                    .font(WFont.pixel(8))
                    .tracking(1)
                    .foregroundStyle(pal.sub)
            }
        }
    }
}

// MARK: 1002 像素小零件（App 里那套在主程序里，小组件是单独的进程，这里另放一份）

private struct WPal {
    let dark: Bool
    private static func h(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
    var paper: Color { dark ? Self.h(0x4B, 0x4A, 0x4F) : Self.h(0xF3, 0xF2, 0xF7) }
    var card: Color { dark ? Self.h(0x3B, 0x3A, 0x40) : .white }
    var ink: Color { dark ? Self.h(0xEC, 0xE7, 0xEC) : Self.h(0x5C, 0x56, 0x6B) }
    var sub: Color { dark ? Self.h(0xA5, 0x9F, 0xA8) : Self.h(0xA4, 0x9E, 0xB2) }
    var pink: Color { dark ? Self.h(0x4D, 0x3A, 0x47) : Self.h(0xF8, 0xD3, 0xEC) }
    var pinkD: Color { dark ? Self.h(0xB9, 0x7A, 0xA2) : Self.h(0xEA, 0xB3, 0xDC) }
    var pinkInk: Color { dark ? Self.h(0xF6, 0xB4, 0xDC) : Self.h(0xC4, 0x6A, 0xAE) }
    var lilacD: Color { dark ? Self.h(0x55, 0x52, 0x5A) : Self.h(0xC9, 0xBD, 0xEC) }
    var lilacInk: Color { dark ? Self.h(0xA5, 0x9F, 0xA8) : Self.h(0x8D, 0x7F, 0xC0) }
    var goD: Color { dark ? Self.h(0xB9, 0x7A, 0xA2) : Self.h(0x86, 0xDC, 0xBF) }
    static let islandPink = h(0xF6, 0xB4, 0xDC)
    static let islandMint = h(0xA9, 0xF0, 0xD6)
}

private enum WFont {
    /// 打包进小组件扩展的 silkscreen.ttf（Info.plist UIAppFonts），找不到就退等宽
    /// 花体 Pinyon Script（同样打包进扩展），找不到就退系统衬线斜体
    static func script(_ size: CGFloat) -> Font {
        UIFont(name: "PinyonScript-Regular", size: size) != nil
            ? Font.custom("PinyonScript-Regular", fixedSize: size)
            : .system(size: size * 0.8, design: .serif).italic()
    }
    /// 1015 Cormorant（聊天页顶栏心率那个字，老式数字），也打包进扩展了
    static func corm(_ size: CGFloat) -> Font {
        UIFont(name: "CormorantGaramond-Medium", size: size) != nil
            ? Font.custom("CormorantGaramond-Medium", fixedSize: size)
            : .system(size: size * 0.9, design: .serif)
    }
    static func cormItalic(_ size: CGFloat) -> Font {
        UIFont(name: "CormorantGaramondItalic-MediumItalic", size: size) != nil
            ? Font.custom("CormorantGaramondItalic-MediumItalic", fixedSize: size)
            : .system(size: size * 0.9, design: .serif).italic()
    }
    static func pixel(_ size: CGFloat) -> Font {
        UIFont(name: "Silkscreen-Regular", size: size) != nil
            ? Font.custom("Silkscreen-Regular", fixedSize: size)
            : .system(size: size - 0.5, weight: .semibold, design: .monospaced)
    }
}

private enum WPX {
    static let heart = [".oo.oo.", "ooooooo", "ooooooo", ".ooooo.", "..ooo..", "...o..."]
    static let heartOutline = [".oo.oo.", "offoffo", "offfffo", ".offfo.", "..ofo..", "...o..."]
    static let spark = ["...o...", "...o...", "..ooo..", "ooooooo", "..ooo..", "...o...", "...o..."]
}

private struct WPixel: View {
    let rows: [String]
    let colors: [Character: Color]
    var scale: CGFloat = 2

    var body: some View {
        let w: CGFloat = CGFloat(rows.first?.count ?? 0) * scale
        let hgt: CGFloat = CGFloat(rows.count) * scale
        Canvas { ctx, _ in
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() {
                    guard let c = colors[ch] else { continue }
                    let px: CGFloat = CGFloat(x) * scale
                    let py: CGFloat = CGFloat(y) * scale
                    ctx.fill(Path(CGRect(x: px, y: py, width: scale + 0.02, height: scale + 0.02)), with: .color(c))
                }
            }
        }
        .frame(width: w, height: hgt)
    }
}

/// 底：白天淡紫小格纸，黑夜灰颗粒
private struct WPaper: View {
    let pal: WPal
    var body: some View {
        ZStack {
            pal.paper
            Image(uiImage: pal.dark ? Self.grain : Self.checker)
                .resizable(resizingMode: .tile)
        }
    }

    static let checker: UIImage = {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: fmt).image { ctx in
            UIColor(red: 201 / 255, green: 189 / 255, blue: 236 / 255, alpha: 0.16).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            ctx.fill(CGRect(x: 8, y: 8, width: 8, height: 8))
        }
    }()

    static let grain: UIImage = {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        var rng = SystemRandomNumberGenerator()
        return UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96), format: fmt).image { ctx in
            for y in 0..<96 {
                for x in 0..<96 {
                    let a: CGFloat = CGFloat(Int.random(in: 0...40, using: &rng)) / 255
                    UIColor(white: 1, alpha: a).setFill()
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }()
}

/// 像素小窗口：标题栏（心＋字＋小方块）＋粉虚线＋内容；白卡粉框、底下一道粉色实影
/// framed = false：不画卡底、粉框、粉影，只留标题栏＋虚线＋内容（1007 小组件/锁屏/灵动岛去边框）
private struct WWindow<Content: View>: View {
    let pal: WPal
    let title: String
    var squares: Int = 3
    var radius: CGFloat = 12
    var framed: Bool = true
    var barInset: CGFloat = 9
    @ViewBuilder var content: () -> Content

    @ViewBuilder
    var body: some View {
        if framed {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            stack
                .background(shape.fill(pal.card))
                .overlay(shape.stroke(pal.pinkD, lineWidth: 1.5))
                .background(shape.fill(pal.pink).offset(y: 4))
        } else {
            stack
        }
    }

    private var stack: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                WPixel(rows: WPX.heartOutline, colors: ["o": pal.pinkInk, "f": pal.pink], scale: 1)
                Text(title)
                    .font(WFont.pixel(9))
                    .tracking(0.8)
                    .foregroundStyle(pal.pinkInk)
                Spacer(minLength: 4)
                ForEach(0..<squares, id: \.self) { i in
                    if i == squares - 1 {
                        Rectangle().fill(pal.goD).frame(width: 10, height: 10)
                    } else {
                        Rectangle().stroke(pal.lilacD, lineWidth: 1.5).frame(width: 9, height: 9)
                    }
                }
            }
            .padding(.horizontal, barInset).padding(.vertical, 5)
            WDash(color: pal.pinkD)
            content()
        }
    }
}

private struct WDash: View {
    let color: Color
    var body: some View {
        Rectangle().fill(Color.clear).frame(height: 1.5)
            .overlay(WLine().stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
    }
}

private struct WLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}

/// 黑乌鸦放在深色底上会糊进去：黑夜时描一圈浅灰边（四个方向各一道 0 半径的影子）
private struct WRavenEdge: ViewModifier {
    let pal: WPal
    @ViewBuilder
    func body(content: Content) -> some View {
        if pal.dark {
            content
                .shadow(color: pal.sub, radius: 0, x: 1, y: 0)
                .shadow(color: pal.sub, radius: 0, x: -1, y: 0)
                .shadow(color: pal.sub, radius: 0, x: 0, y: -1)
        } else {
            content
        }
    }
}

private struct PulseNumber: View {
    let bpm: Int
    let size: CGFloat

    var body: some View {
        Text(bpm > 0 ? "\(bpm)" : "—")
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .monospacedDigit()
            .contentTransition(.numericText())
            .accessibilityLabel(bpm > 0 ? "心率 \(bpm)" : "心率暂无数据")
    }
}


// MARK: - 1008 通话灵动岛 / 锁屏条（她给的参考图：黑岛＋头像＋名字＋「通话中 · 计时」＋消息、免提两个圆按钮）

private struct AlcoveCallLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CallActivityAttributes.self) { context in
            // 锁屏：半透明玻璃条，白字
            CallRow(context: context, avatar: 56, button: 48, nameSize: 17)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .activityBackgroundTint(Color.black.opacity(0.28))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 12) {
                        CallAvatar(data: context.attributes.avatarJPEG, size: 52)
                        CallTitle(context: context, nameSize: 17)
                    }
                    .padding(.leading, 6)
                    .dynamicIsland(verticalPlacement: .belowIfTooWide)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CallButtons(speakerOn: context.state.speakerOn, size: 46)
                        .padding(.trailing, 6)
                        .dynamicIsland(verticalPlacement: .belowIfTooWide)
                }
            } compactLeading: {
                CallAvatar(data: context.attributes.avatarJPEG, size: 24)
            } compactTrailing: {
                Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                    .font(.system(size: 13, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: 54)
            } minimal: {
                CallAvatar(data: context.attributes.avatarJPEG, size: 24)
            }
        }
    }
}

/// 左边头像：圆角方块（参考图那样），没有头像就退小乌鸦
private struct CallAvatar: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let ui = UIImage(data: data) {
                Image(uiImage: ui).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image("RavenOutlined").resizable().interpolation(.none).aspectRatio(contentMode: .fit)
                    .padding(size * 0.12).background(Color.white.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

private struct CallTitle: View {
    let context: ActivityViewContext<CallActivityAttributes>
    let nameSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(context.attributes.name)
                .font(.system(size: nameSize, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            HStack(spacing: 0) {
                Text("通话中 · ")
                Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
            }
            .font(.system(size: nameSize - 3)).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
        }
    }
}

/// 右边两个圆按钮：消息（弹一条能长按回复的通知，打的字发进通话）、免提（开着就亮成白底）
private struct CallButtons: View {
    let speakerOn: Bool
    let size: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            Button(intent: CallMessageIntent()) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: size * 0.38, weight: .medium)).foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("给他说句话")
            Button(intent: CallSpeakerIntent()) {
                Image(systemName: speakerOn ? "speaker.wave.2.fill" : "speaker.fill")
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundStyle(speakerOn ? Color.black : Color.white)
                    .frame(width: size, height: size)
                    .background(Circle().fill(speakerOn ? Color.white : Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(speakerOn ? "免提已开" : "免提已关")
        }
    }
}

private struct CallRow: View {
    let context: ActivityViewContext<CallActivityAttributes>
    let avatar: CGFloat
    let button: CGFloat
    let nameSize: CGFloat

    var body: some View {
        HStack(spacing: 14) {
            CallAvatar(data: context.attributes.avatarJPEG, size: avatar)
            CallTitle(context: context, nameSize: nameSize)
            Spacer(minLength: 6)
            CallButtons(speakerOn: context.state.speakerOn, size: button)
        }
    }
}
