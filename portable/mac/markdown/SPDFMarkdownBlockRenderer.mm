#import "SPDFMarkdownRenderInternal.h"

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

static NSMutableParagraphStyle* SPDFStyle(SPDFMarkdownRenderContext* context, NSUInteger depth) {
    NSMutableParagraphStyle* style = [NSMutableParagraphStyle new];
    style.lineSpacing = context.options.lineSpacing;
    style.paragraphSpacing = context.options.paragraphSpacing;
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
        case SPDFMarkdownSyntaxTokenComment: return NSColor.systemGreenColor;
        case SPDFMarkdownSyntaxTokenString: return NSColor.systemRedColor;
        case SPDFMarkdownSyntaxTokenNumber: return NSColor.systemBlueColor;
        case SPDFMarkdownSyntaxTokenKey: return NSColor.systemTealColor;
        case SPDFMarkdownSyntaxTokenMarkup: return NSColor.systemOrangeColor;
        case SPDFMarkdownSyntaxTokenKeyword: return NSColor.systemPurpleColor;
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

static void SPDFRecord(SPDFMarkdownRenderContext* context, SPDFMarkdownBlock* block, NSRange range,
                       NSUInteger depth) {
    if (!range.length) return;
    [context.output addAttribute:SPDFMarkdownBlockIndexAttribute value:@(block.blockIndex) range:range];
    [context.output addAttribute:SPDFMarkdownBlockKindAttribute value:@(block.kind) range:range];
    [context.blocks addObject:[[SPDFMarkdownRenderedBlock alloc] initWithBlockIndex:block.blockIndex
                                                                                kind:block.kind
                                                                     attributedRange:range
                                                                               level:block.level
                                                                               depth:depth]];
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

static CGFloat SPDFTabLocation(CGFloat left, CGFloat width, NSTextAlignment alignment) {
    if (alignment == NSTextAlignmentCenter) return left + width / 2;
    if (alignment == NSTextAlignmentRight) return left + width;
    return left;
}

static void SPDFRenderTable(SPDFMarkdownRenderContext* context, SPDFMarkdownBlock* table, NSUInteger depth,
                            BOOL record) {
    NSUInteger columnCount = MAX((NSUInteger)1, table.tableColumnCount);
    CGFloat columnWidth = MAX(80.0, context.options.maximumImageWidth / columnCount);
    for (SPDFMarkdownBlock* section in table.children) {
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
            if (record) SPDFRecord(context, row, range, depth);
        }
    }
}

static void SPDFRenderLeaf(SPDFMarkdownRenderContext* context, SPDFMarkdownBlock* block, NSUInteger depth,
                           BOOL record) {
    NSUInteger start = context.output.length;
    if (block.kind == SPDFMarkdownBlockKindThematicBreak) {
        SPDFAppend(context, @"────────────────\n",
                   @{NSForegroundColorAttributeName: context.options.secondaryTextColor});
    } else {
        SPDFRenderRuns(context, block);
        if (![context.output.string hasSuffix:@"\n"]) SPDFAppend(context, @"\n", @{});
    }
    NSRange range = NSMakeRange(start, context.output.length - start);
    NSMutableParagraphStyle* style = SPDFStyle(context, depth);
    if (block.kind == SPDFMarkdownBlockKindHeading) {
        CGFloat size = MAX(context.options.textSize + 2,
                           context.options.textSize + (7 - MIN(block.level, 6)) * 2);
        [context.output addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:size] range:range];
        style.paragraphSpacingBefore = block.level <= 2 ? 18 : 12;
        style.paragraphSpacing = 8;
    } else if (block.kind == SPDFMarkdownBlockKindCode) {
        [context.output addAttributes:@{
            NSFontAttributeName: context.codeFont,
            NSBackgroundColorAttributeName: context.options.codeBackgroundColor,
        } range:range];
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
        for (SPDFMarkdownBlock* child in block.children) SPDFRenderBlock(context, child, depth + 1, record);
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
