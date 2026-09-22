#import <Cocoa/Cocoa.h>
@class SPDFMacCollectionStore;
typedef void (^SPDFCollectionOpenHandler)(NSString* path, BOOL archived);
@interface SPDFMacCollectionWindow : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
- (instancetype)initWithStore:(SPDFMacCollectionStore*)store open:(SPDFCollectionOpenHandler)open;
- (void)showDocumentID:(NSString*)documentID query:(NSString*)query;
@end
void SPDFMacLocateCollectionOriginal(SPDFMacCollectionStore* store, NSString* documentID,
                                    NSWindow* parent, void (^preview)(NSString* path),
                                    void (^completion)(NSString* path));
