#import "SPDFMarkdownDiagramInternal.h"

// Core Graphics rasterizer for the flowchart-family graphs (flowchart, state,
// class, flow fences). Measures node sizes with the scaled body font, runs the
// layered layout under its deadline, then draws nodes, elbow edges with
// arrowheads, and chip-backed edge labels on a paper background.

static const CGFloat kSPDFDiagramGraphMargin = 20;
static const CGFloat kSPDFDiagramLabelMaxWidth = 170;
static const CGFloat kSPDFDiagramNodePaddingX = 13;
static const CGFloat kSPDFDiagramNodePaddingY = 8;

typedef struct {
    NSFont* label;
    NSFont* small;
    NSFont* bold;
} SPDFDiagramGraphFonts;

static void SPDFDiagramMeasureNode(SPDFMarkdownDiagramNode* node, SPDFDiagramGraphFonts fonts, CGFloat scale) {
    CGFloat maxWidth = kSPDFDiagramLabelMaxWidth * scale;
    if (node.shape == SPDFMarkdownDiagramNodeShapeStartDot || node.shape == SPDFMarkdownDiagramNodeShapeEndDot) {
        CGFloat diameter = 14 * scale;
        node.frame = NSMakeRect(0, 0, diameter, diameter);
        return;
    }
    if (node.shape == SPDFMarkdownDiagramNodeShapeClassBox) {
        CGFloat width = SPDFMarkdownDiagramMeasureText(node.label, fonts.bold, maxWidth).width;
        CGFloat lineHeight = ceil(fonts.small.ascender - fonts.small.descender + fonts.small.leading);
        NSUInteger memberLines = node.memberAttributes.count + node.memberMethods.count;
        for (NSString* member in node.memberAttributes)
            width = MAX(width, SPDFMarkdownDiagramMeasureText(member, fonts.small, 320 * scale).width);
        for (NSString* member in node.memberMethods)
            width = MAX(width, SPDFMarkdownDiagramMeasureText(member, fonts.small, 320 * scale).width);
        CGFloat titleHeight = SPDFMarkdownDiagramMeasureText(node.label.length ? node.label : @"X", fonts.bold,
                                                             maxWidth)
                                  .height;
        CGFloat height = titleHeight + 2 * kSPDFDiagramNodePaddingY * scale;
        // Two compartments always render (empty ones stay shallow), UML-style.
        height += 2 * (4 * scale);
        height += memberLines * lineHeight + (node.memberAttributes.count ? 4 * scale : 0) +
                  (node.memberMethods.count ? 4 * scale : 0);
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

static NSBezierPath* SPDFDiagramNodePath(SPDFMarkdownDiagramNode* node, CGFloat scale) {
    NSRect frame = node.frame;
    switch (node.shape) {
        case SPDFMarkdownDiagramNodeShapeRound:
            return [NSBezierPath bezierPathWithRoundedRect:frame xRadius:8 * scale yRadius:8 * scale];
        case SPDFMarkdownDiagramNodeShapeStadium:
            return [NSBezierPath bezierPathWithRoundedRect:frame
                                                   xRadius:NSHeight(frame) / 2
                                                   yRadius:NSHeight(frame) / 2];
        case SPDFMarkdownDiagramNodeShapeCircle:
        case SPDFMarkdownDiagramNodeShapeStartDot:
        case SPDFMarkdownDiagramNodeShapeEndDot:
            return [NSBezierPath bezierPathWithOvalInRect:frame];
        case SPDFMarkdownDiagramNodeShapeDiamond: {
            NSBezierPath* path = [NSBezierPath bezierPath];
            [path moveToPoint:NSMakePoint(NSMidX(frame), NSMinY(frame))];
            [path lineToPoint:NSMakePoint(NSMaxX(frame), NSMidY(frame))];
            [path lineToPoint:NSMakePoint(NSMidX(frame), NSMaxY(frame))];
            [path lineToPoint:NSMakePoint(NSMinX(frame), NSMidY(frame))];
            [path closePath];
            return path;
        }
        case SPDFMarkdownDiagramNodeShapeParallelogram: {
            CGFloat slant = 10 * scale;
            NSBezierPath* path = [NSBezierPath bezierPath];
            [path moveToPoint:NSMakePoint(NSMinX(frame) + slant, NSMinY(frame))];
            [path lineToPoint:NSMakePoint(NSMaxX(frame), NSMinY(frame))];
            [path lineToPoint:NSMakePoint(NSMaxX(frame) - slant, NSMaxY(frame))];
            [path lineToPoint:NSMakePoint(NSMinX(frame), NSMaxY(frame))];
            [path closePath];
            return path;
        }
        case SPDFMarkdownDiagramNodeShapeRect:
        case SPDFMarkdownDiagramNodeShapeSubroutine:
        case SPDFMarkdownDiagramNodeShapeClassBox:
        default:
            return [NSBezierPath bezierPathWithRect:frame];
    }
}

static void SPDFDiagramDrawNode(SPDFMarkdownDiagramNode* node, SPDFDiagramGraphFonts fonts,
                                SPDFMarkdownDiagramPalette* palette, CGFloat scale) {
    NSBezierPath* path = SPDFDiagramNodePath(node, scale);
    path.lineWidth = 1;
    BOOL accentDot = node.shape == SPDFMarkdownDiagramNodeShapeStartDot;
    [(accentDot ? palette.secondaryColor : palette.nodeFillColor) setFill];
    [path fill];
    [palette.nodeStrokeColor setStroke];
    [path stroke];
    NSRect frame = node.frame;
    if (node.shape == SPDFMarkdownDiagramNodeShapeEndDot) {
        NSRect inner = NSInsetRect(frame, 3.5 * scale, 3.5 * scale);
        [palette.secondaryColor setFill];
        [[NSBezierPath bezierPathWithOvalInRect:inner] fill];
        return;
    }
    if (accentDot) return;
    if (node.shape == SPDFMarkdownDiagramNodeShapeSubroutine) {
        NSBezierPath* bars = [NSBezierPath bezierPath];
        CGFloat inset = 5 * scale;
        [bars moveToPoint:NSMakePoint(NSMinX(frame) + inset, NSMinY(frame))];
        [bars lineToPoint:NSMakePoint(NSMinX(frame) + inset, NSMaxY(frame))];
        [bars moveToPoint:NSMakePoint(NSMaxX(frame) - inset, NSMinY(frame))];
        [bars lineToPoint:NSMakePoint(NSMaxX(frame) - inset, NSMaxY(frame))];
        [palette.nodeStrokeColor setStroke];
        [bars stroke];
    }
    if (node.shape == SPDFMarkdownDiagramNodeShapeClassBox) {
        CGFloat lineHeight = ceil(fonts.small.ascender - fonts.small.descender + fonts.small.leading);
        CGFloat titleHeight =
            SPDFMarkdownDiagramMeasureText(node.label.length ? node.label : @"X", fonts.bold, NSWidth(frame)).height;
        CGFloat y = NSMinY(frame) + kSPDFDiagramNodePaddingY * scale;
        SPDFMarkdownDiagramDrawText(node.label,
                                    NSMakeRect(NSMinX(frame), y, NSWidth(frame), titleHeight + 2), fonts.bold,
                                    palette.textColor, NSTextAlignmentCenter);
        y += titleHeight + kSPDFDiagramNodePaddingY * scale;
        NSArray<NSArray<NSString*>*>* compartments = @[
            node.memberAttributes ?: @[], node.memberMethods ?: @[]
        ];
        CGFloat textX = NSMinX(frame) + kSPDFDiagramNodePaddingX * scale;
        CGFloat textWidth = NSWidth(frame) - 2 * kSPDFDiagramNodePaddingX * scale;
        for (NSArray<NSString*>* members in compartments) {
            [palette.nodeStrokeColor setStroke];
            [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMinX(frame), y) toPoint:NSMakePoint(NSMaxX(frame), y)];
            y += 4 * scale;
            for (NSString* member in members) {
                SPDFMarkdownDiagramDrawText(member, NSMakeRect(textX, y, textWidth, lineHeight + 2), fonts.small,
                                            palette.textColor, NSTextAlignmentLeft);
                y += lineHeight;
            }
            if (members.count) y += 4 * scale;
        }
        return;
    }
    NSSize text = SPDFMarkdownDiagramMeasureText(node.label, fonts.label, NSWidth(frame));
    NSRect textRect = NSMakeRect(NSMinX(frame) + 4, NSMidY(frame) - text.height / 2, NSWidth(frame) - 8,
                                 text.height + 2);
    SPDFMarkdownDiagramDrawText(node.label, textRect, fonts.label, palette.textColor, NSTextAlignmentCenter);
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

static void SPDFDiagramDrawArrowHead(NSPoint tip, NSPoint fromDirection, SPDFMarkdownDiagramArrowHead head,
                                     SPDFMarkdownDiagramPalette* palette, CGFloat scale) {
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
    NSPoint left = NSMakePoint(back.x - dy * size * 0.5, back.y + dx * size * 0.5);
    NSPoint right = NSMakePoint(back.x + dy * size * 0.5, back.y - dx * size * 0.5);
    NSBezierPath* path = [NSBezierPath bezierPath];
    [path moveToPoint:tip];
    [path lineToPoint:left];
    if (diamond) [path lineToPoint:NSMakePoint(tip.x - dx * size * 2, tip.y - dy * size * 2)];
    [path lineToPoint:right];
    [path closePath];
    BOOL hollow = head == SPDFMarkdownDiagramArrowHeadHollowTriangle ||
                  head == SPDFMarkdownDiagramArrowHeadHollowDiamond;
    [(hollow ? palette.paperColor : palette.secondaryColor) setFill];
    [path fill];
    [palette.secondaryColor setStroke];
    [path stroke];
}

static void SPDFDiagramDrawEdge(SPDFMarkdownDiagramEdge* edge, SPDFMarkdownDiagramGraph* graph,
                                SPDFDiagramGraphFonts fonts, SPDFMarkdownDiagramPalette* palette, CGFloat scale) {
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
        [points addObject:[NSValue valueWithPoint:start]];
        [points addObject:[NSValue valueWithPoint:NSMakePoint(start.x + loop, start.y)]];
        [points addObject:[NSValue valueWithPoint:NSMakePoint(end.x + loop, end.y)]];
        [points addObject:[NSValue valueWithPoint:end]];
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
                [points addObject:[NSValue valueWithPoint:start]];
                if (fabs(start.x - end.x) > 0.5) {
                    [points addObject:[NSValue valueWithPoint:NSMakePoint(start.x, midY)]];
                    [points addObject:[NSValue valueWithPoint:NSMakePoint(end.x, midY)]];
                }
                [points addObject:[NSValue valueWithPoint:end]];
            } else {
                CGFloat startX = graph.reversed ? NSMinX(from.frame) : NSMaxX(from.frame);
                CGFloat endX = graph.reversed ? NSMaxX(to.frame) : NSMinX(to.frame);
                start = NSMakePoint(startX, fromCenter.y);
                end = NSMakePoint(endX, toCenter.y);
                CGFloat midX = (start.x + end.x) / 2;
                [points addObject:[NSValue valueWithPoint:start]];
                if (fabs(start.y - end.y) > 0.5) {
                    [points addObject:[NSValue valueWithPoint:NSMakePoint(midX, start.y)]];
                    [points addObject:[NSValue valueWithPoint:NSMakePoint(midX, end.y)]];
                }
                [points addObject:[NSValue valueWithPoint:end]];
            }
        } else {
            // Same-rank and back edges keep a straight border-to-border line.
            [points addObject:[NSValue valueWithPoint:SPDFDiagramAnchor(from, toCenter)]];
            [points addObject:[NSValue valueWithPoint:SPDFDiagramAnchor(to, fromCenter)]];
        }
    }
    NSBezierPath* path = [NSBezierPath bezierPath];
    [path moveToPoint:points.firstObject.pointValue];
    for (NSUInteger index = 1; index < points.count; ++index) [path lineToPoint:points[index].pointValue];
    path.lineWidth = edge.lineStyle == SPDFMarkdownDiagramLineStyleThick ? 2.5 : 1.2;
    if (edge.lineStyle == SPDFMarkdownDiagramLineStyleDashed) {
        CGFloat dashes[] = {4 * scale, 3 * scale};
        [path setLineDash:dashes count:2 phase:0];
    }
    [palette.secondaryColor setStroke];
    [path stroke];
    SPDFDiagramDrawArrowHead(points.lastObject.pointValue, points[points.count - 2].pointValue, edge.head, palette,
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
        [palette.paperColor setFill];
        [[NSBezierPath bezierPathWithRoundedRect:chip xRadius:4 yRadius:4] fill];
        SPDFMarkdownDiagramDrawText(edge.label, NSInsetRect(chip, 4, 2), fonts.small, palette.secondaryColor,
                                    NSTextAlignmentCenter);
    }
}

SPDFMarkdownDiagramImage* SPDFMarkdownDiagramRasterizeGraph(SPDFMarkdownDiagramGraph* graph, CGFloat contentWidth,
                                                            CGFloat fontScale,
                                                            SPDFMarkdownDiagramPalette* palette,
                                                            CFAbsoluteTime deadline) {
    CGFloat scale = fontScale > 0 ? fontScale : 1;
    SPDFDiagramGraphFonts fonts = {
        [NSFont systemFontOfSize:12 * scale],
        [NSFont systemFontOfSize:10.5 * scale],
        [NSFont systemFontOfSize:12 * scale weight:NSFontWeightSemibold],
    };
    for (SPDFMarkdownDiagramNode* node in graph.nodes) SPDFDiagramMeasureNode(node, fonts, scale);
    NSSize contentSize = NSZeroSize;
    if (!SPDFMarkdownDiagramLayoutGraph(graph, 34 * scale, 44 * scale, deadline, &contentSize)) return nil;
    CGFloat margin = kSPDFDiagramGraphMargin * scale;
    NSSize naturalSize = NSMakeSize(contentSize.width + 2 * margin, contentSize.height + 2 * margin);
    NSImage* image = SPDFMarkdownDiagramCreateCanvas(naturalSize, ^{
      [palette.paperColor setFill];
      NSRectFill(NSMakeRect(0, 0, naturalSize.width, naturalSize.height));
      NSAffineTransform* transform = [NSAffineTransform transform];
      [transform translateXBy:margin yBy:margin];
      [transform concat];
      for (SPDFMarkdownDiagramEdge* edge in graph.edges)
          SPDFDiagramDrawEdge(edge, graph, fonts, palette, scale);
      for (SPDFMarkdownDiagramNode* node in graph.nodes) SPDFDiagramDrawNode(node, fonts, palette, scale);
    });
    if (!image) return nil;
    CGFloat fit = contentWidth > 0 ? MIN(1.0, contentWidth / naturalSize.width) : 1.0;
    return SPDFMarkdownDiagramImageMake(image, NSMakeSize(floor(naturalSize.width * fit),
                                                          floor(naturalSize.height * fit)));
}
