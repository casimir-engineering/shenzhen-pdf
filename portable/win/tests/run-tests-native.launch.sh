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

LAUNCH_NATIVE_CASES=(launch.budget launch.health)
LAUNCH_WINDOW_BUDGET_MS=300
LAUNCH_FIRST_PAGE_BUDGET_MS=600
LAUNCH_RUNS=5

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

# --- launch.health ---------------------------------------------------------
#
# DOES THE WINDOW ANSWER? launch.budget proves a window appeared and painted;
# it cannot prove the window reacts to anything, because it never touches it.
# That gap is exactly where the report of 2026-09-05 lived -- "the app was
# never responsive to any user input and not even focusable" with every test
# green -- so this case sends REAL input and then asks the app what it saw.
#
# WHAT IT ASSERTS (portable/win/tests/launch-health.ps1):
#
#   1. a click on the toolbar's next-page button, a PageDown, and Ctrl+F with a
#      query typed into it each change the window's PrintWindow capture. The
#      click coordinate comes from `ShenzhenPDF.exe --print-layout`, i.e. from
#      the same layout the painter and the input router share, so the test
#      clicks the BUTTON rather than a coordinate someone measured once;
#   2. the app's OWN launch-health.log, written into the private --state-dir
#      this case hands it, says at 1 s: foreground, enabled, visible, not
#      iconic, not hung, z-index 0, a monitor found, on screen, not modal;
#   3. its input counters and paint total have moved by the 5 s line -- the app
#      agreeing, from the inside, that the input arrived;
#   4. the watchdog recorded no `stall`, i.e. the UI thread never stopped
#      pumping for three seconds.
#
# BLOCKED, NOT FAILED, in the two states where the question cannot be asked: a
# locked workstation (nothing is composited, so no capture can differ) and a
# desktop where the app cannot be brought to the front (real input goes to
# whoever is in FRONT, and typing into somebody else's window is worse than not
# testing). Both are 68. The harness runs under a shell under an editor, which
# Windows does not grant the foreground, so the script asks for it through the
# foreground thread's input queue and reports BLOCKED when the system still
# refuses -- see launch-health.ps1's Raise().
case_launch_health() {
  local case_name="launch.health"
  if [[ -n "$MUPDF_READY" ]]; then
    record "$case_name" BLOCKED "$MUPDF_READY"
    return
  fi
  if ! command -v powershell.exe > /dev/null 2>&1; then
    record "$case_name" BLOCKED "powershell.exe is not on PATH (launch-health.ps1 drives the window)"
    return
  fi
  local fixture="$REPO_ROOT/portable/win/tests/fixtures/golden.pdf"
  if [[ ! -f "$fixture" ]]; then
    record "$case_name" BLOCKED "fixture portable/win/tests/fixtures/golden.pdf is missing"
    return
  fi
  native_app_build
  if [[ $? -ne 0 ]]; then
    record "$case_name" FAIL "ShenzhenPDF.exe does not build (see $OUT/app-build.log)"
    return
  fi
  local log="$OUT/launch-health.log"
  # A PRIVATE state directory, always: the app writes its health log, its
  # settings and its session there, and the reader's %APPDATA%\ShenzhenPDF must
  # never be what a test drives. The script refuses that path outright.
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$REPO_ROOT/portable/win/tests/launch-health.ps1")" \
      -Exe "$SPDF_OUT\\ShenzhenPDF.exe" -Pdf "$(cygpath -w "$fixture")" \
      -StateDir "$SCRATCH_WIN\\launch-health-state" -OutDir "$SCRATCH_WIN\\launch-health" > "$log" 2>&1
  local rc=$?
  case $rc in
    0)
      record "$case_name" PASS "the window answered click, PageDown and Ctrl+F, and its own log agrees ($(health_summary_line "$log"))"
      ;;
    1)
      record "$case_name" FAIL "the window did not answer, or its own launch-health.log disagrees"
      log_tail "$log" 30
      ;;
    68)
      record "$case_name" BLOCKED "the workstation is locked, or the app could not be brought to the foreground so no input could be sent (see $log)"
      ;;
    65|66)
      record "$case_name" FAIL "no window appeared (launch-health.ps1 exited $rc)"
      log_tail "$log" 20
      ;;
    *)
      record "$case_name" FAIL "launch-health.ps1 exited $rc"
      log_tail "$log" 20
      ;;
  esac
}

# The per-step repaint percentages on one line, for the record.
health_summary_line() {
  sed -n 's/^[0-9][0-9] \([a-z-]*\) .*changed=\([0-9.]*\)%.*/\1 \2%/p' "$1" | tr '\n' ' ' | sed 's/ *$//'
}
