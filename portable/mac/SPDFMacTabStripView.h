#import <Cocoa/Cocoa.h>

#import "SPDFMacModels.h"
#import "SPDFMacUIHelpers.h"

@interface SPDFTabStripView : NSView <NSDraggingSource, NSDraggingDestination>
@property(nonatomic, weak) id<SPDFMacUIReader> reader;
@property(nonatomic, copy) NSArray<SPDFDocumentTab*>* tabs;
@property(nonatomic) NSInteger selectedIndex;
@property(nonatomic) CGFloat reservedLeadingInset;
- (BOOL)containsTabOrControlAtPoint:(NSPoint)point;
- (void)dismissHoverPanel;
// Tab-activation focus claim, shared by the reader's selection chokepoint:
// moves keyboard focus to documentKeyView so typing right after a tab
// selection searches the document — but only when the current first responder
// is a passive holder (nil, the window itself, the strip, or one of
// parkedResponders, the views the tab-switch machinery itself parks focus on).
// A responder the user focused deliberately — the find, page, or
// sidebar-filter field's editor, the sidebar — is never robbed. Returns YES
// when documentKeyView took first responder.
+ (BOOL)claimFocusOnDocumentKeyView:(NSView*)documentKeyView
                             window:(NSWindow*)window
                           tabStrip:(NSView*)tabStrip
                   parkedResponders:(NSArray<NSResponder*>*)parkedResponders;
@end
