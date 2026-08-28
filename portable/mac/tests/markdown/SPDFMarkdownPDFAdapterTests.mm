#import "SPDFMarkdownTestSupport.h"

#import <PDFKit/PDFKit.h>

#import "../../markdown/SPDFMarkdownDocument.h"

static NSData* SPDFCreatePDF(SPDFMarkdownPaginationPlan* plan, NSAttributedString* string) {
    NSMutableData* data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect mediaBox = CGRectMake(0, 0, plan.configuration.paperSize.width, plan.configuration.paperSize.height);
    CGContextRef context = CGPDFContextCreate(consumer, &mediaBox, NULL);
    for (NSUInteger page = 0; page < plan.pages.count; ++page) {
        CGPDFContextBeginPage(context, NULL);
        [plan drawPageAtIndex:page attributedString:string inContext:context];
        CGPDFContextEndPage(context);
    }
    CGPDFContextClose(context);
    CGContextRelease(context);
    CGDataConsumerRelease(consumer);
    return data;
}

static NSURL* SPDFCreateImageDocument(NSString** temporaryRoot) {
    NSString* root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES
                                             attributes:nil error:nil];
    NSBitmapImageRep* bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                      pixelsWide:96 pixelsHigh:480 bitsPerSample:8
                                                                    samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                    colorSpaceName:NSCalibratedRGBColorSpace
                                                                       bytesPerRow:0 bitsPerPixel:0];
    for (NSInteger y = 0; y < bitmap.pixelsHigh; ++y) {
        unsigned char* row = bitmap.bitmapData + y * bitmap.bytesPerRow;
        for (NSInteger x = 0; x < bitmap.pixelsWide; ++x) {
            row[x * 4 + 0] = 255;
            row[x * 4 + 1] = 0;
            row[x * 4 + 2] = 255;
            row[x * 4 + 3] = 255;
        }
    }
    NSData* PNG = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [PNG writeToFile:[root stringByAppendingPathComponent:@"local.png"] atomically:YES];
    NSString* documentPath = [root stringByAppendingPathComponent:@"image.md"];
    [@"# Exported image\n\n![Magenta proof](local.png)\n\nAfter image\n"
        writeToFile:documentPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    *temporaryRoot = root;
    return [NSURL fileURLWithPath:documentPath];
}

static CGRect SPDFPDFMagentaBounds(NSData* data) {
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGPDFDocumentRef document = provider ? CGPDFDocumentCreateWithProvider(provider) : NULL;
    size_t width = 596;
    size_t height = 842;
    unsigned char* pixels = (unsigned char*)calloc(width * height, 4);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = pixels ? CGBitmapContextCreate(pixels, width, height, 8, width * 4, colorSpace,
                                                           kCGImageAlphaPremultipliedLast) : NULL;
    NSInteger minimumX = (NSInteger)width;
    NSInteger minimumY = (NSInteger)height;
    NSInteger maximumX = -1;
    NSInteger maximumY = -1;
    size_t pageCount = document ? CGPDFDocumentGetNumberOfPages(document) : 0;
    for (size_t pageIndex = 1; context && pageIndex <= pageCount && maximumX < 0; ++pageIndex) {
        CGPDFPageRef page = CGPDFDocumentGetPage(document, pageIndex);
        CGRect mediaBox = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
        CGContextSaveGState(context);
        CGContextSetRGBFillColor(context, 1, 1, 1, 1);
        CGContextFillRect(context, CGRectMake(0, 0, width, height));
        CGFloat scale = MIN(width / CGRectGetWidth(mediaBox), height / CGRectGetHeight(mediaBox));
        CGContextScaleCTM(context, scale, scale);
        CGContextDrawPDFPage(context, page);
        CGContextRestoreGState(context);
        for (size_t y = 0; y < height; ++y) {
            for (size_t x = 0; x < width; ++x) {
                unsigned char* pixel = pixels + (y * width + x) * 4;
                if (pixel[0] > 220 && pixel[1] < 120 && pixel[2] > 220) {
                    minimumX = MIN(minimumX, (NSInteger)x);
                    minimumY = MIN(minimumY, (NSInteger)y);
                    maximumX = MAX(maximumX, (NSInteger)x);
                    maximumY = MAX(maximumY, (NSInteger)y);
                }
            }
        }
    }
    if (context) CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    free(pixels);
    if (document) CGPDFDocumentRelease(document);
    if (provider) CGDataProviderRelease(provider);
    if (maximumX < 0) return CGRectNull;
    return CGRectMake(minimumX, minimumY, maximumX - minimumX + 1, maximumY - minimumY + 1);
}

static BOOL SPDFPDFContainsMagentaImage(NSData* data) {
    return !CGRectIsNull(SPDFPDFMagentaBounds(data));
}

// Counts raster pixels close to the concrete #F6F8FA code-box fill on page 1.
static NSUInteger SPDFPDFCodeBoxFillPixelCount(NSData* data) {
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGPDFDocumentRef document = provider ? CGPDFDocumentCreateWithProvider(provider) : NULL;
    CGPDFPageRef page = document ? CGPDFDocumentGetPage(document, 1) : NULL;
    size_t width = 596;
    size_t height = 842;
    unsigned char* pixels = (unsigned char*)calloc(width * height, 4);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = pixels ? CGBitmapContextCreate(pixels, width, height, 8, width * 4, colorSpace,
                                                           kCGImageAlphaPremultipliedLast) : NULL;
    if (context && page) {
        CGContextSetRGBFillColor(context, 1, 1, 1, 1);
        CGContextFillRect(context, CGRectMake(0, 0, width, height));
        CGContextDrawPDFPage(context, page);
    }
    NSUInteger filled = 0;
    if (context && page) {
        for (size_t index = 0; index < width * height; ++index) {
            unsigned char* pixel = pixels + index * 4;
            if (abs((int)pixel[0] - 246) <= 6 && abs((int)pixel[1] - 248) <= 6 && abs((int)pixel[2] - 250) <= 5)
                ++filled;
        }
    }
    if (context) CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    free(pixels);
    if (document) CGPDFDocumentRelease(document);
    if (provider) CGDataProviderRelease(provider);
    return filled;
}

static NSUInteger SPDFPDFDarkPixelCount(NSData* data) {
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGPDFDocumentRef document = provider ? CGPDFDocumentCreateWithProvider(provider) : NULL;
    CGPDFPageRef page = document ? CGPDFDocumentGetPage(document, 1) : NULL;
    size_t width = 596;
    size_t height = 842;
    unsigned char* pixels = (unsigned char*)calloc(width * height, 4);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = pixels ? CGBitmapContextCreate(pixels, width, height, 8, width * 4, colorSpace,
                                                           kCGImageAlphaPremultipliedLast) : NULL;
    if (context && page) {
        CGContextSetRGBFillColor(context, 1, 1, 1, 1);
        CGContextFillRect(context, CGRectMake(0, 0, width, height));
        CGContextDrawPDFPage(context, page);
    }
    NSUInteger dark = 0;
    if (context && page) {
        for (size_t index = 0; index < width * height; ++index) {
            unsigned char* pixel = pixels + index * 4;
            if (pixel[0] < 100 && pixel[1] < 100 && pixel[2] < 100) ++dark;
        }
    }
    if (context) CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    free(pixels);
    if (document) CGPDFDocumentRelease(document);
    if (provider) CGDataProviderRelease(provider);
    return dark;
}

int main(void) {
    @autoreleasepool {
        NSError* error = nil;
        SPDFMarkdownDocument* document = [SPDFMarkdownDocument documentWithURL:SPDFFixtureURL(@"commonmark-gfm.md")
                                                                        options:nil error:&error];
        SPDFMarkdownPageConfiguration* configuration = SPDFMarkdownPageConfiguration.A4PortraitConfiguration;
        SPDFMarkdownPaginationPlan* plan = [document paginationPlanForConfiguration:configuration];
        NSData* data = SPDFCreatePDF(plan, document.renderedDocument.attributedString);
        PDFDocument* PDF = [[PDFDocument alloc] initWithData:data];
        SPDFExpect(PDF.pageCount == plan.pages.count && PDF.pageCount > 0,
                   @"drawable plan produces the planned page count");
        PDFPage* first = [PDF pageAtIndex:0];
        NSRect mediaBox = [first boundsForBox:kPDFDisplayBoxMediaBox];
        SPDFExpect(fabs(NSWidth(mediaBox) - 595.2756) < 0.1 && fabs(NSHeight(mediaBox) - 841.8898) < 0.1,
                   @"PDF MediaBox is A4 portrait");
        NSString* extracted = PDF.string ?: @"";
        SPDFExpect([extracted containsString:@"Shenzhen PDF Markdown"],
                   @"PDF text remains vector/selectable and extractable");
        SPDFExpect([extracted containsString:@"Finished task"],
                   @"structural content remains selectable in the PDF adapter");
        SPDFExpect(SPDFPDFCodeBoxFillPixelCount(data) > 2000,
                   @"exported fenced code paints one continuous filled box behind the code lines");
        BOOL plannedCodeBox = NO;
        for (NSUInteger pageIndex = 0; pageIndex < plan.pages.count; ++pageIndex)
            for (SPDFMarkdownPageDecoration* decoration in [plan decorationsForPageIndex:pageIndex])
                if (decoration.type == SPDFMarkdownPageDecorationTypeCodeBox &&
                    fabs(NSWidth(decoration.rect) - NSWidth(configuration.printableRect)) < 0.01)
                    plannedCodeBox = YES;
        SPDFExpect(plannedCodeBox, @"the export plan exposes full-width code-box decoration geometry");
        __block NSData* darkAppearancePDF = nil;
        [[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] performAsCurrentDrawingAppearance:^{
            darkAppearancePDF = SPDFCreatePDF(plan, document.renderedDocument.attributedString);
        }];
        PDFDocument* darkPDF = [[PDFDocument alloc] initWithData:darkAppearancePDF];
        SPDFExpect([(darkPDF.string ?: @"") containsString:@"Shenzhen PDF Markdown"] &&
                       SPDFPDFDarkPixelCount(darkAppearancePDF) > 500,
                   @"dark appearance exports selectable dark text through a concrete print palette");

        NSString* temporaryRoot = nil;
        SPDFMarkdownDocument* imageDocument = [SPDFMarkdownDocument documentWithURL:SPDFCreateImageDocument(&temporaryRoot)
                                                                             options:nil error:&error];
        SPDFMarkdownPaginationPlan* imagePlan =
            [imageDocument paginationPlanForConfiguration:SPDFMarkdownPageConfiguration.A4PortraitConfiguration];
        NSData* imagePDF = SPDFCreatePDF(imagePlan, imageDocument.renderedDocument.attributedString);
        PDFDocument* imagePDFDocument = [[PDFDocument alloc] initWithData:imagePDF];
        SPDFExpect([(imagePDFDocument.string ?: @"") containsString:@"Magenta proof"],
                   @"local-image captions remain selectable in PDF output");
        SPDFExpect(SPDFPDFContainsMagentaImage(imagePDF),
                   @"a real local image attachment is painted into the exported PDF");
        __block NSUInteger attachmentLocation = NSNotFound;
        [imageDocument.renderedDocument.attributedString
            enumerateAttribute:NSAttachmentAttributeName
                       inRange:NSMakeRange(0, imageDocument.renderedDocument.attributedString.length)
                       options:0
                    usingBlock:^(id attachment, NSRange range, BOOL* stop) {
            if (attachment) {
                attachmentLocation = range.location;
                *stop = YES;
            }
        }];
        SPDFMarkdownPageFragment* imageFragment = nil;
        for (SPDFMarkdownPageFragment* fragment in imagePlan.pages.firstObject.fragments) {
            if (attachmentLocation != NSNotFound && NSLocationInRange(attachmentLocation, fragment.attributedRange)) {
                imageFragment = fragment;
                break;
            }
        }
        CGRect magentaBounds = SPDFPDFMagentaBounds(imagePDF);
        CGFloat fragmentBottom = configuration.paperSize.height - NSMinY(configuration.printableRect) -
                                 imageFragment.pageYOffset - imageFragment.height;
        CGFloat fragmentTop = fragmentBottom + imageFragment.height;
        CGFloat imageBottom = configuration.paperSize.height - CGRectGetMaxY(magentaBounds);
        CGFloat imageTop = configuration.paperSize.height - CGRectGetMinY(magentaBounds);
        SPDFExpect(imageFragment && !CGRectIsNull(magentaBounds) &&
                       imageBottom >= fragmentBottom - 2 && imageTop <= fragmentTop + 2,
                   @"PDF attachments remain inside their exact TextKit line fragment without covering adjacent text");

        SPDFMarkdownPageConfiguration* smallPaper =
            [SPDFMarkdownPageConfiguration configurationForPaperSize:NSMakeSize(120, 120)
                                                        printableRect:NSMakeRect(20, 20, 80, 80)];
        SPDFMarkdownPaginationPlan* smallPlan = [imageDocument paginationPlanForConfiguration:smallPaper];
        BOOL foundScaledFragment = NO;
        for (SPDFMarkdownPage* page in smallPlan.pages)
            for (SPDFMarkdownPageFragment* fragment in page.fragments)
                if (fragment.scale < 0.999) foundScaledFragment = YES;
        NSData* smallPDF = SPDFCreatePDF(smallPlan, imageDocument.renderedDocument.attributedString);
        SPDFExpect(foundScaledFragment && SPDFPDFContainsMagentaImage(smallPDF),
                   @"over-tall local images are scaled into small printable pages and remain visible");
        [NSFileManager.defaultManager removeItemAtPath:temporaryRoot error:nil];
    }
    return SPDFFinishTests(@"SPDFMarkdownPDFAdapterTests");
}
