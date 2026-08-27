#import <Foundation/Foundation.h>

@class NSEvent;

// Implemented by SPDFWindow. Views embedded in the transparent title bar use
// this narrow protocol to preserve one native drag/zoom policy without knowing
// about the concrete application window class.
@protocol SPDFWindowChromeHandling <NSObject>
- (void)handleChromeMouseDown:(NSEvent*)event;
@end

typedef NS_ENUM(NSInteger, SPDFWindowChromeAction) {
    SPDFWindowChromeActionNone = 0,
    SPDFWindowChromeActionDrag,
    SPDFWindowChromeActionZoom,
};

SPDFWindowChromeAction spdf_window_chrome_action(NSUInteger clickCount, BOOL fullScreen, BOOL presentation);
