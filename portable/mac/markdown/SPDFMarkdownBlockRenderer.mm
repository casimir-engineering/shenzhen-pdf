#import "SPDFMarkdownDecorations.h"
#import "SPDFMarkdownRenderInternal.h"
#import "SPDFMarkdownTableDecorations.h"

@implementation SPDFMarkdownRenderContext
@end

static NSFont* SPDFFontWithTraits(NSFont* font, NSFontTraitMask traits) {
    return [NSFontManager.sharedFontManager convertFont:font toHaveTrait:traits] ?: font;
}

static void SPDFAppend(SPDFMarkdownRenderContext* context, NSString* string, NSDictionary* attributes) {
    if (string.length) {
        [context.output appendAttributedString:[[NSAttributedString alloc] initWithString:string
                                                                               attributes:attributes]];
    }
}

static CGFloat SPDFScale(SPDFMarkdownRenderContext* context) {
    CGFloat scale = context.options.fontScale;
    return scale > 0 ? scale : 1;
}

static NSMutableParagraphStyle* SPDFStyle(SPDFMarkdownRenderContext* context, NSUInteger depth) {
    NSMutableParagraphStyle* style = [NSMutableParagraphStyle new];
    style.lineSpacing = context.options.lineSpacing * SPDFScale(context);
    style.paragraphSpacing = context.options.paragraphSpacing * SPDFScale(context);
    style.headIndent = depth * 22;
    style.firstLineHeadIndent = depth * 22;
    return style;
}

static NSDictionary* SPDFRunAttributes(SPDFMarkdownRenderContext* context, SPDFMarkdownInlineRun* run) {
    NSFont* font = (run.traits & SPDFMarkdownInlineTraitCode) ? context.codeFont : context.bodyFont;
    if (run.traits & SPDFMarkdownInlineTraitStrong) font = SPDFFontWithTraits(font, NSBoldFontMask);
    if (run.traits & SPDFMarkdownInlineTraitEmphasis) font = SPDFFontWithTraits(font, NSItalicFontMask);
    NSMutableDictionary* attributes = [@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: context.options.textColor,
    } mutableCopy];
    if (run.traits & SPDFMarkdownInlineTraitStrikethrough) attributes[NSStrikethroughStyleAttributeName] = @1;
    if (run.traits & SPDFMarkdownInlineTraitCode) {
        attributes[NSBackgroundColorAttributeName] = context.options.codeBackgroundColor;
    }
    if (run.traits & SPDFMarkdownInlineTraitLink) {
        NSURL* URL = [NSURL URLWithString:run.destination ?: @""];
        NSString* scheme = URL.scheme.lowercaseString;
        attributes[NSForegroundColorAttributeName] = context.options.linkColor;
        attributes[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
        if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] ||
            [scheme isEqualToString:@"mailto"]) {
            attributes[NSLinkAttributeName] = URL;
        }
    }
    if (run.traits & SPDFMarkdownInlineTraitWikiLink) {
        attributes[SPDFMarkdownWikiLinkAttribute] = run.destination ?: @"";
    }
    return attributes;
}

static void SPDFRenderRuns(SPDFMarkdownRenderContext* context, SPDFMarkdownBlock* block) {
    for (SPDFMarkdownInlineRun* run in block.runs) {
        if (context.cancellationToken.isCancelled) return;
        if (!(run.traits & SPDFMarkdownInlineTraitImage)) {
            SPDFAppend(context, run.text, SPDFRunAttributes(context, run));
            continue;
        }
        NSURL* resolvedURL = nil;
        NSImage* image = [context.resourceStore imageForTarget:run.destination ?: @"" resolvedURL:&resolvedURL];
        if (!image || image.size.width <= 0 || image.size.height <= 0) {
            SPDFAppend(context, [NSString stringWithFormat:@"[Image: %@]", run.text.length ? run.text : @"untitled"],
                       @{
                           NSFontAttributeName: context.bodyFont,
                           NSForegroundColorAttributeName: context.options.secondaryTextColor,
                           SPDFMarkdownImageTargetAttribute: run.destination ?: @"",
                       });
            continue;
        }
        CGFloat scale = MIN(1.0, MIN(context.options.maximumImageWidth / image.size.width,
                                     context.options.maximumImageHeight / image.size.height));
        NSTextAttachment* attachment = [NSTextAttachment new];
        attachment.image = image;
        attachment.bounds = NSMakeRect(0, 0, image.size.width * scale, image.size.height * scale);
        NSMutableAttributedString* attached = [[NSMutableAttributedString alloc]
            initWithAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
        [attached addAttribute:SPDFMarkdownImageTargetAttribute
                         value:resolvedURL.path ?: run.destination ?: @""
                         range:NSMakeRange(0, 1)];
        [context.output appendAttributedString:attached];
        if (run.text.length) SPDFAppend(context, [@" " stringByAppendingString:run.text], SPDFRunAttributes(context, run));
    }
}

static NSColor* SPDFTokenColor(SPDFMarkdownSyntaxTokenKind kind) {
    switch (kind) {
        case SPDFMarkdownSyntaxTokenComment: return SPDFMarkdownTheme.syntaxCommentColor;
        case SPDFMarkdownSyntaxTokenString: return SPDFMarkdownTheme.syntaxStringColor;
        case SPDFMarkdownSyntaxTokenNumber: return SPDFMarkdownTheme.syntaxNumberColor;
        case SPDFMarkdownSyntaxTokenKey: return SPDFMarkdownTheme.syntaxKeyColor;
        case SPDFMarkdownSyntaxTokenMarkup: return SPDFMarkdownTheme.syntaxMarkupColor;
        case SPDFMarkdownSyntaxTokenKeyword: return SPDFMarkdownTheme.syntaxKeywordColor;
    }
}

static void SPDFApplyCodeTokens(SPDFMarkdownRenderContext* context, NSRange range,
                                SPDFMarkdownLanguage* language) {
    NSString* code = [context.output.string substringWithRange:range];
    NSArray<SPDFMarkdownSyntaxToken*>* tokens =
        [context.highlighter tokensForCode:code language:language cancellationToken:context.cancellationToken];
    for (SPDFMarkdownSyntaxToken* token in tokens) {
        [context.output addAttribute:NSForegroundColorAttributeName
                               value:SPDFTokenColor(token.kind)
                               range:NSMakeRange(range.location + token.range.location, token.range.length)];
    }
}

static void SPDFRecordWithTableRow(SPDFMarkdownRenderContext* context, SPDFMarkdownBlock* block, NSRange range,
                                   NSUInteger depth, SPDFMarkdownTableRowInfo* tableRowInfo) {
    if (!range.length) return;
    [context.output addAttribute:SPDFMarkdownBlockIndexAttribute value:@(block.blockIndex) range:range];
    [context.output addAttribute:SPDFMarkdownBlockKindAttribute value:@(block.kind) range:range];
    [context.blocks addObject:[[SPDFMarkdownRenderedBlock alloc] initWithBlockIndex:block.blockIndex
                                                                                kind:block.kind
                                                                     attributedRange:range
                                                                               level:block.level
                                                                               depth:depth
                                                                        tableRowInfo:tableRowInfo]];
}

static void SPDFRecord(SPDFMarkdownRenderContext* context, SPDFMarkdownBlock* block, NSRange range,
                       NSUInteger depth) {
    SPDFRecordWithTableRow(context, block, range, depth, nil);
}

static void SPDFRenderBlock(SPDFMarkdownRenderContext* context, SPDFMarkdownBlock* block, NSUInteger depth,
                            BOOL record);

static void SPDFRenderList(SPDFMarkdownRenderContext* context, SPDFMarkdownBlock* list, NSUInteger depth,
                           BOOL record) {
    NSInteger number = list.orderedStart;
    for (SPDFMarkdownBlock* item in list.children) {
        if (context.cancellationToken.isCancelled) return;
        NSUInteger itemStart = context.output.length;
        NSString* marker = list.kind == SPDFMarkdownBlockKindOrderedList
            ? [NSString stringWithFormat:@"%ld. ", (long)number++] : @"• ";
        if (item.taskState >= 0) marker = item.taskState ? @"☑ " : @"☐ ";
        NSMutableDictionary* markerAttributes = [@{
            NSFontAttributeName: context.bodyFont,
            NSForegroundColorAttributeName: context.options.secondaryTextColor,
            NSParagraphStyleAttributeName: SPDFStyle(context, depth),
        } mutableCopy];
        SPDFAppend(context, marker, markerAttributes);

        BOOL recordedFirstContent = NO;
        if (item.runs.count) {
            SPDFRenderRuns(context, item);
            SPDFAppend(context, @"\n", @{});
            if (record) SPDFRecord(context, item, NSMakeRange(itemStart, context.output.length - itemStart), depth);
            recordedFirstContent = YES;
        }

        for (SPDFMarkdownBlock* child in item.children) {
            BOOL nestedList = child.kind == SPDFMarkdownBlockKindUnorderedList ||
                              child.kind == SPDFMarkdownBlockKindOrderedList;
            if (nestedList) {
                SPDFRenderList(context, child, depth + 1, record);
                continue;
            }
            NSUInteger childStart = context.output.length;
            SPDFRenderBlock(context, child, depth + 1, record && recordedFirstContent);
            if (!recordedFirstContent) {
                if (record) {
                    SPDFRecord(context, item, NSMakeRange(itemStart, context.output.length - itemStart), depth);
                }
                recordedFirstContent = YES;
            } else if (context.output.length == childStart) {
                continue;
            }
        }
        if (!recordedFirstContent) {
            SPDFAppend(context, @"\n", @{});
            if (record) SPDFRecord(context, item, NSMakeRange(itemStart, context.output.length - itemStart), depth);
        }
    }
}

static NSTextAlignment SPDFTextAlignment(SPDFMarkdownTableAlignment alignment) {
    if (alignment == SPDFMarkdownTableAlignmentCenter) return NSTextAlignmentCenter;
    if (alignment == SPDFMarkdownTableAlignmentRight) return NSTextAlignmentRight;
    return NSTextAlignmentLeft;
}

// Horizontal padding kept between a cell's tab stop and its column edges, so
// glyphs never touch the vertical grid hairlines. It also keeps every stop
// strictly inside its column: a stop at exactly the paragraph origin (a
// left-aligned first column at location 0) would never satisfy TextKit's
// "next tab stop" rule, shifting every cell one stop over and wrapping the
// last cell onto its own line.
static const CGFloat kSPDFMarkdownTableCellInset = 8.0;

static CGFloat SPDFTabLocation(CGFloat left, CGFloat width, NSTextAlignment alignment) {
    if (alignment == NSTextAlignmentCenter) return left + width / 2;
    if (alignment == NSTextAlignmentRight) return left + width - kSPDFMarkdownTableCellInset;
    return left + kSPDFMarkdownTableCellInset;
}

// Symmetric vertical padding reserved inside every table row so the drawn grid
// hairlines never touch glyphs. Scaled by fontScale like all vertical spacing.
static const CGFloat kSPDFMarkdownTableRowPadding = 6.0;

static void SPDFRenderTable(SPDFMarkdownRenderContext* context, SPDFMarkdownBlock* table, NSUInteger depth,
                            BOOL record) {
    NSUInteger columnCount = MAX((NSUInteger)1, table.tableColumnCount);
    CGFloat columnWidth = MAX(80.0, context.options.maximumImageWidth / columnCount);
    NSMutableArray<NSNumber*>* boundaries = [NSMutableArray arrayWithCapacity:columnCount + 1];
    for (NSUInteger i = 0; i <= columnCount; ++i) [boundaries addObject:@(depth * 22 + i * columnWidth)];
    NSUInteger bodyRowIndex = 0;
    for (SPDFMarkdownBlock* section in table.children) {
        BOOL headerSection = section.kind == SPDFMarkdownBlockKindTableHead;
        for (SPDFMarkdownBlock* row in section.children) {
            if (context.cancellationToken.isCancelled) return;
            NSUInteger start = context.output.length;
            for (NSUInteger i = 0; i < row.children.count; ++i) {
                SPDFAppend(context, @"\t", @{});
                NSUInteger cellStart = context.output.length;
                SPDFMarkdownBlock* cell = row.children[i];
                SPDFRenderRuns(context, cell);
                if (cell.kind == SPDFMarkdownBlockKindTableHeaderCell) {
                    [context.output addAttribute:NSFontAttributeName
                                           value:SPDFFontWithTraits(context.bodyFont, NSBoldFontMask)
                                           range:NSMakeRange(cellStart, context.output.length - cellStart)];
                }
            }
            SPDFAppend(context, @"\n", @{});
            NSRange range = NSMakeRange(start, context.output.length - start);
            NSMutableParagraphStyle* style = SPDFStyle(context, depth);
            style.alignment = NSTextAlignmentLeft;
            style.paragraphSpacingBefore = kSPDFMarkdownTableRowPadding * SPDFScale(context);
            style.paragraphSpacing = kSPDFMarkdownTableRowPadding * SPDFScale(context);
            NSMutableArray<NSTextTab*>* tabs = [NSMutableArray array];
            for (NSUInteger i = 0; i < row.children.count; ++i) {
                NSTextAlignment alignment = SPDFTextAlignment(row.children[i].tableAlignment);
                CGFloat left = depth * 22 + i * columnWidth;
                [tabs addObject:[[NSTextTab alloc] initWithTextAlignment:alignment
                                                               location:SPDFTabLocation(left, columnWidth, alignment)
                                                                options:@{}]];
            }
            style.tabStops = tabs;
            [context.output addAttribute:NSParagraphStyleAttributeName value:style range:range];
            if (record) {
                SPDFMarkdownTableRowInfo* info =
                    [[SPDFMarkdownTableRowInfo alloc] initWithTableBlockIndex:table.blockIndex
                                                                    headerRow:headerSection
                                                                 bodyRowIndex:headerSection ? 0 : bodyRowIndex
                                                             columnBoundaries:boundaries];
                SPDFRecordWithTableRow(context, row, range, depth, info);
            }
            if (!headerSection) ++bodyRowIndex;
        }
    }
}

static void SPDFRenderLeaf(SPDFMarkdownRenderContext* context, SPDFMarkdownBlock* block, NSUInteger depth,
                           BOOL record) {
    NSUInteger start = context.output.length;
    if (block.kind == SPDFMarkdownBlockKindThematicBreak) {
        // The break contributes an invisible blank line that reserves layout
        // space; the visible hairline is a page decoration
        // (SPDFMarkdownPageDecorationTypeThematicBreakRule), so it prints as a
        // real rule instead of a run of box-drawing characters.
        SPDFAppend(context, @"\n",
                   @{
                       NSFontAttributeName: context.bodyFont,
                       NSForegroundColorAttributeName: context.options.secondaryTextColor,
                   });
    } else {
        SPDFRenderRuns(context, block);
        if (![context.output.string hasSuffix:@"\n"]) SPDFAppend(context, @"\n", @{});
    }
    NSRange range = NSMakeRange(start, context.output.length - start);
    NSMutableParagraphStyle* style = SPDFStyle(context, depth);
    if (block.kind == SPDFMarkdownBlockKindHeading) {
        // GitHub-style em ladder on the body size, set in semibold — full bold
        // reads heavy at display sizes. H6 drops below body and goes muted,
        // Primer's caption-like smallest heading.
        static const CGFloat ratios[] = {1.75, 1.5, 1.25, 1.1, 1.0, 0.9};
        NSUInteger level = MIN(MAX(block.level, (NSUInteger)1), (NSUInteger)6);
        CGFloat size = context.options.textSize * ratios[level - 1] * SPDFScale(context);
        [context.output addAttribute:NSFontAttributeName
                               value:[NSFont systemFontOfSize:size weight:NSFontWeightSemibold]
                               range:range];
        if (level == 6) {
            [context.output addAttribute:NSForegroundColorAttributeName
                                   value:context.options.secondaryTextColor
                                   range:range];
        }
        style.paragraphSpacingBefore = (level <= 2 ? 22 : 16) * SPDFScale(context);
        style.paragraphSpacing = (level <= 2 ? 10 : 8) * SPDFScale(context);
    } else if (block.kind == SPDFMarkdownBlockKindCode) {
        // Fenced code flows as one continuous block: tight line spacing, no
        // inter-line paragraph gaps, and a 12pt inset so the text sits inside
        // the unified code box drawn behind it. The box background itself is a
        // page decoration, not a per-character attribute.
        [context.output addAttribute:NSFontAttributeName value:context.codeFont range:range];
        style.lineSpacing = 2 * SPDFScale(context);
        style.paragraphSpacing = 0;
        style.paragraphSpacingBefore = 0;
        style.firstLineHeadIndent = depth * 22 + 12;
        style.headIndent = depth * 22 + 12;
        style.tailIndent = -12;
        NSString* identifier = context.overrides[@(block.blockIndex)] ?: block.codeLanguage;
        SPDFMarkdownLanguage* language = [context.catalog languageForFenceIdentifier:identifier];
        if (language) {
            [context.output addAttribute:SPDFMarkdownCodeLanguageAttribute value:language.identifier range:range];
            SPDFApplyCodeTokens(context, range, language);
        }
    }
    [context.output addAttribute:NSParagraphStyleAttributeName value:style range:range];
    if (record) SPDFRecord(context, block, range, depth);
}

static void SPDFRenderBlock(SPDFMarkdownRenderContext* context, SPDFMarkdownBlock* block, NSUInteger depth,
                            BOOL record) {
    if (context.cancellationToken.isCancelled) return;
    if (block.kind == SPDFMarkdownBlockKindUnorderedList || block.kind == SPDFMarkdownBlockKindOrderedList) {
        SPDFRenderList(context, block, depth, record);
    } else if (block.kind == SPDFMarkdownBlockKindTable) {
        SPDFRenderTable(context, block, depth, record);
    } else if (block.kind == SPDFMarkdownBlockKindBlockQuote) {
        // Quoted prose reads muted, GitHub-style. Only runs still in the plain
        // body color are recolored, so links, inline code chips, and syntax
        // tokens inside the quote keep their own roles.
        NSUInteger start = context.output.length;
        for (SPDFMarkdownBlock* child in block.children) SPDFRenderBlock(context, child, depth + 1, record);
        NSRange quoteRange = NSMakeRange(start, context.output.length - start);
        NSMutableArray<NSValue*>* bodyRanges = [NSMutableArray array];
        [context.output enumerateAttribute:NSForegroundColorAttributeName
                                   inRange:quoteRange
                                   options:0
                                usingBlock:^(NSColor* color, NSRange colorRange, BOOL* stop) {
                                  (void)stop;
                                  if ([color isEqual:context.options.textColor])
                                      [bodyRanges addObject:[NSValue valueWithRange:colorRange]];
                                }];
        for (NSValue* value in bodyRanges) {
            [context.output addAttribute:NSForegroundColorAttributeName
                                   value:context.options.quoteColor
                                   range:value.rangeValue];
        }
    } else if (block.kind == SPDFMarkdownBlockKindCallout) {
        NSUInteger start = context.output.length;
        SPDFAppend(context, [(block.calloutTitle ?: block.calloutKind ?: @"Note") stringByAppendingString:@"\n"],
                   @{
                       NSFontAttributeName: SPDFFontWithTraits(context.bodyFont, NSBoldFontMask),
                       NSForegroundColorAttributeName: context.options.quoteColor,
                   });
        NSRange titleRange = NSMakeRange(start, context.output.length - start);
        [context.output addAttribute:NSParagraphStyleAttributeName value:SPDFStyle(context, depth) range:titleRange];
        if (record) SPDFRecord(context, block, titleRange, depth);
        for (SPDFMarkdownBlock* child in block.children) SPDFRenderBlock(context, child, depth + 1, record);
    } else {
        SPDFRenderLeaf(context, block, depth, record);
    }
}

void SPDFRenderMarkdownBlocks(SPDFMarkdownRenderContext* context, NSArray<SPDFMarkdownBlock*>* blocks) {
    for (SPDFMarkdownBlock* block in blocks) SPDFRenderBlock(context, block, 0, YES);
}
