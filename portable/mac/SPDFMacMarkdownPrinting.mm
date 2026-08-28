#import "SPDFMacMarkdownPrinting.h"

#import <CoreGraphics/CoreGraphics.h>

#import "markdown/SPDFMarkdown.h"

@interface SPDFMacMarkdownPrintView ()
- (void)fitPlanPaperToPrintInfo:(NSPrintInfo*)info;
@end

@implementation SPDFMacMarkdownPrintView

- (instancetype)initWithPaginationPlan:(SPDFMarkdownPaginationPlan*)plan
                      attributedString:(NSAttributedString*)attributedString {
    NSSize paper = plan.configuration.paperSize;
    NSUInteger pageCount = MAX((NSUInteger)1, plan.pages.count);
    self = [super initWithFrame:NSMakeRect(0, 0, MAX(1.0, paper.width), MAX(1.0, paper.height) * pageCount)];
    if (self) {
        _paginationPlan = plan;
        _attributedString = [attributedString copy];
    }
    return self;
}

- (BOOL)isFlipped { return NO; }

// The plan's paper is authoritative; a differing printer paper only scales
// the finished page (centered), it never re-flows or re-margins the content.
- (void)fitPlanPaperToPrintInfo:(NSPrintInfo*)info {
    NSSize paper = _paginationPlan.configuration.paperSize;
    if (!info || paper.width <= 0 || paper.height <= 0) return;
    CGFloat savedScaling = info.scalingFactor;
    info.scalingFactor = 1.0;
    NSRect imageable = info.imageablePageBounds;
    info.scalingFactor = savedScaling;
    if (NSWidth(imageable) < 1 || NSHeight(imageable) < 1) return;
    CGFloat scale = MIN(NSWidth(imageable) / paper.width, NSHeight(imageable) / paper.height);
    if (!isfinite(scale) || scale <= 0) return;
    info.scalingFactor = MIN(1.0, scale);
    info.horizontallyCentered = YES;
    info.verticallyCentered = YES;
}

- (BOOL)knowsPageRange:(NSRangePointer)range {
    [self fitPlanPaperToPrintInfo:NSPrintOperation.currentOperation.printInfo];
    range->location = 1;
    range->length = MAX((NSUInteger)1, _paginationPlan.pages.count);
    return YES;
}

- (NSRect)rectForPage:(NSInteger)page {
    NSSize paper = _paginationPlan.configuration.paperSize;
    return NSMakeRect(0, paper.height * MAX((NSInteger)0, page - 1), paper.width, paper.height);
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSPrintOperation* operation = NSPrintOperation.currentOperation;
    NSInteger page = operation ? operation.currentPage : 1;
    NSUInteger index = page > 0 ? (NSUInteger)(page - 1) : 0;
    if (index >= _paginationPlan.pages.count) return;
    NSRect pageRect = [self rectForPage:page];
    CGContextRef context = NSGraphicsContext.currentContext.CGContext;
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, pageRect.origin.x, pageRect.origin.y);
    [_paginationPlan drawPageAtIndex:index attributedString:_attributedString inContext:context];
    CGContextRestoreGState(context);
}

@end

@implementation SPDFMacMarkdownPrintAdapter

+ (NSPrintOperation*)printOperationForPaginationPlan:(SPDFMarkdownPaginationPlan*)plan
                                    attributedString:(NSAttributedString*)attributedString
                                           printInfo:(NSPrintInfo*)printInfo {
    NSPrintInfo* effectiveInfo = [printInfo copy] ?: [NSPrintInfo.sharedPrintInfo copy];
    SPDFMacMarkdownPrintView* view = [[SPDFMacMarkdownPrintView alloc] initWithPaginationPlan:plan
                                                                             attributedString:attributedString];
    [view fitPlanPaperToPrintInfo:effectiveInfo];
    NSPrintOperation* operation = [NSPrintOperation printOperationWithView:view printInfo:effectiveInfo];
    operation.printPanel.options |= NSPrintPanelShowsPreview | NSPrintPanelShowsPaperSize |
                                    NSPrintPanelShowsOrientation;
    operation.showsPrintPanel = YES;
    operation.showsProgressPanel = YES;
    return operation;
}

+ (BOOL)writePaginationPlan:(SPDFMarkdownPaginationPlan*)plan
           attributedString:(NSAttributedString*)attributedString
                      toURL:(NSURL*)URL
                      error:(NSError**)error {
    if (!plan || !attributedString || !URL.isFileURL) return NO;
    NSMutableData* data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect mediaBox = CGRectMake(0, 0, plan.configuration.paperSize.width, plan.configuration.paperSize.height);
    CGContextRef context = CGPDFContextCreate(consumer, &mediaBox, NULL);
    CGDataConsumerRelease(consumer);
    if (!context) return NO;
    for (NSUInteger page = 0; page < plan.pages.count; ++page) {
        CGPDFContextBeginPage(context, NULL);
        [plan drawPageAtIndex:page attributedString:attributedString inContext:context];
        CGPDFContextEndPage(context);
    }
    CGPDFContextClose(context);
    CGContextRelease(context);
    return [data writeToURL:URL options:NSDataWritingAtomic error:error];
}

@end
