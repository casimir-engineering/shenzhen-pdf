#import "SPDFMacCollectionWindow.h"
#import "SPDFMacCollectionStore.h"
#import "SPDFMacCollectionCompare.h"
@interface SPDFMacCollectionWindow ()
@property(nonatomic) SPDFMacCollectionStore* store;
@property(nonatomic, copy) SPDFCollectionOpenHandler openHandler;
@property(nonatomic) NSPopUpButton* viewPicker;
@property(nonatomic) NSPopUpButton* layoutPicker;
@property(nonatomic) NSPopUpButton* sortPicker;
@property(nonatomic) NSSearchField* search;
@property(nonatomic) NSTableView* table;
@property(nonatomic) NSScrollView* listScroll;
@property(nonatomic) NSScrollView* gridScroll;
@property(nonatomic) NSCollectionView* grid;
@property(nonatomic) NSCache<NSString*, NSImage*>* thumbnailCache;
@property(nonatomic) NSOperationQueue* thumbnailQueue;
@property(nonatomic) NSMutableSet<NSString*>* pendingThumbnails;
@property(nonatomic) NSTextField* details;
@property(nonatomic) NSTextField* storage;
@property(nonatomic) NSButton* enabled;
@property(nonatomic) NSTextField* limitField;
@property(nonatomic) NSArray<NSDictionary*>* rows;
@property(nonatomic) NSArray<NSDictionary*>* documents;
@property(nonatomic) NSString* documentID;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL mutationPending;
@property(nonatomic) NSMutableArray<NSButton*>* selectionButtons;
- (void)reload:(id)sender;
- (NSDictionary*)selectedDocument;
- (NSDictionary*)selectedVersion;
- (void)updateDetails;
- (void)showError:(NSError*)error;
@end
@interface SPDFMacCollectionWindow (Actions)
- (void)openOriginal:(id)sender;
- (void)preview:(id)sender;
- (void)history:(id)sender;
- (void)compareCurrent:(id)sender;
- (void)comparePrevious:(id)sender;
- (void)locate:(id)sender;
- (void)exportCopy:(id)sender;
- (void)keep:(id)sender;
- (void)exclude:(id)sender;
- (void)deleteSelected:(id)sender;
- (void)changeEnabled:(id)sender;
- (void)changeLimit:(id)sender;
- (void)changeLocation:(id)sender;
@end
@interface SPDFMacCollectionWindow (Grid)
- (void)installGridInView:(NSView*)host;
- (void)reloadGrid;
- (void)synchronizeGridSelection;
@end
