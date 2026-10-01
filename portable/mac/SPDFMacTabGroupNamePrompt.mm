#import "SPDFMacTabGroupNamePrompt.h"

NSAlert* SPDFTabGroupNamePrompt(NSString* defaultName, BOOL creating) {
    NSAlert* alert = [NSAlert new];
    alert.messageText = creating ? @"Name New Group" : @"Rename Group";
    alert.informativeText = creating ? @"Choose a name or keep the suggested color name." : @"Leave the name empty to use the color name.";
    [alert addButtonWithTitle:creating ? @"Done" : @"Rename"];
    [alert addButtonWithTitle:creating ? @"Keep Default" : @"Cancel"];
    NSTextField* field = [[NSTextField alloc] initWithFrame:NSMakeRect(0,0,260,24)];
    field.stringValue = defaultName ?: @"";
    field.accessibilityLabel = @"Group name";
    alert.accessoryView = field;
    alert.window.initialFirstResponder = field;
    return alert;
}
void SPDFSelectGroupPromptName(NSAlert* alert) {
    NSTextField* field = (NSTextField*)alert.accessoryView;
    [alert.window makeFirstResponder:field];
    [field selectText:nil];
}
