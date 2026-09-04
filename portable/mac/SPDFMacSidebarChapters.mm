#import "SPDFMacSidebarChapters.h"

#import "SPDFMacSidebarOutline.h"

// Chapter nesting, end to end.
//
// The sidebar is a flat NSTableView shared by chapters, comments and search
// results, so nesting is modelled on the ROWS rather than by swapping in an
// NSOutlineView: the builders produce every row, and this half hides the ones
// under a collapsed parent before the table reloads. That keeps one row view,
// one selection path and one activation path for all three modes.
//
// Collapse state lives in the per-document store (documents.yaml), keyed the
// same way page geometry is, so it is remembered per file across launches
// without a new preference or a new ivar. Absent state means expanded, which is
// the default for a document nobody has touched.

static const CGFloat kSPDFChapterIndentPerLevel = 13.0;
static const CGFloat kSPDFChapterTriangleWidth = 14.0;
static NSString* const kSPDFCollapsedChaptersKey = @"collapsedChapters";

@implementation ShenzhenMacDelegate (SPDFMacSidebarChapters)

#pragma mark - Per-document collapse state

- (NSString*)collapsedChaptersStateKey {
    NSString* path = [self selectedTab].path;
    return path.length ? [self documentStateKeyForPath:path] : nil;
}

- (NSSet<NSString*>*)collapsedChapterKeys {
    NSString* key = [self collapsedChaptersStateKey];
    if (!key.length) return [NSSet set];
    id stored = _documentStates[key][kSPDFCollapsedChaptersKey];
    if (![stored isKindOfClass:NSArray.class]) return [NSSet set];
    NSMutableSet<NSString*>* keys = [NSMutableSet set];
    for (id entry in (NSArray*)stored) {
        if ([entry isKindOfClass:NSString.class]) [keys addObject:entry];
    }
    return keys;
}

- (void)setCollapsedChapterKeys:(NSSet<NSString*>*)keys {
    NSString* key = [self collapsedChaptersStateKey];
    if (!key.length) return;
    NSMutableDictionary* state = _documentStates[key];
    if (![state isKindOfClass:NSMutableDictionary.class]) state = [state mutableCopy] ?: [NSMutableDictionary dictionary];
    if (keys.count)
        // Sorted so the file does not churn between launches on set ordering.
        state[kSPDFCollapsedChaptersKey] = [keys.allObjects sortedArrayUsingSelector:@selector(compare:)];
    else
        [state removeObjectForKey:kSPDFCollapsedChaptersKey];
    state[@"path"] = [self selectedTab].path ?: state[@"path"] ?: @"";
    _documentStates[key] = state;
    [self savePersistentState];
}

#pragma mark - Projection

// The chapter rows' levels, or nil when this is not a nestable chapter list.
- (NSArray<NSNumber*>*)chapterLevelsForCurrentSidebar {
    if (_sidebarModeControl.selectedSegment != SPDFSidebarModeChapters) return nil;
    // A filter already answers "show me these": nesting a filtered list would
    // hide matches under parents that did not match.
    if (_sidebarFilterField.stringValue.length) return nil;
    NSMutableArray<NSNumber*>* levels = [NSMutableArray arrayWithCapacity:_sidebarItems.count];
    for (NSDictionary* item in _sidebarItems) {
        if (![item[@"kind"] isEqualToString:@"chapter"]) return nil;
        id level = item[@"level"];
        [levels addObject:@([level respondsToSelector:@selector(integerValue)] ? [level integerValue] : 0)];
    }
    return levels;
}

- (void)applyChapterNestingAndReload {
    NSArray<NSNumber*>* levels = [self chapterLevelsForCurrentSidebar];
    NSSet<NSString*>* collapsible = levels ? spdf_sidebar_outline_collapsible_keys(levels) : nil;
    [self setChapterOutlineControlsVisible:collapsible.count > 0];
    if (levels.count) {
        NSSet<NSString*>* collapsed = [self collapsedChapterKeys];
        NSIndexSet* visible = spdf_sidebar_outline_visible_indexes(levels, collapsed);
        NSMutableArray<NSDictionary*>* rows = [NSMutableArray arrayWithCapacity:visible.count];
        [visible enumerateIndexesUsingBlock:^(NSUInteger i, BOOL* stop) {
          (void)stop;
          NSMutableDictionary* row = [_sidebarItems[i] mutableCopy];
          NSString* outlineKey = spdf_sidebar_outline_key(levels, i);
          row[@"outlineKey"] = outlineKey;
          row[@"hasChildren"] = @(spdf_sidebar_outline_has_children(levels, i));
          row[@"collapsed"] = @([collapsed containsObject:outlineKey]);
          [rows addObject:row];
        }];
        [_sidebarItems setArray:rows];
    }
    [_sidebarTable reloadData];
}

- (void)toggleChapterAtSidebarRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_sidebarItems.count) return;
    NSDictionary* item = _sidebarItems[(NSUInteger)row];
    NSString* outlineKey = item[@"outlineKey"];
    if (![outlineKey isKindOfClass:NSString.class] || !outlineKey.length) return;
    NSMutableSet<NSString*>* keys = [[self collapsedChapterKeys] mutableCopy];
    if ([keys containsObject:outlineKey])
        [keys removeObject:outlineKey];
    else
        [keys addObject:outlineKey];
    [self setCollapsedChapterKeys:keys];
    // The row set changes under the table, so re-derive it from the builders
    // rather than patching rows here.
    [self rebuildSidebar];
}

- (void)disclosureTriangleClicked:(NSButton*)sender {
    NSInteger row = [_sidebarTable rowForView:sender];
    if (row < 0) {
        // A reused cell can be off-screen mid-reload; fall back to its tag.
        row = sender.tag;
    }
    [self toggleChapterAtSidebarRow:row];
}

#pragma mark - Expand / collapse all

- (void)expandAllChapters:(id)sender {
    (void)sender;
    [self setCollapsedChapterKeys:[NSSet set]];
    [self rebuildSidebar];
}

- (void)collapseAllChapters:(id)sender {
    (void)sender;
    NSArray<NSNumber*>* levels = [self chapterLevelsForCurrentSidebar];
    if (!levels.count) return;
    [self setCollapsedChapterKeys:spdf_sidebar_outline_collapsible_keys(levels)];
    [self rebuildSidebar];
}


#pragma mark - The row view

// Tags let the reused cell (and the sidebar container) find their pieces again
// without a bespoke NSTableCellView subclass.
static const NSInteger kSPDFTriangleTag = 8800;
static const NSInteger kSPDFExpandAllTag = 8801;
static const NSInteger kSPDFCollapseAllTag = 8802;
static NSString* const kSPDFIndentConstraintID = @"SPDFChapterIndent";

// The traditional disclosure pair: pointing right when collapsed, down when
// open. Drawn small and in the secondary tint so it reads as chrome.
static NSImage* SPDFChapterTriangleImage(BOOL collapsed) {
    NSString* symbol = collapsed ? @"chevron.right" : @"chevron.down";
    NSImage* image = [NSImage imageWithSystemSymbolName:symbol
                               accessibilityDescription:collapsed ? @"Expand" : @"Collapse"];
    NSImageSymbolConfiguration* configuration =
        [NSImageSymbolConfiguration configurationWithPointSize:9 weight:NSFontWeightSemibold];
    return [image imageWithSymbolConfiguration:configuration] ?: image;
}

static NSLayoutConstraint* SPDFIndentConstraint(NSView* cell) {
    for (NSLayoutConstraint* constraint in cell.constraints) {
        if ([constraint.identifier isEqualToString:kSPDFIndentConstraintID]) return constraint;
    }
    return nil;
}

- (NSTableCellView*)sidebarCellForTableView:(NSTableView*)tableView {
    NSTableCellView* cell = [tableView makeViewWithIdentifier:@"SidebarCell" owner:self];
    if (cell) return cell;
    cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 230, 25)];
    cell.identifier = @"SidebarCell";

    // Borderless so the triangle reads as a disclosure control rather than a
    // button, and small so it sits inside a 25pt row.
    NSButton* triangle = [NSButton buttonWithImage:SPDFChapterTriangleImage(YES)
                                            target:self
                                            action:@selector(disclosureTriangleClicked:)];
    triangle.bezelStyle = NSBezelStyleInline;
    triangle.bordered = NO;
    triangle.imagePosition = NSImageOnly;
    triangle.tag = kSPDFTriangleTag;
    triangle.translatesAutoresizingMaskIntoConstraints = NO;
    [triangle.widthAnchor constraintEqualToConstant:kSPDFChapterTriangleWidth].active = YES;
    [cell addSubview:triangle];

    NSTextField* field = [NSTextField labelWithString:@""];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.lineBreakMode = NSLineBreakByTruncatingTail;
    cell.textField = field;
    [cell addSubview:field];

    // The triangle's leading is the indent: it moves with the heading's depth
    // and the text follows it, so a nested chapter lines up under its parent's
    // title rather than under the parent's triangle.
    NSLayoutConstraint* indent = [triangle.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:6];
    indent.identifier = kSPDFIndentConstraintID;
    [NSLayoutConstraint activateConstraints:@[
        indent,
        [triangle.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        [field.leadingAnchor constraintEqualToAnchor:triangle.trailingAnchor constant:2],
        [field.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-6],
        [field.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
    ]];
    return cell;
}

- (void)styleSidebarCell:(NSTableCellView*)cell item:(NSDictionary*)item {
    id levelValue = item[@"level"];
    NSInteger level = [levelValue respondsToSelector:@selector(integerValue)] ? [levelValue integerValue] : 0;
    level = MAX(0, MIN(level, 16));
    id titleValue = item[@"title"];
    NSString* title = [titleValue isKindOfClass:NSString.class] ? titleValue : @"";
    id pageValue = item[@"page"];
    NSInteger page = [pageValue respondsToSelector:@selector(integerValue)] ? [pageValue integerValue] : -1;

    NSButton* triangle = [cell viewWithTag:kSPDFTriangleTag];
    BOOL hasChildren = [item[@"hasChildren"] boolValue];
    BOOL collapsed = [item[@"collapsed"] boolValue];
    // A childless row keeps the triangle's WIDTH -- hidden, not removed -- so
    // titles at the same depth align whether or not they have children.
    triangle.hidden = !hasChildren;
    triangle.enabled = hasChildren;
    triangle.image = SPDFChapterTriangleImage(collapsed);
    triangle.toolTip = collapsed ? @"Expand" : @"Collapse";
    triangle.tag = kSPDFTriangleTag;
    SPDFIndentConstraint(cell).constant = 6 + level * kSPDFChapterIndentPerLevel;

    cell.textField.stringValue = title ?: @"";
    cell.textField.font = [NSFont systemFontOfSize:13];
    cell.textField.textColor = page >= 0 ? NSColor.labelColor : NSColor.secondaryLabelColor;
}

#pragma mark - Expand All / Collapse All controls

static NSButton* SPDFOutlineControl(ShenzhenMacDelegate* self, NSInteger tag, NSString* symbol, NSString* tip,
                                    SEL action) {
    NSButton* button = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:symbol
                                                          accessibilityDescription:tip]
                                          target:self
                                          action:action];
    button.bordered = NO;
    button.imagePosition = NSImageOnly;
    button.toolTip = tip;
    button.tag = tag;
    button.contentTintColor = NSColor.secondaryLabelColor;  // discreet: chrome, not an action
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

- (void)installChapterOutlineControls {
    if ([_sidebarContainer viewWithTag:kSPDFExpandAllTag]) return;
    NSScrollView* scroll = _sidebarTable.enclosingScrollView;
    if (!_sidebarContainer || !_sidebarFilterField || !scroll) return;

    NSButton* expand = SPDFOutlineControl(self, kSPDFExpandAllTag, @"chevron.down", @"Expand All",
                                          @selector(expandAllChapters:));
    NSButton* collapse = SPDFOutlineControl(self, kSPDFCollapseAllTag, @"chevron.right", @"Collapse All",
                                            @selector(collapseAllChapters:));
    [_sidebarContainer addSubview:expand];
    [_sidebarContainer addSubview:collapse];

    // Their own thin row between the filter and the list, right-aligned so the
    // filter field keeps its full width and the pair stays out of the way.
    [_sidebarScrollBelowFilterConstraint setActive:NO];
    _sidebarScrollBelowFilterConstraint = [scroll.topAnchor constraintEqualToAnchor:collapse.bottomAnchor constant:4];
    [NSLayoutConstraint activateConstraints:@[
        [collapse.topAnchor constraintEqualToAnchor:_sidebarFilterField.bottomAnchor constant:4],
        [collapse.trailingAnchor constraintEqualToAnchor:_sidebarContainer.trailingAnchor constant:-8],
        [expand.centerYAnchor constraintEqualToAnchor:collapse.centerYAnchor],
        [expand.trailingAnchor constraintEqualToAnchor:collapse.leadingAnchor constant:-2],
        _sidebarScrollBelowFilterConstraint
    ]];
}

- (void)setChapterOutlineControlsVisible:(BOOL)visible {
    NSButton* expand = [_sidebarContainer viewWithTag:kSPDFExpandAllTag];
    NSButton* collapse = [_sidebarContainer viewWithTag:kSPDFCollapseAllTag];
    if (!expand || !collapse) return;
    // Nothing nestable (a flat outline, comments, search results): the pair
    // would be inert, so it goes away and the list takes the space back.
    expand.hidden = !visible;
    collapse.hidden = !visible;
    _sidebarScrollBelowFilterConstraint.constant = visible ? 4 : -18;
}

@end
