#import "SPDFMarkdownDiagramInternal.h"

#import <stdatomic.h>

// Entry seam, budgets, work counter and the per-document render cache.

const NSUInteger SPDFMarkdownDiagramMaximumNodes = 200;
const NSUInteger SPDFMarkdownDiagramMaximumEdges = 400;
const NSTimeInterval SPDFMarkdownDiagramLayoutDeadline = 0.050;
const CGFloat SPDFMarkdownDiagramMaximumRasterDimension = 4096;

static _Atomic NSUInteger sSPDFDiagramWorkCount = 0;

NSUInteger SPDFMarkdownDiagramWorkCount(void) {
    return atomic_load(&sSPDFDiagramWorkCount);
}

void SPDFMarkdownDiagramResetWorkCount(void) {
    atomic_store(&sSPDFDiagramWorkCount, (NSUInteger)0);
}

@interface SPDFMarkdownDiagramImage ()
@property(nonatomic, readwrite, strong) NSImage* image;
@property(nonatomic, readwrite) NSSize logicalSize;
@end

@implementation SPDFMarkdownDiagramImage
@end

SPDFMarkdownDiagramImage* SPDFMarkdownDiagramImageMake(NSImage* image, NSSize logicalSize) {
    SPDFMarkdownDiagramImage* result = [SPDFMarkdownDiagramImage new];
    result.image = image;
    result.logicalSize = logicalSize;
    return result;
}

// --- Cache -------------------------------------------------------------------

// One cached outcome; `source` is kept so a hash collision can never serve the
// wrong diagram. A nil `image` records a failed parse (negative caching).
@interface SPDFMarkdownDiagramCacheEntry : NSObject
@property(nonatomic, copy) NSString* source;
@property(nonatomic, strong, nullable) SPDFMarkdownDiagramImage* image;
@end
@implementation SPDFMarkdownDiagramCacheEntry
@end

@implementation SPDFMarkdownDiagramCache {
    NSMutableDictionary<NSString*, SPDFMarkdownDiagramCacheEntry*>* _entries;
}
- (instancetype)init {
    self = [super init];
    if (self) _entries = [NSMutableDictionary dictionary];
    return self;
}
- (NSUInteger)count {
    @synchronized(self) {
        return _entries.count;
    }
}
- (void)removeAllEntries {
    @synchronized(self) {
        [_entries removeAllObjects];
    }
}
- (SPDFMarkdownDiagramCacheEntry*)entryForKey:(NSString*)key source:(NSString*)source {
    @synchronized(self) {
        SPDFMarkdownDiagramCacheEntry* entry = _entries[key];
        return [entry.source isEqualToString:source] ? entry : nil;
    }
}
- (void)storeImage:(SPDFMarkdownDiagramImage*)image forKey:(NSString*)key source:(NSString*)source {
    SPDFMarkdownDiagramCacheEntry* entry = [SPDFMarkdownDiagramCacheEntry new];
    entry.source = source;
    entry.image = image;
    @synchronized(self) {
        // Simple bound: a runaway document drops the whole map instead of
        // growing without limit (rerenders repopulate what is still visible).
        if (_entries.count >= 128) [_entries removeAllObjects];
        _entries[key] = entry;
    }
}
@end

// --- Dispatch ------------------------------------------------------------------

BOOL SPDFMarkdownDiagramIsDiagramLanguage(NSString* fenceIdentifier) {
    if (!fenceIdentifier.length) return NO;
    NSString* token = [[SPDFMarkdownDiagramTrim(fenceIdentifier)
        componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet] firstObject]
                          .lowercaseString;
    return [token isEqualToString:@"mermaid"] || [token isEqualToString:@"sequence"] ||
           [token isEqualToString:@"flow"];
}

// The mermaid sub-type is the first significant line's first word.
static NSString* SPDFDiagramMermaidKeyword(NSString* source) {
    NSString* first = SPDFMarkdownDiagramSignificantLines(source).firstObject ?: @"";
    return [[first componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet] firstObject]
        .lowercaseString;
}

static SPDFMarkdownDiagramImage* SPDFDiagramRenderUncached(NSString* language, NSString* source,
                                                           CGFloat contentWidth, CGFloat fontScale,
                                                           SPDFMarkdownThemeVariant variant) {
    SPDFMarkdownDiagramPalette* palette = [SPDFMarkdownDiagramPalette paletteForVariant:variant];
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + SPDFMarkdownDiagramLayoutDeadline;
    if ([language isEqualToString:@"sequence"]) {
        SPDFMarkdownDiagramSequence* sequence = SPDFMarkdownDiagramParseSequence(source, NO);
        return sequence ? SPDFMarkdownDiagramRasterizeSequence(sequence, contentWidth, fontScale, palette) : nil;
    }
    if ([language isEqualToString:@"flow"]) {
        SPDFMarkdownDiagramGraph* graph = SPDFMarkdownDiagramParseFlowFence(source);
        return graph ? SPDFMarkdownDiagramRasterizeGraph(graph, contentWidth, fontScale, palette, deadline) : nil;
    }
    // mermaid sub-types.
    NSString* keyword = SPDFDiagramMermaidKeyword(source);
    if ([keyword isEqualToString:@"graph"] || [keyword isEqualToString:@"flowchart"]) {
        SPDFMarkdownDiagramGraph* graph = SPDFMarkdownDiagramParseMermaidFlowchart(source);
        return graph ? SPDFMarkdownDiagramRasterizeGraph(graph, contentWidth, fontScale, palette, deadline) : nil;
    }
    if ([keyword isEqualToString:@"sequencediagram"]) {
        SPDFMarkdownDiagramSequence* sequence = SPDFMarkdownDiagramParseSequence(source, YES);
        return sequence ? SPDFMarkdownDiagramRasterizeSequence(sequence, contentWidth, fontScale, palette) : nil;
    }
    if ([keyword isEqualToString:@"pie"]) {
        SPDFMarkdownDiagramPie* pie = SPDFMarkdownDiagramParsePie(source);
        return pie ? SPDFMarkdownDiagramRasterizePie(pie, contentWidth, fontScale, palette) : nil;
    }
    if ([keyword isEqualToString:@"statediagram"] || [keyword isEqualToString:@"statediagram-v2"]) {
        SPDFMarkdownDiagramGraph* graph = SPDFMarkdownDiagramParseMermaidState(source);
        return graph ? SPDFMarkdownDiagramRasterizeGraph(graph, contentWidth, fontScale, palette, deadline) : nil;
    }
    if ([keyword isEqualToString:@"classdiagram"]) {
        SPDFMarkdownDiagramGraph* graph = SPDFMarkdownDiagramParseMermaidClass(source);
        return graph ? SPDFMarkdownDiagramRasterizeGraph(graph, contentWidth, fontScale, palette, deadline) : nil;
    }
    if ([keyword isEqualToString:@"gantt"]) {
        SPDFMarkdownDiagramGantt* gantt = SPDFMarkdownDiagramParseGantt(source);
        return gantt ? SPDFMarkdownDiagramRasterizeGantt(gantt, contentWidth, fontScale, palette) : nil;
    }
    return nil;  // unknown mermaid sub-type degrades to the code box
}

SPDFMarkdownDiagramImage* SPDFMarkdownDiagramRender(NSString* fenceIdentifier, NSString* source,
                                                    CGFloat contentWidth, CGFloat fontScale,
                                                    SPDFMarkdownThemeVariant variant,
                                                    SPDFMarkdownDiagramCache* cache) {
    if (!SPDFMarkdownDiagramIsDiagramLanguage(fenceIdentifier) || !source.length) return nil;
    NSString* language = [[SPDFMarkdownDiagramTrim(fenceIdentifier)
        componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet] firstObject]
                             .lowercaseString;
    NSString* key = [NSString stringWithFormat:@"%@|%ld|%.4f|%.1f|%lu|%lu", language, (long)variant, fontScale,
                                               contentWidth, (unsigned long)source.hash,
                                               (unsigned long)source.length];
    SPDFMarkdownDiagramCacheEntry* cached = [cache entryForKey:key source:source];
    if (cached) return cached.image;
    atomic_fetch_add(&sSPDFDiagramWorkCount, (NSUInteger)1);
    SPDFMarkdownDiagramImage* image =
        SPDFDiagramRenderUncached(language, source, contentWidth, fontScale, variant);
    [cache storeImage:image forKey:key source:source];
    return image;
}
