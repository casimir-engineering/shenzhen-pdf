#import "SPDFMacDelegatePrivate.h"
#import "SPDFMacMarkdownDelegatePrivate.h"

@interface ShenzhenMacDelegate (SPDFMacContextMenuPrivate)
- (NSInteger)commentIndexAtPageIndex:(NSInteger)pageIndex pagePoint:(NSPoint)pagePoint;
- (NSString*)shortSelectedTextForMenuTitle;
@end

@implementation ShenzhenMacDelegate (SPDFMacContextMenuIntegration)

- (NSMenu*)contextMenuForDocumentView:(NSView*)view event:(NSEvent*)event {
    [self documentViewEndHoverComment];
    _contextPageIndex = -1;
    _contextPagePoint = NSZeroPoint;
    _contextCommentIndex = -1;
    if ([view isKindOfClass:SPDFDocumentView.class]) {
        SPDFDocumentView* documentView = (SPDFDocumentView*)view;
        NSPoint point = [documentView convertPoint:event.locationInWindow fromView:nil];
        [documentView point:point fallsInPage:&_contextPageIndex pagePoint:&_contextPagePoint];
        _contextCommentIndex = [self commentIndexAtPageIndex:_contextPageIndex pagePoint:_contextPagePoint];
    }

    BOOL markdown = [self isMarkdownActive];
    NSString* selectedText = markdown ? [self markdownSelectedText] : (_selectedText ?: @"");
    if (markdown) _contextPageIndex = self.activeMarkdownSession.currentPageIndex;
    NSMenu* menu = [[NSMenu alloc] initWithTitle:@""];
    BOOL contentCopyAllowed = markdown || (_doc && spdf_has_permission(_doc, 'c'));
    if (selectedText.length > 0) {
        NSString* preview = [self shortSelectedTextForMenuTitle];
        NSMenuItem* translateSelection =
            [menu addItemWithTitle:preview.length ? [NSString stringWithFormat:@"Translate \"%@\"", preview]
                                                  : @"Translate Selection"
                            action:@selector(showSelectionTranslationPanel:)
                     keyEquivalent:@""];
        translateSelection.target = self;
        translateSelection.enabled = contentCopyAllowed && !_translationRunning && !_translationInstallRunning;
        NSMenuItem* webSearch =
            [menu addItemWithTitle:preview.length ? [NSString stringWithFormat:@"Search Web for \"%@\"", preview]
                                                  : @"Search Web"
                            action:@selector(searchSelectedTextInBrowser:)
                     keyEquivalent:@""];
        webSearch.target = self;
        webSearch.enabled = contentCopyAllowed;
        [menu addItem:[NSMenuItem separatorItem]];
    }
    NSMenuItem* copy = [menu addItemWithTitle:@"Copy" action:@selector(copySelection:) keyEquivalent:@""];
    copy.target = self;
    copy.enabled = contentCopyAllowed && selectedText.length > 0;
    if (!markdown && _contextCommentIndex >= 0) {
        NSMenuItem* editComment = [menu addItemWithTitle:@"Edit Comment..."
                                                  action:@selector(editComment:)
                                           keyEquivalent:@""];
        editComment.target = self;
        editComment.representedObject = @(_contextCommentIndex);
        NSMenuItem* deleteComment = [menu addItemWithTitle:@"Delete Comment..."
                                                    action:@selector(deleteComment:)
                                             keyEquivalent:@""];
        deleteComment.target = self;
        deleteComment.representedObject = @(_contextCommentIndex);
    }
    NSMenuItem* addComment = [menu addItemWithTitle:@"Add Comment..." action:@selector(addComment:) keyEquivalent:@""];
    addComment.enabled = !markdown && _doc != NULL && (selectedText.length > 0 || _contextPageIndex >= 0);
    NSMenuItem* favorite = [menu addItemWithTitle:@"Favorite Page"
                                           action:@selector(favoriteCurrentPage:)
                                    keyEquivalent:@""];
    favorite.enabled = !markdown && _doc != NULL;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Zoom In" action:@selector(zoomIn:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Zoom Out" action:@selector(zoomOut:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Fit Width" action:@selector(fitWidth:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Fit Page" action:@selector(fitPage:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* showInFolder = [menu addItemWithTitle:@"Show in Folder"
                                               action:@selector(showInFolder:)
                                        keyEquivalent:@""];
    showInFolder.enabled = [self hasActiveDocument] && _path.length > 0;
    NSMenuItem* copyDocument = [menu addItemWithTitle:@"Copy Document"
                                               action:@selector(copyCurrentDocumentFile:)
                                        keyEquivalent:@""];
    copyDocument.enabled = [self hasActiveDocument] && _path.length > 0;
    NSMenuItem* copyPage = [menu addItemWithTitle:@"Copy Page"
                                           action:@selector(copyCurrentPageAsPDF:)
                                    keyEquivalent:@""];
    copyPage.enabled =
        !markdown && contentCopyAllowed && _path.length > 0 && (_contextPageIndex >= 0 || _pageIndex >= 0);
    NSMenuItem* copyImage = [menu addItemWithTitle:@"Copy Page Image"
                                            action:@selector(copyCurrentPageImage:)
                                     keyEquivalent:@""];
    copyImage.enabled = !markdown && contentCopyAllowed && _pageIndex >= 0 &&
                        _pageIndex < (NSInteger)_renderedPages.count &&
                        _renderedPages[(NSUInteger)_pageIndex].image != nil;
    NSMenuItem* copyPath = [menu addItemWithTitle:@"Copy Path"
                                           action:@selector(copyCurrentDocumentPath:)
                                    keyEquivalent:@""];
    copyPath.enabled = [self hasActiveDocument] && _path.length > 0;
    NSMenuItem* properties = [menu addItemWithTitle:@"Properties..."
                                             action:@selector(showProperties:)
                                      keyEquivalent:@""];
    properties.enabled = !markdown && _doc != NULL;
    spdf_apply_system_icons_to_menu(menu);
    return menu;
}

@end
