#import "SPDFMacCollectionWindowPrivate.h"
#import "SPDFMacCollectionStyle.h"

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
    self.window.backgroundColor = SPDFCollectionColor(@"window");
    NSView* root = SPDFCollectionSurface(@"window"); Fill(root,self.window.contentView);
    NSView* sidebar = SPDFCollectionSurface(@"sidebar"); sidebar.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:sidebar];
    [NSLayoutConstraint activateConstraints:@[[sidebar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [sidebar.topAnchor constraintEqualToAnchor:root.topAnchor],[sidebar.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [sidebar.widthAnchor constraintEqualToConstant:154]]];
    NSStackView* navigation = Stack(NO); navigation.spacing = 4; navigation.translatesAutoresizingMaskIntoConstraints = NO;
    [sidebar addSubview:navigation];
    [NSLayoutConstraint activateConstraints:@[[navigation.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:9],
        [navigation.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-9],
        [navigation.topAnchor constraintEqualToAnchor:sidebar.topAnchor constant:17]]];
    NSTextField* caption = SPDFCollectionText(@"Collection",12,NSFontWeightSemibold,YES);
    [navigation addArrangedSubview:caption]; [navigation setCustomSpacing:10 afterView:caption];
    self.documentsButton = SPDFCollectionButton(@"Documents",self,@selector(navigate:),@"nav");
    self.settingsButton = SPDFCollectionButton(@"Settings",self,@selector(navigate:),@"nav");
    self.documentsButton.image = [NSImage imageWithSystemSymbolName:@"doc.on.doc" accessibilityDescription:nil];
    self.settingsButton.image = [NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:nil];
    self.documentsButton.accessibilityLabel = @"Documents"; self.settingsButton.accessibilityLabel = @"Settings";
    for (NSButton* button in @[self.documentsButton,self.settingsButton]) {
        button.buttonType = NSButtonTypePushOnPushOff; [navigation addArrangedSubview:button];
        [button.widthAnchor constraintEqualToAnchor:navigation.widthAnchor].active = YES;
        [button.heightAnchor constraintEqualToConstant:32].active = YES;
    }
    [navigation setCustomSpacing:13 afterView:self.documentsButton];
    NSTextField* note = SPDFCollectionText(@"Local copies and history.\nYour originals stay where they are.",12,NSFontWeightRegular,YES);
    [navigation addArrangedSubview:note]; [navigation setCustomSpacing:20 afterView:self.settingsButton];
    [note.widthAnchor constraintEqualToAnchor:navigation.widthAnchor constant:-10].active = YES;
    NSView* sidebarLine = SPDFCollectionSurface(@"line"); sidebarLine.translatesAutoresizingMaskIntoConstraints = NO;
    [sidebar addSubview:sidebarLine]; [NSLayoutConstraint activateConstraints:@[
        [sidebarLine.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor], [sidebarLine.topAnchor constraintEqualToAnchor:sidebar.topAnchor],
        [sidebarLine.bottomAnchor constraintEqualToAnchor:sidebar.bottomAnchor],[sidebarLine.widthAnchor constraintEqualToConstant:1]]];
    self.contentHost = [NSView new]; self.contentHost.translatesAutoresizingMaskIntoConstraints = NO; [root addSubview:self.contentHost];
    [NSLayoutConstraint activateConstraints:@[[self.contentHost.leadingAnchor constraintEqualToAnchor:sidebar.trailingAnchor],
        [self.contentHost.trailingAnchor constraintEqualToAnchor:root.trailingAnchor], [self.contentHost.topAnchor constraintEqualToAnchor:root.topAnchor],
        [self.contentHost.bottomAnchor constraintEqualToAnchor:root.bottomAnchor]]];
    NSStackView* documents = Stack(NO); documents.spacing = 0; self.documentsPane = documents; Fill(documents,self.contentHost);
    NSStackView* toolbar = Stack(NO); toolbar.spacing = 10; toolbar.edgeInsets = NSEdgeInsetsMake(16,20,13,20);
    [documents addArrangedSubview:toolbar]; [toolbar.widthAnchor constraintEqualToAnchor:documents.widthAnchor].active = YES;
    self.search = SPDFCollectionSearchField(); self.search.placeholderString = @"Search documents and latest saved text";
    self.search.stringValue = [preferences[@"managerQuery"] isKindOfClass:NSString.class] ? preferences[@"managerQuery"] : @"";
    self.search.target = self; self.search.action = @selector(reload:); self.search.sendsSearchStringImmediately = YES;
    [toolbar addArrangedSubview:self.search]; [self.search.widthAnchor constraintEqualToAnchor:toolbar.widthAnchor constant:-40].active = YES;
    [self.search.heightAnchor constraintEqualToConstant:31].active = YES;
    NSStackView* filters = Stack(YES); filters.spacing = 8;
    self.viewPicker = SPDFCollectionPopUp();
    [self.viewPicker addItemsWithTitles:@[@"All Documents",@"Originals Unavailable",@"Kept",@"Excluded"]];
    NSArray<NSNumber*>* filterTags = @[@0,@2,@3,@4];
    for (NSUInteger index=0;index<filterTags.count;index++) [self.viewPicker itemAtIndex:index].tag = filterTags[index].integerValue;
    NSInteger restoredFilter = [preferences[@"managerView"] integerValue];
    if (![filterTags containsObject:@(restoredFilter)]) restoredFilter = 0;
    [self.viewPicker selectItemWithTag:restoredFilter];
    self.viewPicker.target = self; self.viewPicker.action = @selector(reload:);
    [filters addArrangedSubview:SPDFCollectionText(@"Show",13,NSFontWeightRegular,NO)]; [filters addArrangedSubview:self.viewPicker];
    [toolbar addArrangedSubview:filters];
    [toolbar addArrangedSubview:SPDFCollectionText(@"Search each document’s latest saved text. Open History for previous versions.",12,NSFontWeightRegular,YES)];
    NSView* divider = SPDFCollectionDivider(); [documents addArrangedSubview:divider];
    [divider.widthAnchor constraintEqualToAnchor:documents.widthAnchor].active = YES;
    NSStackView* resultsHead = Stack(YES); resultsHead.spacing = 8; resultsHead.edgeInsets = NSEdgeInsetsMake(8,20,7,20);
    self.resultSummary = SPDFCollectionText(@"",12,NSFontWeightRegular,YES); [resultsHead addArrangedSubview:self.resultSummary];
    NSView* spring = [NSView new]; [resultsHead addArrangedSubview:spring];
    self.layoutPicker = SPDFCollectionPopUp(); [self.layoutPicker addItemsWithTitles:@[@"List",@"Thumbnails"]];
    [self.layoutPicker selectItemAtIndex:MIN(1,MAX(0,[preferences[@"managerLayout"] integerValue]))];
    self.sortPicker = SPDFCollectionPopUp(); [self.sortPicker addItemsWithTitles:@[@"Newest first",@"Oldest first",@"Name"]];
    [self.sortPicker selectItemAtIndex:MIN(2,MAX(0,[preferences[@"managerSort"] integerValue]))];
    for (NSPopUpButton* picker in @[self.layoutPicker,self.sortPicker]) {
        picker.target = self; picker.action = @selector(reload:); [resultsHead addArrangedSubview:picker];
    }
    NSButton* more = SPDFCollectionButton(@"More",self,@selector(showDocumentMenu:),@"quiet"); more.tag = -1;
    [resultsHead addArrangedSubview:more]; [documents addArrangedSubview:resultsHead];
    [resultsHead.widthAnchor constraintEqualToAnchor:documents.widthAnchor].active = YES;
    self.listScroll = [NSScrollView new]; self.listScroll.hasVerticalScroller = YES; self.listScroll.borderType = NSNoBorder;
    self.listScroll.drawsBackground = NO;
    self.table = [NSTableView new]; self.table.headerView = nil; self.table.rowHeight = 190;
    self.table.backgroundColor = SPDFCollectionColor(@"window"); self.table.intercellSpacing = NSMakeSize(0,0);
    self.table.allowsMultipleSelection = YES; self.table.dataSource = self; self.table.delegate = self;
    self.table.target = self; self.table.doubleAction = @selector(preview:);
    NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"document"]; column.width = 750;
    [self.table addTableColumn:column]; self.listScroll.documentView = self.table;
    NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Document actions"]; menu.delegate = (id)self; self.table.menu = menu;
    NSView* results = [NSView new]; [documents addArrangedSubview:results]; Fill(self.listScroll,results);
    [self installGridInView:results];
    [results.widthAnchor constraintEqualToAnchor:documents.widthAnchor].active = YES;
    [results.bottomAnchor constraintEqualToAnchor:documents.bottomAnchor].active = YES;
    // Existing command availability remains shared by the accessible contextual menu.
    self.details = Label(@"Select a document or version.",12,NSFontWeightRegular);
    self.selectionButtons = [NSMutableArray array];
    NSArray* titles = @[@"Open Original",@"Preview Read-only Copy",@"History",@"Compare with Current",@"Compare with Previous",
        @"Locate Original…",@"Save a Copy…",@"Keep / Unkeep",@"Exclude / Include",@"Delete Selected Copies…"];
    NSArray* actions = @[@"openOriginal:",@"preview:",@"history:",@"compareCurrent:",@"comparePrevious:",@"locate:",
        @"exportCopy:",@"keep:",@"exclude:",@"deleteSelected:"];
    for (NSUInteger i=0;i<titles.count;i++) [self.selectionButtons addObject:SPDFCollectionButton(titles[i],self,NSSelectorFromString(actions[i]),@"normal")];
    [self buildSettingsPane];
    [self showDestination:[preferences[@"managerDestination"] isEqual:@"Settings"] ? @"Settings" : @"Documents"];
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
    NSDictionary* preferences = @{@"managerView":@(self.viewPicker.selectedItem.tag),
        @"managerLayout":@(self.layoutPicker.indexOfSelectedItem),@"managerSort":@(self.sortPicker.indexOfSelectedItem),
        @"managerDestination":self.destination ?: @"Documents", @"managerQuery":self.search.stringValue,
        @"managerSearchScope":@0, @"managerBrowseState":[self captureBrowseState]};
    dispatch_async(self.preferenceQueue, ^{
        NSError* error = nil; [self.store updateSettings:preferences error:&error];
        if (error) dispatch_async(dispatch_get_main_queue(),^{ [self showError:error]; });
    });
}
@end
