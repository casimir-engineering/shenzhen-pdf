#import "SPDFMacCollectionIntegration.h"
#import "SPDFMacCollectionHistory.h"
#import "SPDFMacCollectionStore.h"
#import "SPDFMacMarkdownDelegatePrivate.h"
#import <objc/runtime.h>
static char historyControllerKey, historyWrapperKey, historyHiddenKey, historyDocumentKey;
@implementation ShenzhenMacDelegate (SPDFMacCollectionSidebar)
- (void)showCollectionHistory:(id)sender {
    NSString* path = [sender respondsToSelector:@selector(representedObject)] && [[sender representedObject] isKindOfClass:NSString.class]
        ? [sender representedObject] : _path;
    SPDFMacCollectionStore* store = [SPDFMacCollectionStore defaultStore];
    NSDictionary* doc = [store documentForPath:path] ?: [store archiveInfoForPath:path][@"document"];
    if (!doc[@"id"]) { [self showCollectionManager:nil]; return; }
    [self collectionRemoveHistoryView];
    __weak ShenzhenMacDelegate* weakSelf = self;
    SPDFMacCollectionHistoryController* controller = [[SPDFMacCollectionHistoryController alloc]
        initWithStore:store documentID:doc[@"id"] open:^(NSString* openPath, BOOL archived) {
            [weakSelf collectionOpenPath:openPath archived:archived];
        }];
    objc_setAssociatedObject(self, &historyControllerKey, controller, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &historyDocumentKey, doc[@"id"], OBJC_ASSOCIATION_COPY_NONATOMIC);
    NSMutableArray* hidden = [NSMutableArray array];
    for (NSView* view in _sidebarContainer.subviews) { [hidden addObject:@{@"view":view,@"hidden":@(view.hidden)}]; view.hidden = YES; }
    objc_setAssociatedObject(self, &historyHiddenKey, hidden, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSVisualEffectView* wrapper = [[NSVisualEffectView alloc] initWithFrame:_sidebarContainer.bounds];
    wrapper.material = NSVisualEffectMaterialSidebar; wrapper.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    wrapper.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    NSButton* close = [NSButton buttonWithTitle:@"‹ Back to document panels" target:self action:@selector(closeCollectionHistory:)];
    close.translatesAutoresizingMaskIntoConstraints = NO; [wrapper addSubview:close];
    NSView* content = controller.view; content.translatesAutoresizingMaskIntoConstraints = NO; [wrapper addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [close.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor constant:8],
        [close.topAnchor constraintEqualToAnchor:wrapper.topAnchor constant:8],
        [content.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:close.bottomAnchor constant:4],
        [content.bottomAnchor constraintEqualToAnchor:wrapper.bottomAnchor]]];
    [_sidebarContainer addSubview:wrapper];
    objc_setAssociatedObject(self, &historyWrapperKey, wrapper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self selectedTab].collectionHistoryDocumentID = doc[@"id"];
    _sidebarPreferredVisible = YES; _sidebarWidth = MAX(280, _sidebarWidth);
    [self setSidebarActuallyVisible:YES]; [self savePersistentState];
}
- (void)collectionRemoveHistoryView {
    NSView* wrapper = objc_getAssociatedObject(self, &historyWrapperKey); [wrapper removeFromSuperview];
    for (NSDictionary* item in objc_getAssociatedObject(self, &historyHiddenKey)) [(NSView*)item[@"view"] setHidden:[item[@"hidden"] boolValue]];
    objc_setAssociatedObject(self, &historyControllerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &historyWrapperKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &historyHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &historyDocumentKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)closeCollectionHistory:(id)sender {
    (void)sender; [self selectedTab].collectionHistoryDocumentID = nil;
    [self collectionRemoveHistoryView]; [self rebuildSidebar]; [self savePersistentState];
}
- (void)collectionPrepareForTabPath:(NSString*)path {
    NSString* identifier = objc_getAssociatedObject(self, &historyDocumentKey); if (!identifier) return;
    SPDFMacCollectionStore* store = [SPDFMacCollectionStore defaultStore];
    NSDictionary* doc = [store documentForPath:path] ?: [store archiveInfoForPath:path][@"document"];
    if ([identifier isEqual:doc[@"id"]]) [self selectedTab].collectionHistoryDocumentID = identifier;
    else [self collectionRemoveHistoryView];
}
- (void)collectionRefreshHistory {
    SPDFMacCollectionHistoryController* controller = objc_getAssociatedObject(self, &historyControllerKey);
    if (controller) {
        [controller reload];
        [self setSidebarActuallyVisible:YES];
    } else if ([self selectedTab].collectionHistoryDocumentID.length) [self showCollectionHistory:nil];
}
@end
