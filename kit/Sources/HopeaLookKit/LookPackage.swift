import Foundation

/// A validated look, ready to render.
public struct LoadedLook: Sendable {
    public let manifest: LookManifest
    public let look: Look
    public let cube: LookCube
}

/// Reads and writes `.hopealook` files: a single JSON document (no archive), so it can be
/// handled with Foundation alone on every platform.
public enum LookPackage {
    public static let fileExtension = "hopealook"
    public static let uniformTypeIdentifier = "com.pcwerk.hopea.look"

    public enum ReadError: Error, Equatable, CustomStringConvertible {
        case tooLarge(bytes: Int)
        case notJSON(String)
        case invalid([LookValidationError])
        case badLUT(String)

        public var description: String {
            switch self {
            case .tooLarge(let bytes):
                "file is \(bytes) bytes; the limit is \(LookValidator.maxPackageBytes)"
            case .notJSON(let detail):
                "not a valid .hopealook file (\(detail))"
            case .invalid(let errors):
                errors.map(\.description).joined(separator: "\n")
            case .badLUT(let detail):
                "lut.cube: \(detail)"
            }
        }
    }

    /// Decodes, validates and parses a package. Never trusts the input: size, schema, every
    /// field and the LUT itself are checked before anything is returned.
    public static func read(_ data: Data) throws(ReadError) -> LoadedLook {
        guard data.count <= LookValidator.maxPackageBytes else { throw .tooLarge(bytes: data.count) }
        let manifest: LookManifest
        do {
            manifest = try JSONDecoder().decode(LookManifest.self, from: data)
        } catch {
            throw .notJSON(String(describing: error))
        }
        let errors = LookValidator.validate(manifest)
        guard errors.isEmpty else { throw .invalid(errors) }

        let cube: LookCube
        do {
            cube = try CubeParser.parse(manifest.lut.cube)
        } catch {
            throw .badLUT(String(describing: error))
        }
        guard cube.dimension == manifest.lut.dimension else {
            throw .badLUT("file is \(cube.dimension)³ but lut.dimension says \(manifest.lut.dimension)")
        }
        return LoadedLook(manifest: manifest, look: Look(manifest), cube: cube)
    }

    public static func read(contentsOf url: URL) throws -> LoadedLook {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= LookValidator.maxPackageBytes else { throw ReadError.tooLarge(bytes: size) }
        return try read(try Data(contentsOf: url))
    }

    /// Encodes a manifest as a stable, diff-friendly `.hopealook` file.
    public static func write(_ manifest: LookManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(manifest)
        data.append(0x0A)
        return data
    }
}
