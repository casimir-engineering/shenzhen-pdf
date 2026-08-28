#pragma once

#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>

#import "SPDFMarkdownDecorations.h"
#import "SPDFMarkdownRenderer.h"

NS_ASSUME_NONNULL_BEGIN

// CoreText gives U+FFFC backed by an NSTextAttachment (which carries no
// CTRunDelegate) a tiny default advance, so a plain
// CTLineCreateWithAttributedString would place everything after an inline
// attachment far left of where the NSLayoutManager measurement that produced
// the pagination fragments put it. Every CTLine built from a fragment
// substring — drawing, hit-testing, highlight/selection x-mapping, and the
// attachment offset math — must go through this shared constructor, which
// mirrors each attachment's bounds into a CTRunDelegate (width = bounds width,
// ascent = the bounds' extent above the baseline, descent = any part below),
// matching how TextKit places attachments on the baseline. Caller releases.
FOUNDATION_EXPORT CTLineRef SPDFMarkdownCreateFragmentLine(NSAttributedString* lineString) CF_RETURNS_RETAINED;

@class SPDFMarkdownTableRowInfo;

@interface SPDFMarkdownPageConfiguration : NSObject <NSCopying>
@property(nonatomic) NSSize paperSize;
@property(nonatomic) NSRect printableRect;
@property(nonatomic) CGFloat headingKeepThreshold;
// Screen pagination can reserve space for its interactive code-language control.
// Print and export configurations intentionally default to NO.
@property(nonatomic) BOOL includesCodeLanguageControlSpacing;
// Distance from the paper's top edge down to the printable area — the TOP
// margin. Equal to NSMinY(printableRect) (the bottom margin) only when the
// vertical margins are symmetric, so every top-anchored coordinate must use
// this instead of NSMinY(printableRect).
@property(nonatomic, readonly) CGFloat topContentInset;
+ (instancetype)A4PortraitConfiguration;
+ (instancetype)configurationForPaperSize:(NSSize)paperSize printableRect:(NSRect)printableRect;
@end

@interface SPDFMarkdownTextLine : NSObject
@property(nonatomic, readonly) NSRange attributedRange;
@property(nonatomic, readonly) CGFloat height;
@property(nonatomic, readonly) CGFloat xOffset;
@property(nonatomic, readonly) CGFloat baselineOffset;
// Vertical offset of this line from the top of its own pagination item. Zero
// for ordinary stacked lines. Table rows place cell lines side by side inside
// the row band, so their lines carry real row-local offsets and the row is
// paginated atomically (see paginateItems:).
@property(nonatomic, readonly) CGFloat rowLocalYOffset;
- (instancetype)initWithAttributedRange:(NSRange)attributedRange
                                 height:(CGFloat)height
                                xOffset:(CGFloat)xOffset
                         baselineOffset:(CGFloat)baselineOffset
                        rowLocalYOffset:(CGFloat)rowLocalYOffset NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithAttributedRange:(NSRange)attributedRange
                                 height:(CGFloat)height
                                xOffset:(CGFloat)xOffset
                         baselineOffset:(CGFloat)baselineOffset;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface SPDFMarkdownPaginationItem : NSObject
@property(nonatomic, readonly) NSUInteger blockIndex;
@property(nonatomic, readonly) SPDFMarkdownBlockKind kind;
@property(nonatomic, readonly) NSUInteger headingLevel;
// Non-nil only for table rows: role and column geometry carried from the
// rendered block so decoration planning can draw the table grid.
@property(nonatomic, readonly, nullable) SPDFMarkdownTableRowInfo* tableRowInfo;
@property(nonatomic, readonly, copy) NSArray<SPDFMarkdownTextLine*>* lines;
@property(nonatomic, readonly) CGFloat measuredHeight;
- (instancetype)initWithBlockIndex:(NSUInteger)blockIndex
                              kind:(SPDFMarkdownBlockKind)kind
                      headingLevel:(NSUInteger)headingLevel
                      tableRowInfo:(nullable SPDFMarkdownTableRowInfo*)tableRowInfo
                             lines:(NSArray<SPDFMarkdownTextLine*>*)lines NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithBlockIndex:(NSUInteger)blockIndex
                              kind:(SPDFMarkdownBlockKind)kind
                      headingLevel:(NSUInteger)headingLevel
                             lines:(NSArray<SPDFMarkdownTextLine*>*)lines;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface SPDFMarkdownPageFragment : NSObject
@property(nonatomic, readonly) NSUInteger itemIndex;
@property(nonatomic, readonly) NSUInteger blockIndex;
@property(nonatomic, readonly) NSRange attributedRange;
@property(nonatomic, readonly) CGFloat pageYOffset;
@property(nonatomic, readonly) CGFloat height;
@property(nonatomic, readonly) CGFloat xOffset;
@property(nonatomic, readonly) CGFloat baselineOffset;
@property(nonatomic, readonly) CGFloat scale;
@property(nonatomic, readonly, getter=isContinuation) BOOL continuation;
@end

@interface SPDFMarkdownPage : NSObject
@property(nonatomic, readonly) NSUInteger pageIndex;
@property(nonatomic, readonly, copy) NSArray<SPDFMarkdownPageFragment*>* fragments;
@property(nonatomic, readonly) CGFloat usedHeight;
@end

@interface SPDFMarkdownPaginationPlan : NSObject
@property(nonatomic, readonly, copy) SPDFMarkdownPageConfiguration* configuration;
@property(nonatomic, readonly, copy) NSArray<SPDFMarkdownPaginationItem*>* items;
@property(nonatomic, readonly, copy) NSArray<SPDFMarkdownPage*>* pages;

// Per-page decoration geometry (code boxes, heading rules) in page-content
// coordinates. Print/export draws these itself; the screen canvas consumes the
// same geometry with the dynamic SPDFMarkdownTheme colors.
- (NSArray<SPDFMarkdownPageDecoration*>*)decorationsForPageIndex:(NSUInteger)pageIndex;
@end

// Concrete-palette page drawing, implemented in SPDFMarkdownPaginatorDrawing.mm.
@interface SPDFMarkdownPaginationPlan (SPDFDrawing)
// Draws the same exact line-fragment plan used by print preview/pagination.
// Decorations are painted first, beneath the planned text.
- (BOOL)drawPageAtIndex:(NSUInteger)pageIndex
       attributedString:(NSAttributedString*)attributedString
              inContext:(CGContextRef)context;
@end

@interface SPDFMarkdownPaginator : NSObject
- (SPDFMarkdownPaginationPlan*)paginateItems:(NSArray<SPDFMarkdownPaginationItem*>*)items
                               configuration:(SPDFMarkdownPageConfiguration*)configuration;
- (NSArray<SPDFMarkdownPaginationItem*>*)measureRenderedDocument:(SPDFMarkdownRenderedDocument*)document
                                                  containerWidth:(CGFloat)containerWidth;
@end

NS_ASSUME_NONNULL_END
