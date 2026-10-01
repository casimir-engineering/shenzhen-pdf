#import "SPDFMacWorkspacePanels.h"
#import "SPDFMacMarkdownDelegatePrivate.h"
#import "SPDFMacSidebarWorkspace.h"
#import <objc/runtime.h>

static char panelPolicyKey;
@interface SPDFWorkspacePanelPolicy : NSObject
@property BOOL sidebarRequested;
@property BOOL mapRequested;
@property BOOL applying;
@end
@implementation SPDFWorkspacePanelPolicy
@end

@interface ShenzhenMacDelegate (WorkspacePanelGeometry)
- (CGFloat)clampedSidebarWidth;
@end

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
@implementation ShenzhenMacDelegate (SPDFMacWorkspacePanels)
- (SPDFWorkspacePanelPolicy*)workspacePanelPolicy {
    SPDFWorkspacePanelPolicy* state = objc_getAssociatedObject(self,&panelPolicyKey);
    if (!state) {
        state = [SPDFWorkspacePanelPolicy new];
        state.sidebarRequested = _sidebarPreferredVisible;
        state.mapRequested = _minimapPreferredVisible;
        objc_setAssociatedObject(self,&panelPolicyKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}
- (BOOL)workspacePanelPolicyIsApplying {
    return [(SPDFWorkspacePanelPolicy*)objc_getAssociatedObject(self,&panelPolicyKey) applying];
}
- (void)prioritizeWorkspaceSidebar { [self sidebarWorkspaceState][@"compactPanel"] = @"sidebar"; }
- (void)prioritizeWorkspaceMap { [self sidebarWorkspaceState][@"compactPanel"] = @"map"; }
- (void)setSidebarActuallyVisible:(BOOL)visible {
    SPDFWorkspacePanelPolicy* state = [self workspacePanelPolicy];
    if (state.applying) return;
    state.sidebarRequested = visible;
    [self applyWorkspacePanelPolicy];
}
- (void)setMinimapActuallyVisible:(BOOL)visible {
    SPDFWorkspacePanelPolicy* state = [self workspacePanelPolicy];
    if (state.applying) return;
    state.mapRequested = visible;
    [self applyWorkspacePanelPolicy];
}
- (void)applyWorkspacePanelPolicy {
    SPDFWorkspacePanelPolicy* state = objc_getAssociatedObject(self,&panelPolicyKey);
    if (!state || state.applying || !_splitView) return;
    BOOL sidebar = state.sidebarRequested, map = state.mapRequested && [self hasActiveDocument];
    CGFloat width = NSWidth(_splitView.bounds);
    CGFloat sidebarWidth = [self clampedSidebarWidth];
    // This is a layout budget, not a stored preference or a new document zoom.
    // The active navigation panel wins while there is insufficient reading room.
    if (sidebar && map && width > 0 && width-sidebarWidth-_minimapWidth-8 < 320) {
        if ([[self sidebarWorkspaceState][@"compactPanel"] isEqual:@"map"]) sidebar = NO; else map = NO;
    }
    state.applying = YES;
    BOOL persistWidth = _allowSidebarWidthPersistence;
    _allowSidebarWidthPersistence = NO;
    // Remove the losing panel first; avoid an intermediate squeezed viewport.
    if (!sidebar) [self setWorkspaceSidebarVisibleWithoutPolicy:NO];
    if (!map) [self setWorkspaceMapVisibleWithoutPolicy:NO];
    if (sidebar) [self setWorkspaceSidebarVisibleWithoutPolicy:YES];
    if (map) [self setWorkspaceMapVisibleWithoutPolicy:YES];
    _allowSidebarWidthPersistence = persistWidth;
    state.applying = NO;
}
@end

#pragma clang diagnostic pop
