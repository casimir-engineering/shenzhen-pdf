# Release notes

User-facing notes for changes merged since the last release (26.8.31 build 2).

Release notes are tracked in `portable/docs/releases/`. Prepare the next release
with `./portable/cut-release.sh --prepare-only ["summary"]`; publish the
validated metadata from master with `./portable/cut-release.sh --publish`.

## Next release

- Images inside a Markdown document now darken with the page in the dark theme, the way a PDF's images already did. Settings > Keep Image Colors in Dark Theme leaves them untouched, and it now takes effect immediately instead of on the next tab switch. Saving or printing still exports the document's own colors.
- Artwork with a cut-out background no longer picks up a bright halo in the dark theme, and the page minimap no longer shows a white sheet behind a page that has no white in it.
