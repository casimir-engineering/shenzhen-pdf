#import <Cocoa/Cocoa.h>

@class SPDFDocumentTab;

void spdf_activate_window_for_view(NSView* view);

@protocol SPDFMacUIReader <NSObject>
- (BOOL)handlePresentationEvent:(NSEvent*)event;
- (BOOL)handleWindowArrangementShortcutEvent:(NSEvent*)event;
- (BOOL)handleTabStripMouseEvent:(NSEvent*)event;
- (BOOL)zoomWithScrollWheelEvent:(NSEvent*)event centeredAtWindowPoint:(NSPoint)windowPoint;
- (void)zoomWithMagnifyEvent:(NSEvent*)event centeredAtWindowPoint:(NSPoint)windowPoint;
- (BOOL)scrollViewShouldTurnWheelIntoPageChange:(NSEvent*)event;
- (void)nextPage:(id)sender;
- (void)previousPage:(id)sender;
- (void)documentScrollPositionChanged;
- (BOOL)documentArrowKeyDown:(NSEvent*)event;
- (BOOL)documentTypeToSearchKeyDown:(NSEvent*)event;
- (BOOL)documentViewHasLinkAtPageIndex:(NSInteger)pageIndex pagePoint:(NSPoint)pagePoint;
- (BOOL)documentViewOpenLinkAtPageIndex:(NSInteger)pageIndex pagePoint:(NSPoint)pagePoint;
- (void)documentViewSelectionChangedOnPage:(NSInteger)pageIndex from:(NSPoint)start to:(NSPoint)end;
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
- (void)moveTabFromIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex;
- (void)detachTabAtIndex:(NSInteger)index;
- (void)newTabRequested:(id)sender;
- (void)clearFindFieldFocus;
- (void)minimapDividerDraggedByDeltaX:(CGFloat)deltaX;
- (void)minimapDividerDidFinishDragging;
- (void)minimapViewDidRequestViewportTopFraction:(CGFloat)yFraction;
- (void)minimapViewDidRequestViewportTopFraction:(CGFloat)yFraction documentCenterX:(CGFloat)documentCenterX;
- (void)minimapViewDidFinishViewportDrag;
- (void)minimapViewDidRequestCenterAtDocumentPoint:(NSPoint)documentPoint;
- (void)minimapViewDidRequestCenterOnPage:(NSInteger)pageIndex
                          xFractionInPage:(CGFloat)xFraction
                          yFractionInPage:(CGFloat)yFraction;
- (void)minimapViewDidReceiveScrollWheel:(NSEvent*)event;
- (void)minimapViewDidReceiveZoomScrollWheel:(NSEvent*)event documentPoint:(NSPoint)documentPoint;
- (void)minimapViewDidReceiveMagnify:(NSEvent*)event documentPoint:(NSPoint)documentPoint;
- (NSArray<NSDictionary*>*)findScrollbarMarkers;
- (NSNumber*)commentIndexForSidebarRow:(NSInteger)row;
- (void)editComment:(id)sender;
- (void)deleteComment:(id)sender;
@end

@interface SPDFPaletteSearchField : NSSearchField
@property(nonatomic, weak) id<SPDFMacUIReader> reader;
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
