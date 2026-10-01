#import "SPDFMacTabAccessibility.h"

#import "SPDFMacTabStripViewPrivate.h"

typedef NS_ENUM(NSInteger, SPDFTabAccessibilityKind) {
    SPDFTabAccessibilityKindTab,
    SPDFTabAccessibilityKindGroup,
    SPDFTabAccessibilityKindOverflow,
    SPDFTabAccessibilityKindNewTab,
};

@interface SPDFMacTabAccessibilityElement : NSAccessibilityElement
@property(nonatomic, weak) SPDFTabStripView* strip;
@property(nonatomic) SPDFTabAccessibilityKind kind;
@property(nonatomic) NSInteger tabIndex;
@property(nonatomic, strong) SPDFTabGroup* group;
@end

@implementation SPDFMacTabAccessibilityElement

// NSAccessibilityElement defaults this synthesized property to NO. VoiceOver
// then announces an otherwise actionable virtual tab/button as "disabled" and
// will not invoke its press action.
- (BOOL)isAccessibilityEnabled { return YES; }

- (BOOL)accessibilityPerformPress {
    SPDFTabStripView* strip = self.strip;
    if (!strip) return NO;
    switch (self.kind) {
        case SPDFTabAccessibilityKindTab:
            if (self.tabIndex < 0 || self.tabIndex >= (NSInteger)strip.tabs.count) return NO;
            [strip.reader selectTabAtIndex:self.tabIndex];
            return YES;
        case SPDFTabAccessibilityKindGroup:
            if (!self.group) return NO;
            [strip.groupReader toggleTabGroup:self.group];
            return YES;
        case SPDFTabAccessibilityKindOverflow:
            [strip showOverflowMenuForAccessibility];
            return YES;
        case SPDFTabAccessibilityKindNewTab:
            [strip.reader newTabRequested:strip];
            return YES;
    }
}

- (BOOL)closeAccessibleTab {
    SPDFTabStripView* strip = self.strip;
    if (!strip || self.kind != SPDFTabAccessibilityKindTab || self.tabIndex < 0 ||
        self.tabIndex >= (NSInteger)strip.tabs.count)
        return NO;
    [strip.reader closeTabAtIndex:self.tabIndex];
    return YES;
}

- (BOOL)showAccessibleMenu {
    SPDFTabStripView* strip = self.strip;
    if (!strip) return NO;
    if (self.kind == SPDFTabAccessibilityKindTab) {
        [strip showContextMenuForTabAtIndex:self.tabIndex]; return YES;
    }
    if (self.kind == SPDFTabAccessibilityKindGroup && self.group) {
        [strip showContextMenuForGroup:self.group]; return YES;
    }
    return NO;
}

@end

static SPDFMacTabAccessibilityElement* Element(SPDFTabStripView* strip, SPDFTabAccessibilityKind kind,
                                                NSAccessibilityRole role, NSString* label, NSRect frame) {
    SPDFMacTabAccessibilityElement* element = [[SPDFMacTabAccessibilityElement alloc] init];
    element.strip = strip;
    element.kind = kind;
    element.accessibilityRole = role;
    element.accessibilityLabel = label;
    element.accessibilityParent = strip;
    element.accessibilityFrameInParentSpace = frame;
    return element;
}

NSArray<NSAccessibilityElement*>* SPDFMacTabAccessibilityChildren(SPDFTabStripView* strip) {
    if (!strip) return @[];
    NSMutableArray<NSAccessibilityElement*>* children = [NSMutableArray array];
    if ([strip hasTabGroups]) {
        for (id layout in [strip groupLayouts]) {
            SPDFTabGroup* group = [layout valueForKey:@"group"];
            NSRect frame = [[layout valueForKey:@"header"] rectValue];
            if (!group || NSIsEmptyRect(frame)) continue;
            SPDFMacTabAccessibilityElement* element =
                Element(strip, SPDFTabAccessibilityKindGroup, NSAccessibilityDisclosureTriangleRole,
                        group.displayName, frame);
            element.group = group;
            element.accessibilityValue = @(group.collapsed ? 0 : 1);
            element.accessibilityHelp = [NSString stringWithFormat:
                @"%@ group, %@. Press to %@. Use the context menu to rename, change its color, ungroup, or close it.",
                group.displayName, group.collapsed ? @"collapsed" : @"expanded",
                group.collapsed ? @"expand" : @"collapse"];
            __weak SPDFMacTabAccessibilityElement* weakElement = element;
            element.accessibilityCustomActions = @[
                [[NSAccessibilityCustomAction alloc] initWithName:@"Show Group Menu" handler:^BOOL {
                  return [weakElement showAccessibleMenu];
                }]
            ];
            [children addObject:element];
        }
    }

    NSArray<NSNumber*>* hidden = [strip hiddenTabIndexes];
    NSRect overflowFrame = [strip overflowRect];
    for (NSInteger index = 0; index < (NSInteger)strip.tabs.count; ++index) {
        SPDFDocumentTab* tab = strip.tabs[(NSUInteger)index];
        if (tab.group.hidden) continue;
        NSRect frame = [strip rectForTabAtIndex:index];
        BOOL hiddenInOverflow = NSIsEmptyRect(frame) || [hidden containsObject:@(index)];
        if (hiddenInOverflow) frame = overflowFrame;
        NSString* title = [strip fullTitleForTabAtIndex:index];
        SPDFMacTabAccessibilityElement* element =
            Element(strip, SPDFTabAccessibilityKindTab, NSAccessibilityRadioButtonRole,
                    title.length ? title : @"Untitled", frame);
        element.tabIndex = index;
        element.accessibilitySelected = index == strip.selectedIndex;
        NSString* group = tab.group ? [NSString stringWithFormat:@" %@ group.", tab.group.displayName] : @"";
        element.accessibilityHelp = [NSString stringWithFormat:@"%@%@ Press to open this tab. Cmd-Left and Cmd-Right move between tabs; Cmd-W closes; Cmd-D returns to the previously active tab.%@",
            index == strip.selectedIndex ? @"Selected." : @"Not selected.", group,
            hiddenInOverflow ? @" This tab is in the overflow menu." : @""];
        if (tab.unsavedPastedImage) element.accessibilityHelp =
            [@"Unsaved pasted image. Use Save As to save an image or PDF. " stringByAppendingString:element.accessibilityHelp];
        __weak SPDFMacTabAccessibilityElement* weakElement = element;
        element.accessibilityCustomActions = @[
            [[NSAccessibilityCustomAction alloc] initWithName:@"Close Tab" handler:^BOOL {
              return [weakElement closeAccessibleTab];
            }],
            [[NSAccessibilityCustomAction alloc] initWithName:@"Show Tab Menu" handler:^BOOL {
              return [weakElement showAccessibleMenu];
            }]
        ];
        [children addObject:element];
    }

    if (!NSIsEmptyRect(overflowFrame)) {
        SPDFMacTabAccessibilityElement* overflow =
            Element(strip, SPDFTabAccessibilityKindOverflow, NSAccessibilityPopUpButtonRole,
                    @"All Groups", overflowFrame);
        overflow.accessibilityHelp = @"Lists all groups, including hidden groups, and their documents.";
        [children addObject:overflow];
    }
    SPDFMacTabAccessibilityElement* add =
        Element(strip, SPDFTabAccessibilityKindNewTab, NSAccessibilityButtonRole, @"Open Document", [strip plusRect]);
    add.accessibilityHelp = @"Opens a document in a new tab.";
    [children addObject:add];
    return children;
}
