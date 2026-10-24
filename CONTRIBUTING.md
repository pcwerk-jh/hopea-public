# Contributing a look

Anyone can share a look. Every submission is checked automatically and reviewed by a maintainer
before it's published.

## Three ways to submit

1. **Submission form (no git needed).** [Open the form](https://github.com/rovetravel/hopea-public/issues/new?template=submit-look.yml),
   fill in the details and attach your `.cube` file (rename it to `.txt` if GitHub won't accept
   it). A bot packages it, renders previews and opens a pull request for review. If something
   needs fixing it comments on your submission — edit it and it tries again. You need a free
   GitHub account.
2. **Pull request.** Package your look with the `hopea-look` tool (see [README.md](README.md)) and
   add it as `looks/<your-handle>/<look-name>/look.hopealook`. You can also write a
   `recipe.json` (photographic controls, see [FORMAT.md](FORMAT.md#recipes)) and bake it — commit
   both files. CI validates every look, checks baked looks match their recipes, and renders
   previews.
3. **Email or DM the maintainers** your `.cube` file and the details from the form. We'll package
   it and credit you.

## What makes a good look

- Natural, photographic, and kind to skin tones. Hopea's character is gentle — no heavy HDR.
- Built for **Display P3** input (see [FORMAT.md](FORMAT.md)). Keep grain, vignette and halation
  out of the LUT and use the numeric settings instead.
- Check it on the reference photos: `hopea-look render-previews …`.

## Licensing

You must have made the look (or have the right to share it). Choose:

- **CC BY 4.0** — anyone may use and remix it, crediting you. Hopea credits the creator in the
  metadata of every photo taken with the look.
- **CC0 1.0** — no conditions.

## Updating a look

Open a pull request that changes your look file and bumps `version`. Apps that installed it are
offered the update. Looks under your handle can only be changed by you or a maintainer.

## Review

Maintainers check that the look works, isn't a copy of someone else's, and fits the catalog.
They may ask for changes or decline a look. Problems with a published look? Open an issue.

## Code

Changes to `kit/`, `site/` and the tools are welcome as pull requests. Run `swift test` first.
Commit messages describe what changed, technically.
