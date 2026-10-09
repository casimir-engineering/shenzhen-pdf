#pragma once
#import <Foundation/Foundation.h>
// Loading is explicit and cheap; this object must not be created during launch.
@interface SPDFMacAISettings : NSObject
@property(nonatomic, copy) NSString* model;
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL automaticAnalysis;
@property(nonatomic) BOOL showSettingsOnLaunch;
@property(nonatomic) NSInteger onboardingRevision;
+ (NSURL*)defaultURL;
- (instancetype)initWithURL:(NSURL*)URL;
- (BOOL)load:(NSError**)error;
- (BOOL)save:(NSError**)error;
@end
