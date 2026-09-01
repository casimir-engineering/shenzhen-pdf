/* spdf_win_chrome_input.h — what a mouse event over the chrome MEANS.
 *
 * WHAT THIS IS: one pure function that turns (how the client area is divided,
 * what the chrome is showing, where the pointer is, which button) into an
 * ACTION plus the hover state the painter needs. No Win32, no Direct2D, no app
 * state, no allocation, header-only -- the third member of the family
 * spdf_win_chrome.h and spdf_win_tabstrip.h belong to, and testable the same way
 * (portable/win/tests/chrome_input_test.c).
 *
 * WHY IT IS A SEPARATE LAYER, given that the window could just hit-test inline.
 *
 *   1. spdf_win_chrome.h says the reason out loud: "Hit-testing and painting
 *      must agree exactly. On macOS they do because AppKit owns both; here they
 *      agree only if they call the same functions." Everything below calls
 *      spdf_win_chrome_hit(), spdf_win_tabstrip_hit(), spdf_win_tabstrip_close_hit()
 *      and spdf_win_toolbar_hit() -- the same four the painters use -- and
 *      derives nothing of its own. Re-deriving would mean re-deriving their bug
 *      fixes too (portable/docs/windows-port-plan.md §2.3).
 *   2. A window proc cannot be tested. This can: a click at (x, y) on a
 *      hand-built layout must produce a named action, and that assertion needs
 *      no HWND, no desktop and no document -- which is the only kind of evidence
 *      this port has ever been able to collect in bulk.
 *   3. Which control does what is PRODUCT POLICY, and spdf_win_window.h already
 *      states the rule for that: "the caller owns the keymap: which key means
 *      'next page' is product policy, not window plumbing." A mouse map is the
 *      same thing. So the window translates messages, this header names the
 *      meaning, and spdf_win_main.cpp performs it.
 *
 * WHAT IT DELIBERATELY DOES NOT DO: it does not touch the canvas, the tab model,
 * or the chrome model. It reports SPDF_WIN_CA_CANVAS and lets the caller run the
 * existing pan/zoom path unchanged, which is what keeps drag-to-pan and
 * Ctrl+wheel exactly as they were everywhere the chrome is not.
 *
 * COORDINATES. Client device pixels in, matching WM_LBUTTONDOWN's own space and
 * the space every rect in SpdfWinChromeLayout is expressed in. The canvas is a
 * SUB-RECT of the client now, so a caller forwarding a point to the canvas must
 * subtract layout->canvas.x/y first: spdf_win_chrome_input_canvas_x/y() below do
 * that conversion so no caller has to remember to. Getting it wrong makes a
 * cursor-anchored zoom drift by the sidebar's width.
 */
#ifndef SPDF_WIN_CHROME_INPUT_H
#define SPDF_WIN_CHROME_INPUT_H

#include "spdf_win_chrome.h"
#include "spdf_win_chrome_toolbar.h"
#include "spdf_win_tabstrip.h"

#if defined(_MSC_VER) && !defined(__cplusplus)
#define SPDF_WIN_CI_INLINE __inline
#else
#define SPDF_WIN_CI_INLINE inline
#endif

/* Which button produced the event. NONE is a bare move -- the hover case, which
 * still needs routing because it is what lights the tab strip's hover branches
 * and what chooses the cursor. */
typedef enum spdf_win_chrome_button {
    SPDF_WIN_CB_NONE = 0,
    SPDF_WIN_CB_LEFT,
    SPDF_WIN_CB_MIDDLE
} spdf_win_chrome_button;

/* What the caller should do. Named after the INTENT, not after the control, so
 * the keyboard and the mouse can converge on the same handler -- the zoom pill
 * and VK_ADD both mean SPDF_WIN_CA_ZOOM_IN, and spdf_win_main.cpp's existing
 * `+`/`-` logic is reused rather than restated. */
typedef enum spdf_win_chrome_action {
    SPDF_WIN_CA_NONE = 0,
    /* Not chrome. Run the document's own pan/zoom path, in CANVAS-LOCAL
     * coordinates. */
    SPDF_WIN_CA_CANVAS,
    SPDF_WIN_CA_SELECT_TAB,   /* `index` */
    SPDF_WIN_CA_CLOSE_TAB,    /* `index` */
    SPDF_WIN_CA_NEW_TAB,      /* the strip's `+` */
    SPDF_WIN_CA_TAB_OVERFLOW, /* the strip's `…` */
    SPDF_WIN_CA_PREV_PAGE,
    SPDF_WIN_CA_NEXT_PAGE,
    SPDF_WIN_CA_ZOOM_OUT,
    SPDF_WIN_CA_ZOOM_IN,
    SPDF_WIN_CA_CYCLE_FIT, /* the fit popup, until there is a real menu */
    SPDF_WIN_CA_TOGGLE_SIDEBAR,
    SPDF_WIN_CA_TOGGLE_MINIMAP,
    SPDF_WIN_CA_TOGGLE_THEME,
    /* A press on a split divider. The caller then follows the pointer and asks
     * spdf_win_chrome_sidebar_drag_pt() / _minimap_drag_pt() for the new width,
     * which clamp exactly as macOS's NSSplitView does. */
    SPDF_WIN_CA_DRAG_SIDEBAR,
    SPDF_WIN_CA_DRAG_MINIMAP
} spdf_win_chrome_action;

/* Cursors as an enum rather than as an HCURSOR, so this header stays free of
 * user32 and a test can assert "the pointer over a divider asks for the
 * left-right resize cursor" with no window. macOS uses resizeLeftRight over its
 * dividers (SPDFMacUIHelpers.mm:425-431); IDC_SIZEWE is the same thing. */
typedef enum spdf_win_chrome_cursor {
    SPDF_WIN_CC_ARROW = 0,
    SPDF_WIN_CC_SIZEWE,
    /* IDC_SIZEALL, shown while a drag is panning the document. Produced by the
     * caller's drag state rather than by the router below: a point over the
     * canvas is an arrow until a button goes down on it. */
    SPDF_WIN_CC_SIZEALL
} spdf_win_chrome_cursor;

typedef struct SpdfWinChromeHit {
    spdf_win_chrome_action action;
    int index; /* tab index for SELECT_TAB / CLOSE_TAB, else -1 */
    spdf_win_chrome_part part;
    /* Straight into SpdfWinChromeModel::hot_tab / hot_close, so the painter's
     * existing hover branches light up without the caller deciding anything.
     * -1 when nothing is hovered, which is the value the model documents. */
    int hot_tab;
    int hot_close;
    spdf_win_chrome_cursor cursor;
} SpdfWinChromeHit;

/* A client point in CANVAS-LOCAL device pixels. The canvas was laid out against
 * the canvas rect's size (spdf_win_canvas_set_viewport is given
 * chrome_layout.canvas.w/h), so every canvas API -- scroll, and above all
 * spdf_win_canvas_zoom_at()'s anchor -- expects the origin at the canvas's
 * top-left corner and not at the window's. Before the chrome existed the two
 * were the same point and the window passed client coordinates straight through;
 * they are 245 px apart now with the sidebar open, and a Ctrl+wheel zoom fed the
 * un-translated point anchors on a document location that is not under the
 * cursor -- it drifts by exactly the offset. */
static SPDF_WIN_CI_INLINE float spdf_win_chrome_input_canvas_x(const SpdfWinChromeLayout* l, float client_x) {
    return l ? client_x - l->canvas.x : client_x;
}

static SPDF_WIN_CI_INLINE float spdf_win_chrome_input_canvas_y(const SpdfWinChromeLayout* l, float client_y) {
    return l ? client_y - l->canvas.y : client_y;
}

/* THE ONE ENTRY POINT.
 *
 * `out` is always fully written, so a caller may read every field after any
 * call. A NULL layout or model yields NONE with no hover, which is the state
 * before the first paint has laid anything out.
 *
 * Order of decisions, and why each is where it is:
 *
 *   dividers first -- spdf_win_chrome_hit() already tests them first because
 *   their grab area overlaps their neighbours', and re-ordering here would make
 *   them unusable;
 *
 *   inside the strip, the CLOSE box before the tab -- the close circle lies
 *   inside the tab, so testing the tab first would swallow every close click
 *   (spdf_win_tabstrip.h says this at spdf_win_tabstrip_close_hit);
 *
 *   the canvas LAST, and only ever as CANVAS, so the fall-through to pan/zoom
 *   happens exactly where the pages are drawn and nowhere else. A click on the
 *   toolbar must not pan the document. */
static SPDF_WIN_CI_INLINE void spdf_win_chrome_input_route(const SpdfWinChromeLayout* l, const SpdfWinChromeModel* m,
                                                          float x, float y, int button, SpdfWinChromeHit* out) {
    float s;
    if (!out) return;
    out->action = SPDF_WIN_CA_NONE;
    out->index = -1;
    out->part = SPDF_WIN_CHROME_NONE;
    out->hot_tab = -1;
    out->hot_close = -1;
    out->cursor = SPDF_WIN_CC_ARROW;
    if (!l || !m) return;

    s = l->dpi_scale > 0.0f ? l->dpi_scale : 1.0f;
    out->part = spdf_win_chrome_hit(l, x, y);

    switch (out->part) {
        case SPDF_WIN_CHROME_SIDEBAR_DIVIDER:
            out->cursor = SPDF_WIN_CC_SIZEWE;
            if (button == SPDF_WIN_CB_LEFT) out->action = SPDF_WIN_CA_DRAG_SIDEBAR;
            return;
        case SPDF_WIN_CHROME_MINIMAP_DIVIDER:
            out->cursor = SPDF_WIN_CC_SIZEWE;
            if (button == SPDF_WIN_CB_LEFT) out->action = SPDF_WIN_CA_DRAG_MINIMAP;
            return;

        case SPDF_WIN_CHROME_TABSTRIP: {
            /* The strip's transcribed arithmetic works in strip-local POINTS,
             * exactly as SPDFMacTabStripView does, so the pointer is divided by
             * the DPI scale rather than the metrics being multiplied by it --
             * spdf_win_tabstrip.h's UNITS paragraph states this is the intended
             * direction, and it is what the painter's inverse conversion pairs
             * with. Passing device pixels in would silently change every
             * threshold in that header (112, 320, the 40 pt close cutoff). */
            float xp = (x - l->tabstrip.x) / s;
            float yp = (y - l->tabstrip.y) / s;
            float strip_w = l->tabstrip.w / s;
            float strip_h = l->tabstrip.h / s;
            int close = spdf_win_tabstrip_close_hit(strip_w, m->tab_count, m->selected_tab, xp, yp);
            int tab = spdf_win_tabstrip_hit(strip_w, strip_h, m->tab_count, m->selected_tab, xp, yp);

            if (close >= 0) out->hot_close = close;
            if (tab >= 0) out->hot_tab = tab;

            if (button == SPDF_WIN_CB_MIDDLE) {
                /* Middle-click closes a tab, which is macOS's behaviour and the
                 * desktop's. It closes the TAB, not the close box: aiming at a
                 * 16 pt circle with the middle button is not a gesture anyone
                 * makes. This is also why middle-drag can still pan -- the strip
                 * is the only place a middle button means something else. */
                if (tab >= 0) {
                    out->action = SPDF_WIN_CA_CLOSE_TAB;
                    out->index = tab;
                }
                return;
            }
            if (button != SPDF_WIN_CB_LEFT) return;
            if (close >= 0) {
                out->action = SPDF_WIN_CA_CLOSE_TAB;
                out->index = close;
                return;
            }
            if (tab >= 0) {
                out->action = SPDF_WIN_CA_SELECT_TAB;
                out->index = tab;
                return;
            }
            if (spdf_win_tabstrip_rect_contains(spdf_win_tabstrip_plus_rect(strip_w), xp, yp)) {
                out->action = SPDF_WIN_CA_NEW_TAB;
                return;
            }
            if (spdf_win_tabstrip_rect_contains(spdf_win_tabstrip_overflow_rect(strip_w, m->tab_count), xp, yp))
                out->action = SPDF_WIN_CA_TAB_OVERFLOW;
            return;
        }

        case SPDF_WIN_CHROME_TOOLBAR: {
            SpdfWinToolbarLayout tb;
            int segment = 0;
            spdf_win_toolbar_item item;
            if (button != SPDF_WIN_CB_LEFT) return;
            spdf_win_toolbar_layout(l->toolbar, s, &tb);
            item = spdf_win_toolbar_hit(&tb, x, y, &segment);
            switch (item) {
                case SPDF_WIN_TB_SIDEBAR_TOGGLE: out->action = SPDF_WIN_CA_TOGGLE_SIDEBAR; return;
                case SPDF_WIN_TB_MINIMAP_TOGGLE: out->action = SPDF_WIN_CA_TOGGLE_MINIMAP; return;
                case SPDF_WIN_TB_READING_THEME: out->action = SPDF_WIN_CA_TOGGLE_THEME; return;
                case SPDF_WIN_TB_PAGE_PILL:
                    /* chevron.left / chevron.right, in that order (:2996-3000). */
                    out->action = segment == 0 ? SPDF_WIN_CA_PREV_PAGE : SPDF_WIN_CA_NEXT_PAGE;
                    return;
                case SPDF_WIN_TB_ZOOM_PILL:
                    /* minus / plus, in that order (:3026-3030). */
                    out->action = segment == 0 ? SPDF_WIN_CA_ZOOM_OUT : SPDF_WIN_CA_ZOOM_IN;
                    return;
                case SPDF_WIN_TB_FIT_POPUP: out->action = SPDF_WIN_CA_CYCLE_FIT; return;
                default: return;
            }
        }

        case SPDF_WIN_CHROME_CANVAS: out->action = SPDF_WIN_CA_CANVAS; return;

        /* The sidebar's list and the minimap's thumbnails are still placeholders
         * (see the 4925e127d commit message), so a press inside either is
         * swallowed rather than passed to the canvas. Swallowed, not forwarded:
         * a drag begun on the sidebar that panned the document would be a worse
         * bug than a panel that does nothing yet. */
        default: return;
    }
}

#endif /* SPDF_WIN_CHROME_INPUT_H */
