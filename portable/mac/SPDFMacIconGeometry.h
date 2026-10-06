#pragma once
#import <Cocoa/Cocoa.h>

// Fit the natural symbol proportions inside its existing visual slot. Hit
// targets and layout stay independent of the painted glyph's aspect ratio.
static inline NSRect SPDFIconAspectFitRect(NSImage* image, NSRect slot) {
    NSSize size = image.size;
    if (size.width <= 0 || size.height <= 0 || NSIsEmptyRect(slot)) return NSZeroRect;
    CGFloat scale = MIN(NSWidth(slot)/size.width, NSHeight(slot)/size.height);
    NSSize fitted = NSMakeSize(size.width*scale,size.height*scale);
    return NSMakeRect(NSMidX(slot)-fitted.width/2,NSMidY(slot)-fitted.height/2,
                      fitted.width,fitted.height);
}
