import CoreImage
import CryptoKit
import Foundation
import HopeaLookKit
import ImageIO
import UniformTypeIdentifiers

// hopea-look — tools for Hopea look packages. Run `hopea-look help`.

let usage = """
hopea-look — tools for Hopea look packages (.hopealook)

  pack            --cube FILE --id @handle/slug --name NAME --author-name NAME
                  [--author-url URL] [--version 1.0.0] [--license CC-BY-4.0|CC0-1.0]
                  [--description TEXT] [--tags a,b] [--grain 0.3] [--vignette 0.2]
                  [--halation 0] [--monochrome] [--remix-of @h/slug@1.0.0]
                  [--min-app-version 1.1] --out FILE
  bake            RECIPE.json --out FILE  turn a look recipe into a .hopealook
  bake-all        DIR [--check]           bake every recipe.json under DIR next to it;
                                          --check fails if a committed look is out of date
  validate        PATH...                 files or folders; checks folder names match ids
  render-previews FILE --reference DIR --out DIR [--max-side 1200]
  build-catalog   --looks DIR --reference DIR --site DIR --out DIR --base-url URL
  intake          --issue-body FILE --looks DIR      (used by the submission workflow)
"""

struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Minimal `--key value` / `--flag` / positional argument parsing (no dependencies).
struct Arguments {
    var options: [String: String] = [:]
    var flags: Set<String> = []
    var positional: [String] = []

    init(_ args: ArraySlice<String>, flagNames: Set<String> = []) {
        var iterator = args.makeIterator()
        while let arg = iterator.next() {
            if arg.hasPrefix("--") {
                let key = String(arg.dropFirst(2))
                if flagNames.contains(key) { flags.insert(key) } else { options[key] = iterator.next() ?? "" }
            } else {
                positional.append(arg)
            }
        }
    }

    func required(_ key: String) throws -> String {
        guard let value = options[key], !value.isEmpty else { throw CLIError("missing --\(key)") }
        return value
    }

    func double(_ key: String, default value: Double) throws -> Double {
        guard let raw = options[key] else { return value }
        guard let parsed = Double(raw) else { throw CLIError("--\(key) must be a number") }
        return parsed
    }
}


// MARK: - Commands

func pack(_ args: Arguments) throws {
    let cubeURL = URL(filePath: try args.required("cube"))
    let cubeText = try String(contentsOf: cubeURL, encoding: .utf8)
    let cube = try CubeParser.parse(cubeText)
    let id = try args.required("id")
    let handle = id.dropFirst().split(separator: "/").first.map(String.init) ?? ""
    let manifest = LookManifest(
        id: id,
        version: args.options["version"] ?? "1.0.0",
        name: try args.required("name"),
        description: args.options["description"],
        tags: args.options["tags"].map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() } } ?? [],
        license: args.options["license"] ?? "CC-BY-4.0",
        author: .init(name: try args.required("author-name"), handle: handle, url: args.options["author-url"]),
        remixOf: args.options["remix-of"],
        minAppVersion: args.options["min-app-version"],
        lut: .init(dimension: cube.dimension, cube: cubeText),
        grain: try args.double("grain", default: 0),
        vignette: try args.double("vignette", default: 0),
        halation: try args.double("halation", default: 0),
        monochrome: args.flags.contains("monochrome"))
    let data = try LookPackage.write(manifest)
    _ = try LookPackage.read(data) // validate before writing anything
    let out = URL(filePath: try args.required("out"))
    try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: out, options: .atomic)
    print("packed \(manifest.id) \(manifest.version) → \(out.path)")
}

/// Every `.hopealook` under the given paths.
func lookFiles(in paths: [String]) -> [URL] {
    paths.flatMap { path -> [URL] in
        let url = URL(filePath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return [url] }
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
        return (enumerator?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == LookPackage.fileExtension }
    }
    .sorted { $0.path < $1.path }
}

func validate(_ args: Arguments) -> Int32 {
    let files = lookFiles(in: args.positional.isEmpty ? ["looks"] : args.positional)
    guard !files.isEmpty else {
        print("no .hopealook files found")
        return 1
    }
    var failures = 0
    var seenIDs: [String: URL] = [:]
    for file in files {
        do {
            let loaded = try LookPackage.read(contentsOf: file)
            var problems: [String] = []
            // Repository convention: looks/<handle>/<slug>/look.hopealook
            if let parts = loaded.manifest.idParts {
                let slugDir = file.deletingLastPathComponent()
                let handleDir = slugDir.deletingLastPathComponent()
                if file.lastPathComponent != "look.hopealook" || slugDir.lastPathComponent != parts.slug
                    || handleDir.lastPathComponent != parts.handle {
                    problems.append("path must be looks/\(parts.handle)/\(parts.slug)/look.hopealook")
                }
            }
            if let other = seenIDs[loaded.manifest.id] {
                problems.append("duplicate id, also in \(other.path)")
            }
            seenIDs[loaded.manifest.id] = file
            if problems.isEmpty {
                print("✓ \(loaded.manifest.id) \(loaded.manifest.version)  \(file.path)")
            } else {
                failures += 1
                print("✗ \(file.path)\n  " + problems.joined(separator: "\n  "))
            }
        } catch {
            failures += 1
            print("✗ \(file.path)\n  " + String(describing: error).replacingOccurrences(of: "\n", with: "\n  "))
        }
    }
    print(failures == 0 ? "\(files.count) look(s) valid" : "\(failures) of \(files.count) look(s) failed")
    return failures == 0 ? 0 : 1
}

func referenceImages(in directory: URL) -> [URL] {
    let extensions: Set<String> = ["jpg", "jpeg", "png", "heic"]
    return ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
        .filter { extensions.contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

/// Renders `loaded` on every reference photo. Fixed grain seed, so previews are reproducible.
func renderPreviews(_ loaded: LoadedLook, references: [URL], to directory: URL, maxSide: CGFloat) async throws -> [String] {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let renderer = LookPreviewRenderer(pipeline: LookPipeline(library: LookLibrary([loaded])))
    var names: [String] = []
    for reference in references {
        guard let image = LookPreviewRenderer.loadImage(at: reference, maxSide: maxSide),
              let rendered = await renderer.render(image, look: loaded.look, maxSide: maxSide, quality: .full, grainSeed: 1234)
        else { throw CLIError("could not render \(reference.lastPathComponent)") }
        let name = reference.deletingPathExtension().lastPathComponent + ".jpg"
        let out = directory.appending(path: name)
        guard let destination = CGImageDestinationCreateWithURL(out as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CLIError("could not write \(out.path)")
        }
        CGImageDestinationAddImage(destination, rendered, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CLIError("could not write \(out.path)") }
        names.append(name)
    }
    return names
}

func renderPreviewsCommand(_ args: Arguments) async throws {
    guard let path = args.positional.first else { throw CLIError("render-previews needs a .hopealook file") }
    let loaded = try LookPackage.read(contentsOf: URL(filePath: path))
    let references = referenceImages(in: URL(filePath: try args.required("reference")))
    let out = URL(filePath: try args.required("out"))
    let names = try await renderPreviews(loaded, references: references, to: out,
                                         maxSide: CGFloat(try args.double("max-side", default: 1200)))
    print("rendered \(names.count) preview(s) for \(loaded.manifest.id) → \(out.path)")
}

struct CatalogEntry: Encodable {
    let id: String
    let version: String
    let name: String
    let description: String?
    let tags: [String]
    let license: String
    let author: LookManifest.Author
    let remixOf: String?
    let monochrome: Bool
    let featured: Bool
    let package: String
    let sha256: String
    let size: Int
    let previews: [String]
}

struct Catalog: Encodable {
    let format = 1
    let movedTo: String?
    let generated: String
    let looks: [CatalogEntry]
}

func buildCatalog(_ args: Arguments) async throws {
    let looksDir = URL(filePath: try args.required("looks"))
    let out = URL(filePath: try args.required("out"))
    let site = URL(filePath: try args.required("site"))
    let references = referenceImages(in: URL(filePath: try args.required("reference")))
    let baseURL = try args.required("base-url").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    // Featured looks come first, in the order listed in looks/featured.txt.
    let featuredOrder = ((try? String(contentsOf: looksDir.appending(path: "featured.txt"), encoding: .utf8)) ?? "")
        .split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    let featured = Set(featuredOrder)

    try? FileManager.default.removeItem(at: out)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    // Static site template first; generated files go alongside.
    for item in try FileManager.default.contentsOfDirectory(at: site, includingPropertiesForKeys: nil) {
        try FileManager.default.copyItem(at: item, to: out.appending(path: item.lastPathComponent))
    }

    var entries: [CatalogEntry] = []
    for file in lookFiles(in: [looksDir.path]) {
        let data = try Data(contentsOf: file)
        let loaded = try LookPackage.read(data)
        guard let parts = loaded.manifest.idParts else { continue }
        let relative = "looks/\(parts.handle)/\(parts.slug)"
        let lookOut = out.appending(path: relative)
        try FileManager.default.createDirectory(at: lookOut, withIntermediateDirectories: true)
        let packageName = "\(parts.slug)-\(loaded.manifest.version).hopealook"
        try data.write(to: lookOut.appending(path: packageName))
        let previews = try await renderPreviews(loaded, references: references,
                                                to: lookOut.appending(path: "previews"), maxSide: 900)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let m = loaded.manifest
        entries.append(CatalogEntry(id: m.id, version: m.version, name: m.name, description: m.description,
                                    tags: m.tags, license: m.license, author: m.author, remixOf: m.remixOf,
                                    monochrome: m.monochrome, featured: featured.contains(m.id),
                                    package: "\(baseURL)/\(relative)/\(packageName)",
                                    sha256: digest, size: data.count,
                                    previews: previews.map { "\(baseURL)/\(relative)/previews/\($0)" }))
        print("✓ \(m.id) \(m.version)")
    }
    func rank(_ entry: CatalogEntry) -> Int { featuredOrder.firstIndex(of: entry.id) ?? Int.max }
    entries.sort { (rank($0), $0.id) < (rank($1), $1.id) }

    let formatter = ISO8601DateFormatter()
    let catalog = Catalog(movedTo: args.options["moved-to"], generated: formatter.string(from: Date()), looks: entries)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(catalog).write(to: out.appending(path: "catalog.json"))
    print("catalog: \(entries.count) look(s) → \(out.appending(path: "catalog.json").path)")
}

// MARK: - Recipes

func bakeRecipe(at url: URL) throws -> Data {
    let recipe = try JSONDecoder().decode(LookRecipe.self, from: Data(contentsOf: url))
    let data = try LookPackage.write(try recipe.bake())
    _ = try LookPackage.read(data)
    return data
}

func bake(_ args: Arguments) throws {
    guard let path = args.positional.first else { throw CLIError("bake needs a recipe.json") }
    let data = try bakeRecipe(at: URL(filePath: path))
    let out = URL(filePath: try args.required("out"))
    try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: out, options: .atomic)
    print("baked \(path) → \(out.path)")
}

func bakeAll(_ args: Arguments) -> Int32 {
    let root = URL(filePath: args.positional.first ?? "looks")
    let check = args.flags.contains("check")
    let recipes = ((FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? [])
        .filter { $0.lastPathComponent == "recipe.json" }
        .sorted { $0.path < $1.path }
    var failures = 0
    for recipe in recipes {
        let target = recipe.deletingLastPathComponent().appending(path: "look.hopealook")
        do {
            let data = try bakeRecipe(at: recipe)
            if check {
                if (try? Data(contentsOf: target)) == data {
                    print("✓ \(target.path)")
                } else {
                    failures += 1
                    print("✗ \(target.path) does not match its recipe — run hopea-look bake-all")
                }
            } else {
                try data.write(to: target, options: .atomic)
                print("baked \(target.path)")
            }
        } catch {
            failures += 1
            print("✗ \(recipe.path)\n  \(error)")
        }
    }
    print("\(recipes.count) recipe(s), \(failures) problem(s)")
    return failures == 0 ? 0 : 1
}

// MARK: - Issue-form intake

/// Fields from a GitHub issue form body ("### Label\n\nvalue" sections).
func issueFields(_ body: String) -> [String: String] {
    var fields: [String: String] = [:]
    var current: String?
    var lines: [String] = []
    func flush() {
        if let current {
            let value = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            fields[current] = value == "_No response_" ? "" : value
        }
        lines = []
    }
    for line in body.components(separatedBy: .newlines) {
        if line.hasPrefix("### ") {
            flush()
            current = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        } else {
            lines.append(line)
        }
    }
    flush()
    return fields
}

/// Downloads an attached .cube. Only GitHub's own attachment hosts are allowed.
func downloadAttachment(from text: String) async throws -> String {
    let allowedHosts: Set<String> = ["github.com", "objects.githubusercontent.com", "user-images.githubusercontent.com"]
    let pattern = /https:\/\/[^\s\)\]"'<>]+/
    guard let match = text.firstMatch(of: pattern), let url = URL(string: String(match.output)),
          let host = url.host(), allowedHosts.contains(host) else {
        throw CLIError("attach your .cube file by dragging it into the \"LUT file\" field")
    }
    let (data, response) = try await URLSession.shared.data(from: url)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CLIError("could not download the attached file") }
    guard data.count <= LookValidator.maxPackageBytes else { throw CLIError("the .cube file is larger than 12 MB") }
    guard let text = String(data: data, encoding: .utf8) else { throw CLIError("the attached file is not a text .cube file") }
    return text
}

func intake(_ args: Arguments) async throws {
    let body = try String(contentsOf: URL(filePath: try args.required("issue-body")), encoding: .utf8)
    let f = issueFields(body)
    func field(_ label: String) -> String { f[label] ?? "" }

    let handle = field("Creator handle").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
    let name = field("Look name")
    let slug = name.lowercased()
        .map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        .split(separator: "-").joined(separator: "-")
    let cubeText = try await downloadAttachment(from: field("LUT file (.cube)"))
    let cube = try CubeParser.parse(cubeText)
    func number(_ label: String) throws -> Double {
        let raw = field(label)
        if raw.isEmpty { return 0 }
        guard let value = Double(raw) else { throw CLIError("\(label) must be a number between 0 and 1") }
        return value
    }
    let manifest = LookManifest(
        id: "@\(handle)/\(slug)",
        version: "1.0.0",
        name: name,
        description: field("Description").isEmpty ? nil : field("Description"),
        tags: field("Tags").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty },
        license: field("Licence").isEmpty ? "CC-BY-4.0" : field("Licence"),
        author: .init(name: field("Your name"), handle: handle, url: field("Link (optional)").isEmpty ? nil : field("Link (optional)")),
        remixOf: field("Remix of (optional)").isEmpty ? nil : field("Remix of (optional)"),
        lut: .init(dimension: cube.dimension, cube: cubeText),
        grain: try number("Grain (0–1)"),
        vignette: try number("Vignette (0–1)"),
        halation: try number("Halation (0–1)"),
        monochrome: field("Monochrome").contains("[X]") || field("Monochrome").contains("[x]"))
    let data = try LookPackage.write(manifest)
    _ = try LookPackage.read(data)
    let out = URL(filePath: try args.required("looks")).appending(path: "\(handle)/\(slug)/look.hopealook")
    guard !FileManager.default.fileExists(atPath: out.path) else {
        throw CLIError("\(manifest.id) already exists — choose another look name, or open a pull request to update it")
    }
    try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: out, options: .atomic)
    print(manifest.id)
}

// MARK: - Entry point

let arguments = CommandLine.arguments
let command = arguments.count > 1 ? arguments[1] : "help"
let rest = arguments.dropFirst(2)
do {
    switch command {
    case "pack": try pack(Arguments(rest, flagNames: ["monochrome"]))
    case "validate": exit(validate(Arguments(rest)))
    case "bake": try bake(Arguments(rest))
    case "bake-all": exit(bakeAll(Arguments(rest, flagNames: ["check"])))
    case "render-previews": try await renderPreviewsCommand(Arguments(rest))
    case "build-catalog": try await buildCatalog(Arguments(rest))
    case "intake": try await intake(Arguments(rest))
    default: print(usage)
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
