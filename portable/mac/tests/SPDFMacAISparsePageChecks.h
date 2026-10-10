#pragma once
#import "SPDFMacAIChatVision.h"
#import "SPDFMacAIChatStore.h"
#import "SPDFMacAITransport.h"
#import "SPDFMacAICitations.h"
static NSDictionary* SparseReadTool(NSString* path) {
    AIContextProbe* reader=[AIContextProbe new];
    reader.testCandidates=@[@{@"path":path,@"readPath":path,@"title":path.lastPathComponent,
        @"revision":SPDFSearchFileStamp(path)}];
    SPDFMacAITools* tools=[[SPDFMacAITools alloc] initWithReader:reader];
    Check([tools valueForKey:@"queue"]==nil && !reader.candidateCalls,"sparse preview feature remains inert until an explicit read");
    __block NSDictionary* result=nil;
    [tools performTool:@"read_pages" arguments:@{@"path":SPDFAIDocumentIdentifier(path),@"page":@1,@"count":@3}
        completion:^(NSDictionary* value){result=value;}];
    NSDate* deadline=[NSDate dateWithTimeIntervalSinceNow:10];
    while (!result && deadline.timeIntervalSinceNow>0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
    Check(result && !result[@"error"],"sparse document read completes"); return result;
}
static void CheckSparsePageRead(NSString* path, NSString* root) {
    NSDate* started=NSDate.date;
    NSDictionary* result=SparseReadTool(path);
    Check([result[@"visualPreviewPage"] isEqual:@1] && [result[@"sparseTextPages"] containsObject:@1],
        "a page with only a small amount of extractable text includes its visual evidence immediately");
    Check([result[@"textCoverage"] containsString:@"Extracted text only"],"read reports extraction limitations, not full visual coverage");
    NSDictionary* preview=result[@"_localPreview"];
    if ([NSProcessInfo.processInfo.environment[@"SPDF_SPARSE_READ_REPLAY"] isEqual:path]) {
        fprintf(stderr,"Reported document: %.0f ms read + preview; %lu sparse pages; visual page %lu\n",
            -started.timeIntervalSinceNow*1000,(unsigned long)[result[@"sparseTextPages"] count],
            (unsigned long)[result[@"visualPreviewPage"] unsignedIntegerValue]);
        [[NSData dataWithContentsOfFile:preview[@"path"]] writeToFile:@"/tmp/sz-sparse-read-replay.png" atomically:YES];
    }
    Check([preview[@"citation"][@"path"] hasPrefix:@"doc:"] && [preview[@"citation"][@"page"] isEqual:@1],
        "automatically supplied image retains the exact opaque page citation");
    Check([preview[@"pixelWidth"] unsignedIntegerValue]<=1600 && [preview[@"pixelHeight"] unsignedIntegerValue]<=1600,
        "automatic image uses the normal bounded full-page preview");
    NSString* identifier=NSUUID.UUID.UUIDString;
    SPDFMacAIChatStore* store=[[SPDFMacAIChatStore alloc] initWithDirectory:[NSURL fileURLWithPath:[root stringByAppendingPathComponent:identifier]]];
    NSDictionary* saved=[store savePreview:preview chatID:identifier];
    Check(saved!=nil,"read image survives chat asset persistence");
    NSMutableDictionary* publicResult=[result mutableCopy]; [publicResult removeObjectForKey:@"_localPreview"];
    NSString* text=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:publicResult options:0 error:nil] encoding:NSUTF8StringEncoding];
    NSArray* transcript=@[
        @{@"role":@"assistant",@"content":@"",@"tool_calls":@[@{@"id":@"read",@"type":@"function",
            @"function":@{@"name":@"read_pages",@"arguments":@"{}"}}]},
        @{@"role":@"preview",@"local":@YES,@"preview":saved,@"tool_call_id":@"read"},
        @{@"role":@"tool",@"tool_call_id":@"read",@"content":text}];
    NSArray* wire=SPDFMacAIChatVisionMessages(transcript,identifier,store,nil);
    NSURLRequest* request=SPDFMacAIChatRequest(wire,nil,@"test/vision",@"offline-test-key",nil);
    NSDictionary* body=[NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:nil];
    NSArray* messages=body[@"messages"]; NSUInteger images=0;
    for (NSDictionary* message in messages) if ([message[@"content"] isKindOfClass:NSArray.class])
        for (NSDictionary* part in message[@"content"]) if ([part[@"type"] isEqual:@"image_url"] &&
            [part[@"image_url"][@"url"] hasPrefix:@"data:image/png;base64,"]) images++;
    Check(images==1 && [messages[1][@"role"] isEqual:@"tool"],"read_pages delivers actual pixels after tool completion in the model HTTP request");
    Check(SPDFMacAIChatContainsCitation(@{@"messages":transcript},preview[@"citation"]),"preview citation can be used by an answer card or link");
}
static void CheckSparsePageBudgets(NSString* path) {
    NSDictionary* candidate=@{@"readPath":path,@"title":@"Sparse fixture"};
    NSString* link=[NSString stringWithFormat:@"spdf-ai://document?path=doc:fixture&page=1&revision=%@",SPDFSearchFileStamp(path)];
    NSMutableDictionary* result=[@{@"revision":SPDFSearchFileStamp(path),@"pages":@[
        @{@"page":@1,@"text":@"Title block",@"citation":link},@{@"page":@2,@"text":@""}]} mutableCopy];
    SPDFAISupplementSparsePageRead(result,candidate,[NSProgress progressWithTotalUnitCount:1]);
    Check([result[@"sparseTextPages"] count]==2 && [result[@"visualPreviewPage"] isEqual:@1],
        "multiple sparse pages attach only one image, with other pages explicitly reported");
    [SPDFMacAIChatStore discardTemporaryPreview:result[@"_localPreview"]];
    NSDictionary* nonexistent=@{@"readPath":@"/nonexistent/never-open.pdf"};
    NSMutableDictionary* dense=[@{@"pages":@[@{@"page":@1,@"text":[@"x" stringByPaddingToLength:200 withString:@"x" startingAtIndex:0]}]} mutableCopy];
    SPDFAISupplementSparsePageRead(dense,nonexistent,[NSProgress progressWithTotalUnitCount:1]);
    Check(!dense[@"_localPreview"] && !dense[@"image_error"] && !dense[@"sparseTextPages"],"ordinary dense reads do not attempt image rendering or file I/O");
    NSMutableDictionary* markdown=[@{@"pages":@[@{@"page":@1,@"text":@"short text"}]} mutableCopy];
    SPDFAISupplementSparsePageRead(markdown,@{@"readPath":@"/nonexistent/short.md"},[NSProgress progressWithTotalUnitCount:1]);
    Check(!markdown[@"textCoverage"] && !markdown[@"image_error"],"short text documents do not trigger fixed-layout previews");
    NSProgress* cancelled=[NSProgress progressWithTotalUnitCount:1]; [cancelled cancel];
    NSMutableDictionary* stopped=[markdown mutableCopy];
    SPDFAISupplementSparsePageRead(stopped,nonexistent,cancelled);
    Check([stopped isEqual:markdown],"cancelled read performs no supplemental work");
    NSMutableDictionary* missing=[markdown mutableCopy];
    SPDFAISupplementSparsePageRead(missing,nonexistent,[NSProgress progressWithTotalUnitCount:1]);
    Check(missing[@"image_error"] && !missing[@"_localPreview"],"unavailable pixels are reported without discarding extracted text");
}
