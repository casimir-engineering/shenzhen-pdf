#import "SPDFMacWorkspaceChrome.h"
#import "SPDFMacMarkdownDelegatePrivate.h"
#import "SPDFMacSidebarModeControl.h"
#import "SPDFMacSidebarWorkspace.h"
#import "SPDFMacCollectionIntegration.h"
#import "SPDFMacCollectionStyle.h"
#import <objc/runtime.h>

// One compact header per column. The renderer and real minimap retain their
// existing hosts; only the chrome is moved, so no page coordinates change.
static char chromeKey;
@interface SPDFWorkspaceChromeState : NSObject
@property NSView* mapHeader;
@property NSView* searchControls;
@property NSButton* command;
@property NSButton* collection;
@property NSButton* print;
@property NSButton* previous;
@property NSButton* next;
@property NSLayoutConstraint* toolbarRight;
@property NSView* footer;
@property NSTextField* pageStatus;
@property NSLayoutConstraint* splitBottom;
@property NSStackView* primaryRow;
@property NSStackView* headerRow;
@property NSStackView* toolsRow;
@property NSArray<NSView*>* tools;
@property BOOL wrapped;
@end
@implementation SPDFWorkspaceChromeState
@end

static NSButton* Icon(NSString* symbol, NSString* title, id target, SEL action) {
    NSImage* image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
    [image setTemplate:YES];
    NSButton* button = [NSButton buttonWithImage:image target:target action:action];
    button.bordered = NO; button.toolTip = title; button.accessibilityLabel = title;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.widthAnchor constraintEqualToConstant:28].active = YES;
    [button.heightAnchor constraintEqualToConstant:28].active = YES;
    return button;
}
@interface ShenzhenMacDelegate (WorkspaceActions)
- (void)showFavoritesPalette:(id)sender;
- (void)printDocument:(id)sender;
- (void)toggleSidebar:(id)sender;
- (void)toggleMinimap:(id)sender;
- (void)previousPage:(id)sender;
- (void)nextPage:(id)sender;
@end
@implementation ShenzhenMacDelegate (SPDFMacWorkspaceChrome)
- (void)installWorkspaceChrome {
    SPDFWorkspaceChromeState* state = [SPDFWorkspaceChromeState new];
    objc_setAssociatedObject(self,&chromeKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SPDFSidebarNavigationControl* navigation = (id)_sidebarModeControl;
    [navigation setCollapseTarget:self action:@selector(toggleSidebar:)];
    _window.backgroundColor = SPDFCollectionColor(@"titlebar");
    for (NSView* host in @[_sidebarContainer,_toolbar]) {
        NSView* surface = SPDFCollectionSurface(@"window"); surface.translatesAutoresizingMaskIntoConstraints = NO;
        [host addSubview:surface positioned:NSWindowBelow relativeTo:nil];
        [NSLayoutConstraint activateConstraints:@[[surface.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
            [surface.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
            [surface.topAnchor constraintEqualToAnchor:host.topAnchor],
            [surface.bottomAnchor constraintEqualToAnchor:host.bottomAnchor]]];
    }
    _sidebarTable.backgroundColor = NSColor.clearColor; _sidebarTable.enclosingScrollView.drawsBackground = NO;
    _toolbar.edgeInsets = NSEdgeInsetsMake(8,8,8,8); _toolbar.spacing = 4;
    // Replace the crowded global toolbar with document controls; Cmd+F's real
    // field now lives in the Find panel, keeping search state and its delegate.
    for (NSView* view in _toolbar.arrangedSubviews.copy) { [_toolbar removeArrangedSubview:view]; [view removeFromSuperview]; }
    _pageField.bordered = NO; _pageField.drawsBackground = NO;
    _pageField.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    for (NSLayoutConstraint* c in _pageField.constraints) if (c.firstAttribute == NSLayoutAttributeWidth) c.constant = 30;
    _fitModePopup.bordered = NO; _fitModePopup.font = [NSFont systemFontOfSize:12];
    _ocrButton.bordered = NO; _translateButton.bordered = NO;
    _readingThemeButton.segmentStyle = NSSegmentStyleSmallSquare;
    state.previous = Icon(@"chevron.left",@"Previous page",self,@selector(previousPage:));
    state.next = Icon(@"chevron.right",@"Next page",self,@selector(nextPage:));
    state.collection = Icon(@"books.vertical",@"Collection",self,@selector(showCollectionManager:));
    state.print = Icon(@"printer",@"Print document",self,@selector(printDocument:));
    state.primaryRow = [NSStackView stackViewWithViews:@[_sidebarToggleButton,state.previous,_pageField,_pageCountLabel,state.next,_fitModePopup,_toolbarSpacer]];
    state.tools = @[state.collection,_markdownFontSizeSegments,_readingThemeButton,_ocrButton,_translateButton,state.print,_minimapToggleButton];
    state.toolsRow = [NSStackView stackViewWithViews:state.tools];
    for (NSStackView* row in @[state.primaryRow,state.toolsRow]) {
        row.orientation = NSUserInterfaceLayoutOrientationHorizontal; row.alignment = NSLayoutAttributeCenterY;
        row.spacing = 4; row.translatesAutoresizingMaskIntoConstraints = NO;

    }
    state.headerRow = [NSStackView stackViewWithViews:@[state.primaryRow,state.toolsRow]];
    state.headerRow.spacing = 4; state.headerRow.alignment = NSLayoutAttributeCenterY;
    state.headerRow.translatesAutoresizingMaskIntoConstraints = NO;
    [_toolbar addArrangedSubview:state.headerRow];
    [state.headerRow.widthAnchor constraintEqualToAnchor:_toolbar.widthAnchor constant:-16].active = YES;
    _toolbar.orientation = NSUserInterfaceLayoutOrientationVertical; _toolbar.alignment = NSLayoutAttributeLeading;
    [state.primaryRow setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [state.toolsRow setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

    state.mapHeader = SPDFCollectionSurface(@"pane"); state.mapHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [_documentContainer addSubview:state.mapHeader];
    NSButton* closeMap = Icon(@"sidebar.right",@"Hide document map",self,@selector(toggleMinimap:));
    [state.mapHeader addSubview:closeMap];
    [NSLayoutConstraint activateConstraints:@[
        [state.mapHeader.topAnchor constraintEqualToAnchor:_documentContainer.topAnchor],
        [state.mapHeader.leadingAnchor constraintEqualToAnchor:_minimapView.leadingAnchor],
        [state.mapHeader.trailingAnchor constraintEqualToAnchor:_minimapView.trailingAnchor],
        [state.mapHeader.heightAnchor constraintEqualToConstant:44],
        [closeMap.centerXAnchor constraintEqualToAnchor:state.mapHeader.centerXAnchor],
        [closeMap.centerYAnchor constraintEqualToAnchor:state.mapHeader.centerYAnchor]]];
    state.toolbarRight = [_toolbar.trailingAnchor constraintEqualToAnchor:_minimapDividerView.leadingAnchor];
    state.toolbarRight.active = YES;

    state.command = Icon(@"magnifyingglass",@"Find documents, groups and text · ⌘K",self,@selector(showFavoritesPalette:));
    [_window.contentView addSubview:state.command];
    [NSLayoutConstraint activateConstraints:@[
        [state.command.trailingAnchor constraintEqualToAnchor:_window.contentView.trailingAnchor constant:-8],
        [state.command.centerYAnchor constraintEqualToAnchor:_tabStrip.centerYAnchor]]];

    state.searchControls = [NSView new]; state.searchControls.translatesAutoresizingMaskIntoConstraints = NO;
    [_sidebarContainer addSubview:state.searchControls];
    for (NSLayoutConstraint* c in _searchField.constraints.copy)
        if (c.firstAttribute == NSLayoutAttributeWidth) c.active = NO;
    _searchField.placeholderString = @"Find in document";
    [state.searchControls addSubview:_searchField];
    NSStackView* options = [NSStackView stackViewWithViews:@[_findRegexCheckbox,_findCountLabel,_findSegments]];
    options.spacing = 4; options.translatesAutoresizingMaskIntoConstraints = NO;
    [state.searchControls addSubview:options];
    [NSLayoutConstraint activateConstraints:@[
        [state.searchControls.leadingAnchor constraintEqualToAnchor:_sidebarContainer.leadingAnchor constant:12],
        [state.searchControls.trailingAnchor constraintEqualToAnchor:_sidebarContainer.trailingAnchor constant:-12],
        [state.searchControls.topAnchor constraintEqualToAnchor:_sidebarModeControl.bottomAnchor constant:4],
        [state.searchControls.heightAnchor constraintEqualToConstant:66],
        [_searchField.topAnchor constraintEqualToAnchor:state.searchControls.topAnchor],
        [_searchField.leadingAnchor constraintEqualToAnchor:state.searchControls.leadingAnchor],
        [_searchField.trailingAnchor constraintEqualToAnchor:state.searchControls.trailingAnchor],
        [_searchField.heightAnchor constraintEqualToConstant:28],
        [options.topAnchor constraintEqualToAnchor:_searchField.bottomAnchor constant:4],
        [options.leadingAnchor constraintEqualToAnchor:state.searchControls.leadingAnchor],
        [options.trailingAnchor constraintLessThanOrEqualToAnchor:state.searchControls.trailingAnchor]]];
    _sidebarScrollBelowModeConstraint.constant = 78;
    state.footer = SPDFCollectionSurface(@"pane"); state.footer.translatesAutoresizingMaskIntoConstraints = NO;
    [_window.contentView addSubview:state.footer];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.font = [NSFont systemFontOfSize:11]; _statusLabel.textColor = NSColor.secondaryLabelColor;
    [state.footer addSubview:_statusLabel];
    state.pageStatus = [NSTextField labelWithString:@""];
    state.pageStatus.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    state.pageStatus.textColor = NSColor.secondaryLabelColor;
    state.pageStatus.translatesAutoresizingMaskIntoConstraints = NO;
    [state.footer addSubview:state.pageStatus];
    for (NSLayoutConstraint* c in _window.contentView.constraints)
        if (c.firstItem == _splitView && c.firstAttribute == NSLayoutAttributeBottom) state.splitBottom = c;
    [NSLayoutConstraint activateConstraints:@[
        [state.footer.leadingAnchor constraintEqualToAnchor:_window.contentView.leadingAnchor],
        [state.footer.trailingAnchor constraintEqualToAnchor:_window.contentView.trailingAnchor],
        [state.footer.bottomAnchor constraintEqualToAnchor:_window.contentView.bottomAnchor],
        [state.footer.heightAnchor constraintEqualToConstant:28],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:state.footer.leadingAnchor constant:16],
        [_statusLabel.centerYAnchor constraintEqualToAnchor:state.footer.centerYAnchor],
        [_statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:state.pageStatus.leadingAnchor constant:-16],
        [state.pageStatus.trailingAnchor constraintEqualToAnchor:state.footer.trailingAnchor constant:-16],
        [state.pageStatus.centerYAnchor constraintEqualToAnchor:state.footer.centerYAnchor]]];
    [self syncWorkspaceChrome];
}
- (void)syncWorkspaceChrome {
    SPDFWorkspaceChromeState* state = objc_getAssociatedObject(self,&chromeKey); if (!state) return;
    ((SPDFSidebarNavigationControl*)_sidebarModeControl).documentTitle = [self selectedTab].title ?: _path.lastPathComponent ?: @"No document";
    state.searchControls.hidden = _sidebarModeControl.spdf_selectedSidebarMode != SPDFSidebarModeSearch;
    state.mapHeader.hidden = !_minimapVisible || _presentationMode;
    state.command.hidden = _presentationMode;
    _markdownFontSizeSegments.hidden = ![self isMarkdownActive];
    BOOL wrapped = NSWidth(_toolbar.bounds) > 0 && NSWidth(_toolbar.bounds) < ([self isMarkdownActive] ? 528 : 460);
    if (state.wrapped != wrapped) {
        state.wrapped = wrapped;
        state.headerRow.orientation = wrapped ? NSUserInterfaceLayoutOrientationVertical : NSUserInterfaceLayoutOrientationHorizontal;
        state.headerRow.alignment = wrapped ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY;
    }
    BOOL revision = NO;
    for (NSView* view in _toolbar.arrangedSubviews)
        if ([view.identifier isEqualToString:@"CollectionVersionIndicator"] && !view.hidden) revision = YES;
    _toolbarHeightConstraint.constant = _presentationMode ? 0 : (wrapped ? 76 : 44) + (revision ? 28 : 0);
    state.footer.hidden = _presentationMode; state.splitBottom.constant = _presentationMode ? 0 : -28;
    state.pageStatus.stringValue = _pageField.stringValue.length ? [NSString stringWithFormat:@"Page %@ %@",_pageField.stringValue,_pageCountLabel.stringValue] : @"";
    _sidebarToggleButton.hidden = _sidebarVisible;
    _minimapToggleButton.hidden = _minimapVisible;
    _toolbarOverflowButton.hidden = YES;
    state.previous.enabled = [_pageSegments isEnabledForSegment:0];
    state.next.enabled = [_pageSegments isEnabledForSegment:1];
    state.print.enabled = [self hasActiveDocument];
    _findCountLabel.hidden = !_searchField.stringValue.length;
    _findSegments.hidden = !_searchField.stringValue.length;
}
- (void)showGroupsSidebar:(id)sender {
    (void)sender;
    _sidebarModeControl.spdf_selectedSidebarMode = SPDFSidebarModeGroups;
    _sidebarPreferredVisible = YES;
    [self rebuildSidebar]; [self syncWorkspaceChrome]; [self rememberSidebarWorkspaceMode];
}
- (void)revealWorkspaceFind {
    if (!_sidebarModeControl) return;
    _sidebarModeControl.spdf_selectedSidebarMode = SPDFSidebarModeSearch;
    _sidebarPreferredVisible = YES;
    [self rebuildSidebar]; [self syncWorkspaceChrome];
    [self rememberSidebarWorkspaceMode];
}
@end
