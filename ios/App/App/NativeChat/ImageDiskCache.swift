import SwiftUI
import CryptoKit

/// 0821 她要的「微信那样」的图片缓存：看过的图存进手机自己的存储
/// （Caches/alcove-images），下次直接从本地开，不再去服务器拉；
/// 设置页能看大小、按日期清、只留最近几天、全部清空。VPS 一个字节不多占。
final class ImageDiskCache {
    static let shared = ImageDiskCache()

    let dir: URL
    /// 0912 她要的：相册的图单独放一格，设置页那几个「清理」「清空」都不碰它。
    /// 放 Application Support 不放 Caches——Caches 在手机空间紧的时候系统会自己删；不进 iCloud 备份。
    let albumDir: URL
    private let mem = NSCache<NSURL, UIImage>()
    private var inflight: [URL: Task<UIImage?, Never>] = [:]
    private let lock = NSLock()

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = caches.appendingPathComponent("alcove-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var album = support.appendingPathComponent("alcove-album", isDirectory: true)
        try? FileManager.default.createDirectory(at: album, withIntermediateDirectories: true)
        var noBackup = URLResourceValues()
        noBackup.isExcludedFromBackup = true
        try? album.setResourceValues(noBackup)
        albumDir = album
        mem.countLimit = 400
        // 0828：只限张数不限字节的话，400 张原图解码开能吃掉几百 MB。
        // 按解码后的像素字节算账，超了 NSCache 自己踢旧的。
        mem.totalCostLimit = 128 * 1024 * 1024
    }

    /// 解码后的内存开销（RGBA 四字节一像素），给 NSCache 记账用
    private static func cost(of img: UIImage) -> Int {
        if let cg = img.cgImage { return cg.width * cg.height * 4 }
        return Int(img.size.width * img.scale * img.size.height * img.scale) * 4
    }

    private func memStore(_ img: UIImage, for url: URL) {
        mem.setObject(img, forKey: url as NSURL, cost: Self.cost(of: img))
    }

    // MARK: - 读

    static func isAlbum(_ url: URL) -> Bool { url.path.contains("/album/media/") }
    /// 1014 她：「表情包和相册的图片永远不会被清缓存」——表情包跟相册放同一格（albumDir），清理、清空都不碰
    static func isSticker(_ url: URL) -> Bool { url.path.hasPrefix("/stickers/") || url.path.hasPrefix("/api/stickers/") }
    static func isPinned(_ url: URL) -> Bool { isAlbum(url) || isSticker(url) }

    func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return (Self.isPinned(url) ? albumDir : dir).appendingPathComponent(name + ".img")
    }

    /// 只查内存、绝不碰磁盘——View 的 init（跑在主线程）只准用这个。
    /// 0828 体检抓的卡顿源：原来这里顺手读盘+解码，滚动列表每行首现都在主线程干重活。
    func memCached(_ url: URL) -> UIImage? {
        mem.object(forKey: url as NSURL)
    }

    /// 磁盘命中：读盘 + 解码 + 预解码位图。只在后台任务里调。
    private func diskLoad(_ url: URL) -> UIImage? {
        let f = fileURL(for: url)
        if Self.isPinned(url), !FileManager.default.fileExists(atPath: f.path) {
            // 0912 以前相册的图（1014 起加上表情包）混在 alcove-images 里：挪过来，别再下一遍
            try? FileManager.default.moveItem(at: dir.appendingPathComponent(f.lastPathComponent), to: f)
        }
        guard let data = try? Data(contentsOf: f), let img = UIImage(data: data) else { return nil }
        let ready = img.preparingForDisplay() ?? img
        memStore(ready, for: url)
        return ready
    }

    /// 内存 → 磁盘 → 网络，逐级找。读盘/解码/下载全在后台，同一个 URL 并发只下一次。
    func image(for url: URL) async -> UIImage? {
        if let hit = memCached(url) { return hit }
        lock.lock()
        if let running = inflight[url] {
            lock.unlock()
            return await running.value
        }
        let task: Task<UIImage?, Never> = Task.detached(priority: .userInitiated) { [self] in
            defer {
                lock.lock(); inflight[url] = nil; lock.unlock()
            }
            if let disk = diskLoad(url) { return disk }
            guard let (data, resp) = try? await URLSession.shared.data(from: url),
                  let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let img = UIImage(data: data) else { return nil }
            try? data.write(to: fileURL(for: url), options: .atomic)
            let ready = img.preparingForDisplay() ?? img
            memStore(ready, for: url)
            return ready
        }
        inflight[url] = task
        lock.unlock()
        return await task.value
    }

    /// 发图时顺手把原图落进缓存：自己发的图立刻能显示，不用再回服务器拉一遍
    func store(_ data: Data, for url: URL) {
        guard let img = UIImage(data: data) else { return }
        try? data.write(to: fileURL(for: url), options: .atomic)
        memStore(img, for: url)
    }

    /// 预热：还没存的才下，四个一起，不阻塞界面
    func prefetch(_ urls: [URL]) async {
        let todo = urls.filter { !FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
        guard !todo.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            var it = todo.makeIterator()
            for _ in 0..<4 {
                if let u = it.next() { group.addTask { _ = await self.image(for: u) } }
            }
            for await _ in group {
                if let u = it.next() { group.addTask { _ = await self.image(for: u) } }
            }
        }
    }

    /// 最近 N 天聊天里的图（缩略图那份，气泡里用的就是它），打开 app 时后台存好
    func prewarmRecent(days: Int) async {
        guard let obj = try? await AlcoveAPI.getRaw("/api/attachments/recent?days=\(days)"),
              let raw = obj["urls"] as? [String] else { return }
        await prefetch(raw.map { AlcoveAPI.attachmentThumbnailURL($0) })
    }

    // MARK: - 算账 / 清理

    private func entries() -> [(url: URL, size: Int64, date: Date)] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: Array(keys)) else { return [] }
        return files.compactMap { f in
            guard let v = try? f.resourceValues(forKeys: keys) else { return nil }
            return (f, Int64(v.fileSize ?? 0), v.contentModificationDate ?? .distantPast)
        }
    }

    func totalBytes() -> Int64 { entries().reduce(0) { $0 + $1.size } }
    func fileCount() -> Int { entries().count }
    func oldestDate() -> Date? { entries().map(\.date).min() }

    /// 清掉某天之前存的；传 nil 就是全部清。返回腾出来的字节数。
    /// 只扫 dir，相册和表情包那格（albumDir）不在账上也不在清理范围里。
    @discardableResult
    func clear(before cutoff: Date?) -> Int64 {
        var freed: Int64 = 0
        for e in entries() where cutoff == nil || e.date < cutoff! {
            if (try? FileManager.default.removeItem(at: e.url)) != nil { freed += e.size }
        }
        mem.removeAllObjects()
        return freed
    }

    @discardableResult
    func keepRecent(days: Int) -> Int64 {
        clear(before: Calendar.current.date(byAdding: .day, value: -days, to: Date()))
    }

    static func format(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}

// MARK: - 视图：跟 AsyncImage 同款用法，换个名字就行

enum CachedImagePhase {
    case empty
    case success(Image)
    case failure
}

/// `AsyncImage(url:) { img in } placeholder: { }` 的替身
struct CachedImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var ui: UIImage?

    init(url: URL?, @ViewBuilder content: @escaping (Image) -> Content,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        // init 跑在主线程：只摸内存缓存；磁盘/网络都交给 .task 在后台干
        _ui = State(initialValue: url.flatMap { ImageDiskCache.shared.memCached($0) })
    }

    var body: some View {
        Group {
            if let ui { content(Image(uiImage: ui)) } else { placeholder() }
        }
        // 0827：原来这里写的是 `guard let url, ui == nil`，
        // 于是 URL 换了、手里还攥着上一张图时就直接 return，图永远不换。
        // 信封的白天/黑夜两张就栽在这儿：她把开关掰过去，字色翻了，图还是黑的。
        .task(id: url) {
            guard let url else { ui = nil; return }
            if let hit = ImageDiskCache.shared.memCached(url) { ui = hit; return }
            ui = await ImageDiskCache.shared.image(for: url)
        }
    }
}

/// `AsyncImage(url:) { phase in switch phase … }` 的替身
struct CachedPhaseImage<Content: View>: View {
    let url: URL?
    @ViewBuilder var content: (CachedImagePhase) -> Content
    @State private var phase: CachedImagePhase

    init(url: URL?, @ViewBuilder content: @escaping (CachedImagePhase) -> Content) {
        self.url = url
        self.content = content
        // init 跑在主线程：只摸内存缓存；磁盘/网络都交给 .task 在后台干
        if let url, let hit = ImageDiskCache.shared.memCached(url) {
            _phase = State(initialValue: .success(Image(uiImage: hit)))
        } else {
            _phase = State(initialValue: .empty)
        }
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                guard let url else { phase = .empty; return }
                // 同上：URL 换了就得重新取，不能因为手里已有一张成功的图就跳过
                if let hit = ImageDiskCache.shared.memCached(url) {
                    phase = .success(Image(uiImage: hit)); return
                }
                if let img = await ImageDiskCache.shared.image(for: url) {
                    phase = .success(Image(uiImage: img))
                } else {
                    phase = .failure
                }
            }
    }
}
