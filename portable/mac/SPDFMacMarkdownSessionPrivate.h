#pragma once

#import "SPDFMacMarkdownSession.h"

#import "SPDFMacMarkdownMinimapModel.h"
#import "SPDFMacMarkdownPagedView.h"
#import "markdown/SPDFMarkdown.h"

@class SPDFMacMarkdownLanguagePickerController;
@class SPDFMacMarkdownSessionImageLoader;

NS_ASSUME_NONNULL_BEGIN

// Shared between the session lifecycle (SPDFMacMarkdownSession.mm) and its
// find/search (SPDFMacMarkdownSession+Search.mm) and interaction
// (SPDFMacMarkdownSession+Interaction.mm) halves; not part of the public
// session API. The remaining lifecycle-only ivars stay declared in
// SPDFMacMarkdownSession.mm's implementation block.
@interface SPDFMacMarkdownSession () {
  @protected
    SPDFMacMarkdownPagedView* _Nullable _pagedView;
    SPDFMarkdownPaginationPlan* _Nullable _paginationPlan;
    // Lazily built LIGHT export rendition, populated only while the session
    // renders DARK. _exportRenditionSource is the renderedDocument it was
    // derived from: a rerender installs a new object, which invalidates the
    // cache by identity with no explicit bookkeeping (see
    // SPDFMacMarkdownSession+Export.mm).
    SPDFMarkdownPaginationPlan* _Nullable _exportPlan;
    NSAttributedString* _Nullable _exportAttributedString;
    SPDFMarkdownRenderedDocument* _Nullable _exportRenditionSource;
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
    // Lazily created by the RemoteImages half; nil until the document's first
    // active render encounters a remote image target.
    SPDFMacMarkdownSessionImageLoader* _Nullable _imageLoader;
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
// The export rendition, implemented in SPDFMacMarkdownSession+Export.mm.
@interface SPDFMacMarkdownSession (Export)
@end

// Paginates a rendition exactly the way the live screen pass does, so an export
// plan and the on-screen plan differ in palette and nothing else. Shared by the
// lifecycle passes and the export rendition; implemented alongside the latter.
FOUNDATION_EXPORT SPDFMarkdownPaginationPlan* SPDFMacMarkdownPlanForRendition(
    SPDFMarkdownRenderedDocument* rendered, SPDFMarkdownThemeVariant variant);

@interface SPDFMacMarkdownSession (LifecycleInternal)
// Shared rerender flow for language overrides and font-scale changes. A
// nil/empty status skips the status callback.
- (void)rerenderDocumentWithStatus:(NSString* _Nullable)status;
// The session's current render options with an EXPLICIT theme variant, so the
// export half can ask for a light rendition of a dark session.
- (SPDFMarkdownRenderOptions*)renderOptionsForThemeVariant:(SPDFMarkdownThemeVariant)variant;
@end

// Interaction internals the lifecycle half calls across the file split;
// implemented in SPDFMacMarkdownSession+Interaction.mm.
@interface SPDFMacMarkdownSession (InteractionInternal)
- (void)activateDestination:(NSString*)destination wikiLink:(BOOL)wikiLink;
- (void)applyLanguageIdentifier:(NSString*)identifier toCodeBlock:(NSUInteger)blockIndex;
@end

// Remote-image lazy loading, implemented in
// SPDFMacMarkdownSession+RemoteImages.mm. Downloads start only once an ACTIVE
// session installs a render containing https image targets; arrivals feed
// SPDFMarkdownRenderOptions.remoteImageData and trigger one coalesced
// viewport-preserving rerender per batch.
@interface SPDFMacMarkdownSession (RemoteImages)
// The session's lazily created loader; tests inject their fetcher seam here
// before activating.
- (SPDFMacMarkdownSessionImageLoader*)remoteImageLoader;
// Replaces the loader (tests supply one with a private cache directory) and
// rebinds its update handler to this session's coalesced rerender.
- (void)installRemoteImageLoader:(SPDFMacMarkdownSessionImageLoader*)loader;
- (void)applyRemoteImageState:(SPDFMarkdownRenderOptions*)options;
- (void)startRemoteImageFetchesIfNeeded;
- (void)cancelQueuedRemoteImageFetches;
@end

NS_ASSUME_NONNULL_END
