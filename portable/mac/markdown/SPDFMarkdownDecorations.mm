#import "SPDFMarkdownDecorations.h"

#import "SPDFMarkdownPaginator.h"
#import "SPDFMarkdownTableDecorations.h"

static NSColor* SPDFRGB(unsigned int hex) {
    return [NSColor colorWithSRGBRed:((hex >> 16) & 0xff) / 255.0
                               green:((hex >> 8) & 0xff) / 255.0
                                blue:(hex & 0xff) / 255.0
                               alpha:1];
}

const CGFloat SPDFMarkdownCodeBoxOuterMargin = 14.0;

// The Markdown page is white paper in every app appearance (PDF parity), so
// screen, print and export share one concrete sRGB light palette. Text sits in
// GitHub's near-black #1F2328 rather than pure black; everything muted uses
// #59636E; chrome hairlines use the #D0D7DE/#D1D9E0 border grays.
@implementation SPDFMarkdownTheme
+ (NSColor*)bodyTextColor { return SPDFRGB(0x1F2328); }
+ (NSColor*)secondaryTextColor { return SPDFRGB(0x59636E); }
+ (NSColor*)linkColor { return SPDFRGB(0x0969DA); }
+ (NSColor*)inlineCodeChipColor { return SPDFRGB(0xEFF1F2); }
+ (NSColor*)syntaxCommentColor { return SPDFRGB(0x59636E); }
+ (NSColor*)syntaxStringColor { return SPDFRGB(0x0A3069); }
+ (NSColor*)syntaxNumberColor { return SPDFRGB(0x0550AE); }
+ (NSColor*)syntaxKeyColor { return SPDFRGB(0x953800); }
+ (NSColor*)syntaxMarkupColor { return SPDFRGB(0x8250DF); }
+ (NSColor*)syntaxKeywordColor { return SPDFRGB(0xCF222E); }
+ (NSColor*)codeBoxFillColor { return SPDFRGB(0xF6F8FA); }
+ (NSColor*)codeBoxStrokeColor { return SPDFRGB(0xD0D7DE); }
+ (NSColor*)headingRuleColor { return SPDFRGB(0xD1D9E0); }
+ (NSColor*)thematicBreakRuleColor { return SPDFRGB(0xD1D9E0); }
+ (NSColor*)tableGridColor { return SPDFRGB(0xD1D9E0); }
+ (NSColor*)tableHeaderFillColor { return SPDFRGB(0xEAEEF2); }
+ (NSColor*)tableStripeFillColor { return SPDFRGB(0xFAFBFC); }
+ (NSColor*)codeControlFillColor { return SPDFRGB(0xEAEEF2); }
+ (NSColor*)codeControlStrokeColor { return SPDFRGB(0xD0D7DE); }
+ (NSColor*)codeControlTextColor { return SPDFRGB(0x59636E); }
+ (NSColor*)printCodeBoxFillColor { return self.codeBoxFillColor; }
+ (NSColor*)printCodeBoxStrokeColor { return self.codeBoxStrokeColor; }
+ (NSColor*)printHeadingRuleColor { return self.headingRuleColor; }
@end

@implementation SPDFMarkdownPageDecoration
- (instancetype)initWithType:(SPDFMarkdownPageDecorationType)type
                        rect:(NSRect)rect
                  blockIndex:(NSUInteger)blockIndex {
    self = [super init];
    if (self) {
        _type = type;
        _rect = rect;
        _blockIndex = blockIndex;
    }
    return self;
}
@end

static const CGFloat kSPDFMarkdownHeadingRuleGap = 9.0;

NSArray<SPDFMarkdownPageDecoration*>* SPDFMarkdownDecorationsForPage(SPDFMarkdownPage* page,
                                                                     NSArray<SPDFMarkdownPaginationItem*>* items,
                                                                     CGFloat printableWidth) {
    NSMutableArray<SPDFMarkdownPageDecoration*>* decorations = [NSMutableArray array];
    NSArray<SPDFMarkdownPageFragment*>* fragments = page.fragments;
    NSUInteger index = 0;
    while (index < fragments.count) {
        SPDFMarkdownPageFragment* first = fragments[index];
        SPDFMarkdownPaginationItem* tableItem = first.itemIndex < items.count ? items[first.itemIndex] : nil;
        if (tableItem.tableRowInfo) {
            // Table rows are separate items; the table planner consumes every
            // consecutive row of the same table and emits its band, stripe and
            // grid decorations in one pass.
            index = SPDFMarkdownAppendTableDecorations(fragments, index, items, printableWidth, decorations);
            continue;
        }
        NSUInteger runEnd = index;
        while (runEnd + 1 < fragments.count && fragments[runEnd + 1].itemIndex == first.itemIndex) ++runEnd;
        SPDFMarkdownPageFragment* last = fragments[runEnd];
        SPDFMarkdownPaginationItem* item = tableItem;
        if (item.kind == SPDFMarkdownBlockKindCode) {
            // The reserved spacer bands are fragments of the code item, so the
            // box covers them and each page portion gets its own box. The
            // outer margin stays unpainted: the box is inset at the item's
            // true top (a non-continuation lead band) and true bottom (the
            // trailing band), while mid-item page splits run edge to edge.
            CGFloat top = first.pageYOffset;
            CGFloat bottom = last.pageYOffset + last.height;
            if (!first.isContinuation) top += SPDFMarkdownCodeBoxOuterMargin;
            if (NSEqualRanges(last.attributedRange, item.lines.lastObject.attributedRange))
                bottom -= SPDFMarkdownCodeBoxOuterMargin;
            if (bottom - top >= 1) {
                [decorations addObject:[[SPDFMarkdownPageDecoration alloc]
                                           initWithType:SPDFMarkdownPageDecorationTypeCodeBox
                                                   rect:NSMakeRect(0, top, printableWidth, bottom - top)
                                             blockIndex:item.blockIndex]];
            }
        } else if (item.kind == SPDFMarkdownBlockKindThematicBreak) {
            // The break renders as an invisible blank line; the visible rule is
            // this 2px hairline centered in the reserved space.
            CGFloat top = first.pageYOffset;
            CGFloat bottom = last.pageYOffset + last.height;
            CGFloat y = MIN(MAX(top, top + (bottom - top) / 2 - 1), MAX(top, bottom - 2));
            [decorations addObject:[[SPDFMarkdownPageDecoration alloc]
                                       initWithType:SPDFMarkdownPageDecorationTypeThematicBreakRule
                                               rect:NSMakeRect(0, y, printableWidth, 2)
                                         blockIndex:item.blockIndex]];
        } else if (item.kind == SPDFMarkdownBlockKindHeading && item.headingLevel >= 1 && item.headingLevel <= 2 &&
                   NSEqualRanges(last.attributedRange, item.lines.lastObject.attributedRange)) {
            CGFloat y = last.pageYOffset + last.baselineOffset + kSPDFMarkdownHeadingRuleGap;
            y = MIN(y, last.pageYOffset + last.height - 1);
            [decorations addObject:[[SPDFMarkdownPageDecoration alloc]
                                       initWithType:SPDFMarkdownPageDecorationTypeHeadingRule
                                               rect:NSMakeRect(0, y, printableWidth, 1)
                                         blockIndex:item.blockIndex]];
        }
        index = runEnd + 1;
    }
    return decorations;
}
