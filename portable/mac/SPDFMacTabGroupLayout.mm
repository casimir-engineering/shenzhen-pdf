#import "SPDFMacTabStripViewPrivate.h"

@interface SPDFTabGroupLayout : NSObject
@property(nonatomic, strong) SPDFTabGroup* group;
@property(nonatomic) NSRect frame;
@property(nonatomic) NSRect header;
@property(nonatomic) NSInteger firstIndex;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, NSValue*>* tabRects;
@property(nonatomic, strong) NSMutableArray<NSNumber*>* members;
@end
@implementation SPDFTabGroupLayout
@end

@implementation SPDFTabStripView (GroupLayout)
- (BOOL)hasTabGroups { return self.tabs.firstObject.group != nil; }
- (NSArray*)groupLayouts {
    if (![self hasTabGroups]) return nil;
    if (_groupLayout && NSEqualRects(_groupLayoutBounds, self.bounds) && _groupLayoutInset == [self leftInset])
        return _groupLayout;
    _groupLayoutBounds = self.bounds;
    _groupLayoutInset = [self leftInset];
    NSMutableArray<SPDFTabGroupLayout*>* groups = [NSMutableArray array];
    SPDFTabGroupLayout* current = nil;
    NSInteger expandedCount = 0;
    CGFloat headers = 0;
    for (NSUInteger i = 0; i < self.tabs.count; ++i) {
        SPDFDocumentTab* tab = self.tabs[i];
        if (current.group != tab.group) {
            current = [[SPDFTabGroupLayout alloc] init];
            current.group = tab.group;
            current.firstIndex = i;
            current.tabRects = [NSMutableDictionary dictionary];
            current.members = [NSMutableArray array];
            CGFloat headerWidth = 26;
            if (tab.group.collapsed)
                headerWidth += MIN(130.0, [tab.group.displayName sizeWithAttributes:
                    @{NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightMedium]}].width) + 9;
            current.header = NSMakeRect(0, 6, headerWidth, 30);
            headers += headerWidth + 8;
            [groups addObject:current];
        }
        if (!tab.group.collapsed) { ++expandedCount; [current.members addObject:@(i)]; }
    }
    CGFloat available = [self tabAreaRightWithOverflow:NO] - [self leftInset];
    BOOL overflow = headers + (groups.count - 1) * 10 + expandedCount * 118 > available;
    available = [self tabAreaRightWithOverflow:overflow] - [self leftInset];
    CGFloat usable = available - headers - (groups.count - 1) * 10;
    CGFloat width = MIN(260.0, MAX(112.0, floor(usable / MAX(1, expandedCount)) - 4));
    CGFloat x = [self leftInset];
    CGFloat right = [self tabAreaRightWithOverflow:overflow];
    NSInteger remainingTabs = expandedCount;
    for (NSUInteger g = 0; g < groups.count; ++g) {
        SPDFTabGroupLayout* layout = groups[g];
        CGFloat remainingHeaders = 0;
        for (NSUInteger next = g + 1; next < groups.count; ++next)
            remainingHeaders += NSWidth(groups[next].header) + 18;
        CGFloat start = x;
        layout.header = NSMakeRect(x + 4, 6, NSWidth(layout.header), 30);
        x += NSWidth(layout.header) + 4;
        NSArray<NSNumber*>* members = layout.members;
        if (members.count) {
            CGFloat space = MAX(0, right - x - remainingHeaders - 4);
            NSInteger capacity = MAX(0, (NSInteger)floor(space / (width + 4)));
            // Reserve one tab per later expanded group; the active group's
            // selected tab is then centered in its own visible slice.
            NSInteger laterTabs = remainingTabs - members.count;
            if (laterTabs && capacity > 1) capacity = MAX(1, capacity - MIN(laterTabs, (NSInteger)(groups.count - g - 1)));
            capacity = MIN((NSInteger)members.count, capacity);
            NSUInteger selected = [members indexOfObject:@(self.selectedIndex)];
            NSInteger first = selected == NSNotFound ? 0 : MAX(0, (NSInteger)selected - (capacity - 1) / 2);
            first = MIN(first, MAX(0, (NSInteger)members.count - capacity));
            for (NSInteger j = 0; j < capacity; ++j) {
                layout.tabRects[members[(NSUInteger)(first + j)]] =
                    [NSValue valueWithRect:NSMakeRect(x, 7, width, 28)];
                x += width + 4;
            }
            remainingTabs -= members.count;
        }
        layout.frame = NSMakeRect(start, 3, MAX(34, x - start + 4), 36);
        // A crowded strip puts complete groups in the existing overflow menu;
        // never paints a partial header underneath the plus/overflow controls.
        if (NSMaxX(layout.frame) > right) {
            layout.frame = NSZeroRect;
            layout.header = NSZeroRect;
            [layout.tabRects removeAllObjects];
        }
        x += 14;
    }
    _groupLayout = groups;
    return groups;
}
- (NSRect)groupedRectForTabAtIndex:(NSInteger)index {
    for (SPDFTabGroupLayout* layout in [self groupLayouts]) {
        NSValue* value = layout.tabRects[@(index)];
        if (value) return value.rectValue;
    }
    return NSZeroRect;
}
- (NSArray<NSNumber*>*)groupedVisibleTabIndexes {
    NSMutableArray* result = [NSMutableArray array];
    for (SPDFTabGroupLayout* layout in [self groupLayouts])
        [result addObjectsFromArray:[[layout.tabRects allKeys] sortedArrayUsingSelector:@selector(compare:)]];
    return result;
}
- (BOOL)groupedHasOverflow {
    for (SPDFTabGroupLayout* layout in [self groupLayouts]) {
        if (NSIsEmptyRect(layout.frame)) return YES;
        if (!layout.group.collapsed && layout.tabRects.count < layout.members.count)
            return YES;
    }
    return NO;
}
- (NSInteger)groupInsertionIndexForPoint:(NSPoint)point {
    for (SPDFTabGroupLayout* layout in [self groupLayouts]) {
        if (!NSIsEmptyRect(layout.frame) && point.x < NSMidX(layout.frame)) return layout.firstIndex;
    }
    return self.tabs.count;
}
- (CGFloat)groupInsertionBoundaryForPoint:(NSPoint)point {
    CGFloat last = [self leftInset];
    for (SPDFTabGroupLayout* layout in [self groupLayouts]) {
        if (NSIsEmptyRect(layout.frame)) continue;
        if (point.x < NSMidX(layout.frame)) return NSMinX(layout.frame) - 5;
        last = NSMaxX(layout.frame) + 5;
    }
    return last;
}
- (SPDFTabGroup*)groupAtPoint:(NSPoint)point headerOnly:(BOOL)headerOnly {
    for (SPDFTabGroupLayout* layout in [self groupLayouts])
        if (NSPointInRect(point, headerOnly ? layout.header : layout.frame)) return layout.group;
    return nil;
}
- (void)drawTabGroups {
    for (SPDFTabGroupLayout* layout in [self groupLayouts]) {
        if (NSIsEmptyRect(layout.frame)) continue;
        NSColor* accent = spdf_tab_group_accent(layout.group.colorName);
        [[accent colorWithAlphaComponent:0.17] setFill];
        NSBezierPath* shape = [NSBezierPath bezierPathWithRoundedRect:layout.frame xRadius:14 yRadius:14];
        [shape fill];
        [[accent colorWithAlphaComponent:0.85] setStroke];
        shape.lineWidth = 1;
        [shape stroke];
        // A single left disclosure is both the group handle and fold control;
        // its chevron never competes with the selected document's solid fill.
        CGFloat cx = NSMinX(layout.header) + 13, cy = NSMidY(layout.header);
        NSBezierPath* chevron = [NSBezierPath bezierPath];
        chevron.lineWidth = 1.8;
        chevron.lineCapStyle = NSLineCapStyleRound;
        chevron.lineJoinStyle = NSLineJoinStyleRound;
        if (layout.group.collapsed) {
            [chevron moveToPoint:NSMakePoint(cx - 2, cy + 4)];
            [chevron lineToPoint:NSMakePoint(cx + 2, cy)];
            [chevron lineToPoint:NSMakePoint(cx - 2, cy - 4)];
        } else {
            [chevron moveToPoint:NSMakePoint(cx - 4, cy + 2)];
            [chevron lineToPoint:NSMakePoint(cx, cy - 2)];
            [chevron lineToPoint:NSMakePoint(cx + 4, cy + 2)];
        }
        [NSColor.secondaryLabelColor setStroke];
        [chevron stroke];
        if (layout.group.collapsed) {
            NSMutableParagraphStyle* style = [[NSMutableParagraphStyle alloc] init];
            style.lineBreakMode = NSLineBreakByTruncatingTail;
            [layout.group.displayName drawInRect:NSMakeRect(cx + 13, cy - 7, NSWidth(layout.header) - 29, 17)
                withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
                                 NSForegroundColorAttributeName: NSColor.labelColor,
                                 NSParagraphStyleAttributeName: style}];
        }
    }
}
- (void)drawGroupDropPreview {
    if (!isnan(_groupDropBoundaryX)) {
        [spdf_tab_group_accent(_groupPreviewColor) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(_groupDropBoundaryX - 1.5, 5, 3, 32)
            xRadius:1.5 yRadius:1.5] fill];
    }
    NSRect target = NSZeroRect;
    if (_groupDropGroup) {
        for (SPDFTabGroupLayout* layout in [self groupLayouts])
            if (layout.group == _groupDropGroup) target = layout.frame;
    } else if (_groupDropTabIndex >= 0) {
        target = NSInsetRect([self rectForTabAtIndex:_groupDropTabIndex], -3, -3);
    }
    if (NSIsEmptyRect(target)) return;
    NSColor* accent = spdf_tab_group_accent(_groupDropGroup.colorName ?: _groupPreviewColor);
    [[accent colorWithAlphaComponent:0.20] setFill];
    NSBezierPath* outline = [NSBezierPath bezierPathWithRoundedRect:target xRadius:14 yRadius:14];
    [outline fill];
    [accent setStroke];
    outline.lineWidth = 3;
    [outline stroke];
}
@end
