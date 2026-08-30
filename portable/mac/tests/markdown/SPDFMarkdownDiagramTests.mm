#import "SPDFMarkdownTestSupport.h"

#import "../../markdown/SPDFMarkdownDiagram.h"
#import "../../markdown/SPDFMarkdownDocument.h"

// The native diagram engine: every supported fence type renders to a bounded
// bitmap figure, every unsupported/malformed/over-budget fence degrades to the
// ordinary code box, the work counter proves a diagram-free document does zero
// diagram work, and the session cache proves a rerender does not re-rasterize.

static const CGFloat kSPDFDiagramTestWidth = 440;

static SPDFMarkdownDiagramImage* SPDFRenderDiagram(NSString* language, NSString* source) {
    return SPDFMarkdownDiagramRender(language, source, kSPDFDiagramTestWidth, 1.0,
                                     SPDFMarkdownThemeVariantLight, nil);
}

// A rendered diagram is well formed: non-empty logical size, inside the content
// width budget, and a 2x bitmap inside the raster budget on both axes.
static void SPDFExpectWellFormedDiagram(SPDFMarkdownDiagramImage* diagram, NSString* what) {
    if (!diagram) {
        SPDFExpect(NO, [what stringByAppendingString:@" renders a diagram"]);
        return;
    }
    SPDFExpect(diagram.logicalSize.width > 0 && diagram.logicalSize.height > 0,
               [what stringByAppendingString:@" has a positive logical size"]);
    SPDFExpect(diagram.logicalSize.width <= kSPDFDiagramTestWidth + 0.5,
               [what stringByAppendingString:@" fits the content width budget"]);
    NSImageRep* rep = diagram.image.representations.firstObject;
    SPDFExpect(rep != nil && rep.pixelsWide <= (NSInteger)SPDFMarkdownDiagramMaximumRasterDimension &&
                   rep.pixelsHigh <= (NSInteger)SPDFMarkdownDiagramMaximumRasterDimension,
               [what stringByAppendingString:@" stays inside the raster budget"]);
    // The bitmap is 2x the diagram's NATURAL size; a diagram wider than the
    // content budget keeps those pixels and is drawn into the smaller
    // fitted bounds, so it is never under-resolved for its logical size.
    SPDFExpect(rep != nil && (CGFloat)rep.pixelsWide >= diagram.logicalSize.width * 2 - 2.0 &&
                   (CGFloat)rep.pixelsHigh >= diagram.logicalSize.height * 2 - 2.0,
               [what stringByAppendingString:@" rasterizes at no less than 2x its logical size"]);
}

static NSString* SPDFOverBudgetFlowchart(void) {
    NSMutableString* source = [NSMutableString stringWithString:@"graph TD\n"];
    for (NSUInteger index = 0; index < 260; ++index)
        [source appendFormat:@"  n%lu --> n%lu\n", (unsigned long)index, (unsigned long)(index + 1)];
    return source;
}

static SPDFMarkdownDocument* SPDFDocumentForMarkdown(NSString* markdown, SPDFMarkdownRenderOptions* options) {
    NSError* error = nil;
    SPDFMarkdownDocumentModel* model = [[SPDFMarkdownParser new] parseString:markdown sourceURL:nil error:&error];
    return model ? [[SPDFMarkdownDocument alloc] initWithModel:model options:options] : nil;
}

int main(void) {
    @autoreleasepool {
        // --- Language classification is O(1) and total ----------------------
        SPDFExpect(SPDFMarkdownDiagramIsDiagramLanguage(@"mermaid") &&
                       SPDFMarkdownDiagramIsDiagramLanguage(@"Mermaid") &&
                       SPDFMarkdownDiagramIsDiagramLanguage(@"sequence") &&
                       SPDFMarkdownDiagramIsDiagramLanguage(@"flow"),
                   @"mermaid / sequence / flow are diagram fences, case-insensitively");
        SPDFExpect(!SPDFMarkdownDiagramIsDiagramLanguage(@"swift") &&
                       !SPDFMarkdownDiagramIsDiagramLanguage(@"") &&
                       !SPDFMarkdownDiagramIsDiagramLanguage(nil) &&
                       !SPDFMarkdownDiagramIsDiagramLanguage(@"mermaidish"),
                   @"ordinary code fences are not diagram fences");

        // --- Per-type parse + render smoke ---------------------------------
        SPDFExpectWellFormedDiagram(
            SPDFRenderDiagram(@"mermaid",
                              @"graph TD\n"
                              @"  A[Start] --> B{Ready?}\n"
                              @"  B -- yes --> C([Ship it])\n"
                              @"  B -- no --> D((Wait))\n"
                              @"  C --> E[[Report]]\n"
                              @"  D -.-> B\n"),
            @"mermaid flowchart with shapes and labelled edges");
        SPDFExpectWellFormedDiagram(SPDFRenderDiagram(@"mermaid",
                                                      @"flowchart LR\n"
                                                      @"  A[Left] --> B[Right]\n"),
                                    @"mermaid flowchart LR");
        SPDFExpectWellFormedDiagram(SPDFRenderDiagram(@"mermaid",
                                                      @"sequenceDiagram\n"
                                                      @"  participant A as Reader\n"
                                                      @"  participant B as Renderer\n"
                                                      @"  A->>B: open document\n"
                                                      @"  Note right of B: parses once\n"
                                                      @"  alt cached\n"
                                                      @"    B-->>A: reuse raster\n"
                                                      @"  else cold\n"
                                                      @"    B-->>A: rasterize\n"
                                                      @"  end\n"),
                                    @"mermaid sequenceDiagram");
        SPDFExpectWellFormedDiagram(SPDFRenderDiagram(@"mermaid",
                                                      @"pie title Fence types\n"
                                                      @"  \"flowchart\" : 45\n"
                                                      @"  \"sequence\" : 30\n"
                                                      @"  \"other\" : 25\n"),
                                    @"mermaid pie");
        SPDFExpectWellFormedDiagram(SPDFRenderDiagram(@"mermaid",
                                                      @"stateDiagram-v2\n"
                                                      @"  [*] --> Idle\n"
                                                      @"  Idle --> Parsing : fence seen\n"
                                                      @"  Parsing --> Drawn\n"
                                                      @"  Drawn --> [*]\n"),
                                    @"mermaid stateDiagram-v2");
        SPDFExpectWellFormedDiagram(SPDFRenderDiagram(@"mermaid",
                                                      @"classDiagram\n"
                                                      @"  class Renderer {\n"
                                                      @"    +NSSize logicalSize\n"
                                                      @"    +render()\n"
                                                      @"  }\n"
                                                      @"  Renderer <|-- GraphRenderer\n"
                                                      @"  Renderer o-- Cache : reuses\n"),
                                    @"mermaid classDiagram");
        SPDFExpectWellFormedDiagram(SPDFRenderDiagram(@"mermaid",
                                                      @"gantt\n"
                                                      @"  title Diagram engine\n"
                                                      @"  dateFormat YYYY-MM-DD\n"
                                                      @"  section Parsing\n"
                                                      @"    Grammar : done, g1, 2026-01-01, 10d\n"
                                                      @"    Layout : active, after g1, 2w\n"
                                                      @"  section Raster\n"
                                                      @"    Drawing : crit, 2026-02-01, 2026-02-20\n"),
                                    @"mermaid gantt");
        SPDFExpectWellFormedDiagram(SPDFRenderDiagram(@"sequence",
                                                      @"Title: js-sequence\n"
                                                      @"Alice->Bob: hello\n"
                                                      @"Bob-->Alice: hi back\n"
                                                      @"Note over Alice,Bob: done\n"),
                                    @"js-sequence `sequence` fence");
        SPDFExpectWellFormedDiagram(SPDFRenderDiagram(@"flow",
                                                      @"st=>start: Begin\n"
                                                      @"op=>operation: Parse fence\n"
                                                      @"cond=>condition: Supported?\n"
                                                      @"io=>inputoutput: Code box\n"
                                                      @"e=>end: Figure\n"
                                                      @"st->op->cond\n"
                                                      @"cond(yes)->e\n"
                                                      @"cond(no)->io\n"),
                                    @"flowchart.js `flow` fence");

        // --- Degradation: every failure mode returns nil ---------------------
        SPDFExpect(SPDFRenderDiagram(@"mermaid", @"graph XX\n  A --> B\n") == nil,
                   @"an unknown flow direction degrades to the code box");
        SPDFExpect(SPDFRenderDiagram(@"mermaid", @"erDiagram\n  A ||--o{ B : has\n") == nil,
                   @"an unimplemented mermaid sub-type degrades to the code box");
        SPDFExpect(SPDFRenderDiagram(@"mermaid", @"not a diagram at all\njust prose\n") == nil,
                   @"garbage in a mermaid fence degrades to the code box");
        SPDFExpect(SPDFRenderDiagram(@"mermaid", @"graph TD\n  A[unterminated --> B\n") == nil,
                   @"a syntax error degrades the whole diagram");
        SPDFExpect(SPDFRenderDiagram(@"mermaid", @"sequenceDiagram\n  A wanders off\n") == nil,
                   @"a malformed sequence line degrades the whole diagram");
        SPDFExpect(SPDFRenderDiagram(@"mermaid", @"pie\n  \"only\" : not-a-number\n") == nil,
                   @"a non-numeric pie value degrades the whole diagram");
        SPDFExpect(SPDFRenderDiagram(@"flow", @"a->b\n") == nil,
                   @"a flow fence referencing undefined nodes degrades");
        SPDFExpect(SPDFRenderDiagram(@"mermaid", SPDFOverBudgetFlowchart()) == nil,
                   @"a graph beyond the 200-node budget degrades to the code box");
        SPDFExpect(SPDFRenderDiagram(@"mermaid", @"") == nil && SPDFRenderDiagram(@"swift", @"let x = 1\n") == nil,
                   @"an empty fence and a non-diagram language both render nothing");

        // --- Laziness: a diagram-free document does zero diagram work --------
        SPDFMarkdownDiagramResetWorkCount();
        SPDFExpect(SPDFMarkdownDiagramWorkCount() == 0, @"the work counter resets");
        NSString* plainMarkdown = @"# Title\n\nSome prose with `inline code`.\n\n"
                                  @"```swift\nlet answer = 42\n```\n\n"
                                  @"| a | b |\n| --- | --- |\n| 1 | 2 |\n\n"
                                  @"> a quote\n\n- item one\n- item two\n";
        SPDFMarkdownDocument* plain =
            SPDFDocumentForMarkdown(plainMarkdown, SPDFMarkdownRenderOptions.defaultOptions);
        SPDFExpect(plain != nil, @"the diagram-free document renders");
        SPDFExpect(SPDFMarkdownDiagramWorkCount() == 0,
                   @"a document with no diagram fence performs ZERO diagram work");
        SPDFExpect([plain.renderedDocument.attributedString.string containsString:@"let answer = 42"],
                   @"an ordinary code fence still renders its source text");

        NSString* diagramMarkdown = @"# Flow\n\n```mermaid\ngraph TD\n  A[Start] --> B[Stop]\n```\n\nAfter.\n";
        SPDFMarkdownDocument* withDiagram =
            SPDFDocumentForMarkdown(diagramMarkdown, SPDFMarkdownRenderOptions.defaultOptions);
        SPDFExpect(withDiagram != nil && SPDFMarkdownDiagramWorkCount() == 1,
                   @"a document WITH a diagram fence performs exactly one unit of diagram work");

        // --- Cache: one session cache, one raster per distinct key -----------
        SPDFMarkdownDiagramResetWorkCount();
        SPDFMarkdownDiagramCache* cache = [SPDFMarkdownDiagramCache new];
        NSString* cachedSource = @"graph LR\n  A[One] --> B[Two]\n";
        SPDFMarkdownDiagramImage* first = SPDFMarkdownDiagramRender(@"mermaid", cachedSource, kSPDFDiagramTestWidth,
                                                                    1.0, SPDFMarkdownThemeVariantLight, cache);
        SPDFMarkdownDiagramImage* second = SPDFMarkdownDiagramRender(@"mermaid", cachedSource, kSPDFDiagramTestWidth,
                                                                     1.0, SPDFMarkdownThemeVariantLight, cache);
        SPDFExpect(first != nil && second == first && SPDFMarkdownDiagramWorkCount() == 1,
                   @"a second render of the same fence hits the cache instead of re-rasterizing");
        SPDFMarkdownDiagramImage* dark = SPDFMarkdownDiagramRender(@"mermaid", cachedSource, kSPDFDiagramTestWidth,
                                                                   1.0, SPDFMarkdownThemeVariantDark, cache);
        SPDFExpect(dark != nil && SPDFMarkdownDiagramWorkCount() == 2,
                   @"a theme switch is a different cache key and re-rasterizes");
        SPDFMarkdownDiagramRender(@"mermaid", cachedSource, kSPDFDiagramTestWidth, 1.5,
                                  SPDFMarkdownThemeVariantLight, cache);
        SPDFExpect(SPDFMarkdownDiagramWorkCount() == 3, @"a text-size change re-rasterizes too");
        // Negative caching: a malformed fence is parsed once, never again.
        SPDFMarkdownDiagramResetWorkCount();
        NSString* broken = @"graph TD\n  A[bad --> B\n";
        SPDFExpect(SPDFMarkdownDiagramRender(@"mermaid", broken, kSPDFDiagramTestWidth, 1.0,
                                             SPDFMarkdownThemeVariantLight, cache) == nil &&
                       SPDFMarkdownDiagramRender(@"mermaid", broken, kSPDFDiagramTestWidth, 1.0,
                                                 SPDFMarkdownThemeVariantLight, cache) == nil &&
                       SPDFMarkdownDiagramWorkCount() == 1,
                   @"a failed parse is cached too, so a rerender never re-parses it");
        SPDFExpect(cache.count > 0, @"the cache holds its entries");
        [cache removeAllEntries];
        SPDFExpect(cache.count == 0, @"the cache can be emptied");

        // --- Theme: the dark variant produces different pixels ---------------
        SPDFMarkdownDiagramImage* light = SPDFMarkdownDiagramRender(
            @"mermaid", cachedSource, kSPDFDiagramTestWidth, 1.0, SPDFMarkdownThemeVariantLight, nil);
        SPDFMarkdownDiagramImage* darkAgain = SPDFMarkdownDiagramRender(
            @"mermaid", cachedSource, kSPDFDiagramTestWidth, 1.0, SPDFMarkdownThemeVariantDark, nil);
        SPDFExpect(light != nil && darkAgain != nil &&
                       NSEqualSizes(light.logicalSize, darkAgain.logicalSize),
                   @"the two themes lay a diagram out identically");
        NSBitmapImageRep* lightRep = (NSBitmapImageRep*)light.image.representations.firstObject;
        NSBitmapImageRep* darkRep = (NSBitmapImageRep*)darkAgain.image.representations.firstObject;
        SPDFExpect([lightRep isKindOfClass:NSBitmapImageRep.class] &&
                       [darkRep isKindOfClass:NSBitmapImageRep.class],
                   @"a diagram is bitmap-backed");
        NSColor* lightPaper = [[lightRep colorAtX:2 y:2] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        NSColor* darkPaper = [[darkRep colorAtX:2 y:2] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        SPDFExpect(lightPaper.brightnessComponent - darkPaper.brightnessComponent > 0.3,
                   @"the dark theme paints a dark paper where the light theme paints a light one");
        SPDFExpect(![light.image.TIFFRepresentation isEqualToData:darkAgain.image.TIFFRepresentation],
                   @"the two themes rasterize to different pixels");

        // --- End to end through the full renderer ----------------------------
        NSAttributedString* diagramString = withDiagram.renderedDocument.attributedString;
        SPDFExpect(![diagramString.string containsString:@"graph TD"] &&
                       ![diagramString.string containsString:@"A[Start]"],
                   @"a rendered diagram keeps its fence source OUT of the canonical string");
        SPDFExpect([diagramString.string containsString:@"￼"],
                   @"a rendered diagram contributes an attachment character");
        NSRange attachment = [diagramString.string rangeOfString:@"￼"];
        NSTextAttachment* diagramAttachment = [diagramString attribute:NSAttachmentAttributeName
                                                               atIndex:attachment.location
                                                        effectiveRange:nil];
        SPDFExpect(diagramAttachment.image != nil && diagramAttachment.bounds.size.width > 0,
                   @"the attachment carries the rasterized diagram at its reserved bounds");
        NSNumber* layoutRole = [diagramString attribute:@"SPDFMarkdownImageLayout"
                                                atIndex:attachment.location
                                         effectiveRange:nil];
        SPDFExpect(layoutRole.integerValue == 1, @"the diagram attachment carries the centered-figure role");
        NSParagraphStyle* figureStyle = [diagramString attribute:NSParagraphStyleAttributeName
                                                         atIndex:attachment.location
                                                  effectiveRange:nil];
        SPDFExpect(figureStyle.alignment == NSTextAlignmentCenter, @"the diagram figure paragraph is centered");
        SPDFMarkdownRenderedBlock* diagramBlock = nil;
        for (SPDFMarkdownRenderedBlock* block in withDiagram.renderedDocument.renderedBlocks)
            if (NSLocationInRange(attachment.location, block.attributedRange)) diagramBlock = block;
        SPDFExpect(diagramBlock != nil && diagramBlock.kind == SPDFMarkdownBlockKindParagraph,
                   @"a diagram fence records as a PARAGRAPH so no code box or language pill is planned");
        SPDFExpect([diagramString attribute:SPDFMarkdownCodeLanguageAttribute atIndex:attachment.location
                             effectiveRange:nil] == nil,
                   @"a diagram figure carries no code-language attribute");

        // Degradation is preserved end to end: an invalid mermaid fence still
        // renders as ordinary, canonical, searchable code text.
        SPDFMarkdownDocument* invalid = SPDFDocumentForMarkdown(
            @"```mermaid\nerDiagram\n  CUSTOMER ||--o{ ORDER : places\n```\n",
            SPDFMarkdownRenderOptions.defaultOptions);
        NSString* invalidText = invalid.renderedDocument.attributedString.string;
        SPDFExpect([invalidText containsString:@"erDiagram"] &&
                       [invalidText containsString:@"CUSTOMER ||--o{ ORDER : places"],
                   @"an unsupported mermaid fence still renders its code text canonically");
        SPDFExpect(![invalidText containsString:@"￼"],
                   @"an unsupported mermaid fence emits no attachment");
        SPDFMarkdownRenderedBlock* invalidBlock = invalid.renderedDocument.renderedBlocks.firstObject;
        SPDFExpect(invalidBlock.kind == SPDFMarkdownBlockKindCode,
                   @"an unsupported mermaid fence stays a recorded CODE block");

        // The options carry the shared cache by reference through a copy, so
        // the renderer's internal copies all hit the same session store.
        SPDFMarkdownRenderOptions* options = SPDFMarkdownRenderOptions.defaultOptions;
        SPDFExpect(options.diagramCache == nil, @"the diagram cache defaults to nil (rendering still works)");
        SPDFMarkdownDiagramCache* sessionCache = [SPDFMarkdownDiagramCache new];
        options.diagramCache = sessionCache;
        SPDFMarkdownRenderOptions* copiedOptions = [options copy];
        SPDFExpect(copiedOptions.diagramCache == sessionCache,
                   @"the shared diagram cache survives a copy BY REFERENCE");

        SPDFMarkdownDiagramResetWorkCount();
        SPDFMarkdownRenderOptions* cachedOptions = SPDFMarkdownRenderOptions.defaultOptions;
        cachedOptions.diagramCache = [SPDFMarkdownDiagramCache new];
        SPDFDocumentForMarkdown(diagramMarkdown, cachedOptions);
        NSUInteger afterFirstDocument = SPDFMarkdownDiagramWorkCount();
        SPDFDocumentForMarkdown(diagramMarkdown, cachedOptions);
        SPDFExpect(afterFirstDocument == 1 && SPDFMarkdownDiagramWorkCount() == 1,
                   @"a rerender with the session cache reuses the raster instead of redrawing it");
    }
    return SPDFFinishTests(@"SPDFMarkdownDiagramTests");
}
