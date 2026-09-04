#import <Cocoa/Cocoa.h>

// Restoring a window exactly where it was left, including on a display that is
// not the main one.
//
// The saved value is a WINDOW frame (NSWindow.frame). -initWithContentRect:
// wants a CONTENT rect, and handing it a window frame made the window one
// titlebar taller than it was saved -- and an oversized window is then
// repositioned by AppKit, which is how a window left on a second display came
// back on the main one (measured: saved y 1319, restored y 487).
//
// The style mask here must match the one buildWindow creates the window with;
// it is the mask that decides how much taller a frame is than its content.
NSRect spdf_window_content_rect_for_saved_frame(NSRect frame);

// Everything the document window needs once it exists: the reader it routes
// events to, its delegate, title and minimum size, and the saved frame applied
// AFTER the style mask is final (AppKit repositions during
// -initWithContentRect:, which is how a window left on a second display came
// back on the main one). Grouped here because they are one step -- "make this
// window the app's document window, placed where it was left" -- and because
// losing any one of them silently breaks event routing or resize handling.
void spdf_window_configure_document_window(NSWindow* window, id reader, NSSize minimumSize, NSRect savedFrame,
                                           BOOL hasSavedFrame);
