#import "SPDFMacTabStripViewPrivate.h"
#import "SPDFMacTabGroupNamePrompt.h"

@implementation SPDFTabStripView (GroupInteraction)
- (id<SPDFTabGroupReader>)groupReader { return (id<SPDFTabGroupReader>)self.reader; }
- (void)tabContextNewGroup:(NSMenuItem*)sender {
    NSInteger index = [sender.representedObject integerValue];
    [self createNamedGroupForTabAtIndex:index withTabAtIndex:-1 color:nil
        beforeTargetGroup:[self newGroupGoesBeforeTargetAtIndex:index]];
}
- (BOOL)newGroupGoesBeforeTargetAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.tabs.count) return NO;
    SPDFTabGroup* parent = self.tabs[(NSUInteger)index].group;
    NSRect visible = NSZeroRect, target = [self rectForTabAtIndex:index];
    NSInteger first = -1, last = -1;
    for (NSUInteger i=0;i<self.tabs.count;i++) if (self.tabs[i].group == parent) {
        if (first < 0) first = i;
        last = i;
        NSRect rect = [self rectForTabAtIndex:i];
        if (!NSIsEmptyRect(rect)) visible = NSIsEmptyRect(visible) ? rect : NSUnionRect(visible,rect);
    }
    // Visible coordinates matter when most General tabs are in overflow.
    if (!NSIsEmptyRect(target) && !NSIsEmptyRect(visible)) return NSMidX(target) < NSMidX(visible);
    return first >= 0 && index-first < (last-first+1)/2;
}
- (NSMenu*)moveToGroupMenuForTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.tabs.count || ![self hasTabGroups]) return nil;
    NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Move to Group"];
    SPDFDocumentTab* tab = self.tabs[(NSUInteger)index];
    NSMutableSet<NSString*>* seen = [NSMutableSet set];
    for (SPDFDocumentTab* candidate in self.tabs) {
        SPDFTabGroup* group = candidate.group;
        if (!group.identifier.length || [seen containsObject:group.identifier]) continue;
        [seen addObject:group.identifier];
        NSMenuItem* item = [menu addItemWithTitle:group.displayName
                                           action:@selector(tabContextMoveToGroup:)
                                    keyEquivalent:@""];
        item.target = self;
        item.representedObject = @{ @"index" : @(index), @"group" : group };
        item.image = spdf_tab_group_swatch_image(group.colorName);
        item.state = [tab.group.identifier isEqualToString:group.identifier]
                         ? NSControlStateValueOn : NSControlStateValueOff;
        item.toolTip = [NSString stringWithFormat:@"Move %@ to the %@ group", tab.title ?: @"this tab",
                                                   group.displayName];
    }
    return menu;
}
- (void)tabContextMoveToGroup:(NSMenuItem*)sender {
    NSDictionary* payload = [sender.representedObject isKindOfClass:NSDictionary.class]
                                ? sender.representedObject : nil;
    NSNumber* indexNumber = [payload[@"index"] isKindOfClass:NSNumber.class] ? payload[@"index"] : nil;
    SPDFTabGroup* group = [payload[@"group"] isKindOfClass:SPDFTabGroup.class] ? payload[@"group"] : nil;
    NSInteger index = indexNumber.integerValue;
    if (!indexNumber || !group || index < 0 || index >= (NSInteger)self.tabs.count) return;
    SPDFDocumentTab* tab = self.tabs[(NSUInteger)index];
    if ([tab.group.identifier isEqualToString:group.identifier]) return;
    NSArray* members = spdf_tab_group_members(self.tabs, group);
    NSUInteger last = [self.tabs indexOfObjectIdenticalTo:members.lastObject];
    NSInteger destination = last == NSNotFound ? (NSInteger)self.tabs.count : (NSInteger)last + 1;
    [self.groupReader moveTabAtIndex:index toGroup:group atIndex:destination];
}
- (void)createNamedGroupForTabAtIndex:(NSInteger)index withTabAtIndex:(NSInteger)other color:(NSString*)color beforeTargetGroup:(BOOL)before {
    if (index < 0 || index >= (NSInteger)self.tabs.count) return;
    SPDFDocumentTab* tab = self.tabs[(NSUInteger)index]; SPDFTabGroup* previous = tab.group;
    [self.groupReader createGroupForTabAtIndex:index withTabAtIndex:other color:color beforeTargetGroup:before];
    SPDFTabGroup* created = tab.group;
    if (!created || created == previous) return;
    // Allow the drag/menu tracking session to finish before presenting the sheet.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (spdf_tab_group_members(self.tabs,created).count) [self promptForGroup:created creating:YES];
    });
}
- (void)promptForGroup:(SPDFTabGroup*)group creating:(BOOL)creating {
    if (!group || !self.window) return;
    NSRect rect = NSZeroRect;
    for (id layout in self.groupLayouts) if ([layout valueForKey:@"group"] == group) {
        rect = [[layout valueForKey:@"header"] rectValue]; break;
    }
    __weak SPDFTabStripView* weakSelf=self;
    SPDFPresentGroupNamePrompt(self,rect,group.displayName,creating,^(NSString* name) {
        [weakSelf.groupReader renameTabGroup:group name:name];
    });
}
- (void)renameGroup:(SPDFTabGroup*)group { [self promptForGroup:group creating:NO]; }
- (void)groupRenameMenu:(NSMenuItem*)sender { [self renameGroup:sender.representedObject]; }
- (void)groupColorMenu:(NSMenuItem*)sender {
    [self.groupReader recolorTabGroup:sender.representedObject color:sender.title];
}
- (void)groupHideMenu:(NSMenuItem*)sender {
    SPDFTabGroup* group=sender.representedObject;
    [self.groupReader setTabGroup:group hidden:!group.hidden];
}
- (void)groupToggleMenu:(NSMenuItem*)sender { [self.groupReader toggleTabGroup:sender.representedObject]; }
- (void)groupUngroupMenu:(NSMenuItem*)sender { [self.groupReader ungroupTabs:sender.representedObject]; }
- (void)groupCloseMenu:(NSMenuItem*)sender { [self.groupReader closeTabGroup:sender.representedObject]; }
- (NSMenu*)contextMenuForGroup:(SPDFTabGroup*)group {
    if (!group) return nil;
    NSMenu* menu = [[NSMenu alloc] initWithTitle:group.displayName];
    {
        NSMenuItem* rename = [menu addItemWithTitle:@"Rename Group…" action:@selector(groupRenameMenu:) keyEquivalent:@""];
        rename.target = self;
        rename.representedObject = group;
    }
    NSMenuItem* hide=[menu addItemWithTitle:group.hidden ? @"Show Group" : @"Hide Group"
        action:@selector(groupHideMenu:) keyEquivalent:@""];
    hide.target=self; hide.representedObject=group;
    hide.image=[NSImage imageWithSystemSymbolName:group.hidden ? @"eye" : @"eye.slash" accessibilityDescription:nil];
    if (!group.general && !group.collectionBackups) {
        // Colors sit directly below Rename, as requested. Text and checkmarks
        // make the palette usable without relying on color discrimination.
        for (NSString* color in spdf_tab_group_colors()) {
            NSMenuItem* item = [menu addItemWithTitle:color action:@selector(groupColorMenu:) keyEquivalent:@""];
            item.target = self;
            item.representedObject = group;
            item.state = [group.colorName isEqualToString:color] ? NSControlStateValueOn : NSControlStateValueOff;
            item.image = spdf_tab_group_swatch_image(color);
        }
        [menu addItem:NSMenuItem.separatorItem];
    }
    NSMenuItem* toggle = [menu addItemWithTitle:group.collapsed ? @"Expand Group" : @"Collapse Group"
        action:@selector(groupToggleMenu:) keyEquivalent:@""];
    toggle.target = self;
    toggle.representedObject = group;
    if (!group.general) {
        NSMenuItem* ungroup = [menu addItemWithTitle:@"Ungroup Tabs" action:@selector(groupUngroupMenu:) keyEquivalent:@""];
        ungroup.target = self;
        ungroup.representedObject = group;
    }
    NSMenuItem* close = [menu addItemWithTitle:@"Close Group" action:@selector(groupCloseMenu:) keyEquivalent:@""];
    close.target = self;
    close.representedObject = group;
    return menu;
}
- (void)showContextMenuForGroup:(SPDFTabGroup*)group {
    NSMenu* menu = [self contextMenuForGroup:group]; if (!menu) return;
    [self dismissHoverPanel];
    NSRect rect = NSZeroRect;
    for (id layout in [self groupLayouts]) if ([layout valueForKey:@"group"] == group) {
        rect = [[layout valueForKey:@"header"] rectValue]; break;
    }
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(NSMinX(rect), NSMinY(rect)) inView:self];
}
- (BOOL)handleGroupRightMouseDown:(NSEvent*)event {
    SPDFTabGroup* group = [self groupAtPoint:[self convertPoint:event.locationInWindow fromView:nil] headerOnly:YES];
    if (!group) return NO;
    NSMenu* menu = [self contextMenuForGroup:group];
    [self dismissHoverPanel];
    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
    return YES;
}
- (BOOL)handleGroupMouseDown:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    for (id layout in [self groupLayouts])
        if (NSPointInRect(point,[[layout valueForKey:@"overflowFrame"] rectValue])) {
            [self showGroupDocuments:[layout valueForKey:@"group"] event:event];
            return YES;
        }
    SPDFTabGroup* group = [self groupAtPoint:point headerOnly:YES];
    _pressedGroup = group;
    if (!group) return NO;
    _pressedGroupAction=nil; _pressedGroupActionKind=0;
    for (id layout in [self groupLayouts]) if ([layout valueForKey:@"group"]==group) {
        NSRect header=[[layout valueForKey:@"header"] rectValue];
        // Hover-only controls never steal the first click on an unseen name.
        if (_hasLastHoverPoint && NSPointInRect(_lastHoverPoint,header)) {
            for (NSNumber* hide in @[@NO,@YES]) if (NSPointInRect(point,[self groupActionRect:header hide:hide.boolValue])) {
                _pressedGroupAction=group; _pressedGroupActionKind=hide.boolValue ? 2 : 1;
            }
        }
    }
    [self suppressWindowMovementForTabGesture];
    _dragStartPoint = point;
    [self dismissHoverPanel];
    return YES;
}
- (BOOL)handleGroupMouseDragged:(NSEvent*)event {
    if (!_pressedGroup) return NO;
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (_pressedGroupAction) return YES;
    if (hypot(point.x - _dragStartPoint.x, point.y - _dragStartPoint.y) >= 4 && !_dragSessionGroup)
        [self startGroupDragSessionWithEvent:event];
    return YES;
}
- (BOOL)handleGroupMouseUp:(NSEvent*)event {
    SPDFTabGroup* group = _pressedGroup;
    _pressedGroup = nil;
    if (!group) return NO;
    [self restoreWindowMovementForTabGesture];
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if ([self groupAtPoint:point headerOnly:YES] != group) return YES;
    if (_pressedGroupAction==group) {
        NSInteger action=_pressedGroupActionKind; _pressedGroupAction=nil; _pressedGroupActionKind=0;
        for (id layout in [self groupLayouts]) if ([layout valueForKey:@"group"]==group) {
            NSRect header=[[layout valueForKey:@"header"] rectValue];
            if (NSPointInRect(point,[self groupActionRect:header hide:action==2])) {
                if (action==2) [self.groupReader setTabGroup:group hidden:YES]; else [self renameGroup:group];
            }
        }
        return YES;
    }
    // The name and disclosure share one activation target. Rename is an
    // explicit context-menu action, never a side effect of opening a group.
    [self.groupReader toggleTabGroup:group];
    return YES;
}
- (void)updateGroupDropForPoint:(NSPoint)point sourceIndex:(NSInteger)source {
    _groupDropGroup = [self groupAtPoint:point headerOnly:YES];
    NSInteger target = [self tabIndexAtPoint:point];
    SPDFTabGroup* sourceGroup = source >= 0 && source < (NSInteger)self.tabs.count
                                   ? self.tabs[(NSUInteger)source].group : nil;
    // Sliding within an existing group is always a reorder, even while paused
    // over a sibling or the group's own handle. A join would append instead.
    if (sourceGroup && _groupDropGroup == sourceGroup) _groupDropGroup = nil;
    if (target == source || (sourceGroup && target >= 0 && self.tabs[(NSUInteger)target].group == sourceGroup))
        target = -1;
    if (target >= 0) {
        NSRect rect = [self rectForTabAtIndex:target];
        // The center creates a pair; either edge remains a reorder target.
        if (point.x < NSMinX(rect) + NSWidth(rect) * 0.28 ||
            point.x > NSMaxX(rect) - NSWidth(rect) * 0.28) target = -1;
    }
    if (target != _groupHoverIndex) {
        _groupHoverIndex = target;
        _groupHoverBegan = NSDate.timeIntervalSinceReferenceDate;
        if (target >= 0 && _draggingTab && !_detachedTabDrag) {
            NSInteger expected = target;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.36 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (self->_draggingTab && !self->_detachedTabDrag && self->_groupHoverIndex == expected)
                    [self updateGroupDropForPoint:point sourceIndex:source];
            });
        }
    }
    _groupDropTabIndex = -1;
    if (target >= 0 && NSDate.timeIntervalSinceReferenceDate - _groupHoverBegan >= 0.35) {
        SPDFTabGroup* group = self.tabs[(NSUInteger)target].group;
        if (group && !group.general) _groupDropGroup = group;
        else {
            _groupDropTabIndex = target;
            if (!_groupPreviewColor) _groupPreviewColor = spdf_tab_group_unused_color(self.tabs);
        }
    }
    if (_groupDropGroup || _groupDropTabIndex >= 0) _dropIndicatorSlot = -1;
    [self setNeedsDisplay:YES];
}
- (BOOL)performGroupDropWithTab:(SPDFDocumentTab*)tab sourceIndex:(NSInteger)source atPoint:(NSPoint)point {
    if (!_groupDropGroup && _groupDropTabIndex < 0) return NO;
    SPDFTabGroup* destination = _groupDropGroup;
    SPDFDocumentTab* target = _groupDropTabIndex >= 0 ? self.tabs[(NSUInteger)_groupDropTabIndex] : nil;
    NSString* color = _groupPreviewColor;
    BOOL before = target ? [self newGroupGoesBeforeTargetAtIndex:_groupDropTabIndex] : NO;
    if (source < 0) {
        // Seed destination membership before inserting: normalization must not
        // briefly create an unrelated source group in the destination window.
        tab.group = destination ?: target.group;
        [self.reader insertDraggedTab:tab atIndex:[self dropIndexForPoint:point]];
        for (NSUInteger i = 0; i < self.tabs.count; ++i)
            if ([self.tabs[i].path isEqualToString:tab.path]) { source = i; break; }
    }
    if (source < 0) return NO;
    if (destination) {
        NSArray* members = spdf_tab_group_members(self.tabs, destination);
        NSUInteger last = [self.tabs indexOfObjectIdenticalTo:members.lastObject];
        [self.groupReader moveTabAtIndex:source toGroup:destination atIndex:last == NSNotFound ? self.tabs.count : last + 1];
    } else {
        NSUInteger other = [self.tabs indexOfObjectIdenticalTo:target];
        if (other != NSNotFound)
            [self createNamedGroupForTabAtIndex:source withTabAtIndex:other color:color beforeTargetGroup:before];
    }
    return YES;
}
@end
