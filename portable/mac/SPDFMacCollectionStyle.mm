#import "SPDFMacCollectionStyle.h"
static NSColor* Hex(unsigned value) {
    return [NSColor colorWithSRGBRed:((value>>16)&255)/255.0 green:((value>>8)&255)/255.0 blue:(value&255)/255.0 alpha:1];
}
NSColor* SPDFCollectionColor(NSString* token) {
    NSDictionary* palette = @{@"window":@[@0xfafafa,@0x252729],@"sidebar":@[@0xedeeef,@0x202224],
        @"pane":@[@0xffffff,@0x2b2d2f],@"text":@[@0x202124,@0xededee],@"secondary":@[@0x50545a,@0xc6c9cc],
        @"line":@[@0xd9dbde,@0x484b4e],@"control":@[@0xffffff,@0x404346],@"selected":@[@0xd9e8fc,@0x334c6c],
        @"accent":@[@0x075dbb,@0x9ac8ff],@"highlight":@[@0xffe59a,@0x685521]};
    NSArray* pair = palette[token] ?: palette[@"text"];
    return [NSColor colorWithName:[@"Collection." stringByAppendingString:token] dynamicProvider:^NSColor*(NSAppearance* appearance) {
        BOOL dark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]] isEqual:NSAppearanceNameDarkAqua];
        return Hex([pair[dark ? 1 : 0] unsignedIntValue]);
    }];
}
@interface SPDFCollectionSurfaceView : NSView
@property(nonatomic) NSString* token;
@end
@implementation SPDFCollectionSurfaceView
- (BOOL)wantsDefaultClipping { return YES; }
- (void)drawRect:(NSRect)dirty { (void)dirty; [SPDFCollectionColor(self.token) setFill]; NSRectFill(self.bounds); }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES; }
@end
@interface SPDFCollectionFlatButton : NSButton
@property(nonatomic) NSString* kind;
@end
@implementation SPDFCollectionFlatButton
- (NSEdgeInsets)alignmentRectInsets { return NSEdgeInsetsMake(0,0,0,0); }
- (NSSize)intrinsicContentSize {
    CGFloat width = [self.title sizeWithAttributes:@{NSFontAttributeName:self.font ?: [NSFont systemFontOfSize:13]}].width;
    return NSMakeSize(ceil(width)+18+(self.image ? 24 : 0),[self.kind isEqual:@"nav"] ? 32 : 26);
}
- (void)setState:(NSControlStateValue)state { [super setState:state]; self.needsDisplay = YES; }
- (void)setEnabled:(BOOL)enabled { [super setEnabled:enabled]; self.needsDisplay = YES; }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES; }
- (void)drawRect:(NSRect)dirty {
    (void)dirty; BOOL quiet = ![self.kind isEqual:@"normal"];
    BOOL selected = self.state == NSControlStateValueOn || self.highlighted;
    NSBezierPath* shape = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,.5,.5) xRadius:5 yRadius:5];
    if (!quiet || selected) { [SPDFCollectionColor(selected ? @"selected" : @"control") setFill]; [shape fill]; }
    if (!quiet) { [SPDFCollectionColor(@"line") setStroke]; shape.lineWidth = 1; [shape stroke]; }
    NSRect titleRect = NSInsetRect(self.bounds,9,3);
    if (self.image) {
        NSRect icon = NSMakeRect(NSMinX(titleRect),floor(NSMidY(self.bounds)-7.5),15,15);
        NSImage* symbol = self.image;
        if (@available(macOS 12.0,*)) symbol = [symbol imageWithSymbolConfiguration:
            [NSImageSymbolConfiguration configurationWithPaletteColors:@[SPDFCollectionColor(@"text")]]] ?: symbol;
        [symbol drawInRect:icon fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:self.enabled ? 1 : .55 respectFlipped:YES hints:nil];
        titleRect.origin.x += 24; titleRect.size.width -= 24;
    }
    NSMutableAttributedString* title = [self.attributedTitle mutableCopy];
    NSMutableParagraphStyle* paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = [self.kind isEqual:@"nav"] ? NSTextAlignmentLeft : self.alignment;
    paragraph.lineBreakMode = self.cell.wraps ? NSLineBreakByWordWrapping : NSLineBreakByTruncatingTail;
    paragraph.lineSpacing = self.cell.wraps ? 3 : 0;
    if ([self.kind isEqual:@"match"]) {
        paragraph.headIndent = 45;
        paragraph.tabStops = @[[[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentLeft location:45 options:@{}]];
        [title addAttribute:NSParagraphStyleAttributeName value:paragraph range:NSMakeRange(0,title.length)];
    } else {
        [title addAttributes:@{NSFontAttributeName:self.font ?: [NSFont systemFontOfSize:13],
            NSForegroundColorAttributeName:[SPDFCollectionColor([self.kind isEqual:@"link"] ? @"accent" : @"text") colorWithAlphaComponent:self.enabled ? 1 : .55],
            NSParagraphStyleAttributeName:paragraph} range:NSMakeRange(0,title.length)];
    }
    NSRect measured = [title boundingRectWithSize:titleRect.size options:NSStringDrawingUsesLineFragmentOrigin];
    if (!self.cell.wraps) { titleRect.origin.y = floor(NSMidY(self.bounds)-measured.size.height/2); titleRect.size.height = measured.size.height; }
    [title drawWithRect:titleRect options:NSStringDrawingUsesLineFragmentOrigin];
    if (self.window.firstResponder == self) { [NSGraphicsContext saveGraphicsState]; NSSetFocusRingStyle(NSFocusRingOnly); [shape fill]; [NSGraphicsContext restoreGraphicsState]; }
}
@end
@interface SPDFCollectionFlatPopUp : NSPopUpButton
@end
@implementation SPDFCollectionFlatPopUp
- (NSEdgeInsets)alignmentRectInsets { return NSEdgeInsetsMake(0,0,0,0); }
- (NSSize)intrinsicContentSize {
    CGFloat width = 0;
    for (NSString* title in self.itemTitles) width = MAX(width,[title sizeWithAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:13]}].width);
    return NSMakeSize(ceil(width)+34,26);
}
- (void)drawRect:(NSRect)dirty {
    (void)dirty; NSBezierPath* shape = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,.5,.5) xRadius:5 yRadius:5];
    [SPDFCollectionColor(@"control") setFill]; [shape fill]; [SPDFCollectionColor(@"line") setStroke]; [shape stroke];
    NSMutableParagraphStyle* paragraph = [NSMutableParagraphStyle new]; paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary* attributes = @{NSFontAttributeName:[NSFont systemFontOfSize:13],NSForegroundColorAttributeName:SPDFCollectionColor(@"text"),NSParagraphStyleAttributeName:paragraph};
    [self.title drawInRect:NSMakeRect(9,floor((NSHeight(self.bounds)-16)/2),NSWidth(self.bounds)-32,18) withAttributes:attributes];
    NSImage* image = [NSImage imageWithSystemSymbolName:@"chevron.down" accessibilityDescription:nil];
    if (@available(macOS 12.0,*)) image = [image imageWithSymbolConfiguration:
        [NSImageSymbolConfiguration configurationWithPaletteColors:@[SPDFCollectionColor(@"text")]]] ?: image;
    [image drawInRect:NSMakeRect(NSWidth(self.bounds)-20,floor(NSMidY(self.bounds)-5),10,10)];
    if (self.window.firstResponder == self) { [NSGraphicsContext saveGraphicsState]; NSSetFocusRingStyle(NSFocusRingOnly); [shape fill]; [NSGraphicsContext restoreGraphicsState]; }
}
@end
static NSBezierPath* SearchShape(NSRect bounds) {
    return [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds,.5,.5) xRadius:6 yRadius:6];
}
@interface SPDFCollectionSearchCell : NSSearchFieldCell
@property(nonatomic) BOOL editingRectPrepared;
@end
@implementation SPDFCollectionSearchCell
- (NSRect)focusRingMaskBoundsForFrame:(NSRect)frame inView:(NSView*)view { (void)view; return frame; }
- (void)drawFocusRingMaskWithFrame:(NSRect)frame inView:(NSView*)view { (void)view; [SearchShape(frame) fill]; }
// Borderless search chrome needs the same inset for static text and the AppKit field editor.
// The inherited editing methods otherwise use the entire 31-point control bounds.
- (void)selectWithFrame:(NSRect)frame inView:(NSView*)view editor:(NSText*)editor delegate:(id)delegate
                  start:(NSInteger)start length:(NSInteger)length {
    BOOL prepared = self.editingRectPrepared; self.editingRectPrepared = YES;
    [super selectWithFrame:prepared ? frame : [self searchTextRectForBounds:frame] inView:view
        editor:editor delegate:delegate start:start length:length];
    self.editingRectPrepared = prepared;
}
- (void)editWithFrame:(NSRect)frame inView:(NSView*)view editor:(NSText*)editor delegate:(id)delegate event:(NSEvent*)event {
    BOOL prepared = self.editingRectPrepared; self.editingRectPrepared = YES;
    [super editWithFrame:prepared ? frame : [self searchTextRectForBounds:frame] inView:view
        editor:editor delegate:delegate event:event];
    self.editingRectPrepared = prepared;
}
- (NSRect)searchTextRectForBounds:(NSRect)bounds {
    CGFloat height = ceil((self.font ?: [NSFont systemFontOfSize:13]).ascender - (self.font ?: [NSFont systemFontOfSize:13]).descender + 2);
    return NSMakeRect(NSMinX(bounds)+29,floor(NSMidY(bounds)-height/2),MAX(0,NSWidth(bounds)-54),height);
}
- (NSRect)drawingRectForBounds:(NSRect)bounds { return [self searchTextRectForBounds:bounds]; }
- (NSRect)titleRectForBounds:(NSRect)bounds { return [self searchTextRectForBounds:bounds]; }
- (NSRect)searchButtonRectForBounds:(NSRect)bounds {
    return NSMakeRect(NSMinX(bounds)+9,floor(NSMidY(bounds)-7.5),15,15);
}
- (NSRect)cancelButtonRectForBounds:(NSRect)bounds {
    return NSMakeRect(NSMaxX(bounds)-24,floor(NSMidY(bounds)-7.5),15,15);
}
@end
@interface SPDFCollectionFlatSearch : NSSearchField
@end
@implementation SPDFCollectionFlatSearch
- (NSRect)focusRingMaskBounds { return self.bounds; }
- (void)drawFocusRingMask { [SearchShape(self.bounds) fill]; }
- (NSEdgeInsets)alignmentRectInsets { return NSEdgeInsetsMake(0,0,0,0); }
- (void)drawRect:(NSRect)dirty {
    NSBezierPath* shape = SearchShape(self.bounds);
    [SPDFCollectionColor(@"pane") setFill]; [shape fill]; [SPDFCollectionColor(@"line") setStroke]; [shape stroke];
    [super drawRect:dirty];
}
@end
NSButton* SPDFCollectionButton(NSString* title,id target,SEL action,NSString* kind) {
    SPDFCollectionFlatButton* button = [[SPDFCollectionFlatButton alloc] init]; button.kind = kind;
    button.title = title; button.target = target; button.action = action; button.bordered = NO;
    button.font = [NSFont systemFontOfSize:13]; button.alignment = NSTextAlignmentCenter;
    // AppKit defaults to wrapping, which pins a single label to the top inset.
    // Contextual match buttons opt into multiline wrapping after construction.
    button.cell.wraps = NO;
    button.focusRingType = NSFocusRingTypeExterior; return button;
}
NSPopUpButton* SPDFCollectionPopUp(void) {
    SPDFCollectionFlatPopUp* button = [SPDFCollectionFlatPopUp new]; button.bordered = NO;
    button.font = [NSFont systemFontOfSize:13]; [button.heightAnchor constraintEqualToConstant:26].active = YES; return button;
}
NSSearchField* SPDFCollectionSearchField(void) {
    SPDFCollectionFlatSearch* field = [SPDFCollectionFlatSearch new];
    field.cell = [[SPDFCollectionSearchCell alloc] initTextCell:@""]; field.bordered = NO; field.bezeled = NO;
    field.editable = YES; field.selectable = YES; field.cell.usesSingleLineMode = YES; field.cell.scrollable = YES;
    field.drawsBackground = NO; field.font = [NSFont systemFontOfSize:13]; field.textColor = SPDFCollectionColor(@"text"); return field;
}
NSTextField* SPDFCollectionText(NSString* text,CGFloat size,NSFontWeight weight,BOOL secondary) {
    NSTextField* field = [NSTextField wrappingLabelWithString:text]; field.font = [NSFont systemFontOfSize:size weight:weight];
    field.textColor = SPDFCollectionColor(secondary ? @"secondary" : @"text"); return field;
}
NSView* SPDFCollectionSurface(NSString* token) { SPDFCollectionSurfaceView* view = [SPDFCollectionSurfaceView new]; view.token = token; return view; }
NSView* SPDFCollectionDivider(void) { NSView* line = SPDFCollectionSurface(@"line"); [line.heightAnchor constraintEqualToConstant:1].active = YES; return line; }
