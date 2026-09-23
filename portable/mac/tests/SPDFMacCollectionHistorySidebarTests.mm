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
@end
@implementation HistoryFixtureStore
- (NSArray*)documents {
    return @[@{@"id":@"fixture",@"title":@"Garden notes.md",@"status":@"Protected local copies",@"path":@"/missing/Notes.md",@"versions":@[
        @{@"id":@"old",@"capturedAt":@1780358400,@"size":@1240,@"reason":@"Before edit"},@{@"id":@"new",@"capturedAt":@1790121600,@"size":@1510,@"reason":@"Saved"}]}];
}
@end
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        NSURL* root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
        HistoryFixtureStore* store = [[HistoryFixtureStore alloc] initWithRootURL:root];
        __block NSUInteger opens = 0;
        SPDFMacCollectionHistoryController* history = [[SPDFMacCollectionHistoryController alloc]
            initWithStore:store documentID:@"fixture" open:^(NSString* path, BOOL archived) {
                (void)path; (void)archived; ++opens;
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
        [NSFileManager.defaultManager removeItemAtURL:root error:nil];
        if (!failures) puts("SPDFMacCollectionHistorySidebarTests passed");
    }
    return failures ? 1 : 0;
}
