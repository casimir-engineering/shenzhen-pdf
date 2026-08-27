#import "SPDFMacMarkdownLanguagePicker.h"

#import "markdown/SPDFMarkdownLanguage.h"

@interface SPDFMacMarkdownLanguagePickerController () <NSTableViewDataSource,
                                                       NSTableViewDelegate,
                                                       NSSearchFieldDelegate>
@end

@implementation SPDFMacMarkdownLanguagePickerController {
    SPDFMarkdownLanguagePickerModel* _model;
    NSSearchField* _searchField;
    NSTableView* _tableView;
    void (^_completion)(SPDFMarkdownLanguage*);
    __weak NSWindow* _parentWindow;
}

- (instancetype)init {
    NSPanel* panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 360, 290)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    self = [super initWithWindow:panel];
    if (!self) return nil;
    _model = [SPDFMarkdownLanguagePickerModel new];
    panel.title = @"Code Language";
    panel.releasedWhenClosed = NO;
    [self buildContent];
    return self;
}

- (void)buildContent {
    NSView* content = self.window.contentView;
    _searchField = [[NSSearchField alloc] init];
    _searchField.placeholderString = @"Search languages";
    _searchField.delegate = self;
    _searchField.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_searchField];

    NSScrollView* scroll = [[NSScrollView alloc] init];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:scroll];
    _tableView = [[NSTableView alloc] init];
    _tableView.headerView = nil;
    _tableView.rowHeight = 30.0;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.target = self;
    _tableView.doubleAction = @selector(acceptSelection:);
    NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"language"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_tableView addTableColumn:column];
    scroll.documentView = _tableView;

    NSButton* cancel = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];
    cancel.translatesAutoresizingMaskIntoConstraints = NO;
    cancel.keyEquivalent = @"\e";
    [content addSubview:cancel];
    NSButton* choose = [NSButton buttonWithTitle:@"Choose" target:self action:@selector(acceptSelection:)];
    choose.translatesAutoresizingMaskIntoConstraints = NO;
    choose.keyEquivalent = @"\r";
    [content addSubview:choose];

    [NSLayoutConstraint activateConstraints:@[
        [_searchField.topAnchor constraintEqualToAnchor:content.topAnchor constant:16],
        [_searchField.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [_searchField.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [scroll.topAnchor constraintEqualToAnchor:_searchField.bottomAnchor constant:10],
        [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [scroll.bottomAnchor constraintEqualToAnchor:cancel.topAnchor constant:-14],
        [cancel.leadingAnchor constraintGreaterThanOrEqualToAnchor:content.leadingAnchor constant:16],
        [cancel.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-14],
        [choose.leadingAnchor constraintEqualToAnchor:cancel.trailingAnchor constant:8],
        [choose.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [choose.centerYAnchor constraintEqualToAnchor:cancel.centerYAnchor],
    ]];
}

- (NSArray<SPDFMarkdownLanguage*>*)visibleLanguages { return _model.filteredLanguages; }
- (NSInteger)selectedIndex { return _model.selectedIndex; }

- (void)presentForWindow:(NSWindow*)window completion:(void (^)(SPDFMarkdownLanguage*))completion {
    if (!window || !completion) return;
    _completion = [completion copy];
    _parentWindow = window;
    [self updateQuery:@""];
    [window beginSheet:self.window completionHandler:nil];
    [self.window makeFirstResponder:_searchField];
}

- (void)finish:(SPDFMarkdownLanguage*)language {
    void (^completion)(SPDFMarkdownLanguage*) = _completion;
    _completion = nil;
    NSWindow* parent = _parentWindow;
    if (parent && self.window.sheetParent == parent) [parent endSheet:self.window];
    else [self.window orderOut:nil];
    if (completion) completion(language);
}

- (void)acceptSelection:(id)sender {
    (void)sender;
    SPDFMarkdownLanguage* language = _model.selectedLanguage;
    if (language) [self finish:language];
    else NSBeep();
}

- (void)cancel:(id)sender {
    (void)sender;
    [self finish:nil];
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
