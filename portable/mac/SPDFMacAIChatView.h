#pragma once
#import <Cocoa/Cocoa.h>
@class SPDFMacAIChatSession;
@interface SPDFMacAIChatView : NSView
@property(nonatomic, copy) BOOL (^sendText)(NSString*);
@property(nonatomic, copy) void (^action)(NSString*);
@property(nonatomic, copy) void (^openLink)(NSURL*);
@property(nonatomic, readonly) NSTextView* composer;
- (void)showSubmissionError:(NSString*)message;
- (void)showSubmissionError:(NSString*)message recoveryAction:(NSString*)action;
- (void)refreshActivityFromSession:(SPDFMacAIChatSession*)session;
- (void)displaySession:(SPDFMacAIChatSession*)session;
- (void)displayChats:(NSArray<NSDictionary*>*)chats;
- (void)setPinMode:(NSInteger)mode;
@end
