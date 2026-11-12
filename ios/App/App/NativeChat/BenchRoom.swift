import SwiftUI
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import UIKit

// MARK: - 1112 工作台（#5018–5032）
// 陈霁上班的文件放在这儿，放进来就一直在；隅要看的时候直接读服务器上的 /root/workroom/desk/<区>/<文件>。
// 样子照她点头的效果图（sanctus-kit/mock-desk/b.jpg）：上面一排区的标签（汉南 / 军山1 / 军山2 / 军山3 / 模版 / 领导），
// 下面一张白纸，每个区里分三块：图 / 表 / 文档。底下一个「放文件进来」。
// 数据走前门 /api/bench/*（alcove-independent/bench_api.py）。点一份＝下到手机用系统预览打开；长按＝备注、改名、挪区、收进旧版、删掉。

// MARK: 数据

struct BenchFile: Identifiable, Equatable {
    let id: String
    let folder: String
    let name: String
    let ext: String
    let kind: String        // pic / sheet / doc
    let note: String
    let size: Int
    let ts: Int
    let latest: Bool
    let isOld: Bool

    init(_ d: [String: Any]) {
        id = d.string("id")
        folder = d.string("folder")
        name = d.string("name")
        ext = d.string("ext").lowercased()
        kind = d.string("kind")
        note = d.string("note")
        size = d.int("size")
        ts = d.int("ts")
        latest = d.bool("latest")
        isOld = d.bool("is_old")
    }

    /// 不带后缀的名字
    var stem: String {
        guard !ext.isEmpty, name.lowercased().hasSuffix("." + ext) else { return name }
        return String(name.dropLast(ext.count + 1))
    }

    /// 小卡上那三个字母：XLS / DOC / PDF / JPG
    var extLabel: String {
        switch ext {
        case "jpg", "jpeg", "heic", "png", "webp", "gif", "bmp": return ext == "png" ? "PNG" : "JPG"
        case "": return "FILE"
        default: return String(ext.prefix(3)).uppercased()
        }
    }

    private static let beijing = TimeZone(identifier: "Asia/Shanghai") ?? .current
    private static let md: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM.dd"; f.timeZone = beijing; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    var dateText: String { Self.md.string(from: Date(timeIntervalSince1970: TimeInterval(ts))) }

    var sizeText: String {
        let kb = Double(size) / 1024
        if kb < 1 { return "1 KB" }
        if kb < 1000 { return "\(Int(kb.rounded())) KB" }
        let mb = kb / 1024
        return mb < 10 ? String(format: "%.1f MB", mb) : "\(Int(mb.rounded())) MB"
    }

    var thumbURL: URL { AlcoveAPI.fullURL("/api/bench/thumb?id=\(id)") }
}

@MainActor
final class BenchStore: ObservableObject {
    @Published var files: [BenchFile] = []
    @Published var counts: [String: Int] = [:]
    @Published var folders: [String] = ["汉南", "军山1", "军山2", "军山3", "模版", "领导"]
    @Published var loading = true
    @Published var failed = false
    @Published var toast = ""
    @Published var opening = ""       // 正在下到手机的那份的 id
    private var toastSeq = 0

    func say(_ t: String, hold: Double = 2.2) {
        toast = t
        toastSeq += 1
        let seq = toastSeq
        guard hold > 0 else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            guard let self, self.toastSeq == seq else { return }
            self.toast = ""
        }
    }

    func load() async {
        guard let j = try? await NativeHouseAPI.object("/api/bench/list") else {
            failed = files.isEmpty
            loading = false
            return
        }
        let list = (j["files"] as? [[String: Any]] ?? []).map(BenchFile.init)
        var c: [String: Int] = [:]
        var names: [String] = []
        for f in j["folders"] as? [[String: Any]] ?? [] {
            let n = f.string("name")
            guard !n.isEmpty else { continue }
            names.append(n)
            c[n] = f.int("count")
        }
        files = list
        counts = c
        if !names.isEmpty { folders = names }
        failed = false
        loading = false
    }

    func edit(_ id: String, _ change: [String: Any]) async {
        var body = change
        body["id"] = id
        guard let j = try? await NativeHouseAPI.objectIncludingHTTPError("/api/bench/edit", method: "POST", body: body) else {
            say("没连上，没改成"); return
        }
        if !j.bool("ok") { say(j.string("error").isEmpty ? "没改成" : j.string("error")) }
        await load()
    }

    func delete(_ id: String) async {
        guard let j = try? await NativeHouseAPI.objectIncludingHTTPError("/api/bench/delete", method: "POST", body: ["id": id]) else {
            say("没连上，没删成"); return
        }
        if !j.bool("ok") { say(j.string("error").isEmpty ? "没删成" : j.string("error")) }
        await load()
    }

    /// 传一份；回来的是「成没成、没成的原因」
    func upload(_ data: Data, name: String, folder: String) async -> (Bool, String) {
        if data.count > 80_000_000 { return (false, "超过 80M，太大了") }
        var comp = URLComponents(url: AlcoveAPI.fullURL("/api/bench/upload"), resolvingAgainstBaseURL: true)
        comp?.queryItems = [URLQueryItem(name: "folder", value: folder), URLQueryItem(name: "name", value: name)]
        // 名字里的加号要自己转（不转会被服务器读成空格）；先取出来再写回，一句里又读又写同一个变量编不过
        let query = comp?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        comp?.percentEncodedQuery = query
        guard let url = comp?.url else { return (false, "名字不对") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        guard let res = try? await AlcoveAPI.session.upload(for: req, from: data),
              let j = try? JSONSerialization.jsonObject(with: res.0) as? [String: Any] else { return (false, "没传上去") }
        if j.bool("ok") { return (true, "") }
        return (false, j.string("error").isEmpty ? "没传上去" : j.string("error"))
    }

    /// 一批放进同一个区，边传边说第几份
    func uploadBatch(_ items: [(data: Data, name: String)], folder: String) async {
        guard !items.isEmpty else { return }
        var bad: [String] = []
        for (i, it) in items.enumerated() {
            say(items.count == 1 ? "正在放进去…" : "正在放进去 \(i + 1) / \(items.count)…", hold: 0)
            let r = await upload(it.data, name: it.name, folder: folder)
            if !r.0 { bad.append(r.1) }
        }
        await load()
        if bad.isEmpty {
            say(items.count == 1 ? "放进「\(folder)」了" : "\(items.count) 份都放进「\(folder)」了")
        } else {
            say("\(bad.count) 份没放进去：\(bad[0])", hold: 4)
        }
    }

    /// 下到手机临时目录（同一份下过就不再下），用系统预览打开
    func open(_ f: BenchFile) async {
        guard opening.isEmpty else { return }
        opening = f.id
        defer { opening = "" }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bench-\(f.id)-\(f.size)", isDirectory: true)
        let dst = dir.appendingPathComponent(f.name)
        if !FileManager.default.fileExists(atPath: dst.path) {
            do {
                let (tmp, resp) = try await AlcoveAPI.session.download(from: AlcoveAPI.fullURL("/api/bench/file?id=\(f.id)"))
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { say("没下下来"); return }
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: dst)
                try FileManager.default.moveItem(at: tmp, to: dst)
            } catch {
                say("没下下来")
                return
            }
        }
        BenchQuickLook.shared.show(dst)
    }
}

/// 系统预览（表、Word、PDF、图都认，右上角能转发、存到「文件」）。从最上面那一页弹，套在弹单里也打得开
final class BenchQuickLook: NSObject, QLPreviewControllerDataSource {
    static let shared = BenchQuickLook()
    private var url: URL?

    @MainActor
    func show(_ url: URL) {
        self.url = url
        guard let win = FloatingOverlay.appWindow(), var top = win.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        let vc = QLPreviewController()
        vc.dataSource = self
        top.present(vc, animated: true)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { url == nil ? 0 : 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        (url ?? URL(fileURLWithPath: NSTemporaryDirectory())) as NSURL
    }
}

// MARK: 颜色（照效果图，黑夜是冷炭灰）

private struct BenchInk {
    let page: SanctusPageInk
    var dark: Bool { page.dark }
    private func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255, opacity: a) }
    /// 那张白纸、选中的标签
    var paper: Color { dark ? rgb(38, 38, 42) : .white }
    /// 没选中的标签
    var tabIdle: Color { dark ? Color.white.opacity(0.07) : rgb(214, 216, 222, 0.75) }
    var tabIdleText: Color { dark ? rgb(139, 143, 153) : rgb(125, 129, 140) }
    var edge: Color { dark ? Color.white.opacity(0.22) : rgb(150, 154, 164, 0.6) }
    var tile: Color { dark ? Color.white.opacity(0.05) : rgb(244, 245, 247) }
    var addFill: Color { dark ? Color.white.opacity(0.05) : Color.white.opacity(0.7) }
}

/// 1112 #5033 她：「背景直接跟着主聊天壁纸走」——铺聊天页那一张（她换壁纸、调模糊都跟着），不另外糊、不压白
private struct BenchBackdrop: View {
    let base: Color
    @ObservedObject private var wall = ChatWallpaperStore.shared
    var body: some View {
        ZStack {
            base
            ChatWallpaperRenderer(descriptor: wall.descriptor)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)     // 填满再裁的大图会挡点按，整层不接手指
    }
}

// MARK: 页面

struct BenchRoomView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = BenchStore()
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    @AppStorage("benchFolder") private var folder = "汉南"
    @State private var showAdd = false
    @State private var pickPhotos = false
    @State private var pickFiles = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var allKind: BenchAllKind?

    private var ink: SanctusPageInk { _ = houseAppearance; return SanctusPageInk() }
    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 0 }
    private var safeBottom: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.bottom ?? 0 }

    var body: some View {
        let ink = self.ink
        let b = BenchInk(page: ink)
        ZStack(alignment: .topLeading) {
            BenchBackdrop(base: ink.page)
            VStack(spacing: 0) {
                (Text("WORKBENCH · ").font(SanctusPageFont.corm(8.5)) + Text("工作台").font(.system(size: 8.5, design: .serif)))
                    .tracking(2.7).foregroundColor(ink.sub)
                    .frame(height: 44).frame(maxWidth: .infinity)
                    .padding(.top, max(safeTop, 20))
                titleBlock(ink)
                tabs(ink, b)
                    // 照片选择器、文件选择器、弹单各挂在不同的 view 上：挂同一个上只有一个生效（1103 旅行踩过）
                    .photosPicker(isPresented: $pickPhotos, selection: $photoItems, maxSelectionCount: 20, matching: .images)
                paper(ink, b)
                    .fileImporter(isPresented: $pickFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                        guard case .success(let urls) = result else { return }
                        Task { await addFiles(urls) }
                    }
                addButton(ink, b)
                footer(ink)
                    .padding(.bottom, max(safeBottom, 10) + 6)
            }
            SanctusBackButton(color: ink.link) { dismiss() }
                .padding(.top, max(safeTop, 20))
            toastLayer(ink)
        }
        .environment(\.sanctusInk, ink)
        .animation(.easeInOut(duration: 0.2), value: store.toast)
        .task { WindowFont.requestSongti(); await store.load() }
        .confirmationDialog("放到「\(folder)」", isPresented: $showAdd, titleVisibility: .visible) {
            Button("照片") { pickPhotos = true }
            Button("文件（表、Word、PDF）") { pickFiles = true }
            Button("算了", role: .cancel) {}
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            photoItems = []
            Task { await addPhotos(items) }
        }
        .sheet(item: $allKind) { kind in
            BenchAllSheet(kind: kind, folder: folder, store: store)
        }
    }

    // MARK: 头

    private func titleBlock(_ ink: SanctusPageInk) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("on my desk").font(SanctusPageFont.script(34)).foregroundColor(ink.title)
            (Text("kept here · ").font(SanctusPageFont.ital(12)) + Text("放进来就一直在").font(SanctusPageFont.cn(11.5)))
                .foregroundColor(ink.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 28)
        .padding(.top, 2)
    }

    private func tabs(_ ink: SanctusPageInk, _ b: BenchInk) -> some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(store.folders, id: \.self) { name in
                tab(name, ink, b)
            }
        }
        .frame(height: 48, alignment: .bottom)
        .padding(.horizontal, 16)
        .padding(.top, 20)
    }

    private func tab(_ name: String, _ ink: SanctusPageInk, _ b: BenchInk) -> some View {
        let on = name == folder
        let shape = UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 9, style: .continuous)
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) { folder = name }
        } label: {
            VStack(spacing: 1) {
                Text(name).font(SanctusPageFont.cn(on ? 13.5 : 12.5))
                    .foregroundColor(on ? ink.title : b.tabIdleText)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text("\(store.counts[name] ?? 0)").font(SanctusPageFont.ital(10))
                    .foregroundColor(on ? ink.script : ink.sub)
            }
            .frame(maxWidth: .infinity)
            .frame(height: on ? 48 : 40)
            .background(on ? b.paper : b.tabIdle, in: shape)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 白纸

    private func paper(_ ink: SanctusPageInk, _ b: BenchInk) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 14, bottomTrailingRadius: 14, topTrailingRadius: 0, style: .continuous)
        return Group {
            if store.loading {
                VStack { Spacer(); ProgressView().tint(ink.sub); Spacer() }.frame(maxWidth: .infinity)
            } else if store.failed {
                VStack(spacing: 10) {
                    Spacer()
                    Text("没连上").font(SanctusPageFont.cn(12)).foregroundColor(ink.sub)
                    Button { Task { store.loading = true; await store.load() } } label: {
                        Text("再试一次").font(SanctusPageFont.cn(12)).tracking(1.5).foregroundColor(ink.link)
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .overlay(Capsule().stroke(b.edge, lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        picsSection(ink, b)
                        SanctusHairline()
                        listSection(.sheet, ink, b)
                        SanctusHairline()
                        listSection(.doc, ink, b)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .padding(.bottom, 18)
                }
                .refreshable { await store.load() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(b.paper, in: shape)
        .clipShape(shape)
        .padding(.horizontal, 16)
    }

    private func mine(_ kind: String) -> [BenchFile] { store.files.filter { $0.folder == folder && $0.kind == kind } }

    private func sectionHead(_ cn: String, _ en: String, _ count: Int, link: String?, _ ink: SanctusPageInk, action: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(cn).font(SanctusPageFont.cn(13)).tracking(1.3).foregroundColor(ink.title)
            Text(en).font(SanctusPageFont.corm(8.5)).tracking(2.7).foregroundColor(ink.sub).padding(.leading, 8)
            Text("\(count)").font(SanctusPageFont.ital(11)).foregroundColor(ink.sub).padding(.leading, 6)
            Spacer(minLength: 0)
            if let link {
                Button(action: action) {
                    Text(link + " ›").font(SanctusPageFont.cn(11)).tracking(1.1).foregroundColor(ink.sub)
                        .padding(.vertical, 6).padding(.leading, 14).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func emptyLine(_ ink: SanctusPageInk) -> some View {
        (Text("nothing yet · ").font(SanctusPageFont.ital(11.5)) + Text("还没放").font(SanctusPageFont.cn(11)))
            .foregroundColor(ink.sub.opacity(0.8))
            .padding(.top, 2).padding(.bottom, 14)
    }

    private func picsSection(_ ink: SanctusPageInk, _ b: BenchInk) -> some View {
        let pics = mine("pic")
        let shown = Array(pics.prefix(4))
        // 底下那行小字：最新一张带备注的；都没备注就写最新那张
        let cap = pics.first { !$0.note.isEmpty } ?? pics.first
        return VStack(alignment: .leading, spacing: 0) {
            sectionHead("图", "PICTURES", pics.count, link: pics.isEmpty ? nil : "全部", ink) { allKind = .pic }
            if pics.isEmpty {
                emptyLine(ink)
            } else {
                HStack(spacing: 8) {
                    ForEach(shown) { f in
                        BenchThumb(file: f, side: 69, store: store)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 8)
                if let cap {
                    BenchCaption(file: cap)
                        .padding(.bottom, 12)
                }
            }
        }
    }

    private func listSection(_ kind: BenchAllKind, _ ink: SanctusPageInk, _ b: BenchInk) -> some View {
        let all = mine(kind.rawValue)
        let now = all.filter { !$0.isOld }
        let old = all.count - now.count
        let cap = kind == .sheet ? 4 : 3
        let shown = Array(now.prefix(cap))
        // 右上角那句：有旧版写「旧版 N」，没旧版但没列全写「全部」；点开都是这一块的整张单子
        let link: String? = old > 0 ? "旧版 \(old)" : (now.count > cap ? "全部" : nil)
        return VStack(alignment: .leading, spacing: 0) {
            sectionHead(kind.cn, kind.en, all.count, link: link, ink) { allKind = kind }
            if shown.isEmpty {
                emptyLine(ink)
            } else {
                ForEach(shown) { f in
                    BenchRow(file: f, store: store)
                }
                Color.clear.frame(height: 6)
            }
        }
    }

    // MARK: 底下

    private func addButton(_ ink: SanctusPageInk, _ b: BenchInk) -> some View {
        Button { showAdd = true } label: {
            HStack(spacing: 14) {
                Text("＋").font(SanctusPageFont.cn(15))
                Text("放文件进来").font(SanctusPageFont.cn(14)).tracking(2.8)
            }
            .foregroundColor(ink.body)
            .padding(.horizontal, 30)
            .frame(height: 38)
            .background(b.addFill, in: Capsule())
            .overlay(Capsule().stroke(b.edge, lineWidth: 0.8))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 14)
    }

    private func footer(_ ink: SanctusPageInk) -> some View {
        (Text("photos · sheets · word").font(SanctusPageFont.ital(11)) + Text("　放进来自己分好").font(SanctusPageFont.cn(10.5)))
            .foregroundColor(ink.sub)
            .padding(.top, 10)
    }

    private func toastLayer(_ ink: SanctusPageInk) -> some View {
        VStack {
            Spacer()
            if !store.toast.isEmpty {
                Text(store.toast).font(SanctusPageFont.cn(12)).foregroundColor(ink.page)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(ink.title.opacity(0.92)))
                    .padding(.bottom, max(safeBottom, 10) + 96)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }

    // MARK: 放进来

    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM.dd HH-mm"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai"); f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    /// 相册里的图：统一转成 JPEG 再传（HEIC 服务器和隅那边都不好读），原尺寸不缩
    private func addPhotos(_ items: [PhotosPickerItem]) async {
        let target = folder
        let when = Self.stamp.string(from: Date())
        var batch: [(data: Data, name: String)] = []
        store.say("正在取照片…", hold: 0)
        for (i, item) in items.enumerated() {
            guard let raw = try? await item.loadTransferable(type: Data.self) else { continue }
            let tail = items.count > 1 ? "-\(i + 1)" : ""
            if let ui = UIImage(data: raw), let jpg = ui.jpegData(compressionQuality: 0.9) {
                batch.append((jpg, "照片 \(when)\(tail).jpg"))
            } else {
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                batch.append((raw, "照片 \(when)\(tail).\(ext)"))
            }
        }
        if batch.isEmpty { store.say("照片没取出来"); return }
        await store.uploadBatch(batch, folder: target)
    }

    private func addFiles(_ urls: [URL]) async {
        let target = folder
        var batch: [(data: Data, name: String)] = []
        var unreadable = 0
        store.say("正在读文件…", hold: 0)
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                batch.append((data, url.lastPathComponent))
            } else {
                unreadable += 1
            }
        }
        if batch.isEmpty { store.say(unreadable > 0 ? "文件读不出来" : "没选文件"); return }
        await store.uploadBatch(batch, folder: target)
    }
}

// MARK: 零件

enum BenchAllKind: String, Identifiable {
    case pic, sheet, doc
    var id: String { rawValue }
    var cn: String { self == .pic ? "图" : (self == .sheet ? "表" : "文档") }
    var en: String { self == .pic ? "PICTURES" : (self == .sheet ? "SHEETS" : "WORD") }
}

private enum BenchEditKind: String, Identifiable {
    case note, name
    var id: String { rawValue }
}

/// 长按菜单（备注 / 改名 / 挪区 / 收进旧版 / 删掉）和它们要弹的东西，图和行共用
private struct BenchActions: ViewModifier {
    let file: BenchFile
    @ObservedObject var store: BenchStore
    @State private var edit: BenchEditKind?
    @State private var askDelete = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button { edit = .note } label: { Label(file.note.isEmpty ? "写备注" : "改备注", systemImage: "square.and.pencil") }
                Button { edit = .name } label: { Label("改名", systemImage: "character.cursor.ibeam") }
                Menu {
                    ForEach(store.folders.filter { $0 != file.folder }, id: \.self) { name in
                        Button(name) { Task { await store.edit(file.id, ["folder": name]) } }
                    }
                } label: { Label("挪到", systemImage: "folder") }
                if file.kind != "pic" {
                    Button { Task { await store.edit(file.id, ["old": !file.isOld]) } } label: {
                        Label(file.isOld ? "拿回来" : "收进旧版", systemImage: file.isOld ? "arrow.uturn.backward" : "archivebox")
                    }
                }
                Button(role: .destructive) { askDelete = true } label: { Label("删掉", systemImage: "trash") }
            }
            .confirmationDialog("删掉「\(file.stem)」？", isPresented: $askDelete, titleVisibility: .visible) {
                Button("删掉", role: .destructive) { Task { await store.delete(file.id) } }
                Button("留着", role: .cancel) {}
            }
            .sheet(item: $edit) { kind in
                if kind == .note {
                    BenchEditSheet(title: "备注", hint: "一句话，比如：CAD 上有，表里没有", text: file.note) { t in
                        Task { await store.edit(file.id, ["note": t]) }
                    }
                } else {
                    BenchEditSheet(title: "改名", hint: "新名字", text: file.stem) { t in
                        guard !t.isEmpty, t != file.stem else { return }
                        Task { await store.edit(file.id, ["name": t]) }
                    }
                }
            }
    }
}

/// 类型小卡：一张右上角折了一点的小纸，底下三个字母
private struct BenchExtCard: View {
    let label: String
    var width: CGFloat = 24
    var height: CGFloat = 29
    @Environment(\.sanctusInk) private var ink
    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 7, style: .continuous)
        Text(label).font(SanctusPageFont.corm(7)).tracking(0.8).foregroundColor(ink.script)
            .lineLimit(1).minimumScaleFactor(0.7)
            .padding(.bottom, 3)
            .frame(width: width, height: height, alignment: .bottom)
            .overlay(shape.stroke(BenchInk(page: ink).edge, lineWidth: 0.7))
    }
}

/// 一行文件：小卡 + 名字（最新版标签）+ 日期大小 + 备注
private struct BenchRow: View {
    let file: BenchFile
    @ObservedObject var store: BenchStore
    @Environment(\.sanctusInk) private var ink

    var body: some View {
        Button { Task { await store.open(file) } } label: {
            HStack(alignment: .top, spacing: 12) {
                BenchExtCard(label: file.extLabel)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(file.stem).font(SanctusPageFont.cn(13)).foregroundColor(ink.title)
                            .lineLimit(1).truncationMode(.middle)
                        if file.latest {
                            Text("最新版").font(SanctusPageFont.cn(10)).tracking(1).foregroundColor(ink.link)
                                .padding(.horizontal, 7).padding(.vertical, 1.5)
                                .overlay(Capsule().stroke(ink.sub.opacity(0.55), lineWidth: 0.6))
                                .fixedSize()
                        }
                    }
                    Text("\(file.dateText) · \(file.sizeText)").font(SanctusPageFont.corm(11)).tracking(0.4).foregroundColor(ink.sub)
                    if !file.note.isEmpty {
                        (Text("note — ").font(SanctusPageFont.ital(11)) + Text(file.note).font(SanctusPageFont.cn(11)))
                            .foregroundColor(ink.script)
                            .lineLimit(2)
                            .padding(.top, 1)
                    }
                }
                Spacer(minLength: 0)
                if store.opening == file.id {
                    ProgressView().controlSize(.mini).tint(ink.sub).padding(.top, 6)
                }
            }
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(BenchActions(file: file, store: store))
    }
}

/// 一张小方图（PDF、打不开的画成带字的小卡）；有备注的右上角一个小白点
private struct BenchThumb: View {
    let file: BenchFile
    let side: CGFloat
    @ObservedObject var store: BenchStore
    @Environment(\.sanctusInk) private var ink

    var body: some View {
        let b = BenchInk(page: ink)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button { Task { await store.open(file) } } label: {
            ZStack {
                if file.ext == "pdf" {
                    plain(b)
                } else {
                    AsyncImage(url: file.thumbURL) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        case .failure: plain(b)
                        default: b.tile
                        }
                    }
                }
                if store.opening == file.id {
                    Color.black.opacity(0.25)
                    ProgressView().controlSize(.small).tint(.white)
                }
            }
            .frame(width: side, height: side)
            .clipShape(shape)
            .overlay(shape.stroke(file.ext == "pdf" ? b.edge.opacity(0.8) : Color.clear, lineWidth: 0.7))
            .overlay(alignment: .topTrailing) {
                if !file.note.isEmpty {
                    Circle().fill(Color.white).frame(width: 6, height: 6)
                        .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 0.7))
                        .padding(5)
                }
            }
            // 填满再裁的图，点按范围不会跟着裁（1103 / 1112 都踩过），这里钉死成方块
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .modifier(BenchActions(file: file, store: store))
    }

    private func plain(_ b: BenchInk) -> some View {
        ZStack(alignment: .bottom) {
            b.tile
            Text(file.extLabel).font(SanctusPageFont.corm(8)).tracking(1.1).foregroundColor(ink.script)
                .padding(.bottom, 7)
        }
    }
}

/// 图底下那行小字：名字 · 日期　note — 备注
private struct BenchCaption: View {
    let file: BenchFile
    @Environment(\.sanctusInk) private var ink
    var body: some View {
        let head = Text("\(file.stem) · \(file.dateText)").font(SanctusPageFont.cn(10.5))
        let tail = file.note.isEmpty
            ? Text("")
            : Text("　note — ").font(SanctusPageFont.ital(11)) + Text(file.note).font(SanctusPageFont.cn(10.5))
        return (head + tail).foregroundColor(ink.sub).lineLimit(2)
    }
}

/// 备注 / 改名：一格字加一个「存下」
private struct BenchEditSheet: View {
    let title: String
    let hint: String
    @State var text: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    @FocusState private var focused: Bool

    var body: some View {
        let ink: SanctusPageInk = { _ = houseAppearance; return SanctusPageInk() }()
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(SanctusPageFont.cn(14, .medium)).tracking(2).foregroundColor(ink.title)
            TextField(hint, text: $text, axis: .vertical)
                .font(SanctusPageFont.cn(14)).foregroundColor(ink.body)
                .lineLimit(1...4)
                .focused($focused)
                .padding(12)
                .background(ink.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(ink.hair, lineWidth: 0.6))
            SanctusButton(title: "存下", primary: true) {
                onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
                dismiss()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .environment(\.sanctusInk, ink)
        .presentationDetents([.height(250)])
        .presentationBackground(ink.page)
        .preferredColorScheme(ink.dark ? .dark : .light)
        .onAppear { focused = true }
    }
}

/// 一块的整张单子：图是三列方格带名字；表、文档先列现在用的，再列旧版
private struct BenchAllSheet: View {
    let kind: BenchAllKind
    let folder: String
    @ObservedObject var store: BenchStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""

    private var mine: [BenchFile] { store.files.filter { $0.folder == folder && $0.kind == kind.rawValue } }

    var body: some View {
        let ink: SanctusPageInk = { _ = houseAppearance; return SanctusPageInk() }()
        let all = mine
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(folder) · \(kind.cn)").font(SanctusPageFont.cn(14, .medium)).tracking(2).foregroundColor(ink.title)
                Text("\(all.count)").font(SanctusPageFont.ital(12)).foregroundColor(ink.sub).padding(.leading, 8)
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Text("done").font(SanctusPageFont.ital(14)).foregroundColor(ink.link)
                        .padding(.vertical, 8).padding(.leading, 16).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 10)
            SanctusHairline().padding(.horizontal, 22)
            ScrollView(showsIndicators: false) {
                if kind == .pic {
                    grid(all, ink)
                } else {
                    list(all, ink)
                }
            }
        }
        .environment(\.sanctusInk, ink)
        .presentationDetents([.large])
        .presentationBackground(ink.dark ? Color(red: 38 / 255, green: 38 / 255, blue: 42 / 255) : Color.white)
        .preferredColorScheme(ink.dark ? .dark : .light)
    }

    private func grid(_ all: [BenchFile], _ ink: SanctusPageInk) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3), spacing: 16) {
            ForEach(all) { f in
                VStack(alignment: .leading, spacing: 5) {
                    BenchThumb(file: f, side: 100, store: store)
                    Text(f.stem).font(SanctusPageFont.cn(10.5)).foregroundColor(ink.body).lineLimit(2)
                    Text(f.dateText).font(SanctusPageFont.corm(10.5)).foregroundColor(ink.sub)
                }
                .frame(width: 100, alignment: .leading)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 30)
    }

    private func list(_ all: [BenchFile], _ ink: SanctusPageInk) -> some View {
        let now = all.filter { !$0.isOld }
        let old = all.filter { $0.isOld }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(now) { f in BenchRow(file: f, store: store) }
            if !old.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("旧版").font(SanctusPageFont.cn(12)).tracking(1.5).foregroundColor(ink.script)
                    Text("earlier").font(SanctusPageFont.ital(11.5)).foregroundColor(ink.sub)
                }
                .padding(.top, 18)
                .padding(.bottom, 4)
                SanctusHairline().padding(.bottom, 4)
                ForEach(old) { f in BenchRow(file: f, store: store) }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 30)
    }
}
