#import "SPDFMacGroupManagement.h"
#import "SPDFMacTabGroups.h"

@interface SPDFGroupManagementTable : NSTableView
@end
@implementation SPDFGroupManagementTable
- (void)keyDown:(NSEvent*)event {
    if (event.keyCode == 36 || event.keyCode == 76) {
        [NSApp sendAction:@selector(activateSelectedRow:) to:self.target from:self]; return;
    }
    [super keyDown:event];
}
@end
@interface SPDFGroupSearchField : NSSearchField
@end
@implementation SPDFGroupSearchField
- (NSRect)focusRingMaskBounds { return NSInsetRect(self.bounds,.5,.5); }
- (void)drawFocusRingMask {
    [[NSBezierPath bezierPathWithRoundedRect:self.focusRingMaskBounds xRadius:MIN(14,NSHeight(self.bounds)/2)
        yRadius:MIN(14,NSHeight(self.bounds)/2)] fill];
}
@end
@interface SPDFGroupManagementRow : NSTableRowView
@end
@implementation SPDFGroupManagementRow
- (void)drawSelectionInRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect rect = NSInsetRect(self.bounds,3,1);
    NSClipView* clip = self.enclosingScrollView.contentView;
    if (clip) {
        NSRect viewport = [self convertRect:clip.bounds fromView:clip];
        CGFloat right = MIN(NSMaxX(rect),NSMaxX(viewport)-3);
        rect.origin.x = MAX(rect.origin.x,NSMinX(viewport)+3); rect.size.width = MAX(0,right-NSMinX(rect));
    }
    [[NSColor.controlAccentColor colorWithAlphaComponent:.14] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:7 yRadius:7] fill];
}
@end
@interface SPDFGroupActionButton : NSButton
@property(nonatomic, copy) NSString* groupID;
@end
@implementation SPDFGroupActionButton
@end

static NSTextField* Label(NSString* text, CGFloat size, BOOL secondary) {
    NSTextField* label = [NSTextField labelWithString:text ?: @""];
    label.font = [NSFont systemFontOfSize:size];
    label.textColor = secondary ? NSColor.secondaryLabelColor : NSColor.labelColor;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}
static SPDFGroupActionButton* Icon(NSString* symbol, NSString* help, id target, SEL action) {
    SPDFGroupActionButton* button = [SPDFGroupActionButton new];
    button.bordered = NO; button.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:help];
    button.target = target; button.action = action; button.toolTip = help;
    [button setAccessibilityLabel:help];
    [button.widthAnchor constraintEqualToConstant:26].active = YES;
    [button.heightAnchor constraintEqualToConstant:26].active = YES;
    return button;
}
@implementation SPDFGroupManagementController {
    NSSearchField* _search;
    NSTextField* _summary;
    NSTextField* _empty;
    NSTableView* _table;
    NSScrollView* _scroll;
    NSArray<NSDictionary*>* _groups;
    NSArray<NSDictionary*>* _rows;
    NSMutableSet<NSString*>* _expanded;
    BOOL _restoring;
    CGFloat _savedScroll;
    BOOL _pendingScrollRestore;
    BOOL _hasSnapshot;
}
- (void)loadView {
    self.view = [NSView new];
    _summary = Label(@"",11,YES);
    _search = [SPDFGroupSearchField new]; _search.placeholderString = @"Search groups"; _search.toolTip = @"Search group names, not document titles.";
    _search.delegate = self; _search.sendsSearchStringImmediately = YES;
    [_search setAccessibilityLabel:@"Search group names"];
    _search.focusRingType = NSFocusRingTypeExterior;
    _table = [SPDFGroupManagementTable new]; _table.headerView = nil; _table.dataSource = self; _table.delegate = self;
    _table.backgroundColor = NSColor.clearColor; _table.style = NSTableViewStylePlain; _table.intercellSpacing = NSMakeSize(0,2);
    _table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    _table.target = self; _table.action = @selector(activateRow:);
    NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"group"];
    [_table addTableColumn:column]; _table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    [_table setAccessibilityLabel:@"Groups and documents"];
    [_table setAccessibilityHelp:@"Select with the arrow keys, then press Return to open a group or document."];
    NSMenu* menu = [NSMenu new]; menu.delegate = self; _table.menu = menu;
    _scroll = [NSScrollView new]; _scroll.documentView = _table; _scroll.hasVerticalScroller = YES;
    _scroll.drawsBackground = NO; _scroll.automaticallyAdjustsContentInsets = NO; _scroll.contentInsets = NSEdgeInsetsZero; _scroll.contentView.postsBoundsChangedNotifications = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(scrolled:)
        name:NSViewBoundsDidChangeNotification object:_scroll.contentView];
    _empty = [NSTextField wrappingLabelWithString:@""]; _empty.textColor = NSColor.secondaryLabelColor;
    _empty.alignment = NSTextAlignmentCenter; _empty.hidden = YES;
    NSString* help = @"Hidden groups stay open. Hiding removes their tabs from the tab bar without closing documents.";
    _summary.toolTip = help; [_summary setAccessibilityHelp:help];
    NSImageView* info = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"info.circle" accessibilityDescription:help]];
    info.contentTintColor = NSColor.secondaryLabelColor; info.toolTip = help;
    [info.widthAnchor constraintEqualToConstant:12].active = YES;
    [_summary setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView* footer = [NSStackView stackViewWithViews:@[_summary,info]]; footer.spacing = 6;
    for (NSView* child in @[_search,_scroll,_empty,footer]) { child.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:child]; }
    [NSLayoutConstraint activateConstraints:@[
        [_search.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:8],
        [_search.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [_search.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [_search.heightAnchor constraintEqualToConstant:26],
        [_scroll.topAnchor constraintEqualToAnchor:_search.bottomAnchor constant:8],
        [_scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:4],
        [_scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-4],
        [_scroll.bottomAnchor constraintEqualToAnchor:footer.topAnchor],
        [footer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [footer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [footer.heightAnchor constraintEqualToConstant:22],
        [footer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_empty.topAnchor constraintEqualToAnchor:_scroll.topAnchor constant:20],
        [_empty.leadingAnchor constraintEqualToAnchor:_search.leadingAnchor],
        [_empty.trailingAnchor constraintEqualToAnchor:_search.trailingAnchor]]];
    _expanded = [NSMutableSet set]; _groups = @[]; _rows = @[];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (NSDictionary*)viewState {
    return @{@"groupQuery":_search.stringValue ?: @"",@"expandedGroups":[_expanded.allObjects sortedArrayUsingSelector:@selector(compare:)],
             @"groupScroll":@(MAX(0,_savedScroll))};
}
- (void)publishState { if (!_restoring && self.stateHandler) self.stateHandler(self.viewState); }
- (void)updateGroups:(NSArray<NSDictionary*>*)groups state:(NSDictionary*)state {
    (void)self.view;
    NSString* query = [state[@"groupQuery"] isKindOfClass:NSString.class] ? state[@"groupQuery"] : @"";
    NSMutableSet* expanded = [NSMutableSet set];
    for (id identifier in [state[@"expandedGroups"] isKindOfClass:NSArray.class] ? state[@"expandedGroups"] : @[])
        if ([identifier isKindOfClass:NSString.class]) [expanded addObject:identifier];
    CGFloat scroll = [state[@"groupScroll"] respondsToSelector:@selector(doubleValue)] ? MAX(0,[state[@"groupScroll"] doubleValue]) : 0;
    if (!isfinite(scroll)) scroll = 0;
    if (_hasSnapshot && [_groups isEqualToArray:groups ?: @[]] && [_search.stringValue isEqual:query] &&
        [_expanded isEqualToSet:expanded] && fabs(_savedScroll-scroll)<.5) return;
    _restoring = YES; _hasSnapshot = YES; _groups = groups.copy ?: @[];
    if (![_search.stringValue isEqual:query]) _search.stringValue = query;
    _expanded = expanded; _savedScroll = scroll; _pendingScrollRestore = YES;
    [self rebuildRows]; [self.view layoutSubtreeIfNeeded];
    [self restoreScrollIfReady];
    _restoring = NO;
}
- (void)rebuildRows {
    NSMutableArray* rows = [NSMutableArray array]; NSUInteger hidden = 0, matched = 0;
    for (NSDictionary* group in _groups) {
        hidden += [group[@"hidden"] boolValue];
        if (_search.stringValue.length && [group[@"name"] rangeOfString:_search.stringValue
            options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location == NSNotFound) continue;
        ++matched; [rows addObject:@{@"group":group}];
        if ([_expanded containsObject:group[@"id"]])
            for (NSDictionary* document in group[@"documents"]) [rows addObject:@{@"group":group,@"document":document}];
    }
    _rows = rows;
    _summary.stringValue = _search.stringValue.length ? [NSString stringWithFormat:@"%lu of %lu groups",matched,_groups.count] :
        [NSString stringWithFormat:@"%lu %@ · %lu hidden",_groups.count,_groups.count==1 ? @"group" : @"groups",hidden];
    _empty.stringValue = _groups.count ? @"No matching groups.\nTry another group name." : @"Open a document to start organizing your groups.";
    _empty.hidden = rows.count > 0; [_table reloadData];
    NSInteger selected = -1;
    for (NSUInteger index=0;index<rows.count;index++) {
        NSDictionary* row = rows[index];
        if ([row[@"document"][@"selected"] boolValue]) { selected = index; break; }
        if (!row[@"document"] && [row[@"group"][@"selected"] boolValue]) selected = index;
    }
    [_table selectRowIndexes:selected >= 0 ? [NSIndexSet indexSetWithIndex:selected] : [NSIndexSet indexSet] byExtendingSelection:NO];
}
- (void)viewDidLayout {
    [super viewDidLayout];
    CGFloat width = NSWidth(_scroll.contentView.bounds);
    if (width > 0) {
        _table.tableColumns.firstObject.width = width;
        [_table setFrameSize:NSMakeSize(width,NSHeight(_table.frame))];
    }
    [self restoreScrollIfReady];
}
- (void)restoreScrollIfReady {
    if (!_pendingScrollRestore || !self.view.window || NSHeight(_scroll.contentView.bounds) <= 1 || NSWidth(_scroll.contentView.bounds) <= 1) return;
    BOOL wasRestoring = _restoring; _restoring = YES;
    NSRect bounds = _scroll.contentView.bounds; bounds.origin = NSMakePoint(0,_savedScroll);
    bounds = [_scroll.contentView constrainBoundsRect:bounds];
    [_scroll.contentView scrollToPoint:bounds.origin]; [_scroll reflectScrolledClipView:_scroll.contentView];
    _savedScroll = MAX(0,bounds.origin.y); _pendingScrollRestore = NO; _restoring = wasRestoring;
}
- (NSTableRowView*)tableView:(NSTableView*)table rowViewForRow:(NSInteger)row {
    (void)table; (void)row; return [SPDFGroupManagementRow new];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView*)table { (void)table; return _rows.count; }
- (CGFloat)tableView:(NSTableView*)table heightOfRow:(NSInteger)row { (void)table; return _rows[row][@"document"] ? 26 : 36; }
- (NSView*)tableView:(NSTableView*)table viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
    (void)table; (void)column; NSDictionary* item = _rows[row], *group = item[@"group"], *document = item[@"document"];
    NSView* container = [NSView new];
    NSStackView* contents;
    if (document) {
        NSImageView* icon = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:[document[@"selected"] boolValue] ? @"doc.fill" : @"doc" accessibilityDescription:nil]];
        icon.contentTintColor = [document[@"selected"] boolValue] ? NSColor.controlAccentColor : NSColor.secondaryLabelColor; [icon.widthAnchor constraintEqualToConstant:12].active = YES;
        NSTextField* label = Label(document[@"title"],12,NO); label.toolTip = document[@"path"];
        if ([document[@"selected"] boolValue]) label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
        contents = [NSStackView stackViewWithViews:@[icon,label]]; contents.spacing = 5;
    } else {
        BOOL expanded = [_expanded containsObject:group[@"id"]];
        SPDFGroupActionButton* disclosure = Icon(expanded ? @"chevron.down" : @"chevron.right",
            [NSString stringWithFormat:@"%@ %@ documents",expanded ? @"Collapse" : @"Expand",group[@"name"]],self,@selector(disclose:)); disclosure.groupID = group[@"id"];
        NSImageView* swatch = [NSImageView imageViewWithImage:spdf_tab_group_swatch_image(group[@"color"])];
        [swatch.widthAnchor constraintEqualToConstant:8].active = YES;
        NSTextField* name = Label(group[@"name"],12,NO);
        [name setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal]; name.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
        name.toolTip = group[@"name"];
        NSUInteger count = [group[@"documents"] count];
        NSString* status = [NSString stringWithFormat:@"%lu%@%@%@",count,
            [group[@"hidden"] boolValue] || [group[@"selected"] boolValue] ? @"" : (count==1 ? @" document" : @" documents"),
            [group[@"hidden"] boolValue] ? @" · Hidden" : @"",[group[@"selected"] boolValue] ? @" · Active" : @""];
        BOOL hiddenAndActive = [group[@"hidden"] boolValue] && [group[@"selected"] boolValue];
        if (hiddenAndActive) name.stringValue = [NSString stringWithFormat:@"%@ (%lu)",group[@"name"],count];
        NSTextField* statusLabel = Label(hiddenAndActive ? @"Hidden · Active" : status,11,YES); statusLabel.toolTip = status;
        [statusLabel setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSStackView* labels = [NSStackView stackViewWithViews:@[name,statusLabel]];
        [labels setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
        labels.orientation = NSUserInterfaceLayoutOrientationVertical; labels.alignment = NSLayoutAttributeLeading; labels.spacing = 1;
        BOOL hidden = [group[@"hidden"] boolValue];
        SPDFGroupActionButton* visibility = Icon(hidden ? @"eye.slash" : @"eye",[NSString stringWithFormat:@"%@ %@ %@ tab bar",hidden ? @"Show" : @"Hide",group[@"name"],hidden ? @"in" : @"from"],self,@selector(visibility:));
        visibility.groupID = group[@"id"];
        [labels setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
        contents = [NSStackView stackViewWithViews:@[disclosure,swatch,labels,visibility]]; contents.spacing = 5;
        container.toolTip = [NSString stringWithFormat:@"Open %@. Right-click for group actions.",group[@"name"]];
    }
    contents.distribution = NSStackViewDistributionFill; contents.alignment = NSLayoutAttributeCenterY;
    contents.translatesAutoresizingMaskIntoConstraints = NO; [container addSubview:contents];
    [NSLayoutConstraint activateConstraints:@[
        [contents.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:document ? 28 : 2],
        [contents.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-6],
        [contents.centerYAnchor constraintEqualToAnchor:container.centerYAnchor]]];
    return container;
}
- (void)activateRow:(id)sender {
    (void)sender; [self activateIndex:_table.clickedRow >= 0 ? _table.clickedRow : _table.selectedRow];
}
- (void)activateSelectedRow:(id)sender { (void)sender; [self activateIndex:_table.selectedRow]; }
- (void)activateIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_rows.count || !self.actionHandler) return;
    NSDictionary* row = _rows[index];
    self.actionHandler(row[@"document"] ? @"document" : @"jump",row[@"group"][@"id"],row[@"document"][@"path"] ?: @"");
}
- (void)disclose:(SPDFGroupActionButton*)sender {
    if ([_expanded containsObject:sender.groupID]) [_expanded removeObject:sender.groupID]; else [_expanded addObject:sender.groupID];
    [self rebuildRows]; [self publishState];
}
- (void)visibility:(SPDFGroupActionButton*)sender {
    if (self.actionHandler) self.actionHandler(@"visibility",sender.groupID,@"");
}
- (void)controlTextDidChange:(NSNotification*)notification {
    if (notification.object != _search) return;
    _savedScroll = 0; [self rebuildRows]; [_scroll.contentView scrollToPoint:NSZeroPoint]; [self publishState];
}
- (void)scrolled:(NSNotification*)notification {
    (void)notification; if (_restoring) return;
    _savedScroll = MAX(0,_scroll.contentView.bounds.origin.y); [self publishState];
}
- (void)menuNeedsUpdate:(NSMenu*)menu {
    [menu removeAllItems]; NSInteger row = _table.clickedRow >= 0 ? _table.clickedRow : _table.selectedRow;
    if (row < 0 || row >= (NSInteger)_rows.count) return;
    NSDictionary* group = _rows[row][@"group"];
    for (NSString* title in @[@"Jump to Group",[group[@"hidden"] boolValue] ? @"Show Group" : @"Hide Group",@"Rename…"]) {
        NSMenuItem* item = [menu addItemWithTitle:title action:@selector(menuAction:) keyEquivalent:@""];
        item.target = self; item.representedObject = group;
    }
}
- (void)menuAction:(NSMenuItem*)sender {
    NSDictionary* group = sender.representedObject; if (!self.actionHandler) return;
    if ([sender.title isEqual:@"Rename…"]) {
        NSAlert* alert = [NSAlert new]; alert.messageText = @"Rename group";
        alert.informativeText = [group[@"id"] isEqual:@"general"] ? @"New documents will open in a new General group." : @"Choose a name for this group.";
        NSTextField* field = [[NSTextField alloc] initWithFrame:NSMakeRect(0,0,260,24)]; field.stringValue = group[@"name"];
        alert.accessoryView = field; [alert addButtonWithTitle:@"Rename"]; [alert addButtonWithTitle:@"Cancel"];
        [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
            if (result == NSAlertFirstButtonReturn) self.actionHandler(@"rename",group[@"id"],field.stringValue);
        }];
    } else self.actionHandler([sender.title isEqual:@"Jump to Group"] ? @"jump" : @"visibility",group[@"id"],@"");
}
@end
