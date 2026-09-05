/* placement_test.c — the window-placement rules in
 * portable/win/src/spdf_win_placement.h, pinned without a display to plug in.
 *
 * The Windows transcription of the mac's SPDFMacWindowChromeTests cases for
 * spdf_window_frame_is_usable_on_screens and the fallback (96b7e8b7a), on the
 * geometry the defect was found on: a built-in display and an external one
 * mounted above it, so the external frame's y is negative in Windows'
 * virtual-screen coordinates the way it was above the main screen on the mac.
 * Three claims:
 *
 *   1. A frame on an ATTACHED display is usable, whether by identity (the
 *      display's name and rectangle match) or by overlap (a mac-written frame
 *      with no display), and a sliver -- under 80 x 80 inside any work area --
 *      is not.
 *   2. A frame on a MISSING display is not usable, even when its display name
 *      is remembered, and even when a display of the same name is attached
 *      somewhere else (the desktop was rearranged: the overlap rule decides).
 *   3. The fallback is CENTRED in the main display's work area, no bigger than
 *      it, and never the corner a clamp would have produced.
 *
 * Header-only under test -- every rule is inline -- so no `spdf-test-sources`
 * line is needed. Exit code is the whole signal: 0 pass, 1 fail.
 */
#include "../src/spdf_win_placement.h"

#include <stdio.h>
#include <string.h>

static int g_failures = 0;
static int g_checks = 0;

#define CHECK(cond)                                                                                                    \
    do {                                                                                                               \
        ++g_checks;                                                                                                    \
        if (!(cond)) {                                                                                                 \
            fprintf(stderr, "FAIL %s (%s:%d)\n", #cond, __FILE__, __LINE__);                                           \
            ++g_failures;                                                                                              \
        }                                                                                                              \
    } while (0)

static spdf_win_rect rect(int x, int y, int w, int h) {
    spdf_win_rect r;
    r.x = x;
    r.y = y;
    r.w = w;
    r.h = h;
    return r;
}

static spdf_win_display display(const char* name, spdf_win_rect monitor, int taskbar_h) {
    spdf_win_display d;
    memset(&d, 0, sizeof(d));
    snprintf(d.name, sizeof(d.name), "%s", name);
    d.monitor = monitor;
    d.work = rect(monitor.x, monitor.y, monitor.w, monitor.h - taskbar_h);
    return d;
}

static spdf_win_placement placement(spdf_win_rect frame, const char* name, spdf_win_rect display_rect) {
    spdf_win_placement p;
    memset(&p, 0, sizeof(p));
    p.frame = frame;
    if (name) snprintf(p.display, sizeof(p.display), "%s", name);
    p.display_rect = display_rect;
    return p;
}

/* The real geometry: a 1800 x 1169 built-in at the origin with a 48 px
 * taskbar, and a 3440 x 1440 external mounted above it, so it sits at y -1440. */
static const spdf_win_rect kBuiltIn = {0, 0, 1800, 1169};
static const spdf_win_rect kExternal = {-820, -1440, 3440, 1440};

int main(void) {
    spdf_win_display both[2];
    spdf_win_display builtin_only[1];
    spdf_win_display rearranged[2];
    spdf_win_placement p;
    spdf_win_rect fallback;
    int w, h;

    both[0] = display("\\\\.\\DISPLAY1", kBuiltIn, 48);
    both[1] = display("\\\\.\\DISPLAY2", kExternal, 0);
    builtin_only[0] = both[0];
    /* The same two displays, the external now to the RIGHT of the built-in. */
    rearranged[0] = both[0];
    rearranged[1] = display("\\\\.\\DISPLAY2", rect(1800, 0, 3440, 1440), 0);

    /* --- overlap: the mac's own rule ------------------------------------- */
    spdf_win_rect_overlap(rect(0, 0, 100, 100), rect(50, 50, 100, 100), &w, &h);
    CHECK(w == 50 && h == 50);
    spdf_win_rect_overlap(rect(0, 0, 100, 100), rect(100, 0, 100, 100), &w, &h);
    CHECK(w == 0 && h == 100); /* touching edges do not overlap */
    spdf_win_rect_overlap(rect(0, 0, 100, 100), rect(500, 500, 10, 10), &w, &h);
    CHECK(w == 0 && h == 0);

    /* 1. A frame on the external display, as measured: usable while attached... */
    p = placement(rect(220, -1319, 1300, 900), "\\\\.\\DISPLAY2", kExternal);
    CHECK(spdf_win_placement_display_attached(&p, both, 2));
    CHECK(spdf_win_placement_is_usable(&p, both, 2));
    /* ...a mac-written frame with no display too, by overlap alone... */
    p = placement(rect(220, -1319, 1300, 900), NULL, rect(0, 0, 0, 0));
    CHECK(!spdf_win_placement_display_attached(&p, both, 2));
    CHECK(spdf_win_placement_is_usable(&p, both, 2));
    /* ...and a frame on the built-in display is usable with either set. */
    p = placement(rect(100, 120, 1120, 800), "\\\\.\\DISPLAY1", kBuiltIn);
    CHECK(spdf_win_placement_is_usable(&p, both, 2));
    CHECK(spdf_win_placement_is_usable(&p, builtin_only, 1));
    /* A sliver is not on screen: 79 px of a window poking in from the right
     * edge of the built-in display, with no display of its own to vouch for it. */
    p = placement(rect(1800 - 79, 200, 1300, 900), NULL, rect(0, 0, 0, 0));
    CHECK(!spdf_win_placement_is_usable(&p, both, 2));
    /* Exactly 80 x 80 is the threshold, inclusive, as kSPDFMinimumVisibleArea. */
    p = placement(rect(1800 - 80, 200, 1300, 900), NULL, rect(0, 0, 0, 0));
    CHECK(spdf_win_placement_is_usable(&p, both, 2));
    /* The taskbar is not work area: a frame entirely under it is not visible. */
    p = placement(rect(100, 1169 - 48, 1300, 900), NULL, rect(0, 0, 0, 0));
    CHECK(!spdf_win_placement_is_usable(&p, builtin_only, 1));
    /* No frame is never usable. */
    p = placement(rect(0, 0, 0, 0), "\\\\.\\DISPLAY1", kBuiltIn);
    CHECK(!spdf_win_placement_is_usable(&p, both, 2));
    CHECK(!spdf_win_placement_is_usable(NULL, both, 2));

    /* 2. The external display is asleep or unplugged: the frame it held is not
     * usable, remembered name or not. THIS is the case that used to clamp the
     * frame onto the built-in display and save the clamp. */
    p = placement(rect(220, -1319, 1300, 900), "\\\\.\\DISPLAY2", kExternal);
    CHECK(!spdf_win_placement_display_attached(&p, builtin_only, 1));
    CHECK(!spdf_win_placement_is_usable(&p, builtin_only, 1));
    p = placement(rect(220, -1319, 1300, 900), NULL, rect(0, 0, 0, 0));
    CHECK(!spdf_win_placement_is_usable(&p, builtin_only, 1));
    /* The display is attached under its name but somewhere else: the identity
     * does not hold, and a frame at the old position is above every display. */
    p = placement(rect(220, -1319, 1300, 900), "\\\\.\\DISPLAY2", kExternal);
    CHECK(!spdf_win_placement_display_attached(&p, rearranged, 2));
    CHECK(!spdf_win_placement_is_usable(&p, rearranged, 2));
    /* ...while a frame that happens to land on the moved display is usable by
     * overlap, which is what lets a replugged display that came back under a
     * new name still show the window. */
    p = placement(rect(2000, 100, 1300, 900), "\\\\.\\DISPLAY3", rect(1800, 0, 3440, 1440));
    CHECK(!spdf_win_placement_display_attached(&p, rearranged, 2));
    CHECK(spdf_win_placement_is_usable(&p, rearranged, 2));
    /* The identity is exact: the same name at the same rectangle, and only that. */
    p = placement(rect(220, -1319, 1300, 900), "\\\\.\\DISPLAY2", rect(-820, -1440, 3440, 1439));
    CHECK(!spdf_win_placement_display_attached(&p, both, 2));
    p = placement(rect(220, -1319, 1300, 900), "\\\\.\\display2", kExternal);
    CHECK(!spdf_win_placement_display_attached(&p, both, 2)); /* names compare as Windows spells them */

    /* 3. The fallback: centred in the main display's work area. The mac
     * measured the clamp at exactly the built-in screen's visible frame
     * (0, 65); centred is the visible difference between "parked" and "moved". */
    fallback = spdf_win_placement_fallback(rect(220, -1319, 1300, 900), builtin_only[0].work);
    CHECK(fallback.w == 1300 && fallback.h == 900);
    CHECK(fallback.x == (1800 - 1300) / 2);
    CHECK(fallback.y == (1121 - 900) / 2);
    CHECK(!(fallback.x == 0 && fallback.y == 0));
    /* No bigger than the work area: a 3440-wide window parks at the width of
     * the display it is parked on, from its left edge. */
    fallback = spdf_win_placement_fallback(rect(-820, -1440, 3440, 1400), builtin_only[0].work);
    CHECK(fallback.w == 1800 && fallback.h == 1121);
    CHECK(fallback.x == 0 && fallback.y == 0);
    /* A work area that does not start at the origin (a taskbar on the left,
     * or a main display that is not at 0,0) centres inside ITS rectangle. */
    fallback = spdf_win_placement_fallback(rect(0, 0, 800, 600), rect(60, 0, 1740, 1169));
    CHECK(fallback.x == 60 + (1740 - 800) / 2 && fallback.y == (1169 - 600) / 2);
    /* The fallback of a frame that is already where it would be parked is the
     * frame itself, which is how restore tells "parked" from "as saved". */
    fallback = spdf_win_placement_fallback(rect(250, 110, 1300, 900), builtin_only[0].work);
    CHECK(spdf_win_rect_equal(fallback, rect(250, 110, 1300, 900)));

    printf("placement_test: %d checks, %d failures\n", g_checks, g_failures);
    return g_failures ? 1 : 0;
}
