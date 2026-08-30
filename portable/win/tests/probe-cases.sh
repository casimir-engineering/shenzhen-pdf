#!/usr/bin/env bash
# The cross-host probe pipeline for portable/win/tests/run-tests.sh: build
# spdf_win_probe.c on macOS, build the same source in the Windows guest, diff the
# two transcripts, and compare the two rendered PNGs.
#
# Split from run-tests.sh to keep both files under the repo's 500-line cap
# (tools/file-size-limits.md), and because these four cases are one story: they
# are the only cases that answer "does the CORE behave the same on Windows?"
# rather than "does the harness work?". Sourced, never executed.
#
# Each case degrades into the next: probe.diff and probe.png record BLOCKED
# rather than inventing a result when the transcript or PNG they need does not
# exist, so a Windows-side failure produces one honest failure instead of three
# confusing ones.

# Both producing cases delete their own outputs before they run. Without this a
# case that succeeded on a previous run and fails on this one leaves its old
# transcript and PNG behind, and probe.diff/probe.png happily compare last
# week's evidence and report a pass. Stale artifacts are the quietest way for a
# test suite to start lying.
case_probe_mac() {
  rm -f "$OUT/probe-mac.txt" "$OUT/mac/probe-page.png"
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
     "$REPO_ROOT/portable/core/spdf_win_compat.c" \
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
  rm -f "$OUT/probe-win.txt" "$OUT/probe-win.raw" "$OUT/win/probe-page.png" \
        "$STAGE/portable/win/build/t4/probe-page.png"
  if [[ -n "$GUEST_MUPDF" ]]; then
    record "probe.win" BLOCKED "$GUEST_MUPDF"
    return
  fi
  local log="$OUT/probe-win-build.log"
  vm_build "$log" spdf_win_probe \
      portable/win/spdf_win_probe.c portable/core/shenzhen_pdf_core.c portable/core/spdf_recolor.c \
      portable/core/spdf_win_compat.c
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    if mupdf_link_defect "$log"; then
      record "probe.win" BLOCKED "libmupdf.lib itself fails to link in the guest (LNK2048 in hyphen.obj) -- toolchain track"
    else
      record "probe.win" FAIL "the probe does not build in the guest (vm-build exited $rc)"
      log_tail "$log" 20
    fi
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
  # --strict first, because section 6 of the port plan says the tolerance must be
  # set from a measurement and pinned, and byte-identity is the measurement worth
  # having: portable/win/verify.sh already proves byte-identical output for pure
  # integer C across these two toolchains, and MuPDF's rasteriser is largely
  # fixed-point. If this passes, pin the defaults at zero. Its result is reported
  # either way -- it never decides the case, so a rasteriser that legitimately
  # differs in the last bit does not fail the run.
  python3 "$TESTS_DIR/compare_png.py" "$OUT/mac/probe-page.png" "$OUT/win/probe-page.png" \
      --strict --quiet > "$OUT/probe-png-strict.txt" 2>&1
  local strict_rc=$?
  local identical="not byte-identical"
  [[ $strict_rc -eq 0 ]] && identical="BYTE-IDENTICAL -- pin the tolerance at zero"

  python3 "$TESTS_DIR/compare_png.py" "$OUT/mac/probe-page.png" "$OUT/win/probe-page.png" \
      --json "$OUT/probe-png.json" > "$OUT/probe-png.txt" 2>&1
  local rc=$?
  if [[ $rc -eq 0 ]]; then
    # The measured numbers go in the note so the value to pin is in the report
    # itself, not somewhere a person has to go and look for it.
    local measured
    measured="$(python3 -c 'import json,sys
r = json.load(open(sys.argv[1]))
print("mae %.4f, max delta %d, %.4f%% over %s" % (r["mae"], r["max_channel_delta"], r["bad_pixel_pct"], "delta"))' \
        "$OUT/probe-png.json" 2>/dev/null)"
    record "probe.png" PASS "matches within tolerance: ${measured:-metrics unavailable}; $identical"
  else
    record "probe.png" FAIL "golden-image comparison failed (compare_png exited $rc)"
    log_tail "$OUT/probe-png.txt" 20
  fi
}
