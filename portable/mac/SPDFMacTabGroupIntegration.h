#import "SPDFMacDelegatePrivate.h"
#import "SPDFMacTabGroups.h"
@interface ShenzhenMacDelegate (SPDFMacTabGroupIntegration) <SPDFTabGroupReader>
- (void)normalizeTabGroups;
- (void)activateSelectedTabGroup;
- (NSInteger)appendNewTabToActiveGroup:(SPDFDocumentTab*)tab;
@end
