#pragma once
#import "SPDFMacDelegatePrivate.h"
@interface ShenzhenMacDelegate (SPDFMacImageSave)
- (BOOL)saveActiveImageAs;
- (void)completeImageSaveFromPath:(NSString*)source tab:(SPDFDocumentTab*)tab
                    destination:(NSString*)destination asPDF:(BOOL)asPDF;
@end
