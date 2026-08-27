#import "SPDFMacMarkdownPrinting.h"

#import <CoreGraphics/CoreGraphics.h>

#import "markdown/SPDFMarkdown.h"

static SPDFMarkdownPageConfiguration* SPDFConfigurationForPrintInfo(NSPrintInfo* info) {
    NSSize paper = info.paperSize;
    NSRect printable = info.imageablePageBounds;
    if (paper.width < 72 || paper.height < 72 || !isfinite(paper.width) || !isfinite(paper.height))
        return SPDFMarkdownPageConfiguration.A4PortraitConfiguration;
    if (printable.size.width < 36 || printable.size.height < 36 || NSMaxX(printable) > paper.width + 1 ||
        NSMaxY(printable) > paper.height + 1)
        printable = NSMakeRect(36, 36, paper.width - 72, paper.height - 72);
    return [SPDFMarkdownPageConfiguration configurationForPaperSize:paper printableRect:printable];
}

@implementation SPDFMacMarkdownPrintView {
    NSPrintInfo* _sourcePrintInfo;
    SPDFMarkdownPaginationPlan* _paginationPlan;
    NSString* _configurationKey;
}

- (instancetype)initWithRenderedDocument:(SPDFMarkdownRenderedDocument*)document printInfo:(NSPrintInfo*)printInfo {
    self = [super initWithFrame:NSMakeRect(0, 0, 595, 842)];
    if (self) {
        _renderedDocument = document;
        _sourcePrintInfo = [printInfo copy] ?: [NSPrintInfo.sharedPrintInfo copy];
        [self rebuildPlanForPrintInfo:_sourcePrintInfo];
    }
    return self;
}

- (BOOL)isFlipped { return NO; }
- (SPDFMarkdownPaginationPlan*)paginationPlan { return _paginationPlan; }

- (NSString*)keyForPrintInfo:(NSPrintInfo*)info {
    NSRect rect = info.imageablePageBounds;
    return [NSString stringWithFormat:@"%.3f:%.3f:%.3f:%.3f:%.3f:%.3f", info.paperSize.width,
                                      info.paperSize.height, rect.origin.x, rect.origin.y,
                                      rect.size.width, rect.size.height];
}

- (void)rebuildPlanForPrintInfo:(NSPrintInfo*)info {
    NSString* key = [self keyForPrintInfo:info];
    if ([key isEqualToString:_configurationKey] && _paginationPlan) return;
    _configurationKey = key;
    _paginationPlan = [SPDFMacMarkdownPrintAdapter paginationPlanForRenderedDocument:_renderedDocument
                                                                            printInfo:info];
    NSSize paper = _paginationPlan.configuration.paperSize;
    self.frame = NSMakeRect(0, 0, paper.width, paper.height * MAX((NSUInteger)1, _paginationPlan.pages.count));
}

- (BOOL)knowsPageRange:(NSRangePointer)range {
    NSPrintInfo* info = NSPrintOperation.currentOperation.printInfo ?: _sourcePrintInfo;
    [self rebuildPlanForPrintInfo:info];
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
    [_paginationPlan drawPageAtIndex:index attributedString:_renderedDocument.attributedString inContext:context];
    CGContextRestoreGState(context);
}

@end

@implementation SPDFMacMarkdownPrintAdapter

+ (SPDFMarkdownPaginationPlan*)paginationPlanForRenderedDocument:(SPDFMarkdownRenderedDocument*)document
                                                       printInfo:(NSPrintInfo*)printInfo {
    SPDFMarkdownPageConfiguration* configuration = SPDFConfigurationForPrintInfo(printInfo ?: NSPrintInfo.sharedPrintInfo);
    SPDFMarkdownPaginator* paginator = [SPDFMarkdownPaginator new];
    NSArray* items = [paginator measureRenderedDocument:document
                                         containerWidth:NSWidth(configuration.printableRect)];
    return [paginator paginateItems:items configuration:configuration];
}

+ (NSPrintOperation*)printOperationForRenderedDocument:(SPDFMarkdownRenderedDocument*)document
                                             printInfo:(NSPrintInfo*)printInfo {
    NSPrintInfo* effectiveInfo = [printInfo copy] ?: [NSPrintInfo.sharedPrintInfo copy];
    SPDFMacMarkdownPrintView* view = [[SPDFMacMarkdownPrintView alloc] initWithRenderedDocument:document
                                                                                       printInfo:effectiveInfo];
    NSPrintOperation* operation = [NSPrintOperation printOperationWithView:view printInfo:effectiveInfo];
    operation.printPanel.options |= NSPrintPanelShowsPreview | NSPrintPanelShowsPaperSize |
                                    NSPrintPanelShowsOrientation;
    operation.showsPrintPanel = YES;
    operation.showsProgressPanel = YES;
    return operation;
}

+ (BOOL)writeRenderedDocument:(SPDFMarkdownRenderedDocument*)document
                        toURL:(NSURL*)URL
                    printInfo:(NSPrintInfo*)printInfo
                        error:(NSError**)error {
    if (!document || !URL.isFileURL) return NO;
    SPDFMarkdownPaginationPlan* plan = [self paginationPlanForRenderedDocument:document printInfo:printInfo];
    NSMutableData* data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect mediaBox = CGRectMake(0, 0, plan.configuration.paperSize.width, plan.configuration.paperSize.height);
    CGContextRef context = CGPDFContextCreate(consumer, &mediaBox, NULL);
    CGDataConsumerRelease(consumer);
    if (!context) return NO;
    for (NSUInteger page = 0; page < plan.pages.count; ++page) {
        CGPDFContextBeginPage(context, NULL);
        [plan drawPageAtIndex:page attributedString:document.attributedString inContext:context];
        CGPDFContextEndPage(context);
    }
    CGPDFContextClose(context);
    CGContextRelease(context);
    return [data writeToURL:URL options:NSDataWritingAtomic error:error];
}

@end
