#import "SPDFMacAIChatStore.h"
#import <sys/stat.h>
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>
static BOOL ValidID(NSString* value) { return [value isKindOfClass:NSString.class] && [[NSUUID alloc] initWithUUIDString:value]; }
@implementation SPDFMacAIChatStore { NSURL* _directory; }
+ (NSURL*)defaultDirectory {
    NSString* root = NSProcessInfo.processInfo.environment[@"SPDF_STATE_DIR"];
    if (!root.length) root = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/ShenzhenPDF"];
    return [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"Chats"] isDirectory:YES];
}
- (instancetype)initWithDirectory:(NSURL*)directory { if ((self=[super init])) _directory=directory; return self; }
- (NSURL*)URLForID:(NSString*)identifier {
    return ValidID(identifier) ? [_directory URLByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"json"]] : nil;
}
- (NSDictionary*)chatWithID:(NSString*)identifier {
    NSURL* URL=[self URLForID:identifier]; if (!URL) return nil;
    NSNumber* size=nil; [URL getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    if (size.unsignedLongLongValue>8*1024*1024) return nil;
    NSData* data=[NSData dataWithContentsOfURL:URL options:NSDataReadingMappedIfSafe error:nil];
    id chat=data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
    if (![chat isKindOfClass:NSDictionary.class] || ![chat[@"id"] isEqual:identifier] ||
        ![chat[@"messages"] isKindOfClass:NSArray.class]) return nil;
    if ((chat[@"title"] && ![chat[@"title"] isKindOfClass:NSString.class]) ||
        (chat[@"updated"] && ![chat[@"updated"] isKindOfClass:NSNumber.class]) || [chat[@"messages"] count]>512) return nil;
    NSMutableSet* pending=[NSMutableSet set]; NSMutableSet* seen=[NSMutableSet set];
    for (id message in chat[@"messages"]) {
        if (![message isKindOfClass:NSDictionary.class] || ![message[@"role"] isKindOfClass:NSString.class] ||
            (message[@"content"] && message[@"content"]!=NSNull.null && ![message[@"content"] isKindOfClass:NSString.class])) return nil;
        NSString* role=message[@"role"];
        if ([role isEqual:@"preview"]) {
            if (![message[@"local"] isEqual:@YES] || ![message[@"preview"] isKindOfClass:NSDictionary.class]) return nil;
            continue;
        }
        if (message[@"local"] || ![@[@"user",@"assistant",@"tool"] containsObject:role]) return nil;
        if ([role isEqual:@"tool"]) {
            NSString* call=message[@"tool_call_id"];
            if (![call isKindOfClass:NSString.class] || ![pending containsObject:call] || ![message[@"content"] isKindOfClass:NSString.class]) return nil;
            [pending removeObject:call]; continue;
        }
        if (pending.count) return nil;
        id calls=message[@"tool_calls"];
        if (calls && (![role isEqual:@"assistant"] || ![calls isKindOfClass:NSArray.class] || [calls count]>12)) return nil;
        for (id call in calls) {
            if (![call isKindOfClass:NSDictionary.class] || ![call[@"id"] isKindOfClass:NSString.class] || ![call[@"id"] length] ||
                [seen containsObject:call[@"id"]] || ![call[@"function"] isKindOfClass:NSDictionary.class]) return nil;
            id function=call[@"function"], raw=function[@"arguments"];
            if (![function[@"name"] isKindOfClass:NSString.class] || ![raw isKindOfClass:NSString.class] || [raw length]>65536) return nil;
            id args=[NSJSONSerialization JSONObjectWithData:[raw dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            if (![args isKindOfClass:NSDictionary.class]) return nil;
            [pending addObject:call[@"id"]]; [seen addObject:call[@"id"]];
        }
    }
    // A terminated process may leave a persisted assistant action without its result.
    // Complete those pairs explicitly; never replay the action automatically.
    for (NSString* identifier in pending) [chat[@"messages"] addObject:@{@"role":@"tool",@"tool_call_id":identifier,
        @"content":@"{\"cancelled\":true,\"reason\":\"Previous session ended\"}"}];
    return chat;
}
- (NSArray<NSDictionary*>*)chats { return [self chatsMatchingQuery:@""]; }
- (NSArray<NSDictionary*>*)chatsMatchingQuery:(NSString*)query {
    NSMutableArray* chats=[NSMutableArray array];
    NSArray* URLs=[NSFileManager.defaultManager contentsOfDirectoryAtURL:_directory includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    for (NSURL* URL in URLs) {
        if (![URL.pathExtension isEqual:@"json"]) continue;
        NSDictionary* chat=[self chatWithID:URL.lastPathComponent.stringByDeletingPathExtension];
        if(query.length && chat) {
            BOOL found=[chat[@"title"] localizedCaseInsensitiveContainsString:query];
            for(NSDictionary* message in chat[@"messages"]) if(!found && [@[@"user",@"assistant"] containsObject:message[@"role"]])
                found=[message[@"content"] isKindOfClass:NSString.class] && [message[@"content"] localizedCaseInsensitiveContainsString:query];
            if(!found)continue;
        }
        if (chat) [chats addObject:@{@"id":chat[@"id"],@"title":chat[@"title"] ?: @"New chat",@"updated":chat[@"updated"] ?: @0}];
    }
    return [chats sortedArrayUsingComparator:^NSComparisonResult(NSDictionary* a, NSDictionary* b) { return [b[@"updated"] compare:a[@"updated"]]; }];
}
- (int)lockStore:(NSError**)error {
    if (![NSFileManager.defaultManager createDirectoryAtURL:_directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error]) return -1;
    int fd=open([[_directory URLByAppendingPathComponent:@".lock"] fileSystemRepresentation],O_CREAT|O_RDWR|O_NOFOLLOW,0600);
    if (fd<0 || flock(fd,LOCK_EX)!=0) { if (fd>=0) close(fd); return -1; } return fd;
}
- (NSURL*)tombstone:(NSString*)identifier {
    return [[_directory URLByAppendingPathComponent:@".deleted"] URLByAppendingPathComponent:identifier];
}
- (BOOL)saveChat:(NSDictionary*)chat error:(NSError**)error {
    NSURL* URL=[self URLForID:chat[@"id"]];
    if (!URL || ![NSJSONSerialization isValidJSONObject:chat]) return NO;
    NSData* data=[NSJSONSerialization dataWithJSONObject:chat options:0 error:error];
    if (!data || data.length>8*1024*1024) return NO;
    // Compare the exact serialized snapshot that will be committed, never mutable caller state.
    chat=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    int fd=[self lockStore:error]; if (fd<0) return NO;
    BOOL removed=[NSFileManager.defaultManager fileExistsAtPath:[self tombstone:chat[@"id"]].path];
    BOOL conflict=NO;
    if (!removed && [NSFileManager.defaultManager fileExistsAtPath:URL.path]) {
        NSData* existing=[NSData dataWithContentsOfURL:URL options:NSDataReadingMappedIfSafe error:nil];
        id previous=existing.length<=8*1024*1024 ? [NSJSONSerialization JSONObjectWithData:existing options:0 error:nil] : nil;
        NSArray* old=[previous isKindOfClass:NSDictionary.class] ? previous[@"messages"] : nil;
        NSArray* incoming=chat[@"messages"];
        if (![old isKindOfClass:NSArray.class] || ![incoming isKindOfClass:NSArray.class] || old.count>incoming.count) conflict=YES;
        else for (NSUInteger i=0;i<old.count;i++) if (![old[i] isEqual:incoming[i]]) { conflict=YES; break; }
    }
    BOOL ok=!removed && !conflict && [data writeToURL:URL options:NSDataWritingAtomic error:error];
    if (conflict && error) *error=[NSError errorWithDomain:@"ShenzhenPDF.Chat" code:2 userInfo:@{NSLocalizedDescriptionKey:@"This chat changed in another window. Reopen it from Chats before continuing. Your unsaved conversation remains visible here."}];
    if (removed && error) *error=[NSError errorWithDomain:@"ShenzhenPDF.Chat" code:1 userInfo:@{NSLocalizedDescriptionKey:@"This chat was deleted in another window. Start a new chat."}];
    if (ok) chmod(URL.fileSystemRepresentation,0600);
    flock(fd,LOCK_UN); close(fd); return ok;
}
- (NSDictionary*)savePreview:(NSDictionary*)preview chatID:(NSString*)identifier {
    if (!ValidID(identifier) || ![preview[@"path"] isKindOfClass:NSString.class]) return nil;
    NSURL* source=[NSURL fileURLWithPath:preview[@"path"]];
    NSDictionary* result=nil;
    @try {
        NSNumber* size=nil; [source getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        if (!size || size.unsignedLongLongValue>8*1024*1024) return nil;
        NSData* data=[NSData dataWithContentsOfURL:source options:0 error:nil];
        static const unsigned char signature[]={137,80,78,71,13,10,26,10};
        if (data.length<8 || memcmp(data.bytes,signature,8)!=0) return nil;
        int fd=[self lockStore:nil]; if (fd<0) return nil;
        @try {
            if ([NSFileManager.defaultManager fileExistsAtPath:[self tombstone:identifier].path]) return nil;
            NSURL* assets=[_directory URLByAppendingPathComponent:[identifier stringByAppendingString:@"-assets"] isDirectory:YES];
            if (![NSFileManager.defaultManager createDirectoryAtURL:assets withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil]) return nil;
            NSURL* target=[assets URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"png"]];
            if (![data writeToURL:target options:NSDataWritingAtomic error:nil]) return nil;
            chmod(target.fileSystemRepresentation,0600);
            NSMutableDictionary* saved=[preview mutableCopy]; saved[@"path"]=target.path; result=saved;
        } @finally { flock(fd,LOCK_UN); close(fd); }
    } @finally { [SPDFMacAIChatStore discardTemporaryPreview:preview]; }
    return result;
}
+ (void)discardTemporaryPreview:(NSDictionary*)preview {
    NSString* path=preview[@"path"];
    if (![path isKindOfClass:NSString.class]) return;
    NSString* parent=path.stringByDeletingLastPathComponent.stringByResolvingSymlinksInPath;
    NSString* temp=NSTemporaryDirectory().stringByResolvingSymlinksInPath;
    if ([path.lastPathComponent isEqual:@"page.png"] && [parent.stringByDeletingLastPathComponent isEqual:temp] &&
        [parent.lastPathComponent hasPrefix:@"ShenzhenPDF-AI-"] &&
        ValidID([parent.lastPathComponent substringFromIndex:[@"ShenzhenPDF-AI-" length]]))
        [NSFileManager.defaultManager removeItemAtPath:parent error:nil];
}
- (BOOL)deleteUnlocked:(NSString*)identifier error:(NSError**)error {
    NSURL* URL=[self URLForID:identifier]; if (!URL) return NO;
    NSURL* tombstone=[self tombstone:identifier];
    if (![NSFileManager.defaultManager createDirectoryAtURL:tombstone.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error] ||
        ![[NSData data] writeToURL:tombstone options:NSDataWritingAtomic error:error]) return NO;
    BOOL ok=![NSFileManager.defaultManager fileExistsAtPath:URL.path] || [NSFileManager.defaultManager removeItemAtURL:URL error:error];
    NSURL* assets=[_directory URLByAppendingPathComponent:[identifier stringByAppendingString:@"-assets"]];
    if ([NSFileManager.defaultManager fileExistsAtPath:assets.path]) ok=[NSFileManager.defaultManager removeItemAtURL:assets error:error] && ok;
    return ok;
}
- (BOOL)deleteChatWithID:(NSString*)identifier error:(NSError**)error {
    int fd=[self lockStore:error]; if (fd<0) return NO;
    BOOL ok=[self deleteUnlocked:identifier error:error]; flock(fd,LOCK_UN); close(fd); return ok;
}
- (BOOL)deleteAll:(NSError**)error {
    int fd=[self lockStore:error]; if (fd<0) return NO;
    NSArray* URLs=[NSFileManager.defaultManager contentsOfDirectoryAtURL:_directory includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:error];
    NSMutableSet* identifiers=[NSMutableSet set];
    for (NSURL* URL in URLs) {
        NSString* name=URL.lastPathComponent;
        NSString* identifier=[name hasSuffix:@"-assets"] ? [name substringToIndex:name.length-7] : name.stringByDeletingPathExtension;
        if (ValidID(identifier) && ([name hasSuffix:@"-assets"] || [name.pathExtension isEqual:@"json"])) [identifiers addObject:identifier];
    }
    BOOL ok=URLs!=nil;
    for (NSString* identifier in identifiers) if (![self deleteUnlocked:identifier error:error]) ok=NO;
    flock(fd,LOCK_UN); close(fd); return ok;
}
@end
