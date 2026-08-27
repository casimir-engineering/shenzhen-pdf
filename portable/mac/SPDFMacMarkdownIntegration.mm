#import "SPDFMacMarkdownDelegatePrivate.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>

#import "SPDFMacMarkdownCache.h"
#import "SPDFMacMarkdownMinimapModel.h"
#import "SPDFMacMarkdownPrinting.h"
#import "SPDFMacMarkdownRouting.h"
#import "SPDFMacMarkdownSidebarModel.h"
#import "SPDFMacSupport.h"
#import "markdown/SPDFMarkdown.h"

@interface SPDFMacMarkdownDelegateState : NSObject
@property(nonatomic, strong) NSView* hostView;
@property(nonatomic, strong) SPDFMacMarkdownSession* activeSession;
@property(nonatomic, strong) dispatch_queue_t workQueue;
@property(nonatomic) BOOL controlsUpdateScheduled;
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

- (SPDFMacMarkdownSession*)activeMarkdownSession {
    return self.markdownState.activeSession;
}

- (void)installMarkdownHostInDocumentContainer {
    SPDFMacMarkdownDelegateState* state = self.markdownState;
    if (state.hostView || !_documentContainer) return;
    state.hostView = [[NSView alloc] init];
    state.hostView.translatesAutoresizingMaskIntoConstraints = NO;
    state.hostView.hidden = YES;
    [_documentContainer addSubview:state.hostView positioned:NSWindowAbove relativeTo:_pageScrollView];
    [NSLayoutConstraint activateConstraints:@[
        [state.hostView.topAnchor constraintEqualToAnchor:_pageScrollView.topAnchor],
        [state.hostView.leadingAnchor constraintEqualToAnchor:_pageScrollView.leadingAnchor],
        [state.hostView.trailingAnchor constraintEqualToAnchor:_pageScrollView.trailingAnchor],
        [state.hostView.bottomAnchor constraintEqualToAnchor:_pageScrollView.bottomAnchor],
    ]];
}

- (BOOL)isMarkdownActive {
    return self.markdownState.activeSession != nil && spdf_mac_path_is_markdown(_path);
}

- (BOOL)hasActiveDocument {
    return _doc != NULL || [self isMarkdownActive];
}

- (void)setPDFToolbarViewsHiddenForMarkdown:(BOOL)hidden {
    (void)hidden;
    for (NSView* view in @[
             _sidebarToggleButton, _ocrButton, _translateButton, _ocrSeparator, _findRegexCheckbox, _minimapToggleButton
         ])
        view.hidden = NO;
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
    session.reader = (id<SPDFMacUIReader>)self;
    __weak ShenzhenMacDelegate* weakSelf = self;
    __weak SPDFMacMarkdownSession* weakSession = session;
    session.statusHandler = ^(NSString* status) {
      ShenzhenMacDelegate* strongSelf = weakSelf;
      if (strongSelf && strongSelf.markdownState.activeSession == weakSession)
          strongSelf->_statusLabel.stringValue = status ?: @"";
    };
    session.openExternalURLHandler = ^(NSURL* URL) {
      ShenzhenMacDelegate* strongSelf = weakSelf;
      if (!strongSelf || strongSelf.markdownState.activeSession != weakSession || !spdf_is_allowed_external_url(URL)) {
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
          } else
              [strongSelf selectTabAtIndex:existing];
          return;
      }
      [strongSelf openPath:URL.path];
      SPDFDocumentTab* destinationTab = [strongSelf selectedTab];
      destinationTab.markdownAnchor = anchor;
      [strongSelf.markdownState.activeSession navigateToAnchorWhenReady:anchor ?: @""];
    };
    session.searchUpdateHandler = ^(NSUInteger count, NSInteger currentIndex, BOOL searching) {
      ShenzhenMacDelegate* strongSelf = weakSelf;
      if (!strongSelf || strongSelf.markdownState.activeSession != weakSession || [strongSelf selectedTab] != tab)
          return;
      strongSelf->_findSearchInProgress = searching;
      [strongSelf->_findMatches removeAllObjects];
      for (NSUInteger index = 0; index < count; ++index)
          [strongSelf->_findMatches addObject:@{@"markdownIndex" : @(index)}];
      strongSelf->_findMatchIndex = currentIndex;
      tab.findMatchIndex = currentIndex;
      [strongSelf updateFindControls];
      [strongSelf rebuildSidebar];
      NSString* query = strongSelf->_searchField.stringValue ?: @"";
      if (!searching && query.length) {
          strongSelf->_statusLabel.stringValue =
              count ? [NSString stringWithFormat:@"%lu matches for \"%@\"", (unsigned long)count, query]
                    : [NSString stringWithFormat:@"No matches for \"%@\"", query];
      }
    };
    session.viewportUpdateHandler = ^(NSInteger pageIndex, CGFloat zoom, SPDFMacMarkdownPageFitMode fitMode) {
      ShenzhenMacDelegate* strongSelf = weakSelf;
      if (!strongSelf || strongSelf.markdownState.activeSession != weakSession || [strongSelf selectedTab] != tab)
          return;
      strongSelf->_pageIndex = pageIndex;
      strongSelf->_zoom = zoom;
      strongSelf->_fitMode = (SPDFFitMode)fitMode;
      tab.pageIndex = pageIndex;
      tab.zoom = zoom;
      tab.customZoom = fitMode == SPDFMacMarkdownPageFitCustom ? zoom : tab.customZoom;
      tab.fitMode = (SPDFFitMode)fitMode;
      SPDFMacMarkdownDelegateState* state = strongSelf.markdownState;
      if (state.controlsUpdateScheduled) return;
      state.controlsUpdateScheduled = YES;
      dispatch_async(dispatch_get_main_queue(), ^{
        state.controlsUpdateScheduled = NO;
        if (strongSelf.markdownState.activeSession == weakSession) {
            [strongSelf updateControlsForActiveMarkdown];
            [strongSelf updateMarkdownMinimap];
        }
      });
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
    _pageScrollView.hidden = YES;
    state.hostView.hidden = NO;
    [self setPDFToolbarViewsHiddenForMarkdown:YES];
    [self setMinimapActuallyVisible:_minimapPreferredVisible];

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
                      pageIndex:tab.pageIndex
                           zoom:tab.zoom > 0 ? tab.zoom : 1.0
                        fitMode:(SPDFMacMarkdownPageFitMode)tab.fitMode
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
                           [strongSelf applySinglePageMinimapDefaultToTab:tab
                                                                pageCount:(NSInteger)weakSession.pageCount];
                           strongSelf->_minimapPreferredVisible = tab.showMinimap;
                           [strongSelf setMinimapActuallyVisible:strongSelf->_minimapPreferredVisible];
                           [strongSelf recordFileAttributes:attributes forTab:tab];
                           tab.cachedMarkdownFileIdentity = fileIdentity;
                           strongSelf->_statusLabel.stringValue = @"Markdown document ready.";
                           if (tab.searchText.length)
                               [strongSelf startMarkdownFindForQuery:tab.searchText preferredIndex:tab.findMatchIndex];
                           [strongSelf rebuildSidebar];
                           [strongSelf updateMarkdownMinimap];
                       }
                       [strongSelf updateControlsForActiveMarkdown];
                       [strongSelf savePersistentState];
                     }];
    [self rebuildSidebar];
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
    tab.pageIndex = session.currentPageIndex;
    tab.zoom = session.zoom;
    if (session.fitMode == SPDFMacMarkdownPageFitCustom) tab.customZoom = session.zoom;
    tab.fitMode = (SPDFFitMode)session.fitMode;
    tab.searchText = _searchField.stringValue ?: @"";
    tab.searchRegex = NO;
    tab.findMatchIndex = session.currentMatchIndex;
    tab.showSidebar = _sidebarPreferredVisible;
    tab.showMinimap = _minimapPreferredVisible;
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
    [self rebuildSidebar];
}

- (NSString*)markdownSelectedText {
    return self.markdownState.activeSession.selectedText ?: @"";
}

- (void)updateControlsForActiveMarkdown {
    if (![self isMarkdownActive]) return;
    SPDFMacMarkdownSession* session = self.markdownState.activeSession;
    [self setPDFToolbarViewsHiddenForMarkdown:YES];
    _pageIndex = session.currentPageIndex;
    _zoom = session.zoom;
    _fitMode = (SPDFFitMode)session.fitMode;
    NSInteger pageCount = (NSInteger)session.pageCount;
    _prevButton.enabled = _pageIndex > 0;
    _nextButton.enabled = _pageIndex + 1 < pageCount;
    _pageField.hidden = NO;
    _pageCountLabel.hidden = NO;
    _prevButton.hidden = NO;
    _nextButton.hidden = NO;
    _fitModePopup.hidden = NO;
    _zoomOutButton.hidden = NO;
    _zoomInButton.hidden = NO;
    _pageField.enabled = pageCount > 0;
    _zoomOutButton.enabled = pageCount > 0;
    _zoomInButton.enabled = pageCount > 0;
    _fitModePopup.enabled = pageCount > 0;
    _pageField.stringValue = pageCount ? [NSString stringWithFormat:@"%ld", (long)_pageIndex + 1] : @"";
    _pageCountLabel.stringValue = [NSString stringWithFormat:@"/ %ld", (long)pageCount];
    _searchField.hidden = NO;
    _searchField.enabled = session.state == SPDFMacMarkdownSessionReady;
    _sidebarToggleButton.enabled = session.state == SPDFMacMarkdownSessionReady;
    _minimapToggleButton.enabled = session.state == SPDFMacMarkdownSessionReady;
    _findRegexCheckbox.enabled = NO;
    _ocrButton.enabled = NO;
    _translateButton.enabled = NO;
    [self updateFindControls];
    [self syncToolbarState];
    NSString* title = [self displayNameForPathConsideringOpenTabs:_path];
    _window.title = [NSString stringWithFormat:@"%@ - Shenzhen PDF", title];
    if (pageCount)
        _statusLabel.stringValue = [NSString
            stringWithFormat:@"Page %ld of %ld    Zoom %.0f%%", (long)_pageIndex + 1, (long)pageCount, _zoom * 100.0];
}

- (BOOL)markdownHasChapters {
    return self.markdownState.activeSession.sidebarModel.chapterItems.count > 0;
}

- (BOOL)markdownHasSearchSidebar {
    return [self isMarkdownActive] &&
           (_searchField.stringValue.length > 0 || _findSearchInProgress || _findMatches.count > 0);
}

- (void)rebuildMarkdownSidebar {
    [_sidebarItems removeAllObjects];
    SPDFMacMarkdownSession* session = self.markdownState.activeSession;
    SPDFMacMarkdownSidebarModel* model = session.sidebarModel;
    BOOL loading = !model && session.state == SPDFMacMarkdownSessionLoading;
    BOOL hasChapters = model.chapterItems.count > 0;
    BOOL hasSearch = [self markdownHasSearchSidebar];
    BOOL hasSidebar = loading || (model && (hasChapters || hasSearch));

    [self syncSidebarModeControlSegmentsForSearchAvailability:hasSearch];
    if (_sidebarModeControl.selectedSegment == SPDFSidebarModeSearch && !hasSearch)
        _sidebarModeControl.selectedSegment = SPDFSidebarModeChapters;
    else if (_sidebarModeControl.selectedSegment == SPDFSidebarModeComments)
        _sidebarModeControl.selectedSegment = hasChapters ? SPDFSidebarModeChapters : SPDFSidebarModeSearch;
    else if (_sidebarModeControl.selectedSegment == SPDFSidebarModeChapters && !hasChapters && hasSearch)
        _sidebarModeControl.selectedSegment = SPDFSidebarModeSearch;

    [_sidebarModeControl setEnabled:hasChapters forSegment:SPDFSidebarModeChapters];
    [_sidebarModeControl setEnabled:NO forSegment:SPDFSidebarModeComments];
    if (hasSearch) [_sidebarModeControl setEnabled:YES forSegment:SPDFSidebarModeSearch];
    [self syncSidebarFilterField];

    if (loading) {
        [_sidebarItems addObject:@{@"kind" : @"findStatus", @"title" : @"Loading chapters...", @"page" : @(-1)}];
    } else if (hasSidebar && _sidebarModeControl.selectedSegment == SPDFSidebarModeSearch) {
        [_sidebarItems addObjectsFromArray:[model searchSidebarItemsForMatches:session.searchMatches
                                                                         query:_searchField.stringValue ?: @""
                                                                     searching:_findSearchInProgress]];
    } else if (hasChapters) {
        [_sidebarItems addObjectsFromArray:[model chapterItemsMatchingQuery:_chapterFilterText ?: @""]];
    }

    [self syncSidebarTableColumnWidth];
    [_sidebarTable reloadData];
    if (_sidebarItems.count > 0)
        [_sidebarTable
            noteHeightOfRowsWithIndexesChanged:[NSIndexSet
                                                   indexSetWithIndexesInRange:NSMakeRange(0, _sidebarItems.count)]];
    [self setSidebarActuallyVisible:hasSidebar && _sidebarPreferredVisible];
    if (hasSidebar && _sidebarVisible) [self restoreSidebarWidth];
    if (hasSidebar) [self selectCurrentSidebarRow];
}

- (void)activateMarkdownSidebarItem:(NSDictionary*)item {
    NSString* kind = item[@"kind"];
    if ([kind isEqualToString:@"findResult"]) {
        [self.markdownState.activeSession goToSearchMatchAtIndex:[item[@"findIndex"] integerValue]];
    } else if ([kind isEqualToString:@"chapter"]) {
        NSValue* rangeValue = item[@"range"];
        if ([rangeValue isKindOfClass:NSValue.class])
            [self.markdownState.activeSession revealRange:rangeValue.rangeValue];
    }
    [self updateControlsForActiveMarkdown];
    [self selectCurrentSidebarRow];
}

- (void)printActiveMarkdown {
    SPDFMarkdownRenderedDocument* rendered = self.markdownState.activeSession.renderedDocument;
    if (![self isMarkdownActive] || !rendered) {
        NSBeep();
        return;
    }
    NSPrintOperation* operation =
        [SPDFMacMarkdownPrintAdapter printOperationForRenderedDocument:rendered
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
    panel.nameFieldStringValue =
        [[_path.lastPathComponent stringByDeletingPathExtension] stringByAppendingPathExtension:@"pdf"];
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
