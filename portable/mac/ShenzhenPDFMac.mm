#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>

#import "SPDFMacDelegatePrivate.h"
#import "SPDFMacDocumentView.h"
#import "SPDFMacModels.h"
#import "SPDFMacMinimapView.h"
#import "SPDFMacPrintView.h"
#import "SPDFMacSupport.h"
#import "SPDFMacTabStripView.h"
#import "SPDFMacUIHelpers.h"

#include "shenzhen_pdf_core.h"

#include <math.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <unistd.h>

static const CGFloat kPageMargin = 44.0;
static const CGFloat kPageGap = 26.0;
static const CGFloat kMinZoom = 0.10;
static const CGFloat kMaxZoom = 8.00;
static const CGFloat kTabStripHeight = 42.0;
static const CGFloat kMinWindowWidth = 560.0;
static const CGFloat kMinWindowHeight = 380.0;
static const CGFloat kDefaultMinimapWidth = 110.0;
static const CGFloat kDefaultSidebarWidth = 240.0;
static const CGFloat kMinSidebarWidth = 176.0;
static const CGFloat kMaxSidebarWidth = 320.0;
static const CGFloat kSidebarMaxWidthFraction = 0.34;
static const CGFloat kMinimapDividerWidth = 5.0;
static const NSInteger kBackgroundRenderBatchSize = 8;
static const NSInteger kRecentDocumentLimit = 10;
static const NSInteger kRenderedImageKeepRadius = 12;
static const NSUInteger kRenderedImageKeepAllTotalByteLimit = (NSUInteger)512 * 1024 * 1024;
static const NSUInteger kRenderedImageKeepAllPerPageByteLimit = (NSUInteger)(2.5 * 1024 * 1024);
static const CGFloat kMaxRenderedPageBitmapDimension = 32760.0;
static const NSUInteger kMaxRenderedPageBitmapByteLimit = (NSUInteger)512 * 1024 * 1024;
static const NSUInteger kRenderedImageSoftByteLimit = (NSUInteger)192 * 1024 * 1024;
static const NSUInteger kRenderedImageTargetByteLimit = (NSUInteger)128 * 1024 * 1024;
static const NSTimeInterval kAfterFirstPaintDelay = 0.05;

#ifndef SPDF_MAC_TRANSLATION_CORE_READY
#define SPDF_MAC_TRANSLATION_CORE_READY 0
#endif

typedef struct SPDFPageAnchor {
    NSInteger pageIndex;
    NSPoint pagePoint;
    NSPoint offsetInViewport;
    BOOL valid;
} SPDFPageAnchor;

static CGFloat spdf_clamp_cg(CGFloat value, CGFloat minValue, CGFloat maxValue) {
    return MAX(minValue, MIN(maxValue, value));
}

static CGFloat spdf_smoothstep_cg(CGFloat value) {
    value = spdf_clamp_cg(value, 0.0, 1.0);
    return value * value * value * (value * (value * 6.0 - 15.0) + 10.0);
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

@class ShenzhenMacDelegate;

static NSMutableArray<ShenzhenMacDelegate*>* gSPDFWindowControllers;
static BOOL gSPDFTerminatingAllWindows;

static NSDictionary* spdf_dictionary_from_window_frame(NSRect frame) {
    return @{
        @"x" : @(NSMinX(frame)),
        @"y" : @(NSMinY(frame)),
        @"width" : @(NSWidth(frame)),
        @"height" : @(NSHeight(frame))
    };
}

static BOOL spdf_window_frame_from_dictionary(NSDictionary* item, NSRect* frame) {
    if (![item isKindOfClass:NSDictionary.class]) return NO;
    CGFloat width = [item[@"width"] doubleValue];
    CGFloat height = [item[@"height"] doubleValue];
    if (width < kMinWindowWidth || height < kMinWindowHeight) return NO;
    if (frame) *frame = NSMakeRect([item[@"x"] doubleValue], [item[@"y"] doubleValue], width, height);
    return YES;
}

static NSRect spdf_sane_window_frame(NSRect frame, NSScreen* fallbackScreen) {
    NSScreen* bestScreen = nil;
    CGFloat bestArea = 0;
    for (NSScreen* screen in NSScreen.screens) {
        NSRect intersection = NSIntersectionRect(frame, screen.visibleFrame);
        CGFloat area = NSWidth(intersection) * NSHeight(intersection);
        if (area > bestArea) {
            bestArea = area;
            bestScreen = screen;
        }
    }
    NSScreen* screen = bestScreen ?: fallbackScreen ?: NSScreen.mainScreen;
    NSRect visible = screen.visibleFrame;
    frame.size.width = MAX(kMinWindowWidth, MIN(NSWidth(frame), NSWidth(visible)));
    frame.size.height = MAX(kMinWindowHeight, MIN(NSHeight(frame), NSHeight(visible)));
    if (bestArea < 80.0 * 80.0) {
        frame.origin.x = floor(NSMidX(visible) - NSWidth(frame) / 2.0);
        frame.origin.y = floor(NSMidY(visible) - NSHeight(frame) / 2.0);
    } else {
        frame.origin.x = MIN(MAX(NSMinX(frame), NSMinX(visible)), NSMaxX(visible) - NSWidth(frame));
        frame.origin.y = MIN(MAX(NSMinY(frame), NSMinY(visible)), NSMaxY(visible) - NSHeight(frame));
    }
    return frame;
}

static NSString* spdf_json_string_from_object(id object) {
    NSData* data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

static NSDictionary* spdf_json_dictionary_from_string(NSString* string) {
    NSData* data = [string dataUsingEncoding:NSUTF8StringEncoding];
    id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [object isKindOfClass:NSDictionary.class] ? object : nil;
}

@implementation ShenzhenMacDelegate

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    (void)notification;
    _zoom = 1.0;
    _rememberedCustomZoom = 1.0;
    _fitMode = SPDFFitModePage;
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
    _presentationUsingBorderlessWindow = NO;
    _pendingWindowArrangementAction = NULL;
    _translationRunning = NO;
    _translationInstallRunning = NO;
    _showShortcutHelpOnLaunch = YES;
    _terminateOnlyThisProcess = NO;
    _suppressSessionWriteOnTerminate = NO;
    _suspendPersistentStateSaves = NO;
    _needsDeferredPersistentStateSave = NO;
    _suppressViewportRerender = NO;
    _liveZooming = NO;
    _restoringSidebarLayout = NO;
    _allowSidebarWidthPersistence = NO;
    _sidebarWidth = kDefaultSidebarWidth;
    _minimapWidth = kDefaultMinimapWidth;
    _findRegexMultiline = YES;
    _translationSourceLanguage = @"zh";
    _translationTargetLanguage = @"en";
    _chapterFilterText = @"";
    _commentFilterText = @"";
    _sidebarItems = [NSMutableArray array];
    _renderedPages = [NSMutableArray array];
    _tabs = [NSMutableArray array];
    _favorites = [NSMutableArray array];
    _documentStates = [NSMutableDictionary dictionary];
    _recentlyOpenedPaths = [NSMutableArray array];
    _closedDocumentPaths = [NSMutableArray array];
    _paletteFavoritePendingDelete = nil;
    _findHighlights = [NSMutableDictionary dictionary];
    _findMatches = [NSMutableArray array];
    _preloadingPaths = [NSMutableSet set];
    _preloadTokens = [NSMutableDictionary dictionary];
    _findMatchIndex = -1;
    _paletteResults = [NSMutableArray array];
    _shortcutHelpRows = [NSMutableArray array];
    _pendingOpenPaths = [NSMutableArray array];
    _pendingRestoreWindowIDs = [NSMutableArray array];
    _queuedRenderPages = [NSMutableSet set];
    _queuedRenderOperations = [NSMutableDictionary dictionary];
    _queuedMinimapThumbnailPages = [NSMutableSet set];
    _selectedTabIndex = -1;
    _windowSessionID = NSUUID.UUID.UUIDString;
    _pendingFindPreferredPage = -1;
    _pendingFindPreferredMatchIndex = -1;

    NSInteger cpuCount = MAX(2, NSProcessInfo.processInfo.activeProcessorCount);
    _renderQueue = [[NSOperationQueue alloc] init];
    _renderQueue.name = @"Shenzhen PDF page renderer";
    _renderQueue.maxConcurrentOperationCount = MAX(2, MIN(cpuCount, (NSInteger)ceil((double)cpuCount * 0.60)));
    _renderQueue.qualityOfService = NSQualityOfServiceUserInitiated;
    _minimapQueue = [[NSOperationQueue alloc] init];
    _minimapQueue.name = @"Shenzhen PDF minimap thumbnails";
    _minimapQueue.maxConcurrentOperationCount = MAX(1, MIN(2, (NSInteger)floor((double)cpuCount * 0.25)));
    _minimapQueue.qualityOfService = NSQualityOfServiceUtility;
    _preloadQueue = [[NSOperationQueue alloc] init];
    _preloadQueue.name = @"Shenzhen PDF tab preloader";
    _preloadQueue.maxConcurrentOperationCount = MAX(1, MIN(2, (NSInteger)floor((double)cpuCount * 0.60)));
    _preloadQueue.qualityOfService = NSQualityOfServiceUtility;
    _findQueue = [[NSOperationQueue alloc] init];
    _findQueue.name = @"Shenzhen PDF document find";
    _findQueue.maxConcurrentOperationCount = 1;
    _findQueue.qualityOfService = NSQualityOfServiceUserInitiated;

    [self loadPersistentState];
    if (!gSPDFWindowControllers) gSPDFWindowControllers = [NSMutableArray array];
    if (![gSPDFWindowControllers containsObject:self]) [gSPDFWindowControllers addObject:self];

    [self buildMenu];
    [self buildWindow];
    _uiReady = YES;
    [_window makeKeyAndOrderFront:nil];
    if (self.restoreWindowID.length == 0) [NSApp activateIgnoringOtherApps:YES];
    dispatch_async(dispatch_get_main_queue(), ^{
      self->_allowSidebarWidthPersistence = YES;
      [self restoreSidebarWidth];
    });

    dispatch_async(dispatch_get_main_queue(), ^{
      [self performWithBatchedPersistentStateSaves:^{
        [self performStartupDocumentWork];
      }];
      if (self->_showShortcutHelpOnLaunch && self.restoreWindowID.length == 0) [self showShortcutHelp:nil];
    });
}

- (void)performStartupDocumentWork {
    NSMutableArray<NSString*>* startupPaths = [NSMutableArray array];
    if (_pendingOpenPath.length > 0) [startupPaths addObject:_pendingOpenPath];
    for (NSString* path in _pendingOpenPaths) {
        if (path.length > 0 && ![startupPaths containsObject:path]) [startupPaths addObject:path];
    }
    if (self.initialPath.length > 0) [startupPaths addObject:self.initialPath];
    _pendingOpenPath = nil;
    [_pendingOpenPaths removeAllObjects];
    if (startupPaths.count > 0) {
        NSArray<NSString*>* pathsToOpen = [self openableDocumentPathsFromPaths:startupPaths showErrors:YES];
        [self openPaths:pathsToOpen];
    } else if (_tabs.count > 0) {
        [self selectTabAtIndex:MAX(0, _selectedTabIndex)];
    } else {
        [self showEmptyDocumentViewWithMessage:@"Open a document"];
    }
    [self spawnPendingRestoredWindowsIfNeeded];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
    (void)sender;
    return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender {
    (void)sender;
    if (!_suppressSessionWriteOnTerminate) [self writeSessionStateForCurrentWindow];
    if (!_terminateOnlyThisProcess && !gSPDFTerminatingAllWindows) {
        gSPDFTerminatingAllWindows = YES;
        for (NSRunningApplication* app in [self otherRunningShenzhenApplications]) [app terminate];
    }
    return NSTerminateNow;
}

- (void)applicationWillTerminate:(NSNotification*)notification {
    (void)notification;
    [self dismissTabHoverPanel];
    [self removePresentationEventMonitor];
    [_translationInstallTask terminate];
    [_translationTask terminate];
    [_renderQueue cancelAllOperations];
    [_minimapQueue cancelAllOperations];
    [_queuedRenderPages removeAllObjects];
    [_queuedRenderOperations removeAllObjects];
    [_queuedMinimapThumbnailPages removeAllObjects];
    [_preloadQueue cancelAllOperations];
    [_findQueue cancelAllOperations];
    [self rememberActiveTabState];
    [self savePersistentState];
    [self clearActiveMetadata];
    [self closeActiveDocumentIfUnowned];
}

- (void)applicationDidResignActive:(NSNotification*)notification {
    (void)notification;
    [self dismissTabHoverPanel];
}

- (BOOL)windowShouldClose:(NSWindow*)sender {
    if (sender != _window) return YES;
    [self dismissTabHoverPanel];
    [self rememberActiveTabState];
    BOOL hasOtherWindows = [self hasOtherShenzhenWindows];
    _terminateOnlyThisProcess = hasOtherWindows;
    if (hasOtherWindows) {
        [self removeSessionStateForCurrentWindow];
        _suppressSessionWriteOnTerminate = YES;
    } else {
        _suppressSessionWriteOnTerminate = NO;
    }
    [self savePersistentState];
    dispatch_async(dispatch_get_main_queue(), ^{
      [NSApp terminate:self];
    });
    return NO;
}

- (BOOL)application:(NSApplication*)sender openFile:(NSString*)filename {
    (void)sender;
    if (!_uiReady) {
        if (!_pendingOpenPath.length) _pendingOpenPath = [filename copy];
        if (filename.length && ![_pendingOpenPaths containsObject:filename]) [_pendingOpenPaths addObject:filename];
        return YES;
    }
    if ([self canOpenDocumentAtPath:filename showError:YES]) [self openPath:filename];
    [self activateWindowForExternalOpen];
    return YES;
}

- (void)application:(NSApplication*)application openFiles:(NSArray<NSString*>*)filenames {
    (void)application;
    if (filenames.count > 0) {
        if (!_uiReady) {
            _pendingOpenPath = [filenames.firstObject copy];
            [_pendingOpenPaths addObjectsFromArray:filenames];
        } else {
            NSArray<NSString*>* pathsToOpen = [self openableDocumentPathsFromPaths:filenames showErrors:YES];
            [self openPaths:pathsToOpen];
            [self activateWindowForExternalOpen];
        }
    }
    [NSApp replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

- (void)windowDidResize:(NSNotification*)notification {
    (void)notification;
    [self dismissTabHoverPanel];
    [self updateTabStripFrame];
    [self updateToolbarOverflow];
    [self restoreSidebarWidth];
    if (_doc && (_fitMode == SPDFFitModeWidth || _fitMode == SPDFFitModeHeight || _fitMode == SPDFFitModePage))
        [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO];
    else {
        [self resizeDocumentView];
        [self renderVisiblePageCropsForCurrentViewportIfNeeded];
        [_pageView setNeedsDisplay:YES];
    }
    [self savePersistentState];
}

- (void)windowDidChangeBackingProperties:(NSNotification*)notification {
    (void)notification;
    [self dismissTabHoverPanel];
    if (_doc)
        [self renderDocumentPreservingScrollPosition];
    else
        [self resizeDocumentView];
}

- (void)windowDidResignKey:(NSNotification*)notification {
    (void)notification;
    [self dismissTabHoverPanel];
}

- (void)windowWillMiniaturize:(NSNotification*)notification {
    (void)notification;
    [self dismissTabHoverPanel];
}

- (void)windowWillEnterFullScreen:(NSNotification*)notification {
    (void)notification;
    [self dismissTabHoverPanel];
}

- (void)windowDidEnterFullScreen:(NSNotification*)notification {
    (void)notification;
    [self dismissTabHoverPanel];
    dispatch_async(dispatch_get_main_queue(), ^{
      [self updateTabStripFrame];
      if (self->_presentationMode && self->_doc) {
          [self renderDocumentAndScrollToPage:self->_pageIndex alignTop:YES];
          [self->_window makeFirstResponder:self->_presentationOverlayView ?: self->_pageView];
      }
    });
}

- (void)windowWillExitFullScreen:(NSNotification*)notification {
    (void)notification;
    [self dismissTabHoverPanel];
}

- (void)windowDidExitFullScreen:(NSNotification*)notification {
    (void)notification;
    [self dismissTabHoverPanel];
    if (_presentationMode && _presentationEnteredFullScreen)
        [self leavePresentationModeAndExitFullScreen:NO sender:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
      [self updateTabStripFrame];
      [self drainPendingWindowArrangementAction];
    });
}

- (NSString*)supportDirectory {
    NSURL* base = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                       inDomains:NSUserDomainMask]
                      .firstObject;
    NSString* dir = [base.path stringByAppendingPathComponent:@"ShenzhenPDF"];
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
        NSNumber* sidebarWidth = settings[@"sidebarWidth"];
        NSNumber* minimapWidth = settings[@"minimapWidth"];
        NSNumber* showShortcutHelp = settings[@"showShortcutHelpOnLaunch"];
        NSDictionary* windowSize = settings[@"windowSize"];
        NSString* commentAuthor = settings[@"commentAuthor"];
        NSString* translateSource = settings[@"translateSourceLanguage"];
        NSString* translateTarget = settings[@"translateTargetLanguage"];
        NSArray* recentlyOpened = settings[@"recentlyOpened"];
        if (fit) _fitMode = (SPDFFitMode)MAX(0, MIN(4, fit.integerValue));
        if (view) _viewMode = (SPDFViewMode)MAX(0, MIN(1, view.integerValue));
        if (sidebarWidth) _sidebarWidth = spdf_sane_sidebar_width(sidebarWidth.doubleValue, 0);
        if (minimapWidth) _minimapWidth = spdf_clamp_cg(minimapWidth.doubleValue, 72.0, 260.0);
        if (showShortcutHelp) _showShortcutHelpOnLaunch = showShortcutHelp.boolValue;
        if ([windowSize isKindOfClass:NSDictionary.class]) {
            _restoredWindowContentSize = spdf_sane_window_content_size(
                NSMakeSize([windowSize[@"width"] doubleValue], [windowSize[@"height"] doubleValue]),
                NSScreen.mainScreen);
        }
        if ([commentAuthor isKindOfClass:NSString.class]) _commentAuthor = [commentAuthor copy];
        if ([translateSource isKindOfClass:NSString.class] && translateSource.length)
            _translationSourceLanguage = [self trimmedLanguageCode:translateSource];
        if ([translateTarget isKindOfClass:NSString.class] && translateTarget.length)
            _translationTargetLanguage = [self trimmedLanguageCode:translateTarget];
        if ([recentlyOpened isKindOfClass:NSArray.class]) {
            for (NSString* path in recentlyOpened) {
                if (![path isKindOfClass:NSString.class] || path.length == 0) continue;
                NSString* standardized = path.stringByStandardizingPath;
                BOOL duplicate = NO;
                for (NSString* existingPath in _recentlyOpenedPaths) {
                    if ([existingPath.stringByStandardizingPath isEqualToString:standardized]) {
                        duplicate = YES;
                        break;
                    }
                }
                if (duplicate) continue;
                [_recentlyOpenedPaths addObject:path];
                if (_recentlyOpenedPaths.count >= kRecentDocumentLimit) break;
            }
        }
    }

    NSArray* favorites = [self jsonObjectFromFile:@"favorites.json"];
    if ([favorites isKindOfClass:NSArray.class]) [_favorites addObjectsFromArray:favorites];

    NSDictionary* documents = [self jsonObjectFromFile:@"documents.json"];
    if ([documents isKindOfClass:NSDictionary.class])
        _documentStates = [documents mutableCopy];
    else
        _documentStates = [NSMutableDictionary dictionary];

    if (self.detachedTabLaunch) return;

    NSMutableDictionary* session =
        [self normalizedMultiWindowSessionFromObject:[self jsonObjectFromFile:@"session.json"]];
    NSArray* windows = session[@"windows"];
    NSDictionary* windowState = nil;
    if (self.restoreWindowID.length > 0) {
        for (NSDictionary* candidate in windows) {
            if ([candidate[@"id"] isEqualToString:self.restoreWindowID]) {
                windowState = candidate;
                break;
            }
        }
    } else {
        windowState = windows.firstObject;
        for (NSUInteger i = 1; i < windows.count; i++) {
            NSString* windowID = [windows[i][@"id"] isKindOfClass:NSString.class] ? windows[i][@"id"] : nil;
            if (windowID.length > 0) [_pendingRestoreWindowIDs addObject:windowID];
        }
    }
    if (windowState)
        [self loadSessionWindowState:windowState];
    else if (self.restoreWindowID.length > 0)
        _windowSessionID = [self.restoreWindowID copy];
}

- (NSMutableDictionary*)normalizedMultiWindowSessionFromObject:(id)object {
    NSMutableArray* windows = [NSMutableArray array];
    if ([object isKindOfClass:NSDictionary.class]) {
        NSDictionary* dictionary = object;
        NSArray* storedWindows = dictionary[@"windows"];
        if ([storedWindows isKindOfClass:NSArray.class]) {
            for (NSDictionary* window in storedWindows) {
                if (![window isKindOfClass:NSDictionary.class]) continue;
                NSMutableDictionary* copy = [window mutableCopy];
                NSString* windowID = [copy[@"id"] isKindOfClass:NSString.class] ? copy[@"id"] : nil;
                if (windowID.length == 0) copy[@"id"] = NSUUID.UUID.UUIDString;
                NSArray* rawTabs = [copy[@"tabs"] isKindOfClass:NSArray.class] ? copy[@"tabs"] : @[];
                NSMutableArray* tabs = [NSMutableArray array];
                for (NSDictionary* tab in rawTabs) {
                    if (![tab isKindOfClass:NSDictionary.class]) continue;
                    NSString* path = [tab[@"path"] isKindOfClass:NSString.class] ? tab[@"path"] : nil;
                    if (path.length > 0) [tabs addObject:tab];
                }
                if (tabs.count == 0) continue;
                copy[@"tabs"] = tabs;
                [windows addObject:copy];
            }
        } else if ([dictionary[@"tabs"] isKindOfClass:NSArray.class]) {
            NSMutableArray* tabs = [NSMutableArray array];
            for (NSDictionary* tab in dictionary[@"tabs"]) {
                if (![tab isKindOfClass:NSDictionary.class]) continue;
                NSString* path = [tab[@"path"] isKindOfClass:NSString.class] ? tab[@"path"] : nil;
                if (path.length > 0) [tabs addObject:tab];
            }
            if (tabs.count == 0) return [@{@"version" : @2, @"windows" : windows} mutableCopy];
            NSMutableDictionary* migrated =
                [@{@"id" : NSUUID.UUID.UUIDString, @"selectedTab" : dictionary[@"selectedTab"] ?: @0, @"tabs" : tabs}
                    mutableCopy];
            [windows addObject:migrated];
        }
    }
    return [@{@"version" : @2, @"windows" : windows} mutableCopy];
}

- (void)loadSessionWindowState:(NSDictionary*)windowState {
    if (![windowState isKindOfClass:NSDictionary.class]) return;
    NSString* windowID = [windowState[@"id"] isKindOfClass:NSString.class] ? windowState[@"id"] : nil;
    if (windowID.length > 0) _windowSessionID = [windowID copy];
    NSRect frame;
    if (spdf_window_frame_from_dictionary(windowState[@"frame"], &frame)) {
        _restoredWindowFrame = spdf_sane_window_frame(frame, NSScreen.mainScreen);
        _hasRestoredWindowFrame = YES;
        _restoredWindowContentSize = _restoredWindowFrame.size;
    }

    NSArray* tabs = [windowState[@"tabs"] isKindOfClass:NSArray.class] ? windowState[@"tabs"] : @[];
    [_tabs removeAllObjects];
    for (NSDictionary* item in tabs) {
        SPDFDocumentTab* tab = spdf_tab_from_dictionary(item);
        if (!tab) continue;
        if (!tab.title.length) tab.title = spdf_display_name_for_path(tab.path);
        if (item[@"showSidebar"] == nil || item[@"showMinimap"] == nil) [self applyStoredDocumentStateToTab:tab];
        [_tabs addObject:tab];
    }
    if (_tabs.count > 0)
        _selectedTabIndex = MIN(MAX(0, [windowState[@"selectedTab"] integerValue]), MAX(0, (NSInteger)_tabs.count - 1));
    else
        _selectedTabIndex = -1;
}

- (NSString*)documentStateKeyForPath:(NSString*)path {
    if (path.length == 0) return @"";
    return path.stringByStandardizingPath ?: path;
}

- (void)applyStoredDocumentStateToTab:(SPDFDocumentTab*)tab {
    if (!tab.path.length) return;
    NSDictionary* state = _documentStates[[self documentStateKeyForPath:tab.path]];
    if (![state isKindOfClass:NSDictionary.class]) return;
    if (state[@"showSidebar"] != nil) tab.showSidebar = [state[@"showSidebar"] boolValue];
    if (state[@"showMinimap"] != nil) tab.showMinimap = [state[@"showMinimap"] boolValue];
}

- (void)saveDocumentStateForTab:(SPDFDocumentTab*)tab {
    if (!tab.path.length) return;
    NSString* key = [self documentStateKeyForPath:tab.path];
    if (!key.length) return;
    NSMutableDictionary* state = [_documentStates[key] isKindOfClass:NSMutableDictionary.class]
                                     ? _documentStates[key]
                                     : [_documentStates[key] mutableCopy];
    if (!state) state = [NSMutableDictionary dictionary];
    state[@"path"] = tab.path;
    state[@"title"] = tab.title.length ? tab.title : spdf_display_name_for_path(tab.path);
    state[@"showSidebar"] = @(tab.showSidebar);
    state[@"showMinimap"] = @(tab.showMinimap);
    state[@"updatedAt"] = @((NSInteger)NSDate.date.timeIntervalSince1970);
    _documentStates[key] = state;
}

- (NSMutableDictionary*)currentWindowSessionDictionary {
    NSMutableArray* tabs = [NSMutableArray array];
    for (SPDFDocumentTab* tab in _tabs) {
        if (!tab.path.length) continue;
        [tabs addObject:@{
            @"path" : tab.path,
            @"title" : tab.title.length ? tab.title : spdf_display_name_for_path(tab.path),
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
            @"findMatchIndex" : @(tab.findMatchIndex),
            @"showSidebar" : @(tab.showSidebar),
            @"showMinimap" : @(tab.showMinimap)
        }];
    }

    NSRect frame = _window ? _window.frame : _restoredWindowFrame;
    if (_presentationMode && _presentationUsingBorderlessWindow) frame = _presentationPreviousWindowFrame;
    if (NSIsEmptyRect(frame)) {
        NSSize contentSize =
            NSEqualSizes(_restoredWindowContentSize, NSZeroSize) ? NSMakeSize(1120, 800) : _restoredWindowContentSize;
        NSRect visible = NSScreen.mainScreen.visibleFrame;
        frame = NSMakeRect(floor(NSMidX(visible) - contentSize.width / 2.0),
                           floor(NSMidY(visible) - contentSize.height / 2.0), contentSize.width, contentSize.height);
    }
    frame = spdf_sane_window_frame(frame, _window.screen ?: NSScreen.mainScreen);
    if (!_windowSessionID.length) _windowSessionID = NSUUID.UUID.UUIDString;
    return [@{
        @"id" : _windowSessionID,
        @"frame" : spdf_dictionary_from_window_frame(frame),
        @"selectedTab" : @(_selectedTabIndex),
        @"tabs" : tabs
    } mutableCopy];
}

- (void)withLockedSessionStore:(void (^)(NSMutableDictionary* session))block {
    if (!block) return;
    NSString* lockPath = [self pathForStateFile:@"session.lock"];
    int fd = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR, 0600);
    if (fd >= 0) flock(fd, LOCK_EX);
    NSMutableDictionary* session =
        [self normalizedMultiWindowSessionFromObject:[self jsonObjectFromFile:@"session.json"]];
    block(session);
    [self writeJSONObject:session toFile:@"session.json"];
    if (fd >= 0) {
        flock(fd, LOCK_UN);
        close(fd);
    }
}

- (void)writeSessionStateForCurrentWindow {
    if (_suppressSessionWriteOnTerminate) return;
    [self rememberActiveTabState];
    if (_tabs.count == 0) {
        [self removeSessionStateForCurrentWindow];
        return;
    }
    NSMutableDictionary* currentWindow = [self currentWindowSessionDictionary];
    [self withLockedSessionStore:^(NSMutableDictionary* session) {
      NSMutableArray* windows = [session[@"windows"] isKindOfClass:NSMutableArray.class] ? session[@"windows"] : nil;
      if (!windows) {
          windows = [NSMutableArray array];
          session[@"windows"] = windows;
      }
      NSUInteger existing = NSNotFound;
      for (NSUInteger i = 0; i < windows.count; i++) {
          if ([windows[i][@"id"] isEqualToString:self->_windowSessionID]) {
              existing = i;
              break;
          }
      }
      if (existing == NSNotFound)
          [windows addObject:currentWindow];
      else
          windows[existing] = currentWindow;
    }];
}

- (void)removeSessionStateForCurrentWindow {
    if (!_windowSessionID.length) return;
    [self withLockedSessionStore:^(NSMutableDictionary* session) {
      NSMutableArray* windows = [session[@"windows"] isKindOfClass:NSMutableArray.class] ? session[@"windows"] : nil;
      if (!windows) return;
      for (NSInteger i = (NSInteger)windows.count - 1; i >= 0; i--) {
          if ([windows[(NSUInteger)i][@"id"] isEqualToString:self->_windowSessionID])
              [windows removeObjectAtIndex:(NSUInteger)i];
      }
    }];
}

- (BOOL)canOpenDocumentAtPath:(NSString*)path showError:(BOOL)showError {
    if (path.length == 0) return NO;
    BOOL isDirectory = NO;
    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory];
    if (!fileExists || isDirectory) {
        if (showError) [self showError:@"File moved or deleted" detail:path];
        return NO;
    }
    return YES;
}

- (NSArray<NSString*>*)openableDocumentPathsFromPaths:(NSArray<NSString*>*)paths showErrors:(BOOL)showErrors {
    NSMutableArray<NSString*>* openable = [NSMutableArray array];
    for (NSString* path in paths) {
        if (![path isKindOfClass:NSString.class] || path.length == 0) continue;
        if ([self canOpenDocumentAtPath:path showError:showErrors]) [openable addObject:path];
    }
    return openable;
}

- (NSArray<NSRunningApplication*>*)otherRunningShenzhenApplications {
    NSString* bundleID = NSBundle.mainBundle.bundleIdentifier;
    pid_t currentPID = NSProcessInfo.processInfo.processIdentifier;
    NSMutableArray<NSRunningApplication*>* apps = [NSMutableArray array];
    for (NSRunningApplication* app in [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID]) {
        if (app.processIdentifier != currentPID) [apps addObject:app];
    }
    return apps;
}

- (BOOL)hasOtherShenzhenWindows {
    for (ShenzhenMacDelegate* controller in gSPDFWindowControllers ?: @[]) {
        if (controller != self && controller->_window && controller->_window.visible) return YES;
    }
    return [self otherRunningShenzhenApplications].count > 0;
}

- (void)activateWindowForExternalOpen {
    if (!_window) return;
    [NSApp activateIgnoringOtherApps:YES];
    [_window orderFrontRegardless];
    [_window makeKeyAndOrderFront:nil];
    [_window makeMainWindow];
}

- (void)dismissTabHoverPanel {
    [_tabStrip dismissHoverPanel];
}

- (void)spawnPendingRestoredWindowsIfNeeded {
    if (self.detachedTabLaunch || self.restoreWindowID.length > 0 || _pendingRestoreWindowIDs.count == 0) return;

    NSString* executable = NSBundle.mainBundle.executablePath ?: NSProcessInfo.processInfo.arguments.firstObject;
    if (executable.length == 0) return;
    NSArray<NSString*>* ids = [_pendingRestoreWindowIDs copy];
    [_pendingRestoreWindowIDs removeAllObjects];
    for (NSString* windowID in ids) {
        if (windowID.length == 0 || [windowID isEqualToString:_windowSessionID]) continue;
        NSTask* task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:executable];
        task.arguments = @[ @"--restore-window", windowID ];
        task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
        task.standardError = [NSFileHandle fileHandleWithNullDevice];
        [task launchAndReturnError:nil];
    }
}

- (void)performWithBatchedPersistentStateSaves:(void (^)(void))block {
    if (!block) return;
    BOOL wasSuspended = _suspendPersistentStateSaves;
    _suspendPersistentStateSaves = YES;
    block();
    _suspendPersistentStateSaves = wasSuspended;
    if (!wasSuspended && _needsDeferredPersistentStateSave) {
        _needsDeferredPersistentStateSave = NO;
        [self savePersistentState];
    }
}

- (void)savePersistentState {
    if (_suspendPersistentStateSaves) {
        _needsDeferredPersistentStateSave = YES;
        return;
    }

    NSSize windowContentSize = _restoredWindowContentSize;
    if (_window && !_window.miniaturized && !_presentationMode && !(_window.styleMask & NSWindowStyleMaskFullScreen)) {
        windowContentSize = [_window contentRectForFrameRect:_window.frame].size;
        _restoredWindowContentSize = windowContentSize;
    }
    windowContentSize = spdf_sane_window_content_size(windowContentSize, _window.screen ?: NSScreen.mainScreen);

    if (!_suppressSessionWriteOnTerminate) [self writeSessionStateForCurrentWindow];
    CGFloat sidebarWidth = spdf_sane_sidebar_width(_sidebarWidth, _splitView ? NSWidth(_splitView.bounds) : 0);
    [self writeJSONObject:@{
        @"version" : @1,
        @"fitMode" : @(_fitMode),
        @"viewMode" : @(_viewMode),
        @"sidebarWidth" : @(sidebarWidth),
        @"minimapWidth" : @(_minimapWidth),
        @"windowSize" : @{@"width" : @(windowContentSize.width), @"height" : @(windowContentSize.height)},
        @"commentAuthor" : _commentAuthor ?: @"",
        @"translateSourceLanguage" : _translationSourceLanguage ?: @"zh",
        @"translateTargetLanguage" : _translationTargetLanguage ?: @"en",
        @"showShortcutHelpOnLaunch" : @(_showShortcutHelpOnLaunch),
        @"recentlyOpened" : _recentlyOpenedPaths ?: @[]
    }
                   toFile:@"settings.json"];
    [self writeJSONObject:_favorites toFile:@"favorites.json"];
    [self writeJSONObject:_documentStates ?: @{} toFile:@"documents.json"];
}

- (void)rebuildRecentlyOpenedMenu {
    if (!_recentlyOpenedMenu) return;
    [_recentlyOpenedMenu removeAllItems];
    if (_recentlyOpenedPaths.count == 0) {
        NSMenuItem* empty = [[NSMenuItem alloc] initWithTitle:@"No Recent Documents" action:nil keyEquivalent:@""];
        empty.enabled = NO;
        [_recentlyOpenedMenu addItem:empty];
        return;
    }
    NSUInteger count = MIN((NSUInteger)kRecentDocumentLimit, _recentlyOpenedPaths.count);
    for (NSUInteger i = 0; i < count; i++) {
        NSString* path = _recentlyOpenedPaths[i];
        NSString* title =
            [NSString stringWithFormat:@"%lu) %@", (unsigned long)(i + 1), spdf_display_name_for_path(path)];
        NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(openRecentDocument:)
                                               keyEquivalent:@""];
        item.representedObject = path;
        item.toolTip = path;
        [_recentlyOpenedMenu addItem:item];
    }
}

- (void)rememberRecentlyOpenedPath:(NSString*)path {
    if (path.length == 0) return;
    NSString* standardized = path.stringByStandardizingPath;
    for (NSInteger i = (NSInteger)_recentlyOpenedPaths.count - 1; i >= 0; --i) {
        NSString* existingPath = _recentlyOpenedPaths[(NSUInteger)i];
        if ([existingPath.stringByStandardizingPath isEqualToString:standardized])
            [_recentlyOpenedPaths removeObjectAtIndex:(NSUInteger)i];
    }
    [_recentlyOpenedPaths insertObject:[path copy] atIndex:0];
    while (_recentlyOpenedPaths.count > kRecentDocumentLimit) [_recentlyOpenedPaths removeLastObject];
    [self rebuildRecentlyOpenedMenu];
}

- (void)rememberClosedDocumentPath:(NSString*)path {
    if (path.length == 0) return;
    [_closedDocumentPaths addObject:[path copy]];
    while (_closedDocumentPaths.count > kRecentDocumentLimit) [_closedDocumentPaths removeObjectAtIndex:0];
}

- (void)buildMenu {
    NSMenu* mainMenu = [[NSMenu alloc] initWithTitle:@""];

    NSMenuItem* appItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    [mainMenu addItem:appItem];
    NSMenu* appMenu = [[NSMenu alloc] initWithTitle:@"Shenzhen PDF"];
    [appMenu addItemWithTitle:@"About Shenzhen PDF" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit Shenzhen PDF" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;

    NSMenuItem* fileItem = [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
    [mainMenu addItem:fileItem];
    NSMenu* fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"Open..." action:@selector(openDocument:) keyEquivalent:@"o"];
    NSMenuItem* reopenClosed = [fileMenu addItemWithTitle:@"Reopen Last Closed"
                                                   action:@selector(reopenLastClosedDocument:)
                                            keyEquivalent:@"t"];
    reopenClosed.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    NSMenuItem* recentItem = [[NSMenuItem alloc] initWithTitle:@"Recently Opened" action:nil keyEquivalent:@""];
    _recentlyOpenedMenu = [[NSMenu alloc] initWithTitle:@"Recently Opened"];
    recentItem.submenu = _recentlyOpenedMenu;
    [fileMenu addItem:recentItem];
    [self rebuildRecentlyOpenedMenu];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Open in Adobe Acrobat Reader"
                        action:@selector(openInExternalReader:)
                 keyEquivalent:@""];
    [fileMenu addItemWithTitle:@"Show in Folder" action:@selector(showInFolder:) keyEquivalent:@""];
    [fileMenu addItemWithTitle:@"Close" action:@selector(closeDocument:) keyEquivalent:@"w"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Print..." action:@selector(printDocument:) keyEquivalent:@"p"];
    [fileMenu addItemWithTitle:@"OCR Document..." action:@selector(ocrDocument:) keyEquivalent:@""];
    [fileMenu addItemWithTitle:@"Translate..." action:@selector(translateDocument:) keyEquivalent:@""];
    [fileMenu addItemWithTitle:@"Properties..." action:@selector(showProperties:) keyEquivalent:@""];
    fileItem.submenu = fileMenu;

    NSMenuItem* goItem = [[NSMenuItem alloc] initWithTitle:@"Go To" action:nil keyEquivalent:@""];
    [mainMenu addItem:goItem];
    NSMenu* goMenu = [[NSMenu alloc] initWithTitle:@"Go To"];
    NSMenuItem* firstPageItem =
        [goMenu addItemWithTitle:@"First Page"
                          action:@selector(firstPage:)
                   keyEquivalent:[NSString stringWithFormat:@"%C", static_cast<unichar>(NSHomeFunctionKey)]];
    NSMenuItem* previousPageItem = [goMenu addItemWithTitle:@"Previous Page"
                                                     action:@selector(previousPage:)
                                              keyEquivalent:@"["];
    NSMenuItem* nextPageItem = [goMenu addItemWithTitle:@"Next Page" action:@selector(nextPage:) keyEquivalent:@"]"];
    NSMenuItem* lastPageItem =
        [goMenu addItemWithTitle:@"Last Page"
                          action:@selector(lastPage:)
                   keyEquivalent:[NSString stringWithFormat:@"%C", static_cast<unichar>(NSEndFunctionKey)]];
    for (NSMenuItem* item in @[ firstPageItem, previousPageItem, nextPageItem, lastPageItem ]) item.target = self;
    [goMenu addItem:[NSMenuItem separatorItem]];
    [goMenu addItemWithTitle:@"Go To Page..." action:@selector(focusPageField:) keyEquivalent:@"l"];
    goItem.submenu = goMenu;

    NSMenuItem* zoomItem = [[NSMenuItem alloc] initWithTitle:@"Zoom" action:nil keyEquivalent:@""];
    [mainMenu addItem:zoomItem];
    NSMenu* zoomMenu = [[NSMenu alloc] initWithTitle:@"Zoom"];
    NSMenuItem* zoomIn = [zoomMenu addItemWithTitle:@"Zoom In" action:@selector(zoomIn:) keyEquivalent:@"+"];
    NSMenuItem* zoomOut = [zoomMenu addItemWithTitle:@"Zoom Out" action:@selector(zoomOut:) keyEquivalent:@"-"];
    NSMenuItem* actualSize = [zoomMenu addItemWithTitle:@"100%" action:@selector(actualSize:) keyEquivalent:@"0"];
    [zoomMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* zoomFitPage = [zoomMenu addItemWithTitle:@"Fit Page" action:@selector(fitPage:) keyEquivalent:@"9"];
    NSMenuItem* zoomFitWidth = [zoomMenu addItemWithTitle:@"Fit Width" action:@selector(fitWidth:) keyEquivalent:@"1"];
    NSMenuItem* zoomFitHeight = [zoomMenu addItemWithTitle:@"Fit Height"
                                                    action:@selector(fitHeight:)
                                             keyEquivalent:@"2"];
    for (NSMenuItem* item in @[ zoomIn, zoomOut, actualSize, zoomFitPage, zoomFitWidth, zoomFitHeight ])
        item.target = self;
    zoomItem.submenu = zoomMenu;

    NSMenuItem* viewItem = [[NSMenuItem alloc] initWithTitle:@"View" action:nil keyEquivalent:@""];
    [mainMenu addItem:viewItem];
    NSMenu* viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    [viewMenu addItemWithTitle:@"Single Page" action:@selector(setSinglePageMode:) keyEquivalent:@"4"];
    [viewMenu addItemWithTitle:@"Continuous" action:@selector(setContinuousMode:) keyEquivalent:@"5"];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* viewFitWidth = [viewMenu addItemWithTitle:@"Fit Width" action:@selector(fitWidth:) keyEquivalent:@""];
    NSMenuItem* viewFitHeight = [viewMenu addItemWithTitle:@"Fit Height"
                                                    action:@selector(fitHeight:)
                                             keyEquivalent:@""];
    NSMenuItem* viewFitPage = [viewMenu addItemWithTitle:@"Fit Page" action:@selector(fitPage:) keyEquivalent:@""];
    for (NSMenuItem* item in @[ viewFitWidth, viewFitHeight, viewFitPage ]) item.target = self;
    [viewMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* sidePanelItem = [viewMenu addItemWithTitle:@"Show Side Panel"
                                                    action:@selector(toggleSidebar:)
                                             keyEquivalent:@""];
    sidePanelItem.target = self;
    NSMenuItem* minimapItem = [viewMenu addItemWithTitle:@"Show Minimap"
                                                  action:@selector(toggleMinimap:)
                                           keyEquivalent:@""];
    minimapItem.target = self;
    [viewMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* viewMoveResizeItem = [[NSMenuItem alloc] initWithTitle:@"Move & Resize Window"
                                                                action:nil
                                                         keyEquivalent:@""];
    NSMenu* viewMoveResizeMenu = [[NSMenu alloc] initWithTitle:@"Move & Resize Window"];
    NSArray<NSDictionary*>* viewMoveResizeActions = @[
        @{@"title" : @"Fill", @"action" : NSStringFromSelector(@selector(fillWindow:))},
        @{@"title" : @"Center", @"action" : NSStringFromSelector(@selector(centerWindowInScreen:))},
        @{@"title" : @"Left Half", @"action" : NSStringFromSelector(@selector(moveWindowToLeftHalf:))},
        @{@"title" : @"Right Half", @"action" : NSStringFromSelector(@selector(moveWindowToRightHalf:))},
        @{@"title" : @"Top Half", @"action" : NSStringFromSelector(@selector(moveWindowToTopHalf:))},
        @{@"title" : @"Bottom Half", @"action" : NSStringFromSelector(@selector(moveWindowToBottomHalf:))}
    ];
    for (NSDictionary* itemInfo in viewMoveResizeActions) {
        NSMenuItem* item = [viewMoveResizeMenu addItemWithTitle:itemInfo[@"title"]
                                                         action:NSSelectorFromString(itemInfo[@"action"])
                                                  keyEquivalent:@""];
        item.target = self;
    }
    viewMoveResizeItem.submenu = viewMoveResizeMenu;
    [viewMenu addItem:viewMoveResizeItem];
    NSMenuItem* presentation =
        [viewMenu addItemWithTitle:@"Presentation Mode"
                            action:@selector(togglePresentation:)
                     keyEquivalent:[NSString stringWithFormat:@"%C", static_cast<unichar>(NSF5FunctionKey)]];
    presentation.target = self;
    presentation.keyEquivalentModifierMask = 0;
    NSMenuItem* presentationAlternate = [viewMenu addItemWithTitle:@"Presentation Mode"
                                                            action:@selector(togglePresentation:)
                                                     keyEquivalent:@"f"];
    presentationAlternate.target = self;
    presentationAlternate.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    NSMenuItem* fullScreen = [viewMenu addItemWithTitle:@"Full Screen"
                                                 action:@selector(toggleFullScreen:)
                                          keyEquivalent:@"f"];
    fullScreen.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;
    [viewMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* rotateClockwise = [viewMenu addItemWithTitle:@"Rotate Clockwise"
                                                      action:@selector(rotateClockwise:)
                                               keyEquivalent:@"r"];
    rotateClockwise.target = self;
    rotateClockwise.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    NSMenuItem* rotateAnticlockwise = [viewMenu addItemWithTitle:@"Rotate Anticlockwise"
                                                          action:@selector(rotateAnticlockwise:)
                                                   keyEquivalent:@"r"];
    rotateAnticlockwise.target = self;
    rotateAnticlockwise.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    viewItem.submenu = viewMenu;

    NSMenuItem* windowItem = [[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""];
    [mainMenu addItem:windowItem];
    NSMenu* windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    NSMenuItem* minimizeItem = [windowMenu addItemWithTitle:@"Minimize"
                                                     action:@selector(performMiniaturize:)
                                              keyEquivalent:@"m"];
    minimizeItem.target = _window;
    NSMenuItem* zoomItemWindow = [windowMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    zoomItemWindow.target = _window;
    [windowMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* bringAllToFront = [windowMenu addItemWithTitle:@"Bring All to Front"
                                                        action:@selector(arrangeInFront:)
                                                 keyEquivalent:@""];
    bringAllToFront.target = NSApp;
    windowItem.submenu = windowMenu;
    [NSApp setWindowsMenu:windowMenu];

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
    NSMenuItem* prevFind = [editMenu addItemWithTitle:@"Find Previous"
                                               action:@selector(findPrevious:)
                                        keyEquivalent:@"G"];
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
    NSArray<NSString*>* stateFiles = @[ @"settings.json", @"session.json", @"documents.json", @"favorites.json" ];
    for (NSString* stateFile in stateFiles) {
        NSMenuItem* stateItem =
            [settingsMenu addItemWithTitle:[NSString stringWithFormat:@"Open %@...", stateFile]
                                    action:@selector(openStateJSONFile:)
                             keyEquivalent:[stateFile isEqualToString:@"settings.json"] ? @"," : @""];
        stateItem.target = self;
        stateItem.representedObject = stateFile;
    }
    [settingsMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* revealSettings = [settingsMenu addItemWithTitle:@"Reveal Settings Folder"
                                                         action:@selector(revealSettingsFolder:)
                                                  keyEquivalent:@""];
    revealSettings.target = self;
    settingsItem.submenu = settingsMenu;

    NSMenuItem* helpItem = [[NSMenuItem alloc] initWithTitle:@"Help" action:nil keyEquivalent:@""];
    [mainMenu addItem:helpItem];
    NSMenu* helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
    NSMenuItem* shortcuts =
        [helpMenu addItemWithTitle:@"Keyboard Shortcuts"
                            action:@selector(showShortcutHelp:)
                     keyEquivalent:[NSString stringWithFormat:@"%C", static_cast<unichar>(NSF1FunctionKey)]];
    shortcuts.target = self;
    shortcuts.keyEquivalentModifierMask = 0;
    helpItem.submenu = helpMenu;

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
    if ([hiddenViews containsObject:_translateButton])
        [self addOverflowItemWithTitle:@"Translate..."
                                action:@selector(translateDocument:)
                                  menu:menu
                                 state:NSControlStateValueOff
                               enabled:hasDoc && !_translationRunning && !_translationInstallRunning];
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
        @[ _ocrButton, _translateButton, _ocrSeparator ],
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
    NSRect frame = _hasRestoredWindowFrame ? spdf_sane_window_frame(_restoredWindowFrame, screen)
                                           : NSMakeRect(floor(NSMidX(visibleFrame) - contentSize.width / 2.0),
                                                        floor(NSMidY(visibleFrame) - contentSize.height / 2.0),
                                                        contentSize.width, contentSize.height);
    _window = [[SPDFWindow alloc] initWithContentRect:frame
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                      NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
    ((SPDFWindow*)_window).reader = self;
    _window.delegate = self;
    _window.title = @"Shenzhen PDF";
    _window.minSize = NSMakeSize(kMinWindowWidth, kMinWindowHeight);
    _window.titleVisibility = NSWindowTitleHidden;
    _window.titlebarAppearsTransparent = YES;
    _window.styleMask |= NSWindowStyleMaskFullSizeContentView;
    _window.movable = YES;
    _window.movableByWindowBackground = NO;

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
    _sidebarToggleButton = [[SPDFToolbarToggleButton alloc] initWithTitle:@"Side Panel"
                                                                   target:self
                                                                   action:@selector(toggleSidebar:)];
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
    NSArray<NSDictionary*>* fitItems = @[
        @{@"title" : @"100%", @"mode" : @(SPDFFitModeActual)},
        @{@"title" : @"Fit Width", @"mode" : @(SPDFFitModeWidth)},
        @{@"title" : @"Fit Height", @"mode" : @(SPDFFitModeHeight)},
        @{@"title" : @"Fit Page", @"mode" : @(SPDFFitModePage)}
    ];
    for (NSDictionary* item in fitItems) {
        [_fitModePopup addItemWithTitle:item[@"title"]];
        _fitModePopup.lastItem.tag = [item[@"mode"] integerValue];
    }
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
    _ocrButton = [self buttonWithTitle:@"" action:@selector(ocrDocument:)];
    _ocrButton.image = spdf_ocr_toolbar_image();
    _ocrButton.imagePosition = NSImageOnly;
    _ocrButton.toolTip = @"Run OCR on this PDF";
    _ocrButton.accessibilityLabel = @"Run OCR";
    [_ocrButton.widthAnchor constraintEqualToConstant:32].active = YES;
    [_ocrButton setContentHuggingPriority:NSLayoutPriorityRequired
                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_ocrButton setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                         forOrientation:NSLayoutConstraintOrientationHorizontal];
    _translateButton = [self buttonWithTitle:@"" action:@selector(translateDocument:)];
    _translateButton.image = spdf_translate_toolbar_image();
    _translateButton.imagePosition = NSImageOnly;
    _translateButton.toolTip = @"Translate selected text or the document";
    _translateButton.accessibilityLabel = @"Translate Document";
    [_translateButton.widthAnchor constraintEqualToConstant:32].active = YES;
    [_translateButton setContentHuggingPriority:NSLayoutPriorityRequired
                                 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_translateButton setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                               forOrientation:NSLayoutConstraintOrientationHorizontal];
    _findPrevButton = [self buttonWithTitle:@"<" action:@selector(findPrevious:)];
    _findNextButton = [self buttonWithTitle:@">" action:@selector(findNext:)];
    _minimapToggleButton = [[SPDFToolbarToggleButton alloc] initWithTitle:@"Map"
                                                                   target:self
                                                                   action:@selector(toggleMinimap:)];
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
    [_toolbar addArrangedSubview:_translateButton];
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

    _sidebarFilterField = [[NSSearchField alloc] init];
    _sidebarFilterField.placeholderString = @"Filter Chapters";
    _sidebarFilterField.delegate = self;
    _sidebarFilterField.translatesAutoresizingMaskIntoConstraints = NO;
    [_sidebarContainer addSubview:_sidebarFilterField];

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
    NSMenuItem* sidebarEditComment = [sidebarMenu addItemWithTitle:@"Edit Comment..."
                                                            action:@selector(editComment:)
                                                     keyEquivalent:@""];
    sidebarEditComment.target = self;
    NSMenuItem* sidebarDeleteComment = [sidebarMenu addItemWithTitle:@"Delete Comment..."
                                                              action:@selector(deleteComment:)
                                                       keyEquivalent:@""];
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
        [_sidebarFilterField.topAnchor constraintEqualToAnchor:_sidebarModeControl.bottomAnchor constant:8],
        [_sidebarFilterField.leadingAnchor constraintEqualToAnchor:_sidebarContainer.leadingAnchor constant:8],
        [_sidebarFilterField.trailingAnchor constraintEqualToAnchor:_sidebarContainer.trailingAnchor constant:-8],
        [sidebarScroll.topAnchor constraintEqualToAnchor:_sidebarFilterField.bottomAnchor constant:8],
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

    return [self zoomForFitMode:fitMode
                       pageSize:NSMakeSize(pageWidth, pageHeight)
                       clipSize:[self documentClipSizeForLayout]
                   fallbackZoom:_zoom];
}

- (CGFloat)zoomForFitMode:(SPDFFitMode)fitMode
                 pageSize:(NSSize)pageSize
                 clipSize:(NSSize)clipSize
             fallbackZoom:(CGFloat)fallbackZoom {
    fallbackZoom = fallbackZoom > 0 ? fallbackZoom : 1.0;
    if (fitMode == SPDFFitModeCustom) return MAX(kMinZoom, MIN(kMaxZoom, fallbackZoom));
    if (fitMode == SPDFFitModeActual) return 1.0;
    if (pageSize.width <= 0.0 || pageSize.height <= 0.0 || clipSize.width <= 0.0 || clipSize.height <= 0.0)
        return MAX(kMinZoom, MIN(kMaxZoom, fallbackZoom));

    CGFloat widthZoom = clipSize.width / pageSize.width;
    CGFloat heightZoom = clipSize.height / pageSize.height;
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

    displayScale = displayScale > 0 ? displayScale : 1.0;
    CGFloat requestedDisplayScale = displayScale;
    CGFloat renderDisplayScale = [self renderDisplayScaleForPageWidth:pageWidth
                                                           pageHeight:pageHeight
                                                                 zoom:zoom
                                                         displayScale:requestedDisplayScale];
    if (renderDisplayScale <= 0.0) {
        if (err && errLen > 0) snprintf(err, errLen, "%s", "Rendered page would be too large.");
        return nil;
    }

    spdf_bitmap bitmap;
    if (!spdf_render_page_rgba(doc, (int)pageIndex, (float)(zoom * renderDisplayScale), &bitmap, err, errLen))
        return nil;

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
    if (!rep || !rep.bitmapData) {
        spdf_free_bitmap(&bitmap);
        if (err && errLen > 0) snprintf(err, errLen, "%s", "Could not allocate page bitmap.");
        return nil;
    }
    memcpy(rep.bitmapData, bitmap.rgba, (size_t)bitmap.stride * (size_t)bitmap.height);

    NSSize pointSize = NSMakeSize((CGFloat)pageWidth * zoom, (CGFloat)pageHeight * zoom);
    if (!isfinite(pointSize.width) || !isfinite(pointSize.height) || pointSize.width <= 0.0 || pointSize.height <= 0.0)
        pointSize = NSMakeSize((CGFloat)bitmap.width / MAX(0.01, renderDisplayScale),
                               (CGFloat)bitmap.height / MAX(0.01, renderDisplayScale));
    rep.size = pointSize;
    NSImage* image = [[NSImage alloc] initWithSize:pointSize];
    if (!image) {
        spdf_free_bitmap(&bitmap);
        if (err && errLen > 0) snprintf(err, errLen, "%s", "Could not allocate page image.");
        return nil;
    }
    [image addRepresentation:rep];
    spdf_free_bitmap(&bitmap);

    SPDFRenderedPage* page = [[SPDFRenderedPage alloc] init];
    page.pageIndex = pageIndex;
    page.pageWidth = pageWidth;
    page.pageHeight = pageHeight;
    page.imagePointWidth = pointSize.width;
    page.imagePointHeight = pointSize.height;
    page.imageZoom = zoom;
    page.imageScale = requestedDisplayScale;
    page.image = image;
    page.highlights = @[];
    page.selectionRects = @[];
    return page;
}

- (NSImage*)renderedPageCropImageAtIndex:(NSInteger)pageIndex
                                document:(spdf_document*)doc
                                    zoom:(CGFloat)zoom
                            displayScale:(CGFloat)displayScale
                            pageCropRect:(NSRect)pageCropRect
                                   error:(char*)err
                             errorLength:(size_t)errLen {
    if (NSIsEmptyRect(pageCropRect)) return nil;
    spdf_rect crop;
    crop.x0 = (float)NSMinX(pageCropRect);
    crop.y0 = (float)NSMinY(pageCropRect);
    crop.x1 = (float)NSMaxX(pageCropRect);
    crop.y1 = (float)NSMaxY(pageCropRect);

    spdf_bitmap bitmap;
    if (!spdf_render_page_region_rgba(doc, (int)pageIndex, (float)(zoom * displayScale), crop, &bitmap, err, errLen))
        return nil;

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
    if (!rep || !rep.bitmapData) {
        spdf_free_bitmap(&bitmap);
        if (err && errLen > 0) snprintf(err, errLen, "%s", "Could not allocate page crop bitmap.");
        return nil;
    }
    memcpy(rep.bitmapData, bitmap.rgba, (size_t)bitmap.stride * (size_t)bitmap.height);
    spdf_free_bitmap(&bitmap);

    NSSize pointSize = NSMakeSize(NSWidth(pageCropRect) * zoom, NSHeight(pageCropRect) * zoom);
    rep.size = pointSize;
    NSImage* image = [[NSImage alloc] initWithSize:pointSize];
    if (!image) {
        if (err && errLen > 0) snprintf(err, errLen, "%s", "Could not allocate page crop image.");
        return nil;
    }
    [image addRepresentation:rep];
    return image;
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
    SPDFWorkerDocument* holder = threadDictionary[@"ShenzhenPDFWorkerDocument"];
    if (holder && [holder.path isEqualToString:path] && holder.document) return holder.document;

    holder = [[SPDFWorkerDocument alloc] init];
    holder.path = path;
    holder.document = spdf_open(path.fileSystemRepresentation, err, errLen);
    if (!holder.document) return NULL;
    threadDictionary[@"ShenzhenPDFWorkerDocument"] = holder;
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

- (BOOL)renderedPageImage:(SPDFRenderedPage*)page matchesZoom:(CGFloat)zoom displayScale:(CGFloat)displayScale {
    if (!page.image) return NO;
    return fabs(page.imageZoom - zoom) <= 0.001 && fabs(page.imageScale - displayScale) <= 0.001;
}

- (BOOL)minimapThumbnailImage:(SPDFRenderedPage*)page matchesZoom:(CGFloat)zoom displayScale:(CGFloat)displayScale {
    if (!page.minimapImage) return NO;
    return fabs(page.minimapImageZoom - zoom) <= 0.01 && fabs(page.minimapImageScale - displayScale) <= 0.01;
}

- (void)copyMinimapThumbnailFromPage:(SPDFRenderedPage*)source toPage:(SPDFRenderedPage*)destination {
    if (!source || !destination) return;
    destination.minimapImage = source.minimapImage;
    destination.minimapImageZoom = source.minimapImageZoom;
    destination.minimapImageScale = source.minimapImageScale;
}

- (CGFloat)minimapThumbnailZoom {
    if (!_minimapView || _renderedPages.count == 0) return 0.0;
    CGFloat widest = 0.0;
    for (SPDFRenderedPage* page in _renderedPages) widest = MAX(widest, page.pageWidth);
    if (widest <= 0.0) return 0.0;
    CGFloat width = NSWidth(_minimapView.bounds);
    if (width <= 16.0) width = _minimapWidth;
    return MAX(0.01, MIN(0.5, (MAX(16.0, width) - 18.0) / widest));
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

- (void)enqueuePageRendersForGeneration:(NSUInteger)generation
                            pageIndexes:(NSArray<NSNumber*>*)pageIndexes
                          preferredPage:(NSInteger)preferredPage
                      forceHighPriority:(BOOL)forceHighPriority {
    if (!_doc || !_path.length) return;

    NSString* path = [_path copy];
    CGFloat zoom = _zoom;
    CGFloat displayScale = [self backingScale];
    for (NSNumber* number in pageIndexes) {
        NSInteger index = number.integerValue;
        if (index < 0 || index >= (NSInteger)_renderedPages.count) continue;
        SPDFRenderedPage* existing = _renderedPages[(NSUInteger)index];
        if ([self renderedPageImage:existing matchesZoom:zoom displayScale:displayScale]) continue;
        if (![self fullPageRenderAllowedForPage:existing zoom:zoom displayScale:displayScale]) continue;
        NSOperation* queuedOperation = _queuedRenderOperations[number];
        if (queuedOperation) {
            if (forceHighPriority) {
                queuedOperation.queuePriority = NSOperationQueuePriorityVeryHigh;
                queuedOperation.qualityOfService = NSQualityOfServiceUserInitiated;
            }
            continue;
        }
        [_queuedRenderPages addObject:number];

        NSInteger distance = labs(index - preferredPage);
        NSBlockOperation* operation = [NSBlockOperation blockOperationWithBlock:^{
          @autoreleasepool {
              if (generation != self->_renderGeneration) {
                  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [self->_queuedRenderPages removeObject:number];
                    [self->_queuedRenderOperations removeObjectForKey:number];
                  }];
                  return;
              }
              char err[1024];
              spdf_document* workerDoc = [self workerDocumentForPath:path error:err errorLength:sizeof(err)];
              if (!workerDoc) {
                  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [self->_queuedRenderPages removeObject:number];
                    [self->_queuedRenderOperations removeObjectForKey:number];
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
                    [self->_queuedRenderOperations removeObjectForKey:number];
                  }];
                  return;
              }

              [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [self->_queuedRenderPages removeObject:number];
                [self->_queuedRenderOperations removeObjectForKey:number];
                if (generation != self->_renderGeneration || !self->_doc ||
                    index >= (NSInteger)self->_renderedPages.count)
                    return;
                SPDFRenderedPage* old = self->_renderedPages[(NSUInteger)index];
                page.highlights = self->_findHighlights[@(index)] ?: old.highlights ?: @[];
                page.selectionRects = old.selectionRects ?: @[];
                [self copyMinimapThumbnailFromPage:old toPage:page];
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
                [self cacheActiveRenderedPagesForSelectedTab];
                [self evictDistantRenderedPageImages];
              }];
          }
        }];
        operation.queuePriority =
            forceHighPriority ? NSOperationQueuePriorityVeryHigh : [self queuePriorityForRenderDistance:distance];
        operation.qualityOfService = forceHighPriority ? NSQualityOfServiceUserInitiated : NSQualityOfServiceUtility;
        _queuedRenderOperations[number] = operation;
        [_renderQueue addOperation:operation];
    }
}

- (void)enqueueNearbyPageRendersForGeneration:(NSUInteger)generation preferredPage:(NSInteger)preferredPage {
    NSArray<NSNumber*>* order = [self pageRenderOrderForCount:(NSInteger)_renderedPages.count
                                                preferredPage:preferredPage
                                                     maxPages:[self backgroundRenderBatchSizeForCurrentZoom]];
    [self enqueuePageRendersForGeneration:generation
                              pageIndexes:order
                            preferredPage:preferredPage
                        forceHighPriority:NO];
}

- (void)enqueueVisibleMinimapThumbnailRenders {
    if (!_minimapVisible || !_doc || !_path.length || _renderedPages.count == 0 || _liveZooming) return;
    NSArray<NSNumber*>* visiblePages = [_minimapView visiblePageIndexes];
    if (visiblePages.count == 0) return;

    NSString* path = [_path copy];
    NSUInteger generation = _renderGeneration;
    CGFloat thumbnailZoom = [self minimapThumbnailZoom];
    CGFloat displayScale = [self backingScale];
    if (thumbnailZoom <= 0.0 || displayScale <= 0.0) return;

    for (NSNumber* number in visiblePages) {
        NSInteger index = number.integerValue;
        if (index < 0 || index >= (NSInteger)_renderedPages.count) continue;
        SPDFRenderedPage* existing = _renderedPages[(NSUInteger)index];
        if ([self minimapThumbnailImage:existing matchesZoom:thumbnailZoom displayScale:displayScale]) continue;
        if ([_queuedMinimapThumbnailPages containsObject:number]) continue;
        [_queuedMinimapThumbnailPages addObject:number];

        NSBlockOperation* operation = [NSBlockOperation blockOperationWithBlock:^{
          @autoreleasepool {
              if (generation != self->_renderGeneration) {
                  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [self->_queuedMinimapThumbnailPages removeObject:number];
                  }];
                  return;
              }
              char err[512];
              spdf_document* workerDoc = [self workerDocumentForPath:path error:err errorLength:sizeof(err)];
              if (!workerDoc) {
                  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [self->_queuedMinimapThumbnailPages removeObject:number];
                  }];
                  return;
              }
              SPDFRenderedPage* thumbnailPage = [self renderedPageAtIndex:index
                                                                 document:workerDoc
                                                                     zoom:thumbnailZoom
                                                             displayScale:displayScale
                                                                    error:err
                                                              errorLength:sizeof(err)];
              [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [self->_queuedMinimapThumbnailPages removeObject:number];
                if (generation != self->_renderGeneration || !self->_doc || ![self->_path isEqualToString:path] ||
                    index >= (NSInteger)self->_renderedPages.count || !thumbnailPage.image)
                    return;
                SPDFRenderedPage* page = self->_renderedPages[(NSUInteger)index];
                if ([self minimapThumbnailImage:page matchesZoom:thumbnailZoom displayScale:displayScale]) return;
                page.minimapImage = thumbnailPage.image;
                page.minimapImageZoom = thumbnailZoom;
                page.minimapImageScale = displayScale;
                [self->_minimapView setNeedsDisplay:YES];
              }];
          }
        }];
        operation.queuePriority = NSOperationQueuePriorityNormal;
        operation.qualityOfService = NSQualityOfServiceUtility;
        [_minimapQueue addOperation:operation];
    }
}

- (NSArray<NSNumber*>*)visibleDocumentPageIndexesWithExtraRadius:(NSInteger)radius
                                                   preferredPage:(NSInteger*)preferredPageOut {
    NSInteger preferredPage = -1;
    if (!_pageScrollView || !_pageView || _renderedPages.count == 0) {
        if (preferredPageOut) *preferredPageOut = preferredPage;
        return @[];
    }

    NSRect visibleRect = _pageScrollView.contentView.bounds;
    preferredPage = [_pageView pageIndexForVisibleRect:visibleRect];
    preferredPage = MAX(0, MIN(preferredPage, (NSInteger)_renderedPages.count - 1));

    NSMutableOrderedSet<NSNumber*>* indexes = [NSMutableOrderedSet orderedSet];
    if (_viewMode == SPDFViewModeSingle) {
        [indexes addObject:@(preferredPage)];
    } else {
        for (NSInteger i = 0; i < (NSInteger)_renderedPages.count; ++i) {
            NSRect pageRect = [_pageView rectForPageAtIndex:i];
            if (!NSIsEmptyRect(NSIntersectionRect(visibleRect, pageRect))) [indexes addObject:@(i)];
        }
        if (indexes.count == 0) [indexes addObject:@(preferredPage)];
    }

    if (radius > 0) {
        NSArray<NSNumber*>* visible = indexes.array;
        for (NSNumber* number in visible) {
            NSInteger center = number.integerValue;
            NSInteger first = MAX(0, center - radius);
            NSInteger last = MIN((NSInteger)_renderedPages.count - 1, center + radius);
            for (NSInteger i = first; i <= last; ++i) [indexes addObject:@(i)];
        }
    }

    if (preferredPageOut) *preferredPageOut = preferredPage;
    return indexes.array;
}

- (void)queueVisibleDocumentPageRendersForCurrentViewportForceHighPriority:(BOOL)forceHighPriority {
    if (!_doc || !_path.length || _renderedPages.count == 0) return;
    NSInteger preferredPage = -1;
    NSArray<NSNumber*>* pageIndexes = [self visibleDocumentPageIndexesWithExtraRadius:1 preferredPage:&preferredPage];
    if (pageIndexes.count == 0) return;
    [self enqueuePageRendersForGeneration:_renderGeneration
                              pageIndexes:pageIndexes
                            preferredPage:preferredPage
                        forceHighPriority:forceHighPriority];
}

- (void)syncCurrentPageFromVisibleViewportQueueRenders:(BOOL)queueRenders forceHighPriority:(BOOL)forceHighPriority {
    if (!_pageScrollView || !_pageView || _renderedPages.count == 0) return;
    NSInteger visiblePage = [_pageView pageIndexForVisibleRect:_pageScrollView.contentView.bounds];
    visiblePage = MAX(0, MIN(visiblePage, (NSInteger)_renderedPages.count - 1));
    if (visiblePage != _pageIndex) {
        _pageIndex = visiblePage;
        _pageView.currentPageIndex = _pageIndex;
        [self clearPageFieldFocus];
        [self updateControls];
        [self selectCurrentSidebarRow];
    }
    if (queueRenders) [self queueVisibleDocumentPageRendersForCurrentViewportForceHighPriority:forceHighPriority];
}

- (void)renderPageIfNeededAtIndex:(NSInteger)pageIndex {
    if (!_doc || pageIndex < 0 || pageIndex >= (NSInteger)_renderedPages.count) return;
    SPDFRenderedPage* existing = _renderedPages[(NSUInteger)pageIndex];
    CGFloat displayScale = [self backingScale];
    if ([self renderedPageImage:existing matchesZoom:_zoom displayScale:displayScale]) return;
    if (![self fullPageRenderAllowedForPage:existing zoom:_zoom displayScale:displayScale]) {
        [self renderVisiblePageCropsForCurrentViewportIfNeeded];
        [_pageView setNeedsDisplayInRect:[_pageView rectForPageAtIndex:pageIndex]];
        [self updateMinimap];
        [self evictDistantRenderedPageImages];
        return;
    }

    char err[1024];
    SPDFRenderedPage* page = [self renderedPageAtIndex:pageIndex error:err errorLength:sizeof(err)];
    if (!page) {
        _statusLabel.stringValue = [NSString stringWithFormat:@"Could not render page %ld", (long)pageIndex + 1];
        return;
    }
    page.highlights = _findHighlights[@(pageIndex)] ?: existing.highlights ?: @[];
    page.selectionRects = existing.selectionRects ?: @[];
    [self copyMinimapThumbnailFromPage:existing toPage:page];
    [_renderedPages replaceObjectAtIndex:(NSUInteger)pageIndex withObject:page];
    _pageView.pages = _renderedPages;
    [self cacheActiveRenderedPagesForSelectedTab];
    [self updateMinimap];
    [self evictDistantRenderedPageImages];
}

- (CGFloat)renderDisplayScaleForPageWidth:(CGFloat)pageWidth
                               pageHeight:(CGFloat)pageHeight
                                     zoom:(CGFloat)zoom
                             displayScale:(CGFloat)displayScale {
    displayScale = displayScale > 0.0 ? displayScale : 1.0;
    if (pageWidth <= 0.0 || pageHeight <= 0.0 || zoom <= 0.0) return 0.0;

    double requestedEffectiveZoom = (double)zoom * (double)displayScale;
    double scaledWidth = ceil((double)pageWidth * requestedEffectiveZoom) + 2.0;
    double scaledHeight = ceil((double)pageHeight * requestedEffectiveZoom) + 2.0;
    double bytes = scaledWidth * scaledHeight * 4.0;
    if (!isfinite(scaledWidth) || !isfinite(scaledHeight) || !isfinite(bytes) ||
        scaledWidth > (double)kMaxRenderedPageBitmapDimension ||
        scaledHeight > (double)kMaxRenderedPageBitmapDimension || bytes > (double)kMaxRenderedPageBitmapByteLimit)
        return 0.0;
    return displayScale;
}

- (BOOL)fullPageRenderAllowedForPage:(SPDFRenderedPage*)page zoom:(CGFloat)zoom displayScale:(CGFloat)displayScale {
    if (!page) return NO;
    return [self renderDisplayScaleForPageWidth:page.pageWidth
                                     pageHeight:page.pageHeight
                                           zoom:zoom
                                   displayScale:displayScale] > 0.0;
}

- (BOOL)viewportImage:(SPDFRenderedPage*)page
    coversPageCropRect:(NSRect)cropRect
                  zoom:(CGFloat)zoom
          displayScale:(CGFloat)displayScale {
    if (!page.viewportImage) return NO;
    if (fabs(page.viewportImageZoom - zoom) > 0.001 || fabs(page.viewportImageScale - displayScale) > 0.001) return NO;
    return NSContainsRect(NSInsetRect(page.viewportImagePageRect, -1.0, -1.0), cropRect);
}

- (NSRect)visiblePageCropRectForPageIndex:(NSInteger)pageIndex extraViewMargin:(CGFloat)extraViewMargin {
    if (!_pageScrollView || !_pageView || pageIndex < 0 || pageIndex >= (NSInteger)_renderedPages.count)
        return NSZeroRect;
    SPDFRenderedPage* page = _renderedPages[(NSUInteger)pageIndex];
    NSRect pageRect = [_pageView rectForPageAtIndex:pageIndex];
    if (NSIsEmptyRect(pageRect)) return NSZeroRect;

    NSRect visibleRect = _pageScrollView.contentView.bounds;
    visibleRect = NSInsetRect(visibleRect, -MAX(0.0, extraViewMargin), -MAX(0.0, extraViewMargin));
    NSRect intersection = NSIntersectionRect(visibleRect, pageRect);
    if (NSIsEmptyRect(intersection)) return NSZeroRect;

    CGFloat scaleX = page.pageWidth / MAX(1.0, NSWidth(pageRect));
    CGFloat scaleY = page.pageHeight / MAX(1.0, NSHeight(pageRect));
    NSRect crop = NSMakeRect((NSMinX(intersection) - NSMinX(pageRect)) * scaleX,
                             (NSMinY(intersection) - NSMinY(pageRect)) * scaleY, NSWidth(intersection) * scaleX,
                             NSHeight(intersection) * scaleY);
    crop.origin.x = MAX(0.0, MIN(crop.origin.x, page.pageWidth));
    crop.origin.y = MAX(0.0, MIN(crop.origin.y, page.pageHeight));
    crop.size.width = MAX(0.0, MIN(NSWidth(crop), page.pageWidth - NSMinX(crop)));
    crop.size.height = MAX(0.0, MIN(NSHeight(crop), page.pageHeight - NSMinY(crop)));
    return crop;
}

- (NSRect)pixelSnappedPageCropRect:(NSRect)cropRect
                              page:(SPDFRenderedPage*)page
                              zoom:(CGFloat)zoom
                      displayScale:(CGFloat)displayScale {
    if (!page || NSIsEmptyRect(cropRect) || zoom <= 0.0 || displayScale <= 0.0) return NSZeroRect;
    CGFloat renderScale = MAX(0.01, zoom * displayScale);
    CGFloat x0 = floor(NSMinX(cropRect) * renderScale) / renderScale;
    CGFloat y0 = floor(NSMinY(cropRect) * renderScale) / renderScale;
    CGFloat x1 = ceil(NSMaxX(cropRect) * renderScale) / renderScale;
    CGFloat y1 = ceil(NSMaxY(cropRect) * renderScale) / renderScale;
    x0 = MAX(0.0, MIN(x0, page.pageWidth));
    y0 = MAX(0.0, MIN(y0, page.pageHeight));
    x1 = MAX(x0, MIN(x1, page.pageWidth));
    y1 = MAX(y0, MIN(y1, page.pageHeight));
    return NSMakeRect(x0, y0, x1 - x0, y1 - y0);
}

- (void)renderVisiblePageCropsForCurrentViewportIfNeeded {
    if (!_doc || !_pageScrollView || !_pageView || _renderedPages.count == 0) return;
    CGFloat displayScale = [self backingScale];
    CGFloat margin =
        MAX(NSWidth(_pageScrollView.contentView.bounds), NSHeight(_pageScrollView.contentView.bounds)) * 0.35;
    NSInteger preferredPage = -1;
    NSArray<NSNumber*>* pageIndexes = [self visibleDocumentPageIndexesWithExtraRadius:0 preferredPage:&preferredPage];
    for (NSNumber* number in pageIndexes) {
        NSInteger pageIndex = number.integerValue;
        if (pageIndex < 0 || pageIndex >= (NSInteger)_renderedPages.count) continue;
        SPDFRenderedPage* page = _renderedPages[(NSUInteger)pageIndex];
        if ([self renderedPageImage:page matchesZoom:_zoom displayScale:displayScale]) continue;
        if ([self fullPageRenderAllowedForPage:page zoom:_zoom displayScale:displayScale]) continue;

        NSRect cropRect = [self visiblePageCropRectForPageIndex:pageIndex extraViewMargin:margin];
        cropRect = [self pixelSnappedPageCropRect:cropRect page:page zoom:_zoom displayScale:displayScale];
        if (NSIsEmptyRect(cropRect)) continue;
        if ([self viewportImage:page coversPageCropRect:cropRect zoom:_zoom displayScale:displayScale]) continue;

        char err[512];
        NSImage* image = [self renderedPageCropImageAtIndex:pageIndex
                                                   document:_doc
                                                       zoom:_zoom
                                               displayScale:displayScale
                                               pageCropRect:cropRect
                                                      error:err
                                                errorLength:sizeof(err)];
        if (!image) {
            _statusLabel.stringValue =
                [NSString stringWithFormat:@"Could not render page crop %ld", (long)pageIndex + 1];
            continue;
        }
        page.viewportImage = image;
        page.viewportImagePageRect = cropRect;
        page.viewportImageZoom = _zoom;
        page.viewportImageScale = displayScale;
        [_pageView setNeedsDisplayInRect:[_pageView rectForPageAtIndex:pageIndex]];
    }
}

- (NSUInteger)renderedImageByteCost:(SPDFRenderedPage*)page {
    if (!page.image || page.imagePointWidth <= 0.0 || page.imagePointHeight <= 0.0) return 0;
    CGFloat scale = page.imageScale > 0.0 ? page.imageScale : [self backingScale];
    double pixels = ceil(page.imagePointWidth * scale) * ceil(page.imagePointHeight * scale);
    if (!isfinite(pixels) || pixels <= 0.0) return 0;
    double bytes = pixels * 4.0;
    if (bytes > (double)NSUIntegerMax) return NSUIntegerMax;
    return (NSUInteger)bytes;
}

- (NSUInteger)renderedViewportImageByteCost:(SPDFRenderedPage*)page {
    if (!page.viewportImage || NSIsEmptyRect(page.viewportImagePageRect) || page.viewportImageZoom <= 0.0) return 0;
    CGFloat scale = page.viewportImageScale > 0.0 ? page.viewportImageScale : [self backingScale];
    double pixels = ceil(NSWidth(page.viewportImagePageRect) * page.viewportImageZoom * scale) *
                    ceil(NSHeight(page.viewportImagePageRect) * page.viewportImageZoom * scale);
    if (!isfinite(pixels) || pixels <= 0.0) return 0;
    double bytes = pixels * 4.0;
    if (bytes > (double)NSUIntegerMax) return NSUIntegerMax;
    return (NSUInteger)bytes;
}

- (NSUInteger)estimatedRenderedImageByteCostForPage:(SPDFRenderedPage*)page
                                               zoom:(CGFloat)zoom
                                       displayScale:(CGFloat)displayScale {
    if (!page || page.pageWidth <= 0.0 || page.pageHeight <= 0.0 || zoom <= 0.0) return 0;
    displayScale = displayScale > 0.0 ? displayScale : [self backingScale];
    double pixels = ceil(page.pageWidth * zoom * displayScale) * ceil(page.pageHeight * zoom * displayScale);
    if (!isfinite(pixels) || pixels <= 0.0) return 0;
    double bytes = pixels * 4.0;
    if (bytes > (double)NSUIntegerMax) return NSUIntegerMax;
    return (NSUInteger)bytes;
}

- (BOOL)shouldKeepFullRenderedDocumentAtCurrentZoom {
    if (_renderedPages.count == 0) return NO;
    CGFloat displayScale = [self backingScale];
    NSUInteger totalBytes = 0;
    for (SPDFRenderedPage* page in _renderedPages) {
        NSUInteger bytes = [self estimatedRenderedImageByteCostForPage:page zoom:_zoom displayScale:displayScale];
        if (bytes == 0 || bytes > kRenderedImageKeepAllPerPageByteLimit) return NO;
        if (totalBytes > kRenderedImageKeepAllTotalByteLimit ||
            bytes > kRenderedImageKeepAllTotalByteLimit - totalBytes)
            return NO;
        totalBytes += bytes;
    }
    return YES;
}

- (NSInteger)backgroundRenderBatchSizeForCurrentZoom {
    if ([self shouldKeepFullRenderedDocumentAtCurrentZoom]) return (NSInteger)_renderedPages.count;
    return kBackgroundRenderBatchSize;
}

- (void)addKeepRangeToSet:(NSMutableSet<NSNumber*>*)keep center:(NSInteger)center radius:(NSInteger)radius {
    if (center < 0 || _renderedPages.count == 0) return;
    NSInteger first = MAX(0, center - radius);
    NSInteger last = MIN((NSInteger)_renderedPages.count - 1, center + radius);
    for (NSInteger i = first; i <= last; ++i) [keep addObject:@(i)];
}

- (void)evictDistantRenderedPageImages {
    if (!_renderedPages.count) return;
    if ([self shouldKeepFullRenderedDocumentAtCurrentZoom]) return;

    NSUInteger totalBytes = 0;
    for (SPDFRenderedPage* page in _renderedPages)
        totalBytes += [self renderedImageByteCost:page] + [self renderedViewportImageByteCost:page];
    if (totalBytes <= kRenderedImageSoftByteLimit) return;

    NSMutableSet<NSNumber*>* keep = [NSMutableSet set];
    [self addKeepRangeToSet:keep center:_pageIndex radius:kRenderedImageKeepRadius];
    [self addKeepRangeToSet:keep center:_pageView.currentPageIndex radius:2];
    [self addKeepRangeToSet:keep center:_pageView.activeFindPageIndex radius:1];
    [self addKeepRangeToSet:keep center:_selectionPageIndex radius:1];
    [self addKeepRangeToSet:keep center:_highlightPageIndex radius:1];
    for (NSNumber* queuedPage in _queuedRenderPages) [keep addObject:queuedPage];
    if (_minimapVisible) {
        for (NSNumber* visibleMinimapPage in [_minimapView visiblePageIndexes]) [keep addObject:visibleMinimapPage];
    }

    NSMutableArray<NSDictionary*>* candidates = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)_renderedPages.count; ++i) {
        NSNumber* indexNumber = @(i);
        if ([keep containsObject:indexNumber]) continue;
        SPDFRenderedPage* page = _renderedPages[(NSUInteger)i];
        NSUInteger bytes = [self renderedImageByteCost:page] + [self renderedViewportImageByteCost:page];
        if (bytes == 0) continue;
        NSInteger distance = labs(i - _pageIndex);
        [candidates addObject:@{@"index" : indexNumber, @"distance" : @(distance), @"bytes" : @(bytes)}];
    }

    [candidates sortUsingComparator:^NSComparisonResult(NSDictionary* a, NSDictionary* b) {
      NSInteger distanceA = [a[@"distance"] integerValue];
      NSInteger distanceB = [b[@"distance"] integerValue];
      if (distanceA != distanceB) return distanceA > distanceB ? NSOrderedAscending : NSOrderedDescending;
      NSUInteger bytesA = [a[@"bytes"] unsignedIntegerValue];
      NSUInteger bytesB = [b[@"bytes"] unsignedIntegerValue];
      if (bytesA == bytesB) return NSOrderedSame;
      return bytesA > bytesB ? NSOrderedAscending : NSOrderedDescending;
    }];

    BOOL evicted = NO;
    for (NSDictionary* candidate in candidates) {
        if (totalBytes <= kRenderedImageTargetByteLimit) break;
        NSInteger index = [candidate[@"index"] integerValue];
        if (index < 0 || index >= (NSInteger)_renderedPages.count) continue;
        SPDFRenderedPage* page = _renderedPages[(NSUInteger)index];
        NSUInteger bytes = [self renderedImageByteCost:page] + [self renderedViewportImageByteCost:page];
        if (bytes == 0) continue;
        page.image = nil;
        page.imagePointWidth = 0.0;
        page.imagePointHeight = 0.0;
        page.imageZoom = 0.0;
        page.imageScale = 0.0;
        page.viewportImage = nil;
        page.viewportImagePageRect = NSZeroRect;
        page.viewportImageZoom = 0.0;
        page.viewportImageScale = 0.0;
        totalBytes = bytes > totalBytes ? 0 : totalBytes - bytes;
        evicted = YES;
    }

    if (evicted) {
        _pageView.pages = _renderedPages;
        [_pageView setNeedsDisplay:YES];
        [self updateMinimap];
    }
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
    [_minimapQueue cancelAllOperations];
    [_queuedRenderPages removeAllObjects];
    [_queuedRenderOperations removeAllObjects];
    [_queuedMinimapThumbnailPages removeAllObjects];
    _renderGeneration++;
    NSUInteger generation = _renderGeneration;
    _zoom = [self zoomForFitMode:_fitMode pageIndex:MAX(0, pageIndex)];
    NSMutableArray<SPDFRenderedPage*>* pages = [NSMutableArray arrayWithCapacity:(NSUInteger)spdf_page_count(_doc)];
    char err[1024];
    NSInteger pageCount = spdf_page_count(_doc);
    pageIndex = MAX(0, MIN(pageIndex, pageCount - 1));
    SPDFRenderedPage* preferredPage = [self renderedPageAtIndex:pageIndex error:err errorLength:sizeof(err)];
    if (!preferredPage) {
        _statusLabel.stringValue = strstr(err, "too large")
                                       ? @""
                                       : [NSString stringWithFormat:@"Could not render page %ld", (long)pageIndex + 1];
        preferredPage = [self placeholderPageAtIndex:pageIndex document:_doc fallbackWidth:612.0 fallbackHeight:792.0];
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
            _statusLabel.stringValue = [NSString stringWithFormat:@"Could not prepare page %ld", (long)i + 1];
            return;
        }
        [pages addObject:page];
    }

    [NSAnimationContext
        runAnimationGroup:^(NSAnimationContext* context) {
          context.duration = 0.0;
          context.allowsImplicitAnimation = NO;
          self->_renderedPages = pages;
          [self cacheActiveRenderedPagesForSelectedTab];
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
    [self renderVisiblePageCropsForCurrentViewportIfNeeded];

    [self syncToolbarState];
    [self updateControls];
    [self selectCurrentSidebarRow];
    [self updateMinimap];
    [self evictDistantRenderedPageImages];

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
    _minimapPrecisionViewportDragActive = NO;
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

- (NSPoint)clampedDocumentBoundsScrollOrigin:(NSPoint)origin {
    NSClipView* clipView = _pageScrollView.contentView;
    origin.x = spdf_clamp_cg(origin.x, 0.0, MAX(0.0, NSWidth(_pageView.bounds) - NSWidth(clipView.bounds)));
    origin.y = spdf_clamp_cg(origin.y, 0.0, MAX(0.0, NSHeight(_pageView.bounds) - NSHeight(clipView.bounds)));
    return origin;
}

- (NSPoint)normalizedDocumentScrollOrigin:(NSPoint)origin forPageIndex:(NSInteger)pageIndex {
    if (_renderedPages.count == 0) return [self clampedDocumentScrollOrigin:origin forPageIndex:pageIndex];

    pageIndex = MAX(0, MIN(pageIndex, (NSInteger)_renderedPages.count - 1));
    NSClipView* clipView = _pageScrollView.contentView;
    NSRect pageRect = [_pageView rectForPageAtIndex:pageIndex];
    if (NSIsEmptyRect(pageRect)) return [self clampedDocumentScrollOrigin:origin forPageIndex:pageIndex];

    if (_viewMode == SPDFViewModeSingle) origin.y = [self singlePageDocumentScrollOriginYForPageIndex:pageIndex];

    CGFloat visibleWidth = NSWidth(clipView.bounds);
    if (NSWidth(pageRect) <= visibleWidth + 0.5) {
        origin.x = 0.0;
    } else if (origin.x <= NSMinX(pageRect) + 2.0) {
        origin.x = MAX(0.0, NSMinX(pageRect) - kPageMargin / 2.0);
    }

    return [self clampedDocumentScrollOrigin:origin forPageIndex:pageIndex];
}

- (CGFloat)singlePageDocumentScrollOriginYForPageIndex:(NSInteger)pageIndex {
    if (_renderedPages.count == 0) return 0.0;
    pageIndex = MAX(0, MIN(pageIndex, (NSInteger)_renderedPages.count - 1));
    NSClipView* clipView = _pageScrollView.contentView;
    NSRect pageRect = [self continuousDocumentRectForPageAtIndex:pageIndex];
    if (NSIsEmptyRect(pageRect)) return 0.0;
    CGFloat maxY = MAX(0.0, NSHeight(_pageView.bounds) - NSHeight(clipView.bounds));
    CGFloat y = NSMidY(pageRect) - NSHeight(clipView.bounds) * 0.5;
    return spdf_clamp_cg(y, 0.0, maxY);
}

- (BOOL)normalizeSinglePageScrollPositionFromUserScroll {
    if (_presentationMode || _viewMode != SPDFViewModeSingle || _updatingFromScroll || _renderedPages.count == 0)
        return NO;

    NSClipView* clipView = _pageScrollView.contentView;
    NSRect visibleRect = clipView.bounds;
    NSInteger visiblePage = [_pageView pageIndexForVisibleRect:visibleRect];
    visiblePage = MAX(0, MIN(visiblePage, (NSInteger)_renderedPages.count - 1));
    BOOL pageChanged = visiblePage != _pageIndex;
    if (pageChanged) {
        _pageIndex = visiblePage;
        _pageView.currentPageIndex = _pageIndex;
        [self clearPageFieldFocus];
        [self renderPageIfNeededAtIndex:_pageIndex];
        [self resizeDocumentView];
        visibleRect = clipView.bounds;
        [self enqueueNearbyPageRendersForGeneration:_renderGeneration preferredPage:_pageIndex];
        [self updateControls];
        [self selectCurrentSidebarRow];
    }

    NSPoint snappedOrigin = [self normalizedDocumentScrollOrigin:visibleRect.origin forPageIndex:_pageIndex];
    if (fabs(snappedOrigin.x - NSMinX(visibleRect)) > 0.5 || fabs(snappedOrigin.y - NSMinY(visibleRect)) > 0.5)
        [self scrollDocumentClipViewToOrigin:snappedOrigin pageIndexHint:_pageIndex notify:NO];

    [_pageView setNeedsDisplay:YES];
    [self renderVisiblePageCropsForCurrentViewportIfNeeded];
    [self updateMinimap];
    [self evictDistantRenderedPageImages];
    return YES;
}

- (void)scrollDocumentClipViewToOrigin:(NSPoint)origin pageIndexHint:(NSInteger)pageIndex notify:(BOOL)notify {
    NSClipView* clipView = _pageScrollView.contentView;
    origin = pageIndex >= 0 ? [self clampedDocumentScrollOrigin:origin forPageIndex:pageIndex]
                            : [self clampedDocumentScrollOrigin:origin];
    _updatingFromScroll = YES;
    [NSAnimationContext
        runAnimationGroup:^(NSAnimationContext* context) {
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

- (void)scrollDocumentClipViewToDocumentOrigin:(NSPoint)origin notify:(BOOL)notify {
    NSClipView* clipView = _pageScrollView.contentView;
    origin = [self clampedDocumentBoundsScrollOrigin:origin];
    BOOL wasSuppressingScrollCallbacks = _suppressScrollCallbacks;
    if (!notify) _suppressScrollCallbacks = YES;
    _updatingFromScroll = YES;
    [NSAnimationContext
        runAnimationGroup:^(NSAnimationContext* context) {
          context.duration = 0.0;
          context.allowsImplicitAnimation = NO;
          [clipView setBoundsOrigin:origin];
          [self->_pageScrollView reflectScrolledClipView:clipView];
        }
        completionHandler:nil];
    _updatingFromScroll = NO;
    _suppressScrollCallbacks = wasSuppressingScrollCallbacks;
    if (notify) {
        [self documentScrollPositionChanged];
        [self updateMinimap];
    }
}

- (void)scrollDocumentClipViewToOrigin:(NSPoint)origin notify:(BOOL)notify {
    [self scrollDocumentClipViewToOrigin:origin pageIndexHint:-1 notify:notify];
}

- (void)scrollToPage:(NSInteger)pageIndex alignTop:(BOOL)alignTop {
    if (_renderedPages.count == 0) return;
    pageIndex = MAX(0, MIN(pageIndex, (NSInteger)_renderedPages.count - 1));
    NSRect pageRect = [_pageView rectForPageAtIndex:pageIndex];
    if (alignTop) {
        NSClipView* clipView = _pageScrollView.contentView;
        CGFloat x = NSWidth(pageRect) <= NSWidth(clipView.bounds) + 0.5 ? 0.0 : MAX(0, pageRect.origin.x - 12.0);
        CGFloat y = MAX(0, pageRect.origin.y - 12);
        if (_viewMode == SPDFViewModeSingle) y = [self singlePageDocumentScrollOriginYForPageIndex:pageIndex];
        NSPoint point = NSMakePoint(x, y);
        [self scrollDocumentClipViewToOrigin:point notify:NO];
    } else {
        NSClipView* clipView = _pageScrollView.contentView;
        NSRect visible = clipView.bounds;
        NSPoint origin = visible.origin;
        if (_viewMode == SPDFViewModeSingle) origin.y = [self singlePageDocumentScrollOriginYForPageIndex:pageIndex];
        if (NSMinX(pageRect) < NSMinX(visible))
            origin.x = NSMinX(pageRect) - 12.0;
        else if (NSMaxX(pageRect) > NSMaxX(visible))
            origin.x = NSMaxX(pageRect) - NSWidth(visible) + 12.0;
        if (_viewMode != SPDFViewModeSingle && NSMinY(pageRect) < NSMinY(visible))
            origin.y = NSMinY(pageRect) - 12.0;
        else if (_viewMode != SPDFViewModeSingle && NSMaxY(pageRect) > NSMaxY(visible))
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

    [NSAnimationContext
        runAnimationGroup:^(NSAnimationContext* context) {
          context.duration = 0.0;
          context.allowsImplicitAnimation = NO;
          [self->_window.contentView layoutSubtreeIfNeeded];
          [self->_documentContainer layoutSubtreeIfNeeded];
          [self->_pageScrollView layoutSubtreeIfNeeded];
          [self resizeDocumentView];
          if (restoreOrigin) {
              NSPoint origin = [self normalizedDocumentScrollOrigin:restoreOrigin.pointValue
                                                       forPageIndex:self->_pageIndex];
              [self scrollDocumentClipViewToOrigin:origin notify:NO];
          } else {
              [self scrollToPage:self->_pageIndex alignTop:alignTop];
          }
          [self renderVisiblePageCropsForCurrentViewportIfNeeded];
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
    if (_viewMode == SPDFViewModeSingle) origin.y = [self singlePageDocumentScrollOriginYForPageIndex:pageIndex];
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
    if (_presentationMode &&
        (_fitMode == SPDFFitModeWidth || _fitMode == SPDFFitModeHeight || _fitMode == SPDFFitModePage)) {
        [self renderDocumentAndScrollToPage:_pageIndex alignTop:YES];
        [self persistActiveState];
        return;
    }
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
    if (_viewMode == SPDFViewModeSingle) {
        CGFloat height = kPageMargin / 2.0;
        for (SPDFRenderedPage* page in _renderedPages ?: @[]) height += MAX(1.0, page.pageHeight * _zoom) + kPageGap;
        height += kPageMargin / 2.0;
        return MAX(1.0, height);
    }
    return MAX(1.0, NSHeight(_pageView.bounds));
}

- (CGFloat)continuousDocumentWidthForMinimap {
    if (_viewMode == SPDFViewModeSingle) {
        CGFloat widest = 0.0;
        for (SPDFRenderedPage* page in _renderedPages ?: @[]) widest = MAX(widest, page.pageWidth * _zoom);
        return MAX(1.0, MAX(NSWidth(_pageView.bounds), widest + kPageMargin));
    }
    return MAX(1.0, NSWidth(_pageView.bounds));
}

- (NSRect)continuousDocumentRectForPageAtIndex:(NSInteger)pageIndex {
    if (pageIndex < 0 || pageIndex >= (NSInteger)_renderedPages.count || !_pageView) return NSZeroRect;
    if (_viewMode == SPDFViewModeSingle) {
        CGFloat y = kPageMargin / 2.0;
        for (NSInteger i = 0; i < pageIndex; ++i) {
            SPDFRenderedPage* prev = _renderedPages[(NSUInteger)i];
            y += MAX(1.0, prev.pageHeight * _zoom) + kPageGap;
        }

        SPDFRenderedPage* page = _renderedPages[(NSUInteger)pageIndex];
        CGFloat width = MAX(1.0, page.pageWidth * _zoom);
        CGFloat height = MAX(1.0, page.pageHeight * _zoom);
        CGFloat documentWidth = [self continuousDocumentWidthForMinimap];
        CGFloat x = floor((documentWidth - width) / 2.0);
        return NSMakeRect(MAX(kPageMargin / 2.0, x), y, width, height);
    }
    return [_pageView rectForPageAtIndex:pageIndex];
}

- (NSRect)continuousDocumentVisibleRectForMinimap {
    if (_viewMode == SPDFViewModeSingle) {
        if (_renderedPages.count == 0) return NSZeroRect;
        NSInteger pageIndex = MAX(0, MIN(_pageIndex, (NSInteger)_renderedPages.count - 1));
        NSRect pageRect = [_pageView rectForPageAtIndex:pageIndex];
        NSRect visibleRect = _pageScrollView.contentView.bounds;
        NSRect intersection = NSIntersectionRect(visibleRect, pageRect);
        NSRect minimapPageRect = [self continuousDocumentRectForPageAtIndex:pageIndex];
        if (NSIsEmptyRect(minimapPageRect)) return NSZeroRect;
        if (NSIsEmptyRect(intersection)) return minimapPageRect;

        CGFloat x0 = spdf_clamp_cg((NSMinX(intersection) - NSMinX(pageRect)) / MAX(1.0, NSWidth(pageRect)), 0.0, 1.0);
        CGFloat x1 = spdf_clamp_cg((NSMaxX(intersection) - NSMinX(pageRect)) / MAX(1.0, NSWidth(pageRect)), 0.0, 1.0);
        CGFloat y0 = spdf_clamp_cg((NSMinY(intersection) - NSMinY(pageRect)) / MAX(1.0, NSHeight(pageRect)), 0.0, 1.0);
        CGFloat y1 = spdf_clamp_cg((NSMaxY(intersection) - NSMinY(pageRect)) / MAX(1.0, NSHeight(pageRect)), 0.0, 1.0);
        return NSMakeRect(NSMinX(minimapPageRect) + x0 * NSWidth(minimapPageRect),
                          NSMinY(minimapPageRect) + y0 * NSHeight(minimapPageRect),
                          MAX(1.0, (x1 - x0) * NSWidth(minimapPageRect)),
                          MAX(1.0, (y1 - y0) * NSHeight(minimapPageRect)));
    }
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
    if (_viewMode == SPDFViewModeSingle)
        origin.y = [self singlePageDocumentScrollOriginYForPageIndex:pageIndex];
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
    _minimapView.documentWidth = [self continuousDocumentWidthForMinimap];
    _minimapView.documentHeight = MAX(1.0, [self continuousDocumentHeightForMinimap]);
    _minimapView.documentScale = MAX(0.01, _zoom);
    [_minimapView setNeedsDisplay:YES];
    [self enqueueVisibleMinimapThumbnailRenders];
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

- (void)minimapViewDidRequestViewportTopFraction:(CGFloat)yFraction {
    [self minimapViewDidRequestViewportTopFraction:yFraction
                                   documentCenterX:NSMidX([self continuousDocumentVisibleRectForMinimap])];
}

- (void)minimapViewDidRequestViewportTopFraction:(CGFloat)yFraction documentCenterX:(CGFloat)documentCenterX {
    if (!_doc || _renderedPages.count == 0) return;
    yFraction = spdf_clamp_cg(yFraction, 0.0, 1.0);

    if (_viewMode == SPDFViewModeSingle) {
        NSRect visibleRect = [self continuousDocumentVisibleRectForMinimap];
        CGFloat documentHeight = [self continuousDocumentHeightForMinimap];
        CGFloat documentTop = yFraction * MAX(0.0, documentHeight - NSHeight(visibleRect));
        CGFloat pageFraction = 0.0;
        NSInteger pageIndex = [self pageIndexForContinuousDocumentY:documentTop + NSHeight(visibleRect) * 0.5
                                                       pageFraction:&pageFraction];
        NSRect pageRect = [self continuousDocumentRectForPageAtIndex:pageIndex];
        CGFloat xFraction =
            !NSIsEmptyRect(pageRect) && isfinite(documentCenterX)
                ? spdf_clamp_cg((documentCenterX - NSMinX(pageRect)) / MAX(1.0, NSWidth(pageRect)), 0.0, 1.0)
                : 0.5;
        [self minimapViewDidRequestCenterOnPage:pageIndex xFractionInPage:xFraction yFractionInPage:pageFraction];
        return;
    }

    NSClipView* clipView = _pageScrollView.contentView;
    CGFloat maxY = MAX(0.0, NSHeight(_pageView.bounds) - NSHeight(clipView.bounds));
    NSPoint origin = clipView.bounds.origin;
    if (isfinite(documentCenterX)) origin.x = documentCenterX - NSWidth(clipView.bounds) * 0.5;
    origin.y = yFraction * maxY;

    NSInteger pageIndex = [_pageView
        pageIndexForVisibleRect:NSMakeRect(origin.x, origin.y, NSWidth(clipView.bounds), NSHeight(clipView.bounds))];
    pageIndex = MAX(0, MIN(pageIndex, (NSInteger)_renderedPages.count - 1));
    if (_viewMode == SPDFViewModeSingle && pageIndex != _pageIndex) {
        _pageIndex = pageIndex;
        _pageView.currentPageIndex = _pageIndex;
        [self renderPageIfNeededAtIndex:_pageIndex];
        [self updateControls];
        [self selectCurrentSidebarRow];
    }

    if (_viewMode == SPDFViewModeContinuous) {
        _minimapPrecisionViewportDragActive = YES;
        [self scrollDocumentClipViewToDocumentOrigin:origin notify:NO];
        [self syncCurrentPageFromVisibleViewportQueueRenders:YES forceHighPriority:YES];
        [self renderVisiblePageCropsForCurrentViewportIfNeeded];
        [_pageView setNeedsDisplay:YES];
        [_pageView displayIfNeeded];
        [self updateMinimap];
    } else {
        [self scrollDocumentClipViewToOrigin:origin pageIndexHint:pageIndex notify:YES];
        [self renderVisiblePageCropsForCurrentViewportIfNeeded];
        [_pageView setNeedsDisplay:YES];
        [self rememberActiveTabState];
    }
}

- (void)minimapViewDidFinishViewportDrag {
    _minimapPrecisionViewportDragActive = NO;
    if (!_doc || _renderedPages.count == 0) return;
    [self documentScrollPositionChanged];
    [self rememberActiveTabState];
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
    NSPoint documentPoint = [self continuousDocumentPointForPage:pageIndex
                                                 xFractionInPage:xFraction
                                                 yFractionInPage:yFraction];
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
    if (_viewMode == SPDFViewModeSingle) {
        CGFloat yFraction = 0.0;
        NSInteger pageIndex = [self pageIndexForContinuousDocumentY:documentPoint.y pageFraction:&yFraction];
        if (pageIndex != _pageIndex) {
            _pageIndex = pageIndex;
            _pageView.currentPageIndex = _pageIndex;
            [self renderPageIfNeededAtIndex:_pageIndex];
            [self resizeDocumentView];
            [self updateControls];
            [self selectCurrentSidebarRow];
        }

        NSRect minimapPageRect = [self continuousDocumentRectForPageAtIndex:pageIndex];
        NSRect pageRect = [_pageView rectForPageAtIndex:pageIndex];
        if (!NSIsEmptyRect(minimapPageRect) && !NSIsEmptyRect(pageRect)) {
            CGFloat xFraction = spdf_clamp_cg(
                (documentPoint.x - NSMinX(minimapPageRect)) / MAX(1.0, NSWidth(minimapPageRect)), 0.0, 1.0);
            return NSMakePoint(NSMinX(pageRect) + xFraction * NSWidth(pageRect),
                               NSMinY(pageRect) + spdf_clamp_cg(yFraction, 0.0, 1.0) * NSHeight(pageRect));
        }
    }
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
    tab.showSidebar = _sidebarPreferredVisible;
    tab.showMinimap = _minimapPreferredVisible;
    [self cacheActiveRenderedPagesForSelectedTab];
    [self saveDocumentStateForTab:tab];
    tab.scrollOrigin = [self normalizedDocumentScrollOrigin:_pageScrollView.contentView.bounds.origin
                                               forPageIndex:_pageIndex];
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

- (NSArray<NSString*>*)openTabPaths {
    NSMutableArray<NSString*>* paths = [NSMutableArray arrayWithCapacity:_tabs.count];
    for (SPDFDocumentTab* tab in _tabs) [paths addObject:tab.path ?: @""];
    return paths;
}

- (SPDFDocumentTab*)selectedTab {
    if (_selectedTabIndex < 0 || _selectedTabIndex >= (NSInteger)_tabs.count) return nil;
    return _tabs[(NSUInteger)_selectedTabIndex];
}

- (NSDictionary*)fileAttributesForPath:(NSString*)path {
    if (!path.length) return nil;
    return [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
}

- (void)recordFileAttributes:(NSDictionary*)attributes forTab:(SPDFDocumentTab*)tab {
    tab.cachedModificationDate = attributes[NSFileModificationDate];
    tab.cachedFileSize = [attributes[NSFileSize] unsignedLongLongValue];
}

- (BOOL)fileAttributes:(NSDictionary*)lhs matchFileAttributes:(NSDictionary*)rhs {
    if (!lhs || !rhs) return NO;
    NSDate* lhsModificationDate = lhs[NSFileModificationDate];
    NSDate* rhsModificationDate = rhs[NSFileModificationDate];
    unsigned long long lhsFileSize = [lhs[NSFileSize] unsignedLongLongValue];
    unsigned long long rhsFileSize = [rhs[NSFileSize] unsignedLongLongValue];
    return lhsModificationDate && [lhsModificationDate isEqualToDate:rhsModificationDate] && lhsFileSize == rhsFileSize;
}

- (BOOL)tab:(SPDFDocumentTab*)tab cacheMatchesFileAttributes:(NSDictionary*)attributes {
    if (!tab.cachedDocument || !attributes) return NO;
    NSDate* modificationDate = attributes[NSFileModificationDate];
    unsigned long long fileSize = [attributes[NSFileSize] unsignedLongLongValue];
    return tab.cachedModificationDate && [tab.cachedModificationDate isEqualToDate:modificationDate] &&
           tab.cachedFileSize == fileSize;
}

- (BOOL)ensureCachedRenderedPagesForTab:(SPDFDocumentTab*)tab preferredPage:(NSInteger)preferredPage {
    if (!tab.cachedDocument) return NO;
    NSInteger pageCount = spdf_page_count(tab.cachedDocument);
    if (pageCount <= 0) return NO;
    if (tab.cachedRenderedPages.count == (NSUInteger)pageCount) return YES;

    preferredPage = MAX(0, MIN(preferredPage, pageCount - 1));
    char err[256];
    float fallbackWidth = 1.0;
    float fallbackHeight = 1.0;
    spdf_page_size(tab.cachedDocument, (int)preferredPage, &fallbackWidth, &fallbackHeight, err, sizeof(err));
    NSMutableArray<SPDFRenderedPage*>* pages = [NSMutableArray arrayWithCapacity:(NSUInteger)pageCount];
    for (NSInteger pageIndex = 0; pageIndex < pageCount; ++pageIndex) {
        SPDFRenderedPage* page = [self placeholderPageAtIndex:pageIndex
                                                     document:tab.cachedDocument
                                                fallbackWidth:MAX(1.0f, fallbackWidth)
                                               fallbackHeight:MAX(1.0f, fallbackHeight)];
        if (!page) return NO;
        [pages addObject:page];
    }
    tab.cachedRenderedPages = pages;
    return YES;
}

- (void)cacheActiveRenderedPagesForSelectedTab {
    SPDFDocumentTab* tab = [self selectedTab];
    if (!tab || tab.cachedDocument != _doc ||
        ![_path.stringByStandardizingPath isEqualToString:tab.path.stringByStandardizingPath])
        return;
    tab.cachedRenderedPages = _renderedPages;
}

- (void)clearActiveMetadata {
    if (!_activeMetadataBorrowed) {
        spdf_free_outline(&_outline);
        spdf_free_comments(&_comments);
    }
    memset(&_outline, 0, sizeof(_outline));
    memset(&_comments, 0, sizeof(_comments));
    _activeMetadataBorrowed = NO;
    _activeMetadataTab = nil;
}

- (void)adoptCachedMetadataForTab:(SPDFDocumentTab*)tab {
    [self clearActiveMetadata];
    if (!tab) return;
    if (tab.cachedOutlineLoaded) _outline = tab.cachedOutline;
    if (tab.cachedCommentsLoaded) _comments = tab.cachedComments;
    _activeMetadataBorrowed = YES;
    _activeMetadataTab = tab;
}

- (void)discardCachedRuntimeForTab:(SPDFDocumentTab*)tab {
    if (!tab) return;
    if (_activeMetadataTab == tab) [self clearActiveMetadata];
    if (_doc == tab.cachedDocument) _doc = NULL;
    [tab clearCachedRuntime];
}

- (void)closeActiveDocumentIfUnowned {
    if (!_doc) return;
    for (SPDFDocumentTab* tab in _tabs) {
        if (tab.cachedDocument == _doc) {
            _doc = NULL;
            return;
        }
    }
    spdf_close(_doc);
    _doc = NULL;
}

- (void)cancelInactiveTabPreloads {
    [_preloadQueue cancelAllOperations];
    [_preloadingPaths removeAllObjects];
    [_preloadTokens removeAllObjects];
}

- (BOOL)preloadToken:(NSString*)token isCurrentForPath:(NSString*)standardizedPath {
    return token.length > 0 && [(_preloadTokens[standardizedPath] ?: @"") isEqualToString:token];
}

- (void)finishPreloadForPath:(NSString*)standardizedPath token:(NSString*)token {
    if (![self preloadToken:token isCurrentForPath:standardizedPath]) return;
    [_preloadTokens removeObjectForKey:standardizedPath];
    [_preloadingPaths removeObject:standardizedPath];
}

- (void)prepareSelectedTabViewState:(SPDFDocumentTab*)tab path:(NSString*)path {
    _path = [path copy];
    _highlightPageIndex = -1;
    _selectionPageIndex = -1;
    _selectedText = nil;
    _searchField.stringValue = tab.searchText ?: @"";
    _findRegexCheckbox.state = tab.searchRegex ? NSControlStateValueOn : NSControlStateValueOff;
    _findRegexMultiline = tab.searchRegexMultiline;
    _sidebarPreferredVisible = tab.showSidebar;
    _minimapPreferredVisible = tab.showMinimap;
    [self clearFindResults];
}

- (void)showUnavailableSelectedTab:(SPDFDocumentTab*)tab
                              path:(NSString*)path
                           message:(NSString*)message
                     showOpenError:(BOOL)showOpenError
                             error:(const char*)err {
    [self discardCachedRuntimeForTab:tab];
    _doc = NULL;
    [self clearActiveMetadata];
    [self prepareSelectedTabViewState:tab path:path];
    _pageIndex = 0;
    _renderGeneration++;
    [_renderedPages removeAllObjects];
    [self replaceDocumentViewForTabSwitch];
    [self rebuildSidebar];
    [self showEmptyDocumentViewWithMessage:message];
    _window.title = [NSString
        stringWithFormat:@"%@ - %@ - Shenzhen PDF", [self displayNameForPathConsideringOpenTabs:path], message];
    _statusLabel.stringValue = [message stringByAppendingString:@"."];
    [self updateTabStrip];
    [self updateControls];
    [self clearToolbarFieldFocusForTabSwitch];
    [self savePersistentState];
    if (showOpenError) {
        [self showError:@"Could not open document"
                 detail:[NSString stringWithUTF8String:err && *err ? err : "Unknown error"]];
    }
}

- (SPDFDocumentTab*)tabForStandardizedPath:(NSString*)standardizedPath index:(NSInteger*)indexOut {
    for (NSInteger i = 0; i < (NSInteger)_tabs.count; ++i) {
        SPDFDocumentTab* tab = _tabs[(NSUInteger)i];
        if ([tab.path.stringByStandardizingPath isEqualToString:standardizedPath]) {
            if (indexOut) *indexOut = i;
            return tab;
        }
    }
    if (indexOut) *indexOut = -1;
    return nil;
}

- (NSString*)displayNameForPathConsideringOpenTabs:(NSString*)path {
    if (!path.length) return @"";
    NSString* standardized = path.stringByStandardizingPath;
    NSArray<NSString*>* paths = [self openTabPaths];
    NSArray<NSString*>* names = spdf_disambiguated_display_names_for_paths(paths);
    for (NSUInteger i = 0; i < paths.count && i < names.count; ++i) {
        if ([paths[i].stringByStandardizingPath isEqualToString:standardized] && names[i].length) return names[i];
    }
    return spdf_display_name_for_path(path);
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

- (BOOL)eventHitsStandardWindowButton:(NSEvent*)event {
    if (!_window || !event) return NO;
    for (NSNumber* buttonType in @[ @(NSWindowCloseButton), @(NSWindowMiniaturizeButton), @(NSWindowZoomButton) ]) {
        NSButton* button = [_window standardWindowButton:(NSWindowButton)buttonType.integerValue];
        if (!button || button.hidden || !button.enabled) continue;
        NSRect buttonRect = [button convertRect:button.bounds toView:nil];
        buttonRect = NSInsetRect(buttonRect, -8.0, -8.0);
        if (NSPointInRect(event.locationInWindow, buttonRect)) return YES;
    }
    return NO;
}

- (BOOL)handleTabStripMouseEvent:(NSEvent*)event {
    if (!_tabStrip || !_window || _presentationMode) return NO;

    NSEventType type = event.type;
    if (type == NSEventTypeRightMouseDown) {
        if (_tabStripHeightConstraint.constant <= 0.0) return NO;
        NSPoint point = [_tabStrip convertPoint:event.locationInWindow fromView:nil];
        if (!NSPointInRect(point, _tabStrip.bounds)) return NO;
        [_tabStrip rightMouseDown:event];
        return YES;
    }

    if (type == NSEventTypeLeftMouseDown) {
        if ([self eventHitsStandardWindowButton:event]) {
            [self dismissTabHoverPanel];
            return NO;
        }
        if (_tabStripHeightConstraint.constant <= 0.0) return NO;
        NSPoint point = [_tabStrip convertPoint:event.locationInWindow fromView:nil];
        if (!NSPointInRect(point, _tabStrip.bounds)) return NO;

        if (![_tabStrip containsTabOrControlAtPoint:point]) {
            [self dismissTabHoverPanel];
            _tabStripCapturingMouse = NO;
            [_window performWindowDragWithEvent:event];
            return YES;
        }
        _tabStripCapturingMouse = YES;
        _window.movable = NO;
        [_tabStrip mouseDown:event];
        return YES;
    }

    if (!_tabStripCapturingMouse) return NO;
    if (type == NSEventTypeLeftMouseDragged) {
        [_tabStrip mouseDragged:event];
        return YES;
    }
    if (type == NSEventTypeLeftMouseUp) {
        _tabStripCapturingMouse = NO;
        _window.movable = YES;
        [_tabStrip mouseUp:event];
        return YES;
    }
    return NO;
}

- (void)preloadInactiveTabs {
    for (NSInteger i = 0; i < (NSInteger)_tabs.count; ++i) {
        if (i == _selectedTabIndex) continue;
        SPDFDocumentTab* tab = _tabs[(NSUInteger)i];
        NSString* path = [tab.path copy];
        if (!path.length) continue;
        NSString* standardized = [path.stringByStandardizingPath copy];
        if ([_preloadingPaths containsObject:standardized]) continue;

        NSDictionary* attributes = [self fileAttributesForPath:path];
        if (!attributes) {
            [self discardCachedRuntimeForTab:tab];
            tab.missingFile = YES;
            tab.missingMessage = @"File moved or deleted";
            continue;
        }
        if ([self tab:tab cacheMatchesFileAttributes:attributes]) {
            tab.missingFile = NO;
            tab.missingMessage = @"";
            continue;
        }

        [_preloadingPaths addObject:standardized];
        NSString* preloadToken = NSUUID.UUID.UUIDString;
        _preloadTokens[standardized] = preloadToken;
        NSInteger preferredPage = MAX(0, tab.pageIndex);
        SPDFFitMode fitMode = tab.fitMode;
        CGFloat fallbackZoom = tab.customZoom > 0 ? tab.customZoom : (tab.zoom > 0 ? tab.zoom : 1.0);
        NSSize clipSize = [self documentClipSizeForLayout];
        CGFloat displayScale = [self backingScale];

        [_preloadQueue addOperationWithBlock:^{
          @autoreleasepool {
              NSDictionary* operationAttributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
              if (!operationAttributes) {
                  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    if (![self preloadToken:preloadToken isCurrentForPath:standardized]) return;
                    [self finishPreloadForPath:standardized token:preloadToken];
                    NSInteger tabIndex = -1;
                    SPDFDocumentTab* currentTab = [self tabForStandardizedPath:standardized index:&tabIndex];
                    if (!currentTab || tabIndex == self->_selectedTabIndex) return;
                    [self discardCachedRuntimeForTab:currentTab];
                    currentTab.missingFile = YES;
                    currentTab.missingMessage = @"File moved or deleted";
                    [self updateTabStrip];
                  }];
                  return;
              }

              char err[1024];
              spdf_document* doc = spdf_open(path.fileSystemRepresentation, err, sizeof(err));
              if (!doc) {
                  NSString* message = @"Could not open document";
                  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    if (![self preloadToken:preloadToken isCurrentForPath:standardized]) return;
                    [self finishPreloadForPath:standardized token:preloadToken];
                    NSInteger tabIndex = -1;
                    SPDFDocumentTab* currentTab = [self tabForStandardizedPath:standardized index:&tabIndex];
                    if (!currentTab || tabIndex == self->_selectedTabIndex) return;
                    [self discardCachedRuntimeForTab:currentTab];
                    currentTab.missingFile = NO;
                    currentTab.missingMessage = message;
                    [self updateTabStrip];
                  }];
                  return;
              }

              NSInteger pageCount = spdf_page_count(doc);
              if (pageCount <= 0) {
                  spdf_close(doc);
                  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    if (![self preloadToken:preloadToken isCurrentForPath:standardized]) return;
                    [self finishPreloadForPath:standardized token:preloadToken];
                    NSInteger tabIndex = -1;
                    SPDFDocumentTab* currentTab = [self tabForStandardizedPath:standardized index:&tabIndex];
                    if (!currentTab || tabIndex == self->_selectedTabIndex) return;
                    [self discardCachedRuntimeForTab:currentTab];
                    currentTab.missingFile = NO;
                    currentTab.missingMessage = @"Could not open document";
                    [self updateTabStrip];
                  }];
                  return;
              }

              NSInteger pageIndex = MAX(0, MIN(preferredPage, pageCount - 1));
              float pageWidth = 0;
              float pageHeight = 0;
              spdf_page_size(doc, (int)pageIndex, &pageWidth, &pageHeight, err, sizeof(err));
              CGFloat fallbackWidth = pageWidth > 0 ? pageWidth : 1.0;
              CGFloat fallbackHeight = pageHeight > 0 ? pageHeight : 1.0;
              NSMutableArray<SPDFRenderedPage*>* pages = [NSMutableArray arrayWithCapacity:(NSUInteger)pageCount];
              for (NSInteger page = 0; page < pageCount; ++page) {
                  SPDFRenderedPage* renderedPage = [self placeholderPageAtIndex:page
                                                                       document:doc
                                                                  fallbackWidth:fallbackWidth
                                                                 fallbackHeight:fallbackHeight];
                  if (!renderedPage) {
                      spdf_close(doc);
                      [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        if (![self preloadToken:preloadToken isCurrentForPath:standardized]) return;
                        [self finishPreloadForPath:standardized token:preloadToken];
                        [self updateTabStrip];
                      }];
                      return;
                  }
                  [pages addObject:renderedPage];
              }

              [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                if (![self preloadToken:preloadToken isCurrentForPath:standardized]) {
                    spdf_close(doc);
                    return;
                }
                NSInteger tabIndex = -1;
                SPDFDocumentTab* currentTab = [self tabForStandardizedPath:standardized index:&tabIndex];
                if (!currentTab || tabIndex == self->_selectedTabIndex) {
                    [self finishPreloadForPath:standardized token:preloadToken];
                    spdf_close(doc);
                    return;
                }
                NSDictionary* latestAttributes = [self fileAttributesForPath:currentTab.path];
                if (![self fileAttributes:operationAttributes matchFileAttributes:latestAttributes]) {
                    [self finishPreloadForPath:standardized token:preloadToken];
                    spdf_close(doc);
                    return;
                }
                [self discardCachedRuntimeForTab:currentTab];
                currentTab.cachedDocument = doc;
                currentTab.cachedRenderedPages = pages;
                [self recordFileAttributes:operationAttributes forTab:currentTab];
                currentTab.missingFile = NO;
                currentTab.missingMessage = @"";
                currentTab.title = spdf_display_name_for_path(currentTab.path);
                [self updateTabStrip];
              }];

              spdf_document* renderDoc = spdf_open(path.fileSystemRepresentation, err, sizeof(err));
              if (!renderDoc) {
                  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    if ([self preloadToken:preloadToken isCurrentForPath:standardized])
                        [self finishPreloadForPath:standardized token:preloadToken];
                  }];
                  return;
              }
              CGFloat zoom = [self zoomForFitMode:fitMode
                                         pageSize:NSMakeSize(pageWidth, pageHeight)
                                         clipSize:clipSize
                                     fallbackZoom:fallbackZoom];
              SPDFRenderedPage* preferredRenderedPage = [self renderedPageAtIndex:pageIndex
                                                                         document:renderDoc
                                                                             zoom:zoom
                                                                     displayScale:displayScale
                                                                            error:err
                                                                      errorLength:sizeof(err)];
              spdf_close(renderDoc);
              [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                if (![self preloadToken:preloadToken isCurrentForPath:standardized]) return;
                [self finishPreloadForPath:standardized token:preloadToken];
                if (!preferredRenderedPage) return;
                NSInteger tabIndex = -1;
                SPDFDocumentTab* currentTab = [self tabForStandardizedPath:standardized index:&tabIndex];
                if (!currentTab || tabIndex == self->_selectedTabIndex ||
                    ![self tab:currentTab cacheMatchesFileAttributes:[self fileAttributesForPath:currentTab.path]])
                    return;
                if (pageIndex < 0 || pageIndex >= (NSInteger)currentTab.cachedRenderedPages.count) return;
                SPDFRenderedPage* old = currentTab.cachedRenderedPages[(NSUInteger)pageIndex];
                preferredRenderedPage.highlights = old.highlights ?: @[];
                preferredRenderedPage.selectionRects = old.selectionRects ?: @[];
                [currentTab.cachedRenderedPages replaceObjectAtIndex:(NSUInteger)pageIndex
                                                          withObject:preferredRenderedPage];
              }];
          }
        }];
    }
    [self updateTabStrip];
}

- (void)loadCommentsForCurrentDocumentAsync {
    if (!_doc || !_path.length) return;
    SPDFDocumentTab* tab = [self selectedTab];
    if (tab.cachedCommentsLoaded) {
        [self adoptCachedMetadataForTab:tab];
        [self rebuildSidebar];
        [_pageView setNeedsDisplay:YES];
        return;
    }

    NSString* path = [_path copy];
    NSString* standardizedPath = [_path.stringByStandardizingPath copy];
    NSUInteger generation = _renderGeneration;
    [_preloadQueue addOperationWithBlock:^{
      @autoreleasepool {
          __block spdf_comments comments;
          memset(&comments, 0, sizeof(comments));
          char err[1024];
          spdf_document* doc = spdf_open(path.fileSystemRepresentation, err, sizeof(err));
          BOOL ok = doc && spdf_load_comments(doc, &comments, err, sizeof(err));
          if (doc) spdf_close(doc);

          [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            SPDFDocumentTab* currentTab = [self selectedTab];
            if (generation != self->_renderGeneration || !self->_doc ||
                ![self->_path.stringByStandardizingPath isEqualToString:standardizedPath] || currentTab != tab) {
                spdf_free_comments(&comments);
                return;
            }
            if (ok) {
                [tab replaceCachedComments:comments loaded:YES];
            } else {
                spdf_free_comments(&comments);
                spdf_comments emptyComments;
                memset(&emptyComments, 0, sizeof(emptyComments));
                [tab replaceCachedComments:emptyComments loaded:YES];
            }
            [self adoptCachedMetadataForTab:tab];
            [self rebuildSidebar];
            [self->_pageView setNeedsDisplay:YES];
          }];
      }
    }];
}

- (void)loadOutlineForCurrentDocumentAsync {
    if (!_doc || !_path.length) return;
    SPDFDocumentTab* tab = [self selectedTab];
    if (tab.cachedOutlineLoaded) {
        [self adoptCachedMetadataForTab:tab];
        [self rebuildSidebar];
        return;
    }

    NSString* path = [_path copy];
    NSString* standardizedPath = [_path.stringByStandardizingPath copy];
    NSUInteger generation = _renderGeneration;
    [_preloadQueue addOperationWithBlock:^{
      @autoreleasepool {
          __block spdf_outline outline;
          memset(&outline, 0, sizeof(outline));
          char err[1024];
          spdf_document* doc = spdf_open(path.fileSystemRepresentation, err, sizeof(err));
          BOOL ok = doc && spdf_load_outline(doc, &outline, err, sizeof(err));
          if (doc) spdf_close(doc);

          [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            SPDFDocumentTab* currentTab = [self selectedTab];
            if (generation != self->_renderGeneration || !self->_doc ||
                ![self->_path.stringByStandardizingPath isEqualToString:standardizedPath] || currentTab != tab) {
                spdf_free_outline(&outline);
                return;
            }
            if (ok) {
                [tab replaceCachedOutline:outline loaded:YES];
            } else {
                spdf_free_outline(&outline);
                spdf_outline emptyOutline;
                memset(&emptyOutline, 0, sizeof(emptyOutline));
                [tab replaceCachedOutline:emptyOutline loaded:YES];
            }
            [self adoptCachedMetadataForTab:tab];
            [self rebuildSidebar];
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
                       [self loadOutlineForCurrentDocumentAsync];
                       [self loadCommentsForCurrentDocumentAsync];
                       [self preloadInactiveTabs];
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
    _liveZooming = NO;
    if (_doc) {
        [self renderDocumentPreservingScrollPosition];
        [self persistActiveState];
    }
}

- (void)beginLiveZoomByFactor:(CGFloat)factor centeredAtWindowPoint:(NSPoint)windowPoint {
    if (!_doc || factor <= 0) return;
    _fitMode = SPDFFitModeCustom;
    _liveZooming = YES;
    [_zoomFinishTimer invalidate];
    [self setZoomWithoutRendering:_zoom * factor centeredAtWindowPoint:windowPoint];
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

- (void)activateCachedSelectedTab:(SPDFDocumentTab*)tab
                             path:(NSString*)path
                       attributes:(NSDictionary*)attributes
              savedFindMatchIndex:(NSInteger)savedFindMatchIndex {
    _doc = tab.cachedDocument;
    if (!_doc || ![self ensureCachedRenderedPagesForTab:tab preferredPage:tab.pageIndex]) return;

    tab.missingFile = NO;
    tab.missingMessage = @"";
    [self recordFileAttributes:attributes forTab:tab];
    [self prepareSelectedTabViewState:tab path:path];
    [self adoptCachedMetadataForTab:tab];
    _pageIndex = MAX(0, MIN(tab.pageIndex, spdf_page_count(_doc) - 1));
    _fitMode = tab.fitMode;
    _viewMode = tab.viewMode;
    _rememberedCustomZoom = tab.customZoom > 0 ? tab.customZoom : (tab.zoom > 0 ? tab.zoom : 1.0);
    _zoom = [self zoomForFitMode:_fitMode pageIndex:_pageIndex];
    _renderGeneration++;

    _renderedPages = tab.cachedRenderedPages;
    _pageScrollView.hidden = NO;
    _pageView.emptyMessage = @"Open a document";
    _pageView.pages = _renderedPages;
    _pageView.currentPageIndex = _pageIndex;
    _pageView.zoom = _zoom;
    _pageView.viewMode = _viewMode;
    _pageView.backingScale = [self backingScale];
    if (_presentationMode)
        _pageScrollView.verticalScroller = nil;
    else if (_pageScrollView.verticalScroller != _markerScroller)
        _pageScrollView.verticalScroller = _markerScroller;
    _pageScrollView.hasVerticalScroller = !_presentationMode;
    BOOL previousSuppressViewportRerender = _suppressViewportRerender;
    _suppressViewportRerender = YES;
    [self setMinimapActuallyVisible:_minimapPreferredVisible];
    tab.title = spdf_display_name_for_path(_path);

    [self rebuildSidebar];
    _suppressViewportRerender = previousSuppressViewportRerender;
    [self updateTabStrip];
    [self savePersistentState];

    NSClipView* clipView = _pageScrollView.contentView;
    BOOL previousPostsBoundsChangedNotifications = clipView.postsBoundsChangedNotifications;
    BOOL previousSuppressScrollCallbacks = _suppressScrollCallbacks;
    _suppressScrollCallbacks = YES;
    clipView.postsBoundsChangedNotifications = NO;
    NSValue* restoreOrigin = tab.hasScrollOrigin ? [NSValue valueWithPoint:tab.scrollOrigin] : nil;
    NSUInteger layoutGeneration = _renderGeneration;
    NSString* layoutPath = [_path copy];

    [NSAnimationContext
        runAnimationGroup:^(NSAnimationContext* context) {
          context.duration = 0.0;
          context.allowsImplicitAnimation = NO;
          [self->_window.contentView layoutSubtreeIfNeeded];
          [self->_documentContainer layoutSubtreeIfNeeded];
          [self resizeDocumentView];
          if (restoreOrigin)
              [self scrollDocumentClipViewToOrigin:[self normalizedDocumentScrollOrigin:restoreOrigin.pointValue
                                                                           forPageIndex:self->_pageIndex]
                                            notify:NO];
          else
              [self scrollToPage:self->_pageIndex alignTop:YES];
          [self->_pageView setNeedsDisplay:YES];
        }
        completionHandler:nil];

    clipView.postsBoundsChangedNotifications = previousPostsBoundsChangedNotifications;
    _suppressScrollCallbacks = previousSuppressScrollCallbacks;
    [self documentScrollPositionChanged];
    [self syncToolbarState];
    [self updateControls];
    [self selectCurrentSidebarRow];
    [self updateMinimap];
    [self enqueuePageRendersForGeneration:layoutGeneration
                              pageIndexes:@[ @(_pageIndex) ]
                            preferredPage:_pageIndex
                        forceHighPriority:YES];
    [self schedulePostFirstPaintWorkForGeneration:layoutGeneration
                                             path:layoutPath
                              savedFindMatchIndex:savedFindMatchIndex
                                    restoreSearch:_searchField.stringValue.length > 0
                              preferredRenderPage:_pageIndex];
    [self clearToolbarFieldFocusForTabSwitch];
}

- (void)loadSelectedTab {
    if (_selectedTabIndex < 0 || _selectedTabIndex >= (NSInteger)_tabs.count) return;
    [self clearToolbarFieldFocusForTabSwitch];
    SPDFDocumentTab* tab = _tabs[(NSUInteger)_selectedTabIndex];
    if (!tab.path.length) return;
    NSString* path = [tab.path copy];
    NSInteger savedFindMatchIndex = tab.findMatchIndex;
    [_renderQueue cancelAllOperations];
    [_minimapQueue cancelAllOperations];
    [_queuedRenderPages removeAllObjects];
    [_queuedRenderOperations removeAllObjects];
    [_queuedMinimapThumbnailPages removeAllObjects];

    [self closeActiveDocumentIfUnowned];
    NSDictionary* attributes = [self fileAttributesForPath:path];
    if (!attributes) {
        tab.missingFile = YES;
        tab.missingMessage = @"File moved or deleted";
        [self showUnavailableSelectedTab:tab path:path message:tab.missingMessage showOpenError:NO error:NULL];
        return;
    }

    if ([self tab:tab cacheMatchesFileAttributes:attributes]) {
        [self activateCachedSelectedTab:tab path:path attributes:attributes savedFindMatchIndex:savedFindMatchIndex];
        return;
    }

    [self discardCachedRuntimeForTab:tab];
    [self clearActiveMetadata];

    char err[1024];
    spdf_document* newDoc = spdf_open(path.fileSystemRepresentation, err, sizeof(err));
    if (!newDoc) {
        NSString* message = @"Could not open document";
        tab.missingFile = NO;
        tab.missingMessage = message;
        [self showUnavailableSelectedTab:tab path:path message:message showOpenError:YES error:err];
        return;
    }

    tab.missingFile = NO;
    tab.missingMessage = @"";
    tab.cachedDocument = newDoc;
    [self recordFileAttributes:attributes forTab:tab];
    _doc = newDoc;
    [self prepareSelectedTabViewState:tab path:path];
    _pageIndex = MAX(0, MIN(tab.pageIndex, spdf_page_count(_doc) - 1));
    _renderGeneration++;
    _rememberedCustomZoom = tab.customZoom > 0 ? tab.customZoom : (tab.zoom > 0 ? tab.zoom : 1.0);
    _fitMode = tab.fitMode;
    _viewMode = tab.viewMode;
    _zoom = [self zoomForFitMode:_fitMode pageIndex:_pageIndex];

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
    NSString* closedPath = [_path copy];
    [self rememberClosedDocumentPath:closedPath];
    [self cancelInactiveTabPreloads];
    [self clearActiveMetadata];
    [self closeActiveDocumentIfUnowned];
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
    _window.title = @"Shenzhen PDF";
    _statusLabel.stringValue = @"Ready";
    [self rebuildSidebar];
    [self showEmptyDocumentViewWithMessage:@"Open a document"];
    [self updateControls];
}

- (SPDFDocumentTab*)newTabForPath:(NSString*)path {
    SPDFDocumentTab* tab = [[SPDFDocumentTab alloc] init];
    tab.path = [path copy];
    tab.title = spdf_display_name_for_path(path);
    tab.zoom = 1.0;
    tab.customZoom = 1.0;
    tab.fitMode = SPDFFitModePage;
    tab.viewMode = _viewMode;
    tab.searchText = @"";
    tab.searchRegex = NO;
    tab.searchRegexMultiline = YES;
    tab.findMatchIndex = -1;
    tab.showSidebar = YES;
    tab.showMinimap = YES;
    [self applyStoredDocumentStateToTab:tab];
    return tab;
}

- (void)openPaths:(NSArray<NSString*>*)paths {
    if (!_uiReady || !_window) {
        if (paths.count > 0) _pendingOpenPath = [paths.firstObject copy];
        for (NSString* path in paths) {
            if (path.length && ![_pendingOpenPaths containsObject:path]) [_pendingOpenPaths addObject:path];
        }
        return;
    }

    if (paths.count == 0) return;
    if (!_suspendPersistentStateSaves) {
        [self performWithBatchedPersistentStateSaves:^{
          [self openPaths:paths];
        }];
        return;
    }

    [self rememberActiveTabState];
    NSInteger targetIndex = -1;
    for (NSString* path in paths) {
        if (![path isKindOfClass:NSString.class] || path.length == 0) continue;
        NSInteger existing = [self indexOfTabForPath:path];
        if (existing >= 0) {
            targetIndex = existing;
            continue;
        }
        SPDFDocumentTab* tab = [self newTabForPath:path];
        [_tabs addObject:tab];
        targetIndex = (NSInteger)_tabs.count - 1;
    }

    if (targetIndex >= 0) {
        if (targetIndex == _selectedTabIndex && _doc) {
            if (_path.length > 0) [self rememberRecentlyOpenedPath:_path];
            [self savePersistentState];
            return;
        }
        [self selectTabAtIndex:targetIndex];
        if (_doc && _path.length > 0) [self rememberRecentlyOpenedPath:_path];
        [self savePersistentState];
    }
}

- (void)openPath:(NSString*)path {
    if (!path.length) return;
    [self openPaths:@[ path ]];
}

- (SPDFDocumentTab*)tabSnapshotForDragAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_tabs.count) return nil;
    [self rememberActiveTabState];
    return spdf_copy_document_tab(_tabs[(NSUInteger)index]);
}

- (void)insertDraggedTab:(SPDFDocumentTab*)tab atIndex:(NSInteger)index {
    if (!tab.path.length) return;
    NSInteger existing = [self indexOfTabForPath:tab.path];
    if (existing >= 0) {
        [self selectTabAtIndex:existing];
        return;
    }
    tab.title = tab.title.length ? tab.title : spdf_display_name_for_path(tab.path);
    [self rememberActiveTabState];
    index = MAX(0, MIN(index, (NSInteger)_tabs.count));
    [_tabs insertObject:tab atIndex:(NSUInteger)index];
    _selectedTabIndex = index;
    [self loadSelectedTab];
    if (_doc && _path.length > 0) [self rememberRecentlyOpenedPath:_path];
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
    SPDFDocumentTab* closingTab = _tabs[(NSUInteger)index];
    NSString* closedPath = [closingTab.path copy];
    [self rememberClosedDocumentPath:closedPath];
    [_preloadingPaths removeObject:closedPath.stringByStandardizingPath];
    [_preloadTokens removeObjectForKey:closedPath.stringByStandardizingPath];
    [self discardCachedRuntimeForTab:closingTab];
    [_tabs removeObjectAtIndex:(NSUInteger)index];
    if (!closingActive && index < _selectedTabIndex) _selectedTabIndex--;

    if (_tabs.count == 0) {
        BOOL shouldCloseThisWindow = [self hasOtherShenzhenWindows];
        [self clearToolbarFieldFocusForTabSwitch];
        _selectedTabIndex = -1;
        [self cancelInactiveTabPreloads];
        [self clearActiveMetadata];
        [self closeActiveDocumentIfUnowned];
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
        if (shouldCloseThisWindow) {
            [self removeSessionStateForCurrentWindow];
            _suppressSessionWriteOnTerminate = YES;
            _terminateOnlyThisProcess = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
              [NSApp terminate:self];
            });
            return;
        }
        [self showEmptyDocumentViewWithMessage:@"Open a document"];
        _window.title = @"Shenzhen PDF";
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

- (void)showTabInFolderAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_tabs.count) {
        NSBeep();
        return;
    }
    SPDFDocumentTab* tab = _tabs[(NSUInteger)index];
    [self showPathInFolder:tab.path];
}

- (void)copyTabFileToPasteboardAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_tabs.count) {
        NSBeep();
        return;
    }
    SPDFDocumentTab* tab = _tabs[(NSUInteger)index];
    if (!tab.path.length) {
        NSBeep();
        return;
    }

    NSURL* fileURL = [NSURL fileURLWithPath:tab.path];
    NSPasteboard* pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    if (![pasteboard writeObjects:@[ fileURL ]]) {
        NSBeep();
        return;
    }
    _statusLabel.stringValue = @"File copied.";
}

- (void)moveTabFromIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex {
    NSInteger count = (NSInteger)_tabs.count;
    if (fromIndex < 0 || fromIndex >= count || toIndex < 0 || toIndex >= count || fromIndex == toIndex) return;

    SPDFDocumentTab* tab = _tabs[(NSUInteger)fromIndex];
    [_tabs removeObjectAtIndex:(NSUInteger)fromIndex];
    [_tabs insertObject:tab atIndex:(NSUInteger)toIndex];

    if (_selectedTabIndex == fromIndex) {
        _selectedTabIndex = toIndex;
    } else if (fromIndex < _selectedTabIndex && _selectedTabIndex <= toIndex) {
        _selectedTabIndex--;
    } else if (toIndex <= _selectedTabIndex && _selectedTabIndex < fromIndex) {
        _selectedTabIndex++;
    }

    [self updateTabStrip];
    [self savePersistentState];
}

- (void)detachTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_tabs.count) return;

    [self rememberActiveTabState];
    SPDFDocumentTab* tab = _tabs[(NSUInteger)index];
    NSString* path = [tab.path copy];
    if (path.length == 0) return;

    NSString* executable = NSBundle.mainBundle.executablePath ?: NSProcessInfo.processInfo.arguments.firstObject;
    if (executable.length == 0) return;

    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:executable];
    task.arguments = @[ @"--detached-tab", path ];
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];

    NSError* error = nil;
    if (![task launchAndReturnError:&error]) {
        [self showError:@"Could not detach tab" detail:error.localizedDescription ?: @"Launch failed"];
        return;
    }

    [self closeTabAtIndex:index];
}

- (void)newTabRequested:(id)sender {
    [self openDocument:sender];
}

- (void)openRecentDocument:(id)sender {
    if (![sender isKindOfClass:NSMenuItem.class]) return;
    NSString* path = ((NSMenuItem*)sender).representedObject;
    if (![path isKindOfClass:NSString.class] || path.length == 0) return;
    [self openPath:path];
}

- (void)reopenLastClosedDocument:(id)sender {
    (void)sender;
    NSString* path = _closedDocumentPaths.lastObject;
    if (!path.length) return;
    [_closedDocumentPaths removeLastObject];
    [self openPath:path];
}

- (BOOL)openFilesFromPasteboard:(NSPasteboard*)pasteboard {
    NSArray<NSURL*>* urls = [pasteboard readObjectsForClasses:@[ [NSURL class] ]
                                                      options:@{NSPasteboardURLReadingFileURLsOnlyKey : @YES}];
    NSMutableArray<NSString*>* paths = [NSMutableArray array];
    for (NSURL* url in urls) {
        NSString* ext = url.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"pdf"] || [ext isEqualToString:@"xps"] || [ext isEqualToString:@"cbz"] ||
            [ext isEqualToString:@"epub"]) {
            [paths addObject:url.path];
        }
    }
    if (paths.count == 0) return NO;
    [self openPaths:paths];
    return YES;
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
    [self relayoutDocumentForViewportChange];
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
    [self relayoutDocumentForViewportChange];
    [self updateMinimap];
    if (actualVisible && _doc) {
        if (!_suppressViewportRerender) [self renderPageIfNeededAtIndex:_pageIndex];
        [self enqueueNearbyPageRendersForGeneration:_renderGeneration preferredPage:_pageIndex];
    }
    [self syncToolbarState];
}

- (void)minimapDividerDraggedByDeltaX:(CGFloat)deltaX {
    if (!_minimapPreferredVisible || !_minimapVisible) return;
    CGFloat maxWidth = MAX(120.0, MIN(320.0, NSWidth(_documentContainer.bounds) * 0.35));
    _minimapWidth = spdf_clamp_cg(_minimapWidth - deltaX, 72.0, maxWidth);
    _minimapWidthConstraint.constant = _minimapWidth;
    [_documentContainer layoutSubtreeIfNeeded];
    [self resizeDocumentView];
    [self renderVisiblePageCropsForCurrentViewportIfNeeded];
    [_pageView setNeedsDisplay:YES];
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
    if (_restoringSidebarLayout || !_allowSidebarWidthPersistence) return;
    if (_doc) [self relayoutDocumentForViewportChange];
    if ((NSEvent.pressedMouseButtons & 1) == 0) return;
    CGFloat width = NSWidth(_sidebarContainer.frame);
    if ([self currentSidebarFrameIsPersistable])
        _sidebarWidth = spdf_sane_sidebar_width(width, NSWidth(_splitView.bounds));
}

- (NSString*)sidebarFilterTextForCurrentMode {
    if (_sidebarModeControl.selectedSegment == SPDFSidebarModeComments) return _commentFilterText ?: @"";
    return _chapterFilterText ?: @"";
}

- (void)setSidebarFilterTextForCurrentMode:(NSString*)filter {
    filter = filter ?: @"";
    if (_sidebarModeControl.selectedSegment == SPDFSidebarModeComments)
        _commentFilterText = [filter copy];
    else
        _chapterFilterText = [filter copy];
}

- (void)syncSidebarFilterField {
    if (!_sidebarFilterField) return;
    BOOL comments = _sidebarModeControl.selectedSegment == SPDFSidebarModeComments;
    _updatingSidebarFilterField = YES;
    _sidebarFilterField.placeholderString = comments ? @"Filter Comments" : @"Filter Chapters";
    _sidebarFilterField.stringValue = [self sidebarFilterTextForCurrentMode];
    _updatingSidebarFilterField = NO;
}

- (BOOL)sidebarSearchText:(NSString*)text matchesFilter:(NSString*)filter {
    if (filter.length == 0) return YES;
    if (text.length == 0) return NO;
    return [text rangeOfString:filter options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location !=
           NSNotFound;
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

    [self syncSidebarFilterField];
    NSString* filter = [self sidebarFilterTextForCurrentMode];
    if (hasSidebar) {
        if (_sidebarModeControl.selectedSegment == SPDFSidebarModeComments && hasComments) {
            for (int i = 0; i < _comments.count; ++i) {
                spdf_comment_item item = _comments.items[i];
                NSString* type = item.type && *item.type ? [NSString stringWithUTF8String:item.type] : @"Comment";
                NSString* author = item.author && *item.author ? [NSString stringWithUTF8String:item.author] : @"";
                NSString* text = item.text && *item.text ? [NSString stringWithUTF8String:item.text] : @"";
                NSString* title = text.length ? text : type;
                if (author.length) title = [NSString stringWithFormat:@"%@: %@", author, title];
                NSString* haystack = [NSString
                    stringWithFormat:@"%@ %@ %@ p.%d", title ?: @"", author ?: @"", type ?: @"", item.page_index + 1];
                if (![self sidebarSearchText:haystack matchesFilter:filter]) continue;
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
                if (![self sidebarSearchText:title matchesFilter:filter]) continue;
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
    [self syncSidebarFilterField];
    [self rebuildSidebar];
}

- (void)goToAdjacentPagePreservingRelativePosition:(NSInteger)delta {
    if (!_doc || delta == 0) return;
    NSInteger pageCount = spdf_page_count(_doc);
    if (pageCount <= 0) return;
    NSInteger target = MAX(0, MIN(_pageIndex + delta, pageCount - 1));
    if (target == _pageIndex) return;
    [self goToPage:target preserveSinglePagePosition:YES];
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
    if (_minimapPrecisionViewportDragActive) {
        [self syncCurrentPageFromVisibleViewportQueueRenders:YES forceHighPriority:YES];
        [self renderVisiblePageCropsForCurrentViewportIfNeeded];
        [_pageView setNeedsDisplay:YES];
        [_pageView displayIfNeeded];
        [self updateMinimap];
        return;
    }
    if (_presentationMode) {
        [self updateMinimap];
        return;
    }
    if ([self normalizeSinglePageScrollPositionFromUserScroll]) return;
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
    [self renderVisiblePageCropsForCurrentViewportIfNeeded];
    [self updateMinimap];
    [self evictDistantRenderedPageImages];
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
    BOOL home = event.keyCode == 115;
    BOOL end = event.keyCode == 119;
    BOOL pageUp = event.keyCode == 116;
    BOOL pageDown = event.keyCode == 121;
    BOOL returnKey = event.keyCode == 36 || event.keyCode == 76;
    BOOL deleteKey = event.keyCode == 51;
    BOOL shift = (flags & NSEventModifierFlagShift) != 0;
    if (_presentationMode && home) {
        [self firstPage:nil];
        return YES;
    }
    if (_presentationMode && end) {
        [self lastPage:nil];
        return YES;
    }
    if (_presentationMode && (space || returnKey)) {
        [self nextPage:nil];
        return YES;
    }
    if (_presentationMode && deleteKey) {
        [self previousPage:nil];
        return YES;
    }
    if (!left && !right && !down && !up && !pageUp && !pageDown) return NO;

    if (!_presentationMode && _viewMode == SPDFViewModeContinuous && shift && (left || right || up || down)) {
        [self goToAdjacentPagePreservingRelativePosition:(left || up) ? -1 : 1];
        return YES;
    }

    if (_presentationMode || _viewMode == SPDFViewModeSingle) {
        if (left || up || pageUp)
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

- (BOOL)documentTypeToSearchKeyDown:(NSEvent*)event {
    if (!_doc || _presentationMode || !_searchField) return NO;
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    if (flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption |
                 NSEventModifierFlagFunction))
        return NO;

    id firstResponder = _window.firstResponder;
    if ([firstResponder isKindOfClass:[NSTextView class]] || firstResponder == _searchField ||
        firstResponder == _pageField || firstResponder == _paletteSearchField || firstResponder == _sidebarFilterField)
        return NO;

    NSString* typed = event.characters ?: @"";
    if (typed.length == 0) return NO;
    NSCharacterSet* controls = NSCharacterSet.controlCharacterSet;
    for (NSUInteger i = 0; i < typed.length; ++i) {
        if ([controls characterIsMember:[typed characterAtIndex:i]]) return NO;
    }

    [_window makeFirstResponder:_searchField];
    _searchField.stringValue = typed;
    NSText* editor = _searchField.currentEditor;
    if (editor) [editor setSelectedRange:NSMakeRange(typed.length, 0)];
    [self startFindForCurrentQueryResetSavedIndex:YES revealMatch:YES];
    return YES;
}

- (BOOL)scrollViewShouldTurnWheelIntoPageChange:(NSEvent*)event {
    (void)event;
    if (!_doc) return NO;
    return _viewMode == SPDFViewModeSingle || _fitMode == SPDFFitModeHeight || _fitMode == SPDFFitModePage;
}

- (BOOL)isAutoFitMode:(SPDFFitMode)fitMode {
    return fitMode == SPDFFitModeWidth || fitMode == SPDFFitModeHeight || fitMode == SPDFFitModePage;
}

- (void)relayoutDocumentForViewportChange {
    if (!_doc) {
        [self resizeDocumentView];
        return;
    }
    if (!_suppressViewportRerender && [self isAutoFitMode:_fitMode] && _renderedPages.count > 0) {
        NSPoint relativePosition = [self relativeScrollPositionForCurrentPage];
        [self renderDocumentAndScrollToPage:_pageIndex alignTop:NO];
        [self scrollToPage:_pageIndex preservingRelativePosition:relativePosition];
        return;
    }
    [self resizeDocumentView];
    [self renderVisiblePageCropsForCurrentViewportIfNeeded];
    [_pageView setNeedsDisplay:YES];
}

- (NSMenuItem*)fitModePopupItemForMode:(SPDFFitMode)mode {
    for (NSMenuItem* item in _fitModePopup.itemArray)
        if (item.tag == mode) return item;
    return nil;
}

- (void)syncToolbarState {
    CGFloat customZoom =
        _fitMode == SPDFFitModeCustom ? _zoom : (_rememberedCustomZoom > 0 ? _rememberedCustomZoom : _zoom);
    NSString* zoomTitle = [NSString stringWithFormat:@"%.0f%%", customZoom * 100.0];
    BOOL showCustomZoom = _fitMode == SPDFFitModeCustom || fabs(customZoom - 1.0) > 0.0049;
    NSMenuItem* customItem = [self fitModePopupItemForMode:SPDFFitModeCustom];
    if (showCustomZoom) {
        if (!customItem) {
            [_fitModePopup insertItemWithTitle:zoomTitle atIndex:0];
            customItem = [_fitModePopup itemAtIndex:0];
            customItem.tag = SPDFFitModeCustom;
        }
        customItem.title = zoomTitle;
    } else if (customItem) {
        NSInteger customIndex = [_fitModePopup indexOfItem:customItem];
        if (customIndex >= 0) [_fitModePopup removeItemAtIndex:customIndex];
    }
    NSMenuItem* actualItem = [self fitModePopupItemForMode:SPDFFitModeActual];
    if (actualItem) actualItem.title = @"100%";
    NSMenuItem* selectedFitItem = [self fitModePopupItemForMode:_fitMode];
    if (selectedFitItem) [_fitModePopup selectItem:selectedFitItem];
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
    _translateButton.enabled = hasDoc && !_translationRunning && !_translationInstallRunning;
    _minimapToggleButton.enabled = hasDoc;
    [self updateFindControls];
    _pageField.stringValue = hasDoc ? [NSString stringWithFormat:@"%ld", (long)_pageIndex + 1] : @"";
    _pageCountLabel.stringValue = [NSString stringWithFormat:@"/ %ld", (long)pageCount];
    [self syncToolbarState];

    if (hasDoc) {
        NSString* displayName = _path.length ? [self displayNameForPathConsideringOpenTabs:_path]
                                             : [NSString stringWithUTF8String:spdf_title(_doc)];
        _window.title = [NSString stringWithFormat:@"%@ - Shenzhen PDF", displayName];
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
    [self renderVisiblePageCropsForCurrentViewportIfNeeded];
    [_pageView setNeedsDisplay:YES];
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
    NSInteger action = [self presentationMouseActionForEvent:event];
    if (action < 0) {
        [self previousPage:nil];
        return YES;
    }
    if (action > 0) {
        [self nextPage:nil];
        return YES;
    }
    return NO;
}

- (NSInteger)presentationMouseActionForEvent:(NSEvent*)event {
    if (!event) return 0;
    if (event.type == NSEventTypeLeftMouseDown) {
        return (event.modifierFlags & NSEventModifierFlagControl) != 0 ? -1 : 1;
    }
    if (event.type == NSEventTypeRightMouseDown) return -1;
    if (event.type == NSEventTypeOtherMouseDown) {
        // AppKit uses 0/1 for left/right; "other" buttons start at 2. Treat middle/forward buttons
        // as next, while common back-side buttons go previous.
        return event.buttonNumber == 3 ? -1 : 1;
    }
    return 0;
}

- (BOOL)handlePresentationEvent:(NSEvent*)event {
    if (!_presentationMode || !_doc || !event) return NO;
    NSInteger keyCode = event.type == NSEventTypeKeyDown ? event.keyCode : -1;
    BOOL mouseEvent = event.type == NSEventTypeLeftMouseDown || event.type == NSEventTypeRightMouseDown ||
                      event.type == NSEventTypeOtherMouseDown;
    NSInteger buttonNumber = mouseEvent ? event.buttonNumber : -1;
    if (_lastPresentationEventType == event.type && _lastPresentationEventKeyCode == keyCode &&
        _lastPresentationEventButtonNumber == buttonNumber &&
        fabs(event.timestamp - _lastPresentationEventTimestamp) < 0.03) {
        return YES;
    }

    BOOL handled = NO;
    if (event.type == NSEventTypeKeyDown)
        handled = [self documentArrowKeyDown:event];
    else if (mouseEvent) {
        [NSApp activateIgnoringOtherApps:YES];
        [_window makeKeyWindow];
        [_window makeMainWindow];
        handled = [self documentViewHandlePresentationMouseDown:event];
    }
    if (handled) {
        _lastPresentationEventType = event.type;
        _lastPresentationEventKeyCode = keyCode;
        _lastPresentationEventButtonNumber = buttonNumber;
        _lastPresentationEventTimestamp = event.timestamp;
        [_window makeFirstResponder:_presentationOverlayView ?: _pageView];
    }
    return handled;
}

- (BOOL)documentViewInPresentationMode {
    return _presentationMode;
}

- (NSArray<NSValue*>*)currentSelectionRects {
    if (_selectionPageIndex < 0 || _selectionPageIndex >= (NSInteger)_renderedPages.count) return @[];
    return _renderedPages[(NSUInteger)_selectionPageIndex].selectionRects ?: @[];
}

- (NSString*)trimmedLanguageCode:(NSString*)code {
    NSString* trimmed =
        [[code ?: @"" lowercaseString] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableString* sanitized = [NSMutableString string];
    NSCharacterSet* allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz-_"];
    for (NSUInteger i = 0; i < trimmed.length; ++i) {
        unichar ch = [trimmed characterAtIndex:i];
        if ([allowed characterIsMember:ch]) [sanitized appendFormat:@"%C", ch];
    }
    return sanitized;
}

- (NSString*)translationSuffixForTargetLanguage:(NSString*)targetLanguage {
    NSString* language = [self trimmedLanguageCode:targetLanguage];
    if ([language isEqualToString:@"en"]) return @"english";
    if (!language.length) return @"translated";
    return language;
}

- (NSString*)translatedOutputPathForPath:(NSString*)path targetLanguage:(NSString*)targetLanguage {
    NSString* dir = path.stringByDeletingLastPathComponent;
    NSString* stem = path.stringByDeletingPathExtension.lastPathComponent;
    NSString* suffix = [self translationSuffixForTargetLanguage:targetLanguage];
    return [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_%@.pdf", stem, suffix]];
}

- (void)populateTranslationLanguagePopup:(NSPopUpButton*)popup selectedCode:(NSString*)selectedCode {
    [popup removeAllItems];
    NSString* selected = [self trimmedLanguageCode:selectedCode];
    BOOL selectedExists = NO;
    for (NSDictionary<NSString*, NSString*>* language in spdf_translation_languages()) {
        NSString* code = language[@"code"] ?: @"";
        NSString* name = language[@"name"] ?: code;
        [popup addItemWithTitle:[NSString stringWithFormat:@"%@ (%@)", name, code]];
        popup.lastItem.representedObject = code;
        if ([code isEqualToString:selected]) selectedExists = YES;
    }
    if (selected.length && !selectedExists) {
        [popup addItemWithTitle:[NSString stringWithFormat:@"Custom (%@)", selected]];
        popup.lastItem.representedObject = selected;
    }
    NSInteger index = 0;
    for (NSInteger i = 0; i < popup.numberOfItems; ++i) {
        NSString* code = popup.itemArray[(NSUInteger)i].representedObject;
        if ([code isKindOfClass:NSString.class] && [code isEqualToString:selected]) {
            index = i;
            break;
        }
    }
    [popup selectItemAtIndex:index];
}

- (NSString*)selectedTranslationLanguageCodeFromPopup:(NSPopUpButton*)popup fallback:(NSString*)fallback {
    NSString* code = popup.selectedItem.representedObject;
    if (![code isKindOfClass:NSString.class] || !code.length) code = fallback;
    return [self trimmedLanguageCode:code];
}

- (NSDictionary*)promptForTranslationOptionsUsingSelection:(BOOL)usingSelection {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = usingSelection ? @"Translate Selection" : @"Translate Document";
    alert.informativeText =
        @"Choose an offline Argos language package. Missing packages can be downloaded automatically.";
    [alert addButtonWithTitle:@"Translate"];
    [alert addButtonWithTitle:@"Cancel"];

    NSView* accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 390, 78)];
    NSTextField* sourceLabel = [NSTextField labelWithString:@"From"];
    sourceLabel.frame = NSMakeRect(0, 48, 72, 22);
    NSPopUpButton* sourcePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(84, 44, 250, 26) pullsDown:NO];
    [self populateTranslationLanguagePopup:sourcePopup selectedCode:_translationSourceLanguage ?: @"zh"];
    NSTextField* targetLabel = [NSTextField labelWithString:@"To"];
    targetLabel.frame = NSMakeRect(0, 14, 72, 22);
    NSPopUpButton* targetPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(84, 10, 250, 26) pullsDown:NO];
    [self populateTranslationLanguagePopup:targetPopup selectedCode:_translationTargetLanguage ?: @"en"];
    for (NSView* view in @[ sourceLabel, sourcePopup, targetLabel, targetPopup ]) [accessory addSubview:view];
    alert.accessoryView = accessory;

    if ([alert runModal] != NSAlertFirstButtonReturn) return nil;

    NSString* source = [self selectedTranslationLanguageCodeFromPopup:sourcePopup fallback:@"zh"];
    NSString* target = [self selectedTranslationLanguageCodeFromPopup:targetPopup fallback:@"en"];
    if (!source.length || !target.length) {
        [self showError:@"Translation needs language codes" detail:@"Choose source and target languages for Argos."];
        return nil;
    }
    if ([source isEqualToString:target]) {
        [self showError:@"Translation needs different languages" detail:@"The source and target language codes match."];
        return nil;
    }

    _translationSourceLanguage = source;
    _translationTargetLanguage = target;
    [self savePersistentState];
    return @{@"source" : source, @"target" : target};
}

- (NSString*)currentTextForTranslationUsingSelection:(BOOL*)usingSelection error:(NSString**)errorOut {
    _pendingTranslationItems = nil;
    BOOL hasSelection = _selectedText.length > 0 && _selectionPageIndex >= 0 && [self currentSelectionRects].count > 0;
    if (hasSelection) {
        NSRect bounds = NSZeroRect;
        BOOL hasBounds = NO;
        for (NSValue* value in [self currentSelectionRects]) {
            NSRect rect = value.rectValue;
            bounds = hasBounds ? NSUnionRect(bounds, rect) : rect;
            hasBounds = YES;
        }
        if (!hasBounds) {
            if (errorOut) *errorOut = @"Could not locate the selected text on the page.";
            return nil;
        }
        _pendingTranslationItems = @[ @{
            @"page" : @(_selectionPageIndex),
            @"rect" : [NSValue valueWithRect:bounds],
            @"font" : @(MAX(8.0, MIN(18.0, NSHeight(bounds) * 0.8)))
        } ];
        if (usingSelection) *usingSelection = YES;
        return _selectedText;
    }

    if (usingSelection) *usingSelection = NO;
    if (!_doc) {
        if (errorOut) *errorOut = @"No document is open.";
        return nil;
    }

    NSMutableArray<NSDictionary*>* items = [NSMutableArray array];
    NSMutableString* text = [NSMutableString string];
    char err[1024];
    int pageCount = spdf_page_count(_doc);
    for (int page = 0; page < pageCount; ++page) {
        spdf_text_lines lines;
        memset(&lines, 0, sizeof(lines));
        if (!spdf_extract_page_text_lines(_doc, page, &lines, err, sizeof(err))) {
            if (errorOut)
                *errorOut = [NSString stringWithFormat:@"Could not extract text from page %d: %s", page + 1,
                                                       err[0] ? err : "Unknown error"];
            return nil;
        }
        for (int i = 0; i < lines.count; ++i) {
            const char* lineText = lines.items[i].text;
            if (!lineText || !*lineText) continue;
            NSString* sourceLine = [NSString stringWithUTF8String:lineText] ?: @"";
            if (sourceLine.length == 0) continue;
            NSRect rect = NSMakeRect(lines.items[i].bounds.x0, lines.items[i].bounds.y0,
                                     lines.items[i].bounds.x1 - lines.items[i].bounds.x0,
                                     lines.items[i].bounds.y1 - lines.items[i].bounds.y0);
            [items addObject:@{
                @"page" : @(page),
                @"rect" : [NSValue valueWithRect:rect],
                @"font" : @(lines.items[i].font_size)
            }];
            [text appendString:sourceLine];
            [text appendString:@"\n"];
        }
        spdf_free_text_lines(&lines);
    }

    if (items.count == 0 || text.length == 0) {
        if (errorOut) *errorOut = @"No selectable document text was found. Run OCR first, then translate.";
        return nil;
    }
    _pendingTranslationItems = items;
    return text;
}

- (BOOL)writeTranslatedPDFWithText:(NSString*)text
                        sourcePath:(NSString*)sourcePath
                        outputPath:(NSString*)outputPath
                             error:(NSError**)errorOut {
    (void)sourcePath;
    if (text.length == 0 || outputPath.length == 0 || _pendingTranslationItems.count == 0) return NO;

    NSArray<NSString*>* outputLines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSMutableArray<NSString*>* mappedText = [NSMutableArray arrayWithCapacity:_pendingTranslationItems.count];
    if (_pendingTranslationItems.count == 1) {
        [mappedText addObject:text];
    } else {
        for (NSUInteger i = 0; i < _pendingTranslationItems.count; ++i) {
            NSString* translated = i < outputLines.count ? outputLines[i] : @"";
            [mappedText addObject:translated.length ? translated : @" "];
        }
        if (outputLines.count > _pendingTranslationItems.count && mappedText.count > 0) {
            NSMutableString* tail = [mappedText.lastObject mutableCopy];
            for (NSUInteger i = _pendingTranslationItems.count; i < outputLines.count; ++i) {
                NSString* extra = outputLines[i];
                if (extra.length == 0) continue;
                if (tail.length > 0) [tail appendString:@"\n"];
                [tail appendString:extra];
            }
            mappedText[mappedText.count - 1] = tail;
        }
    }

    NSUInteger count = MIN(_pendingTranslationItems.count, mappedText.count);
    spdf_translated_line* lines = (spdf_translated_line*)calloc(count ? count : 1, sizeof(spdf_translated_line));
    if (!lines) return NO;
    for (NSUInteger i = 0; i < count; ++i) {
        NSDictionary* item = _pendingTranslationItems[i];
        NSRect rect = [item[@"rect"] rectValue];
        lines[i].page_index = [item[@"page"] intValue];
        lines[i].bounds.x0 = (float)NSMinX(rect);
        lines[i].bounds.y0 = (float)NSMinY(rect);
        lines[i].bounds.x1 = (float)NSMaxX(rect);
        lines[i].bounds.y1 = (float)NSMaxY(rect);
        lines[i].font_size = [item[@"font"] floatValue];
        lines[i].opaque_background = SPDF_TRANSLATION_BACKGROUND_OPAQUE;
        lines[i].text = mappedText[i].UTF8String;
    }

    char err[1024];
    BOOL ok = spdf_save_translated_copy(_doc, outputPath.fileSystemRepresentation, lines, (int)count, err, sizeof(err));
    free(lines);
    if (!ok && errorOut) {
        NSString* detail = [NSString stringWithUTF8String:err[0] ? err : "Could not save translated PDF."];
        *errorOut =
            [NSError errorWithDomain:@"ShenzhenPDFTranslation"
                                code:1
                            userInfo:@{NSLocalizedDescriptionKey : detail ?: @"Could not save translated PDF."}];
    }
    return ok;
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
    NSDictionary* result = [self promptForCommentEditorWithTitle:@"Edit Comment"
                                                     buttonTitle:@"Save"
                                                          author:author
                                                            text:text];
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
    __weak ShenzhenMacDelegate* weakSelf = self;
    _paletteEventMonitor =
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown |
                                                      NSEventMaskOtherMouseDown | NSEventMaskKeyDown
                                              handler:^NSEvent*(NSEvent* event) {
                                                ShenzhenMacDelegate* strongSelf = weakSelf;
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
        [self goToPage:_pageIndex - 1 preserveSinglePagePosition:!_presentationMode && _viewMode == SPDFViewModeSingle];
}

- (void)nextPage:(id)sender {
    (void)sender;
    if (_doc && _pageIndex + 1 < spdf_page_count(_doc))
        [self goToPage:_pageIndex + 1 preserveSinglePagePosition:!_presentationMode && _viewMode == SPDFViewModeSingle];
}

- (void)firstPage:(id)sender {
    (void)sender;
    if (_doc) [self goToPage:0 preserveSinglePagePosition:!_presentationMode && _viewMode == SPDFViewModeSingle];
}

- (void)lastPage:(id)sender {
    (void)sender;
    if (_doc)
        [self goToPage:spdf_page_count(_doc) - 1
            preserveSinglePagePosition:!_presentationMode && _viewMode == SPDFViewModeSingle];
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
    NSInteger selectedTag = _fitModePopup.selectedItem.tag;
    SPDFFitMode selected = (SPDFFitMode)MAX(0, MIN(4, selectedTag));
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

- (NSRect)presentationScreenFrame {
    NSScreen* screen = _window.screen ?: NSScreen.mainScreen;
    return screen ? screen.frame : _window.frame;
}

- (void)enterPresentationWindowChrome {
    if (_presentationUsingBorderlessWindow || !_window) return;
    if ([self windowIsFullScreen]) {
        [_window makeKeyAndOrderFront:nil];
        [_window makeMainWindow];
        [NSApp activateIgnoringOtherApps:YES];
        return;
    }

    _presentationPreviousWindowFrame = _window.frame;
    _presentationPreviousWindowStyleMask = _window.styleMask;
    _presentationPreviousWindowLevel = _window.level;
    _presentationPreviousCollectionBehavior = _window.collectionBehavior;
    _presentationPreviousTitleVisibility = _window.titleVisibility;
    _presentationPreviousTitlebarAppearsTransparent = _window.titlebarAppearsTransparent;
    _presentationPreviousMovable = _window.movable;
    _presentationPreviousMovableByWindowBackground = _window.movableByWindowBackground;
    _presentationPreviousHasShadow = _window.hasShadow;

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
      context.duration = 0.0;
      _window.styleMask = NSWindowStyleMaskBorderless;
      _window.titleVisibility = NSWindowTitleHidden;
      _window.titlebarAppearsTransparent = YES;
      _window.movable = NO;
      _window.movableByWindowBackground = NO;
      _window.hasShadow = NO;
      _window.level = NSPopUpMenuWindowLevel;
      _window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                   NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorStationary;
      [_window setFrame:[self presentationScreenFrame] display:YES animate:NO];
    }];
    [_window makeKeyAndOrderFront:nil];
    [_window makeMainWindow];
    [NSApp activateIgnoringOtherApps:YES];
    _presentationUsingBorderlessWindow = YES;
}

- (void)restorePresentationWindowChrome {
    if (!_presentationUsingBorderlessWindow || !_window) return;

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
      context.duration = 0.0;
      _window.level = _presentationPreviousWindowLevel;
      _window.collectionBehavior = _presentationPreviousCollectionBehavior;
      _window.styleMask = _presentationPreviousWindowStyleMask;
      _window.titleVisibility = _presentationPreviousTitleVisibility;
      _window.titlebarAppearsTransparent = _presentationPreviousTitlebarAppearsTransparent;
      _window.movable = _presentationPreviousMovable;
      _window.movableByWindowBackground = _presentationPreviousMovableByWindowBackground;
      _window.hasShadow = _presentationPreviousHasShadow;
      [_window setFrame:_presentationPreviousWindowFrame display:YES animate:NO];
    }];
    _presentationUsingBorderlessWindow = NO;
    [_window makeKeyAndOrderFront:nil];
    [_window makeMainWindow];
}

- (void)installPresentationEventMonitor {
    if (_presentationEventMonitor) return;
    __weak ShenzhenMacDelegate* weakSelf = self;
    NSEventMask mask = NSEventMaskKeyDown;
    if (!_presentationEventMonitor) {
        _presentationEventMonitor = [NSEvent
            addLocalMonitorForEventsMatchingMask:mask
                                         handler:^NSEvent*(NSEvent* event) {
                                           ShenzhenMacDelegate* strongSelf = weakSelf;
                                           if (!strongSelf || !strongSelf->_presentationMode || !strongSelf->_doc)
                                               return event;
                                           if (event.window && event.window != strongSelf->_window) return event;

                                           if ([strongSelf handlePresentationEvent:event]) return nil;

                                           return event;
                                         }];
    }
}

- (void)removePresentationEventMonitor {
    if (_presentationEventMonitor) {
        [NSEvent removeMonitor:_presentationEventMonitor];
        _presentationEventMonitor = nil;
    }
    if (_presentationGlobalEventMonitor) {
        [NSEvent removeMonitor:_presentationGlobalEventMonitor];
        _presentationGlobalEventMonitor = nil;
    }
}

- (void)applyPresentationChrome {
    BOOL presentation = _presentationMode;
    [self dismissTabHoverPanel];
    _tabStrip.hidden = presentation;
    _toolbar.hidden = presentation;
    _tabStripHeightConstraint.constant = presentation ? 0.0 : kTabStripHeight;
    _toolbarHeightConstraint.constant = presentation ? 0.0 : 42.0;
    _pageView.presentationMode = presentation;
    if (presentation) {
        _pageScrollView.hasVerticalScroller = NO;
        _pageScrollView.verticalScroller = nil;
        if (!_presentationOverlayView) {
            _presentationOverlayView = [[SPDFPresentationOverlayView alloc] initWithFrame:_window.contentView.bounds];
            _presentationOverlayView.reader = self;
            _presentationOverlayView.translatesAutoresizingMaskIntoConstraints = NO;
            _presentationOverlayView.wantsLayer = YES;
            _presentationOverlayView.layer.backgroundColor = NSColor.clearColor.CGColor;
            [_window.contentView addSubview:_presentationOverlayView positioned:NSWindowAbove relativeTo:nil];
            [NSLayoutConstraint activateConstraints:@[
                [_presentationOverlayView.leadingAnchor constraintEqualToAnchor:_window.contentView.leadingAnchor],
                [_presentationOverlayView.trailingAnchor constraintEqualToAnchor:_window.contentView.trailingAnchor],
                [_presentationOverlayView.topAnchor constraintEqualToAnchor:_window.contentView.topAnchor],
                [_presentationOverlayView.bottomAnchor constraintEqualToAnchor:_window.contentView.bottomAnchor],
            ]];
        }
        _presentationOverlayView.hidden = NO;
    } else {
        _pageScrollView.verticalScroller = _markerScroller;
        _pageScrollView.hasVerticalScroller = YES;
        _markerScroller.hidden = NO;
        [_presentationOverlayView removeFromSuperview];
        _presentationOverlayView = nil;
    }
    _pageScrollView.autohidesScrollers = presentation;
    _pageScrollView.backgroundColor = presentation ? NSColor.blackColor : NSColor.windowBackgroundColor;
    _pageScrollView.contentView.backgroundColor = presentation ? NSColor.blackColor : NSColor.windowBackgroundColor;
    [_window.contentView layoutSubtreeIfNeeded];
    if (presentation && _presentationOverlayView) [_window makeFirstResponder:_presentationOverlayView];
}

- (void)enterPresentationMode:(id)sender {
    if (!_doc || _presentationMode) return;

    _presentationPreviousViewMode = _viewMode;
    _presentationPreviousFitMode = _fitMode;
    _presentationPreviousSidebarPreferredVisible = _sidebarPreferredVisible;
    _presentationPreviousMinimapPreferredVisible = _minimapPreferredVisible;
    _presentationEnteredFullScreen = NO;
    _presentationMode = YES;
    _lastPresentationEventTimestamp = 0;
    _lastPresentationEventType = (NSEventType)0;
    _lastPresentationEventKeyCode = -1;
    _lastPresentationEventButtonNumber = -1;

    [self enterPresentationWindowChrome];
    _sidebarPreferredVisible = NO;
    _minimapPreferredVisible = NO;
    _viewMode = SPDFViewModeSingle;
    _fitMode = SPDFFitModePage;
    _pageView.viewMode = _viewMode;
    _pageView.currentPageIndex = _pageIndex;
    [self applyPresentationChrome];
    [self rebuildSidebar];
    [self setMinimapActuallyVisible:NO];
    [self installPresentationEventMonitor];
    [NSApp activateIgnoringOtherApps:YES];
    [_window orderFrontRegardless];
    [_window makeKeyWindow];
    [_window makeMainWindow];
    [_window makeFirstResponder:_presentationOverlayView ?: _pageView];
    [self renderDocumentAndScrollToPage:_pageIndex alignTop:YES];
}

- (void)leavePresentationModeAndExitFullScreen:(BOOL)exitFullScreen sender:(id)sender {
    if (!_presentationMode) return;

    BOOL shouldExitFullScreen = exitFullScreen && _presentationEnteredFullScreen && [self windowIsFullScreen];
    _presentationMode = NO;
    _presentationEnteredFullScreen = NO;
    [self removePresentationEventMonitor];
    _sidebarPreferredVisible = _presentationPreviousSidebarPreferredVisible;
    _minimapPreferredVisible = _presentationPreviousMinimapPreferredVisible;
    _viewMode = _presentationPreviousViewMode;
    _fitMode = _presentationPreviousFitMode;
    _pageView.viewMode = _viewMode;
    _pageView.currentPageIndex = _pageIndex;
    [self applyPresentationChrome];
    [self restorePresentationWindowChrome];
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
    if (_presentationMode)
        [self leavePresentationModeAndExitFullScreen:YES sender:sender];
    else
        [_window toggleFullScreen:sender];
}

- (void)performWindowArrangementAction:(SEL)action sender:(id)sender {
    if (action == @selector(fillWindow:))
        [self fillWindow:sender];
    else if (action == @selector(centerWindowInScreen:))
        [self centerWindowInScreen:sender];
    else if (action == @selector(moveWindowToLeftHalf:))
        [self moveWindowToLeftHalf:sender];
    else if (action == @selector(moveWindowToRightHalf:))
        [self moveWindowToRightHalf:sender];
    else if (action == @selector(moveWindowToTopHalf:))
        [self moveWindowToTopHalf:sender];
    else if (action == @selector(moveWindowToBottomHalf:))
        [self moveWindowToBottomHalf:sender];
}

- (void)drainPendingWindowArrangementAction {
    if (_pendingWindowArrangementAction == NULL || [self windowIsFullScreen]) return;
    SEL action = _pendingWindowArrangementAction;
    _pendingWindowArrangementAction = NULL;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!self->_window || self->_presentationMode || [self windowIsFullScreen]) return;
      [self performWindowArrangementAction:action sender:nil];
    });
}

- (BOOL)deferWindowArrangementActionIfNeeded:(SEL)action sender:(id)sender {
    if (!_window || _presentationMode) return YES;
    if (![self windowIsFullScreen]) return NO;

    BOOL alreadyWaitingForExit = _pendingWindowArrangementAction != NULL;
    _pendingWindowArrangementAction = action;
    if (!alreadyWaitingForExit) [_window toggleFullScreen:sender];
    return YES;
}

- (BOOL)handleWindowArrangementShortcutEvent:(NSEvent*)event {
    if (!_window || _presentationMode || ![self windowIsFullScreen]) return NO;
    if (event.type != NSEventTypeKeyDown) return NO;

    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    NSEventModifierFlags required = NSEventModifierFlagControl | NSEventModifierFlagFunction;
    if ((flags & required) != required) return NO;
    if (flags & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagShift)) return NO;

    SEL action = NULL;
    NSString* characters = event.charactersIgnoringModifiers ?: event.characters ?: @"";
    if (characters.length > 0) {
        unichar key = [characters characterAtIndex:0];
        if (key == 'f' || key == 'F')
            action = @selector(fillWindow:);
        else if (key == 'c' || key == 'C')
            action = @selector(centerWindowInScreen:);
        else if (key == NSLeftArrowFunctionKey)
            action = @selector(moveWindowToLeftHalf:);
        else if (key == NSRightArrowFunctionKey)
            action = @selector(moveWindowToRightHalf:);
        else if (key == NSUpArrowFunctionKey)
            action = @selector(moveWindowToTopHalf:);
        else if (key == NSDownArrowFunctionKey)
            action = @selector(moveWindowToBottomHalf:);
    }

    if (action == NULL) {
        if (event.keyCode == 123)
            action = @selector(moveWindowToLeftHalf:);
        else if (event.keyCode == 124)
            action = @selector(moveWindowToRightHalf:);
        else if (event.keyCode == 126)
            action = @selector(moveWindowToTopHalf:);
        else if (event.keyCode == 125)
            action = @selector(moveWindowToBottomHalf:);
    }

    if (action == NULL) return NO;
    [self performWindowArrangementAction:action sender:nil];
    return YES;
}

- (NSRect)visibleFrameForWindowActions {
    NSScreen* screen = _window.screen ?: NSScreen.mainScreen;
    return screen ? screen.visibleFrame : NSMakeRect(0, 0, 1120, 800);
}

- (void)setWindowFrameForWindowAction:(NSRect)frame {
    if (!_window || _presentationMode || [self windowIsFullScreen]) return;
    [_window setFrame:frame display:YES animate:YES];
    [self savePersistentState];
}

- (void)fillWindow:(id)sender {
    if ([self deferWindowArrangementActionIfNeeded:_cmd sender:sender]) return;
    [self setWindowFrameForWindowAction:[self visibleFrameForWindowActions]];
}

- (void)centerWindowInScreen:(id)sender {
    if ([self deferWindowArrangementActionIfNeeded:_cmd sender:sender]) return;
    NSRect visible = [self visibleFrameForWindowActions];
    NSRect frame = _window.frame;
    frame.size.width = MIN(NSWidth(frame), NSWidth(visible));
    frame.size.height = MIN(NSHeight(frame), NSHeight(visible));
    frame.origin.x = floor(NSMidX(visible) - NSWidth(frame) * 0.5);
    frame.origin.y = floor(NSMidY(visible) - NSHeight(frame) * 0.5);
    [self setWindowFrameForWindowAction:frame];
}

- (void)moveWindowToLeftHalf:(id)sender {
    if ([self deferWindowArrangementActionIfNeeded:_cmd sender:sender]) return;
    NSRect visible = [self visibleFrameForWindowActions];
    [self setWindowFrameForWindowAction:NSMakeRect(NSMinX(visible), NSMinY(visible), floor(NSWidth(visible) * 0.5),
                                                   NSHeight(visible))];
}

- (void)moveWindowToRightHalf:(id)sender {
    if ([self deferWindowArrangementActionIfNeeded:_cmd sender:sender]) return;
    NSRect visible = [self visibleFrameForWindowActions];
    CGFloat width = floor(NSWidth(visible) * 0.5);
    [self setWindowFrameForWindowAction:NSMakeRect(NSMaxX(visible) - width, NSMinY(visible), width, NSHeight(visible))];
}

- (void)moveWindowToTopHalf:(id)sender {
    if ([self deferWindowArrangementActionIfNeeded:_cmd sender:sender]) return;
    NSRect visible = [self visibleFrameForWindowActions];
    CGFloat height = floor(NSHeight(visible) * 0.5);
    [self
        setWindowFrameForWindowAction:NSMakeRect(NSMinX(visible), NSMaxY(visible) - height, NSWidth(visible), height)];
}

- (void)moveWindowToBottomHalf:(id)sender {
    if ([self deferWindowArrangementActionIfNeeded:_cmd sender:sender]) return;
    NSRect visible = [self visibleFrameForWindowActions];
    CGFloat height = floor(NSHeight(visible) * 0.5);
    [self setWindowFrameForWindowAction:NSMakeRect(NSMinX(visible), NSMinY(visible), NSWidth(visible), height)];
}

- (NSString*)ocrToolPath {
    return [self executablePathForTool:@"ocrmypdf"
                            candidates:@[
                                @"/opt/homebrew/bin/ocrmypdf", @"/usr/local/bin/ocrmypdf", @"/opt/local/bin/ocrmypdf",
                                @"/usr/bin/ocrmypdf"
                            ]];
}

- (NSString*)tesseractToolPath {
    return [self executablePathForTool:@"tesseract"
                            candidates:@[
                                @"/opt/homebrew/bin/tesseract", @"/usr/local/bin/tesseract",
                                @"/opt/local/bin/tesseract", @"/usr/bin/tesseract"
                            ]];
}

- (NSString*)argosToolPath {
    NSString* userPath = [NSHomeDirectory() stringByAppendingPathComponent:@".local/bin/argos-translate"];
    return [self
        executablePathForTool:@"argos-translate"
                   candidates:@[ @"/opt/homebrew/bin/argos-translate", @"/usr/local/bin/argos-translate", userPath ]];
}

- (NSString*)argospmToolPath {
    NSString* userPath = [NSHomeDirectory() stringByAppendingPathComponent:@".local/bin/argospm"];
    return [self executablePathForTool:@"argospm"
                            candidates:@[ @"/opt/homebrew/bin/argospm", @"/usr/local/bin/argospm", userPath ]];
}

- (NSString*)executablePathForTool:(NSString*)tool candidates:(NSArray<NSString*>*)candidates {
    NSFileManager* fm = NSFileManager.defaultManager;
    NSString* userPath =
        [[NSHomeDirectory() stringByAppendingPathComponent:@".local/bin"] stringByAppendingPathComponent:tool];
    NSMutableArray<NSString*>* allCandidates = [candidates mutableCopy] ?: [NSMutableArray array];
    [allCandidates addObject:userPath];
    for (NSString* path in allCandidates) {
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

- (NSDictionary<NSString*, NSString*>*)taskEnvironmentWithToolPaths:(NSArray<NSString*>*)toolPaths {
    NSMutableDictionary<NSString*, NSString*>* env = [NSProcessInfo.processInfo.environment mutableCopy];
    NSMutableArray<NSString*>* dirs = [NSMutableArray array];
    void (^addDir)(NSString*) = ^(NSString* dir) {
      if (!dir.length) return;
      if (![dirs containsObject:dir]) [dirs addObject:dir];
    };

    for (NSString* toolPath in toolPaths) addDir(toolPath.stringByDeletingLastPathComponent);
    addDir([NSHomeDirectory() stringByAppendingPathComponent:@".local/bin"]);
    addDir(@"/opt/homebrew/bin");
    addDir(@"/opt/homebrew/sbin");
    addDir(@"/usr/local/bin");
    addDir(@"/usr/local/sbin");
    addDir(@"/opt/local/bin");
    addDir(@"/usr/bin");
    addDir(@"/bin");
    addDir(@"/usr/sbin");
    addDir(@"/sbin");

    for (NSString* dir in [env[@"PATH"] componentsSeparatedByString:@":"]) addDir(dir);
    env[@"PATH"] = [dirs componentsJoinedByString:@":"];
    return env;
}

- (NSString*)argosInstallScript {
    return @"set -e\n"
           @"export "
           @"PATH=\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/"
           @"bin:/usr/sbin:/sbin:$PATH\"\n"
           @"echo 'Checking for Argos Translate...'\n"
           @"if command -v argos-translate >/dev/null 2>&1 && command -v argospm >/dev/null 2>&1; then "
           @"echo 'Argos Translate is already installed.'; exit 0; fi\n"
           @"if command -v pipx >/dev/null 2>&1; then PIPX=$(command -v pipx); "
           @"elif command -v brew >/dev/null 2>&1; then echo 'Installing pipx with Homebrew...'; brew install pipx; "
           @"PIPX=$(command -v pipx); "
           @"else PIPX=\"\"; fi\n"
           @"if [ -n \"$PIPX\" ]; then echo 'Installing or upgrading argostranslate with pipx...'; "
           @"\"$PIPX\" install --include-deps argostranslate || \"$PIPX\" upgrade argostranslate; "
           @"elif command -v python3 >/dev/null 2>&1; then echo 'Installing argostranslate with pip...'; python3 -m "
           @"pip "
           @"install --user --upgrade argostranslate; "
           @"else echo 'Python 3, pipx, or Homebrew is required to install Argos "
           @"Translate.'; exit 1; fi\n"
           @"command -v argos-translate >/dev/null 2>&1\n"
           @"command -v argospm >/dev/null 2>&1\n"
           @"echo 'Argos Translate installed.'\n";
}

- (void)showTranslationProgressWithTitle:(NSString*)title totalUnits:(double)totalUnits {
    if (!_translationProgressPanel) {
        _translationProgressPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 460, 156)
                                                               styleMask:NSWindowStyleMaskTitled
                                                                 backing:NSBackingStoreBuffered
                                                                   defer:NO];
        _translationProgressPanel.releasedWhenClosed = NO;

        NSView* content = [[NSView alloc] initWithFrame:_translationProgressPanel.contentView.bounds];
        content.translatesAutoresizingMaskIntoConstraints = NO;
        _translationProgressPanel.contentView = content;

        _translationProgressTitleLabel = [NSTextField labelWithString:@""];
        _translationProgressTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _translationProgressTitleLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
        [content addSubview:_translationProgressTitleLabel];

        _translationProgressDetailLabel = [NSTextField labelWithString:@""];
        _translationProgressDetailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _translationProgressDetailLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [content addSubview:_translationProgressDetailLabel];

        _translationProgressIndicator = [[NSProgressIndicator alloc] init];
        _translationProgressIndicator.translatesAutoresizingMaskIntoConstraints = NO;
        _translationProgressIndicator.style = NSProgressIndicatorStyleBar;
        _translationProgressIndicator.indeterminate = NO;
        _translationProgressIndicator.minValue = 0.0;
        [content addSubview:_translationProgressIndicator];

        _translationProgressCancelButton = [NSButton buttonWithTitle:@"Cancel"
                                                              target:self
                                                              action:@selector(cancelTranslation:)];
        _translationProgressCancelButton.translatesAutoresizingMaskIntoConstraints = NO;
        [content addSubview:_translationProgressCancelButton];

        [NSLayoutConstraint activateConstraints:@[
            [_translationProgressTitleLabel.topAnchor constraintEqualToAnchor:content.topAnchor constant:16],
            [_translationProgressTitleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:18],
            [_translationProgressTitleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-18],
            [_translationProgressDetailLabel.topAnchor
                constraintEqualToAnchor:_translationProgressTitleLabel.bottomAnchor
                               constant:8],
            [_translationProgressDetailLabel.leadingAnchor
                constraintEqualToAnchor:_translationProgressTitleLabel.leadingAnchor],
            [_translationProgressDetailLabel.trailingAnchor
                constraintEqualToAnchor:_translationProgressTitleLabel.trailingAnchor],
            [_translationProgressIndicator.topAnchor
                constraintEqualToAnchor:_translationProgressDetailLabel.bottomAnchor
                               constant:14],
            [_translationProgressIndicator.leadingAnchor
                constraintEqualToAnchor:_translationProgressTitleLabel.leadingAnchor],
            [_translationProgressIndicator.trailingAnchor
                constraintEqualToAnchor:_translationProgressTitleLabel.trailingAnchor],
            [_translationProgressCancelButton.topAnchor
                constraintEqualToAnchor:_translationProgressIndicator.bottomAnchor
                               constant:16],
            [_translationProgressCancelButton.trailingAnchor
                constraintEqualToAnchor:_translationProgressTitleLabel.trailingAnchor]
        ]];
    }

    _translationProgressPanel.title = @"Translating";
    _translationProgressTitleLabel.stringValue = title.length ? title : @"Translating with Argos";
    _translationProgressDetailLabel.stringValue = @"Preparing text...";
    _translationProgressIndicator.indeterminate = totalUnits <= 0.0;
    _translationProgressIndicator.minValue = 0.0;
    _translationProgressIndicator.maxValue = MAX(1.0, totalUnits);
    _translationProgressIndicator.doubleValue = 0.0;
    _translationProgressCancelButton.enabled = YES;
    if (_translationProgressIndicator.indeterminate)
        [_translationProgressIndicator startAnimation:nil];
    else
        [_translationProgressIndicator stopAnimation:nil];
    [_translationProgressPanel center];
    [_translationProgressPanel makeKeyAndOrderFront:nil];
}

- (void)updateTranslationProgress:(double)value detail:(NSString*)detail {
    if (!_translationProgressPanel) return;
    if (!_translationProgressIndicator.indeterminate)
        _translationProgressIndicator.doubleValue =
            spdf_clamp_cg(value, _translationProgressIndicator.minValue, _translationProgressIndicator.maxValue);
    if (detail.length) {
        _translationProgressDetailLabel.stringValue = detail;
        _statusLabel.stringValue = detail;
    }
}

- (void)finishTranslationProgressWithDetail:(NSString*)detail keepVisible:(BOOL)keepVisible {
    @synchronized(self) {
        _translationTask = nil;
    }
    [_translationProgressIndicator stopAnimation:nil];
    _translationProgressCancelButton.enabled = NO;
    if (detail.length) _translationProgressDetailLabel.stringValue = detail;
    if (!keepVisible) [_translationProgressPanel orderOut:nil];
}

- (void)cancelTranslation:(id)sender {
    (void)sender;
    _translationCancelRequested = YES;
    _translationProgressCancelButton.enabled = NO;
    _translationProgressDetailLabel.stringValue = @"Canceling translation...";
    _statusLabel.stringValue = @"Canceling translation...";
    @synchronized(self) {
        [_translationTask terminate];
    }
}

static NSString* SPDFLastMeaningfulOCRLine(NSString* text) {
    if (!text.length) return @"";
    NSArray<NSString*>* lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    for (NSString* line in lines.reverseObjectEnumerator) {
        NSString* trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length > 0) return trimmed;
    }
    return @"";
}

static NSString* SPDFHumanReadableOCRFailure(NSString* detail) {
    if (!detail.length) return @"OCRmyPDF exited with an error.";
    if ([detail rangeOfString:@"--redo-ocr"].location != NSNotFound &&
        [detail rangeOfString:@"not compatible"].location != NSNotFound) {
        return @"OCRmyPDF could not redo OCR on this PDF.\n\n"
               @"This document already contains selectable text, and this OCRmyPDF version cannot combine redo OCR "
               @"with cleanup operations for it. OCR is probably not needed for text-only or vector-text PDFs.";
    }
    if ([detail rangeOfString:@"Traceback"].location != NSNotFound) {
        return @"OCRmyPDF crashed while processing this PDF.\n\n"
               @"This looks like an OCRmyPDF compatibility error rather than a Shenzhen PDF error. Try updating "
               @"OCRmyPDF and Tesseract, or run OCRmyPDF from Terminal for the full traceback.";
    }
    return detail;
}

- (void)showOCRProgressWithDetail:(NSString*)detail {
    if (!_ocrProgressPanel) {
        _ocrProgressPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 460, 132)
                                                       styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        _ocrProgressPanel.releasedWhenClosed = NO;

        NSView* content = [[NSView alloc] initWithFrame:_ocrProgressPanel.contentView.bounds];
        content.translatesAutoresizingMaskIntoConstraints = NO;
        _ocrProgressPanel.contentView = content;

        _ocrProgressTitleLabel = [NSTextField labelWithString:@""];
        _ocrProgressTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _ocrProgressTitleLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
        [content addSubview:_ocrProgressTitleLabel];

        _ocrProgressDetailLabel = [NSTextField labelWithString:@""];
        _ocrProgressDetailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _ocrProgressDetailLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [content addSubview:_ocrProgressDetailLabel];

        _ocrProgressIndicator = [[NSProgressIndicator alloc] init];
        _ocrProgressIndicator.translatesAutoresizingMaskIntoConstraints = NO;
        _ocrProgressIndicator.style = NSProgressIndicatorStyleBar;
        _ocrProgressIndicator.indeterminate = YES;
        [content addSubview:_ocrProgressIndicator];

        [NSLayoutConstraint activateConstraints:@[
            [_ocrProgressTitleLabel.topAnchor constraintEqualToAnchor:content.topAnchor constant:16],
            [_ocrProgressTitleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:18],
            [_ocrProgressTitleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-18],
            [_ocrProgressDetailLabel.topAnchor constraintEqualToAnchor:_ocrProgressTitleLabel.bottomAnchor constant:8],
            [_ocrProgressDetailLabel.leadingAnchor constraintEqualToAnchor:_ocrProgressTitleLabel.leadingAnchor],
            [_ocrProgressDetailLabel.trailingAnchor constraintEqualToAnchor:_ocrProgressTitleLabel.trailingAnchor],
            [_ocrProgressIndicator.topAnchor constraintEqualToAnchor:_ocrProgressDetailLabel.bottomAnchor constant:14],
            [_ocrProgressIndicator.leadingAnchor constraintEqualToAnchor:_ocrProgressTitleLabel.leadingAnchor],
            [_ocrProgressIndicator.trailingAnchor constraintEqualToAnchor:_ocrProgressTitleLabel.trailingAnchor]
        ]];
    }

    _ocrProgressPanel.title = @"OCR";
    _ocrProgressTitleLabel.stringValue = @"Running OCR";
    _ocrProgressDetailLabel.stringValue = detail.length ? detail : @"Preparing OCR...";
    [_ocrProgressIndicator startAnimation:nil];
    [_ocrProgressPanel center];
    [_ocrProgressPanel makeKeyAndOrderFront:nil];
}

- (void)updateOCRProgressDetail:(NSString*)detail {
    if (!_ocrProgressPanel || !detail.length) return;
    _ocrProgressDetailLabel.stringValue = detail;
    _statusLabel.stringValue = detail;
}

- (void)finishOCRProgressWithDetail:(NSString*)detail {
    [_ocrProgressIndicator stopAnimation:nil];
    if (detail.length) _ocrProgressDetailLabel.stringValue = detail;
    [_ocrProgressPanel orderOut:nil];
}

- (void)appendTranslationInstallLog:(NSString*)text {
    if (!_translationInstallLog || text.length == 0) return;
    NSTextStorage* storage = _translationInstallLog.textStorage;
    NSDictionary* attrs = @{
        NSForegroundColorAttributeName : NSColor.labelColor,
        NSFontAttributeName : _translationInstallLog.font
            ?: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]
    };
    [storage appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:attrs]];
    [_translationInstallLog scrollRangeToVisible:NSMakeRange(storage.length, 0)];
}

- (void)showTranslationInstallPanelWithTitle:(NSString*)title heading:(NSString*)heading {
    if (!_translationInstallPanel) {
        _translationInstallPanel =
            [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 640, 360)
                                       styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                         backing:NSBackingStoreBuffered
                                           defer:NO];
        _translationInstallPanel.releasedWhenClosed = NO;

        NSView* content = [[NSView alloc] initWithFrame:_translationInstallPanel.contentView.bounds];
        content.translatesAutoresizingMaskIntoConstraints = NO;
        _translationInstallPanel.contentView = content;

        _translationInstallTitleLabel = [NSTextField labelWithString:@""];
        _translationInstallTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _translationInstallTitleLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
        [content addSubview:_translationInstallTitleLabel];

        _translationInstallProgress = [[NSProgressIndicator alloc] init];
        _translationInstallProgress.translatesAutoresizingMaskIntoConstraints = NO;
        _translationInstallProgress.indeterminate = YES;
        _translationInstallProgress.style = NSProgressIndicatorStyleBar;
        [content addSubview:_translationInstallProgress];

        NSScrollView* scroll = [[NSScrollView alloc] init];
        scroll.translatesAutoresizingMaskIntoConstraints = NO;
        scroll.hasVerticalScroller = YES;
        [content addSubview:scroll];

        _translationInstallLog = [[NSTextView alloc] init];
        _translationInstallLog.editable = NO;
        _translationInstallLog.selectable = YES;
        _translationInstallLog.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
        _translationInstallLog.drawsBackground = YES;
        _translationInstallLog.backgroundColor = NSColor.textBackgroundColor;
        _translationInstallLog.textColor = NSColor.labelColor;
        scroll.documentView = _translationInstallLog;

        [NSLayoutConstraint activateConstraints:@[
            [_translationInstallTitleLabel.topAnchor constraintEqualToAnchor:content.topAnchor constant:14],
            [_translationInstallTitleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
            [_translationInstallTitleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
            [_translationInstallProgress.topAnchor constraintEqualToAnchor:_translationInstallTitleLabel.bottomAnchor
                                                                  constant:10],
            [_translationInstallProgress.leadingAnchor
                constraintEqualToAnchor:_translationInstallTitleLabel.leadingAnchor],
            [_translationInstallProgress.trailingAnchor
                constraintEqualToAnchor:_translationInstallTitleLabel.trailingAnchor],
            [scroll.topAnchor constraintEqualToAnchor:_translationInstallProgress.bottomAnchor constant:12],
            [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
            [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
            [scroll.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-14]
        ]];
    }

    _translationInstallPanel.title = title.length ? title : @"Installing Translation Support";
    _translationInstallTitleLabel.stringValue = heading.length ? heading : @"Installing Argos Translate";
    [_translationInstallPanel center];
    [_translationInstallPanel makeKeyAndOrderFront:nil];
    [_translationInstallProgress startAnimation:nil];
}

- (void)runTranslationInstallTask:(NSTask*)task
                            title:(NSString*)title
                          heading:(NSString*)heading
                       initialLog:(NSString*)initialLog
                       completion:(void (^)(NSTask* finishedTask, NSString* output))completion {
    if (_translationInstallRunning) {
        [_translationInstallPanel makeKeyAndOrderFront:nil];
        return;
    }

    _translationInstallRunning = YES;
    _translateButton.enabled = NO;
    _statusLabel.stringValue = title.length ? title : @"Installing translation support...";
    [self showTranslationInstallPanelWithTitle:title heading:heading];
    _translationInstallLog.string = @"";
    [self appendTranslationInstallLog:initialLog.length ? initialLog : @"Preparing translation installer...\n"];

    NSPipe* pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    _translationInstallTask = task;
    __block NSMutableData* outputData = [NSMutableData data];
    void (^completionCopy)(NSTask*, NSString*) = [completion copy];
    __weak ShenzhenMacDelegate* weakSelf = self;

    pipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle* handle) {
      NSData* chunk = handle.availableData;
      if (chunk.length == 0) {
          handle.readabilityHandler = nil;
          return;
      }
      @synchronized(outputData) {
          [outputData appendData:chunk];
      }
      NSString* text = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding] ?: @"";
      dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf appendTranslationInstallLog:text];
      });
    };

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
        ShenzhenMacDelegate* strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_translationInstallRunning = NO;
        strongSelf->_translationInstallTask = nil;
        [strongSelf->_translationInstallProgress stopAnimation:nil];
        strongSelf->_translateButton.enabled = strongSelf->_doc != NULL && !strongSelf->_translationRunning;
        if (completionCopy) completionCopy(finishedTask, output);
      });
    };

    NSError* launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        _translationInstallRunning = NO;
        _translationInstallTask = nil;
        [_translationInstallProgress stopAnimation:nil];
        _translateButton.enabled = _doc != NULL && !_translationRunning;
        NSString* detail = launchError.localizedDescription ?: @"Could not start installer.";
        [self appendTranslationInstallLog:[NSString stringWithFormat:@"\n%@\n", detail]];
        _statusLabel.stringValue = @"Translation installer could not start.";
    }
}

- (void)runArgosPackageInstallFromLanguage:(NSString*)sourceLanguage
                                toLanguage:(NSString*)targetLanguage
                                sourceText:(NSString*)sourceText
                                outputPath:(NSString*)outputPath {
    NSString* packageTool = [self argospmToolPath];
    if (!packageTool.length) {
        [self showError:@"Argos package manager not found"
                 detail:@"Install Argos Translate and the required offline "
                        @"language package, then try again."];
        return;
    }

    NSString* packageName = [NSString stringWithFormat:@"translate-%@_%@", sourceLanguage, targetLanguage];
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Install Argos language package?";
    alert.informativeText = [NSString stringWithFormat:@"The offline %@ to %@ package may be "
                                                       @"missing. Shenzhen PDF can ask argospm to "
                                                       @"install %@, then continue translation.",
                                                       sourceLanguage, targetLanguage, packageName];
    [alert addButtonWithTitle:@"Install"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleInformational;
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:packageTool];
    task.arguments = @[ @"install", packageName ];

    __weak ShenzhenMacDelegate* weakSelf = self;
    [self runTranslationInstallTask:task
                              title:@"Installing Translation Package"
                            heading:[NSString stringWithFormat:@"Installing %@", packageName]
                         initialLog:[NSString stringWithFormat:@"Running argospm install %@...\n", packageName]
                         completion:^(NSTask* finishedTask, NSString* output) {
                           ShenzhenMacDelegate* strongSelf = weakSelf;
                           if (!strongSelf) return;
                           strongSelf->_translationInstallRunning = NO;
                           strongSelf->_translateButton.enabled =
                               strongSelf->_doc != NULL && !strongSelf->_translationRunning;
                           if (finishedTask.terminationStatus == 0) {
                               [strongSelf appendTranslationInstallLog:@"\nArgos language package installed.\n"];
                               [strongSelf->_translationInstallPanel orderOut:nil];
                               [strongSelf runArgosTranslationWithTool:[strongSelf argosToolPath]
                                                            sourceText:sourceText
                                                        sourceLanguage:sourceLanguage
                                                        targetLanguage:targetLanguage
                                                            outputPath:outputPath
                                                      offeredInstaller:YES];
                           } else {
                               (void)output;
                               [strongSelf appendTranslationInstallLog:
                                               @"\nArgos language package installation failed. The log above can be "
                                               @"selected and copied.\n"];
                               strongSelf->_statusLabel.stringValue = @"Translation package installation failed.";
                           }
                         }];
}

static BOOL SPDFIsArgosDiagnosticLine(NSString* line, BOOL previousLineWasDiagnostic) {
    NSString* trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([trimmed rangeOfString:@"WARNING: Language "].location != NSNotFound &&
        [trimmed rangeOfString:@" package "].location != NSNotFound &&
        [trimmed rangeOfString:@" expects "].location != NSNotFound) {
        return YES;
    }
    if (previousLineWasDiagnostic &&
        ([trimmed isEqualToString:@"added"] || [trimmed hasPrefix:@"which has been added"])) {
        return YES;
    }
    return NO;
}

static NSString* SPDFStringByRemovingArgosDiagnostics(NSString* output) {
    if (!output.length) return output ?: @"";
    NSArray<NSString*>* lines = [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSMutableArray<NSString*>* kept = [NSMutableArray arrayWithCapacity:lines.count];
    BOOL previousLineWasDiagnostic = NO;
    BOOL removedAny = NO;
    for (NSString* line in lines) {
        BOOL diagnostic = SPDFIsArgosDiagnosticLine(line, previousLineWasDiagnostic);
        if (diagnostic) {
            previousLineWasDiagnostic = YES;
            removedAny = YES;
            continue;
        }
        previousLineWasDiagnostic = NO;
        [kept addObject:line];
    }
    if (!removedAny) return output;
    return [kept componentsJoinedByString:@"\n"];
}

- (BOOL)runArgosToolSynchronously:(NSString*)tool
                   sourceLanguage:(NSString*)sourceLanguage
                   targetLanguage:(NSString*)targetLanguage
                            input:(NSString*)input
                           output:(NSString**)outputOut
                            error:(NSString**)errorOut {
    if (outputOut) *outputOut = nil;
    if (errorOut) *errorOut = nil;
    if (_translationCancelRequested) {
        if (errorOut) *errorOut = @"Translation canceled.";
        return NO;
    }
    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:tool];
    task.arguments = @[ @"--from-lang", sourceLanguage, @"--to-lang", targetLanguage ];
    NSPipe* inputPipe = [NSPipe pipe];
    NSPipe* outputPipe = [NSPipe pipe];
    NSPipe* errorPipe = [NSPipe pipe];
    task.standardInput = inputPipe;
    task.standardOutput = outputPipe;
    task.standardError = errorPipe;

    NSError* launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        if (errorOut) *errorOut = launchError.localizedDescription ?: @"Could not start Argos Translate.";
        return NO;
    }
    @synchronized(self) {
        _translationTask = task;
    }

    NSData* inputData = [input dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    @try {
        [inputPipe.fileHandleForWriting writeData:inputData];
    } @catch (NSException* exception) {
        (void)exception;
    }
    [inputPipe.fileHandleForWriting closeFile];

    __block NSData* errorData = nil;
    dispatch_group_t readGroup = dispatch_group_create();
    dispatch_group_enter(readGroup);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
      errorData = [errorPipe.fileHandleForReading readDataToEndOfFile];
      dispatch_group_leave(readGroup);
    });
    NSData* outputData = [outputPipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    dispatch_group_wait(readGroup, DISPATCH_TIME_FOREVER);
    @synchronized(self) {
        if (_translationTask == task) _translationTask = nil;
    }
    NSString* output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding] ?: @"";
    NSString* errorOutput = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding] ?: @"";
    if (_translationCancelRequested) {
        if (errorOut) *errorOut = @"Translation canceled.";
        return NO;
    }
    if (task.terminationStatus != 0) {
        NSString* failure = errorOutput.length ? errorOutput : output;
        if (errorOut) *errorOut = failure.length ? failure : @"Argos Translate exited with an error.";
        return NO;
    }
    output = SPDFStringByRemovingArgosDiagnostics(output);
    if (outputOut) *outputOut = output;
    return YES;
}

- (void)runArgosTranslationWithTool:(NSString*)tool
                         sourceText:(NSString*)sourceText
                     sourceLanguage:(NSString*)sourceLanguage
                     targetLanguage:(NSString*)targetLanguage
                         outputPath:(NSString*)outputPath
                   offeredInstaller:(BOOL)offeredInstaller {
    if (!tool.length) {
        [self promptToInstallArgosAndContinueWithSourceText:sourceText
                                             sourceLanguage:sourceLanguage
                                             targetLanguage:targetLanguage
                                                 outputPath:outputPath];
        return;
    }

    _translationRunning = YES;
    _translationCancelRequested = NO;
    _translateButton.enabled = NO;
    _statusLabel.stringValue = @"Translating with Argos...";

    NSArray<NSDictionary*>* items = [_pendingTranslationItems copy] ?: @[];
    NSUInteger totalUnits = MAX((NSUInteger)1, items.count);
    [self showTranslationProgressWithTitle:@"Translating with Argos" totalUnits:(double)totalUnits];
    [self updateTranslationProgress:0.0 detail:@"Preparing translation..."];
    NSArray<NSString*>* sourceLines =
        [sourceText componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    __weak ShenzhenMacDelegate* weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSMutableArray<NSString*>* translatedLines = [NSMutableArray arrayWithCapacity:MAX((NSUInteger)1, items.count)];
      for (NSUInteger i = 0; i < MAX((NSUInteger)1, items.count); ++i) [translatedLines addObject:@""];
      NSString* failure = nil;

      if (items.count <= 1) {
          NSString* translated = nil;
          dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf updateTranslationProgress:0.0 detail:@"Translating selected text..."];
          });
          if (![self runArgosToolSynchronously:tool
                                sourceLanguage:sourceLanguage
                                targetLanguage:targetLanguage
                                         input:sourceText
                                        output:&translated
                                         error:&failure]) {
              translated = nil;
          }
          if (translated) translatedLines[0] = translated;
          if (!failure.length) {
              dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf updateTranslationProgress:1.0 detail:@"Writing translated PDF..."];
              });
          }
      } else {
          NSUInteger start = 0;
          NSUInteger translatedCount = 0;
          while (start < items.count && !failure.length) {
              if (self->_translationCancelRequested) {
                  failure = @"Translation canceled.";
                  break;
              }
              NSInteger page = [items[start][@"page"] integerValue];
              NSUInteger end = start + 1;
              while (end < items.count && [items[end][@"page"] integerValue] == page) end++;
              dispatch_async(dispatch_get_main_queue(), ^{
                NSString* detail =
                    [NSString stringWithFormat:@"Translating page %ld (%lu of %lu text blocks)...", (long)page + 1,
                                               (unsigned long)translatedCount, (unsigned long)items.count];
                [weakSelf updateTranslationProgress:(double)translatedCount detail:detail];
              });

              NSMutableString* pageInput = [NSMutableString string];
              for (NSUInteger i = start; i < end; ++i) {
                  NSString* line = i < sourceLines.count ? sourceLines[i] : @"";
                  [pageInput appendString:line ?: @""];
                  [pageInput appendString:@"\n"];
              }

              NSString* translated = nil;
              if (![self runArgosToolSynchronously:tool
                                    sourceLanguage:sourceLanguage
                                    targetLanguage:targetLanguage
                                             input:pageInput
                                            output:&translated
                                             error:&failure]) {
                  if (failure.length && ![failure isEqualToString:@"Translation canceled."])
                      failure = [NSString stringWithFormat:@"Page %ld: %@", (long)page + 1, failure];
                  break;
              }
              NSArray<NSString*>* pageOutput =
                  [translated componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
              for (NSUInteger i = start; i < end; ++i) {
                  NSUInteger local = i - start;
                  NSString* line = local < pageOutput.count ? pageOutput[local] : @"";
                  translatedLines[i] = line.length ? line : @" ";
              }
              if (pageOutput.count > end - start) {
                  NSMutableString* tail = [translatedLines[end - 1] mutableCopy];
                  for (NSUInteger i = end - start; i < pageOutput.count; ++i) {
                      NSString* extra = pageOutput[i];
                      if (!extra.length) continue;
                      if (tail.length) [tail appendString:@"\n"];
                      [tail appendString:extra];
                  }
                  translatedLines[end - 1] = tail;
              }
              translatedCount = end;
              dispatch_async(dispatch_get_main_queue(), ^{
                NSString* detail =
                    [NSString stringWithFormat:@"Translated page %ld (%lu of %lu text blocks)...", (long)page + 1,
                                               (unsigned long)translatedCount, (unsigned long)items.count];
                [weakSelf updateTranslationProgress:(double)translatedCount detail:detail];
              });
              start = end;
          }
      }

      NSString* output = failure.length ? @"" : [translatedLines componentsJoinedByString:@"\n"];
      dispatch_async(dispatch_get_main_queue(), ^{
        ShenzhenMacDelegate* strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_translationRunning = NO;
        strongSelf->_translateButton.enabled = strongSelf->_doc != NULL && !strongSelf->_translationInstallRunning;
        if (failure.length) {
            [strongSelf finishTranslationProgressWithDetail:failure keepVisible:NO];
            if ([failure isEqualToString:@"Translation canceled."]) {
                strongSelf->_statusLabel.stringValue = @"Translation canceled.";
                return;
            }
            if (!offeredInstaller) {
                [strongSelf runArgosPackageInstallFromLanguage:sourceLanguage
                                                    toLanguage:targetLanguage
                                                    sourceText:sourceText
                                                    outputPath:outputPath];
                return;
            }
            NSString* detail = failure.length > 1200 ? [failure substringToIndex:1200] : failure;
            [strongSelf showError:@"Translation failed" detail:detail.length ? detail : @"Argos exited with an error."];
            strongSelf->_statusLabel.stringValue = @"Translation failed.";
            return;
        }

        NSError* writeError = nil;
        strongSelf->_pendingTranslationItems = items;
        if (![strongSelf writeTranslatedPDFWithText:output
                                         sourcePath:strongSelf->_path
                                         outputPath:outputPath
                                              error:&writeError]) {
            [strongSelf showError:@"Could not save translation" detail:writeError.localizedDescription ?: @""];
            [strongSelf finishTranslationProgressWithDetail:@"Could not save translated PDF." keepVisible:NO];
            strongSelf->_statusLabel.stringValue = @"Translation was not saved.";
            return;
        }

        [strongSelf finishTranslationProgressWithDetail:@"Translation complete." keepVisible:NO];
        [strongSelf openPath:outputPath];
        strongSelf->_statusLabel.stringValue =
            [NSString stringWithFormat:@"Translation saved: %@", outputPath.lastPathComponent];
      });
    });
}

- (void)promptToInstallArgosAndContinueWithSourceText:(NSString*)sourceText
                                       sourceLanguage:(NSString*)sourceLanguage
                                       targetLanguage:(NSString*)targetLanguage
                                           outputPath:(NSString*)outputPath {
    if (_translationInstallRunning) return;

    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Install Argos Translate?";
    alert.informativeText = @"Shenzhen PDF uses Argos Translate locally for offline translation. "
                            @"Install it, then continue translation.";
    [alert addButtonWithTitle:@"Install"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleInformational;
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/bash"];
    task.arguments = @[ @"-lc", [self argosInstallScript] ];

    __weak ShenzhenMacDelegate* weakSelf = self;
    [self runTranslationInstallTask:task
                              title:@"Installing Translation Support"
                            heading:@"Installing Argos Translate"
                         initialLog:@"Preparing Argos Translate installer...\n"
                         completion:^(NSTask* finishedTask, NSString* output) {
                           (void)output;
                           ShenzhenMacDelegate* strongSelf = weakSelf;
                           if (!strongSelf) return;
                           strongSelf->_translationInstallRunning = NO;
                           strongSelf->_translateButton.enabled =
                               strongSelf->_doc != NULL && !strongSelf->_translationRunning;
                           NSString* tool = [strongSelf argosToolPath];
                           if (finishedTask.terminationStatus == 0 && tool.length) {
                               [strongSelf appendTranslationInstallLog:@"\nArgos Translate installed.\n"];
                               [strongSelf->_translationInstallPanel orderOut:nil];
                               [strongSelf runArgosTranslationWithTool:tool
                                                            sourceText:sourceText
                                                        sourceLanguage:sourceLanguage
                                                        targetLanguage:targetLanguage
                                                            outputPath:outputPath
                                                      offeredInstaller:NO];
                           } else {
                               [strongSelf appendTranslationInstallLog:
                                               @"\nArgos Translate installation failed. The log above can be selected "
                                               @"and copied.\n"];
                               strongSelf->_statusLabel.stringValue = @"Argos installation failed.";
                           }
                         }];
}

- (void)translateDocument:(id)sender {
    (void)sender;
    if (!_doc || !_path.length) {
        NSBeep();
        return;
    }
    if (_translationInstallRunning) {
        [_translationInstallPanel makeKeyAndOrderFront:nil];
        _statusLabel.stringValue = @"Translation installer is already running.";
        return;
    }
    if (_translationRunning) {
        _statusLabel.stringValue = @"Translation is already running.";
        return;
    }

    BOOL usingSelection = NO;
    NSString* textError = nil;
    NSString* sourceText = [self currentTextForTranslationUsingSelection:&usingSelection error:&textError];
    if (sourceText.length == 0) {
        [self showError:@"Could not prepare translation" detail:textError ?: @"No text is available to translate."];
        return;
    }

    NSDictionary* options = [self promptForTranslationOptionsUsingSelection:usingSelection];
    if (!options) return;

    NSString* sourceLanguage = options[@"source"];
    NSString* targetLanguage = options[@"target"];
    NSString* outputPath = [self translatedOutputPathForPath:_path targetLanguage:targetLanguage];
    [self runArgosTranslationWithTool:[self argosToolPath]
                           sourceText:sourceText
                       sourceLanguage:sourceLanguage
                       targetLanguage:targetLanguage
                           outputPath:outputPath
                     offeredInstaller:NO];
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

        NSTextField* title = [NSTextField labelWithString:@"Installing OCRmyPDF, Tesseract, and language data"];
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
        _ocrInstallLog.selectable = YES;
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

- (NSDictionary<NSString*, NSString*>*)promptForOCRLanguage {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Choose OCR language";
    alert.informativeText = @"Choose the language data Tesseract should use for this PDF.";
    [alert addButtonWithTitle:@"Run OCR"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleInformational;

    NSPopUpButton* popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 320, 28) pullsDown:NO];
    for (NSDictionary<NSString*, NSString*>* language in spdf_ocr_languages()) {
        [popup addItemWithTitle:language[@"name"]];
        popup.lastItem.representedObject = language;
    }
    alert.accessoryView = popup;
    if ([alert runModal] != NSAlertFirstButtonReturn) return nil;
    NSDictionary<NSString*, NSString*>* selected = popup.selectedItem.representedObject;
    return selected[@"code"].length ? selected : nil;
}

- (NSString*)customTessdataParentPath {
    return [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/ShenzhenPDF"]
        stringByAppendingPathComponent:@"tesseract"];
}

- (BOOL)customTessdataHasOCRLanguage:(NSString*)language {
    NSString* tessdataDir = [[self customTessdataParentPath] stringByAppendingPathComponent:@"tessdata"];
    for (NSString* component in spdf_ocr_language_components(language)) {
        NSString* traineddata =
            [tessdataDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.traineddata", component]];
        if (![NSFileManager.defaultManager fileExistsAtPath:traineddata]) return NO;
    }
    return spdf_ocr_language_components(language).count > 0;
}

- (BOOL)tesseractPath:(NSString*)tesseract hasOCRLanguage:(NSString*)language {
    NSArray<NSString*>* required = spdf_ocr_language_components(language);
    if (required.count == 0) return NO;

    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:tesseract];
    task.arguments = @[ @"--list-langs" ];
    task.environment = [self taskEnvironmentWithToolPaths:@[ tesseract ]];
    NSPipe* pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    NSError* error = nil;
    if ([task launchAndReturnError:&error]) {
        [task waitUntilExit];
        NSData* data = pipe.fileHandleForReading.readDataToEndOfFile;
        NSString* output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        NSMutableSet<NSString*>* available = [NSMutableSet set];
        for (NSString* line in [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
            NSString* trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (trimmed.length) [available addObject:trimmed];
        }
        BOOL hasAll = YES;
        for (NSString* component in required) {
            if (![available containsObject:component]) {
                hasAll = NO;
                break;
            }
        }
        if (hasAll) return YES;
    }

    return [self customTessdataHasOCRLanguage:language];
}

- (NSDictionary<NSString*, NSString*>*)ocrTaskEnvironmentWithTool:(NSString*)tool
                                                        tesseract:(NSString*)tesseract
                                                         language:(NSString*)language {
    NSMutableDictionary<NSString*, NSString*>* env =
        [[self taskEnvironmentWithToolPaths:@[ tool ?: @"", tesseract ?: @"" ]] mutableCopy];
    if ([self customTessdataHasOCRLanguage:language]) env[@"TESSDATA_PREFIX"] = [self customTessdataParentPath];
    return env;
}

- (NSString*)ocrInstallScriptForLanguage:(NSString*)language {
    NSString* languageList = [spdf_ocr_language_components(language) componentsJoinedByString:@" "];
    return [NSString
        stringWithFormat:@"set -e\n"
                          "export PATH=\"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH\"\n"
                          "export NONINTERACTIVE=1\n"
                          "OCR_LANGS=\"%@\"\n"
                          "BREW=\"\"\n"
                          "if command -v brew >/dev/null 2>&1; then BREW=$(command -v brew); "
                          "elif [ -x /opt/homebrew/bin/brew ]; then BREW=/opt/homebrew/bin/brew; "
                          "elif [ -x /usr/local/bin/brew ]; then BREW=/usr/local/bin/brew; fi\n"
                          "if ! command -v ocrmypdf >/dev/null 2>&1 || ! command -v tesseract >/dev/null 2>&1; "
                          "then "
                          "if [ -z \"$BREW\" ]; then echo 'Homebrew not found. Installing Homebrew...'; "
                          "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/"
                          "install.sh)\"; "
                          "if [ -x /opt/homebrew/bin/brew ]; then BREW=/opt/homebrew/bin/brew; "
                          "elif [ -x /usr/local/bin/brew ]; then BREW=/usr/local/bin/brew; "
                          "else echo 'Homebrew installation did not produce a brew executable.'; exit 1; fi; fi; "
                          "echo \"Using $BREW\"; \"$BREW\" install ocrmypdf tesseract; "
                          "else echo 'OCRmyPDF and Tesseract are already installed.'; fi\n"
                          "if [ -n \"$BREW\" ] && printf '%%s\\n' \"$OCR_LANGS\" | grep -qv '^eng$'; then "
                          "echo 'Installing Tesseract language data...'; \"$BREW\" install tesseract-lang || true; "
                          "fi\n"
                          "TESS_PARENT=\"$HOME/Library/Application Support/ShenzhenPDF/tesseract\"\n"
                          "mkdir -p \"$TESS_PARENT/tessdata\"\n"
                          "download_lang() {\n"
                          "  lang=\"$1\"\n"
                          "  url=\"https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main/$lang."
                          "traineddata\"\n"
                          "  dest=\"$TESS_PARENT/tessdata/$lang.traineddata\"\n"
                          "  echo \"Downloading $lang traineddata...\"\n"
                          "  if command -v curl >/dev/null 2>&1; then curl -LfsS \"$url\" -o \"$dest\"; "
                          "elif command -v wget >/dev/null 2>&1; then wget -q \"$url\" -O \"$dest\"; "
                          "else echo 'curl or wget is required to download OCR language data.'; return 1; fi\n"
                          "}\n"
                          "for lang in $OCR_LANGS; do\n"
                          "  if command -v tesseract >/dev/null 2>&1 && tesseract --list-langs 2>/dev/null | "
                          "grep -qx \"$lang\"; then echo \"Tesseract language $lang is installed.\"; "
                          "elif [ -f \"$TESS_PARENT/tessdata/$lang.traineddata\" ]; then "
                          "echo \"Bundled Shenzhen PDF language $lang is installed.\"; "
                          "else download_lang \"$lang\"; fi\n"
                          "done\n"
                          "command -v ocrmypdf >/dev/null 2>&1\n"
                          "command -v tesseract >/dev/null 2>&1\n",
                         languageList];
}

- (void)installOCRAndRunAfterwardsWithLanguage:(NSString*)language displayName:(NSString*)displayName {
    if (_ocrInstallRunning) {
        [_ocrInstallPanel makeKeyAndOrderFront:nil];
        return;
    }

    _ocrInstallRunning = YES;
    _ocrButton.enabled = NO;
    [self showOCRInstallPanel];
    _ocrInstallLog.string = @"";
    [self appendOCRInstallLog:[NSString stringWithFormat:@"Preparing OCR installer for %@...\n", displayName]];

    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/bash"];
    task.arguments = @[ @"-lc", [self ocrInstallScriptForLanguage:language] ];
    NSPipe* pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    _ocrInstallTask = task;

    __weak ShenzhenMacDelegate* weakSelf = self;
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
        ShenzhenMacDelegate* strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_ocrInstallRunning = NO;
        strongSelf->_ocrInstallTask = nil;
        [strongSelf->_ocrInstallProgress stopAnimation:nil];
        strongSelf->_ocrButton.enabled =
            strongSelf->_doc != NULL && [strongSelf->_path.pathExtension.lowercaseString isEqualToString:@"pdf"];
        NSString* tool = [strongSelf ocrToolPath];
        NSString* tesseract = [strongSelf tesseractToolPath];
        if (finishedTask.terminationStatus == 0 && tool.length && tesseract.length &&
            [strongSelf tesseractPath:tesseract hasOCRLanguage:language]) {
            [strongSelf appendOCRInstallLog:@"\nOCR tools installed.\n"];
            [strongSelf->_ocrInstallPanel orderOut:nil];
            [strongSelf runOCRWithLanguage:language displayName:displayName];
        } else {
            [strongSelf
                appendOCRInstallLog:
                    @"\nOCR installation failed or the selected language data is still missing. The log above can "
                     "be selected and copied.\n"];
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

- (void)rotateCurrentPageByDegrees:(int)degrees {
    if (!_doc || !_path.length || ![_path.pathExtension.lowercaseString isEqualToString:@"pdf"]) {
        NSBeep();
        return;
    }

    NSInteger pageIndex = _pageIndex;
    char err[1024];
    BOOL ok = spdf_rotate_page(_doc, (int)pageIndex, degrees, err, sizeof(err));
    if (ok) ok = spdf_save_document(_doc, _path.fileSystemRepresentation, err, sizeof(err));
    if (!ok) {
        [self discardCachedRuntimeForTab:[self selectedTab]];
        [self loadSelectedTab];
        [self showError:@"Could not rotate page" detail:[NSString stringWithUTF8String:err[0] ? err : "Unknown error"]];
        return;
    }

    [_renderQueue cancelAllOperations];
    [_minimapQueue cancelAllOperations];
    [_queuedRenderPages removeAllObjects];
    [_queuedRenderOperations removeAllObjects];
    [_queuedMinimapThumbnailPages removeAllObjects];
    _renderGeneration++;
    if (_selectedTabIndex >= 0 && _selectedTabIndex < (NSInteger)_tabs.count) {
        SPDFDocumentTab* tab = _tabs[(NSUInteger)_selectedTabIndex];
        tab.pageIndex = pageIndex;
        [self discardCachedRuntimeForTab:tab];
    }
    [self loadSelectedTab];
    _statusLabel.stringValue = degrees > 0 ? @"Page rotated clockwise." : @"Page rotated anticlockwise.";
}

- (void)rotateClockwise:(id)sender {
    (void)sender;
    [self rotateCurrentPageByDegrees:90];
}

- (void)rotateAnticlockwise:(id)sender {
    (void)sender;
    [self rotateCurrentPageByDegrees:-90];
}

- (void)ocrDocument:(id)sender {
    (void)sender;
    NSDictionary<NSString*, NSString*>* language = [self promptForOCRLanguage];
    if (!language) return;
    [self runOCRWithLanguage:language[@"code"] displayName:language[@"name"]];
}

- (void)runOCRWithLanguage:(NSString*)language displayName:(NSString*)displayName {
    if (!_doc || !_path.length || ![_path.pathExtension.lowercaseString isEqualToString:@"pdf"]) {
        NSBeep();
        return;
    }

    NSString* tool = [self ocrToolPath];
    NSString* tesseract = [self tesseractToolPath];
    BOOL languageReady = tesseract.length && [self tesseractPath:tesseract hasOCRLanguage:language];
    if (!tool.length || !tesseract.length || !languageReady) {
        NSAlert* alert = [[NSAlert alloc] init];
        alert.messageText = !tool.length || !tesseract.length ? @"Install OCR support?" : @"Install OCR language data?";
        alert.informativeText = [NSString
            stringWithFormat:@"Shenzhen PDF can install OCRmyPDF, Tesseract, and the %@ traineddata, then continue OCR "
                             @"automatically when installation finishes.",
                             displayName.length ? displayName : language];
        [alert addButtonWithTitle:@"Install"];
        [alert addButtonWithTitle:@"Cancel"];
        alert.alertStyle = NSAlertStyleInformational;
        if ([alert runModal] == NSAlertFirstButtonReturn)
            [self installOCRAndRunAfterwardsWithLanguage:language displayName:displayName];
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
        alert.informativeText = @"Shenzhen PDF will make a backup of the original file before OCR replaces it.";
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
    NSMutableArray<NSString*>* args =
        [@[ @"--jobs", [NSString stringWithFormat:@"%ld", (long)jobs], @"--rotate-pages", @"--optimize", @"1" ]
            mutableCopy];
    [args addObjectsFromArray:@[ @"-l", language ]];
    if (hasText <= 0) [args addObject:@"--deskew"];
    [args addObject:hasText > 0 ? @"--redo-ocr" : @"--skip-text"];
    [args addObject:originalPath];
    [args addObject:tmp];

    _ocrButton.enabled = NO;
    NSString* runningDetail =
        [NSString stringWithFormat:@"OCR running (%@) with %ld workers...", displayName ?: language, (long)jobs];
    _statusLabel.stringValue = runningDetail;
    [self showOCRProgressWithDetail:runningDetail];

    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:tool];
    task.arguments = args;
    task.environment = [self ocrTaskEnvironmentWithTool:tool tesseract:tesseract language:language];
    NSPipe* pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    __block NSMutableData* outputData = [NSMutableData data];
    __weak ShenzhenMacDelegate* weakSelf = self;
    pipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle* handle) {
      NSData* chunk = handle.availableData;
      if (chunk.length > 0) {
          @synchronized(outputData) {
              [outputData appendData:chunk];
          }
          NSString* chunkText = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding] ?: @"";
          NSString* detail = SPDFLastMeaningfulOCRLine(chunkText);
          if (detail.length) {
              dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf updateOCRProgressDetail:detail];
              });
          }
      } else {
          handle.readabilityHandler = nil;
      }
    };

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
        ShenzhenMacDelegate* strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_ocrButton.enabled =
            strongSelf->_doc != NULL && [strongSelf->_path.pathExtension.lowercaseString isEqualToString:@"pdf"];
        if (finishedTask.terminationStatus != 0) {
            [NSFileManager.defaultManager removeItemAtPath:tmp error:nil];
            [strongSelf finishOCRProgressWithDetail:@"OCR failed."];
            NSString* detail = SPDFHumanReadableOCRFailure(output);
            if (detail.length > 1200) detail = [detail substringToIndex:1200];
            [strongSelf showError:@"OCR failed" detail:detail.length ? detail : @"OCRmyPDF exited with an error."];
            strongSelf->_statusLabel.stringValue = @"OCR failed.";
            return;
        }

        [strongSelf->_renderQueue cancelAllOperations];
        [strongSelf->_minimapQueue cancelAllOperations];
        [strongSelf->_queuedRenderPages removeAllObjects];
        [strongSelf->_queuedRenderOperations removeAllObjects];
        [strongSelf->_queuedMinimapThumbnailPages removeAllObjects];
        strongSelf->_renderGeneration++;
        [strongSelf discardCachedRuntimeForTab:[strongSelf selectedTab]];
        [strongSelf clearActiveMetadata];
        [strongSelf closeActiveDocumentIfUnowned];
        NSError* moveError = nil;
        NSURL* resultingURL = nil;
        if (![NSFileManager.defaultManager replaceItemAtURL:[NSURL fileURLWithPath:originalPath]
                                              withItemAtURL:[NSURL fileURLWithPath:tmp]
                                             backupItemName:nil
                                                    options:0
                                           resultingItemURL:&resultingURL
                                                      error:&moveError]) {
            [strongSelf finishOCRProgressWithDetail:@"Could not save OCR output."];
            [strongSelf showError:@"Could not save OCR output" detail:moveError.localizedDescription ?: @""];
            strongSelf->_statusLabel.stringValue = @"OCR output was not installed.";
            [strongSelf loadSelectedTab];
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
        [strongSelf finishOCRProgressWithDetail:strongSelf->_statusLabel.stringValue];
      });
    };

    NSError* launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        _ocrButton.enabled = YES;
        [self finishOCRProgressWithDetail:@"Could not start OCR."];
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

    NSPrintInfo* info = [NSPrintInfo.sharedPrintInfo copy];
    info.horizontalPagination = NSPrintingPaginationModeClip;
    info.verticalPagination = NSPrintingPaginationModeClip;
    info.horizontallyCentered = YES;
    info.verticallyCentered = YES;

    if ([_path.pathExtension.lowercaseString isEqualToString:@"pdf"]) {
        NSURL* url = [NSURL fileURLWithPath:_path];
        PDFDocument* pdfDocument = [[PDFDocument alloc] initWithURL:url];
        if (pdfDocument && pdfDocument.pageCount > 0) {
            if (!pdfDocument.allowsPrinting) {
                [self showError:@"Printing is not allowed" detail:@"This PDF's permissions do not allow printing."];
                return;
            }

            NSPrintOperation* pdfOperation = [pdfDocument printOperationForPrintInfo:info
                                                                         scalingMode:kPDFPrintPageScaleToFit
                                                                          autoRotate:YES];
            if (pdfOperation) {
                objc_setAssociatedObject(pdfOperation, @selector(printDocument:), pdfDocument,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                pdfOperation.jobTitle = _path.lastPathComponent ?: @"Shenzhen PDF";
                pdfOperation.showsPrintPanel = YES;
                pdfOperation.showsProgressPanel = YES;
                [pdfOperation runOperationModalForWindow:_window delegate:nil didRunSelector:NULL contextInfo:NULL];
                [self evictDistantRenderedPageImages];
                return;
            }
        }
    }

    NSSize paper = info.paperSize;
    NSInteger pageCount = spdf_page_count(_doc);
    SPDFPrintView* printView =
        [[SPDFPrintView alloc] initWithFrame:NSMakeRect(0, 0, paper.width, paper.height * MAX(1, pageCount))];
    printView.document = _doc;
    printView.pageCount = pageCount;
    printView.targetDPI = 1200.0;
    printView.fallbackPages = _renderedPages;

    NSPrintOperation* operation = [NSPrintOperation printOperationWithView:printView printInfo:info];
    operation.showsPrintPanel = YES;
    operation.showsProgressPanel = YES;
    [operation runOperationModalForWindow:_window delegate:nil didRunSelector:NULL contextInfo:NULL];
    [self evictDistantRenderedPageImages];
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

- (void)showPathInFolder:(NSString*)path {
    if (!path.length) {
        NSBeep();
        return;
    }

    NSURL* fileURL = [NSURL fileURLWithPath:path];
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[ fileURL ]];
}

- (void)showInFolder:(id)sender {
    (void)sender;
    if (!_doc || !_path.length) {
        NSBeep();
        return;
    }

    [self showPathInFolder:_path];
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
        NSMenuItem* editComment = [menu addItemWithTitle:@"Edit Comment..."
                                                  action:@selector(editComment:)
                                           keyEquivalent:@""];
        editComment.target = self;
        editComment.representedObject = @(_contextCommentIndex);
        NSMenuItem* deleteComment = [menu addItemWithTitle:@"Delete Comment..."
                                                    action:@selector(deleteComment:)
                                             keyEquivalent:@""];
        deleteComment.target = self;
        deleteComment.representedObject = @(_contextCommentIndex);
    }
    NSMenuItem* addComment = [menu addItemWithTitle:@"Add Comment..." action:@selector(addComment:) keyEquivalent:@""];
    addComment.enabled = _doc != NULL && (_selectedText.length > 0 || _contextPageIndex >= 0);
    NSMenuItem* copyImage = [menu addItemWithTitle:@"Copy Page Image"
                                            action:@selector(copyCurrentPageImage:)
                                     keyEquivalent:@""];
    copyImage.enabled = _doc && _pageIndex >= 0 && _pageIndex < (NSInteger)_renderedPages.count &&
                        _renderedPages[(NSUInteger)_pageIndex].image != nil;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Zoom In" action:@selector(zoomIn:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Zoom Out" action:@selector(zoomOut:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Fit Width" action:@selector(fitWidth:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Fit Page" action:@selector(fitPage:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* favorite = [menu addItemWithTitle:@"Favorite Page"
                                           action:@selector(favoriteCurrentPage:)
                                    keyEquivalent:@""];
    favorite.enabled = _doc != NULL;
    NSMenuItem* showInFolder = [menu addItemWithTitle:@"Show in Folder"
                                               action:@selector(showInFolder:)
                                        keyEquivalent:@""];
    showInFolder.enabled = _doc != NULL && _path.length > 0;
    [menu addItemWithTitle:@"Properties..." action:@selector(showProperties:) keyEquivalent:@""];
    [NSMenu popUpContextMenu:menu withEvent:event forView:view];
}

- (void)unimplementedMenuItem:(id)sender {
    (void)sender;
    NSBeep();
    _statusLabel.stringValue = @"This Shenzhen PDF command is listed but not implemented yet.";
}

- (void)openSettingsFile:(id)sender {
    NSMenuItem* item = [NSMenuItem new];
    item.representedObject = @"settings.json";
    [self openStateJSONFile:item];
}

- (void)openStateJSONFile:(id)sender {
    [self savePersistentState];
    NSString* name = [sender respondsToSelector:@selector(representedObject)] ? [sender representedObject] : nil;
    if (![name isKindOfClass:NSString.class] || name.length == 0) name = @"settings.json";
    NSString* path = [self pathForStateFile:name];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        id empty = [name isEqualToString:@"favorites.json"] ? @[] : @{};
        [self writeJSONObject:empty toFile:name];
    }
    NSURL* url = [NSURL fileURLWithPath:path];
    if (![NSWorkspace.sharedWorkspace openURL:url]) {
        NSBeep();
        _statusLabel.stringValue = [NSString stringWithFormat:@"Could not open %@.", name];
    }
}

- (void)revealSettingsFolder:(id)sender {
    (void)sender;
    NSURL* url = [NSURL fileURLWithPath:[self supportDirectory] isDirectory:YES];
    if (![NSWorkspace.sharedWorkspace openURL:url]) {
        NSBeep();
        _statusLabel.stringValue = @"Could not open settings folder.";
    }
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
    } else if (notification.object == _sidebarFilterField) {
        if (_updatingSidebarFilterField) return;
        [self setSidebarFilterTextForCurrentMode:_sidebarFilterField.stringValue ?: @""];
        [self rebuildSidebar];
    } else if (notification.object == _paletteSearchField) {
        _paletteFavoritePendingDelete = nil;
        [self refreshPaletteResults];
    } else if (notification.object == _shortcutHelpSearchField) {
        [self refreshShortcutHelpRows];
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
            BOOL shift = (NSApp.currentEvent.modifierFlags & NSEventModifierFlagShift) != 0;
            if (_findMatches.count > 0)
                [self findFromCurrentForward:!shift];
            else
                [self startFindForCurrentQuery];
            return YES;
        }
        return NO;
    }
    if (control == _shortcutHelpSearchField) {
        if (commandSelector == @selector(cancelOperation:)) {
            [self closeShortcutHelp:control];
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
    if (tableView == _shortcutHelpTable) return (NSInteger)_shortcutHelpRows.count;
    return (NSInteger)_sidebarItems.count;
}

- (CGFloat)tableView:(NSTableView*)tableView heightOfRow:(NSInteger)row {
    if (tableView == _shortcutHelpTable) {
        if (row < 0 || row >= (NSInteger)_shortcutHelpRows.count) return 48.0;
        NSString* kind = _shortcutHelpRows[(NSUInteger)row][@"kind"];
        return [kind isEqualToString:@"header"] ? 36.0 : 54.0;
    }
    if (tableView != _paletteTable) return _sidebarTable.rowHeight;
    return [self paletteHeightForRow:row];
}

- (NSIndexSet*)tableView:(NSTableView*)tableView
    selectionIndexesForProposedSelection:(NSIndexSet*)proposedSelectionIndexes {
    if (tableView == _shortcutHelpTable) return [NSIndexSet indexSet];
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
    if (tableView == _shortcutHelpTable) {
        if (row < 0 || row >= (NSInteger)_shortcutHelpRows.count) return nil;
        NSDictionary* shortcut = _shortcutHelpRows[(NSUInteger)row];
        NSString* kind = shortcut[@"kind"];
        if ([kind isEqualToString:@"header"]) {
            NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 620, 36)];
            NSTextField* label = [NSTextField labelWithString:shortcut[@"title"] ?: @""];
            label.translatesAutoresizingMaskIntoConstraints = NO;
            label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
            label.textColor = NSColor.labelColor;
            [view addSubview:label];
            [NSLayoutConstraint activateConstraints:@[
                [label.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:6],
                [label.centerYAnchor constraintEqualToAnchor:view.centerYAnchor constant:4]
            ]];
            return view;
        }

        NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 620, 54)];
        NSTextField* title = [NSTextField labelWithString:shortcut[@"title"] ?: @""];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.font = [NSFont systemFontOfSize:15 weight:NSFontWeightRegular];
        title.textColor = [kind isEqualToString:@"empty"] ? NSColor.secondaryLabelColor : NSColor.labelColor;
        [view addSubview:title];

        NSString* subtitleText = shortcut[@"subtitle"];
        NSTextField* subtitle = [NSTextField labelWithString:subtitleText ?: @""];
        subtitle.translatesAutoresizingMaskIntoConstraints = NO;
        subtitle.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
        subtitle.textColor = NSColor.secondaryLabelColor;
        [view addSubview:subtitle];

        NSView* keycaps = [self shortcutKeycapsViewForKeys:shortcut[@"keys"]];
        [view addSubview:keycaps];
        [NSLayoutConstraint activateConstraints:@[
            [title.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:6],
            [title.trailingAnchor constraintLessThanOrEqualToAnchor:keycaps.leadingAnchor constant:-16],
            [title.topAnchor constraintEqualToAnchor:view.topAnchor constant:9],
            [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [subtitle.trailingAnchor constraintLessThanOrEqualToAnchor:keycaps.leadingAnchor constant:-16],
            [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2],
            [keycaps.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-8],
            [keycaps.centerYAnchor constraintEqualToAnchor:view.centerYAnchor]
        ]];
        keycaps.hidden = [kind isEqualToString:@"empty"] || [shortcut[@"keys"] count] == 0;
        return view;
    }

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

                deleteButton = [NSButton buttonWithTitle:@""
                                                  target:self
                                                  action:@selector(paletteFavoriteDeleteClicked:)];
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
            deleteButton.attributedTitle = [[NSAttributedString alloc] initWithString:deleteTitle
                                                                           attributes:attributes];
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
        action == @selector(focusFind:) || action == @selector(setCommentAuthor:) ||
        action == @selector(openRecentDocument:) || action == @selector(openSettingsFile:) ||
        action == @selector(openStateJSONFile:) || action == @selector(revealSettingsFolder:) ||
        action == @selector(showShortcutHelp:))
        return YES;
    if (action == @selector(fillWindow:) || action == @selector(centerWindowInScreen:) ||
        action == @selector(moveWindowToLeftHalf:) || action == @selector(moveWindowToRightHalf:) ||
        action == @selector(moveWindowToTopHalf:) || action == @selector(moveWindowToBottomHalf:))
        return _window != nil && !_presentationMode;
    if (action == @selector(reopenLastClosedDocument:)) return _closedDocumentPaths.count > 0;
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
    if (action == @selector(rotateClockwise:) || action == @selector(rotateAnticlockwise:))
        return hasDoc && [_path.pathExtension.lowercaseString isEqualToString:@"pdf"];
    if (action == @selector(ocrDocument:))
        return hasDoc && [_path.pathExtension.lowercaseString isEqualToString:@"pdf"];
    if (action == @selector(translateDocument:)) return hasDoc && !_translationRunning && !_translationInstallRunning;
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
                printf("Shenzhen PDF portable mac 0.5\n");
                return 0;
            }
        }

        NSApplication* app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyRegular;

        ShenzhenMacDelegate* delegate = [[ShenzhenMacDelegate alloc] init];
        for (int i = 1; i < argc; ++i) {
            if (strcmp(argv[i], "--detached-tab") == 0) {
                delegate.detachedTabLaunch = YES;
                continue;
            }
            if (strcmp(argv[i], "--restore-window") == 0 && i + 1 < argc) {
                delegate.restoreWindowID = [NSString stringWithUTF8String:argv[++i]];
                continue;
            }
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
