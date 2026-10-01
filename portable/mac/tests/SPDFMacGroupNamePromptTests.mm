#import "SPDFMacTabGroupNamePrompt.h"
static void Check(BOOL value, NSString* reason) { if (!value) { NSLog(@"FAIL %@",reason); exit(1); } }
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    for (NSNumber* creating in @[@YES,@NO]) {
        __block NSString* accepted=nil;
        NSViewController* content=SPDFGroupNamePromptContent(@"Purple",creating.boolValue,^(NSString* name) { accepted=name; });
        NSTextField* field=nil; NSButton* confirm=nil;
        for (NSView* child in content.view.subviews) {
            if ([child.identifier isEqual:@"GroupNameField"]) field=(id)child;
            if ([child isKindOfClass:NSButton.class] && [((NSButton*)child).keyEquivalent isEqual:@"\r"]) confirm=(id)child;
        }
        Check([field.stringValue isEqual:@"Purple"],@"suggested name is editable text");
        NSWindow* window=[[NSWindow alloc] initWithContentRect:content.view.bounds styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        window.contentView=content.view; [window makeFirstResponder:field]; [field selectText:nil];
        NSTextView* editor=(id)window.firstResponder;
        Check([editor isKindOfClass:NSTextView.class] && NSEqualRanges(editor.selectedRange,NSMakeRange(0,6)),@"whole name selected for replacement");
        [confirm performClick:nil]; Check([accepted isEqual:@"Purple"],@"Return action accepts default");
        field.stringValue=@"References"; [confirm performClick:nil]; Check([accepted isEqual:@"References"],@"edited name accepted");
        Check(!window.visible,@"prompt verification stays offscreen");
    }
    puts("SPDFMacGroupNamePromptTests passed");
} }
