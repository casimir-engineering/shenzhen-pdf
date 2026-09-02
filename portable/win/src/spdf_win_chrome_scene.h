#pragma once

/* The PAINT-TIME half of the Windows frontend's app glue: what the chrome model
 * is filled from, and the one callback spdf_win_window.h calls before every
 * frame.
 *
 * SPLIT OUT OF spdf_win_chrome_actions.h, which is where all of this used to
 * live, when the scroller work pushed that file past the 500-line cap. The seam
 * is a real one rather than a convenience: everything here runs on the PAINT
 * path and knows only how to describe the document to the chrome, while what is
 * left next door runs on the INPUT path and knows how to change the document.
 * The two touch at exactly two functions -- chrome_scroll_into(), which the
 * router needs because the scroller fractions are geometry, and
 * chrome_fit_for_zoom_mode(), which the fit cycle needs -- and both are here,
 * because a value's definition belongs with the code that produces it.
 *
 * Header-only and included from spdf_win_main.cpp AFTER `struct app`, exactly
 * like spdf_win_tabs_app.h, spdf_win_headless_viewport.h and
 * spdf_win_chrome_actions.h beside it, and BEFORE spdf_win_chrome_actions.h,
 * which calls the two functions named above. Not part of the port's public
 * surface.
 */

/* For spdf_win_chrome_content_set_document(): scene_for_window tells the panels
 * which document is selected. Included here rather than relying on it arriving
 * through spdf_win_main.cpp's include order, which is what left this header
 * depending on a declaration it never asked for. */
#include "spdf_win_chrome_content.h"
#include "spdf_win_chrome_find.h" /* spdf_win_find_apply_overlays */

/* The canvas's zoom mode in the vocabulary the toolbar speaks.
 *
 * Two enums rather than one because spdf_win_chrome.h must not include
 * spdf_win_canvas.h -- the chrome is drawn in tests that have no canvas, no
 * document and no MuPDF -- so this is the seam, and it is four lines now that
 * the canvas has the Fit Height mode macOS always had
 * (SPDF_WIN_ZOOM_FIT_HEIGHT). */
static int chrome_fit_for_zoom_mode(spdf_win_zoom_mode mode) {
    switch (mode) {
        case SPDF_WIN_ZOOM_FIT_WIDTH: return SPDF_WIN_CHROME_FIT_WIDTH;
        case SPDF_WIN_ZOOM_FIT_HEIGHT: return SPDF_WIN_CHROME_FIT_HEIGHT;
        case SPDF_WIN_ZOOM_FIT_PAGE: return SPDF_WIN_CHROME_FIT_PAGE;
        case SPDF_WIN_ZOOM_ACTUAL: return SPDF_WIN_CHROME_FIT_ACTUAL;
        default: return SPDF_WIN_CHROME_FIT_CUSTOM;
    }
}

/* The scroller fractions, straight from the canvas into the model the painters
 * and the router read. Kept out of chrome_inputs_for() below because
 * SpdfWinChromeModelInputs belongs to spdf_win_chrome_model.h, whose build
 * function would have to learn about them; assigning after the build is a
 * two-line seam instead, and the model documents these fields as the window
 * layer's to fill. */
static void chrome_scroll_into(app* a, SpdfWinChromeModel* m) {
    spdf_win_canvas_scroll scroll;
    spdf_win_canvas_scroll_state(a->canvas, &scroll);
    m->v_pos = scroll.v_pos;
    m->v_visible = scroll.v_visible;
    m->h_pos = scroll.h_pos;
    m->h_visible = scroll.h_visible;
    m->h_scrollable = scroll.h_scrollable;
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
    int h_scrollable_this_frame;
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
    chrome_scroll_into(a, &a->chrome);
    scene->chrome = &a->chrome;
    spdf_win_chrome_layout(&a->chrome, client_w, client_h, scene->dpi_scale, &chrome_layout);
    /* WHETHER THERE IS A HORIZONTAL TROUGH IS DECIDED ONCE PER FRAME, HERE.
     *
     * `h_scrollable` is the one model field spdf_win_chrome_layout() reads, and
     * the trough it adds comes out of the canvas's HEIGHT. Under fit-page or
     * fit-height that height feeds back into the zoom, which feeds back into the
     * content width, which feeds back into h_scrollable -- so re-asking the
     * canvas after the viewport has been set could return a different answer
     * from the one this frame's canvas rect was computed with, and the painter
     * would draw a trough into space the pages were told they could have.
     * Latching the first answer for the frame makes the layout and the viewport
     * agree exactly; a trough that has just become necessary appears on the next
     * paint, which is what a scrollbar does anyway. */
    h_scrollable_this_frame = a->chrome.h_scrollable;

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
    chrome_scroll_into(a, &a->chrome);
    a->chrome.h_scrollable = h_scrollable_this_frame;

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

    /* Search highlights, AFTER build_scene because that is what fills
     * scene->pages, which is what the overlay rects are derived from. Reads only
     * pages/page_count/target_px_h/dpi_scale and writes only overlays; a no-op
     * with no live query, and it does not even create a session then.
     *
     * Note it OVERWRITES scene->overlays rather than appending -- documented at
     * its declaration in spdf_win_chrome_find.h. A future selection track adding
     * a second producer has to resolve that; today there is one. */
    if (spdf_win_canvas_build_scene(a->canvas, scene)) {
        spdf_win_find_apply_overlays(scene);
        return 1;
    }
    spdf_win_find_apply_overlays(scene);
    scene->message = a->status[0] ? a->status : NULL;
    return 1;
}
