/* The canvas's half of T5's render service: prefetch, the visible-page ask,
 * adoption, and the notify hook.
 *
 * Split out of spdf_win_canvas.cpp under the repo's 500-line cap. The division
 * is not arbitrary -- this file is the ONLY place the canvas talks to another
 * thread, so "is this concurrent?" is answerable by looking at one file rather
 * than by reading the whole canvas.
 *
 * THE THREADING RULE, and it is the reason almost none of this needs a lock:
 * requests go out from build_scene and results come back through
 * spdf_win_render_drain(), which runs on whichever thread calls it -- the same
 * one. The worker threads never touch the canvas or its cache; they hand back a
 * buffer and nothing else. The one exception is spdf_win_canvas_render_notify(),
 * which DOES run on a worker, reads two fields and one interlocked word, and
 * calls nothing of the canvas's -- see its comment. If a future change ever
 * calls drain() from a second thread, the LRU needs a mutex that same day.
 */
#include "spdf_win_canvas_internal.h"

#include <windows.h> /* Sleep for the headless settle; Interlocked* for notify */

#include <math.h>
#include <stdlib.h>
#include <string.h>

/* --- what is already on its way ------------------------------------------
 *
 * The service coalesces a second request whose key matches one in flight, but
 * only up to SPDF_WIN_RENDER_MAX_WAITERS of them; past that it starts a second
 * render of the same page. A window repainting while a slow page renders would
 * hit that in a quarter of a second, so the canvas keeps its own small table
 * and simply does not ask twice. */

static int inflight_index(const spdf_win_canvas* canvas, const SpdfWinLruKey* key) {
    int i;
    for (i = 0; i < canvas->inflight_count; ++i)
        if (spdf_win_lru_key_equal(&canvas->inflight[i].key, key)) return i;
    return -1;
}

static void inflight_drop(spdf_win_canvas* canvas, unsigned long long token) {
    int i;
    for (i = 0; i < canvas->inflight_count; ++i) {
        if (canvas->inflight[i].token != token) continue;
        canvas->inflight[i] = canvas->inflight[canvas->inflight_count - 1];
        --canvas->inflight_count;
        return;
    }
}

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
    /* The slot goes FIRST and unconditionally: exactly one callback arrives per
     * request whatever its status, so this is the one place the table can be
     * kept honest, and a cancelled or superseded page must become askable
     * again. */
    inflight_drop(ctx->canvas, result->token);
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

/* The one call both askers make. Returns non-zero when the pool now owns a
 * render for `key`, whether this call started it or an earlier one did. */
static int request_page(spdf_win_canvas* canvas, int page, double render_zoom, const SpdfWinLruKey* key,
                        int priority) {
    spdf_win_render_spec spec;
    adopt_ctx* ctx;
    unsigned long long token;

    if (inflight_index(canvas, key) >= 0) return 1;
    if (canvas->inflight_count >= SPDF_WIN_CANVAS_MAX_INFLIGHT) return 0;

    ctx = (adopt_ctx*)calloc(1, sizeof(*ctx));
    if (!ctx) return 0;
    ctx->canvas = canvas;
    ctx->scale = canvas->dpi_scale;

    memset(&spec, 0, sizeof(spec));
    spec.page = page;
    spec.zoom = (float)render_zoom;
    spec.flags = canvas->render_flags;
    token = spdf_win_render_request(canvas->service, &spec, priority, adopt_render, ctx);
    if (!token) {
        free(ctx);
        return 0;
    }
    canvas->inflight[canvas->inflight_count].key = *key;
    canvas->inflight[canvas->inflight_count].token = token;
    canvas->inflight_count++;
    return 1;
}

/* Ask the pool for a page that is about to matter. Skipped for anything not
 * yet measured: its size is still page 1's guess, so its render zoom would be
 * a guess too, and a bitmap filed under a guessed key is work thrown away. */
void spdf_win_canvas_prefetch(spdf_win_canvas* canvas, int page) {
    const SpdfWinPageSizePt* size;
    double render_zoom;
    SpdfWinLruKey key;

    if (!canvas->service || page < 0 || page >= canvas->measured) return;
    size = &canvas->sizes[page];
    render_zoom = spdf_win_capped_render_zoom(canvas->zoom, size->width, size->height);
    key = spdf_win_lru_key(page, render_zoom, canvas->dpi_scale);
    if (spdf_win_lru_peek(&canvas->cache, &key)) return;
    (void)request_page(canvas, page, render_zoom, &key, SPDF_WIN_RENDER_NEAR);
}

/* The page under the viewport, at VISIBLE priority so it jumps every queued
 * neighbour (spdf_win_render.h's priority bands). The caller has just missed
 * the cache for this exact key, so there is no peek here. */
int spdf_win_canvas_request_visible(spdf_win_canvas* canvas, int page, double render_zoom) {
    SpdfWinLruKey key;
    if (!canvas->service || page < 0) return 0;
    key = spdf_win_lru_key(page, render_zoom, canvas->dpi_scale);
    return request_page(canvas, page, render_zoom, &key, SPDF_WIN_RENDER_VISIBLE);
}

/* --- the notify hook, and the only canvas code that runs off the UI thread --
 *
 * A worker calls this the moment a result becomes drainable. It must be cheap
 * and thread-safe, so it does exactly one thing: hand the shell's own hook
 * (a PostMessage, in the window) the shell's own context. Nothing of the
 * canvas is read but the two write-once fields and the interlocked word that
 * publishes them, and nothing is written at all.
 *
 * `notify_armed` is the publication barrier. ready_fn/ready_ctx are written by
 * the UI thread BEFORE the interlocked store that arms them and are never
 * rewritten (spdf_win_canvas_set_async_visible refuses to change a hook it
 * already has), so a worker that sees armed != 0 sees both fields whole.
 * Disarming stores 0 and leaves the fields alone, so the racing worker's worst
 * case is one extra call to a hook that is still valid.
 *
 * It fires for a PREFETCH completion too, which the old comment here called
 * pointless -- "a prefetched page is by definition not on screen yet". That is
 * still true, and it is still one InvalidateRect the next paint was going to do
 * anyway; paying it is far cheaper than a second notify path. */
void spdf_win_canvas_render_notify(void* ctx) {
    spdf_win_canvas* canvas = (spdf_win_canvas*)ctx;
    if (!canvas) return;
    if (InterlockedCompareExchange(&canvas->notify_armed, 0, 0) == 0) return;
    if (canvas->ready_fn) canvas->ready_fn(canvas->ready_ctx);
}

void spdf_win_canvas_set_async_visible(spdf_win_canvas* canvas, void (*ready)(void*), void* ready_ctx) {
    if (!canvas) return;
    if (!ready) {
        /* Disarm only. The hook itself is left in place: it is write-once so a
         * worker mid-notify can never see a half-changed pair. */
        InterlockedExchange(&canvas->notify_armed, 0);
        canvas->async_visible = 0;
        return;
    }
    if (!canvas->ready_fn) {
        canvas->ready_fn = ready;
        canvas->ready_ctx = ready_ctx;
    }
    /* A second arming with a DIFFERENT hook is refused rather than honoured:
     * see the notify hook's comment for why the pair has to be write-once. One
     * shell arms one canvas once, and a canvas dies with its tab. */
    if (canvas->ready_fn != ready || canvas->ready_ctx != ready_ctx) return;
    canvas->async_visible = 1;
    InterlockedExchange(&canvas->notify_armed, 1);
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

int spdf_win_canvas_stale_draws(const spdf_win_canvas* canvas) { return canvas ? canvas->stale_draws : 0; }

unsigned long long spdf_win_canvas_prefetched(spdf_win_canvas* canvas) {
    return canvas && canvas->service ? spdf_win_render_stat(canvas->service, SPDF_WIN_RENDER_STAT_TASKS_STARTED) : 0;
}
