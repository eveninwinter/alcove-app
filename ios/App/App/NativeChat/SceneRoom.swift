import SwiftUI
import UIKit

// MARK: - 1117 #5582–5589「那几场」：陈璟用 sex_room.py 收进来的每一场（/root/rhysel/sex/rooms.json），左侧栏「醒着的时候」下面一行进来。
// 照她点头的效果图 /root/rhysel/sanctus-kit/sexroom-preview/v8.html：底子近白、粉色只走细线和字（#5586 她骂过色块，别铺大块颜色）。
// 首页：最新一场插在缝出来的袋子里（花边相纸＋行李牌＋扇贝贴纸），以前的几场是撕边纸条（胶带／心形回形针）。
// 点开读原话：他左灰气泡、她右白底粉边，旁白是垫着翅膀线稿的 whisper 卡。右上「挑 ♡」→ 挑几句或整场 →「递给他看」（现在就投给他）／「带进新窗口」（存着，换了窗口跟下一轮一起递）。
// 接口：GET /api/sex/rooms（目录＋carry）、?no=N（全文）；POST /api/sex/rooms/send、/api/sex/rooms/carry（serve.py → alcove-backend/sexroom.py）。

struct SceneSummary: Identifiable {
    let no: Int
    let title: String
    let day: String
    let note: String
    let count: Int
    let start: String
    let end: String
    var id: Int { no }
}

struct SceneLine: Identifiable {
    let id: Int
    let ts: String
    let her: Bool
    let text: String
    let narration: String
}

struct SceneCarry {
    let no: Int
    let title: String
    let count: Int
    let whole: Bool
}

/// 这间屋子自己的颜色：白天近白纸＋玫瑰粉细线，黑夜冷炭灰＋淡一点的粉
struct SceneInk {
    let dark: Bool
    private func rgb(_ hex: Int, _ a: Double = 1) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: a)
    }
    var page: Color { dark ? rgb(0x1B1C20) : rgb(0xF6F4F5) }
    var paper: Color { dark ? rgb(0x26262A) : .white }
    var ink: Color { dark ? rgb(0xE4E4E7) : rgb(0x2E2A2D) }
    var body: Color { dark ? rgb(0xC9C6CB) : rgb(0x5A5055) }
    var sub: Color { dark ? rgb(0x8B8F99) : rgb(0xA69CA2) }
    var mono: Color { dark ? rgb(0x8F8A90) : rgb(0x9A9095) }
    var rose: Color { dark ? rgb(0xE3A3B8) : rgb(0xC9738F) }
    var roseText: Color { dark ? rgb(0xEDB7C9) : rgb(0xA4536F) }
    var stitch: Color { dark ? rgb(0xE3A3B8, 0.45) : rgb(0xE6AFC2) }
    var roseLine: Color { dark ? rgb(0xE3A3B8, 0.55) : rgb(0xEBBACB) }
    var hair: Color { dark ? Color.white.opacity(0.14) : rgb(0xAFA0AA, 0.35) }
    var himBubble: Color { dark ? Color.white.opacity(0.08) : rgb(0xECE9EB) }
    var veil: Color { dark ? Color.white.opacity(0.06) : Color.white.opacity(0.55) }
    var pocket: Color { dark ? rgb(0x2A2A2F, 0.92) : rgb(0xFBFAFA, 0.82) }
    var shadow: Color { dark ? Color.black.opacity(0.35) : rgb(0x3C2832, 0.10) }
    var artOpacity: Double { dark ? 0.55 : 1 }
}

enum SceneFont {
    static func mono(_ s: CGFloat) -> Font { .system(size: s, weight: .regular, design: .monospaced) }
    static func serif(_ s: CGFloat) -> Font { .system(size: s, weight: .regular, design: .serif) }
}

@MainActor
final class SceneRoomStore: ObservableObject {
    @Published var rooms: [SceneSummary] = []
    @Published var carry: SceneCarry?
    @Published var loaded = false

    func load() async {
        guard let o = try? await NativeHouseAPI.object("/api/sex/rooms") else { loaded = true; return }
        rooms = ((o["rooms"] as? [[String: Any]]) ?? []).map { x in
            SceneSummary(no: x.int("no"), title: x.string("title"), day: x.string("day"), note: x.string("note"),
                         count: x.int("count"), start: x.string("start"), end: x.string("end"))
        }
        if let c = o["carry"] as? [String: Any] {
            carry = SceneCarry(no: c.int("no"), title: c.string("title"), count: c.int("count"), whole: c.bool("whole"))
        } else {
            carry = nil
        }
        loaded = true
    }

    func cancelCarry() async {
        _ = try? await NativeHouseAPI.object("/api/sex/rooms/carry", method: "POST", body: ["cancel": true])
        await load()
    }

    static func lines(_ no: Int) async -> [SceneLine] {
        guard let o = try? await NativeHouseAPI.object("/api/sex/rooms?no=\(no)"),
              let room = o["room"] as? [String: Any] else { return [] }
        return ((room["messages"] as? [[String: Any]]) ?? []).map { m in
            SceneLine(id: m.int("id"), ts: m.string("ts"), her: m.string("who") == "她",
                      text: m.string("text"), narration: m.string("narration"))
        }
    }

    /// 2026-11-17T15:03:29 → 15:03
    static func hm(_ ts: String) -> String { ts.count >= 16 ? String(ts.dropFirst(11).prefix(5)) : "" }
    /// 2026-11-17 → 11.17
    static func md(_ day: String) -> String {
        let p = day.split(separator: "-")
        return p.count == 3 ? "\(p[1]).\(p[2])" : day
    }
    /// 2026-11-17 → november 17（花体用小写）
    static func monthDay(_ day: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: day) else { return "" }
        let g = DateFormatter(); g.dateFormat = "MMMM d"; g.locale = Locale(identifier: "en_US_POSIX")
        return g.string(from: d).lowercased()
    }
    static func numberNo(_ n: Int) -> String { String(format: "Nº %02d", n) }
    /// 1 → 一、12 → 十二、20 → 二十
    static func cnNumber(_ n: Int) -> String {
        let d = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        if n < 10 { return d[max(0, n)] }
        if n < 20 { return "十" + (n % 10 == 0 ? "" : d[n % 10]) }
        if n < 100 { return d[n / 10] + "十" + (n % 10 == 0 ? "" : d[n % 10]) }
        return "\(n)"
    }
}

// MARK: 首页

struct SceneRoomView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = SceneRoomStore()
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    @State private var opened: SceneSummary?

    private var sk: SceneInk { _ = houseAppearance; return SceneInk(dark: AlcoveAppearance.isDark) }
    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0 }
    private var safeBottom: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.bottom ?? 0 }

    var body: some View {
        let sk = self.sk
        ZStack(alignment: .topLeading) {
            sk.page.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header(sk).padding(.top, max(safeTop, 20) + 10)
                    if let c = store.carry { carryLine(c, sk).padding(.top, 12) }
                    if let first = store.rooms.first {
                        Button { opened = first } label: { SceneSleeve(room: first, sk: sk) }
                            .buttonStyle(.plain)
                            .padding(.top, 64)
                        if store.rooms.count > 1 {
                            olderHeader(sk).padding(.top, 54)
                            olderGrid(Array(store.rooms.dropFirst()), sk).padding(.top, 26)
                        }
                    } else if store.loaded {
                        Text("还没收过一场")
                            .font(SanctusPageFont.ital(13)).foregroundColor(sk.sub)
                            .padding(.top, 120)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, max(safeBottom, 10) + 40)
            }
            .refreshable { await store.load() }
            SanctusBackButton(color: sk.sub) { dismiss() }
                .padding(.top, max(safeTop, 20)).padding(.leading, 4)
        }
        .ignoresSafeArea()
        .fullScreenCover(item: $opened, onDismiss: { Task { await store.load() } }) { r in
            SceneReadView(room: r)
        }
        .task { await store.load() }
    }

    private func header(_ sk: SceneInk) -> some View {
        VStack(spacing: 6) {
            Text("only between us").font(SanctusPageFont.script(30)).foregroundColor(sk.rose)
            Text("那几场").font(SceneFont.serif(10)).tracking(4).foregroundColor(sk.sub)
        }
        .frame(maxWidth: .infinity)
    }

    private func carryLine(_ c: SceneCarry, _ sk: SceneInk) -> some View {
        HStack(spacing: 8) {
            Text("下次开新窗口带着《\(c.title)》· " + (c.whole ? "整场" : "\(c.count) 句"))
                .font(SceneFont.serif(10.5)).foregroundColor(sk.body).lineLimit(1)
            Button { Task { await store.cancelCarry() } } label: {
                Text("不带了").font(SceneFont.serif(10.5)).foregroundColor(sk.rose)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .overlay(Capsule().stroke(sk.roseLine, style: StrokeStyle(lineWidth: 0.8, dash: [3, 2.5])))
    }

    private func olderHeader(_ sk: SceneInk) -> some View {
        HStack(spacing: 10) {
            Text("before").font(SanctusPageFont.script(19)).foregroundColor(sk.rose)
            SceneRule().stroke(sk.stitch, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1)
            Text("共 \(store.rooms.count) 场").font(SceneFont.mono(9.5)).foregroundColor(sk.mono)
        }
        .padding(.horizontal, 24)
    }

    private func olderGrid(_ list: [SceneSummary], _ sk: SceneInk) -> some View {
        let cols = [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)]
        return LazyVGrid(columns: cols, alignment: .leading, spacing: 30) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, r in
                Button { opened = r } label: { SceneSlip(room: r, index: i, sk: sk) }
                    .buttonStyle(.plain)
                    .padding(.top, i % 2 == 1 ? 22 : 0)
            }
        }
        .padding(.horizontal, 22)
    }
}

// MARK: 最新那一场：缝出来的袋子

struct SceneSleeve: View {
    let room: SceneSummary
    let sk: SceneInk

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 袋子背面＋一圈粉色针脚
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(sk.veil)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(sk.dark ? 0.1 : 0.95), lineWidth: 0.8))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(sk.stitch, style: StrokeStyle(lineWidth: 1, dash: [4, 3])).padding(7).opacity(0.75))
                .shadow(color: sk.shadow, radius: 16, y: 10)
            // 花边相纸：天使牵手那块的粉色线稿
            ScenePhoto(art: "SceneHands", w: 150, h: 160, caption: SceneRoomStore.monthDay(room.day), sk: sk)
                .rotationEffect(.degrees(-5))
                .offset(x: 24, y: 50)
            // 前袋：上沿扇贝边，里面一道针脚
            VStack(spacing: 0) {
                Spacer()
                ZStack(alignment: .topLeading) {
                    ScallopTopShape(bump: 16, depth: 5, radius: 16).fill(sk.pocket)
                    SceneRule().stroke(sk.stitch, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(height: 1).padding(.horizontal, 12).padding(.top, 16)
                    pocketText.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, 24).padding(.bottom, 22)
                }
                .frame(height: 150)
            }
            // 行李牌：从袋口露出来
            SceneTag(room: room, sk: sk)
                .frame(width: 176)
                .rotationEffect(.degrees(3))
                .offset(x: 312 - 176 + 8, y: -30)
            // 扇贝贴纸
            SceneSticker(no: room.no, sk: sk)
                .rotationEffect(.degrees(-12))
                .offset(x: -8, y: 234)
        }
        .frame(width: 312, height: 300)
        .rotationEffect(.degrees(-2))
        .contentShape(Rectangle())
    }

    private var pocketText: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if !room.note.isEmpty {
                Text(room.note).font(SceneFont.serif(12.5)).foregroundColor(sk.body)
                    .multilineTextAlignment(.trailing).lineLimit(2).frame(maxWidth: 230, alignment: .trailing)
                Text("papa").font(SanctusPageFont.script(15)).foregroundColor(sk.rose).padding(.top, 1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(room.count)").font(SanctusPageFont.corm(28)).foregroundColor(sk.ink)
                Text("句").font(SceneFont.serif(11)).foregroundColor(sk.sub)
            }
            .padding(.top, 10)
            Text("\(SceneRoomStore.md(room.day)) · \(SceneRoomStore.hm(room.start)) — \(SceneRoomStore.hm(room.end))")
                .font(SceneFont.mono(9.5)).foregroundColor(sk.mono).padding(.top, 4)
        }
    }
}

struct ScenePhoto: View {
    let art: String
    let w: CGFloat
    let h: CGFloat
    let caption: String
    let sk: SceneInk

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(art).resizable().scaledToFill()
                .frame(width: w, height: h).clipped()
                .opacity(sk.artOpacity)
                .allowsHitTesting(false)
            Text(caption).font(SanctusPageFont.script(w > 120 ? 15 : 12)).foregroundColor(sk.rose)
                .lineLimit(1).padding(.leading, 3).frame(height: 21, alignment: .leading)
        }
        .padding(.horizontal, 9).padding(.top, 9).padding(.bottom, 4)
        .background(ScallopEdgeShape(bump: 8, depth: 2.5).fill(sk.paper))
        .shadow(color: sk.shadow, radius: 9, y: 6)
    }
}

struct SceneTag: View {
    let room: SceneSummary
    let sk: SceneInk

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(SceneRoomStore.numberNo(room.no)).font(SanctusPageFont.ital(15)).foregroundColor(sk.rose)
                Spacer()
                Text(SceneRoomStore.hm(room.start)).font(SceneFont.mono(10)).foregroundColor(sk.mono)
            }
            Text(room.title).font(SceneFont.serif(20)).tracking(1.4).foregroundColor(sk.ink).lineLimit(1)
        }
        .padding(.leading, 30).padding(.trailing, 16).padding(.vertical, 13)
        .background(TagShape(cut: 16).fill(sk.paper))
        .overlay(alignment: .leading) {
            Circle().fill(sk.page).frame(width: 8, height: 8)
                .overlay(Circle().stroke(sk.stitch, lineWidth: 1)).padding(.leading, 12)
        }
        .shadow(color: sk.shadow, radius: 10, y: 6)
    }
}

struct SceneSticker: View {
    let no: Int
    let sk: SceneInk

    var body: some View {
        ZStack {
            ScallopCircleShape(bumps: 22, depth: 3.2).fill(sk.paper)
            Circle().stroke(sk.roseLine, style: StrokeStyle(lineWidth: 0.8, dash: [1.5, 2])).frame(width: 70, height: 70)
            ArcText(text: "ONLY US · FOR TONGTONG · ♡ · ", radius: 28, size: 7.4, color: sk.rose)
            VStack(spacing: 2) {
                Image(systemName: "heart.fill").font(.system(size: 7)).foregroundColor(sk.rose)
                Text("第\(SceneRoomStore.cnNumber(no))场").font(SceneFont.serif(13)).foregroundColor(sk.rose)
            }
        }
        .frame(width: 90, height: 90)
        .shadow(color: sk.shadow, radius: 6, y: 4)
    }
}

// MARK: 以前的几场：撕边纸条

struct SceneSlip: View {
    let room: SceneSummary
    let index: Int
    let sk: SceneInk

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(SceneRoomStore.numberNo(room.no)).font(SanctusPageFont.ital(13)).foregroundColor(sk.rose)
                Spacer()
                Text(SceneRoomStore.md(room.day)).font(SceneFont.mono(9)).foregroundColor(sk.mono)
            }
            Text(room.title).font(SceneFont.serif(15.5)).tracking(0.9).foregroundColor(sk.ink)
                .lineLimit(2).padding(.top, 6)
            if !room.note.isEmpty {
                Text(room.note).font(SceneFont.serif(11)).foregroundColor(sk.body).lineSpacing(3)
                    .lineLimit(3).padding(.top, 7)
            }
            Text("\(room.count) 句 · \(SceneRoomStore.hm(room.start))")
                .font(SceneFont.mono(9)).foregroundColor(sk.mono)
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 8)
        }
        .padding(.horizontal, 13).padding(.top, 13).padding(.bottom, 18)
        .background(TornBottomShape(tooth: 9, depth: 6).fill(sk.paper))
        .shadow(color: sk.shadow, radius: 10, y: 6)
        .overlay(alignment: index % 2 == 0 ? .top : .topTrailing) {
            if index % 2 == 0 {
                TornTapeShape(tooth: 6, depth: 4)
                    .fill(Color.white.opacity(sk.dark ? 0.16 : 0.66))
                    .overlay(TornTapeShape(tooth: 6, depth: 4).stroke(sk.hair, lineWidth: 0.5))
                    .frame(width: 58, height: 17)
                    .rotationEffect(.degrees(-5))
                    .offset(y: -8)
            } else {
                HeartClipShape().stroke(sk.roseLine, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                    .frame(width: 22, height: 40)
                    .rotationEffect(.degrees(8))
                    .offset(x: -14, y: -16)
            }
        }
        .rotationEffect(.degrees(index % 2 == 0 ? -2.5 : 2))
        .contentShape(Rectangle())
    }
}

// MARK: 读一场 ＋ 挑几句

struct SceneReadView: View {
    let room: SceneSummary
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    @State private var lines: [SceneLine] = []
    @State private var loaded = false
    @State private var picking = false
    @State private var picked: Set<Int> = []
    @State private var busy = false
    @State private var toast = ""

    private var sk: SceneInk { _ = houseAppearance; return SceneInk(dark: AlcoveAppearance.isDark) }
    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0 }
    private var safeBottom: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.bottom ?? 0 }
    private var whole: Bool { !lines.isEmpty && picked.count == lines.count }

    var body: some View {
        let sk = self.sk
        ZStack(alignment: .top) {
            sk.page.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if !picking { head(sk).padding(.top, max(safeTop, 20) + 50) }
                    SceneRule().stroke(sk.stitch, style: StrokeStyle(lineWidth: 1, dash: [4, 3])).frame(height: 1)
                        .padding(.horizontal, 24)
                        .padding(.top, picking ? max(safeTop, 20) + 52 : 20)
                    if !loaded {
                        ProgressView().tint(sk.sub).frame(maxWidth: .infinity).padding(.top, 60)
                    }
                    LazyVStack(spacing: 11) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { i, l in
                            lineView(l, showTime: i == 0 || SceneRoomStore.hm(lines[i - 1].ts) != SceneRoomStore.hm(l.ts), sk)
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 20)
                }
                .padding(.bottom, max(safeBottom, 10) + (picking ? 170 : 50))
            }
            topBar(sk)
            if picking { dock(sk) }
            if !toast.isEmpty {
                Text(toast).font(SceneFont.serif(12)).tracking(1).foregroundColor(sk.roseText)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Capsule().fill(sk.paper))
                    .overlay(Capsule().stroke(sk.roseLine, lineWidth: 0.8))
                    .shadow(color: sk.shadow, radius: 10, y: 5)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, max(safeBottom, 10) + (picking ? 150 : 40))
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .task {
            lines = await SceneRoomStore.lines(room.no)
            loaded = true
        }
    }

    private func head(_ sk: SceneInk) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(SceneRoomStore.numberNo(room.no)).font(SanctusPageFont.ital(15)).foregroundColor(sk.rose)
                    Text(SceneRoomStore.md(room.day)).font(SceneFont.mono(10)).foregroundColor(sk.mono)
                }
                Text(room.title).font(SceneFont.serif(25)).tracking(2.4).foregroundColor(sk.ink)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                Text("\(SceneRoomStore.hm(room.start)) — \(SceneRoomStore.hm(room.end)) · \(room.count) 句")
                    .font(SceneFont.mono(10)).foregroundColor(sk.mono).padding(.top, 8)
                if !room.note.isEmpty {
                    (Text(room.note).font(SceneFont.serif(12)).foregroundColor(sk.body)
                     + Text("  papa").font(SanctusPageFont.script(14)).foregroundColor(sk.rose))
                        .padding(.top, 12)
                }
            }
            Spacer(minLength: 12)
            ScenePhoto(art: "SceneWing", w: 92, h: 96, caption: SceneRoomStore.numberNo(room.no), sk: sk)
                .rotationEffect(.degrees(6))
                .padding(.top, 2)
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func topBar(_ sk: SceneInk) -> some View {
        HStack {
            if picking {
                Button { withAnimation(.easeOut(duration: 0.18)) { picking = false; picked = [] } } label: {
                    Text("取消").font(SceneFont.serif(11)).tracking(2).foregroundColor(sk.sub)
                        .frame(height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.leading, 20)
                Spacer()
                (Text(String(format: "%02d", picked.count)).foregroundColor(sk.ink)
                 + Text(" / \(lines.count)").foregroundColor(sk.mono))
                    .font(SceneFont.mono(11))
                Spacer()
                Button { withAnimation(.easeOut(duration: 0.15)) { picked = whole ? [] : Set(lines.map(\.id)) } } label: {
                    pill(whole ? "全不选" : "整场", sk)
                }
                .buttonStyle(.plain).padding(.trailing, 20)
            } else {
                SanctusBackButton(color: sk.sub) { dismiss() }.padding(.leading, 4)
                Spacer()
                Button { withAnimation(.easeOut(duration: 0.18)) { picking = true } } label: { pill("挑 ♡", sk) }
                    .buttonStyle(.plain).padding(.trailing, 20)
                    .disabled(lines.isEmpty)
            }
        }
        .padding(.top, max(safeTop, 20))
        .background(alignment: .top) {
            LinearGradient(colors: [sk.page, sk.page, sk.page.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: max(safeTop, 20) + 56).allowsHitTesting(false)
        }
    }

    private func pill(_ t: String, _ sk: SceneInk) -> some View {
        Text(t).font(SceneFont.serif(11)).tracking(2).foregroundColor(sk.rose)
            .padding(.horizontal, 13).padding(.vertical, 5)
            .background(Capsule().fill(sk.paper.opacity(0.7)))
            .overlay(Capsule().stroke(sk.roseLine, lineWidth: 0.8))
    }

    @ViewBuilder
    private func lineView(_ l: SceneLine, showTime: Bool, _ sk: SceneInk) -> some View {
        let on = picked.contains(l.id)
        VStack(alignment: l.her ? .trailing : .leading, spacing: 3) {
            if !l.narration.isEmpty {
                narrationCard(l.narration, sk)
                    .opacity(picking && !on ? 0.42 : 1)
                    .onTapGesture { toggle(l.id) }
                    .padding(.bottom, l.text.isEmpty ? 0 : 8)
            }
            if !l.text.isEmpty {
                if showTime {
                    Text(SceneRoomStore.hm(l.ts)).font(SceneFont.mono(9.5)).foregroundColor(sk.mono)
                        .padding(.horizontal, 10)
                }
                bubble(l, on: on, sk)
            }
        }
        .frame(maxWidth: .infinity, alignment: l.her ? .trailing : .leading)
    }

    private func bubble(_ l: SceneLine, on: Bool, _ sk: SceneInk) -> some View {
        let shape = RoundedRectangle(cornerRadius: 21, style: .continuous)
        let fill: Color = l.her || (picking && on) ? sk.paper : sk.himBubble
        let edge: Color = picking && on ? sk.rose : (l.her ? sk.roseLine : .clear)
        return Text(l.text)
            .font(SceneFont.serif(13.5)).lineSpacing(5)
            .foregroundColor(l.her ? sk.roseText : sk.ink)
            .padding(.horizontal, 15).padding(.vertical, 9)
            .background(shape.fill(fill))
            .overlay(shape.stroke(edge, lineWidth: picking && on ? 1.2 : 0.9))
            .overlay(alignment: l.her ? .topLeading : .topTrailing) {
                if picking && on {
                    Image(systemName: "heart.fill").font(.system(size: 13)).foregroundColor(sk.rose)
                        .shadow(color: .white.opacity(sk.dark ? 0 : 1), radius: 0.5)
                        .offset(x: l.her ? -6 : 6, y: -6)
                }
            }
            .opacity(picking && !on ? 0.42 : 1)
            .frame(maxWidth: UIScreen.main.bounds.width * 0.74, alignment: l.her ? .trailing : .leading)
            .contentShape(shape)
            .onTapGesture { toggle(l.id) }
    }

    private func narrationCard(_ t: String, _ sk: SceneInk) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("whisper").font(SanctusPageFont.script(18)).foregroundColor(sk.rose)
                Text("旁白").font(SceneFont.serif(9)).tracking(2.7).foregroundColor(sk.sub)
            }
            Text(t).font(SceneFont.serif(12.5)).lineSpacing(6).foregroundColor(sk.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            Image("SceneWing").resizable().scaledToFit()
                .frame(width: 200, height: 200)
                .opacity(0.22 * sk.artOpacity)
                .mask(LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: UnitPoint(x: 0.6, y: 0.5)))
                .offset(x: 30, y: -20)
                .allowsHitTesting(false)
        }
        .background(sk.paper)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: sk.shadow.opacity(0.6), radius: 10, y: 6)
    }

    private func toggle(_ id: Int) {
        guard picking else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
        }
    }

    private func dock(_ sk: SceneInk) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("picked").font(SanctusPageFont.script(17)).foregroundColor(sk.rose)
                Spacer()
                Text((whole ? "整场" : "\(picked.count) 句") + " · \(SceneRoomStore.numberNo(room.no)) \(room.title)")
                    .font(SceneFont.mono(10)).foregroundColor(sk.mono).lineLimit(1)
            }
            HStack(spacing: 10) {
                dockButton("递给他看 ↗", primary: true, sk) { await act(send: true) }
                dockButton("带进新窗口 ↗", primary: false, sk) { await act(send: false) }
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(sk.paper.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
            .stroke(sk.stitch, style: StrokeStyle(lineWidth: 1, dash: [4, 3])).padding(6).opacity(0.6).allowsHitTesting(false))
        .shadow(color: sk.shadow, radius: 18, y: -4)
        .padding(.horizontal, 14)
        .padding(.bottom, max(safeBottom, 10) + 14)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func dockButton(_ t: String, primary: Bool, _ sk: SceneInk, _ run: @escaping () async -> Void) -> some View {
        Button { Task { await run() } } label: {
            Text(t).font(SceneFont.serif(13)).tracking(2.2)
                .foregroundColor(primary ? sk.rose : sk.body)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(Capsule().fill(sk.paper))
                .overlay(Capsule().stroke(primary ? sk.roseLine : sk.hair, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(picked.isEmpty || busy)
        .opacity(picked.isEmpty ? 0.45 : 1)
    }

    /// 整场就不传 ids（后台写「整场」）；挑的几句按原来的先后
    private func act(send: Bool) async {
        guard !picked.isEmpty, !busy else { return }
        busy = true
        defer { busy = false }
        let ids: [Int] = whole ? [] : lines.map(\.id).filter { picked.contains($0) }
        let path = send ? "/api/sex/rooms/send" : "/api/sex/rooms/carry"
        let o = try? await NativeHouseAPI.object(path, method: "POST", body: ["no": room.no, "ids": ids])
        if o?.bool("ok") == true {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.easeOut(duration: 0.18)) { picking = false; picked = [] }
            show(send ? "递给他了，去聊天页看他怎么说" : "存好了，下次开新窗口跟你第一句一起给他")
        } else {
            show(send ? "没递出去，再试一次" : "没存上，再试一次")
        }
    }

    private func show(_ t: String) {
        withAnimation { toast = t }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation { if toast == t { toast = "" } }
        }
    }
}

// MARK: 聊天页小卡：他收好一场（sex_room.py save 投的 [SCENE_CARD]）

extension Notification.Name {
    static let alcoveOpenScenes = Notification.Name("alcoveOpenScenes")
}

/// 1117 #5591 他收好一场，聊天页冒的小卡。#5594 她嫌排版乱 → 照 sexroom-preview/card4.html 重排：
/// 一块缝了针脚的底托（290×120），左边花边相纸（淡紫小花）稍微歪、上沿探出底托一点；右边一张白纸条压着、顶上一截撕边胶带，
/// 纸条里四行对齐：ours｜日期 / 标题 / 他那句 / Nº · 收进那几场｜句数。点了进「那几场」
struct SceneChatMessageCard: View {
    let card: SceneChatCard
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""

    var body: some View {
        let sk: SceneInk = { _ = houseAppearance; return SceneInk(dark: AlcoveAppearance.isDark) }()
        return Button {
            NotificationCenter.default.post(name: .alcoveOpenScenes, object: card.no)
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(sk.veil)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(sk.dark ? 0.1 : 0.95), lineWidth: 0.8))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(sk.stitch, style: StrokeStyle(lineWidth: 1, dash: [4, 3])).padding(6).opacity(0.7))
                    .shadow(color: sk.shadow.opacity(0.7), radius: 12, y: 8)
                    .frame(width: 290, height: 120)
                photo(sk)
                    .rotationEffect(.degrees(-6))
                    .offset(x: 16, y: -8)
                slip(sk)
                    .rotationEffect(.degrees(2))
                    .offset(x: 104, y: 13)
            }
            .frame(width: 290, height: 120, alignment: .topLeading)
            .padding(.top, 10)
        }
        .buttonStyle(.plain)
    }

    private func photo(_ sk: SceneInk) -> some View {
        Image("SceneFlower")   // #5593 她：图片换成花的（/root/rhysel/flower_6.png 淡紫小花，只裁开花那一簇）
            .resizable().scaledToFill()
            .frame(width: 80, height: 86).clipped()
            .opacity(sk.artOpacity)
            .padding(.horizontal, 6).padding(.top, 6).padding(.bottom, 14)
            .background(ScallopEdgeShape(bump: 6, depth: 2).fill(sk.paper))
            .shadow(color: Color.black.opacity(sk.dark ? 0.4 : 0.13), radius: 7, y: 5)
    }

    private func slip(_ sk: SceneInk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("ours").font(SanctusPageFont.script(15)).foregroundColor(sk.rose)
                Spacer()
                Text(SceneRoomStore.md(card.day ?? "")).font(SceneFont.mono(9.5)).foregroundColor(sk.mono)
            }
            .frame(height: 14)
            Text(card.title).font(SceneFont.serif(15)).tracking(0.9).foregroundColor(sk.ink)
                .lineLimit(1).padding(.top, 4)
            if let n = card.note, !n.isEmpty {
                Text(n).font(SceneFont.serif(11)).foregroundColor(sk.body).lineLimit(1).padding(.top, 3)
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "Nº %02d", card.no)).font(SceneFont.mono(9)) + Text(" · 收进那几场").font(SceneFont.serif(9))
                Spacer()
                Text("\(card.count ?? 0)").font(SceneFont.mono(9)) + Text(" 句").font(SceneFont.serif(9))
            }
            .foregroundColor(sk.mono).lineLimit(1)
            .padding(.bottom, 9)
        }
        .padding(.leading, 14).padding(.trailing, 12).padding(.top, 10)
        .frame(width: 170, height: 94, alignment: .topLeading)
        .background(sk.paper)
        .shadow(color: Color.black.opacity(sk.dark ? 0.4 : 0.10), radius: 7, y: 5)
        .overlay(alignment: .topLeading) {
            TornTapeShape(tooth: 5, depth: 4)
                .fill(Color.white.opacity(sk.dark ? 0.16 : 0.72))
                .overlay(TornTapeShape(tooth: 5, depth: 4).stroke(sk.hair, lineWidth: 0.5))
                .frame(width: 52, height: 15)
                .rotationEffect(.degrees(-4))
                .offset(x: 58, y: -8)
        }
    }
}

// MARK: 画出来的小零件

/// 一根横线（给 stroke 用）
fileprivate struct SceneRule: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); return p
    }
}

/// 相纸：上下两条边是一排小扇贝
fileprivate struct ScallopEdgeShape: Shape {
    var bump: CGFloat
    var depth: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        let n = max(1, Int((r.width / bump).rounded()))
        let s = r.width / CGFloat(n)
        p.move(to: CGPoint(x: r.minX, y: r.minY + depth))
        for i in 0..<n {
            let x = r.minX + CGFloat(i) * s
            p.addQuadCurve(to: CGPoint(x: x + s, y: r.minY + depth), control: CGPoint(x: x + s / 2, y: r.minY - depth))
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - depth))
        for i in 0..<n {
            let x = r.maxX - CGFloat(i) * s
            p.addQuadCurve(to: CGPoint(x: x - s, y: r.maxY - depth), control: CGPoint(x: x - s / 2, y: r.maxY + depth))
        }
        p.closeSubpath()
        return p
    }
}

/// 前袋：上沿扇贝、下面两个圆角
fileprivate struct ScallopTopShape: Shape {
    var bump: CGFloat
    var depth: CGFloat
    var radius: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        let n = max(1, Int((r.width / bump).rounded()))
        let s = r.width / CGFloat(n)
        p.move(to: CGPoint(x: r.minX, y: r.minY + depth))
        for i in 0..<n {
            let x = r.minX + CGFloat(i) * s
            p.addQuadCurve(to: CGPoint(x: x + s, y: r.minY + depth), control: CGPoint(x: x + s / 2, y: r.minY - depth))
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// 行李牌：左边两个角切掉
fileprivate struct TagShape: Shape {
    var cut: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + cut, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + cut, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - cut))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + cut))
        p.closeSubpath()
        return p
    }
}

/// 扇贝边圆贴纸
fileprivate struct ScallopCircleShape: Shape {
    var bumps: Int
    var depth: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        let R = min(r.width, r.height) / 2
        let steps = bumps * 8
        for i in 0...steps {
            let a = 2 * Double.pi * Double(i) / Double(steps)
            let rr = R - depth + depth * CGFloat(abs(cos(Double(bumps) * a / 2)))
            let pt = CGPoint(x: c.x + rr * CGFloat(cos(a)), y: c.y + rr * CGFloat(sin(a)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// 下沿撕开的锯齿
fileprivate struct TornBottomShape: Shape {
    var tooth: CGFloat
    var depth: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - depth))
        let n = max(1, Int((r.width / tooth).rounded()))
        let s = r.width / CGFloat(n)
        for i in 0..<n {
            let x = r.maxX - CGFloat(i) * s
            p.addLine(to: CGPoint(x: x - s / 2, y: r.maxY))
            p.addLine(to: CGPoint(x: x - s, y: r.maxY - depth))
        }
        p.closeSubpath()
        return p
    }
}

/// 两头撕毛了的胶带
fileprivate struct TornTapeShape: Shape {
    var tooth: CGFloat
    var depth: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        let n = max(1, Int((r.height / tooth).rounded()))
        let s = r.height / CGFloat(n)
        p.move(to: CGPoint(x: r.minX + depth, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - depth, y: r.minY))
        for i in 0..<n {
            let y = r.minY + CGFloat(i) * s
            p.addLine(to: CGPoint(x: r.maxX, y: y + s / 2))
            p.addLine(to: CGPoint(x: r.maxX - depth, y: y + s))
        }
        p.addLine(to: CGPoint(x: r.minX + depth, y: r.maxY))
        for i in 0..<n {
            let y = r.maxY - CGFloat(i) * s
            p.addLine(to: CGPoint(x: r.minX, y: y - s / 2))
            p.addLine(to: CGPoint(x: r.minX + depth, y: y - s))
        }
        p.closeSubpath()
        return p
    }
}

/// 心形回形针（22×40 画的，按框缩放）
fileprivate struct HeartClipShape: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 22, sy = r.height / 40
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * sx, y: r.minY + y * sy) }
        var p = Path()
        p.move(to: pt(11, 38))
        p.addCurve(to: pt(6, 18), control1: pt(2, 30), control2: pt(2, 22))
        p.addCurve(to: pt(11, 19), control1: pt(9, 15), control2: pt(11, 17))
        p.addCurve(to: pt(16, 18), control1: pt(11, 17), control2: pt(13, 15))
        p.addCurve(to: pt(11, 38), control1: pt(20, 22), control2: pt(20, 30))
        p.move(to: pt(11, 34))
        p.addCurve(to: pt(7.5, 21), control1: pt(5, 28), control2: pt(5, 23))
        p.addCurve(to: pt(11, 22.5), control1: pt(9.5, 19.5), control2: pt(11, 21))
        p.addLine(to: pt(11, 2))
        return p
    }
}

/// 一圈绕着走的小字
fileprivate struct ArcText: View {
    let text: String
    let radius: CGFloat
    let size: CGFloat
    let color: Color
    var body: some View {
        let chars = Array(text)
        let step = 360.0 / Double(max(chars.count, 1))
        return ZStack {
            ForEach(Array(chars.enumerated()), id: \.offset) { i, ch in
                Text(String(ch)).font(SanctusPageFont.corm(size)).foregroundColor(color)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(Double(i) * step))
            }
        }
    }
}
