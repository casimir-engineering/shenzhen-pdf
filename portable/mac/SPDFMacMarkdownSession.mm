#import "SPDFMacMarkdownSessionPrivate.h"

#import "SPDFMacMarkdownSidebarModel.h"
#import "SPDFMacMarkdownView.h"

static CGFloat SPDFMacMarkdownClampFontScale(CGFloat scale) {
    return MAX((CGFloat)0.5, MIN((CGFloat)3.0, scale));
}

@implementation SPDFMacMarkdownSession {
    NSView* _rootView;
    NSTextField* _placeholder;
    NSAttributedString* _interactiveString;
    SPDFMarkdownCancellationToken* _renderToken;
    NSUInteger _activationGeneration;
    NSUInteger _renderGeneration;
    // The current activation generation's initial parse+paginate pass is in
    // flight. Cleared by that pass's completion or by cancelAllOperations.
    BOOL _loadInFlight;
    // The live activation's completion, retained until the initial load (or
    // the fast install path) finishes so a cancelled-and-self-healed load
    // still reports back to the reader. Cleared by deactivate.
    void (^_pendingActivationCompletion)(BOOL, NSError*);
    NSPoint _pendingScrollOrigin;
    NSRange _pendingSelectedRange;
    NSInteger _pendingPageIndex;
    CGFloat _pendingZoom;
    SPDFMacMarkdownPageFitMode _pendingFitMode;
    __weak id<SPDFMacUIReader> _reader;
    SPDFMacMarkdownSidebarModel* _sidebarModel;
    // fontScale/themeVariant of the currently installed renderedDocument; when
    // either trails the session preference (changed while inactive or
    // mid-load) activation schedules a catch-up rerender.
    CGFloat _renderedFontScale;
    SPDFMarkdownThemeVariant _renderedThemeVariant;
    SPDFMarkdownDiagramCache* _diagramCache;  // shared by every rerender
}

- (instancetype)initWithDocumentURL:(NSURL*)URL {
    return [self initWithDocumentURL:URL fontScale:1.0];
}

- (instancetype)initWithDocumentURL:(NSURL*)URL fontScale:(CGFloat)fontScale {
    return [self initWithDocumentURL:URL fontScale:fontScale themeVariant:SPDFMarkdownThemeVariantLight];
}

- (instancetype)initWithDocumentURL:(NSURL*)URL
                          fontScale:(CGFloat)fontScale
                       themeVariant:(SPDFMarkdownThemeVariant)themeVariant {
    NSParameterAssert(URL.isFileURL);
    self = [super init];
    if (!self) return nil;
    _documentURL = [URL copy];
    _searchMatches = @[];
    _currentMatchIndex = -1;
    _languageOverrides = [NSMutableDictionary dictionary];
    _fontScale = SPDFMacMarkdownClampFontScale(fontScale);
    _renderedFontScale = _fontScale;
    _themeVariant = themeVariant;
    _renderedThemeVariant = _themeVariant;
    _diagramCache = [SPDFMarkdownDiagramCache new];
    [self buildRootView];
    return self;
}

- (SPDFMarkdownRenderOptions*)renderOptionsForThemeVariant:(SPDFMarkdownThemeVariant)variant {
    SPDFMarkdownRenderOptions* options = [SPDFMarkdownRenderOptions defaultOptionsForThemeVariant:variant];
    options.fontScale = _fontScale;
    options.diagramCache = _diagramCache;  // one diagram-layout cache for the session
    [self applyRemoteImageState:options];  // already-fetched remote image bytes
    return options;
}

- (SPDFMarkdownRenderOptions*)renderOptionsForCurrentScale {
    return [self renderOptionsForThemeVariant:_themeVariant];
}

// The installed render trails the session preferences: a catch-up rerender is
// due (used by activation and the self-heal pass).
- (BOOL)renderTrailsPreferences {
    return _renderedFontScale != _fontScale || _renderedThemeVariant != _themeVariant;
}

- (void)applyFontScale:(CGFloat)scale {
    CGFloat clamped = SPDFMacMarkdownClampFontScale(scale);
    if (clamped == _fontScale) return;
    _fontScale = clamped;
    if (_active && self.document) [self rerenderDocumentWithStatus:@"Markdown text size updated."];
}

// The theme mirrors applyFontScale: exactly — an active session rerenders in
// place preserving the viewport; an inactive one adopts the preference and
// catches up on activation.
- (void)setPreservesImageColors:(BOOL)preservesImageColors {
    if (preservesImageColors == _preservesImageColors) return;
    _preservesImageColors = preservesImageColors;
    // Draw-time only: retarget the live plan instead of re-rendering, then
    // repaint. The canvas is the scroll view's document view, so the scroll
    // view's own setNeedsDisplay: never reached it and the change only showed
    // up after switching tabs and back.
    [_paginationPlan setPreservesImageColors:preservesImageColors];
    [_pagedView redrawPages];
    [_minimapModel invalidateThumbnails];
}

- (void)applyThemeVariant:(SPDFMarkdownThemeVariant)themeVariant {
    if (themeVariant == _themeVariant) return;
    _themeVariant = themeVariant;
    if (_active && self.document) [self rerenderDocumentWithStatus:@"Markdown reading theme updated."];
}

- (SPDFMarkdownPaginationPlan*)paginationPlan {
    return _paginationPlan;
}

- (void)buildRootView {
    NSAssert(NSThread.isMainThread, @"Markdown AppKit views must be created on the main thread");
    _rootView = [[NSView alloc] init];
    _rootView.translatesAutoresizingMaskIntoConstraints = NO;
    _placeholder = [NSTextField labelWithString:@"Loading Markdown..."];
    _placeholder.translatesAutoresizingMaskIntoConstraints = NO;
    _placeholder.alignment = NSTextAlignmentCenter;
    _placeholder.textColor = NSColor.secondaryLabelColor;
    [_rootView addSubview:_placeholder];
    [NSLayoutConstraint activateConstraints:@[
        [_placeholder.centerXAnchor constraintEqualToAnchor:_rootView.centerXAnchor],
        [_placeholder.centerYAnchor constraintEqualToAnchor:_rootView.centerYAnchor],
    ]];
}

- (NSView*)rootView {
    return _rootView;
}
- (id<SPDFMacUIReader>)reader {
    return _reader;
}
- (void)setReader:(id<SPDFMacUIReader>)reader {
    _reader = reader;
    _pagedView.reader = reader;
}
- (NSTextView*)textView {
    return nil;
}
- (NSArray<SPDFMarkdownSearchMatch*>*)searchMatches {
    return _searchMatches ?: @[];
}
- (NSInteger)currentMatchIndex {
    return _currentMatchIndex;
}
- (NSPoint)scrollOrigin {
    return _pagedView ? _pagedView.contentView.bounds.origin : _pendingScrollOrigin;
}
- (NSRange)selectedRange {
    return _pagedView ? _pagedView.selectedRange : _pendingSelectedRange;
}
- (NSString*)selectedText {
    return _pagedView.selectedText ?: @"";
}
- (BOOL)selectionContainsImage {
    return [_pagedView selectionContainsImage];
}
- (BOOL)copySelectionToPasteboard:(NSPasteboard*)pasteboard plainTextTransform:(NSString* (^)(NSString*))transform {
    return [_pagedView writeSelectionToPasteboard:pasteboard plainTextTransform:transform];
}
- (NSUInteger)pageCount {
    return _pagedView.pageCount;
}
- (NSInteger)currentPageIndex {
    return _pagedView ? _pagedView.currentPageIndex : _pendingPageIndex;
}
- (NSUInteger)visibleAttributedLocation {
    return _pagedView ? _pagedView.visibleAttributedLocation : NSNotFound;
}
- (CGFloat)zoom {
    return _pagedView ? _pagedView.magnification : MAX(0.1, _pendingZoom);
}
- (SPDFMacMarkdownPageFitMode)fitMode {
    return _pagedView ? _pagedView.fitMode : _pendingFitMode;
}
- (NSArray<NSValue*>*)documentPageRects {
    return _pagedView.documentPageRects ?: @[];
}
- (NSRect)documentVisibleRect {
    return _pagedView ? _pagedView.documentVisibleRect : NSZeroRect;
}
- (NSSize)documentCanvasSize {
    return _pagedView ? _pagedView.documentCanvasSize : NSZeroSize;
}
- (SPDFMacMarkdownMinimapModel*)minimapModel {
    return _minimapModel;
}
- (SPDFMacMarkdownSidebarModel*)sidebarModel {
    return _sidebarModel;
}

- (void)attachToHostView:(NSView*)hostView {
    if (_rootView.superview != hostView) {
        [_rootView removeFromSuperview];
        [hostView addSubview:_rootView];
        [NSLayoutConstraint activateConstraints:@[
            [_rootView.topAnchor constraintEqualToAnchor:hostView.topAnchor],
            [_rootView.leadingAnchor constraintEqualToAnchor:hostView.leadingAnchor],
            [_rootView.trailingAnchor constraintEqualToAnchor:hostView.trailingAnchor],
            [_rootView.bottomAnchor constraintEqualToAnchor:hostView.bottomAnchor],
        ]];
    }
}

- (void)activateInHostView:(NSView*)hostView
                 workQueue:(dispatch_queue_t)workQueue
              scrollOrigin:(NSPoint)scrollOrigin
             selectedRange:(NSRange)selectedRange
                 pageIndex:(NSInteger)pageIndex
                      zoom:(CGFloat)zoom
                   fitMode:(SPDFMacMarkdownPageFitMode)fitMode
                    anchor:(NSString*)anchor
                completion:(void (^)(BOOL, NSError*))completion {
    NSAssert(NSThread.isMainThread, @"Markdown activation must occur on the main thread");
    // Activating again while the initial load is already in flight must not
    // cancel and restart it: adopt the new viewport/completion and let the
    // running load install with them (idempotent activation).
    BOOL adoptInFlightLoad = _active && _loadInFlight && !self.document;
    if (!adoptInFlightLoad) [self cancelAllOperations];
    _active = YES;
    _workQueue = workQueue ?: dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    _pendingScrollOrigin = scrollOrigin;
    _pendingSelectedRange = selectedRange;
    _pendingPageIndex = MAX(0, pageIndex);
    _pendingZoom = MAX(0.1, zoom);
    _pendingFitMode = fitMode;
    _pendingAnchor = [anchor copy];
    _pendingActivationCompletion = [completion copy];
    [self attachToHostView:hostView];
    if (self.document && self.renderedDocument) {
        [self installRenderedDocument:self.renderedDocument
                       paginationPlan:_paginationPlan
                    interactiveString:_interactiveString
                 preserveCurrentState:NO];
        // Catch up with a font scale or theme changed while this session was
        // cached.
        if (self.renderTrailsPreferences) [self rerenderDocumentWithStatus:nil];
        [self finishActivationWithSuccess:YES error:nil];
        return;
    }
    if (adoptInFlightLoad) return;
    [self startInitialDocumentLoad];
}

// The initial parse+measure+paginate pass for the current activation
// generation. Callers guarantee no initial load is already in flight.
- (void)startInitialDocumentLoad {
    self.state = SPDFMacMarkdownSessionLoading;
    _placeholder.stringValue = @"Loading Markdown...";
    _placeholder.hidden = NO;
    [_pagedView removeFromSuperview];
    _pagedView = nil;
    _loadInFlight = YES;
    NSUInteger activationGeneration = _activationGeneration;
    NSURL* URL = self.documentURL;
    SPDFMarkdownRenderOptions* renderOptions = [self renderOptionsForCurrentScale];
    dispatch_queue_t workQueue = _workQueue ?: dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    dispatch_async(workQueue, ^{
      NSError* error = nil;
      SPDFMarkdownDocument* document = [SPDFMarkdownDocument documentWithURL:URL options:renderOptions error:&error];
      SPDFMarkdownPaginationPlan* plan = nil;
      NSAttributedString* interactive = nil;
      if (document) {
          plan = SPDFMacMarkdownPlanForRendition(document.renderedDocument, renderOptions.themeVariant,
                                                self->_preservesImageColors);
          interactive = SPDFMacMarkdownInteractiveString(document.model, document.renderedDocument);
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        // Only the live generation's load may clear the in-flight flag or
        // install: a cancel or a newer activation owns the session otherwise.
        if (activationGeneration != self->_activationGeneration) return;
        self->_loadInFlight = NO;
        if (!self->_active) return;
        if (!document) {
            self.state = SPDFMacMarkdownSessionFailed;
            self->_placeholder.stringValue = error.localizedDescription ?: @"Could not open Markdown document.";
            [self finishActivationWithSuccess:NO error:error];
            return;
        }
        self.document = document;
        self.renderedDocument = document.renderedDocument;
        self->_paginationPlan = plan;
        self->_interactiveString = interactive;
        self->_renderedFontScale = renderOptions.fontScale;
        self->_renderedThemeVariant = renderOptions.themeVariant;
        self.state = SPDFMacMarkdownSessionReady;
        [self installRenderedDocument:self.renderedDocument
                       paginationPlan:plan
                    interactiveString:interactive
                 preserveCurrentState:NO];
        // Catch up with a font scale or theme applied while the first render
        // was in flight.
        if (self.renderTrailsPreferences) [self rerenderDocumentWithStatus:nil];
        [self finishActivationWithSuccess:YES error:nil];
      });
    });
}

- (void)finishActivationWithSuccess:(BOOL)success error:(NSError*)error {
    void (^activationCompletion)(BOOL, NSError*) = _pendingActivationCompletion;
    _pendingActivationCompletion = nil;
    if (activationCompletion) activationCompletion(success, error);
}

// Self-healing activation invariant: an active session must either have its
// rendered document installed or work actually in flight. Idempotent; main
// thread only. Cancels that land while the session stays on screen (e.g. the
// tab cache dropping its runtime cancels the very session the reader is
// displaying) re-enter here to restart whatever the cancel killed — without
// this the dropped load completion would strand the visible tab on the
// "Loading Markdown..." placeholder forever.
- (void)ensureActiveSessionHasContent {
    NSAssert(NSThread.isMainThread, @"Markdown session healing must occur on the main thread");
    if (!_active || _loadInFlight) return;
    if (self.document && self.renderedDocument) {
        if (!_pagedView)
            [self installRenderedDocument:self.renderedDocument
                           paginationPlan:_paginationPlan
                        interactiveString:_interactiveString
                     preserveCurrentState:NO];
        // Restart a cancelled font-scale/theme catch-up rerender.
        if (!_renderToken && self.renderTrailsPreferences) [self rerenderDocumentWithStatus:nil];
        return;
    }
    [self startInitialDocumentLoad];
}

- (void)installRenderedDocument:(SPDFMarkdownRenderedDocument*)rendered
                 paginationPlan:(SPDFMarkdownPaginationPlan*)plan
              interactiveString:(NSAttributedString*)interactive
           preserveCurrentState:(BOOL)preserve {
    if (!_active || !rendered || !plan || !interactive) return;
    NSPoint origin = preserve && _pagedView ? self.scrollOrigin : _pendingScrollOrigin;
    NSRange selection = preserve && _pagedView ? self.selectedRange : _pendingSelectedRange;
    NSInteger page = preserve && _pagedView ? self.currentPageIndex : _pendingPageIndex;
    CGFloat zoom = preserve && _pagedView ? self.zoom : _pendingZoom;
    SPDFMacMarkdownPageFitMode fit = preserve && _pagedView ? self.fitMode : _pendingFitMode;
    [self clearMatchFlash]; // the flash timer must not drive the outgoing view
    [_pagedView removeFromSuperview];
    _pagedView = [[SPDFMacMarkdownPagedView alloc] initWithPaginationPlan:plan attributedString:interactive];
    _pagedView.reader = _reader;
    _minimapModel = [[SPDFMacMarkdownMinimapModel alloc] initWithPaginationPlan:plan attributedString:interactive];
    _sidebarModel = [[SPDFMacMarkdownSidebarModel alloc] initWithRenderedDocument:rendered paginationPlan:plan];
    _pagedView.translatesAutoresizingMaskIntoConstraints = NO;
    __weak SPDFMacMarkdownSession* weakSelf = self;
    _pagedView.viewportChangedHandler = ^(NSInteger pageIndex, CGFloat currentZoom) {
      SPDFMacMarkdownSession* strongSelf = weakSelf;
      if (strongSelf.viewportUpdateHandler)
          strongSelf.viewportUpdateHandler(pageIndex, currentZoom, strongSelf->_pagedView.fitMode);
    };
    _pagedView.activateDestinationHandler = ^(NSString* destination, BOOL wikiLink) {
      [weakSelf activateDestination:destination wikiLink:wikiLink];
    };
    _pagedView.chooseCodeLanguageHandler = ^(NSUInteger blockIndex) {
      SPDFMacMarkdownSession* strongSelf = weakSelf;
      [strongSelf showLanguagePickerForCodeBlock:blockIndex parentWindow:strongSelf->_pagedView.window];
    };
    [_rootView addSubview:_pagedView];
    [NSLayoutConstraint activateConstraints:@[
        [_pagedView.topAnchor constraintEqualToAnchor:_rootView.topAnchor],
        [_pagedView.leadingAnchor constraintEqualToAnchor:_rootView.leadingAnchor],
        [_pagedView.trailingAnchor constraintEqualToAnchor:_rootView.trailingAnchor],
        [_pagedView.bottomAnchor constraintEqualToAnchor:_rootView.bottomAnchor],
    ]];
    _placeholder.hidden = YES;
    if (_searchMatches.count) [self applySearchHighlights];
    // Every install of an active render is the lazy-load trigger for any
    // remote images the document references (idempotent for known targets).
    [self startRemoteImageFetchesIfNeeded];
    _pagedView.selectedRange = selection;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!self->_active || !self->_pagedView.superview) return;
      [self->_rootView layoutSubtreeIfNeeded];
      // Restore the zoom / fit mode first so a pending anchor scrolls within
      // the restored viewport instead of silently discarding it.
      if (fit == SPDFMacMarkdownPageFitCustom)
          [self->_pagedView setZoom:zoom centeredAtPoint:NSZeroPoint];
      else
          [self->_pagedView applyFitMode:fit];
      if (self->_pendingAnchor.length) {
          [self scrollToHeadingAnchor:self->_pendingAnchor];
          self->_pendingAnchor = nil;
      } else if (preserve) {
          // An in-place rerender (language choice, font scale) captured the
          // live origin: restore it exactly for every fit mode so the viewport
          // does not drift to a page boundary. The bounds-change notification
          // re-derives the current page index.
          [self->_pagedView.contentView scrollToPoint:origin];
          [self->_pagedView reflectScrolledClipView:self->_pagedView.contentView];
      } else {
          [self->_pagedView goToPageAtIndex:page alignTop:NO];
          if (fit == SPDFMacMarkdownPageFitCustom) {
              [self->_pagedView.contentView scrollToPoint:origin];
              [self->_pagedView reflectScrolledClipView:self->_pagedView.contentView];
          }
      }
    });
}

- (void)deactivate {
    _pendingScrollOrigin = self.scrollOrigin;
    _pendingSelectedRange = self.selectedRange;
    _pendingPageIndex = self.currentPageIndex;
    _pendingZoom = self.zoom;
    _pendingFitMode = self.fitMode;
    _active = NO;
    // The activation intent dies with the deactivation: its completion must
    // never fire late (the next activation supplies a fresh one).
    _pendingActivationCompletion = nil;
    [self clearMatchFlash];
    [self cancelAllOperations];
    // Downloads must not keep starting for a background tab; fetched bytes
    // stay cached so reactivation never re-downloads.
    [self cancelQueuedRemoteImageFetches];
    [_rootView removeFromSuperview];
}

- (void)cancelAllOperations {
    BOOL searchWasRunning = _searchToken != nil;
    [_searchToken cancel];
    [_renderToken cancel];
    _searchToken = nil;
    _renderToken = nil;
    _loadInFlight = NO;
    _activationGeneration++;
    _searchGeneration++;
    _renderGeneration++;
    if (searchWasRunning && self.searchUpdateHandler)
        self.searchUpdateHandler(_searchMatches.count, _currentMatchIndex, NO);
    // A cancel that leaves this session active (anything but deactivation)
    // must not strand the on-screen tab: the generation bump silently drops
    // every queued completion, so schedule an idempotent healing pass. It
    // no-ops whenever an activation restarted or reinstalled work first.
    if (_active) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self ensureActiveSessionHasContent];
        });
    }
}

- (void)dealloc {
    _active = NO; // teardown must never schedule the healing pass
    [self cancelAllOperations];
}

// Shared rerender flow for language overrides, font-scale and theme changes:
// every pass renders with the session's current font scale and theme so any
// kind of change survives the others. A nil/empty status skips the status
// callback.
- (void)rerenderDocumentWithStatus:(NSString*)status {
    [_renderToken cancel];
    _renderGeneration++;
    NSUInteger renderGeneration = _renderGeneration;
    CGFloat fontScale = _fontScale;
    SPDFMarkdownThemeVariant themeVariant = _themeVariant;
    NSDictionary* overrides = [_languageOverrides copy];
    __weak SPDFMacMarkdownSession* weakSelf = self;
    _renderToken = [self.document
        renderWithOptions:[self renderOptionsForCurrentScale]
        languageOverrides:overrides
                workQueue:_workQueue
          completionQueue:_workQueue
               completion:^(SPDFMarkdownRenderedDocument* rendered, BOOL cancelled) {
                 SPDFMacMarkdownSession* strongSelf = weakSelf;
                 if (!strongSelf || cancelled || !strongSelf->_active ||
                     renderGeneration != strongSelf->_renderGeneration || !rendered)
                     return;
                 SPDFMarkdownPaginationPlan* plan =
                     SPDFMacMarkdownPlanForRendition(rendered, themeVariant, self->_preservesImageColors);
                 NSAttributedString* interactive =
                     SPDFMacMarkdownInteractiveString(strongSelf.document.model, rendered);
                 dispatch_async(dispatch_get_main_queue(), ^{
                   SPDFMacMarkdownSession* mainSelf = weakSelf;
                   if (!mainSelf || cancelled || !mainSelf->_active || renderGeneration != mainSelf->_renderGeneration)
                       return;
                   mainSelf->_renderToken = nil;
                   mainSelf.renderedDocument = rendered;
                   mainSelf->_paginationPlan = plan;
                   mainSelf->_interactiveString = interactive;
                   mainSelf->_renderedFontScale = fontScale;
                   mainSelf->_renderedThemeVariant = themeVariant;
                   [mainSelf installRenderedDocument:rendered
                                      paginationPlan:plan
                                   interactiveString:interactive
                                preserveCurrentState:YES];
                   // The attributed string changed: re-run the active search so
                   // match ranges can't go stale (the same match index is kept
                   // when the count still fits, else it clamps), without
                   // scrolling away from the preserved viewport.
                   if (mainSelf->_activeSearchQuery.length)
                       [mainSelf searchForQuery:mainSelf->_activeSearchQuery
                                          regex:mainSelf->_activeSearchRegex
                                 preferredIndex:mainSelf->_currentMatchIndex
                                  jumpToNearest:NO
                                         reveal:NO];
                   if (status.length && mainSelf.statusHandler) mainSelf.statusHandler(status);
                 });
               }];
}

@end
