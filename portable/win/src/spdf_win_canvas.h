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
    SPDF_WIN_ZOOM_ACTUAL = 3,     /* 1 PDF point = 1 logical pixel, times the DPI scale */
    /* Page HEIGHT fills the viewport, letting a wide sheet overflow sideways.
     * macOS's fit popup has offered this from the start (SPDFFitModeHeight,
     * ShenzhenPDFMac.mm:3006-3011) and spdf_win_layout.h has carried the
     * arithmetic for it since the layout port (spdf_win_fit_height_zoom); only
     * this enum was missing, so the toolbar's fit cycle silently skipped one of
     * macOS's four items. Numbered last so no persisted or scripted value moves. */
    SPDF_WIN_ZOOM_FIT_HEIGHT = 4
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

/* WHAT A SCROLLBAR NEEDS, and nothing else: two fractions per axis plus whether
 * the content overflows sideways at all.
 *
 * FRACTIONS, NOT OFFSETS, and that is the whole point of this call existing
 * rather than the chrome dividing scroll_y by content_h itself. `visible` is
 * viewport/content, which IS the thumb's proportional length, and `pos` is
 * offset/(content - viewport), which IS where the thumb sits in its travel. Both
 * are unitless, so spdf_win_chrome_scroll.h needs no notion of a PDF point, a
 * zoom or a page -- and neither can be got wrong by a caller that does not know
 * the canvas measures page heights lazily.
 *
 * `h_scrollable` says whether there is anything to drag SIDEWAYS, which is not
 * the same question as "is the content wider than the viewport". The canvas is
 * always at least `widest page + 2 * 22 pt` wide, so at fit width the content
 * permanently overflows by 44 px -- and spdf_win_hscroll_clamp then pins a page
 * that fits the viewport CENTRED, so the offset never moves. A trough drawn
 * from the overflow alone would therefore be present on every ordinary document
 * with a thumb nobody can move. So this reports the CURRENT PAGE's pan range,
 * which is exactly what the clamp permits, and the horizontal `pos`/`visible`
 * are measured against that same page. (This does not contradict
 * spdf_win_layout.h:349-355: that warns against keying the canvas's WIDTH on
 * the current page, which nothing here does.)
 *
 * It decides whether a horizontal trough exists at all, so painter and hit-test
 * must both take it from here and from nowhere else. */
typedef struct spdf_win_canvas_scroll {
    float v_pos;
    float v_visible;
    float h_pos;
    float h_visible;
    int h_scrollable;
} spdf_win_canvas_scroll;

/* Always fully written, so a caller may read every field after any call. A NULL
 * canvas yields "nothing to scroll": both fractions 0 and both `visible` 1,
 * which spdf_win_chrome_scroll.h draws as a full-length thumb -- the honest
 * picture of a window with no document. */
void spdf_win_canvas_scroll_state(const spdf_win_canvas* canvas, spdf_win_canvas_scroll* out);

/* Scroll one axis to a fraction in [0,1] of its travel -- the inverse of the
 * `pos` above, and what a thumb drag performs. Returns non-zero when the offset
 * actually moved. Clamps like every other scroll entry point. */
int spdf_win_canvas_scroll_to_fraction(spdf_win_canvas* canvas, int vertical, float pos);

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

/* --- text selection and links -------------------------------------------
 *
 * THE WHOLE INPUT SURFACE THE SHELL HAS TO WIRE, and deliberately no more: six
 * calls, all of them taking CANVAS-LOCAL DEVICE PIXELS and nothing else. No
 * HWND, no document, no page number, no PDF point crosses this line, so the
 * input router can stay a router. spdf_win_selection.h and spdf_win_links.h
 * hold the model; this is the canvas binding it to its own geometry.
 *
 * Everything here runs on the UI thread against the canvas's own document
 * handle, which is the thread that owns it (shenzhen_pdf_core.c:40-43).
 * Nothing here needs a window, so the headless probe drives the same calls.
 *
 * Each of the three pointer calls returns non-zero when the VISIBLE selection
 * changed, i.e. when the caller should invalidate. */

typedef enum spdf_win_canvas_cursor {
    SPDF_WIN_CANVAS_CURSOR_ARROW = 0, /* IDC_ARROW  */
    SPDF_WIN_CANVAS_CURSOR_TEXT = 1,  /* IDC_IBEAM  */
    SPDF_WIN_CANVAS_CURSOR_HAND = 2   /* IDC_HAND   */
} spdf_win_canvas_cursor;

/* What a release wants done about a link, if anything. `uri` is borrowed and
 * valid until the next pointer call on this canvas. An INTERNAL target has
 * ALREADY been scrolled to by the time this is filled -- the canvas can do that
 * itself and the shell would only be forwarding it back. A URI target is NOT
 * opened here: launching a browser is a shell decision with a shell's security
 * questions, and the canvas has no business making it. */
typedef struct spdf_win_canvas_link_nav {
    int kind;        /* spdf_link_kind: NONE / URI / INTERNAL */
    int page_index;  /* INTERNAL only: the page scrolled to */
    const char* uri; /* URI only: borrowed UTF-8 */
} spdf_win_canvas_link_nav;

/* `click_count` is the accumulated count for a multi-click series (1, 2, 3...).
 * Win32 does not accumulate it: WM_LBUTTONDBLCLK is the SECOND click, so the
 * router counts, and a triple click is a WM_LBUTTONDOWN inside
 * GetDoubleClickTime() of a WM_LBUTTONDBLCLK. Two selects a word, three or more
 * selects the block. */
int spdf_win_canvas_pointer_press(spdf_win_canvas* canvas, float x, float y, unsigned click_count);
/* Only meaningful while a button is down; a no-op otherwise. */
int spdf_win_canvas_pointer_drag(spdf_win_canvas* canvas, float x, float y);
/* `out_nav` may be NULL. */
int spdf_win_canvas_pointer_release(spdf_win_canvas* canvas, spdf_win_canvas_link_nav* out_nav);
/* Capture lost, or Escape: ends the gesture, keeps a completed selection. */
void spdf_win_canvas_pointer_cancel(spdf_win_canvas* canvas);

/* Which cursor belongs at this point. `want_text_cursor` asks for the I-beam
 * over text, which costs one structured-text pass per page visited (see
 * spdf_win_links.h); 0 answers hand-or-arrow for free. */
spdf_win_canvas_cursor spdf_win_canvas_cursor_at(spdf_win_canvas* canvas, float x, float y, int want_text_cursor);

/* Copy the selection to the clipboard as CF_UNICODETEXT. Returns 1 when
 * something was copied. NO PERMISSION GATE, by product decision -- see
 * spdf_win_selection.h section 5 and shenzhen_pdf_core.h:209-214. */
int spdf_win_canvas_copy_selection(spdf_win_canvas* canvas);
/* Borrowed UTF-8, NULL when nothing is selected. */
const char* spdf_win_canvas_selection_text(const spdf_win_canvas* canvas);
int spdf_win_canvas_has_selection(const spdf_win_canvas* canvas);
/* Returns non-zero when something was actually cleared. */
int spdf_win_canvas_clear_selection(spdf_win_canvas* canvas);

/* THE SECOND OVERLAY PRODUCER. Call it AFTER spdf_win_canvas_build_scene() and
 * AFTER spdf_win_find_apply_overlays(): it takes whatever overlays the scene
 * already carries as a base, appends the selection's rects, and re-points the
 * scene at the combined array. Selection last is macOS's own draw order
 * (SPDFMacDocumentView.mm :467 highlights, :475 active ring, :485 selection),
 * and it leaves find's "the active ring is the last thing I emit" contract
 * intact. See spdf_win_selection.h section 4 for why this shape rather than one
 * combined producer. A no-op when nothing is selected. */
void spdf_win_canvas_apply_selection_overlays(spdf_win_canvas* canvas, spdf_win_scene* scene);

#ifdef __cplusplus
}
#endif

#endif /* SPDF_WIN_CANVAS_H */
