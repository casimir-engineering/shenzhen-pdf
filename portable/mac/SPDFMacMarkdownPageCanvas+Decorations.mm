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
        NSForegroundColorAttributeName : SPDFMarkdownTheme.codeControlTextColor,
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
