#import <Foundation/Foundation.h>

// Pure, controller-free palette composition. Candidate dictionaries use path,
// title, focusedAt, markdownLandscape and the persisted tab group dictionary.
NSDictionary* spdf_collection_palette_query(NSString* rawQuery);
NSString* spdf_collection_palette_single_line(NSString* text);
NSArray<NSDictionary*>* spdf_collection_palette_open_candidates(NSArray<NSDictionary*>* liveCandidates,
                                                                 id sessionObject);
NSSet<NSString*>* spdf_collection_palette_open_paths(NSArray<NSDictionary*>* candidates);
NSArray<NSDictionary*>* spdf_collection_palette_open_name_rows(NSArray<NSDictionary*>* candidates,
                                                                NSString* query);
NSArray<NSDictionary*>* spdf_collection_palette_group_rows(id sessionObject, NSString* query);

// Builds the documented section order. Empty sections are omitted, while any
// present sections always retain their relative order. Collection-only mode
// emits only the two Collection sections and the query-preserving Show All row.
NSArray<NSDictionary*>* spdf_collection_palette_rows(BOOL collectionOnly, NSString* query,
                                                      NSArray<NSDictionary*>* openNames,
                                                      NSArray<NSDictionary*>* groups,
                                                      NSArray<NSDictionary*>* openText,
                                                      NSArray<NSDictionary*>* collectionNames,
                                                      NSArray<NSDictionary*>* collectionText,
                                                      BOOL showAll);
