#pragma once

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPDFSidebarMode) {
    SPDFSidebarModeChapters = 0,
    SPDFSidebarModeComments = 1,
    SPDFSidebarModeSearch = 2,
    SPDFSidebarModeHistory = 3,
    SPDFSidebarModeGroups = 4
};

@interface SPDFSidebarNavigationControl : NSSegmentedControl
@end

void spdf_sidebar_mode_control_configure_navigation(NSSegmentedControl* control, BOOL supportsComments, BOOL hasHistory);

// Mode tags stay stable when Markdown omits the Comments segment.
@interface NSSegmentedControl (SPDFSidebarModes)
@property(nonatomic) NSInteger spdf_selectedSidebarMode;
- (void)spdf_setEnabled:(BOOL)enabled forSidebarMode:(NSInteger)mode;
@end

void spdf_sidebar_mode_control_configure(NSSegmentedControl* control, BOOL supportsComments, BOOL hasSearch);

void spdf_sidebar_mode_control_configure_history(NSSegmentedControl* control, BOOL supportsComments, BOOL hasSearch, BOOL hasHistory);

// Keep document-dependent modes in sync even while a workspace panel bypasses
// the normal Chapters / Comments / Search list builder.
void spdf_sidebar_mode_control_set_document_availability(NSSegmentedControl* control, BOOL hasChapters,
                                                         BOOL hasComments);

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
