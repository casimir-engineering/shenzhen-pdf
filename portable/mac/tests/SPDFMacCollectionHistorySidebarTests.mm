#import <Cocoa/Cocoa.h>
#import "SPDFMacCollectionHistory.h"
#import "SPDFMacCollectionStore.h"
@interface CollectionEvidenceSurface : NSView
@end
@implementation CollectionEvidenceSurface
- (void)drawRect:(NSRect)dirty { [NSColor.windowBackgroundColor setFill]; NSRectFill(dirty); }
@end
static int failures;
static void Expect(BOOL result, const char* label) {
    if (!result) { fprintf(stderr,"FAIL: %s\n",label); ++failures; }
}
static NSView* Find(NSView* view, Class cls) {
    if ([view isKindOfClass:cls]) return view;
    for (NSView* child in view.subviews) { NSView* found = Find(child,cls); if (found) return found; }
    return nil;
}
static NSUInteger Badges(NSView* view) {
    NSUInteger count = [view.identifier isEqual:@"CollectionLatestBadge"] ? 1 : 0;
    for (NSView* child in view.subviews) count += Badges(child);
    return count;
}
@interface HistoryFixtureStore : SPDFMacCollectionStore
@property NSString* fixturePath;
@property NSUInteger materializations;
@end
@implementation HistoryFixtureStore
- (NSArray*)documents {
    return @[@{@"id":@"fixture",@"title":@"Garden notes.md",@"status":@"Protected local copies",@"path":self.fixturePath ?: @"/missing/Notes.md",@"versions":@[
        @{@"id":@"old",@"capturedAt":@1780358400,@"size":@1240,@"reason":@"Before edit"},@{@"id":@"new",@"capturedAt":@1790121600,@"size":@1510,@"reason":@"Saved"}]}];
}
- (NSURL*)materializeVersionID:(NSString*)version documentID:(NSString*)document error:(NSError**)error {
    (void)document; (void)error;
    dispatch_async(dispatch_get_main_queue(), ^{ self.materializations++; });
    return [self.rootURL URLByAppendingPathComponent:[version stringByAppendingString:@".md"]];
}
@end
@interface SPDFMacCollectionHistoryController (TestActions)
- (void)revealPath:(NSString*)path;
- (void)showVersionInExplorer:(NSMenuItem*)sender;
- (void)saveVersion:(NSDictionary*)version restoreLink:(BOOL)restore;
- (void)didRestorePath:(NSString*)path;
@end
@interface HistoryProbe : SPDFMacCollectionHistoryController
@property NSString* revealedPath;
@property NSString* savedVersion;
@property BOOL restoresLink;
@end
@implementation HistoryProbe
- (void)revealPath:(NSString*)path { self.revealedPath = path; }
- (void)saveVersion:(NSDictionary*)version restoreLink:(BOOL)restore { self.savedVersion = version[@"id"]; self.restoresLink = restore; }
@end
static BOOL Await(BOOL (^ready)(void)) {
    NSDate* end = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!ready() && end.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    return ready();
}
static NSButton* Button(NSView* view, NSString* title) {
    if ([view isKindOfClass:NSButton.class] && [[(NSButton*)view title] isEqual:title]) return (id)view;
    for (NSView* child in view.subviews) { NSButton* button = Button(child,title); if (button) return button; }
    return nil;
}
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        NSURL* root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
        HistoryFixtureStore* store = [[HistoryFixtureStore alloc] initWithRootURL:root];
        __block NSUInteger opens = 0;
        __block NSString* openedPath; __block BOOL archivedOpen;
        HistoryProbe* history = [[HistoryProbe alloc]
            initWithStore:store documentID:@"fixture" open:^(NSString* path, BOOL archived) {
                openedPath = path; archivedOpen = archived; ++opens;
            }];
        NSWindow* host = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,280,620)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        host.releasedWhenClosed = NO;
        host.contentView = [[CollectionEvidenceSurface alloc] initWithFrame:NSMakeRect(0,0,280,620)];
        NSView* container = host.contentView;
        NSSegmentedControl* modes = [NSSegmentedControl segmentedControlWithLabels:@[@"Chapters",@"Search",@"History"]
            trackingMode:NSSegmentSwitchTrackingSelectOne target:nil action:nil];
        modes.selectedSegment = 2; modes.translatesAutoresizingMaskIntoConstraints = NO;
        history.view.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:modes]; [container addSubview:history.view];
        [NSLayoutConstraint activateConstraints:@[
            [modes.topAnchor constraintEqualToAnchor:container.topAnchor constant:8],
            [modes.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:8],
            [modes.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-8],
            [history.view.topAnchor constraintEqualToAnchor:modes.bottomAnchor constant:8],
            [history.view.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [history.view.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [history.view.bottomAnchor constraintEqualToAnchor:container.bottomAnchor]]];
        [host.contentView layoutSubtreeIfNeeded];
        NSTableView* table = (id)Find(history.view,NSTableView.class);
        NSDate* end = [NSDate dateWithTimeIntervalSinceNow:3];
        while (table.numberOfRows != 2 && end.timeIntervalSinceNow > 0)
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        Expect(table.numberOfRows == 2,"both versions load in the reader history");
        NSView* newest = [history tableView:table viewForTableColumn:table.tableColumns.firstObject row:0];
        NSView* older = [history tableView:table viewForTableColumn:table.tableColumns.firstObject row:1];
        Expect(Badges(newest) == 1,"latest row has exactly one Latest pill");
        Expect(Badges(older) == 0,"older row never claims to be Latest");
        history.view.hidden = YES; history.view.hidden = NO;
        Expect(table.numberOfRows == 2,"switching away from History preserves the loaded versions");
        Expect(opens == 0,"loading and panel switching never opens a version implicitly");
        Expect(!host.visible,"history tests never show the app");
        NSString* evidence = NSProcessInfo.processInfo.environment[@"SPDF_COLLECTION_HISTORY_EVIDENCE"];
        if (evidence.length) {
            host.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
            [container layoutSubtreeIfNeeded];
            NSBitmapImageRep* bitmap = [container bitmapImageRepForCachingDisplayInRect:container.bounds];
            [container cacheDisplayInRect:container.bounds toBitmapImageRep:bitmap];
            Expect([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
                writeToFile:evidence atomically:YES],"history evidence writes a headless PNG");
        }
        Expect(Button(history.view,@"Find Document…") && Button(history.view,@"Save New Copy As…"),
            "missing link offers inline Find and Save actions");
        Expect(!Button(history.view,@"Find Document…").superview.hidden,"missing-source actions are visible without a modal");
        [Button(history.view,@"Save New Copy As…") performClick:nil];
        Expect([history.savedVersion isEqual:@"new"] && history.restoresLink,"Save New Copy restores link from latest version without selection");
        [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        Expect(Await(^BOOL { return opens == 1; }) && archivedOpen && [openedPath.lastPathComponent isEqual:@"new.md"],
            "missing latest opens saved version without a prompt");
        [NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
        store.fixturePath = [root.path stringByAppendingPathComponent:@"Original.md"];
        [@"live edit" writeToFile:store.fixturePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [table deselectAll:nil];
        [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        Expect(Await(^BOOL { return opens == 2; }) && !archivedOpen && [openedPath isEqual:store.fixturePath],
            "Latest rechecks current link and opens on-disk original");
        [table selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
        Expect(Await(^BOOL { return opens == 3; }) && archivedOpen && [openedPath.lastPathComponent isEqual:@"old.md"],
            "older selection stays read-only");
        [history menuNeedsUpdate:table.menu];
        NSMenuItem* reveal = table.menu.itemArray.firstObject;
        Expect([reveal.title isEqual:@"Show in Explorer"],"version context menu offers configured explorer");
        [history showVersionInExplorer:reveal];
        Expect(Await(^BOOL { return history.revealedPath != nil; }) && [history.revealedPath.lastPathComponent isEqual:@"old.md"],
            "older-version reveal uses materialized selected version");
        history.revealedPath = nil; reveal.representedObject = [store.documents.firstObject[@"versions"] lastObject];
        [history showVersionInExplorer:reveal];
        Expect(Await(^BOOL { return history.revealedPath != nil; }) && [history.revealedPath isEqual:store.fixturePath],
            "Latest reveal uses live original");
        store.fixturePath = @"/missing/Notes.md";
        NSUInteger materializations = store.materializations;
        [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [history cancelPendingPreviews];
        Expect(Await(^BOOL { return store.materializations > materializations; }),"pending preview actually materializes");
        NSDate* drained = [NSDate dateWithTimeIntervalSinceNow:.1];
        while (drained.timeIntervalSinceNow > 0)
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:drained];
        Expect(opens == 3,"leaving History cancels stale preview navigation");
        __block NSString* retainedSource; __block NSString* restoredSource;
        history.restoreLinkHandler = ^(NSString* previous, NSString* restored) { retainedSource = previous; restoredSource = restored; };
        [history didRestorePath:@"/restored/Notes.md"];
        Expect([retainedSource hasSuffix:@"Original.md"] && [restoredSource isEqual:@"/restored/Notes.md"] && opens == 3,
            "recovery routes old and new identities to retain existing reader tab instead of opening a duplicate");
        Expect(!host.visible,"all History interaction tests remain headless");
        [NSFileManager.defaultManager removeItemAtURL:root error:nil];
        if (!failures) puts("SPDFMacCollectionHistorySidebarTests passed");
    }
    return failures ? 1 : 0;
}
