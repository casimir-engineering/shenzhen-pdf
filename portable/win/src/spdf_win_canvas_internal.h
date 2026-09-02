/* The canvas's private state, shared by exactly three translation units.
 *
 * It exists because spdf_win_canvas.cpp reached the repo's 500-line cap and the
 * rule is extraction over cap bumps (tools/file-size-limits.md). Every seam is
 * the honest one: spdf_win_canvas.cpp is geometry and composition -- what is
 * where, at what zoom -- spdf_win_canvas_prefetch.cpp is everything to do with
 * T5's worker pool, and spdf_win_canvas_selection.cpp is the pointer gesture
 * that turns those two into a text selection and a followed link. Nothing
 * outside those three files may include this header; spdf_win_canvas.h is the
 * public surface.
 */
#ifndef SPDF_WIN_CANVAS_INTERNAL_H
#define SPDF_WIN_CANVAS_INTERNAL_H

#include "spdf_win_canvas.h"
#include "spdf_win_layout.h"
#include "spdf_win_links.h"
#include "spdf_win_lru.h"
#include "spdf_win_render.h"
#include "spdf_win_selection.h"


#include <windows.h> /* Sleep, for the headless settle only */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

struct spdf_win_canvas {
    spdf_document* doc; /* borrowed */
    unsigned render_flags;
    int page_count;

    /* Page sizes in PDF points. Pages [0, measured) have been asked of the
     * core; the rest hold page 1's size as an estimate. Launching measures
     * exactly ONE page, because a 500-page document would otherwise pay 500
     * fz_load_page calls before the first pixel appears, and launch time is
     * the product's headline promise. The estimate only ever affects the
     * total scroll height below the viewport; everything at or above the
     * viewport is exact, because build_scene() measures forward until the
     * visible range stops moving. */
    SpdfWinPageSizePt* sizes;
    int measured;

    SpdfWinLayout layout;
    double zoom;
    spdf_win_zoom_mode mode;
    double scroll_x;
    double scroll_y;

    unsigned vp_w;
    unsigned vp_h;
    double dpi_scale;

    SpdfWinLru cache; /* SpdfWinLruKey -> spdf_bitmap*, owned */

    /* T5's worker pool, used for NEIGHBOUR PREFETCH ONLY. The visible page is
     * still rendered synchronously, deliberately: it means the canvas can
     * never hand back a blank frame, and it keeps the headless probe
     * deterministic -- a viewport PNG that depended on whether a worker had
     * finished would be a viewport PNG no comparison could trust. What the
     * pool buys is the page you are about to scroll onto being ready before
     * you get there, which is the whole difference between a strip that
     * scrolls and one that stutters at every page break.
     *
     * Every touch of `cache` therefore stays on one thread: requests are made
     * from build_scene, and results are adopted in spdf_win_render_drain(),
     * which runs on whichever thread calls it -- the same one. The LRU needs
     * no lock because it never sees a second thread. */
    spdf_win_render_service* service;
    int sync_renders; /* synchronous renders during the last build_scene */

    /* Scratch for build_scene's page list, grown and reused rather than
     * reallocated per frame: a malloc on every paint is a malloc on the scroll
     * hot path. */
    spdf_win_page_draw* draws;
    int draws_cap;
    int draws_count;

    wchar_t status[256];

    /* --- selection and links, all of it owned by spdf_win_canvas_selection.cpp
     *
     * Allocated LAZILY on the first pointer event, so a document nobody clicks
     * on costs two null pointers and no allocation -- the same rule the find
     * session states for a document nobody searches.
     *
     * They live on the CANVAS rather than beside the window because a selection
     * belongs to a document view: it survives a scroll, a zoom and a repaint,
     * it dies with the document, and it needs exactly the geometry this struct
     * already holds. Per-tab lifetime then comes for free, since a tab owns a
     * canvas. `doc` is the UI thread's handle, which is what makes the core
     * calls below legal on the UI thread (shenzhen_pdf_core.c:40-43). */
    spdf_win_selection* selection;
    spdf_win_links* links;
    /* Where the last press landed, in page space, so the release can resolve
     * the link it was over without re-hit-testing a pointer that has moved. */
    int press_page;
    float press_page_x;
    float press_page_y;
    /* Owned by the canvas and freed before it is overwritten: spdf_link_target
     * carries a malloc'd uri for external links. */
    spdf_link_target nav;
    int nav_valid;
};

/* spdf_win_canvas_prefetch.cpp */
void spdf_win_canvas_prefetch(spdf_win_canvas* canvas, int page);

/* spdf_win_canvas_selection.cpp. Called from spdf_win_canvas_destroy() while
 * the canvas is still whole, for the same reason the render service is torn
 * down there rather than by whoever created it. */
void spdf_win_canvas_selection_teardown(spdf_win_canvas* canvas);

#endif /* SPDF_WIN_CANVAS_INTERNAL_H */
