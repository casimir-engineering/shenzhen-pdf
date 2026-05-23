#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "sumatra_pdf_core.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const CGFloat kPageMargin = 44.0;
static const CGFloat kPageGap = 26.0;
static const CGFloat kMinZoom = 0.10;
static const CGFloat kMaxZoom = 8.00;
static const CGFloat kSelectionOverlayAlpha = 0.20;
static const CGFloat kTabStripHeight = 42.0;
static const CGFloat kTabGap = 6.0;
static const CGFloat kTabMinVisibleWidth = 112.0;
static const CGFloat kTabMaxWidth = 320.0;
static const CGFloat kTabControlWidth = 32.0;
static const CGFloat kMinWindowWidth = 560.0;
static const CGFloat kMinWindowHeight = 380.0;
static const CGFloat kDefaultMinimapWidth = 110.0;
static const CGFloat kDefaultSidebarWidth = 240.0;
static const CGFloat kMinSidebarWidth = 176.0;
static const CGFloat kMaxSidebarWidth = 320.0;
static const CGFloat kSidebarMaxWidthFraction = 0.34;
static const CGFloat kMinimapDividerWidth = 5.0;
static const NSInteger kBackgroundRenderBatchSize = 8;
static const NSTimeInterval kAfterFirstPaintDelay = 0.05;

typedef struct SPDFPageAnchor {
    NSInteger pageIndex;
    NSPoint pagePoint;
    NSPoint offsetInViewport;
    BOOL valid;
} SPDFPageAnchor;

static CGFloat spdf_clamp_cg(CGFloat value, CGFloat minValue, CGFloat maxValue) {
    return MAX(minValue, MIN(maxValue, value));
}

static CGFloat spdf_max_sidebar_width_for_container(CGFloat containerWidth) {
    if (containerWidth <= 0) return kMaxSidebarWidth;
    return MAX(kMinSidebarWidth, MIN(kMaxSidebarWidth, floor(containerWidth * kSidebarMaxWidthFraction)));
}

static CGFloat spdf_sane_sidebar_width(CGFloat width, CGFloat containerWidth) {
    if (!isfinite(width) || width < kMinSidebarWidth || width > kMaxSidebarWidth) return kDefaultSidebarWidth;
    return spdf_clamp_cg(width, kMinSidebarWidth, spdf_max_sidebar_width_for_container(containerWidth));
}

static NSSize spdf_sane_window_content_size(NSSize size, NSScreen* screen) {
    if (!isfinite(size.width) || !isfinite(size.height) || size.width <= 0 || size.height <= 0) return NSZeroSize;
    NSRect visibleFrame = screen ? screen.visibleFrame : NSScreen.mainScreen.visibleFrame;
    CGFloat maxWidth = MAX(kMinWindowWidth, MIN(2200.0, NSWidth(visibleFrame) - 40.0));
    CGFloat maxHeight = MAX(kMinWindowHeight, MIN(1600.0, NSHeight(visibleFrame) - 40.0));
    return NSMakeSize(spdf_clamp_cg(size.width, kMinWindowWidth, maxWidth),
                      spdf_clamp_cg(size.height, kMinWindowHeight, maxHeight));
}

static NSArray<UTType*>* spdf_document_content_types() {
    NSMutableArray<UTType*>* types = [NSMutableArray arrayWithObject:UTTypePDF];
    for (NSString* extension in @[ @"xps", @"cbz", @"epub" ]) {
        UTType* type = [UTType typeWithFilenameExtension:extension];
        if (type) [types addObject:type];
    }
    return types;
}

static NSString* spdf_display_label_without_extension(NSString* label) {
    if (!label.length) return @"";
    NSArray<NSString*>* extensions = @[ @".pdf", @".xps", @".cbz", @".epub" ];
    for (NSString* ext in extensions) {
        NSRange range = [label rangeOfString:ext options:NSCaseInsensitiveSearch | NSBackwardsSearch];
        if (range.location == NSNotFound) continue;
        NSUInteger end = range.location + range.length;
        BOOL atEnd = end == label.length;
        BOOL beforeSuffix = !atEnd && ([[NSCharacterSet whitespaceAndNewlineCharacterSet]
                                           characterIsMember:[label characterAtIndex:end]] ||
                                       [label characterAtIndex:end] == '-');
        if (atEnd || beforeSuffix) return [label stringByReplacingCharactersInRange:range withString:@""];
    }
    return label;
}

static NSString* spdf_display_name_for_path(NSString* path) {
    NSString* name = path.lastPathComponent;
    return spdf_display_label_without_extension(name);
}

static NSString* spdf_display_path_without_extension(NSString* path) {
    if (!path.length) return @"";
    NSString* stem = path.stringByDeletingPathExtension;
    return stem.length && ![stem isEqualToString:path] ? stem : path;
}

static BOOL spdf_is_allowed_external_url(NSURL* url) {
    NSString* scheme = url.scheme.lowercaseString;
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] ||
           [scheme isEqualToString:@"mailto"] || [scheme isEqualToString:@"file"];
}

typedef NS_ENUM(NSInteger, SPDFFitMode) {
    SPDFFitModeCustom = 0,
    SPDFFitModeActual,
    SPDFFitModeWidth,
    SPDFFitModeHeight,
    SPDFFitModePage
};

typedef NS_ENUM(NSInteger, SPDFViewMode) {
    SPDFViewModeSingle = 0,
    SPDFViewModeContinuous
};

typedef NS_ENUM(NSInteger, SPDFSidebarMode) {
    SPDFSidebarModeChapters = 0,
    SPDFSidebarModeComments = 1
};

@class SumatraMacDelegate;

@interface SPDFRenderedPage : NSObject
@property(nonatomic) NSInteger pageIndex;
@property(nonatomic) CGFloat pageWidth;
@property(nonatomic) CGFloat pageHeight;
@property(nonatomic) CGFloat imagePointWidth;
@property(nonatomic) CGFloat imagePointHeight;
@property(nonatomic) CGFloat imageZoom;
@property(nonatomic) CGFloat imageScale;
@property(nonatomic, strong) NSImage* image;
@property(nonatomic, copy) NSArray<NSValue*>* highlights;
@property(nonatomic, copy) NSArray<NSValue*>* selectionRects;
@end

@implementation SPDFRenderedPage
@end

@interface SPDFDocumentTab : NSObject
@property(nonatomic, copy) NSString* path;
@property(nonatomic, copy) NSString* title;
@property(nonatomic) NSInteger pageIndex;
@property(nonatomic) CGFloat zoom;
@property(nonatomic) CGFloat customZoom;
@property(nonatomic) SPDFFitMode fitMode;
@property(nonatomic) SPDFViewMode viewMode;
@property(nonatomic) NSPoint scrollOrigin;
@property(nonatomic) BOOL hasScrollOrigin;
@property(nonatomic, copy) NSString* searchText;
@property(nonatomic) BOOL searchRegex;
@property(nonatomic) BOOL searchRegexMultiline;
@property(nonatomic) NSInteger findMatchIndex;
@property(nonatomic) BOOL missingFile;
@property(nonatomic, copy) NSString* missingMessage;
@end

@implementation SPDFDocumentTab

- (instancetype)init {
    self = [super init];
    if (self) {
        _pageIndex = 0;
        _zoom = 1.0;
        _customZoom = 1.0;
        _fitMode = SPDFFitModeWidth;
        _viewMode = SPDFViewModeContinuous;
        _searchText = @"";
        _searchRegexMultiline = YES;
        _findMatchIndex = -1;
        _missingMessage = @"";
    }
    return self;
}

@end

@interface SPDFWorkerDocument : NSObject
@property(nonatomic) spdf_document* document;
@property(nonatomic, copy) NSString* path;
@end

@implementation SPDFWorkerDocument

- (void)dealloc {
    spdf_close(_document);
}

@end

@interface SPDFTabStripView : NSView
@property(nonatomic, weak) SumatraMacDelegate* reader;
@property(nonatomic, copy) NSArray<SPDFDocumentTab*>* tabs;
@property(nonatomic) NSInteger selectedIndex;
@property(nonatomic) CGFloat reservedLeadingInset;
@end

@interface SPDFPaletteSearchField : NSSearchField
@property(nonatomic, weak) SumatraMacDelegate* reader;
@end

@interface SPDFToolbarStackView : NSStackView
@end

@interface SPDFToolbarToggleButton : NSButton
@property(nonatomic) BOOL active;
@end

@interface SPDFToolbarMenuButton : NSButton
@end

@interface SPDFDropView : NSView <NSDraggingDestination>
@property(nonatomic, weak) SumatraMacDelegate* reader;
@end

@interface SPDFMinimapDividerView : NSView
@property(nonatomic, weak) SumatraMacDelegate* reader;
@end

@interface SPDFScrollView : NSScrollView
@property(nonatomic, weak) SumatraMacDelegate* reader;
@end

@interface SPDFSidebarTableView : NSTableView
@property(nonatomic, weak) SumatraMacDelegate* reader;
@end

@interface SPDFFindMarkerScroller : NSScroller
@property(nonatomic, weak) SumatraMacDelegate* reader;
@end

@interface SPDFDocumentView : NSView <NSDraggingDestination>
@property(nonatomic, copy) NSArray<SPDFRenderedPage*>* pages;
@property(nonatomic) NSInteger currentPageIndex;
@property(nonatomic) CGFloat zoom;
@property(nonatomic) SPDFViewMode viewMode;
@property(nonatomic) CGFloat viewportWidthHint;
@property(nonatomic) CGFloat backingScale;
@property(nonatomic) NSInteger activeFindPageIndex;
@property(nonatomic) NSRect activeFindRect;
@property(nonatomic) CGFloat activeFindAlpha;
@property(nonatomic) BOOL presentationMode;
@property(nonatomic, copy) NSString* emptyMessage;
@property(nonatomic, weak) SumatraMacDelegate* reader;
- (NSSize)documentSizeForClipSize:(NSSize)clipSize;
- (NSRect)rectForPageAtIndex:(NSInteger)pageIndex;
- (NSInteger)pageIndexForVisibleRect:(NSRect)visibleRect;
- (BOOL)point:(NSPoint)point fallsInPage:(NSInteger*)pageIndex pagePoint:(NSPoint*)pagePoint;
- (void)cancelTransientInteraction;
@end

@interface SPDFMinimapView : NSView
@property(nonatomic, copy) NSArray<SPDFRenderedPage*>* pages;
@property(nonatomic, copy) NSArray<NSValue*>* documentPageRects;
@property(nonatomic) NSRect documentVisibleRect;
@property(nonatomic) CGFloat documentWidth;
@property(nonatomic) CGFloat documentHeight;
@property(nonatomic) CGFloat documentScale;
@property(nonatomic) SPDFViewMode viewMode;
@property(nonatomic) NSInteger currentPageIndex;
@property(nonatomic, weak) SumatraMacDelegate* reader;
@end

@interface SumatraMacDelegate : NSObject <NSApplicationDelegate,
                                          NSWindowDelegate,
                                          NSSplitViewDelegate,
                                          NSTableViewDataSource,
                                          NSTableViewDelegate,
                                          NSSearchFieldDelegate,
                                          NSTextFieldDelegate,
                                          NSMenuItemValidation>
@property(nonatomic, copy) NSString* initialPath;
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
- (BOOL)documentViewInPresentationMode;
- (void)copySelection:(id)sender;
- (void)selectTabAtIndex:(NSInteger)index;
- (void)closeTabAtIndex:(NSInteger)index;
- (void)newTabRequested:(id)sender;
- (void)focusFind:(id)sender;
- (void)showFindPalette:(id)sender;
- (void)toggleFindRegex:(id)sender;
- (void)toggleFindRegexMultiline:(id)sender;
- (void)paletteMoveSelection:(NSInteger)delta;
- (void)closePalette:(id)sender;
- (void)activatePaletteSelection:(id)sender;
- (void)paletteFavoriteDeleteClicked:(id)sender;
- (SPDFDocumentView*)newDocumentView;
- (void)replaceDocumentViewForTabSwitch;
- (void)updateFindControls;
- (void)updateMinimap;
- (void)showEmptyDocumentViewWithMessage:(NSString*)message;
- (void)renderDocumentAndScrollToPage:(NSInteger)pageIndex alignTop:(BOOL)alignTop;
- (void)renderDocumentAndScrollToPage:(NSInteger)pageIndex
                             alignTop:(BOOL)alignTop
                        restoreOrigin:(NSValue*)restoreOrigin;
- (void)scrollDocumentClipViewToOrigin:(NSPoint)origin notify:(BOOL)notify;
- (NSPoint)normalizedDocumentScrollOrigin:(NSPoint)origin forPageIndex:(NSInteger)pageIndex;
- (void)stabilizeDocumentLayoutWithRestoreOrigin:(NSValue*)restoreOrigin
                                        alignTop:(BOOL)alignTop
                                      generation:(NSUInteger)generation
                                            path:(NSString*)path;
- (void)minimapViewDidRequestScrollToFraction:(CGFloat)yFraction;
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
- (NSString*)currentCommentAuthor;
- (void)normalizeSidebarModeControlWidths;
- (void)enqueueNearbyPageRendersForGeneration:(NSUInteger)generation preferredPage:(NSInteger)preferredPage;
- (void)scheduleNearbyPageRendersAfterFirstPaintForGeneration:(NSUInteger)generation
                                                preferredPage:(NSInteger)preferredPage;
- (void)schedulePostFirstPaintWorkForGeneration:(NSUInteger)generation
                                           path:(NSString*)path
                            savedFindMatchIndex:(NSInteger)savedFindMatchIndex
                                  restoreSearch:(BOOL)restoreSearch
                            preferredRenderPage:(NSInteger)preferredRenderPage;
@end

@implementation SPDFTabStripView {
    NSTrackingArea* _trackingArea;
    NSPanel* _hoverPanel;
    NSTextField* _hoverLabel;
    NSInteger _hoverTabIndex;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _hoverTabIndex = -1;
    }
    return self;
}

- (void)dealloc {
    [_hoverPanel orderOut:nil];
}

- (BOOL)isFlipped {
    return NO;
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event {
    (void)event;
    return YES;
}

- (CGFloat)tabWidth {
    NSInteger count = MAX(1, (NSInteger)[self visibleTabIndexes].count);
    CGFloat available = [self tabAreaWidthWithOverflow:[self hasOverflowTabs]] - (count - 1) * kTabGap;
    if (available <= 0) return kTabMinVisibleWidth;
    return MAX(1.0, MIN(kTabMaxWidth, floor(available / count)));
}

- (CGFloat)leftInset {
    return MAX(16.0, self.reservedLeadingInset > 0 ? self.reservedLeadingInset : 138.0);
}

- (NSRect)plusRect {
    CGFloat x = MAX([self leftInset] + kTabControlWidth + 16.0, NSWidth(self.bounds) - 42);
    x = MIN(x, MAX([self leftInset] + kTabControlWidth + 16.0, NSWidth(self.bounds) - 40));
    return NSMakeRect(x, 7, kTabControlWidth, 28);
}

- (NSRect)overflowRectAssumingVisible {
    CGFloat x = NSMinX([self plusRect]) - kTabControlWidth - kTabGap;
    x = MAX([self leftInset], x);
    return NSMakeRect(x, 7, kTabControlWidth, 28);
}

- (CGFloat)tabAreaRightWithOverflow:(BOOL)overflow {
    return overflow ? NSMinX([self overflowRectAssumingVisible]) - 8.0 : NSMinX([self plusRect]) - 10.0;
}

- (CGFloat)tabAreaWidthWithOverflow:(BOOL)overflow {
    return MAX(0.0, [self tabAreaRightWithOverflow:overflow] - [self leftInset]);
}

- (NSInteger)selectedIndexForLayout {
    NSInteger count = (NSInteger)self.tabs.count;
    if (count <= 0) return -1;
    if (self.selectedIndex < 0) return 0;
    return MIN(self.selectedIndex, count - 1);
}

- (NSInteger)visibleTabCapacityWithOverflow:(BOOL)overflow {
    NSInteger count = (NSInteger)self.tabs.count;
    if (count <= 0) return 0;

    CGFloat areaWidth = [self tabAreaWidthWithOverflow:overflow];
    if (areaWidth <= 0) return 1;

    NSInteger capacity = (NSInteger)floor((areaWidth + kTabGap) / (kTabMinVisibleWidth + kTabGap));
    return MAX(1, MIN(count, capacity));
}

- (BOOL)hasOverflowTabs {
    NSInteger count = (NSInteger)self.tabs.count;
    if (count <= 1) return NO;
    return [self visibleTabCapacityWithOverflow:NO] < count;
}

- (NSArray<NSNumber*>*)visibleTabIndexes {
    NSInteger count = (NSInteger)self.tabs.count;
    if (count <= 0) return @[];

    BOOL overflow = [self hasOverflowTabs];
    NSInteger visibleCount = overflow ? [self visibleTabCapacityWithOverflow:YES] : count;
    visibleCount = MAX(1, MIN(count, visibleCount));

    NSInteger selected = [self selectedIndexForLayout];
    NSInteger start = overflow ? selected - (visibleCount - 1) / 2 : 0;
    start = MAX(0, MIN(start, count - visibleCount));

    NSMutableArray<NSNumber*>* indexes = [NSMutableArray arrayWithCapacity:(NSUInteger)visibleCount];
    for (NSInteger i = 0; i < visibleCount; ++i) {
        [indexes addObject:@(start + i)];
    }
    return indexes;
}

- (NSArray<NSNumber*>*)hiddenTabIndexes {
    if (![self hasOverflowTabs]) return @[];

    NSMutableIndexSet* visibleIndexes = [NSMutableIndexSet indexSet];
    for (NSNumber* index in [self visibleTabIndexes]) {
        [visibleIndexes addIndex:(NSUInteger)index.integerValue];
    }

    NSMutableArray<NSNumber*>* hiddenIndexes = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; ++i) {
        if (![visibleIndexes containsIndex:(NSUInteger)i]) [hiddenIndexes addObject:@(i)];
    }
    return hiddenIndexes;
}

- (NSRect)overflowRect {
    return [self hasOverflowTabs] ? [self overflowRectAssumingVisible] : NSZeroRect;
}

- (NSRect)rectForTabAtIndex:(NSInteger)index {
    NSArray<NSNumber*>* visibleIndexes = [self visibleTabIndexes];
    NSUInteger visiblePosition = [visibleIndexes indexOfObject:@(index)];
    if (visiblePosition == NSNotFound) return NSZeroRect;

    CGFloat x = [self leftInset] + (CGFloat)visiblePosition * ([self tabWidth] + kTabGap);
    CGFloat maxRight = [self tabAreaRightWithOverflow:[self hasOverflowTabs]];
    CGFloat width = MIN([self tabWidth], maxRight - x);
    return NSMakeRect(x, 7, width, 28);
}

- (NSString*)titleForTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.tabs.count) return @"";
    SPDFDocumentTab* tab = self.tabs[(NSUInteger)index];
    return tab.path.length ? spdf_display_name_for_path(tab.path) : spdf_display_label_without_extension(tab.title);
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow
               owner:self
            userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)hideHoverPanel {
    _hoverTabIndex = -1;
    [_hoverPanel orderOut:nil];
}

- (void)showHoverPanelForTabAtIndex:(NSInteger)index {
    NSString* title = [self titleForTabAtIndex:index];
    if (!title.length || !self.window) {
        [self hideHoverPanel];
        return;
    }

    NSRect tabRect = [self rectForTabAtIndex:index];
    if (NSWidth(tabRect) <= 0) {
        [self hideHoverPanel];
        return;
    }

    if (!_hoverPanel) {
        _hoverPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 240, 26)
                                                 styleMask:NSWindowStyleMaskBorderless
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
        _hoverPanel.releasedWhenClosed = NO;
        _hoverPanel.hidesOnDeactivate = YES;
        _hoverPanel.hasShadow = YES;
        _hoverPanel.opaque = NO;
        _hoverPanel.backgroundColor = NSColor.clearColor;

        NSVisualEffectView* bubble = [[NSVisualEffectView alloc] initWithFrame:_hoverPanel.contentView.bounds];
        bubble.translatesAutoresizingMaskIntoConstraints = NO;
        bubble.material = NSVisualEffectMaterialPopover;
        bubble.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        bubble.state = NSVisualEffectStateActive;
        bubble.wantsLayer = YES;
        bubble.layer.cornerRadius = 8.0;
        bubble.layer.masksToBounds = YES;
        _hoverPanel.contentView = bubble;

        _hoverLabel = [NSTextField labelWithString:@""];
        _hoverLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _hoverLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _hoverLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
        [bubble addSubview:_hoverLabel];
        [NSLayoutConstraint activateConstraints:@[
            [_hoverLabel.leadingAnchor constraintEqualToAnchor:bubble.leadingAnchor constant:10],
            [_hoverLabel.trailingAnchor constraintEqualToAnchor:bubble.trailingAnchor constant:-10],
            [_hoverLabel.centerYAnchor constraintEqualToAnchor:bubble.centerYAnchor]
        ]];
    }

    _hoverLabel.stringValue = title;
    CGFloat width =
        MIN(420.0, MAX(96.0, [title sizeWithAttributes:@{NSFontAttributeName : _hoverLabel.font}].width + 24));
    NSRect tabScreenRect = [self.window convertRectToScreen:[self convertRect:tabRect toView:nil]];
    NSRect frame =
        NSMakeRect(floor(NSMidX(tabScreenRect) - width / 2.0), floor(NSMinY(tabScreenRect) - 31.0), width, 26.0);
    [_hoverPanel setFrame:frame display:NO];
    if (_hoverPanel.parentWindow != self.window) [self.window addChildWindow:_hoverPanel ordered:NSWindowAbove];
    [_hoverPanel orderFront:nil];
    _hoverTabIndex = index;
}

- (void)updateHoverForEvent:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger hovered = -1;
    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; ++i) {
        NSRect tabRect = [self rectForTabAtIndex:i];
        if (NSWidth(tabRect) < 40.0) continue;
        if (NSPointInRect(point, tabRect)) {
            hovered = i;
            break;
        }
    }
    if (hovered == _hoverTabIndex) return;
    if (hovered >= 0)
        [self showHoverPanelForTabAtIndex:hovered];
    else
        [self hideHoverPanel];
}

- (void)setTabs:(NSArray<SPDFDocumentTab*>*)tabs {
    _tabs = [tabs copy];
    [self setNeedsDisplay:YES];
    [self hideHoverPanel];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    _selectedIndex = selectedIndex;
    [self setNeedsDisplay:YES];
}

- (NSRect)closeCircleRectForTabRect:(NSRect)tabRect {
    CGFloat diameter = 16.0;
    return NSMakeRect(floor(NSMaxX(tabRect) - 26.0), floor(NSMidY(tabRect) - diameter / 2.0), diameter, diameter);
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor clearColor] setFill];
    NSRectFill(self.bounds);

    NSMutableParagraphStyle* tabTitleStyle = [[NSMutableParagraphStyle alloc] init];
    tabTitleStyle.alignment = NSTextAlignmentCenter;
    tabTitleStyle.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSDictionary* attrs = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : NSColor.labelColor,
        NSParagraphStyleAttributeName : tabTitleStyle
    };
    NSDictionary* dimAttrs = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12],
        NSForegroundColorAttributeName : NSColor.secondaryLabelColor,
        NSParagraphStyleAttributeName : tabTitleStyle
    };

    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; ++i) {
        NSRect tabRect = [self rectForTabAtIndex:i];
        if (NSWidth(tabRect) < 40.0) continue;
        BOOL selected = i == self.selectedIndex;
        SPDFDocumentTab* tab = self.tabs[(NSUInteger)i];
        BOOL missing = tab.missingFile;
        NSColor* fill;
        NSColor* stroke = nil;
        if (missing) {
            fill = [NSColor.systemRedColor colorWithAlphaComponent:selected ? 0.36 : 0.22];
            stroke = [NSColor.systemRedColor colorWithAlphaComponent:selected ? 0.95 : 0.65];
        } else if (selected) {
            fill = [NSColor.controlAccentColor colorWithAlphaComponent:0.34];
            stroke = [NSColor.controlAccentColor colorWithAlphaComponent:0.95];
        } else {
            fill = NSColor.controlBackgroundColor;
        }
        NSBezierPath* tabPath = [NSBezierPath bezierPathWithRoundedRect:tabRect xRadius:7 yRadius:7];
        [fill setFill];
        [tabPath fill];
        if (stroke) {
            [stroke setStroke];
            tabPath.lineWidth = selected ? 1.4 : 1.0;
            [tabPath stroke];
        }

        NSString* title = [self titleForTabAtIndex:i];
        NSDictionary* titleAttrs = selected || missing ? attrs : dimAttrs;
        CGFloat titleHeight = [title sizeWithAttributes:titleAttrs].height;
        CGFloat titleInset = 32.0;
        NSRect titleRect = NSMakeRect(NSMinX(tabRect) + titleInset, floor(NSMidY(tabRect) - titleHeight / 2.0),
                                      MAX(1.0, NSWidth(tabRect) - titleInset * 2.0), titleHeight + 2);
        [title drawWithRect:titleRect
                    options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine
                 attributes:titleAttrs];

        NSRect closeRect = [self closeCircleRectForTabRect:tabRect];
        NSBezierPath* closeCircle = [NSBezierPath bezierPathWithOvalInRect:closeRect];
        NSColor* closeFill = selected ? [NSColor.labelColor colorWithAlphaComponent:0.16]
                                      : [NSColor.secondaryLabelColor colorWithAlphaComponent:0.13];
        [closeFill setFill];
        [closeCircle fill];

        NSColor* closeStroke = selected ? [NSColor.labelColor colorWithAlphaComponent:0.76]
                                        : [NSColor.secondaryLabelColor colorWithAlphaComponent:0.82];
        [closeStroke setStroke];
        NSBezierPath* closeX = [NSBezierPath bezierPath];
        closeX.lineWidth = 1.35;
        [closeX moveToPoint:NSMakePoint(NSMidX(closeRect) - 3.2, NSMidY(closeRect) - 3.2)];
        [closeX lineToPoint:NSMakePoint(NSMidX(closeRect) + 3.2, NSMidY(closeRect) + 3.2)];
        [closeX moveToPoint:NSMakePoint(NSMidX(closeRect) + 3.2, NSMidY(closeRect) - 3.2)];
        [closeX lineToPoint:NSMakePoint(NSMidX(closeRect) - 3.2, NSMidY(closeRect) + 3.2)];
        [closeX stroke];
    }

    NSRect overflowRect = [self overflowRect];
    if (!NSIsEmptyRect(overflowRect)) {
        [NSColor.controlBackgroundColor setFill];
        NSBezierPath* overflowPath = [NSBezierPath bezierPathWithRoundedRect:overflowRect xRadius:9 yRadius:9];
        [overflowPath fill];
        [[NSColor.separatorColor colorWithAlphaComponent:0.45] setStroke];
        overflowPath.lineWidth = 1.0;
        [overflowPath stroke];

        [[NSColor.labelColor colorWithAlphaComponent:0.78] setFill];
        CGFloat dotDiameter = 3.0;
        CGFloat dotGap = 3.0;
        CGFloat x = floor(NSMidX(overflowRect) - dotDiameter / 2.0);
        CGFloat startY = floor(NSMidY(overflowRect) - dotDiameter * 1.5 - dotGap);
        for (NSInteger i = 0; i < 3; ++i) {
            NSRect dot = NSMakeRect(x, startY + (dotDiameter + dotGap) * i, dotDiameter, dotDiameter);
            [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
        }
    }

    NSRect plusRect = [self plusRect];
    [NSColor.controlBackgroundColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:plusRect xRadius:9 yRadius:9] fill];
    NSDictionary* plusAttrs = @{
        NSFontAttributeName : [NSFont systemFontOfSize:16 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : NSColor.labelColor
    };
    NSSize plusSize = [@"+" sizeWithAttributes:plusAttrs];
    [@"+" drawAtPoint:NSMakePoint(floor(NSMidX(plusRect) - plusSize.width / 2.0),
                                  floor(NSMidY(plusRect) - plusSize.height / 2.0))
        withAttributes:plusAttrs];
}

- (void)showOverflowMenuWithEvent:(NSEvent*)event {
    NSArray<NSNumber*>* hiddenIndexes = [self hiddenTabIndexes];
    if (!hiddenIndexes.count) return;

    [self hideHoverPanel];

    NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Hidden Tabs"];
    for (NSNumber* indexNumber in hiddenIndexes) {
        NSInteger index = indexNumber.integerValue;
        NSString* title = [self titleForTabAtIndex:index];
        if (!title.length) title = @"Untitled";

        NSMenuItem* item =
            [[NSMenuItem alloc] initWithTitle:title action:@selector(overflowTabMenuItemSelected:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = indexNumber;
        item.state = index == self.selectedIndex ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:item];
    }

    NSRect overflowRect = [self overflowRect];
    NSEvent* menuEvent = event;
    if (!menuEvent) {
        NSPoint windowPoint = [self convertPoint:NSMakePoint(NSMinX(overflowRect), NSMinY(overflowRect)) toView:nil];
        menuEvent = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                       location:windowPoint
                                  modifierFlags:0
                                      timestamp:NSProcessInfo.processInfo.systemUptime
                                   windowNumber:self.window.windowNumber
                                        context:nil
                                    eventNumber:0
                                     clickCount:1
                                       pressure:1.0];
    }
    [NSMenu popUpContextMenu:menu withEvent:menuEvent forView:self];
}

- (void)overflowTabMenuItemSelected:(NSMenuItem*)sender {
    NSNumber* indexNumber = [sender.representedObject isKindOfClass:NSNumber.class] ? sender.representedObject : nil;
    if (!indexNumber) return;
    [self.reader selectTabAtIndex:indexNumber.integerValue];
}

- (void)mouseDown:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(point, [self plusRect])) {
        [self.reader newTabRequested:self];
        return;
    }

    NSRect overflowRect = [self overflowRect];
    if (!NSIsEmptyRect(overflowRect) && NSPointInRect(point, overflowRect)) {
        [self showOverflowMenuWithEvent:event];
        return;
    }

    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; ++i) {
        NSRect tabRect = [self rectForTabAtIndex:i];
        if (NSIsEmptyRect(tabRect)) continue;
        if (!NSPointInRect(point, tabRect)) continue;
        NSRect closeRect = NSInsetRect([self closeCircleRectForTabRect:tabRect], -5.0, -5.0);
        if (NSPointInRect(point, closeRect))
            [self.reader closeTabAtIndex:i];
        else
            [self.reader selectTabAtIndex:i];
        return;
    }

    [self hideHoverPanel];
    [self.window performWindowDragWithEvent:event];
}

- (void)mouseMoved:(NSEvent*)event {
    [self updateHoverForEvent:event];
}

- (void)mouseExited:(NSEvent*)event {
    (void)event;
    [self hideHoverPanel];
}

@end

@implementation SPDFToolbarStackView

- (BOOL)acceptsFirstMouse:(NSEvent*)event {
    (void)event;
    return YES;
}

- (BOOL)mouseDownCanMoveWindow {
    return YES;
}

- (void)mouseDown:(NSEvent*)event {
    [self.window performWindowDragWithEvent:event];
}

@end

@implementation SPDFToolbarToggleButton

- (instancetype)initWithTitle:(NSString*)title target:(id)target action:(SEL)action {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.title = title;
        self.target = target;
        self.action = action;
        self.bordered = NO;
        self.bezelStyle = NSBezelStyleRegularSquare;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.focusRingType = NSFocusRingTypeNone;
        [self setButtonType:NSButtonTypeMomentaryChange];
        [self setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    return self;
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event {
    (void)event;
    return YES;
}

- (NSSize)intrinsicContentSize {
    NSDictionary* attrs = @{NSFontAttributeName : [NSFont systemFontOfSize:12.0 weight:NSFontWeightLight]};
    CGFloat titleWidth = ceil([self.title sizeWithAttributes:attrs].width);
    return NSMakeSize(titleWidth + 50.0, 28.0);
}

- (void)setActive:(BOOL)active {
    if (_active == active) return;
    _active = active;
    self.accessibilityValue = active ? @"On" : @"Off";
    [self setNeedsDisplay:YES];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    [self setNeedsDisplay:YES];
}

- (void)setTitle:(NSString*)title {
    [super setTitle:title];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect bounds = NSInsetRect(self.bounds, 1.0, 2.0);
    BOOL enabled = self.enabled;
    BOOL pressed = self.highlighted;
    CGFloat alpha = enabled ? 1.0 : 0.44;

    if (pressed) {
        NSColor* pressFill = [NSColor.labelColor colorWithAlphaComponent:0.08 * alpha];
        [pressFill setFill];
        [[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:7.0 yRadius:7.0] fill];
    }

    NSFont* font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightLight];
    NSMutableParagraphStyle* paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    paragraph.alignment = NSTextAlignmentLeft;
    NSDictionary* attrs = @{
        NSFontAttributeName : font,
        NSForegroundColorAttributeName : [NSColor.labelColor colorWithAlphaComponent:alpha],
        NSParagraphStyleAttributeName : paragraph
    };

    CGFloat switchWidth = 32.0;
    CGFloat switchHeight = 18.0;
    NSRect switchRect = NSMakeRect(floor(NSMaxX(bounds) - switchWidth - 5.0),
                                   floor(NSMidY(bounds) - switchHeight / 2.0), switchWidth, switchHeight);
    NSRect titleRect = NSMakeRect(NSMinX(bounds) + 5.0, floor(NSMidY(bounds) - 8.0),
                                  MAX(1.0, NSMinX(switchRect) - NSMinX(bounds) - 10.0), 17.0);
    [self.title drawWithRect:titleRect
                     options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine
                  attributes:attrs];

    NSColor* trackFill = self.active ? [NSColor.whiteColor colorWithAlphaComponent:(enabled ? 0.94 : 0.38)]
                                     : [NSColor.secondaryLabelColor colorWithAlphaComponent:(enabled ? 0.22 : 0.12)];
    NSBezierPath* track =
        [NSBezierPath bezierPathWithRoundedRect:switchRect xRadius:switchHeight / 2.0 yRadius:switchHeight / 2.0];
    [trackFill setFill];
    [track fill];
    [[NSColor.separatorColor colorWithAlphaComponent:enabled ? 0.55 : 0.24] setStroke];
    track.lineWidth = 1.0;
    [track stroke];

    CGFloat knobSize = 14.0;
    CGFloat knobX = self.active ? NSMaxX(switchRect) - knobSize - 2.0 : NSMinX(switchRect) + 2.0;
    NSRect knobRect = NSMakeRect(floor(knobX), floor(NSMidY(switchRect) - knobSize / 2.0), knobSize, knobSize);
    NSColor* knobFill = self.active ? [NSColor colorWithCalibratedWhite:0.14 alpha:1.0]
                                    : [NSColor.whiteColor colorWithAlphaComponent:0.96];
    if (!enabled) knobFill = [knobFill colorWithAlphaComponent:0.72];
    [knobFill setFill];
    [[NSBezierPath bezierPathWithOvalInRect:knobRect] fill];
    [[NSColor.shadowColor colorWithAlphaComponent:enabled ? 0.18 : 0.08] setStroke];
    [[NSBezierPath bezierPathWithOvalInRect:knobRect] stroke];
}

@end

@implementation SPDFToolbarMenuButton

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.bordered = NO;
        self.bezelStyle = NSBezelStyleRegularSquare;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.focusRingType = NSFocusRingTypeNone;
        [self setButtonType:NSButtonTypeMomentaryChange];
        [self setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    return self;
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event {
    (void)event;
    return YES;
}

- (NSSize)intrinsicContentSize {
    return NSMakeSize(30.0, 28.0);
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect bounds = NSInsetRect(self.bounds, 1.0, 2.0);
    CGFloat alpha = self.enabled ? 1.0 : 0.42;
    NSColor* fill = self.highlighted ? [NSColor.labelColor colorWithAlphaComponent:0.13 * alpha]
                                     : [NSColor.labelColor colorWithAlphaComponent:0.06 * alpha];
    [fill setFill];
    [[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:8.0 yRadius:8.0] fill];

    [[NSColor.separatorColor colorWithAlphaComponent:0.30 * alpha] setStroke];
    NSBezierPath* outline = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:8.0 yRadius:8.0];
    outline.lineWidth = 1.0;
    [outline stroke];

    [[NSColor.labelColor colorWithAlphaComponent:0.78 * alpha] setFill];
    CGFloat dotSize = 3.0;
    CGFloat gap = 3.0;
    CGFloat x = floor(NSMidX(bounds) - dotSize / 2.0);
    CGFloat startY = floor(NSMidY(bounds) - dotSize * 1.5 - gap);
    for (NSInteger i = 0; i < 3; ++i) {
        NSRect dot = NSMakeRect(x, startY + (dotSize + gap) * i, dotSize, dotSize);
        [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
    }
}

@end

@implementation SPDFPaletteSearchField

- (void)keyDown:(NSEvent*)event {
    if (event.keyCode == 53) {
        [self.reader closePalette:self];
        return;
    }
    if (event.keyCode == 125) {
        [self.reader paletteMoveSelection:1];
        return;
    }
    if (event.keyCode == 126) {
        [self.reader paletteMoveSelection:-1];
        return;
    }
    if (event.keyCode == 36 || event.keyCode == 76) {
        [self.reader activatePaletteSelection:self];
        return;
    }
    [super keyDown:event];
}

@end

@implementation SPDFDropView

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    (void)sender;
    return NSDragOperationCopy;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    return [self.reader openFilesFromPasteboard:sender.draggingPasteboard];
}

@end

@implementation SPDFMinimapDividerView {
    CGFloat _lastWindowX;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:NSCursor.resizeLeftRightCursor];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [NSColor.windowBackgroundColor setFill];
    NSRectFill(self.bounds);
    [[NSColor separatorColor] setFill];
    NSRectFill(NSMakeRect(floor(NSWidth(self.bounds) / 2.0), 0.0, 1.0, NSHeight(self.bounds)));
}

- (void)mouseDown:(NSEvent*)event {
    _lastWindowX = event.locationInWindow.x;
    [self.reader clearFindFieldFocus];
}

- (void)mouseDragged:(NSEvent*)event {
    CGFloat x = event.locationInWindow.x;
    [self.reader minimapDividerDraggedByDeltaX:x - _lastWindowX];
    _lastWindowX = x;
}

- (void)mouseUp:(NSEvent*)event {
    (void)event;
    [self.reader minimapDividerDidFinishDragging];
}

@end

@implementation SPDFFindMarkerScroller

- (void)drawKnobSlotInRect:(NSRect)slotRect highlight:(BOOL)flag {
    [super drawKnobSlotInRect:slotRect highlight:flag];
    if (!self.reader || NSHeight(slotRect) <= 2.0) return;

    NSArray<NSDictionary*>* markers = [self.reader findScrollbarMarkers];
    if (markers.count == 0) return;

    CGFloat minY = NSMinY(slotRect) + 2.0;
    CGFloat maxY = NSMaxY(slotRect) - 2.0;
    CGFloat lastY = -1000.0;
    for (NSDictionary* marker in markers) {
        CGFloat fraction = spdf_clamp_cg([marker[@"fraction"] doubleValue], 0.0, 1.0);
        CGFloat y = self.isFlipped ? floor(minY + fraction * MAX(1.0, maxY - minY))
                                   : floor(maxY - fraction * MAX(1.0, maxY - minY));
        if (fabs(y - lastY) < 1.5 && ![marker[@"active"] boolValue]) continue;
        BOOL active = [marker[@"active"] boolValue];
        NSColor* color = active ? [NSColor colorWithCalibratedRed:1.0 green:0.38 blue:0.08 alpha:0.95]
                                : [NSColor colorWithCalibratedRed:1.0 green:0.86 blue:0.12 alpha:0.82];
        [color setFill];
        NSRect line = NSMakeRect(NSMinX(slotRect) + 2.0, y, MAX(2.0, NSWidth(slotRect) - 4.0), active ? 2.0 : 1.0);
        NSRectFillUsingOperation(line, NSCompositingOperationSourceOver);
        lastY = y;
    }
}

@end

@implementation SPDFScrollView {
    CGFloat _wheelAccumulator;
}

- (void)scrollWheel:(NSEvent*)event {
    if (self.reader && [self.reader zoomWithScrollWheelEvent:event centeredAtWindowPoint:event.locationInWindow])
        return;

    if (self.reader && [self.reader scrollViewShouldTurnWheelIntoPageChange:event]) {
        CGFloat delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY;
        _wheelAccumulator += delta;
        CGFloat threshold = event.hasPreciseScrollingDeltas ? 0.75 : 0.50;
        if (fabs(_wheelAccumulator) >= threshold) {
            if (_wheelAccumulator < 0)
                [NSApp sendAction:@selector(nextPage:) to:nil from:self];
            else
                [NSApp sendAction:@selector(previousPage:) to:nil from:self];
            _wheelAccumulator = 0;
        }
        return;
    }

    [super scrollWheel:event];
    if (self.reader) [self.reader documentScrollPositionChanged];
}

- (void)magnifyWithEvent:(NSEvent*)event {
    if (self.reader) [self.reader zoomWithMagnifyEvent:event centeredAtWindowPoint:event.locationInWindow];
}

- (void)keyDown:(NSEvent*)event {
    if (self.reader && [self.reader documentArrowKeyDown:event]) return;
    [super keyDown:event];
}

@end

@implementation SPDFSidebarTableView

- (NSMenu*)menuForEvent:(NSEvent*)event {
    if (!self.reader) return [super menuForEvent:event];

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger row = [self rowAtPoint:point];
    NSNumber* commentIndex = [self.reader commentIndexForSidebarRow:row];
    if (!commentIndex) return nil;

    NSMenu* menu = [super menuForEvent:event];
    for (NSMenuItem* item in menu.itemArray) {
        if (item.action == @selector(editComment:) || item.action == @selector(deleteComment:)) {
            item.target = self.reader;
            item.representedObject = commentIndex;
        }
    }
    return menu;
}

@end

@implementation SPDFDocumentView {
    BOOL _isPanning;
    BOOL _isSelecting;
    BOOL _rightMouseMoved;
    NSPoint _panStartInWindow;
    NSPoint _panStartOrigin;
    NSPoint _lastPanPoint;
    NSTimeInterval _lastPanTime;
    NSPoint _panVelocity;
    NSTimer* _inertiaTimer;
    NSInteger _selectionPageIndex;
    NSPoint _selectionStart;
    NSTrackingArea* _trackingArea;
    NSDictionary* _hoveredComment;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)copy:(id)sender {
    [self.reader copySelection:sender];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow
               owner:self
            userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)setPages:(NSArray<SPDFRenderedPage*>*)pages {
    _pages = [pages copy];
    [self setNeedsDisplay:YES];
}

- (CGFloat)effectiveBackingScale {
    CGFloat scale = self.backingScale;
    if (scale <= 0) scale = self.window.backingScaleFactor;
    if (scale <= 0) scale = NSScreen.mainScreen.backingScaleFactor;
    return scale > 0 ? scale : 1.0;
}

- (CGFloat)pixelSnappedLength:(CGFloat)length {
    CGFloat scale = [self effectiveBackingScale];
    return ceil(length * scale - 0.001) / scale;
}

- (CGFloat)pixelSnappedOrigin:(CGFloat)origin {
    CGFloat scale = [self effectiveBackingScale];
    return floor(origin * scale + 0.001) / scale;
}

- (NSSize)viewSizeForPage:(SPDFRenderedPage*)page {
    if (page.image && page.imagePointWidth > 0 && page.imagePointHeight > 0 &&
        fabs(page.imageZoom - self.zoom) < 0.0001)
        return NSMakeSize(page.imagePointWidth, page.imagePointHeight);
    return NSMakeSize([self pixelSnappedLength:page.pageWidth * self.zoom],
                      [self pixelSnappedLength:page.pageHeight * self.zoom]);
}

- (NSRect)convertPageRect:(NSRect)rect toViewRectInPageRect:(NSRect)pageRect page:(SPDFRenderedPage*)page {
    CGFloat scaleX = NSWidth(pageRect) / MAX(1.0, page.pageWidth);
    CGFloat scaleY = NSHeight(pageRect) / MAX(1.0, page.pageHeight);
    rect.origin.x = pageRect.origin.x + rect.origin.x * scaleX;
    rect.origin.y = pageRect.origin.y + rect.origin.y * scaleY;
    rect.size.width *= scaleX;
    rect.size.height *= scaleY;
    return rect;
}

- (NSPoint)convertViewPoint:(NSPoint)point toPagePointInPageRect:(NSRect)pageRect page:(SPDFRenderedPage*)page {
    CGFloat scaleX = NSWidth(pageRect) / MAX(1.0, page.pageWidth);
    CGFloat scaleY = NSHeight(pageRect) / MAX(1.0, page.pageHeight);
    return NSMakePoint((point.x - pageRect.origin.x) / MAX(0.001, scaleX),
                       (point.y - pageRect.origin.y) / MAX(0.001, scaleY));
}

- (CGFloat)widestPage {
    CGFloat widest = 0;
    for (SPDFRenderedPage* page in self.pages) widest = MAX(widest, [self viewSizeForPage:page].width);
    return widest;
}

- (CGFloat)viewportWidth {
    CGFloat width = self.viewportWidthHint > 1.0 ? self.viewportWidthHint : NSWidth(self.bounds);
    NSScrollView* scrollView = self.enclosingScrollView;
    if (scrollView) width = MAX(width, scrollView.contentSize.width);
    return width;
}

- (CGFloat)continuousDocumentHeight {
    if (self.pages.count == 0) return 0.0;

    CGFloat pageMargin = self.presentationMode ? 0.0 : kPageMargin;
    CGFloat pageGap = self.presentationMode ? 0.0 : kPageGap;
    CGFloat height = pageMargin / 2.0;
    for (SPDFRenderedPage* page in self.pages) height += [self viewSizeForPage:page].height + pageGap;
    height += pageMargin / 2.0;
    return height;
}

- (NSSize)documentSizeForClipSize:(NSSize)clipSize {
    CGFloat pageMargin = self.presentationMode ? 0.0 : kPageMargin;
    CGFloat pageGap = self.presentationMode ? 0.0 : kPageGap;
    CGFloat width = MAX(clipSize.width, [self widestPage] + pageMargin);
    CGFloat height = pageMargin;

    if (self.pages.count == 0) return NSMakeSize(MAX(clipSize.width, 600), MAX(clipSize.height, 500));

    if (self.presentationMode && self.viewMode == SPDFViewModeSingle)
        return NSMakeSize(clipSize.width, clipSize.height);

    if (self.viewMode == SPDFViewModeSingle) {
        height = [self continuousDocumentHeight];
    } else {
        height = pageMargin / 2.0;
        for (SPDFRenderedPage* page in self.pages) {
            CGFloat pageHeight = [self viewSizeForPage:page].height;
            height += pageHeight + pageGap;
        }
        height += pageMargin / 2.0;
    }

    return NSMakeSize(width, MAX(height, clipSize.height));
}

- (NSRect)rectForPageAtIndex:(NSInteger)pageIndex {
    if (pageIndex < 0 || pageIndex >= (NSInteger)self.pages.count) return NSZeroRect;

    CGFloat pageMargin = self.presentationMode ? 0.0 : kPageMargin;
    CGFloat pageGap = self.presentationMode ? 0.0 : kPageGap;
    CGFloat y = pageMargin / 2.0;
    for (NSInteger i = 0; i < pageIndex; ++i) {
        SPDFRenderedPage* prev = self.pages[(NSUInteger)i];
        y += [self viewSizeForPage:prev].height + pageGap;
    }

    SPDFRenderedPage* page = self.pages[(NSUInteger)pageIndex];
    NSSize pageSize = [self viewSizeForPage:page];
    CGFloat width = pageSize.width;
    CGFloat height = pageSize.height;
    CGFloat x = floor(([self viewportWidth] - width) / 2.0);
    if (self.presentationMode && self.viewMode == SPDFViewModeSingle) {
        CGFloat centeredY = floor((NSHeight(self.bounds) - height) / 2.0);
        return NSMakeRect(MAX(0.0, [self pixelSnappedOrigin:x]), MAX(0.0, [self pixelSnappedOrigin:centeredY]), width,
                          height);
    }
    return NSMakeRect(MAX(pageMargin / 2.0, [self pixelSnappedOrigin:x]), [self pixelSnappedOrigin:y], width, height);
}

- (NSInteger)pageIndexForVisibleRect:(NSRect)visibleRect {
    if (self.pages.count == 0) return 0;

    NSInteger bestPage = self.currentPageIndex;
    CGFloat bestOverlap = -1;
    CGFloat visibleMidY = NSMidY(visibleRect);
    CGFloat closestDistance = CGFLOAT_MAX;
    for (SPDFRenderedPage* page in self.pages) {
        NSRect pageRect = [self rectForPageAtIndex:page.pageIndex];
        CGFloat overlap = NSHeight(NSIntersectionRect(visibleRect, pageRect));
        if (overlap > bestOverlap) {
            bestOverlap = overlap;
            bestPage = page.pageIndex;
        }
        if (overlap <= 0.0) {
            CGFloat distance =
                visibleMidY < NSMinY(pageRect) ? NSMinY(pageRect) - visibleMidY : visibleMidY - NSMaxY(pageRect);
            if (distance < closestDistance) {
                closestDistance = distance;
                if (bestOverlap <= 0.0) bestPage = page.pageIndex;
            }
        }
    }
    return bestPage;
}

- (void)drawPage:(SPDFRenderedPage*)page inRect:(NSRect)pageRect {
    NSShadow* shadow = [[NSShadow alloc] init];
    shadow.shadowBlurRadius = 12.0;
    shadow.shadowOffset = NSMakeSize(0.0, -2.0);
    shadow.shadowColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.28];

    [NSGraphicsContext saveGraphicsState];
    if (!self.presentationMode) [shadow set];
    [[NSColor whiteColor] setFill];
    NSRectFill(pageRect);
    [NSGraphicsContext restoreGraphicsState];

    if (page.image) {
        BOOL exactSize = fabs(NSWidth(pageRect) - page.imagePointWidth) < 0.01 &&
                         fabs(NSHeight(pageRect) - page.imagePointHeight) < 0.01;
        NSGraphicsContext* context = NSGraphicsContext.currentContext;
        NSImageInterpolation oldInterpolation = context.imageInterpolation;
        NSImageInterpolation interpolation = exactSize ? NSImageInterpolationNone : NSImageInterpolationHigh;
        context.imageInterpolation = interpolation;
        [page.image drawInRect:pageRect
                      fromRect:NSZeroRect
                     operation:NSCompositingOperationSourceOver
                      fraction:1.0
                respectFlipped:YES
                         hints:@{NSImageHintInterpolation : @(interpolation)}];
        context.imageInterpolation = oldInterpolation;
    }

    if (page.highlights.count > 0 && self.zoom > 0) {
        [[NSColor colorWithCalibratedRed:1.0 green:0.84 blue:0.12 alpha:0.38] setFill];
        for (NSValue* value in page.highlights) {
            NSRect r = [self convertPageRect:[value rectValue] toViewRectInPageRect:pageRect page:page];
            [[NSBezierPath bezierPathWithRoundedRect:r xRadius:2.0 yRadius:2.0] fill];
        }
    }

    if (self.activeFindAlpha > 0 && page.pageIndex == self.activeFindPageIndex && self.zoom > 0) {
        NSRect r = [self convertPageRect:self.activeFindRect toViewRectInPageRect:pageRect page:page];
        r = NSInsetRect(r, -2.0, -2.0);
        [[NSColor colorWithCalibratedRed:0.94 green:0.03 blue:0.02 alpha:self.activeFindAlpha] setStroke];
        NSBezierPath* path = [NSBezierPath bezierPathWithRect:r];
        path.lineWidth = 1.2;
        [path stroke];
    }

    if (page.selectionRects.count > 0 && self.zoom > 0) {
        [[NSColor colorWithCalibratedRed:0.40 green:0.62 blue:0.86 alpha:kSelectionOverlayAlpha] setFill];
        for (NSValue* value in page.selectionRects) {
            NSRect r = [self convertPageRect:[value rectValue] toViewRectInPageRect:pageRect page:page];
            NSRectFillUsingOperation(r, NSCompositingOperationSourceOver);
        }
    }

    NSArray<NSDictionary*>* comments = [self.reader commentAnnotationsForPage:page.pageIndex];
    if (comments.count > 0 && self.zoom > 0) {
        [[NSColor colorWithCalibratedRed:1.0 green:0.76 blue:0.10 alpha:0.16] setFill];
        [[NSColor colorWithCalibratedRed:0.92 green:0.52 blue:0.0 alpha:0.95] setStroke];
        for (NSDictionary* comment in comments) {
            NSRect r = [self convertPageRect:[comment[@"bounds"] rectValue] toViewRectInPageRect:pageRect page:page];
            r = NSInsetRect(r, -2.0, -2.0);
            NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:r xRadius:3.0 yRadius:3.0];
            [path fill];
            path.lineWidth = 1.2;
            [path stroke];
        }
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [(self.presentationMode ? NSColor.blackColor : NSColor.windowBackgroundColor) setFill];
    NSRectFill(self.bounds);

    if (self.pages.count == 0) {
        NSMutableParagraphStyle* style = [[NSMutableParagraphStyle alloc] init];
        style.alignment = NSTextAlignmentCenter;
        NSDictionary* attrs = @{
            NSForegroundColorAttributeName : [NSColor secondaryLabelColor],
            NSFontAttributeName : [NSFont systemFontOfSize:16 weight:NSFontWeightMedium],
            NSParagraphStyleAttributeName : style
        };
        NSString* message = self.emptyMessage.length ? self.emptyMessage : @"Open a document";
        NSRect textRect =
            NSMakeRect(32.0, MAX(72.0, NSMidY(self.bounds) - 18.0), MAX(1.0, NSWidth(self.bounds) - 64.0), 44.0);
        [message drawWithRect:textRect
                      options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine
                   attributes:attrs];
        return;
    }

    if (self.viewMode == SPDFViewModeSingle) {
        NSInteger index = MAX(0, MIN(self.currentPageIndex, (NSInteger)self.pages.count - 1));
        SPDFRenderedPage* page = self.pages[(NSUInteger)index];
        NSRect pageRect = [self rectForPageAtIndex:index];
        if (NSIntersectsRect(dirtyRect, pageRect)) [self drawPage:page inRect:pageRect];
        return;
    }

    for (SPDFRenderedPage* page in self.pages) {
        NSRect pageRect = [self rectForPageAtIndex:page.pageIndex];
        if (NSIntersectsRect(dirtyRect, pageRect)) [self drawPage:page inRect:pageRect];
    }
}

- (BOOL)point:(NSPoint)point fallsInPage:(NSInteger*)pageIndex pagePoint:(NSPoint*)pagePoint {
    if (self.viewMode == SPDFViewModeSingle && self.pages.count > 0) {
        NSInteger index = MAX(0, MIN(self.currentPageIndex, (NSInteger)self.pages.count - 1));
        NSRect pageRect = [self rectForPageAtIndex:index];
        if (NSPointInRect(point, pageRect)) {
            if (pageIndex) *pageIndex = index;
            if (pagePoint)
                *pagePoint =
                    [self convertViewPoint:point toPagePointInPageRect:pageRect page:self.pages[(NSUInteger)index]];
            return YES;
        }
        return NO;
    }

    for (SPDFRenderedPage* page in self.pages) {
        NSRect pageRect = [self rectForPageAtIndex:page.pageIndex];
        if (NSPointInRect(point, pageRect)) {
            if (pageIndex) *pageIndex = page.pageIndex;
            if (pagePoint) *pagePoint = [self convertViewPoint:point toPagePointInPageRect:pageRect page:page];
            return YES;
        }
    }
    return NO;
}

- (void)updateHoveredCommentForEvent:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSPoint pagePoint = NSZeroPoint;
    NSInteger pageIndex = -1;
    NSDictionary* hitComment = nil;
    if ([self point:point fallsInPage:&pageIndex pagePoint:&pagePoint]) {
        for (NSDictionary* comment in [self.reader commentAnnotationsForPage:pageIndex]) {
            NSRect bounds = [comment[@"bounds"] rectValue];
            if (NSPointInRect(pagePoint, NSInsetRect(bounds, -3.0, -3.0))) {
                hitComment = comment;
                break;
            }
        }
    }

    if (hitComment == _hoveredComment || [hitComment isEqualToDictionary:_hoveredComment]) {
        if (hitComment) [self.reader documentViewHoverComment:hitComment atWindowPoint:event.locationInWindow];
        return;
    }

    _hoveredComment = hitComment;
    if (hitComment)
        [self.reader documentViewHoverComment:hitComment atWindowPoint:event.locationInWindow];
    else
        [self.reader documentViewEndHoverComment];
}

- (void)mouseDown:(NSEvent*)event {
    [self.reader clearFindFieldFocus];
    if (!self.reader) {
        [super mouseDown:event];
        return;
    }
    if ([self.reader documentViewHandlePresentationMouseDown:event]) return;
    if (event.modifierFlags & NSEventModifierFlagControl) {
        [self.reader showContextMenuForDocumentView:self event:event];
        return;
    }

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSPoint pagePoint = NSZeroPoint;
    NSInteger pageIndex = -1;
    if ([self point:point fallsInPage:&pageIndex pagePoint:&pagePoint]) {
        if ([self.reader documentViewOpenLinkAtPageIndex:pageIndex pagePoint:pagePoint]) return;
        _isSelecting = YES;
        _selectionPageIndex = pageIndex;
        _selectionStart = pagePoint;
        [self.reader documentViewSelectionChangedOnPage:pageIndex from:pagePoint to:pagePoint];
    } else {
        [super mouseDown:event];
    }
}

- (void)mouseMoved:(NSEvent*)event {
    [self updateHoveredCommentForEvent:event];
    if (!self.reader) return;
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSPoint pagePoint = NSZeroPoint;
    NSInteger pageIndex = -1;
    BOOL hasLink = [self point:point fallsInPage:&pageIndex pagePoint:&pagePoint] &&
                   [self.reader documentViewHasLinkAtPageIndex:pageIndex pagePoint:pagePoint];
    [(hasLink ? NSCursor.pointingHandCursor : NSCursor.arrowCursor) set];
}

- (void)mouseExited:(NSEvent*)event {
    (void)event;
    _hoveredComment = nil;
    [self.reader documentViewEndHoverComment];
    [NSCursor.arrowCursor set];
}

- (void)keyDown:(NSEvent*)event {
    if (self.reader && [self.reader documentArrowKeyDown:event]) return;
    [super keyDown:event];
}

- (void)mouseDragged:(NSEvent*)event {
    [self.reader clearFindFieldFocus];
    if (!_isSelecting) {
        [super mouseDragged:event];
        return;
    }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect pageRect = [self rectForPageAtIndex:_selectionPageIndex];
    if (NSIsEmptyRect(pageRect)) return;
    SPDFRenderedPage* page = self.pages[(NSUInteger)_selectionPageIndex];
    NSPoint pagePoint = [self convertViewPoint:point toPagePointInPageRect:pageRect page:page];
    [self.reader documentViewSelectionChangedOnPage:_selectionPageIndex from:_selectionStart to:pagePoint];
}

- (void)mouseUp:(NSEvent*)event {
    (void)event;
    _isSelecting = NO;
}

- (void)beginPanWithEvent:(NSEvent*)event {
    [self.reader clearFindFieldFocus];
    NSScrollView* scrollView = self.enclosingScrollView;
    if (!scrollView) return;
    [_inertiaTimer invalidate];
    _inertiaTimer = nil;
    _isPanning = YES;
    _panStartInWindow = event.locationInWindow;
    _panStartOrigin = scrollView.contentView.bounds.origin;
    _lastPanPoint = event.locationInWindow;
    _lastPanTime = event.timestamp;
    _panVelocity = NSZeroPoint;
    [[NSCursor closedHandCursor] set];
}

- (void)continuePanWithEvent:(NSEvent*)event {
    if (!_isPanning) return;

    NSScrollView* scrollView = self.enclosingScrollView;
    NSClipView* clipView = scrollView.contentView;
    NSPoint current = event.locationInWindow;
    NSPoint delta = NSMakePoint(current.x - _panStartInWindow.x, current.y - _panStartInWindow.y);
    NSPoint origin = NSMakePoint(_panStartOrigin.x - delta.x, _panStartOrigin.y + delta.y);
    NSTimeInterval dt = MAX(0.001, event.timestamp - _lastPanTime);
    _panVelocity = NSMakePoint((current.x - _lastPanPoint.x) / dt, (current.y - _lastPanPoint.y) / dt);
    _lastPanPoint = current;
    _lastPanTime = event.timestamp;
    origin.x = MAX(0, MIN(origin.x, MAX(0, NSWidth(self.bounds) - NSWidth(clipView.bounds))));
    origin.y = MAX(0, MIN(origin.y, MAX(0, NSHeight(self.bounds) - NSHeight(clipView.bounds))));
    [clipView scrollToPoint:origin];
    [scrollView reflectScrolledClipView:clipView];
}

- (void)stepPanInertia:(NSTimer*)timer {
    NSScrollView* scrollView = self.enclosingScrollView;
    NSClipView* clipView = scrollView.contentView;
    if (!scrollView || !clipView) {
        [timer invalidate];
        _inertiaTimer = nil;
        return;
    }

    NSPoint origin = clipView.bounds.origin;
    origin.x -= _panVelocity.x / 60.0;
    origin.y += _panVelocity.y / 60.0;
    origin.x = MAX(0, MIN(origin.x, MAX(0, NSWidth(self.bounds) - NSWidth(clipView.bounds))));
    origin.y = MAX(0, MIN(origin.y, MAX(0, NSHeight(self.bounds) - NSHeight(clipView.bounds))));
    [clipView scrollToPoint:origin];
    [scrollView reflectScrolledClipView:clipView];

    _panVelocity.x *= 0.90;
    _panVelocity.y *= 0.90;
    if (hypot(_panVelocity.x, _panVelocity.y) < 12.0) {
        [timer invalidate];
        _inertiaTimer = nil;
    }
}

- (void)endPan {
    _isPanning = NO;
    [[NSCursor arrowCursor] set];
    if (hypot(_panVelocity.x, _panVelocity.y) > 90.0) {
        [_inertiaTimer invalidate];
        _inertiaTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
                                                         target:self
                                                       selector:@selector(stepPanInertia:)
                                                       userInfo:nil
                                                        repeats:YES];
    }
}

- (void)cancelTransientInteraction {
    [_inertiaTimer invalidate];
    _inertiaTimer = nil;
    _isPanning = NO;
    _isSelecting = NO;
    _rightMouseMoved = NO;
    _panVelocity = NSZeroPoint;
    _selectionPageIndex = -1;
}

- (void)rightMouseDown:(NSEvent*)event {
    _rightMouseMoved = NO;
    if (self.reader && [self.reader documentViewHandlePresentationMouseDown:event]) {
        _rightMouseMoved = YES;
        return;
    }
    if (event.modifierFlags & NSEventModifierFlagCommand) return;
    [self beginPanWithEvent:event];
}

- (void)rightMouseDragged:(NSEvent*)event {
    _rightMouseMoved = YES;
    if (_isPanning) [self continuePanWithEvent:event];
}

- (void)rightMouseUp:(NSEvent*)event {
    if (self.reader && [self.reader documentViewInPresentationMode]) return;
    BOOL forceMenu = (event.modifierFlags & NSEventModifierFlagCommand) != 0;
    if (forceMenu || !_rightMouseMoved) [self.reader showContextMenuForDocumentView:self event:event];
    if (_isPanning) [self endPan];
}

- (void)otherMouseDown:(NSEvent*)event {
    if (event.buttonNumber == 2)
        [self beginPanWithEvent:event];
    else
        [super otherMouseDown:event];
}

- (void)otherMouseDragged:(NSEvent*)event {
    if (_isPanning)
        [self continuePanWithEvent:event];
    else
        [super otherMouseDragged:event];
}

- (void)otherMouseUp:(NSEvent*)event {
    if (_isPanning)
        [self endPan];
    else
        [super otherMouseUp:event];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    (void)sender;
    return NSDragOperationCopy;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    return [self.reader openFilesFromPasteboard:sender.draggingPasteboard];
}

@end

@implementation SPDFMinimapView {
    BOOL _draggingVisibleRect;
    NSPoint _dragOffsetFromVisibleCenter;
    CGFloat _dragOffsetFromVisibleTop;
    CGFloat _dragThumbTop;
    CGFloat _dragLastMouseY;
    CGFloat _dragSmoothedScale;
    CGFloat _dragAccelerationBlend;
    NSTimeInterval _dragLastTimestamp;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)setPages:(NSArray<SPDFRenderedPage*>*)pages {
    _pages = [pages copy];
    [self setNeedsDisplay:YES];
}

- (CGFloat)widestPage {
    CGFloat widest = 0;
    for (SPDFRenderedPage* page in self.pages) widest = MAX(widest, page.pageWidth);
    return widest;
}

- (CGFloat)scrollFraction {
    CGFloat visibleHeight = NSHeight(self.documentVisibleRect);
    CGFloat maxScroll = MAX(1.0, self.documentHeight - visibleHeight);
    return spdf_clamp_cg(NSMinY(self.documentVisibleRect) / maxScroll, 0.0, 1.0);
}

- (NSRect)miniRectForPage:(SPDFRenderedPage*)targetPage scale:(CGFloat)scale gap:(CGFloat)gap {
    CGFloat y = 0;
    for (SPDFRenderedPage* page in self.pages) {
        CGFloat pageWidth = MAX(1.0, page.pageWidth * scale);
        CGFloat pageHeight = MAX(1.0, page.pageHeight * scale);
        if (page == targetPage || page.pageIndex == targetPage.pageIndex) {
            return NSMakeRect(floor((NSWidth(self.bounds) - pageWidth) / 2.0), y, pageWidth, pageHeight);
        }
        y += pageHeight + gap;
    }
    return NSZeroRect;
}

- (NSRect)documentRectForPage:(SPDFRenderedPage*)targetPage {
    if (targetPage.pageIndex >= 0 && targetPage.pageIndex < (NSInteger)self.documentPageRects.count) {
        NSRect rect = [self.documentPageRects[(NSUInteger)targetPage.pageIndex] rectValue];
        if (!NSIsEmptyRect(rect)) return rect;
    }

    CGFloat documentScale = MAX(0.01, self.documentScale);
    CGFloat documentWidth = MAX(1.0, self.documentWidth);
    CGFloat y = kPageMargin / 2.0;

    for (SPDFRenderedPage* page in self.pages) {
        if (page.pageIndex >= targetPage.pageIndex) break;
        y += page.pageHeight * documentScale + kPageGap;
    }

    CGFloat width = MAX(1.0, targetPage.pageWidth * documentScale);
    CGFloat height = MAX(1.0, targetPage.pageHeight * documentScale);
    CGFloat x = floor((documentWidth - width) / 2.0);
    return NSMakeRect(MAX(kPageMargin / 2.0, x), y, width, height);
}

- (NSRect)miniRectForDocumentIntersection:(NSRect)intersection
                             documentRect:(NSRect)documentRect
                                 miniRect:(NSRect)miniRect {
    if (NSIsEmptyRect(intersection) || NSIsEmptyRect(documentRect) || NSIsEmptyRect(miniRect)) return NSZeroRect;

    CGFloat x0 = spdf_clamp_cg((NSMinX(intersection) - NSMinX(documentRect)) / NSWidth(documentRect), 0.0, 1.0);
    CGFloat x1 = spdf_clamp_cg((NSMaxX(intersection) - NSMinX(documentRect)) / NSWidth(documentRect), 0.0, 1.0);
    CGFloat y0 = spdf_clamp_cg((NSMinY(intersection) - NSMinY(documentRect)) / NSHeight(documentRect), 0.0, 1.0);
    CGFloat y1 = spdf_clamp_cg((NSMaxY(intersection) - NSMinY(documentRect)) / NSHeight(documentRect), 0.0, 1.0);

    return NSMakeRect(NSMinX(miniRect) + x0 * NSWidth(miniRect), NSMinY(miniRect) + y0 * NSHeight(miniRect),
                      MAX(1.0, (x1 - x0) * NSWidth(miniRect)), MAX(1.0, (y1 - y0) * NSHeight(miniRect)));
}

- (NSRect)unscrolledVisibleRectForScale:(CGFloat)scale gap:(CGFloat)gap contentHeight:(CGFloat)contentHeight {
    if (self.pages.count == 0 || contentHeight <= 0) return NSZeroRect;

    if (self.documentHeight > 1.0) {
        NSRect visible = NSZeroRect;
        BOOL hasVisiblePage = NO;
        for (SPDFRenderedPage* page in self.pages) {
            NSRect documentRect = [self documentRectForPage:page];
            NSRect intersection = NSIntersectionRect(self.documentVisibleRect, documentRect);
            if (NSIsEmptyRect(intersection)) continue;

            NSRect miniRect = [self miniRectForPage:page scale:scale gap:gap];
            NSRect miniVisible =
                [self miniRectForDocumentIntersection:intersection documentRect:documentRect miniRect:miniRect];
            if (NSIsEmptyRect(miniVisible)) continue;

            visible = hasVisiblePage ? NSUnionRect(visible, miniVisible) : miniVisible;
            hasVisiblePage = YES;
        }
        if (hasVisiblePage) return NSInsetRect(visible, -2.0, -2.0);
    }

    CGFloat heightFraction =
        spdf_clamp_cg(NSHeight(self.documentVisibleRect) / MAX(1.0, self.documentHeight), 0.02, 1.0);
    CGFloat height = MAX(10.0, heightFraction * contentHeight);
    CGFloat top = [self scrollFraction] * MAX(0.0, contentHeight - height);
    if (top + height > contentHeight) top = MAX(0.0, contentHeight - height);
    return NSMakeRect(5.0, top, NSWidth(self.bounds) - 10.0, height);
}

- (BOOL)layoutScale:(CGFloat*)scaleOut
                gap:(CGFloat*)gapOut
         contentTop:(CGFloat*)topOut
      contentHeight:(CGFloat*)heightOut
        visibleRect:(NSRect*)visibleOut {
    if (self.pages.count == 0 || NSWidth(self.bounds) < 16 || NSHeight(self.bounds) < 16) return NO;

    CGFloat widest = [self widestPage];
    if (widest <= 0) return NO;

    CGFloat scale = (NSWidth(self.bounds) - 18.0) / widest;
    CGFloat gap = 4.0;
    CGFloat contentHeight = 0;
    for (SPDFRenderedPage* page in self.pages) contentHeight += page.pageHeight * scale;
    contentHeight += gap * MAX(0, (NSInteger)self.pages.count - 1);
    CGFloat available = MAX(1.0, NSHeight(self.bounds) - 16.0);
    NSRect visible = [self unscrolledVisibleRectForScale:scale gap:gap contentHeight:contentHeight];
    CGFloat offset = 0;
    if (contentHeight > available) {
        CGFloat maxOffset = contentHeight - available;
        offset = [self scrollFraction] * maxOffset;
    }

    CGFloat contentTop =
        contentHeight < available ? floor((NSHeight(self.bounds) - contentHeight) / 2.0) : 8.0 - offset;
    visible.origin.y += contentTop;
    if (scaleOut) *scaleOut = scale;
    if (gapOut) *gapOut = gap;
    if (topOut) *topOut = contentTop;
    if (heightOut) *heightOut = contentHeight;
    if (visibleOut) *visibleOut = visible;
    return YES;
}

- (CGFloat)contentTopForDocumentCenterY:(CGFloat)documentY contentHeight:(CGFloat)contentHeight {
    CGFloat available = MAX(1.0, NSHeight(self.bounds) - 16.0);
    if (contentHeight < available) return floor((NSHeight(self.bounds) - contentHeight) / 2.0);

    CGFloat visibleHeight = NSHeight(self.documentVisibleRect);
    CGFloat maxScroll = MAX(1.0, self.documentHeight - visibleHeight);
    CGFloat originY = spdf_clamp_cg(documentY - visibleHeight * 0.5, 0.0, maxScroll);
    CGFloat offset = (originY / maxScroll) * (contentHeight - available);
    return 8.0 - offset;
}

- (NSPoint)documentPointForUnscrolledMiniPoint:(NSPoint)point scale:(CGFloat)scale gap:(CGFloat)gap {
    CGFloat y = 0;
    for (SPDFRenderedPage* page in self.pages) {
        NSRect miniRect = [self miniRectForPage:page scale:scale gap:gap];
        NSRect documentRect = [self documentRectForPage:page];
        if (NSIsEmptyRect(miniRect) || NSIsEmptyRect(documentRect)) {
            y += MAX(1.0, page.pageHeight * scale) + gap;
            continue;
        }

        if (point.y >= NSMinY(miniRect) && point.y <= NSMaxY(miniRect)) {
            CGFloat xFraction = spdf_clamp_cg((point.x - NSMinX(miniRect)) / MAX(1.0, NSWidth(miniRect)), 0.0, 1.0);
            CGFloat yFraction = spdf_clamp_cg((point.y - NSMinY(miniRect)) / MAX(1.0, NSHeight(miniRect)), 0.0, 1.0);
            return NSMakePoint(NSMinX(documentRect) + xFraction * NSWidth(documentRect),
                               NSMinY(documentRect) + yFraction * NSHeight(documentRect));
        }

        CGFloat gapStart = NSMaxY(miniRect);
        CGFloat gapEnd = gapStart + gap;
        if (point.y > gapStart && point.y < gapEnd) {
            CGFloat xFraction = spdf_clamp_cg((point.x - NSMinX(miniRect)) / MAX(1.0, NSWidth(miniRect)), 0.0, 1.0);
            CGFloat gapFraction = spdf_clamp_cg((point.y - gapStart) / MAX(1.0, gap), 0.0, 1.0);
            return NSMakePoint(NSMinX(documentRect) + xFraction * NSWidth(documentRect),
                               NSMaxY(documentRect) + gapFraction * kPageGap);
        }
        y += MAX(1.0, page.pageHeight * scale) + gap;
    }

    CGFloat yFraction = spdf_clamp_cg(point.y / MAX(1.0, y), 0.0, 1.0);
    return NSMakePoint(NSMidX(self.documentVisibleRect), yFraction * self.documentHeight);
}

- (NSPoint)documentPointForMinimapCenterPoint:(NSPoint)point
                                        scale:(CGFloat)scale
                                          gap:(CGFloat)gap
                                contentHeight:(CGFloat)contentHeight
                                   contentTop:(CGFloat)contentTop {
    NSPoint documentPoint =
        [self documentPointForUnscrolledMiniPoint:NSMakePoint(point.x, point.y - contentTop) scale:scale gap:gap];
    for (NSInteger i = 0; i < 8; ++i) {
        CGFloat projectedTop = [self contentTopForDocumentCenterY:documentPoint.y contentHeight:contentHeight];
        NSPoint unscrolledPoint = NSMakePoint(point.x, point.y - projectedTop);
        documentPoint = [self documentPointForUnscrolledMiniPoint:unscrolledPoint scale:scale gap:gap];
    }
    return documentPoint;
}

- (NSRect)draggableVisibleRectForRect:(NSRect)visibleRect {
    return NSIntersectionRect(visibleRect, NSInsetRect(self.bounds, 1.0, 1.0));
}

- (BOOL)shouldUsePrecisionViewportDrag {
    return self.pages.count >= 20;
}

- (CGFloat)precisionViewportBaseDragScale {
    return spdf_clamp_cg(20.0 / MAX(1.0, (CGFloat)self.pages.count), 0.35, 0.85);
}

- (NSTimeInterval)precisionViewportDragDeltaTimeForTimestamp:(NSTimeInterval)timestamp {
    NSTimeInterval deltaT = timestamp - _dragLastTimestamp;
    if (!isfinite(deltaT) || deltaT <= 0.0) deltaT = 1.0 / 60.0;
    return spdf_clamp_cg(deltaT, 1.0 / 240.0, 1.0 / 20.0);
}

- (CGFloat)precisionViewportDragScaleForDeltaY:(CGFloat)deltaY timestamp:(NSTimeInterval)timestamp {
    if (![self shouldUsePrecisionViewportDrag]) return 1.0;

    CGFloat baseScale = [self precisionViewportBaseDragScale];
    NSTimeInterval deltaT = [self precisionViewportDragDeltaTimeForTimestamp:timestamp];
    CGFloat speed = fabs(deltaY) / deltaT;
    CGFloat targetBlend = spdf_clamp_cg((speed - 80.0) / (720.0 - 80.0), 0.0, 1.0);
    targetBlend = targetBlend * targetBlend * targetBlend * (targetBlend * (targetBlend * 6.0 - 15.0) + 10.0);
    if (_dragSmoothedScale <= 0.0) _dragSmoothedScale = baseScale;

    CGFloat smoothing = 1.0 - exp(-deltaT / 0.12);
    _dragAccelerationBlend += (targetBlend - _dragAccelerationBlend) * smoothing;
    _dragSmoothedScale = baseScale + (1.0 - baseScale) * _dragAccelerationBlend;
    return _dragSmoothedScale;
}

- (BOOL)documentPointForEvent:(NSEvent*)event documentPoint:(NSPoint*)documentPointOut {
    CGFloat scale = 1.0;
    CGFloat gap = 4.0;
    CGFloat contentTop = 8.0;
    CGFloat contentHeight = 0;
    if (![self layoutScale:&scale gap:&gap contentTop:&contentTop contentHeight:&contentHeight visibleRect:NULL])
        return NO;

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (documentPointOut)
        *documentPointOut = [self documentPointForMinimapCenterPoint:point
                                                               scale:scale
                                                                 gap:gap
                                                       contentHeight:contentHeight
                                                          contentTop:contentTop];
    return YES;
}

- (void)drawPlaceholderInRect:(NSRect)rect {
    if (NSHeight(rect) < 6.0 || NSWidth(rect) < 10.0) return;
    [[NSColor colorWithCalibratedWhite:0.76 alpha:0.34] setFill];
    NSInteger lines = (NSInteger)spdf_clamp_cg(floor(NSHeight(rect) / 7.0), 2.0, 16.0);
    CGFloat y = NSMinY(rect) + MAX(2.0, NSHeight(rect) * 0.08);
    CGFloat lineHeight = MAX(1.0, NSHeight(rect) * 0.018);
    for (NSInteger i = 0; i < lines; ++i) {
        CGFloat widthFactor = (i % 5 == 4) ? 0.56 : 0.78;
        NSRect line = NSMakeRect(NSMinX(rect) + NSWidth(rect) * 0.12, y, NSWidth(rect) * widthFactor, lineHeight);
        NSRectFillUsingOperation(line, NSCompositingOperationSourceOver);
        y += MAX(3.0, NSHeight(rect) / (CGFloat)(lines + 2));
        if (y > NSMaxY(rect) - 2.0) break;
    }
}

- (void)drawRects:(NSArray<NSValue*>*)rects
         pageRect:(NSRect)pageRect
            scale:(CGFloat)scale
            color:(NSColor*)color
        minHeight:(CGFloat)minHeight {
    if (rects.count == 0) return;
    [color setFill];
    for (NSValue* value in rects) {
        NSRect r = [value rectValue];
        r.origin.x = NSMinX(pageRect) + r.origin.x * scale;
        r.origin.y = NSMinY(pageRect) + r.origin.y * scale;
        r.size.width = MAX(1.0, r.size.width * scale);
        r.size.height = MAX(minHeight, r.size.height * scale);
        NSRectFillUsingOperation(NSIntersectionRect(r, pageRect), NSCompositingOperationSourceOver);
    }
}

- (void)drawSearchRects:(NSArray<NSValue*>*)rects pageRect:(NSRect)pageRect scale:(CGFloat)scale {
    if (rects.count == 0) return;
    for (NSValue* value in rects) {
        NSRect r = [value rectValue];
        r.origin.x = NSMinX(pageRect) + r.origin.x * scale;
        r.origin.y = NSMinY(pageRect) + r.origin.y * scale;
        r.size.width = MAX(2.0, r.size.width * scale);
        r.size.height = MAX(3.0, r.size.height * scale);
        CGFloat cx = NSMidX(r);
        CGFloat cy = NSMidY(r);
        r.size.width *= 2.0;
        r.origin.x = cx - NSWidth(r) / 2.0;
        r.origin.y = cy - NSHeight(r) / 2.0;
        r = NSIntersectionRect(r, NSInsetRect(pageRect, -1.0, -1.0));
        if (NSIsEmptyRect(r)) continue;
        [[NSColor colorWithCalibratedRed:1.0 green:0.86 blue:0.06 alpha:0.88] setFill];
        NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:r xRadius:1.5 yRadius:1.5];
        [path fill];
        [[NSColor colorWithCalibratedRed:0.88 green:0.08 blue:0.03 alpha:0.96] setStroke];
        path.lineWidth = 1.1;
        [path stroke];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [NSColor.windowBackgroundColor setFill];
    NSRectFill(self.bounds);
    [NSColor.separatorColor setFill];
    NSRectFill(NSMakeRect(0, 0, 1, NSHeight(self.bounds)));

    CGFloat scale = 1.0;
    CGFloat gap = 4.0;
    CGFloat contentTop = 8.0;
    CGFloat contentHeight = 0;
    NSRect visibleRect = NSZeroRect;
    if (!
        [self layoutScale:&scale gap:&gap contentTop:&contentTop contentHeight:&contentHeight visibleRect:&visibleRect])
        return;

    CGFloat y = contentTop;
    BOOL drawImages = self.pages.count <= 400;
    for (SPDFRenderedPage* page in self.pages) {
        CGFloat pageWidth = page.pageWidth * scale;
        CGFloat pageHeight = MAX(1.0, page.pageHeight * scale);
        NSRect pageRect = NSMakeRect(floor((NSWidth(self.bounds) - pageWidth) / 2.0), y, pageWidth, pageHeight);
        if (NSHeight(pageRect) >= 1.0 && NSIntersectsRect(pageRect, self.bounds)) {
            [[NSColor whiteColor] setFill];
            NSRectFillUsingOperation(pageRect, NSCompositingOperationSourceOver);
            if (drawImages && page.image && NSHeight(pageRect) >= 5.0) {
                [page.image drawInRect:pageRect
                              fromRect:NSZeroRect
                             operation:NSCompositingOperationSourceOver
                              fraction:1.0
                        respectFlipped:YES
                                 hints:@{NSImageHintInterpolation : @(NSImageInterpolationLow)}];
            } else {
                [self drawPlaceholderInRect:pageRect];
            }
            [self drawSearchRects:page.highlights pageRect:pageRect scale:scale];
            [self drawRects:page.selectionRects
                   pageRect:pageRect
                      scale:scale
                      color:[NSColor colorWithCalibratedRed:0.30 green:0.58 blue:0.93 alpha:0.70]
                  minHeight:1.0];
            if (page.pageIndex == self.currentPageIndex) {
                [[NSColor controlAccentColor] setStroke];
                NSBezierPath* path = [NSBezierPath bezierPathWithRect:NSInsetRect(pageRect, -1, -1)];
                path.lineWidth = 1.5;
                [path stroke];
            }
        }
        y += pageHeight + gap;
    }

    if (contentHeight > 1.0) {
        visibleRect = NSIntersectionRect(visibleRect, NSInsetRect(self.bounds, 1.0, 1.0));
        if (NSWidth(visibleRect) > 1.0 && NSHeight(visibleRect) > 1.0) {
            [[NSColor colorWithCalibratedRed:0.18 green:0.55 blue:0.92 alpha:0.18] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:visibleRect xRadius:4 yRadius:4] fill];
            [[NSColor controlAccentColor] setStroke];
            NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:visibleRect xRadius:4 yRadius:4];
            path.lineWidth = 1.2;
            [path stroke];
        }
    }
}

- (void)sendScrollRequestForEvent:(NSEvent*)event {
    CGFloat scale = 1.0;
    CGFloat gap = 4.0;
    CGFloat contentTop = 8.0;
    CGFloat contentHeight = 0;
    NSRect visibleRect = NSZeroRect;
    if (!
        [self layoutScale:&scale gap:&gap contentTop:&contentTop contentHeight:&contentHeight visibleRect:&visibleRect])
        return;

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (_draggingVisibleRect && [self shouldUsePrecisionViewportDrag]) {
        NSRect track = NSInsetRect(self.bounds, 1.0, 1.0);
        NSRect drawnVisibleRect = [self draggableVisibleRectForRect:visibleRect];
        CGFloat thumbHeight = MIN(NSHeight(drawnVisibleRect), NSHeight(track));
        CGFloat minTop = NSMinY(track);
        CGFloat maxTop = MAX(minTop, NSMaxY(track) - thumbHeight);
        CGFloat rawTop = point.y - _dragOffsetFromVisibleTop;

        if (rawTop <= minTop) {
            _dragThumbTop = minTop;
            _dragLastMouseY = point.y;
            _dragLastTimestamp = event.timestamp;
            [self.reader minimapViewDidRequestScrollToFraction:0.0];
            return;
        }
        if (rawTop >= maxTop) {
            _dragThumbTop = maxTop;
            _dragLastMouseY = point.y;
            _dragLastTimestamp = event.timestamp;
            [self.reader minimapViewDidRequestScrollToFraction:1.0];
            return;
        }

        CGFloat deltaY = point.y - _dragLastMouseY;
        CGFloat dragScale = [self precisionViewportDragScaleForDeltaY:deltaY timestamp:event.timestamp];
        _dragThumbTop = spdf_clamp_cg(_dragThumbTop + deltaY * dragScale, minTop, maxTop);

        _dragLastMouseY = point.y;
        _dragLastTimestamp = event.timestamp;
        point = NSMakePoint(point.x - _dragOffsetFromVisibleCenter.x, _dragThumbTop + thumbHeight * 0.5);
    } else if (_draggingVisibleRect) {
        point = NSMakePoint(point.x - _dragOffsetFromVisibleCenter.x, point.y - _dragOffsetFromVisibleCenter.y);
    }
    NSPoint documentPoint = [self documentPointForMinimapCenterPoint:point
                                                               scale:scale
                                                                 gap:gap
                                                       contentHeight:contentHeight
                                                          contentTop:contentTop];
    [self.reader minimapViewDidRequestCenterAtDocumentPoint:documentPoint];
}

- (void)mouseDown:(NSEvent*)event {
    CGFloat scale = 1.0;
    CGFloat gap = 4.0;
    CGFloat contentTop = 8.0;
    CGFloat contentHeight = 0;
    NSRect visibleRect = NSZeroRect;
    if (!
        [self layoutScale:&scale gap:&gap contentTop:&contentTop contentHeight:&contentHeight visibleRect:&visibleRect])
        return;

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect drawnVisibleRect = [self draggableVisibleRectForRect:visibleRect];
    _draggingVisibleRect = NSPointInRect(point, drawnVisibleRect);
    _dragOffsetFromVisibleCenter =
        _draggingVisibleRect ? NSMakePoint(point.x - NSMidX(drawnVisibleRect), point.y - NSMidY(drawnVisibleRect))
                             : NSZeroPoint;
    _dragOffsetFromVisibleTop = _draggingVisibleRect ? point.y - NSMinY(drawnVisibleRect) : 0.0;
    _dragThumbTop = _draggingVisibleRect ? NSMinY(drawnVisibleRect) : 0.0;
    _dragLastMouseY = point.y;
    _dragSmoothedScale = [self shouldUsePrecisionViewportDrag] ? [self precisionViewportBaseDragScale] : 1.0;
    _dragAccelerationBlend = 0.0;
    _dragLastTimestamp = event.timestamp;
    if (!_draggingVisibleRect) [self sendScrollRequestForEvent:event];
}

- (void)mouseDragged:(NSEvent*)event {
    [self sendScrollRequestForEvent:event];
}

- (void)scrollWheel:(NSEvent*)event {
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    if (flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) {
        NSPoint documentPoint = NSZeroPoint;
        if ([self documentPointForEvent:event documentPoint:&documentPoint])
            [self.reader minimapViewDidReceiveZoomScrollWheel:event documentPoint:documentPoint];
        return;
    }

    [self.reader minimapViewDidReceiveScrollWheel:event];
}

- (void)magnifyWithEvent:(NSEvent*)event {
    NSPoint documentPoint = NSZeroPoint;
    if ([self documentPointForEvent:event documentPoint:&documentPoint])
        [self.reader minimapViewDidReceiveMagnify:event documentPoint:documentPoint];
}

- (void)mouseUp:(NSEvent*)event {
    (void)event;
    _draggingVisibleRect = NO;
    _dragOffsetFromVisibleCenter = NSZeroPoint;
    _dragOffsetFromVisibleTop = 0.0;
    _dragThumbTop = 0.0;
    _dragLastMouseY = 0.0;
    _dragSmoothedScale = 0.0;
    _dragAccelerationBlend = 0.0;
    _dragLastTimestamp = 0.0;
}

@end

@interface SPDFPrintView : NSView
@property(nonatomic, copy) NSArray<SPDFRenderedPage*>* pages;
@end

@implementation SPDFPrintView

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)knowsPageRange:(NSRangePointer)range {
    range->location = 1;
    range->length = self.pages.count;
    return YES;
}

- (NSRect)rectForPage:(NSInteger)page {
    NSPrintInfo* info = NSPrintOperation.currentOperation.printInfo;
    NSSize paper = info.paperSize;
    return NSMakeRect(0, (page - 1) * paper.height, paper.width, paper.height);
}

- (void)drawRect:(NSRect)dirtyRect {
    NSPrintInfo* info = NSPrintOperation.currentOperation.printInfo;
    NSSize paper = info.paperSize;
    NSInteger pageNumber = MAX(1, (NSInteger)floor(dirtyRect.origin.y / paper.height) + 1);
    NSInteger pageIndex = pageNumber - 1;
    if (pageIndex < 0 || pageIndex >= (NSInteger)self.pages.count) return;

    NSRect pageRect = [self rectForPage:pageNumber];
    [[NSColor whiteColor] setFill];
    NSRectFill(pageRect);

    SPDFRenderedPage* page = self.pages[(NSUInteger)pageIndex];
    if (!page.image) return;

    NSRect imageable = info.imageablePageBounds;
    imageable.origin.x += pageRect.origin.x;
    imageable.origin.y += pageRect.origin.y;
    CGFloat scale = MIN(NSWidth(imageable) / page.image.size.width, NSHeight(imageable) / page.image.size.height);
    NSSize drawSize = NSMakeSize(page.image.size.width * scale, page.image.size.height * scale);
    NSRect drawRect =
        NSMakeRect(imageable.origin.x + (NSWidth(imageable) - drawSize.width) / 2.0,
                   imageable.origin.y + (NSHeight(imageable) - drawSize.height) / 2.0, drawSize.width, drawSize.height);
    [page.image drawInRect:drawRect
                  fromRect:NSZeroRect
                 operation:NSCompositingOperationSourceOver
                  fraction:1.0
            respectFlipped:YES
                     hints:@{NSImageHintInterpolation : @(NSImageInterpolationHigh)}];
}

@end

@implementation SumatraMacDelegate {
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
    NSBox* _ocrSeparator;
    NSButton* _findPrevButton;
    NSButton* _findNextButton;
    NSTextField* _findCountLabel;
    NSView* _toolbarSpacer;
    NSButton* _toolbarOverflowButton;
    NSMenu* _toolbarOverflowMenu;
    NSTextField* _statusLabel;
    NSSegmentedControl* _sidebarModeControl;
    NSPanel* _palettePanel;
    NSSearchField* _paletteSearchField;
    NSButton* _paletteAllDocsCheckbox;
    NSTableView* _paletteTable;
    NSPanel* _ocrInstallPanel;
    NSProgressIndicator* _ocrInstallProgress;
    NSTextView* _ocrInstallLog;
    NSTask* _ocrInstallTask;
    NSPanel* _commentPanel;
    NSTextField* _commentLabel;
    NSMutableArray<NSDictionary*>* _paletteResults;
    NSInteger _paletteMode;
    NSUInteger _paletteSearchGeneration;
    id _paletteEventMonitor;
    NSOperationQueue* _renderQueue;
    NSOperationQueue* _preloadQueue;
    NSOperationQueue* _findQueue;
    NSMutableSet<NSNumber*>* _queuedRenderPages;
    NSTimer* _findFlashTimer;
    NSTimeInterval _findFlashStartTime;

    spdf_document* _doc;
    spdf_outline _outline;
    spdf_comments _comments;
    NSMutableArray<NSDictionary*>* _sidebarItems;
    NSMutableArray<SPDFRenderedPage*>* _renderedPages;
    NSMutableArray<SPDFDocumentTab*>* _tabs;
    NSMutableArray<NSDictionary*>* _favorites;
    NSDictionary* _paletteFavoritePendingDelete;
    NSMutableDictionary<NSNumber*, NSArray<NSValue*>*>* _findHighlights;
    NSMutableArray<NSDictionary*>* _findMatches;
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
    BOOL _sidebarPreferredVisible;
    BOOL _sidebarVisible;
    BOOL _minimapPreferredVisible;
    BOOL _minimapVisible;
    BOOL _presentationMode;
    BOOL _presentationEnteredFullScreen;
    SPDFViewMode _presentationPreviousViewMode;
    SPDFFitMode _presentationPreviousFitMode;
    BOOL _presentationPreviousSidebarPreferredVisible;
    BOOL _presentationPreviousMinimapPreferredVisible;
    BOOL _ocrInstallRunning;
    BOOL _restoringSidebarLayout;
    BOOL _allowSidebarWidthPersistence;
    CGFloat _sidebarWidth;
    CGFloat _minimapWidth;
    NSSize _restoredWindowContentSize;
    NSInteger _pendingFindPreferredPage;
    NSInteger _pendingFindPreferredMatchIndex;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    (void)notification;
    _zoom = 1.0;
    _rememberedCustomZoom = 1.0;
    _fitMode = SPDFFitModeWidth;
    _viewMode = SPDFViewModeContinuous;
    _highlightPageIndex = -1;
    _selectionPageIndex = -1;
    _contextPageIndex = -1;
    _contextCommentIndex = -1;
    _sidebarPreferredVisible = YES;
    _sidebarVisible = YES;
    _minimapPreferredVisible = YES;
    _minimapVisible = YES;
    _presentationMode = NO;
    _presentationEnteredFullScreen = NO;
    _restoringSidebarLayout = NO;
    _allowSidebarWidthPersistence = NO;
    _sidebarWidth = kDefaultSidebarWidth;
    _minimapWidth = kDefaultMinimapWidth;
    _findRegexMultiline = YES;
    _sidebarItems = [NSMutableArray array];
    _renderedPages = [NSMutableArray array];
    _tabs = [NSMutableArray array];
    _favorites = [NSMutableArray array];
    _paletteFavoritePendingDelete = nil;
    _findHighlights = [NSMutableDictionary dictionary];
    _findMatches = [NSMutableArray array];
    _findMatchIndex = -1;
    _paletteResults = [NSMutableArray array];
    _pendingOpenPaths = [NSMutableArray array];
    _queuedRenderPages = [NSMutableSet set];
    _selectedTabIndex = -1;
    _pendingFindPreferredPage = -1;
    _pendingFindPreferredMatchIndex = -1;

    NSInteger cpuCount = MAX(2, NSProcessInfo.processInfo.activeProcessorCount);
    _renderQueue = [[NSOperationQueue alloc] init];
    _renderQueue.name = @"SumatraPDF page renderer";
    _renderQueue.maxConcurrentOperationCount = MIN(2, cpuCount);
    _renderQueue.qualityOfService = NSQualityOfServiceUserInitiated;
    _preloadQueue = [[NSOperationQueue alloc] init];
    _preloadQueue.name = @"SumatraPDF tab preloader";
    _preloadQueue.maxConcurrentOperationCount = MAX(2, cpuCount / 2);
    _preloadQueue.qualityOfService = NSQualityOfServiceUtility;
    _findQueue = [[NSOperationQueue alloc] init];
    _findQueue.name = @"SumatraPDF document find";
    _findQueue.maxConcurrentOperationCount = 1;
    _findQueue.qualityOfService = NSQualityOfServiceUserInitiated;

    [self loadPersistentState];

    [self buildMenu];
    [self buildWindow];
    _uiReady = YES;
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    dispatch_async(dispatch_get_main_queue(), ^{
      self->_allowSidebarWidthPersistence = YES;
      [self restoreSidebarWidth];
    });

    NSMutableArray<NSString*>* startupPaths = [NSMutableArray array];
    if (_pendingOpenPath.length > 0) [startupPaths addObject:_pendingOpenPath];
    for (NSString* path in _pendingOpenPaths) {
        if (path.length > 0 && ![startupPaths containsObject:path]) [startupPaths addObject:path];
    }
    if (self.initialPath.length > 0) [startupPaths addObject:self.initialPath];
    if (startupPaths.count > 0) {
        for (NSString* path in startupPaths) [self openPath:path];
    } else if (_tabs.count > 0) {
        [self selectTabAtIndex:MAX(0, _selectedTabIndex)];
    } else {
        [self showEmptyDocumentViewWithMessage:@"Open a document"];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
    (void)sender;
    return YES;
}

- (void)applicationWillTerminate:(NSNotification*)notification {
    (void)notification;
    [_renderQueue cancelAllOperations];
    [_queuedRenderPages removeAllObjects];
    [_preloadQueue cancelAllOperations];
    [_findQueue cancelAllOperations];
    [self rememberActiveTabState];
    [self savePersistentState];
    spdf_free_outline(&_outline);
    spdf_free_comments(&_comments);
    spdf_close(_doc);
}

- (BOOL)application:(NSApplication*)sender openFile:(NSString*)filename {
    (void)sender;
    if (!_uiReady) {
        if (!_pendingOpenPath.length) _pendingOpenPath = [filename copy];
        if (filename.length && ![_pendingOpenPaths containsObject:filename]) [_pendingOpenPaths addObject:filename];
        return YES;
    }
    [self openPath:filename];
    return YES;
}

- (void)application:(NSApplication*)application openFiles:(NSArray<NSString*>*)filenames {
    (void)application;
    if (filenames.count > 0) {
        if (!_uiReady) {
            _pendingOpenPath = [filenames.firstObject copy];
            [_pendingOpenPaths addObjectsFromArray:filenames];
        } else {
            for (NSString* filename in filenames) [self openPath:filename];
        }
    }
    [NSApp replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

- (void)windowDidResize:(NSNotification*)notification {
    (void)notification;
    [self updateTabStripFrame];
    [self updateToolbarOverflow];
    [self restoreSidebarWidth];
    if (_doc && (_fitMode == SPDFFitModeWidth || _fitMode == SPDFFitModeHeight || _fitMode == SPDFFitModePage))
        [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO];
    else
        [self resizeDocumentView];
    [self savePersistentState];
}

- (void)windowDidChangeBackingProperties:(NSNotification*)notification {
    (void)notification;
    if (_doc)
        [self renderDocumentPreservingScrollPosition];
    else
        [self resizeDocumentView];
}

- (void)windowDidEnterFullScreen:(NSNotification*)notification {
    (void)notification;
    dispatch_async(dispatch_get_main_queue(), ^{
      [self updateTabStripFrame];
      if (self->_presentationMode && self->_doc) [self renderDocumentAndScrollToPage:self->_pageIndex alignTop:YES];
    });
}

- (void)windowDidExitFullScreen:(NSNotification*)notification {
    (void)notification;
    if (_presentationMode && _presentationEnteredFullScreen)
        [self leavePresentationModeAndExitFullScreen:NO sender:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
      [self updateTabStripFrame];
    });
}

- (NSString*)supportDirectory {
    NSURL* base =
        [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask]
            .firstObject;
    NSString* dir = [base.path stringByAppendingPathComponent:@"SumatraPDF"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (NSString*)pathForStateFile:(NSString*)name {
    return [[self supportDirectory] stringByAppendingPathComponent:name];
}

- (id)jsonObjectFromFile:(NSString*)name {
    NSData* data = [NSData dataWithContentsOfFile:[self pathForStateFile:name]];
    if (!data) return nil;
    return [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
}

- (void)writeJSONObject:(id)object toFile:(NSString*)name {
    NSData* data = [NSJSONSerialization dataWithJSONObject:object
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:nil];
    if (data) [data writeToFile:[self pathForStateFile:name] atomically:YES];
}

- (void)loadPersistentState {
    NSDictionary* settings = [self jsonObjectFromFile:@"settings.json"];
    if ([settings isKindOfClass:NSDictionary.class]) {
        NSNumber* fit = settings[@"fitMode"];
        NSNumber* view = settings[@"viewMode"];
        NSNumber* sidebar = settings[@"showSidebar"];
        NSNumber* minimap = settings[@"showMinimap"];
        NSNumber* sidebarWidth = settings[@"sidebarWidth"];
        NSNumber* minimapWidth = settings[@"minimapWidth"];
        NSDictionary* windowSize = settings[@"windowSize"];
        NSString* commentAuthor = settings[@"commentAuthor"];
        if (fit) _fitMode = (SPDFFitMode)MAX(0, MIN(4, fit.integerValue));
        if (view) _viewMode = (SPDFViewMode)MAX(0, MIN(1, view.integerValue));
        if (sidebar) _sidebarPreferredVisible = sidebar.boolValue;
        if (minimap) _minimapPreferredVisible = minimap.boolValue;
        if (sidebarWidth) _sidebarWidth = spdf_sane_sidebar_width(sidebarWidth.doubleValue, 0);
        if (minimapWidth) _minimapWidth = spdf_clamp_cg(minimapWidth.doubleValue, 72.0, 260.0);
        if ([windowSize isKindOfClass:NSDictionary.class]) {
            _restoredWindowContentSize = spdf_sane_window_content_size(
                NSMakeSize([windowSize[@"width"] doubleValue], [windowSize[@"height"] doubleValue]),
                NSScreen.mainScreen);
        }
        if ([commentAuthor isKindOfClass:NSString.class]) _commentAuthor = [commentAuthor copy];
    }

    NSArray* favorites = [self jsonObjectFromFile:@"favorites.json"];
    if ([favorites isKindOfClass:NSArray.class]) [_favorites addObjectsFromArray:favorites];

    NSDictionary* session = [self jsonObjectFromFile:@"session.json"];
    NSArray* tabs = [session isKindOfClass:NSDictionary.class] ? session[@"tabs"] : nil;
    if ([tabs isKindOfClass:NSArray.class]) {
        for (NSDictionary* item in tabs) {
            if (![item isKindOfClass:NSDictionary.class]) continue;
            NSString* path = item[@"path"];
            if (![path isKindOfClass:NSString.class] || path.length == 0) continue;
            SPDFDocumentTab* tab = [[SPDFDocumentTab alloc] init];
            tab.path = path;
            tab.title = spdf_display_name_for_path(path);
            tab.pageIndex = [item[@"page"] integerValue];
            tab.zoom = [item[@"zoom"] doubleValue] > 0 ? [item[@"zoom"] doubleValue] : 1.0;
            tab.customZoom = [item[@"customZoom"] doubleValue] > 0 ? [item[@"customZoom"] doubleValue] : tab.zoom;
            tab.fitMode = (SPDFFitMode)MAX(0, MIN(4, [item[@"fitMode"] integerValue]));
            tab.viewMode = (SPDFViewMode)MAX(0, MIN(1, [item[@"viewMode"] integerValue]));
            tab.scrollOrigin = NSMakePoint([item[@"scrollX"] doubleValue], [item[@"scrollY"] doubleValue]);
            tab.hasScrollOrigin = item[@"scrollX"] != nil || item[@"scrollY"] != nil;
            if ([item[@"searchText"] isKindOfClass:NSString.class]) tab.searchText = item[@"searchText"];
            tab.searchRegex = item[@"searchRegex"] ? [item[@"searchRegex"] boolValue] : NO;
            tab.searchRegexMultiline = item[@"searchRegexMultiline"] ? [item[@"searchRegexMultiline"] boolValue] : YES;
            tab.findMatchIndex = item[@"findMatchIndex"] ? [item[@"findMatchIndex"] integerValue] : -1;
            [_tabs addObject:tab];
        }
        _selectedTabIndex = MIN(MAX(0, [session[@"selectedTab"] integerValue]), MAX(0, (NSInteger)_tabs.count - 1));
    }
}

- (void)savePersistentState {
    NSSize windowContentSize = _restoredWindowContentSize;
    if (_window && !_window.miniaturized && !_presentationMode && !(_window.styleMask & NSWindowStyleMaskFullScreen)) {
        windowContentSize = [_window contentRectForFrameRect:_window.frame].size;
        _restoredWindowContentSize = windowContentSize;
    }
    windowContentSize = spdf_sane_window_content_size(windowContentSize, _window.screen ?: NSScreen.mainScreen);

    NSMutableArray* tabs = [NSMutableArray array];
    for (SPDFDocumentTab* tab in _tabs) {
        if (!tab.path.length) continue;
        [tabs addObject:@{
            @"path" : tab.path,
            @"title" : spdf_display_name_for_path(tab.path),
            @"page" : @(tab.pageIndex),
            @"zoom" : @(tab.zoom),
            @"customZoom" : @(tab.customZoom),
            @"fitMode" : @(tab.fitMode),
            @"viewMode" : @(tab.viewMode),
            @"scrollX" : @(tab.scrollOrigin.x),
            @"scrollY" : @(tab.scrollOrigin.y),
            @"hasScrollOrigin" : @(tab.hasScrollOrigin),
            @"searchText" : tab.searchText ?: @"",
            @"searchRegex" : @(tab.searchRegex),
            @"searchRegexMultiline" : @(tab.searchRegexMultiline),
            @"findMatchIndex" : @(tab.findMatchIndex)
        }];
    }
    [self writeJSONObject:@{@"version" : @1, @"selectedTab" : @(MAX(0, _selectedTabIndex)), @"tabs" : tabs}
                   toFile:@"session.json"];
    CGFloat sidebarWidth = spdf_sane_sidebar_width(_sidebarWidth, _splitView ? NSWidth(_splitView.bounds) : 0);
    [self writeJSONObject:@{
        @"version" : @1,
        @"fitMode" : @(_fitMode),
        @"viewMode" : @(_viewMode),
        @"showSidebar" : @(_sidebarPreferredVisible),
        @"showMinimap" : @(_minimapPreferredVisible),
        @"sidebarWidth" : @(sidebarWidth),
        @"minimapWidth" : @(_minimapWidth),
        @"windowSize" : @{@"width" : @(windowContentSize.width), @"height" : @(windowContentSize.height)},
        @"commentAuthor" : _commentAuthor ?: @""
    }
                   toFile:@"settings.json"];
    [self writeJSONObject:_favorites toFile:@"favorites.json"];
}

- (void)buildMenu {
    NSMenu* mainMenu = [[NSMenu alloc] initWithTitle:@""];

    NSMenuItem* appItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    [mainMenu addItem:appItem];
    NSMenu* appMenu = [[NSMenu alloc] initWithTitle:@"SumatraPDF"];
    [appMenu addItemWithTitle:@"About SumatraPDF" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit SumatraPDF" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;

    NSMenuItem* fileItem = [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
    [mainMenu addItem:fileItem];
    NSMenu* fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"Open..." action:@selector(openDocument:) keyEquivalent:@"o"];
    [fileMenu addItemWithTitle:@"Open in Adobe Acrobat Reader"
                        action:@selector(openInExternalReader:)
                 keyEquivalent:@""];
    [fileMenu addItemWithTitle:@"Show in Folder" action:@selector(showInFolder:) keyEquivalent:@""];
    [fileMenu addItemWithTitle:@"Close" action:@selector(closeDocument:) keyEquivalent:@"w"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Print..." action:@selector(printDocument:) keyEquivalent:@"p"];
    [fileMenu addItemWithTitle:@"OCR Document..." action:@selector(ocrDocument:) keyEquivalent:@""];
    [fileMenu addItemWithTitle:@"Properties..." action:@selector(showProperties:) keyEquivalent:@""];
    fileItem.submenu = fileMenu;

    NSMenuItem* goItem = [[NSMenuItem alloc] initWithTitle:@"Go To" action:nil keyEquivalent:@""];
    [mainMenu addItem:goItem];
    NSMenu* goMenu = [[NSMenu alloc] initWithTitle:@"Go To"];
    [goMenu addItemWithTitle:@"First Page"
                      action:@selector(firstPage:)
               keyEquivalent:[NSString stringWithFormat:@"%C", static_cast<unichar>(NSHomeFunctionKey)]];
    [goMenu addItemWithTitle:@"Previous Page" action:@selector(previousPage:) keyEquivalent:@"["];
    [goMenu addItemWithTitle:@"Next Page" action:@selector(nextPage:) keyEquivalent:@"]"];
    [goMenu addItemWithTitle:@"Last Page"
                      action:@selector(lastPage:)
               keyEquivalent:[NSString stringWithFormat:@"%C", static_cast<unichar>(NSEndFunctionKey)]];
    [goMenu addItem:[NSMenuItem separatorItem]];
    [goMenu addItemWithTitle:@"Go To Page..." action:@selector(focusPageField:) keyEquivalent:@"l"];
    goItem.submenu = goMenu;

    NSMenuItem* zoomItem = [[NSMenuItem alloc] initWithTitle:@"Zoom" action:nil keyEquivalent:@""];
    [mainMenu addItem:zoomItem];
    NSMenu* zoomMenu = [[NSMenu alloc] initWithTitle:@"Zoom"];
    [zoomMenu addItemWithTitle:@"Zoom In" action:@selector(zoomIn:) keyEquivalent:@"+"];
    [zoomMenu addItemWithTitle:@"Zoom Out" action:@selector(zoomOut:) keyEquivalent:@"-"];
    [zoomMenu addItemWithTitle:@"100%" action:@selector(actualSize:) keyEquivalent:@"0"];
    [zoomMenu addItem:[NSMenuItem separatorItem]];
    [zoomMenu addItemWithTitle:@"Fit Page" action:@selector(fitPage:) keyEquivalent:@"9"];
    [zoomMenu addItemWithTitle:@"Fit Width" action:@selector(fitWidth:) keyEquivalent:@"1"];
    [zoomMenu addItemWithTitle:@"Fit Height" action:@selector(fitHeight:) keyEquivalent:@"2"];
    zoomItem.submenu = zoomMenu;

    NSMenuItem* viewItem = [[NSMenuItem alloc] initWithTitle:@"View" action:nil keyEquivalent:@""];
    [mainMenu addItem:viewItem];
    NSMenu* viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    [viewMenu addItemWithTitle:@"Single Page" action:@selector(setSinglePageMode:) keyEquivalent:@"4"];
    [viewMenu addItemWithTitle:@"Continuous" action:@selector(setContinuousMode:) keyEquivalent:@"5"];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* sidePanelItem =
        [viewMenu addItemWithTitle:@"Show Side Panel" action:@selector(toggleSidebar:) keyEquivalent:@""];
    sidePanelItem.target = self;
    NSMenuItem* minimapItem =
        [viewMenu addItemWithTitle:@"Show Minimap" action:@selector(toggleMinimap:) keyEquivalent:@""];
    minimapItem.target = self;
    NSMenuItem* presentation =
        [viewMenu addItemWithTitle:@"Presentation Mode"
                            action:@selector(togglePresentation:)
                     keyEquivalent:[NSString stringWithFormat:@"%C", static_cast<unichar>(NSF5FunctionKey)]];
    presentation.target = self;
    presentation.keyEquivalentModifierMask = 0;
    NSMenuItem* fullScreen =
        [viewMenu addItemWithTitle:@"Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"f"];
    fullScreen.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"Rotate Left" action:@selector(unimplementedMenuItem:) keyEquivalent:@""];
    [viewMenu addItemWithTitle:@"Rotate Right" action:@selector(unimplementedMenuItem:) keyEquivalent:@""];
    viewItem.submenu = viewMenu;

    NSMenuItem* editItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
    [mainMenu addItem:editItem];
    NSMenu* editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Copy Selected Document Text" action:@selector(copySelection:) keyEquivalent:@""];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Find" action:@selector(focusFind:) keyEquivalent:@"f"];
    [editMenu addItemWithTitle:@"Find Next" action:@selector(findNext:) keyEquivalent:@"g"];
    NSMenuItem* prevFind =
        [editMenu addItemWithTitle:@"Find Previous" action:@selector(findPrevious:) keyEquivalent:@"G"];
    prevFind.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Regex Multiline" action:@selector(toggleFindRegexMultiline:) keyEquivalent:@""];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Set Author for Comments..." action:@selector(setCommentAuthor:) keyEquivalent:@""];
    editItem.submenu = editMenu;

    NSMenuItem* favoritesItem = [[NSMenuItem alloc] initWithTitle:@"Favorites" action:nil keyEquivalent:@""];
    [mainMenu addItem:favoritesItem];
    NSMenu* favoritesMenu = [[NSMenu alloc] initWithTitle:@"Favorites"];
    [favoritesMenu addItemWithTitle:@"Search Favorites..." action:@selector(showFavoritesPalette:) keyEquivalent:@"k"];
    [favoritesMenu addItem:[NSMenuItem separatorItem]];
    [favoritesMenu addItemWithTitle:@"Favorite Current Page" action:@selector(favoriteCurrentPage:) keyEquivalent:@"b"];
    NSMenuItem* docFav = [favoritesMenu addItemWithTitle:@"Favorite Current Document"
                                                  action:@selector(favoriteCurrentDocument:)
                                           keyEquivalent:@"B"];
    docFav.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [favoritesMenu addItemWithTitle:@"Manage Favorites..." action:@selector(showFavoritesPalette:) keyEquivalent:@""];
    favoritesItem.submenu = favoritesMenu;

    NSMenuItem* settingsItem = [[NSMenuItem alloc] initWithTitle:@"Settings" action:nil keyEquivalent:@""];
    [mainMenu addItem:settingsItem];
    NSMenu* settingsMenu = [[NSMenu alloc] initWithTitle:@"Settings"];
    [settingsMenu addItemWithTitle:@"Options..." action:@selector(unimplementedMenuItem:) keyEquivalent:@","];
    [settingsMenu addItemWithTitle:@"Advanced Options..." action:@selector(unimplementedMenuItem:) keyEquivalent:@""];
    settingsItem.submenu = settingsMenu;

    NSApp.mainMenu = mainMenu;
}

- (NSButton*)buttonWithTitle:(NSString*)title action:(SEL)action {
    NSButton* button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleTexturedRounded;
    NSFont* font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightLight];
    button.font = font;
    button.cell.font = font;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                     forOrientation:NSLayoutConstraintOrientationHorizontal];
    return button;
}

- (void)styleToolbarTextButton:(NSButton*)button {
    NSFont* font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightLight];
    NSMutableParagraphStyle* style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    button.font = font;
    button.cell.font = font;
    button.cell.wraps = NO;
    button.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    button.attributedTitle = [[NSAttributedString alloc] initWithString:button.title
                                                             attributes:@{
                                                                 NSFontAttributeName : font,
                                                                 NSForegroundColorAttributeName : NSColor.labelColor,
                                                                 NSParagraphStyleAttributeName : style,
                                                             }];
}

- (void)styleToolbarPanelButton:(NSButton*)button
                          title:(NSString*)title
                         active:(BOOL)active
                        tooltip:(NSString*)tooltip {
    button.state = NSControlStateValueOff;
    button.title = title;
    if ([button isKindOfClass:SPDFToolbarToggleButton.class]) ((SPDFToolbarToggleButton*)button).active = active;
    button.toolTip = tooltip;
}

- (void)addOverflowItemWithTitle:(NSString*)title
                          action:(SEL)action
                            menu:(NSMenu*)menu
                           state:(NSControlStateValue)state
                         enabled:(BOOL)enabled {
    NSMenuItem* item = [menu addItemWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    item.state = state;
    item.enabled = enabled;
}

- (void)rebuildToolbarOverflowMenuWithHiddenViews:(NSSet<NSView*>*)hiddenViews {
    NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Toolbar"];
    BOOL hasDoc = _doc != NULL;
    if ([hiddenViews containsObject:_ocrButton])
        [self addOverflowItemWithTitle:@"OCR Document..."
                                action:@selector(ocrDocument:)
                                  menu:menu
                                 state:NSControlStateValueOff
                               enabled:hasDoc && [_path.pathExtension.lowercaseString isEqualToString:@"pdf"]];
    if ([hiddenViews containsObject:_findRegexCheckbox])
        [self addOverflowItemWithTitle:@"Regex"
                                action:@selector(toggleFindRegex:)
                                  menu:menu
                                 state:_findRegexCheckbox.state
                               enabled:hasDoc];
    if ([hiddenViews containsObject:_findCountLabel] && _findCountLabel.stringValue.length > 0) {
        NSMenuItem* countItem = [menu addItemWithTitle:_findCountLabel.stringValue action:nil keyEquivalent:@""];
        countItem.enabled = NO;
    }
    if ([hiddenViews containsObject:_findPrevButton])
        [self addOverflowItemWithTitle:@"Find Previous"
                                action:@selector(findPrevious:)
                                  menu:menu
                                 state:NSControlStateValueOff
                               enabled:_findPrevButton.enabled];
    if ([hiddenViews containsObject:_findNextButton])
        [self addOverflowItemWithTitle:@"Find Next"
                                action:@selector(findNext:)
                                  menu:menu
                                 state:NSControlStateValueOff
                               enabled:_findNextButton.enabled];
    if ([hiddenViews containsObject:_continuousButton])
        [self addOverflowItemWithTitle:@"Continuous"
                                action:@selector(toggleContinuous:)
                                  menu:menu
                                 state:_continuousButton.state
                               enabled:hasDoc];
    if ([hiddenViews containsObject:_fitModePopup]) {
        [menu addItem:[NSMenuItem separatorItem]];
        [self addOverflowItemWithTitle:@"Actual Size"
                                action:@selector(actualSize:)
                                  menu:menu
                                 state:_fitMode == SPDFFitModeActual ? NSControlStateValueOn : NSControlStateValueOff
                               enabled:hasDoc];
        [self addOverflowItemWithTitle:@"Fit Width"
                                action:@selector(fitWidth:)
                                  menu:menu
                                 state:_fitMode == SPDFFitModeWidth ? NSControlStateValueOn : NSControlStateValueOff
                               enabled:hasDoc];
        [self addOverflowItemWithTitle:@"Fit Height"
                                action:@selector(fitHeight:)
                                  menu:menu
                                 state:_fitMode == SPDFFitModeHeight ? NSControlStateValueOn : NSControlStateValueOff
                               enabled:hasDoc];
        [self addOverflowItemWithTitle:@"Fit Page"
                                action:@selector(fitPage:)
                                  menu:menu
                                 state:_fitMode == SPDFFitModePage ? NSControlStateValueOn : NSControlStateValueOff
                               enabled:hasDoc];
    }
    _toolbarOverflowMenu = menu;
    _toolbarOverflowButton.enabled = menu.numberOfItems > 0;
}

- (void)showToolbarOverflowMenu:(id)sender {
    (void)sender;
    if (_toolbarOverflowMenu.numberOfItems == 0) return;
    NSEvent* event = NSApp.currentEvent;
    NSPoint point = NSMakePoint(0.0, NSHeight(_toolbarOverflowButton.bounds) + 2.0);
    if (event && event.window == _window)
        [NSMenu popUpContextMenu:_toolbarOverflowMenu withEvent:event forView:_toolbarOverflowButton];
    else
        [_toolbarOverflowMenu popUpMenuPositioningItem:nil atLocation:point inView:_toolbarOverflowButton];
}

- (void)updateToolbarOverflow {
    if (!_toolbar || !_toolbarOverflowButton) return;
    NSArray<NSArray<NSView*>*>* groups = @[
        @[ _ocrButton, _ocrSeparator ],
        @[ _findCountLabel ],
        @[ _findPrevButton, _findNextButton ],
        @[ _findRegexCheckbox ],
        @[ _continuousButton ],
        @[ _fitModePopup ],
        @[ _zoomOutButton, _zoomInButton ],
    ];
    NSMutableSet<NSView*>* hiddenViews = [NSMutableSet set];
    for (NSArray<NSView*>* group in groups)
        for (NSView* view in group) view.hidden = NO;
    BOOL hasQuery = _searchField.stringValue.length > 0;
    _findCountLabel.hidden = !hasQuery;
    _findPrevButton.hidden = !hasQuery;
    _findNextButton.hidden = !hasQuery;
    _toolbarOverflowButton.hidden = YES;
    [_toolbar layoutSubtreeIfNeeded];

    CGFloat availableWidth = NSWidth(_toolbar.bounds);
    for (NSArray<NSView*>* group in groups) {
        BOOL hasVisibleView = NO;
        for (NSView* view in group) {
            if (!view.hidden) {
                hasVisibleView = YES;
                break;
            }
        }
        if (!hasVisibleView) continue;
        if (availableWidth <= 0 || _toolbar.fittingSize.width <= availableWidth) break;
        _toolbarOverflowButton.hidden = NO;
        for (NSView* view in group) {
            view.hidden = YES;
            [hiddenViews addObject:view];
        }
        [_toolbar layoutSubtreeIfNeeded];
    }
    _toolbarOverflowButton.hidden = hiddenViews.count == 0;
    [self rebuildToolbarOverflowMenuWithHiddenViews:hiddenViews];
}

- (void)buildWindow {
    NSScreen* screen = NSScreen.mainScreen;
    NSSize restoredSize = spdf_sane_window_content_size(_restoredWindowContentSize, screen);
    NSSize contentSize = NSEqualSizes(restoredSize, NSZeroSize) ? NSMakeSize(1120, 800) : restoredSize;
    _restoredWindowContentSize = contentSize;
    NSRect visibleFrame = screen.visibleFrame;
    NSRect frame =
        NSMakeRect(floor(NSMidX(visibleFrame) - contentSize.width / 2.0),
                   floor(NSMidY(visibleFrame) - contentSize.height / 2.0), contentSize.width, contentSize.height);
    _window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                    NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.delegate = self;
    _window.title = @"SumatraPDF";
    _window.minSize = NSMakeSize(kMinWindowWidth, kMinWindowHeight);
    _window.titleVisibility = NSWindowTitleHidden;
    _window.titlebarAppearsTransparent = YES;
    _window.styleMask |= NSWindowStyleMaskFullSizeContentView;

    SPDFDropView* content = [[SPDFDropView alloc] initWithFrame:frame];
    content.reader = self;
    [content registerForDraggedTypes:@[ NSPasteboardTypeFileURL ]];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    _window.contentView = content;

    _tabStrip = [[SPDFTabStripView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(frame), kTabStripHeight)];
    _tabStrip.reader = self;
    _tabStrip.tabs = _tabs;
    _tabStrip.selectedIndex = _selectedTabIndex;
    _tabStrip.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_tabStrip];
    [self updateTabStripFrame];

    _toolbar = [[SPDFToolbarStackView alloc] init];
    _toolbar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _toolbar.alignment = NSLayoutAttributeCenterY;
    _toolbar.spacing = 4.0;
    _toolbar.edgeInsets = NSEdgeInsetsMake(7, 6, 7, 6);
    _toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_toolbar];

    _prevButton = [self buttonWithTitle:@"<" action:@selector(previousPage:)];
    _nextButton = [self buttonWithTitle:@">" action:@selector(nextPage:)];
    _sidebarToggleButton =
        [[SPDFToolbarToggleButton alloc] initWithTitle:@"Side Panel" target:self action:@selector(toggleSidebar:)];
    _sidebarToggleButton.toolTip = @"Show or hide the side panel";
    _pageField = [[NSTextField alloc] init];
    _pageField.translatesAutoresizingMaskIntoConstraints = NO;
    _pageField.alignment = NSTextAlignmentRight;
    _pageField.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
    _pageField.delegate = self;
    _pageField.target = self;
    _pageField.action = @selector(pageFieldChanged:);
    [_pageField.widthAnchor constraintEqualToConstant:50].active = YES;
    _pageCountLabel = [NSTextField labelWithString:@"/ 0"];
    _pageCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _zoomOutButton = [self buttonWithTitle:@"-" action:@selector(zoomOut:)];
    _zoomInButton = [self buttonWithTitle:@"+" action:@selector(zoomIn:)];

    _fitModePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_fitModePopup addItemsWithTitles:@[ @"100%", @"100%", @"Fit Width", @"Fit Height", @"Fit Page" ]];
    _fitModePopup.target = self;
    _fitModePopup.action = @selector(fitModePopupChanged:);
    _fitModePopup.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightLight];
    _fitModePopup.cell.font = _fitModePopup.font;
    _fitModePopup.translatesAutoresizingMaskIntoConstraints = NO;
    [_fitModePopup.widthAnchor constraintEqualToConstant:96].active = YES;
    [_fitModePopup setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                            forOrientation:NSLayoutConstraintOrientationHorizontal];

    _continuousButton = [NSButton checkboxWithTitle:@"Continuous" target:self action:@selector(toggleContinuous:)];
    [self styleToolbarTextButton:_continuousButton];
    _continuousButton.toolTip = @"Continuous scrolling";
    _continuousButton.translatesAutoresizingMaskIntoConstraints = NO;
    _continuousButton.state = NSControlStateValueOn;
    [_continuousButton.widthAnchor constraintEqualToConstant:104].active = YES;
    [_continuousButton setContentHuggingPriority:NSLayoutPriorityRequired
                                  forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_continuousButton setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                                forOrientation:NSLayoutConstraintOrientationHorizontal];

    _searchField = [[NSSearchField alloc] init];
    _searchField.placeholderString = @"Find";
    _searchField.translatesAutoresizingMaskIntoConstraints = NO;
    _searchField.delegate = self;
    _searchField.target = nil;
    _searchField.action = NULL;
    [_searchField.widthAnchor constraintGreaterThanOrEqualToConstant:88].active = YES;
    [_searchField.widthAnchor constraintLessThanOrEqualToConstant:141].active = YES;
    [_searchField setContentHuggingPriority:NSLayoutPriorityDefaultLow - 1
                             forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_searchField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    _findRegexCheckbox = [NSButton checkboxWithTitle:@"Regex" target:self action:@selector(toggleFindRegex:)];
    [self styleToolbarTextButton:_findRegexCheckbox];
    _findRegexCheckbox.translatesAutoresizingMaskIntoConstraints = NO;
    [_findRegexCheckbox.widthAnchor constraintEqualToConstant:68].active = YES;
    [_findRegexCheckbox setContentHuggingPriority:NSLayoutPriorityRequired
                                   forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_findRegexCheckbox setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                                 forOrientation:NSLayoutConstraintOrientationHorizontal];
    _ocrButton = [self buttonWithTitle:@"OCR" action:@selector(ocrDocument:)];
    _findPrevButton = [self buttonWithTitle:@"<" action:@selector(findPrevious:)];
    _findNextButton = [self buttonWithTitle:@">" action:@selector(findNext:)];
    _minimapToggleButton =
        [[SPDFToolbarToggleButton alloc] initWithTitle:@"Map" target:self action:@selector(toggleMinimap:)];
    _minimapToggleButton.toolTip = @"Show or hide the minimap";
    _findCountLabel = [NSTextField labelWithString:@""];
    _findCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _findCountLabel.alignment = NSTextAlignmentCenter;
    _findCountLabel.textColor = NSColor.secondaryLabelColor;
    _findCountLabel.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    [_findPrevButton.widthAnchor constraintEqualToConstant:30].active = YES;
    [_findNextButton.widthAnchor constraintEqualToConstant:30].active = YES;
    [_findCountLabel.widthAnchor constraintEqualToConstant:64].active = YES;

    _ocrSeparator = [[NSBox alloc] init];
    _ocrSeparator.boxType = NSBoxSeparator;
    _ocrSeparator.translatesAutoresizingMaskIntoConstraints = NO;
    [_ocrSeparator.widthAnchor constraintEqualToConstant:1].active = YES;

    _toolbarOverflowButton = [[SPDFToolbarMenuButton alloc] initWithFrame:NSZeroRect];
    _toolbarOverflowButton.target = self;
    _toolbarOverflowButton.action = @selector(showToolbarOverflowMenu:);
    _toolbarOverflowButton.toolTip = @"More toolbar actions";
    [_toolbarOverflowButton.widthAnchor constraintEqualToConstant:30].active = YES;
    _toolbarSpacer = [[NSView alloc] initWithFrame:NSZeroRect];
    _toolbarSpacer.translatesAutoresizingMaskIntoConstraints = NO;
    [_toolbarSpacer setContentHuggingPriority:NSLayoutPriorityDefaultLow + 1
                               forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_toolbarSpacer setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                             forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_toolbarSpacer.widthAnchor constraintGreaterThanOrEqualToConstant:0.0].active = YES;

    [_toolbar addArrangedSubview:_sidebarToggleButton];
    [_toolbar addArrangedSubview:_ocrButton];
    [_toolbar addArrangedSubview:_ocrSeparator];
    [_toolbar addArrangedSubview:_prevButton];
    [_toolbar addArrangedSubview:_nextButton];
    [_toolbar addArrangedSubview:_pageField];
    [_toolbar addArrangedSubview:_pageCountLabel];
    [_toolbar addArrangedSubview:_zoomOutButton];
    [_toolbar addArrangedSubview:_zoomInButton];
    [_toolbar addArrangedSubview:_fitModePopup];
    [_toolbar addArrangedSubview:_continuousButton];
    [_toolbar addArrangedSubview:_searchField];
    [_toolbar addArrangedSubview:_findRegexCheckbox];
    [_toolbar addArrangedSubview:_findCountLabel];
    [_toolbar addArrangedSubview:_findPrevButton];
    [_toolbar addArrangedSubview:_findNextButton];
    [_toolbar addArrangedSubview:_toolbarSpacer];
    [_toolbar addArrangedSubview:_toolbarOverflowButton];
    [_toolbar addArrangedSubview:_minimapToggleButton];
    [_toolbar setCustomSpacing:8.0 afterView:_continuousButton];
    [_toolbar setCustomSpacing:8.0 afterView:_searchField];

    _splitView = [[NSSplitView alloc] init];
    _splitView.vertical = YES;
    _splitView.dividerStyle = NSSplitViewDividerStyleThin;
    _splitView.delegate = self;
    _splitView.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_splitView];

    _sidebarContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 600)];
    _sidebarContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _sidebarModeControl = [[NSSegmentedControl alloc] init];
    _sidebarModeControl.segmentCount = 2;
    [_sidebarModeControl setLabel:@"Chapters" forSegment:SPDFSidebarModeChapters];
    [_sidebarModeControl setLabel:@"Comments" forSegment:SPDFSidebarModeComments];
    _sidebarModeControl.selectedSegment = SPDFSidebarModeChapters;
    _sidebarModeControl.target = self;
    _sidebarModeControl.action = @selector(sidebarModeChanged:);
    _sidebarModeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [_sidebarContainer addSubview:_sidebarModeControl];

    NSScrollView* sidebarScroll = [[NSScrollView alloc] init];
    sidebarScroll.hasVerticalScroller = YES;
    sidebarScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [_sidebarContainer addSubview:sidebarScroll];

    _sidebarTable = [[SPDFSidebarTableView alloc] init];
    ((SPDFSidebarTableView*)_sidebarTable).reader = self;
    _sidebarTable.headerView = nil;
    _sidebarTable.rowHeight = 25.0;
    _sidebarTable.dataSource = self;
    _sidebarTable.delegate = self;
    _sidebarTable.target = self;
    _sidebarTable.action = @selector(activateSidebarRow:);
    _sidebarTable.doubleAction = @selector(activateSidebarRow:);
    NSMenu* sidebarMenu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem* sidebarEditComment =
        [sidebarMenu addItemWithTitle:@"Edit Comment..." action:@selector(editComment:) keyEquivalent:@""];
    sidebarEditComment.target = self;
    NSMenuItem* sidebarDeleteComment =
        [sidebarMenu addItemWithTitle:@"Delete Comment..." action:@selector(deleteComment:) keyEquivalent:@""];
    sidebarDeleteComment.target = self;
    _sidebarTable.menu = sidebarMenu;
    NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"title"];
    column.title = @"Title";
    column.width = 230.0;
    [_sidebarTable addTableColumn:column];
    sidebarScroll.documentView = _sidebarTable;

    [NSLayoutConstraint activateConstraints:@[
        [_sidebarModeControl.topAnchor constraintEqualToAnchor:_sidebarContainer.topAnchor constant:8],
        [_sidebarModeControl.leadingAnchor constraintEqualToAnchor:_sidebarContainer.leadingAnchor constant:8],
        [_sidebarModeControl.trailingAnchor constraintEqualToAnchor:_sidebarContainer.trailingAnchor constant:-8],
        [sidebarScroll.topAnchor constraintEqualToAnchor:_sidebarModeControl.bottomAnchor constant:8],
        [sidebarScroll.leadingAnchor constraintEqualToAnchor:_sidebarContainer.leadingAnchor],
        [sidebarScroll.trailingAnchor constraintEqualToAnchor:_sidebarContainer.trailingAnchor],
        [sidebarScroll.bottomAnchor constraintEqualToAnchor:_sidebarContainer.bottomAnchor]
    ]];

    _pageScrollView = [[SPDFScrollView alloc] init];
    _pageScrollView.reader = self;
    _markerScroller = [[SPDFFindMarkerScroller alloc] initWithFrame:NSZeroRect];
    _markerScroller.reader = self;
    _pageScrollView.verticalScroller = _markerScroller;
    _pageScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _pageScrollView.hasVerticalScroller = !_presentationMode;
    _pageScrollView.hasHorizontalScroller = NO;
    _pageScrollView.autohidesScrollers = NO;
    _pageScrollView.borderType = NSNoBorder;
    _pageScrollView.drawsBackground = YES;
    _pageScrollView.backgroundColor = NSColor.windowBackgroundColor;
    _pageScrollView.contentView.drawsBackground = YES;
    _pageScrollView.contentView.backgroundColor = NSColor.windowBackgroundColor;
    _pageScrollView.contentView.postsBoundsChangedNotifications = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(clipViewBoundsChanged:)
                                                 name:NSViewBoundsDidChangeNotification
                                               object:_pageScrollView.contentView];

    _pageView = [self newDocumentView];
    _pageScrollView.documentView = _pageView;

    _documentContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    _documentContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [_documentContainer addSubview:_pageScrollView];

    _minimapDividerView = [[SPDFMinimapDividerView alloc] init];
    _minimapDividerView.translatesAutoresizingMaskIntoConstraints = NO;
    _minimapDividerView.reader = self;
    [_documentContainer addSubview:_minimapDividerView];

    _minimapView = [[SPDFMinimapView alloc] init];
    _minimapView.translatesAutoresizingMaskIntoConstraints = NO;
    _minimapView.reader = self;
    _minimapView.wantsLayer = YES;
    [_documentContainer addSubview:_minimapView];
    _minimapWidthConstraint = [_minimapView.widthAnchor constraintEqualToConstant:_minimapWidth];
    _minimapDividerWidthConstraint = [_minimapDividerView.widthAnchor constraintEqualToConstant:kMinimapDividerWidth];
    _pageScrollToMinimapConstraint =
        [_pageScrollView.trailingAnchor constraintEqualToAnchor:_minimapDividerView.leadingAnchor];
    _pageScrollFullWidthConstraint =
        [_pageScrollView.trailingAnchor constraintEqualToAnchor:_documentContainer.trailingAnchor];
    _pageScrollFullWidthConstraint.active = NO;

    [NSLayoutConstraint activateConstraints:@[
        [_pageScrollView.topAnchor constraintEqualToAnchor:_documentContainer.topAnchor],
        [_pageScrollView.leadingAnchor constraintEqualToAnchor:_documentContainer.leadingAnchor],
        [_pageScrollView.bottomAnchor constraintEqualToAnchor:_documentContainer.bottomAnchor],
        _pageScrollToMinimapConstraint,
        [_minimapDividerView.topAnchor constraintEqualToAnchor:_documentContainer.topAnchor],
        [_minimapDividerView.bottomAnchor constraintEqualToAnchor:_documentContainer.bottomAnchor],
        [_minimapDividerView.trailingAnchor constraintEqualToAnchor:_minimapView.leadingAnchor],
        _minimapDividerWidthConstraint, [_minimapView.topAnchor constraintEqualToAnchor:_documentContainer.topAnchor],
        [_minimapView.trailingAnchor constraintEqualToAnchor:_documentContainer.trailingAnchor],
        [_minimapView.bottomAnchor constraintEqualToAnchor:_documentContainer.bottomAnchor], _minimapWidthConstraint
    ]];

    [_splitView addSubview:_sidebarContainer];
    [_splitView addSubview:_documentContainer];

    _statusLabel = [NSTextField labelWithString:@"Ready"];
    _statusLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    _tabStripHeightConstraint = [_tabStrip.heightAnchor constraintEqualToConstant:kTabStripHeight];
    _toolbarHeightConstraint = [_toolbar.heightAnchor constraintEqualToConstant:42.0];
    [NSLayoutConstraint activateConstraints:@[
        [_tabStrip.topAnchor constraintEqualToAnchor:content.topAnchor],
        [_tabStrip.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [_tabStrip.trailingAnchor constraintEqualToAnchor:content.trailingAnchor], _tabStripHeightConstraint,
        [_toolbar.topAnchor constraintEqualToAnchor:_tabStrip.bottomAnchor],
        [_toolbar.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [_toolbar.trailingAnchor constraintEqualToAnchor:content.trailingAnchor], _toolbarHeightConstraint,
        [_splitView.topAnchor constraintEqualToAnchor:_toolbar.bottomAnchor],
        [_splitView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [_splitView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [_splitView.bottomAnchor constraintEqualToAnchor:content.bottomAnchor]
    ]];

    [self restoreSidebarWidth];
    if (!_sidebarPreferredVisible) [self setSidebarActuallyVisible:NO];
    [self setMinimapActuallyVisible:_minimapPreferredVisible];
    [self syncToolbarState];
    [self updateControls];
    [self updateToolbarOverflow];
}

- (CGFloat)backingScale {
    CGFloat scale = _window.backingScaleFactor;
    if (scale <= 0) scale = NSScreen.mainScreen.backingScaleFactor;
    return scale > 0 ? scale : 1.0;
}

- (NSSize)documentClipSizeForLayout {
    NSSize size = _pageScrollView.contentSize;
    if (size.width <= 1.0 || size.height <= 1.0) size = _pageScrollView.contentView.frame.size;
    if (size.width <= 1.0 || size.height <= 1.0) size = _pageScrollView.contentView.bounds.size;
    if (size.width <= 1.0) size.width = NSWidth(_documentContainer.bounds);
    if (size.height <= 1.0) size.height = NSHeight(_documentContainer.bounds);
    return size;
}

- (CGFloat)zoomForFitMode:(SPDFFitMode)fitMode pageIndex:(NSInteger)pageIndex {
    if (!_doc) return _zoom;
    if (fitMode == SPDFFitModeCustom)
        return MAX(kMinZoom, MIN(kMaxZoom, _rememberedCustomZoom > 0 ? _rememberedCustomZoom : _zoom));
    if (fitMode == SPDFFitModeActual) return 1.0;

    char err[1024];
    float pageWidth = 0;
    float pageHeight = 0;
    if (!spdf_page_size(_doc, (int)pageIndex, &pageWidth, &pageHeight, err, sizeof(err)) || pageWidth <= 0 ||
        pageHeight <= 0)
        return _zoom;

    NSSize clipSize = [self documentClipSizeForLayout];
    CGFloat pageMargin = _presentationMode ? 0.0 : kPageMargin;
    CGFloat widthZoom = (clipSize.width - pageMargin * 1.7) / pageWidth;
    CGFloat heightZoom = (clipSize.height - pageMargin) / pageHeight;
    if (fitMode == SPDFFitModeWidth) return MAX(kMinZoom, MIN(kMaxZoom, widthZoom));
    if (fitMode == SPDFFitModeHeight) return MAX(kMinZoom, MIN(kMaxZoom, heightZoom));
    return MAX(kMinZoom, MIN(kMaxZoom, MIN(widthZoom, heightZoom)));
}

- (SPDFRenderedPage*)renderedPageAtIndex:(NSInteger)pageIndex
                                document:(spdf_document*)doc
                                    zoom:(CGFloat)zoom
                            displayScale:(CGFloat)displayScale
                                   error:(char*)err
                             errorLength:(size_t)errLen {
    float pageWidth = 0;
    float pageHeight = 0;
    if (!spdf_page_size(doc, (int)pageIndex, &pageWidth, &pageHeight, err, errLen)) return nil;

    spdf_bitmap bitmap;
    if (!spdf_render_page_rgba(doc, (int)pageIndex, (float)(zoom * displayScale), &bitmap, err, errLen)) return nil;

    NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:bitmap.width
                                                                    pixelsHigh:bitmap.height
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:bitmap.stride
                                                                  bitsPerPixel:32];
    memcpy(rep.bitmapData, bitmap.rgba, (size_t)bitmap.stride * (size_t)bitmap.height);

    displayScale = displayScale > 0 ? displayScale : 1.0;
    NSSize pointSize = NSMakeSize((CGFloat)bitmap.width / displayScale, (CGFloat)bitmap.height / displayScale);
    rep.size = pointSize;
    NSImage* image = [[NSImage alloc] initWithSize:pointSize];
    [image addRepresentation:rep];
    spdf_free_bitmap(&bitmap);

    SPDFRenderedPage* page = [[SPDFRenderedPage alloc] init];
    page.pageIndex = pageIndex;
    page.pageWidth = pageWidth;
    page.pageHeight = pageHeight;
    page.imagePointWidth = pointSize.width;
    page.imagePointHeight = pointSize.height;
    page.imageZoom = zoom;
    page.imageScale = displayScale;
    page.image = image;
    page.highlights = @[];
    page.selectionRects = @[];
    return page;
}

- (SPDFRenderedPage*)renderedPageAtIndex:(NSInteger)pageIndex error:(char*)err errorLength:(size_t)errLen {
    return [self renderedPageAtIndex:pageIndex
                            document:_doc
                                zoom:_zoom
                        displayScale:[self backingScale]
                               error:err
                         errorLength:errLen];
}

- (SPDFRenderedPage*)placeholderPageAtIndex:(NSInteger)pageIndex
                                   document:(spdf_document*)doc
                              fallbackWidth:(CGFloat)fallbackWidth
                             fallbackHeight:(CGFloat)fallbackHeight {
    CGFloat pageWidth = fallbackWidth;
    CGFloat pageHeight = fallbackHeight;
    if (doc) {
        char err[256];
        float nativeWidth = 0;
        float nativeHeight = 0;
        if (spdf_page_size(doc, (int)pageIndex, &nativeWidth, &nativeHeight, err, sizeof(err)) && nativeWidth > 0 &&
            nativeHeight > 0) {
            pageWidth = nativeWidth;
            pageHeight = nativeHeight;
        }
    }

    SPDFRenderedPage* page = [[SPDFRenderedPage alloc] init];
    page.pageIndex = pageIndex;
    page.pageWidth = pageWidth;
    page.pageHeight = pageHeight;
    page.highlights = @[];
    page.selectionRects = @[];
    return page;
}

- (spdf_document*)workerDocumentForPath:(NSString*)path error:(char*)err errorLength:(size_t)errLen {
    if (!path.length) return NULL;

    NSMutableDictionary* threadDictionary = NSThread.currentThread.threadDictionary;
    SPDFWorkerDocument* holder = threadDictionary[@"SumatraPDFWorkerDocument"];
    if (holder && [holder.path isEqualToString:path] && holder.document) return holder.document;

    holder = [[SPDFWorkerDocument alloc] init];
    holder.path = path;
    holder.document = spdf_open(path.fileSystemRepresentation, err, errLen);
    if (!holder.document) return NULL;
    threadDictionary[@"SumatraPDFWorkerDocument"] = holder;
    return holder.document;
}

- (NSArray<NSNumber*>*)pageRenderOrderForCount:(NSInteger)pageCount
                                 preferredPage:(NSInteger)preferredPage
                                      maxPages:(NSInteger)maxPages {
    if (pageCount <= 0 || maxPages <= 0) return @[];
    NSMutableArray<NSNumber*>* order = [NSMutableArray arrayWithCapacity:(NSUInteger)MIN(pageCount, maxPages)];
    if (preferredPage >= 0 && preferredPage < pageCount) [order addObject:@(preferredPage)];
    for (NSInteger distance = 1; distance < pageCount && (NSInteger)order.count < maxPages; ++distance) {
        NSInteger after = preferredPage + distance;
        NSInteger before = preferredPage - distance;
        if (after < pageCount && (NSInteger)order.count < maxPages) [order addObject:@(after)];
        if (before >= 0 && (NSInteger)order.count < maxPages) [order addObject:@(before)];
    }
    return order;
}

- (NSOperationQueuePriority)queuePriorityForRenderDistance:(NSInteger)distance {
    if (distance <= 2) return NSOperationQueuePriorityVeryHigh;
    if (distance <= 6) return NSOperationQueuePriorityHigh;
    if (distance <= 18) return NSOperationQueuePriorityNormal;
    return NSOperationQueuePriorityLow;
}

- (void)scheduleNearbyPageRendersAfterFirstPaintForGeneration:(NSUInteger)generation
                                                preferredPage:(NSInteger)preferredPage {
    NSString* path = [_path copy];
    dispatch_async(dispatch_get_main_queue(), ^{
      [self->_pageScrollView displayIfNeeded];
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAfterFirstPaintDelay * NSEC_PER_SEC)),
                     dispatch_get_main_queue(), ^{
                       if (generation != self->_renderGeneration || ![self->_path isEqualToString:path]) return;
                       [self enqueueNearbyPageRendersForGeneration:generation preferredPage:preferredPage];
                     });
    });
}

- (void)enqueueNearbyPageRendersForGeneration:(NSUInteger)generation preferredPage:(NSInteger)preferredPage {
    if (!_doc || !_path.length) return;

    NSString* path = [_path copy];
    CGFloat zoom = _zoom;
    CGFloat displayScale = [self backingScale];
    NSArray<NSNumber*>* order = [self pageRenderOrderForCount:(NSInteger)_renderedPages.count
                                                preferredPage:preferredPage
                                                     maxPages:kBackgroundRenderBatchSize];
    for (NSNumber* number in order) {
        NSInteger index = number.integerValue;
        if (index < 0 || index >= (NSInteger)_renderedPages.count) continue;
        if (_renderedPages[(NSUInteger)index].image) continue;
        if ([_queuedRenderPages containsObject:number]) continue;
        [_queuedRenderPages addObject:number];

        NSInteger distance = labs(index - preferredPage);
        NSBlockOperation* operation = [NSBlockOperation blockOperationWithBlock:^{
          @autoreleasepool {
              if (generation != self->_renderGeneration) {
                  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [self->_queuedRenderPages removeObject:number];
                  }];
                  return;
              }
              char err[1024];
              spdf_document* workerDoc = [self workerDocumentForPath:path error:err errorLength:sizeof(err)];
              if (!workerDoc) {
                  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [self->_queuedRenderPages removeObject:number];
                  }];
                  return;
              }
              SPDFRenderedPage* page = [self renderedPageAtIndex:index
                                                        document:workerDoc
                                                            zoom:zoom
                                                    displayScale:displayScale
                                                           error:err
                                                     errorLength:sizeof(err)];
              if (!page) {
                  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [self->_queuedRenderPages removeObject:number];
                  }];
                  return;
              }

              [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [self->_queuedRenderPages removeObject:number];
                if (generation != self->_renderGeneration || !self->_doc ||
                    index >= (NSInteger)self->_renderedPages.count)
                    return;
                SPDFRenderedPage* old = self->_renderedPages[(NSUInteger)index];
                page.highlights = self->_findHighlights[@(index)] ?: old.highlights ?: @[];
                page.selectionRects = old.selectionRects ?: @[];
                BOOL geometryChanged =
                    fabs(old.pageWidth - page.pageWidth) > 0.01 || fabs(old.pageHeight - page.pageHeight) > 0.01;
                [self->_renderedPages replaceObjectAtIndex:(NSUInteger)index withObject:page];
                [self applySearchHighlightsToCurrentPage];
                if (geometryChanged)
                    [self resizeDocumentView];
                else {
                    self->_pageView.pages = self->_renderedPages;
                    [self->_pageView setNeedsDisplayInRect:[self->_pageView rectForPageAtIndex:index]];
                    [self updateMinimap];
                }
              }];
          }
        }];
        operation.queuePriority = [self queuePriorityForRenderDistance:distance];
        [_renderQueue addOperation:operation];
    }
}

- (void)renderPageIfNeededAtIndex:(NSInteger)pageIndex {
    if (!_doc || pageIndex < 0 || pageIndex >= (NSInteger)_renderedPages.count) return;
    SPDFRenderedPage* existing = _renderedPages[(NSUInteger)pageIndex];
    if (existing.image) return;

    char err[1024];
    SPDFRenderedPage* page = [self renderedPageAtIndex:pageIndex error:err errorLength:sizeof(err)];
    if (!page) {
        _statusLabel.stringValue = [NSString stringWithFormat:@"Could not render page %ld", (long)pageIndex + 1];
        return;
    }
    page.highlights = _findHighlights[@(pageIndex)] ?: existing.highlights ?: @[];
    page.selectionRects = existing.selectionRects ?: @[];
    [_renderedPages replaceObjectAtIndex:(NSUInteger)pageIndex withObject:page];
    _pageView.pages = _renderedPages;
    [self updateMinimap];
}

- (void)renderDocumentAndScrollToPage:(NSInteger)pageIndex alignTop:(BOOL)alignTop {
    [self renderDocumentAndScrollToPage:pageIndex alignTop:alignTop restoreOrigin:nil];
}

- (void)renderDocumentAndScrollToPage:(NSInteger)pageIndex
                             alignTop:(BOOL)alignTop
                        restoreOrigin:(NSValue*)restoreOrigin {
    if (!_doc || !_uiReady) return;

    [_window.contentView layoutSubtreeIfNeeded];
    [_renderQueue cancelAllOperations];
    [_queuedRenderPages removeAllObjects];
    _renderGeneration++;
    NSUInteger generation = _renderGeneration;
    _zoom = [self zoomForFitMode:_fitMode pageIndex:MAX(0, pageIndex)];
    NSMutableArray<SPDFRenderedPage*>* pages = [NSMutableArray arrayWithCapacity:(NSUInteger)spdf_page_count(_doc)];
    char err[1024];
    NSInteger pageCount = spdf_page_count(_doc);
    pageIndex = MAX(0, MIN(pageIndex, pageCount - 1));
    SPDFRenderedPage* preferredPage = [self renderedPageAtIndex:pageIndex error:err errorLength:sizeof(err)];
    if (!preferredPage) {
        [self showError:@"Could not render page" detail:[NSString stringWithUTF8String:err[0] ? err : "Unknown error"]];
        return;
    }
    for (NSInteger i = 0; i < pageCount; ++i) {
        SPDFRenderedPage* page = nil;
        if (i == pageIndex)
            page = preferredPage;
        else
            page = [self placeholderPageAtIndex:i
                                       document:_doc
                                  fallbackWidth:preferredPage.pageWidth
                                 fallbackHeight:preferredPage.pageHeight];
        if (!page) {
            [self showError:@"Could not render page"
                     detail:[NSString stringWithUTF8String:err[0] ? err : "Unknown error"]];
            return;
        }
        [pages addObject:page];
    }

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
      context.duration = 0.0;
      context.allowsImplicitAnimation = NO;
      self->_renderedPages = pages;
      self->_pageView.pages = self->_renderedPages;
      self->_pageView.currentPageIndex = self->_pageIndex;
      self->_pageView.zoom = self->_zoom;
      self->_pageView.viewMode = self->_viewMode;
      self->_pageView.backingScale = [self backingScale];
      [self applySearchHighlightsToCurrentPage];
      [self resizeDocumentView];
      if (restoreOrigin)
          [self scrollDocumentClipViewToOrigin:[self normalizedDocumentScrollOrigin:restoreOrigin.pointValue
                                                                       forPageIndex:pageIndex]
                                        notify:NO];
      else
          [self scrollToPage:pageIndex alignTop:alignTop];
    }
                        completionHandler:nil];
    NSInteger renderCenterPage = pageIndex;
    if (restoreOrigin) {
        renderCenterPage = [_pageView pageIndexForVisibleRect:_pageScrollView.contentView.bounds];
        _pageIndex = renderCenterPage;
        _pageView.currentPageIndex = _pageIndex;
        [self renderPageIfNeededAtIndex:_pageIndex];
    }

    [self syncToolbarState];
    [self updateControls];
    [self selectCurrentSidebarRow];
    [self updateMinimap];

    [self scheduleNearbyPageRendersAfterFirstPaintForGeneration:generation preferredPage:renderCenterPage];
}

- (void)resizeDocumentView {
    NSClipView* clipView = _pageScrollView.contentView;
    [_pageScrollView layoutSubtreeIfNeeded];
    [_pageScrollView tile];
    NSSize clipSize = [self documentClipSizeForLayout];
    _pageView.viewportWidthHint = MAX(1.0, clipSize.width);
    _pageView.backingScale = [self backingScale];
    if (!_doc) {
        _pageScrollView.hasVerticalScroller = NO;
        _pageScrollView.hasHorizontalScroller = NO;
        [_documentContainer layoutSubtreeIfNeeded];
        [_pageScrollView layoutSubtreeIfNeeded];
        [_pageScrollView tile];
        clipSize = clipView.bounds.size;
        if (clipSize.width <= 1.0 || clipSize.height <= 1.0) clipSize = _pageScrollView.contentSize;
        if (clipSize.width <= 1.0 || clipSize.height <= 1.0) clipSize = _pageScrollView.frame.size;
        _pageView.viewportWidthHint = MAX(1.0, clipSize.width);
        [_pageView setFrame:NSMakeRect(0.0, 0.0, MAX(1.0, clipSize.width), MAX(1.0, clipSize.height))];
        if (fabs(NSMinX(clipView.bounds)) > 0.01 || fabs(NSMinY(clipView.bounds)) > 0.01) {
            [clipView setBoundsOrigin:NSZeroPoint];
            [_pageScrollView reflectScrolledClipView:clipView];
        }
        [_pageView setNeedsDisplay:YES];
        [self updateMinimap];
        [self invalidateFindMarkers];
        return;
    }

    if (_presentationMode)
        _pageScrollView.verticalScroller = nil;
    else if (_pageScrollView.verticalScroller != _markerScroller)
        _pageScrollView.verticalScroller = _markerScroller;
    _pageScrollView.hasVerticalScroller = !_presentationMode;
    NSSize size = [_pageView documentSizeForClipSize:clipSize];
    BOOL needsHorizontalScroller = size.width > clipSize.width + 0.5;
    if (_pageScrollView.hasHorizontalScroller != needsHorizontalScroller) {
        _pageScrollView.hasHorizontalScroller = needsHorizontalScroller;
        [_pageScrollView tile];
        clipSize = [self documentClipSizeForLayout];
        _pageView.viewportWidthHint = MAX(1.0, clipSize.width);
        size = [_pageView documentSizeForClipSize:clipSize];
        needsHorizontalScroller = size.width > clipSize.width + 0.5;
        _pageScrollView.hasHorizontalScroller = needsHorizontalScroller;
    }
    if (!needsHorizontalScroller) size.width = MAX(size.width, clipSize.width);
    [_pageView setFrame:NSMakeRect(0.0, 0.0, size.width, size.height)];
    if (!needsHorizontalScroller && fabs(NSMinX(clipView.bounds)) > 0.01) {
        NSPoint origin = clipView.bounds.origin;
        origin.x = 0.0;
        [clipView setBoundsOrigin:origin];
        [_pageScrollView reflectScrolledClipView:clipView];
    }
    [_pageView setNeedsDisplay:YES];
    [self updateMinimap];
    [self invalidateFindMarkers];
}

- (void)showEmptyDocumentViewWithMessage:(NSString*)message {
    _pageScrollView.hidden = NO;
    _pageView.emptyMessage = message.length ? message : @"Open a document";
    _pageView.currentPageIndex = 0;
    _pageView.activeFindPageIndex = -1;
    _pageView.activeFindAlpha = 0.0;
    _pageView.pages = @[];
    [self setMinimapActuallyVisible:NO];
    [self resizeDocumentView];
    NSString* expectedMessage = [_pageView.emptyMessage copy];
    dispatch_async(dispatch_get_main_queue(), ^{
      if (self->_doc || ![self->_pageView.emptyMessage isEqualToString:expectedMessage]) return;
      [self->_window.contentView layoutSubtreeIfNeeded];
      [self->_documentContainer layoutSubtreeIfNeeded];
      [self->_pageScrollView layoutSubtreeIfNeeded];
      [self resizeDocumentView];
    });
}

- (NSPoint)clampedDocumentScrollOrigin:(NSPoint)origin forPageIndex:(NSInteger)pageIndex {
    NSClipView* clipView = _pageScrollView.contentView;
    if (_renderedPages.count > 0) {
        pageIndex = MAX(0, MIN(pageIndex, (NSInteger)_renderedPages.count - 1));
        NSRect pageRect = [_pageView rectForPageAtIndex:pageIndex];
        if (!NSIsEmptyRect(pageRect)) {
            CGFloat visibleWidth = NSWidth(clipView.bounds);
            if (NSWidth(pageRect) <= visibleWidth + 0.5)
                origin.x = 0.0;
            else
                origin.x = spdf_clamp_cg(origin.x, NSMinX(pageRect), NSMaxX(pageRect) - visibleWidth);
            if (_viewMode == SPDFViewModeSingle && NSHeight(pageRect) <= NSHeight(clipView.bounds) + 0.5)
                origin.y = NSMidY(pageRect) - NSHeight(clipView.bounds) * 0.5;
        }
    }
    origin.x = spdf_clamp_cg(origin.x, 0.0, MAX(0.0, NSWidth(_pageView.bounds) - NSWidth(clipView.bounds)));
    origin.y = spdf_clamp_cg(origin.y, 0.0, MAX(0.0, NSHeight(_pageView.bounds) - NSHeight(clipView.bounds)));
    return origin;
}

- (NSPoint)clampedDocumentScrollOrigin:(NSPoint)origin {
    NSInteger pageIndex = _pageIndex;
    if (_renderedPages.count > 0 && _pageScrollView) {
        NSClipView* clipView = _pageScrollView.contentView;
        NSRect proposedVisible = NSMakeRect(origin.x, origin.y, NSWidth(clipView.bounds), NSHeight(clipView.bounds));
        pageIndex = _viewMode == SPDFViewModeSingle ? _pageIndex : [_pageView pageIndexForVisibleRect:proposedVisible];
    }
    return [self clampedDocumentScrollOrigin:origin forPageIndex:pageIndex];
}

- (NSPoint)normalizedDocumentScrollOrigin:(NSPoint)origin forPageIndex:(NSInteger)pageIndex {
    if (_renderedPages.count == 0) return [self clampedDocumentScrollOrigin:origin forPageIndex:pageIndex];

    pageIndex = MAX(0, MIN(pageIndex, (NSInteger)_renderedPages.count - 1));
    NSClipView* clipView = _pageScrollView.contentView;
    NSRect pageRect = [_pageView rectForPageAtIndex:pageIndex];
    if (NSIsEmptyRect(pageRect)) return [self clampedDocumentScrollOrigin:origin forPageIndex:pageIndex];

    CGFloat visibleWidth = NSWidth(clipView.bounds);
    if (NSWidth(pageRect) <= visibleWidth + 0.5) {
        origin.x = 0.0;
    } else if (origin.x <= NSMinX(pageRect) + 2.0) {
        origin.x = MAX(0.0, NSMinX(pageRect) - kPageMargin / 2.0);
    }

    return [self clampedDocumentScrollOrigin:origin forPageIndex:pageIndex];
}

- (void)scrollDocumentClipViewToOrigin:(NSPoint)origin notify:(BOOL)notify {
    NSClipView* clipView = _pageScrollView.contentView;
    origin = [self clampedDocumentScrollOrigin:origin];
    _updatingFromScroll = YES;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
      context.duration = 0.0;
      context.allowsImplicitAnimation = NO;
      [clipView setBoundsOrigin:origin];
      [self->_pageScrollView reflectScrolledClipView:clipView];
    }
                        completionHandler:nil];
    _updatingFromScroll = NO;
    if (notify) {
        [self documentScrollPositionChanged];
        [self updateMinimap];
    }
}

- (void)scrollToPage:(NSInteger)pageIndex alignTop:(BOOL)alignTop {
    if (_renderedPages.count == 0) return;
    pageIndex = MAX(0, MIN(pageIndex, (NSInteger)_renderedPages.count - 1));
    NSRect pageRect = [_pageView rectForPageAtIndex:pageIndex];
    if (alignTop) {
        NSClipView* clipView = _pageScrollView.contentView;
        CGFloat x = NSWidth(pageRect) <= NSWidth(clipView.bounds) + 0.5 ? 0.0 : MAX(0, pageRect.origin.x - 12.0);
        CGFloat y = MAX(0, pageRect.origin.y - 12);
        if (_viewMode == SPDFViewModeSingle && NSHeight(pageRect) <= NSHeight(clipView.bounds) + 0.5)
            y = NSMidY(pageRect) - NSHeight(clipView.bounds) * 0.5;
        NSPoint point = NSMakePoint(x, y);
        [self scrollDocumentClipViewToOrigin:point notify:NO];
    } else {
        NSClipView* clipView = _pageScrollView.contentView;
        NSRect visible = clipView.bounds;
        NSPoint origin = visible.origin;
        if (NSMinX(pageRect) < NSMinX(visible))
            origin.x = NSMinX(pageRect) - 12.0;
        else if (NSMaxX(pageRect) > NSMaxX(visible))
            origin.x = NSMaxX(pageRect) - NSWidth(visible) + 12.0;
        if (NSMinY(pageRect) < NSMinY(visible))
            origin.y = NSMinY(pageRect) - 12.0;
        else if (NSMaxY(pageRect) > NSMaxY(visible))
            origin.y = NSMaxY(pageRect) - NSHeight(visible) + 12.0;
        [self scrollDocumentClipViewToOrigin:origin notify:NO];
    }
    [self documentScrollPositionChanged];
    [self updateMinimap];
}

- (void)stabilizeDocumentLayoutWithRestoreOrigin:(NSValue*)restoreOrigin
                                        alignTop:(BOOL)alignTop
                                      generation:(NSUInteger)generation
                                            path:(NSString*)path {
    if (!_doc || generation != _renderGeneration || ![_path isEqualToString:path]) return;

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
      context.duration = 0.0;
      context.allowsImplicitAnimation = NO;
      [self->_window.contentView layoutSubtreeIfNeeded];
      [self->_documentContainer layoutSubtreeIfNeeded];
      [self->_pageScrollView layoutSubtreeIfNeeded];
      [self resizeDocumentView];
      if (restoreOrigin) {
          NSPoint origin = [self normalizedDocumentScrollOrigin:restoreOrigin.pointValue forPageIndex:self->_pageIndex];
          [self scrollDocumentClipViewToOrigin:origin notify:NO];
      } else {
          [self scrollToPage:self->_pageIndex alignTop:alignTop];
      }
      [self->_pageView setNeedsDisplay:YES];
      [self->_pageScrollView displayIfNeeded];
    }
                        completionHandler:nil];
    [self documentScrollPositionChanged];
    [self updateMinimap];
    if (!_suppressScrollCallbacks) [self rememberActiveTabState];
}

- (NSPoint)relativeScrollPositionForPage:(NSInteger)pageIndex fromVisibleRect:(NSRect)visibleRect {
    if (_renderedPages.count == 0) return NSZeroPoint;
    pageIndex = MAX(0, MIN(pageIndex, (NSInteger)_renderedPages.count - 1));
    NSRect pageRect = [_pageView rectForPageAtIndex:pageIndex];
    if (NSIsEmptyRect(pageRect)) return NSZeroPoint;

    CGFloat maxX = MAX(1.0, NSWidth(pageRect) - NSWidth(visibleRect));
    CGFloat maxY = MAX(1.0, NSHeight(pageRect) - NSHeight(visibleRect));
    CGFloat relativeX = spdf_clamp_cg((NSMinX(visibleRect) - NSMinX(pageRect)) / maxX, 0.0, 1.0);
    CGFloat relativeY = spdf_clamp_cg((NSMinY(visibleRect) - NSMinY(pageRect)) / maxY, 0.0, 1.0);
    return NSMakePoint(relativeX, relativeY);
}

- (NSPoint)relativeScrollPositionForCurrentPage {
    return [self relativeScrollPositionForPage:_pageIndex fromVisibleRect:_pageScrollView.contentView.bounds];
}

- (void)scrollToPage:(NSInteger)pageIndex preservingRelativePosition:(NSPoint)relativePosition {
    if (_renderedPages.count == 0) return;
    pageIndex = MAX(0, MIN(pageIndex, (NSInteger)_renderedPages.count - 1));
    NSRect pageRect = [_pageView rectForPageAtIndex:pageIndex];
    if (NSIsEmptyRect(pageRect)) return;

    NSClipView* clipView = _pageScrollView.contentView;
    CGFloat maxInPageX = MAX(0.0, NSWidth(pageRect) - NSWidth(clipView.bounds));
    CGFloat maxInPageY = MAX(0.0, NSHeight(pageRect) - NSHeight(clipView.bounds));
    CGFloat maxDocumentX = MAX(0.0, NSWidth(_pageView.bounds) - NSWidth(clipView.bounds));
    CGFloat maxDocumentY = MAX(0.0, NSHeight(_pageView.bounds) - NSHeight(clipView.bounds));
    NSPoint origin = NSMakePoint(NSMinX(pageRect) + spdf_clamp_cg(relativePosition.x, 0.0, 1.0) * maxInPageX,
                                 NSMinY(pageRect) + spdf_clamp_cg(relativePosition.y, 0.0, 1.0) * maxInPageY);
    if (NSWidth(pageRect) <= NSWidth(clipView.bounds) + 0.5) origin.x = 0.0;
    if (_viewMode == SPDFViewModeSingle && NSHeight(pageRect) <= NSHeight(clipView.bounds) + 0.5)
        origin.y = NSMidY(pageRect) - NSHeight(clipView.bounds) * 0.5;
    origin.x = spdf_clamp_cg(origin.x, 0.0, maxDocumentX);
    origin.y = spdf_clamp_cg(origin.y, 0.0, maxDocumentY);

    [self scrollDocumentClipViewToOrigin:origin notify:YES];
}

- (void)goToPage:(NSInteger)pageIndex preserveSinglePagePosition:(BOOL)preserveSinglePagePosition {
    if (!_doc) return;
    NSInteger pageCount = spdf_page_count(_doc);
    if (pageCount <= 0) return;
    pageIndex = MAX(0, MIN(pageIndex, pageCount - 1));
    NSPoint relativePosition = preserveSinglePagePosition ? [self relativeScrollPositionForCurrentPage] : NSZeroPoint;

    _pageIndex = pageIndex;
    _pageView.currentPageIndex = _pageIndex;
    [self clearPageFieldFocus];
    [self renderPageIfNeededAtIndex:_pageIndex];
    [self resizeDocumentView];
    if (preserveSinglePagePosition)
        [self scrollToPage:_pageIndex preservingRelativePosition:relativePosition];
    else
        [self scrollToPage:_pageIndex alignTop:YES];
    [self updateControls];
    [self selectCurrentSidebarRow];
    [_pageView setNeedsDisplay:YES];
    [self persistActiveState];
}

- (CGFloat)continuousDocumentHeightForMinimap {
    return MAX(1.0, NSHeight(_pageView.bounds));
}

- (NSRect)continuousDocumentRectForPageAtIndex:(NSInteger)pageIndex {
    if (pageIndex < 0 || pageIndex >= (NSInteger)_renderedPages.count || !_pageView) return NSZeroRect;
    return [_pageView rectForPageAtIndex:pageIndex];
}

- (NSRect)continuousDocumentVisibleRectForMinimap {
    return _pageScrollView.contentView.bounds;
}

- (NSInteger)pageIndexForContinuousDocumentY:(CGFloat)y pageFraction:(CGFloat*)pageFraction {
    if (_renderedPages.count == 0) {
        if (pageFraction) *pageFraction = 0.0;
        return 0;
    }

    NSInteger closestPage = 0;
    CGFloat closestDistance = CGFLOAT_MAX;
    for (SPDFRenderedPage* page in _renderedPages) {
        NSRect pageRect = [self continuousDocumentRectForPageAtIndex:page.pageIndex];
        if (NSIsEmptyRect(pageRect)) continue;
        if (y >= NSMinY(pageRect) && y <= NSMaxY(pageRect)) {
            if (pageFraction)
                *pageFraction = spdf_clamp_cg((y - NSMinY(pageRect)) / MAX(1.0, NSHeight(pageRect)), 0.0, 1.0);
            return page.pageIndex;
        }

        CGFloat distance = MIN(fabs(y - NSMinY(pageRect)), fabs(y - NSMaxY(pageRect)));
        if (distance < closestDistance) {
            closestDistance = distance;
            closestPage = page.pageIndex;
            if (pageFraction) *pageFraction = y < NSMinY(pageRect) ? 0.0 : 1.0;
        }
    }
    return closestPage;
}

- (NSPoint)continuousDocumentPointForPage:(NSInteger)pageIndex
                          xFractionInPage:(CGFloat)xFraction
                          yFractionInPage:(CGFloat)yFraction {
    NSRect pageRect = [self continuousDocumentRectForPageAtIndex:pageIndex];
    if (NSIsEmptyRect(pageRect)) return NSZeroPoint;
    return NSMakePoint(NSMinX(pageRect) + spdf_clamp_cg(xFraction, 0.0, 1.0) * NSWidth(pageRect),
                       NSMinY(pageRect) + spdf_clamp_cg(yFraction, 0.0, 1.0) * NSHeight(pageRect));
}

- (void)scrollToPage:(NSInteger)pageIndex centeredAtPageXFraction:(CGFloat)xFraction yFraction:(CGFloat)yFraction {
    if (_renderedPages.count == 0) return;
    pageIndex = MAX(0, MIN(pageIndex, (NSInteger)_renderedPages.count - 1));
    xFraction = spdf_clamp_cg(xFraction, 0.0, 1.0);
    yFraction = spdf_clamp_cg(yFraction, 0.0, 1.0);

    NSRect pageRect = [_pageView rectForPageAtIndex:pageIndex];
    if (NSIsEmptyRect(pageRect)) return;

    NSClipView* clipView = _pageScrollView.contentView;
    CGFloat maxInPageX = MAX(0.0, NSWidth(pageRect) - NSWidth(clipView.bounds));
    CGFloat maxInPageY = MAX(0.0, NSHeight(pageRect) - NSHeight(clipView.bounds));
    CGFloat maxDocumentX = MAX(0.0, NSWidth(_pageView.bounds) - NSWidth(clipView.bounds));
    CGFloat maxDocumentY = MAX(0.0, NSHeight(_pageView.bounds) - NSHeight(clipView.bounds));
    NSPoint origin = NSMakePoint(NSMinX(pageRect) + NSWidth(pageRect) * xFraction - NSWidth(clipView.bounds) * 0.5,
                                 NSMinY(pageRect) + NSHeight(pageRect) * yFraction - NSHeight(clipView.bounds) * 0.5);
    if (NSWidth(pageRect) <= NSWidth(clipView.bounds) + 0.5)
        origin.x = 0.0;
    else
        origin.x = spdf_clamp_cg(origin.x, NSMinX(pageRect), NSMinX(pageRect) + maxInPageX);
    origin.x = spdf_clamp_cg(origin.x, 0.0, maxDocumentX);
    if (_viewMode == SPDFViewModeSingle && NSHeight(pageRect) <= NSHeight(clipView.bounds) + 0.5)
        origin.y = NSMidY(pageRect) - NSHeight(clipView.bounds) * 0.5;
    else
        origin.y = spdf_clamp_cg(origin.y, NSMinY(pageRect), NSMinY(pageRect) + maxInPageY);
    origin.y = spdf_clamp_cg(origin.y, 0.0, maxDocumentY);

    [self scrollDocumentClipViewToOrigin:origin notify:YES];
}

- (void)updateMinimap {
    if (!_minimapView) return;
    NSMutableArray<NSValue*>* pageRects = [NSMutableArray arrayWithCapacity:_renderedPages.count];
    for (SPDFRenderedPage* page in _renderedPages ?: @[])
        [pageRects addObject:[NSValue valueWithRect:[self continuousDocumentRectForPageAtIndex:page.pageIndex]]];
    _minimapView.pages = _renderedPages ?: @[];
    _minimapView.documentPageRects = pageRects;
    _minimapView.currentPageIndex = _pageIndex;
    _minimapView.viewMode = _viewMode;
    _minimapView.documentVisibleRect = [self continuousDocumentVisibleRectForMinimap];
    _minimapView.documentWidth = MAX(1.0, NSWidth(_pageView.bounds));
    _minimapView.documentHeight = MAX(1.0, [self continuousDocumentHeightForMinimap]);
    _minimapView.documentScale = MAX(0.01, _zoom);
    [_minimapView setNeedsDisplay:YES];
}

- (void)invalidateFindMarkers {
    [_pageScrollView.verticalScroller setNeedsDisplay:YES];
}

- (NSArray<NSDictionary*>*)findScrollbarMarkers {
    if (!_doc || _findMatches.count == 0 || _renderedPages.count == 0) return @[];

    CGFloat documentHeight = MAX(1.0, [self continuousDocumentHeightForMinimap]);
    NSMutableArray<NSDictionary*>* markers = [NSMutableArray arrayWithCapacity:_findMatches.count];
    for (NSInteger i = 0; i < (NSInteger)_findMatches.count; ++i) {
        NSDictionary* match = _findMatches[(NSUInteger)i];
        NSInteger page = [match[@"page"] integerValue];
        if (page < 0 || page >= (NSInteger)_renderedPages.count) continue;

        NSRect pageRect = [self continuousDocumentRectForPageAtIndex:page];
        NSRect matchRect = [match[@"rect"] rectValue];
        if (NSIsEmptyRect(pageRect) || NSIsEmptyRect(matchRect)) continue;

        CGFloat y = NSMinY(pageRect) + NSMidY(matchRect) * _zoom;
        [markers addObject:@{
            @"fraction" : @(spdf_clamp_cg(y / documentHeight, 0.0, 1.0)),
            @"active" : @(i == _findMatchIndex)
        }];
    }
    return markers;
}

- (void)minimapViewDidRequestScrollToFraction:(CGFloat)yFraction {
    if (!_doc || _renderedPages.count == 0) return;
    yFraction = spdf_clamp_cg(yFraction, 0.0, 1.0);

    NSPoint documentPoint = NSMakePoint(NSMidX([self continuousDocumentVisibleRectForMinimap]),
                                        yFraction * [self continuousDocumentHeightForMinimap]);
    [self minimapViewDidRequestCenterAtDocumentPoint:documentPoint];
}

- (void)minimapViewDidRequestScrollToPage:(NSInteger)pageIndex yFractionInPage:(CGFloat)yFraction {
    [self minimapViewDidRequestCenterOnPage:pageIndex xFractionInPage:0.5 yFractionInPage:yFraction];
}

- (void)minimapViewDidRequestCenterAtDocumentPoint:(NSPoint)documentPoint {
    if (!_doc || _renderedPages.count == 0) return;

    if (_viewMode == SPDFViewModeContinuous) {
        NSClipView* clipView = _pageScrollView.contentView;
        NSPoint origin = NSMakePoint(documentPoint.x - NSWidth(clipView.bounds) * 0.5,
                                     documentPoint.y - NSHeight(clipView.bounds) * 0.5);
        CGFloat maxX = MAX(0.0, NSWidth(_pageView.bounds) - NSWidth(clipView.bounds));
        CGFloat maxY = MAX(0.0, NSHeight(_pageView.bounds) - NSHeight(clipView.bounds));
        origin.x = spdf_clamp_cg(origin.x, 0.0, maxX);
        origin.y = spdf_clamp_cg(origin.y, 0.0, maxY);

        [self scrollDocumentClipViewToOrigin:origin notify:YES];
        [self rememberActiveTabState];
        return;
    }

    CGFloat yFraction = 0.0;
    NSInteger pageIndex = [self pageIndexForContinuousDocumentY:documentPoint.y pageFraction:&yFraction];
    NSRect pageRect = [self continuousDocumentRectForPageAtIndex:pageIndex];
    CGFloat xFraction =
        NSIsEmptyRect(pageRect)
            ? 0.5
            : spdf_clamp_cg((documentPoint.x - NSMinX(pageRect)) / MAX(1.0, NSWidth(pageRect)), 0.0, 1.0);
    [self minimapViewDidRequestCenterOnPage:pageIndex xFractionInPage:xFraction yFractionInPage:yFraction];
}

- (void)minimapViewDidRequestCenterOnPage:(NSInteger)pageIndex
                          xFractionInPage:(CGFloat)xFraction
                          yFractionInPage:(CGFloat)yFraction {
    if (!_doc || pageIndex < 0 || pageIndex >= (NSInteger)_renderedPages.count) return;
    xFraction = spdf_clamp_cg(xFraction, 0.0, 1.0);
    yFraction = spdf_clamp_cg(yFraction, 0.0, 1.0);
    NSPoint documentPoint =
        [self continuousDocumentPointForPage:pageIndex xFractionInPage:xFraction yFractionInPage:yFraction];
    if (_viewMode == SPDFViewModeContinuous) {
        [self minimapViewDidRequestCenterAtDocumentPoint:documentPoint];
        return;
    }
    _pageIndex = pageIndex;
    _pageView.currentPageIndex = _pageIndex;
    [self renderPageIfNeededAtIndex:_pageIndex];
    [self resizeDocumentView];
    [self scrollToPage:_pageIndex centeredAtPageXFraction:xFraction yFraction:yFraction];
    [self updateControls];
    [self selectCurrentSidebarRow];
    [self updateMinimap];
    [self persistActiveState];
}

- (NSPoint)pageViewPointForMinimapDocumentPoint:(NSPoint)documentPoint {
    return documentPoint;
}

- (NSPoint)windowPointForMinimapDocumentPoint:(NSPoint)documentPoint {
    NSPoint pageViewPoint = [self pageViewPointForMinimapDocumentPoint:documentPoint];
    return [_pageView convertPoint:pageViewPoint toView:nil];
}

- (void)minimapViewDidReceiveScrollWheel:(NSEvent*)event {
    if (!_pageScrollView) return;
    [_pageScrollView scrollWheel:event];
}

- (void)minimapViewDidReceiveZoomScrollWheel:(NSEvent*)event documentPoint:(NSPoint)documentPoint {
    if (!_pageView) return;
    [self zoomWithScrollWheelEvent:event centeredAtWindowPoint:[self windowPointForMinimapDocumentPoint:documentPoint]];
}

- (void)minimapViewDidReceiveMagnify:(NSEvent*)event documentPoint:(NSPoint)documentPoint {
    if (!_pageView) return;
    [self zoomWithMagnifyEvent:event centeredAtWindowPoint:[self windowPointForMinimapDocumentPoint:documentPoint]];
}

- (void)rememberActiveTabFindState {
    if (_selectedTabIndex < 0 || _selectedTabIndex >= (NSInteger)_tabs.count) return;
    SPDFDocumentTab* tab = _tabs[(NSUInteger)_selectedTabIndex];
    tab.searchText = _searchField.stringValue ?: @"";
    tab.searchRegex = _findRegexCheckbox.state == NSControlStateValueOn;
    tab.searchRegexMultiline = _findRegexMultiline;
    tab.findMatchIndex = _findMatchIndex;
}

- (void)rememberActiveTabState {
    if (_selectedTabIndex < 0 || _selectedTabIndex >= (NSInteger)_tabs.count) return;
    if (!_doc || !_path.length) return;
    SPDFDocumentTab* tab = _tabs[(NSUInteger)_selectedTabIndex];
    tab.path = _path;
    tab.title = spdf_display_name_for_path(_path) ?: tab.title;
    tab.pageIndex = _pageIndex;
    tab.zoom = _zoom;
    tab.customZoom = _rememberedCustomZoom > 0 ? _rememberedCustomZoom : _zoom;
    tab.fitMode = _fitMode;
    tab.viewMode = _viewMode;
    tab.scrollOrigin =
        [self normalizedDocumentScrollOrigin:_pageScrollView.contentView.bounds.origin forPageIndex:_pageIndex];
    tab.hasScrollOrigin = YES;
    [self rememberActiveTabFindState];
}

- (void)persistActiveState {
    [self rememberActiveTabState];
    [self savePersistentState];
}

- (NSInteger)indexOfTabForPath:(NSString*)path {
    NSString* standardized = path.stringByStandardizingPath;
    for (NSInteger i = 0; i < (NSInteger)_tabs.count; ++i) {
        NSString* tabPath = _tabs[(NSUInteger)i].path.stringByStandardizingPath;
        if ([tabPath isEqualToString:standardized]) return i;
    }
    return -1;
}

- (void)updateTabStrip {
    _tabStrip.tabs = _tabs;
    _tabStrip.selectedIndex = _selectedTabIndex;
    [self updateTabStripFrame];
}

- (void)updateTabStripFrame {
    if (!_tabStrip || !_window) return;
    BOOL fullScreen = (_window.styleMask & NSWindowStyleMaskFullScreen) == NSWindowStyleMaskFullScreen;
    CGFloat leadingInset = fullScreen ? 16.0 : 138.0;
    NSButton* zoomButton = fullScreen ? nil : [_window standardWindowButton:NSWindowZoomButton];
    if (zoomButton && _tabStrip.window) {
        NSRect buttonWindowRect = [zoomButton convertRect:zoomButton.bounds toView:nil];
        NSRect buttonRect = [_tabStrip convertRect:buttonWindowRect fromView:nil];
        if (NSMaxX(buttonRect) > 30.0 && NSMaxX(buttonRect) < NSWidth(_tabStrip.bounds) / 2.0)
            leadingInset = NSMaxX(buttonRect) + 18.0;
    }
    _tabStrip.reservedLeadingInset = leadingInset;
    [_tabStrip setNeedsDisplay:YES];
}

- (void)preloadInactiveTabs {
    [_preloadQueue cancelAllOperations];
    for (NSInteger i = 0; i < (NSInteger)_tabs.count; ++i) {
        if (i == _selectedTabIndex) continue;
        NSString* path = [_tabs[(NSUInteger)i].path copy];
        if (!path.length) continue;
        [_preloadQueue addOperationWithBlock:^{
          @autoreleasepool {
              char err[512];
              spdf_document* doc = spdf_open(path.fileSystemRepresentation, err, sizeof(err));
              [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                NSString* standardized = path.stringByStandardizingPath;
                BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:path];
                for (SPDFDocumentTab* tab in self->_tabs) {
                    if (![tab.path.stringByStandardizingPath isEqualToString:standardized]) continue;
                    tab.missingFile = doc == NULL && !fileExists;
                    tab.missingMessage =
                        doc ? @"" : (fileExists ? @"Could not open document" : @"File moved or deleted");
                    break;
                }
                [self updateTabStrip];
              }];
              if (doc) spdf_close(doc);
          }
        }];
    }
}

- (void)loadCommentsForCurrentDocumentAsync {
    if (!_path.length) return;
    NSString* path = [_path copy];
    [_preloadQueue addOperationWithBlock:^{
      @autoreleasepool {
          spdf_comments* comments = (spdf_comments*)calloc(1, sizeof(spdf_comments));
          if (!comments) return;
          char err[1024];
          spdf_document* doc = spdf_open(path.fileSystemRepresentation, err, sizeof(err));
          if (doc) {
              if (!spdf_load_comments(doc, comments, err, sizeof(err))) spdf_free_comments(comments);
              spdf_close(doc);
          }
          [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if ([self->_path.stringByStandardizingPath isEqualToString:path.stringByStandardizingPath]) {
                spdf_free_comments(&self->_comments);
                self->_comments = *comments;
                free(comments);
                [self rebuildSidebar];
                [self->_pageView setNeedsDisplay:YES];
            } else {
                spdf_free_comments(comments);
                free(comments);
            }
          }];
      }
    }];
}

- (void)schedulePostFirstPaintWorkForGeneration:(NSUInteger)generation
                                           path:(NSString*)path
                            savedFindMatchIndex:(NSInteger)savedFindMatchIndex
                                  restoreSearch:(BOOL)restoreSearch
                            preferredRenderPage:(NSInteger)preferredRenderPage {
    if (!path.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
      [self->_pageScrollView displayIfNeeded];
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAfterFirstPaintDelay * NSEC_PER_SEC)),
                     dispatch_get_main_queue(), ^{
                       if (generation != self->_renderGeneration || ![self->_path isEqualToString:path]) return;
                       [self enqueueNearbyPageRendersForGeneration:generation preferredPage:preferredRenderPage];
                       [self preloadInactiveTabs];
                       [self loadCommentsForCurrentDocumentAsync];
                       if (restoreSearch && self->_searchField.stringValue.length > 0) {
                           self->_pendingFindPreferredMatchIndex = savedFindMatchIndex;
                           self->_pendingFindPreferredPage = -1;
                           [self startFindForCurrentQueryResetSavedIndex:NO revealMatch:NO];
                       }
                     });
    });
}

- (NSArray<NSDictionary*>*)commentAnnotationsForPage:(NSInteger)pageIndex {
    if (_comments.count <= 0) return @[];
    NSMutableArray<NSDictionary*>* comments = [NSMutableArray array];
    for (int i = 0; i < _comments.count; ++i) {
        spdf_comment_item item = _comments.items[i];
        if (item.page_index != pageIndex) continue;
        CGFloat width = item.bounds.x1 - item.bounds.x0;
        CGFloat height = item.bounds.y1 - item.bounds.y0;
        if (width <= 0 || height <= 0) continue;
        NSString* author = item.author && *item.author ? [NSString stringWithUTF8String:item.author] : @"";
        NSString* type = item.type && *item.type ? [NSString stringWithUTF8String:item.type] : @"Comment";
        NSString* text = item.text && *item.text ? [NSString stringWithUTF8String:item.text] : type;
        NSString* title = author.length ? [NSString stringWithFormat:@"%@ - %@", author, type] : type;
        [comments addObject:@{
            @"title" : title,
            @"author" : author,
            @"text" : text,
            @"commentIndex" : @(item.index),
            @"bounds" : [NSValue valueWithRect:NSMakeRect(item.bounds.x0, item.bounds.y0, width, height)]
        }];
    }
    return comments;
}

- (void)documentViewHoverComment:(NSDictionary*)comment atWindowPoint:(NSPoint)windowPoint {
    NSString* title = comment[@"title"] ?: @"Comment";
    NSString* text = comment[@"text"] ?: @"";
    NSString* message = text.length ? [NSString stringWithFormat:@"%@\n%@", title, text] : title;
    if (!_commentPanel) {
        _commentPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 320, 88)
                                                   styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
        _commentPanel.releasedWhenClosed = NO;
        _commentPanel.hidesOnDeactivate = YES;
        _commentPanel.hasShadow = YES;
        _commentPanel.opaque = NO;
        _commentPanel.backgroundColor = NSColor.clearColor;

        NSVisualEffectView* bubble = [[NSVisualEffectView alloc] initWithFrame:_commentPanel.contentView.bounds];
        bubble.translatesAutoresizingMaskIntoConstraints = NO;
        bubble.material = NSVisualEffectMaterialPopover;
        bubble.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        bubble.state = NSVisualEffectStateActive;
        bubble.wantsLayer = YES;
        bubble.layer.cornerRadius = 9.0;
        bubble.layer.masksToBounds = YES;
        _commentPanel.contentView = bubble;

        _commentLabel = [NSTextField wrappingLabelWithString:@""];
        _commentLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _commentLabel.font = [NSFont systemFontOfSize:12];
        _commentLabel.textColor = NSColor.labelColor;
        [bubble addSubview:_commentLabel];
        [NSLayoutConstraint activateConstraints:@[
            [_commentLabel.leadingAnchor constraintEqualToAnchor:bubble.leadingAnchor constant:10],
            [_commentLabel.trailingAnchor constraintEqualToAnchor:bubble.trailingAnchor constant:-10],
            [_commentLabel.topAnchor constraintEqualToAnchor:bubble.topAnchor constant:8],
            [_commentLabel.bottomAnchor constraintEqualToAnchor:bubble.bottomAnchor constant:-8]
        ]];
    }

    _commentLabel.stringValue = message;
    CGFloat width = 340.0;
    NSRect textRect = [message boundingRectWithSize:NSMakeSize(width - 20.0, 220.0)
                                            options:NSStringDrawingUsesLineFragmentOrigin
                                         attributes:@{NSFontAttributeName : _commentLabel.font}];
    CGFloat height = MIN(230.0, MAX(38.0, ceil(NSHeight(textRect)) + 20.0));
    NSRect cursorScreen = [_window convertRectToScreen:NSMakeRect(windowPoint.x, windowPoint.y, 1, 1)];
    NSRect frame =
        NSMakeRect(floor(NSMinX(cursorScreen) + 14.0), floor(NSMinY(cursorScreen) - height - 12.0), width, height);
    [_commentPanel setFrame:frame display:NO];
    if (_commentPanel.parentWindow != _window) [_window addChildWindow:_commentPanel ordered:NSWindowAbove];
    [_commentPanel orderFront:nil];
}

- (void)documentViewEndHoverComment {
    [_commentPanel orderOut:nil];
}

- (NSPoint)visibleCenterWindowPoint {
    NSRect visible = _pageScrollView.contentView.bounds;
    NSPoint centerInPageView = NSMakePoint(NSMidX(visible), NSMidY(visible));
    return [_pageView convertPoint:centerInPageView toView:nil];
}

- (NSPoint)pagePointForViewPoint:(NSPoint)viewPoint pageRect:(NSRect)pageRect page:(SPDFRenderedPage*)page {
    CGFloat scaleX = NSWidth(pageRect) / MAX(1.0, page.pageWidth);
    CGFloat scaleY = NSHeight(pageRect) / MAX(1.0, page.pageHeight);
    return NSMakePoint((viewPoint.x - NSMinX(pageRect)) / MAX(0.001, scaleX),
                       (viewPoint.y - NSMinY(pageRect)) / MAX(0.001, scaleY));
}

- (NSPoint)viewPointForPagePoint:(NSPoint)pagePoint pageRect:(NSRect)pageRect page:(SPDFRenderedPage*)page {
    CGFloat scaleX = NSWidth(pageRect) / MAX(1.0, page.pageWidth);
    CGFloat scaleY = NSHeight(pageRect) / MAX(1.0, page.pageHeight);
    return NSMakePoint(NSMinX(pageRect) + pagePoint.x * scaleX, NSMinY(pageRect) + pagePoint.y * scaleY);
}

- (SPDFPageAnchor)pageAnchorForWindowPoint:(NSPoint)windowPoint {
    SPDFPageAnchor anchor;
    memset(&anchor, 0, sizeof(anchor));
    anchor.pageIndex = -1;
    if (!_doc || _renderedPages.count == 0) return anchor;

    NSClipView* clipView = _pageScrollView.contentView;
    NSPoint viewPoint = [_pageView convertPoint:windowPoint fromView:nil];
    NSInteger pageIndex = -1;
    NSPoint pagePoint = NSZeroPoint;
    if ([_pageView point:viewPoint fallsInPage:&pageIndex pagePoint:&pagePoint]) {
        anchor.pageIndex = pageIndex;
        anchor.pagePoint = pagePoint;
        anchor.offsetInViewport =
            NSMakePoint(viewPoint.x - NSMinX(clipView.bounds), viewPoint.y - NSMinY(clipView.bounds));
        anchor.valid = YES;
        return anchor;
    }

    NSRect visible = clipView.bounds;
    pageIndex = _viewMode == SPDFViewModeSingle ? _pageIndex : [_pageView pageIndexForVisibleRect:visible];
    pageIndex = MAX(0, MIN(pageIndex, (NSInteger)_renderedPages.count - 1));
    NSRect pageRect = [_pageView rectForPageAtIndex:pageIndex];
    if (NSIsEmptyRect(pageRect)) return anchor;
    SPDFRenderedPage* page = _renderedPages[(NSUInteger)pageIndex];
    NSPoint center = NSMakePoint(spdf_clamp_cg(NSMidX(visible), NSMinX(pageRect), NSMaxX(pageRect)),
                                 spdf_clamp_cg(NSMidY(visible), NSMinY(pageRect), NSMaxY(pageRect)));
    anchor.pageIndex = pageIndex;
    anchor.pagePoint = [self pagePointForViewPoint:center pageRect:pageRect page:page];
    anchor.offsetInViewport = NSMakePoint(center.x - NSMinX(visible), center.y - NSMinY(visible));
    anchor.valid = YES;
    return anchor;
}

- (void)scrollToPageAnchor:(SPDFPageAnchor)anchor notify:(BOOL)notify {
    if (!anchor.valid || anchor.pageIndex < 0 || anchor.pageIndex >= (NSInteger)_renderedPages.count) return;
    NSRect pageRect = [_pageView rectForPageAtIndex:anchor.pageIndex];
    if (NSIsEmptyRect(pageRect)) return;
    SPDFRenderedPage* page = _renderedPages[(NSUInteger)anchor.pageIndex];
    NSPoint viewPoint = [self viewPointForPagePoint:anchor.pagePoint pageRect:pageRect page:page];
    NSPoint origin = NSMakePoint(viewPoint.x - anchor.offsetInViewport.x, viewPoint.y - anchor.offsetInViewport.y);
    [self scrollDocumentClipViewToOrigin:[self clampedDocumentScrollOrigin:origin forPageIndex:anchor.pageIndex]
                                  notify:notify];
}

- (BOOL)zoomWithScrollWheelEvent:(NSEvent*)event centeredAtWindowPoint:(NSPoint)windowPoint {
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    if (!(flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl))) return NO;

    CGFloat delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY;
    CGFloat factor = pow(1.00135, delta);
    [self beginLiveZoomByFactor:factor centeredAtWindowPoint:windowPoint];
    return YES;
}

- (void)zoomWithMagnifyEvent:(NSEvent*)event centeredAtWindowPoint:(NSPoint)windowPoint {
    [self beginLiveZoomByFactor:1.0 + event.magnification * 0.82 centeredAtWindowPoint:windowPoint];
}

- (void)zoomByFactor:(CGFloat)factor centeredAtWindowPoint:(NSPoint)windowPoint {
    if (!_doc || factor <= 0) return;

    SPDFPageAnchor anchor = [self pageAnchorForWindowPoint:windowPoint];
    CGFloat oldZoom = _zoom;

    _fitMode = SPDFFitModeCustom;
    _zoom = MAX(kMinZoom, MIN(kMaxZoom, _zoom * factor));
    if (fabs(_zoom - oldZoom) < 0.0001) return;
    _rememberedCustomZoom = _zoom;

    [self renderDocumentAndScrollToPage:_pageIndex
                               alignTop:NO
                          restoreOrigin:[NSValue valueWithPoint:_pageScrollView.contentView.bounds.origin]];
    [self scrollToPageAnchor:anchor notify:YES];
    [self persistActiveState];
}

- (void)setZoomWithoutRendering:(CGFloat)newZoom centeredAtWindowPoint:(NSPoint)windowPoint {
    if (!_doc) return;
    CGFloat oldZoom = _zoom > 0 ? _zoom : 1.0;
    SPDFPageAnchor anchor = [self pageAnchorForWindowPoint:windowPoint];
    _zoom = MAX(kMinZoom, MIN(kMaxZoom, newZoom));
    _rememberedCustomZoom = _zoom;
    if (fabs(_zoom - oldZoom) < 0.0001) return;
    _pageView.backingScale = [self backingScale];
    _pageView.zoom = _zoom;
    [self resizeDocumentView];
    [self scrollToPageAnchor:anchor notify:NO];
    [self syncToolbarState];
    [self updateControls];
    [self documentScrollPositionChanged];
}

- (void)renderDocumentPreservingScrollPosition {
    if (!_doc) return;
    NSClipView* clipView = _pageScrollView.contentView;
    NSPoint origin = clipView.bounds.origin;
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO restoreOrigin:[NSValue valueWithPoint:origin]];
}

- (void)finishLiveZoom:(NSTimer*)timer {
    (void)timer;
    _zoomFinishTimer = nil;
    if (_doc) {
        [self renderDocumentPreservingScrollPosition];
        [self persistActiveState];
    }
}

- (void)beginLiveZoomByFactor:(CGFloat)factor centeredAtWindowPoint:(NSPoint)windowPoint {
    if (!_doc || factor <= 0) return;
    _fitMode = SPDFFitModeCustom;
    [self setZoomWithoutRendering:_zoom * factor centeredAtWindowPoint:windowPoint];
    [_zoomFinishTimer invalidate];
    _zoomFinishTimer = [NSTimer scheduledTimerWithTimeInterval:0.18
                                                        target:self
                                                      selector:@selector(finishLiveZoom:)
                                                      userInfo:nil
                                                       repeats:NO];
}

- (void)openDocument:(id)sender {
    (void)sender;
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.allowedContentTypes = spdf_document_content_types();
    if ([panel runModal] == NSModalResponseOK) [self openPath:panel.URL.path];
}

- (void)loadSelectedTab {
    if (_selectedTabIndex < 0 || _selectedTabIndex >= (NSInteger)_tabs.count) return;
    [self clearToolbarFieldFocusForTabSwitch];
    SPDFDocumentTab* tab = _tabs[(NSUInteger)_selectedTabIndex];
    if (!tab.path.length) return;
    NSString* path = tab.path;
    NSInteger savedFindMatchIndex = tab.findMatchIndex;
    [_renderQueue cancelAllOperations];
    [_queuedRenderPages removeAllObjects];

    char err[1024];
    spdf_document* newDoc = spdf_open(path.fileSystemRepresentation, err, sizeof(err));
    if (!newDoc) {
        BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:path];
        NSString* message = fileExists ? @"Could not open document" : @"File moved or deleted";
        tab.missingFile = !fileExists;
        tab.missingMessage = message;
        [_renderQueue cancelAllOperations];
        [_queuedRenderPages removeAllObjects];
        spdf_free_outline(&_outline);
        spdf_free_comments(&_comments);
        spdf_close(_doc);
        _doc = NULL;
        _path = [path copy];
        _pageIndex = 0;
        _highlightPageIndex = -1;
        _selectionPageIndex = -1;
        _selectedText = nil;
        _searchField.stringValue = tab.searchText ?: @"";
        _findRegexCheckbox.state = tab.searchRegex ? NSControlStateValueOn : NSControlStateValueOff;
        _findRegexMultiline = tab.searchRegexMultiline;
        [self clearFindResults];
        _renderGeneration++;
        [_renderedPages removeAllObjects];
        [self replaceDocumentViewForTabSwitch];
        [self rebuildSidebar];
        [self showEmptyDocumentViewWithMessage:message];
        _window.title = [NSString stringWithFormat:@"%@ - %@ - SumatraPDF", spdf_display_name_for_path(path), message];
        _statusLabel.stringValue = [message stringByAppendingString:@"."];
        [self updateTabStrip];
        [self updateControls];
        [self clearToolbarFieldFocusForTabSwitch];
        [self savePersistentState];
        if (fileExists)
            [self showError:@"Could not open document"
                     detail:[NSString stringWithUTF8String:err[0] ? err : "Unknown error"]];
        return;
    }

    tab.missingFile = NO;
    tab.missingMessage = @"";

    spdf_free_outline(&_outline);
    spdf_free_comments(&_comments);
    spdf_close(_doc);
    _doc = newDoc;
    _path = [path copy];
    _pageIndex = MAX(0, MIN(tab.pageIndex, spdf_page_count(_doc) - 1));
    _highlightPageIndex = -1;
    _selectionPageIndex = -1;
    _selectedText = nil;
    _searchField.stringValue = tab.searchText ?: @"";
    _findRegexCheckbox.state = tab.searchRegex ? NSControlStateValueOn : NSControlStateValueOff;
    _findRegexMultiline = tab.searchRegexMultiline;
    [self clearFindResults];
    _renderGeneration++;
    _zoom = tab.zoom > 0 ? tab.zoom : 1.0;
    _rememberedCustomZoom = tab.customZoom > 0 ? tab.customZoom : _zoom;
    _fitMode = tab.fitMode;
    _viewMode = tab.viewMode;
    _statusLabel.stringValue = @"Opening...";
    NSClipView* clipView = _pageScrollView.contentView;
    BOOL previousHidden = _pageScrollView.hidden;
    BOOL previousPostsBoundsChangedNotifications = clipView.postsBoundsChangedNotifications;
    BOOL previousSuppressScrollCallbacks = _suppressScrollCallbacks;
    _suppressScrollCallbacks = YES;
    _pageScrollView.hidden = YES;
    clipView.postsBoundsChangedNotifications = NO;
    [self replaceDocumentViewForTabSwitch];
    _pageView.emptyMessage = @"Open a document";
    if (_presentationMode)
        _pageScrollView.verticalScroller = nil;
    else if (_pageScrollView.verticalScroller != _markerScroller)
        _pageScrollView.verticalScroller = _markerScroller;
    _pageScrollView.hasVerticalScroller = !_presentationMode;
    [self setMinimapActuallyVisible:_minimapPreferredVisible];
    tab.title = spdf_display_name_for_path(_path);

    char outlineErr[1024];
    if (_doc && !spdf_load_outline(_doc, &_outline, outlineErr, sizeof(outlineErr)))
        _statusLabel.stringValue = [NSString stringWithFormat:@"Opened, but outline was not available: %s", outlineErr];

    [self rebuildSidebar];
    [self updateTabStrip];
    [self savePersistentState];
    NSValue* restoreOrigin = tab.hasScrollOrigin ? [NSValue valueWithPoint:tab.scrollOrigin] : nil;
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:YES restoreOrigin:restoreOrigin];
    NSUInteger layoutGeneration = _renderGeneration;
    NSString* layoutPath = [_path copy];
    clipView.postsBoundsChangedNotifications = previousPostsBoundsChangedNotifications;
    _pageScrollView.hidden = previousHidden;
    [self stabilizeDocumentLayoutWithRestoreOrigin:restoreOrigin
                                          alignTop:YES
                                        generation:layoutGeneration
                                              path:layoutPath];
    _suppressScrollCallbacks = previousSuppressScrollCallbacks;
    [self stabilizeDocumentLayoutWithRestoreOrigin:restoreOrigin
                                          alignTop:YES
                                        generation:layoutGeneration
                                              path:layoutPath];
    dispatch_async(dispatch_get_main_queue(), ^{
      [self stabilizeDocumentLayoutWithRestoreOrigin:restoreOrigin
                                            alignTop:YES
                                          generation:layoutGeneration
                                                path:layoutPath];
    });
    [self schedulePostFirstPaintWorkForGeneration:layoutGeneration
                                             path:layoutPath
                              savedFindMatchIndex:savedFindMatchIndex
                                    restoreSearch:_searchField.stringValue.length > 0
                              preferredRenderPage:_pageIndex];
    [self clearToolbarFieldFocusForTabSwitch];
}

- (void)closeDocument:(id)sender {
    (void)sender;
    if (_selectedTabIndex >= 0) {
        [self closeTabAtIndex:_selectedTabIndex];
        return;
    }
    spdf_free_outline(&_outline);
    spdf_free_comments(&_comments);
    spdf_close(_doc);
    _doc = NULL;
    _path = nil;
    _pageIndex = 0;
    _highlightPageIndex = -1;
    _selectionPageIndex = -1;
    _selectedText = nil;
    _searchField.stringValue = @"";
    _findRegexCheckbox.state = NSControlStateValueOff;
    _findRegexMultiline = YES;
    [self clearFindResults];
    _renderGeneration++;
    [_renderedPages removeAllObjects];
    _window.title = @"SumatraPDF";
    _statusLabel.stringValue = @"Ready";
    [self rebuildSidebar];
    [self showEmptyDocumentViewWithMessage:@"Open a document"];
    [self updateControls];
}

- (void)openPath:(NSString*)path {
    if (!_uiReady || !_window) {
        _pendingOpenPath = [path copy];
        return;
    }

    NSInteger existing = [self indexOfTabForPath:path];
    if (existing >= 0) {
        [self selectTabAtIndex:existing];
        return;
    }

    [self rememberActiveTabState];
    SPDFDocumentTab* tab = [[SPDFDocumentTab alloc] init];
    tab.path = [path copy];
    tab.title = spdf_display_name_for_path(path);
    tab.zoom = _zoom > 0 ? _zoom : 1.0;
    tab.customZoom = _rememberedCustomZoom > 0 ? _rememberedCustomZoom : tab.zoom;
    tab.fitMode = _fitMode;
    tab.viewMode = _viewMode;
    tab.searchText = @"";
    tab.searchRegex = NO;
    tab.searchRegexMultiline = YES;
    tab.findMatchIndex = -1;
    [_tabs addObject:tab];
    _selectedTabIndex = (NSInteger)_tabs.count - 1;
    [self loadSelectedTab];
    [self savePersistentState];
}

- (void)selectTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_tabs.count || (index == _selectedTabIndex && _doc)) return;
    [self clearToolbarFieldFocusForTabSwitch];
    [self rememberActiveTabState];
    _selectedTabIndex = index;
    [self loadSelectedTab];
    [self savePersistentState];
}

- (void)closeTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_tabs.count) return;
    BOOL closingActive = index == _selectedTabIndex;
    [_tabs removeObjectAtIndex:(NSUInteger)index];
    if (!closingActive && index < _selectedTabIndex) _selectedTabIndex--;

    if (_tabs.count == 0) {
        [self clearToolbarFieldFocusForTabSwitch];
        _selectedTabIndex = -1;
        spdf_free_outline(&_outline);
        spdf_free_comments(&_comments);
        spdf_close(_doc);
        _doc = NULL;
        _path = nil;
        _pageIndex = 0;
        _selectedText = nil;
        _searchField.stringValue = @"";
        _findRegexCheckbox.state = NSControlStateValueOff;
        _findRegexMultiline = YES;
        [self clearFindResults];
        _renderGeneration++;
        [_renderedPages removeAllObjects];
        [self rebuildSidebar];
        [self showEmptyDocumentViewWithMessage:@"Open a document"];
        _window.title = @"SumatraPDF";
        _statusLabel.stringValue = @"Ready";
        [self updateTabStrip];
        [self updateControls];
        [self clearToolbarFieldFocusForTabSwitch];
        [self savePersistentState];
        return;
    }

    if (closingActive) {
        _selectedTabIndex = MIN(index, (NSInteger)_tabs.count - 1);
        [self loadSelectedTab];
    } else {
        [self updateTabStrip];
        [self preloadInactiveTabs];
        [self savePersistentState];
    }
}

- (void)newTabRequested:(id)sender {
    [self openDocument:sender];
}

- (BOOL)openFilesFromPasteboard:(NSPasteboard*)pasteboard {
    NSArray<NSURL*>* urls =
        [pasteboard readObjectsForClasses:@[ [NSURL class] ] options:@{NSPasteboardURLReadingFileURLsOnlyKey : @YES}];
    BOOL opened = NO;
    for (NSURL* url in urls) {
        NSString* ext = url.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"pdf"] || [ext isEqualToString:@"xps"] || [ext isEqualToString:@"cbz"] ||
            [ext isEqualToString:@"epub"]) {
            [self openPath:url.path];
            opened = YES;
        }
    }
    return opened;
}

- (SPDFDocumentView*)newDocumentView {
    SPDFDocumentView* view = [[SPDFDocumentView alloc] initWithFrame:NSMakeRect(0, 0, 800, 1000)];
    view.reader = self;
    [view registerForDraggedTypes:@[ NSPasteboardTypeFileURL ]];
    view.viewMode = _viewMode;
    view.zoom = _zoom;
    view.currentPageIndex = _pageIndex;
    view.backingScale = [self backingScale];
    view.viewportWidthHint = MAX(1.0, _pageScrollView.contentSize.width);
    view.activeFindPageIndex = -1;
    view.emptyMessage = @"Open a document";
    return view;
}

- (void)replaceDocumentViewForTabSwitch {
    [_pageView cancelTransientInteraction];
    [self clearToolbarFieldFocusForTabSwitch];
    NSClipView* clipView = _pageScrollView.contentView;
    BOOL previousPostsBoundsChangedNotifications = clipView.postsBoundsChangedNotifications;
    clipView.postsBoundsChangedNotifications = NO;
    _pageScrollView.documentView = nil;
    _pageView = [self newDocumentView];
    _pageScrollView.documentView = _pageView;
    clipView.postsBoundsChangedNotifications = previousPostsBoundsChangedNotifications;
    [self clearToolbarFieldFocusForTabSwitch];
}

- (CGFloat)clampedSidebarWidth {
    return spdf_sane_sidebar_width(_sidebarWidth, _splitView ? NSWidth(_splitView.bounds) : 0);
}

- (BOOL)currentSidebarFrameIsPersistable {
    if (!_splitView || !_sidebarContainer) return NO;
    CGFloat width = NSWidth(_sidebarContainer.frame);
    CGFloat maxWidth = spdf_max_sidebar_width_for_container(NSWidth(_splitView.bounds));
    return isfinite(width) && width >= kMinSidebarWidth - 1.0 && width <= maxWidth + 1.0;
}

- (void)normalizeSidebarModeControlWidths {
    if (!_sidebarVisible || !_sidebarContainer || !_sidebarModeControl) return;
    CGFloat controlWidth = NSWidth(_sidebarContainer.bounds) - 16.0;
    if (!isfinite(controlWidth) || controlWidth < 160.0) controlWidth = [self clampedSidebarWidth] - 16.0;
    CGFloat segmentWidth = floor(MAX(78.0, controlWidth / 2.0));
    [_sidebarModeControl setWidth:segmentWidth forSegment:SPDFSidebarModeChapters];
    [_sidebarModeControl setWidth:segmentWidth forSegment:SPDFSidebarModeComments];
    [_sidebarModeControl invalidateIntrinsicContentSize];
    [_sidebarModeControl setNeedsLayout:YES];
}

- (void)restoreSidebarWidth {
    if (!_splitView || !_sidebarContainer || !_sidebarVisible || _splitView.subviews.count < 2) return;
    _sidebarWidth = [self clampedSidebarWidth];
    _restoringSidebarLayout = YES;
    _sidebarContainer.hidden = NO;
    [_splitView layoutSubtreeIfNeeded];
    [_splitView setPosition:_sidebarWidth ofDividerAtIndex:0];
    [_splitView layoutSubtreeIfNeeded];
    [self normalizeSidebarModeControlWidths];
    _restoringSidebarLayout = NO;
}

- (void)setSidebarActuallyVisible:(BOOL)visible {
    if (!_splitView || !_sidebarContainer || !_documentContainer) return;
    if (![_splitView.subviews containsObject:_sidebarContainer])
        [_splitView addSubview:_sidebarContainer positioned:NSWindowBelow relativeTo:_documentContainer];
    _sidebarContainer.hidden = NO;
    if (visible == _sidebarVisible) {
        [self syncToolbarState];
        [self updateControls];
        return;
    }

    _restoringSidebarLayout = YES;
    if (visible) {
        _sidebarVisible = YES;
        [_splitView layoutSubtreeIfNeeded];
        [_splitView setPosition:[self clampedSidebarWidth] ofDividerAtIndex:0];
        [_splitView layoutSubtreeIfNeeded];
        [self normalizeSidebarModeControlWidths];
    } else {
        if (_allowSidebarWidthPersistence && [self currentSidebarFrameIsPersistable])
            _sidebarWidth = spdf_sane_sidebar_width(NSWidth(_sidebarContainer.frame), NSWidth(_splitView.bounds));
        _sidebarVisible = NO;
        [_splitView layoutSubtreeIfNeeded];
        if (_splitView.subviews.count >= 2) [_splitView setPosition:0.0 ofDividerAtIndex:0];
    }
    [_splitView layoutSubtreeIfNeeded];
    _restoringSidebarLayout = NO;
    [_splitView layoutSubtreeIfNeeded];
    if (_doc) [self resizeDocumentView];
    [self syncToolbarState];
    [self updateControls];
}

- (void)setMinimapActuallyVisible:(BOOL)visible {
    if (!_minimapView || !_minimapWidthConstraint || !_minimapDividerView) {
        [self syncToolbarState];
        return;
    }
    BOOL actualVisible = visible && _doc != NULL;
    BOOL constraintsMatch = actualVisible
                                ? (!_pageScrollFullWidthConstraint.active && _pageScrollToMinimapConstraint.active)
                                : (_pageScrollFullWidthConstraint.active && !_pageScrollToMinimapConstraint.active);
    if (actualVisible == _minimapVisible && _minimapWidthConstraint.constant == (actualVisible ? _minimapWidth : 0.0) &&
        constraintsMatch) {
        [self syncToolbarState];
        return;
    }
    _minimapVisible = actualVisible;
    _minimapView.hidden = !actualVisible;
    _minimapDividerView.hidden = !actualVisible;
    _minimapWidthConstraint.constant = actualVisible ? _minimapWidth : 0.0;
    _minimapDividerWidthConstraint.constant = actualVisible ? kMinimapDividerWidth : 0.0;
    if (actualVisible) {
        _pageScrollFullWidthConstraint.active = NO;
        _pageScrollToMinimapConstraint.active = YES;
    } else {
        _pageScrollToMinimapConstraint.active = NO;
        _pageScrollFullWidthConstraint.active = YES;
    }
    [_documentContainer layoutSubtreeIfNeeded];
    if (_doc) [self resizeDocumentView];
    [self updateMinimap];
    [self syncToolbarState];
}

- (void)minimapDividerDraggedByDeltaX:(CGFloat)deltaX {
    if (!_minimapPreferredVisible || !_minimapVisible) return;
    CGFloat maxWidth = MAX(120.0, MIN(320.0, NSWidth(_documentContainer.bounds) * 0.35));
    _minimapWidth = spdf_clamp_cg(_minimapWidth - deltaX, 72.0, maxWidth);
    _minimapWidthConstraint.constant = _minimapWidth;
    [_documentContainer layoutSubtreeIfNeeded];
    [self resizeDocumentView];
    [self updateMinimap];
}

- (void)minimapDividerDidFinishDragging {
    [self savePersistentState];
    if (_doc && (_fitMode == SPDFFitModeWidth || _fitMode == SPDFFitModeHeight || _fitMode == SPDFFitModePage))
        [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO];
}

- (CGFloat)splitView:(NSSplitView*)splitView
    constrainMinCoordinate:(CGFloat)proposedMinimumPosition
               ofSubviewAt:(NSInteger)dividerIndex {
    (void)proposedMinimumPosition;
    (void)dividerIndex;
    if (splitView == _splitView) return _sidebarVisible ? kMinSidebarWidth : 0.0;
    return proposedMinimumPosition;
}

- (CGFloat)splitView:(NSSplitView*)splitView
    constrainMaxCoordinate:(CGFloat)proposedMaximumPosition
               ofSubviewAt:(NSInteger)dividerIndex {
    (void)proposedMaximumPosition;
    (void)dividerIndex;
    if (splitView == _splitView) return spdf_max_sidebar_width_for_container(NSWidth(splitView.bounds));
    return proposedMaximumPosition;
}

- (BOOL)splitView:(NSSplitView*)splitView shouldAdjustSizeOfSubview:(NSView*)view {
    if (splitView == _splitView) return view == _documentContainer;
    return YES;
}

- (void)splitViewDidResizeSubviews:(NSNotification*)notification {
    if (notification.object != _splitView || !_sidebarVisible) return;
    [self normalizeSidebarModeControlWidths];
    if (_doc) [self resizeDocumentView];
    if (_restoringSidebarLayout || !_allowSidebarWidthPersistence) return;
    if ((NSEvent.pressedMouseButtons & 1) == 0) return;
    CGFloat width = NSWidth(_sidebarContainer.frame);
    if ([self currentSidebarFrameIsPersistable])
        _sidebarWidth = spdf_sane_sidebar_width(width, NSWidth(_splitView.bounds));
}

- (void)rebuildSidebar {
    [_sidebarItems removeAllObjects];
    BOOL hasChapters = _outline.count > 0;
    BOOL hasComments = _comments.count > 0;
    BOOL hasSidebar = _doc && (hasChapters || hasComments);

    [_sidebarModeControl setEnabled:hasChapters forSegment:SPDFSidebarModeChapters];
    [_sidebarModeControl setEnabled:hasComments forSegment:SPDFSidebarModeComments];
    if (hasChapters && !hasComments)
        _sidebarModeControl.selectedSegment = SPDFSidebarModeChapters;
    else if (!hasChapters && hasComments)
        _sidebarModeControl.selectedSegment = SPDFSidebarModeComments;
    else if (!hasChapters && !hasComments)
        _sidebarModeControl.selectedSegment = SPDFSidebarModeChapters;

    if (hasSidebar) {
        if (_sidebarModeControl.selectedSegment == SPDFSidebarModeComments && hasComments) {
            for (int i = 0; i < _comments.count; ++i) {
                spdf_comment_item item = _comments.items[i];
                NSString* type = item.type && *item.type ? [NSString stringWithUTF8String:item.type] : @"Comment";
                NSString* author = item.author && *item.author ? [NSString stringWithUTF8String:item.author] : @"";
                NSString* text = item.text && *item.text ? [NSString stringWithUTF8String:item.text] : @"";
                NSString* title = text.length ? text : type;
                if (author.length) title = [NSString stringWithFormat:@"%@: %@", author, title];
                CGFloat width = item.bounds.x1 - item.bounds.x0;
                CGFloat height = item.bounds.y1 - item.bounds.y0;
                NSMutableDictionary* sidebarItem = [@{
                    @"title" : title ?: @"Comment",
                    @"page" : @(item.page_index),
                    @"level" : @0,
                    @"kind" : @"comment",
                    @"commentIndex" : @(item.index)
                } mutableCopy];
                if (width > 0 && height > 0) {
                    sidebarItem[@"bounds"] =
                        [NSValue valueWithRect:NSMakeRect(item.bounds.x0, item.bounds.y0, width, height)];
                }
                [_sidebarItems addObject:sidebarItem];
            }
        } else if (hasChapters) {
            for (int i = 0; i < _outline.count; ++i) {
                spdf_outline_item item = _outline.items[i];
                NSString* title = item.title ? [NSString stringWithUTF8String:item.title] : @"Untitled";
                [_sidebarItems addObject:@{
                    @"title" : title ?: @"Untitled",
                    @"page" : @(item.page_index),
                    @"level" : @(MAX(0, item.level)),
                    @"kind" : @"chapter"
                }];
            }
        }
    }
    [_sidebarTable reloadData];
    [self setSidebarActuallyVisible:hasSidebar && _sidebarPreferredVisible];
    if (hasSidebar && _sidebarVisible) [self restoreSidebarWidth];
    if (!hasSidebar) return;
    [self selectCurrentSidebarRow];
}

- (void)sidebarModeChanged:(id)sender {
    (void)sender;
    [self rebuildSidebar];
}

- (void)clipViewBoundsChanged:(NSNotification*)notification {
    (void)notification;
    if (_suppressScrollCallbacks) return;
    [self documentScrollPositionChanged];
}

- (void)documentScrollPositionChanged {
    if (_suppressScrollCallbacks) return;
    if (_renderedPages.count == 0) {
        [self updateMinimap];
        return;
    }
    if (!_updatingFromScroll) {
        NSInteger visiblePage = [_pageView pageIndexForVisibleRect:_pageScrollView.contentView.bounds];
        if (visiblePage != _pageIndex) {
            _pageIndex = visiblePage;
            _pageView.currentPageIndex = _pageIndex;
            [self clearPageFieldFocus];
            if (_viewMode == SPDFViewModeSingle) {
                [self renderPageIfNeededAtIndex:_pageIndex];
                [_pageView setNeedsDisplay:YES];
            }
            [self enqueueNearbyPageRendersForGeneration:_renderGeneration preferredPage:_pageIndex];
            [self updateControls];
            [self selectCurrentSidebarRow];
        }
    }
    [self updateMinimap];
}

- (BOOL)documentArrowKeyDown:(NSEvent*)event {
    if (!_doc) return NO;
    if (_presentationMode && event.keyCode == 53) {
        [self leavePresentationModeAndExitFullScreen:YES sender:nil];
        return YES;
    }
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    if (flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) return NO;

    BOOL space = event.keyCode == 49;
    BOOL left = event.keyCode == 123;
    BOOL right = event.keyCode == 124;
    BOOL down = event.keyCode == 125;
    BOOL up = event.keyCode == 126;
    if (_presentationMode && space) {
        [self nextPage:nil];
        return YES;
    }
    if (!left && !right && !down && !up) return NO;

    if (_presentationMode || _viewMode == SPDFViewModeSingle) {
        if (left || up)
            [self previousPage:nil];
        else
            [self nextPage:nil];
        return YES;
    }

    NSClipView* clipView = _pageScrollView.contentView;
    NSPoint origin = clipView.bounds.origin;
    CGFloat lineStep = 54.0;
    if (up) origin.y -= lineStep;
    if (down) origin.y += lineStep;
    if (left) origin.x -= lineStep;
    if (right) origin.x += lineStep;
    [self scrollDocumentClipViewToOrigin:origin notify:YES];
    [self rememberActiveTabState];
    return YES;
}

- (BOOL)scrollViewShouldTurnWheelIntoPageChange:(NSEvent*)event {
    (void)event;
    if (!_doc) return NO;
    return _viewMode == SPDFViewModeSingle || _fitMode == SPDFFitModeHeight || _fitMode == SPDFFitModePage;
}

- (void)syncToolbarState {
    CGFloat customZoom =
        _fitMode == SPDFFitModeCustom ? _zoom : (_rememberedCustomZoom > 0 ? _rememberedCustomZoom : _zoom);
    NSString* zoomTitle = [NSString stringWithFormat:@"%.0f%%", customZoom * 100.0];
    [_fitModePopup itemAtIndex:SPDFFitModeCustom].title = zoomTitle;
    [_fitModePopup itemAtIndex:SPDFFitModeActual].title = @"100%";
    [_fitModePopup selectItemAtIndex:_fitMode];
    _continuousButton.state = _viewMode == SPDFViewModeContinuous ? NSControlStateValueOn : NSControlStateValueOff;
    [self styleToolbarPanelButton:_sidebarToggleButton
                            title:@"Side Panel"
                           active:_sidebarVisible
                          tooltip:_sidebarVisible ? @"Hide the side panel" : @"Show the side panel"];
    [self styleToolbarPanelButton:_minimapToggleButton
                            title:@"Map"
                           active:_minimapVisible
                          tooltip:_minimapVisible ? @"Hide the minimap" : @"Show the minimap"];
    _tabStrip.tabs = _tabs;
    _tabStrip.selectedIndex = _selectedTabIndex;
    [self updateToolbarOverflow];
}

- (void)updateControls {
    NSInteger pageCount = spdf_page_count(_doc);
    BOOL hasDoc = _doc != NULL;
    _prevButton.enabled = hasDoc && _pageIndex > 0;
    _nextButton.enabled = hasDoc && _pageIndex + 1 < pageCount;
    _sidebarToggleButton.enabled = hasDoc;
    _pageField.enabled = hasDoc;
    _zoomOutButton.enabled = hasDoc;
    _zoomInButton.enabled = hasDoc;
    _fitModePopup.enabled = hasDoc;
    _continuousButton.enabled = hasDoc;
    _searchField.enabled = hasDoc;
    _findRegexCheckbox.enabled = hasDoc;
    _ocrButton.enabled = hasDoc && [_path.pathExtension.lowercaseString isEqualToString:@"pdf"];
    _minimapToggleButton.enabled = hasDoc;
    [self updateFindControls];
    _pageField.stringValue = hasDoc ? [NSString stringWithFormat:@"%ld", (long)_pageIndex + 1] : @"";
    _pageCountLabel.stringValue = [NSString stringWithFormat:@"/ %ld", (long)pageCount];
    [self syncToolbarState];

    if (hasDoc) {
        NSString* displayName =
            _path.length ? spdf_display_name_for_path(_path) : [NSString stringWithUTF8String:spdf_title(_doc)];
        _window.title = [NSString stringWithFormat:@"%@ - SumatraPDF", displayName];
        NSString* mode = _viewMode == SPDFViewModeContinuous ? @"Continuous" : @"Single page";
        _statusLabel.stringValue =
            [NSString stringWithFormat:@"Page %ld of %ld    Zoom %.0f%%    %@", (long)_pageIndex + 1, (long)pageCount,
                                       _zoom * 100.0, mode];
    }
    [self updateToolbarOverflow];
}

- (void)selectCurrentSidebarRow {
    if (!_doc || _updatingSelection) return;
    _updatingSelection = YES;
    NSInteger match = -1;
    for (NSInteger i = 0; i < _sidebarItems.count; ++i) {
        NSInteger page = [_sidebarItems[(NSUInteger)i][@"page"] integerValue];
        if (page == _pageIndex) {
            match = i;
            break;
        }
    }
    if (match >= 0) {
        [_sidebarTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)match] byExtendingSelection:NO];
        [_sidebarTable scrollRowToVisible:match];
    }
    _updatingSelection = NO;
}

- (void)updateFindCountLabel {
    if (!_findCountLabel) return;
    if (!_doc || _searchField.stringValue.length == 0) {
        _findCountLabel.stringValue = @"";
        return;
    }
    if (_findSearchInProgress) {
        _findCountLabel.stringValue = @"...";
        return;
    }
    if (_findMatches.count == 0) {
        _findCountLabel.stringValue = @"0 / 0";
        return;
    }
    NSInteger current = _findMatchIndex >= 0 ? _findMatchIndex + 1 : 1;
    _findCountLabel.stringValue = [NSString stringWithFormat:@"%ld / %ld", (long)current, (long)_findMatches.count];
}

- (void)updateFindControls {
    BOOL hasMatches = _findMatches.count > 0;
    BOOL hasQuery = _searchField.stringValue.length > 0;
    _findPrevButton.hidden = !hasQuery;
    _findNextButton.hidden = !hasQuery;
    _findCountLabel.hidden = !hasQuery;
    _findPrevButton.enabled = hasMatches;
    _findNextButton.enabled = hasMatches;
    [self updateFindCountLabel];
    [self invalidateFindMarkers];
}

- (void)clearFindResults {
    [_findQueue cancelAllOperations];
    _findGeneration++;
    [_findFlashTimer invalidate];
    _findFlashTimer = nil;
    _pageView.activeFindPageIndex = -1;
    _pageView.activeFindAlpha = 0.0;
    [_findHighlights removeAllObjects];
    [_findMatches removeAllObjects];
    _findMatchIndex = -1;
    _findSearchInProgress = NO;
    [self applySearchHighlightsToCurrentPage];
    [self updateFindControls];
}

- (NSArray<NSValue*>*)highlightRectsForPage:(NSInteger)pageIndex {
    if (!_doc || _searchField.stringValue.length == 0) return @[];
    char err[1024];
    spdf_rect rects[256];
    int count = spdf_search_page_rects_options(_doc, (int)pageIndex, _searchField.stringValue.UTF8String,
                                               _findRegexCheckbox.state == NSControlStateValueOn, _findRegexMultiline,
                                               rects, 256, err, sizeof(err));
    if (count <= 0) return @[];

    NSMutableArray<NSValue*>* values = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
    for (int i = 0; i < count; ++i) {
        NSRect r = NSMakeRect(rects[i].x0, rects[i].y0, rects[i].x1 - rects[i].x0, rects[i].y1 - rects[i].y0);
        [values addObject:[NSValue valueWithRect:r]];
    }
    return values;
}

- (void)applySearchHighlightsToCurrentPage {
    for (SPDFRenderedPage* page in _renderedPages) page.highlights = _findHighlights[@(page.pageIndex)] ?: @[];
    _pageView.pages = _renderedPages;
    [_pageView setNeedsDisplay:YES];
    [self updateMinimap];
    [self invalidateFindMarkers];
}

- (void)startFindForCurrentQuery {
    [self startFindForCurrentQueryResetSavedIndex:YES revealMatch:YES];
}

- (void)startFindForCurrentQueryResetSavedIndex:(BOOL)resetSavedIndex revealMatch:(BOOL)revealMatch {
    if (!_doc || !_path.length) {
        [self clearFindResults];
        return;
    }

    NSString* query = [_searchField.stringValue copy];
    BOOL useRegex = _findRegexCheckbox.state == NSControlStateValueOn;
    BOOL useRegexMultiline = _findRegexMultiline;
    if (_selectedTabIndex >= 0 && _selectedTabIndex < (NSInteger)_tabs.count) {
        SPDFDocumentTab* tab = _tabs[(NSUInteger)_selectedTabIndex];
        tab.searchText = query ?: @"";
        tab.searchRegex = useRegex;
        tab.searchRegexMultiline = useRegexMultiline;
        if (resetSavedIndex) tab.findMatchIndex = -1;
    }
    [_findQueue cancelAllOperations];
    _findGeneration++;
    NSUInteger generation = _findGeneration;
    [_findHighlights removeAllObjects];
    [_findMatches removeAllObjects];
    _findMatchIndex = -1;
    _findSearchInProgress = NO;
    [self applySearchHighlightsToCurrentPage];
    [self updateFindControls];

    if (query.length == 0) {
        _pendingFindPreferredPage = -1;
        _pendingFindPreferredMatchIndex = -1;
        _statusLabel.stringValue = @"Ready";
        return;
    }

    NSString* path = [_path copy];
    NSInteger preferredPage = _pendingFindPreferredPage;
    _pendingFindPreferredPage = -1;
    NSInteger preferredMatchIndex = _pendingFindPreferredMatchIndex;
    _pendingFindPreferredMatchIndex = -1;
    _findSearchInProgress = YES;
    [self updateFindControls];
    _statusLabel.stringValue = [NSString stringWithFormat:@"Searching for \"%@\"...", query];
    [_findQueue addOperationWithBlock:^{
      @autoreleasepool {
          NSMutableDictionary<NSNumber*, NSArray<NSValue*>*>* highlights = [NSMutableDictionary dictionary];
          NSMutableArray<NSDictionary*>* matches = [NSMutableArray array];
          __block NSString* searchError = nil;
          char openErr[1024];
          spdf_document* doc = spdf_open(path.fileSystemRepresentation, openErr, sizeof(openErr));
          if (!doc) {
              [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                if (generation != self->_findGeneration) return;
                self->_findSearchInProgress = NO;
                [self updateFindControls];
              }];
              return;
          }

          NSInteger pageCount = spdf_page_count(doc);
          for (NSInteger page = 0; page < pageCount; ++page) {
              if (generation != self->_findGeneration) break;
              char err[512];
              spdf_rect rects[256];
              int count = spdf_search_page_rects_options(doc, (int)page, query.UTF8String, useRegex, useRegexMultiline,
                                                         rects, 256, err, sizeof(err));
              if (count < 0) {
                  searchError = [NSString stringWithUTF8String:err[0] ? err : "Search failed"];
                  break;
              }
              if (count <= 0) continue;
              NSMutableArray<NSValue*>* values = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
              for (int i = 0; i < count; ++i) {
                  NSRect r = NSMakeRect(rects[i].x0, rects[i].y0, rects[i].x1 - rects[i].x0, rects[i].y1 - rects[i].y0);
                  [values addObject:[NSValue valueWithRect:r]];
                  [matches addObject:@{@"page" : @(page), @"rect" : [NSValue valueWithRect:r]}];
              }
              highlights[@(page)] = values;
          }
          spdf_close(doc);

          [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (generation != self->_findGeneration) return;
            [self->_findHighlights removeAllObjects];
            [self->_findHighlights addEntriesFromDictionary:highlights];
            [self->_findMatches removeAllObjects];
            [self->_findMatches addObjectsFromArray:matches];
            NSInteger preferredMatch = -1;
            if (preferredPage >= 0) {
                for (NSInteger i = 0; i < (NSInteger)self->_findMatches.count; ++i) {
                    if ([self->_findMatches[(NSUInteger)i][@"page"] integerValue] == preferredPage) {
                        preferredMatch = i;
                        break;
                    }
                }
            }
            if (preferredMatchIndex >= 0 && preferredMatchIndex < (NSInteger)self->_findMatches.count)
                preferredMatch = preferredMatchIndex;
            self->_findMatchIndex = preferredMatch >= 0 ? preferredMatch : (self->_findMatches.count > 0 ? 0 : -1);
            self->_findSearchInProgress = NO;
            [self rememberActiveTabFindState];
            [self applySearchHighlightsToCurrentPage];
            [self updateFindControls];
            if (searchError.length > 0) {
                self->_statusLabel.stringValue = [NSString stringWithFormat:@"Invalid regex/search: %@", searchError];
            } else if (self->_findMatchIndex >= 0) {
                if (revealMatch) [self jumpToFindMatchAtIndex:self->_findMatchIndex];
                self->_statusLabel.stringValue =
                    [NSString stringWithFormat:@"%ld matches for \"%@\"", (long)self->_findMatches.count, query];
            } else
                self->_statusLabel.stringValue = [NSString stringWithFormat:@"No matches for \"%@\"", query];
          }];
      }
    }];
}

- (void)scrollToFindMatch:(NSDictionary*)match {
    if (!_doc || !match) return;
    NSInteger page = [match[@"page"] integerValue];
    NSRect matchRect = [match[@"rect"] rectValue];
    [self scrollToPageRect:matchRect pageIndex:page];
}

- (void)scrollToPageRect:(NSRect)targetRect pageIndex:(NSInteger)page {
    if (!_doc) return;
    page = MAX(0, MIN(page, spdf_page_count(_doc) - 1));
    NSRect pageRect = [_pageView rectForPageAtIndex:page];
    NSRect matchRect = targetRect;
    if (NSIsEmptyRect(pageRect) || NSIsEmptyRect(matchRect)) {
        [self scrollToPage:page alignTop:YES];
        return;
    }

    NSRect viewRect =
        NSMakeRect(pageRect.origin.x + matchRect.origin.x * _zoom, pageRect.origin.y + matchRect.origin.y * _zoom,
                   matchRect.size.width * _zoom, matchRect.size.height * _zoom);
    NSClipView* clipView = _pageScrollView.contentView;
    NSRect visibleRect = clipView.bounds;
    NSPoint origin =
        NSMakePoint(NSMidX(viewRect) - NSWidth(visibleRect) * 0.5, NSMidY(viewRect) - NSHeight(visibleRect) * 0.5);
    BOOL fullPageHeightFits = _viewMode == SPDFViewModeSingle && NSHeight(pageRect) <= NSHeight(visibleRect) + 0.5;
    if (fullPageHeightFits) {
        BOOL pageAlreadyVisible =
            NSMinY(pageRect) >= NSMinY(visibleRect) - 0.5 && NSMaxY(pageRect) <= NSMaxY(visibleRect) + 0.5;
        origin.y = pageAlreadyVisible ? NSMinY(visibleRect) : NSMidY(pageRect) - NSHeight(visibleRect) * 0.5;
        BOOL matchAlreadyVisible =
            NSMinX(viewRect) >= NSMinX(visibleRect) - 0.5 && NSMaxX(viewRect) <= NSMaxX(visibleRect) + 0.5;
        if (matchAlreadyVisible) origin.x = NSMinX(visibleRect);
    }
    [self scrollDocumentClipViewToOrigin:origin notify:NO];
    [self updateMinimap];
}

- (void)stepFindFlash:(NSTimer*)timer {
    (void)timer;
    NSTimeInterval elapsed = NSDate.timeIntervalSinceReferenceDate - _findFlashStartTime;
    CGFloat alpha = 0.0;
    if (elapsed < 0.10)
        alpha = (CGFloat)(elapsed / 0.10);
    else if (elapsed < 0.18)
        alpha = (CGFloat)(1.0 - (elapsed - 0.10) / 0.08);
    else if (elapsed < 0.26)
        alpha = (CGFloat)((elapsed - 0.18) / 0.08);
    else if (elapsed < 1.26)
        alpha = 1.0;
    else if (elapsed < 1.51)
        alpha = (CGFloat)(1.0 - (elapsed - 1.26) / 0.25);
    else {
        [_findFlashTimer invalidate];
        _findFlashTimer = nil;
        _pageView.activeFindPageIndex = -1;
        _pageView.activeFindAlpha = 0.0;
        [_pageView setNeedsDisplay:YES];
        return;
    }

    _pageView.activeFindAlpha = spdf_clamp_cg(alpha, 0.0, 1.0);
    [_pageView setNeedsDisplayInRect:[_pageView rectForPageAtIndex:_pageView.activeFindPageIndex]];
}

- (void)flashPageRect:(NSRect)targetRect pageIndex:(NSInteger)pageIndex {
    if (!_doc || NSIsEmptyRect(targetRect)) return;
    [_findFlashTimer invalidate];
    _pageView.activeFindPageIndex = MAX(0, MIN(pageIndex, spdf_page_count(_doc) - 1));
    _pageView.activeFindRect = targetRect;
    _pageView.activeFindAlpha = 0.0;
    _findFlashStartTime = NSDate.timeIntervalSinceReferenceDate;
    _findFlashTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
                                                       target:self
                                                     selector:@selector(stepFindFlash:)
                                                     userInfo:nil
                                                      repeats:YES];
    [self stepFindFlash:_findFlashTimer];
}

- (void)flashFindMatch:(NSDictionary*)match {
    if (!match) return;
    [self flashPageRect:[match[@"rect"] rectValue] pageIndex:[match[@"page"] integerValue]];
}

- (void)jumpToFindMatchAtIndex:(NSInteger)index {
    if (!_doc || index < 0 || index >= (NSInteger)_findMatches.count) return;
    _findMatchIndex = index;
    NSDictionary* match = _findMatches[(NSUInteger)index];
    NSInteger page = [match[@"page"] integerValue];
    _pageIndex = MAX(0, MIN(page, spdf_page_count(_doc) - 1));
    _pageView.currentPageIndex = _pageIndex;
    [self renderPageIfNeededAtIndex:_pageIndex];
    [self applySearchHighlightsToCurrentPage];
    [self resizeDocumentView];
    [self scrollToFindMatch:match];
    [self flashFindMatch:match];
    [self updateControls];
    [self selectCurrentSidebarRow];
    [self updateFindControls];
    [self rememberActiveTabFindState];
    _statusLabel.stringValue =
        [NSString stringWithFormat:@"Match %ld of %ld", (long)_findMatchIndex + 1, (long)_findMatches.count];
}

- (void)documentViewSelectionChangedOnPage:(NSInteger)pageIndex from:(NSPoint)start to:(NSPoint)end {
    if (!_doc || pageIndex < 0 || pageIndex >= (NSInteger)_renderedPages.count) return;

    char err[1024];
    spdf_rect rects[256];
    char* text = NULL;
    int count = spdf_select_page_text(_doc, (int)pageIndex, (float)start.x, (float)start.y, (float)end.x, (float)end.y,
                                      rects, 256, &text, err, sizeof(err));

    for (SPDFRenderedPage* page in _renderedPages) page.selectionRects = @[];

    if (count > 0) {
        NSMutableArray<NSValue*>* values = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
        for (int i = 0; i < count; ++i) {
            NSRect r = NSMakeRect(rects[i].x0, rects[i].y0, rects[i].x1 - rects[i].x0, rects[i].y1 - rects[i].y0);
            [values addObject:[NSValue valueWithRect:r]];
        }
        _renderedPages[(NSUInteger)pageIndex].selectionRects = values;
        _selectionPageIndex = pageIndex;
        _selectedText = text ? [NSString stringWithUTF8String:text] : @"";
    } else {
        _selectionPageIndex = -1;
        _selectedText = nil;
    }

    if (text) spdf_free_string(text);
    _pageView.pages = _renderedPages;
    [_pageView setNeedsDisplay:YES];
    [self updateMinimap];
}

- (void)copySelection:(id)sender {
    (void)sender;
    if (_selectedText.length == 0) {
        NSBeep();
        return;
    }
    NSPasteboard* pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:_selectedText forType:NSPasteboardTypeString];
    _statusLabel.stringValue = @"Selected text copied.";
}

- (BOOL)documentViewHasLinkAtPageIndex:(NSInteger)pageIndex pagePoint:(NSPoint)pagePoint {
    if (!_doc) return NO;

    char err[512];
    spdf_link_target target;
    int hit =
        spdf_link_at_point(_doc, (int)pageIndex, (float)pagePoint.x, (float)pagePoint.y, &target, err, sizeof(err));
    if (hit <= 0) return NO;
    BOOL hasLink =
        (target.kind == SPDF_LINK_URI && target.uri) || (target.kind == SPDF_LINK_INTERNAL && target.page_index >= 0);
    spdf_free_link_target(&target);
    return hasLink;
}

- (BOOL)documentViewOpenLinkAtPageIndex:(NSInteger)pageIndex pagePoint:(NSPoint)pagePoint {
    if (!_doc) return NO;

    char err[512];
    spdf_link_target target;
    int hit =
        spdf_link_at_point(_doc, (int)pageIndex, (float)pagePoint.x, (float)pagePoint.y, &target, err, sizeof(err));
    if (hit <= 0) return NO;

    if (target.kind == SPDF_LINK_URI && target.uri) {
        NSString* uri = [NSString stringWithUTF8String:target.uri];
        NSURL* url = [NSURL URLWithString:uri];
        if ((!url || url.scheme.length == 0) && uri.length > 0) url = [NSURL fileURLWithPath:uri];
        if (url && spdf_is_allowed_external_url(url))
            [[NSWorkspace sharedWorkspace] openURL:url];
        else
            NSBeep();
        spdf_free_link_target(&target);
        return YES;
    }

    if (target.kind == SPDF_LINK_INTERNAL && target.page_index >= 0) {
        NSInteger targetPage = target.page_index;
        NSRect targetRect = NSZeroRect;
        if (isfinite(target.x) && isfinite(target.y)) targetRect = NSMakeRect(target.x, target.y, 1.0, 24.0);
        _pageIndex = MAX(0, MIN(targetPage, spdf_page_count(_doc) - 1));
        _pageView.currentPageIndex = _pageIndex;
        [self renderPageIfNeededAtIndex:_pageIndex];
        [self resizeDocumentView];
        if (NSIsEmptyRect(targetRect))
            [self scrollToPage:_pageIndex alignTop:YES];
        else
            [self scrollToPageRect:targetRect pageIndex:_pageIndex];
        [self updateControls];
        [self selectCurrentSidebarRow];
        [self persistActiveState];
        spdf_free_link_target(&target);
        return YES;
    }

    spdf_free_link_target(&target);
    return NO;
}

- (BOOL)documentViewHandlePresentationMouseDown:(NSEvent*)event {
    if (!_presentationMode || !_doc) return NO;
    if (event.type == NSEventTypeRightMouseDown) {
        [self previousPage:nil];
        return YES;
    }
    if (event.type == NSEventTypeLeftMouseDown) {
        [self nextPage:nil];
        return YES;
    }
    return NO;
}

- (BOOL)documentViewInPresentationMode {
    return _presentationMode;
}

- (NSArray<NSValue*>*)currentSelectionRects {
    if (_selectionPageIndex < 0 || _selectionPageIndex >= (NSInteger)_renderedPages.count) return @[];
    return _renderedPages[(NSUInteger)_selectionPageIndex].selectionRects ?: @[];
}

- (NSString*)currentCommentAuthor {
    NSString* author = [_commentAuthor stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (author.length > 0) return author;
    NSString* fallback = NSFullUserName();
    if (fallback.length == 0) fallback = NSUserName();
    return fallback ?: @"";
}

- (NSDictionary*)promptForCommentEditorWithTitle:(NSString*)title
                                     buttonTitle:(NSString*)buttonTitle
                                          author:(NSString*)author
                                            text:(NSString*)text {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = title ?: @"Comment";
    alert.informativeText = @"Edit the comment author and text.";
    [alert addButtonWithTitle:buttonTitle ?: @"Save"];
    [alert addButtonWithTitle:@"Cancel"];

    NSView* accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 420, 188)];
    NSTextField* authorLabel = [NSTextField labelWithString:@"Author"];
    authorLabel.frame = NSMakeRect(0, 164, 420, 18);
    NSTextField* authorField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 136, 420, 24)];
    authorField.stringValue = author ?: @"";

    NSTextField* commentLabel = [NSTextField labelWithString:@"Comment"];
    commentLabel.frame = NSMakeRect(0, 112, 420, 18);
    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 420, 108)];
    scroll.hasVerticalScroller = YES;
    NSTextView* textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 420, 108)];
    textView.string = text ?: @"";
    textView.font = [NSFont systemFontOfSize:13.0];
    textView.verticallyResizable = YES;
    textView.horizontallyResizable = NO;
    textView.textContainer.widthTracksTextView = YES;
    scroll.documentView = textView;

    [accessory addSubview:authorLabel];
    [accessory addSubview:authorField];
    [accessory addSubview:commentLabel];
    [accessory addSubview:scroll];
    alert.accessoryView = accessory;
    NSRange commentRange = NSMakeRange(0, textView.string.length);
    [textView setSelectedRange:commentRange];
    [alert.window setInitialFirstResponder:textView];
    [alert.window makeFirstResponder:textView];
    dispatch_async(dispatch_get_main_queue(), ^{
      [alert.window makeFirstResponder:textView];
      [textView setSelectedRange:commentRange];
    });
    if ([alert runModal] != NSAlertFirstButtonReturn) return nil;

    NSString* trimmedText =
        [textView.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString* trimmedAuthor =
        [authorField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmedText.length == 0) return nil;
    return @{@"author" : trimmedAuthor ?: @"", @"text" : trimmedText};
}

- (NSString*)promptForCommentTextWithDefault:(NSString*)defaultText {
    NSDictionary* result = [self promptForCommentEditorWithTitle:@"Add Comment"
                                                     buttonTitle:@"Add"
                                                          author:[self currentCommentAuthor]
                                                            text:defaultText ?: @""];
    if (result[@"author"]) {
        _commentAuthor = result[@"author"];
        [self savePersistentState];
    }
    return result[@"text"];
}

- (void)addComment:(id)sender {
    (void)sender;
    if (!_doc || !_path.length) {
        NSBeep();
        return;
    }

    BOOL hasSelection = _selectedText.length > 0 && _selectionPageIndex >= 0 && [self currentSelectionRects].count > 0;
    NSInteger pageIndex = hasSelection ? _selectionPageIndex : _contextPageIndex;
    if (pageIndex < 0 || pageIndex >= (NSInteger)_renderedPages.count) {
        NSBeep();
        return;
    }

    NSString* comment = [self promptForCommentTextWithDefault:hasSelection ? _selectedText : @""];
    if (!comment) return;
    comment = [comment stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (comment.length == 0) {
        NSBeep();
        return;
    }

    char err[1024];
    BOOL ok = NO;
    if (hasSelection) {
        NSArray<NSValue*>* values = [self currentSelectionRects];
        int count = (int)MIN((NSUInteger)256, values.count);
        spdf_rect rects[256];
        for (int i = 0; i < count; ++i) {
            NSRect r = values[(NSUInteger)i].rectValue;
            rects[i].x0 = NSMinX(r);
            rects[i].y0 = NSMinY(r);
            rects[i].x1 = NSMaxX(r);
            rects[i].y1 = NSMaxY(r);
        }
        ok = spdf_add_highlight_comment(_doc, (int)pageIndex, rects, count, comment.UTF8String,
                                        [self currentCommentAuthor].UTF8String, err, sizeof(err));
    } else {
        ok = spdf_add_text_comment(_doc, (int)pageIndex, (float)_contextPagePoint.x, (float)_contextPagePoint.y,
                                   comment.UTF8String, [self currentCommentAuthor].UTF8String, err, sizeof(err));
    }
    if (ok) ok = spdf_save_document(_doc, _path.fileSystemRepresentation, err, sizeof(err));
    if (!ok) {
        [self showError:@"Could not add comment" detail:[NSString stringWithUTF8String:err[0] ? err : "Unknown error"]];
        return;
    }

    _statusLabel.stringValue = @"Comment added.";
    [self loadCommentsForCurrentDocumentAsync];
    [self renderDocumentAndScrollToPage:_pageIndex
                               alignTop:NO
                          restoreOrigin:[NSValue valueWithPoint:_pageScrollView.contentView.bounds.origin]];
}

- (void)setCommentAuthor:(id)sender {
    (void)sender;
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Set Author for Comments";
    alert.informativeText = @"New comments will use this author.";
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField* field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 360, 24)];
    field.stringValue = [self currentCommentAuthor];
    alert.accessoryView = field;
    [_window makeFirstResponder:field];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    _commentAuthor =
        [field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [self savePersistentState];
    _statusLabel.stringValue = _commentAuthor.length ? @"Comment author saved." : @"Comment author reset.";
}

- (spdf_comment_item*)commentItemForIndex:(NSInteger)commentIndex {
    if (commentIndex < 0) return NULL;
    for (int i = 0; i < _comments.count; ++i) {
        if (_comments.items[i].index == commentIndex) return &_comments.items[i];
    }
    return NULL;
}

- (NSNumber*)commentIndexForSidebarRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_sidebarItems.count) return nil;
    NSDictionary* item = _sidebarItems[(NSUInteger)row];
    if (![item[@"kind"] isEqualToString:@"comment"]) return nil;
    NSNumber* commentIndex = item[@"commentIndex"];
    return [commentIndex isKindOfClass:NSNumber.class] ? commentIndex : nil;
}

- (NSInteger)commentIndexForSidebarContextRow {
    NSNumber* commentIndex = [self commentIndexForSidebarRow:_sidebarTable.clickedRow];
    return commentIndex ? commentIndex.integerValue : -1;
}

- (NSInteger)commentIndexAtPageIndex:(NSInteger)pageIndex pagePoint:(NSPoint)pagePoint {
    if (pageIndex < 0) return -1;
    for (NSDictionary* comment in [self commentAnnotationsForPage:pageIndex]) {
        NSValue* boundsValue = comment[@"bounds"];
        if (!boundsValue) continue;
        NSRect bounds = NSInsetRect(boundsValue.rectValue, -3.0, -3.0);
        if (NSPointInRect(pagePoint, bounds)) return [comment[@"commentIndex"] integerValue];
    }
    return -1;
}

- (NSInteger)commentIndexForEditAction:(id)sender {
    if ([sender isKindOfClass:NSMenuItem.class]) {
        id represented = ((NSMenuItem*)sender).representedObject;
        if ([represented isKindOfClass:NSNumber.class]) return [represented integerValue];
    }
    NSInteger sidebarIndex = [self commentIndexForSidebarContextRow];
    if (sidebarIndex >= 0) return sidebarIndex;
    return _contextCommentIndex;
}

- (void)editComment:(id)sender {
    (void)sender;
    if (!_doc || !_path.length) return;

    NSInteger commentIndex = [self commentIndexForEditAction:sender];
    spdf_comment_item* item = [self commentItemForIndex:commentIndex];
    if (!item) {
        NSBeep();
        return;
    }

    NSString* author =
        item->author && *item->author ? [NSString stringWithUTF8String:item->author] : [self currentCommentAuthor];
    NSString* text = item->text && *item->text ? [NSString stringWithUTF8String:item->text] : @"";
    NSDictionary* result =
        [self promptForCommentEditorWithTitle:@"Edit Comment" buttonTitle:@"Save" author:author text:text];
    if (!result) return;

    _commentAuthor = result[@"author"] ?: @"";
    char err[1024];
    BOOL ok = spdf_update_comment(_doc, (int)commentIndex, [result[@"text"] UTF8String], [result[@"author"] UTF8String],
                                  err, sizeof(err));
    if (ok) ok = spdf_save_document(_doc, _path.fileSystemRepresentation, err, sizeof(err));
    if (!ok) {
        [self showError:@"Could not edit comment"
                 detail:[NSString stringWithUTF8String:err[0] ? err : "Unknown error"]];
        return;
    }

    [self savePersistentState];
    _statusLabel.stringValue = @"Comment updated.";
    [self loadCommentsForCurrentDocumentAsync];
    [self renderDocumentAndScrollToPage:_pageIndex
                               alignTop:NO
                          restoreOrigin:[NSValue valueWithPoint:_pageScrollView.contentView.bounds.origin]];
}

- (void)deleteComment:(id)sender {
    if (!_doc || !_path.length) return;

    NSInteger commentIndex = [self commentIndexForEditAction:sender];
    spdf_comment_item* item = [self commentItemForIndex:commentIndex];
    if (!item) {
        NSBeep();
        return;
    }

    NSString* text = item->text && *item->text ? [NSString stringWithUTF8String:item->text] : @"";
    NSString* detail = @"This will permanently remove the comment from the PDF.";
    if (text.length > 0) {
        NSString* preview = text.length > 180 ? [[text substringToIndex:180] stringByAppendingString:@"..."] : text;
        detail = [NSString stringWithFormat:@"%@\n\n%@", detail, preview];
    }

    NSAlert* alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"Delete Comment?";
    alert.informativeText = detail;
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    [self documentViewEndHoverComment];
    NSValue* restoreOrigin = [NSValue valueWithPoint:_pageScrollView.contentView.bounds.origin];
    char err[1024];
    BOOL ok = spdf_delete_comment(_doc, (int)commentIndex, err, sizeof(err));
    if (ok) ok = spdf_save_document(_doc, _path.fileSystemRepresentation, err, sizeof(err));
    if (!ok) {
        [self showError:@"Could not delete comment"
                 detail:[NSString stringWithUTF8String:err[0] ? err : "Unknown error"]];
        return;
    }

    _statusLabel.stringValue = @"Comment deleted.";
    [self loadCommentsForCurrentDocumentAsync];
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO restoreOrigin:restoreOrigin];
}

- (NSString*)shortProvenanceForPath:(NSString*)path {
    NSString* displayPath = spdf_display_path_without_extension(path);
    if (displayPath.length <= 52) return spdf_display_name_for_path(path);
    NSString* head = [displayPath substringToIndex:MIN((NSUInteger)20, displayPath.length)];
    NSString* tail = [displayPath substringFromIndex:displayPath.length - MIN((NSUInteger)28, displayPath.length)];
    return [NSString stringWithFormat:@"%@...%@", head, tail];
}

- (NSArray<NSString*>*)labelsFromString:(NSString*)text {
    NSMutableArray<NSString*>* labels = [NSMutableArray array];
    NSCharacterSet* separators = [NSCharacterSet characterSetWithCharactersInString:@",;"];
    for (NSString* raw in [text componentsSeparatedByCharactersInSet:separators]) {
        NSString* label = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (label.length > 0 && ![labels containsObject:label]) [labels addObject:label];
    }
    return labels;
}

- (NSDictionary*)promptForFavoriteWithDefaultName:(NSString*)defaultName title:(NSString*)title {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = @"Name this favorite so it is easier to find from the command palette.";
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];

    NSStackView* stack = [[NSStackView alloc] initWithFrame:NSMakeRect(0, 0, 360, 74)];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 6.0;

    NSTextField* nameField = [[NSTextField alloc] init];
    nameField.stringValue = defaultName ?: @"";
    nameField.placeholderString = @"Favorite name";
    NSTextField* labelField = [[NSTextField alloc] init];
    labelField.placeholderString = @"Optional search labels, separated by commas";
    [stack addArrangedSubview:nameField];
    [stack addArrangedSubview:labelField];
    alert.accessoryView = stack;

    if ([alert runModal] != NSAlertFirstButtonReturn) return nil;
    NSString* name =
        [nameField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!name.length) name = defaultName ?: @"Favorite";
    NSArray<NSString*>* labels = [self labelsFromString:labelField.stringValue ?: @""];
    return @{@"name" : name, @"labels" : labels};
}

- (void)favoriteCurrentPage:(id)sender {
    (void)sender;
    if (!_doc || !_path.length) return;
    NSString* displayName = spdf_display_name_for_path(_path);
    NSString* defaultName = [NSString stringWithFormat:@"%@ p.%ld", displayName, (long)_pageIndex + 1];
    NSDictionary* metadata = [self promptForFavoriteWithDefaultName:defaultName title:@"Favorite Current Page"];
    if (!metadata) return;
    NSMutableDictionary* fav = [@{
        @"type" : @"page",
        @"path" : _path,
        @"title" : displayName,
        @"page" : @(_pageIndex),
        @"name" : metadata[@"name"],
        @"labels" : metadata[@"labels"],
        @"created" : @((long)NSDate.date.timeIntervalSince1970)
    } mutableCopy];
    NSIndexSet* dupes = [_favorites indexesOfObjectsPassingTest:^BOOL(NSDictionary* obj, NSUInteger idx, BOOL* stop) {
      (void)idx;
      (void)stop;
      return [obj[@"path"] isEqualToString:_path] && [obj[@"type"] isEqualToString:@"page"] &&
             [obj[@"page"] integerValue] == _pageIndex;
    }];
    if (dupes.count) [_favorites removeObjectsAtIndexes:dupes];
    [_favorites addObject:fav];
    [self savePersistentState];
    _statusLabel.stringValue = @"Page added to favorites.";
}

- (void)favoriteCurrentDocument:(id)sender {
    (void)sender;
    if (!_doc || !_path.length) return;
    NSString* displayName = spdf_display_name_for_path(_path);
    NSDictionary* metadata = [self promptForFavoriteWithDefaultName:displayName title:@"Favorite Current Document"];
    if (!metadata) return;
    NSMutableDictionary* fav = [@{
        @"type" : @"document",
        @"path" : _path,
        @"title" : displayName,
        @"page" : @0,
        @"name" : metadata[@"name"],
        @"labels" : metadata[@"labels"],
        @"created" : @((long)NSDate.date.timeIntervalSince1970)
    } mutableCopy];
    NSIndexSet* dupes = [_favorites indexesOfObjectsPassingTest:^BOOL(NSDictionary* obj, NSUInteger idx, BOOL* stop) {
      (void)idx;
      (void)stop;
      return [obj[@"path"] isEqualToString:_path] && [obj[@"type"] isEqualToString:@"document"];
    }];
    if (dupes.count) [_favorites removeObjectsAtIndexes:dupes];
    [_favorites addObject:fav];
    [self savePersistentState];
    _statusLabel.stringValue = @"Document added to favorites.";
}

- (void)showFavoritesPalette:(id)sender {
    (void)sender;
    _paletteMode = 1;
    [self showPaletteWithTitle:@"Command"];
}

- (void)focusFind:(id)sender {
    (void)sender;
    [_window makeFirstResponder:_searchField];
    [_searchField selectText:nil];
}

- (void)toggleFindRegex:(id)sender {
    (void)sender;
    [self rememberActiveTabFindState];
    [self startFindForCurrentQuery];
}

- (void)toggleFindRegexMultiline:(id)sender {
    (void)sender;
    _findRegexMultiline = !_findRegexMultiline;
    [self rememberActiveTabFindState];
    [self startFindForCurrentQuery];
}

- (void)clearFindFieldFocus {
    if (_window.firstResponder == _searchField || _window.firstResponder == _searchField.currentEditor)
        [_window makeFirstResponder:_pageView];
}

- (void)clearPageFieldFocus {
    if (_window.firstResponder == _pageField || _window.firstResponder == _pageField.currentEditor ||
        _pageField.currentEditor) {
        [_window makeFirstResponder:_pageView ?: _pageScrollView];
    }
}

- (void)clearToolbarFieldFocusForTabSwitch {
    if (!_window) return;

    BOOL toolbarHasFocus = _window.firstResponder == _pageField || _window.firstResponder == _searchField ||
                           _window.firstResponder == _pageField.currentEditor ||
                           _window.firstResponder == _searchField.currentEditor || _pageField.currentEditor ||
                           _searchField.currentEditor;
    if (toolbarHasFocus) [_pageField abortEditing];
    NSResponder* target = _pageView ? (NSResponder*)_pageView : (NSResponder*)_pageScrollView;
    if (target) [_window makeFirstResponder:target];
    if (_pageField.currentEditor) [_pageField abortEditing];
}

- (void)showFindPalette:(id)sender {
    [self focusFind:sender];
}

- (void)showPaletteWithTitle:(NSString*)title {
    if (!_palettePanel) {
        _palettePanel = [[NSPanel alloc]
            initWithContentRect:NSMakeRect(0, 0, 650, 390)
                      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskUtilityWindow | NSWindowStyleMaskClosable
                        backing:NSBackingStoreBuffered
                          defer:NO];
        _palettePanel.floatingPanel = YES;
        _palettePanel.hidesOnDeactivate = YES;
        _palettePanel.releasedWhenClosed = NO;

        NSView* content = [[NSView alloc] initWithFrame:_palettePanel.contentView.bounds];
        content.translatesAutoresizingMaskIntoConstraints = NO;
        _palettePanel.contentView = content;

        _paletteSearchField = [[SPDFPaletteSearchField alloc] init];
        ((SPDFPaletteSearchField*)_paletteSearchField).reader = self;
        _paletteSearchField.translatesAutoresizingMaskIntoConstraints = NO;
        _paletteSearchField.delegate = self;
        _paletteSearchField.font = [NSFont systemFontOfSize:15 weight:NSFontWeightRegular];
        [content addSubview:_paletteSearchField];

        NSScrollView* scroll = [[NSScrollView alloc] init];
        scroll.translatesAutoresizingMaskIntoConstraints = NO;
        scroll.hasVerticalScroller = YES;
        scroll.autohidesScrollers = YES;
        scroll.borderType = NSNoBorder;
        scroll.drawsBackground = NO;
        [content addSubview:scroll];

        _paletteTable = [[NSTableView alloc] init];
        _paletteTable.headerView = nil;
        _paletteTable.rowHeight = 42.0;
        _paletteTable.intercellSpacing = NSMakeSize(0, 0);
        _paletteTable.backgroundColor = NSColor.clearColor;
        _paletteTable.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
        _paletteTable.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
        _paletteTable.allowsEmptySelection = NO;
        _paletteTable.dataSource = self;
        _paletteTable.delegate = self;
        _paletteTable.target = self;
        _paletteTable.action = @selector(activatePaletteSelection:);
        _paletteTable.doubleAction = @selector(activatePaletteSelection:);
        NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"result"];
        column.width = 620;
        column.resizingMask = NSTableColumnAutoresizingMask;
        [_paletteTable addTableColumn:column];
        scroll.documentView = _paletteTable;

        [NSLayoutConstraint activateConstraints:@[
            [_paletteSearchField.topAnchor constraintEqualToAnchor:content.topAnchor constant:14],
            [_paletteSearchField.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
            [_paletteSearchField.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
            [_paletteSearchField.heightAnchor constraintEqualToConstant:34],
            [scroll.topAnchor constraintEqualToAnchor:_paletteSearchField.bottomAnchor constant:8],
            [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
            [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
            [scroll.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-8]
        ]];
    }

    _palettePanel.title = title;
    _paletteSearchField.stringValue = @"";
    _paletteSearchField.placeholderString = @"Favorites and open documents";
    _paletteAllDocsCheckbox.hidden = YES;
    _paletteFavoritePendingDelete = nil;
    [self refreshPaletteResults];
    [self updatePalettePanelFramePreservingTop:NO];
    [_palettePanel makeKeyAndOrderFront:nil];
    [self installPaletteEventMonitor];
    [_palettePanel makeFirstResponder:_paletteSearchField];
}

- (BOOL)isSelectablePaletteResult:(NSDictionary*)result {
    NSString* kind = result[@"kind"];
    return ![kind isEqualToString:@"header"] && ![kind isEqualToString:@"separator"] &&
           ![kind isEqualToString:@"status"];
}

- (void)scrollPaletteRowToVisibleWithHeader:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_paletteResults.count) return;
    NSInteger visibleRow = row;
    if (row > 0 && [_paletteResults[(NSUInteger)row - 1][@"kind"] isEqualToString:@"header"]) visibleRow = row - 1;
    [_paletteTable scrollRowToVisible:visibleRow];
    [_paletteTable scrollRowToVisible:row];
}

- (void)selectFirstPaletteResult {
    for (NSInteger i = 0; i < (NSInteger)_paletteResults.count; ++i) {
        if ([self isSelectablePaletteResult:_paletteResults[(NSUInteger)i]]) {
            [_paletteTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)i] byExtendingSelection:NO];
            [self scrollPaletteRowToVisibleWithHeader:i];
            return;
        }
    }
    [_paletteTable deselectAll:nil];
}

- (void)restorePaletteSelectionAfterReloadFromRow:(NSInteger)previousRow {
    NSInteger row = previousRow;
    if (row >= 0 && row < (NSInteger)_paletteResults.count &&
        [self isSelectablePaletteResult:_paletteResults[(NSUInteger)row]]) {
        [_paletteTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        [self scrollPaletteRowToVisibleWithHeader:row];
        return;
    }
    if (_paletteTable.selectedRow >= 0 && _paletteTable.selectedRow < (NSInteger)_paletteResults.count &&
        [self isSelectablePaletteResult:_paletteResults[(NSUInteger)_paletteTable.selectedRow]]) {
        [self scrollPaletteRowToVisibleWithHeader:_paletteTable.selectedRow];
        return;
    }
    [self selectFirstPaletteResult];
}

- (CGFloat)paletteHeightForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_paletteResults.count) return 42.0;
    NSString* kind = _paletteResults[(NSUInteger)row][@"kind"];
    if ([kind isEqualToString:@"header"]) return 32.0;
    if ([kind isEqualToString:@"separator"]) return 0.0;
    if ([kind isEqualToString:@"status"]) return 38.0;
    return 42.0;
}

- (CGFloat)paletteRowsHeight {
    CGFloat height = 0.0;
    for (NSInteger i = 0; i < (NSInteger)_paletteResults.count; ++i) height += [self paletteHeightForRow:i];
    return height;
}

- (void)updatePalettePanelFramePreservingTop:(BOOL)preserveTop {
    if (!_palettePanel || !_window) return;
    CGFloat contentWidth = 650.0;
    CGFloat chromeHeight = 14.0 + 34.0 + 8.0 + 8.0;
    CGFloat rowsHeight = [self paletteRowsHeight];
    CGFloat contentHeight = chromeHeight + rowsHeight;
    CGFloat minContentHeight = chromeHeight + 42.0;
    CGFloat maxContentHeight = MIN(NSHeight(_window.frame) - 140.0, chromeHeight + 520.0);
    contentHeight = ceil(spdf_clamp_cg(contentHeight, minContentHeight, MAX(minContentHeight, maxContentHeight)));

    NSRect frame = [_palettePanel frameRectForContentRect:NSMakeRect(0, 0, contentWidth, contentHeight)];
    NSRect windowFrame = _window.frame;
    CGFloat topY = preserveTop && _palettePanel.visible ? NSMaxY(_palettePanel.frame) : NSMaxY(windowFrame) - 88.0;
    CGFloat minY = NSMinY(windowFrame) + 24.0;
    if (topY - NSHeight(frame) < minY) frame.size.height = MAX(160.0, topY - minY);
    frame.origin.x = floor(NSMidX(windowFrame) - NSWidth(frame) / 2.0);
    frame.origin.y = floor(topY - NSHeight(frame));
    [_palettePanel setFrame:frame display:_palettePanel.visible animate:NO];
}

- (void)refreshPaletteResults {
    _paletteSearchGeneration++;
    NSUInteger generation = _paletteSearchGeneration;
    [_paletteResults removeAllObjects];
    NSString* query = _paletteSearchField.stringValue.lowercaseString ?: @"";

    NSArray<NSDictionary*>* favorites = [self favoriteResultsForQuery:query prefix:@""];
    if (favorites.count > 0) {
        [_paletteResults addObject:@{@"kind" : @"header", @"title" : @"Favorites", @"subtitle" : @""}];
        [_paletteResults addObjectsFromArray:favorites];
    }

    if (_doc && _path.length && query.length == 0) {
        NSString* displayName = spdf_display_name_for_path(_path);
        [_paletteResults addObject:@{@"kind" : @"header", @"title" : @"Actions", @"subtitle" : @""}];
        [_paletteResults
            addObject:@{@"kind" : @"addPage", @"title" : @"Favorite current page", @"subtitle" : displayName ?: @""}];
        [_paletteResults addObject:@{
            @"kind" : @"addDoc",
            @"title" : @"Favorite current document",
            @"subtitle" : displayName ?: @""
        }];
    }

    if (query.length > 0 && _tabs.count > 0) {
        [_preloadQueue cancelAllOperations];
        [_paletteResults addObject:@{@"kind" : @"header", @"title" : @"Open documents", @"subtitle" : @""}];
        [_paletteResults
            addObject:@{@"kind" : @"status", @"title" : @"Searching open documents...", @"subtitle" : @""}];
        [self runFindPaletteSearchForQuery:query generation:generation searchAll:YES];
    } else if (_paletteResults.count == 0) {
        [_paletteResults addObject:@{
            @"kind" : @"status",
            @"title" : @"No favorites yet",
            @"subtitle" : @"Use Cmd+B or Cmd+Shift+B to add one."
        }];
    }

    [_paletteTable reloadData];
    [self updatePalettePanelFramePreservingTop:_palettePanel.visible];
    [self selectFirstPaletteResult];
}

- (NSArray<NSDictionary*>*)favoriteResultsForQuery:(NSString*)query prefix:(NSString*)prefix {
    NSMutableArray<NSDictionary*>* results = [NSMutableArray array];
    NSString* lowerQuery = query.lowercaseString ?: @"";
    for (NSDictionary* fav in _favorites) {
        NSArray* labels = [fav[@"labels"] isKindOfClass:NSArray.class] ? fav[@"labels"] : @[];
        NSString* labelText = [labels componentsJoinedByString:@" "];
        NSString* haystack = [[NSString stringWithFormat:@"%@ %@ %@ %@", fav[@"name"] ?: @"", fav[@"title"] ?: @"",
                                                         fav[@"path"] ?: @"", labelText ?: @""] lowercaseString];
        if (lowerQuery.length == 0 || [haystack containsString:lowerQuery]) {
            NSString* subtitle = [self shortProvenanceForPath:fav[@"path"] ?: @""];
            if (labels.count > 0)
                subtitle = [subtitle stringByAppendingFormat:@" - %@", [labels componentsJoinedByString:@", "]];
            if (prefix.length) subtitle = [NSString stringWithFormat:@"%@ - %@", prefix, subtitle];
            NSString* title = spdf_display_label_without_extension(fav[@"name"] ?: fav[@"title"] ?: @"Favorite");
            [results addObject:@{
                @"kind" : @"favorite",
                @"title" : title,
                @"subtitle" : subtitle,
                @"path" : fav[@"path"] ?: @"",
                @"page" : fav[@"page"] ?: @0,
                @"favorite" : fav
            }];
        }
    }
    return results;
}

- (void)runFindPaletteSearchForQuery:(NSString*)query generation:(NSUInteger)generation searchAll:(BOOL)searchAll {
    NSString* currentPath = [_path copy];
    NSArray<SPDFDocumentTab*>* tabs = [_tabs copy];
    [_preloadQueue addOperationWithBlock:^{
      @autoreleasepool {
          NSMutableArray<NSDictionary*>* results = [NSMutableArray array];
          NSMutableSet<NSString*>* searchedPaths = [NSMutableSet set];
          for (SPDFDocumentTab* tab in tabs) {
              if (generation != self->_paletteSearchGeneration) return;
              if (results.count >= 220) break;
              BOOL isCurrent =
                  [tab.path.stringByStandardizingPath isEqualToString:currentPath.stringByStandardizingPath];
              if (!isCurrent && !searchAll) continue;
              NSString* path = tab.path;
              if (!path.length || [searchedPaths containsObject:path.stringByStandardizingPath]) continue;
              [searchedPaths addObject:path.stringByStandardizingPath];

              char openErr[512];
              spdf_document* doc = spdf_open(path.fileSystemRepresentation, openErr, sizeof(openErr));
              if (!doc) continue;
              NSInteger pageCount = spdf_page_count(doc);
              for (NSInteger page = 0; page < pageCount && results.count < 220; ++page) {
                  if (generation != self->_paletteSearchGeneration) break;
                  char err[512];
                  int hits = spdf_search_page(doc, (int)page, query.UTF8String, err, sizeof(err));
                  if (hits > 0) {
                      [results addObject:@{
                          @"kind" : @"find",
                          @"title" : [NSString
                              stringWithFormat:@"Page %ld: %d match%@", (long)page + 1, hits, hits == 1 ? @"" : @"es"],
                          @"subtitle" : [self shortProvenanceForPath:path],
                          @"path" : path,
                          @"page" : @(page),
                          @"query" : query
                      }];
                  }
              }
              spdf_close(doc);
          }

          [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (generation != self->_paletteSearchGeneration || !self->_palettePanel.visible) return;
            NSInteger selectedRow = self->_paletteTable.selectedRow;
            NSIndexSet* statusRows = [self->_paletteResults
                indexesOfObjectsPassingTest:^BOOL(NSDictionary* obj, NSUInteger idx, BOOL* stop) {
                  (void)idx;
                  (void)stop;
                  return [obj[@"kind"] isEqualToString:@"status"];
                }];
            if (statusRows.count) [self->_paletteResults removeObjectsAtIndexes:statusRows];
            if (results.count > 0)
                [self->_paletteResults addObjectsFromArray:results];
            else if (query.length > 0) {
                [self->_paletteResults
                    addObject:@{@"kind" : @"status", @"title" : @"No open-document matches", @"subtitle" : @""}];
            }
            [self->_paletteTable reloadData];
            [self updatePalettePanelFramePreservingTop:YES];
            [self restorePaletteSelectionAfterReloadFromRow:selectedRow];
          }];
      }
    }];
}

- (void)openPaletteResult:(NSDictionary*)result {
    NSString* kind = result[@"kind"];
    if (![self isSelectablePaletteResult:result]) return;
    if ([kind isEqualToString:@"addPage"]) {
        [self favoriteCurrentPage:nil];
        return;
    }
    if ([kind isEqualToString:@"addDoc"]) {
        [self favoriteCurrentDocument:nil];
        return;
    }
    NSString* path = result[@"path"];
    NSInteger page = [result[@"page"] integerValue];
    if (path.length) {
        [self openPath:path];
        if (_doc && [_path.stringByStandardizingPath isEqualToString:path.stringByStandardizingPath]) {
            _pageIndex = MAX(0, MIN(page, spdf_page_count(_doc) - 1));
            _pageView.currentPageIndex = _pageIndex;
            if ([kind isEqualToString:@"find"]) {
                NSString* query = result[@"query"] ?: _paletteSearchField.stringValue;
                _searchField.stringValue = query ?: @"";
                _findRegexCheckbox.state = NSControlStateValueOff;
                _findRegexMultiline = YES;
                _pendingFindPreferredPage = _pageIndex;
                [self startFindForCurrentQuery];
            } else {
                [self renderDocumentAndScrollToPage:_pageIndex alignTop:YES];
            }
        }
    }
}

- (void)paletteMoveSelection:(NSInteger)delta {
    if (_paletteResults.count == 0) return;
    NSInteger row = _paletteTable.selectedRow;
    if (row < 0) row = delta > 0 ? -1 : 0;
    NSInteger count = (NSInteger)_paletteResults.count;
    for (NSInteger step = 0; step < count; ++step) {
        row = (row + delta + count) % count;
        if ([self isSelectablePaletteResult:_paletteResults[(NSUInteger)row]]) {
            [_paletteTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
            [self scrollPaletteRowToVisibleWithHeader:row];
            return;
        }
    }
}

- (void)installPaletteEventMonitor {
    if (_paletteEventMonitor) return;
    __weak SumatraMacDelegate* weakSelf = self;
    _paletteEventMonitor =
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown |
                                                      NSEventMaskOtherMouseDown | NSEventMaskKeyDown
                                              handler:^NSEvent*(NSEvent* event) {
                                                SumatraMacDelegate* strongSelf = weakSelf;
                                                if (strongSelf && strongSelf->_palettePanel.visible) {
                                                    if (event.type == NSEventTypeKeyDown &&
                                                        event.window == strongSelf->_palettePanel) {
                                                        if (event.keyCode == 53) {
                                                            [strongSelf closePalette:nil];
                                                            return nil;
                                                        }
                                                        if (event.keyCode == 125) {
                                                            [strongSelf paletteMoveSelection:1];
                                                            return nil;
                                                        }
                                                        if (event.keyCode == 126) {
                                                            [strongSelf paletteMoveSelection:-1];
                                                            return nil;
                                                        }
                                                        if (event.keyCode == 36 || event.keyCode == 76) {
                                                            [strongSelf activatePaletteSelection:nil];
                                                            return nil;
                                                        }
                                                    }
                                                    if (event.type != NSEventTypeKeyDown &&
                                                        event.window != strongSelf->_palettePanel)
                                                        [strongSelf closePalette:nil];
                                                }
                                                return event;
                                              }];
}

- (void)closePalette:(id)sender {
    (void)sender;
    if (_paletteEventMonitor) {
        [NSEvent removeMonitor:_paletteEventMonitor];
        _paletteEventMonitor = nil;
    }
    _paletteFavoritePendingDelete = nil;
    [_palettePanel orderOut:nil];
}

- (void)paletteFavoriteDeleteClicked:(id)sender {
    NSInteger row = [_paletteTable rowForView:(NSView*)sender];
    if (row < 0 || row >= (NSInteger)_paletteResults.count) return;

    NSDictionary* result = _paletteResults[(NSUInteger)row];
    if (![result[@"kind"] isEqualToString:@"favorite"]) return;
    NSDictionary* favorite = result[@"favorite"];
    if (!favorite) return;

    if (_paletteFavoritePendingDelete != favorite) {
        _paletteFavoritePendingDelete = favorite;
        [_paletteTable reloadData];
        [_paletteTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        return;
    }

    NSUInteger index = [_favorites indexOfObjectIdenticalTo:favorite];
    if (index == NSNotFound) {
        _paletteFavoritePendingDelete = nil;
        [self refreshPaletteResults];
        return;
    }

    [_favorites removeObjectAtIndex:index];
    _paletteFavoritePendingDelete = nil;
    [self savePersistentState];
    [self refreshPaletteResults];
    _statusLabel.stringValue = @"Favorite deleted.";
}

- (void)activatePaletteSelection:(id)sender {
    (void)sender;
    NSInteger row = _paletteTable.selectedRow;
    if (row < 0 || row >= (NSInteger)_paletteResults.count) return;
    NSDictionary* result = _paletteResults[(NSUInteger)row];
    if (![self isSelectablePaletteResult:result]) return;
    [self closePalette:nil];
    [self openPaletteResult:result];
}

- (void)previousPage:(id)sender {
    (void)sender;
    if (_doc && _pageIndex > 0)
        [self goToPage:_pageIndex - 1 preserveSinglePagePosition:_viewMode == SPDFViewModeSingle];
}

- (void)nextPage:(id)sender {
    (void)sender;
    if (_doc && _pageIndex + 1 < spdf_page_count(_doc))
        [self goToPage:_pageIndex + 1 preserveSinglePagePosition:_viewMode == SPDFViewModeSingle];
}

- (void)firstPage:(id)sender {
    (void)sender;
    if (_doc) [self goToPage:0 preserveSinglePagePosition:_viewMode == SPDFViewModeSingle];
}

- (void)lastPage:(id)sender {
    (void)sender;
    if (_doc) [self goToPage:spdf_page_count(_doc) - 1 preserveSinglePagePosition:_viewMode == SPDFViewModeSingle];
}

- (void)focusPageField:(id)sender {
    (void)sender;
    [_window makeFirstResponder:_pageField];
}

- (void)pageFieldChanged:(id)sender {
    (void)sender;
    if (!_doc) return;
    NSInteger requested = _pageField.integerValue - 1;
    NSInteger pageCount = spdf_page_count(_doc);
    requested = MAX(0, MIN(requested, pageCount - 1));
    [self goToPage:requested preserveSinglePagePosition:_viewMode == SPDFViewModeSingle];
}

- (void)zoomIn:(id)sender {
    (void)sender;
    [self zoomByFactor:1.20 centeredAtWindowPoint:[self visibleCenterWindowPoint]];
}

- (void)zoomOut:(id)sender {
    (void)sender;
    [self zoomByFactor:1.0 / 1.20 centeredAtWindowPoint:[self visibleCenterWindowPoint]];
}

- (void)rememberCurrentZoomForCustomReturn {
    if (_fitMode == SPDFFitModeCustom && _zoom > 0) _rememberedCustomZoom = _zoom;
}

- (void)actualSize:(id)sender {
    (void)sender;
    if (!_doc) return;
    [self rememberCurrentZoomForCustomReturn];
    _fitMode = SPDFFitModeActual;
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO];
    [self persistActiveState];
}

- (void)fitWidth:(id)sender {
    (void)sender;
    if (!_doc) return;
    [self rememberCurrentZoomForCustomReturn];
    _fitMode = SPDFFitModeWidth;
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO];
    [self persistActiveState];
}

- (void)fitHeight:(id)sender {
    (void)sender;
    if (!_doc) return;
    [self rememberCurrentZoomForCustomReturn];
    _fitMode = SPDFFitModeHeight;
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:YES];
    [self persistActiveState];
}

- (void)fitPage:(id)sender {
    (void)sender;
    if (!_doc) return;
    [self rememberCurrentZoomForCustomReturn];
    _fitMode = SPDFFitModePage;
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:YES];
    [self persistActiveState];
}

- (void)fitModePopupChanged:(id)sender {
    (void)sender;
    SPDFFitMode selected = (SPDFFitMode)_fitModePopup.indexOfSelectedItem;
    if (_doc) {
        if (selected == SPDFFitModeCustom)
            _zoom = MAX(kMinZoom, MIN(kMaxZoom, _rememberedCustomZoom > 0 ? _rememberedCustomZoom : _zoom));
        else
            [self rememberCurrentZoomForCustomReturn];
        _fitMode = selected;
        [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO];
        [self persistActiveState];
    } else {
        _fitMode = selected;
    }
}

- (void)setSinglePageMode:(id)sender {
    (void)sender;
    if (!_doc) return;
    NSPoint relativePosition = [self relativeScrollPositionForCurrentPage];
    _viewMode = SPDFViewModeSingle;
    _pageView.viewMode = _viewMode;
    _pageView.currentPageIndex = _pageIndex;
    [self resizeDocumentView];
    [self scrollToPage:_pageIndex preservingRelativePosition:relativePosition];
    [self syncToolbarState];
    [self updateControls];
    [self persistActiveState];
}

- (void)setContinuousMode:(id)sender {
    (void)sender;
    if (!_doc) return;
    NSPoint relativePosition = [self relativeScrollPositionForCurrentPage];
    _viewMode = SPDFViewModeContinuous;
    _pageView.viewMode = _viewMode;
    [self resizeDocumentView];
    [self scrollToPage:_pageIndex preservingRelativePosition:relativePosition];
    [self syncToolbarState];
    [self updateControls];
    [self updateMinimap];
    [self persistActiveState];
}

- (void)toggleContinuous:(id)sender {
    (void)sender;
    if (_continuousButton.state == NSControlStateValueOn)
        [self setContinuousMode:sender];
    else
        [self setSinglePageMode:sender];
}

- (void)toggleSidebar:(id)sender {
    (void)sender;
    BOOL canShowSidebar = _doc && (_outline.count > 0 || _comments.count > 0);
    if (!_sidebarVisible && !canShowSidebar) {
        [self syncToolbarState];
        [self updateControls];
        return;
    }
    _sidebarPreferredVisible = !_sidebarVisible;
    [self rebuildSidebar];
    [self persistActiveState];
}

- (void)toggleSidebarMode:(SPDFSidebarMode)mode {
    if (!_doc) return;
    BOOL hasItems = mode == SPDFSidebarModeChapters ? _outline.count > 0 : _comments.count > 0;
    if (!hasItems) return;
    BOOL sameVisibleMode = _sidebarVisible && _sidebarModeControl.selectedSegment == mode;
    _sidebarPreferredVisible = !sameVisibleMode;
    if (_sidebarPreferredVisible) _sidebarModeControl.selectedSegment = mode;
    [self rebuildSidebar];
    [self persistActiveState];
}

- (void)toggleChaptersPanel:(id)sender {
    (void)sender;
    [self toggleSidebarMode:SPDFSidebarModeChapters];
}

- (void)toggleCommentsPanel:(id)sender {
    (void)sender;
    [self toggleSidebarMode:SPDFSidebarModeComments];
}

- (void)toggleMinimap:(id)sender {
    (void)sender;
    _minimapPreferredVisible = !_minimapPreferredVisible;
    [self setMinimapActuallyVisible:_minimapPreferredVisible];
    [self persistActiveState];
}

- (BOOL)windowIsFullScreen {
    return (_window.styleMask & NSWindowStyleMaskFullScreen) != 0;
}

- (void)applyPresentationChrome {
    BOOL presentation = _presentationMode;
    _tabStrip.hidden = presentation;
    _toolbar.hidden = presentation;
    _tabStripHeightConstraint.constant = presentation ? 0.0 : kTabStripHeight;
    _toolbarHeightConstraint.constant = presentation ? 0.0 : 42.0;
    _pageView.presentationMode = presentation;
    if (presentation) {
        _pageScrollView.hasVerticalScroller = NO;
        _pageScrollView.verticalScroller = nil;
    } else {
        _pageScrollView.verticalScroller = _markerScroller;
        _pageScrollView.hasVerticalScroller = YES;
        _markerScroller.hidden = NO;
    }
    _pageScrollView.autohidesScrollers = presentation;
    _pageScrollView.backgroundColor = presentation ? NSColor.blackColor : NSColor.windowBackgroundColor;
    _pageScrollView.contentView.backgroundColor = presentation ? NSColor.blackColor : NSColor.windowBackgroundColor;
    [_window.contentView layoutSubtreeIfNeeded];
}

- (void)enterPresentationMode:(id)sender {
    if (!_doc || _presentationMode) return;

    _presentationPreviousViewMode = _viewMode;
    _presentationPreviousFitMode = _fitMode;
    _presentationPreviousSidebarPreferredVisible = _sidebarPreferredVisible;
    _presentationPreviousMinimapPreferredVisible = _minimapPreferredVisible;
    _presentationEnteredFullScreen = ![self windowIsFullScreen];
    _presentationMode = YES;

    _sidebarPreferredVisible = NO;
    _minimapPreferredVisible = NO;
    _viewMode = SPDFViewModeSingle;
    _fitMode = SPDFFitModePage;
    _pageView.viewMode = _viewMode;
    _pageView.currentPageIndex = _pageIndex;
    [self applyPresentationChrome];
    [self rebuildSidebar];
    [self setMinimapActuallyVisible:NO];
    [_window makeFirstResponder:_pageView];
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:YES];
    if (_presentationEnteredFullScreen) [_window toggleFullScreen:sender];
}

- (void)leavePresentationModeAndExitFullScreen:(BOOL)exitFullScreen sender:(id)sender {
    if (!_presentationMode) return;

    BOOL shouldExitFullScreen = exitFullScreen && _presentationEnteredFullScreen && [self windowIsFullScreen];
    _presentationMode = NO;
    _presentationEnteredFullScreen = NO;
    _sidebarPreferredVisible = _presentationPreviousSidebarPreferredVisible;
    _minimapPreferredVisible = _presentationPreviousMinimapPreferredVisible;
    _viewMode = _presentationPreviousViewMode;
    _fitMode = _presentationPreviousFitMode;
    _pageView.viewMode = _viewMode;
    _pageView.currentPageIndex = _pageIndex;
    [self applyPresentationChrome];
    [self rebuildSidebar];
    [self setMinimapActuallyVisible:_minimapPreferredVisible];
    if (_doc) [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO];
    [self persistActiveState];
    if (shouldExitFullScreen) [_window toggleFullScreen:sender];
}

- (void)togglePresentation:(id)sender {
    if (_presentationMode)
        [self leavePresentationModeAndExitFullScreen:YES sender:sender];
    else
        [self enterPresentationMode:sender];
}

- (void)toggleFullScreen:(id)sender {
    [_window toggleFullScreen:sender];
}

- (NSString*)ocrToolPath {
    return [self
        executablePathForTool:@"ocrmypdf"
                   candidates:@[ @"/opt/homebrew/bin/ocrmypdf", @"/usr/local/bin/ocrmypdf", @"/usr/bin/ocrmypdf" ]];
}

- (NSString*)tesseractToolPath {
    return [self
        executablePathForTool:@"tesseract"
                   candidates:@[ @"/opt/homebrew/bin/tesseract", @"/usr/local/bin/tesseract", @"/usr/bin/tesseract" ]];
}

- (NSString*)executablePathForTool:(NSString*)tool candidates:(NSArray<NSString*>*)candidates {
    NSFileManager* fm = NSFileManager.defaultManager;
    for (NSString* path in candidates) {
        if ([fm isExecutableFileAtPath:path]) return path;
    }

    NSString* pathEnv = NSProcessInfo.processInfo.environment[@"PATH"] ?: @"";
    for (NSString* dir in [pathEnv componentsSeparatedByString:@":"]) {
        if (dir.length == 0) continue;
        NSString* path = [dir stringByAppendingPathComponent:tool];
        if ([fm isExecutableFileAtPath:path]) return path;
    }
    return nil;
}

- (void)appendOCRInstallLog:(NSString*)text {
    if (!_ocrInstallLog || text.length == 0) return;
    NSTextStorage* storage = _ocrInstallLog.textStorage;
    NSDictionary* attrs = @{
        NSForegroundColorAttributeName : NSColor.labelColor,
        NSFontAttributeName : _ocrInstallLog.font ?: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]
    };
    [storage appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:attrs]];
    [_ocrInstallLog scrollRangeToVisible:NSMakeRange(storage.length, 0)];
}

- (void)showOCRInstallPanel {
    if (!_ocrInstallPanel) {
        _ocrInstallPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 640, 360)
                                                      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                        backing:NSBackingStoreBuffered
                                                          defer:NO];
        _ocrInstallPanel.title = @"Installing OCR";
        _ocrInstallPanel.releasedWhenClosed = NO;

        NSView* content = [[NSView alloc] initWithFrame:_ocrInstallPanel.contentView.bounds];
        content.translatesAutoresizingMaskIntoConstraints = NO;
        _ocrInstallPanel.contentView = content;

        NSTextField* title = [NSTextField labelWithString:@"Installing OCRmyPDF and Tesseract"];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
        [content addSubview:title];

        _ocrInstallProgress = [[NSProgressIndicator alloc] init];
        _ocrInstallProgress.translatesAutoresizingMaskIntoConstraints = NO;
        _ocrInstallProgress.indeterminate = YES;
        _ocrInstallProgress.style = NSProgressIndicatorStyleBar;
        [content addSubview:_ocrInstallProgress];

        NSScrollView* scroll = [[NSScrollView alloc] init];
        scroll.translatesAutoresizingMaskIntoConstraints = NO;
        scroll.hasVerticalScroller = YES;
        [content addSubview:scroll];

        _ocrInstallLog = [[NSTextView alloc] init];
        _ocrInstallLog.editable = NO;
        _ocrInstallLog.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
        _ocrInstallLog.drawsBackground = YES;
        _ocrInstallLog.backgroundColor = NSColor.textBackgroundColor;
        _ocrInstallLog.textColor = NSColor.labelColor;
        scroll.documentView = _ocrInstallLog;

        [NSLayoutConstraint activateConstraints:@[
            [title.topAnchor constraintEqualToAnchor:content.topAnchor constant:14],
            [title.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
            [title.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
            [_ocrInstallProgress.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
            [_ocrInstallProgress.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [_ocrInstallProgress.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
            [scroll.topAnchor constraintEqualToAnchor:_ocrInstallProgress.bottomAnchor constant:12],
            [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
            [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
            [scroll.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-14]
        ]];
    }

    [_ocrInstallPanel center];
    [_ocrInstallPanel makeKeyAndOrderFront:nil];
    [_ocrInstallProgress startAnimation:nil];
}

- (NSString*)ocrInstallScript {
    return @"set -e\n"
           @"export PATH=\"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH\"\n"
           @"export NONINTERACTIVE=1\n"
           @"if command -v brew >/dev/null 2>&1; then BREW=$(command -v brew); "
           @"elif [ -x /opt/homebrew/bin/brew ]; then BREW=/opt/homebrew/bin/brew; "
           @"elif [ -x /usr/local/bin/brew ]; then BREW=/usr/local/bin/brew; "
           @"else echo 'Homebrew not found. Installing Homebrew...'; "
           @"/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"; "
           @"if [ -x /opt/homebrew/bin/brew ]; then BREW=/opt/homebrew/bin/brew; "
           @"elif [ -x /usr/local/bin/brew ]; then BREW=/usr/local/bin/brew; "
           @"else echo 'Homebrew installation did not produce a brew executable.'; exit 1; fi; fi\n"
           @"echo \"Using $BREW\"\n"
           @"\"$BREW\" install ocrmypdf tesseract\n";
}

- (void)installOCRAndRunAfterwards {
    if (_ocrInstallRunning) {
        [_ocrInstallPanel makeKeyAndOrderFront:nil];
        return;
    }

    _ocrInstallRunning = YES;
    _ocrButton.enabled = NO;
    [self showOCRInstallPanel];
    _ocrInstallLog.string = @"";
    [self appendOCRInstallLog:@"Preparing OCR installer...\n"];

    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/bash"];
    task.arguments = @[ @"-lc", [self ocrInstallScript] ];
    NSPipe* pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    _ocrInstallTask = task;

    __weak SumatraMacDelegate* weakSelf = self;
    pipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle* handle) {
      NSData* chunk = handle.availableData;
      if (chunk.length == 0) {
          handle.readabilityHandler = nil;
          return;
      }
      NSString* text = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding] ?: @"";
      dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf appendOCRInstallLog:text];
      });
    };

    task.terminationHandler = ^(NSTask* finishedTask) {
      pipe.fileHandleForReading.readabilityHandler = nil;
      dispatch_async(dispatch_get_main_queue(), ^{
        SumatraMacDelegate* strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_ocrInstallRunning = NO;
        strongSelf->_ocrInstallTask = nil;
        [strongSelf->_ocrInstallProgress stopAnimation:nil];
        strongSelf->_ocrButton.enabled =
            strongSelf->_doc != NULL && [strongSelf->_path.pathExtension.lowercaseString isEqualToString:@"pdf"];
        if (finishedTask.terminationStatus == 0 && [strongSelf ocrToolPath].length &&
            [strongSelf tesseractToolPath].length) {
            [strongSelf appendOCRInstallLog:@"\nOCR tools installed.\n"];
            [strongSelf->_ocrInstallPanel orderOut:nil];
            [strongSelf ocrDocument:nil];
        } else {
            [strongSelf
                appendOCRInstallLog:@"\nOCR installation failed. The log above has the package manager output.\n"];
            strongSelf->_statusLabel.stringValue = @"OCR installation failed.";
        }
      });
    };

    NSError* error = nil;
    if (![task launchAndReturnError:&error]) {
        _ocrInstallRunning = NO;
        _ocrInstallTask = nil;
        [_ocrInstallProgress stopAnimation:nil];
        _ocrButton.enabled = _doc != NULL && [_path.pathExtension.lowercaseString isEqualToString:@"pdf"];
        [self showError:@"Could not start OCR installer" detail:error.localizedDescription ?: @""];
    }
}

- (NSString*)backupPathForPDFPath:(NSString*)path {
    NSString* dir = path.stringByDeletingLastPathComponent;
    NSString* stem = path.stringByDeletingPathExtension.lastPathComponent;
    NSString* ext = path.pathExtension.length ? path.pathExtension : @"pdf";
    NSFileManager* fm = NSFileManager.defaultManager;
    NSString* candidate = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_backup.%@", stem, ext]];
    NSInteger index = 2;
    while ([fm fileExistsAtPath:candidate]) {
        candidate = [dir
            stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_backup_%ld.%@", stem, (long)index, ext]];
        index++;
    }
    return candidate;
}

- (void)ocrDocument:(id)sender {
    (void)sender;
    if (!_doc || !_path.length || ![_path.pathExtension.lowercaseString isEqualToString:@"pdf"]) {
        NSBeep();
        return;
    }

    NSString* tool = [self ocrToolPath];
    NSString* tesseract = [self tesseractToolPath];
    if (!tool.length || !tesseract.length) {
        NSAlert* alert = [[NSAlert alloc] init];
        alert.messageText = @"Install OCR support?";
        alert.informativeText =
            @"SumatraPDF can install OCRmyPDF and Tesseract, then continue OCR automatically when "
            @"installation finishes.";
        [alert addButtonWithTitle:@"Install"];
        [alert addButtonWithTitle:@"Cancel"];
        alert.alertStyle = NSAlertStyleInformational;
        if ([alert runModal] == NSAlertFirstButtonReturn) [self installOCRAndRunAfterwards];
        return;
    }

    char err[1024];
    int hasText = spdf_document_has_text(_doc, 0, err, sizeof(err));
    if (hasText < 0) {
        [self showError:@"Could not inspect document text"
                 detail:[NSString stringWithUTF8String:err[0] ? err : "Unknown error"]];
        return;
    }

    NSString* backupPath = nil;
    if (hasText > 0) {
        NSAlert* alert = [[NSAlert alloc] init];
        alert.messageText = @"This PDF already contains selectable text.";
        alert.informativeText = @"SumatraPDF will make a backup of the original file before OCR replaces it.";
        [alert addButtonWithTitle:@"OCR and Backup"];
        [alert addButtonWithTitle:@"Cancel"];
        alert.alertStyle = NSAlertStyleWarning;
        if ([alert runModal] != NSAlertFirstButtonReturn) return;

        backupPath = [self backupPathForPDFPath:_path];
        NSError* copyError = nil;
        if (![NSFileManager.defaultManager copyItemAtPath:_path toPath:backupPath error:&copyError]) {
            [self showError:@"Could not create OCR backup" detail:copyError.localizedDescription ?: @""];
            return;
        }
    }

    NSString* originalPath = [_path copy];
    NSInteger originalPage = _pageIndex;
    NSString* dir = originalPath.stringByDeletingLastPathComponent;
    NSString* tmp = [dir
        stringByAppendingPathComponent:[NSString stringWithFormat:@".%@.ocr-%@.pdf", originalPath.lastPathComponent,
                                                                  NSUUID.UUID.UUIDString]];
    NSInteger jobs = MAX(1, NSProcessInfo.processInfo.activeProcessorCount);
    NSMutableArray<NSString*>* args = [@[
        @"--jobs", [NSString stringWithFormat:@"%ld", (long)jobs], @"--rotate-pages", @"--deskew", @"--optimize", @"1"
    ] mutableCopy];
    [args addObject:hasText > 0 ? @"--redo-ocr" : @"--skip-text"];
    [args addObject:originalPath];
    [args addObject:tmp];

    _ocrButton.enabled = NO;
    _statusLabel.stringValue = [NSString stringWithFormat:@"OCR running with %ld workers...", (long)jobs];

    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:tool];
    task.arguments = args;
    NSPipe* pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    __block NSMutableData* outputData = [NSMutableData data];
    pipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle* handle) {
      NSData* chunk = handle.availableData;
      if (chunk.length > 0) {
          @synchronized(outputData) {
              [outputData appendData:chunk];
          }
      } else {
          handle.readabilityHandler = nil;
      }
    };

    __weak SumatraMacDelegate* weakSelf = self;
    task.terminationHandler = ^(NSTask* finishedTask) {
      pipe.fileHandleForReading.readabilityHandler = nil;
      NSData* tail = pipe.fileHandleForReading.readDataToEndOfFile;
      if (tail.length > 0) {
          @synchronized(outputData) {
              [outputData appendData:tail];
          }
      }
      NSData* data = nil;
      @synchronized(outputData) {
          data = [outputData copy];
      }
      NSString* output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
      dispatch_async(dispatch_get_main_queue(), ^{
        SumatraMacDelegate* strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_ocrButton.enabled =
            strongSelf->_doc != NULL && [strongSelf->_path.pathExtension.lowercaseString isEqualToString:@"pdf"];
        if (finishedTask.terminationStatus != 0) {
            [NSFileManager.defaultManager removeItemAtPath:tmp error:nil];
            NSString* detail = output.length > 1200 ? [output substringToIndex:1200] : output;
            [strongSelf showError:@"OCR failed" detail:detail.length ? detail : @"OCRmyPDF exited with an error."];
            strongSelf->_statusLabel.stringValue = @"OCR failed.";
            return;
        }

        [strongSelf->_renderQueue cancelAllOperations];
        [strongSelf->_queuedRenderPages removeAllObjects];
        strongSelf->_renderGeneration++;
        spdf_close(strongSelf->_doc);
        strongSelf->_doc = NULL;
        NSError* moveError = nil;
        NSURL* resultingURL = nil;
        if (![NSFileManager.defaultManager replaceItemAtURL:[NSURL fileURLWithPath:originalPath]
                                              withItemAtURL:[NSURL fileURLWithPath:tmp]
                                             backupItemName:nil
                                                    options:0
                                           resultingItemURL:&resultingURL
                                                      error:&moveError]) {
            [strongSelf showError:@"Could not save OCR output" detail:moveError.localizedDescription ?: @""];
            strongSelf->_statusLabel.stringValue = @"OCR output was not installed.";
            return;
        }

        if (strongSelf->_selectedTabIndex >= 0 && strongSelf->_selectedTabIndex < (NSInteger)strongSelf->_tabs.count) {
            SPDFDocumentTab* tab = strongSelf->_tabs[(NSUInteger)strongSelf->_selectedTabIndex];
            tab.pageIndex = originalPage;
        }
        [strongSelf loadSelectedTab];
        if (backupPath.length)
            strongSelf->_statusLabel.stringValue =
                [NSString stringWithFormat:@"OCR complete. Backup: %@", backupPath.lastPathComponent];
        else
            strongSelf->_statusLabel.stringValue = @"OCR complete.";
      });
    };

    NSError* launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        _ocrButton.enabled = YES;
        [NSFileManager.defaultManager removeItemAtPath:tmp error:nil];
        [self showError:@"Could not start OCR" detail:launchError.localizedDescription ?: @""];
    }
}

- (void)printDocument:(id)sender {
    (void)sender;
    if (!_doc) {
        NSBeep();
        return;
    }

    char err[1024];
    for (NSInteger i = 0; i < (NSInteger)_renderedPages.count; ++i) {
        if (!_renderedPages[(NSUInteger)i].image) {
            SPDFRenderedPage* page = [self renderedPageAtIndex:i error:err errorLength:sizeof(err)];
            if (!page) {
                [self showError:@"Could not prepare print job"
                         detail:[NSString stringWithUTF8String:err[0] ? err : "Unknown error"]];
                return;
            }
            [_renderedPages replaceObjectAtIndex:(NSUInteger)i withObject:page];
        }
    }

    NSPrintInfo* info = [NSPrintInfo.sharedPrintInfo copy];
    info.horizontalPagination = NSPrintingPaginationModeClip;
    info.verticalPagination = NSPrintingPaginationModeClip;
    info.horizontallyCentered = YES;
    info.verticallyCentered = YES;

    NSSize paper = info.paperSize;
    SPDFPrintView* printView = [[SPDFPrintView alloc]
        initWithFrame:NSMakeRect(0, 0, paper.width, paper.height * MAX(1, (NSInteger)_renderedPages.count))];
    printView.pages = _renderedPages;

    NSPrintOperation* operation = [NSPrintOperation printOperationWithView:printView printInfo:info];
    operation.showsPrintPanel = YES;
    operation.showsProgressPanel = YES;
    [operation runOperationModalForWindow:_window delegate:nil didRunSelector:NULL contextInfo:NULL];
}

- (void)showProperties:(id)sender {
    (void)sender;
    if (!_doc) return;
    NSString* message =
        [NSString stringWithFormat:@"%@\n%ld pages\n%@",
                                   spdf_title(_doc) ? [NSString stringWithUTF8String:spdf_title(_doc)] : @"Untitled",
                                   (long)spdf_page_count(_doc), _path ?: @""];
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Document Properties";
    alert.informativeText = message;
    [alert runModal];
}

- (void)openInExternalReader:(id)sender {
    (void)sender;
    if (!_path.length) {
        NSBeep();
        return;
    }

    NSURL* fileURL = [NSURL fileURLWithPath:_path];
    NSURL* acrobat = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.adobe.Reader"];
    if (!acrobat)
        acrobat = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.adobe.Acrobat.Pro"];
    if (acrobat) {
        NSWorkspaceOpenConfiguration* config = [NSWorkspaceOpenConfiguration configuration];
        [NSWorkspace.sharedWorkspace openURLs:@[ fileURL ]
                         withApplicationAtURL:acrobat
                                configuration:config
                            completionHandler:nil];
    } else {
        [NSWorkspace.sharedWorkspace openURL:fileURL];
    }
}

- (void)showInFolder:(id)sender {
    (void)sender;
    if (!_doc || !_path.length) {
        NSBeep();
        return;
    }

    NSURL* fileURL = [NSURL fileURLWithPath:_path];
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[ fileURL ]];
}

- (void)copyCurrentPageImage:(id)sender {
    (void)sender;
    if (!_doc || _pageIndex < 0 || _pageIndex >= (NSInteger)_renderedPages.count ||
        !_renderedPages[(NSUInteger)_pageIndex].image) {
        NSBeep();
        return;
    }

    NSPasteboard* pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard writeObjects:@[ _renderedPages[(NSUInteger)_pageIndex].image ]];
    _statusLabel.stringValue = @"Page image copied.";
}

- (void)showContextMenuForDocumentView:(NSView*)view event:(NSEvent*)event {
    [self documentViewEndHoverComment];
    _contextPageIndex = -1;
    _contextPagePoint = NSZeroPoint;
    _contextCommentIndex = -1;
    if ([view isKindOfClass:SPDFDocumentView.class]) {
        SPDFDocumentView* documentView = (SPDFDocumentView*)view;
        NSPoint point = [documentView convertPoint:event.locationInWindow fromView:nil];
        [documentView point:point fallsInPage:&_contextPageIndex pagePoint:&_contextPagePoint];
        _contextCommentIndex = [self commentIndexAtPageIndex:_contextPageIndex pagePoint:_contextPagePoint];
    }

    NSMenu* menu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem* copy = [menu addItemWithTitle:@"Copy" action:@selector(copySelection:) keyEquivalent:@""];
    copy.enabled = _selectedText.length > 0;
    if (_contextCommentIndex >= 0) {
        NSMenuItem* editComment =
            [menu addItemWithTitle:@"Edit Comment..." action:@selector(editComment:) keyEquivalent:@""];
        editComment.target = self;
        editComment.representedObject = @(_contextCommentIndex);
        NSMenuItem* deleteComment =
            [menu addItemWithTitle:@"Delete Comment..." action:@selector(deleteComment:) keyEquivalent:@""];
        deleteComment.target = self;
        deleteComment.representedObject = @(_contextCommentIndex);
    }
    NSMenuItem* addComment = [menu addItemWithTitle:@"Add Comment..." action:@selector(addComment:) keyEquivalent:@""];
    addComment.enabled = _doc != NULL && (_selectedText.length > 0 || _contextPageIndex >= 0);
    NSMenuItem* copyImage =
        [menu addItemWithTitle:@"Copy Page Image" action:@selector(copyCurrentPageImage:) keyEquivalent:@""];
    copyImage.enabled = _doc && _pageIndex >= 0 && _pageIndex < (NSInteger)_renderedPages.count &&
                        _renderedPages[(NSUInteger)_pageIndex].image != nil;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Zoom In" action:@selector(zoomIn:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Zoom Out" action:@selector(zoomOut:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Fit Width" action:@selector(fitWidth:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Fit Page" action:@selector(fitPage:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* favorite =
        [menu addItemWithTitle:@"Favorite Page" action:@selector(favoriteCurrentPage:) keyEquivalent:@""];
    favorite.enabled = _doc != NULL;
    NSMenuItem* showInFolder =
        [menu addItemWithTitle:@"Show in Folder" action:@selector(showInFolder:) keyEquivalent:@""];
    showInFolder.enabled = _doc != NULL && _path.length > 0;
    [menu addItemWithTitle:@"Properties..." action:@selector(showProperties:) keyEquivalent:@""];
    [NSMenu popUpContextMenu:menu withEvent:event forView:view];
}

- (void)unimplementedMenuItem:(id)sender {
    (void)sender;
    NSBeep();
    _statusLabel.stringValue = @"This SumatraPDF command is listed but not implemented yet.";
}

- (void)findNext:(id)sender {
    (void)sender;
    [self findFromCurrentForward:YES];
}

- (void)findPrevious:(id)sender {
    (void)sender;
    [self findFromCurrentForward:NO];
}

- (void)findFromCurrentForward:(BOOL)forward {
    if (!_doc || _searchField.stringValue.length == 0) return;

    if (_findMatches.count == 0) {
        [self startFindForCurrentQuery];
        return;
    }
    NSInteger next = _findMatchIndex;
    if (next < 0)
        next = forward ? 0 : (NSInteger)_findMatches.count - 1;
    else
        next = (next + (forward ? 1 : -1) + (NSInteger)_findMatches.count) % (NSInteger)_findMatches.count;
    [self jumpToFindMatchAtIndex:next];
}

- (void)controlTextDidChange:(NSNotification*)notification {
    if (notification.object == _searchField) {
        [self startFindForCurrentQuery];
    } else if (notification.object == _paletteSearchField) {
        _paletteFavoritePendingDelete = nil;
        [self refreshPaletteResults];
    }
}

- (BOOL)control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)commandSelector {
    (void)textView;
    if (control == _searchField) {
        if (commandSelector == @selector(cancelOperation:)) {
            if (_searchField.stringValue.length > 0) {
                _searchField.stringValue = @"";
                [self startFindForCurrentQuery];
            }
            [self clearFindFieldFocus];
            return YES;
        }
        if (commandSelector == @selector(insertNewline:) ||
            commandSelector == @selector(insertNewlineIgnoringFieldEditor:)) {
            if (_findMatchIndex >= 0 && _findMatchIndex < (NSInteger)_findMatches.count)
                [self jumpToFindMatchAtIndex:_findMatchIndex];
            else
                [self startFindForCurrentQuery];
            return YES;
        }
        return NO;
    }
    if (control != _paletteSearchField) return NO;
    if (commandSelector == @selector(moveDown:)) {
        [self paletteMoveSelection:1];
        return YES;
    }
    if (commandSelector == @selector(moveUp:)) {
        [self paletteMoveSelection:-1];
        return YES;
    }
    if (commandSelector == @selector(insertNewline:) ||
        commandSelector == @selector(insertNewlineIgnoringFieldEditor:)) {
        [self activatePaletteSelection:control];
        return YES;
    }
    if (commandSelector == @selector(cancelOperation:)) {
        [self closePalette:control];
        return YES;
    }
    return NO;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    if (tableView == _paletteTable) return (NSInteger)_paletteResults.count;
    return (NSInteger)_sidebarItems.count;
}

- (CGFloat)tableView:(NSTableView*)tableView heightOfRow:(NSInteger)row {
    if (tableView != _paletteTable) return _sidebarTable.rowHeight;
    return [self paletteHeightForRow:row];
}

- (NSIndexSet*)tableView:(NSTableView*)tableView
    selectionIndexesForProposedSelection:(NSIndexSet*)proposedSelectionIndexes {
    if (tableView != _paletteTable) return proposedSelectionIndexes;
    NSMutableIndexSet* filtered = [NSMutableIndexSet indexSet];
    [proposedSelectionIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL* stop) {
      (void)stop;
      if (idx < self->_paletteResults.count && [self isSelectablePaletteResult:self->_paletteResults[idx]])
          [filtered addIndex:idx];
    }];
    return filtered;
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
    (void)tableColumn;
    if (tableView == _paletteTable) {
        NSDictionary* result = _paletteResults[(NSUInteger)row];
        NSString* kind = result[@"kind"];
        if ([kind isEqualToString:@"separator"]) {
            return [[NSView alloc] initWithFrame:NSZeroRect];
        }

        if ([kind isEqualToString:@"header"]) {
            NSView* view = [tableView makeViewWithIdentifier:@"PaletteHeader" owner:self];
            NSView* capsule = nil;
            NSTextField* label = nil;
            if (!view) {
                view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 620, 32)];
                view.identifier = @"PaletteHeader";

                capsule = [[NSView alloc] init];
                capsule.translatesAutoresizingMaskIntoConstraints = NO;
                capsule.identifier = @"capsule";
                capsule.wantsLayer = YES;
                capsule.layer.cornerRadius = 8.0;
                capsule.layer.masksToBounds = YES;
                [view addSubview:capsule];

                label = [NSTextField labelWithString:@""];
                label.translatesAutoresizingMaskIntoConstraints = NO;
                label.identifier = @"title";
                label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
                [capsule addSubview:label];
                [NSLayoutConstraint activateConstraints:@[
                    [capsule.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:40],
                    [capsule.trailingAnchor constraintLessThanOrEqualToAnchor:view.trailingAnchor constant:-40],
                    [capsule.topAnchor constraintEqualToAnchor:view.topAnchor constant:5],
                    [capsule.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-3],
                    [label.leadingAnchor constraintEqualToAnchor:capsule.leadingAnchor constant:12],
                    [label.trailingAnchor constraintEqualToAnchor:capsule.trailingAnchor constant:-12],
                    [label.centerYAnchor constraintEqualToAnchor:capsule.centerYAnchor]
                ]];
            }
            for (NSView* subview in view.subviews) {
                if ([subview.identifier isEqualToString:@"capsule"]) {
                    capsule = subview;
                    for (NSView* inner in capsule.subviews)
                        if ([inner.identifier isEqualToString:@"title"]) label = (NSTextField*)inner;
                }
            }
            NSColor* capsuleColor = [[NSColor.controlAccentColor colorWithAlphaComponent:0.16]
                colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            capsule.layer.backgroundColor = capsuleColor.CGColor;
            label.textColor = NSColor.labelColor;
            label.stringValue = result[@"title"] ?: @"";
            return view;
        }

        if ([kind isEqualToString:@"favorite"]) {
            NSTableCellView* cell = [tableView makeViewWithIdentifier:@"PaletteFavoriteCell" owner:self];
            NSButton* deleteButton = nil;
            NSTextField* subtitle = nil;
            NSLayoutConstraint* deleteWidth = nil;
            if (!cell) {
                cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 620, 44)];
                cell.identifier = @"PaletteFavoriteCell";

                deleteButton =
                    [NSButton buttonWithTitle:@"" target:self action:@selector(paletteFavoriteDeleteClicked:)];
                deleteButton.translatesAutoresizingMaskIntoConstraints = NO;
                deleteButton.identifier = @"favoriteDelete";
                deleteButton.bezelStyle = NSBezelStyleRounded;
                deleteButton.bordered = YES;
                deleteButton.controlSize = NSControlSizeSmall;
                deleteButton.focusRingType = NSFocusRingTypeNone;
                deleteButton.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
                deleteButton.toolTip = @"Delete favorite";
                [cell addSubview:deleteButton];

                NSTextField* title = [NSTextField labelWithString:@""];
                title.translatesAutoresizingMaskIntoConstraints = NO;
                title.lineBreakMode = NSLineBreakByTruncatingMiddle;
                title.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
                cell.textField = title;
                [cell addSubview:title];

                subtitle = [NSTextField labelWithString:@""];
                subtitle.translatesAutoresizingMaskIntoConstraints = NO;
                subtitle.identifier = @"subtitle";
                subtitle.lineBreakMode = NSLineBreakByTruncatingMiddle;
                subtitle.font = [NSFont systemFontOfSize:11];
                subtitle.textColor = NSColor.secondaryLabelColor;
                [cell addSubview:subtitle];

                deleteWidth = [deleteButton.widthAnchor constraintEqualToConstant:28];
                deleteWidth.identifier = @"favoriteDeleteWidth";
                [NSLayoutConstraint activateConstraints:@[
                    [deleteButton.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:8],
                    [deleteButton.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
                    [deleteButton.heightAnchor constraintEqualToConstant:26], deleteWidth,
                    [title.leadingAnchor constraintEqualToAnchor:deleteButton.trailingAnchor constant:8],
                    [title.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-10],
                    [title.topAnchor constraintEqualToAnchor:cell.topAnchor constant:6],
                    [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
                    [subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
                    [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2]
                ]];
            }

            for (NSView* subview in cell.subviews) {
                if ([subview.identifier isEqualToString:@"favoriteDelete"]) deleteButton = (NSButton*)subview;
                if ([subview.identifier isEqualToString:@"subtitle"]) subtitle = (NSTextField*)subview;
            }
            for (NSLayoutConstraint* constraint in deleteButton.constraints) {
                if ([constraint.identifier isEqualToString:@"favoriteDeleteWidth"]) deleteWidth = constraint;
            }

            BOOL armed = _paletteFavoritePendingDelete == result[@"favorite"];
            deleteWidth.constant = armed ? 116.0 : 28.0;
            NSString* deleteTitle = armed ? @"Confirm Delete" : @"\u00D7";
            NSDictionary* attributes = @{
                NSForegroundColorAttributeName : armed ? NSColor.systemRedColor : NSColor.secondaryLabelColor,
                NSFontAttributeName : [NSFont systemFontOfSize:armed ? 11.0 : 17.0
                                                        weight:armed ? NSFontWeightSemibold : NSFontWeightRegular]
            };
            deleteButton.attributedTitle =
                [[NSAttributedString alloc] initWithString:deleteTitle attributes:attributes];
            deleteButton.bordered = YES;
            deleteButton.bezelStyle = NSBezelStyleRounded;
            deleteButton.toolTip = armed ? @"Click again to delete this favorite" : @"Delete favorite";

            cell.textField.stringValue = result[@"title"] ?: @"";
            cell.textField.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
            cell.textField.textColor = NSColor.labelColor;
            subtitle.stringValue = result[@"subtitle"] ?: @"";
            subtitle.textColor = NSColor.secondaryLabelColor;
            return cell;
        }

        NSTableCellView* cell = [tableView makeViewWithIdentifier:@"PaletteCell" owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 620, 44)];
            cell.identifier = @"PaletteCell";

            NSTextField* title = [NSTextField labelWithString:@""];
            title.translatesAutoresizingMaskIntoConstraints = NO;
            title.lineBreakMode = NSLineBreakByTruncatingMiddle;
            title.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
            cell.textField = title;
            [cell addSubview:title];

            NSTextField* subtitle = [NSTextField labelWithString:@""];
            subtitle.translatesAutoresizingMaskIntoConstraints = NO;
            subtitle.identifier = @"subtitle";
            subtitle.lineBreakMode = NSLineBreakByTruncatingMiddle;
            subtitle.font = [NSFont systemFontOfSize:11];
            subtitle.textColor = NSColor.secondaryLabelColor;
            [cell addSubview:subtitle];

            [NSLayoutConstraint activateConstraints:@[
                [title.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:12],
                [title.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-10],
                [title.topAnchor constraintEqualToAnchor:cell.topAnchor constant:6],
                [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
                [subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
                [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2]
            ]];
        }

        cell.textField.stringValue = result[@"title"] ?: @"";
        BOOL status = [kind isEqualToString:@"status"];
        cell.textField.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        cell.textField.textColor = status ? NSColor.secondaryLabelColor : NSColor.labelColor;
        for (NSView* subview in cell.subviews) {
            if ([subview.identifier isEqualToString:@"subtitle"]) {
                ((NSTextField*)subview).stringValue = result[@"subtitle"] ?: @"";
                ((NSTextField*)subview).textColor = NSColor.secondaryLabelColor;
            }
        }
        return cell;
    }

    NSTableCellView* cell = [tableView makeViewWithIdentifier:@"SidebarCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 230, 25)];
        cell.identifier = @"SidebarCell";
        NSTextField* field = [NSTextField labelWithString:@""];
        field.translatesAutoresizingMaskIntoConstraints = NO;
        field.lineBreakMode = NSLineBreakByTruncatingTail;
        cell.textField = field;
        [cell addSubview:field];
        [NSLayoutConstraint activateConstraints:@[
            [field.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:8],
            [field.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-6],
            [field.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
        ]];
    }

    if (row < 0 || row >= (NSInteger)_sidebarItems.count) return nil;

    NSDictionary* item = _sidebarItems[(NSUInteger)row];
    id levelValue = item[@"level"];
    NSInteger level = [levelValue respondsToSelector:@selector(integerValue)] ? [levelValue integerValue] : 0;
    level = MAX(0, MIN(level, 16));
    id titleValue = item[@"title"];
    NSString* title = [titleValue isKindOfClass:[NSString class]] ? titleValue : @"";
    id pageValue = item[@"page"];
    NSInteger page = [pageValue respondsToSelector:@selector(integerValue)] ? [pageValue integerValue] : -1;
    NSString* indent = [@"" stringByPaddingToLength:(NSUInteger)(level * 3) withString:@" " startingAtIndex:0];
    cell.textField.stringValue = [indent stringByAppendingString:title ?: @""];
    cell.textField.font = [NSFont systemFontOfSize:13];
    cell.textField.textColor = page >= 0 ? NSColor.labelColor : NSColor.secondaryLabelColor;
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
    if (notification.object == _paletteTable) return;
    if (_updatingSelection) return;
    if (_sidebarTable.clickedRow >= 0) return;
    [self activateSidebarRow:notification.object];
}

- (void)activateSidebarRow:(id)sender {
    (void)sender;
    if (!_doc) return;
    if (_updatingSelection) return;
    NSInteger row = _sidebarTable.clickedRow >= 0 ? _sidebarTable.clickedRow : _sidebarTable.selectedRow;
    if (row < 0 || row >= (NSInteger)_sidebarItems.count) return;
    NSDictionary* item = _sidebarItems[(NSUInteger)row];
    NSInteger page = [item[@"page"] integerValue];
    if (page < 0) return;

    _pageIndex = MAX(0, MIN(page, spdf_page_count(_doc) - 1));
    _pageView.currentPageIndex = _pageIndex;
    [self renderPageIfNeededAtIndex:_pageIndex];
    [self resizeDocumentView];

    NSValue* boundsValue = item[@"bounds"];
    if ([item[@"kind"] isEqualToString:@"comment"] && boundsValue) {
        NSRect bounds = [boundsValue rectValue];
        [self scrollToPageRect:bounds pageIndex:_pageIndex];
        [self flashPageRect:bounds pageIndex:_pageIndex];
    } else {
        [self scrollToPage:_pageIndex alignTop:YES];
    }
    [self updateControls];
}

- (BOOL)validateMenuItem:(NSMenuItem*)menuItem {
    SEL action = menuItem.action;
    BOOL hasDoc = _doc != NULL;
    if (action == @selector(openDocument:) || action == @selector(toggleFullScreen:) ||
        action == @selector(showFavoritesPalette:) || action == @selector(showFindPalette:) ||
        action == @selector(focusFind:) || action == @selector(setCommentAuthor:))
        return YES;
    if (action == @selector(toggleSidebar:)) {
        menuItem.title = _sidebarVisible ? @"Hide Side Panel" : @"Show Side Panel";
        menuItem.state = _sidebarVisible ? NSControlStateValueOn : NSControlStateValueOff;
        return hasDoc;
    }
    if (action == @selector(toggleChaptersPanel:) || action == @selector(toggleCommentsPanel:)) {
        BOOL chapters = action == @selector(toggleChaptersPanel:);
        BOOL hasItems = chapters ? _outline.count > 0 : _comments.count > 0;
        NSString* panelName = chapters ? @"Chapters Panel" : @"Comments Panel";
        BOOL selectedVisible = _sidebarVisible && _sidebarModeControl.selectedSegment ==
                                                      (chapters ? SPDFSidebarModeChapters : SPDFSidebarModeComments);
        menuItem.title = [NSString stringWithFormat:@"%@ %@", selectedVisible ? @"Hide" : @"Show", panelName];
        menuItem.state = selectedVisible ? NSControlStateValueOn : NSControlStateValueOff;
        return hasDoc && hasItems;
    }
    if (action == @selector(togglePresentation:)) {
        menuItem.title = _presentationMode ? @"Exit Presentation Mode" : @"Presentation Mode";
        menuItem.state = _presentationMode ? NSControlStateValueOn : NSControlStateValueOff;
        return hasDoc;
    }
    if (action == @selector(toggleMinimap:)) {
        menuItem.title = _minimapVisible ? @"Hide Minimap" : @"Show Minimap";
        menuItem.state = _minimapVisible ? NSControlStateValueOn : NSControlStateValueOff;
        return hasDoc;
    }
    if (action == @selector(toggleFindRegexMultiline:)) {
        menuItem.state = _findRegexMultiline ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    if (action == @selector(copySelection:)) return _selectedText.length > 0;
    if (action == @selector(addComment:)) return hasDoc && (_selectedText.length > 0 || _contextPageIndex >= 0);
    if (action == @selector(editComment:)) return hasDoc && [self commentIndexForEditAction:menuItem] >= 0;
    if (action == @selector(deleteComment:)) return hasDoc && [self commentIndexForEditAction:menuItem] >= 0;
    if (action == @selector(ocrDocument:))
        return hasDoc && [_path.pathExtension.lowercaseString isEqualToString:@"pdf"];
    if (action == @selector(showInFolder:)) return hasDoc && _path.length > 0;
    if (action == @selector(copyCurrentPageImage:))
        return hasDoc && _pageIndex >= 0 && _pageIndex < (NSInteger)_renderedPages.count &&
               _renderedPages[(NSUInteger)_pageIndex].image != nil;
    if (!hasDoc) return action == @selector(unimplementedMenuItem:);

    if (action == @selector(setSinglePageMode:))
        menuItem.state = _viewMode == SPDFViewModeSingle ? NSControlStateValueOn : NSControlStateValueOff;
    else if (action == @selector(setContinuousMode:))
        menuItem.state = _viewMode == SPDFViewModeContinuous ? NSControlStateValueOn : NSControlStateValueOff;
    else if (action == @selector(fitWidth:))
        menuItem.state = _fitMode == SPDFFitModeWidth ? NSControlStateValueOn : NSControlStateValueOff;
    else if (action == @selector(fitHeight:))
        menuItem.state = _fitMode == SPDFFitModeHeight ? NSControlStateValueOn : NSControlStateValueOff;
    else if (action == @selector(fitPage:))
        menuItem.state = _fitMode == SPDFFitModePage ? NSControlStateValueOn : NSControlStateValueOff;
    else if (action == @selector(actualSize:))
        menuItem.state = _fitMode == SPDFFitModeActual ? NSControlStateValueOn : NSControlStateValueOff;

    return YES;
}

- (void)showError:(NSString*)message detail:(NSString*)detail {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = message;
    alert.informativeText = detail ?: @"";
    alert.alertStyle = NSAlertStyleWarning;
    [alert runModal];
}

@end

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        for (int i = 1; i < argc; ++i) {
            if (strcmp(argv[i], "--version") == 0) {
                printf("SumatraPDF portable mac 0.5\n");
                return 0;
            }
        }

        NSApplication* app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyRegular;

        SumatraMacDelegate* delegate = [[SumatraMacDelegate alloc] init];
        for (int i = 1; i < argc; ++i) {
            if (argv[i][0] != '-') {
                delegate.initialPath = [NSString stringWithUTF8String:argv[i]];
                break;
            }
        }
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
