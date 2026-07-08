#import <Foundation/Foundation.h>

// Pure helpers for assembling the Cmd+K palette's open-document results and
// deduplicating them against favorites. Kept free of controller state so they
// can be unit-tested standalone (see tests/SPDFMacPaletteResultsTests.mm).

// YES when the query is a case/diacritic-insensitive substring of the tab
// title or of the file name — the same matching the other palette entries use.
// An empty query matches everything.
BOOL spdf_palette_open_document_matches_query(NSString* query, NSString* title, NSString* path);

// Filters open-tab candidates (@{@"path", @"title"}, in window/tab order) down
// to the ones matching the query, preserving order and deduplicating repeated
// documents (the same file open in more than one tab/window is shown once).
NSArray<NSDictionary*>* spdf_palette_open_document_results(NSArray<NSDictionary*>* candidates, NSString* query);

// Removes document-level favorite results whose document is already shown as
// an open-document row (openStandardizedPaths holds standardized paths), so a
// document that is open and also a favorite appears once, as the open entry.
// Page-level favorites are kept: they target a specific page, which the
// open-document row does not.
NSArray<NSDictionary*>* spdf_palette_favorites_without_open_documents(NSArray<NSDictionary*>* favoriteResults,
                                                                      NSSet<NSString*>* openStandardizedPaths);
