#import <Cocoa/Cocoa.h>

#import "SPDFMacModels.h"

@interface SPDFPrintView : NSView
@property(nonatomic) spdf_document* document;
@property(nonatomic) NSInteger pageCount;
@property(nonatomic) CGFloat targetDPI;
@property(nonatomic, copy) NSArray<SPDFRenderedPage*>* fallbackPages;
@end
