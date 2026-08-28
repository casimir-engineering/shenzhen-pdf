#pragma once

#import <AppKit/AppKit.h>

#import "SPDFMarkdownDecorations.h"

NS_ASSUME_NONNULL_BEGIN

@class SPDFMarkdownPageFragment;
@class SPDFMarkdownPaginationItem;

// Geometry and role of one rendered table row. The block renderer records this
// on the row's rendered block (and the paginator carries it onto the row's
// pagination item), so decoration planning never re-derives tab-stop math from
// pixels. Column boundaries are the column edge x positions in page-content
// space — columnCount + 1 values, including the table's left and right edges,
// already offset by the row's list-depth indentation. bodyRowIndex counts body
// rows from 0 across the whole table, so a table split across pages keeps its
// zebra-stripe parity.
@interface SPDFMarkdownTableRowInfo : NSObject
@property(nonatomic, readonly) NSUInteger tableBlockIndex;
@property(nonatomic, readonly, getter=isHeaderRow) BOOL headerRow;
@property(nonatomic, readonly) NSUInteger bodyRowIndex;
@property(nonatomic, readonly, copy) NSArray<NSNumber*>* columnBoundaries;
- (instancetype)initWithTableBlockIndex:(NSUInteger)tableBlockIndex
                              headerRow:(BOOL)headerRow
                           bodyRowIndex:(NSUInteger)bodyRowIndex
                       columnBoundaries:(NSArray<NSNumber*>*)columnBoundaries NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

// Appends the GitHub-style table decorations for one table portion on one page:
// a header-row fill band, subtle stripe fills on odd body rows, then the 1px
// hairline grid (fills are emitted before hairlines so the lines always paint
// on top of the bands). fragments[startIndex] must belong to a table row item;
// consecutive fragments of rows from the same table are consumed and the index
// of the first fragment past the table portion is returned. The grid closes at
// the portion's top and bottom, so a table continuing across pages closes at
// the page break and resumes on the next page.
FOUNDATION_EXPORT NSUInteger SPDFMarkdownAppendTableDecorations(
    NSArray<SPDFMarkdownPageFragment*>* fragments, NSUInteger startIndex,
    NSArray<SPDFMarkdownPaginationItem*>* items, CGFloat printableWidth,
    NSMutableArray<SPDFMarkdownPageDecoration*>* decorations);

// Paints one table decoration (header band, stripe, or grid hairline) with its
// concrete SPDFMarkdownTheme color. rect is in the drawing context's own
// coordinates; the caller has already mapped page-content geometry.
FOUNDATION_EXPORT void SPDFMarkdownDrawTableDecoration(CGContextRef context,
                                                       SPDFMarkdownPageDecorationType type,
                                                       CGRect rect);

NS_ASSUME_NONNULL_END
