/* spdf_win_links.h — link hit-testing, link navigation, and the cursor regions
 * that decide between an arrow, an I-beam and a hand.
 *
 * SECTION 1 IS A TRANSCRIPTION. The cursor-region model is ported from
 * portable/linux/gtk4/spdf_docview_internal.h (spdf_cursor_rect_empty,
 * spdf_cursor_rect_contains, spdf_cursor_region_at_point and the two constants
 * beside them), which is itself a port of portable/mac/SPDFMacCursorRegions.mm.
 * portable/win/tests/selection_differential.c compiles the real GTK header
 * under portable/win/tests/glib_shim and compares the two exhaustively --
 * boundaries, slop, empty rects, link-beats-text precedence and NaN -- because
 * that discipline has already caught a one-ulp transcription error in this
 * port. Do not "improve" any of it in place; fix it in all three or in none.
 *
 * SECTION 2 IS THIS PORT'S OWN, and its one interesting decision is WHEN THE
 * EXPENSIVE SCAN RUNS:
 *
 *   Hover asks about links on every mouse move, so hover must be cheap. This
 *   builds its link rects with detect_text_links = 0, which reads the page's
 *   link ANNOTATIONS only. spdf_page_link_rects's own header says to do exactly
 *   that -- "pass 0 for hover/cursor hit-testing and 1 only when actually
 *   following a link on click" -- because detecting plain-text URLs builds the
 *   whole structured-text page and costs hundreds of milliseconds on a dense
 *   one. The CLICK path then calls spdf_link_at_point with detect_text_links=1,
 *   so a bare URL printed in the text is still followed.
 *
 *   The consequence is stated rather than hidden: a plain-text URL is
 *   CLICKABLE but does not show a hand on hover, where macOS and GTK show one.
 *   Both of those build the region set on a WORKER THREAD with a document
 *   handle of its own (the core allows one spdf_document per thread and locks
 *   nothing inside it, shenzhen_pdf_core.c:40-43). That thread is the missing
 *   piece here, not the geometry; when it exists, set want_text_links on the
 *   ensure call and the difference disappears.
 *
 * Everything here is main-thread, against the caller's own document handle.
 */
#ifndef SPDF_WIN_LINKS_H
#define SPDF_WIN_LINKS_H

#include "shenzhen_pdf_core.h"
#include "spdf_win_layout.h" /* SPDF_WIN_INLINE */

#ifdef __cplusplus
extern "C" {
#endif

/* --- 1. cursor regions (transcribed from GTK4) ---------------------------- */

/* Matches spdf_link_at_point's 2 pt text-URL slop (mac kSPDFCursorLinkHitPadding),
 * so what hover shows as a hand is exactly what a click follows. */
#define SPDF_WIN_CURSOR_LINK_HIT_PADDING 2.0
/* mac kSPDFCursorRegionMaxLinkRects. */
#define SPDF_WIN_CURSOR_REGION_MAX_LINK_RECTS 512

typedef enum SpdfWinCursorRegionKind {
    SPDF_WIN_CURSOR_REGION_NONE = 0,
    SPDF_WIN_CURSOR_REGION_LINK,
    SPDF_WIN_CURSOR_REGION_TEXT
} SpdfWinCursorRegionKind;

static SPDF_WIN_INLINE int spdf_win_cursor_rect_empty(const spdf_rect* rect) {
    return !rect || rect->x1 <= rect->x0 || rect->y1 <= rect->y0;
}

/* Merge policy for the built region arrays (mac
 * buildCursorRegionsForPageIfNeeded skips NSIsEmptyRect rects): only non-empty
 * rects enter the cache, so a degenerate rect from the core can never own a hit
 * test. Returns 1 when the rect was appended. GTK's counterpart appends into a
 * GArray; this one takes an explicit array, count and capacity, which is the
 * only difference and is a container change, not a policy one. */
static SPDF_WIN_INLINE int spdf_win_cursor_region_append_rect(spdf_rect* rects, int* count, int capacity,
                                                              const spdf_rect* rect) {
    if (!rects || !count || *count >= capacity) return 0;
    if (spdf_win_cursor_rect_empty(rect)) return 0;
    rects[(*count)++] = *rect;
    return 1;
}

static SPDF_WIN_INLINE int spdf_win_cursor_rect_contains(const spdf_rect* rect, double x, double y, double slop) {
    return rect && x >= rect->x0 - slop && x <= rect->x1 + slop && y >= rect->y0 - slop && y <= rect->y1 + slop;
}

/* Link beats text beats none (SPDFMacCursorRegions.mm spdf_cursor_region_at_point);
 * only link rects get the padding slop. */
static SPDF_WIN_INLINE SpdfWinCursorRegionKind spdf_win_cursor_region_at_point(const spdf_rect* links,
                                                                               unsigned link_count,
                                                                               const spdf_rect* text,
                                                                               unsigned text_count, double x, double y,
                                                                               double link_padding) {
    unsigned i;
    for (i = 0; i < link_count; ++i)
        if (spdf_win_cursor_rect_contains(&links[i], x, y, link_padding)) return SPDF_WIN_CURSOR_REGION_LINK;
    for (i = 0; i < text_count; ++i)
        if (spdf_win_cursor_rect_contains(&text[i], x, y, 0.0)) return SPDF_WIN_CURSOR_REGION_TEXT;
    return SPDF_WIN_CURSOR_REGION_NONE;
}

/* --- 2. the per-page region cache ----------------------------------------- */

/* One page's regions at a time. A reader's pointer is over one page; caching
 * more would buy nothing and would have to be invalidated on the same events.
 * Rebuilding costs one fz_load_links (cheap) plus, when text regions are
 * wanted, one structured-text pass over the page (not cheap -- see below). */
typedef struct spdf_win_links spdf_win_links;

spdf_win_links* spdf_win_links_new(void);
void spdf_win_links_free(spdf_win_links* links);
/* Drop everything cached. Call when the document is replaced or reloaded. */
void spdf_win_links_invalidate(spdf_win_links* links);

/* WHAT `want_text_regions` COSTS. The link half is fz_load_links: microseconds,
 * and safe on every mouse move. The text half is spdf_extract_page_text_lines,
 * which builds the page's structured text -- tens of milliseconds on a dense
 * page, once per page, cached until the pointer leaves it. It buys the I-beam
 * over text, which is the difference between a canvas that looks selectable and
 * one that does not. Pass 0 and the cursor is a plain arrow over text.
 *
 * THE FLAG CONTROLS BUILDING, NOT ANSWERING. Once a page's text regions exist
 * they stay until the pointer leaves that page, and a later query with
 * want_text_regions = 0 still gets the I-beam from them -- throwing away work
 * already paid for, only to rebuild it on the next move, would be the expensive
 * choice dressed up as the cheap one.
 *
 * `doc` MUST BELONG TO THE CALLING THREAD (shenzhen_pdf_core.c:40-43). Returns
 * 1 when the page's regions are available. */
int spdf_win_links_ensure_page(spdf_win_links* links, spdf_document* doc, int page_index, int want_text_regions);

/* The cursor's answer for a PAGE POINT (PDF points, y down -- the space
 * spdf_win_selection.h documents). Builds the page's regions if needed. */
SpdfWinCursorRegionKind spdf_win_links_region_at(spdf_win_links* links, spdf_document* doc, int page_index,
                                                 int want_text_regions, float x, float y);

/* Is there a link under this page point? The cheap question, answered from the
 * cached annotation rects with the 2 pt slop, for the press path -- which has
 * to decide "range candidate or link candidate" before it can do anything
 * else. */
int spdf_win_links_hit(spdf_win_links* links, spdf_document* doc, int page_index, float x, float y);

/* --- 3. following one ----------------------------------------------------- */

/* Resolve the link under a page point, WITH plain-text URL detection, because
 * this only runs on an actual click. Returns 1 and fills `out` (owned: free it
 * with spdf_free_link_target) when a link is there, 0 when there is none, -1 on
 * error. */
int spdf_win_links_target_at(spdf_document* doc, int page_index, float x, float y, spdf_link_target* out);

/* WHERE AN INTERNAL LINK LANDS. The core hands back the target page plus a
 * point from fz_resolve_link. This port navigates to THE TOP OF THE TARGET
 * PAGE and ignores the point, which is what macOS's own link handling does and
 * what every /Fit-style destination forces anyway (it carries no point at all).
 *
 * The point is still exposed on spdf_link_target for a caller that wants to
 * refine it, and portable/win/tests/link_test.c PINS WHICH WAY UP IT IS,
 * measured rather than assumed: fz_resolve_link's y arrives in PAGE space, y
 * DOWN -- the same space as every rect here, and NOT the bottom-left PDF user
 * space that spdf_outline_item.dest_y documents for outline entries. The two
 * differ, so a refinement must not borrow the outline code's flip. */

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* SPDF_WIN_LINKS_H */
