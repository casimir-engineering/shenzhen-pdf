#pragma once
#import "SPDFMacCollectionIntegration.h"
@interface ShenzhenMacDelegate (SPDFMacCollectionReaderNavigation)
- (void)collectionNavigateDocument:(NSDictionary*)document version:(NSDictionary*)version
                             page:(NSUInteger)page query:(NSString*)query history:(BOOL)history;
- (void)collectionSetVersionInfo:(NSDictionary*)info forTab:(SPDFDocumentTab*)tab;
- (void)collectionRefreshVersionInfoForDocument:(NSDictionary*)document;
- (void)collectionUpdateVersionIndicator;
@end
