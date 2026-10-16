import Foundation

/// The contents of a `.hopealook` file (format 1). See FORMAT.md for the full specification.
public struct LookManifest: Codable, Equatable, Sendable {
    public struct Author: Codable, Equatable, Sendable {
        public var name: String
        public var handle: String
        public var url: String?

        public init(name: String, handle: String, url: String? = nil) {
            self.name = name
            self.handle = handle
            self.url = url
        }
    }

    public struct LUT: Codable, Equatable, Sendable {
        public var dimension: Int
        public var colorSpace: String
        /// The `.cube` file's text.
        public var cube: String

        public init(dimension: Int, colorSpace: String = LookManifest.lutColorSpace, cube: String) {
            self.dimension = dimension
            self.colorSpace = colorSpace
            self.cube = cube
        }
    }

    public static let currentFormat = 1
    public static let lutColorSpace = "displayP3"

    public var format: Int
    public var id: String
    public var version: String
    public var name: String
    public var description: String?
    public var tags: [String]
    public var license: String
    public var author: Author
    public var remixOf: String?
    public var minAppVersion: String?
    public var lut: LUT
    public var grain: Double
    public var vignette: Double
    public var halation: Double
    public var monochrome: Bool

    public init(format: Int = LookManifest.currentFormat,
                id: String,
                version: String,
                name: String,
                description: String? = nil,
                tags: [String] = [],
                license: String,
                author: Author,
                remixOf: String? = nil,
                minAppVersion: String? = nil,
                lut: LUT,
                grain: Double,
                vignette: Double,
                halation: Double,
                monochrome: Bool) {
        self.format = format
        self.id = id
        self.version = version
        self.name = name
        self.description = description
        self.tags = tags
        self.license = license
        self.author = author
        self.remixOf = remixOf
        self.minAppVersion = minAppVersion
        self.lut = lut
        self.grain = grain
        self.vignette = vignette
        self.halation = halation
        self.monochrome = monochrome
    }

    /// The creator namespace and look slug from `id` ("@jane/harbor-fog" → ("jane", "harbor-fog")).
    public var idParts: (handle: String, slug: String)? {
        guard id.hasPrefix("@"), let slash = id.firstIndex(of: "/") else { return nil }
        return (String(id[id.index(after: id.startIndex)..<slash]), String(id[id.index(after: slash)...]))
    }
}
