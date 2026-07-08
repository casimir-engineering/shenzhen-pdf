#import <Foundation/Foundation.h>

// Pure geometry for tab-strip drop insertion (reattach drag). Kept free of
// AppKit/view state so it is unit-testable (see
// tests/SPDFMacTabStripGeometryTests.mm).
//
// A "slot" is an insertion position among the VISIBLE tabs, left to right:
// slot 0 is before the first visible tab, slot visibleCount is after the last
// one. The caller maps a slot back to an index into its full tabs array
// (identical for the non-overflow case).

// Returns the slot for a cursor x: the first visible tab whose horizontal
// midpoint lies right of x, else visibleCount. Matches the midpoint semantics
// the strip has always used for drops. Returns 0 when visibleCount <= 0.
NSInteger spdf_tab_strip_drop_slot_for_x(CGFloat x, const CGFloat* visibleTabMidXs, NSInteger visibleCount);

// Center x for the insertion indicator line at a slot: the middle of the gap
// between the two neighboring tabs, or half a tab gap outside the first/last
// tab edge for the end slots. Returns NAN when visibleCount <= 0 or the slot
// is out of range (caller draws nothing).
CGFloat spdf_tab_strip_drop_indicator_center_x(NSInteger slot,
                                               const CGFloat* visibleTabMinXs,
                                               const CGFloat* visibleTabMaxXs,
                                               NSInteger visibleCount,
                                               CGFloat tabGap);
