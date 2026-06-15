#import "SPDFMacDelegatePrivate.h"

@implementation ShenzhenMacDelegate (ShortcutHelp)

- (NSArray<NSDictionary*>*)shortcutHelpCatalog {
    return @[
        @{
            @"category" : @"Search",
            @"items" : @[
                @{@"title" : @"Start searching from the document", @"subtitle" : @"Type anywhere"},
                @{@"title" : @"Find in current document", @"keys" : @[ @"Cmd", @"F" ]},
                @{@"title" : @"Next search result", @"keys" : @[ @"Enter" ]},
                @{@"title" : @"Previous search result", @"keys" : @[ @"Shift", @"Enter" ]},
                @{@"title" : @"Find next", @"keys" : @[ @"Cmd", @"G" ]},
                @{@"title" : @"Find previous", @"keys" : @[ @"Cmd", @"Shift", @"G" ]}
            ]
        },
        @{
            @"category" : @"Favorites",
            @"items" : @[
                @{@"title" : @"Favorites and open-document command palette", @"keys" : @[ @"Cmd", @"K" ]},
                @{@"title" : @"Favorite current page", @"keys" : @[ @"Cmd", @"B" ]},
                @{@"title" : @"Favorite current document", @"keys" : @[ @"Cmd", @"Shift", @"B" ]}
            ]
        },
        @{
            @"category" : @"Pages and View",
            @"items" : @[
                @{@"title" : @"Previous or next page", @"keys" : @[ @"[", @"]" ]},
                @{@"title" : @"First or last page", @"keys" : @[ @"Home", @"End" ]},
                @{@"title" : @"Go to page", @"keys" : @[ @"Cmd", @"L" ]},
                @{
                    @"title" : @"Previous or next page (keeps zoom and position; scrolls when zoomed wider)",
                    @"keys" : @[ @"Left", @"Right" ]
                },
                @{@"title" : @"Always jump a page (keeps zoom and position)", @"keys" : @[ @"Cmd", @"Arrow" ]},
                @{@"title" : @"Jump a page", @"keys" : @[ @"Shift", @"Arrow" ]},
                @{@"title" : @"Scroll up or down", @"keys" : @[ @"Up", @"Down" ]},
                @{@"title" : @"Zoom in or out", @"keys" : @[ @"Cmd", @"+ / -" ]},
                @{@"title" : @"Fit page", @"keys" : @[ @"Cmd", @"1" ]},
                @{@"title" : @"Fit width", @"keys" : @[ @"Cmd", @"2" ]},
                @{@"title" : @"Fit height", @"keys" : @[ @"Cmd", @"3" ]},
                @{@"title" : @"Actual size", @"keys" : @[ @"Cmd", @"4" ]}
            ]
        },
        @{
            @"category" : @"Tabs and Tools",
            @"items" : @[
                @{@"title" : @"Reorder or detach tabs", @"subtitle" : @"Drag tabs"},
                @{@"title" : @"Reopen last closed document", @"keys" : @[ @"Cmd", @"Shift", @"T" ]},
                @{@"title" : @"Rotate page clockwise", @"keys" : @[ @"Cmd", @"R" ]},
                @{@"title" : @"Rotate page anticlockwise", @"keys" : @[ @"Cmd", @"Shift", @"R" ]},
                @{@"title" : @"Presentation mode", @"keys" : @[ @"F5", @"Cmd", @"Shift", @"F" ]},
                @{@"title" : @"Leave presentation mode", @"keys" : @[ @"Esc" ]}
            ]
        },
        @{
            @"category" : @"Panels",
            @"items" : @[
                @{@"title" : @"Show or hide chapters and comments", @"subtitle" : @"View menu or Side Panel toggle"},
                @{@"title" : @"Show or hide minimap", @"subtitle" : @"View menu or Map toggle"}
            ]
        }
    ];
}

- (void)refreshShortcutHelpRows {
    [_shortcutHelpRows removeAllObjects];
    NSString* query = _shortcutHelpSearchField.stringValue.lowercaseString ?: @"";
    for (NSDictionary* section in [self shortcutHelpCatalog]) {
        NSString* category = section[@"category"] ?: @"";
        NSMutableArray<NSDictionary*>* matchingItems = [NSMutableArray array];
        for (NSDictionary* item in section[@"items"]) {
            NSString* haystack =
                [NSString stringWithFormat:@"%@ %@ %@ %@", category, item[@"title"] ?: @"", item[@"subtitle"] ?: @"",
                                           [item[@"keys"] componentsJoinedByString:@" "]]
                    .lowercaseString;
            if (query.length == 0 || [haystack containsString:query]) [matchingItems addObject:item];
        }
        if (matchingItems.count == 0) continue;
        [_shortcutHelpRows addObject:@{@"kind" : @"header", @"title" : category}];
        for (NSDictionary* item in matchingItems) {
            NSMutableDictionary* row = [item mutableCopy];
            row[@"kind"] = @"shortcut";
            [_shortcutHelpRows addObject:row];
        }
    }
    if (_shortcutHelpRows.count == 0)
        [_shortcutHelpRows addObject:@{@"kind" : @"empty", @"title" : @"No shortcuts found"}];
    [_shortcutHelpTable reloadData];
}

- (NSView*)shortcutKeycapsViewForKeys:(NSArray<NSString*>*)keys {
    NSStackView* stack = [[NSStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = NSLayoutAttributeCenterY;
    stack.spacing = 5.0;
    for (NSString* key in keys ?: @[]) {
        NSTextField* keycap = [NSTextField labelWithString:key];
        keycap.translatesAutoresizingMaskIntoConstraints = NO;
        keycap.alignment = NSTextAlignmentCenter;
        keycap.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
        keycap.textColor = NSColor.labelColor;
        keycap.wantsLayer = YES;
        keycap.layer.cornerRadius = 9.0;
        keycap.layer.masksToBounds = YES;
        keycap.layer.backgroundColor = [NSColor.tertiaryLabelColor colorWithAlphaComponent:0.28].CGColor;
        [keycap.widthAnchor constraintGreaterThanOrEqualToConstant:26].active = YES;
        [keycap.heightAnchor constraintEqualToConstant:22].active = YES;
        [stack addArrangedSubview:keycap];
    }
    return stack;
}

- (void)showShortcutHelp:(id)sender {
    (void)sender;
    if (_shortcutHelpPanel && _shortcutHelpPanel.visible) {
        [_shortcutHelpPanel makeKeyAndOrderFront:nil];
        return;
    }

    NSRect frame = NSMakeRect(0, 0, 680, 620);
    if (!_shortcutHelpPanel) {
        _shortcutHelpPanel = [[SPDFShortcutHelpPanel alloc] initWithContentRect:frame
                                                                      styleMask:NSWindowStyleMaskBorderless
                                                                        backing:NSBackingStoreBuffered
                                                                          defer:NO];
        _shortcutHelpPanel.releasedWhenClosed = NO;
        _shortcutHelpPanel.floatingPanel = YES;
        _shortcutHelpPanel.hidesOnDeactivate = NO;
        _shortcutHelpPanel.hasShadow = YES;
        _shortcutHelpPanel.opaque = NO;
        _shortcutHelpPanel.backgroundColor = NSColor.clearColor;

        NSVisualEffectView* content = [[NSVisualEffectView alloc] initWithFrame:frame];
        content.translatesAutoresizingMaskIntoConstraints = NO;
        content.material = NSVisualEffectMaterialHUDWindow;
        content.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        content.state = NSVisualEffectStateActive;
        content.wantsLayer = YES;
        content.layer.cornerRadius = 14.0;
        content.layer.masksToBounds = YES;
        _shortcutHelpPanel.contentView = content;

        NSTextField* title = [NSTextField labelWithString:@"Keyboard shortcuts"];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.font = [NSFont systemFontOfSize:22 weight:NSFontWeightSemibold];
        title.textColor = NSColor.labelColor;
        [content addSubview:title];

        NSButton* closeButton = [NSButton buttonWithTitle:@"x" target:self action:@selector(closeShortcutHelp:)];
        closeButton.translatesAutoresizingMaskIntoConstraints = NO;
        closeButton.bezelStyle = NSBezelStyleRegularSquare;
        closeButton.bordered = NO;
        closeButton.font = [NSFont systemFontOfSize:20 weight:NSFontWeightLight];
        closeButton.contentTintColor = NSColor.secondaryLabelColor;
        [closeButton.widthAnchor constraintEqualToConstant:34].active = YES;
        [closeButton.heightAnchor constraintEqualToConstant:34].active = YES;
        [content addSubview:closeButton];

        _shortcutHelpSearchField = [[NSSearchField alloc] init];
        _shortcutHelpSearchField.translatesAutoresizingMaskIntoConstraints = NO;
        _shortcutHelpSearchField.placeholderString = @"Search shortcuts";
        _shortcutHelpSearchField.delegate = self;
        [content addSubview:_shortcutHelpSearchField];

        NSScrollView* scrollView = [[NSScrollView alloc] init];
        scrollView.translatesAutoresizingMaskIntoConstraints = NO;
        scrollView.hasVerticalScroller = YES;
        scrollView.borderType = NSNoBorder;
        scrollView.drawsBackground = NO;
        [content addSubview:scrollView];

        _shortcutHelpTable = [[NSTableView alloc] init];
        _shortcutHelpTable.headerView = nil;
        _shortcutHelpTable.backgroundColor = NSColor.clearColor;
        _shortcutHelpTable.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
        _shortcutHelpTable.dataSource = self;
        _shortcutHelpTable.delegate = self;
        NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"Shortcut"];
        column.resizingMask = NSTableColumnAutoresizingMask;
        [_shortcutHelpTable addTableColumn:column];
        scrollView.documentView = _shortcutHelpTable;

        _shortcutHelpDisableButton = [NSButton buttonWithTitle:@"Do not show again"
                                                        target:self
                                                        action:@selector(disableLaunchShortcutHelp:)];
        _shortcutHelpDisableButton.translatesAutoresizingMaskIntoConstraints = NO;
        _shortcutHelpDisableButton.bezelStyle = NSBezelStyleRounded;
        [content addSubview:_shortcutHelpDisableButton];

        NSTextField* hint = [NSTextField labelWithString:@"You can start typing in a document at any time to search."];
        hint.translatesAutoresizingMaskIntoConstraints = NO;
        hint.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
        hint.textColor = NSColor.secondaryLabelColor;
        [content addSubview:hint];

        [NSLayoutConstraint activateConstraints:@[
            [title.topAnchor constraintEqualToAnchor:content.topAnchor constant:22],
            [title.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:22],
            [closeButton.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
            [closeButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-18],
            [_shortcutHelpSearchField.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:22],
            [_shortcutHelpSearchField.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:18],
            [_shortcutHelpSearchField.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-18],
            [_shortcutHelpSearchField.heightAnchor constraintEqualToConstant:44],
            [scrollView.topAnchor constraintEqualToAnchor:_shortcutHelpSearchField.bottomAnchor constant:18],
            [scrollView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
            [scrollView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
            [scrollView.bottomAnchor constraintEqualToAnchor:hint.topAnchor constant:-12],
            [hint.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:22],
            [hint.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20],
            [_shortcutHelpDisableButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-22],
            [_shortcutHelpDisableButton.centerYAnchor constraintEqualToAnchor:hint.centerYAnchor]
        ]];
    }

    _shortcutHelpDisableButton.hidden = !_showShortcutHelpOnLaunch;
    [self refreshShortcutHelpRows];
    [_shortcutHelpPanel center];
    [_shortcutHelpPanel makeKeyAndOrderFront:nil];
    [_shortcutHelpPanel makeFirstResponder:_shortcutHelpSearchField];
}

- (void)closeShortcutHelp:(id)sender {
    (void)sender;
    [_shortcutHelpPanel orderOut:nil];
}

- (void)disableLaunchShortcutHelp:(id)sender {
    (void)sender;
    _showShortcutHelpOnLaunch = NO;
    _shortcutHelpDisableButton.hidden = YES;
    [self savePersistentState];
    [_shortcutHelpPanel orderOut:nil];
}

@end
