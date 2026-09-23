#import "SPDFMacCollectionWindowHistory.h"
#import "SPDFMacCollectionWindowPrivate.h"
#import "SPDFMacCollectionHistoryDetail.h"
#import <objc/runtime.h>

static char historyControllerKey, historyReturnSelectionKey;
@implementation SPDFMacCollectionWindow (HistoryDetail)
- (void)showHistoryForDocument:(NSDictionary*)document version:(NSDictionary*)version {
    if (![document[@"id"] length]) return;
    objc_setAssociatedObject(self, &historyReturnSelectionKey, self.table.selectedRowIndexes,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
    [(SPDFMacCollectionHistoryDetailController*)objc_getAssociatedObject(self,&historyControllerKey) invalidate];
    [self.historyPane removeFromSuperview];
    NSDictionary* preferences = self.store.settings;
    BOOL restoring = [preferences[@"managerHistoryDocumentID"] isEqual:document[@"id"]] &&
        [preferences[@"managerHistoryVersionID"] isEqual:version[@"id"]];
    NSUInteger page = restoring ? MAX(1,[preferences[@"managerHistoryPage"] integerValue]) : 1;
    // Search rows may supply an exact matching page rather than a saved reading position.
    if ([version[@"page"] unsignedIntegerValue]) page = [version[@"page"] unsignedIntegerValue];
    NSInteger row = self.table.selectedRow;
    if (row >= 0 && row < (NSInteger)self.rows.count) {
        NSDictionary* selected = self.rows[(NSUInteger)row];
        if ([selected[@"version"][@"id"] isEqual:version[@"id"]] && [selected[@"selectedPage"] unsignedIntegerValue])
            page = [selected[@"selectedPage"] unsignedIntegerValue];
    }
    SPDFMacCollectionHistoryDetailController* controller = [[SPDFMacCollectionHistoryDetailController alloc]
        initWithStore:self.store document:document version:version page:page actionTarget:self];
    controller.searchQuery = self.search.stringValue;
    objc_setAssociatedObject(self, &historyControllerKey, controller, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak SPDFMacCollectionWindow* weakSelf = self;
    controller.back = ^{ [weakSelf returnFromCollectionHistory:nil]; };
    controller.selectionChanged = ^{ [weakSelf updateDetails]; };
    self.historyPane = controller.view;
    self.historyPane.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentHost addSubview:self.historyPane];
    [NSLayoutConstraint activateConstraints:@[
        [self.historyPane.leadingAnchor constraintEqualToAnchor:self.contentHost.leadingAnchor],
        [self.historyPane.trailingAnchor constraintEqualToAnchor:self.contentHost.trailingAnchor],
        [self.historyPane.topAnchor constraintEqualToAnchor:self.contentHost.topAnchor],
        [self.historyPane.bottomAnchor constraintEqualToAnchor:self.contentHost.bottomAnchor]]];
    [self showDestination:@"History"];
    [self persistManagerPreferences];
    [self updateDetails];
}
- (NSDictionary*)historySelectedDocument {
    if (!self.historyPane || self.historyPane.hidden) return nil;
    return [(SPDFMacCollectionHistoryDetailController*)objc_getAssociatedObject(self, &historyControllerKey) document];
}
- (NSDictionary*)historySelectedVersion {
    if (!self.historyPane || self.historyPane.hidden) return nil;
    return [(SPDFMacCollectionHistoryDetailController*)objc_getAssociatedObject(self, &historyControllerKey) selectedVersion];
}
- (void)returnFromCollectionHistory:(id)sender {
    (void)sender;
    [(SPDFMacCollectionHistoryDetailController*)objc_getAssociatedObject(self,&historyControllerKey) invalidate];
    [self showDestination:@"Documents"];
    NSIndexSet* selection = objc_getAssociatedObject(self, &historyReturnSelectionKey);
    if (selection.lastIndex != NSNotFound && selection.lastIndex < self.rows.count)
        [self.table selectRowIndexes:selection byExtendingSelection:NO];
    [self.window makeFirstResponder:self.table];
    [self reload:nil];
}
@end
