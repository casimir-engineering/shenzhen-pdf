#import "SPDFMacCollectionPreviewSearch.h"
#include <vector>
static NSString* Normalize(NSString* text, std::vector<NSRange>* mapping) {
    NSMutableString* result = [NSMutableString string];
    NSCharacterSet* whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    for (NSUInteger index=0;index<text.length;index++) {
        unichar character = [text characterAtIndex:index];
        if ([whitespace characterIsMember:character]) {
            if ([result hasSuffix:@" "]) {
                if (mapping) mapping->back().length = index+1-mapping->back().location;
                continue;
            }
            character = ' ';
        }
        [result appendString:[NSString stringWithCharacters:&character length:1]];
        if (mapping) mapping->push_back(NSMakeRange(index,1));
    }
    return result;
}
NSArray<NSValue*>* SPDFCollectionPreviewMatchRanges(NSString* text, NSString* query) {
    query = [Normalize(query,nil) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!text.length || !query.length) return @[];
    std::vector<NSRange> mapping;
    NSString* normalized = Normalize(text,&mapping);
    NSMutableArray* matches = [NSMutableArray array];
    NSRange remaining = NSMakeRange(0,normalized.length);
    while (remaining.length && matches.count<100) {
        NSRange match = [normalized rangeOfString:query options:(NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch)
            range:remaining];
        if (match.location==NSNotFound || !match.length) break;
        NSRange first = mapping[match.location], last = mapping[NSMaxRange(match)-1];
        [matches addObject:[NSValue valueWithRange:NSMakeRange(first.location,NSMaxRange(last)-first.location)]];
        remaining = NSMakeRange(NSMaxRange(match),normalized.length-NSMaxRange(match));
    }
    return matches;
}
