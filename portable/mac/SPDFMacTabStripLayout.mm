#import "SPDFMacTabStripViewPrivate.h"
#import "SPDFMacSupport.h"

@implementation SPDFTabStripView (Layout)
- (CGFloat)tabWidth {
    NSInteger count = MAX(1, (NSInteger)[self visibleTabIndexes].count);
    CGFloat available = [self tabAreaWidthWithOverflow:[self hasOverflowTabs]] - (count - 1) * kTabGap;
    if (available <= 0) return kTabMinVisibleWidth;
    return MAX(1.0, MIN(kTabMaxWidth, floor(available / count)));
}

- (CGFloat)leftInset {
    return MAX(16.0, self.reservedLeadingInset > 0 ? self.reservedLeadingInset : 138.0);
}

- (NSRect)plusRect {
    CGFloat x = MAX([self leftInset] + kTabControlWidth + 16.0, NSWidth(self.bounds) - 42);
    x = MIN(x, MAX([self leftInset] + kTabControlWidth + 16.0, NSWidth(self.bounds) - 40));
    return NSMakeRect(x, 7, kTabControlWidth, 28);
}

- (NSRect)overflowRectAssumingVisible {
    CGFloat x = NSMinX([self plusRect]) - kTabControlWidth - kTabGap;
    x = MAX([self leftInset], x);
    return NSMakeRect(x, 7, kTabControlWidth, 28);
}

- (CGFloat)tabAreaRightWithOverflow:(BOOL)overflow {
    return overflow ? NSMinX([self overflowRectAssumingVisible]) - 8.0 : NSMinX([self plusRect]) - 10.0;
}

- (CGFloat)tabAreaWidthWithOverflow:(BOOL)overflow {
    return MAX(0.0, [self tabAreaRightWithOverflow:overflow] - [self leftInset]);
}

- (NSInteger)selectedIndexForLayout {
    NSInteger count = (NSInteger)self.tabs.count;
    if (count <= 0) return -1;
    if (self.selectedIndex < 0) return 0;
    return MIN(self.selectedIndex, count - 1);
}

- (NSInteger)visibleTabCapacityWithOverflow:(BOOL)overflow {
    NSInteger count = (NSInteger)self.tabs.count;
    if (count <= 0) return 0;

    CGFloat areaWidth = [self tabAreaWidthWithOverflow:overflow];
    if (areaWidth <= 0) return 1;

    NSInteger capacity = (NSInteger)floor((areaWidth + kTabGap) / (kTabMinVisibleWidth + kTabGap));
    return MAX(1, MIN(count, capacity));
}

- (BOOL)hasOverflowTabs {
    if ([self hasTabGroups]) return [self groupedHasOverflow];
    NSInteger count = (NSInteger)self.tabs.count;
    if (count <= 1) return NO;
    return [self visibleTabCapacityWithOverflow:NO] < count;
}

- (NSArray<NSNumber*>*)visibleTabIndexes {
    if ([self hasTabGroups]) return [self groupedVisibleTabIndexes];
    NSInteger count = (NSInteger)self.tabs.count;
    if (count <= 0) return @[];

    BOOL overflow = [self hasOverflowTabs];
    NSInteger visibleCount = overflow ? [self visibleTabCapacityWithOverflow:YES] : count;
    visibleCount = MAX(1, MIN(count, visibleCount));

    NSInteger selected = [self selectedIndexForLayout];
    NSInteger start = overflow ? selected - (visibleCount - 1) / 2 : 0;
    start = MAX(0, MIN(start, count - visibleCount));

    NSMutableArray<NSNumber*>* indexes = [NSMutableArray arrayWithCapacity:(NSUInteger)visibleCount];
    for (NSInteger i = 0; i < visibleCount; ++i) { [indexes addObject:@(start + i)]; }
    return indexes;
}

- (NSArray<NSNumber*>*)hiddenTabIndexes {
    if (![self hasOverflowTabs]) return @[];

    NSMutableIndexSet* visibleIndexes = [NSMutableIndexSet indexSet];
    for (NSNumber* index in [self visibleTabIndexes]) { [visibleIndexes addIndex:(NSUInteger)index.integerValue]; }

    NSMutableArray<NSNumber*>* hiddenIndexes = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; ++i) {
        if (![visibleIndexes containsIndex:(NSUInteger)i]) [hiddenIndexes addObject:@(i)];
    }
    return hiddenIndexes;
}

- (NSRect)overflowRect {
    return [self hasOverflowTabs] ? [self overflowRectAssumingVisible] : NSZeroRect;
}

- (NSRect)rectForTabAtIndex:(NSInteger)index {
    if ([self hasTabGroups]) return [self groupedRectForTabAtIndex:index];
    NSArray<NSNumber*>* visibleIndexes = [self visibleTabIndexes];
    NSUInteger visiblePosition = [visibleIndexes indexOfObject:@(index)];
    if (visiblePosition == NSNotFound) return NSZeroRect;

    CGFloat x = [self leftInset] + (CGFloat)visiblePosition * ([self tabWidth] + kTabGap);
    CGFloat maxRight = [self tabAreaRightWithOverflow:[self hasOverflowTabs]];
    CGFloat width = MIN([self tabWidth], maxRight - x);
    return NSMakeRect(x, 7, width, 28);
}

- (NSRect)interactionRectForTabRect:(NSRect)tabRect {
    if (NSIsEmptyRect(tabRect)) return NSZeroRect;
    NSRect rect = NSInsetRect(tabRect, -6.0, -10.0);
    rect.origin.y = NSMinY(self.bounds);
    rect.size.height = NSHeight(self.bounds);
    return rect;
}

- (NSInteger)tabIndexAtPoint:(NSPoint)point {
    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; ++i) {
        NSRect tabRect = [self rectForTabAtIndex:i];
        if (!NSIsEmptyRect(tabRect) && NSPointInRect(point, [self interactionRectForTabRect:tabRect])) return i;
    }
    return -1;
}

- (NSString*)titleForTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.tabs.count) return @"";
    SPDFDocumentTab* tab = self.tabs[(NSUInteger)index];
    if (tab.collectionVersionLabel.length) return tab.collectionVersionLabel;
    if (!tab.path.length) return spdf_display_label_without_extension(tab.title);

    if (!_displayTitles) {
        NSMutableArray<NSString*>* paths = [NSMutableArray arrayWithCapacity:self.tabs.count];
        for (SPDFDocumentTab* item in self.tabs) [paths addObject:item.path ?: @""];
        _displayTitles = spdf_disambiguated_display_names_for_paths(paths);
    }
    if (index < (NSInteger)_displayTitles.count && _displayTitles[(NSUInteger)index].length)
        return _displayTitles[(NSUInteger)index];
    return spdf_display_name_for_path(tab.path);
}

@end
