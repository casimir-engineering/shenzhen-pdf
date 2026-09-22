#import "SPDFMacTabGroupIntegration.h"
#import "SPDFMacTabDetach.h"

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
}
- (void)createGroupForTabAtIndex:(NSInteger)index withTabAtIndex:(NSInteger)other color:(NSString*)color {
    if (index < 0 || index >= (NSInteger)_tabs.count) return;
    SPDFTabGroup* group = [SPDFTabGroup groupWithColor:color ?: spdf_tab_group_unused_color(_tabs)];
    SPDFDocumentTab* selected = _tabs[(NSUInteger)index];
    selected.group = group;
    if (other >= 0 && other < (NSInteger)_tabs.count) _tabs[(NSUInteger)other].group = group;
    [self normalizeTabGroups];
    spdf_tab_groups_activate(_tabs, selected);
    [self selectTabAtIndex:[_tabs indexOfObjectIdenticalTo:selected]];
    [self finishTabGroupChange];
}
- (void)toggleTabGroup:(SPDFTabGroup*)group {
    if (!group) return;
    group.collapsed = !group.collapsed;
    if (!group.collapsed) {
        NSArray* members = spdf_tab_group_members(_tabs, group);
        SPDFDocumentTab* target = members.firstObject;
        for (SPDFDocumentTab* tab in members)
            if ([tab.path isEqualToString:group.lastUsedPath]) { target = tab; break; }
        if (target) [self selectTabAtIndex:[_tabs indexOfObjectIdenticalTo:target]];
    }
    [self finishTabGroupChange];
}
- (void)renameTabGroup:(SPDFTabGroup*)group name:(NSString*)name {
    if (!group) return;
    group.name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
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
