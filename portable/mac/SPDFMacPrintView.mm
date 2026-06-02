#import "SPDFMacPrintView.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static const CGFloat kSPDFDefaultPrintDPI = 1200.0;
static const CGFloat kSPDFMinimumPrintRenderZoom = 1.0;

static NSImage* spdf_print_image_from_bitmap(spdf_bitmap* bitmap, CGFloat imageScale, char* err, size_t errLen) {
    if (!bitmap || !bitmap->rgba || bitmap->width <= 0 || bitmap->height <= 0 || bitmap->stride <= 0) {
        if (err && errLen > 0) snprintf(err, errLen, "%s", "Rendered page bitmap is empty.");
        return nil;
    }

    NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:bitmap->width
                                                                    pixelsHigh:bitmap->height
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:bitmap->stride
                                                                  bitsPerPixel:32];
    if (!rep || !rep.bitmapData) {
        if (err && errLen > 0) snprintf(err, errLen, "%s", "Could not allocate print bitmap.");
        return nil;
    }

    memcpy(rep.bitmapData, bitmap->rgba, (size_t)bitmap->stride * (size_t)bitmap->height);
    imageScale = imageScale > 0 ? imageScale : 1.0;
    NSSize pointSize = NSMakeSize((CGFloat)bitmap->width / imageScale, (CGFloat)bitmap->height / imageScale);
    rep.size = pointSize;

    NSImage* image = [[NSImage alloc] initWithSize:pointSize];
    if (!image) {
        if (err && errLen > 0) snprintf(err, errLen, "%s", "Could not allocate print image.");
        return nil;
    }
    [image addRepresentation:rep];
    return image;
}

@implementation SPDFPrintView

- (BOOL)isFlipped {
    return YES;
}

- (NSInteger)effectivePageCount {
    if (self.pageCount > 0) return self.pageCount;
    return (NSInteger)self.fallbackPages.count;
}

- (BOOL)knowsPageRange:(NSRangePointer)range {
    range->location = 1;
    range->length = [self effectivePageCount];
    return YES;
}

- (NSRect)rectForPage:(NSInteger)page {
    NSPrintInfo* info = NSPrintOperation.currentOperation.printInfo;
    NSSize paper = info.paperSize;
    return NSMakeRect(0, (page - 1) * paper.height, paper.width, paper.height);
}

- (NSImage*)highResolutionImageForPageIndex:(NSInteger)pageIndex {
    if (!self.document || pageIndex < 0 || pageIndex >= [self effectivePageCount]) return nil;

    CGFloat targetDPI = self.targetDPI > 0 ? self.targetDPI : kSPDFDefaultPrintDPI;
    CGFloat renderZoom = MAX(kSPDFMinimumPrintRenderZoom, targetDPI / 72.0);
    char err[1024];
    while (renderZoom >= kSPDFMinimumPrintRenderZoom) {
        spdf_bitmap bitmap;
        if (spdf_render_page_rgba(self.document, (int)pageIndex, (float)renderZoom, &bitmap, err, sizeof(err))) {
            NSImage* image = spdf_print_image_from_bitmap(&bitmap, renderZoom, err, sizeof(err));
            spdf_free_bitmap(&bitmap);
            if (image) return image;
        }
        renderZoom *= 0.5;
    }
    return nil;
}

- (void)drawRect:(NSRect)dirtyRect {
    NSPrintInfo* info = NSPrintOperation.currentOperation.printInfo;
    NSSize paper = info.paperSize;
    NSInteger pageNumber = MAX(1, (NSInteger)floor(dirtyRect.origin.y / paper.height) + 1);
    NSInteger pageIndex = pageNumber - 1;
    if (pageIndex < 0 || pageIndex >= [self effectivePageCount]) return;

    NSRect pageRect = [self rectForPage:pageNumber];
    [[NSColor whiteColor] setFill];
    NSRectFill(pageRect);

    NSImage* image = [self highResolutionImageForPageIndex:pageIndex];
    if (!image && pageIndex < (NSInteger)self.fallbackPages.count)
        image = self.fallbackPages[(NSUInteger)pageIndex].image;
    if (!image) return;

    NSRect imageable = info.imageablePageBounds;
    imageable.origin.x += pageRect.origin.x;
    imageable.origin.y += pageRect.origin.y;
    CGFloat scale = MIN(NSWidth(imageable) / image.size.width, NSHeight(imageable) / image.size.height);
    NSSize drawSize = NSMakeSize(image.size.width * scale, image.size.height * scale);
    NSRect drawRect =
        NSMakeRect(imageable.origin.x + (NSWidth(imageable) - drawSize.width) / 2.0,
                   imageable.origin.y + (NSHeight(imageable) - drawSize.height) / 2.0, drawSize.width, drawSize.height);
    [image drawInRect:drawRect
              fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver
              fraction:1.0
        respectFlipped:YES
                 hints:@{NSImageHintInterpolation : @(NSImageInterpolationHigh)}];
}

@end
