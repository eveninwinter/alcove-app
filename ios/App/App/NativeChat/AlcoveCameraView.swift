import SwiftUI
import AVFoundation
import CoreImage
import Photos
import ImageIO
import UniformTypeIdentifiers
import PhotosUI

// 1120 Alcove 相机·ins 苹果风（她 #5809–#5828 一路改定的，效果图 camera-ins-1120/cam10–cam15）。
// 浅灰底；套了边框就把边框图糊开垫在最底下、盖一层雾（毛玻璃，取了她说的“中间值”：糊 33、雾 42%）。
// 顶上 返回｜尺寸｜实况 闪光。取景区整屏宽、3:4 那么高：不带边框尺寸只有 3:4 / 1:1 / 4:3，
// 带边框锁在边框原图的形状（只显示“原始”带锁，点了提示“边框暂无其他尺寸”），两边贴死、上下居中。
// 缩放 .5 / 1× / 2 钉在取景区底边，不跟边框走。卡片四栏：滤镜（她自己做的 LUT，AlcoveFilterEngine）、
// 边框 28 款（camera-1119/export3 重抠过的原图版）、贴纸（像素人｜Clawd）、调节（亮度 柔焦 颗粒 饱和度 色温）。
// 底下相册｜快门｜翻转。按住取景框看原图。
// 实况：开着拍，那段小视频逐帧套上滤镜＋边框＋贴纸，跟静图配对存进手机“照片”；Alcove 相册和发陈璟的是静图。
// 贴纸手势照主聊天打码贴纸（StickerMask.swift）：选中后在取景框任意处一指拖＝挪、两指捏＝缩放，点空白取消；
// 框上左上翻转、右上删除、右下拧＝转＋缩放。

// MARK: - 数据

private enum CamInk {
    static func rgb(_ hex: UInt32, _ a: Double = 1) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255, opacity: a)
    }
    static let page = rgb(0xF3F3F5)
    static let fog = rgb(0xF6F6F8)
    static let ink = rgb(0x1C1C1E)
    static let ink2 = rgb(0x3A3A3C)
    static let dim = rgb(0x8E8E93)
    static let faint = rgb(0xA1A1A6)
    static let width: CGFloat = 1080        // 成片宽（像素）
}

struct CamFrameSpec: Identifiable, Equatable {
    let id: String          // 素材名
    let name: String
    let size: CGSize        // 素材原图像素
    let hole: CGRect        // 照片的洞，占整张的比例
    var aspect: CGFloat { size.height / size.width }

    static let all: [CamFrameSpec] = [
        .init(id: "CamFr01", name: "蝴蝶结蕾丝", size: CGSize(width: 1024, height: 1280), hole: CGRect(x: 0.1006, y: 0.082, width: 0.7979, height: 0.8375)),
        .init(id: "CamFr02", name: "饼干", size: CGSize(width: 1280, height: 720), hole: CGRect(x: 0.1844, y: 0.1778, width: 0.6094, height: 0.6375)),
        .init(id: "CamFr03", name: "粉星星", size: CGSize(width: 1280, height: 954), hole: CGRect(x: 0.0859, y: 0.1143, width: 0.8227, height: 0.7736)),
        .init(id: "CamFr04", name: "粉波点", size: CGSize(width: 1280, height: 1011), hole: CGRect(x: 0.075, y: 0.0821, width: 0.8477, height: 0.7201)),
        .init(id: "CamFr05", name: "奶油熊", size: CGSize(width: 879, height: 1280), hole: CGRect(x: 0.0922, y: 0.0695, width: 0.8134, height: 0.6961)),
        .init(id: "CamFr06", name: "粉色机身", size: CGSize(width: 1246, height: 1280), hole: CGRect(x: 0.0666, y: 0.0578, width: 0.699, height: 0.8898)),
        .init(id: "CamFr07", name: "老手机", size: CGSize(width: 796, height: 1280), hole: CGRect(x: 0.0917, y: 0.1531, width: 0.8379, height: 0.493)),
        .init(id: "CamFr08", name: "相机界面", size: CGSize(width: 1280, height: 736), hole: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)),
        .init(id: "CamFr09", name: "Hello Kitty 碟", size: CGSize(width: 1280, height: 817), hole: CGRect(x: 0.0109, y: 0.0282, width: 0.5078, height: 0.7711)),
        .init(id: "CamFr10", name: "情歌碟", size: CGSize(width: 1280, height: 828), hole: CGRect(x: 0.0148, y: 0.0338, width: 0.5055, height: 0.7621)),
        .init(id: "CamFr11", name: "粉小猫", size: CGSize(width: 1024, height: 1280), hole: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)),
        .init(id: "CamFr12", name: "粉小猫一排", size: CGSize(width: 1024, height: 1280), hole: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)),
        .init(id: "CamFr13", name: "仓鼠咖啡馆", size: CGSize(width: 1024, height: 1280), hole: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)),
        .init(id: "CamFr14", name: "晴空咖啡（横）", size: CGSize(width: 1280, height: 919), hole: CGRect(x: 0.082, y: 0.0892, width: 0.8383, height: 0.8172)),
        .init(id: "CamFr15", name: "晴空咖啡（竖）", size: CGSize(width: 1024, height: 1280), hole: CGRect(x: 0.0996, y: 0.0813, width: 0.8047, height: 0.8367)),
        .init(id: "CamFr16", name: "花田", size: CGSize(width: 1280, height: 919), hole: CGRect(x: 0.0492, y: 0.0348, width: 0.893, height: 0.9282)),
        .init(id: "CamFr17", name: "垂耳兔", size: CGSize(width: 1024, height: 768), hole: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)),
        .init(id: "CamFr18", name: "小狗彩虹", size: CGSize(width: 899, height: 670), hole: CGRect(x: 0.03, y: 0.1179, width: 0.9288, height: 0.791)),
        .init(id: "CamFr19", name: "小狗一排", size: CGSize(width: 899, height: 670), hole: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)),
        .init(id: "CamFr20", name: "咖啡波点星星", size: CGSize(width: 1280, height: 953), hole: CGRect(x: 0.0914, y: 0.1228, width: 0.8102, height: 0.7576)),
        .init(id: "CamFr21", name: "巧克力淋面", size: CGSize(width: 1280, height: 953), hole: CGRect(x: 0.082, y: 0.1805, width: 0.8352, height: 0.6873)),
        .init(id: "CamFr22", name: "草莓月亮", size: CGSize(width: 900, height: 673), hole: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)),
        .init(id: "CamFr23", name: "草莓花边", size: CGSize(width: 900, height: 673), hole: CGRect(x: 0.1644, y: 0.2259, width: 0.6744, height: 0.5646)),
        .init(id: "CamFr24", name: "巧克力椭圆", size: CGSize(width: 900, height: 673), hole: CGRect(x: 0.1089, y: 0.1545, width: 0.7744, height: 0.7088)),
        .init(id: "CamFr25", name: "布丁爱心", size: CGSize(width: 900, height: 673), hole: CGRect(x: 0.09, y: 0.1129, width: 0.8133, height: 0.8262)),
        .init(id: "CamFr26", name: "海星", size: CGSize(width: 900, height: 672), hole: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)),
        .init(id: "CamFr27", name: "Angel", size: CGSize(width: 900, height: 599), hole: CGRect(x: 0.1111, y: 0.0301, width: 0.8033, height: 0.9416)),
        .init(id: "CamFr28", name: "巧克力爱心", size: CGSize(width: 900, height: 700), hole: CGRect(x: 0.1011, y: 0.1329, width: 0.7822, height: 0.7229)),
    ]
}

/// 不带边框时的尺寸
enum CamRatio: String, CaseIterable, Identifiable {
    case portrait = "3:4", square = "1:1", landscape = "4:3"
    var id: String { rawValue }
    var aspect: CGFloat {      // 高 / 宽
        switch self {
        case .portrait: return 4.0 / 3.0
        case .square: return 1
        case .landscape: return 3.0 / 4.0
        }
    }
}

enum CamZoom: String, CaseIterable, Identifiable {
    case half = ".5", one = "1×", two = "2"
    var id: String { rawValue }
}

/// 一张成片的版式：多大、照片塞在哪个洞、盖哪张边框（都是成片像素）
struct CamLayout: Equatable {
    let canvas: CGSize
    let hole: CGRect
    let frameId: String?

    static func make(frame: CamFrameSpec?, ratio: CamRatio) -> CamLayout {
        let w = CamInk.width
        guard let f = frame else {
            let c = CGSize(width: w, height: (w * ratio.aspect).rounded())
            return CamLayout(canvas: c, hole: CGRect(origin: .zero, size: c), frameId: nil)
        }
        let c = CGSize(width: w, height: (w * f.aspect).rounded())
        let h = CGRect(x: f.hole.minX * c.width, y: f.hole.minY * c.height,
                       width: f.hole.width * c.width, height: f.hole.height * c.height)
        return CamLayout(canvas: c, hole: h, frameId: f.id)
    }
}

/// 贴纸栏里的一项：素材名 + 默认宽（成片像素）+ 是不是像素画（放大不糊）
struct CamPiece: Identifiable {
    let id: String
    let width: CGFloat
    let pixel: Bool
    var image: UIImage? { UIImage(named: id) }

    static let groups: [(name: String, items: [CamPiece])] = [
        ("像素人", [
            .init(id: "CamUsHim", width: 300, pixel: true),
            .init(id: "CamUsHer", width: 300, pixel: true),
        ]),
        ("Clawd", [
            .init(id: "CamClawdChop", width: 380, pixel: true),
            .init(id: "CamClawdRamen", width: 300, pixel: true),
            .init(id: "CamClawdBurger", width: 280, pixel: true),
            .init(id: "CamClawdCake", width: 280, pixel: true),
            .init(id: "CamClawdPudding", width: 260, pixel: true),
            .init(id: "CamClawdToast", width: 280, pixel: true),
            .init(id: "CamClawdOnigiri", width: 260, pixel: true),
            .init(id: "CamClawdIcecream", width: 260, pixel: true),
        ]),
    ]
}

struct CamSticker: Identifiable, Equatable {
    let id = UUID()
    let image: UIImage
    let pixel: Bool
    var center: CGPoint      // 成片坐标
    var width: CGFloat       // 成片像素
    var rotation: Double = 0
    var flipped = false
    var height: CGFloat { width * image.size.height / max(image.size.width, 1) }
    static func == (a: CamSticker, b: CamSticker) -> Bool {
        a.id == b.id && a.center == b.center && a.width == b.width && a.rotation == b.rotation && a.flipped == b.flipped
    }
}

/// 调节五项，范围照她 filters.json 的 adjustments
enum CamAdjust: String, CaseIterable, Identifiable {
    case brightness = "亮度", softBlur = "柔焦", grain = "颗粒", saturation = "饱和度", temperature = "色温"
    var id: String { rawValue }
    var range: ClosedRange<Double> {
        switch self {
        case .softBlur, .grain: return 0...100
        default: return -100...100
        }
    }
    var keyPath: WritableKeyPath<AlcoveParams, Double> {
        switch self {
        case .brightness: return \.brightness
        case .softBlur: return \.softBlur
        case .grain: return \.grain
        case .saturation: return \.saturation
        case .temperature: return \.temperature
        }
    }
}

/// 她的滤镜：App 里的 AlcoveFilters 文件夹（filters.json + luts/*.cube）
enum CamFilters {
    static let engine: AlcoveFilterEngine? = {
        guard let url = Bundle.main.url(forResource: "AlcoveFilters", withExtension: nil) else { return nil }
        return try? AlcoveFilterEngine(folder: url)
    }()
    static var list: [AlcoveFilterInfo] { engine?.filters ?? [] }
    static func apply(_ p: AlcoveParams, _ img: CIImage) -> CIImage { engine?.apply(p, to: img) ?? img }
    static let ctx = CIContext(options: [.cacheIntermediates: false])

    /// 一张图整张套上滤镜和调节（拍完那页换滤镜用）
    static func render(_ p: AlcoveParams, _ image: UIImage) -> UIImage {
        guard let ci = CIImage(image: image) else { return image }
        let out = apply(p, ci)
        guard let cg = ctx.createCGImage(out, from: ci.extent) else { return image }
        return UIImage(cgImage: cg)
    }

    /// 滤镜格子的小图：同一张图缩小，每个滤镜各套一遍（不带调节），"" 是原图
    static func thumbs(from image: UIImage) -> [String: UIImage] {
        guard let ci = CIImage(image: image) else { return [:] }
        let ts = 140 / max(ci.extent.width, 1)
        var small = ci.transformed(by: CGAffineTransform(scaleX: ts, y: ts))
        small = small.transformed(by: CGAffineTransform(translationX: -small.extent.minX, y: -small.extent.minY))
        var d: [String: UIImage] = [:]
        if let c = ctx.createCGImage(small, from: small.extent) { d[""] = UIImage(cgImage: c) }
        for f in list {
            let o = apply(AlcoveParams(filter: f.id), small)
            if let c = ctx.createCGImage(o, from: small.extent) { d[f.id] = UIImage(cgImage: c) }
        }
        return d
    }

    /// 相机里滤镜格子用的固定示例图（她滤镜包里的 sample.jpg）
    static var sample: UIImage? {
        guard let url = Bundle.main.url(forResource: "AlcoveFilters", withExtension: nil)?.appendingPathComponent("sample.jpg"),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

/// 拍下来那一下：原图（没上滤镜，拍完那页换滤镜就从它重算）、静图（按拍的时候的滤镜套好）、实况小视频（原样，存的时候再逐帧套）
struct CamCapture {
    let raw: UIImage
    let still: UIImage
    let movie: URL?
    let stillTime: CMTime
    let params: AlcoveParams
    var imported = false     // 1123 从手机相册挑的，不是拍的（拍完那页按钮写“重选”）
}

/// 拍完待确认的一张：合好的成片 + 合成要用的东西（实况要逐帧再合一遍）
struct CamShot {
    let image: UIImage
    let capture: CamCapture
    let layout: CamLayout
    let stickers: [CamSticker]
}

// MARK: - 相机

/// 取景画面单独一个对象：一秒三十帧只让取景框重画，整页不跟着重算
final class CamFeed: ObservableObject {
    @Published var preview: UIImage?
}


final class CamEngine: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    let feed = CamFeed()
    @Published var filterThumbs: [String: UIImage] = [:]   // 滤镜格子：固定示例图，不跟镜头刷新（#5832）
    @Published var denied = false
    @Published var busy = false
    @Published var hasUltraWide = false
    @Published var liveSupported = false

    let session = AVCaptureSession()
    private let videoOut = AVCaptureVideoDataOutput()
    private let photoOut = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "alcove.camera")
    private let ctx = CIContext(options: [.cacheIntermediates: false])
    private var input: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back
    private var zoomOne: CGFloat = 1        // “1×”对应的倍数（三摄虚拟镜头里 1.0 是超广角）
    private var rendering = false

    private var shotDone: ((CamCapture?) -> Void)?
    private var shotParams = AlcoveParams()
    private var shotRaw: UIImage?
    private var shotStill: UIImage?
    private var shotMovie: URL?
    private var shotStillTime = CMTime.invalid

    private let lock = NSLock()
    private var _params = AlcoveParams()
    private var _original = false
    var params: AlcoveParams {
        get { lock.lock(); defer { lock.unlock() }; return _params }
        set { lock.lock(); _params = newValue; lock.unlock() }
    }
    /// 按住取景框：先不上滤镜
    var showOriginal: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _original }
        set { lock.lock(); _original = newValue; lock.unlock() }
    }
    override init() {
        super.init()
        DispatchQueue.global(qos: .utility).async {
            guard let img = CamFilters.sample else { return }
            let d = CamFilters.thumbs(from: img)
            DispatchQueue.main.async { self.filterThumbs = d }
        }
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async { if ok { self.configureAndRun() } else { self.denied = true } }
            }
        default: denied = true
        }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    private func configureAndRun() {
        queue.async {
            if self.input == nil {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                self.attach(self.position)
                self.videoOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                self.videoOut.alwaysDiscardsLateVideoFrames = true
                self.videoOut.setSampleBufferDelegate(self, queue: self.queue)
                if self.session.canAddOutput(self.videoOut) { self.session.addOutput(self.videoOut) }
                if self.session.canAddOutput(self.photoOut) { self.session.addOutput(self.photoOut) }
                self.refreshLive()
                self.orientConnections()
                self.session.commitConfiguration()
                self.applyZoom(self.zoomOne)
            }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    /// 后摄优先用三摄/双广角虚拟镜头，这样 .5 能切到超广角
    private func attach(_ pos: AVCaptureDevice.Position) {
        let types: [AVCaptureDevice.DeviceType] = pos == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera]
            : [.builtInWideAngleCamera]
        guard let device = types.lazy.compactMap({ AVCaptureDevice.default($0, for: .video, position: pos) }).first,
              let newInput = try? AVCaptureDeviceInput(device: device) else { return }
        if let old = input { session.removeInput(old) }
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            input = newInput
            position = pos
            let ultra = device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }
            zoomOne = ultra ? CGFloat(device.virtualDeviceSwitchOverVideoZoomFactors.first?.doubleValue ?? 2) : 1
            DispatchQueue.main.async { self.hasUltraWide = ultra }
        } else if let old = input {
            session.addInput(old)
        }
    }

    private func refreshLive() {
        photoOut.isLivePhotoCaptureEnabled = photoOut.isLivePhotoCaptureSupported
        let ok = photoOut.isLivePhotoCaptureEnabled
        DispatchQueue.main.async { self.liveSupported = ok }
    }

    /// 画面一律竖着出；前摄像头左右镜像（跟照镜子一样），拍出来也镜像，跟取景框里看到的一致
    private func orientConnections() {
        for conn in [videoOut.connection(with: .video), photoOut.connection(with: .video)].compactMap({ $0 }) {
            if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
            if conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = (position == .front)
            }
        }
    }

    func flip() {
        queue.async {
            self.session.beginConfiguration()
            self.attach(self.position == .back ? .front : .back)
            self.refreshLive()
            self.orientConnections()
            self.session.commitConfiguration()
            self.applyZoom(self.zoomOne)
        }
    }

    func setZoom(_ z: CamZoom) {
        queue.async {
            switch z {
            case .half: self.applyZoom(1)
            case .one: self.applyZoom(self.zoomOne)
            case .two: self.applyZoom(self.zoomOne * 2)
            }
        }
    }

    private func applyZoom(_ f: CGFloat) {
        guard let d = input?.device else { return }
        do {
            try d.lockForConfiguration()
            d.videoZoomFactor = min(max(f, d.minAvailableVideoZoomFactor), d.maxAvailableVideoZoomFactor)
            d.unlockForConfiguration()
        } catch {}
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !rendering, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        rendering = true
        defer { rendering = false }
        var img = CIImage(cvPixelBuffer: pb)
        let s = min(1, 900 / max(img.extent.width, 1))
        img = img.transformed(by: CGAffineTransform(scaleX: s, y: s))
        img = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
        let out = showOriginal ? img : CamFilters.apply(params, img)
        guard let cg = ctx.createCGImage(out, from: img.extent) else { return }
        let ui = UIImage(cgImage: cg)
        let feed = self.feed
        DispatchQueue.main.async { feed.preview = ui }
    }

    func shoot(live: Bool, flash: Bool, _ done: @escaping (CamCapture?) -> Void) {
        guard !busy else { return }
        busy = true
        let p = params
        queue.async {
            self.shotDone = done
            self.shotParams = p
            self.shotRaw = nil
            self.shotStill = nil
            self.shotMovie = nil
            self.shotStillTime = .invalid
            let settings = AVCapturePhotoSettings()
            if flash, self.photoOut.supportedFlashModes.contains(.on) { settings.flashMode = .on }
            if live, self.photoOut.isLivePhotoCaptureEnabled {
                settings.livePhotoMovieFileURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("alcove-live-\(UUID().uuidString).mov")
            }
            self.photoOut.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(), let raw = UIImage(data: data) else { return }
        // 先按方向摆正，再上滤镜（跟取景框同一套）
        let upright = UIGraphicsImageRenderer(size: raw.size, format: {
            let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f
        }()).image { _ in raw.draw(in: CGRect(origin: .zero, size: raw.size)) }
        let k = min(1, 2160 / max(upright.size.width, upright.size.height))
        let small = k >= 1 ? upright : UIGraphicsImageRenderer(size: CGSize(width: (upright.size.width * k).rounded(), height: (upright.size.height * k).rounded()), format: {
            let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f
        }()).image { rc in upright.draw(in: rc.format.bounds) }
        shotRaw = small
        shotStill = CamFilters.render(shotParams, small)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL,
                     duration: CMTime, photoDisplayTime: CMTime, resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        guard error == nil else { return }
        shotMovie = outputFileURL
        shotStillTime = photoDisplayTime
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        var result: CamCapture?
        if let raw = shotRaw, let still = shotStill {
            result = CamCapture(raw: raw, still: still, movie: shotMovie, stillTime: shotStillTime, params: shotParams)
        }
        let done = shotDone
        shotDone = nil
        shotRaw = nil
        shotStill = nil
        DispatchQueue.main.async {
            self.busy = false
            done?(result)
        }
    }
}

// MARK: - 合成成片

enum CamCompose {
    /// 套了边框：边框外圈透明的地方（唱片四周、老手机圆角）就留透明，存成 PNG；没边框是整张照片
    static func render(photo: UIImage, layout: CamLayout, stickers: [CamSticker]) -> UIImage {
        let size = layout.canvas
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = layout.frameId == nil
        return UIGraphicsImageRenderer(size: size, format: fmt).image { rc in
            let cg = rc.cgContext
            // 照片：铺满边框的洞
            let r = layout.hole
            let k = max(r.width / photo.size.width, r.height / photo.size.height)
            let pw = photo.size.width * k, ph = photo.size.height * k
            cg.saveGState()
            cg.clip(to: r)
            photo.draw(in: CGRect(x: r.midX - pw / 2, y: r.midY - ph / 2, width: pw, height: ph))
            cg.restoreGState()
            drawOverlay(cg, layout: layout, stickers: stickers)
        }
    }

    /// 垫白底（手机“照片”里的实况静图是 JPEG，透明的地方不垫会变黑）
    static func flattened(_ image: UIImage) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: fmt).image { rc in
            UIColor.white.setFill()
            rc.fill(CGRect(origin: .zero, size: image.size))
            image.draw(at: .zero)
        }
    }

    /// 边框 + 贴纸，透明底（实况每一帧盖在照片上面）
    static func overlay(layout: CamLayout, stickers: [CamSticker], size: CGSize) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: size, format: fmt).image { rc in
            let cg = rc.cgContext
            cg.scaleBy(x: size.width / layout.canvas.width, y: size.height / layout.canvas.height)
            drawOverlay(cg, layout: layout, stickers: stickers)
        }
    }

    private static func drawOverlay(_ cg: CGContext, layout: CamLayout, stickers: [CamSticker]) {
        if let id = layout.frameId, let img = UIImage(named: id) {
            img.draw(in: CGRect(origin: .zero, size: layout.canvas))
        }
        for s in stickers {
            cg.saveGState()
            cg.translateBy(x: s.center.x, y: s.center.y)
            cg.rotate(by: CGFloat(s.rotation))
            if s.flipped { cg.scaleBy(x: -1, y: 1) }
            cg.interpolationQuality = s.pixel ? .none : .high
            s.image.draw(in: CGRect(x: -s.width / 2, y: -s.height / 2, width: s.width, height: s.height))
            cg.restoreGState()
        }
    }
}

// MARK: - 实况：小视频逐帧合成，跟静图配对存进手机“照片”

enum CamLive {
    enum Failure: Error { case noMovie, writer, denied }

    /// 照片和视频靠同一个 identifier 配成一张实况：视频写 content.identifier + still-image-time，照片写 MakerApple["17"]
    static func process(shot: CamShot, params: AlcoveParams, identifier: String) async throws -> URL {
        guard let movie = shot.capture.movie else { throw Failure.noMovie }
        let asset = AVURLAsset(url: movie)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Failure.noMovie }
        let transform = try await track.load(.preferredTransform)
        let duration = try await asset.load(.duration)

        let layout = shot.layout
        let outW = even(layout.canvas.width * 0.75), outH = even(layout.canvas.height * 0.75)
        let outSize = CGSize(width: outW, height: outH)
        let k = outW / layout.canvas.width
        // Core Image 的坐标原点在左下
        let hole = CGRect(x: layout.hole.minX * k, y: outH - layout.hole.maxY * k,
                          width: layout.hole.width * k, height: layout.hole.height * k)
        let base = CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: outSize))
        let overlay = CamCompose.overlay(layout: layout, stickers: shot.stickers, size: outSize).cgImage.map { CIImage(cgImage: $0) }
        let orient = orientation(of: transform)

        let reader = try AVAssetReader(asset: asset)
        let rOut = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        rOut.alwaysCopiesSampleData = false
        guard reader.canAdd(rOut) else { throw Failure.writer }
        reader.add(rOut)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("alcove-live-out-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let idItem = AVMutableMetadataItem()
        idItem.key = "com.apple.quicktime.content.identifier" as NSString
        idItem.keySpace = .quickTimeMetadata
        idItem.value = identifier as NSString
        idItem.dataType = "com.apple.metadata.datatype.UTF-8"
        writer.metadata = [idItem]

        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outW),
            AVVideoHeightKey: Int(outH),
        ])
        vIn.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(outW),
            kCVPixelBufferHeightKey as String: Int(outH),
        ])
        guard writer.canAdd(vIn) else { throw Failure.writer }
        writer.add(vIn)

        let spec: [String: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: "com.apple.metadata.datatype.int8",
        ]
        var desc: CMFormatDescription?
        _ = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(allocator: kCFAllocatorDefault, metadataType: kCMMetadataFormatType_Boxed,
                                                                    metadataSpecifications: [spec] as CFArray, formatDescriptionOut: &desc)
        let mIn = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: desc)
        let mAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: mIn)
        guard writer.canAdd(mIn) else { throw Failure.writer }
        writer.add(mIn)

        guard writer.startWriting(), reader.startReading() else { throw Failure.writer }
        writer.startSession(atSourceTime: .zero)

        let stillItem = AVMutableMetadataItem()
        stillItem.key = "com.apple.quicktime.still-image-time" as NSString
        stillItem.keySpace = .quickTimeMetadata
        stillItem.value = 0 as NSNumber
        stillItem.dataType = "com.apple.metadata.datatype.int8"
        let stillAt = shot.capture.stillTime.isValid ? shot.capture.stillTime
            : CMTime(value: duration.value / 2, timescale: duration.timescale)

        let ci = CIContext()
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)
        var first: CMTime?
        var metaDone = false
        while let sb = rOut.copyNextSampleBuffer() {
            guard let px = CMSampleBufferGetImageBuffer(sb) else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sb)
            if first == nil { first = pts }
            let start = first ?? pts
            if !metaDone {
                let at = CMTimeMaximum(.zero, CMTimeSubtract(stillAt, start))
                waitReady(mIn)
                _ = mAdaptor.append(AVTimedMetadataGroup(items: [stillItem], timeRange: CMTimeRange(start: at, duration: CMTime(value: 1, timescale: 100))))
                mIn.markAsFinished()
                metaDone = true
            }
            var img = CIImage(cvPixelBuffer: px).oriented(orient)
            img = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
            let src = img.extent
            img = CamFilters.apply(params, img).cropped(to: src)
            let s = max(hole.width / src.width, hole.height / src.height)
            img = img.transformed(by: CGAffineTransform(scaleX: s, y: s))
            img = img.transformed(by: CGAffineTransform(translationX: hole.midX - img.extent.midX, y: hole.midY - img.extent.midY))
                .cropped(to: hole)
            var frame = img.composited(over: base)
            if let overlay { frame = overlay.composited(over: frame) }
            waitReady(vIn)
            guard let pool = adaptor.pixelBufferPool else { break }
            var outPx: CVPixelBuffer?
            _ = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outPx)
            guard let outPx else { continue }
            ci.render(frame, to: outPx, bounds: CGRect(origin: .zero, size: outSize), colorSpace: srgb)
            _ = adaptor.append(outPx, withPresentationTime: CMTimeSubtract(pts, start))
        }
        if !metaDone { mIn.markAsFinished() }
        vIn.markAsFinished()
        await writer.finishWriting()
        reader.cancelReading()
        guard writer.status == .completed else { throw Failure.writer }
        return url
    }

    /// 静图 JPEG，带上配对用的 identifier
    static func stillData(_ image: UIImage, identifier: String) -> Data? {
        guard let cg = image.cgImage else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        let props: [CFString: Any] = [
            kCGImagePropertyMakerAppleDictionary: ["17": identifier],
            kCGImageDestinationLossyCompressionQuality: 0.92,
        ]
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    /// 不是实况：成片照样存一份进手机“照片”（#5842 她：点存下也要进手机相册）
    static func saveStillToPhotos(_ data: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.denied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
        }
    }

    static func saveToPhotos(still: Data, movie: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.denied }
        try await PHPhotoLibrary.shared().performChanges {
            let req = PHAssetCreationRequest.forAsset()
            req.addResource(with: .photo, data: still, options: nil)
            let opt = PHAssetResourceCreationOptions()
            opt.shouldMoveFile = true
            req.addResource(with: .pairedVideo, fileURL: movie, options: opt)
        }
    }

    private static func waitReady(_ input: AVAssetWriterInput) {
        var n = 0
        while !input.isReadyForMoreMediaData && n < 400 { usleep(5000); n += 1 }
    }

    private static func even(_ v: CGFloat) -> CGFloat { CGFloat(Int(v.rounded()) / 2 * 2) }

    private static func orientation(of t: CGAffineTransform) -> CGImagePropertyOrientation {
        if t.a == 0 && t.b == 1 && t.c == -1 && t.d == 0 { return .right }
        if t.a == 0 && t.b == -1 && t.c == 1 && t.d == 0 { return .left }
        if t.a == -1 && t.b == 0 && t.c == 0 && t.d == -1 { return .down }
        return .up
    }
}

// MARK: - 页面

struct AlcoveCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = CamEngine()
    @State private var params = AlcoveParams()
    @State private var tab = 0
    @State private var adjust: CamAdjust = .brightness
    @State private var frame: CamFrameSpec?
    @State private var ratio: CamRatio = .portrait
    @State private var pieceGroup = 0
    @State private var stickers: [CamSticker] = []
    @State private var selected: UUID?
    @State private var shot: CamShot?
    @State private var lastSaved: UIImage?
    @State private var showAlbum = false
    @State private var toast: String?
    @State private var live = false
    @State private var flashOn = false
    @State private var zoom: CamZoom = .one
    @State private var showPicker = false            // 1123 #5940 从手机相册挑一张来套滤镜
    @State private var pickItem: PhotosPickerItem?
    @State private var importing = false

    private let tabs = ["滤镜", "边框", "贴纸", "调节"]
    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 47 }
    private var safeBottom: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.bottom ?? 34 }
    private var layout: CamLayout { CamLayout.make(frame: frame, ratio: ratio) }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            // 从底往上排：快门中心离底一截 → 卡片 → 取景区（整屏宽、3:4 那么高）；顶得太高就让顶栏压在取景区上沿
            let areaH = W * 4 / 3
            let dockY = H - max(safeBottom, 20) - 14
            let cardH: CGFloat = 138
            let cardTop = dockY - 28 - 6 - cardH
            let areaTop = min(safeTop + 50, cardTop - 4 - areaH)
            let vf = viewfinderSize(W: W, areaH: areaH, maxH: cardTop - 4 - safeTop)
            let vfY = vf.height <= areaH ? areaTop + areaH / 2 : areaTop + areaH - vf.height / 2
            ZStack(alignment: .topLeading) {
                backdrop(W: W, H: H)
                CamLiveCanvas(feed: engine.feed, layout: layout, size: vf, stickers: $stickers, selected: $selected,
                              hold: { engine.showOriginal = $0 })
                    .frame(width: vf.width, height: vf.height)
                    .position(x: W / 2, y: vfY)
                if engine.denied {
                    deniedNote.position(x: W / 2, y: areaTop + areaH / 2)
                }
                zoomBar.position(x: W / 2, y: areaTop + areaH - 12 - 18)
                topBar.frame(width: W, height: 44).position(x: W / 2, y: safeTop + 24)
                if let toast {
                    toastView(toast).position(x: W / 2, y: safeTop + 76)
                }
                card.frame(width: W - 24, height: cardH).position(x: W / 2, y: cardTop + cardH / 2)
                dock(W: W).position(x: W / 2, y: dockY)
                if let shot {
                    CamConfirmView(shot: shot, imported: shot.capture.imported, retake: {
                        if let m = shot.capture.movie { try? FileManager.default.removeItem(at: m) }
                        self.shot = nil
                    }, saved: { img in
                        lastSaved = img
                        self.shot = nil
                    })
                    .transition(.opacity)
                }
            }
            .frame(width: W, height: H)
        }
        .ignoresSafeArea()
        .onAppear {
            engine.params = params
            engine.start()
        }
        .onDisappear { engine.stop() }
        .onChange(of: params) { _, p in engine.params = p }
        .onChange(of: layout.canvas) { old, new in
            // 换尺寸/换边框：贴纸跟着成片按比例挪，别跑到画外头
            guard old != new, old.width > 0, old.height > 0 else { return }
            let sx = new.width / old.width, sy = new.height / old.height
            for i in stickers.indices {
                stickers[i].center = CGPoint(x: stickers[i].center.x * sx, y: stickers[i].center.y * sy)
            }
        }
        .fullScreenCover(isPresented: $showAlbum) { NativeAlbumView() }
        .photosPicker(isPresented: $showPicker, selection: $pickItem, matching: .images)
        .onChange(of: pickItem) { _, item in
            guard let item else { return }
            pickItem = nil
            importPhoto(item)
        }
        .animation(.easeOut(duration: 0.18), value: shot != nil)
        .animation(.easeInOut(duration: 0.35), value: frame?.id)
    }

    /// 取景框多大：整屏宽；太高（竖长的边框）就按能放下的高度缩
    private func viewfinderSize(W: CGFloat, areaH: CGFloat, maxH: CGFloat) -> CGSize {
        let a = layout.canvas.height / max(layout.canvas.width, 1)
        if W * a <= areaH { return CGSize(width: W, height: W * a) }
        let h = min(W * a, maxH)
        return CGSize(width: h / a, height: h)
    }

    // MARK: 底：浅灰；套了边框就垫边框图糊开＋一层雾

    private func backdrop(W: CGFloat, H: CGFloat) -> some View {
        ZStack {
            CamInk.page
            if let f = frame {
                Image(f.id).resizable()
                    .frame(width: W + 84, height: H + 84)
                    .blur(radius: 33)
                    .saturation(1.32)
                    .frame(width: W, height: H)
                    .clipped()
                    .transition(.opacity)
                CamInk.fog.opacity(0.42)
            }
        }
        .frame(width: W, height: H)
        .allowsHitTesting(false)
    }

    private var deniedNote: some View {
        VStack(spacing: 10) {
            Text("相机没开权限").font(.system(size: 15, weight: .semibold)).foregroundColor(CamInk.ink)
            Button("去设置里打开") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .font(.system(size: 13, weight: .semibold)).foregroundColor(CamInk.ink2)
        }
        .padding(18)
        .background(CamFrost(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)))
    }

    // MARK: 顶栏

    private var topBar: some View {
        ZStack {
            HStack(spacing: 10) {
                roundButton("chevron.left", size: 15) { dismiss() }
                // 1123 #5940 她：「再加一个可以相册选图然后叠加滤镜的功能」
                roundButton(importing ? "hourglass" : "photo.badge.plus", size: 15) { if !importing { showPicker = true } }
                Spacer()
                roundButton(live ? "livephoto" : "livephoto.slash", size: 17) { toggleLive() }
                roundButton(flashOn ? "bolt.fill" : "bolt.slash", size: 15) { flashOn.toggle() }
            }
            .padding(.horizontal, 16)
            sizeSwitch
        }
    }

    private func roundButton(_ icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size, weight: .semibold)).foregroundColor(CamInk.ink)
                .frame(width: 40, height: 40)
                .background(CamFrost(shape: Circle()))
        }
        .buttonStyle(.plain)
    }

    /// 尺寸：不带边框 3:4 / 1:1 / 4:3；带边框只有“原始”，锁着
    @ViewBuilder private var sizeSwitch: some View {
        if frame != nil {
            Button { flash("边框暂无其他尺寸") } label: {
                HStack(spacing: 6) {
                    Text("原始").font(.system(size: 13, weight: .bold)).foregroundColor(CamInk.ink)
                    Image(systemName: "lock.fill").font(.system(size: 10, weight: .semibold)).foregroundColor(CamInk.faint)
                }
                .padding(.horizontal, 15)
                .frame(height: 34)
                .background(CamFrost(shape: Capsule()))
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 2) {
                ForEach(CamRatio.allCases) { r in
                    Button { ratio = r } label: {
                        Text(r.rawValue)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(ratio == r ? CamInk.ink : CamInk.faint)
                            .padding(.horizontal, 9)
                            .frame(height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .background(CamFrost(shape: Capsule()))
        }
    }

    private func toastView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(CamInk.ink2)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(CamFrost(shape: Capsule()))
            .transition(.opacity)
            .allowsHitTesting(false)
    }

    // MARK: 缩放（钉在取景区底边）

    private var zoomBar: some View {
        HStack(spacing: 4) {
            ForEach(CamZoom.allCases.filter { $0 != .half || engine.hasUltraWide }) { z in
                Button {
                    zoom = z
                    engine.setZoom(z)
                } label: {
                    Text(z.rawValue)
                        .font(.system(size: zoom == z ? 12 : 11, weight: .semibold))
                        .foregroundColor(zoom == z ? CamInk.ink : CamInk.ink2)
                        .frame(width: zoom == z ? 38 : 30, height: 30)
                        .background {
                            if zoom == z {
                                Capsule().fill(Color.white).shadow(color: .black.opacity(0.12), radius: 2.5, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(CamFrost(shape: Capsule()))
    }

    // MARK: 卡片：滤镜 / 边框 / 贴纸 / 调节

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 18) {
                ForEach(tabs.indices, id: \.self) { i in
                    Button { tab = i } label: {
                        Text(tabs[i])
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(tab == i ? CamInk.ink : CamInk.faint)
                            .frame(height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 14)
            Group {
                switch tab {
                case 0: filterPane
                case 1: framePane
                case 2: stickerPane
                default: adjustPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CamFrost(shape: RoundedRectangle(cornerRadius: 24, style: .continuous)))
    }

    private var filterPane: some View {
        CamFilterStrip(params: $params, thumbs: engine.filterThumbs)
    }

    private var framePane: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                frameTile(nil)
                ForEach(CamFrameSpec.all) { f in frameTile(f) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .padding(.top, 4)
    }

    private func frameTile(_ f: CamFrameSpec?) -> some View {
        let on = frame?.id == f?.id
        return Button { frame = f } label: {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.55))
                    if let f {
                        CamFrameThumb(frame: f)
                    } else {
                        Text("无").font(.system(size: 12, weight: .semibold)).foregroundColor(CamInk.dim)
                    }
                }
                .frame(width: 56, height: 56)
                .overlay {
                    if on {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CamInk.ink, lineWidth: 1.5).padding(-3.5)
                    }
                }
                Text(f?.name ?? "无边框")
                    .font(.system(size: 10, weight: on ? .bold : .semibold))
                    .foregroundColor(on ? CamInk.ink : CamInk.dim)
                    .lineLimit(1)
                    .frame(width: 64)
            }
        }
        .buttonStyle(.plain)
    }

    private var stickerPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ForEach(CamPiece.groups.indices, id: \.self) { i in
                    Button { pieceGroup = i } label: {
                        Text(CamPiece.groups[i].name)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(pieceGroup == i ? .white : CamInk.dim)
                            .padding(.horizontal, 10)
                            .frame(height: 22)
                            .background(Capsule().fill(pieceGroup == i ? CamInk.ink : Color.white.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 14)
            .padding(.top, 7)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(CamPiece.groups[pieceGroup].items) { p in
                        Button {
                            if let img = p.image { add(image: img, width: p.width, pixel: p.pixel) }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(Color.white.opacity(0.65))
                                    .shadow(color: .black.opacity(0.06), radius: 5, y: 3)
                                if let img = p.image {
                                    Image(uiImage: img).resizable().interpolation(p.pixel ? .none : .high).scaledToFit().padding(7)
                                }
                            }
                            .frame(width: 56, height: 56)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
    }

    private var adjustPane: some View {
        CamAdjustStrip(params: $params, adjust: $adjust)
            .padding(.top, 10)
    }

    // MARK: 底下三颗

    private func dock(W: CGFloat) -> some View {
        HStack(spacing: 0) {
            Button { showAlbum = true } label: {
                ZStack {
                    if let lastSaved {
                        Image(uiImage: lastSaved).resizable().scaledToFill()
                    } else {
                        Color.white.opacity(0.6)
                        Image(systemName: "photo.on.rectangle").font(.system(size: 15)).foregroundColor(CamInk.dim)
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.white, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            Spacer()
            Button { shoot() } label: {
                ZStack {
                    CamFrost(shape: Circle())
                    Circle().fill(Color.white.opacity(0.85)).frame(width: 45, height: 45)
                    if engine.busy { ProgressView().tint(CamInk.ink) }
                }
                .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .disabled(engine.busy || engine.denied)
            Spacer()
            Button {
                zoom = .one
                engine.flip()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 17, weight: .medium)).foregroundColor(CamInk.ink)
                    .frame(width: 40, height: 40)
                    .background(CamFrost(shape: Circle()))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 38)
        .frame(width: W, height: 60)
    }

    // MARK: 动作

    private func toggleLive() {
        guard engine.liveSupported else { flash("这里拍不了实况"); return }
        live.toggle()
        flash(live ? "实况已打开" : "实况已关闭")
    }

    private func add(image: UIImage, width: CGFloat, pixel: Bool) {
        let c = layout.canvas
        // 一个叠一个往右下错一点，别全压在正中
        let n = CGFloat(stickers.count % 5)
        let s = CamSticker(image: image, pixel: pixel,
                           center: CGPoint(x: c.width / 2 + n * 40, y: c.height * 0.6 + n * 40), width: width)
        stickers.append(s)
        selected = s.id
    }

    private func shoot() {
        let keepLayout = layout
        let keepStickers = stickers
        engine.shoot(live: live, flash: flashOn) { cap in
            guard let cap else { flash("没拍上，再按一次"); return }
            selected = nil
            let img = CamCompose.render(photo: cap.still, layout: keepLayout, stickers: keepStickers)
            shot = CamShot(image: img, capture: cap, layout: keepLayout, stickers: keepStickers)
        }
    }

    /// 相册里挑的一张：摆正、长边缩到 3024，当成“刚拍的原图”进拍完那页（换滤镜、调节、存下、发陈璟都一样）。
    /// 选了边框就塞进边框的洞；没边框就照这张图自己的长宽，不裁成 3:4。贴纸跟着成片按比例挪
    private func importPhoto(_ item: PhotosPickerItem) {
        importing = true
        let keepFrame = layout
        let keepStickers = stickers
        let p = params
        Task {
            defer { importing = false }
            guard let data = try? await item.loadTransferable(type: Data.self) else { flash("这张读不出来，换一张"); return }
            let made: (UIImage, UIImage)? = await Task.detached(priority: .userInitiated) {
                guard let img = UIImage(data: data), img.size.width > 0, img.size.height > 0 else { return nil }
                let k = min(1, 3024 / max(img.size.width, img.size.height))
                let size = CGSize(width: (img.size.width * k).rounded(), height: (img.size.height * k).rounded())
                let fmt = UIGraphicsImageRendererFormat()
                fmt.scale = 1
                fmt.opaque = true
                let raw = UIGraphicsImageRenderer(size: size, format: fmt).image { rc in img.draw(in: rc.format.bounds) }
                return (raw, CamFilters.render(p, raw))
            }.value
            guard let made else { flash("这张读不出来，换一张"); return }
            let (raw, still) = made
            let L = keepFrame.frameId != nil ? keepFrame
                : CamLayout(canvas: raw.size, hole: CGRect(origin: .zero, size: raw.size), frameId: nil)
            let sx = L.canvas.width / max(keepFrame.canvas.width, 1), sy = L.canvas.height / max(keepFrame.canvas.height, 1)
            let moved = keepStickers.map { s -> CamSticker in
                var s = s
                s.center = CGPoint(x: s.center.x * sx, y: s.center.y * sy)
                s.width *= sx
                return s
            }
            let cap = CamCapture(raw: raw, still: still, movie: nil, stillTime: .invalid, params: p, imported: true)
            selected = nil
            shot = CamShot(image: CamCompose.render(photo: still, layout: L, stickers: moved), capture: cap, layout: L, stickers: moved)
        }
    }

    private func flash(_ text: String) {
        withAnimation(.easeOut(duration: 0.15)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if toast == text { withAnimation(.easeOut(duration: 0.2)) { toast = nil } }
        }
    }
}

private struct CamLiveCanvas: View {
    @ObservedObject var feed: CamFeed
    let layout: CamLayout
    let size: CGSize
    @Binding var stickers: [CamSticker]
    @Binding var selected: UUID?
    let hold: (Bool) -> Void
    var body: some View {
        CamCanvasView(layout: layout, size: size, photo: feed.preview, stickers: $stickers, selected: $selected, hold: hold)
    }
}

/// 边框格子：不跟镜头（#5839），就是边框原图，照片的洞里填白
private struct CamFrameThumb: View {
    let frame: CamFrameSpec
    var body: some View {
        let a = frame.aspect
        let size = a >= 1 ? CGSize(width: 52 / a, height: 52) : CGSize(width: 52, height: 52 * a)
        let h = frame.hole
        ZStack(alignment: .topLeading) {
            Color.clear
            Color.white
                .frame(width: h.width * size.width, height: h.height * size.height)
                .position(x: h.midX * size.width, y: h.midY * size.height)
            Image(frame.id).resizable().frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// 滤镜条：原图＋她的 7 个滤镜（格子是固定小图）＋强度滑杆。相机卡片和拍完那页共用
private struct CamFilterStrip: View {
    @Binding var params: AlcoveParams
    let thumbs: [String: UIImage]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    tile(nil, name: "原图")
                    ForEach(CamFilters.list) { f in tile(f.id, name: f.name) }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            CamSliderRow(label: "强度", value: $params.intensity, range: 0...100)
                .opacity(params.filter == nil ? 0.35 : 1)
                .disabled(params.filter == nil)
        }
    }

    private func tile(_ id: String?, name: String) -> some View {
        let on = params.filter == id
        return Button {
            params.filter = id
            params.intensity = 100
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Color.black.opacity(0.06)
                    if let img = thumbs[id ?? ""] {
                        Image(uiImage: img).resizable().scaledToFill()
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(on ? 0 : 0.08), radius: 5, y: 3)
                .overlay {
                    if on {
                        RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(CamInk.ink, lineWidth: 1.5).padding(-3.5)
                    }
                }
                Text(name)
                    .font(.system(size: 10, weight: on ? .bold : .semibold))
                    .foregroundColor(on ? CamInk.ink : CamInk.dim)
            }
        }
        .buttonStyle(.plain)
    }
}

/// 调节条：亮度 柔焦 颗粒 饱和度 色温，点哪个下面滑杆调哪个
private struct CamAdjustStrip: View {
    @Binding var params: AlcoveParams
    @Binding var adjust: CamAdjust

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CamAdjust.allCases) { a in
                        let on = adjust == a
                        Button { adjust = a } label: {
                            HStack(spacing: 5) {
                                Text(a.rawValue).font(.system(size: 12, weight: .semibold))
                                Text("\(Int(params[keyPath: a.keyPath]))").font(.system(size: 10, weight: .semibold)).opacity(0.7)
                            }
                            .foregroundColor(on ? .white : CamInk.dim)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(Capsule().fill(on ? CamInk.ink : Color.white.opacity(0.5)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }
            CamSliderRow(label: nil, value: Binding(get: { params[keyPath: adjust.keyPath] },
                                                    set: { params[keyPath: adjust.keyPath] = $0 }),
                         range: adjust.range)
        }
    }
}

private struct CamSliderRow: View {
    let label: String?
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 10) {
            if let label {
                Text(label).font(.system(size: 11, weight: .semibold)).foregroundColor(CamInk.dim)
            }
            Slider(value: $value, in: range, step: 1).tint(CamInk.ink)
            Text("\(Int(value))")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(CamInk.ink)
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 28)
    }
}

/// 磨砂白：毛玻璃 + 一层白 + 细白边 + 很淡的阴影（效果图 cam10 那套）
private struct CamFrost<S: Shape>: View {
    let shape: S
    var body: some View {
        shape.fill(.ultraThinMaterial)
            .overlay(shape.fill(Color.white.opacity(0.45)))
            .overlay(shape.stroke(Color.white.opacity(0.75), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 9, y: 4)
    }
}

// MARK: - 取景画布（边框格子里也用它，interactive=false）

struct CamCanvasView: View {
    let layout: CamLayout
    let size: CGSize
    let photo: UIImage?
    @Binding var stickers: [CamSticker]
    @Binding var selected: UUID?
    var interactive = true
    var hold: ((Bool) -> Void)? = nil

    @State private var bgDragStart: CGPoint?
    @State private var bgPinchBase: CGFloat?
    @State private var pressing = false

    private var k: CGFloat { size.width / max(layout.canvas.width, 1) }

    var body: some View {
        let r = layout.hole
        ZStack(alignment: .topLeading) {
            Color.clear
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
                    .frame(width: r.width * k, height: r.height * k)
                    .clipped()
                    .position(x: r.midX * k, y: r.midY * k)
                    .allowsHitTesting(false)
            }
            if let id = layout.frameId {
                Image(id).resizable().frame(width: size.width, height: size.height).allowsHitTesting(false)
            }
            if interactive {
                if let sel = selected {
                    // 选中时铺一层：取景框里任意处一指拖＝挪、两指捏＝缩放、点一下＝取消（照打码贴纸）
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(backgroundMove(sel))
                        .simultaneousGesture(backgroundPinch(sel))
                        .onTapGesture { selected = nil }
                } else if let hold {
                    // 按住看原图：按满 0.2 秒才切，松手切回（minimumDuration 给很长，免得它自己“认出长按”就提前松开）
                    Color.clear
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 60, maximumDistance: 40, perform: {}, onPressingChanged: { p in
                            pressing = p
                            if p {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { if pressing { hold(true) } }
                            } else {
                                hold(false)
                            }
                        })
                }
            }
            // 不用 ForEach($stickers)：删贴纸时那种写法会拿旧下标越界闪退，按 id 现找
            ForEach(stickers) { s in
                CamStickerView(sticker: binding(s), scale: k, selected: interactive && selected == s.id, interactive: interactive,
                               select: { selected = s.id },
                               remove: { stickers.removeAll { $0.id == s.id }; if selected == s.id { selected = nil } },
                               lift: { lift(s.id) })
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .coordinateSpace(name: "camCanvas")
        .allowsHitTesting(interactive)
    }

    private func binding(_ s: CamSticker) -> Binding<CamSticker> {
        Binding(get: { stickers.first(where: { $0.id == s.id }) ?? s },
                set: { v in if let i = stickers.firstIndex(where: { $0.id == s.id }) { stickers[i] = v } })
    }

    private func lift(_ id: UUID) {
        guard let i = stickers.firstIndex(where: { $0.id == id }), i != stickers.count - 1 else { return }
        let s = stickers.remove(at: i)
        stickers.append(s)
    }

    private func backgroundMove(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("camCanvas"))
            .onChanged { v in
                guard bgPinchBase == nil, let i = stickers.firstIndex(where: { $0.id == id }) else { return }
                if bgDragStart == nil { bgDragStart = stickers[i].center }
                guard let start = bgDragStart else { return }
                stickers[i].center = CGPoint(x: start.x + v.translation.width / k, y: start.y + v.translation.height / k)
            }
            .onEnded { _ in bgDragStart = nil }
    }

    private func backgroundPinch(_ id: UUID) -> some Gesture {
        MagnifyGesture()
            .onChanged { v in
                guard let i = stickers.firstIndex(where: { $0.id == id }) else { return }
                if bgPinchBase == nil {
                    bgPinchBase = stickers[i].width
                    // 两指落下前第一根手指可能已经带着它挪了一点：退回原处
                    if let start = bgDragStart { stickers[i].center = start }
                }
                guard let base = bgPinchBase else { return }
                stickers[i].width = CamStickerView.clampWidth(base * v.magnification)
            }
            .onEnded { _ in bgPinchBase = nil; bgDragStart = nil }
    }
}

struct CamStickerView: View {
    @Binding var sticker: CamSticker
    let scale: CGFloat
    let selected: Bool
    let interactive: Bool
    let select: () -> Void
    let remove: () -> Void
    let lift: () -> Void

    @State private var dragStart: CGPoint?
    @State private var pinchBase: CGFloat?
    @State private var cornerBase: (c: CGPoint, len: CGFloat, ang: Double, w: CGFloat, r: Double)?

    static func clampWidth(_ w: CGFloat) -> CGFloat { min(2400, max(60, w)) }

    var body: some View {
        let w = sticker.width * scale, h = sticker.height * scale
        let center = CGPoint(x: sticker.center.x * scale, y: sticker.center.y * scale)
        Image(uiImage: sticker.image)
            .resizable()
            .interpolation(sticker.pixel ? .none : .high)
            .frame(width: w, height: h)
            .scaleEffect(x: sticker.flipped ? -1 : 1, y: 1)
            .contentShape(Rectangle())
            .onTapGesture { select(); lift() }
            .gesture(moveGesture)
            .simultaneousGesture(pinchGesture)
            .overlay { if selected { handles(w: w, h: h, center: center) } }
            .rotationEffect(.radians(sticker.rotation))
            .position(center)
            .allowsHitTesting(interactive)
    }

    @ViewBuilder private func handles(w: CGFloat, h: CGFloat, center: CGPoint) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.white, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .shadow(color: .black.opacity(0.35), radius: 0.8)
                .padding(-6)
                .allowsHitTesting(false)
            handle(icon: "arrow.left.and.right.righttriangle.left.righttriangle.right", fill: .white, ink: CamInk.ink)
                .position(x: -6, y: -6)
                .onTapGesture { sticker.flipped.toggle() }
            handle(icon: "xmark", fill: .white, ink: CamInk.ink)
                .position(x: w + 6, y: -6)
                .onTapGesture { remove() }
            handle(icon: "arrow.clockwise", fill: CamInk.ink, ink: .white)
                .position(x: w + 6, y: h + 6)
                .gesture(cornerGesture(center: center))
        }
        .frame(width: w, height: h)
    }

    private func handle(icon: String, fill: Color, ink: Color) -> some View {
        Circle().fill(fill)
            .overlay(Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundColor(ink))
            .frame(width: 22, height: 22)
            .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("camCanvas"))
            .onChanged { v in
                guard pinchBase == nil else { return }
                if dragStart == nil { dragStart = sticker.center; select(); lift() }
                guard let start = dragStart else { return }
                sticker.center = CGPoint(x: start.x + v.translation.width / scale, y: start.y + v.translation.height / scale)
            }
            .onEnded { _ in dragStart = nil }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                if pinchBase == nil {
                    pinchBase = sticker.width
                    if let start = dragStart { sticker.center = start }
                    select()
                }
                guard let base = pinchBase else { return }
                sticker.width = Self.clampWidth(base * v.magnification)
            }
            .onEnded { _ in pinchBase = nil; dragStart = nil }
    }

    /// 右下角：拧＝转，往外拉/往里推＝放大缩小（坐标一律用画布空间，跟贴纸自己转了多少无关）
    private func cornerGesture(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("camCanvas"))
            .onChanged { v in
                if cornerBase == nil {
                    let vx = v.startLocation.x - center.x, vy = v.startLocation.y - center.y
                    cornerBase = (center, hypot(vx, vy), atan2(Double(vy), Double(vx)), sticker.width, sticker.rotation)
                }
                guard let b = cornerBase, b.len > 0 else { return }
                let vx = v.location.x - b.c.x, vy = v.location.y - b.c.y
                let len = hypot(vx, vy)
                guard len > 0 else { return }
                sticker.width = Self.clampWidth(b.w * len / b.len)
                sticker.rotation = b.r + (atan2(Double(vy), Double(vx)) - b.ang)
            }
            .onEnded { _ in cornerBase = nil }
    }
}

// MARK: - 拍完：一张静止的照片，还能换滤镜、改调节（边框贴纸定住了）；存下＝进 Alcove 相册＋手机“照片”（实况就存实况），可选发给陈璟

struct CamConfirmView: View {
    let shot: CamShot
    var imported = false
    let retake: () -> Void
    let saved: (UIImage) -> Void

    @State private var params: AlcoveParams
    @State private var image: UIImage
    @State private var editTab = 0
    @State private var adjust: CamAdjust = .brightness
    @State private var thumbs: [String: UIImage] = [:]
    @State private var renderToken = 0
    @State private var sendToHim = false
    @State private var saving = false
    @State private var error: String?

    private static let categoryName = "Alcove 相机"
    private var isLive: Bool { shot.capture.movie != nil }

    init(shot: CamShot, imported: Bool = false, retake: @escaping () -> Void, saved: @escaping (UIImage) -> Void) {
        self.shot = shot
        self.imported = imported
        self.retake = retake
        self.saved = saved
        _params = State(initialValue: shot.capture.params)
        _image = State(initialValue: shot.image)
    }

    var body: some View {
        GeometryReader { geo in
            let safeTop = FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 47
            let safeBottom = FloatingOverlay.appWindow()?.safeAreaInsets.bottom ?? 34
            VStack(spacing: 12) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .overlay(alignment: .topLeading) {
                        if isLive {
                            HStack(spacing: 4) {
                                Image(systemName: "livephoto").font(.system(size: 11, weight: .semibold))
                                Text("实况").font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(CamInk.ink2)
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(CamFrost(shape: Capsule()))
                            .padding(10)
                        }
                    }
                    .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 22)
                editCard
                    .frame(height: 138)
                    .padding(.horizontal, 12)
                Toggle(isOn: $sendToHim) {
                    Text("也发给陈璟").font(.system(size: 14, weight: .semibold)).foregroundColor(CamInk.ink)
                }
                .tint(CamInk.ink)
                .padding(.horizontal, 18)
                .frame(height: 46)
                .background(CamFrost(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 22)
                if let error {
                    Text(error).font(.system(size: 12, weight: .semibold)).foregroundColor(CamInk.dim)
                }
                HStack(spacing: 14) {
                    Button(action: retake) {
                        Text(imported ? "重选" : "重拍").font(.system(size: 15, weight: .semibold)).foregroundColor(CamInk.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(CamFrost(shape: Capsule()))
                    }
                    .buttonStyle(.plain)
                    .disabled(saving)
                    Button { Task { await save() } } label: {
                        ZStack {
                            Capsule().fill(CamInk.ink)
                            if saving { ProgressView().tint(.white) } else {
                                Text("存下").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                    }
                    .buttonStyle(.plain)
                    .disabled(saving)
                }
                .padding(.horizontal, 22)
                .frame(height: 48)
            }
            .padding(.top, safeTop + 10)
            .padding(.bottom, safeBottom + 12)
            .frame(width: geo.size.width, height: geo.size.height)
            .background(CamInk.page)
        }
        .ignoresSafeArea()
        .task {
            // 滤镜格子：就用这张照片做小图，做一次
            let raw = shot.capture.raw
            thumbs = await Task.detached(priority: .utility) { CamFilters.thumbs(from: raw) }.value
        }
        .onChange(of: params) { _, p in rerender(p) }
    }

    /// 滤镜｜调节，跟相机里那两栏一模一样
    private var editCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 18) {
                ForEach(["滤镜", "调节"].indices, id: \.self) { i in
                    Button { editTab = i } label: {
                        Text(i == 0 ? "滤镜" : "调节")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(editTab == i ? CamInk.ink : CamInk.faint)
                            .frame(height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 14)
            Group {
                if editTab == 0 {
                    CamFilterStrip(params: $params, thumbs: thumbs)
                } else {
                    CamAdjustStrip(params: $params, adjust: $adjust).padding(.top, 10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CamFrost(shape: RoundedRectangle(cornerRadius: 24, style: .continuous)))
        .disabled(saving)
    }

    /// 换了滤镜/调节：从原图重算一遍再合进边框贴纸；拖滑杆时只要最后那次的结果
    private func rerender(_ p: AlcoveParams) {
        renderToken += 1
        let token = renderToken
        let shot = self.shot
        Task {
            let img = await Task.detached(priority: .userInitiated) {
                CamCompose.render(photo: CamFilters.render(p, shot.capture.raw), layout: shot.layout, stickers: shot.stickers)
            }.value
            if token == renderToken { image = img }
        }
    }

    private func save() async {
        guard !saving else { return }
        // 滑杆刚松手、最后那次还在算：先等它算完
        let finalImage = CamCompose.render(photo: CamFilters.render(params, shot.capture.raw), layout: shot.layout, stickers: shot.stickers)
        let keepClear = shot.layout.frameId != nil
        guard let data = keepClear ? finalImage.pngData() : finalImage.jpegData(compressionQuality: 0.9) else { return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            let cats = try await AlbumAPI.categories()
            var catId = cats.first(where: { $0.name == Self.categoryName })?.categoryId
            if catId == nil { catId = try await AlbumAPI.category(name: Self.categoryName).categoryId }
            _ = try await AlbumAPI.upload(data: data, caption: "", category: catId, requestId: UUID().uuidString)
        } catch {
            self.error = "没存上：\(error.localizedDescription)"
            return
        }
        var problems: [String] = []
        if sendToHim {
            let name = "AlcoveCam_\(Int(Date().timeIntervalSince1970))" + (keepClear ? ".png" : ".jpg")
            do {
                _ = try await AlcoveAPI.upload(data: data, filename: name, caption: "")
            } catch {
                problems.append("发给陈璟没成功")
            }
        }
        if isLive {
            let shot = self.shot
            let p = params
            let id = UUID().uuidString
            do {
                let movie = try await Task.detached(priority: .userInitiated) {
                    try await CamLive.process(shot: shot, params: p, identifier: id)
                }.value
                guard let still = CamLive.stillData(CamCompose.flattened(finalImage), identifier: id) else { throw CamLive.Failure.writer }
                try await CamLive.saveToPhotos(still: still, movie: movie)
            } catch CamLive.Failure.denied {
                problems.append("实况没存进手机照片（没给相册权限）")
            } catch {
                problems.append("实况没存进手机照片")
            }
            if let m = shot.capture.movie { try? FileManager.default.removeItem(at: m) }
        } else {
            do {
                try await CamLive.saveStillToPhotos(data)
            } catch CamLive.Failure.denied {
                problems.append("没存进手机相册（没给相册权限，去设置里打开）")
            } catch {
                problems.append("没存进手机相册")
            }
        }
        if !problems.isEmpty {
            self.error = "存进 Alcove 相册了；" + problems.joined(separator: "，")
            try? await Task.sleep(nanoseconds: 1_600_000_000)
        }
        saved(finalImage)
    }
}
