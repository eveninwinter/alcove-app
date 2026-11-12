import SwiftUI
import PhotosUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - 1112 檐下「公开」那一边（#5037–5043）
// 檐下顶上一个「私密｜公开」胶囊：私密＝原来的檐下（只有她和陈璟）；公开＝联邦朋友圈
// （github nnkiirue99-maker/ai-friend-circle，装在服务器 /opt/friend-circle，身份 @tong / @chenjing @eaves.ob-memory.uk）。
// 她定：前端不用它自带的界面，两边都照檐下的样子。效果图 sanctus-kit/mock-moments/pub.jpg。
// 数据走前门 /api/federation/*（serve.py 转给它的私有网关）。三页：动态 / 好友 / 邀请。
// 陈璟自己发帖的工具（MCP）她说先不接，所以这里只有她能发；他那边的头像她可以替他同步。

// MARK: 数据

struct EavesActor {
    let id, kind, name, handle, bio, avatar, cover: String
    let links: [String]
    let revision: Int
    init(_ d: [String: Any]) {
        id = d.string("actor_id"); kind = d.string("kind"); name = d.string("name"); handle = d.string("handle")
        bio = d.string("bio"); avatar = d.string("avatar"); cover = d.string("cover")
        links = d["links"] as? [String] ?? []
        revision = d.int("revision")
    }
    var isAI: Bool { kind == "ai" }
}

struct EavesObject: Identifiable {
    let id, actor, kind, root, parent, text: String
    let media: [String]
    let published: Double
    init(_ d: [String: Any]) {
        id = d.string("id"); actor = d.string("actor"); kind = d.string("kind"); root = d.string("root"); parent = d.string("parent")
        let c = d.object("content")
        text = c.string("text")
        media = c["media"] as? [String] ?? []
        published = d.double("published")
    }
}

struct EavesContact: Identifiable {
    let id, human, status, note: String
    let ais: [String]
    let initiated: Int
    init(_ d: [String: Any]) {
        id = d.string("id"); human = d.string("remote_human"); status = d.string("status"); note = d.string("note")
        ais = d["remote_ai"] as? [String] ?? []
        initiated = d.int("initiated")
    }
}

struct EavesInvite: Identifiable {
    let id: String
    let expires: Double
    let revoked, maxUses, uses: Int
    init(_ d: [String: Any]) {
        id = d.string("id"); expires = d.double("expires"); revoked = d.int("revoked"); maxUses = d.int("max_uses"); uses = d.int("uses")
    }
    var state: String {
        if revoked != 0 { return "已撤销" }
        if expires <= Date().timeIntervalSince1970 { return "已过期" }
        if uses >= maxUses { return "已用完" }
        return "有效"
    }
}

struct EavesFailure: Error {
    let status: Int
    let code: String
    var text: String {
        switch code {
        case "invalid_media": return "这张图用不了，换一张"
        case "invalid_request_size", "message_too_large": return "图或字太大了"
        case "federation_gateway_unavailable", "federation_not_installed": return "朋友圈服务没连上"
        default: break
        }
        if status == 403 { return "没有权限，或者好友关系变了" }
        if status == 404 { return "找不到，可能已经删了" }
        if status == 409 { return "那边变过了，刷新再试" }
        if status == 429 { return "点得太勤了，等一下" }
        return "没成（\(status) \(code)）"
    }
}

enum EavesAPI {
    static func query(_ items: [(String, String)]) -> String {
        var c = URLComponents()
        c.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
        return c.percentEncodedQuery ?? ""
    }

    static func call(_ path: String, body: [String: Any]? = nil, method: String? = nil) async throws -> [String: Any] {
        var req = URLRequest(url: AlcoveAPI.fullURL("/api/federation" + path))
        req.httpMethod = method ?? (body == nil ? "GET" : "POST")
        req.timeoutInterval = 40
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("links", forHTTPHeaderField: "X-Federation-Media")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await AlcoveAPI.session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        guard (200...299).contains(status) else { throw EavesFailure(status: status, code: obj.string("error")) }
        return obj
    }
}

/// 把任意照片压成它收得下的小 JPEG（一张 data URL 不超过 10 万字符），一档一档缩，不直接拒
func eavesJPEGDataURL(from data: Data, maxEdge: CGFloat, budget: Int = 72_000) -> String? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let factors: [CGFloat] = [1.0, 0.8, 0.62, 0.48, 0.36, 0.27, 0.2]
    let qualities: [CGFloat] = [0.72, 0.58, 0.45]
    for factor in factors {
        let edge = max(64, (maxEdge * factor).rounded())
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: edge,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        for quality in qualities {
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
            CGImageDestinationAddImage(dest, cg, props as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { continue }
            if out.length <= budget { return "data:image/jpeg;base64," + (out as Data).base64EncodedString() }
        }
    }
    return nil
}

private func eavesDecode(_ dataURL: String) -> UIImage? {
    guard dataURL.hasPrefix("data:image"), let part = dataURL.split(separator: ",", maxSplits: 1).last,
          let data = Data(base64Encoded: String(part)) else { return nil }
    return UIImage(data: data)
}

// MARK: 模型

@MainActor
final class EavesModel: ObservableObject {
    @Published var me = ""
    @Published var own: [EavesActor] = []
    @Published var actors: [String: EavesActor] = [:]
    @Published var posts: [EavesObject] = []
    @Published var threads: [String: [EavesObject]] = [:]
    @Published var contacts: [EavesContact] = []
    @Published var invites: [EavesInvite] = []
    @Published var freshInvite = ""
    @Published var loading = true
    @Published var failed = false
    @Published var notice = ""
    private var noticeSeq = 0

    func say(_ t: String) {
        notice = t
        noticeSeq += 1
        let seq = noticeSeq
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, self.noticeSeq == seq else { return }
            self.notice = ""
        }
    }

    private func report(_ error: Error) {
        if let f = error as? EavesFailure { say(f.text) } else { say("没连上") }
    }

    func isMine(_ actor: String) -> Bool { own.contains { $0.id == actor } }

    func name(_ actor: String) -> String {
        if let c = contacts.first(where: { $0.human == actor }), !c.note.isEmpty { return c.note }
        if let a = actors[actor], !a.name.isEmpty { return a.name }
        return URL(string: actor)?.host ?? "朋友"
    }

    func loadAll() async {
        do {
            let j = try await EavesAPI.call("/me")
            me = j.string("actor_id")
            own = (j["actors"] as? [[String: Any]] ?? []).map(EavesActor.init)
            for a in own { actors[a.id] = a }
            try await loadFeed()
            failed = false
        } catch {
            failed = posts.isEmpty
            if !posts.isEmpty { report(error) }
        }
        loading = false
        await loadContacts()
        await loadInvites()
    }

    func loadFeed() async throws {
        let j = try await EavesAPI.call("/social/feed")
        let list = (j["items"] as? [[String: Any]] ?? []).map(EavesObject.init)
        posts = list.sorted { $0.published == $1.published ? $0.id > $1.id : $0.published > $1.published }
        for actor in Set(posts.map(\.actor)) { await ensureActor(actor) }
        for post in posts.prefix(20) { await loadThread(post.id) }
    }

    func ensureActor(_ actor: String) async {
        guard !actor.isEmpty, actors[actor] == nil else { return }
        let q = EavesAPI.query([("target", actor), ("limit", "1")])
        if let j = try? await EavesAPI.call("/social/profile?" + q), let p = j["profile"] as? [String: Any] {
            actors[actor] = EavesActor(p)
        }
    }

    func loadThread(_ root: String, refresh: Bool = false) async {
        let j: [String: Any]?
        if refresh {
            j = try? await EavesAPI.call("/social/thread/refresh", body: ["root": root])
        } else {
            j = try? await EavesAPI.call("/social/thread?" + EavesAPI.query([("root", root)]))
        }
        guard let j else { return }
        let items = (j["items"] as? [[String: Any]] ?? []).map(EavesObject.init).sorted { $0.published < $1.published }
        threads[root] = items
        for actor in Set(items.map(\.actor)) { await ensureActor(actor) }
    }

    func likes(_ post: EavesObject) -> [EavesObject] { (threads[post.id] ?? []).filter { $0.kind == "like" } }
    func comments(_ post: EavesObject) -> [EavesObject] { (threads[post.id] ?? []).filter { $0.kind == "comment" } }
    func myLike(_ post: EavesObject) -> EavesObject? { likes(post).first { $0.actor == me } }

    func toggleLike(_ post: EavesObject) async {
        do {
            if let mine = myLike(post) {
                _ = try await EavesAPI.call("/social/delete", body: ["id": mine.id])
            } else {
                _ = try await EavesAPI.call("/social/interact", body: ["root": post.id, "kind": "like"])
            }
            await loadThread(post.id, refresh: true)
        } catch { report(error) }
    }

    func comment(_ post: EavesObject, text: String, parent: String?) async {
        var body: [String: Any] = ["root": post.id, "kind": "comment", "text": text]
        if let parent, !parent.isEmpty { body["parent"] = parent }
        do {
            _ = try await EavesAPI.call("/social/interact", body: body)
            await loadThread(post.id, refresh: true)
        } catch { report(error) }
    }

    func deletePost(_ post: EavesObject) async {
        do {
            _ = try await EavesAPI.call("/social/delete", body: ["id": post.id])
            posts.removeAll { $0.id == post.id }
        } catch { report(error) }
    }

    func deleteComment(_ c: EavesObject) async {
        do {
            _ = try await EavesAPI.call("/social/delete", body: ["id": c.id])
            await loadThread(c.root, refresh: true)
        } catch { report(error) }
    }

    func publish(text: String, media: [String]) async -> Bool {
        let audience: [String: Any] = ["mode": "all", "include": [String](), "exclude": [String]()]
        let scope: [String: Any] = ["visibility": "federated_friends", "audience": audience]
        do {
            _ = try await EavesAPI.call("/social/posts", body: ["text": text, "media": media, "scope": scope])
            try? await loadFeed()
            return true
        } catch {
            report(error)
            return false
        }
    }

    // 好友

    func loadContacts() async {
        guard let j = try? await EavesAPI.call("/contacts?limit=50") else { return }
        contacts = (j["items"] as? [[String: Any]] ?? []).map(EavesContact.init)
        for c in contacts {
            await ensureActor(c.human)
            for ai in c.ais { await ensureActor(ai) }
        }
    }

    func answer(_ c: EavesContact, accept: Bool) async {
        do {
            _ = try await EavesAPI.call("/friend-requests/" + (accept ? "accept" : "reject"), body: ["group_id": c.id, "include_ai": true])
            await loadContacts()
            if accept { try? await loadFeed() }
        } catch { report(error) }
    }

    func removeFriend(_ c: EavesContact) async {
        do {
            _ = try await EavesAPI.call("/contacts/remove", body: ["remote_actor_id": c.human])
            await loadContacts()
        } catch { report(error) }
    }

    /// 输入「@名字@域名」或者邀请链接 / 邀请码
    func addFriend(_ raw: String) async -> Bool {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return false }
        do {
            if input.hasPrefix("@") {
                let j = try await EavesAPI.call("/resolve?" + EavesAPI.query([("handle", input)]))
                let actor = j.string("id", "actor_id")
                guard !actor.isEmpty else { say("没找到这个人"); return false }
                _ = try await EavesAPI.call("/friend-requests", body: ["remote_actor_id": actor, "include_ai": true])
            } else {
                _ = try await EavesAPI.call("/invitations/redeem", body: ["invitation": input, "include_ai": true])
            }
            say("申请发出去了，等对方确认")
            await loadContacts()
            return true
        } catch {
            report(error)
            return false
        }
    }

    // 邀请

    func loadInvites() async {
        guard let j = try? await EavesAPI.call("/invitations") else { return }
        invites = (j["items"] as? [[String: Any]] ?? []).map(EavesInvite.init)
    }

    func makeInvite() async {
        do {
            let j = try await EavesAPI.call("/invitations", body: ["lifetime": 604800, "max_uses": 10])
            freshInvite = j.string("url")
            await loadInvites()
        } catch { report(error) }
    }

    func revokeInvite(_ id: String) async {
        do {
            _ = try await EavesAPI.call("/invitations/revoke", body: ["id": id])
            await loadInvites()
        } catch { report(error) }
    }

    // 资料

    private func saveProfile(_ a: EavesActor, name: String, avatar: String) async {
        let profile: [String: Any] = [
            "name": name, "bio": a.bio,
            "avatar": avatar.isEmpty ? NSNull() : avatar as Any,
            "cover": a.cover.isEmpty ? NSNull() : a.cover as Any,
            "links": a.links,
        ]
        do {
            let j = try await EavesAPI.call("/social/profile", body: ["actor_id": a.id, "expected_revision": a.revision, "profile": profile], method: "PUT")
            let saved = EavesActor(j)
            guard !saved.id.isEmpty else { say("没存上"); return }
            actors[saved.id] = saved
            if let i = own.firstIndex(where: { $0.id == saved.id }) { own[i] = saved }
            say("存好了")
        } catch { report(error) }
    }

    func rename(_ a: EavesActor, to name: String) async { await saveProfile(a, name: name, avatar: a.avatar) }

    /// 把聊天页那张头像用到这边（压成小 JPEG）
    func syncAvatar(_ a: EavesActor, chatAvatar: String) async {
        let payload = chatAvatar.split(separator: ",", maxSplits: 1).last.map(String.init) ?? chatAvatar
        guard let data = Data(base64Encoded: payload), let small = eavesJPEGDataURL(from: data, maxEdge: 320) else {
            say("聊天页还没设这张头像"); return
        }
        await saveProfile(a, name: a.name, avatar: small)
    }
}

// MARK: - 头像、图片

/// 自己和陈璟用聊天页那两张；别人用对方资料里的头像，没有就一个字
private struct EavesAvatar: View {
    let actor: String
    @ObservedObject var model: EavesModel
    var size: CGFloat = 40
    var radius: CGFloat = 8

    var body: some View {
        if let mine = model.own.first(where: { $0.id == actor }) {
            PondAvatar(isHers: !mine.isAI, size: size, radius: radius)
        } else {
            Group {
                if let img = eavesDecode(model.actors[actor]?.avatar ?? "") {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    ZStack {
                        Color(red: 0xA9 / 255, green: 0xAF / 255, blue: 0xBC / 255)
                        Text(String(model.name(actor).prefix(1))).font(.system(size: size * 0.38, design: .serif)).foregroundColor(.white)
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

/// 动态里的图：服务器给的是签过名的链接，自己刚选的是内嵌 JPEG
private struct EavesPicture: View {
    let value: String
    let fill: Color
    var body: some View {
        if let img = eavesDecode(value) {
            Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
        } else if let url = URL(string: value), url.scheme == "https" {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(fill)
                }
            }
        } else {
            Rectangle().fill(fill)
        }
    }
}

// MARK: - 封面下面整块

private struct EavesCommentTarget: Identifiable {
    let post: EavesObject
    let parent: EavesObject?
    var id: String { post.id + "|" + (parent?.id ?? "") }
}

struct EavesSection: View {
    let ink: PondInk
    @ObservedObject var model: EavesModel
    @Binding var composing: Bool
    @AppStorage("eavesTab") private var tab = "feed"
    @State private var menuFor: String?
    @State private var commenting: EavesCommentTarget?
    @State private var deleting: EavesObject?
    @State private var askDelete = false

    private let tabs: [(String, String)] = [("feed", "动态"), ("friends", "好友"), ("invite", "邀请")]

    init(ink: PondInk, model: EavesModel, composing: Binding<Bool>) {
        self.ink = ink
        self.model = model
        self._composing = composing
    }

    var body: some View {
        VStack(spacing: 0) {
            subBar
            if !model.notice.isEmpty {
                Text(model.notice).font(.system(size: 11.5, design: .serif)).foregroundColor(ink.link)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.top, 10)
            }
            if tab == "friends" {
                EavesFriends(ink: ink, model: model)
            } else if tab == "invite" {
                EavesInvites(ink: ink, model: model)
            } else {
                feed
            }
        }
        .task { await model.loadAll() }
        .sheet(isPresented: $composing) {
            EavesComposeSheet(ink: ink) { text, media in await model.publish(text: text, media: media) }
        }
        .sheet(item: $commenting) { t in
            EavesCommentSheet(ink: ink, quote: t.parent?.text ?? t.post.text,
                              title: t.parent == nil ? "评论" : "回复 " + model.name(t.parent?.actor ?? "")) { text in
                Task { await model.comment(t.post, text: text, parent: t.parent?.id) }
            }
        }
        .confirmationDialog("删掉这条？好友那边也会一起删", isPresented: $askDelete, titleVisibility: .visible) {
            Button("删掉", role: .destructive) {
                if let d = deleting {
                    Task { if d.kind == "comment" { await model.deleteComment(d) } else { await model.deletePost(d) } }
                }
            }
            Button("留着", role: .cancel) {}
        }
    }

    private var subBar: some View {
        HStack(alignment: .firstTextBaseline) {
            (Text("ON THE EAVES · ").font(SanctusPageFont.corm(8)) + Text("公开").font(.system(size: 8, design: .serif)))
                .tracking(2.4).foregroundColor(ink.sub)
            Spacer()
            HStack(spacing: 16) {
                ForEach(tabs, id: \.0) { t in
                    Button {
                        tab = t.0
                        menuFor = nil
                    } label: {
                        Text(t.1).font(.system(size: 11.5, design: .serif)).tracking(2.3)
                            .foregroundColor(tab == t.0 ? ink.ink : ink.sub)
                            .padding(.bottom, 3)
                            .overlay(alignment: .bottom) {
                                if tab == t.0 { Rectangle().fill(ink.ink).frame(height: 0.8) }
                            }
                            .overlay(alignment: .topTrailing) {
                                if t.0 == "friends" && incoming > 0 {
                                    Circle().fill(ink.ink).frame(width: 4, height: 4).offset(x: 5, y: -1)
                                }
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

    private var incoming: Int { model.contacts.filter { $0.status == "pending" && $0.initiated == 0 }.count }

    @ViewBuilder private var feed: some View {
        if model.loading {
            ProgressView().tint(ink.sub).padding(.top, 50)
        } else if model.failed {
            note("没连上，下拉再试一次")
        } else if model.posts.isEmpty {
            note("这边还没有动态。右上角加号发第一条，或者去「邀请」拉个朋友进来")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(model.posts.enumerated()), id: \.element.id) { i, post in
                    if i > 0 { Rectangle().fill(ink.frame).frame(height: 0.6) }
                    EavesRow(post: post, ink: ink, model: model, menuOpen: menuFor == post.id,
                             onMenu: { withAnimation(.easeOut(duration: 0.15)) { menuFor = menuFor == post.id ? nil : post.id } },
                             onLike: { menuFor = nil; Task { await model.toggleLike(post) } },
                             onComment: { parent in menuFor = nil; commenting = EavesCommentTarget(post: post, parent: parent) },
                             onDelete: { target in menuFor = nil; deleting = target; askDelete = true })
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5, design: .serif))
            .foregroundColor(ink.sub)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .padding(.horizontal, 40)
            .padding(.top, 50)
    }
}

// MARK: - 一条动态（跟檐下那条一个样子）

private struct EavesRow: View {
    let post: EavesObject
    let ink: PondInk
    @ObservedObject var model: EavesModel
    let menuOpen: Bool
    var onMenu: () -> Void
    var onLike: () -> Void
    var onComment: (EavesObject?) -> Void
    var onDelete: (EavesObject) -> Void

    private static let stampFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM · dd  HH:mm"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai"); f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    var body: some View {
        let actor = model.actors[post.actor]
        let likes = model.likes(post)
        let comments = model.comments(post)
        HStack(alignment: .top, spacing: 11) {
            EavesAvatar(actor: post.actor, model: model)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.name(post.actor))
                        .font(.system(size: 13.5, weight: .medium, design: .serif)).tracking(0.8)
                        .foregroundColor(ink.name)
                        .lineLimit(1)
                    if actor?.isAI == true {
                        Text("AI").font(SanctusPageFont.corm(8)).tracking(1.1).foregroundColor(ink.link)
                            .padding(.horizontal, 6).padding(.vertical, 0.5)
                            .overlay(Capsule().stroke(ink.hair, lineWidth: 0.6))
                    }
                    if let handle = actor?.handle, !handle.isEmpty {
                        Text(handle).font(SanctusPageFont.ital(11)).foregroundColor(ink.sub)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
                if !post.text.isEmpty {
                    Text(post.text)
                        .font(.system(size: 14, design: .serif))
                        .foregroundColor(ink.body)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                if !post.media.isEmpty { imageWall.padding(.top, 8) }
                metaRow.padding(.top, 9)
                if !likes.isEmpty || !comments.isEmpty { interactions(likes, comments).padding(.top, 8) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    @ViewBuilder private var imageWall: some View {
        if post.media.count == 1 {
            cell(post.media[0], w: 170, h: 212)
        } else {
            let perRow = post.media.count == 4 ? 2 : 3
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(stride(from: 0, to: post.media.count, by: perRow)), id: \.self) { start in
                    HStack(spacing: 4) {
                        ForEach(Array(post.media[start..<min(start + perRow, post.media.count)].enumerated()), id: \.offset) { _, value in
                            cell(value, w: 82, h: 82)
                        }
                    }
                }
            }
        }
    }

    private func cell(_ value: String, w: CGFloat, h: CGFloat) -> some View {
        Color.clear
            .frame(width: w, height: h)
            .overlay { EavesPicture(value: value, fill: ink.box) }
            .clipped()
            .overlay(Rectangle().stroke(ink.frame, lineWidth: 0.6))
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            Text(Self.stampFormat.string(from: Date(timeIntervalSince1970: post.published)))
                .font(SanctusPageFont.corm(12)).foregroundColor(ink.sub)
            Spacer(minLength: 0)
            Button(action: onMenu) {
                HStack(spacing: 4) {
                    Circle().frame(width: 3.5, height: 3.5)
                    Circle().frame(width: 3.5, height: 3.5)
                }
                .foregroundColor(ink.link)
                .frame(width: 30, height: 19)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(ink.dots))
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

    private var menu: some View {
        let liked = model.myLike(post) != nil
        return HStack(spacing: 0) {
            menuButton(liked ? "heart.slash" : "heart", liked ? "取消" : "赞", action: onLike)
            Rectangle().fill(Color.white.opacity(0.2)).frame(width: 0.6, height: 18)
            menuButton("bubble.left", "评论") { onComment(nil) }
            if model.isMine(post.actor) {
                Rectangle().fill(Color.white.opacity(0.2)).frame(width: 0.6, height: 18)
                menuButton("trash", "删除") { onDelete(post) }
            }
        }
        .foregroundColor(.white)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(ink.menu))
    }

    private func menuButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .light))
                Text(label).font(.system(size: 12, design: .serif)).tracking(1.8)
            }
            .padding(.horizontal, 13).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func interactions(_ likes: [EavesObject], _ comments: [EavesObject]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PondCaret().fill(ink.box).frame(width: 10, height: 5).padding(.leading, 12)
            VStack(alignment: .leading, spacing: 0) {
                if !likes.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("♡").font(SanctusPageFont.corm(13)).foregroundColor(ink.link)
                        Text(likes.map { model.name($0.actor) }.joined(separator: "，"))
                            .font(.system(size: 12, design: .serif)).tracking(0.5).foregroundColor(ink.name)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    if !comments.isEmpty { Rectangle().fill(ink.hair).frame(height: 0.6).padding(.horizontal, 6) }
                }
                if !comments.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(comments) { c in
                            commentLine(c, in: comments)
                                .contentShape(Rectangle())
                                .onTapGesture { onComment(c) }
                                .contextMenu {
                                    if model.isMine(c.actor) {
                                        Button(role: .destructive) { onDelete(c) } label: { Label("删掉这句", systemImage: "trash") }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ink.box, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(ink.frame, lineWidth: 0.6))
        }
    }

    /// 「A：……」；回的是别人那句评论就写「A 回复 B：……」
    private func commentLine(_ c: EavesObject, in all: [EavesObject]) -> some View {
        var line = Text(model.name(c.actor)).fontWeight(.medium).foregroundColor(ink.name)
        if !c.parent.isEmpty, c.parent != post.id, let target = all.first(where: { $0.id == c.parent }) {
            line = line + Text(" 回复 ").foregroundColor(ink.body) + Text(model.name(target.actor)).fontWeight(.medium).foregroundColor(ink.name)
        }
        line = line + Text("：").foregroundColor(ink.body) + Text(c.text).foregroundColor(ink.body)
        return line
            .font(.system(size: 12, design: .serif))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 好友

private struct EavesFriends: View {
    let ink: PondInk
    @ObservedObject var model: EavesModel
    @AppStorage("userAvatarDataURL") private var userAvatar = ""
    @AppStorage("assistantAvatarDataURL") private var assistantAvatar = ""
    @State private var adding = ""
    @State private var renaming = false
    @State private var newName = ""
    @State private var removing: EavesContact?
    @State private var askRemove = false
    @FocusState private var addFocused: Bool

    var body: some View {
        let incoming = model.contacts.filter { $0.status == "pending" && $0.initiated == 0 }
        let outgoing = model.contacts.filter { $0.status == "pending" && $0.initiated != 0 }
        let friends = model.contacts.filter { $0.status == "active" }
        VStack(alignment: .leading, spacing: 0) {
            head("我们", "us")
            ForEach(model.own, id: \.id) { a in ownRow(a) }

            if !incoming.isEmpty {
                head("想加你的", "asking")
                ForEach(incoming) { c in
                    personRow(c) {
                        HStack(spacing: 8) {
                            pill("接受", strong: true) { Task { await model.answer(c, accept: true) } }
                            pill("不加") { Task { await model.answer(c, accept: false) } }
                        }
                    }
                }
            }

            head("加好友", "add")
            HStack(spacing: 8) {
                TextField("@名字@域名，或者对方给的邀请链接", text: $adding)
                    .font(.system(size: 12.5, design: .serif)).foregroundColor(ink.ink)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($addFocused)
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(ink.field, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(ink.fieldEdge, lineWidth: 0.6))
                pill("加", strong: true) {
                    let text = adding
                    addFocused = false
                    Task { if await model.addFriend(text) { adding = "" } }
                }
            }
            .padding(.top, 4)

            head("好友", "friends")
            if friends.isEmpty && outgoing.isEmpty {
                Text("还没有好友").font(.system(size: 12, design: .serif)).foregroundColor(ink.sub).padding(.top, 6)
            }
            ForEach(friends) { c in
                personRow(c) {
                    pill("删除") { removing = c; askRemove = true }
                }
            }
            ForEach(outgoing) { c in
                personRow(c) {
                    Text("等对方确认").font(.system(size: 10.5, design: .serif)).tracking(1).foregroundColor(ink.sub)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .alert("改昵称", isPresented: $renaming) {
            TextField("昵称", text: $newName)
            Button("存") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, let a = model.own.first(where: { !$0.isAI }) { Task { await model.rename(a, to: name) } }
            }
            Button("算了", role: .cancel) {}
        }
        .confirmationDialog("删掉这个好友？对方的 AI 也一起删", isPresented: $askRemove, titleVisibility: .visible) {
            Button("删掉", role: .destructive) { if let c = removing { Task { await model.removeFriend(c) } } }
            Button("留着", role: .cancel) {}
        }
    }

    private func head(_ cn: String, _ en: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(cn).font(.system(size: 12.5, weight: .medium, design: .serif)).tracking(1.6).foregroundColor(ink.ink)
            Text(en).font(SanctusPageFont.ital(11.5)).foregroundColor(ink.sub)
        }
        .padding(.top, 22)
        .padding(.bottom, 6)
    }

    private func pill(_ label: String, strong: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, design: .serif)).tracking(1.4)
                .foregroundColor(strong ? ink.ink : ink.link)
                .padding(.horizontal, 11).padding(.vertical, 5)
                .overlay(Capsule().stroke(strong ? ink.ink : ink.hair, lineWidth: 0.6))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func ownRow(_ a: EavesActor) -> some View {
        HStack(spacing: 11) {
            EavesAvatar(actor: a.id, model: model)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(a.name).font(.system(size: 13.5, weight: .medium, design: .serif)).foregroundColor(ink.name)
                    if a.isAI {
                        Text("AI").font(SanctusPageFont.corm(8)).tracking(1.1).foregroundColor(ink.link)
                            .padding(.horizontal, 6).padding(.vertical, 0.5)
                            .overlay(Capsule().stroke(ink.hair, lineWidth: 0.6))
                    }
                }
                Text(a.handle).font(SanctusPageFont.ital(11)).foregroundColor(ink.sub).lineLimit(1)
            }
            Spacer(minLength: 0)
            if !a.isAI {
                pill("改昵称") { newName = a.name; renaming = true }
            }
            pill(a.avatar.isEmpty ? "同步头像" : "换头像") {
                Task { await model.syncAvatar(a, chatAvatar: a.isAI ? assistantAvatar : userAvatar) }
            }
        }
        .padding(.vertical, 8)
    }

    private func personRow<Trailing: View>(_ c: EavesContact, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 11) {
            EavesAvatar(actor: c.human, model: model)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name(c.human)).font(.system(size: 13.5, weight: .medium, design: .serif)).foregroundColor(ink.name).lineLimit(1)
                Text(model.actors[c.human]?.handle ?? (URL(string: c.human)?.host ?? ""))
                    .font(SanctusPageFont.ital(11)).foregroundColor(ink.sub).lineLimit(1)
                if !c.ais.isEmpty {
                    Text("AI：" + c.ais.map { model.name($0) }.joined(separator: "，"))
                        .font(.system(size: 10.5, design: .serif)).foregroundColor(ink.link).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 邀请

private struct EavesInvites: View {
    let ink: PondInk
    @ObservedObject var model: EavesModel
    @State private var copied = false

    private static let day: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM.dd HH:mm"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai"); f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("生成一个链接发给朋友。对方在自己的服务器上装好同一套，打开链接就能向你发好友申请。")
                .font(.system(size: 12, design: .serif)).foregroundColor(ink.sub).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
            Button { copied = false; Task { await model.makeInvite() } } label: {
                Text("生成邀请链接").font(.system(size: 13, design: .serif)).tracking(2.4).foregroundColor(ink.ink)
                    .padding(.horizontal, 22).padding(.vertical, 9)
                    .overlay(Capsule().stroke(ink.ink.opacity(0.7), lineWidth: 0.7))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
            (Text("7 days · 10 people").font(SanctusPageFont.ital(11)) + Text("　七天内有效，最多十个人用").font(.system(size: 10.5, design: .serif)))
                .foregroundColor(ink.sub).padding(.top, 8)

            if !model.freshInvite.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.freshInvite).font(.system(size: 11, design: .monospaced)).foregroundColor(ink.body)
                        .lineLimit(4).textSelection(.enabled)
                    HStack(spacing: 10) {
                        Button {
                            UIPasteboard.general.string = model.freshInvite
                            copied = true
                        } label: {
                            Text(copied ? "已复制" : "复制").font(.system(size: 11, design: .serif)).tracking(1.4).foregroundColor(ink.ink)
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .overlay(Capsule().stroke(ink.ink, lineWidth: 0.6))
                        }
                        .buttonStyle(.plain)
                        Text("这个链接只显示这一次").font(.system(size: 10.5, design: .serif)).foregroundColor(ink.sub)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ink.box, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(ink.frame, lineWidth: 0.6))
                .padding(.top, 14)
            }

            if !model.invites.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("发出去的").font(.system(size: 12.5, weight: .medium, design: .serif)).tracking(1.6).foregroundColor(ink.ink)
                    Text("sent").font(SanctusPageFont.ital(11.5)).foregroundColor(ink.sub)
                }
                .padding(.top, 24).padding(.bottom, 4)
                ForEach(model.invites) { r in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.state).font(.system(size: 12.5, design: .serif)).foregroundColor(r.state == "有效" ? ink.ink : ink.sub)
                            Text("到 \(Self.day.string(from: Date(timeIntervalSince1970: r.expires))) · 用了 \(r.uses) / \(r.maxUses)")
                                .font(SanctusPageFont.corm(11.5)).foregroundColor(ink.sub)
                        }
                        Spacer(minLength: 0)
                        if r.state == "有效" {
                            Button { Task { await model.revokeInvite(r.id) } } label: {
                                Text("撤销").font(.system(size: 11, design: .serif)).tracking(1.4).foregroundColor(ink.link)
                                    .padding(.horizontal, 11).padding(.vertical, 5)
                                    .overlay(Capsule().stroke(ink.hair, lineWidth: 0.6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                    Rectangle().fill(ink.frame).frame(height: 0.6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
    }
}

// MARK: - 发一条 / 评论

private struct EavesComposeSheet: View {
    let ink: PondInk
    var onPublish: (String, [String]) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var picks: [PhotosPickerItem] = []
    @State private var media: [String] = []
    @State private var preparing = false
    @State private var sending = false
    @State private var skipped = 0

    private var canSend: Bool {
        !sending && !preparing && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !media.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("发一条").font(.system(size: 16, weight: .medium, design: .serif)).tracking(2).foregroundColor(ink.ink)
                Text("out in the open").font(SanctusPageFont.ital(11.5)).foregroundColor(ink.sub)
                Spacer()
                Button(sending ? "发着…" : "发") {
                    sending = true
                    Task {
                        let ok = await onPublish(text.trimmingCharacters(in: .whitespacesAndNewlines), media)
                        sending = false
                        if ok { dismiss() }
                    }
                }
                .font(.system(size: 13, design: .serif)).tracking(2.4)
                .foregroundColor(canSend ? ink.ink : ink.sub)
                .disabled(!canSend)
            }
            Text("所有好友和他们的 AI 都看得到").font(.system(size: 11, design: .serif)).foregroundColor(ink.sub)
            TextEditor(text: $text)
                .font(.system(size: 14, design: .serif))
                .foregroundColor(ink.ink)
                .scrollContentBackground(.hidden)
                .frame(height: 120)
                .padding(8)
                .background(ink.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ink.fieldEdge, lineWidth: 0.6))
            HStack(spacing: 6) {
                ForEach(Array(media.enumerated()), id: \.offset) { _, value in
                    Color.clear.frame(width: 62, height: 62)
                        .overlay { EavesPicture(value: value, fill: ink.box) }
                        .clipped()
                        .overlay(Rectangle().stroke(ink.frame, lineWidth: 0.6))
                }
                PhotosPicker(selection: $picks, maxSelectionCount: 4, matching: .images) {
                    ZStack {
                        Rectangle().fill(ink.field)
                        if preparing { ProgressView().controlSize(.small).tint(ink.sub) }
                        else { Image(systemName: "plus").font(.system(size: 15, weight: .light)).foregroundColor(ink.sub) }
                    }
                    .frame(width: 62, height: 62)
                    .overlay(Rectangle().stroke(ink.fieldEdge, lineWidth: 0.6))
                }
                Spacer(minLength: 0)
            }
            Text(skipped > 0 ? "有 \(skipped) 张图读不出来，没放上" : "最多四张，图会压小了再发")
                .font(.system(size: 10.5, design: .serif)).foregroundColor(ink.sub)
            Spacer()
        }
        .padding(20)
        .background(ink.sheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .preferredColorScheme(ink.dark ? .dark : .light)
        .onChange(of: picks) { _, items in
            preparing = true
            Task {
                var out: [String] = []
                var bad = 0
                for item in items.prefix(4) {
                    if let data = try? await item.loadTransferable(type: Data.self), let url = eavesJPEGDataURL(from: data, maxEdge: 1024) {
                        out.append(url)
                    } else {
                        bad += 1
                    }
                }
                media = out
                skipped = bad
                preparing = false
            }
        }
    }
}

private struct EavesCommentSheet: View {
    let ink: PondInk
    let quote: String
    let title: String
    var onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 16, weight: .medium, design: .serif)).tracking(2).foregroundColor(ink.ink).lineLimit(1)
                Spacer()
                Button("发") {
                    onSubmit(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .font(.system(size: 13, design: .serif)).tracking(2.4)
                .foregroundColor(text.isEmpty ? ink.sub : ink.ink)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !quote.isEmpty {
                Text(quote).font(.system(size: 12, design: .serif)).foregroundColor(ink.sub).lineSpacing(3).lineLimit(3)
            }
            TextEditor(text: $text)
                .font(.system(size: 14, design: .serif))
                .foregroundColor(ink.ink)
                .scrollContentBackground(.hidden)
                .frame(height: 100)
                .padding(8)
                .background(ink.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ink.fieldEdge, lineWidth: 0.6))
            Spacer()
        }
        .padding(20)
        .background(ink.sheet.ignoresSafeArea())
        .presentationDetents([.medium])
        .preferredColorScheme(ink.dark ? .dark : .light)
    }
}
