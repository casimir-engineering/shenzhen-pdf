#import "SPDFMacUIHelpers.h"

// The two custom-drawn buttons of the document toolbar: a labelled switch and a
// three-dot overflow button. Both own their whole appearance, hold no
// application state, and depend on nothing but AppKit -- lifted out of
// SPDFMacUIHelpers.mm, whose size cap asks that further additions go to a
// focused file rather than back onto that mixed pile.

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
