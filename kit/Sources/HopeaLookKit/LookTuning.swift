@preconcurrency import CoreGraphics
@preconcurrency import CoreImage

/// The constants that define how grain, halation and vignette render. Part of the format:
/// changing them changes every look, so they are versioned with the kit (FORMAT.md, "Rendering").
public enum LookTuning {
    public enum Grain {
        /// Grain particle size as a fraction of the image's short side, so grain looks the
        /// same at preview and full resolution.
        public static let sizeFraction: CGFloat = 1.0 / 1500.0
        /// Overlay amplitude at `grain == 1`.
        public static let strength: Double = 0.16
    }

    public enum Halation {
        /// Linear-light luminance above which highlights start to bloom.
        public static let threshold: Double = 0.65
        /// Blur radius as a fraction of the image's short side.
        public static let radiusFraction: CGFloat = 0.012
        /// Screen-blend opacity at `halation == 1`.
        public static let opacity: Double = 0.6
        /// Red/orange tint of the bloom (linear RGB multipliers).
        public static let tint: (r: Double, g: Double, b: Double) = (1.0, 0.38, 0.18)
    }

    public enum Vignette {
        /// Radius as a fraction of the half-diagonal.
        public static let radiusFraction: CGFloat = 0.95
        /// Intensity at `vignette == 1`.
        public static let maxIntensity: Double = 1.0
        public static let falloff: Float = 0.6
    }
}

/// Colour spaces shared by everything that renders looks, so preview and export match.
public enum LookColor {
    /// Core Image working space for every context that renders looks.
    public static let workingColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    /// Output (and LUT) colour space.
    public static let outputColorSpace = CGColorSpace(name: CGColorSpace.displayP3)!

    /// A context configured the way looks are meant to be rendered.
    public static func makeContext(name: String, softwareRenderer: Bool = false) -> CIContext {
        CIContext(options: [
            .workingColorSpace: workingColorSpace,
            .workingFormat: CIFormat.RGBAh,
            .cacheIntermediates: false,
            .useSoftwareRenderer: softwareRenderer,
            .name: name,
        ])
    }
}
