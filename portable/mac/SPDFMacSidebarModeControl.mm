#import "SPDFMacSidebarModeControl.h"

void spdf_sidebar_mode_control_set_segment_count(NSSegmentedControl* control, NSInteger segmentCount,
                                                 NSInteger fallbackSegment) {
    if (!control || segmentCount <= 0) return;
    NSInteger selected = control.selectedSegment;
    if (control.segmentCount != segmentCount) control.segmentCount = segmentCount;
    // Growing keeps the selection, so there is nothing to put back; only a
    // shrink that removes the selected segment leaves it at -1.
    if (control.selectedSegment >= 0) return;
    if (selected < 0 || selected >= segmentCount) selected = fallbackSegment;
    control.selectedSegment = MAX(0, MIN(selected, segmentCount - 1));
}
