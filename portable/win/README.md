# Building ShenzhenPDF code on Windows, from the Mac

This directory is the Windows port's build plumbing: everything needed to
compile and run repo C/C++ **inside a Parallels Windows VM, driven entirely
from the macOS command line, without ever touching the VM's GUI**.

No application code lives here yet. The only C in this directory is a smoke
test whose job is to prove the chain works.

## TL;DR

```sh
portable/win/verify.sh          # full proof; exits non-zero if anything is broken

portable/win/vm-build.sh --run recolor_smoke \
    portable/win/smoke/recolor_smoke.c portable/core/spdf_recolor.c
echo $?                         # this is the GUEST compiler's exit code
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

- Nothing is blocked on a human. The VM is fully configured and headless.
- No CMake project exists yet — CMake and Ninja are installed and ready but
  unused; `guest-build.cmd` currently invokes `cl.exe` directly, which is the
  right level for a smoke test but will want replacing when real sources land.
- MuPDF itself has never been built here; only `portable/core` has.

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
| `tests/compare_png.py` | golden-image comparison, macOS render vs Windows render |
| `tests/png_io.py` | dependency-free PNG reader/writer (stdlib `zlib` only) |
| `tests/compare_png_selftest.py` | proves the comparator detects what it claims to |
| `tests/make_fixture_pdf.py` → `tests/fixtures/golden.pdf` | the deterministic test document |
| `spdf_win_probe.c` | the cross-host probe: same source, built on both hosts, transcripts diffed |
| `tests/exit_code_probe.c`, `tests/never_compiles.c` | canaries for the exit-code contract |

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

### Adding a test for your track

Drop `portable/win/tests/<name>_test.c` in the directory — it is discovered
automatically as case `win.<name>_test`. Declare anything extra in the file:

```c
/* spdf-test-sources: portable/win/src/spdf_win_compat.c */
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
spdf_win_probe <document> [page] [zoom] [out.png] [plain|dark|dark-images]
```

`probe.mac` builds it with clang against `mupdf/build/release-macos-*`;
`probe.win` builds it through `vm-build.sh`; `probe.diff` diffs the two
transcripts; `probe.png` compares the two rendered PNGs.

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

**The tolerance defaults are marked UNMEASURED on purpose.** The port plan
requires them to be set from a real Windows render and pinned. Until
`libmupdf.lib` exists in the guest there is no such render, and inventing a
number would be exactly the dishonesty the plan warns against. When the first
comparison runs: try `--strict` first, and if it is byte-identical, pin the
defaults at zero.

`compare_png_selftest.py` is the argument that any of this can be trusted. It
mutates a synthetic reference with one known port bug at a time and asserts both
that the comparison fails *and* that the diagnosis names the right bug —
a comparator that fails everything would be as useless as one that passes
everything, so the unmutated and jitter cases must pass. 13 checks, including
decoding a real MuPDF-written PNG.

### The fixture

`tests/fixtures/golden.pdf` is hand-assembled by `tests/make_fixture_pdf.py`
(no MuPDF, no reportlab — nothing that could drift and silently change the
golden image) and regenerates byte-for-byte. Every element earns its place: it
is asymmetric top-to-bottom so a vertical flip is unmissable, carries unequal
pure-red and pure-blue regions so a channel swap cannot be confused with the
flip, has text and hairlines so anti-aliasing differences show up somewhere real,
and its second page is a different size from its first.
