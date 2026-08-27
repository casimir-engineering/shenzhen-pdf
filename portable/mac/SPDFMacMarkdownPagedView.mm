#import "SPDFMacMarkdownPagedView.h"

#import "SPDFMacMarkdownPageCanvas.h"
#import "markdown/SPDFMarkdownPaginator.h"

static const CGFloat kSPDFMarkdownMinimumZoom = 0.10;
static const CGFloat kSPDFMarkdownMaximumZoom = 5.00;
static const CGFloat kSPDFMarkdownFitInset = 48.0;

@implementation SPDFMacMarkdownPagedView {
    SPDFMacMarkdownPageCanvas* _canvas;
    SPDFMarkdownPaginationPlan* _plan;
    NSAttributedString* _attributedString;
    NSInteger _currentPageIndex;
    BOOL _updatingGeometry;
}

- (instancetype)initWithPaginationPlan:(SPDFMarkdownPaginationPlan*)plan
                      attributedString:(NSAttributedString*)attributedString {
    self = [super initWithFrame:NSZeroRect];
    if (!self) return nil;
    _plan = plan;
    _attributedString = [attributedString copy];
    _currentPageIndex = 0;
    _fitMode = SPDFMacMarkdownPageFitPage;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.borderType = NSNoBorder;
    self.drawsBackground = YES;
    self.backgroundColor = NSColor.windowBackgroundColor;
    self.hasVerticalScroller = YES;
    self.hasHorizontalScroller = NO;
    self.autohidesScrollers = NO;
    self.usesPredominantAxisScrolling = NO;
    self.verticalScrollElasticity = NSScrollElasticityAllowed;
    self.horizontalScrollElasticity = NSScrollElasticityAllowed;
    self.allowsMagnification = YES;
    self.minMagnification = kSPDFMarkdownMinimumZoom;
    self.maxMagnification = kSPDFMarkdownMaximumZoom;
    _canvas = [[SPDFMacMarkdownPageCanvas alloc] initWithPaginationPlan:plan attributedString:attributedString];
    self.documentView = _canvas;
    self.contentView.postsBoundsChangedNotifications = YES;
    self.postsFrameChangedNotifications = YES;
    __weak SPDFMacMarkdownPagedView* weakSelf = self;
    _canvas.selectionChangedHandler = ^(NSRange range) {
      (void)range;
      SPDFMacMarkdownPagedView* strongSelf = weakSelf;
      if (strongSelf.viewportChangedHandler)
          strongSelf.viewportChangedHandler(strongSelf.currentPageIndex, strongSelf.magnification);
    };
    _canvas.activateDestinationHandler = ^(NSString* destination, BOOL wikiLink) {
      SPDFMacMarkdownPagedView* strongSelf = weakSelf;
      if (strongSelf.activateDestinationHandler) strongSelf.activateDestinationHandler(destination, wikiLink);
    };
    _canvas.chooseCodeLanguageHandler = ^(NSUInteger blockIndex) {
      SPDFMacMarkdownPagedView* strongSelf = weakSelf;
      if (strongSelf.chooseCodeLanguageHandler) strongSelf.chooseCodeLanguageHandler(blockIndex);
    };
    NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
    [center addObserver:self
               selector:@selector(viewportDidChange:)
                   name:NSViewBoundsDidChangeNotification
                 object:self.contentView];
    [center addObserver:self
               selector:@selector(viewportFrameDidChange:)
                   name:NSViewFrameDidChangeNotification
                 object:self];
    [center addObserver:self
               selector:@selector(magnificationDidChange:)
                   name:NSScrollViewDidEndLiveMagnifyNotification
                 object:self];
    [self updateCanvasGeometryPreservingCenter:NO];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (void)setReader:(id<SPDFMacUIReader>)reader {
    [super setReader:reader];
    _canvas.reader = reader;
}
- (NSUInteger)pageCount {
    return _canvas.pageCount;
}
- (NSInteger)currentPageIndex {
    return _currentPageIndex;
}
- (NSUInteger)visibleAttributedLocation {
    NSRect visible = self.documentVisibleRect;
    return [_canvas attributedLocationNearestToPoint:NSMakePoint(NSMidX(visible), NSMinY(visible))];
}
- (NSArray<NSValue*>*)documentPageRects {
    NSMutableArray<NSValue*>* rects = [NSMutableArray arrayWithCapacity:self.pageCount];
    for (NSUInteger pageIndex = 0; pageIndex < self.pageCount; ++pageIndex)
        [rects addObject:[NSValue valueWithRect:[_canvas frameForPageAtIndex:pageIndex]]];
    return rects;
}
- (NSSize)documentCanvasSize {
    return _canvas.bounds.size;
}
- (NSRange)selectedRange {
    return _canvas.selectedRange;
}
- (void)setSelectedRange:(NSRange)selectedRange {
    _canvas.selectedRange = selectedRange;
}
- (NSArray<NSValue*>*)searchRanges {
    return _canvas.searchRanges;
}
- (void)setSearchRanges:(NSArray<NSValue*>*)searchRanges {
    _canvas.searchRanges = searchRanges;
}
- (NSString*)selectedText {
    NSRange range = self.selectedRange;
    if (!range.length || NSMaxRange(range) > _attributedString.length) return @"";
    return [_attributedString.string substringWithRange:range];
}

- (void)updateCanvasGeometryPreservingCenter:(BOOL)preserveCenter {
    if (_updatingGeometry) return;
    _updatingGeometry = YES;
    NSPoint center = NSMakePoint(NSMidX(self.contentView.bounds), NSMidY(self.contentView.bounds));
    CGFloat width = MAX(_plan.configuration.paperSize.width + kSPDFMarkdownFitInset, NSWidth(self.contentView.bounds));
    [_canvas resizeForWidth:width];
    if (preserveCenter) {
        [self.contentView scrollToPoint:NSMakePoint(MAX(0, center.x - NSWidth(self.contentView.bounds) * 0.5),
                                                    MAX(0, center.y - NSHeight(self.contentView.bounds) * 0.5))];
        [self reflectScrolledClipView:self.contentView];
    }
    _updatingGeometry = NO;
}

- (void)viewportDidChange:(NSNotification*)notification {
    (void)notification;
    if (_updatingGeometry) return;
    NSInteger page = [_canvas pageIndexForVisibleRect:_canvas.visibleRect];
    if (page >= 0) _currentPageIndex = page;
    if (self.viewportChangedHandler) self.viewportChangedHandler(_currentPageIndex, self.magnification);
}

- (void)viewportFrameDidChange:(NSNotification*)notification {
    (void)notification;
    [self updateCanvasGeometryPreservingCenter:YES];
    if (_fitMode != SPDFMacMarkdownPageFitCustom && _fitMode != SPDFMacMarkdownPageFitActual)
        [self applyFitMode:_fitMode];
}

- (void)magnificationDidChange:(NSNotification*)notification {
    (void)notification;
    _fitMode = SPDFMacMarkdownPageFitCustom;
    [self viewportDidChange:nil];
}

- (void)setPresentationMode:(BOOL)presentationMode {
    if (_presentationMode == presentationMode) return;
    _presentationMode = presentationMode;
    self.hasVerticalScroller = !presentationMode;
    self.autohidesScrollers = presentationMode;
    self.backgroundColor = presentationMode ? NSColor.blackColor : NSColor.windowBackgroundColor;
    self.contentView.backgroundColor = self.backgroundColor;
    _canvas.presentationMode = presentationMode;
    [_canvas setNeedsDisplay:YES];
}

- (void)setZoom:(CGFloat)zoom centeredAtPoint:(NSPoint)point {
    _fitMode = fabs(zoom - 1.0) < 0.0001 ? SPDFMacMarkdownPageFitActual : SPDFMacMarkdownPageFitCustom;
    [self setMagnification:MAX(kSPDFMarkdownMinimumZoom, MIN(kSPDFMarkdownMaximumZoom, zoom)) centeredAtPoint:point];
    [self viewportDidChange:nil];
}

- (void)zoomByFactor:(CGFloat)factor {
    NSRect visible = _canvas.visibleRect;
    [self setZoom:self.magnification * factor centeredAtPoint:NSMakePoint(NSMidX(visible), NSMidY(visible))];
}

- (CGFloat)zoomForFitMode:(SPDFMacMarkdownPageFitMode)fitMode {
    NSSize viewport = self.contentSize;
    NSSize paper = _plan.configuration.paperSize;
    CGFloat width = MAX(1, viewport.width - kSPDFMarkdownFitInset) / paper.width;
    CGFloat height = MAX(1, viewport.height - kSPDFMarkdownFitInset) / paper.height;
    if (fitMode == SPDFMacMarkdownPageFitWidth) return width;
    if (fitMode == SPDFMacMarkdownPageFitHeight) return height;
    if (fitMode == SPDFMacMarkdownPageFitPage) return MIN(width, height);
    if (fitMode == SPDFMacMarkdownPageFitActual) return 1.0;
    return self.magnification;
}

- (void)applyFitMode:(SPDFMacMarkdownPageFitMode)fitMode {
    _fitMode = fitMode;
    CGFloat zoom = MAX(kSPDFMarkdownMinimumZoom, MIN(kSPDFMarkdownMaximumZoom, [self zoomForFitMode:fitMode]));
    NSRect page = [_canvas frameForPageAtIndex:(NSUInteger)MAX(0, _currentPageIndex)];
    [self setMagnification:zoom centeredAtPoint:NSMakePoint(NSMidX(page), NSMidY(page))];
    _fitMode = fitMode;
    [self viewportDidChange:nil];
}

- (void)setFitMode:(SPDFMacMarkdownPageFitMode)fitMode {
    if (_fitMode == fitMode && fitMode == SPDFMacMarkdownPageFitCustom) return;
    [self applyFitMode:fitMode];
}

- (void)goToPageAtIndex:(NSInteger)pageIndex alignTop:(BOOL)alignTop {
    if (!self.pageCount) return;
    pageIndex = MAX(0, MIN(pageIndex, (NSInteger)self.pageCount - 1));
    NSRect page = [_canvas frameForPageAtIndex:(NSUInteger)pageIndex];
    NSRect target = alignTop ? NSMakeRect(NSMinX(page), NSMinY(page), NSWidth(page), 1.0) : page;
    [_canvas scrollRectToVisible:target];
    _currentPageIndex = pageIndex;
    if (self.viewportChangedHandler) self.viewportChangedHandler(_currentPageIndex, self.magnification);
}

- (BOOL)revealRange:(NSRange)range {
    BOOL revealed = [_canvas scrollRangeToVisible:range];
    if (revealed) {
        _currentPageIndex = (NSInteger)[_canvas pageIndexForRange:range];
        if (self.viewportChangedHandler) self.viewportChangedHandler(_currentPageIndex, self.magnification);
    }
    return revealed;
}

- (NSUInteger)pageIndexForRange:(NSRange)range {
    return [_canvas pageIndexForRange:range];
}

- (void)scrollToDocumentOrigin:(NSPoint)origin {
    NSRect visible = self.documentVisibleRect;
    NSSize canvas = self.documentCanvasSize;
    origin.x = MAX(0.0, MIN(origin.x, MAX(0.0, canvas.width - NSWidth(visible))));
    origin.y = MAX(0.0, MIN(origin.y, MAX(0.0, canvas.height - NSHeight(visible))));
    [self.contentView scrollToPoint:origin];
    [self reflectScrolledClipView:self.contentView];
    [self viewportDidChange:nil];
}

- (void)centerAtDocumentPoint:(NSPoint)point {
    NSRect visible = self.documentVisibleRect;
    [self scrollToDocumentOrigin:NSMakePoint(point.x - NSWidth(visible) * 0.5, point.y - NSHeight(visible) * 0.5)];
}

- (void)centerOnPageAtIndex:(NSInteger)pageIndex xFraction:(CGFloat)xFraction yFraction:(CGFloat)yFraction {
    if (!self.pageCount) return;
    pageIndex = MAX(0, MIN(pageIndex, (NSInteger)self.pageCount - 1));
    NSRect page = [_canvas frameForPageAtIndex:(NSUInteger)pageIndex];
    xFraction = MAX(0.0, MIN(1.0, xFraction));
    yFraction = MAX(0.0, MIN(1.0, yFraction));
    [self centerAtDocumentPoint:NSMakePoint(NSMinX(page) + xFraction * NSWidth(page),
                                            NSMinY(page) + yFraction * NSHeight(page))];
}

- (void)scrollByDocumentDeltaX:(CGFloat)deltaX deltaY:(CGFloat)deltaY {
    NSPoint origin = self.documentVisibleRect.origin;
    [self scrollToDocumentOrigin:NSMakePoint(origin.x + deltaX, origin.y + deltaY)];
}

- (void)forwardScrollWheelEvent:(NSEvent*)event {
    [super scrollWheel:event];
}

- (void)magnifyByDelta:(CGFloat)delta {
    [self magnifyByDelta:delta
        centeredAtDocumentPoint:NSMakePoint(NSMidX(self.documentVisibleRect), NSMidY(self.documentVisibleRect))];
}

- (BOOL)zoomWithScrollWheelEvent:(NSEvent*)event centeredAtWindowPoint:(NSPoint)windowPoint {
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    if (!(flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl))) return NO;
    CGFloat delta = event.scrollingDeltaY != 0.0 ? event.scrollingDeltaY : event.deltaY;
    NSPoint documentPoint = [_canvas convertPoint:windowPoint fromView:nil];
    [self setZoom:self.magnification * pow(1.00135, delta) centeredAtPoint:documentPoint];
    return YES;
}

- (void)magnifyByDelta:(CGFloat)delta centeredAtWindowPoint:(NSPoint)windowPoint {
    [self magnifyByDelta:delta centeredAtDocumentPoint:[_canvas convertPoint:windowPoint fromView:nil]];
}

- (void)magnifyByDelta:(CGFloat)delta centeredAtDocumentPoint:(NSPoint)documentPoint {
    CGFloat factor = MAX(0.1, 1.0 + delta * 0.82);
    [self setZoom:self.magnification * factor centeredAtPoint:documentPoint];
}

- (void)noteExternalScrollPositionChanged {
    [self viewportDidChange:nil];
}

@end
