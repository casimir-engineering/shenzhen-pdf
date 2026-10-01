#import "SPDFMacTabGroupNamePrompt.h"
static void Check(BOOL value, NSString* reason) { if (!value) { NSLog(@"FAIL %@",reason); exit(1); } }
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    for (NSNumber* creating in @[@YES,@NO]) {
        NSAlert* alert=SPDFTabGroupNamePrompt(@"Purple",creating.boolValue);
        NSTextField* field=(id)alert.accessoryView;
        Check([field.stringValue isEqual:@"Purple"],@"default name is real editable text, not a placeholder");
        [alert layout]; SPDFSelectGroupPromptName(alert);
        NSTextView* editor=(id)alert.window.firstResponder;
        Check([editor isKindOfClass:NSTextView.class] && NSEqualRanges(editor.selectedRange,NSMakeRange(0,6)),@"whole name is selected for replacement");
        Check([alert.buttons.firstObject.keyEquivalent isEqual:@"\r"],@"Return accepts the displayed name");
        Check(!alert.window.visible,@"prompt verification stays offscreen");
    }
    puts("SPDFMacGroupNamePromptTests passed");
} }
