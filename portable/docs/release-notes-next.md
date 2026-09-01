# Release notes

User-facing notes for changes merged since the last release (26.9.1 build 1).

Release notes are tracked in `portable/docs/releases/`. Prepare the next release
with `./portable/cut-release.sh --prepare-only ["summary"]`; publish the
validated metadata from master with `./portable/cut-release.sh --publish`.

## Next release

- Clicking a tab now focuses the window, and its traffic lights light up so you
  can see that it did. Tab clicks were handled before macOS could hand the
  window keyboard focus, so the app became usable while still looking
  unfocused, with no feedback that the click had landed. Selecting a tab, its
  close box and a middle-click close all focus the window now.
- An unfocused window can be zoomed with Cmd+scroll, not only with a trackpad
  pinch. The out-of-focus zoom path listened for pinch gestures alone, so a
  modifier-carrying scroll over a background window did nothing.
