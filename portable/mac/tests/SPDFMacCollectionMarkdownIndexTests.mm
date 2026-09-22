#import <Foundation/Foundation.h>
#import "SPDFMacCollectionStore.h"
int main(void) {
    @autoreleasepool {
        if(!NSClassFromString(@"SPDFMarkdownDocument")) { fprintf(stderr,"FAIL Markdown engine must be linked\n"); return 1; }
        NSString* folder=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
        NSString* path=[folder stringByAppendingPathComponent:@"Paged.md"];
        NSString* text=@"---\npaper-size: A5\n---\n# First\nFirst page text.\n\n<!-- pagebreak -->\n\n# Second\nCanonical target phrase.\n";
        [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        SPDFMacCollectionStore* store=[[SPDFMacCollectionStore alloc] initWithRootURL:
            [NSURL fileURLWithPath:[folder stringByAppendingPathComponent:@"Collection"]]];
        [store updateSettings:@{@"choice":@"enabled"} error:nil];
        NSError* error; NSDictionary* doc=[store capturePath:path reason:@"Opened" error:&error];
        NSArray* matches=[store search:@"Canonical target" titlesOnly:NO excludingPaths:NSSet.set limit:5];
        BOOL ok=doc && matches.count==1 && [matches.firstObject[@"page"] integerValue]==2;
        if(!ok)fprintf(stderr,"FAIL archived Markdown canonical page mapping: %s\n",(error ?: matches).description.UTF8String);
        [NSFileManager.defaultManager removeItemAtPath:folder error:nil];
        if(ok)printf("SPDFMacCollectionMarkdownIndexTests passed\n"); return ok?0:1;
    }
}
