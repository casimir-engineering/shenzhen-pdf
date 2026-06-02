#import "SPDFMacModels.h"

@implementation SPDFRenderedPage
@end

@implementation SPDFDocumentTab

- (instancetype)init {
    self = [super init];
    if (self) {
        _pageIndex = 0;
        _zoom = 1.0;
        _customZoom = 1.0;
        _fitMode = SPDFFitModeWidth;
        _viewMode = SPDFViewModeContinuous;
        _searchText = @"";
        _searchRegexMultiline = YES;
        _findMatchIndex = -1;
        _showSidebar = YES;
        _showMinimap = YES;
        _missingMessage = @"";
    }
    return self;
}

@end

SPDFDocumentTab* spdf_copy_document_tab(SPDFDocumentTab* source) {
    SPDFDocumentTab* copy = [[SPDFDocumentTab alloc] init];
    copy.path = source.path;
    copy.title = source.title;
    copy.pageIndex = source.pageIndex;
    copy.zoom = source.zoom;
    copy.customZoom = source.customZoom;
    copy.fitMode = source.fitMode;
    copy.viewMode = source.viewMode;
    copy.scrollOrigin = source.scrollOrigin;
    copy.hasScrollOrigin = source.hasScrollOrigin;
    copy.searchText = source.searchText;
    copy.searchRegex = source.searchRegex;
    copy.searchRegexMultiline = source.searchRegexMultiline;
    copy.findMatchIndex = source.findMatchIndex;
    copy.showSidebar = source.showSidebar;
    copy.showMinimap = source.showMinimap;
    copy.missingFile = source.missingFile;
    copy.missingMessage = source.missingMessage;
    return copy;
}

NSDictionary* spdf_dictionary_from_tab(SPDFDocumentTab* tab, NSInteger sourceWindowNumber) {
    if (!tab) return @{};
    return @{
        @"path" : tab.path ?: @"",
        @"title" : tab.title ?: @"",
        @"page" : @(tab.pageIndex),
        @"zoom" : @(tab.zoom),
        @"customZoom" : @(tab.customZoom),
        @"fitMode" : @(tab.fitMode),
        @"viewMode" : @(tab.viewMode),
        @"scrollX" : @(tab.scrollOrigin.x),
        @"scrollY" : @(tab.scrollOrigin.y),
        @"hasScrollOrigin" : @(tab.hasScrollOrigin),
        @"searchText" : tab.searchText ?: @"",
        @"searchRegex" : @(tab.searchRegex),
        @"searchRegexMultiline" : @(tab.searchRegexMultiline),
        @"findMatchIndex" : @(tab.findMatchIndex),
        @"showSidebar" : @(tab.showSidebar),
        @"showMinimap" : @(tab.showMinimap),
        @"sourcePID" : @(NSProcessInfo.processInfo.processIdentifier),
        @"sourceWindow" : @(sourceWindowNumber)
    };
}

SPDFDocumentTab* spdf_tab_from_dictionary(NSDictionary* item) {
    if (![item isKindOfClass:NSDictionary.class]) return nil;
    NSString* path = item[@"path"];
    if (![path isKindOfClass:NSString.class] || path.length == 0) return nil;
    SPDFDocumentTab* tab = [[SPDFDocumentTab alloc] init];
    tab.path = path;
    if ([item[@"title"] isKindOfClass:NSString.class]) tab.title = item[@"title"];
    tab.pageIndex = MAX(0, [item[@"page"] integerValue]);
    tab.zoom = [item[@"zoom"] doubleValue] > 0 ? [item[@"zoom"] doubleValue] : 1.0;
    tab.customZoom = [item[@"customZoom"] doubleValue] > 0 ? [item[@"customZoom"] doubleValue] : tab.zoom;
    tab.fitMode = (SPDFFitMode)MAX(0, MIN(4, [item[@"fitMode"] integerValue]));
    tab.viewMode = (SPDFViewMode)MAX(0, MIN(1, [item[@"viewMode"] integerValue]));
    tab.scrollOrigin = NSMakePoint([item[@"scrollX"] doubleValue], [item[@"scrollY"] doubleValue]);
    tab.hasScrollOrigin = [item[@"hasScrollOrigin"] boolValue] || item[@"scrollX"] != nil || item[@"scrollY"] != nil;
    if ([item[@"searchText"] isKindOfClass:NSString.class]) tab.searchText = item[@"searchText"];
    tab.searchRegex = [item[@"searchRegex"] boolValue];
    tab.searchRegexMultiline = item[@"searchRegexMultiline"] ? [item[@"searchRegexMultiline"] boolValue] : YES;
    tab.findMatchIndex = item[@"findMatchIndex"] ? [item[@"findMatchIndex"] integerValue] : -1;
    tab.showSidebar = item[@"showSidebar"] ? [item[@"showSidebar"] boolValue] : YES;
    tab.showMinimap = item[@"showMinimap"] ? [item[@"showMinimap"] boolValue] : YES;
    return tab;
}

@implementation SPDFWorkerDocument

- (void)dealloc {
    spdf_close(_document);
}

@end
