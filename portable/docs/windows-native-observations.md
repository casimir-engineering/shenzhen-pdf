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

Everything in `portable/win/README.md` and the handoff assumes an **ARM64**
Windows 11 guest in Parallels, reached over `prlctl exec`, with a toolchain in
`C:\BuildTools` and MuPDF prebuilt in `C:\spdf-build\mupdf`. None of that was
true here.

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

What is genuinely still missing, as of the chrome work:

- **Scrollbars.** macOS shows native ones and overlays the search heat-map on
  them. Windows has none, so a long document gives the reader no position
  feedback outside the minimap. Of everything absent this is the only
  *functional* loss rather than a cosmetic one.
- **Find**, the regex checkbox, the match counter and the scrollbar heat-map.
  The behaviour is already toolkit-free in
  `portable/linux/gtk4/spdf_search_internal.h` and wants porting the way
  `spdf_win_layout.h` was ported.
- **The Comments sidebar section**, OCR and translate — no model on Windows yet.
- **Menus and a command palette**: no `HMENU`, no accelerator table.
- **Open a file**: still command line only. No `WM_DROPFILES`, no
  `IFileOpenDialog`, no file association — so the toolbar's `+` button and the
  tab overflow `…` are routed but inert.
- **The tab strip lives below the caption, not inside it.** macOS puts it in the
  title bar. Hoisting it means owning `WM_NCCALCSIZE`, `WM_NCHITTEST`, the
  caption buttons and snap-layouts hover — a subsystem, and one the offscreen
  compose path cannot verify. `spdf_win_chrome.h` documents exactly which two
  insets change if that is ever done.
- **Selection, links, annotations, printing.** Untouched.

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

```
37 cases, 29 passed, 0 failed, 8 blocked        exit 2 (BLOCKED is not a pass)
```

Newly passing and previously registered nowhere: **all five orphaned core
suites** — `SPDFCoreOutlineTests`, `SPDFCoreRenderThemeTests`,
`SPDFCoreSelectionTests`, `SPDFCoreCJKSelectionTests` pass;
`SPDFCorePasswordTests` is BLOCKED only because it needs `qpdf` to generate
encrypted fixtures (`winget install qpdf.qpdf`). The handoff called this "the
cheapest outstanding win in the port"; it was.

The 8 blocked cases are honest blocks, each naming its missing prerequisite:
`layout.differential` needs glib and the GTK4 headers; the 7 cross-host PNG cases
need a **macOS host**, because `d2d-cases.sh` and `probe-cases.sh` do not compare
against committed references — they **compile the reference probe with `cc` on the
Mac at test time**. There is no committed reference image anywhere in
`portable/win/tests/`. (`portable/docs/windows-captures/` holds live screenshots, but
they are a RECORD, not test references -- a chrome screenshot pins four
subsystems at once and would fail for reasons unrelated to whatever changed.) Any plan to run the port's strongest evidence off a Mac has
to commit references first.

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
- **`spdf_win_layout.h`'s header references `portable/win/tests/layout_transcript_test.c`,
  which does not exist.**
- The handoff's own §3.1 misses two useful reference sets that are committed:
  `portable/docs/gtk4-captures/` (24 PNGs) and `portable/docs/linux-captures/`
  (13 PNGs). They are the GTK4 frontend, not macOS, but they are real screenshots
  of the same document behaviour.

---

## 7. What I would do next, in order

Items 1, 2 and 3 of the original list are done — the tab strip and toolbar are
drawn and wired, and the sidebar and minimap show real content. What is left,
in the order I would take it:

1. ~~Scrollbars~~ and ~~Find~~ — done, with the heat-map on the trough.
   **Tab strip into the title bar** is in progress: the remaining half of the
   "double top bar", and the last structural divergence from the macOS window.
2. **Find.** `portable/linux/gtk4/spdf_search_internal.h` is already
   toolkit-free — 15 `static inline` functions including the heat-map ticks.
   Port it the way `spdf_win_layout.h` was ported and differentially test it with
   the glib shim from §4.4, which is now known to work.
3. **A minimum window size and a sane default** (§2.2). Minutes of work, and it
   fixes a window that can currently open too small to use.
4. **Wire the sidebar's row clicks.** The geometry and hit-testing are written
   and tested; only the routing call is missing.
5. **`SPDF_WIN_ZOOM_FIT_HEIGHT` on the canvas.** macOS's fit popup offers four
   modes and the canvas has three, so the cycle silently skips one.
6. **Commit macOS reference PNGs**, or accept that the port's strongest evidence
   exists only on one machine. §3 makes the cost concrete: 7 of 37 cases are
   blocked on it permanently for anyone without a Mac.
7. **Fix `d2d-cases.sh`'s `d2d.window-dark`** before someone runs it from the Mac
   and hunts a Direct2D bug that is not there (§3.2).
8. **Measure x64 ↔ ARM64 byte-identity**, or restate the claim as ARM64-only. It
   is written as a property of the port and is really a property of one pair of
   machines.
9. **Move the tab strip into the caption**, if visual parity with macOS's
   title-bar tabs is wanted. This is a subsystem, not a detail — see the
   divergence note at the top of `spdf_win_chrome.h`.

---

## 8. Reproducing everything in this file

```
portable\win\mupdf-native-build.cmd --clean          :: MuPDF, x64, ~70 s
portable\win\mupdf-arch-check-native.cmd             :: all 646 members 8664
portable\win\build-native.cmd                        :: ShenzhenPDF.exe
bash portable/win/tests/run-tests-native.sh          :: 33 cases
portable\win\verify-phase1.ps1 -Exe C:\spdf-build\ShenzhenPDF.exe -Pdf <a.pdf>
portable\win\verify-phase1.ps1 -Exe C:\spdf-build\ShenzhenPDF.exe -Pdf <a.pdf> -Dark
```

Every one of these is judged by its exit code. None of them decides anything by
piping output through `grep`.
