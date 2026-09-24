import SwiftUI
import UIKit
import CoreText

// 0924 她要的 Kakao 主题：布局照 KakaoTalk 聊天室，颜色和图从别人做好的主题包里来。
// 主题包由后端 kakao_theme.py 拆好，这边只认 /api/kakao/themes 那张表：
//   壁纸 wall.png、头像 profile.png、四张气泡 send1/send2/recv1/recv2.png（九宫格拉伸图）
//   + 每张气泡的拉伸点（cap_left / cap_top）和字离四边的距离（inset：上 左 下 右）
//   + 一组颜色（我的字 / 他的字 / 未读小 1 / 主色 / 输入框底）
// 换包不用重新构建：设置·外观 里点一下，包名存 UserDefaults，图片走 ImageDiskCache。

struct KakaoBubbleSpec: Decodable {
    let file: String
    let scale: Double
    let w: Double
    let h: Double
    let cap_left: Double
    let cap_top: Double
    let inset: [Double]
    let body_left: Double?     // 0924 晚：看得见的气泡左边离图片左边多少（后端量的），小按钮 / 思绪块按它对齐
    let body_edge: Double?     // 0925：气泡本体的左边（跳过站在左边的小人），没头像时他的截图 / 卡片按它对齐
    let body_top: Double?      // 0924 晚：图上下自带的空边 / 虚边（后端量的），用负边距扣掉，看得见的间距 = 她设的数
    let body_bottom: Double?

    /// 字离四边：上 左 下 右
    var textInsets: EdgeInsets {
        guard inset.count == 4 else { return EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14) }
        return EdgeInsets(top: inset[0], leading: inset[1], bottom: inset[2], trailing: inset[3])
    }
    /// 老 UIKit 的 leftCapWidth / topCapHeight：只有 cap 后面那一行一列会被拉，别的地方一个像素不变形
    var capInsets: EdgeInsets {
        EdgeInsets(top: cap_top, leading: cap_left,
                   bottom: max(0, h - cap_top - 1), trailing: max(0, w - cap_left - 1))
    }
}

struct KakaoPackColors: Decodable {
    let send_text: String
    let recv_text: String
    let unread: String
    let main: String
    let send_fg: String
    let button_fg: String
    let input_bg: String
    let header_text: String
    let main_bg: String
    let main_text: String
    let main_sub: String
}

struct KakaoPack: Decodable, Identifiable {
    let id: String
    let name: String
    let author: String?
    let source: String?
    let wall: String?
    let wall_scale: Double?
    let wall_color: String?
    let wall_avg: String?      // 壁纸平均色，侧边栏/设置页拿它当底色调
    let profile: String?
    let profile_color: String?
    let bubbles: [String: KakaoBubbleSpec]
    let colors: KakaoPackColors

    func url(_ file: String) -> URL {
        AlcoveAPI.fullURL("/api/kakao/themes/\(id)/\(file)")
    }
}

/// 0924 她递的字体：后端 /api/kakao/fonts 那张名单，ttf 下到 Application Support 后用 CoreText 当场注册，不用构建
struct KakaoFont: Decodable, Identifiable {
    let id: String
    let name: String
    let file: String
    let family: String?
    let ps_name: String?
    let size: Int?
    var url: URL { AlcoveAPI.fullURL("/api/kakao/fonts/\(file)") }
}

extension Color {
    /// "#986374" → Color；坏字符串给 fallback
    static func kakaoHex(_ hex: String?, _ fallback: Color) -> Color {
        guard let hex, let ui = UIColor.kakaoHex(hex) else { return fallback }
        return Color(uiColor: ui)
    }
}

extension UIColor {
    static func kakaoHex(_ hex: String) -> UIColor? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return UIColor(red: CGFloat((v >> 16) & 0xff) / 255,
                       green: CGFloat((v >> 8) & 0xff) / 255,
                       blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
}

/// 主题包仓库：列表从后端拉、选中的包名存 UserDefaults、图片按需下载后按 scale 重新包一层。
/// 不标 @MainActor —— AlcoveTheme.named("kakao") 在 view body 里同步读它的颜色，别把线程搅进来；
/// @Published 一律在主线程改。
final class KakaoPackStore: ObservableObject {
    static let shared = KakaoPackStore()
    static let selectedKey = "kakaoPackID"
    static let cacheKey = "kakaoPacksJSON"
    static let usePackAvatarKey = "kakaoUsePackAvatar"
    static let showAvatarKey = "kakaoShowAvatar"   // 0924 她要的：Kakao 下他的消息带不带头像
    static let fontKey = "kakaoFontID"
    static let thoughtFontID = "neozhisong"   // 0924 思绪用的宋体：架子上这一款，没打进包就自己下
    static let fontsCacheKey = "kakaoFontsJSON"

    @Published private(set) var fonts: [KakaoFont] = []
    @Published private(set) var selectedFontID: String = ""     // "" = 系统字
    @Published private(set) var fontLoading = false
    private var registeredFonts: [String: String] = [:]          // 字体 id → 注册后的 PostScript 名
    private var fontDownloading: Set<String> = []

    @Published private(set) var packs: [KakaoPack] = []
    @Published private(set) var selectedID: String
    /// 图片到位 / 换包 / 列表刷新都拨一下，聊天页和壁纸盯着它重画
    @Published private(set) var stamp: Double = 0
    @Published private(set) var loading = false
    @Published private(set) var lastError: String? = nil

    private var images: [String: UIImage] = [:]
    private var loadingKeys: Set<String> = []

    private init() {
        selectedID = UserDefaults.standard.string(forKey: Self.selectedKey) ?? ""
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let list = try? JSONDecoder().decode([KakaoPack].self, from: data) {
            packs = list
        }
        if selectedID.isEmpty, let first = packs.first { selectedID = first.id }
        selectedFontID = UserDefaults.standard.string(forKey: Self.fontKey) ?? ""
        if let data = UserDefaults.standard.data(forKey: Self.fontsCacheKey),
           let list = try? JSONDecoder().decode([KakaoFont].self, from: data) {
            fonts = list
        }
        ensureFont()   // 本地已经有文件就当场注册，开门第一帧就是那个字
        ensureFont(id: Self.thoughtFontID)
    }

    // MARK: 字体

    /// 选中字体注册好之后的 PostScript 名；没选 / 还没下到 → nil（用系统字）
    var fontName: String? {
        guard !selectedFontID.isEmpty else { return nil }
        return registeredName(selectedFontID)
    }
    /// 0924 她要的：字体打包进 App 之后，装上就有——先看进程里已经有没有这个字（Info.plist UIAppFonts 那些），有就直接用
    func registeredName(_ fontID: String) -> String? {
        if let n = registeredFonts[fontID] { return n }
        if let f = fonts.first(where: { $0.id == fontID }), let ps = f.ps_name, !ps.isEmpty,
           UIFont(name: ps, size: 12) != nil {
            registeredFonts[fontID] = ps
            return ps
        }
        return nil
    }
    func chatFont(_ size: CGFloat) -> Font {
        fontName.map { Font.custom($0, fixedSize: size) } ?? .system(size: size)
    }

    func selectFont(_ id: String) {
        guard id != selectedFontID else { return }
        selectedFontID = id
        UserDefaults.standard.set(id, forKey: Self.fontKey)
        bump()
        ensureFont()
    }

    private static var fontsDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("kakao_fonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// 用 CoreText 把文件注册进本进程，返回 PostScript 名（重复注册会报错，忽略，名字照样能取）
    private static func register(_ url: URL) -> String? {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        guard let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let d = descs.first else { return nil }
        return CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute) as? String
    }

    /// 选中的字体：本地有就注册，没有就下载再注册；每次都拨 stamp 让界面重画
    func ensureFont(id: String? = nil) {
        let fid = id ?? selectedFontID
        guard !fid.isEmpty, registeredName(fid) == nil,
              let font = fonts.first(where: { $0.id == fid }) else { return }
        let local = Self.fontsDir.appendingPathComponent(font.file)
        if FileManager.default.fileExists(atPath: local.path) {
            if let name = Self.register(local) {
                registeredFonts[font.id] = name
                bump()
                return
            }
            try? FileManager.default.removeItem(at: local)   // 坏文件，重新下
        }
        guard !fontDownloading.contains(font.id) else { return }
        fontDownloading.insert(font.id)
        DispatchQueue.main.async { self.fontLoading = true }
        Task {
            defer { DispatchQueue.main.async { self.fontDownloading.remove(font.id); self.fontLoading = false } }
            guard let (data, resp) = try? await URLSession.shared.data(from: font.url),
                  let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  data.count > 1024 else { return }
            try? data.write(to: local, options: .atomic)
            await MainActor.run {
                if let name = Self.register(local) {
                    self.registeredFonts[font.id] = name
                    self.stamp = Date().timeIntervalSince1970
                }
            }
        }
    }

    var current: KakaoPack? {
        packs.first { $0.id == selectedID } ?? packs.first
    }

    func select(_ id: String) {
        guard id != selectedID else { return }
        selectedID = id
        UserDefaults.standard.set(id, forKey: Self.selectedKey)
        bump()
        warm()
    }

    private func bump() {
        if Thread.isMainThread { stamp = Date().timeIntervalSince1970 }
        else { DispatchQueue.main.async { self.stamp = Date().timeIntervalSince1970 } }
    }

    /// 拉一遍列表；拉不到就用上次存的
    func refresh() {
        if Thread.isMainThread { loading = true } else { DispatchQueue.main.async { self.loading = true } }
        Task {
            defer { DispatchQueue.main.async { self.loading = false } }
            do {
                let obj = try await AlcoveAPI.getRaw("/api/kakao/themes")
                guard let raw = obj["themes"] else { return }
                let data = try JSONSerialization.data(withJSONObject: raw)
                let list = try JSONDecoder().decode([KakaoPack].self, from: data)
                var fontList: [KakaoFont] = []
                var fontData: Data? = nil
                if let rawFonts = obj["fonts"], let fd = try? JSONSerialization.data(withJSONObject: rawFonts),
                   let fl = try? JSONDecoder().decode([KakaoFont].self, from: fd) {
                    fontList = fl; fontData = fd
                }
                await MainActor.run {
                    self.packs = list
                    UserDefaults.standard.set(data, forKey: Self.cacheKey)
                    if let fontData {
                        self.fonts = fontList
                        UserDefaults.standard.set(fontData, forKey: Self.fontsCacheKey)
                        self.ensureFont()
                        self.ensureFont(id: Self.thoughtFontID)
                    }
                    if self.current == nil, let first = list.first { self.selectedID = first.id }
                    self.lastError = nil
                    self.stamp = Date().timeIntervalSince1970
                    self.warm()   // 字典只在主线程碰
                }
            } catch {
                await MainActor.run { self.lastError = "\(error)" }
            }
        }
    }

    /// 把当前包的壁纸、头像、四张气泡先拉下来
    func warm() {
        guard let pack = current else { return }
        var files: [(String, Double)] = []
        if let w = pack.wall { files.append((w, pack.wall_scale ?? 1)) }
        if let p = pack.profile { files.append((p, 3)) }
        for (_, b) in pack.bubbles { files.append((b.file, b.scale)) }
        for (f, s) in files { _ = image(pack: pack, file: f, scale: s) }
    }

    /// 同步拿：有就给，没有就触发下载、先返回 nil，下载完拨 stamp 让界面重画
    func image(pack: KakaoPack, file: String, scale: Double) -> UIImage? {
        let key = "\(pack.id)/\(file)"
        if let hit = images[key] { return hit }
        guard !loadingKeys.contains(key) else { return nil }
        loadingKeys.insert(key)
        let url = pack.url(file)
        Task {
            let fetched = await ImageDiskCache.shared.image(for: url)
            var scaled: UIImage? = nil
            if let img = fetched, let cg = img.cgImage {
                scaled = UIImage(cgImage: cg, scale: CGFloat(max(scale, 1)), orientation: .up)
            } else {
                scaled = fetched
            }
            await MainActor.run {
                self.loadingKeys.remove(key)
                if let scaled {
                    self.images[key] = scaled
                    self.stamp = Date().timeIntervalSince1970
                }
            }
        }
        return nil
    }

    func image(_ file: String?, scale: Double) -> UIImage? {
        guard let pack = current, let file else { return nil }
        return image(pack: pack, file: file, scale: scale)
    }

    var wallImage: UIImage? {
        guard let pack = current, let wall = pack.wall else { return nil }
        return image(pack: pack, file: wall, scale: pack.wall_scale ?? 1)
    }
    var wallColor: Color? {
        guard let pack = current, let c = pack.wall_color else { return nil }
        return Color.kakaoHex(c, .white)
    }
    var profileImage: UIImage? {
        guard let pack = current, let p = pack.profile else { return nil }
        return image(pack: pack, file: p, scale: 3)
    }
    var unreadColor: Color { Color.kakaoHex(current?.colors.unread, Color(red: 0.55, green: 0.12, blue: 0.12)) }
}

extension AlcoveTheme {
    /// 0924 她要的：抽屉（侧边栏）和设置页跟着 Kakao 主题包走——底色取壁纸的平均色，白天往白里调、黑夜往黑里调，换包跟着变
    static func kakaoPanel(dark: Bool) -> AlcoveTheme {
        let base = panelNamed(dark ? "midnight" : "haven")
        let pack = KakaoPackStore.shared.current
        guard let hex = pack?.wall_avg ?? pack?.wall_color, let avg = UIColor.kakaoHex(hex) else { return base }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        avg.getRed(&r, green: &g, blue: &b, alpha: &a)
        func mix(_ t: CGFloat, toWhite: Bool) -> Color {
            let k: CGFloat = toWhite ? 1 : 0
            return Color(red: Double(r + (k - r) * t), green: Double(g + (k - g) * t), blue: Double(b + (k - b) * t))
        }
        let main = Color.kakaoHex(pack?.colors.main, base.fyAccent)
        if dark {
            return base.panelCopy(
                splashBg: [mix(0.70, toWhite: false).opacity(0.92), mix(0.62, toWhite: false).opacity(0.90), mix(0.76, toWhite: false).opacity(0.94)],
                text: Color(red: 232/255, green: 237/255, blue: 244/255),
                textDim: Color(red: 205/255, green: 215/255, blue: 228/255),
                textLight: Color(red: 160/255, green: 174/255, blue: 191/255),
                accent: mix(0.45, toWhite: true),
                accentSoft: Color.white.opacity(0.24),
                card: mix(0.45, toWhite: false).opacity(0.48),
                cardSub: Color.white.opacity(0.075),
                border: Color.white.opacity(0.30),
                shadow: Color.black.opacity(0.42),
                textureAsset: "WetGlassMidnight")
        }
        return base.panelCopy(
            splashBg: [mix(0.72, toWhite: true).opacity(0.80), mix(0.62, toWhite: true).opacity(0.74), mix(0.68, toWhite: true).opacity(0.78)],
            text: Color(red: 26/255, green: 25/255, blue: 29/255),
            textDim: Color(red: 47/255, green: 48/255, blue: 55/255),
            textLight: Color(red: 91/255, green: 92/255, blue: 101/255),
            accent: mix(0.35, toWhite: false),
            accentSoft: main.opacity(0.30),
            card: Color.white.opacity(0.52),
            cardSub: Color.white.opacity(0.36),
            border: Color.white.opacity(0.60),
            shadow: mix(0.30, toWhite: false).opacity(0.18),
            textureAsset: "WetGlassHaven")
    }

    /// Kakao 家族：挂在「信息」那套骨架上（纯色底 / 顶栏 / 浮动输入框都现成），
    /// 只换颜色 —— 壁纸和气泡是图，在 ChatWallpaperStore 和 KakaoBubbleView 里贴。
    static func kakaoTheme() -> AlcoveTheme {
        let c = KakaoPackStore.shared.current?.colors
        let main = Color.kakaoHex(c?.main, Color(red: 0xF7/255, green: 0xE6/255, blue: 0x00/255))
        let ink = Color.kakaoHex(c?.main_text, Color(red: 0.22, green: 0.22, blue: 0.22))
        let sub = Color.kakaoHex(c?.main_sub, Color(red: 0.49, green: 0.46, blue: 0.46))
        let inputBg = Color.kakaoHex(c?.input_bg, .white)
        var copy = AlcoveTheme(
            isDark: false, isPaper: false, usesWallImage: false,
            wallGradient: [inputBg, inputBg],
            bubbleUser: main, bubbleAI: .white,
            text: ink, textDim: sub, textLight: sub.opacity(0.8), timestamp: sub,
            glassTint: inputBg, glassBorder: Color.black.opacity(0.08),
            capsuleTint: inputBg, capsuleBorder: Color.black.opacity(0.08),
            sendTop: main, sendBottom: main,
            fade: inputBg, splashBg: [inputBg, inputBg],
            splashBarTop: main, splashBarBottom: main.opacity(0.8),
            splashGlowA: .clear, splashGlowB: .clear,
            splashPetal: main.opacity(0.3), splashTitle: main,
            fyAccent: main, fyAccentSoft: main.opacity(0.14), fyCard: inputBg,
            fyCardSub: Color(red: 242/255, green: 242/255, blue: 247/255),
            fyBorder: Color.black.opacity(0.08),
            fyShadow: Color.black.opacity(0.05),
            fyFold: Color.black.opacity(0.08), fyDash: sub.opacity(0.3),
            panelTextureAsset: "PaperLight")
        copy.isMessages = true
        copy.isKakao = true
        copy.textUser = Color.kakaoHex(c?.send_text, Color(red: 0.23, green: 0.23, blue: 0.23))
        copy.textAI = Color.kakaoHex(c?.recv_text, Color(red: 0.21, green: 0.21, blue: 0.21))
        copy.thought = sub
        copy.divider = sub
        return copy
    }
}

/// 九宫格气泡：图从包里来，四个角不变形、中间随字数拉。
/// first = 这一串消息的第一条（Kakao 的 01 图，带尾巴 / 带小人），后面几条用 02 图。
struct KakaoBubbleView<Content: View>: View {
    let isUser: Bool
    let first: Bool
    @ObservedObject var store = KakaoPackStore.shared
    @ViewBuilder let content: () -> Content

    var body: some View {
        let key = isUser ? (first ? "send1" : "send2") : (first ? "recv1" : "recv2")
        let pack = store.current
        let spec = pack?.bubbles[key] ?? pack?.bubbles[isUser ? "send1" : "recv1"]
        Group {
            if let pack, let spec, let img = store.image(pack: pack, file: spec.file, scale: spec.scale) {
                content()
                    .padding(spec.textInsets)
                    .frame(minWidth: spec.w, minHeight: spec.h, alignment: .topLeading)
                    .background(
                        Image(uiImage: img)
                            .resizable(capInsets: spec.capInsets, resizingMode: .stretch)
                    )
                    // 0924 晚她定的「所有主题都按我设的间距」：图上下那圈空边 / 晕开的虚边不算进排版高度，
                    // 图照样整张画出来，只是排版上从看得见的边算起
                    .padding(.top, -CGFloat(spec.body_top ?? 0))
                    .padding(.bottom, -CGFloat(spec.body_bottom ?? 0))
            } else {
                // 包还没到 / 没这张图：Kakao 原版的黄白泡兜底
                content()
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isUser ? Color(red: 0xF7/255, green: 0xE6/255, blue: 0x00/255) : .white)
                    )
            }
        }
    }
}

/// 他的头像：包里的默认头像优先，没有就用她给他设的那张；一串消息只有第一条露脸，后面留位
struct KakaoAvatarView: View {
    let visible: Bool
    @ObservedObject var store = KakaoPackStore.shared
    @AppStorage("assistantAvatarDataURL") var assistantAvatar = ""
    // 0924 她问能不能换头像：开着用包里自带的（兔子、吉伊），关了用她在设置里给他挑的那张
    @AppStorage(KakaoPackStore.usePackAvatarKey) var usePackAvatar = true

    var body: some View {
        let mine = Self.decode(assistantAvatar)
        Group {
            if visible {
                if !usePackAvatar, let img = mine {
                    Image(uiImage: img).resizable().scaledToFill()
                } else if let img = store.profileImage {
                    Image(uiImage: img).resizable().scaledToFill()
                } else if let img = mine {
                    Image(uiImage: img).resizable().scaledToFill()
                } else if let c = store.current?.profile_color {
                    Color.kakaoHex(c, Color(red: 0.9, green: 0.85, blue: 0.6))
                } else {
                    Color(red: 0.9, green: 0.85, blue: 0.6)
                }
            } else {
                Color.clear
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private static func decode(_ value: String) -> UIImage? {
        guard !value.isEmpty else { return nil }
        let payload = value.split(separator: ",", maxSplits: 1).last.map(String.init) ?? value
        return Data(base64Encoded: payload).flatMap(UIImage.init(data:))
    }
}

/// Kakao 的日期分隔：居中一颗半透明深色胶囊，写「2026年9月24日 星期四」
struct KakaoDateDivider: View {
    let date: Date
    var body: some View {
        // 0924 她定的：胶囊不变，里面的字跟信息主题一样（「今天 20:32」那种：相对日期 + 时间）
        HStack(spacing: 4) {
            Text(MessagesTimeDivider.dayFmt.string(from: date)).fontWeight(.semibold)
            Text(MessagesTimeDivider.timeFmt.string(from: date))
        }
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.92))
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Color.black.opacity(0.22), in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }
    static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 EEEE"
        return f
    }()
}

enum KakaoClock {
    /// 0925 她要的：24 小时制「00:18」，不要「上午 12:18」（原来是 Kakao 那种「下午 3:24」）
    static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()
}

/// 设置·外观 里的主题包选择条：一排壁纸缩略图，点哪个换哪个，不用重新构建
struct KakaoPackPicker: View {
    let theme: AlcoveTheme
    @ObservedObject var store = KakaoPackStore.shared
    // 0924 她报的「换了主题包聊天页没变」：她只点了包没点上面的 Kakao 按钮。点包就等于选 Kakao 家族，一步到位
    @AppStorage("alcoveTheme") var themeName = "haven"
    @AppStorage(KakaoPackStore.usePackAvatarKey) var usePackAvatar = true
    @AppStorage(KakaoPackStore.showAvatarKey) var showAvatar = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 0924 她要的预览（选中那套的壁纸 + 一来一回两条真气泡）0925 挪到外观页最上面那块了
            if store.packs.isEmpty {
                HStack(spacing: 8) {
                    if store.loading { ProgressView().scaleEffect(0.7) }
                    Text(store.loading ? "在拉主题包…" : (store.lastError == nil ? "还没有主题包" : "拉不到主题包，等会再试"))
                        .font(.system(size: 12)).foregroundColor(theme.textDim)
                }
            } else {
                // 0925 她说「太多套了左滑看不过来」：横条改成一排 4 个的格子，往下排，一眼看完
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                    ForEach(store.packs) { pack in
                        Button {
                            store.select(pack.id)
                            if themeName != "kakao" { themeName = "kakao" }
                        } label: {
                            VStack(spacing: 6) {
                                Color.clear
                                    .aspectRatio(1, contentMode: .fit)   // 0925 她要正方形，长条太占位子
                                    .overlay(thumb(pack))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(pack.id == store.selectedID ? theme.fyAccent : theme.fyBorder,
                                                lineWidth: pack.id == store.selectedID ? 2 : 1))
                                Text(pack.name)
                                    .font(.system(size: 10.5))
                                    .foregroundColor(pack.id == store.selectedID ? theme.text : theme.textDim)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            Toggle(isOn: $showAvatar) {
                Text("他的消息带头像")
                    .font(.system(size: 12)).foregroundColor(theme.text)
            }
            .tint(theme.fyAccent)
            if showAvatar {
            Toggle(isOn: $usePackAvatar) {
                Text("他的头像用包里自带的")
                    .font(.system(size: 12)).foregroundColor(theme.text)
            }
            .tint(theme.fyAccent)
            }
            Text(usePackAvatar ? "关掉就用你在「他的头像」里给他挑的那张" : "现在用的是你给他挑的那张，没挑就回落到包里的")
                .font(.system(size: 10.5)).foregroundColor(theme.textLight)
            HStack {
                Text("发我一个主题包链接就能多一套")
                    .font(.system(size: 10.5)).foregroundColor(theme.textLight)
                Spacer()
                Button { store.refresh() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
                        Text("刷新").font(.system(size: 11))
                    }
                    .foregroundColor(theme.fyAccent)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { if store.packs.isEmpty { store.refresh() } }
    }

    @ViewBuilder private func thumb(_ pack: KakaoPack) -> some View {
        if let wall = pack.wall, let img = store.image(pack: pack, file: wall, scale: pack.wall_scale ?? 1) {
            Image(uiImage: img).resizable().scaledToFill()
        } else if let c = pack.wall_color {
            Color.kakaoHex(c, .white)
        } else {
            Color(red: 0.93, green: 0.93, blue: 0.95)
        }
    }
}

/// 主题包预览：壁纸铺底，他一条（头像 + 名字 + 01 图）、她一条（01 图 + 小「1」+ 时间），
/// 全走聊天页那几个零件，所见即所得
struct KakaoPackPreview: View {
    @ObservedObject var store = KakaoPackStore.shared
    @AppStorage(KakaoPackStore.showAvatarKey) var showAvatar = true

    var body: some View {
        let t = AlcoveTheme.kakaoTheme()
        let name = UserDefaults.standard.string(forKey: "assistantName") ?? "陈璟"
        ZStack {
            // 0924 她报的「Kakao 按钮和字体栏点不动」：scaledToFill 的壁纸图会撑出 230 那个框，看不见但吃触摸，
            // 把上面的兄弟视图全盖住。这里按框的尺寸硬裁，整块预览也不吃触摸。
            GeometryReader { g in
                if let wall = store.wallImage {
                    Image(uiImage: wall).resizable().scaledToFill()
                        .frame(width: g.size.width, height: g.size.height).clipped()
                } else {
                    (store.wallColor ?? Color(red: 0xB2/255, green: 0xC7/255, blue: 0xD9/255))
                }
            }
            VStack(spacing: 10) {
                KakaoDateDivider(date: Date()).padding(.vertical, -6)
                HStack(alignment: .top, spacing: 8) {
                    if showAvatar { KakaoAvatarView(visible: true) }
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .bottom, spacing: 5) {
                            KakaoBubbleView(isUser: false, first: true) {
                                Text("今天想吃什么")
                                    .font(store.chatFont(14)).foregroundColor(t.textAI ?? t.text)
                            }
                            Text(KakaoClock.fmt.string(from: Date()))
                                .font(.system(size: 10)).foregroundColor(t.timestamp).padding(.bottom, 2)
                        }
                    }
                    Spacer(minLength: 24)
                }
                HStack(alignment: .bottom, spacing: 5) {
                    Spacer(minLength: 48)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("1").font(.system(size: 10, weight: .medium)).foregroundColor(store.unreadColor)
                        Text(KakaoClock.fmt.string(from: Date()))
                            .font(.system(size: 10)).foregroundColor(t.timestamp)
                    }
                    .padding(.bottom, 2)
                    KakaoBubbleView(isUser: true, first: true) {
                        Text("你做的都行")
                            .font(store.chatFont(14)).foregroundColor(t.textUser ?? t.text)
                    }
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Color.black.opacity(0.08), lineWidth: 0.6))
        .allowsHitTesting(false)   // 纯预览，不吃触摸
    }
}

/// 0924 她定的：字体是全局的，哪个聊天主题都吃。设置·外观 里单独一栏「字体」，
/// 选了就下载注册，聊天正文、工作室、Kakao 预览一起换字；「系统」= 不动。
struct ChatFontPicker: View {
    let theme: AlcoveTheme
    @ObservedObject var store = KakaoPackStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if store.fontLoading {
                    ProgressView().scaleEffect(0.6)
                    Text("在下字体…").font(.system(size: 11)).foregroundColor(theme.textDim)
                }
                Spacer()
                Button { store.refresh() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
                        Text("刷新").font(.system(size: 11))
                    }
                    .foregroundColor(theme.fyAccent)
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    fontChip(id: "", label: "系统", font: .system(size: 13))
                    ForEach(store.fonts) { f in
                        fontChip(id: f.id, label: f.name,
                                 font: store.registeredName(f.id).map { Font.custom($0, fixedSize: 13) } ?? .system(size: 13))
                    }
                }
            }
        }
        .onAppear { if store.fonts.isEmpty { store.refresh() } }
    }

    private func fontChip(id: String, label: String, font: Font) -> some View {
        let on = store.selectedFontID == id
        return Button { store.selectFont(id) } label: {
            Text(label).font(font).foregroundColor(on ? theme.text : theme.textDim)
                .padding(.horizontal, 13).padding(.vertical, 8)
                .background(on ? theme.fyAccent.opacity(0.18) : theme.fyCardSub, in: Capsule())
                .overlay(Capsule().stroke(on ? theme.fyAccent : theme.fyBorder, lineWidth: on ? 1.4 : 0.8))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 0924 她要的：思绪里的字用衬线宋体的斜体。宋体用架子上打包进 App 的「霞鹜新致宋」（LXGWNeoZhiSong），
/// 没打进来就退到系统衬线；斜体是 SwiftUI 合成的斜。
enum ThoughtFont {
    static let songPostScript = "LXGWNeoZhiSong"
    /// 注册好的名字：打包进 App 的直接有；没打进来就让仓库去下（下完拨 stamp 重画）
    static var registeredName: String? {
        KakaoPackStore.shared.registeredName(KakaoPackStore.thoughtFontID)
    }
    static func font(_ size: CGFloat) -> Font {
        if let n = registeredName { return Font.custom(n, fixedSize: size).italic() }
        KakaoPackStore.shared.ensureFont(id: KakaoPackStore.thoughtFontID)
        return Font.system(size: size, design: .serif).italic()
    }
}

/// 0924 她抓的：SwiftUI 的 .italic() 只斜英文，中文字形没有斜体版就原样站着。
/// 这里走 UIKit 的 obliqueness（按字形剪切），中文也真斜；字体用打包的霞鹜新致宋。
struct ObliqueText: UIViewRepresentable {
    let text: String
    let size: CGFloat
    let color: UIColor
    var lineSpacing: CGFloat = 0
    var slant: CGFloat = 0.22

    func makeUIView(context: Context) -> UILabel {
        let l = UILabel()
        l.numberOfLines = 0
        l.lineBreakMode = .byWordWrapping
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        l.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return l
    }

    func updateUIView(_ l: UILabel, context: Context) {
        var font = UIFont.systemFont(ofSize: size)
        if let n = ThoughtFont.registeredName, let f = UIFont(name: n, size: size) {
            font = f
        } else {
            KakaoPackStore.shared.ensureFont(id: KakaoPackStore.thoughtFontID)   // 没这款字就去下，下完重画
        }
        let para = NSMutableParagraphStyle()
        para.lineSpacing = lineSpacing
        l.attributedText = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .obliqueness: slant, .paragraphStyle: para
        ])
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let w = proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? (UIScreen.main.bounds.width - 40)
        let s = uiView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude))
        return CGSize(width: min(w, ceil(s.width)), height: ceil(s.height))
    }
}
