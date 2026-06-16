#import <Cocoa/Cocoa.h>

#import "SPDFMacModels.h"
#import "SPDFMacUIHelpers.h"

@interface SPDFMinimapView : NSView
@property(nonatomic, copy) NSArray<SPDFRenderedPage*>* pages;
@property(nonatomic, copy) NSArray<NSValue*>* documentPageRects;
@property(nonatomic) NSRect documentVisibleRect;
@property(nonatomic) CGFloat documentWidth;
@property(nonatomic) CGFloat documentHeight;
@property(nonatomic) CGFloat documentScale;
@property(nonatomic) NSInteger currentPageIndex;
@property(nonatomic) BOOL liveViewportOnly;
@property(nonatomic, weak) id<SPDFMacUIReader> reader;
- (NSArray<NSNumber*>*)visiblePageIndexes;
// Page-content zoom at which a thumbnail should be rendered so it is crisp at
// the page's displayed width in the strip (which is width-capped at 2.5x the
// median page). Returns 0 if the strip has no usable width yet.
- (CGFloat)thumbnailRenderZoomForPage:(SPDFRenderedPage*)page;
// Called when a page's minimap thumbnail finishes rendering: patches just that
// page into the cached strip (cheap) rather than forcing a full-strip rebuild.
- (void)noteThumbnailLoadedForPageIndex:(NSInteger)pageIndex;
@end
