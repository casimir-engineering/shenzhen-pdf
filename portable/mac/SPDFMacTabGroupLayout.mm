#import "SPDFMacTabStripViewPrivate.h"

@interface SPDFTabGroupLayout : NSObject
@property(nonatomic, strong) SPDFTabGroup* group;
@property(nonatomic) NSRect frame;
@property(nonatomic) NSRect header;
@property(nonatomic) NSInteger firstIndex;
@property(nonatomic) NSInteger capacity;
@property(nonatomic) BOOL visible;
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
    CGFloat gaps = MAX(0, (NSInteger)groups.count - 1) * 10;
    CGFloat available = [self tabAreaRightWithOverflow:NO] - [self leftInset];
    BOOL overflow = headers + gaps + expandedCount * 116 > available;
    available = MAX(0, [self tabAreaRightWithOverflow:overflow] - [self leftInset]);
    CGFloat width = MIN(260.0, MAX(112.0, floor((available - headers - gaps) / MAX(1, expandedCount)) - 4));
    CGFloat pitch = width + 4;
    SPDFTabGroupLayout* selectedGroup = nil;
    for (SPDFTabGroupLayout* layout in groups)
        if ([layout.members containsObject:@(self.selectedIndex)]) selectedGroup = layout;

    // Allocate slots before positioning groups. Left-to-right allocation lets
    // General consume a new group's second tab even though both would fit.
    // Preserve selection, then custom-group members, then General documents.
    NSMutableArray<SPDFTabGroupLayout*>* priority = [NSMutableArray array];
    if (selectedGroup) [priority addObject:selectedGroup];
    for (SPDFTabGroupLayout* layout in groups)
        if (layout != selectedGroup && !layout.group.general) [priority addObject:layout];
    for (SPDFTabGroupLayout* layout in groups)
        if (layout != selectedGroup && layout.group.general) [priority addObject:layout];
    NSInteger protectedTabs = selectedGroup.group.general ? 1 : MIN(2, selectedGroup.members.count);
    // A narrow strip may fit only the active tab, rather than its whole pair.
    if (selectedGroup) protectedTabs = MIN(protectedTabs, MAX(0, (NSInteger)floor(
        (available - NSWidth(selectedGroup.header) - 8) / pitch)));
    CGFloat reserved = protectedTabs * pitch;
    CGFloat admittedHeaders = 0;
    NSInteger admittedCount = 0;
    for (SPDFTabGroupLayout* layout in priority) {
        CGFloat cost = NSWidth(layout.header) + 8 + (admittedCount ? 10 : 0);
        if (admittedHeaders + cost + reserved > available) continue;
        layout.visible = YES;
        admittedHeaders += cost;
        ++admittedCount;
    }
    NSInteger slots = MAX(0, (NSInteger)floor((available - admittedHeaders) / pitch));
    if (selectedGroup.visible && slots) { selectedGroup.capacity = 1; --slots; }
    for (SPDFTabGroupLayout* layout in priority) {
        if (!layout.visible || layout.group.general) continue;
        NSInteger extra = MIN(slots, (NSInteger)layout.members.count - layout.capacity);
        layout.capacity += extra;
        slots -= extra;
    }
    for (SPDFTabGroupLayout* layout in priority) {
        if (!layout.visible || !layout.group.general) continue;
        NSInteger extra = MIN(slots, (NSInteger)layout.members.count - layout.capacity);
        layout.capacity += extra;
        slots -= extra;
    }

    CGFloat x = [self leftInset];
    for (SPDFTabGroupLayout* layout in groups) {
        if (!layout.visible) { layout.header = NSZeroRect; continue; }
        CGFloat start = x;
        layout.header = NSMakeRect(x + 4, 6, NSWidth(layout.header), 30);
        x += NSWidth(layout.header) + 4;
        NSArray<NSNumber*>* members = layout.members;
        NSInteger capacity = layout.capacity;
        NSUInteger selected = [members indexOfObject:@(self.selectedIndex)];
        NSInteger first = selected == NSNotFound ? 0 : MAX(0, (NSInteger)selected - (capacity - 1) / 2);
        first = MIN(first, MAX(0, (NSInteger)members.count - capacity));
        for (NSInteger j = 0; j < capacity; ++j) {
            layout.tabRects[members[(NSUInteger)(first + j)]] =
                [NSValue valueWithRect:NSMakeRect(x, 7, width, 28)];
            x += pitch;
        }
        layout.frame = NSMakeRect(start, 3, MAX(34, x - start + 4), 36);
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
            style.alignment = NSTextAlignmentCenter;
            style.lineBreakMode = NSLineBreakByTruncatingTail;
            NSDictionary* attributes = @{NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
                                        NSForegroundColorAttributeName: NSColor.labelColor,
                                        NSParagraphStyleAttributeName: style};
            CGFloat height = [layout.group.displayName sizeWithAttributes:attributes].height;
            [layout.group.displayName drawInRect:NSMakeRect(cx + 13, cy - height / 2,
                NSWidth(layout.header) - 29, height) withAttributes:attributes];
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
