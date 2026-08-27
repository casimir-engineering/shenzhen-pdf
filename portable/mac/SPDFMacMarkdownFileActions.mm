#import "SPDFMacMarkdownDelegatePrivate.h"

#import "SPDFMacFileExplorerPreference.h"

@implementation ShenzhenMacDelegate (SPDFMacMarkdownFileActions)

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
    if (!_doc || _pageIndex < 0 || _pageIndex >= (NSInteger)_renderedPages.count ||
        !_renderedPages[(NSUInteger)_pageIndex].image) {
        NSBeep();
        return;
    }
    if (!spdf_has_permission(_doc, 'c')) {
        [self showError:@"Copying is not allowed"
                 detail:@"This PDF's permissions do not allow content copying."];
        return;
    }

    NSPasteboard* pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard writeObjects:@[ _renderedPages[(NSUInteger)_pageIndex].image ]];
    _statusLabel.stringValue = @"Page image copied.";
}

- (void)copyCurrentPageAsPDF:(id)sender {
    (void)sender;
    NSInteger pageIndex = _contextPageIndex >= 0 ? _contextPageIndex : _pageIndex;
    if (!_doc || !_path.length || pageIndex < 0 || pageIndex >= spdf_page_count(_doc)) {
        NSBeep();
        return;
    }
    if (!spdf_has_permission(_doc, 'c')) {
        [self showError:@"Copying is not allowed"
                 detail:@"This PDF's permissions do not allow content copying."];
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
