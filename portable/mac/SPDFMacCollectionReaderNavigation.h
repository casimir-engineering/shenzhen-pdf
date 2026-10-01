#pragma once
#import "SPDFMacCollectionIntegration.h"
@interface ShenzhenMacDelegate (SPDFMacCollectionReaderNavigation)
- (void)collectionNavigateDocument:(NSDictionary*)document version:(NSDictionary*)version
                             page:(NSUInteger)page query:(NSString*)query history:(BOOL)history;
- (void)collectionSetVersionInfo:(NSDictionary*)info forTab:(SPDFDocumentTab*)tab;
- (void)collectionRefreshVersionInfoForDocument:(NSDictionary*)document;
- (void)collectionUpdateVersionIndicator;
// Cached tab identity only; does not open the store or touch the filesystem.
- (BOOL)collectionTabIsSavedVersion:(SPDFDocumentTab*)tab;
@end
