#import <Cocoa/Cocoa.h>

#include "sumatra_pdf_core.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static const CGFloat kPageMargin = 44.0;
static const CGFloat kPageGap = 26.0;
static const CGFloat kMinZoom = 0.10;
static const CGFloat kMaxZoom = 8.00;
static const CGFloat kSelectionOverlayAlpha = 0.20;

typedef NS_ENUM(NSInteger, SPDFFitMode) {
    SPDFFitModeCustom = 0,
    SPDFFitModeActual,
    SPDFFitModeWidth,
    SPDFFitModeHeight,
    SPDFFitModePage
};

typedef NS_ENUM(NSInteger, SPDFViewMode) {
    SPDFViewModeSingle = 0,
    SPDFViewModeContinuous
};

@class SumatraMacDelegate;

@interface SPDFRenderedPage : NSObject
@property(nonatomic) NSInteger pageIndex;
@property(nonatomic) CGFloat pageWidth;
@property(nonatomic) CGFloat pageHeight;
@property(nonatomic, strong) NSImage *image;
@property(nonatomic, copy) NSArray<NSValue *> *highlights;
@property(nonatomic, copy) NSArray<NSValue *> *selectionRects;
@end

@implementation SPDFRenderedPage
@end

@interface SPDFDocumentTab : NSObject
@property(nonatomic, copy) NSString *path;
@property(nonatomic, copy) NSString *title;
@property(nonatomic) NSInteger pageIndex;
@property(nonatomic) CGFloat zoom;
@property(nonatomic) SPDFFitMode fitMode;
@property(nonatomic) SPDFViewMode viewMode;
@property(nonatomic) NSPoint scrollOrigin;
@end

@implementation SPDFDocumentTab

- (instancetype)init
{
    self = [super init];
    if (self) {
        _pageIndex = 0;
        _zoom = 1.0;
        _fitMode = SPDFFitModeWidth;
        _viewMode = SPDFViewModeContinuous;
    }
    return self;
}

@end

@interface SPDFWorkerDocument : NSObject
@property(nonatomic) spdf_document *document;
@property(nonatomic, copy) NSString *path;
@end

@implementation SPDFWorkerDocument

- (void)dealloc
{
    spdf_close(_document);
}

@end

@interface SPDFTabStripView : NSView
@property(nonatomic, weak) SumatraMacDelegate *reader;
@property(nonatomic, copy) NSArray<SPDFDocumentTab *> *tabs;
@property(nonatomic) NSInteger selectedIndex;
@end

@interface SPDFDropView : NSView <NSDraggingDestination>
@property(nonatomic, weak) SumatraMacDelegate *reader;
@end

@interface SPDFScrollView : NSScrollView
@property(nonatomic, weak) SumatraMacDelegate *reader;
@end

@interface SPDFDocumentView : NSView <NSDraggingDestination>
@property(nonatomic, copy) NSArray<SPDFRenderedPage *> *pages;
@property(nonatomic) NSInteger currentPageIndex;
@property(nonatomic) CGFloat zoom;
@property(nonatomic) SPDFViewMode viewMode;
@property(nonatomic, weak) SumatraMacDelegate *reader;
- (NSSize)documentSizeForClipSize:(NSSize)clipSize;
- (NSRect)rectForPageAtIndex:(NSInteger)pageIndex;
- (NSInteger)pageIndexForVisibleRect:(NSRect)visibleRect;
@end

@interface SumatraMacDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSTextFieldDelegate, NSMenuItemValidation>
@property(nonatomic, copy) NSString *initialPath;
- (BOOL)scrollViewShouldTurnWheelIntoPageChange:(NSEvent *)event;
- (void)zoomByFactor:(CGFloat)factor centeredAtWindowPoint:(NSPoint)windowPoint;
- (void)beginLiveZoomByFactor:(CGFloat)factor centeredAtWindowPoint:(NSPoint)windowPoint;
- (void)documentScrollPositionChanged;
- (void)documentViewSelectionChangedOnPage:(NSInteger)pageIndex from:(NSPoint)start to:(NSPoint)end;
- (void)copySelection:(id)sender;
- (void)selectTabAtIndex:(NSInteger)index;
- (void)closeTabAtIndex:(NSInteger)index;
- (void)newTabRequested:(id)sender;
- (void)showFindPalette:(id)sender;
- (BOOL)openFilesFromPasteboard:(NSPasteboard *)pasteboard;
- (void)showContextMenuForDocumentView:(NSView *)view event:(NSEvent *)event;
@end

@implementation SPDFTabStripView

- (BOOL)isFlipped
{
    return YES;
}

- (CGFloat)tabWidth
{
    return 154.0;
}

- (NSRect)searchRect
{
    return NSMakeRect(8, 5, 26, 22);
}

- (NSRect)plusRect
{
    return NSMakeRect(MAX(40, NSWidth(self.bounds) - 34), 5, 26, 22);
}

- (NSRect)rectForTabAtIndex:(NSInteger)index
{
    CGFloat x = 40 + index * ([self tabWidth] + 4);
    CGFloat maxRight = NSMinX([self plusRect]) - 8;
    CGFloat width = MIN([self tabWidth], MAX(86, maxRight - x));
    return NSMakeRect(x, 4, width, 24);
}

- (void)setTabs:(NSArray<SPDFDocumentTab *> *)tabs
{
    _tabs = [tabs copy];
    [self setNeedsDisplay:YES];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex
{
    _selectedIndex = selectedIndex;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    [[NSColor clearColor] setFill];
    NSRectFill(self.bounds);

    NSDictionary *attrs = @{NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
                            NSForegroundColorAttributeName: NSColor.labelColor};
    NSDictionary *dimAttrs = @{NSFontAttributeName: [NSFont systemFontOfSize:12],
                               NSForegroundColorAttributeName: NSColor.secondaryLabelColor};

    NSBezierPath *search = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect([self searchRect], 7, 6)];
    [NSColor.secondaryLabelColor setStroke];
    search.lineWidth = 1.4;
    [search stroke];
    [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMaxX([self searchRect]) - 8, NSMaxY([self searchRect]) - 7)
                              toPoint:NSMakePoint(NSMaxX([self searchRect]) - 4, NSMaxY([self searchRect]) - 3)];

    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; ++i) {
        NSRect tabRect = [self rectForTabAtIndex:i];
        if (NSWidth(tabRect) < 60)
            break;
        BOOL selected = i == self.selectedIndex;
        NSColor *fill = selected ? NSColor.windowBackgroundColor : NSColor.controlBackgroundColor;
        [fill setFill];
        [[NSBezierPath bezierPathWithRoundedRect:tabRect xRadius:6 yRadius:6] fill];

        SPDFDocumentTab *tab = self.tabs[(NSUInteger)i];
        NSString *title = tab.title.length ? tab.title : tab.path.lastPathComponent;
        NSRect titleRect = NSInsetRect(tabRect, 10, 4);
        titleRect.size.width -= 14;
        [title drawWithRect:titleRect options:NSStringDrawingTruncatesLastVisibleLine attributes:selected ? attrs : dimAttrs];

        NSString *close = @"x";
        [close drawAtPoint:NSMakePoint(NSMaxX(tabRect) - 17, NSMinY(tabRect) + 4) withAttributes:dimAttrs];
    }

    NSRect plusRect = [self plusRect];
    [NSColor.controlBackgroundColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:plusRect xRadius:6 yRadius:6] fill];
    NSDictionary *plusAttrs = @{NSFontAttributeName: [NSFont systemFontOfSize:16 weight:NSFontWeightRegular],
                                NSForegroundColorAttributeName: NSColor.labelColor};
    [@"+" drawAtPoint:NSMakePoint(NSMidX(plusRect) - 4, NSMinY(plusRect) + 1) withAttributes:plusAttrs];
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(point, [self searchRect])) {
        [self.reader showFindPalette:self];
        return;
    }
    if (NSPointInRect(point, [self plusRect])) {
        [self.reader newTabRequested:self];
        return;
    }

    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; ++i) {
        NSRect tabRect = [self rectForTabAtIndex:i];
        if (!NSPointInRect(point, tabRect))
            continue;
        NSRect closeRect = NSMakeRect(NSMaxX(tabRect) - 22, NSMinY(tabRect), 22, NSHeight(tabRect));
        if (NSPointInRect(point, closeRect))
            [self.reader closeTabAtIndex:i];
        else
            [self.reader selectTabAtIndex:i];
        return;
    }
}

@end

@implementation SPDFDropView

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
    (void)sender;
    return NSDragOperationCopy;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    return [self.reader openFilesFromPasteboard:sender.draggingPasteboard];
}

@end

@implementation SPDFScrollView {
    CGFloat _wheelAccumulator;
}

- (void)scrollWheel:(NSEvent *)event
{
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    if (self.reader && (flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl))) {
        CGFloat delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY;
        CGFloat factor = pow(1.00135, delta);
        [self.reader beginLiveZoomByFactor:factor centeredAtWindowPoint:event.locationInWindow];
        return;
    }

    if (self.reader && [self.reader scrollViewShouldTurnWheelIntoPageChange:event]) {
        CGFloat delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY;
        _wheelAccumulator += delta;
        CGFloat threshold = event.hasPreciseScrollingDeltas ? 0.75 : 0.50;
        if (fabs(_wheelAccumulator) >= threshold) {
            if (_wheelAccumulator < 0)
                [NSApp sendAction:@selector(nextPage:) to:nil from:self];
            else
                [NSApp sendAction:@selector(previousPage:) to:nil from:self];
            _wheelAccumulator = 0;
        }
        return;
    }

    [super scrollWheel:event];
    if (self.reader)
        [self.reader documentScrollPositionChanged];
}

- (void)magnifyWithEvent:(NSEvent *)event
{
    if (self.reader)
        [self.reader beginLiveZoomByFactor:1.0 + event.magnification * 0.82 centeredAtWindowPoint:event.locationInWindow];
}

@end

@implementation SPDFDocumentView {
    BOOL _isPanning;
    BOOL _isSelecting;
    BOOL _rightMouseMoved;
    NSPoint _panStartInWindow;
    NSPoint _panStartOrigin;
    NSPoint _lastPanPoint;
    NSTimeInterval _lastPanTime;
    NSPoint _panVelocity;
    NSTimer *_inertiaTimer;
    NSInteger _selectionPageIndex;
    NSPoint _selectionStart;
}

- (BOOL)isFlipped
{
    return YES;
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (void)setPages:(NSArray<SPDFRenderedPage *> *)pages
{
    _pages = [pages copy];
    [self setNeedsDisplay:YES];
}

- (CGFloat)widestPage
{
    CGFloat widest = 0;
    for (SPDFRenderedPage *page in self.pages)
        widest = MAX(widest, page.pageWidth * self.zoom);
    return widest;
}

- (NSSize)documentSizeForClipSize:(NSSize)clipSize
{
    CGFloat width = MAX(clipSize.width, [self widestPage] + kPageMargin);
    CGFloat height = kPageMargin;

    if (self.pages.count == 0)
        return NSMakeSize(MAX(clipSize.width, 600), MAX(clipSize.height, 500));

    if (self.viewMode == SPDFViewModeSingle) {
        NSInteger index = MAX(0, MIN(self.currentPageIndex, (NSInteger)self.pages.count - 1));
        SPDFRenderedPage *page = self.pages[(NSUInteger)index];
        CGFloat pageHeight = page.pageHeight * self.zoom;
        height = pageHeight + kPageMargin;
    } else {
        height = kPageMargin / 2.0;
        for (SPDFRenderedPage *page in self.pages) {
            CGFloat pageHeight = page.pageHeight * self.zoom;
            height += pageHeight + kPageGap;
        }
        height += kPageMargin / 2.0;
    }

    return NSMakeSize(width, MAX(height, clipSize.height));
}

- (NSRect)rectForPageAtIndex:(NSInteger)pageIndex
{
    if (pageIndex < 0 || pageIndex >= (NSInteger)self.pages.count)
        return NSZeroRect;

    CGFloat y = kPageMargin / 2.0;
    if (self.viewMode == SPDFViewModeSingle) {
        pageIndex = MAX(0, MIN(self.currentPageIndex, (NSInteger)self.pages.count - 1));
    } else {
        for (NSInteger i = 0; i < pageIndex; ++i) {
            SPDFRenderedPage *prev = self.pages[(NSUInteger)i];
            y += prev.pageHeight * self.zoom + kPageGap;
        }
    }

    SPDFRenderedPage *page = self.pages[(NSUInteger)pageIndex];
    CGFloat width = page.pageWidth * self.zoom;
    CGFloat height = page.pageHeight * self.zoom;
    CGFloat x = floor((NSWidth(self.bounds) - width) / 2.0);
    return NSMakeRect(MAX(kPageMargin / 2.0, x), y, width, height);
}

- (NSInteger)pageIndexForVisibleRect:(NSRect)visibleRect
{
    if (self.pages.count == 0)
        return 0;
    if (self.viewMode == SPDFViewModeSingle)
        return self.currentPageIndex;

    NSInteger bestPage = self.currentPageIndex;
    CGFloat bestOverlap = -1;
    for (SPDFRenderedPage *page in self.pages) {
        NSRect pageRect = [self rectForPageAtIndex:page.pageIndex];
        CGFloat overlap = NSHeight(NSIntersectionRect(visibleRect, pageRect));
        if (overlap > bestOverlap) {
            bestOverlap = overlap;
            bestPage = page.pageIndex;
        }
    }
    return bestPage;
}

- (void)drawPage:(SPDFRenderedPage *)page inRect:(NSRect)pageRect
{
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowBlurRadius = 12.0;
    shadow.shadowOffset = NSMakeSize(0.0, -2.0);
    shadow.shadowColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.28];

    [NSGraphicsContext saveGraphicsState];
    [shadow set];
    [[NSColor whiteColor] setFill];
    NSRectFill(pageRect);
    [NSGraphicsContext restoreGraphicsState];

    if (page.image)
        [page.image drawInRect:pageRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0 respectFlipped:YES hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];

    if (page.highlights.count > 0 && self.zoom > 0) {
        [[NSColor colorWithCalibratedRed:1.0 green:0.84 blue:0.12 alpha:0.38] setFill];
        for (NSValue *value in page.highlights) {
            NSRect r = [value rectValue];
            r.origin.x = pageRect.origin.x + r.origin.x * self.zoom;
            r.origin.y = pageRect.origin.y + r.origin.y * self.zoom;
            r.size.width *= self.zoom;
            r.size.height *= self.zoom;
            [[NSBezierPath bezierPathWithRoundedRect:r xRadius:2.0 yRadius:2.0] fill];
        }
    }

    if (page.selectionRects.count > 0 && self.zoom > 0) {
        [[NSColor colorWithCalibratedRed:0.40 green:0.62 blue:0.86 alpha:kSelectionOverlayAlpha] setFill];
        for (NSValue *value in page.selectionRects) {
            NSRect r = [value rectValue];
            r.origin.x = pageRect.origin.x + r.origin.x * self.zoom;
            r.origin.y = pageRect.origin.y + r.origin.y * self.zoom;
            r.size.width *= self.zoom;
            r.size.height *= self.zoom;
            NSRectFillUsingOperation(r, NSCompositingOperationSourceOver);
        }
    }
}

- (void)drawRect:(NSRect)dirtyRect
{
    [NSColor.windowBackgroundColor setFill];
    NSRectFill(self.bounds);

    if (self.pages.count == 0) {
        NSDictionary *attrs = @{NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
                                NSFontAttributeName: [NSFont systemFontOfSize:16 weight:NSFontWeightMedium]};
        NSString *message = @"Open a document";
        NSSize size = [message sizeWithAttributes:attrs];
        [message drawAtPoint:NSMakePoint((NSWidth(self.bounds) - size.width) / 2.0, 72.0) withAttributes:attrs];
        return;
    }

    if (self.viewMode == SPDFViewModeSingle) {
        NSInteger index = MAX(0, MIN(self.currentPageIndex, (NSInteger)self.pages.count - 1));
        SPDFRenderedPage *page = self.pages[(NSUInteger)index];
        NSRect pageRect = [self rectForPageAtIndex:index];
        if (NSIntersectsRect(dirtyRect, pageRect))
            [self drawPage:page inRect:pageRect];
        return;
    }

    for (SPDFRenderedPage *page in self.pages) {
        NSRect pageRect = [self rectForPageAtIndex:page.pageIndex];
        if (NSIntersectsRect(dirtyRect, pageRect))
            [self drawPage:page inRect:pageRect];
    }
}

- (BOOL)point:(NSPoint)point fallsInPage:(NSInteger *)pageIndex pagePoint:(NSPoint *)pagePoint
{
    if (self.viewMode == SPDFViewModeSingle && self.pages.count > 0) {
        NSInteger index = MAX(0, MIN(self.currentPageIndex, (NSInteger)self.pages.count - 1));
        NSRect pageRect = [self rectForPageAtIndex:index];
        if (NSPointInRect(point, pageRect)) {
            if (pageIndex)
                *pageIndex = index;
            if (pagePoint)
                *pagePoint = NSMakePoint((point.x - pageRect.origin.x) / self.zoom, (point.y - pageRect.origin.y) / self.zoom);
            return YES;
        }
        return NO;
    }

    for (SPDFRenderedPage *page in self.pages) {
        NSRect pageRect = [self rectForPageAtIndex:page.pageIndex];
        if (NSPointInRect(point, pageRect)) {
            if (pageIndex)
                *pageIndex = page.pageIndex;
            if (pagePoint)
                *pagePoint = NSMakePoint((point.x - pageRect.origin.x) / self.zoom, (point.y - pageRect.origin.y) / self.zoom);
            return YES;
        }
    }
    return NO;
}

- (void)mouseDown:(NSEvent *)event
{
    if (!self.reader) {
        [super mouseDown:event];
        return;
    }
    if (event.modifierFlags & NSEventModifierFlagControl) {
        [self.reader showContextMenuForDocumentView:self event:event];
        return;
    }

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSPoint pagePoint = NSZeroPoint;
    NSInteger pageIndex = -1;
    if ([self point:point fallsInPage:&pageIndex pagePoint:&pagePoint]) {
        _isSelecting = YES;
        _selectionPageIndex = pageIndex;
        _selectionStart = pagePoint;
        [self.reader documentViewSelectionChangedOnPage:pageIndex from:pagePoint to:pagePoint];
    } else {
        [super mouseDown:event];
    }
}

- (void)mouseDragged:(NSEvent *)event
{
    if (!_isSelecting) {
        [super mouseDragged:event];
        return;
    }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect pageRect = [self rectForPageAtIndex:_selectionPageIndex];
    if (NSIsEmptyRect(pageRect))
        return;
    NSPoint pagePoint = NSMakePoint((point.x - pageRect.origin.x) / self.zoom, (point.y - pageRect.origin.y) / self.zoom);
    [self.reader documentViewSelectionChangedOnPage:_selectionPageIndex from:_selectionStart to:pagePoint];
}

- (void)mouseUp:(NSEvent *)event
{
    (void)event;
    _isSelecting = NO;
}

- (void)beginPanWithEvent:(NSEvent *)event
{
    NSScrollView *scrollView = self.enclosingScrollView;
    if (!scrollView)
        return;
    [_inertiaTimer invalidate];
    _inertiaTimer = nil;
    _isPanning = YES;
    _panStartInWindow = event.locationInWindow;
    _panStartOrigin = scrollView.contentView.bounds.origin;
    _lastPanPoint = event.locationInWindow;
    _lastPanTime = event.timestamp;
    _panVelocity = NSZeroPoint;
    [[NSCursor closedHandCursor] set];
}

- (void)continuePanWithEvent:(NSEvent *)event
{
    if (!_isPanning)
        return;

    NSScrollView *scrollView = self.enclosingScrollView;
    NSClipView *clipView = scrollView.contentView;
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
}

- (void)stepPanInertia:(NSTimer *)timer
{
    NSScrollView *scrollView = self.enclosingScrollView;
    NSClipView *clipView = scrollView.contentView;
    if (!scrollView || !clipView) {
        [timer invalidate];
        _inertiaTimer = nil;
        return;
    }

    NSPoint origin = clipView.bounds.origin;
    origin.x -= _panVelocity.x / 60.0;
    origin.y += _panVelocity.y / 60.0;
    origin.x = MAX(0, MIN(origin.x, MAX(0, NSWidth(self.bounds) - NSWidth(clipView.bounds))));
    origin.y = MAX(0, MIN(origin.y, MAX(0, NSHeight(self.bounds) - NSHeight(clipView.bounds))));
    [clipView scrollToPoint:origin];
    [scrollView reflectScrolledClipView:clipView];

    _panVelocity.x *= 0.90;
    _panVelocity.y *= 0.90;
    if (hypot(_panVelocity.x, _panVelocity.y) < 12.0) {
        [timer invalidate];
        _inertiaTimer = nil;
    }
}

- (void)endPan
{
    _isPanning = NO;
    [[NSCursor arrowCursor] set];
    if (hypot(_panVelocity.x, _panVelocity.y) > 90.0) {
        [_inertiaTimer invalidate];
        _inertiaTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0 target:self selector:@selector(stepPanInertia:) userInfo:nil repeats:YES];
    }
}

- (void)rightMouseDown:(NSEvent *)event
{
    _rightMouseMoved = NO;
    if (event.modifierFlags & NSEventModifierFlagCommand)
        return;
    [self beginPanWithEvent:event];
}

- (void)rightMouseDragged:(NSEvent *)event
{
    _rightMouseMoved = YES;
    if (_isPanning)
        [self continuePanWithEvent:event];
}

- (void)rightMouseUp:(NSEvent *)event
{
    BOOL forceMenu = (event.modifierFlags & NSEventModifierFlagCommand) != 0;
    if (forceMenu || !_rightMouseMoved)
        [self.reader showContextMenuForDocumentView:self event:event];
    if (_isPanning)
        [self endPan];
}

- (void)otherMouseDown:(NSEvent *)event
{
    if (event.buttonNumber == 2)
        [self beginPanWithEvent:event];
    else
        [super otherMouseDown:event];
}

- (void)otherMouseDragged:(NSEvent *)event
{
    if (_isPanning)
        [self continuePanWithEvent:event];
    else
        [super otherMouseDragged:event];
}

- (void)otherMouseUp:(NSEvent *)event
{
    if (_isPanning)
        [self endPan];
    else
        [super otherMouseUp:event];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
    (void)sender;
    return NSDragOperationCopy;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    return [self.reader openFilesFromPasteboard:sender.draggingPasteboard];
}

@end

@interface SPDFPrintView : NSView
@property(nonatomic, copy) NSArray<SPDFRenderedPage *> *pages;
@end

@implementation SPDFPrintView

- (BOOL)isFlipped
{
    return YES;
}

- (BOOL)knowsPageRange:(NSRangePointer)range
{
    range->location = 1;
    range->length = self.pages.count;
    return YES;
}

- (NSRect)rectForPage:(NSInteger)page
{
    NSPrintInfo *info = NSPrintOperation.currentOperation.printInfo;
    NSSize paper = info.paperSize;
    return NSMakeRect(0, (page - 1) * paper.height, paper.width, paper.height);
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSPrintInfo *info = NSPrintOperation.currentOperation.printInfo;
    NSSize paper = info.paperSize;
    NSInteger pageNumber = MAX(1, (NSInteger)floor(dirtyRect.origin.y / paper.height) + 1);
    NSInteger pageIndex = pageNumber - 1;
    if (pageIndex < 0 || pageIndex >= (NSInteger)self.pages.count)
        return;

    NSRect pageRect = [self rectForPage:pageNumber];
    [[NSColor whiteColor] setFill];
    NSRectFill(pageRect);

    SPDFRenderedPage *page = self.pages[(NSUInteger)pageIndex];
    if (!page.image)
        return;

    NSRect imageable = info.imageablePageBounds;
    imageable.origin.x += pageRect.origin.x;
    imageable.origin.y += pageRect.origin.y;
    CGFloat scale = MIN(NSWidth(imageable) / page.image.size.width, NSHeight(imageable) / page.image.size.height);
    NSSize drawSize = NSMakeSize(page.image.size.width * scale, page.image.size.height * scale);
    NSRect drawRect = NSMakeRect(imageable.origin.x + (NSWidth(imageable) - drawSize.width) / 2.0,
                                 imageable.origin.y + (NSHeight(imageable) - drawSize.height) / 2.0,
                                 drawSize.width,
                                 drawSize.height);
    [page.image drawInRect:drawRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0 respectFlipped:YES hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
}

@end

@implementation SumatraMacDelegate {
    NSWindow *_window;
    NSTitlebarAccessoryViewController *_tabAccessory;
    SPDFTabStripView *_tabStrip;
    NSSplitView *_splitView;
    NSTableView *_sidebarTable;
    NSView *_sidebarContainer;
    SPDFScrollView *_pageScrollView;
    SPDFDocumentView *_pageView;
    NSButton *_openButton;
    NSButton *_prevButton;
    NSButton *_nextButton;
    NSTextField *_pageField;
    NSTextField *_pageCountLabel;
    NSButton *_zoomOutButton;
    NSButton *_zoomInButton;
    NSPopUpButton *_fitModePopup;
    NSButton *_continuousButton;
    NSSearchField *_searchField;
    NSTextField *_statusLabel;
    NSSegmentedControl *_sidebarModeControl;
    NSPanel *_palettePanel;
    NSSearchField *_paletteSearchField;
    NSButton *_paletteAllDocsCheckbox;
    NSTableView *_paletteTable;
    NSMutableArray<NSDictionary *> *_paletteResults;
    NSInteger _paletteMode;
    NSUInteger _paletteSearchGeneration;
    NSOperationQueue *_renderQueue;
    NSOperationQueue *_preloadQueue;

    spdf_document *_doc;
    spdf_outline _outline;
    NSMutableArray<NSDictionary *> *_sidebarItems;
    NSMutableArray<SPDFRenderedPage *> *_renderedPages;
    NSMutableArray<SPDFDocumentTab *> *_tabs;
    NSMutableArray<NSDictionary *> *_favorites;
    NSString *_path;
    NSString *_pendingOpenPath;
    NSMutableArray<NSString *> *_pendingOpenPaths;
    NSInteger _pageIndex;
    NSInteger _highlightPageIndex;
    NSInteger _selectionPageIndex;
    NSString *_selectedText;
    CGFloat _zoom;
    SPDFFitMode _fitMode;
    SPDFViewMode _viewMode;
    NSInteger _selectedTabIndex;
    NSUInteger _renderGeneration;
    NSTimer *_zoomFinishTimer;
    BOOL _uiReady;
    BOOL _updatingSelection;
    BOOL _updatingFromScroll;
    BOOL _sidebarVisible;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    (void)notification;
    _zoom = 1.0;
    _fitMode = SPDFFitModeWidth;
    _viewMode = SPDFViewModeContinuous;
    _highlightPageIndex = -1;
    _selectionPageIndex = -1;
    _sidebarVisible = YES;
    _sidebarItems = [NSMutableArray array];
    _renderedPages = [NSMutableArray array];
    _tabs = [NSMutableArray array];
    _favorites = [NSMutableArray array];
    _paletteResults = [NSMutableArray array];
    _pendingOpenPaths = [NSMutableArray array];
    _selectedTabIndex = -1;

    NSInteger cpuCount = MAX(2, NSProcessInfo.processInfo.activeProcessorCount);
    _renderQueue = [[NSOperationQueue alloc] init];
    _renderQueue.name = @"SumatraPDF page renderer";
    _renderQueue.maxConcurrentOperationCount = cpuCount;
    _renderQueue.qualityOfService = NSQualityOfServiceUserInitiated;
    _preloadQueue = [[NSOperationQueue alloc] init];
    _preloadQueue.name = @"SumatraPDF tab preloader";
    _preloadQueue.maxConcurrentOperationCount = MAX(2, cpuCount / 2);
    _preloadQueue.qualityOfService = NSQualityOfServiceUtility;

    [self loadPersistentState];

    [self buildMenu];
    [self buildWindow];
    _uiReady = YES;
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    NSMutableArray<NSString *> *startupPaths = [NSMutableArray array];
    if (_pendingOpenPath.length > 0)
        [startupPaths addObject:_pendingOpenPath];
    for (NSString *path in _pendingOpenPaths) {
        if (path.length > 0 && ![startupPaths containsObject:path])
            [startupPaths addObject:path];
    }
    if (self.initialPath.length > 0)
        [startupPaths addObject:self.initialPath];
    if (startupPaths.count > 0) {
        for (NSString *path in startupPaths)
            [self openPath:path];
    } else if (_tabs.count > 0) {
        [self selectTabAtIndex:MAX(0, _selectedTabIndex)];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    (void)sender;
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    (void)notification;
    [_renderQueue cancelAllOperations];
    [_preloadQueue cancelAllOperations];
    [self rememberActiveTabState];
    [self savePersistentState];
    spdf_free_outline(&_outline);
    spdf_close(_doc);
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename
{
    (void)sender;
    if (!_uiReady) {
        if (!_pendingOpenPath.length)
            _pendingOpenPath = [filename copy];
        if (filename.length && ![_pendingOpenPaths containsObject:filename])
            [_pendingOpenPaths addObject:filename];
        return YES;
    }
    [self openPath:filename];
    return YES;
}

- (void)application:(NSApplication *)application openFiles:(NSArray<NSString *> *)filenames
{
    (void)application;
    if (filenames.count > 0) {
        if (!_uiReady) {
            _pendingOpenPath = [filenames.firstObject copy];
            [_pendingOpenPaths addObjectsFromArray:filenames];
        } else {
            for (NSString *filename in filenames)
                [self openPath:filename];
        }
    }
    [NSApp replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

- (void)windowDidResize:(NSNotification *)notification
{
    (void)notification;
    if (_doc && (_fitMode == SPDFFitModeWidth || _fitMode == SPDFFitModeHeight || _fitMode == SPDFFitModePage))
        [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO];
    else
        [self resizeDocumentView];
}

- (NSString *)supportDirectory
{
    NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSString *dir = [base.path stringByAppendingPathComponent:@"SumatraPDF"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (NSString *)pathForStateFile:(NSString *)name
{
    return [[self supportDirectory] stringByAppendingPathComponent:name];
}

- (id)jsonObjectFromFile:(NSString *)name
{
    NSData *data = [NSData dataWithContentsOfFile:[self pathForStateFile:name]];
    if (!data)
        return nil;
    return [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
}

- (void)writeJSONObject:(id)object toFile:(NSString *)name
{
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    if (data)
        [data writeToFile:[self pathForStateFile:name] atomically:YES];
}

- (void)loadPersistentState
{
    NSDictionary *settings = [self jsonObjectFromFile:@"settings.json"];
    if ([settings isKindOfClass:NSDictionary.class]) {
        NSNumber *fit = settings[@"fitMode"];
        NSNumber *view = settings[@"viewMode"];
        NSNumber *sidebar = settings[@"showSidebar"];
        if (fit)
            _fitMode = (SPDFFitMode)MAX(0, MIN(4, fit.integerValue));
        if (view)
            _viewMode = (SPDFViewMode)MAX(0, MIN(1, view.integerValue));
        if (sidebar)
            _sidebarVisible = sidebar.boolValue;
    }

    NSArray *favorites = [self jsonObjectFromFile:@"favorites.json"];
    if ([favorites isKindOfClass:NSArray.class])
        [_favorites addObjectsFromArray:favorites];

    NSDictionary *session = [self jsonObjectFromFile:@"session.json"];
    NSArray *tabs = [session isKindOfClass:NSDictionary.class] ? session[@"tabs"] : nil;
    if ([tabs isKindOfClass:NSArray.class]) {
        for (NSDictionary *item in tabs) {
            if (![item isKindOfClass:NSDictionary.class])
                continue;
            NSString *path = item[@"path"];
            if (![path isKindOfClass:NSString.class] || path.length == 0)
                continue;
            SPDFDocumentTab *tab = [[SPDFDocumentTab alloc] init];
            tab.path = path;
            tab.title = [item[@"title"] isKindOfClass:NSString.class] ? item[@"title"] : path.lastPathComponent;
            tab.pageIndex = [item[@"page"] integerValue];
            tab.zoom = [item[@"zoom"] doubleValue] > 0 ? [item[@"zoom"] doubleValue] : 1.0;
            tab.fitMode = (SPDFFitMode)MAX(0, MIN(4, [item[@"fitMode"] integerValue]));
            tab.viewMode = (SPDFViewMode)MAX(0, MIN(1, [item[@"viewMode"] integerValue]));
            tab.scrollOrigin = NSMakePoint([item[@"scrollX"] doubleValue], [item[@"scrollY"] doubleValue]);
            [_tabs addObject:tab];
        }
        _selectedTabIndex = MIN(MAX(0, [session[@"selectedTab"] integerValue]), MAX(0, (NSInteger)_tabs.count - 1));
    }
}

- (void)savePersistentState
{
    NSMutableArray *tabs = [NSMutableArray array];
    for (SPDFDocumentTab *tab in _tabs) {
        if (!tab.path.length)
            continue;
        [tabs addObject:@{@"path": tab.path,
                          @"title": tab.title ?: tab.path.lastPathComponent,
                          @"page": @(tab.pageIndex),
                          @"zoom": @(tab.zoom),
                          @"fitMode": @(tab.fitMode),
                          @"viewMode": @(tab.viewMode),
                          @"scrollX": @(tab.scrollOrigin.x),
                          @"scrollY": @(tab.scrollOrigin.y)}];
    }
    [self writeJSONObject:@{@"version": @1,
                            @"selectedTab": @(MAX(0, _selectedTabIndex)),
                            @"tabs": tabs} toFile:@"session.json"];
    [self writeJSONObject:@{@"version": @1,
                            @"fitMode": @(_fitMode),
                            @"viewMode": @(_viewMode),
                            @"showSidebar": @(_sidebarVisible)} toFile:@"settings.json"];
    [self writeJSONObject:_favorites toFile:@"favorites.json"];
}

- (void)buildMenu
{
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];

    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    [mainMenu addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"SumatraPDF"];
    [appMenu addItemWithTitle:@"About SumatraPDF" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit SumatraPDF" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;

    NSMenuItem *fileItem = [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
    [mainMenu addItem:fileItem];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"Open..." action:@selector(openDocument:) keyEquivalent:@"o"];
    [fileMenu addItemWithTitle:@"Open in Adobe Acrobat Reader" action:@selector(openInExternalReader:) keyEquivalent:@""];
    [fileMenu addItemWithTitle:@"Close" action:@selector(closeDocument:) keyEquivalent:@"w"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Print..." action:@selector(printDocument:) keyEquivalent:@"p"];
    [fileMenu addItemWithTitle:@"Properties..." action:@selector(showProperties:) keyEquivalent:@""];
    fileItem.submenu = fileMenu;

    NSMenuItem *goItem = [[NSMenuItem alloc] initWithTitle:@"Go To" action:nil keyEquivalent:@""];
    [mainMenu addItem:goItem];
    NSMenu *goMenu = [[NSMenu alloc] initWithTitle:@"Go To"];
    [goMenu addItemWithTitle:@"First Page" action:@selector(firstPage:) keyEquivalent:[NSString stringWithFormat:@"%C", static_cast<unichar>(NSHomeFunctionKey)]];
    [goMenu addItemWithTitle:@"Previous Page" action:@selector(previousPage:) keyEquivalent:@"["];
    [goMenu addItemWithTitle:@"Next Page" action:@selector(nextPage:) keyEquivalent:@"]"];
    [goMenu addItemWithTitle:@"Last Page" action:@selector(lastPage:) keyEquivalent:[NSString stringWithFormat:@"%C", static_cast<unichar>(NSEndFunctionKey)]];
    [goMenu addItem:[NSMenuItem separatorItem]];
    [goMenu addItemWithTitle:@"Go To Page..." action:@selector(focusPageField:) keyEquivalent:@"l"];
    goItem.submenu = goMenu;

    NSMenuItem *zoomItem = [[NSMenuItem alloc] initWithTitle:@"Zoom" action:nil keyEquivalent:@""];
    [mainMenu addItem:zoomItem];
    NSMenu *zoomMenu = [[NSMenu alloc] initWithTitle:@"Zoom"];
    [zoomMenu addItemWithTitle:@"Zoom In" action:@selector(zoomIn:) keyEquivalent:@"+"];
    [zoomMenu addItemWithTitle:@"Zoom Out" action:@selector(zoomOut:) keyEquivalent:@"-"];
    [zoomMenu addItemWithTitle:@"Actual Size" action:@selector(actualSize:) keyEquivalent:@"0"];
    [zoomMenu addItem:[NSMenuItem separatorItem]];
    [zoomMenu addItemWithTitle:@"Fit Page" action:@selector(fitPage:) keyEquivalent:@"9"];
    [zoomMenu addItemWithTitle:@"Fit Width" action:@selector(fitWidth:) keyEquivalent:@"1"];
    [zoomMenu addItemWithTitle:@"Fit Height" action:@selector(fitHeight:) keyEquivalent:@"2"];
    zoomItem.submenu = zoomMenu;

    NSMenuItem *viewItem = [[NSMenuItem alloc] initWithTitle:@"View" action:nil keyEquivalent:@""];
    [mainMenu addItem:viewItem];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    [viewMenu addItemWithTitle:@"Single Page" action:@selector(setSinglePageMode:) keyEquivalent:@"4"];
    [viewMenu addItemWithTitle:@"Continuous" action:@selector(setContinuousMode:) keyEquivalent:@"5"];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"Show Sidebar" action:@selector(toggleSidebar:) keyEquivalent:@""];
    NSMenuItem *fullScreen = [viewMenu addItemWithTitle:@"Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"f"];
    fullScreen.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"Rotate Left" action:@selector(unimplementedMenuItem:) keyEquivalent:@""];
    [viewMenu addItemWithTitle:@"Rotate Right" action:@selector(unimplementedMenuItem:) keyEquivalent:@""];
    viewItem.submenu = viewMenu;

    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
    [mainMenu addItem:editItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copySelection:) keyEquivalent:@"c"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Find" action:@selector(focusFind:) keyEquivalent:@"f"];
    [editMenu addItemWithTitle:@"Find Next" action:@selector(findNext:) keyEquivalent:@"g"];
    NSMenuItem *prevFind = [editMenu addItemWithTitle:@"Find Previous" action:@selector(findPrevious:) keyEquivalent:@"G"];
    prevFind.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    editItem.submenu = editMenu;

    NSMenuItem *favoritesItem = [[NSMenuItem alloc] initWithTitle:@"Favorites" action:nil keyEquivalent:@""];
    [mainMenu addItem:favoritesItem];
    NSMenu *favoritesMenu = [[NSMenu alloc] initWithTitle:@"Favorites"];
    [favoritesMenu addItemWithTitle:@"Search Favorites..." action:@selector(showFavoritesPalette:) keyEquivalent:@"k"];
    [favoritesMenu addItem:[NSMenuItem separatorItem]];
    [favoritesMenu addItemWithTitle:@"Favorite Current Page" action:@selector(favoriteCurrentPage:) keyEquivalent:@"b"];
    NSMenuItem *docFav = [favoritesMenu addItemWithTitle:@"Favorite Current Document" action:@selector(favoriteCurrentDocument:) keyEquivalent:@"B"];
    docFav.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [favoritesMenu addItemWithTitle:@"Manage Favorites..." action:@selector(showFavoritesPalette:) keyEquivalent:@""];
    favoritesItem.submenu = favoritesMenu;

    NSMenuItem *settingsItem = [[NSMenuItem alloc] initWithTitle:@"Settings" action:nil keyEquivalent:@""];
    [mainMenu addItem:settingsItem];
    NSMenu *settingsMenu = [[NSMenu alloc] initWithTitle:@"Settings"];
    [settingsMenu addItemWithTitle:@"Options..." action:@selector(unimplementedMenuItem:) keyEquivalent:@","];
    [settingsMenu addItemWithTitle:@"Advanced Options..." action:@selector(unimplementedMenuItem:) keyEquivalent:@""];
    settingsItem.submenu = settingsMenu;

    NSApp.mainMenu = mainMenu;
}

- (NSButton *)buttonWithTitle:(NSString *)title action:(SEL)action
{
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

- (void)buildWindow
{
    NSRect frame = NSMakeRect(120, 80, 1120, 800);
    _window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.delegate = self;
    _window.title = @"SumatraPDF";
    _window.minSize = NSMakeSize(790, 540);
    _window.titleVisibility = NSWindowTitleHidden;
    _window.titlebarAppearsTransparent = YES;
    _window.styleMask |= NSWindowStyleMaskFullSizeContentView;

    _tabStrip = [[SPDFTabStripView alloc] initWithFrame:NSMakeRect(0, 0, 680, 32)];
    _tabStrip.reader = self;
    _tabStrip.tabs = _tabs;
    _tabStrip.selectedIndex = _selectedTabIndex;
    _tabAccessory = [[NSTitlebarAccessoryViewController alloc] init];
    _tabAccessory.view = _tabStrip;
    _tabAccessory.layoutAttribute = NSLayoutAttributeTop;
    [_window addTitlebarAccessoryViewController:_tabAccessory];

    SPDFDropView *content = [[SPDFDropView alloc] initWithFrame:frame];
    content.reader = self;
    [content registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    _window.contentView = content;

    NSStackView *toolbar = [[NSStackView alloc] init];
    toolbar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    toolbar.alignment = NSLayoutAttributeCenterY;
    toolbar.spacing = 6.0;
    toolbar.edgeInsets = NSEdgeInsetsMake(7, 8, 7, 8);
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:toolbar];

    _openButton = [self buttonWithTitle:@"Open" action:@selector(openDocument:)];
    _prevButton = [self buttonWithTitle:@"<" action:@selector(previousPage:)];
    _nextButton = [self buttonWithTitle:@">" action:@selector(nextPage:)];
    _pageField = [[NSTextField alloc] init];
    _pageField.translatesAutoresizingMaskIntoConstraints = NO;
    _pageField.alignment = NSTextAlignmentRight;
    _pageField.delegate = self;
    _pageField.target = self;
    _pageField.action = @selector(pageFieldChanged:);
    [_pageField.widthAnchor constraintEqualToConstant:58].active = YES;
    _pageCountLabel = [NSTextField labelWithString:@"/ 0"];
    _pageCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _zoomOutButton = [self buttonWithTitle:@"-" action:@selector(zoomOut:)];
    _zoomInButton = [self buttonWithTitle:@"+" action:@selector(zoomIn:)];

    _fitModePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_fitModePopup addItemsWithTitles:@[@"Custom", @"Actual", @"Fit Width", @"Fit Height", @"Fit Page"]];
    _fitModePopup.target = self;
    _fitModePopup.action = @selector(fitModePopupChanged:);
    _fitModePopup.translatesAutoresizingMaskIntoConstraints = NO;
    [_fitModePopup.widthAnchor constraintEqualToConstant:112].active = YES;

    _continuousButton = [NSButton checkboxWithTitle:@"Continuous" target:self action:@selector(toggleContinuous:)];
    _continuousButton.translatesAutoresizingMaskIntoConstraints = NO;
    _continuousButton.state = NSControlStateValueOn;

    _searchField = [[NSSearchField alloc] init];
    _searchField.placeholderString = @"Find";
    _searchField.translatesAutoresizingMaskIntoConstraints = NO;
    _searchField.delegate = self;
    _searchField.target = self;
    _searchField.action = @selector(findNext:);
    [_searchField.widthAnchor constraintEqualToConstant:190].active = YES;

    [toolbar addArrangedSubview:_openButton];
    [toolbar addArrangedSubview:_prevButton];
    [toolbar addArrangedSubview:_nextButton];
    [toolbar addArrangedSubview:_pageField];
    [toolbar addArrangedSubview:_pageCountLabel];
    [toolbar addArrangedSubview:_zoomOutButton];
    [toolbar addArrangedSubview:_zoomInButton];
    [toolbar addArrangedSubview:_fitModePopup];
    [toolbar addArrangedSubview:_continuousButton];
    [toolbar addArrangedSubview:_searchField];

    _splitView = [[NSSplitView alloc] init];
    _splitView.vertical = YES;
    _splitView.dividerStyle = NSSplitViewDividerStyleThin;
    _splitView.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_splitView];

    _sidebarContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 600)];
    _sidebarContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _sidebarModeControl = [[NSSegmentedControl alloc] init];
    _sidebarModeControl.segmentCount = 2;
    [_sidebarModeControl setLabel:@"Pages" forSegment:0];
    [_sidebarModeControl setLabel:@"Contents" forSegment:1];
    _sidebarModeControl.selectedSegment = 0;
    _sidebarModeControl.target = self;
    _sidebarModeControl.action = @selector(sidebarModeChanged:);
    _sidebarModeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [_sidebarContainer addSubview:_sidebarModeControl];

    NSScrollView *sidebarScroll = [[NSScrollView alloc] init];
    sidebarScroll.hasVerticalScroller = YES;
    sidebarScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [_sidebarContainer addSubview:sidebarScroll];

    _sidebarTable = [[NSTableView alloc] init];
    _sidebarTable.headerView = nil;
    _sidebarTable.rowHeight = 25.0;
    _sidebarTable.dataSource = self;
    _sidebarTable.delegate = self;
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"title"];
    column.title = @"Title";
    column.width = 230.0;
    [_sidebarTable addTableColumn:column];
    sidebarScroll.documentView = _sidebarTable;

    [NSLayoutConstraint activateConstraints:@[
        [_sidebarModeControl.topAnchor constraintEqualToAnchor:_sidebarContainer.topAnchor constant:8],
        [_sidebarModeControl.leadingAnchor constraintEqualToAnchor:_sidebarContainer.leadingAnchor constant:8],
        [_sidebarModeControl.trailingAnchor constraintEqualToAnchor:_sidebarContainer.trailingAnchor constant:-8],
        [sidebarScroll.topAnchor constraintEqualToAnchor:_sidebarModeControl.bottomAnchor constant:8],
        [sidebarScroll.leadingAnchor constraintEqualToAnchor:_sidebarContainer.leadingAnchor],
        [sidebarScroll.trailingAnchor constraintEqualToAnchor:_sidebarContainer.trailingAnchor],
        [sidebarScroll.bottomAnchor constraintEqualToAnchor:_sidebarContainer.bottomAnchor],
        [_sidebarContainer.widthAnchor constraintEqualToConstant:240]
    ]];

    _pageScrollView = [[SPDFScrollView alloc] init];
    _pageScrollView.reader = self;
    _pageScrollView.hasVerticalScroller = YES;
    _pageScrollView.hasHorizontalScroller = YES;
    _pageScrollView.autohidesScrollers = NO;
    _pageScrollView.borderType = NSNoBorder;
    _pageScrollView.drawsBackground = YES;
    _pageScrollView.backgroundColor = NSColor.windowBackgroundColor;
    _pageScrollView.contentView.drawsBackground = YES;
    _pageScrollView.contentView.backgroundColor = NSColor.windowBackgroundColor;
    _pageScrollView.contentView.postsBoundsChangedNotifications = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clipViewBoundsChanged:) name:NSViewBoundsDidChangeNotification object:_pageScrollView.contentView];

    _pageView = [[SPDFDocumentView alloc] initWithFrame:NSMakeRect(0, 0, 800, 1000)];
    _pageView.reader = self;
    [_pageView registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    _pageView.viewMode = _viewMode;
    _pageView.zoom = _zoom;
    _pageScrollView.documentView = _pageView;

    [_splitView addSubview:_sidebarContainer];
    [_splitView addSubview:_pageScrollView];

    _statusLabel = [NSTextField labelWithString:@"Ready"];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [content addSubview:_statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [toolbar.topAnchor constraintEqualToAnchor:content.topAnchor],
        [toolbar.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [toolbar.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [toolbar.heightAnchor constraintEqualToConstant:42],
        [_splitView.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor],
        [_splitView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [_splitView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [_splitView.bottomAnchor constraintEqualToAnchor:_statusLabel.topAnchor],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:8],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8],
        [_statusLabel.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-3],
        [_statusLabel.heightAnchor constraintEqualToConstant:22]
    ]];

    [_splitView setPosition:240 ofDividerAtIndex:0];
    if (!_sidebarVisible) {
        _sidebarVisible = YES;
        [self toggleSidebar:nil];
    }
    [self syncToolbarState];
    [self updateControls];
}

- (CGFloat)backingScale
{
    CGFloat scale = _window.backingScaleFactor;
    if (scale <= 0)
        scale = NSScreen.mainScreen.backingScaleFactor;
    return scale > 0 ? scale : 1.0;
}

- (CGFloat)zoomForFitMode:(SPDFFitMode)fitMode pageIndex:(NSInteger)pageIndex
{
    if (!_doc)
        return _zoom;
    if (fitMode == SPDFFitModeCustom)
        return _zoom;
    if (fitMode == SPDFFitModeActual)
        return 1.0;

    char err[1024];
    float pageWidth = 0;
    float pageHeight = 0;
    if (!spdf_page_size(_doc, (int)pageIndex, &pageWidth, &pageHeight, err, sizeof(err)) || pageWidth <= 0 || pageHeight <= 0)
        return _zoom;

    NSSize clipSize = _pageScrollView.contentView.bounds.size;
    CGFloat widthZoom = (clipSize.width - kPageMargin * 1.7) / pageWidth;
    CGFloat heightZoom = (clipSize.height - kPageMargin) / pageHeight;
    if (fitMode == SPDFFitModeWidth)
        return MAX(kMinZoom, MIN(kMaxZoom, widthZoom));
    if (fitMode == SPDFFitModeHeight)
        return MAX(kMinZoom, MIN(kMaxZoom, heightZoom));
    return MAX(kMinZoom, MIN(kMaxZoom, MIN(widthZoom, heightZoom)));
}

- (SPDFRenderedPage *)renderedPageAtIndex:(NSInteger)pageIndex document:(spdf_document *)doc zoom:(CGFloat)zoom displayScale:(CGFloat)displayScale error:(char *)err errorLength:(size_t)errLen
{
    float pageWidth = 0;
    float pageHeight = 0;
    if (!spdf_page_size(doc, (int)pageIndex, &pageWidth, &pageHeight, err, errLen))
        return nil;

    spdf_bitmap bitmap;
    if (!spdf_render_page_rgba(doc, (int)pageIndex, (float)(zoom * displayScale), &bitmap, err, errLen))
        return nil;

    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:bitmap.width
                                                                    pixelsHigh:bitmap.height
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:bitmap.stride
                                                                  bitsPerPixel:32];
    memcpy(rep.bitmapData, bitmap.rgba, (size_t)bitmap.stride * (size_t)bitmap.height);
    spdf_free_bitmap(&bitmap);

    NSSize pointSize = NSMakeSize(pageWidth * zoom, pageHeight * zoom);
    rep.size = pointSize;
    NSImage *image = [[NSImage alloc] initWithSize:pointSize];
    [image addRepresentation:rep];

    SPDFRenderedPage *page = [[SPDFRenderedPage alloc] init];
    page.pageIndex = pageIndex;
    page.pageWidth = pageWidth;
    page.pageHeight = pageHeight;
    page.image = image;
    page.highlights = @[];
    page.selectionRects = @[];
    return page;
}

- (SPDFRenderedPage *)renderedPageAtIndex:(NSInteger)pageIndex error:(char *)err errorLength:(size_t)errLen
{
    return [self renderedPageAtIndex:pageIndex document:_doc zoom:_zoom displayScale:[self backingScale] error:err errorLength:errLen];
}

- (SPDFRenderedPage *)placeholderPageAtIndex:(NSInteger)pageIndex pageWidth:(CGFloat)pageWidth pageHeight:(CGFloat)pageHeight
{
    SPDFRenderedPage *page = [[SPDFRenderedPage alloc] init];
    page.pageIndex = pageIndex;
    page.pageWidth = pageWidth;
    page.pageHeight = pageHeight;
    page.highlights = @[];
    page.selectionRects = @[];
    return page;
}

- (spdf_document *)workerDocumentForPath:(NSString *)path error:(char *)err errorLength:(size_t)errLen
{
    if (!path.length)
        return NULL;

    NSMutableDictionary *threadDictionary = NSThread.currentThread.threadDictionary;
    SPDFWorkerDocument *holder = threadDictionary[@"SumatraPDFWorkerDocument"];
    if (holder && [holder.path isEqualToString:path] && holder.document)
        return holder.document;

    holder = [[SPDFWorkerDocument alloc] init];
    holder.path = path;
    holder.document = spdf_open(path.fileSystemRepresentation, err, errLen);
    if (!holder.document)
        return NULL;
    threadDictionary[@"SumatraPDFWorkerDocument"] = holder;
    return holder.document;
}

- (NSArray<NSNumber *> *)pageRenderOrderForCount:(NSInteger)pageCount preferredPage:(NSInteger)preferredPage
{
    NSMutableArray<NSNumber *> *order = [NSMutableArray arrayWithCapacity:(NSUInteger)MAX(0, pageCount - 1)];
    for (NSInteger distance = 1; distance < pageCount; ++distance) {
        NSInteger after = preferredPage + distance;
        NSInteger before = preferredPage - distance;
        if (after < pageCount)
            [order addObject:@(after)];
        if (before >= 0)
            [order addObject:@(before)];
    }
    return order;
}

- (void)enqueueRemainingPageRendersForGeneration:(NSUInteger)generation preferredPage:(NSInteger)preferredPage
{
    if (!_doc || !_path.length)
        return;

    NSString *path = [_path copy];
    CGFloat zoom = _zoom;
    CGFloat displayScale = [self backingScale];
    NSArray<NSNumber *> *order = [self pageRenderOrderForCount:(NSInteger)_renderedPages.count preferredPage:preferredPage];
    for (NSNumber *number in order) {
        NSInteger index = number.integerValue;
        [_renderQueue addOperationWithBlock:^{
            @autoreleasepool {
                if (generation != self->_renderGeneration)
                    return;
                char err[1024];
                spdf_document *workerDoc = [self workerDocumentForPath:path error:err errorLength:sizeof(err)];
                if (!workerDoc)
                    return;
                SPDFRenderedPage *page = [self renderedPageAtIndex:index document:workerDoc zoom:zoom displayScale:displayScale error:err errorLength:sizeof(err)];
                if (!page)
                    return;

                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    if (generation != self->_renderGeneration || !self->_doc || index >= (NSInteger)self->_renderedPages.count)
                        return;
                    SPDFRenderedPage *old = self->_renderedPages[(NSUInteger)index];
                    page.highlights = old.highlights ?: @[];
                    page.selectionRects = old.selectionRects ?: @[];
                    [self->_renderedPages replaceObjectAtIndex:(NSUInteger)index withObject:page];
                    [self applySearchHighlightsToCurrentPage];
                    [self resizeDocumentView];
                }];
            }
        }];
    }
}

- (void)renderPageIfNeededAtIndex:(NSInteger)pageIndex
{
    if (!_doc || pageIndex < 0 || pageIndex >= (NSInteger)_renderedPages.count)
        return;
    SPDFRenderedPage *existing = _renderedPages[(NSUInteger)pageIndex];
    if (existing.image)
        return;

    char err[1024];
    SPDFRenderedPage *page = [self renderedPageAtIndex:pageIndex error:err errorLength:sizeof(err)];
    if (!page) {
        _statusLabel.stringValue = [NSString stringWithFormat:@"Could not render page %ld", (long)pageIndex + 1];
        return;
    }
    page.highlights = existing.highlights ?: @[];
    page.selectionRects = existing.selectionRects ?: @[];
    [_renderedPages replaceObjectAtIndex:(NSUInteger)pageIndex withObject:page];
    _pageView.pages = _renderedPages;
}

- (void)renderDocumentAndScrollToPage:(NSInteger)pageIndex alignTop:(BOOL)alignTop
{
    if (!_doc || !_uiReady)
        return;

    [_window.contentView layoutSubtreeIfNeeded];
    [_renderQueue cancelAllOperations];
    _renderGeneration++;
    NSUInteger generation = _renderGeneration;
    _zoom = [self zoomForFitMode:_fitMode pageIndex:MAX(0, pageIndex)];
    NSMutableArray<SPDFRenderedPage *> *pages = [NSMutableArray arrayWithCapacity:(NSUInteger)spdf_page_count(_doc)];
    char err[1024];
    NSInteger pageCount = spdf_page_count(_doc);
    pageIndex = MAX(0, MIN(pageIndex, pageCount - 1));
    SPDFRenderedPage *preferredPage = [self renderedPageAtIndex:pageIndex error:err errorLength:sizeof(err)];
    if (!preferredPage) {
        [self showError:@"Could not render page" detail:[NSString stringWithUTF8String:err[0] ? err : "Unknown error"]];
        return;
    }
    for (NSInteger i = 0; i < pageCount; ++i) {
        SPDFRenderedPage *page = nil;
        if (i == pageIndex)
            page = preferredPage;
        else
            page = [self placeholderPageAtIndex:i pageWidth:preferredPage.pageWidth pageHeight:preferredPage.pageHeight];
        if (!page) {
            [self showError:@"Could not render page" detail:[NSString stringWithUTF8String:err[0] ? err : "Unknown error"]];
            return;
        }
        [pages addObject:page];
    }

    _renderedPages = pages;
    _pageView.pages = _renderedPages;
    _pageView.currentPageIndex = _pageIndex;
    _pageView.zoom = _zoom;
    _pageView.viewMode = _viewMode;
    [self applySearchHighlightsToCurrentPage];
    [self resizeDocumentView];
    [self scrollToPage:pageIndex alignTop:alignTop];
    [self syncToolbarState];
    [self updateControls];
    [self selectCurrentSidebarRow];

    [self enqueueRemainingPageRendersForGeneration:generation preferredPage:pageIndex];
}

- (void)resizeDocumentView
{
    NSSize size = [_pageView documentSizeForClipSize:_pageScrollView.contentView.bounds.size];
    [_pageView setFrameSize:size];
    [_pageView setNeedsDisplay:YES];
}

- (void)scrollToPage:(NSInteger)pageIndex alignTop:(BOOL)alignTop
{
    if (_renderedPages.count == 0)
        return;
    pageIndex = MAX(0, MIN(pageIndex, (NSInteger)_renderedPages.count - 1));
    NSRect pageRect = [_pageView rectForPageAtIndex:pageIndex];
    _updatingFromScroll = YES;
    if (alignTop) {
        NSPoint point = NSMakePoint(MAX(0, pageRect.origin.x - 12), MAX(0, pageRect.origin.y - 12));
        [_pageView scrollPoint:point];
    } else {
        [_pageView scrollRectToVisible:pageRect];
    }
    _updatingFromScroll = NO;
}

- (void)rememberActiveTabState
{
    if (_selectedTabIndex < 0 || _selectedTabIndex >= (NSInteger)_tabs.count)
        return;
    if (!_doc || !_path.length)
        return;
    SPDFDocumentTab *tab = _tabs[(NSUInteger)_selectedTabIndex];
    tab.path = _path;
    tab.title = _path.lastPathComponent ?: tab.title;
    tab.pageIndex = _pageIndex;
    tab.zoom = _zoom;
    tab.fitMode = _fitMode;
    tab.viewMode = _viewMode;
    tab.scrollOrigin = _pageScrollView.contentView.bounds.origin;
}

- (void)persistActiveState
{
    [self rememberActiveTabState];
    [self savePersistentState];
}

- (NSInteger)indexOfTabForPath:(NSString *)path
{
    NSString *standardized = path.stringByStandardizingPath;
    for (NSInteger i = 0; i < (NSInteger)_tabs.count; ++i) {
        NSString *tabPath = _tabs[(NSUInteger)i].path.stringByStandardizingPath;
        if ([tabPath isEqualToString:standardized])
            return i;
    }
    return -1;
}

- (void)updateTabStrip
{
    _tabStrip.tabs = _tabs;
    _tabStrip.selectedIndex = _selectedTabIndex;
}

- (void)preloadInactiveTabs
{
    [_preloadQueue cancelAllOperations];
    for (NSInteger i = 0; i < (NSInteger)_tabs.count; ++i) {
        if (i == _selectedTabIndex)
            continue;
        NSString *path = [_tabs[(NSUInteger)i].path copy];
        if (!path.length)
            continue;
        [_preloadQueue addOperationWithBlock:^{
            @autoreleasepool {
                char err[512];
                spdf_document *doc = spdf_open(path.fileSystemRepresentation, err, sizeof(err));
                if (doc)
                    spdf_close(doc);
            }
        }];
    }
}

- (NSPoint)visibleCenterWindowPoint
{
    NSRect visible = _pageScrollView.contentView.bounds;
    NSPoint centerInPageView = NSMakePoint(NSMidX(visible), NSMidY(visible));
    return [_pageView convertPoint:centerInPageView toView:nil];
}

- (void)zoomByFactor:(CGFloat)factor centeredAtWindowPoint:(NSPoint)windowPoint
{
    if (!_doc || factor <= 0)
        return;

    NSClipView *clipView = _pageScrollView.contentView;
    NSPoint viewPoint = [_pageView convertPoint:windowPoint fromView:nil];
    NSPoint oldOrigin = clipView.bounds.origin;
    CGFloat oldZoom = _zoom;

    _fitMode = SPDFFitModeCustom;
    _zoom = MAX(kMinZoom, MIN(kMaxZoom, _zoom * factor));
    if (fabs(_zoom - oldZoom) < 0.0001)
        return;

    CGFloat ratio = _zoom / oldZoom;
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO];

    NSPoint newOrigin = NSMakePoint(viewPoint.x * ratio - (viewPoint.x - oldOrigin.x),
                                    viewPoint.y * ratio - (viewPoint.y - oldOrigin.y));
    newOrigin.x = MAX(0, MIN(newOrigin.x, MAX(0, NSWidth(_pageView.bounds) - NSWidth(clipView.bounds))));
    newOrigin.y = MAX(0, MIN(newOrigin.y, MAX(0, NSHeight(_pageView.bounds) - NSHeight(clipView.bounds))));
    [clipView scrollToPoint:newOrigin];
    [_pageScrollView reflectScrolledClipView:clipView];
    [self documentScrollPositionChanged];
    [self persistActiveState];
}

- (void)setZoomWithoutRendering:(CGFloat)newZoom centeredAtWindowPoint:(NSPoint)windowPoint
{
    if (!_doc)
        return;
    NSClipView *clipView = _pageScrollView.contentView;
    NSPoint viewPoint = [_pageView convertPoint:windowPoint fromView:nil];
    NSPoint oldOrigin = clipView.bounds.origin;
    CGFloat oldZoom = _zoom > 0 ? _zoom : 1.0;
    _zoom = MAX(kMinZoom, MIN(kMaxZoom, newZoom));
    CGFloat ratio = _zoom / oldZoom;
    _pageView.zoom = _zoom;
    [self resizeDocumentView];
    NSPoint newOrigin = NSMakePoint(viewPoint.x * ratio - (viewPoint.x - oldOrigin.x),
                                    viewPoint.y * ratio - (viewPoint.y - oldOrigin.y));
    newOrigin.x = MAX(0, MIN(newOrigin.x, MAX(0, NSWidth(_pageView.bounds) - NSWidth(clipView.bounds))));
    newOrigin.y = MAX(0, MIN(newOrigin.y, MAX(0, NSHeight(_pageView.bounds) - NSHeight(clipView.bounds))));
    [clipView scrollToPoint:newOrigin];
    [_pageScrollView reflectScrolledClipView:clipView];
    [self syncToolbarState];
    [self updateControls];
}

- (void)finishLiveZoom:(NSTimer *)timer
{
    (void)timer;
    _zoomFinishTimer = nil;
    if (_doc) {
        [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO];
        [self persistActiveState];
    }
}

- (void)beginLiveZoomByFactor:(CGFloat)factor centeredAtWindowPoint:(NSPoint)windowPoint
{
    if (!_doc || factor <= 0)
        return;
    _fitMode = SPDFFitModeCustom;
    [self setZoomWithoutRendering:_zoom * factor centeredAtWindowPoint:windowPoint];
    [_zoomFinishTimer invalidate];
    _zoomFinishTimer = [NSTimer scheduledTimerWithTimeInterval:0.09 target:self selector:@selector(finishLiveZoom:) userInfo:nil repeats:NO];
}

- (void)openDocument:(id)sender
{
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.allowedFileTypes = @[@"pdf", @"xps", @"cbz", @"epub"];
    if ([panel runModal] == NSModalResponseOK)
        [self openPath:panel.URL.path];
}

- (void)loadSelectedTab
{
    if (_selectedTabIndex < 0 || _selectedTabIndex >= (NSInteger)_tabs.count)
        return;
    SPDFDocumentTab *tab = _tabs[(NSUInteger)_selectedTabIndex];
    if (!tab.path.length)
        return;
    NSString *path = tab.path;
    [_renderQueue cancelAllOperations];

    char err[1024];
    spdf_document *newDoc = spdf_open(path.fileSystemRepresentation, err, sizeof(err));
    if (!newDoc) {
        [self showError:@"Could not open document" detail:[NSString stringWithUTF8String:err[0] ? err : "Unknown error"]];
        return;
    }

    spdf_free_outline(&_outline);
    spdf_close(_doc);
    _doc = newDoc;
    _path = [path copy];
    _pageIndex = MAX(0, MIN(tab.pageIndex, spdf_page_count(_doc) - 1));
    _highlightPageIndex = -1;
    _selectionPageIndex = -1;
    _selectedText = nil;
    _renderGeneration++;
    _zoom = tab.zoom > 0 ? tab.zoom : 1.0;
    _fitMode = tab.fitMode;
    _viewMode = tab.viewMode;
    _pageView.viewMode = _viewMode;
    _pageView.currentPageIndex = _pageIndex;
    tab.title = _path.lastPathComponent;

    [self rebuildSidebar];
    [self updateTabStrip];
    [self preloadInactiveTabs];
    [self savePersistentState];
    _statusLabel.stringValue = @"Opening...";
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!_doc)
            return;
        [self renderDocumentAndScrollToPage:_pageIndex alignTop:YES];
        if (!NSEqualPoints(tab.scrollOrigin, NSZeroPoint)) {
            [_pageScrollView.contentView scrollToPoint:tab.scrollOrigin];
            [_pageScrollView reflectScrolledClipView:_pageScrollView.contentView];
        }
        char outlineErr[1024];
        if (_doc && !spdf_load_outline(_doc, &_outline, outlineErr, sizeof(outlineErr)))
            _statusLabel.stringValue = [NSString stringWithFormat:@"Opened, but outline was not available: %s", outlineErr];
        if (_sidebarModeControl.selectedSegment == 1)
            [self rebuildSidebar];
    });
}

- (void)closeDocument:(id)sender
{
    (void)sender;
    if (_selectedTabIndex >= 0) {
        [self closeTabAtIndex:_selectedTabIndex];
        return;
    }
    spdf_free_outline(&_outline);
    spdf_close(_doc);
    _doc = NULL;
    _path = nil;
    _pageIndex = 0;
    _highlightPageIndex = -1;
    _selectionPageIndex = -1;
    _selectedText = nil;
    _renderGeneration++;
    [_sidebarItems removeAllObjects];
    [_renderedPages removeAllObjects];
    _pageView.pages = @[];
    _window.title = @"SumatraPDF";
    _statusLabel.stringValue = @"Ready";
    [_sidebarTable reloadData];
    [self updateControls];
}

- (void)openPath:(NSString *)path
{
    if (!_uiReady || !_window) {
        _pendingOpenPath = [path copy];
        return;
    }

    NSInteger existing = [self indexOfTabForPath:path];
    if (existing >= 0) {
        [self selectTabAtIndex:existing];
        return;
    }

    [self rememberActiveTabState];
    SPDFDocumentTab *tab = [[SPDFDocumentTab alloc] init];
    tab.path = [path copy];
    tab.title = path.lastPathComponent;
    tab.zoom = _zoom > 0 ? _zoom : 1.0;
    tab.fitMode = _fitMode;
    tab.viewMode = _viewMode;
    [_tabs addObject:tab];
    _selectedTabIndex = (NSInteger)_tabs.count - 1;
    [self loadSelectedTab];
    [self savePersistentState];
}

- (void)selectTabAtIndex:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger)_tabs.count || (index == _selectedTabIndex && _doc))
        return;
    [self rememberActiveTabState];
    _selectedTabIndex = index;
    [self loadSelectedTab];
    [self savePersistentState];
}

- (void)closeTabAtIndex:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger)_tabs.count)
        return;
    BOOL closingActive = index == _selectedTabIndex;
    [_tabs removeObjectAtIndex:(NSUInteger)index];
    if (!closingActive && index < _selectedTabIndex)
        _selectedTabIndex--;

    if (_tabs.count == 0) {
        _selectedTabIndex = -1;
        spdf_free_outline(&_outline);
        spdf_close(_doc);
        _doc = NULL;
        _path = nil;
        _pageIndex = 0;
        _selectedText = nil;
        _renderGeneration++;
        [_renderedPages removeAllObjects];
        _pageView.pages = @[];
        [_sidebarItems removeAllObjects];
        [_sidebarTable reloadData];
        _window.title = @"SumatraPDF";
        _statusLabel.stringValue = @"Ready";
        [self updateTabStrip];
        [self updateControls];
        [self savePersistentState];
        return;
    }

    if (closingActive) {
        _selectedTabIndex = MIN(index, (NSInteger)_tabs.count - 1);
        [self loadSelectedTab];
    } else {
        [self updateTabStrip];
        [self preloadInactiveTabs];
        [self savePersistentState];
    }
}

- (void)newTabRequested:(id)sender
{
    [self openDocument:sender];
}

- (BOOL)openFilesFromPasteboard:(NSPasteboard *)pasteboard
{
    NSArray<NSURL *> *urls = [pasteboard readObjectsForClasses:@[[NSURL class]]
                                                       options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    BOOL opened = NO;
    for (NSURL *url in urls) {
        NSString *ext = url.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"pdf"] || [ext isEqualToString:@"xps"] || [ext isEqualToString:@"cbz"] || [ext isEqualToString:@"epub"]) {
            [self openPath:url.path];
            opened = YES;
        }
    }
    return opened;
}

- (void)rebuildSidebar
{
    [_sidebarItems removeAllObjects];
    NSInteger pageCount = spdf_page_count(_doc);
    if (_sidebarModeControl.selectedSegment == 1 && _outline.count > 0) {
        for (int i = 0; i < _outline.count; ++i) {
            spdf_outline_item item = _outline.items[i];
            NSString *title = item.title ? [NSString stringWithUTF8String:item.title] : @"Untitled";
            [_sidebarItems addObject:@{@"title": title,
                                       @"page": @(item.page_index),
                                       @"level": @(item.level)}];
        }
    } else {
        for (NSInteger i = 0; i < pageCount; ++i)
            [_sidebarItems addObject:@{@"title": [NSString stringWithFormat:@"Page %ld", (long)i + 1],
                                       @"page": @(i),
                                       @"level": @0}];
    }
    [_sidebarTable reloadData];
    [self selectCurrentSidebarRow];
}

- (void)sidebarModeChanged:(id)sender
{
    (void)sender;
    [self rebuildSidebar];
}

- (void)clipViewBoundsChanged:(NSNotification *)notification
{
    (void)notification;
    [self documentScrollPositionChanged];
}

- (void)documentScrollPositionChanged
{
    if (_updatingFromScroll || _renderedPages.count == 0 || _viewMode != SPDFViewModeContinuous)
        return;
    NSInteger visiblePage = [_pageView pageIndexForVisibleRect:_pageScrollView.contentView.bounds];
    if (visiblePage != _pageIndex) {
        _pageIndex = visiblePage;
        _pageView.currentPageIndex = _pageIndex;
        [self updateControls];
        [self selectCurrentSidebarRow];
    }
}

- (BOOL)scrollViewShouldTurnWheelIntoPageChange:(NSEvent *)event
{
    (void)event;
    if (!_doc)
        return NO;
    return _viewMode == SPDFViewModeSingle || _fitMode == SPDFFitModeHeight || _fitMode == SPDFFitModePage;
}

- (void)syncToolbarState
{
    [_fitModePopup selectItemAtIndex:_fitMode];
    _continuousButton.state = _viewMode == SPDFViewModeContinuous ? NSControlStateValueOn : NSControlStateValueOff;
    _tabStrip.tabs = _tabs;
    _tabStrip.selectedIndex = _selectedTabIndex;
}

- (void)updateControls
{
    NSInteger pageCount = spdf_page_count(_doc);
    BOOL hasDoc = _doc != NULL;
    _prevButton.enabled = hasDoc && _pageIndex > 0;
    _nextButton.enabled = hasDoc && _pageIndex + 1 < pageCount;
    _pageField.enabled = hasDoc;
    _zoomOutButton.enabled = hasDoc;
    _zoomInButton.enabled = hasDoc;
    _fitModePopup.enabled = hasDoc;
    _continuousButton.enabled = hasDoc;
    _searchField.enabled = hasDoc;
    _pageField.stringValue = hasDoc ? [NSString stringWithFormat:@"%ld", (long)_pageIndex + 1] : @"";
    _pageCountLabel.stringValue = [NSString stringWithFormat:@"/ %ld", (long)pageCount];

    if (hasDoc) {
        NSString *displayName = _path.lastPathComponent ?: [NSString stringWithUTF8String:spdf_title(_doc)];
        _window.title = [NSString stringWithFormat:@"%@ - SumatraPDF", displayName];
        NSString *mode = _viewMode == SPDFViewModeContinuous ? @"Continuous" : @"Single page";
        _statusLabel.stringValue = [NSString stringWithFormat:@"Page %ld of %ld    Zoom %.0f%%    %@", (long)_pageIndex + 1, (long)pageCount, _zoom * 100.0, mode];
    }
}

- (void)selectCurrentSidebarRow
{
    if (!_doc || _updatingSelection)
        return;
    _updatingSelection = YES;
    NSInteger match = -1;
    for (NSInteger i = 0; i < _sidebarItems.count; ++i) {
        NSInteger page = [_sidebarItems[(NSUInteger)i][@"page"] integerValue];
        if (page == _pageIndex) {
            match = i;
            break;
        }
    }
    if (match >= 0) {
        [_sidebarTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)match] byExtendingSelection:NO];
        [_sidebarTable scrollRowToVisible:match];
    }
    _updatingSelection = NO;
}

- (NSArray<NSValue *> *)highlightRectsForPage:(NSInteger)pageIndex
{
    if (!_doc || _searchField.stringValue.length == 0)
        return @[];
    char err[1024];
    spdf_rect rects[256];
    int count = spdf_search_page_rects(_doc, (int)pageIndex, _searchField.stringValue.UTF8String, rects, 256, err, sizeof(err));
    if (count <= 0)
        return @[];

    NSMutableArray<NSValue *> *values = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
    for (int i = 0; i < count; ++i) {
        NSRect r = NSMakeRect(rects[i].x0, rects[i].y0, rects[i].x1 - rects[i].x0, rects[i].y1 - rects[i].y0);
        [values addObject:[NSValue valueWithRect:r]];
    }
    return values;
}

- (void)applySearchHighlightsToCurrentPage
{
    for (SPDFRenderedPage *page in _renderedPages)
        page.highlights = @[];
    if (_highlightPageIndex >= 0 && _highlightPageIndex < (NSInteger)_renderedPages.count)
        _renderedPages[(NSUInteger)_highlightPageIndex].highlights = [self highlightRectsForPage:_highlightPageIndex];
    _pageView.pages = _renderedPages;
    [_pageView setNeedsDisplay:YES];
}

- (void)documentViewSelectionChangedOnPage:(NSInteger)pageIndex from:(NSPoint)start to:(NSPoint)end
{
    if (!_doc || pageIndex < 0 || pageIndex >= (NSInteger)_renderedPages.count)
        return;

    char err[1024];
    spdf_rect rects[256];
    char *text = NULL;
    int count = spdf_select_page_text(_doc, (int)pageIndex, (float)start.x, (float)start.y, (float)end.x, (float)end.y, rects, 256, &text, err, sizeof(err));

    for (SPDFRenderedPage *page in _renderedPages)
        page.selectionRects = @[];

    if (count > 0) {
        NSMutableArray<NSValue *> *values = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
        for (int i = 0; i < count; ++i) {
            NSRect r = NSMakeRect(rects[i].x0, rects[i].y0, rects[i].x1 - rects[i].x0, rects[i].y1 - rects[i].y0);
            [values addObject:[NSValue valueWithRect:r]];
        }
        _renderedPages[(NSUInteger)pageIndex].selectionRects = values;
        _selectionPageIndex = pageIndex;
        _selectedText = text ? [NSString stringWithUTF8String:text] : @"";
    } else {
        _selectionPageIndex = -1;
        _selectedText = nil;
    }

    if (text)
        spdf_free_string(text);
    _pageView.pages = _renderedPages;
    [_pageView setNeedsDisplay:YES];
}

- (void)copySelection:(id)sender
{
    (void)sender;
    if (_selectedText.length == 0) {
        NSBeep();
        return;
    }
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:_selectedText forType:NSPasteboardTypeString];
    _statusLabel.stringValue = @"Selected text copied.";
}

- (NSString *)shortProvenanceForPath:(NSString *)path
{
    if (path.length <= 52)
        return path.lastPathComponent;
    NSString *head = [path substringToIndex:MIN((NSUInteger)20, path.length)];
    NSString *tail = [path substringFromIndex:path.length - MIN((NSUInteger)28, path.length)];
    return [NSString stringWithFormat:@"%@...%@", head, tail];
}

- (void)favoriteCurrentPage:(id)sender
{
    (void)sender;
    if (!_path.length)
        return;
    NSString *name = [NSString stringWithFormat:@"%@ p.%ld", _path.lastPathComponent, (long)_pageIndex + 1];
    NSMutableDictionary *fav = [@{@"type": @"page",
                                  @"path": _path,
                                  @"title": _path.lastPathComponent,
                                  @"page": @(_pageIndex),
                                  @"name": name,
                                  @"created": @((long)NSDate.date.timeIntervalSince1970)} mutableCopy];
    NSIndexSet *dupes = [_favorites indexesOfObjectsPassingTest:^BOOL(NSDictionary *obj, NSUInteger idx, BOOL *stop) {
        (void)idx; (void)stop;
        return [obj[@"path"] isEqualToString:_path] && [obj[@"type"] isEqualToString:@"page"] && [obj[@"page"] integerValue] == _pageIndex;
    }];
    if (dupes.count)
        [_favorites removeObjectsAtIndexes:dupes];
    [_favorites addObject:fav];
    [self savePersistentState];
    _statusLabel.stringValue = @"Page added to favorites.";
}

- (void)favoriteCurrentDocument:(id)sender
{
    (void)sender;
    if (!_path.length)
        return;
    NSMutableDictionary *fav = [@{@"type": @"document",
                                  @"path": _path,
                                  @"title": _path.lastPathComponent,
                                  @"page": @0,
                                  @"name": _path.lastPathComponent,
                                  @"created": @((long)NSDate.date.timeIntervalSince1970)} mutableCopy];
    NSIndexSet *dupes = [_favorites indexesOfObjectsPassingTest:^BOOL(NSDictionary *obj, NSUInteger idx, BOOL *stop) {
        (void)idx; (void)stop;
        return [obj[@"path"] isEqualToString:_path] && [obj[@"type"] isEqualToString:@"document"];
    }];
    if (dupes.count)
        [_favorites removeObjectsAtIndexes:dupes];
    [_favorites addObject:fav];
    [self savePersistentState];
    _statusLabel.stringValue = @"Document added to favorites.";
}

- (void)showFavoritesPalette:(id)sender
{
    (void)sender;
    _paletteMode = 1;
    [self showPaletteWithTitle:@"Favorites"];
}

- (void)focusFind:(id)sender
{
    (void)sender;
    [self showFindPalette:sender];
}

- (void)showFindPalette:(id)sender
{
    (void)sender;
    _paletteMode = 2;
    [self showPaletteWithTitle:@"Find"];
}

- (void)showPaletteWithTitle:(NSString *)title
{
    if (!_palettePanel) {
        _palettePanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 650, 420)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskUtilityWindow | NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
        _palettePanel.floatingPanel = YES;
        _palettePanel.releasedWhenClosed = NO;

        NSView *content = [[NSView alloc] initWithFrame:_palettePanel.contentView.bounds];
        content.translatesAutoresizingMaskIntoConstraints = NO;
        _palettePanel.contentView = content;

        _paletteSearchField = [[NSSearchField alloc] init];
        _paletteSearchField.translatesAutoresizingMaskIntoConstraints = NO;
        _paletteSearchField.delegate = self;
        _paletteSearchField.target = self;
        _paletteSearchField.action = @selector(activatePaletteSelection:);
        [content addSubview:_paletteSearchField];

        _paletteAllDocsCheckbox = [NSButton checkboxWithTitle:@"Search in all open documents" target:self action:@selector(refreshPaletteResults)];
        _paletteAllDocsCheckbox.translatesAutoresizingMaskIntoConstraints = NO;
        [content addSubview:_paletteAllDocsCheckbox];

        NSScrollView *scroll = [[NSScrollView alloc] init];
        scroll.translatesAutoresizingMaskIntoConstraints = NO;
        scroll.hasVerticalScroller = YES;
        [content addSubview:scroll];

        _paletteTable = [[NSTableView alloc] init];
        _paletteTable.headerView = nil;
        _paletteTable.rowHeight = 44.0;
        _paletteTable.dataSource = self;
        _paletteTable.delegate = self;
        _paletteTable.target = self;
        _paletteTable.doubleAction = @selector(activatePaletteSelection:);
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"result"];
        column.width = 620;
        [_paletteTable addTableColumn:column];
        scroll.documentView = _paletteTable;

        [NSLayoutConstraint activateConstraints:@[
            [_paletteSearchField.topAnchor constraintEqualToAnchor:content.topAnchor constant:14],
            [_paletteSearchField.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
            [_paletteSearchField.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
            [_paletteAllDocsCheckbox.topAnchor constraintEqualToAnchor:_paletteSearchField.bottomAnchor constant:8],
            [_paletteAllDocsCheckbox.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
            [scroll.topAnchor constraintEqualToAnchor:_paletteAllDocsCheckbox.bottomAnchor constant:10],
            [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
            [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
            [scroll.bottomAnchor constraintEqualToAnchor:content.bottomAnchor]
        ]];
    }

    _palettePanel.title = title;
    _paletteSearchField.stringValue = @"";
    _paletteSearchField.placeholderString = _paletteMode == 1 ? @"Search favorites" : @"Search current document";
    _paletteAllDocsCheckbox.hidden = _paletteMode != 2;
    [self refreshPaletteResults];
    if (_palettePanel.sheetParent != _window)
        [_window beginSheet:_palettePanel completionHandler:nil];
    [_palettePanel makeFirstResponder:_paletteSearchField];
}

- (void)refreshPaletteResults
{
    _paletteSearchGeneration++;
    NSUInteger generation = _paletteSearchGeneration;
    [_paletteResults removeAllObjects];
    NSString *query = _paletteSearchField.stringValue.lowercaseString ?: @"";

    if (_paletteMode == 1) {
        if (_path.length) {
            [_paletteResults addObject:@{@"kind": @"addPage", @"title": @"Favorite current page", @"subtitle": _path.lastPathComponent ?: @""}];
            [_paletteResults addObject:@{@"kind": @"addDoc", @"title": @"Favorite current document", @"subtitle": _path.lastPathComponent ?: @""}];
        }
        for (NSDictionary *fav in _favorites) {
            NSString *haystack = [[NSString stringWithFormat:@"%@ %@ %@", fav[@"name"] ?: @"", fav[@"title"] ?: @"", fav[@"path"] ?: @""] lowercaseString];
            if (query.length == 0 || [haystack containsString:query]) {
                [_paletteResults addObject:@{@"kind": @"favorite",
                                             @"title": fav[@"name"] ?: fav[@"title"] ?: @"Favorite",
                                             @"subtitle": [self shortProvenanceForPath:fav[@"path"] ?: @""],
                                             @"path": fav[@"path"] ?: @"",
                                             @"page": fav[@"page"] ?: @0}];
            }
        }
    } else if (_paletteMode == 2) {
        if (query.length > 0 && _doc) {
            [_preloadQueue cancelAllOperations];
            [_paletteResults addObject:@{@"kind": @"status", @"title": @"Searching...", @"subtitle": _paletteAllDocsCheckbox.state == NSControlStateValueOn ? @"Current document and open tabs" : @"Current document"}];
            [self runFindPaletteSearchForQuery:query generation:generation searchAll:_paletteAllDocsCheckbox.state == NSControlStateValueOn];
        } else {
            for (NSDictionary *fav in _favorites) {
                NSString *haystack = [[NSString stringWithFormat:@"%@ %@ %@", fav[@"name"] ?: @"", fav[@"title"] ?: @"", fav[@"path"] ?: @""] lowercaseString];
                if (query.length == 0 || [haystack containsString:query]) {
                    [_paletteResults addObject:@{@"kind": @"favorite",
                                                 @"title": fav[@"name"] ?: fav[@"title"] ?: @"Favorite",
                                                 @"subtitle": [NSString stringWithFormat:@"Favorite - %@", [self shortProvenanceForPath:fav[@"path"] ?: @""]],
                                                 @"path": fav[@"path"] ?: @"",
                                                 @"page": fav[@"page"] ?: @0}];
                }
            }
        }
    }
    [_paletteTable reloadData];
    if (_paletteResults.count)
        [_paletteTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
}

- (NSArray<NSDictionary *> *)favoriteResultsForQuery:(NSString *)query prefix:(NSString *)prefix
{
    NSMutableArray<NSDictionary *> *results = [NSMutableArray array];
    NSString *lowerQuery = query.lowercaseString ?: @"";
    for (NSDictionary *fav in _favorites) {
        NSString *haystack = [[NSString stringWithFormat:@"%@ %@ %@", fav[@"name"] ?: @"", fav[@"title"] ?: @"", fav[@"path"] ?: @""] lowercaseString];
        if (lowerQuery.length == 0 || [haystack containsString:lowerQuery]) {
            NSString *subtitle = [self shortProvenanceForPath:fav[@"path"] ?: @""];
            if (prefix.length)
                subtitle = [NSString stringWithFormat:@"%@ - %@", prefix, subtitle];
            [results addObject:@{@"kind": @"favorite",
                                 @"title": fav[@"name"] ?: fav[@"title"] ?: @"Favorite",
                                 @"subtitle": subtitle,
                                 @"path": fav[@"path"] ?: @"",
                                 @"page": fav[@"page"] ?: @0}];
        }
    }
    return results;
}

- (void)runFindPaletteSearchForQuery:(NSString *)query generation:(NSUInteger)generation searchAll:(BOOL)searchAll
{
    NSString *currentPath = [_path copy];
    NSArray<SPDFDocumentTab *> *tabs = [_tabs copy];
    [_preloadQueue addOperationWithBlock:^{
        @autoreleasepool {
            NSMutableArray<NSDictionary *> *results = [NSMutableArray array];
            NSMutableSet<NSString *> *searchedPaths = [NSMutableSet set];
            for (SPDFDocumentTab *tab in tabs) {
                if (generation != self->_paletteSearchGeneration)
                    return;
                if (results.count >= 220)
                    break;
                BOOL isCurrent = [tab.path.stringByStandardizingPath isEqualToString:currentPath.stringByStandardizingPath];
                if (!isCurrent && !searchAll)
                    continue;
                NSString *path = tab.path;
                if (!path.length || [searchedPaths containsObject:path.stringByStandardizingPath])
                    continue;
                [searchedPaths addObject:path.stringByStandardizingPath];

                char openErr[512];
                spdf_document *doc = spdf_open(path.fileSystemRepresentation, openErr, sizeof(openErr));
                if (!doc)
                    continue;
                NSInteger pageCount = spdf_page_count(doc);
                for (NSInteger page = 0; page < pageCount && results.count < 220; ++page) {
                    if (generation != self->_paletteSearchGeneration)
                        break;
                    char err[512];
                    int hits = spdf_search_page(doc, (int)page, query.UTF8String, err, sizeof(err));
                    if (hits > 0) {
                        [results addObject:@{@"kind": @"find",
                                             @"title": [NSString stringWithFormat:@"Page %ld: %d match%@", (long)page + 1, hits, hits == 1 ? @"" : @"es"],
                                             @"subtitle": [self shortProvenanceForPath:path],
                                             @"path": path,
                                             @"page": @(page)}];
                    }
                }
                spdf_close(doc);
            }

            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                if (generation != self->_paletteSearchGeneration || self->_paletteMode != 2)
                    return;
                [self->_paletteResults removeAllObjects];
                if (results.count > 0) {
                    [self->_paletteResults addObjectsFromArray:results];
                } else {
                    [self->_paletteResults addObjectsFromArray:[self favoriteResultsForQuery:query prefix:@"Favorite"]];
                }
                [self->_paletteTable reloadData];
                if (self->_paletteResults.count)
                    [self->_paletteTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
            }];
        }
    }];
}

- (void)openPaletteResult:(NSDictionary *)result
{
    NSString *kind = result[@"kind"];
    if ([kind isEqualToString:@"status"])
        return;
    if ([kind isEqualToString:@"addPage"]) {
        [self favoriteCurrentPage:nil];
        return;
    }
    if ([kind isEqualToString:@"addDoc"]) {
        [self favoriteCurrentDocument:nil];
        return;
    }
    NSString *path = result[@"path"];
    NSInteger page = [result[@"page"] integerValue];
    if (path.length) {
        [self openPath:path];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (_doc && [_path.stringByStandardizingPath isEqualToString:path.stringByStandardizingPath]) {
                _pageIndex = MAX(0, MIN(page, spdf_page_count(_doc) - 1));
                _pageView.currentPageIndex = _pageIndex;
                [self renderDocumentAndScrollToPage:_pageIndex alignTop:YES];
            }
        });
    }
}

- (void)activatePaletteSelection:(id)sender
{
    (void)sender;
    NSInteger row = _paletteTable.selectedRow;
    if (row < 0 || row >= (NSInteger)_paletteResults.count)
        return;
    NSDictionary *result = _paletteResults[(NSUInteger)row];
    [_window endSheet:_palettePanel];
    [_palettePanel orderOut:nil];
    [self openPaletteResult:result];
}

- (void)previousPage:(id)sender
{
    (void)sender;
    if (_doc && _pageIndex > 0) {
        _pageIndex--;
        _pageView.currentPageIndex = _pageIndex;
        [self renderPageIfNeededAtIndex:_pageIndex];
        [self resizeDocumentView];
        [self scrollToPage:_pageIndex alignTop:YES];
        [self updateControls];
        [self selectCurrentSidebarRow];
        [_pageView setNeedsDisplay:YES];
        [self persistActiveState];
    }
}

- (void)nextPage:(id)sender
{
    (void)sender;
    if (_doc && _pageIndex + 1 < spdf_page_count(_doc)) {
        _pageIndex++;
        _pageView.currentPageIndex = _pageIndex;
        [self renderPageIfNeededAtIndex:_pageIndex];
        [self resizeDocumentView];
        [self scrollToPage:_pageIndex alignTop:YES];
        [self updateControls];
        [self selectCurrentSidebarRow];
        [_pageView setNeedsDisplay:YES];
        [self persistActiveState];
    }
}

- (void)firstPage:(id)sender
{
    (void)sender;
    if (_doc) {
        _pageIndex = 0;
        _pageView.currentPageIndex = _pageIndex;
        [self renderPageIfNeededAtIndex:_pageIndex];
        [self resizeDocumentView];
        [self scrollToPage:_pageIndex alignTop:YES];
        [self updateControls];
        [self selectCurrentSidebarRow];
        [self persistActiveState];
    }
}

- (void)lastPage:(id)sender
{
    (void)sender;
    if (_doc) {
        _pageIndex = spdf_page_count(_doc) - 1;
        _pageView.currentPageIndex = _pageIndex;
        [self renderPageIfNeededAtIndex:_pageIndex];
        [self resizeDocumentView];
        [self scrollToPage:_pageIndex alignTop:YES];
        [self updateControls];
        [self selectCurrentSidebarRow];
        [self persistActiveState];
    }
}

- (void)focusPageField:(id)sender
{
    (void)sender;
    [_window makeFirstResponder:_pageField];
}

- (void)pageFieldChanged:(id)sender
{
    (void)sender;
    if (!_doc)
        return;
    NSInteger requested = _pageField.integerValue - 1;
    NSInteger pageCount = spdf_page_count(_doc);
    requested = MAX(0, MIN(requested, pageCount - 1));
    _pageIndex = requested;
    _pageView.currentPageIndex = _pageIndex;
    [self renderPageIfNeededAtIndex:_pageIndex];
    [self resizeDocumentView];
    [self scrollToPage:_pageIndex alignTop:YES];
    [self updateControls];
    [self selectCurrentSidebarRow];
    [self persistActiveState];
}

- (void)zoomIn:(id)sender
{
    (void)sender;
    [self zoomByFactor:1.20 centeredAtWindowPoint:[self visibleCenterWindowPoint]];
}

- (void)zoomOut:(id)sender
{
    (void)sender;
    [self zoomByFactor:1.0 / 1.20 centeredAtWindowPoint:[self visibleCenterWindowPoint]];
}

- (void)actualSize:(id)sender
{
    (void)sender;
    if (!_doc)
        return;
    _fitMode = SPDFFitModeActual;
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO];
    [self persistActiveState];
}

- (void)fitWidth:(id)sender
{
    (void)sender;
    if (!_doc)
        return;
    _fitMode = SPDFFitModeWidth;
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO];
    [self persistActiveState];
}

- (void)fitHeight:(id)sender
{
    (void)sender;
    if (!_doc)
        return;
    _fitMode = SPDFFitModeHeight;
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:YES];
    [self persistActiveState];
}

- (void)fitPage:(id)sender
{
    (void)sender;
    if (!_doc)
        return;
    _fitMode = SPDFFitModePage;
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:YES];
    [self persistActiveState];
}

- (void)fitModePopupChanged:(id)sender
{
    (void)sender;
    _fitMode = (SPDFFitMode)_fitModePopup.indexOfSelectedItem;
    if (_doc) {
        [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO];
        [self persistActiveState];
    }
}

- (void)setSinglePageMode:(id)sender
{
    (void)sender;
    if (!_doc)
        return;
    _viewMode = SPDFViewModeSingle;
    _pageView.viewMode = _viewMode;
    _pageView.currentPageIndex = _pageIndex;
    [self resizeDocumentView];
    [self scrollToPage:_pageIndex alignTop:YES];
    [self syncToolbarState];
    [self updateControls];
    [self persistActiveState];
}

- (void)setContinuousMode:(id)sender
{
    (void)sender;
    if (!_doc)
        return;
    _viewMode = SPDFViewModeContinuous;
    _pageView.viewMode = _viewMode;
    [self resizeDocumentView];
    [self scrollToPage:_pageIndex alignTop:NO];
    [self syncToolbarState];
    [self updateControls];
    [self persistActiveState];
}

- (void)toggleContinuous:(id)sender
{
    (void)sender;
    if (_continuousButton.state == NSControlStateValueOn)
        [self setContinuousMode:sender];
    else
        [self setSinglePageMode:sender];
}

- (void)toggleSidebar:(id)sender
{
    (void)sender;
    if (!_sidebarVisible) {
        [_splitView addSubview:_sidebarContainer positioned:NSWindowBelow relativeTo:_pageScrollView];
        [_splitView setPosition:240 ofDividerAtIndex:0];
        _sidebarVisible = YES;
    } else {
        [_sidebarContainer removeFromSuperview];
        _sidebarVisible = NO;
    }
    [self persistActiveState];
}

- (void)toggleFullScreen:(id)sender
{
    [_window toggleFullScreen:sender];
}

- (void)printDocument:(id)sender
{
    (void)sender;
    if (!_doc) {
        NSBeep();
        return;
    }

    char err[1024];
    for (NSInteger i = 0; i < (NSInteger)_renderedPages.count; ++i) {
        if (!_renderedPages[(NSUInteger)i].image) {
            SPDFRenderedPage *page = [self renderedPageAtIndex:i error:err errorLength:sizeof(err)];
            if (!page) {
                [self showError:@"Could not prepare print job" detail:[NSString stringWithUTF8String:err[0] ? err : "Unknown error"]];
                return;
            }
            [_renderedPages replaceObjectAtIndex:(NSUInteger)i withObject:page];
        }
    }

    NSPrintInfo *info = [NSPrintInfo.sharedPrintInfo copy];
    info.horizontalPagination = NSPrintingPaginationModeClip;
    info.verticalPagination = NSPrintingPaginationModeClip;
    info.horizontallyCentered = YES;
    info.verticallyCentered = YES;

    NSSize paper = info.paperSize;
    SPDFPrintView *printView = [[SPDFPrintView alloc] initWithFrame:NSMakeRect(0, 0, paper.width, paper.height * MAX(1, (NSInteger)_renderedPages.count))];
    printView.pages = _renderedPages;

    NSPrintOperation *operation = [NSPrintOperation printOperationWithView:printView printInfo:info];
    operation.showsPrintPanel = YES;
    operation.showsProgressPanel = YES;
    [operation runOperationModalForWindow:_window delegate:nil didRunSelector:NULL contextInfo:NULL];
}

- (void)showProperties:(id)sender
{
    (void)sender;
    if (!_doc)
        return;
    NSString *message = [NSString stringWithFormat:@"%@\n%ld pages\n%@", spdf_title(_doc) ? [NSString stringWithUTF8String:spdf_title(_doc)] : @"Untitled", (long)spdf_page_count(_doc), _path ?: @""];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Document Properties";
    alert.informativeText = message;
    [alert runModal];
}

- (void)openInExternalReader:(id)sender
{
    (void)sender;
    if (!_path.length) {
        NSBeep();
        return;
    }

    NSURL *fileURL = [NSURL fileURLWithPath:_path];
    NSURL *acrobat = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.adobe.Reader"];
    if (!acrobat)
        acrobat = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.adobe.Acrobat.Pro"];
    if (acrobat) {
        NSWorkspaceOpenConfiguration *config = [NSWorkspaceOpenConfiguration configuration];
        [NSWorkspace.sharedWorkspace openURLs:@[fileURL] withApplicationAtURL:acrobat configuration:config completionHandler:nil];
    } else {
        [NSWorkspace.sharedWorkspace openURL:fileURL];
    }
}

- (void)copyCurrentPageImage:(id)sender
{
    (void)sender;
    if (!_doc || _pageIndex < 0 || _pageIndex >= (NSInteger)_renderedPages.count || !_renderedPages[(NSUInteger)_pageIndex].image) {
        NSBeep();
        return;
    }

    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard writeObjects:@[_renderedPages[(NSUInteger)_pageIndex].image]];
    _statusLabel.stringValue = @"Page image copied.";
}

- (void)showContextMenuForDocumentView:(NSView *)view event:(NSEvent *)event
{
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *copy = [menu addItemWithTitle:@"Copy" action:@selector(copySelection:) keyEquivalent:@""];
    copy.enabled = _selectedText.length > 0;
    NSMenuItem *copyImage = [menu addItemWithTitle:@"Copy Page Image" action:@selector(copyCurrentPageImage:) keyEquivalent:@""];
    copyImage.enabled = _doc && _pageIndex >= 0 && _pageIndex < (NSInteger)_renderedPages.count && _renderedPages[(NSUInteger)_pageIndex].image != nil;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Zoom In" action:@selector(zoomIn:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Zoom Out" action:@selector(zoomOut:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Fit Width" action:@selector(fitWidth:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Fit Page" action:@selector(fitPage:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Favorite Page" action:@selector(favoriteCurrentPage:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Properties..." action:@selector(showProperties:) keyEquivalent:@""];
    [NSMenu popUpContextMenu:menu withEvent:event forView:view];
}

- (void)unimplementedMenuItem:(id)sender
{
    (void)sender;
    NSBeep();
    _statusLabel.stringValue = @"This SumatraPDF command is listed but not implemented yet.";
}

- (void)findNext:(id)sender
{
    (void)sender;
    [self findFromCurrentForward:YES];
}

- (void)findPrevious:(id)sender
{
    (void)sender;
    [self findFromCurrentForward:NO];
}

- (void)findFromCurrentForward:(BOOL)forward
{
    if (!_doc || _searchField.stringValue.length == 0)
        return;

    char err[1024];
    NSInteger pageCount = spdf_page_count(_doc);
    for (NSInteger offset = 0; offset < pageCount; ++offset) {
        NSInteger page = forward ? (_pageIndex + offset) % pageCount : (_pageIndex - offset + pageCount) % pageCount;
        int hits = spdf_search_page(_doc, (int)page, _searchField.stringValue.UTF8String, err, sizeof(err));
        if (hits > 0) {
            _pageIndex = page;
            _highlightPageIndex = page;
            _pageView.currentPageIndex = _pageIndex;
            [self applySearchHighlightsToCurrentPage];
            [self resizeDocumentView];
            [self scrollToPage:_pageIndex alignTop:YES];
            [self updateControls];
            [self selectCurrentSidebarRow];
            _statusLabel.stringValue = [NSString stringWithFormat:@"Found %d match%@ on page %ld", hits, hits == 1 ? @"" : @"es", (long)page + 1];
            return;
        }
    }
    _highlightPageIndex = -1;
    [self applySearchHighlightsToCurrentPage];
    _statusLabel.stringValue = [NSString stringWithFormat:@"No matches for \"%@\"", _searchField.stringValue];
}

- (void)controlTextDidChange:(NSNotification *)notification
{
    if (notification.object == _searchField) {
        _highlightPageIndex = _pageIndex;
        [self applySearchHighlightsToCurrentPage];
    } else if (notification.object == _paletteSearchField) {
        [self refreshPaletteResults];
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    if (tableView == _paletteTable)
        return (NSInteger)_paletteResults.count;
    return (NSInteger)_sidebarItems.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    (void)tableColumn;
    if (tableView == _paletteTable) {
        NSTableCellView *cell = [tableView makeViewWithIdentifier:@"PaletteCell" owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 620, 44)];
            cell.identifier = @"PaletteCell";

            NSTextField *title = [NSTextField labelWithString:@""];
            title.translatesAutoresizingMaskIntoConstraints = NO;
            title.lineBreakMode = NSLineBreakByTruncatingMiddle;
            title.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
            cell.textField = title;
            [cell addSubview:title];

            NSTextField *subtitle = [NSTextField labelWithString:@""];
            subtitle.translatesAutoresizingMaskIntoConstraints = NO;
            subtitle.identifier = @"subtitle";
            subtitle.lineBreakMode = NSLineBreakByTruncatingMiddle;
            subtitle.font = [NSFont systemFontOfSize:11];
            subtitle.textColor = NSColor.secondaryLabelColor;
            [cell addSubview:subtitle];

            [NSLayoutConstraint activateConstraints:@[
                [title.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:12],
                [title.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-10],
                [title.topAnchor constraintEqualToAnchor:cell.topAnchor constant:6],
                [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
                [subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
                [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2]
            ]];
        }

        NSDictionary *result = _paletteResults[(NSUInteger)row];
        cell.textField.stringValue = result[@"title"] ?: @"";
        for (NSView *subview in cell.subviews) {
            if ([subview.identifier isEqualToString:@"subtitle"])
                ((NSTextField *)subview).stringValue = result[@"subtitle"] ?: @"";
        }
        return cell;
    }

    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"SidebarCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 230, 25)];
        cell.identifier = @"SidebarCell";
        NSTextField *field = [NSTextField labelWithString:@""];
        field.translatesAutoresizingMaskIntoConstraints = NO;
        field.lineBreakMode = NSLineBreakByTruncatingTail;
        cell.textField = field;
        [cell addSubview:field];
        [NSLayoutConstraint activateConstraints:@[
            [field.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:8],
            [field.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-6],
            [field.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
        ]];
    }

    NSDictionary *item = _sidebarItems[(NSUInteger)row];
    NSInteger level = [item[@"level"] integerValue];
    NSString *indent = [@"" stringByPaddingToLength:(NSUInteger)(level * 3) withString:@" " startingAtIndex:0];
    cell.textField.stringValue = [indent stringByAppendingString:item[@"title"]];
    cell.textField.font = [NSFont systemFontOfSize:13];
    cell.textField.textColor = [item[@"page"] integerValue] >= 0 ? NSColor.labelColor : NSColor.secondaryLabelColor;
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    if (notification.object == _paletteTable)
        return;
    if (_updatingSelection)
        return;
    NSInteger row = _sidebarTable.selectedRow;
    if (row < 0 || row >= (NSInteger)_sidebarItems.count)
        return;
    NSInteger page = [_sidebarItems[(NSUInteger)row][@"page"] integerValue];
    if (page >= 0 && page != _pageIndex) {
        _pageIndex = page;
        _pageView.currentPageIndex = _pageIndex;
        [self resizeDocumentView];
        [self scrollToPage:_pageIndex alignTop:YES];
        [self updateControls];
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    SEL action = menuItem.action;
    BOOL hasDoc = _doc != NULL;
    if (action == @selector(openDocument:) || action == @selector(toggleFullScreen:) || action == @selector(showFavoritesPalette:) || action == @selector(showFindPalette:) || action == @selector(focusFind:))
        return YES;
    if (action == @selector(copySelection:))
        return _selectedText.length > 0;
    if (action == @selector(copyCurrentPageImage:))
        return hasDoc && _pageIndex >= 0 && _pageIndex < (NSInteger)_renderedPages.count && _renderedPages[(NSUInteger)_pageIndex].image != nil;
    if (!hasDoc)
        return action == @selector(unimplementedMenuItem:);

    if (action == @selector(setSinglePageMode:))
        menuItem.state = _viewMode == SPDFViewModeSingle ? NSControlStateValueOn : NSControlStateValueOff;
    else if (action == @selector(setContinuousMode:))
        menuItem.state = _viewMode == SPDFViewModeContinuous ? NSControlStateValueOn : NSControlStateValueOff;
    else if (action == @selector(fitWidth:))
        menuItem.state = _fitMode == SPDFFitModeWidth ? NSControlStateValueOn : NSControlStateValueOff;
    else if (action == @selector(fitHeight:))
        menuItem.state = _fitMode == SPDFFitModeHeight ? NSControlStateValueOn : NSControlStateValueOff;
    else if (action == @selector(fitPage:))
        menuItem.state = _fitMode == SPDFFitModePage ? NSControlStateValueOn : NSControlStateValueOff;
    else if (action == @selector(actualSize:))
        menuItem.state = _fitMode == SPDFFitModeActual ? NSControlStateValueOn : NSControlStateValueOff;
    else if (action == @selector(toggleSidebar:))
        menuItem.state = _sidebarVisible ? NSControlStateValueOn : NSControlStateValueOff;

    return YES;
}

- (void)showError:(NSString *)message detail:(NSString *)detail
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = message;
    alert.informativeText = detail ?: @"";
    alert.alertStyle = NSAlertStyleWarning;
    [alert runModal];
}

@end

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        for (int i = 1; i < argc; ++i) {
            if (strcmp(argv[i], "--version") == 0) {
                printf("SumatraPDF portable mac 0.4\n");
                return 0;
            }
        }

        NSApplication *app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyRegular;

        SumatraMacDelegate *delegate = [[SumatraMacDelegate alloc] init];
        for (int i = 1; i < argc; ++i) {
            if (argv[i][0] != '-') {
                delegate.initialPath = [NSString stringWithUTF8String:argv[i]];
                break;
            }
        }
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
