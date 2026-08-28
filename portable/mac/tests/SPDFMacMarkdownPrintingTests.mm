#import <AppKit/AppKit.h>
#import <PDFKit/PDFKit.h>

#import "../SPDFMacMarkdownPrinting.h"
#import "../markdown/SPDFMarkdown.h"

#include <assert.h>
#include <stdio.h>

// Rasterizes one page of a produced PDF at 1:1 (one pixel per point) so pixel
// probes address exact page-coordinate positions. yFromTop counts down from
// the paper's top edge, matching pagination-plan geometry.
static unsigned char* RasterizePage(NSData* data, size_t pageNumber, size_t* outWidth, size_t* outHeight) {
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGPDFDocumentRef document = provider ? CGPDFDocumentCreateWithProvider(provider) : NULL;
    CGPDFPageRef page = document ? CGPDFDocumentGetPage(document, pageNumber) : NULL;
    assert(page);
    CGRect mediaBox = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
    size_t width = (size_t)ceil(CGRectGetWidth(mediaBox));
    size_t height = (size_t)ceil(CGRectGetHeight(mediaBox));
    unsigned char* pixels = (unsigned char*)calloc(width * height, 4);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context =
        CGBitmapContextCreate(pixels, width, height, 8, width * 4, colorSpace, kCGImageAlphaPremultipliedLast);
    assert(context);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));
    CGContextDrawPDFPage(context, page);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    CGPDFDocumentRelease(document);
    CGDataProviderRelease(provider);
    *outWidth = width;
    *outHeight = height;
    return pixels;
}

static const unsigned char* PixelAt(const unsigned char* pixels, size_t width, size_t height, CGFloat x,
                                    CGFloat yFromTop) {
    size_t column = (size_t)MIN((CGFloat)width - 1, MAX((CGFloat)0, round(x)));
    size_t row = (size_t)MIN((CGFloat)height - 1, MAX((CGFloat)0, round(yFromTop)));
    return pixels + (row * width + column) * 4;
}

int main(void) {
    @autoreleasepool {
        (void)NSApplication.sharedApplication;
        NSString* path = [NSTemporaryDirectory()
            stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"md"]];
        NSString* markdown = @"# Release Notes\nZanzibar anchors the geometry probe of this exported page.\n\n"
                             @"```\nprint_safe();\n```\n\n"
                             @"## Details\nA second section verifies heading pagination stays selectable.\n";
        assert([markdown writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);

        // Build the exact rendition + plan the on-screen session uses: the
        // user's current font scale and the reserved language-control band.
        SPDFMarkdownRenderOptions* options = [SPDFMarkdownRenderOptions defaultOptions];
        options.fontScale = 1.5;
        SPDFMarkdownDocument* document = [SPDFMarkdownDocument documentWithURL:[NSURL fileURLWithPath:path]
                                                                       options:options
                                                                         error:nil];
        assert(document);
        SPDFMarkdownRenderedDocument* rendered = document.renderedDocument;
        SPDFMarkdownPaginator* paginator = [SPDFMarkdownPaginator new];
        SPDFMarkdownPageConfiguration* configuration = [SPDFMarkdownPageConfiguration A4PortraitConfiguration];
        configuration.includesCodeLanguageControlSpacing = YES;
        NSArray* items = [paginator measureRenderedDocument:rendered
                                             containerWidth:NSWidth(configuration.printableRect)];
        SPDFMarkdownPaginationPlan* plan = [paginator paginateItems:items configuration:configuration];
        assert(plan.pages.count >= 1);

        // The export plan is the screen plan: A4 geometry with the language
        // control band still reserved (the pill itself is screen chrome).
        assert(plan.configuration.includesCodeLanguageControlSpacing);
        SPDFMarkdownPaginationItem* codeItem = nil;
        for (SPDFMarkdownPaginationItem* item in plan.items)
            if (item.kind == SPDFMarkdownBlockKindCode) codeItem = item;
        assert(codeItem != nil && codeItem.lines.firstObject.attributedRange.length == 0 &&
               fabs(codeItem.lines.firstObject.height - 48.0) < 0.001);

        // Print never repaginates: the view keeps the given plan, and a
        // differing printer paper only scales the finished page, centered.
        NSPrintInfo* letter = [NSPrintInfo.sharedPrintInfo copy];
        letter.paperSize = NSMakeSize(612, 792);
        letter.leftMargin = 30;
        letter.rightMargin = 30;
        letter.topMargin = 30;
        letter.bottomMargin = 30;
        letter.scalingFactor = 1.0;
        NSPrintOperation* operation = [SPDFMacMarkdownPrintAdapter printOperationForPaginationPlan:plan
                                                                                  attributedString:rendered.attributedString
                                                                                         printInfo:letter];
        assert(operation.printPanel.options & NSPrintPanelShowsPreview);
        assert(operation.printPanel.options & NSPrintPanelShowsPaperSize);
        SPDFMacMarkdownPrintView* view = (SPDFMacMarkdownPrintView*)operation.view;
        assert([view isKindOfClass:SPDFMacMarkdownPrintView.class]);
        assert(view.paginationPlan == plan);
        NSRange range = NSMakeRange(0, 0);
        assert([view knowsPageRange:&range]);
        assert(range.location == 1 && range.length == plan.pages.count);
        NSRect pageRect = [view rectForPage:1];
        assert(NSEqualSizes(pageRect.size, plan.configuration.paperSize));
        NSPrintInfo* operationInfo = operation.printInfo;
        assert(operationInfo.horizontallyCentered && operationInfo.verticallyCentered);
        assert(operationInfo.scalingFactor > 0.5 && operationInfo.scalingFactor <= 1.0001);
        // Letter minus 30pt margins cannot hold a full A4 page unscaled.
        assert(operationInfo.scalingFactor < 0.999);

        // Save-as-PDF draws the plan's own pages; no NSPrintInfo involved.
        NSString* output = [NSTemporaryDirectory()
            stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"pdf"]];
        NSError* error = nil;
        assert([SPDFMacMarkdownPrintAdapter writePaginationPlan:plan
                                               attributedString:rendered.attributedString
                                                          toURL:[NSURL fileURLWithPath:output]
                                                          error:&error]);
        assert(!error);
        NSData* PDFData = [NSData dataWithContentsOfFile:output];
        PDFDocument* PDF = [[PDFDocument alloc] initWithData:PDFData];
        assert(PDF.pageCount == plan.pages.count);
        NSRect mediaBox = [[PDF pageAtIndex:0] boundsForBox:kPDFDisplayBoxMediaBox];
        assert(fabs(NSWidth(mediaBox) - plan.configuration.paperSize.width) < 0.5 &&
               fabs(NSHeight(mediaBox) - plan.configuration.paperSize.height) < 0.5);
        NSMutableString* text = [NSMutableString string];
        for (NSUInteger index = 0; index < PDF.pageCount; ++index)
            [text appendString:[PDF pageAtIndex:index].string ?: @""];
        assert([text containsString:@"Release Notes"]);
        assert([text containsString:@"Zanzibar"] && [text containsString:@"selectable"]);

        // Geometry probe: the probe word lands exactly where the screen plan
        // placed its line fragment (same margins, same scaled fonts).
        CGFloat printableLeft = NSMinX(plan.configuration.printableRect);
        CGFloat printableTopY = plan.configuration.paperSize.height - plan.configuration.topContentInset;
        NSUInteger probeLocation = [rendered.attributedString.string rangeOfString:@"Zanzibar"].location;
        assert(probeLocation != NSNotFound);
        SPDFMarkdownPageFragment* probeFragment = nil;
        NSUInteger probePageIndex = 0;
        for (SPDFMarkdownPage* page in plan.pages) {
            for (SPDFMarkdownPageFragment* fragment in page.fragments) {
                if (fragment.attributedRange.length && NSLocationInRange(probeLocation, fragment.attributedRange)) {
                    probeFragment = fragment;
                    probePageIndex = page.pageIndex;
                    break;
                }
            }
            if (probeFragment) break;
        }
        assert(probeFragment != nil);
        PDFSelection* found = [PDF findString:@"Zanzibar" withOptions:0].firstObject;
        assert(found != nil);
        PDFPage* foundPage = found.pages.firstObject;
        assert([PDF indexForPage:foundPage] == probePageIndex);
        NSRect foundBounds = [found boundsForPage:foundPage];
        CGFloat fragmentTopY = printableTopY - probeFragment.pageYOffset;
        CGFloat baselineY = fragmentTopY - probeFragment.baselineOffset;
        assert(fabs(NSMinX(foundBounds) - (printableLeft + probeFragment.xOffset)) < 3.0);
        assert(NSMaxY(foundBounds) <= fragmentTopY + 2.0);
        assert(NSMinY(foundBounds) >= fragmentTopY - probeFragment.height - 2.0);
        assert(NSMinY(foundBounds) <= baselineY + 1.0 && NSMaxY(foundBounds) > baselineY);

        // Raster probe: the code box paints its concrete fill exactly at the
        // decoration rect the screen canvas uses, and the margins stay paper.
        SPDFMarkdownPageDecoration* codeBox = nil;
        NSUInteger codePageIndex = 0;
        for (NSUInteger pageIndex = 0; pageIndex < plan.pages.count && !codeBox; ++pageIndex) {
            for (SPDFMarkdownPageDecoration* decoration in [plan decorationsForPageIndex:pageIndex]) {
                if (decoration.type == SPDFMarkdownPageDecorationTypeCodeBox) {
                    codeBox = decoration;
                    codePageIndex = pageIndex;
                    break;
                }
            }
        }
        assert(codeBox != nil);
        size_t rasterWidth = 0;
        size_t rasterHeight = 0;
        unsigned char* pixels = RasterizePage(PDFData, codePageIndex + 1, &rasterWidth, &rasterHeight);
        CGFloat topInset = plan.configuration.topContentInset;
        // Sample inside the box (right of the short code line) for the fill.
        const unsigned char* fill = PixelAt(pixels, rasterWidth, rasterHeight,
                                            printableLeft + NSMaxX(codeBox.rect) - 20.0,
                                            topInset + NSMidY(codeBox.rect));
        assert(abs((int)fill[0] - 246) <= 5 && abs((int)fill[1] - 248) <= 5 && abs((int)fill[2] - 250) <= 5);
        // Just above the box sits the unpainted outer margin (pure paper).
        const unsigned char* aboveBox = PixelAt(pixels, rasterWidth, rasterHeight,
                                                printableLeft + NSMidX(codeBox.rect),
                                                topInset + NSMinY(codeBox.rect) - 7.0);
        assert(aboveBox[0] >= 250 && aboveBox[1] >= 250 && aboveBox[2] >= 250);
        // The top margin above the printable area stays untouched paper.
        const unsigned char* margin =
            PixelAt(pixels, rasterWidth, rasterHeight, plan.configuration.paperSize.width * 0.5, topInset * 0.5);
        assert(margin[0] >= 250 && margin[1] >= 250 && margin[2] >= 250);
        free(pixels);

        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        [NSFileManager.defaultManager removeItemAtPath:output error:nil];
        puts("SPDFMacMarkdownPrintingTests passed");
    }
    return 0;
}
