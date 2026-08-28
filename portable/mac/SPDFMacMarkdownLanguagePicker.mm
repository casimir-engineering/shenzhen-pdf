#import "SPDFMacMarkdownLanguagePicker.h"

#import "markdown/SPDFMarkdownLanguage.h"

static const CGFloat kSPDFLanguagePickerWidth = 240.0;
static const CGFloat kSPDFLanguagePickerHeight = 300.0;

@interface SPDFMacMarkdownLanguagePickerController () <NSTableViewDataSource,
                                                       NSTableViewDelegate,
                                                       NSSearchFieldDelegate,
                                                       NSPopoverDelegate>
@end

@implementation SPDFMacMarkdownLanguagePickerController {
    SPDFMarkdownLanguagePickerModel* _model;
    NSSearchField* _searchField;
    NSTableView* _tableView;
    NSPopover* _popover;
    void (^_completion)(SPDFMarkdownLanguage*);
}

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (!self) return nil;
    _model = [SPDFMarkdownLanguagePickerModel new];
    (void)self.view; // keep the keyboard/model machinery usable before any presentation
    return self;
}

- (void)loadView {
    NSView* content =
        [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kSPDFLanguagePickerWidth, kSPDFLanguagePickerHeight)];
    _searchField = [[NSSearchField alloc] init];
    _searchField.placeholderString = @"Search languages";
    _searchField.delegate = self;
    _searchField.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_searchField];

    NSScrollView* scroll = [[NSScrollView alloc] init];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = NO;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:scroll];
    _tableView = [[NSTableView alloc] init];
    _tableView.headerView = nil;
    _tableView.rowHeight = 24.0;
    _tableView.backgroundColor = NSColor.clearColor;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.target = self;
    _tableView.action = @selector(tableClicked:);
    _tableView.doubleAction = @selector(acceptSelection:);
    NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"language"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_tableView addTableColumn:column];
    scroll.documentView = _tableView;

    [NSLayoutConstraint activateConstraints:@[
        [_searchField.topAnchor constraintEqualToAnchor:content.topAnchor constant:8],
        [_searchField.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:8],
        [_searchField.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8],
        [scroll.topAnchor constraintEqualToAnchor:_searchField.bottomAnchor constant:6],
        [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-4],
    ]];
    self.preferredContentSize = NSMakeSize(kSPDFLanguagePickerWidth, kSPDFLanguagePickerHeight);
    self.view = content;
}

- (NSArray<SPDFMarkdownLanguage*>*)visibleLanguages { return _model.filteredLanguages; }
- (NSInteger)selectedIndex { return _model.selectedIndex; }

- (void)presentFromView:(NSView*)view
             anchorRect:(NSRect)anchorRect
             completion:(void (^)(SPDFMarkdownLanguage*))completion {
    if (!view || !completion) return;
    if (_completion) [self finishWithLanguage:nil]; // a pending presentation resolves before re-arming
    _completion = [completion copy];
    [self updateQuery:@""];
    // Without a window there is nothing to anchor to (headless tests); the
    // keyboard machinery still drives the armed completion.
    if (!view.window) return;
    if (!_popover) {
        _popover = [NSPopover new];
        _popover.behavior = NSPopoverBehaviorTransient;
        _popover.delegate = self;
        _popover.contentViewController = self;
        _popover.contentSize = NSMakeSize(kSPDFLanguagePickerWidth, kSPDFLanguagePickerHeight);
    }
    [_popover showRelativeToRect:(NSIsEmptyRect(anchorRect) ? view.bounds : anchorRect)
                          ofView:view
                   preferredEdge:NSRectEdgeMaxY];
    [_searchField.window makeFirstResponder:_searchField];
}

- (void)finishWithLanguage:(SPDFMarkdownLanguage*)language {
    void (^completion)(SPDFMarkdownLanguage*) = _completion;
    _completion = nil; // popoverDidClose: re-enters finishWithLanguage: with nothing left to fire
    if (_popover.isShown) [_popover close];
    if (completion) completion(language);
}

// NSPopoverDelegate: clicking outside a transient popover (or Esc) closes it
// without going through cancel:, so a still-pending completion resolves to nil
// here — exactly once, because finishWithLanguage: clears it first.
- (void)popoverDidClose:(NSNotification*)notification {
    (void)notification;
    [self finishWithLanguage:nil];
    // Break the popover <-> contentViewController retain cycle between
    // presentations; presentFromView: rebuilds the popover on demand.
    _popover.contentViewController = nil;
    _popover = nil;
}

- (void)acceptSelection:(id)sender {
    (void)sender;
    SPDFMarkdownLanguage* language = _model.selectedLanguage;
    if (language) [self finishWithLanguage:language];
    else NSBeep();
}

- (void)cancel:(id)sender {
    (void)sender;
    [self finishWithLanguage:nil];
}

- (void)tableClicked:(id)sender {
    (void)sender;
    NSInteger row = _tableView.clickedRow;
    if (row < 0 || row >= (NSInteger)_model.filteredLanguages.count) return;
    _model.selectedIndex = row;
    [self acceptSelection:nil];
}

- (void)updateQuery:(NSString*)query {
    _model.query = query ?: @"";
    if (![_searchField.stringValue isEqualToString:_model.query]) _searchField.stringValue = _model.query;
    [_tableView reloadData];
    [self syncTableSelection];
}

- (void)syncTableSelection {
    if (_model.selectedIndex >= 0) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)_model.selectedIndex]
               byExtendingSelection:NO];
        [_tableView scrollRowToVisible:_model.selectedIndex];
    } else [_tableView deselectAll:nil];
}

- (BOOL)handleCommandSelector:(SEL)selector {
    if (selector == @selector(moveDown:)) [_model moveSelectionBy:1];
    else if (selector == @selector(moveUp:)) [_model moveSelectionBy:-1];
    else if (selector == @selector(pageDown:)) [_model moveSelectionByPage:1 visibleRowCount:6];
    else if (selector == @selector(pageUp:)) [_model moveSelectionByPage:-1 visibleRowCount:6];
    else if (selector == @selector(moveToBeginningOfDocument:)) [_model selectFirst];
    else if (selector == @selector(moveToEndOfDocument:)) [_model selectLast];
    else if (selector == @selector(insertNewline:) || selector == @selector(insertNewlineIgnoringFieldEditor:)) {
        [self acceptSelection:nil];
        return YES;
    } else if (selector == @selector(cancelOperation:)) {
        [self cancel:nil];
        return YES;
    } else return NO;
    [self syncTableSelection];
    return YES;
}

- (void)controlTextDidChange:(NSNotification*)notification {
    if (notification.object == _searchField) [self updateQuery:_searchField.stringValue];
}

- (BOOL)control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)selector {
    (void)textView;
    return control == _searchField && [self handleCommandSelector:selector];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    (void)tableView;
    return (NSInteger)_model.filteredLanguages.count;
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
    (void)column;
    NSTextField* field = [tableView makeViewWithIdentifier:@"language" owner:self];
    if (!field) {
        field = [NSTextField labelWithString:@""];
        field.identifier = @"language";
        field.font = [NSFont systemFontOfSize:13];
    }
    SPDFMarkdownLanguage* language = _model.filteredLanguages[(NSUInteger)row];
    field.stringValue = language.displayName;
    field.toolTip = language.identifier;
    return field;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
    if (notification.object == _tableView && _tableView.selectedRow >= 0)
        _model.selectedIndex = _tableView.selectedRow;
}

@end
