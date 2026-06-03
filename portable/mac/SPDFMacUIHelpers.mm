#import "SPDFMacUIHelpers.h"

static CGFloat spdf_ui_clamp_cg(CGFloat value, CGFloat minValue, CGFloat maxValue) {
    return MAX(minValue, MIN(maxValue, value));
}

@implementation SPDFPresentationOverlayView

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event {
    (void)event;
    return YES;
}

- (NSView*)hitTest:(NSPoint)point {
    (void)point;
    return self.hidden ? nil : self;
}

- (void)mouseDown:(NSEvent*)event {
    if (self.reader && [self.reader handlePresentationEvent:event]) return;
    [super mouseDown:event];
}

- (void)rightMouseDown:(NSEvent*)event {
    if (self.reader && [self.reader handlePresentationEvent:event]) return;
    [super rightMouseDown:event];
}

- (void)otherMouseDown:(NSEvent*)event {
    if (self.reader && [self.reader handlePresentationEvent:event]) return;
    [super otherMouseDown:event];
}

- (void)mouseUp:(NSEvent*)event {
    [super mouseUp:event];
}

- (void)rightMouseUp:(NSEvent*)event {
    [super rightMouseUp:event];
}

- (void)otherMouseUp:(NSEvent*)event {
    [super otherMouseUp:event];
}

- (void)keyDown:(NSEvent*)event {
    if (self.reader && [self.reader handlePresentationEvent:event]) return;
    [super keyDown:event];
}

@end

@implementation SPDFToolbarStackView

- (BOOL)acceptsFirstMouse:(NSEvent*)event {
    (void)event;
    return YES;
}

- (BOOL)mouseDownCanMoveWindow {
    return YES;
}

- (void)mouseDown:(NSEvent*)event {
    BOOL wasMovable = self.window.movable;
    self.window.movable = YES;
    [self.window performWindowDragWithEvent:event];
    self.window.movable = wasMovable;
}

@end

@implementation SPDFToolbarToggleButton

- (instancetype)initWithTitle:(NSString*)title target:(id)target action:(SEL)action {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.title = title;
        self.target = target;
        self.action = action;
        self.bordered = NO;
        self.bezelStyle = NSBezelStyleRegularSquare;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.focusRingType = NSFocusRingTypeNone;
        [self setButtonType:NSButtonTypeMomentaryChange];
        [self setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    return self;
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event {
    (void)event;
    return YES;
}

- (NSSize)intrinsicContentSize {
    NSDictionary* attrs = @{NSFontAttributeName : [NSFont systemFontOfSize:12.0 weight:NSFontWeightLight]};
    CGFloat titleWidth = ceil([self.title sizeWithAttributes:attrs].width);
    return NSMakeSize(titleWidth + 50.0, 28.0);
}

- (void)setActive:(BOOL)active {
    if (_active == active) return;
    _active = active;
    self.accessibilityValue = active ? @"On" : @"Off";
    [self setNeedsDisplay:YES];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    [self setNeedsDisplay:YES];
}

- (void)setTitle:(NSString*)title {
    [super setTitle:title];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect bounds = NSInsetRect(self.bounds, 1.0, 2.0);
    BOOL enabled = self.enabled;
    BOOL pressed = self.highlighted;
    CGFloat alpha = enabled ? 1.0 : 0.44;

    if (pressed) {
        NSColor* pressFill = [NSColor.labelColor colorWithAlphaComponent:0.08 * alpha];
        [pressFill setFill];
        [[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:7.0 yRadius:7.0] fill];
    }

    NSFont* font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightLight];
    NSMutableParagraphStyle* paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    paragraph.alignment = NSTextAlignmentLeft;
    NSDictionary* attrs = @{
        NSFontAttributeName : font,
        NSForegroundColorAttributeName : [NSColor.labelColor colorWithAlphaComponent:alpha],
        NSParagraphStyleAttributeName : paragraph
    };

    CGFloat switchWidth = 32.0;
    CGFloat switchHeight = 18.0;
    NSRect switchRect = NSMakeRect(floor(NSMaxX(bounds) - switchWidth - 5.0),
                                   floor(NSMidY(bounds) - switchHeight / 2.0), switchWidth, switchHeight);
    NSRect titleRect = NSMakeRect(NSMinX(bounds) + 5.0, floor(NSMidY(bounds) - 8.0),
                                  MAX(1.0, NSMinX(switchRect) - NSMinX(bounds) - 10.0), 17.0);
    [self.title drawWithRect:titleRect
                     options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine
                  attributes:attrs];

    NSColor* trackFill = self.active ? [NSColor.whiteColor colorWithAlphaComponent:(enabled ? 0.94 : 0.38)]
                                     : [NSColor.secondaryLabelColor colorWithAlphaComponent:(enabled ? 0.22 : 0.12)];
    NSBezierPath* track = [NSBezierPath bezierPathWithRoundedRect:switchRect
                                                          xRadius:switchHeight / 2.0
                                                          yRadius:switchHeight / 2.0];
    [trackFill setFill];
    [track fill];
    [[NSColor.separatorColor colorWithAlphaComponent:enabled ? 0.55 : 0.24] setStroke];
    track.lineWidth = 1.0;
    [track stroke];

    CGFloat knobSize = 14.0;
    CGFloat knobX = self.active ? NSMaxX(switchRect) - knobSize - 2.0 : NSMinX(switchRect) + 2.0;
    NSRect knobRect = NSMakeRect(floor(knobX), floor(NSMidY(switchRect) - knobSize / 2.0), knobSize, knobSize);
    NSColor* knobFill = self.active ? [NSColor colorWithCalibratedWhite:0.14 alpha:1.0]
                                    : [NSColor.whiteColor colorWithAlphaComponent:0.96];
    if (!enabled) knobFill = [knobFill colorWithAlphaComponent:0.72];
    [knobFill setFill];
    [[NSBezierPath bezierPathWithOvalInRect:knobRect] fill];
    [[NSColor.shadowColor colorWithAlphaComponent:enabled ? 0.18 : 0.08] setStroke];
    [[NSBezierPath bezierPathWithOvalInRect:knobRect] stroke];
}

@end

@implementation SPDFToolbarMenuButton

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.bordered = NO;
        self.bezelStyle = NSBezelStyleRegularSquare;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.focusRingType = NSFocusRingTypeNone;
        [self setButtonType:NSButtonTypeMomentaryChange];
        [self setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    return self;
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event {
    (void)event;
    return YES;
}

- (NSSize)intrinsicContentSize {
    return NSMakeSize(30.0, 28.0);
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect bounds = NSInsetRect(self.bounds, 1.0, 2.0);
    CGFloat alpha = self.enabled ? 1.0 : 0.42;
    NSColor* fill = self.highlighted ? [NSColor.labelColor colorWithAlphaComponent:0.13 * alpha]
                                     : [NSColor.labelColor colorWithAlphaComponent:0.06 * alpha];
    [fill setFill];
    [[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:8.0 yRadius:8.0] fill];

    [[NSColor.separatorColor colorWithAlphaComponent:0.30 * alpha] setStroke];
    NSBezierPath* outline = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:8.0 yRadius:8.0];
    outline.lineWidth = 1.0;
    [outline stroke];

    [[NSColor.labelColor colorWithAlphaComponent:0.78 * alpha] setFill];
    CGFloat dotSize = 3.0;
    CGFloat gap = 3.0;
    CGFloat x = floor(NSMidX(bounds) - dotSize / 2.0);
    CGFloat startY = floor(NSMidY(bounds) - dotSize * 1.5 - gap);
    for (NSInteger i = 0; i < 3; ++i) {
        NSRect dot = NSMakeRect(x, startY + (dotSize + gap) * i, dotSize, dotSize);
        [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
    }
}

@end

@implementation SPDFPaletteSearchField

- (void)keyDown:(NSEvent*)event {
    if (event.keyCode == 53) {
        [self.reader closePalette:self];
        return;
    }
    if (event.keyCode == 125) {
        [self.reader paletteMoveSelection:1];
        return;
    }
    if (event.keyCode == 126) {
        [self.reader paletteMoveSelection:-1];
        return;
    }
    if (event.keyCode == 36 || event.keyCode == 76) {
        [self.reader activatePaletteSelection:self];
        return;
    }
    [super keyDown:event];
}

@end

@implementation SPDFDropView

- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    (void)sender;
    return NSDragOperationCopy;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    return [self.reader openFilesFromPasteboard:sender.draggingPasteboard];
}

@end

@implementation SPDFMinimapDividerView {
    CGFloat _lastWindowX;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:NSCursor.resizeLeftRightCursor];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [NSColor.windowBackgroundColor setFill];
    NSRectFill(self.bounds);
    [[NSColor separatorColor] setFill];
    NSRectFill(NSMakeRect(floor(NSWidth(self.bounds) / 2.0), 0.0, 1.0, NSHeight(self.bounds)));
}

- (void)mouseDown:(NSEvent*)event {
    _lastWindowX = event.locationInWindow.x;
    [self.reader clearFindFieldFocus];
}

- (void)mouseDragged:(NSEvent*)event {
    CGFloat x = event.locationInWindow.x;
    [self.reader minimapDividerDraggedByDeltaX:x - _lastWindowX];
    _lastWindowX = x;
}

- (void)mouseUp:(NSEvent*)event {
    (void)event;
    [self.reader minimapDividerDidFinishDragging];
}

@end

@implementation SPDFFindMarkerScroller

- (void)drawKnobSlotInRect:(NSRect)slotRect highlight:(BOOL)flag {
    [super drawKnobSlotInRect:slotRect highlight:flag];
    if (!self.reader || NSHeight(slotRect) <= 2.0) return;

    NSArray<NSDictionary*>* markers = [self.reader findScrollbarMarkers];
    if (markers.count == 0) return;

    CGFloat minY = NSMinY(slotRect) + 2.0;
    CGFloat maxY = NSMaxY(slotRect) - 2.0;
    CGFloat lastY = -1000.0;
    for (NSDictionary* marker in markers) {
        CGFloat fraction = spdf_ui_clamp_cg([marker[@"fraction"] doubleValue], 0.0, 1.0);
        CGFloat y = self.isFlipped ? floor(minY + fraction * MAX(1.0, maxY - minY))
                                   : floor(maxY - fraction * MAX(1.0, maxY - minY));
        if (fabs(y - lastY) < 1.5 && ![marker[@"active"] boolValue]) continue;
        BOOL active = [marker[@"active"] boolValue];
        NSColor* color = active ? [NSColor colorWithCalibratedRed:1.0 green:0.38 blue:0.08 alpha:0.95]
                                : [NSColor colorWithCalibratedRed:1.0 green:0.86 blue:0.12 alpha:0.82];
        [color setFill];
        NSRect line = NSMakeRect(NSMinX(slotRect) + 2.0, y, MAX(2.0, NSWidth(slotRect) - 4.0), active ? 2.0 : 1.0);
        NSRectFillUsingOperation(line, NSCompositingOperationSourceOver);
        lastY = y;
    }
}

@end

@implementation SPDFWindow

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return YES;
}

- (void)sendEvent:(NSEvent*)event {
    if (self.reader && [self.reader handleTabStripMouseEvent:event]) return;
    if (self.reader && [self.reader handlePresentationEvent:event]) return;
    if (self.reader && [self.reader handleWindowArrangementShortcutEvent:event]) return;
    [super sendEvent:event];
}

@end

@implementation SPDFShortcutHelpPanel

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return YES;
}

@end

@implementation SPDFScrollView {
    CGFloat _wheelAccumulator;
}

- (void)scrollWheel:(NSEvent*)event {
    if (self.reader && [self.reader zoomWithScrollWheelEvent:event centeredAtWindowPoint:event.locationInWindow])
        return;

    if (self.reader && [self.reader scrollViewShouldTurnWheelIntoPageChange:event]) {
        CGFloat delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY;
        _wheelAccumulator += delta;
        CGFloat threshold = event.hasPreciseScrollingDeltas ? 0.75 : 0.50;
        if (fabs(_wheelAccumulator) >= threshold) {
            if (_wheelAccumulator < 0)
                [self.reader nextPage:self];
            else
                [self.reader previousPage:self];
            _wheelAccumulator = 0;
        }
        return;
    }

    [super scrollWheel:event];
    if (self.reader) [self.reader documentScrollPositionChanged];
}

- (void)magnifyWithEvent:(NSEvent*)event {
    if (self.reader) [self.reader zoomWithMagnifyEvent:event centeredAtWindowPoint:event.locationInWindow];
}

- (void)keyDown:(NSEvent*)event {
    if (self.reader && [self.reader handlePresentationEvent:event]) return;
    if (self.reader && [self.reader documentArrowKeyDown:event]) return;
    if (self.reader && [self.reader documentTypeToSearchKeyDown:event]) return;
    [super keyDown:event];
}

@end

@implementation SPDFSidebarTableView

- (NSMenu*)menuForEvent:(NSEvent*)event {
    if (!self.reader) return [super menuForEvent:event];

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger row = [self rowAtPoint:point];
    NSNumber* commentIndex = [self.reader commentIndexForSidebarRow:row];
    if (!commentIndex) return nil;

    NSMenu* menu = [super menuForEvent:event];
    for (NSMenuItem* item in menu.itemArray) {
        if (item.action == @selector(editComment:) || item.action == @selector(deleteComment:)) {
            item.target = self.reader;
            item.representedObject = commentIndex;
        }
    }
    return menu;
}

@end
