#import "SPDFMacDelegatePrivate.h"
#import "SPDFMacTabGroups.h"
@interface ShenzhenMacDelegate (SPDFMacTabGroupIntegration) <SPDFTabGroupReader>
- (SPDFTabGroup*)ensureGeneralTabGroup;
- (void)normalizeTabGroups;
- (void)activateSelectedTabGroup;
- (NSInteger)appendNewTabToActiveGroup:(SPDFDocumentTab*)tab;
@end
