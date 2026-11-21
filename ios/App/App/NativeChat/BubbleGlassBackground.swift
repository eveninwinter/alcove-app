import SwiftUI
import UIKit
import CoreImage

struct ChatWallpaperDescriptor {
    enum Source {
        case image(UIImage)
        case asset(String)
        case gradient([Color])
        case layeredPanel(
            preparedImage: UIImage?,
            asset: String,
            gradient: [Color],
            textureOpacity: Double
        )
    }

    let source: Source
}

@MainActor
final class ChatWallpaperStore: ObservableObject {
    /// 0925：聊天页用的这一份。房间页的毛玻璃底下铺同一张壁纸，借它读好的图，不再另读一遍。
    static let shared = ChatWallpaperStore()

    @Published private(set) var descriptor = ChatWallpaperDescriptor(
        source: .asset("ChatWall")
    )

    private var loadedKey = ""

    // nonisolated：纯查表，壁纸方案（WallSchemes，不在主线程类里）也要用它
    nonisolated static func fileName(for themeName: String) -> String {
        switch themeName {
        case "midnight": return "chatwall_midnight.jpg"
        case "paper": return "chatwall_paper.jpg"
        case "paper-dark": return "chatwall_paper_dark.jpg"
        case "imessage": return "chatwall_imessage.jpg"
        case "imessage-dark": return "chatwall_imessage_dark.jpg"
        case "kakao": return "chatwall_kakao.jpg"
        case "treehouse": return "chatwall_treehouse.jpg"
        case "treehouse-dark": return "chatwall_treehouse_dark.jpg"   // #3518 黑夜单独一格，她自己换的壁纸白天黑夜各管各的
        default: return "chatwall_haven.jpg"
        }
    }

    func refresh(themeName: String, theme: AlcoveTheme, wallStamp: Double) {
        let fileName = Self.fileName(for: themeName)
        // 1010 #3566：壁纸模糊度（设置里的滑杆）。糊在图上，不糊在视图上——玻璃气泡借的是同一张图，得一起糊
        // 1010 #3584 她：「模糊壁纸程度调节我希望所有主题都可以」——每一族主题各存各的值
        let thBlur = TreehouseWallBlur.value(for: themeName)
        let key = "\(themeName)|\(wallStamp)|\(fileName)|\(KakaoPackStore.shared.selectedID)|\(KakaoPackStore.shared.stamp)|\(thBlur)"
        guard key != loadedKey else { return }
        loadedKey = key

        let url = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent(fileName)

        if let image = UIImage(contentsOfFile: url.path) {
            if thBlur > 0 {
                applyBlurred(image, points: thBlur, key: key)
                return
            }
            image.prepareForDisplay { [weak self] prepared in
                Task { @MainActor in
                    guard self?.loadedKey == key else { return }
                    self?.descriptor = ChatWallpaperDescriptor(
                        source: .image(prepared ?? image)
                    )
                }
            }
        } else if theme.isKakao {
            // 0924 Kakao：壁纸是主题包里那张图；图还没下到就先铺包里的底色 / Kakao 原版的蓝灰
            if let wall = KakaoPackStore.shared.wallImage {
                if thBlur > 0 { applyBlurred(wall, points: thBlur, key: key) }
                else { descriptor = ChatWallpaperDescriptor(source: .image(wall)) }
            } else {
                let c = KakaoPackStore.shared.wallColor ?? Color(red: 0xB2/255, green: 0xC7/255, blue: 0xD9/255)
                descriptor = ChatWallpaperDescriptor(source: .gradient([c, c]))
            }
        } else if theme.isTreehouse {
            // 1009 树屋：她成品里那层字符画树 + 蓝蝴蝶 + 颗粒，原样渲成一张图；设置里换壁纸照样能盖掉
            let name = theme.isDark ? "ChatWallTreehouseNight" : "ChatWallTreehouse"
            if thBlur > 0, let image = UIImage(named: name) {
                applyBlurred(image, points: thBlur, key: key)
            } else {
                descriptor = ChatWallpaperDescriptor(source: .asset(name))
            }
        } else if theme.usesWallImage {
            if thBlur > 0, let image = UIImage(named: "ChatWall") { applyBlurred(image, points: thBlur, key: key) }
            else { descriptor = ChatWallpaperDescriptor(source: .asset("ChatWall")) }
        } else {
            descriptor = ChatWallpaperDescriptor(
                source: .gradient(theme.wallGradient)
            )
        }
    }
}

extension ChatWallpaperStore {
    /// 糊图放后台算，算完还是这把钥匙才换上（滑杆拖得快时，旧的那几张算完就扔）
    fileprivate func applyBlurred(_ image: UIImage, points: Double, key: String) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let out = TreehouseWallBlur.blurred(image, points: points)
            await MainActor.run {
                guard let self, self.loadedKey == key else { return }
                self.descriptor = ChatWallpaperDescriptor(source: .image(out))
            }
        }
    }
}

/// 1010 #3564–3566 她：树屋壁纸能调模糊度；蝴蝶和 UNDER THE GINKGO 跟着一起糊（她看完两版预览定的）。
/// 值是「屏幕上大约糊几个点」，0 = 不糊；预览图 /root/workroom/mock/wall-blur/。
enum TreehouseWallBlur {   // 名字是树屋时候起的；1010 #3584 起所有主题都用
    static let legacyKey = "treehouseWallBlur"    // 树屋那一格的老位置（迁移用）
    static let stampKey = "wallBlurStamp"         // 任何一族的值一变就换这个，聊天页 / 预览盯它重糊
    static func key(for themeName: String) -> String { "wallBlur." + AlcoveAppearance.family(of: themeName) }
    static func value(for themeName: String) -> Double {
        let d = UserDefaults.standard, k = key(for: themeName)
        let raw = (d.object(forKey: k) == nil && AlcoveAppearance.family(of: themeName) == "treehouse")
            ? d.double(forKey: legacyKey) : d.double(forKey: k)
        return max(0, min(12, raw))
    }
    static func set(_ v: Double, for themeName: String) {
        UserDefaults.standard.set(v, forKey: key(for: themeName))
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: stampKey)
    }
    private static let context = CIContext(options: nil)

    static func blurred(_ image: UIImage, points: Double) -> UIImage {
        guard points > 0.05, let cg = image.cgImage else { return image }
        // 壁纸铺满屏宽（约 390 点），按图的像素宽折算成像素半径
        let radius = points * Double(cg.width) / 390.0
        let input = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return image }
        // 先往外无限延伸边缘再糊、糊完裁回原尺寸：不然四周会糊出一圈发白 / 发黑的边
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let out = filter.outputImage?.cropped(to: input.extent),
              let cgOut = context.createCGImage(out, from: input.extent) else { return image }
        return UIImage(cgImage: cgOut, scale: image.scale, orientation: image.imageOrientation)
    }
}

struct ChatWallpaperRenderer: View {
    let descriptor: ChatWallpaperDescriptor

    var body: some View {
        GeometryReader { proxy in
            switch descriptor.source {
            case .image(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            case .asset(let name):
                Image(name)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            case .gradient(let colors):
                LinearGradient(
                    colors: colors,
                    startPoint: .top,
                    endPoint: .bottom
                )
            case .layeredPanel(
                let preparedImage,
                let asset,
                let gradient,
                let textureOpacity
            ):
                ZStack {
                    LinearGradient(
                        colors: gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    if let preparedImage {
                        Image(uiImage: preparedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                            .opacity(textureOpacity)
                    } else {
                        Image(asset)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                            .opacity(textureOpacity)
                    }
                }
            }
        }
    }
}

private struct ChatWallpaperDescriptorKey: EnvironmentKey {
    static let defaultValue = ChatWallpaperDescriptor(
        source: .asset("ChatWall")
    )
}

private struct ChatWallpaperViewportSizeKey: EnvironmentKey {
    static let defaultValue = CGSize(width: 1, height: 1)
}

/// 1016 #3933 毛玻璃气泡自己磨壁纸：壁纸在屏幕上的位置（全局坐标）。量不到就是 nil，气泡退回系统磨砂
private struct FrostedWallFrameKey: EnvironmentKey {
    static let defaultValue: CGRect? = nil
}

private struct ChatWallpaperViewportInsetKey: EnvironmentKey {
    static let defaultValue = CGSize.zero
}

extension EnvironmentValues {
    var chatWallpaperDescriptor: ChatWallpaperDescriptor {
        get { self[ChatWallpaperDescriptorKey.self] }
        set { self[ChatWallpaperDescriptorKey.self] = newValue }
    }

    var chatWallpaperViewportSize: CGSize {
        get { self[ChatWallpaperViewportSizeKey.self] }
        set { self[ChatWallpaperViewportSizeKey.self] = newValue }
    }


    var frostedWallFrame: CGRect? {
        get { self[FrostedWallFrameKey.self] }
        set { self[FrostedWallFrameKey.self] = newValue }
    }

    var chatWallpaperViewportInset: CGSize {
        get { self[ChatWallpaperViewportInsetKey.self] }
        set { self[ChatWallpaperViewportInsetKey.self] = newValue }
    }
}

extension View {
    /// 量这张壁纸在屏幕上的位置（毛玻璃气泡按它对位，见 FrostedWallLens）
    func measuresFrostedWall(_ frame: Binding<CGRect?>) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame.wrappedValue = $0 }
    }
}

// MARK: - 1120 #5800 壁纸方案
// 她：「壁纸那里加多重方案，方案一就是现在白色的壁纸，后面切粉色的，白色的留在方案一，名字自己能改，随意切换」。
// 每个主题格子（ChatWallpaperStore.fileName 那一格，树屋白天黑夜各一格）各存一串方案；一个方案＝一张图＋模糊度。
// 第一次打开把当时正在用的那张存成「方案一」。切换＝方案里的图拷回这一格的壁纸文件、模糊度写回、wallStamp 一跳，
// 聊天页那套读图的路一点不改。在某个方案上「从相册更换」/拉模糊/恢复默认，都记进当前这个方案。

struct WallScheme: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var blur: Double
    var hasImage: Bool      // false＝这个方案用的是主题自带的默认壁纸
    var look: Data? = nil   // 1121 #5893 她：方案要包含所有调节——字体字号间距、气泡颜色、Kakao 包这些（plist 存的那一组键）
}

enum WallSchemes {
    private static var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private static func slot(_ themeName: String) -> String {
        (ChatWallpaperStore.fileName(for: themeName) as NSString).deletingPathExtension
    }
    private static func dir(_ themeName: String) -> URL {
        let d = docs.appendingPathComponent("wallSchemes", isDirectory: true).appendingPathComponent(slot(themeName), isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private static func listKey(_ themeName: String) -> String { "wallSchemes." + slot(themeName) }
    private static func activeKey(_ themeName: String) -> String { "wallSchemes.active." + slot(themeName) }
    private static func wallURL(_ themeName: String) -> URL { docs.appendingPathComponent(ChatWallpaperStore.fileName(for: themeName)) }
    static func imageURL(_ id: String, _ themeName: String) -> URL { dir(themeName).appendingPathComponent(id + ".jpg") }

    static func list(_ themeName: String) -> [WallScheme] {
        if let data = UserDefaults.standard.data(forKey: listKey(themeName)),
           let items = try? JSONDecoder().decode([WallScheme].self, from: data), !items.isEmpty {
            return items
        }
        // 第一次：她现在用的这张就是方案一
        var first = WallScheme(id: UUID().uuidString, name: "方案一", blur: 0, hasImage: false)
        snapshot(&first, themeName)
        save([first], themeName)
        UserDefaults.standard.set(first.id, forKey: activeKey(themeName))
        return [first]
    }

    static func activeID(_ themeName: String) -> String? {
        UserDefaults.standard.string(forKey: activeKey(themeName))
    }

    private static func save(_ items: [WallScheme], _ themeName: String) {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: listKey(themeName)) }
    }

    /// 把这一格现在的壁纸（图＋模糊）存进方案
    private static func snapshot(_ s: inout WallScheme, _ themeName: String) {
        let fm = FileManager.default
        let dst = imageURL(s.id, themeName)
        try? fm.removeItem(at: dst)
        if fm.fileExists(atPath: wallURL(themeName).path) {
            s.hasImage = (try? fm.copyItem(at: wallURL(themeName), to: dst)) != nil
        } else {
            s.hasImage = false
        }
        s.blur = TreehouseWallBlur.value(for: themeName)
        s.look = captureLook(themeName)
    }

    // ── 1121 #5893 外观页上除了壁纸以外的调节 ──
    // 全局的（哪个主题都吃）＋这一族主题自己的；颜色只管眼下白天 / 黑夜那一套，免得切一个方案把另一边的颜色也冲掉
    private static let globalLookKeys = ["chatFontSize", "chatBubbleGap", "chatTurnGap", BubblePadV.key,
                                         "showClawdPet", KakaoPackStore.fontKey]

    private static let glassLookKeys = ["msgGlassFrost", "msgGlassKind", "msgGlassFog2"]

    private static func lookKeys(_ themeName: String) -> (exact: [String], prefixes: [String]) {
        let dark = MessagesPalette.isDark
        switch AlcoveAppearance.family(of: themeName) {
        // 1121 #5897 她：「气泡没有存在方案里面」——玻璃气泡那几样（透 / 雾、两条透明滑杆、我的 / 他的毛玻璃色）树屋也在用，上一版漏了
        case "treehouse":
            return (globalLookKeys + [MessagesPalette.thGlassKey, TreehouseBubbleMode.key] + glassLookKeys,
                    [dark ? "msgColorTreehouseNight." : "msgColorTreehouse.", "frostTint." + (dark ? "night." : "day.")])
        case "imessage":
            return (globalLookKeys + [MessagesPalette.glassKey] + glassLookKeys,
                    ["msgColor." + (dark ? "night." : "day."), "msgColorGlass." + (dark ? "night." : "day."),
                     "frostTint." + (dark ? "night." : "day.")])
        case "kakao":
            return (globalLookKeys + [KakaoPackStore.selectedKey, KakaoPackStore.usePackAvatarKey,
                                      KakaoPackStore.showAvatarKey, KakaoSendButton.key], [])
        default:
            return (globalLookKeys, [])
        }
    }

    private static let modeMark = "@mode"
    private static let exactMark = "@exact"
    private static let prefixMark = "@prefixes"

    private static func managedKeys(_ themeName: String) -> [String] {
        let (exact, prefixes) = lookKeys(themeName)
        let all = UserDefaults.standard.dictionaryRepresentation().keys
        return exact + all.filter { k in prefixes.contains { k.hasPrefix($0) } }
    }

    private static func captureLook(_ themeName: String) -> Data? {
        var dict: [String: Any] = [:]
        for k in managedKeys(themeName) {
            if let v = UserDefaults.standard.object(forKey: k) { dict[k] = v }
        }
        dict[modeMark] = MessagesPalette.isDark ? "night" : "day"
        let (exact, prefixes) = lookKeys(themeName)
        dict[exactMark] = exact          // 存的时候认识哪几样：换上时只清这些，后来新加的键不会被老方案当成默认清掉
        dict[prefixMark] = prefixes
        return try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
    }

    /// 方案里没存的键＝那时候是默认，换上时也清回默认
    private static func restoreLook(_ data: Data?, _ themeName: String) {
        guard let data,
              let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return }
        let d = UserDefaults.standard
        let oldPack = d.string(forKey: KakaoPackStore.selectedKey) ?? ""
        let oldFont = d.string(forKey: KakaoPackStore.fontKey) ?? ""
        // 存的时候是白天、现在是黑夜（或反过来）：颜色那组不动，只换全局和开关那几样
        let sameMode = (dict[modeMark] as? String) == (MessagesPalette.isDark ? "night" : "day")
        let marks: Set<String> = [modeMark, exactMark, prefixMark]
        let exact = Set(lookKeys(themeName).exact)
        let knewExact = Set(dict[exactMark] as? [String] ?? [])
        let knewPrefixes = dict[prefixMark] as? [String] ?? []
        var keys = Set(sameMode ? managedKeys(themeName) : lookKeys(themeName).exact)
        if sameMode { keys.formUnion(dict.keys.filter { !marks.contains($0) }) }
        for k in keys where sameMode || exact.contains(k) {
            if let v = dict[k] {
                d.set(v, forKey: k)
            } else if knewExact.contains(k) || knewPrefixes.contains(where: { k.hasPrefix($0) }) {
                d.removeObject(forKey: k)     // 存的时候是默认 → 清回默认
            }                                  // 存的时候还不认识这一样 → 不动
        }
        // Kakao 包和字体在 KakaoPackStore 里另有一份内存里的，走它自己的入口换，别只改了存的那份
        let store = KakaoPackStore.shared
        let pack = d.string(forKey: KakaoPackStore.selectedKey) ?? ""
        let font = d.string(forKey: KakaoPackStore.fontKey) ?? ""
        if pack != oldPack, !pack.isEmpty { d.set(oldPack, forKey: KakaoPackStore.selectedKey); store.select(pack) }
        if font != oldFont { d.set(oldFont, forKey: KakaoPackStore.fontKey); store.selectFont(font) }
        MessagesPalette.bump()
    }

    /// 切走之前：把眼下这一整套调节记进正在用的方案
    private static func saveActiveLook(_ themeName: String) {
        var items = list(themeName)
        guard let id = activeID(themeName), let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].look = captureLook(themeName)
        save(items, themeName)
    }

    /// 换图 / 恢复默认之后：记进当前方案
    static func syncActiveImage(_ themeName: String) {
        var items = list(themeName)
        guard let id = activeID(themeName), let i = items.firstIndex(where: { $0.id == id }) else { return }
        snapshot(&items[i], themeName)
        save(items, themeName)
    }

    /// 拉模糊之后：只记模糊度，不拷图
    static func syncActiveBlur(_ themeName: String) {
        var items = list(themeName)
        guard let id = activeID(themeName), let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].blur = TreehouseWallBlur.value(for: themeName)
        save(items, themeName)
    }

    static func apply(_ id: String, _ themeName: String) {
        if activeID(themeName) != id { saveActiveLook(themeName) }
        guard let s = list(themeName).first(where: { $0.id == id }) else { return }
        let fm = FileManager.default
        let wall = wallURL(themeName)
        try? fm.removeItem(at: wall)
        if s.hasImage { try? fm.copyItem(at: imageURL(id, themeName), to: wall) }
        TreehouseWallBlur.set(s.blur, for: themeName)
        restoreLook(s.look, themeName)
        UserDefaults.standard.set(id, forKey: activeKey(themeName))
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "wallStamp")
    }

    /// 新方案：先照着现在这张抄一份，切过去，她再从相册换成想要的
    @discardableResult
    static func add(_ themeName: String) -> WallScheme {
        saveActiveLook(themeName)
        var items = list(themeName)
        var s = WallScheme(id: UUID().uuidString, name: defaultName(items.count + 1), blur: 0, hasImage: false)
        snapshot(&s, themeName)
        items.append(s)
        save(items, themeName)
        UserDefaults.standard.set(s.id, forKey: activeKey(themeName))
        return s
    }

    static func rename(_ id: String, to name: String, _ themeName: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var items = list(themeName)
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].name = String(trimmed.prefix(12))
        save(items, themeName)
    }

    /// 删一个；最后一个不让删。删的是正在用的，就切到剩下的第一个
    static func remove(_ id: String, _ themeName: String) {
        var items = list(themeName)
        guard items.count > 1, let i = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: i)
        save(items, themeName)
        try? FileManager.default.removeItem(at: imageURL(id, themeName))
        if activeID(themeName) == id, let first = items.first { apply(first.id, themeName) }
    }

    private static func defaultName(_ n: Int) -> String {
        let cn = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        return "方案" + (n >= 1 && n <= 10 ? cn[n - 1] : String(n))
    }
}
