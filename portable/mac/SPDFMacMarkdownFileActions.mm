#import "SPDFMacMarkdownDelegatePrivate.h"

#import "SPDFMacFileExplorerPreference.h"
#import "SPDFMacMarkdownPrinting.h"
#import "markdown/SPDFMarkdown.h"

@implementation ShenzhenMacDelegate (SPDFMacMarkdownFileActions)

// The active Markdown session can serve single-page copies once its live
// pagination plan and rendered text exist and pageIndex names a planned page.
// Deliberately probes the LIVE plan, not the export one: this runs from
// -validateMenuItem: on every menu pass, and must never build a rendition.
- (BOOL)markdownSessionCanCopyPageAtIndex:(NSInteger)pageIndex {
    SPDFMacMarkdownSession* session = self.activeMarkdownSession;
    return session.paginationPlan != nil && session.renderedDocument.attributedString != nil && pageIndex >= 0 &&
           pageIndex < (NSInteger)session.paginationPlan.pages.count;
}

// Copy Page honors the context-clicked page when the context menu set one,
// falling back to the current page — mirroring the PDF tab's behavior.
- (NSInteger)markdownCopyPageIndex {
    return _contextPageIndex >= 0 ? _contextPageIndex : self.activeMarkdownSession.currentPageIndex;
}

- (BOOL)canCopyCurrentPageAsPDF {
    if ([self isMarkdownActive]) return [self markdownSessionCanCopyPageAtIndex:[self markdownCopyPageIndex]];
    return _doc != NULL && _path.length > 0;
}

- (BOOL)canCopyCurrentPageImage {
    if ([self isMarkdownActive])
        return [self markdownSessionCanCopyPageAtIndex:self.activeMarkdownSession.currentPageIndex];
    return _doc != NULL && _pageIndex >= 0 && _pageIndex < (NSInteger)_renderedPages.count &&
           _renderedPages[(NSUInteger)_pageIndex].image != nil;
}

- (void)openInExternalReader:(id)sender {
    (void)sender;
    if (!_path.length) {
        NSBeep();
        return;
    }

    NSURL* fileURL = [NSURL fileURLWithPath:_path];
    NSURL* acrobat = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.adobe.Reader"];
    if (!acrobat)
        acrobat = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.adobe.Acrobat.Pro"];
    if (acrobat) {
        NSWorkspaceOpenConfiguration* config = [NSWorkspaceOpenConfiguration configuration];
        [NSWorkspace.sharedWorkspace openURLs:@[ fileURL ]
                         withApplicationAtURL:acrobat
                                configuration:config
                            completionHandler:nil];
    } else {
        [NSWorkspace.sharedWorkspace openURL:fileURL];
    }
}

- (void)showPathInFolder:(NSString*)path {
    if (!SPDFMacRevealPathUsingPreference(path)) NSBeep();
}

- (void)showInFolder:(id)sender {
    (void)sender;
    if (![self hasActiveDocument] || !_path.length) {
        NSBeep();
        return;
    }
    [self showPathInFolder:_path];
}

- (void)copyCurrentDocumentPath:(id)sender {
    (void)sender;
    if (![self hasActiveDocument] || !_path.length) {
        NSBeep();
        return;
    }
    [self copyPathStringToPasteboard:_path statusMessage:@"Path copied."];
}

- (void)copyCurrentDocumentFile:(id)sender {
    (void)sender;
    if (![self hasActiveDocument] || !_path.length) {
        NSBeep();
        return;
    }
    [self copyTabFileToPasteboardAtIndex:_selectedTabIndex];
}

- (void)copyCurrentPageImage:(id)sender {
    (void)sender;
    if ([self isMarkdownActive]) {
        SPDFMacMarkdownSession* session = self.activeMarkdownSession;
        NSInteger pageIndex = session.currentPageIndex;
        if (![self markdownSessionCanCopyPageAtIndex:pageIndex] ||
            ![SPDFMacMarkdownPrintAdapter copyPageImageAtIndex:(NSUInteger)pageIndex
                                                paginationPlan:session.exportPaginationPlan
                                              attributedString:session.exportAttributedString
                                                  toPasteboard:NSPasteboard.generalPasteboard]) {
            NSBeep();
            return;
        }
        _statusLabel.stringValue = @"Page image copied.";
        return;
    }
    if (!_doc || _pageIndex < 0 || _pageIndex >= (NSInteger)_renderedPages.count ||
        !_renderedPages[(NSUInteger)_pageIndex].image) {
        NSBeep();
        return;
    }
    // Copy the document's OWN colors, like Print and Save as PDF: the cached
    // image may be recolored for the dark reading theme, and a pasted page
    // carrying our dark paper would be wrong wherever it lands. Re-render at
    // the cached page's own zoom and scale when that is the case.
    SPDFRenderedPage* cached = _renderedPages[(NSUInteger)_pageIndex];
    NSImage* image = cached.image;
    if (cached.imageDarkTheme) {
        char err[512];
        BOOL darkTheme = _darkReadingTheme;
        _darkReadingTheme = NO;
        SPDFRenderedPage* original = [self renderedPageAtIndex:_pageIndex
                                                      document:_doc
                                                          zoom:cached.imageZoom
                                                  displayScale:cached.imageScale
                                                         error:err
                                                   errorLength:sizeof(err)];
        _darkReadingTheme = darkTheme;
        if (!original.image) {
            NSBeep();
            return;
        }
        image = original.image;
    }

    NSPasteboard* pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard writeObjects:@[ image ]];
    _statusLabel.stringValue = @"Page image copied.";
}

- (void)copyCurrentPageAsPDF:(id)sender {
    (void)sender;
    if ([self isMarkdownActive]) {
        SPDFMacMarkdownSession* session = self.activeMarkdownSession;
        NSInteger pageIndex = [self markdownCopyPageIndex];
        if (![self markdownSessionCanCopyPageAtIndex:pageIndex]) {
            NSBeep();
            return;
        }
        NSString* base = _path.lastPathComponent.stringByDeletingPathExtension;
        NSString* fileName =
            [NSString stringWithFormat:@"%@ - page %ld.pdf", base.length ? base : @"Page", (long)(pageIndex + 1)];
        if (![SPDFMacMarkdownPrintAdapter copyPageAtIndex:(NSUInteger)pageIndex
                                           paginationPlan:session.exportPaginationPlan
                                         attributedString:session.exportAttributedString
                                                 fileName:fileName
                                             toPasteboard:NSPasteboard.generalPasteboard]) {
            NSBeep();
            return;
        }
        _statusLabel.stringValue = @"Page copied.";
        return;
    }
    NSInteger pageIndex = _contextPageIndex >= 0 ? _contextPageIndex : _pageIndex;
    if (!_doc || !_path.length || pageIndex < 0 || pageIndex >= spdf_page_count(_doc)) {
        NSBeep();
        return;
    }
    NSString* base = _path.lastPathComponent.stringByDeletingPathExtension;
    NSString* fileName =
        [NSString stringWithFormat:@"%@ - page %ld.pdf", base.length ? base : @"Page", (long)(pageIndex + 1)];
    NSString* directory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ShenzhenPDF-copy"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
    NSString* tempPath = [directory stringByAppendingPathComponent:fileName];

    char err[1024];
    if (!spdf_save_single_page_pdf(_doc, (int)pageIndex, tempPath.fileSystemRepresentation, err, sizeof(err))) {
        [self showError:@"Could not copy page"
                 detail:[NSString stringWithFormat:@"%s", err[0] ? err : "The page could not be written as a PDF."]];
        return;
    }

    NSPasteboard* pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    NSPasteboardItem* item = [[NSPasteboardItem alloc] init];
    NSData* pdfData = [NSData dataWithContentsOfFile:tempPath];
    if (pdfData) [item setData:pdfData forType:NSPasteboardTypePDF];
    [item setString:[NSURL fileURLWithPath:tempPath].absoluteString forType:NSPasteboardTypeFileURL];
    if (![pasteboard writeObjects:@[ item ]]) {
        NSBeep();
        return;
    }
    _statusLabel.stringValue = @"Page copied.";
}

@end
