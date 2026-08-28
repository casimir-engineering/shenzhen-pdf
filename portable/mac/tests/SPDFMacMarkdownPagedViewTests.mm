#import <AppKit/AppKit.h>

#import "../SPDFMacMarkdownPageCanvas.h"
#import "../SPDFMacMarkdownPanController.h"
#import "../SPDFMacMarkdownPagedView.h"
#import "../SPDFMacMarkdownSidebarModel.h"
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
        assert(codeItem.lines.count == measuredCodeItem.lines.count + 2);
        assert(codeItem.lines.firstObject.attributedRange.length == 0);
        assert(fabs(codeItem.lines.firstObject.height - (SPDFMarkdownCodeBoxOuterMargin + 34.0)) < 0.001);
        assert(codeItem.lines.lastObject.attributedRange.length == 0);
        assert(fabs(codeItem.lines.lastObject.height - (SPDFMarkdownCodeBoxOuterMargin + 8.0)) < 0.001);
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

        // --- GitHub-style language control: right-aligned inside the code
        // box's reserved header band ---
        NSRect printable = configuration.printableRect;
        NSRect controlFrame = [codeCanvas codeLanguageControlFrameForBlockIndex:codeBlockIndex];
        assert(!NSIsEmptyRect(controlFrame));
        CGFloat boxLeft = NSMinX(codePageFrame) + NSMinX(printable);
        CGFloat boxRight = boxLeft + NSWidth(printable);
        // The leading band opens with the unpainted outer margin above the box;
        // the control centers in the in-box header portion below it.
        CGFloat bandTop =
            NSMinY(codePageFrame) + NSMinY(printable) + controlFragment.pageYOffset + SPDFMarkdownCodeBoxOuterMargin;
        CGFloat headerHeight = controlFragment.height - SPDFMarkdownCodeBoxOuterMargin;
        assert(fabs(NSMaxX(controlFrame) - (boxRight - 10.0)) < 0.001); // 10pt off the box's right edge
        assert(NSMinX(controlFrame) > boxLeft);
        assert(NSMinY(controlFrame) >= bandTop);                 // inside the in-box header band...
        assert(NSMaxY(controlFrame) <= bandTop + headerHeight);  // ...reserved by the layout
        assert(fabs(NSHeight(controlFrame) - 20.0) < 0.001);
        assert(fabs(NSMidY(controlFrame) - (bandTop + headerHeight * 0.5)) < 1.0); // centered
        // Non-code blocks expose no control anchor.
        assert(codeBlockIndex != 0);
        assert(NSIsEmptyRect([codeCanvas codeLanguageControlFrameForBlockIndex:0]));
        assert(NSIsEmptyRect([codeCanvas codeLanguageControlFrameForBlockIndex:codeBlockIndex + 999]));
        NSPoint controlPoint = NSMakePoint(NSMidX(controlFrame), NSMidY(controlFrame));
        assert([[codeCanvas codeLanguageBlockAtPoint:controlPoint] unsignedIntegerValue] == codeBlockIndex);
        // The control no longer sits at the box's left edge.
        assert([codeCanvas codeLanguageBlockAtPoint:NSMakePoint(boxLeft + 8, NSMidY(controlFrame))] == nil);

        // --- Popover anchor geometry surfaced through the paged view ---
        SPDFMacMarkdownPagedView* codeView =
            [[SPDFMacMarkdownPagedView alloc] initWithPaginationPlan:codePlan
                                                    attributedString:codeRendered.attributedString];
        codeView.frame = NSMakeRect(0, 0, 900, 700);
        [codeView layoutSubtreeIfNeeded];
        [codeView applyFitMode:SPDFMacMarkdownPageFitPage];
        SPDFMacMarkdownPageCanvas* codeViewCanvas = (SPDFMacMarkdownPageCanvas*)codeView.documentView;
        NSRect anchorRect = [codeView codeLanguageControlFrameInViewForBlockIndex:codeBlockIndex];
        assert(!NSIsEmptyRect(anchorRect));
        assert(NSIntersectsRect(anchorRect, codeView.bounds));
        NSRect canvasAnchor = [codeViewCanvas codeLanguageControlFrameForBlockIndex:codeBlockIndex];
        // The conversion runs through the standard convertRect: chain, so the
        // anchor scales with the fit magnification.
        assert(fabs(NSWidth(anchorRect) - NSWidth(canvasAnchor) * codeView.magnification) < 0.5);
        assert(NSIsEmptyRect([codeView codeLanguageControlFrameInViewForBlockIndex:0]));
        // A control scrolled outside the viewport stops anchoring.
        [codeView setZoom:4.0 centeredAtPoint:NSMakePoint(NSMidX(codePageFrame), NSMaxY(codePageFrame))];
        [codeView.contentView
            scrollToPoint:NSMakePoint(0, NSHeight(codeViewCanvas.bounds) - NSHeight(codeView.contentView.bounds))];
        [codeView reflectScrolledClipView:codeView.contentView];
        assert(NSIsEmptyRect([codeView codeLanguageControlFrameInViewForBlockIndex:codeBlockIndex]));
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

        // --- Chapter reveal parity with the sidebar model (fix for chapter
        // jumps landing one page early when a heading starts a new page) ---
        NSMutableString* chapterSource = [NSMutableString string];
        NSUInteger paragraphsPerSection[] = {18, 21, 24, 27, 30, 33};
        for (NSUInteger section = 0; section < 6; ++section) {
            [chapterSource appendFormat:@"## Section %lu\n\n", (unsigned long)section];
            for (NSUInteger line = 0; line < paragraphsPerSection[section]; ++line)
                [chapterSource appendFormat:@"Section %lu paragraph %lu carries enough words to fill page space.\n\n",
                                            (unsigned long)section, (unsigned long)line];
        }
        SPDFMarkdownDocumentModel* chapterModel = [parser parseString:chapterSource sourceURL:nil error:nil];
        SPDFMarkdownRenderedDocument* chapterRendered =
            [[SPDFMarkdownRenderer new] renderModel:chapterModel
                                            options:[SPDFMarkdownRenderOptions defaultOptions]
                                  languageOverrides:nil];
        NSArray* chapterMeasuredItems = [paginator measureRenderedDocument:chapterRendered
                                                            containerWidth:NSWidth(configuration.printableRect)];
        SPDFMarkdownPaginationPlan* chapterPlan = [paginator paginateItems:chapterMeasuredItems
                                                             configuration:configuration];
        assert(chapterPlan.pages.count > 2);
        SPDFMacMarkdownSidebarModel* sidebarModel =
            [[SPDFMacMarkdownSidebarModel alloc] initWithRenderedDocument:chapterRendered paginationPlan:chapterPlan];
        assert(sidebarModel.chapterItems.count == 6);
        SPDFMacMarkdownPagedView* chapterView =
            [[SPDFMacMarkdownPagedView alloc] initWithPaginationPlan:chapterPlan
                                                    attributedString:chapterRendered.attributedString];
        assert([chapterView.contentView isKindOfClass:SPDFDocumentClipView.class]);
        chapterView.frame = NSMakeRect(0, 0, 900, 700);
        [chapterView layoutSubtreeIfNeeded];
        [chapterView applyFitMode:SPDFMacMarkdownPageFitPage];
        SPDFMacMarkdownPageCanvas* chapterCanvas = (SPDFMacMarkdownPageCanvas*)chapterView.documentView;
        NSDictionary* pageStartChapter = nil;
        for (NSDictionary* chapter in sidebarModel.chapterItems) {
            NSRange chapterRange = [chapter[@"range"] rangeValue];
            NSInteger sidebarPage = [chapter[@"page"] integerValue];
            // The canvas and the sidebar model must agree on the page for every
            // heading — the old inclusive range predicate reported the previous
            // page whenever a heading started a fresh page.
            assert((NSInteger)[chapterView pageIndexForRange:chapterRange] == sidebarPage);
            if (pageStartChapter || sidebarPage <= 0) continue;
            SPDFMarkdownPageFragment* firstFragment = nil;
            for (SPDFMarkdownPageFragment* fragment in chapterPlan.pages[(NSUInteger)sidebarPage].fragments) {
                if (!fragment.attributedRange.length) continue;
                firstFragment = fragment;
                break;
            }
            if (firstFragment && firstFragment.attributedRange.location == chapterRange.location)
                pageStartChapter = chapter;
        }
        // The fixture must contain a heading that starts a new page — the exact
        // scenario the regression covers.
        assert(pageStartChapter != nil);
        NSRange headingRange = [pageStartChapter[@"range"] rangeValue];
        NSInteger headingPage = [pageStartChapter[@"page"] integerValue];
        assert([chapterView revealRange:headingRange]);
        assert(chapterView.currentPageIndex == headingPage);
        SPDFMarkdownPageFragment* headingFragment = nil;
        for (SPDFMarkdownPageFragment* fragment in chapterPlan.pages[(NSUInteger)headingPage].fragments) {
            if (headingRange.location < fragment.attributedRange.location ||
                headingRange.location >= NSMaxRange(fragment.attributedRange))
                continue;
            headingFragment = fragment;
            break;
        }
        assert(headingFragment != nil);
        NSRect headingPageFrame = [chapterCanvas frameForPageAtIndex:(NSUInteger)headingPage];
        CGFloat headingTop =
            NSMinY(headingPageFrame) + NSMinY(configuration.printableRect) + headingFragment.pageYOffset;
        // The reveal is deterministic and top-aligned, matching the PDF path's
        // 12pt breathing room above the target.
        assert(fabs(NSMinY(chapterView.documentVisibleRect) - (headingTop - 12.0)) < 1.5);

        // --- Horizontal center lock parity with the PDF view ---
        NSRect lockPageFrame = [chapterCanvas frameForPageAtIndex:(NSUInteger)headingPage];
        [chapterView setZoom:1.45 centeredAtPoint:NSMakePoint(NSMidX(lockPageFrame), NSMidY(lockPageFrame))];
        lockPageFrame = [chapterCanvas frameForPageAtIndex:(NSUInteger)chapterView.currentPageIndex];
        CGFloat clipWidth = NSWidth(chapterView.contentView.bounds);
        assert(NSWidth(lockPageFrame) <= clipWidth + 0.5);              // page fits the viewport
        assert(chapterView.documentCanvasSize.width > clipWidth + 0.5); // canvas is pannable
        CGFloat centeredX =
            MAX(0.0, MIN(NSMidX(lockPageFrame) - clipWidth * 0.5, chapterView.documentCanvasSize.width - clipWidth));
        // A page narrower than the viewport is pinned centered: an attempted
        // horizontal scroll must leave the origin at the centered x.
        [chapterView scrollByDocumentDeltaX:50.0 deltaY:0.0];
        assert(fabs(NSMinX(chapterView.documentVisibleRect) - centeredX) < 0.5);
        assert(chapterView.horizontalScrollElasticity == NSScrollElasticityNone);
        // The clip view clamp guards the wheel/elastic paths too.
        NSRect proposedBounds = chapterView.contentView.bounds;
        proposedBounds.origin.x = 0.0;
        NSRect constrainedBounds = [chapterView.contentView constrainBoundsRect:proposedBounds];
        assert(fabs(NSMinX(constrainedBounds) - centeredX) < 0.5);

        // Zooming out must resize the canvas with the viewport (the stale-width
        // bug parked the page at the left edge on the next vertical scroll) and
        // keep the page horizontally centered afterwards.
        [chapterView setZoom:0.5 centeredAtPoint:NSMakePoint(NSMidX(lockPageFrame), NSMidY(lockPageFrame))];
        assert(chapterView.documentCanvasSize.width >= NSWidth(chapterView.contentView.bounds) - 0.5);
        [chapterView scrollByDocumentDeltaX:0.0 deltaY:300.0];
        NSRect zoomedPageFrame = [chapterCanvas frameForPageAtIndex:(NSUInteger)chapterView.currentPageIndex];
        assert(fabs(NSMidX(zoomedPageFrame) - NSMidX(chapterView.contentView.bounds)) < 1.0);
        puts("SPDFMacMarkdownPagedViewTests passed");
    }
    return 0;
}
