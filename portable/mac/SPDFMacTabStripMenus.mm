#import "SPDFMacTabStripViewPrivate.h"
#import "SPDFMacCollectionPathPolicy.h"

@protocol SPDFTabCollectionMenuProviding <NSObject>
- (void)addCollectionItemsToTabMenu:(NSMenu*)menu path:(NSString*)path;
@end

@implementation SPDFTabStripView (Menus)
- (NSMenu*)overflowMenu {
    NSArray<NSNumber*>* hiddenIndexes = [self hiddenTabIndexes];
    if (!hiddenIndexes.count) return nil;

    NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Hidden Tabs"];
    SPDFTabGroup* previousGroup = nil;
    for (NSNumber* indexNumber in hiddenIndexes) {
        NSInteger index = indexNumber.integerValue;
        SPDFDocumentTab* tab = self.tabs[(NSUInteger)index];
        SPDFTabGroup* group = tab.group;
        if (group && group != previousGroup) {
            if (previousGroup) [menu addItem:NSMenuItem.separatorItem];
            NSMenuItem* heading = [menu addItemWithTitle:group.displayName action:nil keyEquivalent:@""];
            heading.enabled = NO;
            heading.image = spdf_tab_group_swatch_image(group.colorName);
            heading.toolTip = [NSString stringWithFormat:@"%@ group, %@", group.displayName,
                                                         group.collapsed ? @"collapsed" : @"expanded"];
            previousGroup = group;
        }
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

    return menu;
}

- (void)showOverflowMenuWithEvent:(NSEvent*)event {
    NSMenu* menu = [self overflowMenu];
    if (!menu || !event) return;
    [self dismissHoverPanel];
    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
}

- (void)showOverflowMenuForAccessibility {
    NSMenu* menu = [self overflowMenu];
    NSRect rect = [self overflowRect];
    if (!menu || NSIsEmptyRect(rect)) return;
    [self dismissHoverPanel];
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(NSMinX(rect), NSMinY(rect)) inView:self];
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

- (NSMenu*)contextMenuForTabAtIndex:(NSInteger)tabIndex {
    if (tabIndex < 0 || tabIndex >= (NSInteger)self.tabs.count) return nil;
    NSNumber* indexNumber = @(tabIndex);
    NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Tab"];
    NSMenuItem* group = [menu addItemWithTitle:@"Add to New Group" action:@selector(tabContextNewGroup:)
                               keyEquivalent:@""];
    group.target = self; group.representedObject = indexNumber;
    NSMenu* moveToGroup = [self moveToGroupMenuForTabAtIndex:tabIndex];
    if (moveToGroup.numberOfItems) {
        NSMenuItem* move = [[NSMenuItem alloc] initWithTitle:@"Move to Group" action:nil keyEquivalent:@""];
        move.submenu = moveToGroup; [menu addItem:move];
    }
    NSString* tabPath = self.tabs[(NSUInteger)tabIndex].path;
    if ([@[@"md", @"markdown"] containsObject:tabPath.pathExtension.lowercaseString]) {
        NSMenuItem* editor = [menu addItemWithTitle:@"Open in Editor" action:NSSelectorFromString(@"openMarkdownInEditor:")
                                     keyEquivalent:@""];
        editor.target = self.reader; editor.representedObject = tabPath;
        editor.enabled = !SPDFMacPathIsCollectionArchive(tabPath);
    }
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem* showInFolder = [menu addItemWithTitle:@"Show in Folder" action:@selector(tabContextShowInFolder:)
                                        keyEquivalent:@""];
    showInFolder.target = self; showInFolder.representedObject = indexNumber;
    NSMenuItem* copy = [menu addItemWithTitle:@"Copy Document" action:@selector(tabContextCopyFile:) keyEquivalent:@""];
    copy.target = self; copy.representedObject = indexNumber;
    NSMenuItem* copyTitle = [menu addItemWithTitle:@"Copy Title" action:@selector(tabContextCopyTitle:) keyEquivalent:@""];
    copyTitle.target = self; copyTitle.representedObject = indexNumber;
    NSMenuItem* copyPath = [menu addItemWithTitle:@"Copy Path" action:@selector(tabContextCopyPath:) keyEquivalent:@""];
    copyPath.target = self; copyPath.representedObject = indexNumber;
    if ([self.reader respondsToSelector:@selector(addCollectionItemsToTabMenu:path:)])
        [(id<SPDFTabCollectionMenuProviding>)self.reader addCollectionItemsToTabMenu:menu path:tabPath];
    spdf_set_menu_item_system_symbol(showInFolder, @"folder");
    spdf_set_menu_item_system_symbol(copy, @"doc.on.doc");
    spdf_set_menu_item_system_symbol(copyTitle, @"character.cursor.ibeam");
    spdf_set_menu_item_system_symbol(copyPath, @"doc.text");
    return menu;
}

- (void)showContextMenuForTabAtIndex:(NSInteger)index {
    NSMenu* menu = [self contextMenuForTabAtIndex:index];
    if (!menu) return;
    [self dismissHoverPanel];
    NSRect rect = [self rectForTabAtIndex:index];
    if (NSIsEmptyRect(rect)) rect = [self overflowRect];
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(NSMinX(rect), NSMinY(rect)) inView:self];
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
    NSMenu* menu = [self contextMenuForTabAtIndex:tabIndex];
    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
}

@end
