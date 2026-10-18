import Foundation

/// An immutable set of looks and their LUTs, ready for `LookPipeline`.
public final class LookLibrary: Sendable {
    public let looks: [Look]
    private let cubes: [String: LookCube]

    public init(looks: [Look], cubes: [String: LookCube]) {
        self.looks = looks
        self.cubes = cubes
    }

    /// Builds a library from validated packages, keeping the first look for any duplicate id.
    public convenience init(_ loaded: [LoadedLook]) {
        var looks: [Look] = []
        var cubes: [String: LookCube] = [:]
        for item in loaded where cubes[item.look.id] == nil {
            looks.append(item.look)
            cubes[item.look.id] = item.cube
        }
        self.init(looks: looks, cubes: cubes)
    }

    /// Builds a library from validated packages with Natural (no look) first.
    public convenience init(_ loaded: [LoadedLook], includingNatural: Bool) {
        let library = LookLibrary(loaded)
        self.init(looks: (includingNatural ? [Look.natural] : []) + library.looks.filter { !$0.isNatural },
                  cubes: library.cubes)
    }

    public func cube(for look: Look) -> LookCube? { cubes[look.id] }

    public func look(withID id: String) -> Look? { looks.first { $0.id == id } }

    public var defaultLook: Look? { looks.first }
}

