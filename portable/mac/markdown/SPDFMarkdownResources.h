#pragma once

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// Holds a verified directory descriptor for one Markdown document and shares
// decoded images across every reference in a render.
@interface SPDFMarkdownResourceStore : NSObject

@property(nonatomic, readonly) NSUInteger loadedResourceBytes;
@property(nonatomic, readonly) NSUInteger decodedImagePixels;
@property(nonatomic, readonly) NSUInteger cachedResourceCount;

- (nullable instancetype)initWithDocumentURL:(NSURL*)documentURL;
- (nullable instancetype)initWithDocumentURL:(NSURL*)documentURL
                         maximumResourceBytes:(NSUInteger)maximumResourceBytes
                    maximumDecodedImagePixels:(NSUInteger)maximumDecodedImagePixels;
- (instancetype)init NS_UNAVAILABLE;

// Creates an independent cache with render-specific budgets while retaining
// the exact directory identity pinned by this store.
- (nullable SPDFMarkdownResourceStore*)storeWithMaximumResourceBytes:(NSUInteger)maximumResourceBytes
                                           maximumDecodedImagePixels:(NSUInteger)maximumDecodedImagePixels;

- (nullable NSData*)dataForTarget:(NSString*)target resolvedURL:(NSURL* _Nullable* _Nullable)resolvedURL;
- (nullable NSImage*)imageForTarget:(NSString*)target resolvedURL:(NSURL* _Nullable* _Nullable)resolvedURL;

@end

NS_ASSUME_NONNULL_END
