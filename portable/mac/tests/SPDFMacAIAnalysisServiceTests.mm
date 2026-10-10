#import "SPDFMacAIAnalysisService.h"
#import "SPDFMacAIDocumentContext.h"
#import "SPDFMacAISettings.h"
#import "SPDFMacAITransport.h"
#import "SPDFMacAICredentials.h"
#import "SPDFMacSearchFileCache.h"
#import "SPDFMacAIIntegration.h"
#import "SPDFMacAIToolsReader.h"
#import "markdown/SPDFMarkdownDocument.h"
#include <fcntl.h>
#include <unistd.h>
static int failures=0;
static void Check(BOOL value,const char* name) { if(!value){fprintf(stderr,"FAIL %s\n",name);failures++;} }
static BOOL Wait(BOOL (^predicate)(void)) {
    NSDate* limit=[NSDate dateWithTimeIntervalSinceNow:3];
    while(!predicate() && limit.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
    return predicate();
}
@interface AnalysisTransport : SPDFMacAITransport
@property(atomic) NSInteger calls;
@property(nonatomic) NSString* reply;
@property(nonatomic) NSDictionary* payload;
@property(nonatomic,copy) void (^held)(NSDictionary*,NSError*);
@property(nonatomic) BOOL hold;
@property(nonatomic) NSString* markerPath;
@end
@implementation AnalysisTransport
- (SPDFMacAIRequestToken*)sendMessages:(NSArray*)messages tools:(NSArray*)tools model:(NSString*)model apiKey:(NSString*)key
 completion:(void (^)(NSDictionary*,NSError*))completion {
    if(self.markerPath) {
        int fd=open(self.markerPath.fileSystemRepresentation,O_CREAT|O_WRONLY|O_APPEND,0600);
        if(fd>=0){write(fd,"request\n",8);close(fd);}
    }
    (void)model;(void)key;Check(!tools.count,"analysis has no action tools");self.calls++;
    self.payload=[NSJSONSerialization JSONObjectWithData:[messages[1][@"content"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if(self.hold)self.held=completion;
    else dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{completion(@{@"content":self.reply},nil);});
    return [SPDFMacAIRequestToken new];
}
@end
@interface ShenzhenMacDelegate (AnalysisProbeInstall)
- (void)aiInstallAnalysis:(NSDictionary*)analysis error:(NSError*)error candidate:(NSDictionary*)candidate
    settings:(SPDFMacAISettings*)settings;
@end
@interface AnalysisReaderProbe : ShenzhenMacDelegate
@property(nonatomic) NSArray* candidates;
@property(nonatomic) NSUInteger candidateReads;
- (void)seedPath:(NSString*)path;
@end
@implementation AnalysisReaderProbe
- (NSArray*)aiDocumentCandidates {self.candidateReads++;return self.candidates;}
- (NSDictionary*)aiDocumentCandidateForPath:(NSString*)path { self.candidateReads++;for (NSDictionary* row in self.candidates) if ([row[@"path"] isEqual:path]) return row;return nil;}
- (void)seedPath:(NSString*)path {_path=path;}
- (BOOL)isMarkdownActive {return NO;}
- (void)rebuildSidebar {}
- (void)aiRememberAnalysis:(NSDictionary*)a forPath:(NSString*)p {}
@end
static int ProcessAnalysis(NSString* directory) {
    NSURL* root=[NSURL fileURLWithPath:directory];
    AnalysisTransport* transport=[AnalysisTransport new];transport.markerPath=[directory stringByAppendingPathComponent:@"requests"];
    transport.reply=@"{\"summary\":\"Shared\",\"keywords\":[],\"chapters\":[]}";
    SPDFMacAIAnalysisService* service=[[SPDFMacAIAnalysisService alloc]
        initWithCache:[[SPDFMacAIAnalysisCache alloc] initWithRootURL:root] transport:transport
        contextProvider:^NSDictionary*(NSString* p,BOOL l,NSProgress* g,NSError** e) {
            return @{@"pageCount":@1,@"pages":@[@{@"page":@1,@"text":@"same excerpt"}],@"outline":@[]};
        } hashProvider:^NSString*(NSString* p,NSProgress* g,NSError** e) {
            return [@"c" stringByPaddingToLength:64 withString:@"c" startingAtIndex:0];
        } keyProvider:^NSString*(NSError** e) {return @"offline-test-key";}];
    SPDFMacAISettings* settings=[[SPDFMacAISettings alloc] initWithURL:[root URLByAppendingPathComponent:@"settings"]];
    settings.enabled=YES;settings.automaticAnalysis=YES;
    __block BOOL done=NO,success=NO;
    [service analyzeDocumentAtPath:@"/shared.pdf" landscape:NO settings:settings completion:^(NSDictionary* a,NSError* e){
        done=YES;success=a && !e;
    }];
    return Wait(^BOOL{return done;}) && success ? 0 : 1;
}
#undef main
int main(int argc,const char** argv) { @autoreleasepool {
    if(argc==3 && strcmp(argv[1],"--process-analysis")==0) return ProcessAnalysis([NSString stringWithUTF8String:argv[2]]);
    NSString* hash=[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0];
    NSURL* root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    SPDFMacAIAnalysisCache* cache=[[SPDFMacAIAnalysisCache alloc] initWithRootURL:root];
    AnalysisTransport* transport=[AnalysisTransport new];
    transport.reply=@"{\"summary\":\"A summary\",\"keywords\":[\"test\"],\"chapters\":[{\"title\":\"Start\",\"page\":1,\"level\":1}]}";
    __block NSInteger hashes=0,contexts=0,keys=0;__block BOOL changed=NO;__block BOOL authored=NO;__block BOOL large=NO;__block NSString* layout=@"live-layout-1";
    SPDFMacAIAnalysisService* service=[[SPDFMacAIAnalysisService alloc] initWithCache:cache transport:transport
        contextProvider:^NSDictionary*(NSString* path,BOOL landscape,NSProgress* progress,NSError** error) {
            (void)path;(void)landscape;(void)progress;(void)error;contexts++;
            return @{@"layoutIdentity":layout,@"pageCount":large ? @40 : @2,@"pages":@[@{@"page":@1,@"text":large ? [@"x" stringByPaddingToLength:100000 withString:@"x" startingAtIndex:0] : @"First page"},@{@"page":@2,@"text":@"Second page"}],
                @"outline":authored ? @[@{@"title":@"Authored",@"page":@1,@"level":@1}] : @[],@"truncated":@NO};
        } hashProvider:^NSString*(NSString* path,NSProgress* progress,NSError** error) {
            (void)path;(void)progress;(void)error;hashes++;
            return changed && hashes%3==0 ? [@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0] : hash;
        } keyProvider:^NSString*(NSError** error) { (void)error;keys++;return @"sk-or-v1-offline-test-key"; }];
    SPDFMacAISettings* settings=[[SPDFMacAISettings alloc] initWithURL:[root URLByAppendingPathComponent:@"settings.yaml"]];
    [service analyzeDocumentAtPath:@"/test.pdf" landscape:NO settings:settings completion:nil];
    Check([service valueForKey:@"worker"]==nil && hashes==0 && contexts==0 && keys==0 && transport.calls==0 && ![NSFileManager.defaultManager fileExistsAtPath:root.path],"disabled analysis is fully inert");
    settings.enabled=YES;settings.automaticAnalysis=YES;__block BOOL done=NO;__block NSDictionary* result=nil;__block NSError* failure=nil;
    void (^completion)(NSDictionary*,NSError*)=^(NSDictionary* a,NSError* e){result=a;failure=e;done=YES;Check(NSThread.isMainThread,"analysis completion main queue");};
    [service analyzeDocumentAtPath:@"/test.pdf" landscape:NO settings:settings completion:completion];
    Check(Wait(^BOOL{return done;}) && result && !failure && transport.calls==1,"analysis produces validated result");
    Check([result[@"analyzedPages"] isEqual:@[@1,@2]] && ![result[@"partial"] boolValue],"accurate complete coverage");
    done=NO;[service analyzeDocumentAtPath:@"/test.pdf" landscape:NO settings:settings completion:completion];
    Check(Wait(^BOOL{return done;}) && transport.calls==1 && contexts==2 && keys==1,"same content deduplicates analysis and key access");
    Check([result[@"promptVersion"] isEqual:@"analysis-excerpts-v2"] && [result[@"cacheKey"] length]==64,"cache records model prompt and complete identity");
    settings.model=@"fixture/another-model";done=NO;
    [service analyzeDocumentAtPath:@"/test.pdf" landscape:NO settings:settings completion:completion];
    Check(Wait(^BOOL{return done;}) && result && transport.calls==2,"model change causes fresh analysis");
    layout=@"live-layout-2";done=NO;
    [service analyzeDocumentAtPath:@"/test.pdf" landscape:NO settings:settings completion:completion];
    Check(Wait(^BOOL{return done;}) && result && transport.calls==3,"live layout change causes fresh analysis");
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
    hashes=0;changed=YES;done=NO;result=nil;
    [service analyzeDocumentAtPath:@"/test.pdf" landscape:NO settings:settings completion:completion];
    Check(Wait(^BOOL{return done;}) && !result && failure && ![cache analysisForHash:hash],"changed source never commits stale analysis");
    changed=NO;authored=YES;done=NO;
    [service analyzeDocumentAtPath:@"/test.pdf" landscape:NO settings:settings completion:completion];
    Check(Wait(^BOOL{return done;}) && result && [result[@"chapters"] count]==0,"authored outline never replaced");
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
    authored=NO;large=YES;done=NO;
    [service analyzeDocumentAtPath:@"/test.pdf" landscape:NO settings:settings completion:completion];
    Check(Wait(^BOOL{return done;}) && result && [result[@"partial"] boolValue] && [result[@"analyzedPages"] isEqual:@[@1]],
        "bounded excerpts have explicit partial coverage");
    Check([transport.payload[@"pages"][0][@"text"] length]==64000,"upload text bound enforced");
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];large=NO;
    authored=NO;transport.reply=@"{\"summary\":\"A summary\",\"keywords\":[],\"chapters\":[{\"title\":\"Invalid\",\"page\":3}]}";
    done=NO;[service analyzeDocumentAtPath:@"/test.pdf" landscape:NO settings:settings completion:completion];
    Check(Wait(^BOOL{return done;}) && !result && failure,"out of bounds chapter rejected");
    service.maximumRequestsPerSession=transport.calls;NSInteger previous=transport.calls;
    done=NO;[service analyzeDocumentAtPath:@"/test.pdf" landscape:NO settings:settings completion:completion];
    Check(Wait(^BOOL{return done;}) && !result && failure && transport.calls==previous,"background request budget enforced");
    service.maximumRequestsPerSession=100;transport.hold=YES;done=NO;
    [service analyzeDocumentAtPath:@"/test.pdf" landscape:NO settings:settings completion:completion];
    Check(Wait(^BOOL{return transport.held!=nil;}),"request can remain in flight");
    [service cancelAll];transport.held(@{@"content":@"{\"summary\":\"Late\",\"keywords\":[],\"chapters\":[]}"},nil);
    Check(Wait(^BOOL{return done;}) && !result && failure.code==NSURLErrorCancelled && ![cache analysisForHash:hash],"late cancelled response cannot write analysis");
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
    [NSApplication sharedApplication];
    AnalysisReaderProbe* reader=[AnalysisReaderProbe new];[reader seedPath:@"/test.pdf"];
    settings.enabled=NO;[reader configureAIAnalysis:settings];[reader aiDocumentDidOpen:@"/test.pdf"];
    Check(reader.candidateReads==0,"production disabled document-open does not gather candidates or create service");
    settings.enabled=YES;[reader configureAIAnalysis:settings];
    NSDictionary* snapshot=@{@"path":@"/test.pdf",@"readPath":@"/test.pdf",@"revision":@"one",@"landscape":@NO,
        @"renderedDocument":[NSObject new],@"paginationPlan":[NSObject new]};reader.candidates=@[snapshot];
    NSDictionary* generated=@{@"model":settings.model,@"chapters":@[@{@"title":@"Generated",@"page":@1,@"level":@1}]};
    [reader aiInstallAnalysis:generated error:nil candidate:snapshot settings:settings];
    Check([reader aiGeneratedChapterRows].count==1,"generated analysis installs for current exact snapshot");
    SPDFMacAISettings* unrelated=[[SPDFMacAISettings alloc] initWithURL:[root URLByAppendingPathComponent:@"unrelated.yaml"]];
    unrelated.enabled=settings.enabled;unrelated.automaticAnalysis=settings.automaticAnalysis;unrelated.model=settings.model;
    [reader configureAIAnalysis:unrelated];
    Check([reader aiGeneratedChapterRows].count==1,"unrelated settings changes preserve existing generated chapters");
    NSMutableDictionary* later=[snapshot mutableCopy];later[@"paginationPlan"]=[NSObject new];reader.candidates=@[later];
    Check([reader aiGeneratedChapterRows].count==0,"changed pagination immediately hides generated chapters");
    [reader aiInstallAnalysis:generated error:nil candidate:snapshot settings:settings];
    Check([reader aiGeneratedChapterRows].count==0,"late old-layout completion cannot install chapters");
    reader.candidates=@[snapshot];settings.enabled=NO;[reader configureAIAnalysis:settings];
    [reader aiInstallAnalysis:generated error:nil candidate:snapshot settings:settings];
    Check(![reader aiAnalysisForPath:@"/test.pdf"],"opt-out rejects already queued main-thread completion");
    [NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
    NSString* md=[root.path stringByAppendingPathComponent:@"assets.md"];
    NSString* asset=[root.path stringByAppendingPathComponent:@"asset.png"];
    NSBitmapImageRep* bitmap=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:8 pixelsHigh:8
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    memset(bitmap.bitmapData,80,bitmap.bytesPerRow*bitmap.pixelsHigh);
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:asset atomically:YES];
    [@"![fixture](asset.png)\n\nAn image and evidence." writeToFile:md atomically:YES encoding:NSUTF8StringEncoding error:nil];
    SPDFMarkdownDocument* document=[SPDFMarkdownDocument documentWithURL:[NSURL fileURLWithPath:md] options:nil error:nil];
    SPDFMarkdownPaginationPlan* plan=[document paginationPlanForConfiguration:SPDFMarkdownPageConfiguration.A4PortraitConfiguration];
    NSDictionary* liveCandidate=@{@"path":md,@"readPath":md,@"revision":SPDFSearchFileStamp(md),@"sourceRevision":SPDFSearchFileStamp(md),
        @"renderedDocument":document.renderedDocument,@"paginationPlan":plan};
    NSProgress* readProgress=[NSProgress progressWithTotalUnitCount:1];
    NSDictionary* imageBefore=SPDFAIDocumentContextForCandidate(liveCandidate,1,30,readProgress,nil);
    memset(bitmap.bitmapData,180,bitmap.bytesPerRow*bitmap.pixelsHigh);
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:asset atomically:YES];
    NSDictionary* imageAfter=SPDFAIDocumentContextForCandidate(liveCandidate,1,30,readProgress,nil);
    Check(imageBefore && imageAfter && ![imageBefore[@"layoutIdentity"] isEqual:imageAfter[@"layoutIdentity"]],
        "image bytes invalidate analysis identity without changing Markdown or pagination");
    SPDFMarkdownPageConfiguration* geometry=[SPDFMarkdownPageConfiguration A4PortraitConfiguration];
    geometry.headingKeepThreshold+=1;
    NSMutableDictionary* changedGeometry=[liveCandidate mutableCopy];
    changedGeometry[@"paginationPlan"]=[document paginationPlanForConfiguration:geometry];
    NSDictionary* geometryContext=SPDFAIDocumentContextForCandidate(changedGeometry,1,30,readProgress,nil);
    Check(geometryContext && ![geometryContext[@"layoutIdentity"] isEqual:imageAfter[@"layoutIdentity"]],
        "explicit page configuration participates even when page boundaries are unchanged");
    [@"![fixture](https://example.invalid/image.png)\n\nEvidence." writeToFile:md atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSMutableArray* remoteIdentities=[NSMutableArray array];
    for (NSUInteger i=0;i<2;i++) {
        memset(bitmap.bitmapData,i ? 50 : 200,bitmap.bytesPerRow*bitmap.pixelsHigh);
        SPDFMarkdownRenderOptions* options=SPDFMarkdownRenderOptions.defaultOptions;
        options.remoteImageData=@{@"https://example.invalid/image.png":
            [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]};
        SPDFMarkdownDocument* remote=[SPDFMarkdownDocument documentWithURL:[NSURL fileURLWithPath:md] options:options error:nil];
        NSDictionary* remoteCandidate=@{@"path":md,@"readPath":md,@"revision":SPDFSearchFileStamp(md),@"sourceRevision":SPDFSearchFileStamp(md),
            @"renderedDocument":remote.renderedDocument,
            @"paginationPlan":[remote paginationPlanForConfiguration:SPDFMarkdownPageConfiguration.A4PortraitConfiguration]};
        NSDictionary* remoteContext=SPDFAIDocumentContextForCandidate(remoteCandidate,1,30,readProgress,nil);
        if (remoteContext) [remoteIdentities addObject:remoteContext[@"layoutIdentity"]];
    }
    Check(remoteIdentities.count==2 && ![remoteIdentities[0] isEqual:remoteIdentities[1]],
        "already loaded remote image bytes affect identity without a network request");
    NSURL* shared=[root URLByAppendingPathComponent:@"shared"];
    NSTask* first=[NSTask new];NSTask* second=[NSTask new];
    first.executableURL=second.executableURL=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[0]]];
    first.arguments=second.arguments=@[@"--process-analysis",shared.path];
    Check([first launchAndReturnError:nil] && [second launchAndReturnError:nil],"two independent analysis processes start");
    [first waitUntilExit];[second waitUntilExit];
    NSString* calls=[NSString stringWithContentsOfFile:[shared.path stringByAppendingPathComponent:@"requests"] encoding:NSUTF8StringEncoding error:nil];
    Check(first.terminationStatus==0 && second.terminationStatus==0 && [calls isEqual:@"request\n"],"two processes issue exactly one paid request for one key");
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
    fprintf(stderr,"AI analysis service checks: %s (%d failures)\n",failures ? "FAIL" : "PASS",failures);return failures ? 1 : 0;
} }
