#import "SPDFMarkdownTestSupport.h"

#import "../../markdown/SPDFMarkdownDocument.h"

static SPDFMarkdownTextLine* SPDFLine(NSUInteger location, CGFloat height) {
    return [[SPDFMarkdownTextLine alloc] initWithAttributedRange:NSMakeRange(location, 5)
                                                          height:height
                                                         xOffset:0
                                                  baselineOffset:height * 0.8];
}

static SPDFMarkdownPaginationItem* SPDFItem(NSUInteger index, SPDFMarkdownBlockKind kind, NSUInteger level,
                                            NSArray<NSNumber*>* heights) {
    NSMutableArray* lines = [NSMutableArray array];
    NSUInteger location = index * 100;
    for (NSNumber* height in heights) {
        [lines addObject:SPDFLine(location, height.doubleValue)];
        location += 5;
    }
    return [[SPDFMarkdownPaginationItem alloc] initWithBlockIndex:index kind:kind headingLevel:level lines:lines];
}

static SPDFMarkdownPageConfiguration* SPDFTestPage(void) {
    return [SPDFMarkdownPageConfiguration configurationForPaperSize:NSMakeSize(100, 100)
                                                      printableRect:NSMakeRect(0, 0, 100, 100)];
}

static void SPDFExpectExactLineRanges(SPDFMarkdownPaginationPlan* plan) {
    NSMutableSet* expected = [NSMutableSet set];
    for (SPDFMarkdownPaginationItem* item in plan.items)
        for (SPDFMarkdownTextLine* line in item.lines)
            [expected addObject:[NSValue valueWithRange:line.attributedRange]];
    NSMutableSet* actual = [NSMutableSet set];
    for (SPDFMarkdownPage* page in plan.pages)
        for (SPDFMarkdownPageFragment* fragment in page.fragments)
            [actual addObject:[NSValue valueWithRange:fragment.attributedRange]];
    SPDFExpect([actual isEqualToSet:expected], @"pagination uses complete exact TextKit line ranges only");
}

int main(void) {
    @autoreleasepool {
        SPDFMarkdownPaginator* paginator = [SPDFMarkdownPaginator new];
        SPDFMarkdownPaginationPlan* threshold = [paginator paginateItems:@[
            SPDFItem(1, SPDFMarkdownBlockKindParagraph, 0, @[ @75 ]),
            SPDFItem(2, SPDFMarkdownBlockKindHeading, 2, @[ @10 ]),
            SPDFItem(3, SPDFMarkdownBlockKindParagraph, 0, @[ @15, @15 ]),
        ]
                                                           configuration:SPDFTestPage()];
        SPDFExpect(threshold.pages.count == 2, @"heading at 75 percent moves with fresh-page section lead");
        SPDFExpect(threshold.pages[1].fragments.firstObject.blockIndex == 2, @"new page begins with heading");
        SPDFExpectExactLineRanges(threshold);

        SPDFMarkdownPaginationPlan* before = [paginator paginateItems:@[
            SPDFItem(1, SPDFMarkdownBlockKindParagraph, 0, @[ @74 ]),
            SPDFItem(2, SPDFMarkdownBlockKindHeading, 2, @[ @10 ]),
            SPDFItem(3, SPDFMarkdownBlockKindParagraph, 0, @[ @15, @15 ]),
        ]
                                                        configuration:SPDFTestPage()];
        BOOL headingOnFirstPage = NO;
        for (SPDFMarkdownPageFragment* fragment in before.pages[0].fragments)
            if (fragment.blockIndex == 2) headingOnFirstPage = YES;
        SPDFExpect(headingOnFirstPage, @"heading before 75 percent remains on current page");
        SPDFExpectExactLineRanges(before);

        SPDFMarkdownPaginationPlan* shortSection = [paginator paginateItems:@[
            SPDFItem(1, SPDFMarkdownBlockKindParagraph, 0, @[ @75 ]),
            SPDFItem(2, SPDFMarkdownBlockKindHeading, 2, @[ @10 ]),
            SPDFItem(3, SPDFMarkdownBlockKindParagraph, 0, @[ @10 ]),
        ]
                                                              configuration:SPDFTestPage()];
        SPDFExpect(shortSection.pages[0].fragments.count == 3,
                   @"late heading stays when its complete short section fits the remainder");

        SPDFMarkdownPaginationPlan* overTall = [paginator paginateItems:@[
            SPDFItem(9, SPDFMarkdownBlockKindParagraph, 0, @[ @250 ]),
        ]
                                                          configuration:SPDFTestPage()];
        SPDFMarkdownPageFragment* scaled = overTall.pages.firstObject.fragments.firstObject;
        SPDFExpect(overTall.pages.count == 1 && overTall.pages.firstObject.fragments.count == 1 &&
                       fabs(scaled.scale - 0.4) < 0.001 && fabs(scaled.height - 100) < 0.001,
                   @"a line taller than the printable page is scaled to fit instead of discarded");
        SPDFExpectExactLineRanges(overTall);

        NSError* error = nil;
        SPDFMarkdownDocument* document = [SPDFMarkdownDocument documentWithURL:SPDFFixtureURL(@"obsidian.md")
                                                                       options:nil
                                                                         error:&error];
        NSArray* measured = [paginator measureRenderedDocument:document.renderedDocument containerWidth:220];
        BOOL foundCallout = NO;
        for (SPDFMarkdownPaginationItem* item in measured) {
            SPDFExpect(item.lines.count > 0, @"each measured item contains TextKit line fragments");
            for (SPDFMarkdownTextLine* line in item.lines)
                SPDFExpect(NSMaxRange(line.attributedRange) <= document.renderedDocument.attributedString.length,
                           @"measured line range is within canonical attributed text");
            if (item.kind == SPDFMarkdownBlockKindCallout) foundCallout = YES;
        }
        SPDFExpect(foundCallout, @"callout title is measured as pagination content");
        SPDFMarkdownPaginationPlan* measuredPlan =
            [paginator paginateItems:measured configuration:SPDFMarkdownPageConfiguration.A4PortraitConfiguration];
        SPDFExpectExactLineRanges(measuredPlan);

        SPDFMarkdownPageConfiguration* A4 = SPDFMarkdownPageConfiguration.A4PortraitConfiguration;
        SPDFExpect(fabs(A4.paperSize.width - 595.2756) < 0.01 && fabs(A4.paperSize.height - 841.8898) < 0.01,
                   @"A4 portrait uses exact point dimensions");
        SPDFExpect(A4.headingKeepThreshold == 0.75, @"A4 and printer plans share the 75 percent rule");
        SPDFExpect(!A4.includesCodeLanguageControlSpacing, @"A4 pagination defaults to print-safe code spacing");

        SPDFMarkdownParser* parser = [SPDFMarkdownParser new];
        SPDFMarkdownDocumentModel* codeModel = [parser parseString:@"# Code\n\n```\nfirst();\nsecond();\n```\n"
                                                         sourceURL:nil
                                                             error:nil];
        SPDFMarkdownRenderedDocument* codeDocument =
            [[SPDFMarkdownRenderer new] renderModel:codeModel
                                            options:SPDFMarkdownRenderOptions.defaultOptions
                                  languageOverrides:nil];
        NSArray<SPDFMarkdownPaginationItem*>* codeItems = [paginator measureRenderedDocument:codeDocument
                                                                              containerWidth:NSWidth(A4.printableRect)];
        SPDFMarkdownPaginationItem* measuredCode = nil;
        for (SPDFMarkdownPaginationItem* item in codeItems)
            if (item.kind == SPDFMarkdownBlockKindCode) measuredCode = item;
        SPDFExpect(measuredCode != nil && measuredCode.lines.firstObject.attributedRange.length > 0,
                   @"canonical code measurement has no synthetic control line");

        SPDFMarkdownPaginationPlan* printPlan = [paginator paginateItems:codeItems configuration:A4];
        SPDFMarkdownPaginationItem* printedCode = nil;
        for (SPDFMarkdownPaginationItem* item in printPlan.items)
            if (item.kind == SPDFMarkdownBlockKindCode) printedCode = item;
        SPDFMarkdownTextLine* printLead = printedCode.lines.firstObject;
        SPDFMarkdownTextLine* printTail = printedCode.lines.lastObject;
        SPDFExpect(printLead.attributedRange.length == 0 && fabs(printLead.height - 8.0) < 0.001 &&
                       printTail.attributedRange.length == 0 && fabs(printTail.height - 8.0) < 0.001,
                   @"print and export plans reserve 8pt code-box padding bands");
        SPDFExpect(printedCode.lines.count == measuredCode.lines.count + 2,
                   @"code-box padding wraps the measured code lines as one pagination item");

        SPDFMarkdownPageConfiguration* screenA4 = [A4 copy];
        screenA4.includesCodeLanguageControlSpacing = YES;
        SPDFMarkdownPaginationPlan* screenPlan = [paginator paginateItems:codeItems configuration:screenA4];
        SPDFMarkdownPaginationItem* screenCode = nil;
        for (SPDFMarkdownPaginationItem* item in screenPlan.items)
            if (item.kind == SPDFMarkdownBlockKindCode) screenCode = item;
        SPDFMarkdownTextLine* controlLine = screenCode.lines.firstObject;
        SPDFExpect(controlLine.attributedRange.length == 0 && fabs(controlLine.height - 34.0) < 0.001,
                   @"screen A4 opt-in reserves clear space between the language control and code");
        SPDFExpect(fabs(screenCode.lines.lastObject.height - 8.0) < 0.001 &&
                       screenCode.lines.lastObject.attributedRange.length == 0,
                   @"screen plans keep the trailing code-box padding band");
        SPDFExpect(screenCode.lines.count == printedCode.lines.count,
                   @"screen spacing preserves the code fence as one pagination item");
        SPDFExpect(screenPlan.configuration.includesCodeLanguageControlSpacing,
                   @"pagination-plan configuration copy preserves the screen opt-in");

        SPDFMarkdownPageDecoration* screenBox = nil;
        for (SPDFMarkdownPageDecoration* decoration in [screenPlan decorationsForPageIndex:0])
            if (decoration.type == SPDFMarkdownPageDecorationTypeCodeBox) screenBox = decoration;
        SPDFExpect(screenBox != nil &&
                       fabs(NSHeight(screenBox.rect) - (measuredCode.measuredHeight + 34.0 + 8.0)) < 0.01 &&
                       fabs(NSWidth(screenBox.rect) - NSWidth(A4.printableRect)) < 0.01,
                   @"the screen code box covers both reserved spacer bands at full printable width");

        SPDFMarkdownPaginationPlan* decorated = [paginator paginateItems:@[
            SPDFItem(1, SPDFMarkdownBlockKindParagraph, 0, @[ @20 ]),
            SPDFItem(2, SPDFMarkdownBlockKindCode, 0, @[ @10, @10 ]),
            SPDFItem(3, SPDFMarkdownBlockKindHeading, 2, @[ @10 ]),
            SPDFItem(4, SPDFMarkdownBlockKindHeading, 3, @[ @10 ]),
        ]
                                                           configuration:SPDFTestPage()];
        SPDFExpect(decorated.pages.count == 1, @"decoration scenario fits one page");
        NSArray<SPDFMarkdownPageDecoration*>* decorations = [decorated decorationsForPageIndex:0];
        SPDFMarkdownPageDecoration* codeBox = nil;
        SPDFMarkdownPageDecoration* headingRule = nil;
        BOOL unexpectedRule = NO;
        for (SPDFMarkdownPageDecoration* decoration in decorations) {
            if (decoration.type == SPDFMarkdownPageDecorationTypeCodeBox) codeBox = decoration;
            else if (decoration.blockIndex == 3) headingRule = decoration;
            else unexpectedRule = YES;
        }
        SPDFExpect(decorations.count == 2 && !unexpectedRule,
                   @"one code box and one H2 rule; level-3 headings and paragraphs get no decoration");
        SPDFExpect(codeBox.blockIndex == 2 && fabs(NSMinX(codeBox.rect)) < 0.001 &&
                       fabs(NSWidth(codeBox.rect) - 100) < 0.001 && fabs(NSMinY(codeBox.rect) - 20) < 0.001 &&
                       fabs(NSHeight(codeBox.rect) - 36) < 0.001,
                   @"the code box spans the printable width and covers the reserved padding bands");
        SPDFExpect(headingRule != nil && headingRule.type == SPDFMarkdownPageDecorationTypeHeadingRule &&
                       fabs(NSHeight(headingRule.rect) - 1) < 0.001 &&
                       fabs(NSWidth(headingRule.rect) - 100) < 0.001 && NSMinY(headingRule.rect) > 56 &&
                       NSMaxY(headingRule.rect) <= 66.001,
                   @"H1/H2 headings get a 1px full-width underline rule beneath their last fragment");
        SPDFExpect([decorated decorationsForPageIndex:1].count == 0,
                   @"out-of-range decoration queries return an empty array");

        SPDFMarkdownPaginationPlan* splitPlan = [paginator paginateItems:@[
            SPDFItem(7, SPDFMarkdownBlockKindCode, 0, @[ @60, @60 ]),
        ]
                                                           configuration:SPDFTestPage()];
        SPDFExpect(splitPlan.pages.count == 2, @"tall code splits across two pages");
        NSArray<SPDFMarkdownPageDecoration*>* splitFirst = [splitPlan decorationsForPageIndex:0];
        NSArray<SPDFMarkdownPageDecoration*>* splitSecond = [splitPlan decorationsForPageIndex:1];
        SPDFExpect(splitFirst.count == 1 && splitSecond.count == 1 &&
                       splitFirst.firstObject.type == SPDFMarkdownPageDecorationTypeCodeBox &&
                       splitSecond.firstObject.type == SPDFMarkdownPageDecorationTypeCodeBox &&
                       fabs(NSHeight(splitFirst.firstObject.rect) - 68) < 0.001 &&
                       fabs(NSHeight(splitSecond.firstObject.rect) - 68) < 0.001,
                   @"a code block continuing across pages gets one box per page portion");
    }
    return SPDFFinishTests(@"SPDFMarkdownPaginatorTests");
}
