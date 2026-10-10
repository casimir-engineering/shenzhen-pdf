#pragma once
#import <Foundation/Foundation.h>
@class SPDFMacAITransport, SPDFMacAIChatStore;
@protocol SPDFMacAIChatTools <NSObject>
- (void)performTool:(NSString*)name arguments:(NSDictionary*)arguments completion:(void (^)(NSDictionary*))completion;
@property(nonatomic, readonly) BOOL canUndo;
- (void)cancel;
- (BOOL)undoLastAction:(NSError**)error;
@end
typedef NS_ENUM(NSInteger, SPDFMacAIChatActivityState) {
    SPDFMacAIChatActivityIdle, SPDFMacAIChatActivityThinking, SPDFMacAIChatActivityWorking,
    SPDFMacAIChatActivityCompleted, SPDFMacAIChatActivityError, SPDFMacAIChatActivityStopped
};
@interface SPDFMacAIChatSession : NSObject
@property(nonatomic, copy) void (^changed)(void);
@property(nonatomic, readonly) NSDictionary* chat;
@property(nonatomic, readonly) BOOL running;
@property(nonatomic, readonly) BOOL canUndo;
@property(nonatomic, readonly) NSString* status;
@property(nonatomic, readonly) SPDFMacAIChatActivityState activityState;
@property(nonatomic, readonly) NSString* activityDetail;
- (instancetype)initWithTransport:(SPDFMacAITransport*)transport tools:(id<SPDFMacAIChatTools>)tools
    definitions:(NSArray*)definitions store:(SPDFMacAIChatStore*)store;
- (void)newChat;
- (void)loadChat:(NSDictionary*)chat;
- (void)send:(NSString*)text model:(NSString*)model apiKey:(NSString*)key;
- (void)cancel;
- (BOOL)undo:(NSError**)error;
@end
