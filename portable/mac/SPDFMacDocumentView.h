#import <Cocoa/Cocoa.h>

#import "SPDFMacModels.h"
#import "SPDFMacSelectionClick.h"
#import "SPDFMacUIHelpers.h"

@protocol SPDFMacDocumentViewReader <SPDFMacUIReader>
- (BOOL)documentViewSelectionChangedOnPage:(NSInteger)pageIndex
                                      from:(NSPoint)start
                                        to:(NSPoint)end
                               granularity:(SPDFMacSelectionGranularity)granularity;
@end

@interface SPDFDocumentView : NSView <NSDraggingDestination>
@property(nonatomic, copy) NSArray<SPDFRenderedPage*>* pages;
@property(nonatomic) NSInteger currentPageIndex;
@property(nonatomic) CGFloat zoom;
@property(nonatomic) CGFloat viewportWidthHint;
@property(nonatomic) CGFloat backingScale;
@property(nonatomic) NSInteger activeFindPageIndex;
@property(nonatomic) NSRect activeFindRect;
@property(nonatomic) CGFloat activeFindAlpha;
@property(nonatomic) BOOL presentationMode;
@property(nonatomic) BOOL liveZooming;
@property(nonatomic, copy) NSString* emptyMessage;
@property(nonatomic, weak) id<SPDFMacDocumentViewReader> reader;
- (NSSize)documentSizeForClipSize:(NSSize)clipSize;
// Image-only page refresh: swaps in an updated pages array whose page SIZES are
// unchanged (only a render image differs), keeping the layout cache valid and
// repainting just the changed page — unlike the `pages` setter, which fully
// invalidates layout and repaints the whole view. Use on render-completion /
// eviction hot paths to avoid an O(n) layout rebuild + full redraw per page.
- (void)refreshRenderedPages:(NSArray<SPDFRenderedPage*>*)pages changedPageIndex:(NSInteger)changedIndex;
- (NSRect)rectForPageAtIndex:(NSInteger)pageIndex;
- (NSInteger)pageIndexForVisibleRect:(NSRect)visibleRect;
- (BOOL)point:(NSPoint)point fallsInPage:(NSInteger*)pageIndex pagePoint:(NSPoint*)pagePoint;
- (void)cancelTransientInteraction;
// Re-resolve the pointer cursor (I-beam / hand / arrow) for the current mouse
// location, e.g. after a cursor-region cache fill or when a pan drag ends.
// No-op when the pointer is outside the view.
- (void)refreshCursorForMouseLocation;
@end
