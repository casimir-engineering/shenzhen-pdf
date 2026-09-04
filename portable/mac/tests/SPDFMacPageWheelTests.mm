// Option + wheel = the page arrows. The rules that matter are the gesture
// rules: a mouse notch turns exactly one page, a trackpad flick turns exactly
// one page however long the flick, momentum never turns any, and the modifier
// must not collide with the zoom gestures.

#import <Cocoa/Cocoa.h>

#import "SPDFMacPageWheel.h"

static int gFailures;

// The routing only needs -reader from the window and the two page selectors
// from it; standing in for them keeps this a unit test.
@interface SPDFPageWheelRecorder : NSObject {
@public
    int steps;
    BOOL lastWasNext;
}
@end
@implementation SPDFPageWheelRecorder
- (void)nextPage:(id)sender {
    (void)sender;
    ++steps;
    lastWasNext = YES;
}
- (void)previousPage:(id)sender {
    (void)sender;
    ++steps;
    lastWasNext = NO;
}
@end

@interface SPDFPageWheelFakeWindow : NSObject
@property(nonatomic, strong) SPDFPageWheelRecorder* recorder;
- (id)reader;
@end
@implementation SPDFPageWheelFakeWindow
- (id)reader {
    return self.recorder;
}
@end

static void Expect(const char* what, BOOL condition) {
    if (condition) return;
    fprintf(stderr, "FAIL: %s\n", what);
    ++gFailures;
}

// deltaY < 0 is the direction that advances the document.
static const double kForward = -1.0;
static const double kBack = 1.0;

int main(void) {
    @autoreleasepool {
        // --- Which modifiers mean "page" -------------------------------
        Expect("option alone pages", spdf_page_wheel_modifiers_page(NSEventModifierFlagOption));
        Expect("no modifier does not page", !spdf_page_wheel_modifiers_page(0));
        // Command and Control already mean zoom; stealing them would break it.
        Expect("option+command does not page",
               !spdf_page_wheel_modifiers_page(NSEventModifierFlagOption | NSEventModifierFlagCommand));
        Expect("option+control does not page",
               !spdf_page_wheel_modifiers_page(NSEventModifierFlagOption | NSEventModifierFlagControl));
        Expect("command alone does not page", !spdf_page_wheel_modifiers_page(NSEventModifierFlagCommand));
        // Shift is not a zoom modifier, so it may ride along.
        Expect("option+shift still pages",
               spdf_page_wheel_modifiers_page(NSEventModifierFlagOption | NSEventModifierFlagShift));

        // --- A mouse wheel: one page per notch --------------------------
        {
            spdf_page_wheel_state state = {};
            int first = spdf_page_wheel_step(&state, kForward, false, false, false, false, 1.00);
            Expect("a notch forward turns to the next page", first == 1);
            // The debounce swallows the echo a single notch often produces...
            int echo = spdf_page_wheel_step(&state, kForward, false, false, false, false, 1.05);
            Expect("an immediate second event does not double-page", echo == 0);
            // ...but a deliberate second notch pages again.
            int second = spdf_page_wheel_step(&state, kForward, false, false, false, false, 1.40);
            Expect("a later notch turns another page", second == 1);
            int back = spdf_page_wheel_step(&state, kBack, false, false, false, false, 2.00);
            Expect("a notch the other way goes back a page", back == -1);
        }

        // --- A trackpad flick: exactly one page ------------------------
        {
            spdf_page_wheel_state state = {};
            int turns = 0;
            // A flick is one Began plus a long tail of precise deltas.
            if (spdf_page_wheel_step(&state, kForward * 0.4, true, true, false, false, 10.0)) ++turns;
            for (int i = 1; i < 25; ++i) {
                if (spdf_page_wheel_step(&state, kForward * 1.5, true, false, false, false, 10.0 + i * 0.01)) ++turns;
            }
            Expect("a whole trackpad flick turns exactly one page", turns == 1);
            // Momentum is the tail of that flick, not a request for more.
            int momentum = 0;
            for (int i = 0; i < 20; ++i) {
                if (spdf_page_wheel_step(&state, kForward * 3.0, true, false, false, true, 10.3 + i * 0.01)) ++momentum;
            }
            Expect("momentum turns no pages", momentum == 0);
            // A fresh gesture pages again.
            int next = spdf_page_wheel_step(&state, kForward * 2.0, true, true, false, false, 12.0);
            Expect("the next flick turns a page", next == 1);
        }

        // --- Reversing mid-gesture ------------------------------------
        {
            spdf_page_wheel_state state = {};
            spdf_page_wheel_step(&state, kForward * 0.3, true, true, false, false, 20.0);
            // Below the threshold, then reversed: must not fire the direction
            // the reader abandoned.
            int reversed = spdf_page_wheel_step(&state, kBack * 1.2, true, false, false, false, 20.05);
            Expect("reversing mid-gesture pages the way the wheel now turns", reversed == -1);
        }

        // --- A pause starts a new gesture ------------------------------
        {
            spdf_page_wheel_state state = {};
            Expect("first flick pages", spdf_page_wheel_step(&state, kForward * 2.0, true, true, false, false, 30.0) == 1);
            // Same gesture, no Began: still one page only.
            Expect("no second page without a pause",
                   spdf_page_wheel_step(&state, kForward * 2.0, true, false, false, false, 30.1) == 0);
            // After an idle gap the reader is clearly asking again.
            Expect("a page turns again after a pause",
                   spdf_page_wheel_step(&state, kForward * 2.0, true, false, false, false, 31.0) == 1);
        }

        // --- Degenerate input -----------------------------------------
        {
            spdf_page_wheel_state state = {};
            Expect("a zero delta does nothing", spdf_page_wheel_step(&state, 0.0, true, false, false, false, 40.0) == 0);
            Expect("a null state is safe", spdf_page_wheel_step(NULL, kForward, false, false, false, false, 41.0) == 0);
        }

        // --- The routing, not just the policy -------------------------
        // The policy above is pure; this checks the window entry point really
        // turns an Option + wheel NSEvent into a page-arrow call, and leaves
        // every other scroll alone. Events are CONSTRUCTED, not posted: posting
        // needs Input Monitoring permission the test process does not have.
        {
            CGEventRef scroll = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 1, -1);
            CGEventSetFlags(scroll, kCGEventFlagMaskAlternate);
            NSEvent* optionWheel = [NSEvent eventWithCGEvent:scroll];
            CGEventSetFlags(scroll, 0);
            NSEvent* plainWheel = [NSEvent eventWithCGEvent:scroll];
            CGEventSetFlags(scroll, kCGEventFlagMaskCommand);
            NSEvent* commandWheel = [NSEvent eventWithCGEvent:scroll];
            CFRelease(scroll);
            Expect("an option wheel event is built", optionWheel != nil);

            SPDFPageWheelRecorder* recorder = [SPDFPageWheelRecorder new];
            SPDFPageWheelFakeWindow* window = [SPDFPageWheelFakeWindow new];
            window.recorder = recorder;

            Expect("a plain wheel event is left to scroll",
                   !spdf_page_wheel_handle_window_scroll((NSWindow*)window, plainWheel) && recorder->steps == 0);
            Expect("a command wheel event is left to the zoom path",
                   !spdf_page_wheel_handle_window_scroll((NSWindow*)window, commandWheel) && recorder->steps == 0);
            BOOL consumed = spdf_page_wheel_handle_window_scroll((NSWindow*)window, optionWheel);
            Expect("an option wheel event is consumed", consumed);
            Expect("...and asks the reader for a page", recorder->steps == 1);
            Expect("...forward, because the wheel turned forward", recorder->lastWasNext);
        }

        if (gFailures == 0) fprintf(stderr, "SPDFMacPageWheelTests passed\n");
    }
    return gFailures == 0 ? 0 : 1;
}
