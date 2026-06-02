#import <Cocoa/Cocoa.h>

#import "SPDFMacModels.h"
#import "SPDFMacUIHelpers.h"

@interface SPDFDocumentView : NSView <NSDraggingDestination>
@property(nonatomic, copy) NSArray<SPDFRenderedPage*>* pages;
@property(nonatomic) NSInteger currentPageIndex;
@property(nonatomic) CGFloat zoom;
@property(nonatomic) SPDFViewMode viewMode;
@property(nonatomic) CGFloat viewportWidthHint;
@property(nonatomic) CGFloat backingScale;
@property(nonatomic) NSInteger activeFindPageIndex;
@property(nonatomic) NSRect activeFindRect;
@property(nonatomic) CGFloat activeFindAlpha;
@property(nonatomic) BOOL presentationMode;
@property(nonatomic, copy) NSString* emptyMessage;
@property(nonatomic, weak) id<SPDFMacUIReader> reader;
- (NSSize)documentSizeForClipSize:(NSSize)clipSize;
- (NSRect)rectForPageAtIndex:(NSInteger)pageIndex;
- (NSInteger)pageIndexForVisibleRect:(NSRect)visibleRect;
- (BOOL)point:(NSPoint)point fallsInPage:(NSInteger*)pageIndex pagePoint:(NSPoint*)pagePoint;
- (void)cancelTransientInteraction;
@end
