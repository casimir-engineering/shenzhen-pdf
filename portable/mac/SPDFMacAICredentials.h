#pragma once
#import <Foundation/Foundation.h>
#import <Security/Security.h>
@protocol SPDFMacAIKeychainAccess <NSObject>
- (OSStatus)copyMatching:(NSDictionary*)query result:(NSData**)result;
- (OSStatus)add:(NSDictionary*)attributes;
- (OSStatus)update:(NSDictionary*)query attributes:(NSDictionary*)attributes;
- (OSStatus)remove:(NSDictionary*)query;
@end
@interface SPDFMacAICredentials : NSObject
+ (BOOL)storeAPIKey:(NSString*)key error:(NSError**)error;
+ (NSString*)APIKeyWithError:(NSError**)error;
+ (BOOL)removeAPIKeyWithError:(NSError**)error;
- (instancetype)initWithKeychain:(id<SPDFMacAIKeychainAccess>)keychain;
- (BOOL)storeAPIKey:(NSString*)key error:(NSError**)error;
- (NSString*)APIKeyWithError:(NSError**)error;
- (BOOL)removeAPIKeyWithError:(NSError**)error;
@end
