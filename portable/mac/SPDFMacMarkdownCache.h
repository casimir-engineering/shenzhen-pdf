#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSString* _Nullable spdf_mac_markdown_file_identity(NSString* path);
BOOL spdf_mac_markdown_cache_matches(NSDate* cachedModificationDate,
                                     unsigned long long cachedFileSize,
                                     NSString* _Nullable cachedFileIdentity,
                                     NSDictionary<NSFileAttributeKey, id>* currentAttributes,
                                     NSString* _Nullable currentFileIdentity);

NS_ASSUME_NONNULL_END
