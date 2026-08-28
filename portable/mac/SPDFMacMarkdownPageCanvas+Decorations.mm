#import "SPDFMacMarkdownPageCanvasPrivate.h"

#import <CoreText/CoreText.h>

#import "markdown/SPDFMarkdown.h"

// GitHub-style code-language control anchored inside the code box header band.
static const CGFloat kSPDFMarkdownCodeControlHeight = 20.0;
static const CGFloat kSPDFMarkdownCodeControlCornerRadius = 5.0;
static const CGFloat kSPDFMarkdownCodeControlRightInset = 10.0;
static const CGFloat kSPDFMarkdownCodeControlHorizontalPadding = 9.0;
static const CGFloat kSPDFMarkdownCodeControlHitSlop = 7.0;

static NSDictionary<NSAttributedStringKey, id>* SPDFCodeControlTitleAttributes(void) {
    return @{
        NSFontAttributeName : [NSFont systemFontOfSize:11 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName : NSColor.secondaryLabelColor,
    };
}

@implementation SPDFMacMarkdownPageCanvas (Decorations)

- (NSString*)codeLanguageLabelForBlockIndex:(NSUInteger)blockIndex {
    for (SPDFMarkdownPage* page in self.plan.pages) {
        for (SPDFMarkdownPageFragment* fragment in page.fragments) {
            if (fragment.blockIndex != blockIndex || !fragment.attributedRange.length ||
                NSMaxRange(fragment.attributedRange) > self.attributedString.length)
                continue;
            NSString* identifier = [self.attributedString attribute:SPDFMarkdownCodeLanguageAttribute
                                                            atIndex:fragment.attributedRange.location
                                                     effectiveRange:NULL];
            SPDFMarkdownLanguage* language =
                [SPDFMarkdownLanguageCatalog.sharedCatalog languageForFenceIdentifier:identifier];
            return language.displayName ?: (identifier.length ? identifier : @"Plain Text");
        }
    }
    return @"Plain Text";
}

- (NSString*)codeLanguageControlTitleForBlockIndex:(NSUInteger)blockIndex {
    return [[self codeLanguageLabelForBlockIndex:blockIndex] stringByAppendingString:@" ▾"];
}

- (SPDFMarkdownPageFragment*)codeControlFragmentOnPage:(SPDFMarkdownPage*)page blockIndex:(NSUInteger)blockIndex {
    for (SPDFMarkdownPageFragment* fragment in page.fragments) {
        if (fragment.blockIndex != blockIndex || fragment.itemIndex >= self.plan.items.count) continue;
        SPDFMarkdownPaginationItem* item = self.plan.items[fragment.itemIndex];
        if (item.kind == SPDFMarkdownBlockKindCode && !fragment.isContinuation) return fragment;
    }
    return nil;
}

// The non-continuation fragment of a code item is its reserved leading band
// (see SPDFItemsForConfiguration), so the control centers vertically in the
// header band the layout actually reserved and right-aligns inside the box.
- (NSRect)codeLanguageControlRectForFragment:(SPDFMarkdownPageFragment*)fragment pageFrame:(NSRect)pageFrame {
    NSRect printable = self.plan.configuration.printableRect;
    NSString* title = [self codeLanguageControlTitleForBlockIndex:fragment.blockIndex];
    CGFloat width = ceil([title sizeWithAttributes:SPDFCodeControlTitleAttributes()].width) +
                    kSPDFMarkdownCodeControlHorizontalPadding * 2.0;
    width =
        MIN(width, MAX(kSPDFMarkdownCodeControlHeight, NSWidth(printable) - kSPDFMarkdownCodeControlRightInset * 2.0));
    CGFloat bandTop = NSMinY(pageFrame) + NSMinY(printable) + fragment.pageYOffset;
    CGFloat y = round(bandTop + (fragment.height - kSPDFMarkdownCodeControlHeight) * 0.5);
    CGFloat maxX = NSMinX(pageFrame) + NSMinX(printable) + NSWidth(printable) - kSPDFMarkdownCodeControlRightInset;
    return NSMakeRect(maxX - width, y, width, kSPDFMarkdownCodeControlHeight);
}

- (NSRect)codeLanguageControlHitRectForFragment:(SPDFMarkdownPageFragment*)fragment pageFrame:(NSRect)pageFrame {
    return NSInsetRect([self codeLanguageControlRectForFragment:fragment pageFrame:pageFrame],
                       -kSPDFMarkdownCodeControlHitSlop, -kSPDFMarkdownCodeControlHitSlop);
}

- (NSRect)codeLanguageControlFrameForBlockIndex:(NSUInteger)blockIndex {
    for (SPDFMarkdownPage* page in self.plan.pages) {
        SPDFMarkdownPageFragment* fragment = [self codeControlFragmentOnPage:page blockIndex:blockIndex];
        if (fragment)
            return [self codeLanguageControlRectForFragment:fragment
                                                  pageFrame:[self frameForPageAtIndex:page.pageIndex]];
    }
    return NSZeroRect;
}

- (NSNumber*)codeLanguageBlockAtPoint:(NSPoint)point {
    NSInteger pageIndex = [self pageIndexForVisibleRect:NSMakeRect(point.x, point.y, 1, 1)];
    if (pageIndex < 0 || pageIndex >= (NSInteger)self.pageCount) return nil;
    SPDFMarkdownPage* page = self.plan.pages[(NSUInteger)pageIndex];
    NSRect pageFrame = [self frameForPageAtIndex:(NSUInteger)pageIndex];
    for (SPDFMarkdownPageFragment* fragment in page.fragments) {
        if (fragment.itemIndex >= self.plan.items.count) continue;
        SPDFMarkdownPaginationItem* item = self.plan.items[fragment.itemIndex];
        if (item.kind != SPDFMarkdownBlockKindCode || fragment.isContinuation) continue;
        if (NSPointInRect(point, [self codeLanguageControlHitRectForFragment:fragment pageFrame:pageFrame]))
            return @(fragment.blockIndex);
    }
    return nil;
}

// Repaint the code lines of one block portion over the freshly filled box. The
// shared plan draw already painted them in the concrete print palette; drawing
// the raw interactive string here resolves its dynamic colors against the
// canvas's current appearance. Code fragments carry no attachments, so plain
// CTLineDraw reproduces the plan's text pass exactly.
- (void)drawCodeTextForBlockIndex:(NSUInteger)blockIndex page:(SPDFMarkdownPage*)page pageFrame:(NSRect)pageFrame {
    NSRect printable = self.plan.configuration.printableRect;
    CGFloat paperHeight = self.plan.configuration.paperSize.height;
    CGContextRef context = NSGraphicsContext.currentContext.CGContext;
    CGContextSaveGState(context);
    // Same page transform as the plan draw: paper coordinates, y up.
    CGContextTranslateCTM(context, NSMinX(pageFrame), NSMaxY(pageFrame));
    CGContextScaleCTM(context, 1, -1);
    CGContextSetTextMatrix(context, CGAffineTransformIdentity);
    for (SPDFMarkdownPageFragment* fragment in page.fragments) {
        if (fragment.blockIndex != blockIndex || !fragment.attributedRange.length ||
            NSMaxRange(fragment.attributedRange) > self.attributedString.length)
            continue;
        NSAttributedString* substring = [self.attributedString attributedSubstringFromRange:fragment.attributedRange];
        CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)substring);
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, NSMinX(printable) + fragment.xOffset,
                              paperHeight - NSMinY(printable) - fragment.pageYOffset - fragment.baselineOffset);
        CGContextScaleCTM(context, fragment.scale, fragment.scale);
        CGContextSetTextPosition(context, 0, 0);
        CTLineDraw(line, context);
        CGContextRestoreGState(context);
        CFRelease(line);
    }
    CGContextRestoreGState(context);
}

// The shared plan draw paints the page (paper fill, print-palette decorations,
// text). This screen pass then repaints the same decoration geometry with the
// dynamic SPDFMarkdownTheme colors: the opaque code-box fill replaces the print
// box and its print-palette code lines, which are redrawn appearance-correct on
// top, so the box stays beneath its text.
- (void)drawDecorationsForPageAtIndex:(NSUInteger)pageIndex pageFrame:(NSRect)pageFrame {
    NSArray<SPDFMarkdownPageDecoration*>* decorations = [self.plan decorationsForPageIndex:pageIndex];
    if (!decorations.count) return;
    SPDFMarkdownPage* page = self.plan.pages[pageIndex];
    NSRect printable = self.plan.configuration.printableRect;
    CGFloat contentX = NSMinX(pageFrame) + NSMinX(printable);
    CGFloat contentY = NSMinY(pageFrame) + NSMinY(printable);
    for (SPDFMarkdownPageDecoration* decoration in decorations) {
        NSRect rect = NSOffsetRect(decoration.rect, contentX, contentY);
        if (decoration.type == SPDFMarkdownPageDecorationTypeCodeBox) {
            // Half-pixel inset keeps the 1px stroke crisp at 1x and 2x.
            NSRect boxRect = NSInsetRect(rect, 0.5, 0.5);
            if (NSWidth(boxRect) <= 0 || NSHeight(boxRect) <= 0) continue;
            CGFloat radius = MIN(6.0, MIN(NSWidth(boxRect), NSHeight(boxRect)) / 2.0);
            NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:boxRect xRadius:radius yRadius:radius];
            [SPDFMarkdownTheme.codeBoxFillColor setFill];
            [path fill];
            [SPDFMarkdownTheme.codeBoxStrokeColor setStroke];
            path.lineWidth = 1.0;
            [path stroke];
            [self drawCodeTextForBlockIndex:decoration.blockIndex page:page pageFrame:pageFrame];
        } else {
            [SPDFMarkdownTheme.headingRuleColor setFill];
            NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);
        }
    }
}

- (void)drawCodeLanguageControlsOnPage:(SPDFMarkdownPage*)page pageFrame:(NSRect)pageFrame {
    for (SPDFMarkdownPageFragment* fragment in page.fragments) {
        if (fragment.itemIndex >= self.plan.items.count) continue;
        SPDFMarkdownPaginationItem* item = self.plan.items[fragment.itemIndex];
        if (item.kind != SPDFMarkdownBlockKindCode || fragment.isContinuation) continue;
        NSRect controlRect = [self codeLanguageControlRectForFragment:fragment pageFrame:pageFrame];
        NSRect boxRect = NSInsetRect(controlRect, 0.5, 0.5);
        NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:boxRect
                                                             xRadius:kSPDFMarkdownCodeControlCornerRadius
                                                             yRadius:kSPDFMarkdownCodeControlCornerRadius];
        [SPDFMarkdownTheme.codeControlFillColor setFill];
        [path fill];
        [SPDFMarkdownTheme.codeControlStrokeColor setStroke];
        path.lineWidth = 1.0;
        [path stroke];
        NSString* title = [self codeLanguageControlTitleForBlockIndex:fragment.blockIndex];
        NSDictionary* attributes = SPDFCodeControlTitleAttributes();
        NSSize titleSize = [title sizeWithAttributes:attributes];
        [title drawAtPoint:NSMakePoint(NSMinX(controlRect) + kSPDFMarkdownCodeControlHorizontalPadding,
                                       round(NSMidY(controlRect) - titleSize.height * 0.5))
            withAttributes:attributes];
    }
}

@end
