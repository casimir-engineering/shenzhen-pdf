#pragma once

/* For spdf_win_chrome_content_set_document(): scene_for_window tells the panels
 * which document is selected. Included here rather than relying on it arriving
 * through spdf_win_main.cpp's include order, which is what left this header
 * depending on a declaration it never asked for. */
#include "spdf_win_chrome_content.h"

/* Performing what spdf_win_chrome_input.h decided.
 *
 * Internal to the Windows frontend and header-only, like spdf_win_tabs_app.h and
 * spdf_win_headless_viewport.h beside it, and for the same two reasons those give:
 * it depends on `struct app`, so it must be included from spdf_win_main.cpp after
 * that struct; and spdf_win_main.cpp is at its 500-line cap, where
 * tools/file-size-limits.md asks for an extracted file rather than a raised one.
 *
 * THE THREE-LAYER SPLIT, and why the middle layer exists at all:
 *
 *   spdf_win_window.cpp   translates Win32 messages. Owns the HWND, the capture
 *                         and the cursor. Knows no document and no chrome.
 *   spdf_win_chrome_input.h  decides what a point MEANS. Pure, testable, knows
 *                         no app.
 *   this file             does it. Knows both, and is the only file that does.
 *
 * That is the same shape spdf_win_window.h already imposed on the keyboard --
 * "the caller owns the keymap: which key means 'next page' is product policy,
 * not window plumbing" -- extended to the mouse, which is now a device that can
 * land on eight different things.
 *
 * TWO INVARIANTS THIS FILE EXISTS TO HOLD.
 *
 * 1. The chrome is laid out here with the SAME function and the SAME inputs the
 *    painter used, so a click lands on the rect that was drawn. Not a cached
 *    layout from the last paint: a cache is stale for exactly one event after a
 *    resize, and a divider that resizes the wrong panel for one frame is the kind
 *    of bug that gets blamed on the divider.
 *
 * 2. Canvas coordinates are CANVAS-LOCAL. The canvas is laid out against
 *    chrome_layout.canvas.w/h, so every canvas API -- and above all
 *    spdf_win_canvas_zoom_at()'s anchor -- has its origin at the canvas's own
 *    corner. Before the chrome existed that corner was the window's, and the
 *    window passed client coordinates straight through; with the sidebar open
 *    they are 245 px apart, and a Ctrl+wheel zoom fed the un-translated point
 *    anchors on a document point that is not under the cursor. Every conversion
 *    here goes through spdf_win_chrome_input_canvas_x/y() so there is one place
 *    to be wrong.
 */

/* The canvas's zoom mode in the vocabulary the toolbar speaks.
 *
 * Two enums rather than one because spdf_win_chrome.h must not include
 * spdf_win_canvas.h -- the chrome is drawn in tests that have no canvas, no
 * document and no MuPDF -- so this is the seam, and it is three lines. Note that
 * SPDF_WIN_CHROME_FIT_HEIGHT is unreachable: macOS offers Fit Height and
 * spdf_win_canvas.h does not have it yet. */
static int chrome_fit_for_zoom_mode(spdf_win_zoom_mode mode) {
    switch (mode) {
        case SPDF_WIN_ZOOM_FIT_WIDTH: return SPDF_WIN_CHROME_FIT_WIDTH;
        case SPDF_WIN_ZOOM_FIT_PAGE: return SPDF_WIN_CHROME_FIT_PAGE;
        case SPDF_WIN_ZOOM_ACTUAL: return SPDF_WIN_CHROME_FIT_ACTUAL;
        default: return SPDF_WIN_CHROME_FIT_CUSTOM;
    }
}

/* Everything the chrome shows about the document, read from the canvas ONCE per
 * paint and handed to the model. The painters never reach for any of it
 * themselves: spdf_win_chrome_paint.h's whole arrangement is that a painter works
 * from a hand-built model with no app behind it, which is what lets the window's
 * appearance be pixel-tested offscreen. */
static void chrome_inputs_for(app* a, SpdfWinChromeModelInputs* in, float dpi_scale) {
    spdf_win_chrome_model_inputs_init(in);
    in->dark = (a->render_flags & SPDF_RENDER_DARK_THEME) != 0;
    in->show_sidebar = a->show_sidebar;
    in->show_minimap = a->show_minimap;
    in->sidebar_w = a->sidebar_w;
    in->minimap_w = a->minimap_w;
    in->hot_tab = a->hot_tab;
    in->hot_close = a->hot_close;
    in->zoom_dpi_scale = dpi_scale > 0.0f ? dpi_scale : 1.0f;
    if (!a->canvas) return;
    /* 0-BASED out of the canvas and 0-BASED into the model. The `+ 1` that makes
     * it a human's page number happens once, in the toolbar painter. */
    in->page_index = spdf_win_canvas_current_page(a->canvas);
    in->page_count = spdf_win_canvas_page_count(a->canvas);
    in->zoom = spdf_win_canvas_zoom(a->canvas);
    in->fit_mode = chrome_fit_for_zoom_mode(spdf_win_canvas_zoom_mode(a->canvas));
}

/* THE PAINT-TIME GLUE. Chrome first, because it decides how big the canvas is.
 *
 * The model is rebuilt per paint rather than cached: it is a few dozen bytes plus
 * one UTF-16 conversion per tab, and a cached copy is how a closed tab keeps
 * being drawn -- or how a page indicator keeps reading 4 after the reader has
 * scrolled to 40. `a->chrome_tabs` owns the titles the model borrows and must
 * therefore live as long as the paint, which is why it is a field on `app`. */
static int scene_for_window(void* user, spdf_win_scene* scene) {
    app* a = (app*)user;
    SpdfWinChromeModelInputs inputs;
    SpdfWinChromeLayout chrome_layout;
    unsigned client_w, client_h;
    if (!a->canvas) return 0; /* the last tab just closed; the pump is exiting */

    client_w = scene->client_px_w ? scene->client_px_w : scene->target_px_w;
    client_h = scene->client_px_h ? scene->client_px_h : scene->target_px_h;

    /* Built twice, and deliberately. The first build only has to be right about
     * GEOMETRY, because it decides the canvas rect; the readouts it carries are
     * whatever the canvas said BEFORE this frame's viewport and fit were applied.
     * The second build, after the canvas has settled, is the one the painter
     * reads -- so a resize that re-fits the zoom shows the zoom it re-fitted to,
     * not the one it had a frame ago. Neither build can change the layout: every
     * field spdf_win_chrome_layout() looks at is identical in the two. */
    chrome_inputs_for(a, &inputs, scene->dpi_scale);
    spdf_win_chrome_model_build(&a->chrome, &a->chrome_tabs, a->tabs, &inputs);
    scene->chrome = &a->chrome;
    spdf_win_chrome_layout(&a->chrome, client_w, client_h, scene->dpi_scale, &chrome_layout);

    /* The canvas is laid out against the CANVAS REGION, not the client area, so
     * fit-width fits the space the reader can actually see. spdf_win_paint()
     * translates the page rects into that region, so everything downstream keeps
     * working in canvas-local coordinates. */
    spdf_win_canvas_set_viewport(a->canvas, (unsigned)chrome_layout.canvas.w, (unsigned)chrome_layout.canvas.h,
                                 scene->dpi_scale);
    if (a->pending_page > 0) {
        spdf_win_canvas_scroll_to_page(a->canvas, a->pending_page);
        a->pending_page = -1;
    }
    chrome_inputs_for(a, &inputs, scene->dpi_scale);
    spdf_win_chrome_model_build(&a->chrome, &a->chrome_tabs, a->tabs, &inputs);

    /* Tell the panels which document is selected and where the reader is in it.
     * The app is the only thing that knows both; left to itself the content
     * bridge guesses from the process command line, so the sidebar listed the
     * LAUNCH document's outline and the minimap its thumbnails even after a
     * Ctrl+Tab, next to a canvas showing the right pages. Passing the live
     * current page also makes the minimap's current-page outline follow
     * scrolling instead of pinning to the page the window opened on.
     *
     * Cheap by construction: same path is a strcmp and two stores. */
    {
        int sel = a->tabs ? spdf_win_tabs_selected_index(a->tabs) : -1;
        const char* sel_path = sel < 0 ? NULL : spdf_win_tabs_path(a->tabs, sel);
        spdf_win_chrome_content_set_document(sel_path ? sel_path : a->path,
                                            spdf_win_canvas_current_page(a->canvas));
    }

    if (spdf_win_canvas_build_scene(a->canvas, scene)) return 1;
    scene->message = a->status[0] ? a->status : NULL;
    return 1;
}

/* The model the ROUTER needs, which is not the model the PAINTER needs.
 *
 * The strip's geometry keys on tab_count and selected_tab; the titles cost a
 * UTF-16 conversion per tab and are only needed to draw glyphs. WM_MOUSEMOVE
 * arrives on every pixel of pointer travel, so a move must not pay for strings
 * it will not draw. Everything that affects GEOMETRY is copied faithfully --
 * that is what makes this layout identical to the painter's. */
static void chrome_layout_for_input(app* a, const spdf_win_input* in, SpdfWinChromeModel* model,
                                    SpdfWinChromeLayout* layout) {
    memset(model, 0, sizeof(*model));
    model->dark = (a->render_flags & SPDF_RENDER_DARK_THEME) != 0;
    model->show_sidebar = a->show_sidebar;
    model->show_minimap = a->show_minimap;
    model->sidebar_w = a->sidebar_w;
    model->minimap_w = a->minimap_w;
    model->hot_tab = a->hot_tab;
    model->hot_close = a->hot_close;
    model->tab_count = a->tabs ? spdf_win_tabs_count(a->tabs) : 0;
    model->selected_tab = a->tabs ? spdf_win_tabs_selected_index(a->tabs) : -1;
    spdf_win_chrome_layout(model, in->view_px_w, in->view_px_h, in->dpi_scale, layout);
}

/* Zoom about the CANVAS's centre, by the same factors the `+`/`-` keys use.
 *
 * One function for the keys and for the toolbar's zoom pill, because two copies
 * of "1.25" and "0.8" is two chances for a zoom-in that a zoom-out cannot undo.
 * The two are exact reciprocals (1.25 * 0.8 == 1.0), which is why they are the
 * pair rather than 1.25 and 1/1.25. */
static int chrome_zoom_step(app* a, const SpdfWinChromeLayout* l, int zoom_in) {
    if (!a->canvas) return 0;
    spdf_win_canvas_zoom_at(a->canvas, zoom_in ? 1.25f : 0.8f, l->canvas.w * 0.5f, l->canvas.h * 0.5f);
    return 1;
}

/* Ctrl+wheel, anchored under the cursor.
 *
 * THE BUG THIS FUNCTION EXISTS TO NOT HAVE: spdf_win_canvas_zoom_at() takes a
 * VIEWPORT point, and the viewport is the canvas -- but WM_MOUSEWHEEL gives a
 * CLIENT point. The two were the same before the chrome existed, and the window
 * passed the client point straight through. With the sidebar open they are 245 px
 * apart, so the un-translated point would anchor the zoom a sidebar's width to
 * the left of the cursor and the document would visibly slide out from under the
 * pointer -- worse the further from the canvas's left edge you zoom.
 *
 * Clamped into the canvas, so a Ctrl+wheel with the pointer over the toolbar or a
 * side panel still zooms about the nearest point of the page rather than about a
 * negative coordinate. */
static int chrome_zoom_at_client(app* a, const spdf_win_input* in) {
    SpdfWinChromeModel model;
    SpdfWinChromeLayout l;
    float vx, vy;
    if (!a->canvas) return 0;
    chrome_layout_for_input(a, in, &model, &l);
    vx = spdf_win_chrome_input_canvas_x(&l, in->x);
    vy = spdf_win_chrome_input_canvas_y(&l, in->y);
    vx = spdf_win_chrome_max(0.0f, spdf_win_chrome_min(vx, l.canvas.w));
    vy = spdf_win_chrome_max(0.0f, spdf_win_chrome_min(vy, l.canvas.h));
    spdf_win_canvas_zoom_at(a->canvas, in->factor, vx, vy);
    return 1;
}

/* The page pill. macOS's chevrons move the READING POSITION by one page, so this
 * is scroll_to_page and not a scroll by a viewport: at fit-page they coincide, at
 * fit-width on a tall page they do not, and "next page" must mean the next page. */
static int chrome_step_page(app* a, int delta) {
    int page;
    if (!a->canvas) return 0;
    page = spdf_win_canvas_current_page(a->canvas) + delta;
    if (page < 0 || page >= spdf_win_canvas_page_count(a->canvas)) return 0;
    return spdf_win_canvas_scroll_to_page(a->canvas, page);
}

/* The fit popup, WITHOUT a popup.
 *
 * macOS opens an NSPopUpButton with four items; a real Win32 menu is a separate
 * piece of work (TrackPopupMenu, its own message loop, keyboard navigation), and
 * a control that looks live and does nothing is worse than one that cycles. So a
 * click advances through the three modes the Windows canvas actually has, in the
 * popup's own order (:3006-3011) minus Fit Height, which spdf_win_canvas.h does
 * not offer. A custom zoom re-enters the cycle at Fit Width, which is where
 * macOS's own selectItem lands a custom zoom (:10504-10505). */
static int chrome_cycle_fit(app* a) {
    spdf_win_zoom_mode next;
    if (!a->canvas) return 0;
    switch (spdf_win_canvas_zoom_mode(a->canvas)) {
        case SPDF_WIN_ZOOM_FIT_WIDTH: next = SPDF_WIN_ZOOM_FIT_PAGE; break;
        case SPDF_WIN_ZOOM_FIT_PAGE: next = SPDF_WIN_ZOOM_ACTUAL; break;
        default: next = SPDF_WIN_ZOOM_FIT_WIDTH; break;
    }
    spdf_win_canvas_set_zoom_mode(a->canvas, next);
    return 1;
}

/* The reading-theme button. The canvas takes its render flags at construction
 * and has no setter, so the theme is changed by rebuilding it over the same
 * document -- which is exactly what a tab switch already does, so the path is
 * proven rather than new. The reader's PAGE survives (remember() writes it into
 * the tab's view state and show() restores it); the exact scroll offset within
 * that page does not, because spdf_win_tabs_app_show only replays the page.
 *
 * The window frame follows, or `--dark`'s own fix -- a light caption around a
 * #121212 canvas -- comes straight back the first time anyone presses this. */
static int chrome_toggle_theme(app* a) {
    if (!a->canvas) return 0;
    /* Both bits together, as the --dark flag sets them together: dark theme with
     * images left in their original colours (SPDF_RENDER_PRESERVE_IMAGES), which
     * is what makes a scanned page readable rather than inverted. */
    a->render_flags ^= (unsigned)(SPDF_RENDER_DARK_THEME | SPDF_RENDER_PRESERVE_IMAGES);
    spdf_win_tabs_app_remember(a->tabs, a->canvas);
    if (a->window) spdf_win_window_set_dark_frame(a->window, (a->render_flags & SPDF_RENDER_DARK_THEME) != 0);
    return show_selected_tab(a);
}

/* Close a tab from the strip. prefer_most_recent_active is 0, matching
 * ShenzhenPDFMac.mm:9115 -- the close box and Ctrl+W both ask for the
 * DETERMINISTIC ADJACENT survivor, and only detaching a tab into its own window
 * asks for the most recently active one (:9300). Getting that argument backwards
 * would make the close box feel like a different app from Ctrl+W. */
static int chrome_close_tab(app* a, int index) {
    if (!a->tabs || index < 0) return 0;
    if (index == spdf_win_tabs_selected_index(a->tabs)) spdf_win_tabs_app_remember(a->tabs, a->canvas);
    spdf_win_tabs_close(a->tabs, index, 0);
    if (spdf_win_tabs_count(a->tabs) == 0) {
        PostQuitMessage(0);
        return 1;
    }
    return show_selected_tab(a);
}

static int chrome_select_tab(app* a, int index) {
    if (!a->tabs || index < 0 || index == spdf_win_tabs_selected_index(a->tabs)) return 0;
    spdf_win_tabs_app_remember(a->tabs, a->canvas);
    spdf_win_tabs_select_deferred(a->tabs, index);
    return show_selected_tab(a);
}

/* Do it. `l` is the layout the hit was computed against, so a handler that needs
 * geometry -- the zoom pill's anchor, a divider's clamp -- uses the same rects
 * the click was tested against. */
static int chrome_perform(app* a, const SpdfWinChromeHit* hit, const SpdfWinChromeLayout* l) {
    switch (hit->action) {
        case SPDF_WIN_CA_SELECT_TAB: return chrome_select_tab(a, hit->index);
        case SPDF_WIN_CA_CLOSE_TAB: return chrome_close_tab(a, hit->index);
        case SPDF_WIN_CA_PREV_PAGE: return chrome_step_page(a, -1);
        case SPDF_WIN_CA_NEXT_PAGE: return chrome_step_page(a, 1);
        case SPDF_WIN_CA_ZOOM_IN: return chrome_zoom_step(a, l, 1);
        case SPDF_WIN_CA_ZOOM_OUT: return chrome_zoom_step(a, l, 0);
        case SPDF_WIN_CA_CYCLE_FIT: return chrome_cycle_fit(a);
        case SPDF_WIN_CA_TOGGLE_THEME: return chrome_toggle_theme(a);
        case SPDF_WIN_CA_TOGGLE_SIDEBAR: a->show_sidebar = !a->show_sidebar; return 1;
        case SPDF_WIN_CA_TOGGLE_MINIMAP: a->show_minimap = !a->show_minimap; return 1;
        /* A divider press changes nothing by itself; the WIDTH follows the
         * pointer on the moves that come after, so this only arms the drag. */
        case SPDF_WIN_CA_DRAG_SIDEBAR:
        case SPDF_WIN_CA_DRAG_MINIMAP: return 0;
        /* The strip's `+` and `…`. Neither has anywhere to go yet: opening a
         * document needs a file dialog and the overflow needs a menu, and both
         * are their own work. Returning 0 leaves them inert rather than
         * pretending -- and, critically, does NOT fall through to the canvas, so
         * a press on either cannot pan the document. */
        case SPDF_WIN_CA_NEW_TAB:
        case SPDF_WIN_CA_TAB_OVERFLOW:
        default: return 0;
    }
}

/* One mouse event, routed. Returns non-zero when the view changed.
 *
 * THE ORDER HERE IS THE POINT: everything is decided by
 * spdf_win_chrome_input_route() first, and the document's own pan is reached
 * only through SPDF_WIN_CA_CANVAS. That is what makes a press on the toolbar not
 * pan the page -- the failure this whole change was most likely to introduce. */
static int chrome_mouse(app* a, spdf_win_input* in) {
    SpdfWinChromeModel model;
    SpdfWinChromeLayout l;
    SpdfWinChromeHit hit;

    chrome_layout_for_input(a, in, &model, &l);
    spdf_win_chrome_input_route(&l, &model, in->x, in->y, in->button, &hit);

    if (in->kind == SPDF_WIN_INPUT_CURSOR) {
        /* While a drag is running the cursor belongs to the DRAG, not to
         * wherever the pointer has got to: a divider drag that outran its
         * divider must keep the resize cursor, and a pan must keep IDC_SIZEALL
         * even as the page moves out from under the pointer. */
        if (a->drag == SPDF_WIN_CA_CANVAS) in->cursor = SPDF_WIN_CC_SIZEALL;
        else if (a->drag != SPDF_WIN_CA_NONE) in->cursor = SPDF_WIN_CC_SIZEWE;
        else in->cursor = hit.cursor;
        return 0; /* a cursor query must never cost a repaint */
    }

    if (in->kind == SPDF_WIN_INPUT_MOUSE_UP) {
        a->drag = SPDF_WIN_CA_NONE;
        return 0;
    }

    if (in->kind == SPDF_WIN_INPUT_MOUSE_DOWN) {
        a->drag = hit.action == SPDF_WIN_CA_CANVAS || hit.action == SPDF_WIN_CA_DRAG_SIDEBAR ||
                          hit.action == SPDF_WIN_CA_DRAG_MINIMAP
                      ? hit.action
                      : SPDF_WIN_CA_NONE;
        a->drag_last_x = in->x;
        a->drag_last_y = in->y;
        return chrome_perform(a, &hit, &l);
    }

    /* --- MOUSE_MOVE ----------------------------------------------------- */
    switch (a->drag) {
        case SPDF_WIN_CA_CANVAS: {
            /* Dragging the paper down scrolls the document up, so the scroll
             * delta is the negated cursor delta -- grab-and-pull, not
             * push-the-scrollbar. A DELTA, so it needs no origin translation;
             * only absolute points do. */
            float dx = a->drag_last_x - in->x;
            float dy = a->drag_last_y - in->y;
            a->drag_last_x = in->x;
            a->drag_last_y = in->y;
            return a->canvas ? spdf_win_canvas_scroll_by(a->canvas, dx, dy) : 0;
        }
        case SPDF_WIN_CA_DRAG_SIDEBAR:
            /* The clamp is macOS's own, transcribed in spdf_win_chrome.h, so a
             * width dragged here lands exactly where NSSplitView would put it. */
            a->sidebar_w = spdf_win_chrome_sidebar_drag_pt(&l, in->x, model.search_active);
            return 1;
        case SPDF_WIN_CA_DRAG_MINIMAP:
            a->minimap_w = spdf_win_chrome_minimap_drag_pt(&l, in->x);
            return 1;
        default: break;
    }

    /* No drag: this is hover. Only a CHANGE repaints, or the pointer would
     * invalidate the window on every pixel it crosses. */
    if (hit.hot_tab == a->hot_tab && hit.hot_close == a->hot_close) return 0;
    a->hot_tab = hit.hot_tab;
    a->hot_close = hit.hot_close;
    return 1;
}
