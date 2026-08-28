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
    }
    return 0;
}
