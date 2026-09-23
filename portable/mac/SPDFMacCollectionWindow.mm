#import "SPDFMacCollectionAvailability.h"
#import "SPDFMacCollectionWindowPrivate.h"
#import "SPDFMacCollectionStoreContextSearch.h"
#import "SPDFMacCollectionWindowHistory.h"
#import "SPDFMacCollectionManagerWindow.h"
@implementation SPDFMacCollectionWindow
- (instancetype)initWithStore:(SPDFMacCollectionStore*)store open:(SPDFCollectionOpenHandler)open {
    NSWindow* window = [[SPDFCollectionManagerWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1100, 690)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    if (!(self = [super initWithWindow:window])) return nil;
    _store = store; _openHandler = [open copy]; _rows = @[]; _documents = @[];
    window.title = @"Collection"; window.releasedWhenClosed = NO;
    window.minSize = NSMakeSize(940, 560); [window setFrameAutosaveName:@"CollectionManager"];
    NSDictionary* preferences = store.settings;
    _initialBrowseState = [preferences[@"managerBrowseState"] isKindOfClass:NSDictionary.class] ? preferences[@"managerBrowseState"] : @{};
    NSArray* expanded = [_initialBrowseState[@"expanded"] isKindOfClass:NSArray.class] ? _initialBrowseState[@"expanded"] : @[];
    _expandedResults = [NSMutableSet setWithArray:expanded];
    if ([preferences[@"managerDestination"] isEqual:@"History"]) {
        _documentID = preferences[@"managerHistoryDocumentID"];
        _restoreHistoryVersionID = preferences[@"managerHistoryVersionID"];
    }
    _preferenceQueue = dispatch_queue_create("engineering.casimir.collection.manager-preferences", DISPATCH_QUEUE_SERIAL);
    [self buildManagerLayout];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(managerWindowWillClose:)
        name:NSWindowWillCloseNotification object:window];
    return self;
}
- (void)showDocumentID:(NSString*)documentID query:(NSString*)query {
    if (documentID.length || query != nil) {
        _documentID = documentID;
        _restoreHistoryVersionID = nil;
    }
    if (query != nil) { _search.stringValue = query; [self showDestination:@"Documents"]; }

    [self reload:nil]; [self showWindow:nil]; [self.window makeKeyAndOrderFront:nil];
}
- (void)reload:(id)sender {
    if (sender == _search || sender == _scopePicker || sender == _viewPicker) {
        _documentID = nil; _restoreHistoryVersionID = nil;
    }
    [self persistManagerPreferences];
    NSDictionary* browseState = [self captureBrowseState];
    BOOL allVersions = self.scopePicker.indexOfSelectedItem == 1;
    NSUInteger generation = ++_generation;
    NSInteger view = _viewPicker.indexOfSelectedItem, sort = _sortPicker.indexOfSelectedItem;
    NSString* query = [_search.stringValue copy]; NSString* selectedID = [_documentID copy];
    _storage.stringValue = @"Loading local history…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray* docs = [self.store documents]; NSMutableArray* rows = [NSMutableArray array];
        for (NSDictionary* doc in docs) {
            BOOL missing = !SPDFCollectionOriginalAvailable(doc);
            if (view == 2 && !missing) continue;
            if (view == 4 && ![doc[@"excluded"] boolValue]) continue;
            NSArray* versions = doc[@"versions"] ?: @[];
            if (view == 1 || view == 3) {
                for (NSDictionary* version in versions) {
                    if (view == 3 && ![version[@"keep"] boolValue]) continue;
                    [rows addObject:@{@"document":doc, @"version":version}];
                }
            } else [rows addObject:@{@"document":doc, @"version":versions.lastObject ?: @{}}];
        }
        if (query.length) {
            [rows removeAllObjects];
            for (NSDictionary* group in [self.store searchGroups:query allVersions:allVersions]) {
                NSDictionary* doc = group[@"document"];
                if (view == 2 && SPDFCollectionOriginalAvailable(doc)) continue;
                if (view == 4 && ![doc[@"excluded"] boolValue]) continue;
                for (NSDictionary* result in group[@"versions"]) {
                    if (view == 3 && ![result[@"version"][@"keep"] boolValue]) continue;
                    NSMutableDictionary* row = [result mutableCopy]; row[@"document"] = doc;
                    [rows addObject:row];
                }
            }
        }
        [rows sortUsingComparator:^NSComparisonResult(NSDictionary* a, NSDictionary* b) {
            if (sort == 2) return [a[@"document"][@"title"] localizedStandardCompare:b[@"document"][@"title"]];
            NSComparisonResult result = [a[@"version"][@"capturedAt"] compare:b[@"version"][@"capturedAt"]];
            return sort == 0 ? (NSComparisonResult)-result : result;
        }];
        unsigned long long used = [self.store storageUsedBytes];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.generation) return;
            self.reloadingResults = YES;
            [self restoreBrowseState:browseState toRows:rows query:query];
            if (![browseState[@"query"] isEqual:query]) [self.expandedResults removeAllObjects];
            self.documents = docs; self.rows = rows; self.resultQuery = query; self.hasLoadedResults = YES;
            self.table.rowHeight = 100;
            [self.table reloadData];
            [self reloadGrid];
            [self restoreBrowseSelectionAndScroll:browseState];
            self.reloadingResults = NO;
            self.resultSummary.stringValue = [NSString stringWithFormat:@"%lu %@",(unsigned long)rows.count,query.length ? (rows.count==1 ? @"matching saved copy" : @"matching saved copies") : (rows.count==1 ? @"item" : @"items")];
            self.locationField.stringValue = self.store.rootURL.path;
            [self updateStoragePolicy];
            self.enabled.state = self.store.isEnabled ? NSControlStateValueOn : NSControlStateValueOff;
            if (selectedID.length) {
                self.documentID = nil;
                for (NSDictionary* doc in docs) if ([doc[@"id"] isEqual:selectedID]) {
                    NSDictionary* chosen = [doc[@"versions"] lastObject];
                    for (NSDictionary* version in doc[@"versions"])
                        if ([version[@"id"] isEqual:self.restoreHistoryVersionID]) { chosen = version; break; }
                    [self showHistoryForDocument:doc version:chosen];
                }
                self.restoreHistoryVersionID = nil;
            }
            self.storage.stringValue = [NSString stringWithFormat:@"%@ used · %@",
                [NSByteCountFormatter stringFromByteCount:(long long)used countStyle:NSByteCountFormatterCountStyleFile],
                self.store.isEnabled ? @"Capturing" : @"Capture off"];
            [self updateDetails];
        });
    });
}
- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView { (void)tableView; return _rows.count; }
- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
    (void)tableView; (void)column; return [self resultCellForRow:row];
}
- (void)tableViewSelectionDidChange:(NSNotification*)notification {
    (void)notification; [self synchronizeGridSelection]; [self updateDetails];
    if (!self.reloadingResults && self.hasLoadedResults) [self persistManagerPreferences];
}
- (NSDictionary*)selectedDocument {
    if ([self.destination isEqual:@"History"]) return [self historySelectedDocument];
    NSInteger row = _table.selectedRow;
    return row >= 0 && row < (NSInteger)_rows.count ? _rows[(NSUInteger)row][@"document"] : nil;
}
- (NSDictionary*)selectedVersion {
    if ([self.destination isEqual:@"History"]) return [self historySelectedVersion];
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
    BOOL single = [self.destination isEqual:@"History"] || _table.selectedRowIndexes.count == 1;
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
- (void)managerWindowWillClose:(NSNotification*)notification {
    (void)notification; [self persistManagerPreferences];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)showError:(NSError*)error { if (error) [self.window presentError:error]; }
@end
