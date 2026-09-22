#import "SPDFMacCollectionStorePrivate.h"
@implementation SPDFMacCollectionStore (CaptureScheduling)
- (NSNumber*)advanceCaptureGenerationForPath:(NSString*)path {
    @synchronized (self) {
        if (!self.captureGenerations) self.captureGenerations = [NSMutableDictionary dictionary];
        NSString* key = SPDFCollectionPath(path);
        NSNumber* next = @([self.captureGenerations[key] unsignedLongLongValue] + 1);
        self.captureGenerations[key] = next; return next;
    }
}
- (BOOL)captureRequestIsCurrentForPath:(NSString*)path {
    NSDictionary* context = NSThread.currentThread.threadDictionary[[NSString stringWithFormat:@"SPDFCollectionCapture.%p", self]];
    if (!context || ![context[@"path"] isEqual:SPDFCollectionPath(path)]) return YES;
    @synchronized (self) { return [context[@"generation"] isEqual:self.captureGenerations[SPDFCollectionPath(path)]]; }
}
- (BOOL)captureEpochIsCurrentForPath:(NSString*)path document:(NSDictionary*)document {
    NSDictionary* context = NSThread.currentThread.threadDictionary[[NSString stringWithFormat:@"SPDFCollectionCapture.%p", self]];
    return !context || ![context[@"path"] isEqual:SPDFCollectionPath(path)] ||
        [context[@"epoch"] isEqual:document[@"protectionEpoch"] ?: @""];
}
- (void)capturePath:(NSString*)path reason:(NSString*)reason completion:(void (^)(NSDictionary*,NSError*))completion {
    [self capturePath:path reason:reason continuingDocumentID:nil completion:completion];
}
- (void)capturePath:(NSString*)path reason:(NSString*)reason continuingDocumentID:(NSString*)documentID
        completion:(void (^)(NSDictionary*,NSError*))completion {
    if (![self isEnabled] || [self isArchivePath:path]) { if (completion) dispatch_async(dispatch_get_main_queue(),^{ completion(nil,nil); }); return; }
    @synchronized (self) {
        if (!self.captureQueue) { self.captureQueue=[NSOperationQueue new]; self.captureQueue.maxConcurrentOperationCount=1;
            self.captureQueue.qualityOfService=NSQualityOfServiceUtility; }
    }
    [self enqueueCapturePath:path reason:reason continuingDocumentID:documentID attempt:0 generation:[self advanceCaptureGenerationForPath:path] epoch:[self documentForPath:path][@"protectionEpoch"] ?: @"" completion:completion];
}
- (void)enqueueCapturePath:(NSString*)path reason:(NSString*)reason continuingDocumentID:(NSString*)documentID
                  attempt:(NSUInteger)attempt generation:(NSNumber*)generation epoch:(NSString*)epoch completion:(void (^)(NSDictionary*,NSError*))completion {
    NSBlockOperation* operation=[NSBlockOperation blockOperationWithBlock:^{
        NSString* contextKey = [NSString stringWithFormat:@"SPDFCollectionCapture.%p", self];
        NSThread.currentThread.threadDictionary[contextKey] = @{@"path":SPDFCollectionPath(path), @"generation":generation, @"epoch":epoch};
        NSError* error=nil; NSDictionary* row;
        @try { row=[self capturePath:path reason:reason continuingDocumentID:documentID error:&error]; }
        @finally { [NSThread.currentThread.threadDictionary removeObjectForKey:contextKey]; }
        BOOL transient=([error.domain isEqual:@"SPDFCollection"] &&
                        (error.code==5 || error.code==EAGAIN || error.code==EINTR || error.code==EBUSY)) ||
                       ([error.domain isEqual:NSCocoaErrorDomain] && error.code==NSFileReadUnknownError);
        if (!row && transient && attempt<2 && self.isEnabled) {
            NSString* continuation=documentID ?: error.userInfo[@"continuingDocumentID"];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)((attempt+1)*0.25*NSEC_PER_SEC)),
                dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
                    if (self.isEnabled) [self enqueueCapturePath:path reason:reason continuingDocumentID:continuation
                                                        attempt:attempt+1 generation:generation epoch:epoch completion:completion];
                    else if(completion)dispatch_async(dispatch_get_main_queue(),^{completion(nil,nil);});
                });
            return;
        }
        if (completion) dispatch_async(dispatch_get_main_queue(),^{ completion(row,error); });
    }];
    operation.queuePriority=[reason isEqual:@"Imported recent document"] ? NSOperationQueuePriorityVeryLow : NSOperationQueuePriorityNormal;
    [self.captureQueue addOperation:operation];
}
- (void)importRecentPaths:(NSArray<NSString*>*)paths {
    if (![self isEnabled]) return;
    @synchronized (self) {
        if (!self.captureQueue) { self.captureQueue=[NSOperationQueue new]; self.captureQueue.maxConcurrentOperationCount=1;
            self.captureQueue.qualityOfService=NSQualityOfServiceUtility; }
    }
    NSArray* snapshot=[paths copy];
    NSBlockOperation* scan=[NSBlockOperation blockOperationWithBlock:^{
        if (!self.isEnabled) return;
        NSMutableSet* known=[NSMutableSet set];
        for (NSDictionary* doc in self.documents) if ([doc[@"versions"] count]) [known addObject:doc[@"path"]];
        NSUInteger count=0;
        for (NSString* path in [NSOrderedSet orderedSetWithArray:snapshot]) {
            if (++count>1000) break;
            if ([known containsObject:SPDFCollectionPath(path)] || ![NSFileManager.defaultManager fileExistsAtPath:path]) continue;
            [self enqueueCapturePath:path reason:@"Imported recent document" continuingDocumentID:nil attempt:0 generation:[self advanceCaptureGenerationForPath:path] epoch:[self documentForPath:path][@"protectionEpoch"] ?: @"" completion:nil];
        }
    }];
    scan.queuePriority=NSOperationQueuePriorityVeryLow; [self.captureQueue addOperation:scan];
}
@end
