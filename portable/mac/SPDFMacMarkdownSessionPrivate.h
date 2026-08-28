#pragma once

#import "SPDFMacMarkdownSession.h"

#import "SPDFMacMarkdownMinimapModel.h"
#import "SPDFMacMarkdownPagedView.h"
#import "markdown/SPDFMarkdown.h"

@class SPDFMacMarkdownLanguagePickerController;

NS_ASSUME_NONNULL_BEGIN

// Shared between the session lifecycle (SPDFMacMarkdownSession.mm) and its
// find/search (SPDFMacMarkdownSession+Search.mm) and interaction
// (SPDFMacMarkdownSession+Interaction.mm) halves; not part of the public
// session API. The remaining lifecycle-only ivars stay declared in
// SPDFMacMarkdownSession.mm's implementation block.
@interface SPDFMacMarkdownSession () {
  @protected
    SPDFMacMarkdownPagedView* _Nullable _pagedView;
    SPDFMacMarkdownMinimapModel* _Nullable _minimapModel;
    NSString* _Nullable _pendingAnchor;
    NSMutableDictionary<NSNumber*, NSString*>* _languageOverrides;
    SPDFMacMarkdownLanguagePickerController* _Nullable _languagePicker;
    NSArray<SPDFMarkdownSearchMatch*>* _searchMatches;
    NSInteger _currentMatchIndex;
    // The live query/regex flag, kept so a font-scale or language re-render can
    // re-run the search against the freshly rendered attributed string instead
    // of reapplying stale ranges.
    NSString* _Nullable _activeSearchQuery;
    BOOL _activeSearchRegex;
    NSString* _Nullable _searchErrorDescription;
    // PDF-parity current-match flash (stepFindFlash:'s envelope) driving the
    // paged view's activeSearchRange/activeSearchAlpha overlay.
    NSTimer* _Nullable _matchFlashTimer;
    NSTimeInterval _matchFlashStartTime;
    SPDFMarkdownCancellationToken* _Nullable _searchToken;
    NSUInteger _searchGeneration;
    dispatch_queue_t _Nullable _workQueue;
    BOOL _active;
}
@property(nonatomic) SPDFMacMarkdownSessionState state;
@property(nonatomic, strong, nullable) SPDFMarkdownDocument* document;
@property(nonatomic, strong, nullable) SPDFMarkdownRenderedDocument* renderedDocument;
@end

// Search internals the lifecycle half calls across the file split; implemented
// in SPDFMacMarkdownSession+Search.mm.
@interface SPDFMacMarkdownSession (SearchInternal)
- (void)applySearchHighlights;
- (void)removeSearchHighlights;
- (void)clearMatchFlash;
@end

// Lifecycle internals the interaction half calls across the file split;
// implemented in SPDFMacMarkdownSession.mm.
@interface SPDFMacMarkdownSession (LifecycleInternal)
// Shared rerender flow for language overrides and font-scale changes. A
// nil/empty status skips the status callback.
- (void)rerenderDocumentWithStatus:(NSString* _Nullable)status;
@end

// Interaction internals the lifecycle half calls across the file split;
// implemented in SPDFMacMarkdownSession+Interaction.mm.
@interface SPDFMacMarkdownSession (InteractionInternal)
- (void)activateDestination:(NSString*)destination wikiLink:(BOOL)wikiLink;
- (void)applyLanguageIdentifier:(NSString*)identifier toCodeBlock:(NSUInteger)blockIndex;
@end

NS_ASSUME_NONNULL_END
