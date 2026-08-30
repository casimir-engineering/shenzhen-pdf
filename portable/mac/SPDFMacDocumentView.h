#import <Cocoa/Cocoa.h>

#import "SPDFMacModels.h"
#import "markdown/SPDFMarkdownDecorations.h"
#import "SPDFMacSelectionClick.h"
#import "SPDFMacUIHelpers.h"

@protocol SPDFMacDocumentViewReader <SPDFMacUIReader>
- (BOOL)documentViewSelectionChangedOnPage:(NSInteger)pageIndex
                                      from:(NSPoint)start
                                        to:(NSPoint)end
                               granularity:(SPDFMacSelectionGranularity)granularity;
@end

@interface SPDFDocumentView : NSView <NSDraggingDestination>
@property(nonatomic, copy) NSArray<SPDFRenderedPage*>* pages;
@property(nonatomic) NSInteger currentPageIndex;
@property(nonatomic) CGFloat zoom;
@property(nonatomic) CGFloat viewportWidthHint;
@property(nonatomic) CGFloat viewportHeightHint;
@property(nonatomic) CGFloat backingScale;
@property(nonatomic) NSInteger activeFindPageIndex;
@property(nonatomic) NSRect activeFindRect;
@property(nonatomic) CGFloat activeFindAlpha;
@property(nonatomic) BOOL presentationMode;
// The active reading theme, threaded in from the delegate exactly like the
// Markdown canvas's plan variant. It decides the gutter fill and how a page is
// separated from it: light keeps the drop shadow, dark draws a 1px border
// (a black shadow is invisible against a dark gutter).
@property(nonatomic) SPDFMarkdownThemeVariant themeVariant;
@property(nonatomic) BOOL liveZooming;
@property(nonatomic, copy) NSString* emptyMessage;
@property(nonatomic, weak) id<SPDFMacDocumentViewReader> reader;
- (NSSize)documentSizeForClipSize:(NSSize)clipSize;
// Image-only page refresh: swaps in an updated pages array whose page SIZES are
// unchanged (only a render image differs), keeping the layout cache valid and
// repainting just the changed page — unlike the `pages` setter, which fully
// invalidates layout and repaints the whole view. Use on render-completion /
// eviction hot paths to avoid an O(n) layout rebuild + full redraw per page.
- (void)refreshRenderedPages:(NSArray<SPDFRenderedPage*>*)pages changedPageIndex:(NSInteger)changedIndex;
- (NSRect)rectForPageAtIndex:(NSInteger)pageIndex;
- (NSInteger)pageIndexForVisibleRect:(NSRect)visibleRect;
- (BOOL)point:(NSPoint)point fallsInPage:(NSInteger*)pageIndex pagePoint:(NSPoint*)pagePoint;
- (void)cancelTransientInteraction;
// Re-resolve the pointer cursor (I-beam / hand / arrow) for the current mouse
// location, e.g. after a cursor-region cache fill or when a pan drag ends.
// No-op when the pointer is outside the view.
- (void)refreshCursorForMouseLocation;
// The page-separation decision for the active theme, split into fill/stroke
// choices so a headless test can probe it without rasterizing — the mirror of
// the Markdown canvas's paperFillColor/drawsPaperShadow seam. pageBorderColor
// is nil whenever no border is drawn (light theme).
@end

// Implemented in SPDFMacDocumentViewTheme.mm.
@interface SPDFDocumentView (Theme)
- (BOOL)drawsPageShadow;
- (NSColor*)pageBorderColor;  // nil when no border is drawn
// The viewport gutter behind the sheets: the theme's own dark gutter, or the
// unchanged system-derived canvas background in light.
- (NSColor*)viewportBackgroundColor;
// Drawn after the page content, so the hairline stays crisp at the page edge.
- (void)drawPageBorderInRect:(NSRect)pageRect;
@end
