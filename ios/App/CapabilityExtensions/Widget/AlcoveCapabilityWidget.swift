import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

@main
struct AlcoveCapabilityWidgetBundle: WidgetBundle {
    var body: some Widget {
        AlcoveHomeWidget()
        AlcoveLabLiveActivity()
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

    private var pal: WPal { WPal(dark: scheme == .dark) }

    @ViewBuilder
    var body: some View {
        switch family {
        case .systemSmall, .systemMedium:
            // 1002 她要的：跟 App 里一样的像素风（终端 / 日记页那套），白天小格纸、黑夜灰颗粒，跟手机深浅走
            widgetContent
                .containerBackground(for: .widget) { WPaper(pal: pal) }
        default:
            widgetContent
                .containerBackground(.clear, for: .widget)
        }
    }

    @ViewBuilder
    private var widgetContent: some View {
        switch family {
        case .systemMedium:
            WWindow(pal: pal, title: "ALCOVE.EXE", squares: 3) {
                HStack(spacing: 10) {
                    SleepingRavenMark(size: 112)
                        .modifier(WRavenEdge(pal: pal))
                    VStack(alignment: .center, spacing: 6) {
                        Text("Time, gently kept.")
                            .font(.system(size: 19, weight: .regular, design: .serif))
                            .italic()
                            .foregroundStyle(pal.lilacInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            WPixel(rows: WPX.spark, colors: ["o": pal.pinkInk], scale: 2)
                            Text("\(togetherDays)")
                                .font(WFont.pixel(38))
                                .foregroundStyle(pal.pinkInk)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text("DAYS")
                                .font(WFont.pixel(10))
                                .tracking(1.2)
                                .foregroundStyle(pal.sub)
                        }
                        Text("SINCE 2026.06.01")
                            .font(WFont.pixel(8.5))
                            .tracking(0.8)
                            .foregroundStyle(pal.sub)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.leading, 6).padding(.trailing, 12)
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 14)

        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                RavenMark(size: 35)
            }
            .widgetAccentable()

        case .accessoryRectangular:
            HStack(spacing: 7) {
                SleepingRavenMark(size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Present")
                        .font(.headline)
                    Text("NEAR, ALWAYS.")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 2)
                Image(systemName: "heart.fill")
                    .font(.caption)
            }
            .widgetAccentable()

        case .accessoryInline:
            Label("Still here", systemImage: "heart.fill")

        default:
            WWindow(pal: pal, title: "ONLINE", squares: 1) {
                VStack(spacing: 3) {
                    RavenMark(size: 70)
                        .modifier(WRavenEdge(pal: pal))
                    Text("STILL HERE")
                        .font(WFont.pixel(12))
                        .tracking(0.8)
                        .foregroundStyle(pal.pinkInk)
                    HStack(spacing: 4) {
                        Text("陈璟")
                            .font(.system(size: 10))
                            .foregroundStyle(pal.sub)
                        WPixel(rows: WPX.heartOutline, colors: ["o": pal.pinkInk, "f": pal.pink], scale: 1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 9).padding(.top, 9).padding(.bottom, 13)
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
            // 1002 锁屏那一条：小格纸 / 灰颗粒底上一个像素窗口
            LiveBanner(name: context.attributes.name, message: context.state.message, bpm: context.state.bpm)
        } dynamicIsland: { context in
            DynamicIsland {
                // 1002 她要的：展开时黑框里镶一块像素窗口。四个区里只用最下面那块（整宽），别的空着
                DynamicIslandExpandedRegion(.bottom) {
                    IslandCard(name: context.attributes.name, message: context.state.message, bpm: context.state.bpm)
                }
            } compactLeading: {
                RavenMark(size: 23)
                    .modifier(WRavenEdge(pal: WPal(dark: true)))
            } compactTrailing: {
                HStack(spacing: 4) {
                    WPixel(rows: WPX.heart, colors: ["o": WPal.islandPink], scale: 2)
                    Text(context.state.bpm > 0 ? "\(context.state.bpm)" : "—")
                        .font(WFont.pixel(12))
                        .foregroundStyle(WPal.islandMint)
                        .contentTransition(.numericText())
                }
            } minimal: {
                RavenMark(size: 23)
                    .modifier(WRavenEdge(pal: WPal(dark: true)))
            }
            .keylineTint(WPal.islandPink)     // 外面那一圈细线（深色背景时才显）
        }
    }
}

/// 灵动岛展开那块：跟锁屏那条同一个窗口，只是外面一圈是苹果锁死的黑
private struct IslandCard: View {
    let name: String
    let message: String
    let bpm: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = WPal(dark: scheme == .dark)
        WWindow(pal: pal, title: "ALCOVE.LIVE", squares: 2, radius: 24) {
            LiveRow(pal: pal, name: name, message: message, bpm: bpm, raven: 46)
                .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .background(WPaper(pal: pal).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)))
    }
}

private struct LiveBanner: View {
    let name: String
    let message: String
    let bpm: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = WPal(dark: scheme == .dark)
        WWindow(pal: pal, title: "ALCOVE.LIVE", squares: 2) {
            LiveRow(pal: pal, name: name, message: message, bpm: bpm, raven: 50)
                .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .padding(10)
        .background(WPaper(pal: pal))
        .activityBackgroundTint(pal.paper)
        .activitySystemActionForegroundColor(pal.pinkInk)
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
private struct WWindow<Content: View>: View {
    let pal: WPal
    let title: String
    var squares: Int = 3
    var radius: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
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
            .padding(.horizontal, 9).padding(.vertical, 5)
            WDash(color: pal.pinkD)
            content()
        }
        .background(shape.fill(pal.card))
        .overlay(shape.stroke(pal.pinkD, lineWidth: 1.5))
        .background(shape.fill(pal.pink).offset(y: 4))
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
