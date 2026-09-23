#import <Cocoa/Cocoa.h>
#import "SPDFMacCollectionWindow.h"

@interface SPDFMacCollectionHistoryController : NSViewController <NSTableViewDataSource,NSTableViewDelegate>
@property(nonatomic, copy) void (^manageHandler)(NSString* documentID);
- (instancetype)initWithStore:(SPDFMacCollectionStore*)store documentID:(NSString*)documentID
                         open:(SPDFCollectionOpenHandler)open;
- (void)reload;
@end
