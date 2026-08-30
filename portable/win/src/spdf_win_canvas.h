/* The continuous scrolling document canvas -- Phase 2's model layer.
 *
 * This is the piece that turns "a window showing page 1" into "a document":
 * every page stacked on one vertical strip, a scroll offset, a zoom with fit
 * modes and cursor anchoring, and a render cache that only ever holds pages
 * somebody can actually see.
 *
 * IT OWNS NO WIN32 AND NO DIRECT2D. It takes a spdf_document and a viewport
 * size in device pixels, and it produces a spdf_win_scene -- a list of page
 * bitmaps with destination rectangles. spdf_win_window.cpp feeds it input,
 * spdf_win_d2d.cpp draws what it produces, and neither of those two files
 * knows how a page is placed. That split is what lets the headless probe and
 * the real window scroll to the same pixel: spdf_win_main.cpp's
 * --render-window-png drives this same canvas with no HWND in sight.
 *
 * Geometry comes from T3's spdf_win_layout.h, the page cache is T3's
 * spdf_win_lru, and neighbour prefetch runs on T5's spdf_win_render worker
 * pool. Nothing here re-derives any of the three. The page under the viewport
 * is still rendered synchronously on purpose -- see the .cpp.
 *
 * `path` is the document's UTF-8 path, used only to give the render workers
 * something to open (the core allows one spdf_document per thread, so they
 * cannot share ours). NULL disables prefetch; everything still works, just on
 * the calling thread.
 */
#ifndef SPDF_WIN_CANVAS_H
#define SPDF_WIN_CANVAS_H

#include "spdf_win_d2d.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct spdf_win_canvas spdf_win_canvas;

typedef enum spdf_win_zoom_mode {
    SPDF_WIN_ZOOM_FREE = 0,       /* whatever zoom was last set */
    SPDF_WIN_ZOOM_FIT_WIDTH = 1,  /* page width fills the viewport; re-fits on resize */
    SPDF_WIN_ZOOM_FIT_PAGE = 2,   /* whole page visible */
    SPDF_WIN_ZOOM_ACTUAL = 3      /* 1 PDF point = 1 logical pixel, times the DPI scale */
} spdf_win_zoom_mode;

/* Borrows `doc` -- the caller keeps ownership and must outlive the canvas.
 * Cheap: it reads page 1's size and NOTHING else, because that is all the
 * first frame needs and launch time is the product's headline promise. Sizes
 * for later pages are measured as the viewport reaches them. */
spdf_win_canvas* spdf_win_canvas_create(spdf_document* doc, const char* path, unsigned render_flags, char* err,
                                        size_t err_len);
void spdf_win_canvas_destroy(spdf_win_canvas* canvas);

/* Viewport in DEVICE PIXELS, plus the display's device-pixels-per-logical-pixel.
 * Idempotent: relaying out only happens when something actually changed. A
 * resize under a fit mode re-derives the zoom and keeps the anchored page. */
void spdf_win_canvas_set_viewport(spdf_win_canvas* canvas, unsigned px_w, unsigned px_h, float dpi_scale);

void spdf_win_canvas_set_zoom_mode(spdf_win_canvas* canvas, spdf_win_zoom_mode mode);
spdf_win_zoom_mode spdf_win_canvas_zoom_mode(const spdf_win_canvas* canvas);
float spdf_win_canvas_zoom(const spdf_win_canvas* canvas);

/* Multiplies the zoom by `factor`, keeping the document point currently under
 * viewport pixel (vx, vy) under that same pixel afterwards. This is the
 * operation Ctrl+wheel and pinch perform, and the one the zoom-anchor test
 * checks: the anchor is captured in document space (page + PDF point), so it
 * stays exact even when the render byte cap shrinks the texture. Switches the
 * zoom mode to FREE. */
void spdf_win_canvas_zoom_at(spdf_win_canvas* canvas, float factor, float vx, float vy);
void spdf_win_canvas_set_zoom_at(spdf_win_canvas* canvas, float zoom, float vx, float vy);

/* Scrolling, in viewport device pixels. Both clamp to the scrollable range;
 * scroll_by returns non-zero when the offset actually moved, so the window can
 * skip an invalidate that would repaint identical pixels. */
int spdf_win_canvas_scroll_by(spdf_win_canvas* canvas, float dx, float dy);
int spdf_win_canvas_scroll_to(spdf_win_canvas* canvas, float x, float y);
/* Puts the top of `page_index` at the top of the viewport (minus the slot
 * margin), measuring intervening pages as needed. */
int spdf_win_canvas_scroll_to_page(spdf_win_canvas* canvas, int page_index);

float spdf_win_canvas_scroll_x(const spdf_win_canvas* canvas);
float spdf_win_canvas_scroll_y(const spdf_win_canvas* canvas);
float spdf_win_canvas_content_w(const spdf_win_canvas* canvas);
float spdf_win_canvas_content_h(const spdf_win_canvas* canvas);
int spdf_win_canvas_page_count(const spdf_win_canvas* canvas);
/* The page whose centre is nearest the viewport's middle -- what a page
 * indicator would show, and what the horizontal clamp policy keys on. */
int spdf_win_canvas_current_page(const spdf_win_canvas* canvas);

/* Fills `scene` with every page intersecting the viewport, rendering the ones
 * that are not cached. `scene`'s target_px_w/h, dpi_scale and dark are set
 * from the canvas. The page list it points at stays valid until the next call
 * on this canvas. Returns non-zero when there is something to draw. */
int spdf_win_canvas_build_scene(spdf_win_canvas* canvas, spdf_win_scene* scene);

/* Bytes currently held by the page-bitmap cache. For the render-budget check;
 * never used to make a drawing decision. */
size_t spdf_win_canvas_cache_bytes(const spdf_win_canvas* canvas);
/* How many pages the LAST build_scene had to render on the calling thread. 0
 * means every visible page came from the cache -- which, after a scroll onto a
 * new page, is the observable proof that prefetch did its job. */
int spdf_win_canvas_sync_renders(const spdf_win_canvas* canvas);
/* How many renders the worker pool has started. Diagnostic only. */
unsigned long long spdf_win_canvas_prefetched(spdf_win_canvas* canvas);

/* HEADLESS ONLY. Drains completions, waiting up to timeout_ms for outstanding
 * prefetches, and returns how many were adopted. A window must never call this
 * -- it drains as it paints, and blocking the UI thread on a prefetch gives
 * back the stall the prefetch exists to remove. It exists so a probe can make
 * a multi-frame scroll deterministic. */
int spdf_win_canvas_settle(spdf_win_canvas* canvas, int timeout_ms);

#ifdef __cplusplus
}
#endif

#endif /* SPDF_WIN_CANVAS_H */
