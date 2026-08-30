/* Neighbour prefetch: the canvas's half of T5's render service.
 *
 * Split out of spdf_win_canvas.cpp under the repo's 500-line cap. The division
 * is not arbitrary -- this file is the ONLY place the canvas talks to another
 * thread, so "is this concurrent?" is answerable by looking at one file rather
 * than by reading the whole canvas.
 *
 * THE THREADING RULE, and it is the reason none of this needs a lock: requests
 * go out from build_scene and results come back through
 * spdf_win_render_drain(), which runs on whichever thread calls it -- the same
 * one. The worker threads never touch the canvas or its cache; they hand back
 * a buffer and nothing else. If a future change ever calls drain() from a
 * second thread, the LRU needs a mutex that same day.
 */
#include "spdf_win_canvas_internal.h"

#include <windows.h> /* Sleep, for the headless settle only */

#include <math.h>
#include <stdlib.h>
#include <string.h>

/* --- prefetch adoption --------------------------------------------------- */

/* One per outstanding request. It carries the display scale rather than
 * reading canvas->dpi_scale at delivery, because the two can differ: the
 * window may have moved to another monitor while the render was in flight,
 * and filing the result under today's scale would put it where nothing will
 * ever look for it. */
struct adopt_ctx {
    spdf_win_canvas* canvas;
    double scale;
};

static void adopt_render(spdf_win_render_result* result, void* user_data) {
    adopt_ctx* ctx = (adopt_ctx*)user_data;
    SpdfWinLruKey key;
    spdf_bitmap* bitmap;

    if (!ctx) return;
    /* Anything but OK -- cancelled, superseded by a zoom change, shut down,
     * failed -- is simply dropped. The service guarantees exactly one callback
     * per request either way, which is what makes freeing ctx here safe. */
    if (result->status != SPDF_WIN_RENDER_OK || !result->rgba || result->width <= 0) {
        free(ctx);
        return;
    }
    /* Keyed on what was ACTUALLY rendered, not on what was asked for: the
     * service applies its own byte cap and may have come back at a lower zoom
     * than the request named. */
    key = spdf_win_lru_key(result->spec.page, result->render_zoom, ctx->scale);
    bitmap = (spdf_bitmap*)calloc(1, sizeof(*bitmap));
    if (bitmap) {
        bitmap->width = result->width;
        bitmap->height = result->height;
        bitmap->stride = result->stride;
        bitmap->rgba = result->rgba;
        result->rgba = NULL; /* ownership taken; the service must not free it */
        spdf_win_lru_insert(&ctx->canvas->cache, &key, bitmap,
                            spdf_win_lru_bitmap_bytes(bitmap->width, bitmap->height));
    }
    free(ctx);
}

/* Ask the pool for a page that is about to matter. Skipped for anything not
 * yet measured: its size is still page 1's guess, so its render zoom would be
 * a guess too, and a bitmap filed under a guessed key is work thrown away. */
void spdf_win_canvas_prefetch(spdf_win_canvas* canvas, int page) {
    spdf_win_render_spec spec;
    const SpdfWinPageSizePt* size;
    double render_zoom;
    SpdfWinLruKey key;
    adopt_ctx* ctx;

    if (!canvas->service || page < 0 || page >= canvas->measured) return;
    size = &canvas->sizes[page];
    render_zoom = spdf_win_capped_render_zoom(canvas->zoom, size->width, size->height);
    key = spdf_win_lru_key(page, render_zoom, canvas->dpi_scale);
    if (spdf_win_lru_lookup(&canvas->cache, &key)) return;

    ctx = (adopt_ctx*)calloc(1, sizeof(*ctx));
    if (!ctx) return;
    ctx->canvas = canvas;
    ctx->scale = canvas->dpi_scale;

    memset(&spec, 0, sizeof(spec));
    spec.page = page;
    spec.zoom = (float)render_zoom;
    spec.flags = canvas->render_flags;
    /* The service coalesces a request whose key matches one already queued, so
     * asking again every frame for a page still being rendered is cheap and
     * needs no bookkeeping here. */
    if (!spdf_win_render_request(canvas->service, &spec, SPDF_WIN_RENDER_NEAR, adopt_render, ctx)) free(ctx);
}

int spdf_win_canvas_settle(spdf_win_canvas* canvas, int timeout_ms) {
    int adopted = 0;
    int waited = 0;

    if (!canvas || !canvas->service) return 0;
    /* Only the headless probe should call this. A window drains as it paints
     * and never blocks; blocking the UI thread on a prefetch would give back
     * exactly the stall the prefetch exists to remove. */
    while (waited < timeout_ms && spdf_win_render_stat(canvas->service, SPDF_WIN_RENDER_STAT_INFLIGHT) > 0) {
        adopted += spdf_win_render_drain(canvas->service, -1);
        Sleep(2);
        waited += 2;
    }
    return adopted + spdf_win_render_drain(canvas->service, -1);
}

int spdf_win_canvas_sync_renders(const spdf_win_canvas* canvas) { return canvas ? canvas->sync_renders : 0; }

unsigned long long spdf_win_canvas_prefetched(spdf_win_canvas* canvas) {
    return canvas && canvas->service ? spdf_win_render_stat(canvas->service, SPDF_WIN_RENDER_STAT_TASKS_STARTED) : 0;
}
