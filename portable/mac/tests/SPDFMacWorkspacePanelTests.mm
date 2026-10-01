#import "SPDFMacWorkspacePanels.h"
#import "SPDFMacMarkdownDelegatePrivate.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wprotocol"
@implementation ShenzhenMacDelegate
@end
#pragma clang diagnostic pop
@interface PanelProbe : ShenzhenMacDelegate
@property NSUInteger changes;
@property NSMutableDictionary* workspace;
- (void)seed;
- (void)resize:(CGFloat)width;
- (NSDictionary*)snapshot;
@end
@implementation PanelProbe
- (void)seed {
    self.workspace = [NSMutableDictionary dictionary];
    _splitView = [[NSSplitView alloc] initWithFrame:NSMakeRect(0,0,1280,780)];
    _sidebarWidth=284; _minimapWidth=126.5;
    _sidebarPreferredVisible=YES; _minimapPreferredVisible=YES;
    _sidebarVisible=YES; _minimapVisible=YES; _allowSidebarWidthPersistence=YES;
}
- (NSMutableDictionary*)sidebarWorkspaceState { return self.workspace; }
- (BOOL)hasActiveDocument { return YES; }
- (CGFloat)clampedSidebarWidth { return MAX(176,MIN(_sidebarWidth,floor(NSWidth(_splitView.bounds)*.34))); }
- (void)setWorkspaceSidebarVisibleWithoutPolicy:(BOOL)visible {
    if (_sidebarVisible != visible) self.changes++;
    _sidebarVisible=visible;
    if (_allowSidebarWidthPersistence && !visible) _sidebarWidth=190; // catches accidental persistence during suppression
}
- (void)setWorkspaceMapVisibleWithoutPolicy:(BOOL)visible {
    if (_minimapVisible != visible) self.changes++;
    _minimapVisible=visible;
}
- (void)resize:(CGFloat)width { [_splitView setFrameSize:NSMakeSize(width,780)]; [self applyWorkspacePanelPolicy]; }
- (NSDictionary*)snapshot { return @{@"sidebar":@(_sidebarVisible),@"map":@(_minimapVisible),
    @"sidebarRequested":@(_sidebarPreferredVisible),@"mapRequested":@(_minimapPreferredVisible),
    @"sidebarWidth":@(_sidebarWidth),@"mapWidth":@(_minimapWidth),@"persist":@(_allowSidebarWidthPersistence)}; }
@end
static int failures;
static void Check(BOOL ok,const char* message) { if(!ok) { fprintf(stderr,"FAIL %s\n",message);failures++; } }
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    PanelProbe* p=[PanelProbe new]; [p seed];
    [p applyWorkspacePanelPolicy]; Check(p.changes==0,"policy is lazy before panel construction");
    [p setSidebarActuallyVisible:YES]; [p setMinimapActuallyVisible:YES];
    NSDictionary* before=p.snapshot;
    [p resize:560]; Check([p.snapshot[@"sidebar"] boolValue] && ![p.snapshot[@"map"] boolValue],"compact reader prioritizes navigation");
    Check([p.snapshot[@"sidebarWidth"] isEqual:before[@"sidebarWidth"]] && [p.snapshot[@"mapWidth"] isEqual:before[@"mapWidth"]],"compact layout retains exact preferred widths");
    Check([p.snapshot[@"sidebarRequested"] boolValue] && [p.snapshot[@"mapRequested"] boolValue] && [p.snapshot[@"persist"] boolValue],"suppression preserves requested visibility and persistence state");
    [p prioritizeWorkspaceMap]; [p setMinimapActuallyVisible:YES];
    Check(![p.snapshot[@"sidebar"] boolValue] && [p.snapshot[@"map"] boolValue],"explicit map reveal wins in one operation");
    PanelProbe* restored=[PanelProbe new]; [restored seed]; restored.workspace=[p.workspace mutableCopy];
    [restored setSidebarActuallyVisible:YES]; [restored setMinimapActuallyVisible:YES]; [restored resize:560];
    Check(![restored.snapshot[@"sidebar"] boolValue] && [restored.snapshot[@"map"] boolValue],"restored compact priority shows the same last-used panel");
    [p prioritizeWorkspaceSidebar]; [p setSidebarActuallyVisible:YES];
    Check([p.snapshot[@"sidebar"] boolValue] && ![p.snapshot[@"map"] boolValue],"explicit sidebar reveal wins");
    [p resize:1280]; Check([p.snapshot[@"sidebar"] boolValue] && [p.snapshot[@"map"] boolValue],"enlarging restores both requested panels");
    Check([p.snapshot[@"sidebarWidth"] isEqual:@284],"restored sidebar width remains the requested 284 points");
    [p setSidebarActuallyVisible:NO]; [p resize:560]; Check(![p.snapshot[@"sidebar"] boolValue] && [p.snapshot[@"map"] boolValue],"explicitly hidden sidebar stays hidden");
    [p resize:1280]; Check(![p.snapshot[@"sidebar"] boolValue],"enlarging cannot revive a hidden sidebar");
    NSUInteger changes=p.changes; for(int i=0;i<1000;i++) [p applyWorkspacePanelPolicy];
    Check(p.changes==changes,"unchanged policy produces no repeated visibility transitions");
    puts(failures ? "Workspace panel tests failed" : "Workspace panel tests passed"); return failures ? 1 : 0;
} }
