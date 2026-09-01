#import "SPDFMacUIHelpers.h"
#import "SPDFMacSupport.h"
#import "SPDFMacInactiveZoom.h"
#import "SPDFMacWindowChrome.h"

static CGFloat spdf_ui_clamp_cg(CGFloat value, CGFloat minValue, CGFloat maxValue) {
    return MAX(minValue, MIN(maxValue, value));
}

void spdf_activate_window_for_view(NSView* view) {
    NSWindow* window = view.window;
    if (!window) return;
    if (!NSApp.active) [NSApp activateIgnoringOtherApps:YES];
    if (!window.keyWindow) [window makeKeyAndOrderFront:nil];
}

void spdf_set_menu_item_system_symbol(NSMenuItem* item, NSString* symbolName) {
    if (!item || symbolName.length == 0) return;
    if (@available(macOS 11.0, *)) {
        NSImage* image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:item.title];
        if (!image) return;
        [image setTemplate:YES];
        item.image = image;
    }
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
    [(SPDFWindow*)self.window handleChromeMouseDown:event];
}

@end

@implementation SPDFToolbarDragView

- (BOOL)acceptsFirstMouse:(NSEvent*)event {
    (void)event;
    return YES;
}

- (BOOL)mouseDownCanMoveWindow {
    return YES;
}

- (void)mouseDown:(NSEvent*)event {
    [(SPDFWindow*)self.window handleChromeMouseDown:event];
}

@end

@implementation SPDFToolbarDragLabel

+ (instancetype)labelWithString:(NSString*)stringValue {
    SPDFToolbarDragLabel* label = [[self alloc] initWithFrame:NSZeroRect];
    label.stringValue = stringValue ?: @"";
    label.bezeled = NO;
    label.bordered = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event {
    (void)event;
    return YES;
}

- (BOOL)mouseDownCanMoveWindow {
    return YES;
}

- (void)mouseDown:(NSEvent*)event {
    [(SPDFWindow*)self.window handleChromeMouseDown:event];
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
        // Fire on mouse-down rather than the default mouse-up so toggling the
        // Side Panel / Map feels immediate.
        [self sendActionOn:NSEventMaskLeftMouseDown];
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

@implementation SPDFFindSearchField

- (BOOL)acceptsFirstMouse:(NSEvent*)event {
    (void)event;
    return YES;
}

- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

- (void)scrollWheel:(NSEvent*)event {
    CGFloat deltaX = event.scrollingDeltaX != 0.0 ? event.scrollingDeltaX : event.deltaX;
    CGFloat deltaY = event.scrollingDeltaY != 0.0 ? event.scrollingDeltaY : event.deltaY;
    NSText* editor = self.currentEditor;
    if (editor && fabs(deltaX) > fabs(deltaY) && fabs(deltaX) > 0.01) {
        NSString* string = editor.string ?: @"";
        NSRange selectedRange = editor.selectedRange;
        NSInteger step = MAX(1, MIN(18, (NSInteger)ceil(fabs(deltaX) / 3.0)));
        NSUInteger location = selectedRange.location;
        if (deltaX > 0.0) location = MIN(string.length, location + (NSUInteger)step);
        else location = location > (NSUInteger)step ? location - (NSUInteger)step : 0;
        [editor setSelectedRange:NSMakeRange(location, 0)];
        [editor scrollRangeToVisible:NSMakeRange(location, 0)];
        return;
    }
    [super scrollWheel:event];
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

@implementation SPDFSidebarDividerView {
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
    [self.reader sidebarDividerDraggedByDeltaX:x - _lastWindowX];
    _lastWindowX = x;
}

- (void)mouseUp:(NSEvent*)event {
    (void)event;
    [self.reader sidebarDividerDidFinishDragging];
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

- (instancetype)initWithContentRect:(NSRect)contentRect
                           styleMask:(NSWindowStyleMask)style
                             backing:(NSBackingStoreType)bufferingType
                               defer:(BOOL)flag {
    self = [super initWithContentRect:contentRect styleMask:style backing:bufferingType defer:flag];
    if (self) {
        spdf_inactive_zoom_register_window(self);
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    self = [super initWithCoder:coder];
    if (self) {
        spdf_inactive_zoom_register_window(self);
    }
    return self;
}

- (void)dealloc {
    spdf_inactive_zoom_forget_window(self);
}

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return YES;
}

- (void)handleChromeMouseDown:(NSEvent*)event {
    if (!event) return;
    BOOL fullScreen = (self.styleMask & NSWindowStyleMaskFullScreen) != 0;
    BOOL presentation = self.reader && [self.reader documentViewInPresentationMode];
    switch (spdf_window_chrome_action_for_event(self, event, fullScreen, presentation)) {
        case SPDFWindowChromeActionDrag: {
            BOOL wasMovable = self.movable;
            self.movable = YES;
            [self performWindowDragWithEvent:event];
            self.movable = wasMovable;
            break;
        }
        case SPDFWindowChromeActionZoom:
            [self performZoom:nil];
            break;
        case SPDFWindowChromeActionNone:
            break;
    }
}

- (void)sendEvent:(NSEvent*)event {
    spdf_window_activate_for_click_event(self, event);  // any click in the window focuses it, before any handler
    if (self.reader && [self.reader handleTabStripMouseEvent:event]) return;
    if (self.reader && [self.reader handlePresentationEvent:event]) return;
    if (self.reader && [self.reader handleWindowArrangementShortcutEvent:event]) return;
    if ([self routeInactiveMagnifyEvent:event]) return;
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

// Points scrolled per line for a classic mouse wheel. A non-precise wheel
// reports line-based deltas (already scaled by the system "scrolling speed"
// preference). AppKit's own default uses a conservative line height and an
// animated, deferred redraw, which reads as sluggish next to other apps. We
// convert lines to points with this factor and scroll immediately instead.
static const CGFloat kSPDFMouseWheelPointsPerLine = 32.0;

@implementation SPDFScrollView {
    CGFloat _wheelAccumulator;
    NSTimeInterval _lastZoomWheelTimestamp;
    NSTimeInterval _zoomWheelSuppressMomentumUntil;
    NSTimeInterval _zoomWheelSuppressPhaseLessUntil;
    NSTimeInterval _lastPageWheelEventTimestamp;
    NSTimeInterval _lastPageWheelTurnTimestamp;
    NSInteger _wheelAccumulatorDirection;
    BOOL _wheelGestureActive;
    BOOL _wheelPageTurnedInGesture;
}

- (BOOL)eventPhase:(NSEventPhase)phase contains:(NSEventPhase)flag {
    return (phase & flag) != 0;
}

- (void)resetPageWheelGesture {
    _wheelAccumulator = 0.0;
    _wheelAccumulatorDirection = 0;
    _wheelGestureActive = NO;
    _wheelPageTurnedInGesture = NO;
    _lastPageWheelEventTimestamp = 0.0;
}

- (void)markZoomWheelAtTimestamp:(NSTimeInterval)timestamp {
    [self resetPageWheelGesture];
    _lastZoomWheelTimestamp = timestamp;
    _zoomWheelSuppressMomentumUntil = timestamp + 0.65;
    _zoomWheelSuppressPhaseLessUntil = timestamp + 0.18;
}

- (BOOL)shouldSuppressResidualZoomWheelEvent:(NSEvent*)event {
    if (_lastZoomWheelTimestamp <= 0.0) return NO;
    BOOL phaseBegan = [self eventPhase:event.phase contains:NSEventPhaseBegan] ||
                      [self eventPhase:event.phase contains:NSEventPhaseMayBegin];
    if (phaseBegan) {
        // Fingers down again means a genuinely new gesture: end the residual
        // window immediately so the new scroll's Changed events flow. Only the
        // tail/momentum of the gesture that drove the zoom should ever be
        // swallowed — previously this exempted just the Began event and then
        // ate the first ~0.65s of the user's next trackpad scroll.
        _lastZoomWheelTimestamp = 0.0;
        _zoomWheelSuppressMomentumUntil = 0.0;
        _zoomWheelSuppressPhaseLessUntil = 0.0;
        return NO;
    }
    BOOL phaseLess = event.phase == NSEventPhaseNone && event.momentumPhase == NSEventPhaseNone;
    BOOL suppress = phaseLess ? event.timestamp < _zoomWheelSuppressPhaseLessUntil
                              : event.timestamp < _zoomWheelSuppressMomentumUntil;
    if (suppress && spdf_zoom_profile_enabled())
        spdf_zoom_profile_log(@"suppressResidualWheel phase=%lu momentum=%lu dt=%.0fms",
                              (unsigned long)event.phase, (unsigned long)event.momentumPhase,
                              (event.timestamp - _lastZoomWheelTimestamp) * 1000.0);
    return suppress;
}

- (CGFloat)dampedPreciseScrollDelta:(CGFloat)delta momentum:(BOOL)momentum {
    CGFloat magnitude = fabs(delta);
    if (magnitude <= 18.0) return delta;

    CGFloat ratio = 1.0 - MIN((magnitude - 18.0) / 220.0, 1.0) * 0.55;
    if (momentum) ratio *= 0.72;
    ratio = MAX(momentum ? 0.30 : 0.45, ratio);
    return delta * ratio;
}

// Apply a point-space scroll delta to the document clip view immediately, with a
// synchronous redraw flush. Shared by the trackpad (precise) and mouse-wheel
// paths so both feel equally reactive. Returns YES when the event is consumed
// (including when already pinned at an edge), NO only when there is nothing to
// scroll so the caller can fall back to the default handler.
- (BOOL)scrollDocumentClipViewByDeltaX:(CGFloat)deltaX deltaY:(CGFloat)deltaY {
    if (!self.documentView || !self.contentView) return NO;
    if (fabs(deltaX) < 0.0001 && fabs(deltaY) < 0.0001) return YES;

    NSClipView* clipView = self.contentView;
    NSRect visible = clipView.bounds;
    NSSize documentSize = self.documentView.bounds.size;
    CGFloat maxX = MAX(0.0, documentSize.width - NSWidth(visible));
    CGFloat maxY = MAX(0.0, documentSize.height - NSHeight(visible));
    NSPoint origin = visible.origin;
    origin.x = spdf_ui_clamp_cg(origin.x - deltaX, 0.0, maxX);
    origin.y = spdf_ui_clamp_cg(origin.y - deltaY, 0.0, maxY);
    // scrollToPoint: bypasses constrainBoundsRect:, so honor the lock ranges
    // here: a viewport-fit page is pinned centered (min==max); a page wider
    // than the viewport pans only within its own bounds (min<max), not across
    // the whole canvas; a document that fits vertically is pinned on y too.
    if ([clipView isKindOfClass:[SPDFDocumentClipView class]]) {
        SPDFDocumentClipView* docClip = (SPDFDocumentClipView*)clipView;
        if (isfinite(docClip.horizontalLockMinX))
            origin.x = spdf_ui_clamp_cg(origin.x, docClip.horizontalLockMinX,
                                        MAX(docClip.horizontalLockMinX, docClip.horizontalLockMaxX));
        if (isfinite(docClip.verticalLockMinY))
            origin.y = spdf_ui_clamp_cg(origin.y, docClip.verticalLockMinY,
                                        MAX(docClip.verticalLockMinY, docClip.verticalLockMaxY));
    }
    if (fabs(origin.x - NSMinX(visible)) < 0.0001 && fabs(origin.y - NSMinY(visible)) < 0.0001) return YES;

    // scrollToPoint: posts a bounds-change notification that re-enters
    // documentScrollPositionChanged; since we invoke it explicitly just below,
    // suppress the duplicate (the minimap-drag path suppresses the same way via
    // notify:NO). Halves the per-event work — the redundant pass was doing extra
    // O(total-pages) pageIndexForVisibleRect: scans and an extra horizontal-lock
    // update, which is the main trackpad scroll/page-switch stutter on large docs.
    BOOL posts = clipView.postsBoundsChangedNotifications;
    clipView.postsBoundsChangedNotifications = NO;
    [clipView scrollToPoint:origin];
    clipView.postsBoundsChangedNotifications = posts;
    [self reflectScrolledClipView:clipView];
    // Flush the exposed-area redraw synchronously so the document content stays
    // locked to the scroll position — this is exactly what makes minimap-driven
    // scrolling smooth. Without it the redraw lands on a later, possibly
    // congested, display cycle (background-render completions flooding the main
    // queue), so the content visibly lags and stutters behind the scroll.
    [self.documentView displayIfNeeded];
    if (self.reader) [self.reader documentScrollPositionChanged];
    return YES;
}

// Classic mouse wheel: translate line-based notches into an immediate point
// scroll so it matches the snappiness of other apps (and our own trackpad path),
// instead of AppKit's animated, deferred default.
- (BOOL)scrollMouseWheelEvent:(NSEvent*)event {
    if (event.hasPreciseScrollingDeltas) return NO;  // trackpad: handled with damping
    CGFloat lineDeltaX = event.scrollingDeltaX != 0.0 ? event.scrollingDeltaX : event.deltaX;
    CGFloat lineDeltaY = event.scrollingDeltaY != 0.0 ? event.scrollingDeltaY : event.deltaY;
    // Shift+wheel scrolls horizontally, matching the AppKit default we bypass.
    if ((event.modifierFlags & NSEventModifierFlagShift) && fabs(lineDeltaX) < fabs(lineDeltaY)) {
        lineDeltaX = lineDeltaY;
        lineDeltaY = 0.0;
    }
    if (fabs(lineDeltaX) < 0.0001 && fabs(lineDeltaY) < 0.0001) return NO;
    return [self scrollDocumentClipViewByDeltaX:lineDeltaX * kSPDFMouseWheelPointsPerLine
                                         deltaY:lineDeltaY * kSPDFMouseWheelPointsPerLine];
}

- (BOOL)scrollPreciseTrackpadEventWithDamping:(NSEvent*)event {
    if (!event.hasPreciseScrollingDeltas) return NO;
    if (!self.documentView || !self.contentView) return NO;

    CGFloat deltaX = [self dampedPreciseScrollDelta:event.scrollingDeltaX
                                           momentum:event.momentumPhase != NSEventPhaseNone];
    CGFloat deltaY = [self dampedPreciseScrollDelta:event.scrollingDeltaY
                                           momentum:event.momentumPhase != NSEventPhaseNone];
    return [self scrollDocumentClipViewByDeltaX:deltaX deltaY:deltaY];
}

- (void)scrollWheel:(NSEvent*)event {
    // A real mouse/trackpad scroll takes over from any in-flight smooth
    // keyboard scroll so the two never fight over the clip-view origin.
    [self.reader stopKeyboardScrollAnimation];
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    // Cmd/Ctrl + wheel zooms; momentum falls through to the scroll path below
    // (see spdf_scroll_is_zoom_wheel).
    if (spdf_scroll_is_zoom_wheel(flags, event.momentumPhase != NSEventPhaseNone)) {
        // Out of focus the event tap sees this same scroll first and has already
        // zoomed with it; applying it again here would double every step.
        if (spdf_inactive_zoom_wheel_already_applied(event)) return;
        [self spdf_zoomWithScrollWheelEvent:event centeredAtWindowPoint:event.locationInWindow];
        return;
    }

    if ([self shouldSuppressResidualZoomWheelEvent:event]) {
        [self resetPageWheelGesture];
        return;
    }

    if (self.reader && [self.reader scrollViewShouldTurnWheelIntoPageChange:event]) {
        BOOL phaseBegan = [self eventPhase:event.phase contains:NSEventPhaseBegan] ||
                          [self eventPhase:event.phase contains:NSEventPhaseMayBegin];
        BOOL phaseEnded = [self eventPhase:event.phase contains:NSEventPhaseEnded] ||
                          [self eventPhase:event.phase contains:NSEventPhaseCancelled];
        if (phaseBegan) [self resetPageWheelGesture];
        if (event.momentumPhase != NSEventPhaseNone || phaseEnded) {
            [self resetPageWheelGesture];
            return;
        }
        if (_lastPageWheelEventTimestamp > 0.0 && event.timestamp - _lastPageWheelEventTimestamp > 0.35)
            [self resetPageWheelGesture];
        if (_wheelGestureActive && _wheelPageTurnedInGesture && event.hasPreciseScrollingDeltas) {
            _lastPageWheelEventTimestamp = event.timestamp;
            return;
        }
        if (!event.hasPreciseScrollingDeltas && _lastPageWheelTurnTimestamp > 0.0 &&
            event.timestamp - _lastPageWheelTurnTimestamp < 0.18) {
            _lastPageWheelEventTimestamp = event.timestamp;
            return;
        }

        CGFloat delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY;
        if (fabs(delta) < 0.0001) {
            _lastPageWheelEventTimestamp = event.timestamp;
            return;
        }
        NSInteger direction = delta < 0 ? -1 : 1;
        if (_wheelAccumulatorDirection != 0 && direction != _wheelAccumulatorDirection) {
            _wheelAccumulator = 0.0;
            _wheelPageTurnedInGesture = NO;
        }
        _wheelAccumulatorDirection = direction;
        _wheelGestureActive = YES;
        _wheelAccumulator += delta;
        CGFloat threshold = event.hasPreciseScrollingDeltas ? 0.75 : 0.50;
        if (fabs(_wheelAccumulator) >= threshold) {
            if (_wheelAccumulator < 0) [self.reader nextPage:self];
            else [self.reader previousPage:self];
            _wheelAccumulator = 0.0;
            _wheelPageTurnedInGesture = YES;
            _lastPageWheelTurnTimestamp = event.timestamp;
        }
        _lastPageWheelEventTimestamp = event.timestamp;
        return;
    }

    [self resetPageWheelGesture];
    if ([self scrollPreciseTrackpadEventWithDamping:event]) return;
    if ([self scrollMouseWheelEvent:event]) return;
    [super scrollWheel:event];
    if (self.reader) [self.reader documentScrollPositionChanged];
}

- (void)magnifyWithEvent:(NSEvent*)event {
    if (spdf_zoom_profile_enabled()) {
        double ageMs = (NSProcessInfo.processInfo.systemUptime - event.timestamp) * 1000.0;
        spdf_zoom_profile_log(@"focusedMagnify phase=%lu m=%.4f age=%.1fms", (unsigned long)event.phase,
                              (double)event.magnification, ageMs);
    }
    [self markZoomWheelAtTimestamp:event.timestamp];
    if (self.reader) [self.reader zoomWithMagnifyEvent:event centeredAtWindowPoint:event.locationInWindow];
}

- (void)spdf_magnifyWithEvent:(NSEvent*)event
                magnification:(CGFloat)magnification
        centeredAtWindowPoint:(NSPoint)windowPoint {
    [self markZoomWheelAtTimestamp:event.timestamp];
    if (self.reader) [self.reader zoomWithMagnifyDelta:magnification centeredAtWindowPoint:windowPoint];
}

// The single wheel-zoom entry, used by the focused responder-chain path and by
// the unfocused tap route alike, so both mark the residual-wheel window and
// convert the wheel delta to a zoom factor identically.
- (BOOL)spdf_zoomWithScrollWheelEvent:(NSEvent*)event centeredAtWindowPoint:(NSPoint)windowPoint {
    [self markZoomWheelAtTimestamp:event.timestamp];
    if (!self.reader) return NO;
    return [self.reader zoomWithScrollWheelEvent:event centeredAtWindowPoint:windowPoint];
}

- (void)keyDown:(NSEvent*)event {
    if (self.reader && [self.reader handlePresentationEvent:event]) return;
    if (self.reader && [self.reader documentArrowKeyDown:event]) return;
    if (self.reader && [self.reader documentTypeToSearchKeyDown:event]) return;
    [super keyDown:event];
}

@end

@implementation SPDFDocumentClipView

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _horizontalLockMinX = NAN;
        _horizontalLockMaxX = NAN;
        _verticalLockMinY = NAN;
        _verticalLockMaxY = NAN;
    }
    return self;
}

- (NSRect)constrainBoundsRect:(NSRect)proposedBounds {
    NSRect bounds = [super constrainBoundsRect:proposedBounds];
    if (isfinite(_horizontalLockMinX))
        bounds.origin.x = spdf_ui_clamp_cg(bounds.origin.x, _horizontalLockMinX, MAX(_horizontalLockMinX, _horizontalLockMaxX));
    if (isfinite(_verticalLockMinY))
        bounds.origin.y = spdf_ui_clamp_cg(bounds.origin.y, _verticalLockMinY, MAX(_verticalLockMinY, _verticalLockMaxY));
    return bounds;
}

@end

@implementation SPDFSidebarTableView

- (void)keyDown:(NSEvent*)event {
    // Escape clears the active search from the sidebar too (same as when the
    // document view is focused); with no active search it keeps its normal
    // table behavior.
    if (event.keyCode == 53 && self.reader && [self.reader documentEscapeKeyDown:event]) return;
    // Typing a printable character while the sidebar (e.g. search results) is
    // focused should start a fresh search — exactly as it does when typing after
    // clicking in the document — rather than driving the table's type-select.
    // Arrows / Enter / Tab / Delete keep their normal table behavior and fall
    // through to super.
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    BOOL hasModifier = (flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl |
                                 NSEventModifierFlagOption | NSEventModifierFlagFunction)) != 0;
    NSString* typed = event.characters ?: @"";
    BOOL printable = !hasModifier && typed.length > 0;
    if (printable) {
        NSCharacterSet* controls = NSCharacterSet.controlCharacterSet;
        for (NSUInteger i = 0; i < typed.length; ++i) {
            unichar ch = [typed characterAtIndex:i];
            // Reject control characters and the function-key range (arrows, F-keys,
            // page up/down, etc. all live at >= 0xF700) so they keep navigating.
            if (ch >= 0xF700 || [controls characterIsMember:ch]) {
                printable = NO;
                break;
            }
        }
    }
    if (printable && self.reader && [self.reader documentTypeToSearchKeyDown:event]) return;
    [super keyDown:event];
}

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
