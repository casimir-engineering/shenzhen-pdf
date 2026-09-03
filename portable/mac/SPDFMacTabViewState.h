#import <Cocoa/Cocoa.h>

#import "SPDFMacDelegatePrivate.h"

// Adopting one document's own view state. Every document (re)load and every tab
// switch funnels through -prepareSelectedTabViewState:path:, which makes it both
// the invalidation choke point for per-page caches and the single place a tab's
// per-document preferences become the window's live state. Split out of
// ShenzhenPDFMac.mm so that seam is readable on its own.
@interface ShenzhenMacDelegate (SPDFMacTabViewState)

- (void)prepareSelectedTabViewState:(SPDFDocumentTab*)tab path:(NSString*)path;
// A newly opened document starts at the launch default (settings.yaml
// "darkThemePreservesImages") and remembers its own choice from there.
- (void)seedKeepImageColorsForNewTab:(SPDFDocumentTab*)tab;
// The document view the app installs. A tab switch replaces it, so everything
// window-level it carries -- including the reading theme, whose gutter and page
// border a fresh Light view would silently drop -- is applied here.
- (SPDFDocumentView*)newDocumentView;
- (void)replaceDocumentViewForTabSwitch;

@end
