#import "SPDFMacAIChatMarkdown.h"
#import "markdown/SPDFMarkdownParser.h"
#import "markdown/SPDFMarkdownRenderer.h"
BOOL SPDFMacAIChatLinkAllowed(NSURL* URL) {
    return ([URL.scheme.lowercaseString isEqual:@"https"] && URL.host.length && !URL.user.length && !URL.password.length) ||
        ([URL.scheme.lowercaseString isEqual:@"spdf-ai"] && [URL.host isEqual:@"document"]);
}
static SPDFMarkdownBlock* SafeBlock(SPDFMarkdownBlock* block, NSMutableDictionary* citations) {
    NSMutableArray* runs=[NSMutableArray array];
    for(SPDFMarkdownInlineRun* run in block.runs) {
        SPDFMarkdownInlineTraits traits=run.traits; NSString* destination=run.destination;
        if(traits & SPDFMarkdownInlineTraitImage) {
            // Strip at the model boundary BEFORE rendering: absolute file URLs
            // otherwise load even with a nil Markdown sourceURL.
            traits &= ~(SPDFMarkdownInlineTraitImage|SPDFMarkdownInlineTraitLink); destination=nil;
        }
        if(traits & (SPDFMarkdownInlineTraitLink|SPDFMarkdownInlineTraitWikiLink)) {
            if(!SPDFMacAIChatLinkAllowed([NSURL URLWithString:destination ?: @""])) {
                traits &= ~(SPDFMarkdownInlineTraitLink|SPDFMarkdownInlineTraitWikiLink); destination=nil;
            }
        }
        if((traits & SPDFMarkdownInlineTraitLink) && [[NSURL URLWithString:destination ?: @""].scheme isEqual:@"spdf-ai"]) {
            NSString* alias=[@"https://spdf-ai.invalid/" stringByAppendingString:NSUUID.UUID.UUIDString];
            citations[alias]=[NSURL URLWithString:destination]; destination=alias;
        }
        [runs addObject:[[SPDFMarkdownInlineRun alloc] initWithText:run.text traits:traits destination:destination]];
    }
    NSMutableArray* children=[NSMutableArray array];
    for(SPDFMarkdownBlock* child in block.children) [children addObject:SafeBlock(child,citations)];
    // Chat retains code formatting but doesn't run diagram layout on model output.
    NSString* language=block.codeLanguage;
    if([@[@"mermaid",@"flow",@"flowchart",@"sequence"] containsObject:language.lowercaseString]) language=@"text";
    return [[SPDFMarkdownBlock alloc] initWithKind:block.kind blockIndex:block.blockIndex level:block.level
        orderedStart:block.orderedStart taskState:block.taskState tableAlignment:block.tableAlignment
        blockAlignment:block.blockAlignment tableColumnCount:block.tableColumnCount runs:runs children:children
        codeLanguage:language codeInfo:nil calloutKind:block.calloutKind calloutTitle:block.calloutTitle];
}
NSAttributedString* SPDFMacAIChatMarkdown(NSString* text, CGFloat width, BOOL dark) {
    if(text.length>128*1024) text=[[text substringToIndex:128*1024] stringByAppendingString:@"\n[Message display truncated]"];
    SPDFMarkdownParser* parser=[SPDFMarkdownParser new]; parser.maximumInputBytes=512*1024;
    SPDFMarkdownDocumentModel* parsed=[parser parseString:text sourceURL:nil error:nil];
    if(!parsed) return [[NSAttributedString alloc] initWithString:text ?: @""];
    NSMutableArray* blocks=[NSMutableArray array]; NSMutableDictionary* citations=[NSMutableDictionary dictionary];
    for(SPDFMarkdownBlock* block in parsed.blocks) [blocks addObject:SafeBlock(block,citations)];
    SPDFMarkdownDocumentModel* safe=[[SPDFMarkdownDocumentModel alloc] initWithSourceURL:nil frontMatter:@{}
        rawFrontMatter:nil blocks:blocks];
    SPDFMarkdownRenderOptions* options=[SPDFMarkdownRenderOptions defaultOptionsForThemeVariant:dark ? SPDFMarkdownThemeVariantDark : SPDFMarkdownThemeVariantLight];
    options.textSize=13; options.codeSize=12; options.contentInset=0;
    options.textColor=dark ? [NSColor colorWithSRGBRed:.93 green:.94 blue:.95 alpha:1] : [NSColor colorWithSRGBRed:.15 green:.16 blue:.17 alpha:1];
    options.secondaryTextColor=dark ? [NSColor colorWithSRGBRed:.70 green:.72 blue:.75 alpha:1] : [NSColor colorWithSRGBRed:.38 green:.40 blue:.43 alpha:1];
    options.linkColor=dark ? [NSColor colorWithSRGBRed:.63 green:.79 blue:.93 alpha:1] : [NSColor colorWithSRGBRed:.16 green:.39 blue:.60 alpha:1];
    options.codeBackgroundColor=dark ? [NSColor colorWithSRGBRed:.14 green:.15 blue:.16 alpha:1] : [NSColor colorWithSRGBRed:.95 green:.95 blue:.95 alpha:1];
    options.pageContentSize=NSMakeSize(MAX(200,width),10000);
    NSAttributedString* rendered=[[[SPDFMarkdownRenderer alloc] init] renderModel:safe options:options languageOverrides:nil].attributedString;
    NSMutableAttributedString* result=[rendered mutableCopy];
    [rendered enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0,rendered.length) options:0 usingBlock:^(id value,NSRange range,BOOL* stop) {
        (void)stop; NSString* key=[value isKindOfClass:NSURL.class] ? [value absoluteString] : [value description];
        if(citations[key]) [result addAttribute:NSLinkAttributeName value:citations[key] range:range];
    }];
    return result;
}
