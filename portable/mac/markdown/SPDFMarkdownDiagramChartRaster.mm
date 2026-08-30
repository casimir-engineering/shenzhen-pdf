#import "SPDFMarkdownDiagramInternal.h"

// Rasterizers for mermaid `pie` (circle slices plus a side legend with
// percentages) and `gantt` (day-scaled horizontal bars in section rows with
// date ticks).

SPDFMarkdownDiagramImage* SPDFMarkdownDiagramRasterizePie(SPDFMarkdownDiagramPie* pie, CGFloat contentWidth,
                                                          CGFloat fontScale, SPDFMarkdownDiagramPalette* palette) {
    CGFloat scale = fontScale > 0 ? fontScale : 1;
    NSFont* labelFont = [NSFont systemFontOfSize:11 * scale];
    NSFont* titleFont = [NSFont systemFontOfSize:13 * scale weight:NSFontWeightSemibold];
    CGFloat lineHeight = ceil(labelFont.ascender - labelFont.descender + labelFont.leading);
    double total = 0;
    for (SPDFMarkdownDiagramPieSlice* slice in pie.slices) total += slice.value;
    if (total <= 0) return nil;

    CGFloat radius = 78 * scale;
    CGFloat margin = 16 * scale;
    CGFloat swatch = 10 * scale;
    CGFloat legendRowHeight = MAX(lineHeight, swatch) + 6 * scale;
    CGFloat legendWidth = 0;
    NSMutableArray<NSString*>* legendTexts = [NSMutableArray arrayWithCapacity:pie.slices.count];
    for (SPDFMarkdownDiagramPieSlice* slice in pie.slices) {
        NSString* text = [NSString stringWithFormat:@"%@ — %.1f%%", slice.label, slice.value / total * 100];
        [legendTexts addObject:text];
        legendWidth = MAX(legendWidth, SPDFMarkdownDiagramMeasureText(text, labelFont, 260 * scale).width);
    }
    legendWidth += swatch + 8 * scale;
    CGFloat titleHeight = pie.title.length
        ? SPDFMarkdownDiagramMeasureText(pie.title, titleFont, 400 * scale).height + 10 * scale
        : 0;
    CGFloat legendHeight = pie.slices.count * legendRowHeight;
    CGFloat bodyHeight = MAX(2 * radius, legendHeight);
    NSSize naturalSize = NSMakeSize(margin * 3 + 2 * radius + legendWidth, margin * 2 + titleHeight + bodyHeight);

    NSImage* image = SPDFMarkdownDiagramCreateCanvas(naturalSize, ^{
      [palette.paperColor setFill];
      NSRectFill(NSMakeRect(0, 0, naturalSize.width, naturalSize.height));
      if (pie.title.length) {
          SPDFMarkdownDiagramDrawText(pie.title, NSMakeRect(0, margin * 0.6, naturalSize.width, titleHeight),
                                      titleFont, palette.textColor, NSTextAlignmentCenter);
      }
      NSPoint center = NSMakePoint(margin + radius, margin + titleHeight + bodyHeight / 2);
      // Slices start at 12 o'clock and run clockwise (y-down flipped context:
      // clockwise on screen is counterclockwise in the flipped path).
      double startAngle = 90;
      for (NSUInteger index = 0; index < pie.slices.count; ++index) {
          SPDFMarkdownDiagramPieSlice* slice = pie.slices[index];
          double sweep = slice.value / total * 360.0;
          double endAngle = startAngle - sweep;
          NSBezierPath* path = [NSBezierPath bezierPath];
          [path moveToPoint:center];
          [path appendBezierPathWithArcWithCenter:center
                                           radius:radius
                                       startAngle:startAngle
                                         endAngle:endAngle
                                        clockwise:NO];
          [path closePath];
          [palette.accentRamp[index % palette.accentRamp.count] setFill];
          [path fill];
          [palette.paperColor setStroke];
          path.lineWidth = 1.5;
          [path stroke];
          startAngle = endAngle;
      }
      CGFloat legendX = margin * 2 + 2 * radius;
      CGFloat legendY = margin + titleHeight + (bodyHeight - legendHeight) / 2;
      for (NSUInteger index = 0; index < pie.slices.count; ++index) {
          NSRect swatchRect = NSMakeRect(legendX, legendY + (legendRowHeight - swatch) / 2, swatch, swatch);
          [palette.accentRamp[index % palette.accentRamp.count] setFill];
          [[NSBezierPath bezierPathWithRoundedRect:swatchRect xRadius:2 yRadius:2] fill];
          SPDFMarkdownDiagramDrawText(legendTexts[index],
                                      NSMakeRect(legendX + swatch + 8 * scale,
                                                 legendY + (legendRowHeight - lineHeight) / 2,
                                                 legendWidth, lineHeight + 2),
                                      labelFont, palette.textColor, NSTextAlignmentLeft);
          legendY += legendRowHeight;
      }
    });
    if (!image) return nil;
    CGFloat fit = contentWidth > 0 ? MIN(1.0, contentWidth / naturalSize.width) : 1.0;
    return SPDFMarkdownDiagramImageMake(image, NSMakeSize(floor(naturalSize.width * fit),
                                                          floor(naturalSize.height * fit)));
}

// --- gantt ------------------------------------------------------------------

static NSString* SPDFGanttTickLabel(NSDate* epoch, NSInteger day) {
    static NSDateFormatter* formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      formatter = [NSDateFormatter new];
      formatter.dateFormat = @"MM-dd";
      formatter.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
      formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    return [formatter stringFromDate:[epoch dateByAddingTimeInterval:(NSTimeInterval)day * 86400.0]];
}

SPDFMarkdownDiagramImage* SPDFMarkdownDiagramRasterizeGantt(SPDFMarkdownDiagramGantt* gantt, CGFloat contentWidth,
                                                            CGFloat fontScale,
                                                            SPDFMarkdownDiagramPalette* palette) {
    CGFloat scale = fontScale > 0 ? fontScale : 1;
    NSFont* labelFont = [NSFont systemFontOfSize:11 * scale];
    NSFont* smallFont = [NSFont systemFontOfSize:9.5 * scale];
    NSFont* sectionFont = [NSFont systemFontOfSize:11 * scale weight:NSFontWeightSemibold];
    NSFont* titleFont = [NSFont systemFontOfSize:13 * scale weight:NSFontWeightSemibold];
    CGFloat lineHeight = ceil(labelFont.ascender - labelFont.descender + labelFont.leading);
    if (!gantt.taskCount || !gantt.epoch) return nil;

    NSInteger minimumDay = NSIntegerMax;
    NSInteger maximumDay = NSIntegerMin;
    CGFloat nameWidth = 0;
    for (SPDFMarkdownDiagramGanttSection* section in gantt.sections) {
        nameWidth = MAX(nameWidth, SPDFMarkdownDiagramMeasureText(section.name, sectionFont, 220 * scale).width);
        for (SPDFMarkdownDiagramGanttTask* task in section.tasks) {
            minimumDay = MIN(minimumDay, task.startDay);
            maximumDay = MAX(maximumDay, task.endDay);
            nameWidth = MAX(nameWidth, SPDFMarkdownDiagramMeasureText(task.name, labelFont, 220 * scale).width);
        }
    }
    NSInteger spanDays = MAX(1, maximumDay - minimumDay);
    if (spanDays > 3660) return nil;
    CGFloat margin = 14 * scale;
    CGFloat labelColumn = MIN(230 * scale, nameWidth + 16 * scale);
    CGFloat chartWidth = MAX(180 * scale, MIN(520 * scale, (CGFloat)spanDays * 26 * scale));
    CGFloat dayWidth = chartWidth / (CGFloat)spanDays;
    CGFloat rowHeight = lineHeight + 10 * scale;
    CGFloat titleHeight = gantt.title.length
        ? SPDFMarkdownDiagramMeasureText(gantt.title, titleFont, 400 * scale).height + 10 * scale
        : 0;
    NSUInteger rows = gantt.taskCount + gantt.sections.count;
    CGFloat axisHeight = lineHeight + 8 * scale;
    NSSize naturalSize = NSMakeSize(margin * 2 + labelColumn + chartWidth,
                                    margin * 2 + titleHeight + rows * rowHeight + axisHeight);
    // Tick cadence: the smallest of 1/2/7/14/30/90/365 days spacing >= 46pt.
    NSInteger tickStep = 365;
    for (NSNumber* candidate in @[ @1, @2, @7, @14, @30, @90 ]) {
        if (dayWidth * candidate.integerValue >= 46 * scale) {
            tickStep = candidate.integerValue;
            break;
        }
    }

    NSImage* image = SPDFMarkdownDiagramCreateCanvas(naturalSize, ^{
      [palette.paperColor setFill];
      NSRectFill(NSMakeRect(0, 0, naturalSize.width, naturalSize.height));
      if (gantt.title.length) {
          SPDFMarkdownDiagramDrawText(gantt.title, NSMakeRect(0, margin * 0.6, naturalSize.width, titleHeight),
                                      titleFont, palette.textColor, NSTextAlignmentCenter);
      }
      CGFloat chartX = margin + labelColumn;
      CGFloat topY = margin + titleHeight;
      CGFloat chartBottom = topY + rows * rowHeight;
      // Day grid + tick labels.
      for (NSInteger day = 0; day <= spanDays; day += tickStep) {
          CGFloat x = chartX + day * dayWidth;
          [[palette.nodeStrokeColor colorWithAlphaComponent:0.6] setStroke];
          [NSBezierPath strokeLineFromPoint:NSMakePoint(x, topY) toPoint:NSMakePoint(x, chartBottom)];
          SPDFMarkdownDiagramDrawText(SPDFGanttTickLabel(gantt.epoch, minimumDay + day),
                                      NSMakeRect(x - 30 * scale, chartBottom + 4 * scale, 60 * scale,
                                                 lineHeight + 2),
                                      smallFont, palette.secondaryColor, NSTextAlignmentCenter);
      }
      CGFloat y = topY;
      for (SPDFMarkdownDiagramGanttSection* section in gantt.sections) {
          // Section band across the full row for orientation.
          [[palette.nodeFillColor colorWithAlphaComponent:0.7] setFill];
          NSRectFillUsingOperation(NSMakeRect(margin, y, naturalSize.width - 2 * margin, rowHeight),
                                   NSCompositingOperationSourceOver);
          SPDFMarkdownDiagramDrawText(section.name.length ? section.name : @"Tasks",
                                      NSMakeRect(margin + 2 * scale, y + 5 * scale, labelColumn, lineHeight + 2),
                                      sectionFont, palette.textColor, NSTextAlignmentLeft);
          y += rowHeight;
          for (SPDFMarkdownDiagramGanttTask* task in section.tasks) {
              SPDFMarkdownDiagramDrawText(task.name,
                                          NSMakeRect(margin + 8 * scale, y + 5 * scale, labelColumn - 10 * scale,
                                                     lineHeight + 2),
                                          labelFont, task.done ? palette.secondaryColor : palette.textColor,
                                          NSTextAlignmentLeft);
              CGFloat barX = chartX + (task.startDay - minimumDay) * dayWidth;
              CGFloat barWidth = MAX(4 * scale, (task.endDay - task.startDay) * dayWidth);
              NSRect bar = NSMakeRect(barX, y + 3 * scale, barWidth, rowHeight - 6 * scale);
              NSColor* fill = task.critical ? palette.criticalColor
                  : task.done              ? palette.secondaryColor
                  : task.active            ? palette.accentRamp[1]
                                           : palette.accentColor;
              [[fill colorWithAlphaComponent:task.done ? 0.45 : 0.85] setFill];
              NSBezierPath* barPath = [NSBezierPath bezierPathWithRoundedRect:bar
                                                                      xRadius:3 * scale
                                                                      yRadius:3 * scale];
              [barPath fill];
              [fill setStroke];
              [barPath stroke];
              y += rowHeight;
          }
      }
    });
    if (!image) return nil;
    CGFloat fit = contentWidth > 0 ? MIN(1.0, contentWidth / naturalSize.width) : 1.0;
    return SPDFMarkdownDiagramImageMake(image, NSMakeSize(floor(naturalSize.width * fit),
                                                          floor(naturalSize.height * fit)));
}
