# Release notes

User-facing notes for changes merged since the last release (26.8.28 build 1).
Because the staged 26.8.27-1 and 26.8.28-1 metadata was never published, the
next release's notes span everything since 26.7.17 build 1 — the last release
users actually received.

Release notes are tracked in `portable/docs/releases/`. Prepare the next release
with `./portable/cut-release.sh --prepare-only ["summary"]`; publish the
validated metadata from master with `./portable/cut-release.sh --publish`.

## Next release

- **Markdown support**: GitHub-grade formatting
- Markdown documents have the same navigation as PDFs and can export as PDFs
- Password-protected PDF support
- Double click to select a word, triple a text block. Double click to expand the window.
- Bug fixes: Cmd/Ctrl+W to close a file-not-found tab
- Chapters now work in EPUB

---

### Markdown reading design

- A GitHub-flavored reading palette replaces pure black: near-black body text,
  muted secondary grays, semibold headings with hairline underlines, blue
  underlined links, and a real thematic-break rule.
- Fenced code renders as one continuous rounded box with syntax colors, real
  margins, and a quiet language control in the box header.
- Tables are laid out from their content: columns size to their cells, long
  cells wrap inside their own column, and every table draws a light-gray grid,
  a distinct header band, and subtle alternating row striping. A table split
  across pages keeps its header with its rows and its striping parity.
- Markdown text size is adjustable from the toolbar (A− / A＋) and remembered
  across documents and launches.

### PDF-parity reading interactions

- Chapter clicks land exactly on their section, top-aligned, and highlight the
  right sidebar row. Page stepping always moves the view deterministically.
- Pages that fit the window stay locked to the horizontal center through
  scrolling, zooming, and resizing, exactly like PDF tabs.
- Search gains full PDF parity: match highlights that hug the text, an animated
  outline on the current match, centered scroll-to-match, nearest-match
  selection, match markers in the document map and the scrollbar, chapter-
  grouped results, and regex support.
- The pointer now matches PDF tabs: an I-beam over text, a pointing hand over
  links and the code-language control, and a grab hand while panning.
- Toolbar button pairs (pages, zoom, text size, search next/previous) are
  compact two-segment controls.

### Code languages

- The syntax catalog grows from 5 to 31 languages, including C, C++,
  Objective-C, Rust, Go, TypeScript, SQL, HTML, CSS, YAML, TOML, LaTeX, and
  shell, with generous fence aliases.
- The language picker opens instantly as a searchable list anchored to the code
  block, and Plain Text is an explicit choice that clears highlighting.

### Fidelity between screen, print, and export

- Save as PDF and Print reproduce the on-screen pages exactly — same margins,
  pagination, text size, and chrome — scaling to the printer paper when needed.
- Copy Page and Copy Page Image work on Markdown tabs, producing a single-page
  vector PDF or a crisp 2x image of the current sheet.
- Choosing a code language or changing the text size re-renders in place
  without moving the viewport.
