#import <AppKit/AppKit.h>

#import "../SPDFMacMarkdownLanguagePicker.h"
#import "../markdown/SPDFMarkdownLanguage.h"

#include <assert.h>
#include <stdio.h>

int main(void) {
    @autoreleasepool {
        (void)NSApplication.sharedApplication;
        SPDFMacMarkdownLanguagePickerController* picker = [SPDFMacMarkdownLanguagePickerController new];
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

        NSWindow* parent = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 360)
                                                       styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered defer:NO];
        __block NSString* chosen = nil;
        [picker presentForWindow:parent completion:^(SPDFMarkdownLanguage* language) {
          chosen = language.identifier;
        }];
        [picker updateQuery:@"swift"];
        assert([picker handleCommandSelector:@selector(insertNewline:)]);
        assert([chosen isEqualToString:@"swift"]);
        puts("SPDFMacMarkdownLanguagePickerTests passed");
    }
    return 0;
}
