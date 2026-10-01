#import "SPDFMacTabStripViewPrivate.h"

@interface SPDFTabGroupLayout : NSObject
@property(nonatomic, strong) SPDFTabGroup* group;
@property(nonatomic) NSRect frame;
@property(nonatomic) NSRect header;
@property(nonatomic) NSRect overflowFrame;
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
    for (NSUInteger i = 0; i < self.tabs.count; ++i) {
        SPDFDocumentTab* tab = self.tabs[i];
        if (tab.group.hidden) continue;
        if (current.group != tab.group) {
            current = [[SPDFTabGroupLayout alloc] init];
            current.group = tab.group;
            current.firstIndex = i;
            current.tabRects = [NSMutableDictionary dictionary];
            current.members = [NSMutableArray array];
            CGFloat labelWidth = MIN(tab.group.collectionBackups ? 172.0 : 100.0, ceil([tab.group.displayName sizeWithAttributes:
                @{NSFontAttributeName:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium]}].width) + (tab.group.collectionBackups ? 34 : 14));
            current.header = NSMakeRect(0, floor((NSHeight(self.bounds)-20)/2), labelWidth, 20);
            [groups addObject:current];
        }
        if (!tab.group.collapsed) [current.members addObject:@(i)];
    }
    CGFloat available = MAX(0, [self tabAreaRightWithOverflow:YES] - [self leftInset]);
    // Admit the expanded group's documents first. Other labels may use spare
    // room, but may never displace one more readable document tab.
    NSMutableArray<SPDFTabGroupLayout*>* priority = [NSMutableArray array];
    for (SPDFTabGroupLayout* layout in groups)
        if ([layout.members containsObject:@(self.selectedIndex)]) [priority addObject:layout];
    for (SPDFTabGroupLayout* layout in groups)
        if (!layout.group.collapsed && ![priority containsObject:layout]) [priority addObject:layout];
    for (SPDFTabGroupLayout* layout in groups) if (layout.group.collapsed) [priority addObject:layout];
    CGFloat remaining = available;
    for (SPDFTabGroupLayout* layout in priority) {
        CGFloat labelCost = NSWidth(layout.header) + (remaining < available ? 8 : 0);
        if (remaining < labelCost) continue;
        layout.visible = YES;
        remaining -= labelCost;
        NSMutableArray<NSNumber*>* candidates = [layout.members mutableCopy];
        NSNumber* selected = @(self.selectedIndex);
        if ([candidates containsObject:selected]) [candidates sortUsingComparator:^NSComparisonResult(NSNumber* a, NSNumber* b) {
            NSInteger left = labs(a.integerValue-self.selectedIndex), right = labs(b.integerValue-self.selectedIndex);
            return left < right ? NSOrderedAscending : left > right ? NSOrderedDescending : [a compare:b];
        }];
        CGFloat desired = 12;
        for (NSNumber* index in candidates) desired += [self preferredWidthForTabAtIndex:index.integerValue] + kTabGap;
        BOOL needsOverflow = candidates.count && desired > remaining;
        if (needsOverflow && remaining >= 28) { remaining -= 28; layout.overflowFrame = NSMakeRect(0,0,28,24); }
        CGFloat leadingGap = 12;
        for (NSNumber* index in candidates) {
            CGFloat width = [self preferredWidthForTabAtIndex:index.integerValue];
            if (remaining < width + leadingGap) continue;
            layout.tabRects[index] = [NSValue valueWithRect:NSMakeRect(0,0,width,24)];
            remaining -= width + leadingGap;
            leadingGap = kTabGap;
            ++layout.capacity;
        }
    }
    CGFloat x = [self leftInset];
    for (SPDFTabGroupLayout* layout in groups) {
        if (!layout.visible) { layout.header = NSZeroRect; continue; }
        CGFloat start = x;
        layout.header = NSMakeRect(x, floor((NSHeight(self.bounds)-20)/2), NSWidth(layout.header), 20);
        x += NSWidth(layout.header);
        BOOL first = YES;
        for (NSNumber* index in layout.members) {
            NSValue* admitted = layout.tabRects[index];
            if (!admitted) continue;
            x += first ? 12 : kTabGap;
            first = NO;
            CGFloat width = admitted.rectValue.size.width;
            layout.tabRects[index] = [NSValue valueWithRect:NSMakeRect(x, floor((NSHeight(self.bounds)-24)/2), width,24)];
            x += width;
        }
        if (!NSIsEmptyRect(layout.overflowFrame)) {
            layout.overflowFrame = NSMakeRect(x+4,floor((NSHeight(self.bounds)-24)/2),24,24);
            x += 28;
        }
        layout.frame = NSMakeRect(start, 4, x-start, NSHeight(self.bounds)-8);
        x += 8;
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
        [[accent colorWithAlphaComponent:0.16] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:layout.header xRadius:4 yRadius:4] fill];
        if (!layout.group.collapsed) {
            [accent setFill];
            [[NSBezierPath bezierPathWithRoundedRect:
                NSMakeRect(NSMinX(layout.frame),4,NSWidth(layout.frame),2) xRadius:1 yRadius:1] fill];
        }
        NSMutableParagraphStyle* style = [[NSMutableParagraphStyle alloc] init];
        style.alignment = NSTextAlignmentCenter;
        style.lineBreakMode = NSLineBreakByTruncatingTail;
        NSDictionary* attributes = @{NSFontAttributeName:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName:NSColor.labelColor, NSParagraphStyleAttributeName:style};
        if (!NSIsEmptyRect(layout.overflowFrame)) {
            NSString* remaining = [NSString stringWithFormat:@"+%lu",(unsigned long)(layout.members.count-layout.capacity)];
            [remaining drawInRect:NSInsetRect(layout.overflowFrame,0,4) withAttributes:attributes];
        }
        CGFloat iconSpace=layout.group.collectionBackups ? 20 : 0;
        if (iconSpace) {
            NSImage* icon=[NSImage imageWithSystemSymbolName:@"books.vertical" accessibilityDescription:nil];
            icon=[icon imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPaletteColors:@[NSColor.labelColor]]];
            [icon drawInRect:NSMakeRect(NSMinX(layout.header)+6,NSMidY(layout.header)-6,12,12)];
        }
        CGFloat height = [layout.group.displayName sizeWithAttributes:attributes].height;
        [layout.group.displayName drawInRect:NSMakeRect(NSMinX(layout.header)+7+iconSpace,
            NSMidY(layout.header)-height/2, NSWidth(layout.header)-14-iconSpace, height) withAttributes:attributes];
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
