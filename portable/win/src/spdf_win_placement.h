/* spdf_win_placement.h — where a restored window goes, and which frame is
 * remembered. The RULES only: no Win32, no HWND, so placement_test.c can pin
 * them with the display geometry the defect was found on and no monitor to
 * plug in.
 *
 * Ported from portable/mac/SPDFMacWindowPlacement.mm (060856589, 96b7e8b7a).
 * The defect it exists to not have, stated once: a window left on a second
 * display, launched while that display was asleep or unplugged, was CLAMPED
 * onto the main display at load time and the clamp was SAVED on quit -- one
 * launch without the display forgot the position for good. So:
 *
 *   1. The saved frame is kept RAW. Nothing clamps it on the way in.
 *   2. A frame no attached display can show is still put somewhere visible --
 *      centred on the main display, no bigger than its work area -- but that
 *      placement is a FALLBACK and display-only: what gets saved is still the
 *      frame the reader left, until the reader moves or resizes the window
 *      themselves (spdf_win_window_get_placement, spdf_win_window_frame.h).
 *   3. When the missing display reappears (WM_DISPLAYCHANGE), the remembered
 *      frame is applied then.
 *
 * WHAT IDENTIFIES A DISPLAY. The mac judges a frame by what it overlaps
 * (NSScreen.visibleFrame). Windows can do better: MONITORINFOEXW carries a
 * device name (\\.\DISPLAY2) and the monitor's rectangle in virtual-screen
 * coordinates, and the two together say "the display it was left on, where it
 * was". A frame whose display is attached at the same rectangle is applied
 * exactly, whatever it overlaps. Otherwise -- a mac-written file has no
 * display, an unplugged and replugged display can come back under another
 * name, a rearranged desktop moves the rectangle -- the overlap rule decides,
 * with the mac's own threshold: an 80 x 80 sliver is not "on screen".
 */
#ifndef SPDF_WIN_PLACEMENT_H
#define SPDF_WIN_PLACEMENT_H

#include <string.h>

#if defined(_MSC_VER) && !defined(__cplusplus)
#define SPDF_WIN_PLACEMENT_INLINE __inline
#else
#define SPDF_WIN_PLACEMENT_INLINE inline
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* CCHDEVICENAME: the size of MONITORINFOEXW::szDevice. */
#define SPDF_WIN_DISPLAY_NAME_MAX 32

/* The smallest overlap worth calling "on screen" (mac: kSPDFMinimumVisibleArea). */
#define SPDF_WIN_PLACEMENT_MIN_VISIBLE 80

typedef struct spdf_win_rect {
    int x, y, w, h;
} spdf_win_rect;

/* A window's placement for the session: the NORMAL frame -- what it occupies
 * when neither maximized nor full screen -- in virtual-screen device pixels,
 * and the display it was on. `display` is empty when unknown (a mac-written
 * session, or a build that never wrote one); `frame.w`/`h` <= 0 means none. */
typedef struct spdf_win_placement {
    spdf_win_rect frame;
    char display[SPDF_WIN_DISPLAY_NAME_MAX]; /* MONITORINFOEXW szDevice, ASCII */
    spdf_win_rect display_rect;              /* that display's rcMonitor */
} spdf_win_placement;

/* An attached display, as the window layer enumerates them. */
typedef struct spdf_win_display {
    char name[SPDF_WIN_DISPLAY_NAME_MAX];
    spdf_win_rect monitor; /* rcMonitor */
    spdf_win_rect work;    /* rcWork: minus the taskbar */
} spdf_win_display;

static SPDF_WIN_PLACEMENT_INLINE int spdf_win_rect_equal(spdf_win_rect a, spdf_win_rect b) {
    return a.x == b.x && a.y == b.y && a.w == b.w && a.h == b.h;
}

/* The intersection's width and height, each 0 when the rectangles miss. */
static SPDF_WIN_PLACEMENT_INLINE void spdf_win_rect_overlap(spdf_win_rect a, spdf_win_rect b, int* w, int* h) {
    int left = a.x > b.x ? a.x : b.x;
    int top = a.y > b.y ? a.y : b.y;
    int right = a.x + a.w < b.x + b.w ? a.x + a.w : b.x + b.w;
    int bottom = a.y + a.h < b.y + b.h ? a.y + a.h : b.y + b.h;
    *w = right > left ? right - left : 0;
    *h = bottom > top ? bottom - top : 0;
}

/* Whether `frame` is reachable on some attached display: at least an 80 x 80
 * block of it lies inside a work area. Pure, and the mac's rule exactly
 * (spdf_window_frame_is_usable_on_screens), so the two apps agree about what
 * "on screen" means. */
static SPDF_WIN_PLACEMENT_INLINE int spdf_win_frame_is_visible(spdf_win_rect frame, const spdf_win_display* displays,
                                                              int count) {
    int i, w, h;
    if (frame.w <= 0 || frame.h <= 0) return 0;
    for (i = 0; i < count; ++i) {
        spdf_win_rect_overlap(frame, displays[i].work, &w, &h);
        if (w >= SPDF_WIN_PLACEMENT_MIN_VISIBLE && h >= SPDF_WIN_PLACEMENT_MIN_VISIBLE) return 1;
    }
    return 0;
}

/* Whether the display a placement names is attached where it was. */
static SPDF_WIN_PLACEMENT_INLINE int spdf_win_placement_display_attached(const spdf_win_placement* p,
                                                                        const spdf_win_display* displays, int count) {
    int i;
    if (!p || !p->display[0]) return 0;
    for (i = 0; i < count; ++i)
        if (strcmp(displays[i].name, p->display) == 0 && spdf_win_rect_equal(displays[i].monitor, p->display_rect))
            return 1;
    return 0;
}

/* THE RULE: a saved placement is applied as it is when its display is attached
 * where it was, or when its frame is visible on some attached display. Anything
 * else is a frame the desktop cannot show, and gets the fallback below. */
static SPDF_WIN_PLACEMENT_INLINE int spdf_win_placement_is_usable(const spdf_win_placement* p,
                                                                 const spdf_win_display* displays, int count) {
    if (!p || p->frame.w <= 0 || p->frame.h <= 0) return 0;
    if (spdf_win_placement_display_attached(p, displays, count)) return 1;
    return spdf_win_frame_is_visible(p->frame, displays, count);
}

/* Where to park a window whose own display is not attached: centred in `work`
 * (the main display's work area), at no more than its size. Centred rather
 * than clamped into a corner, which is what produced a window pinned at the
 * display's exact edge -- and, saved, a position nobody chose. */
static SPDF_WIN_PLACEMENT_INLINE spdf_win_rect spdf_win_placement_fallback(spdf_win_rect desired, spdf_win_rect work) {
    spdf_win_rect r;
    r.w = desired.w < work.w ? desired.w : work.w;
    r.h = desired.h < work.h ? desired.h : work.h;
    r.x = work.x + (work.w - r.w) / 2;
    r.y = work.y + (work.h - r.h) / 2;
    return r;
}

#ifdef __cplusplus
}
#endif

#endif /* SPDF_WIN_PLACEMENT_H */
