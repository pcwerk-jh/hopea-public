@preconcurrency import CoreGraphics
@preconcurrency import CoreImage
import Foundation
import Testing
@testable import HopeaLookKit

@Suite("Look pipeline")
struct LookPipelineTests {
    static let root = URL(filePath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let context = LookColor.makeContext(name: "tests")

    static func seededLibrary() throws -> LookLibrary {
        let loaded = try ["hopea", "americana", "harbor", "silver"].map {
            try LookPackage.read(contentsOf: root.appending(path: "looks/hopea/\($0)/look.hopealook"))
        }
        return LookLibrary(loaded)
    }

    static func reference(_ name: String, maxSide: CGFloat) throws -> CIImage {
        try #require(LookPreviewRenderer.loadImage(at: root.appending(path: "reference/\(name).jpg"), maxSide: maxSide))
    }

    static func rgbaf(_ image: CIImage) -> [Float] {
        let rect = image.extent.integral
        var values = [Float](repeating: 0, count: Int(rect.width) * Int(rect.height) * 4)
        values.withUnsafeMutableBytes { buffer in
            context.render(image, toBitmap: buffer.baseAddress!, rowBytes: Int(rect.width) * 16, bounds: rect,
                           format: .RGBAf, colorSpace: LookColor.outputColorSpace)
        }
        return values
    }

    @Test("Same seed → identical output; the extent never changes",
          arguments: ["@hopea/hopea", "@hopea/americana", "@hopea/harbor", "@hopea/silver"])
    func deterministic(id: String) throws {
        let library = try Self.seededLibrary()
        let pipeline = LookPipeline(library: library)
        let look = try #require(library.look(withID: id))
        let input = try Self.reference("sample_menu", maxSide: 96)
        let a = pipeline.apply(look, to: input, quality: .full, grainSeed: 99)
        let b = pipeline.apply(look, to: input, quality: .full, grainSeed: 99)
        #expect(a.extent == input.extent)
        #expect(Self.rgbaf(a) == Self.rgbaf(b))
    }

    @Test("Preview and full quality match in colour after downscaling",
          arguments: ["@hopea/hopea", "@hopea/americana", "@hopea/harbor", "@hopea/silver"])
    func previewMatchesFull(id: String) throws {
        let library = try Self.seededLibrary()
        let pipeline = LookPipeline(library: library)
        let look = try #require(library.look(withID: id))
        let full = try Self.reference("sample_bronco", maxSide: 1024)
        let small = LookPreviewRenderer.downscale(full, maxSide: 256)
        func smooth(_ image: CIImage) -> CIImage {
            let sized = LookPreviewRenderer.downscale(image, maxSide: 256)
            return sized.clampedToExtent().applyingGaussianBlur(sigma: 3).cropped(to: sized.extent.insetBy(dx: 8, dy: 8))
        }
        let a = Self.rgbaf(smooth(pipeline.apply(look, to: full, quality: .full, grainSeed: 1)))
        let b = Self.rgbaf(smooth(pipeline.apply(look, to: small, quality: .preview, grainSeed: 2)))
        #expect(a.count == b.count)
        var total: Float = 0
        var count = 0
        for i in 0..<min(a.count, b.count) where i % 4 != 3 {
            total += abs(a[i] - b[i])
            count += 1
        }
        #expect(total / Float(max(count, 1)) < 0.012)
    }

    @Test("Monochrome looks produce neutral pixels")
    func silverIsNeutral() throws {
        let library = try Self.seededLibrary()
        let output = LookPipeline(library: library)
            .apply(try #require(library.look(withID: "@hopea/silver")), to: try Self.reference("sample_sign", maxSide: 128),
                   quality: .full, grainSeed: 7)
        let pixels = Self.rgbaf(output)
        var spread: Float = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let rgb = pixels[i..<i + 3]
            spread = max(spread, (rgb.max() ?? 0) - (rgb.min() ?? 0))
        }
        #expect(spread < 0.01)
    }

    @Test("An identity look with no effects leaves the image unchanged")
    func identity() throws {
        let loaded = try LookPackage.read(try LookPackage.write(
            LookManifest(id: "@test/identity", version: "1.0.0", name: "Identity", license: "CC0-1.0",
                         author: .init(name: "Test", handle: "test"),
                         lut: .init(dimension: 17, cube: identityCube(size: 17)),
                         grain: 0, vignette: 0, halation: 0, monochrome: false)))
        let input = try Self.reference("sample_smokers", maxSide: 64)
        let output = LookPipeline(library: LookLibrary([loaded])).apply(loaded.look, to: input, quality: .full, grainSeed: 0)
        let a = Self.rgbaf(input), b = Self.rgbaf(output)
        let maxDiff = zip(a, b).map { abs($0 - $1) }.max() ?? 0
        #expect(maxDiff < 0.01)
    }
}
