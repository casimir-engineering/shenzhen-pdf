#import "SPDFMacAIModelCatalog.h"
static NSError* Error(NSString* text) { return [NSError errorWithDomain:@"ShenzhenPDF.AI.Model" code:1 userInfo:@{NSLocalizedDescriptionKey:text}]; }
NSDictionary* SPDFMacAIModelFromCatalog(NSData* data,NSString* identifier,NSError** error) {
    if (!data.length || data.length>4*1024*1024) { if(error)*error=Error(@"Model list is unavailable. Your chosen model has been kept."); return nil; }
    id value=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray* models=[value isKindOfClass:NSDictionary.class] ? value[@"data"] : nil;
    if (![models isKindOfClass:NSArray.class]) { if(error)*error=Error(@"OpenRouter returned an invalid model list."); return nil; }
    for (id model in models) {
        if (![model isKindOfClass:NSDictionary.class] || ![model[@"id"] isEqual:identifier]) continue;
        NSArray* parameters=model[@"supported_parameters"];
        if (![parameters isKindOfClass:NSArray.class] || ![parameters containsObject:@"tools"]) {
            if(error)*error=Error(@"This model does not advertise tool support. Choose a model that can work with documents."); return nil;
        }
        return model;
    }
    if(error)*error=Error(@"That model is not currently in OpenRouter’s catalog. Check its ID or choose another model. Your preference has been kept."); return nil;
}
NSURLSessionDataTask* SPDFMacAIValidateModel(NSString* identifier,void (^completion)(NSDictionary*,NSError*)) {
    NSURLSessionConfiguration* config=NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForRequest=20; config.timeoutIntervalForResource=25; config.URLCache=nil;
    NSURLSession* session=[NSURLSession sessionWithConfiguration:config];
    NSURLSessionDataTask* task=[session dataTaskWithURL:[NSURL URLWithString:@"https://openrouter.ai/api/v1/models"]
        completionHandler:^(NSData* data,NSURLResponse* response,NSError* error) {
            NSError* failure=error;
            if (!failure && [(NSHTTPURLResponse*)response statusCode]!=200) failure=Error(@"OpenRouter’s model list could not be checked. Try again later.");
            NSDictionary* model=failure ? nil : SPDFMacAIModelFromCatalog(data,identifier,&failure);
            [session finishTasksAndInvalidate];
            dispatch_async(dispatch_get_main_queue(),^{ if(completion)completion(model,failure); });
        }];
    [task resume]; return task;
}
