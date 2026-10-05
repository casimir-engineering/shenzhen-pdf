#import "SPDFMacChromeColors.h"
#import "SPDFMacSidebarModeControl.h"

static const CGFloat RowHeight = 28;
static NSString* Symbol(NSInteger mode) {
    switch (mode) {
        case -1: return @"sidebar.left";
        case SPDFSidebarModeComments: return @"text.bubble";
        case SPDFSidebarModeSearch: return @"magnifyingglass";
        case SPDFSidebarModeHistory: return @"clock.arrow.circlepath";
        case SPDFSidebarModeGroups: return @"square.3.layers.3d";
        default: return @"list.bullet.indent";
    }
}
// Rows paint a full 28-point target, not an AppKit bezel. Native button cells
// otherwise hit-test an inset bezel/title rectangle, leaving painted edges out.
@interface SPDFSidebarNavigationCell : NSButtonCell
@end
@implementation SPDFSidebarNavigationCell
- (NSCellHitResult)hitTestForEvent:(NSEvent*)event inRect:(NSRect)frame ofView:(NSView*)view {
    (void)frame;
    NSPoint point = [view convertPoint:event.locationInWindow fromView:nil];
    return self.enabled && NSPointInRect(point,view.bounds)
        ? NSCellHitContentArea | NSCellHitTrackableArea : NSCellHitNone;
}
@end
@interface SPDFSidebarNavigationRow : NSButton
@property NSInteger mode;
@end
@implementation SPDFSidebarNavigationRow {
    NSTrackingArea* _hoverArea;
    BOOL _hovered;
}
+ (Class)cellClass { return SPDFSidebarNavigationCell.class; }
- (void)mouseDown:(NSEvent*)event {
    if (self.mode >= 0) { [super mouseDown:event]; return; }
    [self highlight:NO]; self.state=NSControlStateValueOff;
    if (self.enabled) [self sendAction:self.action to:self.target];
    [self highlight:NO]; self.state=NSControlStateValueOff;
}
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty {
    (void)dirty;
    BOOL selected = self.mode >= 0 && self.state == NSControlStateValueOn;
    NSRect bounds = NSInsetRect(self.bounds,.5,.5);
    NSBezierPath* shape = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:7 yRadius:7];
    if (self.mode >= 0 && (selected || self.highlighted || _hovered)) {
        BOOL dark = [[self.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]] isEqual:NSAppearanceNameDarkAqua];
        NSColor* fill = selected ? (dark ? [NSColor colorWithSRGBRed:.216 green:.294 blue:.380 alpha:1] : [NSColor colorWithSRGBRed:.859 green:.898 blue:.941 alpha:1]) : [NSColor.labelColor colorWithAlphaComponent:self.highlighted ? .065 : .035];
        [fill setFill]; [shape fill];
    }
    if (selected && self.window.firstResponder == self.superview) {
        [NSGraphicsContext saveGraphicsState]; NSSetFocusRingStyle(NSFocusRingOnly); [shape fill]; [NSGraphicsContext restoreGraphicsState];
    }
    NSColor* color = SPDFChromeIconColor(self.enabled);
    NSImage* icon = [NSImage imageWithSystemSymbolName:Symbol(self.mode) accessibilityDescription:nil];
    icon = [icon imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:16 weight:NSFontWeightRegular]];
    icon = [icon imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPaletteColors:@[color]]];
    [icon drawInRect:NSMakeRect(floor((NSWidth(self.bounds)-16)/2),6,16,16) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];

}
- (void)updateTrackingAreas {
    [super updateTrackingAreas]; if (_hoverArea) [self removeTrackingArea:_hoverArea];
    _hoverArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited|NSTrackingActiveAlways|NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:_hoverArea];
}
- (void)mouseEntered:(NSEvent*)event { (void)event; _hovered = YES; self.needsDisplay = YES; }
- (void)mouseExited:(NSEvent*)event { (void)event; _hovered = NO; self.needsDisplay = YES; }
- (void)keyDown:(NSEvent*)event {
    if (event.keyCode == 125 || event.keyCode == 126 || event.keyCode == 123 || event.keyCode == 124 || event.keyCode == 49 || event.keyCode == 36 || event.keyCode == 76) [self.superview keyDown:event]; else [super keyDown:event];
}
- (NSRect)focusRingMaskBounds { return NSInsetRect(self.bounds,.5,.5); }
- (void)drawFocusRingMask { [[NSBezierPath bezierPathWithRoundedRect:self.focusRingMaskBounds xRadius:7 yRadius:7] fill]; }
- (NSString*)accessibilityRole { return self.mode < 0 ? NSAccessibilityButtonRole : NSAccessibilityRadioButtonRole; }
- (id)accessibilityValue { return self.mode < 0 ? nil : @(self.state == NSControlStateValueOn); }
@end

@implementation SPDFSidebarNavigationControl {
    NSMutableArray<SPDFSidebarNavigationRow*>* _rows;
    NSButton* _collapse;
    NSMutableArray<NSString*>* _labels;
    NSMutableArray<NSNumber*>* _tags;
    NSMutableArray<NSNumber*>* _enabled;
    NSInteger _selectedSegment;
}
- (BOOL)isFlipped { return YES; }
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _rows = [NSMutableArray array]; _labels = [NSMutableArray array];
        _tags = [NSMutableArray array]; _enabled = [NSMutableArray array]; _selectedSegment = -1;
        self.focusRingType = NSFocusRingTypeNone; [self rebuildRows];
    }
    return self;
}
- (NSSize)intrinsicContentSize {
    return NSMakeSize(NSViewNoIntrinsicMetric,self.spdf_selectedSidebarMode == SPDFSidebarModeGroups ? 44 : 72);
}
- (void)setDocumentTitle:(NSString*)title {
    if ([_documentTitle isEqualToString:title]) return;
    _documentTitle = [title copy]; self.needsDisplay = YES;
}
- (void)setCollapseTarget:(id)target action:(SEL)action {
    if (!_collapse) {
        SPDFSidebarNavigationRow* collapse = [SPDFSidebarNavigationRow new]; collapse.mode = -1;
        collapse.ignoresMultiClick=NO; [collapse setButtonType:NSButtonTypeMomentaryChange];
        collapse.target = target; collapse.action = action; collapse.bordered = NO;
        _collapse = collapse; _collapse.toolTip = @"Hide side panel";
        _collapse.accessibilityLabel = @"Hide side panel"; [self addSubview:_collapse];
    }
}
- (NSArray<SPDFSidebarNavigationRow*>*)visualRows {
    NSMutableArray* result = [NSMutableArray array];
    for (NSNumber* mode in @[@(SPDFSidebarModeGroups),@(SPDFSidebarModeChapters),@(SPDFSidebarModeSearch),
                             @(SPDFSidebarModeComments),@(SPDFSidebarModeHistory)])
        for (SPDFSidebarNavigationRow* row in _rows) if (row.mode == mode.integerValue) [result addObject:row];
    return result;
}
- (void)rebuildRows {
    if (!_rows) return;
    NSResponder* focused = self.window.firstResponder;
    BOOL retainedFocus = [focused isKindOfClass:NSView.class] && [(NSView*)focused isDescendantOf:self];
    for (NSView* row in _rows) [row removeFromSuperview]; [_rows removeAllObjects];
    for (NSInteger i=0;i<self.segmentCount;i++) {
        SPDFSidebarNavigationRow* row = [SPDFSidebarNavigationRow new]; row.bordered = NO;
        row.ignoresMultiClick = NO;
        row.tag = i; row.target = self; row.action = @selector(chooseRow:);
        [self addSubview:row]; [_rows addObject:row];
    }
    [self syncRows]; [self invalidateIntrinsicContentSize]; self.needsLayout = YES;
    if (retainedFocus) [self.window makeFirstResponder:self];
}
- (void)syncRows {
    for (NSUInteger i=0;i<_rows.count;i++) {
        SPDFSidebarNavigationRow* row = _rows[i];
        row.title = [self labelForSegment:i] ?: @""; row.mode = [self tagForSegment:i];
        row.accessibilityLabel = row.title; row.toolTip = row.mode == SPDFSidebarModeHistory ? @"History (⌘H)" : row.title;
        row.enabled = [self isEnabledForSegment:i];
        row.state = self.selectedSegment == (NSInteger)i ? NSControlStateValueOn : NSControlStateValueOff;
        row.needsDisplay = YES;
    }
}
// The container deliberately has no NSSegmentedCell: AppKit's segmented hit
// routing can consume child-button clicks below its own invisible native bezel.
- (NSInteger)segmentCount { return _labels.count; }
- (void)setSegmentCount:(NSInteger)count {
    count = MAX(0,count);
    while (_labels.count < (NSUInteger)count) { [_labels addObject:@""]; [_tags addObject:@0]; [_enabled addObject:@YES]; }
    while (_labels.count > (NSUInteger)count) { [_labels removeLastObject]; [_tags removeLastObject]; [_enabled removeLastObject]; }
    if (_selectedSegment >= count) _selectedSegment = -1;
    [self rebuildRows];
}
- (NSInteger)selectedSegment { return _selectedSegment; }
- (void)setSelectedSegment:(NSInteger)index {
    _selectedSegment = index >= 0 && index < self.segmentCount ? index : -1;
    [self syncRows]; [self invalidateIntrinsicContentSize]; self.needsDisplay = YES;
}
- (NSString*)labelForSegment:(NSInteger)segment { return _labels[(NSUInteger)segment]; }
- (NSInteger)tagForSegment:(NSInteger)segment { return _tags[(NSUInteger)segment].integerValue; }
- (BOOL)isEnabledForSegment:(NSInteger)segment { return _enabled[(NSUInteger)segment].boolValue; }
- (void)setTag:(NSInteger)tag forSegment:(NSInteger)segment { _tags[(NSUInteger)segment] = @(tag); [self syncRows]; }
- (void)setLabel:(NSString*)label forSegment:(NSInteger)segment { _labels[(NSUInteger)segment] = label ?: @""; [self syncRows]; }
- (void)setEnabled:(BOOL)enabled forSegment:(NSInteger)segment { _enabled[(NSUInteger)segment] = @(enabled); [self syncRows]; }
- (void)setWidth:(CGFloat)width forSegment:(NSInteger)segment { (void)width; (void)segment; }
- (void)layout {
    [super layout];
    NSArray* rows = [self visualRows];
    CGFloat width = MIN(28, floor((NSWidth(self.bounds)-16-(_collapse ? 28 : 0))/MAX(1,rows.count)));
    CGFloat x = 0;
    for (SPDFSidebarNavigationRow* row in rows) {
        row.frame = NSMakeRect(x,8,width,RowHeight); x += width;
        if (row.mode == SPDFSidebarModeGroups) x += 16;
    }
    _collapse.frame = NSMakeRect(NSWidth(self.bounds)-28,8,28,28);
}
- (void)drawRect:(NSRect)dirty {
    (void)dirty; [[NSColor.labelColor colorWithAlphaComponent:.13] setFill];
    NSRectFill(NSMakeRect(-8,43,NSWidth(self.bounds)+16,.5));
    SPDFSidebarNavigationRow* group = [self visualRows].firstObject;
    NSRectFill(NSMakeRect(NSMaxX(group.frame)+7,14,.5,16));
    if (self.spdf_selectedSidebarMode != SPDFSidebarModeGroups) {
        NSMutableParagraphStyle* style = [NSMutableParagraphStyle new]; style.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [_documentTitle ?: @"No document" drawInRect:NSMakeRect(4,53,MAX(0,NSWidth(self.bounds)-8),16)
            withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:11],
                NSForegroundColorAttributeName:NSColor.secondaryLabelColor,NSParagraphStyleAttributeName:style}];
    }
}

- (NSView*)hitTest:(NSPoint)point {
    NSPoint local = [self convertPoint:point fromView:self.superview];
    if (self.hidden || !NSPointInRect(local,self.bounds)) return nil;
    if (_collapse && NSPointInRect(local,_collapse.frame)) return _collapse;
    for (NSView* row in _rows) if (NSPointInRect(local,row.frame)) return row;
    return nil; // Empty header space belongs to the dedicated drag surface below.
}
- (void)chooseRow:(NSButton*)row {
    if (!row.enabled) return;
    self.selectedSegment = row.tag;
    NSResponder* focused = self.window.firstResponder;
    if (focused != self && [focused isKindOfClass:NSView.class] && [(NSView*)focused isDescendantOf:self])
        [self.window makeFirstResponder:row];
    [self sendAction:self.action to:self.target];
}
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)becomeFirstResponder { [self syncRows]; return YES; }
- (BOOL)resignFirstResponder { [self syncRows]; return YES; }
- (void)keyDown:(NSEvent*)event {
    if (event.keyCode == 49 || event.keyCode == 36 || event.keyCode == 76) {
        NSInteger selected = self.selectedSegment;
        if (selected >= 0 && selected < (NSInteger)_rows.count) [self chooseRow:_rows[selected]];
        return;
    }
    NSInteger direction = (event.keyCode == 125 || event.keyCode == 124) ? 1 : (event.keyCode == 126 || event.keyCode == 123) ? -1 : 0;
    if (!direction) { [super keyDown:event]; return; }
    NSArray* ordered = [self visualRows];
    if (self.selectedSegment < 0 || self.selectedSegment >= (NSInteger)_rows.count) return;
    NSInteger current = [ordered indexOfObject:_rows[self.selectedSegment]];
    for (NSInteger i=current+direction;i>=0 && i<(NSInteger)ordered.count;i+=direction)
        if ([ordered[i] isEnabled]) { [self chooseRow:ordered[i]]; return; }
}
- (NSArray*)accessibilityChildren { return _collapse ? [(NSArray*)[self visualRows] arrayByAddingObject:_collapse] : [self visualRows]; }
- (NSString*)accessibilityRole { return NSAccessibilityTabGroupRole; }
@end
