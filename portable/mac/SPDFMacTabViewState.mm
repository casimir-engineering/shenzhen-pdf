#import "SPDFMacTabViewState.h"

#import "SPDFMacMarkdownDelegatePrivate.h"

// Implemented in ShenzhenPDFMac.mm, which keeps them private to its own
// translation unit; declared here the way the launch prerender declares the
// coordinator methods its worker reuses.
@interface ShenzhenMacDelegate (SPDFMacTabViewStateHost)
- (void)invalidateCursorRegionCache;
- (void)clearFindResults;
- (CGFloat)backingScale;
- (void)clearToolbarFieldFocusForTabSwitch;
@end

@implementation ShenzhenMacDelegate (SPDFMacTabViewState)

- (void)prepareSelectedTabViewState:(SPDFDocumentTab*)tab path:(NSString*)path {
    _path = [path copy];
    // Render/read path: temp copy when the source is read-only, else the source.
    // _path stays the SOURCE for title/Recent/Favorites/watcher/Save/edit-gate.
    _workingPath = tab.workingPath.length ? [tab.workingPath copy] : [path copy];
    // Every document (re)load and tab switch funnels through here, so this is
    // the invalidation choke point for the per-page cursor-region caches.
    [self invalidateCursorRegionCache];
    _highlightPageIndex = -1;
    _selectionPageIndex = -1;
    _selectedText = nil;
    _searchField.stringValue = tab.searchText ?: @"";
    _findRegexCheckbox.state = tab.searchRegex ? NSControlStateValueOn : NSControlStateValueOff;
    _findRegexMultiline = tab.searchRegexMultiline;
    _sidebarPreferredVisible = tab.showSidebar;
    _minimapPreferredVisible = tab.showMinimap;
    // Keep-image-colors is this document's own (SPDFDocumentTab.preservesImageColors).
    // The render wrappers read the mirrored byte on background queues, so it has
    // to point at the document they are about to render.
    _darkThemePreservesImages = tab.preservesImageColors;
    [self clearFindResults];
}

- (void)seedKeepImageColorsForNewTab:(SPDFDocumentTab*)tab {
    tab.preservesImageColors = _darkThemePreservesImagesDefault;
}

- (SPDFDocumentView*)newDocumentView {
    SPDFDocumentView* view = [[SPDFDocumentView alloc] initWithFrame:NSMakeRect(0, 0, 800, 1000)];
    view.reader = self;
    [view registerForDraggedTypes:@[ NSPasteboardTypeFileURL ]];
    view.presentationMode = _presentationMode;
    view.themeVariant = self.markdownThemeVariant; // see applyReadingThemeToDocumentViewport
    view.zoom = _zoom;
    view.currentPageIndex = _pageIndex;
    view.backingScale = [self backingScale];
    view.viewportWidthHint = MAX(1.0, _pageScrollView.contentSize.width);
    view.viewportHeightHint = MAX(1.0, _pageScrollView.contentSize.height);
    view.activeFindPageIndex = -1;
    view.emptyMessage = @"Open a document";
    return view;
}

- (void)replaceDocumentViewForTabSwitch {
    [_pageView cancelTransientInteraction];
    [self clearToolbarFieldFocusForTabSwitch];
    NSClipView* clipView = _pageScrollView.contentView;
    BOOL previousPostsBoundsChangedNotifications = clipView.postsBoundsChangedNotifications;
    clipView.postsBoundsChangedNotifications = NO;
    _pageScrollView.documentView = nil;
    _pageView = [self newDocumentView];
    _pageScrollView.documentView = _pageView;
    clipView.postsBoundsChangedNotifications = previousPostsBoundsChangedNotifications;
    [self clearToolbarFieldFocusForTabSwitch];
}

@end
