# Release notes

User-facing notes for changes merged since the last release (26.9.1 build 2).

Release notes are tracked in `portable/docs/releases/`. Prepare the next release
with `./portable/cut-release.sh --prepare-only ["summary"]`; publish the
validated metadata from master with `./portable/cut-release.sh --publish`.

## Next release

- Tabs now have a visible outline. An unselected tab was drawn with no border
  at all, over a background the same colour as the tab strip behind it, so in
  both the light and dark themes it had no edge you could see. Unselected tabs
  get a neutral hairline; the selected tab keeps its heavier accent border.
