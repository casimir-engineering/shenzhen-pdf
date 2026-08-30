#import "SPDFMarkdownDiagram.h"
#import "SPDFMarkdownRenderInternal.h"

// The block-renderer hook: a fenced code block whose language is a diagram
// type (mermaid / sequence / flow) renders as a CENTERED FIGURE attachment
// through the existing image-figure machinery instead of a code box. The
// fence SOURCE text is then not part of the canonical string (exactly like
// image attachments); when the seam returns nil the caller falls through to
// the unchanged code-box path and the code text stays canonical as today.
//
// The rendered block is recorded as a PARAGRAPH: pagination and decoration
// planning must not reserve code-box spacer bands, draw the code box, or
// offer the interactive language pill for a figure.

BOOL SPDFMarkdownRenderDiagramFigureBlock(SPDFMarkdownRenderContext* context, SPDFMarkdownBlock* block,
                                          NSUInteger depth, BOOL record) {
    NSString* identifier = context.overrides[@(block.blockIndex)] ?: block.codeLanguage;
    if (!SPDFMarkdownDiagramIsDiagramLanguage(identifier)) return NO;
    CGFloat contentWidth = MAX(64.0, context.options.maximumImageWidth);
    SPDFMarkdownDiagramImage* diagram =
        SPDFMarkdownDiagramRender(identifier, block.plainText ?: @"", contentWidth, context.options.fontScale,
                                  context.options.themeVariant, context.options.diagramCache);
    if (!diagram) return NO;

    NSUInteger start = context.output.length;
    NSTextAttachment* attachment = [NSTextAttachment new];
    attachment.image = diagram.image;
    attachment.bounds = NSMakeRect(0, 0, diagram.logicalSize.width, diagram.logicalSize.height);
    NSMutableAttributedString* attached = [[NSMutableAttributedString alloc]
        initWithAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
    [attached addAttribute:SPDFMarkdownImageLayoutAttribute
                     value:@(SPDFMarkdownImageLayoutRoleFigure)
                     range:NSMakeRange(0, 1)];
    [context.output appendAttributedString:attached];
    SPDFMarkdownAppend(context, @"\n", @{});

    NSRange range = NSMakeRange(start, context.output.length - start);
    NSMutableParagraphStyle* style = [NSMutableParagraphStyle new];
    style.lineSpacing = context.options.lineSpacing * SPDFMarkdownRenderScale(context);
    style.paragraphSpacing = context.options.paragraphSpacing * SPDFMarkdownRenderScale(context);
    style.headIndent = depth * 22;
    style.firstLineHeadIndent = depth * 22;
    [context.output addAttribute:NSParagraphStyleAttributeName value:style range:range];
    SPDFMarkdownApplyImageBlockStyles(context, range, style);  // centers the figure paragraph
    if (record) {
        [context.output addAttribute:SPDFMarkdownBlockIndexAttribute value:@(block.blockIndex) range:range];
        [context.output addAttribute:SPDFMarkdownBlockKindAttribute
                               value:@(SPDFMarkdownBlockKindParagraph)
                               range:range];
        [context.blocks addObject:[[SPDFMarkdownRenderedBlock alloc]
                                      initWithBlockIndex:block.blockIndex
                                                    kind:SPDFMarkdownBlockKindParagraph
                                         attributedRange:range
                                                   level:block.level
                                                   depth:depth]];
    }
    return YES;
}
