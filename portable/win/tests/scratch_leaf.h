#pragma once

/* A SCRATCH DIRECTORY LEAF UNIQUE TO THIS PROCESS, for the suites that put a
 * whole state directory under %TEMP%.
 *
 * WHY THIS EXISTS. %TEMP% is one directory for the whole machine, and several
 * suites run at once here -- one per parallel worktree, each with its own
 * SPDF_OUT but the same %TEMP%. Three tests (session, state, settings) each
 * built a FIXED leaf under it, so two runs rewrote each other's settings.yaml
 * and session.yaml mid-assertion. That surfaced as failures which read exactly
 * like real regressions ("the session file is byte-for-byte what it was", "a
 * save refuses to run over a session it cannot read") and cost an integration
 * a rollback before the collision was understood.
 *
 * THE NON-ASCII PART STAYS. Putting every file operation through a path the
 * narrow CRT would mangle is the point of those leaves, not decoration: it is
 * how the port's UTF-8 path boundary is exercised. So the process id is
 * appended to it rather than replacing it.
 *
 * Header-only and dependency-free on purpose: it is included by tests that
 * link quite different halves of the port, and by the POSIX-side runs of the
 * portable tests, so it must not drag in anything.
 */

#include <stdio.h>

#if defined(_WIN32)
/* GetCurrentProcessId, without pulling the rest of windows.h into a test that
 * may not want it. */
__declspec(dllimport) unsigned long __stdcall GetCurrentProcessId(void);
#else
#include <unistd.h>
#endif

/* Writes "<stem>-<pid>" into `out`. `stem` carries the non-ASCII bytes; the
 * caller keeps its own buffer so this needs no allocation. */
static void spdf_test_scratch_leaf(char* out, size_t out_len, const char* stem) {
    unsigned long pid;
#if defined(_WIN32)
    pid = GetCurrentProcessId();
#else
    pid = (unsigned long)getpid();
#endif
    snprintf(out, out_len, "%s-%lu", stem, pid);
}
