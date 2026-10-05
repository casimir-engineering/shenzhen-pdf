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
NSImage* SPDFGroupDocumentIcon(NSString* path) {
    // File-type icons need no access to the document and include installed type associations.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSImage* icon=[NSWorkspace.sharedWorkspace iconForFileType:path.pathExtension];
#pragma clang diagnostic pop
    return icon ?: [NSImage imageWithSystemSymbolName:@"doc" accessibilityDescription:nil];
}
