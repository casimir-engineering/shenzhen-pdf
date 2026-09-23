#import <Cocoa/Cocoa.h>
#import "SPDFMacSidebarModeControl.h"
static int failures;
static void Check(BOOL ok, const char* label) { if (!ok) { fprintf(stderr,"FAIL: %s\n",label); failures++; } }
@interface SidebarSurface : NSView
@end
@implementation SidebarSurface
- (void)drawRect:(NSRect)dirty { [NSColor.windowBackgroundColor setFill]; NSRectFill(dirty); }
@end
@interface SidebarFixture : NSObject <NSTableViewDataSource,NSTableViewDelegate>
@property NSUInteger changes;
@end
@implementation SidebarFixture
- (void)changed:(id)sender { (void)sender; self.changes++; }
- (NSInteger)numberOfRowsInTableView:(NSTableView*)table { (void)table; return 24; }
- (NSView*)tableView:(NSTableView*)table viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
    (void)table; (void)column;
    NSArray* names = @[@"Overview",@"Getting started",@"Working with documents",@"Organizing your workspace",@"Reading and annotations",@"Version history",@"Keyboard shortcuts",@"Reference"];
    NSTextField* label = [NSTextField labelWithString:names[row % names.count]];
    label.font = [NSFont systemFontOfSize:12]; label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}
@end
static void Exercise(CGFloat width, CGFloat height, BOOL dark, NSInteger focus, NSString* evidence) {
    NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,width,height)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    window.appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    window.contentView = [[SidebarSurface alloc] initWithFrame:NSMakeRect(0,0,width,height)];
    NSView* surface = window.contentView;
    SPDFSidebarNavigationControl* navigation = [SPDFSidebarNavigationControl new];
    spdf_sidebar_mode_control_configure_navigation(navigation,YES,YES);
    navigation.spdf_selectedSidebarMode = SPDFSidebarModeChapters;
    navigation.translatesAutoresizingMaskIntoConstraints = NO;
    NSSearchField* filter = [NSSearchField new]; filter.placeholderString = @"Filter Chapters";
    filter.translatesAutoresizingMaskIntoConstraints = NO;
    NSTableView* table = [NSTableView new]; table.headerView = nil; table.rowHeight = 29;
    [table addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"chapter"]];
    SidebarFixture* fixture = [SidebarFixture new]; table.dataSource = fixture; table.delegate = fixture;
    navigation.target = fixture; navigation.action = @selector(changed:);
    NSScrollView* scroll = [NSScrollView new]; scroll.documentView = table; scroll.hasVerticalScroller = YES;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [surface addSubview:navigation]; [surface addSubview:filter]; [surface addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [navigation.topAnchor constraintEqualToAnchor:surface.topAnchor constant:8],
        [navigation.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor constant:8],
        [navigation.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-8],
        [filter.topAnchor constraintEqualToAnchor:navigation.bottomAnchor constant:10],
        [filter.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor constant:8],
        [filter.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-8],
        [scroll.topAnchor constraintEqualToAnchor:filter.bottomAnchor constant:8],
        [scroll.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:surface.bottomAnchor]]];
    [surface layoutSubtreeIfNeeded];
    Check(navigation.segmentCount == 5,"all PDF workspace modes present");
    Check(navigation.accessibilityChildren.count == 5,"navigation is a vertical row per mode");
    CGFloat bottom = 0;
    for (NSButton* row in navigation.accessibilityChildren) {
        Check(NSHeight(row.frame) == 28 && NSMinY(row.frame) >= bottom,"rows have full click targets and never overlap");
        Check(NSWidth(row.frame) == width-16,"navigation uses available panel width");
        Check(row.accessibilityLabel.length > 0,"all icons have accessible text names");
        bottom = NSMaxY(row.frame);
    }
    Check(NSHeight(scroll.frame) > 100,"short sidebar retains a useful scrollable content viewport");
    NSButton* groups = navigation.accessibilityChildren.lastObject; [groups performClick:nil];
    Check(navigation.spdf_selectedSidebarMode == SPDFSidebarModeGroups && fixture.changes == 1,"click selects Groups and dispatches action once");
    spdf_sidebar_mode_control_configure_history(navigation,NO,NO,NO);
    Check(navigation.segmentCount == 3 && navigation.spdf_selectedSidebarMode == SPDFSidebarModeGroups,
        "Markdown omits Comments, Search and Groups remain stable without document history");
    navigation.spdf_selectedSidebarMode = SPDFSidebarModeSearch;
    [navigation spdf_setEnabled:NO forSidebarMode:SPDFSidebarModeChapters];
    NSEvent* down = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
        windowNumber:window.windowNumber context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:125];
    [navigation keyDown:down];
    Check(navigation.spdf_selectedSidebarMode == SPDFSidebarModeGroups,"arrow navigation moves to next enabled mode");
    navigation.spdf_selectedSidebarMode = SPDFSidebarModeSearch;
    NSEvent* up = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
        windowNumber:window.windowNumber context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:126];
    [navigation keyDown:up];
    Check(navigation.spdf_selectedSidebarMode == SPDFSidebarModeSearch,"keyboard skips disabled Chapters");
    NSButton* searchRow = navigation.accessibilityChildren[1];
    [window makeFirstResponder:searchRow]; [searchRow keyDown:down];
    Check(window.firstResponder == navigation.accessibilityChildren.lastObject &&
        navigation.spdf_selectedSidebarMode == SPDFSidebarModeGroups,"arrow follows focused row to new selected mode");
    NSEvent* space = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
        windowNumber:window.windowNumber context:nil characters:@" " charactersIgnoringModifiers:@" " isARepeat:NO keyCode:49];
    NSUInteger changes = fixture.changes;
    [(NSView*)window.firstResponder keyDown:space];
    Check(navigation.spdf_selectedSidebarMode == SPDFSidebarModeGroups && fixture.changes == changes+1,
        "Space after arrows activates the new selection instead of stale focused row");
    Check([[(NSButton*)navigation.accessibilityChildren.lastObject accessibilityValue] boolValue],
        "accessibility announces selected radio state");
    spdf_sidebar_mode_control_configure_navigation(navigation,YES,YES);
    Check(window.firstResponder == navigation,"dynamic navigation rebuild preserves keyboard focus");
    [navigation spdf_setEnabled:YES forSidebarMode:SPDFSidebarModeChapters];
    navigation.spdf_selectedSidebarMode = SPDFSidebarModeChapters;
    [surface layoutSubtreeIfNeeded];
    [window makeFirstResponder:nil];
    if (focus == 1) {
        [window makeFirstResponder:navigation];
        Check(window.firstResponder == navigation,"navigation accepts keyboard focus");
        NSButton* hover = navigation.accessibilityChildren.lastObject;
        [hover mouseEntered:[NSEvent mouseEventWithType:NSEventTypeMouseMoved location:NSZeroPoint modifierFlags:0 timestamp:0
            windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:0 pressure:0]];
    }
    if (focus == 2) { filter.stringValue = @"document"; [window makeFirstResponder:filter]; }
    Check(!window.visible,"navigation test never shows a window");
    if (evidence.length) {
        NSBitmapImageRep* bitmap = [surface bitmapImageRepForCachingDisplayInRect:surface.bounds];
        [surface cacheDisplayInRect:surface.bounds toBitmapImageRep:bitmap];
        Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:evidence atomically:YES],"native mockup PNG saved");
    }
}
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        NSString* directory = NSProcessInfo.processInfo.environment[@"SPDF_SIDEBAR_EVIDENCE_DIR"];
        if (directory.length) [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
        Exercise(220,620,NO,NO,directory ? [directory stringByAppendingPathComponent:@"sidebar-light-narrow.png"] : nil);
        Exercise(240,620,YES,NO,directory ? [directory stringByAppendingPathComponent:@"sidebar-dark.png"] : nil);
        Exercise(220,340,NO,NO,directory ? [directory stringByAppendingPathComponent:@"sidebar-short.png"] : nil);
        Exercise(240,620,NO,YES,directory ? [directory stringByAppendingPathComponent:@"sidebar-focus-hover.png"] : nil);
        Exercise(240,620,NO,2,directory ? [directory stringByAppendingPathComponent:@"sidebar-search-focus.png"] : nil);
        if (!failures) puts("SPDFMacSidebarNavigationTests passed");
    }
    return failures ? 1 : 0;
}
