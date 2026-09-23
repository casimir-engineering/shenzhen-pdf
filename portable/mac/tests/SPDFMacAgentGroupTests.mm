#import "SPDFMacAgentGroups.h"
#import "SPDFMacAgentCommand.h"
#import "SPDFMacTabGroupIntegration.h"
#include <assert.h>

NSString* spdf_mac_support_directory(void) { return @"/unused-agent-group-tests"; }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wprotocol"
@implementation ShenzhenMacDelegate
@end
#pragma clang diagnostic pop
@interface AgentGroupProbe : ShenzhenMacDelegate
@property(nonatomic) NSUInteger saves;
@property(nonatomic) NSArray* savedTabs;
- (void)seed:(NSArray*)tabs;
- (NSArray*)tabs;
@end
@implementation AgentGroupProbe
- (void)seed:(NSArray*)tabs { _tabs=[tabs mutableCopy]; _selectedTabIndex=tabs.count ? 0 : -1; _windowSessionID=@"test-window"; }
- (NSArray*)tabs { return _tabs; }
- (void)updateTabStrip {}
- (void)rememberActiveTabState {}
- (void)savePersistentState {
    self.saves++; NSMutableArray* encoded=[NSMutableArray array];
    for (SPDFDocumentTab* tab in _tabs) [encoded addObject:spdf_dictionary_from_tab(tab,0)];
    self.savedTabs=encoded;
}
- (void)selectTabAtIndex:(NSInteger)index { _selectedTabIndex=index; [self activateSelectedTabGroup]; }
@end
static void Check(BOOL value) { assert(value); }
static SPDFDocumentTab* Tab(NSString* path) {
    SPDFDocumentTab* tab=[SPDFDocumentTab new]; tab.path=path; tab.title=path.lastPathComponent; return tab;
}
static NSDictionary* Run(AgentGroupProbe* host,NSDictionary* command) {
    NSError* error=nil; NSData* bytes=[NSJSONSerialization dataWithJSONObject:command options:0 error:nil];
    NSDictionary* validated=SPDFMacValidateAgentCommand(bytes,&error); Check(validated && !error);
    return [host performAgentGroupCommand:validated];
}
static NSDictionary* Group(NSDictionary* state, NSString* identifier) {
    for (NSDictionary* group in state[@"groups"]) if ([group[@"id"] isEqual:identifier]) return group;
    return nil;
}
int main(void) {
    @autoreleasepool {
        AgentGroupProbe* host=[AgentGroupProbe new];
        [host seed:@[Tab(@"/a.pdf"),Tab(@"/b.md"),Tab(@"/c.pdf"),Tab(@"/d.md")]];
        NSDictionary* state=Run(host,@{@"action":@"list-groups"});
        Check([state[@"groups"] count]==0 && [state[@"tabs"] count]==4 && host.saves==0);
        Check([state[@"tabs"][0][@"groupID"] isEqual:NSNull.null]);
        Check([state[@"windowSessionID"] isEqual:@"test-window"] && [state[@"colors"] containsObject:@"Blue"]);
        Check(Run(host,@{@"action":@"create-group",@"paths":@[@"/a.pdf",@"/missing.md"]})[@"error"]);
        Check(host.saves==0 && !((SPDFDocumentTab*)host.tabs[0]).group);
        Check(Run(host,@{@"action":@"create-group",@"paths":@[@"/a.pdf"],@"color":@"Unknown"})[@"error"]);
        Check(host.saves==0);
        state=Run(host,@{@"action":@"create-group",@"paths":@[@"/c.pdf",@"/a.pdf"],@"name":@" Research ",@"color":@"Blue"});
        NSString* research=state[@"groupID"]; Check(research.length && !state[@"error"]);
        Check([Group(state,research)[@"paths"] isEqual:@[@"/c.pdf",@"/a.pdf"]]);
        Check([Group(state,research)[@"name"] isEqual:@"Research"]);
        Check([state[@"groups"][0][@"id"] isEqual:@"general"]);
        Check([Group(state,@"general")[@"paths"] isEqual:@[@"/b.md",@"/d.md"]]);
        NSUInteger saves=host.saves;
        Check(Run(host,@{@"action":@"update-group",@"groupID":research,@"name":@"Wrong window",@"windowSessionID":@"other"})[@"error"]);
        Check(Run(host,@{@"action":@"update-group",@"groupID":@"general",@"name":@"Must not change",@"color":@"Blue"})[@"error"]);
        Check(Run(host,@{@"action":@"move-tab",@"path":@"/b.md",@"groupID":research,@"beforePath":@"/d.md"})[@"error"]);
        Check(host.saves==saves);
        state=Run(host,@{@"action":@"update-group",@"groupID":research,@"name":@"Sources",@"color":@"Rose",@"collapsed":@YES});
        Check([Group(state,research)[@"name"] isEqual:@"Sources"] && [Group(state,research)[@"color"] isEqual:@"Rose"]);
        Check([Group(state,research)[@"collapsed"] boolValue]);
        state=Run(host,@{@"action":@"update-group",@"groupID":research,@"collapsed":@NO});
        Check(![Group(state,research)[@"collapsed"] boolValue]);
        state=Run(host,@{@"action":@"move-tab",@"path":@"/b.md",@"groupID":research,@"beforePath":@"/a.pdf"});
        Check([Group(state,research)[@"paths"] isEqual:@[@"/c.pdf",@"/b.md",@"/a.pdf"]]);
        state=Run(host,@{@"action":@"move-tab",@"path":@"/a.pdf",@"groupID":research,@"beforePath":@"/c.pdf"});
        Check([Group(state,research)[@"paths"] isEqual:@[@"/a.pdf",@"/c.pdf",@"/b.md"]]);
        state=Run(host,@{@"action":@"move-group",@"groupID":research,@"beforeGroupID":@"general"});
        Check([state[@"groups"][0][@"id"] isEqual:research]);
        state=Run(host,@{@"action":@"create-group",@"paths":@[@"/d.md"],@"beforeGroupID":research,@"name":@"Review"});
        NSString* review=state[@"groupID"];
        Check([state[@"groups"][0][@"id"] isEqual:review]);
        Check(Run(host,@{@"action":@"create-group",@"paths":@[@"/d.md"],@"beforeGroupID":review})[@"error"]);
        state=Run(host,@{@"action":@"move-group",@"groupID":review});
        Check([[state[@"groups"] lastObject][@"id"] isEqual:review]);
        // The actual session/tab codec is the persistence contract; no parallel agent registry.
        NSMutableArray* restored=[NSMutableArray array];
        for (NSDictionary* saved in host.savedTabs) [restored addObject:spdf_tab_from_dictionary(saved)];
        spdf_tab_groups_normalize(restored);
        AgentGroupProbe* reopened=[AgentGroupProbe new]; [reopened seed:restored];
        NSDictionary* snapshot=Run(reopened,@{@"action":@"list-groups"});
        Check([snapshot[@"groups"] isEqual:state[@"groups"]]);
        Check([[snapshot[@"tabs"] valueForKey:@"path"] isEqual:[state[@"tabs"] valueForKey:@"path"]]);
        state=Run(host,@{@"action":@"ungroup",@"groupID":research});
        Check(!Group(state,research) && [Group(state,@"general")[@"paths"] count]==3);
        Check(Run(host,@{@"action":@"ungroup",@"groupID":@"general"})[@"error"]);
        Check(Run(host,@{@"action":@"update-group",@"groupID":research,@"name":@"Gone"})[@"error"]);
        puts("SPDFMacAgentGroupTests passed");
    }
}
