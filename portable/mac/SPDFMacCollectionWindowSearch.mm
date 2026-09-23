#import "SPDFMacCollectionWindowPrivate.h"
#import "SPDFMacCollectionAvailability.h"
static NSString* RowKey(NSDictionary* row) {
    return [NSString stringWithFormat:@"%@/%@",row[@"document"][@"id"],row[@"version"][@"id"] ?: @""];
}
static NSString* DateLabel(NSDictionary* version) {
    return version[@"capturedAt"] ? [NSDateFormatter localizedStringFromDate:
        [NSDate dateWithTimeIntervalSince1970:[version[@"capturedAt"] doubleValue]]
        dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle] : @"No saved copy";
}
@implementation SPDFMacCollectionWindow (SearchResults)
- (CGFloat)tableView:(NSTableView*)tableView heightOfRow:(NSInteger)index {
    (void)tableView; NSDictionary* row = self.rows[(NSUInteger)index];
    NSUInteger count = [row[@"matches"] count];
    NSUInteger visible = [self.expandedResults containsObject:RowKey(row)] ? count : MIN(3,count);
    return count ? 88 + visible * 58 + (count > 3 ? 30 : 0) + ([row[@"truncated"] boolValue] ? 22 : 0) : 112;
}
- (NSView*)resultCellForRow:(NSInteger)index {
    NSDictionary* row = self.rows[(NSUInteger)index], *doc = row[@"document"], *version = row[@"version"];
    NSView* cell = [NSView new];
    NSImageView* image = [NSImageView new]; image.translatesAutoresizingMaskIntoConstraints = NO;
    image.imageScaling = NSImageScaleProportionallyUpOrDown; image.identifier = RowKey(row);
    NSInteger page = [row[@"selectedPage"] integerValue];
    if (!page && [row[@"matches"] count]) page = [row[@"matches"][0][@"page"] integerValue];
    NSString* key = [RowKey(row) stringByAppendingFormat:@"/%ld",(long)page];
    image.identifier = key; image.image = [self.thumbnailCache objectForKey:key] ?: [NSImage imageWithSystemSymbolName:
        [version[@"encrypted"] boolValue] ? @"lock.doc" : @"doc" accessibilityDescription:@"Saved page preview"];
    image.accessibilityLabel = page > 0 ? [NSString stringWithFormat:@"Page %ld preview",(long)page] : @"Saved copy preview";
    [cell addSubview:image];
    if (version[@"id"] && ![version[@"encrypted"] boolValue]) {
        NSMutableDictionary* thumbnailRow = [row mutableCopy]; thumbnailRow[@"selectedPage"] = @(page);
        [self requestThumbnail:thumbnailRow key:key];
    }
    NSStackView* text = [NSStackView stackViewWithViews:@[]]; text.translatesAutoresizingMaskIntoConstraints = NO;
    text.orientation = NSUserInterfaceLayoutOrientationVertical; text.alignment = NSLayoutAttributeLeading; text.spacing = 5;
    [cell addSubview:text];
    NSStackView* heading = [NSStackView stackViewWithViews:@[]]; heading.spacing = 8;
    NSTextField* title = [NSTextField labelWithString:version[@"filename"] ?: doc[@"title"] ?: @"Document"];
    title.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]; title.lineBreakMode = NSLineBreakByTruncatingMiddle;
    title.toolTip = doc[@"path"]; [title setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [heading addArrangedSubview:title];
    NSButton* history = [NSButton buttonWithTitle:@"History" target:self action:@selector(historyForRow:)];
    history.tag = index; history.accessibilityLabel = [@"History for " stringByAppendingString:doc[@"title"] ?: @"document"];
    [heading addArrangedSubview:history]; [text addArrangedSubview:heading];
    NSString* latest = [version[@"id"] isEqual:doc[@"latestVersionID"]] || [row[@"latest"] boolValue] ? @"Latest" : @"Older version";
    NSTextField* meta = [NSTextField wrappingLabelWithString:[NSString stringWithFormat:@"%@ · %@%@",latest,DateLabel(version),[version[@"keep"] boolValue] ? @" · Kept" : @""]];
    meta.font = [NSFont systemFontOfSize:11]; meta.textColor = NSColor.secondaryLabelColor; [text addArrangedSubview:meta];
    NSArray* matches = row[@"matches"] ?: @[];
    NSUInteger visible = [self.expandedResults containsObject:RowKey(row)] ? matches.count : MIN(3,matches.count);
    for (NSUInteger i=0;i<visible;i++) {
        NSDictionary* match = matches[i]; NSString* snippet = match[@"snippet"] ?: @"";
        NSString* prefix = [match[@"page"] integerValue] > 0 ? [NSString stringWithFormat:@"Page %@ · ",match[@"page"]] : @"Saved text · ";
        NSMutableAttributedString* caption = [[NSMutableAttributedString alloc] initWithString:[prefix stringByAppendingString:snippet]
            attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:12],NSForegroundColorAttributeName:NSColor.labelColor}];
        for (NSValue* value in match[@"ranges"]) {
            NSRange range = value.rangeValue; range.location += prefix.length;
            if (NSMaxRange(range) <= caption.length) [caption addAttributes:@{
                NSBackgroundColorAttributeName:[NSColor.systemYellowColor colorWithAlphaComponent:.45],
                NSFontAttributeName:[NSFont systemFontOfSize:12 weight:NSFontWeightSemibold]} range:range];
        }
        NSButton* hit = [NSButton buttonWithTitle:@"" target:self action:@selector(selectSearchMatch:)];
        hit.bordered = NO; hit.alignment = NSTextAlignmentLeft; hit.attributedTitle = caption;
        hit.cell.wraps = YES; hit.cell.lineBreakMode = NSLineBreakByTruncatingTail;
        hit.tag = index; hit.identifier = [NSString stringWithFormat:@"%lu",(unsigned long)i];
        hit.toolTip = [prefix stringByAppendingString:snippet];
        [hit.heightAnchor constraintEqualToConstant:53].active = YES; [text addArrangedSubview:hit];
        [hit.widthAnchor constraintEqualToAnchor:text.widthAnchor].active = YES;
    }
    if (!matches.count) {
        NSString* status = self.search.stringValue.length ?
            ([row[@"textAvailable"] boolValue] ? @"Title match · no matching saved text" : @"Title match · saved text is not indexed") :
            (SPDFCollectionOriginalAvailable(doc) ? @"Original available · Read-only saved copy" : @"Original unavailable · Read-only saved copy");
        NSTextField* label = [NSTextField wrappingLabelWithString:status]; label.font = [NSFont systemFontOfSize:11];
        [text addArrangedSubview:label];
    }
    if (matches.count > 3) {
        BOOL expanded = [self.expandedResults containsObject:RowKey(row)];
        NSButton* more = [NSButton buttonWithTitle:expanded ? @"Show fewer matches" :
            [NSString stringWithFormat:@"Show %lu more matches",(unsigned long)matches.count-3] target:self action:@selector(toggleMatches:)];
        more.tag = index; [text addArrangedSubview:more];
    }
    if ([row[@"truncated"] boolValue]) {
        NSTextField* note = [NSTextField wrappingLabelWithString:[NSString stringWithFormat:
            @"Showing %lu contexts from %@ text matches. Refine your search to narrow results.",
            (unsigned long)matches.count,row[@"matchCount"] ?: @(matches.count)]];
        note.font = [NSFont systemFontOfSize:11]; note.textColor = NSColor.secondaryLabelColor;
        [text addArrangedSubview:note];
    }
    [NSLayoutConstraint activateConstraints:@[
        [image.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:10],
        [image.topAnchor constraintEqualToAnchor:cell.topAnchor constant:10],
        [image.widthAnchor constraintEqualToConstant:72],[image.heightAnchor constraintEqualToConstant:92],
        [text.leadingAnchor constraintEqualToAnchor:image.trailingAnchor constant:12],
        [text.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-10],
        [text.topAnchor constraintEqualToAnchor:cell.topAnchor constant:7],
        [heading.widthAnchor constraintEqualToAnchor:text.widthAnchor]]];
    return cell;
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
