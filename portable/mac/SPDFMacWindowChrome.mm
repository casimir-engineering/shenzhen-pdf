#import "SPDFMacWindowChrome.h"

SPDFWindowChromeAction spdf_window_chrome_action(NSUInteger clickCount, BOOL fullScreen, BOOL presentation) {
    if (clickCount < 2) return SPDFWindowChromeActionDrag;
    if (fullScreen || presentation) return SPDFWindowChromeActionNone;
    return SPDFWindowChromeActionZoom;
}
