#import "SPDFMarkdownTestSupport.h"

#import "../../markdown/SPDFMarkdownDocument.h"

static SPDFMarkdownTextLine* SPDFLine(NSUInteger location, CGFloat height) {
    return [[SPDFMarkdownTextLine alloc] initWithAttributedRange:NSMakeRange(location, 5)
                                                          height:height xOffset:0 baselineOffset:height * 0.8];
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
        for (SPDFMarkdownTextLine* line in item.lines) [expected addObject:[NSValue valueWithRange:line.attributedRange]];
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
            SPDFItem(1, SPDFMarkdownBlockKindParagraph, 0, @[@75]),
            SPDFItem(2, SPDFMarkdownBlockKindHeading, 2, @[@10]),
            SPDFItem(3, SPDFMarkdownBlockKindParagraph, 0, @[@15, @15]),
        ] configuration:SPDFTestPage()];
        SPDFExpect(threshold.pages.count == 2, @"heading at 75 percent moves with fresh-page section lead");
        SPDFExpect(threshold.pages[1].fragments.firstObject.blockIndex == 2, @"new page begins with heading");
        SPDFExpectExactLineRanges(threshold);

        SPDFMarkdownPaginationPlan* before = [paginator paginateItems:@[
            SPDFItem(1, SPDFMarkdownBlockKindParagraph, 0, @[@74]),
            SPDFItem(2, SPDFMarkdownBlockKindHeading, 2, @[@10]),
            SPDFItem(3, SPDFMarkdownBlockKindParagraph, 0, @[@15, @15]),
        ] configuration:SPDFTestPage()];
        BOOL headingOnFirstPage = NO;
        for (SPDFMarkdownPageFragment* fragment in before.pages[0].fragments)
            if (fragment.blockIndex == 2) headingOnFirstPage = YES;
        SPDFExpect(headingOnFirstPage, @"heading before 75 percent remains on current page");
        SPDFExpectExactLineRanges(before);

        SPDFMarkdownPaginationPlan* shortSection = [paginator paginateItems:@[
            SPDFItem(1, SPDFMarkdownBlockKindParagraph, 0, @[@75]),
            SPDFItem(2, SPDFMarkdownBlockKindHeading, 2, @[@10]),
            SPDFItem(3, SPDFMarkdownBlockKindParagraph, 0, @[@10]),
        ] configuration:SPDFTestPage()];
        SPDFExpect(shortSection.pages[0].fragments.count == 3,
                   @"late heading stays when its complete short section fits the remainder");

        SPDFMarkdownPaginationPlan* overTall = [paginator paginateItems:@[
            SPDFItem(9, SPDFMarkdownBlockKindParagraph, 0, @[@250]),
        ] configuration:SPDFTestPage()];
        SPDFMarkdownPageFragment* scaled = overTall.pages.firstObject.fragments.firstObject;
        SPDFExpect(overTall.pages.count == 1 && overTall.pages.firstObject.fragments.count == 1 &&
                       fabs(scaled.scale - 0.4) < 0.001 && fabs(scaled.height - 100) < 0.001,
                   @"a line taller than the printable page is scaled to fit instead of discarded");
        SPDFExpectExactLineRanges(overTall);

        NSError* error = nil;
        SPDFMarkdownDocument* document = [SPDFMarkdownDocument documentWithURL:SPDFFixtureURL(@"obsidian.md")
                                                                        options:nil error:&error];
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
        SPDFMarkdownPaginationPlan* measuredPlan = [paginator paginateItems:measured
                                                               configuration:SPDFMarkdownPageConfiguration.A4PortraitConfiguration];
        SPDFExpectExactLineRanges(measuredPlan);

        SPDFMarkdownPageConfiguration* A4 = SPDFMarkdownPageConfiguration.A4PortraitConfiguration;
        SPDFExpect(fabs(A4.paperSize.width - 595.2756) < 0.01 &&
                       fabs(A4.paperSize.height - 841.8898) < 0.01,
                   @"A4 portrait uses exact point dimensions");
        SPDFExpect(A4.headingKeepThreshold == 0.75, @"A4 and printer plans share the 75 percent rule");
    }
    return SPDFFinishTests(@"SPDFMarkdownPaginatorTests");
}
