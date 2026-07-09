#import <Cocoa/Cocoa.h>

#import "../SPDFMacPaletteResults.h"

static int gFailureCount = 0;

static void expect_true(NSString* label, BOOL condition) {
    if (!condition) {
        fprintf(stderr, "FAIL %s\n", label.UTF8String);
        ++gFailureCount;
    }
}

static void expect_paths(NSString* label, NSArray<NSDictionary*>* results, NSArray<NSString*>* expectedPaths) {
    NSMutableArray<NSString*>* actual = [NSMutableArray array];
    for (NSDictionary* result in results) [actual addObject:result[@"path"] ?: @""];
    if (![actual isEqualToArray:expectedPaths]) {
        fprintf(stderr, "FAIL %s: expected %s, got %s\n", label.UTF8String, expectedPaths.description.UTF8String,
                actual.description.UTF8String);
        ++gFailureCount;
    }
}

static NSDictionary* open_candidate(NSString* path, NSString* title) {
    return @{@"path" : path, @"title" : title};
}

static NSDictionary* favorite_result(NSString* path, NSString* type) {
    return @{
        @"kind" : @"favorite",
        @"title" : path.lastPathComponent,
        @"path" : path,
        @"favorite" : @{@"type" : type, @"path" : path}
    };
}

int main(int argc, char** argv) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        // --- spdf_palette_open_document_matches_query ---
        expect_true(@"empty query matches", spdf_palette_open_document_matches_query(@"", @"Title", @"/a/b.pdf"));
        expect_true(@"title substring matches case-insensitively",
                    spdf_palette_open_document_matches_query(@"hard", @"SG882G Hardware Design", @"/a/b.pdf"));
        expect_true(@"file name matches when title does not",
                    spdf_palette_open_document_matches_query(@"quectel", @"Datasheet (2)",
                                                             @"/docs/Quectel_SG882G.pdf"));
        expect_true(@"diacritic-insensitive match",
                    spdf_palette_open_document_matches_query(@"resume", @"R\u00e9sum\u00e9", @"/a/r.pdf"));
        expect_true(@"non-matching query rejected",
                    !spdf_palette_open_document_matches_query(@"missing", @"Title", @"/a/b.pdf"));
        expect_true(@"directory names do not match",
                    !spdf_palette_open_document_matches_query(@"docs", @"Title", @"/docs/b.pdf"));

        // --- spdf_palette_open_document_results ---
        NSArray<NSDictionary*>* candidates = @[
            open_candidate(@"/docs/alpha.pdf", @"alpha"),
            open_candidate(@"/docs/beta.pdf", @"beta"),
            open_candidate(@"/other/alpha-two.pdf", @"alpha-two"),
        ];
        expect_paths(@"empty query returns all candidates in order",
                     spdf_palette_open_document_results(candidates, @""),
                     @[ @"/docs/alpha.pdf", @"/docs/beta.pdf", @"/other/alpha-two.pdf" ]);
        expect_paths(@"query filters by title/file name preserving order",
                     spdf_palette_open_document_results(candidates, @"alpha"),
                     @[ @"/docs/alpha.pdf", @"/other/alpha-two.pdf" ]);
        expect_paths(@"no matches yields empty", spdf_palette_open_document_results(candidates, @"gamma"), @[]);

        NSArray<NSDictionary*>* duplicated = @[
            open_candidate(@"/docs/alpha.pdf", @"alpha"),
            open_candidate(@"/docs/alpha.pdf", @"alpha"),
            open_candidate(@"/docs//alpha.pdf", @"alpha"),
        ];
        expect_paths(@"same document open twice is listed once",
                     spdf_palette_open_document_results(duplicated, @""), @[ @"/docs/alpha.pdf" ]);
        expect_paths(@"blank paths are skipped",
                     spdf_palette_open_document_results(@[ open_candidate(@"", @"ghost") ], @""), @[]);

        // --- spdf_palette_favorites_without_open_documents ---
        NSArray<NSDictionary*>* favorites = @[
            favorite_result(@"/docs/alpha.pdf", @"document"),
            favorite_result(@"/docs/alpha.pdf", @"page"),
            favorite_result(@"/docs/beta.pdf", @"document"),
        ];
        NSSet<NSString*>* open = [NSSet setWithObject:@"/docs/alpha.pdf"];
        expect_paths(@"document favorite deduped against open entry, page favorite kept",
                     spdf_palette_favorites_without_open_documents(favorites, open),
                     @[ @"/docs/alpha.pdf", @"/docs/beta.pdf" ]);
        NSArray<NSDictionary*>* deduped = spdf_palette_favorites_without_open_documents(favorites, open);
        expect_true(@"kept alpha favorite is the page-level one",
                    deduped.count > 0 && [deduped[0][@"favorite"][@"type"] isEqualToString:@"page"]);
        expect_paths(@"no open documents keeps all favorites",
                     spdf_palette_favorites_without_open_documents(favorites, [NSSet set]),
                     @[ @"/docs/alpha.pdf", @"/docs/alpha.pdf", @"/docs/beta.pdf" ]);

        // --- spdf_palette_query_reveals_all_favorites ---
        expect_true(@"'fav' reveals all favorites", spdf_palette_query_reveals_all_favorites(@"fav"));
        expect_true(@"'favo' reveals all favorites", spdf_palette_query_reveals_all_favorites(@"favo"));
        expect_true(@"'favorite' reveals all favorites", spdf_palette_query_reveals_all_favorites(@"favorite"));
        expect_true(@"'favorites' reveals all favorites", spdf_palette_query_reveals_all_favorites(@"favorites"));
        expect_true(@"keyword is case-insensitive", spdf_palette_query_reveals_all_favorites(@"FaV"));
        expect_true(@"keyword ignores surrounding whitespace",
                    spdf_palette_query_reveals_all_favorites(@" fav "));
        expect_true(@"two characters are not enough", !spdf_palette_query_reveals_all_favorites(@"fa"));
        expect_true(@"empty query is not the keyword", !spdf_palette_query_reveals_all_favorites(@""));
        expect_true(@"nil query is not the keyword", !spdf_palette_query_reveals_all_favorites(nil));
        expect_true(@"'fax' is not a prefix of favorites", !spdf_palette_query_reveals_all_favorites(@"fax"));
        expect_true(@"'favorite x' is not a prefix of favorites",
                    !spdf_palette_query_reveals_all_favorites(@"favorite x"));
        expect_true(@"'favoritess' overshoots the keyword",
                    !spdf_palette_query_reveals_all_favorites(@"favoritess"));
    }
    if (gFailureCount > 0) return 1;
    printf("SPDFMacPaletteResultsTests passed\n");
    return 0;
}
