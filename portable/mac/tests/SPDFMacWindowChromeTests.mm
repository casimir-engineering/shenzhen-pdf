#import <Foundation/Foundation.h>

#import "SPDFMacWindowChrome.h"

static void expect_action(NSString* label, SPDFWindowChromeAction actual, SPDFWindowChromeAction expected) {
    if (actual == expected) return;
    NSLog(@"FAIL %@: got %ld, expected %ld", label, (long)actual, (long)expected);
    exit(1);
}

static void expect_bool(NSString* label, BOOL actual, BOOL expected) {
    if (actual == expected) return;
    NSLog(@"FAIL %@: got %d, expected %d", label, (int)actual, (int)expected);
    exit(1);
}

int main(void) {
    @autoreleasepool {
        expect_action(@"single click drags", spdf_window_chrome_action(1, NO, NO, NO), SPDFWindowChromeActionDrag);
        expect_action(@"double click zooms", spdf_window_chrome_action(2, NO, NO, NO), SPDFWindowChromeActionZoom);
        expect_action(@"later click count zooms", spdf_window_chrome_action(3, NO, NO, NO),
                      SPDFWindowChromeActionZoom);
        expect_action(@"full screen ignores double click", spdf_window_chrome_action(2, YES, NO, NO),
                      SPDFWindowChromeActionNone);
        expect_action(@"presentation ignores double click", spdf_window_chrome_action(2, NO, YES, NO),
                      SPDFWindowChromeActionNone);

        // Clicks that land on an interactive control belong to the control:
        // no drag on single click, no zoom on double click, in any mode.
        expect_action(@"control single click never drags", spdf_window_chrome_action(1, NO, NO, YES),
                      SPDFWindowChromeActionNone);
        expect_action(@"control double click never zooms", spdf_window_chrome_action(2, NO, NO, YES),
                      SPDFWindowChromeActionNone);
        expect_action(@"control triple click never zooms", spdf_window_chrome_action(3, NO, NO, YES),
                      SPDFWindowChromeActionNone);
        expect_action(@"control click inert in full screen", spdf_window_chrome_action(2, YES, NO, YES),
                      SPDFWindowChromeActionNone);
        expect_action(@"control click inert in presentation", spdf_window_chrome_action(2, NO, YES, YES),
                      SPDFWindowChromeActionNone);

        // The hit-view classifier tolerates a missed hit-test (nil view):
        // empty chrome background keeps its native drag/zoom behavior.
        expect_bool(@"nil hit view is not interactive", spdf_window_chrome_view_is_interactive(nil), NO);

        // Click-to-focus: any press of any mouse button counts, nothing else does.
        expect_bool(@"left mouse down is a press", spdf_window_event_is_mouse_press(SPDFWindowEventTypeLeftMouseDown),
                    YES);
        expect_bool(@"right mouse down is a press",
                    spdf_window_event_is_mouse_press(SPDFWindowEventTypeRightMouseDown), YES);
        expect_bool(@"middle mouse down is a press",
                    spdf_window_event_is_mouse_press(SPDFWindowEventTypeOtherMouseDown), YES);
        expect_bool(@"left mouse up is not a press", spdf_window_event_is_mouse_press(2), NO);
        expect_bool(@"left mouse dragged is not a press", spdf_window_event_is_mouse_press(6), NO);
        expect_bool(@"key down is not a press", spdf_window_event_is_mouse_press(10), NO);
        expect_bool(@"scroll wheel is not a press", spdf_window_event_is_mouse_press(22), NO);
        expect_bool(@"magnify is not a press", spdf_window_event_is_mouse_press(30), NO);

        // The window is unfocused in any of these three ways; a click fixes all
        // of them. The middle-click case is the tab close the user reported:
        // macOS never activates an app on a middle-click, so we must.
        expect_bool(@"click activates an inactive app",
                    spdf_window_click_should_activate(SPDFWindowEventTypeLeftMouseDown, NO, NO, YES, NO, NO), YES);
        expect_bool(@"click focuses a non-key window of the active app",
                    spdf_window_click_should_activate(SPDFWindowEventTypeLeftMouseDown, YES, NO, YES, NO, NO), YES);
        expect_bool(@"click activates the app for its own key window",
                    spdf_window_click_should_activate(SPDFWindowEventTypeLeftMouseDown, NO, YES, YES, NO, NO), YES);
        expect_bool(@"middle click focuses too",
                    spdf_window_click_should_activate(SPDFWindowEventTypeOtherMouseDown, NO, NO, YES, NO, NO), YES);
        expect_bool(@"right click focuses too",
                    spdf_window_click_should_activate(SPDFWindowEventTypeRightMouseDown, NO, NO, YES, NO, NO), YES);

        // Nothing to do, or not ours to do.
        expect_bool(@"already focused window is left alone",
                    spdf_window_click_should_activate(SPDFWindowEventTypeLeftMouseDown, YES, YES, YES, NO, NO), NO);
        expect_bool(@"scroll never activates", spdf_window_click_should_activate(22, NO, NO, YES, NO, NO), NO);
        expect_bool(@"magnify never activates", spdf_window_click_should_activate(30, NO, NO, YES, NO, NO), NO);
        expect_bool(@"mouse up never activates", spdf_window_click_should_activate(2, NO, NO, YES, NO, NO), NO);
        expect_bool(@"a window that cannot take key is left alone",
                    spdf_window_click_should_activate(SPDFWindowEventTypeLeftMouseDown, NO, NO, NO, NO, NO), NO);
        expect_bool(@"an attached sheet keeps focus",
                    spdf_window_click_should_activate(SPDFWindowEventTypeLeftMouseDown, NO, NO, YES, YES, NO), NO);
        expect_bool(@"an app-modal window keeps focus",
                    spdf_window_click_should_activate(SPDFWindowEventTypeLeftMouseDown, NO, NO, YES, NO, YES), NO);

        // Nil arguments are inert: the imperative wrapper must never crash on a
        // window or event that is gone.
        spdf_window_activate_for_click_event(nil, nil);

        // Zoom wheel: Cmd or Ctrl on an actively scrolling wheel, never on the
        // inertial tail. Both the focused responder chain and the out-of-focus
        // event tap ask this, so an unfocused Cmd+wheel zooms exactly like a
        // focused one.
        const NSUInteger cmd = SPDFWindowModifierFlagCommand;
        const NSUInteger ctrl = SPDFWindowModifierFlagControl;
        const NSUInteger shift = 1 << 17;  // NSEventModifierFlagShift
        expect_bool(@"command wheel zooms", spdf_scroll_is_zoom_wheel(cmd, NO), YES);
        expect_bool(@"control wheel zooms", spdf_scroll_is_zoom_wheel(ctrl, NO), YES);
        expect_bool(@"command with other modifiers still zooms", spdf_scroll_is_zoom_wheel(cmd | shift, NO), YES);
        expect_bool(@"plain wheel scrolls", spdf_scroll_is_zoom_wheel(0, NO), NO);
        expect_bool(@"shift wheel scrolls sideways, never zooms", spdf_scroll_is_zoom_wheel(shift, NO), NO);
        expect_bool(@"command held during momentum never zooms", spdf_scroll_is_zoom_wheel(cmd, YES), NO);
        expect_bool(@"plain momentum never zooms", spdf_scroll_is_zoom_wheel(0, YES), NO);

        // Tap ownership. Out of focus the tap sees the scroll first; if the
        // window server hands the very same event to the window as well, the
        // responder chain must stand down instead of zooming twice.
        expect_bool(@"tap owns the event it just zoomed",
                    spdf_zoom_wheel_handled_by_tap(YES, NO, 100.0, 100.0, 0.5), YES);
        expect_bool(@"tap owns a rebuilt event within the hop window",
                    spdf_zoom_wheel_handled_by_tap(YES, NO, 100.5, 100.0, 0.001), YES);
        expect_bool(@"a later scroll the tap declined still zooms",
                    spdf_zoom_wheel_handled_by_tap(YES, NO, 100.5, 100.0, 0.5), NO);
        expect_bool(@"no tap zoom yet leaves the responder chain in charge",
                    spdf_zoom_wheel_handled_by_tap(YES, NO, 100.0, 0.0, 1.0e6), NO);
        expect_bool(@"focused app always zooms through the responder chain",
                    spdf_zoom_wheel_handled_by_tap(YES, YES, 100.0, 100.0, 0.0), NO);
        expect_bool(@"without a tap the responder chain is the only path",
                    spdf_zoom_wheel_handled_by_tap(NO, NO, 100.0, 100.0, 0.0), NO);
        expect_bool(@"a clock that ran backwards does not silence the wheel",
                    spdf_zoom_wheel_handled_by_tap(YES, NO, 100.5, 100.0, -1.0), NO);
    }
    return 0;
}
