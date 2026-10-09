#import "SPDFMacAITransport.h"
NSString* const SPDFMacAIDefaultModel=@"deepseek/deepseek-v4.1-flash";
NSError* SPDFMacAIError(NSInteger code,NSString* message) {
    return [NSError errorWithDomain:@"SPDFMacAI" code:code userInfo:@{NSLocalizedDescriptionKey:message}];
}
static BOOL ValidModel(NSString* model) {
    return [model isKindOfClass:NSString.class] && model.length>0 && model.length<=160 &&
        [model rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location==NSNotFound;
}
NSURLRequest* SPDFMacAIChatRequest(NSArray<NSDictionary*>* messages,NSArray<NSDictionary*>* tools,
                                 NSString* model,NSString* apiKey,NSError** error) {
    if (error) *error=nil;
    if (![messages isKindOfClass:NSArray.class] || !messages.count || messages.count>128 ||
        (tools && (![tools isKindOfClass:NSArray.class] || tools.count>48)) || !ValidModel(model) ||
        ![apiKey isKindOfClass:NSString.class] || apiKey.length<12 || apiKey.length>512 ||
        [apiKey rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location!=NSNotFound) {
        if(error)*error=SPDFMacAIError(1,@"Connect OpenRouter and choose a valid model before sending."); return nil;
    }
    NSMutableDictionary* body=[@{@"model":model,@"messages":messages,@"stream":@NO,@"max_tokens":@4096,
        @"provider":@{@"data_collection":@"deny",@"zdr":@YES},@"user":@"shenzhen-pdf"} mutableCopy];
    if (tools.count) { body[@"tools"]=tools; body[@"tool_choice"]=@"auto"; }
    if (![NSJSONSerialization isValidJSONObject:body]) {
        if(error)*error=SPDFMacAIError(2,@"The conversation contains unsupported data."); return nil;
    }
    NSData* data=[NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    if (!data || data.length>1024*1024) {
        if(error)*error=SPDFMacAIError(3,@"This conversation is too large. Start a new chat or narrow the document context.");
        return nil;
    }
    NSMutableURLRequest* request=[NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:@"https://openrouter.ai/api/v1/chat/completions"]
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:90];
    request.HTTPMethod=@"POST"; request.HTTPBody=data;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[@"Bearer " stringByAppendingString:apiKey] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"Shenzhen PDF" forHTTPHeaderField:@"X-Title"];
    return request;
}
@interface SPDFMacAIRequestToken ()
@property(nonatomic) NSURLSessionTask* task;
@property(nonatomic) BOOL cancelledValue;
@end
@implementation SPDFMacAIRequestToken
- (BOOL)isCancelled { @synchronized(self) { return _cancelledValue; } }
- (void)setTask:(NSURLSessionTask*)task { @synchronized(self) { _task=task; if(_cancelledValue)[task cancel]; } }
- (void)cancel { @synchronized(self) { _cancelledValue=YES; [_task cancel]; } }
@end
@interface SPDFMacAIResponse : NSObject <NSURLSessionDataDelegate>
@property(nonatomic) NSMutableData* bytes;
@property(nonatomic) NSError* failure;
@property(nonatomic) NSInteger status;
@property(nonatomic) SPDFMacAIRequestToken* token;
@property(nonatomic,copy) void (^completion)(NSDictionary*,NSError*);
@end
@implementation SPDFMacAIResponse
- (void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task
 willPerformHTTPRedirection:(NSHTTPURLResponse*)response newRequest:(NSURLRequest*)request
 completionHandler:(void (^)(NSURLRequest*))completionHandler {
    (void)session;(void)task;(void)response;(void)request;
    // Never forward the credential or document to a redirected origin.
    completionHandler(nil);
}
- (void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)task
 didReceiveResponse:(NSURLResponse*)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completion {
    (void)session;(void)task;
    self.status=[response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse*)response).statusCode : 0;
    if (response.expectedContentLength>2*1024*1024) {
        self.failure=SPDFMacAIError(4,@"The model response exceeded the size limit."); completion(NSURLSessionResponseCancel);
    } else completion(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)task didReceiveData:(NSData*)data {
    (void)session;
    if(self.bytes.length+data.length>2*1024*1024) {
        self.failure=SPDFMacAIError(4,@"The model response exceeded the size limit."); [task cancel]; return;
    }
    [self.bytes appendData:data];
}
- (void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task didCompleteWithError:(NSError*)error {
    (void)task;
    NSDictionary* message=nil; NSError* failure=self.failure;
    if(self.token.cancelled) failure=[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil];
    else if (!failure && error) failure=SPDFMacAIError(5,@"OpenRouter could not be reached. Check your connection and retry.");
    else if (!failure && (self.status<200 || self.status>=300)) {
        NSString* text=self.status==401 ? @"OpenRouter authorization expired. Connect again in Settings." :
            self.status==402 ? @"Your OpenRouter account needs credits." :
            self.status==429 ? @"OpenRouter is busy or your account limit was reached. Try again shortly." :
            @"OpenRouter could not complete the request with the required privacy settings. Try another model.";
        failure=SPDFMacAIError(self.status,text);
    }
    if(!failure) {
        id JSON=[NSJSONSerialization JSONObjectWithData:self.bytes options:0 error:nil];
        id choices=[JSON isKindOfClass:NSDictionary.class] ? JSON[@"choices"] : nil;
        id first=[choices isKindOfClass:NSArray.class] && [choices count] ? choices[0] : nil;
        id candidate=[first isKindOfClass:NSDictionary.class] ? first[@"message"] : nil;
        if([candidate isKindOfClass:NSDictionary.class] &&
            ([candidate[@"content"] isKindOfClass:NSString.class] || [candidate[@"tool_calls"] isKindOfClass:NSArray.class]))
            message=candidate;
        else failure=SPDFMacAIError(6,@"The model returned an unreadable response. Try again.");
    }
    void (^completion)(NSDictionary*,NSError*)=self.completion; self.completion=nil;
    self.token.task=nil; self.bytes=nil;
    [session finishTasksAndInvalidate];
    if(completion) dispatch_async(dispatch_get_main_queue(),^{
        if(self.token.cancelled) completion(nil,[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
        else completion(message,failure);
    });
}
@end
@implementation SPDFMacAITransport { NSURLSessionConfiguration* _configuration; }
- (instancetype)initWithConfiguration:(NSURLSessionConfiguration*)configuration {
    if((self=[super init])) _configuration=[configuration copy]; return self;
}
- (SPDFMacAIRequestToken*)sendMessages:(NSArray<NSDictionary*>*)messages tools:(NSArray<NSDictionary*>*)tools
    model:(NSString*)model apiKey:(NSString*)apiKey completion:(void (^)(NSDictionary*,NSError*))completion {
    SPDFMacAIRequestToken* token=[SPDFMacAIRequestToken new]; NSError* error=nil;
    NSURLRequest* request=SPDFMacAIChatRequest(messages,tools,model,apiKey,&error);
    if(!request) {
        dispatch_async(dispatch_get_main_queue(),^{ if(completion) completion(nil,error); }); return token;
    }
    NSURLSessionConfiguration* configuration=_configuration ? [_configuration copy] : NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.URLCache=nil; configuration.HTTPCookieStorage=nil; configuration.URLCredentialStorage=nil;
    configuration.timeoutIntervalForRequest=90; configuration.timeoutIntervalForResource=120;
    SPDFMacAIResponse* response=[SPDFMacAIResponse new]; response.bytes=[NSMutableData data];
    response.token=token; response.completion=completion;
    NSURLSession* session=[NSURLSession sessionWithConfiguration:configuration delegate:response delegateQueue:nil];
    NSURLSessionDataTask* task=[session dataTaskWithRequest:request]; token.task=task; [task resume]; return token;
}
@end
