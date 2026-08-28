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

static void SPDFWritePNG(NSString* path, NSInteger width, NSInteger height) {
    NSBitmapImageRep* bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                      pixelsWide:width pixelsHigh:height
                                                                    bitsPerSample:8
                                                                    samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                    colorSpaceName:NSCalibratedRGBColorSpace
                                                                       bytesPerRow:0 bitsPerPixel:0];
    memset(bitmap.bitmapData, 0x7f, bitmap.bytesPerRow * bitmap.pixelsHigh);
    NSData* PNG = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [PNG writeToFile:path atomically:YES];
}

static NSString* SPDFCreateFixtureDirectory(void) {
    NSString* directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES
                                               attributes:nil error:nil];
    return directory;
}

static SPDFMarkdownPageFragment* SPDFFragmentForIndex(SPDFMarkdownPaginationPlan* plan, NSUInteger characterIndex) {
    for (SPDFMarkdownPage* page in plan.pages) {
        for (SPDFMarkdownPageFragment* fragment in page.fragments) {
            if (fragment.attributedRange.length && NSLocationInRange(characterIndex, fragment.attributedRange))
                return fragment;
        }
    }
    return nil;
}

static NSURL* SPDFCreateImageDocument(void) {
    NSString* directory = SPDFCreateFixtureDirectory();
    SPDFWritePNG([directory stringByAppendingPathComponent:@"local.png"], 4, 2);
    SPDFWritePNG([directory stringByAppendingPathComponent:@"second.png"], 4, 2);
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
                SPDFExpect(attachment.bounds.size.width <= 440 && attachment.bounds.size.height <= 320,
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
            SPDFMarkdownPageFragment* firstRowFragment = SPDFFragmentForIndex(figurePlan, firstImageIndex);
            SPDFMarkdownPageFragment* secondRowFragment = SPDFFragmentForIndex(figurePlan, secondImageIndex);
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

        // Row width fitting. Two images at the default per-image caps (440
        // wide each after capping) cannot sit side by side within the row
        // budget, so the row scales both attachments down by ONE common
        // factor until the line fits; a badge strip of small images already
        // fits and keeps its natural sizes; a row that would need less than
        // the 0.45x floor keeps the floor and wraps instead.
        NSString* fitDirectory = SPDFCreateFixtureDirectory();
        SPDFWritePNG([fitDirectory stringByAppendingPathComponent:@"wide.png"], 960, 320);
        SPDFWritePNG([fitDirectory stringByAppendingPathComponent:@"badge.png"], 60, 20);
        NSMutableString* fitSource = [NSMutableString string];
        [fitSource appendString:@"![Wide left](wide.png)\n![Wide right](wide.png)\n\n"];
        [fitSource appendString:@"![B1](badge.png) ![B2](badge.png) ![B3](badge.png) "
                                 "![B4](badge.png) ![B5](badge.png)\n\n"];
        for (NSUInteger index = 0; index < 6; ++index)
            [fitSource appendFormat:@"![Wall %lu](wide.png)\n", (unsigned long)index];
        NSString* fitPath = [fitDirectory stringByAppendingPathComponent:@"fit.md"];
        [fitSource writeToFile:fitPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        error = nil;
        SPDFMarkdownDocument* fitDocument =
            [SPDFMarkdownDocument documentWithURL:[NSURL fileURLWithPath:fitPath]
                                          options:SPDFMarkdownRenderOptions.defaultOptions error:&error];
        SPDFExpect(fitDocument != nil && error == nil, @"row-fit document loads and renders");
        NSAttributedString* fitString = fitDocument.renderedDocument.attributedString;
        SPDFMarkdownPaginationPlan* fitPlan = [fitDocument paginationPlanForConfiguration:figureConfiguration];

        NSRange pairRow = [fitString.string rangeOfString:@"\uFFFC \uFFFC"];
        SPDFExpect(pairRow.location != NSNotFound, @"the two-image row keeps its side-by-side shape");
        if (pairRow.location != NSNotFound) {
            NSTextAttachment* pairLeft = [fitString attribute:NSAttachmentAttributeName
                                                      atIndex:pairRow.location
                                               effectiveRange:nil];
            NSTextAttachment* pairRight = [fitString attribute:NSAttachmentAttributeName
                                                       atIndex:pairRow.location + 2
                                                effectiveRange:nil];
            CGFloat pairFactor = pairLeft.bounds.size.width / 440.0;
            SPDFExpect(pairLeft != nil && pairRight != nil && pairFactor < 1.0 && pairFactor >= 0.45,
                       @"two cap-width row images scale below the cap but never below the 0.45x floor");
            SPDFExpect(pairLeft && pairRight &&
                           fabs(pairRight.bounds.size.width - pairLeft.bounds.size.width) < 0.001 &&
                           fabs(pairLeft.bounds.size.height - (440.0 / 3.0) * pairFactor) < 0.01 &&
                           fabs(pairRight.bounds.size.height - (440.0 / 3.0) * pairFactor) < 0.01,
                       @"both row attachments shrink by one common factor and keep their aspect ratio");
            CGFloat pairSpaceWidth =
                [[fitString attributedSubstringFromRange:NSMakeRange(pairRow.location + 1, 1)] size].width;
            SPDFExpect(pairLeft && pairRight &&
                           pairLeft.bounds.size.width + pairSpaceWidth + pairRight.bounds.size.width <=
                               440.0 + 0.5,
                       @"the fitted row's total width stays within the row budget");
            SPDFMarkdownPageFragment* pairFragment = SPDFFragmentForIndex(fitPlan, pairRow.location);
            SPDFMarkdownPageFragment* pairSecondFragment = SPDFFragmentForIndex(fitPlan, pairRow.location + 2);
            SPDFExpect(pairFragment != nil && pairFragment == pairSecondFragment,
                       @"the fitted pair shares one line fragment band instead of stacking");
            if (pairFragment && pairFragment == pairSecondFragment) {
                NSAttributedString* pairLine =
                    [fitString attributedSubstringFromRange:pairFragment.attributedRange];
                CTLineRef pairCTLine = SPDFMarkdownCreateFragmentLine(pairLine);
                CGFloat pairLineWidth = (CGFloat)CTLineGetTypographicBounds(pairCTLine, NULL, NULL, NULL) -
                                        (CGFloat)CTLineGetTrailingWhitespaceWidth(pairCTLine);
                CFRelease(pairCTLine);
                SPDFExpect(fabs(pairFragment.xOffset + pairLineWidth / 2 - printableWidth / 2) < 2.0,
                           @"the fitted pair still centers as a group within the printable width");
            }
            SPDFExpect(![fitString.string containsString:@"Wide left"] &&
                           ![fitString.string containsString:@"Wide right"],
                       @"the fitted row still shows no visible alt captions");
        }

        NSRange badgeRow = [fitString.string rangeOfString:@"\uFFFC \uFFFC \uFFFC \uFFFC \uFFFC"];
        SPDFExpect(badgeRow.location != NSNotFound, @"the five-badge row keeps its side-by-side shape");
        if (badgeRow.location != NSNotFound) {
            for (NSUInteger offset = 0; offset < 9; offset += 2) {
                NSTextAttachment* badge = [fitString attribute:NSAttachmentAttributeName
                                                       atIndex:badgeRow.location + offset
                                                effectiveRange:nil];
                SPDFExpect(badge != nil && fabs(badge.bounds.size.width - 60.0) < 0.001 &&
                               fabs(badge.bounds.size.height - 20.0) < 0.001,
                           @"a badge strip already under the budget keeps its natural sizes");
            }
        }

        NSRange wallRow = [fitString.string rangeOfString:@"\uFFFC \uFFFC \uFFFC \uFFFC \uFFFC \uFFFC"];
        SPDFExpect(wallRow.location != NSNotFound, @"the six-image row renders as one row paragraph");
        if (wallRow.location != NSNotFound) {
            for (NSUInteger offset = 0; offset < 11; offset += 2) {
                NSTextAttachment* wall = [fitString attribute:NSAttachmentAttributeName
                                                      atIndex:wallRow.location + offset
                                               effectiveRange:nil];
                SPDFExpect(wall != nil && fabs(wall.bounds.size.width - 440.0 * 0.45) < 0.01 &&
                               fabs(wall.bounds.size.height - (440.0 / 3.0) * 0.45) < 0.01,
                           @"a row that cannot fit even at the floor stops shrinking at 0.45x");
            }
            SPDFMarkdownPageFragment* wallFirst = SPDFFragmentForIndex(fitPlan, wallRow.location);
            SPDFMarkdownPageFragment* wallLast = SPDFFragmentForIndex(fitPlan, wallRow.location + 10);
            SPDFExpect(wallFirst != nil && wallLast != nil && wallFirst != wallLast,
                       @"a floored row wraps onto further lines instead of overflowing the page");
        }
    }
    return SPDFFinishTests(@"SPDFMarkdownImageFigureTests");
}
