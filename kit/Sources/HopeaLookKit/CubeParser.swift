import Foundation

/// Parser for Adobe/Resolve `.cube` 3D LUT files.
///
/// Byte-level with `strtof`: a 64³ LUT is ~260k lines, and apps parse LUTs at launch.
public enum CubeParser {
    public enum ParseError: Error, Equatable, Sendable {
        case missingSize
        case unsupported1D
        case unsupportedSize(Int)
        case unsupportedDomain
        case malformedLine(Int)
        case wrongEntryCount(expected: Int, found: Int)
        case nonFiniteValue(Int)
    }

    public static func parse(_ text: String) throws -> LookCube {
        var bytes = Array(text.utf8CString) // NUL-terminated, so strtof can never run off the end
        return try bytes.withUnsafeMutableBufferPointer { buffer in
            try parse(base: buffer.baseAddress!, count: buffer.count - 1)
        }
    }

    private static func parse(base: UnsafeMutablePointer<CChar>, count: Int) throws -> LookCube {
        var size: Int?
        var values: [Float] = []
        var lineStart = 0
        var lineNumber = 0

        while lineStart < count {
            var lineEnd = lineStart
            while lineEnd < count, base[lineEnd] != 0x0A, base[lineEnd] != 0x0D { lineEnd += 1 }
            lineNumber += 1
            defer { lineStart = lineEnd + 1 }

            var i = lineStart
            while i < lineEnd, base[i] == 0x20 || base[i] == 0x09 { i += 1 }
            if i == lineEnd || base[i] == 0x23 /* # */ { continue }

            let first = UInt8(bitPattern: base[i])
            let isKeyword = (first >= 0x41 && first <= 0x5A) || (first >= 0x61 && first <= 0x7A)
            if isKeyword {
                let raw = UnsafeRawBufferPointer(start: base + i, count: lineEnd - i)
                let parts = String(decoding: raw, as: UTF8.self).split(whereSeparator: \.isWhitespace)
                switch parts.first {
                case "LUT_3D_SIZE":
                    guard parts.count == 2, let n = Int(parts[1]) else { throw ParseError.malformedLine(lineNumber) }
                    guard (2...128).contains(n) else { throw ParseError.unsupportedSize(n) }
                    size = n
                    values.reserveCapacity(n * n * n * 4)
                case "LUT_1D_SIZE":
                    throw ParseError.unsupported1D
                case "DOMAIN_MIN":
                    guard parts.dropFirst().compactMap({ Float($0) }) == [0, 0, 0] else { throw ParseError.unsupportedDomain }
                case "DOMAIN_MAX":
                    guard parts.dropFirst().compactMap({ Float($0) }) == [1, 1, 1] else { throw ParseError.unsupportedDomain }
                default:
                    continue // TITLE, LUT_3D_INPUT_RANGE and vendor keywords
                }
                continue
            }

            guard size != nil else { throw ParseError.missingSize }
            var cursor = base + i
            let limit = base + lineEnd
            for _ in 0..<3 {
                var end: UnsafeMutablePointer<CChar>?
                let value = strtof(cursor, &end)
                guard let end, end != cursor, end <= limit else { throw ParseError.malformedLine(lineNumber) }
                // strtof accepts "nan" and "inf"; a LUT must never contain them.
                guard value.isFinite else { throw ParseError.nonFiniteValue(lineNumber) }
                values.append(value)
                cursor = end
            }
            while cursor < limit, cursor.pointee == 0x20 || cursor.pointee == 0x09 { cursor += 1 }
            guard cursor == limit else { throw ParseError.malformedLine(lineNumber) }
            values.append(1)
        }

        guard let size else { throw ParseError.missingSize }
        let expected = size * size * size
        guard values.count == expected * 4 else {
            throw ParseError.wrongEntryCount(expected: expected, found: values.count / 4)
        }
        // .cube order (red fastest) matches CIColorCube's expected layout.
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        return LookCube(dimension: size, data: data)
    }
}
