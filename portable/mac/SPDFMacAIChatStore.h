#pragma once
#import <Foundation/Foundation.h>
// Disk access is explicit. Each chat has its own atomic file, so different windows
// cannot overwrite unrelated conversations. Credentials never enter this store.
@interface SPDFMacAIChatStore : NSObject
- (instancetype)initWithDirectory:(NSURL*)directory;
+ (NSURL*)defaultDirectory;
- (NSArray<NSDictionary*>*)chats;
- (NSDictionary*)chatWithID:(NSString*)identifier;
- (BOOL)saveChat:(NSDictionary*)chat error:(NSError**)error;
- (BOOL)deleteChatWithID:(NSString*)identifier error:(NSError**)error;
- (BOOL)deleteAll:(NSError**)error;
- (NSDictionary*)savePreview:(NSDictionary*)preview chatID:(NSString*)identifier;
+ (void)discardTemporaryPreview:(NSDictionary*)preview;
@end
