#import <Foundation/Foundation.h>

@class NSEvent;
@class NSView;
@class NSWindow;

// Implemented by SPDFWindow. Views embedded in the transparent title bar use
// this narrow protocol to preserve one native drag/zoom policy without knowing
// about the concrete application window class.
@protocol SPDFWindowChromeHandling <NSObject>
- (void)handleChromeMouseDown:(NSEvent*)event;
@end

typedef NS_ENUM(NSInteger, SPDFWindowChromeAction) {
    SPDFWindowChromeActionNone = 0,
    SPDFWindowChromeActionDrag,
    SPDFWindowChromeActionZoom,
};

SPDFWindowChromeAction spdf_window_chrome_action(NSUInteger clickCount, BOOL fullScreen, BOOL presentation,
                                                 BOOL onInteractiveControl);

// YES when the deepest hit view under a chrome click is (a descendant of) an
// interactive control — button, segmented control, popup, checkbox, text
// field, or a field editor — so the click must never be treated as titlebar
// chrome (drag / double-click zoom). Chrome-owned drag surfaces that happen
// to be controls (e.g. SPDFToolbarDragLabel) opt back in by overriding
// -mouseDownCanMoveWindow to return YES.
BOOL spdf_window_chrome_view_is_interactive(NSView* hitView);

// Raw NSEventType values for the three mouse-button presses, spelled out so the
// Foundation-only unit test can exercise the activation policy below without
// linking AppKit. Static-asserted against the AppKit constants in the .mm.
enum {
    SPDFWindowEventTypeLeftMouseDown = 1,    // NSEventTypeLeftMouseDown
    SPDFWindowEventTypeRightMouseDown = 3,   // NSEventTypeRightMouseDown
    SPDFWindowEventTypeOtherMouseDown = 25,  // NSEventTypeOtherMouseDown
};

// YES for a press of any mouse button (left / right / middle / extra). Releases,
// drags, scrolls, gestures and key events are not presses.
BOOL spdf_window_event_is_mouse_press(NSUInteger eventType);

// Should this event focus the document window it was delivered to? Any press of
// any mouse button anywhere inside a ShenzhenPDF window focuses that window —
// AppKit only does this for clicks it dispatches itself, and the tab strip's
// clicks (tab select, close box, middle-click close) are intercepted in
// -sendEvent: before AppKit ever sees them, while macOS never activates an app
// on a middle-click at all. Declines when there is nothing to do (already the
// key window of the active app), when the window cannot take key, when a sheet
// is attached, and while some other window is running app-modal — in all three
// of those cases another window owns focus and AppKit's own handling is right.
BOOL spdf_window_click_should_activate(NSUInteger eventType, BOOL appActive, BOOL windowIsKey,
                                       BOOL windowCanBecomeKey, BOOL windowHasAttachedSheet,
                                       BOOL anotherWindowIsModal);

// Applies the policy above to one event: activates the app and makes `window`
// key before the event is dispatched further, so the focusing click still does
// its own job (select text, follow a link, close the tab) instead of being
// swallowed as a first click. No-op when the policy declines.
void spdf_window_activate_for_click_event(NSWindow* window, NSEvent* event);

// Full decision for one chrome mouse-down: re-hit-tests the event against the
// window's content view and refuses drag/zoom for clicks that land on an
// interactive control (chrome views also receive mouseDown via the responder
// chain from descendant controls that decline the event — a disabled control,
// or a click inside a segmented pill's frame padding off the visible bezel).
SPDFWindowChromeAction spdf_window_chrome_action_for_event(NSWindow* window, NSEvent* event, BOOL fullScreen,
                                                           BOOL presentation);
