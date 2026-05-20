#import <Cocoa/Cocoa.h>

#include "sumatra_pdf_core.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const CGFloat kPageMargin = 44.0;
static const CGFloat kPageGap = 26.0;
static const CGFloat kMinZoom = 0.10;
static const CGFloat kMaxZoom = 8.00;
static const CGFloat kSelectionOverlayAlpha = 0.20;
static const CGFloat kTabStripHeight = 42.0;
static const CGFloat kMinimapWidth = 96.0;

static CGFloat spdf_clamp_cg(CGFloat value, CGFloat minValue, CGFloat maxValue) {
    return MAX(minValue, MIN(maxValue, value));
}

static NSString* spdf_display_label_without_extension(NSString* label) {
    if (!label.length) return @"";
    NSArray<NSString*>* extensions = @[ @".pdf", @".xps", @".cbz", @".epub" ];
    for (NSString* ext in extensions) {
        NSRange range = [label rangeOfString:ext options:NSCaseInsensitiveSearch | NSBackwardsSearch];
        if (range.location == NSNotFound) continue;
        NSUInteger end = range.location + range.length;
        BOOL atEnd = end == label.length;
        BOOL beforeSuffix = !atEnd && ([[NSCharacterSet whitespaceAndNewlineCharacterSet]
                                           characterIsMember:[label characterAtIndex:end]] ||
                                       [label characterAtIndex:end] == '-');
        if (atEnd || beforeSuffix) return [label stringByReplacingCharactersInRange:range withString:@""];
    }
    return label;
}

static NSString* spdf_display_name_for_path(NSString* path) {
    NSString* name = path.lastPathComponent;
    return spdf_display_label_without_extension(name);
}

static NSString* spdf_display_path_without_extension(NSString* path) {
    if (!path.length) return @"";
    NSString* stem = path.stringByDeletingPathExtension;
    return stem.length && ![stem isEqualToString:path] ? stem : path;
}

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

typedef NS_ENUM(NSInteger, SPDFSidebarMode) {
    SPDFSidebarModeChapters = 0,
    SPDFSidebarModeComments = 1
};

@class SumatraMacDelegate;

@interface SPDFRenderedPage : NSObject
@property(nonatomic) NSInteger pageIndex;
@property(nonatomic) CGFloat pageWidth;
@property(nonatomic) CGFloat pageHeight;
@property(nonatomic, strong) NSImage* image;
@property(nonatomic, copy) NSArray<NSValue*>* highlights;
@property(nonatomic, copy) NSArray<NSValue*>* selectionRects;
@end

@implementation SPDFRenderedPage
@end

@interface SPDFDocumentTab : NSObject
@property(nonatomic, copy) NSString* path;
@property(nonatomic, copy) NSString* title;
@property(nonatomic) NSInteger pageIndex;
@property(nonatomic) CGFloat zoom;
@property(nonatomic) SPDFFitMode fitMode;
@property(nonatomic) SPDFViewMode viewMode;
@property(nonatomic) NSPoint scrollOrigin;
@property(nonatomic) BOOL hasScrollOrigin;
@end

@implementation SPDFDocumentTab

- (instancetype)init {
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
@property(nonatomic) spdf_document* document;
@property(nonatomic, copy) NSString* path;
@end

@implementation SPDFWorkerDocument

- (void)dealloc {
    spdf_close(_document);
}

@end

@interface SPDFTabStripView : NSView
@property(nonatomic, weak) SumatraMacDelegate* reader;
@property(nonatomic, copy) NSArray<SPDFDocumentTab*>* tabs;
@property(nonatomic) NSInteger selectedIndex;
@property(nonatomic) CGFloat reservedLeadingInset;
@end

@interface SPDFPaletteSearchField : NSSearchField
@property(nonatomic, weak) SumatraMacDelegate* reader;
@end

@interface SPDFDropView : NSView <NSDraggingDestination>
@property(nonatomic, weak) SumatraMacDelegate* reader;
@end

@interface SPDFScrollView : NSScrollView
@property(nonatomic, weak) SumatraMacDelegate* reader;
@end

@interface SPDFDocumentView : NSView <NSDraggingDestination>
@property(nonatomic, copy) NSArray<SPDFRenderedPage*>* pages;
@property(nonatomic) NSInteger currentPageIndex;
@property(nonatomic) CGFloat zoom;
@property(nonatomic) SPDFViewMode viewMode;
@property(nonatomic, weak) SumatraMacDelegate* reader;
- (NSSize)documentSizeForClipSize:(NSSize)clipSize;
- (NSRect)rectForPageAtIndex:(NSInteger)pageIndex;
- (NSInteger)pageIndexForVisibleRect:(NSRect)visibleRect;
- (void)cancelTransientInteraction;
@end

@interface SPDFMinimapView : NSView
@property(nonatomic, copy) NSArray<SPDFRenderedPage*>* pages;
@property(nonatomic) NSRect documentVisibleRect;
@property(nonatomic) CGFloat documentWidth;
@property(nonatomic) CGFloat documentHeight;
@property(nonatomic) CGFloat documentScale;
@property(nonatomic) SPDFViewMode viewMode;
@property(nonatomic) NSInteger currentPageIndex;
@property(nonatomic, weak) SumatraMacDelegate* reader;
@end

@interface SumatraMacDelegate : NSObject <NSApplicationDelegate,
                                          NSWindowDelegate,
                                          NSTableViewDataSource,
                                          NSTableViewDelegate,
                                          NSSearchFieldDelegate,
                                          NSTextFieldDelegate,
                                          NSMenuItemValidation>
@property(nonatomic, copy) NSString* initialPath;
- (BOOL)scrollViewShouldTurnWheelIntoPageChange:(NSEvent*)event;
- (void)zoomByFactor:(CGFloat)factor centeredAtWindowPoint:(NSPoint)windowPoint;
- (void)beginLiveZoomByFactor:(CGFloat)factor centeredAtWindowPoint:(NSPoint)windowPoint;
- (void)documentScrollPositionChanged;
- (void)documentViewSelectionChangedOnPage:(NSInteger)pageIndex from:(NSPoint)start to:(NSPoint)end;
- (void)copySelection:(id)sender;
- (void)selectTabAtIndex:(NSInteger)index;
- (void)closeTabAtIndex:(NSInteger)index;
- (void)newTabRequested:(id)sender;
- (void)focusFind:(id)sender;
- (void)showFindPalette:(id)sender;
- (void)paletteMoveSelection:(NSInteger)delta;
- (void)closePalette:(id)sender;
- (void)activatePaletteSelection:(id)sender;
- (SPDFDocumentView*)newDocumentView;
- (void)replaceDocumentViewForTabSwitch;
- (void)updateFindControls;
- (void)updateMinimap;
- (void)renderDocumentAndScrollToPage:(NSInteger)pageIndex alignTop:(BOOL)alignTop;
- (void)renderDocumentAndScrollToPage:(NSInteger)pageIndex
                             alignTop:(BOOL)alignTop
                        restoreOrigin:(NSValue*)restoreOrigin;
- (void)scrollDocumentClipViewToOrigin:(NSPoint)origin notify:(BOOL)notify;
- (void)minimapViewDidRequestScrollToFraction:(CGFloat)yFraction;
- (void)minimapViewDidRequestScrollToPage:(NSInteger)pageIndex yFractionInPage:(CGFloat)yFraction;
- (void)minimapViewDidRequestCenterAtDocumentPoint:(NSPoint)documentPoint;
- (void)minimapViewDidRequestCenterOnPage:(NSInteger)pageIndex
                          xFractionInPage:(CGFloat)xFraction
                          yFractionInPage:(CGFloat)yFraction;
- (BOOL)openFilesFromPasteboard:(NSPasteboard*)pasteboard;
- (void)showContextMenuForDocumentView:(NSView*)view event:(NSEvent*)event;
@end

@implementation SPDFTabStripView

- (BOOL)isFlipped {
    return NO;
}

- (CGFloat)tabWidth {
    NSInteger count = MAX(1, (NSInteger)self.tabs.count);
    CGFloat available = NSMinX([self plusRect]) - [self leftInset] - 12.0 - (count - 1) * 6.0;
    if (available <= 0) return 112.0;
    return MAX(112.0, MIN(178.0, floor(available / count)));
}

- (CGFloat)leftInset {
    return MAX(16.0, self.reservedLeadingInset > 0 ? self.reservedLeadingInset : 138.0);
}

- (NSRect)plusRect {
    CGFloat x = MAX([self leftInset] + 48, NSWidth(self.bounds) - 42);
    x = MIN(x, MAX([self leftInset] + 48, NSWidth(self.bounds) - 40));
    return NSMakeRect(x, 7, 32, 28);
}

- (NSRect)rectForTabAtIndex:(NSInteger)index {
    CGFloat x = [self leftInset] + index * ([self tabWidth] + 6);
    CGFloat maxRight = NSMinX([self plusRect]) - 10;
    CGFloat width = MIN([self tabWidth], maxRight - x);
    return NSMakeRect(x, 7, width, 28);
}

- (void)setTabs:(NSArray<SPDFDocumentTab*>*)tabs {
    _tabs = [tabs copy];
    [self setNeedsDisplay:YES];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    _selectedIndex = selectedIndex;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor clearColor] setFill];
    NSRectFill(self.bounds);

    NSMutableParagraphStyle* tabTitleStyle = [[NSMutableParagraphStyle alloc] init];
    tabTitleStyle.alignment = NSTextAlignmentCenter;
    tabTitleStyle.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSDictionary* attrs = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName : NSColor.labelColor,
        NSParagraphStyleAttributeName : tabTitleStyle
    };
    NSDictionary* dimAttrs = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12],
        NSForegroundColorAttributeName : NSColor.secondaryLabelColor,
        NSParagraphStyleAttributeName : tabTitleStyle
    };

    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; ++i) {
        NSRect tabRect = [self rectForTabAtIndex:i];
        if (NSWidth(tabRect) < 74) break;
        BOOL selected = i == self.selectedIndex;
        NSColor* fill = selected ? NSColor.windowBackgroundColor : NSColor.controlBackgroundColor;
        [fill setFill];
        [[NSBezierPath bezierPathWithRoundedRect:tabRect xRadius:7 yRadius:7] fill];

        SPDFDocumentTab* tab = self.tabs[(NSUInteger)i];
        NSString* title =
            tab.path.length ? spdf_display_name_for_path(tab.path) : spdf_display_label_without_extension(tab.title);
        NSDictionary* titleAttrs = selected ? attrs : dimAttrs;
        CGFloat titleHeight = [title sizeWithAttributes:titleAttrs].height;
        CGFloat titleInset = 26.0;
        NSRect titleRect = NSMakeRect(NSMinX(tabRect) + titleInset, floor(NSMidY(tabRect) - titleHeight / 2.0),
                                      MAX(1.0, NSWidth(tabRect) - titleInset * 2.0), titleHeight + 2);
        [title drawWithRect:titleRect
                    options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine
                 attributes:titleAttrs];

        NSString* close = @"x";
        NSSize closeSize = [close sizeWithAttributes:dimAttrs];
        [close drawAtPoint:NSMakePoint(NSMaxX(tabRect) - 18, floor(NSMidY(tabRect) - closeSize.height / 2.0))
            withAttributes:dimAttrs];
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
}

- (void)mouseDown:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(point, [self plusRect])) {
        [self.reader newTabRequested:self];
        return;
    }

    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; ++i) {
        NSRect tabRect = [self rectForTabAtIndex:i];
        if (!NSPointInRect(point, tabRect)) continue;
        NSRect closeRect = NSMakeRect(NSMaxX(tabRect) - 22, NSMinY(tabRect), 22, NSHeight(tabRect));
        if (NSPointInRect(point, closeRect))
            [self.reader closeTabAtIndex:i];
        else
            [self.reader selectTabAtIndex:i];
        return;
    }
}

@end

@implementation SPDFPaletteSearchField

- (void)keyDown:(NSEvent*)event {
    if (event.keyCode == 53) {
        [self.reader closePalette:self];
        return;
    }
    if (event.keyCode == 125) {
        [self.reader paletteMoveSelection:1];
        return;
    }
    if (event.keyCode == 126) {
        [self.reader paletteMoveSelection:-1];
        return;
    }
    if (event.keyCode == 36 || event.keyCode == 76) {
        [self.reader activatePaletteSelection:self];
        return;
    }
    [super keyDown:event];
}

@end

@implementation SPDFDropView

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    (void)sender;
    return NSDragOperationCopy;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    return [self.reader openFilesFromPasteboard:sender.draggingPasteboard];
}

@end

@implementation SPDFScrollView {
    CGFloat _wheelAccumulator;
}

- (void)scrollWheel:(NSEvent*)event {
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
    if (self.reader) [self.reader documentScrollPositionChanged];
}

- (void)magnifyWithEvent:(NSEvent*)event {
    if (self.reader)
        [self.reader beginLiveZoomByFactor:1.0 + event.magnification * 0.82
                     centeredAtWindowPoint:event.locationInWindow];
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
    NSTimer* _inertiaTimer;
    NSInteger _selectionPageIndex;
    NSPoint _selectionStart;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)setPages:(NSArray<SPDFRenderedPage*>*)pages {
    _pages = [pages copy];
    [self setNeedsDisplay:YES];
}

- (CGFloat)widestPage {
    CGFloat widest = 0;
    for (SPDFRenderedPage* page in self.pages) widest = MAX(widest, page.pageWidth * self.zoom);
    return widest;
}

- (NSSize)documentSizeForClipSize:(NSSize)clipSize {
    CGFloat width = MAX(clipSize.width, [self widestPage] + kPageMargin);
    CGFloat height = kPageMargin;

    if (self.pages.count == 0) return NSMakeSize(MAX(clipSize.width, 600), MAX(clipSize.height, 500));

    if (self.viewMode == SPDFViewModeSingle) {
        NSInteger index = MAX(0, MIN(self.currentPageIndex, (NSInteger)self.pages.count - 1));
        SPDFRenderedPage* page = self.pages[(NSUInteger)index];
        CGFloat pageHeight = page.pageHeight * self.zoom;
        height = pageHeight + kPageMargin;
    } else {
        height = kPageMargin / 2.0;
        for (SPDFRenderedPage* page in self.pages) {
            CGFloat pageHeight = page.pageHeight * self.zoom;
            height += pageHeight + kPageGap;
        }
        height += kPageMargin / 2.0;
    }

    return NSMakeSize(width, MAX(height, clipSize.height));
}

- (NSRect)rectForPageAtIndex:(NSInteger)pageIndex {
    if (pageIndex < 0 || pageIndex >= (NSInteger)self.pages.count) return NSZeroRect;

    CGFloat y = kPageMargin / 2.0;
    if (self.viewMode == SPDFViewModeSingle) {
        pageIndex = MAX(0, MIN(self.currentPageIndex, (NSInteger)self.pages.count - 1));
    } else {
        for (NSInteger i = 0; i < pageIndex; ++i) {
            SPDFRenderedPage* prev = self.pages[(NSUInteger)i];
            y += prev.pageHeight * self.zoom + kPageGap;
        }
    }

    SPDFRenderedPage* page = self.pages[(NSUInteger)pageIndex];
    CGFloat width = page.pageWidth * self.zoom;
    CGFloat height = page.pageHeight * self.zoom;
    CGFloat x = floor((NSWidth(self.bounds) - width) / 2.0);
    return NSMakeRect(MAX(kPageMargin / 2.0, x), y, width, height);
}

- (NSInteger)pageIndexForVisibleRect:(NSRect)visibleRect {
    if (self.pages.count == 0) return 0;
    if (self.viewMode == SPDFViewModeSingle) return self.currentPageIndex;

    NSInteger bestPage = self.currentPageIndex;
    CGFloat bestOverlap = -1;
    for (SPDFRenderedPage* page in self.pages) {
        NSRect pageRect = [self rectForPageAtIndex:page.pageIndex];
        CGFloat overlap = NSHeight(NSIntersectionRect(visibleRect, pageRect));
        if (overlap > bestOverlap) {
            bestOverlap = overlap;
            bestPage = page.pageIndex;
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
    [shadow set];
    [[NSColor whiteColor] setFill];
    NSRectFill(pageRect);
    [NSGraphicsContext restoreGraphicsState];

    if (page.image)
        [page.image drawInRect:pageRect
                      fromRect:NSZeroRect
                     operation:NSCompositingOperationSourceOver
                      fraction:1.0
                respectFlipped:YES
                         hints:@{NSImageHintInterpolation : @(NSImageInterpolationHigh)}];

    if (page.highlights.count > 0 && self.zoom > 0) {
        [[NSColor colorWithCalibratedRed:1.0 green:0.84 blue:0.12 alpha:0.38] setFill];
        for (NSValue* value in page.highlights) {
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
        for (NSValue* value in page.selectionRects) {
            NSRect r = [value rectValue];
            r.origin.x = pageRect.origin.x + r.origin.x * self.zoom;
            r.origin.y = pageRect.origin.y + r.origin.y * self.zoom;
            r.size.width *= self.zoom;
            r.size.height *= self.zoom;
            NSRectFillUsingOperation(r, NSCompositingOperationSourceOver);
        }
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [NSColor.windowBackgroundColor setFill];
    NSRectFill(self.bounds);

    if (self.pages.count == 0) {
        NSDictionary* attrs = @{
            NSForegroundColorAttributeName : [NSColor secondaryLabelColor],
            NSFontAttributeName : [NSFont systemFontOfSize:16 weight:NSFontWeightMedium]
        };
        NSString* message = @"Open a document";
        NSSize size = [message sizeWithAttributes:attrs];
        [message drawAtPoint:NSMakePoint((NSWidth(self.bounds) - size.width) / 2.0, 72.0) withAttributes:attrs];
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
                *pagePoint =
                    NSMakePoint((point.x - pageRect.origin.x) / self.zoom, (point.y - pageRect.origin.y) / self.zoom);
            return YES;
        }
        return NO;
    }

    for (SPDFRenderedPage* page in self.pages) {
        NSRect pageRect = [self rectForPageAtIndex:page.pageIndex];
        if (NSPointInRect(point, pageRect)) {
            if (pageIndex) *pageIndex = page.pageIndex;
            if (pagePoint)
                *pagePoint =
                    NSMakePoint((point.x - pageRect.origin.x) / self.zoom, (point.y - pageRect.origin.y) / self.zoom);
            return YES;
        }
    }
    return NO;
}

- (void)mouseDown:(NSEvent*)event {
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

- (void)mouseDragged:(NSEvent*)event {
    if (!_isSelecting) {
        [super mouseDragged:event];
        return;
    }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect pageRect = [self rectForPageAtIndex:_selectionPageIndex];
    if (NSIsEmptyRect(pageRect)) return;
    NSPoint pagePoint =
        NSMakePoint((point.x - pageRect.origin.x) / self.zoom, (point.y - pageRect.origin.y) / self.zoom);
    [self.reader documentViewSelectionChangedOnPage:_selectionPageIndex from:_selectionStart to:pagePoint];
}

- (void)mouseUp:(NSEvent*)event {
    (void)event;
    _isSelecting = NO;
}

- (void)beginPanWithEvent:(NSEvent*)event {
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
}

- (void)stepPanInertia:(NSTimer*)timer {
    NSScrollView* scrollView = self.enclosingScrollView;
    NSClipView* clipView = scrollView.contentView;
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
}

- (void)rightMouseDown:(NSEvent*)event {
    _rightMouseMoved = NO;
    if (event.modifierFlags & NSEventModifierFlagCommand) return;
    [self beginPanWithEvent:event];
}

- (void)rightMouseDragged:(NSEvent*)event {
    _rightMouseMoved = YES;
    if (_isPanning) [self continuePanWithEvent:event];
}

- (void)rightMouseUp:(NSEvent*)event {
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

@implementation SPDFMinimapView {
    BOOL _draggingVisibleRect;
    NSPoint _dragOffsetFromVisibleCenter;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)setPages:(NSArray<SPDFRenderedPage*>*)pages {
    _pages = [pages copy];
    [self setNeedsDisplay:YES];
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

- (NSRect)miniRectForPage:(SPDFRenderedPage*)targetPage scale:(CGFloat)scale gap:(CGFloat)gap {
    CGFloat y = 0;
    for (SPDFRenderedPage* page in self.pages) {
        CGFloat pageWidth = MAX(1.0, page.pageWidth * scale);
        CGFloat pageHeight = MAX(1.0, page.pageHeight * scale);
        if (page == targetPage || page.pageIndex == targetPage.pageIndex) {
            return NSMakeRect(floor((NSWidth(self.bounds) - pageWidth) / 2.0), y, pageWidth, pageHeight);
        }
        y += pageHeight + gap;
    }
    return NSZeroRect;
}

- (NSRect)documentRectForPage:(SPDFRenderedPage*)targetPage {
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

    CGFloat y = contentTop;
    BOOL drawImages = self.pages.count <= 400;
    for (SPDFRenderedPage* page in self.pages) {
        CGFloat pageWidth = page.pageWidth * scale;
        CGFloat pageHeight = MAX(1.0, page.pageHeight * scale);
        NSRect pageRect = NSMakeRect(floor((NSWidth(self.bounds) - pageWidth) / 2.0), y, pageWidth, pageHeight);
        if (NSHeight(pageRect) >= 1.0 && NSIntersectsRect(pageRect, self.bounds)) {
            [[NSColor whiteColor] setFill];
            NSRectFillUsingOperation(pageRect, NSCompositingOperationSourceOver);
            if (drawImages && page.image && NSHeight(pageRect) >= 5.0) {
                [page.image drawInRect:pageRect
                              fromRect:NSZeroRect
                             operation:NSCompositingOperationSourceOver
                              fraction:1.0
                        respectFlipped:YES
                                 hints:@{NSImageHintInterpolation : @(NSImageInterpolationLow)}];
            } else {
                [self drawPlaceholderInRect:pageRect];
            }
            [self drawRects:page.highlights
                   pageRect:pageRect
                      scale:scale
                      color:[NSColor colorWithCalibratedRed:1.0 green:0.78 blue:0.05 alpha:0.78]
                  minHeight:1.3];
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

- (void)sendScrollRequestForEvent:(NSEvent*)event {
    CGFloat scale = 1.0;
    CGFloat gap = 4.0;
    CGFloat contentTop = 8.0;
    CGFloat contentHeight = 0;
    if (![self layoutScale:&scale gap:&gap contentTop:&contentTop contentHeight:&contentHeight visibleRect:NULL])
        return;

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (_draggingVisibleRect)
        point = NSMakePoint(point.x - _dragOffsetFromVisibleCenter.x, point.y - _dragOffsetFromVisibleCenter.y);
    NSPoint documentPoint = [self documentPointForMinimapCenterPoint:point
                                                               scale:scale
                                                                 gap:gap
                                                       contentHeight:contentHeight
                                                          contentTop:contentTop];
    [self.reader minimapViewDidRequestCenterAtDocumentPoint:documentPoint];
}

- (void)mouseDown:(NSEvent*)event {
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
    _draggingVisibleRect = NSPointInRect(point, visibleRect);
    _dragOffsetFromVisibleCenter =
        _draggingVisibleRect ? NSMakePoint(point.x - NSMidX(visibleRect), point.y - NSMidY(visibleRect)) : NSZeroPoint;
    if (!_draggingVisibleRect) [self sendScrollRequestForEvent:event];
}

- (void)mouseDragged:(NSEvent*)event {
    [self sendScrollRequestForEvent:event];
}

- (void)mouseUp:(NSEvent*)event {
    (void)event;
    _draggingVisibleRect = NO;
    _dragOffsetFromVisibleCenter = NSZeroPoint;
}

@end

@interface SPDFPrintView : NSView
@property(nonatomic, copy) NSArray<SPDFRenderedPage*>* pages;
@end

@implementation SPDFPrintView

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)knowsPageRange:(NSRangePointer)range {
    range->location = 1;
    range->length = self.pages.count;
    return YES;
}

- (NSRect)rectForPage:(NSInteger)page {
    NSPrintInfo* info = NSPrintOperation.currentOperation.printInfo;
    NSSize paper = info.paperSize;
    return NSMakeRect(0, (page - 1) * paper.height, paper.width, paper.height);
}

- (void)drawRect:(NSRect)dirtyRect {
    NSPrintInfo* info = NSPrintOperation.currentOperation.printInfo;
    NSSize paper = info.paperSize;
    NSInteger pageNumber = MAX(1, (NSInteger)floor(dirtyRect.origin.y / paper.height) + 1);
    NSInteger pageIndex = pageNumber - 1;
    if (pageIndex < 0 || pageIndex >= (NSInteger)self.pages.count) return;

    NSRect pageRect = [self rectForPage:pageNumber];
    [[NSColor whiteColor] setFill];
    NSRectFill(pageRect);

    SPDFRenderedPage* page = self.pages[(NSUInteger)pageIndex];
    if (!page.image) return;

    NSRect imageable = info.imageablePageBounds;
    imageable.origin.x += pageRect.origin.x;
    imageable.origin.y += pageRect.origin.y;
    CGFloat scale = MIN(NSWidth(imageable) / page.image.size.width, NSHeight(imageable) / page.image.size.height);
    NSSize drawSize = NSMakeSize(page.image.size.width * scale, page.image.size.height * scale);
    NSRect drawRect =
        NSMakeRect(imageable.origin.x + (NSWidth(imageable) - drawSize.width) / 2.0,
                   imageable.origin.y + (NSHeight(imageable) - drawSize.height) / 2.0, drawSize.width, drawSize.height);
    [page.image drawInRect:drawRect
                  fromRect:NSZeroRect
                 operation:NSCompositingOperationSourceOver
                  fraction:1.0
            respectFlipped:YES
                     hints:@{NSImageHintInterpolation : @(NSImageInterpolationHigh)}];
}

@end

@implementation SumatraMacDelegate {
    NSWindow* _window;
    SPDFTabStripView* _tabStrip;
    NSSplitView* _splitView;
    NSTableView* _sidebarTable;
    NSView* _sidebarContainer;
    NSView* _documentContainer;
    SPDFScrollView* _pageScrollView;
    SPDFDocumentView* _pageView;
    SPDFMinimapView* _minimapView;
    NSLayoutConstraint* _minimapWidthConstraint;
    NSButton* _prevButton;
    NSButton* _nextButton;
    NSTextField* _pageField;
    NSTextField* _pageCountLabel;
    NSButton* _zoomOutButton;
    NSButton* _zoomInButton;
    NSPopUpButton* _fitModePopup;
    NSButton* _continuousButton;
    NSSearchField* _searchField;
    NSButton* _ocrButton;
    NSButton* _findPrevButton;
    NSButton* _findNextButton;
    NSTextField* _findCountLabel;
    NSTextField* _statusLabel;
    NSSegmentedControl* _sidebarModeControl;
    NSPanel* _palettePanel;
    NSSearchField* _paletteSearchField;
    NSButton* _paletteAllDocsCheckbox;
    NSTableView* _paletteTable;
    NSPanel* _ocrInstallPanel;
    NSProgressIndicator* _ocrInstallProgress;
    NSTextView* _ocrInstallLog;
    NSTask* _ocrInstallTask;
    NSMutableArray<NSDictionary*>* _paletteResults;
    NSInteger _paletteMode;
    NSUInteger _paletteSearchGeneration;
    id _paletteEventMonitor;
    NSOperationQueue* _renderQueue;
    NSOperationQueue* _preloadQueue;
    NSOperationQueue* _findQueue;

    spdf_document* _doc;
    spdf_outline _outline;
    spdf_comments _comments;
    NSMutableArray<NSDictionary*>* _sidebarItems;
    NSMutableArray<SPDFRenderedPage*>* _renderedPages;
    NSMutableArray<SPDFDocumentTab*>* _tabs;
    NSMutableArray<NSDictionary*>* _favorites;
    NSMutableDictionary<NSNumber*, NSArray<NSValue*>*>* _findHighlights;
    NSMutableArray<NSDictionary*>* _findMatches;
    NSUInteger _findGeneration;
    BOOL _findSearchInProgress;
    NSString* _path;
    NSString* _pendingOpenPath;
    NSMutableArray<NSString*>* _pendingOpenPaths;
    NSInteger _pageIndex;
    NSInteger _highlightPageIndex;
    NSInteger _findMatchIndex;
    NSInteger _selectionPageIndex;
    NSString* _selectedText;
    CGFloat _zoom;
    SPDFFitMode _fitMode;
    SPDFViewMode _viewMode;
    NSInteger _selectedTabIndex;
    NSUInteger _renderGeneration;
    NSTimer* _zoomFinishTimer;
    BOOL _uiReady;
    BOOL _updatingSelection;
    BOOL _updatingFromScroll;
    BOOL _suppressScrollCallbacks;
    BOOL _sidebarPreferredVisible;
    BOOL _sidebarVisible;
    BOOL _ocrInstallRunning;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    (void)notification;
    _zoom = 1.0;
    _fitMode = SPDFFitModeWidth;
    _viewMode = SPDFViewModeContinuous;
    _highlightPageIndex = -1;
    _selectionPageIndex = -1;
    _sidebarPreferredVisible = YES;
    _sidebarVisible = YES;
    _sidebarItems = [NSMutableArray array];
    _renderedPages = [NSMutableArray array];
    _tabs = [NSMutableArray array];
    _favorites = [NSMutableArray array];
    _findHighlights = [NSMutableDictionary dictionary];
    _findMatches = [NSMutableArray array];
    _findMatchIndex = -1;
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
    _findQueue = [[NSOperationQueue alloc] init];
    _findQueue.name = @"SumatraPDF document find";
    _findQueue.maxConcurrentOperationCount = 1;
    _findQueue.qualityOfService = NSQualityOfServiceUserInitiated;

    [self loadPersistentState];

    [self buildMenu];
    [self buildWindow];
    _uiReady = YES;
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    NSMutableArray<NSString*>* startupPaths = [NSMutableArray array];
    if (_pendingOpenPath.length > 0) [startupPaths addObject:_pendingOpenPath];
    for (NSString* path in _pendingOpenPaths) {
        if (path.length > 0 && ![startupPaths containsObject:path]) [startupPaths addObject:path];
    }
    if (self.initialPath.length > 0) [startupPaths addObject:self.initialPath];
    if (startupPaths.count > 0) {
        for (NSString* path in startupPaths) [self openPath:path];
    } else if (_tabs.count > 0) {
        [self selectTabAtIndex:MAX(0, _selectedTabIndex)];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
    (void)sender;
    return YES;
}

- (void)applicationWillTerminate:(NSNotification*)notification {
    (void)notification;
    [_renderQueue cancelAllOperations];
    [_preloadQueue cancelAllOperations];
    [_findQueue cancelAllOperations];
    [self rememberActiveTabState];
    [self savePersistentState];
    spdf_free_outline(&_outline);
    spdf_free_comments(&_comments);
    spdf_close(_doc);
}

- (BOOL)application:(NSApplication*)sender openFile:(NSString*)filename {
    (void)sender;
    if (!_uiReady) {
        if (!_pendingOpenPath.length) _pendingOpenPath = [filename copy];
        if (filename.length && ![_pendingOpenPaths containsObject:filename]) [_pendingOpenPaths addObject:filename];
        return YES;
    }
    [self openPath:filename];
    return YES;
}

- (void)application:(NSApplication*)application openFiles:(NSArray<NSString*>*)filenames {
    (void)application;
    if (filenames.count > 0) {
        if (!_uiReady) {
            _pendingOpenPath = [filenames.firstObject copy];
            [_pendingOpenPaths addObjectsFromArray:filenames];
        } else {
            for (NSString* filename in filenames) [self openPath:filename];
        }
    }
    [NSApp replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

- (void)windowDidResize:(NSNotification*)notification {
    (void)notification;
    [self updateTabStripFrame];
    if (_doc && (_fitMode == SPDFFitModeWidth || _fitMode == SPDFFitModeHeight || _fitMode == SPDFFitModePage))
        [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO];
    else
        [self resizeDocumentView];
}

- (void)windowDidEnterFullScreen:(NSNotification*)notification {
    (void)notification;
    dispatch_async(dispatch_get_main_queue(), ^{
      [self updateTabStripFrame];
    });
}

- (void)windowDidExitFullScreen:(NSNotification*)notification {
    (void)notification;
    dispatch_async(dispatch_get_main_queue(), ^{
      [self updateTabStripFrame];
    });
}

- (NSString*)supportDirectory {
    NSURL* base = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                       inDomains:NSUserDomainMask]
                      .firstObject;
    NSString* dir = [base.path stringByAppendingPathComponent:@"SumatraPDF"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (NSString*)pathForStateFile:(NSString*)name {
    return [[self supportDirectory] stringByAppendingPathComponent:name];
}

- (id)jsonObjectFromFile:(NSString*)name {
    NSData* data = [NSData dataWithContentsOfFile:[self pathForStateFile:name]];
    if (!data) return nil;
    return [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
}

- (void)writeJSONObject:(id)object toFile:(NSString*)name {
    NSData* data = [NSJSONSerialization dataWithJSONObject:object
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:nil];
    if (data) [data writeToFile:[self pathForStateFile:name] atomically:YES];
}

- (void)loadPersistentState {
    NSDictionary* settings = [self jsonObjectFromFile:@"settings.json"];
    if ([settings isKindOfClass:NSDictionary.class]) {
        NSNumber* fit = settings[@"fitMode"];
        NSNumber* view = settings[@"viewMode"];
        NSNumber* sidebar = settings[@"showSidebar"];
        if (fit) _fitMode = (SPDFFitMode)MAX(0, MIN(4, fit.integerValue));
        if (view) _viewMode = (SPDFViewMode)MAX(0, MIN(1, view.integerValue));
        if (sidebar) _sidebarPreferredVisible = sidebar.boolValue;
    }

    NSArray* favorites = [self jsonObjectFromFile:@"favorites.json"];
    if ([favorites isKindOfClass:NSArray.class]) [_favorites addObjectsFromArray:favorites];

    NSDictionary* session = [self jsonObjectFromFile:@"session.json"];
    NSArray* tabs = [session isKindOfClass:NSDictionary.class] ? session[@"tabs"] : nil;
    if ([tabs isKindOfClass:NSArray.class]) {
        for (NSDictionary* item in tabs) {
            if (![item isKindOfClass:NSDictionary.class]) continue;
            NSString* path = item[@"path"];
            if (![path isKindOfClass:NSString.class] || path.length == 0) continue;
            SPDFDocumentTab* tab = [[SPDFDocumentTab alloc] init];
            tab.path = path;
            tab.title = spdf_display_name_for_path(path);
            tab.pageIndex = [item[@"page"] integerValue];
            tab.zoom = [item[@"zoom"] doubleValue] > 0 ? [item[@"zoom"] doubleValue] : 1.0;
            tab.fitMode = (SPDFFitMode)MAX(0, MIN(4, [item[@"fitMode"] integerValue]));
            tab.viewMode = (SPDFViewMode)MAX(0, MIN(1, [item[@"viewMode"] integerValue]));
            tab.scrollOrigin = NSMakePoint([item[@"scrollX"] doubleValue], [item[@"scrollY"] doubleValue]);
            tab.hasScrollOrigin = item[@"scrollX"] != nil || item[@"scrollY"] != nil;
            [_tabs addObject:tab];
        }
        _selectedTabIndex = MIN(MAX(0, [session[@"selectedTab"] integerValue]), MAX(0, (NSInteger)_tabs.count - 1));
    }
}

- (void)savePersistentState {
    NSMutableArray* tabs = [NSMutableArray array];
    for (SPDFDocumentTab* tab in _tabs) {
        if (!tab.path.length) continue;
        [tabs addObject:@{
            @"path" : tab.path,
            @"title" : spdf_display_name_for_path(tab.path),
            @"page" : @(tab.pageIndex),
            @"zoom" : @(tab.zoom),
            @"fitMode" : @(tab.fitMode),
            @"viewMode" : @(tab.viewMode),
            @"scrollX" : @(tab.scrollOrigin.x),
            @"scrollY" : @(tab.scrollOrigin.y),
            @"hasScrollOrigin" : @(tab.hasScrollOrigin)
        }];
    }
    [self writeJSONObject:@{@"version" : @1, @"selectedTab" : @(MAX(0, _selectedTabIndex)), @"tabs" : tabs}
                   toFile:@"session.json"];
    [self writeJSONObject:@{
        @"version" : @1,
        @"fitMode" : @(_fitMode),
        @"viewMode" : @(_viewMode),
        @"showSidebar" : @(_sidebarPreferredVisible)
    }
                   toFile:@"settings.json"];
    [self writeJSONObject:_favorites toFile:@"favorites.json"];
}

- (void)buildMenu {
    NSMenu* mainMenu = [[NSMenu alloc] initWithTitle:@""];

    NSMenuItem* appItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    [mainMenu addItem:appItem];
    NSMenu* appMenu = [[NSMenu alloc] initWithTitle:@"SumatraPDF"];
    [appMenu addItemWithTitle:@"About SumatraPDF" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit SumatraPDF" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;

    NSMenuItem* fileItem = [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
    [mainMenu addItem:fileItem];
    NSMenu* fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"Open..." action:@selector(openDocument:) keyEquivalent:@"o"];
    [fileMenu addItemWithTitle:@"Open in Adobe Acrobat Reader"
                        action:@selector(openInExternalReader:)
                 keyEquivalent:@""];
    [fileMenu addItemWithTitle:@"Show in Folder" action:@selector(showInFolder:) keyEquivalent:@""];
    [fileMenu addItemWithTitle:@"Close" action:@selector(closeDocument:) keyEquivalent:@"w"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Print..." action:@selector(printDocument:) keyEquivalent:@"p"];
    [fileMenu addItemWithTitle:@"OCR Document..." action:@selector(ocrDocument:) keyEquivalent:@""];
    [fileMenu addItemWithTitle:@"Properties..." action:@selector(showProperties:) keyEquivalent:@""];
    fileItem.submenu = fileMenu;

    NSMenuItem* goItem = [[NSMenuItem alloc] initWithTitle:@"Go To" action:nil keyEquivalent:@""];
    [mainMenu addItem:goItem];
    NSMenu* goMenu = [[NSMenu alloc] initWithTitle:@"Go To"];
    [goMenu addItemWithTitle:@"First Page"
                      action:@selector(firstPage:)
               keyEquivalent:[NSString stringWithFormat:@"%C", static_cast<unichar>(NSHomeFunctionKey)]];
    [goMenu addItemWithTitle:@"Previous Page" action:@selector(previousPage:) keyEquivalent:@"["];
    [goMenu addItemWithTitle:@"Next Page" action:@selector(nextPage:) keyEquivalent:@"]"];
    [goMenu addItemWithTitle:@"Last Page"
                      action:@selector(lastPage:)
               keyEquivalent:[NSString stringWithFormat:@"%C", static_cast<unichar>(NSEndFunctionKey)]];
    [goMenu addItem:[NSMenuItem separatorItem]];
    [goMenu addItemWithTitle:@"Go To Page..." action:@selector(focusPageField:) keyEquivalent:@"l"];
    goItem.submenu = goMenu;

    NSMenuItem* zoomItem = [[NSMenuItem alloc] initWithTitle:@"Zoom" action:nil keyEquivalent:@""];
    [mainMenu addItem:zoomItem];
    NSMenu* zoomMenu = [[NSMenu alloc] initWithTitle:@"Zoom"];
    [zoomMenu addItemWithTitle:@"Zoom In" action:@selector(zoomIn:) keyEquivalent:@"+"];
    [zoomMenu addItemWithTitle:@"Zoom Out" action:@selector(zoomOut:) keyEquivalent:@"-"];
    [zoomMenu addItemWithTitle:@"Actual Size" action:@selector(actualSize:) keyEquivalent:@"0"];
    [zoomMenu addItem:[NSMenuItem separatorItem]];
    [zoomMenu addItemWithTitle:@"Fit Page" action:@selector(fitPage:) keyEquivalent:@"9"];
    [zoomMenu addItemWithTitle:@"Fit Width" action:@selector(fitWidth:) keyEquivalent:@"1"];
    [zoomMenu addItemWithTitle:@"Fit Height" action:@selector(fitHeight:) keyEquivalent:@"2"];
    zoomItem.submenu = zoomMenu;

    NSMenuItem* viewItem = [[NSMenuItem alloc] initWithTitle:@"View" action:nil keyEquivalent:@""];
    [mainMenu addItem:viewItem];
    NSMenu* viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    [viewMenu addItemWithTitle:@"Single Page" action:@selector(setSinglePageMode:) keyEquivalent:@"4"];
    [viewMenu addItemWithTitle:@"Continuous" action:@selector(setContinuousMode:) keyEquivalent:@"5"];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"Show Sidebar" action:@selector(toggleSidebar:) keyEquivalent:@""];
    NSMenuItem* fullScreen = [viewMenu addItemWithTitle:@"Full Screen"
                                                 action:@selector(toggleFullScreen:)
                                          keyEquivalent:@"f"];
    fullScreen.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"Rotate Left" action:@selector(unimplementedMenuItem:) keyEquivalent:@""];
    [viewMenu addItemWithTitle:@"Rotate Right" action:@selector(unimplementedMenuItem:) keyEquivalent:@""];
    viewItem.submenu = viewMenu;

    NSMenuItem* editItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
    [mainMenu addItem:editItem];
    NSMenu* editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copySelection:) keyEquivalent:@"c"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Find" action:@selector(focusFind:) keyEquivalent:@"f"];
    [editMenu addItemWithTitle:@"Find Next" action:@selector(findNext:) keyEquivalent:@"g"];
    NSMenuItem* prevFind = [editMenu addItemWithTitle:@"Find Previous"
                                               action:@selector(findPrevious:)
                                        keyEquivalent:@"G"];
    prevFind.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    editItem.submenu = editMenu;

    NSMenuItem* favoritesItem = [[NSMenuItem alloc] initWithTitle:@"Favorites" action:nil keyEquivalent:@""];
    [mainMenu addItem:favoritesItem];
    NSMenu* favoritesMenu = [[NSMenu alloc] initWithTitle:@"Favorites"];
    [favoritesMenu addItemWithTitle:@"Search Favorites..." action:@selector(showFavoritesPalette:) keyEquivalent:@"k"];
    [favoritesMenu addItem:[NSMenuItem separatorItem]];
    [favoritesMenu addItemWithTitle:@"Favorite Current Page" action:@selector(favoriteCurrentPage:) keyEquivalent:@"b"];
    NSMenuItem* docFav = [favoritesMenu addItemWithTitle:@"Favorite Current Document"
                                                  action:@selector(favoriteCurrentDocument:)
                                           keyEquivalent:@"B"];
    docFav.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [favoritesMenu addItemWithTitle:@"Manage Favorites..." action:@selector(showFavoritesPalette:) keyEquivalent:@""];
    favoritesItem.submenu = favoritesMenu;

    NSMenuItem* settingsItem = [[NSMenuItem alloc] initWithTitle:@"Settings" action:nil keyEquivalent:@""];
    [mainMenu addItem:settingsItem];
    NSMenu* settingsMenu = [[NSMenu alloc] initWithTitle:@"Settings"];
    [settingsMenu addItemWithTitle:@"Options..." action:@selector(unimplementedMenuItem:) keyEquivalent:@","];
    [settingsMenu addItemWithTitle:@"Advanced Options..." action:@selector(unimplementedMenuItem:) keyEquivalent:@""];
    settingsItem.submenu = settingsMenu;

    NSApp.mainMenu = mainMenu;
}

- (NSButton*)buttonWithTitle:(NSString*)title action:(SEL)action {
    NSButton* button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(120, 80, 1120, 800);
    _window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                    NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.delegate = self;
    _window.title = @"SumatraPDF";
    _window.minSize = NSMakeSize(790, 540);
    _window.titleVisibility = NSWindowTitleHidden;
    _window.titlebarAppearsTransparent = YES;
    _window.styleMask |= NSWindowStyleMaskFullSizeContentView;

    SPDFDropView* content = [[SPDFDropView alloc] initWithFrame:frame];
    content.reader = self;
    [content registerForDraggedTypes:@[ NSPasteboardTypeFileURL ]];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    _window.contentView = content;

    _tabStrip = [[SPDFTabStripView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(frame), kTabStripHeight)];
    _tabStrip.reader = self;
    _tabStrip.tabs = _tabs;
    _tabStrip.selectedIndex = _selectedTabIndex;
    _tabStrip.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_tabStrip];
    [self updateTabStripFrame];

    NSStackView* toolbar = [[NSStackView alloc] init];
    toolbar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    toolbar.alignment = NSLayoutAttributeCenterY;
    toolbar.spacing = 6.0;
    toolbar.edgeInsets = NSEdgeInsetsMake(7, 8, 7, 8);
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:toolbar];

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
    [_fitModePopup addItemsWithTitles:@[ @"Custom", @"Actual", @"Fit Width", @"Fit Height", @"Fit Page" ]];
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
    _ocrButton = [self buttonWithTitle:@"OCR" action:@selector(ocrDocument:)];
    _findPrevButton = [self buttonWithTitle:@"<" action:@selector(findPrevious:)];
    _findNextButton = [self buttonWithTitle:@">" action:@selector(findNext:)];
    _findCountLabel = [NSTextField labelWithString:@""];
    _findCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _findCountLabel.alignment = NSTextAlignmentCenter;
    _findCountLabel.textColor = NSColor.secondaryLabelColor;
    _findCountLabel.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    [_findPrevButton.widthAnchor constraintEqualToConstant:30].active = YES;
    [_findNextButton.widthAnchor constraintEqualToConstant:30].active = YES;
    [_findCountLabel.widthAnchor constraintEqualToConstant:64].active = YES;

    [toolbar addArrangedSubview:_prevButton];
    [toolbar addArrangedSubview:_nextButton];
    [toolbar addArrangedSubview:_pageField];
    [toolbar addArrangedSubview:_pageCountLabel];
    [toolbar addArrangedSubview:_zoomOutButton];
    [toolbar addArrangedSubview:_zoomInButton];
    [toolbar addArrangedSubview:_fitModePopup];
    [toolbar addArrangedSubview:_continuousButton];
    [toolbar addArrangedSubview:_searchField];
    [toolbar addArrangedSubview:_ocrButton];
    [toolbar addArrangedSubview:_findCountLabel];
    [toolbar addArrangedSubview:_findPrevButton];
    [toolbar addArrangedSubview:_findNextButton];

    _splitView = [[NSSplitView alloc] init];
    _splitView.vertical = YES;
    _splitView.dividerStyle = NSSplitViewDividerStyleThin;
    _splitView.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_splitView];

    _sidebarContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 600)];
    _sidebarContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _sidebarModeControl = [[NSSegmentedControl alloc] init];
    _sidebarModeControl.segmentCount = 2;
    [_sidebarModeControl setLabel:@"Chapters" forSegment:SPDFSidebarModeChapters];
    [_sidebarModeControl setLabel:@"Comments" forSegment:SPDFSidebarModeComments];
    _sidebarModeControl.selectedSegment = SPDFSidebarModeChapters;
    _sidebarModeControl.target = self;
    _sidebarModeControl.action = @selector(sidebarModeChanged:);
    _sidebarModeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [_sidebarContainer addSubview:_sidebarModeControl];

    NSScrollView* sidebarScroll = [[NSScrollView alloc] init];
    sidebarScroll.hasVerticalScroller = YES;
    sidebarScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [_sidebarContainer addSubview:sidebarScroll];

    _sidebarTable = [[NSTableView alloc] init];
    _sidebarTable.headerView = nil;
    _sidebarTable.rowHeight = 25.0;
    _sidebarTable.dataSource = self;
    _sidebarTable.delegate = self;
    NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"title"];
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
    _pageScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _pageScrollView.hasVerticalScroller = YES;
    _pageScrollView.hasHorizontalScroller = YES;
    _pageScrollView.autohidesScrollers = NO;
    _pageScrollView.borderType = NSNoBorder;
    _pageScrollView.drawsBackground = YES;
    _pageScrollView.backgroundColor = NSColor.windowBackgroundColor;
    _pageScrollView.contentView.drawsBackground = YES;
    _pageScrollView.contentView.backgroundColor = NSColor.windowBackgroundColor;
    _pageScrollView.contentView.postsBoundsChangedNotifications = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(clipViewBoundsChanged:)
                                                 name:NSViewBoundsDidChangeNotification
                                               object:_pageScrollView.contentView];

    _pageView = [self newDocumentView];
    _pageScrollView.documentView = _pageView;

    _documentContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    _documentContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [_documentContainer addSubview:_pageScrollView];

    _minimapView = [[SPDFMinimapView alloc] init];
    _minimapView.translatesAutoresizingMaskIntoConstraints = NO;
    _minimapView.reader = self;
    _minimapView.wantsLayer = YES;
    [_documentContainer addSubview:_minimapView];
    _minimapWidthConstraint = [_minimapView.widthAnchor constraintEqualToConstant:kMinimapWidth];

    [NSLayoutConstraint activateConstraints:@[
        [_pageScrollView.topAnchor constraintEqualToAnchor:_documentContainer.topAnchor],
        [_pageScrollView.leadingAnchor constraintEqualToAnchor:_documentContainer.leadingAnchor],
        [_pageScrollView.bottomAnchor constraintEqualToAnchor:_documentContainer.bottomAnchor],
        [_pageScrollView.trailingAnchor constraintEqualToAnchor:_minimapView.leadingAnchor],
        [_minimapView.topAnchor constraintEqualToAnchor:_documentContainer.topAnchor],
        [_minimapView.trailingAnchor constraintEqualToAnchor:_documentContainer.trailingAnchor],
        [_minimapView.bottomAnchor constraintEqualToAnchor:_documentContainer.bottomAnchor], _minimapWidthConstraint
    ]];

    [_splitView addSubview:_sidebarContainer];
    [_splitView addSubview:_documentContainer];

    _statusLabel = [NSTextField labelWithString:@"Ready"];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [content addSubview:_statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_tabStrip.topAnchor constraintEqualToAnchor:content.topAnchor],
        [_tabStrip.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [_tabStrip.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [_tabStrip.heightAnchor constraintEqualToConstant:kTabStripHeight],
        [toolbar.topAnchor constraintEqualToAnchor:_tabStrip.bottomAnchor],
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
    if (!_sidebarPreferredVisible) [self setSidebarActuallyVisible:NO];
    [self syncToolbarState];
    [self updateControls];
}

- (CGFloat)backingScale {
    CGFloat scale = _window.backingScaleFactor;
    if (scale <= 0) scale = NSScreen.mainScreen.backingScaleFactor;
    return scale > 0 ? scale : 1.0;
}

- (CGFloat)zoomForFitMode:(SPDFFitMode)fitMode pageIndex:(NSInteger)pageIndex {
    if (!_doc) return _zoom;
    if (fitMode == SPDFFitModeCustom) return _zoom;
    if (fitMode == SPDFFitModeActual) return 1.0;

    char err[1024];
    float pageWidth = 0;
    float pageHeight = 0;
    if (!spdf_page_size(_doc, (int)pageIndex, &pageWidth, &pageHeight, err, sizeof(err)) || pageWidth <= 0 ||
        pageHeight <= 0)
        return _zoom;

    NSSize clipSize = _pageScrollView.contentView.bounds.size;
    CGFloat widthZoom = (clipSize.width - kPageMargin * 1.7) / pageWidth;
    CGFloat heightZoom = (clipSize.height - kPageMargin) / pageHeight;
    if (fitMode == SPDFFitModeWidth) return MAX(kMinZoom, MIN(kMaxZoom, widthZoom));
    if (fitMode == SPDFFitModeHeight) return MAX(kMinZoom, MIN(kMaxZoom, heightZoom));
    return MAX(kMinZoom, MIN(kMaxZoom, MIN(widthZoom, heightZoom)));
}

- (SPDFRenderedPage*)renderedPageAtIndex:(NSInteger)pageIndex
                                document:(spdf_document*)doc
                                    zoom:(CGFloat)zoom
                            displayScale:(CGFloat)displayScale
                                   error:(char*)err
                             errorLength:(size_t)errLen {
    float pageWidth = 0;
    float pageHeight = 0;
    if (!spdf_page_size(doc, (int)pageIndex, &pageWidth, &pageHeight, err, errLen)) return nil;

    spdf_bitmap bitmap;
    if (!spdf_render_page_rgba(doc, (int)pageIndex, (float)(zoom * displayScale), &bitmap, err, errLen)) return nil;

    NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
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
    NSImage* image = [[NSImage alloc] initWithSize:pointSize];
    [image addRepresentation:rep];

    SPDFRenderedPage* page = [[SPDFRenderedPage alloc] init];
    page.pageIndex = pageIndex;
    page.pageWidth = pageWidth;
    page.pageHeight = pageHeight;
    page.image = image;
    page.highlights = @[];
    page.selectionRects = @[];
    return page;
}

- (SPDFRenderedPage*)renderedPageAtIndex:(NSInteger)pageIndex error:(char*)err errorLength:(size_t)errLen {
    return [self renderedPageAtIndex:pageIndex
                            document:_doc
                                zoom:_zoom
                        displayScale:[self backingScale]
                               error:err
                         errorLength:errLen];
}

- (SPDFRenderedPage*)placeholderPageAtIndex:(NSInteger)pageIndex
                                   document:(spdf_document*)doc
                              fallbackWidth:(CGFloat)fallbackWidth
                             fallbackHeight:(CGFloat)fallbackHeight {
    CGFloat pageWidth = fallbackWidth;
    CGFloat pageHeight = fallbackHeight;
    if (doc) {
        char err[256];
        float nativeWidth = 0;
        float nativeHeight = 0;
        if (spdf_page_size(doc, (int)pageIndex, &nativeWidth, &nativeHeight, err, sizeof(err)) && nativeWidth > 0 &&
            nativeHeight > 0) {
            pageWidth = nativeWidth;
            pageHeight = nativeHeight;
        }
    }

    SPDFRenderedPage* page = [[SPDFRenderedPage alloc] init];
    page.pageIndex = pageIndex;
    page.pageWidth = pageWidth;
    page.pageHeight = pageHeight;
    page.highlights = @[];
    page.selectionRects = @[];
    return page;
}

- (spdf_document*)workerDocumentForPath:(NSString*)path error:(char*)err errorLength:(size_t)errLen {
    if (!path.length) return NULL;

    NSMutableDictionary* threadDictionary = NSThread.currentThread.threadDictionary;
    SPDFWorkerDocument* holder = threadDictionary[@"SumatraPDFWorkerDocument"];
    if (holder && [holder.path isEqualToString:path] && holder.document) return holder.document;

    holder = [[SPDFWorkerDocument alloc] init];
    holder.path = path;
    holder.document = spdf_open(path.fileSystemRepresentation, err, errLen);
    if (!holder.document) return NULL;
    threadDictionary[@"SumatraPDFWorkerDocument"] = holder;
    return holder.document;
}

- (NSArray<NSNumber*>*)pageRenderOrderForCount:(NSInteger)pageCount preferredPage:(NSInteger)preferredPage {
    NSMutableArray<NSNumber*>* order = [NSMutableArray arrayWithCapacity:(NSUInteger)MAX(0, pageCount - 1)];
    for (NSInteger distance = 1; distance < pageCount; ++distance) {
        NSInteger after = preferredPage + distance;
        NSInteger before = preferredPage - distance;
        if (after < pageCount) [order addObject:@(after)];
        if (before >= 0) [order addObject:@(before)];
    }
    return order;
}

- (NSOperationQueuePriority)queuePriorityForRenderDistance:(NSInteger)distance {
    if (distance <= 2) return NSOperationQueuePriorityVeryHigh;
    if (distance <= 6) return NSOperationQueuePriorityHigh;
    if (distance <= 18) return NSOperationQueuePriorityNormal;
    return NSOperationQueuePriorityLow;
}

- (void)enqueueRemainingPageRendersForGeneration:(NSUInteger)generation preferredPage:(NSInteger)preferredPage {
    if (!_doc || !_path.length) return;

    NSString* path = [_path copy];
    CGFloat zoom = _zoom;
    CGFloat displayScale = [self backingScale];
    NSArray<NSNumber*>* order = [self pageRenderOrderForCount:(NSInteger)_renderedPages.count
                                                preferredPage:preferredPage];
    for (NSNumber* number in order) {
        NSInteger index = number.integerValue;
        if (index < 0 || index >= (NSInteger)_renderedPages.count) continue;
        if (_renderedPages[(NSUInteger)index].image) continue;

        NSInteger distance = labs(index - preferredPage);
        NSBlockOperation* operation = [NSBlockOperation blockOperationWithBlock:^{
          @autoreleasepool {
              if (generation != self->_renderGeneration) return;
              char err[1024];
              spdf_document* workerDoc = [self workerDocumentForPath:path error:err errorLength:sizeof(err)];
              if (!workerDoc) return;
              SPDFRenderedPage* page = [self renderedPageAtIndex:index
                                                        document:workerDoc
                                                            zoom:zoom
                                                    displayScale:displayScale
                                                           error:err
                                                     errorLength:sizeof(err)];
              if (!page) return;

              [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                if (generation != self->_renderGeneration || !self->_doc ||
                    index >= (NSInteger)self->_renderedPages.count)
                    return;
                SPDFRenderedPage* old = self->_renderedPages[(NSUInteger)index];
                page.highlights = self->_findHighlights[@(index)] ?: old.highlights ?: @[];
                page.selectionRects = old.selectionRects ?: @[];
                BOOL geometryChanged =
                    fabs(old.pageWidth - page.pageWidth) > 0.01 || fabs(old.pageHeight - page.pageHeight) > 0.01;
                [self->_renderedPages replaceObjectAtIndex:(NSUInteger)index withObject:page];
                [self applySearchHighlightsToCurrentPage];
                if (geometryChanged)
                    [self resizeDocumentView];
                else {
                    self->_pageView.pages = self->_renderedPages;
                    [self->_pageView setNeedsDisplayInRect:[self->_pageView rectForPageAtIndex:index]];
                    [self updateMinimap];
                }
              }];
          }
        }];
        operation.queuePriority = [self queuePriorityForRenderDistance:distance];
        [_renderQueue addOperation:operation];
    }
}

- (void)renderPageIfNeededAtIndex:(NSInteger)pageIndex {
    if (!_doc || pageIndex < 0 || pageIndex >= (NSInteger)_renderedPages.count) return;
    SPDFRenderedPage* existing = _renderedPages[(NSUInteger)pageIndex];
    if (existing.image) return;

    char err[1024];
    SPDFRenderedPage* page = [self renderedPageAtIndex:pageIndex error:err errorLength:sizeof(err)];
    if (!page) {
        _statusLabel.stringValue = [NSString stringWithFormat:@"Could not render page %ld", (long)pageIndex + 1];
        return;
    }
    page.highlights = _findHighlights[@(pageIndex)] ?: existing.highlights ?: @[];
    page.selectionRects = existing.selectionRects ?: @[];
    [_renderedPages replaceObjectAtIndex:(NSUInteger)pageIndex withObject:page];
    _pageView.pages = _renderedPages;
    [self updateMinimap];
}

- (void)renderDocumentAndScrollToPage:(NSInteger)pageIndex alignTop:(BOOL)alignTop {
    [self renderDocumentAndScrollToPage:pageIndex alignTop:alignTop restoreOrigin:nil];
}

- (void)renderDocumentAndScrollToPage:(NSInteger)pageIndex
                             alignTop:(BOOL)alignTop
                        restoreOrigin:(NSValue*)restoreOrigin {
    if (!_doc || !_uiReady) return;

    [_window.contentView layoutSubtreeIfNeeded];
    [_renderQueue cancelAllOperations];
    _renderGeneration++;
    NSUInteger generation = _renderGeneration;
    _zoom = [self zoomForFitMode:_fitMode pageIndex:MAX(0, pageIndex)];
    NSMutableArray<SPDFRenderedPage*>* pages = [NSMutableArray arrayWithCapacity:(NSUInteger)spdf_page_count(_doc)];
    char err[1024];
    NSInteger pageCount = spdf_page_count(_doc);
    pageIndex = MAX(0, MIN(pageIndex, pageCount - 1));
    SPDFRenderedPage* preferredPage = [self renderedPageAtIndex:pageIndex error:err errorLength:sizeof(err)];
    if (!preferredPage) {
        [self showError:@"Could not render page" detail:[NSString stringWithUTF8String:err[0] ? err : "Unknown error"]];
        return;
    }
    for (NSInteger i = 0; i < pageCount; ++i) {
        SPDFRenderedPage* page = nil;
        if (i == pageIndex)
            page = preferredPage;
        else
            page = [self placeholderPageAtIndex:i
                                       document:_doc
                                  fallbackWidth:preferredPage.pageWidth
                                 fallbackHeight:preferredPage.pageHeight];
        if (!page) {
            [self showError:@"Could not render page"
                     detail:[NSString stringWithUTF8String:err[0] ? err : "Unknown error"]];
            return;
        }
        [pages addObject:page];
    }

    [NSAnimationContext
        runAnimationGroup:^(NSAnimationContext* context) {
          context.duration = 0.0;
          context.allowsImplicitAnimation = NO;
          self->_renderedPages = pages;
          self->_pageView.pages = self->_renderedPages;
          self->_pageView.currentPageIndex = self->_pageIndex;
          self->_pageView.zoom = self->_zoom;
          self->_pageView.viewMode = self->_viewMode;
          [self applySearchHighlightsToCurrentPage];
          [self resizeDocumentView];
          if (restoreOrigin)
              [self scrollDocumentClipViewToOrigin:restoreOrigin.pointValue notify:NO];
          else
              [self scrollToPage:pageIndex alignTop:alignTop];
        }
        completionHandler:nil];
    NSInteger renderCenterPage = pageIndex;
    if (restoreOrigin) {
        renderCenterPage = [_pageView pageIndexForVisibleRect:_pageScrollView.contentView.bounds];
        _pageIndex = renderCenterPage;
        _pageView.currentPageIndex = _pageIndex;
        [self renderPageIfNeededAtIndex:_pageIndex];
    }

    [self syncToolbarState];
    [self updateControls];
    [self selectCurrentSidebarRow];
    [self updateMinimap];

    [self enqueueRemainingPageRendersForGeneration:generation preferredPage:renderCenterPage];
}

- (void)resizeDocumentView {
    NSSize size = [_pageView documentSizeForClipSize:_pageScrollView.contentView.bounds.size];
    [_pageView setFrameSize:size];
    [_pageView setNeedsDisplay:YES];
    [self updateMinimap];
}

- (NSPoint)clampedDocumentScrollOrigin:(NSPoint)origin {
    NSClipView* clipView = _pageScrollView.contentView;
    origin.x = spdf_clamp_cg(origin.x, 0.0, MAX(0.0, NSWidth(_pageView.bounds) - NSWidth(clipView.bounds)));
    origin.y = spdf_clamp_cg(origin.y, 0.0, MAX(0.0, NSHeight(_pageView.bounds) - NSHeight(clipView.bounds)));
    return origin;
}

- (void)scrollDocumentClipViewToOrigin:(NSPoint)origin notify:(BOOL)notify {
    NSClipView* clipView = _pageScrollView.contentView;
    origin = [self clampedDocumentScrollOrigin:origin];
    _updatingFromScroll = YES;
    [NSAnimationContext
        runAnimationGroup:^(NSAnimationContext* context) {
          context.duration = 0.0;
          context.allowsImplicitAnimation = NO;
          [clipView setBoundsOrigin:origin];
          [self->_pageScrollView reflectScrolledClipView:clipView];
        }
        completionHandler:nil];
    _updatingFromScroll = NO;
    if (notify) {
        [self documentScrollPositionChanged];
        [self updateMinimap];
    }
}

- (void)scrollToPage:(NSInteger)pageIndex alignTop:(BOOL)alignTop {
    if (_renderedPages.count == 0) return;
    pageIndex = MAX(0, MIN(pageIndex, (NSInteger)_renderedPages.count - 1));
    NSRect pageRect = [_pageView rectForPageAtIndex:pageIndex];
    if (alignTop) {
        NSPoint point = NSMakePoint(MAX(0, pageRect.origin.x - 12), MAX(0, pageRect.origin.y - 12));
        [self scrollDocumentClipViewToOrigin:point notify:NO];
    } else {
        NSClipView* clipView = _pageScrollView.contentView;
        NSRect visible = clipView.bounds;
        NSPoint origin = visible.origin;
        if (NSMinX(pageRect) < NSMinX(visible))
            origin.x = NSMinX(pageRect) - 12.0;
        else if (NSMaxX(pageRect) > NSMaxX(visible))
            origin.x = NSMaxX(pageRect) - NSWidth(visible) + 12.0;
        if (NSMinY(pageRect) < NSMinY(visible))
            origin.y = NSMinY(pageRect) - 12.0;
        else if (NSMaxY(pageRect) > NSMaxY(visible))
            origin.y = NSMaxY(pageRect) - NSHeight(visible) + 12.0;
        [self scrollDocumentClipViewToOrigin:origin notify:NO];
    }
    [self documentScrollPositionChanged];
    [self updateMinimap];
}

- (NSPoint)relativeScrollPositionForPage:(NSInteger)pageIndex fromVisibleRect:(NSRect)visibleRect {
    if (_renderedPages.count == 0) return NSZeroPoint;
    pageIndex = MAX(0, MIN(pageIndex, (NSInteger)_renderedPages.count - 1));
    NSRect pageRect = [_pageView rectForPageAtIndex:pageIndex];
    if (NSIsEmptyRect(pageRect)) return NSZeroPoint;

    CGFloat maxX = MAX(1.0, NSWidth(pageRect) - NSWidth(visibleRect));
    CGFloat maxY = MAX(1.0, NSHeight(pageRect) - NSHeight(visibleRect));
    CGFloat relativeX = spdf_clamp_cg((NSMinX(visibleRect) - NSMinX(pageRect)) / maxX, 0.0, 1.0);
    CGFloat relativeY = spdf_clamp_cg((NSMinY(visibleRect) - NSMinY(pageRect)) / maxY, 0.0, 1.0);
    return NSMakePoint(relativeX, relativeY);
}

- (NSPoint)relativeScrollPositionForCurrentPage {
    return [self relativeScrollPositionForPage:_pageIndex fromVisibleRect:_pageScrollView.contentView.bounds];
}

- (void)scrollToPage:(NSInteger)pageIndex preservingRelativePosition:(NSPoint)relativePosition {
    if (_renderedPages.count == 0) return;
    pageIndex = MAX(0, MIN(pageIndex, (NSInteger)_renderedPages.count - 1));
    NSRect pageRect = [_pageView rectForPageAtIndex:pageIndex];
    if (NSIsEmptyRect(pageRect)) return;

    NSClipView* clipView = _pageScrollView.contentView;
    CGFloat maxInPageX = MAX(0.0, NSWidth(pageRect) - NSWidth(clipView.bounds));
    CGFloat maxInPageY = MAX(0.0, NSHeight(pageRect) - NSHeight(clipView.bounds));
    CGFloat maxDocumentX = MAX(0.0, NSWidth(_pageView.bounds) - NSWidth(clipView.bounds));
    CGFloat maxDocumentY = MAX(0.0, NSHeight(_pageView.bounds) - NSHeight(clipView.bounds));
    NSPoint origin = NSMakePoint(NSMinX(pageRect) + spdf_clamp_cg(relativePosition.x, 0.0, 1.0) * maxInPageX,
                                 NSMinY(pageRect) + spdf_clamp_cg(relativePosition.y, 0.0, 1.0) * maxInPageY);
    origin.x = spdf_clamp_cg(origin.x, 0.0, maxDocumentX);
    origin.y = spdf_clamp_cg(origin.y, 0.0, maxDocumentY);

    [self scrollDocumentClipViewToOrigin:origin notify:YES];
}

- (void)goToPage:(NSInteger)pageIndex preserveSinglePagePosition:(BOOL)preserveSinglePagePosition {
    if (!_doc) return;
    NSInteger pageCount = spdf_page_count(_doc);
    if (pageCount <= 0) return;
    pageIndex = MAX(0, MIN(pageIndex, pageCount - 1));
    NSPoint relativePosition = preserveSinglePagePosition ? [self relativeScrollPositionForCurrentPage] : NSZeroPoint;

    _pageIndex = pageIndex;
    _pageView.currentPageIndex = _pageIndex;
    [self renderPageIfNeededAtIndex:_pageIndex];
    [self resizeDocumentView];
    if (preserveSinglePagePosition)
        [self scrollToPage:_pageIndex preservingRelativePosition:relativePosition];
    else
        [self scrollToPage:_pageIndex alignTop:YES];
    [self updateControls];
    [self selectCurrentSidebarRow];
    [_pageView setNeedsDisplay:YES];
    [self persistActiveState];
}

- (CGFloat)continuousDocumentHeightForMinimap {
    if (_renderedPages.count == 0) return MAX(1.0, NSHeight(_pageView.bounds));

    CGFloat height = kPageMargin / 2.0;
    for (SPDFRenderedPage* page in _renderedPages) height += page.pageHeight * _zoom + kPageGap;
    height += kPageMargin / 2.0;
    return MAX(height, NSHeight(_pageScrollView.contentView.bounds));
}

- (NSRect)continuousDocumentRectForPageAtIndex:(NSInteger)pageIndex {
    if (pageIndex < 0 || pageIndex >= (NSInteger)_renderedPages.count) return NSZeroRect;

    CGFloat y = kPageMargin / 2.0;
    for (NSInteger i = 0; i < pageIndex; ++i) {
        SPDFRenderedPage* page = _renderedPages[(NSUInteger)i];
        y += page.pageHeight * _zoom + kPageGap;
    }

    SPDFRenderedPage* page = _renderedPages[(NSUInteger)pageIndex];
    CGFloat width = page.pageWidth * _zoom;
    CGFloat height = page.pageHeight * _zoom;
    CGFloat x = floor((NSWidth(_pageView.bounds) - width) / 2.0);
    return NSMakeRect(MAX(kPageMargin / 2.0, x), y, width, height);
}

- (NSRect)continuousDocumentVisibleRectForMinimap {
    NSRect visible = _pageScrollView.contentView.bounds;
    if (_viewMode == SPDFViewModeContinuous || _renderedPages.count == 0) return visible;

    NSRect singlePageRect = [_pageView rectForPageAtIndex:_pageIndex];
    NSRect continuousPageRect = [self continuousDocumentRectForPageAtIndex:_pageIndex];
    if (NSIsEmptyRect(singlePageRect) || NSIsEmptyRect(continuousPageRect)) return visible;

    NSRect projected = NSMakeRect(NSMinX(continuousPageRect) + (NSMinX(visible) - NSMinX(singlePageRect)),
                                  NSMinY(continuousPageRect) + (NSMinY(visible) - NSMinY(singlePageRect)),
                                  NSWidth(visible), NSHeight(visible));
    CGFloat maxX = MAX(0.0, NSWidth(_pageView.bounds) - NSWidth(projected));
    CGFloat maxY = MAX(0.0, [self continuousDocumentHeightForMinimap] - NSHeight(projected));
    projected.origin.x = spdf_clamp_cg(projected.origin.x, 0.0, maxX);
    projected.origin.y = spdf_clamp_cg(projected.origin.y, 0.0, maxY);
    return projected;
}

- (NSInteger)pageIndexForContinuousDocumentY:(CGFloat)y pageFraction:(CGFloat*)pageFraction {
    if (_renderedPages.count == 0) {
        if (pageFraction) *pageFraction = 0.0;
        return 0;
    }

    NSInteger closestPage = 0;
    CGFloat closestDistance = CGFLOAT_MAX;
    for (SPDFRenderedPage* page in _renderedPages) {
        NSRect pageRect = [self continuousDocumentRectForPageAtIndex:page.pageIndex];
        if (NSIsEmptyRect(pageRect)) continue;
        if (y >= NSMinY(pageRect) && y <= NSMaxY(pageRect)) {
            if (pageFraction)
                *pageFraction = spdf_clamp_cg((y - NSMinY(pageRect)) / MAX(1.0, NSHeight(pageRect)), 0.0, 1.0);
            return page.pageIndex;
        }

        CGFloat distance = MIN(fabs(y - NSMinY(pageRect)), fabs(y - NSMaxY(pageRect)));
        if (distance < closestDistance) {
            closestDistance = distance;
            closestPage = page.pageIndex;
            if (pageFraction) *pageFraction = y < NSMinY(pageRect) ? 0.0 : 1.0;
        }
    }
    return closestPage;
}

- (NSPoint)continuousDocumentPointForPage:(NSInteger)pageIndex
                          xFractionInPage:(CGFloat)xFraction
                          yFractionInPage:(CGFloat)yFraction {
    NSRect pageRect = [self continuousDocumentRectForPageAtIndex:pageIndex];
    if (NSIsEmptyRect(pageRect)) return NSZeroPoint;
    return NSMakePoint(NSMinX(pageRect) + spdf_clamp_cg(xFraction, 0.0, 1.0) * NSWidth(pageRect),
                       NSMinY(pageRect) + spdf_clamp_cg(yFraction, 0.0, 1.0) * NSHeight(pageRect));
}

- (void)scrollToPage:(NSInteger)pageIndex centeredAtPageXFraction:(CGFloat)xFraction yFraction:(CGFloat)yFraction {
    if (_renderedPages.count == 0) return;
    pageIndex = MAX(0, MIN(pageIndex, (NSInteger)_renderedPages.count - 1));
    xFraction = spdf_clamp_cg(xFraction, 0.0, 1.0);
    yFraction = spdf_clamp_cg(yFraction, 0.0, 1.0);

    NSRect pageRect = [_pageView rectForPageAtIndex:pageIndex];
    if (NSIsEmptyRect(pageRect)) return;

    NSClipView* clipView = _pageScrollView.contentView;
    CGFloat maxInPageX = MAX(0.0, NSWidth(pageRect) - NSWidth(clipView.bounds));
    CGFloat maxInPageY = MAX(0.0, NSHeight(pageRect) - NSHeight(clipView.bounds));
    CGFloat maxDocumentX = MAX(0.0, NSWidth(_pageView.bounds) - NSWidth(clipView.bounds));
    CGFloat maxDocumentY = MAX(0.0, NSHeight(_pageView.bounds) - NSHeight(clipView.bounds));
    NSPoint origin = NSMakePoint(NSMinX(pageRect) + NSWidth(pageRect) * xFraction - NSWidth(clipView.bounds) * 0.5,
                                 NSMinY(pageRect) + NSHeight(pageRect) * yFraction - NSHeight(clipView.bounds) * 0.5);
    origin.x = spdf_clamp_cg(origin.x, NSMinX(pageRect), NSMinX(pageRect) + maxInPageX);
    origin.x = spdf_clamp_cg(origin.x, 0.0, maxDocumentX);
    origin.y = spdf_clamp_cg(origin.y, NSMinY(pageRect), NSMinY(pageRect) + maxInPageY);
    origin.y = spdf_clamp_cg(origin.y, 0.0, maxDocumentY);

    [self scrollDocumentClipViewToOrigin:origin notify:YES];
}

- (void)updateMinimap {
    if (!_minimapView) return;
    _minimapView.pages = _renderedPages ?: @[];
    _minimapView.currentPageIndex = _pageIndex;
    _minimapView.viewMode = _viewMode;
    _minimapView.documentVisibleRect = [self continuousDocumentVisibleRectForMinimap];
    _minimapView.documentWidth = MAX(1.0, NSWidth(_pageView.bounds));
    _minimapView.documentHeight = MAX(1.0, [self continuousDocumentHeightForMinimap]);
    _minimapView.documentScale = MAX(0.01, _zoom);
    [_minimapView setNeedsDisplay:YES];
}

- (void)minimapViewDidRequestScrollToFraction:(CGFloat)yFraction {
    if (!_doc || _renderedPages.count == 0) return;
    yFraction = spdf_clamp_cg(yFraction, 0.0, 1.0);

    NSPoint documentPoint = NSMakePoint(NSMidX([self continuousDocumentVisibleRectForMinimap]),
                                        yFraction * [self continuousDocumentHeightForMinimap]);
    [self minimapViewDidRequestCenterAtDocumentPoint:documentPoint];
}

- (void)minimapViewDidRequestScrollToPage:(NSInteger)pageIndex yFractionInPage:(CGFloat)yFraction {
    [self minimapViewDidRequestCenterOnPage:pageIndex xFractionInPage:0.5 yFractionInPage:yFraction];
}

- (void)minimapViewDidRequestCenterAtDocumentPoint:(NSPoint)documentPoint {
    if (!_doc || _renderedPages.count == 0) return;

    if (_viewMode == SPDFViewModeContinuous) {
        NSClipView* clipView = _pageScrollView.contentView;
        NSPoint origin = NSMakePoint(documentPoint.x - NSWidth(clipView.bounds) * 0.5,
                                     documentPoint.y - NSHeight(clipView.bounds) * 0.5);
        CGFloat maxX = MAX(0.0, NSWidth(_pageView.bounds) - NSWidth(clipView.bounds));
        CGFloat maxY = MAX(0.0, NSHeight(_pageView.bounds) - NSHeight(clipView.bounds));
        origin.x = spdf_clamp_cg(origin.x, 0.0, maxX);
        origin.y = spdf_clamp_cg(origin.y, 0.0, maxY);

        [self scrollDocumentClipViewToOrigin:origin notify:YES];
        [self rememberActiveTabState];
        return;
    }

    CGFloat yFraction = 0.0;
    NSInteger pageIndex = [self pageIndexForContinuousDocumentY:documentPoint.y pageFraction:&yFraction];
    NSRect pageRect = [self continuousDocumentRectForPageAtIndex:pageIndex];
    CGFloat xFraction =
        NSIsEmptyRect(pageRect)
            ? 0.5
            : spdf_clamp_cg((documentPoint.x - NSMinX(pageRect)) / MAX(1.0, NSWidth(pageRect)), 0.0, 1.0);
    [self minimapViewDidRequestCenterOnPage:pageIndex xFractionInPage:xFraction yFractionInPage:yFraction];
}

- (void)minimapViewDidRequestCenterOnPage:(NSInteger)pageIndex
                          xFractionInPage:(CGFloat)xFraction
                          yFractionInPage:(CGFloat)yFraction {
    if (!_doc || pageIndex < 0 || pageIndex >= (NSInteger)_renderedPages.count) return;
    xFraction = spdf_clamp_cg(xFraction, 0.0, 1.0);
    yFraction = spdf_clamp_cg(yFraction, 0.0, 1.0);
    NSPoint documentPoint = [self continuousDocumentPointForPage:pageIndex
                                                 xFractionInPage:xFraction
                                                 yFractionInPage:yFraction];
    if (_viewMode == SPDFViewModeContinuous) {
        [self minimapViewDidRequestCenterAtDocumentPoint:documentPoint];
        return;
    }
    _pageIndex = pageIndex;
    _pageView.currentPageIndex = _pageIndex;
    [self renderPageIfNeededAtIndex:_pageIndex];
    [self resizeDocumentView];
    [self scrollToPage:_pageIndex centeredAtPageXFraction:xFraction yFraction:yFraction];
    [self updateControls];
    [self selectCurrentSidebarRow];
    [self updateMinimap];
    [self persistActiveState];
}

- (void)rememberActiveTabState {
    if (_selectedTabIndex < 0 || _selectedTabIndex >= (NSInteger)_tabs.count) return;
    if (!_doc || !_path.length) return;
    SPDFDocumentTab* tab = _tabs[(NSUInteger)_selectedTabIndex];
    tab.path = _path;
    tab.title = spdf_display_name_for_path(_path) ?: tab.title;
    tab.pageIndex = _pageIndex;
    tab.zoom = _zoom;
    tab.fitMode = _fitMode;
    tab.viewMode = _viewMode;
    tab.scrollOrigin = _pageScrollView.contentView.bounds.origin;
    tab.hasScrollOrigin = YES;
}

- (void)persistActiveState {
    [self rememberActiveTabState];
    [self savePersistentState];
}

- (NSInteger)indexOfTabForPath:(NSString*)path {
    NSString* standardized = path.stringByStandardizingPath;
    for (NSInteger i = 0; i < (NSInteger)_tabs.count; ++i) {
        NSString* tabPath = _tabs[(NSUInteger)i].path.stringByStandardizingPath;
        if ([tabPath isEqualToString:standardized]) return i;
    }
    return -1;
}

- (void)updateTabStrip {
    _tabStrip.tabs = _tabs;
    _tabStrip.selectedIndex = _selectedTabIndex;
    [self updateTabStripFrame];
}

- (void)updateTabStripFrame {
    if (!_tabStrip || !_window) return;
    BOOL fullScreen = (_window.styleMask & NSWindowStyleMaskFullScreen) == NSWindowStyleMaskFullScreen;
    CGFloat leadingInset = fullScreen ? 16.0 : 138.0;
    NSButton* zoomButton = fullScreen ? nil : [_window standardWindowButton:NSWindowZoomButton];
    if (zoomButton && _tabStrip.window) {
        NSRect buttonWindowRect = [zoomButton convertRect:zoomButton.bounds toView:nil];
        NSRect buttonRect = [_tabStrip convertRect:buttonWindowRect fromView:nil];
        if (NSMaxX(buttonRect) > 30.0 && NSMaxX(buttonRect) < NSWidth(_tabStrip.bounds) / 2.0)
            leadingInset = NSMaxX(buttonRect) + 18.0;
    }
    _tabStrip.reservedLeadingInset = leadingInset;
    [_tabStrip setNeedsDisplay:YES];
}

- (void)preloadInactiveTabs {
    [_preloadQueue cancelAllOperations];
    for (NSInteger i = 0; i < (NSInteger)_tabs.count; ++i) {
        if (i == _selectedTabIndex) continue;
        NSString* path = [_tabs[(NSUInteger)i].path copy];
        if (!path.length) continue;
        [_preloadQueue addOperationWithBlock:^{
          @autoreleasepool {
              char err[512];
              spdf_document* doc = spdf_open(path.fileSystemRepresentation, err, sizeof(err));
              if (doc) spdf_close(doc);
          }
        }];
    }
}

- (void)loadCommentsForCurrentDocumentAsync {
    if (!_path.length) return;
    NSString* path = [_path copy];
    NSUInteger generation = _renderGeneration;
    [_preloadQueue addOperationWithBlock:^{
      @autoreleasepool {
          spdf_comments* comments = (spdf_comments*)calloc(1, sizeof(spdf_comments));
          if (!comments) return;
          char err[1024];
          spdf_document* doc = spdf_open(path.fileSystemRepresentation, err, sizeof(err));
          if (doc) {
              if (!spdf_load_comments(doc, comments, err, sizeof(err))) spdf_free_comments(comments);
              spdf_close(doc);
          }
          [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (generation == self->_renderGeneration &&
                [self->_path.stringByStandardizingPath isEqualToString:path.stringByStandardizingPath]) {
                spdf_free_comments(&self->_comments);
                self->_comments = *comments;
                free(comments);
                [self rebuildSidebar];
            } else {
                spdf_free_comments(comments);
                free(comments);
            }
          }];
      }
    }];
}

- (NSPoint)visibleCenterWindowPoint {
    NSRect visible = _pageScrollView.contentView.bounds;
    NSPoint centerInPageView = NSMakePoint(NSMidX(visible), NSMidY(visible));
    return [_pageView convertPoint:centerInPageView toView:nil];
}

- (void)zoomByFactor:(CGFloat)factor centeredAtWindowPoint:(NSPoint)windowPoint {
    if (!_doc || factor <= 0) return;

    NSClipView* clipView = _pageScrollView.contentView;
    NSPoint viewPoint = [_pageView convertPoint:windowPoint fromView:nil];
    NSPoint oldOrigin = clipView.bounds.origin;
    CGFloat oldZoom = _zoom;

    _fitMode = SPDFFitModeCustom;
    _zoom = MAX(kMinZoom, MIN(kMaxZoom, _zoom * factor));
    if (fabs(_zoom - oldZoom) < 0.0001) return;

    CGFloat ratio = _zoom / oldZoom;
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO restoreOrigin:[NSValue valueWithPoint:oldOrigin]];

    NSPoint newOrigin = NSMakePoint(viewPoint.x * ratio - (viewPoint.x - oldOrigin.x),
                                    viewPoint.y * ratio - (viewPoint.y - oldOrigin.y));
    newOrigin.x = MAX(0, MIN(newOrigin.x, MAX(0, NSWidth(_pageView.bounds) - NSWidth(clipView.bounds))));
    newOrigin.y = MAX(0, MIN(newOrigin.y, MAX(0, NSHeight(_pageView.bounds) - NSHeight(clipView.bounds))));
    [self scrollDocumentClipViewToOrigin:newOrigin notify:YES];
    [self persistActiveState];
}

- (void)setZoomWithoutRendering:(CGFloat)newZoom centeredAtWindowPoint:(NSPoint)windowPoint {
    if (!_doc) return;
    NSClipView* clipView = _pageScrollView.contentView;
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
    [self scrollDocumentClipViewToOrigin:newOrigin notify:NO];
    [self syncToolbarState];
    [self updateControls];
    [self documentScrollPositionChanged];
}

- (void)renderDocumentPreservingScrollPosition {
    if (!_doc) return;
    NSClipView* clipView = _pageScrollView.contentView;
    NSPoint origin = clipView.bounds.origin;
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO restoreOrigin:[NSValue valueWithPoint:origin]];
}

- (void)finishLiveZoom:(NSTimer*)timer {
    (void)timer;
    _zoomFinishTimer = nil;
    if (_doc) {
        [self renderDocumentPreservingScrollPosition];
        [self persistActiveState];
    }
}

- (void)beginLiveZoomByFactor:(CGFloat)factor centeredAtWindowPoint:(NSPoint)windowPoint {
    if (!_doc || factor <= 0) return;
    _fitMode = SPDFFitModeCustom;
    [self setZoomWithoutRendering:_zoom * factor centeredAtWindowPoint:windowPoint];
    [_zoomFinishTimer invalidate];
    _zoomFinishTimer = [NSTimer scheduledTimerWithTimeInterval:0.18
                                                        target:self
                                                      selector:@selector(finishLiveZoom:)
                                                      userInfo:nil
                                                       repeats:NO];
}

- (void)openDocument:(id)sender {
    (void)sender;
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.allowedFileTypes = @[ @"pdf", @"xps", @"cbz", @"epub" ];
    if ([panel runModal] == NSModalResponseOK) [self openPath:panel.URL.path];
}

- (void)loadSelectedTab {
    if (_selectedTabIndex < 0 || _selectedTabIndex >= (NSInteger)_tabs.count) return;
    SPDFDocumentTab* tab = _tabs[(NSUInteger)_selectedTabIndex];
    if (!tab.path.length) return;
    NSString* path = tab.path;
    [_renderQueue cancelAllOperations];

    char err[1024];
    spdf_document* newDoc = spdf_open(path.fileSystemRepresentation, err, sizeof(err));
    if (!newDoc) {
        [self showError:@"Could not open document"
                 detail:[NSString stringWithUTF8String:err[0] ? err : "Unknown error"]];
        return;
    }

    spdf_free_outline(&_outline);
    spdf_free_comments(&_comments);
    spdf_close(_doc);
    _doc = newDoc;
    _path = [path copy];
    _pageIndex = MAX(0, MIN(tab.pageIndex, spdf_page_count(_doc) - 1));
    _highlightPageIndex = -1;
    _selectionPageIndex = -1;
    _selectedText = nil;
    _searchField.stringValue = @"";
    [self clearFindResults];
    _renderGeneration++;
    _zoom = tab.zoom > 0 ? tab.zoom : 1.0;
    _fitMode = tab.fitMode;
    _viewMode = tab.viewMode;
    _statusLabel.stringValue = @"Opening...";
    NSClipView* clipView = _pageScrollView.contentView;
    BOOL previousHidden = _pageScrollView.hidden;
    BOOL previousPostsBoundsChangedNotifications = clipView.postsBoundsChangedNotifications;
    BOOL previousSuppressScrollCallbacks = _suppressScrollCallbacks;
    _suppressScrollCallbacks = YES;
    _pageScrollView.hidden = YES;
    clipView.postsBoundsChangedNotifications = NO;
    [self replaceDocumentViewForTabSwitch];
    tab.title = spdf_display_name_for_path(_path);

    char outlineErr[1024];
    if (_doc && !spdf_load_outline(_doc, &_outline, outlineErr, sizeof(outlineErr)))
        _statusLabel.stringValue = [NSString stringWithFormat:@"Opened, but outline was not available: %s", outlineErr];

    [self rebuildSidebar];
    [self loadCommentsForCurrentDocumentAsync];
    [self updateTabStrip];
    [self preloadInactiveTabs];
    [self savePersistentState];
    NSValue* restoreOrigin = tab.hasScrollOrigin ? [NSValue valueWithPoint:tab.scrollOrigin] : nil;
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:YES restoreOrigin:restoreOrigin];
    clipView.postsBoundsChangedNotifications = previousPostsBoundsChangedNotifications;
    _pageScrollView.hidden = previousHidden;
    _suppressScrollCallbacks = previousSuppressScrollCallbacks;
    [self documentScrollPositionChanged];
    [_pageView setNeedsDisplay:YES];
    [_pageScrollView displayIfNeeded];
}

- (void)closeDocument:(id)sender {
    (void)sender;
    if (_selectedTabIndex >= 0) {
        [self closeTabAtIndex:_selectedTabIndex];
        return;
    }
    spdf_free_outline(&_outline);
    spdf_free_comments(&_comments);
    spdf_close(_doc);
    _doc = NULL;
    _path = nil;
    _pageIndex = 0;
    _highlightPageIndex = -1;
    _selectionPageIndex = -1;
    _selectedText = nil;
    _renderGeneration++;
    [_renderedPages removeAllObjects];
    _pageView.pages = @[];
    [self updateMinimap];
    _window.title = @"SumatraPDF";
    _statusLabel.stringValue = @"Ready";
    [self rebuildSidebar];
    [self updateControls];
}

- (void)openPath:(NSString*)path {
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
    SPDFDocumentTab* tab = [[SPDFDocumentTab alloc] init];
    tab.path = [path copy];
    tab.title = spdf_display_name_for_path(path);
    tab.zoom = _zoom > 0 ? _zoom : 1.0;
    tab.fitMode = _fitMode;
    tab.viewMode = _viewMode;
    [_tabs addObject:tab];
    _selectedTabIndex = (NSInteger)_tabs.count - 1;
    [self loadSelectedTab];
    [self savePersistentState];
}

- (void)selectTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_tabs.count || (index == _selectedTabIndex && _doc)) return;
    [self rememberActiveTabState];
    _selectedTabIndex = index;
    [self loadSelectedTab];
    [self savePersistentState];
}

- (void)closeTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_tabs.count) return;
    BOOL closingActive = index == _selectedTabIndex;
    [_tabs removeObjectAtIndex:(NSUInteger)index];
    if (!closingActive && index < _selectedTabIndex) _selectedTabIndex--;

    if (_tabs.count == 0) {
        _selectedTabIndex = -1;
        spdf_free_outline(&_outline);
        spdf_free_comments(&_comments);
        spdf_close(_doc);
        _doc = NULL;
        _path = nil;
        _pageIndex = 0;
        _selectedText = nil;
        _renderGeneration++;
        [_renderedPages removeAllObjects];
        _pageView.pages = @[];
        [self updateMinimap];
        [self rebuildSidebar];
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

- (void)newTabRequested:(id)sender {
    [self openDocument:sender];
}

- (BOOL)openFilesFromPasteboard:(NSPasteboard*)pasteboard {
    NSArray<NSURL*>* urls = [pasteboard readObjectsForClasses:@[ [NSURL class] ]
                                                      options:@{NSPasteboardURLReadingFileURLsOnlyKey : @YES}];
    BOOL opened = NO;
    for (NSURL* url in urls) {
        NSString* ext = url.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"pdf"] || [ext isEqualToString:@"xps"] || [ext isEqualToString:@"cbz"] ||
            [ext isEqualToString:@"epub"]) {
            [self openPath:url.path];
            opened = YES;
        }
    }
    return opened;
}

- (SPDFDocumentView*)newDocumentView {
    SPDFDocumentView* view = [[SPDFDocumentView alloc] initWithFrame:NSMakeRect(0, 0, 800, 1000)];
    view.reader = self;
    [view registerForDraggedTypes:@[ NSPasteboardTypeFileURL ]];
    view.viewMode = _viewMode;
    view.zoom = _zoom;
    view.currentPageIndex = _pageIndex;
    return view;
}

- (void)replaceDocumentViewForTabSwitch {
    [_pageView cancelTransientInteraction];
    NSClipView* clipView = _pageScrollView.contentView;
    BOOL previousPostsBoundsChangedNotifications = clipView.postsBoundsChangedNotifications;
    clipView.postsBoundsChangedNotifications = NO;
    _pageScrollView.documentView = nil;
    _pageView = [self newDocumentView];
    _pageScrollView.documentView = _pageView;
    clipView.postsBoundsChangedNotifications = previousPostsBoundsChangedNotifications;
}

- (void)setSidebarActuallyVisible:(BOOL)visible {
    if (!_splitView || !_sidebarContainer || !_documentContainer || visible == _sidebarVisible) return;
    if (visible) {
        [_splitView addSubview:_sidebarContainer positioned:NSWindowBelow relativeTo:_documentContainer];
        [_splitView setPosition:240 ofDividerAtIndex:0];
    } else {
        [_sidebarContainer removeFromSuperview];
    }
    _sidebarVisible = visible;
}

- (void)rebuildSidebar {
    [_sidebarItems removeAllObjects];
    BOOL hasChapters = _outline.count > 0;
    BOOL hasComments = _comments.count > 0;
    BOOL hasSidebar = _doc && (hasChapters || hasComments);

    [_sidebarModeControl setEnabled:hasChapters forSegment:SPDFSidebarModeChapters];
    [_sidebarModeControl setEnabled:hasComments forSegment:SPDFSidebarModeComments];
    if (hasChapters && !hasComments)
        _sidebarModeControl.selectedSegment = SPDFSidebarModeChapters;
    else if (!hasChapters && hasComments)
        _sidebarModeControl.selectedSegment = SPDFSidebarModeComments;
    else if (!hasChapters && !hasComments)
        _sidebarModeControl.selectedSegment = SPDFSidebarModeChapters;

    [self setSidebarActuallyVisible:hasSidebar && _sidebarPreferredVisible];
    if (!hasSidebar) {
        [_sidebarTable reloadData];
        return;
    }

    if (_sidebarModeControl.selectedSegment == SPDFSidebarModeComments && hasComments) {
        for (int i = 0; i < _comments.count; ++i) {
            spdf_comment_item item = _comments.items[i];
            NSString* type = item.type && *item.type ? [NSString stringWithUTF8String:item.type] : @"Comment";
            NSString* author = item.author && *item.author ? [NSString stringWithUTF8String:item.author] : @"";
            NSString* text = item.text && *item.text ? [NSString stringWithUTF8String:item.text] : @"";
            NSString* title = text.length ? text : type;
            if (author.length) title = [NSString stringWithFormat:@"%@: %@", author, title];
            [_sidebarItems
                addObject:@{@"title" : title, @"page" : @(item.page_index), @"level" : @0, @"kind" : @"comment"}];
        }
    } else if (hasChapters) {
        for (int i = 0; i < _outline.count; ++i) {
            spdf_outline_item item = _outline.items[i];
            NSString* title = item.title ? [NSString stringWithUTF8String:item.title] : @"Untitled";
            [_sidebarItems addObject:@{
                @"title" : title,
                @"page" : @(item.page_index),
                @"level" : @(item.level),
                @"kind" : @"chapter"
            }];
        }
    }
    [_sidebarTable reloadData];
    [self selectCurrentSidebarRow];
}

- (void)sidebarModeChanged:(id)sender {
    (void)sender;
    [self rebuildSidebar];
}

- (void)clipViewBoundsChanged:(NSNotification*)notification {
    (void)notification;
    if (_suppressScrollCallbacks) return;
    [self documentScrollPositionChanged];
}

- (void)documentScrollPositionChanged {
    if (_suppressScrollCallbacks) return;
    if (_renderedPages.count == 0) {
        [self updateMinimap];
        return;
    }
    if (!_updatingFromScroll && _viewMode == SPDFViewModeContinuous) {
        NSInteger visiblePage = [_pageView pageIndexForVisibleRect:_pageScrollView.contentView.bounds];
        if (visiblePage != _pageIndex) {
            _pageIndex = visiblePage;
            _pageView.currentPageIndex = _pageIndex;
            [self updateControls];
            [self selectCurrentSidebarRow];
        }
    }
    [self updateMinimap];
}

- (BOOL)scrollViewShouldTurnWheelIntoPageChange:(NSEvent*)event {
    (void)event;
    if (!_doc) return NO;
    return _viewMode == SPDFViewModeSingle || _fitMode == SPDFFitModeHeight || _fitMode == SPDFFitModePage;
}

- (void)syncToolbarState {
    [_fitModePopup selectItemAtIndex:_fitMode];
    _continuousButton.state = _viewMode == SPDFViewModeContinuous ? NSControlStateValueOn : NSControlStateValueOff;
    _tabStrip.tabs = _tabs;
    _tabStrip.selectedIndex = _selectedTabIndex;
}

- (void)updateControls {
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
    _ocrButton.enabled = hasDoc && [_path.pathExtension.lowercaseString isEqualToString:@"pdf"];
    [self updateFindControls];
    _pageField.stringValue = hasDoc ? [NSString stringWithFormat:@"%ld", (long)_pageIndex + 1] : @"";
    _pageCountLabel.stringValue = [NSString stringWithFormat:@"/ %ld", (long)pageCount];

    if (hasDoc) {
        NSString* displayName =
            _path.length ? spdf_display_name_for_path(_path) : [NSString stringWithUTF8String:spdf_title(_doc)];
        _window.title = [NSString stringWithFormat:@"%@ - SumatraPDF", displayName];
        NSString* mode = _viewMode == SPDFViewModeContinuous ? @"Continuous" : @"Single page";
        _statusLabel.stringValue =
            [NSString stringWithFormat:@"Page %ld of %ld    Zoom %.0f%%    %@", (long)_pageIndex + 1, (long)pageCount,
                                       _zoom * 100.0, mode];
    }
}

- (void)selectCurrentSidebarRow {
    if (!_doc || _updatingSelection) return;
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

- (void)updateFindCountLabel {
    if (!_findCountLabel) return;
    if (!_doc || _searchField.stringValue.length == 0) {
        _findCountLabel.stringValue = @"";
        return;
    }
    if (_findSearchInProgress) {
        _findCountLabel.stringValue = @"...";
        return;
    }
    if (_findMatches.count == 0) {
        _findCountLabel.stringValue = @"0 / 0";
        return;
    }
    NSInteger current = _findMatchIndex >= 0 ? _findMatchIndex + 1 : 1;
    _findCountLabel.stringValue = [NSString stringWithFormat:@"%ld / %ld", (long)current, (long)_findMatches.count];
}

- (void)updateFindControls {
    BOOL hasMatches = _findMatches.count > 0;
    _findPrevButton.enabled = hasMatches;
    _findNextButton.enabled = hasMatches;
    [self updateFindCountLabel];
}

- (void)clearFindResults {
    [_findQueue cancelAllOperations];
    _findGeneration++;
    [_findHighlights removeAllObjects];
    [_findMatches removeAllObjects];
    _findMatchIndex = -1;
    _findSearchInProgress = NO;
    [self applySearchHighlightsToCurrentPage];
    [self updateFindControls];
}

- (NSArray<NSValue*>*)highlightRectsForPage:(NSInteger)pageIndex {
    if (!_doc || _searchField.stringValue.length == 0) return @[];
    char err[1024];
    spdf_rect rects[256];
    int count =
        spdf_search_page_rects(_doc, (int)pageIndex, _searchField.stringValue.UTF8String, rects, 256, err, sizeof(err));
    if (count <= 0) return @[];

    NSMutableArray<NSValue*>* values = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
    for (int i = 0; i < count; ++i) {
        NSRect r = NSMakeRect(rects[i].x0, rects[i].y0, rects[i].x1 - rects[i].x0, rects[i].y1 - rects[i].y0);
        [values addObject:[NSValue valueWithRect:r]];
    }
    return values;
}

- (void)applySearchHighlightsToCurrentPage {
    for (SPDFRenderedPage* page in _renderedPages) page.highlights = _findHighlights[@(page.pageIndex)] ?: @[];
    _pageView.pages = _renderedPages;
    [_pageView setNeedsDisplay:YES];
    [self updateMinimap];
}

- (void)startFindForCurrentQuery {
    if (!_doc || !_path.length) {
        [self clearFindResults];
        return;
    }

    NSString* query = [_searchField.stringValue copy];
    [_findQueue cancelAllOperations];
    _findGeneration++;
    NSUInteger generation = _findGeneration;
    [_findHighlights removeAllObjects];
    [_findMatches removeAllObjects];
    _findMatchIndex = -1;
    _findSearchInProgress = NO;
    [self applySearchHighlightsToCurrentPage];
    [self updateFindControls];

    if (query.length == 0) {
        _statusLabel.stringValue = @"Ready";
        return;
    }

    NSString* path = [_path copy];
    _findSearchInProgress = YES;
    [self updateFindControls];
    _statusLabel.stringValue = [NSString stringWithFormat:@"Searching for \"%@\"...", query];
    [_findQueue addOperationWithBlock:^{
      @autoreleasepool {
          NSMutableDictionary<NSNumber*, NSArray<NSValue*>*>* highlights = [NSMutableDictionary dictionary];
          NSMutableArray<NSDictionary*>* matches = [NSMutableArray array];
          char openErr[1024];
          spdf_document* doc = spdf_open(path.fileSystemRepresentation, openErr, sizeof(openErr));
          if (!doc) {
              [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                if (generation != self->_findGeneration) return;
                self->_findSearchInProgress = NO;
                [self updateFindControls];
              }];
              return;
          }

          NSInteger pageCount = spdf_page_count(doc);
          for (NSInteger page = 0; page < pageCount; ++page) {
              if (generation != self->_findGeneration) break;
              char err[512];
              spdf_rect rects[256];
              int count = spdf_search_page_rects(doc, (int)page, query.UTF8String, rects, 256, err, sizeof(err));
              if (count <= 0) continue;
              NSMutableArray<NSValue*>* values = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
              for (int i = 0; i < count; ++i) {
                  NSRect r = NSMakeRect(rects[i].x0, rects[i].y0, rects[i].x1 - rects[i].x0, rects[i].y1 - rects[i].y0);
                  [values addObject:[NSValue valueWithRect:r]];
                  [matches addObject:@{@"page" : @(page), @"rect" : [NSValue valueWithRect:r]}];
              }
              highlights[@(page)] = values;
          }
          spdf_close(doc);

          [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (generation != self->_findGeneration) return;
            [self->_findHighlights removeAllObjects];
            [self->_findHighlights addEntriesFromDictionary:highlights];
            [self->_findMatches removeAllObjects];
            [self->_findMatches addObjectsFromArray:matches];
            self->_findMatchIndex = self->_findMatches.count > 0 ? 0 : -1;
            self->_findSearchInProgress = NO;
            [self applySearchHighlightsToCurrentPage];
            [self updateFindControls];
            if (self->_findMatches.count > 0)
                self->_statusLabel.stringValue =
                    [NSString stringWithFormat:@"%ld matches for \"%@\"", (long)self->_findMatches.count, query];
            else
                self->_statusLabel.stringValue = [NSString stringWithFormat:@"No matches for \"%@\"", query];
          }];
      }
    }];
}

- (void)jumpToFindMatchAtIndex:(NSInteger)index {
    if (!_doc || index < 0 || index >= (NSInteger)_findMatches.count) return;
    _findMatchIndex = index;
    NSDictionary* match = _findMatches[(NSUInteger)index];
    NSInteger page = [match[@"page"] integerValue];
    _pageIndex = MAX(0, MIN(page, spdf_page_count(_doc) - 1));
    _pageView.currentPageIndex = _pageIndex;
    [self renderPageIfNeededAtIndex:_pageIndex];
    [self applySearchHighlightsToCurrentPage];
    [self resizeDocumentView];
    [self scrollToPage:_pageIndex alignTop:YES];
    [self updateControls];
    [self selectCurrentSidebarRow];
    [self updateFindControls];
    _statusLabel.stringValue =
        [NSString stringWithFormat:@"Match %ld of %ld", (long)_findMatchIndex + 1, (long)_findMatches.count];
}

- (void)documentViewSelectionChangedOnPage:(NSInteger)pageIndex from:(NSPoint)start to:(NSPoint)end {
    if (!_doc || pageIndex < 0 || pageIndex >= (NSInteger)_renderedPages.count) return;

    char err[1024];
    spdf_rect rects[256];
    char* text = NULL;
    int count = spdf_select_page_text(_doc, (int)pageIndex, (float)start.x, (float)start.y, (float)end.x, (float)end.y,
                                      rects, 256, &text, err, sizeof(err));

    for (SPDFRenderedPage* page in _renderedPages) page.selectionRects = @[];

    if (count > 0) {
        NSMutableArray<NSValue*>* values = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
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

    if (text) spdf_free_string(text);
    _pageView.pages = _renderedPages;
    [_pageView setNeedsDisplay:YES];
    [self updateMinimap];
}

- (void)copySelection:(id)sender {
    (void)sender;
    if (_selectedText.length == 0) {
        NSBeep();
        return;
    }
    NSPasteboard* pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:_selectedText forType:NSPasteboardTypeString];
    _statusLabel.stringValue = @"Selected text copied.";
}

- (NSString*)shortProvenanceForPath:(NSString*)path {
    NSString* displayPath = spdf_display_path_without_extension(path);
    if (displayPath.length <= 52) return spdf_display_name_for_path(path);
    NSString* head = [displayPath substringToIndex:MIN((NSUInteger)20, displayPath.length)];
    NSString* tail = [displayPath substringFromIndex:displayPath.length - MIN((NSUInteger)28, displayPath.length)];
    return [NSString stringWithFormat:@"%@...%@", head, tail];
}

- (void)favoriteCurrentPage:(id)sender {
    (void)sender;
    if (!_path.length) return;
    NSString* displayName = spdf_display_name_for_path(_path);
    NSString* name = [NSString stringWithFormat:@"%@ p.%ld", displayName, (long)_pageIndex + 1];
    NSMutableDictionary* fav = [@{
        @"type" : @"page",
        @"path" : _path,
        @"title" : displayName,
        @"page" : @(_pageIndex),
        @"name" : name,
        @"created" : @((long)NSDate.date.timeIntervalSince1970)
    } mutableCopy];
    NSIndexSet* dupes = [_favorites indexesOfObjectsPassingTest:^BOOL(NSDictionary* obj, NSUInteger idx, BOOL* stop) {
      (void)idx;
      (void)stop;
      return [obj[@"path"] isEqualToString:_path] && [obj[@"type"] isEqualToString:@"page"] &&
             [obj[@"page"] integerValue] == _pageIndex;
    }];
    if (dupes.count) [_favorites removeObjectsAtIndexes:dupes];
    [_favorites addObject:fav];
    [self savePersistentState];
    _statusLabel.stringValue = @"Page added to favorites.";
}

- (void)favoriteCurrentDocument:(id)sender {
    (void)sender;
    if (!_path.length) return;
    NSString* displayName = spdf_display_name_for_path(_path);
    NSMutableDictionary* fav = [@{
        @"type" : @"document",
        @"path" : _path,
        @"title" : displayName,
        @"page" : @0,
        @"name" : displayName,
        @"created" : @((long)NSDate.date.timeIntervalSince1970)
    } mutableCopy];
    NSIndexSet* dupes = [_favorites indexesOfObjectsPassingTest:^BOOL(NSDictionary* obj, NSUInteger idx, BOOL* stop) {
      (void)idx;
      (void)stop;
      return [obj[@"path"] isEqualToString:_path] && [obj[@"type"] isEqualToString:@"document"];
    }];
    if (dupes.count) [_favorites removeObjectsAtIndexes:dupes];
    [_favorites addObject:fav];
    [self savePersistentState];
    _statusLabel.stringValue = @"Document added to favorites.";
}

- (void)showFavoritesPalette:(id)sender {
    (void)sender;
    _paletteMode = 1;
    [self showPaletteWithTitle:@"Command"];
}

- (void)focusFind:(id)sender {
    (void)sender;
    [_window makeFirstResponder:_searchField];
    [_searchField selectText:nil];
}

- (void)showFindPalette:(id)sender {
    [self focusFind:sender];
}

- (void)showPaletteWithTitle:(NSString*)title {
    if (!_palettePanel) {
        _palettePanel = [[NSPanel alloc]
            initWithContentRect:NSMakeRect(0, 0, 650, 390)
                      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskUtilityWindow | NSWindowStyleMaskClosable
                        backing:NSBackingStoreBuffered
                          defer:NO];
        _palettePanel.floatingPanel = YES;
        _palettePanel.hidesOnDeactivate = YES;
        _palettePanel.releasedWhenClosed = NO;

        NSView* content = [[NSView alloc] initWithFrame:_palettePanel.contentView.bounds];
        content.translatesAutoresizingMaskIntoConstraints = NO;
        _palettePanel.contentView = content;

        _paletteSearchField = [[SPDFPaletteSearchField alloc] init];
        ((SPDFPaletteSearchField*)_paletteSearchField).reader = self;
        _paletteSearchField.translatesAutoresizingMaskIntoConstraints = NO;
        _paletteSearchField.delegate = self;
        [content addSubview:_paletteSearchField];

        NSScrollView* scroll = [[NSScrollView alloc] init];
        scroll.translatesAutoresizingMaskIntoConstraints = NO;
        scroll.hasVerticalScroller = YES;
        [content addSubview:scroll];

        _paletteTable = [[NSTableView alloc] init];
        _paletteTable.headerView = nil;
        _paletteTable.rowHeight = 42.0;
        _paletteTable.intercellSpacing = NSMakeSize(0, 0);
        _paletteTable.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
        _paletteTable.allowsEmptySelection = NO;
        _paletteTable.dataSource = self;
        _paletteTable.delegate = self;
        _paletteTable.target = self;
        _paletteTable.action = @selector(activatePaletteSelection:);
        _paletteTable.doubleAction = @selector(activatePaletteSelection:);
        NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"result"];
        column.width = 620;
        [_paletteTable addTableColumn:column];
        scroll.documentView = _paletteTable;

        [NSLayoutConstraint activateConstraints:@[
            [_paletteSearchField.topAnchor constraintEqualToAnchor:content.topAnchor constant:14],
            [_paletteSearchField.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
            [_paletteSearchField.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
            [scroll.topAnchor constraintEqualToAnchor:_paletteSearchField.bottomAnchor constant:10],
            [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
            [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
            [scroll.bottomAnchor constraintEqualToAnchor:content.bottomAnchor]
        ]];
    }

    _palettePanel.title = title;
    _paletteSearchField.stringValue = @"";
    _paletteSearchField.placeholderString = @"Favorites and open documents";
    _paletteAllDocsCheckbox.hidden = YES;
    [self refreshPaletteResults];
    NSRect windowFrame = _window.frame;
    NSRect panelFrame = _palettePanel.frame;
    panelFrame.origin.x = NSMidX(windowFrame) - NSWidth(panelFrame) / 2.0;
    panelFrame.origin.y = NSMaxY(windowFrame) - NSHeight(panelFrame) - 88.0;
    [_palettePanel setFrame:panelFrame display:NO];
    [_palettePanel makeKeyAndOrderFront:nil];
    [self installPaletteEventMonitor];
    [_palettePanel makeFirstResponder:_paletteSearchField];
}

- (BOOL)isSelectablePaletteResult:(NSDictionary*)result {
    NSString* kind = result[@"kind"];
    return ![kind isEqualToString:@"header"] && ![kind isEqualToString:@"separator"] &&
           ![kind isEqualToString:@"status"];
}

- (void)selectFirstPaletteResult {
    for (NSInteger i = 0; i < (NSInteger)_paletteResults.count; ++i) {
        if ([self isSelectablePaletteResult:_paletteResults[(NSUInteger)i]]) {
            [_paletteTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)i] byExtendingSelection:NO];
            [_paletteTable scrollRowToVisible:i];
            return;
        }
    }
    [_paletteTable deselectAll:nil];
}

- (void)refreshPaletteResults {
    _paletteSearchGeneration++;
    NSUInteger generation = _paletteSearchGeneration;
    [_paletteResults removeAllObjects];
    NSString* query = _paletteSearchField.stringValue.lowercaseString ?: @"";

    NSArray<NSDictionary*>* favorites = [self favoriteResultsForQuery:query prefix:@""];
    if (favorites.count > 0) {
        [_paletteResults addObject:@{@"kind" : @"header", @"title" : @"Favorites", @"subtitle" : @""}];
        [_paletteResults addObject:@{@"kind" : @"separator", @"title" : @"", @"subtitle" : @""}];
        [_paletteResults addObjectsFromArray:favorites];
    }

    if (_path.length && query.length == 0) {
        NSString* displayName = spdf_display_name_for_path(_path);
        [_paletteResults addObject:@{@"kind" : @"header", @"title" : @"Actions", @"subtitle" : @""}];
        [_paletteResults
            addObject:@{@"kind" : @"addPage", @"title" : @"Favorite current page", @"subtitle" : displayName ?: @""}];
        [_paletteResults addObject:@{
            @"kind" : @"addDoc",
            @"title" : @"Favorite current document",
            @"subtitle" : displayName ?: @""
        }];
    }

    if (query.length > 0 && _tabs.count > 0) {
        [_preloadQueue cancelAllOperations];
        [_paletteResults addObject:@{@"kind" : @"header", @"title" : @"Open documents", @"subtitle" : @""}];
        [_paletteResults addObject:@{@"kind" : @"separator", @"title" : @"", @"subtitle" : @""}];
        [_paletteResults
            addObject:@{@"kind" : @"status", @"title" : @"Searching open documents...", @"subtitle" : @""}];
        [self runFindPaletteSearchForQuery:query generation:generation searchAll:YES];
    } else if (_paletteResults.count == 0) {
        [_paletteResults addObject:@{
            @"kind" : @"status",
            @"title" : @"No favorites yet",
            @"subtitle" : @"Use Cmd+B or Cmd+Shift+B to add one."
        }];
    }

    [_paletteTable reloadData];
    [self selectFirstPaletteResult];
}

- (NSArray<NSDictionary*>*)favoriteResultsForQuery:(NSString*)query prefix:(NSString*)prefix {
    NSMutableArray<NSDictionary*>* results = [NSMutableArray array];
    NSString* lowerQuery = query.lowercaseString ?: @"";
    for (NSDictionary* fav in _favorites) {
        NSString* haystack = [[NSString stringWithFormat:@"%@ %@ %@", fav[@"name"] ?: @"", fav[@"title"] ?: @"",
                                                         fav[@"path"] ?: @""] lowercaseString];
        if (lowerQuery.length == 0 || [haystack containsString:lowerQuery]) {
            NSString* subtitle = [self shortProvenanceForPath:fav[@"path"] ?: @""];
            if (prefix.length) subtitle = [NSString stringWithFormat:@"%@ - %@", prefix, subtitle];
            NSString* title = spdf_display_label_without_extension(fav[@"name"] ?: fav[@"title"] ?: @"Favorite");
            [results addObject:@{
                @"kind" : @"favorite",
                @"title" : title,
                @"subtitle" : subtitle,
                @"path" : fav[@"path"] ?: @"",
                @"page" : fav[@"page"] ?: @0
            }];
        }
    }
    return results;
}

- (void)runFindPaletteSearchForQuery:(NSString*)query generation:(NSUInteger)generation searchAll:(BOOL)searchAll {
    NSString* currentPath = [_path copy];
    NSArray<SPDFDocumentTab*>* tabs = [_tabs copy];
    [_preloadQueue addOperationWithBlock:^{
      @autoreleasepool {
          NSMutableArray<NSDictionary*>* results = [NSMutableArray array];
          NSMutableSet<NSString*>* searchedPaths = [NSMutableSet set];
          for (SPDFDocumentTab* tab in tabs) {
              if (generation != self->_paletteSearchGeneration) return;
              if (results.count >= 220) break;
              BOOL isCurrent =
                  [tab.path.stringByStandardizingPath isEqualToString:currentPath.stringByStandardizingPath];
              if (!isCurrent && !searchAll) continue;
              NSString* path = tab.path;
              if (!path.length || [searchedPaths containsObject:path.stringByStandardizingPath]) continue;
              [searchedPaths addObject:path.stringByStandardizingPath];

              char openErr[512];
              spdf_document* doc = spdf_open(path.fileSystemRepresentation, openErr, sizeof(openErr));
              if (!doc) continue;
              NSInteger pageCount = spdf_page_count(doc);
              for (NSInteger page = 0; page < pageCount && results.count < 220; ++page) {
                  if (generation != self->_paletteSearchGeneration) break;
                  char err[512];
                  int hits = spdf_search_page(doc, (int)page, query.UTF8String, err, sizeof(err));
                  if (hits > 0) {
                      [results addObject:@{
                          @"kind" : @"find",
                          @"title" : [NSString
                              stringWithFormat:@"Page %ld: %d match%@", (long)page + 1, hits, hits == 1 ? @"" : @"es"],
                          @"subtitle" : [self shortProvenanceForPath:path],
                          @"path" : path,
                          @"page" : @(page)
                      }];
                  }
              }
              spdf_close(doc);
          }

          [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (generation != self->_paletteSearchGeneration || !self->_palettePanel.visible) return;
            NSIndexSet* statusRows = [self->_paletteResults
                indexesOfObjectsPassingTest:^BOOL(NSDictionary* obj, NSUInteger idx, BOOL* stop) {
                  (void)idx;
                  (void)stop;
                  return [obj[@"kind"] isEqualToString:@"status"];
                }];
            if (statusRows.count) [self->_paletteResults removeObjectsAtIndexes:statusRows];
            if (results.count > 0)
                [self->_paletteResults addObjectsFromArray:results];
            else if (query.length > 0) {
                [self->_paletteResults
                    addObject:@{@"kind" : @"status", @"title" : @"No open-document matches", @"subtitle" : @""}];
            }
            [self->_paletteTable reloadData];
            [self selectFirstPaletteResult];
          }];
      }
    }];
}

- (void)openPaletteResult:(NSDictionary*)result {
    NSString* kind = result[@"kind"];
    if (![self isSelectablePaletteResult:result]) return;
    if ([kind isEqualToString:@"addPage"]) {
        [self favoriteCurrentPage:nil];
        return;
    }
    if ([kind isEqualToString:@"addDoc"]) {
        [self favoriteCurrentDocument:nil];
        return;
    }
    NSString* path = result[@"path"];
    NSInteger page = [result[@"page"] integerValue];
    if (path.length) {
        [self openPath:path];
        if (_doc && [_path.stringByStandardizingPath isEqualToString:path.stringByStandardizingPath]) {
            _pageIndex = MAX(0, MIN(page, spdf_page_count(_doc) - 1));
            _pageView.currentPageIndex = _pageIndex;
            [self renderDocumentAndScrollToPage:_pageIndex alignTop:YES];
        }
    }
}

- (void)paletteMoveSelection:(NSInteger)delta {
    if (_paletteResults.count == 0) return;
    NSInteger row = _paletteTable.selectedRow;
    if (row < 0) row = delta > 0 ? -1 : 0;
    NSInteger count = (NSInteger)_paletteResults.count;
    for (NSInteger step = 0; step < count; ++step) {
        row = (row + delta + count) % count;
        if ([self isSelectablePaletteResult:_paletteResults[(NSUInteger)row]]) {
            [_paletteTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
            [_paletteTable scrollRowToVisible:row];
            return;
        }
    }
}

- (void)installPaletteEventMonitor {
    if (_paletteEventMonitor) return;
    __weak SumatraMacDelegate* weakSelf = self;
    _paletteEventMonitor =
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown |
                                                      NSEventMaskOtherMouseDown | NSEventMaskKeyDown
                                              handler:^NSEvent*(NSEvent* event) {
                                                SumatraMacDelegate* strongSelf = weakSelf;
                                                if (strongSelf && strongSelf->_palettePanel.visible) {
                                                    if (event.type == NSEventTypeKeyDown &&
                                                        event.window == strongSelf->_palettePanel) {
                                                        if (event.keyCode == 53) {
                                                            [strongSelf closePalette:nil];
                                                            return nil;
                                                        }
                                                        if (event.keyCode == 125) {
                                                            [strongSelf paletteMoveSelection:1];
                                                            return nil;
                                                        }
                                                        if (event.keyCode == 126) {
                                                            [strongSelf paletteMoveSelection:-1];
                                                            return nil;
                                                        }
                                                        if (event.keyCode == 36 || event.keyCode == 76) {
                                                            [strongSelf activatePaletteSelection:nil];
                                                            return nil;
                                                        }
                                                    }
                                                    if (event.type != NSEventTypeKeyDown &&
                                                        event.window != strongSelf->_palettePanel)
                                                        [strongSelf closePalette:nil];
                                                }
                                                return event;
                                              }];
}

- (void)closePalette:(id)sender {
    (void)sender;
    if (_paletteEventMonitor) {
        [NSEvent removeMonitor:_paletteEventMonitor];
        _paletteEventMonitor = nil;
    }
    [_palettePanel orderOut:nil];
}

- (void)activatePaletteSelection:(id)sender {
    (void)sender;
    NSInteger row = _paletteTable.selectedRow;
    if (row < 0 || row >= (NSInteger)_paletteResults.count) return;
    NSDictionary* result = _paletteResults[(NSUInteger)row];
    if (![self isSelectablePaletteResult:result]) return;
    [self closePalette:nil];
    [self openPaletteResult:result];
}

- (void)previousPage:(id)sender {
    (void)sender;
    if (_doc && _pageIndex > 0)
        [self goToPage:_pageIndex - 1 preserveSinglePagePosition:_viewMode == SPDFViewModeSingle];
}

- (void)nextPage:(id)sender {
    (void)sender;
    if (_doc && _pageIndex + 1 < spdf_page_count(_doc))
        [self goToPage:_pageIndex + 1 preserveSinglePagePosition:_viewMode == SPDFViewModeSingle];
}

- (void)firstPage:(id)sender {
    (void)sender;
    if (_doc) [self goToPage:0 preserveSinglePagePosition:_viewMode == SPDFViewModeSingle];
}

- (void)lastPage:(id)sender {
    (void)sender;
    if (_doc) [self goToPage:spdf_page_count(_doc) - 1 preserveSinglePagePosition:_viewMode == SPDFViewModeSingle];
}

- (void)focusPageField:(id)sender {
    (void)sender;
    [_window makeFirstResponder:_pageField];
}

- (void)pageFieldChanged:(id)sender {
    (void)sender;
    if (!_doc) return;
    NSInteger requested = _pageField.integerValue - 1;
    NSInteger pageCount = spdf_page_count(_doc);
    requested = MAX(0, MIN(requested, pageCount - 1));
    [self goToPage:requested preserveSinglePagePosition:_viewMode == SPDFViewModeSingle];
}

- (void)zoomIn:(id)sender {
    (void)sender;
    [self zoomByFactor:1.20 centeredAtWindowPoint:[self visibleCenterWindowPoint]];
}

- (void)zoomOut:(id)sender {
    (void)sender;
    [self zoomByFactor:1.0 / 1.20 centeredAtWindowPoint:[self visibleCenterWindowPoint]];
}

- (void)actualSize:(id)sender {
    (void)sender;
    if (!_doc) return;
    _fitMode = SPDFFitModeActual;
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO];
    [self persistActiveState];
}

- (void)fitWidth:(id)sender {
    (void)sender;
    if (!_doc) return;
    _fitMode = SPDFFitModeWidth;
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO];
    [self persistActiveState];
}

- (void)fitHeight:(id)sender {
    (void)sender;
    if (!_doc) return;
    _fitMode = SPDFFitModeHeight;
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:YES];
    [self persistActiveState];
}

- (void)fitPage:(id)sender {
    (void)sender;
    if (!_doc) return;
    _fitMode = SPDFFitModePage;
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:YES];
    [self persistActiveState];
}

- (void)fitModePopupChanged:(id)sender {
    (void)sender;
    _fitMode = (SPDFFitMode)_fitModePopup.indexOfSelectedItem;
    if (_doc) {
        [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO];
        [self persistActiveState];
    }
}

- (void)setSinglePageMode:(id)sender {
    (void)sender;
    if (!_doc) return;
    NSPoint relativePosition = [self relativeScrollPositionForCurrentPage];
    _viewMode = SPDFViewModeSingle;
    _pageView.viewMode = _viewMode;
    _pageView.currentPageIndex = _pageIndex;
    [self resizeDocumentView];
    [self scrollToPage:_pageIndex preservingRelativePosition:relativePosition];
    [self syncToolbarState];
    [self updateControls];
    [self persistActiveState];
}

- (void)setContinuousMode:(id)sender {
    (void)sender;
    if (!_doc) return;
    NSPoint relativePosition = [self relativeScrollPositionForCurrentPage];
    _viewMode = SPDFViewModeContinuous;
    _pageView.viewMode = _viewMode;
    [self resizeDocumentView];
    [self scrollToPage:_pageIndex preservingRelativePosition:relativePosition];
    [self syncToolbarState];
    [self updateControls];
    [self updateMinimap];
    [self persistActiveState];
}

- (void)toggleContinuous:(id)sender {
    (void)sender;
    if (_continuousButton.state == NSControlStateValueOn)
        [self setContinuousMode:sender];
    else
        [self setSinglePageMode:sender];
}

- (void)toggleSidebar:(id)sender {
    (void)sender;
    _sidebarPreferredVisible = !_sidebarPreferredVisible;
    [self rebuildSidebar];
    [self persistActiveState];
}

- (void)toggleFullScreen:(id)sender {
    [_window toggleFullScreen:sender];
}

- (NSString*)ocrToolPath {
    return [self
        executablePathForTool:@"ocrmypdf"
                   candidates:@[ @"/opt/homebrew/bin/ocrmypdf", @"/usr/local/bin/ocrmypdf", @"/usr/bin/ocrmypdf" ]];
}

- (NSString*)tesseractToolPath {
    return [self
        executablePathForTool:@"tesseract"
                   candidates:@[ @"/opt/homebrew/bin/tesseract", @"/usr/local/bin/tesseract", @"/usr/bin/tesseract" ]];
}

- (NSString*)executablePathForTool:(NSString*)tool candidates:(NSArray<NSString*>*)candidates {
    NSFileManager* fm = NSFileManager.defaultManager;
    for (NSString* path in candidates) {
        if ([fm isExecutableFileAtPath:path]) return path;
    }

    NSString* pathEnv = NSProcessInfo.processInfo.environment[@"PATH"] ?: @"";
    for (NSString* dir in [pathEnv componentsSeparatedByString:@":"]) {
        if (dir.length == 0) continue;
        NSString* path = [dir stringByAppendingPathComponent:tool];
        if ([fm isExecutableFileAtPath:path]) return path;
    }
    return nil;
}

- (void)appendOCRInstallLog:(NSString*)text {
    if (!_ocrInstallLog || text.length == 0) return;
    NSTextStorage* storage = _ocrInstallLog.textStorage;
    [storage appendAttributedString:[[NSAttributedString alloc] initWithString:text]];
    [_ocrInstallLog scrollRangeToVisible:NSMakeRange(storage.length, 0)];
}

- (void)showOCRInstallPanel {
    if (!_ocrInstallPanel) {
        _ocrInstallPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 640, 360)
                                                      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                        backing:NSBackingStoreBuffered
                                                          defer:NO];
        _ocrInstallPanel.title = @"Installing OCR";
        _ocrInstallPanel.releasedWhenClosed = NO;

        NSView* content = [[NSView alloc] initWithFrame:_ocrInstallPanel.contentView.bounds];
        content.translatesAutoresizingMaskIntoConstraints = NO;
        _ocrInstallPanel.contentView = content;

        NSTextField* title = [NSTextField labelWithString:@"Installing OCRmyPDF and Tesseract"];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
        [content addSubview:title];

        _ocrInstallProgress = [[NSProgressIndicator alloc] init];
        _ocrInstallProgress.translatesAutoresizingMaskIntoConstraints = NO;
        _ocrInstallProgress.indeterminate = YES;
        _ocrInstallProgress.style = NSProgressIndicatorStyleBar;
        [content addSubview:_ocrInstallProgress];

        NSScrollView* scroll = [[NSScrollView alloc] init];
        scroll.translatesAutoresizingMaskIntoConstraints = NO;
        scroll.hasVerticalScroller = YES;
        [content addSubview:scroll];

        _ocrInstallLog = [[NSTextView alloc] init];
        _ocrInstallLog.editable = NO;
        _ocrInstallLog.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
        scroll.documentView = _ocrInstallLog;

        [NSLayoutConstraint activateConstraints:@[
            [title.topAnchor constraintEqualToAnchor:content.topAnchor constant:14],
            [title.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
            [title.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
            [_ocrInstallProgress.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
            [_ocrInstallProgress.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [_ocrInstallProgress.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
            [scroll.topAnchor constraintEqualToAnchor:_ocrInstallProgress.bottomAnchor constant:12],
            [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
            [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
            [scroll.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-14]
        ]];
    }

    [_ocrInstallPanel center];
    [_ocrInstallPanel makeKeyAndOrderFront:nil];
    [_ocrInstallProgress startAnimation:nil];
}

- (NSString*)ocrInstallScript {
    return @"set -e\n"
           @"export PATH=\"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH\"\n"
           @"export NONINTERACTIVE=1\n"
           @"if command -v brew >/dev/null 2>&1; then BREW=$(command -v brew); "
           @"elif [ -x /opt/homebrew/bin/brew ]; then BREW=/opt/homebrew/bin/brew; "
           @"elif [ -x /usr/local/bin/brew ]; then BREW=/usr/local/bin/brew; "
           @"else echo 'Homebrew not found. Installing Homebrew...'; "
           @"/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"; "
           @"if [ -x /opt/homebrew/bin/brew ]; then BREW=/opt/homebrew/bin/brew; "
           @"elif [ -x /usr/local/bin/brew ]; then BREW=/usr/local/bin/brew; "
           @"else echo 'Homebrew installation did not produce a brew executable.'; exit 1; fi; fi\n"
           @"echo \"Using $BREW\"\n"
           @"\"$BREW\" install ocrmypdf tesseract\n";
}

- (void)installOCRAndRunAfterwards {
    if (_ocrInstallRunning) {
        [_ocrInstallPanel makeKeyAndOrderFront:nil];
        return;
    }

    _ocrInstallRunning = YES;
    _ocrButton.enabled = NO;
    [self showOCRInstallPanel];
    _ocrInstallLog.string = @"";
    [self appendOCRInstallLog:@"Preparing OCR installer...\n"];

    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/bash"];
    task.arguments = @[ @"-lc", [self ocrInstallScript] ];
    NSPipe* pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    _ocrInstallTask = task;

    __weak SumatraMacDelegate* weakSelf = self;
    pipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle* handle) {
      NSData* chunk = handle.availableData;
      if (chunk.length == 0) {
          handle.readabilityHandler = nil;
          return;
      }
      NSString* text = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding] ?: @"";
      dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf appendOCRInstallLog:text];
      });
    };

    task.terminationHandler = ^(NSTask* finishedTask) {
      pipe.fileHandleForReading.readabilityHandler = nil;
      dispatch_async(dispatch_get_main_queue(), ^{
        SumatraMacDelegate* strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_ocrInstallRunning = NO;
        strongSelf->_ocrInstallTask = nil;
        [strongSelf->_ocrInstallProgress stopAnimation:nil];
        strongSelf->_ocrButton.enabled = strongSelf->_doc != NULL;
        if (finishedTask.terminationStatus == 0 && [strongSelf ocrToolPath].length &&
            [strongSelf tesseractToolPath].length) {
            [strongSelf appendOCRInstallLog:@"\nOCR tools installed.\n"];
            [strongSelf->_ocrInstallPanel orderOut:nil];
            [strongSelf ocrDocument:nil];
        } else {
            [strongSelf
                appendOCRInstallLog:@"\nOCR installation failed. The log above has the package manager output.\n"];
            strongSelf->_statusLabel.stringValue = @"OCR installation failed.";
        }
      });
    };

    NSError* error = nil;
    if (![task launchAndReturnError:&error]) {
        _ocrInstallRunning = NO;
        _ocrInstallTask = nil;
        [_ocrInstallProgress stopAnimation:nil];
        _ocrButton.enabled = _doc != NULL;
        [self showError:@"Could not start OCR installer" detail:error.localizedDescription ?: @""];
    }
}

- (NSString*)backupPathForPDFPath:(NSString*)path {
    NSString* dir = path.stringByDeletingLastPathComponent;
    NSString* stem = path.stringByDeletingPathExtension.lastPathComponent;
    NSString* ext = path.pathExtension.length ? path.pathExtension : @"pdf";
    NSFileManager* fm = NSFileManager.defaultManager;
    NSString* candidate = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_backup.%@", stem, ext]];
    NSInteger index = 2;
    while ([fm fileExistsAtPath:candidate]) {
        candidate = [dir
            stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_backup_%ld.%@", stem, (long)index, ext]];
        index++;
    }
    return candidate;
}

- (void)ocrDocument:(id)sender {
    (void)sender;
    if (!_doc || !_path.length || ![_path.pathExtension.lowercaseString isEqualToString:@"pdf"]) {
        NSBeep();
        return;
    }

    NSString* tool = [self ocrToolPath];
    NSString* tesseract = [self tesseractToolPath];
    if (!tool.length || !tesseract.length) {
        NSAlert* alert = [[NSAlert alloc] init];
        alert.messageText = @"Install OCR support?";
        alert.informativeText = @"SumatraPDF can install OCRmyPDF and Tesseract, then continue OCR automatically when "
                                @"installation finishes.";
        [alert addButtonWithTitle:@"Install"];
        [alert addButtonWithTitle:@"Cancel"];
        alert.alertStyle = NSAlertStyleInformational;
        if ([alert runModal] == NSAlertFirstButtonReturn) [self installOCRAndRunAfterwards];
        return;
    }

    char err[1024];
    int hasText = spdf_document_has_text(_doc, 0, err, sizeof(err));
    if (hasText < 0) {
        [self showError:@"Could not inspect document text"
                 detail:[NSString stringWithUTF8String:err[0] ? err : "Unknown error"]];
        return;
    }

    NSString* backupPath = nil;
    if (hasText > 0) {
        NSAlert* alert = [[NSAlert alloc] init];
        alert.messageText = @"This PDF already contains selectable text.";
        alert.informativeText = @"SumatraPDF will make a backup of the original file before OCR replaces it.";
        [alert addButtonWithTitle:@"OCR and Backup"];
        [alert addButtonWithTitle:@"Cancel"];
        alert.alertStyle = NSAlertStyleWarning;
        if ([alert runModal] != NSAlertFirstButtonReturn) return;

        backupPath = [self backupPathForPDFPath:_path];
        NSError* copyError = nil;
        if (![NSFileManager.defaultManager copyItemAtPath:_path toPath:backupPath error:&copyError]) {
            [self showError:@"Could not create OCR backup" detail:copyError.localizedDescription ?: @""];
            return;
        }
    }

    NSString* originalPath = [_path copy];
    NSInteger originalPage = _pageIndex;
    NSString* dir = originalPath.stringByDeletingLastPathComponent;
    NSString* tmp = [dir
        stringByAppendingPathComponent:[NSString stringWithFormat:@".%@.ocr-%@.pdf", originalPath.lastPathComponent,
                                                                  NSUUID.UUID.UUIDString]];
    NSInteger jobs = MAX(1, NSProcessInfo.processInfo.activeProcessorCount);
    NSMutableArray<NSString*>* args = [@[
        @"--jobs", [NSString stringWithFormat:@"%ld", (long)jobs], @"--rotate-pages", @"--deskew", @"--optimize", @"1"
    ] mutableCopy];
    [args addObject:hasText > 0 ? @"--redo-ocr" : @"--skip-text"];
    [args addObject:originalPath];
    [args addObject:tmp];

    _ocrButton.enabled = NO;
    _statusLabel.stringValue = [NSString stringWithFormat:@"OCR running with %ld workers...", (long)jobs];

    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:tool];
    task.arguments = args;
    NSPipe* pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    __block NSMutableData* outputData = [NSMutableData data];
    pipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle* handle) {
      NSData* chunk = handle.availableData;
      if (chunk.length > 0) {
          @synchronized(outputData) {
              [outputData appendData:chunk];
          }
      } else {
          handle.readabilityHandler = nil;
      }
    };

    __weak SumatraMacDelegate* weakSelf = self;
    task.terminationHandler = ^(NSTask* finishedTask) {
      pipe.fileHandleForReading.readabilityHandler = nil;
      NSData* tail = pipe.fileHandleForReading.readDataToEndOfFile;
      if (tail.length > 0) {
          @synchronized(outputData) {
              [outputData appendData:tail];
          }
      }
      NSData* data = nil;
      @synchronized(outputData) {
          data = [outputData copy];
      }
      NSString* output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
      dispatch_async(dispatch_get_main_queue(), ^{
        SumatraMacDelegate* strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_ocrButton.enabled = strongSelf->_doc != NULL;
        if (finishedTask.terminationStatus != 0) {
            [NSFileManager.defaultManager removeItemAtPath:tmp error:nil];
            NSString* detail = output.length > 1200 ? [output substringToIndex:1200] : output;
            [strongSelf showError:@"OCR failed" detail:detail.length ? detail : @"OCRmyPDF exited with an error."];
            strongSelf->_statusLabel.stringValue = @"OCR failed.";
            return;
        }

        [strongSelf->_renderQueue cancelAllOperations];
        strongSelf->_renderGeneration++;
        spdf_close(strongSelf->_doc);
        strongSelf->_doc = NULL;
        NSError* moveError = nil;
        NSURL* resultingURL = nil;
        if (![NSFileManager.defaultManager replaceItemAtURL:[NSURL fileURLWithPath:originalPath]
                                              withItemAtURL:[NSURL fileURLWithPath:tmp]
                                             backupItemName:nil
                                                    options:0
                                           resultingItemURL:&resultingURL
                                                      error:&moveError]) {
            [strongSelf showError:@"Could not save OCR output" detail:moveError.localizedDescription ?: @""];
            strongSelf->_statusLabel.stringValue = @"OCR output was not installed.";
            return;
        }

        if (strongSelf->_selectedTabIndex >= 0 && strongSelf->_selectedTabIndex < (NSInteger)strongSelf->_tabs.count) {
            SPDFDocumentTab* tab = strongSelf->_tabs[(NSUInteger)strongSelf->_selectedTabIndex];
            tab.pageIndex = originalPage;
        }
        [strongSelf loadSelectedTab];
        if (backupPath.length)
            strongSelf->_statusLabel.stringValue =
                [NSString stringWithFormat:@"OCR complete. Backup: %@", backupPath.lastPathComponent];
        else
            strongSelf->_statusLabel.stringValue = @"OCR complete.";
      });
    };

    NSError* launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        _ocrButton.enabled = YES;
        [NSFileManager.defaultManager removeItemAtPath:tmp error:nil];
        [self showError:@"Could not start OCR" detail:launchError.localizedDescription ?: @""];
    }
}

- (void)printDocument:(id)sender {
    (void)sender;
    if (!_doc) {
        NSBeep();
        return;
    }

    char err[1024];
    for (NSInteger i = 0; i < (NSInteger)_renderedPages.count; ++i) {
        if (!_renderedPages[(NSUInteger)i].image) {
            SPDFRenderedPage* page = [self renderedPageAtIndex:i error:err errorLength:sizeof(err)];
            if (!page) {
                [self showError:@"Could not prepare print job"
                         detail:[NSString stringWithUTF8String:err[0] ? err : "Unknown error"]];
                return;
            }
            [_renderedPages replaceObjectAtIndex:(NSUInteger)i withObject:page];
        }
    }

    NSPrintInfo* info = [NSPrintInfo.sharedPrintInfo copy];
    info.horizontalPagination = NSPrintingPaginationModeClip;
    info.verticalPagination = NSPrintingPaginationModeClip;
    info.horizontallyCentered = YES;
    info.verticallyCentered = YES;

    NSSize paper = info.paperSize;
    SPDFPrintView* printView = [[SPDFPrintView alloc]
        initWithFrame:NSMakeRect(0, 0, paper.width, paper.height * MAX(1, (NSInteger)_renderedPages.count))];
    printView.pages = _renderedPages;

    NSPrintOperation* operation = [NSPrintOperation printOperationWithView:printView printInfo:info];
    operation.showsPrintPanel = YES;
    operation.showsProgressPanel = YES;
    [operation runOperationModalForWindow:_window delegate:nil didRunSelector:NULL contextInfo:NULL];
}

- (void)showProperties:(id)sender {
    (void)sender;
    if (!_doc) return;
    NSString* message =
        [NSString stringWithFormat:@"%@\n%ld pages\n%@",
                                   spdf_title(_doc) ? [NSString stringWithUTF8String:spdf_title(_doc)] : @"Untitled",
                                   (long)spdf_page_count(_doc), _path ?: @""];
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Document Properties";
    alert.informativeText = message;
    [alert runModal];
}

- (void)openInExternalReader:(id)sender {
    (void)sender;
    if (!_path.length) {
        NSBeep();
        return;
    }

    NSURL* fileURL = [NSURL fileURLWithPath:_path];
    NSURL* acrobat = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.adobe.Reader"];
    if (!acrobat)
        acrobat = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.adobe.Acrobat.Pro"];
    if (acrobat) {
        NSWorkspaceOpenConfiguration* config = [NSWorkspaceOpenConfiguration configuration];
        [NSWorkspace.sharedWorkspace openURLs:@[ fileURL ]
                         withApplicationAtURL:acrobat
                                configuration:config
                            completionHandler:nil];
    } else {
        [NSWorkspace.sharedWorkspace openURL:fileURL];
    }
}

- (void)showInFolder:(id)sender {
    (void)sender;
    if (!_path.length) {
        NSBeep();
        return;
    }

    NSURL* fileURL = [NSURL fileURLWithPath:_path];
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[ fileURL ]];
}

- (void)copyCurrentPageImage:(id)sender {
    (void)sender;
    if (!_doc || _pageIndex < 0 || _pageIndex >= (NSInteger)_renderedPages.count ||
        !_renderedPages[(NSUInteger)_pageIndex].image) {
        NSBeep();
        return;
    }

    NSPasteboard* pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard writeObjects:@[ _renderedPages[(NSUInteger)_pageIndex].image ]];
    _statusLabel.stringValue = @"Page image copied.";
}

- (void)showContextMenuForDocumentView:(NSView*)view event:(NSEvent*)event {
    NSMenu* menu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem* copy = [menu addItemWithTitle:@"Copy" action:@selector(copySelection:) keyEquivalent:@""];
    copy.enabled = _selectedText.length > 0;
    NSMenuItem* copyImage = [menu addItemWithTitle:@"Copy Page Image"
                                            action:@selector(copyCurrentPageImage:)
                                     keyEquivalent:@""];
    copyImage.enabled = _doc && _pageIndex >= 0 && _pageIndex < (NSInteger)_renderedPages.count &&
                        _renderedPages[(NSUInteger)_pageIndex].image != nil;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Zoom In" action:@selector(zoomIn:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Zoom Out" action:@selector(zoomOut:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Fit Width" action:@selector(fitWidth:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Fit Page" action:@selector(fitPage:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Favorite Page" action:@selector(favoriteCurrentPage:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Show in Folder" action:@selector(showInFolder:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Properties..." action:@selector(showProperties:) keyEquivalent:@""];
    [NSMenu popUpContextMenu:menu withEvent:event forView:view];
}

- (void)unimplementedMenuItem:(id)sender {
    (void)sender;
    NSBeep();
    _statusLabel.stringValue = @"This SumatraPDF command is listed but not implemented yet.";
}

- (void)findNext:(id)sender {
    (void)sender;
    [self findFromCurrentForward:YES];
}

- (void)findPrevious:(id)sender {
    (void)sender;
    [self findFromCurrentForward:NO];
}

- (void)findFromCurrentForward:(BOOL)forward {
    if (!_doc || _searchField.stringValue.length == 0) return;

    if (_findMatches.count == 0) {
        [self startFindForCurrentQuery];
        return;
    }
    NSInteger next = _findMatchIndex;
    if (next < 0)
        next = forward ? 0 : (NSInteger)_findMatches.count - 1;
    else
        next = (next + (forward ? 1 : -1) + (NSInteger)_findMatches.count) % (NSInteger)_findMatches.count;
    [self jumpToFindMatchAtIndex:next];
}

- (void)controlTextDidChange:(NSNotification*)notification {
    if (notification.object == _searchField) {
        [self startFindForCurrentQuery];
    } else if (notification.object == _paletteSearchField) {
        [self refreshPaletteResults];
    }
}

- (BOOL)control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)commandSelector {
    (void)textView;
    if (control != _paletteSearchField) return NO;
    if (commandSelector == @selector(moveDown:)) {
        [self paletteMoveSelection:1];
        return YES;
    }
    if (commandSelector == @selector(moveUp:)) {
        [self paletteMoveSelection:-1];
        return YES;
    }
    if (commandSelector == @selector(insertNewline:) || commandSelector == @selector
                                                            (insertNewlineIgnoringFieldEditor:)) {
        [self activatePaletteSelection:control];
        return YES;
    }
    if (commandSelector == @selector(cancelOperation:)) {
        [self closePalette:control];
        return YES;
    }
    return NO;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    if (tableView == _paletteTable) return (NSInteger)_paletteResults.count;
    return (NSInteger)_sidebarItems.count;
}

- (CGFloat)tableView:(NSTableView*)tableView heightOfRow:(NSInteger)row {
    if (tableView != _paletteTable) return _sidebarTable.rowHeight;
    if (row < 0 || row >= (NSInteger)_paletteResults.count) return 42.0;
    NSString* kind = _paletteResults[(NSUInteger)row][@"kind"];
    if ([kind isEqualToString:@"header"]) return 28.0;
    if ([kind isEqualToString:@"separator"]) return 10.0;
    if ([kind isEqualToString:@"status"]) return 36.0;
    return 42.0;
}

- (NSIndexSet*)tableView:(NSTableView*)tableView
    selectionIndexesForProposedSelection:(NSIndexSet*)proposedSelectionIndexes {
    if (tableView != _paletteTable) return proposedSelectionIndexes;
    NSMutableIndexSet* filtered = [NSMutableIndexSet indexSet];
    [proposedSelectionIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL* stop) {
      (void)stop;
      if (idx < self->_paletteResults.count && [self isSelectablePaletteResult:self->_paletteResults[idx]])
          [filtered addIndex:idx];
    }];
    return filtered;
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
    (void)tableColumn;
    if (tableView == _paletteTable) {
        NSDictionary* result = _paletteResults[(NSUInteger)row];
        NSString* kind = result[@"kind"];
        if ([kind isEqualToString:@"separator"]) {
            NSView* view = [tableView makeViewWithIdentifier:@"PaletteSeparator" owner:self];
            if (!view) {
                view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 620, 10)];
                view.identifier = @"PaletteSeparator";
                NSBox* line = [[NSBox alloc] init];
                line.translatesAutoresizingMaskIntoConstraints = NO;
                line.boxType = NSBoxSeparator;
                [view addSubview:line];
                [NSLayoutConstraint activateConstraints:@[
                    [line.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:12],
                    [line.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-12],
                    [line.centerYAnchor constraintEqualToAnchor:view.centerYAnchor]
                ]];
            }
            return view;
        }

        NSTableCellView* cell = [tableView makeViewWithIdentifier:@"PaletteCell" owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 620, 44)];
            cell.identifier = @"PaletteCell";

            NSTextField* title = [NSTextField labelWithString:@""];
            title.translatesAutoresizingMaskIntoConstraints = NO;
            title.lineBreakMode = NSLineBreakByTruncatingMiddle;
            title.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
            cell.textField = title;
            [cell addSubview:title];

            NSTextField* subtitle = [NSTextField labelWithString:@""];
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

        cell.textField.stringValue = result[@"title"] ?: @"";
        BOOL header = [kind isEqualToString:@"header"];
        BOOL status = [kind isEqualToString:@"status"];
        cell.textField.font = header ? [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold]
                                     : [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        cell.textField.textColor = header || status ? NSColor.secondaryLabelColor : NSColor.labelColor;
        for (NSView* subview in cell.subviews) {
            if ([subview.identifier isEqualToString:@"subtitle"]) {
                ((NSTextField*)subview).stringValue = header ? @"" : result[@"subtitle"] ?: @"";
                ((NSTextField*)subview).textColor = NSColor.secondaryLabelColor;
            }
        }
        return cell;
    }

    NSTableCellView* cell = [tableView makeViewWithIdentifier:@"SidebarCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 230, 25)];
        cell.identifier = @"SidebarCell";
        NSTextField* field = [NSTextField labelWithString:@""];
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

    NSDictionary* item = _sidebarItems[(NSUInteger)row];
    NSInteger level = [item[@"level"] integerValue];
    NSString* indent = [@"" stringByPaddingToLength:(NSUInteger)(level * 3) withString:@" " startingAtIndex:0];
    cell.textField.stringValue = [indent stringByAppendingString:item[@"title"]];
    cell.textField.font = [NSFont systemFontOfSize:13];
    cell.textField.textColor = [item[@"page"] integerValue] >= 0 ? NSColor.labelColor : NSColor.secondaryLabelColor;
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
    if (notification.object == _paletteTable) return;
    if (_updatingSelection) return;
    NSInteger row = _sidebarTable.selectedRow;
    if (row < 0 || row >= (NSInteger)_sidebarItems.count) return;
    NSInteger page = [_sidebarItems[(NSUInteger)row][@"page"] integerValue];
    if (page >= 0 && page != _pageIndex) {
        _pageIndex = page;
        _pageView.currentPageIndex = _pageIndex;
        [self resizeDocumentView];
        [self scrollToPage:_pageIndex alignTop:YES];
        [self updateControls];
    }
}

- (BOOL)validateMenuItem:(NSMenuItem*)menuItem {
    SEL action = menuItem.action;
    BOOL hasDoc = _doc != NULL;
    if (action == @selector(openDocument:) || action == @selector(toggleFullScreen:) ||
        action == @selector(showFavoritesPalette:) || action == @selector(showFindPalette:) ||
        action == @selector(focusFind:))
        return YES;
    if (action == @selector(copySelection:)) return _selectedText.length > 0;
    if (action == @selector(ocrDocument:))
        return hasDoc && [_path.pathExtension.lowercaseString isEqualToString:@"pdf"];
    if (action == @selector(showInFolder:)) return hasDoc && _path.length > 0;
    if (action == @selector(copyCurrentPageImage:))
        return hasDoc && _pageIndex >= 0 && _pageIndex < (NSInteger)_renderedPages.count &&
               _renderedPages[(NSUInteger)_pageIndex].image != nil;
    if (!hasDoc) return action == @selector(unimplementedMenuItem:);

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
        menuItem.state = _sidebarPreferredVisible ? NSControlStateValueOn : NSControlStateValueOff;

    return YES;
}

- (void)showError:(NSString*)message detail:(NSString*)detail {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = message;
    alert.informativeText = detail ?: @"";
    alert.alertStyle = NSAlertStyleWarning;
    [alert runModal];
}

@end

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        for (int i = 1; i < argc; ++i) {
            if (strcmp(argv[i], "--version") == 0) {
                printf("SumatraPDF portable mac 0.5\n");
                return 0;
            }
        }

        NSApplication* app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyRegular;

        SumatraMacDelegate* delegate = [[SumatraMacDelegate alloc] init];
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
