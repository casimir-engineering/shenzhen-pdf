#import "SPDFMacSidebarHitProbe.h"
#import "SPDFMacSidebarModeControl.h"
@interface ShenzhenMacDelegate (SidebarHitProbeFixture)
- (void)setProbeHistory:(BOOL)value;
@end
@implementation ShenzhenMacDelegate (SidebarHitProbe)
- (NSUInteger)probeHistoryMouseClicks {
    NSUInteger failures = 0;
    for (NSNumber* y in @[@1,@7,@14,@21,@27]) {
        [self setProbeHistory:NO]; [_window.contentView layoutSubtreeIfNeeded];
        NSButton* history = nil;
        for (NSButton* row in _sidebarModeControl.accessibilityChildren)
            if ([row.accessibilityLabel isEqual:@"History"]) history = row;
        if (!history) { fprintf(stderr,"FAIL: missing History button\n"); failures++; }
        if (!history) continue;
        NSPoint point=[history convertPoint:NSMakePoint(NSMidX(history.bounds),y.doubleValue) toView:nil];
        NSEvent* down=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:point modifierFlags:0 timestamp:1
            windowNumber:_window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
        NSEvent* up=[NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:point modifierFlags:0 timestamp:1.01
            windowNumber:_window.windowNumber context:nil eventNumber:2 clickCount:1 pressure:0];
        [NSApp postEvent:up atStart:YES]; [history mouseDown:down];
        [_window.contentView layoutSubtreeIfNeeded];
        if (_sidebarModeControl.spdf_selectedSidebarMode != SPDFSidebarModeHistory) {
            fprintf(stderr,"FAIL: History did not activate at y=%.0f\n",y.doubleValue); failures++;
        }
    }
    return failures;
}
@end
