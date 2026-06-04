#import <Cocoa/Cocoa.h>

#import "SPDFMacDocumentView.h"
#import "SPDFMacMinimapView.h"
#import "SPDFMacModels.h"
#import "SPDFMacTabStripView.h"
#import "SPDFMacUIHelpers.h"

#include "shenzhen_pdf_core.h"

@interface ShenzhenMacDelegate : NSObject <NSApplicationDelegate,
                                           NSWindowDelegate,
                                           NSSplitViewDelegate,
                                           NSTableViewDataSource,
                                           NSTableViewDelegate,
                                           NSSearchFieldDelegate,
                                           NSTextFieldDelegate,
                                           NSMenuItemValidation> {
    NSWindow* _window;
    SPDFTabStripView* _tabStrip;
    SPDFToolbarStackView* _toolbar;
    NSSplitView* _splitView;
    NSTableView* _sidebarTable;
    NSView* _sidebarContainer;
    NSView* _documentContainer;
    SPDFScrollView* _pageScrollView;
    SPDFDocumentView* _pageView;
    SPDFMinimapView* _minimapView;
    SPDFMinimapDividerView* _minimapDividerView;
    SPDFFindMarkerScroller* _markerScroller;
    SPDFPresentationOverlayView* _presentationOverlayView;
    NSLayoutConstraint* _minimapWidthConstraint;
    NSLayoutConstraint* _minimapDividerWidthConstraint;
    NSLayoutConstraint* _pageScrollToMinimapConstraint;
    NSLayoutConstraint* _pageScrollFullWidthConstraint;
    NSLayoutConstraint* _tabStripHeightConstraint;
    NSLayoutConstraint* _toolbarHeightConstraint;
    NSButton* _prevButton;
    NSButton* _nextButton;
    NSTextField* _pageField;
    NSTextField* _pageCountLabel;
    NSButton* _zoomOutButton;
    NSButton* _zoomInButton;
    NSPopUpButton* _fitModePopup;
    NSButton* _continuousButton;
    NSButton* _sidebarToggleButton;
    NSButton* _minimapToggleButton;
    NSSearchField* _searchField;
    NSButton* _findRegexCheckbox;
    BOOL _findRegexMultiline;
    NSButton* _ocrButton;
    NSButton* _translateButton;
    NSBox* _ocrSeparator;
    NSButton* _findPrevButton;
    NSButton* _findNextButton;
    NSTextField* _findCountLabel;
    NSView* _toolbarSpacer;
    NSButton* _toolbarOverflowButton;
    NSMenu* _toolbarOverflowMenu;
    NSMenu* _recentlyOpenedMenu;
    NSTextField* _statusLabel;
    NSSegmentedControl* _sidebarModeControl;
    NSSearchField* _sidebarFilterField;
    NSPanel* _palettePanel;
    NSSearchField* _paletteSearchField;
    NSButton* _paletteAllDocsCheckbox;
    NSTableView* _paletteTable;
    NSPanel* _ocrInstallPanel;
    NSProgressIndicator* _ocrInstallProgress;
    NSTextView* _ocrInstallLog;
    NSTask* _ocrInstallTask;
    NSPanel* _ocrProgressPanel;
    NSTextField* _ocrProgressTitleLabel;
    NSTextField* _ocrProgressDetailLabel;
    NSProgressIndicator* _ocrProgressIndicator;
    NSPanel* _translationInstallPanel;
    NSTextField* _translationInstallTitleLabel;
    NSProgressIndicator* _translationInstallProgress;
    NSTextView* _translationInstallLog;
    NSTask* _translationInstallTask;
    NSPanel* _translationProgressPanel;
    NSTextField* _translationProgressTitleLabel;
    NSTextField* _translationProgressDetailLabel;
    NSProgressIndicator* _translationProgressIndicator;
    NSButton* _translationProgressCancelButton;
    NSTask* _translationTask;
    NSPanel* _commentPanel;
    NSTextField* _commentLabel;
    NSPanel* _shortcutHelpPanel;
    NSSearchField* _shortcutHelpSearchField;
    NSTableView* _shortcutHelpTable;
    NSButton* _shortcutHelpDisableButton;
    NSMutableArray<NSDictionary*>* _shortcutHelpRows;
    NSMutableArray<NSDictionary*>* _paletteResults;
    NSInteger _paletteMode;
    NSUInteger _paletteSearchGeneration;
    id _paletteEventMonitor;
    id _presentationEventMonitor;
    id _presentationGlobalEventMonitor;
    NSOperationQueue* _renderQueue;
    NSOperationQueue* _minimapQueue;
    NSOperationQueue* _preloadQueue;
    NSOperationQueue* _findQueue;
    NSMutableSet<NSNumber*>* _queuedRenderPages;
    NSMutableDictionary<NSNumber*, NSOperation*>* _queuedRenderOperations;
    NSMutableSet<NSNumber*>* _queuedMinimapThumbnailPages;
    NSTimer* _findFlashTimer;
    NSTimeInterval _findFlashStartTime;

    spdf_document* _doc;
    spdf_outline _outline;
    spdf_comments _comments;
    BOOL _activeMetadataBorrowed;
    SPDFDocumentTab* _activeMetadataTab;
    NSMutableArray<NSDictionary*>* _sidebarItems;
    NSString* _chapterFilterText;
    NSString* _commentFilterText;
    NSMutableArray<SPDFRenderedPage*>* _renderedPages;
    NSMutableArray<SPDFDocumentTab*>* _tabs;
    NSMutableArray<NSDictionary*>* _favorites;
    NSMutableDictionary<NSString*, NSMutableDictionary*>* _documentStates;
    NSMutableArray<NSString*>* _recentlyOpenedPaths;
    NSMutableArray<NSString*>* _closedDocumentPaths;
    NSDictionary* _paletteFavoritePendingDelete;
    NSMutableDictionary<NSNumber*, NSArray<NSValue*>*>* _findHighlights;
    NSMutableArray<NSDictionary*>* _findMatches;
    NSMutableSet<NSString*>* _preloadingPaths;
    NSMutableDictionary<NSString*, NSString*>* _preloadTokens;
    NSUInteger _findGeneration;
    BOOL _findSearchInProgress;
    NSString* _path;
    NSString* _pendingOpenPath;
    NSMutableArray<NSString*>* _pendingOpenPaths;
    NSInteger _pageIndex;
    NSInteger _highlightPageIndex;
    NSInteger _findMatchIndex;
    NSInteger _selectionPageIndex;
    NSString* _selectedText;
    NSInteger _contextPageIndex;
    NSPoint _contextPagePoint;
    NSInteger _contextCommentIndex;
    NSString* _commentAuthor;
    NSString* _translationSourceLanguage;
    NSString* _translationTargetLanguage;
    CGFloat _zoom;
    CGFloat _rememberedCustomZoom;
    SPDFFitMode _fitMode;
    SPDFViewMode _viewMode;
    NSInteger _selectedTabIndex;
    NSUInteger _renderGeneration;
    NSTimer* _zoomFinishTimer;
    BOOL _uiReady;
    BOOL _updatingSelection;
    BOOL _updatingFromScroll;
    BOOL _suppressScrollCallbacks;
    BOOL _suppressViewportRerender;
    BOOL _liveZooming;
    BOOL _minimapPrecisionViewportDragActive;
    BOOL _sidebarPreferredVisible;
    BOOL _sidebarVisible;
    BOOL _minimapPreferredVisible;
    BOOL _minimapVisible;
    BOOL _presentationMode;
    BOOL _presentationEnteredFullScreen;
    BOOL _presentationUsingBorderlessWindow;
    NSRect _presentationPreviousWindowFrame;
    NSWindowStyleMask _presentationPreviousWindowStyleMask;
    NSInteger _presentationPreviousWindowLevel;
    NSWindowCollectionBehavior _presentationPreviousCollectionBehavior;
    NSWindowTitleVisibility _presentationPreviousTitleVisibility;
    BOOL _presentationPreviousTitlebarAppearsTransparent;
    BOOL _presentationPreviousMovable;
    BOOL _presentationPreviousMovableByWindowBackground;
    BOOL _presentationPreviousHasShadow;
    SEL _pendingWindowArrangementAction;
    NSTimeInterval _lastPresentationEventTimestamp;
    NSEventType _lastPresentationEventType;
    NSInteger _lastPresentationEventKeyCode;
    NSInteger _lastPresentationEventButtonNumber;
    SPDFViewMode _presentationPreviousViewMode;
    SPDFFitMode _presentationPreviousFitMode;
    BOOL _presentationPreviousSidebarPreferredVisible;
    BOOL _presentationPreviousMinimapPreferredVisible;
    BOOL _ocrInstallRunning;
    BOOL _translationRunning;
    BOOL _translationInstallRunning;
    BOOL _translationCancelRequested;
    BOOL _showShortcutHelpOnLaunch;
    BOOL _tabStripCapturingMouse;
    BOOL _terminateOnlyThisProcess;
    BOOL _suppressSessionWriteOnTerminate;
    BOOL _suspendPersistentStateSaves;
    BOOL _needsDeferredPersistentStateSave;
    BOOL _updatingSidebarFilterField;
    NSArray<NSDictionary*>* _pendingTranslationItems;
    BOOL _restoringSidebarLayout;
    BOOL _allowSidebarWidthPersistence;
    CGFloat _sidebarWidth;
    CGFloat _minimapWidth;
    NSSize _restoredWindowContentSize;
    NSRect _restoredWindowFrame;
    BOOL _hasRestoredWindowFrame;
    NSString* _windowSessionID;
    NSMutableArray<NSString*>* _pendingRestoreWindowIDs;
    NSInteger _pendingFindPreferredPage;
    NSInteger _pendingFindPreferredMatchIndex;
}
@property(nonatomic, copy) NSString* initialPath;
@property(nonatomic, copy) NSString* restoreWindowID;
@property(nonatomic) BOOL detachedTabLaunch;
- (BOOL)scrollViewShouldTurnWheelIntoPageChange:(NSEvent*)event;
- (BOOL)zoomWithScrollWheelEvent:(NSEvent*)event centeredAtWindowPoint:(NSPoint)windowPoint;
- (void)zoomWithMagnifyEvent:(NSEvent*)event centeredAtWindowPoint:(NSPoint)windowPoint;
- (void)zoomByFactor:(CGFloat)factor centeredAtWindowPoint:(NSPoint)windowPoint;
- (void)beginLiveZoomByFactor:(CGFloat)factor centeredAtWindowPoint:(NSPoint)windowPoint;
- (void)documentScrollPositionChanged;
- (BOOL)documentViewHasLinkAtPageIndex:(NSInteger)pageIndex pagePoint:(NSPoint)pagePoint;
- (BOOL)documentViewOpenLinkAtPageIndex:(NSInteger)pageIndex pagePoint:(NSPoint)pagePoint;
- (void)documentViewSelectionChangedOnPage:(NSInteger)pageIndex from:(NSPoint)start to:(NSPoint)end;
- (BOOL)documentViewHandlePresentationMouseDown:(NSEvent*)event;
- (BOOL)handlePresentationEvent:(NSEvent*)event;
- (NSInteger)presentationMouseActionForEvent:(NSEvent*)event;
- (BOOL)handleTabStripMouseEvent:(NSEvent*)event;
- (BOOL)documentViewInPresentationMode;
- (void)copySelection:(id)sender;
- (void)translateDocument:(id)sender;
- (void)rotateClockwise:(id)sender;
- (void)rotateAnticlockwise:(id)sender;
- (SPDFDocumentTab*)tabSnapshotForDragAtIndex:(NSInteger)index;
- (void)insertDraggedTab:(SPDFDocumentTab*)tab atIndex:(NSInteger)index;
- (void)selectTabAtIndex:(NSInteger)index;
- (void)closeTabAtIndex:(NSInteger)index;
- (void)moveTabFromIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex;
- (void)detachTabAtIndex:(NSInteger)index;
- (void)newTabRequested:(id)sender;
- (void)previousPage:(id)sender;
- (void)nextPage:(id)sender;
- (void)performWindowArrangementAction:(SEL)action sender:(id)sender;
- (void)drainPendingWindowArrangementAction;
- (BOOL)deferWindowArrangementActionIfNeeded:(SEL)action sender:(id)sender;
- (void)openPath:(NSString*)path;
- (void)openPaths:(NSArray<NSString*>*)paths;
- (void)openRecentDocument:(id)sender;
- (void)reopenLastClosedDocument:(id)sender;
- (void)focusFind:(id)sender;
- (void)showFindPalette:(id)sender;
- (void)toggleFindRegex:(id)sender;
- (void)toggleFindRegexMultiline:(id)sender;
- (void)openStateJSONFile:(id)sender;
- (void)revealSettingsFolder:(id)sender;
- (NSString*)documentStateKeyForPath:(NSString*)path;
- (void)applyStoredDocumentStateToTab:(SPDFDocumentTab*)tab;
- (void)saveDocumentStateForTab:(SPDFDocumentTab*)tab;
- (void)paletteMoveSelection:(NSInteger)delta;
- (void)closePalette:(id)sender;
- (void)activatePaletteSelection:(id)sender;
- (void)paletteFavoriteDeleteClicked:(id)sender;
- (SPDFDocumentView*)newDocumentView;
- (void)replaceDocumentViewForTabSwitch;
- (SPDFDocumentTab*)selectedTab;
- (void)clearActiveMetadata;
- (void)adoptCachedMetadataForTab:(SPDFDocumentTab*)tab;
- (void)discardCachedRuntimeForTab:(SPDFDocumentTab*)tab;
- (void)closeActiveDocumentIfUnowned;
- (void)cancelInactiveTabPreloads;
- (BOOL)preloadToken:(NSString*)token isCurrentForPath:(NSString*)standardizedPath;
- (void)finishPreloadForPath:(NSString*)standardizedPath token:(NSString*)token;
- (void)updateFindControls;
- (void)updateMinimap;
- (void)showEmptyDocumentViewWithMessage:(NSString*)message;
- (void)renderDocumentAndScrollToPage:(NSInteger)pageIndex alignTop:(BOOL)alignTop;
- (void)renderDocumentAndScrollToPage:(NSInteger)pageIndex
                             alignTop:(BOOL)alignTop
                        restoreOrigin:(NSValue*)restoreOrigin;
- (CGFloat)zoomForFitMode:(SPDFFitMode)fitMode pageIndex:(NSInteger)pageIndex;
- (CGFloat)zoomForFitMode:(SPDFFitMode)fitMode
                 pageSize:(NSSize)pageSize
                 clipSize:(NSSize)clipSize
             fallbackZoom:(CGFloat)fallbackZoom;
- (void)scrollDocumentClipViewToOrigin:(NSPoint)origin notify:(BOOL)notify;
- (void)scrollDocumentClipViewToOrigin:(NSPoint)origin pageIndexHint:(NSInteger)pageIndex notify:(BOOL)notify;
- (void)scrollDocumentClipViewToDocumentOrigin:(NSPoint)origin notify:(BOOL)notify;
- (NSPoint)normalizedDocumentScrollOrigin:(NSPoint)origin forPageIndex:(NSInteger)pageIndex;
- (CGFloat)singlePageDocumentScrollOriginYForPageIndex:(NSInteger)pageIndex;
- (BOOL)normalizeSinglePageScrollPositionFromUserScroll;
- (void)stabilizeDocumentLayoutWithRestoreOrigin:(NSValue*)restoreOrigin
                                        alignTop:(BOOL)alignTop
                                      generation:(NSUInteger)generation
                                            path:(NSString*)path;
- (void)minimapViewDidRequestScrollToFraction:(CGFloat)yFraction;
- (void)minimapViewDidRequestViewportTopFraction:(CGFloat)yFraction;
- (void)minimapViewDidRequestViewportTopFraction:(CGFloat)yFraction documentCenterX:(CGFloat)documentCenterX;
- (void)minimapViewDidFinishViewportDrag;
- (void)minimapViewDidRequestScrollToPage:(NSInteger)pageIndex yFractionInPage:(CGFloat)yFraction;
- (void)minimapViewDidRequestCenterAtDocumentPoint:(NSPoint)documentPoint;
- (void)minimapViewDidRequestCenterOnPage:(NSInteger)pageIndex
                          xFractionInPage:(CGFloat)xFraction
                          yFractionInPage:(CGFloat)yFraction;
- (void)minimapViewDidReceiveScrollWheel:(NSEvent*)event;
- (void)minimapViewDidReceiveZoomScrollWheel:(NSEvent*)event documentPoint:(NSPoint)documentPoint;
- (void)minimapViewDidReceiveMagnify:(NSEvent*)event documentPoint:(NSPoint)documentPoint;
- (BOOL)openFilesFromPasteboard:(NSPasteboard*)pasteboard;
- (void)showContextMenuForDocumentView:(NSView*)view event:(NSEvent*)event;
- (void)setCommentAuthor:(id)sender;
- (void)editComment:(id)sender;
- (void)deleteComment:(id)sender;
- (NSNumber*)commentIndexForSidebarRow:(NSInteger)row;
- (BOOL)documentArrowKeyDown:(NSEvent*)event;
- (BOOL)documentTypeToSearchKeyDown:(NSEvent*)event;
- (void)goToAdjacentPagePreservingRelativePosition:(NSInteger)delta;
- (void)installPresentationEventMonitor;
- (void)removePresentationEventMonitor;
- (void)writeSessionStateForCurrentWindow;
- (void)removeSessionStateForCurrentWindow;
- (void)savePersistentState;
- (void)performStartupDocumentWork;
- (void)performWithBatchedPersistentStateSaves:(void (^)(void))block;
- (void)dismissTabHoverPanel;
- (NSArray<NSNumber*>*)visibleDocumentPageIndexesWithExtraRadius:(NSInteger)radius
                                                   preferredPage:(NSInteger*)preferredPageOut;
- (void)queueVisibleDocumentPageRendersForCurrentViewportForceHighPriority:(BOOL)forceHighPriority;
- (void)syncCurrentPageFromVisibleViewportQueueRenders:(BOOL)queueRenders forceHighPriority:(BOOL)forceHighPriority;
- (NSUInteger)estimatedRenderedImageByteCostForPage:(SPDFRenderedPage*)page
                                               zoom:(CGFloat)zoom
                                       displayScale:(CGFloat)displayScale;
- (BOOL)shouldKeepFullRenderedDocumentAtCurrentZoom;
- (NSInteger)backgroundRenderBatchSizeForCurrentZoom;
- (BOOL)canOpenDocumentAtPath:(NSString*)path showError:(BOOL)showError;
- (NSArray<NSString*>*)openableDocumentPathsFromPaths:(NSArray<NSString*>*)paths showErrors:(BOOL)showErrors;
- (BOOL)hasOtherShenzhenWindows;
- (void)activateWindowForExternalOpen;
- (void)spawnPendingRestoredWindowsIfNeeded;
- (void)showPathInFolder:(NSString*)path;
- (NSArray<NSDictionary*>*)commentAnnotationsForPage:(NSInteger)pageIndex;
- (void)documentViewHoverComment:(NSDictionary*)comment atWindowPoint:(NSPoint)windowPoint;
- (void)documentViewEndHoverComment;
- (void)setMinimapActuallyVisible:(BOOL)visible;
- (void)minimapDividerDraggedByDeltaX:(CGFloat)deltaX;
- (void)minimapDividerDidFinishDragging;
- (void)clearFindFieldFocus;
- (void)clearPageFieldFocus;
- (void)clearToolbarFieldFocusForTabSwitch;
- (void)restoreSidebarWidth;
- (void)leavePresentationModeAndExitFullScreen:(BOOL)exitFullScreen sender:(id)sender;
- (void)activateSidebarRow:(id)sender;
- (void)scrollToPageRect:(NSRect)targetRect pageIndex:(NSInteger)pageIndex;
- (void)flashPageRect:(NSRect)targetRect pageIndex:(NSInteger)pageIndex;
- (CGFloat)paletteHeightForRow:(NSInteger)row;
- (void)updatePalettePanelFramePreservingTop:(BOOL)preserveTop;
- (void)scrollPaletteRowToVisibleWithHeader:(NSInteger)row;
- (void)restorePaletteSelectionAfterReloadFromRow:(NSInteger)previousRow;
- (void)rememberActiveTabFindState;
- (void)startFindForCurrentQueryResetSavedIndex:(BOOL)resetSavedIndex revealMatch:(BOOL)revealMatch;
- (void)invalidateFindMarkers;
- (NSArray<NSDictionary*>*)findScrollbarMarkers;
- (BOOL)isAutoFitMode:(SPDFFitMode)fitMode;
- (void)relayoutDocumentForViewportChange;
- (NSString*)currentCommentAuthor;
- (void)normalizeSidebarModeControlWidths;
- (void)enqueueNearbyPageRendersForGeneration:(NSUInteger)generation preferredPage:(NSInteger)preferredPage;
- (void)evictDistantRenderedPageImages;
- (void)scheduleNearbyPageRendersAfterFirstPaintForGeneration:(NSUInteger)generation
                                                preferredPage:(NSInteger)preferredPage;
- (void)schedulePostFirstPaintWorkForGeneration:(NSUInteger)generation
                                           path:(NSString*)path
                            savedFindMatchIndex:(NSInteger)savedFindMatchIndex
                                  restoreSearch:(BOOL)restoreSearch
                            preferredRenderPage:(NSInteger)preferredRenderPage;
@end

@interface ShenzhenMacDelegate (SPDFMacUIReaderConformance) <SPDFMacUIReader>
@end

@interface ShenzhenMacDelegate (ShortcutHelp)
- (NSArray<NSDictionary*>*)shortcutHelpCatalog;
- (void)refreshShortcutHelpRows;
- (NSView*)shortcutKeycapsViewForKeys:(NSArray<NSString*>*)keys;
- (void)showShortcutHelp:(id)sender;
- (void)closeShortcutHelp:(id)sender;
- (void)disableLaunchShortcutHelp:(id)sender;
@end
