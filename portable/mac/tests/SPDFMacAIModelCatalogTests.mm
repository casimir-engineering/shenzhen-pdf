#import <Foundation/Foundation.h>
#import "SPDFMacAIModelCatalog.h"
int main(void) { @autoreleasepool {
    NSDictionary* value=@{@"data":@[@{@"id":@"deepseek/deepseek-v4.1-flash",@"supported_parameters":@[@"tools"]},
        @{@"id":@"text-only",@"supported_parameters":@[]} ]};
    NSData* data=[NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    if (!SPDFMacAIModelFromCatalog(data,@"deepseek/deepseek-v4.1-flash",nil)) return 1;
    NSError* error=nil;
    if (SPDFMacAIModelFromCatalog(data,@"missing",&error) || !error) return 2;
    if (SPDFMacAIModelFromCatalog(data,@"text-only",nil)) return 3;
    if (SPDFMacAIModelFromCatalog([@"{}" dataUsingEncoding:NSUTF8StringEncoding],@"missing",nil)) return 4;
    if (SPDFMacAIModelFromCatalog([@"null" dataUsingEncoding:NSUTF8StringEncoding],@"missing",nil)) return 5;
    puts("AI model catalog: passed"); return 0;
} }
