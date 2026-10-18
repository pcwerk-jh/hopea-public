import Foundation
import Testing
@testable import HopeaLookKit

@Suite("Look recipes")
struct LookRecipeTests {
    func recipe(_ edit: (inout LookRecipe) -> Void = { _ in }) -> LookRecipe {
        var r = LookRecipe(recipe: 1, id: "@test/look", version: "1.0.0", name: "Test", description: nil, tags: [],
                           license: "CC0-1.0", author: .init(name: "Test", handle: "test"), remixOf: nil,
                           lutDimension: 17, controls: .init(), colors: nil, splitTone: nil, monochrome: nil,
                           channelGain: nil)
        edit(&r)
        return r
    }

    let samples: [RGB] = [RGB(0.1, 0.1, 0.1), RGB(0.5, 0.5, 0.5), RGB(0.9, 0.9, 0.9),
                          RGB(0.8, 0.3, 0.2), RGB(0.2, 0.6, 0.3), RGB(0.2, 0.3, 0.8)]

    @Test("A neutral recipe is the identity")
    func neutral() {
        let r = recipe()
        for c in samples {
            let out = r.apply(c)
            #expect(abs(out.r - c.r) < 1e-6 && abs(out.g - c.g) < 1e-6 && abs(out.b - c.b) < 1e-6)
        }
    }

    @Test("Controls move colour in the expected direction")
    func directions() {
        let grey = RGB(0.5, 0.5, 0.5)
        #expect(recipe { $0.controls.exposure = 1 }.apply(grey).g > 0.6)
        let warm = recipe { $0.controls.warmth = 50 }.apply(grey)
        #expect(warm.r > warm.b)
        let magenta = recipe { $0.controls.tint = 50 }.apply(grey)
        #expect(magenta.g < magenta.r)
        #expect(recipe { $0.controls.fade = 100 }.apply(RGB(0, 0, 0)).g > 0.1)
        #expect(recipe { $0.controls.contrast = 100 }.apply(RGB(0.3, 0.3, 0.3)).g < 0.3)
        #expect(recipe { $0.controls.contrast = -100 }.apply(RGB(0.1, 0.1, 0.1)).g > 0.1)
        let red = RGB(0.8, 0.3, 0.2)
        let desaturated = recipe { $0.controls.saturation = -100 }.apply(red)
        #expect(abs(desaturated.r - desaturated.b) < 1e-6)
    }

    @Test("Colour bands only touch their hue, and leave greys alone")
    func bands() {
        let r = recipe { $0.colors = [.init(hue: .blue, saturation: -100)] }
        let blue = r.apply(RGB(0.2, 0.3, 0.8))
        #expect(blue.b - blue.r < 0.3)
        let red = RGB(0.8, 0.3, 0.2)
        #expect(r.apply(red) == red)
        #expect(r.apply(RGB(0.5, 0.5, 0.5)) == RGB(0.5, 0.5, 0.5))
    }

    @Test("Monochrome is neutral unless toned")
    func monochrome() throws {
        let plain = recipe { $0.monochrome = .init(mix: .init(red: 0.3, green: 0.59, blue: 0.11)) }
        for c in samples {
            let out = plain.apply(c)
            #expect(abs(out.r - out.g) < 1e-9 && abs(out.g - out.b) < 1e-9)
        }
        #expect(try plain.bake().monochrome)
        let toned = recipe {
            $0.monochrome = .init(mix: .init(red: 0.3, green: 0.59, blue: 0.11),
                                  shadowTone: "#191B1D", highlightTone: "#F6EBDD", toning: 0.5)
        }
        let light = toned.apply(RGB(0.9, 0.9, 0.9))
        #expect(light.r > light.b)
        #expect(try toned.bake().monochrome == false)
    }

    @Test("Baking is deterministic and produces a valid package")
    func bake() throws {
        let r = recipe { $0.controls.contrast = 20; $0.controls.grain = 40; $0.controls.vignette = 10 }
        let a = try LookPackage.write(try r.bake())
        let b = try LookPackage.write(try r.bake())
        #expect(a == b)
        let loaded = try LookPackage.read(a)
        #expect(loaded.cube.dimension == 17)
        #expect(loaded.manifest.grain == 0.4)
        #expect(loaded.manifest.vignette == 0.1)
    }

    @Test("Out-of-range controls are rejected")
    func ranges() {
        #expect(throws: LookRecipe.BakeError.self) { try recipe { $0.controls.contrast = 150 }.bake() }
        #expect(throws: LookRecipe.BakeError.self) { try recipe { $0.controls.grain = -1 }.bake() }
        #expect(throws: LookRecipe.BakeError.self) { try recipe { $0.controls.exposure = 5 }.bake() }
        #expect(throws: LookRecipe.BakeError.self) { try recipe { $0.monochrome = .init(mix: .init(red: 0, green: 0, blue: 0)) }.bake() }
        #expect(throws: LookRecipe.BakeError.self) { try recipe { $0.recipe = 2 }.bake() }
    }

    @Test("The table for Core Image matches the saved .cube text")
    func cubeMatchesText() throws {
        let r = recipe { $0.controls.contrast = 30; $0.controls.warmth = -20; $0.colors = [.init(hue: .blue, saturation: -40)] }
        let direct = r.cube(dimension: 17)
        let parsed = try CubeParser.parse(r.cubeText(dimension: 17))
        #expect(direct.dimension == parsed.dimension && direct.data == parsed.data)
    }

    @Test("A recipe on a base table: neutral keeps the base, an identity base keeps the recipe")
    func layeredOnBase() throws {
        let warm = recipe { $0.controls.warmth = 60; $0.controls.fade = 20 }
        let base = warm.cube(dimension: 17)
        let neutralOnBase = recipe().cube(dimension: 17, base: base)
        #expect(neutralOnBase.data == base.data)
        let identity = recipe().cube(dimension: 17)
        let warmOnIdentity = warm.cube(dimension: 17, base: identity)
        #expect(warmOnIdentity.data == base.data)
        // Layered: the recipe moves the base's output further.
        let cooler = recipe { $0.controls.warmth = -60 }
        let layered = cooler.cube(dimension: 17, base: base)
        #expect(layered.data != base.data)
        let manifest = try cooler.bake(base: base, baseIsMonochrome: true)
        #expect(manifest.monochrome)
        #expect(try CubeParser.parse(manifest.lut.cube).data == layered.data)
    }

    @Test("Neutral recipes are recognised")
    func neutralRecipe() {
        #expect(recipe().isNeutral)
        #expect(!recipe { $0.controls.grain = 10 }.isNeutral)
        #expect(!recipe { $0.colors = [.init(hue: .red, luminance: 5)] }.isNeutral)
        #expect(recipe { $0.colors = [.init(hue: .red)] }.isNeutral)
    }

    @Test("Every committed recipe bakes to its committed look")
    func committedRecipes() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let enumerator = FileManager.default.enumerator(at: root.appending(path: "looks"), includingPropertiesForKeys: nil)
        let recipes = (enumerator?.allObjects as? [URL] ?? []).filter { $0.lastPathComponent == "recipe.json" }
        #expect(recipes.count >= 24)
        for url in recipes {
            let recipe = try JSONDecoder().decode(LookRecipe.self, from: Data(contentsOf: url))
            let baked = try LookPackage.write(try recipe.bake())
            let committed = try Data(contentsOf: url.deletingLastPathComponent().appending(path: "look.hopealook"))
            #expect(baked == committed, "\(recipe.id) is out of date — run hopea-look bake-all")
        }
    }
}
