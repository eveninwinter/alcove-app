import SwiftUI
import UIKit

// 1002 她要的日程提醒（#3369–#3373）：日记页月历上的小铃铛，她和陈璟都能加，到点后端叫醒陈璟、
// 聊天页出一张像素小卡、推她锁屏。整页照终端那套像素风（白天薄荷粉淡紫小格纸，黑夜灰颗粒泡泡糖粉），
// 效果图在 /root/workroom/mock/diary-remind/（page / page-night / sheet / bits）。
// 后端 alcove-backend/reminders.py，接口 /api/reminders/*；他的命令 /root/rhysel/remind.py。

// MARK: 颜色（照效果图的两套 CSS 变量）

struct DiaryPixelPalette {
    let dark: Bool
    private static func h(_ s: String) -> Color { Color(hexString: s) ?? .gray }
    var paper: Color { Self.h(dark ? "#4B4A4F" : "#F3F2F7") }
    var card: Color { dark ? Self.h("#3B3A40") : .white }
    var ink: Color { Self.h(dark ? "#ECE7EC" : "#5C566B") }
    var sub: Color { Self.h(dark ? "#A59FA8" : "#A49EB2") }
    var pink: Color { Self.h(dark ? "#4D3A47" : "#F8D3EC") }
    var pinkD: Color { Self.h(dark ? "#B97AA2" : "#EAB3DC") }
    var pinkInk: Color { Self.h(dark ? "#F6B4DC" : "#C46AAE") }
    var lilac: Color { Self.h(dark ? "#323136" : "#E4DDF6") }
    var lilacD: Color { Self.h(dark ? "#55525A" : "#C9BDEC") }
    var lilacInk: Color { Self.h(dark ? "#A59FA8" : "#8D7FC0") }
    var blue: Color { Self.h(dark ? "#36404E" : "#D6E6FB") }
    var blueD: Color { Self.h(dark ? "#6F86A8" : "#A9C6F0") }
    var blueInk: Color { Self.h(dark ? "#A9C6F0" : "#5B86C9") }
    /// 「＋」键帽、勾选框：白天薄荷，黑夜换成泡泡糖粉（终端黑夜那版就是这么换的）
    var go: Color { dark ? pink : Self.h("#A9F0D6") }
    var goD: Color { dark ? pinkD : Self.h("#86DCBF") }
    var goInk: Color { dark ? pinkInk : Self.h("#3FAE88") }
    var goShadow: Color { dark ? Self.h("#8F5F7E") : Self.h("#3FAE88") }

    /// 铃铛：她粉、他蓝
    func bell(him: Bool) -> [Character: Color] {
        him ? ["o": blueInk, "f": blue] : ["o": pinkInk, "f": pink]
    }
    var flower: [Character: Color] {
        ["p": Self.h("#F8D3EC"), "P": Self.h("#F3B6DD"), "Y": .white, "g": Self.h("#A9F0D6")]
    }
}

// MARK: 像素小图（终端页那套是 private 的，这里另画几张小的）

enum DPX {
    static let flower = ["..pp.pp..", "..pPPPp..", "pp.PYP.pp", "pPPYYYPPp", ".pPPYPPp.", "..pp.pp..", "....g....", "...gg....", "....g...."]
    static let bell = ["...oo...", "..offo..", ".offffo.", ".offffo.", ".offffo.", "offffffo", "oooooooo", "...oo..."]
    static let plus = ["..oo..", "..oo..", "oooooo", "oooooo", "..oo..", "..oo.."]
    static let check = [".....o", "....oo", "o..oo.", "oooo..", ".oo..."]
    static let clock = [".ooooo.", "of.o.fo", "of.o.fo", "of.ooo.", "off..fo", "offfffo", ".ooooo."]
    static let disc = [".oooo.", "offffo", "of..fo", "of..fo", "offffo", ".oooo."]
    static let smile = ["..ooooo..", ".offfffo.", "offfffffo", "ofofffofo", "offfffffo", "ofofffofo", "offoooffo", ".offfffo.", "..ooooo.."]
}

struct PixelGlyph: View {
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
        .allowsHitTesting(false)
    }
}

/// 页面底：白天淡紫小格纸，黑夜胶片颗粒（开门时画一次的小图铺满）
struct DiaryPixelPaper: View {
    let pal: DiaryPixelPalette
    var body: some View {
        ZStack {
            pal.paper
            Image(uiImage: pal.dark ? Self.grain : Self.checker)
                .resizable(resizingMode: .tile)
        }
        .ignoresSafeArea()
    }

    static let checker: UIImage = {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: fmt).image { ctx in
            UIColor(red: 201 / 255, green: 189 / 255, blue: 236 / 255, alpha: 0.13).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            ctx.fill(CGRect(x: 8, y: 8, width: 8, height: 8))
        }
    }()

    static let grain: UIImage = {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        var rng = SystemRandomNumberGenerator()
        return UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120), format: fmt).image { ctx in
            for y in 0..<120 {
                for x in 0..<120 {
                    let a: CGFloat = CGFloat(Int.random(in: 0...40, using: &rng)) / 255
                    UIColor(white: 1, alpha: a).setFill()
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }()
}

/// 像素字：后端字体架子上的 Silkscreen（hidden，不进她的字体栏），没下到就退等宽
enum DiaryFonts {
    static func pixel(_ size: CGFloat) -> Font {
        KakaoPackStore.shared.registeredName("silkscreen").map { Font.custom($0, fixedSize: size) }
            ?? .system(size: size - 0.5, weight: .semibold, design: .monospaced)
    }
    static func script(_ size: CGFloat) -> Font {
        KakaoPackStore.shared.registeredName("pinyon").map { Font.custom($0, fixedSize: size) }
            ?? .system(size: size * 0.7, design: .serif).italic()
    }
    static func ensure() {
        let store = KakaoPackStore.shared
        if store.fonts.isEmpty { store.refresh() }
        store.ensureFont(id: "silkscreen")
        store.ensureFont(id: "pinyon")
    }
}

/// 键帽：白底、描边、底下一道实色阴影
struct PixelKeycap: ViewModifier {
    let fill: Color
    let edge: Color
    var radius: CGFloat = 8
    var drop: CGFloat = 3
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .background(shape.fill(fill))
            .overlay(shape.stroke(edge, lineWidth: 1.5))
            .background(shape.fill(edge).offset(y: drop))
    }
}

/// 像素小窗口：标题栏（小图标＋路径字＋右边几个小方块）＋虚线＋内容
struct DiaryPixelWindow<Content: View>: View {
    let pal: DiaryPixelPalette
    let title: String
    var icon: [String] = DPX.disc
    var squares: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                PixelGlyph(rows: icon, colors: ["o": pal.pinkInk, "f": pal.pink], scale: 2)
                Text(title).font(DiaryFonts.pixel(10)).tracking(0.6).foregroundColor(pal.pinkInk)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if squares {
                    Rectangle().stroke(pal.lilacD, lineWidth: 1.5).frame(width: 11, height: 11)
                    Rectangle().stroke(pal.lilacD, lineWidth: 1.5).frame(width: 11, height: 11)
                    Rectangle().fill(pal.goD).frame(width: 12, height: 12)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            DashedLine(color: pal.pinkD)
            content()
        }
        .background(shape.fill(pal.card))
        .overlay(shape.stroke(pal.pinkD, lineWidth: 1.5))
        .background(shape.fill(pal.pink).offset(y: 4))
    }
}

struct DashedLine: View {
    let color: Color
    var body: some View {
        Rectangle().fill(Color.clear).frame(height: 1.5)
            .overlay(Line().stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
    }
    private struct Line: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: r.midY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            return p
        }
    }
}

// MARK: 数据

struct ReminderItem: Identifiable, Equatable {
    let rid: String
    let day: String          // 这一次是哪天（重复的展开过）
    let time: String         // "" = 全天
    let title: String
    let note: String
    let repeatKind: String
    let alertMin: Int
    let author: String       // user = 她 / assistant = 他
    var done: Bool

    var id: String { rid + "_" + day }
    var isHim: Bool { author == "assistant" }
    var timeLabel: String { time.isEmpty ? "全天" : time }
    var repeatLabel: String {
        ["daily": "每天", "weekly": "每周", "monthly": "每月", "yearly": "每年"][repeatKind] ?? ""
    }
    /// 「10/03」
    var shortDay: String {
        let p = day.split(separator: "-")
        guard p.count == 3 else { return day }
        return "\(p[1])/\(p[2])"
    }

    init?(_ o: [String: Any]) {
        guard let rid = o["id"] as? String, let day = o["day"] as? String else { return nil }
        self.rid = rid
        self.day = day
        time = o["time"] as? String ?? ""
        title = o["title"] as? String ?? ""
        note = o["note"] as? String ?? ""
        repeatKind = o["repeat"] as? String ?? "none"
        alertMin = o["alert_min"] as? Int ?? 0
        author = o["author"] as? String ?? "user"
        done = o["done"] as? Bool ?? false
    }
}

enum ReminderAPI {
    static func month(year: Int, month: Int) async -> [ReminderItem] {
        let ym = String(format: "%04d-%02d", year, month)
        guard let obj = try? await NativeHouseAPI.object("/api/reminders/month?ym=\(ym)") else { return [] }
        return obj.array("items").compactMap(ReminderItem.init)
    }
    static func upcoming(_ n: Int = 3) async -> [ReminderItem] {
        guard let obj = try? await NativeHouseAPI.object("/api/reminders/upcoming?n=\(n)") else { return [] }
        return obj.array("items").compactMap(ReminderItem.init)
    }
    static func add(_ body: [String: Any]) async -> String? {
        guard let obj = try? await NativeHouseAPI.objectIncludingHTTPError("/api/reminders/add", method: "POST", body: body)
        else { return "连不上小屋" }
        return (obj["ok"] as? Bool == true) ? nil : (obj["error"] as? String ?? "没加上")
    }
    static func setDone(_ it: ReminderItem, _ done: Bool) async {
        _ = try? await NativeHouseAPI.object("/api/reminders/done", method: "POST",
                                              body: ["id": it.rid, "day": it.day, "done": done])
    }
    static func delete(_ it: ReminderItem) async {
        _ = try? await NativeHouseAPI.object("/api/reminders/delete", method: "POST", body: ["id": it.rid])
    }
}

// MARK: 「NEXT UP」那一排

struct ReminderNextStrip: View {
    let items: [ReminderItem]
    let pal: DiaryPixelPalette

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text("NEXT").font(DiaryFonts.pixel(9))
                Text("UP").font(DiaryFonts.pixel(9))
            }
            .foregroundColor(pal.goInk)
            .frame(width: 38, alignment: .leading)
            ForEach(items.prefix(3)) { it in chip(it) }
            if items.count < 3 { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 14)
    }

    private func chip(_ it: ReminderItem) -> some View {
        let edge = it.isHim ? pal.blueD : pal.pinkD
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                PixelGlyph(rows: DPX.bell, colors: pal.bell(him: it.isHim), scale: 1)
                Text("\(it.shortDay) \(it.timeLabel)").font(DiaryFonts.pixel(8.5)).foregroundColor(pal.sub)
                    .lineLimit(1)
            }
            Text(it.title).font(.system(size: 11.5, weight: .medium)).foregroundColor(pal.ink).lineLimit(1)
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(PixelKeycap(fill: pal.card, edge: edge, radius: 7))
    }
}

// MARK: 某天的提醒栏

struct ReminderDayPanel: View {
    let title: String
    let items: [ReminderItem]
    let pal: DiaryPixelPalette
    let onToggle: (ReminderItem) -> Void
    let onDelete: (ReminderItem) -> Void

    var body: some View {
        DiaryPixelWindow(pal: pal, title: title, icon: DPX.clock, squares: false) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                    row(it)
                    if i < items.count - 1 { DashedLine(color: pal.lilac).padding(.horizontal, 10) }
                }
            }
        }
    }

    private func row(_ it: ReminderItem) -> some View {
        HStack(spacing: 8) {
            Button { onToggle(it) } label: {
                ZStack {
                    Rectangle().fill(it.done ? pal.go : pal.card)
                    Rectangle().stroke(it.done ? pal.goD : pal.lilacD, lineWidth: 1.5)
                    if it.done { PixelGlyph(rows: DPX.check, colors: ["o": pal.goInk], scale: 2) }
                }
                .frame(width: 16, height: 16)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(it.timeLabel).font(DiaryFonts.pixel(10)).foregroundColor(pal.lilacInk)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(it.title).font(.system(size: 13.5))
                    .foregroundColor(it.done ? pal.sub : pal.ink)
                    .strikethrough(it.done, color: pal.sub)
                if !it.note.isEmpty {
                    Text(it.note).font(.system(size: 11)).foregroundColor(pal.sub).lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            if !it.repeatLabel.isEmpty {
                Text(it.repeatLabel).font(.system(size: 10)).foregroundColor(pal.sub)
            }
            Text(it.isHim ? "HIM" : "HER").font(DiaryFonts.pixel(8.5))
                .foregroundColor(it.isHim ? pal.blueInk : pal.pinkInk)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(it.isHim ? pal.blue : pal.pink))
        }
        .padding(.leading, 4).padding(.trailing, 12).padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) { onDelete(it) } label: {
                Label(it.repeatKind == "none" ? "删掉这条" : "删掉这条（以后每次都不提醒了）", systemImage: "trash")
            }
        }
    }
}

// MARK: 新建提醒（照 sheet.png）

struct NewReminderSheet: View {
    let pal: DiaryPixelPalette
    let onAdded: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var year: Int
    @State private var month: Int
    @State private var picked: DateComponents
    @State private var allDay = false
    @State private var hour = 9
    @State private var minute = 30
    @State private var repeatKind = "none"
    @State private var alertMin = 60
    @State private var note = ""
    @State private var saving = false
    @State private var error: String?
    @FocusState private var titleFocused: Bool

    private static let repeats: [(String, String)] = [("none", "不重复"), ("daily", "每天"), ("weekly", "每周"), ("monthly", "每月"), ("yearly", "每年")]
    private static let alerts: [(Int, String)] = [(0, "准时"), (60, "提前1小时"), (1440, "提前1天")]

    init(pal: DiaryPixelPalette, initialDay: String?, onAdded: @escaping () -> Void) {
        self.pal = pal
        self.onAdded = onAdded
        let cal = Calendar.current
        var c = cal.dateComponents([.year, .month, .day], from: Date())
        if let s = initialDay {
            let p = s.split(separator: "-").compactMap { Int($0) }
            if p.count == 3 {
                var cc = DateComponents(); cc.year = p[0]; cc.month = p[1]; cc.day = p[2]
                // 在过去的日子点「＋」：日期还是给今天，别订到昨天去
                if let d = cal.date(from: cc), d >= cal.startOfDay(for: Date()) { c = cc }
            }
        }
        _picked = State(initialValue: c)
        _year = State(initialValue: c.year ?? 2026)
        _month = State(initialValue: c.month ?? 1)
    }

    var body: some View {
        ZStack(alignment: .top) {
            DiaryPixelPaper(pal: pal)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    header
                    card {
                        row("TITLE") {
                            TextField("", text: $title, prompt: Text("要提醒什么…").foregroundColor(pal.sub))
                                .font(.system(size: 14)).foregroundColor(pal.ink).focused($titleFocused)
                        }
                        DashedLine(color: pal.lilac)
                        row("ALL DAY") {
                            Spacer()
                            pixelSwitch
                        }
                        DashedLine(color: pal.lilac)
                        miniCalendar
                        if !allDay {
                            DashedLine(color: pal.lilac)
                            row("TIME") {
                                Spacer()
                                timeBox(hour, options: Array(0..<24)) { hour = $0 }
                                Text(":").font(DiaryFonts.pixel(14)).foregroundColor(pal.lilacInk)
                                timeBox(minute, options: Array(stride(from: 0, to: 60, by: 5))) { minute = $0 }
                            }
                        }
                    }
                    card {
                        row("REPEAT") { pills(Self.repeats, selected: repeatKind) { repeatKind = $0 } }
                        DashedLine(color: pal.lilac)
                        row("ALERT") { pills(Self.alerts, selected: alertMin) { alertMin = $0 } }
                        DashedLine(color: pal.lilac)
                        row("NOTE") {
                            TextField("", text: $note, prompt: Text("备注（可不填）").foregroundColor(pal.sub), axis: .vertical)
                                .font(.system(size: 14)).foregroundColor(pal.ink).lineLimit(1...4)
                        }
                    }
                    HStack(spacing: 6) {
                        PixelGlyph(rows: DPX.bell, colors: pal.bell(him: true), scale: 1.6)
                        Text(error ?? "到点后台告诉陈璟 · 这条标成「你加的」")
                            .font(.system(size: 11)).foregroundColor(error == nil ? pal.sub : pal.pinkInk)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            DiaryFonts.ensure()
            titleFocused = true
        }
    }

    private var header: some View {
        HStack {
            Button("取消") { dismiss() }
                .font(.system(size: 13)).foregroundColor(pal.lilacInk)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .modifier(PixelKeycap(fill: pal.card, edge: pal.lilacD))
            Spacer()
            Text("NEW.REMINDER").font(DiaryFonts.pixel(12)).tracking(1).foregroundColor(pal.pinkInk)
            Spacer()
            Button(saving ? "…" : "添加") { save() }
                .font(.system(size: 13, weight: .medium)).foregroundColor(pal.goInk)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .modifier(PixelKeycap(fill: pal.go, edge: pal.goD))
                .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14).padding(.top, 18)
    }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(spacing: 0) { c() }
            .background(shape.fill(pal.card))
            .overlay(shape.stroke(pal.lilacD, lineWidth: 1.5))
            .background(shape.fill(pal.lilac).offset(y: 3))
            .padding(.horizontal, 12)
    }

    private func row<C: View>(_ key: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(key).font(DiaryFonts.pixel(10)).tracking(0.5).foregroundColor(pal.lilacInk)
                .frame(width: 62, alignment: .leading)
            c()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private var pixelSwitch: some View {
        Button { withAnimation(.easeInOut(duration: 0.15)) { allDay.toggle() } } label: {
            ZStack(alignment: allDay ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 6).fill(allDay ? pal.go : pal.card)
                RoundedRectangle(cornerRadius: 6).stroke(allDay ? pal.goD : pal.lilacD, lineWidth: 1.5)
                RoundedRectangle(cornerRadius: 4).fill(allDay ? pal.card : pal.lilacD)
                    .frame(width: 16, height: 16).padding(3)
            }
            .frame(width: 42, height: 22)
        }
        .buttonStyle(.plain)
    }

    private func timeBox(_ value: Int, options: [Int], set: @escaping (Int) -> Void) -> some View {
        Menu {
            ForEach(options, id: \.self) { v in
                Button(String(format: "%02d", v)) { set(v) }
            }
        } label: {
            Text(String(format: "%02d", value)).font(DiaryFonts.pixel(15)).foregroundColor(pal.lilacInk)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(pal.lilac))
        }
    }

    private func pills<T: Hashable>(_ opts: [(T, String)], selected: T, set: @escaping (T) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(opts.indices, id: \.self) { i in
                    let opt = opts[i]
                    let on = opt.0 == selected
                    Button { set(opt.0) } label: {
                        Text(opt.1).font(.system(size: 12))
                            .foregroundColor(on ? pal.pinkInk : pal.lilacInk)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 7).fill(on ? pal.pink : pal.lilac))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? pal.pinkD : Color.clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // 像素小月历：过去的日子灰着点不了
    private var miniCalendar: some View {
        let cal = Calendar.current
        var first = DateComponents(); first.year = year; first.month = month; first.day = 1
        let firstDate = cal.date(from: first) ?? Date()
        let days = cal.range(of: .day, in: .month, for: firstDate)?.count ?? 30
        let lead = (cal.component(.weekday, from: firstDate) + 5) % 7
        let today = cal.startOfDay(for: Date())
        let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        let names = ["一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月"]
        return VStack(spacing: 4) {
            HStack {
                Button { shift(-1) } label: { Text("<").font(DiaryFonts.pixel(12)).frame(width: 30, height: 26) }
                Spacer()
                Text("\(String(year)) · \(names[max(0, min(11, month - 1))])").font(DiaryFonts.pixel(11)).tracking(1)
                Spacer()
                Button { shift(1) } label: { Text(">").font(DiaryFonts.pixel(12)).frame(width: 30, height: 26) }
            }
            .buttonStyle(.plain)
            .foregroundColor(pal.lilacInk)
            LazyVGrid(columns: cols, spacing: 2) {
                ForEach(["MO", "TU", "WE", "TH", "FR", "SA", "SU"], id: \.self) { w in
                    Text(w).font(DiaryFonts.pixel(8.5)).foregroundColor(pal.sub).frame(height: 16)
                }
                ForEach(-lead..<0, id: \.self) { _ in Color.clear.frame(height: 30) }
                ForEach(1...days, id: \.self) { d in
                    dayButton(d, past: isPast(d, today: today))
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private func isPast(_ d: Int, today: Date) -> Bool {
        var c = DateComponents(); c.year = year; c.month = month; c.day = d
        guard let dt = Calendar.current.date(from: c) else { return false }
        return dt < today
    }

    private func dayButton(_ d: Int, past: Bool) -> some View {
        let on = picked.year == year && picked.month == month && picked.day == d
        return Button {
            var c = DateComponents(); c.year = year; c.month = month; c.day = d
            picked = c
        } label: {
            ZStack {
                if on {
                    RoundedRectangle(cornerRadius: 6).fill(pal.pinkInk).frame(width: 27, height: 27)
                        .background(RoundedRectangle(cornerRadius: 6).fill(pal.pinkD).offset(y: 2))
                }
                Text("\(d)").font(DiaryFonts.pixel(11))
                    .foregroundColor(on ? pal.card : (past ? pal.lilacD : pal.ink))
            }
            .frame(height: 30).frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(past)
    }

    private func shift(_ delta: Int) {
        month += delta
        if month > 12 { month = 1; year += 1 }
        if month < 1 { month = 12; year -= 1 }
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let y = picked.year, let m = picked.month, let d = picked.day else { return }
        saving = true
        error = nil
        let body: [String: Any] = [
            "title": t, "day": String(format: "%04d-%02d-%02d", y, m, d),
            "time": allDay ? "" : String(format: "%02d:%02d", hour, minute), "all_day": allDay,
            "repeat": repeatKind, "alert_min": alertMin, "note": note, "author": "user",
        ]
        Task {
            let err = await ReminderAPI.add(body)
            saving = false
            if let err {
                error = err
            } else {
                onAdded()
                dismiss()
            }
        }
    }
}

// MARK: 聊天页小卡（照 bits.png 第二块：整行居中、不大）

struct ReminderChatCard: Decodable {
    let id: String
    let day: String
    let time: String?
    let title: String
    let note: String?
    let author: String?
    let created: String?
    let repeatLabel: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id, day, time, title, note, author, created, status
        case repeatLabel = "repeat"
    }
}

struct ReminderMessageCard: View {
    let card: ReminderChatCard
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = "dark"
    @ObservedObject private var fonts = KakaoPackStore.shared

    private var pal: DiaryPixelPalette { _ = houseAppearance; return DiaryPixelPalette(dark: AlcoveAppearance.isDark) }
    private var him: Bool { card.author == "assistant" }

    private var dateLine: String {
        let p = card.day.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return card.day }
        var c = DateComponents(); c.year = p[0]; c.month = p[1]; c.day = p[2]
        var wd = ""
        if let dt = Calendar.current.date(from: c) {
            wd = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][(Calendar.current.component(.weekday, from: dt) - 1) % 7]
        }
        return String(format: "%02d/%02d ", p[1], p[2]) + wd
    }

    private var footLine: String {
        var parts: [String] = []
        if let c = card.created, c.count >= 10 {
            let p = c.prefix(10).split(separator: "-").compactMap { Int($0) }
            if p.count == 3 { parts.append("\(p[1])/\(p[2]) 订的") }
        }
        if let r = card.repeatLabel, !r.isEmpty { parts.append(r) }
        if let s = card.status, !s.isEmpty { parts.append(s) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let p = pal
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                PixelGlyph(rows: DPX.bell, colors: p.bell(him: him), scale: 1)
                Text("REMINDER").font(DiaryFonts.pixel(9)).tracking(0.6).foregroundColor(p.pinkInk)
                Spacer()
                Rectangle().stroke(p.lilacD, lineWidth: 1.5).frame(width: 9, height: 9)
                Rectangle().fill(p.goD).frame(width: 10, height: 10)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            DashedLine(color: p.pinkD)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text((card.time ?? "").isEmpty ? "全天" : (card.time ?? "")).font(DiaryFonts.pixel(17)).foregroundColor(p.lilacInk)
                    Text(dateLine).font(DiaryFonts.pixel(8.5)).foregroundColor(p.sub)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title).font(.system(size: 14, weight: .medium)).foregroundColor(p.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let n = card.note, !n.isEmpty {
                        Text(n).font(.system(size: 11)).foregroundColor(p.sub).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            DashedLine(color: p.lilac)
            HStack(spacing: 5) {
                Text(him ? "HIM" : "HER").font(DiaryFonts.pixel(8.5))
                    .foregroundColor(him ? p.blueInk : p.pinkInk)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(him ? p.blue : p.pink))
                Text(footLine).font(.system(size: 10.5)).foregroundColor(p.sub).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
        }
        .frame(width: 236)
        .background(shape.fill(p.card))
        .overlay(shape.stroke(p.pinkD, lineWidth: 1.5))
        .background(shape.fill(p.pink).offset(y: 3))
        .onAppear { DiaryFonts.ensure() }
    }
}
