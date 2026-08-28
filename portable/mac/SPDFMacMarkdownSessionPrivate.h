#pragma once

#import "SPDFMacMarkdownSession.h"

#import "SPDFMacMarkdownMinimapModel.h"
#import "SPDFMacMarkdownPagedView.h"
#import "markdown/SPDFMarkdown.h"

NS_ASSUME_NONNULL_BEGIN

// Shared between the session lifecycle (SPDFMacMarkdownSession.mm) and its
// find/search half (SPDFMacMarkdownSession+Search.mm); not part of the public
// session API. The remaining lifecycle-only ivars stay declared in
// SPDFMacMarkdownSession.mm's implementation block.
@interface SPDFMacMarkdownSession () {
  @protected
    SPDFMacMarkdownPagedView* _Nullable _pagedView;
    SPDFMacMarkdownMinimapModel* _Nullable _minimapModel;
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

NS_ASSUME_NONNULL_END
