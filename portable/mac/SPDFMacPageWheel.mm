#import "SPDFMacPageWheel.h"

#import "SPDFMacUIHelpers.h"

// Thresholds and debounces are lifted from the presentation-mode wheel paging
// in SPDFScrollView -scrollWheel:, so Option + wheel feels like the paging this
// app already had rather than a second, differently tuned gesture.
static const double kPreciseThreshold = 0.75;
static const double kDiscreteThreshold = 0.50;
static const double kDiscreteTurnDebounce = 0.18;  // one page per mouse notch
static const double kGestureIdleReset = 0.35;      // a pause starts a new gesture

bool spdf_page_wheel_modifiers_page(NSEventModifierFlags flags) {
    NSEventModifierFlags relevant = flags & NSEventModifierFlagDeviceIndependentFlagsMask;
    if (!(relevant & NSEventModifierFlagOption)) return false;
    // Command and Control already mean zoom; leave those alone.
    return !(relevant & (NSEventModifierFlagCommand | NSEventModifierFlagControl));
}

static void spdf_page_wheel_reset(spdf_page_wheel_state* state) {
    state->accumulator = 0.0;
    state->direction = 0;
    state->turnedInGesture = false;
    state->gestureActive = false;
}

int spdf_page_wheel_step(spdf_page_wheel_state* state, double deltaY, bool preciseDeltas, bool phaseBegan,
                         bool phaseEnded, bool momentum, double timestamp) {
    if (!state) return 0;
    if (phaseBegan) spdf_page_wheel_reset(state);
    // Momentum is the tail of a flick, not the reader asking for more pages.
    if (momentum || phaseEnded) {
        spdf_page_wheel_reset(state);
        state->lastEventTimestamp = timestamp;
        return 0;
    }
    if (state->lastEventTimestamp > 0.0 && timestamp - state->lastEventTimestamp > kGestureIdleReset)
        spdf_page_wheel_reset(state);
    // One page per trackpad gesture, however far the flick travels.
    if (state->gestureActive && state->turnedInGesture && preciseDeltas) {
        state->lastEventTimestamp = timestamp;
        return 0;
    }
    if (!preciseDeltas && state->lastTurnTimestamp > 0.0 && timestamp - state->lastTurnTimestamp < kDiscreteTurnDebounce) {
        state->lastEventTimestamp = timestamp;
        return 0;
    }
    if (fabs(deltaY) < 0.0001) {
        state->lastEventTimestamp = timestamp;
        return 0;
    }
    int direction = deltaY < 0 ? -1 : 1;
    if (state->direction != 0 && direction != state->direction) {
        state->accumulator = 0.0;
        state->turnedInGesture = false;
    }
    state->direction = direction;
    state->gestureActive = true;
    state->accumulator += deltaY;
    state->lastEventTimestamp = timestamp;
    double threshold = preciseDeltas ? kPreciseThreshold : kDiscreteThreshold;
    if (fabs(state->accumulator) < threshold) return 0;
    // Scrolling forward (negative delta, the direction that advances the
    // document) goes to the next page, matching the presentation-mode paging.
    int step = state->accumulator < 0 ? 1 : -1;
    state->accumulator = 0.0;
    state->turnedInGesture = true;
    state->lastTurnTimestamp = timestamp;
    return step;
}

BOOL spdf_page_wheel_handle_window_scroll(NSWindow* window, NSEvent* event) {
    if (!window || event.type != NSEventTypeScrollWheel) return NO;
    if (!spdf_page_wheel_modifiers_page(event.modifierFlags)) return NO;
    id reader = [window respondsToSelector:@selector(reader)] ? [(id)window reader] : nil;
    if (![reader respondsToSelector:@selector(nextPage:)]) return NO;

    // One window per process, so the gesture state can live here.
    static spdf_page_wheel_state state;
    BOOL phaseBegan = (event.phase & (NSEventPhaseBegan | NSEventPhaseMayBegin)) != 0;
    BOOL phaseEnded = (event.phase & (NSEventPhaseEnded | NSEventPhaseCancelled)) != 0;
    double delta = event.scrollingDeltaY != 0.0 ? event.scrollingDeltaY : event.deltaY;
    int step = spdf_page_wheel_step(&state, delta, event.hasPreciseScrollingDeltas, phaseBegan, phaseEnded,
                                    event.momentumPhase != NSEventPhaseNone, event.timestamp);
    if (step > 0)
        [reader nextPage:nil];
    else if (step < 0)
        [reader previousPage:nil];
    // Consumed either way: an Option + wheel event must never also scroll
    // whatever the pointer happens to be over.
    return YES;
}
