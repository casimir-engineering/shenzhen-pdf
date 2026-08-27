#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, SPDFMacSelectionGranularity) {
    SPDFMacSelectionGranularityRange = 0,
    SPDFMacSelectionGranularityWord = 1,
    SPDFMacSelectionGranularityBlock = 2,
};

// AppKit reports the accumulated click count on each mouse-down. A plain click
// starts the existing range gesture; double/triple clicks are atomic selections
// and must never enter that drag path.
SPDFMacSelectionGranularity spdf_mac_selection_granularity_for_event(NSEvent* event);
BOOL spdf_mac_selection_uses_range_path(SPDFMacSelectionGranularity granularity);
