//
//  AlcoveFilterEngine.swift
//  Alcove camera filters for iOS (Core Image only, no custom kernels).
//
//  Same pipeline, order and maths as web/alcove-filters.js (see README):
//    1. LUT (16^3 .cube) mixed by intensity -> brightness (gamma) -> saturation
//       -> temperature -> clamp
//    2. soft blur: gaussian blur blended back
//    3. grain: monochrome uniform noise per grain cell
//
//  All steps run on Display P3 *encoded* values, which is how the reference
//  app applies its filters to iPhone photos.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import MetalKit

// MARK: - Parameters (same names and ranges as filters.json and the web page)

struct AlcoveParams: Codable, Equatable {
    var filter: String? = nil       // nil = 原图 (no filter)
    var intensity: Double = 100     // 0...100
    var brightness: Double = 0      // -100...100
    var softBlur: Double = 0        // 0...100
    var grain: Double = 0           // 0...100
    var saturation: Double = 0      // -100...100
    var temperature: Double = 0     // -100...100
    var seed: UInt32 = 7
}

struct AlcoveFilterInfo: Codable, Identifiable {
    let id: String
    let name: String
    let lut: String
}

private struct AlcoveManifest: Codable {
    let lutSize: Int
    let defaultIntensity: Double
    let filters: [AlcoveFilterInfo]
}

// MARK: - Engine

final class AlcoveFilterEngine {

    /// Tunable constants. Keep in sync with `K` in web/alcove-filters.js.
    enum K {
        static let brightnessGamma = 0.7    // power = exp(-0.7 * b)
        static let temperatureGain = 0.10   // R *= 1 + 0.1t, B *= 1 - 0.1t
        static let softSigma = 0.015        // blur sigma = 1.5% of short side
        static let softMix = 0.7
        static let grainAmount = 0.16
        static let grainCellDiv = 1500.0    // grain cell = max(1px, long side / 1500)
    }

    let filters: [AlcoveFilterInfo]
    let context: CIContext
    private var cubes: [String: (data: Data, size: Int)] = [:]
    private let p3 = CGColorSpace(name: CGColorSpace.displayP3)!

    /// `folder` is the bundled `filters` folder (filters.json + luts/*.cube).
    /// Add it to the app target as a folder reference, then:
    ///   let url = Bundle.main.url(forResource: "filters", withExtension: nil)!
    init(folder: URL, context: CIContext = CIContext()) throws {
        let manifestData = try Data(contentsOf: folder.appendingPathComponent("filters.json"))
        let manifest = try JSONDecoder().decode(AlcoveManifest.self, from: manifestData)
        filters = manifest.filters
        self.context = context
        for f in manifest.filters {
            let text = try String(contentsOf: folder.appendingPathComponent(f.lut), encoding: .utf8)
            cubes[f.id] = try Self.parseCube(text)
        }
    }

    /// .cube text -> Float32 RGBA data in Core Image's colour-cube order
    /// (red fastest, then green, then blue: the same order as .cube files).
    static func parseCube(_ text: String) throws -> (data: Data, size: Int) {
        var size = 0
        var values: [Float] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let first = line.first, first != "#" else { continue }
            if line.hasPrefix("LUT_3D_SIZE") {
                size = Int(line.split(separator: " ").last ?? "") ?? 0
                continue
            }
            if first.isLetter { continue }                     // TITLE, DOMAIN_MIN, ...
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).compactMap { Float($0) }
            guard parts.count == 3 else { continue }
            values.append(contentsOf: [parts[0], parts[1], parts[2], 1])
        }
        guard size > 1, values.count == size * size * size * 4 else {
            throw NSError(domain: "AlcoveFilters", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Bad .cube file"])
        }
        return (values.withUnsafeBufferPointer { Data(buffer: $0) }, size)
    }

    /// Apply the whole pipeline. Works for live camera frames and full photos.
    func apply(_ p: AlcoveParams, to input: CIImage) -> CIImage {
        let extent = input.extent
        guard var img = input.matchedFromWorkingSpace(to: p3) else { return input }

        // 1. colour
        if let id = p.filter, let cube = cubes[id] {
            let f = CIFilter.colorCube()
            f.inputImage = img
            f.cubeDimension = Float(cube.size)
            f.cubeData = cube.data
            if let out = f.outputImage {
                img = p.intensity >= 100 ? out : Self.mix(img, out, p.intensity / 100)
            }
        }
        if p.brightness != 0 {
            let f = CIFilter.gammaAdjust()
            f.inputImage = img
            f.power = Float(exp(-K.brightnessGamma * p.brightness / 100))
            img = f.outputImage ?? img
        }
        if p.saturation != 0 || p.temperature != 0 {
            // out = L + (c - L) * s, then R/B gains for temperature
            let s = 1 + p.saturation / 100
            let t = p.temperature / 100
            let w = [0.2126, 0.7152, 0.0722]
            func row(_ i: Int, gain: Double) -> CIVector {
                var r = w.map { (1 - s) * $0 }
                r[i] += s
                return CIVector(x: CGFloat(r[0] * gain), y: CGFloat(r[1] * gain), z: CGFloat(r[2] * gain), w: 0)
            }
            let f = CIFilter.colorMatrix()
            f.inputImage = img
            f.rVector = row(0, gain: 1 + K.temperatureGain * t)
            f.gVector = row(1, gain: 1)
            f.bVector = row(2, gain: 1 - K.temperatureGain * t)
            f.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            f.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
            img = f.outputImage ?? img
        }
        img = Self.clamp(img)

        // 2. soft blur: mix(a, mix(blur, max(a, blur), 0.5), 0.7 * k)
        if p.softBlur > 0 {
            let sigma = K.softSigma * Double(min(extent.width, extent.height))
            let blurred = img.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: extent)
            let lighten = CIFilter.lightenBlendMode()
            lighten.inputImage = img
            lighten.backgroundImage = blurred
            let hazy = Self.mix(blurred, lighten.outputImage ?? blurred, 0.5)
            img = Self.mix(img, hazy, K.softMix * p.softBlur / 100)
        }

        // 3. grain: out = a + amp * (r - 0.5), done with linear light (d + 2s - 1)
        if p.grain > 0 {
            let cell = max(1, Double(max(extent.width, extent.height)) / K.grainCellDiv)
            let amp = K.grainAmount * p.grain / 100
            let noise = CIFilter.randomGenerator().outputImage!
                .transformed(by: CGAffineTransform(translationX: CGFloat(p.seed % 251), y: CGFloat(p.seed % 241)))
                .samplingNearest()
                .transformed(by: CGAffineTransform(scaleX: cell, y: cell))
                .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
                .cropped(to: extent)
                .settingAlphaOne(in: extent)
            let grey = CIFilter.colorMatrix()                   // s = 0.5 + 0.5 * amp * (r - 0.5)
            grey.inputImage = noise
            let v = CIVector(x: CGFloat(0.5 * amp), y: 0, z: 0, w: 0)
            grey.rVector = v; grey.gVector = v; grey.bVector = v
            grey.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            let b = CGFloat(0.5 - 0.25 * amp)
            grey.biasVector = CIVector(x: b, y: b, z: b, w: 0)
            let blend = CIFilter.linearLightBlendMode()
            blend.inputImage = grey.outputImage
            blend.backgroundImage = img
            img = Self.clamp(blend.outputImage ?? img).cropped(to: extent)
        }

        return img.matchedToWorkingSpace(from: p3) ?? img
    }

    /// Full-resolution JPEG of a filtered photo, tagged Display P3.
    func jpegData(_ p: AlcoveParams, photo: CIImage, quality: Double = 0.95) -> Data? {
        let key = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        return context.jpegRepresentation(of: apply(p, to: photo), colorSpace: p3, options: [key: quality])
    }

    // MARK: helpers

    /// a * (1 - t) + b * t
    private static func mix(_ a: CIImage, _ b: CIImage, _ t: Double) -> CIImage {
        let f = CIFilter.dissolveTransition()
        f.inputImage = a
        f.targetImage = b
        f.time = Float(min(max(t, 0), 1))
        return f.outputImage ?? a
    }

    private static func clamp(_ img: CIImage) -> CIImage {
        let f = CIFilter.colorClamp()
        f.inputImage = img
        f.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        f.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        return f.outputImage ?? img
    }
}

// MARK: - Live preview view (Metal)

/// Shows filtered camera frames. Set `image` on the main thread for every frame.
final class AlcovePreviewView: MTKView {
    var image: CIImage? { didSet { setNeedsDisplay() } }

    private var queue: MTLCommandQueue!
    private var ciContext: CIContext!
    private let p3 = CGColorSpace(name: CGColorSpace.displayP3)!

    init() {
        let device = MTLCreateSystemDefaultDevice()!
        super.init(frame: .zero, device: device)
        queue = device.makeCommandQueue()
        ciContext = CIContext(mtlDevice: device)
        framebufferOnly = false
        isPaused = true
        enableSetNeedsDisplay = true
        colorPixelFormat = .bgra8Unorm
        (layer as? CAMetalLayer)?.colorspace = p3
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let image, let drawable = currentDrawable,
              let buffer = queue.makeCommandBuffer() else { return }
        let size = drawableSize
        // aspect-fit, centred
        let s = min(size.width / image.extent.width, size.height / image.extent.height)
        var img = image.transformed(by: CGAffineTransform(scaleX: s, y: s))
        img = img.transformed(by: CGAffineTransform(
            translationX: (size.width - img.extent.width) / 2 - img.extent.minX,
            y: (size.height - img.extent.height) / 2 - img.extent.minY))
        let dest = CIRenderDestination(width: Int(size.width), height: Int(size.height),
                                       pixelFormat: colorPixelFormat, commandBuffer: buffer,
                                       mtlTextureProvider: { drawable.texture })
        dest.colorSpace = p3
        _ = try? ciContext.startTask(toClear: dest)
        _ = try? ciContext.startTask(toRender: img, to: dest)
        buffer.present(drawable)
        buffer.commit()
    }
}
