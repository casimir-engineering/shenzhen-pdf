#import <Foundation/Foundation.h>

#import "SPDFMacWindowChrome.h"

static void expect_action(NSString* label, SPDFWindowChromeAction actual, SPDFWindowChromeAction expected) {
    if (actual == expected) return;
    NSLog(@"FAIL %@: got %ld, expected %ld", label, (long)actual, (long)expected);
    exit(1);
}

int main(void) {
    @autoreleasepool {
        expect_action(@"single click drags", spdf_window_chrome_action(1, NO, NO), SPDFWindowChromeActionDrag);
        expect_action(@"double click zooms", spdf_window_chrome_action(2, NO, NO), SPDFWindowChromeActionZoom);
        expect_action(@"later click count zooms", spdf_window_chrome_action(3, NO, NO), SPDFWindowChromeActionZoom);
        expect_action(@"full screen ignores double click", spdf_window_chrome_action(2, YES, NO),
                      SPDFWindowChromeActionNone);
        expect_action(@"presentation ignores double click", spdf_window_chrome_action(2, NO, YES),
                      SPDFWindowChromeActionNone);
    }
    return 0;
}
