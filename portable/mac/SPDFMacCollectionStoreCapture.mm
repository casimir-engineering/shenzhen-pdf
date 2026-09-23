#import "SPDFMacCollectionStorePrivate.h"
#import <PDFKit/PDFKit.h>

static BOOL SameSource(struct stat a, struct stat b) {
    return a.st_dev==b.st_dev && a.st_ino==b.st_ino && a.st_size==b.st_size &&
           a.st_mtimespec.tv_sec==b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec==b.st_mtimespec.tv_nsec &&
           a.st_ctimespec.tv_sec==b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec==b.st_ctimespec.tv_nsec;
}
static NSString* BytesHash(NSData* bytes) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(bytes.bytes,(CC_LONG)bytes.length,digest);
    NSMutableString* hash = [NSMutableString string];
    for (int i=0;i<CC_SHA256_DIGEST_LENGTH;++i) [hash appendFormat:@"%02x",digest[i]];
    return hash;
}
static BOOL DefinitivelyMissing(NSString* path) {
    if (!path.length) return NO;
    struct stat info = {};
    // Permission failures and existing symlinks must not be mistaken for a lost original.
    if (lstat(path.fileSystemRepresentation,&info)==0) return NO;
    return errno==ENOENT || errno==ENOTDIR;
}
static NSMutableDictionary* UniqueLostHistory(NSDictionary* rows, NSString* hash) {
    NSMutableDictionary* match=nil;
    for (NSMutableDictionary* row in rows.allValues) {
        BOOL known=NO;
        for (NSDictionary* version in row[@"versions"])
            if ([version[@"hash"] isEqual:hash]) { known=YES; break; }
        if (!known || !DefinitivelyMissing(row[@"path"])) continue;
        // Equal bytes cannot establish which of two lost documents was opened.
        if (match) return nil;
        match=row;
    }
    return [match[@"excluded"] boolValue] ? nil : match;
}
static BOOL RelinkSourceStillMissing(NSString* path, NSError** error) {
    if (!path || DefinitivelyMissing(path)) return YES;
    if (error) *error=SPDFCollectionError(5,@"The original reappeared while linking its history. Retrying the opened document.");
    return NO;
}
static NSDictionary* TextIndex(NSData* data, NSString* path, NSArray* assets, NSURL* root) {
    NSString* extension=path.pathExtension.lowercaseString;
    NSMutableArray* pages = [NSMutableArray array]; BOOL encrypted = NO;
    if ([extension isEqual:@"pdf"]) {
        PDFDocument* pdf = [[PDFDocument alloc] initWithData:data]; encrypted = pdf.isEncrypted;
        // An authenticated UI document must not leak decrypted text into its archive index.
        if (!encrypted) {
            NSUInteger chars = 0;
            for (NSUInteger i=0;i<MIN(pdf.pageCount,2000UL) && chars<2*1024*1024;++i) {
                NSString* text = [pdf pageAtIndex:i].string ?: @"";
                if (text.length > 65536) text = [text substringToIndex:65536];
                if (text.length) [pages addObject:@{@"page":@(i+1),@"text":text}]; chars += text.length;
            }
        }
    } else if ([@[@"md",@"markdown",@"mdown"] containsObject:extension]) {
        [pages addObjectsFromArray:SPDFCollectionMarkdownTextPages(data,path,assets,root)];
    } else if ([extension isEqual:@"txt"]) {
        NSString* text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (text.length > 2*1024*1024) text = [text substringToIndex:2*1024*1024];
        if (text.length) [pages addObject:@{@"page":@0,@"text":text}];
    }
    return @{@"textPages":pages,@"encrypted":@(encrypted)};
}
@implementation SPDFMacCollectionStore (Capture)
- (NSDictionary*)captureLockedPath:(NSString*)path reason:(NSString*)reason
               continuingDocumentID:(NSString*)documentID manifest:(NSMutableDictionary*)manifest error:(NSError**)error {
    if (![manifest[@"settings"][@"choice"] isEqual:@"enabled"]) return nil;
    NSMutableDictionary* rows = manifest[@"documents"]; NSMutableDictionary* doc;
    for (NSMutableDictionary* row in rows.allValues)
        if ([row[@"path"] isEqual:path] && ![row[@"sourceReplaced"] boolValue]) { doc = row; break; }
    if (![self captureEpochIsCurrentForPath:path document:doc]) return nil;
    if ([doc[@"excluded"] boolValue]) return nil;
    if ((!documentID.length || [doc[@"id"] isEqual:documentID]) && [self canReuseProtection:doc path:path]) {
        [self recordCaptureUserOpenInDocument:doc path:path]; return doc;
    }
    NSData* bytes; struct stat before = {}, after = {}; BOOL stable = NO;
    for (NSUInteger retry=0; retry<3; ++retry) {
        if (stat(path.fileSystemRepresentation,&before) != 0 || !S_ISREG(before.st_mode)) break;
        if (before.st_size > 512LL*1024*1024) {
            if (error) *error = SPDFCollectionError(4,@"Document exceeds the 512 MB snapshot limit; reading is available.");
            return nil;
        }
        bytes = [NSData dataWithContentsOfFile:path options:0 error:error];
        stable = bytes && stat(path.fileSystemRepresentation,&after)==0 && SameSource(before,after) &&
                 bytes.length == (NSUInteger)after.st_size;
        if (stable) break;
    }
    if (!stable) {
        if (error && !*error) *error = SPDFCollectionError(5,@"Source is unavailable or changed during capture. Retry after saving finishes.");
        return nil;
    }
    NSString* identity = [NSString stringWithFormat:@"%llu:%llu",(unsigned long long)after.st_dev,
                          (unsigned long long)after.st_ino];
    if (documentID.length && (![doc[@"id"] isEqual:documentID] || [doc[@"sourceReplaced"] boolValue])) {
        if(error)*error=SPDFCollectionError(19,@"Document continuity no longer matches this source. Reopen the current document."); return nil;
    }
    if (doc[@"fileIdentity"] && ![doc[@"fileIdentity"] isEqual:identity] && !documentID.length) {
        doc[@"sourceReplaced"]=@YES; doc[@"originalUnavailable"]=@YES; doc[@"status"]=@"Original replaced";
        doc=nil;
    }
    // A verified move retains its identity; same bytes at two existing paths remain separate entries.
    if (!doc) for (NSMutableDictionary* row in rows.allValues) {
        if (![row[@"sourceReplaced"] boolValue] && [row[@"fileIdentity"] isEqual:identity] &&
            ![NSFileManager.defaultManager fileExistsAtPath:row[@"path"]]) { doc=row; break; }
    }
    if ([doc[@"excluded"] boolValue]) return nil;
    NSString* hash = BytesHash(bytes);
    NSString* relinkedSource=nil;
    if (!doc) {
        // The normal capture already read stable bytes on its background worker.
        // Reuse history only when those bytes identify exactly one lost source.
        doc=UniqueLostHistory(rows,hash);
        relinkedSource=doc[@"path"];
    }
    NSDictionary* dependencies = SPDFCollectionAssets(path,bytes);
    NSDictionary* capturedSource=SPDFCollectionFingerprintFromStat(&after);
    NSMutableDictionary* capturedDependencies=[NSMutableDictionary dictionary];
    NSMutableArray* assets = [NSMutableArray array];
    for (NSDictionary* asset in dependencies[@"entries"]) {
        capturedDependencies[asset[@"relativePath"]]=asset[@"captureFingerprint"];
        NSMutableDictionary* metadata = [asset mutableCopy]; [metadata removeObjectForKey:@"data"]; [metadata removeObjectForKey:@"captureFingerprint"]; [assets addObject:metadata];
    }
    NSDictionary* last = [doc[@"versions"] lastObject];
    if ([last[@"hash"] isEqual:hash] && [last[@"assets"] isEqual:assets] &&
        [last[@"assetWarnings"] isEqual:dependencies[@"warnings"]]) {
        // A manifest entry alone is not evidence of durable protection after disk damage.
        if (![[SPDFCollectionHashURL([self blobURL:hash],error) lowercaseString] isEqual:hash]) {
            if(error && !*error)*error=SPDFCollectionError(3,@"A retained snapshot failed its integrity check."); return nil;
        }
        for (NSDictionary* asset in assets)
            if (![SPDFCollectionHashURL([self blobURL:asset[@"hash"]],error) isEqual:asset[@"hash"]]) {
                if(error && !*error)*error=SPDFCollectionError(3,@"A retained asset failed its integrity check."); return nil;
            }
        if (!RelinkSourceStillMissing(relinkedSource,error)) return nil;
        NSMutableArray* aliases=[doc[@"aliases"] mutableCopy] ?: [NSMutableArray array];
        if (doc[@"path"] && ![aliases containsObject:doc[@"path"]]) [aliases addObject:doc[@"path"]];
        if (![aliases containsObject:path]) [aliases addObject:path];
        doc[@"aliases"]=aliases; doc[@"path"]=path; doc[@"title"]=path.lastPathComponent;
        doc[@"fileIdentity"]=identity;
        [doc removeObjectForKey:@"sourceReplaced"]; [doc removeObjectForKey:@"originalUnavailable"];
        doc[@"status"] = @"Protected"; [doc removeObjectForKey:@"captureError"];
        [self recordFingerprints:doc source:capturedSource dependencies:capturedDependencies];
        [self recordCaptureUserOpenInDocument:doc path:path]; return doc;
    }
    if (![self installBytes:bytes hash:hash error:error]) return nil;
    for (NSDictionary* asset in dependencies[@"entries"])
        if (![self installBytes:asset[@"data"] hash:asset[@"hash"] error:error]) return nil;
    // Recheck after writing assets: an edit gate may only protect the source revision it is about to overwrite.
    struct stat final = {};
    if (stat(path.fileSystemRepresentation,&final)!=0 || !SameSource(after,final)) {
        if (error) *error = SPDFCollectionError(5,@"Source changed while committing its snapshot; retry capture."); return nil;
    }
    NSDictionary* index = TextIndex(bytes,path,dependencies[@"entries"],self.rootURL);
    if (stat(path.fileSystemRepresentation,&final)!=0 || !SameSource(after,final)) {
        if(error)*error=SPDFCollectionError(5,@"Source changed during indexing; retry capture."); return nil;
    }
    for (NSDictionary* asset in dependencies[@"entries"]) {
        NSString* assetPath=[path.stringByDeletingLastPathComponent stringByAppendingPathComponent:asset[@"relativePath"]];
        if (![SPDFCollectionFingerprint(assetPath) isEqual:asset[@"captureFingerprint"]]) {
            if(error)*error=SPDFCollectionError(5,@"A linked asset changed during capture; retry after saving finishes."); return nil;
        }
    }
    NSNumber* now = @(NSDate.date.timeIntervalSince1970);
    NSMutableDictionary* version = [@{@"id":NSUUID.UUID.UUIDString,@"hash":hash,@"size":@(bytes.length),
        @"filename":path.lastPathComponent,@"capturedAt":now,@"modifiedAt":@((double)after.st_mtimespec.tv_sec+after.st_mtimespec.tv_nsec/1e9),
        @"reason":reason ?: @"Opened",@"keep":@NO,@"assets":assets,@"assetWarnings":dependencies[@"warnings"]} mutableCopy];
    version[@"encrypted"]=index[@"encrypted"];
    if (![index[@"encrypted"] boolValue]) {
        NSData* indexBytes=[NSJSONSerialization dataWithJSONObject:index options:0 error:error];
        NSString* indexFile=[version[@"id"] stringByAppendingPathExtension:@"json"];
        NSURL* indexURL=[[self.rootURL URLByAppendingPathComponent:@"indexes"] URLByAppendingPathComponent:indexFile];
        if (!indexBytes || !SPDFCollectionMakeDirectory(indexURL.URLByDeletingLastPathComponent,error) ||
            !SPDFCollectionAtomicData(indexBytes,indexURL,0400,error)) return nil;
        version[@"indexFile"]=indexFile;
    }
    if (!RelinkSourceStillMissing(relinkedSource,error)) return nil;
    if (!doc) {
        doc = [@{@"id":NSUUID.UUID.UUIDString,@"path":path,@"aliases":[NSMutableArray array],
                 @"versions":[NSMutableArray array],@"excluded":@NO} mutableCopy]; rows[doc[@"id"]]=doc;
    }
    NSMutableArray* aliases = [doc[@"aliases"] mutableCopy] ?: [NSMutableArray array];
    if (doc[@"path"] && ![aliases containsObject:doc[@"path"]]) [aliases addObject:doc[@"path"]];
    if (![aliases containsObject:path]) [aliases addObject:path];
    doc[@"aliases"]=aliases; doc[@"path"]=path; doc[@"title"]=path.lastPathComponent; doc[@"fileIdentity"]=identity;
    NSMutableArray* versions = [doc[@"versions"] mutableCopy]; [versions addObject:version]; doc[@"versions"]=versions;
    doc[@"latestVersionID"]=version[@"id"]; doc[@"capturedAt"]=now; doc[@"status"]=@"Protected";
    [doc removeObjectForKey:@"sourceReplaced"]; [doc removeObjectForKey:@"originalUnavailable"];
    [doc removeObjectForKey:@"captureError"]; [self recordFingerprints:doc source:capturedSource dependencies:capturedDependencies];
    [self recordCaptureUserOpenInDocument:doc path:path];
    if (![self enforceStorageLimitInManifest:manifest protectedVersionID:version[@"id"] error:error]) return nil;
    if (![capturedSource isEqual:SPDFCollectionFingerprint(path)]) {
        if(error)*error=SPDFCollectionError(5,@"Source changed before committing its snapshot; retry capture."); return nil;
    }
    return doc;
}
- (NSDictionary*)capturePath:(NSString*)path reason:(NSString*)reason error:(NSError**)error {
    return [self capturePath:path reason:reason continuingDocumentID:nil error:error];
}
- (NSDictionary*)capturePath:(NSString*)path reason:(NSString*)reason
       continuingDocumentID:(NSString*)documentID error:(NSError**)error {
    path = SPDFCollectionPath(path);
    if (![self captureRequestIsCurrentForPath:path]) return nil;
    if (![self isEnabled] || [self isArchivePath:path] || [[self documentForPath:path][@"excluded"] boolValue]) return nil;
    NSDictionary* existing=[self documentForPath:path];
    if (![self captureEpochIsCurrentForPath:path document:existing]) return nil;
    if (![self captureUserOpenCountForPath:path] && (!documentID.length || [existing[@"id"] isEqual:documentID]) &&
        [self canReuseProtection:existing path:path]) return existing;
    __block NSDictionary* result; NSError* failure;
    BOOL ok = [self transaction:^BOOL(NSMutableDictionary* m,NSError** e) {
        if (![self captureRequestIsCurrentForPath:path]) return NO;
        result = [self captureLockedPath:path reason:reason continuingDocumentID:documentID manifest:m error:e]; return result != nil;
    } error:&failure];
    if (ok) [self markCaptureUserOpenRecordedForPath:path];
    if (ok && ![result[@"sourceFingerprint"] isEqual:SPDFCollectionFingerprint(path)]) {
        ok=NO;
        failure=[NSError errorWithDomain:@"SPDFCollection" code:5 userInfo:@{
            NSLocalizedDescriptionKey:@"Source changed before capture completed; retrying its newer revision.",
            @"continuingDocumentID":result[@"id"]}];
    }
    if (!ok && failure && !([failure.domain isEqual:@"SPDFCollection"] && failure.code==19)) {
        [self transaction:^BOOL(NSMutableDictionary* m,NSError** e) {
            (void)e;
            NSMutableDictionary* row;
            for (NSMutableDictionary* d in [m[@"documents"] allValues]) if ([d[@"path"] isEqual:path] && ![d[@"sourceReplaced"] boolValue]) { row=d; break; }
            struct stat current={}; NSString* currentIdentity=nil;
            if(stat(path.fileSystemRepresentation,&current)==0)
                currentIdentity=[NSString stringWithFormat:@"%llu:%llu",(unsigned long long)current.st_dev,(unsigned long long)current.st_ino];
            if (!documentID.length && !failure.userInfo[@"continuingDocumentID"] && currentIdentity &&
                row[@"fileIdentity"] && ![row[@"fileIdentity"] isEqual:currentIdentity]) {
                row[@"sourceReplaced"]=@YES; row[@"originalUnavailable"]=@YES; row[@"status"]=@"Original replaced"; row=nil;
            }
            if (!row) {
                row=[@{@"id":NSUUID.UUID.UUIDString,@"path":path,@"title":path.lastPathComponent,
                       @"aliases":@[path],@"versions":@[]} mutableCopy]; m[@"documents"][row[@"id"]]=row;
                if(currentIdentity)row[@"fileIdentity"]=currentIdentity;
            }
            row[@"status"]=@"Capture failed"; row[@"captureError"]=failure.localizedDescription;
            // Discard failed, unpublished capture bytes only after old references
            // are durably preserved. This never prunes a retained revision.
            m[@"_collectUnreferencedFiles"]=@YES; return YES;
        } error:nil];
    }
    if (error) *error=failure; return ok ? result : nil;
}
- (BOOL)ensureProtectedPath:(NSString*)path reason:(NSString*)reason error:(NSError**)error {
    return [self ensureProtectedPath:path reason:reason continuingDocumentID:nil error:error];
}
- (BOOL)ensureProtectedPath:(NSString*)path reason:(NSString*)reason
     continuingDocumentID:(NSString*)documentID error:(NSError**)error {
    if ([self isArchivePath:path]) {
        if (error) *error=SPDFCollectionError(7,@"Archived versions are read-only. Save a Copy to edit."); return NO;
    }
    if (![self isEnabled] || [[self documentForPath:path][@"excluded"] boolValue]) return YES;
    [self advanceCaptureGenerationForPath:path];
    NSDictionary* protectedDocument=[self capturePath:path reason:reason continuingDocumentID:documentID error:error];
    if (!protectedDocument) return NO;
    // This durable epoch invalidates older jobs in every window/process before
    // the source write is allowed to begin, including a reused protected copy.
    return [self transaction:^BOOL(NSMutableDictionary* manifest,NSError** failure) {
        NSMutableDictionary* current=manifest[@"documents"][protectedDocument[@"id"]];
        if ([current[@"sourceReplaced"] boolValue] ||
            ![current[@"sourceFingerprint"] isEqual:SPDFCollectionFingerprint(path)]) {
            if (failure) *failure=SPDFCollectionError(5,@"Source changed before edit protection completed. Retry.");
            return NO;
        }
        current[@"protectionEpoch"]=NSUUID.UUID.UUIDString;
        return YES;
    } error:error];
}
@end
