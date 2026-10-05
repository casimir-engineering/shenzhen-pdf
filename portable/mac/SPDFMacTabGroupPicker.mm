#import "SPDFMacTabStripViewPrivate.h"

// Transient popovers dismiss before the anchor's mouseDown is delivered. Let
// the anchor own that click, otherwise its toggle sees "closed" and reopens it.
@interface SPDFTabGroupPickerPopover : NSPopover
@property(nonatomic, weak) SPDFTabStripView* anchorStrip;
- (BOOL)shouldCloseForEvent:(NSEvent*)event;
@end
@implementation SPDFTabGroupPickerPopover
- (BOOL)shouldCloseForEvent:(NSEvent*)event {
    SPDFTabStripView* strip = self.anchorStrip;
    if (!strip.window || event.window != strip.window ||
        (event.type != NSEventTypeLeftMouseDown && event.type != NSEventTypeLeftMouseUp)) return YES;
    NSPoint point = [strip convertPoint:event.locationInWindow fromView:nil];
    return !NSPointInRect(point,spdf_tab_strip_control_interaction_rect([strip overflowRect]));
}
- (BOOL)popoverShouldClose:(NSPopover*)popover {
    (void)popover; return [self shouldCloseForEvent:NSApp.currentEvent];
}
@end

@interface SPDFTabGroupPickerContent : NSView
@end
@implementation SPDFTabGroupPickerContent
- (void)drawRect:(NSRect)dirty {
    (void)dirty;
    [NSColor.windowBackgroundColor setFill]; NSRectFill(self.bounds);
}
@end

@interface SPDFTabGroupPickerRow : NSButton
@property(nonatomic,strong) SPDFTabGroup* group;
@property(nonatomic,copy) NSString* detail;
@end
@implementation SPDFTabGroupPickerRow
- (BOOL)isFlipped { return YES; }
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea* area in self.trackingAreas.copy) [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds
        options:NSTrackingMouseEnteredAndExited|NSTrackingActiveAlways|NSTrackingInVisibleRect owner:self userInfo:nil]];
}
- (void)mouseEntered:(NSEvent*)event { (void)event; [self setNeedsDisplay:YES]; }
- (void)mouseExited:(NSEvent*)event { (void)event; [self setNeedsDisplay:YES]; }
- (void)drawRect:(NSRect)dirty {
    (void)dirty;
    BOOL hovered = self.window && NSPointInRect([self convertPoint:self.window.mouseLocationOutsideOfEventStream
        fromView:nil],self.bounds);
    if (hovered || self.highlighted || (self.group && !self.group.collapsed && !self.group.hidden)) {
        [[NSColor.labelColor colorWithAlphaComponent:0.07] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:5 yRadius:5] fill];
    }
    NSImage* icon = [NSImage imageWithSystemSymbolName:self.group.collectionBackups ? @"books.vertical" : self.group ? @"square.3.layers.3d" : @"slider.horizontal.3"
                            accessibilityDescription:nil];
    NSColor* color = self.group ? spdf_tab_group_accent(self.group.colorName) : NSColor.secondaryLabelColor;
    icon = [icon imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPaletteColors:@[color]]];
    [icon drawInRect:NSMakeRect(8,8,16,16) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
            fraction:1 respectFlipped:YES hints:nil];
    NSMutableParagraphStyle* paragraph = [NSMutableParagraphStyle new];
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary* attributes = @{NSFontAttributeName:[NSFont systemFontOfSize:12],
        NSForegroundColorAttributeName:NSColor.labelColor,NSParagraphStyleAttributeName:paragraph};
    CGFloat detailWidth = self.detail.length ? [self.detail sizeWithAttributes:attributes].width : 0;
    [self.title drawInRect:NSMakeRect(32,8,NSWidth(self.bounds)-48-detailWidth,16) withAttributes:attributes];
    if (self.detail.length) [self.detail drawInRect:NSMakeRect(NSWidth(self.bounds)-8-detailWidth,8,detailWidth,16)
        withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:11],NSForegroundColorAttributeName:NSColor.secondaryLabelColor}];
    if (self.window.firstResponder == self) {
        [NSColor.keyboardFocusIndicatorColor setStroke];
        NSBezierPath* focus = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,1) xRadius:5 yRadius:5];
        focus.lineWidth=2; [focus stroke];
    }
}
@end

@implementation SPDFTabStripView (GroupPicker)
- (NSView*)groupPickerContentView {
    NSMutableArray<SPDFTabGroup*>* groups = [NSMutableArray array];
    NSMutableDictionary<NSString*,NSNumber*>* counts = [NSMutableDictionary dictionary];
    for (SPDFDocumentTab* tab in self.tabs) {
        SPDFTabGroup* group=tab.group;
        if (!group) continue;
        if (!counts[group.identifier]) [groups addObject:group];
        counts[group.identifier]=@([counts[group.identifier] integerValue]+1);
    }
    // Construct only on demand; no extra view tree or model traversal at launch.
    NSView* content = [[SPDFTabGroupPickerContent alloc] initWithFrame:NSMakeRect(0,0,236,groups.count*32+52)];
    CGFloat y=NSHeight(content.bounds)-38;
    for (SPDFTabGroup* group in groups) {
        SPDFTabGroupPickerRow* row=[[SPDFTabGroupPickerRow alloc] initWithFrame:NSMakeRect(6,y,224,32)];
        row.group=group; row.title=group.displayName;
        row.detail=[NSString stringWithFormat:@"%@%@",group.hidden ? @"Hidden · " : @"",counts[group.identifier]];
        row.bordered=NO; row.target=self; row.action=@selector(browseGroupPickerRow:);
        row.accessibilityLabel=[NSString stringWithFormat:@"%@, %@ documents%@",group.displayName,counts[group.identifier],group.hidden ? @", hidden" : @""];
        row.toolTip=[NSString stringWithFormat:@"Show %@ tabs without changing the document",group.displayName];
        row.frame=NSMakeRect(6,y,198,32);
        NSButton* eye=[[NSButton alloc] initWithFrame:NSMakeRect(204,y+4,26,24)];
        eye.bordered=NO; eye.image=[NSImage imageWithSystemSymbolName:group.hidden ? @"eye.slash" : @"eye"
            accessibilityDescription:group.hidden ? @"Show group" : @"Hide group"];
        eye.target=self; eye.action=@selector(toggleGroupPickerVisibility:); eye.identifier=group.identifier;
        eye.toolTip=group.hidden ? @"Show group in tab bar" : @"Hide group from tab bar";
        eye.accessibilityLabel=[NSString stringWithFormat:@"%@ %@",group.hidden ? @"Show" : @"Hide",group.displayName];
        [content addSubview:row]; [content addSubview:eye]; y-=32;
    }
    NSBox* line=[[NSBox alloc] initWithFrame:NSMakeRect(6,40,224,1)]; line.boxType=NSBoxSeparator;
    [content addSubview:line];
    SPDFTabGroupPickerRow* manage=[[SPDFTabGroupPickerRow alloc] initWithFrame:NSMakeRect(6,5,224,32)];
    manage.title=@"Manage groups"; manage.bordered=NO; manage.target=self; manage.action=@selector(manageGroupsFromPicker:);
    [content addSubview:manage];
    return content;
}
- (void)browseGroupPickerRow:(SPDFTabGroupPickerRow*)sender {
    [_groupPicker close];
    SPDFTabGroup* group=sender.group;
    if (group.hidden) [self.groupReader setTabGroup:group hidden:NO];
    if (group.collapsed) [self.groupReader toggleTabGroup:group];
}
- (void)toggleGroupPickerVisibility:(NSButton*)sender {
    for (SPDFDocumentTab* tab in self.tabs) if ([tab.group.identifier isEqual:sender.identifier]) {
        [self.groupReader setTabGroup:tab.group hidden:!tab.group.hidden];
        sender.image=[NSImage imageWithSystemSymbolName:tab.group.hidden ? @"eye.slash" : @"eye" accessibilityDescription:nil];
        sender.toolTip=tab.group.hidden ? @"Show group in tab bar" : @"Hide group from tab bar";
        sender.accessibilityLabel=[NSString stringWithFormat:@"%@ %@",tab.group.hidden ? @"Show" : @"Hide",tab.group.displayName];
        return;
    }
}
- (void)manageGroupsFromPicker:(id)sender {
    [_groupPicker close];
    [NSApp sendAction:NSSelectorFromString(@"showGroupsSidebar:") to:self.reader from:sender];
}
- (void)showGroupPicker {
    if (_groupPicker.shown) { [_groupPicker close]; return; }
    [self dismissHoverPanel];
    NSView* content=[self groupPickerContentView];
    NSViewController* controller=[NSViewController new];
    if (NSHeight(content.frame)>420) {
        NSScrollView* scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,236,420)];
        scroll.hasVerticalScroller=YES; scroll.drawsBackground=NO; scroll.documentView=content;
        controller.view=scroll;
        [content scrollPoint:NSMakePoint(0,NSHeight(content.frame)-420)];
    } else controller.view=content;
    SPDFTabGroupPickerPopover* picker=[SPDFTabGroupPickerPopover new]; picker.anchorStrip=self;
    _groupPicker=picker; _groupPicker.behavior=NSPopoverBehaviorTransient;
    _groupPicker.animates=NO; _groupPicker.contentViewController=controller;
    [_groupPicker showRelativeToRect:[self overflowRect] ofView:self preferredEdge:NSRectEdgeMinY];
}
@end
