#import "SPDFMacCollectionStorePrivate.h"

@implementation SPDFMacCollectionStore (Location)
- (BOOL)relocateToURL:(NSURL*)URL error:(NSError**)error {
    URL=URL.URLByStandardizingPath;
    NSURL* old=self.rootURL;
    NSString* destination=URL.path.stringByResolvingSymlinksInPath;
    NSString* source=old.path.stringByResolvingSymlinksInPath;
    if ([destination isEqual:source]) return YES;
    if ([destination hasPrefix:[source stringByAppendingString:@"/"]] ||
        [source hasPrefix:[destination stringByAppendingString:@"/"]]) {
        if(error)*error=SPDFCollectionError(15,@"Choose a separate, empty Collection folder."); return NO;
    }
    NSArray* existing=[NSFileManager.defaultManager contentsOfDirectoryAtPath:URL.path error:nil];
    if (existing.count) { if(error)*error=SPDFCollectionError(15,@"The new Collection folder must be empty."); return NO; }
    return [self transaction:^BOOL(NSMutableDictionary* manifest,NSError** e) {
        NSURL* active=self.rootURL;
        if (![active isEqual:old]) { if(e)*e=SPDFCollectionError(16,@"Another window moved Collection. Retry from its new location."); return NO; }
        if (!SPDFCollectionMakeDirectory(URL,e)) return NO;
        // Source lock prevents captures and deletion until every destination byte and manifest is durable.
        NSDirectoryEnumerator* enumerator=[NSFileManager.defaultManager enumeratorAtURL:old
             includingPropertiesForKeys:@[NSURLIsDirectoryKey,NSURLIsSymbolicLinkKey] options:0 errorHandler:nil];
        for (NSURL* item in enumerator) {
            NSString* relative=[item.path.stringByResolvingSymlinksInPath substringFromIndex:old.path.stringByResolvingSymlinksInPath.length+1];
            if ([relative isEqual:@"collection.lock"] || [relative isEqual:@"redirect.json"] ||
                [relative isEqual:@"manifest.json"]) continue;
            NSDictionary* values=[item resourceValuesForKeys:@[NSURLIsDirectoryKey,NSURLIsSymbolicLinkKey] error:e];
            if ([values[NSURLIsSymbolicLinkKey] boolValue]) { [enumerator skipDescendants]; continue; }
            NSURL* target=[URL URLByAppendingPathComponent:relative];
            if ([values[NSURLIsDirectoryKey] boolValue]) { if(!SPDFCollectionMakeDirectory(target,e))return NO; continue; }
            NSData* bytes=[NSData dataWithContentsOfURL:item options:0 error:e];
            if (!bytes || !SPDFCollectionMakeDirectory(target.URLByDeletingLastPathComponent,e) ||
                !SPDFCollectionAtomicData(bytes,target,0400,e)) return NO;
            if (![SPDFCollectionHashURL(item,e) isEqual:SPDFCollectionHashURL(target,e)]) {
                if(e)*e=SPDFCollectionError(3,@"Collection move failed integrity verification; original storage is unchanged."); return NO;
            }
        }
        NSData* manifestBytes=[NSJSONSerialization dataWithJSONObject:manifest options:0 error:e];
        if (!manifestBytes || !SPDFCollectionAtomicData(manifestBytes,[URL URLByAppendingPathComponent:@"manifest.json"],0600,e)) return NO;
        NSData* redirect=[NSJSONSerialization dataWithJSONObject:@{@"path":URL.path} options:0 error:e];
        if (!redirect || !SPDFCollectionAtomicData(redirect,[old URLByAppendingPathComponent:@"redirect.json"],0600,e)) return NO;
        // Legacy preview session paths continue resolving to the moved, immutable preview tree.
        NSURL* previews=[old URLByAppendingPathComponent:@"previews"];
        [NSFileManager.defaultManager removeItemAtURL:previews error:nil];
        [NSFileManager.defaultManager createSymbolicLinkAtURL:previews withDestinationURL:
            [URL URLByAppendingPathComponent:@"previews"] error:nil];
        [NSFileManager.defaultManager removeItemAtURL:[old URLByAppendingPathComponent:@"objects"] error:nil];
        [NSFileManager.defaultManager removeItemAtURL:[old URLByAppendingPathComponent:@"manifest.json"] error:nil];
        return YES;
    } error:error];
}
@end
