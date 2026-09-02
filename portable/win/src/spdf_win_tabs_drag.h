/* spdf_win_tabs_drag.h — the two pieces of tab-drag geometry that decide what
 * a drag SHOWS and what it BECOMES: where the yellow drop indicator sits, and
 * when a drag has left the strip and turns into a detach.
 *
 * Split out of spdf_win_tabstrip.h for the file-size ratchet
 * (tools/file-size-limits.md). Depends on that header's functions, so it is
 * included AFTER it -- by spdf_win_chrome_actions.h, which runs the drag, and
 * by portable/win/tests/tabstrip_geometry_test.c, which pins both. Toolkit-free,
 * header-only, C and C++.
 */
#ifndef SPDF_WIN_TABS_DRAG_H
#define SPDF_WIN_TABS_DRAG_H

#include "spdf_win_tabstrip.h"

/* spdf_tab_strip_drop_indicator_center_x (SPDFMacTabStripGeometry.mm:13-22),
 * turned into the indicator's whole rect so the painter has nothing to derive:
 * SPDF_WIN_TABSTRIP_DROP_INDICATOR_WIDTH wide, the full tab height at the tab
 * y, centred in the gap between the two neighbouring visible tabs -- or half a
 * gap outside the first/last tab edge for the end slots (:19-20). An empty rect
 * for no visible tabs or a slot out of range, where the mac returns NAN and the
 * caller draws nothing. The mac's `floor(centerX) - 1.0` snap happens where the
 * mac does it, in the painter, in device pixels. */
static SPDF_WIN_TS_INLINE SpdfWinTabRect spdf_win_tabstrip_drop_indicator_rect(double strip_w, int tab_count,
                                                                              int selected, int slot) {
    int start = 0, visible = 0;
    double center;
    SpdfWinTabRect r;
    spdf_win_tabstrip_visible_range(strip_w, tab_count, selected, &start, &visible);
    if (visible <= 0 || slot < 0 || slot > visible) return spdf_win_tabstrip_zero_rect();
    if (slot == 0) {
        SpdfWinTabRect first = spdf_win_tabstrip_tab_rect(strip_w, tab_count, selected, start);
        center = first.x - SPDF_WIN_TABSTRIP_TAB_GAP / 2.0;
    } else if (slot == visible) {
        SpdfWinTabRect last = spdf_win_tabstrip_tab_rect(strip_w, tab_count, selected, start + visible - 1);
        center = last.x + last.w + SPDF_WIN_TABSTRIP_TAB_GAP / 2.0;
    } else {
        SpdfWinTabRect before = spdf_win_tabstrip_tab_rect(strip_w, tab_count, selected, start + slot - 1);
        SpdfWinTabRect after = spdf_win_tabstrip_tab_rect(strip_w, tab_count, selected, start + slot);
        center = (before.x + before.w + after.x) / 2.0;
    }
    r.x = center - SPDF_WIN_TABSTRIP_DROP_INDICATOR_WIDTH / 2.0;
    r.y = SPDF_WIN_TABSTRIP_TAB_Y;
    r.w = SPDF_WIN_TABSTRIP_DROP_INDICATOR_WIDTH;
    r.h = SPDF_WIN_TABSTRIP_TAB_HEIGHT;
    return r;
}

/* WHEN A DRAG HAS LEFT THE STRIP -- SPDFMacTabStripView.mm:1012-1014, the test
 * that turns a same-window reorder into a detach: the pointer more than 24 pt
 * above or below the strip, more than 18 pt left of the leading inset or right
 * of the `+`, or more than 48 pt from where the drag began vertically. Strip
 * points in, like every other test in this header. */
#define SPDF_WIN_TABSTRIP_DETACH_SLOP_Y 24.0
#define SPDF_WIN_TABSTRIP_DETACH_SLOP_X 18.0
#define SPDF_WIN_TABSTRIP_DETACH_DY 48.0

static SPDF_WIN_TS_INLINE int spdf_win_tabstrip_drag_detaches(double strip_w, double strip_h, double x, double y,
                                                              double start_y) {
    SpdfWinTabRect plus = spdf_win_tabstrip_plus_rect(strip_w);
    int outside = y < -SPDF_WIN_TABSTRIP_DETACH_SLOP_Y || y > strip_h + SPDF_WIN_TABSTRIP_DETACH_SLOP_Y ||
                  x < SPDF_WIN_TABSTRIP_LEADING_INSET - SPDF_WIN_TABSTRIP_DETACH_SLOP_X ||
                  x > plus.x + plus.w + SPDF_WIN_TABSTRIP_DETACH_SLOP_X;
    return outside || fabs(y - start_y) > SPDF_WIN_TABSTRIP_DETACH_DY;
}


#endif /* SPDF_WIN_TABS_DRAG_H */
