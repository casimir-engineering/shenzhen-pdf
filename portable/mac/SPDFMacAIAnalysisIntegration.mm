#import "SPDFMacAIIntegration.h"
#import "SPDFMacAISettings.h"
#import "SPDFMacAIAnalysisService.h"
#import "SPDFMacAIDocumentContext.h"
#import "SPDFMacAITransport.h"
#import "SPDFMacCollectionStore.h"
#import "SPDFMacAIToolsReader.h"
#import "SPDFMacMarkdownDelegatePrivate.h"
#import "SPDFMacMarkdownSidebarModel.h"
@interface ShenzhenMacDelegate (AIAnalysisHost)
- (void)aiInstallAnalysis:(NSDictionary*)analysis error:(NSError*)error candidate:(NSDictionary*)candidate
    settings:(SPDFMacAISettings*)settings;
- (BOOL)sidebarSearchText:(NSString*)text matchesFilter:(NSString*)filter;
@end
#import <objc/runtime.h>
static char analysisServiceKey, analysisSettingsKey, analysisResultsKey, analysisConfigurationKey, analysisRevisionObserverKey;
@interface SPDFAnalysisRevisionObserver : NSObject
@property(atomic) NSUInteger generation;
@property(atomic) BOOL enabled;
@property(nonatomic) id token;
@property(nonatomic,copy) void (^changed)(NSString* root);
@property(nonatomic) NSMutableSet* roots;
- (void)distributedChange:(NSNotification*)note;
@end
@implementation SPDFAnalysisRevisionObserver
- (void)dealloc {
    if(self.token)[NSNotificationCenter.defaultCenter removeObserver:self.token];
    [NSDistributedNotificationCenter.defaultCenter removeObserver:self];
}
- (void)distributedChange:(NSNotification*)note {
    if([note.userInfo[@"processID"] intValue]==NSProcessInfo.processInfo.processIdentifier)return;
    if(self.changed && [note.object isKindOfClass:NSString.class])self.changed(note.object);
}
@end
static NSString* CollectionCopyRoot(NSDictionary* candidate) {
    for(NSString* key in @[@"path",@"readPath"]) {
        NSString* path=[candidate[key] stringByStandardizingPath];NSArray* parts=path.pathComponents;
        if(parts.count<5)continue;
        NSString* folder=parts[parts.count-4];
        if(![folder isEqual:@"editable"] && ![folder isEqual:@"previews"])continue;
        for(NSUInteger i=0;i<4;i++)path=path.stringByDeletingLastPathComponent;
        return path;
    }
    return nil;
}
static BOOL CollectionCopyCandidate(NSDictionary* candidate) { return CollectionCopyRoot(candidate)!=nil; }
static BOOL CurrentCollectionGeneration(ShenzhenMacDelegate* owner,NSDictionary* candidate) {
    if(!CollectionCopyCandidate(candidate))return YES;
    SPDFAnalysisRevisionObserver* observer=objc_getAssociatedObject(owner,&analysisRevisionObserverKey);
    return [candidate[@"collectionGeneration"] unsignedIntegerValue]==observer.generation;
}
static NSDictionary* Candidate(ShenzhenMacDelegate* owner,NSString* path) {
    return [owner aiDocumentCandidateForPath:path];
}
static BOOL SameCandidate(NSDictionary* before,NSDictionary* after) {
    return before && after && [before[@"revision"] isEqual:after[@"revision"]] &&
        [before[@"readPath"] isEqual:after[@"readPath"]] &&
        [before[@"landscape"] isEqual:after[@"landscape"]] &&
        before[@"renderedDocument"]==after[@"renderedDocument"] && before[@"paginationPlan"]==after[@"paginationPlan"];
}
@implementation ShenzhenMacDelegate (SPDFMacAIAnalysisIntegration)
- (SPDFAnalysisRevisionObserver*)aiObserveCollectionAnalysisRevisions:(NSDictionary*)candidate {
    SPDFAnalysisRevisionObserver* observer=objc_getAssociatedObject(self,&analysisRevisionObserverKey);
    NSString* root=CollectionCopyRoot(candidate);
    if(observer) { @synchronized(observer) { if(root)[observer.roots addObject:root]; } return observer; }
    observer=[SPDFAnalysisRevisionObserver new];observer.roots=[NSMutableSet set];observer.enabled=YES;
    if(root)[observer.roots addObject:root];
    __weak SPDFAnalysisRevisionObserver* weakObserver=observer;
    __weak ShenzhenMacDelegate* weakSelf=self;
    observer.changed=^(NSString* changedRoot){
            SPDFAnalysisRevisionObserver* state=weakObserver;if(!state || !state.enabled)return;
            @synchronized(state) { if(![state.roots containsObject:changedRoot.stringByStandardizingPath])return;state.generation++; }
            dispatch_async(dispatch_get_main_queue(),^{
                ShenzhenMacDelegate* owner=weakSelf;if(!owner)return;
                SPDFMacAISettings* settings=objc_getAssociatedObject(owner,&analysisSettingsKey);
                if(!settings.enabled || !settings.automaticAnalysis)return;
                NSMutableDictionary* results=objc_getAssociatedObject(owner,&analysisResultsKey);
                for(NSString* path in results.allKeys)
                    if(CollectionCopyCandidate(results[path][@"candidate"]))[results removeObjectForKey:path];
                NSDictionary* current=@{@"path":owner->_path ?: @""};
                if(CollectionCopyCandidate(current)) {
                    [owner rebuildSidebar];[owner aiDocumentDidOpen:owner->_path];
                }
            });
        };
    observer.token=[NSNotificationCenter.defaultCenter addObserverForName:SPDFCollectionStoreDidChangeNotification
        object:nil queue:nil usingBlock:^(NSNotification* note) {
            if([note.object isKindOfClass:SPDFMacCollectionStore.class] && weakObserver.changed)
                weakObserver.changed([(SPDFMacCollectionStore*)note.object rootURL].path);
        }];
    [NSDistributedNotificationCenter.defaultCenter addObserver:observer selector:@selector(distributedChange:)
        name:@"SPDFCollectionStoreDidChangeAcrossProcesses" object:nil suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    objc_setAssociatedObject(self,&analysisRevisionObserverKey,observer,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return observer;
}
- (void)configureAIAnalysis:(id)value {
    SPDFMacAISettings* settings=value;
    NSArray* previous=objc_getAssociatedObject(self,&analysisConfigurationKey);
    NSArray* configuration=@[@(settings.enabled),@(settings.automaticAnalysis),settings.model ?: @""];
    if ([previous isEqual:configuration]) return;
    objc_setAssociatedObject(self,&analysisConfigurationKey,configuration,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self,&analysisSettingsKey,settings,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [objc_getAssociatedObject(self,&analysisServiceKey) cancelAll];
    objc_setAssociatedObject(self,&analysisResultsKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL enabled=settings.enabled && settings.automaticAnalysis;
    [(SPDFAnalysisRevisionObserver*)objc_getAssociatedObject(self,&analysisRevisionObserverKey) setEnabled:enabled];
    if (enabled || (previous.count && [previous[0] boolValue] && [previous[1] boolValue])) {
        for (SPDFDocumentTab* tab in _tabs) if (tab.cachedMarkdownSession)
            [self configureAIAnalysisForMarkdownSession:tab.cachedMarkdownSession path:tab.path];
        if ([self activeMarkdownSession]) [self configureAIAnalysisForMarkdownSession:[self activeMarkdownSession] path:_path];
    }
    if (enabled && _path.length) [self aiDocumentDidOpen:_path];
}
- (void)configureAIAnalysisForMarkdownSession:(id)value path:(NSString*)path {
    SPDFMacMarkdownSession* session=value;
    SPDFMacAISettings* settings=objc_getAssociatedObject(self,&analysisSettingsKey);
    session.renderInstalledHandler=nil;
    if (!settings.enabled || !settings.automaticAnalysis) return;
    __weak ShenzhenMacDelegate* weakSelf=self; __weak SPDFMacMarkdownSession* weakSession=session;
    session.renderInstalledHandler=^{
        ShenzhenMacDelegate* owner=weakSelf;
        if (owner && [owner activeMarkdownSession]==weakSession) [owner aiDocumentDidOpen:path];
    };
}
- (void)aiDocumentDidOpen:(NSString*)path {
    SPDFMacAISettings* settings=objc_getAssociatedObject(self,&analysisSettingsKey);
    // This branch precedes even queue/cache creation. Opening a document without
    // opted-in background analysis has no AI disk, extraction or network work.
    if (!settings.enabled || !settings.automaticAnalysis || !path.length) return;
    NSMutableDictionary* candidate=[Candidate(self,path) mutableCopy];
    if (!candidate) return;
    if(CollectionCopyCandidate(candidate))candidate[@"collectionGeneration"]=@([self aiObserveCollectionAnalysisRevisions:candidate].generation);
    dispatch_async(dispatch_get_main_queue(),^{
        if (objc_getAssociatedObject(self,&analysisSettingsKey)!=settings || !settings.enabled || !settings.automaticAnalysis) return;
        SPDFMacAIAnalysisService* service=objc_getAssociatedObject(self,&analysisServiceKey);
        if (!service) {
            NSURL* root=[SPDFMacAISettings.defaultURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"AI/Analysis"];
            service=[[SPDFMacAIAnalysisService alloc] initWithCache:[[SPDFMacAIAnalysisCache alloc] initWithRootURL:root]
                transport:[[SPDFMacAITransport alloc] initWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration]];
            objc_setAssociatedObject(self,&analysisServiceKey,service,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        __weak ShenzhenMacDelegate* weakSelf=self;
        [service analyzeCandidate:candidate settings:settings completion:^(NSDictionary* analysis,NSError* error) {
            [weakSelf aiInstallAnalysis:analysis error:error candidate:candidate settings:settings];
        }];
    });
}
- (void)aiInstallAnalysis:(NSDictionary*)analysis error:(NSError*)error candidate:(NSDictionary*)candidate
    settings:(SPDFMacAISettings*)settings {
            ShenzhenMacDelegate* owner=self;
            NSString* path=candidate[@"path"];
            if(CollectionCopyCandidate(candidate))[self aiObserveCollectionAnalysisRevisions:candidate];
            if (!owner || !CurrentCollectionGeneration(owner,candidate) || objc_getAssociatedObject(owner,&analysisSettingsKey)!=settings ||
                !settings.enabled || !settings.automaticAnalysis || ![settings.model isEqual:analysis[@"model"] ?: settings.model] ||
                !SameCandidate(candidate,Candidate(owner,path))) return;
            NSMutableDictionary* results=objc_getAssociatedObject(owner,&analysisResultsKey);
            if (!results) { results=[NSMutableDictionary dictionary]; objc_setAssociatedObject(owner,&analysisResultsKey,results,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            if (analysis) {
                results[path]=@{@"analysis":analysis,@"candidate":candidate};
                [owner aiRememberAnalysis:analysis forPath:path];
            } else if (error) results[path]=@{@"analysis":@{@"error":error.localizedDescription ?: @"Analysis unavailable"},
                @"candidate":candidate};
            if ([owner->_path isEqual:path]) [owner rebuildSidebar];
}
- (NSDictionary*)aiAnalysisForPath:(NSString*)path {
    NSDictionary* entry=[objc_getAssociatedObject(self,&analysisResultsKey) objectForKey:path ?: @""];
    if (!entry) return nil;
    SPDFMacAISettings* settings=objc_getAssociatedObject(self,&analysisSettingsKey);
    if (!settings.enabled || !settings.automaticAnalysis || !CurrentCollectionGeneration(self,entry[@"candidate"]) ||
        !SameCandidate(entry[@"candidate"],Candidate(self,path))) return nil;
    return entry[@"analysis"];
}
- (NSArray<NSDictionary*>*)aiGeneratedChapterRows {
    // Authored chapters always win. Generated metadata is separate from the file.
    if ([self isMarkdownActive] ? [self activeMarkdownSession].sidebarModel.chapterItems.count>0 : _outline.count>0) return @[];
    NSDictionary* analysis=[self aiAnalysisForPath:_path];
    NSMutableArray* rows=[NSMutableArray array];
    for (NSDictionary* chapter in analysis[@"chapters"]) {
        NSInteger page=[chapter[@"page"] integerValue]-1;
        if (page<0) continue;
        [rows addObject:@{@"kind":@"chapter",@"title":[@"✧ " stringByAppendingString:chapter[@"title"] ?: @"Chapter"],
            @"page":@(page),@"level":chapter[@"level"] ?: @0,@"generated":@YES}];
    }
    return rows;
}
- (void)appendAIGeneratedChaptersMatchingFilter:(NSString*)filter {
    for (NSDictionary* row in [self aiGeneratedChapterRows])
        if ([self sidebarSearchText:row[@"title"] matchesFilter:filter ?: @""]) [_sidebarItems addObject:row];
}
@end
