#pragma once

#import <AppKit/AppKit.h>

#import "SPDFMarkdownDecorations.h"

NS_ASSUME_NONNULL_BEGIN

// Native diagram rendering for Markdown code fences (Typora's set): mermaid
// (flowchart, sequenceDiagram, pie, stateDiagram/-v2, classDiagram, gantt),
// js-sequence (`sequence` fences) and flowchart.js (`flow` fences). Pure
// parsing plus Core Graphics — no web engine, no JS, no network. Every
// unsupported, malformed or over-budget input returns nil so the caller falls
// through to the exact existing code-box rendering.

// Hard budgets. Exceeding any of them degrades the fence to a code block.
FOUNDATION_EXPORT const NSUInteger SPDFMarkdownDiagramMaximumNodes;         // 200 nodes/actors/slices/tasks
FOUNDATION_EXPORT const NSUInteger SPDFMarkdownDiagramMaximumEdges;         // 400 edges/events
FOUNDATION_EXPORT const NSTimeInterval SPDFMarkdownDiagramLayoutDeadline;   // 50 ms of layout wall-clock
FOUNDATION_EXPORT const CGFloat SPDFMarkdownDiagramMaximumRasterDimension;  // 4096 px per bitmap axis

// A finished diagram: a 2x bitmap-backed NSImage plus its logical point size
// (the attachment bounds the renderer should reserve).
@interface SPDFMarkdownDiagramImage : NSObject
@property(nonatomic, readonly) NSImage* image;
@property(nonatomic, readonly) NSSize logicalSize;
@end

// Thread-safe render cache keyed by (source, language, variant, fontScale,
// width). Failed parses are cached too, so a rerender never re-parses a
// malformed fence. Owned per document/session and threaded through
// SPDFMarkdownRenderOptions.diagramCache; theme and text-size rerenders hit it.
@interface SPDFMarkdownDiagramCache : NSObject
@property(nonatomic, readonly) NSUInteger count;
- (void)removeAllEntries;
@end

// YES when the fence identifier names a diagram fence (mermaid / sequence /
// flow, case-insensitive first token). O(1); safe to call on every code fence.
FOUNDATION_EXPORT BOOL SPDFMarkdownDiagramIsDiagramLanguage(NSString* _Nullable fenceIdentifier);

// The single entry seam: (fence language, source, content width budget,
// fontScale, theme variant) -> image + logical size, or nil on ANY parse,
// unsupported-subtype, or over-budget condition. Deterministic per inputs.
FOUNDATION_EXPORT SPDFMarkdownDiagramImage* _Nullable SPDFMarkdownDiagramRender(
    NSString* fenceIdentifier, NSString* source, CGFloat contentWidth, CGFloat fontScale,
    SPDFMarkdownThemeVariant variant, SPDFMarkdownDiagramCache* _Nullable cache);

// Test-visible laziness/caching proof: incremented once per actual
// parse+layout+raster attempt (cache hits and non-diagram languages do not
// count). A document with no diagram fences must leave this untouched.
FOUNDATION_EXPORT NSUInteger SPDFMarkdownDiagramWorkCount(void);
FOUNDATION_EXPORT void SPDFMarkdownDiagramResetWorkCount(void);

NS_ASSUME_NONNULL_END
