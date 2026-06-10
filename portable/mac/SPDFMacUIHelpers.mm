#import "SPDFMacUIHelpers.h"
#import "SPDFMacSupport.h"

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

@interface SPDFScrollView (SPDFInactiveMagnifyRouting)
- (void)spdf_magnifyWithEvent:(NSEvent*)event
                magnification:(CGFloat)magnification
        centeredAtWindowPoint:(NSPoint)windowPoint;
@end

@interface NSView (SPDFInactiveMinimapMagnifyRouting)
- (BOOL)layoutScale:(CGFloat*)scaleOut
                gap:(CGFloat*)gapOut
         contentTop:(CGFloat*)contentTopOut
      contentHeight:(CGFloat*)contentHeightOut
        visibleRect:(NSRect*)visibleRectOut;
- (NSPoint)documentPointForMinimapCenterPoint:(NSPoint)point
                                        scale:(CGFloat)scale
                                          gap:(CGFloat)gap
                                contentHeight:(CGFloat)contentHeight
                                   contentTop:(CGFloat)contentTop;
@end

@interface SPDFWindow ()
- (BOOL)routeInactiveMagnifyEvent:(NSEvent*)event windowPoint:(NSPoint)windowPoint magnification:(CGFloat)magnification;
- (BOOL)routeInactiveMagnifyEvent:(NSEvent*)event screenPoint:(NSPoint)screenPoint magnification:(CGFloat)magnification;
@end

static NSHashTable<SPDFWindow*>* spdf_inactive_magnify_windows(void) {
    static NSHashTable<SPDFWindow*>* windows = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ windows = [NSHashTable weakObjectsHashTable]; });
    return windows;
}

static SPDFWindow* spdf_magnify_window_under_screen_point(NSPoint screenPoint) {
    NSInteger hitWindowNumber = [NSWindow windowNumberAtPoint:screenPoint belowWindowWithWindowNumber:0];
    if (hitWindowNumber <= 0) return nil;
    for (SPDFWindow* window in spdf_inactive_magnify_windows()) {
        if (window.windowNumber != hitWindowNumber) continue;
        if (!window.visible || window.miniaturized) return nil;
        return window;
    }
    return nil;
}

// Magnify NSEvents observed through a global monitor are rebuilt by AppKit from the other app's gesture
// CGEvents: `magnification` is filled with the gesture's CUMULATIVE zoom (CGEvent gesture field 113) and
// `phase` is left at NSEventPhaseNone, unlike responder-chain events which carry per-event deltas. This
// converts consecutive cumulative values back into the per-event deltas the zoom code expects. Gesture
// boundaries are detected via phase when present, otherwise via the gap between event timestamps; the
// first event after a boundary only establishes the baseline (its own delta is unknown and tiny).
static const NSTimeInterval kSPDFInactiveMagnifyGestureGapSeconds = 0.3;

static CGFloat spdf_global_magnify_delta(NSEvent* event) {
    static BOOL gestureActive = NO;
    static CGFloat lastCumulative = 0.0;
    static NSTimeInterval lastTimestamp = 0.0;

    CGFloat cumulative = event.magnification;
    NSEventPhase phase = event.phase;

    if (phase & (NSEventPhaseEnded | NSEventPhaseCancelled)) {
        CGFloat delta = gestureActive ? cumulative - lastCumulative : 0.0;
        gestureActive = NO;
        lastCumulative = 0.0;
        return delta;
    }
    // The other app's stream also contains legacy magnify CGEvents whose gesture payload does not survive
    // the monitor conversion (magnification reads 0); ignore them so they cannot corrupt the baseline.
    if (cumulative == 0.0 && phase == NSEventPhaseNone) return 0.0;

    BOOL gestureBreak = (phase & NSEventPhaseBegan) || !gestureActive ||
                        event.timestamp - lastTimestamp > kSPDFInactiveMagnifyGestureGapSeconds;
    CGFloat delta = gestureBreak ? 0.0 : cumulative - lastCumulative;
    gestureActive = YES;
    lastCumulative = cumulative;
    lastTimestamp = event.timestamp;
    return delta;
}

static void spdf_install_inactive_magnify_monitor(void) {
    static dispatch_once_t onceToken;
    static id spdf_global_magnify_monitor = nil;
    static id spdf_local_magnify_monitor = nil;
    dispatch_once(&onceToken, ^{
      // Another app is active: its event stream receives the pinch, so the magnify events are only observable
      // through a global monitor (global monitors never see events delivered to this app). These events carry
      // cumulative magnification, so they are converted to per-event deltas before routing. When this app is
      // active its own event stream (local monitor / responder chain) is authoritative and the global
      // observation is ignored, so no event can ever be applied through two paths.
      spdf_global_magnify_monitor = [NSEvent
          addGlobalMonitorForEventsMatchingMask:NSEventMaskMagnify
                                        handler:^(NSEvent* event) {
                                          if (NSApp.active) return;
                                          NSPoint screenPoint = NSEvent.mouseLocation;
                                          SPDFWindow* window = spdf_magnify_window_under_screen_point(screenPoint);
                                          if (!window || window.keyWindow) return;
                                          CGFloat delta = spdf_global_magnify_delta(event);
                                          if (spdf_zoom_profile_enabled()) {
                                              spdf_zoom_profile_log(@"inactiveMagnify path=global phase=%lu raw=%.4f "
                                                                    @"delta=%.4f",
                                                                    (unsigned long)event.phase,
                                                                    (double)event.magnification, (double)delta);
                                          }
                                          if (delta == 0.0) return;
                                          [window routeInactiveMagnifyEvent:event
                                                                screenPoint:screenPoint
                                                              magnification:delta];
                                        }];
      // This app is active: AppKit routes magnify events to the key window even when the cursor hovers another
      // ShenzhenPDF window, so reroute them to the window under the cursor and swallow the event. When the
      // cursor is over the key window itself the event is returned unchanged so the regular responder-chain
      // magnifyWithEvent: path handles it exactly once. These are first-class AppKit events whose
      // magnification is already a per-event delta.
      spdf_local_magnify_monitor = [NSEvent
          addLocalMonitorForEventsMatchingMask:NSEventMaskMagnify
                                       handler:^NSEvent*(NSEvent* event) {
                                         NSPoint screenPoint = NSEvent.mouseLocation;
                                         SPDFWindow* window = spdf_magnify_window_under_screen_point(screenPoint);
                                         if (!window || window.keyWindow) return event;
                                         if (spdf_zoom_profile_enabled()) {
                                             spdf_zoom_profile_log(@"inactiveMagnify path=local phase=%lu raw=%.4f",
                                                                   (unsigned long)event.phase,
                                                                   (double)event.magnification);
                                         }
                                         if ([window routeInactiveMagnifyEvent:event
                                                                   screenPoint:screenPoint
                                                                 magnification:event.magnification])
                                             return nil;
                                         return event;
                                       }];
      (void)spdf_global_magnify_monitor;
      (void)spdf_local_magnify_monitor;
    });
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

@implementation SPDFToolbarDragView

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
        spdf_install_inactive_magnify_monitor();
        [spdf_inactive_magnify_windows() addObject:self];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    self = [super initWithCoder:coder];
    if (self) {
        spdf_install_inactive_magnify_monitor();
        [spdf_inactive_magnify_windows() addObject:self];
    }
    return self;
}

- (void)dealloc {
    [spdf_inactive_magnify_windows() removeObject:self];
}

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return YES;
}

- (BOOL)routeInactiveMagnifyEvent:(NSEvent*)event windowPoint:(NSPoint)windowPoint magnification:(CGFloat)magnification {
    if (event.type != NSEventTypeMagnify || self.keyWindow || !self.visible || self.miniaturized) return NO;

    // Defensive: a genuine pinch never produces per-event deltas anywhere near this large, so anything
    // bigger is a misdecoded monitor event; swallow it instead of slamming the zoom.
    if (fabs(magnification) > 0.5) {
        if (spdf_zoom_profile_enabled())
            spdf_zoom_profile_log(@"inactiveMagnify dropped out-of-range delta=%.4f", (double)magnification);
        return YES;
    }

    NSView* contentView = self.contentView;
    if (!contentView) return NO;

    // hitTest: expects the point in the receiver's superview coordinate space.
    NSView* hitReference = contentView.superview ?: contentView;
    NSPoint contentPoint = [hitReference convertPoint:windowPoint fromView:nil];
    NSView* hitView = [contentView hitTest:contentPoint];
    Class minimapClass = NSClassFromString(@"SPDFMinimapView");
    for (NSView* view = hitView; view; view = view.superview) {
        if ([view isKindOfClass:SPDFScrollView.class]) {
            [(SPDFScrollView*)view spdf_magnifyWithEvent:event
                                           magnification:magnification
                                   centeredAtWindowPoint:windowPoint];
            return YES;
        }

        if (minimapClass && [view isKindOfClass:minimapClass]) {
            SEL documentPointSelector = @selector(documentPointForMinimapCenterPoint:scale:gap:contentHeight:contentTop:);
            if (![view respondsToSelector:@selector(layoutScale:gap:contentTop:contentHeight:visibleRect:)] ||
                ![view respondsToSelector:documentPointSelector])
                return NO;

            CGFloat scale = 1.0;
            CGFloat gap = 4.0;
            CGFloat contentTop = 8.0;
            CGFloat contentHeight = 0.0;
            if (![view layoutScale:&scale gap:&gap contentTop:&contentTop contentHeight:&contentHeight visibleRect:NULL])
                return NO;

            NSPoint minimapPoint = [view convertPoint:windowPoint fromView:nil];
            NSPoint documentPoint = [view documentPointForMinimapCenterPoint:minimapPoint
                                                                       scale:scale
                                                                         gap:gap
                                                               contentHeight:contentHeight
                                                                  contentTop:contentTop];
            id<SPDFMacUIReader> reader = [view valueForKey:@"reader"];
            if (!reader) return NO;
            [reader minimapViewDidReceiveMagnifyDelta:magnification documentPoint:documentPoint];
            return YES;
        }
    }
    return NO;
}

- (BOOL)routeInactiveMagnifyEvent:(NSEvent*)event screenPoint:(NSPoint)screenPoint magnification:(CGFloat)magnification {
    if (event.type != NSEventTypeMagnify || self.keyWindow || !self.visible || self.miniaturized) return NO;
    if (!NSPointInRect(screenPoint, self.frame)) return NO;
    return [self routeInactiveMagnifyEvent:event
                               windowPoint:[self convertPointFromScreen:screenPoint]
                             magnification:magnification];
}

- (BOOL)routeInactiveMagnifyEvent:(NSEvent*)event {
    if (event.type != NSEventTypeMagnify || self.keyWindow) return NO;
    // Events that reach sendEvent: were dispatched to this window by AppKit itself, so their
    // magnification is already a per-event delta.
    if (spdf_zoom_profile_enabled()) {
        spdf_zoom_profile_log(@"inactiveMagnify path=sendEvent phase=%lu raw=%.4f", (unsigned long)event.phase,
                              (double)event.magnification);
    }
    return [self routeInactiveMagnifyEvent:event windowPoint:event.locationInWindow magnification:event.magnification];
}

- (void)sendEvent:(NSEvent*)event {
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
    if (phaseBegan) return NO;
    BOOL phaseLess = event.phase == NSEventPhaseNone && event.momentumPhase == NSEventPhaseNone;
    if (phaseLess) return event.timestamp < _zoomWheelSuppressPhaseLessUntil;
    return event.timestamp < _zoomWheelSuppressMomentumUntil;
}

- (CGFloat)dampedPreciseScrollDelta:(CGFloat)delta momentum:(BOOL)momentum {
    CGFloat magnitude = fabs(delta);
    if (magnitude <= 18.0) return delta;

    CGFloat ratio = 1.0 - MIN((magnitude - 18.0) / 220.0, 1.0) * 0.55;
    if (momentum) ratio *= 0.72;
    ratio = MAX(momentum ? 0.30 : 0.45, ratio);
    return delta * ratio;
}

- (BOOL)scrollPreciseTrackpadEventWithDamping:(NSEvent*)event {
    if (!event.hasPreciseScrollingDeltas) return NO;
    if (!self.documentView || !self.contentView) return NO;

    CGFloat deltaX = [self dampedPreciseScrollDelta:event.scrollingDeltaX
                                           momentum:event.momentumPhase != NSEventPhaseNone];
    CGFloat deltaY = [self dampedPreciseScrollDelta:event.scrollingDeltaY
                                           momentum:event.momentumPhase != NSEventPhaseNone];
    if (fabs(deltaX) < 0.0001 && fabs(deltaY) < 0.0001) return YES;

    NSClipView* clipView = self.contentView;
    NSRect visible = clipView.bounds;
    NSSize documentSize = self.documentView.bounds.size;
    CGFloat maxX = MAX(0.0, documentSize.width - NSWidth(visible));
    CGFloat maxY = MAX(0.0, documentSize.height - NSHeight(visible));
    NSPoint origin = visible.origin;
    origin.x = spdf_ui_clamp_cg(origin.x - deltaX, 0.0, maxX);
    origin.y = spdf_ui_clamp_cg(origin.y - deltaY, 0.0, maxY);
    if (fabs(origin.x - NSMinX(visible)) < 0.0001 && fabs(origin.y - NSMinY(visible)) < 0.0001) return YES;

    [clipView scrollToPoint:origin];
    [self reflectScrolledClipView:clipView];
    if (self.reader) [self.reader documentScrollPositionChanged];
    return YES;
}

- (void)scrollWheel:(NSEvent*)event {
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    if (flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) {
        [self markZoomWheelAtTimestamp:event.timestamp];
        if (self.reader) [self.reader zoomWithScrollWheelEvent:event centeredAtWindowPoint:event.locationInWindow];
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
    [super scrollWheel:event];
    if (self.reader) [self.reader documentScrollPositionChanged];
}

- (void)magnifyWithEvent:(NSEvent*)event {
    [self markZoomWheelAtTimestamp:event.timestamp];
    if (self.reader) [self.reader zoomWithMagnifyEvent:event centeredAtWindowPoint:event.locationInWindow];
}

- (void)spdf_magnifyWithEvent:(NSEvent*)event
                magnification:(CGFloat)magnification
        centeredAtWindowPoint:(NSPoint)windowPoint {
    [self markZoomWheelAtTimestamp:event.timestamp];
    if (self.reader) [self.reader zoomWithMagnifyDelta:magnification centeredAtWindowPoint:windowPoint];
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
