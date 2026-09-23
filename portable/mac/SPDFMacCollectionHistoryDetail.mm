#import "SPDFMacCollectionHistoryDetail.h"
#import "SPDFMacCollectionStore.h"
#import "SPDFMacCollectionCompare.h"
#import "SPDFMacCollectionAvailability.h"
#import "SPDFMacCollectionPreviewSearch.h"
#import "SPDFMacCollectionStyle.h"

static NSOperationQueue* HistoryPreferenceQueue(void) {
    static NSOperationQueue* queue; static dispatch_once_t once;
    dispatch_once(&once,^{ queue=[NSOperationQueue new]; queue.maxConcurrentOperationCount=1; });
    return queue;
}
static NSString* CaptureDate(NSDictionary* version) {
    return [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:
        [version[@"capturedAt"] doubleValue]] dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle];
}
static NSTextField* Label(NSString* text, CGFloat size) {
    return SPDFCollectionText(text,size,NSFontWeightRegular,NO);
}
@interface SPDFCollectionHistoryPDFView : PDFView
@end
@implementation SPDFCollectionHistoryPDFView
- (void)setFrameSize:(NSSize)size {
    BOOL changed=!NSEqualSizes(size,self.frame.size);
    PDFDestination* anchor=changed ? self.currentDestination : nil;
    PDFSelection* match=changed ? self.highlightedSelections.firstObject : nil;
    [super setFrameSize:size];
    if (anchor) {
        [self layoutDocumentView];
        if (match) [self goToSelection:match]; else [self goToDestination:anchor];
    }
}
@end
@interface SPDFCollectionHistoryRow : NSTableRowView
@end
@implementation SPDFCollectionHistoryRow
- (void)drawBackgroundInRect:(NSRect)dirty { [SPDFCollectionColor(@"window") setFill]; NSRectFill(dirty); }
- (void)drawSelectionInRect:(NSRect)dirty {
    (void)dirty; [SPDFCollectionColor(@"selected") setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,3) xRadius:5 yRadius:5] fill];
}
@end
@implementation SPDFMacCollectionHistoryDetailController {
    SPDFMacCollectionStore* _store;
    NSDictionary* _document;
    NSString* _selectedID;
    NSArray<NSDictionary*>* _versions;
    PDFView* _reader;
    NSTableView* _table;
    NSButton* _keepButton;
    NSTextField* _protection;
    NSTextField* _title;
    NSTextField* _summary;
    NSTextField* _identity;
    NSTextField* _status;
    NSTextField* _pageField;
    NSTextField* _pageCount;
    NSArray<NSButton*>* _actions;
    NSButton* _actionMenu;
    NSOperationQueue* _work;
    NSOperationQueue* _preferences;
    NSProgress* _previewProgress;
    NSUInteger _generation;
    NSUInteger _page;
    BOOL _restoringSelection;
    BOOL _mutating;
    BOOL _invalidated;
    __weak id _actionTarget;
}
- (instancetype)initWithStore:(SPDFMacCollectionStore*)store document:(NSDictionary*)document
                      version:(NSDictionary*)version page:(NSUInteger)page actionTarget:(id)target {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    _store = store; _document = document; _selectedID = version[@"id"];
    _versions = [[document[@"versions"] reverseObjectEnumerator] allObjects] ?: @[];
    if (!_selectedID.length) _selectedID = _versions.firstObject[@"id"];
    _page = MAX(1,page); _actionTarget = target;
    _work = [NSOperationQueue new]; _work.maxConcurrentOperationCount = 1;
    _work.qualityOfService = NSQualityOfServiceUserInitiated;
    _preferences = HistoryPreferenceQueue();
    return self;
}
- (void)dealloc { [_previewProgress cancel]; [_work cancelAllOperations]; [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)invalidate {
    _invalidated=YES; ++_generation; [_previewProgress cancel]; [_work cancelAllOperations];
    _reader.document=nil;
}
- (NSDictionary*)document { return _document; }
- (PDFView*)reader { return _reader; }
- (NSTableView*)table { return _table; }
- (NSButton*)keepButton { return _keepButton; }
- (NSTextField*)protection { return _protection; }
- (NSDictionary*)selectedVersion {
    for (NSDictionary* version in _versions) if ([version[@"id"] isEqual:_selectedID]) return version;
    return nil;
}
- (void)loadView {
    // AppKit can select row zero as soon as empty selection is forbidden.
    // Suppress that construction callback until the requested version is restored.
    _restoringSelection=YES;
    self.view = SPDFCollectionSurface(@"window"); self.view.frame=NSMakeRect(0,0,880,640);
    NSButton* back = SPDFCollectionButton(@"‹ Back to Documents",self,@selector(goBack:),@"normal");
    back.keyEquivalent=@"\e"; back.keyEquivalentModifierMask=0;
    _title = Label(_document[@"title"] ?: @"Document history",16);
    _title.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
    _summary = Label(@"",12); _summary.textColor=SPDFCollectionColor(@"secondary");
    _table = [NSTableView new]; _table.headerView = nil; _table.rowHeight = 82; _table.backgroundColor=SPDFCollectionColor(@"window");
    _table.intercellSpacing=NSMakeSize(0,5);
    _table.columnAutoresizingStyle=NSTableViewLastColumnOnlyAutoresizingStyle;
    _table.dataSource = self; _table.delegate = self; _table.allowsEmptySelection = NO;
    [_table setAccessibilityLabel:@"Saved versions"];
    NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"version"];
    column.width = 205; column.minWidth=0; column.resizingMask=NSTableColumnAutoresizingMask;
    [_table addTableColumn:column];
    NSScrollView* versions = [NSScrollView new]; versions.hasVerticalScroller = YES; versions.drawsBackground=NO;
    versions.documentView = _table; [versions.widthAnchor constraintEqualToConstant:225].active = YES;
    _identity = Label(@"",12); _identity.textColor=SPDFCollectionColor(@"secondary");
    _keepButton = [NSButton checkboxWithTitle:@"Keep this version" target:self action:@selector(changeKeep:)];
    _protection = Label(@"",12); _protection.textColor = SPDFCollectionColor(@"secondary");
    _pageField = [NSTextField textFieldWithString:[NSString stringWithFormat:@"%lu",(unsigned long)_page]];
    [_pageField.widthAnchor constraintEqualToConstant:52].active = YES;
    [_pageField setAccessibilityLabel:@"History preview page"];
    _pageField.target = self; _pageField.action = @selector(changePage:);
    _pageCount = Label(@"/ —",12);
    NSView* spacer=[NSView new];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView* controls = [NSStackView stackViewWithViews:@[Label(@"Page",12),_pageField,_pageCount,spacer,_keepButton]];
    controls.spacing = 8; controls.distribution=NSStackViewDistributionFill;
    _reader = [SPDFCollectionHistoryPDFView new]; _reader.autoScales = YES;
    _reader.displayMode = kPDFDisplaySinglePageContinuous; _reader.backgroundColor = SPDFCollectionColor(@"window");
    [_reader setAccessibilityLabel:@"Read-only saved version preview"];
    _status = Label(@"Preparing saved copy…",12); _status.textColor=SPDFCollectionColor(@"secondary");
    NSMutableArray* actions = [NSMutableArray array];
    NSArray* titles = @[@"Compare with Current",@"Compare with Previous",@"Save a Copy…"];
    NSArray* selectors = @[@"compareCurrent:",@"comparePrevious:",@"exportCopy:"];
    for (NSUInteger i=0;i<titles.count;i++) {
        NSButton* button = [NSButton buttonWithTitle:titles[i] target:_actionTarget
            action:NSSelectorFromString(selectors[i])]; [actions addObject:button];
    }
    _actions = actions;
    _actionMenu=SPDFCollectionButton(@"Actions ▾",self,@selector(showActions:),@"normal");
    NSView* topSpace=[NSView new];
    [topSpace setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView* top=[NSStackView stackViewWithViews:@[back,topSpace,_actionMenu]];
    top.distribution=NSStackViewDistributionFill;
    NSStackView* detail = [NSStackView stackViewWithViews:@[Label(@"Read-only preview",15),_identity,
        controls,_protection,_reader,_status]];
    detail.distribution=NSStackViewDistributionFill;
    detail.orientation = NSUserInterfaceLayoutOrientationVertical;
    detail.alignment = NSLayoutAttributeLeading; detail.spacing = 10;
    detail.edgeInsets=NSEdgeInsetsMake(0,20,0,0);
    NSView* divider=SPDFCollectionSurface(@"line"); divider.translatesAutoresizingMaskIntoConstraints=NO;
    [detail addSubview:divider];
    [NSLayoutConstraint activateConstraints:@[[divider.widthAnchor constraintEqualToConstant:1],
        [divider.leadingAnchor constraintEqualToAnchor:detail.leadingAnchor],
        [divider.topAnchor constraintEqualToAnchor:detail.topAnchor],
        [divider.bottomAnchor constraintEqualToAnchor:detail.bottomAnchor]]];
    NSStackView* content = [NSStackView stackViewWithViews:@[versions,detail]];
    content.distribution=NSStackViewDistributionFill;
    content.alignment = NSLayoutAttributeTop; content.spacing = 20;
    NSStackView* root = [NSStackView stackViewWithViews:@[top,_title,_summary,content]];
    root.distribution=NSStackViewDistributionFill;
    root.orientation = NSUserInterfaceLayoutOrientationVertical; root.alignment = NSLayoutAttributeLeading;
    root.spacing = 12; root.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [root.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [root.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:14],
        [root.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-14],
        [top.widthAnchor constraintEqualToAnchor:root.widthAnchor],
        [_title.widthAnchor constraintEqualToAnchor:root.widthAnchor],
        [_summary.widthAnchor constraintEqualToAnchor:root.widthAnchor],
        [content.widthAnchor constraintEqualToAnchor:root.widthAnchor],
        [versions.heightAnchor constraintEqualToAnchor:content.heightAnchor],
        [detail.heightAnchor constraintEqualToAnchor:content.heightAnchor],
        [controls.widthAnchor constraintEqualToAnchor:detail.widthAnchor constant:-20],
        [_identity.widthAnchor constraintEqualToAnchor:detail.widthAnchor constant:-20],
        [_protection.widthAnchor constraintEqualToAnchor:detail.widthAnchor constant:-20],
        [_reader.widthAnchor constraintEqualToAnchor:detail.widthAnchor constant:-20],
        [_reader.heightAnchor constraintGreaterThanOrEqualToConstant:180],
        [_status.widthAnchor constraintEqualToAnchor:detail.widthAnchor constant:-20]]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(pageChanged:)
        name:PDFViewPageChangedNotification object:_reader];
    [self refreshMetadata]; [self loadPreview];
}
- (void)refreshMetadata {
    _title.stringValue = _document[@"title"] ?: @"Document history";
    NSNumber* opened = _document[@"lastOpenedAt"];
    NSString* last = opened ? [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:opened.doubleValue]
        dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle] : @"Not recorded";
    _summary.stringValue = [NSString stringWithFormat:@"%lu saved %@ · %@\nOpened %@ times · Last opened %@",
        (unsigned long)_versions.count,_versions.count==1 ? @"version" : @"versions",SPDFCollectionOriginalAvailable(_document) ? @"Original available" : @"Original missing",
        _document[@"openCount"] ?: @0,last];
    _summary.toolTip = @"Only explicit opens count. Previews, searches, indexing and session restoration do not count.";
    _restoringSelection = YES; [_table reloadData];
    NSUInteger row = [_versions indexOfObjectPassingTest:^BOOL(NSDictionary* v,NSUInteger i,BOOL* stop) {
        (void)i;(void)stop; return [v[@"id"] isEqual:self->_selectedID];
    }];
    if (row != NSNotFound) [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    _restoringSelection = NO;
    NSDictionary* version = self.selectedVersion;
    _identity.stringValue = version ? [NSString stringWithFormat:@"Captured %@ · %@\n%@",CaptureDate(version),
        [version[@"id"] isEqual:_versions.firstObject[@"id"]] ? @"Latest copy" : @"Earlier version",
        version[@"reason"] ?: @"Saved copy"] : @"No saved versions";
    _keepButton.enabled = version != nil && !_mutating;
    _keepButton.state = [version[@"keep"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    BOOL anyKept = NO;
    for (NSDictionary* item in _versions) anyKept |= [item[@"keep"] boolValue];
    _protection.stringValue = [version[@"keep"] boolValue]
        ? @"Keeping this version protects the document’s entire history from automatic cleanup."
        : anyKept ? @"Keep protects the entire history. Another kept version currently protects this document."
        : @"Keep protects the entire history. No version is kept; automatic cleanup can remove copies when a limit is set.";
    _keepButton.accessibilityHelp = _protection.stringValue;
    for (NSButton* button in _actions) button.enabled = version != nil;
    _actions[0].enabled = version && ![version[@"encrypted"] boolValue] && SPDFCollectionOriginalAvailable(_document);
    _actions[1].enabled = version && ![version[@"encrypted"] boolValue] && row != NSNotFound && row+1<_versions.count;
    if (self.selectionChanged) self.selectionChanged();
}
- (void)showActions:(NSButton*)sender {
    NSMenu* menu=[NSMenu new]; menu.autoenablesItems=NO;
    for (NSButton* button in _actions) {
        NSMenuItem* item=[[NSMenuItem alloc] initWithTitle:button.title action:button.action keyEquivalent:@""];
        item.target=button.target; item.enabled=button.enabled; [menu addItem:item];
    }
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0,NSHeight(sender.bounds)+3) inView:sender];
}
- (NSTableRowView*)tableView:(NSTableView*)table rowViewForRow:(NSInteger)row {
    (void)table;(void)row; return [SPDFCollectionHistoryRow new];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView*)table { (void)table; return _versions.count; }
- (NSView*)tableView:(NSTableView*)table viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
    (void)table;(void)column; NSDictionary* v = _versions[(NSUInteger)row];
    NSString* text = [NSString stringWithFormat:@"%@\n%@%@ · %@\n%@",CaptureDate(v),row==0?@"Latest copy":@"Earlier version",
        [v[@"keep"] boolValue]?@" · Kept":@"",[NSByteCountFormatter stringFromByteCount:[v[@"size"] longLongValue]
            countStyle:NSByteCountFormatterCountStyleFile],v[@"reason"]?:@"Saved version"];
    NSView* cell=[NSView new];
    NSTextField* label = Label(text,12); label.accessibilityLabel = text;
    label.translatesAutoresizingMaskIntoConstraints=NO; [cell addSubview:label];
    NSMutableAttributedString* caption=[[NSMutableAttributedString alloc] initWithString:text];
    [caption addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:12 weight:NSFontWeightSemibold]
        range:NSMakeRange(0,CaptureDate(v).length)]; label.attributedStringValue=caption;
    [NSLayoutConstraint activateConstraints:@[[label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:10],
        [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-10],
        [label.topAnchor constraintEqualToAnchor:cell.topAnchor constant:10]]];
    return cell;
}
- (void)tableViewSelectionDidChange:(NSNotification*)notification {
    (void)notification; if (_restoringSelection || _table.selectedRow<0) return;
    [self selectVersionID:_versions[(NSUInteger)_table.selectedRow][@"id"]];
}
- (void)selectVersionID:(NSString*)identifier {
    if ([_selectedID isEqual:identifier]) return;
    _selectedID = [identifier copy]; _page = 1;
    [self refreshMetadata]; [self loadPreview];
}
- (void)persistSelection {
    if (_invalidated || !_selectedID) return;
    NSDictionary* state = @{@"managerHistoryDocumentID":_document[@"id"],@"managerHistoryVersionID":_selectedID,
                            @"managerHistoryPage":@(_page)};
    SPDFMacCollectionStore* store = _store;
    [_preferences addOperationWithBlock:^{ [store updateSettings:state error:nil]; }];
}
- (void)loadPreview {
    [_previewProgress cancel]; [_work cancelAllOperations];
    NSUInteger generation = ++_generation; NSDictionary* version = self.selectedVersion;
    _reader.document = nil; _pageField.enabled = NO; _pageCount.stringValue = @"/ —";
    if (!version) { _status.stringValue = @"No saved version is available."; return; }
    _status.stringValue = @"Preparing read-only preview…";
    _previewProgress = [NSProgress progressWithTotalUnitCount:1]; NSProgress* progress = _previewProgress;
    [self persistSelection];
    [_work addOperationWithBlock:^{
        @autoreleasepool {
            NSError* error = nil;
            NSURL* URL = [self->_store materializeVersionID:version[@"id"] documentID:self->_document[@"id"] error:&error];
            PDFDocument* pdf = URL && !progress.cancelled ? SPDFCollectionLoadPreviewDocument(URL,progress,&error) : nil;
            // Widgets and annotations stay non-editable in this private in-memory preview.
            for (NSUInteger index=0;index<pdf.pageCount && !progress.cancelled;index++)
                for (PDFAnnotation* annotation in [pdf pageAtIndex:index].annotations) annotation.readOnly=YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self->_invalidated || generation!=self->_generation || progress.cancelled) return;
                NSUInteger requestedPage = self->_page;
                self->_reader.document = pdf;
                self->_status.stringValue = error.localizedDescription ?: (pdf ? @"Saved copy · Read-only · Original unchanged" : @"Preview unavailable");
                self->_pageField.enabled = pdf.pageCount>0;
                self->_pageCount.stringValue = [NSString stringWithFormat:@"/ %lu",(unsigned long)pdf.pageCount];
                if (pdf.pageCount) {
                    self->_page = MIN(MAX(1,requestedPage),pdf.pageCount);
                    [self->_reader goToPage:[pdf pageAtIndex:self->_page-1]];
                    self->_pageField.integerValue = self->_page;
                }
            });
        }
    }];
}
- (void)pageChanged:(NSNotification*)notification {
    (void)notification;
    if (!_reader.document || !_reader.currentPage) return;
    NSUInteger index = [_reader.document indexForPage:_reader.currentPage];
    if (index==NSNotFound) return;
    _page = index+1; _pageField.integerValue = _page; [self persistSelection];
    [self highlightQuery];
}
- (void)highlightQuery {
    NSMutableArray* highlights = [NSMutableArray array];
    PDFPage* page = _reader.currentPage; NSString* text = page.string;
    for (NSValue* value in SPDFCollectionPreviewMatchRanges(text,self.searchQuery)) {
        PDFSelection* selection = [page selectionForRange:value.rangeValue];
        if (selection) { selection.color=NSColor.systemYellowColor; [highlights addObject:selection]; }
    }
    _reader.highlightedSelections = highlights;
}
- (void)changePage:(id)sender {
    (void)sender; if (!_reader.document.pageCount) return;
    _page = MIN((NSUInteger)MAX(1,_pageField.integerValue),_reader.document.pageCount);
    [_reader goToPage:[_reader.document pageAtIndex:_page-1]];
    _pageField.integerValue = _page; [self persistSelection];
}
- (void)changeKeep:(id)sender {
    (void)sender; NSDictionary* version = self.selectedVersion; if (!version || _mutating) return;
    _mutating = YES; _keepButton.enabled = NO;
    BOOL keep = _keepButton.state==NSControlStateValueOn; NSString* documentID = _document[@"id"];
    // Selection cancels preview work, never a committed Keep mutation.
    [_preferences addOperationWithBlock:^{
        NSError* error = nil;
        [self->_store setKeep:keep versionID:version[@"id"] documentID:documentID error:&error];
        NSDictionary* found = nil;
        for (NSDictionary* doc in self->_store.documents) if ([doc[@"id"] isEqual:documentID]) { found = doc; break; }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->_invalidated) return;
            self->_mutating = NO;
            if (found) { self->_document = found; self->_versions = [[found[@"versions"] reverseObjectEnumerator] allObjects]; }
            [self refreshMetadata]; [self.view.window makeFirstResponder:self->_keepButton];
            if (error) self->_status.stringValue = error.localizedDescription;
            NSAccessibilityPostNotificationWithUserInfo(self->_protection,NSAccessibilityAnnouncementRequestedNotification,
                @{NSAccessibilityAnnouncementKey:self->_protection.stringValue,
                  NSAccessibilityPriorityKey:@(NSAccessibilityPriorityMedium)});
        });
    }];
}
- (void)reload {
    NSString* documentID = _document[@"id"];
    [_work addOperationWithBlock:^{
        NSDictionary* found = nil;
        for (NSDictionary* doc in self->_store.documents) if ([doc[@"id"] isEqual:documentID]) { found=doc;break; }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->_invalidated || !found) return;
            self->_document=found;self->_versions=[[found[@"versions"] reverseObjectEnumerator] allObjects];
            if (!self.selectedVersion) self->_selectedID=self->_versions.firstObject[@"id"];
            [self refreshMetadata];
        });
    }];
}
- (void)goBack:(id)sender { (void)sender; if(self.back)self.back(); }
@end
