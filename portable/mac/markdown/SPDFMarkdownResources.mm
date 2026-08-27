#import "SPDFMarkdownResources.h"

#import "SPDFMarkdownParser.h"

#import <ImageIO/ImageIO.h>

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <sys/stat.h>
#include <unistd.h>

static const NSUInteger SPDFMarkdownMaximumSingleResourceBytes = 64 * 1024 * 1024;

static BOOL SPDFContainsNullCharacter(NSString* value) {
    unichar nullCharacter = 0;
    NSString* needle = [NSString stringWithCharacters:&nullCharacter length:1];
    return [value rangeOfString:needle].location != NSNotFound;
}

static NSArray<NSString*>* SPDFLocalPathComponents(NSString* target) {
    NSString* decoded = [target stringByRemovingPercentEncoding] ?: target;
    NSURLComponents* URLParts = [NSURLComponents componentsWithString:decoded];
    if (!URLParts || URLParts.scheme.length || URLParts.host.length || URLParts.user.length ||
        URLParts.password.length || [decoded hasPrefix:@"//"] || [decoded hasPrefix:@"data:"]) {
        return nil;
    }
    NSString* path = [[decoded componentsSeparatedByString:@"#"] firstObject];
    if (path.length == 0 || [path hasPrefix:@"/"] || [path hasPrefix:@"~"] || [path containsString:@"?"]) {
        return nil;
    }
    NSMutableArray<NSString*>* components = [NSMutableArray array];
    for (NSString* component in path.pathComponents) {
        if ([component isEqualToString:@"."] || component.length == 0) continue;
        if ([component isEqualToString:@".."] || [component isEqualToString:@"~"] ||
            [component containsString:@"/"] || SPDFContainsNullCharacter(component)) {
            return nil;
        }
        [components addObject:component];
    }
    return components.count ? components : nil;
}

static BOOL SPDFSameFile(struct stat left, struct stat right) {
    return left.st_dev == right.st_dev && left.st_ino == right.st_ino;
}

static int SPDFOpenVerifiedDocumentRoot(NSURL* documentURL, NSString** rootPath) {
    if (!documentURL.isFileURL) return -1;
    int document = open(documentURL.fileSystemRepresentation, O_RDONLY | O_CLOEXEC);
    if (document < 0) return -1;
    struct stat documentInfo = {};
    char canonicalPath[PATH_MAX] = {};
    BOOL identified = fstat(document, &documentInfo) == 0 && S_ISREG(documentInfo.st_mode) &&
                      fcntl(document, F_GETPATH, canonicalPath) == 0;
    if (!identified) {
        close(document);
        return -1;
    }

    NSString* canonical = [NSFileManager.defaultManager stringWithFileSystemRepresentation:canonicalPath
                                                                                     length:strlen(canonicalPath)];
    NSString* directoryPath = canonical.stringByDeletingLastPathComponent;
    NSString* fileName = canonical.lastPathComponent;
    int directory = open(directoryPath.fileSystemRepresentation,
                         O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    int verified = directory >= 0
        ? openat(directory, fileName.fileSystemRepresentation, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        : -1;
    struct stat verifiedInfo = {};
    BOOL matches = verified >= 0 && fstat(verified, &verifiedInfo) == 0 &&
                   SPDFSameFile(documentInfo, verifiedInfo);
    if (verified >= 0) close(verified);
    close(document);
    if (!matches) {
        if (directory >= 0) close(directory);
        return -1;
    }
    if (rootPath) *rootPath = directoryPath;
    return directory;
}

static NSData* SPDFReadDescriptor(int fileDescriptor, NSUInteger maximumBytes) {
    struct stat info = {};
    NSUInteger limit = MIN(maximumBytes, SPDFMarkdownMaximumSingleResourceBytes);
    if (fstat(fileDescriptor, &info) != 0 || !S_ISREG(info.st_mode) || info.st_size < 0 ||
        (uint64_t)info.st_size > limit) {
        return nil;
    }
    NSMutableData* data = [NSMutableData dataWithCapacity:(NSUInteger)info.st_size];
    unsigned char buffer[64 * 1024];
    for (;;) {
        ssize_t count = read(fileDescriptor, buffer, sizeof(buffer));
        if (count == 0) return data;
        if (count < 0 && errno == EINTR) continue;
        if (count < 0 || data.length + (NSUInteger)count > limit) return nil;
        [data appendBytes:buffer length:(NSUInteger)count];
    }
}

@interface SPDFMarkdownCachedResource : NSObject
@property(nonatomic, nullable) NSData* data;
@property(nonatomic, nullable) NSImage* image;
@property(nonatomic, nullable) NSURL* resolvedURL;
@property(nonatomic) BOOL imageLoaded;
@end
@implementation SPDFMarkdownCachedResource
@end

@interface SPDFMarkdownResourceStore ()
- (instancetype)initWithRootDescriptor:(int)rootDescriptor
                               rootPath:(NSString*)rootPath
                   maximumResourceBytes:(NSUInteger)maximumResourceBytes
              maximumDecodedImagePixels:(NSUInteger)maximumDecodedImagePixels NS_DESIGNATED_INITIALIZER;
@end

@implementation SPDFMarkdownResourceStore {
    int _rootDescriptor;
    NSString* _rootPath;
    NSUInteger _maximumResourceBytes;
    NSUInteger _maximumDecodedImagePixels;
    NSMutableDictionary<NSString*, SPDFMarkdownCachedResource*>* _cache;
}

- (instancetype)initWithRootDescriptor:(int)rootDescriptor
                               rootPath:(NSString*)rootPath
                   maximumResourceBytes:(NSUInteger)maximumResourceBytes
              maximumDecodedImagePixels:(NSUInteger)maximumDecodedImagePixels {
    self = [super init];
    if (!self) {
        close(rootDescriptor);
        return nil;
    }
    _rootDescriptor = rootDescriptor;
    _rootPath = [rootPath copy];
    _maximumResourceBytes = maximumResourceBytes;
    _maximumDecodedImagePixels = maximumDecodedImagePixels;
    _cache = [NSMutableDictionary dictionary];
    return self;
}

- (instancetype)initWithDocumentURL:(NSURL*)documentURL {
    return [self initWithDocumentURL:documentURL
                maximumResourceBytes:64 * 1024 * 1024
           maximumDecodedImagePixels:32 * 1024 * 1024];
}

- (instancetype)initWithDocumentURL:(NSURL*)documentURL
                maximumResourceBytes:(NSUInteger)maximumResourceBytes
           maximumDecodedImagePixels:(NSUInteger)maximumDecodedImagePixels {
    NSString* rootPath = nil;
    int descriptor = SPDFOpenVerifiedDocumentRoot(documentURL, &rootPath);
    if (descriptor < 0) return nil;
    return [self initWithRootDescriptor:descriptor
                              rootPath:rootPath
                  maximumResourceBytes:maximumResourceBytes
             maximumDecodedImagePixels:maximumDecodedImagePixels];
}

- (void)dealloc {
    if (_rootDescriptor >= 0) close(_rootDescriptor);
}

- (NSUInteger)cachedResourceCount { return _cache.count; }

- (SPDFMarkdownResourceStore*)storeWithMaximumResourceBytes:(NSUInteger)maximumResourceBytes
                                  maximumDecodedImagePixels:(NSUInteger)maximumDecodedImagePixels {
    int descriptor = dup(_rootDescriptor);
    if (descriptor < 0) return nil;
    return [[SPDFMarkdownResourceStore alloc] initWithRootDescriptor:descriptor
                                                           rootPath:_rootPath
                                               maximumResourceBytes:maximumResourceBytes
                                          maximumDecodedImagePixels:maximumDecodedImagePixels];
}

- (NSString*)currentRootPath {
    char path[PATH_MAX] = {};
    if (fcntl(_rootDescriptor, F_GETPATH, path) != 0) return _rootPath;
    return [NSFileManager.defaultManager stringWithFileSystemRepresentation:path length:strlen(path)];
}

- (SPDFMarkdownCachedResource*)loadTarget:(NSString*)target {
    NSArray<NSString*>* components = SPDFLocalPathComponents(target);
    if (!components.count) return nil;
    NSString* key = [components componentsJoinedByString:@"/"];
    SPDFMarkdownCachedResource* cached = _cache[key];
    if (cached) return cached;

    cached = [SPDFMarkdownCachedResource new];
    _cache[key] = cached;  // Failed resources are cached too.
    int descriptor = dup(_rootDescriptor);
    if (descriptor < 0) return cached;
    for (NSUInteger index = 0; index < components.count; ++index) {
        BOOL final = index + 1 == components.count;
        int flags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW | (final ? O_NONBLOCK : O_DIRECTORY);
        int next = openat(descriptor, components[index].fileSystemRepresentation, flags);
        close(descriptor);
        descriptor = next;
        if (descriptor < 0) return cached;
    }
    NSUInteger remaining = _loadedResourceBytes < _maximumResourceBytes
        ? _maximumResourceBytes - _loadedResourceBytes : 0;
    NSData* data = SPDFReadDescriptor(descriptor, remaining);
    close(descriptor);
    if (!data) return cached;
    cached.data = data;
    _loadedResourceBytes += data.length;
    NSURL* URL = [NSURL fileURLWithPath:self.currentRootPath isDirectory:YES];
    for (NSString* component in components) URL = [URL URLByAppendingPathComponent:component];
    cached.resolvedURL = URL;
    return cached;
}

- (NSData*)dataForTarget:(NSString*)target resolvedURL:(NSURL**)resolvedURL {
    if (resolvedURL) *resolvedURL = nil;
    SPDFMarkdownCachedResource* resource = [self loadTarget:target];
    if (resolvedURL) *resolvedURL = resource.resolvedURL;
    return resource.data;
}

- (NSImage*)imageForTarget:(NSString*)target resolvedURL:(NSURL**)resolvedURL {
    if (resolvedURL) *resolvedURL = nil;
    SPDFMarkdownCachedResource* resource = [self loadTarget:target];
    if (resolvedURL) *resolvedURL = resource.resolvedURL;
    if (!resource || resource.imageLoaded) return resource.image;
    resource.imageLoaded = YES;
    if (!resource.data) return nil;

    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)resource.data, NULL);
    CFDictionaryRef rawProperties = source ? CGImageSourceCopyPropertiesAtIndex(source, 0, NULL) : NULL;
    NSDictionary* properties = CFBridgingRelease(rawProperties);
    uint64_t width = [properties[(NSString*)kCGImagePropertyPixelWidth] unsignedLongLongValue];
    uint64_t height = [properties[(NSString*)kCGImagePropertyPixelHeight] unsignedLongLongValue];
    uint64_t pixels = width && height <= UINT64_MAX / width ? width * height : UINT64_MAX;
    NSUInteger remaining = _decodedImagePixels < _maximumDecodedImagePixels
        ? _maximumDecodedImagePixels - _decodedImagePixels : 0;
    if (!source || !width || !height || pixels > remaining) {
        if (source) CFRelease(source);
        resource.data = nil;
        return nil;
    }
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    if (image) {
        resource.image = [[NSImage alloc] initWithCGImage:image size:NSMakeSize(width, height)];
        CGImageRelease(image);
        _decodedImagePixels += (NSUInteger)pixels;
    }
    resource.data = nil;
    return resource.image;
}

@end

@implementation SPDFMarkdownParser (Resources)
+ (NSData*)localResourceDataForTarget:(NSString*)target
                relativeToDocumentURL:(NSURL*)documentURL
                             resolvedURL:(NSURL**)resolvedURL {
    SPDFMarkdownResourceStore* store = [[SPDFMarkdownResourceStore alloc] initWithDocumentURL:documentURL];
    return [store dataForTarget:target resolvedURL:resolvedURL];
}
@end
