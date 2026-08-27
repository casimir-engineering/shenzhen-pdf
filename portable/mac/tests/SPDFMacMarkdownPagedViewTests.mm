#import <AppKit/AppKit.h>

#import "../SPDFMacMarkdownPageCanvas.h"
#import "../SPDFMacMarkdownPanController.h"
#import "../SPDFMacMarkdownPagedView.h"
#import "../markdown/SPDFMarkdown.h"

#include <assert.h>
#include <stdio.h>

@interface SPDFMarkdownPagedTestReader : NSObject
@property(nonatomic) NSUInteger menuRequests;
@end

@implementation SPDFMarkdownPagedTestReader
- (NSMenu*)contextMenuForDocumentView:(NSView*)view event:(NSEvent*)event {
    (void)view;
    (void)event;
    self.menuRequests++;
    NSMenu* menu = [NSMenu new];
    [menu addItemWithTitle:@"Shared Reader Action" action:nil keyEquivalent:@""];
    return menu;
}
- (void)copySelection:(id)sender {
    (void)sender;
}
@end

int main(void) {
    @autoreleasepool {
        (void)NSApplication.sharedApplication;
        NSString* untypedCode = @"# Demo\n\n## Code\n\n```\nlet first = 1;\nlet second = first + 1;\n```\n";
        SPDFMarkdownParser* parser = [SPDFMarkdownParser new];
        SPDFMarkdownDocumentModel* codeModel = [parser parseString:untypedCode sourceURL:nil error:nil];
        SPDFMarkdownRenderedDocument* codeRendered =
            [[SPDFMarkdownRenderer new] renderModel:codeModel
                                            options:[SPDFMarkdownRenderOptions defaultOptions]
                                  languageOverrides:nil];
        SPDFMarkdownPageConfiguration* configuration = [SPDFMarkdownPageConfiguration A4PortraitConfiguration];
        configuration.includesCodeLanguageControlSpacing = YES;
        SPDFMarkdownPaginator* paginator = [SPDFMarkdownPaginator new];
        NSArray* codeItems = [paginator measureRenderedDocument:codeRendered
                                                 containerWidth:NSWidth(configuration.printableRect)];
        NSUInteger codeBlockIndex = codeModel.codeFences.firstObject.blockIndex;
        NSPredicate* codeItemPredicate =
            [NSPredicate predicateWithBlock:^BOOL(SPDFMarkdownPaginationItem* item, NSDictionary* bindings) {
              (void)bindings;
              return item.kind == SPDFMarkdownBlockKindCode && item.blockIndex == codeBlockIndex;
            }];
        NSArray* matchingCodeItems = [codeItems filteredArrayUsingPredicate:codeItemPredicate];
        assert(matchingCodeItems.count == 1);
        SPDFMarkdownPaginationItem* measuredCodeItem = matchingCodeItems.firstObject;
        assert(measuredCodeItem.lines.count >= 2);
        assert(measuredCodeItem.lines.firstObject.attributedRange.length > 0);
        SPDFMarkdownPaginationPlan* codePlan = [paginator paginateItems:codeItems configuration:configuration];
        NSArray* configuredCodeItems = [codePlan.items filteredArrayUsingPredicate:codeItemPredicate];
        assert(configuredCodeItems.count == 1);
        SPDFMarkdownPaginationItem* codeItem = configuredCodeItems.firstObject;
        assert(codeItem.lines.count == measuredCodeItem.lines.count + 1);
        assert(codeItem.lines.firstObject.attributedRange.length == 0);
        assert(fabs(codeItem.lines.firstObject.height - 26.0) < 0.001);
        SPDFMacMarkdownPageCanvas* codeCanvas =
            [[SPDFMacMarkdownPageCanvas alloc] initWithPaginationPlan:codePlan
                                                     attributedString:codeRendered.attributedString];
        [codeCanvas resizeForWidth:800];
        assert([[codeCanvas codeLanguageLabelForBlockIndex:codeBlockIndex] isEqualToString:@"Plain Text"]);
        SPDFMarkdownPageFragment* controlFragment = nil;
        for (SPDFMarkdownPageFragment* fragment in codePlan.pages.firstObject.fragments) {
            if (fragment.blockIndex == codeBlockIndex && !fragment.isContinuation) {
                controlFragment = fragment;
                break;
            }
        }
        assert(controlFragment != nil);
        NSRect codePageFrame = [codeCanvas frameForPageAtIndex:0];
        NSPoint controlPoint =
            NSMakePoint(NSMinX(codePageFrame) + NSMinX(configuration.printableRect) + 8,
                        NSMinY(codePageFrame) + NSMinY(configuration.printableRect) + controlFragment.pageYOffset + 10);
        assert([[codeCanvas codeLanguageBlockAtPoint:controlPoint] unsignedIntegerValue] == codeBlockIndex);
        SPDFMarkdownPagedTestReader* menuReader = [SPDFMarkdownPagedTestReader new];
        codeCanvas.reader = (id<SPDFMacUIReader>)menuReader;
        NSEvent* contextEvent = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown
                                                   location:controlPoint
                                              modifierFlags:0
                                                  timestamp:1.0
                                               windowNumber:0
                                                    context:nil
                                                eventNumber:1
                                                 clickCount:1
                                                   pressure:1.0];
        NSMenu* contextMenu = [codeCanvas menuForEvent:contextEvent];
        assert(menuReader.menuRequests == 1);
        assert([contextMenu itemWithTitle:@"Shared Reader Action"] != nil);

        NSString* testPath = @(__FILE__);
        if (!testPath.isAbsolutePath)
            testPath = [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:testPath];
        NSString* fixturePath = [[testPath stringByDeletingLastPathComponent]
            stringByAppendingPathComponent:@"markdown/fixtures/language-picker-demo.md"];
        NSString* fixtureSource = [NSString stringWithContentsOfFile:fixturePath
                                                            encoding:NSUTF8StringEncoding
                                                               error:nil];
        assert(fixtureSource.length > 0);
        SPDFMarkdownDocumentModel* fixtureModel = [parser parseString:fixtureSource sourceURL:nil error:nil];
        assert(fixtureModel.codeFences.count == 1);
        SPDFMarkdownCodeFence* fixtureFence = fixtureModel.codeFences.firstObject;
        assert(fixtureFence.declaredLanguage.length == 0);
        assert([fixtureFence.code containsString:@"function summarizePages(pages)"]);
        assert([fixtureFence.code containsString:@"const result = summarizePages"]);
        SPDFMarkdownRenderedDocument* fixtureRendered =
            [[SPDFMarkdownRenderer new] renderModel:fixtureModel
                                            options:[SPDFMarkdownRenderOptions defaultOptions]
                                  languageOverrides:nil];
        NSArray* fixtureItems = [paginator measureRenderedDocument:fixtureRendered
                                                    containerWidth:NSWidth(configuration.printableRect)];
        NSPredicate* fixtureCodePredicate =
            [NSPredicate predicateWithBlock:^BOOL(SPDFMarkdownPaginationItem* item, NSDictionary* bindings) {
              (void)bindings;
              return item.kind == SPDFMarkdownBlockKindCode && item.blockIndex == fixtureFence.blockIndex;
            }];
        assert([fixtureItems filteredArrayUsingPredicate:fixtureCodePredicate].count == 1);

        NSMutableString* source = [NSMutableString stringWithString:@"# A4 document\n\n"];
        for (NSUInteger index = 0; index < 240; ++index)
            [source appendFormat:@"Line %lu contains searchable text and page content.\n\n", (unsigned long)index];
        SPDFMarkdownDocumentModel* model = [parser parseString:source sourceURL:nil error:nil];
        assert(model != nil);
        SPDFMarkdownRenderedDocument* rendered =
            [[SPDFMarkdownRenderer new] renderModel:model
                                            options:[SPDFMarkdownRenderOptions defaultOptions]
                                  languageOverrides:nil];
        NSArray* items = [paginator measureRenderedDocument:rendered
                                             containerWidth:NSWidth(configuration.printableRect)];
        SPDFMarkdownPaginationPlan* plan = [paginator paginateItems:items configuration:configuration];
        assert(plan.pages.count > 2);

        SPDFMacMarkdownPagedView* view =
            [[SPDFMacMarkdownPagedView alloc] initWithPaginationPlan:plan attributedString:rendered.attributedString];
        assert([view isKindOfClass:SPDFScrollView.class]);
        NSObject* reader = [NSObject new];
        view.reader = (id<SPDFMacUIReader>)reader;
        assert(view.reader == (id<SPDFMacUIReader>)reader);
        view.frame = NSMakeRect(0, 0, 900, 700);
        [view layoutSubtreeIfNeeded];
        [view applyFitMode:SPDFMacMarkdownPageFitPage];
        assert(view.magnification > 0.1 && view.magnification <= 1.0);
        [view goToPageAtIndex:2 alignTop:YES];
        assert(view.currentPageIndex == 2);
        view.presentationMode = YES;
        assert(!view.hasVerticalScroller);
        assert(((SPDFMacMarkdownPageCanvas*)view.documentView).presentationMode);
        assert([view.backgroundColor isEqual:NSColor.blackColor]);
        view.presentationMode = NO;
        assert(view.hasVerticalScroller);
        assert(!((SPDFMacMarkdownPageCanvas*)view.documentView).presentationMode);
        NSRect thirdPageFrame = view.documentPageRects[2].rectValue;
        [view.contentView scrollToPoint:NSMakePoint(0, NSMinY(thirdPageFrame))];
        [view reflectScrolledClipView:view.contentView];
        NSUInteger visibleLocation = view.visibleAttributedLocation;
        assert(visibleLocation != NSNotFound);
        NSUInteger thirdPageStart = NSNotFound;
        NSUInteger thirdPageEnd = 0;
        for (SPDFMarkdownPageFragment* fragment in plan.pages[2].fragments) {
            if (!fragment.attributedRange.length) continue;
            thirdPageStart = MIN(thirdPageStart, fragment.attributedRange.location);
            thirdPageEnd = MAX(thirdPageEnd, NSMaxRange(fragment.attributedRange));
        }
        assert(thirdPageStart != NSNotFound);
        assert(visibleLocation >= thirdPageStart && visibleLocation <= thirdPageEnd);

        NSRange match = [rendered.attributedString.string rangeOfString:@"Line 200"];
        assert(match.location != NSNotFound);
        assert([view pageIndexForRange:match] > 0);
        view.searchRanges = @[ [NSValue valueWithRange:match] ];
        view.selectedRange = match;
        assert([view.selectedText isEqualToString:@"Line 200"]);
        assert([view revealRange:match]);

        CGFloat before = view.magnification;
        [view zoomByFactor:1.2];
        assert(view.fitMode == SPDFMacMarkdownPageFitCustom);
        assert(view.magnification > before);

        CGEventRef wheelCG = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 2, 20, 0);
        CGEventSetFlags(wheelCG, kCGEventFlagMaskCommand);
        NSEvent* wheelZoom = [NSEvent eventWithCGEvent:wheelCG];
        CFRelease(wheelCG);
        before = view.magnification;
        assert([view zoomWithScrollWheelEvent:wheelZoom centeredAtWindowPoint:NSMakePoint(450, 350)]);
        assert(view.magnification > before);
        before = view.magnification;
        [view magnifyByDelta:-0.1 centeredAtDocumentPoint:NSMakePoint(NSMidX(thirdPageFrame), NSMidY(thirdPageFrame))];
        assert(view.magnification < before);
        [view setZoom:2.0 centeredAtPoint:NSMakePoint(NSMidX(thirdPageFrame), NSMidY(thirdPageFrame))];
        [view.contentView scrollToPoint:NSMakePoint(80, NSMinY(thirdPageFrame))];
        [view reflectScrolledClipView:view.contentView];
        SPDFMacMarkdownPanController* pan =
            [[SPDFMacMarkdownPanController alloc] initWithDocumentView:view.documentView];
        NSPoint panOrigin = view.documentVisibleRect.origin;
        [pan beginAtWindowPoint:NSMakePoint(200, 200) timestamp:1.0];
        assert(pan.isPanning && !pan.moved);
        [pan continueAtWindowPoint:NSMakePoint(170, 200) timestamp:2.0];
        assert(pan.moved);
        assert(view.documentVisibleRect.origin.x > panOrigin.x);
        [pan end];
        assert(!pan.isPanning);
        [view noteExternalScrollPositionChanged];
        assert(view.currentPageIndex >= 0 && view.currentPageIndex < (NSInteger)view.pageCount);
        puts("SPDFMacMarkdownPagedViewTests passed");
    }
    return 0;
}
