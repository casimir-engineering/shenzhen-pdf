#pragma once

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SPDFMarkdownPage;
@class SPDFMarkdownPaginationItem;

typedef NS_ENUM(NSInteger, SPDFMarkdownPageDecorationType) {
    SPDFMarkdownPageDecorationTypeCodeBox,
    SPDFMarkdownPageDecorationTypeHeadingRule,
};

// GitHub-flavored page chrome colors. The Markdown page renders as white paper
// in every app appearance (PDF parity), so screen, print and export all use
// this one concrete light palette. The print-prefixed names are aliases kept
// for the export/Print call sites.
@interface SPDFMarkdownTheme : NSObject
+ (NSColor*)codeBoxFillColor;
+ (NSColor*)codeBoxStrokeColor;
// Quiet chrome for the interactive language control drawn inside a code box.
+ (NSColor*)codeControlFillColor;
+ (NSColor*)codeControlStrokeColor;
+ (NSColor*)codeControlTextColor;
+ (NSColor*)headingRuleColor;
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
// full-printable-width box per page portion covering its reserved spacer bands;
// level 1 and 2 headings contribute a 1px underline rule.
FOUNDATION_EXPORT NSArray<SPDFMarkdownPageDecoration*>* SPDFMarkdownDecorationsForPage(
    SPDFMarkdownPage* page, NSArray<SPDFMarkdownPaginationItem*>* items, CGFloat printableWidth);

NS_ASSUME_NONNULL_END
