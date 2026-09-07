#pragma once

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// The sidebar's Chapters / Comments / Search control, which grows a Search
// segment while a search is live and drops it again when the search ends.
//
// AppKit clears -selectedSegment when the segment it removes is the selected
// one, and that is exactly the case that happens: the reader is looking at the
// search results when they clear the query. Everything downstream reads that
// selection -- which builder fills the list, and whether the chapter rows get
// their levels, their disclosure triangles and their expand/collapse button --
// so a selection of -1 rebuilds the chapter list flat and buttonless, with no
// segment lit, until the reader clicks a mode by hand.
//
// Resize through this rather than setting -segmentCount: the selection survives
// when its segment does, and falls back to `fallbackSegment` when it does not.
void spdf_sidebar_mode_control_set_segment_count(NSSegmentedControl* control, NSInteger segmentCount,
                                                 NSInteger fallbackSegment);

NS_ASSUME_NONNULL_END
