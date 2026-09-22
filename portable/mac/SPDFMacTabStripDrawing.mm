#import "SPDFMacTabStripViewPrivate.h"
#include <math.h>

@implementation SPDFTabStripView (Drawing)
- (void)drawTabAtIndex:(NSInteger)index
                inRect:(NSRect)tabRect
            attributes:(NSDictionary*)attrs
         dimAttributes:(NSDictionary*)dimAttrs {
    if (index < 0 || index >= (NSInteger)self.tabs.count || NSWidth(tabRect) < 40.0) return;
    (void)dimAttrs;

    BOOL selected = index == self.selectedIndex;
    SPDFDocumentTab* tab = self.tabs[(NSUInteger)index];
    BOOL missing = tab.missingFile;
    // Fill, then outline every tab — see SPDFMacTabStripStyle.h for why an
    // unselected tab was previously edgeless. The outline path is inset by half
    // its width so its centreline lands on a device-pixel boundary.
    SPDFTabStyle style = spdf_tab_style_for_state(selected, missing);
    BOOL dark = [[self.effectiveAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
    NSColor* accent = tab.group ? spdf_tab_group_accent(tab.group.colorName) : nil;
    NSColor* fill = spdf_tab_style_color(style.fillRole, style.fillAlpha);
    NSColor* stroke = spdf_tab_style_color(style.strokeRole, style.strokeAlpha);
    if (tab.group && !missing) {
        fill = selected ? spdf_tab_group_selected_fill(tab.group.colorName, dark)
                        : [accent blendedColorWithFraction:dark ? 0.65 : 0.62 ofColor:NSColor.controlBackgroundColor];
        stroke = selected ? [accent blendedColorWithFraction:0.3 ofColor:NSColor.whiteColor]
                          : [accent colorWithAlphaComponent:0.65];
    } else if (selected && !missing) {
        fill = spdf_tab_group_selected_fill(nil, dark);
        stroke = NSColor.secondaryLabelColor;
    }
    [fill setFill];
    CGFloat radius = kSPDFTabCornerRadius;
    [[NSBezierPath bezierPathWithRoundedRect:tabRect xRadius:radius yRadius:radius] fill];
    CGFloat inset = spdf_tab_stroke_inset(style.strokeWidth);
    NSBezierPath* outline = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(tabRect, inset, inset)
                                                           xRadius:radius - inset
                                                           yRadius:radius - inset];
    [stroke setStroke];
    outline.lineWidth = style.strokeWidth;
    [outline stroke];

    NSString* title = [self titleForTabAtIndex:index];
    // Selection is carried by the fill, outline and font weight. Keeping one
    // foreground colour across every title avoids making an inactive document
    // look disabled, especially in the dark appearance.
    NSMutableDictionary* titleAttrs = [attrs mutableCopy];
    if (selected) titleAttrs[NSFontAttributeName] = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    CGFloat titleHeight = [title sizeWithAttributes:titleAttrs].height;
    CGFloat leftInset = 12.0;
    CGFloat rightInset = 34.0;

    // Read-only indicator: a small orange dot immediately left of the title for
    // any tab whose SOURCE is read-only (the app renders a copy without
    // prompting). Drawn per-tab so it follows reorder; never for a missing tab
    // (the red tint already owns that case). systemOrange is theme-correct.
    BOOL showReadOnlyDot = tab.readOnly && !missing;
    if (showReadOnlyDot) {
        // -rebuildReadOnlyTooltips computes the same rect via kReadOnlyDotLeftInset,
        // so the hover hit-area stays aligned with the drawn dot.
        NSRect dotRect = [self readOnlyDotRectForTabRect:tabRect
                                                diameter:kReadOnlyDotDiameter
                                               leftInset:kReadOnlyDotLeftInset];
        [NSColor.systemOrangeColor setFill];
        [[NSBezierPath bezierPathWithOvalInRect:dotRect] fill];
        // Reserve space so the (middle-ellipsis) title sits just right of the dot.
        leftInset = kReadOnlyDotLeftInset + kReadOnlyDotDiameter + kReadOnlyDotTitleGap;
    }

    NSRect titleRect = NSMakeRect(NSMinX(tabRect) + leftInset, floor(NSMidY(tabRect) - titleHeight / 2.0),
                                  MAX(1.0, NSWidth(tabRect) - leftInset - rightInset), titleHeight + 2);
    [title drawWithRect:titleRect
                options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine
             attributes:titleAttrs];

    NSRect closeRect = [self closeCircleRectForTabRect:tabRect];
    NSBezierPath* closeCircle = [NSBezierPath bezierPathWithOvalInRect:closeRect];
    NSColor* closeFill = selected ? [NSColor.labelColor colorWithAlphaComponent:0.13]
                                  : [NSColor.secondaryLabelColor colorWithAlphaComponent:0.13];
    [closeFill setFill];
    [closeCircle fill];

    NSColor* closeStroke = selected ? [NSColor.labelColor colorWithAlphaComponent:0.90]
                                    : [NSColor.secondaryLabelColor colorWithAlphaComponent:0.82];
    [closeStroke setStroke];
    NSBezierPath* closeX = [NSBezierPath bezierPath];
    closeX.lineWidth = 1.35;
    [closeX moveToPoint:NSMakePoint(NSMidX(closeRect) - 3.2, NSMidY(closeRect) - 3.2)];
    [closeX lineToPoint:NSMakePoint(NSMidX(closeRect) + 3.2, NSMidY(closeRect) + 3.2)];
    [closeX moveToPoint:NSMakePoint(NSMidX(closeRect) + 3.2, NSMidY(closeRect) - 3.2)];
    [closeX lineToPoint:NSMakePoint(NSMidX(closeRect) - 3.2, NSMidY(closeRect) + 3.2)];
    [closeX stroke];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor clearColor] setFill];
    NSRectFill(self.bounds);

    NSMutableParagraphStyle* tabTitleStyle = [[NSMutableParagraphStyle alloc] init];
    tabTitleStyle.alignment = NSTextAlignmentCenter;
    tabTitleStyle.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSDictionary* attrs = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : NSColor.labelColor,
        NSParagraphStyleAttributeName : tabTitleStyle
    };
    // Kept as a separate argument while older callers/tests use the drawing
    // seam; it deliberately has the exact same foreground as attrs.
    NSDictionary* dimAttrs = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12],
        NSForegroundColorAttributeName : NSColor.labelColor,
        NSParagraphStyleAttributeName : tabTitleStyle
    };

    [self drawTabGroups];
    NSInteger draggedIndex = [self isVisuallyReorderingTabs] ? _dragSourceTabIndex : -1;
    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; ++i) {
        if (i == draggedIndex) continue;
        [self drawTabAtIndex:i inRect:[self visualRectForTabAtIndex:i] attributes:attrs dimAttributes:dimAttrs];
    }
    if (draggedIndex >= 0) {
        [self drawTabAtIndex:draggedIndex
                      inRect:[self visualRectForTabAtIndex:draggedIndex]
                  attributes:attrs
               dimAttributes:dimAttrs];
    }

    NSRect overflowRect = [self overflowRect];
    if (!NSIsEmptyRect(overflowRect)) {
        [NSColor.controlBackgroundColor setFill];
        NSBezierPath* overflowPath = [NSBezierPath bezierPathWithRoundedRect:overflowRect xRadius:9 yRadius:9];
        [overflowPath fill];
        [[NSColor.separatorColor colorWithAlphaComponent:0.45] setStroke];
        overflowPath.lineWidth = 1.0;
        [overflowPath stroke];

        [[NSColor.labelColor colorWithAlphaComponent:0.78] setFill];
        CGFloat dotDiameter = 3.0;
        CGFloat dotGap = 3.0;
        CGFloat x = floor(NSMidX(overflowRect) - dotDiameter / 2.0);
        CGFloat startY = floor(NSMidY(overflowRect) - dotDiameter * 1.5 - dotGap);
        for (NSInteger i = 0; i < 3; ++i) {
            NSRect dot = NSMakeRect(x, startY + (dotDiameter + dotGap) * i, dotDiameter, dotDiameter);
            [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
        }
    }

    NSRect plusRect = [self plusRect];
    [NSColor.controlBackgroundColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:plusRect xRadius:9 yRadius:9] fill];
    NSDictionary* plusAttrs = @{
        NSFontAttributeName : [NSFont systemFontOfSize:16 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : NSColor.labelColor
    };
    NSSize plusSize = [@"+" sizeWithAttributes:plusAttrs];
    [@"+" drawAtPoint:NSMakePoint(floor(NSMidX(plusRect) - plusSize.width / 2.0),
                                  floor(NSMidY(plusRect) - plusSize.height / 2.0))
        withAttributes:plusAttrs];

    [self drawGroupDropPreview];

    // Drop-insertion indicator: a thin rounded systemYellow line, full tab
    // height, centered in the gap where a hovering detached tab would insert.
    // Drawn last as a pure overlay so the existing tabs never shift.
    if (_dropIndicatorSlot >= 0) {
        CGFloat minXs[kMaxVisibleTabGeometry], midXs[kMaxVisibleTabGeometry], maxXs[kMaxVisibleTabGeometry];
        NSInteger arrayIndexes[kMaxVisibleTabGeometry];
        NSInteger visibleCount = [self collectVisibleTabGeometryMinXs:minXs midXs:midXs maxXs:maxXs
                                                         arrayIndexes:arrayIndexes];
        CGFloat centerX = spdf_tab_strip_drop_indicator_center_x(_dropIndicatorSlot, minXs, maxXs, visibleCount,
                                                                 kTabGap);
        if (!isnan(centerX)) {
            NSRect anyTabRect = [self rectForTabAtIndex:arrayIndexes[0]];
            NSRect lineRect = NSMakeRect(floor(centerX) - 1.0, NSMinY(anyTabRect), 2.0, NSHeight(anyTabRect));
            [NSColor.systemYellowColor setFill];
            [[NSBezierPath bezierPathWithRoundedRect:lineRect xRadius:1.0 yRadius:1.0] fill];
        }
    }
}

@end
