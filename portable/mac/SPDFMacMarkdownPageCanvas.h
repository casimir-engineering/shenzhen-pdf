#pragma once

#import <AppKit/AppKit.h>

#import "SPDFMacCursorRegions.h"

@class SPDFMarkdownPaginationPlan;
@protocol SPDFMacUIReader;

NS_ASSUME_NONNULL_BEGIN

@interface SPDFMacMarkdownPageCanvas : NSView
@property(nonatomic, weak, nullable) id<SPDFMacUIReader> reader;
@property(nonatomic, readonly) NSUInteger pageCount;
@property(nonatomic) BOOL presentationMode;
@property(nonatomic) NSRange selectedRange;
@property(nonatomic, copy) NSArray<NSValue*>* searchRanges;
// Current find match, drawn as the PDF view's animated red outline. {0,0}
// means none; setting either property repaints only (no scrolling).
@property(nonatomic) NSRange activeSearchRange;
@property(nonatomic) CGFloat activeSearchAlpha;  // 0..1 outline opacity
@property(nonatomic, copy, nullable) void (^selectionChangedHandler)(NSRange range);
@property(nonatomic, copy, nullable) void (^activateDestinationHandler)(NSString* destination, BOOL wikiLink);
@property(nonatomic, copy, nullable) void (^chooseCodeLanguageHandler)(NSUInteger blockIndex);

- (instancetype)initWithPaginationPlan:(SPDFMarkdownPaginationPlan*)plan
                      attributedString:(NSAttributedString*)attributedString NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder*)coder NS_UNAVAILABLE;
// Viewport size in CANVAS coordinates (the paged view's clip bounds size, which
// is contentSize / magnification). Drives the exact-fit vertical inset: the
// outer canvas inset collapses to 0 as the page height reaches the viewport
// (Fit Page puts the page top at the viewport top with nothing to scroll on a
// one-page document) and a single page shorter than the viewport is centered
// vertically. NSZeroSize (standalone canvases) keeps the full decorative inset.
@property(nonatomic) NSSize layoutViewportSize;
- (NSRect)frameForPageAtIndex:(NSUInteger)pageIndex;
- (void)resizeForWidth:(CGFloat)width;
- (NSInteger)pageIndexForVisibleRect:(NSRect)visibleRect;
- (NSUInteger)attributedLocationNearestToPoint:(NSPoint)point;
@end

// Implemented in SPDFMacMarkdownPageCanvas+Navigation.mm.
@interface SPDFMacMarkdownPageCanvas (Navigation)
- (BOOL)scrollRangeToVisible:(NSRange)range;
- (NSUInteger)pageIndexForRange:(NSRange)range;
// Canvas-space rect of the first rendered portion of `range`: the range's
// glyph run inside the fragment that renders range.location, falling back to
// that fragment's full line band. NSZeroRect when the plan has no pages.
- (NSRect)firstRectForRange:(NSRange)range;
@end

// Implemented in SPDFMacMarkdownPageCanvas+Decorations.mm: the dynamic-color
// page chrome (code boxes, heading rules) and the code-language control that
// lives in each code box's header band.
@interface SPDFMacMarkdownPageCanvas (Decorations)
- (nullable NSNumber*)codeLanguageBlockAtPoint:(NSPoint)point;
- (nullable NSString*)codeLanguageLabelForBlockIndex:(NSUInteger)blockIndex;
// Canvas-space frame of the language control for a code block, or NSZeroRect
// when the block index has no code-language control in the plan.
- (NSRect)codeLanguageControlFrameForBlockIndex:(NSUInteger)blockIndex;
@end

// Implemented in SPDFMacMarkdownPageCanvas+Cursor.mm: PDF-parity pointer
// feedback driven by the tracking area (pointing hand over links and the
// code-language control, I-beam over text line boxes, arrow elsewhere).
@interface SPDFMacMarkdownPageCanvas (Cursor)
// Resolve the cursor region for a canvas-space point: the code-language
// control and link runs (2pt slop) beat text; text requires the point to be
// inside a fragment's line box on a page; margins, page gaps, and the gutter
// resolve to none. Presentation mode forces none (arrow).
- (SPDFCursorRegionKind)cursorRegionAtPoint:(NSPoint)point;
// Re-resolve the pointer cursor (I-beam / hand / arrow) for the current mouse
// location, e.g. after a scroll/zoom change or when a pan drag ends. No-op
// when the pointer is outside the view.
- (void)refreshCursorForMouseLocation;
@end

// Implemented in SPDFMacMarkdownPageCanvas+Search.mm.
@interface SPDFMacMarkdownPageCanvas (Search)
// Per page index, the rects of every range portion rendered on that page, in
// PAGE-LOCAL coordinates (relative to that page's frame origin, same flipped
// orientation as the canvas), using the same CTLine mapping as highlight
// drawing. Pages without a match are absent.
- (NSDictionary<NSNumber*, NSArray<NSValue*>*>*)pageLocalRectsForRanges:(NSArray<NSValue*>*)ranges;
@end

NS_ASSUME_NONNULL_END
