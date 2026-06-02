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
@property(nonatomic) SPDFViewMode viewMode;
@property(nonatomic) NSInteger currentPageIndex;
@property(nonatomic, weak) id<SPDFMacUIReader> reader;
- (NSArray<NSNumber*>*)visiblePageIndexes;
@end
