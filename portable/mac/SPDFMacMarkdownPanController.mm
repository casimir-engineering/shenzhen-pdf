#import "SPDFMacMarkdownPanController.h"

@implementation SPDFMacMarkdownPanController {
    __weak NSView* _documentView;
    NSTimer* _inertiaTimer;
    NSPoint _panStartInWindow;
    NSPoint _panStartOrigin;
    NSPoint _lastPanPoint;
    NSTimeInterval _lastPanTime;
    NSPoint _panVelocity;
    BOOL _panning;
    BOOL _moved;
}

- (instancetype)initWithDocumentView:(NSView*)documentView {
    NSParameterAssert(documentView);
    self = [super init];
    if (!self) return nil;
    _documentView = documentView;
    return self;
}

- (BOOL)isPanning {
    return _panning;
}

- (NSScrollView*)scrollView {
    return _documentView.enclosingScrollView;
}

- (void)scrollToOrigin:(NSPoint)origin {
    NSScrollView* scrollView = self.scrollView;
    NSClipView* clipView = scrollView.contentView;
    if (!scrollView || !clipView) return;
    NSRect bounds = clipView.bounds;
    bounds.origin = origin;
    [clipView scrollToPoint:[clipView constrainBoundsRect:bounds].origin];
    [scrollView reflectScrolledClipView:clipView];
}

- (void)beginAtWindowPoint:(NSPoint)windowPoint timestamp:(NSTimeInterval)timestamp {
    NSScrollView* scrollView = self.scrollView;
    if (!scrollView) return;
    [self cancel];
    _panning = YES;
    _moved = NO;
    _panStartInWindow = windowPoint;
    _panStartOrigin = scrollView.contentView.bounds.origin;
    _lastPanPoint = windowPoint;
    _lastPanTime = timestamp;
    _panVelocity = NSZeroPoint;
    [NSCursor.closedHandCursor set];
}

- (void)continueAtWindowPoint:(NSPoint)windowPoint timestamp:(NSTimeInterval)timestamp {
    if (!_panning) return;
    _moved = YES;
    NSPoint delta = NSMakePoint(windowPoint.x - _panStartInWindow.x, windowPoint.y - _panStartInWindow.y);
    [self scrollToOrigin:NSMakePoint(_panStartOrigin.x - delta.x, _panStartOrigin.y + delta.y)];
    NSTimeInterval elapsed = MAX(0.001, timestamp - _lastPanTime);
    _panVelocity =
        NSMakePoint((windowPoint.x - _lastPanPoint.x) / elapsed, (windowPoint.y - _lastPanPoint.y) / elapsed);
    _lastPanPoint = windowPoint;
    _lastPanTime = timestamp;
}

- (void)stepInertia:(NSTimer*)timer {
    if (!self.scrollView) {
        [self cancel];
        return;
    }
    NSPoint origin = self.scrollView.contentView.bounds.origin;
    [self scrollToOrigin:NSMakePoint(origin.x - _panVelocity.x / 60.0, origin.y + _panVelocity.y / 60.0)];
    _panVelocity.x *= 0.90;
    _panVelocity.y *= 0.90;
    if (hypot(_panVelocity.x, _panVelocity.y) >= 12.0) return;
    [timer invalidate];
    _inertiaTimer = nil;
    _panVelocity = NSZeroPoint;
}

- (void)end {
    if (!_panning) return;
    _panning = NO;
    _moved = NO;
    [NSCursor.arrowCursor set];
    if (self.panDidEndHandler) self.panDidEndHandler();
    if (hypot(_panVelocity.x, _panVelocity.y) <= 90.0) {
        _panVelocity = NSZeroPoint;
        return;
    }
    [_inertiaTimer invalidate];
    _inertiaTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
                                                     target:self
                                                   selector:@selector(stepInertia:)
                                                   userInfo:nil
                                                    repeats:YES];
}

- (void)cancel {
    BOOL wasPanning = _panning;
    [_inertiaTimer invalidate];
    _inertiaTimer = nil;
    _panning = NO;
    _panVelocity = NSZeroPoint;
    [NSCursor.arrowCursor set];
    if (wasPanning && self.panDidEndHandler) self.panDidEndHandler();
}

- (void)dealloc {
    [_inertiaTimer invalidate];
}

@end
