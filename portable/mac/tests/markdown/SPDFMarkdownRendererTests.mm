#import "SPDFMarkdownTestSupport.h"

#import "../../markdown/SPDFMarkdownDocument.h"

static BOOL SPDFColorMatchesHex(NSColor* color, unsigned int hex) {
    NSColor* sRGB = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!sRGB) return NO;
    return fabs(sRGB.redComponent - ((hex >> 16) & 0xff) / 255.0) < 0.002 &&
           fabs(sRGB.greenComponent - ((hex >> 8) & 0xff) / 255.0) < 0.002 &&
           fabs(sRGB.blueComponent - (hex & 0xff) / 255.0) < 0.002;
}

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
    [source appendString:@"![Budgeted out](second.png)\n"];
    [source writeToFile:[directory stringByAppendingPathComponent:@"image.md"]
             atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"image.md"]];
}

int main(void) {
    @autoreleasepool {
        NSError* error = nil;
        SPDFMarkdownDocument* document = [SPDFMarkdownDocument documentWithURL:SPDFFixtureURL(@"commonmark-gfm.md")
                                                                        options:nil error:&error];
        SPDFExpect(document != nil && error == nil, @"document facade loads and renders");
        NSString* canonical = document.renderedDocument.attributedString.string;
        SPDFExpect([canonical containsString:@"☑ Finished task"], @"canonical text includes task markers");
        SPDFExpect([canonical containsString:@"Alpha\t42"], @"canonical text includes table separators");
        SPDFExpect([canonical containsString:@"[Image: Local diagram]"], @"missing image has canonical placeholder");
        SPDFExpectSearchCorrespondence(document, @"Finished task");
        SPDFExpectSearchCorrespondence(document, @"Alpha");
        SPDFExpectSearchCorrespondence(document, @"Local diagram");
        NSRange tableText = [canonical rangeOfString:@"Alpha\t42"];
        NSParagraphStyle* tableStyle = [document.renderedDocument.attributedString
            attribute:NSParagraphStyleAttributeName atIndex:tableText.location effectiveRange:nil];
        SPDFExpect(tableStyle.tabStops.count == 2 && tableStyle.tabStops.firstObject.alignment == NSTextAlignmentLeft &&
                       tableStyle.tabStops.lastObject.alignment == NSTextAlignmentRight,
                   @"rendered table gives every column an explicit alignment tab");
        for (SPDFMarkdownRenderedHeading* heading in document.renderedDocument.headings) {
            NSString* selected = [[canonical substringWithRange:heading.attributedRange]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            SPDFExpect([selected isEqualToString:heading.title], @"heading index uses canonical coordinates");
        }

        SPDFMarkdownDocument* obsidian = [SPDFMarkdownDocument documentWithURL:SPDFFixtureURL(@"obsidian.md")
                                                                        options:nil error:&error];
        SPDFExpectSearchCorrespondence(obsidian, @"Release gate");
        SPDFExpect([[obsidian.renderedDocument.attributedString.string
                        componentsSeparatedByString:@"Release gate"] count] == 2,
                   @"callout title is rendered exactly once");
        BOOL calloutRecorded = NO;
        for (SPDFMarkdownRenderedBlock* block in obsidian.renderedDocument.renderedBlocks)
            if (block.kind == SPDFMarkdownBlockKindCallout) calloutRecorded = YES;
        SPDFExpect(calloutRecorded, @"callout title participates in layout and pagination");

        NSRange fencedCode = [canonical rangeOfString:@"let greeting"];
        SPDFExpect([document.renderedDocument.attributedString attribute:NSBackgroundColorAttributeName
                                                                 atIndex:fencedCode.location
                                                          effectiveRange:nil] == nil,
                   @"fenced code paints no per-character background; the code box is a page decoration");
        NSParagraphStyle* codeStyle = [document.renderedDocument.attributedString
            attribute:NSParagraphStyleAttributeName atIndex:fencedCode.location effectiveRange:nil];
        SPDFExpect(codeStyle.paragraphSpacing == 0 && codeStyle.paragraphSpacingBefore == 0 &&
                       fabs(codeStyle.lineSpacing - 2) < 0.001,
                   @"fenced code lines flow as one continuous block without inter-line gaps");
        SPDFExpect(fabs(codeStyle.firstLineHeadIndent - 12) < 0.001 && fabs(codeStyle.headIndent - 12) < 0.001 &&
                       fabs(codeStyle.tailIndent - -12) < 0.001,
                   @"fenced code text is inset 12pt within its box");
        NSRange inlineCode = [canonical rangeOfString:@"inline code"];
        SPDFExpect([document.renderedDocument.attributedString attribute:NSBackgroundColorAttributeName
                                                                 atIndex:inlineCode.location
                                                          effectiveRange:nil] != nil,
                   @"inline code spans keep their subtle chip background");
        NSRange h2 = [canonical rangeOfString:@"Lists and tables"];
        NSParagraphStyle* h2Style = [document.renderedDocument.attributedString
            attribute:NSParagraphStyleAttributeName atIndex:h2.location effectiveRange:nil];
        SPDFExpect(fabs(h2Style.paragraphSpacingBefore - 22) < 0.001 && fabs(h2Style.paragraphSpacing - 10) < 0.001,
                   @"H1/H2 headings get 22pt leading and 10pt trailing space");
        NSFont* h2Font = [document.renderedDocument.attributedString attribute:NSFontAttributeName
                                                                        atIndex:h2.location
                                                                 effectiveRange:nil];
        SPDFExpect(fabs(h2Font.pointSize - 22.5) < 0.01 &&
                       [h2Font isEqual:[NSFont systemFontOfSize:h2Font.pointSize weight:NSFontWeightSemibold]],
                   @"H2 renders at 1.5em in semibold rather than full bold");
        NSRange h1 = [canonical rangeOfString:@"Shenzhen PDF Markdown"];
        NSFont* h1Font = [document.renderedDocument.attributedString attribute:NSFontAttributeName
                                                                        atIndex:h1.location
                                                                 effectiveRange:nil];
        SPDFExpect(fabs(h1Font.pointSize - 26.25) < 0.01, @"H1 renders at 1.75em of the body size");

        NSRange bodyRun = [canonical rangeOfString:@"This is"];
        NSColor* bodyColor = [document.renderedDocument.attributedString attribute:NSForegroundColorAttributeName
                                                                            atIndex:bodyRun.location
                                                                     effectiveRange:nil];
        SPDFExpect(SPDFColorMatchesHex(bodyColor, 0x1F2328),
                   @"body text uses the concrete near-black reading color, never pure black");
        NSColor* h2Color = [document.renderedDocument.attributedString attribute:NSForegroundColorAttributeName
                                                                          atIndex:h2.location
                                                                   effectiveRange:nil];
        SPDFExpect(SPDFColorMatchesHex(h2Color, 0x1F2328), @"heading text shares the body near-black");
        NSRange linkRun = [canonical rangeOfString:@"safe link"];
        NSColor* linkColor = [document.renderedDocument.attributedString attribute:NSForegroundColorAttributeName
                                                                            atIndex:linkRun.location
                                                                     effectiveRange:nil];
        SPDFExpect(SPDFColorMatchesHex(linkColor, 0x0969DA), @"links use the concrete accent blue");
        NSString* obsidianText = obsidian.renderedDocument.attributedString.string;
        NSRange quoteRun = [obsidianText rangeOfString:@"A normal block quote"];
        NSColor* quoteTextColor = [obsidian.renderedDocument.attributedString
            attribute:NSForegroundColorAttributeName atIndex:quoteRun.location effectiveRange:nil];
        SPDFExpect(SPDFColorMatchesHex(quoteTextColor, 0x59636E),
                   @"block quote prose reads in the muted secondary color");

        NSUInteger unknownBlock = document.model.codeFences.lastObject.blockIndex;
        [document setLanguageIdentifier:@"python" forCodeBlock:unknownBlock];
        SPDFMarkdownRenderedBlock* unknown = [document.renderedDocument renderedBlockWithIndex:unknownBlock];
        NSString* language = [document.renderedDocument.attributedString
            attribute:SPDFMarkdownCodeLanguageAttribute atIndex:unknown.attributedRange.location effectiveRange:nil];
        SPDFExpect([language isEqualToString:@"python"], @"picker override re-renders an untagged fence");

        SPDFMarkdownRenderOptions* imageOptions = SPDFMarkdownRenderOptions.defaultOptions;
        imageOptions.maximumDecodedImagePixels = 8;
        SPDFMarkdownDocument* imageDocument = [SPDFMarkdownDocument documentWithURL:SPDFCreateImageDocument()
                                                                             options:imageOptions error:&error];
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
        SPDFExpect(attachmentCount == 200 && allAttachmentsShared,
                   @"repeated image references reuse one decoded image rather than multiplying memory");
        SPDFExpect([imageDocument.renderedDocument.attributedString.string containsString:@"[Image: Budgeted out]"],
                   @"an image beyond the aggregate pixel budget becomes a graceful placeholder");
        SPDFExpectSearchCorrespondence(imageDocument, @"Local pixels");

        SPDFMarkdownParser* parser = [SPDFMarkdownParser new];
        SPDFMarkdownDocumentModel* centeredTableModel =
            [parser parseString:@"| center | right |\n| :---: | ---: |\n| alpha | beta |\n"
                      sourceURL:nil error:&error];
        SPDFMarkdownDocument* centeredTable = [[SPDFMarkdownDocument alloc]
            initWithModel:centeredTableModel options:SPDFMarkdownRenderOptions.defaultOptions];
        NSRange centeredRow = [centeredTable.renderedDocument.attributedString.string rangeOfString:@"\talpha\tbeta"];
        NSParagraphStyle* centeredStyle = [centeredTable.renderedDocument.attributedString
            attribute:NSParagraphStyleAttributeName atIndex:centeredRow.location effectiveRange:nil];
        SPDFExpect(centeredStyle.alignment == NSTextAlignmentLeft && centeredStyle.tabStops.count == 2 &&
                       centeredStyle.tabStops.firstObject.alignment == NSTextAlignmentCenter &&
                       centeredStyle.tabStops.lastObject.alignment == NSTextAlignmentRight,
                   @"first-column alignment is scoped to its own tab instead of the whole row");

        SPDFMarkdownDocumentModel* breakModel =
            [parser parseString:@"Above\n\n***\n\nBelow\n\n###### Tiny heading\n" sourceURL:nil error:&error];
        SPDFMarkdownDocument* breakDocument = [[SPDFMarkdownDocument alloc]
            initWithModel:breakModel options:SPDFMarkdownRenderOptions.defaultOptions];
        NSString* breakText = breakDocument.renderedDocument.attributedString.string;
        SPDFExpect(![breakText containsString:@"─"],
                   @"a thematic break reserves a blank line; the visible rule is a page decoration");
        SPDFMarkdownRenderedBlock* breakBlock = nil;
        for (SPDFMarkdownRenderedBlock* block in breakDocument.renderedDocument.renderedBlocks)
            if (block.kind == SPDFMarkdownBlockKindThematicBreak) breakBlock = block;
        SPDFExpect(breakBlock != nil && breakBlock.attributedRange.length == 1,
                   @"the thematic break stays a recorded block so pagination can place its rule");
        NSRange h6 = [breakText rangeOfString:@"Tiny heading"];
        NSFont* h6Font = [breakDocument.renderedDocument.attributedString attribute:NSFontAttributeName
                                                                             atIndex:h6.location
                                                                      effectiveRange:nil];
        NSColor* h6Color = [breakDocument.renderedDocument.attributedString
            attribute:NSForegroundColorAttributeName atIndex:h6.location effectiveRange:nil];
        SPDFExpect(fabs(h6Font.pointSize - 13.5) < 0.01 && SPDFColorMatchesHex(h6Color, 0x59636E),
                   @"H6 drops below body size and goes muted, caption-style");

        NSString* listSource = @"- first paragraph\n\n  - nested before\n\n  after nested\n\n  ```swift\n  let x = 1\n  ```\n";
        SPDFMarkdownDocumentModel* nestedModel = [parser parseString:listSource sourceURL:nil error:&error];
        SPDFMarkdownDocument* nested = [[SPDFMarkdownDocument alloc] initWithModel:nestedModel
                                                                            options:SPDFMarkdownRenderOptions.defaultOptions];
        NSString* nestedText = nested.renderedDocument.attributedString.string;
        NSRange firstParagraph = [nestedText rangeOfString:@"first paragraph"];
        NSRange nestedItem = [nestedText rangeOfString:@"nested before"];
        NSRange afterNested = [nestedText rangeOfString:@"after nested"];
        NSRange nestedCode = [nestedText rangeOfString:@"let x = 1"];
        SPDFExpect(firstParagraph.location < nestedItem.location && nestedItem.location < afterNested.location &&
                       afterNested.location < nestedCode.location,
                   @"interleaved list paragraphs, nested lists, following paragraphs, and code preserve source order");
        SPDFExpect([nestedText containsString:@"• nested before"], @"nested list content remains recursively rendered");
        NSRange secondParagraph = afterNested;
        NSParagraphStyle* secondParagraphStyle = [nested.renderedDocument.attributedString
            attribute:NSParagraphStyleAttributeName atIndex:secondParagraph.location effectiveRange:nil];
        SPDFExpect(secondParagraphStyle.headIndent >= 22,
                   @"continuation paragraphs align inside the list item rather than under its marker");
        NSString* nestedLanguage = [nested.renderedDocument.attributedString
            attribute:SPDFMarkdownCodeLanguageAttribute atIndex:nestedCode.location effectiveRange:nil];
        SPDFExpect([nestedLanguage isEqualToString:@"swift"], @"fenced code inside a list keeps code styling");
        NSMutableSet* depths = [NSMutableSet set];
        NSMutableDictionary<NSNumber*, NSNumber*>* indents = [NSMutableDictionary dictionary];
        for (SPDFMarkdownRenderedBlock* block in nested.renderedDocument.renderedBlocks)
            if (block.kind == SPDFMarkdownBlockKindListItem) {
                [depths addObject:@(block.depth)];
                NSParagraphStyle* style = [nested.renderedDocument.attributedString
                    attribute:NSParagraphStyleAttributeName atIndex:block.attributedRange.location effectiveRange:nil];
                indents[@(block.depth)] = @(style.headIndent);
            }
        SPDFExpect([depths containsObject:@0] && [depths containsObject:@1], @"nested list indentation is stable");
        SPDFExpect([indents[@1] doubleValue] > [indents[@0] doubleValue],
                   @"nested list paragraph indentation increases by depth");

        SPDFMarkdownRenderOptions* scaledOptions = SPDFMarkdownRenderOptions.defaultOptions;
        scaledOptions.fontScale = 1.5;
        SPDFMarkdownDocument* scaled = [SPDFMarkdownDocument documentWithURL:SPDFFixtureURL(@"commonmark-gfm.md")
                                                                     options:scaledOptions
                                                                       error:&error];
        NSString* scaledText = scaled.renderedDocument.attributedString.string;
        NSRange scaledBody = [scaledText rangeOfString:@"First item"];
        NSFont* scaledBodyFont = [scaled.renderedDocument.attributedString attribute:NSFontAttributeName
                                                                             atIndex:scaledBody.location
                                                                      effectiveRange:nil];
        NSRange scaledCode = [scaledText rangeOfString:@"let greeting"];
        NSFont* scaledCodeFont = [scaled.renderedDocument.attributedString attribute:NSFontAttributeName
                                                                             atIndex:scaledCode.location
                                                                      effectiveRange:nil];
        SPDFExpect(fabs(scaledBodyFont.pointSize - 22.5) < 0.01 && fabs(scaledCodeFont.pointSize - 19.5) < 0.01,
                   @"fontScale multiplies body and code font sizes in the attributed output");
        NSRange scaledParagraph = [scaledText rangeOfString:@"This is"];
        NSParagraphStyle* scaledBodyStyle = [scaled.renderedDocument.attributedString
            attribute:NSParagraphStyleAttributeName atIndex:scaledParagraph.location effectiveRange:nil];
        SPDFExpect(fabs(scaledBodyStyle.lineSpacing - 6) < 0.01 && fabs(scaledBodyStyle.paragraphSpacing - 18) < 0.01,
                   @"fontScale multiplies line and paragraph spacing");
        NSParagraphStyle* scaledCodeStyle = [scaled.renderedDocument.attributedString
            attribute:NSParagraphStyleAttributeName atIndex:scaledCode.location effectiveRange:nil];
        SPDFExpect(fabs(scaledCodeStyle.firstLineHeadIndent - 12) < 0.001,
                   @"indent constants stay unscaled under fontScale");
        scaledOptions.fontScale = 99;
        SPDFExpect(fabs(scaledOptions.fontScale - 3.0) < 0.001, @"fontScale clamps to at most 3.0");
        scaledOptions.fontScale = 0.1;
        SPDFExpect(fabs(scaledOptions.fontScale - 0.5) < 0.001, @"fontScale clamps to at least 0.5");
        scaledOptions.fontScale = 1.5;
        SPDFMarkdownRenderOptions* copiedOptions = [scaledOptions copy];
        SPDFExpect(fabs(copiedOptions.fontScale - 1.5) < 0.001, @"copyWithZone preserves fontScale");
        SPDFExpect(fabs(SPDFMarkdownRenderOptions.defaultOptions.fontScale - 1.0) < 0.001 &&
                       fabs([SPDFMarkdownRenderOptions new].fontScale - 1.0) < 0.001,
                   @"fontScale defaults to 1.0");

        NSTextView* view = [document newSelectableTextView];
        SPDFExpect(view.isSelectable && !view.isEditable && view.importsGraphics,
                   @"native view is selectable, read-only, and attachment-capable");
    }
    return SPDFFinishTests(@"SPDFMarkdownRendererTests");
}
