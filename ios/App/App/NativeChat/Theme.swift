import SwiftUI

// PWA 主题引擎的原生对照表：haven（粉白）/ rain（暂沿用 haven 聊天）/ midnight（黑夜）
// 主题名同步自 PWA localStorage 'alcove-theme'，她在设置里切，这边跟着变
struct AlcoveTheme {
    let isDark: Bool
    let isPaper: Bool
    let usesWallImage: Bool      // haven 铺 chat-bg.png；midnight 用深色渐变
    let wallGradient: [Color]
    var bubbleUser: Color        // 0902 信息主题可由她自己调色（MessagesPalette），所以是 var
    var bubbleAI: Color
    let text: Color
    let textDim: Color
    let textLight: Color
    var timestamp: Color
    let glassTint: Color
    let glassBorder: Color
    let capsuleTint: Color
    let capsuleBorder: Color
    let sendTop: Color
    let sendBottom: Color
    let fade: Color              // 上下渐隐的底色
    // 开屏
    let splashBg: [Color]
    let splashBarTop: Color
    let splashBarBottom: Color
    let splashGlowA: Color
    let splashGlowB: Color
    let splashPetal: Color
    let splashTitle: Color
    // Foyer 暖纸系 — 同步 PWA --fy-* 变量
    let fyAccent: Color
    let fyAccentSoft: Color
    let fyCard: Color
    let fyCardSub: Color
    let fyBorder: Color
    let fyShadow: Color
    let fyFold: Color
    let fyDash: Color
    let panelTextureAsset: String
    // 0822 她要的 iMessage 同款：纯色底、实心蓝/灰气泡带尾巴、过程线藏成一个点
    var isMessages: Bool = false
    // 0924 她要的 Kakao 家族：挂在信息骨架上，壁纸和气泡是主题包里的图（KakaoTheme.swift）
    var isKakao: Bool = false
    // 1009 #3501 她要的「树屋」：也挂在信息骨架上，气泡 / 顶栏 / 输入框 / 时间照她的成品 alcove chat page.html 画，
    // 壁纸是那张字符画树（资源 ChatWallTreehouse）。只有一版，不分白天黑夜（跟 Kakao 一样）
    var isTreehouse: Bool = false
    // 0902 她要的两个可调色位：思绪/过程线、各种截断线（时间戳截断、做了一场梦、切歌那一行）。
    // 没调过就是 nil，回落到 textDim——别的主题一个像素不变。
    var thought: Color? = nil
    /// 0903 她要的：气泡里的正文颜色也能调（MessagesPalette），nil = 主题原样
    var textUser: Color? = nil
    var textAI: Color? = nil
    var divider: Color? = nil
    /// 0929 她要的：已读双勾、输入框发送键各自单独调色，nil = 原来的系统蓝
    var readTick: Color? = nil
    var sendButton: Color? = nil
    var readTickColor: Color { readTick ?? Color(uiColor: .systemBlue) }
    var sendButtonColor: Color { sendButton ?? Color(uiColor: .systemBlue) }
    var thoughtColor: Color { thought ?? textDim }
    var dividerColor: Color { divider ?? textDim }

    static let haven = AlcoveTheme(
        isDark: false,
        isPaper: false,
        usesWallImage: true,
        wallGradient: [],
        bubbleUser: Color(red: 247/255, green: 227/255, blue: 234/255).opacity(0.44),
        bubbleAI: Color.white.opacity(0.38),
        text: Color(red: 0.22, green: 0.20, blue: 0.21),
        textDim: Color(red: 0.42, green: 0.40, blue: 0.41),
        textLight: Color(red: 0.62, green: 0.58, blue: 0.60),
        timestamp: Color(red: 0.2, green: 0.2, blue: 0.2),
        glassTint: Color.white.opacity(0.45),
        glassBorder: Color(red: 210/255, green: 210/255, blue: 218/255).opacity(0.22),
        capsuleTint: Color.white.opacity(0.92),
        capsuleBorder: Color.clear,
        sendTop: Color(red: 58/255, green: 56/255, blue: 60/255),
        sendBottom: Color(red: 42/255, green: 40/255, blue: 44/255),
        fade: Color.white,
        splashBg: [Color(red: 253/255, green: 250/255, blue: 251/255),
                   Color(red: 251/255, green: 243/255, blue: 246/255),
                   Color(red: 248/255, green: 237/255, blue: 241/255)],
        splashBarTop: Color(red: 228/255, green: 170/255, blue: 187/255),
        splashBarBottom: Color(red: 207/255, green: 148/255, blue: 166/255),
        splashGlowA: Color(red: 238/255, green: 190/255, blue: 205/255).opacity(0.40),
        splashGlowB: Color(red: 244/255, green: 214/255, blue: 224/255).opacity(0.34),
        splashPetal: Color(red: 238/255, green: 198/255, blue: 210/255),
        splashTitle: Color(red: 207/255, green: 148/255, blue: 166/255),
        fyAccent: Color(red: 207/255, green: 148/255, blue: 166/255),
        fyAccentSoft: Color(red: 223/255, green: 178/255, blue: 192/255).opacity(0.5),
        fyCard: Color.white.opacity(0.94),
        fyCardSub: Color.white.opacity(0.9),
        fyBorder: Color(red: 198/255, green: 198/255, blue: 210/255).opacity(0.40),
        fyShadow: Color(red: 140/255, green: 140/255, blue: 160/255).opacity(0.10),
        fyFold: Color(red: 233/255, green: 201/255, blue: 212/255).opacity(0.65),
        fyDash: Color(red: 210/255, green: 190/255, blue: 197/255).opacity(0.45),
        panelTextureAsset: "WetGlassHaven")

    static let midnight = AlcoveTheme(
        isDark: true,
        isPaper: false,
        usesWallImage: false,
        wallGradient: [Color(red: 28/255, green: 28/255, blue: 32/255),
                       Color(red: 23/255, green: 23/255, blue: 27/255),
                       Color(red: 19/255, green: 19/255, blue: 21/255),
                       Color(red: 16/255, green: 16/255, blue: 18/255)],
        bubbleUser: Color(red: 52/255, green: 52/255, blue: 62/255).opacity(0.82),
        bubbleAI: Color(red: 36/255, green: 36/255, blue: 44/255).opacity(0.82),
        text: Color(red: 216/255, green: 216/255, blue: 222/255),
        textDim: Color(red: 190/255, green: 190/255, blue: 200/255),
        textLight: Color(red: 150/255, green: 150/255, blue: 164/255),
        timestamp: Color(red: 200/255, green: 200/255, blue: 210/255),
        glassTint: Color(red: 26/255, green: 26/255, blue: 32/255).opacity(0.68),
        glassBorder: Color(red: 80/255, green: 80/255, blue: 95/255).opacity(0.22),
        capsuleTint: Color(red: 32/255, green: 32/255, blue: 40/255).opacity(0.5),
        capsuleBorder: Color(red: 80/255, green: 80/255, blue: 95/255).opacity(0.28),
        sendTop: Color(red: 136/255, green: 136/255, blue: 154/255),
        sendBottom: Color(red: 136/255, green: 136/255, blue: 154/255),
        fade: Color(red: 20/255, green: 20/255, blue: 24/255),
        splashBg: [Color(red: 29/255, green: 29/255, blue: 33/255),
                   Color(red: 25/255, green: 25/255, blue: 29/255),
                   Color(red: 22/255, green: 22/255, blue: 26/255)],
        splashBarTop: Color(red: 151/255, green: 113/255, blue: 127/255),
        splashBarBottom: Color(red: 125/255, green: 95/255, blue: 107/255),
        splashGlowA: Color(red: 160/255, green: 125/255, blue: 138/255).opacity(0.16),
        splashGlowB: Color(red: 140/255, green: 110/255, blue: 122/255).opacity(0.13),
        splashPetal: Color(red: 74/255, green: 62/255, blue: 68/255),
        splashTitle: Color(red: 151/255, green: 113/255, blue: 127/255),
        fyAccent: Color(red: 160/255, green: 125/255, blue: 138/255),
        fyAccentSoft: Color(red: 140/255, green: 105/255, blue: 118/255).opacity(0.45),
        fyCard: Color(red: 36/255, green: 36/255, blue: 44/255).opacity(0.88),
        fyCardSub: Color(red: 42/255, green: 42/255, blue: 52/255).opacity(0.85),
        fyBorder: Color(red: 105/255, green: 105/255, blue: 122/255).opacity(0.30),
        fyShadow: Color.black.opacity(0.35),
        fyFold: Color(red: 120/255, green: 90/255, blue: 102/255).opacity(0.45),
        fyDash: Color(red: 120/255, green: 105/255, blue: 112/255).opacity(0.4),
        panelTextureAsset: "WetGlassMidnight")

    static let paper = haven.paperCopy(dark: false)
    static let paperDark = midnight.paperCopy(dark: true)
    static let messages = haven.messagesCopy(dark: false)
    static let messagesDark = midnight.messagesCopy(dark: true)
    static let treehouse = haven.treehouseCopy()
    static let treehouseNight = haven.treehouseCopy(dark: true)

    static func named(_ name: String) -> AlcoveTheme {
        switch name {
        case "paper": return .paper
        case "paper-dark": return .paperDark
        case "midnight": return .midnight
        case "imessage": return MessagesPalette.apply(to: .messages, dark: false)
        case "imessage-dark": return MessagesPalette.apply(to: .messagesDark, dark: true)
        case "kakao": return .kakaoTheme()
        // 1009 #3507 她要的：脚印、时间、思绪那几行跟信息主题一模一样——连她在信息主题里调过的颜色也一起借（白天那份）
        case "treehouse": return MessagesPalette.applyTreehouse(to: .treehouse, dark: false)
        case "treehouse-dark": return MessagesPalette.applyTreehouse(to: .treehouseNight, dark: true)
        default: return .haven
        }
    }

    // 下拉面板拥有独立的湿玻璃配色。rain 的聊天页仍由 named(_:) 返回 haven，
    // 因而新增蓝色选项不会改动聊天气泡、输入框、顶栏或聊天壁纸。
    static func panelNamed(_ name: String) -> AlcoveTheme {
        switch name {
        case "paper": return paper
        case "paper-dark": return paperDark
        // iMessage 主题只改聊天页；抽屉/面板沿用玻璃系（白天 haven、黑夜 midnight），其他地方一律不动
        case "imessage": return panelNamed("haven")
        case "imessage-dark": return panelNamed("midnight")
        case "kakao": return AlcoveTheme.kakaoPanel(dark: AlcoveAppearance.isDark)   // 0924 她要的：抽屉/设置页的底色跟主题包壁纸走
        // 树屋只改聊天页（日记、梦境另有自己的样子）；别的页面、抽屉、设置页跟信息主题一样借玻璃系
        // （白天 haven、黑夜 midnight），深浅跟全屋按钮走。1010 #3570 她：「现在是跟着纸页走的」——原来借的是纸页
        case "treehouse", "treehouse-dark": return panelNamed(AlcoveAppearance.isDark ? "midnight" : "haven")
        case "midnight":
            return midnight.panelCopy(
                splashBg: [
                    Color(red: 13/255, green: 22/255, blue: 35/255).opacity(0.90),
                    Color(red: 20/255, green: 31/255, blue: 47/255).opacity(0.88),
                    Color(red: 9/255, green: 15/255, blue: 25/255).opacity(0.92)
                ],
                text: Color(red: 232/255, green: 237/255, blue: 244/255),
                textDim: Color(red: 205/255, green: 215/255, blue: 228/255),
                textLight: Color(red: 160/255, green: 174/255, blue: 191/255),
                accent: Color(red: 218/255, green: 227/255, blue: 239/255),
                accentSoft: Color.white.opacity(0.24),
                card: Color(red: 25/255, green: 37/255, blue: 54/255).opacity(0.48),
                cardSub: Color.white.opacity(0.075),
                border: Color.white.opacity(0.30),
                shadow: Color.black.opacity(0.42),
                textureAsset: "WetGlassMidnight"
            )
        default:
            return haven.panelCopy(
                splashBg: [
                    Color.white.opacity(0.78),
                    Color(red: 235/255, green: 237/255, blue: 244/255).opacity(0.72),
                    Color(red: 247/255, green: 244/255, blue: 248/255).opacity(0.76)
                ],
                text: Color(red: 26/255, green: 25/255, blue: 29/255),
                textDim: Color(red: 47/255, green: 48/255, blue: 55/255),
                textLight: Color(red: 91/255, green: 92/255, blue: 101/255),
                accent: Color(red: 159/255, green: 31/255, blue: 82/255),
                accentSoft: Color(red: 159/255, green: 31/255, blue: 82/255).opacity(0.28),
                card: Color.white.opacity(0.34),
                cardSub: Color.white.opacity(0.30),
                border: Color.white.opacity(0.70),
                shadow: Color(red: 70/255, green: 78/255, blue: 96/255).opacity(0.16),
                textureAsset: "WetGlassHaven"
            )
        }
    }

    func panelCopy(
        splashBg: [Color],
        text: Color,
        textDim: Color,
        textLight: Color,
        accent: Color,
        accentSoft: Color,
        card: Color,
        cardSub: Color,
        border: Color,
        shadow: Color,
        textureAsset: String
    ) -> AlcoveTheme {
        AlcoveTheme(
            isDark: isDark,
            isPaper: isPaper,
            usesWallImage: usesWallImage,
            wallGradient: wallGradient,
            bubbleUser: bubbleUser,
            bubbleAI: bubbleAI,
            text: text,
            textDim: textDim,
            textLight: textLight,
            timestamp: timestamp,
            glassTint: card,
            glassBorder: border,
            capsuleTint: capsuleTint,
            capsuleBorder: capsuleBorder,
            sendTop: sendTop,
            sendBottom: sendBottom,
            fade: fade,
            splashBg: splashBg,
            splashBarTop: splashBarTop,
            splashBarBottom: splashBarBottom,
            splashGlowA: splashGlowA,
            splashGlowB: splashGlowB,
            splashPetal: splashPetal,
            splashTitle: splashTitle,
            fyAccent: accent,
            fyAccentSoft: accentSoft,
            fyCard: card,
            fyCardSub: cardSub,
            fyBorder: border,
            fyShadow: shadow,
            fyFold: Color.white.opacity(isDark ? 0.08 : 0.22),
            fyDash: border.opacity(0.72),
            panelTextureAsset: textureAsset
        )
    }

    /// iMessage 同款：白天 #FFF 底 / 灰泡 #E9E9EB 黑字；黑夜 #000 底 / 灰泡 #262628 白字；
    /// 她的泡系统蓝白字，不带尾巴。面板那套颜色沿用纸页系，不动别的房间。
    private func messagesCopy(dark: Bool) -> AlcoveTheme {
        let bg = dark ? Color.black : Color.white
        let gray = dark ? Color(red: 38/255, green: 38/255, blue: 40/255) : Color(red: 233/255, green: 233/255, blue: 235/255)
        // 0822 第三版：从她真机截图取像素——iOS 26 的蓝泡实际渲染出来是 #57A1F3（比 systemBlue 浅一截、更灰）；
        // 夜里没截图，按同样的浅法估 #3D8EF2，不对她会再截
        let blue = dark ? Color(red: 0x3D/255, green: 0x8E/255, blue: 0xF2/255) : Color(red: 0x57/255, green: 0xA1/255, blue: 0xF3/255)
        let ink = dark ? Color.white : Color.black
        let dim = Color(red: 142/255, green: 142/255, blue: 147/255)   // systemGray
        let card = dark ? Color(red: 28/255, green: 28/255, blue: 30/255) : Color.white
        let line = dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
        var t = AlcoveTheme(
            isDark: dark, isPaper: false, usesWallImage: false,
            wallGradient: [bg, bg],
            bubbleUser: blue, bubbleAI: gray, text: ink, textDim: dim,
            textLight: dim.opacity(0.8), timestamp: dim,
            glassTint: card, glassBorder: line,
            capsuleTint: card, capsuleBorder: line,
            sendTop: blue, sendBottom: blue,
            fade: bg, splashBg: [bg, bg], splashBarTop: blue,
            splashBarBottom: blue.opacity(0.8), splashGlowA: .clear, splashGlowB: .clear,
            splashPetal: blue.opacity(0.3), splashTitle: blue,
            fyAccent: blue, fyAccentSoft: blue.opacity(0.14), fyCard: card,
            fyCardSub: dark ? Color(red: 44/255, green: 44/255, blue: 46/255) : Color(red: 242/255, green: 242/255, blue: 247/255),
            fyBorder: line,
            fyShadow: Color.black.opacity(dark ? 0.22 : 0.05),
            fyFold: line, fyDash: dim.opacity(0.3),
            panelTextureAsset: dark ? "PaperDark" : "PaperLight"
        )
        t.isMessages = true
        return t
    }

    /// 树屋：颜色全照她的成品 alcove chat page.html —— 冷白颗粒底 #EFEFED、他的泡 #FBFAF7 黑字、
    /// 她的泡 #2A2826 白字、墨 #141414、电光蓝 #0B1BFF。抽屉那些面板不读这里（panelNamed 走纸页）
    /// 1009 #3516–3518 黑夜版（她看过效果图说「这个颜色可以」）：中性炭灰底 #1B1C20、浅墨 #E9E8E4、
    /// 气泡反过来——他的炭灰泡 #2A2B31 浅字、她的纸白泡 #E4E3DE 深字，电光蓝提亮成 #3A55FF
    fileprivate func treehouseCopy(dark night: Bool = false) -> AlcoveTheme {
        let bg = night ? Color(red: 0x1B/255, green: 0x1C/255, blue: 0x20/255) : Color(red: 0xEF/255, green: 0xEF/255, blue: 0xED/255)
        let white = night ? Color(red: 0x2A/255, green: 0x2B/255, blue: 0x31/255) : Color(red: 0xFB/255, green: 0xFA/255, blue: 0xF7/255)
        let dark = night ? Color(red: 0xE4/255, green: 0xE3/255, blue: 0xDE/255) : Color(red: 0x2A/255, green: 0x28/255, blue: 0x26/255)
        let ink = night ? Color(red: 0xE9/255, green: 0xE8/255, blue: 0xE4/255) : Color(red: 0x14/255, green: 0x14/255, blue: 0x14/255)
        // 时间、思绪、脚印这些小字跟信息主题同一个系统灰（#3507）；顶栏模型名那行另用成品的 #7A7975
        let dim = Color(red: 142/255, green: 142/255, blue: 147/255)
        let blue = night ? Color(red: 0x3A/255, green: 0x55/255, blue: 0xFF/255) : Color(red: 0x0B/255, green: 0x1B/255, blue: 0xFF/255)
        let line = ink.opacity(0.14)
        var t = AlcoveTheme(
            isDark: night, isPaper: false, usesWallImage: false,
            wallGradient: [bg, bg],
            bubbleUser: dark, bubbleAI: white, text: ink, textDim: dim,
            textLight: dim.opacity(0.8), timestamp: dim,
            glassTint: white, glassBorder: line,
            capsuleTint: bg.opacity(0.42), capsuleBorder: ink.opacity(0.55),
            sendTop: ink, sendBottom: ink,
            fade: bg, splashBg: [bg, bg], splashBarTop: blue,
            splashBarBottom: blue.opacity(0.8), splashGlowA: .clear, splashGlowB: .clear,
            splashPetal: blue.opacity(0.3), splashTitle: ink,
            fyAccent: blue, fyAccentSoft: blue.opacity(0.14), fyCard: white,
            fyCardSub: bg, fyBorder: line,
            fyShadow: Color.black.opacity(night ? 0.3 : 0.05),
            fyFold: line, fyDash: dim.opacity(0.3),
            panelTextureAsset: night ? "PaperDark" : "PaperLight"
        )
        t.isMessages = true
        t.isTreehouse = true
        t.textUser = white
        t.textAI = ink
        t.sendButton = ink
        return t
    }

    private func paperCopy(dark: Bool) -> AlcoveTheme {
        let paper = dark ? Color(red: 24/255, green: 24/255, blue: 25/255)
                         : Color(red: 248/255, green: 248/255, blue: 246/255)
        let card = dark ? Color(red: 36/255, green: 35/255, blue: 33/255)
                        : Color.white
        let ink = dark ? Color(red: 231/255, green: 227/255, blue: 218/255)
                       : Color(red: 37/255, green: 36/255, blue: 34/255)
        let pencil = dark ? Color(red: 166/255, green: 160/255, blue: 151/255)
                          : Color(red: 139/255, green: 136/255, blue: 130/255)
        let rose = dark ? Color(red: 148/255, green: 91/255, blue: 91/255)
                        : Color(red: 185/255, green: 120/255, blue: 120/255)
        return AlcoveTheme(
            isDark: dark, isPaper: true, usesWallImage: false,
            wallGradient: [paper, paper],
            bubbleUser: dark ? Color(red: 54/255, green: 52/255, blue: 57/255) : Color(red: 233/255, green: 232/255, blue: 236/255),
            bubbleAI: .clear, text: ink, textDim: pencil,
            textLight: pencil.opacity(0.72), timestamp: pencil,
            glassTint: card, glassBorder: pencil.opacity(0.16),
            capsuleTint: card, capsuleBorder: pencil.opacity(0.14),
            sendTop: dark ? Color(red: 231/255, green: 227/255, blue: 218/255) : Color(red: 37/255, green: 36/255, blue: 34/255),
            sendBottom: dark ? Color(red: 205/255, green: 200/255, blue: 191/255) : Color(red: 24/255, green: 24/255, blue: 23/255),
            fade: paper, splashBg: [paper, paper], splashBarTop: rose,
            splashBarBottom: rose.opacity(0.8), splashGlowA: .clear, splashGlowB: .clear,
            splashPetal: rose.opacity(0.35), splashTitle: rose,
            fyAccent: rose, fyAccentSoft: rose.opacity(0.16), fyCard: card,
            fyCardSub: paper, fyBorder: pencil.opacity(0.17),
            fyShadow: Color.black.opacity(dark ? 0.22 : 0.05),
            fyFold: pencil.opacity(0.10), fyDash: pencil.opacity(0.24),
            panelTextureAsset: dark ? "PaperDark" : "PaperLight"
        )
    }
}

// MARK: - 一个按钮管全屋（0827 她定的）
//
// 以前深浅有两个源：设置里的“功能页外观”（houseInterfaceAppearance，还带一档跟随系统）
// 管共读室／檐下／信箱／数据页，聊天主题里那个白天黑夜（alcoveTheme 的深浅后缀）
// 管聊天页／圆桌／根视图。她要的是一个按钮管所有页面、并且不跟系统走。
//
// 现在 houseInterfaceAppearance 只剩 "light"/"dark" 两个值，是全屋唯一真源；
// alcoveTheme 只负责“哪一套皮”（玻璃／纸页／信息），深浅永远被掰到跟开关一致。
enum AlcoveAppearance {
    static let key = "houseInterfaceAppearance"
    static let themeKey = "alcoveTheme"

    /// 皮的家族，跟深浅无关
    static func family(of name: String) -> String {
        switch name {
        case "paper", "paper-dark": return "paper"
        case "imessage", "imessage-dark": return "imessage"
        case "kakao": return "kakao"
        case "treehouse", "treehouse-dark": return "treehouse"
        default: return "glass"
        }
    }

    /// 只管聊天页、自己不分深浅的皮（Kakao、树屋）：别的页面拿它画会恒按白天，得改认全屋按钮
    static func chatOnly(_ name: String) -> Bool {
        let f = family(of: name)
        return f == "kakao" || f == "treehouse"
    }

    static func themeName(family: String, dark: Bool) -> String {
        switch family {
        case "paper": return dark ? "paper-dark" : "paper"
        case "imessage": return dark ? "imessage-dark" : "imessage"
        case "kakao": return "kakao"   // 主题包自己带颜色，没有夜里那版
        case "treehouse": return dark ? "treehouse-dark" : "treehouse"   // #3518 起树屋也分白天黑夜
        default: return dark ? "midnight" : "haven"
        }
    }

    static func isDark(_ themeName: String) -> Bool {
        themeName == "midnight" || themeName == "paper-dark" || themeName == "imessage-dark" || themeName == "treehouse-dark"
    }

    /// 开关当下是不是黑夜（读不到就按聊天主题的深浅兜底）
    static var isDark: Bool {
        let d = UserDefaults.standard
        switch d.string(forKey: key) {
        case "dark":  return true
        case "light": return false
        default:      return isDark(d.string(forKey: themeKey) ?? "haven")
        }
    }

    /// 按一次按钮：开关和皮的深浅一起翻
    static func apply(dark: Bool) {
        let d = UserDefaults.standard
        d.set(dark ? "dark" : "light", forKey: key)
        let current = d.string(forKey: themeKey) ?? "haven"
        d.set(themeName(family: family(of: current), dark: dark), forKey: themeKey)
        MessagesPalette.bump()   // 1002：Kakao 下 themeName 不变，靠这一下让盯着 paletteStamp 的页面重算主题
    }

    /// 换皮不换深浅
    static func applyFamily(_ family: String) {
        let d = UserDefaults.standard
        d.set(themeName(family: family, dark: isDark), forKey: themeKey)
    }

    /// 启动时对齐一次：旧的 "system" 值按此刻系统色落定成 light/dark，
    /// 再把聊天主题的深浅掰到跟开关一致，之后全 app 只认这一个值。
    static func migrate(systemDark: Bool) {
        let d = UserDefaults.standard
        let stored = d.string(forKey: key)
        let dark: Bool
        switch stored {
        case "dark":  dark = true
        case "light": dark = false
        default:      dark = stored == "system" ? systemDark : isDark(d.string(forKey: themeKey) ?? "haven")
        }
        apply(dark: dark)
    }
}

// MARK: - 0902 信息主题调色板（她自己调：时间戳 / 思绪 / 截断线 / 两边气泡）
//
// 只对 imessage / imessage-dark 生效，别的主题不读。每一项各自存一个十六进制色，
// 没存就用主题原来的颜色（就是"默认"）；点某一项的「默认」只清那一项。
// 改了任何一项就把 msgPaletteStamp 拨一下，聊天页 / RootView / 设置页都盯着这个数重画。

// 0903 她要的：(1) 多两项「我的正文」「他的正文」；(2) 七项全部夜里一套、白天一套，跟全屋日夜开关走
//（以前只存一套，她夜里调的白天还顶着）。老键 msgColor.<item> 第一次读到就搬进夜里那套。
enum MessagesPalette {
    enum Item: String, CaseIterable, Identifiable {
        case timestamp, thought, divider, bubbleUser, bubbleAI, textUser, textAI, readTick, sendButton
        var id: String { rawValue }
        var title: String {
            switch self {
            case .timestamp: return "时间戳"
            case .thought: return "思绪与过程线"
            case .divider: return "截断线"
            case .bubbleUser: return "我的气泡"
            case .bubbleAI: return "他的气泡"
            case .textUser: return "我的正文"
            case .textAI: return "他的正文"
            case .readTick: return "已读勾"
            case .sendButton: return "发送键"
            }
        }
        /// 旧键（0902 只有一套的时候）
        var legacyKey: String { "msgColor." + rawValue }
        /// 1001 她要的：普通气泡、玻璃气泡各存一套（普通沿用原来的键，切回去以前调的都在）
        func key(dark: Bool, glass: Bool = MessagesPalette.glass) -> String {
            (glass ? "msgColorGlass." : "msgColor.") + (dark ? "night" : "day") + "." + rawValue
        }
    }

    static let stampKey = "msgPaletteStamp"
    /// 1001 信息主题气泡用玻璃还是普通实心（设置「颜色 · 信息主题」顶上那个切换）。没设过＝玻璃（她正在试）
    static let glassKey = "msgBubbleGlass"
    /// 1009 #3519 树屋也能切玻璃气泡：单独一个开关，不跟信息主题那个连着；默认实心（成品那样）
    static let thGlassKey = "treehouseBubbleGlass"
    static var thGlass: Bool { UserDefaults.standard.bool(forKey: thGlassKey) }
    static var glass: Bool { UserDefaults.standard.object(forKey: glassKey) as? Bool ?? true }
    private static let migratedKey = "msgColor.migratedToDayNight"

    /// 全屋现在是夜里还是白天（跟 AlcoveAppearance 那个开关走）
    static var isDark: Bool { UserDefaults.standard.string(forKey: AlcoveAppearance.key) != "light" }

    /// 老的单套值搬进夜里那套（她 0902 是夜里调的），只搬一次
    private static func migrateIfNeeded() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: migratedKey) else { return }
        for item in Item.allCases {
            if let hex = d.string(forKey: item.legacyKey), !hex.isEmpty {
                if d.string(forKey: item.key(dark: true, glass: false)) == nil { d.set(hex, forKey: item.key(dark: true, glass: false)) }
                d.removeObject(forKey: item.legacyKey)
            }
        }
        d.set(true, forKey: migratedKey)
    }

    /// 预设色块：一点就换。跟着壁纸走的常用色，白、米白、两档灰、藕粉、iMessage 蓝、近黑
    static let presets: [Color] = [
        .white,
        Color(hexString: "#F2EDE4")!,
        Color(hexString: "#C7C7CC")!,
        Color(hexString: "#8E8E93")!,
        Color(hexString: "#F2DCE0")!,
        Color(hexString: "#57A1F3")!,
        Color(hexString: "#1C1C1E")!,
    ]

    /// 主题原本的颜色 = 这一项的默认值
    static func defaultColor(_ item: Item, dark: Bool) -> Color {
        let base: AlcoveTheme = dark ? .messagesDark : .messages
        switch item {
        case .timestamp: return base.timestamp
        case .thought: return base.textDim
        case .divider: return base.textDim
        case .bubbleUser: return base.bubbleUser
        case .bubbleAI: return base.bubbleAI
        // 普通气泡：她的气泡上的字本来就是白的；1001 玻璃气泡不带颜色，白字在白天看不见，默认跟他的正文一样
        case .textUser: return glass ? base.text : .white
        case .textAI: return base.text
        case .readTick, .sendButton: return Color(uiColor: .systemBlue)
        }
    }

    static func stored(_ item: Item, dark: Bool) -> Color? {
        migrateIfNeeded()
        guard let hex = UserDefaults.standard.string(forKey: item.key(dark: dark)), !hex.isEmpty else { return nil }
        return Color(hexString: hex)
    }

    static func current(_ item: Item, dark: Bool) -> Color {
        stored(item, dark: dark) ?? defaultColor(item, dark: dark)
    }

    static func isDefault(_ item: Item, dark: Bool) -> Bool { stored(item, dark: dark) == nil }

    static func set(_ item: Item, _ color: Color?, dark: Bool) {
        migrateIfNeeded()
        if let color, let hex = color.hexString {
            UserDefaults.standard.set(hex, forKey: item.key(dark: dark))
        } else {
            UserDefaults.standard.removeObject(forKey: item.key(dark: dark))
        }
        bump()
    }

    static func bump() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: stampKey)
    }

    /// 1009 树屋：只借她在信息主题里调的那几行小字的颜色（时间、思绪、截断线、已读勾），气泡和正文还是树屋自己的
    static func applyMeta(to theme: AlcoveTheme) -> AlcoveTheme {
        var t = theme
        if let c = stored(.timestamp, dark: false) { t.timestamp = c }
        if let c = stored(.thought, dark: false) { t.thought = c }
        if let c = stored(.divider, dark: false) { t.divider = c }
        if let c = stored(.readTick, dark: false) { t.readTick = c }
        return t
    }

    // MARK: - 树屋自己那套（1009 晚 她：「信息主题不是可以调节一大堆颜色吗，把我们树屋主题也加上那些调节的」）
    // 跟信息主题分开存，各调各的。#3518 有了黑夜版：白天沿用原来的键（她调过的不丢），黑夜另存一套 msgColorTreehouseNight.*

    static func thKey(_ item: Item, dark: Bool = AlcoveAppearance.isDark) -> String {
        (dark ? "msgColorTreehouseNight." : "msgColorTreehouse.") + item.rawValue
    }

    /// 树屋原本的颜色 = 这一项的默认值
    static func thDefault(_ item: Item, dark: Bool = AlcoveAppearance.isDark) -> Color {
        let base = dark ? AlcoveTheme.treehouseNight : AlcoveTheme.treehouse
        switch item {
        case .timestamp: return base.timestamp
        case .thought: return base.textDim
        case .divider: return base.textDim
        case .bubbleUser: return base.bubbleUser
        case .bubbleAI: return base.bubbleAI
        case .textUser: return base.textUser ?? base.text   // 她的泡上的字：白天纸白、黑夜炭灰
        case .textAI: return base.text
        case .readTick: return base.textDim
        case .sendButton: return base.sendButton ?? base.text
        }
    }

    static func thStored(_ item: Item, dark: Bool = AlcoveAppearance.isDark) -> Color? {
        guard let hex = UserDefaults.standard.string(forKey: thKey(item, dark: dark)), !hex.isEmpty else { return nil }
        return Color(hexString: hex)
    }

    static func thCurrent(_ item: Item, dark: Bool = AlcoveAppearance.isDark) -> Color { thStored(item, dark: dark) ?? thDefault(item, dark: dark) }

    static func thIsDefault(_ item: Item, dark: Bool = AlcoveAppearance.isDark) -> Bool { thStored(item, dark: dark) == nil }

    static func thSet(_ item: Item, _ color: Color?, dark: Bool = AlcoveAppearance.isDark) {
        if let color, let hex = color.hexString {
            UserDefaults.standard.set(hex, forKey: thKey(item, dark: dark))
        } else {
            UserDefaults.standard.removeObject(forKey: thKey(item, dark: dark))
        }
        bump()
    }

    /// 九项全上：她在树屋（这一档白天 / 黑夜）里调过的盖上去，没调过的还是树屋原样
    static func applyTreehouse(to theme: AlcoveTheme, dark: Bool) -> AlcoveTheme {
        var t = theme   // 树屋恢复默认时使用树屋本身，不继承其他主题的自选色。
        if let c = thStored(.timestamp, dark: dark) { t.timestamp = c }
        if let c = thStored(.thought, dark: dark) { t.thought = c }
        if let c = thStored(.divider, dark: dark) { t.divider = c }
        if let c = thStored(.bubbleUser, dark: dark) { t.bubbleUser = c }
        if let c = thStored(.bubbleAI, dark: dark) { t.bubbleAI = c }
        if let c = thStored(.textUser, dark: dark) { t.textUser = c }
        if let c = thStored(.textAI, dark: dark) { t.textAI = c }
        if let c = thStored(.readTick, dark: dark) { t.readTick = c }
        if let c = thStored(.sendButton, dark: dark) { t.sendButton = c }
        // 玻璃气泡不带底色：她那边原来是「深泡配浅字」，换成玻璃浅字就看不见了，没单独调过就跟正文墨色走
        if thGlass && thStored(.textUser, dark: dark) == nil { t.textUser = t.text }
        return t
    }

    static func apply(to theme: AlcoveTheme, dark: Bool) -> AlcoveTheme {
        var t = theme
        if let c = stored(.timestamp, dark: dark) { t.timestamp = c }
        if let c = stored(.thought, dark: dark) { t.thought = c }
        if let c = stored(.divider, dark: dark) { t.divider = c }
        if let c = stored(.bubbleUser, dark: dark) { t.bubbleUser = c }
        if let c = stored(.bubbleAI, dark: dark) { t.bubbleAI = c }
        if let c = stored(.textUser, dark: dark) { t.textUser = c }
        if let c = stored(.textAI, dark: dark) { t.textAI = c }
        if let c = stored(.readTick, dark: dark) { t.readTick = c }
        if let c = stored(.sendButton, dark: dark) { t.sendButton = c }
        return t
    }
}

extension Color {
    /// "#RRGGBB" 或 "#RRGGBBAA"
    init?(hexString: String) {
        var h = hexString.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6 || h.count == 8, let v = UInt64(h, radix: 16) else { return nil }
        let r, g, b, a: Double
        if h.count == 8 {
            r = Double((v >> 24) & 0xFF) / 255; g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255;  a = Double(v & 0xFF) / 255
        } else {
            r = Double((v >> 16) & 0xFF) / 255; g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255;         a = 1
        }
        self.init(red: r, green: g, blue: b, opacity: a)
    }

    var hexString: String? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02X%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)),
                      Int(round(b * 255)), Int(round(a * 255)))
    }
}

