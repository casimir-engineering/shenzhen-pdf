#import "SPDFMacTabGroupIntegration.h"
#import "SPDFMacTabDetach.h"
#import "SPDFMacSidebarWorkspace.h"

@interface ShenzhenMacDelegate (SPDFMacTabGroupPrivate)
- (void)rememberActiveTabState;
- (NSString*)pathForStateFile:(NSString*)name;
- (id)stateObjectFromFile:(NSString*)name;
- (void)writeStateObject:(id)object toFile:(NSString*)name;
- (void)showError:(NSString*)message detail:(NSString*)detail;
- (void)updateTabStrip;
- (void)selectTabAtIndex:(NSInteger)index;
- (void)closeTabAtIndex:(NSInteger)index;
- (void)insertDraggedTab:(SPDFDocumentTab*)tab atIndex:(NSInteger)index;
- (void)savePersistentState;
@end

@implementation ShenzhenMacDelegate (SPDFMacTabGroupIntegration)
- (SPDFTabGroup*)ensureGeneralTabGroup {
    SPDFTabGroup* general=nil;
    for (SPDFDocumentTab* tab in _tabs) if (tab.group.general) { general=tab.group; break; }
    if (!general) for (SPDFDocumentTab* tab in _tabs) if (!tab.group) {
        if (!general) general=SPDFTabGroup.generalGroup;
        tab.group=general;
    }
    if (general) { general.explicitGeneral=YES; [self finishTabGroupChange]; }
    return general;
}
- (void)setTabGroup:(SPDFTabGroup*)group hidden:(BOOL)hidden {
    if (!group || !spdf_tab_group_members(_tabs,group).count) return;
    group.hidden=hidden;
    if (group.general) group.explicitGeneral=YES;
    // Visibility is independent of selection: hiding the active group leaves its document open.
    [self finishTabGroupChange];
}
- (void)jumpTabGroup:(SPDFTabGroup*)group {
    NSArray* members=spdf_tab_group_members(_tabs,group); if (!members.count) return;
    SPDFDocumentTab* target=members.firstObject;
    for (SPDFDocumentTab* tab in members) if ([tab.path isEqual:group.lastUsedPath]) { target=tab; break; }
    group.hidden=NO;
    spdf_tab_groups_activate(_tabs,target);
    [self selectTabAtIndex:[_tabs indexOfObjectIdenticalTo:target]];
    [self finishTabGroupChange];
}
- (void)normalizeTabGroups {
    SPDFDocumentTab* selected = _selectedTabIndex >= 0 && _selectedTabIndex < (NSInteger)_tabs.count
        ? _tabs[(NSUInteger)_selectedTabIndex] : nil;
    spdf_tab_groups_normalize(_tabs);
    if (selected) _selectedTabIndex = [_tabs indexOfObjectIdenticalTo:selected];
}
- (void)activateSelectedTabGroup {
    if (_selectedTabIndex >= 0 && _selectedTabIndex < (NSInteger)_tabs.count)
        spdf_tab_groups_activate(_tabs, _tabs[(NSUInteger)_selectedTabIndex]);
}
- (NSInteger)appendNewTabToActiveGroup:(SPDFDocumentTab*)tab {
    SPDFTabGroup* group = _selectedTabIndex >= 0 && _selectedTabIndex < (NSInteger)_tabs.count
        ? _tabs[(NSUInteger)_selectedTabIndex].group : nil;
    if ([[self sidebarWorkspaceState][@"newDocumentsInGeneral"] boolValue] || group.hidden) {
        group=nil;
        for (SPDFDocumentTab* existing in _tabs) if (existing.group.general) { group=existing.group; break; }
        if (!group) group=SPDFTabGroup.generalGroup;
        group.explicitGeneral=YES;
    }
    // Explicitly opening a new document must not strand its tab in a hidden group.
    group.hidden=NO;
    tab.group = group;
    NSInteger index = _tabs.count;
    if (group) {
        for (NSInteger i = _tabs.count - 1; i >= 0; --i)
            if (_tabs[(NSUInteger)i].group == group) { index = i + 1; break; }
    }
    [_tabs insertObject:tab atIndex:(NSUInteger)index];
    return index;
}
- (void)finishTabGroupChange {
    [self normalizeTabGroups];
    [self updateTabStrip];
    [self savePersistentState];
    [self refreshSidebarWorkspacePanel];
}
- (void)createGroupForTabAtIndex:(NSInteger)index withTabAtIndex:(NSInteger)other color:(NSString*)color {
    NSInteger target = other >= 0 && other < (NSInteger)_tabs.count ? other : index;
    if (index < 0 || index >= (NSInteger)_tabs.count) return;
    SPDFTabGroup* parent = _tabs[(NSUInteger)target].group;
    NSInteger first = target, last = target;
    while (first > 0 && _tabs[(NSUInteger)first-1].group == parent) --first;
    while (last+1 < (NSInteger)_tabs.count && _tabs[(NSUInteger)last+1].group == parent) ++last;
    [self createGroupForTabAtIndex:index withTabAtIndex:other color:color
        beforeTargetGroup:target-first < (last-first+1)/2];
}
- (void)createGroupForTabAtIndex:(NSInteger)index withTabAtIndex:(NSInteger)other color:(NSString*)color
             beforeTargetGroup:(BOOL)before {
    if (index < 0 || index >= (NSInteger)_tabs.count) return;
    SPDFDocumentTab* selected = _tabs[(NSUInteger)index];
    SPDFDocumentTab* target = other >= 0 && other < (NSInteger)_tabs.count ? _tabs[(NSUInteger)other] : selected;
    SPDFDocumentTab* active = _selectedTabIndex >= 0 && _selectedTabIndex < (NSInteger)_tabs.count
        ? _tabs[(NSUInteger)_selectedTabIndex] : nil;
    SPDFTabGroup* parent = target.group;
    NSMutableArray* members = [NSMutableArray array];
    NSUInteger fallback = 0;
    NSUInteger targetIndex = [_tabs indexOfObjectIdenticalTo:target];
    for (NSUInteger i=0;i<_tabs.count;i++) {
        SPDFDocumentTab* tab = _tabs[i];
        if (tab == selected || tab == target) [members addObject:tab];
        else if (i < targetIndex) ++fallback;
    }
    [_tabs removeObjectsInArray:members];
    NSUInteger insertion = fallback;
    // General remains contiguous, on the opposite side from the visible drop.
    // Establish that boundary before normalization; first occurrence alone
    // would move a left-side group behind every hidden General tab.
    for (NSUInteger i=0;i<_tabs.count;i++) if (_tabs[i].group == parent) {
        insertion = before ? i : i+1;
        if (before) break;
    }
    SPDFTabGroup* group = [SPDFTabGroup groupWithColor:color ?: spdf_tab_group_unused_color(_tabs)];
    for (SPDFDocumentTab* tab in members) tab.group = group;
    [_tabs insertObjects:members atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(insertion,members.count)]];
    if (active) _selectedTabIndex = [_tabs indexOfObjectIdenticalTo:active];
    [self normalizeTabGroups];
    spdf_tab_groups_activate(_tabs, selected);
    [self selectTabAtIndex:[_tabs indexOfObjectIdenticalTo:selected]];
    [self finishTabGroupChange];
}
- (void)toggleTabGroup:(SPDFTabGroup*)group {
    if (!group) return;
    group.collapsed = !group.collapsed;
    [self finishTabGroupChange];
}
- (void)renameTabGroup:(SPDFTabGroup*)group name:(NSString*)name {
    if (!group) return;
    NSString* trimmed=[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (group.general && trimmed.length && ![trimmed isEqual:@"General"]) {
        NSString* previousIdentifier=group.identifier;
        group.identifier=NSUUID.UUID.UUIDString;
        NSMutableArray* expanded=[[self sidebarWorkspaceState][@"expandedGroups"] mutableCopy];
        if ([expanded containsObject:previousIdentifier]) {
            [expanded removeObject:previousIdentifier]; [expanded addObject:group.identifier];
            [self sidebarWorkspaceState][@"expandedGroups"]=expanded;
        }
        group.colorName=spdf_tab_group_unused_color(_tabs);
        group.explicitGeneral=NO;
        [self sidebarWorkspaceState][@"newDocumentsInGeneral"]=@YES;
    }
    group.name = trimmed;
    [self finishTabGroupChange];
}
- (void)recolorTabGroup:(SPDFTabGroup*)group color:(NSString*)color {
    if (group.general || ![spdf_tab_group_colors() containsObject:color]) return;
    group.colorName = color;
    [self finishTabGroupChange];
}
- (void)ungroupTabs:(SPDFTabGroup*)group {
    if (!group || group.general) return;
    for (SPDFDocumentTab* tab in spdf_tab_group_members(_tabs, group)) tab.group = nil;
    [self finishTabGroupChange];
}
- (void)closeTabGroup:(SPDFTabGroup*)group {
    NSArray* members = spdf_tab_group_members(_tabs, group);
    // Identity snapshots survive the normalization/selection each close runs.
    for (SPDFDocumentTab* tab in [members reverseObjectEnumerator]) {
        NSUInteger index = [_tabs indexOfObjectIdenticalTo:tab];
        if (index != NSNotFound) [self closeTabAtIndex:(NSInteger)index];
    }
}
- (void)moveTabGroup:(SPDFTabGroup*)group toIndex:(NSInteger)index {
    NSArray* members = spdf_tab_group_members(_tabs, group);
    if (!members.count) return;
    SPDFDocumentTab* selected = _selectedTabIndex >= 0 ? _tabs[(NSUInteger)_selectedTabIndex] : nil;
    index = MAX(0, MIN(index, (NSInteger)_tabs.count));
    // A whole group inserts at a group boundary, never splits another group.
    if (index < (NSInteger)_tabs.count) {
        SPDFTabGroup* destination = _tabs[(NSUInteger)index].group;
        while (index > 0 && _tabs[(NSUInteger)index - 1].group == destination) --index;
    }
    NSInteger removedBefore = 0;
    for (NSInteger i = 0; i < index; ++i) if ([members containsObject:_tabs[(NSUInteger)i]]) ++removedBefore;
    [_tabs removeObjectsInArray:members];
    index = MAX(0, MIN(index - removedBefore, (NSInteger)_tabs.count));
    NSIndexSet* indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(index, members.count)];
    [_tabs insertObjects:members atIndexes:indexes];
    if (selected) _selectedTabIndex = [_tabs indexOfObjectIdenticalTo:selected];
    [self finishTabGroupChange];
}
- (void)moveTabAtIndex:(NSInteger)index toGroup:(SPDFTabGroup*)group atIndex:(NSInteger)destination {
    if (index < 0 || index >= (NSInteger)_tabs.count) return;
    SPDFDocumentTab* tab = _tabs[(NSUInteger)index];
    SPDFDocumentTab* selected = _selectedTabIndex >= 0 ? _tabs[(NSUInteger)_selectedTabIndex] : nil;
    tab.group = group;
    [_tabs removeObjectAtIndex:index];
    if (destination > index) --destination;
    destination = MAX(0, MIN(destination, (NSInteger)_tabs.count));
    [_tabs insertObject:tab atIndex:destination];
    if (selected) _selectedTabIndex = [_tabs indexOfObjectIdenticalTo:selected];
    [self normalizeTabGroups];
    spdf_tab_groups_activate(_tabs, tab);
    [self selectTabAtIndex:[_tabs indexOfObjectIdenticalTo:tab]];
    [self finishTabGroupChange];
}
- (NSArray<NSDictionary*>*)snapshotTabGroup:(SPDFTabGroup*)group {
    [self rememberActiveTabState];
    NSMutableArray* result = [NSMutableArray array];
    for (SPDFDocumentTab* tab in spdf_tab_group_members(_tabs, group))
        [result addObject:spdf_dictionary_from_tab(tab, _window.windowNumber)];
    return result;
}
- (void)insertDraggedGroup:(NSArray<NSDictionary*>*)items atIndex:(NSInteger)index {
    // Decode before mutation. Cross-window groups keep identity so returning a
    // group to its originating window rejoins any tabs left there.
    NSMutableArray* incoming = [NSMutableArray array];
    for (id item in items) {
        SPDFDocumentTab* tab = spdf_tab_from_dictionary(item);
        if (tab) [incoming addObject:tab];
    }
    if (!incoming.count) return;
    [self rememberActiveTabState];
    SPDFDocumentTab* previous = _selectedTabIndex >= 0 && _selectedTabIndex < (NSInteger)_tabs.count
        ? _tabs[(NSUInteger)_selectedTabIndex] : nil;
    index = MAX(0, MIN(index, (NSInteger)_tabs.count));
    if (index < (NSInteger)_tabs.count) {
        SPDFTabGroup* group = _tabs[(NSUInteger)index].group;
        while (index > 0 && _tabs[(NSUInteger)index - 1].group == group) --index;
    }
    SPDFDocumentTab* target = nil;
    for (SPDFDocumentTab* tab in incoming) {
        SPDFDocumentTab* existing = nil;
        for (SPDFDocumentTab* candidate in _tabs)
            if ([candidate.path.stringByStandardizingPath isEqualToString:tab.path.stringByStandardizingPath])
                { existing = candidate; break; }
        if (existing) { existing.group = tab.group; target = existing; continue; }
        [_tabs insertObject:tab atIndex:index++];
        if (!target || [tab.path isEqualToString:tab.group.lastUsedPath]) target = tab;
    }
    _selectedTabIndex = previous ? [_tabs indexOfObjectIdenticalTo:previous] : -1;
    [self normalizeTabGroups];
    [self selectTabAtIndex:[_tabs indexOfObjectIdenticalTo:target]];
    [self finishTabGroupChange];
}
- (void)detachTabGroup:(SPDFTabGroup*)group atScreenPoint:(NSPoint)point {
    NSArray* tabs = [self snapshotTabGroup:group];
    if (!tabs.count) return;
    NSString* path = tabs.firstObject[@"path"];
    NSString* executable = NSBundle.mainBundle.executablePath ?: NSProcessInfo.processInfo.arguments.firstObject;
    if (!executable.length) return;
    NSRect frame = _window.frame;
    frame.origin = NSMakePoint(point.x - MIN(180.0, frame.size.width / 2), point.y - frame.size.height + 22);
    NSDictionary* handoff = @{@"tabs": tabs, @"frame": NSStringFromRect(frame)};
    NSString* handoffName = spdf_mac_detach_handoff_name(path);
    [self writeStateObject:handoff toFile:handoffName];
    // The shared writer has a void API. Read back before launching/closing:
    // a full disk or inaccessible state directory must leave the source intact.
    if (![[self stateObjectFromFile:handoffName] isEqual:handoff]) {
        [self showError:@"Could not move group to a new window"
                 detail:@"The group's reading positions could not be saved. The tabs remain in this window."];
        return;
    }
    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:executable];
    task.arguments = @[@"--detached-tab", path];
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    NSError* error = nil;
    if (![task launchAndReturnError:&error]) {
        [NSFileManager.defaultManager removeItemAtPath:[self pathForStateFile:spdf_mac_detach_handoff_name(path)] error:nil];
        [self showError:@"Could not move group to a new window" detail:error.localizedDescription];
        return;
    }
    [self closeTabGroup:group];
}
@end
