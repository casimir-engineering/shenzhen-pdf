#import "SPDFMarkdownPaginator.h"

#import <CoreText/CoreText.h>

@implementation SPDFMarkdownPageConfiguration
+ (instancetype)A4PortraitConfiguration {
    SPDFMarkdownPageConfiguration* value = [SPDFMarkdownPageConfiguration new];
    value.paperSize = NSMakeSize(595.2756, 841.8898);
    value.printableRect = NSMakeRect(36, 36, value.paperSize.width - 72, value.paperSize.height - 72);
    value.headingKeepThreshold = 0.75;
    return value;
}
+ (instancetype)configurationForPaperSize:(NSSize)paperSize printableRect:(NSRect)printableRect {
    SPDFMarkdownPageConfiguration* value = [SPDFMarkdownPageConfiguration new];
    value.paperSize = paperSize;
    value.printableRect = printableRect;
    value.headingKeepThreshold = 0.75;
    return value;
}
- (id)copyWithZone:(NSZone*)zone {
    SPDFMarkdownPageConfiguration* copy = [[[self class] allocWithZone:zone] init];
    copy.paperSize = self.paperSize;
    copy.printableRect = self.printableRect;
    copy.headingKeepThreshold = self.headingKeepThreshold;
    copy.includesCodeLanguageControlSpacing = self.includesCodeLanguageControlSpacing;
    return copy;
}
@end

@implementation SPDFMarkdownTextLine
- (instancetype)initWithAttributedRange:(NSRange)attributedRange
                                 height:(CGFloat)height
                                xOffset:(CGFloat)xOffset
                         baselineOffset:(CGFloat)baselineOffset {
    self = [super init];
    if (self) {
        _attributedRange = attributedRange;
        _height = MAX(height, 0.5);
        _xOffset = MAX(0, xOffset);
        _baselineOffset = MAX(0, baselineOffset);
    }
    return self;
}
@end

@implementation SPDFMarkdownPaginationItem
- (instancetype)initWithBlockIndex:(NSUInteger)blockIndex
                              kind:(SPDFMarkdownBlockKind)kind
                      headingLevel:(NSUInteger)headingLevel
                             lines:(NSArray<SPDFMarkdownTextLine*>*)lines {
    self = [super init];
    if (self) {
        _blockIndex = blockIndex;
        _kind = kind;
        _headingLevel = headingLevel;
        _lines = [lines copy];
        CGFloat height = 0;
        for (SPDFMarkdownTextLine* line in lines) height += line.height;
        _measuredHeight = height;
    }
    return self;
}
@end

@interface SPDFMarkdownPageFragment ()
- (instancetype)initWithItemIndex:(NSUInteger)itemIndex
                       blockIndex:(NSUInteger)blockIndex
                             line:(SPDFMarkdownTextLine*)line
                      pageYOffset:(CGFloat)pageYOffset
                            scale:(CGFloat)scale
                     continuation:(BOOL)continuation;
@end
@implementation SPDFMarkdownPageFragment
- (instancetype)initWithItemIndex:(NSUInteger)itemIndex
                       blockIndex:(NSUInteger)blockIndex
                             line:(SPDFMarkdownTextLine*)line
                      pageYOffset:(CGFloat)pageYOffset
                            scale:(CGFloat)scale
                     continuation:(BOOL)continuation {
    self = [super init];
    if (self) {
        _itemIndex = itemIndex;
        _blockIndex = blockIndex;
        _attributedRange = line.attributedRange;
        _pageYOffset = pageYOffset;
        _scale = MIN(1, MAX(scale, 0.001));
        _height = line.height * _scale;
        _xOffset = line.xOffset * _scale;
        _baselineOffset = line.baselineOffset * _scale;
        _continuation = continuation;
    }
    return self;
}
@end

@interface SPDFMarkdownPage ()
- (instancetype)initWithIndex:(NSUInteger)index fragments:(NSArray<SPDFMarkdownPageFragment*>*)fragments;
@end
@implementation SPDFMarkdownPage
- (instancetype)initWithIndex:(NSUInteger)index fragments:(NSArray<SPDFMarkdownPageFragment*>*)fragments {
    self = [super init];
    if (self) {
        _pageIndex = index;
        _fragments = [fragments copy];
        CGFloat height = 0;
        for (SPDFMarkdownPageFragment* fragment in fragments)
            height = MAX(height, fragment.pageYOffset + fragment.height);
        _usedHeight = height;
    }
    return self;
}
@end

@interface SPDFMarkdownPaginationPlan ()
- (instancetype)initWithConfiguration:(SPDFMarkdownPageConfiguration*)configuration
                                items:(NSArray<SPDFMarkdownPaginationItem*>*)items
                                pages:(NSArray<SPDFMarkdownPage*>*)pages;
@end
@implementation SPDFMarkdownPaginationPlan
- (instancetype)initWithConfiguration:(SPDFMarkdownPageConfiguration*)configuration
                                items:(NSArray<SPDFMarkdownPaginationItem*>*)items
                                pages:(NSArray<SPDFMarkdownPage*>*)pages {
    self = [super init];
    if (self) {
        _configuration = [configuration copy];
        _items = [items copy];
        _pages = [pages copy];
    }
    return self;
}

static void SPDFDrawAttachments(NSAttributedString* lineString, CTLineRef line, CGContextRef context, CGFloat lineX,
                                CGFloat baselineY, CGFloat lineHeight, CGFloat baselineOffset) {
    [lineString enumerateAttribute:NSAttachmentAttributeName
                           inRange:NSMakeRange(0, lineString.length)
                           options:0
                        usingBlock:^(id value, NSRange range, BOOL* stop) {
                          (void)stop;
                          NSTextAttachment* attachment = value;
                          NSImage* image = attachment.image;
                          if (!image || range.length == 0) return;
                          NSRect bounds = attachment.bounds;
                          if (bounds.size.width <= 0 || bounds.size.height <= 0) {
                              bounds.size = image.size;
                          }
                          if (bounds.size.width <= 0 || bounds.size.height <= 0) return;
                          NSRect proposed = NSMakeRect(0, 0, bounds.size.width, bounds.size.height);
                          CGImageRef CGImage = [image CGImageForProposedRect:&proposed context:nil hints:nil];
                          if (!CGImage) return;
                          CGFloat offset = CTLineGetOffsetForStringIndex(line, (CFIndex)range.location, NULL);
                          CGFloat fragmentBottom = baselineY + baselineOffset - lineHeight;
                          CGFloat fragmentTop = baselineY + baselineOffset;
                          CGFloat drawHeight = MIN(bounds.size.height, lineHeight);
                          CGFloat drawWidth = bounds.size.width * drawHeight / bounds.size.height;
                          CGFloat desiredBottom = baselineY + bounds.origin.y;
                          CGFloat attachmentBottom = MIN(MAX(desiredBottom, fragmentBottom), fragmentTop - drawHeight);
                          CGRect destination =
                              CGRectMake(lineX + offset + bounds.origin.x, attachmentBottom, drawWidth, drawHeight);
                          CGContextSaveGState(context);
                          CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
                          CGContextDrawImage(context, destination, CGImage);
                          CGContextRestoreGState(context);
                        }];
}

static NSColor* SPDFConcretePrintColor(NSColor* color, NSColor* fallback) {
    __block NSColor* converted = nil;
    NSAppearance* appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    [appearance performAsCurrentDrawingAppearance:^{
      converted = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    }];
    if (!converted) return fallback;
    CGFloat red = converted.redComponent;
    CGFloat green = converted.greenComponent;
    CGFloat blue = converted.blueComponent;
    if (red * 0.2126 + green * 0.7152 + blue * 0.0722 > 0.85) return fallback;
    return [NSColor colorWithSRGBRed:red green:green blue:blue alpha:converted.alphaComponent];
}

static NSAttributedString* SPDFPrintableLine(NSAttributedString* source) {
    NSMutableAttributedString* result = [source mutableCopy];
    NSRange all = NSMakeRange(0, result.length);
    SPDFMarkdownRenderOptions* palette = SPDFMarkdownRenderOptions.printOptions;
    [result enumerateAttribute:NSForegroundColorAttributeName
                       inRange:all
                       options:0
                    usingBlock:^(NSColor* color, NSRange range, BOOL* stop) {
                      (void)stop;
                      NSColor* concrete = SPDFConcretePrintColor(color ?: palette.textColor, palette.textColor);
                      [result addAttribute:NSForegroundColorAttributeName value:concrete range:range];
                    }];
    [result enumerateAttribute:NSBackgroundColorAttributeName
                       inRange:all
                       options:0
                    usingBlock:^(NSColor* color, NSRange range, BOOL* stop) {
                      (void)stop;
                      if (!color) return;
                      NSColor* concrete = SPDFConcretePrintColor(color, palette.codeBackgroundColor);
                      [result addAttribute:NSBackgroundColorAttributeName value:concrete range:range];
                    }];
    return result;
}

- (BOOL)drawPageAtIndex:(NSUInteger)pageIndex
       attributedString:(NSAttributedString*)attributedString
              inContext:(CGContextRef)context {
    if (pageIndex >= self.pages.count || !context) return NO;
    SPDFMarkdownPage* page = self.pages[pageIndex];
    CGFloat paperHeight = self.configuration.paperSize.height;
    CGContextSaveGState(context);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, self.configuration.paperSize.width, paperHeight));
    CGContextSetTextMatrix(context, CGAffineTransformIdentity);
    for (SPDFMarkdownPageFragment* fragment in page.fragments) {
        if (NSMaxRange(fragment.attributedRange) > attributedString.length) continue;
        NSAttributedString* substring =
            SPDFPrintableLine([attributedString attributedSubstringFromRange:fragment.attributedRange]);
        CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)substring);
        CGFloat x = NSMinX(self.configuration.printableRect) + fragment.xOffset;
        CGFloat y =
            paperHeight - NSMinY(self.configuration.printableRect) - fragment.pageYOffset - fragment.baselineOffset;
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, x, y);
        CGContextScaleCTM(context, fragment.scale, fragment.scale);
        CGContextSetTextPosition(context, 0, 0);
        CTLineDraw(line, context);
        CGFloat localScale = MAX(fragment.scale, 0.001);
        SPDFDrawAttachments(substring, line, context, 0, 0, fragment.height / localScale,
                            fragment.baselineOffset / localScale);
        CGContextRestoreGState(context);
        CFRelease(line);
    }
    CGContextRestoreGState(context);
    return YES;
}
@end

static CGFloat SPDFHeadingSectionLeadHeight(NSArray<SPDFMarkdownPaginationItem*>* items, NSUInteger headingIndex,
                                            CGFloat pageHeight) {
    SPDFMarkdownPaginationItem* heading = items[headingIndex];
    CGFloat height = 0;
    for (NSUInteger i = headingIndex; i < items.count; ++i) {
        SPDFMarkdownPaginationItem* item = items[i];
        if (i > headingIndex && item.kind == SPDFMarkdownBlockKindHeading && item.headingLevel <= heading.headingLevel)
            break;
        for (SPDFMarkdownTextLine* line in item.lines) {
            if (height + line.height > pageHeight + 0.01) return pageHeight;
            height += line.height;
        }
    }
    return height;
}

static const CGFloat kSPDFMarkdownCodeLanguageControlHeight = 26.0;

static NSArray<SPDFMarkdownPaginationItem*>* SPDFItemsForConfiguration(NSArray<SPDFMarkdownPaginationItem*>* items,
                                                                       SPDFMarkdownPageConfiguration* configuration) {
    if (!configuration.includesCodeLanguageControlSpacing) return items;
    NSMutableArray<SPDFMarkdownPaginationItem*>* configuredItems = [NSMutableArray arrayWithCapacity:items.count];
    for (SPDFMarkdownPaginationItem* item in items) {
        if (item.kind != SPDFMarkdownBlockKindCode) {
            [configuredItems addObject:item];
            continue;
        }
        NSMutableArray<SPDFMarkdownTextLine*>* lines = [item.lines mutableCopy];
        [lines insertObject:[[SPDFMarkdownTextLine alloc]
                                initWithAttributedRange:NSMakeRange(item.lines.firstObject.attributedRange.location, 0)
                                                 height:kSPDFMarkdownCodeLanguageControlHeight
                                                xOffset:0
                                         baselineOffset:0]
                    atIndex:0];
        [configuredItems addObject:[[SPDFMarkdownPaginationItem alloc] initWithBlockIndex:item.blockIndex
                                                                                     kind:item.kind
                                                                             headingLevel:item.headingLevel
                                                                                    lines:lines]];
    }
    return configuredItems;
}

@implementation SPDFMarkdownPaginator
- (SPDFMarkdownPaginationPlan*)paginateItems:(NSArray<SPDFMarkdownPaginationItem*>*)items
                               configuration:(SPDFMarkdownPageConfiguration*)configuration {
    items = SPDFItemsForConfiguration(items, configuration);
    CGFloat pageHeight = NSHeight(configuration.printableRect);
    if (pageHeight <= 0)
        return [[SPDFMarkdownPaginationPlan alloc] initWithConfiguration:configuration items:items pages:@[]];
    NSMutableArray<SPDFMarkdownPage*>* pages = [NSMutableArray array];
    NSMutableArray<SPDFMarkdownPageFragment*>* current = [NSMutableArray array];
    __block CGFloat used = 0;
    void (^finishPage)(void) = ^{
      [pages addObject:[[SPDFMarkdownPage alloc] initWithIndex:pages.count fragments:[current copy]]];
      [current removeAllObjects];
      used = 0;
    };

    for (NSUInteger itemIndex = 0; itemIndex < items.count; ++itemIndex) {
        SPDFMarkdownPaginationItem* item = items[itemIndex];
        CGFloat remaining = pageHeight - used;
        if (item.kind == SPDFMarkdownBlockKindHeading && used >= pageHeight * configuration.headingKeepThreshold) {
            CGFloat freshLead = SPDFHeadingSectionLeadHeight(items, itemIndex, pageHeight);
            if (freshLead > remaining + 0.01 && current.count) finishPage();
        }
        if (item.kind == SPDFMarkdownBlockKindHeading && item.measuredHeight <= pageHeight &&
            item.measuredHeight > pageHeight - used + 0.01 && current.count)
            finishPage();
        for (NSUInteger lineIndex = 0; lineIndex < item.lines.count; ++lineIndex) {
            SPDFMarkdownTextLine* line = item.lines[lineIndex];
            CGFloat scale = MIN(1, pageHeight / line.height);
            CGFloat height = line.height * scale;
            if (used + height > pageHeight + 0.01 && current.count) finishPage();
            [current addObject:[[SPDFMarkdownPageFragment alloc] initWithItemIndex:itemIndex
                                                                        blockIndex:item.blockIndex
                                                                              line:line
                                                                       pageYOffset:used
                                                                             scale:scale
                                                                      continuation:lineIndex > 0]];
            used += height;
        }
    }
    if (current.count || pages.count == 0) finishPage();
    return [[SPDFMarkdownPaginationPlan alloc] initWithConfiguration:configuration items:items pages:pages];
}

- (NSArray<SPDFMarkdownPaginationItem*>*)measureRenderedDocument:(SPDFMarkdownRenderedDocument*)document
                                                  containerWidth:(CGFloat)containerWidth {
    if (containerWidth <= 0 || document.attributedString.length == 0) return @[];
    NSTextStorage* storage = [[NSTextStorage alloc] initWithAttributedString:document.attributedString];
    NSLayoutManager* layout = [NSLayoutManager new];
    NSTextContainer* container = [[NSTextContainer alloc] initWithSize:NSMakeSize(containerWidth, CGFLOAT_MAX)];
    container.lineFragmentPadding = 0;
    [layout addTextContainer:container];
    [storage addLayoutManager:layout];
    [layout ensureLayoutForTextContainer:container];

    NSMutableArray* result = [NSMutableArray array];
    for (SPDFMarkdownRenderedBlock* block in document.renderedBlocks) {
        if (!block.attributedRange.length || NSMaxRange(block.attributedRange) > storage.length) continue;
        NSRange glyphRange = [layout glyphRangeForCharacterRange:block.attributedRange actualCharacterRange:nil];
        NSMutableArray* lines = [NSMutableArray array];
        [layout enumerateLineFragmentsForGlyphRange:glyphRange
                                         usingBlock:^(NSRect rect, NSRect usedRect, NSTextContainer* textContainer,
                                                      NSRange lineGlyphRange, BOOL* stop) {
                                           (void)rect;
                                           (void)textContainer;
                                           (void)stop;
                                           NSRange characterRange = [layout characterRangeForGlyphRange:lineGlyphRange
                                                                                       actualGlyphRange:nil];
                                           characterRange = NSIntersectionRange(characterRange, block.attributedRange);
                                           if (!characterRange.length) return;
                                           NSPoint glyphLocation =
                                               [layout locationForGlyphAtIndex:lineGlyphRange.location];
                                           CGFloat lineHeight = MAX(NSHeight(rect), NSHeight(usedRect));
                                           CGFloat baseline = MIN(lineHeight, MAX(0, glyphLocation.y - NSMinY(rect)));
                                           [lines addObject:[[SPDFMarkdownTextLine alloc]
                                                                initWithAttributedRange:characterRange
                                                                                 height:lineHeight
                                                                                xOffset:NSMinX(usedRect)
                                                                         baselineOffset:baseline]];
                                         }];
        if (lines.count)
            [result addObject:[[SPDFMarkdownPaginationItem alloc] initWithBlockIndex:block.blockIndex
                                                                                kind:block.kind
                                                                        headingLevel:block.level
                                                                               lines:lines]];
    }
    return result;
}
@end
