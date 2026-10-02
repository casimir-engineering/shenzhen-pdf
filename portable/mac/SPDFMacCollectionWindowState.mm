#import "SPDFMacCollectionWindowPrivate.h"
static NSString* RowIdentity(NSDictionary* row) {
    return [NSString stringWithFormat:@"%@/%@",row[@"document"][@"id"] ?: @"",row[@"version"][@"id"] ?: @""];
}
@implementation SPDFMacCollectionWindow (BrowsingState)
- (NSDictionary*)captureBrowseState {
    if (!self.hasLoadedResults) return self.initialBrowseState ?: @{};
    NSMutableArray* selection = [NSMutableArray array];
    NSMutableArray* documents = [NSMutableArray array];
    [self.table.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger index,BOOL* stop) {
        (void)stop; if (index < self.rows.count) {
            [selection addObject:RowIdentity(self.rows[index])];
            NSString* identifier = self.rows[index][@"document"][@"id"];
            if (identifier) [documents addObject:identifier];
        }
    }];
    NSMutableDictionary* matches = [NSMutableDictionary dictionary];
    for (NSDictionary* row in self.rows) if (row[@"selectedPage"]) {
        NSUInteger matchIndex = [row[@"selectedMatchIndex"] unsignedIntegerValue];
        if (!row[@"selectedMatchIndex"] && row[@"selectedMatch"])
            matchIndex = [row[@"matches"] indexOfObject:row[@"selectedMatch"]];
        matches[RowIdentity(row)] = @{@"page":row[@"selectedPage"],@"index":@(matchIndex)};
    }
    NSPoint list = self.listScroll.contentView.bounds.origin;
    return @{@"query":self.resultQuery ?: self.search.stringValue,@"selection":selection,@"selectedDocuments":documents,@"matches":matches,
        @"expanded":self.expandedResults.allObjects,@"listX":@(list.x),@"listY":@(list.y)};
}
- (void)restoreBrowseState:(NSDictionary*)state toRows:(NSMutableArray*)rows query:(NSString*)query {
    // Match indices only describe the same query and immutable archived version.
    // A changed query must never reuse an unrelated hit just because its index matches.
    if (![state[@"query"] isEqual:query]) return;
    NSDictionary* contexts = [state[@"matches"] isKindOfClass:NSDictionary.class] ? state[@"matches"] : @{};
    for (NSUInteger i=0;i<rows.count;i++) {
        NSDictionary* saved = contexts[RowIdentity(rows[i])]; if (![saved isKindOfClass:NSDictionary.class]) continue;
        NSMutableDictionary* row = [rows[i] mutableCopy];
        NSArray* matches = row[@"matches"] ?: @[]; NSUInteger index = [saved[@"index"] unsignedIntegerValue];
        if (index < matches.count) {
            row[@"selectedMatchIndex"] = @(index); row[@"selectedMatch"] = matches[index];
            row[@"selectedPage"] = matches[index][@"page"] ?: @0;
        } else if (!query.length && saved[@"page"]) row[@"selectedPage"] = saved[@"page"];
        rows[i] = row;
    }
}
- (void)restoreBrowseSelectionAndScroll:(NSDictionary*)state {
    NSArray* selection = [state[@"selection"] isKindOfClass:NSArray.class] ? state[@"selection"] : @[];
    NSMutableIndexSet* selected = [NSMutableIndexSet indexSet];
    NSArray* documents = [state[@"selectedDocuments"] isKindOfClass:NSArray.class] ? state[@"selectedDocuments"] : @[];
    for (NSUInteger i=0;i<self.rows.count;i++)
        if ([selection containsObject:RowIdentity(self.rows[i])] || [documents containsObject:self.rows[i][@"document"][@"id"]])
            [selected addIndex:i];
    [self.table selectRowIndexes:selected byExtendingSelection:NO];
    [self.window.contentView layoutSubtreeIfNeeded];
    // Restore after row heights and list layout settle; reloading a table can otherwise
    // reset the clip origin even though History never changed the user's result list.
    if ([state[@"query"] isEqual:self.search.stringValue]) {
        [self.listScroll.contentView scrollToPoint:NSMakePoint([state[@"listX"] doubleValue],[state[@"listY"] doubleValue])];
        [self.listScroll reflectScrolledClipView:self.listScroll.contentView];
    }
}
@end
