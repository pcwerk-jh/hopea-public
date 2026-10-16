import Foundation
import Testing
@testable import HopeaLookKit

/// A tiny identity `.cube` of the given size.
func identityCube(size: Int) -> String {
    var text = "TITLE \"Identity\"\nLUT_3D_SIZE \(size)\n"
    let n = Double(size - 1)
    for b in 0..<size {
        for g in 0..<size {
            for r in 0..<size {
                text += "\(Double(r) / n) \(Double(g) / n) \(Double(b) / n)\n"
            }
        }
    }
    return text
}

func manifest(id: String = "@jane/soft-fog", handle: String = "jane", dimension: Int = 17,
              cube: String? = nil) -> LookManifest {
    LookManifest(id: id, version: "1.0.0", name: "Soft Fog", description: "Test look.", tags: ["cool", "soft"],
                 license: "CC-BY-4.0", author: .init(name: "Jane Doe", handle: handle, url: "https://example.com"),
                 lut: .init(dimension: dimension, cube: cube ?? identityCube(size: dimension)),
                 grain: 0.3, vignette: 0.2, halation: 0.1, monochrome: false)
}

@Suite("Look packages (.hopealook)")
struct LookPackageTests {
    @Test("A valid package round-trips through write and read")
    func roundTrip() throws {
        let original = manifest()
        let data = try LookPackage.write(original)
        let loaded = try LookPackage.read(data)
        #expect(loaded.manifest == original)
        #expect(loaded.look.id == "@jane/soft-fog")
        #expect(loaded.cube.dimension == 17)
        #expect(loaded.cube.data.count == 17 * 17 * 17 * 4 * MemoryLayout<Float>.size)
    }

    @Test("Written files are stable (sorted keys) for clean diffs")
    func stableOutput() throws {
        #expect(try LookPackage.write(manifest()) == LookPackage.write(manifest()))
    }

    @Test("The seeded repository looks are valid")
    func seededLooks() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for slug in ["hopea", "americana", "harbor", "silver"] {
            let loaded = try LookPackage.read(contentsOf: root.appending(path: "looks/hopea/\(slug)/look.hopealook"))
            #expect(loaded.manifest.id == "@hopea/\(slug)")
            #expect(loaded.manifest.license == "CC-BY-4.0")
            #expect(loaded.cube.dimension == 33)
        }
    }

    @Test("Non-JSON and truncated files are rejected")
    func notJSON() throws {
        #expect(throws: LookPackage.ReadError.self) { try LookPackage.read(Data("hello".utf8)) }
        let data = try LookPackage.write(manifest())
        #expect(throws: LookPackage.ReadError.self) { try LookPackage.read(data.prefix(200)) }
    }

    @Test("Oversized files are rejected before parsing")
    func tooLarge() {
        let data = Data(count: LookValidator.maxPackageBytes + 1)
        #expect(throws: LookPackage.ReadError.tooLarge(bytes: data.count)) { try LookPackage.read(data) }
    }

    @Test("A LUT whose size disagrees with lut.dimension is rejected")
    func dimensionMismatch() throws {
        let m = manifest(dimension: 17, cube: identityCube(size: 2))
        do {
            _ = try LookPackage.read(try LookPackage.write(m))
            Issue.record("expected a failure")
        } catch let error as LookPackage.ReadError {
            guard case .badLUT = error else { Issue.record("wrong error \(error)"); return }
        }
    }

    @Test("NaN or infinite LUT values are rejected")
    func nonFiniteLUT() throws {
        let cube = identityCube(size: 17).replacingOccurrences(of: "\n0.0 0.0 0.0\n", with: "\nnan 0.0 0.0\n")
        #expect(throws: LookPackage.ReadError.self) {
            try LookPackage.read(try LookPackage.write(manifest(cube: cube)))
        }
    }
}

@Suite("Validation rules")
struct LookValidatorTests {
    func errors(_ edit: (inout LookManifest) -> Void) -> [String] {
        var m = manifest()
        edit(&m)
        return LookValidator.validate(m).map(\.field)
    }

    @Test("A good manifest has no errors")
    func valid() { #expect(errors { _ in }.isEmpty) }

    @Test("ids must be @handle/slug and match the author")
    func ids() {
        #expect(errors { $0.id = "jane/soft-fog" } == ["id"])
        #expect(errors { $0.id = "@Jane/Soft Fog" } == ["id"])
        #expect(errors { $0.id = "@bob/soft-fog" } == ["id"])
        #expect(errors { $0.id = "@jane/-x" } == ["id"])
    }

    @Test("Versions, licences, dimensions and colour space are checked")
    func fields() {
        #expect(errors { $0.version = "1.0" } == ["version"])
        #expect(errors { $0.license = "MIT" } == ["license"])
        #expect(errors { $0.lut.dimension = 32 } == ["lut.dimension"])
        #expect(errors { $0.lut.colorSpace = "sRGB" } == ["lut.colorSpace"])
        #expect(errors { $0.format = 2 } == ["format"])
    }

    @Test("Parameters must be finite and within 0…1")
    func parameters() {
        #expect(errors { $0.grain = 1.5 } == ["grain"])
        #expect(errors { $0.vignette = -0.1 } == ["vignette"])
        #expect(errors { $0.halation = .nan } == ["halation"])
    }

    @Test("Strings are bounded and URLs must be https")
    func strings() {
        #expect(errors { $0.name = "" } == ["name"])
        #expect(errors { $0.name = String(repeating: "a", count: 41) } == ["name"])
        #expect(errors { $0.description = String(repeating: "a", count: 501) } == ["description"])
        #expect(errors { $0.tags = Array(repeating: "x", count: 9) } == ["tags"])
        #expect(errors { $0.tags = ["Not OK"] } == ["tags"])
        #expect(errors { $0.author.url = "http://example.com" } == ["author.url"])
        #expect(errors { $0.author.url = "javascript:alert(1)" } == ["author.url"])
        #expect(errors { $0.remixOf = "@hopea/harbor" } == ["remixOf"])
        #expect(errors { $0.remixOf = "@hopea/harbor@0.9.0" }.isEmpty)
    }
}

@Suite(".cube parser")
struct CubeParserTests {
    @Test("Parses comments, keywords, domains and CRLF")
    func parses() throws {
        let text = "# c\r\n" + identityCube(size: 2).replacingOccurrences(of: "\n", with: "\r\n")
            .replacingOccurrences(of: "LUT_3D_SIZE 2\r\n", with: "LUT_3D_SIZE 2\r\nDOMAIN_MIN 0 0 0\r\nDOMAIN_MAX 1 1 1\r\n")
        let cube = try CubeParser.parse(text)
        let floats = cube.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        #expect(cube.dimension == 2)
        #expect(Array(floats[4..<8]) == [1, 0, 0, 1])
    }

    @Test("Rejects malformed input")
    func rejects() {
        #expect(throws: CubeParser.ParseError.missingSize) { try CubeParser.parse("0 0 0\n") }
        #expect(throws: CubeParser.ParseError.unsupported1D) { try CubeParser.parse("LUT_1D_SIZE 16\n") }
        #expect(throws: CubeParser.ParseError.unsupportedDomain) { try CubeParser.parse("LUT_3D_SIZE 2\nDOMAIN_MAX 2 2 2\n") }
        #expect(throws: CubeParser.ParseError.malformedLine(2)) { try CubeParser.parse("LUT_3D_SIZE 2\n0 0\n") }
        #expect(throws: CubeParser.ParseError.wrongEntryCount(expected: 8, found: 1)) { try CubeParser.parse("LUT_3D_SIZE 2\n0 0 0\n") }
        #expect(throws: CubeParser.ParseError.unsupportedSize(200)) { try CubeParser.parse("LUT_3D_SIZE 200\n") }
    }
}
