#import "SPDFMarkdownDiagramInternal.h"

#import <CoreText/CoreText.h>

// Shared diagram model objects, the per-variant palette, and the small text /
// text utilities every parser and shape emitter builds on.

@implementation SPDFMarkdownDiagramNode
- (instancetype)init {
    self = [super init];
    if (self) {
        _identifier = @"";
        _label = @"";
    }
    return self;
}
@end

@implementation SPDFMarkdownDiagramEdge
- (instancetype)init {
    self = [super init];
    if (self) {
        _fromIdentifier = @"";
        _toIdentifier = @"";
        _head = SPDFMarkdownDiagramArrowHeadArrow;
    }
    return self;
}
@end

@implementation SPDFMarkdownDiagramGraph {
    NSMutableDictionary<NSString*, SPDFMarkdownDiagramNode*>* _byIdentifier;
}
- (instancetype)init {
    self = [super init];
    if (self) {
        _vertical = YES;
        _nodes = [NSMutableArray array];
        _edges = [NSMutableArray array];
        _byIdentifier = [NSMutableDictionary dictionary];
        _classStyles = [NSMutableDictionary dictionary];
        _classNamesByIdentifier = [NSMutableDictionary dictionary];
    }
    return self;
}
- (SPDFMarkdownDiagramNode*)nodeForIdentifier:(NSString*)identifier createWithLabel:(NSString*)label {
    SPDFMarkdownDiagramNode* node = _byIdentifier[identifier];
    if (node) {
        // A later statement can attach the shaped label to a node first seen bare.
        if (label.length) node.label = label;
        return node;
    }
    node = [SPDFMarkdownDiagramNode new];
    node.identifier = identifier;
    node.label = label.length ? label : identifier;
    [_nodes addObject:node];
    _byIdentifier[identifier] = node;
    return node;
}
- (SPDFMarkdownDiagramNode*)existingNodeForIdentifier:(NSString*)identifier { return _byIdentifier[identifier]; }
- (SPDFMarkdownDiagramNodeStyle*)styleForNode:(SPDFMarkdownDiagramNode*)node {
    // `classDef default ...` is mermaid's catch-all; a node with its own class
    // never falls back to it.
    SPDFMarkdownDiagramNodeStyle* own = node.className.length ? _classStyles[node.className] : nil;
    return own ?: _classStyles[@"default"];
}
- (void)applyDeferredClassNames {
    if (!_classNamesByIdentifier.count) return;
    for (SPDFMarkdownDiagramNode* node in _nodes) {
        // A `:::name` written on the node itself wins over a later `class`
        // statement, so the closer declaration is the one that shows.
        if (node.className.length) continue;
        NSString* name = _classNamesByIdentifier[node.identifier];
        if (name.length) node.className = name;
    }
}
@end

@implementation SPDFMarkdownDiagramSequenceEvent
@end

@implementation SPDFMarkdownDiagramSequence
- (instancetype)init {
    self = [super init];
    if (self) {
        _actorIdentifiers = [NSMutableArray array];
        _actorLabels = [NSMutableDictionary dictionary];
        _events = [NSMutableArray array];
    }
    return self;
}
- (NSString*)actorForToken:(NSString*)token {
    NSString* identifier = SPDFMarkdownDiagramTrim(token);
    if (!identifier.length) return identifier;
    if (!self.actorLabels[identifier]) {
        [self.actorIdentifiers addObject:identifier];
        self.actorLabels[identifier] = identifier;
    }
    return identifier;
}
@end

@implementation SPDFMarkdownDiagramPieSlice
@end

@implementation SPDFMarkdownDiagramPie
- (instancetype)init {
    self = [super init];
    if (self) _slices = [NSMutableArray array];
    return self;
}
@end

@implementation SPDFMarkdownDiagramGanttTask
@end

@implementation SPDFMarkdownDiagramGanttSection
- (instancetype)init {
    self = [super init];
    if (self) _tasks = [NSMutableArray array];
    return self;
}
@end

@implementation SPDFMarkdownDiagramGantt
- (instancetype)init {
    self = [super init];
    if (self) _sections = [NSMutableArray array];
    return self;
}
- (NSUInteger)taskCount {
    NSUInteger count = 0;
    for (SPDFMarkdownDiagramGanttSection* section in self.sections) count += section.tasks.count;
    return count;
}
@end

// The categorical ramp starts from the theme accent and rotates through five
// fixed hue offsets, with saturation/brightness retuned per variant so slices
// and bars stay readable on both papers without ever leaving the theme family.
static NSArray<NSColor*>* SPDFDiagramAccentRamp(NSColor* accent, SPDFMarkdownThemeVariant variant) {
    NSColor* base = [accent colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: accent;
    CGFloat hue = 0, saturation = 0, brightness = 0, alpha = 0;
    [base getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha];
    static const CGFloat offsets[] = {0.0, 0.45, 0.12, 0.62, 0.27, 0.82};
    BOOL dark = variant == SPDFMarkdownThemeVariantDark;
    NSMutableArray* ramp = [NSMutableArray arrayWithCapacity:6];
    for (NSUInteger index = 0; index < 6; ++index) {
        CGFloat rotated = fmod(hue + offsets[index], 1.0);
        [ramp addObject:[NSColor colorWithColorSpace:NSColorSpace.sRGBColorSpace
                                                 hue:rotated
                                          saturation:MIN(1.0, saturation * (dark ? 0.62 : 0.85))
                                          brightness:dark ? MIN(1.0, brightness * 1.05) : MIN(0.78, brightness)
                                               alpha:1.0]];
    }
    return ramp;
}

@implementation SPDFMarkdownDiagramPalette
+ (instancetype)paletteForVariant:(SPDFMarkdownThemeVariant)variant {
    static SPDFMarkdownDiagramPalette* palettes[2];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      for (NSInteger raw = 0; raw < 2; ++raw) {
          SPDFMarkdownTheme* theme = [SPDFMarkdownTheme themeForVariant:(SPDFMarkdownThemeVariant)raw];
          SPDFMarkdownDiagramPalette* palette = [SPDFMarkdownDiagramPalette new];
          palette->_paperColor = theme.paperColor;
          palette->_nodeFillColor = theme.codeBoxFillColor;
          palette->_nodeStrokeColor = theme.codeBoxStrokeColor;
          palette->_textColor = theme.bodyTextColor;
          palette->_secondaryColor = theme.secondaryTextColor;
          palette->_accentColor = theme.linkColor;
          palette->_criticalColor = raw == SPDFMarkdownThemeVariantDark
              ? [NSColor colorWithSRGBRed:0.90 green:0.33 blue:0.29 alpha:1.0]   // #E5544A
              : [NSColor colorWithSRGBRed:0.82 green:0.14 blue:0.18 alpha:1.0];  // #D1242F
          palette->_accentRamp = SPDFDiagramAccentRamp(theme.linkColor, (SPDFMarkdownThemeVariant)raw);
          palettes[raw] = palette;
      }
    });
    return palettes[variant == SPDFMarkdownThemeVariantDark ? 1 : 0];
}
@end

NSString* SPDFMarkdownDiagramTrim(NSString* string) {
    return [string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

// Splits source into trimmed lines, dropping blanks, `%%` comment lines
// (including `%%{init: ...}%%` directives) and js-sequence `#` comments.
NSArray<NSString*>* SPDFMarkdownDiagramSignificantLines(NSString* source) {
    NSMutableArray* lines = [NSMutableArray array];
    for (NSString* raw in [source componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString* line = SPDFMarkdownDiagramTrim(raw);
        if (!line.length || [line hasPrefix:@"%%"] || [line hasPrefix:@"#"]) continue;
        [lines addObject:line];
    }
    return lines;
}

// The five entities mermaid labels actually carry. `&amp;` is decoded LAST so
// `&amp;lt;` comes out as the text `&lt;` rather than as a `<`.
static NSString* SPDFDiagramDecodeEntities(NSString* text) {
    if ([text rangeOfString:@"&"].location == NSNotFound) return text;
    static NSArray<NSArray<NSString*>*>* replacements;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      replacements = @[
          @[ @"&lt;", @"<" ], @[ @"&gt;", @">" ], @[ @"&quot;", @"\"" ], @[ @"&#39;", @"'" ],
          @[ @"&apos;", @"'" ], @[ @"&nbsp;", @" " ], @[ @"&amp;", @"&" ]
      ];
    });
    NSString* decoded = text;
    for (NSArray<NSString*>* replacement in replacements)
        decoded = [decoded stringByReplacingOccurrencesOfString:replacement[0]
                                                     withString:replacement[1]];
    return decoded;
}

// Collapses every whitespace run in one line of a label to a single space.
static NSString* SPDFDiagramCollapseSpaces(NSString* text) {
    NSMutableArray* kept = [NSMutableArray array];
    for (NSString* part in [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet])
        if (part.length) [kept addObject:part];
    return [kept componentsJoinedByString:@" "];
}

// Normalizes a node/edge/message label: turns the <br> variants into REAL line
// breaks, strips wrapping quotes and backticks, decodes HTML entities, and
// collapses whitespace runs inside each line. A label is therefore a
// newline-separated list of lines, and the wrap/measure pair below is the only
// place that has to know it.
//
// Order matters twice: <br> becomes a newline before the quote strip (the
// quotes are still at the ends), and entities are decoded AFTER it, so a
// `&quot;`-quoted label keeps its quotes as text instead of losing them to the
// syntactic-quote strip.
NSString* SPDFMarkdownDiagramCleanLabel(NSString* label) {
    NSString* text = SPDFMarkdownDiagramTrim(label);
    for (NSString* br in @[ @"<br/>", @"<br />", @"<br>" ]) {
        text = [text stringByReplacingOccurrencesOfString:br withString:@"\n"
                                                  options:NSCaseInsensitiveSearch
                                                    range:NSMakeRange(0, text.length)];
    }
    if (text.length >= 2) {
        unichar first = [text characterAtIndex:0];
        unichar last = [text characterAtIndex:text.length - 1];
        if ((first == '"' && last == '"') || (first == '`' && last == '`'))
            text = [text substringWithRange:NSMakeRange(1, text.length - 2)];
    }
    text = SPDFDiagramDecodeEntities(text);
    if ([text rangeOfString:@"\n"].location == NSNotFound) return SPDFDiagramCollapseSpaces(text);
    NSMutableArray<NSString*>* lines = [NSMutableArray array];
    for (NSString* line in [text componentsSeparatedByString:@"\n"]) {
        NSString* collapsed = SPDFDiagramCollapseSpaces(line);
        if (collapsed.length) [lines addObject:collapsed];
    }
    return [lines componentsJoinedByString:@"\n"];
}

// A diagram label is always ONE line of canonical text at an explicit
// position, so wrapping is done here, up front, by the same CoreText
// typesetter the drawing pass uses — never by an implicit drawWithRect: pass.
// One <br>-free segment, appended as one line per soft wrap.
static void SPDFDiagramAppendWrappedSegment(NSMutableArray<NSString*>* lines, NSString* text, NSFont* font,
                                            CGFloat maximumWidth) {
    NSAttributedString* attributed =
        [[NSAttributedString alloc] initWithString:text attributes:@{NSFontAttributeName: font}];
    CTTypesetterRef typesetter =
        CTTypesetterCreateWithAttributedString((__bridge CFAttributedStringRef)attributed);
    if (!typesetter) {
        if (text.length) [lines addObject:text];
        return;
    }
    CFIndex start = 0;
    CFIndex length = (CFIndex)text.length;
    while (start < length) {
        CFIndex count = CTTypesetterSuggestLineBreak(typesetter, start, maximumWidth);
        if (count <= 0) count = length - start;  // a single glyph wider than the box
        NSString* line = [text substringWithRange:NSMakeRange((NSUInteger)start, (NSUInteger)count)];
        line = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (line.length) [lines addObject:line];
        start += count;
    }
    CFRelease(typesetter);
}

NSArray<NSString*>* SPDFMarkdownDiagramWrapText(NSString* text, NSFont* font, CGFloat maximumWidth) {
    if (!text.length) return @[];
    if (maximumWidth <= 0) return [text componentsSeparatedByString:@"\n"];
    NSMutableArray<NSString*>* lines = [NSMutableArray array];
    // A `<br/>` in the source is a HARD break: each segment wraps on its own,
    // so an authored break is never undone by the soft wrapper.
    for (NSString* segment in [text componentsSeparatedByString:@"\n"])
        SPDFDiagramAppendWrappedSegment(lines, segment, font, maximumWidth);
    return lines.count ? lines : @[ text ];
}

CGFloat SPDFMarkdownDiagramLineHeight(NSFont* font) {
    return ceil(font.ascender - font.descender + font.leading);
}

// The box a wrapped string occupies: the widest line by the widest line's
// typographic width, and one line height per wrapped line — exactly what the
// emitted labels will take up.
NSSize SPDFMarkdownDiagramMeasureText(NSString* text, NSFont* font, CGFloat maximumWidth) {
    if (!text.length) return NSZeroSize;
    NSArray<NSString*>* lines = SPDFMarkdownDiagramWrapText(text, font, maximumWidth);
    CGFloat width = 0;
    for (NSString* line in lines) {
        NSSize size = [line sizeWithAttributes:@{NSFontAttributeName: font}];
        width = MAX(width, size.width);
    }
    return NSMakeSize(ceil(width), ceil(lines.count * SPDFMarkdownDiagramLineHeight(font)));
}
