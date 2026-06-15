#import <Cocoa/Cocoa.h>

@class SPDFDocumentTab;

void spdf_activate_window_for_view(NSView* view);
void spdf_set_menu_item_system_symbol(NSMenuItem* item, NSString* symbolName);

// Lazily install / tear down the listen-only CGEventTap that captures
// out-of-focus trackpad pinch (magnify) gestures. The install call is cheap and
// idempotent; it is invoked the first time the app resigns active (never at
// launch) so there is no launch-time cost and no launch-time permission prompt.
// If Input Monitoring permission is absent the tap simply does not arm and the
// feature stays inactive (logged under SPDF_ZOOM_PROFILE). Teardown is called on
// app termination so the CFMachPort / run-loop source are released.
void spdf_install_inactive_magnify_tap(void);
void spdf_teardown_inactive_magnify_tap(void);

@protocol SPDFMacUIReader <NSObject>
- (BOOL)handlePresentationEvent:(NSEvent*)event;
- (BOOL)handleWindowArrangementShortcutEvent:(NSEvent*)event;
- (BOOL)handleTabStripMouseEvent:(NSEvent*)event;
- (BOOL)zoomWithScrollWheelEvent:(NSEvent*)event centeredAtWindowPoint:(NSPoint)windowPoint;
- (void)zoomWithMagnifyEvent:(NSEvent*)event centeredAtWindowPoint:(NSPoint)windowPoint;
- (void)zoomWithMagnifyDelta:(CGFloat)delta centeredAtWindowPoint:(NSPoint)windowPoint;
- (BOOL)scrollViewShouldTurnWheelIntoPageChange:(NSEvent*)event;
- (void)nextPage:(id)sender;
- (void)previousPage:(id)sender;
- (void)documentScrollPositionChanged;
- (NSInteger)documentViewCurrentPageIndex;
- (BOOL)documentArrowKeyDown:(NSEvent*)event;
- (void)stopKeyboardScrollAnimation;
- (BOOL)documentTypeToSearchKeyDown:(NSEvent*)event;
- (BOOL)documentViewHasLinkAtPageIndex:(NSInteger)pageIndex pagePoint:(NSPoint)pagePoint;
- (BOOL)documentViewOpenLinkAtPageIndex:(NSInteger)pageIndex pagePoint:(NSPoint)pagePoint;
- (BOOL)documentViewSelectionChangedOnPage:(NSInteger)pageIndex from:(NSPoint)start to:(NSPoint)end;
- (void)documentViewDidBeginPan;
- (void)documentViewDidFinishPanMotion;
- (BOOL)documentViewInPresentationMode;
- (NSArray<NSDictionary*>*)commentAnnotationsForPage:(NSInteger)pageIndex;
- (void)documentViewHoverComment:(NSDictionary*)comment atWindowPoint:(NSPoint)windowPoint;
- (void)documentViewEndHoverComment;
- (void)showContextMenuForDocumentView:(NSView*)view event:(NSEvent*)event;
- (void)copySelection:(id)sender;
- (void)closePalette:(id)sender;
- (void)paletteMoveSelection:(NSInteger)delta;
- (void)activatePaletteSelection:(id)sender;
- (BOOL)openFilesFromPasteboard:(NSPasteboard*)pasteboard;
- (SPDFDocumentTab*)tabSnapshotForDragAtIndex:(NSInteger)index;
- (void)insertDraggedTab:(SPDFDocumentTab*)tab atIndex:(NSInteger)index;
- (void)selectTabAtIndex:(NSInteger)index;
- (void)closeTabAtIndex:(NSInteger)index;
- (void)showTabInFolderAtIndex:(NSInteger)index;
- (void)copyTabFileToPasteboardAtIndex:(NSInteger)index;
- (void)copyTabPathToPasteboardAtIndex:(NSInteger)index;
- (void)moveTabFromIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex;
- (void)detachTabAtIndex:(NSInteger)index;
- (void)newTabRequested:(id)sender;
- (void)clearFindFieldFocus;
- (void)sidebarDividerDraggedByDeltaX:(CGFloat)deltaX;
- (void)sidebarDividerDidFinishDragging;
- (void)minimapDividerDraggedByDeltaX:(CGFloat)deltaX;
- (void)minimapDividerDidFinishDragging;
- (void)minimapViewDidRequestViewportTopFraction:(CGFloat)yFraction;
- (void)minimapViewDidRequestViewportTopFraction:(CGFloat)yFraction documentCenterX:(CGFloat)documentCenterX;
- (void)minimapViewDidRequestViewportTopDocumentY:(CGFloat)documentTopY documentCenterX:(CGFloat)documentCenterX;
- (void)minimapViewDidFinishViewportDrag;
- (void)minimapViewDidRequestCenterAtDocumentPoint:(NSPoint)documentPoint;
- (void)minimapViewDidRequestCenterOnPage:(NSInteger)pageIndex
                          xFractionInPage:(CGFloat)xFraction
                          yFractionInPage:(CGFloat)yFraction;
- (void)minimapViewDidReceiveScrollWheel:(NSEvent*)event;
- (void)minimapViewDidReceiveZoomScrollWheel:(NSEvent*)event documentPoint:(NSPoint)documentPoint;
- (void)minimapViewDidReceiveMagnify:(NSEvent*)event documentPoint:(NSPoint)documentPoint;
- (void)minimapViewDidReceiveMagnifyDelta:(CGFloat)delta documentPoint:(NSPoint)documentPoint;
- (NSArray<NSDictionary*>*)findScrollbarMarkers;
- (NSNumber*)commentIndexForSidebarRow:(NSInteger)row;
- (void)editComment:(id)sender;
- (void)deleteComment:(id)sender;
@end

@interface SPDFPaletteSearchField : NSSearchField
@property(nonatomic, weak) id<SPDFMacUIReader> reader;
@end

@interface SPDFFindSearchField : NSSearchField
@end

@interface SPDFToolbarStackView : NSStackView
@end

@interface SPDFToolbarDragView : NSView
@end

@interface SPDFToolbarDragLabel : NSTextField
+ (instancetype)labelWithString:(NSString*)stringValue;
@end

@interface SPDFToolbarToggleButton : NSButton
@property(nonatomic) BOOL active;
- (instancetype)initWithTitle:(NSString*)title target:(id)target action:(SEL)action;
@end

@interface SPDFToolbarMenuButton : NSButton
@end

@interface SPDFDropView : NSView <NSDraggingDestination>
@property(nonatomic, weak) id<SPDFMacUIReader> reader;
@end

@interface SPDFMinimapDividerView : NSView
@property(nonatomic, weak) id<SPDFMacUIReader> reader;
@end

@interface SPDFSidebarDividerView : NSView
@property(nonatomic, weak) id<SPDFMacUIReader> reader;
@end

@interface SPDFScrollView : NSScrollView
@property(nonatomic, weak) id<SPDFMacUIReader> reader;
@end

@interface SPDFWindow : NSWindow
@property(nonatomic, weak) id<SPDFMacUIReader> reader;
@end

@interface SPDFShortcutHelpPanel : NSPanel
@end

@interface SPDFPresentationOverlayView : NSView
@property(nonatomic, weak) id<SPDFMacUIReader> reader;
@end

@interface SPDFSidebarTableView : NSTableView
@property(nonatomic, weak) id<SPDFMacUIReader> reader;
@end

@interface SPDFFindMarkerScroller : NSScroller
@property(nonatomic, weak) id<SPDFMacUIReader> reader;
@end
