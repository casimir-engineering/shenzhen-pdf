#import <AppKit/AppKit.h>
#import <PDFKit/PDFKit.h>

#import "../SPDFMacMarkdownPrinting.h"
#import "../markdown/SPDFMarkdown.h"

#include <assert.h>
#include <stdio.h>

int main(void) {
    @autoreleasepool {
        (void)NSApplication.sharedApplication;
        NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"md"]];
        NSString* markdown = @"# Release Notes\nThis text must remain selectable in the exported PDF.\n\n"
                              @"## Details\nA second section verifies heading pagination.\n";
        assert([markdown writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
        SPDFMarkdownDocument* document = [SPDFMarkdownDocument
            documentWithURL:[NSURL fileURLWithPath:path] options:nil error:nil];
        assert(document);

        NSPrintInfo* info = [NSPrintInfo.sharedPrintInfo copy];
        info.paperSize = NSMakeSize(612, 792);
        info.leftMargin = 42;
        info.rightMargin = 42;
        info.topMargin = 42;
        info.bottomMargin = 42;
        SPDFMarkdownPaginationPlan* plan = [SPDFMacMarkdownPrintAdapter
            paginationPlanForRenderedDocument:document.renderedDocument printInfo:info];
        assert(plan.pages.count >= 1);
        assert(NSEqualSizes(plan.configuration.paperSize, info.paperSize));

        NSPrintOperation* operation = [SPDFMacMarkdownPrintAdapter
            printOperationForRenderedDocument:document.renderedDocument printInfo:info];
        assert(operation.printPanel.options & NSPrintPanelShowsPreview);
        assert(operation.printPanel.options & NSPrintPanelShowsPaperSize);
        SPDFMacMarkdownPrintView* view = (SPDFMacMarkdownPrintView*)operation.view;
        NSRange range = NSMakeRange(0, 0);
        assert([view knowsPageRange:&range]);
        assert(range.length == plan.pages.count);

        NSString* output = [NSTemporaryDirectory() stringByAppendingPathComponent:
                            [NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"pdf"]];
        NSError* error = nil;
        assert([SPDFMacMarkdownPrintAdapter writeRenderedDocument:document.renderedDocument
                                                            toURL:[NSURL fileURLWithPath:output]
                                                        printInfo:info error:&error]);
        assert(!error);
        PDFDocument* PDF = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:output]];
        assert(PDF.pageCount == plan.pages.count);
        NSMutableString* text = [NSMutableString string];
        for (NSUInteger index = 0; index < PDF.pageCount; ++index)
            [text appendString:[PDF pageAtIndex:index].string ?: @""];
        assert([text containsString:@"Release Notes"]);
        assert([text containsString:@"selectable in the exported PDF"]);

        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        [NSFileManager.defaultManager removeItemAtPath:output error:nil];
        puts("SPDFMacMarkdownPrintingTests passed");
    }
    return 0;
}
