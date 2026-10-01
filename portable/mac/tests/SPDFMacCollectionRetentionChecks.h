#import "SPDFMacCollectionRetention.h"
static void CheckCollectionRetentionMenu(SPDFMacCollectionWindow* manager) {
    NSArray* savedRows = manager.rows;
    NSIndexSet* savedSelection = manager.table.selectedRowIndexes;
    if (!savedRows.count) { Expect(@"retention menu fixture has a document",NO); return; }
    NSDictionary* doc = @{@"id":@"retention",@"title":@"Notes",@"path":@"/missing/notes.txt",@"excluded":@NO};
    NSDictionary* version = @{@"id":@"version",@"keep":@NO};
    NSDictionary* row = @{@"document":doc,@"version":version};
    NSDictionary* kept = @{@"document":doc,@"version":@{@"id":@"version",@"keep":@YES}};
    NSDictionary* paused = @{@"document":@{@"id":@"retention",@"excluded":@YES},@"version":version};
    Expect(@"mixed kept selections offer Keep for all",!SPDFCollectionSelectionIsKept(@[row,kept]));
    Expect(@"all kept selections offer removal",SPDFCollectionSelectionIsKept(@[kept,kept]));
    Expect(@"mixed capture selections offer Pause for all",!SPDFCollectionSelectionIsPaused(@[row,paused]));
    Expect(@"all paused selections offer Resume",SPDFCollectionSelectionIsPaused(@[paused,paused]));
    [manager.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    // Swap the selected model without reloading cells or requesting fake previews.
    for (NSNumber* flag in @[@NO,@YES]) {
        NSMutableDictionary* d = [doc mutableCopy]; d[@"excluded"] = flag;
        NSMutableDictionary* v = [version mutableCopy]; v[@"keep"] = flag;
        manager.rows = @[@{@"document":d,@"version":v}];
        NSMenu* menu = [NSMenu new]; [manager populateDocumentMenu:menu];
        NSMenuItem* keep = nil; NSMenuItem* pause = nil;
        for (NSMenuItem* item in menu.itemArray) {
            if (item.action == @selector(keep:)) keep = item;
            if (item.action == @selector(exclude:)) pause = item;
        }
        Expect(@"Keep command names the actual next action",[keep.title isEqual:flag.boolValue ?
            @"Stop keeping this version" : @"Keep this version"]);
        Expect(@"capture command names the actual next action",[pause.title isEqual:flag.boolValue ?
            @"Resume saving new versions" : @"Pause saving new versions"]);
        Expect(@"Keep help explains whole-history cleanup protection",[keep.toolTip containsString:@"entire history"] &&
            [keep.toolTip containsString:@"Manual deletion"]);
        Expect(@"Pause help explains existing copies remain",[pause.toolTip containsString:@"Existing saved versions"]);
    }
    manager.rows = savedRows;
    [manager.table selectRowIndexes:savedSelection byExtendingSelection:NO]; [manager updateDetails];
}
