import Foundation
import os

/// The parameters the pipeline needs to render a look. Built from a validated `LookManifest`.
public struct Look: Identifiable, Hashable, Sendable {
    public let id: String          // e.g. "@hopea/harbor"
    public let name: String        // display name, e.g. "Harbor"
    public let grain: Double       // 0–1, subtle
    public let vignette: Double    // 0–1
    public let halation: Double    // 0–1 (0 skips the step)
    public let isMonochrome: Bool

    public init(id: String, name: String, grain: Double, vignette: Double, halation: Double, isMonochrome: Bool) {
        self.id = id
        self.name = name
        self.grain = grain
        self.vignette = vignette
        self.halation = halation
        self.isMonochrome = isMonochrome
    }

    public init(_ manifest: LookManifest) {
        self.init(id: manifest.id,
                  name: manifest.name,
                  grain: manifest.grain,
                  vignette: manifest.vignette,
                  halation: manifest.halation,
                  isMonochrome: manifest.monochrome)
    }
}

/// A parsed 3D LUT, laid out for `CIColorCubeWithColorSpace` (RGBA float32, red fastest).
public struct LookCube: Sendable, Equatable {
    public let dimension: Int
    public let data: Data

    public init(dimension: Int, data: Data) {
        self.dimension = dimension
        self.data = data
    }
}

/// Preview may use cheaper settings; colour must match `.full` (see FORMAT.md).
public enum LookQuality: Sendable {
    case preview
    case full
}

enum KitLog {
    static let looks = Logger(subsystem: "HopeaLookKit", category: "looks")
}

extension Look {
    /// Natural: no look at all — the photo as the camera developed it, with no colour change,
    /// grain, halation or vignette. Every library can include it (first); the pipeline passes
    /// the image straight through.
    public static let natural = Look(id: "@hopea/natural", name: "Natural", grain: 0, vignette: 0, halation: 0,
                                     isMonochrome: false)

    public var isNatural: Bool { id == Look.natural.id }
}
