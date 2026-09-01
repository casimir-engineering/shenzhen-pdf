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

The handoff's §1.4 ledger is accurate. Placed beside
`docs/images/portable/macos-main-window.webp`, the Windows window is missing,
visibly, in this order of prominence:

1. **The tab strip.** macOS shows five tabs with traffic lights, a `+`, a
   read-only dot. Windows shows an OS caption. Largest single visual gap.
2. **The toolbar.** macOS: 18 arranged controls — Side Panel, OCR, translate,
   page field `4 / 117`, page pill, `Fit Page`, zoom pill, Find, Regex, Map.
   Windows: nothing.
3. **The sidebar** (Chapters/Comments + filter field, visible by default).
4. **The minimap** strip (visible by default).
5. **Scrollbars.** macOS has native ones carrying the search heat-map; Windows
   has none, so a long document gives the reader no position feedback at all.

Everything absent is chrome. The *document* — layout, zoom, fit, theme,
continuous scroll — is there and is correct. That matches the handoff's own
summary and is worth restating: what remains is painting and hit-testing, not
document behaviour.

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
33 cases, 25 passed, 0 failed, 8 blocked        exit 2 (BLOCKED is not a pass)
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
`portable/win/tests/`. Any plan to run the port's strongest evidence off a Mac has
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

## 5. New tooling, and why each exists

| file | why |
|---|---|
| `portable/win/screenshot-window.ps1` | Makes "look at the window" a command. `PrintWindow` with `PW_RENDERFULLCONTENT` (mandatory for a D2D client area), enumerates windows by pid rather than trusting `MainWindowHandle`, reports the client offset so a capture can be cropped to exactly what `spdf_win_paint` drew, and **always** closes the app it started. |
| `portable/win/verify-phase1.ps1` | Turns Phase 1's five criteria into one exit code. Compares the live client area against the headless compose at the same size *and the same DPI*. |
| `portable/win/build-native.cmd` | The native build the port never had. Discovers `portable/win/src/*`, lists `portable/core/*` explicitly, links MuPDF when present. |
| `portable/win/tests/run-tests-native.sh` (+ `.lib.sh`, `.d2d.sh`) | The harness, natively. Honours the in-file `spdf-test-*` directives, registers the five orphaned core suites, BLOCKS rather than skips. |
| `portable/win/mupdf-gen-ninja-native.sh`, `mupdf-native-build.cmd`, `mupdf-arch-check-native.cmd`, `mupdf-native-linkcheck.c/.cmd` | MuPDF for x64, still derived from `mupdf/Makefile`'s own recipe via `make -n` so both hosts compile the same MuPDF. 646 translation units in 14 flag groups, 417 + 229 objects — the same counts as the ARM64 build. |
| `portable/win/src/spdf_win_tabstrip.h`, `portable/win/tests/tabstrip_geometry_test.c` | Tab-strip geometry transcribed from `SPDFMacTabStripView.mm` and `SPDFMacTabStripGeometry.h`, toolkit-free and header-only, 741 assertions. Geometry only — nothing draws it yet. |

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

1. **Draw the tab strip.** The model is finished and tested; the geometry is now
   finished and tested (`spdf_win_tabstrip.h`, 741 assertions). What remains is
   D2D painting and `WM_LBUTTONDOWN` hit-testing — no new logic. Largest visible
   parity gain per unit of risk.
2. **Draw the toolbar**, pills first.
3. **Give the window a minimum size and a sane default** (§2.2). Minutes, and it
   fixes a window that can currently open too small to use.
4. **Commit macOS reference PNGs**, or accept that the port's strongest evidence
   only exists on one machine. §3 makes this concrete: 7 of 33 cases are blocked
   on it, permanently, for anyone without a Mac.
5. **Fix `d2d-cases.sh`'s `d2d.window-dark`** before someone runs it from the Mac
   and hunts a Direct2D bug that is not there (§3.2).
6. **Measure x64 ↔ ARM64 byte-identity**, or restate the claim as ARM64-only. It
   is currently written as a property of the port and is really a property of one
   pair of machines.
7. **Scrollbars.** Of the missing chrome, this is the one whose absence is a
   functional loss rather than a cosmetic one.

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
