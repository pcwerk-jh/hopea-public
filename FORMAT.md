# The `.hopealook` format — version 1

A Hopea look is a single UTF-8 JSON file with the extension `.hopealook`
(uniform type identifier `com.pcwerk.hopea.look`). It contains **data only** — a 3D LUT and a few
numeric settings — never code.

## Example

```json
{
  "format": 1,
  "id": "@jane/harbor-fog",
  "version": "1.2.0",
  "name": "Harbor Fog",
  "description": "Cool, soft and foggy.",
  "tags": ["cool", "muted"],
  "license": "CC-BY-4.0",
  "author": { "name": "Jane Doe", "handle": "jane", "url": "https://example.com" },
  "remixOf": "@hopea/harbor@0.9.0",
  "minAppVersion": "1.1",
  "lut": { "dimension": 33, "colorSpace": "displayP3", "cube": "LUT_3D_SIZE 33\n0.0 0.0 0.0\n…" },
  "grain": 0.3,
  "vignette": 0.2,
  "halation": 0.0,
  "monochrome": false
}
```

## Fields

| Field | Required | Rules |
|---|---|---|
| `format` | yes | `1` |
| `id` | yes | `@handle/look-name`: lowercase letters, digits, dashes; handle must equal `author.handle` |
| `version` | yes | `MAJOR.MINOR.PATCH`. Bump it for every change; apps offer the update |
| `name` | yes | 1–40 characters |
| `description` | no | up to 500 characters |
| `tags` | no | up to 8, each lowercase letters/digits/dashes, up to 24 characters |
| `license` | yes | `CC-BY-4.0` or `CC0-1.0` |
| `author.name` | yes | 1–60 characters |
| `author.handle` | yes | lowercase letters, digits, dashes, up to 32 characters |
| `author.url` | no | `https://` only |
| `remixOf` | no | `@handle/look-name@1.0.0` of the look this one started from |
| `minAppVersion` | no | oldest Hopea version that can use it, e.g. `1.1` |
| `lut.dimension` | yes | `17`, `33` or `64`, and must match the `.cube` |
| `lut.colorSpace` | yes | `displayP3` |
| `lut.cube` | yes | the full text of a 3D `.cube` file (domain 0…1, finite values) |
| `grain`, `vignette`, `halation` | yes | `0`…`1` |
| `monochrome` | yes | `true` forces neutral (black-and-white) output |

A file may be at most **12 MB**. Apps and the hub reject anything that fails these rules.

## Rendering

Every app and tool must render looks the same way (`kit/Sources/HopeaLookKit/LookPipeline.swift`):

1. The input is converted to the working space (extended linear sRGB).
2. **LUT**, applied to gamma-encoded Display P3 values (the space LUTs are authored in).
3. **Monochrome** looks are made exactly neutral.
4. **Halation** (if > 0): highlights above a threshold are blurred, tinted red/orange and
   screen-blended.
5. **Vignette** (if > 0).
6. **Grain** (if > 0): zero-mean monochrome noise overlay-blended in gamma space, strongest in the
   midtones.

Sizes (blur radius, vignette radius, grain size) are fractions of the image, so a look renders
the same at any resolution. The constants are in `LookTuning.swift` and are part of the format.

## Making the LUT

Export a 3D LUT (`.cube`, 17/33/64 points) from DaVinci Resolve, Lightroom/Photoshop, Affinity,
etc. **Grade in Display P3 (gamma-encoded)** — the LUT receives Display P3 values from the camera.
Leave grain, vignette and halation out of the LUT; set them with the numeric fields instead.

## `catalog.json`

The site publishes an index the Hopea app reads (only when the user turns on Community Looks):

```json
{ "format": 1, "movedTo": null, "generated": "2026-10-15T12:00:00Z",
  "looks": [ { "id": "@jane/harbor-fog", "version": "1.2.0", "name": "Harbor Fog",
               "description": "…", "tags": ["cool"], "license": "CC-BY-4.0",
               "author": { "name": "Jane Doe", "handle": "jane" }, "remixOf": null,
               "monochrome": false, "featured": false,
               "package": "https://…/harbor-fog-1.2.0.hopealook", "sha256": "…", "size": 1007042,
               "previews": ["https://…/previews/sample_bronco.jpg"] } ] }
```

Apps verify each package's `sha256` and re-validate it before installing. If `movedTo` is set,
apps switch to that catalog URL.

## Recipes

Instead of a hand-made LUT, a look can be described with photographic controls in a
`recipe.json` next to its `look.hopealook`. `hopea-look bake` turns the recipe into the LUT and
settings; CI checks every committed look still matches its recipe (`bake-all --check`). The maths
is in `kit/Sources/HopeaLookKit/LookRecipe.swift` and is part of the recipe format (version 1).

```json
{
  "recipe": 1,
  "id": "@hopea/softportrait", "version": "0.9.0", "name": "Soft Portrait",
  "description": "…", "tags": ["portrait"], "license": "CC-BY-4.0",
  "author": { "name": "Hopea", "handle": "hopea" },
  "controls": { "contrast": -12, "saturation": -12, "warmth": 12, "highlights": -25,
                "shadows": 15, "grain": 16, "fade": 8 },
  "colors": [ { "hue": "green", "saturation": -10 } ],
  "splitTone": { "shadows": { "hue": 200, "amount": 20 } },
  "monochrome": { "mix": { "red": 0.3, "green": 0.59, "blue": 0.11 },
                  "shadowTone": "#191B1D", "highlightTone": "#F6EBDD", "toning": 0.12 },
  "channelGain": { "red": 1, "green": 0.8, "blue": 0.4 }
}
```

| Control | Range | Effect |
|---|---|---|
| `exposure` | −2…+2 EV | brightness, in linear light |
| `contrast` | −100…+100 | S-curve / flatten around mid-grey |
| `saturation` | −100…+100 | overall colour (−100 = none) |
| `warmth`, `tint` | −100…+100 | blue↔amber, green↔magenta (linear light) |
| `highlights`, `shadows` | −100…+100 | recover/brighten highlights; deepen/lift shadows |
| `fade` | 0…100 | lift blacks, soften whites |
| `grain`, `vignette`, `halation` | 0…100 | stored in the look as 0…1 |
| `colors[]` | per band: `saturation`, `luminance` ±100, `hueShift` ±180° | bands: red, orange, yellow, green, aqua, blue, purple, magenta |
| `splitTone` | `hue` (degrees), `amount` 0…100 | colour into shadows / highlights |
| `monochrome` | channel `mix` 0…1, optional duotone `shadowTone`/`highlightTone` + `toning` 0…1 | black and white |
| `channelGain` | 0…2 per channel | linear-light channel response (e.g. redscale) |

Order: linear light (exposure, white balance, channel gain, mono mix) → colour bands → saturation →
tone curve → split tone / duotone → fade. Sharpness is not part of a look.
