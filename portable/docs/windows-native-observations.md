# Windows Port — First Observations From a Real Desktop

Written 2026-09-01 on a **native Windows x64 desktop**, continuing from
`portable/docs/windows-port-handoff.md` (HEAD at handoff `19cb2f6a8`; this work
starts at `2a3afd434`).

The handoff's §0 said the thing that mattered most:

> **Nobody has ever seen a ShenzhenPDF window open on Windows.**

Somebody has now. This file is the evidence, written in the order the handoff's
§7 asked for it, and it corrects several claims that could only be checked by
looking.

---

## 0. The headline

**A ShenzhenPDF window opens on Windows, renders the page correctly, repaints on
resize, scales correctly on a fractional-DPI display, and exits 0.**

All five of Phase 1's done-criteria were listed as unobserved. All five now pass,
in **both** light and dark, reproducibly, by exit code:

```
portable\win\verify-phase1.ps1 -Exe <exe> -Pdf <pdf>          # 7 passed, 0 failed  exit 0
portable\win\verify-phase1.ps1 -Exe <exe> -Pdf <pdf> -Dark    # 7 passed, 0 failed  exit 0
```

And the strongest single result, because it retroactively justifies the port's
whole verification strategy:

> **The window's client area is BYTE-IDENTICAL to the headless compose path** at
> the same viewport and the same DPI scale — 0 differing pixels out of 816,912,
> in light and in dark.

`spdf_win_d2d.h`'s rule that `spdf_win_paint()` must never require an `HWND` was
taken on faith for the entire port. It is now measured: the offscreen pixel tests
really are evidence about the real window. Nobody could show that before, and
every pixel test in this repo was worth less until it was shown.

---

## 1. This is not the machine the port was written for

When this was written, everything in `portable/win/README.md` and the handoff
assumed an **ARM64** Windows 11 guest in Parallels, reached over `prlctl exec`,
with a toolchain in `C:\BuildTools` and MuPDF prebuilt in `C:\spdf-build\mupdf`.
None of that was true here. (`portable/win/README.md` has since been rewritten
native-first and the Parallels route moved to its own chapter; the handoff has
not, and should be read as history.)

| | Docs assume | This machine |
|---|---|---|
| CPU / target | Windows 11 **ARM64** (`AA64`) | **x64** (`8664`), AMD Ryzen 5 6600U |
| Toolchain root | `C:\BuildTools` | `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools` |
| MSVC | 19.44 / 14.44.35207, `HostARM64\arm64` | same toolset, `Hostx64\x64` |
| Windows SDK | 10.0.26100.0 present | **absent** — had to be installed |
| MuPDF libs | prebuilt, present | **absent** — had to be built |
| `make` | present on the Mac side | **absent** (installed: GNU make 4.4.1) |
| Display | unknown, assumed 1× / 2× | **144 dpi (150%)** — fractional |

Two consequences that change what the documents mean:

**The byte-identity claim was ARM64 ↔ ARM64.** §1.3's "the rendered page is
byte-identical to macOS, tolerance pinned at zero" was measured between an ARM64
Mac and an ARM64 guest. Reproducing it here would be **x64 ↔ ARM64**, which is a
different and unproven claim — SSE versus NEON float behaviour is a new variable,
and the existing `-ffp-contract=off` note (gotcha 19) is about exactly this class
of last-bit difference. **Do not assume the zero tolerance carries to x64 until
someone measures it.** Nothing in this session measured it, because it needs a
Mac.

**The fractional DPI is a gift.** The plan asked for "DPI scaling is correct on a
2× display". 150% is a *harder* test than 200%: it produces fractional layout and
fractional stroke widths, and it found a real defect that 1× or 2× would have
hidden (§4.1). macOS backing scales are only ever 1× or 2×, so this is a class of
bug the macOS source cannot warn you about.

### 1.1 New environment gotchas

Add these to `portable/win/README.md`'s numbered list rather than here.

- **`NoDefaultCurrentDirectoryInExePath=1` is set on this machine.** `cmd` will
  not find `foo.cmd` in the working directory; scripts must be invoked by
  absolute path or `.\foo.cmd`. Cost: one confusing "is not recognized as an
  internal or external command" for a file that was plainly there.
- **`vcvarsall.bat` prints `'vswhere.exe' is not recognized` on stderr here and
  still returns 0.** It is noise, caused by the item above. Judge it by exit code
  and by `VSCMD_ARG_TGT_ARCH`, never by its output.
- **`mupdf/generated/` is not needed on Windows at all.** The handoff (§2.3) and
  `mupdf-gen-ninja.sh`'s exit-70 guard imply it is a build input. It is not: it
  holds only the font and hyphenation hexdumps, which the Windows build replaces
  with bin2coff over the original binaries. Every *other* `generate:` target in
  `mupdf/Makefile` — 7 ICC headers, `util.js.h`, `css-properties.h`, and all 71
  cmap headers — is **already committed** and present. The guard's real job is a
  symbol cross-check, not a dependency.
- **Do not glob MuPDF's fonts.** There are **185** font binaries on disk; the
  Makefile embeds **181**. The four extras are CharisSIL *design sources*. `make -n`
  excludes them for free; a structural glob would have embedded 4 MB of the wrong
  thing.
- **Argument quoting bit twice, in two different tools.** PowerShell's
  `Start-Process -ArgumentList` does not quote for you, so a path containing
  spaces arrives as several arguments. This produced a VS installer that silently
  used `--installPath C:\Program`, and an app that "could not open the file" with
  exit 64 when the file was fine. Both were harness bugs wearing a product bug's
  clothes.

---

## 2. What the window actually looks like

Captured with `portable/win/screenshot-window.ps1` (new; see §5), at the macOS
default content size of 1120×800, on `what made apollo a success` (a NASA scan —
multi-page, image-backed, so it exercises the dark theme's scan path).

**Light.** The page is correctly fit to width, sharp, correctly positioned, on the
`#E0E0E2` surround. The document renders exactly as the headless path renders it.

**Dark.** The luma remap is visibly a remap and not an inversion — light ink on
dark paper with the page's own structure intact. Verified against the palette *in
a live window*, not in a unit test:

| Role | Measured in the window | Palette says |
|---|---|---|
| viewport gutter | `#121212` | `#121212` ✓ |
| page border, all four edges | `#333333` | `#333333` ✓ |
| page paper | `#1E1E1E` | `#1E1E1E` ✓ |

The OS title bar follows the theme (dark caption around a dark canvas), and the
title reads `apollo.pdf - Shenzhen PDF` — both of which were defects the handoff
listed and are now fixed.

### 2.1 The parity gap, seen rather than inferred

At first sight, placed beside `docs/images/portable/macos-main-window.webp`, the
Windows window was missing every piece of chrome the macOS app has. **That has
since been built** — tab strip, toolbar, sidebar and minimap now all draw, with
metrics transcribed from the macOS source and cited to the line, in both themes.

This section listed seven gaps when it was written. **Six of the seven have
since landed** (see §9 for the wave that closed them); the list is kept with
each item's disposition rather than deleted, because the ledger's value is that
it can be checked.

- ~~**Scrollbars.**~~ Landed in `099a68508`, with the search heat-map overlaid
  on them as macOS has it (`spdf_win_chrome_scroll.h`,
  `spdf_win_chrome_scrollbar.cpp`; `chrome_scroll_test`,
  `chrome_scroll_input_test`, `find_overlay_test` test_thin_marks).
- ~~**Find**, the regex checkbox, the match counter and the scrollbar
  heat-map.~~ Landed in `099a68508`, ported from
  `portable/linux/gtk4/spdf_search_internal.h` exactly as predicted and
  differentially tested against it — 37,440 comparisons, 0 differ
  (`search-differential-native.cmd`). Regex multiline is a real toggle since
  `95f1b1433`.
- **The Comments sidebar section** is still missing: Windows draws a "No
  Comments" placeholder and the core's annotation API has no caller. **OCR and
  translate landed** in `d52fadc22` (toolchain, jobs, panel, glue), with the
  first real installs' lessons in `1c5b5ddf3` and `443ee4603`.
- ~~**Menus and a command palette**: no `HMENU`, no accelerator table.~~ Menus
  landed in `86ae70cf3` as a popup from the toolbar's `…` — deliberately not a
  menu bar, because a Win32 bar cannot be themed (§4.7). The palette, Open
  Recent, reopen-closed and favorites landed in `f30842fdb`, with the filter and
  ranking ported from GTK and differentially tested (`54b9f9a64`).
- ~~**Open a file**: still command line only.~~ Landed in `86ae70cf3`
  (`IFileOpenDialog`, `WM_DROPFILES`, the `+` button and the overflow `…` now
  routed to real handlers). `.pdf` registration and the shell commands landed in
  `85ba7fad5`.
- ~~**The tab strip lives below the caption, not inside it.**~~ Hoisted: the
  client now owns `WM_NCCALCSIZE` and `WM_NCHITTEST` and paints its own caption
  buttons (`spdf_win_window_caption.h`, `spdf_win_chrome_caption.h`;
  `chrome_nc_test` 5,552 hit checks, `chrome_caption_paint_test`). The window has
  one header band, as macOS does. What remains is cosmetic — see §7 item 1.
- **Selection, links, printing** all landed (`86ae70cf3`, `e8cba79fa`), each with
  a differential against its original: selection 50,171 comparisons / 0 differ,
  print maths 1,944,132 / 0 mismatches. **Annotations are still untouched** and
  are the largest remaining reading gap; they also block the Properties dialog's
  comment count, which is passed as 0.

### 2.2 One thing the ledger did not mention

**The initial window size is driven by page 0's dimensions, and it is wrong for
small pages.** `initial_client_size()` (`spdf_win_main.cpp:242-252`) uses the
page size plus margins. Opening the 200×260 pt `golden.pdf` fixture produced a
**244×286** window — smaller than the caption buttons need, so Windows clipped
them. macOS instead opens at a fixed `1120 × 800` with a `560 × 380` minimum
(`ShenzhenPDFMac.mm:2912-2938`, `:69-70`) and clamps a restored size into
`[560 … min(2200, screenW−40)] × [380 … min(1600, screenH−40)]`.

Windows applies **no minimum at all**. This is a parity gap and a usability bug,
and it is only visible if you open a small document — which no headless test does.

---

## 3. Test results, natively

`portable/win/tests/run-tests-native.sh` — new, because `run-tests.sh` is a
macOS-side orchestrator that drives `prlctl`.

As measured in this session (2026-09-01):

```
37 cases, 29 passed, 0 failed, 8 blocked        exit 2 (BLOCKED is not a pass)
```

**That count is a snapshot and has moved twice since.** The audit in
`windows-feature-matrix.md` recorded 56 cases at `5677cc628`, and the parity wave
of 2026-09-02 (§9) took the inventory to **86** — `bash
portable/win/tests/run-tests-native.sh --list`, which needs no build and is the
only number worth quoting, because a track that drops
`tests/<name>_test.c` in the directory registers a case without touching the
runner. Do not copy a case count into another document; cite `--list`.

Newly passing here and previously registered nowhere: **all five orphaned core
suites** — `SPDFCoreOutlineTests`, `SPDFCoreRenderThemeTests`,
`SPDFCoreSelectionTests`, `SPDFCoreCJKSelectionTests` pass;
`SPDFCorePasswordTests` is BLOCKED only because it needs `qpdf` to generate
encrypted fixtures (`winget install qpdf.qpdf`). The handoff called this "the
cheapest outstanding win in the port"; it was. `CORE_SUITES` now registers
**nine**: the Markdown track added `SPDFCoreMarkdownTests`, which needs no MuPDF
at all.

The 8 blocked cases are honest blocks, each naming its missing prerequisite:
`layout.differential` needs glib and the GTK4 headers; the 7 cross-host PNG cases
need a **macOS host**, because `d2d-cases.sh` and `probe-cases.sh` do not compare
against committed references — they **compile the reference probe with `cc` on the
Mac at test time**. There is no committed reference image anywhere in
`portable/win/tests/`. (`portable/docs/windows-captures/` holds live screenshots, but
they are a RECORD, not test references -- a chrome screenshot pins four
subsystems at once and would fail for reasons unrelated to whatever changed.) Any plan to run the port's strongest evidence off a Mac has
to commit references first.

`layout.differential` no longer needs a Mac: §4.4's shim closed it, and
`portable/win/tests/layout-differential-native.cmd` runs it natively. It stays in
`CROSS_HOST` because the runner's own `layout.differential` case is the
macOS-driven one; the native script is the substitute and reports 395,514
comparisons, 0 mismatches. So the structural block on this box is **seven
cross-host cases plus the password suite**, and a complete run exits 2 even with
everything built.

### 3.1 Salvaging the Direct2D cases without a Mac

The four `d2d.*` cases' reference is just "a correct render of this page produced
without Direct2D" — and `spdf_win_probe.c` is portable C with zero Direct2D
references. So the same comparison runs entirely on Windows: probe (core → PNG)
versus the app (core → D2D → WIC → PNG). Four new cases, `d2d.compose-*`, all
byte-identical under `--strict` at tolerance 0.

They are **deliberately named differently**. They prove strictly less than the
cross-host cases — they cannot catch a Windows-vs-macOS divergence — and letting
a weaker test inherit a stronger one's name is how this repo's documents drifted
in the first place. Both sets are listed; the cross-host four stay BLOCKED.

### 3.2 A latent failure in the existing macOS-side `d2d.window-dark`

Found while checking whether the dark-theme fixes broke anything, and it matters
to whoever next runs `run-tests.sh` **from the Mac**:

`d2d_window_case` crops the composed canvas frame to page 0's printed `dest` rect
and compares it against a bare, chrome-free core render. macOS's dark theme
deliberately draws its page border **inside** that rect. So the moment the
Windows build draws the dark page border — which it now does, correctly — that
case must fail, in exactly the page's outermost ring.

Measured on a synthetic 40×40 page: **156 of 1600** pixels differ in dark, 0 in
light, and 156 is exactly the 1-pixel perimeter. This is a flaw in the case's
design, not in either renderer. `d2d-cases.sh` was **not** modified. The native
substitute handles it by asserting the frame is uniformly the colour the theme
declares and then comparing the interior — so the border is *tested*, not
tolerated. The macOS-side case needs the same treatment.

---

## 4. Defects found by looking, and fixed

The five the handoff named in §7.5 are all done and all verified in a live window
(§2). Two more were found by looking, both invisible to every existing test.

### 4.1 The dark page border blurred at fractional DPI

`draw_canvas_page()` drew the border with `strokeWidth = 1.0f * dpi_scale`. At
150% that is **1.5 device pixels**, which cannot land on the pixel grid however
it is inset: it covered one full row and half of the next, and the half-covered
row came out `#282828` against `#1E1E1E` paper. A blurry hairline where the whole
point of the hairline is crispness.

Fixed by rounding the stroke to whole device pixels. Measured after: rows 13 and
14 are both exactly `#333333`, row 15 exactly `#1E1E1E` — no blended row.

macOS cannot warn you about this. AppKit backing scales are 1× and 2×, where a
1 pt `lineWidth` is already 1 or 2 whole pixels. Windows' 125/150/175% steps are
why it needs saying, and it is the second time in this file that a Windows-only
DPI step has produced a defect (the first being §1's whole framing).

**An honest correction about how this was diagnosed.** I first attributed the
blur to the GPU window target (`D2D1_RENDER_TARGET_TYPE_DEFAULT`) rasterising
strokes differently from the headless SOFTWARE target. That was wrong. The real
cause of the *discrepancy* was my own comparison: I was rendering the headless
reference at `dpi_scale = 1.0` and comparing it against a `1.5` window, and the
border width is legitimately DPI-scaled. Page **layout** is DPI-independent here
(`dpi_scale` reaches only the LRU key and "actual size"), which is why the flawed
comparison passed for a long time and then failed only in dark — in light the
shade band falls outside the visible page rect on a tall page. A comparison that
passes in one theme and fails in the other looks exactly like a dark-theme bug.
`verify-phase1.ps1` now passes `--dpi` to the headless render, and the fix above
stands on its own merits: the 1.5 px stroke really did blur on screen.

### 4.2 No minimum window size

See §2.2. Not fixed in this session; filed here so it is not lost.

---

### 4.3 GPU and software Direct2D do not agree on resampling

Measured while checking the chrome against the headless compose, and it changes
what the port's pixel tests can be said to prove.

The window paints into an HWND target created with
`D2D1_RENDER_TARGET_TYPE_DEFAULT` (GPU). `spdf_win_render_scene_to_png` uses
`D2D1_RENDER_TARGET_TYPE_SOFTWARE`, deliberately, because the harness host may
have no display adapter. Where `DrawBitmap` resamples, the two rasterisers'
bilinear filters do not agree bit-for-bit, and disagree more the further the
scale is from 1:1:

| case | differing | max delta | MAE |
|---|---|---|---|
| 1426 px bitmap into a 1425.6 px slot | 0.76% | 2 | — |
| ~1000 px bitmap into a 208 px canvas | 11.2% | 43 | 0.60 |

Established rather than assumed: two runs of the same **window** are
byte-identical to each other, two runs of the **headless** path are
byte-identical to each other, and every differing pixel lies inside the page
bitmap — the gutter above it matches exactly, 0 of 2704 px.

**What this does and does not affect.** Every zero-tolerance case in this repo
compares SOFTWARE against SOFTWARE (`spdf_win_probe` versus
`--render-window-png`), so all of them are unaffected. What they do **not**
certify is the GPU window's resampled pixels. `verify-phase1.ps1` therefore
decides on MAE ≤ 1.0 with a max-delta ceiling, and says so in the script: a wrong
zoom, origin, fit mode, theme colour or a stale texture moves the mean by tens,
which is two orders of magnitude above the noise.

### 4.4 A "needs glib" block was softer than it looked

`layout.differential` has always been BLOCKED with "needs glib and the GTK4
headers". That is true of glib the **library** and not of the two pure headers
this port transcribes: they need typedefs, `MAX`/`MIN`/`CLAMP` and
`g_new0`/`g_free` and nothing else.

A shim supplying exactly those — with glib's own macro bodies character for
character, because the comparison order at the edges is part of what is being
checked — lets the **real** `portable/linux/gtk4/spdf_minimap_internal.h`
compile under MSVC beside the port in one binary: **131,503 comparisons, all
identical**, across strip layout, median/scale, hit-testing, both
document↔strip mappings, the viewport rect and the marker ticks. Same compiler
on both sides, so a difference could only be a transcription error.

`portable/win/tests/glib_shim/glib.h` is that shim. The same trick should
unblock `layout.differential` itself.

### 4.5 `verify-phase1.ps1` is sensitive to the saved session

`%APPDATA%\ShenzhenPDF\session.yaml` remembers the page each tab was on. The
window restores it; the headless reference renders page 0. So a session left
behind by earlier clicking makes the two legitimately disagree, and it presents
as three real failures with large deltas. Delete the session before a run, or
accept that the first run after any interactive poking is meaningless.


### 4.6 A locked workstation looks exactly like a broken window

The most convincing false positive this port has produced, and it cost a second
investigation after §5.1's.

Windows does not composite a locked session. The DWM-drawn title bar still
appears in a capture, because DWM has it cached, but a Direct2D client area
backed by a GPU surface does not: `PrintWindow` returns black or stale pixels,
and `CopyFromScreen` returns black for the **entire screen**.

What that presents as: the window paints nothing, `verify-phase1` reports three
hard failures with enormous deltas, and **it reproduces** — including from a
clean build of a known-good commit in a throwaway worktree. Commit `640ee4c3d`,
measured at 7 passed / 0 failed earlier the same day with a correct screenshot,
produced an identical black frame once the machine locked.

The tell was in hand the whole time and was misread as a curiosity: **the
offscreen compose of the very same binary stayed perfect.** Under this port's
own central rule — `spdf_win_paint()` needs no desktop — that is evidence *for*
the app, not a detail beside the failure. A regression that predates the commit
that supposedly caused it is not a regression.

There is an irony worth keeping. The entire reason nobody had ever seen this
window is that `prlctl exec` runs in a session with no interactive desktop. This
machine has one — until it locks.

Both scripts now refuse to lie about it. `screenshot-window.ps1` checks for
`LogonUI` **before** launching the app and exits **68**; `verify-phase1.ps1` maps
68 to BLOCKED for the whole run. A pixel backstop covers the cases `LogonUI` does
not name (disconnected RDP, a sleeping display, a GPU reset), and it samples the
**client** area rather than the framed window — because that distinction is
exactly what defeated the first attempt at the guard: with the title bar
composited and the client blank, the whole-window count was 7 distinct colours
and passed a naive uniformity test while the client area was 2.

Neither check can turn a bad frame into a pass. They only ever turn a FAIL into
a BLOCKED, which is the distinction the harness's BLOCKED convention exists for.

**Confirmed by unlocking.** The same commit, on the same machine, an hour later
with the workstation unlocked:

```
phase1[light]: 7 passed, 0 failed, 0 blocked   exit 0
phase1[dark]:  7 passed, 0 failed, 0 blocked   exit 0
```

Black while locked, green while unlocked, nothing changed in between. That closes
the diagnosis rather than leaving it as a plausible story, and the live captures
in portable/docs/windows-captures/ were taken in the same session.


### 4.7 Four defects only a person using the app could report

Reported 2026-09-02 from actual use, after every automated check in this port was
green: *"cannot be focussed or interacted with; runs from a terminal window that
stays open; does not respect the system theme; a double top bar like it's a
window inside of a window."* None of the four is visible in a `PrintWindow`
capture, which is why they survived.

**The terminal window.** The exe was linked `/SUBSYSTEM:CONSOLE` — confirmed by
reading the PE header (`Subsystem=3`) — because the entry point is `main()` and
no subsystem was ever specified. Now `/SUBSYSTEM:WINDOWS /ENTRY:mainCRTStartup`,
for the app only; the test binaries stay console programs because a harness reads
their output. stdout still reaches a pipe or a file (subsystem controls only
whether a console is *allocated*), verified both ways before trusting it.

**The system theme.** This machine is set to dark and the app shipped light
unless told otherwise. It now reads `AppsUseLightTheme`. The ordering mattered
and was got wrong once: the canvas takes its render flags at construction, so
applying the theme after `spdf_win_tabs_app_show()` left the pages light while
the caption and thumbnails went dark. Headless paths deliberately do **not**
follow it, or every pixel comparison would depend on the developer's registry;
`--dark` and `--light` both override.

**The double top bar.** Half of it was a Win32 menu bar, which **cannot** be
themed: `SetPreferredAppMode(AllowDark)` darkens popup menus but not the bar,
measured — it stayed white between a dark caption and dark chrome. macOS keeps
its menus in the system menu bar, so an in-window strip was a bar macOS never
had; it is gone, and the toolbar's `…` opens the same menu. The other half is
the OS caption above the tab strip — macOS puts the strip *inside* the title bar
— and that integration is a separate change.

**"Cannot be focussed"** was not the app. Every measurement said healthy —
responding, enabled, answering `WM_NULL`, a `PostMessage`'d click toggling the
sidebar — yet physical clicks did nothing. `WindowFromPoint` across the app's
rect returned the **Claude desktop app** every time: maximized, foreground, and
the *parent* of the automation that launched the app, so the window opened
behind it and every real click landed on Claude. `PostMessage` and `PrintWindow`
ignore z-order, which is exactly why the automated evidence lied. Same session,
same user, same integrity, same desktop — the launch *parent* was the problem,
not the launch context. The real-world path (double-click the exe) has no such
parent, and was impossible: the app exited 64 without a document. It now
launches bare, restoring the session or opening an empty window.

Two harness lessons from the same afternoon: PowerShell's `&` does not wait for a
GUI-subsystem process, so `verify-phase1` silently compared the whole client and
failed three criteria with no error message; and a stray-process check that
counts by *name* fails whenever the user has their own instance open. Both fixed.


### 4.8 The phantom second: launch is ~50 ms, the tool that timed it was not

Setting out to make launch "feel instant", the first measurement said the
app took a constant ~1.0 s to do anything headless: `--render-png` on a
1.8 KB two-page fixture, `--render-window-png --chrome`, even a *missing
file* all came in at 1,011-1,029 ms, while the window itself appeared in
45-88 ms. A constant that survives removing the document is not document
work; the suspicion was a fixed wait at exit.

It was neither. The runs were timed with PowerShell's
`Start-Process -Wait -RedirectStandardOutput`, and that cmdlet adds about a
second of pipe teardown to every process it waits for. Polling
`$p.HasExited` instead, with `t0` taken before launch (`$p.StartTime` is
invalid once the process is gone):

| path (warm, published build) | polled |
|---|---|
| usage text and exit 64 (no factory, no MuPDF) | 30 ms |
| `--render-png` golden.pdf, PNG on disk and process gone | 57-124 ms |
| window visible, outline.pdf | 45-88 ms |
| WM_CLOSE to process gone | 16-39 ms |

So there is no stall to remove: process start to a visible window is a
few tens of milliseconds, an order of magnitude under the GTK profile's
769 ms `first-window-present` (`gtk4-captures/launch-profile.txt`) that
motivated Linux's resident mode. What is *not* yet measured is
launch-to-first-page-pixels: the ad-hoc PrintWindow sampler written for
it returned blank frames (the repo's `screenshot-window.ps1`, which makes
its host DPI-aware and waits for settle, is the capture path that works),
so the number the reader actually feels still needs an in-process
timeline. That is the launch track's first deliverable, not another shell
stopwatch.

The lesson generalises: two other tool-layer artefacts in the same
session produced false conclusions -- in Git Bash, `cmd /c` has its `/c`
rewritten to `C:\` by MSYS path conversion, so a build driver "succeeds
in one second" having run nothing (use `cmd //c`), and a `build exit=0`
read that way green-lit a commit that did not compile. Judge by an exit
code, yes -- but first make sure the exit code belongs to the program you
think ran.

## 5. New tooling, and why each exists

| file | why |
|---|---|
| `portable/win/screenshot-window.ps1` | Makes "look at the window" a command. `PrintWindow` with `PW_RENDERFULLCONTENT` (mandatory for a D2D client area), enumerates windows by pid rather than trusting `MainWindowHandle`, reports the client offset so a capture can be cropped to exactly what `spdf_win_paint` drew, and **always** closes the app it started. |
| `portable/win/verify-phase1.ps1` | Turns Phase 1's five criteria into one exit code. Compares the live client area against the headless compose at the same size *and the same DPI*. |
| `portable/win/build-native.cmd` | The native build the port never had. Discovers `portable/win/src/*`, lists `portable/core/*` explicitly, links MuPDF when present. |
| `portable/win/tests/run-tests-native.sh` (+ `.lib.sh`, `.d2d.sh`) | The harness, natively. Honours the in-file `spdf-test-*` directives, registers the five orphaned core suites, BLOCKS rather than skips. |
| `portable/win/mupdf-gen-ninja-native.sh`, `mupdf-native-build.cmd`, `mupdf-arch-check-native.cmd`, `mupdf-native-linkcheck.c/.cmd` | MuPDF for x64, still derived from `mupdf/Makefile`'s own recipe via `make -n` so both hosts compile the same MuPDF. 646 translation units in 14 flag groups, 417 + 229 objects — the same counts as the ARM64 build. |
| `portable/win/src/spdf_win_tabstrip.h` + `tests/tabstrip_geometry_test.c` | Tab-strip geometry transcribed from `SPDFMacTabStripView.mm` and `SPDFMacTabStripGeometry.h`, toolkit-free and header-only, 741 assertions. |
| `portable/win/src/spdf_win_chrome*.{h,cpp}` + `tests/chrome_geometry_test.c` | The chrome itself: how the client area divides (3807 assertions), the theme, the painters (strip / toolbar / sidebar / minimap), the model, the input router (94,240 assertions). All HWND-free, so `--render-window-png --chrome` composes the whole window offscreen. |
| `portable/win/src/spdf_win_minimap.h` + `tests/minimap_differential.c`, `tests/glib_shim/` | The GTK4 minimap geometry, ported and then differentially tested against the **real** GTK header under MSVC: 131,503 comparisons, all identical. See §4.4. |
| `portable/win/tests/layout-differential-native.cmd` | Runs `gtk_differential.c` natively — **395,514 comparisons, 0 mismatches**. This is the port's strongest test and had been BLOCKED as "needs glib" since the beginning. Proven to bite: perturbing the ported fit-width zoom by one part in 10⁷ gives 17 mismatches. The two `spdf_lru_*` halves stay skipped, because glib leaves hash iteration order unspecified and a shim would report mismatches that are not transcription errors. |
| `portable/win/src/spdf_win_search.*`, `spdf_win_chrome_find.*` + `tests/search_differential.c` | Find/search, with the GTK4 search header ported and differentially tested: 37,440 comparisons, 0 differ. |
| `portable/win/src/spdf_win_window_caption.h`, `spdf_win_chrome_caption.h` + `tests/chrome_nc_test.c`, `tests/chrome_caption_paint_test.c` | The client-owned caption: `WM_NCCALCSIZE`, `WM_NCHITTEST` from the painter's own geometry, and the three caption buttons painted from model state so the paint path still needs no `HWND`. 5,552 hit-test checks; the button pixels pinned in both themes. |
| `portable/win/drive-window.ps1` | Drives the live window with synthetic `PostMessage` mouse input and captures after each step. `PostMessage`, not `SendInput`, deliberately: the user is sitting at this machine and `SendInput` would move their real cursor. |
| `portable/win/tests/fixtures/outline.pdf` + `make_outline_fixture.py` | No committed fixture had a document outline, and neither does the NASA scan — so the sidebar's chapter list, its nesting and its UTF-8 titles were untestable. This one carries an accented and a CJK title, which is what a narrow CP1252 conversion mangles silently here. |

### 5.1 The capture host must be DPI-aware — this cost real time

`powershell.exe` is not per-monitor DPI aware. When a DPI-unaware process calls
`GetWindowRect`/`GetClientRect` on a window owned by a per-monitor-aware process,
Windows **virtualises** the answer: it reported a 1680×1200 window as 1120×800.
Allocating a bitmap of that virtualised size and calling `PrintWindow` then
captures only the window's top-left 1120×800 *physical* pixels — a crop at true
scale.

That produces an extremely convincing false positive: the page appears ~1.5×
too large and clipped, the ratio equals the DPI scale, and it reproduces every
time. It points straight at the app's DPI handling, which is precisely the
criterion nobody had ever verified. **The app was correct the whole time.**
`SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2)` at script start is what
makes every number in this file mean what it says.

Anyone writing a Windows capture harness for this project needs to know this
before they write it, which is why it has a section rather than a footnote.

---

## 6. Corrections to `windows-port-handoff.md`

Verified against the tree; the tree wins.

- **The fixture SHA256s are wrong.** §1.3 gives `golden.pdf` as
  `00432a55a58dbfe1…` and `alpha.pdf` as `32c0e3b9de92eeeb…`. Actual:
  `56dd60224d1c17049b03fe7fd2de0296e376dde51ee13f1d8e579109355b7881` and
  `d44f1dbffbad43b2e692dd61bcb6fb05502f7f933086de8dce5bf9a4bf92c64c`. Not stale:
  `golden.pdf` has only ever had **one** commit. Confirmed intact, not mangled by
  a Windows checkout — `.gitattributes` sets `* -text` and `git hash-object`
  matches the committed blob. Do not "fix" the fixtures to match the doc.
- **§3.3's line numbers for the surround colours moved**: dark is `:303` and
  light `:305` at HEAD, not `:302`/`:304`. Everything else §3.3/§3.4 cites was
  accurate.
- **Windows' window title was wrong in two more ways** than "it never updates":
  it used an em dash and `ShenzhenPDF` with no space, where macOS uses
  `"<name> - Shenzhen PDF"`.
- **§3.5's tab stroke description is incomplete**: the tree is
  `lineWidth = selected ? 1.4 : 1.0`, and an unselected non-missing tab is not
  stroked at all.
- **`spdf_win_layout.h`'s header referenced `portable/win/tests/layout_transcript_test.c`,
  which does not exist and never has.** Fixed: the header now cites
  `layout_geometry_test.c` for the numbers and `gtk_differential.c` (run by
  `layout-differential-native.cmd`) for the comparison against the real GTK
  header, and says plainly that no transcript test exists.
- The handoff's own §3.1 misses two useful reference sets that are committed:
  `portable/docs/gtk4-captures/` (24 PNGs) and `portable/docs/linux-captures/`
  (13 PNGs). They are the GTK4 frontend, not macOS, but they are real screenshots
  of the same document behaviour.

---

## 7. What I would do next, in order

**Six of these nine are done.** Each is marked with the commit that did it
rather than deleted, so the list stays checkable and so a reader can see which
predictions in it held. The three that remain all need a machine this one is
not.

1. ~~Scrollbars~~, ~~Find~~ and ~~the tab strip into the title bar~~ — **done**
   (`099a68508`, `86ae70cf3`). The window has one header band, as macOS does;
   the "double top bar" is closed. The two cosmetic remainders named here — no
   1 px top border when windowed, and the maximized edge — are closed too:
   `extend_frame_into_strip()` in `spdf_win_window_caption.h` calls
   `DwmExtendFrameIntoClientArea` with the full caption height when windowed
   (which is what keeps DWM drawing the shadow, the rounded corners and the 1 px
   frame) and with nothing when maximized or full screen, because a non-zero
   margin over a borderless popup draws a DWM strip along its top edge.
2. ~~**Find.**~~ **Done** (`099a68508`), and the prediction held exactly:
   `spdf_search_internal.h` was ported the way `spdf_win_layout.h` was and
   differentially tested with §4.4's shim — 37,440 comparisons, 0 differ. The
   results half followed in `a22c17cb4`/`5e0afbe7b` with its own differential.
3. ~~**A minimum window size and a sane default** (§2.2).~~ **Done**
   (`099a68508`, extended by `c8c8ed557`): `WM_GETMINMAXINFO` → `min_track_size`
   in `spdf_win_window.cpp`, and `initial_client_size()` in
   `spdf_win_session_app.h` now clamps a restored or default size into
   `[MIN_CONTENT … RESTORE_MAX]` against the monitor's **work** area, defaulting
   to macOS's 1120×800 with a 560×380 floor. §2.2's 244×286 window with clipped
   caption buttons cannot happen again.
4. ~~**Wire the sidebar's row clicks.**~~ **Done** (`5e0afbe7b`), along with the
   segmented Chapters/Comments/Search control, the results rows and their
   snippets. The Comments section is still a placeholder because annotations are
   not ported.
5. ~~**`SPDF_WIN_ZOOM_FIT_HEIGHT` on the canvas.**~~ **Done** (`099a68508`);
   `--fit height` is a real mode and `menu_test test_fit_keys_match_the_other_two_frontends`
   pins the accelerators against the other two frontends.
6. **Commit macOS reference PNGs** — still open, and now the largest single
   verification gap. §3 makes the cost concrete: seven cases are blocked on it
   permanently for anyone without a Mac, and they are the only cases that can
   catch a Windows-vs-macOS divergence.
7. **Fix `d2d-cases.sh`'s `d2d.window-dark`** — still open. `d2d-cases.sh` has
   not been touched since `833e0d527`, so the flaw §3.2 measured is still there
   and will fire the moment someone runs the suite from a Mac. Fix it before
   they hunt a Direct2D bug that is not there.
8. **Measure x64 ↔ ARM64 byte-identity**, or restate the claim as ARM64-only —
   still open, and needs a machine with both. It is written as a property of the
   port and is really a property of one pair of machines.
9. ~~**Move the tab strip into the caption.**~~ **Done** — see item 1. It was a
   subsystem, as predicted: `WM_NCCALCSIZE`, `WM_NCHITTEST` from the painter's
   own geometry and three caption buttons painted from model state, so the paint
   path still needs no `HWND`. `chrome_nc_test` runs 5,552 hit-test checks and
   `chrome_caption_paint_test` pins the button pixels in both themes.

---

## 8. Reproducing everything in this file

```
portable\win\mupdf-native-build.cmd --clean          :: MuPDF, x64, ~70 s
portable\win\mupdf-arch-check-native.cmd             :: all 646 members 8664
portable\win\build-native.cmd                        :: ShenzhenPDF.exe
bash portable/win/tests/run-tests-native.sh --list   :: the inventory: 92 cases
bash portable/win/tests/run-tests-native.sh          :: the run; exit 2 here (7 cross-host + qpdf)
portable\win\verify-phase1.ps1 -Exe %SPDF_OUT%\ShenzhenPDF.exe -Pdf <a.pdf>
portable\win\verify-phase1.ps1 -Exe %SPDF_OUT%\ShenzhenPDF.exe -Pdf <a.pdf> -Dark
```

Set `SPDF_OUT` to a private directory if another track is building, and point
`SPDF_MUPDF_LIBDIR` at the shared `C:\spdf-build\mupdf` so the private build does
not have to rebuild 74 MB of MuPDF. The user's own running instance holds a lock
on `ShenzhenPDF.exe`, so a shared `SPDF_OUT` fails to link rather than
mysteriously testing yesterday's binary. `portable/win/README.md` has the table.

From Git Bash, `cmd /c` is **`cmd //c`**: MSYS rewrites a bare `/c` to `C:\`, so
`cmd /c build-native.cmd` runs nothing and exits 0 (§4.8). Every one of the
commands above is judged by its exit code, and none of them decides anything by
piping output through `grep`.

---

## 9. The parity wave of 2026-09-02

Seven tracks were developed in parallel worktrees and merged into `master` on
2026-09-02, taking the port from "the chrome draws" to "most of the reader
works". Each merge is a first-parent merge commit with the track's own commits
under it; `git log --merges --first-parent` lists them in reverse order.

| merge | track | what landed, and what pins it |
|---|---|---|
| `32e4271c9` (+ `b5c21bb3a`) | **Markdown** | Markdown opens as paginated pages through **MuPDF's HTML engine** rather than a transcription of the 18,138-LOC AppKit reader (`portable/core/spdf_markdown*.c`, `spdf_win_md*`). Pinned by `SPDFCoreMarkdownTests` (no MuPDF needed), `markdown_core_test`, `markdown_open_test`, `md_win_test`; the decision and the phased plan are in `windows-markdown-design.md`, and four live Markdown captures are in `windows-captures/` |
| `2a1a452d8` | **Search** | the chapter-grouped **results sidebar**, centred scroll-to-match, a **clickable** minimap, type-anywhere search, and a pointing hand over plain-text URLs. A new `sidebar-differential-native.cmd` compares the result grouping against `spdf_sidebar_internal.h`, and the minimap's input policy was folded into the existing minimap differential (`minimap_differential_input.h`); plus `sidebar_rows_test`, `find_overlay_test`, `link_test`, `canvas_selection_test` |
| `76a51bbb1` | **Docs/state** | `documents.yaml` and `favorites.yaml` written the way the other two frontends write them; the **palette** with Open Recent, reopen-last-closed and favorites; **password prompts** and the **file watcher** (auto-reload, read-only shadow copy). `palette-differential-native.cmd` and `watcher-differential-native.cmd` compare the ported halves against their GTK originals; `palette_filter_test`, `palette_model_test`, `recents_test`, `password_test`, `password_flow_test`, `watcher_logic_test`, `watcher_test` |
| `a9348b0b3` | **Window** | **presentation mode**, full screen, a **second window**, session fidelity (frame, query, detaching), `settings.yaml` read and written, print **scaling** UI — and the one-line fix that stops **Escape closing the window** when nothing is focused, which §7's predecessor list called a real usability hazard. `settings_test`, `session_frame_test`, `window_keys_test`, `print_scaling_dialog_test` |
| `68bb691b6` | **Shell** | the exe's **identity** (icon, per-monitor-v2 manifest, version block, About box), `.pdf` **registration**, the F1 **shortcuts sheet generated from the menu table**, Explorer reveal and the other shell commands, and the **auto-updater** ported with Authenticode trust and a self-replacing exe. `about_test`, `assoc_test`, `shortcuts_test`, `shell_test`, `shell_windows_test`, `updater_feed_test`, `updater_verify_test`, `updater_install_test`, `updater_store_test` |
| `5b224fd11` | **Tools** | **OCR and translation**: toolchain acquisition, job running, the live-log panel and the glue. The first real installs cost two revisions — Ghostscript dropped, Argos put in a venv, the tools' data kept out of `AppData`, `TESSDATA_PREFIX` completed. `ocr_test`, `translate_test`, `toolchain_test`, `toolchain_run_test`, plus the `tools_e2e.sh` and `tools_panel.sh` probes |
| `03fa9f15a` | **Launch** | launch **measured** from process creation to first page (§4.8 left this as the open question), the Direct2D device created on a worker before the first paint needs it, and a `launch.budget` case in the suite. `windows-launch-performance.md` carries the bar, the baseline, the diagnosis and the patch for files other tracks own |

Two things the wave changed about how to read the rest of this file:

- **The counts moved.** 37 cases in §3 → 56 at the audit → **86** today. LOC
  under `portable/win/src/` went from 5,021 (the number
  `portable/win/README.md` carried for months) to **46,968** across 195 files,
  and the differentials from six to **nine**.
- **`windows-feature-matrix.md` is the feature-status authority**, audited
  against a built and run tree rather than from memory. §2.1 and §7 above are
  now a record of what this session predicted and how it turned out; where they
  disagree with the matrix, the matrix is newer. The handoff's §1.4 ledger and
  the plan's §0/§4 phase status are older than both.

---

## 10. The live-verification pass of 2026-09-03

Every visual claim in this port had been checked headless; §4.6 records why the
live half kept coming back BLOCKED — the workstation was locked for the whole
parity wave, and a locked session is not composited. **This section is that pass
re-run unlocked**, at HEAD `0fb7d8d92`, against a build made for it
(`SPDF_OUT=C:\spdf-build\track-live`). It replaces no earlier section; where it
contradicts one, it says so.

Same machine as §1: x64 Ryzen 5 6600U, Radeon 680M, Windows 11 26200, one
144 dpi (150%) display, 2880×1800 physical.

### 10.1 Phase 1 is 7/7 in both themes, on a composited desktop

```
verify-phase1.ps1 -Exe <track-live exe> -Pdf portable\win\tests\fixtures\outline.pdf
    light:  7 passed, 0 failed, 0 blocked   exit 0
    -Dark:  7 passed, 0 failed, 0 blocked   exit 0
```

Criterion by criterion, identical in both: the window opens (352 ms light /
377 ms dark to a visible `ShenzhenPDFWindow` titled `outline.pdf - Shenzhen
PDF`); the host is per-monitor-v2; the **canvas region 368,126,509,663 matches
the headless compose** inside the script's MAE ceiling; DPI is correct at
144 dpi (1.5×); all three resize sizes (900×700, 1300×900, 700×520) repaint
correctly against their own headless renders; `WM_CLOSE` exits 0; and nothing
this run started was left behind.

Nothing had to be fixed to get there. **All three failures the last locked run
reported were the black frame and only the black frame** — which is what §4.6
predicted and what could not be shown until now.

### 10.2 A defect only a live window could find: `--find` is dead on the windowed path

`--find <text>` on a **windowed** launch does nothing at HEAD. The find field
stays empty, the sidebar's Search segment never appears, and no match is
highlighted. `--render-window-png --chrome --find fixture` — the headless path —
is unaffected, which is why no test caught it and why capture
`07-search-section-headless.png` looks right.

The proof is in the captures directory's own history:
`windows-captures/01-window-light.png`, taken 2026-09-01 with the same flag on
the same fixture, shows `fixture` in the field, the Search segment present, the
match ringed and the scroller's heat-map ticks. `08-window-light.png`, taken
today with the same command, shows none of it. **01 is deliberately left in
place as the before-picture.**

One line causes it. `main()` parses `--find` into `a.find_text`
(`spdf_win_main.cpp:265`) and pushes it (`:292`), and then, inside session
restore, calls `app_restore_find_text(&a)` (`:417`), whose first act is

```c
a->find_text[0] = L'\0';
```

before refilling the field from the *selected tab's* remembered `search_text`
(`spdf_win_session_app.h:59-68`). A tab opened by this launch has none, so the
command line's query is overwritten with the empty string before the first
paint. The per-tab query restore is right and wanted — it is what makes Ctrl+Tab
bring back the query you left in a document — it simply has no case for "the
command line already asked for one". Not fixed here: this pass owns no source
file. The fix belongs with whoever owns `spdf_win_main.cpp`, and its shape is to
let an argv-supplied query win over an empty remembered one.

The feature itself is fine, which is the useful half of the report: typed into
the field (`drive-uia.ps1 cmd:26` then `type:fixture`) the whole thing works
live — four results grouped under their chapter headings with "match *n* of 4",
the active match ringed red over yellow, ticks on the scroller and yellow marker
bars inside the minimap thumbnails. That is
`windows-captures/11-search-results-live.png`, the first live picture of the
Search section; 07 could only be composed offscreen.

### 10.3 Modal windows, driven for real (gap 16)

`windows-feature-matrix.md` gap 16 — "modal windows verified live" — was the
largest hole in the port's evidence, and `drive-window.ps1` is the wrong tool
for it: it clicks CLIENT COORDINATES, which is right for chrome the app paints
itself and wrong for a dialog whose controls are child windows this repo does
not lay out, and a modal dialog runs its own message loop, so the app's window
stops answering the "is it alive" probes at the same moment.

`portable/win/drive-uia.ps1` is the new tool: UI Automation to find and read the
dialog, control ids to press it, `PrintWindow` to capture it, and it never moves
the reader's cursor. Driven and captured this pass:

| dialog | class | driven | evidence |
|---|---|---|---|
| Keyboard Shortcuts (F1) | `SpdfWinShortcutsSheet` | opened by `cmd:55`, dismissed by Escape | `15-shortcuts-sheet.png` |
| About | `SpdfWinAboutBox` | `cmd:56`, Escape | `16-about-box.png` — 26.9.2 (build 1), MuPDF 1.27.2 |
| Add Comment | `SpdfWinAnnotDialog` | `cmd:63` after a page click, both fields typed, **Add pressed** | `14-add-comment-dialog.png`, then `12-comments-sidebar.png` |
| `--install`'s completion box | `#32770` | **OK pressed**, process exited 0 | §10.4 |

The annotation chain is the one worth stating whole, because it is what the
matrix's annotations row lists as untested: a click on the page, Add Comment,
author and text typed, Add — and then a note marker on the page, a `Page 1`
group header in the **Comments** section, and a `Reviewer: Check this heading
agains…` / `Text - Page 1` row under it. The whole flow, live, end to end. It
also settles where the annotation goes: **into the document**, which grew from
6,449 to 7,264 bytes. Never run this against a committed fixture in place; the
one that was is restored and re-checked against `make_outline_fixture.py`'s own
output (`sha256 d757157117610c4d…`).

**One trap, and it is a trap for the report rather than for the app.** Through
`System.Windows.Automation` on this box, every child of every dialog comes back
as `ControlType.Pane` with the control id as its `AutomationId`, the window text
as its `Name`, and **no `InvokePattern` and no `ValuePattern`** — so a
UIA-pattern driver can press nothing. That looks exactly like an accessibility
defect in the app's dialogs, and it is not: `--install`'s **stock `MessageBoxW`**
reports its OK button — a plain `L"BUTTON"` in a plain `#32770`, the most
accessible control in Windows — the same way, `type=Pane name='OK' id='2'
invokable=False`. When the OS's own message box comes back like that, the missing
piece is the standard-control proxy providers on the client side.
**Do not report these dialogs as inaccessible on this evidence.** They are built
from real `L"EDIT"` and `L"BUTTON"` children
(`spdf_win_annot_dialog.cpp:203-243`); `drive-uia.ps1` presses them by control id
through `GetDlgItem`, and its `tree` step still prints what UIA can see, which is
how the limitation was found.

A second trap, cheap to hit and expensive to notice: `GetWindowTextW` on another
process's EDIT control returns the CACHED window text, not the field's content.
`childtext:1101=Reviewer` reported `text='sagan'` and had worked perfectly — the
capture shows `Reviewer`. Judge a `WM_SETTEXT` by the picture or by the outcome,
never by reading it back that way.

### 10.4 The first-run dialog: still not drivable, and the gate is why

**This is the one deliverable of the pass that could not be met, and it is no
longer the lock's fault.** The task was to press the three command links of the
"Run this copy / Install / Install and run" TaskDialog for real. It cannot be
done on this machine without writing into the reader's live
`%APPDATA%\ShenzhenPDF`, and the reason is a deliberate line in the gate.

The dialog appears only when `spdf_win_setup_first_run_action()` returns ASK,
which needs all six of its inputs to say "ask"
(`spdf_win_setup_first_run.h`). Five were confirmed absent by measurement: no
`--install/--uninstall/--quiet/--purge/--portable/--state-dir` on the command
line, no `ShenzhenPDF.portable` beside the exe (a scratch copy alone in an
otherwise empty directory), not running from the install directory, and nothing
installed — `%LOCALAPPDATA%\Programs\ShenzhenPDF`, the per-user Start Menu
`.lnk`, `HKCU\…\Uninstall\ShenzhenPDF` and the ProgID were all verified absent
before and after. The sixth is `answered`, read from `settings.yaml`'s
`setupPromptAnswered`.

A bare launch of that scratch copy — the one intentional bare launch, killed
while modal so nothing could be committed — **went straight to a window.** So
`setupPromptAnswered` is already true in the real state directory, written by
the setup track's own live verification of the install cycle (whose matrix row
records that it "verified live on the real per-user locations and fully restored
afterwards"). Clearing it means writing the reader's `settings.yaml`.

And the redirection that exists for exactly this kind of test cannot help,
because it suppresses the very thing it would isolate:

```c
/* spdf_win_setup.cpp:418-423 */
if (!explicit_flag &&
    (GetEnvironmentVariableW(SPDF_WIN_SETUP_NO_PROMPT_ENV, NULL, 0) > 0 ||
     GetEnvironmentVariableW(SPDF_WIN_SETUP_PROFILE_ENV, NULL, 0) > 0 ||
     GetEnvironmentVariableW(SPDF_WIN_SETUP_ROOT_ENV, NULL, 0) > 0))
    explicit_flag = 1;
```

`SPDF_WIN_SETUP_ROOT` redirects the install directory, the Start Menu, the
registry and the purge target — and is itself a reason not to ask. `--state-dir`
would redirect the settings the answer is remembered in, and is also a reason
not to ask. **So "the prompt is shown" and "nothing real is written" are
mutually exclusive as the gate stands**, and after the first answer on any
machine the dialog becomes permanently unreachable there. That is a testability
defect, not a correctness one: the truth table is right and `setup_test.c`
covers all 64 rows.

The smallest honest fix is a suppressor that redirection can distinguish from
intent — treat `SPDF_WIN_SETUP_ROOT` as "redirect but still ask", or add an
`SPDF_WIN_SETUP_FORCE_PROMPT` honoured only alongside it. Either would make the
three links pressable with nothing real on the line. Until then there is no
capture of this dialog, and the `11-first-run-dialog.png` this pass was asked
for does not exist.

**What was driven instead**, all under `SPDF_WIN_SETUP_ROOT` pointed at a
scratch directory, which exercises every consequence the three links have except
the remembered answer:

| the link | what it does | what was verified live |
|---|---|---|
| **Install** | `spdf_win_setup_install(quiet, NULL, 0)` | `--install --quiet` exit **0**; `<root>\Programs\ShenzhenPDF\ShenzhenPDF.exe` (41,620,480 bytes); `<root>\Start Menu\Programs\ShenzhenPDF.lnk` whose `IShellLinkW` target and working directory read back as the installed exe and its folder; ten `Uninstall\ShenzhenPDF` values incl. `DisplayVersion 26.9.2`, `EstimatedSize 40645`, `UninstallString "…" --uninstall`, `NoModify`/`NoRepair` 1; the whole ProgID tree (`ShenzhenPDF.Document`, `Applications\ShenzhenPDF.exe`, `.pdf\OpenWithProgids`, `RegisteredApplications`, `ShenzhenPDF\Capabilities`). **No window opened** — asserted with an `expect-no-dialog` step, not assumed. Run again without `--quiet`, its completion `MessageBoxW` was captured and its **OK pressed**, exit 0 |
| **Install and run** | the same with `relaunch = 1` | the relaunch is suppressed under the redirection **on purpose** (`spdf_win_setup.cpp:207`: "an installed copy pointed at a scratch directory is not a thing anyone wants to see start"), so the second half was verified by launching `<root>\Programs\ShenzhenPDF\ShenzhenPDF.exe` directly: it opens a window titled `outline.pdf - Shenzhen PDF`, raises no dialog (it *is* the installed copy, so the gate does not ask), and exits 0 |
| **Run this copy** | remember the answer, then run | the "run" half is every other launch in this pass. **The "remember" half is not verified**: it writes `setupPromptAnswered` into the active state directory and is reachable only from the dialog |

Then `--uninstall --quiet --purge`, exit **0**, and the machine proved clean.
Gone: the install directory, the installed exe, the `.lnk`, the `Uninstall` key,
`ShenzhenPDF.Document`, `Applications\ShenzhenPDF.exe`, the `Capabilities` tree,
the `RegisteredApplications` value, and the redirected state directory the purge
was aimed at. **Ten keys survive and all ten are correct**: they are empty shared
containers — `Software\Classes\.pdf\OpenWithProgids`,
`Software\RegisteredApplications`, `…\CurrentVersion\Uninstall` and their
parents — holding no value at all. On a real profile those belong to the shell,
not to the app, and an uninstaller that deleted them would be the bug.

The real per-user locations were verified absent before the cycle and absent
after: no install directory, no Start Menu `.lnk`, no
`HKCU\…\Uninstall\ShenzhenPDF`, no `ShenzhenPDF.Document`, no
`ShenzhenPDF.pdf`, no `RegisteredApplications` value. The scratch root and the
`HKCU\Software\ShenzhenPDF-setup-test` key were both deleted afterwards.

One asymmetry found while setting the purge up, worth knowing before writing a
test against it: `SPDF_WIN_SETUP_ROOT` redirects `setup_state_dir()`, which is
what `--purge` deletes and what the completion message names, but it does **not**
redirect the app's runtime state directory — `spdf_win_paths.c`'s
`resolve_roaming_dir()` calls `SHGetKnownFolderPath(FOLDERID_RoamingAppData)`
and knows nothing about the variable. So a redirected app writes its session and
settings to the REAL `%APPDATA%\ShenzhenPDF` while a redirected `--purge` aims at
`<root>\Roaming\ShenzhenPDF`, which nothing ever fills. The purge above had to be
given a file to delete before it could be seen to delete one.

### 10.5 Two harness bugs of this pass's own making, both worth keeping

**A name-based process sweep closed another track's app.** The first version of
`drive-uia.ps1`'s cleanup enumerated `Get-Process -Name ShenzhenPDF` and closed
anything newer than its own launch. It found and closed a
`C:\spdf-build\track-settings\ShenzhenPDF.exe` belonging to another agent's build
tree. This is §4.7's trap — the one that made `verify-phase1.ps1` report a false
leak — in a worse form, because that one only mis-reported and this one acted.
The rule that follows is not "compare start times": it is that a harness may only
close a pid that was **absent from a snapshot taken before its own launch** *and*
whose image path is one this run launched. `drive-uia.ps1` now requires both.

**A PowerShell function returns its output stream.** A capture helper that wrote
three `Write-Output` lines and then `return 0` handed the caller a four-element
array; `if ($rc)` read it as true and `exit $rc` threw. The visible symptom was a
run that stopped silently mid-way with no error text and a stale exit code —
which reads exactly like the app hanging. Step results now travel in a
script-scope variable.

A third, milder one: `SetProcessDpiAwarenessContext` succeeds once per process,
so a script taking several captures from one PowerShell session reports
`host_dpi_aware=True` for the first and `False` for the rest while remaining
fully aware. `verify-phase1.ps1` never sees this because it spawns a fresh
`powershell -File` per capture. Do not read that second `False` as §5.1's
virtualisation trap.

### 10.6 What is still not verifiable, and why

- **The first-run dialog's three command links** — §10.4. Needs a gate change,
  not an unlocked desktop.
- **"Run this copy" remembering the answer** — same cause.
- **The Open and Save pickers, and a print job end to end.** Not attempted:
  the pickers are shell dialogs that would browse the reader's own filesystem,
  and printing needs a printer. `drive-uia.ps1` is now the tool for the first two
  when someone wants them.
- **x64 ↔ ARM64 render identity** — still needs a Mac (§1); being unlocked
  changes nothing about it.
- **The reader's live state directory was modified during this pass, and not by
  it.** `%APPDATA%\ShenzhenPDF\documents.yaml` and `settings.yaml` changed at
  18:29-18:30 while this pass ran. Every launch here carried an explicit
  `--state-dir` (visible in each harness's echoed `args=` line) except the two
  `--install`/`--uninstall` invocations, which return before the settings layer
  is reached (`spdf_win_main.cpp:127-132`), and the one bare launch, which was
  killed while modal eleven minutes earlier. Other agents were building and
  launching the app on this machine at the time and are the likely author. It was
  not checked by reading the files, and should not be: they are the reader's.


## 11. Two launch defects a person found that no test did (2026-09-05)

"When I launch the app from dist I can't interact with it at all, not even
focus it with Alt+Tab." Every test was green; the app's own window was visible,
enabled, foreground and answering messages. Two defects, both from the launch
work merged the day before:

1. The GPU prewarm created a top-level WS_OVERLAPPEDWINDOW on a worker thread
   and then parked that thread forever without pumping. To Windows that is a
   HUNG window for the life of the process: every desktop broadcast stalls on
   it for its timeout, the shell's enumeration of the process slows to the
   same timeout, and activating the app's real window becomes unreliable.
   Measured with IsHungAppWindow: true from seconds after launch until exit,
   on that window and the IME window it owned. It is now a WS_POPUP tool
   window (excluded from Alt+Tab and the taskbar by definition) whose thread
   parks in MsgWaitForMultipleObjects and dispatches what arrives.
2. spdf_win_window_show() never asked for the foreground. ShowWindow maps a
   window; it does not decide who is in front, and the launch now does about
   145 ms of work before showing anything so the window appears complete.
   The launching window had the foreground back by then and the app arrived
   at z-order position 1, underneath it, with a sliver to click. It now calls
   SetForegroundWindow, BringWindowToTop and SetFocus, and flashes the
   taskbar button when the system refuses.

Verified from Explorer with another app maximized and focused: before, the
app sat at z-index 1 behind it; after, z-index 0, foreground, and still there
two seconds later, with no hung window in the process.

The lesson for the harness: headless composes and even live captures cannot
see a z-order or a hung-window problem. A launch check that asserts "is the
foreground window AND at z-index 0 AND no window of the process is hung"
would have caught both in the launch budget case. It now does: `measure-launch.ps1`
records, per run and while the window is up, whether it is the foreground window,
its z-index among Alt+Tab-sized visible top-level windows, and how many windows
of the process `IsHungAppWindow` reports; `launch.budget` FAILS on any hung
window or on a z-index other than 0 in a majority of runs. Foreground is reported
but not judged -- Windows grants it only to a process launched BY the foreground
process, which a harness under a shell under an editor never is, so it reads
0/5 there while a hand launch is 5/5. Before the two fixes this case would have
read "1 hung window, z-index 1"; after, "5/5 in front, 0 hung".

## 12. The upstream parity wave (2026-09-06)

The macOS behaviours from 26.9.3 through 26.9.5-1 that section (d) of the
feature matrix listed, ported in three tracks: nested chapters with
per-document collapse memory and the single Expand/Collapse button, the
minimap following the reading theme (merge 386590a08); windows reopening on
their display with the last-used one focused and siblings opening together,
Keep Image Colors per document (merge 340ce34f6); Alt+wheel paging by wheel
distance and in-place Markdown reload (in flight). Each verified from a clean
build: full suite with only the seven macOS-host cases blocked, ratchet green,
sidebar differential unchanged at 15,203/0.
