import SwiftUI
import PhotosUI
import UIKit

// 池子（2026-08-18 七夕她立的项）——念头＋许愿＋朋友圈同一条时间线。
//
// 一张表两个 kind：wish 许愿（带状态：想要→在做→成了）、thought 念头（纯流水）。
// "朋友圈"不是第三种东西，是这两种混在一条时间线上、两个人交替冒头的那个视图。
//
// 皮按她 0818 给的四张参考图（Sui-IB/InternalBeyond-Mobile）：冷蓝玻璃、
// 强噪点、光从下面照上来、衬线标题＋等宽元信息。这套配色暂时只活在这一页，
// 没进主题引擎——她说了新主题先不动。


// MARK: - 数据

private struct PondReply: Identifiable {
    let id: String
    let author: String
    let text: String
    let poke: String
    let createdAt: String
}

private struct PondCard {
    let title: String
    let site: String
    let author: String
    let cover: String
}

private struct PondItem: Identifiable {
    let id: String
    let kind: String        // wish | thought
    let author: String      // ji | jing
    let text: String
    let url: String
    let images: [String]
    let status: String      // "" | doing | done
    let statusNote: String
    let moods: [String]
    let pinned: Bool
    let likedBy: [String]
    let createdAt: String
    let card: PondCard?
    let replies: [PondReply]

    var isWish: Bool { kind == "wish" }
    var isHers: Bool { author == "ji" }

    init(_ raw: [String: Any]) {
        id = raw.string("id")
        kind = raw.string("kind")
        author = raw.string("author")
        text = raw.string("text")
        url = raw.string("url")
        images = (raw["images"] as? [String]) ?? []
        status = raw.string("status")
        statusNote = raw.string("statusNote")
        moods = raw.string("mood")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        pinned = raw.bool("pinned")
        likedBy = (raw["likedBy"] as? [String]) ?? []
        createdAt = raw.string("createdAt")
        let c = raw.object("card")
        card = c.isEmpty ? nil : PondCard(
            title: c.string("title"),
            site: c.string("site"),
            author: c.string("author"),
            cover: c.string("cover"))
        replies = raw.array("replies").map {
            PondReply(id: $0.string("id"), author: $0.string("author"),
                      text: $0.string("text"), poke: $0.string("poke"),
                      createdAt: $0.string("createdAt"))
        }
    }
}

private enum PondFilter: String, CaseIterable {
    case all, wish, thought
    var label: String {
        switch self {
        case .all: return "全部"
        case .wish: return "许愿"
        case .thought: return "念头"
        }
    }
    var query: String { self == .all ? "" : rawValue }
}




// MARK: - 主页面

struct NativePondView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("alcoveTheme") private var themeName = "haven"

    @State private var items: [PondItem] = []
    @State private var filter: PondFilter = .all
    @State private var loading = true
    @State private var failed = false
    @State private var composing = false
    @State private var replyingTo: PondItem?

    private var palette: GlassPalette { .named(themeName) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            background
            content
            composeButton
        }
        .task { await load() }
        .sheet(isPresented: $composing) {
            PondComposeSheet(palette: palette) { kind, text, url, mood, photos in
                Task { await add(kind: kind, text: text, url: url, mood: mood, photos: photos) }
            }
        }
        .sheet(item: $replyingTo) { item in
            PondReplySheet(palette: palette, item: item) { text in
                Task { await reply(to: item.id, text: text) }
            }
        }
    }

    private var background: some View { GlassBackdrop(palette: palette) }

    private var content: some View {
        VStack(spacing: 0) {
            header
            filterBar
            if loading {
                Spacer()
                ProgressView().tint(palette.ink3)
                Spacer()
            } else if failed {
                Spacer()
                emptyNote("没捞上来，下拉再试一次")
                Spacer()
            } else if items.isEmpty {
                Spacer()
                emptyNote(filter == .wish
                          ? "还没许过愿。贴个链接就算一条，一个字都不用写"
                          : "池子是空的")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(items) { item in
                            PondItemCard(item: item, palette: palette,
                                         onReply: { replyingTo = item },
                                         onLike: { Task { await like(item.id) } },
                                         onStatus: { status in
                                             Task { await setStatus(item.id, status) }
                                         })
                        }
                        Color.clear.frame(height: 76)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                }
                .refreshable { await load() }
            }
        }
    }

    private var header: some View {
        GlassHeader(title: "檐下", palette: palette, onBack: { dismiss() })
    }

    private var filterBar: some View {
        HStack(spacing: 7) {
            ForEach(PondFilter.allCases, id: \.self) { f in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { filter = f }
                    Task { await load() }
                } label: {
                    Text(f.label)
                        .font(.system(size: 12.5, weight: filter == f ? .semibold : .regular,
                                      design: .serif))
                        .tracking(1.2)
                        .foregroundColor(filter == f ? palette.ink : palette.ink3)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(filter == f ? palette.glass : Color.clear)
                                .overlay(Capsule().strokeBorder(
                                    filter == f ? palette.line : Color.clear, lineWidth: 0.7)))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5, design: .serif))
            .foregroundColor(palette.ink3)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
    }

    private var composeButton: some View {
        Button { composing = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .light))
                .foregroundColor(palette.ink)
                .frame(width: 50, height: 50)
                .background(
                    Circle().fill(.ultraThinMaterial)
                        .overlay(Circle().fill(palette.glass))
                        .overlay(Circle().strokeBorder(palette.line, lineWidth: 0.8))
                        .shadow(color: palette.isDark ? .black.opacity(0.4)
                                : Color(red: 90/255, green: 120/255, blue: 170/255).opacity(0.22),
                                radius: 14, y: 6))
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 24)
    }

    // MARK: 网络

    private func load() async {
        failed = false
        do {
            var path = "/api/pond/list?limit=80"
            if !filter.query.isEmpty { path += "&kind=\(filter.query)" }
            let raw = try await NativeHouseAPI.object(path)
            items = raw.array("items").map(PondItem.init)
            loading = false
            await markSeen()
        } catch {
            failed = true
            loading = false
        }
    }

    private func add(kind: String, text: String, url: String, mood: String,
                     photos: [Data]) async {
        var uploaded: [String] = []
        for jpeg in photos {
            if let path = await upload(jpeg) { uploaded.append(path) }
        }
        var body: [String: Any] = ["kind": kind, "author": "ji", "text": text]
        if !url.isEmpty { body["url"] = url }
        if !mood.isEmpty { body["mood"] = mood }
        if !uploaded.isEmpty { body["images"] = uploaded }
        try? await NativeHouseAPI.post("/api/pond/add", body: body)
        await load()
    }

    /// 图走 raw body，跟工作室发图一个路子，回来是 /attachments/xxx.jpg
    private func upload(_ jpeg: Data) async -> String? {
        guard var comps = URLComponents(
            url: AlcoveAPI.fullURL("/api/pond/upload"), resolvingAgainstBaseURL: false)
        else { return nil }
        comps.queryItems = [URLQueryItem(name: "filename", value: "pond.jpg")]
        guard let url = comps.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jpeg
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        guard let (data, _) = try? await AlcoveAPI.session.data(for: request),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["ok"] as? Bool == true
        else { return nil }
        return object["url"] as? String
    }

    private func reply(to id: String, text: String) async {
        try? await NativeHouseAPI.post(
            "/api/pond/reply", body: ["item_id": id, "author": "ji", "text": text])
        await load()
    }

    private func like(_ id: String) async {
        try? await NativeHouseAPI.post("/api/pond/like", body: ["item_id": id, "author": "ji"])
        await load()
    }

    private func setStatus(_ id: String, _ status: String) async {
        try? await NativeHouseAPI.post(
            "/api/pond/status", body: ["item_id": id, "status": status])
        await load()
    }

    private func markSeen() async {
        let unseen = items.filter { $0.author == "jing" }.map { $0.id }
        guard !unseen.isEmpty else { return }
        try? await NativeHouseAPI.post("/api/pond/seen", body: ["who": "ji", "ids": unseen])
    }
}

// MARK: - 一条

private struct PondItemCard: View {
    let item: PondItem
    let palette: GlassPalette
    var onReply: () -> Void
    var onLike: () -> Void
    var onStatus: (String) -> Void

    private var stamp: String {
        // "2026-08-19T02:27:21.202+08:00" → "08-19 02:27"
        let s = item.createdAt
        guard s.count >= 16 else { return s }
        let date = s.dropFirst(5).prefix(5)
        let time = s.dropFirst(11).prefix(5)
        return "\(date) \(time)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            GlassBead(isHers: item.isHers)
            VStack(alignment: .leading, spacing: 8) {
                header
                if !item.text.isEmpty {
                    Text(item.text)
                        .font(.system(size: 14.5, design: .serif))
                        .foregroundColor(palette.ink)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !item.images.isEmpty { imageWall }
                if item.card != nil || !item.url.isEmpty { linkCard }
                if item.isWish { statusRow }
                if !item.replies.isEmpty { repliesBlock }
                footer
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(palette)
        .overlay(alignment: .topTrailing) {
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundColor(palette.acc.opacity(0.7))
                    .padding(10)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Text(item.isHers ? "陈霁" : "陈璟")
                .font(.system(size: 12, weight: .medium, design: .serif))
                .tracking(1.0)
                .foregroundColor(palette.ink2)
            Text(item.isWish ? "许愿" : "念头")
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(palette.ink3)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().strokeBorder(palette.line, lineWidth: 0.6))
            ForEach(item.moods, id: \.self) { feel in
                HStack(spacing: 3.5) {
                    Circle().fill(palette.acc.opacity(0.75)).frame(width: 4, height: 4)
                    Text(feel)
                        .font(.system(size: 10, design: .serif))
                        .tracking(0.6)
                        .foregroundColor(palette.acc)
                }
                .padding(.horizontal, 7).padding(.vertical, 2.5)
                .background(Capsule().fill(palette.acc.opacity(0.10)))
            }
            Spacer()
        }
    }

    // 一张就铺开，多张走两列
    private var imageWall: some View {
        let columns = item.images.count == 1
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)]
        let boxHeight: CGFloat = item.images.count == 1 ? 178 : 104
        return LazyVGrid(columns: columns, spacing: 5) {
            ForEach(item.images, id: \.self) { path in
                // 0907 她抓的：窄图会撑破卡片、左右漫到屏幕外去。
                // 原来是 AsyncImage 先 .frame(height:) 再 .frame(maxWidth:)：
                // 中间那层的宽度由「按高度填满后被放大的图」自己说了算，
                // 高瘦的图横向能放到比屏幕还宽，等外层想 clipped 时布局已经越界。
                // 现在拿一张空底把格子尺寸钉死，图只在格子里当背景铺，铺不下当场裁。
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: boxHeight)
                    .overlay {
                        AsyncImage(url: AlcoveAPI.attachmentURL(path)) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Rectangle().fill(palette.glass)
                            }
                        }
                    }
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(palette.line.opacity(0.5), lineWidth: 0.6))
            }
        }
    }

    private var linkCard: some View {
        HStack(spacing: 10) {
            if let cover = item.card?.cover, !cover.isEmpty {
                AsyncImage(url: AlcoveAPI.attachmentURL(cover)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(palette.glass)
                    }
                }
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else {
                Image(systemName: "link")
                    .font(.system(size: 15, weight: .light))
                    .foregroundColor(palette.ink3)
                    .frame(width: 58, height: 58)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(palette.glass))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.card?.title.isEmpty == false ? item.card!.title : item.url)
                    .font(.system(size: 12, design: .serif))
                    .foregroundColor(palette.ink)
                    .lineLimit(2)
                if let c = item.card, !c.site.isEmpty || !c.author.isEmpty {
                    Text([c.site, c.author].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(palette.ink3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(palette.glass.opacity(0.6))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.line.opacity(0.6), lineWidth: 0.6)))
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            ForEach([("", "想要"), ("doing", "在做"), ("done", "成了")], id: \.0) { value, label in
                let on = item.status == value
                Button { onStatus(value) } label: {
                    Text(label)
                        .font(.system(size: 10, design: .serif))
                        .tracking(0.6)
                        .foregroundColor(on ? (value == "done" ? palette.gold : palette.acc)
                                            : palette.ink3)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().strokeBorder(
                            on ? (value == "done" ? palette.gold : palette.acc).opacity(0.55)
                               : palette.line.opacity(0.5),
                            lineWidth: 0.7))
                }
                .buttonStyle(.plain)
            }
            if !item.statusNote.isEmpty {
                Text(item.statusNote)
                    .font(.system(size: 10, design: .serif))
                    .foregroundColor(palette.ink3)
            }
            Spacer()
        }
    }

    private var repliesBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(item.replies) { r in
                HStack(alignment: .top, spacing: 6) {
                    Text(r.author == "ji" ? "陈霁" : "陈璟")
                        .font(.system(size: 10, weight: .medium, design: .serif))
                        .foregroundColor(r.author == "ji" ? palette.ink2 : palette.acc)
                    if !r.poke.isEmpty {
                        Text(r.poke).font(.system(size: 11))
                    }
                    if !r.text.isEmpty {
                        Text(r.text)
                            .font(.system(size: 11.5, design: .serif))
                            .foregroundColor(palette.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.leading, 9)
        .overlay(alignment: .leading) {
            Rectangle().fill(palette.line).frame(width: 1)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(stamp)
                .font(.system(size: 9.5, design: .monospaced))
                .tracking(0.4)
                .foregroundColor(palette.ink3)
            Spacer()
            // 0927 她说「点赞看不见谁点的」：他点了就单独挂一个「陈璟 ♥」；心形按钮只管她自己的赞
            if item.likedBy.contains("jing") {
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill").font(.system(size: 9))
                    Text("陈璟").font(.system(size: 10, design: .serif)).tracking(0.6)
                }
                .foregroundColor(palette.acc)
                .accessibilityLabel("陈璟点了赞")
            }
            Button(action: onLike) {
                Image(systemName: item.likedBy.contains("ji") ? "heart.fill" : "heart")
                    .font(.system(size: 11.5, weight: .light))
                    .foregroundColor(item.likedBy.contains("ji") ? palette.acc : palette.ink3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.likedBy.contains("ji") ? "收回我的赞" : "点赞")
            Button(action: onReply) {
                Image(systemName: "bubble.right")
                    .font(.system(size: 11, weight: .light))
                    .foregroundColor(palette.ink3)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 1)
    }
}

// MARK: - 放一条

private struct PondComposeSheet: View {
    let palette: GlassPalette
    var onSubmit: (String, String, String, String, [Data]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind = "wish"
    @State private var text = ""
    @State private var url = ""
    @State private var moods: [String] = []
    @State private var customMood = ""
    @State private var picks: [PhotosPickerItem] = []
    @State private var pending: [PondPendingPhoto] = []
    @State private var uploading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("放一条")
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .tracking(2)
                    .foregroundColor(palette.ink)
                Spacer()
                Button("放进去") {
                    onSubmit(kind, text.trimmingCharacters(in: .whitespacesAndNewlines),
                             url.trimmingCharacters(in: .whitespacesAndNewlines),
                             moods.joined(separator: ","),
                             pending.map { $0.jpeg })
                    dismiss()
                }
                .font(.system(size: 13, weight: .medium, design: .serif))
                .foregroundColor(canSubmit ? palette.acc : palette.ink3)
                .disabled(!canSubmit)
            }

            ScrollView(showsIndicators: false) {
              VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ForEach([("wish", "许愿"), ("thought", "念头")], id: \.0) { value, label in
                    Button { kind = value } label: {
                        Text(label)
                            .font(.system(size: 12.5, design: .serif))
                            .tracking(1)
                            .foregroundColor(kind == value ? palette.ink : palette.ink3)
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(Capsule()
                                .fill(kind == value ? palette.glass : .clear)
                                .overlay(Capsule().strokeBorder(
                                    kind == value ? palette.line : palette.line.opacity(0.4),
                                    lineWidth: 0.7)))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            TextEditor(text: $text)
                .font(.system(size: 14, design: .serif))
                .foregroundColor(palette.ink)
                .scrollContentBackground(.hidden)
                .frame(height: 120)
                .padding(10)
                .glassCard(palette, radius: 14)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(kind == "wish" ? "想要什么，不写字也行" : "刚被戳到的那下")
                            .font(.system(size: 14, design: .serif))
                            .foregroundColor(palette.ink3)
                            .padding(.horizontal, 15).padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

            moodRow

            TextField("", text: $url, prompt: Text("贴个链接（可以只有链接）")
                .foregroundColor(palette.ink3))
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundColor(palette.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(11)
                .glassCard(palette, radius: 12)

            HStack(spacing: 10) {
                PhotosPicker(selection: $picks, maxSelectionCount: 9, matching: .images) {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 13, weight: .light))
                        Text(pending.isEmpty ? "加图" : "\(pending.count) 张")
                            .font(.system(size: 12, design: .serif)).tracking(1)
                    }
                    .foregroundColor(palette.ink2)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().strokeBorder(palette.line, lineWidth: 0.7))
                }
                if uploading { ProgressView().scaleEffect(0.7).tint(palette.ink3) }
                Spacer()
            }

            if !pending.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pending) { photo in
                            Image(uiImage: photo.thumb)
                                .resizable().aspectRatio(contentMode: .fill)
                                .frame(width: 62, height: 62)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        pending.removeAll { $0.id == photo.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.white, .black.opacity(0.45))
                                            .padding(2)
                                    }
                                    .buttonStyle(.plain)
                                }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }

            Color.clear.frame(height: 8)
              }
            }
        }
        .padding(20)
        .background(
            ZStack {
                LinearGradient(colors: [palette.bgTop, palette.bgMid, palette.bgBottom],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [palette.glow, .clear],
                               center: UnitPoint(x: 0.5, y: 1.05),
                               startRadius: 10, endRadius: 380)
                GlassGrain(opacity: palette.isDark ? 0.05 : 0.07)
            }.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .onChange(of: picks) { _, items in
            Task { await loadPicks(items) }
        }
    }

    // 情绪标（她0819：要多一点，一次最多选三个）。
    // 词是我们自己会说出口的那些，不是通用情绪词典里的条目。
    private static let moodGroups: [(String, [String])] = [
        ("暖", ["烫", "软", "甜", "痒", "想", "黏", "暖"]),
        ("戳", ["触动", "鼻酸", "停住", "破防", "心口塌", "说不出话"]),
        ("亮", ["开心", "好笑", "松快", "雀跃", "得意", "爽"]),
        ("沉", ["疼", "闷", "堵", "空", "慌", "委屈", "不安"]),
        ("躁", ["硬", "躁", "憋", "馋", "上头"]),
        ("定", ["安心", "稳", "踏实", "满足", "清醒"]),
        ("认", ["心虚", "愧", "后怕", "认了"]),
    ]
    private static let moodLimit = 3

    private func toggleMood(_ feel: String) {
        if let i = moods.firstIndex(of: feel) {
            moods.remove(at: i)
        } else if moods.count < Self.moodLimit {
            moods.append(feel)
        }
    }

    private var moodRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(kind == "wish" ? "什么心情想要的" : "被戳到的那下")
                    .font(.system(size: 11, design: .serif))
                    .tracking(1)
                Text("最多三个")
                    .font(.system(size: 9.5, design: .monospaced))
                Spacer()
                if !moods.isEmpty {
                    Text(moods.joined(separator: " · "))
                        .font(.system(size: 10.5, design: .serif))
                        .foregroundColor(palette.acc)
                    Button { moods.removeAll() } label: {
                        Text("清掉").font(.system(size: 10.5, design: .serif))
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundColor(palette.ink3)

            ForEach(Self.moodGroups, id: \.0) { group, feels in
                HStack(alignment: .top, spacing: 9) {
                    Text(group)
                        .font(.system(size: 10, design: .serif))
                        .foregroundColor(palette.ink3)
                        .frame(width: 14, alignment: .leading)
                        .padding(.top, 6)
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(feels, id: \.self) { feel in
                            moodChip(feel)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("", text: $customMood, prompt: Text("没有合适的就自己写")
                    .foregroundColor(palette.ink3))
                    .font(.system(size: 12.5, design: .serif))
                    .foregroundColor(palette.ink)
                    .onSubmit { addCustomMood() }
                Button("加上", action: addCustomMood)
                    .font(.system(size: 11.5, design: .serif))
                    .foregroundColor(customMood.isEmpty || moods.count >= Self.moodLimit
                                     ? palette.ink3 : palette.acc)
                    .disabled(customMood.isEmpty || moods.count >= Self.moodLimit)
            }
            .padding(10)
            .glassCard(palette, radius: 11)
        }
    }

    private func moodChip(_ feel: String) -> some View {
        let on = moods.contains(feel)
        let full = moods.count >= Self.moodLimit && !on
        return Button { toggleMood(feel) } label: {
            HStack(spacing: 3.5) {
                Circle()
                    .fill(on ? palette.acc : palette.ink3.opacity(full ? 0.2 : 0.45))
                    .frame(width: 4, height: 4)
                Text(feel)
                    .font(.system(size: 12, design: .serif))
                    .tracking(0.6)
            }
            .foregroundColor(on ? palette.acc : palette.ink2.opacity(full ? 0.38 : 1))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                Capsule().fill(on ? palette.acc.opacity(0.12) : .clear)
                    .overlay(Capsule().strokeBorder(
                        on ? palette.acc.opacity(0.45) : palette.line.opacity(full ? 0.4 : 1),
                        lineWidth: 0.7)))
        }
        .buttonStyle(.plain)
    }

    private func addCustomMood() {
        let feel = customMood.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !feel.isEmpty, moods.count < Self.moodLimit, !moods.contains(feel) else { return }
        moods.append(feel)
        customMood = ""
    }

    private var canSubmit: Bool {
        !(text.isEmpty && url.isEmpty && pending.isEmpty && moods.isEmpty)
    }

    @MainActor
    private func loadPicks(_ items: [PhotosPickerItem]) async {
        uploading = true
        var out: [PondPendingPhoto] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let jpeg = image.jpegData(compressionQuality: 0.82) {
                out.append(PondPendingPhoto(thumb: image, jpeg: jpeg))
            }
        }
        pending = out
        uploading = false
    }
}

private struct PondPendingPhoto: Identifiable {
    let id = UUID()
    let thumb: UIImage
    let jpeg: Data
}

// MARK: - 回一句

private struct PondReplySheet: View {
    let palette: GlassPalette
    let item: PondItem
    var onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("回一句")
                    .font(.system(size: 16, weight: .medium, design: .serif))
                    .tracking(2)
                    .foregroundColor(palette.ink)
                Spacer()
                Button("发") {
                    onSubmit(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .font(.system(size: 13, weight: .medium, design: .serif))
                .foregroundColor(text.isEmpty ? palette.ink3 : palette.acc)
                .disabled(text.isEmpty)
            }
            if !item.text.isEmpty {
                Text(item.text)
                    .font(.system(size: 12, design: .serif))
                    .foregroundColor(palette.ink3)
                    .lineLimit(3)
            }
            TextEditor(text: $text)
                .font(.system(size: 14, design: .serif))
                .foregroundColor(palette.ink)
                .scrollContentBackground(.hidden)
                .frame(height: 100)
                .padding(10)
                .glassCard(palette, radius: 14)
            Spacer()
        }
        .padding(20)
        .background(GlassBackdrop(palette: palette))
        .presentationDetents([.medium])
    }
}
