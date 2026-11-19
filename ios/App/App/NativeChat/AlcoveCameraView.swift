import SwiftUI
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

// 1120 Alcove 相机（她 1119 #5769「最先做这个」）。排版照她自己出的那张图（camera-1119/ref_her_layout.jpg），
// 再按她后面几句改：蕾丝下面留一条白、取景框整屏宽、滤镜一张卡、「边框 人物 贴纸 装饰」一张卡、底下相册/快门/翻转。
// 底是她给的壁纸原图（CamWall），不染色不拉伸，只整张往下错 32 点，顶上空出来那截用壁纸最上面同色补。
// 成片 1080×1440（3:4）：照片按边框的洞 aspect-fill 塞进去 → 盖边框 → 盖贴纸。取景框里看到的就是成片。
// 贴纸手势照主聊天打码贴纸（StickerMask.swift）：选中后在取景框任意处一指拖＝挪、两指捏＝缩放，点空白取消；
// 框上左上翻转、右上删除、右下拧＝转＋缩放。

// MARK: - 数据

private enum CamInk {
    static func rgb(_ hex: UInt32, _ a: Double = 1) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255, opacity: a)
    }
    static let wallTop = rgb(0xFDE7F3)      // 壁纸最上面那截的颜色，往下错开后补顶
    static let cardBG = rgb(0xFDEFF3)       // 成片底色（边框外圈）
    static let pink = rgb(0xEC6F9E)
    static let pinkSoft = rgb(0xF3A9C7)
    static let text = rgb(0x7D6A72)
    static let textDark = rgb(0x4F4045)
    static let textDim = rgb(0x8A7880)
    static let canvas = CGSize(width: 1080, height: 1440)
    static let cardUI = UIColor(red: 253 / 255, green: 239 / 255, blue: 243 / 255, alpha: 1)
}

struct CamFrameSpec: Identifiable, Equatable {
    let id: String          // 素材名
    let name: String
    let rect: CGRect        // 照片的洞，1080×1440 坐标

    static let all: [CamFrameSpec] = [
        .init(id: "CamFrame01", name: "小白熊", rect: CGRect(x: 202, y: 310, width: 677, height: 677)),
        .init(id: "CamFrame02", name: "大耳狗", rect: CGRect(x: 230, y: 410, width: 619, height: 619)),
        .init(id: "CamFrame03", name: "粉碗", rect: CGRect(x: 79, y: 79, width: 922, height: 900)),
        .init(id: "CamFrame04", name: "蝴蝶结蕾丝", rect: CGRect(x: 143, y: 201, width: 792, height: 1040)),
        .init(id: "CamFrame05", name: "饼干", rect: CGRect(x: 226, y: 539, width: 606, height: 357)),
        .init(id: "CamFrame06", name: "粉星星", rect: CGRect(x: 128, y: 434, width: 817, height: 573)),
        .init(id: "CamFrame07", name: "巧克力星星", rect: CGRect(x: 128, y: 434, width: 817, height: 574)),
        .init(id: "CamFrame08", name: "奶油巧克力", rect: CGRect(x: 78, y: 470, width: 936, height: 567)),
        .init(id: "CamFrame09", name: "粉波点", rect: CGRect(x: 118, y: 392, width: 841, height: 565)),
        .init(id: "CamFrame10", name: "奶油熊", rect: CGRect(x: 169, y: 150, width: 739, height: 921)),
        .init(id: "CamFrame11", name: "粉色机身", rect: CGRect(x: 109, y: 268, width: 694, height: 908)),
        .init(id: "CamFrame12", name: "老手机", rect: CGRect(x: 204, y: 261, width: 690, height: 653)),
        .init(id: "CamFrame13", name: "相机界面", rect: CGRect(x: 0, y: 0, width: 1080, height: 1440)),
        .init(id: "CamFrame14", name: "Hello Kitty 碟", rect: CGRect(x: 54, y: 421, width: 504, height: 489)),
        .init(id: "CamFrame15", name: "情歌碟", rect: CGRect(x: 58, y: 421, width: 502, height: 489)),
    ]
}

/// 贴纸栏里的一项：素材名 + 默认宽（成片像素）+ 是不是像素画（放大不糊）
struct CamPiece: Identifiable {
    let id: String
    let width: CGFloat
    let pixel: Bool
    var image: UIImage? { UIImage(named: id) }

    static let people: [CamPiece] = [
        .init(id: "CamUsHim", width: 300, pixel: true),
        .init(id: "CamUsHer", width: 300, pixel: true),
    ]
    static let stickers: [CamPiece] = [
        .init(id: "CamClawdChop", width: 380, pixel: true),
        .init(id: "CamClawdRamen", width: 300, pixel: true),
        .init(id: "CamClawdBurger", width: 280, pixel: true),
        .init(id: "CamClawdCake", width: 280, pixel: true),
        .init(id: "CamClawdPudding", width: 260, pixel: true),
        .init(id: "CamClawdToast", width: 280, pixel: true),
        .init(id: "CamClawdOnigiri", width: 260, pixel: true),
        .init(id: "CamClawdIcecream", width: 260, pixel: true),
    ]
    static let decos: [CamPiece] = [
        .init(id: "CamDecoBow", width: 320, pixel: false),
        .init(id: "CamDecoWing", width: 360, pixel: false),
        .init(id: "CamDecoHearts", width: 300, pixel: false),
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

enum CamFilter: String, CaseIterable, Identifiable {
    case orig = "原图", retro = "复古", film = "胶片", instant = "拍立得", soft = "软萌", mono = "黑白"
    var id: String { rawValue }

    func apply(_ input: CIImage) -> CIImage {
        let extent = input.extent
        switch self {
        case .orig:
            return input
        case .retro:   // 暖、褪一点色、四角压暗
            let sepia = CIFilter.sepiaTone(); sepia.inputImage = input; sepia.intensity = 0.22
            let cc = CIFilter.colorControls(); cc.inputImage = sepia.outputImage; cc.saturation = 0.88; cc.brightness = 0.02; cc.contrast = 1.0
            let vig = CIFilter.vignette(); vig.inputImage = cc.outputImage; vig.intensity = 0.7; vig.radius = 1.4
            return (vig.outputImage ?? input).cropped(to: extent)
        case .film:    // 轻偏青＋颗粒
            let m = CIFilter.colorMatrix(); m.inputImage = input
            m.rVector = CIVector(x: 0.96, y: 0, z: 0, w: 0)
            m.gVector = CIVector(x: 0, y: 1.0, z: 0, w: 0)
            m.bVector = CIVector(x: 0, y: 0, z: 1.04, w: 0)
            m.biasVector = CIVector(x: 0, y: 0.015, z: 0.03, w: 0)
            let base = m.outputImage ?? input
            guard let noise = CIFilter.randomGenerator().outputImage?.cropped(to: extent) else { return base }
            let g = CIFilter.colorMatrix(); g.inputImage = noise
            g.rVector = CIVector(x: 0.16, y: 0, z: 0, w: 0)
            g.gVector = CIVector(x: 0.16, y: 0, z: 0, w: 0)
            g.bVector = CIVector(x: 0.16, y: 0, z: 0, w: 0)
            g.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            g.biasVector = CIVector(x: 0.42, y: 0.42, z: 0.42, w: 0)
            let blend = CIFilter.softLightBlendMode(); blend.inputImage = g.outputImage; blend.backgroundImage = base
            return (blend.outputImage ?? base).cropped(to: extent)
        case .instant: // 拍立得：提亮、压对比
            let fx = CIFilter.photoEffectInstant(); fx.inputImage = input
            let cc = CIFilter.colorControls(); cc.inputImage = fx.outputImage; cc.brightness = 0.04; cc.contrast = 0.92; cc.saturation = 1
            return (cc.outputImage ?? input).cropped(to: extent)
        case .soft:    // 软萌：亮一点粉一点（照 camera-1119/photo_soft.jpg 量出来的那组）
            let m = CIFilter.colorMatrix(); m.inputImage = input
            m.rVector = CIVector(x: 1.02, y: 0, z: 0, w: 0)
            m.gVector = CIVector(x: 0, y: 1.03, z: 0, w: 0)
            m.bVector = CIVector(x: 0, y: 0, z: 1.02, w: 0)
            m.biasVector = CIVector(x: 0.08, y: 0.02, z: 0.049, w: 0)
            let cc = CIFilter.colorControls(); cc.inputImage = m.outputImage; cc.saturation = 0.95; cc.brightness = 0; cc.contrast = 1
            return (cc.outputImage ?? input).cropped(to: extent)
        case .mono:
            let fx = CIFilter.photoEffectMono(); fx.inputImage = input
            return (fx.outputImage ?? input).cropped(to: extent)
        }
    }
}

// MARK: - 相机

/// 取景画面单独一个对象：一秒三十帧只让取景框和边框格子重画，整页不跟着重算
final class CamFeed: ObservableObject {
    @Published var preview: UIImage?
    @Published var thumb: UIImage?          // 边框格子里用，半秒换一次，省电
}

final class CamEngine: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    let feed = CamFeed()
    @Published var denied = false
    @Published var busy = false

    let session = AVCaptureSession()
    private let videoOut = AVCaptureVideoDataOutput()
    private let photoOut = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "alcove.camera")
    private let ctx = CIContext(options: [.cacheIntermediates: false])
    private var input: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back
    private var rendering = false
    private var lastThumb = Date.distantPast
    private var shotDone: ((UIImage?) -> Void)?

    private let lock = NSLock()
    private var _filter: CamFilter = .soft
    var filter: CamFilter {
        get { lock.lock(); defer { lock.unlock() }; return _filter }
        set { lock.lock(); _filter = newValue; lock.unlock() }
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
                self.orientConnections()
                self.session.commitConfiguration()
            }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    private func attach(_ pos: AVCaptureDevice.Position) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: pos),
              let newInput = try? AVCaptureDeviceInput(device: device) else { return }
        if let old = input { session.removeInput(old) }
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            input = newInput
            position = pos
        } else if let old = input {
            session.addInput(old)
        }
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
            self.orientConnections()
            self.session.commitConfiguration()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !rendering, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        rendering = true
        defer { rendering = false }
        var img = CIImage(cvPixelBuffer: pb)
        let s = min(1, 900 / max(img.extent.width, 1))
        img = img.transformed(by: CGAffineTransform(scaleX: s, y: s))
        img = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
        let out = filter.apply(img)
        guard let cg = ctx.createCGImage(out, from: out.extent) else { return }
        let ui = UIImage(cgImage: cg)
        let now = Date()
        let refreshThumb = now.timeIntervalSince(lastThumb) > 0.5
        if refreshThumb { lastThumb = now }
        let feed = self.feed
        DispatchQueue.main.async {
            feed.preview = ui
            if refreshThumb { feed.thumb = ui }
        }
    }

    func shoot(_ done: @escaping (UIImage?) -> Void) {
        guard !busy else { return }
        busy = true
        shotDone = done
        queue.async {
            let settings = AVCapturePhotoSettings()
            self.photoOut.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        var result: UIImage?
        if let data = photo.fileDataRepresentation(), let raw = UIImage(data: data) {
            // 先按方向摆正，再上滤镜（跟取景框同一套）
            let upright = UIGraphicsImageRenderer(size: raw.size, format: {
                let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f
            }()).image { _ in raw.draw(in: CGRect(origin: .zero, size: raw.size)) }
            if let ci = CIImage(image: upright) {
                let out = filter.apply(ci)
                if let cg = ctx.createCGImage(out, from: out.extent) { result = UIImage(cgImage: cg) }
            }
        }
        let done = shotDone
        shotDone = nil
        DispatchQueue.main.async {
            self.busy = false
            done?(result)
        }
    }
}

// MARK: - 合成成片

enum CamCompose {
    static func render(photo: UIImage, frame: CamFrameSpec, stickers: [CamSticker]) -> UIImage {
        let size = CamInk.canvas
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: size, format: fmt).image { rc in
            let cg = rc.cgContext
            CamInk.cardUI.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            // 照片：铺满边框的洞
            let r = frame.rect
            let k = max(r.width / photo.size.width, r.height / photo.size.height)
            let pw = photo.size.width * k, ph = photo.size.height * k
            cg.saveGState()
            cg.clip(to: r)
            photo.draw(in: CGRect(x: r.midX - pw / 2, y: r.midY - ph / 2, width: pw, height: ph))
            cg.restoreGState()
            UIImage(named: frame.id)?.draw(in: CGRect(origin: .zero, size: size))
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

    /// 自己抠图：iOS 自带的抠主体
    static func liftSubject(_ image: UIImage) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let upright = UIGraphicsImageRenderer(size: image.size).image { _ in image.draw(at: .zero) }
            guard let cg = upright.cgImage else { return nil }
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            let request = VNGenerateForegroundInstanceMaskRequest()
            do {
                try handler.perform([request])
                guard let obs = request.results?.first else { return nil }
                let buffer = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: true)
                let ci = CIImage(cvPixelBuffer: buffer)
                guard let out = CIContext().createCGImage(ci, from: ci.extent) else { return nil }
                return UIImage(cgImage: out)
            } catch {
                return nil
            }
        }.value
    }
}

// MARK: - 页面

struct AlcoveCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = CamEngine()
    @State private var filter: CamFilter = .soft
    @State private var tab = 0
    @State private var frame = CamFrameSpec.all[0]
    @State private var stickers: [CamSticker] = []
    @State private var selected: UUID?
    @State private var cutouts: [UIImage] = []
    @State private var pickingCutout = false
    @State private var lifting = false
    @State private var shot: UIImage?
    @State private var lastSaved: UIImage?
    @State private var showAlbum = false
    @State private var toast: String?

    private let tabs = ["边框", "人物", "贴纸", "装饰"]
    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 47 }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            // 位置照 844 高那张图：快门中心离底 59，标签卡顶离底 244，滤镜卡顶离底 299；取景框从安全区下面 53 开始
            let dockY = H - 59
            let tabTop = H - 244
            let filterTop = H - 299
            let vfTop = safeTop + 53
            let vfH = max(200, filterTop - 3 - vfTop)
            ZStack(alignment: .topLeading) {
                wallpaper(W: W)
                viewfinder(width: W, height: vfH)
                    .position(x: W / 2, y: vfTop + vfH / 2)
                filterCard
                    .frame(width: W - 18, height: 53)
                    .position(x: W / 2, y: filterTop + 26.5)
                tabCard
                    .frame(width: W - 18, height: 137)
                    .position(x: W / 2, y: tabTop + 68.5)
                dock(W: W)
                    .position(x: W / 2, y: dockY)
                if let shot {
                    CamConfirmView(image: shot, retake: { self.shot = nil }, saved: { img in
                        lastSaved = img
                        self.shot = nil
                    })
                    .transition(.opacity)
                }
                if let toast {
                    Text(toast)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Capsule().fill(CamInk.textDark.opacity(0.82)))
                        .position(x: W / 2, y: vfTop + vfH - 30)
                }
            }
            .frame(width: W, height: H)
        }
        .ignoresSafeArea()
        .onAppear { engine.filter = filter; engine.start() }
        .onDisappear { engine.stop() }
        .onChange(of: filter) { _, f in engine.filter = f }
        .sheet(isPresented: $pickingCutout) {
            PhotoLibraryPicker(maxCount: 1) { images in
                guard let img = images.first else { return }
                lifting = true
                Task {
                    let cut = await CamCompose.liftSubject(img)
                    lifting = false
                    if let cut {
                        cutouts.insert(cut, at: 0)
                        add(image: cut, width: 460, pixel: false)
                    } else {
                        flash("这张没找到能抠的主体")
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showAlbum) { NativeAlbumView() }
        .animation(.easeOut(duration: 0.18), value: shot != nil)
    }

    // MARK: 底

    private func wallpaper(W: CGFloat) -> some View {
        let img = UIImage(named: "CamWall")
        let h = W * (img.map { $0.size.height / max($0.size.width, 1) } ?? 2.17)
        let drop = 32 * W / 390
        return ZStack(alignment: .top) {
            CamInk.wallTop
            if let img {
                Image(uiImage: img).resizable().frame(width: W, height: h).offset(y: drop)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    // MARK: 取景框

    private func viewfinder(width: CGFloat, height: CGFloat) -> some View {
        // 成片 3:4 整张放进去（看到的就是拍出来的），两边多出来的用成片底色补
        let cw = min(width, height * 3 / 4)
        let ch = cw * 4 / 3
        return ZStack(alignment: .topLeading) {
            CamInk.cardBG
            CamLiveCanvas(feed: engine.feed, size: CGSize(width: cw, height: ch), frame: frame,
                          stickers: $stickers, selected: $selected)
                .frame(width: cw, height: ch)
                .position(x: width / 2, y: height / 2)
            if engine.denied {
                VStack(spacing: 10) {
                    Text("相机没开权限").font(.system(size: 15, weight: .semibold)).foregroundColor(CamInk.textDark)
                    Button("去设置里打开") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .font(.system(size: 13)).foregroundColor(CamInk.pink)
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.9)))
                .position(x: width / 2, y: height / 2)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundColor(CamInk.textDark)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.white).shadow(color: CamInk.rgb(0xC87896, 0.25), radius: 3, y: 2))
            }
            .buttonStyle(.plain)
            .position(x: 12 + 17, y: 12 + 17)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: 卡片

    private var filterCard: some View {
        HStack(spacing: 0) {
            ForEach(CamFilter.allCases) { f in
                Button { filter = f } label: {
                    VStack(spacing: 1) {
                        Text(f.rawValue)
                            .font(.system(size: 13.5, weight: filter == f ? .bold : .regular))
                            .foregroundColor(filter == f ? CamInk.pink : CamInk.text)
                        Text("♥").font(.system(size: 9)).foregroundColor(CamInk.pink).opacity(filter == f ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .background(CamCardBackground())
    }

    private var tabCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 2) {
                ForEach(tabs.indices, id: \.self) { i in
                    Button { tab = i } label: {
                        Text(tabs[i])
                            .font(.system(size: 13.5, weight: tab == i ? .semibold : .regular))
                            .foregroundColor(tab == i ? .white : (i == 1 ? CamInk.textDark : CamInk.textDim))
                            .frame(width: 59, height: 33)
                            .background {
                                if tab == i {
                                    Capsule().fill(LinearGradient(colors: [CamInk.rgb(0xF6B3CD), CamInk.rgb(0xEE9CBD)], startPoint: .top, endPoint: .bottom))
                                        .overlay(Capsule().stroke(.white.opacity(0.55), lineWidth: 1).blur(radius: 0.5).offset(y: 1).mask(Capsule()))
                                        .shadow(color: CamInk.pink.opacity(0.25), radius: 2.5, y: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 9)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) { tiles }
                    .padding(.horizontal, 3)
                    .padding(.vertical, 3)
            }
        }
        .padding(.horizontal, 9)
        .padding(.top, 9)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(CamCardBackground())
    }

    @ViewBuilder private var tiles: some View {
        switch tab {
        case 0:
            ForEach(CamFrameSpec.all) { f in
                tile(on: frame == f) {
                    CamFrameThumb(feed: engine.feed, frame: f)
                } action: { frame = f }
            }
        case 1:
            ForEach(CamPiece.people) { p in pieceTile(p) }
            ForEach(cutouts.indices, id: \.self) { i in
                tile(on: false) {
                    Image(uiImage: cutouts[i]).resizable().scaledToFit().padding(6)
                } action: { add(image: cutouts[i], width: 460, pixel: false) }
            }
            tile(on: false) {
                VStack(spacing: 4) {
                    if lifting { ProgressView().tint(CamInk.pink) } else {
                        Image(systemName: "plus").font(.system(size: 18, weight: .medium)).foregroundColor(CamInk.pink)
                    }
                    Text("抠图").font(.system(size: 10)).foregroundColor(CamInk.textDim)
                }
            } action: { if !lifting { pickingCutout = true } }
        case 2:
            ForEach(CamPiece.stickers) { p in pieceTile(p) }
        default:
            ForEach(CamPiece.decos) { p in pieceTile(p) }
        }
    }

    private func pieceTile(_ p: CamPiece) -> some View {
        tile(on: false) {
            if let img = p.image {
                Image(uiImage: img).resizable().interpolation(p.pixel ? .none : .high).scaledToFit().padding(8)
            }
        } action: {
            if let img = p.image { add(image: img, width: p.width, pixel: p.pixel) }
        }
    }

    private func tile<C: View>(on: Bool, @ViewBuilder _ content: () -> C, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            content()
                .frame(width: 66, height: 72)
                .background(LinearGradient(colors: [CamInk.rgb(0xFFF4F9), CamInk.rgb(0xFBE3EE)], startPoint: .top, endPoint: .bottom))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(on ? CamInk.pinkSoft : .white.opacity(0.9), lineWidth: on ? 2.5 : 1))
                .shadow(color: CamInk.rgb(0xDC8CAF, 0.18), radius: 1.5, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: 底下三颗

    private func dock(W: CGFloat    private func dock(W: CGFloat) -> some View {
        // 照图：相册 57 方、快门 78、翻转 57，中间各空 45 / 47，整排居中
        HStack(spacing: 0) {
            Button { showAlbum = true } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(LinearGradient(colors: [.white, CamInk.rgb(0xFBE9F1)], startPoint: .top, endPoint: .bottom))
                        .shadow(color: CamInk.rgb(0xDC8CAF, 0.25), radius: 4, y: 3)
                    if let lastSaved {
                        Image(uiImage: lastSaved).resizable().scaledToFill()
                            .frame(width: 45, height: 45).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Image(systemName: "photo.on.rectangle").font(.system(size: 18)).foregroundColor(CamInk.pinkSoft)
                    }
                }
                .frame(width: 57, height: 57)
            }
            .buttonStyle(.plain)
            Color.clear.frame(width: 45, height: 1)
            Button { shoot() } label: {
                ZStack {
                    Circle().fill(LinearGradient(colors: [.white, CamInk.rgb(0xFBE6EF)], startPoint: .top, endPoint: .bottom))
                        .shadow(color: CamInk.rgb(0xE682AA, 0.32), radius: 6, y: 4)
                    Circle().fill(RadialGradient(colors: [CamInk.rgb(0xF8C9DC), CamInk.rgb(0xEC9FC0)], center: UnitPoint(x: 0.5, y: 0.28), startRadius: 2, endRadius: 40))
                        .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1.5).blur(radius: 1).offset(y: 1.5).mask(Circle()))
                        .frame(width: 62, height: 62)
                    if engine.busy {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "heart.fill").font(.system(size: 24)).foregroundColor(.white)
                    }
                }
                .frame(width: 78, height: 78)
            }
            .buttonStyle(.plain)
            .disabled(engine.busy || engine.denied)
            Color.clear.frame(width: 47, height: 1)
            Button { engine.flip() } label: {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 22, weight: .medium)).foregroundColor(CamInk.pink)
                    .frame(width: 57, height: 57)
                    .background(Circle().fill(LinearGradient(colors: [.white, CamInk.rgb(0xFBE9F1)], startPoint: .top, endPoint: .bottom))
                        .shadow(color: CamInk.rgb(0xDC8CAF, 0.25), radius: 4, y: 3))
            }
            .buttonStyle(.plain)
        }
        .frame(width: W, height: 80)
    }

c add(image: UIImage, width: CGFloat, pixel: Bool) {
        let c = CamInk.canvas
        // 一个叠一个往右下错一点，别全压在正中
        let n = CGFloat(stickers.count % 5)
        let s = CamSticker(image: image, pixel: pixel,
                           center: CGPoint(x: c.width / 2 + n * 40, y: c.height * 0.62 + n * 40), width: width)
        stickers.append(s)
        selected = s.id
    }

    private func shoot() {
        let keepFrame = frame
        let keepStickers = stickers
        engine.shoot { photo in
            guard let photo else { flash("没拍上，再按一次"); return }
            selected = nil
            shot = CamCompose.render(photo: photo, frame: keepFrame, stickers: keepStickers)
        }
    }

    private func flash(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if toast == text { toast = nil } }
    }
}

private struct CamLiveCanvas: View {
    @ObservedObject var feed: CamFeed
    let size: CGSize
    let frame: CamFrameSpec
    @Binding var stickers: [CamSticker]
    @Binding var selected: UUID?
    var body: some View {
        CamCanvasView(size: size, frame: frame, photo: feed.preview, stickers: $stickers, selected: $selected)
    }
}

private struct CamFrameThumb: View {
    @ObservedObject var feed: CamFeed
    let frame: CamFrameSpec
    var body: some View {
        CamCanvasView(size: CGSize(width: 54, height: 72), frame: frame, photo: feed.thumb,
                      stickers: .constant([]), selected: .constant(nil), interactive: false)
            .frame(width: 54, height: 72)
    }
}

/// 奶白卡：上面一道高光、底下软粉阴影
private struct CamCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: [CamInk.rgb(0xFFFBFD), CamInk.rgb(0xFDF1F7)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white, lineWidth: 1.5).blur(radius: 0.6).offset(y: 1)
                .mask(RoundedRectangle(cornerRadius: 24, style: .continuous)))
            .shadow(color: CamInk.rgb(0xE696B9, 0.20), radius: 7, y: 4)
    }
}

// MARK: - 取景画布（边框格子里也用它，interactive=false）

struct CamCanvasView: View {
    let size: CGSize
    let frame: CamFrameSpec
    let photo: UIImage?
    @Binding var stickers: [CamSticker]
    @Binding var selected: UUID?
    var interactive = true

    @State private var bgDragStart: CGPoint?
    @State private var bgPinchBase: CGFloat?

    private var k: CGFloat { size.width / CamInk.canvas.width }

    var body: some View {
        let r = frame.rect
        ZStack(alignment: .topLeading) {
            CamInk.cardBG
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
                    .frame(width: r.width * k, height: r.height * k)
                    .clipped()
                    .position(x: r.midX * k, y: r.midY * k)
            }
            Image(frame.id).resizable().frame(width: size.width, height: size.height)
            if interactive, let sel = selected {
                // 选中时铺一层：取景框里任意处一指拖＝挪、两指捏＝缩放、点一下＝取消（照打码贴纸）
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(backgroundMove(sel))
                    .simultaneousGesture(backgroundPinch(sel))
                    .onTapGesture { selected = nil }
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
                .shadow(color: CamInk.pink.opacity(0.7), radius: 0.8)
                .padding(-6)
                .allowsHitTesting(false)
            handle(icon: "arrow.left.and.right.righttriangle.left.righttriangle.right", fill: .white, ink: CamInk.pink)
                .position(x: -6, y: -6)
                .onTapGesture { sticker.flipped.toggle() }
            handle(icon: "xmark", fill: .white, ink: CamInk.pink)
                .position(x: w + 6, y: -6)
                .onTapGesture { remove() }
            handle(icon: "arrow.clockwise", fill: CamInk.rgb(0xF08FB0), ink: .white)
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

// MARK: - 拍完：存下 / 重拍，可选发给陈璟

struct CamConfirmView: View {
    let image: UIImage
    let retake: () -> Void
    let saved: (UIImage) -> Void

    @State private var sendToHim = false
    @State private var saving = false
    @State private var error: String?

    private static let categoryName = "Alcove 相机"

    var body: some View {
        GeometryReader { geo in
            let safeTop = FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 47
            let safeBottom = FloatingOverlay.appWindow()?.safeAreaInsets.bottom ?? 34
            VStack(spacing: 14) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: CamInk.rgb(0xE696B9, 0.25), radius: 10, y: 5)
                    .frame(maxHeight: geo.size.height - safeTop - safeBottom - 190)
                    .padding(.horizontal, 22)
                Toggle(isOn: $sendToHim) {
                    Text("也发给陈璟").font(.system(size: 14)).foregroundColor(CamInk.textDark)
                }
                .tint(CamInk.pinkSoft)
                .padding(.horizontal, 18)
                .frame(height: 50)
                .background(CamCardBackground())
                .padding(.horizontal, 22)
                if let error {
                    Text(error).font(.system(size: 12)).foregroundColor(CamInk.pink)
                }
                HStack(spacing: 14) {
                    Button(action: retake) {
                        Text("重拍").font(.system(size: 15, weight: .medium)).foregroundColor(CamInk.text)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(CamCardBackground())
                    }
                    .buttonStyle(.plain)
                    .disabled(saving)
                    Button { Task { await save() } } label: {
                        ZStack {
                            Capsule().fill(LinearGradient(colors: [CamInk.rgb(0xF6B3CD), CamInk.rgb(0xEE9CBD)], startPoint: .top, endPoint: .bottom))
                                .shadow(color: CamInk.pink.opacity(0.3), radius: 4, y: 3)
                            if saving { ProgressView().tint(.white) } else {
                                Text("存下").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .disabled(saving)
                }
                .padding(.horizontal, 22)
            }
            .padding(.top, safeTop + 16)
            .padding(.bottom, safeBottom + 16)
            .frame(width: geo.size.width, height: geo.size.height)
            .background(CamInk.wallTop.opacity(0.97))
        }
        .ignoresSafeArea()
    }

    private func save() async {
        guard !saving, let data = image.jpegData(compressionQuality: 0.9) else { return }
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
        if sendToHim {
            let name = "AlcoveCam_\(Int(Date().timeIntervalSince1970)).jpg"
            do {
                _ = try await AlcoveAPI.upload(data: data, filename: name, caption: "")
            } catch {
                self.error = "存进相册了，发给陈璟没成功"
                saved(image)
                return
            }
        }
        saved(image)
    }
}
