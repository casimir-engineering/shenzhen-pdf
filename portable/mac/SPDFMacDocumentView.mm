#import "SPDFMacDocumentView.h"
#import "SPDFMacSupport.h"

#include <math.h>

static const CGFloat kPageMargin = 44.0;
static const CGFloat kPageGap = 26.0;
static const CGFloat kSelectionOverlayAlpha = 0.20;
static const NSUInteger kLiveZoomStaleFullPageDrawByteLimit = (NSUInteger)24 * 1024 * 1024;

// Launch profiling (SPDF_LAUNCH_PROFILE=1): logs the first completed drawRect
// that painted actual document pages — i.e. the first visible paint.
static void spdf_launch_log_first_document_paint(NSUInteger pageCount, double startMs) {
    if (startMs <= 0.0 || pageCount == 0) return;
    static BOOL logged;
    if (logged) return;
    logged = YES;
    spdf_launch_profile_log(@"first document drawRect complete pages=%lu draw=%.1fms", (unsigned long)pageCount,
                            spdf_zoom_profile_now_ms() - startMs);
}

@implementation SPDFDocumentView {
    BOOL _isPanning;
    BOOL _isSelecting;
    BOOL _rightMouseMoved;
    NSPoint _panStartInWindow;
    NSPoint _panStartOrigin;
    NSPoint _lastPanPoint;
    NSTimeInterval _lastPanTime;
    NSPoint _panVelocity;
    NSTimer* _inertiaTimer;
    NSInteger _selectionPageIndex;
    NSPoint _selectionStart;
    NSTrackingArea* _trackingArea;
    NSDictionary* _hoveredComment;
    BOOL _layoutCacheValid;
    NSArray<SPDFRenderedPage*>* _layoutPages;
    NSArray<NSValue*>* _layoutPageSizes;
    NSArray<NSValue*>* _layoutContinuousPageRects;
    NSSize _layoutBoundsSize;
    CGFloat _layoutViewportWidth;
    CGFloat _layoutEffectiveBackingScale;
    CGFloat _layoutZoom;
    BOOL _layoutPresentationMode;
    CGFloat _layoutWidestPage;
    CGFloat _layoutContinuousDocumentHeight;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event {
    (void)event;
    return YES;
}

- (void)copy:(id)sender {
    [self.reader copySelection:sender];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow
               owner:self
            userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)setPages:(NSArray<SPDFRenderedPage*>*)pages {
    _pages = [pages copy];
    [self invalidateLayoutCache];
    [self setNeedsDisplay:YES];
}

- (void)setZoom:(CGFloat)zoom {
    if (_zoom == zoom) return;
    _zoom = zoom;
    [self invalidateLayoutCache];
}

- (void)setViewportWidthHint:(CGFloat)viewportWidthHint {
    if (_viewportWidthHint == viewportWidthHint) return;
    _viewportWidthHint = viewportWidthHint;
    [self invalidateLayoutCache];
}

- (void)setBackingScale:(CGFloat)backingScale {
    if (_backingScale == backingScale) return;
    _backingScale = backingScale;
    [self invalidateLayoutCache];
}

- (void)setPresentationMode:(BOOL)presentationMode {
    if (_presentationMode == presentationMode) return;
    _presentationMode = presentationMode;
    [self invalidateLayoutCache];
}

- (void)setFrameSize:(NSSize)newSize {
    NSSize oldSize = self.frame.size;
    [super setFrameSize:newSize];
    if (fabs(oldSize.width - newSize.width) > 0.001) [self invalidateLayoutCache];
}

- (void)setBoundsSize:(NSSize)newSize {
    NSSize oldSize = self.bounds.size;
    [super setBoundsSize:newSize];
    if (fabs(oldSize.width - newSize.width) > 0.001) [self invalidateLayoutCache];
}

- (CGFloat)effectiveBackingScale {
    CGFloat scale = self.backingScale;
    if (scale <= 0) scale = self.window.backingScaleFactor;
    if (scale <= 0) scale = NSScreen.mainScreen.backingScaleFactor;
    return scale > 0 ? scale : 1.0;
}

- (CGFloat)pixelSnappedLength:(CGFloat)length {
    CGFloat scale = [self effectiveBackingScale];
    return ceil(length * scale - 0.001) / scale;
}

- (CGFloat)pixelSnappedOrigin:(CGFloat)origin {
    CGFloat scale = [self effectiveBackingScale];
    return floor(origin * scale + 0.001) / scale;
}

- (NSSize)viewSizeForPage:(SPDFRenderedPage*)page {
    if (page.image && page.imagePointWidth > 0 && page.imagePointHeight > 0 &&
        fabs(page.imageZoom - self.zoom) < 0.0001)
        return NSMakeSize(page.imagePointWidth, page.imagePointHeight);
    return NSMakeSize([self pixelSnappedLength:page.pageWidth * self.zoom],
                      [self pixelSnappedLength:page.pageHeight * self.zoom]);
}

- (void)invalidateLayoutCache {
    _layoutCacheValid = NO;
    _layoutPages = nil;
    _layoutPageSizes = nil;
    _layoutContinuousPageRects = nil;
}

- (CGFloat)viewportWidth {
    CGFloat width = self.viewportWidthHint > 1.0 ? self.viewportWidthHint : NSWidth(self.bounds);
    NSScrollView* scrollView = self.enclosingScrollView;
    if (scrollView) width = MAX(width, scrollView.contentSize.width);
    return width;
}

- (void)ensureLayoutCache {
    CGFloat viewportWidth = [self viewportWidth];
    CGFloat effectiveBackingScale = [self effectiveBackingScale];
    NSSize boundsSize = self.bounds.size;
    BOOL boundsWidthMatches = fabs(_layoutBoundsSize.width - boundsSize.width) <= 0.001;
    if (_layoutCacheValid && _layoutPages == self.pages && _layoutZoom == self.zoom &&
        _layoutPresentationMode == self.presentationMode &&
        _layoutViewportWidth == viewportWidth && _layoutEffectiveBackingScale == effectiveBackingScale &&
        boundsWidthMatches)
        return;

    CGFloat pageMargin = self.presentationMode ? 0.0 : kPageMargin;
    CGFloat pageGap = self.presentationMode ? 0.0 : kPageGap;
    NSMutableArray<NSValue*>* pageSizes = [NSMutableArray arrayWithCapacity:self.pages.count];
    NSMutableArray<NSValue*>* continuousRects = [NSMutableArray arrayWithCapacity:self.pages.count];

    CGFloat widestPage = 0.0;
    for (SPDFRenderedPage* page in self.pages) {
        NSSize pageSize = [self viewSizeForPage:page];
        [pageSizes addObject:[NSValue valueWithSize:pageSize]];
        widestPage = MAX(widestPage, pageSize.width);
    }

    // Center every page on the same vertical axis — the canvas midline — so a
    // page wider than the viewport (e.g. an oversized schematic) shares its
    // midline with the normal pages instead of being pinned to the left while
    // the narrow pages sit centered in the viewport. The canvas is as wide as the
    // widest page, so center within max(viewportWidth, widestPage); for a uniform
    // document this equals viewportWidth, leaving the prior layout unchanged.
    CGFloat layoutWidth = MAX(viewportWidth, widestPage);
    CGFloat continuousY = pageMargin / 2.0;
    for (NSUInteger i = 0; i < self.pages.count; ++i) {
        NSSize pageSize = [pageSizes[i] sizeValue];
        CGFloat x = floor((layoutWidth - pageSize.width) / 2.0);
        CGFloat minX = pageSize.width >= layoutWidth - 0.5 ? 0.0 : pageMargin / 2.0;
        NSRect continuousRect = NSMakeRect(MAX(minX, [self pixelSnappedOrigin:x]),
                                           [self pixelSnappedOrigin:continuousY], pageSize.width, pageSize.height);
        [continuousRects addObject:[NSValue valueWithRect:continuousRect]];
        continuousY += pageSize.height + pageGap;
    }

    _layoutPages = self.pages;
    _layoutPageSizes = pageSizes;
    _layoutContinuousPageRects = continuousRects;
    _layoutBoundsSize = boundsSize;
    _layoutViewportWidth = viewportWidth;
    _layoutEffectiveBackingScale = effectiveBackingScale;
    _layoutZoom = self.zoom;
    _layoutPresentationMode = self.presentationMode;
    _layoutWidestPage = widestPage;
    _layoutContinuousDocumentHeight = self.pages.count == 0 ? 0.0 : continuousY + pageMargin / 2.0;
    _layoutCacheValid = YES;
}

- (NSSize)cachedViewSizeForPageAtIndex:(NSInteger)pageIndex {
    [self ensureLayoutCache];
    if (pageIndex < 0 || pageIndex >= (NSInteger)_layoutPageSizes.count) return NSZeroSize;
    return [_layoutPageSizes[(NSUInteger)pageIndex] sizeValue];
}

- (NSRect)continuousRectForPageAtIndex:(NSInteger)pageIndex {
    [self ensureLayoutCache];
    if (pageIndex < 0 || pageIndex >= (NSInteger)_layoutContinuousPageRects.count) return NSZeroRect;
    return [_layoutContinuousPageRects[(NSUInteger)pageIndex] rectValue];
}

- (NSRect)convertPageRect:(NSRect)rect toViewRectInPageRect:(NSRect)pageRect page:(SPDFRenderedPage*)page {
    CGFloat scaleX = NSWidth(pageRect) / MAX(1.0, page.pageWidth);
    CGFloat scaleY = NSHeight(pageRect) / MAX(1.0, page.pageHeight);
    rect.origin.x = pageRect.origin.x + rect.origin.x * scaleX;
    rect.origin.y = pageRect.origin.y + rect.origin.y * scaleY;
    rect.size.width *= scaleX;
    rect.size.height *= scaleY;
    return rect;
}

- (NSPoint)convertViewPoint:(NSPoint)point toPagePointInPageRect:(NSRect)pageRect page:(SPDFRenderedPage*)page {
    CGFloat scaleX = NSWidth(pageRect) / MAX(1.0, page.pageWidth);
    CGFloat scaleY = NSHeight(pageRect) / MAX(1.0, page.pageHeight);
    return NSMakePoint((point.x - pageRect.origin.x) / MAX(0.001, scaleX),
                       (point.y - pageRect.origin.y) / MAX(0.001, scaleY));
}

- (NSUInteger)estimatedFullPageImageByteCost:(SPDFRenderedPage*)page {
    if (!page.image || page.imagePointWidth <= 0.0 || page.imagePointHeight <= 0.0) return 0;
    CGFloat scale = page.imageScale > 0.0 ? page.imageScale : [self effectiveBackingScale];
    double pixels = ceil(page.imagePointWidth * scale) * ceil(page.imagePointHeight * scale);
    if (!isfinite(pixels) || pixels <= 0.0) return 0;
    double bytes = pixels * 4.0;
    if (bytes > (double)NSUIntegerMax) return NSUIntegerMax;
    return (NSUInteger)bytes;
}

- (BOOL)shouldDrawStaleFullPageImageDuringLiveZoom:(SPDFRenderedPage*)page {
    if (!page.image) return NO;
    if (fabs(page.imageZoom - self.zoom) <= 0.001) return YES;
    return [self estimatedFullPageImageByteCost:page] <= kLiveZoomStaleFullPageDrawByteLimit;
}

- (BOOL)pageSubrectCoversFullPage:(NSRect)pageSubrect page:(SPDFRenderedPage*)page {
    if (NSIsEmptyRect(pageSubrect) || page.pageWidth <= 0.0 || page.pageHeight <= 0.0) return NO;
    return fabs(NSMinX(pageSubrect)) <= 0.01 && fabs(NSMinY(pageSubrect)) <= 0.01 &&
           fabs(NSWidth(pageSubrect) - page.pageWidth) <= 0.01 &&
           fabs(NSHeight(pageSubrect) - page.pageHeight) <= 0.01;
}

- (BOOL)drawPageImage:(NSImage*)image
          pageSubrect:(NSRect)pageSubrect
               inRect:(NSRect)pageRect
            dirtyRect:(NSRect)dirtyRect
                 page:(SPDFRenderedPage*)page
        interpolation:(NSImageInterpolation)interpolation {
    if (!image || NSIsEmptyRect(pageSubrect)) return NO;
    NSRect imageRect = [self convertPageRect:pageSubrect toViewRectInPageRect:pageRect page:page];
    if (NSIsEmptyRect(imageRect)) return NO;
    NSRect drawRect = NSIntersectionRect(imageRect, dirtyRect);
    if (NSIsEmptyRect(drawRect)) return NO;

    NSGraphicsContext* context = NSGraphicsContext.currentContext;
    NSImageInterpolation oldInterpolation = context.imageInterpolation;
    context.imageInterpolation = interpolation;
    [NSGraphicsContext saveGraphicsState];
    NSRectClip(drawRect);
    double profileStart = spdf_zoom_profile_enabled() ? spdf_zoom_profile_now_ms() : 0.0;
    [image drawInRect:imageRect
             fromRect:NSZeroRect
            operation:NSCompositingOperationSourceOver
             fraction:1.0
       respectFlipped:YES
                hints:@{NSImageHintInterpolation : @(interpolation)}];
    if (spdf_zoom_profile_enabled()) {
        double elapsed = spdf_zoom_profile_now_ms() - profileStart;
        if (elapsed > 2.0)
            spdf_zoom_profile_log(@"drawPageImage page=%ld img=%p size=%.0fx%.0f imageRect=%.0fx%.0f draw=%.0fx%.0f %.2fms",
                                  (long)page.pageIndex, image, image.size.width, image.size.height,
                                  NSWidth(imageRect), NSHeight(imageRect), NSWidth(drawRect), NSHeight(drawRect),
                                  elapsed);
    }
    [NSGraphicsContext restoreGraphicsState];
    context.imageInterpolation = oldInterpolation;
    return YES;
}

- (CGFloat)widestPage {
    [self ensureLayoutCache];
    return _layoutWidestPage;
}

- (CGFloat)continuousDocumentHeight {
    [self ensureLayoutCache];
    return _layoutContinuousDocumentHeight;
}

- (NSInteger)boundedPageIndex:(NSInteger)pageIndex {
    if (self.pages.count == 0) return 0;
    return MAX(0, MIN(pageIndex, (NSInteger)self.pages.count - 1));
}

- (NSSize)documentSizeForClipSize:(NSSize)clipSize {
    CGFloat pageMargin = self.presentationMode ? 0.0 : kPageMargin;
    CGFloat widestPage = [self widestPage];
    CGFloat width = widestPage >= clipSize.width - 0.5 ? MAX(clipSize.width, widestPage)
                                                       : MAX(clipSize.width, widestPage + pageMargin);
    CGFloat height = pageMargin;

    if (self.pages.count == 0) return NSMakeSize(MAX(clipSize.width, 600), MAX(clipSize.height, 500));

    // Presentation mode shows exactly one page (the current one) fit to and
    // centered in the viewport, with no scrolling — the document view is a
    // single viewport and page changes just swap which page is drawn.
    if (self.presentationMode) return NSMakeSize(clipSize.width, clipSize.height);

    height = [self continuousDocumentHeight];
    return NSMakeSize(width, MAX(height, clipSize.height));
}

- (NSRect)presentationRectForPageAtIndex:(NSInteger)pageIndex {
    // Only the current page is shown in presentation mode, centered in the
    // single-viewport document view at its current view size. Other pages are
    // placed far offscreen so nothing else is drawn or hit-tested.
    NSInteger current = MAX(0, MIN(self.currentPageIndex, (NSInteger)self.pages.count - 1));
    if (pageIndex != current) return NSMakeRect(0.0, -1.0e7, 0.0, 0.0);
    NSSize pageSize = [self viewSizeForPage:self.pages[(NSUInteger)current]];
    NSRect bounds = self.bounds;
    CGFloat x = [self pixelSnappedOrigin:NSMinX(bounds) + (NSWidth(bounds) - pageSize.width) / 2.0];
    CGFloat y = [self pixelSnappedOrigin:NSMinY(bounds) + (NSHeight(bounds) - pageSize.height) / 2.0];
    return NSMakeRect(x, y, pageSize.width, pageSize.height);
}

- (NSRect)rectForPageAtIndex:(NSInteger)pageIndex {
    if (pageIndex < 0 || pageIndex >= (NSInteger)self.pages.count) return NSZeroRect;
    if (self.presentationMode) return [self presentationRectForPageAtIndex:pageIndex];
    return [self continuousRectForPageAtIndex:pageIndex];
}

- (NSInteger)pageIndexForVisibleRect:(NSRect)visibleRect {
    if (self.pages.count == 0) return 0;

    NSInteger bestPage = self.currentPageIndex;
    CGFloat bestOverlap = -1;
    CGFloat visibleMidY = NSMidY(visibleRect);
    CGFloat bestCenterDistance = CGFLOAT_MAX;
    CGFloat closestDistance = CGFLOAT_MAX;
    for (SPDFRenderedPage* page in self.pages) {
        NSRect pageRect = [self rectForPageAtIndex:page.pageIndex];
        CGFloat overlap = NSHeight(NSIntersectionRect(visibleRect, pageRect));
        CGFloat centerDistance = fabs(NSMidY(pageRect) - visibleMidY);
        if (overlap > bestOverlap + 0.5 ||
            (overlap > 0.0 && fabs(overlap - bestOverlap) <= 0.5 && centerDistance < bestCenterDistance)) {
            bestOverlap = overlap;
            bestCenterDistance = centerDistance;
            bestPage = page.pageIndex;
        }
        if (overlap <= 0.0) {
            CGFloat distance =
                visibleMidY < NSMinY(pageRect) ? NSMinY(pageRect) - visibleMidY : visibleMidY - NSMaxY(pageRect);
            if (distance < closestDistance) {
                closestDistance = distance;
                if (bestOverlap <= 0.0) bestPage = page.pageIndex;
            }
        }
    }
    return bestPage;
}

- (void)drawPage:(SPDFRenderedPage*)page inRect:(NSRect)pageRect dirtyRect:(NSRect)dirtyRect {
    NSShadow* shadow = [[NSShadow alloc] init];
    shadow.shadowBlurRadius = 12.0;
    shadow.shadowOffset = NSMakeSize(0.0, -2.0);
    shadow.shadowColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.28];

    [NSGraphicsContext saveGraphicsState];
    if (!self.presentationMode) [shadow set];
    [[NSColor whiteColor] setFill];
    NSRectFill(pageRect);
    [NSGraphicsContext restoreGraphicsState];

    BOOL hasLiveZoomSeed = self.liveZooming && page.zoomSeedImage && !NSIsEmptyRect(page.zoomSeedPageRect);
    BOOL liveZoomSeedCoversFullPage = hasLiveZoomSeed && [self pageSubrectCoversFullPage:page.zoomSeedPageRect page:page];
    BOOL drewLiveZoomSeed = liveZoomSeedCoversFullPage &&
                            [self drawPageImage:page.zoomSeedImage
                                    pageSubrect:page.zoomSeedPageRect
                                         inRect:pageRect
                                      dirtyRect:dirtyRect
                                           page:page
                                  interpolation:NSImageInterpolationHigh];

    BOOL hasExactFullPageImage = page.image && fabs(page.imageZoom - self.zoom) <= 0.001 &&
                                 fabs(page.imageScale - [self effectiveBackingScale]) <= 0.001;
    BOOL hasReusableViewportImage = page.viewportImage && !NSIsEmptyRect(page.viewportImagePageRect);
    BOOL hasHighQualityImage = page.highQualityImage && page.highQualityImagePointWidth > 0.0 &&
                               page.highQualityImagePointHeight > 0.0;
    BOOL hasBaseImage = page.baseImage && page.baseImagePointWidth > 0.0 && page.baseImagePointHeight > 0.0;
    NSRect fullPageSubrect = NSMakeRect(0.0, 0.0, page.pageWidth, page.pageHeight);
    NSImage* image = nil;
    NSImageInterpolation imageInterpolation = NSImageInterpolationHigh;
    if (hasExactFullPageImage) image = page.image;
    else if (self.liveZooming && hasHighQualityImage)
        image = page.highQualityImage;
    else if (self.liveZooming && hasBaseImage)
        image = page.baseImage;
    else if (self.liveZooming && [self shouldDrawStaleFullPageImageDuringLiveZoom:page])
        image = page.image;
    else if (self.liveZooming && !hasReusableViewportImage)
        image = page.minimapImage;
    else if (self.liveZooming)
        image = nil;
    else image = page.image ?: page.highQualityImage ?: page.baseImage ?: page.minimapImage;
    if (!drewLiveZoomSeed && image) {
        BOOL drawingExactImage = hasExactFullPageImage && page.image == image;
        BOOL exactSize = drawingExactImage && fabs(NSWidth(pageRect) - page.imagePointWidth) < 0.01 &&
                         fabs(NSHeight(pageRect) - page.imagePointHeight) < 0.01;
        imageInterpolation = exactSize ? NSImageInterpolationNone : NSImageInterpolationHigh;
        [self drawPageImage:image
                pageSubrect:fullPageSubrect
                     inRect:pageRect
                  dirtyRect:dirtyRect
                       page:page
              interpolation:imageInterpolation];
    }

    BOOL hasCurrentViewportImage = page.viewportImage && fabs(page.viewportImageZoom - self.zoom) <= 0.001 &&
                                   fabs(page.viewportImageScale - [self effectiveBackingScale]) <= 0.001;
    BOOL canDrawViewportImage = hasCurrentViewportImage || (self.liveZooming && hasReusableViewportImage);
    if (!drewLiveZoomSeed && !hasExactFullPageImage && canDrawViewportImage) {
        [self drawPageImage:page.viewportImage
                pageSubrect:page.viewportImagePageRect
                     inRect:pageRect
                  dirtyRect:dirtyRect
                       page:page
              interpolation:NSImageInterpolationHigh];
    }

    if (hasLiveZoomSeed && !drewLiveZoomSeed) {
        [self drawPageImage:page.zoomSeedImage
                pageSubrect:page.zoomSeedPageRect
                     inRect:pageRect
                  dirtyRect:dirtyRect
                       page:page
              interpolation:NSImageInterpolationHigh];
    }

    if (page.highlights.count > 0 && self.zoom > 0) {
        [[NSColor colorWithCalibratedRed:1.0 green:0.84 blue:0.12 alpha:0.38] setFill];
        for (NSValue* value in page.highlights) {
            NSRect r = [self convertPageRect:[value rectValue] toViewRectInPageRect:pageRect page:page];
            [[NSBezierPath bezierPathWithRoundedRect:r xRadius:2.0 yRadius:2.0] fill];
        }
    }

    if (self.activeFindAlpha > 0 && page.pageIndex == self.activeFindPageIndex && self.zoom > 0) {
        NSRect r = [self convertPageRect:self.activeFindRect toViewRectInPageRect:pageRect page:page];
        r = NSInsetRect(r, -2.0, -2.0);
        [[NSColor colorWithCalibratedRed:0.94 green:0.03 blue:0.02 alpha:self.activeFindAlpha] setStroke];
        NSBezierPath* path = [NSBezierPath bezierPathWithRect:r];
        path.lineWidth = 1.2;
        [path stroke];
    }

    if (page.selectionRects.count > 0 && self.zoom > 0) {
        [[NSColor colorWithCalibratedRed:0.40 green:0.62 blue:0.86 alpha:kSelectionOverlayAlpha] setFill];
        for (NSValue* value in page.selectionRects) {
            NSRect r = [self convertPageRect:[value rectValue] toViewRectInPageRect:pageRect page:page];
            NSRectFillUsingOperation(r, NSCompositingOperationSourceOver);
        }
    }

    NSArray<NSDictionary*>* comments = [self.reader commentAnnotationsForPage:page.pageIndex];
    if (comments.count > 0 && self.zoom > 0) {
        [[NSColor colorWithCalibratedRed:1.0 green:0.76 blue:0.10 alpha:0.16] setFill];
        [[NSColor colorWithCalibratedRed:0.92 green:0.52 blue:0.0 alpha:0.95] setStroke];
        for (NSDictionary* comment in comments) {
            NSRect r = [self convertPageRect:[comment[@"bounds"] rectValue] toViewRectInPageRect:pageRect page:page];
            r = NSInsetRect(r, -2.0, -2.0);
            NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:r xRadius:3.0 yRadius:3.0];
            [path fill];
            path.lineWidth = 1.2;
            [path stroke];
        }
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    double profileStart = spdf_zoom_profile_enabled() ? spdf_zoom_profile_now_ms() : 0.0;
    double launchPaintStart = spdf_launch_profile_enabled() ? spdf_zoom_profile_now_ms() : 0.0;
    [(self.presentationMode ? NSColor.blackColor : NSColor.windowBackgroundColor) setFill];
    NSRectFill(dirtyRect);

    if (self.pages.count == 0) {
        NSMutableParagraphStyle* style = [[NSMutableParagraphStyle alloc] init];
        style.alignment = NSTextAlignmentCenter;
        NSDictionary* attrs = @{
            NSForegroundColorAttributeName : [NSColor secondaryLabelColor],
            NSFontAttributeName : [NSFont systemFontOfSize:16 weight:NSFontWeightMedium],
            NSParagraphStyleAttributeName : style
        };
        NSString* message = self.emptyMessage.length ? self.emptyMessage : @"Open a document";
        NSRect textRect =
            NSMakeRect(32.0, MAX(72.0, NSMidY(self.bounds) - 18.0), MAX(1.0, NSWidth(self.bounds) - 64.0), 44.0);
        [message drawWithRect:textRect
                      options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine
                   attributes:attrs];
        return;
    }

    if (self.presentationMode) {
        NSInteger index = MAX(0, MIN(self.currentPageIndex, (NSInteger)self.pages.count - 1));
        SPDFRenderedPage* page = self.pages[(NSUInteger)index];
        NSRect pageRect = [self rectForPageAtIndex:index];
        if (NSIntersectsRect(dirtyRect, pageRect)) [self drawPage:page inRect:pageRect dirtyRect:dirtyRect];
        spdf_launch_log_first_document_paint(self.pages.count, launchPaintStart);
        return;
    }

    for (SPDFRenderedPage* page in self.pages) {
        NSRect pageRect = [self rectForPageAtIndex:page.pageIndex];
        if (NSMaxY(pageRect) < NSMinY(dirtyRect) - 1.0) continue;
        if (NSMinY(pageRect) > NSMaxY(dirtyRect) + 1.0) break;
        if (NSIntersectsRect(dirtyRect, pageRect)) [self drawPage:page inRect:pageRect dirtyRect:dirtyRect];
    }
    if (spdf_zoom_profile_enabled()) {
        double elapsed = spdf_zoom_profile_now_ms() - profileStart;
        if (elapsed > 2.0)
            spdf_zoom_profile_log(@"drawRect liveZoom=%d zoom=%.2f dirty=%.0fx%.0f total=%.2fms", self.liveZooming,
                                  self.zoom, NSWidth(dirtyRect), NSHeight(dirtyRect), elapsed);
    }
    spdf_launch_log_first_document_paint(self.pages.count, launchPaintStart);
}

- (BOOL)point:(NSPoint)point fallsInPage:(NSInteger*)pageIndex pagePoint:(NSPoint*)pagePoint {
    for (SPDFRenderedPage* page in self.pages) {
        NSRect pageRect = [self rectForPageAtIndex:page.pageIndex];
        if (NSMaxY(pageRect) < point.y - 1.0) continue;
        if (NSMinY(pageRect) > point.y + 1.0) break;
        if (NSPointInRect(point, pageRect)) {
            if (pageIndex) *pageIndex = page.pageIndex;
            if (pagePoint) *pagePoint = [self convertViewPoint:point toPagePointInPageRect:pageRect page:page];
            return YES;
        }
    }
    return NO;
}

- (void)updateHoveredCommentForEvent:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSPoint pagePoint = NSZeroPoint;
    NSInteger pageIndex = -1;
    NSDictionary* hitComment = nil;
    if ([self point:point fallsInPage:&pageIndex pagePoint:&pagePoint]) {
        for (NSDictionary* comment in [self.reader commentAnnotationsForPage:pageIndex]) {
            NSRect bounds = [comment[@"bounds"] rectValue];
            if (NSPointInRect(pagePoint, NSInsetRect(bounds, -3.0, -3.0))) {
                hitComment = comment;
                break;
            }
        }
    }

    if (hitComment == _hoveredComment || [hitComment isEqualToDictionary:_hoveredComment]) {
        if (hitComment) [self.reader documentViewHoverComment:hitComment atWindowPoint:event.locationInWindow];
        return;
    }

    _hoveredComment = hitComment;
    if (hitComment) [self.reader documentViewHoverComment:hitComment atWindowPoint:event.locationInWindow];
    else [self.reader documentViewEndHoverComment];
}

- (void)mouseDown:(NSEvent*)event {
    spdf_activate_window_for_view(self);
    [self.reader clearFindFieldFocus];
    if (!self.reader) {
        [super mouseDown:event];
        return;
    }
    if ([self.reader handlePresentationEvent:event]) return;
    if (event.modifierFlags & NSEventModifierFlagControl) {
        [self.reader showContextMenuForDocumentView:self event:event];
        return;
    }

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSPoint pagePoint = NSZeroPoint;
    NSInteger pageIndex = -1;
    if ([self point:point fallsInPage:&pageIndex pagePoint:&pagePoint]) {
        if ([self.reader documentViewOpenLinkAtPageIndex:pageIndex pagePoint:pagePoint]) return;
        _isSelecting = YES;
        _selectionPageIndex = pageIndex;
        _selectionStart = pagePoint;
        [self.reader documentViewSelectionChangedOnPage:pageIndex from:pagePoint to:pagePoint];
    } else {
        [super mouseDown:event];
    }
}

- (void)mouseMoved:(NSEvent*)event {
    [self updateHoveredCommentForEvent:event];
    if (!self.reader) return;
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSPoint pagePoint = NSZeroPoint;
    NSInteger pageIndex = -1;
    BOOL hasLink = [self point:point fallsInPage:&pageIndex pagePoint:&pagePoint] &&
                   [self.reader documentViewHasLinkAtPageIndex:pageIndex pagePoint:pagePoint];
    [(hasLink ? NSCursor.pointingHandCursor : NSCursor.arrowCursor) set];
}

- (void)mouseExited:(NSEvent*)event {
    (void)event;
    _hoveredComment = nil;
    [self.reader documentViewEndHoverComment];
    [NSCursor.arrowCursor set];
}

- (void)keyDown:(NSEvent*)event {
    if (self.reader && [self.reader handlePresentationEvent:event]) return;
    if (self.reader && [self.reader documentArrowKeyDown:event]) return;
    if (self.reader && [self.reader documentTypeToSearchKeyDown:event]) return;
    [super keyDown:event];
}

- (void)mouseDragged:(NSEvent*)event {
    [self.reader clearFindFieldFocus];
    if (_isPanning) {
        [self continuePanWithEvent:event];
        return;
    }
    if (!_isSelecting) {
        [super mouseDragged:event];
        return;
    }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect pageRect = [self rectForPageAtIndex:_selectionPageIndex];
    if (NSIsEmptyRect(pageRect)) return;
    SPDFRenderedPage* page = self.pages[(NSUInteger)_selectionPageIndex];
    NSPoint pagePoint = [self convertViewPoint:point toPagePointInPageRect:pageRect page:page];
    [self.reader documentViewSelectionChangedOnPage:_selectionPageIndex from:_selectionStart to:pagePoint];
}

- (void)mouseUp:(NSEvent*)event {
    (void)event;
    if (_isPanning) {
        [self endPan];
        return;
    }
    _isSelecting = NO;
}

- (void)beginPanWithEvent:(NSEvent*)event {
    [self beginPanWithWindowPoint:event.locationInWindow timestamp:event.timestamp];
}

- (void)beginPanWithWindowPoint:(NSPoint)windowPoint timestamp:(NSTimeInterval)timestamp {
    spdf_activate_window_for_view(self);
    [self.reader clearFindFieldFocus];
    NSScrollView* scrollView = self.enclosingScrollView;
    if (!scrollView) return;
    [_inertiaTimer invalidate];
    _inertiaTimer = nil;
    _isPanning = YES;
    _isSelecting = NO;
    _panStartInWindow = windowPoint;
    _panStartOrigin = scrollView.contentView.bounds.origin;
    _lastPanPoint = windowPoint;
    _lastPanTime = timestamp;
    _panVelocity = NSZeroPoint;
    [[NSCursor closedHandCursor] set];
    [self.reader documentViewDidBeginPan];
}

- (void)continuePanWithEvent:(NSEvent*)event {
    if (!_isPanning) return;

    NSPoint current = event.locationInWindow;
    NSPoint delta = NSMakePoint(current.x - _panStartInWindow.x, current.y - _panStartInWindow.y);
    NSPoint origin = NSMakePoint(_panStartOrigin.x - delta.x, _panStartOrigin.y + delta.y);
    NSTimeInterval dt = MAX(0.001, event.timestamp - _lastPanTime);
    _panVelocity = NSMakePoint((current.x - _lastPanPoint.x) / dt, (current.y - _lastPanPoint.y) / dt);
    _lastPanPoint = current;
    _lastPanTime = event.timestamp;
    // The reader clamps (centering a viewport-fit page, panning a wider one),
    // applies the scroll, and posts the position change.
    [self.reader documentViewPanToProposedOrigin:origin];
}

- (void)stepPanInertia:(NSTimer*)timer {
    NSScrollView* scrollView = self.enclosingScrollView;
    NSClipView* clipView = scrollView.contentView;
    if (!scrollView || !clipView) {
        [timer invalidate];
        _inertiaTimer = nil;
        [self.reader documentViewDidFinishPanMotion];
        return;
    }

    NSPoint origin = clipView.bounds.origin;
    origin.x -= _panVelocity.x / 60.0;
    origin.y += _panVelocity.y / 60.0;
    [self.reader documentViewPanToProposedOrigin:origin];

    _panVelocity.x *= 0.90;
    _panVelocity.y *= 0.90;
    if (hypot(_panVelocity.x, _panVelocity.y) < 12.0) {
        [timer invalidate];
        _inertiaTimer = nil;
        [self.reader documentViewDidFinishPanMotion];
    }
}

- (void)endPan {
    _isPanning = NO;
    [[NSCursor arrowCursor] set];
    if (hypot(_panVelocity.x, _panVelocity.y) > 90.0) {
        [_inertiaTimer invalidate];
        _inertiaTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
                                                         target:self
                                                       selector:@selector(stepPanInertia:)
                                                       userInfo:nil
                                                        repeats:YES];
    } else {
        [self.reader documentViewDidFinishPanMotion];
    }
}

- (void)cancelTransientInteraction {
    [_inertiaTimer invalidate];
    _inertiaTimer = nil;
    _isPanning = NO;
    _isSelecting = NO;
    _rightMouseMoved = NO;
    _panVelocity = NSZeroPoint;
    _selectionPageIndex = -1;
    [[NSCursor arrowCursor] set];
}

- (void)rightMouseDown:(NSEvent*)event {
    spdf_activate_window_for_view(self);
    _rightMouseMoved = NO;
    if (self.reader && [self.reader handlePresentationEvent:event]) {
        _rightMouseMoved = YES;
        return;
    }
    if (event.modifierFlags & NSEventModifierFlagCommand) return;
    [self beginPanWithEvent:event];
}

- (void)rightMouseDragged:(NSEvent*)event {
    _rightMouseMoved = YES;
    if (_isPanning) [self continuePanWithEvent:event];
}

- (void)rightMouseUp:(NSEvent*)event {
    if (self.reader && [self.reader documentViewInPresentationMode]) return;
    BOOL forceMenu = (event.modifierFlags & NSEventModifierFlagCommand) != 0;
    if (forceMenu || !_rightMouseMoved) [self.reader showContextMenuForDocumentView:self event:event];
    if (_isPanning) [self endPan];
}

- (void)otherMouseDown:(NSEvent*)event {
    if (event.buttonNumber == 2) [self beginPanWithEvent:event];
    else [super otherMouseDown:event];
}

- (void)otherMouseDragged:(NSEvent*)event {
    if (_isPanning) [self continuePanWithEvent:event];
    else [super otherMouseDragged:event];
}

- (void)otherMouseUp:(NSEvent*)event {
    if (_isPanning) [self endPan];
    else [super otherMouseUp:event];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    (void)sender;
    return NSDragOperationCopy;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    return [self.reader openFilesFromPasteboard:sender.draggingPasteboard];
}

@end
