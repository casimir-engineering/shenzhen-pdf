/* spdf_win_chrome_toolbar.h — where each toolbar control sits.
 *
 * WHY THIS FILE EXISTS. The toolbar's arithmetic used to live inside
 * spdf_win_chrome_toolbar.cpp's painter, interleaved with the drawing, and while
 * nothing could click a toolbar that was harmless. It is not harmless now:
 * spdf_win_chrome.h's second stated reason for separating geometry from painting
 * is that "hit-testing and painting must agree exactly ... here they agree only
 * if they call the same functions". A router that re-derived where the zoom pill
 * is would be a router that drifts from the pixels the moment either side is
 * touched, and the drift would be silent -- a button that looks right and
 * responds two pixels away.
 *
 * So the row is laid out ONCE, here, into a table of rects. The painter walks
 * that table and draws; spdf_win_chrome_input.h walks the same table and
 * hit-tests. Pure, toolkit-free, header-only, no state, no allocation -- the
 * same shape as spdf_win_chrome.h and spdf_win_tabstrip.h, and testable the same
 * way (portable/win/tests/chrome_input_test.c).
 *
 * THE METRICS ARE macOS'S, transcribed with the layout in
 * portable/mac/ShenzhenPDFMac.mm:2964-2968 and :3105-3122 -- SPDFToolbarStackView,
 * horizontal, spacing 4.0, edgeInsets (7, 6, 7, 6), 42 pt tall, with custom
 * spacing 8.0 after the zoom pill, the reading-theme button and the search
 * field. See spdf_win_chrome_toolbar.cpp's header for the full 18-item list and
 * for what each control looks like.
 *
 * ONE DELIBERATE DIVERGENCE FROM THE STACK VIEW. AppKit resolves this row by
 * measuring every control and hiding whole groups when they do not fit
 * (:2866-2909). This header instead lays the row out from BOTH ends -- the
 * left-hand group forward from the leading inset, the Map toggle and the
 * overflow button backward from the trailing inset -- and drops the find group
 * when the gap between them is too small, which is the same rule the painter
 * already applied. Widths that AppKit would measure from a string are constants
 * here so the row can lay itself out with no text-metric pass, which is what
 * keeps this header free of DirectWrite and therefore testable without a device.
 *
 * UNITS. Points in via the metrics, device pixels out, exactly as
 * spdf_win_chrome.h: every metric goes through spdf_win_chrome_px() so a control
 * edge lands on the pixel grid. The bar rect handed in is already in client
 * device pixels, so the rects that come out are too -- which is the space both
 * the render target and WM_LBUTTONDOWN work in, so neither consumer converts.
 */
/* GUARD NAME. Not SPDF_WIN_CHROME_TOOLBAR_H, which spdf_win_chrome.h:64 already
 * uses for the toolbar's HEIGHT -- a 42.0 metric, not a guard. The obvious guard
 * name for this file is therefore always already defined, so the whole header
 * silently preprocesses to nothing and every one of its types comes back as
 * "undeclared identifier" at the point of USE, in the file that included it.
 * Cost half an hour. Do not "tidy" this back. */
#ifndef SPDF_WIN_CHROME_TOOLBAR_GEOMETRY_H
#define SPDF_WIN_CHROME_TOOLBAR_GEOMETRY_H

#include "spdf_win_chrome.h"

#if defined(_MSC_VER) && !defined(__cplusplus)
#define SPDF_WIN_TB_INLINE __inline
#else
#define SPDF_WIN_TB_INLINE inline
#endif

/* --- metrics, cited to portable/mac/ShenzhenPDFMac.mm -------------------- */

#define SPDF_WIN_TB_INSET_X 6.0  /* edgeInsets left/right (:2966) */
#define SPDF_WIN_TB_INSET_Y 7.0  /* edgeInsets top/bottom; 42 - 2*7 = 28 */
#define SPDF_WIN_TB_SPACING 4.0  /* the stack view's spacing (:2965) */
#define SPDF_WIN_TB_WIDE_SPACING 8.0 /* setCustomSpacing:8.0 (:3123-3125) */
#define SPDF_WIN_TB_CONTROL_H 28.0
#define SPDF_WIN_TB_ICON_W 32.0        /* :3059, :3072 -- the icon buttons */
#define SPDF_WIN_TB_PAGE_FIELD_W 50.0  /* :2986 */
#define SPDF_WIN_TB_PAGE_COUNT_W 44.0  /* the "/ N" label; AppKit measures it */
#define SPDF_WIN_TB_FIT_POPUP_W 96.0   /* :3021 */
#define SPDF_WIN_TB_SEARCH_FIELD_W 141.0 /* :3032, the un-squeezed width */
#define SPDF_WIN_TB_SEGMENT_W 32.0     /* one half of a pill */
#define SPDF_WIN_TB_PILL_W 64.0        /* a two-segment pill */
#define SPDF_WIN_TB_OVERFLOW_W 30.0    /* :3096 */
/* SPDFToolbarToggleButton's intrinsic width is titleWidth + 50.0
 * (SPDFMacUIHelpers.mm:144-246). "Side Panel" and "Map" at systemFontOfSize:12
 * Light measure ~62 and ~24, so these are those two sums, constant rather than
 * measured -- see the header comment on why the row must not need a text pass. */
#define SPDF_WIN_TB_SIDEBAR_TOGGLE_W 112.0
#define SPDF_WIN_TB_MINIMAP_TOGGLE_W 74.0

/* Every control the row can contain, left to right in the order the stack view
 * arranges them. The five macOS items this port does not draw yet (the markdown
 * font-size pill, the regex checkbox, the find-count label, the flexible spacer)
 * are absent rather than reserved: an item in this table is an item with a rect,
 * and a rect nothing draws is a rect something could still click. */
typedef enum spdf_win_toolbar_item {
    SPDF_WIN_TB_NONE = 0,
    SPDF_WIN_TB_SIDEBAR_TOGGLE,
    SPDF_WIN_TB_OCR,
    SPDF_WIN_TB_TRANSLATE,
    SPDF_WIN_TB_SEPARATOR,
    SPDF_WIN_TB_PAGE_FIELD,
    SPDF_WIN_TB_PAGE_COUNT,
    SPDF_WIN_TB_PAGE_PILL,
    SPDF_WIN_TB_FIT_POPUP,
    SPDF_WIN_TB_ZOOM_PILL,
    SPDF_WIN_TB_READING_THEME,
    SPDF_WIN_TB_FIND_FIELD,
    SPDF_WIN_TB_FIND_PILL,
    SPDF_WIN_TB_OVERFLOW,
    SPDF_WIN_TB_MINIMAP_TOGGLE,
    SPDF_WIN_TB_ITEM_COUNT
} spdf_win_toolbar_item;

/* Indexed by spdf_win_toolbar_item. An empty rect means the control is not in
 * the row at all -- the find group in a narrow window, or everything when the
 * toolbar itself has been collapsed by a tiny window or presentation mode. Every
 * consumer must treat w <= 0 as absent, which is the same contract
 * SpdfWinChromeLayout states. */
typedef struct SpdfWinToolbarLayout {
    SpdfWinChromeRect item[SPDF_WIN_TB_ITEM_COUNT];
    float dpi_scale;
} SpdfWinToolbarLayout;

/* Whole device pixels for a hairline, matching spdf_win_chrome_stroke_px() in
 * spdf_win_chrome_paint.h. Duplicated as three lines rather than taken from
 * there because that header is C++ and pulls in Direct2D, and this one must
 * stay compilable by a plain C test. SPDF_WIN_CT_HAIRLINE is 1.0f. */
static SPDF_WIN_TB_INLINE float spdf_win_tb_hairline_px(float dpi_scale) {
    float s = dpi_scale > 0.0f ? dpi_scale : 1.0f;
    float w = floorf(1.0f * s + 0.5f);
    return w < 1.0f ? 1.0f : w;
}

/* One segment of a `segments`-wide pill. The painter's cell_of(), moved here so
 * the two chevrons it draws and the two halves the router hit-tests are the same
 * two rectangles. */
static SPDF_WIN_TB_INLINE SpdfWinChromeRect spdf_win_toolbar_cell(SpdfWinChromeRect pill, int index, int segments) {
    SpdfWinChromeRect c = pill;
    if (segments < 1) segments = 1;
    c.w = pill.w / (float)segments;
    c.x = pill.x + c.w * (float)index;
    return c;
}

/* THE ONE ENTRY POINT. `bar` is SpdfWinChromeLayout::toolbar, in client device
 * pixels; an empty bar yields an all-empty table. */
static SPDF_WIN_TB_INLINE void spdf_win_toolbar_layout(SpdfWinChromeRect bar, float dpi_scale,
                                                       SpdfWinToolbarLayout* out) {
    float s = dpi_scale > 0.0f ? dpi_scale : 1.0f;
    float x, y, h, right;
    int i;

    if (!out) return;
    for (i = 0; i < SPDF_WIN_TB_ITEM_COUNT; ++i) out->item[i] = spdf_win_chrome_zero();
    out->dpi_scale = s;
    if (spdf_win_chrome_rect_empty(bar)) return;

    y = bar.y + spdf_win_chrome_px(SPDF_WIN_TB_INSET_Y, s);
    h = spdf_win_chrome_px(SPDF_WIN_TB_CONTROL_H, s);
    x = bar.x + spdf_win_chrome_px(SPDF_WIN_TB_INSET_X, s);
    right = bar.x + bar.w - spdf_win_chrome_px(SPDF_WIN_TB_INSET_X, s);

/* The forward and backward walks, as two macros, because the alternative is
 * fourteen five-line blocks that differ only in a width -- and the mistake that
 * form invites is forgetting one advance, which shifts every control after it. */
#define SPDF_WIN_TB_PLACE(id, width_pt, advance_pt)                                                                    \
    do {                                                                                                               \
        out->item[(id)].x = x;                                                                                         \
        out->item[(id)].y = y;                                                                                         \
        out->item[(id)].w = spdf_win_chrome_px((width_pt), s);                                                          \
        out->item[(id)].h = h;                                                                                         \
        x += out->item[(id)].w + spdf_win_chrome_px((advance_pt), s);                                                   \
    } while (0)

#define SPDF_WIN_TB_PLACE_TRAILING(id, width_pt)                                                                       \
    do {                                                                                                               \
        out->item[(id)].w = spdf_win_chrome_px((width_pt), s);                                                          \
        out->item[(id)].x = right - out->item[(id)].w;                                                                  \
        out->item[(id)].y = y;                                                                                         \
        out->item[(id)].h = h;                                                                                         \
        right = out->item[(id)].x - spdf_win_chrome_px(SPDF_WIN_TB_SPACING, s);                                         \
    } while (0)

    SPDF_WIN_TB_PLACE(SPDF_WIN_TB_SIDEBAR_TOGGLE, SPDF_WIN_TB_SIDEBAR_TOGGLE_W, SPDF_WIN_TB_SPACING);
    SPDF_WIN_TB_PLACE(SPDF_WIN_TB_OCR, SPDF_WIN_TB_ICON_W, SPDF_WIN_TB_SPACING);
    SPDF_WIN_TB_PLACE(SPDF_WIN_TB_TRANSLATE, SPDF_WIN_TB_ICON_W, SPDF_WIN_TB_SPACING);

    /* The separator is an NSBox of width 1 inset 4 pt top and bottom (:2977).
     * Its drawn width is a hairline but the row advances by a whole point, which
     * is what the painter did and what keeps every control after it in the same
     * place at every DPI. */
    out->item[SPDF_WIN_TB_SEPARATOR].x = x;
    out->item[SPDF_WIN_TB_SEPARATOR].y = y + spdf_win_chrome_px(4.0, s);
    out->item[SPDF_WIN_TB_SEPARATOR].w = spdf_win_tb_hairline_px(s);
    out->item[SPDF_WIN_TB_SEPARATOR].h = h - 2.0f * spdf_win_chrome_px(4.0, s);
    x += spdf_win_chrome_px(1.0, s) + spdf_win_chrome_px(SPDF_WIN_TB_SPACING, s);

    SPDF_WIN_TB_PLACE(SPDF_WIN_TB_PAGE_FIELD, SPDF_WIN_TB_PAGE_FIELD_W, SPDF_WIN_TB_SPACING);
    SPDF_WIN_TB_PLACE(SPDF_WIN_TB_PAGE_COUNT, SPDF_WIN_TB_PAGE_COUNT_W, SPDF_WIN_TB_SPACING);
    SPDF_WIN_TB_PLACE(SPDF_WIN_TB_PAGE_PILL, SPDF_WIN_TB_PILL_W, SPDF_WIN_TB_SPACING);
    SPDF_WIN_TB_PLACE(SPDF_WIN_TB_FIT_POPUP, SPDF_WIN_TB_FIT_POPUP_W, SPDF_WIN_TB_SPACING);
    SPDF_WIN_TB_PLACE(SPDF_WIN_TB_ZOOM_PILL, SPDF_WIN_TB_PILL_W, SPDF_WIN_TB_WIDE_SPACING);
    SPDF_WIN_TB_PLACE(SPDF_WIN_TB_READING_THEME, SPDF_WIN_TB_ICON_W, SPDF_WIN_TB_WIDE_SPACING);

    SPDF_WIN_TB_PLACE_TRAILING(SPDF_WIN_TB_MINIMAP_TOGGLE, SPDF_WIN_TB_MINIMAP_TOGGLE_W);
    SPDF_WIN_TB_PLACE_TRAILING(SPDF_WIN_TB_OVERFLOW, SPDF_WIN_TB_OVERFLOW_W);

    /* The find group, only when the gap left between the two walks can hold it.
     * This stands in for macOS's group-by-group overflow, and it is the ONE
     * place the two walks interact -- which is why it is tested. */
    if (right - x > spdf_win_chrome_px(SPDF_WIN_TB_SEARCH_FIELD_W + 2.0 * SPDF_WIN_TB_SEGMENT_W +
                                           3.0 * SPDF_WIN_TB_SPACING,
                                       s)) {
        SPDF_WIN_TB_PLACE_TRAILING(SPDF_WIN_TB_FIND_PILL, SPDF_WIN_TB_PILL_W);
        SPDF_WIN_TB_PLACE_TRAILING(SPDF_WIN_TB_FIND_FIELD, SPDF_WIN_TB_SEARCH_FIELD_W);
    }

#undef SPDF_WIN_TB_PLACE
#undef SPDF_WIN_TB_PLACE_TRAILING
}

/* Which control a point lands on, and for a pill which half.
 *
 * The separator is skipped: it is decoration a hairline wide, and letting a
 * click land on it would mean a click 1 px left of the page field doing nothing
 * instead of falling through to the bar. `out_segment` is 0 for a non-pill and
 * for a miss. */
static SPDF_WIN_TB_INLINE spdf_win_toolbar_item spdf_win_toolbar_hit(const SpdfWinToolbarLayout* l, float x, float y,
                                                                    int* out_segment) {
    int i;
    if (out_segment) *out_segment = 0;
    if (!l) return SPDF_WIN_TB_NONE;
    for (i = SPDF_WIN_TB_NONE + 1; i < SPDF_WIN_TB_ITEM_COUNT; ++i) {
        if (i == SPDF_WIN_TB_SEPARATOR) continue;
        if (!spdf_win_chrome_contains(l->item[i], x, y)) continue;
        if (out_segment &&
            (i == SPDF_WIN_TB_PAGE_PILL || i == SPDF_WIN_TB_ZOOM_PILL || i == SPDF_WIN_TB_FIND_PILL)) {
            /* Which half, from the pill's own rect rather than from a midpoint
             * recomputed here, so a pill of odd device width splits exactly
             * where spdf_win_toolbar_cell() drew the divider. */
            SpdfWinChromeRect second = spdf_win_toolbar_cell(l->item[i], 1, 2);
            *out_segment = x >= second.x ? 1 : 0;
        }
        return (spdf_win_toolbar_item)i;
    }
    return SPDF_WIN_TB_NONE;
}

#endif /* SPDF_WIN_CHROME_TOOLBAR_GEOMETRY_H */
