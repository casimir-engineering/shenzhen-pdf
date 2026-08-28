#import <AppKit/AppKit.h>

#import "../SPDFMacMarkdownLanguagePicker.h"
#import "../markdown/SPDFMarkdownLanguage.h"

#include <assert.h>
#include <stdio.h>

int main(void) {
    @autoreleasepool {
        (void)NSApplication.sharedApplication;
        SPDFMacMarkdownLanguagePickerController* picker = [SPDFMacMarkdownLanguagePickerController new];
        assert(picker.searchField != nil);
        assert(picker.tableView != nil);
        assert(picker.visibleLanguages.count == 5);
        [picker updateQuery:@"py"];
        assert(picker.visibleLanguages.count == 1);
        assert([picker.visibleLanguages.firstObject.identifier isEqualToString:@"python"]);
        [picker updateQuery:@""];
        assert([picker handleCommandSelector:@selector(moveDown:)]);
        assert(picker.selectedIndex == 1);
        assert([picker handleCommandSelector:@selector(moveUp:)]);
        assert(picker.selectedIndex == 0);
        assert([picker handleCommandSelector:@selector(moveToEndOfDocument:)]);
        assert(picker.selectedIndex == 4);

        // Present -> filter -> Return accepts with the filtered language. The
        // anchor view is windowless, so the popover machinery stays headless
        // while the armed completion is driven through the action methods.
        NSView* anchorView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 240)];
        __block NSUInteger acceptCount = 0;
        __block NSString* chosen = nil;
        [picker presentFromView:anchorView
                     anchorRect:NSMakeRect(200, 20, 80, 20)
                     completion:^(SPDFMarkdownLanguage* language) {
                       acceptCount++;
                       chosen = language.identifier;
                     }];
        assert(picker.visibleLanguages.count == 5); // presenting resets the query
        [picker updateQuery:@"swift"];
        assert(picker.visibleLanguages.count == 1);
        assert([picker handleCommandSelector:@selector(insertNewline:)]);
        assert(acceptCount == 1);
        assert([chosen isEqualToString:@"swift"]);
        // A stale Return after the completion resolved must not re-fire it.
        assert([picker handleCommandSelector:@selector(insertNewline:)]);
        assert(acceptCount == 1);

        // Present -> Esc dismisses with nil, exactly once.
        __block NSUInteger dismissCount = 0;
        __block BOOL dismissedWithNil = NO;
        [picker presentFromView:anchorView
                     anchorRect:NSMakeRect(200, 20, 80, 20)
                     completion:^(SPDFMarkdownLanguage* language) {
                       dismissCount++;
                       dismissedWithNil = language == nil;
                     }];
        assert([picker handleCommandSelector:@selector(cancelOperation:)]);
        assert(dismissCount == 1);
        assert(dismissedWithNil);
        assert([picker handleCommandSelector:@selector(cancelOperation:)]);
        assert(dismissCount == 1);

        // Re-presenting while a completion is still pending resolves the old
        // presentation with nil before arming the new one.
        __block NSUInteger firstCount = 0;
        __block BOOL firstWasNil = NO;
        [picker presentFromView:anchorView
                     anchorRect:NSMakeRect(200, 20, 80, 20)
                     completion:^(SPDFMarkdownLanguage* language) {
                       firstCount++;
                       firstWasNil = language == nil;
                     }];
        __block NSString* second = nil;
        [picker presentFromView:anchorView
                     anchorRect:NSMakeRect(200, 20, 80, 20)
                     completion:^(SPDFMarkdownLanguage* language) {
                       second = language.identifier;
                     }];
        assert(firstCount == 1);
        assert(firstWasNil);
        [picker updateQuery:@"python"];
        assert([picker handleCommandSelector:@selector(insertNewline:)]);
        assert([second isEqualToString:@"python"]);
        assert(firstCount == 1);
        puts("SPDFMacMarkdownLanguagePickerTests passed");
    }
    return 0;
}
