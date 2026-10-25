import SwiftUI
import PhotosUI
import UIKit

// 池子（2026-08-18 七夕她立的项）——念头＋许愿＋朋友圈同一条时间线。
//
// 一张表两个 kind：wish 许愿（带状态：想要→在做→成了）、thought 念头（纯流水）。
// "朋友圈"不是第三种东西，是这两种混在一条时间线上、两个人交替冒头的那个视图。
//
// 1025 #4323 起主页面换成朋友圈的样子、Sanctus 配色（见「主页面」那段注释）；
// 放一条 / 回一句两个弹层还是 0818 的冷蓝玻璃皮（GlassPalette），没动。


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

// 1025 #4323–4325 她：「檐下布局改成朋友圈的感觉」，效果图 /root/rhysel/sanctus-kit/mock-moments/mock.html
// 她点头：「可以 颜色有点黄了 稍微偏白一点点就行 其他的没问题」「黑夜版换那个人脸闭眼那张图在上面去」。
// - 顶上一张封面（白天天使壁纸 PondCoverDay，黑夜人脸闭眼那张 HealthPortrait），往下化进底色；
//   右下两个方头像（聊天页设的那两张）＋花体 under the eaves；左上返回、右上加号＝放一条（原来右下的圆按钮去掉）。
// - 每条平铺不装卡：左方头像，右边名字、正文、图（一张放大、多张三个一排方格）、链接、许愿状态，
//   一行时间＋许愿/念头＋心情，最右「··」点开「赞 / 评论」；赞和回复收在底下浅色小框里。
// - 底色比 Sanctus 页面再白一点（F4F5F7），深浅只认全屋按钮。

private struct PondInk {
    let dark: Bool
    private func rgb(_ hex: Int, _ a: Double = 1) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: a)
    }
    var page: Color { dark ? rgb(0x1B1C20) : rgb(0xF4F5F7) }
    var ink: Color { dark ? rgb(0xE4E4E7) : rgb(0x2A2A2E) }
    var body: Color { dark ? rgb(0xE3E4E8) : rgb(0x3E4048) }
    var name: Color { dark ? rgb(0xAEB3BF) : rgb(0x5E6474) }
    var script: Color { dark ? rgb(0xC3C6CE) : rgb(0x6F7480) }
    var sub: Color { dark ? rgb(0x8B8F99) : rgb(0x9A9EA8) }
    var link: Color { dark ? rgb(0xA3A7B0) : rgb(0x7D818C) }
    var hair: Color { dark ? Color.white.opacity(0.14) : rgb(0x969AA4, 0.45) }
    var frame: Color { dark ? Color.white.opacity(0.08) : rgb(0x969AA4, 0.22) }
    var box: Color { dark ? Color.white.opacity(0.05) : Color.white.opacity(0.66) }
    var dots: Color { dark ? Color.white.opacity(0.08) : rgb(0x969AA4, 0.16) }
    var menu: Color { dark ? rgb(0x3A3B42) : rgb(0x3E4048) }
    var blue: Color { dark ? rgb(0x3A55FF) : rgb(0x0B1BFF) }
    var avatarEdge: Color { dark ? Color.white.opacity(0.18) : Color.white }
}

/// 头像：跟聊天页同一份（设置里换的那两张）；没设就一个字
private struct PondAvatar: View {
    let isHers: Bool
    var size: CGFloat = 40
    var radius: CGFloat = 8
    @AppStorage("userAvatarDataURL") private var userAvatar = ""
    @AppStorage("assistantAvatarDataURL") private var assistantAvatar = ""

    private static var cache: [Int: UIImage] = [:]
    private static func decode(_ value: String) -> UIImage? {
        guard !value.isEmpty else { return nil }
        let key = value.hashValue
        if let hit = cache[key] { return hit }
        let payload = value.split(separator: ",", maxSplits: 1).last.map(String.init) ?? value
        guard let img = Data(base64Encoded: payload).flatMap(UIImage.init(data:)) else { return nil }
        cache[key] = img
        return img
    }

    var body: some View {
        Group {
            if let img = Self.decode(isHers ? userAvatar : assistantAvatar) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Color(red: isHers ? 0xB9 / 255 : 0x8E / 255, green: isHers ? 0xBD / 255 : 0x93 / 255,
                          blue: isHers ? 0xC6 / 255 : 0xA0 / 255)
                    Text(isHers ? "霁" : "璟").font(.system(size: size * 0.38, design: .serif)).foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct NativePondView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""

    @State private var items: [PondItem] = []
    @State private var filter: PondFilter = .all
    @State private var loading = true
    @State private var failed = false
    @State private var composing = false
    @State private var replyingTo: PondItem?
    @State private var menuFor: String?

    private var palette: GlassPalette { .named(themeName) }
    private var ink: PondInk { _ = houseAppearance; return PondInk(dark: AlcoveAppearance.isDark) }
    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0 }
    private var safeBottom: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.bottom ?? 0 }

    var body: some View {
        let ink = self.ink
        ZStack(alignment: .top) {
            ink.page.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    cover(ink)
                    subBar(ink)
                    content(ink)
                    Color.clear.frame(height: safeBottom + 30)
                }
            }
            .ignoresSafeArea(edges: .top)
            .refreshable { await load() }
            topButtons(ink)
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

    // MARK: 封面

    private func cover(_ ink: PondInk) -> some View {
        let h: CGFloat = 300
        return ZStack(alignment: .bottomTrailing) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: h)
                .overlay {
                    Image(ink.dark ? "HealthPortrait" : "PondCoverDay")
                        .resizable().scaledToFill()
                        .brightness(ink.dark ? -0.08 : 0)
                }
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [ink.page.opacity(0), ink.page], startPoint: .top, endPoint: .bottom)
                        .frame(height: 90)
                }
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .trailing, spacing: 6) {
                    Text("under the eaves").font(SanctusPageFont.script(31)).foregroundColor(ink.ink)
                    Text("ji & jing, side by side").font(SanctusPageFont.ital(11)).foregroundColor(ink.script)
                }
                .padding(.bottom, 26)
                ZStack(alignment: .bottomLeading) {
                    PondAvatar(isHers: true, size: 56, radius: 10)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(ink.avatarEdge, lineWidth: 2))
                    PondAvatar(isHers: false, size: 56, radius: 10)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(ink.avatarEdge, lineWidth: 2))
                        .offset(x: 40, y: -10)
                }
                .frame(width: 96, height: 66, alignment: .bottomLeading)
            }
            .padding(.trailing, 16)
            .offset(y: 20)
        }
        .zIndex(1)
    }

    private func topButtons(_ ink: PondInk) -> some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .regular))
                    .foregroundColor(ink.script)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
            .accessibilityLabel("返回")
            Spacer()
            Button { composing = true } label: {
                Image(systemName: "plus").font(.system(size: 14, weight: .light))
                    .foregroundColor(ink.script)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(ink.dark ? Color.black.opacity(0.25) : Color.white.opacity(0.55)))
                    .overlay(Circle().stroke(ink.script.opacity(0.6), lineWidth: 0.8))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 9)
            .accessibilityLabel("放一条")
        }
        .padding(.top, safeTop)
    }

    // MARK: 封面下面一行：眉标＋全部/许愿/念头

    private func subBar(_ ink: PondInk) -> some View {
        HStack(alignment: .firstTextBaseline) {
            (Text("ON THE EAVES · ").font(SanctusPageFont.corm(8)) + Text("檐下").font(.system(size: 8, design: .serif)))
                .tracking(2.4).foregroundColor(ink.sub)
            Spacer()
            HStack(spacing: 16) {
                ForEach(PondFilter.allCases, id: \.self) { f in
                    Button {
                        filter = f
                        menuFor = nil
                        Task { await load() }
                    } label: {
                        Text(f.label).font(.system(size: 11.5, design: .serif)).tracking(2.3)
                            .foregroundColor(filter == f ? ink.ink : ink.sub)
                            .padding(.bottom, 3)
                            .overlay(alignment: .bottom) {
                                if filter == f { Rectangle().fill(ink.ink).frame(height: 0.8) }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 30)
        .padding(.bottom, 4)
    }

    @ViewBuilder private func content(_ ink: PondInk) -> some View {
        if loading {
            ProgressView().tint(ink.sub).padding(.top, 50)
        } else if failed {
            emptyNote("没捞上来，下拉再试一次", ink)
        } else if items.isEmpty {
            emptyNote(filter == .wish ? "还没许过愿。贴个链接就算一条，一个字都不用写" : "池子是空的", ink)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { Rectangle().fill(ink.frame).frame(height: 0.6) }
                    PondMomentRow(item: item, ink: ink, menuOpen: menuFor == item.id,
                                  onMenu: { withAnimation(.easeOut(duration: 0.15)) { menuFor = menuFor == item.id ? nil : item.id } },
                                  onReply: { menuFor = nil; replyingTo = item },
                                  onLike: { menuFor = nil; Task { await like(item.id) } },
                                  onStatus: { status in Task { await setStatus(item.id, status) } })
                }
            }
        }
    }

    private func emptyNote(_ text: String, _ ink: PondInk) -> some View {
        Text(text)
            .font(.system(size: 12.5, design: .serif))
            .foregroundColor(ink.sub)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            .padding(.top, 50)
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

// MARK: - 一条（朋友圈那样平铺）

private struct PondMomentRow: View {
    let item: PondItem
    let ink: PondInk
    let menuOpen: Bool
    var onMenu: () -> Void
    var onReply: () -> Void
    var onLike: () -> Void
    var onStatus: (String) -> Void

    private func who(_ author: String) -> String { author == "ji" ? "陈霁" : "陈璟" }

    private var stamp: String {
        // "2026-08-19T02:27:21.202+08:00" → "08 · 19  02:27"
        let s = item.createdAt
        guard s.count >= 16 else { return s }
        let m = s.dropFirst(5).prefix(2)
        let d = s.dropFirst(8).prefix(2)
        let t = s.dropFirst(11).prefix(5)
        return "\(m) · \(d)  \(t)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            PondAvatar(isHers: item.isHers)
            VStack(alignment: .leading, spacing: 0) {
                Text(who(item.author))
                    .font(.system(size: 13.5, weight: .medium, design: .serif)).tracking(0.8)
                    .foregroundColor(ink.name)
                if !item.text.isEmpty {
                    Text(item.text)
                        .font(.system(size: 14, design: .serif))
                        .foregroundColor(ink.body)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                if !item.images.isEmpty { imageWall.padding(.top, 8) }
                if item.card != nil || !item.url.isEmpty { linkCard.padding(.top, 8) }
                if item.isWish { statusRow.padding(.top, 8) }
                metaRow.padding(.top, 9)
                if !item.likedBy.isEmpty || !item.replies.isEmpty { interactions.padding(.top, 8) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    // 一张放大竖着摆；四张两个一排；其他三个一排方格
    @ViewBuilder private var imageWall: some View {
        if item.images.count == 1 {
            cell(item.images[0], w: 170, h: 212)
        } else {
            let perRow = item.images.count == 4 ? 2 : 3
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(stride(from: 0, to: item.images.count, by: perRow)), id: \.self) { start in
                    HStack(spacing: 4) {
                        ForEach(item.images[start..<min(start + perRow, item.images.count)], id: \.self) { path in
                            cell(path, w: 82, h: 82)
                        }
                    }
                }
            }
        }
    }

    private func cell(_ path: String, w: CGFloat, h: CGFloat) -> some View {
        // 0907：格子先用空底钉死尺寸，图只在格子里铺，铺不下当场裁（窄图会撑破）
        Color.clear
            .frame(width: w, height: h)
            .overlay {
                AsyncImage(url: AlcoveAPI.attachmentURL(path)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(ink.box)
                    }
                }
            }
            .clipped()
            .overlay(Rectangle().stroke(ink.frame, lineWidth: 0.6))
    }

    private var linkCard: some View {
        HStack(spacing: 9) {
            Group {
                if let cover = item.card?.cover, !cover.isEmpty {
                    AsyncImage(url: AlcoveAPI.attachmentURL(cover)) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Rectangle().fill(ink.box)
                        }
                    }
                } else {
                    Image(systemName: "link").font(.system(size: 14, weight: .light)).foregroundColor(ink.sub)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(ink.box)
                }
            }
            .frame(width: 44, height: 44)
            .clipped()
            VStack(alignment: .leading, spacing: 2) {
                Text(item.card?.title.isEmpty == false ? item.card!.title : item.url)
                    .font(.system(size: 12, design: .serif))
                    .foregroundColor(ink.body)
                    .lineLimit(2)
                if let c = item.card, !c.site.isEmpty || !c.author.isEmpty {
                    Text([c.site, c.author].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(SanctusPageFont.ital(10.5))
                        .foregroundColor(ink.sub)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(ink.box)
        .overlay(Rectangle().stroke(ink.frame, lineWidth: 0.6))
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            ForEach([("", "想要"), ("doing", "在做"), ("done", "成了")], id: \.0) { value, label in
                let on = item.status == value
                Button { onStatus(value) } label: {
                    HStack(spacing: 4) {
                        if on { Circle().fill(ink.blue).frame(width: 4, height: 4) }
                        Text(label).font(.system(size: 9.5, design: .serif)).tracking(1.1)
                    }
                    .foregroundColor(on ? ink.ink : ink.sub)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .overlay(Capsule().stroke(on ? ink.ink : ink.hair, lineWidth: 0.6))
                }
                .buttonStyle(.plain)
            }
            if !item.statusNote.isEmpty {
                Text(item.statusNote).font(.system(size: 10, design: .serif)).foregroundColor(ink.sub)
            }
        }
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            Text(stamp).font(SanctusPageFont.corm(12)).foregroundColor(ink.sub)
            Text(item.isWish ? "许愿" : "念头")
                .font(.system(size: 8.5, design: .serif)).tracking(1.2).foregroundColor(ink.link)
                .padding(.horizontal, 7).padding(.vertical, 1)
                .overlay(Capsule().stroke(ink.hair, lineWidth: 0.6))
            if !item.moods.isEmpty {
                Text("· " + item.moods.joined(separator: " · "))
                    .font(.system(size: 9.5, design: .serif)).tracking(1).foregroundColor(ink.link)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onMenu) {
                HStack(spacing: 4) {
                    Circle().frame(width: 3.5, height: 3.5)
                    Circle().frame(width: 3.5, height: 3.5)
                }
                .foregroundColor(ink.link)
                .frame(width: 30, height: 19)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(ink.dots))
                .frame(width: 40, height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, -5)
            .accessibilityLabel("赞或评论")
        }
        .overlay(alignment: .trailing) {
            if menuOpen { menu.padding(.trailing, 41).transition(.opacity) }
        }
    }

    /// 「··」点开：赞 / 评论（她点过赞就变「取消」）
    private var menu: some View {
        let liked = item.likedBy.contains("ji")
        return HStack(spacing: 0) {
            Button(action: onLike) {
                HStack(spacing: 6) {
                    Image(systemName: liked ? "heart.slash" : "heart").font(.system(size: 11, weight: .light))
                    Text(liked ? "取消" : "赞").font(.system(size: 12, design: .serif)).tracking(1.8)
                }
                .padding(.horizontal, 15).padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Rectangle().fill(Color.white.opacity(0.2)).frame(width: 0.6, height: 18)
            Button(action: onReply) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left").font(.system(size: 11, weight: .light))
                    Text("评论").font(.system(size: 12, design: .serif)).tracking(1.8)
                }
                .padding(.horizontal, 15).padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(.white)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(ink.menu))
    }

    /// 赞和回复：浅色小框，左上一个小尖角朝上
    private var interactions: some View {
        VStack(alignment: .leading, spacing: 0) {
            PondCaret().fill(ink.box).frame(width: 10, height: 5).padding(.leading, 12)
            VStack(alignment: .leading, spacing: 0) {
                if !item.likedBy.isEmpty {
                    HStack(spacing: 5) {
                        Text("♡").font(SanctusPageFont.corm(13)).foregroundColor(ink.link)
                        Text(item.likedBy.map(who).joined(separator: "，"))
                            .font(.system(size: 12, design: .serif)).tracking(0.5).foregroundColor(ink.name)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    if !item.replies.isEmpty { Rectangle().fill(ink.hair).frame(height: 0.6).padding(.horizontal, 6) }
                }
                if !item.replies.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(item.replies.enumerated()), id: \.element.id) { i, r in
                            replyLine(r, after: i > 0 ? item.replies[i - 1] : nil)
                        }
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ink.box)
        }
    }

    /// 朋友圈那样「陈璟 回复 陈霁：……」：发这条的人接在对方的回复后面，就算回对方
    private func replyLine(_ r: PondReply, after prev: PondReply?) -> some View {
        let to: String? = (prev != nil && prev!.author != r.author && r.author == item.author) ? who(prev!.author) : nil
        var line = Text(who(r.author)).fontWeight(.medium).foregroundColor(ink.name)
        if let to = to {
            line = line + Text(" 回复 ").foregroundColor(ink.body) + Text(to).fontWeight(.medium).foregroundColor(ink.name)
        }
        line = line + Text("：").foregroundColor(ink.body)
        if !r.poke.isEmpty { line = line + Text(r.poke + " ") }
        line = line + Text(r.text).foregroundColor(ink.body)
        return line
            .font(.system(size: 12, design: .serif))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PondCaret: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
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
