import SwiftUI
import UIKit

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
        default: return "chatwall_haven.jpg"
        }
    }

    func refresh(themeName: String, theme: AlcoveTheme, wallStamp: Double) {
        let fileName = Self.fileName(for: themeName)
        let key = "\(themeName)|\(wallStamp)|\(fileName)|\(KakaoPackStore.shared.selectedID)|\(KakaoPackStore.shared.stamp)"
        guard key != loadedKey else { return }
        loadedKey = key

        let url = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent(fileName)

        if let image = UIImage(contentsOfFile: url.path) {
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
                descriptor = ChatWallpaperDescriptor(source: .image(wall))
            } else {
                let c = KakaoPackStore.shared.wallColor ?? Color(red: 0xB2/255, green: 0xC7/255, blue: 0xD9/255)
                descriptor = ChatWallpaperDescriptor(source: .gradient([c, c]))
            }
        } else if theme.usesWallImage {
            descriptor = ChatWallpaperDescriptor(source: .asset("ChatWall"))
        } else {
            descriptor = ChatWallpaperDescriptor(
                source: .gradient(theme.wallGradient)
            )
        }
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

/// Repaints the exact chat wallpaper behind this bubble, then bends that copy
/// with a rounded-rectangle Metal lens. Text remains outside the shader.
struct BubbleGlassBackground: View {
    let tintColor: Color
    var tintOpacity: CGFloat
    var style: BubbleGlassStyle = .reference
    var cornerRadius: CGFloat = 18

    @Environment(\.chatWallpaperDescriptor) private var wallpaper
    @Environment(\.chatWallpaperViewportSize) private var viewportSize
    @Environment(\.chatWallpaperViewportInset) private var viewportInset
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let frame = proxy.frame(in: .named("alcoveChatRoot"))
            let radius = min(cornerRadius, min(size.width, size.height) / 2)
            let shape = RoundedRectangle(
                cornerRadius: radius,
                style: .continuous
            )

            ZStack {
                if reduceTransparency {
                    shape.fill(tintColor.opacity(0.88))
                } else {
                    refractedWallpaper(size: size, frame: frame, radius: radius)
                        .clipShape(shape)

                    shape.fill(tintColor.opacity(tintOpacity))
                }

                // A continuous wet-glass rim: the horizontal arcs catch
                // more light, while the side edges stay present but quieter.
                shape.stroke(
                    Color.white.opacity(0.10),
                    lineWidth: 0.45
                )

                shape.stroke(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.40), location: 0.00),
                            .init(color: .white.opacity(0.12), location: 0.32),
                            .init(color: .white.opacity(0.10), location: 0.68),
                            .init(color: .white.opacity(0.32), location: 1.00)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.95
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func refractedWallpaper(
        size: CGSize,
        frame: CGRect,
        radius: CGFloat
    ) -> some View {
        let rootSize = CGSize(
            width: max(viewportSize.width, size.width),
            height: max(viewportSize.height, size.height)
        )
        let effectiveStrength = style.strength(for: size)

        return ChatWallpaperRenderer(descriptor: wallpaper)
            .frame(width: rootSize.width, height: rootSize.height)
            .offset(x: -(frame.minX + viewportInset.width),
                    y: -(frame.minY + viewportInset.height))
            .saturation(1.08)
            .blur(radius: style.backdropBlur)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .layerEffect(
                ShaderLibrary.default.roundedRectGlassLens(
                    .float2(size),
                    .float(Float(radius)),
                    .float(Float(effectiveStrength)),
                    .float(Float(style.dispersion)),
                    .float(Float(style.magnify)),
                    .float(Float(style.rimWidth))
                ),
                maxSampleOffset: style.maximumSampleOffset(for: size)
            )
    }
}
