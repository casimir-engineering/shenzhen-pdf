#import "SPDFMacCollectionSavePanel.h"
#import "SPDFMacCollectionAvailability.h"
#import "SPDFMacCollectionHistory.h"
#import "SPDFMacCollectionStore.h"
#import "SPDFMacCollectionCompare.h"
#import "SPDFMacCollectionCompareLatest.h"
#import "SPDFMacCollectionStyle.h"
#import "SPDFMacFileExplorerPreference.h"

@implementation SPDFMacCollectionHistoryController {
    SPDFMacCollectionStore* _store;
    NSString* _documentID;
    SPDFCollectionOpenHandler _open;
    NSDictionary* _document;
    NSArray<NSDictionary*>* _versions;
    NSTableView* _table;
    NSTextField* _title;
    NSTextField* _status;
    NSMutableArray<NSButton*>* _buttons;
    NSUInteger _generation;
    NSUInteger _previewGeneration;
    BOOL _restoringSelection;
    NSStackView* _recoveryActions;
}
- (instancetype)initWithStore:(SPDFMacCollectionStore*)store documentID:(NSString*)documentID
                         open:(SPDFCollectionOpenHandler)open {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    _store = store; _documentID = documentID.copy; _open = [open copy]; _versions = @[];
    return self;
}
- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0,0,280,650)];
    NSTextField* heading = [NSTextField labelWithString:@"Version History"];
    heading.font = [NSFont boldSystemFontOfSize:15];
    _title = [NSTextField wrappingLabelWithString:@"Loading…"];
    _title.maximumNumberOfLines = 3;
    _status = [NSTextField wrappingLabelWithString:@"Archived copies are read-only."];
    _status.font = [NSFont systemFontOfSize:11];
    _status.textColor = NSColor.secondaryLabelColor;
    _table = [NSTableView new]; _table.headerView = nil; _table.rowHeight = 82;
    _table.dataSource = self; _table.delegate = self;
    _table.menu = [[NSMenu alloc] initWithTitle:@"Version"]; _table.menu.delegate = self;
    NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"version"]; column.width = 240;
    [_table addTableColumn:column];
    NSScrollView* scroll = [NSScrollView new]; scroll.documentView = _table;
    scroll.hasVerticalScroller = YES;
    _buttons = [NSMutableArray array];
    NSStackView* actions = [NSStackView stackViewWithViews:@[]];
    actions.orientation = NSUserInterfaceLayoutOrientationVertical; actions.alignment = NSLayoutAttributeLeading;
    NSArray* titles = @[@"Compare with Latest",@"Compare with Previous",@"Save a Copy…",@"Keep Version",@"Manage Collection…"];
    NSArray* selectors = @[@"compareCurrent:",@"comparePrevious:",@"saveCopy:",@"keep:",@"manage:"];
    for (NSUInteger index = 0; index < titles.count; index++) {
        NSButton* button = [NSButton buttonWithTitle:titles[index] target:self action:NSSelectorFromString(selectors[index])];
        button.bezelStyle = NSBezelStyleRounded;
        [actions addArrangedSubview:button]; [_buttons addObject:button];
    }
    NSButton* find = [NSButton buttonWithTitle:@"Find Document…" target:self action:@selector(findDocument:)];
    NSButton* save = [NSButton buttonWithTitle:@"Save New Copy As…" target:self action:@selector(saveLatestAs:)];
    _recoveryActions = [NSStackView stackViewWithViews:@[find,save]];
    _recoveryActions.orientation = NSUserInterfaceLayoutOrientationVertical;
    _recoveryActions.alignment = NSLayoutAttributeLeading; _recoveryActions.hidden = YES;
    NSStackView* stack = [NSStackView stackViewWithViews:@[heading,_title,_status,_recoveryActions,scroll,actions]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical; stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10; stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [stack.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-10],
        [_title.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [_status.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [scroll.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:80]]];
    [self reload];
}
- (void)reload {
    NSUInteger generation = ++_generation;
    NSString* identifier = _documentID;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSDictionary* found = nil;
        for (NSDictionary* doc in [self->_store documents]) if ([doc[@"id"] isEqual:identifier]) { found = doc; break; }
        NSArray* versions = [[found[@"versions"] reverseObjectEnumerator] allObjects] ?: @[];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->_generation) return;
            NSString* selected = [self selectedVersion][@"id"];
            self->_document = found; self->_versions = versions;
            self->_title.stringValue = found[@"title"] ?: @"No protected history";
            self->_title.toolTip = found[@"path"];
            BOOL available = SPDFCollectionOriginalAvailable(found);
            self->_recoveryActions.hidden = available || !versions.count;
            self->_status.stringValue = available ? @"Latest opens your original. Earlier versions are read-only." :
                (versions.count ? @"Original missing. Saved versions remain available." : @"No saved versions yet");
            self->_restoringSelection = YES;
            [self->_table reloadData];
            if (selected) for (NSUInteger i = 0; i < versions.count; i++) if ([versions[i][@"id"] isEqual:selected])
                [self->_table selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
            self->_restoringSelection = NO;
            [self updateActions];
        });
    });
}
- (NSInteger)numberOfRowsInTableView:(NSTableView*)table { (void)table; return _versions.count; }
- (NSView*)tableView:(NSTableView*)table viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
    (void)table; (void)column;
    NSDictionary* version = _versions[row];
    NSString* date = [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:[version[@"capturedAt"] doubleValue]]
        dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle];
    NSString* size = [NSByteCountFormatter stringFromByteCount:[version[@"size"] longLongValue]
        countStyle:NSByteCountFormatterCountStyleFile];
    NSTextField* label = [NSTextField wrappingLabelWithString:[NSString stringWithFormat:@"%@%@\n%@ · %@",
        [version[@"keep"] boolValue] ? @"★ " : @"",date,version[@"reason"] ?: @"Saved version",size]];
    label.font = [NSFont systemFontOfSize:12]; label.maximumNumberOfLines = 3;
    NSStackView* rowView = [NSStackView stackViewWithViews:SPDFCollectionVersionIsLatest(_document, version)
        ? @[SPDFCollectionLatestBadge(), label] : @[label]];
    rowView.orientation = NSUserInterfaceLayoutOrientationVertical;
    rowView.alignment = NSLayoutAttributeLeading; rowView.spacing = 3;
    return rowView;
}
- (NSDictionary*)selectedVersion {
    NSInteger row = _table.selectedRow;
    return row >= 0 && row < (NSInteger)_versions.count ? _versions[row] : nil;
}
- (void)updateActions {
    NSDictionary* version = [self selectedVersion];
    for (NSUInteger i = 0; i < _buttons.count; i++) {
        _buttons[i].enabled = i == 4 || version != nil;
        if (i == 0) _buttons[i].enabled &= _versions.count > 0;
        if (i == 1) _buttons[i].enabled &= _table.selectedRow+1 < (NSInteger)_versions.count;
        if (i < 2) _buttons[i].enabled &= ![version[@"encrypted"] boolValue];
        if (i == 3) _buttons[i].title = [version[@"keep"] boolValue] ? @"Unkeep Version" : @"Keep Version";
    }
}
- (void)tableViewSelectionDidChange:(NSNotification*)note {
    (void)note; [self updateActions];
    NSDictionary* version = [self selectedVersion]; if (!version || _restoringSelection) return;
    NSUInteger generation = ++_previewGeneration;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSDictionary* current = [self currentDocument];
        BOOL original = SPDFCollectionVersionIsLatest(current,version) && SPDFCollectionOriginalAvailable(current);
        NSError* error = nil;
        NSURL* URL = original ? [NSURL fileURLWithPath:current[@"path"]] :
            [self->_store materializeVersionID:version[@"id"] documentID:self->_documentID error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->_previewGeneration) return;
            self->_document = current; self->_recoveryActions.hidden = SPDFCollectionOriginalAvailable(current);
            self->_status.stringValue = error.localizedDescription ?: (SPDFCollectionOriginalAvailable(current) ?
                @"Latest opens your original. Earlier versions are read-only." : @"Original missing. Saved versions remain available.");
            if (URL) self->_open(URL.path,!original);
        });
    });
}
- (void)materialize:(NSDictionary*)version completion:(void (^)(NSURL*))completion {
    _status.stringValue = @"Preparing read-only preview…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSError* error = nil;
        NSURL* URL = [self->_store materializeVersionID:version[@"id"] documentID:self->_documentID error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_status.stringValue = error.localizedDescription ?: @"Archived copy · read-only";
            if (URL) completion(URL);
        });
    });
}
- (void)compare:(BOOL)previous {
    NSDictionary* selected = [self selectedVersion]; if (!selected) return;
    NSInteger row = _table.selectedRow;
    if (previous && row+1 >= (NSInteger)_versions.count) return;
    NSDictionary* oldVersion = previous ? _versions[row+1] : selected;
    NSString* title = _document[@"title"] ?: @"Document";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSError* error = nil;
        NSURL* oldURL = [self->_store materializeVersionID:oldVersion[@"id"] documentID:self->_documentID error:&error];
        NSDictionary* latest = !previous && oldURL ? SPDFCollectionResolveLatestComparison(self->_store,self->_documentID,&error) : nil;
        NSURL* newURL = previous && oldURL ? [self->_store materializeVersionID:selected[@"id"] documentID:self->_documentID error:&error] : latest[@"URL"];
        NSString* (^label)(NSDictionary*) = ^NSString*(NSDictionary* version) {
            NSString* date = [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:
                [version[@"capturedAt"] doubleValue]] dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle];
            return [NSString stringWithFormat:@"%@ · %@",title,date];
        };
        dispatch_async(dispatch_get_main_queue(), ^{
            if (oldURL && newURL) SPDFMacShowCollectionComparison(oldURL,newURL,label(oldVersion),
                previous ? label(selected) : latest[@"label"],self.view.window);
            else self->_status.stringValue = error.localizedDescription ?: @"Comparison unavailable";
        });
    });
}
- (void)compareCurrent:(id)sender { (void)sender; [self compare:NO]; }
- (void)comparePrevious:(id)sender { (void)sender; [self compare:YES]; }
- (void)saveCopy:(id)sender {
    (void)sender; NSDictionary* version = [self selectedVersion]; if (!version) return;
    [self saveVersion:version restoreLink:NO];
}
- (void)saveVersion:(NSDictionary*)version restoreLink:(BOOL)restore {
    NSSavePanel* panel = [NSSavePanel savePanel]; SPDFCollectionConfigureSavePanel(panel, _document[@"path"]);
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
            NSError* error = nil;
            BOOL saved = [self->_store exportVersionID:version[@"id"] documentID:self->_documentID toURL:panel.URL error:&error];
            if (saved && restore) [self->_store linkDocumentID:self->_documentID toPath:panel.URL.path allowMismatch:NO error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) [self.view.window presentError:error]; else if (restore) [self didRestorePath:panel.URL.path];
                else { [self reload]; self->_open(panel.URL.path,NO); }
            });
        });
    }];
}
- (void)keep:(id)sender {
    (void)sender; NSDictionary* version = [self selectedVersion]; if (!version) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSError* error = nil;
        [self->_store setKeep:![version[@"keep"] boolValue] versionID:version[@"id"] documentID:self->_documentID error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{ if (error) [self.view.window presentError:error]; [self reload]; });
    });
}
- (NSDictionary*)currentDocument {
    for (NSDictionary* doc in [_store documents]) if ([doc[@"id"] isEqual:_documentID]) return doc;
    return _document;
}
- (void)findDocument:(id)sender {
    (void)sender;
    SPDFMacLocateCollectionOriginal(_store,_documentID,self.view.window, ^(NSString* path) {
        self->_open(path,NO);
    }, ^(NSString* path) {
        [self didRestorePath:path];
    });
}
- (void)didRestorePath:(NSString*)path {
    if (self.restoreLinkHandler) self.restoreLinkHandler(_document[@"path"],path);
    else _open(path,NO);
    [self reload];
}
- (void)saveLatestAs:(id)sender {
    (void)sender;
    NSDictionary* latest = _versions.firstObject;
    for (NSDictionary* version in _versions)
        if (SPDFCollectionVersionIsLatest(_document,version)) { latest = version; break; }
    if (latest) [self saveVersion:latest restoreLink:YES];
}
- (void)menuNeedsUpdate:(NSMenu*)menu {
    [menu removeAllItems];
    NSInteger row = _table.clickedRow >= 0 ? _table.clickedRow : _table.selectedRow;
    if (row < 0 || row >= (NSInteger)_versions.count) return;
    NSMenuItem* reveal = [[NSMenuItem alloc] initWithTitle:@"Show in Explorer" action:@selector(showVersionInExplorer:) keyEquivalent:@""];
    reveal.target = self; reveal.representedObject = _versions[row]; [menu addItem:reveal];
}
- (void)showVersionInExplorer:(NSMenuItem*)sender {
    NSDictionary* version = sender.representedObject; if (!version) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSDictionary* doc = [self currentDocument]; NSError* error = nil;
        NSURL* URL = SPDFCollectionVersionIsLatest(doc,version) && SPDFCollectionOriginalAvailable(doc) ?
            [NSURL fileURLWithPath:doc[@"path"]] :
            [self->_store materializeVersionID:version[@"id"] documentID:self->_documentID error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (URL) [self revealPath:URL.path]; else self->_status.stringValue = error.localizedDescription ?: @"Copy unavailable";
        });
    });
}
- (void)revealPath:(NSString*)path { SPDFMacRevealPath(path,SPDFMacCurrentFileExplorerPreference()); }
- (void)manage:(id)sender {
    (void)sender;
    if (self.manageHandler) self.manageHandler(_documentID);
}
@end
