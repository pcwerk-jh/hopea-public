import Foundation

/// A look described by photographic controls instead of a hand-made LUT (recipe format 1).
///
/// `LookRecipe.bake()` turns the controls into a 3D LUT plus the grain / vignette / halation
/// settings of a `.hopealook`. The maths below is part of the recipe format: the same recipe
/// always bakes to the same look, and editors (web, in-app) must use the same definitions.
///
/// Control ranges follow common editing apps: most are −100…+100 with 0 neutral;
/// grain, fade, vignette, halation are 0…100; exposure is in EV.
public struct LookRecipe: Codable, Equatable, Sendable {
    public struct Controls: Codable, Equatable, Sendable {
        public var exposure: Double = 0      // EV, −2…+2
        public var contrast: Double = 0      // −100…+100
        public var saturation: Double = 0    // −100…+100 (−100 = no colour)
        public var warmth: Double = 0        // −100 (blue) … +100 (amber)
        public var tint: Double = 0          // −100 (green) … +100 (magenta)
        public var highlights: Double = 0    // −100 (recover) … +100
        public var shadows: Double = 0       // −100 (deepen) … +100 (lift)
        public var fade: Double = 0          // 0…100, lifts blacks and softens whites
        public var grain: Double = 0         // 0…100
        public var vignette: Double = 0      // 0…100
        public var halation: Double = 0      // 0…100

        public init() {}

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func value(_ key: CodingKeys) throws -> Double { try c.decodeIfPresent(Double.self, forKey: key) ?? 0 }
            exposure = try value(.exposure)
            contrast = try value(.contrast)
            saturation = try value(.saturation)
            warmth = try value(.warmth)
            tint = try value(.tint)
            highlights = try value(.highlights)
            shadows = try value(.shadows)
            fade = try value(.fade)
            grain = try value(.grain)
            vignette = try value(.vignette)
            halation = try value(.halation)
        }
    }

    /// Targeted colour adjustment around one hue band.
    public struct ColorBand: Codable, Equatable, Sendable {
        public enum Hue: String, Codable, Sendable, CaseIterable {
            case red, orange, yellow, green, aqua, blue, purple, magenta

            public var degrees: Double {
                switch self {
                case .red: 0
                case .orange: 30
                case .yellow: 60
                case .green: 120
                case .aqua: 180
                case .blue: 225
                case .purple: 270
                case .magenta: 315
                }
            }
        }

        public var hue: Hue
        public var saturation: Double? // −100…+100
        public var hueShift: Double?   // degrees, −180…+180
        public var luminance: Double?  // −100…+100

        public init(hue: Hue, saturation: Double? = nil, hueShift: Double? = nil, luminance: Double? = nil) {
            self.hue = hue
            self.saturation = saturation
            self.hueShift = hueShift
            self.luminance = luminance
        }
    }

    /// A colour pushed into shadows or highlights.
    public struct Tone: Codable, Equatable, Sendable {
        public var hue: Double     // degrees
        public var amount: Double  // 0…100

        public init(hue: Double, amount: Double) {
            self.hue = hue
            self.amount = amount
        }
    }

    public struct SplitTone: Codable, Equatable, Sendable {
        public var shadows: Tone?
        public var highlights: Tone?

        public init(shadows: Tone? = nil, highlights: Tone? = nil) {
            self.shadows = shadows
            self.highlights = highlights
        }
    }

    /// Black-and-white conversion with an optional duotone.
    public struct Monochrome: Codable, Equatable, Sendable {
        public struct Mix: Codable, Equatable, Sendable {
            public var red: Double
            public var green: Double
            public var blue: Double

            public init(red: Double, green: Double, blue: Double) {
                self.red = red
                self.green = green
                self.blue = blue
            }
        }

        public var mix: Mix
        public var shadowTone: String?     // "#RRGGBB"
        public var highlightTone: String?  // "#RRGGBB"
        public var toning: Double?         // 0…1

        public init(mix: Mix, shadowTone: String? = nil, highlightTone: String? = nil, toning: Double? = nil) {
            self.mix = mix
            self.shadowTone = shadowTone
            self.highlightTone = highlightTone
            self.toning = toning
        }
    }

    /// Per-channel gain applied in linear light (e.g. suppressing blue for a redscale look).
    public struct ChannelGain: Codable, Equatable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    public var recipe: Int
    public var id: String
    public var version: String
    public var name: String
    public var description: String?
    public var tags: [String]
    public var license: String
    public var author: LookManifest.Author
    public var remixOf: String?
    public var lutDimension: Int?
    public var controls: Controls
    public var colors: [ColorBand]?
    public var splitTone: SplitTone?
    public var monochrome: Monochrome?
    public var channelGain: ChannelGain?

    public static let currentFormat = 1

    public enum BakeError: Error, CustomStringConvertible {
        case unsupportedRecipe(Int)
        case outOfRange(String)
        case invalid([LookValidationError])

        public var description: String {
            switch self {
            case .unsupportedRecipe(let v): "unsupported recipe format \(v)"
            case .outOfRange(let field): "\(field) is out of range"
            case .invalid(let errors): errors.map(\.description).joined(separator: "\n")
            }
        }
    }

    // MARK: Baking

    /// The finished look: a validated manifest whose LUT and settings come from this recipe.
    public func bake() throws -> LookManifest {
        guard recipe == Self.currentFormat else { throw BakeError.unsupportedRecipe(recipe) }
        try checkRanges()
        let dimension = lutDimension ?? 33
        let toned = isTonedMonochrome
        let manifest = LookManifest(
            id: id, version: version, name: name, description: description, tags: tags,
            license: license, author: author, remixOf: remixOf,
            lut: .init(dimension: dimension, cube: cubeText(dimension: dimension)),
            grain: controls.grain / 100, vignette: controls.vignette / 100, halation: controls.halation / 100,
            // A toned monochrome keeps its tint, so it must not be forced neutral.
            monochrome: monochrome != nil && !toned)
        let errors = LookValidator.validate(manifest)
        guard errors.isEmpty else { throw BakeError.invalid(errors) }
        return manifest
    }

    private var isTonedMonochrome: Bool {
        guard let mono = monochrome else { return false }
        return (mono.toning ?? 0) > 0 && (mono.shadowTone != nil || mono.highlightTone != nil)
    }

    private func checkRanges() throws {
        let c = controls
        let bipolar = [("contrast", c.contrast), ("saturation", c.saturation), ("warmth", c.warmth), ("tint", c.tint),
                       ("highlights", c.highlights), ("shadows", c.shadows)]
        for (name, v) in bipolar where !(v.isFinite && (-100...100).contains(v)) { throw BakeError.outOfRange("controls.\(name)") }
        for (name, v) in [("fade", c.fade), ("grain", c.grain), ("vignette", c.vignette), ("halation", c.halation)]
        where !(v.isFinite && (0...100).contains(v)) { throw BakeError.outOfRange("controls.\(name)") }
        guard c.exposure.isFinite, (-2...2).contains(c.exposure) else { throw BakeError.outOfRange("controls.exposure") }
        for band in colors ?? [] {
            if let s = band.saturation, !(-100...100).contains(s) { throw BakeError.outOfRange("colors.\(band.hue).saturation") }
            if let h = band.hueShift, !(-180...180).contains(h) { throw BakeError.outOfRange("colors.\(band.hue).hueShift") }
            if let l = band.luminance, !(-100...100).contains(l) { throw BakeError.outOfRange("colors.\(band.hue).luminance") }
        }
        for tone in [splitTone?.shadows, splitTone?.highlights].compactMap({ $0 }) where !(0...100).contains(tone.amount) {
            throw BakeError.outOfRange("splitTone.amount")
        }
        if let gain = channelGain, ![gain.red, gain.green, gain.blue].allSatisfy({ (0...2).contains($0) }) {
            throw BakeError.outOfRange("channelGain")
        }
        if let mono = monochrome {
            let m = mono.mix
            guard [m.red, m.green, m.blue].allSatisfy({ (0...1).contains($0) }), m.red + m.green + m.blue > 0 else {
                throw BakeError.outOfRange("monochrome.mix")
            }
            if let t = mono.toning, !(0...1).contains(t) { throw BakeError.outOfRange("monochrome.toning") }
            for hex in [mono.shadowTone, mono.highlightTone].compactMap({ $0 }) where RGB(hex: hex) == nil {
                throw BakeError.outOfRange("monochrome tone \(hex)")
            }
        }
    }

    /// The `.cube` text for the baked LUT (gamma-encoded Display P3 in and out).
    public func cubeText(dimension: Int) -> String {
        cubeText(dimension: dimension, base: nil)
    }

    /// The `.cube` text with `base` (another look's table) applied before this recipe.
    public func cubeText(dimension: Int, base: LookCube?) -> String {
        var out = "TITLE \"\(name)\"\n# Baked from recipe \(id) \(version) by HopeaLookKit\nLUT_3D_SIZE \(dimension)\n"
        out.reserveCapacity(dimension * dimension * dimension * 26 + 100)
        let n = Double(dimension - 1)
        for b in 0..<dimension {
            for g in 0..<dimension {
                for r in 0..<dimension {
                    let c = output(RGB(Double(r) / n, Double(g) / n, Double(b) / n), base: base)
                    out += "\(Self.format(c.r)) \(Self.format(c.g)) \(Self.format(c.b))\n"
                }
            }
        }
        return out
    }

    /// One grid point of the table: the base look (if any), then this recipe.
    func output(_ input: RGB, base: LookCube?) -> RGB {
        apply(base.map { $0.sample(input) } ?? input)
    }

    static func format(_ v: Double) -> String {
        String(format: "%.5f", min(max(v, 0), 1))
    }

    /// The colour transform for one gamma-encoded Display P3 value.
    func apply(_ input: RGB) -> RGB {
        let k = controls

        // 1. Linear light: exposure, white balance, channel gain, black-and-white mix.
        var lin = input.map(Self.toLinear)
        let ev = pow(2, k.exposure)
        let w = k.warmth / 100, t = k.tint / 100
        lin = RGB(lin.r * ev * (1 + 0.10 * w + 0.03 * t),
                  lin.g * ev * (1 - 0.06 * t),
                  lin.b * ev * (1 - 0.10 * w + 0.03 * t))
        if let gain = channelGain {
            lin = RGB(lin.r * gain.red, lin.g * gain.green, lin.b * gain.blue)
        }
        if let mono = monochrome {
            let m = mono.mix
            let y = (lin.r * m.red + lin.g * m.green + lin.b * m.blue) / (m.red + m.green + m.blue)
            lin = RGB(y, y, y)
        }
        var c = lin.map { Self.toGamma(min(max($0, 0), 1)) }

        // 2. Colour: targeted bands, then global saturation.
        if monochrome == nil {
            if let bands = colors, !bands.isEmpty { c = Self.adjustBands(c, bands) }
            let y = c.luma
            let s = 1 + k.saturation / 100
            c = RGB(y + (c.r - y) * s, y + (c.g - y) * s, y + (c.b - y) * s).clamped
        }

        // 3. Tone, per channel (film-like: contrast also adds a little colour).
        c = c.map { Self.tone($0, contrast: k.contrast / 100, highlights: k.highlights / 100, shadows: k.shadows / 100) }

        // 4. Split toning / monochrome duotone.
        if let split = splitTone, monochrome == nil {
            let y = c.luma
            if let tone = split.shadows {
                c = c + Self.tint(hue: tone.hue) * (tone.amount / 100 * 0.12 * (1 - Self.smoothstep(0, 0.55, y)))
            }
            if let tone = split.highlights {
                c = c + Self.tint(hue: tone.hue) * (tone.amount / 100 * 0.12 * Self.smoothstep(0.45, 1, y))
            }
        }
        if let mono = monochrome, let strength = mono.toning, strength > 0 {
            let y = c.luma
            let dark = mono.shadowTone.flatMap(RGB.init(hex:)) ?? RGB(y, y, y)
            let light = mono.highlightTone.flatMap(RGB.init(hex:)) ?? RGB(y, y, y)
            let toneColor = dark * (1 - y) + light * y
            let scaled = toneColor * (y / max(toneColor.luma, 1e-4))
            c = RGB(y, y, y) * (1 - strength) + scaled * strength
        }

        // 5. Fade: lift blacks, soften whites.
        let f = k.fade / 100
        c = c.map { f * 0.15 + $0 * (1 - f * 0.20) }
        return c.clamped
    }

    // MARK: Building blocks

    static func toLinear(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    static func toGamma(_ l: Double) -> Double {
        l <= 0.0031308 ? 12.92 * l : 1.055 * pow(l, 1 / 2.4) - 0.055
    }

    static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    static func tone(_ x: Double, contrast: Double, highlights: Double, shadows: Double) -> Double {
        var v = x
        if contrast >= 0 {
            v = v + (smoothstep(0, 1, v) - v) * contrast * 0.9
        } else {
            v = v + (0.5 + (v - 0.5) * 0.6 - v) * -contrast
        }
        let highlightWeight = smoothstep(0.45, 0.85, v) * (1 - 0.5 * smoothstep(0.85, 1, v))
        v += highlights * 0.15 * highlightWeight
        let shadowWeight = (1 - smoothstep(0, 0.5, v)) * smoothstep(0, 0.15, v)
        v += shadows * 0.15 * shadowWeight
        return min(max(v, 0), 1)
    }

    /// A zero-mean colour offset pointing toward `hue`.
    static func tint(hue: Double) -> RGB {
        let c = HSV(h: hue, s: 1, v: 1).rgb
        let mean = (c.r + c.g + c.b) / 3
        return RGB(c.r - mean, c.g - mean, c.b - mean)
    }

    static func adjustBands(_ input: RGB, _ bands: [ColorBand]) -> RGB {
        var hsv = HSV(input)
        let originalHue = hsv.h
        // Neutral colours have no meaningful hue: leave greys alone.
        let chroma = smoothstep(0.04, 0.25, hsv.s)
        guard chroma > 0 else { return input }
        var touched = false
        for band in bands {
            var distance = abs(originalHue - band.hue.degrees).truncatingRemainder(dividingBy: 360)
            if distance > 180 { distance = 360 - distance }
            let width = 35.0
            guard distance < width else { continue }
            var weight = 1 - distance / width
            weight = weight * weight * (3 - 2 * weight) * chroma
            touched = true
            hsv.h += (band.hueShift ?? 0) * weight
            hsv.s *= 1 + (band.saturation ?? 0) / 100 * weight
            hsv.v *= 1 + (band.luminance ?? 0) / 100 * 0.25 * weight
        }
        guard touched else { return input }
        hsv.s = min(max(hsv.s, 0), 1)
        hsv.v = min(max(hsv.v, 0), 1)
        return hsv.rgb
    }
}

// MARK: - Small colour types

struct RGB: Equatable {
    var r, g, b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    /// Rec. 709 weights on gamma-encoded values: a perceptual luma, good enough for tone masks.
    var luma: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
    var clamped: RGB { map { min(max($0, 0), 1) } }

    func map(_ f: (Double) -> Double) -> RGB { RGB(f(r), f(g), f(b)) }

    static func + (a: RGB, b: RGB) -> RGB { RGB(a.r + b.r, a.g + b.g, a.b + b.b) }
    static func * (a: RGB, k: Double) -> RGB { RGB(a.r * k, a.g * k, a.b * k) }
}

struct HSV {
    var h: Double  // degrees
    var s: Double
    var v: Double

    init(h: Double, s: Double, v: Double) {
        self.h = h
        self.s = s
        self.v = v
    }

    init(_ c: RGB) {
        let maxV = max(c.r, c.g, c.b), minV = min(c.r, c.g, c.b)
        let delta = maxV - minV
        v = maxV
        s = maxV > 0 ? delta / maxV : 0
        if delta == 0 {
            h = 0
        } else if maxV == c.r {
            h = 60 * ((c.g - c.b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxV == c.g {
            h = 60 * ((c.b - c.r) / delta + 2)
        } else {
            h = 60 * ((c.r - c.g) / delta + 4)
        }
        if h < 0 { h += 360 }
    }

    var rgb: RGB {
        var hue = h.truncatingRemainder(dividingBy: 360)
        if hue < 0 { hue += 360 }
        let c = v * s
        let x = c * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let (r, g, b): (Double, Double, Double) = switch hue {
        case ..<60: (c, x, 0)
        case ..<120: (x, c, 0)
        case ..<180: (0, c, x)
        case ..<240: (0, x, c)
        case ..<300: (x, 0, c)
        default: (c, 0, x)
        }
        return RGB(r + m, g + m, b + m)
    }
}
