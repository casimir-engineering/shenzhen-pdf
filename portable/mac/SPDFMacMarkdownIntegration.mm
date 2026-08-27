#import "SPDFMacMarkdownDelegatePrivate.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>

#import "SPDFMacMarkdownCache.h"
#import "SPDFMacMarkdownPrinting.h"
#import "SPDFMacMarkdownRouting.h"
#import "SPDFMacSupport.h"
#import "markdown/SPDFMarkdown.h"

@interface SPDFMacMarkdownDelegateState : NSObject
@property(nonatomic, strong) NSView* hostView;
@property(nonatomic, strong) SPDFMacMarkdownSession* activeSession;
@property(nonatomic, strong) dispatch_queue_t workQueue;
@end

@implementation SPDFMacMarkdownDelegateState
@end

static char kSPDFMacMarkdownDelegateStateKey;

@implementation ShenzhenMacDelegate (SPDFMacMarkdownIntegration)

- (SPDFMacMarkdownDelegateState*)markdownState {
    SPDFMacMarkdownDelegateState* state = objc_getAssociatedObject(self, &kSPDFMacMarkdownDelegateStateKey);
    if (!state) {
        state = [SPDFMacMarkdownDelegateState new];
        objc_setAssociatedObject(self, &kSPDFMacMarkdownDelegateStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}

- (SPDFMacMarkdownSession*)activeMarkdownSession { return self.markdownState.activeSession; }

- (void)installMarkdownHostInDocumentContainer {
    SPDFMacMarkdownDelegateState* state = self.markdownState;
    if (state.hostView || !_documentContainer) return;
    state.hostView = [[NSView alloc] init];
    state.hostView.translatesAutoresizingMaskIntoConstraints = NO;
    state.hostView.hidden = YES;
    [_documentContainer addSubview:state.hostView positioned:NSWindowAbove relativeTo:nil];
    [NSLayoutConstraint activateConstraints:@[
        [state.hostView.topAnchor constraintEqualToAnchor:_documentContainer.topAnchor],
        [state.hostView.leadingAnchor constraintEqualToAnchor:_documentContainer.leadingAnchor],
        [state.hostView.trailingAnchor constraintEqualToAnchor:_documentContainer.trailingAnchor],
        [state.hostView.bottomAnchor constraintEqualToAnchor:_documentContainer.bottomAnchor],
    ]];
}

- (BOOL)isMarkdownActive {
    return self.markdownState.activeSession != nil && spdf_mac_path_is_markdown(_path);
}

- (BOOL)hasActiveDocument { return _doc != NULL || [self isMarkdownActive]; }

- (void)setPDFToolbarViewsHiddenForMarkdown:(BOOL)hidden {
    for (NSView* view in @[
             _sidebarToggleButton, _ocrButton, _translateButton, _ocrSeparator, _pageField, _pageCountLabel,
             _prevButton, _nextButton, _fitModePopup, _zoomOutButton, _zoomInButton, _findRegexCheckbox,
             _minimapToggleButton
         ])
        view.hidden = hidden;
}

- (void)deactivateActiveMarkdownView {
    SPDFMacMarkdownDelegateState* state = self.markdownState;
    [state.activeSession deactivate];
    state.activeSession = nil;
    state.hostView.hidden = YES;
    _pageScrollView.hidden = NO;
    [self setPDFToolbarViewsHiddenForMarkdown:NO];
}

- (BOOL)markdownCacheForTab:(SPDFDocumentTab*)tab
          matchesAttributes:(NSDictionary*)attributes
               fileIdentity:(NSString*)fileIdentity {
    return tab.cachedMarkdownSession &&
           spdf_mac_markdown_cache_matches(tab.cachedModificationDate, tab.cachedFileSize,
                                           tab.cachedMarkdownFileIdentity, attributes, fileIdentity);
}

- (void)configureMarkdownSession:(SPDFMacMarkdownSession*)session forTab:(SPDFDocumentTab*)tab {
    __weak ShenzhenMacDelegate* weakSelf = self;
    __weak SPDFMacMarkdownSession* weakSession = session;
    session.statusHandler = ^(NSString* status) {
      ShenzhenMacDelegate* strongSelf = weakSelf;
      if (strongSelf && strongSelf.markdownState.activeSession == weakSession)
          strongSelf->_statusLabel.stringValue = status ?: @"";
    };
    session.openExternalURLHandler = ^(NSURL* URL) {
      ShenzhenMacDelegate* strongSelf = weakSelf;
      if (!strongSelf || strongSelf.markdownState.activeSession != weakSession ||
          !spdf_is_allowed_external_url(URL)) {
          NSBeep();
          return;
      }
      [NSWorkspace.sharedWorkspace openURL:URL];
    };
    session.openDocumentHandler = ^(NSURL* URL, NSString* anchor) {
      ShenzhenMacDelegate* strongSelf = weakSelf;
      if (!strongSelf || strongSelf.markdownState.activeSession != weakSession || !URL.isFileURL) return;
      NSInteger existing = [strongSelf indexOfTabForPath:URL.path];
      if (existing >= 0) {
          SPDFDocumentTab* destinationTab = strongSelf->_tabs[(NSUInteger)existing];
          destinationTab.markdownAnchor = anchor;
          if (existing == strongSelf->_selectedTabIndex) {
              [strongSelf.markdownState.activeSession navigateToAnchorWhenReady:anchor ?: @""];
          } else [strongSelf selectTabAtIndex:existing];
          return;
      }
      [strongSelf openPath:URL.path];
      SPDFDocumentTab* destinationTab = [strongSelf selectedTab];
      destinationTab.markdownAnchor = anchor;
      [strongSelf.markdownState.activeSession navigateToAnchorWhenReady:anchor ?: @""];
    };
    session.searchUpdateHandler = ^(NSUInteger count, NSInteger currentIndex, BOOL searching) {
      ShenzhenMacDelegate* strongSelf = weakSelf;
      if (!strongSelf || strongSelf.markdownState.activeSession != weakSession ||
          [strongSelf selectedTab] != tab)
          return;
      strongSelf->_findSearchInProgress = searching;
      [strongSelf->_findMatches removeAllObjects];
      for (NSUInteger index = 0; index < count; ++index)
          [strongSelf->_findMatches addObject:@{ @"markdownIndex" : @(index) }];
      strongSelf->_findMatchIndex = currentIndex;
      tab.findMatchIndex = currentIndex;
      [strongSelf updateFindControls];
      NSString* query = strongSelf->_searchField.stringValue ?: @"";
      if (!searching && query.length) {
          strongSelf->_statusLabel.stringValue = count
              ? [NSString stringWithFormat:@"%lu matches for \"%@\"", (unsigned long)count, query]
              : [NSString stringWithFormat:@"No matches for \"%@\"", query];
      }
    };
}

- (void)loadSelectedMarkdownTab:(SPDFDocumentTab*)tab {
    SPDFMacMarkdownDelegateState* state = self.markdownState;
    NSString* path = [tab.path copy];
    [self ensureSecurityAccessForPath:path];
    NSDictionary* attributes = [self fileAttributesForPath:path];
    NSString* fileIdentity = spdf_mac_markdown_file_identity(path);
    if (!attributes) {
        tab.missingFile = YES;
        tab.missingMessage = @"File moved or deleted";
        [self showUnavailableSelectedTab:tab path:path message:tab.missingMessage showOpenError:NO error:NULL];
        return;
    }
    if (![self markdownCacheForTab:tab matchesAttributes:attributes fileIdentity:fileIdentity])
        [tab clearCachedRuntime];

    [self clearActiveMetadata];
    [self prepareSelectedTabViewState:tab path:path];
    _doc = NULL;
    _workingPath = path;
    _renderGeneration++;
    _sidebarPreferredVisible = NO;
    _minimapPreferredVisible = NO;
    [self setSidebarActuallyVisible:NO];
    [self setMinimapActuallyVisible:NO];
    _pageScrollView.hidden = YES;
    state.hostView.hidden = NO;
    [self setPDFToolbarViewsHiddenForMarkdown:YES];

    SPDFMacMarkdownSession* session = tab.cachedMarkdownSession;
    if (!session) {
        session = [[SPDFMacMarkdownSession alloc] initWithDocumentURL:[NSURL fileURLWithPath:path]];
        tab.cachedMarkdownSession = session;
    }
    state.activeSession = session;
    [self configureMarkdownSession:session forTab:tab];
    if (!state.workQueue)
        state.workQueue = dispatch_queue_create("com.intuition.shenzhenpdf.markdown", DISPATCH_QUEUE_CONCURRENT);
    tab.missingFile = NO;
    tab.missingMessage = @"";
    tab.title = spdf_display_name_for_path(path);
    _window.title = [NSString stringWithFormat:@"%@ - Shenzhen PDF", tab.title];
    _statusLabel.stringValue = @"Opening Markdown...";
    [self updateTabStrip];
    [self updateControlsForActiveMarkdown];

    NSString* anchor = tab.markdownAnchor;
    tab.markdownAnchor = nil;
    __weak ShenzhenMacDelegate* weakSelf = self;
    __weak SPDFMacMarkdownSession* weakSession = session;
    [session activateInHostView:state.hostView
                     workQueue:state.workQueue
                  scrollOrigin:tab.hasScrollOrigin ? tab.scrollOrigin : NSZeroPoint
                 selectedRange:tab.markdownSelectionRange
                        anchor:anchor
                    completion:^(BOOL success, NSError* error) {
      ShenzhenMacDelegate* strongSelf = weakSelf;
      if (!strongSelf || strongSelf.markdownState.activeSession != weakSession ||
          [strongSelf selectedTab] != tab)
          return;
      if (!success) {
          tab.missingFile = NO;
          tab.missingMessage = error.localizedDescription ?: @"Could not open Markdown document";
          strongSelf->_statusLabel.stringValue = tab.missingMessage;
      } else {
          [strongSelf recordFileAttributes:attributes forTab:tab];
          tab.cachedMarkdownFileIdentity = fileIdentity;
          strongSelf->_statusLabel.stringValue = @"Markdown document ready.";
          if (tab.searchText.length)
              [strongSelf startMarkdownFindForQuery:tab.searchText preferredIndex:tab.findMatchIndex];
      }
      [strongSelf updateControlsForActiveMarkdown];
      [strongSelf savePersistentState];
    }];
    [self teardownActiveFileWatcher];
    [self rememberRecentlyOpenedPath:path];
    [self savePersistentState];
}

- (void)rememberActiveMarkdownStateForTab:(SPDFDocumentTab*)tab {
    if (!tab || ![self isMarkdownActive]) return;
    SPDFMacMarkdownSession* session = self.markdownState.activeSession;
    tab.path = _path;
    tab.title = spdf_display_name_for_path(_path);
    tab.scrollOrigin = session.scrollOrigin;
    tab.hasScrollOrigin = YES;
    tab.markdownSelectionRange = session.selectedRange;
    tab.searchText = _searchField.stringValue ?: @"";
    tab.searchRegex = NO;
    tab.findMatchIndex = session.currentMatchIndex;
    tab.showSidebar = NO;
    tab.showMinimap = NO;
}

- (void)startMarkdownFindForQuery:(NSString*)query preferredIndex:(NSInteger)preferredIndex {
    SPDFDocumentTab* tab = [self selectedTab];
    if (![self isMarkdownActive] || !tab) return;
    tab.searchText = query ?: @"";
    tab.searchRegex = NO;
    tab.findMatchIndex = preferredIndex;
    [self.markdownState.activeSession searchForQuery:query ?: @"" preferredIndex:MAX(0, preferredIndex)];
}

- (void)moveMarkdownFindForward:(BOOL)forward {
    [self.markdownState.activeSession moveToNextMatch:forward];
    _findMatchIndex = self.markdownState.activeSession.currentMatchIndex;
    [self selectedTab].findMatchIndex = _findMatchIndex;
    [self updateFindControls];
}

- (void)clearMarkdownFindResults {
    [self.markdownState.activeSession clearSearch];
    [_findMatches removeAllObjects];
    _findMatchIndex = -1;
    _findSearchInProgress = NO;
}

- (NSString*)markdownSelectedText { return self.markdownState.activeSession.selectedText ?: @""; }

- (void)updateControlsForActiveMarkdown {
    if (![self isMarkdownActive]) return;
    [self setPDFToolbarViewsHiddenForMarkdown:YES];
    _searchField.hidden = NO;
    _searchField.enabled = self.markdownState.activeSession.state == SPDFMacMarkdownSessionReady;
    [self updateFindControls];
    NSString* title = [self displayNameForPathConsideringOpenTabs:_path];
    _window.title = [NSString stringWithFormat:@"%@ - Shenzhen PDF", title];
}

- (void)printActiveMarkdown {
    SPDFMarkdownRenderedDocument* rendered = self.markdownState.activeSession.renderedDocument;
    if (![self isMarkdownActive] || !rendered) {
        NSBeep();
        return;
    }
    NSPrintOperation* operation = [SPDFMacMarkdownPrintAdapter
        printOperationForRenderedDocument:rendered
                                 printInfo:[NSPrintInfo.sharedPrintInfo copy]];
    operation.jobTitle = _path.lastPathComponent ?: @"Markdown Document";
    [operation runOperationModalForWindow:_window delegate:nil didRunSelector:NULL contextInfo:NULL];
}

- (void)saveActiveMarkdownAsPDF {
    SPDFMarkdownRenderedDocument* rendered = self.markdownState.activeSession.renderedDocument;
    if (![self isMarkdownActive] || !rendered) {
        NSBeep();
        return;
    }
    NSSavePanel* panel = [NSSavePanel savePanel];
    panel.title = @"Save Markdown as PDF";
    panel.canCreateDirectories = YES;
    panel.nameFieldStringValue = [[_path.lastPathComponent stringByDeletingPathExtension]
        stringByAppendingPathExtension:@"pdf"];
    panel.allowedContentTypes = @[ UTTypePDF ];
    if ([panel runModal] != NSModalResponseOK) return;
    NSError* error = nil;
    if (![SPDFMacMarkdownPrintAdapter writeRenderedDocument:rendered
                                                      toURL:panel.URL
                                                  printInfo:[NSPrintInfo.sharedPrintInfo copy]
                                                      error:&error]) {
        [self showError:@"Could not save Markdown as PDF"
                 detail:error.localizedDescription ?: @"The PDF could not be written."];
        return;
    }
    _statusLabel.stringValue = @"Markdown PDF saved.";
}

@end
