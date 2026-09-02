/* The continuous scrolling canvas. See spdf_win_canvas.h for the layering.
 *
 * NOTHING HERE IS STUBBED, which is worth saying because an earlier draft of
 * this file was. All three seams are the real thing:
 *
 *  - GEOMETRY IS REAL. Every slot rect, fit zoom, zoom anchor and horizontal
 *    clamp below comes from T3's spdf_win_layout.h, which is the de-glib'd
 *    port of the shipping GTK4 header. Nothing here re-derives layout maths,
 *    which is the point: the provenance comments in that header record which
 *    shipped bug each formulation fixes.
 *  - THE CACHE IS REAL. T3's spdf_win_lru holds decoded pages under the 96 MB
 *    budget with the same LRU policy the other two frontends use.
 *  - THE WORKER POOL IS REAL. T5's spdf_win_render service prefetches the
 *    pages either side of the viewport off-thread.
 *
 * The one deliberate asymmetry: the pages actually ON SCREEN are rendered
 * SYNCHRONOUSLY, in ensure_page(), even though a worker pool is right there.
 * Two reasons, and both are worth more than the symmetry:
 *
 *   - the canvas can then never hand back a frame with a hole in it, so the
 *     placeholder path in the compose layer is a safety net rather than
 *     something a reader sees on every page break;
 *   - and the headless viewport probe stays deterministic. A --render-window-png
 *     whose pixels depended on whether a worker had finished yet would be a PNG
 *     no comparison against macOS could trust, and that comparison is the only
 *     evidence this port is correct.
 *
 * What the pool buys is the page you are ABOUT to reach being ready before you
 * get there, which is the whole difference between a strip that scrolls and one
 * that stutters at every boundary. Moving the visible page onto it too is a
 * later change, and wants a placeholder that does not flash.
 */
#include "spdf_win_canvas_internal.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

/* --- the cached value ---------------------------------------------------- */

static void destroy_bitmap(void* value) {
    spdf_bitmap* bitmap = (spdf_bitmap*)value;
    if (!bitmap) return;
    spdf_free_bitmap(bitmap);
    free(bitmap);
}


/* --- measurement --------------------------------------------------------- */

/* Measures pages up to and including `through`. Returns non-zero when at least
 * one new page was measured, i.e. when the layout is now stale. */
static int ensure_measured(spdf_win_canvas* canvas, int through) {
    char err[128];

    if (through >= canvas->page_count) through = canvas->page_count - 1;
    if (through < canvas->measured) return 0;
    for (int i = canvas->measured; i <= through; ++i) {
        float w = 0.0f;
        float h = 0.0f;
        if (spdf_page_size(canvas->doc, i, &w, &h, err, sizeof(err)) && w > 0.0f && h > 0.0f) {
            canvas->sizes[i].width = w;
            canvas->sizes[i].height = h;
        }
        /* On failure the page keeps the estimate rather than collapsing to
         * zero: a damaged page should leave a gap in the strip, not shift
         * every page after it. */
    }
    canvas->measured = through + 1;
    return 1;
}

/* --- layout -------------------------------------------------------------- */

static int current_page_of(const spdf_win_canvas* canvas) {
    int page = spdf_win_layout_page_nearest_center(&canvas->layout, canvas->scroll_y + (double)canvas->vp_h * 0.5);
    return page < 0 ? 0 : page;
}

static void clamp_scroll(spdf_win_canvas* canvas) {
    SpdfWinHScrollClamp h;
    double max_y = spdf_win_max_d(0.0, canvas->layout.canvas_h - (double)canvas->vp_h);

    canvas->scroll_y = spdf_win_clamp_d(canvas->scroll_y, 0.0, max_y);
    h = spdf_win_hscroll_clamp(&canvas->layout, current_page_of(canvas), (double)canvas->vp_w, canvas->scroll_x);
    canvas->scroll_x = h.value;
}

/* Re-derives the zoom under a fit mode and rebuilds every slot rect. The fit
 * modes key on the CURRENT page, so a mixed-size document fits the page you
 * are looking at rather than the widest sheet in the file. */
/* Everything already rendered is now the wrong size. Bumping the generation
 * cancels in-flight prefetches and makes their results arrive as SUPERSEDED
 * rather than being adopted -- without it, a worker that started before a zoom
 * change would file a stale bitmap under a key nothing will ever ask for, and
 * the LRU would carry it until eviction. */
static void note_zoom_changed(spdf_win_canvas* canvas, double before) {
    if (canvas->service && fabs(canvas->zoom - before) > 1e-9) spdf_win_render_service_bump_generation(canvas->service);
}

static void relayout(spdf_win_canvas* canvas) {
    int page = current_page_of(canvas);
    double before = canvas->zoom;
    double fit = 0.0;

    if (page >= canvas->page_count) page = canvas->page_count - 1;
    if (page < 0) page = 0;
    if (canvas->page_count > 0) {
        const SpdfWinPageSizePt* size = &canvas->sizes[page];
        if (canvas->mode == SPDF_WIN_ZOOM_FIT_WIDTH)
            fit = spdf_win_fit_width_zoom(size->width, (double)canvas->vp_w);
        else if (canvas->mode == SPDF_WIN_ZOOM_FIT_PAGE)
            fit = spdf_win_fit_page_zoom(size->width, size->height, (double)canvas->vp_w, (double)canvas->vp_h);
        else if (canvas->mode == SPDF_WIN_ZOOM_FIT_HEIGHT)
            fit = spdf_win_fit_height_zoom(size->height, (double)canvas->vp_h);
        else if (canvas->mode == SPDF_WIN_ZOOM_ACTUAL)
            fit = spdf_win_clamp_d(canvas->dpi_scale, SPDF_WIN_MIN_ZOOM, SPDF_WIN_MAX_ZOOM);
    }
    /* 0.0 is the fit helpers' "viewport too small to trust" answer; keeping
     * the current zoom then is what stops a window that has not been sized yet
     * from snapping to something absurd. */
    if (fit > 0.0) canvas->zoom = fit;
    note_zoom_changed(canvas, before);

    spdf_win_layout_compute(&canvas->layout, canvas->sizes, canvas->page_count, canvas->zoom, (double)canvas->vp_w,
                            SPDF_WIN_PAGE_MARGIN_H, SPDF_WIN_PAGE_MARGIN_V);
    clamp_scroll(canvas);
}

/* --- lifecycle ----------------------------------------------------------- */

spdf_win_canvas* spdf_win_canvas_create(spdf_document* doc, const char* path, unsigned render_flags, char* err,
                                        size_t err_len) {
    spdf_win_canvas* canvas;
    float w = 612.0f;
    float h = 792.0f;

    if (err && err_len) err[0] = '\0';
    if (!doc) return NULL;

    canvas = (spdf_win_canvas*)calloc(1, sizeof(*canvas));
    if (!canvas) return NULL;
    canvas->doc = doc;
    canvas->render_flags = render_flags;
    canvas->page_count = spdf_page_count(doc);
    canvas->zoom = 1.0;
    canvas->mode = SPDF_WIN_ZOOM_FIT_WIDTH;
    canvas->dpi_scale = 1.0;
    canvas->vp_w = 1;
    canvas->vp_h = 1;
    if (canvas->page_count <= 0) {
        if (err && err_len) _snprintf_s(err, err_len, _TRUNCATE, "This document has no pages.");
        free(canvas);
        return NULL;
    }

    canvas->sizes = (SpdfWinPageSizePt*)calloc((size_t)canvas->page_count, sizeof(SpdfWinPageSizePt));
    if (!canvas->sizes) {
        free(canvas);
        return NULL;
    }
    if (!spdf_page_size(doc, 0, &w, &h, err, err_len) || w <= 0.0f || h <= 0.0f) {
        free(canvas->sizes);
        free(canvas);
        return NULL;
    }
    for (int i = 0; i < canvas->page_count; ++i) {
        canvas->sizes[i].width = w;
        canvas->sizes[i].height = h;
    }
    canvas->measured = 1;

    spdf_win_lru_init(&canvas->cache, SPDF_WIN_MAX_RENDER_SURFACE_BYTES, destroy_bitmap);
    /* No path means no prefetch -- the workers open the file themselves, one
     * document per thread, because the core's contract is one spdf_document
     * per thread and handing them ours would break it. Not having a service is
     * a supported state, not a failure: everything still renders, just on the
     * calling thread. Starting it costs nothing here; T5 spawns threads on the
     * first request, not on construction, so launch pays for no worker it does
     * not use. */
    /* No notify hook on purpose: this canvas drains as it builds a frame,
     * so a PostMessage per completion would only ask for a repaint the next
     * paint was going to do anyway. A prefetched page is by definition not on
     * screen yet, so nothing needs redrawing when it lands. */
    canvas->service = spdf_win_render_service_new(path, NULL, SPDF_WIN_MAX_RENDER_SURFACE_BYTES, NULL, NULL);
    return canvas;
}

void spdf_win_canvas_destroy(spdf_win_canvas* canvas) {
    if (!canvas) return;
    /* The service FIRST, and while the canvas is still whole: freeing it
     * cancels everything in flight and then delivers each outstanding request
     * SPDF_WIN_RENDER_SHUTDOWN on this thread, and those callbacks touch this
     * canvas's cache. Tearing the cache down first would hand them freed
     * memory. */
    spdf_win_render_service_free(canvas->service);
    canvas->service = NULL;
    spdf_win_canvas_selection_teardown(canvas);
    spdf_win_lru_deinit(&canvas->cache);
    spdf_win_layout_clear(&canvas->layout);
    free(canvas->draws);
    free(canvas->sizes);
    free(canvas);
}

/* --- viewport, zoom, scroll ---------------------------------------------- */

void spdf_win_canvas_set_viewport(spdf_win_canvas* canvas, unsigned px_w, unsigned px_h, float dpi_scale) {
    if (!canvas) return;
    if (px_w == 0) px_w = 1;
    if (px_h == 0) px_h = 1;
    if (dpi_scale <= 0.0f) dpi_scale = 1.0f;
    if (canvas->vp_w == px_w && canvas->vp_h == px_h && canvas->dpi_scale == (double)dpi_scale) return;
    canvas->vp_w = px_w;
    canvas->vp_h = px_h;
    canvas->dpi_scale = dpi_scale;
    relayout(canvas);
}

void spdf_win_canvas_set_zoom_mode(spdf_win_canvas* canvas, spdf_win_zoom_mode mode) {
    if (!canvas || canvas->mode == mode) return;
    canvas->mode = mode;
    relayout(canvas);
}

spdf_win_zoom_mode spdf_win_canvas_zoom_mode(const spdf_win_canvas* canvas) {
    return canvas ? canvas->mode : SPDF_WIN_ZOOM_FREE;
}

float spdf_win_canvas_zoom(const spdf_win_canvas* canvas) { return canvas ? (float)canvas->zoom : 1.0f; }

void spdf_win_canvas_set_zoom_at(spdf_win_canvas* canvas, float zoom, float vx, float vy) {
    SpdfWinZoomAnchor anchor;
    double target;

    if (!canvas) return;
    target = spdf_win_clamp_d((double)zoom, SPDF_WIN_MIN_ZOOM, SPDF_WIN_MAX_ZOOM);
    if (fabs(target - canvas->zoom) < 1e-9) return;

    /* Captured BEFORE the relayout, in document space (page + PDF point), so
     * the point survives a layout whose slot rects all moved. */
    spdf_win_zoom_anchor_capture(&anchor, &canvas->layout, canvas->sizes, canvas->zoom, (double)vx, (double)vy,
                                 canvas->scroll_x, canvas->scroll_y);
    double before = canvas->zoom;
    canvas->zoom = target;
    canvas->mode = SPDF_WIN_ZOOM_FREE;
    note_zoom_changed(canvas, before);
    spdf_win_layout_compute(&canvas->layout, canvas->sizes, canvas->page_count, canvas->zoom, (double)canvas->vp_w,
                            SPDF_WIN_PAGE_MARGIN_H, SPDF_WIN_PAGE_MARGIN_V);
    spdf_win_zoom_anchor_apply(&anchor, &canvas->layout, canvas->zoom, (double)canvas->vp_w, (double)canvas->vp_h,
                               &canvas->scroll_x, &canvas->scroll_y);
    clamp_scroll(canvas);
}

void spdf_win_canvas_zoom_at(spdf_win_canvas* canvas, float factor, float vx, float vy) {
    if (!canvas || !(factor > 0.0f)) return;
    spdf_win_canvas_set_zoom_at(canvas, (float)(canvas->zoom * (double)factor), vx, vy);
}

int spdf_win_canvas_scroll_to(spdf_win_canvas* canvas, float x, float y) {
    double before_x;
    double before_y;

    if (!canvas) return 0;
    before_x = canvas->scroll_x;
    before_y = canvas->scroll_y;
    canvas->scroll_x = (double)x;
    canvas->scroll_y = (double)y;
    clamp_scroll(canvas);
    return fabs(canvas->scroll_x - before_x) > 0.01 || fabs(canvas->scroll_y - before_y) > 0.01;
}

int spdf_win_canvas_scroll_by(spdf_win_canvas* canvas, float dx, float dy) {
    if (!canvas) return 0;
    return spdf_win_canvas_scroll_to(canvas, (float)(canvas->scroll_x + (double)dx),
                                     (float)(canvas->scroll_y + (double)dy));
}

int spdf_win_canvas_scroll_to_page(spdf_win_canvas* canvas, int page_index) {
    if (!canvas || page_index < 0 || page_index >= canvas->page_count) return 0;
    if (ensure_measured(canvas, page_index)) relayout(canvas);
    if (page_index >= canvas->layout.count) return 0;
    return spdf_win_canvas_scroll_to(canvas, (float)canvas->scroll_x,
                                     (float)(canvas->layout.rects[page_index].y - SPDF_WIN_PAGE_MARGIN_V));
}

/* One axis of spdf_win_canvas_scroll_state(). `visible` saturates at 1 when the
 * viewport is at least as big as the content, which is the case the scroller
 * draws as a full-length thumb; `pos` is 0 there rather than 0/0. */
static void scroll_fractions(double content, double viewport, double offset, float* pos, float* visible) {
    double travel;
    if (!(content > 0.0) || !(viewport > 0.0) || viewport >= content) {
        *pos = 0.0f;
        *visible = 1.0f;
        return;
    }
    *visible = (float)(viewport / content);
    travel = content - viewport;
    *pos = (float)spdf_win_clamp_d(offset / travel, 0.0, 1.0);
}

/* THE HORIZONTAL AXIS IS THE CURRENT PAGE'S, NOT THE CANVAS'S, and the reason
 * is spdf_win_hscroll_clamp's policy rather than a preference.
 *
 * The canvas is always at least `widest page + 2 * 22 pt` wide, so at FIT WIDTH
 * -- where spdf_win_fit_width_zoom makes the page exactly the viewport's width
 * -- the content is permanently 44 px wider than the viewport. By the clamp's
 * own `scrollable` flag that is horizontally scrollable, but the clamp then PINS
 * a page that fits the viewport centred, so the offset never moves: a trough
 * drawn from that flag would be present on every ordinary document with a thumb
 * that cannot be dragged. What the reader can actually pan is the CURRENT page,
 * when that page is wider than the viewport, and this returns exactly that
 * range.
 *
 * NOTE the distinction from spdf_win_layout.h:349-355, which warns that keying
 * scrollable on the current page was the June GTK defect. That warning is about
 * the canvas's WIDTH -- one wide sheet must not blow the viewport up and push
 * narrower pages off screen -- and the width here is still the canvas's,
 * untouched. This is only about whether there is anything to drag.
 *
 * Returns 0 when the current page fits, leaving the outputs alone. */
static int h_pan_range(const spdf_win_canvas* canvas, double* out_min, double* out_travel, double* out_page_w) {
    const SpdfWinRect* r;
    int page = current_page_of(canvas);
    if (canvas->layout.count <= 0 || page < 0 || page >= canvas->layout.count) return 0;
    r = &canvas->layout.rects[page];
    if (r->w <= (double)canvas->vp_w + 0.5) return 0;
    *out_min = r->x;
    *out_travel = r->w - (double)canvas->vp_w;
    *out_page_w = r->w;
    return 1;
}

void spdf_win_canvas_scroll_state(const spdf_win_canvas* canvas, spdf_win_canvas_scroll* out) {
    double min_x = 0.0, travel = 0.0, page_w = 0.0;
    if (!out) return;
    out->v_pos = 0.0f;
    out->v_visible = 1.0f;
    out->h_pos = 0.0f;
    out->h_visible = 1.0f;
    out->h_scrollable = 0;
    if (!canvas) return;
    scroll_fractions(canvas->layout.canvas_h, (double)canvas->vp_h, canvas->scroll_y, &out->v_pos, &out->v_visible);
    if (!h_pan_range(canvas, &min_x, &travel, &page_w)) return;
    out->h_scrollable = 1;
    scroll_fractions(page_w, (double)canvas->vp_w, canvas->scroll_x - min_x, &out->h_pos, &out->h_visible);
}

int spdf_win_canvas_scroll_to_fraction(spdf_win_canvas* canvas, int vertical, float pos) {
    double min_x = 0.0, travel = 0.0, page_w = 0.0;
    if (!canvas) return 0;
    if (!(pos >= 0.0f)) pos = 0.0f; /* also catches NaN */
    if (pos > 1.0f) pos = 1.0f;
    if (vertical) {
        travel = canvas->layout.canvas_h - (double)canvas->vp_h;
        if (!(travel > 0.0)) return 0;
        return spdf_win_canvas_scroll_to(canvas, (float)canvas->scroll_x, (float)((double)pos * travel));
    }
    /* The same range spdf_win_canvas_scroll_state() reported the thumb against,
     * so a thumb dragged to a fraction lands where that fraction was drawn. */
    if (!h_pan_range(canvas, &min_x, &travel, &page_w)) return 0;
    return spdf_win_canvas_scroll_to(canvas, (float)(min_x + (double)pos * travel), (float)canvas->scroll_y);
}

float spdf_win_canvas_scroll_x(const spdf_win_canvas* canvas) { return canvas ? (float)canvas->scroll_x : 0.0f; }
float spdf_win_canvas_scroll_y(const spdf_win_canvas* canvas) { return canvas ? (float)canvas->scroll_y : 0.0f; }
float spdf_win_canvas_content_w(const spdf_win_canvas* canvas) { return canvas ? (float)canvas->layout.canvas_w : 0.0f; }
float spdf_win_canvas_content_h(const spdf_win_canvas* canvas) { return canvas ? (float)canvas->layout.canvas_h : 0.0f; }
int spdf_win_canvas_page_count(const spdf_win_canvas* canvas) { return canvas ? canvas->page_count : 0; }
int spdf_win_canvas_current_page(const spdf_win_canvas* canvas) { return canvas ? current_page_of(canvas) : 0; }
size_t spdf_win_canvas_cache_bytes(const spdf_win_canvas* canvas) {
    return canvas ? spdf_win_lru_bytes(&canvas->cache) : 0;
}

/* --- rendering ----------------------------------------------------------- */

/* THE T5 SEAM. Cache hit, or a synchronous render. See the file header.
 * The zoom is byte-capped before it reaches the core, so a 10900x7539 pt sheet
 * renders a smaller texture that the compose layer stretches back over its
 * full slot -- geometry never sees the cap, which is what keeps the zoom
 * anchor exact on giant pages. */
static const spdf_bitmap* ensure_page(spdf_win_canvas* canvas, int page) {
    SpdfWinLruKey key;
    const SpdfWinPageSizePt* size = &canvas->sizes[page];
    double render_zoom = spdf_win_capped_render_zoom(canvas->zoom, size->width, size->height);
    spdf_bitmap* bitmap;
    char err[256];

    key = spdf_win_lru_key(page, render_zoom, canvas->dpi_scale);
    bitmap = (spdf_bitmap*)spdf_win_lru_lookup(&canvas->cache, &key);
    if (bitmap) return bitmap;

    canvas->sync_renders++;
    bitmap = (spdf_bitmap*)calloc(1, sizeof(*bitmap));
    if (!bitmap) return NULL;
    if (!spdf_render_page_rgba_opts(canvas->doc, page, (float)render_zoom, canvas->render_flags, NULL, bitmap, err,
                                    sizeof(err))) {
        _snwprintf_s(canvas->status, _TRUNCATE, L"Could not render page %d: %hs", page + 1, err);
        free(bitmap);
        return NULL;
    }
    if (!spdf_win_lru_insert(&canvas->cache, &key, bitmap, spdf_win_lru_bitmap_bytes(bitmap->width, bitmap->height)))
        return NULL; /* insert destroyed it; a placeholder is drawn this frame */
    return bitmap;
}

int spdf_win_canvas_build_scene(spdf_win_canvas* canvas, spdf_win_scene* scene) {
    int first = 0;
    int last = 0;
    int visible = 0;

    if (!canvas || !scene) return 0;
    /* Adopt anything the pool finished since the last frame. Cheap and O(1)
     * per item -- adoption on the UI thread must never do O(n) work. */
    if (canvas->service) spdf_win_render_drain(canvas->service, -1);
    canvas->sync_renders = 0;
    if (canvas->layout.count != canvas->page_count) relayout(canvas);

    /* Measure forward until the visible range stops changing. Each round can
     * only extend `measured`, which is bounded by the page count, so this
     * terminates; in practice it runs twice -- once to find the range under
     * the estimate, once to confirm it under the real sizes. */
    for (int round = 0; round < 8; ++round) {
        double y0 = canvas->scroll_y;
        double y1 = y0 + (double)canvas->vp_h;
        visible = spdf_win_layout_visible_range(&canvas->layout, y0, y1, &first, &last);
        if (!visible) {
            first = last = current_page_of(canvas);
            visible = canvas->page_count > 0;
        }
        if (!ensure_measured(canvas, last + 1)) break;
        relayout(canvas);
    }

    if (last >= canvas->page_count) last = canvas->page_count - 1;
    if (first < 0) first = 0;

    if (last - first + 1 > canvas->draws_cap) {
        int want = last - first + 1;
        spdf_win_page_draw* grown = (spdf_win_page_draw*)realloc(canvas->draws, (size_t)want * sizeof(*grown));
        if (!grown) return 0;
        canvas->draws = grown;
        canvas->draws_cap = want;
    }

    canvas->draws_count = 0;
    for (int i = first; i <= last && visible; ++i) {
        const SpdfWinRect* rect = &canvas->layout.rects[i];
        spdf_win_page_draw* draw = &canvas->draws[canvas->draws_count++];
        draw->page_index = i;
        draw->bitmap = ensure_page(canvas, i);
        draw->dest_x = (float)(rect->x - canvas->scroll_x);
        draw->dest_y = (float)(rect->y - canvas->scroll_y);
        draw->dest_w = (float)rect->w;
        draw->dest_h = (float)rect->h;
    }

    /* The two pages the reader is most likely to reach next, off-thread. Both
     * directions, because scrolling back up is as common as scrolling down. */
    spdf_win_canvas_prefetch(canvas, last + 1);
    spdf_win_canvas_prefetch(canvas, first - 1);

    scene->page = NULL;
    scene->pages = canvas->draws;
    scene->page_count = canvas->draws_count;
    scene->fit = SPDF_WIN_FIT_CANVAS;
    scene->target_px_w = canvas->vp_w;
    scene->target_px_h = canvas->vp_h;
    scene->dpi_scale = (float)canvas->dpi_scale;
    scene->dark = (canvas->render_flags & SPDF_RENDER_DARK_THEME) != 0;
    scene->message = canvas->draws_count > 0 ? NULL : (canvas->status[0] ? canvas->status : NULL);
    return canvas->draws_count > 0;
}
