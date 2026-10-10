#import "SPDFMacAIIntegration.h"
#import "SPDFMacUnifiedSettings.h"
#import "SPDFMacAISettings.h"
#import "SPDFMacAICredentials.h"
#import "SPDFMacAIOpenRouterAuth.h"
#import "SPDFMacAIModelCatalog.h"
#import "SPDFMacCollectionStore.h"
#import "SPDFMacCollectionIntegration.h"
#import <objc/runtime.h>
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>
@interface ShenzhenMacDelegate (AISettingsHost)
- (void)makeDefaultPDFReader:(id)sender;
- (BOOL)hasActiveDocument;
- (void)openAccessibilitySettings;
- (void)openFullDiskAccessSettings;

@end
static char settingsControllerKey, authKey, authGenerationKey, catalogKey, settingsObserverKey;
static NSUInteger InvalidateAuth(ShenzhenMacDelegate* reader) {
    NSUInteger generation=[objc_getAssociatedObject(reader,&authGenerationKey) unsignedIntegerValue]+1;
    objc_setAssociatedObject(reader,&authGenerationKey,@(generation),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [objc_getAssociatedObject(reader,&authKey) cancel];
    objc_setAssociatedObject(reader,&authKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return generation;
}
static SPDFMacAISettings* ReadSettings(void) {
    SPDFMacAISettings* settings=[[SPDFMacAISettings alloc] initWithURL:SPDFMacAISettings.defaultURL];
    [settings load:nil]; return settings;
}
@implementation ShenzhenMacDelegate (SPDFMacAISettingsIntegration)
- (NSDictionary*)unifiedSettingsState {
    SPDFMacAISettings* ai=ReadSettings(); NSDictionary* collection=SPDFMacCollectionStore.defaultStore.settings;
    BOOL connected=[SPDFMacAICredentials APIKeyWithError:nil].length>0;
    return @{@"connected":@(connected),@"model":ai.model,@"aiEnabled":@(ai.enabled),
        @"autoAnalyze":@(ai.automaticAnalysis),@"showSettingsOnLaunch":@(ai.showSettingsOnLaunch),
        @"collectionEnabled":@(![collection[@"choice"] isEqual:@"disabled"]),
        @"collectionChoiceMade":@([@[@"enabled",@"disabled"] containsObject:collection[@"choice"] ?: @""]),
        @"showShortcutsOnLaunch":@(_showShortcutHelpOnLaunch),@"keepImageColors":@(_darkThemePreservesImagesDefault)};
}
- (void)showUnifiedSettings:(id)sender {
    (void)sender;
    SPDFMacUnifiedSettingsController* controller=objc_getAssociatedObject(self,&settingsControllerKey);
    if (!controller) {
        controller=[[SPDFMacUnifiedSettingsController alloc] initWithState:[self unifiedSettingsState]];
        objc_setAssociatedObject(self,&settingsControllerKey,controller,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak __typeof__(self) weakSelf=self;
        controller.settingsChanged=^(NSDictionary* changes) { [weakSelf applyUnifiedSettings:changes]; };
        controller.actionHandler=^(NSString* action) { [weakSelf unifiedSettingsAction:action]; };
        controller.credentialHandler=^(NSString* secret) {
            NSError* error=nil;
            ShenzhenMacDelegate* reader=weakSelf; if (!reader) return;
            InvalidateAuth(reader);
            BOOL saved=[SPDFMacAICredentials storeAPIKey:secret error:&error];
            SPDFMacUnifiedSettingsController* c=objc_getAssociatedObject(reader,&settingsControllerKey);
            [c updateState:[reader unifiedSettingsState]];
            [c updateState:@{@"connecting":@NO,@"connectionStatus":saved ?
                @"API key saved securely. Enable document chat when you are ready." :
                (error.localizedDescription ?: @"The API key could not be saved. Try again.")}];
            if (saved) [reader validateAIModel:ReadSettings().model];
            else if (error) [reader->_window presentError:error];
        };
    } else [controller updateState:[self unifiedSettingsState]];
    [controller showForWindow:_window];
}
- (void)showAIConnectionSettingsWithReason:(NSString*)reason {
    [self showUnifiedSettings:nil];
    SPDFMacUnifiedSettingsController* controller=objc_getAssociatedObject(self,&settingsControllerKey);
    [controller updateState:@{@"connectionStatus":reason ?: @""}]; [controller selectSection:@"ai"];
}
- (void)validateAIModel:(NSString*)identifier {
    [objc_getAssociatedObject(self,&catalogKey) cancel];
    SPDFMacUnifiedSettingsController* controller=objc_getAssociatedObject(self,&settingsControllerKey);
    __weak ShenzhenMacDelegate* weakSelf=self;
    NSURLSessionDataTask* task=SPDFMacAIValidateModel(identifier,^(NSDictionary* model,NSError* error) {
        ShenzhenMacDelegate* reader=weakSelf; if (!reader || error.code==NSURLErrorCancelled) return;
        if (![ReadSettings().model isEqual:identifier]) return;
        NSString* status=error ? error.localizedDescription : [NSString stringWithFormat:@"%@ · document tools supported",model[@"name"] ?: identifier];
        [controller updateState:@{@"modelStatus":status}];
    });
    objc_setAssociatedObject(self,&catalogKey,task,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)applyUnifiedSettings:(NSDictionary*)changes {
    SPDFMacAISettings* ai=ReadSettings();
    if (changes[@"model"]) ai.model=changes[@"model"];
    if (changes[@"aiEnabled"]) ai.enabled=[changes[@"aiEnabled"] boolValue];
    if (changes[@"autoAnalyze"]) ai.automaticAnalysis=[changes[@"autoAnalyze"] boolValue];
    if (changes[@"showSettingsOnLaunch"]) ai.showSettingsOnLaunch=[changes[@"showSettingsOnLaunch"] boolValue];
    NSError* error=nil; [ai save:&error];
    if (!error && changes[@"collectionEnabled"]) {
        [SPDFMacCollectionStore.defaultStore updateSettings:@{@"choice":[changes[@"collectionEnabled"] boolValue] ? @"enabled" : @"disabled"} error:&error];
        if (!error && [changes[@"collectionEnabled"] boolValue])
            for (SPDFDocumentTab* tab in _tabs) [self collectionDidOpenPath:tab.path];
    }
    if (changes[@"keepImageColors"]) { _darkThemePreservesImagesDefault=[changes[@"keepImageColors"] boolValue]; [self savePersistentState]; }
    if (changes[@"showShortcutsOnLaunch"]) { _showShortcutHelpOnLaunch=[changes[@"showShortcutsOnLaunch"] boolValue]; [self savePersistentState]; }
    if (!error && (changes[@"model"] || [changes[@"aiEnabled"] boolValue])) [self validateAIModel:ai.model];
    [self configureAIAnalysis:ai];
    if (!ai.enabled) [self cancelAIChat];
    if (!error) [NSDistributedNotificationCenter.defaultCenter postNotificationName:@"ShenzhenPDFAISettingsChanged" object:nil userInfo:nil deliverImmediately:YES];
    if (error) [_window presentError:error];
}
- (void)unifiedSettingsAction:(NSString*)action {
    SPDFMacUnifiedSettingsController* controller=objc_getAssociatedObject(self,&settingsControllerKey);
    if ([action isEqual:@"dismissed"]) {
        InvalidateAuth(self); [controller updateState:@{@"connecting":@NO,@"connectionStatus":@"Sign in in your browser, or use an API key."}]; return;
    }
    if ([action isEqual:@"done"]) {
        InvalidateAuth(self); [controller updateState:@{@"connecting":@NO,@"connectionStatus":@"Sign in in your browser, or use an API key."}];
        // Start reading accepts the explicitly displayed Collection choice. Closing
        // the window with its close control leaves an undecided choice undecided.
        NSString* choice=SPDFMacCollectionStore.defaultStore.settings[@"choice"];
        if (![choice isEqual:@"enabled"] && ![choice isEqual:@"disabled"])
            [self applyUnifiedSettings:@{@"collectionEnabled":@YES}];
        return;
    }
    if ([action isEqual:@"showAI"]) { [controller selectSection:@"ai"]; return; }
    if ([action isEqual:@"connect"]) {
        [controller updateState:@{@"connecting":@YES,@"connectionStatus":@"Finish connecting in your browser. Close Settings to cancel."}];
        NSUInteger generation=InvalidateAuth(self);
        SPDFMacAIOpenRouterAuth* auth=[SPDFMacAIOpenRouterAuth new];
        objc_setAssociatedObject(self,&authKey,auth,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak __typeof__(self) weakSelf=self; NSError* error=nil;
        NSURL* URL=[auth startWithCompletion:^(BOOL connected,NSError* problem) {
            __typeof__(self) reader=weakSelf; if (!reader ||
                [objc_getAssociatedObject(reader,&authGenerationKey) unsignedIntegerValue]!=generation) return;
            [controller updateState:[reader unifiedSettingsState]];
            [controller updateState:@{@"connecting":@NO,@"connectionStatus":connected ? @"Connected. Enable document chat when you are ready." :
                problem.code==NSURLErrorCancelled ? @"Connection cancelled. Connect again when you are ready." : @"Connection failed. Try again."}];
            if (problem && problem.code!=NSURLErrorCancelled) [controller.window presentError:problem];
            if (connected) [reader validateAIModel:ReadSettings().model];
        } error:&error];
        if (URL) [NSWorkspace.sharedWorkspace openURL:URL]; else { [controller updateState:@{@"connecting":@NO,@"connectionStatus":error.localizedDescription ?: @"Could not begin browser sign-in. Try again."}]; if (error) [controller.window presentError:error]; }
    } else if ([action isEqual:@"disconnect"]) {
        InvalidateAuth(self); NSError* error=nil;
        [SPDFMacAICredentials removeAPIKeyWithError:&error]; [self applyUnifiedSettings:@{@"aiEnabled":@NO}];
        [controller updateState:[self unifiedSettingsState]];
        [controller updateState:@{@"connecting":@NO,@"connectionStatus":error ? error.localizedDescription : @"Disconnected. Connect OpenRouter when you want to use AI again."}];
        if (error) [controller.window presentError:error];
    } else if ([action isEqual:@"defaultReader"]) [self makeDefaultPDFReader:nil];
    else if ([action isEqual:@"accessibility"]) [self openAccessibilitySettings];
    else if ([action isEqual:@"fullDiskAccess"]) [self openFullDiskAccessSettings];
    else if ([action isEqual:@"shortcuts"]) [self showShortcutHelp:nil];
    else if ([action isEqual:@"collection"]) [self showCollectionManager:nil];
    else if ([action isEqual:@"collectionSettings"]) [self showCollectionSettings:nil];
}
- (void)observeAISettingsChanges {
    if (objc_getAssociatedObject(self,&settingsObserverKey)) return;
    __weak ShenzhenMacDelegate* weakSelf=self;
    id observer=[NSDistributedNotificationCenter.defaultCenter addObserverForName:@"ShenzhenPDFAISettingsChanged"
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification* note) {
            (void)note; ShenzhenMacDelegate* reader=weakSelf; if (!reader) return;
            SPDFMacAISettings* settings=ReadSettings(); [reader configureAIAnalysis:settings];
            if (!settings.enabled) [reader cancelAIChat];
        }];
    objc_setAssociatedObject(self,&settingsObserverKey,observer,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)showUnifiedSettingsAfterFirstPaint {
    [self observeAISettingsChanges];
    if (self.restoreWindowID.length || self.detachedTabLaunch) { [self configureAIAnalysis:ReadSettings()]; return; }
    // Executed only in the existing deferred first-paint tail. No AI network,
    // credential access, document indexing, or UI construction precedes this gate.
    NSURL* URL=SPDFMacAISettings.defaultURL;
    [NSFileManager.defaultManager createDirectoryAtURL:URL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    int fd=open([[URL.path stringByAppendingString:@".onboarding.lock"] fileSystemRepresentation],O_CREAT|O_RDWR,0600);
    if (fd<0 || flock(fd,LOCK_EX|LOCK_NB)!=0) { if (fd>=0) close(fd); return; }
    SPDFMacAISettings* settings=ReadSettings();
    [self configureAIAnalysis:settings];
    BOOL show=settings.showSettingsOnLaunch || settings.onboardingRevision<SPDFUnifiedSettingsExperienceVersion;
    settings.onboardingRevision=SPDFUnifiedSettingsExperienceVersion;
    BOOL saved=!show || [settings save:nil]; flock(fd,LOCK_UN); close(fd);
    if (show && saved) [self showUnifiedSettings:nil];
    if ([self hasActiveDocument]) [self aiDocumentDidOpen:_path];
}
@end
