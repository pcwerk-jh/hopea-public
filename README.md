# Hopea — public

The public home of the [Hopea](https://pcwerk-jh.github.io/hopea-public/) camera app: community
**looks**, the **website**, and the open **look kit** that renders them.

- **Browse looks:** https://pcwerk-jh.github.io/hopea-public/
- **Share a look:** [submit one](https://github.com/pcwerk-jh/hopea-public/issues/new?template=submit-look.yml)
  — no git needed — or see [CONTRIBUTING.md](CONTRIBUTING.md)
- **Look file format:** [FORMAT.md](FORMAT.md)

## What's here

| Path | Contents |
|---|---|
| `looks/` | Every published look: `looks/<handle>/<look>/look.hopealook` (+ `recipe.json` for recipe-made looks) |
| `site/` | The website template (static; built and published to GitHub Pages) |
| `kit/` | **HopeaLookKit** (format, validation, rendering) and the `hopea-look` command-line tool |
| `reference/` | Photos used to render look previews |
| `tools/` | Generator for the placeholder LUTs of the default looks |
| `Package.swift` | Swift package manifest (at the root so apps can depend on this repository) |

## A look is data, not code

A look is a single `.hopealook` file: a 3D LUT plus a few settings (grain, vignette, halation) and
credits. There is no code in a look, so installing one is safe. The Hopea app and this site render
looks with the same engine (`kit/Sources/HopeaLookKit`), so previews here match the app.

## Tools

Requires Swift 6 on macOS 15 or later.

```sh
swift build
swift test
swift run hopea-look help

# Package a LUT you made in Resolve, Lightroom, Photoshop…
swift run hopea-look pack --cube my-look.cube --id @jane/harbor-fog --name "Harbor Fog" \
  --author-name "Jane Doe" --grain 0.3 --vignette 0.2 --out looks/jane/harbor-fog/look.hopealook

# Or describe a look with photographic controls and bake it (see FORMAT.md, "Recipes")
swift run hopea-look bake looks/jane/harbor-fog/recipe.json --out looks/jane/harbor-fog/look.hopealook
swift run hopea-look bake-all looks          # re-bake every recipe.json

swift run hopea-look validate looks
swift run hopea-look render-previews looks/jane/harbor-fog/look.hopealook --reference reference --out previews

# Build the site exactly as GitHub Pages serves it
swift run hopea-look build-catalog --looks looks --reference reference --site site --out _site \
  --base-url https://pcwerk-jh.github.io/hopea-public
```

## Licences

- Code (`kit/`, `site/`, `tools/`, workflows): [MIT](LICENSE).
- Looks: each look's own licence, recorded in its file — CC BY 4.0 or CC0 1.0.
  The default `@hopea/*` looks are CC BY 4.0.
- Reference photos: see [reference/README.md](reference/README.md).
