# Native Markdown subsystem

This directory is a self-contained, read-only AppKit Markdown pipeline. It is
kept separate from the PDF/MuPDF tab path and does not use HTML, WebKit,
temporary PDFs, network fetches, or executable content.

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
image captions/placeholders. Consumers must never translate ranges through the
parser model's source text.

The parser model stores direct node text only. Parent blocks do not concatenate
their descendants, preventing repeated subtree strings and quadratic indexes.

## Input and safety

- Strict UTF-8 CommonMark with GFM tables, task lists, strikethrough and
  autolinks through vendored MD4C 0.5.3.
- Conservative Obsidian YAML front matter, wikilinks/aliases, and callouts.
- Raw/inline HTML disabled. Scripts and active content are never evaluated.
- `loadURL:` accepts local file URLs only.
- Default budgets: 64 MiB UTF-8 input, 100,000 structural/inline nodes, and
  nesting depth 128. All are configurable on `SPDFMarkdownParser`; exceeding
  one returns `SPDFMarkdownErrorBudgetExceeded` or `TooLarge`.
- Local images must use a relative path inside the Markdown document's verified
  directory. The parsed model pins that directory by descriptor after checking
  the opened document identity. Each render duplicates the pinned descriptor
  instead of reopening the pathname, then walks children with no-follow `openat`
  calls. Absolute, parent-traversal, data and remote URLs are rejected.
- A render caches each unique decoded image. The default aggregate budgets are
  64 MiB of resource bytes and 32 million decoded pixels; over-budget or invalid
  images become stable text placeholders rather than consuming unbounded memory.

Tables retain column count and per-cell left/center/right alignment in the
model. Native rendering uses stable tab stops with the declared alignment.
Nested lists retain depth and increasing paragraph indentation.

## Styling

Rendering is GitHub-flavored. Fenced code flows as one continuous block: tight
line spacing, zero paragraph spacing between code lines, and a 12pt horizontal
inset so the text sits inside the unified code box. The box background is not a
text attribute — it is drawn as a page decoration behind the code (inline code
spans keep their subtle background chip). `SPDFMarkdownTheme` in
`SPDFMarkdownDecorations.h` exposes the shared box/rule colors, both as
appearance-dynamic colors for the screen canvas and as the concrete light
palette used on paper. `SPDFMarkdownRenderOptions.fontScale` (clamped to
[0.5, 3.0]) uniformly scales fonts and vertical spacing without touching indent
constants or image budgets, and
`renderWithOptions:languageOverrides:workQueue:completionQueue:completion:` on
the facade re-renders with caller-supplied options without mutating the
document's stored ones.

## Code languages

The picker deliberately advertises only languages with dedicated offline
lexers: JavaScript, JSON, Markdown, Python and Swift. Each lexer has its own
comment/string/number/keyword or markup grammar. Rules run in precedence order,
and accepted token ranges cannot overlap, preventing later token classes from
corrupting strings or comments. Missing/unknown fences remain uncolored and can
be assigned through `SPDFMarkdownLanguagePickerModel`.

## Pagination and drawing

`SPDFMarkdownPaginator` asks TextKit for real line fragments at the target
printable width. A page fragment always carries an exact attributed character
range for one complete TextKit line plus its x, baseline and page offsets.
There is no proportional range splitting or arbitrary pixel clipping.

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
across pages gets one box per portion), and a 1px underline rule beneath level
1 and 2 headings.

Use `A4PortraitConfiguration` for export or build a configuration from the
selected printer's paper and printable rectangle. Save as PDF, preview and
Print should all use the same `SPDFMarkdownPaginationPlan`. Its
`drawPageAtIndex:attributedString:inContext:` method draws the decorations
first (concrete light palette: #F6F8FA/#D0D7DE code boxes, #D8DEE4 rules) and
then the exact planned ranges into any PDF/print Core Graphics context,
preserving vector/selectable text. Drawing resolves dynamic AppKit colors
through a concrete light print palette on white paper, so a dark application
appearance cannot produce white-on-white output.

## Compile and test

Compile `ext/md4c/md4c.c` as C. Compile this directory's `.mm` files as
Objective-C++ with ARC. Link Foundation, AppKit, CoreText and ImageIO.

```sh
portable/mac/tests/markdown/run-tests.sh
SPDF_MARKDOWN_SANITIZER_FLAGS='-fsanitize=address,undefined -fno-omit-frame-pointer' \
    ASAN_OPTIONS=detect_leaks=0 portable/mac/tests/markdown/run-tests.sh
```

The direct suite covers canonical search/selection correspondence after
structural content, input/path budgets, pathological nesting, CRLF/BOM/CJK and
emoji, language-specific non-overlapping tokens, local image attachments,
table alignment, exact interleaved list order, bounded image memory, pinned-root
replacement between parse and render, large-search cancellation and long-query
rejection, exact TextKit ranges, the 75% rule, callout pagination, over-tall
content scaling, code-box/heading-rule decoration geometry (including blocks
split across pages), font scaling, and PDFKit/raster probes for selectable
text, concrete print colors, the filled code-box background, and image
containment within its line fragment.

## Recommended Makefile fragment

Do not copy this blindly into a differently named build graph; it documents the
required source/link/test shape for the later integration change:

```make
MARKDOWN_C := ext/md4c/md4c.c
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
