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

    static func fileName(for themeName: String) -> String {
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


    var chatWallpaperViewportInset: CGSize {
        get { self[ChatWallpaperViewportInsetKey.self] }
        set { self[ChatWallpaperViewportInsetKey.self] = newValue }
    }
}
