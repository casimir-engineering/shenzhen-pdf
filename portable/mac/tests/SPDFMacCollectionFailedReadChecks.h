#import "SPDFMacCollectionAvailability.h"
#include <sys/stat.h>
@interface CollectionFailedReadProbe : WorkspaceReaderProbe
@property NSUInteger openErrors;
- (void)checkFailedSource:(NSURL*)URL;
@end
@implementation CollectionFailedReadProbe
- (void)showError:(NSString*)message detail:(NSString*)detail { (void)message; (void)detail; self.openErrors++; }
- (void)checkFailedSource:(NSURL*)URL {
    SPDFMacCollectionStore* store=SPDFMacCollectionStore.defaultStore;
    [store updateSettings:@{@"choice":@"enabled"} error:nil];
    NSDictionary* document=[store capturePath:URL.path reason:@"Opened" error:nil];
    Check([document[@"versions"] count]>0,@"fixture has a saved revision before access is lost");
    SPDFDocumentTab* original=[self selectedTab]; SPDFTabGroup* group=original.group;
    original.collectionHistoryDocumentID=document[@"id"]; original.pageIndex=1;
    NSURL* existingCopy=[store editableVersionID:nil documentID:document[@"id"] error:nil];
    SPDFDocumentTab* duplicate=[SPDFDocumentTab new]; duplicate.path=existingCopy.path;
    duplicate.group=SPDFTabGroup.generalGroup; duplicate.collectionHistoryDocumentID=document[@"id"]; [_tabs addObject:duplicate];
    // Exactly the Safari failure: stat succeeds while reading returns a permission error.
    chmod(URL.fileSystemRepresentation,0000);
    Check([NSFileManager.defaultManager attributesOfItemAtPath:URL.path error:nil]!=nil &&
        [NSData dataWithContentsOfURL:URL]==nil,@"metadata-visible source is unreadable");
    NSString* mode=NSProcessInfo.processInfo.environment[@"SPDF_COLLECTION_FAILURE_MODE"];
    if ([mode isEqual:@"missing"]) [NSFileManager.defaultManager removeItemAtURL:URL error:nil];
    if ([mode isEqual:@"invalid"]) {
        chmod(URL.fileSystemRepresentation,0600);
        [@"broken document" writeToURL:URL atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    [self loadSelectedTab];
    NSDate* deadline=[NSDate dateWithTimeIntervalSinceNow:10];
    while ((!_doc || [_path isEqual:URL.path]) && deadline.timeIntervalSinceNow>0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    Check(_doc && spdf_page_count(_doc)>0 && ![_path isEqual:URL.path],@"real loader renders Collection after an existing source cannot be read");
    Check([self selectedTab]==original && original.group==group && original.pageIndex==1,@"fallback preserves the original tab group and page");
    Check(_tabs.count==5 && self.openErrors==0,@"recovery adds no duplicate tab or error dialog");
    Check(!original.readOnly && [store editableInfoForPath:original.path]!=nil,@"actual loaded document is editable");
    NSDictionary* info=[store editableInfoForPath:original.path];
    Check(!SPDFCollectionOriginalAvailable(info[@"document"]),@"failed source remains unavailable despite successful stat");
    [_window.contentView layoutSubtreeIfNeeded]; [self updateControls]; [_window.contentView layoutSubtreeIfNeeded];
    NSMutableArray* controls=[NSMutableArray array]; VisibleControls(_toolbar,controls);
    NSButton* pill=nil; NSButton* locate=nil;
    for (NSControl* control in controls) {
        if ([control.identifier isEqual:@"CollectionVersionIndicator"]) pill=(id)control;
        if ([control.identifier isEqual:@"CollectionLocateDocument"]) locate=(id)control;
    }
    Check(pill && locate && [pill valueForKey:@"missing"] && [[pill valueForKey:@"missing"] boolValue],@"native toolbar contains red status and Locate action");
    NSRect rect=[pill convertRect:pill.bounds toView:_toolbar];
    Check(pill && NSContainsRect(_toolbar.bounds,rect) && _toolbarHeightConstraint.constant>=64,
        @"the status row fits inside the real reader toolbar instead of being clipped");
    spdf_bitmap bitmap={}; char renderError[1024]={};
    BOOL rendered=_doc && spdf_render_page_rgba(_doc,0,1,&bitmap,renderError,sizeof(renderError));
    Check(rendered && bitmap.width>0 && bitmap.height>0,@"MuPDF renders actual recovered document pixels");
    spdf_free_bitmap(&bitmap);
    if (getenv("SPDF_COLLECTION_TOOLBAR_CAPTURE")) {
        NSBitmapImageRep* image=[_toolbar bitmapImageRepForCachingDisplayInRect:_toolbar.bounds];
        [_toolbar cacheDisplayInRect:_toolbar.bounds toBitmapImageRep:image];
        Check([[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
            writeToFile:@(getenv("SPDF_COLLECTION_TOOLBAR_CAPTURE")) atomically:YES],@"real toolbar renders offscreen");
    }
    Check(!_window.visible,@"reader fixture never displays a window");
    chmod(URL.fileSystemRepresentation,0600);
    NSData* recovered=[NSData dataWithContentsOfURL:existingCopy];
    [recovered writeToURL:URL atomically:YES];
    [store capturePath:URL.path reason:@"Restored original" continuingDocumentID:document[@"id"] error:nil];
    [self discardCachedRuntimeForTab:original]; original.path=URL.path; original.workingPath=nil;
    [self collectionSetVersionInfo:nil forTab:original]; [self loadSelectedTab];
    Check(_doc && [_path isEqual:URL.path],@"restored original can be opened again");
    chmod(URL.fileSystemRepresentation,0000); [self loadSelectedTab];
    deadline=[NSDate dateWithTimeIntervalSinceNow:10];
    while ((!_doc || [_path isEqual:URL.path]) && deadline.timeIntervalSinceNow>0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    Check(_doc && ![_path isEqual:URL.path] && original==[self selectedTab] && original.group==group,
        @"a second access loss on the same tab recovers again instead of getting stuck");
    chmod(URL.fileSystemRepresentation,0600);
}
@end

static int CheckCollectionFailedReadFixture(NSURL* URL,NSString* root) {
    const char* sample=getenv("SPDF_COLLECTION_FAILURE_SAMPLE");
    if (sample) {
        URL=[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"Safari collection copy.pdf"]];
        Check([[NSData dataWithContentsOfFile:@(sample)] writeToURL:URL atomically:YES],@"private sample copied into isolated fixture");
    }
    CollectionFailedReadProbe* reader=[CollectionFailedReadProbe new]; [reader prepare:URL width:1280 dark:YES];
    [reader checkFailedSource:URL];
    printf("Collection failed-read checks: %lu failures\n",(unsigned long)failures);
    return failures ? 1 : 0;
}
