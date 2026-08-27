#import <Cocoa/Cocoa.h>

@class SPDFRenderedPage;

CGFloat spdf_mac_effective_backing_scale(CGFloat configuredScale, NSWindow* window);
CGFloat spdf_mac_pixel_snapped_length(CGFloat length, CGFloat backingScale);
CGFloat spdf_mac_pixel_snapped_origin(CGFloat origin, CGFloat backingScale);
NSSize spdf_mac_view_size_for_page(SPDFRenderedPage* page, CGFloat zoom, CGFloat backingScale);

NSRect spdf_mac_page_rect_to_view_rect(NSRect rect, NSRect pageRect, SPDFRenderedPage* page);
NSPoint spdf_mac_view_point_to_page_point(NSPoint point, NSRect pageRect, SPDFRenderedPage* page);
BOOL spdf_mac_page_subrect_covers_full_page(NSRect pageSubrect, SPDFRenderedPage* page);
BOOL spdf_mac_should_draw_stale_full_page_image(SPDFRenderedPage* page, CGFloat zoom, CGFloat backingScale);

BOOL spdf_mac_draw_page_image(NSImage* image,
                              NSRect pageSubrect,
                              NSRect pageRect,
                              NSRect dirtyRect,
                              SPDFRenderedPage* page,
                              NSImageInterpolation interpolation);
