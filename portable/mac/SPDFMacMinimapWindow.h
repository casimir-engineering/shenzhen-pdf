#import <Foundation/Foundation.h>

// Windowed lazy loading for minimap thumbnails.
//
// Thumbnails are only rendered/kept for a window of pages around the visible
// strip range, so the minimap works at constant memory for any document size
// (the old design capped thumbnail drawing at 400 pages and never evicted).
// Pages outside the window draw the cheap placeholder; their strip slots keep
// exact geometry, so drag/click/zoom hit-testing is unaffected.
//
// The window has hysteresis: it recenters only once the visible range moves
// within kSPDFMinimapWindowRecenterMarginPages of a window edge, so scrolling
// one page at a time does not recompute (and re-evict) per step.

// Pages rendered beyond the visible strip range on each side.
extern const NSInteger kSPDFMinimapWindowExtraPages;
// Recenter once the visible range is within this many pages of a window edge.
extern const NSInteger kSPDFMinimapWindowRecenterMarginPages;
// Extra pages kept beyond the window before a thumbnail is evicted, so a
// recenter doesn't immediately drop pages the user may scroll straight back to.
extern const NSInteger kSPDFMinimapWindowEvictSlackPages;

typedef struct SPDFMinimapThumbnailWindow {
    NSInteger start;  // first page index in the window, inclusive
    NSInteger end;    // last page index in the window, inclusive; start > end means "no window yet"
} SPDFMinimapThumbnailWindow;

SPDFMinimapThumbnailWindow spdf_minimap_window_empty(void);
BOOL spdf_minimap_window_is_valid(SPDFMinimapThumbnailWindow window);
BOOL spdf_minimap_window_contains(SPDFMinimapThumbnailWindow window, NSInteger pageIndex);

// Window for the visible strip range [visibleFirst..visibleLast] (both
// inclusive, clamped to the document). Returns `previous` unchanged while it
// still covers the visible range plus the recenter margin (clamped to the
// document edges); otherwise recenters to visible ± kSPDFMinimapWindowExtraPages.
SPDFMinimapThumbnailWindow spdf_minimap_window_for_visible_range(NSInteger pageCount,
                                                                 NSInteger visibleFirst,
                                                                 NSInteger visibleLast,
                                                                 SPDFMinimapThumbnailWindow previous);

// YES when pageIndex is further than kSPDFMinimapWindowEvictSlackPages outside
// `window` and its thumbnail should be dropped. Never YES for an invalid window.
BOOL spdf_minimap_window_should_evict(SPDFMinimapThumbnailWindow window, NSInteger pageIndex);

// All page indexes of `window` ordered by render priority: pages nearest the
// visible range first (the visible pages themselves lead), ties by lower index.
NSArray<NSNumber*>* spdf_minimap_window_render_order(SPDFMinimapThumbnailWindow window,
                                                     NSInteger visibleFirst,
                                                     NSInteger visibleLast);
