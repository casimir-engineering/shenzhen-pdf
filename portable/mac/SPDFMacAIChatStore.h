#pragma once
#import <Foundation/Foundation.h>
// Disk access is explicit. Each chat has its own atomic file, so different windows
// cannot overwrite unrelated conversations. Credentials never enter this store.
@interface SPDFMacAIChatStore : NSObject
- (instancetype)initWithDirectory:(NSURL*)directory;
+ (NSURL*)defaultDirectory;
- (NSArray<NSDictionary*>*)chats;
- (NSArray<NSDictionary*>*)chatsMatchingQuery:(NSString*)query;
- (NSDictionary*)chatWithID:(NSString*)identifier;
- (BOOL)saveChat:(NSDictionary*)chat error:(NSError**)error;
- (BOOL)deleteChatWithID:(NSString*)identifier error:(NSError**)error;
- (BOOL)deleteAll:(NSError**)error;
// Organization is stored separately: stale conversation saves cannot undo a rename or move.
- (NSArray<NSDictionary*>*)folders;
- (NSString*)createFolderNamed:(NSString*)name error:(NSError**)error;
- (BOOL)renameFolder:(NSString*)identifier name:(NSString*)name error:(NSError**)error;
- (BOOL)removeFolder:(NSString*)identifier error:(NSError**)error;
- (BOOL)setFolder:(NSString*)folderID collapsed:(BOOL)collapsed error:(NSError**)error;
- (BOOL)moveChat:(NSString*)identifier toFolder:(NSString*)folderID error:(NSError**)error;
- (BOOL)renameChat:(NSString*)identifier title:(NSString*)title error:(NSError**)error;
- (BOOL)shouldSuggestTitleForChatID:(NSString*)identifier;
- (BOOL)setSuggestedTitle:(NSString*)title forChatID:(NSString*)identifier error:(NSError**)error;
- (NSDictionary*)savePreview:(NSDictionary*)preview chatID:(NSString*)identifier;
+ (void)discardTemporaryPreview:(NSDictionary*)preview;
@end
