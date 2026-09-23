#import "SPDFMacCollectionStore.h"
#import <CommonCrypto/CommonDigest.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSDictionary* SPDFCollectionFingerprint(NSString* path);
FOUNDATION_EXPORT NSDictionary* SPDFCollectionFingerprintFromStat(const struct stat* value);
FOUNDATION_EXPORT NSError* SPDFCollectionError(NSInteger code, NSString* message);
FOUNDATION_EXPORT NSString* SPDFCollectionPath(NSString* path);
FOUNDATION_EXPORT NSString* _Nullable SPDFCollectionHashURL(NSURL* URL, NSError** error);
FOUNDATION_EXPORT BOOL SPDFCollectionAtomicData(NSData* data, NSURL* URL, mode_t mode, NSError** error);
FOUNDATION_EXPORT BOOL SPDFCollectionMakeDirectory(NSURL* URL, NSError** error);
FOUNDATION_EXPORT NSArray* SPDFCollectionMarkdownTextPages(NSData* bytes, NSString* path, NSArray* assets, NSURL* root);
FOUNDATION_EXPORT NSDictionary* SPDFCollectionAssets(NSString* sourcePath, NSData* bytes);
@interface SPDFMacCollectionStore ()
@property(nonatomic, readwrite) NSURL* rootURL;
@property(nonatomic) NSRecursiveLock* localLock;
@property(nonatomic) NSURL* originalRootURL;
@property(nonatomic) NSOperationQueue* captureQueue;
@property(nonatomic) NSMutableDictionary<NSString*, NSNumber*>* captureGenerations;
- (NSMutableDictionary*)readManifest;

- (BOOL)transaction:(BOOL (^)(NSMutableDictionary*, NSError**))body error:(NSError**)error;
- (NSDictionary*)versionID:(NSString*)versionID document:(NSDictionary*)document;
- (NSURL*)blobURL:(NSString*)hash;
- (NSDictionary*)textIndexForVersion:(NSDictionary*)version;
- (BOOL)installBytes:(NSData*)data hash:(NSString*)hash error:(NSError**)error;
@end
@interface SPDFMacCollectionStore (Fingerprint)
- (BOOL)canReuseProtection:(NSDictionary*)doc path:(NSString*)path;
- (void)recordFingerprints:(NSMutableDictionary*)doc source:(NSDictionary*)source dependencies:(NSDictionary*)dependencies;
@end
@interface SPDFMacCollectionStore (CapturePrivate)
- (NSNumber*)advanceCaptureGenerationForPath:(NSString*)path;
- (BOOL)captureRequestIsCurrentForPath:(NSString*)path;
- (BOOL)captureEpochIsCurrentForPath:(NSString*)path document:(nullable NSDictionary*)document;
- (void)enqueueCapturePath:(NSString*)path reason:(NSString*)reason continuingDocumentID:(nullable NSString*)documentID
                  attempt:(NSUInteger)attempt generation:(NSNumber*)generation epoch:(NSString*)epoch completion:(nullable void (^)(NSDictionary* _Nullable,NSError* _Nullable))completion;
- (nullable NSDictionary*)captureLockedPath:(NSString*)path reason:(NSString*)reason
                     continuingDocumentID:(nullable NSString*)documentID
                                  manifest:(NSMutableDictionary*)manifest error:(NSError**)error;
@end

@interface SPDFMacCollectionStore (CleanupPrivate)
- (unsigned long long)retainedBytesInManifest:(NSDictionary*)manifest;
- (BOOL)enforceStorageLimitInManifest:(NSMutableDictionary*)manifest
                  protectedVersionID:(nullable NSString*)versionID error:(NSError**)error;
- (void)collectUnreferencedFilesInManifest:(NSDictionary*)manifest;
@end
NS_ASSUME_NONNULL_END
