#import "SPDFMarkdownDiagramBand.h"
#import "SPDFMarkdownRenderInternal.h"

// The block-renderer hook: a fenced code block whose language is a diagram
// type (mermaid / sequence / flow) renders as native VECTOR artwork instead of
// a code box. The fence SOURCE text is not canonical (like image
// attachments), but every diagram LABEL is: each label lands in the attributed
// string as its own tab-separated run, so a diagram's text is selectable,
// findable by Cmd+F, copied with the selection, and exported as real text.
// The shapes travel separately, as one page decoration (see
// SPDFMarkdownDiagramBand.h). When the seam returns nil the caller falls
// through to the unchanged code-box path and the code text stays canonical.
//
// The rendered block is recorded as a PARAGRAPH: pagination and decoration
// planning must not reserve code-box spacer bands, draw the code box, or offer
// the interactive language pill for a diagram.

BOOL SPDFMarkdownRenderDiagramBlock(SPDFMarkdownRenderContext* context, SPDFMarkdownBlock* block,
                                          NSUInteger depth, BOOL record) {
    NSString* identifier = context.overrides[@(block.blockIndex)] ?: block.codeLanguage;
    if (!SPDFMarkdownDiagramIsDiagramLanguage(identifier)) return NO;
    CGFloat contentWidth = MAX(64.0, context.options.maximumImageWidth);
    SPDFMarkdownDiagramLayout* layout =
        SPDFMarkdownDiagramRender(identifier, block.plainText ?: @"", contentWidth, context.options.fontScale,
                                  context.options.diagramCache);
    if (!layout) return NO;

    NSUInteger start = context.output.length;
    SPDFMarkdownThemeVariant variant = context.options.themeVariant;
    NSMutableArray<NSValue*>* labelRanges = [NSMutableArray arrayWithCapacity:layout.labels.count];
    for (SPDFMarkdownDiagramLabel* label in layout.labels) {
        // One tab between labels: it keeps neighboring labels from reading as
        // one word for search and selection, and gives the flowing fallback
        // text view a legible column-ish layout.
        SPDFMarkdownAppend(context, @"\t", @{});
        NSUInteger labelStart = context.output.length;
        SPDFMarkdownAppend(context, label.text,
                           @{
                               NSFontAttributeName: label.font,
                               NSForegroundColorAttributeName: SPDFMarkdownDiagramLabelColor(label, variant),
                           });
        [labelRanges addObject:[NSValue valueWithRange:NSMakeRange(labelStart,
                                                                   context.output.length - labelStart)]];
    }
    SPDFMarkdownAppend(context, @"\n", @{});

    NSRange range = NSMakeRange(start, context.output.length - start);
    CGFloat scale = SPDFMarkdownRenderScale(context);
    NSMutableParagraphStyle* style = [NSMutableParagraphStyle new];
    style.lineSpacing = context.options.lineSpacing * scale;
    style.paragraphSpacing = context.options.paragraphSpacing * scale;
    style.headIndent = depth * 22;
    style.firstLineHeadIndent = depth * 22;
    style.alignment = NSTextAlignmentCenter;  // the flowing fallback view centers the labels
    [context.output addAttribute:NSParagraphStyleAttributeName value:style range:range];
    if (record) {
        [context.output addAttribute:SPDFMarkdownBlockIndexAttribute value:@(block.blockIndex) range:range];
        [context.output addAttribute:SPDFMarkdownBlockKindAttribute
                               value:@(SPDFMarkdownBlockKindParagraph)
                               range:range];
        // The paginated band reserves its own air above and below the artwork
        // (paragraph spacing never reaches a band item).
        CGFloat margin = context.options.paragraphSpacing * scale;
        SPDFMarkdownDiagramBlockInfo* info =
            [[SPDFMarkdownDiagramBlockInfo alloc] initWithLayout:layout
                                                     labelRanges:labelRanges
                                                       topMargin:margin
                                                    bottomMargin:margin
                                                     depthIndent:depth * 22];
        [context.blocks addObject:[[SPDFMarkdownRenderedBlock alloc] initWithBlockIndex:block.blockIndex
                                                                                   kind:SPDFMarkdownBlockKindParagraph
                                                                        attributedRange:range
                                                                                  level:block.level
                                                                                  depth:depth
                                                                           tableRowInfo:nil
                                                                            diagramInfo:info]];
    }
    return YES;
}
