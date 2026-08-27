#pragma once

#import "SPDFMacDelegatePrivate.h"
#import "SPDFMacMarkdownSession.h"

// Private bridge used by the focused Markdown and shared file-action category
// implementations. Keeping these declarations here avoids growing the main
// delegate interface with cross-module implementation details.
@interface ShenzhenMacDelegate (SPDFMacMarkdownHostAccess)
- (NSDictionary*)fileAttributesForPath:(NSString*)path;
- (void)recordFileAttributes:(NSDictionary*)attributes forTab:(SPDFDocumentTab*)tab;
- (void)prepareSelectedTabViewState:(SPDFDocumentTab*)tab path:(NSString*)path;
- (void)showUnavailableSelectedTab:(SPDFDocumentTab*)tab
                              path:(NSString*)path
                           message:(NSString*)message
                     showOpenError:(BOOL)showOpenError
                             error:(const char*)error;
- (NSInteger)indexOfTabForPath:(NSString*)path;
- (void)updateTabStrip;
- (void)updateControls;
- (void)rememberRecentlyOpenedPath:(NSString*)path;
- (void)setSidebarActuallyVisible:(BOOL)visible;
- (void)showError:(NSString*)message detail:(NSString*)detail;
- (void)ensureSecurityAccessForPath:(NSString*)path;
- (NSString*)displayNameForPathConsideringOpenTabs:(NSString*)path;
- (void)copyPathStringToPasteboard:(NSString*)path statusMessage:(NSString*)statusMessage;
- (void)copyTabFileToPasteboardAtIndex:(NSInteger)index;
@end

@interface ShenzhenMacDelegate (SPDFMacMarkdownIntegration)
- (void)installMarkdownHostInDocumentContainer;
- (SPDFMacMarkdownSession*)activeMarkdownSession;
- (BOOL)isMarkdownActive;
- (BOOL)hasActiveDocument;
- (void)deactivateActiveMarkdownView;
- (void)loadSelectedMarkdownTab:(SPDFDocumentTab*)tab;
- (void)rememberActiveMarkdownStateForTab:(SPDFDocumentTab*)tab;
- (void)startMarkdownFindForQuery:(NSString*)query preferredIndex:(NSInteger)preferredIndex;
- (void)moveMarkdownFindForward:(BOOL)forward;
- (void)clearMarkdownFindResults;
- (NSString*)markdownSelectedText;
- (void)printActiveMarkdown;
- (void)saveActiveMarkdownAsPDF;
- (void)updateControlsForActiveMarkdown;
@end

@interface ShenzhenMacDelegate (SPDFMacMarkdownFileActions)
- (void)openInExternalReader:(id)sender;
- (void)showPathInFolder:(NSString*)path;
- (void)showInFolder:(id)sender;
- (void)copyCurrentDocumentPath:(id)sender;
- (void)copyCurrentDocumentFile:(id)sender;
- (void)copyCurrentPageImage:(id)sender;
- (void)copyCurrentPageAsPDF:(id)sender;
@end
