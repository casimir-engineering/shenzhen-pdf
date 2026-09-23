#import "SPDFMacCollectionWindowPrivate.h"
#import "SPDFMacCollectionAvailability.h"
#import "SPDFMacCollectionStyle.h"
static NSString* RowKey(NSDictionary* row) {
    return [NSString stringWithFormat:@"%@/%@",row[@"document"][@"id"],row[@"version"][@"id"] ?: @""];
}
static NSString* DateLabel(NSDictionary* version) {
    return version[@"capturedAt"] ? [NSDateFormatter localizedStringFromDate:
        [NSDate dateWithTimeIntervalSince1970:[version[@"capturedAt"] doubleValue]]
        dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle] : @"No saved copy";
}
@interface SPDFCollectionResultRow : NSTableRowView
@end
@implementation SPDFCollectionResultRow
- (void)drawSelectionInRect:(NSRect)dirtyRect {
    (void)dirtyRect; [SPDFCollectionColor(@"selected") setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,10,2) xRadius:5 yRadius:5] fill];
}
@end
@implementation SPDFMacCollectionWindow (SearchResults)
- (NSTableRowView*)tableView:(NSTableView*)tableView rowViewForRow:(NSInteger)row {
    (void)tableView; (void)row; return [SPDFCollectionResultRow new];
}
- (CGFloat)tableView:(NSTableView*)tableView heightOfRow:(NSInteger)index {
    (void)tableView; NSDictionary* row = self.rows[(NSUInteger)index];
    NSUInteger count = [row[@"matches"] count];
    NSUInteger visible = [self.expandedResults containsObject:RowKey(row)] ? count : MIN(3,count);
    return 78 + MAX(110,visible*68) + (count>3 ? 30 : 0) + ([row[@"truncated"] boolValue] ? 36 : 0);
}
- (NSView*)resultCellForRow:(NSInteger)index {
    NSDictionary* row = self.rows[(NSUInteger)index], *doc = row[@"document"], *version = row[@"version"];
    NSView* cell = [NSView new];
    NSTextField* title = SPDFCollectionText(version[@"filename"] ?: doc[@"title"] ?: @"Document",13,NSFontWeightSemibold,NO);
    title.lineBreakMode = NSLineBreakByTruncatingMiddle; title.maximumNumberOfLines = 1; title.toolTip = doc[@"path"];
    title.translatesAutoresizingMaskIntoConstraints = NO; [cell addSubview:title];
    NSButton* history = SPDFCollectionButton(@"History",self,@selector(historyForRow:),@"normal"); history.tag = index;
    history.accessibilityLabel = [@"History for " stringByAppendingString:doc[@"title"] ?: @"document"];
    history.translatesAutoresizingMaskIntoConstraints = NO; [cell addSubview:history];
    NSButton* more = SPDFCollectionButton(@"…",self,@selector(showDocumentMenu:),@"quiet"); more.tag = index;
    more.accessibilityLabel = [@"More actions for " stringByAppendingString:doc[@"title"] ?: @"document"];
    more.translatesAutoresizingMaskIntoConstraints = NO; [cell addSubview:more];
    NSString* latest = [version[@"id"] isEqual:doc[@"latestVersionID"]] || [row[@"latest"] boolValue] ? @"Latest saved copy" : @"Older saved version";
    NSTextField* meta = SPDFCollectionText([NSString stringWithFormat:@"%@ · %@%@",latest,DateLabel(version),
        [version[@"keep"] boolValue] ? @" · Kept" : @""],12,NSFontWeightRegular,YES);
    meta.translatesAutoresizingMaskIntoConstraints = NO; [cell addSubview:meta];
    NSImageView* image = [NSImageView new]; image.translatesAutoresizingMaskIntoConstraints = NO;
    image.imageScaling = NSImageScaleProportionallyUpOrDown;
    NSInteger page = [row[@"selectedPage"] integerValue];
    if (!page && [row[@"matches"] count]) page = [row[@"matches"][0][@"page"] integerValue];
    NSString* key = [RowKey(row) stringByAppendingFormat:@"/%ld",(long)page];
    image.identifier = key; image.image = [self.thumbnailCache objectForKey:key] ?: [NSImage imageWithSystemSymbolName:
        [version[@"encrypted"] boolValue] ? @"lock.doc" : @"doc" accessibilityDescription:@"Saved page preview"];
    image.accessibilityLabel = page>0 ? [NSString stringWithFormat:@"Page %ld preview",(long)page] : @"Saved copy preview";
    [cell addSubview:image];
    if (version[@"id"] && ![version[@"encrypted"] boolValue]) {
        NSMutableDictionary* thumbnailRow = [row mutableCopy]; thumbnailRow[@"selectedPage"] = @(page);
        [self requestThumbnail:thumbnailRow key:key];
    }
    NSStackView* text = [NSStackView stackViewWithViews:@[]]; text.translatesAutoresizingMaskIntoConstraints = NO;
    text.orientation = NSUserInterfaceLayoutOrientationVertical; text.alignment = NSLayoutAttributeLeading; text.spacing = 8;
    [cell addSubview:text];
    NSArray* matches = row[@"matches"] ?: @[];
    NSUInteger visible = [self.expandedResults containsObject:RowKey(row)] ? matches.count : MIN(3,matches.count);
    for (NSUInteger i=0;i<visible;i++) {
        NSDictionary* match = matches[i]; NSString* snippet = match[@"snippet"] ?: @"";
        NSString* prefix = [match[@"page"] integerValue]>0 ? [NSString stringWithFormat:@"p. %@\t",match[@"page"]] : @"Text\t";
        NSMutableAttributedString* caption = [[NSMutableAttributedString alloc] initWithString:[prefix stringByAppendingString:snippet]
            attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:13],NSForegroundColorAttributeName:SPDFCollectionColor(@"text")}];
        [caption addAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:12],NSForegroundColorAttributeName:SPDFCollectionColor(@"secondary")}
            range:NSMakeRange(0,prefix.length)];
        for (NSValue* value in match[@"ranges"]) {
            NSRange range = value.rangeValue; range.location += prefix.length;
            if (NSMaxRange(range)<=caption.length) [caption addAttributes:@{NSBackgroundColorAttributeName:SPDFCollectionColor(@"highlight"),
                NSFontAttributeName:[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]} range:range];
        }
        NSButton* hit = SPDFCollectionButton(@"",self,@selector(selectSearchMatch:),@"match");
        hit.alignment = NSTextAlignmentLeft; hit.attributedTitle = caption; hit.cell.wraps = YES;
        hit.cell.lineBreakMode = NSLineBreakByWordWrapping; hit.tag = index; hit.identifier = [NSString stringWithFormat:@"%lu",(unsigned long)i];
        hit.toolTip = [prefix stringByAppendingString:snippet];
        hit.state = row[@"selectedMatchIndex"] && [row[@"selectedMatchIndex"] unsignedIntegerValue]==i ? NSControlStateValueOn : NSControlStateValueOff;
        [hit.heightAnchor constraintEqualToConstant:60].active = YES; [text addArrangedSubview:hit];
        [hit.widthAnchor constraintEqualToAnchor:text.widthAnchor].active = YES;
        [hit setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    if (!matches.count) {
        NSString* status = self.search.stringValue.length ? ([row[@"textAvailable"] boolValue] ?
            @"Title match · no matching saved text" : @"Title match · saved text is not indexed") :
            (SPDFCollectionOriginalAvailable(doc) ? @"Original available. Saved copies are read-only." : @"Original unavailable. Saved copies are read-only.");
        NSTextField* label = SPDFCollectionText(status,12,NSFontWeightRegular,YES); [text addArrangedSubview:label];
        NSButton* preview = SPDFCollectionButton(@"Preview saved copy",self,@selector(previewForRow:),@"normal");
        preview.tag = index; preview.enabled = [version[@"id"] length]>0; [text addArrangedSubview:preview];
    }
    if (matches.count>3) {
        BOOL expanded = [self.expandedResults containsObject:RowKey(row)];
        NSButton* expand = SPDFCollectionButton(expanded ? @"Show fewer matches" :
            [NSString stringWithFormat:@"Show %lu more matches",(unsigned long)matches.count-3],self,@selector(toggleMatches:),@"link");
        expand.tag = index; [text addArrangedSubview:expand];
    }
    if ([row[@"truncated"] boolValue]) [text addArrangedSubview:SPDFCollectionText([NSString stringWithFormat:
        @"Showing %lu contexts from %@ text matches. Refine your search to narrow results.",(unsigned long)matches.count,
        row[@"matchCount"] ?: @(matches.count)],12,NSFontWeightRegular,YES)];
    NSView* divider = SPDFCollectionDivider(); divider.translatesAutoresizingMaskIntoConstraints = NO; [cell addSubview:divider];
    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:20],[title.topAnchor constraintEqualToAnchor:cell.topAnchor constant:13],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:history.leadingAnchor constant:-12],
        [history.trailingAnchor constraintEqualToAnchor:more.leadingAnchor constant:-6],[history.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [more.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-20],[more.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [meta.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[meta.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4],
        [meta.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-20],
        [image.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[image.topAnchor constraintEqualToAnchor:meta.bottomAnchor constant:10],
        [image.widthAnchor constraintEqualToConstant:84],[image.heightAnchor constraintEqualToConstant:110],
        [text.leadingAnchor constraintEqualToAnchor:image.trailingAnchor constant:16],[text.topAnchor constraintEqualToAnchor:image.topAnchor],
        [text.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-20],
        [divider.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[divider.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-20],
        [divider.bottomAnchor constraintEqualToAnchor:cell.bottomAnchor constant:-1]]];
    return cell;
}
- (void)previewForRow:(NSControl*)sender {
    NSInteger index = sender.tag; if (index<0 || index>=(NSInteger)self.rows.count) return;
    [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO]; [self preview:nil];
}
- (void)showDocumentMenu:(NSControl*)sender {
    if (sender.tag>=0 && sender.tag<(NSInteger)self.rows.count)
        [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:sender.tag] byExtendingSelection:NO];
    NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Document actions"]; [self populateDocumentMenu:menu];
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0,NSHeight(sender.bounds)) inView:sender];
}
- (void)menuNeedsUpdate:(NSMenu*)menu {
    NSInteger index = self.table.clickedRow;
    if (index>=0 && ![self.table.selectedRowIndexes containsIndex:index])
        [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
    [self populateDocumentMenu:menu];
}
- (void)populateDocumentMenu:(NSMenu*)menu {
    [self updateDetails]; [menu removeAllItems]; menu.autoenablesItems = NO;
    for (NSButton* command in self.selectionButtons) {
        NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:command.title action:command.action keyEquivalent:@""];
        item.target = self; item.enabled = command.enabled; [menu addItem:item];
    }
}
- (void)historyForRow:(NSControl*)sender {
    NSInteger index = sender.tag; if (index < 0 || index >= (NSInteger)self.rows.count) return;
    [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO]; [self history:nil];
}
- (void)toggleMatches:(NSControl*)sender {
    NSInteger index = sender.tag; if (index < 0 || index >= (NSInteger)self.rows.count) return;
    NSString* key = RowKey(self.rows[(NSUInteger)index]);
    if ([self.expandedResults containsObject:key]) [self.expandedResults removeObject:key]; else [self.expandedResults addObject:key];
    NSIndexSet* indexes = [NSIndexSet indexSetWithIndex:index]; [self.table noteHeightOfRowsWithIndexesChanged:indexes];
    [self.table reloadDataForRowIndexes:indexes columnIndexes:[NSIndexSet indexSetWithIndex:0]];
    [self persistManagerPreferences];
}
- (void)selectSearchMatch:(NSControl*)sender {
    NSInteger index = sender.tag, matchIndex = sender.identifier.integerValue;
    if (index < 0 || index >= (NSInteger)self.rows.count) return;
    NSMutableDictionary* row = [self.rows[(NSUInteger)index] mutableCopy]; NSArray* matches = row[@"matches"];
    if (matchIndex < 0 || matchIndex >= (NSInteger)matches.count) return;
    row[@"selectedPage"] = matches[(NSUInteger)matchIndex][@"page"] ?: @0;
    row[@"selectedMatch"] = matches[(NSUInteger)matchIndex];
    row[@"selectedMatchIndex"] = @(matchIndex);
    NSMutableArray* rows = [self.rows mutableCopy]; rows[(NSUInteger)index] = row; self.rows = rows;
    [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
    [self.table reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:index] columnIndexes:[NSIndexSet indexSetWithIndex:0]];
    [self showHistoryForDocument:row[@"document"] version:row[@"version"]];
}
@end
