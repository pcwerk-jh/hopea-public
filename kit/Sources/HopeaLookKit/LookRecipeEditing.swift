import Foundation

// Building and baking recipes in an editor (Hopea's Lab): public initialisers, a table ready for
// Core Image without going through `.cube` text, and recipes layered on another look's table.

extension LookRecipe {
    public init(id: String, version: String, name: String, description: String? = nil, tags: [String] = [],
                license: String, author: LookManifest.Author, remixOf: String? = nil, lutDimension: Int? = nil,
                controls: Controls = .init(), colors: [ColorBand]? = nil, splitTone: SplitTone? = nil,
                monochrome: Monochrome? = nil, channelGain: ChannelGain? = nil) {
        self.init(recipe: Self.currentFormat, id: id, version: version, name: name, description: description,
                  tags: tags, license: license, author: author, remixOf: remixOf, lutDimension: lutDimension,
                  controls: controls, colors: colors, splitTone: splitTone, monochrome: monochrome,
                  channelGain: channelGain)
    }

    /// The baked table, laid out for `CIColorCubeWithColorSpace`, with `base` (another look's
    /// table) applied first. Values are rounded as the `.cube` text rounds them, so a preview made
    /// from this matches the saved look exactly.
    public func cube(dimension: Int, base: LookCube? = nil) -> LookCube {
        var values = [Float](repeating: 1, count: dimension * dimension * dimension * 4)
        let n = Double(dimension - 1)
        var i = 0
        for b in 0..<dimension {
            for g in 0..<dimension {
                for r in 0..<dimension {
                    let c = output(RGB(Double(r) / n, Double(g) / n, Double(b) / n), base: base)
                    values[i] = Self.rounded(c.r)
                    values[i + 1] = Self.rounded(c.g)
                    values[i + 2] = Self.rounded(c.b)
                    i += 4
                }
            }
        }
        return LookCube(dimension: dimension, data: values.withUnsafeBufferPointer { Data(buffer: $0) })
    }

    private static func rounded(_ v: Double) -> Float {
        Float((min(max(v, 0), 1) * 100_000).rounded() / 100_000)
    }

    /// Bakes this recipe on top of `base`. A monochrome base stays monochrome unless the recipe
    /// tones it.
    public func bake(base: LookCube?, baseIsMonochrome: Bool = false) throws -> LookManifest {
        var manifest = try bake()
        guard let base else { return manifest }
        let dimension = lutDimension ?? 33
        manifest.lut = .init(dimension: dimension, cube: cubeText(dimension: dimension, base: base))
        let toned = (monochrome?.toning ?? 0) > 0 && (monochrome?.shadowTone != nil || monochrome?.highlightTone != nil)
        manifest.monochrome = (monochrome != nil || baseIsMonochrome) && !toned
        return manifest
    }

    /// Every control at its neutral value: the recipe changes nothing.
    public var isNeutral: Bool {
        controls == Controls() && (colors ?? []).allSatisfy(\.isNeutral)
            && (splitTone?.shadows?.amount ?? 0) == 0 && (splitTone?.highlights?.amount ?? 0) == 0
            && monochrome == nil && (channelGain.map { $0.red == 1 && $0.green == 1 && $0.blue == 1 } ?? true)
    }
}

extension LookRecipe.ColorBand {
    public var isNeutral: Bool { (saturation ?? 0) == 0 && (hueShift ?? 0) == 0 && (luminance ?? 0) == 0 }
}

extension LookCube {
    /// The table's output for one gamma-encoded Display P3 colour, interpolated between grid
    /// points as Core Image does (trilinear).
    func sample(_ c: RGB) -> RGB {
        let n = dimension
        let scale = Double(n - 1)
        func axis(_ v: Double) -> (Int, Int, Double) {
            let x = min(max(v, 0), 1) * scale
            let i = min(Int(x), n - 2)
            return (i, i + 1, x - Double(i))
        }
        let (r0, r1, fr) = axis(c.r), (g0, g1, fg) = axis(c.g), (b0, b1, fb) = axis(c.b)
        return data.withUnsafeBytes { raw -> RGB in
            let v = raw.bindMemory(to: Float.self)
            func at(_ r: Int, _ g: Int, _ b: Int) -> RGB {
                let i = ((b * n + g) * n + r) * 4
                return RGB(Double(v[i]), Double(v[i + 1]), Double(v[i + 2]))
            }
            func lerp(_ a: RGB, _ b: RGB, _ t: Double) -> RGB { a * (1 - t) + b * t }
            let c00 = lerp(at(r0, g0, b0), at(r1, g0, b0), fr)
            let c10 = lerp(at(r0, g1, b0), at(r1, g1, b0), fr)
            let c01 = lerp(at(r0, g0, b1), at(r1, g0, b1), fr)
            let c11 = lerp(at(r0, g1, b1), at(r1, g1, b1), fr)
            return lerp(lerp(c00, c10, fg), lerp(c01, c11, fg), fb)
        }
    }
}
