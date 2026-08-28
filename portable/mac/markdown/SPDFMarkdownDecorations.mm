#import "SPDFMarkdownDecorations.h"

#import "SPDFMarkdownPaginator.h"

static NSColor* SPDFRGB(unsigned int hex) {
    return [NSColor colorWithSRGBRed:((hex >> 16) & 0xff) / 255.0
                               green:((hex >> 8) & 0xff) / 255.0
                                blue:(hex & 0xff) / 255.0
                               alpha:1];
}

static NSColor* SPDFDynamicColor(NSString* name, NSColor* light, NSColor* dark) {
    return [NSColor colorWithName:name
                  dynamicProvider:^NSColor*(NSAppearance* appearance) {
                    NSAppearanceName best = [appearance
                        bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]];
                    return [best isEqualToString:NSAppearanceNameDarkAqua] ? dark : light;
                  }];
}

@implementation SPDFMarkdownTheme
+ (NSColor*)printCodeBoxFillColor { return SPDFRGB(0xF6F8FA); }
+ (NSColor*)printCodeBoxStrokeColor { return SPDFRGB(0xD0D7DE); }
+ (NSColor*)printHeadingRuleColor { return SPDFRGB(0xD8DEE4); }
+ (NSColor*)codeBoxFillColor {
    return SPDFDynamicColor(@"SPDFMarkdownCodeBoxFill", SPDFRGB(0xF6F8FA), SPDFRGB(0x151B23));
}
+ (NSColor*)codeBoxStrokeColor {
    return SPDFDynamicColor(@"SPDFMarkdownCodeBoxStroke", SPDFRGB(0xD0D7DE), SPDFRGB(0x3D444D));
}
+ (NSColor*)codeControlFillColor {
    return SPDFDynamicColor(@"SPDFMarkdownCodeControlFill", SPDFRGB(0xEAEEF2), SPDFRGB(0x212830));
}
+ (NSColor*)codeControlStrokeColor {
    return SPDFDynamicColor(@"SPDFMarkdownCodeControlStroke", SPDFRGB(0xD0D7DE), SPDFRGB(0x3D444D));
}
+ (NSColor*)headingRuleColor {
    return SPDFDynamicColor(@"SPDFMarkdownHeadingRule", SPDFRGB(0xD8DEE4), SPDFRGB(0x3D444D));
}
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

static const CGFloat kSPDFMarkdownHeadingRuleGap = 6.0;

NSArray<SPDFMarkdownPageDecoration*>* SPDFMarkdownDecorationsForPage(SPDFMarkdownPage* page,
                                                                     NSArray<SPDFMarkdownPaginationItem*>* items,
                                                                     CGFloat printableWidth) {
    NSMutableArray<SPDFMarkdownPageDecoration*>* decorations = [NSMutableArray array];
    NSArray<SPDFMarkdownPageFragment*>* fragments = page.fragments;
    NSUInteger index = 0;
    while (index < fragments.count) {
        SPDFMarkdownPageFragment* first = fragments[index];
        NSUInteger runEnd = index;
        while (runEnd + 1 < fragments.count && fragments[runEnd + 1].itemIndex == first.itemIndex) ++runEnd;
        SPDFMarkdownPageFragment* last = fragments[runEnd];
        SPDFMarkdownPaginationItem* item = first.itemIndex < items.count ? items[first.itemIndex] : nil;
        if (item.kind == SPDFMarkdownBlockKindCode) {
            // The reserved spacer bands are fragments of the code item, so the
            // box covers them and each page portion gets its own box.
            CGFloat top = first.pageYOffset;
            CGFloat bottom = last.pageYOffset + last.height;
            [decorations addObject:[[SPDFMarkdownPageDecoration alloc]
                                       initWithType:SPDFMarkdownPageDecorationTypeCodeBox
                                               rect:NSMakeRect(0, top, printableWidth, bottom - top)
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
