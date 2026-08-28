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

// Full decision for one chrome mouse-down: re-hit-tests the event against the
// window's content view and refuses drag/zoom for clicks that land on an
// interactive control (chrome views also receive mouseDown via the responder
// chain from descendant controls that decline the event — a disabled control,
// or a click inside a segmented pill's frame padding off the visible bezel).
SPDFWindowChromeAction spdf_window_chrome_action_for_event(NSWindow* window, NSEvent* event, BOOL fullScreen,
                                                           BOOL presentation);
