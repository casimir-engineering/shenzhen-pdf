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

static_assert(SPDFWindowEventTypeLeftMouseDown == NSEventTypeLeftMouseDown, "left mouse down value drifted");
static_assert(SPDFWindowEventTypeRightMouseDown == NSEventTypeRightMouseDown, "right mouse down value drifted");
static_assert(SPDFWindowEventTypeOtherMouseDown == NSEventTypeOtherMouseDown, "other mouse down value drifted");

BOOL spdf_window_event_is_mouse_press(NSUInteger eventType) {
    return eventType == SPDFWindowEventTypeLeftMouseDown || eventType == SPDFWindowEventTypeRightMouseDown ||
           eventType == SPDFWindowEventTypeOtherMouseDown;
}

BOOL spdf_window_click_should_activate(NSUInteger eventType, BOOL appActive, BOOL windowIsKey,
                                       BOOL windowCanBecomeKey, BOOL windowHasAttachedSheet,
                                       BOOL anotherWindowIsModal) {
    if (!spdf_window_event_is_mouse_press(eventType)) return NO;
    // A sheet is modal for its parent, and an app-modal window is modal for
    // everything: clicks elsewhere must keep AppKit's native handling (bounce
    // the modal), never pull key away from it.
    if (windowHasAttachedSheet || anotherWindowIsModal) return NO;
    if (!windowCanBecomeKey) return NO;
    // Already focused: nothing to do, and re-ordering on every click would be
    // both wasteful and visible.
    if (appActive && windowIsKey) return NO;
    return YES;
}

void spdf_window_activate_for_click_event(NSWindow* window, NSEvent* event) {
    if (!window || !event) return;
    // Resolved by name (not by symbol) so this file keeps linking into the
    // Foundation-only window-chrome unit-test binary.
    id app = [NSClassFromString(@"NSApplication") sharedApplication];
    BOOL appActive = app ? [app isActive] : YES;
    id modalWindow = [app modalWindow];
    if (!spdf_window_click_should_activate(event.type, appActive, window.keyWindow, window.canBecomeKeyWindow,
                                           window.attachedSheet != nil, modalWindow && modalWindow != window))
        return;
    // Order matters: focus the window BEFORE the event is dispatched, so AppKit
    // sees a key window and delivers the click normally instead of consuming it
    // as the click that activates.
    if (!appActive) [app activateIgnoringOtherApps:YES];
    if (!window.keyWindow) [window makeKeyAndOrderFront:nil];
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
