#import "SPDFMarkdownDiagramInternal.h"

// Vector emitter for the flowchart-family graphs (flowchart, state, class,
// flow fences). Measures node sizes with the scaled body font, runs the
// layered layout under its deadline, then emits node shapes, elbow edges with
// arrowheads, and chip-backed edge labels as geometry plus positioned text.

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

// Border anchor: where the segment toward `toward` leaves the node's frame.
static NSPoint SPDFDiagramAnchor(SPDFMarkdownDiagramNode* node, NSPoint toward) {
    NSRect frame = node.frame;
    NSPoint center = NSMakePoint(NSMidX(frame), NSMidY(frame));
    CGFloat dx = toward.x - center.x;
    CGFloat dy = toward.y - center.y;
    if (fabs(dx) < 0.001 && fabs(dy) < 0.001) return center;
    CGFloat scaleX = fabs(dx) > 0.001 ? (NSWidth(frame) / 2) / fabs(dx) : CGFLOAT_MAX;
    CGFloat scaleY = fabs(dy) > 0.001 ? (NSHeight(frame) / 2) / fabs(dy) : CGFLOAT_MAX;
    CGFloat scale = MIN(scaleX, scaleY);
    return NSMakePoint(center.x + dx * scale, center.y + dy * scale);
}

static void SPDFDiagramAddArrowHead(SPDFMarkdownDiagramCanvas* canvas, NSPoint tip, NSPoint fromDirection,
                                    SPDFMarkdownDiagramArrowHead head, CGFloat scale) {
    if (head == SPDFMarkdownDiagramArrowHeadNone) return;
    CGFloat dx = tip.x - fromDirection.x;
    CGFloat dy = tip.y - fromDirection.y;
    CGFloat length = hypot(dx, dy);
    if (length < 0.001) return;
    dx /= length;
    dy /= length;
    BOOL diamond = head == SPDFMarkdownDiagramArrowHeadFilledDiamond ||
                   head == SPDFMarkdownDiagramArrowHeadHollowDiamond;
    CGFloat size = (head == SPDFMarkdownDiagramArrowHeadArrow ? 7 : 9) * scale;
    NSPoint back = NSMakePoint(tip.x - dx * size, tip.y - dy * size);
    NSMutableArray<NSValue*>* points = [NSMutableArray arrayWithCapacity:4];
    [points addObject:SPDFPoint(tip.x, tip.y)];
    [points addObject:SPDFPoint(back.x - dy * size * 0.5, back.y + dx * size * 0.5)];
    if (diamond) [points addObject:SPDFPoint(tip.x - dx * size * 2, tip.y - dy * size * 2)];
    [points addObject:SPDFPoint(back.x + dy * size * 0.5, back.y - dx * size * 0.5)];
    BOOL hollow = head == SPDFMarkdownDiagramArrowHeadHollowTriangle ||
                  head == SPDFMarkdownDiagramArrowHeadHollowDiamond;
    [canvas addPolygon:points
                  fill:hollow ? SPDFMarkdownDiagramRolePaper : SPDFMarkdownDiagramRoleSecondary
                stroke:SPDFMarkdownDiagramRoleSecondary
                 width:1];
}

// A smooth curve through `waypoints`, sampled into a polyline. Each span is a
// cubic Bezier whose two control points sit on the FLOW axis, half a span
// apart: that makes the path leave and land perpendicular to a node's border,
// keeps it monotone along the flow axis (so a fan-out never loops back over
// its own source anchor), and joins spans with a matching tangent, so a
// rank-skipping route reads as one continuous wave. The shape vocabulary has
// no curve primitive and does not need one -- at this density the sampled path
// IS the curve for screen, print and PDF export alike, and two edges that
// cross stay traceable instead of collapsing onto a shared right-angle trunk.
static NSArray<NSValue*>* SPDFDiagramCurveThrough(NSArray<NSValue*>* waypoints, BOOL vertical) {
    if (waypoints.count < 2) return waypoints;
    const NSUInteger samples = 8;
    NSMutableArray<NSValue*>* path = [NSMutableArray arrayWithCapacity:(waypoints.count - 1) * samples + 1];
    [path addObject:waypoints.firstObject];
    for (NSUInteger index = 0; index + 1 < waypoints.count; ++index) {
        NSPoint a = waypoints[index].pointValue, d = waypoints[index + 1].pointValue;
        CGFloat reach = (vertical ? (d.y - a.y) : (d.x - a.x)) / 2;
        NSPoint b = vertical ? NSMakePoint(a.x, a.y + reach) : NSMakePoint(a.x + reach, a.y);
        NSPoint c = vertical ? NSMakePoint(d.x, d.y - reach) : NSMakePoint(d.x - reach, d.y);
        if (fabs(vertical ? (d.x - a.x) : (d.y - a.y)) < 0.5) {  // already aligned: a straight run
            [path addObject:SPDFPoint(d.x, d.y)];
            continue;
        }
        for (NSUInteger step = 1; step <= samples; ++step) {
            CGFloat t = (CGFloat)step / samples, u = 1 - t;
            CGFloat w0 = u * u * u, w1 = 3 * u * u * t, w2 = 3 * u * t * t, w3 = t * t * t;
            [path addObject:SPDFPoint(w0 * a.x + w1 * b.x + w2 * c.x + w3 * d.x,
                                      w0 * a.y + w1 * b.y + w2 * c.y + w3 * d.y)];
        }
    }
    return path;
}

static void SPDFDiagramAddEdge(SPDFMarkdownDiagramCanvas* canvas, SPDFMarkdownDiagramEdge* edge,
                               SPDFMarkdownDiagramGraph* graph, SPDFDiagramGraphFonts fonts, CGFloat scale) {
    SPDFMarkdownDiagramNode* from = [graph existingNodeForIdentifier:edge.fromIdentifier];
    SPDFMarkdownDiagramNode* to = [graph existingNodeForIdentifier:edge.toIdentifier];
    if (!from || !to) return;
    NSArray<NSValue*>* points = nil;
    NSPoint fromCenter = NSMakePoint(NSMidX(from.frame), NSMidY(from.frame));
    NSPoint toCenter = NSMakePoint(NSMidX(to.frame), NSMidY(to.frame));
    if (from == to) {
        // Self-loop: a small square detour off the node's right edge.
        CGFloat loop = 18 * scale;
        NSPoint start = NSMakePoint(NSMaxX(from.frame), NSMidY(from.frame) - 6 * scale);
        NSPoint end = NSMakePoint(NSMaxX(from.frame), NSMidY(from.frame) + 6 * scale);
        points = @[
            SPDFPoint(start.x, start.y), SPDFPoint(start.x + loop, start.y),
            SPDFPoint(end.x + loop, end.y), SPDFPoint(end.x, end.y)
        ];
    } else {
        // Which way the edge runs is read off the finished geometry, so BT/RL
        // (mirrored coordinates) and a BACK edge (target in an earlier rank)
        // are the same case: leave the source's downstream border, land on the
        // target's facing one.
        BOOL vertical = graph.vertical;
        CGFloat fromLow = vertical ? NSMinY(from.frame) : NSMinX(from.frame);
        CGFloat fromHigh = vertical ? NSMaxY(from.frame) : NSMaxX(from.frame);
        CGFloat toLow = vertical ? NSMinY(to.frame) : NSMinX(to.frame);
        CGFloat toHigh = vertical ? NSMaxY(to.frame) : NSMaxX(to.frame);
        if (toLow >= fromHigh || toHigh <= fromLow) {
            BOOL rising = toLow >= fromHigh;
            CGFloat startMain = rising ? fromHigh : fromLow;
            CGFloat endMain = rising ? toLow : toHigh;
            NSPoint start = vertical ? NSMakePoint(fromCenter.x, startMain)
                                     : NSMakePoint(startMain, fromCenter.y);
            NSPoint end = vertical ? NSMakePoint(toCenter.x, endMain) : NSMakePoint(endMain, toCenter.y);
            // The layout reserved a bend point per rank a long edge skips; the
            // curve threads them, so it never cuts through a column it passes.
            NSMutableArray<NSValue*>* waypoints = [NSMutableArray arrayWithObject:SPDFPoint(start.x, start.y)];
            [waypoints addObjectsFromArray:edge.routePoints ?: @[]];
            [waypoints addObject:SPDFPoint(end.x, end.y)];
            points = SPDFDiagramCurveThrough(waypoints, vertical);
        } else {
            // Overlapping bands (same rank) keep a straight border-to-border line.
            NSPoint start = SPDFDiagramAnchor(from, toCenter);
            NSPoint end = SPDFDiagramAnchor(to, fromCenter);
            points = @[ SPDFPoint(start.x, start.y), SPDFPoint(end.x, end.y) ];
        }
    }
    [canvas addPolyline:points
                 stroke:SPDFMarkdownDiagramRoleSecondary
                  width:edge.lineStyle == SPDFMarkdownDiagramLineStyleThick ? 2.5 : 1.2
                   dash:edge.lineStyle == SPDFMarkdownDiagramLineStyleDashed ? 4 * scale : 0];
    SPDFDiagramAddArrowHead(canvas, points.lastObject.pointValue, points[points.count - 2].pointValue, edge.head,
                            scale);
    // `<-->`: the same head, pointing back out of the `from` node.
    SPDFDiagramAddArrowHead(canvas, points.firstObject.pointValue, points[1].pointValue, edge.tail, scale);
    if (edge.label.length) {
        // Label chip at the path midpoint, backed with paper so the text stays
        // readable where it crosses the line.
        NSPoint a = points[(points.count - 1) / 2].pointValue;
        NSPoint b = points[(points.count - 1) / 2 + (points.count > 1 ? 1 : 0)].pointValue;
        NSPoint middle = NSMakePoint((a.x + b.x) / 2, (a.y + b.y) / 2);
        NSSize text = SPDFMarkdownDiagramMeasureText(edge.label, fonts.small, 150 * scale);
        NSRect chip = NSMakeRect(middle.x - text.width / 2 - 4, middle.y - text.height / 2 - 2, text.width + 8,
                                 text.height + 4);
        [canvas addRect:chip
                 radius:4
                   fill:SPDFMarkdownDiagramRolePaper
                 stroke:SPDFMarkdownDiagramRoleNone
                  width:0];
        [canvas addText:edge.label
                 inRect:NSInsetRect(chip, 4, 2)
                   font:fonts.small
                   role:SPDFMarkdownDiagramRoleSecondary
              alignment:NSTextAlignmentCenter];
    }
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
    for (SPDFMarkdownDiagramEdge* edge in graph.edges) SPDFDiagramAddEdge(canvas, edge, graph, fonts, scale);
    for (SPDFMarkdownDiagramNode* node in graph.nodes) SPDFDiagramAddNode(canvas, node, graph, fonts, scale);
    return SPDFMarkdownDiagramFinishLayout(canvas, natural, contentBox);
}
