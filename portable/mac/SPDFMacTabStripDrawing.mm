#import "SPDFMacTabStripViewPrivate.h"
#import "SPDFMacTabTitleDrawing.h"
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
    BOOL hovered = _hoverTabIndex == index;
    BOOL dark = [[self.effectiveAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
    NSColor* accent = spdf_tab_group_accent(tab.group.colorName);
    NSColor* fill = missing ? [NSColor.systemRedColor colorWithAlphaComponent:selected ? 0.36 : 0.22]
        : selected ? spdf_tab_group_selected_fill(tab.group.colorName, dark)
        : [accent colorWithAlphaComponent:hovered ? 0.16 : 0.06];
    [fill setFill];
    [[NSBezierPath bezierPathWithRoundedRect:tabRect xRadius:6 yRadius:6] fill];

    NSString* title = [self titleForTabAtIndex:index];
    // Selection is carried by the fill, outline and font weight. Keeping one
    // foreground colour across every title avoids making an inactive document
    // look disabled, especially in the dark appearance.
    NSMutableDictionary* titleAttrs = [attrs mutableCopy];
    if (selected) titleAttrs[NSFontAttributeName] = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    CGFloat titleHeight = [title sizeWithAttributes:titleAttrs].height;
    CGFloat leftInset = 6.0;
    CGFloat rightInset = 6.0;

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

    NSRect titleRect = NSMakeRect(NSMinX(tabRect)+leftInset, floor(NSMidY(tabRect)-titleHeight/2),
                                  MAX(1,NSWidth(tabRect)-leftInset-rightInset), titleHeight+2);
    [NSGraphicsContext saveGraphicsState];
    NSRectClip(titleRect);
    CGContextRef graphics = NSGraphicsContext.currentContext.CGContext;
    if (hovered) CGContextBeginTransparencyLayer(graphics, NULL);
    SPDFDrawTabTitle(title, titleRect, titleAttrs);
    // The glyph geometry never changes on hover. Fade only the trailing region
    // into this tab's actual fill, then overlay the close control.
    if (hovered) {
        CGContextSetBlendMode(graphics, kCGBlendModeDestinationOut);
        NSRect fade = NSMakeRect(NSMaxX(titleRect)-34,NSMinY(titleRect),16,NSHeight(titleRect));
        CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
        CGFloat components[]={0,0,0,0, 0,0,0,1};
        CGFloat locations[]={0,1};
        CGGradientRef gradient=CGGradientCreateWithColorComponents(space,components,locations,2);
        CGContextDrawLinearGradient(graphics,gradient,CGPointMake(NSMinX(fade),NSMidY(fade)),
            CGPointMake(NSMaxX(fade),NSMidY(fade)),0);
        CGContextSetRGBFillColor(graphics,0,0,0,1);
        CGContextFillRect(graphics,CGRectMake(NSMaxX(titleRect)-18,NSMinY(titleRect),18,NSHeight(titleRect)));
        CGGradientRelease(gradient); CGColorSpaceRelease(space);
        CGContextEndTransparencyLayer(graphics);
    }
    [NSGraphicsContext restoreGraphicsState];
    if (!hovered) return;

    NSRect closeRect = [self closeCircleRectForTabRect:tabRect];
    NSBezierPath* closeCircle = [NSBezierPath bezierPathWithRoundedRect:closeRect xRadius:4 yRadius:4];
    NSColor* closeFill = selected ? [NSColor.labelColor colorWithAlphaComponent:0.13]
                                  : [NSColor.secondaryLabelColor colorWithAlphaComponent:0.13];
    [closeFill setFill];
    if (_hasLastHoverPoint && NSPointInRect(_lastHoverPoint,closeRect)) [closeCircle fill];

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

    NSParagraphStyle* tabTitleStyle = SPDFTabTitleParagraphStyle();
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
        NSImage* icon = [NSImage imageWithSystemSymbolName:@"square.3.layers.3d" accessibilityDescription:@"All Groups"];
        icon = [icon imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPaletteColors:@[NSColor.labelColor]]];
        [icon drawInRect:NSInsetRect(overflowRect,6,6)];
    }

    NSRect plusRect = [self plusRect];

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
