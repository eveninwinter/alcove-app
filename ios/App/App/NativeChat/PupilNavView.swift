import SwiftUI
import UIKit

// MARK: - 瞳孔导览（1003 她给的 pupil-nav.html，一比一移植成原生，原型存 /root/workroom/mock/pupil/pupil-nav.html）
// 以后替换侧边栏；今天先只把页面做出来，不接入（入口用侧边栏那 22 间的真名字，点进去是原型那种占位页）。
// 常数、公式、动画时长、缓动、12fps 步进、开屏分辨率序列、mulberry32 种子（虹膜 7、眼白 11）、
// 64×64 蓝噪声表、F57 点阵字全照原型。跟原型不一样的只有三处：
//   ① 入口 13 → 22，起始停在 CHAT（原型停在第 4 个）；RADII 原型只给了 13 个，往后按 i % 13 循环
//   ② 没有键盘（方向键 / 回车 / Esc 那几行不搬）
//   ③ 底色跟全屋白天 / 黑夜按钮，不跟系统（她的规矩）

private enum PN {
    static let W: Double = 390, H: Double = 844, CX: Double = 195, CY: Double = 640
    static let RI: Double = 330, RP0: Double = 96            // 虹膜半径、静止瞳孔半径
    static let STEP: Double = 21 * Double.pi / 180           // 入口之间的角度
    static let HOLD_MS: Double = 700                          // 按住进入
    static let INK: (UInt8, UInt8, UInt8) = (42, 37, 53)
    static let PAPER: (UInt8, UInt8, UInt8) = (241, 236, 245)
    static let PINK: (UInt8, UInt8, UInt8) = (227, 106, 174)
    static let NT = 1024, NR = 240
    static let R0 = RP0 - 12, R1 = RI + 14
    static let BASE_RADII: [Double] = [214, 198, 210, 206, 200, 214, 204, 208, 199, 212, 203, 209, 201]
}

private struct PNEntry {
    let en: String
    let zh: String
    let grp: String
    var badge: String? = nil
}

/// 顺序 = 绕虹膜一圈的顺序（照侧边栏）
private let PN_ENTRIES: [PNEntry] = [
    PNEntry(en: "CHAT", zh: "Chat", grp: "TALK"),
    PNEntry(en: "TABLE", zh: "圆桌", grp: "TALK"),
    PNEntry(en: "TERM", zh: "Terminal", grp: "TALK"),
    PNEntry(en: "SETTINGS", zh: "设置", grp: "TEND"),
    PNEntry(en: "FACTORY", zh: "出厂设置", grp: "TEND"),
    PNEntry(en: "PULSE", zh: "Pulse", grp: "HOUSE"),
    PNEntry(en: "ROOF", zh: "檐上", grp: "HOUSE"),
    PNEntry(en: "EAVES", zh: "檐下", grp: "HOUSE"),
    PNEntry(en: "TAROT", zh: "占星室", grp: "PLAY"),
    PNEntry(en: "NURSERY", zh: "育儿室", grp: "PLAY"),
    PNEntry(en: "WALLET", zh: "钱包", grp: "PLAY"),
    PNEntry(en: "SHOP", zh: "商店", grp: "PLAY"),
    PNEntry(en: "LETTERS", zh: "信箱", grp: "TALK"),
    PNEntry(en: "ALBUM", zh: "相册", grp: "KEEP"),
    PNEntry(en: "KEEP", zh: "不忘", grp: "KEEP"),
    PNEntry(en: "DREAMS", zh: "Dreams", grp: "KEEP"),
    PNEntry(en: "STUDY", zh: "书房", grp: "WANDER"),
    PNEntry(en: "NOWHERE", zh: "乌有乡", grp: "WANDER"),
    PNEntry(en: "SURF", zh: "冲浪收藏", grp: "WANDER"),
    PNEntry(en: "WINDOW", zh: "世界之窗", grp: "WANDER"),
    PNEntry(en: "RINGS", zh: "年轮", grp: "KEEP"),
    PNEntry(en: "CHRONICLE", zh: "编年史", grp: "KEEP"),
]

// MARK: 小工具（照原型）

private struct Mulberry32 {
    var a: UInt32
    init(_ seed: UInt32) { a = seed }
    mutating func next() -> Double {
        a = a &+ 0x6D2B79F5
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4294967296
    }
}

@inline(__always) private func pnClamp(_ v: Double, _ a: Double, _ b: Double) -> Double { v < a ? a : (v > b ? b : v) }
@inline(__always) private func pnEase(_ t: Double) -> Double { let t = pnClamp(t, 0, 1); return 1 - pow(1 - t, 3) }
@inline(__always) private func pnEaseIn(_ t: Double) -> Double { let t = pnClamp(t, 0, 1); return t * t * t }
/// JS 的 Math.round（.5 一律往上）
@inline(__always) private func jsRound(_ x: Double) -> Double { floor(x + 0.5) }
private func pnWrapPI(_ x: Double) -> Double {
    var a = x
    while a > Double.pi { a -= 2 * Double.pi }
    while a < -Double.pi { a += 2 * Double.pi }
    return a
}
private func pnStepped(_ t: Double, _ fps: Double) -> Double { let f = 1000 / fps; return floor(t / f) * f }
private func pnMod(_ n: Int, _ m: Int) -> Int { ((n % m) + m) % m }

// MARK: 蓝噪声阈值表（64×64，原型那段 base64 原样）

private let PN_BLUE: [Float] = {
    let s = "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"
    guard let d = Data(base64Encoded: s) else { return [Float](repeating: 0.5, count: 4096) }
    return d.map { Float($0) / 255 }
}()

// MARK: 虹膜纹理（极坐标）

private func pnBuildIris() -> [Float] {
    var rnd = Mulberry32(7)
    var Fk: [Double] = [], Fph: [Double] = [], Fw: [Double] = [], Fa: [Double] = []
    for _ in 0..<38 {
        let k = 18 + floor(rnd.next() * 182)
        let ph = rnd.next() * 6.28
        let w = (rnd.next() * 2 - 1) * 0.02
        let a = 0.3 + rnd.next() * 0.7
        Fk.append(k); Fph.append(ph); Fw.append(w); Fa.append(a)
    }
    var CRx: [Double] = [], CRy: [Double] = [], CRc: [Double] = [], CRs: [Double] = [], CRsx: [Double] = [], CRsy: [Double] = []
    for _ in 0..<26 {
        let ang = (rnd.next() * 2 - 1) * Double.pi
        let rr = PN.RP0 * (1.5 + rnd.next() * 0.9)
        let sx = 6 + rnd.next() * 10
        let sy = 14 + rnd.next() * 20
        CRx.append(rr * cos(ang)); CRy.append(rr * sin(ang)); CRc.append(cos(ang)); CRs.append(sin(ang))
        CRsx.append(sx); CRsy.append(sy)
    }
    let NT = PN.NT, NR = PN.NR
    let rAt: (Int) -> Double = { j in PN.R0 + Double(j) * (PN.R1 - PN.R0) / Double(NR - 1) }
    // 原型：s += a·sin(k·θ + ph + w·r + 0.6·sin(r·0.03 + ph))；跟 θ 无关的那半先按 r 算好
    var inner = [Double](repeating: 0, count: NR * 38)
    for j in 0..<NR {
        let r = rAt(j)
        for k in 0..<38 { inner[j * 38 + k] = Fph[k] + Fw[k] * r + 0.6 * sin(r * 0.03 + Fph[k]) }
    }
    var fib = [Double](repeating: 0, count: NT * NR)
    var maxA = 0.0
    for i in 0..<NT {
        let th = Double(i) / Double(NT) * Double.pi * 2
        for j in 0..<NR {
            var s = 0.0
            let base = j * 38
            for k in 0..<38 { s += Fa[k] * sin(Fk[k] * th + inner[base + k]) }
            fib[i * NR + j] = s
            if abs(s) > maxA { maxA = abs(s) }
        }
    }
    var tex = [Float](repeating: 0, count: NT * NR)
    for i in 0..<NT {
        let th = Double(i) / Double(NT) * Double.pi * 2
        let ct = cos(th), st = sin(th)
        let colR = PN.RP0 * 1.75 + 14 * sin(7 * th + 2) + 9 * sin(13 * th + 0.7) + 6 * sin(23 * th)
        let edge = PN.RI + 6 * sin(3 * th + 0.4)
        for j in 0..<NR {
            let r = rAt(j)
            let x = r * ct, y = r * st
            var crypt = 0.0
            for k in 0..<26 {
                let dx = x - CRx[k], dy = y - CRy[k]
                let u = dx * CRc[k] + dy * CRs[k], v = -dx * CRs[k] + dy * CRc[k]
                crypt += exp(-(u / CRsy[k]) * (u / CRsy[k]) - (v / CRsx[k]) * (v / CRsx[k]))
            }
            let tn = pnClamp((r - PN.RP0) / (PN.RI - PN.RP0), 0, 1)
            var val = 0.42 + 0.30 * (fib[i * NR + j] / maxA) * (0.6 + 0.4 * tn)
            val += 0.16 * exp(-pow((r - colR) / 10, 2))
            if r < colR { val -= 0.06 }
            val -= 0.22 * pnClamp(crypt, 0, 1)
            val -= 0.38 * pow(pnClamp((r - (edge - 60)) / 60, 0, 1), 1.6)
            val += 0.06 * sin(r * 0.11 + 2 * sin(th * 3))
            tex[i * NR + j] = Float(val)
        }
    }
    return tex
}

// MARK: 静态层：眼白、血丝、睫毛（直角坐标，1 px）

private func pnBuildStatic() -> [Float] {
    let W = Int(PN.W), H = Int(PN.H)
    var rnd = Mulberry32(11)
    var buf = [UInt8](repeating: 0, count: W * H * 4)
    for y in 0..<H {
        for x in 0..<W {
            let dx = Double(x) - PN.CX, dy = Double(y) - PN.CY
            let r = hypot(dx, dy), th = atan2(dy, dx)
            var v = 0.80 - 0.30 * pnClamp((r - PN.RI) / 260, 0, 1) - 0.18 * pnClamp(dx * dx / (195 * 195), 0, 1)
                + 0.05 * sin(th * 2 + r * 0.01)
            v -= 0.40 * pow(pnClamp((230 - Double(y)) / 230, 0, 1), 1.4)
            v += (rnd.next() - 0.5) * 0.05
            let b = UInt8((pnClamp(v, 0, 1) * 255).rounded(.toNearestOrEven))
            let p = (y * W + x) * 4
            buf[p] = b; buf[p + 1] = b; buf[p + 2] = b; buf[p + 3] = 255
        }
    }
    let cs = CGColorSpaceCreateDeviceRGB()
    var out = [Float](repeating: 0, count: W * H)
    buf.withUnsafeMutableBytes { raw in
        guard let g = CGContext(data: raw.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        g.translateBy(x: 0, y: CGFloat(H)); g.scaleBy(x: 1, y: -1)          // 跟 canvas 一样左上角是原点
        g.setLineCap(.round)
        for _ in 0..<9 {                                                      // 血丝
            var vx = rnd.next() < 0.5 ? rnd.next() * 60 : 330 + rnd.next() * 60
            var vy = 230 + rnd.next() * 290
            var a = atan2(PN.CY - vy, PN.CX - vx) + (rnd.next() - 0.5) * 1.2
            g.setStrokeColor(red: 150 / 255, green: 150 / 255, blue: 150 / 255, alpha: 1)
            g.setLineWidth(1)
            g.beginPath(); g.move(to: CGPoint(x: vx, y: vy))
            for _ in 0..<28 {
                a += (rnd.next() - 0.5) * 0.7
                vx += 3 * cos(a); vy += 3 * sin(a)
                g.addLine(to: CGPoint(x: vx, y: vy))
                if hypot(vx - PN.CX, vy - PN.CY) < PN.RI { break }
            }
            g.strokePath()
        }
        for _ in 0..<16 {                                                     // 上眼皮的睫毛
            let x0 = -40 + rnd.next() * 470
            let L = 120 + rnd.next() * 110
            let bend = (rnd.next() * 2 - 1) * 0.9
            let wd = 2.5 + rnd.next() * 3.5
            g.setStrokeColor(red: 12 / 255, green: 12 / 255, blue: 12 / 255, alpha: 1)
            for t in 0..<29 {
                let t0 = Double(t) / 29, t1 = Double(t + 1) / 29
                g.setLineWidth(max(1, wd * (1 - Double(t) / 30)))
                g.beginPath()
                g.move(to: CGPoint(x: x0 + bend * L * t0 * t0 + (x0 - 195) * 0.25 * t0, y: -10 + L * t0))
                g.addLine(to: CGPoint(x: x0 + bend * L * t1 * t1 + (x0 - 195) * 0.25 * t1, y: -10 + L * t1))
                g.strokePath()
            }
        }
    }
    for i in 0..<(W * H) { out[i] = Float(buf[i * 4]) / 255 }
    return out
}

// MARK: 像素字

private struct PNBitmap {
    let image: CGImage
    let width: Int
    let height: Int
}

private let PN_F57: [Character: String] = [
    "A": "01110 10001 10001 11111 10001 10001 10001", "B": "11110 10001 10001 11110 10001 10001 11110",
    "C": "01111 10000 10000 10000 10000 10000 01111", "D": "11110 10001 10001 10001 10001 10001 11110",
    "E": "11111 10000 10000 11110 10000 10000 11111", "F": "11111 10000 10000 11110 10000 10000 10000",
    "G": "01111 10000 10000 10011 10001 10001 01111", "H": "10001 10001 10001 11111 10001 10001 10001",
    "I": "111 010 010 010 010 010 111", "J": "00111 00010 00010 00010 00010 10010 01100",
    "K": "10001 10010 10100 11000 10100 10010 10001", "L": "10000 10000 10000 10000 10000 10000 11111",
    "M": "10001 11011 10101 10101 10001 10001 10001", "N": "10001 11001 10101 10011 10001 10001 10001",
    "O": "01110 10001 10001 10001 10001 10001 01110", "P": "11110 10001 10001 11110 10000 10000 10000",
    "Q": "01110 10001 10001 10001 10101 10010 01101", "R": "11110 10001 10001 11110 10100 10010 10001",
    "S": "01111 10000 10000 01110 00001 00001 11110", "T": "11111 00100 00100 00100 00100 00100 00100",
    "U": "10001 10001 10001 10001 10001 10001 01110", "V": "10001 10001 10001 10001 10001 01010 00100",
    "W": "10001 10001 10001 10101 10101 10101 01010", "X": "10001 10001 01010 00100 01010 10001 10001",
    "Y": "10001 10001 01010 00100 00100 00100 00100", "Z": "11111 00001 00010 00100 01000 10000 11111",
    "0": "01110 10011 10101 11001 10001 10001 01110", "1": "010 110 010 010 010 010 111",
    "2": "01110 10001 00001 00010 00100 01000 11111", "3": "11110 00001 00001 01110 00001 00001 11110",
    "4": "00010 00110 01010 10010 11111 00010 00010", "5": "11111 10000 11110 00001 00001 10001 01110",
    "6": "00110 01000 10000 11110 10001 10001 01110", "7": "11111 00001 00010 00100 01000 01000 01000",
    "8": "01110 10001 10001 01110 10001 10001 01110", "9": "01110 10001 10001 01111 00001 00010 01100",
    ".": "0 0 0 0 0 0 1", ":": "0 0 1 0 0 1 0", " ": "000 000 000 000 000 000 000",
    "/": "00001 00010 00010 00100 01000 01000 10000", "\\": "10000 01000 01000 00100 00010 00010 00001",
    ">": "10000 01000 00100 00010 00100 01000 10000", "<": "00001 00010 00100 01000 00100 00010 00001",
    "+": "000 000 010 111 010 000 000", "-": "000 000 000 111 000 000 000",
    "[": "11 10 10 10 10 10 11", "]": "11 01 01 01 01 01 11", "_": "00000 00000 00000 00000 00000 00000 11111",
]

private func pnBitmap(_ rows: [[Bool]], _ w: Int, _ h: Int, _ color: (UInt8, UInt8, UInt8)) -> PNBitmap? {
    var px = [UInt8](repeating: 0, count: w * h * 4)
    for y in 0..<h {
        for x in 0..<w where rows[y][x] {
            let p = (y * w + x) * 4
            px[p] = color.0; px[p + 1] = color.1; px[p + 2] = color.2; px[p + 3] = 255
        }
    }
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let provider = CGDataProvider(data: Data(px) as CFData),
          let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: cs,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { return nil }
    return PNBitmap(image: img, width: w, height: h)
}

private final class PNFonts {
    private var cache: [String: PNBitmap] = [:]

    func pix5(_ text: String, _ color: (UInt8, UInt8, UInt8)) -> PNBitmap? {
        let key = "5|\(text)|\(color.0),\(color.1),\(color.2)"
        if let c = cache[key] { return c }
        let glyphs: [[String]] = text.map { ch in (PN_F57[ch] ?? PN_F57[" "]!).split(separator: " ").map(String.init) }
        let w = max(glyphs.reduce(0) { $0 + $1[0].count + 1 } - 1, 1)
        var rows = [[Bool]](repeating: [Bool](repeating: false, count: w), count: 7)
        var x0 = 0
        for g in glyphs {
            for y in 0..<7 {
                for (x, c) in g[y].enumerated() where c == "1" { rows[y][x0 + x] = true }
            }
            x0 += g[0].count + 1
        }
        let bm = pnBitmap(rows, w, 7, color)
        cache[key] = bm
        return bm
    }

    /// 中文：系统字小尺寸画出来，按 alpha > 84 压成 1-bit，裁到字的边
    func pixZh(_ text: String, _ size: Int, _ color: (UInt8, UInt8, UInt8), bold: Bool = false) -> PNBitmap? {
        let key = "z|\(text)|\(size)|\(color.0),\(color.1),\(color.2)|\(bold)"
        if let c = cache[key] { return c }
        let cw = size * text.count + 8, ch = size + 8
        var buf = [UInt8](repeating: 0, count: cw * ch * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        buf.withUnsafeMutableBytes { raw in
            guard let g = CGContext(data: raw.baseAddress, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: cw * 4,
                                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            g.translateBy(x: 0, y: CGFloat(ch)); g.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(g)
            let font = UIFont.systemFont(ofSize: CGFloat(size), weight: bold ? .semibold : .medium)
            (text as NSString).draw(at: CGPoint(x: 2, y: 3), withAttributes: [.font: font, .foregroundColor: UIColor.black])
            UIGraphicsPopContext()
        }
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        var on = [[Bool]](repeating: [Bool](repeating: false, count: cw), count: ch)
        for y in 0..<ch {
            for x in 0..<cw where buf[(y * cw + x) * 4 + 3] > 84 {
                on[y][x] = true
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        if maxX < 0 { minX = 0; minY = 0; maxX = 0; maxY = 0 }
        let crop = on[minY...maxY].map { Array($0[minX...maxX]) }
        let bm = pnBitmap(crop, maxX - minX + 1, maxY - minY + 1, color)
        cache[key] = bm
        return bm
    }
}

// MARK: 画布

final class PupilNavCanvas: UIView {
    private let entries = PN_ENTRIES
    private var NE: Int { entries.count }
    private var radii: [Double] { (0..<NE).map { PN.BASE_RADII[$0 % PN.BASE_RADII.count] } }
    private lazy var RADII: [Double] = radii

    private var tex: [Float] = []
    private var stat: [Float] = []
    private var ready = false
    private let fonts = PNFonts()

    private var link: CADisplayLink?
    private let start = CACurrentMediaTime()
    private func nowMs() -> Double { (CACurrentMediaTime() - start) * 1000 }

    private let reduce = UIAccessibility.isReduceMotionEnabled
    private var mode = "intro"                  // intro | nav | enter | page | exit
    private var modeAt: Double = 0
    private var pos: Double = 0                 // 连续的选择位置（正上方是第几个入口）
    private var vel: Double = 0
    private var target: Double? = nil
    private var dragging = false, lastAng = 0.0, lastT = 0.0, moved = 0.0
    private var downLabel = -1, downOnPupil = false, downOnBack = false
    private var holdStart = 0.0, holdP = 0.0, holding = false
    private var selShown = 0, selAt = 0.0, tickFlash = -1e9
    private var labelRects: [(i: Int, r: CGRect)] = []
    private var backRect: CGRect? = nil
    private var lastFrame: Double? = nil
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)

    // 场景缓存：参数不变不重算
    private var sceneImage: CGImage?
    private var sceneCell = 2
    private var lastKey = ""
    private var valBuf: [Float] = []
    private var rgba: [UInt8] = []

    // 逻辑坐标 → 屏幕
    private var scale: CGFloat = 1
    private var origin: CGPoint = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isMultipleTouchEnabled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let t = pnBuildIris(), s = pnBuildStatic()
            DispatchQueue.main.async {
                guard let self else { return }
                self.tex = t; self.stat = s; self.ready = true
                let now = self.nowMs()
                self.mode = self.reduce ? "nav" : "intro"; self.modeAt = now; self.selAt = now
                self.setNeedsDisplay()
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        link?.invalidate(); link = nil
        guard window != nil else { return }
        let l = CADisplayLink(target: PNLinkProxy(self), selector: #selector(PNLinkProxy.tick))
        l.add(to: .main, forMode: .common)
        link = l
        light.prepare()
    }

    fileprivate func tick() { setNeedsDisplay() }

    private func sel() -> Int { pnMod(Int(jsRound(pos)), NE) }
    private func setMode(_ m: String, _ now: Double) { mode = m; modeAt = now }

    // MARK: 采样
    @inline(__always) private func staticAt(_ x: Double, _ y: Double) -> Float {
        let W = Int(PN.W), H = Int(PN.H)
        let xi = min(max(Int(x), 0), W - 1), yi = min(max(Int(y), 0), H - 1)
        return stat[yi * W + xi]
    }

    @inline(__always) private func irisAt(_ theta: Double, _ rb: Double) -> Double {
        let NT = PN.NT, NR = PN.NR
        var tt = (theta / (2 * Double.pi)).truncatingRemainder(dividingBy: 1); if tt < 0 { tt += 1 }
        let fx = tt * Double(NT)
        let ti = min(Int(fx), NT - 1), a = fx - Double(ti), ti2 = (ti + 1) % NT
        let fr = pnClamp((rb - PN.R0) / (PN.R1 - PN.R0) * Double(NR - 1), 0, Double(NR) - 1.001)
        let ri = Int(fr), b = fr - Double(ri)
        let v00 = Double(tex[ti * NR + ri]), v01 = Double(tex[ti * NR + ri + 1])
        let v10 = Double(tex[ti2 * NR + ri]), v11 = Double(tex[ti2 * NR + ri + 1])
        return (v00 * (1 - b) + v01 * b) * (1 - a) + (v10 * (1 - b) + v11 * b) * a
    }

    // MARK: 场景（抖动）
    private func renderScene(_ cell: Int, _ z: Double, _ rot: Double, _ rp: Double, _ flat: Double) {
        let key = "\(cell)|" + String(format: "%.3f|%.4f|%.1f|", z, rot, rp) + "\(flat)"
        if key == lastKey { return }
        lastKey = key
        let W = PN.W, H = PN.H, CX = PN.CX, CY = PN.CY
        let gw = Int(ceil(W / Double(cell))), gh = Int(ceil(H / Double(cell)))
        if rgba.count != gw * gh * 4 { rgba = [UInt8](repeating: 0, count: gw * gh * 4) }
        if valBuf.count < gw * gh + 2 * gw + 2 { valBuf = [Float](repeating: 0, count: gw * gh + 2 * gw + 2) }
        let hx = CX - 38, hy = CY - 44
        let ink = PN.INK, paper = PN.PAPER
        let cellD = Double(cell)
        rgba.withUnsafeMutableBufferPointer { d in
            valBuf.withUnsafeMutableBufferPointer { vb in
                var p = 0
                for j in 0..<gh {
                    let y = (Double(j) + 0.5) * cellD, sy = CY + (y - CY) / z, brow = (j & 63) * 64
                    for i in 0..<gw {
                        var v: Double
                        if flat >= 0 {
                            v = flat
                        } else {
                            let x = (Double(i) + 0.5) * cellD, sx = CX + (x - CX) / z
                            let dx = sx - CX, dy = sy - CY, r = sqrt(dx * dx + dy * dy)
                            if r < PN.R1 {
                                let th = atan2(dy, dx), thi = th - rot
                                let edge = PN.RI + 6 * sin(3 * thi + 0.4)
                                let rpt = rp + 1.5 * sin(5 * thi + 1.3) + 0.8 * sin(11 * thi)
                                let rb = PN.RP0 + (r - rp) * (PN.RI - PN.RP0) / (PN.RI - rp)
                                var iv = irisAt(thi, rb)
                                let pb = pnClamp((r - rpt + 3) / 6, 0, 1)
                                iv = 0.03 * (1 - pb) + iv * pb
                                let bl = pnClamp((r - edge + 6) / 12, 0, 1)
                                v = bl > 0 ? iv * (1 - bl) + Double(staticAt(sx, sy)) * bl : iv
                                // 角膜反光：钉在镜头上，不跟虹膜转
                                if sx > hx - 15 && sx < hx + 13 && sy > hy - 19 && sy < hy + 15 &&
                                    abs(sx - (hx - 1)) > 1 && abs(sy - (hy - 2)) > 1 { v = 0.96 }
                                let ddx = sx - (CX + 47), ddy = sy - (CY - 7)
                                if ddx * ddx + ddy * ddy < 9 { v = 0.8 }
                            } else {
                                v = Double(staticAt(sx, sy))
                            }
                            v = pow(pnClamp((v - 0.06) / 0.86, 0, 1), 1.1)
                        }
                        if flat >= 0 {
                            let c0 = Float(v) > PN_BLUE[brow + (i & 63)] ? paper : ink
                            d[p] = c0.0; d[p + 1] = c0.1; d[p + 2] = c0.2; d[p + 3] = 255
                        } else {
                            vb[j * gw + i] = Float(v)
                        }
                        p += 4
                    }
                }
                if flat < 0 {
                    // Atkinson 误差扩散：干脆利落，虹膜纤维看得清
                    for j in 0..<gh {
                        for i in 0..<gw {
                            let k = j * gw + i, old = vb[k]
                            let nw: Float = old > 0.5 ? 1 : 0
                            let e = (old - nw) / 8
                            if i + 1 < gw { vb[k + 1] += e }
                            if i + 2 < gw { vb[k + 2] += e }
                            if j + 1 < gh {
                                if i > 0 { vb[k + gw - 1] += e }
                                vb[k + gw] += e
                                if i + 1 < gw { vb[k + gw + 1] += e }
                            }
                            if j + 2 < gh { vb[k + 2 * gw] += e }
                            let cc = nw > 0 ? paper : ink, q = k * 4
                            d[q] = cc.0; d[q + 1] = cc.1; d[q + 2] = cc.2; d[q + 3] = 255
                        }
                    }
                }
            }
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        if let provider = CGDataProvider(data: Data(rgba) as CFData) {
            sceneImage = CGImage(width: gw, height: gh, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: gw * 4, space: cs,
                                 bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                 provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
        sceneCell = cell
    }

    // MARK: 画法小件（逻辑坐标）
    private var g: CGContext!

    private func color(_ c: (UInt8, UInt8, UInt8)) -> CGColor {
        CGColor(red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: 1)
    }

    private func R(_ x: Double) -> Double { jsRound(x) }

    private func drawImage(_ img: CGImage, _ rect: CGRect) {
        g.saveGState()
        g.translateBy(x: rect.minX, y: rect.maxY)
        g.scaleBy(x: 1, y: -1)
        g.draw(img, in: CGRect(origin: .zero, size: rect.size))
        g.restoreGState()
    }

    private func stamp(_ bm: PNBitmap?, _ x: Double, _ y: Double, _ unit: Int, _ w: Int? = nil) {
        guard let bm else { return }
        let cut = w == nil ? bm.width : min(bm.width, w!)
        if cut <= 0 { return }
        let img: CGImage? = cut == bm.width ? bm.image : bm.image.cropping(to: CGRect(x: 0, y: 0, width: cut, height: bm.height))
        guard let img else { return }
        drawImage(img, CGRect(x: R(x), y: R(y), width: Double(cut * unit), height: Double(bm.height * unit)))
    }

    private func plate(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ fill: (UInt8, UInt8, UInt8),
                       _ border: (UInt8, UInt8, UInt8) = PN.INK, _ b: Double = 1) {
        let x = R(x), y = R(y), w = R(w), h = R(h)
        g.setFillColor(color(border)); g.fill(CGRect(x: x, y: y, width: w, height: h))
        g.setFillColor(color(fill)); g.fill(CGRect(x: x + b, y: y + b, width: w - 2 * b, height: h - 2 * b))
    }

    private func cell(_ x: Double, _ y: Double, _ s: Double, _ c: (UInt8, UInt8, UInt8)) {
        g.setFillColor(color(c))
        g.fill(CGRect(x: jsRound(x / 2) * 2, y: jsRound(y / 2) * 2, width: s, height: s))
    }

    private func fillRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ c: (UInt8, UInt8, UInt8)) {
        g.setFillColor(color(c)); g.fill(CGRect(x: x, y: y, width: w, height: h))
    }

    // MARK: 标题块
    private func drawTitle(_ ent: PNEntry, _ x: Double, _ y: Double, _ since: Double, _ now: Double) {
        let t = now - since
        guard let en = fonts.pix5(ent.en, PN.INK) else { return }
        let zh = fonts.pixZh(ent.zh, 12, PN.INK)
        let unit = min(5, Int(floor(300 / Double(en.width))))
        let w = max(Double(en.width * unit + 24), 170), h = Double(7 * unit + 70)
        let grow = pnClamp(t / 150, 0, 1); if grow <= 0 { return }
        plate(x, y, w, grow >= 1 ? h : max(4, h * floor(grow * 4) / 4), PN.PAPER)
        if t < 120 { return }
        let n = ent.en.count
        let chars = Int(pnClamp(floor((t - 120) / 35) + 1, 0, Double(n)))
        stamp(fonts.pix5(String(ent.en.prefix(chars)), PN.INK), x + 12, y + 14, unit)
        if t > 120 + Double(n) * 35 { stamp(zh, x + 13, y + 14 + Double(7 * unit) + 10, 1) }
        if t > 180 + Double(n) * 35, let gp = fonts.pix5(ent.grp, PN.INK) {
            let gy = y + h - 26
            stamp(gp, x + 13, gy, 2)
            if let badge = ent.badge, let b = fonts.pix5(badge, PN.PAPER) {
                let bx = x + 13 + Double(gp.width * 2) + 10
                fillRect(R(bx - 4), R(gy - 4), Double(b.width * 2 + 8), 22, PN.PINK)
                stamp(b, bx, gy, 2)
            }
        }
    }

    // MARK: 每一帧
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        g = ctx
        let W = PN.W, H = PN.H
        scale = min(bounds.width / CGFloat(W), bounds.height / CGFloat(H))
        origin = CGPoint(x: (bounds.width - CGFloat(W) * scale) / 2, y: (bounds.height - CGFloat(H) * scale) / 2)
        ctx.saveGState()
        ctx.translateBy(x: origin.x, y: origin.y)
        ctx.addPath(UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: CGFloat(W) * scale, height: CGFloat(H) * scale),
                                 cornerRadius: 24).cgPath)
        ctx.clip()
        ctx.scaleBy(x: scale, y: scale)
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        defer { ctx.restoreGState() }
        guard ready else {
            fillRect(0, 0, W, H, PN.INK)
            return
        }

        let now = nowMs()
        var t = now - modeAt

        // ---- 转盘物理 ----
        let dt = min(48, now - (lastFrame ?? now)); lastFrame = now
        if mode == "nav" && !dragging {
            if target == nil && abs(vel) > 0 {
                pos += vel * dt; vel *= exp(-dt / 260)
                if abs(vel) < 0.0007 { vel = 0; target = jsRound(pos) }
            }
            if let tg = target {
                pos += (tg - pos) * (1 - exp(-dt / 80))
                if abs(tg - pos) < 0.001 { pos = tg; target = nil }
            }
        }
        let s = sel()
        if s != selShown {
            selShown = s; selAt = now; tickFlash = now
            light.impactOccurred(); light.prepare()
        }

        // ---- 按住 ----
        if holding {
            holdP = pnClamp((now - holdStart) / PN.HOLD_MS, 0, 1)
            if holdP >= 1 {
                holding = false
                medium.impactOccurred()
                setMode("enter", now); t = 0
            }
        } else if mode == "nav" && holdP > 0 {
            holdP = max(0, holdP - dt / 250)
        }

        // ---- 各模式的场景参数 ----
        var cellSize = 2, z = 1.0, rp = PN.RP0, flat = -1.0
        let rot = -pos * PN.STEP
        let breath = 0.0
        var showUI = true, uiAt = 0.0

        switch mode {
        case "intro":
            let tq = pnStepped(t, 12), p1 = pnClamp(tq / 900, 0, 1)
            let cells = [14, 12, 10, 8, 6, 5, 4, 3, 2]
            cellSize = cells[min(cells.count - 1, Int(floor(p1 * Double(cells.count - 1) + 0.0001)))]
            z = 1.22 - 0.22 * pnEase(p1)
            rp = PN.RP0 + 44 * exp(-5 * p1) * cos(6 * p1)
            uiAt = 650
            if t > 2000 { setMode("nav", now) }
        case "nav":
            rp = PN.RP0 + breath + 30 * pnEase(holdP)
            uiAt = -1e9
        case "enter":
            showUI = false
            let tq2 = pnStepped(t, 12)
            if tq2 < 750 {
                let p2 = tq2 / 750
                z = exp(log(14) * pnEaseIn(p2))
                rp = PN.RP0 + 30 + 30 * p2
            } else if tq2 < 1250 {
                flat = (tq2 - 750) / 500
            } else { setMode("page", now); flat = 1 }
        case "page":
            showUI = false; flat = 1
        case "exit":
            let tq3 = pnStepped(t, 12)
            if tq3 < 300 { flat = 1 - tq3 / 300; showUI = false }
            else if tq3 < 900 {
                let p3 = (tq3 - 300) / 600
                z = exp(log(14) * (1 - pnEase(p3)))
                rp = PN.RP0 + 60 * (1 - pnEase(p3))
                showUI = false
            } else { setMode("nav", now); holdP = 0 }
        default: break
        }

        renderScene(cellSize, z, rot, rp, flat)

        // ---- 画 ----
        if let img = sceneImage {
            drawImage(img, CGRect(x: 0, y: 0, width: Double(img.width * sceneCell), height: Double(img.height * sceneCell)))
        }
        labelRects = []; backRect = nil
        if mode == "page" || (mode == "enter" && t >= 1250) { drawPage(mode == "page" ? t : 0, now) }
        if showUI { drawNav(mode == "intro" ? t - uiAt : 1e9, now, rp) }
    }

    // MARK: 导览界面
    private func drawNav(_ ut: Double, _ now: Double, _ rp: Double) {
        if ut < 0 { return }
        let CX = PN.CX, CY = PN.CY
        let ent = entries[sel()]
        // 顶上
        if ut > 0, let t1 = fonts.pix5("ALCOVE.TERM", PN.INK), let cnt = fonts.pix5(String(NE), PN.INK) {
            plate(16, 44, Double(t1.width * 2 + 16), 26, PN.PAPER); stamp(t1, 24, 50, 2)
            let cw = Double(cnt.width * 2 + 38)
            plate(374 - cw, 44, cw, 26, PN.PAPER)
            let ex = 374 - cw + 8, ey = 52.0
            let eye: [(Double, Double)] = [(2,0),(3,0),(4,0),(5,0),(6,0),(1,1),(7,1),(0,2),(8,2),(1,3),(7,3),(2,4),(3,4),(4,4),(5,4),(6,4),(3,2),(4,2),(5,2),(4,1),(4,3)]
            for p in eye { fillRect(ex + p.0 * 2, ey + p.1 * 2, 2, 2, PN.INK) }
            stamp(cnt, 374 - Double(cnt.width * 2) - 8, 50, 2)
        }
        // 刻度：跟着虹膜转；粉色指针钉在正上方
        let frac = pos - jsRound(pos)
        for d in -9...9 {
            if ut < 200 + Double(abs(d)) * 40 { continue }
            let a = -Double.pi / 2 + (Double(d) - frac) * PN.STEP
            var rr = 292.0
            while rr < 310 { cell(CX + rr * cos(a) - 1, CY + rr * sin(a) - 1, 2, PN.PAPER); rr += 2 }
        }
        if ut > 300 {
            let flash = now - tickFlash < 120
            var rr = flash ? 274.0 : 280.0
            while rr < 318 { fillRect(CX - 2, R(CY - rr), 4, 2, PN.PINK); rr += 2 }
        }
        // 环上的入口
        var items: [(i: Int, d: Double)] = []
        for i in 0..<NE {
            var dd = Double(i) - pos
            dd = dd - Double(NE) * jsRound(dd / Double(NE))
            if abs(dd) > 4.6 { continue }
            items.append((i, dd))
        }
        items.sort { abs($0.d) > abs($1.d) }
        for it in items {
            let appear = 350 + abs(jsRound(it.d)) * 70
            if ut < appear { continue }
            let e = entries[it.i], ang = -Double.pi / 2 + it.d * PN.STEP, rr = RADII[it.i]
            let isSel = it.i == sel() && abs(it.d) < 0.5
            // 从瞳孔拉出来的一根纤维
            let reach = pnClamp((ut - appear) / 260, 0, 1), end = rp + 10 + (rr - 24 - rp - 10) * reach
            var sR = rp + 10
            while sR < end {
                let wob = 3 * sin(sR * 0.07 + Double(it.i))
                cell(CX + sR * cos(ang) - wob * sin(ang), CY + sR * sin(ang) + wob * cos(ang), 2, isSel ? PN.PINK : PN.PAPER)
                sR += 6
            }
            let lx = CX + rr * cos(ang), ly = CY + rr * sin(ang)
            let far = abs(it.d) >= 2.5
            guard let bm = isSel ? fonts.pixZh(e.zh, 14, PN.INK, bold: true) : fonts.pixZh(e.zh, 12, far ? PN.PAPER : PN.INK) else { continue }
            let unit = isSel ? 2 : 1, padx = isSel ? 12.0 : 7.0, pady = isSel ? 9.0 : 5.0
            let w = Double(bm.width * unit) + padx * 2, h = Double(bm.height * unit) + pady * 2
            let x0 = lx - w / 2, y0 = ly - h / 2
            if isSel {
                plate(x0 - 4, y0 - 4, w + 8, h + 8, PN.INK, PN.PINK, 2)
                plate(x0, y0, w, h, PN.PINK, PN.INK, 1)
            } else {
                plate(x0, y0, w, h, far ? PN.INK : PN.PAPER, far ? PN.PAPER : PN.INK, 1)
            }
            stamp(bm, x0 + padx, y0 + pady, unit)
            labelRects.append((it.i, CGRect(x: x0 - 6, y: y0 - 6, width: w + 12, height: h + 12)))
        }
        // 标题
        if ut > 450 { drawTitle(ent, 16, 96, max(selAt, now - ut + 450), now) }
        // 瞳孔：闲着时一圈圈水波，按住时粉色进度圈
        if ut > 750 {
            if holdP > 0 {
                let steps = Int(floor(holdP * 60))
                for k in 0...steps {
                    let aa = -Double.pi / 2 + Double(k) / 60 * Double.pi * 2
                    cell(CX + 46 * cos(aa), CY + 46 * sin(aa), 2, PN.PINK)
                    cell(CX + 48 * cos(aa), CY + 48 * sin(aa), 2, PN.PINK)
                }
            } else {
                let ph = reduce ? 0.3 : (now / 1800).truncatingRemainder(dividingBy: 1)
                for q in 0..<3 {
                    let f = (ph + Double(q) / 3).truncatingRemainder(dividingBy: 1), rad = 40 + f * 42
                    let n = Int(jsRound(44 - f * 26))
                    if f > 0.92 { continue }
                    for k in 0..<n {
                        let a2 = Double(k) / Double(n) * Double.pi * 2 + rad
                        cell(CX + rad * cos(a2), CY + rad * sin(a2), 2, PN.PAPER)
                    }
                }
            }
            let pulse = holdP > 0 ? 1 + floor((now / 120).truncatingRemainder(dividingBy: 2)) : 1
            let heart: [(Double, Double)] = [(-2,-4),(0,-4),(-4,-2),(-2,-2),(0,-2),(2,-2),(-4,0),(-2,0),(0,0),(2,0),(-2,2),(0,2)]
            for p in heart {
                fillRect(CX + p.0 * pulse - (pulse - 1), CY + p.1 * pulse - (pulse - 1), 2 * pulse, 2 * pulse, PN.PINK)
            }
        }
        // 底下的提示
        if ut > 1000, let hint = fonts.pixZh(holdP > 0 ? "进入 " + ent.zh : "转动虹膜 选择", 12, PN.INK),
           let arr = fonts.pix5(">", PN.PINK), let arl = fonts.pix5("<", PN.PINK) {
            let hw = Double(hint.width + 34)
            plate(CX - hw / 2 - 8, 790, hw + 16, Double(hint.height + 16), PN.PAPER)
            stamp(arl, CX - hw / 2 + 2, 798 + Double(hint.height - 7) / 2, 1)
            stamp(hint, CX - Double(hint.width) / 2, 798, 1)
            stamp(arr, CX + hw / 2 - 6, 798 + Double(hint.height - 7) / 2, 1)
        }
    }

    // MARK: 进去以后的页面（今天是占位）
    private func drawPage(_ pt: Double, _ now: Double) {
        let ent = entries[sel()]
        if pt > 0, let back = fonts.pix5("< BACK", PN.INK) {
            let bw = Double(back.width * 2 + 16)
            plate(16, 44, bw, 26, PN.PAPER); stamp(back, 24, 50, 2)
            backRect = CGRect(x: 10, y: 38, width: bw + 12, height: 38)
        }
        if pt > 80 {
            stamp(fonts.pix5("C:\\ALCOVE\\" + ent.grp + "\\" + ent.en + ">", PN.PINK), 18, 88, 2, Int(floor((pt - 80) / 18)) * 6)
        }
        if pt > 150 { drawTitle(ent, 16, 116, now - pt + 150, now) }
        if pt > 500, let en = fonts.pix5(ent.en, PN.INK) {
            let y0 = 116 + Double(7 * min(5, Int(floor(300 / Double(en.width))))) + 70 + 20, h = 790 - y0
            var x = 16.0
            while x < 374 { cell(x, y0, 2, PN.INK); cell(x, y0 + h, 2, PN.INK); x += 6 }
            var y = y0
            while y < y0 + h { cell(16, y, 2, PN.INK); cell(372, y, 2, PN.INK); y += 6 }
            if let ph = fonts.pixZh("[ " + ent.zh + " 页面内容 ]", 12, PN.INK) {
                stamp(ph, PN.CX - Double(ph.width) / 2, y0 + h / 2 - Double(ph.height) / 2, 1)
            }
        }
    }

    // MARK: 手势
    private func local(_ touch: UITouch) -> CGPoint {
        let p = touch.location(in: self)
        return CGPoint(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale)
    }

    private func hit(_ r: CGRect?, _ p: CGPoint) -> Bool {
        guard let r else { return false }
        return p.x >= r.minX && p.x <= r.maxX && p.y >= r.minY && p.y <= r.maxY
    }

    private func goTo(_ i: Int) {
        var dd = Double(i) - pos
        dd = dd - Double(NE) * jsRound(dd / Double(NE))
        target = jsRound(pos + dd); vel = 0
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard ready, let touch = touches.first else { return }
        let now = nowMs(), p = local(touch), px = Double(p.x), py = Double(p.y)
        if mode == "intro" { setMode("nav", now); return }
        if mode == "page" { downOnBack = hit(backRect, p); return }
        if mode != "nav" { return }
        let r = hypot(px - PN.CX, py - PN.CY)
        downLabel = -1
        for lr in labelRects where hit(lr.r, p) { downLabel = lr.i }
        if downLabel < 0 && r < PN.RP0 {
            downOnPupil = true; holding = true; holdStart = now; return
        }
        dragging = true; target = nil; vel = 0; moved = 0
        lastAng = atan2(py - PN.CY, px - PN.CX); lastT = now
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard dragging, let touch = touches.first else { return }
        let now = nowMs(), p = local(touch), px = Double(p.x), py = Double(p.y)
        if hypot(px - PN.CX, py - PN.CY) < 40 { return }
        let ang = atan2(py - PN.CY, px - PN.CX), da = pnWrapPI(ang - lastAng)
        let dp = -da / PN.STEP
        pos += dp; moved += abs(da) * 200
        let dtm = max(1, now - lastT)
        vel = vel * 0.6 + (dp / dtm) * 0.4
        lastAng = ang; lastT = now
    }

    private func end(_ touches: Set<UITouch>) {
        guard let touch = touches.first else { return }
        let now = nowMs(), p = local(touch)
        if mode == "page" {
            if downOnBack && hit(backRect, p) { setMode("exit", now) }
            downOnBack = false; return
        }
        if holding { holding = false; downOnPupil = false; return }
        if !dragging { return }
        dragging = false
        if moved < 8 && downLabel >= 0 { goTo(downLabel); return }
        if now - lastT > 80 { vel = 0 }
        if abs(vel) < 0.0007 { vel = 0; target = jsRound(pos) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }
}

/// CADisplayLink 会强引用 target，拿个小中间人断开，画布走了它就停
private final class PNLinkProxy: NSObject {
    weak var view: PupilNavCanvas?
    init(_ v: PupilNavCanvas) { view = v }
    @objc func tick() { view?.tick() }
}

private struct PupilNavCanvasRep: UIViewRepresentable {
    func makeUIView(context: Context) -> PupilNavCanvas { PupilNavCanvas(frame: .zero) }
    func updateUIView(_ uiView: PupilNavCanvas, context: Context) {}
}

/// 瞳孔导览整页（今天只做出来，没接到任何入口上）
struct PupilNavView: View {
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""
    private var page: Color {
        _ = houseAppearance
        return AlcoveAppearance.isDark ? Color(red: 0x16 / 255, green: 0x14 / 255, blue: 0x1b / 255)
                                       : Color(red: 0xe9 / 255, green: 0xe4 / 255, blue: 0xf0 / 255)
    }
    var body: some View {
        ZStack {
            page.ignoresSafeArea()
            PupilNavCanvasRep().ignoresSafeArea()
        }
    }
}
