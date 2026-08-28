#import "SPDFMarkdownTestSupport.h"

#import "../../markdown/SPDFMarkdownDocument.h"

// Local-image layout by paragraph shape: a single-image paragraph renders as
// a centered figure with the alt text as a centered caption line below the
// artwork; a paragraph of several images keeps them inline, CommonMark-style,
// flowing side by side in one center-aligned paragraph with no visible
// captions; and images mixed into sentence text keep plain inline flow, also
// caption-free.

static void SPDFExpectSearchCorrespondence(SPDFMarkdownDocument* document, NSString* query) {
    NSArray* matches = [document searchForQuery:query caseSensitive:YES];
    SPDFExpect(matches.count > 0, [@"search finds " stringByAppendingString:query]);
    for (SPDFMarkdownSearchMatch* match in matches) {
        NSString* selected = [document.renderedDocument.attributedString.string substringWithRange:match.range];
        SPDFExpect([selected isEqualToString:query], [@"search range exactly selects " stringByAppendingString:query]);
    }
}

static NSURL* SPDFCreateImageDocument(void) {
    NSString* directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES
                                               attributes:nil error:nil];
    NSBitmapImageRep* bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                      pixelsWide:4 pixelsHigh:2 bitsPerSample:8
                                                                    samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                    colorSpaceName:NSCalibratedRGBColorSpace
                                                                       bytesPerRow:0 bitsPerPixel:0];
    memset(bitmap.bitmapData, 0x7f, bitmap.bytesPerRow * bitmap.pixelsHigh);
    NSData* PNG = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [PNG writeToFile:[directory stringByAppendingPathComponent:@"local.png"] atomically:YES];
    [PNG writeToFile:[directory stringByAppendingPathComponent:@"second.png"] atomically:YES];
    NSMutableString* source = [NSMutableString stringWithString:@"# Image\n\n"];
    for (NSUInteger index = 0; index < 200; ++index)
        [source appendString:@"![Local pixels](local.png)\n\n"];
    [source appendString:@"![Budgeted out](second.png)\n\n"];
    [source appendString:@"![Badge one](local.png)\n![Badge two](local.png)\n\n"];
    [source appendString:@"Inline sentence with ![Inline art](local.png) image continues.\n"];
    [source writeToFile:[directory stringByAppendingPathComponent:@"image.md"]
             atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"image.md"]];
}

int main(void) {
    @autoreleasepool {
        NSError* error = nil;
        SPDFMarkdownRenderOptions* imageOptions = SPDFMarkdownRenderOptions.defaultOptions;
        imageOptions.maximumDecodedImagePixels = 8;
        SPDFMarkdownDocument* imageDocument = [SPDFMarkdownDocument documentWithURL:SPDFCreateImageDocument()
                                                                             options:imageOptions error:&error];
        SPDFExpect(imageDocument != nil && error == nil, @"local-image document loads and renders");
        __block NSImage* sharedImage = nil;
        __block NSUInteger attachmentCount = 0;
        __block BOOL allAttachmentsShared = YES;
        [imageDocument.renderedDocument.attributedString enumerateAttribute:NSAttachmentAttributeName
                                                                     inRange:NSMakeRange(0, imageDocument.renderedDocument.attributedString.length)
                                                                     options:0
                                                                  usingBlock:^(id value, NSRange range, BOOL* stop) {
            (void)stop;
            NSTextAttachment* attachment = value;
            if (attachment && range.length == 1) {
                ++attachmentCount;
                if (!sharedImage) sharedImage = attachment.image;
                else if (sharedImage != attachment.image) allAttachmentsShared = NO;
                SPDFExpect(attachment.bounds.size.width <= 480 && attachment.bounds.size.height <= 320,
                           @"each cached image remains constrained to render bounds");
            }
        }];
        // 200 repeated figures + the two row images + the inline image all
        // reference local.png and share one decoded NSImage.
        SPDFExpect(attachmentCount == 203 && allAttachmentsShared,
                   @"repeated image references reuse one decoded image rather than multiplying memory");
        SPDFExpect([imageDocument.renderedDocument.attributedString.string containsString:@"[Image: Budgeted out]"],
                   @"an image beyond the aggregate pixel budget becomes a graceful placeholder");
        SPDFExpectSearchCorrespondence(imageDocument, @"Local pixels");

        // Standalone images render as GitHub-style figures: the alt text is a
        // muted caption on its own centered line below the artwork (never
        // beside it), and the attachment paragraph centers within the page.
        NSAttributedString* figureString = imageDocument.renderedDocument.attributedString;
        NSRange figureRange = [figureString.string rangeOfString:@"\uFFFC\nLocal pixels"];
        SPDFExpect(figureRange.location != NSNotFound,
                   @"a standalone image's alt text renders on its own line below the attachment");
        SPDFExpect((NSUInteger)[figureString.string componentsSeparatedByString:@"Local pixels"].count == 201,
                   @"alt text still appears exactly once per image");
        NSUInteger captionIndex = figureRange.location + 2;
        NSFont* captionFont = [figureString attribute:NSFontAttributeName atIndex:captionIndex effectiveRange:nil];
        NSColor* captionColor = [figureString attribute:NSForegroundColorAttributeName
                                                atIndex:captionIndex
                                         effectiveRange:nil];
        SPDFExpect(fabs(captionFont.pointSize - 13.5) < 0.01 &&
                       [captionColor isEqual:imageOptions.secondaryTextColor],
                   @"figure captions drop below body size and go muted, caption-style");
        NSParagraphStyle* figureStyle = [figureString attribute:NSParagraphStyleAttributeName
                                                        atIndex:figureRange.location
                                                 effectiveRange:nil];
        NSParagraphStyle* captionStyle = [figureString attribute:NSParagraphStyleAttributeName
                                                         atIndex:captionIndex
                                                  effectiveRange:nil];
        SPDFExpect(figureStyle.alignment == NSTextAlignmentCenter && captionStyle.alignment == NSTextAlignmentCenter,
                   @"figure and caption paragraphs are center-aligned");
        SPDFMarkdownPageConfiguration* figureConfiguration = SPDFMarkdownPageConfiguration.A4PortraitConfiguration;
        SPDFMarkdownPaginationPlan* figurePlan = [imageDocument paginationPlanForConfiguration:figureConfiguration];
        SPDFMarkdownPageFragment* attachmentFragment = nil;
        SPDFMarkdownPageFragment* captionFragment = nil;
        for (SPDFMarkdownPageFragment* fragment in figurePlan.pages.firstObject.fragments) {
            if (!fragment.attributedRange.length) continue;
            if (NSLocationInRange(figureRange.location, fragment.attributedRange)) attachmentFragment = fragment;
            if (NSLocationInRange(captionIndex, fragment.attributedRange) &&
                !NSLocationInRange(figureRange.location, fragment.attributedRange))
                captionFragment = fragment;
            if (attachmentFragment && captionFragment) break;
        }
        SPDFExpect(attachmentFragment != nil && captionFragment != nil,
                   @"the attachment and its caption paginate as two separate fragments");
        SPDFExpect(attachmentFragment && captionFragment &&
                       captionFragment.pageYOffset >
                           attachmentFragment.pageYOffset + attachmentFragment.height - 0.5,
                   @"the caption fragment sits strictly below the attachment fragment");
        NSTextAttachment* figureAttachment = [figureString attribute:NSAttachmentAttributeName
                                                             atIndex:figureRange.location
                                                      effectiveRange:nil];
        CGFloat printableWidth = NSWidth(figureConfiguration.printableRect);
        SPDFExpect(attachmentFragment &&
                       fabs(attachmentFragment.xOffset -
                            (printableWidth - figureAttachment.bounds.size.width) / 2) < 1.0,
                   @"a standalone image centers within the printable width");
        NSAttributedString* captionText = [figureString
            attributedSubstringFromRange:NSMakeRange(captionIndex, [@"Local pixels" length])];
        CGFloat captionWidth = NSWidth([captionText boundingRectWithSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)
                                                                  options:NSStringDrawingUsesLineFragmentOrigin
                                                                  context:nil]);
        SPDFExpect(captionFragment && captionFragment.xOffset > 8.0 &&
                       fabs(captionFragment.xOffset + captionWidth / 2 - printableWidth / 2) < 2.0,
                   @"the caption centers within the printable width instead of hanging at the image's right");

        // A paragraph containing several images (with nothing but whitespace/
        // soft breaks between them) keeps them inline, CommonMark-style: the
        // images flow side by side in one paragraph -- the soft break renders
        // as a plain space -- with no visible alt captions, and the row
        // paragraph center-aligns as a group.
        NSRange rowRange = [figureString.string rangeOfString:@"\uFFFC \uFFFC"];
        SPDFExpect(rowRange.location != NSNotFound,
                   @"a multi-image paragraph flows its images side by side separated by a space");
        SPDFExpect(![figureString.string containsString:@"Badge one"] &&
                       ![figureString.string containsString:@"Badge two"],
                   @"a multi-image paragraph shows no visible alt captions");
        if (rowRange.location != NSNotFound) {
            NSUInteger firstImageIndex = rowRange.location;
            NSUInteger secondImageIndex = rowRange.location + 2;
            for (NSNumber* index in @[ @(firstImageIndex), @(secondImageIndex) ]) {
                NSParagraphStyle* rowStyle = [figureString attribute:NSParagraphStyleAttributeName
                                                             atIndex:index.unsignedIntegerValue
                                                      effectiveRange:nil];
                SPDFExpect(rowStyle.alignment == NSTextAlignmentCenter,
                           @"the multi-image row paragraph is center-aligned");
            }
            SPDFExpect([[figureString attribute:SPDFMarkdownImageTargetAttribute
                                        atIndex:secondImageIndex
                                 effectiveRange:nil] hasSuffix:@"local.png"],
                       @"row images keep their target metadata");
            SPDFMarkdownPageFragment* (^fragmentForIndex)(NSUInteger) =
                ^SPDFMarkdownPageFragment*(NSUInteger characterIndex) {
                  for (SPDFMarkdownPage* page in figurePlan.pages) {
                      for (SPDFMarkdownPageFragment* fragment in page.fragments) {
                          if (fragment.attributedRange.length &&
                              NSLocationInRange(characterIndex, fragment.attributedRange))
                              return fragment;
                      }
                  }
                  return nil;
                };
            SPDFMarkdownPageFragment* firstRowFragment = fragmentForIndex(firstImageIndex);
            SPDFMarkdownPageFragment* secondRowFragment = fragmentForIndex(secondImageIndex);
            SPDFExpect(firstRowFragment != nil && secondRowFragment != nil,
                       @"both row images land in pagination fragments");
            SPDFExpect(firstRowFragment && secondRowFragment && firstRowFragment == secondRowFragment,
                       @"both row images share one line fragment band");
            if (firstRowFragment && firstRowFragment == secondRowFragment) {
                NSAttributedString* rowLine =
                    [figureString attributedSubstringFromRange:firstRowFragment.attributedRange];
                CTLineRef line = SPDFMarkdownCreateFragmentLine(rowLine);
                CGFloat lineWidth = (CGFloat)CTLineGetTypographicBounds(line, NULL, NULL, NULL) -
                                    (CGFloat)CTLineGetTrailingWhitespaceWidth(line);
                CGFloat firstX = CTLineGetOffsetForStringIndex(
                    line, (CFIndex)(firstImageIndex - firstRowFragment.attributedRange.location), NULL);
                CGFloat secondX = CTLineGetOffsetForStringIndex(
                    line, (CFIndex)(secondImageIndex - firstRowFragment.attributedRange.location), NULL);
                CFRelease(line);
                NSTextAttachment* rowAttachment = [figureString attribute:NSAttachmentAttributeName
                                                                  atIndex:firstImageIndex
                                                           effectiveRange:nil];
                SPDFExpect(rowAttachment != nil && firstX < 0.5 &&
                               secondX > firstX + rowAttachment.bounds.size.width + 0.5,
                           @"the second image sits to the first image's right, past its width plus the space");
                SPDFExpect(fabs(firstRowFragment.xOffset + lineWidth / 2 - printableWidth / 2) < 2.0,
                           @"the image row centers as a group within the printable width");
            }
        }

        // An image genuinely mixed into sentence text keeps inline flow and
        // emits no visible alt-text caption (GitHub shows nothing); the alt
        // survives only as the attachment's target/tooltip metadata.
        SPDFExpect(![figureString.string containsString:@"Inline art"],
                   @"an inline image emits no visible alt-text caption");
        NSRange inlineSentence =
            [figureString.string rangeOfString:@"Inline sentence with \uFFFC image continues."];
        SPDFExpect(inlineSentence.location != NSNotFound,
                   @"an inline image flows inside its sentence without extra line breaks");
        if (inlineSentence.location != NSNotFound) {
            NSUInteger inlineAttachmentIndex = inlineSentence.location + [@"Inline sentence with " length];
            NSParagraphStyle* inlineStyle = [figureString attribute:NSParagraphStyleAttributeName
                                                            atIndex:inlineAttachmentIndex
                                                     effectiveRange:nil];
            SPDFExpect(inlineStyle.alignment != NSTextAlignmentCenter,
                       @"an inline image's paragraph keeps the block's own alignment");
            NSString* inlineTarget = [figureString attribute:SPDFMarkdownImageTargetAttribute
                                                     atIndex:inlineAttachmentIndex
                                              effectiveRange:nil];
            SPDFExpect([inlineTarget hasSuffix:@"local.png"],
                       @"the inline image keeps its target metadata");
        }
    }
    return SPDFFinishTests(@"SPDFMarkdownImageFigureTests");
}
