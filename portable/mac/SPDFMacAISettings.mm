#import "SPDFMacAISettings.h"
#import "SPDFMacAITransport.h"
#import <sys/stat.h>
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>
@implementation SPDFMacAISettings { NSURL* _URL; NSDictionary* _baseline; }
+ (NSURL*)defaultURL {
    NSString* root=NSProcessInfo.processInfo.environment[@"SPDF_STATE_DIR"];
    if(!root.length)root=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/ShenzhenPDF"];
    return [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"ai-settings.yaml"]];
}
- (instancetype)initWithURL:(NSURL*)URL {
    if((self=[super init])) { _URL=URL; _model=SPDFMacAIDefaultModel; _enabled=YES; _automaticAnalysis=YES; _baseline=[self values]; } return self;
}
- (BOOL)allowsRequestsForSetupRevision:(NSInteger)revision {
    return self.enabled && self.connectionConfigured && self.onboardingRevision>=revision;
}
- (NSDictionary*)values {
    return @{@"model":self.model ?: SPDFMacAIDefaultModel,@"enabled":@(self.enabled),
        @"connection_configured":@(self.connectionConfigured),@"automatic_analysis":@(self.automaticAnalysis),@"show_settings_on_launch":@(self.showSettingsOnLaunch),
        @"onboarding_revision":@(self.onboardingRevision),@"onboarding_step":@(self.onboardingStep)};
}
- (BOOL)load:(NSError**)error {
    if(error)*error=nil;
    if(![NSFileManager.defaultManager fileExistsAtPath:_URL.path])return YES;
    NSDictionary* attrs=[NSFileManager.defaultManager attributesOfItemAtPath:_URL.path error:error];
    if(!attrs || [attrs[NSFileSize] unsignedLongLongValue]>8192) {
        if(error && !*error)*error=SPDFMacAIError(30,@"AI settings are too large to read."); return NO;
    }
    NSString* YAML=[NSString stringWithContentsOfURL:_URL encoding:NSUTF8StringEncoding error:error];
    if(!YAML)return NO;
    // A flat, deliberately restricted YAML scalar schema: secrets and arbitrary objects cannot enter this file.
    for(NSString* line in [YAML componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSRange colon=[line rangeOfString:@":"]; if(colon.location==NSNotFound)continue;
        NSString* key=[[line substringToIndex:colon.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString* value=[[line substringFromIndex:colon.location+1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if([key isEqual:@"model"] && value.length>0 && value.length<=160 &&
            [value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_/.:~"].invertedSet].location==NSNotFound)
            self.model=value;
        else if([key isEqual:@"connection_configured"])self.connectionConfigured=[value isEqual:@"true"];
        else if([key isEqual:@"enabled"])self.enabled=[value isEqual:@"true"];
        else if([key isEqual:@"automatic_analysis"])self.automaticAnalysis=[value isEqual:@"true"];
        else if([key isEqual:@"show_settings_on_launch"])self.showSettingsOnLaunch=[value isEqual:@"true"];
        else if([key isEqual:@"onboarding_step"])self.onboardingStep=MIN(3,MAX(0,value.integerValue));
        else if([key isEqual:@"onboarding_revision"])self.onboardingRevision=MAX(0,value.integerValue);
    }
    _baseline=[self values]; return YES;
}
- (BOOL)save:(NSError**)error {
    if(error)*error=nil;
    if(!self.model.length || self.model.length>160 || [self.model rangeOfCharacterFromSet:
        [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_/.:~"].invertedSet].location!=NSNotFound) {
        if(error)*error=SPDFMacAIError(31,@"Enter a valid OpenRouter model identifier."); return NO;
    }
    if(![NSFileManager.defaultManager createDirectoryAtURL:_URL.URLByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error])return NO;
    NSString* lockPath=[_URL.path stringByAppendingString:@".lock"];
    int descriptor=open(lockPath.fileSystemRepresentation,O_CREAT|O_RDWR|O_NOFOLLOW,0600);
    if(descriptor<0 || flock(descriptor,LOCK_EX)!=0) {
        if(descriptor>=0)close(descriptor);
        if(error)*error=SPDFMacAIError(32,@"AI settings could not be locked for saving."); return NO;
    }
    SPDFMacAISettings* current=[[SPDFMacAISettings alloc] initWithURL:_URL];
    if(![current load:error]) { flock(descriptor,LOCK_UN);close(descriptor);return NO; }
    NSMutableDictionary* merged=[[current values] mutableCopy]; NSDictionary* requested=[self values];
    // Independent windows update only their changed fields, preserving other windows' settings.
    for(NSString* key in requested)if(![requested[key] isEqual:_baseline[key]])merged[key]=requested[key];
    NSString* YAML=[NSString stringWithFormat:@"schema_version: 1\nmodel: %@\nenabled: %@\nconnection_configured: %@\nautomatic_analysis: %@\nshow_settings_on_launch: %@\nonboarding_revision: %ld\nonboarding_step: %ld\n",
        merged[@"model"],[merged[@"enabled"] boolValue] ? @"true" : @"false",
        [merged[@"connection_configured"] boolValue] ? @"true" : @"false",
        [merged[@"automatic_analysis"] boolValue] ? @"true" : @"false",
        [merged[@"show_settings_on_launch"] boolValue] ? @"true" : @"false",[merged[@"onboarding_revision"] longValue],[merged[@"onboarding_step"] longValue]];
    BOOL saved=[[YAML dataUsingEncoding:NSUTF8StringEncoding] writeToURL:_URL options:NSDataWritingAtomic error:error];
    if(saved) {
        chmod(_URL.fileSystemRepresentation,0600); self.model=merged[@"model"]; self.enabled=[merged[@"enabled"] boolValue];
        self.connectionConfigured=[merged[@"connection_configured"] boolValue];
        self.automaticAnalysis=[merged[@"automatic_analysis"] boolValue];
        self.showSettingsOnLaunch=[merged[@"show_settings_on_launch"] boolValue];
        self.onboardingRevision=[merged[@"onboarding_revision"] integerValue]; self.onboardingStep=[merged[@"onboarding_step"] integerValue]; _baseline=[self values];
    }
    flock(descriptor,LOCK_UN);close(descriptor);return saved;
}
@end
