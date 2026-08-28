#import "../SPDFMacUIHelpers.h"

void spdf_activate_window_for_view(NSView* view) {
    (void)view;
}

// Focused Markdown test executables do not link the complete app UI helpers.
// This minimal implementation supplies the shared superclass while production
// builds use SPDFMacUIHelpers.mm.
static NSMapTable<SPDFScrollView*, id<SPDFMacUIReader>>* TestScrollViewReaders(void) {
    static NSMapTable<SPDFScrollView*, id<SPDFMacUIReader>>* readers = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      readers = [NSMapTable weakToWeakObjectsMapTable];
    });
    return readers;
}

@implementation SPDFScrollView
- (id<SPDFMacUIReader>)reader {
    return [TestScrollViewReaders() objectForKey:self];
}
- (void)setReader:(id<SPDFMacUIReader>)reader {
    if (reader)
        [TestScrollViewReaders() setObject:reader forKey:self];
    else
        [TestScrollViewReaders() removeObjectForKey:self];
}
@end

// The production marker drawing lives in SPDFMacUIHelpers.mm; focused test
// executables only need the class and its reader wiring to exist.
@implementation SPDFFindMarkerScroller {
    __weak id<SPDFMacUIReader> _testReader;
}
- (id<SPDFMacUIReader>)reader {
    return _testReader;
}
- (void)setReader:(id<SPDFMacUIReader>)reader {
    _testReader = reader;
}
@end

// Same clamp behavior as the production SPDFDocumentClipView in
// SPDFMacUIHelpers.mm, which these focused executables do not link.
@implementation SPDFDocumentClipView

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _horizontalLockMinX = NAN;
        _horizontalLockMaxX = NAN;
    }
    return self;
}

- (NSRect)constrainBoundsRect:(NSRect)proposedBounds {
    NSRect bounds = [super constrainBoundsRect:proposedBounds];
    if (isfinite(_horizontalLockMinX))
        bounds.origin.x = MAX(_horizontalLockMinX, MIN(bounds.origin.x, MAX(_horizontalLockMinX, _horizontalLockMaxX)));
    return bounds;
}

@end
