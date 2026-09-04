#import "SPDFMacWindowPlacement.h"

NSRect spdf_window_content_rect_for_saved_frame(NSRect frame) {
    static const NSWindowStyleMask mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                          NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    return [NSWindow contentRectForFrameRect:frame styleMask:mask];
}
