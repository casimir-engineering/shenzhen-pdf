#import <Cocoa/Cocoa.h>
#import "SPDFMacGroupManagement.h"
#import "SPDFMacSidebarModeControl.h"
static int failures;
static void Check(BOOL ok, const char* label) { if (!ok) { fprintf(stderr,"FAIL: %s\n",label); failures++; } }
@interface GroupSurface : NSView
@end
@implementation GroupSurface
- (void)drawRect:(NSRect)rect { [NSColor.windowBackgroundColor setFill]; NSRectFill(rect); }
@end
static NSView* Find(NSView* view, Class type) {
    if ([view isKindOfClass:type]) return view;
    for (NSView* child in view.subviews) { NSView* found = Find(child,type); if (found) return found; }
    return nil;
}
static NSButton* Button(NSView* view, NSString* label) {
    if ([view isKindOfClass:NSButton.class] && [view.accessibilityLabel isEqual:label]) return (id)view;
    for (NSView* child in view.subviews) { NSButton* found = Button(child,label); if (found) return found; }
    return nil;
}
static NSArray* Groups(void) {
    NSMutableArray* groups = [NSMutableArray array];
    NSArray* names = @[@"General",@"Research",@"Travel plans",@"Design references",@"Project notes",@"Archive"];
    NSArray* colors = @[@"Gray",@"Blue",@"Teal",@"Purple",@"Coral",@"Green"];
    for (NSUInteger i=0;i<names.count;i++) {
        NSString* identifier = i ? [NSString stringWithFormat:@"group-%lu",i] : @"general";
        [groups addObject:@{@"id":identifier,@"name":names[i],@"color":colors[i],@"hidden":@(i==2 || i==5),@"selected":@(i==1),
            @"documents":@[@{@"title":@"Getting started.pdf",@"path":@"/Getting started.pdf"},
                @{@"title":@"Conference notes.md",@"path":@"/Conference notes.md",@"selected":@(i==1)}]}];
    }
    return groups;
}
static void Render(CGFloat width, CGFloat height, BOOL dark, NSInteger variant, NSString* output) {
    NSWindow* host = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,width,height)
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    host.releasedWhenClosed = NO; host.appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    host.contentView = [[GroupSurface alloc] initWithFrame:NSMakeRect(0,0,width,height)];
    Check(fabs(NSWidth(host.contentView.bounds)-width)<.5,"fixture renders the requested sidebar width");
    SPDFSidebarNavigationControl* navigation = [SPDFSidebarNavigationControl new];
    spdf_sidebar_mode_control_configure_navigation(navigation,variant == 3 || variant == 4,YES);
    navigation.spdf_selectedSidebarMode = SPDFSidebarModeGroups;
    NSMutableArray* fixtureGroups = [Groups() mutableCopy];
    BOOL hiddenActive = variant == 1 || variant == 4;
    if (hiddenActive) {
        NSMutableDictionary* active = [fixtureGroups[1] mutableCopy]; active[@"hidden"] = @YES; fixtureGroups[1] = active;
        NSMutableDictionary* longName = [fixtureGroups[3] mutableCopy]; longName[@"name"] = @"Design references and archived project material"; fixtureGroups[3] = longName;
    }
    SPDFGroupManagementController* manager = [SPDFGroupManagementController new];
    [manager updateGroups:fixtureGroups state:@{@"expandedGroups":@[@"group-1"],@"groupScroll":@100}];
    for (NSView* child in @[navigation,manager.view]) { child.translatesAutoresizingMaskIntoConstraints = NO; [host.contentView addSubview:child]; }
    [NSLayoutConstraint activateConstraints:@[
        [navigation.topAnchor constraintEqualToAnchor:host.contentView.topAnchor constant:8],
        [navigation.leadingAnchor constraintEqualToAnchor:host.contentView.leadingAnchor constant:8],
        [navigation.trailingAnchor constraintEqualToAnchor:host.contentView.trailingAnchor constant:-8],
        [manager.view.topAnchor constraintEqualToAnchor:navigation.bottomAnchor constant:4],
        [manager.view.leadingAnchor constraintEqualToAnchor:host.contentView.leadingAnchor],
        [manager.view.trailingAnchor constraintEqualToAnchor:host.contentView.trailingAnchor],
        [manager.view.bottomAnchor constraintEqualToAnchor:host.contentView.bottomAnchor]]];
    [host.contentView layoutSubtreeIfNeeded];
    Check(fabs(NSWidth(host.contentView.bounds)-width)<.5,"layout preserves the requested sidebar width");
    NSTableView* table = (id)Find(manager.view,NSTableView.class);
    NSSearchField* search = (id)Find(manager.view,NSSearchField.class);
    NSScrollView* scroll = table.enclosingScrollView;
    Check(fabs(NSWidth(table.frame)-NSWidth(scroll.contentView.bounds))<1,"table width follows clip viewport");
    Check(fabs(scroll.contentView.bounds.origin.y-MIN(100,MAX(0,NSHeight(table.frame)-NSHeight(scroll.contentView.bounds))))<1,
        "initial detached scroll restore waits for real viewport and clamps to content");
    Check(table.numberOfRows == 8,"expanded group exposes documents inline");
    Check(NSWidth(scroll.frame) <= width && NSHeight(scroll.frame) > 35,"group list fits narrow and short panel");
    if (height <= 296) Check(NSHeight(scroll.contentView.bounds) >= 76,"minimum sidebar initially fits two complete group rows including gaps");
    Check([manager tableView:table heightOfRow:0] >= 36,"group metadata retains two readable lines");
    Check(NSHeight(search.frame) >= 26 && NSWidth(search.frame) >= 160,"search remains usable at minimum supported width");
    fprintf(stdout,"Groups geometry %.0fx%.0f modes=%ld list=%.0fpt first=%.0fpt\n",width,height,navigation.segmentCount,
        NSHeight(scroll.contentView.bounds),height-NSMaxY([scroll convertRect:scroll.bounds toView:host.contentView]));
    Check(search.focusRingType != NSFocusRingTypeNone,"search retains accessible keyboard focus feedback");
    Check(table.selectedRow == 3,"active document has selected-row feedback");
    __block NSString* action; __block NSString* target; __block NSUInteger changes = 0;
    manager.actionHandler = ^(NSString* verb, NSString* group, NSString* value) { (void)value; action = verb; target = group; changes++; };
    NSView* research = [manager tableView:table viewForTableColumn:table.tableColumns.firstObject row:1];
    [Button(research,hiddenActive ? @"Show Research in tab bar" : @"Hide Research from tab bar") performClick:nil];
    Check([action isEqual:@"visibility"] && [target isEqual:@"group-1"] && changes == 1,"eye action changes visibility without jumping");
    [Button(research,@"Collapse Research documents") performClick:nil];
    Check(table.numberOfRows == 6 && changes == 1,"disclosure changes document expansion without navigation");
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO];
    Check(changes == 1,"keyboard-style row selection alone does not navigate");
    NSEvent* enter = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
        windowNumber:host.windowNumber context:nil characters:@"\r" charactersIgnoringModifiers:@"\r" isARepeat:NO keyCode:36];
    [table keyDown:enter];
    Check(changes == 2 && [action isEqual:@"jump"] && [target isEqual:@"group-2"],"Return activates selected group independently of old mouse row");
    search.stringValue = @"Conference";
    [manager controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:search]];
    Check(table.numberOfRows == 12,"document-name search reveals matching documents under each owning group");
    NSArray* matchedRows = [manager valueForKey:@"rows"];
    Check([matchedRows[1][@"document"][@"title"] isEqual:@"Conference notes.md"],"search excludes unrelated siblings");
    Check([manager.viewState[@"expandedGroups"] count] == 0,"temporary search expansion does not change saved groups");
    search.stringValue = @".MD";
    [manager controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:search]];
    Check(table.numberOfRows == 12,"filename extension search is case insensitive");
    search.stringValue = @"";
    [manager controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:search]];
    Check(table.numberOfRows == 6,"clearing search restores saved collapsed groups");
    search.stringValue = @"rEsEaRcH";
    [manager controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:search]];
    Check(table.numberOfRows == 3,"group-name search is case insensitive and shows its documents");
    Check([manager.viewState[@"groupQuery"] isEqual:@"rEsEaRcH"],"search is exposed for YAML persistence");
    [manager updateGroups:fixtureGroups state:@{@"expandedGroups":@[@"group-1"],@"groupScroll":@100}];
    [host.contentView layoutSubtreeIfNeeded];
    Check(fabs(scroll.contentView.bounds.origin.y-MIN(100,MAX(0,NSHeight(table.frame)-NSHeight(scroll.contentView.bounds))))<1,
        "saved list scroll restores after layout without blank overscroll");
    search.stringValue = @"Research";
    [manager controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:search]];
    [host makeFirstResponder:search];
    NSTextView* editor = (id)search.currentEditor; [editor setSelectedRange:NSMakeRange(2,3)];
    [manager updateGroups:fixtureGroups state:manager.viewState];
    Check(NSEqualRanges(editor.selectedRange,NSMakeRange(2,3)),"unchanged background refresh preserves field-editor selection");
    [host makeFirstResponder:nil];
    [manager updateGroups:fixtureGroups state:@{@"expandedGroups":@[@"group-1"]}];
    [host.contentView layoutSubtreeIfNeeded];
    if (hiddenActive) [host makeFirstResponder:search];
    if (variant == 2) { search.stringValue = @"No such document"; [manager controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:search]]; }
    [table layoutSubtreeIfNeeded];
    NSView* visibleResearch = table.numberOfRows > 1 ? [table viewAtColumn:0 row:1 makeIfNecessary:YES] : nil;
    NSButton* eye = Button(visibleResearch,hiddenActive ? @"Show Research in tab bar" : @"Hide Research from tab bar");
    if (eye) {
        NSRect eyeBounds = [eye convertRect:eye.bounds toView:table];
        Check(NSWidth(eye.bounds) >= 26 && NSHeight(eye.bounds) >= 26,"visibility retains its full click target");
        Check(NSMinX(eyeBounds) >= 0 && NSMaxX(eyeBounds) <= NSWidth(table.bounds),"visibility target never clips at narrow width");
    }
    if (output.length) {
        NSBitmapImageRep* bitmap = [host.contentView bitmapImageRepForCachingDisplayInRect:host.contentView.bounds];
        [host.contentView cacheDisplayInRect:host.contentView.bounds toBitmapImageRep:bitmap];
        Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:output atomically:YES],"integrated native PNG written");
    }
    Check(!host.visible,"group management tests never show app window");
}
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        NSString* evidence = NSProcessInfo.processInfo.environment[@"SPDF_GROUP_MANAGEMENT_EVIDENCE_DIR"];
        if (evidence.length) [NSFileManager.defaultManager createDirectoryAtPath:evidence withIntermediateDirectories:YES attributes:nil error:nil];
        Render(176,296,NO,3,evidence ? [evidence stringByAppendingPathComponent:@"groups-minimum.png"] : nil);
        Render(220,296,NO,3,evidence ? [evidence stringByAppendingPathComponent:@"groups-220-minimum.png"] : nil);
        Render(240,640,YES,3,evidence ? [evidence stringByAppendingPathComponent:@"groups-default-dark.png"] : nil);
        Render(176,640,NO,4,evidence ? [evidence stringByAppendingPathComponent:@"groups-minimum-hidden-active.png"] : nil);
        Render(220,640,NO,NO,evidence ? [evidence stringByAppendingPathComponent:@"groups-narrow.png"] : nil);
        Render(280,640,YES,NO,evidence ? [evidence stringByAppendingPathComponent:@"groups-dark.png"] : nil);
        Render(220,340,NO,NO,evidence ? [evidence stringByAppendingPathComponent:@"groups-short.png"] : nil);
        Render(220,640,NO,YES,evidence ? [evidence stringByAppendingPathComponent:@"groups-hidden-active-focus.png"] : nil);
        Render(220,640,NO,2,evidence ? [evidence stringByAppendingPathComponent:@"groups-no-matches.png"] : nil);
        Render(220,340,NO,3,evidence ? [evidence stringByAppendingPathComponent:@"groups-pdf-short.png"] : nil);
        SPDFGroupManagementController* empty = [SPDFGroupManagementController new];
        [empty updateGroups:@[] state:@{}];
        NSTextField* message = [empty valueForKey:@"empty"];
        Check(!message.hidden && [message.stringValue containsString:@"Open a document"],"initial empty workspace shows guidance");
        if (!failures) puts("SPDFMacGroupManagementTests passed");
    }
    return failures ? 1 : 0;
}
