# Release notes

User-facing notes for changes merged since the last release (26.8.30 build 1).

Release notes are tracked in `portable/docs/releases/`. Prepare the next release
with `./portable/cut-release.sh --prepare-only ["summary"]`; publish the
validated metadata from master with `./portable/cut-release.sh --publish`.

## Next release

- The dark reading theme now darkens the area around the pages too, well below
  the paper, so a page reads as a sheet on a desk instead of blending into its
  own background. PDF pages get a thin border on all four sides in the dark
  theme, replacing the drop shadow that no dark background could show.
- Markdown Save as PDF, Print, Copy Page and Copy Page Image always produce the
  light pages now, even while you are reading in the dark theme — the same rule
  PDFs already followed. Everything else is unchanged: same margins, same
  pagination, same text size, page for page with the screen.
- Translate now works on Markdown documents. Select any text and translate it
  from the toolbar or the right-click menu, exactly as on a PDF. Whole-document
  translation stays a PDF feature — it rewrites translated lines back into a
  PDF's own pages — and says so instead of leaving the button greyed out.
- The reading-theme toggle now matches the toolbar controls beside it.
