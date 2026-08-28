#import "SPDFMacMarkdownSession.h"
#import "SPDFMacMarkdownLanguagePicker.h"
#import "SPDFMacMarkdownMinimapModel.h"
#import "SPDFMacMarkdownPagedView.h"
#import "SPDFMacMarkdownRouting.h"
#import "SPDFMacMarkdownSidebarModel.h"
#import "SPDFMacMarkdownView.h"
#import "markdown/SPDFMarkdown.h"

static CGFloat SPDFMacMarkdownClampFontScale(CGFloat scale) {
    return MAX((CGFloat)0.5, MIN((CGFloat)3.0, scale));
}

@interface SPDFMacMarkdownSession ()
@property(nonatomic) SPDFMacMarkdownSessionState state;
@property(nonatomic, strong, nullable) SPDFMarkdownDocument* document;
@property(nonatomic, strong, nullable) SPDFMarkdownRenderedDocument* renderedDocument;
@end
@implementation SPDFMacMarkdownSession {
    NSView* _rootView;
    NSTextField* _placeholder;
    SPDFMacMarkdownPagedView* _pagedView;
    SPDFMarkdownPaginationPlan* _paginationPlan;
    NSAttributedString* _interactiveString;
    NSArray<SPDFMarkdownSearchMatch*>* _searchMatches;
    NSInteger _currentMatchIndex;
    SPDFMarkdownCancellationToken* _searchToken;
    SPDFMarkdownCancellationToken* _renderToken;
    NSMutableDictionary<NSNumber*, NSString*>* _languageOverrides;
    SPDFMacMarkdownLanguagePickerController* _languagePicker;
    dispatch_queue_t _workQueue;
    NSUInteger _activationGeneration;
    NSUInteger _searchGeneration;
    NSUInteger _renderGeneration;
    BOOL _active;
    NSPoint _pendingScrollOrigin;
    NSRange _pendingSelectedRange;
    NSInteger _pendingPageIndex;
    CGFloat _pendingZoom;
    SPDFMacMarkdownPageFitMode _pendingFitMode;
    NSString* _pendingAnchor;
    __weak id<SPDFMacUIReader> _reader;
    SPDFMacMarkdownMinimapModel* _minimapModel;
    SPDFMacMarkdownSidebarModel* _sidebarModel;
    // fontScale of the currently installed renderedDocument; when it trails
    // _fontScale (the scale changed while inactive or mid-load) activation
    // schedules a catch-up rerender.
    CGFloat _renderedFontScale;
}

- (instancetype)initWithDocumentURL:(NSURL*)URL {
    return [self initWithDocumentURL:URL fontScale:1.0];
}

- (instancetype)initWithDocumentURL:(NSURL*)URL fontScale:(CGFloat)fontScale {
    NSParameterAssert(URL.isFileURL);
    self = [super init];
    if (!self) return nil;
    _documentURL = [URL copy];
    _searchMatches = @[];
    _currentMatchIndex = -1;
    _languageOverrides = [NSMutableDictionary dictionary];
    _fontScale = SPDFMacMarkdownClampFontScale(fontScale);
    _renderedFontScale = _fontScale;
    [self buildRootView];
    return self;
}

- (SPDFMarkdownRenderOptions*)renderOptionsForCurrentScale {
    SPDFMarkdownRenderOptions* options = [SPDFMarkdownRenderOptions defaultOptions];
    options.fontScale = _fontScale;
    return options;
}

- (void)applyFontScale:(CGFloat)scale {
    CGFloat clamped = SPDFMacMarkdownClampFontScale(scale);
    if (clamped == _fontScale) return;
    _fontScale = clamped;
    if (_active && self.document) [self rerenderDocumentWithStatus:@"Markdown text size updated."];
}

- (SPDFMarkdownRenderedDocument*)renderedDocumentForExport {
    if (_renderedFontScale == 1.0 || !self.document) return self.renderedDocument;
    SPDFMarkdownRenderedDocument* rendered =
        [[SPDFMarkdownRenderer new] renderModel:self.document.model
                                        options:SPDFMarkdownRenderOptions.defaultOptions
                              languageOverrides:[_languageOverrides copy]];
    return rendered ?: self.renderedDocument;
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
    [self cancelAllOperations];
    _active = YES;
    NSUInteger activationGeneration = _activationGeneration;
    _workQueue = workQueue ?: dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    _pendingScrollOrigin = scrollOrigin;
    _pendingSelectedRange = selectedRange;
    _pendingPageIndex = MAX(0, pageIndex);
    _pendingZoom = MAX(0.1, zoom);
    _pendingFitMode = fitMode;
    _pendingAnchor = [anchor copy];
    [self attachToHostView:hostView];
    if (self.document && self.renderedDocument) {
        [self installRenderedDocument:self.renderedDocument
                       paginationPlan:_paginationPlan
                    interactiveString:_interactiveString
                 preserveCurrentState:NO];
        // Catch up with a font scale changed while this session was cached.
        if (_renderedFontScale != _fontScale) [self rerenderDocumentWithStatus:nil];
        if (completion) completion(YES, nil);
        return;
    }

    self.state = SPDFMacMarkdownSessionLoading;
    _placeholder.stringValue = @"Loading Markdown...";
    _placeholder.hidden = NO;
    [_pagedView removeFromSuperview];
    _pagedView = nil;
    NSURL* URL = self.documentURL;
    SPDFMarkdownRenderOptions* renderOptions = [self renderOptionsForCurrentScale];
    dispatch_async(_workQueue, ^{
      NSError* error = nil;
      SPDFMarkdownDocument* document = [SPDFMarkdownDocument documentWithURL:URL options:renderOptions error:&error];
      SPDFMarkdownPaginationPlan* plan = nil;
      NSAttributedString* interactive = nil;
      if (document) {
          SPDFMarkdownPaginator* paginator = [SPDFMarkdownPaginator new];
          SPDFMarkdownPageConfiguration* configuration = [SPDFMarkdownPageConfiguration A4PortraitConfiguration];
          configuration.includesCodeLanguageControlSpacing = YES;
          NSArray* items = [paginator measureRenderedDocument:document.renderedDocument
                                               containerWidth:NSWidth(configuration.printableRect)];
          plan = [paginator paginateItems:items configuration:configuration];
          interactive = SPDFMacMarkdownInteractiveString(document.model, document.renderedDocument);
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_active || activationGeneration != self->_activationGeneration) return;
        if (!document) {
            self.state = SPDFMacMarkdownSessionFailed;
            self->_placeholder.stringValue = error.localizedDescription ?: @"Could not open Markdown document.";
            if (completion) completion(NO, error);
            return;
        }
        self.document = document;
        self.renderedDocument = document.renderedDocument;
        self->_paginationPlan = plan;
        self->_interactiveString = interactive;
        self->_renderedFontScale = renderOptions.fontScale;
        self.state = SPDFMacMarkdownSessionReady;
        [self installRenderedDocument:self.renderedDocument
                       paginationPlan:plan
                    interactiveString:interactive
                 preserveCurrentState:NO];
        // Catch up with a font scale applied while the first render was in flight.
        if (self->_renderedFontScale != self->_fontScale) [self rerenderDocumentWithStatus:nil];
        if (completion) completion(YES, nil);
      });
    });
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
    [self cancelAllOperations];
    [_rootView removeFromSuperview];
}

- (void)cancelAllOperations {
    BOOL searchWasRunning = _searchToken != nil;
    [_searchToken cancel];
    [_renderToken cancel];
    _searchToken = nil;
    _renderToken = nil;
    _activationGeneration++;
    _searchGeneration++;
    _renderGeneration++;
    if (searchWasRunning && self.searchUpdateHandler)
        self.searchUpdateHandler(_searchMatches.count, _currentMatchIndex, NO);
}

- (void)dealloc {
    [self cancelAllOperations];
}

- (void)removeSearchHighlights {
    _pagedView.searchRanges = @[];
}

- (void)applySearchHighlights {
    NSMutableArray<NSValue*>* ranges = [NSMutableArray arrayWithCapacity:_searchMatches.count];
    for (SPDFMarkdownSearchMatch* match in _searchMatches) [ranges addObject:[NSValue valueWithRange:match.range]];
    _pagedView.searchRanges = ranges;
}

- (void)clearSearch {
    [_searchToken cancel];
    _searchToken = nil;
    _searchGeneration++;
    _searchMatches = @[];
    _currentMatchIndex = -1;
    [self removeSearchHighlights];
    if (self.searchUpdateHandler) self.searchUpdateHandler(0, -1, NO);
}

- (void)searchForQuery:(NSString*)query preferredIndex:(NSInteger)preferredIndex {
    [_searchToken cancel];
    _searchToken = nil;
    _searchGeneration++;
    NSUInteger searchGeneration = _searchGeneration;
    if (!query.length || !self.renderedDocument || !_active) {
        _searchMatches = @[];
        _currentMatchIndex = -1;
        [self removeSearchHighlights];
        if (self.searchUpdateHandler) self.searchUpdateHandler(0, -1, NO);
        return;
    }
    if (self.searchUpdateHandler) self.searchUpdateHandler(0, -1, YES);
    SPDFMarkdownCancellationToken* token = [SPDFMarkdownCancellationToken new];
    _searchToken = token;
    SPDFMarkdownRenderedDocument* snapshot = self.renderedDocument;
    dispatch_async(_workQueue ?: dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSArray* matches = [snapshot searchForQuery:query caseSensitive:NO cancellationToken:token];
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_active || token.isCancelled || searchGeneration != self->_searchGeneration) return;
        self->_searchToken = nil;
        self->_searchMatches = matches ?: @[];
        self->_currentMatchIndex =
            self->_searchMatches.count ? MAX(0, MIN(preferredIndex, (NSInteger)self->_searchMatches.count - 1)) : -1;
        [self applySearchHighlights];
        if (self->_currentMatchIndex >= 0) [self revealCurrentMatch];
        if (self.searchUpdateHandler)
            self.searchUpdateHandler(self->_searchMatches.count, self->_currentMatchIndex, NO);
      });
    });
}

- (void)revealCurrentMatch {
    if (_currentMatchIndex < 0 || _currentMatchIndex >= (NSInteger)_searchMatches.count) return;
    NSRange range = _searchMatches[(NSUInteger)_currentMatchIndex].range;
    [_pagedView revealRange:range];
    if (self.searchUpdateHandler) self.searchUpdateHandler(_searchMatches.count, _currentMatchIndex, NO);
}

- (void)moveToNextMatch:(BOOL)forward {
    if (_searchMatches.count == 0) return;
    NSInteger count = (NSInteger)_searchMatches.count;
    _currentMatchIndex =
        _currentMatchIndex < 0 ? (forward ? 0 : count - 1) : (_currentMatchIndex + (forward ? 1 : -1) + count) % count;
    [self revealCurrentMatch];
}

- (void)goToSearchMatchAtIndex:(NSInteger)matchIndex {
    if (matchIndex < 0 || matchIndex >= (NSInteger)_searchMatches.count) return;
    _currentMatchIndex = matchIndex;
    [self revealCurrentMatch];
}

- (BOOL)scrollToHeadingAnchor:(NSString*)anchor {
    NSString* slug = spdf_mac_markdown_heading_slug(anchor);
    for (SPDFMarkdownRenderedHeading* heading in self.renderedDocument.headings) {
        if ([spdf_mac_markdown_heading_slug(heading.title) isEqualToString:slug]) {
            [_pagedView revealRange:heading.attributedRange];
            return YES;
        }
    }
    return NO;
}

- (void)navigateToAnchorWhenReady:(NSString*)anchor {
    _pendingAnchor = [anchor copy];
    if (_active && self.state == SPDFMacMarkdownSessionReady && [self scrollToHeadingAnchor:_pendingAnchor])
        _pendingAnchor = nil;
}

- (void)activateDestination:(NSString*)destination wikiLink:(BOOL)wikiLink {
    SPDFMacMarkdownLinkResolution* resolution = spdf_mac_resolve_markdown_link(destination, self.documentURL, wikiLink);
    if (resolution.kind == SPDFMacMarkdownLinkExternal) {
        if (self.openExternalURLHandler) self.openExternalURLHandler(resolution.URL);
    } else if (resolution.kind == SPDFMacMarkdownLinkDocument) {
        if (self.openDocumentHandler) self.openDocumentHandler(resolution.URL, resolution.anchor);
    } else if (resolution.kind == SPDFMacMarkdownLinkAnchor) {
        if (![self scrollToHeadingAnchor:resolution.anchor] && self.statusHandler)
            self.statusHandler(@"Heading not found.");
    } else if (self.statusHandler)
        self.statusHandler(@"Blocked unsafe or unsupported Markdown link.");
}

- (void)showLanguagePickerForCodeBlock:(NSUInteger)blockIndex parentWindow:(NSWindow*)window {
    if (!window || ![self.document.model blockWithIndex:blockIndex]) return;
    if (!_languagePicker) _languagePicker = [SPDFMacMarkdownLanguagePickerController new];
    NSRect anchor = [_pagedView codeLanguageControlFrameInViewForBlockIndex:blockIndex];
    if (NSIsEmptyRect(anchor)) {
        // Scrolled away or invoked from the context menu: reveal the block's
        // page so its language control can anchor the popover.
        SPDFMarkdownRenderedBlock* block = [self.renderedDocument renderedBlockWithIndex:blockIndex];
        if (block) [_pagedView revealRange:block.attributedRange];
        anchor = [_pagedView codeLanguageControlFrameInViewForBlockIndex:blockIndex];
    }
    if (NSIsEmptyRect(anchor))
        anchor = NSMakeRect(NSMidX(_pagedView.bounds) - 4.0, NSMinY(_pagedView.bounds) + 4.0, 8.0, 8.0);
    __weak SPDFMacMarkdownSession* weakSelf = self;
    [_languagePicker presentFromView:_pagedView
                          anchorRect:anchor
                          completion:^(SPDFMarkdownLanguage* language) {
                            SPDFMacMarkdownSession* strongSelf = weakSelf;
                            if (!strongSelf || !language || !strongSelf->_active) return;
                            [strongSelf applyLanguageIdentifier:language.identifier toCodeBlock:blockIndex];
                          }];
}

- (void)applyLanguageIdentifier:(NSString*)identifier toCodeBlock:(NSUInteger)blockIndex {
    if (!identifier.length || ![self.document.model blockWithIndex:blockIndex]) return;
    _languageOverrides[@(blockIndex)] = identifier;
    [self rerenderDocumentWithStatus:@"Code language updated."];
}

// Shared rerender flow for language overrides and font-scale changes: every
// pass renders with the session's current font scale so either kind of change
// survives the other. A nil/empty status skips the status callback.
- (void)rerenderDocumentWithStatus:(NSString*)status {
    [_renderToken cancel];
    _renderGeneration++;
    NSUInteger renderGeneration = _renderGeneration;
    CGFloat fontScale = _fontScale;
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
                 SPDFMarkdownPaginator* paginator = [SPDFMarkdownPaginator new];
                 SPDFMarkdownPageConfiguration* configuration = [SPDFMarkdownPageConfiguration A4PortraitConfiguration];
                 configuration.includesCodeLanguageControlSpacing = YES;
                 NSArray* items = [paginator measureRenderedDocument:rendered
                                                      containerWidth:NSWidth(configuration.printableRect)];
                 SPDFMarkdownPaginationPlan* plan = [paginator paginateItems:items configuration:configuration];
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
                   [mainSelf installRenderedDocument:rendered
                                      paginationPlan:plan
                                   interactiveString:interactive
                                preserveCurrentState:YES];
                   if (status.length && mainSelf.statusHandler) mainSelf.statusHandler(status);
                 });
               }];
}

- (void)goToPageAtIndex:(NSInteger)pageIndex {
    [_pagedView goToPageAtIndex:pageIndex alignTop:YES];
}
- (void)zoomByFactor:(CGFloat)factor {
    [_pagedView zoomByFactor:factor];
}
- (void)setZoom:(CGFloat)zoom {
    NSRect visible = _pagedView.documentVisibleRect;
    [_pagedView setZoom:zoom centeredAtPoint:NSMakePoint(NSMidX(visible), NSMidY(visible))];
}
- (void)applyFitMode:(SPDFMacMarkdownPageFitMode)fitMode {
    [_pagedView applyFitMode:fitMode];
}
- (void)setPresentationMode:(BOOL)presentationMode {
    _pagedView.presentationMode = presentationMode;
}
- (NSUInteger)pageIndexForRange:(NSRange)range {
    return [_pagedView pageIndexForRange:range];
}
- (void)revealRange:(NSRange)range {
    [_pagedView revealRange:range];
}
- (void)centerAtDocumentPoint:(NSPoint)point {
    [_pagedView centerAtDocumentPoint:point];
}
- (void)centerOnPageAtIndex:(NSInteger)pageIndex xFraction:(CGFloat)xFraction yFraction:(CGFloat)yFraction {
    [_pagedView centerOnPageAtIndex:pageIndex xFraction:xFraction yFraction:yFraction];
}
- (void)scrollByDocumentDeltaX:(CGFloat)deltaX deltaY:(CGFloat)deltaY {
    [_pagedView scrollByDocumentDeltaX:deltaX deltaY:deltaY];
}
- (void)forwardScrollWheelEvent:(NSEvent*)event {
    [_pagedView forwardScrollWheelEvent:event];
}
- (void)magnifyByDelta:(CGFloat)delta {
    [_pagedView magnifyByDelta:delta];
}
- (BOOL)zoomWithScrollWheelEvent:(NSEvent*)event centeredAtWindowPoint:(NSPoint)windowPoint {
    return [_pagedView zoomWithScrollWheelEvent:event centeredAtWindowPoint:windowPoint];
}
- (void)magnifyByDelta:(CGFloat)delta centeredAtWindowPoint:(NSPoint)windowPoint {
    [_pagedView magnifyByDelta:delta centeredAtWindowPoint:windowPoint];
}
- (void)magnifyByDelta:(CGFloat)delta centeredAtDocumentPoint:(NSPoint)documentPoint {
    [_pagedView magnifyByDelta:delta centeredAtDocumentPoint:documentPoint];
}
- (void)noteExternalScrollPositionChanged {
    [_pagedView noteExternalScrollPositionChanged];
}

@end
