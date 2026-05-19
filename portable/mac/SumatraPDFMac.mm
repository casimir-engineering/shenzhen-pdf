#import <Cocoa/Cocoa.h>

#include "sumatra_pdf_core.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static const CGFloat kPageMargin = 44.0;
static const CGFloat kPageGap = 26.0;
static const CGFloat kMinZoom = 0.10;
static const CGFloat kMaxZoom = 8.00;

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

@interface SPDFScrollView : NSScrollView
@property(nonatomic, weak) SumatraMacDelegate *reader;
@end

@interface SPDFDocumentView : NSView
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
- (void)documentScrollPositionChanged;
- (void)documentViewSelectionChangedOnPage:(NSInteger)pageIndex from:(NSPoint)start to:(NSPoint)end;
- (void)copySelection:(id)sender;
@end

@implementation SPDFScrollView {
    CGFloat _wheelAccumulator;
}

- (void)scrollWheel:(NSEvent *)event
{
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    if (self.reader && (flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl))) {
        CGFloat delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY;
        CGFloat factor = pow(1.0018, delta);
        [self.reader zoomByFactor:factor centeredAtWindowPoint:event.locationInWindow];
        return;
    }

    if (self.reader && [self.reader scrollViewShouldTurnWheelIntoPageChange:event]) {
        CGFloat delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY;
        _wheelAccumulator += delta;
        CGFloat threshold = event.hasPreciseScrollingDeltas ? 6.0 : 1.0;
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
        [self.reader zoomByFactor:1.0 + event.magnification centeredAtWindowPoint:event.locationInWindow];
}

@end

@implementation SPDFDocumentView {
    BOOL _isPanning;
    BOOL _isSelecting;
    NSPoint _panStartInWindow;
    NSPoint _panStartOrigin;
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
        widest = MAX(widest, page.image ? page.image.size.width : page.pageWidth * self.zoom);
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
        CGFloat pageHeight = page.image ? page.image.size.height : page.pageHeight * self.zoom;
        height = pageHeight + kPageMargin;
    } else {
        height = kPageMargin / 2.0;
        for (SPDFRenderedPage *page in self.pages) {
            CGFloat pageHeight = page.image ? page.image.size.height : page.pageHeight * self.zoom;
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
            y += (prev.image ? prev.image.size.height : prev.pageHeight * self.zoom) + kPageGap;
        }
    }

    SPDFRenderedPage *page = self.pages[(NSUInteger)pageIndex];
    CGFloat width = page.image ? page.image.size.width : page.pageWidth * self.zoom;
    CGFloat height = page.image ? page.image.size.height : page.pageHeight * self.zoom;
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
        [[NSColor selectedTextBackgroundColor] setFill];
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
    [[NSColor colorWithCalibratedWhite:0.58 alpha:1.0] setFill];
    NSRectFill(self.bounds);

    if (self.pages.count == 0) {
        NSDictionary *attrs = @{NSForegroundColorAttributeName: [NSColor whiteColor],
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
    _isPanning = YES;
    _panStartInWindow = event.locationInWindow;
    _panStartOrigin = scrollView.contentView.bounds.origin;
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
    origin.x = MAX(0, MIN(origin.x, MAX(0, NSWidth(self.bounds) - NSWidth(clipView.bounds))));
    origin.y = MAX(0, MIN(origin.y, MAX(0, NSHeight(self.bounds) - NSHeight(clipView.bounds))));
    [clipView scrollToPoint:origin];
    [scrollView reflectScrolledClipView:clipView];
}

- (void)endPan
{
    _isPanning = NO;
    [[NSCursor arrowCursor] set];
}

- (void)rightMouseDown:(NSEvent *)event
{
    [self beginPanWithEvent:event];
}

- (void)rightMouseDragged:(NSEvent *)event
{
    [self continuePanWithEvent:event];
}

- (void)rightMouseUp:(NSEvent *)event
{
    (void)event;
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

    spdf_document *_doc;
    spdf_outline _outline;
    NSMutableArray<NSDictionary *> *_sidebarItems;
    NSMutableArray<SPDFRenderedPage *> *_renderedPages;
    NSString *_path;
    NSString *_pendingOpenPath;
    NSInteger _pageIndex;
    NSInteger _highlightPageIndex;
    NSInteger _selectionPageIndex;
    NSString *_selectedText;
    CGFloat _zoom;
    SPDFFitMode _fitMode;
    SPDFViewMode _viewMode;
    NSUInteger _renderGeneration;
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

    [self buildMenu];
    [self buildWindow];
    _uiReady = YES;
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    NSString *path = _pendingOpenPath ?: self.initialPath;
    if (path.length > 0)
        [self openPath:path];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    (void)sender;
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    (void)notification;
    spdf_free_outline(&_outline);
    spdf_close(_doc);
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename
{
    (void)sender;
    if (!_uiReady) {
        _pendingOpenPath = [filename copy];
        return YES;
    }
    [self openPath:filename];
    return YES;
}

- (void)application:(NSApplication *)application openFiles:(NSArray<NSString *> *)filenames
{
    (void)application;
    if (filenames.count > 0) {
        if (!_uiReady)
            _pendingOpenPath = [filenames.firstObject copy];
        else
            [self openPath:filenames.firstObject];
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
    [viewMenu addItemWithTitle:@"Show Sidebar" action:@selector(toggleSidebar:) keyEquivalent:@"b"];
    [viewMenu addItemWithTitle:@"Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"f"];
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
    [favoritesMenu addItemWithTitle:@"Add Page to Favorites" action:@selector(unimplementedMenuItem:) keyEquivalent:@"d"];
    [favoritesMenu addItemWithTitle:@"Manage Favorites..." action:@selector(unimplementedMenuItem:) keyEquivalent:@""];
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

    NSView *content = [[NSView alloc] initWithFrame:frame];
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
    _pageScrollView.contentView.postsBoundsChangedNotifications = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clipViewBoundsChanged:) name:NSViewBoundsDidChangeNotification object:_pageScrollView.contentView];

    _pageView = [[SPDFDocumentView alloc] initWithFrame:NSMakeRect(0, 0, 800, 1000)];
    _pageView.reader = self;
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

- (SPDFRenderedPage *)renderedPageAtIndex:(NSInteger)pageIndex error:(char *)err errorLength:(size_t)errLen
{
    float pageWidth = 0;
    float pageHeight = 0;
    if (!spdf_page_size(_doc, (int)pageIndex, &pageWidth, &pageHeight, err, errLen))
        return nil;

    CGFloat displayScale = [self backingScale];
    spdf_bitmap bitmap;
    if (!spdf_render_page_rgba(_doc, (int)pageIndex, (float)(_zoom * displayScale), &bitmap, err, errLen))
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

    NSSize pointSize = NSMakeSize(pageWidth * _zoom, pageHeight * _zoom);
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

- (SPDFRenderedPage *)placeholderPageAtIndex:(NSInteger)pageIndex error:(char *)err errorLength:(size_t)errLen
{
    float pageWidth = 0;
    float pageHeight = 0;
    if (!spdf_page_size(_doc, (int)pageIndex, &pageWidth, &pageHeight, err, errLen))
        return nil;

    SPDFRenderedPage *page = [[SPDFRenderedPage alloc] init];
    page.pageIndex = pageIndex;
    page.pageWidth = pageWidth;
    page.pageHeight = pageHeight;
    page.highlights = @[];
    page.selectionRects = @[];
    return page;
}

- (void)renderRemainingPagesFromIndex:(NSInteger)index generation:(NSUInteger)generation preferredPage:(NSInteger)preferredPage
{
    if (generation != _renderGeneration || !_doc)
        return;
    NSInteger pageCount = spdf_page_count(_doc);
    if (index >= pageCount)
        return;

    if (index == preferredPage) {
        [self renderRemainingPagesFromIndex:index + 1 generation:generation preferredPage:preferredPage];
        return;
    }

    char err[1024];
    SPDFRenderedPage *page = [self renderedPageAtIndex:index error:err errorLength:sizeof(err)];
    if (generation != _renderGeneration || !_doc)
        return;
    if (page && index < (NSInteger)_renderedPages.count) {
        [_renderedPages replaceObjectAtIndex:(NSUInteger)index withObject:page];
        [self applySearchHighlightsToCurrentPage];
        [self resizeDocumentView];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self renderRemainingPagesFromIndex:index + 1 generation:generation preferredPage:preferredPage];
    });
}

- (void)renderDocumentAndScrollToPage:(NSInteger)pageIndex alignTop:(BOOL)alignTop
{
    if (!_doc || !_uiReady)
        return;

    [_window.contentView layoutSubtreeIfNeeded];
    _renderGeneration++;
    NSUInteger generation = _renderGeneration;
    _zoom = [self zoomForFitMode:_fitMode pageIndex:MAX(0, pageIndex)];
    NSMutableArray<SPDFRenderedPage *> *pages = [NSMutableArray arrayWithCapacity:(NSUInteger)spdf_page_count(_doc)];
    char err[1024];
    NSInteger pageCount = spdf_page_count(_doc);
    for (NSInteger i = 0; i < pageCount; ++i) {
        SPDFRenderedPage *page = nil;
        if (i == pageIndex)
            page = [self renderedPageAtIndex:i error:err errorLength:sizeof(err)];
        else
            page = [self placeholderPageAtIndex:i error:err errorLength:sizeof(err)];
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

    dispatch_async(dispatch_get_main_queue(), ^{
        [self renderRemainingPagesFromIndex:0 generation:generation preferredPage:pageIndex];
    });
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

- (void)closeDocument:(id)sender
{
    (void)sender;
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
    _pageIndex = 0;
    _highlightPageIndex = -1;
    _selectionPageIndex = -1;
    _selectedText = nil;
    _renderGeneration++;
    _zoom = 1.0;
    _fitMode = SPDFFitModeWidth;
    _viewMode = SPDFViewModeContinuous;

    [self rebuildSidebar];
    _statusLabel.stringValue = @"Opening...";
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!_doc)
            return;
        [self renderDocumentAndScrollToPage:0 alignTop:YES];
        char outlineErr[1024];
        if (_doc && !spdf_load_outline(_doc, &_outline, outlineErr, sizeof(outlineErr)))
            _statusLabel.stringValue = [NSString stringWithFormat:@"Opened, but outline was not available: %s", outlineErr];
        if (_sidebarModeControl.selectedSegment == 1)
            [self rebuildSidebar];
    });
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

- (void)previousPage:(id)sender
{
    (void)sender;
    if (_doc && _pageIndex > 0) {
        _pageIndex--;
        _pageView.currentPageIndex = _pageIndex;
        [self resizeDocumentView];
        [self scrollToPage:_pageIndex alignTop:YES];
        [self updateControls];
        [self selectCurrentSidebarRow];
        [_pageView setNeedsDisplay:YES];
    }
}

- (void)nextPage:(id)sender
{
    (void)sender;
    if (_doc && _pageIndex + 1 < spdf_page_count(_doc)) {
        _pageIndex++;
        _pageView.currentPageIndex = _pageIndex;
        [self resizeDocumentView];
        [self scrollToPage:_pageIndex alignTop:YES];
        [self updateControls];
        [self selectCurrentSidebarRow];
        [_pageView setNeedsDisplay:YES];
    }
}

- (void)firstPage:(id)sender
{
    (void)sender;
    if (_doc) {
        _pageIndex = 0;
        _pageView.currentPageIndex = _pageIndex;
        [self resizeDocumentView];
        [self scrollToPage:_pageIndex alignTop:YES];
        [self updateControls];
        [self selectCurrentSidebarRow];
    }
}

- (void)lastPage:(id)sender
{
    (void)sender;
    if (_doc) {
        _pageIndex = spdf_page_count(_doc) - 1;
        _pageView.currentPageIndex = _pageIndex;
        [self resizeDocumentView];
        [self scrollToPage:_pageIndex alignTop:YES];
        [self updateControls];
        [self selectCurrentSidebarRow];
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
    [self resizeDocumentView];
    [self scrollToPage:_pageIndex alignTop:YES];
    [self updateControls];
    [self selectCurrentSidebarRow];
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
}

- (void)fitWidth:(id)sender
{
    (void)sender;
    if (!_doc)
        return;
    _fitMode = SPDFFitModeWidth;
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO];
}

- (void)fitHeight:(id)sender
{
    (void)sender;
    if (!_doc)
        return;
    _fitMode = SPDFFitModeHeight;
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:YES];
}

- (void)fitPage:(id)sender
{
    (void)sender;
    if (!_doc)
        return;
    _fitMode = SPDFFitModePage;
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:YES];
}

- (void)fitModePopupChanged:(id)sender
{
    (void)sender;
    _fitMode = (SPDFFitMode)_fitModePopup.indexOfSelectedItem;
    if (_doc)
        [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO];
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

- (void)unimplementedMenuItem:(id)sender
{
    (void)sender;
    NSBeep();
    _statusLabel.stringValue = @"This SumatraPDF command is listed but not implemented yet.";
}

- (void)focusFind:(id)sender
{
    (void)sender;
    [_window makeFirstResponder:_searchField];
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
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    (void)tableView;
    return (NSInteger)_sidebarItems.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    (void)tableColumn;
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
    (void)notification;
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
    if (action == @selector(openDocument:) || action == @selector(toggleFullScreen:))
        return YES;
    if (action == @selector(copySelection:))
        return _selectedText.length > 0;
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
                printf("SumatraPDF portable mac 0.3\n");
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
