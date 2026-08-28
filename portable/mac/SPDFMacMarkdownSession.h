#pragma once

#import <AppKit/AppKit.h>
#import "SPDFMacMarkdownPagedView.h"

@class SPDFMarkdownDocument;
@class SPDFMarkdownPaginationPlan;
@class SPDFMarkdownRenderedDocument;
@class SPDFMarkdownSearchMatch;
@class SPDFMacMarkdownMinimapModel;
@class SPDFMacMarkdownSidebarModel;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPDFMacMarkdownSessionState) {
    SPDFMacMarkdownSessionIdle,
    SPDFMacMarkdownSessionLoading,
    SPDFMacMarkdownSessionReady,
    SPDFMacMarkdownSessionFailed,
};

@interface SPDFMacMarkdownSession : NSObject
@property(nonatomic, readonly, copy) NSURL* documentURL;
@property(nonatomic, readonly) NSView* rootView;
@property(nonatomic, weak, nullable) id<SPDFMacUIReader> reader;
@property(nonatomic, readonly, nullable) NSTextView* textView;
@property(nonatomic, readonly, nullable) SPDFMarkdownDocument* document;
@property(nonatomic, readonly, nullable) SPDFMarkdownRenderedDocument* renderedDocument;
// The live on-screen pagination plan (current font scale, language overrides,
// reserved language-control band). Print and Save-as-PDF consume this plan
// with renderedDocument so exports match the reader page for page.
@property(nonatomic, readonly, nullable) SPDFMarkdownPaginationPlan* paginationPlan;
@property(nonatomic, readonly) SPDFMacMarkdownSessionState state;
@property(nonatomic, readonly, copy) NSArray<SPDFMarkdownSearchMatch*>* searchMatches;
@property(nonatomic, readonly) NSInteger currentMatchIndex;
@property(nonatomic, readonly) NSPoint scrollOrigin;
@property(nonatomic, readonly) NSRange selectedRange;
@property(nonatomic, readonly, copy) NSString* selectedText;
@property(nonatomic, readonly) NSUInteger pageCount;
@property(nonatomic, readonly) NSInteger currentPageIndex;
@property(nonatomic, readonly) NSUInteger visibleAttributedLocation;
@property(nonatomic, readonly) CGFloat zoom;
@property(nonatomic, readonly) SPDFMacMarkdownPageFitMode fitMode;
// Uniform typography multiplier applied to every render, clamped to
// [0.5, 3.0]. Set at creation for the first render; applyFontScale: rerenders
// the active session while preserving its viewport state.
@property(nonatomic, readonly) CGFloat fontScale;
@property(nonatomic, readonly, copy) NSArray<NSValue*>* documentPageRects;
@property(nonatomic, readonly) NSRect documentVisibleRect;
@property(nonatomic, readonly) NSSize documentCanvasSize;
@property(nonatomic, readonly, nullable) SPDFMacMarkdownMinimapModel* minimapModel;
@property(nonatomic, readonly, nullable) SPDFMacMarkdownSidebarModel* sidebarModel;
@property(nonatomic, copy, nullable) void (^openDocumentHandler)(NSURL* URL, NSString* _Nullable anchor);
@property(nonatomic, copy, nullable) void (^openExternalURLHandler)(NSURL* URL);
@property(nonatomic, copy, nullable) void (^statusHandler)(NSString* status);
@property(nonatomic, copy, nullable) void (^searchUpdateHandler)
    (NSUInteger count, NSInteger currentIndex, BOOL searching);
// Fired by next/previous/explicit match jumps (never by searchUpdateHandler's
// search lifecycle), so index-only changes can refresh controls without
// rebuilding the sidebar — the PDF jump path's split.
@property(nonatomic, copy, nullable) void (^matchIndexChangedHandler)(NSInteger currentIndex, NSUInteger count);
// Human-readable engine failure from the last completed search (an invalid
// regex pattern); nil after a successful search or clear.
@property(nonatomic, readonly, copy, nullable) NSString* searchErrorDescription;
@property(nonatomic, copy, nullable) void (^viewportUpdateHandler)
    (NSInteger pageIndex, CGFloat zoom, SPDFMacMarkdownPageFitMode fitMode);

- (instancetype)initWithDocumentURL:(NSURL*)URL;
- (instancetype)initWithDocumentURL:(NSURL*)URL fontScale:(CGFloat)fontScale NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)applyFontScale:(CGFloat)scale;
- (void)activateInHostView:(NSView*)hostView
                 workQueue:(dispatch_queue_t)workQueue
              scrollOrigin:(NSPoint)scrollOrigin
             selectedRange:(NSRange)selectedRange
                 pageIndex:(NSInteger)pageIndex
                      zoom:(CGFloat)zoom
                   fitMode:(SPDFMacMarkdownPageFitMode)fitMode
                    anchor:(nullable NSString*)anchor
                completion:(void (^)(BOOL success, NSError* _Nullable error))completion;
- (void)deactivate;
- (void)cancelAllOperations;
- (BOOL)scrollToHeadingAnchor:(NSString*)anchor;
- (void)navigateToAnchorWhenReady:(NSString*)anchor;
- (void)showLanguagePickerForCodeBlock:(NSUInteger)blockIndex parentWindow:(NSWindow*)window;
- (void)goToPageAtIndex:(NSInteger)pageIndex;
- (void)zoomByFactor:(CGFloat)factor;
- (void)setZoom:(CGFloat)zoom;
- (void)applyFitMode:(SPDFMacMarkdownPageFitMode)fitMode;
- (void)setPresentationMode:(BOOL)presentationMode;
- (NSUInteger)pageIndexForRange:(NSRange)range;
- (void)revealRange:(NSRange)range;
- (void)centerAtDocumentPoint:(NSPoint)point;
- (void)centerOnPageAtIndex:(NSInteger)pageIndex xFraction:(CGFloat)xFraction yFraction:(CGFloat)yFraction;
- (void)scrollByDocumentDeltaX:(CGFloat)deltaX deltaY:(CGFloat)deltaY;
- (void)forwardScrollWheelEvent:(NSEvent*)event;
- (void)magnifyByDelta:(CGFloat)delta;
- (BOOL)zoomWithScrollWheelEvent:(NSEvent*)event centeredAtWindowPoint:(NSPoint)windowPoint;
- (void)magnifyByDelta:(CGFloat)delta centeredAtWindowPoint:(NSPoint)windowPoint;
- (void)magnifyByDelta:(CGFloat)delta centeredAtDocumentPoint:(NSPoint)documentPoint;
- (void)noteExternalScrollPositionChanged;
@end

// Implemented in SPDFMacMarkdownSession+Search.mm: the PDF-parity find half of
// the session (nearest-match selection, centered reveal with the animated red
// flash, regex support, and scrollbar trough markers).
@interface SPDFMacMarkdownSession (Search)
// Convenience for the full search below: plain (non-regex) query, no
// nearest-match preference, revealing the selected match.
- (void)searchForQuery:(NSString*)query preferredIndex:(NSInteger)preferredIndex;
// PDF-parity search. preferredIndex < 0 means "no explicit target": the match
// nearest the current viewport is selected when jumpToNearest is set, else the
// first match. reveal == NO keeps the viewport still (no scroll, no flash) —
// the toolbar's non-revealing restore path.
- (void)searchForQuery:(NSString*)query
                 regex:(BOOL)regex
        preferredIndex:(NSInteger)preferredIndex
         jumpToNearest:(BOOL)jumpToNearest
                reveal:(BOOL)reveal;
- (void)clearSearch;
- (void)moveToNextMatch:(BOOL)forward;
- (void)goToSearchMatchAtIndex:(NSInteger)matchIndex;
// PDF-parity scrollbar trough markers: one {fraction, active} entry per search
// match (fraction = match center Y / canvas height), the shape
// [reader findScrollbarMarkers] serves to SPDFFindMarkerScroller.
- (NSArray<NSDictionary*>*)searchScrollbarMarkers;
- (void)invalidateSearchScrollbarMarkers;
@end

NS_ASSUME_NONNULL_END
