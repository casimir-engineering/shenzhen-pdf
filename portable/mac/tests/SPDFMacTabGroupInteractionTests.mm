#import <Cocoa/Cocoa.h>

#import "SPDFMacTabGroups.h"
#import "SPDFMacTabStripViewPrivate.h"

@interface SPDFGroupFakeTab : NSObject
@property(nonatomic, strong) SPDFTabGroup* group;
@property(nonatomic, copy) NSString* path;
@property(nonatomic, copy) NSString* title;
@property(nonatomic, copy) NSString* collectionVersionLabel;
@property(nonatomic) BOOL readOnly;
@property(nonatomic) BOOL missingFile;
@end
@implementation SPDFGroupFakeTab
@end

@interface SPDFGroupFakeReader : NSObject <SPDFTabGroupReader>
@property(nonatomic) NSInteger toggles;
@property(nonatomic) NSInteger createdGroups;
@property(nonatomic) BOOL createdBeforeTarget;
@property(nonatomic) NSInteger movedToGroup;
@property(nonatomic) NSInteger lastInsertionIndex;
@property(nonatomic) NSInteger selectedTab;
@property(nonatomic) NSInteger closedTab;
@property(nonatomic) NSInteger newTabRequests;
@property(nonatomic, strong) SPDFTabGroup* lastDestination;
@property(nonatomic, copy) NSString* lastColor;
@end

@implementation SPDFGroupFakeReader
- (void)toggleTabGroup:(SPDFTabGroup*)group { self.toggles++; group.collapsed = !group.collapsed; }
- (void)createGroupForTabAtIndex:(NSInteger)index withTabAtIndex:(NSInteger)other color:(NSString*)color {
    (void)index, (void)other;
    self.createdGroups++;
    self.lastColor = color;
}
- (void)createGroupForTabAtIndex:(NSInteger)index withTabAtIndex:(NSInteger)other color:(NSString*)color
             beforeTargetGroup:(BOOL)before {
    self.createdBeforeTarget = before;
    [self createGroupForTabAtIndex:index withTabAtIndex:other color:color];
}
- (void)moveTabAtIndex:(NSInteger)index toGroup:(SPDFTabGroup*)group atIndex:(NSInteger)destination {
    (void)index;
    self.lastInsertionIndex = destination;
    self.movedToGroup++;
    self.lastDestination = group;
}
- (void)renameTabGroup:(SPDFTabGroup*)group name:(NSString*)name { (void)group, (void)name; }
- (void)recolorTabGroup:(SPDFTabGroup*)group color:(NSString*)color { (void)group, (void)color; }
- (void)ungroupTabs:(SPDFTabGroup*)group { (void)group; }
- (void)closeTabGroup:(SPDFTabGroup*)group { (void)group; }
- (void)moveTabGroup:(SPDFTabGroup*)group toIndex:(NSInteger)index { (void)group, (void)index; }
- (NSArray<NSDictionary*>*)snapshotTabGroup:(SPDFTabGroup*)group { (void)group; return @[]; }
- (void)insertDraggedGroup:(NSArray<NSDictionary*>*)tabs atIndex:(NSInteger)index { (void)tabs, (void)index; }
- (void)detachTabGroup:(SPDFTabGroup*)group atScreenPoint:(NSPoint)point { (void)group, (void)point; }
- (void)newTabRequested:(id)sender { (void)sender; self.newTabRequests++; }
- (void)selectTabAtIndex:(NSInteger)index { self.selectedTab = index; }
- (void)moveTabFromIndex:(NSInteger)sourceIndex toIndex:(NSInteger)targetIndex {
    (void)sourceIndex, (void)targetIndex;
}
- (void)closeTabAtIndex:(NSInteger)index { self.closedTab = index; }
- (void)detachTabAtIndex:(NSInteger)index { (void)index; }
- (void)insertDraggedTab:(id)tab atIndex:(NSInteger)index { (void)tab, (void)index; }
- (BOOL)documentTypeToSearchKeyDown:(NSEvent*)event { (void)event; return NO; }
@end

@interface SPDFGroupTestStrip : SPDFTabStripView
@property(nonatomic) NSInteger renameRequests;
@property(nonatomic) NSInteger groupDragRequests;
@end
@implementation SPDFGroupTestStrip
- (void)renameGroup:(SPDFTabGroup*)group { if (group) self.renameRequests++; }
- (void)startGroupDragSessionWithEvent:(NSEvent*)event { (void)event; self.groupDragRequests++; }
@end

NSString* spdf_display_label_without_extension(NSString* label) { return label ?: @""; }
NSString* spdf_display_name_for_path(NSString* path) { return path.lastPathComponent ?: @""; }
NSArray<NSString*>* spdf_disambiguated_display_names_for_paths(NSArray<NSString*>* paths) { return paths; }
NSDictionary* spdf_dictionary_from_tab(SPDFDocumentTab* tab, NSInteger sourceWindowNumber) {
    (void)tab, (void)sourceWindowNumber;
    return @{};
}
SPDFDocumentTab* spdf_tab_from_dictionary(NSDictionary* item) { (void)item; return nil; }
void spdf_set_menu_item_system_symbol(NSMenuItem* item, NSString* symbolName) { (void)item, (void)symbolName; }

static void expect(BOOL condition, NSString* message) {
    if (condition) return;
    NSLog(@"FAIL: %@", message);
    exit(1);
}

static SPDFGroupFakeTab* tab(NSString* name, SPDFTabGroup* group) {
    SPDFGroupFakeTab* value = [SPDFGroupFakeTab new];
    value.path = [@"/tmp" stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"pdf"]];
    value.title = name;
    value.group = group;
    return value;
}

static NSEvent* mouse(NSWindow* window, NSEventType type, NSPoint point) {
    return [NSEvent mouseEventWithType:type location:point modifierFlags:0
                             timestamp:NSProcessInfo.processInfo.systemUptime
                          windowNumber:window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
}

static id layout_for_group(SPDFTabStripView* strip, SPDFTabGroup* group) {
    for (id layout in strip.groupLayouts)
        if ([layout valueForKey:@"group"] == group) return layout;
    return nil;
}

static unsigned char alpha_at(NSBitmapImageRep* bitmap, NSPoint point) {
    NSInteger x = MAX(0, MIN(bitmap.pixelsWide - 1, (NSInteger)floor(point.x * bitmap.pixelsWide / bitmap.size.width)));
    NSInteger y = MAX(0, MIN(bitmap.pixelsHigh - 1, (NSInteger)floor(point.y * bitmap.pixelsHigh / bitmap.size.height)));
    NSColor* color = [bitmap colorAtX:x y:y];
    return (unsigned char)lrint(color.alphaComponent * 255.0);
}

static NSBitmapImageRep* render_strip(SPDFTabStripView* strip, NSAppearance* appearance, NSString* path) {
    strip.appearance = appearance;
    NSBitmapImageRep* bitmap = [strip bitmapImageRepForCachingDisplayInRect:strip.bounds];
    [strip cacheDisplayInRect:strip.bounds toBitmapImageRep:bitmap];
    NSData* png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    expect([png writeToFile:path atomically:YES], [@"could not write " stringByAppendingString:path]);
    NSBitmapImageRep* compositedBitmap = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)NSWidth(strip.bounds)
        pixelsHigh:(NSInteger)NSHeight(strip.bounds) bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [appearance performAsCurrentDrawingAppearance:^{
      [NSGraphicsContext saveGraphicsState];
      NSGraphicsContext* context = [NSGraphicsContext graphicsContextWithBitmapImageRep:compositedBitmap];
      NSGraphicsContext.currentContext = context;
      NSColor* background = [NSColor.windowBackgroundColor colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
      CGFloat red = 0, green = 0, blue = 0, alpha = 1;
      [background getRed:&red green:&green blue:&blue alpha:&alpha];
      CGContextRef graphicsPort = context.CGContext;
      CGContextSetRGBFillColor(graphicsPort, red, green, blue, alpha);
      CGContextFillRect(graphicsPort, NSRectToCGRect(strip.bounds));
      [bitmap drawInRect:NSMakeRect(0, 0, strip.bounds.size.width, strip.bounds.size.height)
                fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1
          respectFlipped:YES hints:nil];
      [NSGraphicsContext restoreGraphicsState];
    }];
    NSString* compositedPath = [path.stringByDeletingPathExtension stringByAppendingString:@"-composited.png"];
    NSData* compositedPNG = [compositedBitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    expect([compositedPNG writeToFile:compositedPath atomically:YES],
           [@"could not write " stringByAppendingString:compositedPath]);
    return bitmap;
}

static void check_group_reorder(BOOL useGeneral) {
    NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1200,42)
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    SPDFGroupTestStrip* strip = [[SPDFGroupTestStrip alloc] initWithFrame:window.contentView.bounds];
    SPDFGroupFakeReader* reader = [SPDFGroupFakeReader new];
    strip.reader = (id)reader;
    [window.contentView addSubview:strip];
    SPDFTabGroup* group = useGeneral ? SPDFTabGroup.generalGroup : [SPDFTabGroup groupWithColor:@"Blue"];
    SPDFTabGroup* other = [SPDFTabGroup groupWithColor:@"Green"];
    strip.tabs = (id)@[tab(@"Moving document",group), tab(@"Second",group), tab(@"Third",group),
                      tab(@"Other group",other)];
    strip.selectedIndex = 0;
    NSRect first = [strip rectForTabAtIndex:0], second = [strip rectForTabAtIndex:1];
    NSRect third = [strip rectForTabAtIndex:2], outside = [strip rectForTabAtIndex:3];
    NSPoint start = NSMakePoint(NSMinX(first)+28, NSMidY(first));
    NSPoint right = NSMakePoint(NSMidX(second)+8, start.y);
    [strip mouseDown:mouse(window,NSEventTypeLeftMouseDown,start)];
    [strip mouseDragged:mouse(window,NSEventTypeLeftMouseDragged,right)];
    expect(strip.isVisuallyReorderingTabs, @"grouped drag did not enable its moving preview");
    expect(fabs(NSMinX([strip visualRectForTabAtIndex:0])-floor(right.x-28)) < 0.1,
           @"moving grouped tab did not preserve the pointer's grab offset");
    expect(NSEqualRects([strip visualRectForTabAtIndex:1],first), @"rightward drag did not shift sibling left");
    expect(NSEqualRects([strip visualRectForTabAtIndex:2],third), @"uncrossed sibling moved");
    expect(NSEqualRects([strip visualRectForTabAtIndex:3],outside), @"reorder displaced another group's tabs");
    expect(reader.movedToGroup == 0, @"preview committed document order before mouse release");
    [strip setValue:@(NSDate.timeIntervalSinceReferenceDate-1) forKey:@"groupHoverBegan"];
    [strip updateGroupDropForPoint:right sourceIndex:0];
    expect([strip valueForKey:@"groupDropGroup"] == nil && [[strip valueForKey:@"groupDropTabIndex"] integerValue] < 0,
           @"pausing within a group changed a reorder into a group join or creation");
    render_strip(strip,[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua],
                 useGeneral ? @"/tmp/spdf-group-reorder-general.png" : @"/tmp/spdf-group-reorder-blue.png");
    [strip mouseUp:mouse(window,NSEventTypeLeftMouseUp,right)];
    expect(reader.movedToGroup == 1 && reader.lastDestination == group && reader.lastInsertionIndex == 2,
           @"released tab did not use the previewed insertion position");
    expect(!strip.isVisuallyReorderingTabs && NSEqualRects([strip visualRectForTabAtIndex:1],second),
           @"drop left stale preview geometry");

    strip.selectedIndex = 2;
    start = NSMakePoint(NSMinX(third)+28,NSMidY(third));
    NSPoint left = NSMakePoint(NSMidX(first)-8,start.y);
    [strip mouseDown:mouse(window,NSEventTypeLeftMouseDown,start)];
    [strip mouseDragged:mouse(window,NSEventTypeLeftMouseDragged,left)];
    expect(NSEqualRects([strip visualRectForTabAtIndex:0],second) &&
           NSEqualRects([strip visualRectForTabAtIndex:1],third), @"leftward drag did not shift siblings right");
    [strip mouseUp:mouse(window,NSEventTypeLeftMouseUp,left)];
    expect(reader.lastInsertionIndex == 0 && reader.createdGroups == 0, @"leftward drop changed group membership");

    strip.selectedIndex = 0;
    start = NSMakePoint(NSMinX(first)+28,NSMidY(first));
    NSPoint across = NSMakePoint(NSMidX(outside),start.y);
    [strip mouseDown:mouse(window,NSEventTypeLeftMouseDown,start)];
    [strip mouseDragged:mouse(window,NSEventTypeLeftMouseDragged,across)];
    [strip setValue:@(NSDate.timeIntervalSinceReferenceDate-1) forKey:@"groupHoverBegan"];
    [strip updateGroupDropForPoint:across sourceIndex:0];
    expect([strip valueForKey:@"groupDropGroup"] == other && strip.isVisuallyReorderingTabs,
           @"joining another group lost either the destination highlight or moving tab");
    expect(NSEqualRects([strip visualRectForTabAtIndex:3],outside), @"cross-group preview overlapped the group header");
    [strip resetTabDragTracking];
    expect(NSEqualRects([strip visualRectForTabAtIndex:0],first), @"reset did not restore the original tab geometry");

    // A later group's handle means its own first slot, never the preceding
    // group's last tab. Its neighbors must remain outside this preview.
    strip.tabs = (id)@[tab(@"Other first",other),tab(@"Other second",other),
                      tab(@"First",group),tab(@"Second",group),tab(@"Moving",group)];
    strip.selectedIndex = 4;
    NSRect last = [strip rectForTabAtIndex:4];
    NSRect header = [[layout_for_group(strip,group) valueForKey:@"header"] rectValue];
    start = NSMakePoint(NSMinX(last)+28,NSMidY(last));
    left = NSMakePoint(NSMidX(header),NSMidY(header));
    [strip mouseDown:mouse(window,NSEventTypeLeftMouseDown,start)];
    [strip mouseDragged:mouse(window,NSEventTypeLeftMouseDragged,left)];
    expect([[strip valueForKey:@"dragTargetTabIndex"] integerValue] == 2,
           @"dragging onto the source group's handle targeted the previous group");
    expect(NSEqualRects([strip visualRectForTabAtIndex:1],[strip rectForTabAtIndex:1]),
           @"source header reorder displaced the preceding group");
    [strip mouseUp:mouse(window,NSEventTypeLeftMouseUp,left)];
    expect(reader.lastDestination == group && reader.lastInsertionIndex == 2,
           @"source handle drop appended instead of using the group's first slot");
}

#include "SPDFMacTabGroupOverflowChecks.h"

int main(void) {
    @autoreleasepool {
        (void)NSApplication.sharedApplication;
        check_group_reorder(YES);
        check_group_reorder(NO);
        check_group_overflow();
        check_group_creation_side();
        NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 42)
                                                       styleMask:NSWindowStyleMaskBorderless
                                                         backing:NSBackingStoreBuffered defer:NO];
        SPDFGroupTestStrip* strip = [[SPDFGroupTestStrip alloc] initWithFrame:window.contentView.bounds];
        SPDFGroupFakeReader* reader = [SPDFGroupFakeReader new];
        strip.reader = (id)reader;
        [window.contentView addSubview:strip];

        SPDFTabGroup* general = SPDFTabGroup.generalGroup;
        SPDFTabGroup* blue = [SPDFTabGroup groupWithColor:@"Blue"];
        SPDFTabGroup* green = [SPDFTabGroup groupWithColor:@"Green"];
        strip.frame = NSMakeRect(0,0,1120,42);
        strip.tabs = (id)@[tab(@"General A", general), tab(@"Archive", general), tab(@"Blue A", blue)];
        strip.selectedIndex = 2;
        expect(strip.groupedVisibleTabIndexes.count == 3 && !strip.groupedHasOverflow,
               @"three tabs must use available space before overflowing");
        SPDFGroupFakeTab* archived = (id)strip.tabs[1];
        archived.collectionVersionLabel = @"Archived · Sep 23 · Notes · Read-only";
        expect([[strip titleForTabAtIndex:1] isEqual:archived.collectionVersionLabel], @"archive label must bypass path disambiguation");
        strip.frame = NSMakeRect(0,0,900,42);
        NSMutableArray* tabs = [NSMutableArray arrayWithObjects:tab(@"General A", general),
                                 tab(@"General B", general), nil];
        for (NSInteger i = 0; i < 8; ++i) [tabs addObject:tab([NSString stringWithFormat:@"Blue %ld", (long)i], blue)];
        [tabs addObject:tab(@"Green A", green)];
        [tabs addObject:tab(@"Green B", green)];
        strip.tabs = (id)tabs;
        strip.selectedIndex = 9;

        NSArray<NSNumber*>* visible = strip.groupedVisibleTabIndexes;
        expect([visible containsObject:@9], @"crowded group layout hid the selected tab");
        expect(!NSIsEmptyRect([strip groupedRectForTabAtIndex:9]), @"selected tab has no grouped frame");
        expect(strip.groupedHasOverflow, @"crowded grouped strip did not report overflow");

        // Activating a group collapses every other group, including General.
        // The selected group is always expanded and visible.
        general.collapsed = NO;
        green.collapsed = NO;
        spdf_tab_groups_activate((id)tabs, (id)tabs[9]);
        expect(general.collapsed, @"automatic activation left inactive General expanded");
        expect(!blue.collapsed, @"automatic activation collapsed the selected group");
        expect(green.collapsed, @"automatic activation left an inactive custom group expanded");
        strip.tabs = (id)tabs;

        id blueLayout = layout_for_group(strip, blue);
        NSRect blueFrame = [[blueLayout valueForKey:@"frame"] rectValue];
        NSRect blueHeader = [[blueLayout valueForKey:@"header"] rectValue];
        expect(!NSIsEmptyRect(blueFrame) && !NSIsEmptyRect(blueHeader), @"expanded group has no chrome geometry");

        NSBitmapImageRep* bitmap = render_strip(strip, [NSAppearance appearanceNamed:NSAppearanceNameAqua],
                                                @"/tmp/spdf-tab-groups-light.png");
        expect(alpha_at(bitmap, NSMakePoint(NSMinX(blueFrame) + 1, NSMinY(blueFrame) + 1)) == 0,
               @"group background lost its rounded transparent corner");
        expect(alpha_at(bitmap, NSMakePoint(NSMinX(blueHeader) + 4, NSMidY(blueHeader))) > 0,
               @"group background was not painted behind its header");
        render_strip(strip, [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua],
                     @"/tmp/spdf-tab-groups-dark.png");
        spdf_tab_groups_activate((id)tabs, (id)tabs[0]);
        strip.tabs = (id)tabs;
        strip.selectedIndex = 0;
        render_strip(strip, [NSAppearance appearanceNamed:NSAppearanceNameAqua],
                     @"/tmp/spdf-tab-groups-general.png");

        // Both the collapsed name and chevron open the group, never rename it.
        blue.collapsed = YES;
        strip.tabs = (id)tabs;
        blueHeader = [[layout_for_group(strip, blue) valueForKey:@"header"] rectValue];
        NSPoint namePoint = NSMakePoint(NSMinX(blueHeader) + 34, NSMidY(blueHeader));
        expect([strip handleGroupMouseDown:mouse(window, NSEventTypeLeftMouseDown, namePoint)],
               @"collapsed group name was not a hit zone");
        expect([strip handleGroupMouseUp:mouse(window, NSEventTypeLeftMouseUp, namePoint)],
               @"collapsed group name mouse-up was not handled");
        expect(strip.renameRequests == 0 && reader.toggles == 1,
               @"collapsed custom-group name did not open the group");
        NSPoint chevronPoint = NSMakePoint(NSMinX(blueHeader) + 13, NSMidY(blueHeader));
        [strip handleGroupMouseDown:mouse(window, NSEventTypeLeftMouseDown, chevronPoint)];
        [strip handleGroupMouseUp:mouse(window, NSEventTypeLeftMouseUp, chevronPoint)];
        expect(reader.toggles == 2, @"group chevron did not toggle collapse");

        // General uses the same activation behavior; rename stays in its menu.
        general.collapsed = YES;
        strip.tabs = (id)tabs;
        render_strip(strip, [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua],
                     @"/tmp/spdf-tab-group-labels-centered.png");
        NSRect generalHeader = [[layout_for_group(strip, general) valueForKey:@"header"] rectValue];
        NSPoint generalName = NSMakePoint(NSMinX(generalHeader) + 34, NSMidY(generalHeader));
        [strip handleGroupMouseDown:mouse(window, NSEventTypeLeftMouseDown, generalName)];
        [strip handleGroupMouseUp:mouse(window, NSEventTypeLeftMouseUp, generalName)];
        expect(reader.toggles == 3 && strip.renameRequests == 0,
               [NSString stringWithFormat:@"General name routing: toggles=%ld renames=%ld",
                                          (long)reader.toggles, (long)strip.renameRequests]);
        NSMenuItem* rename = [[strip contextMenuForGroup:general] itemWithTitle:@"Rename Group…"];
        [NSApp sendAction:rename.action to:rename.target from:rename];
        expect(strip.renameRequests == 1, @"context menu must retain explicit group rename");

        // A header drag routes the whole group once it crosses the threshold.
        strip.tabs = (id)tabs;
        blueHeader = [[layout_for_group(strip, blue) valueForKey:@"header"] rectValue];
        chevronPoint = NSMakePoint(NSMinX(blueHeader) + 13, NSMidY(blueHeader));
        [strip handleGroupMouseDown:mouse(window, NSEventTypeLeftMouseDown, chevronPoint)];
        [strip handleGroupMouseDragged:mouse(window, NSEventTypeLeftMouseDragged,
                                             NSMakePoint(chevronPoint.x + 8, chevronPoint.y))];
        expect(strip.groupDragRequests == 1, @"group-header drag did not start a group drag session");

        // Hovering a tab center creates a stable-color pair preview; its edge
        // remains ordinary reorder territory. Centering on a custom tab joins it.
        strip.frame = NSMakeRect(0,0,1800,42); // Hover checks require their General target to be visible.
        general.collapsed = NO;
        blue.collapsed = NO;
        strip.tabs = (id)tabs;
        strip.selectedIndex = 9;
        NSRect generalTab = [strip groupedRectForTabAtIndex:0];
        NSPoint center = NSMakePoint(NSMidX(generalTab), NSMidY(generalTab));
        [strip updateGroupDropForPoint:center sourceIndex:2];
        [strip setValue:@(NSDate.timeIntervalSinceReferenceDate - 1) forKey:@"groupHoverBegan"];
        [strip updateGroupDropForPoint:center sourceIndex:2];
        NSString* previewColor = [strip valueForKey:@"groupPreviewColor"];
        expect(previewColor.length > 0, @"center hover did not choose a pastel group color");
        [strip updateGroupDropForPoint:center sourceIndex:2];
        expect([[strip valueForKey:@"groupPreviewColor"] isEqualToString:previewColor],
               @"pair preview color changed while the hover stayed active");
        expect([strip performGroupDropWithTab:(id)tabs[2] sourceIndex:2 atPoint:center],
               @"center drop was not handled as group creation");
        expect(reader.createdGroups == 1 && [reader.lastColor isEqualToString:previewColor],
               @"center drop did not route its preview color to group creation");

        NSPoint edge = NSMakePoint(NSMinX(generalTab) + 2, NSMidY(generalTab));
        [strip updateGroupDropForPoint:edge sourceIndex:2];
        expect(![strip performGroupDropWithTab:(id)tabs[2] sourceIndex:2 atPoint:edge],
               @"tab edge was consumed as a group drop instead of reorder");

        NSRect blueTab = [strip groupedRectForTabAtIndex:9];
        NSPoint blueCenter = NSMakePoint(NSMidX(blueTab), NSMidY(blueTab));
        [strip updateGroupDropForPoint:blueCenter sourceIndex:0];
        [strip setValue:@(NSDate.timeIntervalSinceReferenceDate - 1) forKey:@"groupHoverBegan"];
        [strip updateGroupDropForPoint:blueCenter sourceIndex:0];
        expect([strip performGroupDropWithTab:(id)tabs[0] sourceIndex:0 atPoint:blueCenter],
               @"custom-group center drop was not handled");
        expect(reader.movedToGroup == 1 && reader.lastDestination == blue,
               @"custom-group center drop did not route to move-into-group");

        // Whole-group drops use group frames even when every group is folded
        // and therefore no tab midpoint exists.
        general.collapsed = YES;
        blue.collapsed = YES;
        green.collapsed = YES;
        strip.tabs = (id)tabs;
        NSArray* layouts = strip.groupLayouts;
        expect(layouts.count == 3, @"collapsed group layout count changed");
        NSRect firstGroup = [[[layouts objectAtIndex:0] valueForKey:@"frame"] rectValue];
        NSRect secondGroup = [[[layouts objectAtIndex:1] valueForKey:@"frame"] rectValue];
        NSRect thirdGroup = [[[layouts objectAtIndex:2] valueForKey:@"frame"] rectValue];
        expect([strip groupInsertionIndexForPoint:NSMakePoint(NSMinX(firstGroup), NSMidY(firstGroup))] == 0,
               @"collapsed-group drop before the first group missed index zero");
        expect([strip groupInsertionIndexForPoint:NSMakePoint(NSMinX(secondGroup), NSMidY(secondGroup))] == 2,
               @"collapsed-group drop before the second group split the first group");
        expect([strip groupInsertionIndexForPoint:NSMakePoint(NSMaxX(thirdGroup) + 2, NSMidY(thirdGroup))] ==
                   (NSInteger)tabs.count,
               @"collapsed-group drop after the last group did not append");

        // When headers alone exceed the window, whole groups move into the
        // existing overflow path. Every hidden member remains addressable,
        // including the selected tab in a late group.
        strip.frame = NSMakeRect(0,0,900,42);
        NSMutableArray* crowdedTabs = [NSMutableArray array];
        NSMutableArray* crowdedGroups = [NSMutableArray array];
        for (NSInteger i = 0; i < 12; ++i) {
            SPDFTabGroup* group = [SPDFTabGroup groupWithColor:spdf_tab_group_colors()[(NSUInteger)i % 10]];
            group.name = [NSString stringWithFormat:@"Reference Group %ld", (long)i];
            group.collapsed = YES;
            [crowdedGroups addObject:group];
            [crowdedTabs addObject:tab([NSString stringWithFormat:@"Crowded %ld A", (long)i], group)];
            [crowdedTabs addObject:tab([NSString stringWithFormat:@"Crowded %ld B", (long)i], group)];
        }
        NSInteger crowdedSelected = (NSInteger)crowdedTabs.count - 1;
        spdf_tab_groups_activate((id)crowdedTabs, (id)crowdedTabs[(NSUInteger)crowdedSelected]);
        strip.tabs = (id)crowdedTabs;
        strip.selectedIndex = crowdedSelected;
        NSArray<NSNumber*>* crowdedVisible = strip.groupedVisibleTabIndexes;
        NSArray<NSNumber*>* crowdedHidden = strip.hiddenTabIndexes;
        expect([crowdedVisible containsObject:@(crowdedSelected)] &&
                   [crowdedVisible containsObject:@(crowdedSelected-1)],
               @"collapsed headers hid a member of the active pair in a late group");
        expect([crowdedHidden containsObject:@0] && [crowdedHidden containsObject:@1],
               @"collapsed group members were omitted from overflow");
        NSMenu* groupedOverflow = [strip overflowMenu];
        NSUInteger overflowHeadings = 0;
        for (NSMenuItem* item in groupedOverflow.itemArray)
            if (!item.enabled && !item.separatorItem && item.image) ++overflowHeadings;
        expect(overflowHeadings >= 2, @"grouped overflow omitted named color headings");

        // Context moves enumerate every existing destination once, including
        // General, and identify current membership without relying on color.
        strip.tabs = (id)tabs;
        strip.selectedIndex = 9;
        NSMenu* destinations = [strip moveToGroupMenuForTabAtIndex:9];
        expect(destinations.numberOfItems == 3, @"Move to Group omitted an existing destination");
        expect([destinations.itemArray[0].title isEqualToString:@"General"] &&
                   [destinations.itemArray[1].title isEqualToString:blue.displayName] &&
                   [destinations.itemArray[2].title isEqualToString:green.displayName],
               @"Move to Group did not preserve visible group order");
        expect(destinations.itemArray[1].state == NSControlStateValueOn,
               @"Move to Group did not check the tab's current group");
        expect(destinations.itemArray[0].image != nil && destinations.itemArray[1].image != nil,
               @"Move to Group destinations omitted color swatches");
        [strip tabContextMoveToGroup:destinations.itemArray[0]];
        expect(reader.lastDestination == general, @"Move to Group did not route the General destination");

        // The custom-drawn strip must expose actionable virtual children: all
        // tabs (including overflow), group disclosure controls and the plus.
        NSArray* accessible = strip.accessibilityChildren;
        NSPredicate* blueGroup = [NSPredicate predicateWithBlock:^BOOL(id item, NSDictionary* bindings) {
          (void)bindings;
          return [[item accessibilityRole] isEqualToString:NSAccessibilityDisclosureTriangleRole] &&
                 [[item accessibilityLabel] isEqualToString:blue.displayName];
        }];
        expect([[accessible filteredArrayUsingPredicate:blueGroup] count] == 1,
               @"accessibility tree omitted the Blue group disclosure");
        id blueAX = [accessible filteredArrayUsingPredicate:blueGroup].firstObject;
        expect([[blueAX accessibilityHelp] containsString:@"Press to"],
               @"group accessibility omitted collapse/expand help");
        expect([[[blueAX accessibilityCustomActions] valueForKey:@"name"] containsObject:@"Show Group Menu"],
               @"group accessibility omitted its context menu action");
        NSPredicate* selectedTab = [NSPredicate predicateWithBlock:^BOOL(id item, NSDictionary* bindings) {
          (void)bindings;
          return [[item accessibilityRole] isEqualToString:NSAccessibilityRadioButtonRole] &&
                 [item isAccessibilitySelected];
        }];
        NSArray* selectedChildren = [accessible filteredArrayUsingPredicate:selectedTab];
        expect(selectedChildren.count == 1, @"accessibility tree did not expose one selected tab");
        expect([selectedChildren.firstObject isAccessibilityEnabled],
               @"virtual tab accessibility element was exposed as disabled");
        expect([[[selectedChildren.firstObject accessibilityCustomActions] valueForKey:@"name"]
                    containsObject:@"Show Tab Menu"],
               @"tab accessibility omitted its context menu action");
        expect([selectedChildren.firstObject accessibilityPerformPress],
               @"selected tab accessibility press was rejected");
        expect(reader.selectedTab == 9, @"tab accessibility press did not route selection");
    }
    puts("SPDF mac tab-group interaction tests passed");
    return 0;
}
