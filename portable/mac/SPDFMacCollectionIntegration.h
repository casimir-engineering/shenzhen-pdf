#import "SPDFMacDelegatePrivate.h"
@interface ShenzhenMacDelegate (SPDFMacCollectionHost)
- (void)loadSelectedTab;
@end
@interface ShenzhenMacDelegate (SPDFMacCollectionAPI)
- (void)collectionPrepareForTabPath:(NSString*)path;
- (void)collectionRefreshHistory;
- (BOOL)collectionShowSelectedHistoryPanel;
- (void)collectionRememberSidebarMode;
- (void)collectionSaveArchiveCopy:(id)sender;
- (void)collectionRecordObservedChangeAtPath:(NSString*)path;
- (void)collectionDidSavePath:(NSString*)path;
- (void)collectionClearObservedChangeAtPath:(NSString*)path;
- (void)collectionDidOpenPath:(NSString*)path;
- (void)collectionRememberPasswordForPath:(NSString*)path;
- (void)collectionWillOpenPaths:(NSArray<NSString*>*)paths;
- (void)collectionRecordUserOpenForPath:(NSString*)path document:(NSDictionary*)document;
- (NSUInteger)collectionConsumeUserOpenForPath:(NSString*)path;
- (void)collectionRecordUserOpenCount:(NSUInteger)count document:(NSDictionary*)document;
- (BOOL)collectionProtectPath:(NSString*)path operation:(NSString*)operation;
- (void)installCollectionSettingsMenu:(NSMenu*)menu;
- (void)addCollectionItemsToTabMenu:(NSMenu*)menu path:(NSString*)path;
- (void)showCollectionManager:(id)sender;
- (void)showCollectionManagerForQuery:(NSString*)query;
- (void)showCollectionManagerForDocumentID:(NSString*)documentID query:(NSString*)query;
- (void)showCollectionHistory:(id)sender;
- (void)showCollectionPreviousVersion:(id)sender;
- (void)showCollectionRecovery:(id)sender;
- (void)collectionPresentMissingPath:(NSString*)path;
- (void)collectionOpenPath:(NSString*)path archived:(BOOL)archived;
- (BOOL)openCollectionPaletteResult:(NSDictionary*)result;
@end
