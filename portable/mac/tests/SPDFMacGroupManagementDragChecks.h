@interface SPDFGroupDragInfoProbe : NSObject
@property(nonatomic, strong) id draggingSource;
@property(nonatomic, strong) NSPasteboard* draggingPasteboard;
@end
@implementation SPDFGroupDragInfoProbe
@end
static SPDFGroupDragInfoProbe* BeginGroupDocumentDrag(SPDFGroupManagementController* manager,
                                                     NSTableView* table, NSInteger row) {
    id<NSPasteboardWriting> writer = [manager tableView:table pasteboardWriterForRow:row];
    Check(writer != nil,"document rows provide a local drag token");
    SPDFGroupDragInfoProbe* info = [SPDFGroupDragInfoProbe new];
    info.draggingSource = table; info.draggingPasteboard = [NSPasteboard pasteboardWithUniqueName];
    [info.draggingPasteboard writeObjects:@[writer]];
    [manager tableView:table draggingSession:(id)[NSObject new] willBeginAtPoint:NSZeroPoint
        forRowIndexes:[NSIndexSet indexSetWithIndex:row]];
    return info;
}
static void CheckGroupDocumentDragging(void) {
    SPDFGroupManagementController* manager = [SPDFGroupManagementController new];
    NSDictionary* state = @{@"groupQuery":@"Research",@"expandedGroups":@[@"general",@"group-1"],@"groupScroll":@0};
    [manager updateGroups:Groups() state:state];
    NSTableView* table = (id)Find(manager.view,NSTableView.class);
    __block NSMutableArray* published = [NSMutableArray array];
    __block NSMutableArray* actions = [NSMutableArray array];
    manager.stateHandler = ^(NSDictionary* value) { [published addObject:value]; };
    manager.actionHandler = ^(NSString* action,NSString* group,NSString* value) {
        [actions addObject:@{@"action":action,@"group":group,@"value":value ?: @""}];
    };
    Check(table.numberOfRows == 3,"drag fixture begins with an active group filter and its documents");
    Check([manager tableView:table pasteboardWriterForRow:0] == nil,"group headers cannot start document drags");
    SPDFGroupDragInfoProbe* info = BeginGroupDocumentDrag(manager,table,2);
    Check(table.numberOfRows == 6,"drag temporarily exposes all group headers despite the active filter");
    BOOL onlyHeaders = YES;
    for (NSDictionary* row in [manager valueForKey:@"rows"]) onlyHeaders &= row[@"document"] == nil;
    Check(onlyHeaders,"drag temporarily collapses every destination group");
    Check([manager.viewState[@"expandedGroups"] isEqual:state[@"expandedGroups"]] &&
        [manager.viewState[@"groupQuery"] isEqual:@"Research"] && !published.count,
        "temporary collapse changes neither persisted expansion nor the search query");
    [manager tableView:table draggingSession:(id)[NSObject new] endedAtPoint:NSZeroPoint operation:NSDragOperationNone];
    Check(table.numberOfRows == 3 && [manager.viewState[@"expandedGroups"] isEqual:state[@"expandedGroups"]] &&
        [manager.viewState[@"groupQuery"] isEqual:@"Research"] && !actions.count,
        "cancelling restores filtered rows and all original expansion without moving documents");
    Check(published.count == 1 && [published.lastObject[@"expandedGroups"] isEqual:state[@"expandedGroups"]],
        "cancel never saves the temporary collapsed presentation");
    [info.draggingPasteboard releaseGlobally];

    info = BeginGroupDocumentDrag(manager,table,2);
    SPDFGroupDragInfoProbe* foreign = [SPDFGroupDragInfoProbe new];
    foreign.draggingSource = [NSTableView new]; foreign.draggingPasteboard = info.draggingPasteboard;
    Check([manager tableView:table validateDrop:(id)foreign proposedRow:2 proposedDropOperation:NSTableViewDropOn] == NSDragOperationNone &&
        ![manager tableView:table acceptDrop:(id)foreign row:2 dropOperation:NSTableViewDropOn],
        "a foreign workspace cannot replay even a valid local token");
    NSPasteboard* validPasteboard = info.draggingPasteboard;
    info.draggingPasteboard = [NSPasteboard pasteboardWithUniqueName];
    [info.draggingPasteboard setString:@"foreign-token" forType:@"com.shenzhenpdf.group-document"];
    Check([manager tableView:table validateDrop:(id)info proposedRow:2 proposedDropOperation:NSTableViewDropOn] == NSDragOperationNone &&
        ![manager tableView:table acceptDrop:(id)info row:2 dropOperation:NSTableViewDropOn],
        "a mismatched token cannot move a document");
    [info.draggingPasteboard releaseGlobally]; info.draggingPasteboard = validPasteboard;
    Check([manager tableView:table validateDrop:(id)info proposedRow:1 proposedDropOperation:NSTableViewDropOn] == NSDragOperationNone &&
        [manager tableView:table validateDrop:(id)info proposedRow:-1 proposedDropOperation:NSTableViewDropOn] == NSDragOperationNone &&
        [manager tableView:table validateDrop:(id)info proposedRow:6 proposedDropOperation:NSTableViewDropOn] == NSDragOperationNone,
        "same-group and out-of-range drops are rejected");
    Check([manager tableView:table validateDrop:(id)info proposedRow:2 proposedDropOperation:NSTableViewDropAbove] == NSDragOperationMove &&
        [manager tableView:table acceptDrop:(id)info row:2 dropOperation:NSTableViewDropOn],
        "a local document can move onto another group header");
    NSDictionary* command = actions.lastObject;
    NSDictionary* payload = [NSJSONSerialization JSONObjectWithData:[command[@"value"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    Check(actions.count == 1 && [command[@"action"] isEqual:@"move-document"] && [command[@"group"] isEqual:@"group-2"] &&
        [payload[@"source"] isEqual:@"group-1"] && [payload[@"path"] isEqual:@"/Conference notes.md"],
        "move JSON identifies source group and exact path even when other groups contain that same path");
    Check(published.count == 1,"accepted drop still does not persist the temporary collapsed presentation");
    [manager tableView:table draggingSession:(id)[NSObject new] endedAtPoint:NSZeroPoint operation:NSDragOperationMove];
    Check(table.numberOfRows == 3 && [manager.viewState[@"groupQuery"] isEqual:@"Research"] &&
        [manager.viewState[@"expandedGroups"] containsObject:@"group-2"] &&
        [manager.viewState[@"expandedGroups"] containsObject:@"general"] &&
        [manager.viewState[@"expandedGroups"] containsObject:@"group-1"],
        "successful move restores the filter and original expansion and remembers the destination expanded");
    Check(published.count == 2 && [published.lastObject[@"expandedGroups"] count] == 3,
        "only final expanded state is saved after a successful move");
    Check(![manager tableView:table acceptDrop:(id)info row:0 dropOperation:NSTableViewDropOn],
        "an ended drag cannot replay its move");
    [info.draggingPasteboard releaseGlobally];
}

// Contact sheet of the actual background draw calls, with fixture labels only.
// It bypasses NSTableView layer caching and never displays a window.
static void WriteGroupHeaderColorEvidence(NSArray<NSBitmapImageRep*>* rows, NSString* path) {
    if (!path.length) return;
    NSBitmapImageRep* sheet = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:560 pixelsHigh:174
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:sheet];
    for (NSInteger theme=0;theme<2;theme++) {
        CGFloat x = theme*280;
        NSColor* text = theme ? NSColor.whiteColor : NSColor.blackColor;
        [[NSColor colorWithSRGBRed:theme ? .118 : 1 green:theme ? .118 : 1 blue:theme ? .118 : 1 alpha:1] setFill];
        NSRectFill(NSMakeRect(x,0,280,174));
        [(theme ? @"Dark appearance" : @"Light appearance") drawAtPoint:NSMakePoint(x+20,145)
            withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],NSForegroundColorAttributeName:text}];
        for (NSInteger index=0;index<2;index++) {
            CGFloat y = 96-index*46;
            [rows[theme*2+index] drawInRect:NSMakeRect(x+20,y,240,36)];
            [(index ? @"Collection Backups" : @"Blue group") drawAtPoint:NSMakePoint(x+32,y+10)
                withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:12],NSForegroundColorAttributeName:text}];
        }
        [@"Native row backgrounds · fixture labels" drawAtPoint:NSMakePoint(x+20,16)
            withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:9],NSForegroundColorAttributeName:[text colorWithAlphaComponent:.65]}];
    }
    [NSGraphicsContext restoreGraphicsState];
    Check([[sheet representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],
        "native group header color evidence writes successfully");
}
static void CheckGroupHeaderColors(void) {
    SPDFGroupManagementController* manager = [SPDFGroupManagementController new];
    [manager updateGroups:@[@{@"id":@"blue",@"name":@"Blue",@"color":@"Blue",@"documents":@[]},
        @{@"id":@"collection-backups",@"name":@"Collection Backups",@"color":@"Orange",@"documents":@[]}] state:@{}];
    NSTableView* table = (id)Find(manager.view,NSTableView.class);
    NSMutableArray* renderedRows = [NSMutableArray array];
    for (NSString* name in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]) {
        NSAppearance* appearance = [NSAppearance appearanceNamed:name];
        [appearance performAsCurrentDrawingAppearance:^{
            for (NSInteger index=0;index<2;index++) {
                NSTableRowView* row = [manager tableView:table rowViewForRow:index];
                row.frame = NSMakeRect(0,0,240,36); row.groupRowStyle = YES;
                NSBitmapImageRep* bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                    pixelsWide:240 pixelsHigh:36 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                    colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
                [NSGraphicsContext saveGraphicsState];
                NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
                [row drawBackgroundInRect:row.bounds];
                [NSGraphicsContext restoreGraphicsState];
                [renderedRows addObject:bitmap];
                NSColor* actual = [[bitmap colorAtX:12 y:12] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
                NSColor* background = [NSColor.windowBackgroundColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
                NSColor* accent = [[row valueForKey:@"groupAccent"] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
                // Calibrated AppKit bitmap blending differs slightly from sRGB
                // channel arithmetic. Check the hue signal and subdued tint directly.
                CGFloat tint = fabs(actual.redComponent-background.redComponent)+
                    fabs(actual.greenComponent-background.greenComponent)+fabs(actual.blueComponent-background.blueComponent);
                Check(actual.alphaComponent>.99 && tint>.04 && tint<.5 &&
                    (actual.redComponent-actual.blueComponent)*(accent.redComponent-accent.blueComponent)>.002,
                    "native group header paint is opaque and carries its pastel color in both appearances");
            }
        }];
    }
    WriteGroupHeaderColorEvidence(renderedRows,NSProcessInfo.processInfo.environment[@"SPDF_GROUP_HEADER_COLOR_EVIDENCE"]);
}
