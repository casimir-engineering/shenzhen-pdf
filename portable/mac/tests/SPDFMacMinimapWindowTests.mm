#import <Cocoa/Cocoa.h>

#import "../SPDFMacMinimapWindow.h"

static int gFailureCount = 0;

static void expect_true(NSString* label, BOOL condition) {
    if (!condition) {
        fprintf(stderr, "FAIL %s\n", label.UTF8String);
        ++gFailureCount;
    }
}

static void expect_window(NSString* label, SPDFMinimapThumbnailWindow window, NSInteger start, NSInteger end) {
    if (window.start != start || window.end != end) {
        fprintf(stderr, "FAIL %s: expected [%ld..%ld], got [%ld..%ld]\n", label.UTF8String, (long)start, (long)end,
                (long)window.start, (long)window.end);
        ++gFailureCount;
    }
}

static void test_tiny_documents(void) {
    // A tiny document is fully covered by the window from any visible range.
    SPDFMinimapThumbnailWindow empty = spdf_minimap_window_empty();
    expect_true(@"empty window is invalid", !spdf_minimap_window_is_valid(empty));
    expect_window(@"2-page doc covers everything", spdf_minimap_window_for_visible_range(2, 0, 1, empty), 0, 1);
    expect_window(@"1-page doc", spdf_minimap_window_for_visible_range(1, 0, 0, empty), 0, 0);
    expect_window(@"30-page doc covers everything from top", spdf_minimap_window_for_visible_range(30, 0, 8, empty), 0,
                  29);
    // Window covering the whole doc never evicts anything.
    SPDFMinimapThumbnailWindow window = spdf_minimap_window_for_visible_range(2, 0, 1, empty);
    expect_true(@"2-page doc: page 0 kept", !spdf_minimap_window_should_evict(window, 0));
    expect_true(@"2-page doc: page 1 kept", !spdf_minimap_window_should_evict(window, 1));
    // Zero page count yields no window and no renders.
    expect_true(@"0-page doc invalid", !spdf_minimap_window_is_valid(spdf_minimap_window_for_visible_range(0, 0, 0, empty)));
    expect_true(@"invalid window renders nothing", spdf_minimap_window_render_order(empty, 0, 0).count == 0);
}

static void test_huge_document_bounds(void) {
    SPDFMinimapThumbnailWindow empty = spdf_minimap_window_empty();
    const NSInteger pageCount = 2000;
    // Start: visible [0..8] -> window clamps at 0.
    expect_window(@"huge doc at start", spdf_minimap_window_for_visible_range(pageCount, 0, 8, empty), 0,
                  8 + kSPDFMinimapWindowExtraPages);
    // Middle: symmetric window around the visible range.
    expect_window(@"huge doc in middle", spdf_minimap_window_for_visible_range(pageCount, 1000, 1008, empty),
                  1000 - kSPDFMinimapWindowExtraPages, 1008 + kSPDFMinimapWindowExtraPages);
    // End: clamps at pageCount-1.
    expect_window(@"huge doc at end", spdf_minimap_window_for_visible_range(pageCount, 1991, 1999, empty),
                  1991 - kSPDFMinimapWindowExtraPages, 1999);
    // Out-of-range visible values are clamped, not propagated.
    SPDFMinimapThumbnailWindow clamped = spdf_minimap_window_for_visible_range(pageCount, -5, 5000, empty);
    expect_true(@"clamped window valid", spdf_minimap_window_is_valid(clamped));
    expect_true(@"clamped window inside doc", clamped.start >= 0 && clamped.end <= pageCount - 1);
    // Window size stays bounded regardless of page count (visible range + 2*extra).
    SPDFMinimapThumbnailWindow middle = spdf_minimap_window_for_visible_range(pageCount, 1000, 1008, empty);
    expect_true(@"window size bounded",
                middle.end - middle.start + 1 <= 9 + 2 * kSPDFMinimapWindowExtraPages);
}

static void test_recentering(void) {
    const NSInteger pageCount = 2000;
    SPDFMinimapThumbnailWindow window = spdf_minimap_window_for_visible_range(pageCount, 1000, 1008, spdf_minimap_window_empty());
    // Still comfortably inside: window unchanged (hysteresis).
    SPDFMinimapThumbnailWindow same = spdf_minimap_window_for_visible_range(pageCount, 1004, 1012, window);
    expect_window(@"inside margin keeps window", same, window.start, window.end);
    // Moving within the recenter margin of the bottom edge recenters.
    NSInteger nearEdgeLast = window.end - kSPDFMinimapWindowRecenterMarginPages + 1;
    SPDFMinimapThumbnailWindow recentered =
        spdf_minimap_window_for_visible_range(pageCount, nearEdgeLast - 8, nearEdgeLast, window);
    expect_true(@"near edge recenters", recentered.start != window.start || recentered.end != window.end);
    expect_window(@"recentered around new visible", recentered, nearEdgeLast - 8 - kSPDFMinimapWindowExtraPages,
                  nearEdgeLast + kSPDFMinimapWindowExtraPages);
    // A far jump (click-to-jump / drag) recenters immediately.
    SPDFMinimapThumbnailWindow jumped = spdf_minimap_window_for_visible_range(pageCount, 100, 108, recentered);
    expect_window(@"far jump recenters", jumped, 100 - kSPDFMinimapWindowExtraPages,
                  108 + kSPDFMinimapWindowExtraPages);
    // Sitting at the document edges never forces a recenter loop.
    SPDFMinimapThumbnailWindow top = spdf_minimap_window_for_visible_range(pageCount, 0, 8, spdf_minimap_window_empty());
    SPDFMinimapThumbnailWindow topAgain = spdf_minimap_window_for_visible_range(pageCount, 0, 8, top);
    expect_window(@"stable at top", topAgain, top.start, top.end);
    SPDFMinimapThumbnailWindow bottom =
        spdf_minimap_window_for_visible_range(pageCount, 1991, 1999, spdf_minimap_window_empty());
    SPDFMinimapThumbnailWindow bottomAgain = spdf_minimap_window_for_visible_range(pageCount, 1991, 1999, bottom);
    expect_window(@"stable at bottom", bottomAgain, bottom.start, bottom.end);
    // A stale window from a longer document is recomputed for a shorter one.
    SPDFMinimapThumbnailWindow stale = {1800, 1900};
    SPDFMinimapThumbnailWindow refreshed = spdf_minimap_window_for_visible_range(50, 0, 8, stale);
    expect_true(@"stale window recomputed", refreshed.start == 0 && refreshed.end <= 49);
}

static void test_eviction(void) {
    SPDFMinimapThumbnailWindow window = {970, 1038};
    // Inside the window: kept.
    expect_true(@"inside kept", !spdf_minimap_window_should_evict(window, 1000));
    expect_true(@"window edge kept", !spdf_minimap_window_should_evict(window, 970));
    // Within the slack band outside the window: kept (hysteresis).
    expect_true(@"slack band above kept",
                !spdf_minimap_window_should_evict(window, 970 - kSPDFMinimapWindowEvictSlackPages));
    expect_true(@"slack band below kept",
                !spdf_minimap_window_should_evict(window, 1038 + kSPDFMinimapWindowEvictSlackPages));
    // Beyond the slack: evicted.
    expect_true(@"far above evicted",
                spdf_minimap_window_should_evict(window, 970 - kSPDFMinimapWindowEvictSlackPages - 1));
    expect_true(@"far below evicted",
                spdf_minimap_window_should_evict(window, 1038 + kSPDFMinimapWindowEvictSlackPages + 1));
    // An invalid window never evicts (e.g. layout transiently unavailable).
    expect_true(@"invalid window never evicts",
                !spdf_minimap_window_should_evict(spdf_minimap_window_empty(), 0));
}

static void test_render_order(void) {
    SPDFMinimapThumbnailWindow window = {90, 130};
    NSArray<NSNumber*>* order = spdf_minimap_window_render_order(window, 100, 108);
    expect_true(@"order covers whole window", (NSInteger)order.count == window.end - window.start + 1);
    // Visible pages come first, in index order.
    for (NSInteger i = 0; i <= 8; ++i)
        expect_true(@"visible pages lead", order[(NSUInteger)i].integerValue == 100 + i);
    // Every later page is at least as far from the visible range as its predecessor.
    NSInteger lastDistance = 0;
    for (NSNumber* number in order) {
        NSInteger index = number.integerValue;
        NSInteger distance = index < 100 ? 100 - index : (index > 108 ? index - 108 : 0);
        expect_true(@"distance is non-decreasing", distance >= lastDistance);
        lastDistance = distance;
    }
}

static void test_no_thrash_single_page_moves(void) {
    // Scroll a 2000-page document one page at a time and verify no page is
    // ever rendered, evicted, and re-rendered while the viewport moves in one
    // direction — and that the total render count stays ~one per new page.
    const NSInteger pageCount = 2000;
    const NSInteger visibleSpan = 8;
    SPDFMinimapThumbnailWindow window = spdf_minimap_window_empty();
    NSMutableSet<NSNumber*>* thumbnails = [NSMutableSet set];
    NSMutableDictionary<NSNumber*, NSNumber*>* renderCounts = [NSMutableDictionary dictionary];
    NSInteger totalRenders = 0;
    NSInteger maxResident = 0;
    for (NSInteger first = 0; first + visibleSpan < 700; ++first) {
        window = spdf_minimap_window_for_visible_range(pageCount, first, first + visibleSpan, window);
        for (NSNumber* number in [thumbnails copy]) {
            if (spdf_minimap_window_should_evict(window, number.integerValue)) [thumbnails removeObject:number];
        }
        for (NSNumber* number in spdf_minimap_window_render_order(window, first, first + visibleSpan)) {
            if ([thumbnails containsObject:number]) continue;
            [thumbnails addObject:number];
            renderCounts[number] = @(renderCounts[number].integerValue + 1);
            ++totalRenders;
        }
        maxResident = MAX(maxResident, (NSInteger)thumbnails.count);
    }
    for (NSNumber* number in renderCounts) {
        if (renderCounts[number].integerValue > 1) {
            fprintf(stderr, "FAIL no-thrash: page %ld rendered %ld times\n", (long)number.integerValue,
                    (long)renderCounts[number].integerValue);
            ++gFailureCount;
            break;
        }
    }
    expect_true(@"total renders ~ pages passed", totalRenders <= 700 + 2 * kSPDFMinimapWindowExtraPages + visibleSpan);
    // Resident thumbnails stay bounded by window + slack on both sides.
    NSInteger bound = visibleSpan + 1 + 2 * (kSPDFMinimapWindowExtraPages + kSPDFMinimapWindowEvictSlackPages) +
                      2 * kSPDFMinimapWindowRecenterMarginPages;
    expect_true(@"resident thumbnails bounded", maxResident <= bound);

    // Reversing direction right after a recenter must not re-render evicted
    // pages immediately (eviction slack > recenter distance).
    NSInteger reverseRenders = 0;
    for (NSInteger first = 690; first >= 600; --first) {
        window = spdf_minimap_window_for_visible_range(pageCount, first, first + visibleSpan, window);
        for (NSNumber* number in [thumbnails copy]) {
            if (spdf_minimap_window_should_evict(window, number.integerValue)) [thumbnails removeObject:number];
        }
        for (NSNumber* number in spdf_minimap_window_render_order(window, first, first + visibleSpan)) {
            if ([thumbnails containsObject:number]) continue;
            [thumbnails addObject:number];
            ++reverseRenders;
        }
    }
    // Going back over just-visited pages should need at most the pages beyond
    // the kept band (not a re-render of every page).
    expect_true(@"reverse scroll reuses kept thumbnails", reverseRenders <= kSPDFMinimapWindowExtraPages * 2);
}

int main(int argc, char** argv) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        test_tiny_documents();
        test_huge_document_bounds();
        test_recentering();
        test_eviction();
        test_render_order();
        test_no_thrash_single_page_moves();
    }
    if (gFailureCount > 0) return 1;
    printf("SPDFMacMinimapWindowTests passed\n");
    return 0;
}
