#import "SPDFMacCollectionSavePanel.h"
#import "SPDFMacCollectionAvailability.h"
#import "SPDFMacCollectionHistory.h"
#import "SPDFMacCollectionStore.h"
#import "SPDFMacCollectionCompare.h"
#import "SPDFMacCollectionStyle.h"

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
    NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"version"]; column.width = 240;
    [_table addTableColumn:column];
    NSScrollView* scroll = [NSScrollView new]; scroll.documentView = _table;
    scroll.hasVerticalScroller = YES;
    _buttons = [NSMutableArray array];
    NSStackView* actions = [NSStackView stackViewWithViews:@[]];
    actions.orientation = NSUserInterfaceLayoutOrientationVertical; actions.alignment = NSLayoutAttributeLeading;
    NSArray* titles = @[@"Compare with Current",@"Compare with Previous",@"Save a Copy…",@"Keep Version",@"Manage Collection…"];
    NSArray* selectors = @[@"compareCurrent:",@"comparePrevious:",@"saveCopy:",@"keep:",@"manage:"];
    for (NSUInteger index = 0; index < titles.count; index++) {
        NSButton* button = [NSButton buttonWithTitle:titles[index] target:self action:NSSelectorFromString(selectors[index])];
        button.bezelStyle = NSBezelStyleRounded;
        [actions addArrangedSubview:button]; [_buttons addObject:button];
    }
    NSStackView* stack = [NSStackView stackViewWithViews:@[heading,_title,_status,scroll,actions]];
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
            self->_status.stringValue = [NSString stringWithFormat:@"%@\nSelect a version to open its read-only copy.",
                found[@"status"] ?: @"No saved versions yet"];
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
        if (i == 0) _buttons[i].enabled &= SPDFCollectionOriginalAvailable(_document);
        if (i == 1) _buttons[i].enabled &= _table.selectedRow+1 < (NSInteger)_versions.count;
        if (i < 2) _buttons[i].enabled &= ![version[@"encrypted"] boolValue];
        if (i == 3) _buttons[i].title = [version[@"keep"] boolValue] ? @"Unkeep Version" : @"Keep Version";
    }
}
- (void)tableViewSelectionDidChange:(NSNotification*)note {
    (void)note; [self updateActions];
    NSDictionary* version = [self selectedVersion]; if (!version || _restoringSelection) return;
    NSUInteger generation = ++_previewGeneration;
    [self materialize:version completion:^(NSURL* URL) {
        if (generation == self->_previewGeneration) self->_open(URL.path,YES);
    }];
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
    if (!previous && !SPDFCollectionOriginalAvailable(_document)) { [self manage:nil]; return; }
    NSInteger row = _table.selectedRow;
    if (previous && row+1 >= (NSInteger)_versions.count) return;
    NSDictionary* oldVersion = previous ? _versions[row+1] : selected;
    NSString* path = _document[@"path"];
    NSString* title = _document[@"title"] ?: @"Document";
    [self materialize:oldVersion completion:^(NSURL* oldURL) {
        void (^show)(NSURL*) = ^(NSURL* newURL) {
            NSString* (^label)(NSDictionary*) = ^NSString*(NSDictionary* version) {
                NSString* date = [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:
                    [version[@"capturedAt"] doubleValue]] dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle];
                return [NSString stringWithFormat:@"%@ · %@",title,date];
            };
            SPDFMacShowCollectionComparison(oldURL,newURL,label(oldVersion),previous ? label(selected) :
                [title stringByAppendingString:@" · Current original"],self.view.window);
        };
        if (previous) [self materialize:selected completion:show]; else show([NSURL fileURLWithPath:path]);
    }];
}
- (void)compareCurrent:(id)sender { (void)sender; [self compare:NO]; }
- (void)comparePrevious:(id)sender { (void)sender; [self compare:YES]; }
- (void)saveCopy:(id)sender {
    (void)sender; NSDictionary* version = [self selectedVersion]; if (!version) return;
    NSSavePanel* panel = [NSSavePanel savePanel]; SPDFCollectionConfigureSavePanel(panel, _document[@"path"]);
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
            NSError* error = nil;
            [self->_store exportVersionID:version[@"id"] documentID:self->_documentID toURL:panel.URL error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) [self.view.window presentError:error]; else self->_open(panel.URL.path,NO);
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
- (void)manage:(id)sender {
    (void)sender;
    if (self.manageHandler) self.manageHandler(_documentID);
}
@end
