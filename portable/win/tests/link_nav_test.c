/* link_nav_test.c — the PURE model behind where an internal link jump lands
 * (spdf_win_links.h section 3).
 *
 * NO DOCUMENT AND NO MUPDF, on purpose. The model is arithmetic over numbers a
 * caller already has, so this runs on any host and stays exhaustive; the
 * real-document half is portable/win/tests/link_destination_test.c, which drives
 * the same two functions through a real canvas at a real zoom.
 *
 * IT IS A TRANSCRIPTION, so the expectations below are the MAC TEST'S OWN cases
 * rather than newly invented ones. spdf_win_link_destination_scroll_y ports
 * spdf_mac_link_destination_scroll_origin_y, pinned on that side by
 * SPDFMacSelectionClickTests.mm's
 * test_link_destination_scroll_is_target_page_top -- page-only destination,
 * offset honoured, offset scaled by zoom, never reaching page N-1, a negative
 * offset, and the first page clamping at the document top. Every one of those
 * six is repeated here with this port's own lead-in constant.
 */
#include "spdf_win_links.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static int g_failures = 0;
static int g_checks = 0;

#define CHECK(cond)                                                                                                    \
    do {                                                                                                               \
        ++g_checks;                                                                                                    \
        if (!(cond)) {                                                                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);                                                     \
            ++g_failures;                                                                                              \
        }                                                                                                              \
    } while (0)

#define CHECK_EQI(a, b)                                                                                                \
    do {                                                                                                               \
        long long va = (long long)(a);                                                                                 \
        long long vb = (long long)(b);                                                                                 \
        ++g_checks;                                                                                                    \
        if (va != vb) {                                                                                                \
            printf("FAIL %s:%d: %s (%lld) != %s (%lld)\n", __FILE__, __LINE__, #a, va, #b, vb);                        \
            ++g_failures;                                                                                              \
        }                                                                                                              \
    } while (0)

#define CHECK_EQD(a, b)                                                                                                \
    do {                                                                                                               \
        double va = (double)(a);                                                                                       \
        double vb = (double)(b);                                                                                       \
        ++g_checks;                                                                                                    \
        if (!(fabs(va - vb) < 1e-9)) {                                                                                 \
            printf("FAIL %s:%d: %s (%.9f) != %s (%.9f)\n", __FILE__, __LINE__, #a, va, #b, vb);                        \
            ++g_failures;                                                                                              \
        }                                                                                                              \
    } while (0)

/* --- section 3: where the jump lands -------------------------------------- */

/* Two adjacent slots from a real continuous layout: 612x792 pages at zoom 1,
 * so page 0 sits at y = SPDF_WIN_PAGE_MARGIN_V and page 1 one gutter below it
 * (spdf_win_layout_compute: y += h + 2 * margin_v). The mac test uses two
 * hand-written NSRects for the same reason -- the arithmetic must depend on the
 * TARGET slot only. */
#define SLOT_PREV (SPDF_WIN_PAGE_MARGIN_V)
#define SLOT_PREV_BOTTOM (SLOT_PREV + 792.0)
#define SLOT_TARGET (SLOT_PREV + 792.0 + 2.0 * SPDF_WIN_PAGE_MARGIN_V)

static void test_destination_scroll_y(void) {
    /* "page-only destination aligns the page top": EXACTLY what
     * spdf_win_canvas_scroll_to_page() computes, which is the invariant mac's
     * own comment states and the reason this port subtracts its own gutter
     * rather than mac's 12 pt lead-in. */
    CHECK_EQD(spdf_win_link_destination_scroll_y(SLOT_TARGET, 0.0, 1.0), SLOT_TARGET - SPDF_WIN_PAGE_MARGIN_V);
    /* "destination offset is honored at zoom 1" */
    CHECK_EQD(spdf_win_link_destination_scroll_y(SLOT_TARGET, 50.0, 1.0), SLOT_TARGET + 50.0 - SPDF_WIN_PAGE_MARGIN_V);
    /* "destination offset scales with zoom" -- points times zoom, not points. */
    CHECK_EQD(spdf_win_link_destination_scroll_y(SLOT_TARGET, 50.0, 2.0), SLOT_TARGET + 100.0 - SPDF_WIN_PAGE_MARGIN_V);
    CHECK_EQD(spdf_win_link_destination_scroll_y(SLOT_TARGET, 232.0, 1.5),
              SLOT_TARGET + 348.0 - SPDF_WIN_PAGE_MARGIN_V);
    /* "result never reaches the preceding page": the whole reason this is
     * top-aligned instead of centred. */
    CHECK(spdf_win_link_destination_scroll_y(SLOT_TARGET, 0.0, 1.0) > SLOT_PREV_BOTTOM);
    /* "a negative destination cannot pull the previous page in" */
    CHECK_EQD(spdf_win_link_destination_scroll_y(SLOT_TARGET, -400.0, 1.0), SLOT_TARGET - SPDF_WIN_PAGE_MARGIN_V);
    /* "first page clamps at the document top" -- page 0's slot y IS the gutter,
     * so a page-only destination there is offset 0, not a negative scroll. */
    CHECK_EQD(spdf_win_link_destination_scroll_y(SPDF_WIN_PAGE_MARGIN_V, 0.0, 1.0), 0.0);
    CHECK_EQD(spdf_win_link_destination_scroll_y(0.0, 0.0, 1.0), 0.0);
    CHECK_EQD(spdf_win_link_destination_scroll_y(0.0, 4.0, 1.0), 0.0); /* still inside the gutter */
    CHECK_EQD(spdf_win_link_destination_scroll_y(0.0, 20.0, 1.0), 7.0);

    /* A zoom of 0 or less is treated as 1 (mac: `zoom > 0.0 ? zoom : 1.0`),
     * which is what a canvas with no measured page would hand over. */
    CHECK_EQD(spdf_win_link_destination_scroll_y(SLOT_TARGET, 50.0, 0.0), SLOT_TARGET + 50.0 - SPDF_WIN_PAGE_MARGIN_V);
    CHECK_EQD(spdf_win_link_destination_scroll_y(SLOT_TARGET, 50.0, -3.0), SLOT_TARGET + 50.0 - SPDF_WIN_PAGE_MARGIN_V);
    /* A destination exactly at the page's top edge is a page-only destination:
     * `> 0.0`, so zero adds nothing and no rounding creeps in. */
    CHECK_EQD(spdf_win_link_destination_scroll_y(SLOT_TARGET, 0.0, 3.7), SLOT_TARGET - SPDF_WIN_PAGE_MARGIN_V);
}

static spdf_link_target internal_target(int page, float x, float y) {
    spdf_link_target t;
    memset(&t, 0, sizeof(t));
    t.kind = SPDF_LINK_INTERNAL;
    t.page_index = page;
    t.x = x;
    t.y = y;
    return t;
}

static void test_destination_page_y(void) {
    spdf_link_target t = internal_target(3, 72.0f, 232.0f);
    /* PAGE SPACE, y DOWN, taken as it comes: link_test.c measures that
     * fz_resolve_link already flipped it, so nothing here flips it again. */
    CHECK_EQD(spdf_win_link_destination_page_y(&t), 232.0);

    /* A destination that names only a page, reported as the origin. */
    t.x = 0.0f;
    t.y = 0.0f;
    CHECK_EQD(spdf_win_link_destination_page_y(&t), 0.0);

    /* BOTH AXES MUST BE FINITE, which is mac's `isfinite(target.x) &&
     * isfinite(target.y)`: fz_resolve_link fills them together, so a
     * half-finite point is a point it could not resolve. This is the real
     * /Fit case, not a hypothetical one -- link_destination_test.c measures a
     * /Fit destination arriving as (nan, nan). */
    t = internal_target(3, 72.0f, (float)NAN);
    CHECK_EQD(spdf_win_link_destination_page_y(&t), 0.0);
    t = internal_target(3, (float)NAN, 232.0f);
    CHECK_EQD(spdf_win_link_destination_page_y(&t), 0.0);
    t = internal_target(3, (float)INFINITY, 232.0f);
    CHECK_EQD(spdf_win_link_destination_page_y(&t), 0.0);
    t = internal_target(3, 72.0f, (float)-INFINITY);
    CHECK_EQD(spdf_win_link_destination_page_y(&t), 0.0);

    /* Only an INTERNAL target names a place in this document. */
    t = internal_target(3, 72.0f, 232.0f);
    t.kind = SPDF_LINK_URI;
    CHECK_EQD(spdf_win_link_destination_page_y(&t), 0.0);
    t.kind = SPDF_LINK_NONE;
    CHECK_EQD(spdf_win_link_destination_page_y(&t), 0.0);
    CHECK_EQD(spdf_win_link_destination_page_y(NULL), 0.0);

    /* A negative y survives the extraction and is dropped by the scroll, which
     * is where mac drops it too -- one guard, not two. */
    t = internal_target(3, 72.0f, -5.0f);
    CHECK_EQD(spdf_win_link_destination_page_y(&t), -5.0);
    CHECK_EQD(spdf_win_link_destination_scroll_y(SLOT_TARGET, spdf_win_link_destination_page_y(&t), 1.0),
              SLOT_TARGET - SPDF_WIN_PAGE_MARGIN_V);
}

int main(void) {
    test_destination_scroll_y();
    test_destination_page_y();

    printf("link_nav_test: %d checks, %d failures\n", g_checks, g_failures);
    return g_failures ? 1 : 0;
}
