#import <Cocoa/Cocoa.h>
#import "SPDFMacCollectionWindow.h"

@interface SPDFMacCollectionHistoryController : NSViewController <NSTableViewDataSource,NSTableViewDelegate>
- (instancetype)initWithStore:(SPDFMacCollectionStore*)store documentID:(NSString*)documentID
                         open:(SPDFCollectionOpenHandler)open;
- (void)reload;
@end
