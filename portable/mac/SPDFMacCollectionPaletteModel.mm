#import "SPDFMacCollectionPaletteModel.h"
#import <float.h>

static NSString* Text(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
static NSNumber* Number(id value) { return [value isKindOfClass:NSNumber.class] ? value : @0; }
static NSString* PathKey(NSString* path) {
    NSString* key = path.stringByStandardizingPath;
    return key.length ? key : (path ?: @"");
}
static NSInteger MatchRank(NSString* query, NSString* title, NSString* path) {
    if (!query.length) return 0;
    NSStringCompareOptions folded = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    for (NSString* value in @[title ?: @"", path.lastPathComponent ?: @""]) {
        if ([value compare:query options:folded] == NSOrderedSame) return 0;
        NSRange range = [value rangeOfString:query options:folded];
        if (range.location == 0) return 1;
        if (range.location != NSNotFound) return 2;
    }
    return NSNotFound;
}
static NSComparisonResult RankRows(NSDictionary* left, NSDictionary* right) {
    NSComparisonResult rank = [Number(left[@"_rank"]) compare:Number(right[@"_rank"])];
    if (rank != NSOrderedSame) return rank;
    NSComparisonResult recent = [Number(right[@"focusedAt"]) compare:Number(left[@"focusedAt"])];
    if (recent != NSOrderedSame) return recent;
    NSComparisonResult order = [Number(left[@"_order"]) compare:Number(right[@"_order"])];
    if (order != NSOrderedSame) return order;
    return [Text(left[@"title"]) localizedCaseInsensitiveCompare:Text(right[@"title"])];
}

NSDictionary* spdf_collection_palette_query(NSString* rawQuery) {
    NSString* raw = [Text(rawQuery) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    BOOL scoped = [raw.lowercaseString hasPrefix:@"col:"];
    NSString* query = scoped ? [raw substringFromIndex:4] : raw;
    query = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return @{@"collectionOnly":@(scoped), @"query":query};
}

NSString* spdf_collection_palette_single_line(NSString* text) {
    NSArray* words = [Text(text) componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [[words filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString* word, NSDictionary* _) {
      (void)_; return word.length > 0;
    }]] componentsJoinedByString:@" "];
}

static NSArray<NSDictionary*>* SessionCandidates(id sessionObject) {
    if (![sessionObject isKindOfClass:NSDictionary.class]) return @[];
    NSArray* windows = [sessionObject[@"windows"] isKindOfClass:NSArray.class] ? sessionObject[@"windows"] : @[];
    NSMutableArray* results = [NSMutableArray array];
    NSUInteger order = 0;
    for (NSDictionary* window in windows) {
        if (![window isKindOfClass:NSDictionary.class]) continue;
        NSNumber* focusedAt = Number(window[@"focusedAt"]);
        NSArray* tabs = [window[@"tabs"] isKindOfClass:NSArray.class] ? window[@"tabs"] : @[];
        for (NSDictionary* tab in tabs) {
            if (![tab isKindOfClass:NSDictionary.class]) continue;
            NSString* path = Text(tab[@"path"]); if (!path.length) continue;
            NSMutableDictionary* row = [@{@"path":path, @"title":Text(tab[@"collectionVersionLabel"]).length ? tab[@"collectionVersionLabel"] : Text(tab[@"title"]),
                @"focusedAt":focusedAt, @"_order":@(order++),
                @"markdownLandscape":@([tab[@"markdownLandscape"] boolValue])} mutableCopy];
            if ([tab[@"group"] isKindOfClass:NSDictionary.class]) row[@"group"] = tab[@"group"];
            [results addObject:row];
        }
    }
    return results;
}

NSArray<NSDictionary*>* spdf_collection_palette_open_candidates(NSArray<NSDictionary*>* liveCandidates,
                                                                 id sessionObject) {
    NSMutableArray* results = [NSMutableArray array];
    NSMutableDictionary<NSString*, NSNumber*>* indices = [NSMutableDictionary dictionary];
    NSArray* sources = @[@{ @"items":liveCandidates ?: @[], @"live":@YES },
                         @{ @"items":SessionCandidates(sessionObject), @"live":@NO }];
    NSUInteger order = 0;
    for (NSDictionary* source in sources) for (NSDictionary* raw in source[@"items"]) {
        if (![raw isKindOfClass:NSDictionary.class]) continue;
        NSString* path = Text(raw[@"path"]); if (!path.length) continue;
        NSString* key = PathKey(path); NSNumber* existing = indices[key];
        if (existing) {
            NSMutableDictionary* row = [results[existing.unsignedIntegerValue] mutableCopy];
            for (NSString* field in @[@"group", @"markdownLandscape", @"focusedAt"])
                if (!row[field] && raw[field]) row[field] = raw[field];
            if ([Number(raw[@"focusedAt"]) doubleValue] > [Number(row[@"focusedAt"]) doubleValue])
                row[@"focusedAt"] = raw[@"focusedAt"];
            results[existing.unsignedIntegerValue] = row;
            continue;
        }
        NSMutableDictionary* row = [raw mutableCopy];
        row[@"path"] = path; row[@"_order"] = @(order++);
        if (!Text(row[@"title"]).length) row[@"title"] = path.lastPathComponent.stringByDeletingPathExtension;
        if ([source[@"live"] boolValue]) row[@"focusedAt"] = @(DBL_MAX);
        indices[key] = @(results.count); [results addObject:row];
    }
    return results;
}

NSSet<NSString*>* spdf_collection_palette_open_paths(NSArray<NSDictionary*>* candidates) {
    NSMutableSet* paths = [NSMutableSet set];
    for (NSDictionary* candidate in candidates ?: @[]) {
        NSString* path = Text(candidate[@"path"]); if (path.length) [paths addObject:PathKey(path)];
    }
    return paths;
}

NSArray<NSDictionary*>* spdf_collection_palette_open_name_rows(NSArray<NSDictionary*>* candidates,
                                                                NSString* query) {
    NSMutableArray* ranked = [NSMutableArray array];
    for (NSDictionary* candidate in candidates ?: @[]) {
        NSString* path = Text(candidate[@"path"]), *title = Text(candidate[@"title"]);
        NSInteger rank = MatchRank(query, title, path); if (rank == NSNotFound) continue;
        NSMutableDictionary* row = [candidate mutableCopy];
        row[@"kind"] = @"openDoc"; row[@"title"] = title.length ? title : path.lastPathComponent;
        row[@"_rank"] = @(rank); [ranked addObject:row];
    }
    [ranked sortUsingComparator:^NSComparisonResult(NSDictionary* a, NSDictionary* b) { return RankRows(a, b); }];
    return ranked;
}

NSArray<NSDictionary*>* spdf_collection_palette_group_rows(id sessionObject, NSString* query) {
    NSMutableDictionary<NSString*, NSMutableDictionary*>* groups = [NSMutableDictionary dictionary];
    NSUInteger order = 0;
    for (NSDictionary* candidate in SessionCandidates(sessionObject)) {
        NSDictionary* group = [candidate[@"group"] isKindOfClass:NSDictionary.class] ? candidate[@"group"] : nil;
        NSString* identifier = Text(group[@"id"]); if (!identifier.length) continue;
        NSMutableDictionary* row = groups[identifier];
        if (!row) {
            NSString* name = Text(group[@"name"]), *color = Text(group[@"color"]);
            NSString* title = name.length ? name : [identifier isEqual:@"general"] ? @"General" : color;
            NSInteger rank = MatchRank(query, title, @""); if (rank == NSNotFound) continue;
            row = [@{@"kind":@"collectionGroup", @"title":title.length ? title : @"Group",
                @"color":color.length ? color : @"Gray", @"path":Text(group[@"lastUsedPath"]),
                @"focusedAt":Number(candidate[@"focusedAt"]), @"count":@0,
                @"_rank":@(rank), @"_order":@(order++)} mutableCopy];
            groups[identifier] = row;
        }
        row[@"count"] = @([row[@"count"] unsignedIntegerValue] + 1);
        if (!Text(row[@"path"]).length) row[@"path"] = candidate[@"path"];
        if ([Number(candidate[@"focusedAt"]) doubleValue] > [Number(row[@"focusedAt"]) doubleValue])
            row[@"focusedAt"] = candidate[@"focusedAt"];
    }
    NSMutableArray* rows = [groups.allValues mutableCopy];
    for (NSMutableDictionary* row in rows)
        row[@"subtitle"] = [NSString stringWithFormat:@"%@ group · %@ tabs", row[@"color"], row[@"count"]];
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary* a, NSDictionary* b) { return RankRows(a, b); }];
    return rows;
}

static void AddSection(NSMutableArray* rows, NSString* name, NSArray* content) {
    if (!content.count) return;
    [rows addObject:@{@"kind":@"header", @"title":name, @"subtitle":@""}];
    [rows addObjectsFromArray:content];
}
NSArray<NSDictionary*>* spdf_collection_palette_rows(BOOL collectionOnly, NSString* query,
                                                      NSArray<NSDictionary*>* openNames,
                                                      NSArray<NSDictionary*>* groups,
                                                      NSArray<NSDictionary*>* openText,
                                                      NSArray<NSDictionary*>* collectionNames,
                                                      NSArray<NSDictionary*>* collectionText,
                                                      BOOL showAll) {
    NSMutableArray* rows = [NSMutableArray array];
    if (!collectionOnly) {
        AddSection(rows, @"Open documents", openNames);
        AddSection(rows, @"Tab groups", groups);
        AddSection(rows, @"Text in open documents", openText.count > 5 ? [openText subarrayWithRange:NSMakeRange(0, 5)] : openText);
    }
    AddSection(rows, @"Collection documents", collectionNames.count > 5 ? [collectionNames subarrayWithRange:NSMakeRange(0, 5)] : collectionNames);
    AddSection(rows, @"Text in Collection", collectionText.count > 5 ? [collectionText subarrayWithRange:NSMakeRange(0, 5)] : collectionText);
    if (collectionOnly && showAll)
        [rows addObject:@{@"kind":@"collectionShowAll", @"title":@"Show all in Collection…",
                          @"subtitle":query ?: @"", @"query":query ?: @""}];
    return rows;
}
