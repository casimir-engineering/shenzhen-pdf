#import "SPDFMacMarkdownPageCanvasPrivate.h"

#import <CoreText/CoreText.h>

#import "SPDFMacMarkdownView.h"
#import "markdown/SPDFMarkdown.h"

// GitHub-style code-language control anchored inside the code box header band.
static const CGFloat kSPDFMarkdownCodeControlHeight = 20.0;
static const CGFloat kSPDFMarkdownCodeControlCornerRadius = 5.0;
static const CGFloat kSPDFMarkdownCodeControlRightInset = 10.0;
static const CGFloat kSPDFMarkdownCodeControlHorizontalPadding = 9.0;
static const CGFloat kSPDFMarkdownCodeControlHitSlop = 7.0;

static NSDictionary<NSAttributedStringKey, id>* SPDFCodeControlTitleAttributes(SPDFMarkdownTheme* theme) {
    return @{
        NSFontAttributeName : [NSFont systemFontOfSize:11 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName : theme.codeControlTextColor,
    };
}

@implementation SPDFMacMarkdownPageCanvas (Decorations)

// The plan's theme variant is the single source of the page chrome palette,
// so canvas chrome always matches the page content drawn from the same plan.
- (SPDFMarkdownTheme*)pageTheme {
    return [SPDFMarkdownTheme themeForVariant:self.plan.configuration.themeVariant];
}

// Paper presentation: light paper keeps the classic white sheet with a soft
// drop shadow; dark paper is the theme's #1E1E1E sheet separated from the
// canvas gutter by a subtle 1px #333333 border instead of a shadow (a dark
// shadow reads as mud on dark gutters). Split into fill/shadow decisions so a
// headless test can probe the choice without rasterizing.
- (NSColor*)paperFillColor {
    return self.pageTheme.paperColor;
}

- (BOOL)drawsPaperShadow {
    return self.pageTheme.drawsPaperShadow;
}

// The gutter behind the sheets. Dark takes the theme's #121212 so the #1E1E1E
// paper edge always reads; light keeps windowBackgroundColor exactly as before.
- (NSColor*)viewportBackgroundColor {
    return self.pageTheme.viewportBackgroundColor ?: NSColor.windowBackgroundColor;
}

- (void)drawPaperBackgroundInFrame:(NSRect)pageFrame {
    [NSGraphicsContext saveGraphicsState];
    if (self.drawsPaperShadow) {
        NSShadow* shadow = [NSShadow new];
        shadow.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.22];
        shadow.shadowBlurRadius = 4.0;
        shadow.shadowOffset = NSMakeSize(0, -1);
        [shadow set];
    }
    [self.paperFillColor setFill];
    NSRectFill(pageFrame);
    [NSGraphicsContext restoreGraphicsState];
}

// Drawn after the page content so the hairline stays crisp at the page edge.
- (void)drawPaperBorderInFrame:(NSRect)pageFrame {
    if (self.drawsPaperShadow) return;
    [self.pageTheme.paperBorderColor setStroke];
    NSBezierPath* border = [NSBezierPath bezierPathWithRect:NSInsetRect(pageFrame, 0.5, 0.5)];
    border.lineWidth = 1.0;
    [border stroke];
}

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
    CGFloat width = ceil([title sizeWithAttributes:SPDFCodeControlTitleAttributes(self.pageTheme)].width) +
                    kSPDFMarkdownCodeControlHorizontalPadding * 2.0;
    width =
        MIN(width, MAX(kSPDFMarkdownCodeControlHeight, NSWidth(printable) - kSPDFMarkdownCodeControlRightInset * 2.0));
    // The leading band starts with the unpainted outer margin above the box;
    // the control centers in the in-box header portion below it.
    CGFloat outerMargin = MIN(SPDFMarkdownCodeBoxOuterMargin * fragment.scale, fragment.height);
    CGFloat bandTop =
        NSMinY(pageFrame) + self.plan.configuration.topContentInset + fragment.pageYOffset + outerMargin;
    CGFloat y = round(bandTop + (fragment.height - outerMargin - kSPDFMarkdownCodeControlHeight) * 0.5);
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

// PDF parity: links show the pointing-hand cursor on hover. Returns one rect
// per link run portion inside each of the page's line fragments, using the
// same CTLine offset mapping the highlight drawing uses; the tracking-area
// cursor path (SPDFMacMarkdownPageCanvas+Cursor.mm) hit-tests these.
- (NSArray<NSValue*>*)linkRectsForPage:(SPDFMarkdownPage*)page pageFrame:(NSRect)pageFrame {
    NSMutableArray<NSValue*>* linkRects = [NSMutableArray array];
    NSRect printable = self.plan.configuration.printableRect;
    NSAttributedString* attributedString = self.attributedString;
    for (SPDFMarkdownPageFragment* fragment in page.fragments) {
        if (!fragment.attributedRange.length || NSMaxRange(fragment.attributedRange) > attributedString.length)
            continue;
        CTLineRef line = NULL;
        NSUInteger cursor = fragment.attributedRange.location;
        while (cursor < NSMaxRange(fragment.attributedRange)) {
            NSRange effective = NSMakeRange(0, 0);
            NSDictionary* attributes = [attributedString attributesAtIndex:cursor
                                                      longestEffectiveRange:&effective
                                                                    inRange:fragment.attributedRange];
            if (attributes[SPDFMacMarkdownDestinationAttribute] ||
                attributes[SPDFMacMarkdownWikiDestinationAttribute]) {
                if (!line) {
                    NSAttributedString* lineString =
                        [attributedString attributedSubstringFromRange:fragment.attributedRange];
                    line = SPDFMarkdownCreateFragmentLine(lineString);
                }
                CFIndex start = (CFIndex)(effective.location - fragment.attributedRange.location);
                CFIndex end = (CFIndex)(NSMaxRange(effective) - fragment.attributedRange.location);
                CGFloat x0 = CTLineGetOffsetForStringIndex(line, start, NULL) * fragment.scale;
                CGFloat x1 = CTLineGetOffsetForStringIndex(line, end, NULL) * fragment.scale;
                NSRect linkRect =
                    NSMakeRect(NSMinX(pageFrame) + NSMinX(printable) + fragment.xOffset + MIN(x0, x1),
                               NSMinY(pageFrame) + self.plan.configuration.topContentInset + fragment.pageYOffset,
                               fabs(x1 - x0), fragment.height);
                if (!NSIsEmptyRect(linkRect)) [linkRects addObject:[NSValue valueWithRect:linkRect]];
            }
            cursor = NSMaxRange(effective);
        }
        if (line) CFRelease(line);
    }
    return linkRects;
}

- (void)drawCodeLanguageControlsOnPage:(SPDFMarkdownPage*)page pageFrame:(NSRect)pageFrame {
    SPDFMarkdownTheme* theme = self.pageTheme;
    for (SPDFMarkdownPageFragment* fragment in page.fragments) {
        if (fragment.itemIndex >= self.plan.items.count) continue;
        SPDFMarkdownPaginationItem* item = self.plan.items[fragment.itemIndex];
        if (item.kind != SPDFMarkdownBlockKindCode || fragment.isContinuation) continue;
        NSRect controlRect = [self codeLanguageControlRectForFragment:fragment pageFrame:pageFrame];
        NSRect boxRect = NSInsetRect(controlRect, 0.5, 0.5);
        NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:boxRect
                                                             xRadius:kSPDFMarkdownCodeControlCornerRadius
                                                             yRadius:kSPDFMarkdownCodeControlCornerRadius];
        [theme.codeControlFillColor setFill];
        [path fill];
        [theme.codeControlStrokeColor setStroke];
        path.lineWidth = 1.0;
        [path stroke];
        NSString* title = [self codeLanguageControlTitleForBlockIndex:fragment.blockIndex];
        NSDictionary* attributes = SPDFCodeControlTitleAttributes(theme);
        NSSize titleSize = [title sizeWithAttributes:attributes];
        [title drawAtPoint:NSMakePoint(NSMinX(controlRect) + kSPDFMarkdownCodeControlHorizontalPadding,
                                       round(NSMidY(controlRect) - titleSize.height * 0.5))
            withAttributes:attributes];
    }
}

@end
