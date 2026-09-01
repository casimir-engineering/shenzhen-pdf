/* spdf_win_chrome.h — how the client area is divided, for the Win32 frontend.
 *
 * WHAT THIS IS: the arithmetic that turns one client rect into the bands and
 * panels the macOS window is made of, plus the model the painters read. Pure,
 * toolkit-free, header-only, no state, no allocation — the same shape as
 * spdf_win_layout.h and spdf_win_tabstrip.h, and testable the same way
 * (portable/win/tests/chrome_geometry_test.c).
 *
 * THE macOS WINDOW, top to bottom (ShenzhenPDFMac.mm:3292-3312):
 *
 *     +--------------------------------------------------+
 *     | tab strip                                  42 pt |
 *     +--------------------------------------------------+
 *     | toolbar                                    42 pt |
 *     +--------------------------------------------------+
 *     | sidebar  | |            canvas            | | mm |
 *     |  240 pt  |5|                              |5|126.5
 *     +--------------------------------------------------+
 *
 * The middle row is an NSSplitView (vertical, thin divider) filling the rest.
 * BOTH side panels are visible by default -- `_defaultSidebarVisibleForNewDocuments
 * = YES` (:836-838) and the minimap likewise (:837-840) -- which is worth stating
 * because a Windows reader coming from SumatraPDF will assume otherwise, and
 * because "looks like the Mac app" means both panels showing on first launch.
 *
 * WHY THE GEOMETRY IS SEPARATE FROM THE PAINTING. Two reasons, both learned in
 * this port rather than assumed:
 *
 *   1. spdf_win_paint() must never require an HWND (spdf_win_d2d.h). That rule
 *      is what let Phase 1 be verified at all -- the live window's client area
 *      was measured byte-identical to the offscreen compose path. Chrome that
 *      computes its own rects from an HWND would put itself outside every pixel
 *      test in the repo. Chrome laid out by this header stays inside them.
 *   2. Hit-testing and painting must agree exactly. On macOS they do because
 *      AppKit owns both; here they agree only if they call the same functions.
 *      Every rect below is consumed by the painter AND by the input router.
 *
 * UNITS. Points in, device pixels out. Every function takes a `dpi_scale` and
 * returns device-pixel rects, because chrome is screen furniture: a 42 pt strip
 * must be 63 px at 150%. This is deliberately unlike SPDF_WIN_PAGE_MARGIN_H/V in
 * spdf_win_layout.h, which are content-space and NOT DPI-scaled -- page margins
 * live in document coordinates. Keeping the two in different spaces is
 * intentional; do not unify them.
 *
 * Rects are LEFT/TOP/WIDTH/HEIGHT in the client area's own coordinates, origin
 * top-left, y increasing downward -- Win32's convention and D2D's, not
 * AppKit's. So "the tab strip is at the top" reads y = 0 here and y = maxY on
 * macOS; the numbers are the same, the axis is flipped.
 */
#ifndef SPDF_WIN_CHROME_H
#define SPDF_WIN_CHROME_H

#include <math.h>

#if defined(_MSC_VER) && !defined(__cplusplus)
#define SPDF_WIN_CHROME_INLINE __inline
#else
#define SPDF_WIN_CHROME_INLINE inline
#endif

/* --- metrics, all cited to portable/mac/ShenzhenPDFMac.mm ---------------- */

#define SPDF_WIN_CHROME_TABSTRIP_H 42.0 /* :68  kTabStripHeight */
#define SPDF_WIN_CHROME_TOOLBAR_H 42.0  /* :3293 toolbar height pin */

/* :72-76. kSearchSidebarMinWidth 216.0 applies while the Search section is
 * showing; the caller raises the minimum then rather than this header guessing
 * which section is live. */
#define SPDF_WIN_CHROME_SIDEBAR_W 240.0
#define SPDF_WIN_CHROME_SIDEBAR_MIN_W 176.0
#define SPDF_WIN_CHROME_SIDEBAR_MAX_W 320.0
#define SPDF_WIN_CHROME_SIDEBAR_SEARCH_MIN_W 216.0
/* :72-76 again: never more than this fraction of the split view. */
#define SPDF_WIN_CHROME_SIDEBAR_MAX_FRACTION 0.34

/* :71, persisted as settings["minimapWidth"], clamped [72, 260] on read
 * (:1455) and [72, MAX(120, MIN(320, containerWidth * 0.35))] on drag
 * (:9535-9537). The odd default is macOS's, not a typo. */
#define SPDF_WIN_CHROME_MINIMAP_W 126.5
#define SPDF_WIN_CHROME_MINIMAP_MIN_W 72.0
#define SPDF_WIN_CHROME_MINIMAP_MAX_W 260.0
#define SPDF_WIN_CHROME_MINIMAP_DRAG_MAX_FRACTION 0.35

/* :77-78. Drawn as windowBackgroundColor with a 1 pt separator line down its
 * centre and a resizeLeftRight cursor (SPDFMacUIHelpers.mm:425-431). */
#define SPDF_WIN_CHROME_DIVIDER_W 5.0

/* Window sizing (:2912-2938, :69-70). Windows currently applies NO minimum at
 * all and derives its initial size from page 0, so golden.pdf opens a 244x286
 * window -- narrower than its own caption buttons. These are the macOS numbers
 * to adopt. */
#define SPDF_WIN_CHROME_DEFAULT_CONTENT_W 1120.0
#define SPDF_WIN_CHROME_DEFAULT_CONTENT_H 800.0
#define SPDF_WIN_CHROME_MIN_CONTENT_W 560.0
#define SPDF_WIN_CHROME_MIN_CONTENT_H 380.0

typedef struct SpdfWinChromeRect {
    float x, y, w, h;
} SpdfWinChromeRect;

/* Which chrome element a point lands in. The order of the divider cases
 * matters to the caller: a divider's grab area overlaps its neighbours'
 * edges, so dividers are tested first (see spdf_win_chrome_hit). */
typedef enum spdf_win_chrome_part {
    SPDF_WIN_CHROME_NONE = 0,
    SPDF_WIN_CHROME_TABSTRIP,
    SPDF_WIN_CHROME_TOOLBAR,
    SPDF_WIN_CHROME_SIDEBAR,
    SPDF_WIN_CHROME_SIDEBAR_DIVIDER,
    SPDF_WIN_CHROME_CANVAS,
    SPDF_WIN_CHROME_MINIMAP_DIVIDER,
    SPDF_WIN_CHROME_MINIMAP
} spdf_win_chrome_part;

/* The full division of one client area. Empty rects (w or h <= 0) mean the
 * element is not present -- hidden by the user, or squeezed out by a window too
 * small to hold it. Every consumer must treat w <= 0 as absent rather than
 * assuming the element is always there; a 560 pt minimum window still has to
 * survive a user dragging the sidebar to its maximum. */
typedef struct SpdfWinChromeLayout {
    SpdfWinChromeRect tabstrip;
    SpdfWinChromeRect toolbar;
    SpdfWinChromeRect sidebar;
    SpdfWinChromeRect sidebar_divider;
    SpdfWinChromeRect canvas;
    SpdfWinChromeRect minimap_divider;
    SpdfWinChromeRect minimap;
    float dpi_scale;
} SpdfWinChromeLayout;

/* One tab, as the strip needs to see it. Borrowed UTF-16 title; the tab model
 * in spdf_win_tabs.h owns the storage. `missing` and `read_only` exist because
 * macOS colours a tab red for a missing file and shows an orange dot for a
 * read-only source (SPDFMacTabStripView.mm:552-555, :585). */
typedef struct SpdfWinChromeTab {
    const wchar_t* title;
    int read_only;
    int missing;
} SpdfWinChromeTab;

/* What the painters need to know that geometry does not carry. Deliberately a
 * plain value type with no pointers into app state beyond the strings it
 * borrows, so a headless test can build one by hand -- which is how the chrome
 * gets pixel-tested without a window. */
typedef struct SpdfWinChromeModel {
    /* Tab strip contents. `count` also drives the strip's GEOMETRY (tab width,
     * overflow, the visible window), which is why it lives in the model rather
     * than in a separate content struct. `hot` and `hot_close` are -1 when
     * nothing is hovered. */
    const SpdfWinChromeTab* tabs;
    int tab_count;
    int selected_tab;
    int hot_tab;
    int hot_close;

    int dark;
    int presentation; /* collapses the strip and toolbar to zero, as :13634 does */
    int show_sidebar;
    int show_minimap;
    float sidebar_w;   /* points; 0 asks for the default */
    float minimap_w;   /* points; 0 asks for the default */
    int sidebar_section; /* 0 chapters, 1 comments, 2 search */
    int search_active;   /* the Search section exists only while a query is live */
} SpdfWinChromeModel;

static SPDF_WIN_CHROME_INLINE SpdfWinChromeRect spdf_win_chrome_zero(void) {
    SpdfWinChromeRect r;
    r.x = r.y = r.w = r.h = 0.0f;
    return r;
}

static SPDF_WIN_CHROME_INLINE int spdf_win_chrome_rect_empty(SpdfWinChromeRect r) {
    return !(r.w > 0.0f && r.h > 0.0f);
}

static SPDF_WIN_CHROME_INLINE int spdf_win_chrome_contains(SpdfWinChromeRect r, float x, float y) {
    if (spdf_win_chrome_rect_empty(r)) return 0;
    return x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h;
}

static SPDF_WIN_CHROME_INLINE float spdf_win_chrome_max(float a, float b) { return a > b ? a : b; }
static SPDF_WIN_CHROME_INLINE float spdf_win_chrome_min(float a, float b) { return a < b ? a : b; }

/* Whole device pixels. Chrome edges must land on the pixel grid: a band at a
 * fractional y puts a 1 px separator across two rows, which is the defect the
 * dark page border already hit at 150% (spdf_win_d2d.cpp draw_canvas_page). */
static SPDF_WIN_CHROME_INLINE float spdf_win_chrome_px(double points, float dpi_scale) {
    float s = dpi_scale > 0.0f ? dpi_scale : 1.0f;
    return floorf((float)(points * (double)s) + 0.5f);
}

/* Clamp helpers matching macOS's own, so a restored width lands where macOS
 * would put it (ShenzhenPDFMac.mm:179-187, :1455). */
static SPDF_WIN_CHROME_INLINE float spdf_win_chrome_clamp_sidebar_pt(float want_pt, float split_w_pt,
                                                                     int search_active) {
    float lo = search_active ? (float)SPDF_WIN_CHROME_SIDEBAR_SEARCH_MIN_W : (float)SPDF_WIN_CHROME_SIDEBAR_MIN_W;
    float hi = (float)SPDF_WIN_CHROME_SIDEBAR_MAX_W;
    float frac = (float)(SPDF_WIN_CHROME_SIDEBAR_MAX_FRACTION * (double)split_w_pt);
    if (want_pt <= 0.0f) want_pt = (float)SPDF_WIN_CHROME_SIDEBAR_W;
    if (frac > 0.0f) hi = spdf_win_chrome_min(hi, frac);
    /* A window narrow enough that the fraction falls below the minimum cannot
     * satisfy both. macOS resolves this by letting the minimum win and letting
     * the split view squeeze the canvas; matching that is what keeps a narrow
     * window's sidebar usable rather than a sliver. */
    if (hi < lo) hi = lo;
    return spdf_win_chrome_max(lo, spdf_win_chrome_min(hi, want_pt));
}

static SPDF_WIN_CHROME_INLINE float spdf_win_chrome_clamp_minimap_pt(float want_pt, float container_w_pt) {
    float hi = (float)SPDF_WIN_CHROME_MINIMAP_MAX_W;
    float drag_hi;
    if (want_pt <= 0.0f) want_pt = (float)SPDF_WIN_CHROME_MINIMAP_W;
    drag_hi = (float)spdf_win_chrome_max(120.0f,
                                        spdf_win_chrome_min(320.0f, (float)(SPDF_WIN_CHROME_MINIMAP_DRAG_MAX_FRACTION *
                                                                            (double)container_w_pt)));
    hi = spdf_win_chrome_min(hi, drag_hi);
    if (hi < (float)SPDF_WIN_CHROME_MINIMAP_MIN_W) hi = (float)SPDF_WIN_CHROME_MINIMAP_MIN_W;
    return spdf_win_chrome_max((float)SPDF_WIN_CHROME_MINIMAP_MIN_W, spdf_win_chrome_min(hi, want_pt));
}

/* THE ONE ENTRY POINT.
 *
 * Divides a client area of client_px_w x client_px_h device pixels. Order of
 * operations mirrors the macOS view tree: the two full-width bands come off the
 * top, then what is left is the split view, and the side panels come off its
 * edges. The canvas gets the remainder -- never a negative remainder, which is
 * why every step clamps rather than subtracting blindly.
 *
 * A panel whose divider would not fit is dropped WITH its divider, so a window
 * can never show a divider with nothing beyond it. */
static SPDF_WIN_CHROME_INLINE void spdf_win_chrome_layout(const SpdfWinChromeModel* model, unsigned client_px_w,
                                                          unsigned client_px_h, float dpi_scale,
                                                          SpdfWinChromeLayout* out) {
    float w = (float)client_px_w;
    float h = (float)client_px_h;
    float s = dpi_scale > 0.0f ? dpi_scale : 1.0f;
    float y = 0.0f;
    float split_top, split_h, split_w_pt;
    float div_px = spdf_win_chrome_px(SPDF_WIN_CHROME_DIVIDER_W, s);
    float left = 0.0f, right = w;

    if (!out) return;
    out->tabstrip = spdf_win_chrome_zero();
    out->toolbar = spdf_win_chrome_zero();
    out->sidebar = spdf_win_chrome_zero();
    out->sidebar_divider = spdf_win_chrome_zero();
    out->canvas = spdf_win_chrome_zero();
    out->minimap_divider = spdf_win_chrome_zero();
    out->minimap = spdf_win_chrome_zero();
    out->dpi_scale = s;
    if (!model || w <= 0.0f || h <= 0.0f) return;

    /* --- the two bands ---------------------------------------------------
     * Presentation mode collapses both to zero rather than hiding them, which
     * is what :13634 does, so the canvas gets the whole window. */
    if (!model->presentation) {
        float strip_h = spdf_win_chrome_px(SPDF_WIN_CHROME_TABSTRIP_H, s);
        float bar_h = spdf_win_chrome_px(SPDF_WIN_CHROME_TOOLBAR_H, s);
        /* Do not let chrome eat a window so small that nothing is left to
         * read. Below this the bands are dropped in the order that keeps the
         * document usable: the toolbar first, then the strip. */
        if (strip_h + bar_h < h * 0.75f) {
            out->tabstrip.x = 0.0f;
            out->tabstrip.y = 0.0f;
            out->tabstrip.w = w;
            out->tabstrip.h = strip_h;
            y += strip_h;

            out->toolbar.x = 0.0f;
            out->toolbar.y = y;
            out->toolbar.w = w;
            out->toolbar.h = bar_h;
            y += bar_h;
        } else if (strip_h < h * 0.5f) {
            out->tabstrip.x = 0.0f;
            out->tabstrip.y = 0.0f;
            out->tabstrip.w = w;
            out->tabstrip.h = strip_h;
            y += strip_h;
        }
    }

    split_top = y;
    split_h = spdf_win_chrome_max(0.0f, h - y);
    if (split_h <= 0.0f) return;
    split_w_pt = w / s;

    /* --- sidebar, from the leading edge --------------------------------- */
    if (model->show_sidebar) {
        float want = spdf_win_chrome_clamp_sidebar_pt(model->sidebar_w, split_w_pt, model->search_active);
        float px = spdf_win_chrome_px(want, s);
        /* Leave at least the divider plus a token canvas, else drop the panel
         * and its divider together. */
        if (px + div_px < w * 0.9f) {
            out->sidebar.x = left;
            out->sidebar.y = split_top;
            out->sidebar.w = px;
            out->sidebar.h = split_h;
            left += px;

            out->sidebar_divider.x = left;
            out->sidebar_divider.y = split_top;
            out->sidebar_divider.w = div_px;
            out->sidebar_divider.h = split_h;
            left += div_px;
        }
    }

    /* --- minimap, from the trailing edge -------------------------------- */
    if (model->show_minimap) {
        float want = spdf_win_chrome_clamp_minimap_pt(model->minimap_w, split_w_pt);
        float px = spdf_win_chrome_px(want, s);
        if (left + div_px + px < right - div_px) {
            out->minimap.x = right - px;
            out->minimap.y = split_top;
            out->minimap.w = px;
            out->minimap.h = split_h;
            right -= px;

            out->minimap_divider.x = right - div_px;
            out->minimap_divider.y = split_top;
            out->minimap_divider.w = div_px;
            out->minimap_divider.h = split_h;
            right -= div_px;
        }
    }

    /* --- canvas gets what is left --------------------------------------- */
    out->canvas.x = left;
    out->canvas.y = split_top;
    out->canvas.w = spdf_win_chrome_max(0.0f, right - left);
    out->canvas.h = split_h;
}

/* Dividers are tested FIRST and with a widened grab area: a 5 pt divider is a
 * hard target with a mouse, and macOS gets the same forgiveness from its
 * NSSplitView. The widening overlaps the neighbouring panels, so testing the
 * panels first would make the divider unusable. */
#define SPDF_WIN_CHROME_DIVIDER_GRAB_SLOP 2.0

static SPDF_WIN_CHROME_INLINE SpdfWinChromeRect spdf_win_chrome_grab_rect(SpdfWinChromeRect divider, float dpi_scale) {
    float slop;
    if (spdf_win_chrome_rect_empty(divider)) return spdf_win_chrome_zero();
    slop = spdf_win_chrome_px(SPDF_WIN_CHROME_DIVIDER_GRAB_SLOP, dpi_scale);
    divider.x -= slop;
    divider.w += 2.0f * slop;
    return divider;
}

static SPDF_WIN_CHROME_INLINE spdf_win_chrome_part spdf_win_chrome_hit(const SpdfWinChromeLayout* l, float x,
                                                                      float y) {
    if (!l) return SPDF_WIN_CHROME_NONE;
    if (spdf_win_chrome_contains(spdf_win_chrome_grab_rect(l->sidebar_divider, l->dpi_scale), x, y))
        return SPDF_WIN_CHROME_SIDEBAR_DIVIDER;
    if (spdf_win_chrome_contains(spdf_win_chrome_grab_rect(l->minimap_divider, l->dpi_scale), x, y))
        return SPDF_WIN_CHROME_MINIMAP_DIVIDER;
    if (spdf_win_chrome_contains(l->tabstrip, x, y)) return SPDF_WIN_CHROME_TABSTRIP;
    if (spdf_win_chrome_contains(l->toolbar, x, y)) return SPDF_WIN_CHROME_TOOLBAR;
    if (spdf_win_chrome_contains(l->sidebar, x, y)) return SPDF_WIN_CHROME_SIDEBAR;
    if (spdf_win_chrome_contains(l->minimap, x, y)) return SPDF_WIN_CHROME_MINIMAP;
    if (spdf_win_chrome_contains(l->canvas, x, y)) return SPDF_WIN_CHROME_CANVAS;
    return SPDF_WIN_CHROME_NONE;
}

/* New width in POINTS for a divider drag, clamped the way macOS clamps it.
 * The sidebar's trailing edge follows the pointer; the minimap's leading edge
 * moves the opposite way, hence the subtraction. */
static SPDF_WIN_CHROME_INLINE float spdf_win_chrome_sidebar_drag_pt(const SpdfWinChromeLayout* l, float pointer_x,
                                                                    int search_active) {
    float s, want_pt, split_w_pt;
    if (!l) return 0.0f;
    s = l->dpi_scale > 0.0f ? l->dpi_scale : 1.0f;
    want_pt = (pointer_x - l->sidebar.x) / s;
    split_w_pt = (l->sidebar.w + l->sidebar_divider.w + l->canvas.w + l->minimap_divider.w + l->minimap.w) / s;
    return spdf_win_chrome_clamp_sidebar_pt(want_pt, split_w_pt, search_active);
}

static SPDF_WIN_CHROME_INLINE float spdf_win_chrome_minimap_drag_pt(const SpdfWinChromeLayout* l, float pointer_x) {
    float s, want_pt, split_w_pt;
    if (!l) return 0.0f;
    s = l->dpi_scale > 0.0f ? l->dpi_scale : 1.0f;
    want_pt = ((l->minimap.x + l->minimap.w) - pointer_x) / s;
    split_w_pt = (l->sidebar.w + l->sidebar_divider.w + l->canvas.w + l->minimap_divider.w + l->minimap.w) / s;
    return spdf_win_chrome_clamp_minimap_pt(want_pt, split_w_pt);
}

#endif /* SPDF_WIN_CHROME_H */
