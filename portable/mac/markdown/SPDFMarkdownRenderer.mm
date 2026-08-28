#import "SPDFMarkdownRenderer.h"

#import "SPDFMarkdownRenderInternal.h"

NSAttributedStringKey const SPDFMarkdownBlockIndexAttribute = @"SPDFMarkdownBlockIndex";
NSAttributedStringKey const SPDFMarkdownBlockKindAttribute = @"SPDFMarkdownBlockKind";
NSAttributedStringKey const SPDFMarkdownWikiLinkAttribute = @"SPDFMarkdownWikiLink";
NSAttributedStringKey const SPDFMarkdownImageTargetAttribute = @"SPDFMarkdownImageTarget";
NSAttributedStringKey const SPDFMarkdownCodeLanguageAttribute = @"SPDFMarkdownCodeLanguage";

@implementation SPDFMarkdownRenderOptions
- (instancetype)init {
    self = [super init];
    if (self) _fontScale = 1.0;
    return self;
}
- (void)setFontScale:(CGFloat)fontScale { _fontScale = MAX(0.5, MIN(3.0, fontScale)); }
+ (instancetype)defaultOptions {
    SPDFMarkdownRenderOptions* options = [SPDFMarkdownRenderOptions new];
    options.textSize = 15;
    options.codeSize = 13;
    options.lineSpacing = 3;
    options.paragraphSpacing = 10;
    options.fontScale = 1.0;
    options.contentInset = 24;
    options.maximumImageWidth = 480;
    options.maximumImageHeight = 320;
    options.maximumResourceBytes = 64 * 1024 * 1024;
    options.maximumDecodedImagePixels = 32 * 1024 * 1024;
    options.textColor = NSColor.labelColor;
    options.secondaryTextColor = NSColor.secondaryLabelColor;
    options.linkColor = NSColor.linkColor;
    options.codeBackgroundColor = [NSColor.quaternaryLabelColor colorWithAlphaComponent:0.10];
    options.quoteColor = NSColor.secondaryLabelColor;
    return options;
}
+ (instancetype)printOptions {
    SPDFMarkdownRenderOptions* options = self.defaultOptions;
    options.textColor = [NSColor colorWithSRGBRed:0.05 green:0.05 blue:0.05 alpha:1];
    options.secondaryTextColor = [NSColor colorWithSRGBRed:0.30 green:0.30 blue:0.30 alpha:1];
    options.linkColor = [NSColor colorWithSRGBRed:0.0 green:0.30 blue:0.72 alpha:1];
    options.codeBackgroundColor = [NSColor colorWithSRGBRed:0.94 green:0.94 blue:0.94 alpha:1];
    options.quoteColor = [NSColor colorWithSRGBRed:0.28 green:0.28 blue:0.28 alpha:1];
    return options;
}
- (id)copyWithZone:(NSZone*)zone {
    SPDFMarkdownRenderOptions* copy = [[[self class] allocWithZone:zone] init];
    copy.textSize = self.textSize;
    copy.codeSize = self.codeSize;
    copy.lineSpacing = self.lineSpacing;
    copy.paragraphSpacing = self.paragraphSpacing;
    copy.fontScale = self.fontScale;
    copy.contentInset = self.contentInset;
    copy.maximumImageWidth = self.maximumImageWidth;
    copy.maximumImageHeight = self.maximumImageHeight;
    copy.maximumResourceBytes = self.maximumResourceBytes;
    copy.maximumDecodedImagePixels = self.maximumDecodedImagePixels;
    copy.textColor = self.textColor;
    copy.secondaryTextColor = self.secondaryTextColor;
    copy.linkColor = self.linkColor;
    copy.codeBackgroundColor = self.codeBackgroundColor;
    copy.quoteColor = self.quoteColor;
    return copy;
}
@end

@implementation SPDFMarkdownRenderedBlock
- (instancetype)initWithBlockIndex:(NSUInteger)blockIndex
                              kind:(SPDFMarkdownBlockKind)kind
                   attributedRange:(NSRange)attributedRange
                             level:(NSUInteger)level
                             depth:(NSUInteger)depth {
    self = [super init];
    if (self) {
        _blockIndex = blockIndex;
        _kind = kind;
        _attributedRange = attributedRange;
        _level = level;
        _depth = depth;
    }
    return self;
}
@end

@interface SPDFMarkdownRenderedHeading ()
- (instancetype)initWithBlockIndex:(NSUInteger)blockIndex
                              level:(NSUInteger)level
                              title:(NSString*)title
                    attributedRange:(NSRange)attributedRange;
@end

@implementation SPDFMarkdownRenderedHeading
- (instancetype)initWithBlockIndex:(NSUInteger)blockIndex
                              level:(NSUInteger)level
                              title:(NSString*)title
                    attributedRange:(NSRange)attributedRange {
    self = [super init];
    if (self) {
        _blockIndex = blockIndex;
        _level = level;
        _title = [title copy];
        _attributedRange = attributedRange;
    }
    return self;
}
@end

@interface SPDFMarkdownRenderedDocument ()
- (instancetype)initWithString:(NSAttributedString*)string blocks:(NSArray<SPDFMarkdownRenderedBlock*>*)blocks;
@end

@implementation SPDFMarkdownRenderedDocument {
    NSDictionary<NSNumber*, SPDFMarkdownRenderedBlock*>* _byIndex;
    NSArray<SPDFMarkdownRenderedBlock*>* _sortedBlocks;
}
- (instancetype)initWithString:(NSAttributedString*)string blocks:(NSArray<SPDFMarkdownRenderedBlock*>*)blocks {
    self = [super init];
    if (!self) return nil;
    _attributedString = [string copy];
    _renderedBlocks = [blocks copy];
    NSMutableDictionary* byIndex = [NSMutableDictionary dictionary];
    NSMutableArray* headings = [NSMutableArray array];
    for (SPDFMarkdownRenderedBlock* block in blocks) {
        if (!byIndex[@(block.blockIndex)]) byIndex[@(block.blockIndex)] = block;
        if (block.kind != SPDFMarkdownBlockKindHeading) continue;
        NSString* title = [[string.string substringWithRange:block.attributedRange]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        SPDFMarkdownRenderedHeading* heading = [[SPDFMarkdownRenderedHeading alloc]
            initWithBlockIndex:block.blockIndex level:block.level title:title attributedRange:block.attributedRange];
        [headings addObject:heading];
    }
    _byIndex = [byIndex copy];
    _sortedBlocks = [blocks sortedArrayUsingComparator:^NSComparisonResult(SPDFMarkdownRenderedBlock* left,
                                                                           SPDFMarkdownRenderedBlock* right) {
        if (left.attributedRange.location != right.attributedRange.location) {
            return left.attributedRange.location < right.attributedRange.location ? NSOrderedAscending
                                                                                   : NSOrderedDescending;
        }
        if (left.attributedRange.length == right.attributedRange.length) return NSOrderedSame;
        return left.attributedRange.length > right.attributedRange.length ? NSOrderedAscending : NSOrderedDescending;
    }];
    _headings = [headings copy];
    return self;
}
- (SPDFMarkdownRenderedBlock*)renderedBlockWithIndex:(NSUInteger)blockIndex { return _byIndex[@(blockIndex)]; }

- (SPDFMarkdownRenderedBlock*)blockContainingLocation:(NSUInteger)location {
    NSUInteger low = 0;
    NSUInteger high = _sortedBlocks.count;
    while (low < high) {
        NSUInteger middle = low + (high - low) / 2;
        if (_sortedBlocks[middle].attributedRange.location <= location) low = middle + 1;
        else high = middle;
    }
    if (low == 0) return nil;
    SPDFMarkdownRenderedBlock* candidate = _sortedBlocks[low - 1];
    return NSLocationInRange(location, candidate.attributedRange) ? candidate : nil;
}

- (NSInteger)headingIndexAtLocation:(NSUInteger)location {
    NSUInteger low = 0;
    NSUInteger high = self.headings.count;
    while (low < high) {
        NSUInteger middle = low + (high - low) / 2;
        if (self.headings[middle].attributedRange.location <= location) low = middle + 1;
        else high = middle;
    }
    return low == 0 ? -1 : (NSInteger)low - 1;
}

- (void)appendSearchMatch:(NSRange)found
                canonical:(NSString*)canonical
                   matches:(NSMutableArray<SPDFMarkdownSearchMatch*>*)matches {
    SPDFMarkdownRenderedBlock* owner = [self blockContainingLocation:found.location];
    NSInteger headingIndex = [self headingIndexAtLocation:found.location];
    NSUInteger contextStart = found.location > 48 ? found.location - 48 : 0;
    NSUInteger contextEnd = MIN(canonical.length, NSMaxRange(found) + 48);
    NSRange contextRange = [canonical rangeOfComposedCharacterSequencesForRange:
        NSMakeRange(contextStart, contextEnd - contextStart)];
    NSString* context = [[canonical substringWithRange:contextRange]
        stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    [matches addObject:[[SPDFMarkdownSearchMatch alloc] initWithRange:found
                                                           blockIndex:owner ? owner.blockIndex : NSNotFound
                                                         headingIndex:headingIndex
                                                              context:context]];
}

- (NSArray<SPDFMarkdownSearchMatch*>*)exactSearchForQuery:(NSString*)query
                                                canonical:(NSString*)canonical
                                        cancellationToken:(SPDFMarkdownCancellationToken*)cancellationToken {
    NSUInteger* prefix = (NSUInteger*)calloc(query.length, sizeof(NSUInteger));
    if (!prefix) return @[];
    for (NSUInteger index = 1, matched = 0; index < query.length; ++index) {
        unichar value = [query characterAtIndex:index];
        while (matched && value != [query characterAtIndex:matched]) matched = prefix[matched - 1];
        if (value == [query characterAtIndex:matched]) ++matched;
        prefix[index] = matched;
    }
    NSMutableArray* matches = [NSMutableArray array];
    for (NSUInteger index = 0, matched = 0; index < canonical.length; ++index) {
        if ((index & 0xfff) == 0 && cancellationToken.isCancelled) {
            free(prefix);
            return @[];
        }
        unichar value = [canonical characterAtIndex:index];
        while (matched && value != [query characterAtIndex:matched]) matched = prefix[matched - 1];
        if (value == [query characterAtIndex:matched]) ++matched;
        if (matched == query.length) {
            NSRange found = NSMakeRange(index + 1 - matched, matched);
            [self appendSearchMatch:found canonical:canonical matches:matches];
            matched = 0;  // Preserve the existing non-overlapping match semantics.
        }
    }
    free(prefix);
    return cancellationToken.isCancelled ? @[] : matches;
}

- (NSArray<SPDFMarkdownSearchMatch*>*)searchForQuery:(NSString*)query caseSensitive:(BOOL)caseSensitive {
    return [self searchForQuery:query caseSensitive:caseSensitive cancellationToken:nil];
}
- (NSArray<SPDFMarkdownSearchMatch*>*)searchForQuery:(NSString*)query
                                       caseSensitive:(BOOL)caseSensitive
                                   cancellationToken:(SPDFMarkdownCancellationToken*)cancellationToken {
    static const NSUInteger maximumInteractiveQueryLength = 4096;
    if (query.length == 0 || query.length > maximumInteractiveQueryLength) return @[];
    NSString* canonical = self.attributedString.string;
    if (caseSensitive) {
        return [self exactSearchForQuery:query canonical:canonical cancellationToken:cancellationToken];
    }
    NSStringCompareOptions options = caseSensitive ? 0 : NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    NSMutableArray* matches = [NSMutableArray array];
    static const NSUInteger chunkLength = 64 * 1024;
    NSUInteger chunkStart = 0;
    while (chunkStart < canonical.length) {
        if (cancellationToken.isCancelled) return @[];
        NSUInteger ownedEnd = chunkStart + MIN(chunkLength, canonical.length - chunkStart);
        if (ownedEnd < canonical.length) {
            ownedEnd = NSMaxRange([canonical rangeOfComposedCharacterSequenceAtIndex:ownedEnd]);
        }
        NSUInteger overlap = MIN(query.length - 1, canonical.length - ownedEnd);
        NSRange remaining = NSMakeRange(chunkStart, ownedEnd + overlap - chunkStart);
        while (remaining.length) {
            if (cancellationToken.isCancelled) return @[];
            NSRange found = [canonical rangeOfString:query options:options range:remaining];
            if (found.location == NSNotFound || found.location >= ownedEnd) break;
            [self appendSearchMatch:found canonical:canonical matches:matches];
            NSUInteger next = MAX(NSMaxRange(found), found.location + 1);
            NSUInteger searchEnd = NSMaxRange(remaining);
            remaining = NSMakeRange(next, searchEnd - next);
        }
        chunkStart = ownedEnd;
    }
    return matches;
}
@end

@implementation SPDFMarkdownRenderer
- (instancetype)init { return [self initWithLanguageCatalog:SPDFMarkdownLanguageCatalog.sharedCatalog]; }
- (instancetype)initWithLanguageCatalog:(SPDFMarkdownLanguageCatalog*)languageCatalog {
    self = [super init];
    if (self) _languageCatalog = languageCatalog;
    return self;
}
- (SPDFMarkdownRenderedDocument*)renderModel:(SPDFMarkdownDocumentModel*)model
                                     options:(SPDFMarkdownRenderOptions*)options
                           languageOverrides:(NSDictionary<NSNumber*, NSString*>*)languageOverrides {
    return [self renderModel:model options:options languageOverrides:languageOverrides cancellationToken:nil];
}
- (SPDFMarkdownRenderedDocument*)renderModel:(SPDFMarkdownDocumentModel*)model
                                      options:(SPDFMarkdownRenderOptions*)options
                            languageOverrides:(NSDictionary<NSNumber*, NSString*>*)languageOverrides
                            cancellationToken:(SPDFMarkdownCancellationToken*)cancellationToken {
    SPDFMarkdownRenderContext* context = [SPDFMarkdownRenderContext new];
    context.output = [NSMutableAttributedString new];
    context.blocks = [NSMutableArray array];
    context.options = options;
    context.catalog = self.languageCatalog;
    context.highlighter = [SPDFMarkdownHighlighter new];
    context.cancellationToken = cancellationToken;
    context.overrides = languageOverrides ?: @{};
    context.sourceURL = model.sourceURL;
    if (model.resourceStore) {
        context.resourceStore = [model.resourceStore
            storeWithMaximumResourceBytes:options.maximumResourceBytes
                 maximumDecodedImagePixels:options.maximumDecodedImagePixels];
    }
    CGFloat fontScale = options.fontScale > 0 ? options.fontScale : 1;
    context.bodyFont = [NSFont systemFontOfSize:options.textSize * fontScale];
    context.codeFont = [NSFont monospacedSystemFontOfSize:options.codeSize * fontScale weight:NSFontWeightRegular];
    SPDFRenderMarkdownBlocks(context, model.blocks);
    if (cancellationToken.isCancelled) return nil;
    return [[SPDFMarkdownRenderedDocument alloc] initWithString:context.output blocks:context.blocks];
}
- (NSTextView*)newSelectableTextViewForRenderedDocument:(SPDFMarkdownRenderedDocument*)document
                                                 options:(SPDFMarkdownRenderOptions*)options {
    NSTextView* view = [[NSTextView alloc] initWithFrame:NSZeroRect];
    view.editable = NO;
    view.selectable = YES;
    view.richText = YES;
    view.importsGraphics = YES;
    view.drawsBackground = NO;
    view.textContainerInset = NSMakeSize(options.contentInset, options.contentInset);
    view.textContainer.widthTracksTextView = YES;
    [view.textStorage setAttributedString:document.attributedString];
    return view;
}
@end
