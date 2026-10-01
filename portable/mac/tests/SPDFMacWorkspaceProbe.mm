// Offscreen integration fixture: actual reader window, controls, constraints,
// PDF canvas and minimap. This does not call the application's entry point or
// launch delegate. It never reads the user's configuration or opens a window.
#import "SPDFMacDelegatePrivate.h"
#import "SPDFMacMarkdownDelegatePrivate.h"
#import "SPDFMacTabGroups.h"
#import "SPDFUpdater.h"
#import "SPDFMacWorkspaceChrome.h"
#import <PDFKit/PDFKit.h>
#import <objc/runtime.h>
#undef main

static NSUInteger failures;
static void Check(BOOL ok, NSString* message) {
    if (!ok) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); failures++; }
}
static void ForbiddenOrder(id object, SEL action, NSInteger place, NSInteger other) {
    (void)object; (void)action; (void)place; (void)other;
    fprintf(stderr,"FAIL: headless reader attempted to order a window\n");
    exit(1);
}
@interface ShenzhenMacDelegate (WorkspaceProbeAccess)
- (void)buildWindow;
- (void)buildMenu;
- (void)checkForUpdates:(id)sender;
- (void)applyPresentationChrome;
- (void)startFindForCurrentQueryResetSavedIndex:(BOOL)reset revealMatch:(BOOL)reveal;
- (void)sidebarModeChanged:(id)sender;
- (void)updateTabStripFrame;
@end
@interface WorkspaceReaderProbe : ShenzhenMacDelegate
- (void)prepare:(NSURL*)URL width:(CGFloat)width dark:(BOOL)dark;
- (void)capture:(NSString*)path width:(CGFloat)width sidebar:(BOOL)sidebar map:(BOOL)map;
- (void)prepareMarkdown:(NSURL*)URL;
- (void)setProbePresentation:(BOOL)value;
- (void)setProbeFind:(BOOL)value;
@end
@implementation WorkspaceReaderProbe
// These are disk boundaries, not UI code. Keeping them inert makes the full
// production buildWindow safe even when a layout callback wants to persist.
- (void)savePersistentState {}
- (void)persistActiveState {}
- (void)rememberActiveTabState {}
- (void)prepare:(NSURL*)URL width:(CGFloat)width dark:(BOOL)dark {
    _tabs=[NSMutableArray array];
    SPDFTabGroup* research=[SPDFTabGroup groupWithColor:@"Purple"]; research.name=@"Research";
    SPDFTabGroup* general=[SPDFTabGroup generalGroup]; general.collapsed=YES;
    SPDFTabGroup* design=[SPDFTabGroup groupWithColor:@"Teal"]; design.name=@"Design"; design.collapsed=YES;
    NSArray* titles=@[@"Interface specification.pdf",@"Hardware reference.pdf",@"Project notes.md",@"Product brief.pdf",@"Visual guidelines.pdf"];
    for (NSUInteger i=0;i<titles.count;i++) {
        SPDFDocumentTab* tab=[SPDFDocumentTab new]; tab.title=titles[i];
        tab.path=i ? [URL.URLByDeletingLastPathComponent.path stringByAppendingPathComponent:titles[i]] : URL.path;
        tab.group=i<3 ? research : i==3 ? general : design;
        tab.showSidebar=YES; tab.showMinimap=YES; tab.zoom=1; tab.fitMode=SPDFFitModeWidth;
        [_tabs addObject:tab];
    }
    _selectedTabIndex=0; _path=URL.path; _zoom=1; _fitMode=SPDFFitModeWidth;
    _markdownFontScale=1; _sidebarWidth=240; _minimapWidth=112;
    _sidebarPreferredVisible=YES; _minimapPreferredVisible=YES;
    _restoredWindowContentSize=NSMakeSize(width,780);
    _renderedPages=[NSMutableArray array]; _sidebarItems=[NSMutableArray array];
    _findMatches=[NSMutableArray array]; _findHighlights=[NSMutableDictionary dictionary];
    _findMatchIndex=-1; _findQueue=[NSOperationQueue new];
    char error[1024]={}; _doc=spdf_open(URL.fileSystemRepresentation,error,sizeof(error));
    Check(_doc!=NULL, [NSString stringWithFormat:@"PDF fixture loads: %s",error]);
    if (!_doc) return;
    spdf_load_outline(_doc,&_outline,error,sizeof(error));
    [self buildWindow];
    _suppressToolbarOverflowUpdates=NO; _uiReady=YES;
    _window.appearance=[NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    [_window setContentSize:NSMakeSize(width,780)];
    PDFDocument* PDF=[[PDFDocument alloc] initWithURL:URL];
    for (NSUInteger i=0;i<PDF.pageCount;i++) {
        PDFPage* original=[PDF pageAtIndex:i]; NSRect bounds=[original boundsForBox:kPDFDisplayBoxMediaBox];
        SPDFRenderedPage* page=[SPDFRenderedPage new]; page.pageIndex=i;
        page.pageWidth=NSWidth(bounds); page.pageHeight=NSHeight(bounds);
        page.image=[original thumbnailOfSize:bounds.size forBox:kPDFDisplayBoxMediaBox];
        page.imagePointWidth=NSWidth(bounds); page.imagePointHeight=NSHeight(bounds);
        page.imageZoom=1; page.imageScale=1; page.minimapImage=page.image;
        [_renderedPages addObject:page];
    }
    _pageView.pages=_renderedPages; _pageView.zoom=1; _minimapView.pages=_renderedPages;
    [self rebuildSidebar]; [self updateControls];
}
- (void)prepareMarkdown:(NSURL*)URL {
    _path=URL.path; _tabs[0].path=URL.path; _tabs[0].title=URL.lastPathComponent;
    if (_doc) { spdf_close(_doc); _doc=NULL; }
    spdf_free_outline(&_outline);
    [self installMarkdownHostInDocumentContainer];
    id state=[self valueForKey:@"markdownState"];
    NSView* host=[state valueForKey:@"hostView"]; host.hidden=NO; _pageScrollView.hidden=YES;
    SPDFMacMarkdownSession* session=[[SPDFMacMarkdownSession alloc] initWithDocumentURL:URL];
    [state setValue:session forKey:@"activeSession"];
    __block BOOL done=NO, ready=NO;
    [session activateInHostView:host workQueue:dispatch_queue_create("workspace-probe.markdown",DISPATCH_QUEUE_SERIAL)
        scrollOrigin:NSZeroPoint selectedRange:NSMakeRange(NSNotFound,0) pageIndex:0 zoom:1
        fitMode:SPDFMacMarkdownPageFitWidth anchor:nil completion:^(BOOL success,NSError* error) {
            ready=success; done=YES; if(error) fprintf(stderr,"Markdown fixture: %s\n",error.localizedDescription.UTF8String);
        }];
    NSDate* deadline=[NSDate dateWithTimeIntervalSinceNow:20];
    while((!done || !session.navigationReady) && deadline.timeIntervalSinceNow>0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    Check(done && ready && session.navigationReady && session.pageCount>0,@"actual Markdown renderer populates the native reader host");
    [self rebuildSidebar]; [self updateControls];
}
- (void)setProbeFind:(BOOL)value {
    _searchField.stringValue=value ? @"workspace" : @"";
    [self startFindForCurrentQueryResetSavedIndex:YES revealMatch:NO];
    NSDate* deadline=[NSDate dateWithTimeIntervalSinceNow:10];
    while(_findSearchInProgress && deadline.timeIntervalSinceNow>0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    if(value) Check(!_findSearchInProgress && _findMatches.count>0,@"real PDF search populates the Find panel");
    _sidebarModeControl.spdf_selectedSidebarMode=value ? SPDFSidebarModeSearch : SPDFSidebarModeChapters;
    [self sidebarModeChanged:_sidebarModeControl];
}
- (void)setProbePresentation:(BOOL)value {
    _presentationMode=value; [self applyPresentationChrome];
    Check(_toolbar.hidden==value && _tabStrip.hidden==value,@"presentation hides and restores reader chrome");
}
- (void)capture:(NSString*)path width:(CGFloat)width sidebar:(BOOL)sidebar map:(BOOL)map {
    [_window setContentSize:NSMakeSize(width,780)];
    [self setSidebarActuallyVisible:sidebar]; [self setMinimapActuallyVisible:map];
    [_window.contentView layoutSubtreeIfNeeded];
    [self syncWorkspaceChrome]; [_window.contentView layoutSubtreeIfNeeded];
    NSSize clip=_pageScrollView.contentView.bounds.size;
    _pageView.viewportWidthHint=clip.width; _pageView.viewportHeightHint=clip.height;
    [_pageView setFrameSize:[_pageView documentSizeForClipSize:clip]];
    [self updateMinimap];
    [_window.contentView layoutSubtreeIfNeeded];
    Check(!_window.visible,@"reader window stays offscreen");
    Check(NSWidth(_pageScrollView.frame)>100 && NSHeight(_pageScrollView.frame)>100,@"document retains a usable viewport");
    if (![self isMarkdownActive])
        Check(_pageView.pages.count==3 && _minimapView.pages.count==3,@"real PDF canvas and map retain every fixture page");
    else Check(self.activeMarkdownSession.pageCount>0,@"Markdown pages survive workspace resizing");
    Check(_sidebarVisible==sidebar && (sidebar || NSWidth(_sidebarContainer.frame)<=1),@"requested sidebar visibility is applied");
    if (!_presentationMode) {
        CGFloat titleWidth=[_fitModePopup.titleOfSelectedItem sizeWithAttributes:@{NSFontAttributeName:_fitModePopup.font}].width;
        Check(NSWidth(_fitModePopup.frame)>=ceil(titleWidth)+18,@"zoom selection keeps its full readable title");
        for(NSView* child in _toolbar.arrangedSubviews) if([child isKindOfClass:NSStackView.class]) {
            NSStackView* row=(id)child; NSMutableArray<NSValue*>* controls=[NSMutableArray array];
            for(NSView* control in row.arrangedSubviews) {
                if(control.hidden || NSWidth(control.frame)<=0) continue;
                NSRect rect=[control convertRect:control.bounds toView:_toolbar];
                Check(NSMinX(rect)>=-.5 && NSMaxX(rect)<=NSWidth(_toolbar.bounds)+.5,@"direct toolbar controls stay inside the header");
                if([control isKindOfClass:NSControl.class]) {
                    for(NSValue* value in controls) Check(!NSIntersectsRect(NSInsetRect(value.rectValue,.5,.5),NSInsetRect(rect,.5,.5)),
                        [NSString stringWithFormat:@"toolbar controls never overlap: %@ / %@",NSStringFromRect(value.rectValue),NSStringFromRect(rect)]);
                    [controls addObject:[NSValue valueWithRect:rect]];
                }
            }
        }
        Check([((SPDFSidebarNavigationControl*)_sidebarModeControl).documentTitle isEqual:_tabs[0].title],@"sidebar retains the full document filename");
    }
    NSView* view=_window.contentView;
    for (NSView* child in @[_tabStrip,_toolbar,_sidebarModeControl,_pageScrollView]) {
        NSRect rect=[child convertRect:child.bounds toView:view];
        printf("geometry %s %s\n",NSStringFromClass(child.class).UTF8String,NSStringFromRect(rect).UTF8String);
        Check(isfinite(rect.origin.x)&&isfinite(rect.origin.y)&&isfinite(rect.size.width)&&isfinite(rect.size.height),@"chrome has finite geometry");
    }
    if (path.length) {
        NSBitmapImageRep* bitmap=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
        [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
        // cacheDisplay omits the window backing. Composite it explicitly so
        // clear NSView regions do not appear black in PNG viewers.
        NSBitmapImageRep* opaque=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
            pixelsWide:bitmap.pixelsWide pixelsHigh:bitmap.pixelsHigh bitsPerSample:8 samplesPerPixel:4
            hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        opaque.size=view.bounds.size;
        [_window.appearance performAsCurrentDrawingAppearance:^{
            [NSGraphicsContext saveGraphicsState];
            NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithBitmapImageRep:opaque];
            [NSColor.windowBackgroundColor setFill]; NSRectFill(view.bounds);
            [bitmap drawInRect:view.bounds fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
                fraction:1 respectFlipped:YES hints:nil];
            [NSGraphicsContext restoreGraphicsState];
        }];
        Check([[opaque representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],@"native reader PNG written");
    }
}
@end
static BOOL updaterInvoked;
static void UpdaterSpy(id object,SEL action,BOOL userInitiated) {
    (void)object; (void)action; updaterInvoked=userInitiated;
}
static void CheckUpdaterMenu(WorkspaceReaderProbe* reader) {
    [reader buildMenu]; NSMenuItem* found=nil;
    for(NSMenuItem* item in NSApp.mainMenu.itemArray.firstObject.submenu.itemArray)
        if(item.action==@selector(checkForUpdates:)) found=item;
    Check(found!=nil && [reader validateMenuItem:found],@"Check for Updates remains reachable and enabled in the reader menu");
    Method method=class_getInstanceMethod(SPDFUpdater.class,@selector(checkForUpdatesUserInitiated:));
    IMP original=method_setImplementation(method,(IMP)UpdaterSpy);
    [reader checkForUpdates:nil];
    method_setImplementation(method,original);
    Check(updaterInvoked,@"native menu route requests a user-initiated update check");
}
static NSURL* Fixture(NSString* root) {
    NSURL* URL=[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"Interface specification.pdf"]];
    NSMutableData* data=[NSMutableData data];
    CGRect paper=CGRectMake(0,0,595,842);
    CGDataConsumerRef consumer=CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGContextRef context=CGPDFContextCreate(consumer,&paper,NULL); CGDataConsumerRelease(consumer);
    for (NSUInteger page=0;page<3;page++) {
        CGPDFContextBeginPage(context,NULL);
        NSGraphicsContext* saved=NSGraphicsContext.currentContext;
        NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithCGContext:context flipped:NO];
        [NSColor.whiteColor setFill]; NSRectFill(NSRectFromCGRect(paper));
        [[NSString stringWithFormat:@"%lu. Interface specification",page+1] drawAtPoint:NSMakePoint(48,750)
            withAttributes:@{NSFontAttributeName:[NSFont boldSystemFontOfSize:24],NSForegroundColorAttributeName:NSColor.blackColor}];
        [@"A focused workspace for reading and organizing documents.\n\nAll controls remain native, and reading positions are preserved.\nThe map continues to show the real document and viewport."
            drawInRect:NSMakeRect(48,560,499,150) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:14],NSForegroundColorAttributeName:NSColor.darkGrayColor}];
        NSGraphicsContext.currentContext=saved; CGPDFContextEndPage(context);
    }
    CGPDFContextClose(context); CGContextRelease(context);
    PDFDocument* PDF=[[PDFDocument alloc] initWithData:data]; PDFOutline* outline=[PDFOutline new];
    for (NSUInteger i=0;i<3;i++) { PDFOutline* entry=[PDFOutline new];
        entry.label=@[@"Overview",@"Reading workspace",@"Technical decisions"][i];
        entry.destination=[[PDFDestination alloc] initWithPage:[PDF pageAtIndex:i] atPoint:NSMakePoint(0,842)];
        [outline insertChild:entry atIndex:i]; }
    PDF.outlineRoot=outline; Check([PDF writeToURL:URL],@"PDF fixture written"); return URL;
}
int main(int argc,const char* argv[]) {
    @autoreleasepool {
        NSString* root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
        setenv("SPDF_STATE_DIR",root.UTF8String,1); setenv("SPDF_NO_WINDOW_FIRST","1",1);
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        method_setImplementation(class_getInstanceMethod(NSWindow.class,@selector(orderWindow:relativeTo:)),(IMP)ForbiddenOrder);
        NSString* output=argc>1 ? [NSString stringWithUTF8String:argv[1]] : @"";
        if (output.length) [NSFileManager.defaultManager createDirectoryAtPath:output withIntermediateDirectories:YES attributes:nil error:nil];
        NSURL* URL=Fixture(root);
        NSURL* markdownURL=[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"Project notes.md"]];
        [@"# Project notes\n\nThe same compact chrome surrounds Markdown.\n\n## Reading workspace\n\nA native document map, visible tools and a single sidebar.\n\n## Interaction\n\nSelect a document to read; collapse a group without changing the document."
            writeToURL:markdownURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
        for (NSNumber* dark in @[@NO,@YES]) {
            WorkspaceReaderProbe* reader=[WorkspaceReaderProbe new]; [reader prepare:URL width:1280 dark:dark.boolValue];
            CheckUpdaterMenu(reader);
            for (NSNumber* width in @[@1280,@880,@640]) {
                NSString* name=[NSString stringWithFormat:@"reader-%@-%@.png",dark.boolValue ? @"dark" : @"light",width];
                [reader capture:output.length ? [output stringByAppendingPathComponent:name] : nil width:width.doubleValue sidebar:YES map:YES];
            }
            [reader setProbeFind:YES];
            [reader capture:output.length ? [output stringByAppendingPathComponent:dark.boolValue ? @"reader-dark-find.png" : @"reader-light-find.png"] : nil
                width:1280 sidebar:YES map:YES];
            [reader setProbeFind:NO];
            [reader capture:output.length ? [output stringByAppendingPathComponent:dark.boolValue ? @"reader-dark-hidden.png" : @"reader-light-hidden.png"] : nil
                width:1280 sidebar:NO map:NO];
            [reader setProbePresentation:YES];
            [reader capture:output.length ? [output stringByAppendingPathComponent:dark.boolValue ? @"reader-dark-presentation.png" : @"reader-light-presentation.png"] : nil
                width:1280 sidebar:NO map:NO];
            [reader setProbePresentation:NO];
            [reader prepareMarkdown:markdownURL];
            [reader capture:output.length ? [output stringByAppendingPathComponent:dark.boolValue ? @"reader-dark-markdown.png" : @"reader-light-markdown.png"] : nil
                width:1280 sidebar:YES map:YES];
        }
        Check(NSApp.windows.count>0,@"probe constructed actual reader windows");
        for (NSWindow* window in NSApp.windows) Check(!window.visible,@"no window was displayed");
        [NSFileManager.defaultManager removeItemAtPath:root error:nil];
        if (!failures) puts("SPDFMacWorkspaceProbe passed");
    }
    return failures ? 1 : 0;
}
