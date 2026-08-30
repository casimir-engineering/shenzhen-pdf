#pragma once

#import "SPDFMarkdownDiagram.h"

NS_ASSUME_NONNULL_BEGIN

// Internal model, parser, layout and raster seams of the diagram engine.
// Everything here is deterministic and side-effect free; the only public
// surface is SPDFMarkdownDiagram.h. Tests import this header directly.

typedef NS_ENUM(NSInteger, SPDFMarkdownDiagramNodeShape) {
    SPDFMarkdownDiagramNodeShapeRect = 0,      // id[text]
    SPDFMarkdownDiagramNodeShapeRound,         // id(text)
    SPDFMarkdownDiagramNodeShapeStadium,       // id([text])
    SPDFMarkdownDiagramNodeShapeDiamond,       // id{text}
    SPDFMarkdownDiagramNodeShapeCircle,        // id((text))
    SPDFMarkdownDiagramNodeShapeSubroutine,    // id[[text]] / flow subroutine
    SPDFMarkdownDiagramNodeShapeParallelogram, // flow inputoutput
    SPDFMarkdownDiagramNodeShapeStartDot,      // state [*] source
    SPDFMarkdownDiagramNodeShapeEndDot,        // state [*] target
    SPDFMarkdownDiagramNodeShapeClassBox,      // classDiagram compartments
};

typedef NS_ENUM(NSInteger, SPDFMarkdownDiagramLineStyle) {
    SPDFMarkdownDiagramLineStyleSolid = 0,
    SPDFMarkdownDiagramLineStyleDashed,
    SPDFMarkdownDiagramLineStyleThick,
};

typedef NS_ENUM(NSInteger, SPDFMarkdownDiagramArrowHead) {
    SPDFMarkdownDiagramArrowHeadNone = 0,
    SPDFMarkdownDiagramArrowHeadArrow,           // filled triangle
    SPDFMarkdownDiagramArrowHeadHollowTriangle,  // class inheritance/realization
    SPDFMarkdownDiagramArrowHeadFilledDiamond,   // class composition
    SPDFMarkdownDiagramArrowHeadHollowDiamond,   // class aggregation
};

@interface SPDFMarkdownDiagramNode : NSObject
@property(nonatomic, copy) NSString* identifier;
@property(nonatomic, copy) NSString* label;
@property(nonatomic) SPDFMarkdownDiagramNodeShape shape;
// classDiagram compartments (nil elsewhere).
@property(nonatomic, copy, nullable) NSArray<NSString*>* memberAttributes;
@property(nonatomic, copy, nullable) NSArray<NSString*>* memberMethods;
// Layout state/results.
@property(nonatomic) NSInteger rank;
@property(nonatomic) NSInteger order;
@property(nonatomic) NSRect frame;
@end

@interface SPDFMarkdownDiagramEdge : NSObject
@property(nonatomic, copy) NSString* fromIdentifier;
@property(nonatomic, copy) NSString* toIdentifier;
@property(nonatomic, copy, nullable) NSString* label;
@property(nonatomic) SPDFMarkdownDiagramLineStyle lineStyle;
@property(nonatomic) SPDFMarkdownDiagramArrowHead head;  // drawn at the `to` end
@end

// A directed graph plus flow direction. `vertical` maps TD/TB (and BT via
// `reversed`); horizontal maps LR (RL via `reversed`).
@interface SPDFMarkdownDiagramGraph : NSObject
@property(nonatomic) BOOL vertical;
@property(nonatomic) BOOL reversed;
@property(nonatomic, readonly) NSMutableArray<SPDFMarkdownDiagramNode*>* nodes;
@property(nonatomic, readonly) NSMutableArray<SPDFMarkdownDiagramEdge*>* edges;
- (SPDFMarkdownDiagramNode*)nodeForIdentifier:(NSString*)identifier createWithLabel:(nullable NSString*)label;
- (nullable SPDFMarkdownDiagramNode*)existingNodeForIdentifier:(NSString*)identifier;
@end

typedef NS_ENUM(NSInteger, SPDFMarkdownDiagramSequenceEventKind) {
    SPDFMarkdownDiagramSequenceEventMessage = 0,
    SPDFMarkdownDiagramSequenceEventNote,
    SPDFMarkdownDiagramSequenceEventFrameBegin,  // alt/opt/loop/par/rect
    SPDFMarkdownDiagramSequenceEventFrameElse,   // else / and
    SPDFMarkdownDiagramSequenceEventFrameEnd,    // end
    SPDFMarkdownDiagramSequenceEventActivate,
    SPDFMarkdownDiagramSequenceEventDeactivate,
};

typedef NS_ENUM(NSInteger, SPDFMarkdownDiagramNotePosition) {
    SPDFMarkdownDiagramNoteLeftOf = 0,
    SPDFMarkdownDiagramNoteRightOf,
    SPDFMarkdownDiagramNoteOver,
};

@interface SPDFMarkdownDiagramSequenceEvent : NSObject
@property(nonatomic) SPDFMarkdownDiagramSequenceEventKind kind;
@property(nonatomic, copy, nullable) NSString* fromIdentifier;
@property(nonatomic, copy, nullable) NSString* toIdentifier;  // == from for self-messages
@property(nonatomic, copy, nullable) NSString* text;
@property(nonatomic) BOOL dashed;
@property(nonatomic) BOOL arrowhead;
@property(nonatomic) SPDFMarkdownDiagramNotePosition notePosition;
@property(nonatomic, copy, nullable) NSString* frameKeyword;  // alt/opt/loop/...
@end

@interface SPDFMarkdownDiagramSequence : NSObject
@property(nonatomic, copy, nullable) NSString* title;
@property(nonatomic, readonly) NSMutableArray<NSString*>* actorIdentifiers;  // in column order
@property(nonatomic, readonly) NSMutableDictionary<NSString*, NSString*>* actorLabels;
@property(nonatomic, readonly) NSMutableArray<SPDFMarkdownDiagramSequenceEvent*>* events;
- (NSString*)actorForToken:(NSString*)token;  // registers on first sight
@end

@interface SPDFMarkdownDiagramPieSlice : NSObject
@property(nonatomic, copy) NSString* label;
@property(nonatomic) double value;
@end

@interface SPDFMarkdownDiagramPie : NSObject
@property(nonatomic, copy, nullable) NSString* title;
@property(nonatomic, readonly) NSMutableArray<SPDFMarkdownDiagramPieSlice*>* slices;
@end

@interface SPDFMarkdownDiagramGanttTask : NSObject
@property(nonatomic, copy) NSString* name;
@property(nonatomic, copy, nullable) NSString* taskIdentifier;
@property(nonatomic) NSInteger startDay;  // days since the chart's epoch
@property(nonatomic) NSInteger endDay;    // exclusive
@property(nonatomic) BOOL done;
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL critical;
@end

@interface SPDFMarkdownDiagramGanttSection : NSObject
@property(nonatomic, copy) NSString* name;
@property(nonatomic, readonly) NSMutableArray<SPDFMarkdownDiagramGanttTask*>* tasks;
@end

@interface SPDFMarkdownDiagramGantt : NSObject
@property(nonatomic, copy, nullable) NSString* title;
@property(nonatomic, copy, nullable) NSDate* epoch;  // day 0
@property(nonatomic, readonly) NSMutableArray<SPDFMarkdownDiagramGanttSection*>* sections;
- (NSUInteger)taskCount;
@end

// Concrete per-variant palette derived from SPDFMarkdownTheme roles: node
// fill/stroke are the code-box roles, text is body text, edges are secondary,
// and the accent ramp starts from the link color with a fixed 6-hue rotation.
@interface SPDFMarkdownDiagramPalette : NSObject
@property(nonatomic, readonly) NSColor* paperColor;
@property(nonatomic, readonly) NSColor* nodeFillColor;
@property(nonatomic, readonly) NSColor* nodeStrokeColor;
@property(nonatomic, readonly) NSColor* textColor;
@property(nonatomic, readonly) NSColor* secondaryColor;
@property(nonatomic, readonly) NSColor* accentColor;
@property(nonatomic, readonly) NSColor* criticalColor;
@property(nonatomic, readonly, copy) NSArray<NSColor*>* accentRamp;  // 6 categorical colors
+ (instancetype)paletteForVariant:(SPDFMarkdownThemeVariant)variant;
@end

// Shared line utilities (SPDFMarkdownDiagramModel.mm).
FOUNDATION_EXPORT NSArray<NSString*>* SPDFMarkdownDiagramSignificantLines(NSString* source);
FOUNDATION_EXPORT NSString* SPDFMarkdownDiagramTrim(NSString* string);
FOUNDATION_EXPORT NSString* SPDFMarkdownDiagramCleanLabel(NSString* label);

// Text helpers shared by every rasterizer (SPDFMarkdownDiagramModel.mm).
FOUNDATION_EXPORT NSSize SPDFMarkdownDiagramMeasureText(NSString* text, NSFont* font, CGFloat maximumWidth);
FOUNDATION_EXPORT void SPDFMarkdownDiagramDrawText(NSString* text, NSRect rect, NSFont* font, NSColor* color,
                                                   NSTextAlignment alignment);
// 2x bitmap canvas: `draw` runs in a flipped (y-down), point-scaled context.
// Returns nil when either bitmap axis would exceed the raster budget.
FOUNDATION_EXPORT NSImage* _Nullable SPDFMarkdownDiagramCreateCanvas(NSSize logicalSize,
                                                                     void (NS_NOESCAPE ^ draw)(void));

// Parsers. Every parser returns nil on malformed or over-budget input.
FOUNDATION_EXPORT SPDFMarkdownDiagramGraph* _Nullable SPDFMarkdownDiagramParseMermaidFlowchart(NSString* source);
FOUNDATION_EXPORT SPDFMarkdownDiagramGraph* _Nullable SPDFMarkdownDiagramParseFlowFence(NSString* source);
FOUNDATION_EXPORT SPDFMarkdownDiagramGraph* _Nullable SPDFMarkdownDiagramParseMermaidState(NSString* source);
FOUNDATION_EXPORT SPDFMarkdownDiagramGraph* _Nullable SPDFMarkdownDiagramParseMermaidClass(NSString* source);
FOUNDATION_EXPORT SPDFMarkdownDiagramSequence* _Nullable SPDFMarkdownDiagramParseSequence(NSString* source,
                                                                                          BOOL mermaidSyntax);
FOUNDATION_EXPORT SPDFMarkdownDiagramPie* _Nullable SPDFMarkdownDiagramParsePie(NSString* source);
FOUNDATION_EXPORT SPDFMarkdownDiagramGantt* _Nullable SPDFMarkdownDiagramParseGantt(NSString* source);

// Layered layout: ranks via longest path in flow direction (back edges from a
// DFS sweep are ignored for ranking), a few barycenter ordering passes, then
// grid coordinates with generous gaps. Node frames must carry their measured
// sizes on entry; on success every frame origin is set and *outSize holds the
// content bounds. Returns NO when `deadline` (absolute time) passes mid-work.
FOUNDATION_EXPORT BOOL SPDFMarkdownDiagramLayoutGraph(SPDFMarkdownDiagramGraph* graph, CGFloat nodeGap,
                                                      CGFloat rankGap, CFAbsoluteTime deadline, NSSize* outSize);

// Rasterizers: measured+laid-out models -> 2x bitmap + logical size, or nil
// when the raster budget is exceeded. fontScale scales every font and gap.
FOUNDATION_EXPORT SPDFMarkdownDiagramImage* _Nullable SPDFMarkdownDiagramRasterizeGraph(
    SPDFMarkdownDiagramGraph* graph, CGFloat contentWidth, CGFloat fontScale, SPDFMarkdownDiagramPalette* palette,
    CFAbsoluteTime deadline);
FOUNDATION_EXPORT SPDFMarkdownDiagramImage* _Nullable SPDFMarkdownDiagramRasterizeSequence(
    SPDFMarkdownDiagramSequence* sequence, CGFloat contentWidth, CGFloat fontScale,
    SPDFMarkdownDiagramPalette* palette);
FOUNDATION_EXPORT SPDFMarkdownDiagramImage* _Nullable SPDFMarkdownDiagramRasterizePie(
    SPDFMarkdownDiagramPie* pie, CGFloat contentWidth, CGFloat fontScale, SPDFMarkdownDiagramPalette* palette);
FOUNDATION_EXPORT SPDFMarkdownDiagramImage* _Nullable SPDFMarkdownDiagramRasterizeGantt(
    SPDFMarkdownDiagramGantt* gantt, CGFloat contentWidth, CGFloat fontScale, SPDFMarkdownDiagramPalette* palette);

// SPDFMarkdownDiagram.mm internal constructor, exposed for the rasterizers.
FOUNDATION_EXPORT SPDFMarkdownDiagramImage* SPDFMarkdownDiagramImageMake(NSImage* image, NSSize logicalSize);

NS_ASSUME_NONNULL_END
