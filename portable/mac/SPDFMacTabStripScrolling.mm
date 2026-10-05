#import "SPDFMacTabStripViewPrivate.h"

@implementation SPDFTabStripView (Scrolling)
- (NSRect)tabViewportRect {
    CGFloat left = NSIsEmptyRect(_tabPinnedViewport) ? [self leftInset] : NSMinX(_tabPinnedViewport);
    CGFloat right = NSIsEmptyRect(_tabPinnedViewport) ? [self tabAreaRightWithOverflow:YES] : NSMaxX(_tabPinnedViewport);
    BOOL overflow = [self hasTabGroups] && _tabContentWidth > right-left+.5;
    return NSMakeRect(left+(overflow ? 30 : 0),0,MAX(0,right-left-(overflow ? 60 : 0)),NSHeight(self.bounds));
}
- (NSRect)tabScrollIndicatorRectOnLeft:(BOOL)left {
    NSRect viewport = [self tabViewportRect];
    CGFloat x = left ? NSMinX(viewport)-30 : NSMaxX(viewport)+2;
    return NSMakeRect(x,floor((NSHeight(self.bounds)-28)/2),28,28);
}
- (NSInteger)tabScrollHiddenCountOnLeft:(BOOL)left {
    if (![self hasTabGroups]) return 0;
    NSInteger count = 0; NSRect viewport = [self tabViewportRect];
    for (id layout in [self groupLayouts]) {
        NSRect header = [[layout valueForKey:@"header"] rectValue];
        SPDFTabGroup* group = [layout valueForKey:@"group"];
        if (NSIsEmptyRect(_tabPinnedViewport) && group.collapsed && (left ? NSMinX(header)<NSMinX(viewport)-.5 : NSMaxX(header)>NSMaxX(viewport)+.5)) ++count;
        NSDictionary* rects = [layout valueForKey:@"tabRects"];
        for (NSValue* value in rects.allValues) {
            NSRect rect = value.rectValue;
            if (left ? NSMinX(rect)<NSMinX(viewport)-.5 : NSMaxX(rect)>NSMaxX(viewport)+.5) ++count;
        }
    }
    return count;
}
- (void)scrollTabStripBy:(CGFloat)delta {
    if (![self hasTabGroups] || fabs(delta)<.01) return;
    [self groupLayouts];
    CGFloat next = MIN(MAX(0,_tabScrollOffset+delta),MAX(0,_tabContentWidth-NSWidth([self tabViewportRect])));
    if (fabs(next-_tabScrollOffset)<.01) return;
    _tabScrollOffset = next; _groupLayout = nil; _revealSelectedTab = NO;
    if (self.tabScrollDidChange) self.tabScrollDidChange(next);
    _accessibilityChildrenSnapshot = nil;
    [self dismissHoverPanel]; [self rebuildReadOnlyTooltips]; [self setNeedsDisplay:YES];
}
- (void)scrollWheel:(NSEvent*)event {
    // Trackpads supply pixel deltas and momentum; a vertical mouse wheel is
    // equally useful over this horizontal-only surface. Never select a tab.
    CGFloat delta = fabs(event.scrollingDeltaX)>fabs(event.scrollingDeltaY)
        ? event.scrollingDeltaX : event.scrollingDeltaY;
    [self scrollTabStripBy:-delta*(event.hasPreciseScrollingDeltas ? 1 : 20)];
}
- (BOOL)handleTabScrollMouseDown:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    for (NSNumber* left in @[@YES,@NO]) {
        if ([self tabScrollHiddenCountOnLeft:left.boolValue] > 0 &&
            NSPointInRect(point,[self tabScrollIndicatorRectOnLeft:left.boolValue])) {
            [self scrollTabStripBy:(left.boolValue ? -1 : 1)*MAX(96,NSWidth([self tabViewportRect])*.7)];
            return YES;
        }
    }
    return NO;
}
- (NSRect)groupHideRect:(NSRect)header {
    return NSMakeRect(NSMaxX(header)-20,NSMidY(header)-10,20,20);
}
@end
