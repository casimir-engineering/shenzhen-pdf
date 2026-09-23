#import "SPDFMacSidebarWorkspace.h"
#import "SPDFMacSidebarModeControl.h"
#import "SPDFMacTabGroupIntegration.h"
#import "SPDFMacGroupManagement.h"
#include "spdf_yaml.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wprotocol"
@implementation ShenzhenMacDelegate
@end
#pragma clang diagnostic pop
@interface ShenzhenMacDelegate (WorkspaceTesting)
- (NSArray*)sidebarGroupSnapshots;
- (void)performSidebarGroupAction:(NSString*)action identifier:(NSString*)identifier value:(NSString*)value;
@end
@interface WorkspaceProbe : ShenzhenMacDelegate
@property NSInteger saves;
@property NSInteger collectionPanelChecks;
@property NSInteger snapshotCount;
- (void)seed:(NSArray*)tabs;
- (NSArray*)tabs;
- (NSSegmentedControl*)navigation;
- (CGFloat)sidebarWidth;
- (void)preferSidebarVisible:(BOOL)visible;
@end
@implementation WorkspaceProbe
- (void)seed:(NSArray*)tabs {
    _tabs = tabs.mutableCopy; _selectedTabIndex = tabs.count ? 0 : -1;
    _sidebarWidth = 284; _sidebarPreferredVisible = YES;
    _sidebarContainer = [[NSView alloc] initWithFrame:NSMakeRect(0,0,284,700)];
    _sidebarModeControl = [SPDFSidebarNavigationControl new];
    spdf_sidebar_mode_control_configure_history(_sidebarModeControl,NO,NO,YES);
    [_sidebarContainer addSubview:_sidebarModeControl];
    _sidebarModeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[[_sidebarModeControl.topAnchor constraintEqualToAnchor:_sidebarContainer.topAnchor],
        [_sidebarModeControl.leadingAnchor constraintEqualToAnchor:_sidebarContainer.leadingAnchor],
        [_sidebarModeControl.trailingAnchor constraintEqualToAnchor:_sidebarContainer.trailingAnchor]]];
}
- (NSArray*)tabs { return _tabs; }
- (NSSegmentedControl*)navigation { return _sidebarModeControl; }
- (CGFloat)sidebarWidth { return _sidebarWidth; }
- (void)preferSidebarVisible:(BOOL)visible { _sidebarPreferredVisible=visible; }
- (NSArray*)sidebarGroupSnapshots { self.snapshotCount++; return [super sidebarGroupSnapshots]; }
- (SPDFDocumentTab*)selectedTab { return _selectedTabIndex >= 0 ? _tabs[_selectedTabIndex] : nil; }
- (void)savePersistentState { self.saves++; }
- (void)updateTabStrip {}
- (void)rebuildSidebar { [self showSidebarWorkspacePanel]; }
- (void)rememberActiveTabState {}
- (void)selectTabAtIndex:(NSInteger)index { _selectedTabIndex = index; _sidebarPreferredVisible = _tabs[index].showSidebar; [self activateSelectedTabGroup]; }
- (BOOL)hasSearchSidebar { return NO; }
- (BOOL)collectionShowSelectedHistoryPanel { self.collectionPanelChecks++; return NO; }
- (void)setSidebarActuallyVisible:(BOOL)visible { _sidebarVisible = visible; }
- (void)restoreSidebarWidth {}
@end
static int failures;
static void Check(BOOL ok,NSString* message) { if (!ok) { fprintf(stderr,"FAIL %s\n",message.UTF8String); failures++; } }
static SPDFDocumentTab* Tab(NSString* name) {
    SPDFDocumentTab* tab = [SPDFDocumentTab new]; tab.path = [@"/tmp/" stringByAppendingString:name]; tab.title = name;
    tab.pageIndex = 7; tab.scrollOrigin = NSMakePoint(0,132); tab.hasScrollOrigin = YES; return tab;
}
static NSDictionary* YAML(NSDictionary* value) {
    NSData* json = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:nil];
    NSString* text = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    char* encoded = spdf_yaml_from_json(text.UTF8String,"sidebar session");
    Check(encoded != NULL,@"session serializes to YAML"); if (!encoded) return @{};
    char* decoded = spdf_json_from_yaml(encoded); free(encoded);
    Check(decoded != NULL,@"session parses from YAML"); if (!decoded) return @{};
    NSDictionary* result = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:decoded length:strlen(decoded)] options:0 error:nil];
    free(decoded); return result;
}
static void BenchmarkWorkspace(void) {
    for (NSNumber* countValue in @[@20,@200,@1000]) {
        NSUInteger count=countValue.unsignedIntegerValue;
        NSMutableArray* tabs=[NSMutableArray array]; SPDFTabGroup* group=nil;
        for (NSUInteger i=0;i<count;i++) {
            if (i%10==0) group=[SPDFTabGroup groupWithColor:@"Blue"];
            SPDFDocumentTab* tab=Tab([NSString stringWithFormat:@"benchmark-%lu.pdf",(unsigned long)i]);
            tab.group=group; [tabs addObject:tab];
        }
        WorkspaceProbe* reader=[WorkspaceProbe new]; [reader seed:tabs];
        reader.navigation.spdf_selectedSidebarMode=SPDFSidebarModeGroups;
        [reader showSidebarWorkspacePanel];
        for (NSUInteger phase=0;phase<4;phase++) {
            if (phase==3) [reader preferSidebarVisible:NO];
            CFAbsoluteTime start=CFAbsoluteTimeGetCurrent();
            const NSUInteger repeats=250;
            for (NSUInteger i=0;i<repeats;i++) { @autoreleasepool {
                if (phase==0) (void)[reader sidebarGroupSnapshots];
                else if (phase==1 || phase==3) [reader refreshSidebarWorkspacePanel];
                else [reader showSidebarWorkspacePanel];
            } }
            printf("workspace_tabs=%lu %s_us=%.3f\n",(unsigned long)count,
                phase==0 ? "snapshot" : phase==1 ? "unchanged_refresh" : phase==2 ? "unchanged_show" : "hidden_refresh",
                (CFAbsoluteTimeGetCurrent()-start)*1e6/repeats);
        }
    }
}
int main(int argc, const char* argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        if (argc>1 && strcmp(argv[1],"--benchmark")==0) { BenchmarkWorkspace(); return 0; }
        WorkspaceProbe* reader = [WorkspaceProbe new]; [reader seed:@[Tab(@"Alpha.pdf"),Tab(@"Beta.md")]];
        Check(![reader showSidebarWorkspacePanel] && reader.collectionPanelChecks == 0,
            @"ordinary chapter sidebar starts no management or Collection work");
        reader.navigation.spdf_selectedSidebarMode=SPDFSidebarModeGroups; [reader preferSidebarVisible:NO];
        Check([reader showSidebarWorkspacePanel] && reader.snapshotCount==0 && reader.collectionPanelChecks==0,
            @"restored hidden manager starts no snapshot or Collection work");
        [reader preferSidebarVisible:YES]; reader.navigation.spdf_selectedSidebarMode=SPDFSidebarModeChapters;
        Check([reader sidebarGroupSnapshots].count == 1 && !((SPDFDocumentTab*)reader.tabs.firstObject).group,
            @"manager snapshot shows virtual General without mutating ordinary tabs");
        [reader performSidebarGroupAction:@"visibility" identifier:@"general" value:@""];
        SPDFDocumentTab* selected = reader.selectedTab;
        Check(selected.group.hidden && reader.selectedTab == reader.tabs.firstObject,@"hiding General retains active document");
        reader.sidebarWorkspaceState[@"expandedGroups"] = @[@"general"];
        [reader performSidebarGroupAction:@"rename" identifier:@"general" value:@"Reference"];
        SPDFTabGroup* promoted = selected.group;
        Check(!promoted.general && [promoted.name isEqual:@"Reference"],@"General rename promotes to a named group");
        Check([reader.sidebarWorkspaceState[@"expandedGroups"] isEqual:@[promoted.identifier]],@"renaming General preserves manager expansion");
        NSMutableDictionary* state = reader.sidebarWorkspaceState;
        state[@"groupQuery"] = @"Réference"; state[@"expandedGroups"] = @[promoted.identifier]; state[@"groupScroll"] = @48;
        reader.navigation.spdf_selectedSidebarMode = SPDFSidebarModeGroups;
        NSMutableArray* savedTabs = [NSMutableArray array];
        for (SPDFDocumentTab* tab in reader.tabs) [savedTabs addObject:spdf_dictionary_from_tab(tab,0)];
        NSDictionary* restoredYAML = YAML(@{@"sidebar":reader.sidebarWorkspaceSnapshot,@"tabs":savedTabs});
        NSMutableArray* tabs = [NSMutableArray array];
        for (NSDictionary* item in restoredYAML[@"tabs"]) [tabs addObject:spdf_tab_from_dictionary(item)];
        spdf_tab_groups_normalize(tabs);
        WorkspaceProbe* reopened = [WorkspaceProbe new]; [reopened seed:tabs];
        [reopened restoreSidebarWorkspaceState:restoredYAML[@"sidebar"]]; [reopened applySidebarWorkspaceState];
        Check(reopened.navigation.spdf_selectedSidebarMode == SPDFSidebarModeGroups && reopened.sidebarWidth == 284,
            @"YAML restores exact sidebar mode and width");
        Check([reopened.sidebarWorkspaceState[@"groupQuery"] isEqual:@"Réference"] &&
            [reopened.sidebarWorkspaceState[@"expandedGroups"] isEqual:@[promoted.identifier]] &&
            [reopened.sidebarWorkspaceState[@"groupScroll"] integerValue] == 48,@"YAML restores manager query, expansion and scroll");
        Check(reopened.selectedTab.group.hidden && reopened.selectedTab.pageIndex == 7 && reopened.selectedTab.scrollOrigin.y == 132,
            @"YAML preserves hidden groups and document reading position");
        SPDFDocumentTab* fresh = Tab(@"Fresh.pdf"); [reopened appendNewTabToActiveGroup:fresh];
        Check(fresh.group.general && !fresh.group.hidden && reopened.selectedTab.group != fresh.group,
            @"opening after restart creates a fresh General after rename");
        [reopened performSidebarGroupAction:@"jump" identifier:promoted.identifier value:@""];
        Check(!reopened.selectedTab.group.hidden && [reopened.selectedTab.group.identifier isEqual:promoted.identifier],
            @"jump restores hidden group and selects its document");
        Check(reopened.navigation.spdf_selectedSidebarMode == SPDFSidebarModeGroups &&
            [reopened.sidebarWorkspaceSnapshot[@"visible"] boolValue],@"jump preserves manager navigation and visibility despite target tab preference");
        [reopened preferSidebarVisible:NO]; NSInteger snapshots=reopened.snapshotCount;
        [reopened refreshSidebarWorkspacePanel];
        Check(reopened.snapshotCount==snapshots,@"hidden sidebar refresh performs no group snapshot work");
        [reopened preferSidebarVisible:YES]; [reopened showSidebarWorkspacePanel];
        Check(reopened.snapshotCount==snapshots+1,@"revealing sidebar refreshes current group state");
        reopened.navigation.spdf_selectedSidebarMode = SPDFSidebarModeHistory; [reopened rememberSidebarWorkspaceMode];
        reopened.navigation.spdf_selectedSidebarMode = SPDFSidebarModeChapters; [reopened applySidebarWorkspaceState];
        Check(reopened.navigation.spdf_selectedSidebarMode == SPDFSidebarModeHistory,@"explicit new mode replaces prior sticky Groups state");
        [reopened restoreSidebarWorkspaceState:@{@"groupQuery":@3,@"expandedGroups":@[@1,@"ok"],@"width":@(-1)}];
        Check(!reopened.sidebarWorkspaceState[@"groupQuery"] && [reopened.sidebarWorkspaceState[@"expandedGroups"] isEqual:@[@"ok"]],
            @"malformed YAML fields are ignored safely");
        NSString* source = [NSString stringWithContentsOfFile:@"mac/ShenzhenPDFMac.mm" encoding:NSUTF8StringEncoding error:nil];
        Check([source containsString:@"[self restoreSidebarWorkspaceState:windowState[@\"sidebar\"]]"] &&
            [source containsString:@"@\"sidebar\" : [self sidebarWorkspaceSnapshot]"],@"window YAML load/save both wire workspace state");
        Check([source containsString:@"[[SPDFSidebarNavigationControl alloc] init]"] &&
            [source containsString:@"[self showSidebarWorkspacePanel] ||"],@"reader constructs vertical navigation and routes workspace before legacy modes");
        Check([source containsString:@"_sidebarToggleButton.enabled = _sidebarModeControl != nil"] &&
            [source containsString:@"BOOL canShowSidebar = _sidebarModeControl != nil"],@"empty readers can reopen the always-available sidebar");
        if (!failures) puts("SPDFMacSidebarWorkspaceTests passed");
        return failures ? 1 : 0;
    }
}
