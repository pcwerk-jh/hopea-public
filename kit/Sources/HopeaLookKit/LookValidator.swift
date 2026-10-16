import Foundation

/// One problem found in a look. `field` is the manifest key it relates to.
public struct LookValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    public let field: String
    public let message: String

    public init(_ field: String, _ message: String) {
        self.field = field
        self.message = message
    }

    public var description: String { "\(field): \(message)" }
}

/// The rules every look must pass before it is listed or installed (FORMAT.md, "Validation").
public enum LookValidator {
    public static let maxPackageBytes = 12 * 1024 * 1024
    public static let supportedDimensions: Set<Int> = [17, 33, 64]
    public static let acceptedLicenses: Set<String> = ["CC-BY-4.0", "CC0-1.0"]
    public static let maxNameLength = 40
    public static let maxDescriptionLength = 500
    public static let maxTags = 8
    public static let maxTagLength = 24

    private static let namePart = #"[a-z0-9](?:[a-z0-9-]{0,46}[a-z0-9])?"#
    private static let handlePart = #"[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?"#
    private static let semver = #"\d{1,4}\.\d{1,4}\.\d{1,4}"#

    /// Checks everything that can be checked without parsing the LUT.
    public static func validate(_ m: LookManifest) -> [LookValidationError] {
        var errors: [LookValidationError] = []
        func fail(_ field: String, _ message: String) { errors.append(LookValidationError(field, message)) }

        if m.format != LookManifest.currentFormat {
            fail("format", "unsupported format \(m.format); this tool reads format \(LookManifest.currentFormat)")
        }
        if !matches(m.id, "@\(handlePart)/\(namePart)") {
            fail("id", "must look like @handle/look-name (lowercase letters, digits and dashes)")
        } else if let parts = m.idParts, parts.handle != m.author.handle {
            fail("id", "namespace @\(parts.handle) must match author.handle \(m.author.handle)")
        }
        if !matches(m.version, semver) {
            fail("version", "must be MAJOR.MINOR.PATCH, e.g. 1.0.0")
        }
        let trimmedName = m.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty || m.name.count > maxNameLength {
            fail("name", "must be 1–\(maxNameLength) characters")
        }
        if let description = m.description, description.count > maxDescriptionLength {
            fail("description", "must be at most \(maxDescriptionLength) characters")
        }
        if m.tags.count > maxTags {
            fail("tags", "at most \(maxTags) tags")
        }
        for tag in m.tags where !matches(tag, "[a-z0-9-]{1,\(maxTagLength)}") {
            fail("tags", "\"\(tag)\" must be lowercase letters, digits or dashes, up to \(maxTagLength) characters")
        }
        if !acceptedLicenses.contains(m.license) {
            fail("license", "must be one of \(acceptedLicenses.sorted().joined(separator: ", "))")
        }
        if m.author.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || m.author.name.count > 60 {
            fail("author.name", "must be 1–60 characters")
        }
        if !matches(m.author.handle, handlePart) {
            fail("author.handle", "lowercase letters, digits and dashes, up to 32 characters")
        }
        if let url = m.author.url, !(url.hasPrefix("https://") && url.count <= 200 && URL(string: url) != nil) {
            fail("author.url", "must be an https:// URL")
        }
        if let remix = m.remixOf, !matches(remix, "@\(handlePart)/\(namePart)@\(semver)") {
            fail("remixOf", "must look like @handle/look-name@1.0.0")
        }
        if let minApp = m.minAppVersion, !matches(minApp, #"\d{1,4}(\.\d{1,4}){0,2}"#) {
            fail("minAppVersion", "must look like 1.1 or 1.1.0")
        }
        if !supportedDimensions.contains(m.lut.dimension) {
            fail("lut.dimension", "must be one of \(supportedDimensions.sorted().map(String.init).joined(separator: ", "))")
        }
        if m.lut.colorSpace != LookManifest.lutColorSpace {
            fail("lut.colorSpace", "must be \(LookManifest.lutColorSpace)")
        }
        for (field, value) in [("grain", m.grain), ("vignette", m.vignette), ("halation", m.halation)]
        where !(value.isFinite && (0...1).contains(value)) {
            fail(field, "must be between 0 and 1")
        }
        return errors
    }

    private static func matches(_ string: String, _ pattern: String) -> Bool {
        guard let regex = try? Regex("^(?:\(pattern))$") else { return false }
        return string.wholeMatch(of: regex) != nil
    }
}
