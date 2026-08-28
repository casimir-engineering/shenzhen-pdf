#import "SPDFMarkdownPaginator.h"

#import <CoreText/CoreText.h>

#import "SPDFMarkdownTableDecorations.h"

// Concrete-palette drawing of a planned page into any Core Graphics context
// (screen page canvas, print, PDF export, copy-page). Kept beside the
// paginator: it consumes exactly the fragments and decoration geometry the
// plan produced, so every consumer stays page-for-page identical.

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

static void SPDFSetContextColor(CGContextRef context, NSColor* color, BOOL stroke) {
    NSColor* sRGB = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: NSColor.blackColor;
    if (stroke) {
        CGContextSetRGBStrokeColor(context, sRGB.redComponent, sRGB.greenComponent, sRGB.blueComponent,
                                   sRGB.alphaComponent);
    } else {
        CGContextSetRGBFillColor(context, sRGB.redComponent, sRGB.greenComponent, sRGB.blueComponent,
                                 sRGB.alphaComponent);
    }
}

@implementation SPDFMarkdownPaginationPlan (SPDFDrawing)

// Print always paints the concrete light palette: rounded #F6F8FA/#D0D7DE code
// boxes and #D1D9E0 heading/thematic-break rules, drawn beneath the planned
// text lines.
- (void)spdf_drawDecorationsForPageIndex:(NSUInteger)pageIndex inContext:(CGContextRef)context {
    CGFloat printableLeft = NSMinX(self.configuration.printableRect);
    CGFloat printableTop = self.configuration.paperSize.height - self.configuration.topContentInset;
    for (SPDFMarkdownPageDecoration* decoration in [self decorationsForPageIndex:pageIndex]) {
        CGRect rect = CGRectMake(printableLeft + NSMinX(decoration.rect), printableTop - NSMaxY(decoration.rect),
                                 NSWidth(decoration.rect), NSHeight(decoration.rect));
        if (decoration.type == SPDFMarkdownPageDecorationTypeCodeBox) {
            CGRect boxRect = CGRectInset(rect, 0.5, 0.5);
            if (boxRect.size.width <= 0 || boxRect.size.height <= 0) continue;
            CGFloat radius = MIN(6, MIN(boxRect.size.width, boxRect.size.height) / 2);
            CGPathRef path = CGPathCreateWithRoundedRect(boxRect, radius, radius, NULL);
            SPDFSetContextColor(context, SPDFMarkdownTheme.printCodeBoxFillColor, NO);
            CGContextAddPath(context, path);
            CGContextFillPath(context);
            SPDFSetContextColor(context, SPDFMarkdownTheme.printCodeBoxStrokeColor, YES);
            CGContextSetLineWidth(context, 1);
            CGContextAddPath(context, path);
            CGContextStrokePath(context);
            CGPathRelease(path);
        } else if (decoration.type == SPDFMarkdownPageDecorationTypeTableHeaderBand ||
                   decoration.type == SPDFMarkdownPageDecorationTypeTableStripe ||
                   decoration.type == SPDFMarkdownPageDecorationTypeTableGridLine) {
            SPDFMarkdownDrawTableDecoration(context, decoration.type, rect);
        } else {
            NSColor* ruleColor = decoration.type == SPDFMarkdownPageDecorationTypeThematicBreakRule
                                     ? SPDFMarkdownTheme.thematicBreakRuleColor
                                     : SPDFMarkdownTheme.printHeadingRuleColor;
            SPDFSetContextColor(context, ruleColor, NO);
            CGContextFillRect(context, rect);
        }
    }
}

- (BOOL)drawPageAtIndex:(NSUInteger)pageIndex
       attributedString:(NSAttributedString*)attributedString
              inContext:(CGContextRef)context {
    if (pageIndex >= self.pages.count || !context) return NO;
    SPDFMarkdownPage* page = self.pages[pageIndex];
    CGFloat paperHeight = self.configuration.paperSize.height;
    CGFloat printableTop = paperHeight - self.configuration.topContentInset;
    CGContextSaveGState(context);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, self.configuration.paperSize.width, paperHeight));
    [self spdf_drawDecorationsForPageIndex:pageIndex inContext:context];
    CGContextSetTextMatrix(context, CGAffineTransformIdentity);
    for (SPDFMarkdownPageFragment* fragment in page.fragments) {
        if (NSMaxRange(fragment.attributedRange) > attributedString.length) continue;
        NSAttributedString* substring =
            SPDFPrintableLine([attributedString attributedSubstringFromRange:fragment.attributedRange]);
        CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)substring);
        CGFloat x = NSMinX(self.configuration.printableRect) + fragment.xOffset;
        CGFloat y = printableTop - fragment.pageYOffset - fragment.baselineOffset;
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
