#import "SPDFMacDocumentView.h"

#include <math.h>

static const CGFloat kPageMargin = 44.0;
static const CGFloat kPageGap = 26.0;
static const CGFloat kSelectionOverlayAlpha = 0.20;

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
    [self setNeedsDisplay:YES];
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

- (CGFloat)widestPage {
    CGFloat widest = 0;
    for (SPDFRenderedPage* page in self.pages) widest = MAX(widest, [self viewSizeForPage:page].width);
    return widest;
}

- (CGFloat)viewportWidth {
    CGFloat width = self.viewportWidthHint > 1.0 ? self.viewportWidthHint : NSWidth(self.bounds);
    NSScrollView* scrollView = self.enclosingScrollView;
    if (scrollView) width = MAX(width, scrollView.contentSize.width);
    return width;
}

- (CGFloat)continuousDocumentHeight {
    if (self.pages.count == 0) return 0.0;

    CGFloat pageMargin = self.presentationMode ? 0.0 : kPageMargin;
    CGFloat pageGap = self.presentationMode ? 0.0 : kPageGap;
    CGFloat height = pageMargin / 2.0;
    for (SPDFRenderedPage* page in self.pages) height += [self viewSizeForPage:page].height + pageGap;
    height += pageMargin / 2.0;
    return height;
}

- (NSRect)singlePageDocumentSlotForPageAtIndex:(NSInteger)pageIndex {
    if (pageIndex < 0 || pageIndex >= (NSInteger)self.pages.count) return NSZeroRect;

    CGFloat pageMargin = self.presentationMode ? 0.0 : kPageMargin;
    CGFloat pageGap = self.presentationMode ? 0.0 : kPageGap;
    CGFloat documentWidth = MAX(NSWidth(self.bounds), [self widestPage] + pageMargin);
    SPDFRenderedPage* page = self.pages[(NSUInteger)pageIndex];
    NSSize pageSize = [self viewSizeForPage:page];
    CGFloat y = pageMargin / 2.0;
    for (NSInteger i = 0; i < pageIndex; ++i) y += [self viewSizeForPage:self.pages[(NSUInteger)i]].height + pageGap;
    CGFloat x = floor((documentWidth - pageSize.width) / 2.0);
    CGFloat minX = pageSize.width >= documentWidth - 0.5 ? 0.0 : pageMargin / 2.0;
    return NSMakeRect(MAX(minX, [self pixelSnappedOrigin:x]), [self pixelSnappedOrigin:y], pageSize.width,
                      pageSize.height);
}

- (NSInteger)boundedPageIndex:(NSInteger)pageIndex {
    if (self.pages.count == 0) return 0;
    return MAX(0, MIN(pageIndex, (NSInteger)self.pages.count - 1));
}

- (NSSize)singlePageDocumentSizeForClipSize:(NSSize)clipSize page:(SPDFRenderedPage*)page {
    NSSize pageSize = [self viewSizeForPage:page];
    CGFloat width = pageSize.width >= clipSize.width - 0.5 ? MAX(clipSize.width, pageSize.width)
                                                           : MAX(clipSize.width, pageSize.width + kPageMargin);
    CGFloat height = self.pages.count > 1 ? [self continuousDocumentHeight] : pageSize.height + kPageMargin;
    height = MAX(clipSize.height, height);
    return NSMakeSize(width, height);
}

- (NSSize)documentSizeForClipSize:(NSSize)clipSize {
    CGFloat pageMargin = self.presentationMode ? 0.0 : kPageMargin;
    CGFloat pageGap = self.presentationMode ? 0.0 : kPageGap;
    CGFloat widestPage = [self widestPage];
    CGFloat width = widestPage >= clipSize.width - 0.5 ? MAX(clipSize.width, widestPage)
                                                       : MAX(clipSize.width, widestPage + pageMargin);
    CGFloat height = pageMargin;

    if (self.pages.count == 0) return NSMakeSize(MAX(clipSize.width, 600), MAX(clipSize.height, 500));

    if (self.presentationMode && self.viewMode == SPDFViewModeSingle)
        return NSMakeSize(clipSize.width, clipSize.height);

    if (self.viewMode == SPDFViewModeSingle) {
        NSInteger pageIndex = [self boundedPageIndex:self.currentPageIndex];
        return [self singlePageDocumentSizeForClipSize:clipSize page:self.pages[(NSUInteger)pageIndex]];
    } else {
        height = pageMargin / 2.0;
        for (SPDFRenderedPage* page in self.pages) {
            CGFloat pageHeight = [self viewSizeForPage:page].height;
            height += pageHeight + pageGap;
        }
        height += pageMargin / 2.0;
    }

    return NSMakeSize(width, MAX(height, clipSize.height));
}

- (NSRect)rectForPageAtIndex:(NSInteger)pageIndex {
    if (pageIndex < 0 || pageIndex >= (NSInteger)self.pages.count) return NSZeroRect;

    CGFloat pageMargin = self.presentationMode ? 0.0 : kPageMargin;
    SPDFRenderedPage* page = self.pages[(NSUInteger)pageIndex];
    NSSize pageSize = [self viewSizeForPage:page];
    CGFloat width = pageSize.width;
    CGFloat height = pageSize.height;
    CGFloat viewportWidth = [self viewportWidth];
    CGFloat x = floor((viewportWidth - width) / 2.0);
    CGFloat minX = width >= viewportWidth - 0.5 ? 0.0 : pageMargin / 2.0;
    if (self.viewMode == SPDFViewModeSingle) {
        NSClipView* clipView = self.enclosingScrollView.contentView;
        NSRect visibleRect =
            clipView ? clipView.bounds : NSMakeRect(0.0, 0.0, NSWidth(self.bounds), NSHeight(self.bounds));
        CGFloat centeredY = NSMinY(visibleRect) + floor((NSHeight(visibleRect) - height) / 2.0);
        CGFloat minY = self.presentationMode ? 0.0 : kPageMargin / 2.0;
        if (self.pages.count > 1) minY = -CGFLOAT_MAX;
        return NSMakeRect(MAX(minX, [self pixelSnappedOrigin:x]), MAX(minY, [self pixelSnappedOrigin:centeredY]), width,
                          height);
    }

    CGFloat pageGap = self.presentationMode ? 0.0 : kPageGap;
    CGFloat y = pageMargin / 2.0;
    for (NSInteger i = 0; i < pageIndex; ++i) {
        SPDFRenderedPage* prev = self.pages[(NSUInteger)i];
        y += [self viewSizeForPage:prev].height + pageGap;
    }
    return NSMakeRect(MAX(minX, [self pixelSnappedOrigin:x]), [self pixelSnappedOrigin:y], width, height);
}

- (NSInteger)pageIndexForVisibleRect:(NSRect)visibleRect {
    if (self.pages.count == 0) return 0;

    NSInteger bestPage = self.currentPageIndex;
    CGFloat bestOverlap = -1;
    CGFloat visibleMidY = NSMidY(visibleRect);
    CGFloat bestCenterDistance = CGFLOAT_MAX;
    CGFloat closestDistance = CGFLOAT_MAX;
    for (SPDFRenderedPage* page in self.pages) {
        NSRect pageRect = self.viewMode == SPDFViewModeSingle
                              ? [self singlePageDocumentSlotForPageAtIndex:page.pageIndex]
                              : [self rectForPageAtIndex:page.pageIndex];
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

- (void)drawPage:(SPDFRenderedPage*)page inRect:(NSRect)pageRect {
    NSShadow* shadow = [[NSShadow alloc] init];
    shadow.shadowBlurRadius = 12.0;
    shadow.shadowOffset = NSMakeSize(0.0, -2.0);
    shadow.shadowColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.28];

    [NSGraphicsContext saveGraphicsState];
    if (!self.presentationMode) [shadow set];
    [[NSColor whiteColor] setFill];
    NSRectFill(pageRect);
    [NSGraphicsContext restoreGraphicsState];

    BOOL hasExactFullPageImage = page.image && fabs(page.imageZoom - self.zoom) <= 0.001 &&
                                 fabs(page.imageScale - [self effectiveBackingScale]) <= 0.001;
    NSImage* image = page.image ?: page.minimapImage;
    if (image) {
        BOOL drawingExactImage = page.image == image;
        BOOL exactSize = drawingExactImage && fabs(NSWidth(pageRect) - page.imagePointWidth) < 0.01 &&
                         fabs(NSHeight(pageRect) - page.imagePointHeight) < 0.01;
        NSGraphicsContext* context = NSGraphicsContext.currentContext;
        NSImageInterpolation oldInterpolation = context.imageInterpolation;
        NSImageInterpolation interpolation = exactSize ? NSImageInterpolationNone : NSImageInterpolationHigh;
        context.imageInterpolation = interpolation;
        [image drawInRect:pageRect
                  fromRect:NSZeroRect
                 operation:NSCompositingOperationSourceOver
                  fraction:1.0
            respectFlipped:YES
                     hints:@{NSImageHintInterpolation : @(interpolation)}];
        context.imageInterpolation = oldInterpolation;
    }

    if (!hasExactFullPageImage && page.viewportImage) {
        NSRect cropRect = [self convertPageRect:page.viewportImagePageRect toViewRectInPageRect:pageRect page:page];
        if (!NSIsEmptyRect(cropRect)) {
            NSGraphicsContext* context = NSGraphicsContext.currentContext;
            NSImageInterpolation oldInterpolation = context.imageInterpolation;
            context.imageInterpolation = NSImageInterpolationHigh;
            [page.viewportImage drawInRect:cropRect
                                  fromRect:NSZeroRect
                                 operation:NSCompositingOperationSourceOver
                                  fraction:1.0
                            respectFlipped:YES
                                     hints:@{NSImageHintInterpolation : @(NSImageInterpolationHigh)}];
            context.imageInterpolation = oldInterpolation;
        }
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
    [(self.presentationMode ? NSColor.blackColor : NSColor.windowBackgroundColor) setFill];
    NSRectFill(self.bounds);

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

    if (self.viewMode == SPDFViewModeSingle) {
        NSInteger index = MAX(0, MIN(self.currentPageIndex, (NSInteger)self.pages.count - 1));
        SPDFRenderedPage* page = self.pages[(NSUInteger)index];
        NSRect pageRect = [self rectForPageAtIndex:index];
        if (NSIntersectsRect(dirtyRect, pageRect)) [self drawPage:page inRect:pageRect];
        return;
    }

    for (SPDFRenderedPage* page in self.pages) {
        NSRect pageRect = [self rectForPageAtIndex:page.pageIndex];
        if (NSIntersectsRect(dirtyRect, pageRect)) [self drawPage:page inRect:pageRect];
    }
}

- (BOOL)point:(NSPoint)point fallsInPage:(NSInteger*)pageIndex pagePoint:(NSPoint*)pagePoint {
    if (self.viewMode == SPDFViewModeSingle && self.pages.count > 0) {
        NSInteger index = MAX(0, MIN(self.currentPageIndex, (NSInteger)self.pages.count - 1));
        NSRect pageRect = [self rectForPageAtIndex:index];
        if (NSPointInRect(point, pageRect)) {
            if (pageIndex) *pageIndex = index;
            if (pagePoint)
                *pagePoint = [self convertViewPoint:point
                              toPagePointInPageRect:pageRect
                                               page:self.pages[(NSUInteger)index]];
            return YES;
        }
        return NO;
    }

    for (SPDFRenderedPage* page in self.pages) {
        NSRect pageRect = [self rectForPageAtIndex:page.pageIndex];
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
    if (hitComment)
        [self.reader documentViewHoverComment:hitComment atWindowPoint:event.locationInWindow];
    else
        [self.reader documentViewEndHoverComment];
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
    _isSelecting = NO;
}

- (void)beginPanWithEvent:(NSEvent*)event {
    spdf_activate_window_for_view(self);
    [self.reader clearFindFieldFocus];
    NSScrollView* scrollView = self.enclosingScrollView;
    if (!scrollView) return;
    [_inertiaTimer invalidate];
    _inertiaTimer = nil;
    _isPanning = YES;
    _panStartInWindow = event.locationInWindow;
    _panStartOrigin = scrollView.contentView.bounds.origin;
    _lastPanPoint = event.locationInWindow;
    _lastPanTime = event.timestamp;
    _panVelocity = NSZeroPoint;
    [[NSCursor closedHandCursor] set];
    [self.reader documentViewDidBeginPan];
}

- (void)continuePanWithEvent:(NSEvent*)event {
    if (!_isPanning) return;

    NSScrollView* scrollView = self.enclosingScrollView;
    NSClipView* clipView = scrollView.contentView;
    NSPoint current = event.locationInWindow;
    NSPoint delta = NSMakePoint(current.x - _panStartInWindow.x, current.y - _panStartInWindow.y);
    NSPoint origin = NSMakePoint(_panStartOrigin.x - delta.x, _panStartOrigin.y + delta.y);
    NSTimeInterval dt = MAX(0.001, event.timestamp - _lastPanTime);
    _panVelocity = NSMakePoint((current.x - _lastPanPoint.x) / dt, (current.y - _lastPanPoint.y) / dt);
    _lastPanPoint = current;
    _lastPanTime = event.timestamp;
    origin.x = MAX(0, MIN(origin.x, MAX(0, NSWidth(self.bounds) - NSWidth(clipView.bounds))));
    origin.y = MAX(0, MIN(origin.y, MAX(0, NSHeight(self.bounds) - NSHeight(clipView.bounds))));
    [clipView scrollToPoint:origin];
    [scrollView reflectScrolledClipView:clipView];
    [self.reader documentScrollPositionChanged];
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
    origin.x = MAX(0, MIN(origin.x, MAX(0, NSWidth(self.bounds) - NSWidth(clipView.bounds))));
    origin.y = MAX(0, MIN(origin.y, MAX(0, NSHeight(self.bounds) - NSHeight(clipView.bounds))));
    [clipView scrollToPoint:origin];
    [scrollView reflectScrolledClipView:clipView];
    [self.reader documentScrollPositionChanged];

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
    if (event.buttonNumber == 2)
        [self beginPanWithEvent:event];
    else
        [super otherMouseDown:event];
}

- (void)otherMouseDragged:(NSEvent*)event {
    if (_isPanning)
        [self continuePanWithEvent:event];
    else
        [super otherMouseDragged:event];
}

- (void)otherMouseUp:(NSEvent*)event {
    if (_isPanning)
        [self endPan];
    else
        [super otherMouseUp:event];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    (void)sender;
    return NSDragOperationCopy;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    return [self.reader openFilesFromPasteboard:sender.draggingPasteboard];
}

@end
