#!/usr/bin/env bash
# The launch budget: does the window still come up, and the first page still
# paint, inside a time a person would call instant?
#
# WHAT IT ASSERTS. portable/win/measure-launch.ps1 launches the freshly built
# ShenzhenPDF.exe on outline.pdf several times and takes medians of two numbers,
# both measured from the process's kernel creation time:
#
#   window visible   -- the host sees a visible top-level window (external);
#   first page       -- the app's own `first-compose-end` mark, i.e. the first
#                       EndDraw of the first WM_PAINT returned (in-process,
#                       spdf_win_launch_profile.h). When the exe carries no
#                       markers the sampler's first non-blank client frame
#                       stands in.
#
# THE BUDGETS ARE GENEROUS ON PURPOSE. This is a regression tripwire, not the
# target: the target (window < 100 ms, first page < 150 ms warm) and the
# measured state live in portable/docs/windows-launch-performance.md. Other
# tracks build on this machine while the suite runs and a median of five
# absorbs a few slow runs, but a budget tight enough to be the goal would fail
# on every busy afternoon and be ignored by the evening. Tighten them with a
# measurement, in the doc, never here first.
#
# BLOCKED, NOT FAILED, when the workstation is locked: the desktop is not
# composited then and the numbers describe nothing a person sees. The harness
# exits 68 for that; it is mapped to BLOCKED, so the suite exits 2, as it does
# for every other host-blocked case.
#
# The user's live session.yaml is backed up and restored by the harness around
# every launch; see its SESSION SAFETY note.
#
# Sourced by run-tests-native.sh, never executed. Needs harness-lib.sh and
# run-tests-native.lib.sh.

LAUNCH_NATIVE_CASES=(launch.budget launch.invariant)
LAUNCH_WINDOW_BUDGET_MS=300
LAUNCH_FIRST_PAGE_BUDGET_MS=600
LAUNCH_RUNS=5

# THE LAUNCH INVARIANT (portable/win/launch-invariant.ps1): after a launch,
# every window of the app is enabled, not hung and reachable -- its tab strip
# inside a work area it overlaps by 80 x 80 -- and the window the session left
# focused is the topmost of the app's windows. Four launches that broke it, each
# from a session.yaml written into a private --state-dir on the live display
# geometry: a late --behind sibling that came up OVER the focused window at its
# exact frame (z-index 0, the keyboard underneath it); a saved frame with a
# 60 x 28 corner on screen; one with its title bar 1100 px above the display;
# one on a display that is not attached. windows-native-observations.md,
# section 13, has the measurements. BLOCKED (68) on a locked workstation, as
# launch.budget is: a z-order and a work area describe a desktop somebody sees.
case_launch_invariant() {
  local case_name="launch.invariant"
  if [[ -n "$MUPDF_READY" ]]; then
    record "$case_name" BLOCKED "$MUPDF_READY"
    return
  fi
  if ! command -v powershell.exe > /dev/null 2>&1; then
    record "$case_name" BLOCKED "powershell.exe is not on PATH (launch-invariant.ps1 drives the launches)"
    return
  fi
  local fixture="$REPO_ROOT/portable/win/tests/fixtures/golden.pdf"
  local fixture2="$REPO_ROOT/portable/win/tests/fixtures/outline.pdf"
  if [[ ! -f "$fixture" || ! -f "$fixture2" ]]; then
    record "$case_name" BLOCKED "fixtures golden.pdf / outline.pdf are missing under portable/win/tests/fixtures"
    return
  fi
  native_app_build
  if [[ $? -ne 0 ]]; then
    record "$case_name" FAIL "ShenzhenPDF.exe does not build (see $OUT/app-build.log)"
    return
  fi
  local log="$OUT/launch-invariant.log"
  local out_dir="$SCRATCH/launch-invariant"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$REPO_ROOT/portable/win/launch-invariant.ps1")" \
      -Exe "$SPDF_OUT\\ShenzhenPDF.exe" -Pdf "$(cygpath -w "$fixture")" -Pdf2 "$(cygpath -w "$fixture2")" \
      -OutDir "$(cygpath -w "$out_dir")" > "$log" 2>&1
  local rc=$?
  case $rc in
    0)
      record "$case_name" PASS "behind, sliver, strip, gone: every window enabled, unhung, reachable; the focused window on top"
      ;;
    1)
      record "$case_name" FAIL "the launch invariant does not hold: $(grep -m 3 'FAIL' "$log" | tr '\n' ';')"
      log_tail "$log" 30
      ;;
    68)
      record "$case_name" BLOCKED "the workstation is locked; unlock and re-run (see $log)"
      ;;
    65)
      record "$case_name" FAIL "a launch produced no window (launch-invariant.ps1 exited 65)"
      log_tail "$log" 20
      ;;
    *)
      record "$case_name" FAIL "launch-invariant.ps1 exited $rc"
      log_tail "$log" 20
      ;;
  esac
}

case_launch_budget() {
  local case_name="launch.budget"
  if [[ -n "$MUPDF_READY" ]]; then
    record "$case_name" BLOCKED "$MUPDF_READY"
    return
  fi
  if ! command -v powershell.exe > /dev/null 2>&1; then
    record "$case_name" BLOCKED "powershell.exe is not on PATH (measure-launch.ps1 drives the launch)"
    return
  fi
  local fixture="$REPO_ROOT/portable/win/tests/fixtures/outline.pdf"
  if [[ ! -f "$fixture" ]]; then
    record "$case_name" BLOCKED "fixture portable/win/tests/fixtures/outline.pdf is missing (regenerate: make_outline_fixture.py)"
    return
  fi
  native_app_build
  if [[ $? -ne 0 ]]; then
    record "$case_name" FAIL "ShenzhenPDF.exe does not build (see $OUT/app-build.log)"
    return
  fi
  local log="$OUT/launch-budget.log"
  local out_dir="$SCRATCH/launch-budget"
  # Nothing between powershell's exit status and $?: the harness's exit code is
  # the whole verdict (0 within budget, 1 over, 68 blocked, other = broken).
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$REPO_ROOT/portable/win/measure-launch.ps1")" \
      -Exe "$SPDF_OUT\\ShenzhenPDF.exe" -Pdf "$(cygpath -w "$fixture")" -Runs "$LAUNCH_RUNS" \
      -OutDir "$(cygpath -w "$out_dir")" -Label launch.budget \
      -WindowBudgetMs "$LAUNCH_WINDOW_BUDGET_MS" -FirstPageBudgetMs "$LAUNCH_FIRST_PAGE_BUDGET_MS" > "$log" 2>&1
  local rc=$?
  case $rc in
    0)
      record "$case_name" PASS "median launch: window < ${LAUNCH_WINDOW_BUDGET_MS} ms, first page < ${LAUNCH_FIRST_PAGE_BUDGET_MS} ms over $LAUNCH_RUNS runs ($(launch_summary_line "$log"))"
      ;;
    1)
      record "$case_name" FAIL "launch is over budget: $(launch_summary_line "$log")"
      log_tail "$log" 30
      ;;
    68)
      record "$case_name" BLOCKED "the workstation is locked or the desktop is not composited; unlock and re-run (see $log)"
      ;;
    65|66)
      record "$case_name" FAIL "no window appeared (measure-launch.ps1 exited $rc)"
      log_tail "$log" 20
      ;;
    *)
      record "$case_name" FAIL "measure-launch.ps1 exited $rc"
      log_tail "$log" 20
      ;;
  esac
}

# The two medians from the harness's table, on one line, for the record.
launch_summary_line() {
  local w p
  w="$(sed -n 's/^  window visible  *\([0-9.]*\).*/\1/p' "$1" | sed -n 1p)"
  p="$(sed -n 's/^  first-compose-end  *\([0-9.]*\).*/\1/p' "$1" | sed -n 1p)"
  [[ -n "$p" ]] || p="$(sed -n 's/^  first client pixels (sampler)  *\([0-9.]*\).*/\1/p' "$1" | sed -n 1p)"
  echo "window ${w:-?} ms, first page ${p:-?} ms"
}
