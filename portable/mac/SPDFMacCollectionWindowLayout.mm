#import "SPDFMacCollectionWindowPrivate.h"

@interface SPDFCollectionOptionsStack : NSStackView
@end
@implementation SPDFCollectionOptionsStack
- (BOOL)isFlipped { return YES; }
@end
static NSTextField* Label(NSString* text, CGFloat size, NSFontWeight weight) {
    NSTextField* field = [NSTextField wrappingLabelWithString:text];
    field.font = [NSFont systemFontOfSize:size weight:weight]; return field;
}
static NSStackView* Stack(BOOL horizontal) {
    NSStackView* stack = [NSStackView stackViewWithViews:@[]];
    stack.orientation = horizontal ? NSUserInterfaceLayoutOrientationHorizontal : NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = horizontal ? NSLayoutAttributeCenterY : NSLayoutAttributeLeading;
    stack.distribution = NSStackViewDistributionFill;
    stack.spacing = 10; return stack;
}
static void Fill(NSView* child, NSView* parent) {
    child.translatesAutoresizingMaskIntoConstraints = NO; [parent addSubview:child];
    [NSLayoutConstraint activateConstraints:@[
        [child.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor],
        [child.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor],
        [child.topAnchor constraintEqualToAnchor:parent.topAnchor],
        [child.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor]]];
}
@implementation SPDFMacCollectionWindow (Layout)
- (void)buildManagerLayout {
    NSDictionary* preferences = self.store.settings;
    NSStackView* root = Stack(YES); root.alignment = NSLayoutAttributeTop;
    root.edgeInsets = NSEdgeInsetsMake(18,18,18,18); root.spacing = 18;
    Fill(root,self.window.contentView);
    NSStackView* sidebar = Stack(NO); [sidebar.widthAnchor constraintEqualToConstant:140].active = YES;
    [sidebar addArrangedSubview:Label(@"Collection",22,NSFontWeightBold)];
    [sidebar addArrangedSubview:Label(@"Local copies and history",11,NSFontWeightRegular)];
    self.documentsButton = [NSButton buttonWithTitle:@"Documents" target:self action:@selector(navigate:)];
    self.settingsButton = [NSButton buttonWithTitle:@"Settings" target:self action:@selector(navigate:)];
    for (NSButton* button in @[self.documentsButton,self.settingsButton]) {
        button.buttonType = NSButtonTypePushOnPushOff;
        [button.widthAnchor constraintEqualToConstant:140].active = YES;
        [sidebar addArrangedSubview:button];
    }
    [root addArrangedSubview:sidebar];
    self.contentHost = [NSView new]; [root addArrangedSubview:self.contentHost];
    [self.contentHost.heightAnchor constraintEqualToAnchor:root.heightAnchor constant:-36].active = YES;
    NSStackView* documents = Stack(YES); documents.alignment = NSLayoutAttributeTop;
    self.documentsPane = documents; Fill(documents,self.contentHost);
    NSStackView* center = Stack(NO); [documents addArrangedSubview:center];
    self.search = [NSSearchField new]; self.search.placeholderString = @"Search documents and saved text";
    self.search.stringValue = [preferences[@"managerQuery"] isKindOfClass:NSString.class] ? preferences[@"managerQuery"] : @"";
    self.search.target = self; self.search.action = @selector(reload:); self.search.sendsSearchStringImmediately = YES;
    [center addArrangedSubview:self.search]; [self.search.widthAnchor constraintEqualToAnchor:center.widthAnchor].active = YES;
    NSStackView* filters = Stack(YES); filters.spacing = 6;
    self.viewPicker = [NSPopUpButton new];
    [self.viewPicker addItemsWithTitles:@[@"All Documents",@"Versions",@"Originals Unavailable",@"Kept",@"Excluded"]];
    [self.viewPicker selectItemAtIndex:MIN(4,MAX(0,[preferences[@"managerView"] integerValue]))];
    self.layoutPicker = [NSPopUpButton new]; [self.layoutPicker addItemsWithTitles:@[@"List",@"Thumbnails"]];
    [self.layoutPicker selectItemAtIndex:MIN(1,MAX(0,[preferences[@"managerLayout"] integerValue]))];
    self.sortPicker = [NSPopUpButton new]; [self.sortPicker addItemsWithTitles:@[@"Newest first",@"Oldest first",@"Name"]];
    [self.sortPicker selectItemAtIndex:MIN(2,MAX(0,[preferences[@"managerSort"] integerValue]))];
    for (NSPopUpButton* picker in @[self.viewPicker,self.layoutPicker,self.sortPicker]) {
        picker.target = self; picker.action = @selector(reload:); [filters addArrangedSubview:picker];
    }
    [center addArrangedSubview:filters];
    NSStackView* scope = Stack(YES); self.scopePicker = [NSPopUpButton new];
    [self.scopePicker addItemsWithTitles:@[@"Latest saved copies",@"All saved versions"]];
    [self.scopePicker selectItemAtIndex:MIN(1,MAX(0,[preferences[@"managerSearchScope"] integerValue]))];
    self.scopePicker.target = self; self.scopePicker.action = @selector(reload:);
    [scope addArrangedSubview:self.scopePicker]; self.resultSummary = Label(@"",11,NSFontWeightRegular);
    [scope addArrangedSubview:self.resultSummary]; [center addArrangedSubview:scope];
    self.listScroll = [NSScrollView new]; self.listScroll.hasVerticalScroller = YES;
    self.listScroll.borderType = NSBezelBorder;
    self.table = [NSTableView new]; self.table.headerView = nil; self.table.rowHeight = 100;
    self.table.allowsMultipleSelection = YES; self.table.dataSource = self; self.table.delegate = self;
    self.table.target = self; self.table.doubleAction = @selector(preview:);
    NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"document"];
    column.width = 520; [self.table addTableColumn:column]; self.listScroll.documentView = self.table;
    NSView* results = [NSView new]; [center addArrangedSubview:results]; Fill(self.listScroll,results);
    [self installGridInView:results];
    [NSLayoutConstraint activateConstraints:@[
        [center.heightAnchor constraintEqualToAnchor:documents.heightAnchor],
        [results.widthAnchor constraintEqualToAnchor:center.widthAnchor],
        [results.bottomAnchor constraintEqualToAnchor:center.bottomAnchor]]];
    NSStackView* options = [SPDFCollectionOptionsStack stackViewWithViews:@[]];
    options.orientation = NSUserInterfaceLayoutOrientationVertical; options.alignment = NSLayoutAttributeLeading;
    options.spacing = 9; [options.widthAnchor constraintEqualToConstant:210].active = YES;
    [options addArrangedSubview:Label(@"Document options",16,NSFontWeightSemibold)];
    self.details = Label(@"Select a document or version.",12,NSFontWeightRegular);
    [self.details.widthAnchor constraintEqualToConstant:210].active = YES; [options addArrangedSubview:self.details];
    self.selectionButtons = [NSMutableArray array];
    NSArray* titles = @[@"Open Original",@"Preview Read-only Copy",@"History",@"Compare with Current",@"Compare with Previous",
        @"Locate Original…",@"Save a Copy…",@"Keep / Unkeep",@"Exclude / Include",@"Delete Selected Copies…"];
    NSArray* actions = @[@"openOriginal:",@"preview:",@"history:",@"compareCurrent:",@"comparePrevious:",@"locate:",
        @"exportCopy:",@"keep:",@"exclude:",@"deleteSelected:"];
    for (NSUInteger i=0;i<titles.count;i++) {
        NSButton* button = [NSButton buttonWithTitle:titles[i] target:self action:NSSelectorFromString(actions[i])];
        [options addArrangedSubview:button]; [self.selectionButtons addObject:button];
    }
    NSScrollView* optionsScroll = [NSScrollView new]; optionsScroll.hasVerticalScroller = YES;
    optionsScroll.drawsBackground = NO; options.frame = NSMakeRect(0,0,210,690); optionsScroll.documentView = options;
    [documents addArrangedSubview:optionsScroll];
    [optionsScroll.widthAnchor constraintEqualToConstant:224].active = YES;
    [optionsScroll.heightAnchor constraintEqualToAnchor:documents.heightAnchor].active = YES;
    [options.heightAnchor constraintGreaterThanOrEqualToConstant:650].active = YES;
    [self buildSettingsPane];
    NSString* destination = preferences[@"managerDestination"];
    [self showDestination:[destination isEqual:@"Settings"] ? @"Settings" : @"Documents"];
}
- (void)navigate:(id)sender {
    [self showDestination:sender == self.settingsButton ? @"Settings" : @"Documents"];
    [self persistManagerPreferences];
}
- (void)showDestination:(NSString*)destination {
    self.destination = destination;
    self.documentsPane.hidden = ![destination isEqual:@"Documents"];
    self.settingsPane.hidden = ![destination isEqual:@"Settings"];
    self.historyPane.hidden = ![destination isEqual:@"History"];
    self.documentsButton.state = [destination isEqual:@"Settings"] ? NSControlStateValueOff : NSControlStateValueOn;
    self.settingsButton.state = [destination isEqual:@"Settings"] ? NSControlStateValueOn : NSControlStateValueOff;
}
- (void)persistManagerPreferences {
    NSDictionary* preferences = @{@"managerView":@(self.viewPicker.indexOfSelectedItem),
        @"managerLayout":@(self.layoutPicker.indexOfSelectedItem),@"managerSort":@(self.sortPicker.indexOfSelectedItem),
        @"managerDestination":self.destination ?: @"Documents", @"managerQuery":self.search.stringValue,
        @"managerSearchScope":@(self.scopePicker.indexOfSelectedItem)};
    dispatch_async(self.preferenceQueue, ^{
        NSError* error = nil; [self.store updateSettings:preferences error:&error];
        if (error) dispatch_async(dispatch_get_main_queue(),^{ [self showError:error]; });
    });
}
@end
