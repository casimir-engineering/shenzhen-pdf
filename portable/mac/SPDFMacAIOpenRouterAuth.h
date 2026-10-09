#pragma once
#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSString* SPDFMacAIPKCEChallenge(NSString* verifier);
@class SPDFMacAICredentials;
// A fresh, single-use session. Caller opens returned URL in the browser. Completion is main queue.
@interface SPDFMacAIOpenRouterAuth : NSObject
- (instancetype)initWithConfiguration:(NSURLSessionConfiguration*)configuration credentials:(SPDFMacAICredentials*)credentials;
- (NSURL*)startWithCompletion:(void (^)(BOOL connected, NSError* error))completion error:(NSError**)error;
- (void)cancel;
@end
