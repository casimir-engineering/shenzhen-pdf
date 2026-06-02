#import <Cocoa/Cocoa.h>

#include "shenzhen_pdf_core.h"

typedef NS_ENUM(NSInteger, SPDFFitMode) {
    SPDFFitModeCustom = 0,
    SPDFFitModeActual,
    SPDFFitModeWidth,
    SPDFFitModeHeight,
    SPDFFitModePage
};

typedef NS_ENUM(NSInteger, SPDFViewMode) {
    SPDFViewModeSingle = 0,
    SPDFViewModeContinuous
};

typedef NS_ENUM(NSInteger, SPDFSidebarMode) {
    SPDFSidebarModeChapters = 0,
    SPDFSidebarModeComments = 1
};

@interface SPDFRenderedPage : NSObject
@property(nonatomic) NSInteger pageIndex;
@property(nonatomic) CGFloat pageWidth;
@property(nonatomic) CGFloat pageHeight;
@property(nonatomic) CGFloat imagePointWidth;
@property(nonatomic) CGFloat imagePointHeight;
@property(nonatomic) CGFloat imageZoom;
@property(nonatomic) CGFloat imageScale;
@property(nonatomic, strong) NSImage* image;
@property(nonatomic, copy) NSArray<NSValue*>* highlights;
@property(nonatomic, copy) NSArray<NSValue*>* selectionRects;
@end

@interface SPDFDocumentTab : NSObject
@property(nonatomic, copy) NSString* path;
@property(nonatomic, copy) NSString* title;
@property(nonatomic) NSInteger pageIndex;
@property(nonatomic) CGFloat zoom;
@property(nonatomic) CGFloat customZoom;
@property(nonatomic) SPDFFitMode fitMode;
@property(nonatomic) SPDFViewMode viewMode;
@property(nonatomic) NSPoint scrollOrigin;
@property(nonatomic) BOOL hasScrollOrigin;
@property(nonatomic, copy) NSString* searchText;
@property(nonatomic) BOOL searchRegex;
@property(nonatomic) BOOL searchRegexMultiline;
@property(nonatomic) NSInteger findMatchIndex;
@property(nonatomic) BOOL showSidebar;
@property(nonatomic) BOOL showMinimap;
@property(nonatomic) BOOL missingFile;
@property(nonatomic, copy) NSString* missingMessage;
@end

@interface SPDFWorkerDocument : NSObject
@property(nonatomic) spdf_document* document;
@property(nonatomic, copy) NSString* path;
@end

SPDFDocumentTab* spdf_copy_document_tab(SPDFDocumentTab* source);
NSDictionary* spdf_dictionary_from_tab(SPDFDocumentTab* tab, NSInteger sourceWindowNumber);
SPDFDocumentTab* spdf_tab_from_dictionary(NSDictionary* item);
