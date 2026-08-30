/* The continuous scrolling canvas. See spdf_win_canvas.h for the layering.
 *
 * WHAT IS REAL AND WHAT IS STUBBED, because it matters to whoever reads this
 * next:
 *
 *  - GEOMETRY IS REAL. Every slot rect, fit zoom, zoom anchor and horizontal
 *    clamp below comes from T3's spdf_win_layout.h, which is the de-glib'd
 *    port of the shipping GTK4 header. Nothing here re-derives layout maths,
 *    which is the point: the provenance comments in that header record which
 *    shipped bug each formulation fixes.
 *  - THE CACHE IS REAL. T3's spdf_win_lru holds decoded pages under the 96 MB
 *    budget with the same LRU policy the other two frontends use.
 *  - RENDERING IS SYNCHRONOUS, and that is the one stub. T5's
 *    spdf_win_render.h has landed but spdf_win_render.c has not, so there is
 *    nothing to link against yet. ensure_page(): a cache miss renders inline
 *    on the calling thread. The seam is one function wide -- when T5's
 *    implementation lands, ensure_page() posts a request and returns NULL
 *    (drawing a paper placeholder, which this file already handles for exactly
 *    that reason) and a drain callback inserts into the same cache under the
 *    same key. Nothing else in the frontend changes. There is deliberately no
 *    neighbour prefetch here: prefetching on the UI thread would trade the
 *    stutter it is supposed to remove for a bigger one, and it is T5's to add.
 */
#include "spdf_win_canvas.h"

#include "spdf_win_layout.h"
#include "spdf_win_lru.h"

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

    spdf_win_page_draw* draws;
    int draws_cap;
    int draws_count;

    wchar_t status[256];
};

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
static void relayout(spdf_win_canvas* canvas) {
    int page = current_page_of(canvas);
    double fit = 0.0;

    if (page >= canvas->page_count) page = canvas->page_count - 1;
    if (page < 0) page = 0;
    if (canvas->page_count > 0) {
        const SpdfWinPageSizePt* size = &canvas->sizes[page];
        if (canvas->mode == SPDF_WIN_ZOOM_FIT_WIDTH)
            fit = spdf_win_fit_width_zoom(size->width, (double)canvas->vp_w);
        else if (canvas->mode == SPDF_WIN_ZOOM_FIT_PAGE)
            fit = spdf_win_fit_page_zoom(size->width, size->height, (double)canvas->vp_w, (double)canvas->vp_h);
        else if (canvas->mode == SPDF_WIN_ZOOM_ACTUAL)
            fit = spdf_win_clamp_d(canvas->dpi_scale, SPDF_WIN_MIN_ZOOM, SPDF_WIN_MAX_ZOOM);
    }
    /* 0.0 is the fit helpers' "viewport too small to trust" answer; keeping
     * the current zoom then is what stops a window that has not been sized yet
     * from snapping to something absurd. */
    if (fit > 0.0) canvas->zoom = fit;

    spdf_win_layout_compute(&canvas->layout, canvas->sizes, canvas->page_count, canvas->zoom, (double)canvas->vp_w,
                            SPDF_WIN_PAGE_MARGIN_H, SPDF_WIN_PAGE_MARGIN_V);
    clamp_scroll(canvas);
}

/* --- lifecycle ----------------------------------------------------------- */

spdf_win_canvas* spdf_win_canvas_create(spdf_document* doc, unsigned render_flags, char* err, size_t err_len) {
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
    return canvas;
}

void spdf_win_canvas_destroy(spdf_win_canvas* canvas) {
    if (!canvas) return;
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
    canvas->zoom = target;
    canvas->mode = SPDF_WIN_ZOOM_FREE;
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
