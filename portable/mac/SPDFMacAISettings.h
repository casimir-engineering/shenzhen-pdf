#pragma once
#import <Foundation/Foundation.h>
// Loading is explicit and cheap. Construction performs no I/O; setup reads happen after first paint.
@interface SPDFMacAISettings : NSObject
@property(nonatomic, copy) NSString* model;
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL connectionConfigured;
@property(nonatomic) BOOL automaticAnalysis;
@property(nonatomic) BOOL showSettingsOnLaunch;
@property(nonatomic) NSInteger onboardingRevision;
@property(nonatomic) NSInteger onboardingStep;
+ (NSURL*)defaultURL;
- (instancetype)initWithURL:(NSURL*)URL;
- (BOOL)allowsRequestsForSetupRevision:(NSInteger)revision;
- (BOOL)load:(NSError**)error;
- (BOOL)save:(NSError**)error;
@end
