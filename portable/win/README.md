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
