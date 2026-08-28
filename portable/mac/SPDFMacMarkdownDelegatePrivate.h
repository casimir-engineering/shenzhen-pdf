#pragma once

#import "SPDFMacDelegatePrivate.h"
#import "SPDFMacMarkdownSession.h"

NS_ASSUME_NONNULL_BEGIN

// Private bridge used by the focused Markdown and shared file-action category
// implementations. Keeping these declarations here avoids growing the main
// delegate interface with cross-module implementation details.
@interface ShenzhenMacDelegate (SPDFMacMarkdownHostAccess)
- (nullable NSDictionary*)fileAttributesForPath:(NSString*)path;
- (void)recordFileAttributes:(NSDictionary*)attributes forTab:(SPDFDocumentTab*)tab;
- (void)prepareSelectedTabViewState:(SPDFDocumentTab*)tab path:(NSString*)path;
- (void)showUnavailableSelectedTab:(SPDFDocumentTab*)tab
                              path:(NSString*)path
                           message:(NSString*)message
                     showOpenError:(BOOL)showOpenError
                             error:(const char* _Nullable)error;
- (NSInteger)indexOfTabForPath:(NSString*)path;
- (void)updateTabStrip;
- (void)updateControls;
- (void)syncToolbarState;
- (void)persistActiveState;
- (void)rememberRecentlyOpenedPath:(NSString*)path;
- (void)setSidebarActuallyVisible:(BOOL)visible;
- (void)setMinimapActuallyVisible:(BOOL)visible;
- (void)rebuildSidebar;
- (void)syncSidebarModeControlSegmentsForSearchAvailability:(BOOL)hasSearch;
- (void)syncSidebarFilterField;
- (void)syncSidebarTableColumnWidth;
- (void)restoreSidebarWidth;
- (void)selectCurrentSidebarRow;
- (void)applySinglePageMinimapDefaultToTab:(SPDFDocumentTab*)tab pageCount:(NSInteger)pageCount;
- (void)showError:(NSString*)message detail:(NSString*)detail;
- (void)ensureSecurityAccessForPath:(NSString*)path;
- (NSString*)displayNameForPathConsideringOpenTabs:(NSString*)path;
- (void)copyPathStringToPasteboard:(NSString*)path statusMessage:(NSString*)statusMessage;
- (void)copyTabFileToPasteboardAtIndex:(NSInteger)index;
- (void)selectPreviousTab:(nullable id)sender;
- (void)selectNextTab:(nullable id)sender;
- (void)beginOrSustainKeyboardScrollInDirection:(CGFloat)direction
                                           axis:(NSInteger)axis
                                        keyCode:(unsigned short)keyCode
                                       isRepeat:(BOOL)isRepeat;
@end

@interface ShenzhenMacDelegate (SPDFMacMarkdownIntegration)
- (void)installMarkdownHostInDocumentContainer;
- (SPDFMacMarkdownSession*)activeMarkdownSession;
- (BOOL)isMarkdownActive;
- (BOOL)hasActiveDocument;
- (void)deactivateActiveMarkdownView;
- (void)loadSelectedMarkdownTab:(SPDFDocumentTab*)tab;
- (void)rememberActiveMarkdownStateForTab:(SPDFDocumentTab*)tab;
- (void)startMarkdownFindForQuery:(NSString*)query preferredIndex:(NSInteger)preferredIndex;
- (void)moveMarkdownFindForward:(BOOL)forward;
- (void)clearMarkdownFindResults;
- (NSString*)markdownSelectedText;
- (void)printActiveMarkdown;
- (void)saveActiveMarkdownAsPDF;
- (void)updateControlsForActiveMarkdown;
- (void)updateMarkdownFontControls;
- (void)decreaseMarkdownFontSize:(nullable id)sender;
- (void)increaseMarkdownFontSize:(nullable id)sender;
- (BOOL)markdownHasChapters;
- (BOOL)markdownHasSearchSidebar;
- (void)rebuildMarkdownSidebar;
- (void)activateMarkdownSidebarItem:(NSDictionary*)item;
@end

@interface ShenzhenMacDelegate (SPDFMacMarkdownInteractionIntegration)
- (void)updateMarkdownMinimap;
- (nullable NSDictionary*)currentMarkdownChapterItem;
- (BOOL)markdownArrowKeyDown:(NSEvent*)event;
- (BOOL)markdownZoomWithScrollWheelEvent:(NSEvent*)event centeredAtWindowPoint:(NSPoint)windowPoint;
- (void)markdownZoomWithMagnifyDelta:(CGFloat)delta centeredAtWindowPoint:(NSPoint)windowPoint;
- (void)markdownDocumentScrollPositionChanged;
- (void)markdownMinimapViewportTopFraction:(CGFloat)yFraction documentCenterX:(CGFloat)documentCenterX;
- (void)markdownMinimapViewportTopDocumentY:(CGFloat)documentTopY documentCenterX:(CGFloat)documentCenterX;
- (void)markdownMinimapCenterAtDocumentPoint:(NSPoint)documentPoint;
- (void)markdownMinimapCenterOnPage:(NSInteger)pageIndex
                    xFractionInPage:(CGFloat)xFraction
                    yFractionInPage:(CGFloat)yFraction;
- (void)markdownMinimapReceiveScrollWheel:(NSEvent*)event;
- (void)markdownMinimapReceiveZoomScrollWheel:(NSEvent*)event documentPoint:(NSPoint)documentPoint;
- (void)markdownMinimapReceiveMagnifyDelta:(CGFloat)delta documentPoint:(NSPoint)documentPoint;
- (void)markdownPreviousPage;
- (void)markdownNextPage;
- (void)markdownFirstPage;
- (void)markdownLastPage;
- (void)markdownGoToPage:(NSInteger)pageIndex;
- (void)markdownZoomByFactor:(CGFloat)factor;
- (void)markdownApplyFitMode:(SPDFFitMode)fitMode;
- (void)relayoutActiveMarkdownForViewportChange;
@end

@interface ShenzhenMacDelegate (SPDFMacMarkdownFileActions)
- (void)openInExternalReader:(nullable id)sender;
- (void)showPathInFolder:(NSString*)path;
- (void)showInFolder:(nullable id)sender;
- (void)copyCurrentDocumentPath:(nullable id)sender;
- (void)copyCurrentDocumentFile:(nullable id)sender;
- (void)copyCurrentPageImage:(nullable id)sender;
- (void)copyCurrentPageAsPDF:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
