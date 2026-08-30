# Release notes

User-facing notes for changes merged since the last release (26.8.31 build 1).

Release notes are tracked in `portable/docs/releases/`. Prepare the next release
with `./portable/cut-release.sh --prepare-only ["summary"]`; publish the
validated metadata from master with `./portable/cut-release.sh --publish`.

## Next release

- Reopening a closed Markdown document (Cmd+Shift+T) now lets you search it straight away. The document took focus only when its tab was selected, but a Markdown page is built in the background, so there was nothing to focus yet and typing or Cmd+F did nothing until you clicked the page. Any displayed document is searchable the moment it appears.
- Dark-theme pages no longer show a faint lighter line down their right edge. Every page was painted white underneath its rendered image, and at some zoom levels the image stops a fraction of a point short of the edge, letting that white show through. Pages are now painted in the theme's own paper color.
