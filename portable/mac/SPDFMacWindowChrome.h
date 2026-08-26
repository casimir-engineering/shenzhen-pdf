#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SPDFWindowChromeAction) {
    SPDFWindowChromeActionNone = 0,
    SPDFWindowChromeActionDrag,
    SPDFWindowChromeActionZoom,
};

SPDFWindowChromeAction spdf_window_chrome_action(NSUInteger clickCount, BOOL fullScreen, BOOL presentation);
