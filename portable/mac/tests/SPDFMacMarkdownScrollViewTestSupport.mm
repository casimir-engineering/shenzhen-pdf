#import "../SPDFMacUIHelpers.h"

#import "../SPDFMacMarkdownPageCanvas.h"
#import "../SPDFMacMarkdownPagedView.h"

#include <assert.h>

void spdf_activate_window_for_view(NSView* view) {
    (void)view;
}

// Regression for the "page number changes but the visible page does not" bug:
// goToPageAtIndex:alignTop: used AppKit's minimum-scroll scrollRectToVisible:,
// which moved nothing when the target page was already partially visible while
// _currentPageIndex still advanced. Both alignTop values must now land the
// page's top at the viewport top with the PDF path's 12pt breathing room, and
// out-of-range indexes must clamp to the first/last page.
void spdf_assert_paged_view_go_to_page_scrolls(SPDFMacMarkdownPagedView* view) {
    SPDFMacMarkdownPageCanvas* canvas = (SPDFMacMarkdownPageCanvas*)view.documentView;
    assert(view.pageCount > 2);
    NSRect page = [canvas frameForPageAtIndex:2];
    BOOL alignTopValues[] = {YES, NO};
    for (size_t i = 0; i < 2; ++i) {
        // Park the viewport so page 2 peeks in at the bottom edge — the exact
        // partially-visible state the minimum scroll used to leave alone.
        [view.contentView
            scrollToPoint:NSMakePoint(0, NSMinY(page) - NSHeight(view.contentView.bounds) + 40.0)];
        [view reflectScrolledClipView:view.contentView];
        assert(NSIntersectsRect(view.documentVisibleRect, page));
        NSPoint before = view.documentVisibleRect.origin;
        [view goToPageAtIndex:2 alignTop:alignTopValues[i]];
        assert(!NSEqualPoints(view.documentVisibleRect.origin, before)); // the viewport actually moved
        assert(fabs(NSMinY(view.documentVisibleRect) - (NSMinY(page) - 12.0)) < 1.5); // top-aligned
        assert(view.currentPageIndex == 2);
    }
    [view goToPageAtIndex:-7 alignTop:YES];
    assert(view.currentPageIndex == 0);
    assert(NSMinY(view.documentVisibleRect) >= -0.5);
    [view goToPageAtIndex:(NSInteger)view.pageCount + 9 alignTop:NO];
    assert(view.currentPageIndex == (NSInteger)view.pageCount - 1);
    assert(NSMaxY(view.documentVisibleRect) <= view.documentCanvasSize.height + 0.5);
}

// Focused Markdown test executables do not link the complete app UI helpers.
// This minimal implementation supplies the shared superclass while production
// builds use SPDFMacUIHelpers.mm.
static NSMapTable<SPDFScrollView*, id<SPDFMacUIReader>>* TestScrollViewReaders(void) {
    static NSMapTable<SPDFScrollView*, id<SPDFMacUIReader>>* readers = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      readers = [NSMapTable weakToWeakObjectsMapTable];
    });
    return readers;
}

@implementation SPDFScrollView
- (id<SPDFMacUIReader>)reader {
    return [TestScrollViewReaders() objectForKey:self];
}
- (void)setReader:(id<SPDFMacUIReader>)reader {
    if (reader)
        [TestScrollViewReaders() setObject:reader forKey:self];
    else
        [TestScrollViewReaders() removeObjectForKey:self];
}
@end

// The production marker drawing lives in SPDFMacUIHelpers.mm; focused test
// executables only need the class and its reader wiring to exist.
@implementation SPDFFindMarkerScroller {
    __weak id<SPDFMacUIReader> _testReader;
}
- (id<SPDFMacUIReader>)reader {
    return _testReader;
}
- (void)setReader:(id<SPDFMacUIReader>)reader {
    _testReader = reader;
}
@end

// Same clamp behavior as the production SPDFDocumentClipView in
// SPDFMacUIHelpers.mm, which these focused executables do not link.
@implementation SPDFDocumentClipView

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _horizontalLockMinX = NAN;
        _horizontalLockMaxX = NAN;
    }
    return self;
}

- (NSRect)constrainBoundsRect:(NSRect)proposedBounds {
    NSRect bounds = [super constrainBoundsRect:proposedBounds];
    if (isfinite(_horizontalLockMinX))
        bounds.origin.x = MAX(_horizontalLockMinX, MIN(bounds.origin.x, MAX(_horizontalLockMinX, _horizontalLockMaxX)));
    return bounds;
}

@end
