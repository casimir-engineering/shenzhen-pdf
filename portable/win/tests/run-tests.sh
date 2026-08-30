#!/usr/bin/env bash
# The Windows port's headless test runner. Runs from macOS; never opens the VM's
# desktop, never launches the macOS app.
#
#   portable/win/tests/run-tests.sh [--list] [--filter PAT] [--self-check]
#                                   [--wait-for-toolchain SECONDS] [--keep] [--quiet]
#
# ---------------------------------------------------------------------------
# THE ONE THING THIS SCRIPT MUST GET RIGHT
#
# It must exit non-zero when a Windows test fails. A harness that always exits 0
# does not merely fail to help -- it silently blesses every broken change made
# after it, and every later track's "green" becomes meaningless. Everything else
# here is secondary to that.
#
# Three habits protect it, and none of them may be "simplified" away:
#   1. No `set -e`: an early exit would skip the aggregation entirely.
#   2. NOTHING is piped through grep/tee/head to decide pass or fail. A pipeline
#      reports the LAST command's status, so `prog | grep -c ok` is green when
#      prog crashes. Output goes to a file with `> log 2>&1`; the very next
#      statement reads $?.
#   3. Every case's status is recorded and the exit status is computed from the
#      records at the end -- never from whatever ran last.
#
# The `harness.exit-code` case proves point 1-3 empirically by running a guest
# binary that deliberately exits 3 and 42, and `--self-check` proves the runner
# itself turns a failing case into a non-zero exit.
#
# ---------------------------------------------------------------------------
# HONEST DEGRADATION
#
# The guest toolchain is being built by another track while this runs. A case
# whose prerequisites are missing is recorded BLOCKED, printed with the exact
# thing that is missing, and still makes the run exit non-zero -- exit 2 rather
# than 1, so "waiting on the toolchain" is distinguishable from "the code is
# broken", but never zero. A harness that reports success because it could not
# run anything is the failure mode this whole file exists to prevent.
#
# GUEST NOTES: `prlctl exec` runs as nt authority\system, where the interactive
# user's Z: drive does not exist -- address the staging tree by UNC path. The
# guest has no head/grep/tail; use findstr if you must filter guest-side, but
# prefer bringing output back and deciding here. The macOS shell expands $ inside
# double quotes and cmd.exe uses %, so guest command lines are assembled from
# SINGLE-quoted fragments.
#
# ADDING A TEST: drop `portable/win/tests/<name>_test.c` here and it is
# discovered automatically. Declare extra translation units, runtime arguments
# and prerequisites in the file itself; paths are repo-relative and an argument
# naming a repo path is rewritten to the guest's copy:
#
#     /* spdf-test-sources: portable/win/src/spdf_win_compat.c */
#     /* spdf-test-args: portable/win/tests/fixtures/golden.pdf */
#     /* spdf-test-needs: mupdf */
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TESTS_DIR="$REPO_ROOT/portable/win/tests"
OUT="$REPO_ROOT/portable/win/build/t4"
VM_NAME="${SPDF_VM_NAME:-Windows 11}"
STAGE="${SPDF_WIN_STAGE:-$HOME/Documents/spdf-win}"
VM_BUILD="$REPO_ROOT/portable/win/vm-build.sh"
FIXTURE="portable/win/tests/fixtures/golden.pdf"

# Guest-side constants. Single-quoted: backslashes and % must survive verbatim.
GUEST_TREE='C:\spdf'
GUEST_OUT='C:\spdf-build'
GUEST_SHARE='\\Mac\Home\Documents\spdf-win'
# The drop box the guest writes results into. portable/win/build/ is excluded
# from sync-to-vm.sh's rsync, so it is never deleted out from under a run.
GUEST_DROP="$GUEST_SHARE"'\portable\win\build\t4'

FILTER=""
LIST=0
KEEP=0
QUIET=0
SELF_CHECK=0
WAIT_SECS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list) LIST=1; shift ;;
    --filter) FILTER="${2:-}"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    --quiet) QUIET=1; shift ;;
    --self-check) SELF_CHECK=1; shift ;;
    --wait-for-toolchain) WAIT_SECS="${2:-0}"; shift 2 ;;
    -h|--help) sed -n '2,60p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "run-tests: unknown option $1" >&2; exit 64 ;;
  esac
done

mkdir -p "$OUT" "$STAGE/portable/win/build/t4"

# Guest plumbing, result recording and prerequisite discovery.
. "$TESTS_DIR/harness-lib.sh"

# --- cases -----------------------------------------------------------------

case_compare_png_selftest() {
  local log="$OUT/compare-png-selftest.log"
  # bash 3.2 (the macOS system bash) errors on "${arr[@]}" for an empty array
  # under `set -u`, so the decode argument is carried as a plain string.
  local extra=""
  [[ -f "$OUT/mac/probe-page.png" ]] && extra="--decode $OUT/mac/probe-page.png"
  # shellcheck disable=SC2086
  python3 "$TESTS_DIR/compare_png_selftest.py" $extra > "$log" 2>&1
  local rc=$?
  if [[ $rc -eq 0 ]]; then
    record "selftest.compare-png" PASS "every golden-image detector fired correctly"
  else
    record "selftest.compare-png" FAIL "comparator self-test exited $rc"
    log_tail "$log" 14
  fi
}

# The proof that the whole chain is honest, run before anything that depends on
# it. Every assertion here is about an exit STATUS, never about output text.
case_exit_code() {
  if [[ -n "$GUEST_READY" ]]; then
    record "harness.exit-code" BLOCKED "$GUEST_READY"
    return
  fi

  guest "$OUT/exit0.log" 'exit /b 0'; local rc0=$?
  guest "$OUT/exit7.log" 'exit /b 7'; local rc7=$?
  if [[ $rc0 -ne 0 || $rc7 -ne 7 ]]; then
    record "harness.exit-code" FAIL "prlctl exec does not propagate guest exit codes (got $rc0 for 0, $rc7 for 7)"
    return
  fi

  vm_build "$OUT/never-compiles.log" spdf_never_compiles portable/win/tests/never_compiles.c
  local rcbad=$?
  if [[ $rcbad -eq 0 ]]; then
    record "harness.exit-code" FAIL "vm-build.sh returned 0 for a source that cannot compile -- a broken Windows build would look green"
    return
  fi

  vm_build "$OUT/exit-probe-build.log" spdf_exit_code_probe portable/win/tests/exit_code_probe.c
  local rcb=$?
  if [[ $rcb -ne 0 ]]; then
    record "harness.exit-code" FAIL "could not build the exit-code canary (vm-build exited $rcb)"
    log_tail "$OUT/exit-probe-build.log"
    return
  fi

  local want got
  for want in 0 3 42; do
    guest "$OUT/exit-probe-$want.log" "$GUEST_OUT"'\spdf_exit_code_probe.exe '"$want"
    got=$?
    if [[ $got -ne $want ]]; then
      record "harness.exit-code" FAIL "a guest binary exiting $want was seen as $got on the Mac"
      return
    fi
  done
  record "harness.exit-code" PASS "guest exit codes 0/3/42 and a failed compile all reach the Mac intact"
}

# Only meaningful under --self-check, which re-runs this script with the env var
# set and asserts the outer exit status is non-zero. Without it, a runner bug
# that swallowed failures would be invisible to the runner's own suite.
case_forced_failure() {
  if [[ "${SPDF_FORCE_FAIL:-0}" != "1" ]]; then
    return
  fi
  record "harness.forced-failure" FAIL "deliberate failure injected by --self-check"
}

case_probe_mac() {
  if ! find_mac_mupdf; then
    record "probe.mac" BLOCKED "no macOS libmupdf.a under mupdf/build (run: make -C portable mupdf)"
    return
  fi
  mkdir -p "$OUT/mac"
  local log="$OUT/probe-mac-build.log"
  cc -O2 -Wall -Wextra -I"$REPO_ROOT/portable/core" -I"$REPO_ROOT/mupdf/include" \
     -o "$OUT/spdf_win_probe_mac" \
     "$REPO_ROOT/portable/win/spdf_win_probe.c" \
     "$REPO_ROOT/portable/core/shenzhen_pdf_core.c" \
     "$REPO_ROOT/portable/core/spdf_recolor.c" \
     "$MAC_MUPDF/libmupdf.a" "$MAC_MUPDF/libmupdf-third.a" "$MAC_MUPDF/libmupdf-pkcs7.a" \
     -framework Foundation -lm > "$log" 2>&1
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    record "probe.mac" FAIL "the probe does not build on macOS (cc exited $rc)"
    log_tail "$log" 20
    return
  fi
  "$OUT/spdf_win_probe_mac" "$REPO_ROOT/$FIXTURE" 0 2.0 "$OUT/mac/probe-page.png" plain \
      > "$OUT/probe-mac.txt" 2> "$OUT/probe-mac.err"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    record "probe.mac" FAIL "the macOS probe exited $rc"
    log_tail "$OUT/probe-mac.err"
    return
  fi
  record "probe.mac" PASS "reference transcript and PNG written from $MAC_MUPDF"
}

case_probe_win() {
  if [[ -n "$GUEST_MUPDF" ]]; then
    record "probe.win" BLOCKED "$GUEST_MUPDF"
    return
  fi
  local log="$OUT/probe-win-build.log"
  vm_build "$log" spdf_win_probe \
      portable/win/spdf_win_probe.c portable/core/shenzhen_pdf_core.c portable/core/spdf_recolor.c
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    record "probe.win" FAIL "the probe does not build in the guest (vm-build exited $rc)"
    log_tail "$log" 20
    return
  fi
  guest "$OUT/probe-win.raw" "$GUEST_OUT"'\spdf_win_probe.exe "'"$GUEST_TREE"'\'"${FIXTURE//\//\\}"'" 0 2.0 "'"$GUEST_OUT"'\probe-page.png" plain'
  rc=$?
  if [[ $rc -ne 0 ]]; then
    record "probe.win" FAIL "the Windows probe exited $rc"
    log_tail "$OUT/probe-win.raw"
    return
  fi
  mkdir -p "$OUT/win"
  tr -d '\r' < "$OUT/probe-win.raw" > "$OUT/probe-win.txt"
  guest "$OUT/probe-fetch.log" 'copy /Y "'"$GUEST_OUT"'\probe-page.png" "'"$GUEST_DROP"'\probe-page.png"'
  rc=$?
  if [[ $rc -ne 0 ]]; then
    record "probe.win" FAIL "could not copy the rendered PNG back to the share (copy exited $rc)"
    log_tail "$OUT/probe-fetch.log"
    return
  fi
  cp "$STAGE/portable/win/build/t4/probe-page.png" "$OUT/win/probe-page.png"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    record "probe.win" FAIL "the guest reported the PNG copied but it is not readable on the Mac"
    return
  fi
  record "probe.win" PASS "transcript and PNG produced in the guest"
}

case_probe_diff() {
  if [[ ! -s "$OUT/probe-mac.txt" || ! -s "$OUT/probe-win.txt" ]]; then
    record "probe.diff" BLOCKED "needs both probe.mac and probe.win to have produced a transcript"
    return
  fi
  diff -u "$OUT/probe-mac.txt" "$OUT/probe-win.txt" > "$OUT/probe-diff.txt" 2>&1
  local rc=$?
  if [[ $rc -eq 0 ]]; then
    record "probe.diff" PASS "the core produces an identical transcript on macOS/clang and Windows/MSVC"
  else
    record "probe.diff" FAIL "the macOS and Windows core transcripts differ"
    log_tail "$OUT/probe-diff.txt" 30
  fi
}

case_probe_png() {
  if [[ ! -f "$OUT/mac/probe-page.png" || ! -f "$OUT/win/probe-page.png" ]]; then
    record "probe.png" BLOCKED "needs a rendered PNG from both hosts"
    return
  fi
  python3 "$TESTS_DIR/compare_png.py" "$OUT/mac/probe-page.png" "$OUT/win/probe-page.png" \
      --json "$OUT/probe-png.json" > "$OUT/probe-png.txt" 2>&1
  local rc=$?
  if [[ $rc -eq 0 ]]; then
    record "probe.png" PASS "the Windows render matches the macOS render within tolerance"
  else
    record "probe.png" FAIL "golden-image comparison failed (compare_png exited $rc)"
    log_tail "$OUT/probe-png.txt" 20
  fi
}

# Core suites that already exist and are pure C over portable/core. Free Windows
# conformance the moment the guest can compile them. `-` means no MuPDF needed.
CORE_SUITES=(
  "SPDFCoreRecolorTests:-:portable/core/spdf_recolor.c"
)

case_core_suites() {
  local entry name need srcs log rc
  for entry in "${CORE_SUITES[@]}"; do
    name="${entry%%:*}"
    need="$(echo "$entry" | cut -d: -f2)"
    srcs="$(echo "$entry" | cut -d: -f3-)"
    selected "core.$name" || continue
    if [[ -n "$GUEST_READY" ]]; then
      record "core.$name" BLOCKED "$GUEST_READY"
      continue
    fi
    if [[ "$need" == "mupdf" && -n "$GUEST_MUPDF" ]]; then
      record "core.$name" BLOCKED "$GUEST_MUPDF"
      continue
    fi
    log="$OUT/core-$name.log"
    # srcs is a deliberate space-separated list
    # shellcheck disable=SC2086
    vm_build "$log" "$name" "portable/core/tests/$name.c" $srcs
    rc=$?
    if [[ $rc -ne 0 ]]; then
      record "core.$name" FAIL "does not build in the guest (vm-build exited $rc)"
      log_tail "$log" 20
      continue
    fi
    guest "$OUT/core-$name.run.log" "$GUEST_OUT"'\'"$name"'.exe'
    rc=$?
    if [[ $rc -eq 0 ]]; then
      record "core.$name" PASS "passes in the guest"
    else
      record "core.$name" FAIL "exited $rc in the guest"
      log_tail "$OUT/core-$name.run.log" 20
    fi
  done
}

# Auto-discovered per-track tests. See the ADDING A TEST note in the header.
case_win_tests() {
  local f stem extra args need log rc guest_args
  for f in "$TESTS_DIR"/*_test.c; do
    [[ -e "$f" ]] || continue
    stem="$(basename "$f" .c)"
    selected "win.$stem" || continue
    extra="$(declared spdf-test-sources "$f")"
    args="$(declared spdf-test-args "$f")"
    need="$(declared spdf-test-needs "$f")"
    if [[ -n "$GUEST_READY" ]]; then
      record "win.$stem" BLOCKED "$GUEST_READY"
      continue
    fi
    if [[ "$need" == *mupdf* && -n "$GUEST_MUPDF" ]]; then
      record "win.$stem" BLOCKED "$GUEST_MUPDF"
      continue
    fi
    log="$OUT/win-$stem.log"
    # extra is a deliberate space-separated list
    # shellcheck disable=SC2086
    vm_build "$log" "$stem" "portable/win/tests/$(basename "$f")" $extra
    rc=$?
    if [[ $rc -ne 0 ]]; then
      record "win.$stem" FAIL "does not build in the guest (vm-build exited $rc); if it needs extra translation units, declare them with /* spdf-test-sources: ... */"
      log_tail "$log" 20
      continue
    fi
    guest_args=""
    for a in $args; do
      if [[ -f "$REPO_ROOT/$a" ]]; then
        guest_args="$guest_args \"$GUEST_TREE\\${a//\//\\}\""
      else
        guest_args="$guest_args $a"
      fi
    done
    guest "$OUT/win-$stem.run.log" "$GUEST_OUT"'\'"$stem"'.exe'"$guest_args"
    rc=$?
    if [[ $rc -eq 0 ]]; then
      record "win.$stem" PASS "passes in the guest"
    else
      record "win.$stem" FAIL "exited $rc in the guest"
      log_tail "$OUT/win-$stem.run.log" 20
    fi
  done
}

# --- drive -----------------------------------------------------------------

if [[ $LIST -eq 1 ]]; then
  printf '%s\n' selftest.compare-png harness.exit-code probe.mac probe.win \
      probe.diff probe.png 'core.<suite>' 'win.<name>_test'
  exit 0
fi

if [[ $SELF_CHECK -eq 1 ]]; then
  echo "== run-tests self-check: a failing case must produce a non-zero exit =="
  SPDF_FORCE_FAIL=1 "${BASH_SOURCE[0]}" --filter harness.forced-failure --quiet > "$OUT/self-check.log" 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    echo "SELF-CHECK FAILED: the runner exited 0 with a failing case. Do not trust any result from it." >&2
    exit 1
  fi
  echo "   ok: injected failure produced exit $rc"
  echo
fi

[[ "$WAIT_SECS" -gt 0 ]] && wait_for_toolchain
probe_guest

say "run-tests: repo $REPO_ROOT"
say "run-tests: vm '$VM_NAME', stage $STAGE, results $OUT"
[[ -n "$GUEST_READY" ]] && say "run-tests: GUEST UNAVAILABLE -- $GUEST_READY"
[[ -z "$GUEST_READY" && -n "$GUEST_MUPDF" ]] && say "run-tests: no guest MuPDF -- $GUEST_MUPDF"
say

selected selftest.compare-png && case_compare_png_selftest
selected harness.exit-code && case_exit_code
selected harness.forced-failure && case_forced_failure
selected probe.mac && case_probe_mac
selected probe.win && case_probe_win
selected probe.diff && case_probe_diff
selected probe.png && case_probe_png
case_core_suites
case_win_tests

if [[ ${#names[@]} -eq 0 ]]; then
  # A filter that matches nothing must never look like a clean run.
  echo "run-tests: NOTHING RAN (filter '$FILTER') -- refusing to report success"
  exit 3
fi

fails=0
blocked=0
echo "== results =="
for i in "${!names[@]}"; do
  printf '  %-8s %-28s %s\n' "${states[$i]}" "${names[$i]}" "${notes[$i]}"
  case "${states[$i]}" in
    FAIL) fails=$((fails + 1)) ;;
    BLOCKED) blocked=$((blocked + 1)) ;;
  esac
done

echo
echo "run-tests: ${#names[@]} cases, $fails failed, $blocked blocked"
[[ $KEEP -eq 1 ]] || rm -f "$OUT"/exit*.log "$OUT"/guest-probe.log
if [[ $fails -gt 0 ]]; then
  echo "run-tests: FAILED"
  exit 1
fi
if [[ $blocked -gt 0 ]]; then
  echo "run-tests: BLOCKED -- $blocked case(s) could not run. This is NOT a pass."
  exit 2
fi
echo "run-tests: OK"
exit 0
