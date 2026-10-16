@preconcurrency import CoreGraphics
@preconcurrency import CoreImage
import Foundation
@preconcurrency import ImageIO

/// Small renders of an image with each look: look pickers, catalogs, and the hub's previews.
public struct LookPreviewRenderer: Sendable {
    public let pipeline: LookPipeline
    private let context = LookColor.makeContext(name: "HopeaLookKit previews")

    public init(pipeline: LookPipeline) {
        self.pipeline = pipeline
    }

    /// Renders `image` once per look, downscaled to `maxSide`. Runs off the caller's actor.
    public func render(_ image: CIImage, looks: [Look], maxSide: CGFloat,
                       quality: LookQuality = .preview, grainSeed: UInt32? = nil) async -> [Look.ID: CGImage] {
        let small = Self.downscale(image, maxSide: maxSide)
        var result: [Look.ID: CGImage] = [:]
        for look in looks {
            let seed = grainSeed ?? LookPipeline.randomSeed()
            if let cgImage = makeCGImage(pipeline.apply(look, to: small, quality: quality, grainSeed: seed)) {
                result[look.id] = cgImage
            }
        }
        return result
    }

    /// Renders `image` with one look (or unprocessed when `look` is nil).
    public func render(_ image: CIImage, look: Look?, maxSide: CGFloat,
                       quality: LookQuality = .preview, grainSeed: UInt32? = nil) async -> CGImage? {
        let small = Self.downscale(image, maxSide: maxSide)
        let seed = grainSeed ?? LookPipeline.randomSeed()
        let graded = look.map { pipeline.apply($0, to: small, quality: quality, grainSeed: seed) } ?? small
        return makeCGImage(graded)
    }

    private func makeCGImage(_ image: CIImage) -> CGImage? {
        context.createCGImage(image, from: image.extent.integral, format: .RGBA8, colorSpace: LookColor.outputColorSpace)
    }

    /// Scales `image` so its longer side is at most `maxSide`, moved to the origin.
    public static func downscale(_ image: CIImage, maxSide: CGFloat) -> CIImage {
        let extent = image.extent
        let scale = min(1, maxSide / max(extent.width, extent.height))
        return image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    /// Loads an image file, upright, with its longer side at most `maxSide`.
    public static func loadImage(at url: URL, maxSide: CGFloat) -> CIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { CIImage(cgImage: $0) }
    }
}
