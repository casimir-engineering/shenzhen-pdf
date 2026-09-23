#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Dates are Unix seconds. Document rows: id, path, aliases, title, versions,
// latestVersionID, capturedAt, status, excluded. Version rows: id, hash, size,
// capturedAt, modifiedAt, reason, keep, assets, assetWarnings, encrypted, indexFile.
// Private text-index pages are {page:1-based, text}; page0 means unknown in engine-free tools.
// Search rows also have page, snippet, query. Construction/reads never create folders.
@interface SPDFMacCollectionStore : NSObject
@property(nonatomic, readonly) NSURL* rootURL;
+ (instancetype)defaultStore;
- (instancetype)initWithRootURL:(NSURL*)URL;
// choice: unset/enabled/disabled. storageLimitBytes: 0 means Keep all.
- (NSDictionary*)settings;
- (BOOL)updateSettings:(NSDictionary*)changes error:(NSError**)error;
- (BOOL)isEnabled;
- (NSArray<NSDictionary*>*)documents;
- (nullable NSDictionary*)documentForPath:(NSString*)path;
- (NSArray<NSDictionary*>*)versionsForDocumentID:(NSString*)documentID;
// Retained document/asset objects plus text indexes, excluding regenerated preview caches.
- (unsigned long long)storageUsedBytes;
- (BOOL)isArchivePath:(NSString*)path;
@end
@interface SPDFMacCollectionStore (Capture)
- (nullable NSDictionary*)capturePath:(NSString*)path reason:(NSString*)reason error:(NSError**)error;
// Only observed live-watch/app-save continuity may supply an existing document ID.
// Generic opens pass nil: a changed file identity at the same path starts separate history.
- (nullable NSDictionary*)capturePath:(NSString*)path reason:(NSString*)reason
               continuingDocumentID:(nullable NSString*)documentID error:(NSError**)error;
// Completion always runs on main queue. No queue exists until explicitly capturing.
- (void)capturePath:(NSString*)path reason:(NSString*)reason
        completion:(nullable void (^)(NSDictionary* _Nullable, NSError* _Nullable))completion;
- (void)capturePath:(NSString*)path reason:(NSString*)reason
        continuingDocumentID:(nullable NSString*)documentID
        completion:(nullable void (^)(NSDictionary* _Nullable, NSError* _Nullable))completion;
- (void)importRecentPaths:(NSArray<NSString*>*)paths;
- (BOOL)ensureProtectedPath:(NSString*)path reason:(NSString*)reason error:(NSError**)error;
- (BOOL)ensureProtectedPath:(NSString*)path reason:(NSString*)reason
      continuingDocumentID:(nullable NSString*)documentID error:(NSError**)error;
@end
@interface SPDFMacCollectionStore (Access)
- (BOOL)setExcluded:(BOOL)excluded path:(NSString*)path error:(NSError**)error;
- (BOOL)setExcluded:(BOOL)excluded documentID:(NSString*)documentID error:(NSError**)error;
- (BOOL)setKeep:(BOOL)keep versionID:(NSString*)versionID documentID:(NSString*)documentID error:(NSError**)error;
// nil versionID removes document history; nil documentID removes all archived data.
// Caller obtains explicit scope confirmation. Originals/exclusion choices are untouched.
- (BOOL)deleteDocumentID:(nullable NSString*)documentID versionID:(nullable NSString*)versionID error:(NSError**)error;
- (nullable NSURL*)materializeVersionID:(NSString*)versionID documentID:(NSString*)documentID error:(NSError**)error;
- (BOOL)linkDocumentID:(NSString*)documentID toPath:(NSString*)path
        allowMismatch:(BOOL)allowMismatch error:(NSError**)error;
@end
@interface SPDFMacCollectionStore (Export)
- (nullable NSDictionary*)archiveInfoForPath:(NSString*)path;
- (BOOL)exportVersionID:(NSString*)versionID documentID:(NSString*)documentID
                 toURL:(NSURL*)URL error:(NSError**)error;
@end
@interface SPDFMacCollectionStore (Search)
- (NSArray<NSDictionary*>*)search:(NSString*)query titlesOnly:(BOOL)titlesOnly
                 excludingPaths:(NSSet<NSString*>*)paths limit:(NSUInteger)limit;
// Explicit invocation only. Enumerates user-provided roots, skips archive, symlinks/packages.
- (NSArray<NSDictionary*>*)locateCandidatesForDocumentID:(NSString*)documentID
            roots:(NSArray<NSURL*>*)roots cancelled:(BOOL (^)(void))cancelled error:(NSError**)error;
@end
@interface SPDFMacCollectionStore (Location)
// Copies/verifies existing storage, then durably redirects running windows. Destination must be empty.
- (BOOL)relocateToURL:(NSURL*)URL error:(NSError**)error;
@end
@interface SPDFMacCollectionStore (Cleanup)
// Preview does not create storage. Applying rejects a stale review without deleting anything.
// Plan: storageLimitBytes, usedBytes, projectedBytes, reclaimedBytes, canApply,
// removedVersionCount, removedDocumentCount, reviewToken, removals (documentID,
// versionID, title, capturedAt, openCount, stage: previousVersion/document).
- (NSDictionary*)previewStorageLimit:(unsigned long long)limit;
- (BOOL)applyStorageLimit:(unsigned long long)limit reviewedPlan:(NSDictionary*)plan error:(NSError**)error;
// Explicit user opens only; callers exclude restoration, capture and history previews.
// Missing histories are a lazy no-op; this never creates an unused Collection.
- (BOOL)recordUserOpenForDocumentID:(NSString*)documentID error:(NSError**)error;
@end
NS_ASSUME_NONNULL_END
