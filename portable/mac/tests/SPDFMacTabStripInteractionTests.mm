#import <Cocoa/Cocoa.h>

#import "SPDFMacTabStripGeometry.h"
#import "SPDFMacTabStripView.h"
#import "SPDFMacWindowChrome.h"

@interface SPDFFakeTab : NSObject
@property(nonatomic, copy) NSString* path;
@property(nonatomic, copy) NSString* title;
@property(nonatomic) BOOL readOnly;
@property(nonatomic) BOOL missingFile;
@end

@implementation SPDFFakeTab
@end

@interface SPDFFakeTabReader : NSObject
@property(nonatomic) NSInteger newTabCount;
@property(nonatomic) NSInteger selectedTabIndex;
@property(nonatomic) NSInteger movedTabCount;
@end

@implementation SPDFFakeTabReader

- (void)newTabRequested:(id)sender {
    (void)sender;
    self.newTabCount += 1;
}

- (void)selectTabAtIndex:(NSInteger)index {
    self.selectedTabIndex = index;
}

- (void)moveTabFromIndex:(NSInteger)sourceIndex toIndex:(NSInteger)targetIndex {
    (void)sourceIndex;
    (void)targetIndex;
    self.movedTabCount += 1;
}

@end

@interface SPDFChromeSpyWindow : NSWindow <SPDFWindowChromeHandling>
@property(nonatomic) NSInteger chromeEventCount;
@property(nonatomic) SPDFWindowChromeAction lastChromeAction;
@end

@implementation SPDFChromeSpyWindow

- (void)handleChromeMouseDown:(NSEvent*)event {
    self.chromeEventCount += 1;
    self.lastChromeAction = spdf_window_chrome_action(event.clickCount, NO, NO, NO);
}

@end

// The tab-strip implementation references these application helpers from
// paths unrelated to this focused interaction test. Small deterministic stubs
// keep the test linked to the production view without pulling in the app.
NSString* spdf_display_label_without_extension(NSString* label) {
    return label ?: @"";
}

NSString* spdf_display_name_for_path(NSString* path) {
    return path.lastPathComponent ?: @"";
}

NSArray<NSString*>* spdf_disambiguated_display_names_for_paths(NSArray<NSString*>* paths) {
    return paths;
}

NSDictionary* spdf_dictionary_from_tab(SPDFDocumentTab* tab, NSInteger sourceWindowNumber) {
    (void)tab;
    (void)sourceWindowNumber;
    return @{};
}

SPDFDocumentTab* spdf_tab_from_dictionary(NSDictionary* item) {
    (void)item;
    return nil;
}

void spdf_set_menu_item_system_symbol(NSMenuItem* item, NSString* symbolName) {
    (void)item;
    (void)symbolName;
}

static void expect_true(NSString* label, BOOL value) {
    if (value) return;
    NSLog(@"FAIL %@", label);
    exit(1);
}

static void expect_integer(NSString* label, NSInteger actual, NSInteger expected) {
    if (actual == expected) return;
    NSLog(@"FAIL %@: got %ld, expected %ld", label, (long)actual, (long)expected);
    exit(1);
}

static NSEvent* mouse_event(SPDFChromeSpyWindow* window, NSEventType type, NSPoint point, NSInteger clickCount) {
    return [NSEvent mouseEventWithType:type
                              location:point
                         modifierFlags:0
                             timestamp:NSProcessInfo.processInfo.systemUptime
                          windowNumber:window.windowNumber
                               context:nil
                           eventNumber:1
                            clickCount:clickCount
                              pressure:1.0];
}

static void dispatch(SPDFChromeSpyWindow* window, NSEventType type, NSPoint point, NSInteger clickCount) {
    [window sendEvent:mouse_event(window, type, point, clickCount)];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        SPDFChromeSpyWindow* window = [[SPDFChromeSpyWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 42)
                                                                             styleMask:NSWindowStyleMaskBorderless
                                                                               backing:NSBackingStoreBuffered
                                                                                 defer:NO];
        SPDFTabStripView* strip = [[SPDFTabStripView alloc] initWithFrame:window.contentView.bounds];
        strip.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        SPDFFakeTabReader* reader = [[SPDFFakeTabReader alloc] init];
        reader.selectedTabIndex = -1;
        SPDFFakeTab* tab = [[SPDFFakeTab alloc] init];
        tab.path = @"/tmp/alpha.pdf";
        tab.title = @"Alpha";
        SPDFFakeTab* secondTab = [[SPDFFakeTab alloc] init];
        secondTab.path = @"/tmp/beta.pdf";
        secondTab.title = @"Beta";
        strip.reader = (id)reader;
        strip.tabs = (id) @[ tab, secondTab ];
        strip.selectedIndex = 0;
        [window.contentView addSubview:strip];
        [window orderFront:nil];
        [window makeKeyWindow];
        [window displayIfNeeded];

        NSPoint tabPoint = NSMakePoint(180, 21);
        NSPoint emptyPoint = NSMakePoint(820, 21);
        NSPoint plusPoint = NSMakePoint(874, 21);
        expect_true(@"tab is an interactive hit region", [strip containsTabOrControlAtPoint:tabPoint]);
        expect_true(@"plus is an interactive hit region", [strip containsTabOrControlAtPoint:plusPoint]);
        expect_true(@"background is outside interactive hit regions", ![strip containsTabOrControlAtPoint:emptyPoint]);

        dispatch(window, NSEventTypeLeftMouseDown, tabPoint, 1);
        dispatch(window, NSEventTypeLeftMouseUp, tabPoint, 1);
        expect_integer(@"tab press selects the tab", reader.selectedTabIndex, 0);

        dispatch(window, NSEventTypeLeftMouseDown, tabPoint, 1);
        dispatch(window, NSEventTypeLeftMouseDragged, NSMakePoint(650, 21), 1);
        dispatch(window, NSEventTypeLeftMouseUp, NSMakePoint(650, 21), 1);
        expect_integer(@"tab remains reorderable", reader.movedTabCount, 1);
        expect_integer(@"tab gesture never enters window chrome", window.chromeEventCount, 0);

        dispatch(window, NSEventTypeLeftMouseDown, plusPoint, 1);
        expect_integer(@"plus remains clickable", reader.newTabCount, 1);
        expect_integer(@"plus never enters window chrome", window.chromeEventCount, 0);

        dispatch(window, NSEventTypeLeftMouseDown, emptyPoint, 1);
        expect_integer(@"empty background forwards one event", window.chromeEventCount, 1);
        expect_integer(@"single background press starts native drag", window.lastChromeAction,
                       SPDFWindowChromeActionDrag);

        dispatch(window, NSEventTypeLeftMouseDown, emptyPoint, 2);
        expect_integer(@"double background press forwards once", window.chromeEventCount, 2);
        expect_integer(@"double background press uses native zoom", window.lastChromeAction,
                       SPDFWindowChromeActionZoom);
    }
    return 0;
}
