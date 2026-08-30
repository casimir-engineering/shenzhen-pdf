# Building ShenzhenPDF code on Windows, from the Mac

This directory is the Windows port: the application sources under `src/`, the
headless test harness under `tests/`, and the build plumbing that compiles and
runs all of it **inside a Parallels Windows VM, driven entirely from the macOS
command line, without ever touching the VM's GUI**.

There **is** application code here — 5,021 committed lines under `portable/win/src/`,
including a Direct2D renderer, a continuous-scroll canvas, a background render
pool and the `%APPDATA%` state layer. `ShenzhenPDF.exe` builds, links against a
native ARM64 `libmupdf`, and renders pages byte-identically to macOS. (This
paragraph replaces one that read "No application code lives here yet. The only C
in this directory is a smoke test" — true when written, false for some hours
before anyone noticed.)

**One thing this directory cannot do, and it is the port's central limitation:
nobody has seen a ShenzhenPDF window open on Windows.** `prlctl exec` runs in
the SYSTEM session, which has no interactive desktop, so every claim below is a
build, an exit code or a pixel comparison. See "What is and is not proven".

## TL;DR

Every command in this file was run, from this repo, against this VM. None is
aspirational.

```sh
portable/win/tests/run-tests.sh   # the whole suite: 20 cases, 0 failed, exit 0
portable/win/verify.sh            # toolchain + cross-host proof; non-zero if broken
portable/win/mupdf-build.sh       # libmupdf for ARM64 (~59 s cold, ~3 s no-op)
```

Build and headlessly render the app itself:

```sh
portable/win/vm-build.sh --run ShenzhenPDF \
    portable/win/src/spdf_win_main.cpp portable/win/src/spdf_win_window.cpp \
    portable/win/src/spdf_win_d2d.cpp portable/win/src/spdf_win_canvas.cpp \
    portable/win/src/spdf_win_canvas_prefetch.cpp portable/win/src/spdf_win_lru.c \
    portable/win/src/spdf_win_paths.c portable/win/src/spdf_win_render.c \
    portable/win/src/spdf_win_state.c portable/win/src/spdf_win_tabs.cpp \
    portable/win/src/spdf_win_session.cpp portable/core/shenzhen_pdf_core.c \
    portable/core/spdf_selection.c portable/core/spdf_selection_support.c \
    portable/core/spdf_recolor.c portable/core/spdf_yaml.c \
    portable/core/spdf_win_compat.c \
    -- --render-png 'C:\spdf\portable\win\tests\fixtures\golden.pdf' 0 1.0 \
       '\\Mac\Home\Documents\spdf-win\out\app-page.png'
# -> wrote \\Mac\Home\Documents\spdf-win\out\app-page.png 200x260
```

There is no shorter form of that link line yet: no CMake project and no source
manifest exists, so the app's translation units are listed by hand at every
call site. Note `portable/core/spdf_win_compat.c` at the end of it —
**it belongs in every Windows source list** (see gotcha 18).

`--render-window-png <pdf> <page> <w> <h> <out.png>` composes the full window
scene instead of one exact-zoom page, which is how the fit-mode geometry is
checked without a window:

```
frame viewport=900x700 zoom=4.500000 scroll=247.0000,0.0000 content=1394.0000,1942.0000
frame draw page=0 dest=0.0000,13.0000 size=900.0000,1170.0000 bitmap=900x1170
```

## The machine

| | |
|---|---|
| VM | Parallels, named exactly `Windows 11` (override with `SPDF_VM_NAME`) |
| Guest OS | Windows 11, build 10.0.26200.8875 |
| Guest CPU | **ARM64** (`PROCESSOR_ARCHITECTURE=ARM64`) |

The host is Apple Silicon, so the guest is **ARM64 Windows, not x64**. This is
the single easiest thing to get wrong here. Windows on ARM will happily run an
x64 binary under emulation, so a mis-targeted build *appears* to work while
being slower and subtly different. Everything below targets ARM64 natively, and
`portable/win/guest-info.cmd` prints the produced binary's machine type so the
claim stays checkable:

```
Microsoft (R) C/C++ Optimizing Compiler Version 19.44.35228 for ARM64
C:\BuildTools\VC\Tools\MSVC\14.44.35207\bin\HostARM64\arm64\cl.exe
            AA64 machine (ARM64)
```

## Toolchain

**Visual Studio 2022 Build Tools 17.14.39** — chosen over MSYS2/MinGW because
the eventual app is Win32/Direct2D, which means MSVC is the toolchain its
headers, COM interfaces and `.rc` resources are written for. It installed
silently with no GUI interaction at all, so the fallback was never needed.

| Component | Version |
|---|---|
| MSVC (HostARM64/arm64) | 19.44.35228 / toolset 14.44.35207 |
| Windows SDK | 10.0.26100.0 |
| CMake | 3.31.6-msvc6 |
| Ninja | 1.12.1 |

CMake and Ninja come from the `VC.CMake.Project` component and are on `PATH`
only *after* `vcvarsall.bat` runs — they are not global installs.

### Install commands (already done; recorded so the VM is reproducible)

Run from the Mac. Took **~11.5 minutes** wall clock to a usable `cl.exe`.

```sh
# 1. fetch the bootstrapper inside the guest
prlctl exec "Windows 11" cmd.exe /c 'if not exist C:\spdf-tools mkdir C:\spdf-tools & powershell -NoProfile -Command "Invoke-WebRequest -Uri https://aka.ms/vs/17/release/vs_BuildTools.exe -OutFile C:\spdf-tools\vs_BuildTools.exe -UseBasicParsing"'

# 2. silent install (no GUI, runs as SYSTEM, exits 0 on success)
prlctl exec "Windows 11" cmd.exe /c 'C:\spdf-tools\vs_BuildTools.exe --quiet --wait --norestart --nocache --installPath C:\BuildTools --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.Tools.ARM64 --add Microsoft.VisualStudio.Component.VC.CMake.Project --add Microsoft.VisualStudio.Component.Windows11SDK.26100'
```

`Microsoft.VisualStudio.Component.VC.Tools.ARM64` is the load-bearing one. The
base `VCTools` workload on an ARM64 host installs `HostARM64\x64` and
`HostARM64\x86` — ARM64-hosted **cross** compilers that emit x64/x86. Without
that extra component there is no `HostARM64\arm64` and no way to build a native
ARM64 binary.

## How the pieces fit

```
  macOS repo                    ~/Documents/spdf-win          guest C:\spdf
  ──────────                    ────────────────────          ─────────────
  portable/core  ──┐
  portable/win   ──┼─ rsync ──▶  staging dir  ── robocopy ──▶  build source
  ext/           ──┘  (a)        = \\Mac\Home\...   (b)              │
                                                                 cl.exe (c)
                                                                     │
                                            exit code ◀──────────────┘
```

| file | side | role |
|---|---|---|
| `sync-to-vm.sh` | macOS | (a) rsync the platform-independent subtrees into the staging dir |
| `guest-build.cmd` | guest | (b) robocopy share → `C:\spdf`, enter MSVC env, (c) compile |
| `vm-build.sh` | macOS | orchestrates both and **returns the guest's exit code** |
| `guest-info.cmd` | guest | prints toolchain versions and binary machine type |
| `verify.sh` | macOS | the end-to-end proof, below |
| `smoke/recolor_smoke.c` | both | exercises `portable/core/spdf_recolor.c` |
| `smoke/broken.c` | guest | deliberately un-compilable; guards the exit-code contract |

### The exit-code contract

A cross-machine build script that always exits 0 is worse than no script: it
reports success for a tree that does not compile, and every check layered on
top of it becomes worthless. So:

- `prlctl exec` propagates the guest's exit code faithfully — verified
  directly: `exit /b 7` in the guest yields `$? == 7` on the Mac.
- `guest-build.cmd` ends with `exit /b %CL_RC%`, i.e. cl.exe's own code.
- `vm-build.sh` uses no `set -e`, no pipe around the `prlctl` call, and nothing
  after it that would clobber `$?`.
- `verify.sh` step 2 compiles `smoke/broken.c` and **fails the whole run if the
  exit code is 0.** Observed: `vm-build.sh exited 2` (cl.exe's error code).

Infrastructure failures use distinct codes so they are never mistaken for a
compile error: `64` bad usage, `65` sync failed, `66` unknown/unstaged source,
`90` robocopy failed, `91` no vcvarsall, `92` vcvarsall failed.

## Proof

`portable/win/verify.sh` builds `smoke/recolor_smoke.c` +
`portable/core/spdf_recolor.c` natively on macOS (clang, arm64) and in the VM
(MSVC, ARM64), runs both, and diffs. `spdf_recolor.c` is the ideal subject: pure
C, no MuPDF, no platform headers, and **no floating point** — every printed
value is fixed by integer arithmetic, so any difference is a real toolchain
problem rather than acceptable numerical drift.

Current result: **61 lines, byte-identical.** Sample:

```
mode=LUMA_REMAP kind=1 ink=[220 221 222] span=[190 191 192]
  in=(255,255,255,255) out=( 30, 30, 30,255)
  in=(255,  0,  0,255) out=(255, 86, 87,255)     <- chroma preserved
exclusions x=[2,5)
  x=3 in=( 96,159, 56) out=( 96,159, 56) [kept]  <- excluded pixels byte-identical
```

## Running a guest command by hand

```sh
prlctl exec "Windows 11" cmd.exe /c "echo %PROCESSOR_ARCHITECTURE%"
prlctl exec "Windows 11" cmd.exe /c '\\Mac\Home\Documents\spdf-win\portable\win\guest-info.cmd'
```

## Gotchas

Each of these cost real time; they are written down so they cost it once.

**1. `prlctl exec` runs as `nt authority\system`, not as the logged-in user.**
Consequence: the mapped drive `Z:` that Parallels sets up for the interactive
user **does not exist** in that session. Guest tooling must use the UNC path
`\\Mac\Home\Documents\...` and never `Z:`.

**2. `~/Projects` is not shared with the guest.** Parallels exposes only
`Desktop`, `Documents` and `Downloads` from the Mac home directory, so the repo
is invisible from Windows no matter how the path is spelled. That is the entire
reason for the staging directory under `~/Documents`.

**3. `%ERRORLEVEL%` in a `&` chain is expanded at PARSE time.** The whole line
is parsed before any of it runs, so this silently reports the errorlevel from
*before* the command:

```
cmd /c "some-failing-thing & echo RC=%ERRORLEVEL%"   -> RC=0     WRONG
cmd /c "some-failing-thing & if errorlevel 42 ..."   -> correct
```
Verified: `cmd /c exit 42 & echo INLINE=%ERRORLEVEL%` prints `INLINE=0`. Use
`if errorlevel N`, which is evaluated at runtime, or a separate script line.

**4. `if COND cmd & other` runs `other` unconditionally.** cmd parses the `&`
chain as a sibling command, not as part of the `if` body. So
`if errorlevel 8 echo failed & exit /b 90` exits 90 on *every* run. Every
conditional in `guest-build.cmd` uses a parenthesised block for this reason.

**5. robocopy's exit code is a bit field, and success is `< 8`.** `0` = nothing
to do, `1` = files copied, `2` = extras, `3` = both. A plain `if errorlevel 1`
would fail every build that actually copied something. Only `>= 8` is failure.

**6. `vcvarsall.bat` breaks when invoked inside a `prlctl` `&` chain.** It
prints `The system cannot find the path specified.` and sets no environment, so
`cl` is then "not recognized". Inside a real `.cmd` file it works normally.
This is why `guest-build.cmd` and `guest-info.cmd` are script files rather than
one-liners. `cmd.exe /c` with a multi-line argument does not work either.

**7. macOS shell quoting.** `$` is expanded by the Mac shell and `&` separates
commands inside cmd, so guest command lines want **single** quotes on the macOS
side. Nesting quotes through `prlctl exec` gets bad fast — prefer putting the
logic in a `.cmd` file on the share and invoking that.

**8. The guest has no `head`, `grep`, `sed` or `git`.** Use `findstr`. Note
`findstr` sets errorlevel 1 on no-match, which makes it a reasonable exit-code
test but a poor thing to put mid-`&`-chain.

**9. Build from `C:\spdf`, not from the share.** Measured over the 4442 staged
files, warm on both sides: bulk header reads take **0.06s locally vs 0.58s over
the share (~9x)**. For the current 2-file smoke build the difference is *not*
measurable (0.06s either way) — but a MuPDF-scale build opens headers thousands
of times, so `guest-build.cmd` copies first. The copy itself is cheap: 85 MB /
4463 files in **2.6s cold, 0.25s warm** (robocopy `/MIR` skips unchanged files).

## Still to do

- Nothing is blocked on a human *for building and headless testing*. The VM is
  fully configured and needs no desktop session.
- **Something is blocked on a human for the window layer**, and no amount of
  work here will unblock it: see "What is and is not proven".
- No CMake project and no source manifest exists for the **app** target, so its
  translation units are spelled out by hand at every call site (see TL;DR).
  `guest-build.cmd` invokes `cl.exe` directly. CMake and Ninja are installed and
  are used for the MuPDF build, which generates its own `build.ninja`.
- Only three of the six `portable/core` suites are wired into the runner
  (`SPDFCoreRecolorTests`, `SPDFCoreCompatTests`, `SPDFCoreSaveTests`).
  `SPDFCoreOutlineTests`, `SPDFCorePasswordTests`, `SPDFCoreRenderThemeTests`,
  `SPDFCoreSelectionTests` and `SPDFCoreCJKSelectionTests` are written, are pure
  C over MuPDF, and would be near-free Windows conformance — they are simply not
  in `CORE_SUITES` yet.
- Nothing compares the **Direct2D compose** output automatically. The comparison
  has been run by hand and is byte-identical in both themes; the gap is coverage,
  not known incorrectness. (QC finding F3, still open.)

## What is and is not proven

This is the most important section in this file, and the easiest to skip.

**Proven, by exit code or by hashed pixels, re-run on demand:**

- The core renders byte-identically on Windows/MSVC/ARM64 and macOS/clang/arm64
  — same transcript, same PNG bytes, same sha256, for both an opaque and an
  alpha-bearing fixture.
- Every object in `libmupdf.lib`, `libmupdf-third.lib` and `ShenzhenPDF.exe` is
  native ARM64 (`AA64`), not x64 under emulation.
- The layout, zoom-anchor, clamp and LRU maths agree with the GTK4 originals.
- The render pool's callback-exactly-once and cancellation contracts hold.
- The state layer round-trips YAML and refuses to overwrite state it could not
  read.
- `ShenzhenPDF.exe` composes a page through Direct2D into a WIC bitmap with no
  window, and writes a PNG.

**Not proven, and not provable from this environment:**

- **That a window ever opens.** `prlctl exec` runs as `nt authority\system` with
  no interactive desktop. Nothing in any session so far has observed a
  ShenzhenPDF window on Windows — not the window appearing, not a resize
  repainting, not DPI scaling on a 2× display, not a clean exit on close.
- Anything else that requires an interactive session: real input events, menus,
  drag, the taskbar, file associations.

The honest one-line summary, which should survive every future edit of this
file: **the port is complete and verified at the core-and-pixels layer, unproven
at the window layer, and unprovable at the window layer from here.** Closing
that gap needs a human at the VM's GUI, or an interactive-session automation
route that does not yet exist.

## The application sources

`portable/win/src/`, 5,021 committed lines (Phase 1–3). A Phase 4 tab/session
layer is in flight and not counted here. Every file is under the 500-line cap
(`tools/check-file-sizes.sh` is green).

| file | LOC | role |
|---|---|---|
| `spdf_win_main.cpp` | 471 | entry point, `CommandLineToArgvW`, the two headless render modes |
| `spdf_win_window.{h,cpp}` | 519 | window class, message pump, DPI awareness, input |
| `spdf_win_d2d.{h,cpp}` | 536 | Direct2D device, scene compose, WIC PNG encode — **no `HWND` required** |
| `spdf_win_canvas.{h,cpp}` + `_internal.h` + `_prefetch.cpp` | 709 | continuous-scroll canvas, fit modes, neighbour prefetch |
| `spdf_win_layout.h` | 399 | the de-glib'd port of GTK4's `spdf_docview_internal.h`; differentially tested against it |
| `spdf_win_render.{h,c}` | 759 | background render pool, coalescing, cancellation tokens |
| `spdf_win_lru.{h,c}` | 460 | byte-bounded rendered-page cache |
| `spdf_win_paths.{h,c}` | 582 | `%APPDATA%` via `SHGetKnownFolderPath`, UTF-8⇄UTF-16 |
| `spdf_win_state.{h,c}` | 586 | YAML state layer over `portable/core/spdf_yaml.c` |

The one architectural rule that must not be broken: **`spdf_win_d2d.cpp` paints
into an `ID2D1RenderTarget` that may or may not be backed by a window.** The
window's `WM_PAINT` and the headless probe call the same compose path. If
painting ever requires an `HWND`, every pixel test in this directory dies with
it — and given the window layer is the one thing that cannot be verified here,
that would leave the port with no verification at all.

## The headless test harness

Everything above proves that *a* Windows build works. This section is about
proving that *the port* works — from macOS, by exit code and by pixel
comparison, with nobody looking at a screen.

```sh
portable/win/tests/run-tests.sh --self-check   # everything; exit 0 only if it all ran and passed
portable/win/tests/run-tests.sh --list
portable/win/tests/run-tests.sh --filter probe --keep
```

| file | role |
|---|---|
| `tests/run-tests.sh` | the runner: builds and runs the Windows test binaries and aggregates a real exit status |
| `tests/harness-lib.sh` | guest plumbing — `guest()`, `vm_build()`, prerequisite discovery |
| `tests/probe-cases.sh` | the eight cross-host probe cases (`probe.*` and `alpha.*`) |
| `tests/compare_png.py` | golden-image comparison, macOS render vs Windows render |
| `tests/png_io.py` | dependency-free PNG reader/writer (stdlib `zlib` only) |
| `tests/compare_png_selftest.py` | proves the comparator detects what it claims to |
| `tests/make_fixture_pdf.py` → `tests/fixtures/golden.pdf` | the deterministic test document |
| `spdf_win_probe.c` | the cross-host probe: same source, built on both hosts, transcripts diffed |
| `tests/exit_code_probe.c`, `tests/never_compiles.c` | canaries for the exit-code contract |
| `tests/narrow_path_probe.c`, `tests/non_ascii_path.ps1` | the code-page check below |

### Exit status

`run-tests.sh` exits **0** only when every selected case ran and passed;
**1** if any case failed; **2** if any case was *blocked* by a missing
prerequisite; **3** if a `--filter` matched nothing. Blocked is deliberately not
zero — a harness that reports success because it could not run anything is worse
than no harness, since everything layered on top of it inherits the lie.

That status is proven rather than asserted:

- `harness.exit-code` builds `tests/exit_code_probe.c` in the guest and runs it
  with 0, 3 and 42, checking each value arrives intact on the Mac, then compiles
  `tests/never_compiles.c` and fails the run if `vm-build.sh` returns 0.
- `--self-check` re-runs the script with a deliberate failure injected and
  refuses to proceed unless the runner's own exit status is non-zero.

Three habits keep it honest and none may be tidied away: no `set -e`; nothing
piped through `grep`/`tee` to decide pass or fail (a pipeline reports the *last*
command's status, so `prog | grep -c ok` is green when `prog` crashes); and the
final status computed from recorded results rather than from whatever ran last.

### The guest's code page is 1252, not UTF-8

`harness.non-ascii-path` checks this rather than assuming it, because assuming
it wrong is expensive: a harness that hands the guest a UTF-8 path gets a file
that does not exist and then blames the code under test. That is not
hypothetical — it is how a real failure in this port was first mis-diagnosed.

Windows narrows the real UTF-16 command line to the ANSI code page on the way
into `char** argv`, and `fopen` widens it back the same way. Observed in this
guest, for a directory named with an e-acute:

```
argv1-bytes 43 3A 5C ... 74 34 2D E9 64 69 72 5C 67 6F 6C 64 65 6E 2E 70 64 66
fopen ok                                  ^^ E9, not C3 A9
```

So CP1252-representable names round-trip; anything outside CP1252 will not, and
any narrow `fopen` in the port inherits that limit. The runner *reports* those
bytes rather than asserting them — the code page is a property of the guest, and
pinning `E9` here would turn a differently configured Windows into a spurious
failure.

`tests/non_ascii_path.ps1` is a script in the staged tree rather than an inline
`-Command`, because `prlctl exec` strips the quotes out of `-Command` and every
string literal vanishes. It spells the character as `[char]0xE9` so the file
itself stays pure ASCII: a literal would have to survive git, rsync, the
Parallels share and robocopy, and on macOS would also be exposed to NFC/NFD
normalisation — making the test's own input depend on which machine checked the
repo out.

### Adding a test for your track

Drop `portable/win/tests/<name>_test.c` in the directory — it is discovered
automatically as case `win.<name>_test`. Declare anything extra in the file:

```c
/* spdf-test-sources: portable/core/spdf_win_compat.c */
/* spdf-test-args: portable/win/tests/fixtures/golden.pdf */
/* spdf-test-needs: mupdf */
```

Paths are repo-relative; an argument naming a repo path is rewritten to the
guest's copy. `spdf-test-needs: mupdf` makes the case report BLOCKED instead of
FAILED while `libmupdf.lib` does not exist yet. No track needs to edit
`run-tests.sh` to be tested by it.

### `spdf_win_probe.c` — one source, two hosts, one diff

The probe exercises `spdf_open`, `spdf_page_count`, `spdf_page_size` and
`spdf_render_page_rgba_opts` and prints a transcript whose only intended
consumer is `diff`. Every line must be reproducible across two compilers on two
operating systems, so it contains no timings, no pointers, no full paths
(basenames are split on both `/` and `\`), and only integer statistics — a
floating-point mean could differ in its last digit and turn a healthy run red.
It deliberately avoids `clock_gettime`, which is absent from the MSVC UCRT.

```sh
spdf_win_probe <document> [page] [zoom] [out.png] [plain|dark|dark-images|alpha]
```

`probe.mac` builds it with clang against `mupdf/build/release-macos-*`;
`probe.win` builds it through `vm-build.sh`; `probe.diff` diffs the two
transcripts; `probe.png` compares the two rendered PNGs. `alpha.mac` /
`alpha.win` / `alpha.diff` / `alpha.png` do the same over `alpha.pdf` in `alpha`
mode.

**A failed PNG write is a failed run.** `write_png()` used to return `void`: it
caught the MuPDF throw, printed it to stderr, and returned, after which `main()`
printed `png <basename>` — a line that asserts the file exists — then `ok`, and
exited **0**. The exit code is the only signal `run-tests.sh` consults, so that
failure never happened as far as the harness was concerned. It now returns a
status, `main()` propagates it, and neither `png` nor `ok` is printed for a file
that was not written.

That mattered because it composed with a second defect into a complete false-pass
chain, which is worth spelling out since the whole port's headline claim rested
on it:

> the Windows probe fails to render → it exits 0 anyway → `probe.win` records
> **PASS** → `fetch_probe_png.ps1` returns the **previous** run's image →
> `probe.png` compares last run's Windows pixels against this run's macOS
> reference and reports **byte-identical**.

A real Windows render regression was invisible for as long as the stale file
survived. Three independent guards now close it, and each one alone is enough:

1. **The probe deletes its own output before rendering**, so "the file exists"
   means "*this* run wrote it" for every caller — harness, canary, or a hand
   invocation in the guest.
2. **`probe-cases.sh` clears the guest-side artifact before the run**, via its
   own `prlctl exec` (the Mac cannot reach `C:\` through the share) and verified
   by exit code rather than assumed — `del` reports success for a file it never
   found. The run refuses to start if the path could not be cleared.
3. **`fetch_probe_png.ps1` removes the file once it has read it.** It is a
   transport buffer, not an artifact; the durable copy is the one on the Mac.
   After a successful fetch there is nothing left to serve twice, and a second
   fetch with no intervening render fails loudly, which is the right answer to a
   question with no fresh data behind it.

Deleting *after* a run would have closed nothing: the entire hazard lives in the
window between a failed render and the next fetch. `tests/qc/probe-staleness-check.sh`
pins both halves and is green.

### `compare_png.py` — why one tolerance is not enough

A single MAE threshold has to be loose enough to tolerate two rasterisers
anti-aliasing the same glyph. Once it is that loose it will happily pass a
vertically flipped page, a BGRA page, or a half-scale render, because none of
those disturb the global statistics much. So the structural checks run first and
fail regardless of tolerance:

| check | the bug it catches |
|---|---|
| fully transparent / flat-colour output | the render target was never painted |
| flat-colour *reference* | the test itself is broken; fix it before trusting anything |
| vertical flip | a y-up rasteriser blitted into a y-down target |
| R/B channel swap | an RGBA core buffer read as BGRA |
| premultiplied vs straight alpha | the dark-halo bug this repo has already shipped once |
| transparent-pixel halo | the same bug in its invisible form — composited output looks perfect, and fringes the moment anything blends or filters the buffer |
| wrong scale | dimension ratio, DPI or device-pixel-ratio path |
| worst-block MAE | a small ruined region hiding inside a good whole-image average |

Only then does the tolerance apply, to two separate numbers: mean absolute error
of the image composited over white, and the fraction of pixels whose
per-channel delta exceeds `--delta`. It reports both, plus max channel delta,
the worst 16×16 block and its coordinates, a transparent-halo pixel count, and a
one-line diagnosis; `--json` writes the lot. `--strict` demands byte identity.

**The tolerance is pinned at zero, because zero is what was measured.** The port
plan requires it to be set from a real Windows render rather than assumed. The
render exists, and both fixtures come back byte-identical from the guest — same
pixels, same sha256 — so `probe-cases.sh` passes `--strict` and **`--strict`
decides the case**. It used to run "for the report only", with the case actually
decided by the loose provisional defaults (mae 1.5, 2% bad pixels); a regression
that stayed inside those would have passed a comparison known to be bit-exact.
The loose numbers survive only as a diagnostic scale — once `--strict` has failed
a case, a second loose run says whether the drift is subtle or gross and names
the bug. If byte-identity ever becomes genuinely unattainable, record the newly
observed numbers in `compare_png.py` with the run that produced them. Never widen
a threshold to make a failing comparison pass.

`compare_png_selftest.py` is the argument that any of this can be trusted. It
mutates a synthetic reference with one known port bug at a time and asserts both
that the comparison fails *and* that the diagnosis names the right bug —
a comparator that fails everything would be as useless as one that passes
everything, so the unmutated and jitter cases must pass. 13 checks, including
decoding a real MuPDF-written PNG.

### Where it stands

The `libmupdf.lib` `LNK2048` alignment defect that once blocked `probe.win`,
`probe.diff`, `probe.png` and `SPDFCoreSaveTests` **is fixed** — see the MuPDF
chapter below, which builds, links and renders in the guest. There is a Windows
render, it is byte-identical to the macOS one, and the tolerance is pinned at
zero accordingly. (This section claimed the opposite for a while, two hundred
lines before the chapter proving otherwise; a reader who stopped here concluded
the port had no Windows render at all.)

### The current case list

`portable/win/tests/run-tests.sh` → **20 cases, 0 failed, 0 blocked, exit 0**,
in about 50 seconds. This is the inventory as run, not as remembered:

| case | what it proves |
|---|---|
| `selftest.compare-png` | every golden-image detector fires on its own mutation (13 checks) |
| `harness.exit-code` | guest exit codes 0/3/42 and a failed compile all reach the Mac intact |
| `harness.non-ascii-path` | narrow `argv` round-trips a CP1252 path; reports the bytes rather than pinning them |
| `probe.mac` / `probe.win` | the cross-host probe builds and runs on both hosts (opaque `golden.pdf`) |
| `probe.diff` | identical **43-line** transcript, macOS/clang vs Windows/MSVC |
| `probe.png` | rendered PNGs **byte-identical** (`--strict`) |
| `alpha.mac` / `alpha.win` | same, over the transparent `alpha.pdf` in `alpha` mode |
| `alpha.diff` | identical **42-line** transcript |
| `alpha.png` | byte-identical over 49,660 partially transparent px — the alpha detectors are live here |
| `core.SPDFCoreRecolorTests` | the recolor core, no MuPDF needed |
| `core.SPDFCoreCompatTests` | the POSIX shim in `portable/core/spdf_win_compat.c` |
| `core.SPDFCoreSaveTests` | the Windows save path, incl. replace-existing rename |
| `win.layout_geometry_test` | continuous layout, fit zooms, zoom anchoring, clamp, byte cap |
| `win.lru_cache_test` | the byte-bounded rendered-page cache |
| `win.paths_test` | `%APPDATA%` resolution and UTF-8⇄UTF-16 |
| `win.render_service_test` | worker pool, tokens, callback-exactly-once |
| `win.silent_failure_test` | the three silent-failure fixes (QC F5, F6, F7) |
| `win.state_test` | YAML state round-trip, session lock, absent-vs-failed reads |

Two transcript lengths, both measured and both easy to confuse: the **probe** is
43 lines, the **alpha** probe is 42, and `verify.sh`'s separate `spdf_recolor`
transcript is 61. The runner prints each count from its own measurement so none
of them can drift in prose again.

A separate QC canary, not part of the 20:

```sh
bash portable/win/tests/qc/probe-staleness-check.sh   # exit 0
#   ok  defect 1 fixed: a failed PNG write exits 1
#   ok  defect 2 fixed: the guest PNG is gone after a run that wrote none
```

The port's headline pixel claim, stated precisely: the rendered PNGs are
byte-identical across hosts — `sha256 00432a55a58dbfe1…` for `golden.pdf` in
`plain` mode, `sha256 32c0e3b9de92eeeb…` for `alpha.pdf` in `alpha` mode.

`SPDFCoreSaveTests` deserves its own line: it is newly passing not because the
code changed but because it had **never actually run**. `guest_run()` pasted its
argument straight onto the closing quote of the executable path, cmd answered
*"The filename, directory name, or volume label syntax is incorrect"*, and the
harness reported the result as a failure in `portable/core` — sending every
reader to the wrong file while the only suite that exercises the Windows save
path silently never launched. The separator is now inserted by `guest_run()`
itself rather than left to each caller's convention.

A build that fails *inside* `libmupdf.lib` is recorded BLOCKED rather than
FAILED so the report points at the party who can fix it. That does not change
the exit status and the case still counts against the run. The match is
deliberately narrow — a linker error attributed to an object inside
`libmupdf.lib`, nothing else — because treating link errors generally as
infrastructure would hide exactly the unresolved-symbol failures the harness
exists to surface.

### The fixtures

`tests/fixtures/golden.pdf` is hand-assembled by `tests/make_fixture_pdf.py`
(no MuPDF, no reportlab — nothing that could drift and silently change the
golden image) and regenerates byte-for-byte. Every element earns its place: it
is asymmetric top-to-bottom so a vertical flip is unmissable, carries unequal
pure-red and pure-blue regions so a channel swap cannot be confused with the
flip, has text and hairlines so anti-aliasing differences show up somewhere real,
and its second page is a different size from its first.

`tests/fixtures/alpha.pdf` exists because `golden.pdf` **cannot** do the other
half of the job. It paints an opaque white backdrop and renders fully opaque —
alpha 255 everywhere — and premultiplying a fully opaque image is the identity
transform. So the comparator's two alpha guards, the pair aimed squarely at the
premultiplied-alpha halo this repo has already shipped once, could not fire on
any real comparison in the suite however broken the render was. Measured
directly: premultiplying the `golden.pdf` reference, and recolouring every one of
its transparent pixels, both still **pass** `--strict`. The same two mutations of
the `alpha.pdf` reference fail, and are named correctly (`PREMULTIPLIED ALPHA`
over 49,660 partially transparent pixels; `TRANSPARENT-PIXEL HALO`, 84,690 px).
The halo case is the one that shows why this matters: it scores mean absolute
error **0.0000** and max channel delta **0**, so no tolerance, no block check and
no checksum over composited output can see it — only a detector pointed at an
image that actually has alpha.

`alpha.pdf` has a transparent page background (no backdrop fill at all), two
constant-alpha graphics states over overlapping rectangles, text under 50% alpha,
and an image XObject with an `/SMask` cut-out whose mask has hard 0 and 255
plateaus and a graded rim. Its render carries 49,660 partially transparent pixels
across alpha 0–255.

It is compared through the probe's `alpha` mode rather than `plain`, and that is
a finding in itself: **no PDF fixture can produce a non-opaque render through the
shipping core entry point.** `spdf_render_page_rgba_opts` creates its pixmap with
`alpha=0` on all three of its paths, and `copy_pixmap_to_bitmap` then writes a
literal 255 into every alpha byte. The core's output is opaque by construction,
whatever the document says — a reasonable choice for a page renderer, but it
means the alpha detectors could never have been exercised by adding a fixture
alone. `alpha` mode renders through MuPDF directly with an alpha-bearing pixmap
and un-premultiplies into the straight-alpha RGBA convention `spdf_bitmap`
documents and the Direct2D path consumes. It proves something narrower than the
`plain` transcript — that the two toolchains agree bit-for-bit on alpha
compositing — and it makes two dead detectors live.

---

# Building MuPDF for Windows ARM64

*(Track T0. Files: `mupdf-build.sh`, `mupdf-build.cmd`, `mupdf-gen-ninja.sh`,
`mupdf-bin2coff.c`, `mupdf-arch-check.{sh,cmd}`, `mupdf-render-check.sh`.)*

`libmupdf` now builds natively for ARM64 in the guest, and a real PDF page
rendered through `portable/core` on Windows is **byte-identical** to the same
page rendered on macOS. That equality is the whole point: it is what makes every
later pixel comparison in this port mean something.

## TL;DR

```sh
portable/win/mupdf-build.sh          # ~59 s cold, ~3 s when nothing changed
portable/win/mupdf-arch-check.sh     # proves every object is AA64, not x64
portable/win/mupdf-render-check.sh   # renders a page on both hosts and diffs it
portable/win/verify.sh               # all of the above plus the original 1-4
```

## Which MuPDF, and where it comes from

**MuPDF 1.27.2**, the tree already vendored at `mupdf/` in this repo — the exact
one `portable/Makefile` builds the macOS app against (`MUPDF_DIR := ../mupdf`,
output in `mupdf/build/release-macos-arm64-12.0/`). Nothing is downloaded and
no second copy exists. `sync-to-vm.sh` gained `mupdf` in `SUBTREES`, so the
guest compiles the same files the Mac does.

Two wrinkles about that tree are worth knowing:

- **`mupdf/thirdparty/*` are symlinks into `ext/`** (`freetype -> ../../ext/freetype`
  and ten more). Parallels does not present macOS symlinks to Windows in a form
  robocopy or `cl.exe` can follow, so `sync-to-vm.sh` stages with
  `--copy-unsafe-links` and the guest gets real directories.
- **`mupdf/generated/` is `.gitignore`d.** It holds the 182 embedded fonts and
  the hyphenation dictionary hexdumped into C, produced by the macOS MuPDF
  build. The Windows build does not compile it (see below) but
  `mupdf-gen-ninja.sh` still reads it, and refuses to run without it — because
  its absence means this Mac has never built the MuPDF the comparison is
  against.

## How the build description is produced

There is no checked-in `build.ninja` and no use of `mupdf/platform/win32/mupdf.sln`.
`mupdf-gen-ninja.sh` runs `make -n` **inside `mupdf/` with exactly the arguments
`portable/Makefile:113` uses**, and mechanically translates the printed compile
lines into `cl.exe` flags:

```sh
make -n build=release OUT=build/win-manifest-dryrun \
     ARCHFLAGS="-arch arm64" USE_SYSTEM_GLUT=yes brotli=no libs
```

This matters more than it looks. `mupdf.sln` does carry ARM64 configurations
(619 references), but its feature set is its own — barcode, tesseract, brotli, a
different font selection — and it would drift from the Mac build silently, which
is the one failure this port cannot detect by looking at the output. Deriving
the recipe from the Makefile means changing `portable/Makefile`'s MuPDF
arguments changes the Windows build too, automatically.

The result is **646 translation units in 14 flag groups**, one response file per
group, emitted into `$SPDF_WIN_STAGE/mupdf-win/` (outside every subtree
`sync-to-vm.sh` mirrors with `--delete`, so it survives the next sync).
Unknown flags are a hard error rather than a silent drop.

Flag translation, in full:

| POSIX | MSVC | note |
|---|---|---|
| `-O2` / `-O0` | `/O2` / `/Od` | |
| `-ffunction-sections` / `-fdata-sections` | `/Gy` / `/Gw` | |
| `-I…` | `-I…` | rewritten to the guest's `C:/spdf/mupdf/…` |
| `-D…` | `-D…` | verbatim, **including the backslashes** (below) |
| `-DHAVE_UNISTD_H` | *dropped* | MSVC has no `<unistd.h>`; zlib only uses it to decide whether to include it for `fdopen`, so no compressed byte changes |
| `-Wall -Wsign-compare …` | `/W3` (mupdf's own C), `/W1` (thirdparty), `/W0` (C++) | plus `/we4013`, below |
| `-std=gnu++11`, `-fno-exceptions`, `-fno-rtti`, `-fno-threadsafe-statics` | `/std:c++14 /EHs-c- /GR- /Zc:threadSafeInit-` | harfbuzz |
| `-pipe`, `-MMD`, `-MP`, `-mmacosx-version-min=…` | *dropped* | ninja uses `/showIncludes` for dependencies |

Everything also gets `/MT /utf-8 /Zc:inline /D_CRT_SECURE_NO_WARNINGS`, and
gumbo-parser additionally gets `-Ithirdparty/gumbo-parser/visualc/include`,
which is where gumbo keeps its MSVC `<strings.h>` shim. `mupdf.sln`'s
`libthirdparty` project adds that same directory for that same reason.

**`/we4013` is deliberate and load-bearing.** Under MSVC an implicit function
declaration is a *warning*, so a POSIX function that does not exist on Windows
compiles to a call returning `int` and fails at link time — or worse, links
against something unrelated. Promoting C4013 to an error over MuPDF's own 232
sources means a missing function stops the build at the file that wanted it.
All 232 compile clean at `/W3` with it on.

## The font blob problem

**MSVC cannot compile MuPDF's embedded resources, and this is the one place the
Windows build deliberately differs from the POSIX one.**

On POSIX the 182 fonts and the hyphenation dictionary arrive as
`generated/resources/**.c`: a chain of `"\xNN"` string literals per file, from
`mupdf/scripts/hexdump.sh`. `cl.exe` needs multiple GB of heap per megabyte of
literal. Measured in this VM (16 GB, 8 cores):

| `.c` size | result |
|---|---|
| under ~1.5 MB | compiles |
| ~1.5–4 MB | `fatal error C1060: compiler is out of heap space` under `-j8` |
| over ~4 MB | C1060 even at `-j1` |

and `generated/resources/fonts/han/SourceHanSerif-Regular.ttc.c` is **103 MB**.
There is no parallelism setting that makes that work.

So the 182 blobs are embedded from their **original binaries** under
`mupdf/resources/` by `portable/win/mupdf-bin2coff.c`, which writes a COFF object
exporting `_binary_<name>` and `_binary_<name>_size` — the same interface
`hexdump.sh` produces, so MuPDF's sources link against it unchanged. The
embedded bytes are identical; only the route into the object file differs. The
generator derives each symbol name with hexdump.sh's own rule
(`sed 's/[.-]/_/g'`) **and then checks it against the second line of the .c that
hexdump.sh actually produced**, so a rename in either tool fails the generator
rather than the link. Net effect on staging: `mupdf/generated/` (190 MB) is
excluded and `mupdf/resources/` (56 MB) is included.

**Why not `mupdf/scripts/bin2coff.c`, which exists and does exactly this?**
Because its ARM64 output does not link. It puts the size word immediately after
the data with no padding, so any blob whose length is not a multiple of 4 gets
an unaligned size symbol:

```
libmupdf.lib(hyphen.obj) : error LNK2048: relocation PAGEOFFSET_12L targeting
'_binary_hyph_all_zip_size' (0056EC03) is invalid for the instruction
(B9400102 at RVA 00055DEC) ... due to bad alignment of offset to target (C03);
expected to be 4 bytes aligned
```

AArch64's `LDR` (immediate) cannot address it. Roughly three quarters of the 182
blobs have a length that is not a multiple of 4, so this is systemic, not bad
luck — `mupdf.sln`'s ARM64 configurations look untested here.
`mupdf-bin2coff.c` pads to 8 and puts the section in `.rdata` with 16-byte
alignment. It is ~200 lines and writes every COFF field byte by byte rather than
through packed structs, because COFF is fully specified and struct packing is not.

## What gets built, and how long it takes

| | |
|---|---|
| `C:\spdf-build\mupdf\libmupdf.lib` | 58.5 MB, **417 objects** (MuPDF proper + the 182 embedded blobs) |
| `C:\spdf-build\mupdf\libmupdf-third.lib` | 15.2 MB, **229 objects** (freetype, harfbuzz, libjpeg, lcms2, zlib, jbig2dec, openjpeg, mujs, gumbo, extract) |
| clean build | **59 s** wall clock from the Mac, 8 cores, `ninja -j8` |
| no-op rebuild | ~3 s, nearly all of it robocopy and `prlctl` |
| staging | 233 MB / 8323 files; guest robocopy of that is seconds |

There is no `libmupdf-pkcs7.lib`: the macOS build sets `HAVE_LIBCRYPTO=no`, and
its `libmupdf-pkcs7.a` is 1336 bytes of nothing. Signature verification is a
later phase's problem, and adding it here would be a difference from the Mac.

## The linking interface — what other tracks get

**No track needs to edit any of T0's files to link MuPDF.** `guest-build.cmd`
already does all of this:

| | |
|---|---|
| include path | `C:\spdf\mupdf\include`, plus `C:\spdf\portable\core` and `C:\spdf\portable\win\src` |
| libraries | `libmupdf.lib` and `libmupdf-third.lib`, linked **when they exist** |
| system libraries | `user32 gdi32 shell32 ole32 oleaut32 advapi32 shcore d2d1 dwrite windowscodecs uuid` |
| CRT | `/MT` — static, and `libmupdf.lib` is `/MT` too. Mixing CRTs here produces link errors that read like missing symbols |
| stack | `/STACK:8388608`, matching macOS's 8 MB main thread. Windows defaults to 1 MB and MuPDF's content-stream and CSS recursion can outrun that |
| objects | `C:\spdf-build\obj-<target>\`, one directory per target — several repo sources share a basename (`buffer.c`, `image.c`, `util.c`) and a flat `/Fo` would have them overwrite each other |

"When they exist" is deliberate: the tracks whose code is pure C keep building
on a machine where MuPDF has never been built, and get a one-line note instead
of a link failure. The linker only pulls the objects a symbol actually needs, so
a target that ignores MuPDF pays nothing.

`vm-build.sh` also grew a way to pass arguments to the program it runs:

```sh
portable/win/vm-build.sh --run core_smoke <sources...> \
    -- 'C:\spdf\portable\win\smoke\smoke.pdf' 0 2.0 \
       '\\Mac\Home\Documents\spdf-win\out\page.rgba'
```

Everything after a lone `--` is a **guest** argument. Note the second path: the
share is writable from the guest, so a probe can drop its output straight onto
the Mac with no copy step. Use `$SPDF_WIN_STAGE/out/`, which sits outside every
subtree `sync-to-vm.sh` mirrors and therefore is not deleted on the next sync.

## Proof it is native ARM64

Windows on ARM runs x64 under emulation without complaint, so "it built and it
ran" proves nothing about the target architecture. `mupdf-arch-check.sh` runs
`dumpbin /headers` over both archives and asserts that **every** member reports
`AA64`:

```
   libmupdf.lib             417 objects  AA64 ARM64
   libmupdf-third.lib       229 objects  AA64 ARM64
   core_smoke.exe             1 objects  AA64 ARM64
ARCH CHECK OK: every member is AA64 (native ARM64)
```

It fails on the first non-`AA64` member. One x64 object would still link on some
paths and would make the whole claim false.

## Proof the pixels match

`portable/win/smoke/core_smoke.c` opens a PDF through
`portable/core/shenzhen_pdf_core.h`, prints the page count and page size,
renders a page with `spdf_render_page_rgba_opts`, prints an FNV-1a digest of the
pixels and nine sampled points, and optionally dumps the raw RGBA.
`mupdf-render-check.sh` builds it twice — clang/arm64 against
`mupdf/build/release-macos-arm64-12.0`, MSVC/ARM64 against `C:\spdf-build\mupdf`
— runs both on the same fixture and compares the report *and* the raw bytes.

The fixture, `portable/win/smoke/smoke.pdf`, is generated by
`make_smoke_pdf.py` (the repo's root `.gitignore` excludes `*.pdf`) and is
chosen to load the code most likely to diverge between two compilers: text in
two base-14 faces at five sizes, a bezier, a dashed stroked polyline, a rotated
and scaled text matrix, constant-alpha fills over other fills, and an upscaled
inline RGB image.

Result, measured — not assumed:

```
   render zoom=2.0000 -> 600x800 stride=2400
   rgba fnv1a=b6f5f36846f24e18 bytes=1920000
   BYTE-IDENTICAL: 1920000 bytes of RGBA, macOS clang/arm64 == Windows MSVC/ARM64
```

Also byte-identical at page 1 zoom 1.0 (480,000 bytes), page 0 zoom 3.5
(5,880,000 bytes) and page 1 zoom 0.75 (270,000 bytes). Stride matched too, at
every size.

**So the tolerance for core render comparisons is zero, and it should stay zero.**
The plan (§6, risk 6) left this open pending measurement; the measurement says
the two toolchains agree exactly on this content, which is the strongest
possible starting point. If a future MuPDF or toolchain introduces real drift,
widen the tolerance *then*, with the measurement that justifies it recorded next
to it. `mupdf-render-check.sh` prints differing-byte count, max per-channel
delta and mean absolute error when a comparison fails, so that measurement is
one run away.

## Gotchas (in addition to 1–9 above)

**10. MSVC dies on large string literals, not large arrays.** The failure is
`fatal error C1060: compiler is out of heap space`, it is memory-driven rather
than a hard limit, and it therefore depends on `-j`: the same file can compile
alone and fail under `-j8`. Do not spend time tuning parallelism — see "The font
blob problem".

**11. `\"` in a response file must stay escaped.** `cl` parses a response file
with the same CRT `argv` rules as a command line, so a bare `"` is a grouping
quote it strips. `-DFT_CONFIG_OPTIONS_H="slimftoptions.h"` therefore arrives as
`FT_CONFIG_OPTIONS_H=slimftoptions.h` and freetype fails with
`error C2006: '#include': expected "FILENAME" or <FILENAME>`. Keep the
backslashes exactly as `make -n` prints them.

**12. ninja here does NOT put a shell between itself and the command.** A
trailing `>nul` arrives as an extra `argv` entry, not a redirection — which is
how `bin2coff` came to print its usage message 182 times instead of embedding
anything. Redirect from the `.cmd` wrapper instead, or not at all.

**13. `rsync --delete` PROTECTS files that are already excluded.** Changing an
exclude does not clean up what the old rule copied; `sync-to-vm.sh` needs
`--delete-excluded`, or 190 MB of `mupdf/generated/` lingers in the staging tree
and is robocopied into the guest on every build forever.

**14. `robocopy /MIR` will delete build output that lives under its
destination.** `C:\spdf-build` is deliberately a sibling of `C:\spdf`, never a
child. `mupdf-build.cmd` runs ninja from `C:\spdf-build\mupdf` for exactly this
reason: build.ninja names its objects relative to *there* and its sources
absolutely under `C:\spdf\mupdf`.

**15. Escape `:` in ninja paths.** Ninja treats `:` as a field separator in path
positions, so a Windows absolute path has to be written `C$:/spdf/mupdf/...`.
Inside a variable value (`flags = ...`) it needs no escaping.

**16. `ninja -k 0`.** `mupdf-build.cmd` passes it always. Without it ninja stops
scheduling after the first failure, and a 646-edge build reports one broken file
per round trip to the VM — which, at a minute a round trip, is the difference
between one debugging session and six.

**17. The guest has no `timeout`, and macOS `zsh` does not word-split unquoted
expansions.** Both cost time in this session; neither is a Windows problem.

**18. `portable/core/spdf_win_compat.c` belongs in EVERY Windows source list.**
It is the POSIX shim the core's own sources `#include "spdf_win_compat.h"` from
(`shenzhen_pdf_core.c:5`, `spdf_yaml.c:6`, and six of the core test suites), so
omitting it produces a wall of `LNK2019: unresolved external symbol
spdf_compat_*` rather than a compile error at the file that wanted it. Note the
path: it lives under `portable/core/`, **not** `portable/win/src/`. This README
told you `portable/win/src/spdf_win_compat.c` for a while, and
`run-tests.sh`'s own header comment still does; the file has only ever been in
`portable/core/`.

**19. `-ffp-contract=off` on the macOS side is load-bearing, not a workaround.**
It is the reason cross-host float results come back byte-identical. clang
contracts `a*b + c` into a single fused multiply-add — one rounding step instead
of two — while MSVC under `/fp:precise` (what `guest-build.cmd` uses) does not
fuse. Same IEEE-754 arithmetic, same ARM64 hardware, different results in the
last bit, and a golden-image comparison pinned at zero tolerance goes red.
`portable/win/tests/t3-verify.sh:41-47` builds the macOS side with it for
exactly this reason. Do not remove it to "match the release flags"; the release
flags are not being compared to anything.

**20. The guest ANSI code page is 1252, not UTF-8.** Windows narrows the real
UTF-16 command line to the ACP on the way into `char** argv`, so a CP1252-
representable path round-trips through a narrow `fopen` and anything outside
CP1252 does not. `harness.non-ascii-path` checks this rather than assuming it —
assuming it wrong is how a real failure in this port was first mis-diagnosed.
See "The guest's code page is 1252, not UTF-8" above for the observed bytes.
