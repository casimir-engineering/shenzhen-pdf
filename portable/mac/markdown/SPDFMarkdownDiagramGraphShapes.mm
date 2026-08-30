#import "SPDFMarkdownDiagramInternal.h"

// Vector emitter for the flowchart-family graphs (flowchart, state, class,
// flow fences). Measures node sizes with the scaled body font, runs the
// layered layout under its deadline, then emits node shapes, elbow edges with
// arrowheads, and chip-backed edge labels as geometry plus positioned text.

static const CGFloat kSPDFDiagramGraphMargin = 20;
static const CGFloat kSPDFDiagramLabelMaxWidth = 170;
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

static void SPDFDiagramMeasureNode(SPDFMarkdownDiagramNode* node, SPDFDiagramGraphFonts fonts, CGFloat scale) {
    CGFloat maxWidth = kSPDFDiagramLabelMaxWidth * scale;
    if (node.shape == SPDFMarkdownDiagramNodeShapeStartDot || node.shape == SPDFMarkdownDiagramNodeShapeEndDot) {
        CGFloat diameter = 14 * scale;
        node.frame = NSMakeRect(0, 0, diameter, diameter);
        return;
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
        return;
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
}

static NSValue* SPDFPoint(CGFloat x, CGFloat y) { return [NSValue valueWithPoint:NSMakePoint(x, y)]; }

static void SPDFDiagramAddNodeShape(SPDFMarkdownDiagramCanvas* canvas, SPDFMarkdownDiagramNode* node,
                                    CGFloat scale) {
    NSRect frame = node.frame;
    BOOL accentDot = node.shape == SPDFMarkdownDiagramNodeShapeStartDot;
    SPDFMarkdownDiagramRole fill = accentDot ? SPDFMarkdownDiagramRoleSecondary
                                             : SPDFMarkdownDiagramRoleNodeFill;
    SPDFMarkdownDiagramRole stroke = SPDFMarkdownDiagramRoleNodeStroke;
    switch (node.shape) {
        case SPDFMarkdownDiagramNodeShapeRound:
            [canvas addRect:frame radius:8 * scale fill:fill stroke:stroke width:1];
            return;
        case SPDFMarkdownDiagramNodeShapeStadium:
            [canvas addRect:frame radius:NSHeight(frame) / 2 fill:fill stroke:stroke width:1];
            return;
        case SPDFMarkdownDiagramNodeShapeCircle:
        case SPDFMarkdownDiagramNodeShapeStartDot:
        case SPDFMarkdownDiagramNodeShapeEndDot:
            [canvas addEllipse:frame fill:fill stroke:stroke width:1];
            return;
        case SPDFMarkdownDiagramNodeShapeDiamond:
            [canvas addPolygon:@[
                SPDFPoint(NSMidX(frame), NSMinY(frame)), SPDFPoint(NSMaxX(frame), NSMidY(frame)),
                SPDFPoint(NSMidX(frame), NSMaxY(frame)), SPDFPoint(NSMinX(frame), NSMidY(frame))
            ]
                          fill:fill
                        stroke:stroke
                         width:1];
            return;
        case SPDFMarkdownDiagramNodeShapeParallelogram: {
            CGFloat slant = 10 * scale;
            [canvas addPolygon:@[
                SPDFPoint(NSMinX(frame) + slant, NSMinY(frame)), SPDFPoint(NSMaxX(frame), NSMinY(frame)),
                SPDFPoint(NSMaxX(frame) - slant, NSMaxY(frame)), SPDFPoint(NSMinX(frame), NSMaxY(frame))
            ]
                          fill:fill
                        stroke:stroke
                         width:1];
            return;
        }
        case SPDFMarkdownDiagramNodeShapeRect:
        case SPDFMarkdownDiagramNodeShapeSubroutine:
        case SPDFMarkdownDiagramNodeShapeClassBox:
        default:
            [canvas addRect:frame radius:0 fill:fill stroke:stroke width:1];
            return;
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
                               SPDFDiagramGraphFonts fonts, CGFloat scale) {
    SPDFDiagramAddNodeShape(canvas, node, scale);
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
            [canvas addLineFrom:NSMakePoint(x.doubleValue, NSMinY(frame))
                             to:NSMakePoint(x.doubleValue, NSMaxY(frame))
                         stroke:SPDFMarkdownDiagramRoleNodeStroke
                          width:1
                           dash:0];
        }
    }
    if (node.shape == SPDFMarkdownDiagramNodeShapeClassBox) {
        SPDFDiagramAddClassBody(canvas, node, fonts, scale);
        return;
    }
    NSSize text = SPDFMarkdownDiagramMeasureText(node.label, fonts.label, NSWidth(frame));
    [canvas addText:node.label
             inRect:NSMakeRect(NSMinX(frame) + 4, NSMidY(frame) - text.height / 2, NSWidth(frame) - 8,
                               text.height)
               font:fonts.label
               role:SPDFMarkdownDiagramRoleText
          alignment:NSTextAlignmentCenter];
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

static void SPDFDiagramAddEdge(SPDFMarkdownDiagramCanvas* canvas, SPDFMarkdownDiagramEdge* edge,
                               SPDFMarkdownDiagramGraph* graph, SPDFDiagramGraphFonts fonts, CGFloat scale) {
    SPDFMarkdownDiagramNode* from = [graph existingNodeForIdentifier:edge.fromIdentifier];
    SPDFMarkdownDiagramNode* to = [graph existingNodeForIdentifier:edge.toIdentifier];
    if (!from || !to) return;
    NSMutableArray<NSValue*>* points = [NSMutableArray array];
    NSPoint fromCenter = NSMakePoint(NSMidX(from.frame), NSMidY(from.frame));
    NSPoint toCenter = NSMakePoint(NSMidX(to.frame), NSMidY(to.frame));
    if (from == to) {
        // Self-loop: a small square detour off the node's right edge.
        CGFloat loop = 18 * scale;
        NSPoint start = NSMakePoint(NSMaxX(from.frame), NSMidY(from.frame) - 6 * scale);
        NSPoint end = NSMakePoint(NSMaxX(from.frame), NSMidY(from.frame) + 6 * scale);
        [points addObject:SPDFPoint(start.x, start.y)];
        [points addObject:SPDFPoint(start.x + loop, start.y)];
        [points addObject:SPDFPoint(end.x + loop, end.y)];
        [points addObject:SPDFPoint(end.x, end.y)];
    } else {
        BOOL forward = graph.vertical ? (NSMinY(to.frame) >= NSMaxY(from.frame))
                                      : (NSMinX(to.frame) >= NSMaxX(from.frame));
        if (graph.reversed)
            forward = graph.vertical ? (NSMaxY(to.frame) <= NSMinY(from.frame))
                                     : (NSMaxX(to.frame) <= NSMinX(from.frame));
        if (forward) {
            // Single-elbow route between facing edges of the two rank bands.
            NSPoint start, end;
            if (graph.vertical) {
                CGFloat startY = graph.reversed ? NSMinY(from.frame) : NSMaxY(from.frame);
                CGFloat endY = graph.reversed ? NSMaxY(to.frame) : NSMinY(to.frame);
                start = NSMakePoint(fromCenter.x, startY);
                end = NSMakePoint(toCenter.x, endY);
                CGFloat midY = (start.y + end.y) / 2;
                [points addObject:SPDFPoint(start.x, start.y)];
                if (fabs(start.x - end.x) > 0.5) {
                    [points addObject:SPDFPoint(start.x, midY)];
                    [points addObject:SPDFPoint(end.x, midY)];
                }
                [points addObject:SPDFPoint(end.x, end.y)];
            } else {
                CGFloat startX = graph.reversed ? NSMinX(from.frame) : NSMaxX(from.frame);
                CGFloat endX = graph.reversed ? NSMaxX(to.frame) : NSMinX(to.frame);
                start = NSMakePoint(startX, fromCenter.y);
                end = NSMakePoint(endX, toCenter.y);
                CGFloat midX = (start.x + end.x) / 2;
                [points addObject:SPDFPoint(start.x, start.y)];
                if (fabs(start.y - end.y) > 0.5) {
                    [points addObject:SPDFPoint(midX, start.y)];
                    [points addObject:SPDFPoint(midX, end.y)];
                }
                [points addObject:SPDFPoint(end.x, end.y)];
            }
        } else {
            // Same-rank and back edges keep a straight border-to-border line.
            NSPoint start = SPDFDiagramAnchor(from, toCenter);
            NSPoint end = SPDFDiagramAnchor(to, fromCenter);
            [points addObject:SPDFPoint(start.x, start.y)];
            [points addObject:SPDFPoint(end.x, end.y)];
        }
    }
    [canvas addPolyline:points
                 stroke:SPDFMarkdownDiagramRoleSecondary
                  width:edge.lineStyle == SPDFMarkdownDiagramLineStyleThick ? 2.5 : 1.2
                   dash:edge.lineStyle == SPDFMarkdownDiagramLineStyleDashed ? 4 * scale : 0];
    SPDFDiagramAddArrowHead(canvas, points.lastObject.pointValue, points[points.count - 2].pointValue, edge.head,
                            scale);
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

SPDFMarkdownDiagramLayout* SPDFMarkdownDiagramLayOutGraph(SPDFMarkdownDiagramGraph* graph, CGFloat contentWidth,
                                                          CGFloat fontScale, CFAbsoluteTime deadline) {
    CGFloat scale = fontScale > 0 ? fontScale : 1;
    SPDFDiagramGraphFonts fonts = {
        [NSFont systemFontOfSize:12 * scale],
        [NSFont systemFontOfSize:10.5 * scale],
        [NSFont systemFontOfSize:12 * scale weight:NSFontWeightSemibold],
    };
    for (SPDFMarkdownDiagramNode* node in graph.nodes) SPDFDiagramMeasureNode(node, fonts, scale);
    NSSize contentSize = NSZeroSize;
    if (!SPDFMarkdownDiagramLayoutGraph(graph, 34 * scale, 44 * scale, deadline, &contentSize)) return nil;
    // The margin used to be a drawing-time transform; with geometry as the
    // product it is folded into the node frames so every emitted point is
    // already in diagram-local space.
    CGFloat margin = kSPDFDiagramGraphMargin * scale;
    for (SPDFMarkdownDiagramNode* node in graph.nodes)
        node.frame = NSOffsetRect(node.frame, margin, margin);
    NSSize naturalSize = NSMakeSize(contentSize.width + 2 * margin, contentSize.height + 2 * margin);

    SPDFMarkdownDiagramCanvas* canvas = [SPDFMarkdownDiagramCanvas new];
    for (SPDFMarkdownDiagramEdge* edge in graph.edges) SPDFDiagramAddEdge(canvas, edge, graph, fonts, scale);
    for (SPDFMarkdownDiagramNode* node in graph.nodes) SPDFDiagramAddNode(canvas, node, fonts, scale);
    return SPDFMarkdownDiagramFinishLayout(canvas, naturalSize, contentWidth);
}
