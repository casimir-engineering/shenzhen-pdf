#import "SPDFMacWindowChrome.h"

#import <AppKit/AppKit.h>


SPDFWindowChromeAction spdf_window_chrome_action(NSUInteger clickCount, BOOL fullScreen, BOOL presentation,
                                                 BOOL onInteractiveControl) {
    // A click that lands on an interactive control belongs to that control:
    // never drag the window from it, and never let the second click of a
    // rapid double-click on it zoom the window. (Events still reach the
    // chrome layer from controls that decline them — a disabled control
    // forwards mouseDown up the responder chain, and a click inside a
    // segmented control's frame padding but off the visible bezel does too.)
    if (onInteractiveControl) return SPDFWindowChromeActionNone;
    if (clickCount < 2) return SPDFWindowChromeActionDrag;
    if (fullScreen || presentation) return SPDFWindowChromeActionNone;
    return SPDFWindowChromeActionZoom;
}

BOOL spdf_window_chrome_view_is_interactive(NSView* hitView) {
    // Resolved by name (not by symbol) so this file also links into the
    // Foundation-only window-chrome unit-test binary.
    Class controlClass = NSClassFromString(@"NSControl");
    Class textClass = NSClassFromString(@"NSText"); // field editors (NSTextView)
    for (NSView* view = hitView; view; view = view.superview) {
        BOOL interactiveKind =
            (controlClass && [view isKindOfClass:controlClass]) || (textClass && [view isKindOfClass:textClass]);
        if (!interactiveKind) continue;
        // Chrome drag surfaces (SPDFToolbarDragLabel is an NSTextField)
        // declare mouseDownCanMoveWindow=YES; genuine controls return NO.
        if (view.mouseDownCanMoveWindow) continue;
        return YES;
    }
    return NO;
}

SPDFWindowChromeAction spdf_window_chrome_action_for_event(NSWindow* window, NSEvent* event, BOOL fullScreen,
                                                           BOOL presentation) {
    if (!event) return SPDFWindowChromeActionNone;
    NSView* contentView = window.contentView;
    // hitTest: expects the point in the receiver's superview coordinate space.
    NSView* hitReference = contentView.superview ?: contentView;
    NSView* hitView =
        contentView ? [contentView hitTest:[hitReference convertPoint:event.locationInWindow fromView:nil]] : nil;
    return spdf_window_chrome_action(event.clickCount, fullScreen, presentation,
                                     spdf_window_chrome_view_is_interactive(hitView));
}
