#import "SPDFMacGroupManagementTable.h"
@implementation SPDFGroupManagementTable
- (BOOL)acceptsFirstMouse:(NSEvent*)event { (void)event; return YES; }
- (void)mouseDown:(NSEvent*)event {
    NSInteger row=[self rowAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if(row<0) { [super mouseDown:event]; return; }
    self.draggedDuringPress=NO;
    [self selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [self displayIfNeeded];
    // Keep AppKit's drag tracking/autoscroll, but commit navigation on release.
    SEL action=self.action; self.action=NULL;
    [super mouseDown:event]; self.action=action;
    NSInteger released=[self rowAtPoint:[self convertPoint:self.window.mouseLocationOutsideOfEventStream fromView:nil]];
    if(!self.draggedDuringPress && released==row) [NSApp sendAction:@selector(activateSelectedRow:) to:self.target from:self];
}
- (void)keyDown:(NSEvent*)event {
    if(event.keyCode==36 || event.keyCode==76) {
        [NSApp sendAction:@selector(activateSelectedRow:) to:self.target from:self]; return;
    }
    [super keyDown:event];
}
@end
@interface SPDFGroupExtensionBadge : NSView
@property(nonatomic,copy) NSString* text;
@end
@implementation SPDFGroupExtensionBadge
- (void)drawRect:(NSRect)dirty {
    (void)dirty;
    [[NSColor.labelColor colorWithAlphaComponent:.055] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:4 yRadius:4] fill];
    NSDictionary* attributes=@{NSFontAttributeName:[NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName:NSColor.labelColor};
    NSSize size=[self.text sizeWithAttributes:attributes];
    [self.text drawAtPoint:NSMakePoint(floor((NSWidth(self.bounds)-size.width)/2),floor((NSHeight(self.bounds)-size.height)/2))
        withAttributes:attributes];
}
@end
NSView* SPDFGroupDocumentBadge(NSString* path) {
    SPDFGroupExtensionBadge* badge=[SPDFGroupExtensionBadge new];
    NSString* extension=path.pathExtension.lowercaseString;
    badge.text=extension.length ? [@"." stringByAppendingString:extension] : @"file";
    badge.accessibilityElement=YES; badge.accessibilityRole=NSAccessibilityStaticTextRole;
    badge.accessibilityLabel=[NSString stringWithFormat:@"File type: %@",badge.text];
    badge.toolTip=badge.text;
    CGFloat width=MAX(36,ceil([badge.text sizeWithAttributes:@{NSFontAttributeName:[NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightMedium]}].width)+10);
    [badge.widthAnchor constraintEqualToConstant:width].active=YES;
    [badge.heightAnchor constraintEqualToConstant:18].active=YES;
    return badge;
}
