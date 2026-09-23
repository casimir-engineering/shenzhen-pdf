#import <Cocoa/Cocoa.h>
#import "SPDFMacCollectionWindowPrivate.h"
#import "SPDFMacCollectionHistory.h"
#import "SPDFMacCollectionCompareViews.h"

// The comparison controller stays private in the app; the test exercises the
// real constructor without calling the facade that orders its window onscreen.
@interface SPDFCollectionCompareController : NSWindowController
- (instancetype)initWithOldLabel:(NSString*)oldLabel newLabel:(NSString*)newLabel;
@end

static int failures;
static void Expect(NSString* label, BOOL value) {
    if (!value) { fprintf(stderr,"FAIL: %s\n",label.UTF8String); failures++; }
}
static void Layout(NSWindow* window, NSSize size) {
    [window setContentSize:size];
    [window.contentView layoutSubtreeIfNeeded];
    Expect(@"headless layout never shows a window",!window.visible);
}
static NSView* Label(NSView* view, NSString* string) {
    if ([view isKindOfClass:NSTextField.class] && [[(NSTextField*)view stringValue] isEqual:string]) return view;
    for (NSView* child in view.subviews) { NSView* found = Label(child,string); if (found) return found; }
    return nil;
}
static NSView* Descendant(NSView* view, Class cls) {
    if ([view isKindOfClass:cls]) return view;
    for (NSView* child in view.subviews) {
        NSView* found = Descendant(child,cls); if (found) return found;
    }
    return nil;
}
static BOOL CaptionHasInk(NSCollectionViewItem* item) {
    [item.view layoutSubtreeIfNeeded];
    NSBitmapImageRep* bitmap = [item.view bitmapImageRepForCachingDisplayInRect:item.view.bounds];
    [item.view cacheDisplayInRect:item.view.bounds toBitmapImageRep:bitmap];
    NSRect caption = NSInsetRect(item.textField.frame,4,4);
    CGFloat scaleX = bitmap.pixelsWide / item.view.bounds.size.width;
    CGFloat scaleY = bitmap.pixelsHigh / item.view.bounds.size.height;
    CGFloat darkest = 1, lightest = 0;
    for (NSInteger y = floor(NSMinY(caption) * scaleY); y < ceil(NSMaxY(caption) * scaleY); y += 2) {
        for (NSInteger x = floor(NSMinX(caption) * scaleX); x < ceil(NSMaxX(caption) * scaleX); x += 2) {
            NSColor* color = [[bitmap colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            CGFloat brightness = .2126 * color.redComponent + .7152 * color.greenComponent +
                .0722 * color.blueComponent;
            darkest = MIN(darkest,brightness); lightest = MAX(lightest,brightness);
        }
    }
    return lightest - darkest > .3;
}
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        NSURL* root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
        SPDFMacCollectionStore* store = [[SPDFMacCollectionStore alloc] initWithRootURL:root];
        SPDFMacCollectionWindow* manager = nil;
        @try {
            manager = [[SPDFMacCollectionWindow alloc] initWithStore:store open:^(NSString* path, BOOL archived) {
                (void)path; (void)archived;
            }];
            Layout(manager.window,NSMakeSize(1100,690));
            Expect(@"document pane uses the available window width",NSWidth(manager.documentsPane.frame) > 850);
            Expect(@"manager list has a readable viewport",manager.listScroll.frame.size.width > 300 &&
                manager.listScroll.frame.size.height > 350);
            Expect(@"Collection navigation has only Documents and Settings",manager.documentsButton && manager.settingsButton &&
                ![manager.viewPicker.itemTitles containsObject:@"Storage"] && manager.documentsPane && manager.settingsPane);
            Expect(@"unlimited is the default storage setting",manager.limitField.doubleValue == 0);
            Expect(@"location is displayed before loading documents",[manager.locationField.stringValue isEqual:root.path]);
            [manager showDestination:@"Settings"];
            Layout(manager.window,NSMakeSize(940,560));
            Expect(@"Settings replaces the document pane",manager.documentsPane.hidden && !manager.settingsPane.hidden);
            Expect(@"storage controls belong exclusively to Settings",[manager.limitField isDescendantOf:manager.settingsPane] &&
                ![manager.limitField isDescendantOf:manager.documentsPane]);
            Expect(@"settings controls fit the minimum window",NSContainsRect(manager.settingsPane.bounds,
                [manager.limitField convertRect:manager.limitField.bounds toView:manager.settingsPane]));
            [manager showDestination:@"Documents"]; Layout(manager.window,NSMakeSize(1100,690));
            NSView* optionsHeading = Label(manager.window.contentView,@"Document options");
            Expect(@"document options start visible at the top",optionsHeading &&
                NSIntersectsRect(optionsHeading.bounds,optionsHeading.visibleRect));
            NSString* evidence = NSProcessInfo.processInfo.environment[@"SPDF_COLLECTION_WINDOW_EVIDENCE"];
            if (evidence.length) {
                NSBitmapImageRep* bitmap = [manager.window.contentView bitmapImageRepForCachingDisplayInRect:manager.window.contentView.bounds];
                [manager.window.contentView cacheDisplayInRect:manager.window.contentView.bounds toBitmapImageRep:bitmap];
                [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:evidence atomically:YES];
            }
            [manager.layoutPicker selectItemAtIndex:1]; [manager reloadGrid];
            Layout(manager.window,NSMakeSize(940,560));
            Expect(@"thumbnail layout has a real visible collection view",!manager.gridScroll.hidden &&
                manager.listScroll.hidden && manager.gridScroll.frame.size.width > 300);
            NSDictionary* fixtureDocument = @{@"id": @"fixture-document", @"title": @"Bridge Notes.pdf",
                @"path": @"/tmp/Bridge Notes.pdf", @"versions": @[]};
            NSDictionary* fixtureVersion = @{@"id": @"fixture-version", @"capturedAt": @1727092800,
                @"encrypted": @YES};
            manager.rows = @[@{@"document": fixtureDocument, @"version": fixtureVersion}];
            [manager.table reloadData]; [manager reloadGrid];
            [manager.window.contentView layoutSubtreeIfNeeded]; [manager.grid layoutSubtreeIfNeeded];
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
            [manager.window.contentView layoutSubtreeIfNeeded]; [manager.grid layoutSubtreeIfNeeded];
            NSIndexPath* fixturePath = [NSIndexPath indexPathForItem:0 inSection:0];
            NSCollectionViewItem* fixtureItem = [manager.grid itemAtIndexPath:fixturePath];
            Expect(@"thumbnail fixture creates its native item",fixtureItem != nil);
            Expect(@"thumbnail caption contains filename and capture date",
                fixtureItem.textField.stringValue.length > 20 &&
                    [fixtureItem.textField.stringValue containsString:@"Bridge Notes.pdf"]);
            Expect(@"thumbnail caption occupies visible item space",
                fixtureItem.textField.superview == fixtureItem.view &&
                    NSIntersectsRect(fixtureItem.textField.frame,fixtureItem.view.bounds));
            Expect(@"thumbnail caption has stable layout and rendered pixels",
                !fixtureItem.textField.hasAmbiguousLayout && fixtureItem.textField.frame.size.height == 50 &&
                    CaptionHasInk(fixtureItem));
            Expect(@"thumbnail item is a named accessibility element",fixtureItem.view.isAccessibilityElement &&
                [fixtureItem.view.accessibilityLabel containsString:@"Bridge Notes.pdf"] &&
                [fixtureItem.view.accessibilityLabel isEqual:fixtureItem.textField.stringValue]);
            Expect(@"thumbnail collection exposes its named item",
                [manager.grid.accessibilityChildren containsObject:fixtureItem.view]);
            Expect(@"thumbnail accessibility press selects the item",[fixtureItem.view accessibilityPerformPress] &&
                [manager.grid.selectionIndexPaths containsObject:fixturePath]);
            Expect(@"thumbnail accessibility press updates document actions",manager.table.selectedRow == 0 &&
                [manager.details.stringValue containsString:@"Bridge Notes.pdf"] &&
                    manager.selectionButtons[1].enabled);
            Expect(@"manager construction starts no capture or thumbnail work",manager.thumbnailQueue.operationCount == 0 &&
                ![NSFileManager.defaultManager fileExistsAtPath:root.path]);
            NSString* indexedPath = [root.path stringByAppendingString:@"-Field Notes.md"];
            [@"# Greenhouse log\nThe orchid bloomed overnight.\n" writeToFile:indexedPath atomically:YES
                encoding:NSUTF8StringEncoding error:nil];
            [store updateSettings:@{@"choice":@"enabled"} error:nil];
            NSDictionary* indexed = [store capturePath:indexedPath reason:@"Opened" error:nil];
            [manager.viewPicker selectItemAtIndex:1];
            [manager.viewPicker selectItemAtIndex:0]; manager.search.stringValue = @"orchid"; manager.rows = @[];
            [manager reload:nil];
            NSDate* filterDeadline = [NSDate dateWithTimeIntervalSinceNow:2];
            while (!manager.rows.count && filterDeadline.timeIntervalSinceNow > 0)
                [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:
                    [NSDate dateWithTimeIntervalSinceNow:.01]];
            Expect(@"manager content search includes an indexed document whose title does not match",
                indexed && manager.rows.count == 1 &&
                [manager.rows.firstObject[@"document"][@"id"] isEqual:indexed[@"id"]]);
            Expect(@"search uses list results even if thumbnail browsing was selected",!manager.listScroll.hidden && manager.gridScroll.hidden);
            NSDictionary* result = manager.rows.firstObject;
            Expect(@"native search retains exact text contexts and version identity",[result[@"matches"] count] > 0 && result[@"version"][@"id"]);
            NSView* resultCell = [manager resultCellForRow:0];
            NSImageView* thumbnail = (id)Descendant(resultCell,NSImageView.class);
            Expect(@"text results include a saved-page thumbnail",thumbnail != nil);
            NSArray* matches = result[@"matches"];
            Expect(@"context highlights are available",[matches.firstObject[@"ranges"] count] > 0);
            manager.search.stringValue = @"orchid";
            [manager showDestination:@"Settings"]; [manager showDestination:@"Documents"];
            Expect(@"settings navigation preserves query and document rows",[manager.search.stringValue isEqual:@"orchid"] && manager.rows.count == 1);
            [NSFileManager.defaultManager removeItemAtPath:indexedPath error:nil];
        } @catch (NSException* exception) {
            fprintf(stderr,"FAIL: manager constructor/layout raised %s\n",exception.description.UTF8String); failures++;
        }
        SPDFMacCollectionHistoryController* history = nil;
        NSWindow* historyHost = nil;
        @try {
            history = [[SPDFMacCollectionHistoryController alloc] initWithStore:store documentID:@"missing"
                open:^(NSString* path, BOOL archived) { (void)path; (void)archived; }];
            historyHost = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,280,620)
                styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
            historyHost.releasedWhenClosed = NO;
            historyHost.contentViewController = history;
            Layout(historyHost,NSMakeSize(280,620));
            NSScrollView* list = (id)Descendant(history.view,NSScrollView.class);
            Expect(@"history rows fit the sidebar",list.frame.size.width > 200 && list.frame.size.height > 80);
        } @catch (NSException* exception) {
            fprintf(stderr,"FAIL: history constructor/layout raised %s\n",exception.description.UTF8String); failures++;
        }
        SPDFCollectionCompareController* comparison = nil;
        @try {
            comparison = [[SPDFCollectionCompareController alloc] initWithOldLabel:@"Fixture · Old" newLabel:@"Fixture · New"];
            Layout(comparison.window,NSMakeSize(1200,820));
            SPDFCollectionComparePane* pane = (id)Descendant(comparison.window.contentView,SPDFCollectionComparePane.class);
            Expect(@"comparison reader has a useful viewport",pane.reader.frame.size.width > 400 &&
                pane.reader.frame.size.height > 400);
            Layout(comparison.window,NSMakeSize(980,520));
            Expect(@"comparison fits its minimum window",pane.reader.frame.size.width > 300 && pane.reader.frame.size.height > 250);
        } @catch (NSException* exception) {
            fprintf(stderr,"FAIL: comparison constructor/layout raised %s\n",exception.description.UTF8String); failures++;
        }
        [manager.window close]; [historyHost close]; [comparison.window close];
        NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:.15];
        while ([deadline timeIntervalSinceNow] > 0)
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
        [NSFileManager.defaultManager removeItemAtURL:root error:nil];
        if (!failures) puts("SPDFMacCollectionWindowTests passed");
    }
    return failures ? 1 : 0;
}
