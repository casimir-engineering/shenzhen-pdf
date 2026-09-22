#import <Cocoa/Cocoa.h>

#import "SPDFMacTabGroups.h"
#import "SPDFMacTabStripViewPrivate.h"

@interface SPDFGroupFakeTab : NSObject
@property(nonatomic, strong) SPDFTabGroup* group;
@property(nonatomic, copy) NSString* path;
@property(nonatomic, copy) NSString* title;
@property(nonatomic) BOOL readOnly;
@property(nonatomic) BOOL missingFile;
@end
@implementation SPDFGroupFakeTab
@end

@interface SPDFGroupFakeReader : NSObject <SPDFTabGroupReader>
@property(nonatomic) NSInteger toggles;
@property(nonatomic) NSInteger createdGroups;
@property(nonatomic) NSInteger movedToGroup;
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
- (void)moveTabAtIndex:(NSInteger)index toGroup:(SPDFTabGroup*)group atIndex:(NSInteger)destination {
    (void)index, (void)destination;
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
- (void)newTabRequested:(id)sender { (void)sender; }
- (void)selectTabAtIndex:(NSInteger)index { (void)index; }
- (void)moveTabFromIndex:(NSInteger)sourceIndex toIndex:(NSInteger)targetIndex {
    (void)sourceIndex, (void)targetIndex;
}
- (void)closeTabAtIndex:(NSInteger)index { (void)index; }
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
    NSInteger x = MAX(0, MIN(bitmap.pixelsWide - 1, (NSInteger)floor(point.x)));
    NSInteger y = MAX(0, MIN(bitmap.pixelsHigh - 1, (NSInteger)floor(point.y)));
    NSColor* color = [bitmap colorAtX:x y:y];
    return (unsigned char)lrint(color.alphaComponent * 255.0);
}

static NSBitmapImageRep* render_strip(SPDFTabStripView* strip, NSAppearance* appearance, NSString* path) {
    strip.appearance = appearance;
    NSBitmapImageRep* bitmap = [strip bitmapImageRepForCachingDisplayInRect:strip.bounds];
    [strip cacheDisplayInRect:strip.bounds toBitmapImageRep:bitmap];
    NSData* png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    expect([png writeToFile:path atomically:YES], [@"could not write " stringByAppendingString:path]);
    return bitmap;
}

int main(void) {
    @autoreleasepool {
        (void)NSApplication.sharedApplication;
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

        // Activating a custom group collapses other custom groups but leaves
        // General alone; the selected group is always expanded and visible.
        general.collapsed = NO;
        green.collapsed = NO;
        spdf_tab_groups_activate((id)tabs, (id)tabs[9]);
        expect(!general.collapsed, @"automatic activation collapsed General");
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

        // A collapsed custom group's name opens rename; its chevron toggles.
        blue.collapsed = YES;
        strip.tabs = (id)tabs;
        blueHeader = [[layout_for_group(strip, blue) valueForKey:@"header"] rectValue];
        NSPoint namePoint = NSMakePoint(NSMinX(blueHeader) + 34, NSMidY(blueHeader));
        expect([strip handleGroupMouseDown:mouse(window, NSEventTypeLeftMouseDown, namePoint)],
               @"collapsed group name was not a hit zone");
        expect([strip handleGroupMouseUp:mouse(window, NSEventTypeLeftMouseUp, namePoint)],
               @"collapsed group name mouse-up was not handled");
        expect(strip.renameRequests == 1 && reader.toggles == 0,
               @"collapsed custom-group name did not route to rename only");
        NSPoint chevronPoint = NSMakePoint(NSMinX(blueHeader) + 13, NSMidY(blueHeader));
        [strip handleGroupMouseDown:mouse(window, NSEventTypeLeftMouseDown, chevronPoint)];
        [strip handleGroupMouseUp:mouse(window, NSEventTypeLeftMouseUp, chevronPoint)];
        expect(reader.toggles == 1, @"group chevron did not toggle collapse");

        // General has no rename behavior: even its expanded name area toggles.
        general.collapsed = YES;
        strip.tabs = (id)tabs;
        NSRect generalHeader = [[layout_for_group(strip, general) valueForKey:@"header"] rectValue];
        NSPoint generalName = NSMakePoint(NSMinX(generalHeader) + 34, NSMidY(generalHeader));
        [strip handleGroupMouseDown:mouse(window, NSEventTypeLeftMouseDown, generalName)];
        [strip handleGroupMouseUp:mouse(window, NSEventTypeLeftMouseUp, generalName)];
        expect(reader.toggles == 2 && strip.renameRequests == 1, @"General name entered rename behavior");

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
        general.collapsed = NO;
        blue.collapsed = NO;
        strip.tabs = (id)tabs;
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
        expect([crowdedVisible containsObject:@(crowdedSelected)] ||
                   ([crowdedHidden containsObject:@(crowdedSelected)] && !NSIsEmptyRect(strip.overflowRect)),
               @"selected tab in an overflowed late group became unreachable");
        expect([crowdedHidden containsObject:@0] && [crowdedHidden containsObject:@1],
               @"collapsed group members were omitted from overflow");
    }
    puts("SPDF mac tab-group interaction tests passed");
    return 0;
}
