#import <Cocoa/Cocoa.h>

#import "SPDFMacModels.h"
#import "SPDFMacUIHelpers.h"

@interface SPDFTabStripView : NSView <NSDraggingSource, NSDraggingDestination>
@property(nonatomic, weak) id<SPDFMacUIReader> reader;
@property(nonatomic, copy) NSArray<SPDFDocumentTab*>* tabs;
@property(nonatomic) NSInteger selectedIndex;
@property(nonatomic) CGFloat reservedLeadingInset;
- (BOOL)containsTabOrControlAtPoint:(NSPoint)point;
@end
