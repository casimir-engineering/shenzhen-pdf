#import "SPDFMarkdownImageRecolor.h"

#import <objc/runtime.h>

#import "spdf_recolor.h"

CGImageRef SPDFMarkdownCreateDarkRecoloredImage(CGImageRef source) {
    if (!source) return NULL;
    size_t width = CGImageGetWidth(source);
    size_t height = CGImageGetHeight(source);
    if (width == 0 || height == 0) return NULL;
    // Guard against a pathological asset turning a scroll into a stall; an
    // image this large is drawn downscaled anyway.
    if (width > 8192 || height > 8192) return NULL;

    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if (!space) return NULL;
    size_t stride = width * 4;
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, stride, space,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return NULL;

    CGContextDrawImage(context, CGRectMake(0, 0, (CGFloat)width, (CGFloat)height), source);
    unsigned char* pixels = (unsigned char*)CGBitmapContextGetData(context);
    if (!pixels) {
        CGContextRelease(context);
        return NULL;
    }

    // One table per process: the dark palette is fixed, and building it per
    // image would cost more than the remap on a small badge.
    static spdf_recolor_table table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      spdf_recolor_table_init(&table, SPDF_RECOLOR_LUMA_REMAP, spdf_recolor_default_dark_theme());
    });
    spdf_recolor_rgba(pixels, (int)width, (int)height, (int)stride, &table);

    CGImageRef recolored = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return recolored;
}

// Cached on the attachment so the lifetime of the twin matches the lifetime of
// the image it was derived from -- no pointer-keyed cache that could outlive a
// freed CGImage and hand back the wrong pixels.
static const void* kSPDFRecoloredImageKey = &kSPDFRecoloredImageKey;

@interface SPDFMarkdownRecoloredImageBox : NSObject
@property(nonatomic, readonly) CGImageRef image;
@end

@implementation SPDFMarkdownRecoloredImageBox {
    CGImageRef _image;
}
- (instancetype)initWithImage:(CGImageRef)image {
    if ((self = [super init])) _image = image ? CGImageRetain(image) : NULL;
    return self;
}
- (CGImageRef)image {
    return _image;
}
- (void)dealloc {
    if (_image) CGImageRelease(_image);
}
@end

CGImageRef SPDFMarkdownDarkRecoloredImageForAttachment(NSTextAttachment* attachment, CGImageRef source) {
    if (!attachment || !source) return NULL;
    SPDFMarkdownRecoloredImageBox* cached = objc_getAssociatedObject(attachment, kSPDFRecoloredImageKey);
    // A box holding NULL is a remembered failure: do not retry it every frame.
    if (cached) return cached.image;
    CGImageRef recolored = SPDFMarkdownCreateDarkRecoloredImage(source);
    SPDFMarkdownRecoloredImageBox* box = [[SPDFMarkdownRecoloredImageBox alloc] initWithImage:recolored];
    if (recolored) CGImageRelease(recolored);
    objc_setAssociatedObject(attachment, kSPDFRecoloredImageKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return box.image;
}
