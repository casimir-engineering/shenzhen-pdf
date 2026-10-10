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
    NSArray* models=SPDFMacAIModelsFromCatalog(data,nil);
    if(models.count!=1 || ![models[0][@"id"] isEqual:@"deepseek/deepseek-v4.1-flash"]) return 6;
    NSData* malformed=[NSJSONSerialization dataWithJSONObject:@{@"data":@[@{@"id":@1},@{@"id":@"bad id",@"supported_parameters":@[@"tools"]}]} options:0 error:nil];
    if(SPDFMacAIModelsFromCatalog(malformed,nil).count) return 7;
    NSData* vision=[NSJSONSerialization dataWithJSONObject:@{@"data":@[
        @{@"id":@"fixture/vision",@"name":@"Vision",@"supported_parameters":@[@"tools"],
          @"architecture":@{@"input_modalities":@[@"text",@"image"]}},
        @{@"id":@"fixture/text",@"name":@"Text",@"supported_parameters":@[@"tools"],@"architecture":@"bad"}
    ]} options:0 error:nil];
    NSArray* choices=SPDFMacAIModelsFromCatalog(vision,nil);
    NSDictionary* visual=nil; NSDictionary* plain=nil;
    for(NSDictionary* choice in choices) {
        if([choice[@"id"] isEqual:@"fixture/vision"]) visual=choice;
        if([choice[@"id"] isEqual:@"fixture/text"]) plain=choice;
    }
    if(![visual[@"supportsImages"] boolValue] || ![visual[@"name"] isEqual:@"Vision · Images"] ||
        [plain[@"supportsImages"] boolValue] || ![plain[@"name"] isEqual:@"Text"]) return 8;
    puts("AI model catalog: passed"); return 0;
} }
