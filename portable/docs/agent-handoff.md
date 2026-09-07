# Agent handoff — how this codebase works and how to work in it

Written 2026-09-08 after a long run of releases (26.9.1-1 → 26.9.7-1). It is the
document I wish I had had on day one: the shape of the code, the reasons behind
its rules, where the tools are, and the traps that cost hours. Read `AGENTS.md`
first (the rules), then this, then the deeper docs it points at.

- [What you are working on](#what)
- [Philosophy — the rules and why they exist](#philosophy)
- [Architecture map](#architecture)
- [Mechanisms you will touch](#mechanisms)
- [Tools and commands](#tools)
- [The release pipeline](#release)
- [Working with the owner](#owner)
- [Traps, each one paid for](#traps)
- [Open threads](#open)
- [First hour checklist](#first-hour)

## <a id="what"></a>What you are working on

ShenzhenPDF: a native macOS reader (AppKit, Objective-C++) for PDF and Markdown,
on a portable C core wrapping MuPDF. A GTK4 Linux frontend and a native Win32
frontend (`portable/win/`, in progress on a separate track, no binary shipped)
share the core and the on-disk formats. The inherited SumatraPDF tree in `src/`
is legacy and not built. The product is described in `readme.md` (short) and
`docs/features.md` (exhaustive — keep it current when you ship a feature).

The owner uses the app all day on the same Mac you run on. Everything below is
shaped by that fact.

## <a id="philosophy"></a>Philosophy — the rules and why they exist

**The file-size ratchet is the codebase's immune system.** `tools/check-file-sizes.sh`
enforces 500 lines per maintained source file; 501–1000 needs an `exception`
entry with a justification in `tools/file-size-limits.tsv`; anything larger is
`legacy` with an *exact* cap that may only shrink. Several files sit exactly at
their cap (`ShenzhenPDFMac.mm` at 16494, `SPDFMacDelegatePrivate.h` at 642,
`SPDFMacUIHelpers.mm` at 744). Adding one line to those means removing one, and
the sanctioned way to pay is **extraction**: move a coherent unit into a new
file and lower the cap in the same change. Never raise a cap to pass. This is why
the mac frontend is ~90 small files and categories rather than one coordinator.
Read `tools/file-size-limits.md`.

**Every fix ships with a test that fails on the old code.** Prefer a pure
function you can call headlessly (see `SPDFMacFitGeometry.h`,
`SPDFMacSidebarOutline.mm`, `SPDFMacPageWheel.mm`, `SPDFMacMarkdownCopyText.mm`)
over UI plumbing. When the cause is a call that must exist in the coordinator, a
**source-contract test** that asserts on the coordinator's source text is the
accepted fallback (see `SPDFMacTabStateTests.mm`). Before claiming a test bites,
run it against the pre-fix code (`git show HEAD:path > /tmp/old.mm`, compile
against that).

**Comments say WHY.** Every non-obvious line carries the failure that motivated
it, often with the measured numbers. Match this. Lines are ≤120 columns; the
repo has a `.clang-format` but it does not cover Objective-C, so format by hand.

**Rendering is deterministic and explicit.** Theme variants, render options and
page configurations are passed as parameters; colours in rendered output are
concrete sRGB constants; screen, print, export and copy-page draw from the same
plan. Exports never carry the dark theme. See `portable/mac/markdown/README.md`.

**Speed is a requirement, not a feature.** Nothing new runs on the launch path;
a feature costs nothing for documents that do not use it. Measure with
`SPDF_LAUNCH_PROFILE=1` (phase timings to stderr). Current reference: first
window on screen ≈170 ms; a restored second window is a second process and now
starts alongside the first.

**Extraction over cleverness, and pictures over prose.** The readme is
picture-first; a feature earns a cropped screenshot, not a paragraph.

## <a id="architecture"></a>Architecture map

```
portable/core/        C: MuPDF wrapper (shenzhen_pdf_core.c), recolor (dark theme luma remap),
                      selection, YAML state codec, and the Windows-side Markdown C engine.
portable/mac/         AppKit app. ~90 .mm files. Entry: ShenzhenPDFMac.mm (the "coordinator",
                      class ShenzhenMacDelegate — app delegate + window controller + reader).
portable/mac/markdown/ The Markdown engine: parser (vendored MD4C + Gumbo), renderer to one
                      canonical NSAttributedString, paginator onto A4 sheets, native vector
                      diagrams, math typesetter, themes. Pure; no AppKit views.
portable/linux/gtk4/  GTK4 + libadwaita frontend on the same core and YAML files.
portable/win/         Native Win32 + Direct2D frontend (another agent's track; see its docs).
portable/release/     Release pipeline library and its tests.
portable/docs/        Journals, plans, this file, releases/<tag>.md notes.
tools/                Ratchet checker + tests.
```

### The coordinator and its categories

`ShenzhenMacDelegate` is declared in `SPDFMacDelegatePrivate.h` (ivars — capped)
and implemented across `ShenzhenPDFMac.mm` plus many `ShenzhenMacDelegate (X)`
categories, one per concern: `SPDFMacTabViewState` (a tab's view state becoming
the window's live state), `SPDFMacSidebarChapters` (chapter nesting + the
expand/collapse control), `SPDFMacWindowPlacement` (window frames across
displays, spawning sibling windows), `SPDFMacReadingThemeIntegration` (the one
dark-theme preference driving PDF recolor and the Markdown palette),
`SPDFMacLaunchPrerender` (speculative first-page render during launch),
`SPDFMacMarkdown*Integration` (routing Markdown tabs into the same chrome).
New coordinator behaviour goes into a category or a pure helper, never into the
big file.

### Two document paths, one chrome

- **PDF/XPS/EPUB/…**: `SPDFDocumentView` (`SPDFMacDocumentView.mm`) draws
  pre-rendered page bitmaps; zoom re-renders; `SPDFDocumentClipView` carries the
  page-aware scroll locks. Rendering pipeline, queues, crop regime, minimap:
  `portable/docs/architecture.md` — read it before touching any of that.
- **Markdown**: `SPDFMacMarkdownSession` owns a document's render + plan and its
  `SPDFMacMarkdownPagedView` (an `NSScrollView` whose zoom is `magnification`)
  around `SPDFMacMarkdownPageCanvas` (draws the plan with CoreText, live). The
  canvas is split into categories: `+Copy`, `+Cursor`, `+Decorations` (link
  rects, code-box controls), `+Navigation`, `+Pan`, `+Search`, `+Focus`. The
  paged view's fit logic lives in `SPDFMacMarkdownPagedView+Fit.mm`; its ivars
  are in `SPDFMacMarkdownPagedViewPrivate.h` so categories can reach them.

### The canonical string (Markdown)

`SPDFMarkdownRenderedDocument.attributedString` is the ONE coordinate space for
selection, search, links, pagination. It already encodes structure: `\n` after
every block and table row, `\t` before every table cell, list markers as text.
The **renderer records a rendered block per table ROW, never per cell** — cells
own the inline runs but have no rendered range. Anything walking blocks must
inherit the nearest recorded ancestor's range (see `SPDFMacMarkdownView.mm`).
Click destinations are stamped as `SPDFMacMarkdownDestinationAttribute` on the
"interactive string" (`SPDFMacMarkdownInteractiveString`), not `NSLinkAttributeName`.

### State on disk

`~/Library/Application Support/ShenzhenPDF/` (override with `SPDF_STATE_DIR`):
`settings.yaml`, `session.yaml` (windows → tabs; one entry per window with
`frame`, `selectedTab`, `focusedAt`), `documents.yaml` (per-file memory keyed
by standardized path: panels, collapsed chapters, Markdown orientation, page
geometry), `favorites.yaml`, `bookmarks.yaml`. Human-readable, hand-editable
while the app is closed. `spdf_dictionary_from_tab` / `spdf_tab_from_dictionary`
in `SPDFMacModels.mm` are the ONLY tab codecs — a second inline writer once
silently dropped a field for a release.

### Windows are processes

A multi-window session restores as **one process per window**: the process that
activates takes the window with the newest `focusedAt` and relaunches the others
with `--restore-window <id>`. Consequences: `applicationShouldTerminate`
**cascades** (quitting one instance terminates every other ShenzhenPDF process,
including a capture instance you launched), each process writes only its own
session entry under `session.lock`, and a window is "key" inside its own process
even when the app is not active (hence `NSApp.isActive &&` on the focus stamp).

## <a id="mechanisms"></a>Mechanisms you will touch

- **Exact-viewport fit.** Fit zooms are computed against the raw clip size; the
  decorative canvas inset collapses at exact fit (`SPDFMacFitGeometry.h`, pure,
  shared by both views). A fit also *places* the current page: centered where it
  fits, flush at its top where taller (`spdf_mac_fit_scroll_origin_y`,
  `alignCurrentPageAfterFit`).
- **Markdown magnification.** The clip view's bounds are in unmagnified document
  units. Any pointer delta must be divided by `magnification`; any scroll origin
  must land on a device pixel or live text wobbles (`SPDFMacMarkdownClipView`).
- **Option + wheel = page arrows.** `SPDFMacPageWheel.mm`, distance-based so
  LinearMouse-style precise deltas page at the right rate; routed from
  `SPDFWindow -sendEvent:` so pointer location does not matter.
- **Chapter nesting** is modelled on table rows (`level`), not an
  `NSOutlineView`; collapsed keys are positional (`"0.2.1"`) in `documents.yaml`.
  Removing a segment from the sidebar `NSSegmentedControl` clears its selection
  to −1 — `spdf_sidebar_mode_control_set_segment_count` guards that.
- **Copy.** PDF copy collapses whitespace (line breaks are visual wraps).
  Markdown copy must not: `SPDFMacMarkdownCopyText` keeps blocks, rows, tabs, and
  applies the transform only inside a cell.
- **Reading theme.** One byte, `_darkReadingTheme`, read on background queues;
  changes bump the render generation. PDFs are luma-remapped in the core with
  chroma kept; Markdown swaps to a concrete dark palette; the minimap has its own
  variant. Print/export/copy-page never carry it.
- **Launch prerender.** Starts in `main()` before `applicationDidFinishLaunching`,
  reads `settings.yaml` early, speculates on the session's focused window's
  selected tab, bails for Markdown and cloud paths. Ownership state machine in
  `SPDFMacLaunchWorkPolicy.mm`. Disable with `SPDF_DISABLE_LAUNCH_PRERENDER=1`.

## <a id="tools"></a>Tools and commands

```sh
make -C portable mac-app                 # builds dist/ShenzhenPDF.app (ad-hoc signed)
make -C portable <name>-tests            # one suite; names: grep -oE '^[a-z0-9-]+-tests:' portable/Makefile
make -C portable mac-markdown-tests      # engine suites (mac/tests/markdown/run-tests.sh)
                                         # + UI suites (mac/tests/run-markdown-integration-tests.sh)
./tools/check-file-sizes.sh              # the ratchet; tools/test-file-size-ratchet.sh self-tests it
./portable/cut-release.sh --dry-run|--prepare-only "summary"|--publish
```

Test suites are plain executables under `portable/mac/tests/` (and
`tests/markdown/`); each prints `<Name> passed` and exits 0. **Judge by exit
code**, never by grepping for "passed". Adding a UI suite means adding it to the
`TESTS` list in `run-markdown-integration-tests.sh` and, for a new source file,
to that script's `SOURCES`; the app itself globs `mac/*.mm`, so new sources need
no Makefile change. `make` skips a rebuild when source and binary share the same
mtime second — `rm -f build/<Test>` before trusting a rerun.

Env switches: `SPDF_STATE_DIR` (private state for experiments), `SPDF_NO_ACTIVATE=1`
(do not steal focus), `SPDF_LAUNCH_PROFILE=1`, `SPDF_DISABLE_LAUNCH_PRERENDER=1`,
`SPDF_RENDER_WORKERS`, `SPDF_DIAGRAM_LAYOUT_DEADLINE` (tests raise the diagram
budget so they are not timing-dependent).

Headless probes beat launching: compile a throwaway `.mm` against the sources
the test script lists, print geometry, delete it. If you must capture the app
(only when asked): scratch `SPDF_STATE_DIR`, your own copy of the bundle, find
the window by owner pid (CGWindowList), `screencapture -l <id>`, and end the
instance with `kill -9 <pid>` — never Cmd+Q (the cascade) and never `pkill`.

## <a id="release"></a>The release pipeline

Versions are `YY.M.DD-BUILD`, date of the *prepare*; a build number is spent
only when its tag reaches origin. Flow:

1. Write `portable/docs/releases/<tag>.md`: highlights above one `---` (≤500
   chars, direct, one line each), detail bullets below. The owner reads the
   highlights before every release — show them first.
2. `./portable/cut-release.sh --prepare-only "summary"`: validates the notes,
   runs every `*-tests` target (35 at the time of writing), enforces the README
   gate (`readme.md` must change for a feature release; a pure bugfix sets
   `SPDF_README_UNCHANGED=1` deliberately), commits the metadata. The working
   tree must be clean except for the notes file.
3. `./portable/cut-release.sh --publish`: reruns the tests, clean release build,
   Developer ID signing, notarization, DMG, then an **atomic push of master and
   the tag** — the point of no return. It is rejected if origin moved; merge
   `origin/master`, delete the stale local tag it left, publish again. Other
   agents push to master constantly (the Windows track), so check
   `git log master..origin/master` right before both prepare and publish.

The script blocks on nothing — if it seems hung, the shell is (see traps). Poll
`pgrep -f cut-release.sh` and read its log; never sit on a 600 s timeout.

## <a id="owner"></a>Working with the owner

- **Same Mac, same screen.** Do not launch the app while they are testing; when
  they say "let me test", build and hand over. They will tell you what they see.
- **Never `--publish` without a fresh, explicit yes** for that exact build. "Make
  a release" authorizes the prepare; "publish" authorizes the push. Approval for
  one build does not carry to the next.
- **A reported bug is a fix request.** Diagnose, fix, test, then report — do not
  stop at the diagnosis. If you cannot reproduce, say so with the evidence and
  what you ruled out; do not guess a fix.
- **Be direct and brief.** Release notes and reports in plain language, no
  hedging, numbers only when they change a decision. They asked for "one picture
  is better than a thousand words" in the readme.
- **Stage explicit paths, never `git add -A`.** Other agents share the worktree.
  Commit each tested change set with a message that explains the failure and the
  fix; end with `Co-Authored-By`.
- Their shortcut tooling: LinearMouse is installed (wheel deltas arrive as
  precise deltas), two displays (built-in Retina main + external 3440×1440 at
  1×), Shenzhen Files as file manager.

## <a id="traps"></a>Traps, each one paid for

- A Bash command that produces no output for minutes is a **shell blocked on a
  prompt**, not a slow build — `~/.zshrc` once asked "[oh-my-zsh] Would you like
  to update?" (now `zstyle ':omz:update' mode auto`). Check
  `pgrep clang|make|codesign` before waiting.
- A **multi-line regex** stripping debug lines deleted four load-bearing lines
  of window setup and shipped. Delete code with exact-string edits only.
- `initWithContentRect:` takes a content rect and AppKit repositions oversized
  windows during init; apply saved frames after the style mask is final, and
  never persist a fallback position over the one the reader left.
- A hidden `NSScrollView` does not scroll (tests fail mysteriously); use
  `alphaValue = 0` for a pre-rendered swap.
- `NSScreen.screens` may omit a sleeping display early in launch.
- Reusing an expired deadline for a second layout pass made diagrams vanish.
- The README gate's `grep -q` tail SIGPIPEd under `pipefail` on large diffs and
  rejected exactly the rewrite it should have passed (fixed; the lesson is: never
  end a pipeline in `grep -q` under `set -o pipefail`).
- A killed `--publish` can leave a **local tag** pointing at the old commit; the
  next publish refuses until you `git tag -d` it.
- The prepare's version is today's date: notes written yesterday under
  yesterday's tag are "changes outside the release notes" — rename the file.

## <a id="open"></a>Open threads

- **Markdown light-on-dark launch.** Twice on 2026-09-05 a restored Markdown tab
  rendered the light palette while the gutter, minimap and toolbar were dark;
  never reproduced in ten tries across the dev build, the shipped release binary,
  fresh state and a light→dark replay. If seen again: instrument
  `SPDFMacMarkdownIntegration.mm`'s session creation with the theme byte.
- **Markdown page restore with the minimap hidden** landed on page 1 once out of
  three runs; the other two were correct. Not understood.
- **Diagram labels carry no links** by design: mermaid `click` and flowchart.js
  `:>url` are dropped in the parser. A small feature if wanted.
- Markdown chapters are H1–H3 only; `<details>` always renders expanded;
  footnotes unsupported.
- GTK frontend: a dead copy gate remains at `portable/linux/gtk4/spdf_window.c`
  (copying is always allowed now).
- The Windows track (`portable/win/`, `portable/docs/windows-*.md`) is another
  agent's; coordinate through master, do not edit its files.

## <a id="first-hour"></a>First hour checklist

1. `git fetch && git log --oneline master..origin/master` — someone else has
   probably pushed.
2. `./tools/check-file-sizes.sh` — know which files are at cap before editing.
3. `make -C portable mac-app` once, so incremental builds are fast (~2 min cold).
4. Read `portable/docs/architecture.md` §3–5 if you touch rendering or scrolling;
   `portable/mac/markdown/README.md` if you touch Markdown.
5. Find the test suite nearest your change and read one test in it — the style
   (headless, `Expect`, prints `<Name> passed`) is the contract.
6. Ask yourself where the line budget will come from before writing the fix.
