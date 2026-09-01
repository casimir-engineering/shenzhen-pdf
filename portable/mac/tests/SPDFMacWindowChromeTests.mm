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
    }
    return 0;
}
