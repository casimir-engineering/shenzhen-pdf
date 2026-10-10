#pragma once
#import <Cocoa/Cocoa.h>
@interface SPDFMacAIChatHistoryView : NSView <NSTableViewDataSource,NSTableViewDelegate,NSSearchFieldDelegate>
@property(nonatomic,copy) void (^action)(NSString*);
@property(nonatomic,copy) void (^searchChanged)(NSString*);
@property(nonatomic,readonly) NSSearchField* search;
- (void)displayFolders:(NSArray<NSDictionary*>*)folders;
- (void)displayChats:(NSArray<NSDictionary*>*)chats selectedID:(NSString*)identifier;
@end
