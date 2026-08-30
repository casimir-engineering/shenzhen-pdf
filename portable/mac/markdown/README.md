# Native Markdown subsystem

This directory is a self-contained, read-only AppKit Markdown pipeline. It is
kept separate from the PDF/MuPDF tab path and does not use HTML, WebKit,
temporary PDFs, or executable content. The engine itself never performs
network fetches: remote image bytes are downloaded by the session layer and
fed in through render options (see below), so parse/render/pagination stay
deterministic and never block on the network.

## Public entry point

Import `SPDFMarkdown.h` and build `SPDFMarkdownDocument` on a worker queue.
Create and attach its `NSTextView` on the main thread.

```objc
NSError* error = nil;
SPDFMarkdownDocument* document =
    [SPDFMarkdownDocument documentWithURL:url options:nil error:&error];
NSTextView* view = [document newSelectableTextView];
```

The view is native, selectable, non-editable, and attachment-capable. The
facade also exposes synchronous and cancellable asynchronous search/rerender
APIs. Search uses bounded overlapping windows so cancellation remains responsive
inside a very large no-match scan. Cancellation is also checked while traversing
blocks and tokenizing fenced code.

## Canonical coordinate contract

`SPDFMarkdownRenderedDocument.attributedString` is the only user-visible text
coordinate space. Search matches, heading ranges, block ranges, TextKit line
fragments, selection, and pagination all refer directly to ranges in this
string. It includes rendered structure such as list/task markers, callout
titles, table separators, thematic rules, image attachment characters and
image captions/placeholders. A fenced diagram is the one code fence whose
SOURCE is NOT canonical: it is replaced by a single attachment character, the
same way an image is (an unrenderable diagram fence keeps its source text as
ordinary, searchable code). Visible text emitted from sanitized HTML islands
is searchable/selectable exactly like markdown text; raw tag text never
appears in the canonical string. Consumers must never translate ranges through
the parser model's source text.

The parser model stores direct node text only. Parent blocks do not concatenate
their descendants, preventing repeated subtree strings and quadratic indexes.

## Input and safety

- Strict UTF-8 CommonMark with GFM tables, task lists, strikethrough and
  autolinks through vendored MD4C 0.5.3.
- LaTeX math spans (`MD_FLAG_LATEXMATHSPANS`): `$inline$` and `$$display$$`.
  The parser strips the dollar delimiters and stores the raw LaTeX as an
  inline run carrying `SPDFMarkdownInlineTraitMath` (display math additionally
  carries `SPDFMarkdownInlineTraitDisplayMath`). MD4C's flanking rules keep
  prose dollars (`$5 and $10`) out of math. Rendering is a native LaTeX-subset
  typesetter (`SPDFMarkdownMathTypesetter.mm`) — no WebKit, JS, network, or
  drawing layer: Greek letters and common operator/relation/arrow symbols map
  to Unicode, `x^2`/`a_{ij}` become smaller raised/lowered runs (one nested
  level), `\frac` collapses to a vulgar fraction when trivial and a
  fraction-slash form otherwise, `\sqrt` degrades to `√(...)`, `\text` sets
  upright, single-letter variables set in math italic, spacing commands map to
  Unicode spaces, and an unknown command degrades to its visible `\name` in
  the code font — content is never dropped. Whatever visible text the
  typesetter emits IS the canonical searchable text (`x^2` is searchable as
  `x2`). Inline math flows baseline-aligned in its paragraph; display math
  renders centered on its own line, slightly larger, with vertical margin
  (via `SPDFMarkdownMathLayoutAttribute`, the image-figure re-derivation
  pattern). Math uses the body text color and scales with `fontScale`.
- Conservative Obsidian YAML front matter, wikilinks/aliases, and callouts.
- Raw HTML islands render natively through a strict sanitizing whitelist
  (vendored Gumbo HTML5 parser, `SPDFMarkdownHTML.mm` /
  `SPDFMarkdownHTMLBlocks.mm`). Nothing is ever evaluated — HTML only
  translates into ordinary model blocks and styled runs:
  - Inline: `b`/`strong`, `i`/`em`, `code`/`tt`/`samp`, `s`/`strike`/`del`,
    `sub`/`sup` (smaller baseline-shifted runs, mirroring the math scripts),
    `kbd` (key-cap chip: smaller mono type on the inline-code background),
    `br`, `a href` (http/https/mailto/#anchor destinations only; other schemes
    keep the text and drop the link), and `img` (alt/`title` preserved;
    `width`/`height` become display-size hints with the existing image caps as
    maxima, scaling proportionally when only one is given; the src goes
    through the exact same local/https resource pipeline as markdown images).
  - Block: `h1`-`h6` (real navigable headings), `hr`, `p`/`div`/`center`
    paragraph alignment (`align` attributes and the `center` tag set a block
    alignment field the renderer's paragraph styles consume), `blockquote`,
    `ul`/`ol`/`li`, `pre`, and simple `table`/`tr`/`th`/`td` mapped onto the
    existing content-aware table model (alignment from `align` attributes;
    tables using colspan/rowspan degrade to plain text rows). The GitHub
    container pattern is handled with an explicit block-format stack: an
    island consisting only of opening container tags (`<div align="center">`,
    `<center>`, `<p align=…>`, `<details>`) pushes an alignment context that
    applies to the markdown blocks that follow, until the island holding the
    matching close tag pops it.
  - `details`/`summary`: v1 always renders the content EXPANDED, with the
    summary as a distinct bold line prefixed with a "▸ " disclosure triangle
    (collapsing is a documented limitation).
  - Dropped entirely, content included: `script`, `style`, `iframe`,
    `object`, `embed`, `form`/`input`/`select`/`textarea`/`button`, `video`,
    `audio`, inline `svg`, `math`, `canvas`, `link`, `meta`, plus every
    event/style attribute (attributes other than the whitelisted
    href/src/alt/title/align/width/height/start/colspan/rowspan are never
    read). Unknown-but-harmless tags (`span`, `font`, …) pass their children
    through unstyled. Scripts and active content are never evaluated.
- `loadURL:` accepts local file URLs only.
- Default budgets: 64 MiB UTF-8 input, 100,000 structural/inline nodes, and
  nesting depth 128. All are configurable on `SPDFMarkdownParser`; exceeding
  one returns `SPDFMarkdownErrorBudgetExceeded` or `TooLarge`.
- Local images must use a relative path inside the Markdown document's verified
  directory. The parsed model pins that directory by descriptor after checking
  the opened document identity. Each render duplicates the pinned descriptor
  instead of reopening the pathname, then walks children with no-follow `openat`
  calls. Absolute, parent-traversal, and data URLs are rejected.
- Remote images are https-only (http, data:, file: and every other scheme keep
  the text placeholder) and are GitHub-style: inline and reference-style
  syntax both resolve, and title attributes become tooltips on links and image
  attachments. The engine consults
  `SPDFMarkdownRenderOptions.remoteImageData`, a map of raw bytes keyed by
  `SPDFMarkdownRemoteImageKeyForTarget` output, synchronously; it never opens
  a connection. A remote target with no bytes yet renders as a fixed-size
  pending placeholder box (maximumImageWidth x remoteImagePlaceholderHeight,
  theme-gray with the alt text) that reserves layout space; targets in
  `failedRemoteImageTargets`, undecodable bytes, and over-budget bytes render
  the stable `[Image: alt]` text placeholder.
- The session layer (`SPDFMacMarkdownSession+RemoteImages.mm` +
  `SPDFMacMarkdownSessionImageLoader`) downloads lazily: fetches start only
  when a document containing remote images is the ACTIVE tab, run at most 4 at
  a time over an ephemeral no-cookie NSURLSession with a ~20s timeout, a 20 MB
  per-image cap, an image/* content-type requirement, and https-only
  redirects. Bytes are kept in memory for the session and persisted in an LRU
  disk cache (`~/Library/Caches/ShenzhenPDF/markdown-images/`, ~100 MB) so a
  URL downloads at most once; arrivals coalesce (~300 ms or batch completion)
  into a single viewport-preserving rerender. Print/export/copy reuse the live
  plan, so they include exactly the images loaded at that moment.
- A render caches each unique decoded image. The default aggregate budgets are
  64 MiB of resource bytes and 32 million decoded pixels, shared between local
  and remote images; over-budget or invalid images become stable text
  placeholders rather than consuming unbounded memory. Bytes that ImageIO
  cannot identify — notably SVG badges (shields.io) — get one NSImage decode
  attempt (macOS rasterizes SVG data natively on modern systems) under the
  same pixel budget; where that fails too, the text placeholder stands. No
  SVG library is vendored.

Tables retain column count and per-cell left/center/right alignment in the
model, and lay out content-aware columns (GFM's `| --- |` separator line is
consumed by the parser and never rendered). The renderer measures each
column's natural width (its widest cell plus the 8pt cell insets that keep
glyphs clear of the drawn grid) and `SPDFMarkdownTableLayout` distributes the
widths: a table narrower than the width budget keeps its compact natural
columns; a wider one caps at the budget with a fair-share waterfall — columns
at or below their fair share keep their natural width, and only the over-wide
columns split the rest, so long cells wrap inside their own column box while
short columns never wrap. Alignment applies per cell inside its column, so a
right-aligned
column flushes to its own edge and never bleeds into a neighbor. A row is as
tall as its tallest cell. Each row records an `SPDFMarkdownTableRowInfo`
(table identity, header/body role, body-row ordinal, column boundary x
positions, per-cell canonical ranges and alignments, natural widths, row
padding) on its rendered block; the paginator re-distributes the natural
widths at the real printable width, rebinds the boundaries on the row's
pagination item, and decoration planning draws GitHub-style table chrome from
that measured geometry: a
`tableHeaderFillColor` (#F6F8FA) band behind the header row, a subtle
`tableStripeFillColor` (#FAFBFC) on alternating body rows (parity is
per-table, so a split table keeps its striping across the page break), and a
1px `tableGridColor` (#D1D9E0) hairline grid at every row and column boundary.
The grid closes at a page break and resumes on the next page. Rows reserve 6pt
of symmetric vertical padding so hairlines never touch glyphs. Nested lists
retain depth and increasing paragraph indentation.

## Styling

Rendering is GitHub-flavored. Fenced code flows as one continuous block: tight
line spacing, zero paragraph spacing between code lines, and a 12pt horizontal
inset so the text sits inside the unified code box. The box background is not a
text attribute — it is drawn as a page decoration behind the code (inline code
spans keep their subtle background chip). `SPDFMarkdownTheme` in
`SPDFMarkdownDecorations.h` exposes every color as a named role of a reading
theme. Two variants exist (`SPDFMarkdownThemeVariant`): the default LIGHT
GitHub-Primer palette, and an Obsidian-default DARK palette (#1E1E1E paper,
#DCDDDE text, the #7F6DF2 purple accent, #333333 hairlines, #262626/#2A2A2A
code surfaces, a dark-tuned syntax token set). Both are concrete sRGB
constants — a theme is a set of constants, not a subsystem, and nothing is
appearance-dynamic. The variant threads explicitly:
`SPDFMarkdownRenderOptions.themeVariant` re-derives the render's palette-role
colors, and `SPDFMarkdownPageConfiguration.themeVariant` carries the palette
into every drawing consumer of the plan. The mac app persists the choice as
`markdownTheme` ("light"/"dark") in settings.yaml, toggles it from a
markdown-only toolbar button beside the text-size pill, and applies it to the
active session through the same viewport-preserving rerender as the font
scale (cached sessions catch up on activation). On the screen canvas, light
paper keeps the white sheet + drop shadow while dark paper draws a subtle
1px #333333 border instead. An images-only paragraph (nothing but images and
whitespace/soft breaks) renders by its shape. A single image becomes a
centered figure, GitHub-style: the attachment centered on its own line with a
muted centered caption line below it. The caption text is the markdown title
(`![alt](src "title")`) when one is present, falling back to the alt text;
the title also stays a tooltip on the attachment. Two or more images stay the
inline elements CommonMark says they are: they flow side by side in one
center-aligned paragraph, separated by the source's spaces (a soft break
renders as a space), wrapping onto further lines when the printable width
runs out — badge rows read as one line. Each row image captions below itself:
the row renders its image line(s), then a caption line where every
attachment-rendered image's title-or-alt caption centers under that image's
own horizontal span (wrapped rows get one caption band per wrapped image
line, and the whole row paginates as one atomic band). The captions live
exactly once in the canonical string, as a trailing caption paragraph, so
search ranges stay exact; the paginator's measurement pass re-positions each
caption span under its image via the shared
`SPDFMarkdownImageRowIndexAttribute` ordinal. An image with neither title nor
alt gets no caption, and its neighbors keep theirs. Pending remote
placeholder boxes follow the same rules by paragraph shape and caption
identically before their download lands (the caption is known at parse time,
so nothing jumps); `[Image: alt]` text placeholders already show their text
and caption nothing. An image genuinely mixed into sentence text keeps inline
flow and shows no visible alt text. In every caption-free flow the alt
survives only as the attachment's tooltip/target
metadata. `SPDFMarkdownRenderOptions.fontScale` (clamped to
[0.5, 3.0]) uniformly scales fonts and vertical spacing without touching indent
constants or image budgets, and
`renderWithOptions:languageOverrides:workQueue:completionQueue:completion:` on
the facade re-renders with caller-supplied options without mutating the
document's stored ones.

## Code languages

The picker only advertises languages with dedicated offline lexers. The
catalog covers the mainstream set: C, C#, C++, CSS, Dart, Go, Haskell, HTML,
Java, JavaScript, JSON, Kotlin, LaTeX, Lua, Markdown, Objective-C, Perl, PHP,
Python, R, Ruby, Rust, Scala, Shell, SQL, Swift, TOML, TypeScript, XML and
YAML, with generous fence aliases (`c++`, `yml`, `bash`, `golang`, …) resolved
case-insensitively.

Every lexer keeps the same rule-based architecture: rules run in precedence
order (comments, then strings, then numbers/keywords), and accepted token
ranges cannot overlap, preventing later token classes from corrupting strings
or comments. Most braces-and-keywords languages share one parameterized
grammar scanner (`SPDFMarkdownLexerSupport.mm`), instantiated per language
with its comment delimiters, string quote styles, sigils and keyword set in
`SPDFMarkdownLexersCFamily.mm` and `SPDFMarkdownLexersScripting.mm`. HTML/XML,
CSS and LaTeX have dedicated markup scanners in `SPDFMarkdownLexersMarkup.mm`;
YAML and TOML have line-oriented key/section scanners in
`SPDFMarkdownLexersData.mm`. JavaScript, TypeScript, Swift, Python, JSON and
Markdown keep their original lexers in `SPDFMarkdownHighlighter.mm`.
Missing/unknown fences remain uncolored and can be assigned through
`SPDFMarkdownLanguagePickerModel`.

## Diagrams

Fenced `mermaid`, `sequence` (js-sequence) and `flow` (flowchart.js) blocks
render as native figures: pure parsing plus Core Graphics, with no web engine,
no JavaScript and no network. The whole engine sits behind one seam,
`SPDFMarkdownDiagram.h`:

```objc
SPDFMarkdownDiagramIsDiagramLanguage(fenceIdentifier);  // O(1) fence triage
SPDFMarkdownDiagramRender(language, source, width, fontScale, variant, cache);
```

Implemented types: mermaid `graph`/`flowchart` (TD/TB/BT/LR/RL, rect, round,
stadium, circle, diamond and subroutine shapes, labelled solid/dashed/thick
edges), `sequenceDiagram` (participants and aliases, arrow variants, notes,
activations, `alt`/`opt`/`loop`/`par`/`critical`/`rect` frames), `pie`,
`stateDiagram`/`stateDiagram-v2`, `classDiagram` (compartments and the UML
relation set) and `gantt` (`YYYY-MM-DD` dates, durations, `after` chains,
`done`/`active`/`crit`). `sequence` fences use the js-sequence grammar
(including its `Title:` line) and `flow` fences the flowchart.js
`id=>type: text` grammar with branch qualifiers.

Simplifications, all deliberate and all lossless on the page: flowchart
`subgraph` grouping, `classDef`/`style`/`linkStyle`/`click` statements,
composite-state braces, state notes, class cardinality strings and mermaid's
`autonumber` are skipped, though their members still render.

**Degradation is the contract.** The seam returns nil — never a partial or
approximate drawing — on an unsupported sub-type, ANY syntax error, or a
budget overrun, and the caller then runs the unchanged code-box path: the
fence keeps its highlighted source, its canonical text, and its language pill.
The budgets are hard: 200 nodes/actors/slices/tasks, 400 edges/events, a 50 ms
layout deadline, and 4096 px per bitmap axis.

**Speed.** A document with no diagram fence does zero diagram work: the only
cost is one lowercased first-token comparison per code fence.
`SPDFMarkdownDiagramWorkCount()` counts real parse+layout+raster attempts and
is the test-visible proof of both that and the cache.
`SPDFMarkdownRenderOptions.diagramCache` carries one thread-safe
`SPDFMarkdownDiagramCache` per session, held BY REFERENCE across
`-copyWithZone:`; it is keyed by (source, language, variant, fontScale, width)
and caches failures too, so a theme or text-size change re-rasterizes while
every other rerender — a remote image arriving, a language override, a
self-heal — reuses the existing bitmaps. Diagrams are drawn at 2x into
bitmap-backed images and reserved as centered figure attachments
(`SPDFMarkdownImageLayoutRoleFigure`), recorded as PARAGRAPH blocks so
pagination never plans a code box or a language pill behind one.

`dist/diagram-demo.md` exercises every implemented type plus the degradation
cases.

## Pagination and drawing

`SPDFMarkdownPaginator` asks TextKit for real line fragments at the target
printable width. A page fragment always carries an exact attributed character
range for one complete TextKit line plus its x, baseline and page offsets.
There is no proportional range splitting or arbitrary pixel clipping.

Table rows are measured per cell: each cell wraps inside its own column box
and its lines carry a row-local y offset, so wrapped cells sit side by side
within the row band (a zero-length spacer line spans the exact band). Rows
paginate atomically — a row never splits at a page break, and a row taller
than the printable page scales into one page like any over-tall line. A table
header row keeps-with-next: when the header plus the first body row do not
both fit the page remainder, the table start moves to a fresh page, so a
header is never stranded as the last line of a page.

At or after 75% of printable height, a heading moves when the portion of its
following section that fits on a fresh page would not fit in the current
remainder. The lookahead stops at the next heading of equal or higher level.
Callout titles are independent layout items and cannot disappear from the plan.
An image or line taller than the printable area is proportionally scaled into a
page instead of being dropped. Attachment drawing is constrained to the exact
TextKit line fragment, preventing tall images from overlapping adjacent text.

Case-sensitive search uses a linear matcher with cancellation checks every 4096
UTF-16 code units. Interactive queries longer than 4096 code units are rejected
without scanning the document; this keeps pasted pathological queries bounded
while preserving normal Find semantics.

Every configuration reserves real spacer bands around each fenced-code item —
a trailing 8pt band always, plus a leading band of 8pt (print/export) or the
34pt interactive language-control height when
`includesCodeLanguageControlSpacing` is set. The plan's
`decorationsForPageIndex:` returns per-page decoration geometry in
page-content coordinates: one full-printable-width rounded code box per code
item portion on that page (covering the spacer bands; a block continuing
across pages gets one box per portion), a 1px underline rule beneath level
1 and 2 headings, and the table chrome (header band, zebra stripes, hairline
grid) described in the styling section above.

Save as PDF, preview and Print all reuse the session's live on-screen
`SPDFMarkdownPaginationPlan` (A4 portrait, current font scale and reading
theme, reserved language-control band) — a differing printer paper only
scales the finished page, it never repaginates. Configurations built from
asymmetric printable rectangles anchor content to `topContentInset`, the true
top margin. The plan's `drawPageAtIndex:attributedString:inContext:` method
draws the decorations first (the active theme's concrete palette — light:
#F6F8FA/#D0D7DE code boxes and #D1D9E0 rules on white paper; dark:
#262626/#363636 boxes and #333333 rules on #1E1E1E paper) and then the exact
planned ranges into any PDF/print Core Graphics context, preserving
vector/selectable text. Exports are WYSIWYG by design: a dark reading theme
exports dark pages, exactly what the screen shows. Drawing resolves dynamic
AppKit colors through the active theme's concrete palette with a
paper-appropriate luminance guard, so an application-appearance flip can
never produce white-on-white (or black-on-black) output.

## Compile and test

Compile `ext/md4c/md4c.c` as C. Compile every `ext/gumbo-parser/src/*.c` as
C99 with `-Iext/gumbo-parser/src` (third-party: without `-Werror`). Compile
this directory's `.mm` files as Objective-C++ with ARC. Link Foundation,
AppKit, CoreText and ImageIO.

```sh
portable/mac/tests/markdown/run-tests.sh
SPDF_MARKDOWN_SANITIZER_FLAGS='-fsanitize=address,undefined -fno-omit-frame-pointer' \
    ASAN_OPTIONS=detect_leaks=0 portable/mac/tests/markdown/run-tests.sh
```

The direct suite covers canonical search/selection correspondence after
structural content, input/path budgets, pathological nesting, CRLF/BOM/CJK and
emoji, language-specific non-overlapping tokens, local image attachments,
table alignment, content-aware column distribution and in-column cell wrapping
(including per-cell fragment containment, header keep-with-next, atomic rows,
grid/stripe alignment with measured boundaries, and wrapped-cell search
correspondence), exact interleaved list order, bounded image memory, pinned-root
replacement between parse and render, large-search cancellation and long-query
rejection, exact TextKit ranges, the 75% rule, callout pagination, over-tall
content scaling, code-box/heading-rule decoration geometry (including blocks
split across pages), font scaling, and PDFKit/raster probes for selectable
text, concrete print colors for both reading themes (including the dark-paper
raster probes), the filled code-box background, and image containment within
its line fragment. The diagram suite covers a render of every implemented
diagram type, the nil-degradation paths (unknown sub-type, syntax error,
over-budget graph), the zero-work proof for a diagram-free document, the
session cache (including negative caching and the variant/scale re-raster),
per-theme pixel inequality, and the end-to-end canonical-string shape of both
a rendered figure and a degraded fence.

## Recommended Makefile fragment

Do not copy this blindly into a differently named build graph; it documents the
required source/link/test shape for the later integration change:

```make
MARKDOWN_C := ext/md4c/md4c.c $(wildcard ext/gumbo-parser/src/*.c)
MARKDOWN_MM := $(wildcard portable/mac/markdown/*.mm)
MARKDOWN_FRAMEWORKS := -framework Foundation -framework AppKit -framework CoreText -framework ImageIO

.PHONY: mac-markdown-tests
mac-markdown-tests:
	portable/mac/tests/markdown/run-tests.sh
```

## Remaining app hooks

The intentionally separate integration patch must recognize `.md` files,
create Markdown tabs, attach the view, route Find to canonical matches, handle
wikilink clicks, present language choices, and share one page plan between
system Print and Save as PDF. None of those existing app files are modified by
this subsystem change.
