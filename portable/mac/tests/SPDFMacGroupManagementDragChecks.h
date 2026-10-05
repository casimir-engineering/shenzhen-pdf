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
static void CheckGroupDragAutoscroll(void);
static void CheckGroupDocumentDragging(void) {
    CheckGroupDragAutoscroll();
    SPDFGroupManagementController* manager=[SPDFGroupManagementController new];
    NSDictionary* state=@{@"expandedGroups":@[@"general",@"group-1"],@"groupScroll":@0};
    [manager updateGroups:Groups() state:state]; NSTableView* table=(id)Find(manager.view,NSTableView.class);
    __block NSString* target; __block NSDictionary* payload;
    manager.actionHandler=^(NSString* action,NSString* group,NSString* value) {
        Check([action isEqual:@"move-document"],"drop dispatches a document move"); target=group;
        payload=[NSJSONSerialization JSONObjectWithData:[value dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    };
    NSInteger count=table.numberOfRows;
    SPDFGroupDragInfoProbe* info=BeginGroupDocumentDrag(manager,table,5);
    Check(table.numberOfRows==count && count==10,"drag preserves expanded groups and document rows");
    Check([manager tableView:table validateDrop:(id)info proposedRow:4 proposedDropOperation:NSTableViewDropAbove]==NSDragOperationMove,
        "same-group insertion is accepted");
    Check([manager tableView:table acceptDrop:(id)info row:4 dropOperation:NSTableViewDropAbove] &&
        [target isEqual:@"group-1"] && [payload[@"before"] isEqual:@"/Getting started.pdf"],"same-group drop carries exact before-document anchor");
    Check([manager tableView:table acceptDrop:(id)info row:6 dropOperation:NSTableViewDropOn] && [target isEqual:@"group-2"] && ![payload[@"before"] length],
        "drop on a group appends to that group");
    Check([manager tableView:table acceptDrop:(id)info row:count dropOperation:NSTableViewDropAbove] && [target isEqual:@"group-5"],
        "drop after last row appends at list end");
    info.draggingSource=[NSTableView new];
    Check(![manager tableView:table acceptDrop:(id)info row:4 dropOperation:NSTableViewDropAbove],"foreign source is rejected");
    info.draggingSource=table;
    [manager tableView:table draggingSession:(id)[NSObject new] endedAtPoint:NSZeroPoint operation:NSDragOperationNone];
    Check(![manager tableView:table acceptDrop:(id)info row:4 dropOperation:NSTableViewDropAbove],"cancelled drag tokens cannot be replayed");
    Check(table.numberOfRows==count,"cancel preserves disclosure state");
    [info.draggingPasteboard releaseGlobally];
    // A document context menu is supplied by the tab strip, not group actions.
    manager.documentMenuProvider=^NSMenu*(NSString* path,NSString* group) {
        Check([path isEqual:@"/Getting started.pdf"] && [group isEqual:@"general"],"context menu targets the document identity");
        NSMenu* menu=[NSMenu new]; [menu addItemWithTitle:@"Close Document" action:nil keyEquivalent:@""]; return menu;
    };
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
    [manager menuNeedsUpdate:table.menu];
    Check(table.menu.numberOfItems==1 && [table.menu.itemArray.firstObject.title isEqual:@"Close Document"],"document rows use document menu provider");
}

static void CheckGroupDragAutoscroll(void) {
    NSWindow* window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,280,240) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    SPDFGroupManagementController* manager=[SPDFGroupManagementController new];
    NSMutableArray* documents=[NSMutableArray array];
    for(NSUInteger i=0;i<40;i++) [documents addObject:@{@"title":@"Document",@"path":[NSString stringWithFormat:@"/%lu.pdf",i]}];
    [manager updateGroups:@[@{@"id":@"g",@"name":@"Group",@"color":@"Blue",@"documents":documents}]
        state:@{@"expandedGroups":@[@"g"]}];
    window.contentView=manager.view; [window.contentView layoutSubtreeIfNeeded];
    NSTableView* table=(id)Find(manager.view,NSTableView.class);
    NSScrollView* scroll=table.enclosingScrollView;
    NSRect visible=table.visibleRect;
    NSPoint point=[table convertPoint:NSMakePoint(NSMidX(visible),NSMaxY(visible)+8) toView:nil];
    NSEvent* event=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDragged location:point modifierFlags:0 timestamp:0
        windowNumber:window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
    [table autoscroll:event];
    Check(NSMinY(scroll.contentView.bounds)>0,"document drag at the lower edge scrolls a crowded panel");
    point=[table convertPoint:NSMakePoint(NSMidX(table.visibleRect),NSMinY(table.visibleRect)-8) toView:nil];
    CGFloat before=NSMinY(scroll.contentView.bounds);
    event=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDragged location:point modifierFlags:0 timestamp:0
        windowNumber:window.windowNumber context:nil eventNumber:2 clickCount:1 pressure:1];
    [table autoscroll:event];
    Check(NSMinY(scroll.contentView.bounds)<before,"document drag at the upper edge scrolls back");
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
