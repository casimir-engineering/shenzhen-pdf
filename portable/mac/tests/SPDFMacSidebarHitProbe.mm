#import "SPDFMacSidebarHitProbe.h"
#import "SPDFMacSidebarModeControl.h"
#import <objc/runtime.h>

static IMP OriginalWindowOrder;
static void GuardWindowOrder(id object,SEL action,NSInteger place,NSInteger other) {
    // AppKit can close its own text-input helper windows during event dispatch.
    if (place == NSWindowOut) {
        ((void(*)(id,SEL,NSInteger,NSInteger))OriginalWindowOrder)(object,action,place,other); return;
    }
    fprintf(stderr,"FAIL: headless reader attempted to display a window\n"); exit(1);
}
void spdf_sidebar_probe_install_order_guard(void) {
    OriginalWindowOrder=method_setImplementation(class_getInstanceMethod(NSWindow.class,@selector(orderWindow:relativeTo:)),(IMP)GuardWindowOrder);
}
static void OrderInvisible(NSWindow* window,NSInteger place) {
    if (window.alphaValue != 0 || NSMaxX(window.frame) >= -1000) {
        fprintf(stderr,"FAIL: click probe must remain transparent and offscreen\n"); exit(1);
    }
    ((void(*)(id,SEL,NSInteger,NSInteger))OriginalWindowOrder)(window,@selector(orderWindow:relativeTo:),place,0);
}
static BOOL ProbeAppActive(id object,SEL selector) { (void)object; (void)selector; return YES; }
static NSRect ProbeUnconstrainedFrame(id object,SEL selector,NSRect frame,NSScreen* screen) {
    (void)object; (void)selector; (void)screen; return frame;
}
@interface ShenzhenMacDelegate (SidebarHitFixture)
- (void)sidebarModeChanged:(id)sender;
@end
@implementation ShenzhenMacDelegate (SidebarHitProbe)
- (NSUInteger)probeHistoryMouseClicks {
    NSUInteger failures=0;
    NSRect frame=_window.frame; CGFloat alpha=_window.alphaValue;
    // Swap methods, never the window's class: AppKit adds KVO subclasses while
    // realizing titlebar views, and replacing that class breaks observer cleanup.
    Method constrain=class_getInstanceMethod(NSWindow.class,@selector(constrainFrameRect:toScreen:));
    IMP oldConstrain=method_setImplementation(constrain,(IMP)ProbeUnconstrainedFrame);
    Method key=class_getInstanceMethod(NSWindow.class,@selector(isKeyWindow));
    IMP oldKey=method_setImplementation(key,(IMP)ProbeAppActive);
    _window.alphaValue=0; [_window setFrameOrigin:NSMakePoint(-10000,-10000)];
    // Unordered windows silently discard sendEvent. Realize an invisible window
    // without activating it so native frame/control routing really executes.
    OrderInvisible(_window,NSWindowBelow);
    Method active=class_getInstanceMethod(NSApplication.class,@selector(isActive));
    IMP oldActive=method_setImplementation(active,(IMP)ProbeAppActive);
    NSString* previousTitle=nil; NSInteger eventNumber=0;
    for (NSNumber* y in @[@1,@7,@14,@21,@27]) for (NSString* title in @[@"Groups",@"Search",@"Comments",@"History",@"History",@"Chapters"]) {
        [_window.contentView layoutSubtreeIfNeeded];
        NSButton* button=nil;
        for (NSButton* row in _sidebarModeControl.accessibilityChildren)
            if ([row.accessibilityLabel isEqual:title]) button=row;
        if (!button) { fprintf(stderr,"FAIL: missing %s button\n",title.UTF8String); failures++; continue; }
        NSInteger expected=button.enabled ? [_sidebarModeControl tagForSegment:button.tag] : _sidebarModeControl.spdf_selectedSidebarMode;
        NSPoint point=[button convertPoint:NSMakePoint(NSMidX(button.bounds),y.doubleValue) toView:nil];
        NSView* frameView=_window.contentView.superview;
        NSView* hit=[frameView hitTest:frameView.superview ? [frameView.superview convertPoint:point fromView:nil] : point];
        if (hit != button || NSPointInRect([_tabStrip convertPoint:point fromView:nil],_tabStrip.bounds)) {
            fprintf(stderr,"FAIL: reader overlay intercepts %s at y=%.0f\n",title.UTF8String,y.doubleValue); failures++;
        }
        NSTimeInterval timestamp=NSProcessInfo.processInfo.systemUptime;
        // Native multi-click dispatch intentionally retains the first target.
        // Only repeated clicks at the same button get a multi-click count.
        NSInteger count=[title isEqual:previousTitle] ? 2 : 1;
        NSEvent* down=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:point modifierFlags:0 timestamp:timestamp
            windowNumber:_window.windowNumber context:nil eventNumber:++eventNumber clickCount:count pressure:1];
        NSEvent* up=[NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:point modifierFlags:0 timestamp:timestamp+.01
            windowNumber:_window.windowNumber context:nil eventNumber:++eventNumber clickCount:count pressure:0];
        [NSApp postEvent:up atStart:YES]; [_window sendEvent:down];
        while ([NSApp nextEventMatchingMask:NSEventMaskLeftMouseUp|NSEventMaskLeftMouseDragged untilDate:NSDate.distantPast inMode:NSEventTrackingRunLoopMode dequeue:YES]) {}
        previousTitle=title; [_window.contentView layoutSubtreeIfNeeded];
        if (_sidebarModeControl.spdf_selectedSidebarMode != expected) {
            fprintf(stderr,"FAIL: %s did not activate at y=%.0f\n",title.UTF8String,y.doubleValue); failures++;
        }
    }
    method_setImplementation(active,oldActive);
    OrderInvisible(_window,NSWindowOut);
    method_setImplementation(constrain,oldConstrain); method_setImplementation(key,oldKey);
    [_window setFrame:frame display:NO]; _window.alphaValue=alpha;
    _sidebarModeControl.spdf_selectedSidebarMode=SPDFSidebarModeHistory; [self sidebarModeChanged:_sidebarModeControl];
    return failures;
}
@end
