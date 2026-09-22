#import "SPDFMacCollectionAvailability.h"
#import "SPDFMacCollectionPalette.h"
#import "SPDFMacCollectionPaletteModel.h"
#import "SPDFMacCollectionStore.h"
#import "SPDFMacMarkdownDelegatePrivate.h"
#import "SPDFMacTabGroups.h"
#import "markdown/SPDFMarkdownDocument.h"
#import <PDFKit/PDFKit.h>
#import <objc/runtime.h>
#import <float.h>

id spdf_state_object_from_yaml_data(NSData* data);
static const void* kSPDFPaletteSearchToken = &kSPDFPaletteSearchToken;

static NSString* RowIdentity(NSDictionary* row) {
    if (![row isKindOfClass:NSDictionary.class]) return @"";
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@", row[@"kind"] ?: @"", row[@"path"] ?: @"",
        row[@"page"] ?: @"", row[@"query"] ?: @"", row[@"title"] ?: @""];
}
static NSArray<NSDictionary*>* SessionWindows(id session) {
    return [session isKindOfClass:NSDictionary.class] && [session[@"windows"] isKindOfClass:NSArray.class]
        ? session[@"windows"] : @[];
}
static NSDictionary* MergeSession(id stored, NSDictionary* liveWindow) {
    NSMutableArray* windows = [SessionWindows(stored) mutableCopy];
    if (liveWindow) [windows addObject:liveWindow];
    return @{@"windows":windows};
}
static NSArray<NSDictionary*>* SearchCandidates(NSArray<NSDictionary*>* candidates) {
    return [candidates sortedArrayUsingComparator:^NSComparisonResult(NSDictionary* a, NSDictionary* b) {
      NSComparisonResult recent = [b[@"focusedAt"] compare:a[@"focusedAt"]];
      return recent != NSOrderedSame ? recent : [a[@"_order"] compare:b[@"_order"]];
    }];
}
static NSArray<NSDictionary*>* OpenTextMatches(NSArray<NSDictionary*>* candidates, NSString* query,
                                               NSProgress* progress) {
    NSMutableArray* results = [NSMutableArray array];
    NSUInteger visitedDocuments = 0, visitedPages = 0;
    for (NSDictionary* candidate in SearchCandidates(candidates)) {
        if (progress.cancelled || results.count == 5 || visitedDocuments++ >= 128 || visitedPages >= 10000) break;
        NSString* path = candidate[@"path"];
        if (![path isKindOfClass:NSString.class] || !path.length) continue;
        NSMutableArray<NSString*>* pages = [NSMutableArray array];
        if ([@[@"md", @"markdown"] containsObject:path.pathExtension.lowercaseString]) {
            SPDFMarkdownDocument* doc = [SPDFMarkdownDocument documentWithURL:[NSURL fileURLWithPath:path]
                                                                       options:nil error:nil];
            SPDFMarkdownPageConfiguration* fallback = [candidate[@"markdownLandscape"] boolValue]
                ? [SPDFMarkdownPageConfiguration A4LandscapeConfiguration]
                : [SPDFMarkdownPageConfiguration A4PortraitConfiguration];
            SPDFMarkdownPaginationPlan* plan = [doc paginationPlanForConfiguration:doc.authoredPageConfiguration ?: fallback];
            NSString* text = doc.renderedDocument.attributedString.string;
            for (SPDFMarkdownPage* page in plan.pages) {
                if (progress.cancelled || visitedPages++ >= 10000) break;
                NSMutableString* pageText = [NSMutableString string];
                for (SPDFMarkdownPageFragment* fragment in page.fragments) {
                    if (NSMaxRange(fragment.attributedRange) > text.length) continue;
                    if (pageText.length) [pageText appendString:@" "];
                    [pageText appendString:[text substringWithRange:fragment.attributedRange]];
                }
                [pages addObject:pageText];
            }
        } else {
            PDFDocument* pdf = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:path]];
            if (pdf.isLocked) continue;
            for (NSUInteger page = 0; page < pdf.pageCount && visitedPages++ < 10000; page++) {
                if (progress.cancelled) break;
                [pages addObject:[pdf pageAtIndex:page].string ?: @""];
            }
        }
        for (NSUInteger page = 0; page < pages.count && results.count < 5; page++) {
            NSString* text = pages[page];
            NSRange match = [text rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch];
            if (match.location == NSNotFound) continue;
            NSUInteger start = match.location > 60 ? match.location - 60 : 0;
            NSString* snippet = spdf_collection_palette_single_line([text substringWithRange:NSMakeRange(start,
                MIN((NSUInteger)190, text.length - start))]);
            [results addObject:@{@"kind":@"collectionOpenText",
                @"title":[NSString stringWithFormat:@"%@ · page %lu", candidate[@"title"], (unsigned long)page + 1],
                @"subtitle":snippet, @"path":path, @"page":@(page), @"query":query}];
        }
    }
    return results;
}
static NSArray<NSDictionary*>* CollectionRows(NSArray<NSDictionary*>* hits, NSString* query, BOOL text) {
    NSMutableArray* rows = [NSMutableArray array];
    for (NSDictionary* hit in hits ?: @[]) {
        NSMutableDictionary* row = [hit mutableCopy]; row[@"kind"] = @"collectionDocument";
        row[@"title"] = hit[@"title"] ?: [hit[@"path"] lastPathComponent] ?: @"Document";
        row[@"subtitle"] = text ? spdf_collection_palette_single_line(hit[@"snippet"] ?: @"") : hit[@"path"] ?: @"";
        NSInteger oneBasedPage = [hit[@"page"] integerValue];
        if (text) row[@"page"] = @(oneBasedPage > 0 ? oneBasedPage - 1 : 0);
        if (text && oneBasedPage > 0) row[@"title"] = [NSString stringWithFormat:@"%@ · page %ld", row[@"title"], (long)oneBasedPage];
        if (text) row[@"query"] = query;
        [rows addObject:row];
    }
    return rows;
}

@implementation ShenzhenMacDelegate (SPDFMacCollectionPalette)
- (NSDictionary*)livePaletteSessionWindow {
    NSMutableArray* tabs = [NSMutableArray array];
    for (SPDFDocumentTab* tab in _tabs) {
        if (!tab.path.length) continue;
        NSMutableDictionary* item = [@{@"path":tab.path, @"title":tab.title ?: @"",
            @"markdownLandscape":@(tab.markdownLandscape)} mutableCopy];
        if (tab.group) item[@"group"] = tab.group.dictionary;
        [tabs addObject:item];
    }
    return @{@"id":@"live-palette", @"focusedAt":@(DBL_MAX), @"tabs":tabs};
}
- (void)applyPaletteRows:(NSArray<NSDictionary*>*)rows preservingIdentity:(NSString*)identity {
    [_paletteResults setArray:rows.count ? rows : @[@{@"kind":@"status", @"title":@"No matches",
        @"subtitle":@"Try a document name, group, or col: followed by text."}]];
    [_paletteTable reloadData]; [self updatePalettePanelFramePreservingTop:YES];
    NSInteger match = -1;
    if (identity.length) for (NSUInteger index = 0; index < _paletteResults.count; index++)
        if ([RowIdentity(_paletteResults[index]) isEqual:identity]) { match = (NSInteger)index; break; }
    if (match >= 0) [_paletteTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)match]
                              byExtendingSelection:NO];
    else [self selectFirstPaletteResult];
}
- (void)refreshPaletteResults {
    NSProgress* previous = objc_getAssociatedObject(self, kSPDFPaletteSearchToken); [previous cancel];
    NSProgress* progress = [NSProgress progressWithTotalUnitCount:1];
    objc_setAssociatedObject(self, kSPDFPaletteSearchToken, progress, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSUInteger generation = ++_paletteSearchGeneration;
    NSDictionary* parsed = spdf_collection_palette_query(_paletteSearchField.stringValue);
    BOOL collectionOnly = [parsed[@"collectionOnly"] boolValue]; NSString* query = parsed[@"query"];
    NSArray* liveCandidates = [self openDocumentPaletteCandidates];
    NSDictionary* liveWindow = [self livePaletteSessionWindow];
    NSDictionary* immediateSession = MergeSession(nil, liveWindow);
    NSArray* immediateOpen = spdf_collection_palette_open_candidates(liveCandidates, immediateSession);
    NSArray* supplements = collectionOnly ? @[] : [self collectionPaletteSupplementaryRowsForQuery:query excludingOpenPaths:spdf_collection_palette_open_paths(immediateOpen)];
    NSArray* openNames = collectionOnly ? @[] : spdf_collection_palette_open_name_rows(immediateOpen, query);
    NSMutableArray* titledOpen = [NSMutableArray array];
    for (NSDictionary* row in openNames) {
        NSMutableDictionary* display = [row mutableCopy]; display[@"subtitle"] = [self shortProvenanceForPath:row[@"path"]];
        [titledOpen addObject:display];
    }
    NSArray* groups = collectionOnly ? @[] : spdf_collection_palette_group_rows(immediateSession, query);
    NSArray* instant = [spdf_collection_palette_rows(collectionOnly, query, titledOpen, groups, @[], @[], @[], NO) arrayByAddingObjectsFromArray:supplements];
    [_paletteResults setArray:instant];
    [_paletteResults addObject:@{@"kind":@"status", @"title":@"Searching…",
                                 @"subtitle":@"Open documents, groups and local Collection"}];
    [_paletteTable reloadData]; [self selectFirstPaletteResult];
    [self updatePalettePanelFramePreservingTop:_palettePanel.visible];

    NSString* sessionPath = [[self pathForStateFile:@"session.yaml"] copy];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_MSEC), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (progress.cancelled) return;
        NSData* data = [NSData dataWithContentsOfFile:sessionPath];
        NSDictionary* session = MergeSession(spdf_state_object_from_yaml_data(data), liveWindow);
        NSArray* candidates = spdf_collection_palette_open_candidates(liveCandidates, session);
        NSSet* openPaths = spdf_collection_palette_open_paths(candidates);
        NSArray* asyncOpenNames = collectionOnly ? @[] : spdf_collection_palette_open_name_rows(candidates, query);
        NSArray* asyncGroups = collectionOnly ? @[] : spdf_collection_palette_group_rows(session, query);
        NSArray* openText = !collectionOnly && query.length ? OpenTextMatches(candidates, query, progress) : @[];
        if (progress.cancelled) return;
        SPDFMacCollectionStore* store = SPDFMacCollectionStore.defaultStore;
        NSSet* nameExclusions = collectionOnly ? NSSet.set : openPaths;
        NSArray* nameHits = [store search:query titlesOnly:YES excludingPaths:nameExclusions limit:5];
        // Open text is the live file; Collection text is the protected revision.
        // Both are useful when contents differ, and the specified exclusion only
        // applies to Collection document-name results.
        NSArray* textHits = query.length ? [store search:query titlesOnly:NO excludingPaths:NSSet.set limit:5] : @[];
        NSMutableArray* displayNames = [NSMutableArray array];
        for (NSDictionary* row in asyncOpenNames) {
            NSMutableDictionary* display = [row mutableCopy];
            display[@"subtitle"] = [self shortProvenanceForPath:row[@"path"]]; [displayNames addObject:display];
        }
        NSArray* rows = [spdf_collection_palette_rows(collectionOnly, query, displayNames, asyncGroups, openText,
            CollectionRows(nameHits, query, NO), CollectionRows(textHits, query, YES), collectionOnly) arrayByAddingObjectsFromArray:supplements];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (progress.cancelled || generation != self->_paletteSearchGeneration || !self->_palettePanel.visible) return;
            NSInteger selected = self->_paletteTable.selectedRow;
            NSString* identity = selected >= 0 && selected < (NSInteger)self->_paletteResults.count
                ? RowIdentity(self->_paletteResults[(NSUInteger)selected]) : @"";
            [self applyPaletteRows:rows preservingIdentity:identity];
        });
    });
}
- (BOOL)openCollectionPaletteResult:(NSDictionary*)result {
    NSString* kind = result[@"kind"];
    if (![kind hasPrefix:@"collection"]) return NO;
    if ([kind isEqual:@"collectionShowAll"]) {
        NSString* query = result[@"query"] ?: @"";
        dispatch_async(dispatch_get_main_queue(), ^{ [self showCollectionManagerForQuery:query]; });
        return YES;
    }
    NSString* path = result[@"path"];
    if ([kind isEqual:@"collectionGroup"]) { [self focusOpenDocumentTabForPath:path]; return YES; }
    if ([kind isEqual:@"collectionDocument"] && !SPDFCollectionOriginalAvailable(result)) {
        SPDFMacCollectionStore* store = SPDFMacCollectionStore.defaultStore;
        NSDictionary* doc = result; NSError* error = nil;
        NSURL* URL = [store materializeVersionID:doc[@"latestVersionID"] documentID:doc[@"id"] error:&error];
        if (!URL) { [_window presentError:error]; return YES; }
        path = URL.path;
    }
    [self collectionOpenPath:path archived:[SPDFMacCollectionStore.defaultStore isArchivePath:path]];
    [self collectionNavigateResult:result path:path attempts:100];
    return YES;
}
- (void)collectionNavigateResult:(NSDictionary*)result path:(NSString*)path attempts:(NSInteger)attempts {
    if (!result[@"page"] || ![_path isEqual:path] || attempts <= 0) return;
    SPDFMacMarkdownSession* session = [self isMarkdownActive] ? self.activeMarkdownSession : nil;
    if (session && !session.isNavigationReady) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            [self collectionNavigateResult:result path:path attempts:attempts - 1];
        }); return;
    }
    NSInteger page = MAX(0, [result[@"page"] integerValue]);
    if (session) [self markdownGoToPage:page]; else [self goToPage:page preserveSinglePagePosition:NO];
    if ([result[@"query"] length]) {
        _searchField.stringValue = result[@"query"]; _findRegexCheckbox.state = NSControlStateValueOff;
        _pendingFindPreferredPage = page;
        [self startFindForCurrentQueryResetSavedIndex:YES revealMatch:YES];
    }
}
@end
