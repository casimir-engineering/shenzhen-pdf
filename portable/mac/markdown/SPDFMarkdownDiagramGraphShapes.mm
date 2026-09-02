#import "SPDFMarkdownDiagramInternal.h"

// Vector emitter for the flowchart-family graphs (flowchart, state, class,
// flow fences). Measures node sizes with the scaled body font, runs the
// layered layout under its deadline (reflowing labels narrower when the page
// box would otherwise shrink the drawing below the legibility floor), then emits
// the node shapes. Edge geometry is its own concern: see
// SPDFMarkdownDiagramGraphEdges.mm.

static const CGFloat kSPDFDiagramGraphMargin = 20;
static const CGFloat kSPDFDiagramLabelMaxWidth = 170;
// Narrower label wraps the emitter is allowed to fall back to when the page box
// would otherwise shrink the drawing below the legibility floor. Tightening the
// wrap trades WIDTH for HEIGHT (a node's text takes more lines), which is
// exactly the trade a wide flowchart needs on a portrait page. Ordered
// widest-first, and the first entry is the ordinary wrap, so a diagram that
// already fits costs nothing and comes out byte for byte as it did before.
static const CGFloat kSPDFDiagramLabelWrapLadder[] = {kSPDFDiagramLabelMaxWidth, 130, 100, 76};
static const CGFloat kSPDFDiagramNodePaddingX = 13;
static const CGFloat kSPDFDiagramNodePaddingY = 8;
static const CGFloat kSPDFDiagramClassGutter = 4;

typedef struct {
    NSFont* label;
    NSFont* small;
    NSFont* bold;
} SPDFDiagramGraphFonts;

// A classDiagram box shows ONLY the compartments it has members for: a class
// with no attributes and no methods is a single named box, and a class with
// members on one side gets exactly one extra compartment. Empty strips are
// never drawn.
static NSArray<NSArray<NSString*>*>* SPDFDiagramClassCompartments(SPDFMarkdownDiagramNode* node) {
    NSMutableArray<NSArray<NSString*>*>* compartments = [NSMutableArray arrayWithCapacity:2];
    if (node.memberAttributes.count) [compartments addObject:node.memberAttributes];
    if (node.memberMethods.count) [compartments addObject:node.memberMethods];
    return compartments;
}

// Sizes one node's box for a given label wrap. Returns the width the node's own
// TEXT actually took, so the reflow search can tell whether a narrower wrap
// could still change anything (a cap at or above the widest text is a no-op).
static CGFloat SPDFDiagramMeasureNode(SPDFMarkdownDiagramNode* node, SPDFDiagramGraphFonts fonts, CGFloat scale,
                                      CGFloat labelWrap) {
    CGFloat maxWidth = labelWrap * scale;
    if (node.shape == SPDFMarkdownDiagramNodeShapeStartDot || node.shape == SPDFMarkdownDiagramNodeShapeEndDot) {
        CGFloat diameter = 14 * scale;
        node.frame = NSMakeRect(0, 0, diameter, diameter);
        return 0;
    }
    if (node.shape == SPDFMarkdownDiagramNodeShapeClassBox) {
        CGFloat width = SPDFMarkdownDiagramMeasureText(node.label, fonts.bold, maxWidth).width;
        CGFloat lineHeight = SPDFMarkdownDiagramLineHeight(fonts.small);
        NSArray<NSArray<NSString*>*>* compartments = SPDFDiagramClassCompartments(node);
        for (NSArray<NSString*>* members in compartments)
            for (NSString* member in members)
                width = MAX(width, SPDFMarkdownDiagramMeasureText(member, fonts.small, 320 * scale).width);
        CGFloat titleHeight = SPDFMarkdownDiagramMeasureText(node.label.length ? node.label : @"X", fonts.bold,
                                                             maxWidth)
                                  .height;
        CGFloat height = titleHeight + 2 * kSPDFDiagramNodePaddingY * scale;
        // Each PRESENT compartment adds its divider gutter above and below its
        // member lines; an absent one adds nothing at all.
        for (NSArray<NSString*>* members in compartments)
            height += 2 * kSPDFDiagramClassGutter * scale + members.count * lineHeight;
        node.frame = NSMakeRect(0, 0, ceil(width + 2 * kSPDFDiagramNodePaddingX * scale), ceil(height));
        return width;
    }
    NSSize text = SPDFMarkdownDiagramMeasureText(node.label.length ? node.label : @" ", fonts.label, maxWidth);
    CGFloat width = text.width + 2 * kSPDFDiagramNodePaddingX * scale;
    CGFloat height = text.height + 2 * kSPDFDiagramNodePaddingY * scale;
    if (node.shape == SPDFMarkdownDiagramNodeShapeDiamond) {
        // The label must fit the inscribed half-size box of the rhombus.
        width = text.width * 1.9 + 14 * scale;
        height = text.height * 1.9 + 14 * scale;
    } else if (node.shape == SPDFMarkdownDiagramNodeShapeCircle) {
        CGFloat diameter = MAX(width, height) + 6 * scale;
        width = diameter;
        height = diameter;
    } else if (node.shape == SPDFMarkdownDiagramNodeShapeParallelogram) {
        width += 16 * scale;  // room for the slanted sides
    }
    node.frame = NSMakeRect(0, 0, ceil(MAX(width, 34 * scale)), ceil(MAX(height, 26 * scale)));
    return text.width;
}

static NSValue* SPDFPoint(CGFloat x, CGFloat y) { return [NSValue valueWithPoint:NSMakePoint(x, y)]; }

// Author `classDef` colors ride on the shape, not on its role: the layout stays
// theme-independent and each draw target resolves them for the variant it
// paints with (see SPDFMarkdownDiagramAuthorColor).
static void SPDFDiagramTintShape(SPDFMarkdownDiagramShape* shape, SPDFMarkdownDiagramNodeStyle* style) {
    if (!shape || !style) return;
    shape.authorFillColor = style.fillColor;
    shape.authorStrokeColor = style.strokeColor;
}

static SPDFMarkdownDiagramShape* SPDFDiagramAddNodeShape(SPDFMarkdownDiagramCanvas* canvas,
                                                         SPDFMarkdownDiagramNode* node, CGFloat scale) {
    NSRect frame = node.frame;
    BOOL accentDot = node.shape == SPDFMarkdownDiagramNodeShapeStartDot;
    SPDFMarkdownDiagramRole fill = accentDot ? SPDFMarkdownDiagramRoleSecondary
                                             : SPDFMarkdownDiagramRoleNodeFill;
    SPDFMarkdownDiagramRole stroke = SPDFMarkdownDiagramRoleNodeStroke;
    switch (node.shape) {
        case SPDFMarkdownDiagramNodeShapeRound:
            return [canvas addRect:frame radius:8 * scale fill:fill stroke:stroke width:1];
        case SPDFMarkdownDiagramNodeShapeStadium:
            return [canvas addRect:frame radius:NSHeight(frame) / 2 fill:fill stroke:stroke width:1];
        case SPDFMarkdownDiagramNodeShapeCircle:
        case SPDFMarkdownDiagramNodeShapeStartDot:
        case SPDFMarkdownDiagramNodeShapeEndDot:
            return [canvas addEllipse:frame fill:fill stroke:stroke width:1];
        case SPDFMarkdownDiagramNodeShapeDiamond:
            return [canvas addPolygon:@[
                SPDFPoint(NSMidX(frame), NSMinY(frame)), SPDFPoint(NSMaxX(frame), NSMidY(frame)),
                SPDFPoint(NSMidX(frame), NSMaxY(frame)), SPDFPoint(NSMinX(frame), NSMidY(frame))
            ]
                                 fill:fill
                               stroke:stroke
                                width:1];
        case SPDFMarkdownDiagramNodeShapeParallelogram: {
            CGFloat slant = 10 * scale;
            return [canvas addPolygon:@[
                SPDFPoint(NSMinX(frame) + slant, NSMinY(frame)), SPDFPoint(NSMaxX(frame), NSMinY(frame)),
                SPDFPoint(NSMaxX(frame) - slant, NSMaxY(frame)), SPDFPoint(NSMinX(frame), NSMaxY(frame))
            ]
                                 fill:fill
                               stroke:stroke
                                width:1];
        }
        case SPDFMarkdownDiagramNodeShapeRect:
        case SPDFMarkdownDiagramNodeShapeSubroutine:
        case SPDFMarkdownDiagramNodeShapeClassBox:
        default:
            return [canvas addRect:frame radius:0 fill:fill stroke:stroke width:1];
    }
}

static void SPDFDiagramAddClassBody(SPDFMarkdownDiagramCanvas* canvas, SPDFMarkdownDiagramNode* node,
                                    SPDFDiagramGraphFonts fonts, CGFloat scale) {
    NSRect frame = node.frame;
    CGFloat lineHeight = SPDFMarkdownDiagramLineHeight(fonts.small);
    CGFloat titleHeight =
        SPDFMarkdownDiagramMeasureText(node.label.length ? node.label : @"X", fonts.bold, NSWidth(frame)).height;
    CGFloat y = NSMinY(frame) + kSPDFDiagramNodePaddingY * scale;
    [canvas addText:node.label
             inRect:NSMakeRect(NSMinX(frame), y, NSWidth(frame), titleHeight)
               font:fonts.bold
               role:SPDFMarkdownDiagramRoleText
          alignment:NSTextAlignmentCenter];
    y += titleHeight + kSPDFDiagramNodePaddingY * scale;
    CGFloat textX = NSMinX(frame) + kSPDFDiagramNodePaddingX * scale;
    CGFloat textWidth = NSWidth(frame) - 2 * kSPDFDiagramNodePaddingX * scale;
    for (NSArray<NSString*>* members in SPDFDiagramClassCompartments(node)) {
        [canvas addLineFrom:NSMakePoint(NSMinX(frame), y)
                         to:NSMakePoint(NSMaxX(frame), y)
                     stroke:SPDFMarkdownDiagramRoleNodeStroke
                      width:1
                       dash:0];
        y += kSPDFDiagramClassGutter * scale;
        for (NSString* member in members) {
            [canvas addText:member
                     inRect:NSMakeRect(textX, y, textWidth, lineHeight)
                       font:fonts.small
                       role:SPDFMarkdownDiagramRoleText
                  alignment:NSTextAlignmentLeft];
            y += lineHeight;
        }
        y += kSPDFDiagramClassGutter * scale;
    }
}

static void SPDFDiagramAddNode(SPDFMarkdownDiagramCanvas* canvas, SPDFMarkdownDiagramNode* node,
                               SPDFMarkdownDiagramGraph* graph, SPDFDiagramGraphFonts fonts, CGFloat scale) {
    SPDFMarkdownDiagramNodeStyle* style = [graph styleForNode:node];
    SPDFDiagramTintShape(SPDFDiagramAddNodeShape(canvas, node, scale), style);
    NSRect frame = node.frame;
    if (node.shape == SPDFMarkdownDiagramNodeShapeEndDot) {
        [canvas addEllipse:NSInsetRect(frame, 3.5 * scale, 3.5 * scale)
                      fill:SPDFMarkdownDiagramRoleSecondary
                    stroke:SPDFMarkdownDiagramRoleNone
                     width:0];
        return;
    }
    if (node.shape == SPDFMarkdownDiagramNodeShapeStartDot) return;
    if (node.shape == SPDFMarkdownDiagramNodeShapeSubroutine) {
        CGFloat inset = 5 * scale;
        for (NSNumber* x in @[ @(NSMinX(frame) + inset), @(NSMaxX(frame) - inset) ]) {
            SPDFDiagramTintShape([canvas addLineFrom:NSMakePoint(x.doubleValue, NSMinY(frame))
                                                  to:NSMakePoint(x.doubleValue, NSMaxY(frame))
                                              stroke:SPDFMarkdownDiagramRoleNodeStroke
                                               width:1
                                                dash:0],
                                 style);
        }
    }
    if (node.shape == SPDFMarkdownDiagramNodeShapeClassBox) {
        SPDFDiagramAddClassBody(canvas, node, fonts, scale);
        return;
    }
    // A `<br/>`-broken label is several lines tall; the measured height centers
    // the whole stack on the node and addText: centers each line in the box.
    NSSize text = SPDFMarkdownDiagramMeasureText(node.label, fonts.label, NSWidth(frame) - 8);
    NSArray<SPDFMarkdownDiagramLabel*>* labels =
        [canvas addText:node.label
                 inRect:NSMakeRect(NSMinX(frame) + 4, NSMidY(frame) - text.height / 2, NSWidth(frame) - 8,
                                   text.height)
                   font:fonts.label
                   role:SPDFMarkdownDiagramRoleText
              alignment:NSTextAlignmentCenter];
    for (SPDFMarkdownDiagramLabel* label in labels) label.authorColor = style.textColor;
}

// One complete measure+layout attempt at a given label wrap. Leaves the node
// frames in CONTENT space (the diagram margin is folded in by the caller, once,
// for the attempt that actually wins) and reports the natural size the attempt
// would produce plus the widest text any node needed.
static BOOL SPDFDiagramLayOutAtWrap(SPDFMarkdownDiagramGraph* graph, SPDFDiagramGraphFonts fonts, CGFloat scale,
                                    CGFloat labelWrap, CFAbsoluteTime deadline, NSSize* outNatural,
                                    CGFloat* outWidestText) {
    CGFloat widest = 0;
    for (SPDFMarkdownDiagramNode* node in graph.nodes)
        widest = MAX(widest, SPDFDiagramMeasureNode(node, fonts, scale, labelWrap));
    if (outWidestText) *outWidestText = widest / (scale > 0 ? scale : 1);
    NSSize contentSize = NSZeroSize;
    if (!SPDFMarkdownDiagramLayoutGraph(graph, 34 * scale, 44 * scale, deadline, &contentSize)) return NO;
    CGFloat margin = kSPDFDiagramGraphMargin * scale;
    *outNatural = NSMakeSize(contentSize.width + 2 * margin, contentSize.height + 2 * margin);
    // A tighter wrap can only ever make a diagram TALLER, so an attempt that
    // walks off the per-axis dimension budget is discarded rather than allowed
    // to degrade a fence that a looser wrap renders perfectly well.
    return outNatural->width <= SPDFMarkdownDiagramMaximumDimension &&
           outNatural->height <= SPDFMarkdownDiagramMaximumDimension;
}

SPDFMarkdownDiagramLayout* SPDFMarkdownDiagramLayOutGraph(SPDFMarkdownDiagramGraph* graph, NSSize contentBox,
                                                          CGFloat fontScale, CFAbsoluteTime deadline) {
    CGFloat scale = fontScale > 0 ? fontScale : 1;
    SPDFDiagramGraphFonts fonts = {
        [NSFont systemFontOfSize:12 * scale],
        [NSFont systemFontOfSize:10.5 * scale],
        [NSFont systemFontOfSize:12 * scale weight:NSFontWeightSemibold],
    };
    // The fit the page box would impose, expressed as the label size it leaves:
    // the body font is 12 pt, so clearing the floor means fit >= 7/12.
    const CGFloat legibleFit = SPDFMarkdownDiagramLegibleLabelSize / 12.0;
    NSSize natural = NSZeroSize;
    CGFloat widestText = 0;
    if (!SPDFDiagramLayOutAtWrap(graph, fonts, scale, kSPDFDiagramLabelWrapLadder[0], deadline, &natural,
                                 &widestText))
        return nil;
    CGFloat bestWrap = kSPDFDiagramLabelWrapLadder[0];
    CGFloat bestFit = SPDFMarkdownDiagramBoxFit(natural, contentBox);
    CGFloat appliedWrap = bestWrap;
    // Reflow search. Only a diagram the box would squeeze under the floor pays
    // for it, and only wraps narrower than the widest label can change anything,
    // so the overwhelmingly common case is the single pass above. Ties keep the
    // earlier (wider-label) candidate, which makes the winner a pure function of
    // (source, box, fontScale) -- the diagram cache key.
    const NSUInteger ladderCount = sizeof(kSPDFDiagramLabelWrapLadder) / sizeof(CGFloat);
    for (NSUInteger index = 1; index < ladderCount && bestFit < legibleFit; ++index) {
        CGFloat wrap = kSPDFDiagramLabelWrapLadder[index];
        if (wrap >= widestText) continue;
        NSSize candidate = NSZeroSize;
        // A candidate that trips the shared deadline (or the dimension budget)
        // ends the search; the best COMPLETED attempt stands, and attempt zero
        // is the ordinary layout, so the outcome is never worse than before.
        if (!SPDFDiagramLayOutAtWrap(graph, fonts, scale, wrap, deadline, &candidate, NULL)) break;
        appliedWrap = wrap;
        CGFloat fit = SPDFMarkdownDiagramBoxFit(candidate, contentBox);
        if (fit <= bestFit + 0.0005) continue;
        bestFit = fit;
        bestWrap = wrap;
        natural = candidate;
    }
    // The frames on the graph belong to the LAST attempt, which is only the
    // winner when the search stopped on it.
    if (appliedWrap != bestWrap &&
        !SPDFDiagramLayOutAtWrap(graph, fonts, scale, bestWrap, deadline, &natural, NULL))
        return nil;

    // The margin used to be a drawing-time transform; with geometry as the
    // product it is folded into the node frames so every emitted point is
    // already in diagram-local space.
    CGFloat margin = kSPDFDiagramGraphMargin * scale;
    for (SPDFMarkdownDiagramNode* node in graph.nodes)
        node.frame = NSOffsetRect(node.frame, margin, margin);

    SPDFMarkdownDiagramCanvas* canvas = [SPDFMarkdownDiagramCanvas new];
    SPDFMarkdownDiagramEmitGraphEdges(canvas, graph, fonts.small, scale);
    for (SPDFMarkdownDiagramNode* node in graph.nodes) SPDFDiagramAddNode(canvas, node, graph, fonts, scale);
    return SPDFMarkdownDiagramFinishLayout(canvas, natural, contentBox);
}
