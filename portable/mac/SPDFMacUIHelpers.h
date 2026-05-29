#import <Cocoa/Cocoa.h>

@protocol SPDFMacUIReader <NSObject>
- (BOOL)handlePresentationEvent:(NSEvent*)event;
- (BOOL)handleTabStripMouseEvent:(NSEvent*)event;
- (BOOL)zoomWithScrollWheelEvent:(NSEvent*)event centeredAtWindowPoint:(NSPoint)windowPoint;
- (void)zoomWithMagnifyEvent:(NSEvent*)event centeredAtWindowPoint:(NSPoint)windowPoint;
- (BOOL)scrollViewShouldTurnWheelIntoPageChange:(NSEvent*)event;
- (void)nextPage:(id)sender;
- (void)previousPage:(id)sender;
- (void)documentScrollPositionChanged;
- (BOOL)documentArrowKeyDown:(NSEvent*)event;
- (BOOL)documentTypeToSearchKeyDown:(NSEvent*)event;
- (void)closePalette:(id)sender;
- (void)paletteMoveSelection:(NSInteger)delta;
- (void)activatePaletteSelection:(id)sender;
- (BOOL)openFilesFromPasteboard:(NSPasteboard*)pasteboard;
- (void)clearFindFieldFocus;
- (void)minimapDividerDraggedByDeltaX:(CGFloat)deltaX;
- (void)minimapDividerDidFinishDragging;
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
