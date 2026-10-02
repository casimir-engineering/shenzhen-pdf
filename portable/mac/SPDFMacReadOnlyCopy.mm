#import "SPDFMacReadOnlyCopy.h"
#import <os/log.h>

SPDFReadOnlyCopyResolution SPDFResolveReadOnlyCopy(NSString* sourcePath, NSString* copyPath,
    NSDictionary* existingBinding, void (^authorizeRead)(void)) {
    SPDFReadOnlyCopyResolution result = {sourcePath, 0, nil, NO, nil};
    NSDictionary* source = SPDFReadOnlyFileFingerprint(sourcePath);
    if (SPDFReadOnlyCopyBindingMatches(existingBinding, sourcePath, copyPath)) {
        result.fingerprintBinding = existingBinding;
        source = existingBinding[@"source"];
    } else {
        // A legacy size/date-only binding is not proof of source identity. Renew
        // lazily when the reader actually resolves this tab, never at restore.
        if (authorizeRead) authorizeRead();
        source = SPDFReadOnlyFileFingerprint(sourcePath);
        NSError* error = nil;
        NSData* bytes = [NSData dataWithContentsOfFile:sourcePath options:0 error:&error];
        if (!bytes || !source.count || ![source isEqual:SPDFReadOnlyFileFingerprint(sourcePath)] ||
            bytes.length != [source[@"size"] unsignedLongLongValue]) return result;
        // Write fresh bytes, not copyItem: inherited restricted provenance/xattrs
        // would make the private render copy prompt for source access again.
        [NSFileManager.defaultManager removeItemAtPath:copyPath error:nil];
        if (![bytes writeToFile:copyPath options:NSDataWritingAtomic error:&error]) {
            os_log_error(OS_LOG_DEFAULT, "read-only copy write failed: %{public}@", error.localizedDescription);
            return result;
        }
        NSDictionary* copy = SPDFReadOnlyFileFingerprint(copyPath);
        if (!copy.count || ![source isEqual:SPDFReadOnlyFileFingerprint(sourcePath)] ||
            ![source[@"size"] isEqual:copy[@"size"]]) return result;
        result.fingerprintBinding = @{@"source":source, @"copy":copy};
    }
    result.workingPath = copyPath;
    result.fileSize = [source[@"size"] unsignedLongLongValue];
    result.modificationDate = [NSDate dateWithTimeIntervalSince1970:
        [source[@"mtime"] doubleValue] + [source[@"mtimeNS"] doubleValue]/1e9];
    result.hasCopyBinding = YES;
    return result;
}
