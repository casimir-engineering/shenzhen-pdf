#import "SPDFMarkdownDiagramInternal.h"

// Deterministic vertical-flow renderer for sequence diagrams (mermaid
// sequenceDiagram and js-sequence). Actor boxes top and bottom, dashed
// lifelines, straight message arrows with the text above the line,
// self-message loops, notes, alt/opt/loop frames spanning the involved
// lifelines, and thin activation bars.

static const CGFloat kSPDFSequenceMargin = 16;
static const CGFloat kSPDFSequenceActorPadX = 14;
static const CGFloat kSPDFSequenceActorPadY = 8;
static const CGFloat kSPDFSequenceActivationWidth = 8;

typedef struct {
    NSFont* label;
    NSFont* small;
    NSFont* bold;
    CGFloat lineHeight;
    CGFloat smallLineHeight;
} SPDFSequenceFonts;

@interface SPDFSequenceFrame : NSObject
@property(nonatomic, copy) NSString* keyword;
@property(nonatomic, copy) NSString* text;
@property(nonatomic) CGFloat topY;
@property(nonatomic) CGFloat bottomY;
@property(nonatomic) NSInteger minActor;
@property(nonatomic) NSInteger maxActor;
@property(nonatomic) NSUInteger depth;
@property(nonatomic, readonly) NSMutableArray<NSNumber*>* dividerYs;
@property(nonatomic, readonly) NSMutableArray<NSString*>* dividerTexts;
@end
@implementation SPDFSequenceFrame
- (instancetype)init {
    self = [super init];
    if (self) {
        _dividerYs = [NSMutableArray array];
        _dividerTexts = [NSMutableArray array];
        _minActor = NSIntegerMax;
        _maxActor = NSIntegerMin;
    }
    return self;
}
@end

@interface SPDFSequenceBar : NSObject  // one activation bar portion
@property(nonatomic) NSInteger actor;
@property(nonatomic) CGFloat topY;
@property(nonatomic) CGFloat bottomY;
@end
@implementation SPDFSequenceBar
@end

SPDFMarkdownDiagramImage* SPDFMarkdownDiagramRasterizeSequence(SPDFMarkdownDiagramSequence* sequence,
                                                               CGFloat contentWidth, CGFloat fontScale,
                                                               SPDFMarkdownDiagramPalette* palette) {
    CGFloat scale = fontScale > 0 ? fontScale : 1;
    SPDFSequenceFonts fonts;
    fonts.label = [NSFont systemFontOfSize:12 * scale];
    fonts.small = [NSFont systemFontOfSize:10.5 * scale];
    fonts.bold = [NSFont systemFontOfSize:12 * scale weight:NSFontWeightSemibold];
    fonts.lineHeight = ceil(fonts.label.ascender - fonts.label.descender + fonts.label.leading);
    fonts.smallLineHeight = ceil(fonts.small.ascender - fonts.small.descender + fonts.small.leading);

    NSArray<NSString*>* actors = sequence.actorIdentifiers;
    NSUInteger actorCount = actors.count;
    if (!actorCount) return nil;
    NSMutableDictionary<NSString*, NSNumber*>* columns = [NSMutableDictionary dictionaryWithCapacity:actorCount];
    for (NSUInteger index = 0; index < actorCount; ++index) columns[actors[index]] = @(index);

    // Actor box sizes and column gap: wide enough for the widest message text.
    NSMutableArray<NSNumber*>* boxWidths = [NSMutableArray arrayWithCapacity:actorCount];
    CGFloat boxHeight = fonts.lineHeight + 2 * kSPDFSequenceActorPadY * scale;
    for (NSString* actor in actors) {
        CGFloat width = SPDFMarkdownDiagramMeasureText(sequence.actorLabels[actor] ?: actor, fonts.label,
                                                       200 * scale)
                            .width;
        [boxWidths addObject:@(ceil(MAX(width + 2 * kSPDFSequenceActorPadX * scale, 64 * scale)))];
    }
    CGFloat maximumTextWidth = 0;
    for (SPDFMarkdownDiagramSequenceEvent* event in sequence.events) {
        if (event.kind != SPDFMarkdownDiagramSequenceEventMessage &&
            event.kind != SPDFMarkdownDiagramSequenceEventNote)
            continue;
        CGFloat width = SPDFMarkdownDiagramMeasureText(event.text ?: @"", fonts.small, 320 * scale).width;
        maximumTextWidth = MAX(maximumTextWidth, width);
    }
    CGFloat gap = MIN(420 * scale, MAX(120 * scale, maximumTextWidth + 30 * scale));
    NSMutableArray<NSNumber*>* centers = [NSMutableArray arrayWithCapacity:actorCount];
    CGFloat x = kSPDFSequenceMargin * scale;
    for (NSUInteger index = 0; index < actorCount; ++index) {
        CGFloat halfWidth = boxWidths[index].doubleValue / 2;
        if (index == 0) x += halfWidth;
        else x += MAX(gap, halfWidth + boxWidths[index - 1].doubleValue / 2 + 20 * scale);
        [centers addObject:@(x)];
    }
    CGFloat rightEdge = centers.lastObject.doubleValue + boxWidths.lastObject.doubleValue / 2 +
                        kSPDFSequenceMargin * scale;

    // First pass: assign a y position to every event.
    CGFloat titleHeight = 0;
    if (sequence.title.length)
        titleHeight = SPDFMarkdownDiagramMeasureText(sequence.title, fonts.bold, rightEdge).height + 10 * scale;
    CGFloat topBoxY = kSPDFSequenceMargin * scale + titleHeight;
    __block CGFloat y = topBoxY + boxHeight + 16 * scale;
    NSMutableArray<SPDFSequenceFrame*>* openFrames = [NSMutableArray array];
    NSMutableArray<SPDFSequenceFrame*>* finishedFrames = [NSMutableArray array];
    NSMutableArray<SPDFSequenceBar*>* bars = [NSMutableArray array];
    NSMutableDictionary<NSNumber*, NSMutableArray<SPDFSequenceBar*>*>* openBars = [NSMutableDictionary dictionary];
    NSMutableArray<NSDictionary*>* drawables = [NSMutableArray array];  // event + geometry per drawable

    void (^touchActor)(NSInteger) = ^(NSInteger actor) {
      for (SPDFSequenceFrame* frame in openFrames) {
          frame.minActor = MIN(frame.minActor, actor);
          frame.maxActor = MAX(frame.maxActor, actor);
      }
    };
    for (SPDFMarkdownDiagramSequenceEvent* event in sequence.events) {
        switch (event.kind) {
            case SPDFMarkdownDiagramSequenceEventMessage: {
                NSInteger from = columns[event.fromIdentifier].integerValue;
                NSInteger to = columns[event.toIdentifier].integerValue;
                touchActor(from);
                touchActor(to);
                CGFloat textHeight = event.text.length
                    ? SPDFMarkdownDiagramMeasureText(event.text, fonts.small, 320 * scale).height
                    : 0;
                CGFloat lineY = y + textHeight + 4 * scale;
                [drawables addObject:@{@"event": event, @"y": @(lineY), @"textY": @(y)}];
                y = lineY + (from == to ? 16 * scale : 0) + 16 * scale;
                break;
            }
            case SPDFMarkdownDiagramSequenceEventNote: {
                NSInteger from = columns[event.fromIdentifier].integerValue;
                NSInteger to = columns[event.toIdentifier].integerValue;
                touchActor(from);
                touchActor(to);
                CGFloat noteWidth = MIN(220 * scale,
                                        SPDFMarkdownDiagramMeasureText(event.text ?: @" ", fonts.small, 200 * scale)
                                                .width +
                                            16 * scale);
                CGFloat noteHeight =
                    SPDFMarkdownDiagramMeasureText(event.text ?: @" ", fonts.small, noteWidth - 12 * scale).height +
                    10 * scale;
                [drawables addObject:@{
                    @"event": event, @"y": @(y), @"noteWidth": @(noteWidth), @"noteHeight": @(noteHeight)
                }];
                y += noteHeight + 12 * scale;
                break;
            }
            case SPDFMarkdownDiagramSequenceEventFrameBegin: {
                SPDFSequenceFrame* frame = [SPDFSequenceFrame new];
                frame.keyword = event.frameKeyword ?: @"";
                frame.text = event.text ?: @"";
                frame.topY = y;
                frame.depth = openFrames.count;
                [openFrames addObject:frame];
                y += fonts.smallLineHeight + 12 * scale;
                break;
            }
            case SPDFMarkdownDiagramSequenceEventFrameElse: {
                SPDFSequenceFrame* frame = openFrames.lastObject;
                if (frame) {
                    [frame.dividerYs addObject:@(y)];
                    [frame.dividerTexts addObject:event.text ?: @""];
                }
                y += fonts.smallLineHeight + 10 * scale;
                break;
            }
            case SPDFMarkdownDiagramSequenceEventFrameEnd: {
                SPDFSequenceFrame* frame = openFrames.lastObject;
                if (frame) {
                    [openFrames removeLastObject];
                    frame.bottomY = y;
                    if (frame.minActor > frame.maxActor) {
                        frame.minActor = 0;
                        frame.maxActor = (NSInteger)actorCount - 1;
                    }
                    [finishedFrames addObject:frame];
                }
                y += 10 * scale;
                break;
            }
            case SPDFMarkdownDiagramSequenceEventActivate: {
                NSNumber* actor = columns[event.fromIdentifier];
                if (!actor) break;
                SPDFSequenceBar* bar = [SPDFSequenceBar new];
                bar.actor = actor.integerValue;
                bar.topY = y - 6 * scale;
                NSMutableArray* stack = openBars[actor] ?: (openBars[actor] = [NSMutableArray array]);
                [stack addObject:bar];
                break;
            }
            case SPDFMarkdownDiagramSequenceEventDeactivate: {
                NSNumber* actor = columns[event.fromIdentifier];
                if (!actor) break;
                SPDFSequenceBar* bar = openBars[actor].lastObject;
                if (bar) {
                    [openBars[actor] removeLastObject];
                    bar.bottomY = y - 6 * scale;
                    if (bar.bottomY > bar.topY) [bars addObject:bar];
                }
                break;
            }
        }
    }
    CGFloat bottomBoxY = y + 6 * scale;
    for (NSMutableArray<SPDFSequenceBar*>* stack in openBars.allValues) {
        for (SPDFSequenceBar* bar in stack) {  // unterminated activations run to the bottom
            bar.bottomY = bottomBoxY - 2 * scale;
            if (bar.bottomY > bar.topY) [bars addObject:bar];
        }
    }
    NSSize naturalSize = NSMakeSize(rightEdge, bottomBoxY + boxHeight + kSPDFSequenceMargin * scale);

    NSImage* image = SPDFMarkdownDiagramCreateCanvas(naturalSize, ^{
      [palette.paperColor setFill];
      NSRectFill(NSMakeRect(0, 0, naturalSize.width, naturalSize.height));
      if (sequence.title.length) {
          SPDFMarkdownDiagramDrawText(sequence.title,
                                      NSMakeRect(0, kSPDFSequenceMargin * scale * 0.5, naturalSize.width,
                                                 titleHeight),
                                      fonts.bold, palette.textColor, NSTextAlignmentCenter);
      }
      // Lifelines.
      CGFloat dashes[] = {4 * scale, 3 * scale};
      for (NSUInteger index = 0; index < actorCount; ++index) {
          NSBezierPath* lifeline = [NSBezierPath bezierPath];
          [lifeline moveToPoint:NSMakePoint(centers[index].doubleValue, topBoxY + boxHeight)];
          [lifeline lineToPoint:NSMakePoint(centers[index].doubleValue, bottomBoxY)];
          [lifeline setLineDash:dashes count:2 phase:0];
          [palette.secondaryColor setStroke];
          [lifeline stroke];
      }
      // Activation bars over the lifelines.
      for (SPDFSequenceBar* bar in bars) {
          NSRect rect = NSMakeRect(centers[(NSUInteger)bar.actor].doubleValue -
                                       kSPDFSequenceActivationWidth * scale / 2,
                                   bar.topY, kSPDFSequenceActivationWidth * scale, bar.bottomY - bar.topY);
          [palette.nodeFillColor setFill];
          NSRectFill(rect);
          [palette.nodeStrokeColor setStroke];
          [NSBezierPath strokeRect:NSInsetRect(rect, 0.5, 0.5)];
      }
      // Frames (alt/opt/loop/par): border, label chip, else dividers.
      for (SPDFSequenceFrame* frame in finishedFrames) {
          CGFloat inset = (10 + 8 * (double)frame.depth) * scale;
          CGFloat left = centers[(NSUInteger)frame.minActor].doubleValue - gap / 2 + inset;
          CGFloat right = centers[(NSUInteger)frame.maxActor].doubleValue + gap / 2 - inset;
          left = MAX(4 * scale, left);
          right = MIN(naturalSize.width - 4 * scale, right);
          NSRect rect = NSMakeRect(left, frame.topY, right - left, frame.bottomY - frame.topY);
          [palette.secondaryColor setStroke];
          [NSBezierPath strokeRect:rect];
          if (frame.keyword.length) {
              NSSize keywordSize = SPDFMarkdownDiagramMeasureText(frame.keyword, fonts.bold, 100 * scale);
              NSRect chip = NSMakeRect(left, frame.topY, keywordSize.width + 12 * scale,
                                       fonts.smallLineHeight + 6 * scale);
              [palette.nodeFillColor setFill];
              NSRectFill(chip);
              [palette.secondaryColor setStroke];
              [NSBezierPath strokeRect:chip];
              SPDFMarkdownDiagramDrawText(frame.keyword, NSInsetRect(chip, 6 * scale, 3 * scale), fonts.bold,
                                          palette.textColor, NSTextAlignmentLeft);
              if (frame.text.length) {
                  SPDFMarkdownDiagramDrawText([NSString stringWithFormat:@"[%@]", frame.text],
                                              NSMakeRect(NSMaxX(chip) + 6 * scale, frame.topY + 3 * scale,
                                                         MAX(0, right - NSMaxX(chip) - 10 * scale),
                                                         fonts.smallLineHeight + 2),
                                              fonts.small, palette.secondaryColor, NSTextAlignmentLeft);
              }
          }
          for (NSUInteger divider = 0; divider < frame.dividerYs.count; ++divider) {
              CGFloat dividerY = frame.dividerYs[divider].doubleValue;
              NSBezierPath* line = [NSBezierPath bezierPath];
              [line moveToPoint:NSMakePoint(left, dividerY)];
              [line lineToPoint:NSMakePoint(right, dividerY)];
              [line setLineDash:dashes count:2 phase:0];
              [palette.secondaryColor setStroke];
              [line stroke];
              NSString* text = frame.dividerTexts[divider];
              if (text.length) {
                  SPDFMarkdownDiagramDrawText([NSString stringWithFormat:@"[%@]", text],
                                              NSMakeRect(left + 8 * scale, dividerY + 2 * scale, right - left,
                                                         fonts.smallLineHeight + 2),
                                              fonts.small, palette.secondaryColor, NSTextAlignmentLeft);
              }
          }
      }
      // Messages and notes.
      for (NSDictionary* drawable in drawables) {
          SPDFMarkdownDiagramSequenceEvent* event = drawable[@"event"];
          NSInteger from = columns[event.fromIdentifier].integerValue;
          NSInteger to = columns[event.toIdentifier].integerValue;
          CGFloat fromX = centers[(NSUInteger)from].doubleValue;
          CGFloat toX = centers[(NSUInteger)to].doubleValue;
          if (event.kind == SPDFMarkdownDiagramSequenceEventNote) {
              CGFloat noteWidth = [drawable[@"noteWidth"] doubleValue];
              CGFloat noteHeight = [drawable[@"noteHeight"] doubleValue];
              CGFloat noteY = [drawable[@"y"] doubleValue];
              NSRect rect;
              if (event.notePosition == SPDFMarkdownDiagramNoteLeftOf) {
                  rect = NSMakeRect(fromX - noteWidth - 10 * scale, noteY, noteWidth, noteHeight);
              } else if (event.notePosition == SPDFMarkdownDiagramNoteRightOf) {
                  rect = NSMakeRect(fromX + 10 * scale, noteY, noteWidth, noteHeight);
              } else {
                  CGFloat middle = (fromX + toX) / 2;
                  CGFloat width = MAX(noteWidth, fabs(toX - fromX) + 30 * scale);
                  rect = NSMakeRect(middle - width / 2, noteY, width, noteHeight);
              }
              rect.origin.x = MAX(2 * scale, MIN(rect.origin.x, naturalSize.width - NSWidth(rect) - 2 * scale));
              [palette.nodeFillColor setFill];
              NSRectFill(rect);
              [palette.nodeStrokeColor setStroke];
              [NSBezierPath strokeRect:NSInsetRect(rect, 0.5, 0.5)];
              SPDFMarkdownDiagramDrawText(event.text, NSInsetRect(rect, 6 * scale, 5 * scale), fonts.small,
                                          palette.textColor, NSTextAlignmentCenter);
              continue;
          }
          CGFloat lineY = [drawable[@"y"] doubleValue];
          CGFloat textY = [drawable[@"textY"] doubleValue];
          NSBezierPath* line = [NSBezierPath bezierPath];
          if (from == to) {
              CGFloat loop = 26 * scale;
              [line moveToPoint:NSMakePoint(fromX, lineY)];
              [line lineToPoint:NSMakePoint(fromX + loop, lineY)];
              [line lineToPoint:NSMakePoint(fromX + loop, lineY + 14 * scale)];
              [line lineToPoint:NSMakePoint(fromX, lineY + 14 * scale)];
          } else {
              [line moveToPoint:NSMakePoint(fromX, lineY)];
              [line lineToPoint:NSMakePoint(toX, lineY)];
          }
          line.lineWidth = 1.2;
          if (event.dashed) [line setLineDash:dashes count:2 phase:0];
          [palette.secondaryColor setStroke];
          [line stroke];
          // Arrowhead pointing at the target lifeline.
          if (event.arrowhead) {
              CGFloat tipX = from == to ? fromX : toX;
              CGFloat tipY = from == to ? lineY + 14 * scale : lineY;
              CGFloat direction = (from == to || toX < fromX) ? 1 : -1;
              CGFloat size = 7 * scale;
              NSBezierPath* head = [NSBezierPath bezierPath];
              [head moveToPoint:NSMakePoint(tipX, tipY)];
              [head lineToPoint:NSMakePoint(tipX + direction * size, tipY - size * 0.5)];
              [head lineToPoint:NSMakePoint(tipX + direction * size, tipY + size * 0.5)];
              [head closePath];
              [palette.secondaryColor setFill];
              [head fill];
          }
          if (event.text.length) {
              CGFloat left = MIN(fromX, toX);
              CGFloat width = from == to ? 280 * scale : fabs(toX - fromX);
              SPDFMarkdownDiagramDrawText(event.text,
                                          NSMakeRect(from == to ? fromX + 32 * scale : left, textY, width,
                                                     lineY - textY),
                                          fonts.small, palette.textColor,
                                          from == to ? NSTextAlignmentLeft : NSTextAlignmentCenter);
          }
      }
      // Actor boxes, top and bottom.
      for (NSUInteger index = 0; index < actorCount; ++index) {
          CGFloat centerX = centers[index].doubleValue;
          CGFloat width = boxWidths[index].doubleValue;
          NSString* label = sequence.actorLabels[actors[index]] ?: actors[index];
          for (NSUInteger position = 0; position < 2; ++position) {
              NSRect rect = NSMakeRect(centerX - width / 2, position == 0 ? topBoxY : bottomBoxY, width, boxHeight);
              NSBezierPath* box = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:5 * scale yRadius:5 * scale];
              [palette.nodeFillColor setFill];
              [box fill];
              [palette.nodeStrokeColor setStroke];
              [box stroke];
              SPDFMarkdownDiagramDrawText(label,
                                          NSMakeRect(NSMinX(rect), NSMidY(rect) - fonts.lineHeight / 2,
                                                     NSWidth(rect), fonts.lineHeight + 2),
                                          fonts.label, palette.textColor, NSTextAlignmentCenter);
          }
      }
    });
    if (!image) return nil;
    CGFloat fit = contentWidth > 0 ? MIN(1.0, contentWidth / naturalSize.width) : 1.0;
    return SPDFMarkdownDiagramImageMake(image, NSMakeSize(floor(naturalSize.width * fit),
                                                          floor(naturalSize.height * fit)));
}
