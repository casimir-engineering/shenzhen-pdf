#import "SPDFMacMinimapView.h"

#include <math.h>

static const CGFloat kPageMargin = 44.0;
static const CGFloat kPageGap = 26.0;
static const NSInteger kLongDocumentDragPageThreshold = 20;
static const CGFloat kLongDocumentDragFineSpeed = 180.0;
static const CGFloat kLongDocumentDragFullSpeed = 300.0;
static const CGFloat kLiveContentCacheMaxPixels = 12000000.0;
static const CGFloat kLiveContentCacheMaxHeight = 48000.0;

static CGFloat spdf_clamp_cg(CGFloat value, CGFloat minValue, CGFloat maxValue) {
    return MAX(minValue, MIN(maxValue, value));
}

static CGFloat spdf_smoothstep_cg(CGFloat value) {
    value = spdf_clamp_cg(value, 0.0, 1.0);
    return value * value * value * (value * (value * 6.0 - 15.0) + 10.0);
}

@implementation SPDFMinimapView {
    BOOL _draggingVisibleRect;
    BOOL _pressPending;
    BOOL _dragMoved;
    NSPoint _pressPoint;
    NSPoint _dragOffsetFromVisibleCenter;
    CGFloat _dragOffsetFromVisibleTop;
    CGFloat _dragThumbTop;
    CGFloat _dragLastMouseY;
    NSTimeInterval _dragLastTimestamp;
    BOOL _miniLayoutCacheValid;
    NSArray<SPDFRenderedPage*>* _miniLayoutPages;
    NSArray<NSValue*>* _miniLayoutPageRects;
    NSDictionary<NSNumber*, NSValue*>* _miniLayoutPageRectsByIndex;
    CGFloat _miniLayoutScale;
    CGFloat _miniLayoutGap;
    CGFloat _miniLayoutBoundsWidth;
    NSImage* _contentImageCache;
    NSArray<SPDFRenderedPage*>* _contentImageCachePages;
    CGFloat _contentImageCacheScale;
    CGFloat _contentImageCacheGap;
    CGFloat _contentImageCacheHeight;
    CGFloat _contentImageCacheBoundsWidth;
    NSInteger _contentImageCacheCurrentPageIndex;
    BOOL _contentImageCacheDrawImages;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event {
    (void)event;
    return YES;
}

- (void)setPages:(NSArray<SPDFRenderedPage*>*)pages {
    _pages = [pages copy];
    [self invalidateMiniLayoutCache];
    [self invalidateContentImageCache];
    [self setNeedsDisplay:YES];
}

- (void)setFrameSize:(NSSize)newSize {
    NSSize oldSize = self.frame.size;
    [super setFrameSize:newSize];
    if (!NSEqualSizes(oldSize, newSize)) {
        [self invalidateMiniLayoutCache];
        [self invalidateContentImageCache];
    }
}

- (void)setBoundsSize:(NSSize)newSize {
    NSSize oldSize = self.bounds.size;
    [super setBoundsSize:newSize];
    if (!NSEqualSizes(oldSize, newSize)) {
        [self invalidateMiniLayoutCache];
        [self invalidateContentImageCache];
    }
}

- (void)invalidateMiniLayoutCache {
    _miniLayoutCacheValid = NO;
    _miniLayoutPages = nil;
    _miniLayoutPageRects = nil;
    _miniLayoutPageRectsByIndex = nil;
}

- (void)invalidateContentImageCache {
    _contentImageCache = nil;
    _contentImageCachePages = nil;
}

- (CGFloat)widestPage {
    CGFloat widest = 0;
    for (SPDFRenderedPage* page in self.pages) widest = MAX(widest, page.pageWidth);
    return widest;
}

- (CGFloat)scrollFraction {
    CGFloat visibleHeight = NSHeight(self.documentVisibleRect);
    CGFloat maxScroll = MAX(1.0, self.documentHeight - visibleHeight);
    return spdf_clamp_cg(NSMinY(self.documentVisibleRect) / maxScroll, 0.0, 1.0);
}

- (void)ensureMiniLayoutCacheForScale:(CGFloat)scale gap:(CGFloat)gap {
    CGFloat boundsWidth = NSWidth(self.bounds);
    if (_miniLayoutCacheValid && _miniLayoutPages == self.pages && _miniLayoutScale == scale && _miniLayoutGap == gap &&
        _miniLayoutBoundsWidth == boundsWidth)
        return;

    NSMutableArray<NSValue*>* pageRects = [NSMutableArray arrayWithCapacity:self.pages.count];
    NSMutableDictionary<NSNumber*, NSValue*>* pageRectsByIndex = [NSMutableDictionary dictionary];
    CGFloat y = 0.0;
    for (SPDFRenderedPage* page in self.pages) {
        CGFloat pageWidth = MAX(1.0, page.pageWidth * scale);
        CGFloat pageHeight = MAX(1.0, page.pageHeight * scale);
        NSRect rect = NSMakeRect(floor((boundsWidth - pageWidth) / 2.0), y, pageWidth, pageHeight);
        NSValue* value = [NSValue valueWithRect:rect];
        [pageRects addObject:value];
        NSNumber* pageIndex = @(page.pageIndex);
        if (!pageRectsByIndex[pageIndex]) pageRectsByIndex[pageIndex] = value;
        y += pageHeight + gap;
    }

    _miniLayoutPages = self.pages;
    _miniLayoutPageRects = pageRects;
    _miniLayoutPageRectsByIndex = pageRectsByIndex;
    _miniLayoutScale = scale;
    _miniLayoutGap = gap;
    _miniLayoutBoundsWidth = boundsWidth;
    _miniLayoutCacheValid = YES;
}

- (NSRect)miniRectForPage:(SPDFRenderedPage*)targetPage scale:(CGFloat)scale gap:(CGFloat)gap {
    [self ensureMiniLayoutCacheForScale:scale gap:gap];
    NSValue* indexedRect = _miniLayoutPageRectsByIndex[@(targetPage.pageIndex)];
    if (indexedRect) return indexedRect.rectValue;

    for (SPDFRenderedPage* page in self.pages) {
        if (page == targetPage || page.pageIndex == targetPage.pageIndex) {
            NSUInteger index = [self.pages indexOfObjectIdenticalTo:page];
            if (index != NSNotFound && index < _miniLayoutPageRects.count)
                return [_miniLayoutPageRects[index] rectValue];
        }
    }
    return NSZeroRect;
}

- (NSRect)documentRectForPage:(SPDFRenderedPage*)targetPage {
    if (targetPage.pageIndex >= 0 && targetPage.pageIndex < (NSInteger)self.documentPageRects.count) {
        NSRect rect = [self.documentPageRects[(NSUInteger)targetPage.pageIndex] rectValue];
        if (!NSIsEmptyRect(rect)) return rect;
    }

    CGFloat documentScale = MAX(0.01, self.documentScale);
    CGFloat documentWidth = MAX(1.0, self.documentWidth);
    CGFloat y = kPageMargin / 2.0;

    for (SPDFRenderedPage* page in self.pages) {
        if (page.pageIndex >= targetPage.pageIndex) break;
        y += page.pageHeight * documentScale + kPageGap;
    }

    CGFloat width = MAX(1.0, targetPage.pageWidth * documentScale);
    CGFloat height = MAX(1.0, targetPage.pageHeight * documentScale);
    CGFloat x = floor((documentWidth - width) / 2.0);
    return NSMakeRect(MAX(kPageMargin / 2.0, x), y, width, height);
}

- (NSRect)miniRectForDocumentIntersection:(NSRect)intersection
                             documentRect:(NSRect)documentRect
                                 miniRect:(NSRect)miniRect {
    if (NSIsEmptyRect(intersection) || NSIsEmptyRect(documentRect) || NSIsEmptyRect(miniRect)) return NSZeroRect;

    CGFloat x0 = spdf_clamp_cg((NSMinX(intersection) - NSMinX(documentRect)) / NSWidth(documentRect), 0.0, 1.0);
    CGFloat x1 = spdf_clamp_cg((NSMaxX(intersection) - NSMinX(documentRect)) / NSWidth(documentRect), 0.0, 1.0);
    CGFloat y0 = spdf_clamp_cg((NSMinY(intersection) - NSMinY(documentRect)) / NSHeight(documentRect), 0.0, 1.0);
    CGFloat y1 = spdf_clamp_cg((NSMaxY(intersection) - NSMinY(documentRect)) / NSHeight(documentRect), 0.0, 1.0);

    return NSMakeRect(NSMinX(miniRect) + x0 * NSWidth(miniRect), NSMinY(miniRect) + y0 * NSHeight(miniRect),
                      MAX(1.0, (x1 - x0) * NSWidth(miniRect)), MAX(1.0, (y1 - y0) * NSHeight(miniRect)));
}

- (BOOL)shouldUseLongDocumentViewportDrag {
    return self.pages.count > kLongDocumentDragPageThreshold;
}

- (CGFloat)longDocumentViewportDragThumbHeightForContentHeight:(CGFloat)contentHeight track:(NSRect)track {
    CGFloat heightFraction =
        spdf_clamp_cg(NSHeight(self.documentVisibleRect) / MAX(1.0, self.documentHeight), 0.02, 1.0);
    return MIN(MAX(10.0, heightFraction * MAX(1.0, contentHeight)), NSHeight(track));
}

- (NSRect)unscrolledVisibleRectForScale:(CGFloat)scale gap:(CGFloat)gap contentHeight:(CGFloat)contentHeight {
    if (self.pages.count == 0 || contentHeight <= 0) return NSZeroRect;

    if (self.documentHeight > 1.0) {
        NSRect visible = NSZeroRect;
        BOOL hasVisiblePage = NO;
        for (SPDFRenderedPage* page in self.pages) {
            NSRect documentRect = [self documentRectForPage:page];
            NSRect intersection = NSIntersectionRect(self.documentVisibleRect, documentRect);
            if (NSIsEmptyRect(intersection)) continue;

            NSRect miniRect = [self miniRectForPage:page scale:scale gap:gap];
            NSRect miniVisible = [self miniRectForDocumentIntersection:intersection
                                                          documentRect:documentRect
                                                              miniRect:miniRect];
            if (NSIsEmptyRect(miniVisible)) continue;

            visible = hasVisiblePage ? NSUnionRect(visible, miniVisible) : miniVisible;
            hasVisiblePage = YES;
        }
        if (hasVisiblePage) return NSInsetRect(visible, -2.0, -2.0);
    }

    CGFloat heightFraction =
        spdf_clamp_cg(NSHeight(self.documentVisibleRect) / MAX(1.0, self.documentHeight), 0.02, 1.0);
    CGFloat height = MAX(10.0, heightFraction * contentHeight);
    CGFloat top = [self scrollFraction] * MAX(0.0, contentHeight - height);
    if (top + height > contentHeight) top = MAX(0.0, contentHeight - height);
    return NSMakeRect(5.0, top, NSWidth(self.bounds) - 10.0, height);
}

- (BOOL)layoutScale:(CGFloat*)scaleOut
                gap:(CGFloat*)gapOut
         contentTop:(CGFloat*)topOut
      contentHeight:(CGFloat*)heightOut
        visibleRect:(NSRect*)visibleOut {
    if (self.pages.count == 0 || NSWidth(self.bounds) < 16 || NSHeight(self.bounds) < 16) return NO;

    CGFloat widest = [self widestPage];
    if (widest <= 0) return NO;

    CGFloat scale = (NSWidth(self.bounds) - 18.0) / widest;
    CGFloat gap = 4.0;
    CGFloat contentHeight = 0;
    for (SPDFRenderedPage* page in self.pages) contentHeight += page.pageHeight * scale;
    contentHeight += gap * MAX(0, (NSInteger)self.pages.count - 1);
    CGFloat available = MAX(1.0, NSHeight(self.bounds) - 16.0);
    NSRect visible = [self unscrolledVisibleRectForScale:scale gap:gap contentHeight:contentHeight];
    CGFloat offset = 0;
    if (contentHeight > available) {
        CGFloat maxOffset = contentHeight - available;
        offset = [self scrollFraction] * maxOffset;
    }

    CGFloat contentTop =
        contentHeight < available ? floor((NSHeight(self.bounds) - contentHeight) / 2.0) : 8.0 - offset;
    visible.origin.y += contentTop;
    if (scaleOut) *scaleOut = scale;
    if (gapOut) *gapOut = gap;
    if (topOut) *topOut = contentTop;
    if (heightOut) *heightOut = contentHeight;
    if (visibleOut) *visibleOut = visible;
    return YES;
}

- (CGFloat)contentTopForDocumentCenterY:(CGFloat)documentY contentHeight:(CGFloat)contentHeight {
    CGFloat available = MAX(1.0, NSHeight(self.bounds) - 16.0);
    if (contentHeight < available) return floor((NSHeight(self.bounds) - contentHeight) / 2.0);

    CGFloat visibleHeight = NSHeight(self.documentVisibleRect);
    CGFloat maxScroll = MAX(1.0, self.documentHeight - visibleHeight);
    CGFloat originY = spdf_clamp_cg(documentY - visibleHeight * 0.5, 0.0, maxScroll);
    CGFloat offset = (originY / maxScroll) * (contentHeight - available);
    return 8.0 - offset;
}

- (NSPoint)documentPointForUnscrolledMiniPoint:(NSPoint)point scale:(CGFloat)scale gap:(CGFloat)gap {
    CGFloat y = 0;
    for (SPDFRenderedPage* page in self.pages) {
        NSRect miniRect = [self miniRectForPage:page scale:scale gap:gap];
        NSRect documentRect = [self documentRectForPage:page];
        if (NSIsEmptyRect(miniRect) || NSIsEmptyRect(documentRect)) {
            y += MAX(1.0, page.pageHeight * scale) + gap;
            continue;
        }

        if (point.y >= NSMinY(miniRect) && point.y <= NSMaxY(miniRect)) {
            CGFloat xFraction = spdf_clamp_cg((point.x - NSMinX(miniRect)) / MAX(1.0, NSWidth(miniRect)), 0.0, 1.0);
            CGFloat yFraction = spdf_clamp_cg((point.y - NSMinY(miniRect)) / MAX(1.0, NSHeight(miniRect)), 0.0, 1.0);
            return NSMakePoint(NSMinX(documentRect) + xFraction * NSWidth(documentRect),
                               NSMinY(documentRect) + yFraction * NSHeight(documentRect));
        }

        CGFloat gapStart = NSMaxY(miniRect);
        CGFloat gapEnd = gapStart + gap;
        if (point.y > gapStart && point.y < gapEnd) {
            CGFloat xFraction = spdf_clamp_cg((point.x - NSMinX(miniRect)) / MAX(1.0, NSWidth(miniRect)), 0.0, 1.0);
            CGFloat gapFraction = spdf_clamp_cg((point.y - gapStart) / MAX(1.0, gap), 0.0, 1.0);
            return NSMakePoint(NSMinX(documentRect) + xFraction * NSWidth(documentRect),
                               NSMaxY(documentRect) + gapFraction * kPageGap);
        }
        y += MAX(1.0, page.pageHeight * scale) + gap;
    }

    CGFloat yFraction = spdf_clamp_cg(point.y / MAX(1.0, y), 0.0, 1.0);
    return NSMakePoint(NSMidX(self.documentVisibleRect), yFraction * self.documentHeight);
}

- (NSPoint)documentPointForMinimapCenterPoint:(NSPoint)point
                                        scale:(CGFloat)scale
                                          gap:(CGFloat)gap
                                contentHeight:(CGFloat)contentHeight
                                   contentTop:(CGFloat)contentTop {
    NSPoint documentPoint = [self documentPointForUnscrolledMiniPoint:NSMakePoint(point.x, point.y - contentTop)
                                                                scale:scale
                                                                  gap:gap];
    for (NSInteger i = 0; i < 8; ++i) {
        CGFloat projectedTop = [self contentTopForDocumentCenterY:documentPoint.y contentHeight:contentHeight];
        NSPoint unscrolledPoint = NSMakePoint(point.x, point.y - projectedTop);
        documentPoint = [self documentPointForUnscrolledMiniPoint:unscrolledPoint scale:scale gap:gap];
    }
    return documentPoint;
}

- (BOOL)pageHitForMiniPoint:(NSPoint)point
                      scale:(CGFloat)scale
                        gap:(CGFloat)gap
                 contentTop:(CGFloat)contentTop
                  pageIndex:(NSInteger*)pageIndexOut
            xFractionInPage:(CGFloat*)xFractionOut
            yFractionInPage:(CGFloat*)yFractionOut {
    NSPoint unscrolledPoint = NSMakePoint(point.x, point.y - contentTop);
    for (SPDFRenderedPage* page in self.pages) {
        NSRect miniRect = [self miniRectForPage:page scale:scale gap:gap];
        if (NSIsEmptyRect(miniRect)) continue;
        if (unscrolledPoint.y >= NSMinY(miniRect) && unscrolledPoint.y <= NSMaxY(miniRect)) {
            if (pageIndexOut) *pageIndexOut = page.pageIndex;
            if (xFractionOut)
                *xFractionOut =
                    spdf_clamp_cg((unscrolledPoint.x - NSMinX(miniRect)) / MAX(1.0, NSWidth(miniRect)), 0.0, 1.0);
            if (yFractionOut)
                *yFractionOut =
                    spdf_clamp_cg((unscrolledPoint.y - NSMinY(miniRect)) / MAX(1.0, NSHeight(miniRect)), 0.0, 1.0);
            return YES;
        }
    }
    return NO;
}

- (NSRect)draggableVisibleRectForRect:(NSRect)visibleRect {
    return NSIntersectionRect(visibleRect, NSInsetRect(self.bounds, 1.0, 1.0));
}

- (NSTimeInterval)dragDeltaTimeForTimestamp:(NSTimeInterval)timestamp {
    NSTimeInterval deltaT = timestamp - _dragLastTimestamp;
    if (!isfinite(deltaT) || deltaT <= 0.0) deltaT = 1.0 / 60.0;
    return spdf_clamp_cg(deltaT, 1.0 / 240.0, 1.0 / 15.0);
}

- (CGFloat)longDocumentDragScaleForDeltaY:(CGFloat)deltaY timestamp:(NSTimeInterval)timestamp {
    if (![self shouldUseLongDocumentViewportDrag]) return 1.0;

    NSTimeInterval deltaT = [self dragDeltaTimeForTimestamp:timestamp];
    CGFloat speed = fabs(deltaY) / deltaT;
    CGFloat acceleration = spdf_smoothstep_cg((speed - kLongDocumentDragFineSpeed) /
                                              (kLongDocumentDragFullSpeed - kLongDocumentDragFineSpeed));
    CGFloat pageScale = spdf_clamp_cg(20.0 / MAX(1.0, (CGFloat)self.pages.count), 0.30, 0.72);
    return pageScale + acceleration * (1.0 - pageScale);
}

- (BOOL)sendLongDocumentViewportDragForPoint:(NSPoint)point
                                       event:(NSEvent*)event
                                       scale:(CGFloat)scale
                                         gap:(CGFloat)gap
                               contentHeight:(CGFloat)contentHeight
                                  contentTop:(CGFloat)contentTop {
    if (!_draggingVisibleRect || ![self shouldUseLongDocumentViewportDrag]) return NO;

    NSRect track = NSInsetRect(self.bounds, 1.0, 1.0);
    CGFloat thumbHeight = [self longDocumentViewportDragThumbHeightForContentHeight:contentHeight track:track];
    CGFloat minTop = NSMinY(track);
    CGFloat maxTop = MAX(minTop, NSMaxY(track) - thumbHeight);
    CGFloat deltaY = point.y - _dragLastMouseY;
    CGFloat dragScale = [self longDocumentDragScaleForDeltaY:deltaY timestamp:event.timestamp];
    _dragThumbTop = spdf_clamp_cg(_dragThumbTop + deltaY * dragScale, minTop, maxTop);
    _dragLastMouseY = point.y;
    _dragLastTimestamp = event.timestamp;

    CGFloat fraction = maxTop <= minTop ? 0.0 : (_dragThumbTop - minTop) / (maxTop - minTop);
    NSPoint horizontalCenterPoint =
        NSMakePoint(point.x - _dragOffsetFromVisibleCenter.x, _dragThumbTop + thumbHeight * 0.5);
    NSPoint documentPoint = [self documentPointForMinimapCenterPoint:horizontalCenterPoint
                                                               scale:scale
                                                                 gap:gap
                                                       contentHeight:contentHeight
                                                          contentTop:contentTop];
    if (!isfinite(documentPoint.x)) documentPoint.x = NSMidX(self.documentVisibleRect);
    [self.reader minimapViewDidRequestViewportTopFraction:fraction documentCenterX:documentPoint.x];
    return YES;
}

- (BOOL)documentPointForEvent:(NSEvent*)event documentPoint:(NSPoint*)documentPointOut {
    CGFloat scale = 1.0;
    CGFloat gap = 4.0;
    CGFloat contentTop = 8.0;
    CGFloat contentHeight = 0;
    if (![self layoutScale:&scale gap:&gap contentTop:&contentTop contentHeight:&contentHeight visibleRect:NULL])
        return NO;

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (documentPointOut)
        *documentPointOut = [self documentPointForMinimapCenterPoint:point
                                                               scale:scale
                                                                 gap:gap
                                                       contentHeight:contentHeight
                                                          contentTop:contentTop];
    return YES;
}

- (void)drawPlaceholderInRect:(NSRect)rect {
    if (NSHeight(rect) < 6.0 || NSWidth(rect) < 10.0) return;
    [[NSColor colorWithCalibratedWhite:0.76 alpha:0.34] setFill];
    NSInteger lines = (NSInteger)spdf_clamp_cg(floor(NSHeight(rect) / 7.0), 2.0, 16.0);
    CGFloat y = NSMinY(rect) + MAX(2.0, NSHeight(rect) * 0.08);
    CGFloat lineHeight = MAX(1.0, NSHeight(rect) * 0.018);
    for (NSInteger i = 0; i < lines; ++i) {
        CGFloat widthFactor = (i % 5 == 4) ? 0.56 : 0.78;
        NSRect line = NSMakeRect(NSMinX(rect) + NSWidth(rect) * 0.12, y, NSWidth(rect) * widthFactor, lineHeight);
        NSRectFillUsingOperation(line, NSCompositingOperationSourceOver);
        y += MAX(3.0, NSHeight(rect) / (CGFloat)(lines + 2));
        if (y > NSMaxY(rect) - 2.0) break;
    }
}

- (void)drawRects:(NSArray<NSValue*>*)rects
         pageRect:(NSRect)pageRect
            scale:(CGFloat)scale
            color:(NSColor*)color
        minHeight:(CGFloat)minHeight {
    if (rects.count == 0) return;
    [color setFill];
    for (NSValue* value in rects) {
        NSRect r = [value rectValue];
        r.origin.x = NSMinX(pageRect) + r.origin.x * scale;
        r.origin.y = NSMinY(pageRect) + r.origin.y * scale;
        r.size.width = MAX(1.0, r.size.width * scale);
        r.size.height = MAX(minHeight, r.size.height * scale);
        NSRectFillUsingOperation(NSIntersectionRect(r, pageRect), NSCompositingOperationSourceOver);
    }
}

- (void)drawSearchRects:(NSArray<NSValue*>*)rects pageRect:(NSRect)pageRect scale:(CGFloat)scale {
    if (rects.count == 0) return;
    for (NSValue* value in rects) {
        NSRect r = [value rectValue];
        r.origin.x = NSMinX(pageRect) + r.origin.x * scale;
        r.origin.y = NSMinY(pageRect) + r.origin.y * scale;
        r.size.width = MAX(2.0, r.size.width * scale);
        r.size.height = MAX(3.0, r.size.height * scale);
        CGFloat cx = NSMidX(r);
        CGFloat cy = NSMidY(r);
        r.size.width *= 2.0;
        r.origin.x = cx - NSWidth(r) / 2.0;
        r.origin.y = cy - NSHeight(r) / 2.0;
        r = NSIntersectionRect(r, NSInsetRect(pageRect, -1.0, -1.0));
        if (NSIsEmptyRect(r)) continue;
        [[NSColor colorWithCalibratedRed:1.0 green:0.86 blue:0.06 alpha:0.88] setFill];
        NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:r xRadius:1.5 yRadius:1.5];
        [path fill];
        [[NSColor colorWithCalibratedRed:0.88 green:0.08 blue:0.03 alpha:0.96] setStroke];
        path.lineWidth = 1.1;
        [path stroke];
    }
}

- (void)drawPageContentAtContentTop:(CGFloat)contentTop
                              scale:(CGFloat)scale
                                gap:(CGFloat)gap
                         drawImages:(BOOL)drawImages
                           clipRect:(NSRect)clipRect {
    CGFloat y = contentTop;
    for (SPDFRenderedPage* page in self.pages) {
        CGFloat pageWidth = page.pageWidth * scale;
        CGFloat pageHeight = MAX(1.0, page.pageHeight * scale);
        NSRect pageRect = NSMakeRect(floor((NSWidth(self.bounds) - pageWidth) / 2.0), y, pageWidth, pageHeight);
        if (NSHeight(pageRect) >= 1.0 && NSIntersectsRect(pageRect, clipRect)) {
            [[NSColor whiteColor] setFill];
            NSRectFillUsingOperation(pageRect, NSCompositingOperationSourceOver);
            NSImage* image = page.image ?: page.minimapImage;
            if (drawImages && image && NSHeight(pageRect) >= 5.0) {
                [image drawInRect:pageRect
                          fromRect:NSZeroRect
                         operation:NSCompositingOperationSourceOver
                          fraction:1.0
                    respectFlipped:YES
                             hints:@{NSImageHintInterpolation : @(NSImageInterpolationLow)}];
            } else {
                [self drawPlaceholderInRect:pageRect];
            }
            [self drawSearchRects:page.highlights pageRect:pageRect scale:scale];
            [self drawRects:page.selectionRects
                   pageRect:pageRect
                      scale:scale
                      color:[NSColor colorWithCalibratedRed:0.30 green:0.58 blue:0.93 alpha:0.70]
                  minHeight:1.0];
            if (page.pageIndex == self.currentPageIndex) {
                [[NSColor controlAccentColor] setStroke];
                NSBezierPath* path = [NSBezierPath bezierPathWithRect:NSInsetRect(pageRect, -1, -1)];
                path.lineWidth = 1.5;
                [path stroke];
            }
        }
        y += pageHeight + gap;
    }
}

- (BOOL)contentImageCacheMatchesScale:(CGFloat)scale
                                  gap:(CGFloat)gap
                        contentHeight:(CGFloat)contentHeight
                           drawImages:(BOOL)drawImages {
    return _contentImageCache && _contentImageCachePages == self.pages && _contentImageCacheScale == scale &&
           _contentImageCacheGap == gap && _contentImageCacheHeight == contentHeight &&
           _contentImageCacheBoundsWidth == NSWidth(self.bounds) &&
           _contentImageCacheCurrentPageIndex == self.currentPageIndex && _contentImageCacheDrawImages == drawImages;
}

- (BOOL)rebuildContentImageCacheForScale:(CGFloat)scale
                                     gap:(CGFloat)gap
                           contentHeight:(CGFloat)contentHeight
                              drawImages:(BOOL)drawImages {
    CGFloat width = NSWidth(self.bounds);
    CGFloat height = ceil(MAX(1.0, contentHeight));
    if (width < 1.0 || height < 1.0) return NO;
    if (height > kLiveContentCacheMaxHeight || width * height > kLiveContentCacheMaxPixels) return NO;

    NSImage* image = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
    [image lockFocusFlipped:YES];
    [[NSColor clearColor] setFill];
    NSRectFill(NSMakeRect(0, 0, width, height));
    [self drawPageContentAtContentTop:0.0
                                scale:scale
                                  gap:gap
                           drawImages:drawImages
                             clipRect:NSMakeRect(0, 0, width, height)];
    [image unlockFocus];

    _contentImageCache = image;
    _contentImageCachePages = self.pages;
    _contentImageCacheScale = scale;
    _contentImageCacheGap = gap;
    _contentImageCacheHeight = contentHeight;
    _contentImageCacheBoundsWidth = width;
    _contentImageCacheCurrentPageIndex = self.currentPageIndex;
    _contentImageCacheDrawImages = drawImages;
    return YES;
}

- (BOOL)drawCachedPageContentAtContentTop:(CGFloat)contentTop
                                    scale:(CGFloat)scale
                                      gap:(CGFloat)gap
                            contentHeight:(CGFloat)contentHeight
                               drawImages:(BOOL)drawImages {
    if (![self contentImageCacheMatchesScale:scale gap:gap contentHeight:contentHeight drawImages:drawImages] &&
        ![self rebuildContentImageCacheForScale:scale gap:gap contentHeight:contentHeight drawImages:drawImages])
        return NO;

    [_contentImageCache drawInRect:NSMakeRect(0, contentTop, NSWidth(self.bounds), ceil(MAX(1.0, contentHeight)))
                          fromRect:NSZeroRect
                         operation:NSCompositingOperationSourceOver
                          fraction:1.0
                    respectFlipped:YES
                             hints:@{NSImageHintInterpolation : @(NSImageInterpolationLow)}];
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [NSColor.windowBackgroundColor setFill];
    NSRectFill(self.bounds);
    [NSColor.separatorColor setFill];
    NSRectFill(NSMakeRect(0, 0, 1, NSHeight(self.bounds)));

    CGFloat scale = 1.0;
    CGFloat gap = 4.0;
    CGFloat contentTop = 8.0;
    CGFloat contentHeight = 0;
    NSRect visibleRect = NSZeroRect;
    if (![self layoutScale:&scale
                       gap:&gap
                contentTop:&contentTop
             contentHeight:&contentHeight
               visibleRect:&visibleRect])
        return;

    BOOL drawImages = self.pages.count <= 400;
    BOOL drewCachedContent = self.liveViewportOnly && [self drawCachedPageContentAtContentTop:contentTop
                                                                                        scale:scale
                                                                                          gap:gap
                                                                                contentHeight:contentHeight
                                                                                   drawImages:drawImages];
    if (!drewCachedContent)
        [self drawPageContentAtContentTop:contentTop scale:scale gap:gap drawImages:drawImages clipRect:self.bounds];
    if (!self.liveViewportOnly) [self invalidateContentImageCache];

    if (contentHeight > 1.0) {
        visibleRect = NSIntersectionRect(visibleRect, NSInsetRect(self.bounds, 1.0, 1.0));
        if (NSWidth(visibleRect) > 1.0 && NSHeight(visibleRect) > 1.0) {
            [[NSColor colorWithCalibratedRed:0.18 green:0.55 blue:0.92 alpha:0.18] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:visibleRect xRadius:4 yRadius:4] fill];
            [[NSColor controlAccentColor] setStroke];
            NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:visibleRect xRadius:4 yRadius:4];
            path.lineWidth = 1.2;
            [path stroke];
        }
    }
}

- (NSArray<NSNumber*>*)visiblePageIndexes {
    CGFloat scale = 1.0;
    CGFloat gap = 4.0;
    CGFloat contentTop = 8.0;
    CGFloat contentHeight = 0;
    if (![self layoutScale:&scale gap:&gap contentTop:&contentTop contentHeight:&contentHeight visibleRect:NULL])
        return @[];

    NSMutableArray<NSNumber*>* indexes = [NSMutableArray array];
    for (SPDFRenderedPage* page in self.pages) {
        NSRect miniRect = [self miniRectForPage:page scale:scale gap:gap];
        miniRect.origin.y += contentTop;
        if (NSIntersectsRect(miniRect, self.bounds)) [indexes addObject:@(page.pageIndex)];
    }
    return indexes;
}

- (void)sendScrollRequestForEvent:(NSEvent*)event {
    CGFloat scale = 1.0;
    CGFloat gap = 4.0;
    CGFloat contentTop = 8.0;
    CGFloat contentHeight = 0;
    NSRect visibleRect = NSZeroRect;
    if (![self layoutScale:&scale
                       gap:&gap
                contentTop:&contentTop
             contentHeight:&contentHeight
               visibleRect:&visibleRect])
        return;

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if ([self sendLongDocumentViewportDragForPoint:point
                                             event:event
                                             scale:scale
                                               gap:gap
                                     contentHeight:contentHeight
                                        contentTop:contentTop])
        return;
    if (_draggingVisibleRect) {
        point = NSMakePoint(point.x - _dragOffsetFromVisibleCenter.x, point.y - _dragOffsetFromVisibleCenter.y);
    }
    NSPoint documentPoint = [self documentPointForMinimapCenterPoint:point
                                                               scale:scale
                                                                 gap:gap
                                                       contentHeight:contentHeight
                                                          contentTop:contentTop];
    [self.reader minimapViewDidRequestCenterAtDocumentPoint:documentPoint];
}

- (void)sendClickRequestForEvent:(NSEvent*)event {
    CGFloat scale = 1.0;
    CGFloat gap = 4.0;
    CGFloat contentTop = 8.0;
    CGFloat contentHeight = 0;
    if (![self layoutScale:&scale gap:&gap contentTop:&contentTop contentHeight:&contentHeight visibleRect:NULL])
        return;

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger pageIndex = -1;
    CGFloat xFraction = 0.5;
    CGFloat yFraction = 0.0;
    if ([self pageHitForMiniPoint:point
                            scale:scale
                              gap:gap
                       contentTop:contentTop
                        pageIndex:&pageIndex
                  xFractionInPage:&xFraction
                  yFractionInPage:&yFraction]) {
        [self.reader minimapViewDidRequestCenterOnPage:pageIndex xFractionInPage:xFraction yFractionInPage:yFraction];
    }
}

- (void)mouseDown:(NSEvent*)event {
    spdf_activate_window_for_view(self);

    CGFloat scale = 1.0;
    CGFloat gap = 4.0;
    CGFloat contentTop = 8.0;
    CGFloat contentHeight = 0;
    NSRect visibleRect = NSZeroRect;
    if (![self layoutScale:&scale
                       gap:&gap
                contentTop:&contentTop
             contentHeight:&contentHeight
               visibleRect:&visibleRect])
        return;

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect drawnVisibleRect = [self draggableVisibleRectForRect:visibleRect];
    _pressPending = YES;
    _dragMoved = NO;
    _pressPoint = point;
    _draggingVisibleRect = NSPointInRect(point, drawnVisibleRect);
    _dragOffsetFromVisibleCenter =
        _draggingVisibleRect ? NSMakePoint(point.x - NSMidX(drawnVisibleRect), point.y - NSMidY(drawnVisibleRect))
                             : NSZeroPoint;
    _dragOffsetFromVisibleTop = _draggingVisibleRect ? point.y - NSMinY(drawnVisibleRect) : 0.0;
    _dragThumbTop = _draggingVisibleRect ? NSMinY(drawnVisibleRect) : 0.0;
    if (_draggingVisibleRect && [self shouldUseLongDocumentViewportDrag]) {
        NSRect track = NSInsetRect(self.bounds, 1.0, 1.0);
        CGFloat thumbHeight = [self longDocumentViewportDragThumbHeightForContentHeight:contentHeight track:track];
        CGFloat minTop = NSMinY(track);
        CGFloat maxTop = MAX(minTop, NSMaxY(track) - thumbHeight);
        _dragThumbTop = minTop + [self scrollFraction] * (maxTop - minTop);
    }
    _dragLastMouseY = point.y;
    _dragLastTimestamp = event.timestamp;
}

- (void)mouseDragged:(NSEvent*)event {
    if (_pressPending && !_dragMoved) {
        NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
        if (hypot(point.x - _pressPoint.x, point.y - _pressPoint.y) < 3.0) return;
        _dragMoved = YES;
        _pressPending = NO;
    }
    [self sendScrollRequestForEvent:event];
}

- (void)scrollWheel:(NSEvent*)event {
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    if (flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) {
        NSPoint documentPoint = NSZeroPoint;
        if ([self documentPointForEvent:event documentPoint:&documentPoint])
            [self.reader minimapViewDidReceiveZoomScrollWheel:event documentPoint:documentPoint];
        return;
    }

    [self.reader minimapViewDidReceiveScrollWheel:event];
}

- (void)magnifyWithEvent:(NSEvent*)event {
    NSPoint documentPoint = NSZeroPoint;
    if ([self documentPointForEvent:event documentPoint:&documentPoint])
        [self.reader minimapViewDidReceiveMagnify:event documentPoint:documentPoint];
}

- (void)mouseUp:(NSEvent*)event {
    BOOL didFinishLongDocumentViewportDrag =
        _draggingVisibleRect && _dragMoved && [self shouldUseLongDocumentViewportDrag];
    if (_pressPending && !_dragMoved) [self sendClickRequestForEvent:event];
    _draggingVisibleRect = NO;
    _pressPending = NO;
    _dragMoved = NO;
    _pressPoint = NSZeroPoint;
    _dragOffsetFromVisibleCenter = NSZeroPoint;
    _dragOffsetFromVisibleTop = 0.0;
    _dragThumbTop = 0.0;
    _dragLastMouseY = 0.0;
    _dragLastTimestamp = 0.0;
    if (didFinishLongDocumentViewportDrag) [self.reader minimapViewDidFinishViewportDrag];
}

@end
