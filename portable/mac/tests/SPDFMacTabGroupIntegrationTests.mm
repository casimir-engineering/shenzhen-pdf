#import "SPDFMacTabGroupIntegration.h"

// Link the production category onto a headless delegate. Its document loading
// and disk boundary are replaced; group mutations and codec paths are real.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wprotocol"
@implementation ShenzhenMacDelegate
@end
#pragma clang diagnostic pop

@interface GroupReaderProbe : ShenzhenMacDelegate
@property(nonatomic, copy) NSString* activePath;
@property(nonatomic, strong) NSArray* savedTabs;
@property(nonatomic) NSInteger saveCount;
@property(nonatomic) NSInteger handoffWriteCount;
@property(nonatomic) NSInteger errorCount;
- (void)seed:(NSArray*)tabs selected:(NSInteger)index;
- (NSArray*)tabs;
- (NSInteger)selectedIndex;
@end
@implementation GroupReaderProbe
- (void)seed:(NSArray*)tabs selected:(NSInteger)index {
    _tabs = [tabs mutableCopy];
    _selectedTabIndex = index;
    self.activePath = index >= 0 ? _tabs[(NSUInteger)index].path : nil;
}
- (NSArray*)tabs { return _tabs; }
- (NSInteger)selectedIndex { return _selectedTabIndex; }
- (void)rememberActiveTabState {}
- (void)writeStateObject:(id)object toFile:(NSString*)name {
    (void)object; (void)name; self.handoffWriteCount++;
}
- (id)stateObjectFromFile:(NSString*)name { (void)name; return nil; }
- (void)showError:(NSString*)message detail:(NSString*)detail { (void)message; (void)detail; self.errorCount++; }
- (void)updateTabStrip {}
- (void)savePersistentState {
    self.saveCount++;
    NSMutableArray* encoded = [NSMutableArray array];
    for (SPDFDocumentTab* tab in _tabs) [encoded addObject:spdf_dictionary_from_tab(tab, 0)];
    self.savedTabs = encoded;
}
- (void)selectTabAtIndex:(NSInteger)index {
    // The real reader short-circuits selecting the current index. Incoming
    // groups must update that index when inserting before the active tab.
    if (index == _selectedTabIndex && self.activePath.length) return;
    _selectedTabIndex = index;
    self.activePath = _tabs[(NSUInteger)index].path;
    [self activateSelectedTabGroup];
}
- (void)closeTabAtIndex:(NSInteger)index {
    SPDFDocumentTab* current = _selectedTabIndex >= 0 ? _tabs[(NSUInteger)_selectedTabIndex] : nil;
    [_tabs removeObjectAtIndex:index];
    _selectedTabIndex = current && [_tabs containsObject:current] ? [_tabs indexOfObjectIdenticalTo:current] : -1;
    [self normalizeTabGroups];
    [self savePersistentState];
}
@end
static int failures;
static void Expect(NSString* label, BOOL condition) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", label.UTF8String); ++failures; }
}
static SPDFDocumentTab* Tab(NSString* path) {
    SPDFDocumentTab* tab = [[SPDFDocumentTab alloc] init];
    tab.path = path; tab.title = path.lastPathComponent;
    return tab;
}
static void CheckCreationPlacement(BOOL before, BOOL explicitPlacement) {
    GroupReaderProbe* reader = [GroupReaderProbe new];
    NSMutableArray* tabs = [NSMutableArray array];
    for (NSUInteger i=0;i<60;i++) [tabs addObject:Tab([NSString stringWithFormat:@"/placement-%lu.md",(unsigned long)i])];
    // With overflow, a left-side visible target can be near the end of the model.
    NSInteger source = explicitPlacement ? 59 : before ? 10 : 0;
    NSInteger target = explicitPlacement ? 54 : before ? 11 : 55;
    SPDFDocumentTab* dragged = tabs[source]; SPDFDocumentTab* destination = tabs[target];
    dragged.pageIndex = 9; destination.pageIndex = 17;
    [reader seed:tabs selected:source];
    if (explicitPlacement) {
        BOOL supported = [reader respondsToSelector:@selector(createGroupForTabAtIndex:withTabAtIndex:color:beforeTargetGroup:)];
        Expect(@"creation accepts an explicit visible-side placement",supported);
        if (!supported) return;
        [reader createGroupForTabAtIndex:source withTabAtIndex:target color:@"Blue" beforeTargetGroup:before];
    } else [reader createGroupForTabAtIndex:source withTabAtIndex:target color:@"Blue"];
    Expect(before ? @"left-side creation precedes General" : @"right-side creation follows General",
        ((SPDFDocumentTab*)(before ? reader.tabs.firstObject : reader.tabs.lastObject)).group == dragged.group &&
        ((SPDFDocumentTab*)(before ? reader.tabs.lastObject : reader.tabs.firstObject)).group.general);
    Expect(@"creation keeps both documents and all other tabs",reader.tabs.count == 60 &&
        dragged.group == destination.group && [NSSet setWithArray:reader.tabs].count == 60);
    Expect(@"creation preserves active document and reading state",[reader.activePath isEqual:dragged.path] &&
        ((SPDFDocumentTab*)reader.tabs[reader.selectedIndex]) == dragged && dragged.pageIndex == 9 && destination.pageIndex == 17);
    NSMutableArray* restored = [NSMutableArray array];
    for (NSDictionary* encoded in reader.savedTabs) [restored addObject:spdf_tab_from_dictionary(encoded)];
    spdf_tab_groups_normalize(restored);
    Expect(@"created side and document order survive session restore",
        [[restored valueForKey:@"path"] isEqual:[reader.tabs valueForKey:@"path"]] &&
        ((SPDFDocumentTab*)(before ? restored.lastObject : restored.firstObject)).group.general);
}
int main(void) {
    @autoreleasepool {
        CheckCreationPlacement(YES,NO); CheckCreationPlacement(NO,NO);
        CheckCreationPlacement(YES,YES); CheckCreationPlacement(NO,YES);
        GroupReaderProbe* reader = [[GroupReaderProbe alloc] init];
        SPDFDocumentTab* a = Tab(@"/a.pdf");
        SPDFDocumentTab* b = Tab(@"/b.md");
        SPDFDocumentTab* c = Tab(@"/c.pdf");
        SPDFDocumentTab* d = Tab(@"/d.md");
        [reader seed:@[a, b, c, d] selected:0];
        [reader createGroupForTabAtIndex:1 withTabAtIndex:2 color:@"Purple"];
        SPDFTabGroup* purple = b.group;
        Expect(@"pair creation gives both tabs one group", purple && c.group == purple);
        Expect(@"all remaining tabs share General", a.group.general && a.group == d.group);
        Expect(@"creating a group preserves current document selection after normalization",
               [reader.activePath isEqualToString:b.path]);
        [reader renameTabGroup:purple name:@"  References  "];
        [reader recolorTabGroup:purple color:@"Teal"];
        Expect(@"rename and palette persist immediately", [reader.savedTabs[2][@"group"][@"name"] isEqual:@"References"]
            && [reader.savedTabs[2][@"group"][@"color"] isEqual:@"Teal"]);
        [reader renameTabGroup:a.group name:@"Inbox"];
        Expect(@"General can be renamed without losing its policy", a.group.general
            && [a.group.displayName isEqualToString:@"Inbox"]);
        [reader renameTabGroup:a.group name:@""];
        Expect(@"empty General name restores its default", [a.group.displayName isEqualToString:@"General"]);
        [reader toggleTabGroup:purple];
        Expect(@"folding persists immediately", [reader.savedTabs[2][@"group"][@"collapsed"] boolValue]);
        SPDFDocumentTab* fresh = Tab(@"/new.md");
        NSInteger inserted = [reader appendNewTabToActiveGroup:fresh];
        Expect(@"new opens append inside active group", fresh.group == purple && inserted == 4);
        [reader moveTabGroup:purple toIndex:0];
        Expect(@"dragging handle reorders whole group intact", [reader.tabs isEqual:@[b, c, fresh, a, d]]);
        Expect(@"group reorder keeps selected document", ((SPDFDocumentTab*)reader.tabs[reader.selectedIndex]) == b);
        [reader moveTabAtIndex:1 toGroup:a.group atIndex:reader.tabs.count];
        Expect(@"dropping a tab into General moves membership and order", c.group.general && reader.tabs.lastObject == c);
        [reader ungroupTabs:purple];
        BOOL ordinary = YES;
        for (SPDFDocumentTab* tab in reader.tabs) ordinary &= tab.group == nil;
        Expect(@"ungrouping last custom group removes the group chrome", ordinary);

        GroupReaderProbe* source = [[GroupReaderProbe alloc] init];
        SPDFDocumentTab* one = Tab(@"/one.md");
        SPDFDocumentTab* two = Tab(@"/two.pdf");
        [source seed:@[one, two] selected:0];
        [source createGroupForTabAtIndex:0 withTabAtIndex:1 color:@"Rose"];
        one.pageIndex = 7; two.pageIndex = 11;
        one.group.lastUsedPath = two.path;
        [source toggleTabGroup:one.group];
        [source toggleTabGroup:one.group];
        Expect(@"expanding a group opens its last-used document at its reading position",
            !one.group.collapsed && [source.activePath isEqual:two.path] && two.pageIndex == 11);
        [source detachTabGroup:one.group atScreenPoint:NSMakePoint(300, 500)];
        Expect(@"failed handoff write leaves the source tabs open and reports the failure",
               source.handoffWriteCount == 1 && source.errorCount == 1 && source.tabs.count == 2);
        NSArray* payload = [source snapshotTabGroup:one.group];
        GroupReaderProbe* destination = [[GroupReaderProbe alloc] init];
        SPDFDocumentTab* existing = Tab(@"/existing.pdf");
        [destination seed:@[existing] selected:0];
        [destination insertDraggedGroup:payload atIndex:0];
        Expect(@"incoming group before active tab loads the incoming last-used document",
               [destination.activePath isEqualToString:two.path]);
        Expect(@"incoming group owns two tabs and General owns preexisting tab", existing.group.general
            && ((SPDFDocumentTab*)destination.tabs[0]).group == ((SPDFDocumentTab*)destination.tabs[1]).group);
        Expect(@"incoming reading positions survive", ((SPDFDocumentTab*)destination.tabs[0]).pageIndex == 7
            && ((SPDFDocumentTab*)destination.tabs[1]).pageIndex == 11);
        [destination closeTabGroup:((SPDFDocumentTab*)destination.tabs[0]).group];
        Expect(@"closing a group only closes its members", [destination.tabs isEqual:@[existing]] && !existing.group);
        // Duplicate paths keep the destination's live document but join the
        // moved group; the source may close safely after this successful drop.
        [destination seed:@[one, existing] selected:0];
        [destination insertDraggedGroup:payload atIndex:1];
        Expect(@"duplicate path transfer does not create duplicate tabs", destination.tabs.count == 3);
        Expect(@"duplicate document joins incoming group", one.group && one.group == ((SPDFDocumentTab*)destination.tabs[1]).group);
    }
    if (!failures) puts("SPDFMacTabGroupIntegrationTests passed");
    return failures ? 1 : 0;
}
