#import "SPDFMacAITransport.h"
#import "SPDFMacAISettings.h"
#import "SPDFMacAICredentials.h"
#import "SPDFMacAIOpenRouterAuth.h"
#import "SPDFMacKeychainNoninteractiveChecks.h"
#import <arpa/inet.h>
#import <sys/socket.h>
#import <unistd.h>
static int failures=0, requests=0, mode=0;
static NSURLRequest* captured;
static void Check(BOOL value,const char* name) { if(!value){fprintf(stderr,"FAIL %s\n",name);failures++;} }
static BOOL Wait(BOOL (^predicate)(void)) {
    NSDate* limit=[NSDate dateWithTimeIntervalSinceNow:3];
    while(!predicate() && limit.timeIntervalSinceNow>0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
    return predicate();
}
@interface FakeProtocol : NSURLProtocol @end
@implementation FakeProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest*)request { return [request.URL.host isEqual:@"openrouter.ai"]; }
+ (NSURLRequest*)canonicalRequestForRequest:(NSURLRequest*)request { return request; }
- (void)startLoading {
    @synchronized(FakeProtocol.class) { requests++; captured=self.request; }
    if(mode==1)return;
    NSInteger status=mode==2 ? 401 : 200;
    [self.client URLProtocol:self didReceiveResponse:[[NSHTTPURLResponse alloc] initWithURL:self.request.URL
        statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}]
        cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    NSData* data=nil;
    if(mode==3)data=[NSMutableData dataWithLength:2*1024*1024+1];
    else if(mode==4)data=[@"{\"wrong\":true}" dataUsingEncoding:NSUTF8StringEncoding];
    else if([self.request.URL.path hasSuffix:@"/auth/keys"])
        data=[@"{\"key\":\"sk-or-v1-offline-test-key-value\"}" dataUsingEncoding:NSUTF8StringEncoding];
    else data=[@"{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"Hello\"}}]}" dataUsingEncoding:NSUTF8StringEncoding];
    [self.client URLProtocol:self didLoadData:data]; [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end
@interface FakeKeychain : NSObject <SPDFMacAIKeychainAccess>
@property(nonatomic) NSInteger calls;
@property(nonatomic) NSData* stored;
@property(nonatomic) NSDictionary* last;
@property(nonatomic) OSStatus failure;
@property(nonatomic) NSUInteger interactiveCalls;
@property(nonatomic) BOOL unsupportedAuthorization;
@end
@implementation FakeKeychain
- (BOOL)respondsToSelector:(SEL)selector {
    if(self.unsupportedAuthorization && selector==@selector(copyMatchingWithUserInteraction:result:))return NO;
    return [super respondsToSelector:selector];
}
- (OSStatus)copyMatchingWithUserInteraction:(NSDictionary*)query result:(NSData**)result {
    self.interactiveCalls++;return [self copyMatching:query result:result];
}
- (OSStatus)copyMatching:(NSDictionary*)query result:(NSData**)result {
    self.calls++; self.last=query; if(self.failure)return self.failure;
    if(result)*result=self.stored; return self.stored ? errSecSuccess : errSecItemNotFound;
}
- (OSStatus)add:(NSDictionary*)attributes {
    self.calls++; self.last=attributes; if(self.failure)return self.failure;if(self.stored)return errSecDuplicateItem;
    self.stored=[attributes[(__bridge id)kSecValueData] copy];return errSecSuccess;
}
- (OSStatus)update:(NSDictionary*)query attributes:(NSDictionary*)attributes {
    self.calls++;self.last=query;if(self.failure)return self.failure;
    self.stored=[attributes[(__bridge id)kSecValueData] copy];return errSecSuccess;
}
- (OSStatus)remove:(NSDictionary*)query {self.calls++;self.last=query;if(self.failure)return self.failure;self.stored=nil;return errSecSuccess;}
@end
static NSDictionary* RequestJSON(NSURLRequest* request) {
    NSData* data=request.HTTPBody;
    if(!data && request.HTTPBodyStream) {
        NSInputStream* stream=request.HTTPBodyStream; [stream open]; NSMutableData* bytes=[NSMutableData data];
        uint8_t buffer[2048]; NSInteger count;
        while((count=[stream read:buffer maxLength:sizeof(buffer)])>0)[bytes appendBytes:buffer length:(NSUInteger)count];
        [stream close];data=bytes;
    }
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}
static NSString* Callback(NSURL* URL,NSString* code,NSString* state) {
    NSURLComponents* target=[NSURLComponents componentsWithURL:URL resolvingAgainstBaseURL:NO];
    target.queryItems=code || state ? @[[NSURLQueryItem queryItemWithName:@"code" value:code],[NSURLQueryItem queryItemWithName:@"state" value:state]] : nil;
    int fd=socket(AF_INET,SOCK_STREAM,0); struct sockaddr_in address={}; address.sin_family=AF_INET;
    address.sin_port=htons(target.port.unsignedShortValue);address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    if(connect(fd,(struct sockaddr*)&address,sizeof(address))!=0){close(fd);return nil;}
    struct timeval timeout={2,0};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    NSString* suffix=target.percentEncodedQuery.length ? [@"?" stringByAppendingString:target.percentEncodedQuery] : @"";
    NSString* request=[NSString stringWithFormat:@"GET %@%@ HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",target.percentEncodedPath,suffix];
    NSData* data=[request dataUsingEncoding:NSUTF8StringEncoding];send(fd,data.bytes,data.length,0);
    char response[2048];ssize_t n=recv(fd,response,sizeof(response),0);close(fd);
    return n>0 ? [[NSString alloc] initWithBytes:response length:(NSUInteger)n encoding:NSUTF8StringEncoding] : nil;
}
int main(void) { @autoreleasepool {
    CheckNoninteractiveGuard(^(BOOL ok,NSString* label){Check(ok,label.UTF8String);});
    NSURLSessionConfiguration* config=NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.protocolClasses=@[FakeProtocol.class]; SPDFMacAITransport* transport=[[SPDFMacAITransport alloc] initWithConfiguration:config];
    FakeKeychain* keychain=[FakeKeychain new];SPDFMacAICredentials* credentials=[[SPDFMacAICredentials alloc] initWithKeychain:keychain];
    NSURL* root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    NSURL* settingsURL=[root URLByAppendingPathComponent:@"ai-settings.yaml"];
    SPDFMacAISettings* settings=[[SPDFMacAISettings alloc] initWithURL:settingsURL];
    SPDFMacAIOpenRouterAuth* auth=[[SPDFMacAIOpenRouterAuth alloc] initWithConfiguration:config credentials:credentials];
    Check(requests==0 && keychain.calls==0 && ![NSFileManager.defaultManager fileExistsAtPath:root.path],"construction has zero network, Keychain or disk side effects");
    Check(settings.enabled && settings.automaticAnalysis && [settings.model isEqual:SPDFMacAIDefaultModel],"chat and analysis default on without construction side effects");
    Check(![settings allowsRequestsForSetupRevision:2],"default-on features do no work before setup and connection");
    settings.connectionConfigured=YES;
    Check(![settings allowsRequestsForSetupRevision:2],"connection alone does not bypass setup");
    settings.onboardingRevision=2;
    Check([settings allowsRequestsForSetupRevision:2],"completed setup and connection permit AI");
    settings.connectionConfigured=NO;
    Check(![settings allowsRequestsForSetupRevision:2],"disconnect immediately gates requests");
    NSError* error=nil; Check([settings load:&error],"missing settings loads defaults");
    settings.enabled=YES; settings.automaticAnalysis=YES; settings.onboardingStep=2; settings.onboardingRevision=2; settings.showSettingsOnLaunch=YES;Check([settings save:&error],"save YAML");
    SPDFMacAISettings* restored=[[SPDFMacAISettings alloc] initWithURL:settingsURL];Check([restored load:&error] && restored.enabled && restored.automaticAnalysis && restored.onboardingRevision==2 && restored.onboardingStep==2 && restored.showSettingsOnLaunch,"YAML round trip");
    SPDFMacAISettings* parallel=[[SPDFMacAISettings alloc] initWithURL:settingsURL];[parallel load:&error];
    restored.model=@"deepseek/deepseek-v4-flash";Check([restored save:&error],"first window saves model");
    parallel.automaticAnalysis=NO;Check([parallel save:&error],"second window saves analysis");
    [restored load:&error];Check([restored.model isEqual:@"deepseek/deepseek-v4-flash"] && !restored.automaticAnalysis,
        "locked field merge preserves concurrent window changes");
    settings.model=@"x\napi_key: secret";Check(![settings save:&error],"reject YAML injection");
    Check(![credentials storeAPIKey:@"bad" error:&error] && keychain.calls==0,"reject invalid key before Keychain");
    NSString* key=@"sk-or-v1-offline-test-key-value";
    Check([credentials storeAPIKey:key error:&error] && NoninteractiveQuery(keychain.last),"secure key add disables UI");
    Check([[credentials APIKeyWithError:&error] isEqual:key] && NoninteractiveQuery(keychain.last),"secure key read disables UI");
    Check([keychain.last[(__bridge id)kSecAttrSynchronizable] isEqual:@NO],"credential remains local");
    Check([credentials storeAPIKey:key error:&error] && NoninteractiveQuery(keychain.last),"replace existing credential without UI");
    keychain.failure=errSecInteractionNotAllowed;
    Check(![credentials APIKeyWithError:&error] && error.code==errSecInteractionNotAllowed,"locked AI key fails without pretending connected");
    Check(![credentials storeAPIKey:key error:&error] && error.code==errSecInteractionNotAllowed,"locked AI key cannot pretend save succeeded");
    Check(![credentials removeAPIKeyWithError:&error] && error.code==errSecInteractionNotAllowed && keychain.stored.length,"denied disconnect preserves the credential");
    keychain.failure=errSecSuccess;
    Check(keychain.interactiveCalls==0,"normal credential operations never request interactive authorization");
    Check([[credentials authorizeAPIKeyAccessWithError:&error] isEqual:key] && keychain.interactiveCalls==1 &&
        ExplicitAuthorizationQuery(keychain.last) &&
        [keychain.last[(__bridge id)kSecReturnData] boolValue],"explicit authorization alone allows system UI and returns the validated key");
    Check([[credentials APIKeyWithError:&error] isEqual:key] && NoninteractiveQuery(keychain.last) && keychain.interactiveCalls==1,
        "authorization never changes subsequent noninteractive query policy");
    keychain.failure=errSecUserCanceled;
    Check(![credentials authorizeAPIKeyAccessWithError:&error] && error.code==errSecUserCanceled && keychain.stored.length,
        "cancelled explicit authorization preserves key and reports cancellation");
    keychain.failure=errSecAuthFailed;
    Check(![credentials authorizeAPIKeyAccessWithError:&error] && error.code==errSecAuthFailed && keychain.stored.length,
        "failed explicit authorization cannot pretend success");
    keychain.failure=errSecSuccess;keychain.unsupportedAuthorization=YES;NSInteger calls=keychain.calls;
    Check(![credentials authorizeAPIKeyAccessWithError:&error] && error.code==errSecUnimplemented && keychain.calls==calls,
        "backend without explicit authorization support fails closed");
    keychain.unsupportedAuthorization=NO;
    Check([credentials removeAPIKeyWithError:&error] && NoninteractiveQuery(keychain.last),"disconnect removes credential without UI");
    Check(![credentials APIKeyWithError:&error],"disconnected credential stays absent");
    NSArray* messages=@[@{@"role":@"user",@"content":@"Test"}];
    NSURLRequest* request=SPDFMacAIChatRequest(messages,@[],SPDFMacAIDefaultModel,key,&error);
    NSDictionary* body=RequestJSON(request);
    Check([body[@"provider"][@"data_collection"] isEqual:@"deny"] && [body[@"provider"][@"zdr"] boolValue],"privacy fail closed");
    Check([body[@"max_tokens"] integerValue]==4096 && request.timeoutInterval==90,"bounded token and timeout budget");
    NSString* huge=[@"x" stringByPaddingToLength:1024*1024+1 withString:@"x" startingAtIndex:0];
    Check(!SPDFMacAIChatRequest(@[@{@"role":@"user",@"content":huge}],nil,SPDFMacAIDefaultModel,key,&error),"oversized request rejected");
    __block BOOL done=NO;__block NSDictionary* result=nil;__block NSError* failure=nil;
    void (^completion)(NSDictionary*,NSError*)=^(NSDictionary* message,NSError* e){result=message;failure=e;done=YES;Check(NSThread.isMainThread,"completion on main thread");};
    [transport sendMessages:messages tools:nil model:SPDFMacAIDefaultModel apiKey:key completion:completion];
    Check(Wait(^BOOL{return done;}) && !failure && [result[@"content"] isEqual:@"Hello"],"offline successful response");
    for(int testMode=2;testMode<=4;testMode++) {
        mode=testMode; done=NO;result=nil;failure=nil;
        [transport sendMessages:messages tools:nil model:SPDFMacAIDefaultModel apiKey:key completion:completion];
        Check(Wait(^BOOL{return done;}) && failure && !result,"HTTP, oversized and malformed response safely rejected");
        Check([failure.localizedDescription rangeOfString:key].location==NSNotFound,"errors exclude credentials");
    }
    mode=1;done=NO;failure=nil;
    SPDFMacAIRequestToken* token=[transport sendMessages:messages tools:nil model:SPDFMacAIDefaultModel apiKey:key completion:completion];
    [token cancel];Check(Wait(^BOOL{return done;}) && token.cancelled && failure.code==NSURLErrorCancelled,"cancellation completes without result");
    Check([SPDFMacAIPKCEChallenge(@"dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") isEqual:@"E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"],"RFC 7636 S256 vector");
    mode=0;done=NO;failure=nil;__block BOOL connected=NO;NSInteger keyCalls=keychain.calls;
    NSURL* authorization=[auth startWithCompletion:^(BOOL success,NSError* e){connected=success;failure=e;done=YES;} error:&error];
    Check(authorization && keychain.calls==keyCalls,"sign-in begins without reading credentials");
    NSMutableDictionary* query=[NSMutableDictionary dictionary];
    for(NSURLQueryItem* item in [NSURLComponents componentsWithURL:authorization resolvingAgainstBaseURL:NO].queryItems)query[item.name]=item.value;
    NSURL* callback=[NSURL URLWithString:query[@"callback_url"]];
    Check([Callback(callback,@"offline-code",@"wrong-state") containsString:@"400 Bad Request"],"forged callback rejected");
    Check(!done && keychain.calls==keyCalls,"forged callback does not consume sign-in or modify credentials");
    Check([Callback(callback,@"offline-code",query[@"state"]) containsString:@"200 OK"],"matching local callback accepted");
    Check(Wait(^BOOL{return done;}) && connected && !failure,"OAuth exchange and secure save complete offline");
    NSDictionary* exchange=RequestJSON(captured);
    Check([SPDFMacAIPKCEChallenge(exchange[@"code_verifier"]) isEqual:query[@"code_challenge"]],"OAuth verifier matches browser challenge");
    SPDFMacAIOpenRouterAuth* cancelled=[[SPDFMacAIOpenRouterAuth alloc] initWithConfiguration:config credentials:credentials];
    done=NO;[cancelled startWithCompletion:^(BOOL success,NSError* e){connected=success;failure=e;done=YES;} error:&error];
    [cancelled cancel];Check(Wait(^BOOL{return done;}) && !connected && failure.code==NSURLErrorCancelled,"OAuth cancellable");
    SPDFMacAIOpenRouterAuth* denied=[[SPDFMacAIOpenRouterAuth alloc] initWithConfiguration:config credentials:credentials];
    done=NO; keyCalls=keychain.calls; NSInteger beforeRequests=requests;
    authorization=[denied startWithCompletion:^(BOOL success,NSError* e){connected=success;failure=e;done=YES;} error:&error];
    for(NSURLQueryItem* item in [NSURLComponents componentsWithURL:authorization resolvingAgainstBaseURL:NO].queryItems)query[item.name]=item.value;
    callback=[NSURL URLWithString:query[@"callback_url"]];
    NSURL* unrelated=[NSURL URLWithString:@"/favicon.ico" relativeToURL:callback].absoluteURL;
    Check([Callback(unrelated,nil,nil) containsString:@"400 Bad Request"] && !done,"unrelated empty browser probe cannot cancel sign-in");
    Check([Callback(callback,nil,nil) containsString:@"Connection cancelled"],"real provider denial returns a friendly browser response");
    Check(Wait(^BOOL{return done;}) && !connected && failure.code==NSURLErrorCancelled,"provider denial immediately completes cancellation");
    Check(keychain.calls==keyCalls && requests==beforeRequests,"denial neither exchanges a code nor touches credentials");
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
    fprintf(stderr,"AI transport checks: %s (%d failures)\n",failures ? "FAIL" : "PASS",failures);return failures ? 1 : 0;
} }
