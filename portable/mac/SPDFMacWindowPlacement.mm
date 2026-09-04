#import "SPDFMacWindowPlacement.h"

NSRect spdf_window_content_rect_for_saved_frame(NSRect frame) {
    static const NSWindowStyleMask mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                          NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    return [NSWindow contentRectForFrameRect:frame styleMask:mask];
}

void spdf_window_configure_document_window(NSWindow* window, id reader, NSSize minimumSize, NSRect savedFrame,
                                           BOOL hasSavedFrame) {
    if (!window) return;
    // Set through KVC rather than importing SPDFWindow: this file is linked on
    // its own by the placement test, and the reader is the only thing it would
    // need that header for.
    if ([window respondsToSelector:@selector(setReader:)]) [window setValue:reader forKey:@"reader"];
    window.delegate = reader;
    window.title = @"Shenzhen PDF";
    window.minSize = minimumSize;
    if (hasSavedFrame) [window setFrame:savedFrame display:NO];
}
