#import "SPDFMarkdownDiagramInternal.h"

// Layered graph layout for the flowchart family (flowchart, state, class,
// flow fences). Ranks come from a longest-path pass in the flow direction
// (back edges found by a DFS sweep are ignored for ranking, so cycles are
// safe), within-rank order from a couple of barycenter passes, and the final
// coordinates from a simple centered grid with generous gaps — nodes in one
// rank are placed sequentially, so overlap is impossible by construction.
// Every loop nest checks the wall-clock deadline and bails with NO.

static BOOL SPDFDeadlinePassed(CFAbsoluteTime deadline) {
    return CFAbsoluteTimeGetCurrent() > deadline;
}

// Depth-first back-edge detection (iterative, explicit stack).
static NSIndexSet* SPDFFindBackEdges(NSArray<SPDFMarkdownDiagramNode*>* nodes,
                                     NSArray<SPDFMarkdownDiagramEdge*>* edges,
                                     NSDictionary<NSString*, NSNumber*>* indexes,
                                     NSArray<NSArray<NSNumber*>*>* outgoing, CFAbsoluteTime deadline) {
    NSMutableIndexSet* backEdges = [NSMutableIndexSet indexSet];
    NSUInteger count = nodes.count;
    // 0 = white, 1 = gray (on stack), 2 = black.
    NSMutableData* colorData = [NSMutableData dataWithLength:count];
    uint8_t* colors = (uint8_t*)colorData.mutableBytes;
    for (NSUInteger root = 0; root < count; ++root) {
        if (colors[root] != 0) continue;
        // Stack of (node, next outgoing-edge cursor).
        NSMutableArray<NSNumber*>* stack = [NSMutableArray arrayWithObject:@(root)];
        NSMutableArray<NSNumber*>* cursors = [NSMutableArray arrayWithObject:@0];
        colors[root] = 1;
        while (stack.count) {
            if (SPDFDeadlinePassed(deadline)) return nil;
            NSUInteger node = stack.lastObject.unsignedIntegerValue;
            NSUInteger cursor = cursors.lastObject.unsignedIntegerValue;
            NSArray<NSNumber*>* edgesOut = outgoing[node];
            if (cursor >= edgesOut.count) {
                colors[node] = 2;
                [stack removeLastObject];
                [cursors removeLastObject];
                continue;
            }
            cursors[cursors.count - 1] = @(cursor + 1);
            NSUInteger edgeIndex = edgesOut[cursor].unsignedIntegerValue;
            SPDFMarkdownDiagramEdge* edge = edges[edgeIndex];
            NSNumber* targetNumber = indexes[edge.toIdentifier];
            if (!targetNumber) continue;
            NSUInteger target = targetNumber.unsignedIntegerValue;
            if (colors[target] == 1) {
                [backEdges addIndex:edgeIndex];
            } else if (colors[target] == 0) {
                colors[target] = 1;
                [stack addObject:@(target)];
                [cursors addObject:@0];
            }
        }
    }
    return backEdges;
}

BOOL SPDFMarkdownDiagramLayoutGraph(SPDFMarkdownDiagramGraph* graph, CGFloat nodeGap, CGFloat rankGap,
                                    CFAbsoluteTime deadline, NSSize* outSize) {
    NSArray<SPDFMarkdownDiagramNode*>* nodes = graph.nodes;
    NSArray<SPDFMarkdownDiagramEdge*>* edges = graph.edges;
    NSUInteger count = nodes.count;
    if (!count) return NO;
    NSMutableDictionary<NSString*, NSNumber*>* indexes = [NSMutableDictionary dictionaryWithCapacity:count];
    for (NSUInteger index = 0; index < count; ++index) indexes[nodes[index].identifier] = @(index);
    NSMutableArray<NSMutableArray<NSNumber*>*>* outgoing = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger index = 0; index < count; ++index) [outgoing addObject:[NSMutableArray array]];
    for (NSUInteger edgeIndex = 0; edgeIndex < edges.count; ++edgeIndex) {
        NSNumber* from = indexes[edges[edgeIndex].fromIdentifier];
        if (from) [outgoing[from.unsignedIntegerValue] addObject:@(edgeIndex)];
    }

    NSIndexSet* backEdges = SPDFFindBackEdges(nodes, edges, indexes, outgoing, deadline);
    if (!backEdges) return NO;

    // Longest-path ranks over the acyclic edge subset, relaxed to a fixed
    // point (bounded by node count; the subset is acyclic so it terminates
    // earlier). Rank respects edge direction: to.rank >= from.rank + 1.
    for (SPDFMarkdownDiagramNode* node in nodes) node.rank = 0;
    for (NSUInteger pass = 0; pass < count; ++pass) {
        if (SPDFDeadlinePassed(deadline)) return NO;
        BOOL changed = NO;
        for (NSUInteger edgeIndex = 0; edgeIndex < edges.count; ++edgeIndex) {
            if ([backEdges containsIndex:edgeIndex]) continue;
            SPDFMarkdownDiagramEdge* edge = edges[edgeIndex];
            NSNumber* fromNumber = indexes[edge.fromIdentifier];
            NSNumber* toNumber = indexes[edge.toIdentifier];
            if (!fromNumber || !toNumber || [fromNumber isEqualToNumber:toNumber]) continue;
            SPDFMarkdownDiagramNode* from = nodes[fromNumber.unsignedIntegerValue];
            SPDFMarkdownDiagramNode* to = nodes[toNumber.unsignedIntegerValue];
            if (to.rank < from.rank + 1) {
                to.rank = from.rank + 1;
                changed = YES;
            }
        }
        if (!changed) break;
    }

    // Bucket into ranks, keeping declaration order initially.
    NSInteger maximumRank = 0;
    for (SPDFMarkdownDiagramNode* node in nodes) maximumRank = MAX(maximumRank, node.rank);
    NSMutableArray<NSMutableArray<SPDFMarkdownDiagramNode*>*>* ranks =
        [NSMutableArray arrayWithCapacity:(NSUInteger)maximumRank + 1];
    for (NSInteger rank = 0; rank <= maximumRank; ++rank) [ranks addObject:[NSMutableArray array]];
    for (SPDFMarkdownDiagramNode* node in nodes) {
        node.order = (NSInteger)ranks[(NSUInteger)node.rank].count;
        [ranks[(NSUInteger)node.rank] addObject:node];
    }

    // Barycenter ordering: two down sweeps and two up sweeps, averaging the
    // orders of a node's neighbors on the adjacent rank.
    NSMutableArray<NSMutableArray<NSNumber*>*>* neighborsDown = [NSMutableArray arrayWithCapacity:count];
    NSMutableArray<NSMutableArray<NSNumber*>*>* neighborsUp = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger index = 0; index < count; ++index) {
        [neighborsDown addObject:[NSMutableArray array]];
        [neighborsUp addObject:[NSMutableArray array]];
    }
    for (SPDFMarkdownDiagramEdge* edge in edges) {
        NSNumber* fromNumber = indexes[edge.fromIdentifier];
        NSNumber* toNumber = indexes[edge.toIdentifier];
        if (!fromNumber || !toNumber) continue;
        [neighborsDown[fromNumber.unsignedIntegerValue] addObject:toNumber];
        [neighborsUp[toNumber.unsignedIntegerValue] addObject:fromNumber];
    }
    for (NSUInteger sweep = 0; sweep < 4; ++sweep) {
        BOOL downward = (sweep % 2) == 0;
        for (NSInteger step = 0; step <= maximumRank; ++step) {
            if (SPDFDeadlinePassed(deadline)) return NO;
            NSInteger rank = downward ? step : maximumRank - step;
            NSMutableArray<SPDFMarkdownDiagramNode*>* row = ranks[(NSUInteger)rank];
            if (row.count < 2) continue;
            NSMutableDictionary<NSString*, NSNumber*>* barycenters =
                [NSMutableDictionary dictionaryWithCapacity:row.count];
            for (SPDFMarkdownDiagramNode* node in row) {
                NSArray<NSNumber*>* neighborList =
                    (downward ? neighborsUp : neighborsDown)[indexes[node.identifier].unsignedIntegerValue];
                double sum = 0;
                NSUInteger considered = 0;
                for (NSNumber* neighborIndex in neighborList) {
                    SPDFMarkdownDiagramNode* neighbor = nodes[neighborIndex.unsignedIntegerValue];
                    sum += (double)neighbor.order;
                    ++considered;
                }
                barycenters[node.identifier] = @(considered ? sum / (double)considered : (double)node.order);
            }
            [row sortWithOptions:NSSortStable
                 usingComparator:^NSComparisonResult(SPDFMarkdownDiagramNode* left, SPDFMarkdownDiagramNode* right) {
                   double a = barycenters[left.identifier].doubleValue;
                   double b = barycenters[right.identifier].doubleValue;
                   if (a == b) return NSOrderedSame;
                   return a < b ? NSOrderedAscending : NSOrderedDescending;
                 }];
            for (NSUInteger order = 0; order < row.count; ++order) row[order].order = (NSInteger)order;
        }
    }

    // Coordinates on a centered grid. The primary axis follows the flow
    // direction; each rank band is as deep as its deepest node.
    BOOL labeledEdges = NO;
    for (SPDFMarkdownDiagramEdge* edge in edges)
        if (edge.label.length) labeledEdges = YES;
    CGFloat effectiveRankGap = rankGap + (labeledEdges ? 18 : 0);
    CGFloat totalCross = 0;
    NSMutableArray<NSNumber*>* rankCrossSizes = [NSMutableArray arrayWithCapacity:ranks.count];
    NSMutableArray<NSNumber*>* rankDepths = [NSMutableArray arrayWithCapacity:ranks.count];
    for (NSMutableArray<SPDFMarkdownDiagramNode*>* row in ranks) {
        if (SPDFDeadlinePassed(deadline)) return NO;
        CGFloat cross = 0;
        CGFloat depth = 0;
        for (SPDFMarkdownDiagramNode* node in row) {
            NSSize size = node.frame.size;
            cross += (graph.vertical ? size.width : size.height) + nodeGap;
            depth = MAX(depth, graph.vertical ? size.height : size.width);
        }
        cross = row.count ? cross - nodeGap : 0;
        [rankCrossSizes addObject:@(cross)];
        [rankDepths addObject:@(depth)];
        totalCross = MAX(totalCross, cross);
    }
    CGFloat mainOffset = 0;
    for (NSUInteger rank = 0; rank < ranks.count; ++rank) {
        CGFloat crossOffset = (totalCross - rankCrossSizes[rank].doubleValue) / 2;
        CGFloat depth = rankDepths[rank].doubleValue;
        for (SPDFMarkdownDiagramNode* node in ranks[rank]) {
            NSSize size = node.frame.size;
            CGFloat main = mainOffset + (depth - (graph.vertical ? size.height : size.width)) / 2;
            node.frame = graph.vertical ? NSMakeRect(crossOffset, main, size.width, size.height)
                                        : NSMakeRect(main, crossOffset, size.width, size.height);
            crossOffset += (graph.vertical ? size.width : size.height) + nodeGap;
        }
        mainOffset += depth + effectiveRankGap;
    }
    CGFloat mainExtent = MAX(0, mainOffset - effectiveRankGap);
    NSSize contentSize = graph.vertical ? NSMakeSize(totalCross, mainExtent) : NSMakeSize(mainExtent, totalCross);

    // BT / RL simply mirror the finished coordinates along the flow axis.
    if (graph.reversed) {
        for (SPDFMarkdownDiagramNode* node in nodes) {
            NSRect frame = node.frame;
            if (graph.vertical) frame.origin.y = contentSize.height - NSMaxY(frame);
            else frame.origin.x = contentSize.width - NSMaxX(frame);
            node.frame = frame;
        }
    }
    if (outSize) *outSize = contentSize;
    return YES;
}
