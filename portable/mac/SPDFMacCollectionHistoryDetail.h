#pragma once
#import "SPDFMacCollectionWindow.h"
#import <PDFKit/PDFKit.h>

// Created only on explicit History entry. Previewing never opens the source or changes usage counts.
@interface SPDFMacCollectionHistoryDetailController : NSViewController <NSTableViewDataSource,NSTableViewDelegate>
@property(nonatomic, readonly) NSDictionary* document;
@property(nonatomic, readonly) NSDictionary* selectedVersion;
@property(nonatomic, readonly) PDFView* reader;
@property(nonatomic, readonly) NSTableView* table;
@property(nonatomic, readonly) NSButton* keepButton;
@property(nonatomic, readonly) NSTextField* protection;
@property(nonatomic, copy) void (^back)(void);
@property(nonatomic, copy) void (^selectionChanged)(void);
@property(nonatomic, copy) NSString* searchQuery;
- (instancetype)initWithStore:(SPDFMacCollectionStore*)store document:(NSDictionary*)document
                      version:(NSDictionary*)version page:(NSUInteger)page actionTarget:(id)target;
- (void)invalidate;
- (void)reload;
- (void)selectVersionID:(NSString*)identifier;
@end
