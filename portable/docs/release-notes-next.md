# Release notes

User-facing notes for changes merged since the last release (26.8.28 build 2).

Release notes are tracked in `portable/docs/releases/`. Prepare the next release
with `./portable/cut-release.sh --prepare-only ["summary"]`; publish the
validated metadata from master with `./portable/cut-release.sh --publish`.

## Next release

- Markdown tabs now render LaTeX math: `$inline$` and `$$display$$` spans
  typeset natively (Greek letters and common symbols, super/subscripts,
  fractions, roots, `\text`, spacing commands) with GitHub-style centered
  display equations; unknown commands stay visible instead of disappearing,
  and math text remains searchable and prints exactly as shown.
