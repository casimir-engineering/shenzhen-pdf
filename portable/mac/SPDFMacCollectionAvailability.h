#pragma once
#import <Foundation/Foundation.h>
// A historical path can exist again while belonging to an unrelated document.
// Availability follows Collection identity, not just the filesystem entry.
static inline BOOL SPDFCollectionOriginalAvailable(NSDictionary* document) {
    NSString* path = document[@"path"];
    return path.length && ![document[@"sourceReplaced"] boolValue] &&
        ![document[@"originalUnavailable"] boolValue] && [NSFileManager.defaultManager fileExistsAtPath:path];
}
