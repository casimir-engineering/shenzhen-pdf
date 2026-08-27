#import "SPDFMacMarkdownSession.h"

#import "SPDFMacMarkdownLanguagePicker.h"
#import "SPDFMacMarkdownRouting.h"
#import "SPDFMacMarkdownView.h"
#import "markdown/SPDFMarkdown.h"

@interface SPDFMacMarkdownSession () <SPDFMacMarkdownTextViewEventDelegate>
@property(nonatomic) SPDFMacMarkdownSessionState state;
@property(nonatomic, strong, nullable) SPDFMarkdownDocument* document;
@property(nonatomic, strong, nullable) SPDFMarkdownRenderedDocument* renderedDocument;
@end

@implementation SPDFMacMarkdownSession {
    NSScrollView* _scrollView;
    NSTextField* _placeholder;
    SPDFMacMarkdownTextView* _textView;
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
    NSString* _pendingAnchor;
}

- (instancetype)initWithDocumentURL:(NSURL*)URL {
    NSParameterAssert(URL.isFileURL);
    self = [super init];
    if (!self) return nil;
    _documentURL = [URL copy];
    _searchMatches = @[];
    _currentMatchIndex = -1;
    _languageOverrides = [NSMutableDictionary dictionary];
    [self buildRootView];
    return self;
}

- (void)buildRootView {
    NSAssert(NSThread.isMainThread, @"Markdown AppKit views must be created on the main thread");
    _scrollView = [[NSScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.autohidesScrollers = YES;
    _scrollView.borderType = NSNoBorder;
    _scrollView.drawsBackground = YES;
    _scrollView.backgroundColor = NSColor.textBackgroundColor;
    _placeholder = [NSTextField labelWithString:@"Loading Markdown..."];
    _placeholder.alignment = NSTextAlignmentCenter;
    _placeholder.textColor = NSColor.secondaryLabelColor;
    _placeholder.frame = NSMakeRect(0, 0, 420, 80);
    _scrollView.documentView = _placeholder;
}

- (NSView*)rootView { return _scrollView; }
- (NSTextView*)textView { return _textView; }
- (NSArray<SPDFMarkdownSearchMatch*>*)searchMatches { return _searchMatches ?: @[]; }
- (NSInteger)currentMatchIndex { return _currentMatchIndex; }
- (NSPoint)scrollOrigin { return _scrollView.contentView.bounds.origin; }
- (NSRange)selectedRange { return _textView ? _textView.selectedRange : NSMakeRange(0, 0); }
- (NSString*)selectedText {
    NSRange range = self.selectedRange;
    return _textView && NSMaxRange(range) <= _textView.string.length ? [_textView.string substringWithRange:range] : @"";
}

- (void)attachToHostView:(NSView*)hostView {
    if (_scrollView.superview != hostView) {
        [_scrollView removeFromSuperview];
        [hostView addSubview:_scrollView];
        [NSLayoutConstraint activateConstraints:@[
            [_scrollView.topAnchor constraintEqualToAnchor:hostView.topAnchor],
            [_scrollView.leadingAnchor constraintEqualToAnchor:hostView.leadingAnchor],
            [_scrollView.trailingAnchor constraintEqualToAnchor:hostView.trailingAnchor],
            [_scrollView.bottomAnchor constraintEqualToAnchor:hostView.bottomAnchor],
        ]];
    }
}

- (void)activateInHostView:(NSView*)hostView
                 workQueue:(dispatch_queue_t)workQueue
              scrollOrigin:(NSPoint)scrollOrigin
             selectedRange:(NSRange)selectedRange
                    anchor:(NSString*)anchor
                completion:(void (^)(BOOL, NSError*))completion {
    NSAssert(NSThread.isMainThread, @"Markdown activation must occur on the main thread");
    [self cancelAllOperations];
    _active = YES;
    NSUInteger activationGeneration = _activationGeneration;
    _workQueue = workQueue ?: dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    _pendingScrollOrigin = scrollOrigin;
    _pendingSelectedRange = selectedRange;
    _pendingAnchor = [anchor copy];
    [self attachToHostView:hostView];
    if (self.document && self.renderedDocument) {
        [self installRenderedDocument:self.renderedDocument preserveCurrentState:NO];
        if (completion) completion(YES, nil);
        return;
    }

    self.state = SPDFMacMarkdownSessionLoading;
    _placeholder.stringValue = @"Loading Markdown...";
    _scrollView.documentView = _placeholder;
    NSURL* URL = self.documentURL;
    dispatch_async(_workQueue, ^{
      NSError* error = nil;
      SPDFMarkdownDocument* document = [SPDFMarkdownDocument documentWithURL:URL options:nil error:&error];
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_active || activationGeneration != self->_activationGeneration) return;
        if (!document) {
            self.state = SPDFMacMarkdownSessionFailed;
            self->_placeholder.stringValue = error.localizedDescription ?: @"Could not open Markdown document.";
            self->_scrollView.documentView = self->_placeholder;
            if (completion) completion(NO, error);
            return;
        }
        self.document = document;
        self.renderedDocument = document.renderedDocument;
        self.state = SPDFMacMarkdownSessionReady;
        [self installRenderedDocument:self.renderedDocument preserveCurrentState:NO];
        if (completion) completion(YES, nil);
      });
    });
}

- (SPDFMacMarkdownTextView*)newTextViewForRenderedDocument:(SPDFMarkdownRenderedDocument*)rendered {
    SPDFMacMarkdownTextView* view = [[SPDFMacMarkdownTextView alloc] initWithFrame:NSMakeRect(0, 0, 600, 10)];
    view.editable = NO;
    view.selectable = YES;
    view.richText = YES;
    view.importsGraphics = YES;
    view.drawsBackground = YES;
    view.backgroundColor = NSColor.textBackgroundColor;
    view.textContainerInset = NSMakeSize(self.document.renderOptions.contentInset,
                                        self.document.renderOptions.contentInset);
    view.verticallyResizable = YES;
    view.horizontallyResizable = NO;
    view.autoresizingMask = NSViewWidthSizable;
    view.minSize = NSMakeSize(0, 0);
    view.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    view.textContainer.widthTracksTextView = YES;
    view.textContainer.containerSize = NSMakeSize(MAX(1, _scrollView.contentSize.width), CGFLOAT_MAX);
    view.markdownEventDelegate = self;
    [view.textStorage setAttributedString:SPDFMacMarkdownInteractiveString(self.document.model, rendered)];
    [view sizeToFit];
    return view;
}

- (void)installRenderedDocument:(SPDFMarkdownRenderedDocument*)rendered preserveCurrentState:(BOOL)preserve {
    if (!_active || !rendered) return;
    NSPoint origin = preserve && _textView ? self.scrollOrigin : _pendingScrollOrigin;
    NSRange selection = preserve && _textView ? self.selectedRange : _pendingSelectedRange;
    _textView = [self newTextViewForRenderedDocument:rendered];
    _scrollView.documentView = _textView;
    if (_searchMatches.count) [self applySearchHighlights];
    if (selection.location != NSNotFound && NSMaxRange(selection) <= _textView.string.length)
        _textView.selectedRange = selection;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!self->_active || self->_scrollView.documentView != self->_textView) return;
      if (self->_pendingAnchor.length) {
          [self scrollToHeadingAnchor:self->_pendingAnchor];
          self->_pendingAnchor = nil;
      } else {
          [self->_scrollView.contentView scrollToPoint:origin];
          [self->_scrollView reflectScrolledClipView:self->_scrollView.contentView];
      }
    });
}

- (void)deactivate {
    _pendingScrollOrigin = self.scrollOrigin;
    _pendingSelectedRange = self.selectedRange;
    _active = NO;
    [self cancelAllOperations];
    [_scrollView removeFromSuperview];
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

- (void)dealloc { [self cancelAllOperations]; }

- (void)removeSearchHighlights {
    NSLayoutManager* layout = _textView.layoutManager;
    if (layout && _textView.textStorage.length)
        [layout removeTemporaryAttribute:NSBackgroundColorAttributeName
                       forCharacterRange:NSMakeRange(0, _textView.textStorage.length)];
}

- (void)applySearchHighlights {
    [self removeSearchHighlights];
    NSLayoutManager* layout = _textView.layoutManager;
    for (SPDFMarkdownSearchMatch* match in _searchMatches) {
        if (NSMaxRange(match.range) <= _textView.textStorage.length)
            [layout addTemporaryAttribute:NSBackgroundColorAttributeName
                                    value:[NSColor.systemYellowColor colorWithAlphaComponent:0.42]
                        forCharacterRange:match.range];
    }
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
        self->_currentMatchIndex = self->_searchMatches.count
            ? MAX(0, MIN(preferredIndex, (NSInteger)self->_searchMatches.count - 1)) : -1;
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
    [_textView scrollRangeToVisible:range];
    [_textView showFindIndicatorForRange:range];
    if (self.searchUpdateHandler) self.searchUpdateHandler(_searchMatches.count, _currentMatchIndex, NO);
}

- (void)moveToNextMatch:(BOOL)forward {
    if (_searchMatches.count == 0) return;
    NSInteger count = (NSInteger)_searchMatches.count;
    _currentMatchIndex = _currentMatchIndex < 0 ? (forward ? 0 : count - 1)
        : (_currentMatchIndex + (forward ? 1 : -1) + count) % count;
    [self revealCurrentMatch];
}

- (BOOL)scrollToHeadingAnchor:(NSString*)anchor {
    NSString* slug = spdf_mac_markdown_heading_slug(anchor);
    for (SPDFMarkdownRenderedHeading* heading in self.renderedDocument.headings) {
        if ([spdf_mac_markdown_heading_slug(heading.title) isEqualToString:slug]) {
            [_textView scrollRangeToVisible:heading.attributedRange];
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

- (void)markdownTextView:(NSTextView*)textView
       activateDestination:(NSString*)destination
                  wikiLink:(BOOL)wikiLink {
    (void)textView;
    SPDFMacMarkdownLinkResolution* resolution = spdf_mac_resolve_markdown_link(destination, self.documentURL, wikiLink);
    if (resolution.kind == SPDFMacMarkdownLinkExternal) {
        if (self.openExternalURLHandler) self.openExternalURLHandler(resolution.URL);
    } else if (resolution.kind == SPDFMacMarkdownLinkDocument) {
        if (self.openDocumentHandler) self.openDocumentHandler(resolution.URL, resolution.anchor);
    } else if (resolution.kind == SPDFMacMarkdownLinkAnchor) {
        if (![self scrollToHeadingAnchor:resolution.anchor] && self.statusHandler)
            self.statusHandler(@"Heading not found.");
    } else if (self.statusHandler) self.statusHandler(@"Blocked unsafe or unsupported Markdown link.");
}

- (void)markdownTextView:(NSTextView*)textView chooseLanguageForCodeBlock:(NSUInteger)blockIndex {
    [self showLanguagePickerForCodeBlock:blockIndex parentWindow:textView.window];
}

- (void)showLanguagePickerForCodeBlock:(NSUInteger)blockIndex parentWindow:(NSWindow*)window {
    if (!window || ![self.document.model blockWithIndex:blockIndex]) return;
    if (!_languagePicker) _languagePicker = [SPDFMacMarkdownLanguagePickerController new];
    __weak SPDFMacMarkdownSession* weakSelf = self;
    [_languagePicker presentForWindow:window completion:^(SPDFMarkdownLanguage* language) {
      SPDFMacMarkdownSession* strongSelf = weakSelf;
      if (!strongSelf || !language || !strongSelf->_active) return;
      [strongSelf applyLanguageIdentifier:language.identifier toCodeBlock:blockIndex];
    }];
}

- (void)applyLanguageIdentifier:(NSString*)identifier toCodeBlock:(NSUInteger)blockIndex {
    if (!identifier.length || ![self.document.model blockWithIndex:blockIndex]) return;
    _languageOverrides[@(blockIndex)] = identifier;
    [self rerenderWithLanguageOverrides];
}

- (void)rerenderWithLanguageOverrides {
    [_renderToken cancel];
    _renderGeneration++;
    NSUInteger renderGeneration = _renderGeneration;
    NSDictionary* overrides = [_languageOverrides copy];
    __weak SPDFMacMarkdownSession* weakSelf = self;
    _renderToken = [self.document renderWithLanguageOverrides:overrides
                                                    workQueue:_workQueue
                                               completionQueue:dispatch_get_main_queue()
                                                   completion:^(SPDFMarkdownRenderedDocument* rendered, BOOL cancelled) {
      SPDFMacMarkdownSession* strongSelf = weakSelf;
      if (!strongSelf || cancelled || !strongSelf->_active ||
          renderGeneration != strongSelf->_renderGeneration || !rendered)
          return;
      strongSelf->_renderToken = nil;
      strongSelf.renderedDocument = rendered;
      [strongSelf installRenderedDocument:rendered preserveCurrentState:YES];
      if (strongSelf.statusHandler) strongSelf.statusHandler(@"Code language updated.");
    }];
}

@end
