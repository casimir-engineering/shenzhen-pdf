#import "SPDFMacMarkdownCache.h"

#include <sys/stat.h>

NSString* spdf_mac_markdown_file_identity(NSString* path) {
    if (!path.length) return nil;
    struct stat info;
    if (lstat(path.fileSystemRepresentation, &info) != 0 || !S_ISREG(info.st_mode)) return nil;
    return [NSString stringWithFormat:@"%llu:%llu",
                                      (unsigned long long)info.st_dev,
                                      (unsigned long long)info.st_ino];
}

BOOL spdf_mac_markdown_cache_matches(NSDate* cachedModificationDate,
                                     unsigned long long cachedFileSize,
                                     NSString* cachedFileIdentity,
                                     NSDictionary<NSFileAttributeKey, id>* currentAttributes,
                                     NSString* currentFileIdentity) {
    if (!cachedModificationDate || !cachedFileIdentity.length || !currentAttributes ||
        !currentFileIdentity.length)
        return NO;
    NSDate* currentModificationDate = currentAttributes[NSFileModificationDate];
    unsigned long long currentFileSize = [currentAttributes[NSFileSize] unsignedLongLongValue];
    return currentModificationDate && [currentModificationDate isEqualToDate:cachedModificationDate] &&
           currentFileSize == cachedFileSize && [currentFileIdentity isEqualToString:cachedFileIdentity];
}
