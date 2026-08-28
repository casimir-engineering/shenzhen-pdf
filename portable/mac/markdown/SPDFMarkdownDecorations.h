#pragma once

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SPDFMarkdownPage;
@class SPDFMarkdownPaginationItem;

typedef NS_ENUM(NSInteger, SPDFMarkdownPageDecorationType) {
    SPDFMarkdownPageDecorationTypeCodeBox,
    SPDFMarkdownPageDecorationTypeHeadingRule,
    SPDFMarkdownPageDecorationTypeThematicBreakRule,
    // GitHub-style table chrome: a header-row fill band, a subtle fill on
    // alternating body rows, and the 1px hairline grid (horizontal row
    // boundaries plus vertical column boundaries).
    SPDFMarkdownPageDecorationTypeTableHeaderBand,
    SPDFMarkdownPageDecorationTypeTableStripe,
    SPDFMarkdownPageDecorationTypeTableGridLine,
};

// Unpainted page margin kept between a code box edge and its neighbors. The
// paginator reserves it inside the code item's spacer bands; the decoration
// geometry insets the drawn box by the same amount, so two consecutive code
// boxes end up two margins apart. The screen code-language control centers in
// the leading band below this margin.
FOUNDATION_EXPORT const CGFloat SPDFMarkdownCodeBoxOuterMargin;

// The reading palette, GitHub-Primer flavored. The Markdown page renders as
// white paper in every app appearance (PDF parity), so screen, print and
// export all draw from this one concrete sRGB light palette — no dynamic
// colors anywhere. Every element takes a named role from here instead of an
// ad-hoc NSColor. The print-prefixed names are aliases kept for the
// export/Print call sites.
@interface SPDFMarkdownTheme : NSObject
// Text roles.
+ (NSColor*)bodyTextColor;       // #1F2328 near-black, body and headings
+ (NSColor*)secondaryTextColor;  // #59636E muted: markers, captions, quotes, H6
+ (NSColor*)linkColor;           // #0969DA
+ (NSColor*)inlineCodeChipColor; // #EFF1F2 inline-code chip background
// Syntax token roles (Primer light).
+ (NSColor*)syntaxCommentColor;  // #59636E
+ (NSColor*)syntaxStringColor;   // #0A3069
+ (NSColor*)syntaxNumberColor;   // #0550AE
+ (NSColor*)syntaxKeyColor;      // #953800
+ (NSColor*)syntaxMarkupColor;   // #8250DF
+ (NSColor*)syntaxKeywordColor;  // #CF222E
// Page chrome roles.
+ (NSColor*)codeBoxFillColor;
+ (NSColor*)codeBoxStrokeColor;
// Quiet chrome for the interactive language control drawn inside a code box.
+ (NSColor*)codeControlFillColor;
+ (NSColor*)codeControlStrokeColor;
+ (NSColor*)codeControlTextColor;
+ (NSColor*)headingRuleColor;
+ (NSColor*)thematicBreakRuleColor;
// Table chrome roles, Primer-flavored like the code box.
+ (NSColor*)tableGridColor;        // #D1D9E0 1px hairline grid
+ (NSColor*)tableHeaderFillColor;  // #EAEEF2 header-row band, darker than the stripe
+ (NSColor*)tableStripeFillColor;  // #FAFBFC alternating body rows
+ (NSColor*)printCodeBoxFillColor;
+ (NSColor*)printCodeBoxStrokeColor;
+ (NSColor*)printHeadingRuleColor;
@end

// One drawable decoration on one page. The rect is in page-content coordinates:
// x is relative to the printable rect's left edge and y is the offset from the
// printable top, the same space as SPDFMarkdownPageFragment.pageYOffset.
@interface SPDFMarkdownPageDecoration : NSObject
@property(nonatomic, readonly) SPDFMarkdownPageDecorationType type;
@property(nonatomic, readonly) NSRect rect;
@property(nonatomic, readonly) NSUInteger blockIndex;
- (instancetype)initWithType:(SPDFMarkdownPageDecorationType)type
                        rect:(NSRect)rect
                  blockIndex:(NSUInteger)blockIndex NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

// Computes the decorations for one planned page. A code item contributes one
// full-printable-width box per page portion covering its reserved spacer bands
// (inset by SPDFMarkdownCodeBoxOuterMargin at the item's true top and bottom);
// level 1 and 2 headings contribute a 1px underline rule; a thematic break
// contributes a 2px full-width rule centered in its reserved line.
FOUNDATION_EXPORT NSArray<SPDFMarkdownPageDecoration*>* SPDFMarkdownDecorationsForPage(
    SPDFMarkdownPage* page, NSArray<SPDFMarkdownPaginationItem*>* items, CGFloat printableWidth);

NS_ASSUME_NONNULL_END
