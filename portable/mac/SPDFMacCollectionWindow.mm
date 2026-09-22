#import "SPDFMacCollectionAvailability.h"
#import "SPDFMacCollectionWindowPrivate.h"
@interface SPDFCollectionOptionsStack : NSStackView
@end
@implementation SPDFCollectionOptionsStack
- (BOOL)isFlipped { return YES; }
@end
static NSTextField* SPDFCollectionLabel(NSString* text, CGFloat size, NSFontWeight weight) {
    NSTextField* field = [NSTextField wrappingLabelWithString:text];
    field.font = [NSFont systemFontOfSize:size weight:weight];
    return field;
}
@implementation SPDFMacCollectionWindow
- (instancetype)initWithStore:(SPDFMacCollectionStore*)store open:(SPDFCollectionOpenHandler)open {
    NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1100, 690)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    if (!(self = [super initWithWindow:window])) return nil;
    _store = store; _openHandler = [open copy]; _rows = @[]; _documents = @[];
    window.title = @"Collection"; window.releasedWhenClosed = NO;
    window.minSize = NSMakeSize(940, 560); [window setFrameAutosaveName:@"CollectionManager"];
    NSStackView* root = [NSStackView stackViewWithViews:@[]];
    root.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    root.distribution = NSStackViewDistributionFill;
    root.alignment = NSLayoutAttributeTop; root.spacing = 18;
    root.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    root.translatesAutoresizingMaskIntoConstraints = NO; [window.contentView addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:window.contentView.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:window.contentView.bottomAnchor]]];
    NSStackView* left = [NSStackView stackViewWithViews:@[]];
    left.orientation = NSUserInterfaceLayoutOrientationVertical; left.alignment = NSLayoutAttributeLeading;
    left.spacing = 12; [left.widthAnchor constraintEqualToConstant:175].active = YES;
    [left addArrangedSubview:SPDFCollectionLabel(@"Collection", 22, NSFontWeightBold)];
    [left addArrangedSubview:SPDFCollectionLabel(@"Local copies and history", 12, NSFontWeightRegular)];
    _viewPicker = [[NSPopUpButton alloc] init];
    [_viewPicker addItemsWithTitles:@[@"All Documents", @"Versions", @"Originals Unavailable", @"Kept", @"Excluded", @"Storage"]];
    _viewPicker.target = self; _viewPicker.action = @selector(reload:);
    [_viewPicker selectItemAtIndex:MIN(5, MAX(0, [[store settings][@"managerView"] integerValue]))];
    [left addArrangedSubview:_viewPicker];
    _layoutPicker = [[NSPopUpButton alloc] init]; [_layoutPicker addItemsWithTitles:@[@"List", @"Thumbnails"]];
    [_layoutPicker selectItemAtIndex:MIN(1, MAX(0, [[store settings][@"managerLayout"] integerValue]))];
    _layoutPicker.target = self; _layoutPicker.action = @selector(reload:); [left addArrangedSubview:_layoutPicker];
    _sortPicker = [[NSPopUpButton alloc] init]; [_sortPicker addItemsWithTitles:@[@"Newest first", @"Oldest first", @"Name"]];
    [_sortPicker selectItemAtIndex:MIN(2, MAX(0, [[store settings][@"managerSort"] integerValue]))];
    _sortPicker.target = self; _sortPicker.action = @selector(reload:); [left addArrangedSubview:_sortPicker];
    [root addArrangedSubview:left];
    NSStackView* center = [NSStackView stackViewWithViews:@[]];
    center.orientation = NSUserInterfaceLayoutOrientationVertical; center.alignment = NSLayoutAttributeLeading;
    center.spacing = 12;
    _search = [[NSSearchField alloc] init]; _search.placeholderString = @"Search Collection";
    _search.target = self; _search.action = @selector(reload:); _search.sendsSearchStringImmediately = YES;
    [center addArrangedSubview:_search];
    NSScrollView* scroll = [[NSScrollView alloc] init]; scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    _table = [[NSTableView alloc] init]; _table.headerView = nil; _table.rowHeight = 58;
    _table.allowsMultipleSelection = YES; _table.dataSource = self; _table.delegate = self;
    _table.target = self; _table.doubleAction = @selector(preview:);
    NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"document"];
    column.width = 530; [_table addTableColumn:column]; scroll.documentView = _table;
    _listScroll = scroll;
    NSView* contents = [NSView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [contents addSubview:scroll];
    [center addArrangedSubview:contents];
    [self installGridInView:contents];
    // Attach the subtree before activating constraints to the root. AppKit
    // rejects cross-tree anchors, even if the missing parent is added later.
    [root addArrangedSubview:center];
    [NSLayoutConstraint activateConstraints:@[
        [_search.widthAnchor constraintEqualToAnchor:center.widthAnchor],
        [contents.widthAnchor constraintEqualToAnchor:center.widthAnchor],
        [contents.heightAnchor constraintEqualToAnchor:root.heightAnchor constant:-82],
        [scroll.leadingAnchor constraintEqualToAnchor:contents.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:contents.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:contents.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:contents.bottomAnchor]]];
    NSStackView* right = [SPDFCollectionOptionsStack stackViewWithViews:@[]];
    right.orientation = NSUserInterfaceLayoutOrientationVertical; right.alignment = NSLayoutAttributeLeading;
    right.spacing = 9; [right.widthAnchor constraintEqualToConstant:235].active = YES;
    [right addArrangedSubview:SPDFCollectionLabel(@"Document options", 16, NSFontWeightSemibold)];
    _details = SPDFCollectionLabel(@"Select a document or version.", 12, NSFontWeightRegular);
    [_details.widthAnchor constraintEqualToConstant:235].active = YES; [right addArrangedSubview:_details];
    _selectionButtons = [NSMutableArray array];
    NSArray* titles = @[@"Open Original", @"Preview Read-only Copy", @"Version History", @"Compare with Current",
                         @"Compare with Previous", @"Locate Original…", @"Save a Copy…", @"Keep / Unkeep", @"Exclude / Include", @"Delete Selected Copies…"];
    NSArray* selectors = @[@"openOriginal:", @"preview:", @"history:", @"compareCurrent:", @"comparePrevious:",
                            @"locate:", @"exportCopy:", @"keep:", @"exclude:", @"deleteSelected:"];
    for (NSUInteger i = 0; i < titles.count; i++) {
        NSButton* button = [NSButton buttonWithTitle:titles[i] target:self action:NSSelectorFromString(selectors[i])];
        button.bezelStyle = NSBezelStyleRounded; [right addArrangedSubview:button]; [_selectionButtons addObject:button];
    }
    [right addArrangedSubview:SPDFCollectionLabel(@"Collection settings", 16, NSFontWeightSemibold)];
    _enabled = [NSButton checkboxWithTitle:@"Keep copies and history" target:self action:@selector(changeEnabled:)];
    _enabled.state = store.isEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [right addArrangedSubview:_enabled];
    NSTextField* offExplanation = SPDFCollectionLabel(@"Off stops new copies and indexing. Existing history stays searchable and can be exported or deleted.", 11, NSFontWeightRegular);
    [offExplanation.widthAnchor constraintEqualToConstant:235].active = YES;
    [right addArrangedSubview:offExplanation];
    _storage = SPDFCollectionLabel(@"", 11, NSFontWeightRegular); [_storage.widthAnchor constraintEqualToConstant:235].active = YES;
    [right addArrangedSubview:_storage];
    [right addArrangedSubview:[NSButton buttonWithTitle:@"Collection Location…" target:self action:@selector(changeLocation:)]];
    [right addArrangedSubview:SPDFCollectionLabel(@"Storage cap in GB · 0 keeps all",11,NSFontWeightRegular)];
    _limitField = [[NSTextField alloc] init]; _limitField.placeholderString = @"Storage cap in GB (0 = keep all)";
    _limitField.doubleValue = [[store settings][@"storageLimitBytes"] doubleValue] / 1e9;
    _limitField.target = self; _limitField.action = @selector(changeLimit:);
    [_limitField.widthAnchor constraintEqualToConstant:235].active = YES; [right addArrangedSubview:_limitField];
    [right addArrangedSubview:[NSButton buttonWithTitle:@"Apply Storage Cap" target:self action:@selector(changeLimit:)]];
    // Options remain reachable on a laptop: this panel scrolls independently
    // instead of forcing its controls below the window's bottom edge.
    NSScrollView* optionsScroll = [NSScrollView new];
    optionsScroll.hasVerticalScroller = YES; optionsScroll.drawsBackground = NO;
    right.frame = NSMakeRect(0,0,235,900);
    optionsScroll.documentView = right;
    [root addArrangedSubview:optionsScroll];
    [optionsScroll.widthAnchor constraintEqualToConstant:250].active = YES;
    [optionsScroll.heightAnchor constraintEqualToAnchor:root.heightAnchor constant:-40].active = YES;
    [right.heightAnchor constraintGreaterThanOrEqualToConstant:880].active = YES;
    return self;
}
- (void)showDocumentID:(NSString*)documentID query:(NSString*)query {
    _documentID = documentID;
    if (documentID.length) [_viewPicker selectItemAtIndex:1];
    else if (query != nil) [_viewPicker selectItemAtIndex:0];
    _search.stringValue = query ?: @"";
    [self reload:nil]; [self showWindow:nil]; [self.window makeKeyAndOrderFront:nil];
}
- (void)reload:(id)sender {
    if (sender == _viewPicker && _viewPicker.indexOfSelectedItem != 1) _documentID = nil;
    NSDictionary* preferences = @{@"managerView": @(_viewPicker.indexOfSelectedItem),
        @"managerLayout": @(_layoutPicker.indexOfSelectedItem), @"managerSort": @(_sortPicker.indexOfSelectedItem)};
    NSUInteger generation = ++_generation;
    NSInteger view = _viewPicker.indexOfSelectedItem, sort = _sortPicker.indexOfSelectedItem;
    NSString* query = [_search.stringValue copy]; NSString* selectedID = [_documentID copy];
    _storage.stringValue = @"Loading local history…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError* preferenceError = nil;
        [self.store updateSettings:preferences error:&preferenceError];
        NSArray* docs = [self.store documents]; NSMutableArray* rows = [NSMutableArray array];
        for (NSDictionary* doc in docs) {
            BOOL missing = !SPDFCollectionOriginalAvailable(doc);
            if (view == 2 && !missing) continue;
            if (view == 4 && ![doc[@"excluded"] boolValue]) continue;
            if (selectedID.length && ![doc[@"id"] isEqual:selectedID]) continue;
            NSArray* versions = doc[@"versions"] ?: @[];
            if (view == 1 || view == 3) {
                for (NSDictionary* version in versions) {
                    if (view == 3 && ![version[@"keep"] boolValue]) continue;
                    [rows addObject:@{@"document":doc, @"version":version}];
                }
            } else [rows addObject:@{@"document":doc, @"version":versions.lastObject ?: @{}}];
        }
        NSMutableSet* matchingDocuments = [NSMutableSet set];
        if (query.length) {
            for (NSDictionary* hit in [self.store search:query titlesOnly:YES excludingPaths:NSSet.set limit:0]) [matchingDocuments addObject:hit[@"id"]];
            for (NSDictionary* hit in [self.store search:query titlesOnly:NO excludingPaths:NSSet.set limit:0]) [matchingDocuments addObject:hit[@"id"]];
        }
        if (query.length) [rows filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary* row, NSDictionary* unused) {
            (void)unused; NSDictionary* doc = row[@"document"];
            NSString* text = [NSString stringWithFormat:@"%@ %@ %@", doc[@"title"], doc[@"path"], row[@"version"][@"reason"] ?: @""];
            return [matchingDocuments containsObject:doc[@"id"]] || [text localizedCaseInsensitiveContainsString:query];
        }]];
        [rows sortUsingComparator:^NSComparisonResult(NSDictionary* a, NSDictionary* b) {
            if (sort == 2) return [a[@"document"][@"title"] localizedStandardCompare:b[@"document"][@"title"]];
            NSComparisonResult result = [a[@"version"][@"capturedAt"] compare:b[@"version"][@"capturedAt"]];
            return sort == 0 ? (NSComparisonResult)-result : result;
        }];
        unsigned long long used = [self.store storageUsedBytes];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.generation) return;
            if (preferenceError) [self showError:preferenceError];
            self.documents = docs; self.rows = rows;
            self.table.rowHeight = 58;
            [self.table reloadData];
            [self reloadGrid];
            self.storage.stringValue = [NSString stringWithFormat:@"%@ used · %@\n%@\nOriginals are never deleted by Collection.",
                [NSByteCountFormatter stringFromByteCount:(long long)used countStyle:NSByteCountFormatterCountStyleFile],
                self.store.isEnabled ? @"Capturing" : @"Capture off",self.store.rootURL.path];
            [self updateDetails];
        });
    });
}
- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView { (void)tableView; return _rows.count; }
- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
    (void)tableView; (void)column;
    NSDictionary* entry = _rows[(NSUInteger)row]; NSDictionary* doc = entry[@"document"], *version = entry[@"version"];
    NSString* date = version[@"capturedAt"] ? [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:[version[@"capturedAt"] doubleValue]]
                                                   dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle] : @"No protected copy";
    BOOL missing = !SPDFCollectionOriginalAvailable(doc);
    NSString* status = missing ? @"Original unavailable" : @"Original available";
    NSString* text = [NSString stringWithFormat:@"%@%@\n%@ · %@ · %@", [version[@"keep"] boolValue] ? @"★ " : @"",
        doc[@"title"] ?: @"Document", date, version[@"reason"] ?: @"", status];
    NSStackView* cell = [NSStackView stackViewWithViews:@[]]; cell.spacing = 10;
    if (_layoutPicker.indexOfSelectedItem == 1) {
        NSImageView* icon = [[NSImageView alloc] init]; icon.image = [NSWorkspace.sharedWorkspace iconForFile:doc[@"path"]];
        [icon.widthAnchor constraintEqualToConstant:60].active = YES; [icon.heightAnchor constraintEqualToConstant:70].active = YES;
        [cell addArrangedSubview:icon];
    }
    NSTextField* label = SPDFCollectionLabel(text, 12, NSFontWeightRegular); label.toolTip = doc[@"path"];
    [cell addArrangedSubview:label]; return cell;
}
- (void)tableViewSelectionDidChange:(NSNotification*)notification {
    (void)notification; [self synchronizeGridSelection]; [self updateDetails];
}
- (NSDictionary*)selectedDocument {
    NSInteger row = _table.selectedRow;
    return row >= 0 && row < (NSInteger)_rows.count ? _rows[(NSUInteger)row][@"document"] : nil;
}
- (NSDictionary*)selectedVersion {
    NSInteger row = _table.selectedRow;
    return row >= 0 && row < (NSInteger)_rows.count ? _rows[(NSUInteger)row][@"version"] : nil;
}
- (void)updateDetails {
    NSDictionary* doc = [self selectedDocument], *version = [self selectedVersion];
    NSString* (^date)(id) = ^NSString*(id seconds) {
        return seconds ? [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:[seconds doubleValue]]
            dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle] : @"Not captured";
    };
    NSString* warnings = [version[@"assetWarnings"] isKindOfClass:NSArray.class]
        ? [version[@"assetWarnings"] componentsJoinedByString:@"\n"] : @"";
    _details.stringValue = doc ? [NSString stringWithFormat:@"%@\n%@\n%@ · %lu versions\nCaptured %@\nSource modified %@\n%@ · %@\n%@%@%@",
        doc[@"title"],doc[@"path"],doc[@"status"] ?: @"Protected",(unsigned long)[doc[@"versions"] count],
        date(version[@"capturedAt"]),date(version[@"modifiedAt"]),
        [NSByteCountFormatter stringFromByteCount:[version[@"size"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile],
        [version[@"keep"] boolValue] ? @"Kept version" : version[@"id"] ? @"Read-only archive" : @"No archived version",
        [doc[@"excluded"] boolValue] ? @"Excluded from future capture" : @"Capture allowed",
        [version[@"encrypted"] boolValue] ? @"\nEncrypted · no text index" : @"",
        warnings.length ? [@"\nAssets incomplete:\n" stringByAppendingString:warnings] : @""]
        : (_rows.count ? @"Select a document or version." : @"No documents in this view.");
    BOOL single = _table.selectedRowIndexes.count == 1;
    BOOL archived = [version[@"id"] length] > 0;
    BOOL sourceAvailable = SPDFCollectionOriginalAvailable(doc);
    NSArray* versions = doc ? doc[@"versions"] ?: @[] : @[];
    BOOL previous = versions.count > 1 && ![versions.firstObject[@"id"] isEqual:version[@"id"]];
    for (NSButton* button in _selectionButtons) {
        NSString* action = NSStringFromSelector(button.action);
        BOOL bulk = [@[@"keep:",@"exclude:",@"deleteSelected:"] containsObject:action];
        button.enabled = doc && (single || bulk) && !_mutationPending;
        if ([@[@"preview:",@"exportCopy:",@"keep:",@"compareCurrent:",@"comparePrevious:"] containsObject:action])
            button.enabled &= archived;
        if ([action isEqual:@"openOriginal:"] || [action isEqual:@"compareCurrent:"]) button.enabled &= sourceAvailable;
        if ([action isEqual:@"comparePrevious:"]) button.enabled &= previous;
        if ([action hasPrefix:@"compare"]) button.enabled &= ![version[@"encrypted"] boolValue];
    }
}
- (void)showError:(NSError*)error { if (error) [self.window presentError:error]; }
@end
