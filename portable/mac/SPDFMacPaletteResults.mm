#import "SPDFMacPaletteResults.h"

static NSString* spdf_palette_standardized_path(NSString* path) {
    NSString* standardized = path.stringByStandardizingPath;
    return standardized.length ? standardized : (path ?: @"");
}

BOOL spdf_palette_open_document_matches_query(NSString* query, NSString* title, NSString* path) {
    if (query.length == 0) return YES;
    NSStringCompareOptions options = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    if (title.length && [title rangeOfString:query options:options].location != NSNotFound) return YES;
    NSString* fileName = path.lastPathComponent;
    return fileName.length && [fileName rangeOfString:query options:options].location != NSNotFound;
}

NSArray<NSDictionary*>* spdf_palette_open_document_results(NSArray<NSDictionary*>* candidates, NSString* query) {
    NSMutableArray<NSDictionary*>* results = [NSMutableArray array];
    NSMutableSet<NSString*>* seenPaths = [NSMutableSet set];
    for (NSDictionary* candidate in candidates ?: @[]) {
        NSString* path = [candidate[@"path"] isKindOfClass:NSString.class] ? candidate[@"path"] : @"";
        if (!path.length) continue;
        NSString* key = spdf_palette_standardized_path(path);
        if ([seenPaths containsObject:key]) continue;
        NSString* title = [candidate[@"title"] isKindOfClass:NSString.class] ? candidate[@"title"] : @"";
        if (!spdf_palette_open_document_matches_query(query, title, path)) continue;
        [seenPaths addObject:key];
        [results addObject:candidate];
    }
    return results;
}

BOOL spdf_palette_query_reveals_all_favorites(NSString* query) {
    NSString* trimmed = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length < 3) return NO;
    NSRange range = [@"favorites" rangeOfString:trimmed
                                        options:NSCaseInsensitiveSearch | NSAnchoredSearch];
    return range.location == 0;
}

NSArray<NSDictionary*>* spdf_palette_favorites_without_open_documents(NSArray<NSDictionary*>* favoriteResults,
                                                                      NSSet<NSString*>* openStandardizedPaths) {
    if (openStandardizedPaths.count == 0) return favoriteResults ?: @[];
    NSMutableArray<NSDictionary*>* results = [NSMutableArray array];
    for (NSDictionary* result in favoriteResults ?: @[]) {
        NSDictionary* favorite = [result[@"favorite"] isKindOfClass:NSDictionary.class] ? result[@"favorite"] : nil;
        BOOL documentLevel = [favorite[@"type"] isKindOfClass:NSString.class] &&
                             [favorite[@"type"] isEqualToString:@"document"];
        NSString* path = [result[@"path"] isKindOfClass:NSString.class] ? result[@"path"] : @"";
        if (documentLevel && path.length &&
            [openStandardizedPaths containsObject:spdf_palette_standardized_path(path)])
            continue;
        [results addObject:result];
    }
    return results;
}
