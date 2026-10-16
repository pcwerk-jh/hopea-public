@preconcurrency import CoreGraphics
@preconcurrency import CoreImage
import CoreImage.CIFilterBuiltins

/// The look pipeline: the single definition of how a look renders, shared by the Hopea app
/// (preview, capture, library apply) and the hub's preview renderer, so what you see is what
/// you get everywhere.
///
/// Order (FORMAT.md, "Rendering"): input → working space → LUT → halation → vignette → grain.
/// Core Image converts inputs into the context's working space (extended linear sRGB)
/// automatically, and every step below is expressed in that space unless noted.
///
/// Only built-in Core Image filters are used. Every size-dependent parameter (halation radius,
/// vignette radius, grain size) is relative to the input's extent, so a 1440-pixel preview
/// frame and a 12 MP capture get the same look.
public struct LookPipeline: Sendable {
    public let library: LookLibrary

    public init(library: LookLibrary) {
        self.library = library
    }

    /// Display P3, gamma-encoded: the space the LUTs are authored in.
    public static let lutColorSpace = CGColorSpace(name: CGColorSpace.displayP3)!

    public func apply(_ look: Look, to image: CIImage, quality: LookQuality, grainSeed: UInt32) -> CIImage {
        let extent = image.extent
        guard !extent.isInfinite, !extent.isEmpty else { return image }
        guard let cube = library.cube(for: look) else {
            KitLog.looks.error("No LUT loaded for look \(look.id, privacy: .public); passing image through")
            return image
        }

        var output = applyLUT(cube, to: image)
        if look.isMonochrome {
            output = Self.monochrome(output)
        }
        if look.halation > 0 {
            output = Self.halation(output, amount: look.halation, monochrome: look.isMonochrome)
        }
        if look.vignette > 0 {
            output = Self.vignette(output, amount: look.vignette)
        }
        if look.grain > 0 {
            // Preview and full use the same grain model; at preview size the particle size is
            // clamped to one pixel, which is cheaper and visually equivalent on screen.
            output = Self.grain(output, amount: look.grain, seed: grainSeed)
        }
        return output.cropped(to: extent)
    }

    // MARK: Steps

    private func applyLUT(_ cube: LookCube, to image: CIImage) -> CIImage {
        let filter = CIFilter.colorCubeWithColorSpace()
        filter.inputImage = image
        filter.cubeDimension = Float(cube.dimension)
        filter.cubeData = cube.data
        filter.colorSpace = Self.lutColorSpace
        filter.extrapolate = false
        return filter.outputImage ?? image
    }

    /// Belt and braces for monochrome looks: guarantees neutral output even if a LUT drifts.
    private static func monochrome(_ image: CIImage) -> CIImage {
        let luma = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = luma
        filter.gVector = luma
        filter.bVector = luma
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        filter.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        return filter.outputImage ?? image
    }

    /// Threshold highlights → blur → tint red/orange → screen-blend at low opacity.
    private static func halation(_ image: CIImage, amount: Double, monochrome: Bool) -> CIImage {
        let extent = image.extent
        let t = LookTuning.Halation.threshold
        let scale = 1 / (1 - t)
        let strength = amount * LookTuning.Halation.opacity
        let tint = monochrome ? (r: 1.0, g: 1.0, b: 1.0) : LookTuning.Halation.tint

        // One matrix: tinted, scaled (luminance − threshold). Clamping removes the negatives.
        func row(_ k: Double) -> CIVector {
            let s = CGFloat(k * scale * strength)
            return CIVector(x: 0.2126 * s, y: 0.7152 * s, z: 0.0722 * s, w: 0)
        }
        func bias(_ k: Double) -> CGFloat { CGFloat(-t * scale * strength * k) }

        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        matrix.rVector = row(tint.r)
        matrix.gVector = row(tint.g)
        matrix.bVector = row(tint.b)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        matrix.biasVector = CIVector(x: bias(tint.r), y: bias(tint.g), z: bias(tint.b), w: 0)

        let clamp = CIFilter.colorClamp()
        clamp.inputImage = matrix.outputImage
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 1)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)

        let radius = min(extent.width, extent.height) * LookTuning.Halation.radiusFraction
        guard let highlights = clamp.outputImage else { return image }
        let glow = highlights.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(radius))
            .cropped(to: extent)

        let screen = CIFilter.screenBlendMode()
        screen.inputImage = glow
        screen.backgroundImage = image
        return screen.outputImage ?? image
    }

    private static func vignette(_ image: CIImage, amount: Double) -> CIImage {
        let extent = image.extent
        let halfDiagonal = hypot(extent.width, extent.height) / 2
        let filter = CIFilter.vignetteEffect()
        filter.inputImage = image
        filter.center = CGPoint(x: extent.midX, y: extent.midY)
        filter.radius = Float(halfDiagonal * LookTuning.Vignette.radiusFraction)
        filter.intensity = Float(amount * LookTuning.Vignette.maxIntensity)
        filter.falloff = LookTuning.Vignette.falloff
        return filter.outputImage ?? image
    }

    /// Luminance-weighted film grain.
    ///
    /// Mid-grey-centred monochrome noise is overlay-blended onto the gamma-encoded image.
    /// Overlay leaves black and white untouched and has the most effect in the midtones, which
    /// gives the "stronger in midtones, weaker in deep shadows and highlights" weighting
    /// without a custom kernel. The noise is zero-mean, so the average colour is
    /// unchanged — which is what lets preview and full quality match after downscaling.
    private static func grain(_ image: CIImage, amount: Double, seed: UInt32) -> CIImage {
        let extent = image.extent
        let particle = max(1, min(extent.width, extent.height) * LookTuning.Grain.sizeFraction)
        let a = CGFloat(amount * LookTuning.Grain.strength)

        // CIRandomGenerator is an infinite, fixed noise field; the seed picks where we sample it.
        let offset = CGPoint(x: CGFloat(seed % 4096), y: CGFloat((seed / 4096) % 4096))
        guard let random = CIFilter.randomGenerator().outputImage else { return image }
        // The generator randomises alpha too; force it to 1 first, otherwise filters that
        // un-premultiply (like the colour matrix below) divide by a random alpha and the
        // noise stops being zero-mean.
        let field = random
            .settingAlphaOne(in: .infinite)
            .transformed(by: CGAffineTransform(translationX: -offset.x, y: -offset.y))
            .transformed(by: CGAffineTransform(scaleX: particle, y: particle))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)

        // Monochrome, centred on 0.5 with amplitude `a`, fully opaque.
        let noise = CIFilter.colorMatrix()
        noise.inputImage = field
        let r = CIVector(x: a, y: 0, z: 0, w: 0)
        noise.rVector = r
        noise.gVector = r
        noise.bVector = r
        noise.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        noise.biasVector = CIVector(x: 0.5 - a / 2, y: 0.5 - a / 2, z: 0.5 - a / 2, w: 1)

        let encoded = image.applyingFilter("CILinearToSRGBToneCurve")
        let overlay = CIFilter.overlayBlendMode()
        overlay.inputImage = noise.outputImage
        overlay.backgroundImage = encoded
        guard let blended = overlay.outputImage else { return image }
        return blended.applyingFilter("CISRGBToneCurveToLinear")
    }
}

extension LookPipeline {
    /// A fresh grain seed for each preview frame or capture.
    public static func randomSeed() -> UInt32 { UInt32.random(in: 0..<(4096 * 4096)) }
}
