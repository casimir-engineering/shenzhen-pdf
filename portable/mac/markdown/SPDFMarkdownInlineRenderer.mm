#import "SPDFMarkdownDecorations.h"
#import "SPDFMarkdownRenderInternal.h"

// Inline-run rendering: styled text runs, links, and image attachments with
// their alt-text captions. Block structure (headings, lists, tables, quotes)
// stays in SPDFMarkdownBlockRenderer.mm; this file owns everything that flows
// inside a single block's runs.

NSAttributedStringKey const SPDFMarkdownImageLayoutAttribute = @"SPDFMarkdownImageLayout";

NSFont* SPDFMarkdownFontWithTraits(NSFont* font, NSFontTraitMask traits) {
    return [NSFontManager.sharedFontManager convertFont:font toHaveTrait:traits] ?: font;
}

void SPDFMarkdownAppend(SPDFMarkdownRenderContext* context, NSString* string,
                        NSDictionary<NSAttributedStringKey, id>* attributes) {
    if (string.length) {
        [context.output appendAttributedString:[[NSAttributedString alloc] initWithString:string
                                                                               attributes:attributes]];
    }
}

CGFloat SPDFMarkdownRenderScale(SPDFMarkdownRenderContext* context) {
    CGFloat scale = context.options.fontScale;
    return scale > 0 ? scale : 1;
}

static NSDictionary* SPDFRunAttributes(SPDFMarkdownRenderContext* context, SPDFMarkdownInlineRun* run) {
    NSFont* font = (run.traits & SPDFMarkdownInlineTraitCode) ? context.codeFont : context.bodyFont;
    if (run.traits & SPDFMarkdownInlineTraitStrong) font = SPDFMarkdownFontWithTraits(font, NSBoldFontMask);
    if (run.traits & SPDFMarkdownInlineTraitEmphasis) font = SPDFMarkdownFontWithTraits(font, NSItalicFontMask);
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
    if (run.title.length) attributes[NSToolTipAttributeName] = run.title;
    return attributes;
}

// A remote image whose bytes have not arrived yet renders as a fixed-size
// GitHub-gray box carrying the alt text, so the download landing later only
// swaps the attachment instead of reflowing the whole document from nothing.
// The box is drawn with concrete light-palette colors (like print decoration
// colors) via a deferred drawing handler, keeping render passes thread-safe.
static NSTextAttachment* SPDFPendingRemoteImageAttachment(SPDFMarkdownRenderContext* context, NSString* altText) {
    CGFloat width = MAX(64.0, context.options.maximumImageWidth);
    CGFloat height = MAX(48.0, context.options.remoteImagePlaceholderHeight);
    NSString* caption = altText.length ? altText : @"Loading image";
    NSFont* font = context.bodyFont;
    NSImage* image = [NSImage
         imageWithSize:NSMakeSize(width, height)
               flipped:NO
        drawingHandler:^BOOL(NSRect rect) {
          NSBezierPath* box = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, 0.5, 0.5)
                                                              xRadius:6
                                                              yRadius:6];
          [[NSColor colorWithSRGBRed:0xF6 / 255.0 green:0xF8 / 255.0 blue:0xFA / 255.0 alpha:1] setFill];
          [box fill];
          [[NSColor colorWithSRGBRed:0xD1 / 255.0 green:0xD9 / 255.0 blue:0xE0 / 255.0 alpha:1] setStroke];
          [box stroke];
          NSMutableParagraphStyle* style = [NSMutableParagraphStyle new];
          style.alignment = NSTextAlignmentCenter;
          style.lineBreakMode = NSLineBreakByTruncatingTail;
          NSDictionary* attributes = @{
              NSFontAttributeName: font,
              NSForegroundColorAttributeName:
                  [NSColor colorWithSRGBRed:0x59 / 255.0 green:0x63 / 255.0 blue:0x6E / 255.0 alpha:1],
              NSParagraphStyleAttributeName: style,
          };
          CGFloat lineHeight = ceil(font.ascender - font.descender + font.leading);
          NSRect textRect = NSInsetRect(rect, 12, 0);
          textRect.origin.y = NSMidY(rect) - lineHeight / 2;
          textRect.size.height = lineHeight;
          [caption drawWithRect:textRect options:NSStringDrawingUsesLineFragmentOrigin attributes:attributes context:nil];
          return YES;
        }];
    NSTextAttachment* attachment = [NSTextAttachment new];
    attachment.image = image;
    attachment.bounds = NSMakeRect(0, 0, width, height);
    return attachment;
}

// Figure captions read like GitHub's smallest heading role: below body size
// and muted, but regular weight.
static NSDictionary* SPDFCaptionAttributes(SPDFMarkdownRenderContext* context) {
    CGFloat size = context.options.textSize * 0.9 * SPDFMarkdownRenderScale(context);
    return @{
        NSFontAttributeName: [NSFont systemFontOfSize:size],
        NSForegroundColorAttributeName: context.options.secondaryTextColor,
        SPDFMarkdownImageLayoutAttribute: @(SPDFMarkdownImageLayoutRoleCaption),
    };
}

static void SPDFAppendImageAttachment(SPDFMarkdownRenderContext* context, SPDFMarkdownInlineRun* run,
                                      NSTextAttachment* attachment, NSString* target, BOOL standalone) {
    NSMutableAttributedString* attached = [[NSMutableAttributedString alloc]
        initWithAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
    [attached addAttribute:SPDFMarkdownImageTargetAttribute value:target range:NSMakeRange(0, 1)];
    if (run.title.length) [attached addAttribute:NSToolTipAttributeName value:run.title range:NSMakeRange(0, 1)];
    if (standalone) {
        [attached addAttribute:SPDFMarkdownImageLayoutAttribute
                         value:@(SPDFMarkdownImageLayoutRoleFigure)
                         range:NSMakeRange(0, 1)];
    }
    [context.output appendAttributedString:attached];
    if (!run.text.length) return;
    if (standalone) {
        // GitHub renders standalone images as figures: the alt text becomes a
        // real caption on its own line below the artwork instead of flowing to
        // the artwork's right.
        SPDFMarkdownAppend(context, @"\n",
                           @{SPDFMarkdownImageLayoutAttribute: @(SPDFMarkdownImageLayoutRoleFigure)});
        SPDFMarkdownAppend(context, run.text, SPDFCaptionAttributes(context));
    } else {
        SPDFMarkdownAppend(context, [@" " stringByAppendingString:run.text], SPDFRunAttributes(context, run));
    }
}

static BOOL SPDFIsWhitespaceRun(SPDFMarkdownInlineRun* run) {
    return [run.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0;
}

// A paragraph whose only meaningful content is a single image renders as a
// standalone centered figure; images embedded mid-sentence keep inline flow.
static BOOL SPDFBlockIsStandaloneImage(SPDFMarkdownBlock* block) {
    if (block.kind != SPDFMarkdownBlockKindParagraph) return NO;
    NSUInteger imageRuns = 0;
    for (SPDFMarkdownInlineRun* run in block.runs) {
        if (run.traits & SPDFMarkdownInlineTraitImage) ++imageRuns;
        else if (!SPDFIsWhitespaceRun(run)) return NO;
    }
    return imageRuns == 1;
}

void SPDFMarkdownRenderInlineRuns(SPDFMarkdownRenderContext* context, SPDFMarkdownBlock* block) {
    BOOL standalone = SPDFBlockIsStandaloneImage(block);
    for (SPDFMarkdownInlineRun* run in block.runs) {
        if (context.cancellationToken.isCancelled) return;
        if (!(run.traits & SPDFMarkdownInlineTraitImage)) {
            // Whitespace padding around a standalone image would keep the
            // figure paragraph from starting at the attachment (and carry the
            // uncentered base style), so the figure drops it.
            if (!standalone) SPDFMarkdownAppend(context, run.text, SPDFRunAttributes(context, run));
            continue;
        }
        NSString* destination = run.destination ?: @"";
        NSURL* resolvedURL = nil;
        NSImage* image = [context.resourceStore imageForTarget:destination resolvedURL:&resolvedURL];
        if (!image || image.size.width <= 0 || image.size.height <= 0) {
            // A well-formed https target with no fetched bytes yet is pending:
            // reserve real layout space for the asynchronous download. Fetched
            // bytes that fail to decode, session-reported fetch failures, and
            // every non-https remote scheme keep the stable text placeholder.
            NSString* remoteKey = SPDFMarkdownRemoteImageKeyForTarget(destination);
            BOOL pending = remoteKey != nil && context.resourceStore.remoteImageData[remoteKey] == nil &&
                           ![context.options.failedRemoteImageTargets containsObject:remoteKey];
            if (pending) {
                SPDFAppendImageAttachment(context, run, SPDFPendingRemoteImageAttachment(context, run.text),
                                          destination, standalone);
                continue;
            }
            NSMutableDictionary* attributes = [@{
                NSFontAttributeName: context.bodyFont,
                NSForegroundColorAttributeName: context.options.secondaryTextColor,
                SPDFMarkdownImageTargetAttribute: destination,
            } mutableCopy];
            if (run.title.length) attributes[NSToolTipAttributeName] = run.title;
            SPDFMarkdownAppend(context,
                               [NSString stringWithFormat:@"[Image: %@]", run.text.length ? run.text : @"untitled"],
                               attributes);
            continue;
        }
        CGFloat scale = MIN(1.0, MIN(context.options.maximumImageWidth / image.size.width,
                                     context.options.maximumImageHeight / image.size.height));
        NSTextAttachment* attachment = [NSTextAttachment new];
        attachment.image = image;
        attachment.bounds = NSMakeRect(0, 0, image.size.width * scale, image.size.height * scale);
        NSString* target = resolvedURL.isFileURL ? resolvedURL.path : (resolvedURL.absoluteString ?: destination);
        SPDFAppendImageAttachment(context, run, attachment, target, standalone);
    }
}

// Re-derives the centered figure/caption paragraph styles after the leaf
// renderer has applied the block's base style across its whole range. The
// figure paragraph keeps only a small gap above its caption; the caption
// paragraph keeps the block's own spacing below the figure.
void SPDFMarkdownApplyImageBlockStyles(SPDFMarkdownRenderContext* context, NSRange range,
                                       NSParagraphStyle* baseStyle) {
    [context.output
        enumerateAttribute:SPDFMarkdownImageLayoutAttribute
                   inRange:range
                   options:0
                usingBlock:^(NSNumber* role, NSRange markedRange, BOOL* stop) {
                  (void)stop;
                  if (!role) return;
                  NSMutableParagraphStyle* style = [baseStyle mutableCopy];
                  style.alignment = NSTextAlignmentCenter;
                  if (role.integerValue == SPDFMarkdownImageLayoutRoleFigure &&
                      NSMaxRange(markedRange) < context.output.length) {
                      NSNumber* next = [context.output attribute:SPDFMarkdownImageLayoutAttribute
                                                         atIndex:NSMaxRange(markedRange)
                                                  effectiveRange:NULL];
                      if (next.integerValue == SPDFMarkdownImageLayoutRoleCaption)
                          style.paragraphSpacing = 4 * SPDFMarkdownRenderScale(context);
                  }
                  NSRange paragraphRange = [context.output.string paragraphRangeForRange:markedRange];
                  [context.output addAttribute:NSParagraphStyleAttributeName
                                         value:style
                                         range:NSIntersectionRange(paragraphRange, range)];
                }];
}
