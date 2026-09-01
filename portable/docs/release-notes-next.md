# Release notes

User-facing notes for changes merged since the last release (26.9.1 build 1).

Release notes are tracked in `portable/docs/releases/`. Prepare the next release
with `./portable/cut-release.sh --prepare-only ["summary"]`; publish the
validated metadata from master with `./portable/cut-release.sh --publish`.

## Next release

- Any click inside a ShenzhenPDF window now focuses that window, including
  clicks on the tab strip: selecting a tab, hitting a tab's close box, and
  middle-clicking a tab to close it all bring the window to the front. Pinch and
  Cmd+scroll zoom work straight afterwards, instead of needing a separate click
  in the page first.
