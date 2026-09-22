#import "SPDFMacTabStripViewPrivate.h"

@implementation SPDFTabStripView (Menus)
- (void)showOverflowMenuWithEvent:(NSEvent*)event {
    NSArray<NSNumber*>* hiddenIndexes = [self hiddenTabIndexes];
    if (!hiddenIndexes.count || !event) return;

    [self dismissHoverPanel];

    NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Hidden Tabs"];
    for (NSNumber* indexNumber in hiddenIndexes) {
        NSInteger index = indexNumber.integerValue;
        NSString* title = [self titleForTabAtIndex:index];
        if (!title.length) title = @"Untitled";

        NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(overflowTabMenuItemSelected:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = indexNumber;
        item.state = index == self.selectedIndex ? NSControlStateValueOn : NSControlStateValueOff;
        spdf_set_menu_item_system_symbol(item, @"doc.text");
        [menu addItem:item];
    }

    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
}

- (void)overflowTabMenuItemSelected:(NSMenuItem*)sender {
    NSNumber* indexNumber = [sender.representedObject isKindOfClass:NSNumber.class] ? sender.representedObject : nil;
    if (!indexNumber) return;
    [self.reader selectTabAtIndex:indexNumber.integerValue];
}

- (void)tabContextShowInFolder:(NSMenuItem*)sender {
    NSNumber* indexNumber = [sender.representedObject isKindOfClass:NSNumber.class] ? sender.representedObject : nil;
    if (!indexNumber) return;
    [self.reader showTabInFolderAtIndex:indexNumber.integerValue];
}

- (void)tabContextCopyFile:(NSMenuItem*)sender {
    NSNumber* indexNumber = [sender.representedObject isKindOfClass:NSNumber.class] ? sender.representedObject : nil;
    if (!indexNumber) return;
    [self.reader copyTabFileToPasteboardAtIndex:indexNumber.integerValue];
}

- (void)tabContextCopyPath:(NSMenuItem*)sender {
    NSNumber* indexNumber = [sender.representedObject isKindOfClass:NSNumber.class] ? sender.representedObject : nil;
    if (!indexNumber) return;
    [self.reader copyTabPathToPasteboardAtIndex:indexNumber.integerValue];
}

- (void)tabContextCopyTitle:(NSMenuItem*)sender {
    NSNumber* indexNumber = [sender.representedObject isKindOfClass:NSNumber.class] ? sender.representedObject : nil;
    if (!indexNumber) return;
    [self.reader copyTabTitleToPasteboardAtIndex:indexNumber.integerValue];
}

- (void)rightMouseDown:(NSEvent*)event {
    if ([self handleGroupRightMouseDown:event]) return;
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger tabIndex = [self tabIndexAtPoint:point];
    if (tabIndex < 0) {
        [self dismissHoverPanel];
        [super rightMouseDown:event];
        return;
    }

    [self dismissHoverPanel];
    NSNumber* indexNumber = @(tabIndex);
    NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Tab"];
    NSMenuItem* group = [menu addItemWithTitle:@"Add to New Group" action:@selector(tabContextNewGroup:)
                               keyEquivalent:@""];
    group.target = self;
    group.representedObject = indexNumber;
    NSString* tabPath = self.tabs[(NSUInteger)tabIndex].path;
    if ([@[@"md", @"markdown"] containsObject:tabPath.pathExtension.lowercaseString]) {
        NSMenuItem* editor = [menu addItemWithTitle:@"Open in Editor" action:NSSelectorFromString(@"openMarkdownInEditor:")
                                     keyEquivalent:@""];
        editor.target = self.reader;
        editor.representedObject = tabPath;
    }
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem* showInFolder = [menu addItemWithTitle:@"Show in Folder"
                                               action:@selector(tabContextShowInFolder:)
                                        keyEquivalent:@""];
    showInFolder.target = self;
    showInFolder.representedObject = indexNumber;
    NSMenuItem* copy =
        [menu addItemWithTitle:@"Copy Document" action:@selector(tabContextCopyFile:) keyEquivalent:@""];
    copy.target = self;
    copy.representedObject = indexNumber;
    NSMenuItem* copyTitle = [menu addItemWithTitle:@"Copy Title"
                                            action:@selector(tabContextCopyTitle:)
                                     keyEquivalent:@""];
    copyTitle.target = self;
    copyTitle.representedObject = indexNumber;
    NSMenuItem* copyPath = [menu addItemWithTitle:@"Copy Path" action:@selector(tabContextCopyPath:) keyEquivalent:@""];
    copyPath.target = self;
    copyPath.representedObject = indexNumber;
    spdf_set_menu_item_system_symbol(showInFolder, @"folder");
    spdf_set_menu_item_system_symbol(copy, @"doc.on.doc");
    spdf_set_menu_item_system_symbol(copyTitle, @"character.cursor.ibeam");
    spdf_set_menu_item_system_symbol(copyPath, @"doc.text");
    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
}

@end
