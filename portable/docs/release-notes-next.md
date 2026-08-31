# Release notes

User-facing notes for changes merged since the last release (26.8.31 build 3).

Release notes are tracked in `portable/docs/releases/`. Prepare the next release
with `./portable/cut-release.sh --prepare-only ["summary"]`; publish the
validated metadata from master with `./portable/cut-release.sh --publish`.

## Next release

- Keep Image Colors in Dark Theme is now ON by default. Photographs, screenshots and figures keep their own colors on a dark page instead of being darkened with it; the page around them still is. If you had already turned the setting off, it stays off. A page that is essentially one big image is a scan, and is still darkened whole so dark mode is not a no-op on it.
