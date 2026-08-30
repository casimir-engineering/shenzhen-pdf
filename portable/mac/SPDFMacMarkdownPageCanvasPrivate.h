#pragma once

#import "SPDFMacMarkdownPageCanvas.h"

@class SPDFMarkdownPaginationPlan;

@class SPDFMarkdownPage;
@class SPDFMarkdownPageFragment;
@class SPDFMacMarkdownPanController;

// Shared between SPDFMacMarkdownPageCanvas.mm and its categories
// (SPDFMacMarkdownPageCanvas+Navigation.mm); not part of the public canvas API.
@interface SPDFMacMarkdownPageCanvas ()
@property(nonatomic, readonly) SPDFMarkdownPaginationPlan* plan;
@property(nonatomic, readonly) NSAttributedString* attributedString;
// YES while a left-button selection drag is in flight (forces the I-beam in
// updateCursorForPointInWindow:, matching the PDF view's selection drag).
@property(nonatomic, readonly, getter=isDraggingSelection) BOOL draggingSelection;
// Double-click word selection: the word containing `index`, else the image
// attachment character at (or just before — CTLine hit-testing returns the
// caret index, which lands after the character for a right-half click) the
// index, so double-clicking an image selects exactly its attachment
// character. Zero length when neither resolves.
- (NSRange)wordRangeAtIndex:(NSUInteger)index;
// Character index under a canvas-space point (a caret index: a click on a
// character's right half resolves to the following index), NSNotFound when
// the point is not over a drawn line fragment.
- (NSUInteger)characterIndexAtPoint:(NSPoint)point;
@end

// Implemented in SPDFMacMarkdownPageCanvas+Pan.mm: the lazily created hand-pan
// controller shared by the right-/middle-button pan handlers and the cursor
// precedence logic (an active pan grab owns the cursor).
@interface SPDFMacMarkdownPageCanvas (Pan)
@property(nonatomic, readonly) SPDFMacMarkdownPanController* spdf_panController;
@end

// Drawing/geometry internals implemented alongside the public (Decorations)
// category in SPDFMacMarkdownPageCanvas+Decorations.mm.
@interface SPDFMacMarkdownPageCanvas (DecorationsInternal)
// Paper presentation for the plan's theme variant: the light theme keeps the
// white sheet + drop shadow, the dark theme paints the theme paper with a 1px
// border instead. paperFillColor/drawsPaperShadow expose the decision to
// headless tests. viewportBackgroundColor is the gutter AROUND the sheets: the
// theme's own dark gutter, or windowBackgroundColor unchanged in light.
- (NSColor*)paperFillColor;
- (BOOL)drawsPaperShadow;
- (NSColor*)viewportBackgroundColor;
- (void)drawPaperBackgroundInFrame:(NSRect)pageFrame;
- (void)drawPaperBorderInFrame:(NSRect)pageFrame;
- (SPDFMarkdownPageFragment*)codeControlFragmentOnPage:(SPDFMarkdownPage*)page blockIndex:(NSUInteger)blockIndex;
- (NSRect)codeLanguageControlRectForFragment:(SPDFMarkdownPageFragment*)fragment pageFrame:(NSRect)pageFrame;
- (NSRect)codeLanguageControlHitRectForFragment:(SPDFMarkdownPageFragment*)fragment pageFrame:(NSRect)pageFrame;
- (void)drawCodeLanguageControlsOnPage:(SPDFMarkdownPage*)page pageFrame:(NSRect)pageFrame;
// Canvas-space rects of every link-run portion inside the page's line
// fragments, using the same CTLine offset mapping the highlight drawing uses.
- (NSArray<NSValue*>*)linkRectsForPage:(SPDFMarkdownPage*)page pageFrame:(NSRect)pageFrame;
@end

// Search/highlight geometry internals implemented alongside the public
// (Search) category in SPDFMacMarkdownPageCanvas+Search.mm.
@interface SPDFMacMarkdownPageCanvas (SearchInternal)
// The single source of truth for range-to-rect mapping: PAGE-LOCAL rects
// (relative to the page frame origin, flipped like the canvas) for every
// portion of `ranges` rendered by `page`, in fragment order.
- (void)enumeratePageLocalRectsForRanges:(NSArray<NSValue*>*)ranges
                                  onPage:(SPDFMarkdownPage*)page
                              usingBlock:(void (^)(NSRect rect))block;
// PDF-parity animated red outline around the active find match.
- (void)drawActiveSearchOnPage:(SPDFMarkdownPage*)page pageFrame:(NSRect)pageFrame;
@end
