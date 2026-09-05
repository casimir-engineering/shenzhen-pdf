# ShenzhenPDF — complete feature list

Everything the app does today, grouped by what you would be doing at the time.
The [readme](../readme.md) is the short version; this is the exhaustive one.

Platform tags: **mac** = macOS (AppKit), **linux** = GTK4 + libadwaita,
**win** = the native Win32 + Direct2D frontend in `portable/win/`. An untagged
entry works on all three. (The separate Win32 tree in `src/` is the legacy
SumatraPDF-era code and is not the Windows app; see
`portable/docs/windows-feature-matrix.md` for the Windows frontend's
feature-by-feature status.) No Windows binary is published yet; the build
is a single self-installing executable, `dist\ShenzhenPDF-win-x64.exe`.

- [Formats](#formats)
- [Opening documents](#opening)
- [Tabs and windows](#tabs)
- [Reading and navigation](#reading)
- [Search](#search)
- [Document map and scrollbar](#map)
- [Chapters, comments and the side panel](#sidepanel)
- [Markdown](#markdown)
- [Markdown syntax support](#markdown-syntax)
- [Diagrams](#diagrams)
- [Annotations](#annotations)
- [OCR](#ocr)
- [Translation](#translation)
- [Printing and export](#export)
- [Appearance and reading theme](#theme)
- [Speed](#speed)
- [Files, state and integration](#files)
- [Updates and verification](#updates)
- [Keyboard shortcuts](#shortcuts)

## <a id="formats"></a>Formats

| Format | Notes |
| --- | --- |
| PDF | The primary, most-polished path: text, links, outline, annotations, rotation, save, export |
| XPS | Rendered through MuPDF |
| EPUB, MOBI | Reflowable e-books |
| CBZ | Comic archives; never recolored by the dark theme |
| FB2 | E-book format |
| HTML | Rendered by MuPDF, not a browser engine |
| Images | PNG, JPEG and the rest of MuPDF's image set; never recolored |
| Markdown | `.md` through the app's own paginated renderer **mac** |

Password-protected PDFs prompt for the password, remember it for the session,
and drop every stored credential at quit.

Read-only sources (a file on a locked volume, a document opened from a
read-only location) are opened through a persisted shadow copy, so a relaunch
does not re-trigger the macOS access prompt.

## <a id="opening"></a>Opening documents

- **Open…** (<kbd>Cmd+O</kbd>) — the standard macOS panel, starting in the
  current document's folder, else your last opened one's, else home.
- **Open Path…** (<kbd>Cmd+Shift+O</kbd>) — type or paste a path; a file opens
  it, a folder opens the file browser there.
- **Drag and drop** onto the window or the tab strip.
- **Recents** — the recently-opened list lives in `settings.yaml`.
- **Reopen Last Closed** (<kbd>Cmd+Shift+T</kbd>) — brings a just-closed tab
  back with its view state.
- **Favorites** — star a page or a whole document, give it a name and optional
  search labels, and find it later from the command palette or *Manage
  Favorites*.
- **Command palette** (<kbd>Cmd+K</kbd>) — one search field over favorites,
  open documents, and commands.
- **Make ShenzhenPDF the default PDF reader** — one menu item, no System
  Settings trip.

## <a id="tabs"></a>Tabs and windows

- **Compact tab strip** — every tab outlined, same-named files disambiguated by
  their folder, overflow into a "…" menu.
- **Drag to reorder**, drag out to **detach into a new window**, drag back to
  **reattach**. A detached tab keeps its page, zoom, scroll and search.
- **Read-only dot** — a tab opened from a read-only source is marked.
- **Multi-window session restore** — every window comes back with its own tabs,
  selected tab, size and position, on the display it was left on. The window
  you were last using returns focused, and the others open alongside it rather
  than a launch later.
- **A stand-in position is never saved** — launch with a display missing and the
  window is shown somewhere visible for that session only; the position you
  left is kept until you move the window yourself, and the window returns to its
  display when it reappears.
- **Per-document view state** — page, zoom, fit mode, scroll position, search
  text, and (for Markdown) page orientation come back per file.

## <a id="reading"></a>Reading and navigation

- **Continuous scrolling** with page stepping that keeps your zoom and position.
- **Fit page / fit width / fit height / actual size / custom zoom**, with zoom
  presets and <kbd>Cmd</kbd>+scroll zoom — including in an unfocused window.
- **Option + scroll turns pages** **mac** — anywhere in the window, over the page
  or the minimap; behaves exactly like the page arrows and pages faster the
  faster you spin.
- **Go to page** (<kbd>Cmd+L</kbd>), first/last page, page-by-page arrows.
- **Internal links** follow instantly and land at the top of the target page;
  the pointer becomes a hand over a link and an I-beam over text.
- **Text selection and copy**, including *Copy Selected Document Text* and an
  optional *Replace Line Breaks When Copying Text*. Copying is always allowed —
  a PDF's own copy-permission flag never blocks it.
- **Rotate page** clockwise / anticlockwise (<kbd>Cmd+R</kbd> /
  <kbd>Cmd+Shift+R</kbd>). On a Markdown document the same commands turn the
  *paper* landscape, and the text stays upright.
- **Presentation mode** (<kbd>F5</kbd> or <kbd>Cmd+Shift+F</kbd>) — chrome-free
  full screen, pure black surround, optional sleep prevention.
- **Properties** (<kbd>Cmd+I</kbd>) — title, author, producer, dates, page size,
  encryption, file size.
- **Auto-reload** — a document edited on disk refreshes in place, keeping your
  place. For Markdown the new render is prepared off-screen and swapped in
  complete, so nothing blanks or flashes.

## <a id="search"></a>Search

- **Type anywhere to search** — no need to focus a field first.
- **Live match count** — a running "current / total" as you type, with every
  match highlighted in the page.
- **Find next / previous** (<kbd>Enter</kbd> / <kbd>Shift+Enter</kbd>,
  <kbd>Cmd+G</kbd> / <kbd>Cmd+Shift+G</kbd>).
- **Regular expressions**, including **multiline** patterns that span line and
  paragraph breaks. An invalid pattern fails gracefully instead of clearing your
  results.
- **Nearest-result jump** — an optional setting makes a new search land on the
  match closest to where you are reading rather than at the top.
- **Per-tab memory** — each tab remembers its query across tab switches and
  relaunches.
- **Search across everything** — the command palette searches open documents and
  favorites at once.

## <a id="map"></a>Document map and scrollbar

- **Minimap** — a live thumbnail strip beside the page: drag the viewport to
  scroll, click to jump, <kbd>Cmd</kbd>+scroll to zoom. Scales to hundreds of
  pages, renders lazily, and follows the reading theme.
- **Search markers** — hits appear as yellow marks in the map.
- **Scrollbar heat-map** — the scrollbar doubles as a match density map, one
  tick per hit with the active one hotter.
- **Per-document map preference** — show or hide the map per document, with a
  default for newly opened ones; a single-page document hides it automatically.

## <a id="sidepanel"></a>Chapters, comments and the side panel

- **Three modes in one panel** — Chapters, Comments, and search results.
- **Nested chapters** **mac** — a PDF's outline and a Markdown document's
  headings both fold, with the traditional disclosure arrows on every parent.
- **One expand / collapse all button** at the end of the filter row, showing the
  action it will perform.
- **Per-document memory** — what you left collapsed comes back collapsed, per
  file, across launches.
- **Filter field** — filter chapters or comments as you type.
- **Chapter-grouped search results** — every match with a snippet, grouped under
  its chapter heading; click to jump.
- **Per-document panel preference**, with a default for newly opened documents.

## <a id="markdown"></a>Markdown **mac**

Markdown opens as real A4 sheets in the same reader as PDFs — same tabs,
chapters, map, search, zoom presets, presentation mode and export. There is no
web engine, no JavaScript, and no network in the rendering path.

- **GitHub-flavored typography and palette**, paginated onto sheets.
- **Live update** — edit the file in another app and the document re-renders in
  the background and swaps in complete, keeping your place.
- **Landscape paper** — the Rotate commands turn the sheet; wide tables, images
  and diagrams re-fit to it. Each file reopens on the sheet you last read it on.
- **Adjustable text size** (<kbd>A−</kbd> / <kbd>A＋</kbd>), remembered across
  documents.
- **Dark palette, not a filter** — an Obsidian-flavored dark theme (dark paper,
  purple accents, dark-tuned syntax colors) that lands on the same paper and
  body-text colors as a dark PDF page.
- **Everything is real text** — selectable, searchable with <kbd>Cmd+F</kbd>,
  and still text in an exported PDF. That includes labels inside diagrams.

### <a id="markdown-syntax"></a>Markdown syntax support

Strict UTF-8 CommonMark through vendored MD4C, plus:

| Feature | Support |
| --- | --- |
| Headings `#`–`######` | Real navigable headings; feed the chapter list |
| Emphasis, strong, inline code | Yes |
| Strikethrough `~~…~~` | Yes (GFM) |
| Links and autolinks | Yes; titles become tooltips |
| Images, local | Relative paths inside the document's verified directory only |
| Images, remote | `https` only, lazily downloaded into a shared disk cache |
| Lists, ordered and unordered | Yes, with nesting depth and indentation |
| Task lists `- [ ]` / `- [x]` | Yes (GFM) |
| Tables | GFM tables with per-cell alignment, content-aware column widths, header band, zebra striping, hairline grid that closes at a page break |
| Fenced code | Continuous rounded box, 31 languages highlighted, language picker and copy button on every block |
| Indented code | Yes |
| Block quotes | Yes |
| Callouts | Obsidian-style `> [!note]` callouts |
| Thematic breaks | Yes |
| Front matter | Conservative Obsidian YAML front matter |
| Wikilinks `[[page]]` and aliases | Yes |
| LaTeX math | `$inline$` and `$$display$$`, typeset natively |
| Footnotes | Not supported |
| `<details>` collapsing | Renders always expanded, with a bold ▸ summary line |

**Inline HTML** renders natively through a strict sanitizing whitelist (vendored
Gumbo HTML5 parser). Nothing is ever evaluated:

- Inline: `b`/`strong`, `i`/`em`, `code`/`tt`/`samp`, `s`/`strike`/`del`,
  `sub`/`sup`, `kbd` (as a key-cap chip), `br`, `a href` (http/https/mailto/
  anchor only), `img` (with `width`/`height` size hints).
- Block: `h1`–`h6`, `hr`, `p`/`div`/`center` with `align`, `blockquote`,
  `ul`/`ol`/`li`, `pre`, and simple `table`/`tr`/`th`/`td`. `details`/`summary`
  as above.
- Dropped entirely, content included: `script`, `style`, `iframe`, `object`,
  `embed`, forms and form controls, `video`, `audio`, inline `svg`, `math`,
  `canvas`, `link`, `meta`, and every event or style attribute.

**LaTeX math** is a native subset typesetter — no WebKit, no JavaScript, no
network: Greek letters and common operator, relation and arrow symbols map to
Unicode; `x^2` and `a_{ij}` become raised and lowered runs; `\frac` collapses to
a vulgar fraction or a fraction-slash form; `\sqrt` degrades to `√(…)`; `\text`
sets upright; spacing commands map to Unicode spaces; an unknown command degrades
to its visible `\name` in the code font. Content is never dropped, and whatever
is shown is searchable.

**Syntax highlighting** covers 31 languages — C, C++, C#, CSS, Dart, Go,
Haskell, HTML, Java, JavaScript, JSON, Kotlin, LaTeX, Lua, Markdown,
Objective-C, Perl, PHP, Python, R, Ruby, Rust, Scala, Shell, SQL, Swift, TOML,
TypeScript, XML, YAML, and Plain Text — chosen from a searchable picker anchored
to the block, which also clears highlighting.

### <a id="diagrams"></a>Diagrams

Fenced `mermaid`, `sequence` (js-sequence) and `flow` (flowchart.js) blocks
render as native vector artwork — parsing plus geometry, no web engine, no
JavaScript, no network, no bitmaps. They stay crisp at any zoom and export to
PDF as vector art.

| Diagram | Support |
| --- | --- |
| `graph` / `flowchart` | TD/TB/BT/LR/RL; rect, round, stadium, circle, diamond, subroutine shapes; labelled solid, dashed and thick edges; bidirectional arrows; layered layout with routed long edges and a non-crossing fan; `classDef` styling via `:::name` or `class a,b name` |
| `sequenceDiagram` | Participants and aliases, arrow variants, notes, activations, `alt`/`opt`/`loop`/`par`/`critical`/`rect` frames |
| `classDiagram` | Compartments and the UML relation set |
| `stateDiagram` / `stateDiagram-v2` | Yes |
| `pie` | Yes |
| `gantt` | `YYYY-MM-DD` dates, durations, `after` chains, `done`/`active`/`crit`; takes the full width of the page, landscape included |
| `sequence` fences | js-sequence grammar, including its `Title:` line |
| `flow` fences | flowchart.js grammar |

`<b>`/`<i>` inside a label render as real bold and italic runs, `<br/>` breaks
the line, and labels are fitted to the shape they sit in. Author colors from
`classDef` are painted verbatim in the light theme and put through the same
luma remap as everything else in the dark one, so hues stay distinguishable. A
fence the renderer cannot draw keeps its ordinary highlighted code box.

## <a id="annotations"></a>Annotations

- **Highlight comments** — select text, add a comment anchored to the
  highlighted rectangles.
- **Text comments** — drop a comment at a point on the page.
- **Edit and delete** existing comments.
- **Comment author** — set once (*Set Author for Comments…*) and reused.
- **Comments panel** — every comment listed with its page, filterable, click to
  jump.
- Comments are saved into the PDF immediately, so any other reader sees them.

## <a id="ocr"></a>OCR — on-device **mac · linux**

- **Make a scanned PDF searchable** with OCRmyPDF + Tesseract, entirely on your
  machine. Nothing is uploaded.
- **Language choice up front** — Simplified or Traditional Chinese alone or with
  English, plus ~20 more; missing language data is fetched on demand.
- **One job per core**, deskews scans, backs up the original, and swaps in only
  confirmed text.
- **One-click toolchain install** — missing OCRmyPDF, Tesseract or a language
  pack is installed for you (Homebrew on macOS; apt/dnf/pacman/zypper on Linux)
  and the job resumes, with a live copyable log.
- **Delete All Text** — strip a bad OCR layer back out.

## <a id="translation"></a>Translation — on-device **mac · linux**

- **Argos Translate**, running locally across ~19 languages including Chinese.
  Text never leaves the machine.
- **Translate a selection** into a panel, or **a whole document**.
- **Whole-document mode writes a real PDF** (`<name>_<lang>.pdf`) with the
  translated text overlaid at each source line's position, and opens it when it
  finishes.
- **Cancellable mid-run**, with the same one-click toolchain install as OCR.

## <a id="export"></a>Printing and export

- **Native printing** through the standard macOS pipeline, with **Fit**,
  **Actual Size** and **Custom** scaling.
- **Save As** — save the document, including added comments and rotations.
- **Save as PDF** from a Markdown document, page for page with what is on
  screen.
- **Copy Page** and **Copy Page Image**.
- **Single-page PDF export** from the core.
- **Exports never carry the dark theme.** A file that leaves the reader keeps
  the document's own colors — for Markdown as much as for a PDF.

## <a id="theme"></a>Appearance and reading theme

- **One dark reading theme for every document** (<kbd>Cmd+Shift+I</kbd>) —
  PDF, XPS, EPUB and Markdown alike, onto the same soft `#1E1E1E` paper rather
  than pure black.
- **Lightness remap, not inversion** — a rendered page keeps its chroma, so a
  red warning stays red and a blue link stays blue.
- **Keep Image Colors in Dark Theme** — leaves photographs and figures
  untouched, **per document**, defaulting to on and remembered per file. Scanned
  pages (one big image) are darkened anyway, so the setting can never quietly
  switch dark mode off.
- **Comic archives and image files are never recolored.**
- **Page separation that works in the dark** — a white sheet with a drop shadow
  in light, a crisp hairline border in dark, in the page view and the minimap
  alike.

## <a id="speed"></a>Speed

- **Instant launch** — the first page of the document you are actually opening
  is prerendered during launch, before the window is built.
- **Priority rendering** — the visible page renders first at high priority;
  nearby pages and inactive tabs warm up quietly behind it, so tab switches are
  instant.
- **Cached display lists** and crop-to-viewport rendering make repeat renders
  cheap; a stale render aborts within milliseconds.
- **Bounded, cancellable search** — a large no-match scan stays responsive.
- **Compact C core** — ~93 KB wrapping statically linked MuPDF 1.27.2 behind a
  small stable ABI shared by both frontends. No Win32 emulation.

## <a id="files"></a>Files, state and integration

- **Human-readable YAML state** you can read, diff and edit:
  `settings.yaml`, `session.yaml`, `documents.yaml`, `favorites.yaml`,
  `bookmarks.yaml`. Existing JSON state migrates automatically, originals kept
  as `.migrated-backup`.
  macOS: `~/Library/Application Support/ShenzhenPDF/` · Linux:
  `~/.config/shenzhenpdf/`
- **Show in Folder** and **Copy Path** for the current document.
- **Shenzhen Files integration** **mac** — install Shenzhen Files and it becomes
  the app's file manager on its own; *Settings ▸ File Manager* switches back to
  Finder, an explicit choice always wins, and every launch falls back to Finder
  if it is missing. Picking a file always uses the standard macOS panel.
- **Open in Adobe Acrobat Reader** when it is installed.
- **Permissions wizard** — walks through the macOS grants the optional features
  need (Accessibility for out-of-focus pinch zoom, Full Disk Access), and never
  nags once dismissed.
- **Keyboard shortcuts panel**, searchable, optionally shown at launch.

## <a id="updates"></a>Updates and verification

- **Once-a-day background check** against GitHub Releases, kept off the launch
  path, and switchable off.
- **Offline verification before installing** — pinned Apple Developer ID (Team
  66LJ4BV7Q3), hardened runtime, bundle id, and stapled notarization.
- **Atomic swap with rollback** — a failed installation restores the working app
  immediately; a mismatched relaunch keeps and reveals the previous `.old` app
  for manual recovery.
- **Skip a version** and it stays skipped.
- **Linux** ships a minisign-verified updater for the deb and tarball builds.

## <a id="shortcuts"></a>Keyboard shortcuts

### Search

| Action | Keys |
| --- | --- |
| Start searching from the document | Type anywhere |
| Find in current document | <kbd>Cmd+F</kbd> |
| Next / previous result | <kbd>Enter</kbd> / <kbd>Shift+Enter</kbd> |
| Find next / previous | <kbd>Cmd+G</kbd> / <kbd>Cmd+Shift+G</kbd> |

### Favorites

| Action | Keys |
| --- | --- |
| Command palette (open documents, favorites, commands) | <kbd>Cmd+K</kbd> |
| Favorite current page | <kbd>Cmd+B</kbd> |
| Favorite current document | <kbd>Cmd+Shift+B</kbd> |

### Pages and view

| Action | Keys |
| --- | --- |
| First / last page | <kbd>Opt+↑</kbd> / <kbd>Opt+↓</kbd> |
| Previous / next page (always jumps a page) | <kbd>Opt+←</kbd> / <kbd>Opt+→</kbd> |
| Previous / next page (keeps zoom and position) | <kbd>←</kbd> / <kbd>→</kbd>, <kbd>Cmd+↑</kbd> / <kbd>Cmd+↓</kbd> |
| Previous or next page, wherever the pointer is | <kbd>Opt</kbd> + scroll wheel |
| Go to page | <kbd>Cmd+L</kbd> |
| Jump a page | <kbd>Shift</kbd> + arrow |
| Scroll up / down | <kbd>↑</kbd> / <kbd>↓</kbd> |
| Zoom in / out | <kbd>Cmd++</kbd> / <kbd>Cmd+-</kbd> |
| Fit page / width / height | <kbd>Cmd+1</kbd> / <kbd>Cmd+2</kbd> / <kbd>Cmd+3</kbd> |
| Actual size | <kbd>Cmd+4</kbd> |

### Tabs and tools

| Action | Keys |
| --- | --- |
| Reorder or detach tabs | Drag tabs |
| Previous / next tab | <kbd>Cmd+←</kbd> / <kbd>Cmd+→</kbd> |
| Open file | <kbd>Cmd+O</kbd> |
| Open path | <kbd>Cmd+Shift+O</kbd> |
| Reopen last closed document | <kbd>Cmd+Shift+T</kbd> |
| Document properties | <kbd>Cmd+I</kbd> |
| Rotate clockwise / anticlockwise | <kbd>Cmd+R</kbd> / <kbd>Cmd+Shift+R</kbd> |
| Presentation mode | <kbd>F5</kbd> or <kbd>Cmd+Shift+F</kbd> |
| Leave presentation mode | <kbd>Esc</kbd> |

### Panels

| Action | Keys |
| --- | --- |
| Show or hide chapters and comments | View menu or the Side Panel toggle |
| Show or hide the map | View menu or the Map toggle |
| Light or dark reading theme | <kbd>Cmd+Shift+I</kbd> |

## Platform support

| | macOS | Linux | Windows |
| --- | --- | --- | --- |
| Frontend | AppKit | GTK4 + libadwaita | Win32 + Direct2D (`portable/win/`), no published binary yet |
| Reading, tabs, session restore | Yes | Yes | Yes |
| Search, map, scrollbar heat-map | Yes | Yes | Yes |
| Command palette, favorites | Yes | Yes | Yes |
| Presentation mode, printing, properties | Yes | Yes | Yes (print preview; Windows' own dialog where it opens) |
| OCR and translation | Yes | Yes | Yes (winget Tesseract, pip OCRmyPDF, Argos in a venv) |
| Markdown renderer, diagrams, math | Yes | — | Markdown and math via MuPDF's HTML engine; diagrams still draw as code boxes |
| Nested chapters, Option+scroll paging | Yes | — | Nested chapters yes; Alt+scroll paging not yet |
| Auto-updater | Developer ID + notarization | minisign (deb, tarball) | Authenticode, pending a signed release |

Linux additionally offers an optional resident mode for instant launches.

Windows is a single statically linked executable that launches in about 130 ms
to a window with its first page already painted, so it needs no resident mode.
Everything above marked "Yes" for Windows is pinned by the native test suite in
`portable/win/tests/`; the exhaustive per-feature status, with evidence, is
`portable/docs/windows-feature-matrix.md`.
