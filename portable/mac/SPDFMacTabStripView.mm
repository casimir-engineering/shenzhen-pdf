#import "SPDFMacTabStripView.h"

#import "SPDFMacSupport.h"
#import "SPDFMacTabStripGeometry.h"

#include <math.h>

static const CGFloat kTabGap = 6.0;
static const CGFloat kTabMinVisibleWidth = 112.0;
static const CGFloat kTabMaxWidth = 320.0;
static const CGFloat kTabControlWidth = 32.0;
// Read-only indicator dot. Shared by the draw and tooltip-rect sites so the
// hover hit-area stays aligned with the drawn dot if either is tweaked.
static const CGFloat kReadOnlyDotDiameter = 7.0;
// 50% less horizontal space around the read-only dot than before (was 12 / 5).
static const CGFloat kReadOnlyDotLeftInset = 6.0;
static const CGFloat kReadOnlyDotTitleGap = 2.5;
// Upper bound on simultaneously visible tabs, for stack-allocated geometry
// arrays. Visible tabs are >= kTabMinVisibleWidth wide, so even a 5K-wide
// strip shows far fewer than this.
static const NSInteger kMaxVisibleTabGeometry = 64;
static NSPasteboardType const SPDFTabDragPasteboardType = @"com.intuition.shenzhenpdf.tab";

static NSString* spdf_tab_strip_json_string_from_object(id object) {
    NSData* data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

static NSDictionary* spdf_tab_strip_json_dictionary_from_string(NSString* string) {
    NSData* data = [string dataUsingEncoding:NSUTF8StringEncoding];
    id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [object isKindOfClass:NSDictionary.class] ? object : nil;
}

@interface SPDFTabStripView ()
- (void)hideHoverPanel;
@end

@implementation SPDFTabStripView {
    NSTrackingArea* _trackingArea;
    NSPanel* _hoverPanel;
    NSTextField* _hoverLabel;
    NSInteger _hoverTabIndex;
    NSInteger _draggedTabIndex;
    NSInteger _dragSessionTabIndex;
    NSPoint _dragStartPoint;
    BOOL _draggingTab;
    BOOL _detachedTabDrag;
    BOOL _mouseDownInsideTab;
    NSInteger _dragSourceTabIndex;
    NSInteger _dragTargetTabIndex;
    CGFloat _dragPointerOffsetX;
    CGFloat _dragCurrentX;
    NSPoint _lastHoverPoint;
    BOOL _hasLastHoverPoint;
    BOOL _suppressingWindowMovementForTabGesture;
    BOOL _previousWindowMovableForTabGesture;
    NSInteger _middleClickTabIndex;
    NSString* _middleClickTabPath;
    // Insertion slot (see SPDFMacTabStripGeometry.h) for the yellow drop
    // indicator shown while a detached tab hovers over this strip; -1 hidden.
    NSInteger _dropIndicatorSlot;
    // Set by -performDragOperation: when a drop from this strip's own dragging
    // session was handled as an in-process move (continuous same-window
    // gesture), so the source-side session-ended callback neither closes nor
    // detaches the tab.
    BOOL _sameWindowTabDropHandled;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _hoverTabIndex = -1;
        _draggedTabIndex = -1;
        _dragSessionTabIndex = -1;
        _dragSourceTabIndex = -1;
        _dragTargetTabIndex = -1;
        _middleClickTabIndex = -1;
        _dropIndicatorSlot = -1;
        [self registerForDraggedTypes:@[ SPDFTabDragPasteboardType ]];
    }
    return self;
}

- (void)dealloc {
    [self hideHoverPanel];
}

- (void)viewWillMoveToWindow:(NSWindow*)newWindow {
    if (!newWindow) {
        [self restoreWindowMovementForTabGesture];
        [self hideHoverPanel];
    }
    [super viewWillMoveToWindow:newWindow];
}

- (BOOL)isFlipped {
    return NO;
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event {
    (void)event;
    return YES;
}

- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

- (void)suppressWindowMovementForTabGesture {
    if (_suppressingWindowMovementForTabGesture || !self.window) return;
    _previousWindowMovableForTabGesture = self.window.movable;
    self.window.movable = NO;
    _suppressingWindowMovementForTabGesture = YES;
}

- (void)restoreWindowMovementForTabGesture {
    if (!_suppressingWindowMovementForTabGesture || !self.window) return;
    self.window.movable = _previousWindowMovableForTabGesture;
    _suppressingWindowMovementForTabGesture = NO;
}

- (void)setHidden:(BOOL)hidden {
    if (hidden) {
        [self hideHoverPanel];
        [self clearDropIndicator];
    }
    [super setHidden:hidden];
}

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
    NSInteger count = (NSInteger)self.tabs.count;
    if (count <= 1) return NO;
    return [self visibleTabCapacityWithOverflow:NO] < count;
}

- (NSArray<NSNumber*>*)visibleTabIndexes {
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
    if (!tab.path.length) return spdf_display_label_without_extension(tab.title);

    NSMutableArray<NSString*>* paths = [NSMutableArray arrayWithCapacity:self.tabs.count];
    for (SPDFDocumentTab* item in self.tabs) [paths addObject:item.path ?: @""];
    NSArray<NSString*>* titles = spdf_disambiguated_display_names_for_paths(paths);
    if (index < (NSInteger)titles.count && titles[(NSUInteger)index].length) return titles[(NSUInteger)index];
    return spdf_display_name_for_path(tab.path);
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                                                         NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
    [self rebuildReadOnlyTooltips];
}

// Per-dot helper tooltip for read-only tabs. AppKit-managed (does not go through
// mouseMoved:), so it coexists with the full-title hover panel and never
// interferes with drag tracking. Rebuilt on any layout change.
- (void)rebuildReadOnlyTooltips {
    [self removeAllToolTips];
    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; ++i) {
        SPDFDocumentTab* tab = self.tabs[(NSUInteger)i];
        if (!tab.readOnly || tab.missingFile) continue;
        NSRect tabRect = [self rectForTabAtIndex:i];
        if (NSWidth(tabRect) < 40.0) continue;
        NSRect dotRect = [self readOnlyDotRectForTabRect:tabRect
                                                diameter:kReadOnlyDotDiameter
                                               leftInset:kReadOnlyDotLeftInset];
        // Pad the hit area so the small dot is easy to hover.
        [self addToolTipRect:NSInsetRect(dotRect, -3.0, -3.0) owner:self userData:NULL];
    }
}

- (NSString*)view:(NSView*)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void*)userData {
    (void)view;
    (void)tag;
    (void)point;
    (void)userData;
    return @"Read-only file. You're viewing a local copy, so opening it doesn't "
           @"prompt for access. Changes to the original are picked up automatically "
           @"(and on reopen). Editing will ask to save a copy.";
}

- (void)hideHoverPanel {
    _hoverTabIndex = -1;
    _hasLastHoverPoint = NO;
    if (_hoverPanel.parentWindow) [_hoverPanel.parentWindow removeChildWindow:_hoverPanel];
    [_hoverPanel orderOut:nil];
}

- (void)dismissHoverPanel {
    [self hideHoverPanel];
}

- (void)updateHoverForPoint:(NSPoint)point {
    NSInteger hovered = -1;
    _lastHoverPoint = point;
    _hasLastHoverPoint = YES;
    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; ++i) {
        NSRect tabRect = [self rectForTabAtIndex:i];
        if (NSWidth(tabRect) < 40.0) continue;
        if (NSPointInRect(point, tabRect)) {
            hovered = i;
            break;
        }
    }
    if (hovered == _hoverTabIndex) return;
    if (hovered >= 0) [self showHoverPanelForTabAtIndex:hovered];
    else [self hideHoverPanel];
}

- (void)showHoverPanelForTabAtIndex:(NSInteger)index {
    NSString* title = [self titleForTabAtIndex:index];
    if (!title.length || !self.window) {
        [self hideHoverPanel];
        return;
    }

    NSRect tabRect = [self rectForTabAtIndex:index];
    if (NSWidth(tabRect) <= 0) {
        [self hideHoverPanel];
        return;
    }

    if (!_hoverPanel) {
        _hoverPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 240, 26)
                                                 styleMask:NSWindowStyleMaskBorderless
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
        _hoverPanel.releasedWhenClosed = NO;
        _hoverPanel.hidesOnDeactivate = YES;
        _hoverPanel.hasShadow = YES;
        _hoverPanel.opaque = NO;
        _hoverPanel.backgroundColor = NSColor.clearColor;

        NSVisualEffectView* bubble = [[NSVisualEffectView alloc] initWithFrame:_hoverPanel.contentView.bounds];
        bubble.translatesAutoresizingMaskIntoConstraints = NO;
        bubble.material = NSVisualEffectMaterialPopover;
        bubble.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        bubble.state = NSVisualEffectStateActive;
        bubble.wantsLayer = YES;
        bubble.layer.cornerRadius = 8.0;
        bubble.layer.masksToBounds = YES;
        _hoverPanel.contentView = bubble;

        _hoverLabel = [NSTextField labelWithString:@""];
        _hoverLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _hoverLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _hoverLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
        [bubble addSubview:_hoverLabel];
        [NSLayoutConstraint activateConstraints:@[
            [_hoverLabel.leadingAnchor constraintEqualToAnchor:bubble.leadingAnchor constant:10],
            [_hoverLabel.trailingAnchor constraintEqualToAnchor:bubble.trailingAnchor constant:-10],
            [_hoverLabel.centerYAnchor constraintEqualToAnchor:bubble.centerYAnchor]
        ]];
    }

    _hoverLabel.stringValue = title;
    CGFloat width =
        MIN(420.0, MAX(96.0, [title sizeWithAttributes:@{NSFontAttributeName : _hoverLabel.font}].width + 24));
    NSRect tabScreenRect = [self.window convertRectToScreen:[self convertRect:tabRect toView:nil]];
    NSRect frame =
        NSMakeRect(floor(NSMidX(tabScreenRect) - width / 2.0), floor(NSMinY(tabScreenRect) - 31.0), width, 26.0);
    [_hoverPanel setFrame:frame display:NO];
    if (_hoverPanel.parentWindow != self.window) [self.window addChildWindow:_hoverPanel ordered:NSWindowAbove];
    // orderFront: on a child window pulls the whole parent group to the front of
    // its level, so hovering a tab in an UNFOCUSED window (the tracking area is
    // NSTrackingActiveAlways) would re-stack this window above other windows
    // without a click. Order the bubble relative to its parent instead: it
    // becomes visible without moving the parent in the z-order.
    [_hoverPanel orderWindow:NSWindowAbove relativeTo:self.window.windowNumber];
    _hoverTabIndex = index;
}

- (void)updateHoverForEvent:(NSEvent*)event {
    [self updateHoverForPoint:[self convertPoint:event.locationInWindow fromView:nil]];
}

- (void)setTabs:(NSArray<SPDFDocumentTab*>*)tabs {
    _tabs = [tabs copy];
    [self setNeedsDisplay:YES];
    [self rebuildReadOnlyTooltips];
    if (_hasLastHoverPoint && NSPointInRect(_lastHoverPoint, self.bounds)) [self updateHoverForPoint:_lastHoverPoint];
    else [self hideHoverPanel];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    _selectedIndex = selectedIndex;
    [self setNeedsDisplay:YES];
    [self rebuildReadOnlyTooltips];
}

- (NSRect)closeCircleRectForTabRect:(NSRect)tabRect {
    CGFloat diameter = 16.0;
    return NSMakeRect(floor(NSMaxX(tabRect) - 26.0), floor(NSMidY(tabRect) - diameter / 2.0), diameter, diameter);
}

// Read-only dot rect: inside the title's left inset, vertically centered. View
// is non-flipped (y grows up), so center via NSMidY like the close circle.
- (NSRect)readOnlyDotRectForTabRect:(NSRect)tabRect diameter:(CGFloat)diameter leftInset:(CGFloat)leftInset {
    return NSMakeRect(floor(NSMinX(tabRect) + leftInset), floor(NSMidY(tabRect) - diameter / 2.0), diameter, diameter);
}

- (void)beginTabTrackingAtIndex:(NSInteger)index point:(NSPoint)point tabRect:(NSRect)tabRect {
    [self suppressWindowMovementForTabGesture];
    _draggedTabIndex = index;
    _dragSourceTabIndex = index;
    _dragTargetTabIndex = index;
    _dragStartPoint = point;
    _dragPointerOffsetX = point.x - NSMinX(tabRect);
    _dragCurrentX = NSMinX(tabRect);
}

- (void)resetTabDragTracking {
    _draggedTabIndex = -1;
    _dragSourceTabIndex = -1;
    _dragTargetTabIndex = -1;
    _draggingTab = NO;
    _detachedTabDrag = NO;
    _mouseDownInsideTab = NO;
    _dragPointerOffsetX = 0;
    _dragCurrentX = 0;
    [self restoreWindowMovementForTabGesture];
    [self setNeedsDisplay:YES];
}

- (NSInteger)dragDestinationIndexForPoint:(NSPoint)point {
    NSArray<NSNumber*>* visibleIndexes = [self visibleTabIndexes];
    if (!visibleIndexes.count) return -1;

    NSInteger sourceIndex = _dragSourceTabIndex >= 0 ? _dragSourceTabIndex : _draggedTabIndex;
    NSInteger targetIndex = sourceIndex;
    for (NSNumber* indexNumber in visibleIndexes) {
        NSInteger index = indexNumber.integerValue;
        if (index == sourceIndex) continue;
        NSRect tabRect = [self rectForTabAtIndex:index];
        if (NSIsEmptyRect(tabRect)) continue;
        if (index < sourceIndex && point.x < NSMidX(tabRect)) {
            targetIndex = index;
            break;
        }
        if (index > sourceIndex && point.x > NSMidX(tabRect)) targetIndex = index;
    }
    return targetIndex;
}

// Collects the frames of the visible, non-collapsed tabs (left to right) into
// the caller-provided arrays, each sized kMaxVisibleTabGeometry. arrayIndexes
// maps each geometry slot back to the tab's index in self.tabs. Returns the
// number of entries filled. Shared by the drop-index computation and the
// insertion-indicator drawing so both always agree.
- (NSInteger)collectVisibleTabGeometryMinXs:(CGFloat*)minXs
                                      midXs:(CGFloat*)midXs
                                      maxXs:(CGFloat*)maxXs
                               arrayIndexes:(NSInteger*)arrayIndexes {
    NSInteger filled = 0;
    for (NSNumber* indexNumber in [self visibleTabIndexes]) {
        if (filled >= kMaxVisibleTabGeometry) break;
        NSInteger index = indexNumber.integerValue;
        NSRect tabRect = [self rectForTabAtIndex:index];
        if (NSIsEmptyRect(tabRect)) continue;
        minXs[filled] = NSMinX(tabRect);
        midXs[filled] = NSMidX(tabRect);
        maxXs[filled] = NSMaxX(tabRect);
        arrayIndexes[filled] = index;
        ++filled;
    }
    return filled;
}

- (NSInteger)dropIndexForPoint:(NSPoint)point {
    CGFloat minXs[kMaxVisibleTabGeometry], midXs[kMaxVisibleTabGeometry], maxXs[kMaxVisibleTabGeometry];
    NSInteger arrayIndexes[kMaxVisibleTabGeometry];
    NSInteger visibleCount = [self collectVisibleTabGeometryMinXs:minXs midXs:midXs maxXs:maxXs
                                                     arrayIndexes:arrayIndexes];
    if (visibleCount <= 0) return (NSInteger)self.tabs.count;

    NSInteger slot = spdf_tab_strip_drop_slot_for_x(point.x, midXs, visibleCount);
    if (slot < visibleCount) return arrayIndexes[slot];
    return MIN((NSInteger)self.tabs.count, arrayIndexes[visibleCount - 1] + 1);
}

- (void)updateDropIndicatorForPoint:(NSPoint)point {
    CGFloat minXs[kMaxVisibleTabGeometry], midXs[kMaxVisibleTabGeometry], maxXs[kMaxVisibleTabGeometry];
    NSInteger arrayIndexes[kMaxVisibleTabGeometry];
    NSInteger visibleCount = [self collectVisibleTabGeometryMinXs:minXs midXs:midXs maxXs:maxXs
                                                     arrayIndexes:arrayIndexes];
    NSInteger slot = visibleCount > 0 ? spdf_tab_strip_drop_slot_for_x(point.x, midXs, visibleCount) : -1;
    if (slot == _dropIndicatorSlot) return;
    _dropIndicatorSlot = slot;
    [self setNeedsDisplay:YES];
}

- (void)clearDropIndicator {
    if (_dropIndicatorSlot < 0) return;
    _dropIndicatorSlot = -1;
    [self setNeedsDisplay:YES];
}

- (BOOL)containsTabOrControlAtPoint:(NSPoint)point {
    if (NSPointInRect(point, NSInsetRect([self plusRect], -3.0, -4.0))) return YES;
    NSRect overflowRect = [self overflowRect];
    if (!NSIsEmptyRect(overflowRect) && NSPointInRect(point, NSInsetRect(overflowRect, -3.0, -4.0))) return YES;
    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; ++i) {
        NSRect tabRect = [self rectForTabAtIndex:i];
        if (!NSIsEmptyRect(tabRect) && NSPointInRect(point, [self interactionRectForTabRect:tabRect])) return YES;
    }
    return NO;
}

- (BOOL)isVisuallyReorderingTabs {
    return _draggingTab && !_detachedTabDrag && _dragSourceTabIndex >= 0 &&
           _dragSourceTabIndex < (NSInteger)self.tabs.count && _dragTargetTabIndex >= 0;
}

- (NSRect)visualRectForTabAtIndex:(NSInteger)index {
    NSRect baseRect = [self rectForTabAtIndex:index];
    if (NSIsEmptyRect(baseRect) || ![self isVisuallyReorderingTabs]) return baseRect;

    NSInteger source = _dragSourceTabIndex;
    NSInteger target = _dragTargetTabIndex;
    if (index == source) {
        CGFloat width = NSWidth(baseRect);
        CGFloat minX = [self leftInset];
        CGFloat maxX = MAX(minX, [self tabAreaRightWithOverflow:[self hasOverflowTabs]] - width);
        return NSMakeRect(floor(MAX(minX, MIN(_dragCurrentX, maxX))), NSMinY(baseRect), width, NSHeight(baseRect));
    }

    if (source < target && index > source && index <= target) {
        NSRect shifted = [self rectForTabAtIndex:index - 1];
        if (!NSIsEmptyRect(shifted)) return shifted;
    } else if (target < source && index >= target && index < source) {
        NSRect shifted = [self rectForTabAtIndex:index + 1];
        if (!NSIsEmptyRect(shifted)) return shifted;
    }
    return baseRect;
}

- (void)drawTabAtIndex:(NSInteger)index
                inRect:(NSRect)tabRect
            attributes:(NSDictionary*)attrs
         dimAttributes:(NSDictionary*)dimAttrs {
    if (index < 0 || index >= (NSInteger)self.tabs.count || NSWidth(tabRect) < 40.0) return;

    BOOL selected = index == self.selectedIndex;
    SPDFDocumentTab* tab = self.tabs[(NSUInteger)index];
    BOOL missing = tab.missingFile;
    NSColor* fill;
    NSColor* stroke = nil;
    if (missing) {
        fill = [NSColor.systemRedColor colorWithAlphaComponent:selected ? 0.36 : 0.22];
        stroke = [NSColor.systemRedColor colorWithAlphaComponent:selected ? 0.95 : 0.65];
    } else if (selected) {
        fill = [NSColor.controlAccentColor colorWithAlphaComponent:0.34];
        stroke = [NSColor.controlAccentColor colorWithAlphaComponent:0.95];
    } else {
        fill = NSColor.controlBackgroundColor;
    }
    NSBezierPath* tabPath = [NSBezierPath bezierPathWithRoundedRect:tabRect xRadius:7 yRadius:7];
    [fill setFill];
    [tabPath fill];
    if (stroke) {
        [stroke setStroke];
        tabPath.lineWidth = selected ? 1.4 : 1.0;
        [tabPath stroke];
    }

    NSString* title = [self titleForTabAtIndex:index];
    NSDictionary* titleAttrs = selected || missing ? attrs : dimAttrs;
    CGFloat titleHeight = [title sizeWithAttributes:titleAttrs].height;
    CGFloat leftInset = 12.0;
    CGFloat rightInset = 34.0;

    // Read-only indicator: a small orange dot immediately left of the title for
    // any tab whose SOURCE is read-only (the app renders a copy without
    // prompting). Drawn per-tab so it follows reorder; never for a missing tab
    // (the red tint already owns that case). systemOrange is theme-correct.
    BOOL showReadOnlyDot = tab.readOnly && !missing;
    if (showReadOnlyDot) {
        // -rebuildReadOnlyTooltips computes the same rect via kReadOnlyDotLeftInset,
        // so the hover hit-area stays aligned with the drawn dot.
        NSRect dotRect = [self readOnlyDotRectForTabRect:tabRect
                                                diameter:kReadOnlyDotDiameter
                                               leftInset:kReadOnlyDotLeftInset];
        [NSColor.systemOrangeColor setFill];
        [[NSBezierPath bezierPathWithOvalInRect:dotRect] fill];
        // Reserve space so the (middle-ellipsis) title sits just right of the dot.
        leftInset = kReadOnlyDotLeftInset + kReadOnlyDotDiameter + kReadOnlyDotTitleGap;
    }

    NSRect titleRect = NSMakeRect(NSMinX(tabRect) + leftInset, floor(NSMidY(tabRect) - titleHeight / 2.0),
                                  MAX(1.0, NSWidth(tabRect) - leftInset - rightInset), titleHeight + 2);
    [title drawWithRect:titleRect
                options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine
             attributes:titleAttrs];

    NSRect closeRect = [self closeCircleRectForTabRect:tabRect];
    NSBezierPath* closeCircle = [NSBezierPath bezierPathWithOvalInRect:closeRect];
    NSColor* closeFill = selected ? [NSColor.labelColor colorWithAlphaComponent:0.16]
                                  : [NSColor.secondaryLabelColor colorWithAlphaComponent:0.13];
    [closeFill setFill];
    [closeCircle fill];

    NSColor* closeStroke = selected ? [NSColor.labelColor colorWithAlphaComponent:0.76]
                                    : [NSColor.secondaryLabelColor colorWithAlphaComponent:0.82];
    [closeStroke setStroke];
    NSBezierPath* closeX = [NSBezierPath bezierPath];
    closeX.lineWidth = 1.35;
    [closeX moveToPoint:NSMakePoint(NSMidX(closeRect) - 3.2, NSMidY(closeRect) - 3.2)];
    [closeX lineToPoint:NSMakePoint(NSMidX(closeRect) + 3.2, NSMidY(closeRect) + 3.2)];
    [closeX moveToPoint:NSMakePoint(NSMidX(closeRect) + 3.2, NSMidY(closeRect) - 3.2)];
    [closeX lineToPoint:NSMakePoint(NSMidX(closeRect) - 3.2, NSMidY(closeRect) + 3.2)];
    [closeX stroke];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor clearColor] setFill];
    NSRectFill(self.bounds);

    NSMutableParagraphStyle* tabTitleStyle = [[NSMutableParagraphStyle alloc] init];
    tabTitleStyle.alignment = NSTextAlignmentCenter;
    tabTitleStyle.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSDictionary* attrs = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : NSColor.labelColor,
        NSParagraphStyleAttributeName : tabTitleStyle
    };
    NSDictionary* dimAttrs = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12],
        NSForegroundColorAttributeName : NSColor.secondaryLabelColor,
        NSParagraphStyleAttributeName : tabTitleStyle
    };

    NSInteger draggedIndex = [self isVisuallyReorderingTabs] ? _dragSourceTabIndex : -1;
    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; ++i) {
        if (i == draggedIndex) continue;
        [self drawTabAtIndex:i inRect:[self visualRectForTabAtIndex:i] attributes:attrs dimAttributes:dimAttrs];
    }
    if (draggedIndex >= 0) {
        [self drawTabAtIndex:draggedIndex
                      inRect:[self visualRectForTabAtIndex:draggedIndex]
                  attributes:attrs
               dimAttributes:dimAttrs];
    }

    NSRect overflowRect = [self overflowRect];
    if (!NSIsEmptyRect(overflowRect)) {
        [NSColor.controlBackgroundColor setFill];
        NSBezierPath* overflowPath = [NSBezierPath bezierPathWithRoundedRect:overflowRect xRadius:9 yRadius:9];
        [overflowPath fill];
        [[NSColor.separatorColor colorWithAlphaComponent:0.45] setStroke];
        overflowPath.lineWidth = 1.0;
        [overflowPath stroke];

        [[NSColor.labelColor colorWithAlphaComponent:0.78] setFill];
        CGFloat dotDiameter = 3.0;
        CGFloat dotGap = 3.0;
        CGFloat x = floor(NSMidX(overflowRect) - dotDiameter / 2.0);
        CGFloat startY = floor(NSMidY(overflowRect) - dotDiameter * 1.5 - dotGap);
        for (NSInteger i = 0; i < 3; ++i) {
            NSRect dot = NSMakeRect(x, startY + (dotDiameter + dotGap) * i, dotDiameter, dotDiameter);
            [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
        }
    }

    NSRect plusRect = [self plusRect];
    [NSColor.controlBackgroundColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:plusRect xRadius:9 yRadius:9] fill];
    NSDictionary* plusAttrs = @{
        NSFontAttributeName : [NSFont systemFontOfSize:16 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : NSColor.labelColor
    };
    NSSize plusSize = [@"+" sizeWithAttributes:plusAttrs];
    [@"+" drawAtPoint:NSMakePoint(floor(NSMidX(plusRect) - plusSize.width / 2.0),
                                  floor(NSMidY(plusRect) - plusSize.height / 2.0))
        withAttributes:plusAttrs];

    // Drop-insertion indicator: a thin rounded systemYellow line, full tab
    // height, centered in the gap where a hovering detached tab would insert.
    // Drawn last as a pure overlay so the existing tabs never shift.
    if (_dropIndicatorSlot >= 0) {
        CGFloat minXs[kMaxVisibleTabGeometry], midXs[kMaxVisibleTabGeometry], maxXs[kMaxVisibleTabGeometry];
        NSInteger arrayIndexes[kMaxVisibleTabGeometry];
        NSInteger visibleCount = [self collectVisibleTabGeometryMinXs:minXs midXs:midXs maxXs:maxXs
                                                         arrayIndexes:arrayIndexes];
        CGFloat centerX = spdf_tab_strip_drop_indicator_center_x(_dropIndicatorSlot, minXs, maxXs, visibleCount,
                                                                 kTabGap);
        if (!isnan(centerX)) {
            NSRect anyTabRect = [self rectForTabAtIndex:arrayIndexes[0]];
            NSRect lineRect = NSMakeRect(floor(centerX) - 1.0, NSMinY(anyTabRect), 2.0, NSHeight(anyTabRect));
            [NSColor.systemYellowColor setFill];
            [[NSBezierPath bezierPathWithRoundedRect:lineRect xRadius:1.0 yRadius:1.0] fill];
        }
    }
}

- (void)showOverflowMenuWithEvent:(NSEvent*)event {
    NSArray<NSNumber*>* hiddenIndexes = [self hiddenTabIndexes];
    if (!hiddenIndexes.count) return;

    [self hideHoverPanel];

    NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Hidden Tabs"];
    for (NSNumber* indexNumber in hiddenIndexes) {
        NSInteger index = indexNumber.integerValue;
        NSString* title = [self titleForTabAtIndex:index];
        if (!title.length) title = @"Untitled";

        NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(overflowTabMenuItemSelected:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = indexNumber;
        item.state = index == self.selectedIndex ? NSControlStateValueOn : NSControlStateValueOff;
        spdf_set_menu_item_system_symbol(item, @"doc.text");
        [menu addItem:item];
    }

    NSRect overflowRect = [self overflowRect];
    NSEvent* menuEvent = event;
    if (!menuEvent) {
        NSPoint windowPoint = [self convertPoint:NSMakePoint(NSMinX(overflowRect), NSMinY(overflowRect)) toView:nil];
        menuEvent = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                       location:windowPoint
                                  modifierFlags:0
                                      timestamp:NSProcessInfo.processInfo.systemUptime
                                   windowNumber:self.window.windowNumber
                                        context:nil
                                    eventNumber:0
                                     clickCount:1
                                       pressure:1.0];
    }
    [NSMenu popUpContextMenu:menu withEvent:menuEvent forView:self];
}

- (void)overflowTabMenuItemSelected:(NSMenuItem*)sender {
    NSNumber* indexNumber = [sender.representedObject isKindOfClass:NSNumber.class] ? sender.representedObject : nil;
    if (!indexNumber) return;
    [self.reader selectTabAtIndex:indexNumber.integerValue];
}

- (void)tabContextShowInFolder:(NSMenuItem*)sender {
    NSNumber* indexNumber = [sender.representedObject isKindOfClass:NSNumber.class] ? sender.representedObject : nil;
    if (!indexNumber) return;
    [self.reader showTabInFolderAtIndex:indexNumber.integerValue];
}

- (void)tabContextCopyFile:(NSMenuItem*)sender {
    NSNumber* indexNumber = [sender.representedObject isKindOfClass:NSNumber.class] ? sender.representedObject : nil;
    if (!indexNumber) return;
    [self.reader copyTabFileToPasteboardAtIndex:indexNumber.integerValue];
}

- (void)tabContextCopyPath:(NSMenuItem*)sender {
    NSNumber* indexNumber = [sender.representedObject isKindOfClass:NSNumber.class] ? sender.representedObject : nil;
    if (!indexNumber) return;
    [self.reader copyTabPathToPasteboardAtIndex:indexNumber.integerValue];
}

- (void)tabContextCopyTitle:(NSMenuItem*)sender {
    NSNumber* indexNumber = [sender.representedObject isKindOfClass:NSNumber.class] ? sender.representedObject : nil;
    if (!indexNumber) return;
    [self.reader copyTabTitleToPasteboardAtIndex:indexNumber.integerValue];
}

- (void)startTabDragSessionWithEvent:(NSEvent*)event {
    if (_draggedTabIndex < 0 || _draggedTabIndex >= (NSInteger)self.tabs.count) return;
    SPDFDocumentTab* snapshot = [self.reader tabSnapshotForDragAtIndex:_draggedTabIndex];
    if (!snapshot.path.length) return;

    NSDictionary* payload = spdf_dictionary_from_tab(snapshot, self.window.windowNumber);
    NSString* json = spdf_tab_strip_json_string_from_object(payload);
    if (!json.length) return;

    NSPasteboardItem* item = [[NSPasteboardItem alloc] init];
    [item setString:json forType:SPDFTabDragPasteboardType];
    NSDraggingItem* dragItem = [[NSDraggingItem alloc] initWithPasteboardWriter:item];
    NSRect tabRect = [self rectForTabAtIndex:_draggedTabIndex];
    NSImage* image = [[NSImage alloc] initWithSize:tabRect.size];
    [image lockFocus];
    [[NSColor.controlAccentColor colorWithAlphaComponent:0.22] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, NSWidth(tabRect), NSHeight(tabRect)) xRadius:7
                                     yRadius:7] fill];
    NSString* title = [self titleForTabAtIndex:_draggedTabIndex];
    NSMutableParagraphStyle* style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    style.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSDictionary* attrs = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : NSColor.labelColor,
        NSParagraphStyleAttributeName : style
    };
    [title drawWithRect:NSInsetRect(NSMakeRect(0, 0, NSWidth(tabRect), NSHeight(tabRect)), 18, 7)
                options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine
             attributes:attrs];
    [image unlockFocus];
    [dragItem setDraggingFrame:tabRect contents:image];

    _dragSessionTabIndex = _draggedTabIndex;
    _sameWindowTabDropHandled = NO;
    _detachedTabDrag = YES;
    [self setNeedsDisplay:YES];
    NSDraggingSession* session = [self beginDraggingSessionWithItems:@[ dragItem ] event:event source:self];
    // No slide-back animation on cancel/fail: a failed drop detaches into a new
    // window at the drop point (animating the image back first would contradict
    // that), and -draggingSession:endedAtPoint:operation: then runs at the
    // instant of an Escape cancel, while the key/button state that identifies
    // the cancellation (see -tabDragSessionEndedByCancellation) is still live.
    session.animatesToStartingPositionsOnCancelOrFail = NO;
}

- (NSDragOperation)draggingSession:(NSDraggingSession*)session
    sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    (void)session;
    (void)context;
    return NSDragOperationMove;
}

// YES when the dragging session that just ended was cancelled (Escape or
// Cmd-.) rather than concluded by a drop: a release ends the drag BECAUSE the
// left button went up, so at cancel time the button is still physically down.
// The Escape key state is checked as well in case the button-up races the
// ended callback. Both are point-in-time state queries (no event tap, no
// Accessibility/Input Monitoring permission). Sessions are created with
// animatesToStartingPositionsOnCancelOrFail = NO, so this runs at the moment
// of cancellation while that state is still current.
- (BOOL)tabDragSessionEndedByCancellation {
    if ((NSEvent.pressedMouseButtons & 0x1) != 0) return YES;
    return CGEventSourceKeyState(kCGEventSourceStateCombinedSessionState, 53 /* kVK_Escape */);
}

- (void)draggingSession:(NSDraggingSession*)session
           endedAtPoint:(NSPoint)screenPoint
              operation:(NSDragOperation)operation {
    (void)session;
    (void)screenPoint;
    NSInteger index = _dragSessionTabIndex;
    BOOL sameWindowDropHandled = _sameWindowTabDropHandled;
    _dragSessionTabIndex = -1;
    _sameWindowTabDropHandled = NO;
    [self resetTabDragTracking];
    if (index < 0 || sameWindowDropHandled) return;
    if (operation == NSDragOperationMove) {
        [self.reader closeTabAtIndex:index];
        return;
    }
    if (operation != NSDragOperationNone) return;
    if ([self tabDragSessionEndedByCancellation]) return;
    [self.reader detachTabAtIndex:index];
}

// YES when the dragged tab originated from THIS strip (same process and same
// window number in the pasteboard payload): the drop is then handled as an
// in-process move of the live tab instead of a pasteboard-copy insert.
- (BOOL)isSameWindowTabDragFromSender:(id<NSDraggingInfo>)sender {
    NSString* json = [sender.draggingPasteboard stringForType:SPDFTabDragPasteboardType];
    NSDictionary* payload = spdf_tab_strip_json_dictionary_from_string(json);
    NSNumber* sourcePID = [payload[@"sourcePID"] isKindOfClass:NSNumber.class] ? payload[@"sourcePID"] : nil;
    NSNumber* sourceWindow = [payload[@"sourceWindow"] isKindOfClass:NSNumber.class] ? payload[@"sourceWindow"] : nil;
    if (!sourceWindow) return NO;
    if (sourcePID && sourcePID.integerValue != NSProcessInfo.processInfo.processIdentifier) return NO;
    return sourceWindow.integerValue == self.window.windowNumber;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    // Same-window drags are accepted too: a tab torn off this strip and (still
    // held) dragged back in reinserts in place — the continuous-gesture
    // counterpart of the cross-window reattach, with the same indicator.
    NSDragOperation operation = NSDragOperationNone;
    if ([sender.draggingPasteboard availableTypeFromArray:@[ SPDFTabDragPasteboardType ]]) {
        operation = NSDragOperationMove;
    }
    // Browser-style insertion indicator: while a detached tab hovers over this
    // strip, mark the gap it would insert into; the drop below uses the same
    // -dropIndexForPoint: geometry, so indicator and drop always agree.
    if (operation == NSDragOperationMove) {
        [self updateDropIndicatorForPoint:[self convertPoint:sender.draggingLocation fromView:nil]];
    } else {
        [self clearDropIndicator];
    }
    return operation;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    return [self draggingEntered:sender];
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    (void)sender;
    [self clearDropIndicator];
}

- (void)draggingEnded:(id<NSDraggingInfo>)sender {
    (void)sender;
    [self clearDropIndicator];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    [self clearDropIndicator];
    NSString* json = [sender.draggingPasteboard stringForType:SPDFTabDragPasteboardType];
    SPDFDocumentTab* tab = spdf_tab_from_dictionary(spdf_tab_strip_json_dictionary_from_string(json));
    if (!tab.path.length) return NO;
    NSPoint point = [self convertPoint:sender.draggingLocation fromView:nil];
    NSInteger insertionIndex = [self dropIndexForPoint:point];
    if ([self isSameWindowTabDragFromSender:sender]) {
        // Continuous same-window gesture: the tab never left this window, so
        // move the LIVE tab (no reload, no process spawn) instead of round-
        // tripping through the pasteboard copy. The insertion index was
        // computed with the dragged tab still occupying its slot; map it to
        // the post-removal index. Always report the drop handled: the flag
        // stops the session-ended callback from closing or detaching, and the
        // downstream operation for a NO here would be ambiguous.
        _sameWindowTabDropHandled = YES;
        NSInteger count = (NSInteger)self.tabs.count;
        NSInteger sourceIndex = _dragSessionTabIndex;
        if (sourceIndex < 0 || sourceIndex >= count ||
            ![(self.tabs[(NSUInteger)sourceIndex].path ?: @"") isEqualToString:tab.path]) {
            // Tabs changed under the drag (async strip refresh): relocate the
            // live tab by path so the right one moves.
            sourceIndex = -1;
            for (NSInteger i = 0; i < count; ++i) {
                if ([(self.tabs[(NSUInteger)i].path ?: @"") isEqualToString:tab.path]) {
                    sourceIndex = i;
                    break;
                }
            }
        }
        if (sourceIndex < 0) {
            // The live tab vanished mid-drag; fall back to inserting the
            // pasteboard snapshot so the drop still lands.
            [self.reader insertDraggedTab:tab atIndex:insertionIndex];
            return YES;
        }
        NSInteger targetIndex = spdf_tab_strip_same_window_move_index(insertionIndex, sourceIndex, count);
        if (targetIndex != sourceIndex) [self.reader moveTabFromIndex:sourceIndex toIndex:targetIndex];
        return YES;
    }
    [self.reader insertDraggedTab:tab atIndex:insertionIndex];
    return YES;
}

- (void)mouseDown:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    _draggedTabIndex = -1;
    _dragSourceTabIndex = -1;
    _dragTargetTabIndex = -1;
    _draggingTab = NO;
    _detachedTabDrag = NO;
    _mouseDownInsideTab = NO;

    if (NSPointInRect(point, [self plusRect])) {
        [self.reader newTabRequested:self];
        return;
    }

    NSRect overflowRect = [self overflowRect];
    if (!NSIsEmptyRect(overflowRect) && NSPointInRect(point, overflowRect)) {
        [self showOverflowMenuWithEvent:event];
        return;
    }

    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; ++i) {
        NSRect tabRect = [self rectForTabAtIndex:i];
        if (NSIsEmptyRect(tabRect)) continue;
        if (!NSPointInRect(point, [self interactionRectForTabRect:tabRect])) continue;
        _mouseDownInsideTab = YES;
        NSRect closeRect = NSInsetRect([self closeCircleRectForTabRect:tabRect], -5.0, -5.0);
        if (NSPointInRect(point, closeRect)) {
            [self.reader closeTabAtIndex:i];
        } else {
            [self.reader selectTabAtIndex:i];
            [self beginTabTrackingAtIndex:i point:point tabRect:tabRect];
        }
        return;
    }

    [self hideHoverPanel];
}

- (void)rightMouseDown:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger tabIndex = [self tabIndexAtPoint:point];
    if (tabIndex < 0) {
        [self hideHoverPanel];
        [super rightMouseDown:event];
        return;
    }

    [self hideHoverPanel];
    NSNumber* indexNumber = @(tabIndex);
    NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Tab"];
    NSMenuItem* showInFolder = [menu addItemWithTitle:@"Show in Folder"
                                               action:@selector(tabContextShowInFolder:)
                                        keyEquivalent:@""];
    showInFolder.target = self;
    showInFolder.representedObject = indexNumber;
    NSMenuItem* copy = [menu addItemWithTitle:@"Copy" action:@selector(tabContextCopyFile:) keyEquivalent:@""];
    copy.target = self;
    copy.representedObject = indexNumber;
    NSMenuItem* copyTitle = [menu addItemWithTitle:@"Copy Title"
                                            action:@selector(tabContextCopyTitle:)
                                     keyEquivalent:@""];
    copyTitle.target = self;
    copyTitle.representedObject = indexNumber;
    NSMenuItem* copyPath = [menu addItemWithTitle:@"Copy Path" action:@selector(tabContextCopyPath:) keyEquivalent:@""];
    copyPath.target = self;
    copyPath.representedObject = indexNumber;
    spdf_set_menu_item_system_symbol(showInFolder, @"folder");
    spdf_set_menu_item_system_symbol(copy, @"doc.on.doc");
    spdf_set_menu_item_system_symbol(copyTitle, @"character.cursor.ibeam");
    spdf_set_menu_item_system_symbol(copyPath, @"doc.text");
    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
}

- (void)mouseDragged:(NSEvent*)event {
    if (_draggedTabIndex < 0) { return; }

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat dx = point.x - _dragStartPoint.x;
    CGFloat dy = point.y - _dragStartPoint.y;
    if (!_draggingTab && hypot(dx, dy) < 3.0) return;
    _draggingTab = YES;
    [self hideHoverPanel];

    BOOL outsideTabStrip = point.y < -24.0 || point.y > NSHeight(self.bounds) + 24.0 ||
                           point.x < [self leftInset] - 18.0 || point.x > NSMaxX([self plusRect]) + 18.0;
    if (!_detachedTabDrag && (outsideTabStrip || fabs(dy) > 48.0)) {
        [self startTabDragSessionWithEvent:event];
        return;
    }
    if (_detachedTabDrag) return;

    _dragCurrentX = point.x - _dragPointerOffsetX;
    NSInteger targetIndex = [self dragDestinationIndexForPoint:point];
    if (targetIndex >= 0) _dragTargetTabIndex = targetIndex;
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent*)event {
    (void)event;
    NSInteger clickedTabIndex = _dragSourceTabIndex >= 0 ? _dragSourceTabIndex : _draggedTabIndex;
    NSInteger targetIndex = _dragTargetTabIndex;
    BOOL dragged = _draggingTab;
    BOOL detached = _detachedTabDrag;
    [self resetTabDragTracking];
    if (detached) return;
    if (dragged && clickedTabIndex >= 0 && targetIndex >= 0 && clickedTabIndex != targetIndex) {
        [self.reader moveTabFromIndex:clickedTabIndex toIndex:targetIndex];
        [self.reader selectTabAtIndex:targetIndex];
    } else if (!dragged && clickedTabIndex >= 0) {
        [self.reader selectTabAtIndex:clickedTabIndex];
    }
}

// Middle-click closes a tab with browser semantics: the close fires on
// middle-button RELEASE over the same tab that was pressed (middle-dragging
// off the tab cancels). Goes through the same -closeTabAtIndex: path as the
// tab's close button, so reopen-last-closed bookkeeping applies. The pressed
// tab is never selected first. Presses on the "+" / "…" controls or empty
// strip space hit no tab and do nothing.
- (void)otherMouseDown:(NSEvent*)event {
    if (event.buttonNumber != 2) {
        [super otherMouseDown:event];
        return;
    }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger index = [self tabIndexAtPoint:point];
    _middleClickTabIndex = index;
    _middleClickTabPath = index >= 0 ? [self.tabs[(NSUInteger)index].path copy] : nil;
}

- (void)otherMouseUp:(NSEvent*)event {
    if (event.buttonNumber != 2) {
        [super otherMouseUp:event];
        return;
    }
    NSInteger pressedIndex = _middleClickTabIndex;
    NSString* pressedPath = _middleClickTabPath;
    _middleClickTabIndex = -1;
    _middleClickTabPath = nil;
    if (pressedIndex < 0 || pressedIndex >= (NSInteger)self.tabs.count) return;
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if ([self tabIndexAtPoint:point] != pressedIndex) return;
    // Guard against the tabs array having changed between press and release
    // (async tab-strip refreshes): only close if the same document is still at
    // the pressed index.
    NSString* currentPath = self.tabs[(NSUInteger)pressedIndex].path ?: @"";
    if (![currentPath isEqualToString:pressedPath ?: @""]) return;
    [self hideHoverPanel];
    [self.reader closeTabAtIndex:pressedIndex];
}

- (void)mouseMoved:(NSEvent*)event {
    [self updateHoverForEvent:event];
}

- (void)mouseEntered:(NSEvent*)event {
    [self updateHoverForEvent:event];
}

- (void)mouseExited:(NSEvent*)event {
    (void)event;
    [self hideHoverPanel];
}

@end
