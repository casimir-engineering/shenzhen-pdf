#import "SPDFMacAICitations.h"
NSDictionary* SPDFMacAICitationArguments(NSURL* URL) {
    if (![URL.scheme.lowercaseString isEqual:@"spdf-ai"] || ![URL.host isEqual:@"document"] ||
        URL.user || URL.password || URL.port || URL.fragment || URL.path.length) return nil;
    NSMutableDictionary* args=[NSMutableDictionary dictionary];
    for (NSURLQueryItem* item in [NSURLComponents componentsWithURL:URL resolvingAgainstBaseURL:NO].queryItems) {
        if (!item.value.length || args[item.name] || ![@[@"path",@"page",@"revision",@"layoutIdentity",@"query"] containsObject:item.name]) return nil;
        args[item.name]=item.value;
    }
    if (![args[@"path"] hasPrefix:@"doc:"] || ![args[@"revision"] length]) return nil;
    NSString* raw=args[@"page"]; if (!raw) return nil;
    NSScanner* scanner=[NSScanner scannerWithString:raw]; scanner.charactersToBeSkipped=nil;
    NSInteger page=0; if (![scanner scanInteger:&page] || !scanner.isAtEnd || page<1 || page>1000000) return nil;
    if ([args[@"query"] length]>512) return nil;
    args[@"page"]=@(page); return args;
}
static BOOL Contains(id value, NSDictionary* arguments, NSUInteger depth) {
    if (depth>20) return NO;
    if ([value isKindOfClass:NSDictionary.class]) {
        for (id key in value) {
            id item=value[key];
            if ([key isEqual:@"citation"] && [item isKindOfClass:NSString.class] &&
                [SPDFMacAICitationArguments([NSURL URLWithString:item]) isEqual:arguments]) return YES;
            if (Contains(item,arguments,depth+1)) return YES;
        }
    } else if ([value isKindOfClass:NSArray.class]) for (id item in value) if (Contains(item,arguments,depth+1)) return YES;
    return NO;
}
BOOL SPDFMacAIChatContainsCitation(NSDictionary* chat, NSDictionary* arguments) {
    if (!arguments) return NO;
    for (NSDictionary* message in chat[@"messages"]) {
        if ([message[@"role"] isEqual:@"preview"] && [message[@"local"] boolValue] &&
            [message[@"preview"][@"citation"] isEqual:arguments]) return YES;
        if (![message[@"role"] isEqual:@"tool"] || ![message[@"content"] isKindOfClass:NSString.class]) continue;
        NSData* data=[message[@"content"] dataUsingEncoding:NSUTF8StringEncoding];
        if (data.length>100000) continue;
        id result=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (Contains(result,arguments,0)) return YES;
    }
    return NO;
}
NSDictionary* SPDFMacAIResolveCitation(NSDictionary* chat, NSDictionary* arguments) {
    if (SPDFMacAIChatContainsCitation(chat,arguments)) return arguments;
    if (!arguments[@"query"]) return nil;
    // A model may append a made-up search query to a genuine page link. Never
    // navigate to that passage; recover only the independently retrieved page.
    NSMutableDictionary* page=[arguments mutableCopy]; [page removeObjectForKey:@"query"];
    return SPDFMacAIChatContainsCitation(chat,page) ? page : nil;
}
NSString* SPDFMacAIRepairCitationLinks(NSString* text, NSDictionary* chat) {
    if (![text containsString:@"spdf-ai://"]) return text;
    NSRegularExpression* links=[NSRegularExpression regularExpressionWithPattern:@"spdf-ai://document\\?[^\\s<>)]+"
        options:0 error:nil];
    NSMutableString* repaired=[text mutableCopy];
    NSArray* matches=[links matchesInString:text options:0 range:NSMakeRange(0,text.length)];
    for (NSTextCheckingResult* match in matches.reverseObjectEnumerator) {
        NSURLComponents* link=[NSURLComponents componentsWithString:[text substringWithRange:match.range]];
        NSDictionary* original=SPDFMacAICitationArguments(link.URL);
        NSDictionary* verified=SPDFMacAIResolveCitation(chat,original);
        if (!verified || [original isEqual:verified]) continue;
        NSMutableArray* items=[NSMutableArray array];
        for (NSURLQueryItem* item in link.queryItems) if (![item.name isEqual:@"query"]) [items addObject:item];
        link.queryItems=items;
        [repaired replaceCharactersInRange:match.range withString:link.string];
    }
    return repaired;
}
