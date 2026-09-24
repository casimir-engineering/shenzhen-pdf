#import "SPDFMacSidebarModeControl.h"

static const CGFloat RowHeight = 26, RowGap = 0;
static NSString* Symbol(NSInteger mode) {
    switch (mode) {
        case SPDFSidebarModeComments: return @"text.bubble";
        case SPDFSidebarModeSearch: return @"magnifyingglass";
        case SPDFSidebarModeHistory: return @"clock.arrow.circlepath";
        case SPDFSidebarModeGroups: return @"rectangle.3.group";
        default: return @"list.bullet.indent";
    }
}
@interface SPDFSidebarNavigationRow : NSButton
@property NSInteger mode;
@end
@implementation SPDFSidebarNavigationRow {
    NSTrackingArea* _hoverArea;
    BOOL _hovered;
}
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty {
    (void)dirty;
    BOOL selected = self.state == NSControlStateValueOn;
    NSRect bounds = NSInsetRect(self.bounds,.5,.5);
    NSBezierPath* shape = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:7 yRadius:7];
    if (selected || self.highlighted || _hovered) {
        NSColor* fill = [NSColor.labelColor colorWithAlphaComponent:selected ? .085 : (self.highlighted ? .065 : .035)];
        [fill setFill]; [shape fill];
    }
    if (selected && self.window.firstResponder == self.superview) {
        [NSGraphicsContext saveGraphicsState]; NSSetFocusRingStyle(NSFocusRingOnly); [shape fill]; [NSGraphicsContext restoreGraphicsState];
    }
    NSColor* color = self.enabled ? NSColor.labelColor : NSColor.disabledControlTextColor;
    NSImage* icon = [NSImage imageWithSystemSymbolName:Symbol(self.mode) accessibilityDescription:nil];
    icon = [icon imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:13 weight:selected ? NSFontWeightSemibold : NSFontWeightRegular]];
    icon = [icon imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPaletteColors:@[color]]];
    [icon drawInRect:NSMakeRect(10,6,14,14) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
    NSMutableParagraphStyle* paragraph = [NSMutableParagraphStyle new]; paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary* attributes = @{NSFontAttributeName:[NSFont systemFontOfSize:12 weight:selected ? NSFontWeightSemibold : NSFontWeightRegular],
        NSForegroundColorAttributeName:color,NSParagraphStyleAttributeName:paragraph};
    CGFloat height = [self.title sizeWithAttributes:attributes].height;
    [self.title drawInRect:NSMakeRect(32,floor((NSHeight(self.bounds)-height)/2),MAX(0,NSWidth(self.bounds)-42),height) withAttributes:attributes];
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas]; if (_hoverArea) [self removeTrackingArea:_hoverArea];
    _hoverArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited|NSTrackingActiveAlways|NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:_hoverArea];
}
- (void)mouseEntered:(NSEvent*)event { (void)event; _hovered = YES; self.needsDisplay = YES; }
- (void)mouseExited:(NSEvent*)event { (void)event; _hovered = NO; self.needsDisplay = YES; }
- (void)keyDown:(NSEvent*)event {
    if (event.keyCode == 125 || event.keyCode == 126 || event.keyCode == 49 || event.keyCode == 36 || event.keyCode == 76) [self.superview keyDown:event]; else [super keyDown:event];
}
- (NSRect)focusRingMaskBounds { return NSInsetRect(self.bounds,.5,.5); }
- (void)drawFocusRingMask { [[NSBezierPath bezierPathWithRoundedRect:self.focusRingMaskBounds xRadius:7 yRadius:7] fill]; }
- (NSString*)accessibilityRole { return NSAccessibilityRadioButtonRole; }
- (id)accessibilityValue { return @(self.state == NSControlStateValueOn); }
@end

@implementation SPDFSidebarNavigationControl {
    NSMutableArray<SPDFSidebarNavigationRow*>* _rows;
}
- (BOOL)isFlipped { return YES; }
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) { _rows = [NSMutableArray array]; self.focusRingType = NSFocusRingTypeNone; [self rebuildRows]; }
    return self;
}
- (NSSize)intrinsicContentSize {
    return NSMakeSize(NSViewNoIntrinsicMetric,self.segmentCount ? self.segmentCount*RowHeight+(self.segmentCount-1)*RowGap+9 : 0);
}
- (void)rebuildRows {
    if (!_rows) return;
    NSResponder* focused = self.window.firstResponder;
    BOOL retainedFocus = [focused isKindOfClass:NSView.class] && [(NSView*)focused isDescendantOf:self];
    for (NSView* row in _rows) [row removeFromSuperview]; [_rows removeAllObjects];
    for (NSInteger i=0;i<self.segmentCount;i++) {
        SPDFSidebarNavigationRow* row = [SPDFSidebarNavigationRow new]; row.bordered = NO;
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
        row.accessibilityLabel = row.title; row.toolTip = row.title;
        row.enabled = [self isEnabledForSegment:i];
        row.state = self.selectedSegment == (NSInteger)i ? NSControlStateValueOn : NSControlStateValueOff;
        row.needsDisplay = YES;
    }
}
- (void)setSegmentCount:(NSInteger)count { [super setSegmentCount:count]; [self rebuildRows]; }
- (void)setSelectedSegment:(NSInteger)index { [super setSelectedSegment:index]; [self syncRows]; }
- (void)setTag:(NSInteger)tag forSegment:(NSInteger)segment { [super setTag:tag forSegment:segment]; [self syncRows]; }
- (void)setLabel:(NSString*)label forSegment:(NSInteger)segment { [super setLabel:label forSegment:segment]; [self syncRows]; }
- (void)setEnabled:(BOOL)enabled forSegment:(NSInteger)segment { [super setEnabled:enabled forSegment:segment]; [self syncRows]; }
- (void)setWidth:(CGFloat)width forSegment:(NSInteger)segment { (void)width; (void)segment; }
- (void)layout {
    [super layout];
    for (NSUInteger i=0;i<_rows.count;i++) _rows[i].frame = NSMakeRect(0,i*(RowHeight+RowGap),NSWidth(self.bounds),RowHeight);
}
- (void)drawRect:(NSRect)dirty {
    (void)dirty; [[NSColor.labelColor colorWithAlphaComponent:.13] setFill];
    NSRectFillUsingOperation(NSMakeRect(0,NSHeight(self.bounds)-1,NSWidth(self.bounds),.5),NSCompositingOperationSourceOver);
}
- (NSView*)hitTest:(NSPoint)point {
    NSPoint local = [self convertPoint:point fromView:self.superview];
    if (self.hidden || !NSPointInRect(local,self.bounds)) return nil;
    for (NSView* row in _rows) if (NSPointInRect(local,row.frame)) return row;
    return self;
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
    NSInteger direction = event.keyCode == 125 ? 1 : event.keyCode == 126 ? -1 : 0;
    if (!direction) { [super keyDown:event]; return; }
    for (NSInteger i=self.selectedSegment+direction;i>=0 && i<self.segmentCount;i+=direction)
        if ([self isEnabledForSegment:i]) { [self chooseRow:_rows[i]]; return; }
}
- (NSArray*)accessibilityChildren { return _rows.copy; }
- (NSString*)accessibilityRole { return NSAccessibilityTabGroupRole; }
@end
