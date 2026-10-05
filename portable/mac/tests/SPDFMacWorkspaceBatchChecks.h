// Included by the production reader probe; never orders a reader window onscreen.
#import "SPDFMacHeaderDragView.h"
#import "SPDFMacWindowChrome.h"
static NSView* BatchFind(NSView* host,NSString* identifier) {
    if([host.identifier isEqual:identifier]) return host;
    for(NSView* child in host.subviews) { NSView* found=BatchFind(child,identifier); if(found) return found; }
    return nil;
}
static NSUInteger BatchDragCalls;
static void BatchDragSpy(id object,SEL action,NSEvent* event) { (void)object; (void)action; (void)event; BatchDragCalls++; }
@interface WorkspaceReaderProbe (BatchChecks)
- (void)checkBatchChanges;
- (void)checkSingleImageFit;
- (void)checkCopyPanelInsets;
- (void)fitWidth:(id)sender;
- (void)fitPage:(id)sender;
- (void)resizeDocumentView;
@end
@implementation WorkspaceReaderProbe (BatchChecks)
- (void)checkBatchChanges {
    [_window setContentSize:NSMakeSize(1280,780)]; [self applyWorkspacePanelPolicy];
    [_window.contentView layoutSubtreeIfNeeded];
    Check(fabs(NSMinY(_splitView.frame))<.5,@"reader reaches bottom of window without redundant footer");
    NSView* pill=BatchFind(_sidebarContainer,@"WorkspaceSourcePill");
    Check(pill && pill.hidden,@"ordinary originals have no source-status pill");
    [self setProbeVersion:YES]; [self syncWorkspaceChrome];
    Check(!pill.hidden && NSMaxY(pill.frame)<45,@"Collection status appears at bottom of left panel");
    [self setProbeVersion:NO]; [self syncWorkspaceChrome];
    Method method=class_getInstanceMethod(SPDFWindow.class,@selector(handleChromeMouseDown:));
    IMP original=method_setImplementation(method,(IMP)BatchDragSpy);
    NSEvent* down=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSZeroPoint modifierFlags:0 timestamp:0
        windowNumber:_window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    NSUInteger headers=0;
    for(NSView* host in @[_sidebarContainer,_documentContainer]) for(NSView* view in host.subviews)
        if([view isKindOfClass:SPDFHeaderDragView.class]) {
            NSPoint point=host==_sidebarContainer ?
                [_sidebarModeControl convertPoint:NSMakePoint(20,58) toView:nil] :
                [view convertPoint:NSMakePoint(12,20) toView:nil];
            NSView* frame=_window.contentView.superview;
            NSView* hit=[frame hitTest:frame.superview ? [frame.superview convertPoint:point fromView:nil] : point];
            Check(hit==view,[NSString stringWithFormat:@"%@ empty header hits drag surface, got %@",host==_sidebarContainer ? @"Sidebar" : @"Map",NSStringFromClass(hit.class)]);
            [hit mouseDown:down]; headers++;
        }
    method_setImplementation(method,original);
    Check(headers==2 && BatchDragCalls>=2,@"both panel headers route empty-space presses to native window drag");
    for(NSButton* control in _sidebarModeControl.accessibilityChildren)
        Check(spdf_window_chrome_view_is_interactive(control),@"sidebar buttons retain click ownership instead of dragging");
    _pageScrollView.scrollerStyle=NSScrollerStyleLegacy;
    _pageScrollView.hasHorizontalScroller=YES; _pageScrollView.hasVerticalScroller=YES;
    [_pageScrollView tile];
    CGFloat first=[self zoomForFitMode:SPDFFitModePage pageIndex:0];
    Check(!_pageScrollView.hasHorizontalScroller,@"first Fit Page removes stale Fit Width horizontal scroller before measuring");
    CGFloat second=[self zoomForFitMode:SPDFFitModePage pageIndex:0];
    Check(fabs(first-second)<.0001,@"repeating Fit Page does not change fitted zoom");
    _pageScrollView.scrollerStyle=NSScrollerStyleOverlay;
    [self checkSingleImageFit];
}
- (void)checkSingleImageFit {
    // Exercise the actual Cmd+2 / Cmd+1 action path on a tall, single-page image.
    NSBitmapImageRep* bitmap=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:400 pixelsHigh:900
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace
        bytesPerRow:0 bitsPerPixel:0];
    NSString* path=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"png"]];
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
    char error[1024]={}; spdf_document* image=spdf_open(path.fileSystemRepresentation,error,sizeof(error));
    Check(image!=NULL,@"image fit regression fixture loads"); if(!image) return;
    spdf_document* previous=_doc; _doc=image;
    NSString* previousPath=_path; _path=path;
    NSMutableArray* pages=_renderedPages;
    CGFloat zoom=_zoom; SPDFFitMode mode=_fitMode;
    _pageScrollView.scrollerStyle=NSScrollerStyleLegacy;
    SPDFRenderedPage* page=[SPDFRenderedPage new]; page.pageWidth=400; page.pageHeight=900;
    _renderedPages=[NSMutableArray arrayWithObject:page]; _pageView.pages=_renderedPages;
    [self fitWidth:nil];
    Check(_pageScrollView.hasVerticalScroller,@"Fit Width requires scrolling the tall image");
    [self fitPage:nil]; CGFloat first=_zoom; NSRect firstFrame=_pageView.frame;
    [self fitPage:nil];
    Check(fabs(first-_zoom)<.0001 && NSEqualRects(firstFrame,_pageView.frame),
        @"first Fit Page after Fit Width is identical to second Fit Page");
    Check(!_pageScrollView.hasVerticalScroller && !_pageScrollView.hasHorizontalScroller,
        @"single image Fit Page has no leftover scrollbars or bottom strip");
    _doc=previous; _path=previousPath; _renderedPages=pages; _pageView.pages=pages;
    _zoom=zoom; _fitMode=mode; _pageView.zoom=zoom;
    _pageScrollView.scrollerStyle=NSScrollerStyleOverlay;
    [self resizeDocumentView]; spdf_close(image);
    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
}
- (void)checkCopyPanelInsets {
    NSInteger mode=_sidebarModeControl.spdf_selectedSidebarMode;
    [self setProbeVersion:YES];
    for(NSNumber* value in @[@(SPDFSidebarModeGroups),@(SPDFSidebarModeHistory)]) {
        _sidebarModeControl.spdf_selectedSidebarMode=value.integerValue;
        [self sidebarModeChanged:_sidebarModeControl]; [self syncWorkspaceChrome];
        [_window.contentView layoutSubtreeIfNeeded];
        NSView* pill=BatchFind(_sidebarContainer,@"WorkspaceSourcePill"); BOOL found=NO;
        for(NSView* body in _sidebarContainer.subviews)
            if(!body.hidden && [body.identifier isEqual:@"WorkspaceSidebarBody"]) {
                found=YES;
                Check(NSMinY(body.frame)>=NSMaxY(pill.frame)+7,
                    @"History and Groups leave room for the copy pill without obscuring content");
            }
        Check(found,@"copy-panel clearance uses a real visible History/Groups body");
    }
    [self setProbeVersion:NO];
    _sidebarModeControl.spdf_selectedSidebarMode=mode; [self sidebarModeChanged:_sidebarModeControl];
}
@end
