#import "SPDFUpdater.h"

#import <AppKit/AppKit.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>

#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <sys/stat.h>

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

static NSString* const kSPDFTeamID = @"66LJ4BV7Q3";
static NSString* const kSPDFAppBundleID = @"com.intuition.shenzhenpdf";
static NSString* const kSPDFReleasesLatestURL =
    @"https://api.github.com/repos/casimir-engineering/shenzhen-pdf/releases/latest";
static NSString* const kSPDFReleasePageURL =
    @"https://github.com/casimir-engineering/shenzhen-pdf/releases";
static NSString* const kSPDFAssetName = @"ShenzhenPDF-mac-arm64.dmg";

static const NSTimeInterval kSPDFDailyInterval = 86400.0;        // 24h gate
static const NSTimeInterval kSPDFIdleDelay = 5.0;               // post-first-paint settle
static const NSTimeInterval kSPDFNetworkTimeout = 15.0;
static const NSTimeInterval kSPDFLeaseStaleAfter = 3600.0;      // 1h liveness ceiling
static const NSTimeInterval kSPDFLaterSnooze = 7.0 * 86400.0;   // "Later" nag cap
static const long long kSPDFMaxDownloadBytes = 64LL * 1024 * 1024;
static const NSUInteger kSPDFMaxRedirects = 5;
static const NSInteger kSPDFSiblingQuitTimeoutSeconds = 20;
static const uint32_t kSPDFHardenedRuntimeFlag = 0x10000;       // kSecCodeSignatureRuntime

static NSString* const kSPDFUpdaterErrorDomain = @"SPDFUpdaterErrorDomain";

// ---------------------------------------------------------------------------
// Sandbox detection
// ---------------------------------------------------------------------------

BOOL spdf_is_sandboxed(void) {
    static BOOL sandboxed = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      if (getenv("APP_SANDBOX_CONTAINER_ID") != NULL) {
          sandboxed = YES;
          return;
      }
      SecCodeRef self = NULL;
      if (SecCodeCopySelf(kSecCSDefaultFlags, &self) != errSecSuccess || !self) return;
      CFDictionaryRef info = NULL;
      if (SecCodeCopySigningInformation(self, kSecCSDynamicInformation, &info) == errSecSuccess && info) {
          NSDictionary* infoDict = (__bridge NSDictionary*)info;
          NSDictionary* entitlements = infoDict[(__bridge NSString*)kSecCodeInfoEntitlementsDict];
          id sandboxValue = entitlements[@"com.apple.security.app-sandbox"];
          if ([sandboxValue respondsToSelector:@selector(boolValue)] && [sandboxValue boolValue]) sandboxed = YES;
          CFRelease(info);
      }
      CFRelease(self);
    });
    return sandboxed;
}

// ---------------------------------------------------------------------------
// Version comparison (pure)
// ---------------------------------------------------------------------------

static NSArray<NSNumber*>* spdf_version_components(NSString* version) {
    if (![version isKindOfClass:NSString.class] || version.length == 0) return nil;
    NSCharacterSet* seps = [NSCharacterSet characterSetWithCharactersInString:@". -"];
    NSArray<NSString*>* parts = [version componentsSeparatedByCharactersInSet:seps];
    NSMutableArray<NSNumber*>* out = [NSMutableArray array];
    for (NSString* part in parts) {
        if (part.length == 0) continue;  // tolerate "v1..2" style noise
        NSScanner* scanner = [NSScanner scannerWithString:part];
        long long value = 0;
        if (![scanner scanLongLong:&value] || !scanner.atEnd) return nil;  // non-numeric field => malformed
        [out addObject:@(value)];
    }
    return out.count ? out : nil;
}

NSComparisonResult spdf_compare_versions(NSString* a, NSString* b) {
    NSArray<NSNumber*>* ca = spdf_version_components(a);
    NSArray<NSNumber*>* cb = spdf_version_components(b);
    // Malformed input on either side => no ordering decision (treated as same).
    if (!ca || !cb) return NSOrderedSame;
    NSUInteger n = MAX(ca.count, cb.count);
    for (NSUInteger i = 0; i < n; ++i) {
        long long va = i < ca.count ? ca[i].longLongValue : 0;
        long long vb = i < cb.count ? cb[i].longLongValue : 0;
        if (va < vb) return NSOrderedAscending;
        if (va > vb) return NSOrderedDescending;
    }
    return NSOrderedSame;
}

// ---------------------------------------------------------------------------
// Offline signature verification (the only trust boundary)
// ---------------------------------------------------------------------------

static NSError* spdf_make_error(NSString* message) {
    return [NSError errorWithDomain:kSPDFUpdaterErrorDomain
                               code:-1
                           userInfo:@{NSLocalizedDescriptionKey : message ?: @"Verification failed."}];
}

// Full Developer ID requirement: Apple anchor + OU pin + WWDR intermediate
// marker (1.2.840.113635.100.6.2.6) + Developer ID Application leaf marker
// (1.2.840.113635.100.6.1.13). Pinning both markers prevents a leaf from any
// other Apple-anchored program with the same OU from satisfying it.
static NSString* const kSPDFDeveloperIDRequirement =
    @"anchor apple generic and "
    @"certificate leaf[subject.OU] = \"66LJ4BV7Q3\" and "
    @"certificate 1[field.1.2.840.113635.100.6.2.6] exists and "
    @"certificate leaf[field.1.2.840.113635.100.6.1.13] exists";

BOOL spdf_verify_signed_bundle(NSURL* url, BOOL isApp, NSError** error) {
    if (!url) {
        if (error) *error = spdf_make_error(@"No file to verify.");
        return NO;
    }

    SecStaticCodeRef code = NULL;
    OSStatus status = SecStaticCodeCreateWithPath((__bridge CFURLRef)url, kSecCSDefaultFlags, &code);
    if (status != errSecSuccess || !code) {
        if (error) *error = spdf_make_error(@"The update could not be read for verification.");
        if (code) CFRelease(code);
        return NO;
    }

    BOOL ok = NO;
    SecRequirementRef requirement = NULL;
    CFErrorRef cfError = NULL;
    CFDictionaryRef info = NULL;

    @try {
        // 1. Developer ID requirement. For the DMG we additionally fold in
        //    "notarized" so the offline stapled-ticket gate is part of the same
        //    SecStaticCode validity check (hard reject when absent/invalid).
        NSString* reqString = kSPDFDeveloperIDRequirement;
        if (!isApp) reqString = [reqString stringByAppendingString:@" and notarized"];

        if (SecRequirementCreateWithString((__bridge CFStringRef)reqString, kSecCSDefaultFlags, &requirement) !=
                errSecSuccess ||
            !requirement) {
            if (error) *error = spdf_make_error(@"Could not build the verification policy.");
            return NO;
        }

        // For the extracted app, deep-verify: nested Mach-O (bundled dylibs,
        // helper tools), the strict resource envelope, and all architectures.
        // Default flags alone would let a tampered/added nested binary or extra
        // unsealed resource slip past the top-level check.
        SecCSFlags validityFlags = kSecCSDefaultFlags;
        if (isApp)
            validityFlags |=
                kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate;
        status = SecStaticCodeCheckValidityWithErrors(code, validityFlags, requirement, &cfError);
        if (status != errSecSuccess) {
            if (error) *error = spdf_make_error(@"The update's signature or notarization did not pass verification.");
            return NO;
        }

        // 2. Independently pin the Team ID (never the DMG codesign Identifier,
        //    which is the hdiutil-generated "ShenzhenPDF-installer").
        if (SecCodeCopySigningInformation(code, kSecCSSigningInformation, &info) != errSecSuccess || !info) {
            if (error) *error = spdf_make_error(@"Could not read the update's signing information.");
            return NO;
        }
        NSDictionary* infoDict = (__bridge NSDictionary*)info;
        NSString* team = infoDict[(__bridge NSString*)kSecCodeInfoTeamIdentifier];
        if (![team isEqualToString:kSPDFTeamID]) {
            if (error) *error = spdf_make_error(@"The update was signed by an unexpected developer.");
            return NO;
        }

        if (isApp) {
            // 3a. Hardened runtime flag.
            NSNumber* flags = infoDict[(__bridge NSString*)kSecCodeInfoFlags];
            if (!((flags.unsignedIntValue) & kSPDFHardenedRuntimeFlag)) {
                if (error) *error = spdf_make_error(@"The update is not built with the hardened runtime.");
                return NO;
            }
            // 3b. Bundle id pin (applies to the app, never the DMG).
            NSDictionary* plist = infoDict[(__bridge NSString*)kSecCodeInfoPList];
            NSString* bundleID = plist[@"CFBundleIdentifier"];
            if (![bundleID isEqualToString:kSPDFAppBundleID]) {
                if (error) *error = spdf_make_error(@"The update is not Shenzhen PDF.");
                return NO;
            }
        }

        ok = YES;
    } @finally {
        if (info) CFRelease(info);
        if (cfError) CFRelease(cfError);
        if (requirement) CFRelease(requirement);
        if (code) CFRelease(code);
    }
    return ok;
}

// Read CFBundleShortVersionString from a bundle's Info.plist on disk.
static NSString* spdf_bundle_short_version(NSString* appPath) {
    NSBundle* bundle = [NSBundle bundleWithPath:appPath];
    return bundle.infoDictionary[@"CFBundleShortVersionString"];
}

// ---------------------------------------------------------------------------
// Foundation-only post-update swap/relaunch helper (--post-update path)
// ---------------------------------------------------------------------------

static NSUInteger spdf_running_instance_count(void) {
    NSUInteger count = 0;
    for (NSRunningApplication* app in
         [NSRunningApplication runningApplicationsWithBundleIdentifier:kSPDFAppBundleID]) {
        if (app.processIdentifier != getpid()) ++count;
    }
    return count;
}

// Clear updateInProgress and pendingTag from update.json on a helper abort so
// the next launch isn't left with a half-set lifecycle. Foundation-only flock
// read-modify-write mirroring -withLockedUpdateStore:.
static void spdf_helper_clear_update_state(void) {
    NSURL* base = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                       inDomains:NSUserDomainMask]
                      .firstObject;
    NSString* dir = [base.path stringByAppendingPathComponent:@"ShenzhenPDF"];
    NSString* lockPath = [dir stringByAppendingPathComponent:@"update.lock"];
    NSString* jsonPath = [dir stringByAppendingPathComponent:@"update.json"];
    int fd = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR, 0600);
    if (fd >= 0) flock(fd, LOCK_EX);
    NSMutableDictionary* update = [NSMutableDictionary dictionary];
    NSData* data = [NSData dataWithContentsOfFile:jsonPath];
    if (data) {
        id obj = [NSJSONSerialization JSONObjectWithData:data
                                                 options:NSJSONReadingMutableContainers
                                                   error:nil];
        if ([obj isKindOfClass:NSDictionary.class]) update = obj;
    }
    [update removeObjectForKey:@"updateInProgress"];
    [update removeObjectForKey:@"pendingTag"];
    NSData* out = [NSJSONSerialization dataWithJSONObject:update
                                                 options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                   error:nil];
    if (out) [out writeToFile:jsonPath atomically:YES];
    if (fd >= 0) {
        flock(fd, LOCK_UN);
        close(fd);
    }
}

static void spdf_helper_relaunch_original(NSString* targetBundlePath) {
    NSURL* originalURL = [NSURL fileURLWithPath:targetBundlePath];
    LSRegisterURL((__bridge CFURLRef)originalURL, true);
    [NSWorkspace.sharedWorkspace openApplicationAtURL:originalURL
                                        configuration:[NSWorkspaceOpenConfiguration configuration]
                                    completionHandler:nil];
}

int spdf_run_post_update_helper(NSString* stagedAppPath, NSString* targetBundlePath) {
    if (spdf_is_sandboxed()) return 0;
    if (stagedAppPath.length == 0 || targetBundlePath.length == 0) return 1;
    setsid();  // detach from the parent's process group so we outlive the cascade

    NSFileManager* fm = NSFileManager.defaultManager;

    // 0. TRUST BOUNDARY: re-verify the staged bundle here, in the trusted
    //    in-place binary, immediately before it is renamed into the final path.
    //    The parent verified it earlier, but the staged copy sat in a temp dir
    //    across the sibling-quit window where a local attacker could have
    //    swapped it. Verification must be the immediate predecessor of the
    //    rename (HARD RULE: never exec a staged binary before it is verified AND
    //    renamed into the final path).
    NSError* verifyErr = nil;
    if (!spdf_verify_signed_bundle([NSURL fileURLWithPath:stagedAppPath], /*isApp=*/YES, &verifyErr)) {
        [fm removeItemAtPath:stagedAppPath error:nil];
        spdf_helper_clear_update_state();
        spdf_helper_relaunch_original(targetBundlePath);
        return 1;
    }
    // Defense in depth: lock the staging dir to owner-only so nothing can race
    // the verified copy between this check and the rename below.
    NSString* stagingDir = stagedAppPath.stringByDeletingLastPathComponent;
    chmod(stagingDir.fileSystemRepresentation, 0700);

    // 1. Bounded poll until all old-bundle instances exit; escalate to
    //    forceTerminate on timeout; then a short settle.
    NSTimeInterval waited = 0;
    while (spdf_running_instance_count() > 0 && waited < kSPDFSiblingQuitTimeoutSeconds) {
        [NSThread sleepForTimeInterval:0.5];
        waited += 0.5;
    }
    if (spdf_running_instance_count() > 0) {
        // Escalate: force-terminate any wedged siblings, then poll a second
        // bounded window before giving up.
        for (NSRunningApplication* app in
             [NSRunningApplication runningApplicationsWithBundleIdentifier:kSPDFAppBundleID]) {
            if (app.processIdentifier != getpid()) [app forceTerminate];
        }
        NSTimeInterval forced = 0;
        while (spdf_running_instance_count() > 0 && forced < 5.0) {
            [NSThread sleepForTimeInterval:0.5];
            forced += 0.5;
        }
    }
    if (spdf_running_instance_count() > 0) {
        // Siblings still wedged: abort the swap, leave the bundle untouched,
        // clear the lifecycle state, and relaunch the original.
        [fm removeItemAtPath:stagedAppPath error:nil];
        spdf_helper_clear_update_state();
        spdf_helper_relaunch_original(targetBundlePath);
        return 1;
    }
    [NSThread sleepForTimeInterval:0.5];  // kernel map release after last exit

    NSString* oldPath = [targetBundlePath stringByAppendingString:@".old"];
    [fm removeItemAtPath:oldPath error:nil];  // sweep a stale move-aside

    // 2. Move-aside two-rename swap (PRIMARY; matches existing codebase rename use).
    BOOL targetExists = [fm fileExistsAtPath:targetBundlePath];
    if (targetExists) {
        if (rename(targetBundlePath.fileSystemRepresentation, oldPath.fileSystemRepresentation) != 0) {
            // Not writable: re-register the original, relaunch it untouched.
            spdf_helper_clear_update_state();
            spdf_helper_relaunch_original(targetBundlePath);
            return 1;
        }
    }
    if (rename(stagedAppPath.fileSystemRepresentation, targetBundlePath.fileSystemRepresentation) != 0) {
        // 3. Rollback: restore the working install.
        if (targetExists) rename(oldPath.fileSystemRepresentation, targetBundlePath.fileSystemRepresentation);
        spdf_helper_clear_update_state();
        spdf_helper_relaunch_original(targetBundlePath);
        return 1;
    }

    // 3a. TRUST BOUNDARY (final): re-verify the code now sitting at the final
    //     path before we register and exec it, so the binary we launch is
    //     verified at its final location (not just where it was staged).
    NSError* finalVerifyErr = nil;
    if (!spdf_verify_signed_bundle([NSURL fileURLWithPath:targetBundlePath], /*isApp=*/YES, &finalVerifyErr)) {
        // Roll back to the known-good install and relaunch it.
        [fm removeItemAtPath:targetBundlePath error:nil];
        if (targetExists) rename(oldPath.fileSystemRepresentation, targetBundlePath.fileSystemRepresentation);
        spdf_helper_clear_update_state();
        spdf_helper_relaunch_original(targetBundlePath);
        return 1;
    }

    // Strip quarantine on the FINAL in-place bundle so Gatekeeper does not
    // translocate the relaunched process to a read-only shadow copy.
    NSTask* xattr = [[NSTask alloc] init];
    xattr.executableURL = [NSURL fileURLWithPath:@"/usr/bin/xattr"];
    xattr.arguments = @[ @"-dr", @"com.apple.quarantine", targetBundlePath ];
    xattr.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    xattr.standardError = [NSFileHandle fileHandleWithNullDevice];
    if ([xattr launchAndReturnError:nil]) [xattr waitUntilExit];

    // 4. Re-register Launch Services on the FINAL path before relaunch.
    NSURL* finalURL = [NSURL fileURLWithPath:targetBundlePath];
    LSRegisterURL((__bridge CFURLRef)finalURL, true);

    // 5. Relaunch with no path argument so the standard restore path fans the
    //    full multi-window session back out.
    NSWorkspaceOpenConfiguration* config = [NSWorkspaceOpenConfiguration configuration];
    config.createsNewApplicationInstance = YES;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSRunningApplication* launched = nil;
    [NSWorkspace.sharedWorkspace openApplicationAtURL:finalURL
                                        configuration:config
                                    completionHandler:^(NSRunningApplication* app, NSError* err) {
                                      (void)err;
                                      launched = app;
                                      dispatch_semaphore_signal(sem);
                                    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)));

    // 5.9.5 Assert the relaunched instance runs from the real in-place path and
    //        was not translocated to a read-only shadow copy. If it is
    //        translocated, the in-place swap did not "take" for the user; leave
    //        .old in place so the next launch can roll back, but log nothing
    //        (Foundation-only helper). The pendingTag/update_ok handshake in the
    //        relaunched process is the authoritative health gate.
    NSString* launchedPath = launched.bundleURL.path;
    (void)launchedPath;  // best-effort assertion; handshake is authoritative

    // .old is retained until the relaunched process writes update_ok (§5.9.6 /
    // §5.10). The relaunched process's launch-time hook consumes pendingTag,
    // writes update_ok, deletes .old on a version match, or rolls .old back on a
    // mismatch. Do NOT delete .old here.
    return 0;
}

// ---------------------------------------------------------------------------
// SPDFUpdater
// ---------------------------------------------------------------------------

// Informal bridge the app delegate implements (declared here to silence
// undeclared-selector warnings; calls are all respondsToSelector-guarded).
@protocol SPDFUpdaterHostBridge <NSObject>
@optional
- (BOOL)autoUpdateEnabledForUpdater;
- (NSString*)skippedUpdateVersionForUpdater;
- (void)setSkippedUpdateVersionForUpdater:(NSString*)tag;
- (void)showError:(NSString*)message detail:(NSString*)detail;
@end

@interface SPDFUpdater () <NSURLSessionTaskDelegate, NSURLSessionDownloadDelegate>
@end

@implementation SPDFUpdater {
    dispatch_queue_t _queue;            // Background-QoS serial queue
    BOOL _updateInProgress;             // in-process driver flag (main thread)

    // Download/session state (touched on _queue / delegate callbacks).
    NSURLSession* _downloadSession;
    NSURLSessionDownloadTask* _downloadTask;
    NSUInteger _redirectCount;
    long long _expectedAssetSize;
    NSURL* _downloadStagingURL;        // same-volume staging dir for the moved download
    NSString* _pendingTag;
    NSString* _pendingNotes;
    void (^_downloadCompletion)(NSURL* _Nullable location, NSError* _Nullable error);

    // Progress panel (main thread).
    NSPanel* _progressPanel;
    NSTextField* _progressTitleLabel;
    NSTextField* _progressDetailLabel;
    NSProgressIndicator* _progressIndicator;
    NSButton* _progressCancelButton;
    BOOL _userCancelled;

    // Deferred (non-active) prompt.
    NSDictionary* _pendingPromptInfo;
}

+ (instancetype)shared {
    static SPDFUpdater* shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[SPDFUpdater alloc] init]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        dispatch_queue_attr_t attr =
            dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_BACKGROUND, 0);
        _queue = dispatch_queue_create("com.intuition.shenzhenpdf.updater", attr);
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:NSApplicationDidBecomeActiveNotification
                                                   object:nil];
    }
    return self;
}

// ----- support dir / json helpers (own flock unit, sidesteps save suspension) -

- (NSString*)supportDirectory {
    NSURL* base = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                       inDomains:NSUserDomainMask]
                      .firstObject;
    NSString* dir = [base.path stringByAppendingPathComponent:@"ShenzhenPDF"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (NSString*)pathForStateFile:(NSString*)name {
    return [[self supportDirectory] stringByAppendingPathComponent:name];
}

- (NSMutableDictionary*)readUpdateJSON {
    NSData* data = [NSData dataWithContentsOfFile:[self pathForStateFile:@"update.json"]];
    if (!data) return [NSMutableDictionary dictionary];
    id obj = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    if (![obj isKindOfClass:NSDictionary.class]) return [NSMutableDictionary dictionary];
    return obj;
}

- (void)writeUpdateJSON:(NSDictionary*)object {
    NSData* data = [NSJSONSerialization dataWithJSONObject:object
                                                  options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                    error:nil];
    if (data) [data writeToFile:[self pathForStateFile:@"update.json"] atomically:YES];
}

// flock'd read-modify-write of update.json, mirroring withLockedSessionStore:.
- (void)withLockedUpdateStore:(BOOL (^)(NSMutableDictionary* update))block {
    if (!block) return;
    NSString* lockPath = [self pathForStateFile:@"update.lock"];
    int fd = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR, 0600);
    if (fd >= 0) flock(fd, LOCK_EX);
    NSMutableDictionary* update = [self readUpdateJSON];
    BOOL changed = block(update);
    if (changed) [self writeUpdateJSON:update];
    if (fd >= 0) {
        flock(fd, LOCK_UN);
        close(fd);
    }
}

// ----- self version -----------------------------------------------------------

// "YY.M.DD-BUILD" read directly from the running bundle's Info.plist. Fails
// closed (returns nil) if CFBundleShortVersionString is missing/unparseable.
- (NSString*)runningVersion {
    NSDictionary* info = NSBundle.mainBundle.infoDictionary;
    NSString* shortVersion = info[@"CFBundleShortVersionString"];
    if (![shortVersion isKindOfClass:NSString.class] || shortVersion.length == 0) return nil;
    if (!spdf_version_components(shortVersion)) return nil;
    NSString* build = info[(NSString*)kCFBundleVersionKey];
    if (![build isKindOfClass:NSString.class] || build.length == 0) build = @"1";
    return [NSString stringWithFormat:@"%@-%@", shortVersion, build];
}

- (NSString*)userAgent {
    NSString* version = [self runningVersion] ?: @"unknown";
    return [NSString stringWithFormat:@"ShenzhenPDF/%@ (macOS; +https://github.com/casimir-engineering/shenzhen-pdf)",
                                      version];
}

// ----- settings access (delegate-owned prefs) ---------------------------------

- (id<SPDFUpdaterHostBridge>)hostBridge {
    id delegate = NSApp.delegate;
    return [delegate conformsToProtocol:@protocol(SPDFUpdaterHostBridge)] ||
                   [delegate respondsToSelector:@selector(autoUpdateEnabledForUpdater)]
               ? (id<SPDFUpdaterHostBridge>)delegate
               : nil;
}

- (BOOL)autoUpdateEnabled {
    id<SPDFUpdaterHostBridge> bridge = [self hostBridge];
    if ([bridge respondsToSelector:@selector(autoUpdateEnabledForUpdater)])
        return [bridge autoUpdateEnabledForUpdater];
    return YES;
}

- (NSString*)skippedUpdateVersion {
    id<SPDFUpdaterHostBridge> bridge = [self hostBridge];
    if ([bridge respondsToSelector:@selector(skippedUpdateVersionForUpdater)])
        return [bridge skippedUpdateVersionForUpdater];
    return nil;
}

- (void)setSkippedUpdateVersion:(NSString*)tag {
    id<SPDFUpdaterHostBridge> bridge = [self hostBridge];
    if ([bridge respondsToSelector:@selector(setSkippedUpdateVersionForUpdater:)])
        [bridge setSkippedUpdateVersionForUpdater:tag];
}

// ----- daily scheduling -------------------------------------------------------

- (void)scheduleDailyUpdateCheckIfNeeded {
    if (spdf_is_sandboxed()) return;        // 1. App Store build never self-updates
    if (![self autoUpdateEnabled]) return;  // 2. persisted opt-out

    // 3. Cross-process 24h gate, stamped pre-network (a crash still burns the day).
    __block BOOL gated = NO;
    [self withLockedUpdateStore:^BOOL(NSMutableDictionary* update) {
      NSTimeInterval now = [NSDate date].timeIntervalSince1970;
      NSNumber* last = update[@"lastUpdateCheck"];
      if ([last isKindOfClass:NSNumber.class] && (now - last.doubleValue) < kSPDFDailyInterval) {
          gated = YES;
          return NO;
      }
      update[@"lastUpdateCheck"] = @(now);
      return YES;
    }];
    if (gated) return;

    // On launch, sweep any stale staging dirs from an interrupted prior run.
    [self sweepStaleStagingDirs];

    // 4. Idle delay, then run on Background QoS.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSPDFIdleDelay * NSEC_PER_SEC)), _queue, ^{
      [self performNetworkCheckUserInitiated:NO];
    });
}

- (void)checkForUpdatesUserInitiated:(BOOL)userInitiated {
    if (spdf_is_sandboxed()) return;
    if (userInitiated) {
        // "Already in progress" fast path: live + recent lease, or our own driver.
        if (_updateInProgress || [self liveLeaseHeldByOther]) {
            [self showInfo:@"An update is already in progress." detail:@""];
            return;
        }
    }
    dispatch_async(_queue, ^{ [self performNetworkCheckUserInitiated:userInitiated]; });
}

// ----- network check ----------------------------------------------------------

- (void)performNetworkCheckUserInitiated:(BOOL)userInitiated {
    NSString* running = [self runningVersion];
    if (running == nil) {
        // Fail closed: unknown self version => no update.
        if (userInitiated) [self showErrorOnMain:@"Could not determine the installed version."];
        return;
    }

    NSURLSessionConfiguration* config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.waitsForConnectivity = NO;
    NSURLSession* session = [NSURLSession sessionWithConfiguration:config];

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kSPDFReleasesLatestURL]];
    request.timeoutInterval = kSPDFNetworkTimeout;
    [request setValue:[self userAgent] forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];

    __block NSString* etag = nil;
    [self withLockedUpdateStore:^BOOL(NSMutableDictionary* update) {
      id e = update[@"etag"];
      if ([e isKindOfClass:NSString.class]) etag = e;
      return NO;
    }];
    // The manual "Check for Updates…" path omits If-None-Match so the server
    // always returns a fresh 200 and the full decision logic runs (including a
    // re-offer of a previously-skipped tag). The silent daily path sends the
    // ETag so a 304 short-circuits and doesn't count against the rate limit.
    if (etag.length && !userInitiated) [request setValue:etag forHTTPHeaderField:@"If-None-Match"];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSData* responseData = nil;
    __block NSHTTPURLResponse* httpResponse = nil;
    __block NSError* netError = nil;
    NSURLSessionDataTask* task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
                                              responseData = data;
                                              if ([response isKindOfClass:NSHTTPURLResponse.class])
                                                  httpResponse = (NSHTTPURLResponse*)response;
                                              netError = error;
                                              dispatch_semaphore_signal(sem);
                                            }];
    [task resume];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    [session finishTasksAndInvalidate];

    if (netError || !httpResponse) {
        if (userInitiated) [self showErrorOnMain:@"Could not reach the update server."];
        return;  // silent on the daily path; lastUpdateCheck already stamped
    }
    if (httpResponse.statusCode == 304) {
        if (userInitiated) [self showUpToDate];  // server says unchanged
        return;
    }
    if (httpResponse.statusCode != 200) {
        if (userInitiated) [self showErrorOnMain:@"The update server returned an unexpected response."];
        return;
    }

    NSString* newEtag = httpResponse.allHeaderFields[@"Etag"] ?: httpResponse.allHeaderFields[@"ETag"];

    id json = responseData ? [NSJSONSerialization JSONObjectWithData:responseData options:0 error:nil] : nil;
    if (![json isKindOfClass:NSDictionary.class]) {
        if (userInitiated) [self showErrorOnMain:@"The update server response was malformed."];
        return;
    }
    NSDictionary* release = json;
    NSString* tag = release[@"tag_name"];
    BOOL draft = [release[@"draft"] boolValue];
    BOOL prerelease = [release[@"prerelease"] boolValue];
    NSString* notes = [release[@"body"] isKindOfClass:NSString.class] ? release[@"body"] : nil;

    // Asset selection: exact name match.
    NSString* downloadURL = nil;
    long long assetSize = 0;
    NSString* assetDigest = nil;
    for (NSDictionary* asset in (release[@"assets"] ?: @[])) {
        if (![asset isKindOfClass:NSDictionary.class]) continue;
        if ([asset[@"name"] isEqualToString:kSPDFAssetName]) {
            downloadURL = asset[@"browser_download_url"];
            assetSize = [asset[@"size"] longLongValue];
            id digest = asset[@"digest"];
            if ([digest isKindOfClass:NSString.class]) assetDigest = digest;
            break;
        }
    }

    // Persist etag + advance highestVersionSeen (replay/downgrade high-water).
    __block NSString* highestSeen = nil;
    [self withLockedUpdateStore:^BOOL(NSMutableDictionary* update) {
      BOOL changed = NO;
      if (newEtag.length) {
          update[@"etag"] = newEtag;
          changed = YES;
      }
      id hv = update[@"highestVersionSeen"];
      highestSeen = [hv isKindOfClass:NSString.class] ? hv : nil;
      if (tag.length && spdf_compare_versions(tag, highestSeen) == NSOrderedDescending) {
          update[@"highestVersionSeen"] = tag;
          highestSeen = tag;
          changed = YES;
      }
      return changed;
    }];

    // Update-available decision.
    BOOL isNewer = (tag.length && spdf_compare_versions(tag, running) == NSOrderedDescending);
    BOOL notDowngrade = (tag.length && spdf_compare_versions(tag, highestSeen) != NSOrderedAscending);
    BOOL hasAsset = (downloadURL.length > 0);
    BOOL available = isNewer && notDowngrade && hasAsset && !draft && !prerelease;

    if (!available) {
        if (userInitiated) [self showUpToDate];
        return;
    }

    // Silent path honours Skip + Later snooze; manual path ignores both.
    if (!userInitiated) {
        if ([tag isEqualToString:[self skippedUpdateVersion]]) return;
        __block BOOL snoozed = NO;
        [self withLockedUpdateStore:^BOOL(NSMutableDictionary* update) {
          NSString* deferredTag = update[@"deferredTag"];
          NSNumber* remindAfter = update[@"remindAfter"];
          if ([deferredTag isEqualToString:tag] && [remindAfter isKindOfClass:NSNumber.class] &&
              [NSDate date].timeIntervalSince1970 < remindAfter.doubleValue)
              snoozed = YES;
          return NO;
        }];
        if (snoozed) return;
    }

    NSDictionary* promptInfo = @{
        @"tag" : tag ?: @"",
        @"downloadURL" : downloadURL ?: @"",
        @"assetSize" : @(assetSize),
        @"assetDigest" : assetDigest ?: @"",
        @"notes" : notes ?: @"",
        @"userInitiated" : @(userInitiated),
    };
    dispatch_async(dispatch_get_main_queue(), ^{ [self presentUpdateAvailable:promptInfo]; });
}

// ----- update-available prompt ------------------------------------------------

- (void)presentUpdateAvailable:(NSDictionary*)info {
    BOOL userInitiated = [info[@"userInitiated"] boolValue];
    if (!userInitiated && !NSApp.isActive) {
        // Defer: surface on next activation, no focus theft.
        _pendingPromptInfo = info;
        return;
    }

    NSString* tag = info[@"tag"];
    NSString* running = [self runningVersion] ?: @"";
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"A new version of Shenzhen PDF is available";
    NSString* detail =
        [NSString stringWithFormat:@"Shenzhen PDF %@ is available — you have %@. Would you like to install it now?",
                                   tag, running];
    NSString* notes = info[@"notes"];
    if ([notes isKindOfClass:NSString.class] && notes.length) {
        NSString* plain = [self plainTextReleaseNotes:notes];
        if (plain.length) detail = [detail stringByAppendingFormat:@"\n\n%@", plain];
    }
    alert.informativeText = detail;
    [alert addButtonWithTitle:@"Install and Relaunch"];  // NSAlertFirstButtonReturn
    [alert addButtonWithTitle:@"Skip This Version"];      // NSAlertSecondButtonReturn
    [alert addButtonWithTitle:@"Later"];                  // NSAlertThirdButtonReturn

    NSWindow* window = [self mainWindow];
    if (!userInitiated && window && NSApp.isActive) {
        [alert beginSheetModalForWindow:window
                      completionHandler:^(NSModalResponse response) {
                        [self handlePromptResponse:response info:info];
                      }];
    } else {
        NSModalResponse response = [alert runModal];
        [self handlePromptResponse:response info:info];
    }
}

- (void)handlePromptResponse:(NSModalResponse)response info:(NSDictionary*)info {
    NSString* tag = info[@"tag"];
    if (response == NSAlertFirstButtonReturn) {
        dispatch_async(_queue, ^{ [self downloadAndInstall:info]; });
    } else if (response == NSAlertSecondButtonReturn) {
        [self setSkippedUpdateVersion:tag];  // permanent per-version suppression
    } else {
        // "Later": snooze this tag for 7 days on the silent path.
        [self withLockedUpdateStore:^BOOL(NSMutableDictionary* update) {
          update[@"deferredTag"] = tag;
          update[@"remindAfter"] = @([NSDate date].timeIntervalSince1970 + kSPDFLaterSnooze);
          return YES;
        }];
    }
}

- (void)applicationDidBecomeActive:(NSNotification*)note {
    (void)note;
    if (!_pendingPromptInfo) return;
    NSDictionary* info = _pendingPromptInfo;
    _pendingPromptInfo = nil;
    [self presentUpdateAvailable:info];
}

- (NSString*)plainTextReleaseNotes:(NSString*)body {
    return spdf_format_release_notes_for_alert(body);
}

NSString* spdf_format_release_notes_for_alert(NSString* body) {
    if (![body isKindOfClass:NSString.class] || body.length == 0) return @"";
    NSCharacterSet* ws = NSCharacterSet.whitespaceCharacterSet;
    NSString* text = [body stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    text = [text stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];

    NSMutableArray<NSString*>* lines = [NSMutableArray array];
    for (NSString* rawLine in [text componentsSeparatedByString:@"\n"]) {
        NSString* line = [rawLine stringByTrimmingCharactersInSet:ws];
        // Release bodies put a brief highlights section above the first
        // horizontal rule; the alert shows only that section.
        if ([line hasPrefix:@"---"] || [line hasPrefix:@"***"] || [line hasPrefix:@"___"]) break;
        while ([line hasPrefix:@"#"]) line = [line substringFromIndex:1];
        if ([line hasPrefix:@"> "]) line = [line substringFromIndex:2];
        line = [line stringByTrimmingCharactersInSet:ws];
        BOOL isBullet = NO;
        for (NSString* bullet in @[ @"- ", @"* ", @"+ " ]) {
            if ([line hasPrefix:bullet]) {
                line = [@"• " stringByAppendingString:[line substringFromIndex:2]];
                isBullet = YES;
                break;
            }
        }
        for (NSString* marker in @[ @"**", @"`", @"_" ])
            line = [line stringByReplacingOccurrencesOfString:marker withString:@""];
        // Hard-wrapped continuation lines (indented in the raw body) rejoin
        // their bullet so the alert wraps them naturally.
        BOOL continuation = !isBullet && line.length && [rawLine hasPrefix:@"  "] && lines.count &&
                            ((NSString*)lines.lastObject).length;
        if (continuation) {
            lines[lines.count - 1] = [lines.lastObject stringByAppendingFormat:@" %@", line];
        } else if (line.length) {
            [lines addObject:line];  // blank lines add nothing in the compact alert
        }
    }
    text = [lines componentsJoinedByString:@"\n"];

    // Neutralize control + format characters and bidi overrides so a crafted
    // release body can't spoof the version/identity line that follows in the
    // alert. NSAlert renders plain text (won't execute), but bidi/control chars
    // could still reorder or hide text visually. Real line breaks survive.
    NSMutableCharacterSet* strip = [NSMutableCharacterSet new];
    [strip formUnionWithCharacterSet:NSCharacterSet.controlCharacterSet];
    [strip addCharactersInRange:NSMakeRange(0x202A, 5)];   // U+202A-202E embeddings/overrides
    [strip addCharactersInRange:NSMakeRange(0x2066, 4)];   // U+2066-2069 isolates
    NSMutableString* cleaned = [NSMutableString stringWithCapacity:text.length];
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
                             options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString* sub, NSRange r, NSRange er, BOOL* stop) {
                            (void)r;
                            (void)er;
                            (void)stop;
                            unichar c = sub.length ? [sub characterAtIndex:0] : 0;
                            if (sub.length == 1 && [strip characterIsMember:c] && c != '\n') return;
                            [cleaned appendString:sub];
                          }];
    text = [cleaned stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length > 500) {
        // Cut at the last complete line that fits, falling back to a hard cut.
        NSRange lastBreak = [[text substringToIndex:500] rangeOfString:@"\n" options:NSBackwardsSearch];
        NSUInteger cut = lastBreak.location != NSNotFound ? lastBreak.location : 500;
        text = [[[text substringToIndex:cut] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
            stringByAppendingString:@"\n…"];
    }
    return text;
}

// ----- download + install -----------------------------------------------------

- (void)downloadAndInstall:(NSDictionary*)info {
    // Take the single-driver liveness lease.
    if (![self acquireLease]) {
        [self showInfoOnMain:@"An update is already in progress." detail:@""];
        return;
    }
    _updateInProgress = YES;

    NSError* error = nil;
    BOOL helperLaunched = NO;
    @try {
        [self runInstallPipeline:info error:&error helperLaunched:&helperLaunched];
    } @catch (NSException* exception) {
        error = spdf_make_error(exception.reason ?: @"The update could not be installed.");
    }

    // On success the detached helper owns the swap window. Do NOT clear the
    // lease here — that would let a waking sibling start a second update against
    // a bundle that is mid-rename. The helper clears updateInProgress on abort,
    // and the relaunched process clears it after the handshake; the stale-lease
    // reclaim (dead pid or >1h) is the backstop if the helper dies.
    if (!helperLaunched) {
        _updateInProgress = NO;
        [self releaseLease];
    }

    if (error) {
        [self dismissProgressOnMain];
        [self showErrorOnMain:error.localizedDescription];
    }
}

- (void)runInstallPipeline:(NSDictionary*)info
                     error:(NSError**)outError
             helperLaunched:(BOOL*)outHelperLaunched {
    NSFileManager* fm = NSFileManager.defaultManager;
    NSString* tag = info[@"tag"];
    NSString* downloadURLString = info[@"downloadURL"];
    long long assetSize = [info[@"assetSize"] longLongValue];

    NSURL* bundleURL = NSBundle.mainBundle.bundleURL;
    NSString* bundlePath = bundleURL.path;

    // 5.0 Translocation / non-Applications guard.
    if ([bundlePath containsString:@"/AppTranslocation/"] || [bundlePath hasPrefix:@"/private/var/folders"]) {
        if (outError)
            *outError = spdf_make_error(
                @"To enable automatic updates, move Shenzhen PDF to your Applications folder.");
        return;
    }

    // 5.1 Staging dir on the same volume as the install target (atomic rename).
    NSURL* parentURL = bundleURL.URLByDeletingLastPathComponent;
    NSError* stageErr = nil;
    NSURL* stagingURL = [fm URLForDirectory:NSItemReplacementDirectory
                                   inDomain:NSUserDomainMask
                          appropriateForURL:parentURL
                                     create:YES
                                      error:&stageErr];
    if (!stagingURL) {
        if (outError) *outError = spdf_make_error(@"Could not create a staging directory for the update.");
        return;
    }

    @try {
        // Free-space pre-check (~3x DMG).
        NSDictionary* attrs = [fm attributesOfFileSystemForPath:stagingURL.path error:nil];
        long long freeBytes = [attrs[NSFileSystemFreeSize] longLongValue];
        if (assetSize > 0 && freeBytes > 0 && freeBytes < assetSize * 3) {
            if (outError) *outError = spdf_make_error(@"There is not enough disk space to install the update.");
            return;
        }

        // 5.2 Download (determinate progress wired to asset.size).
        [self showProgressOnMain:tag assetSize:assetSize];
        NSURL* dmgURL = [self downloadAssetFrom:downloadURLString
                                      assetSize:assetSize
                                      stagingURL:stagingURL
                                            tag:tag
                                          error:outError];
        if (!dmgURL) return;  // *outError set, or user-cancelled (silent)

        // 5.3 Content integrity (corruption heuristic only).
        NSDictionary* dmgAttrs = [fm attributesOfItemAtPath:dmgURL.path error:nil];
        long long actualSize = [dmgAttrs[NSFileSize] longLongValue];
        if (assetSize > 0 && actualSize != assetSize) {
            if (outError) *outError = spdf_make_error(@"The downloaded update was incomplete.");
            return;
        }
        NSString* expectedDigest = info[@"assetDigest"];
        if ([expectedDigest isKindOfClass:NSString.class] && expectedDigest.length) {
            NSString* hexDigest = [expectedDigest hasPrefix:@"sha256:"]
                                      ? [expectedDigest substringFromIndex:7]
                                      : expectedDigest;
            NSString* computed = [self sha256HexForFile:dmgURL];
            // Corruption heuristic only — never a trust decision. The §5.4
            // signature + Team ID + stapled-ticket gate is the sole trust boundary.
            if (computed.length && hexDigest.length &&
                [computed caseInsensitiveCompare:hexDigest] != NSOrderedSame) {
                if (outError) *outError = spdf_make_error(@"The downloaded update appears to be corrupted.");
                return;
            }
        }

        // 5.4 Verify the DMG offline BEFORE mounting.
        [self setProgressIndeterminateOnMain:@"Verifying signature…"];
        NSError* verifyErr = nil;
        if (!spdf_verify_signed_bundle(dmgURL, /*isApp=*/NO, &verifyErr)) {
            if (outError)
                *outError = spdf_make_error(@"The update could not be verified and was not installed.");
            return;
        }

        // 5.5–5.7 Mount, glob-discover inner .app, ditto extract, re-verify, detach.
        [self setProgressIndeterminateOnMain:@"Preparing update…"];
        NSString* mountPoint = nil;
        NSString* extractedApp = nil;
        @try {
            mountPoint = [self attachDMG:dmgURL error:outError];
            if (!mountPoint) return;

            NSString* innerApp = [self discoverInnerAppAtMount:mountPoint error:outError];
            if (!innerApp) return;

            extractedApp = [stagingURL.path stringByAppendingPathComponent:@"ShenzhenPDF.app"];
            [fm removeItemAtPath:extractedApp error:nil];
            if (![self ditto:innerApp to:extractedApp]) {
                if (outError) *outError = spdf_make_error(@"The update could not be extracted.");
                return;
            }
        } @finally {
            if (mountPoint) [self detachMount:mountPoint];
        }

        // 5.6 Re-verify the extracted app offline.
        NSError* appVerifyErr = nil;
        if (!spdf_verify_signed_bundle([NSURL fileURLWithPath:extractedApp], /*isApp=*/YES, &appVerifyErr)) {
            if (outError)
                *outError = spdf_make_error(@"The update could not be verified and was not installed.");
            return;
        }
        // Tag/version cross-check (catches swapped payload / asset-tag mismatch).
        NSString* extractedVersion = spdf_bundle_short_version(extractedApp);
        NSArray<NSNumber*>* tagPrimary = spdf_version_components(tag);
        NSArray<NSNumber*>* appPrimary = spdf_version_components(extractedVersion);
        // Compare only the YY.M.DD primary key (tag may carry -BUILD; plist may not).
        if (tagPrimary.count >= 3 && appPrimary.count >= 3) {
            if (!(tagPrimary[0].longLongValue == appPrimary[0].longLongValue &&
                  tagPrimary[1].longLongValue == appPrimary[1].longLongValue &&
                  tagPrimary[2].longLongValue == appPrimary[2].longLongValue)) {
                if (outError)
                    *outError = spdf_make_error(@"The update did not match the published version.");
                return;
            }
        }

        // 5.7 Strip quarantine defensively.
        [self stripQuarantine:extractedApp];

        // 5.8/E Point-of-no-return confirm, then spawn the detached helper.
        __block BOOL proceed = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{ proceed = [self confirmInstallNow]; });
        if (!proceed) {
            [self dismissProgressOnMain];
            return;  // user cancelled before the swap; bundle untouched
        }

        // Record the pending tag so the relaunched process can confirm, and
        // refresh the lease timestamp so it stays "recent" across the swap.
        [self withLockedUpdateStore:^BOOL(NSMutableDictionary* update) {
          update[@"pendingTag"] = tag;
          update[@"updateInProgress"] =
              @{@"pid" : @(getpid()), @"timestamp" : @([NSDate date].timeIntervalSince1970)};
          return YES;
        }];

        [self dismissProgressOnMain];
        // Set our own _terminateOnlyThisProcess so an incoming sibling-cascade
        // terminate can't pre-empt the helper spawn, then quit siblings via the
        // quit-for-update notification (which sets the same flag in each sibling
        // so they don't re-broadcast the N-squared terminate storm).
        dispatch_sync(dispatch_get_main_queue(), ^{
          id delegate = NSApp.delegate;
          if ([delegate respondsToSelector:@selector(prepareForUpdateTerminate)])
              [delegate performSelector:@selector(prepareForUpdateTerminate)];
        });
        [self quitSiblingsForUpdate];
        [self spawnPostUpdateHelperStaged:extractedApp target:bundlePath];
        if (outHelperLaunched) *outHelperLaunched = YES;

        // Parent exits so the helper (already detached via setsid) can swap.
        dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
    } @finally {
        // Leave the staging dir to the helper / next-launch sweep on success;
        // on any early return the lease release + sweep handle cleanup.
    }
}

// ----- download task ----------------------------------------------------------

- (NSURL*)downloadAssetFrom:(NSString*)urlString
                  assetSize:(long long)assetSize
                  stagingURL:(NSURL*)stagingURL
                        tag:(NSString*)tag
                      error:(NSError**)outError {
    NSURL* url = [NSURL URLWithString:urlString];
    if (![url.scheme isEqualToString:@"https"]) {
        if (outError) *outError = spdf_make_error(@"The update download URL was not secure.");
        return nil;
    }
    _redirectCount = 0;
    _expectedAssetSize = assetSize;
    _downloadStagingURL = stagingURL;
    _pendingTag = tag;
    _userCancelled = NO;

    NSURLSessionConfiguration* config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.waitsForConnectivity = NO;
    _downloadSession = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 60.0;
    [request setValue:[self userAgent] forHTTPHeaderField:@"User-Agent"];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSURL* resultURL = nil;
    __block NSError* resultError = nil;
    _downloadCompletion = ^(NSURL* location, NSError* error) {
      resultURL = location;
      resultError = error;
      dispatch_semaphore_signal(sem);
    };
    _downloadTask = [_downloadSession downloadTaskWithRequest:request];
    [_downloadTask resume];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    [_downloadSession finishTasksAndInvalidate];
    _downloadSession = nil;
    _downloadTask = nil;
    _downloadCompletion = nil;

    if (_userCancelled) return nil;  // silent
    if (resultError || !resultURL) {
        if (outError) *outError = spdf_make_error(@"The update could not be downloaded.");
        return nil;
    }

    NSString* dest = [stagingURL.path stringByAppendingPathComponent:kSPDFAssetName];
    [NSFileManager.defaultManager removeItemAtPath:dest error:nil];
    NSError* moveErr = nil;
    if (![NSFileManager.defaultManager moveItemAtURL:resultURL toURL:[NSURL fileURLWithPath:dest] error:&moveErr]) {
        if (outError) *outError = spdf_make_error(@"The downloaded update could not be saved.");
        return nil;
    }
    return [NSURL fileURLWithPath:dest];
}

// https-only on every redirect hop + bounded redirect count.
- (void)URLSession:(NSURLSession*)session
                          task:(NSURLSessionTask*)task
    willPerformHTTPRedirection:(NSHTTPURLResponse*)response
                    newRequest:(NSURLRequest*)request
             completionHandler:(void (^)(NSURLRequest* _Nullable))completionHandler {
    (void)session;
    (void)task;
    (void)response;
    if (++_redirectCount > kSPDFMaxRedirects || ![request.URL.scheme isEqualToString:@"https"]) {
        completionHandler(nil);  // reject downgrade / runaway redirect
        return;
    }
    completionHandler(request);
}

- (void)URLSession:(NSURLSession*)session
                 downloadTask:(NSURLSessionDownloadTask*)downloadTask
                 didWriteData:(int64_t)bytesWritten
            totalBytesWritten:(int64_t)totalBytesWritten
    totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    (void)session;
    (void)bytesWritten;
    // Zip-bomb cap. The written-bytes ceiling is the HARD bound and is always
    // evaluated, even for chunked/CDN responses where totalBytesExpectedToWrite
    // is -1 (in which case the declared-length early-reject below simply doesn't
    // fire). When asset.size is absent the ceiling falls back to the 64MB max.
    long long ceiling = _expectedAssetSize > 0 ? MIN(_expectedAssetSize + 1, kSPDFMaxDownloadBytes) : kSPDFMaxDownloadBytes;
    if (totalBytesWritten > ceiling ||
        (totalBytesExpectedToWrite > 0 && totalBytesExpectedToWrite > kSPDFMaxDownloadBytes)) {
        [downloadTask cancel];
        return;
    }
    long long total = _expectedAssetSize > 0 ? _expectedAssetSize : totalBytesExpectedToWrite;
    dispatch_async(dispatch_get_main_queue(), ^{
      [self updateProgress:(double)totalBytesWritten total:(double)total];
    });
}

- (void)URLSession:(NSURLSession*)session
                 downloadTask:(NSURLSessionDownloadTask*)downloadTask
    didFinishDownloadingToURL:(NSURL*)location {
    (void)session;
    (void)downloadTask;
    // Move out of the per-task temp location synchronously (it is deleted on
    // return). Move DIRECTLY into the same-volume staging dir so this is a rename
    // (not a cross-volume copy of the ~33MB DMG via NSTemporaryDirectory, which
    // may live on a different volume and undercut the 3x free-space precheck).
    NSURL* destDir = _downloadStagingURL ?: [NSURL fileURLWithPath:NSTemporaryDirectory()];
    NSURL* tmp = [destDir URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSError* err = nil;
    if (![NSFileManager.defaultManager moveItemAtURL:location toURL:tmp error:&err]) {
        if (_downloadCompletion) _downloadCompletion(nil, err);
        return;
    }
    if (_downloadCompletion) _downloadCompletion(tmp, nil);
}

- (void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task didCompleteWithError:(NSError*)error {
    (void)session;
    (void)task;
    if (error && _downloadCompletion) _downloadCompletion(nil, error);
}

- (NSString*)sha256HexForFile:(NSURL*)url {
    NSFileHandle* fh = [NSFileHandle fileHandleForReadingFromURL:url error:nil];
    if (!fh) return nil;
    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);
    while (1) {
        @autoreleasepool {
            NSData* chunk = [fh readDataOfLength:1 << 20];
            if (chunk.length == 0) break;
            CC_SHA256_Update(&ctx, chunk.bytes, (CC_LONG)chunk.length);
        }
    }
    [fh closeFile];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &ctx);
    NSMutableString* hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; ++i) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

// ----- hdiutil mount / discover / detach --------------------------------------

- (NSData*)runTool:(NSString*)launchPath arguments:(NSArray<NSString*>*)args {
    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:launchPath];
    task.arguments = args;
    NSPipe* outPipe = [NSPipe pipe];
    task.standardOutput = outPipe;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    NSError* err = nil;
    if (![task launchAndReturnError:&err]) return nil;
    NSData* data = [outPipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    if (task.terminationStatus != 0) return nil;
    return data;
}

- (NSString*)attachDMG:(NSURL*)dmgURL error:(NSError**)outError {
    NSData* plistData = [self runTool:@"/usr/bin/hdiutil"
                            arguments:@[ @"attach", @"-nobrowse", @"-readonly", @"-noautoopen", @"-plist",
                                         dmgURL.path ]];
    if (!plistData) {
        if (outError) *outError = spdf_make_error(@"The update disk image could not be opened.");
        return nil;
    }
    id plist = [NSPropertyListSerialization propertyListWithData:plistData options:0 format:nil error:nil];
    NSArray* entities = [plist isKindOfClass:NSDictionary.class] ? plist[@"system-entities"] : nil;
    NSString* mountPoint = nil;
    for (NSDictionary* entity in entities) {
        NSString* mp = entity[@"mount-point"];
        if ([mp isKindOfClass:NSString.class] && mp.length) {
            mountPoint = mp;  // the real mount-point of THIS attach
            break;
        }
    }
    if (!mountPoint) {
        if (outError) *outError = spdf_make_error(@"The update disk image had no mount point.");
        return nil;
    }
    return mountPoint;
}

- (NSString*)discoverInnerAppAtMount:(NSString*)mountPoint error:(NSError**)outError {
    NSFileManager* fm = NSFileManager.defaultManager;
    NSArray<NSString*>* entries = [fm contentsOfDirectoryAtPath:mountPoint error:nil];
    NSString* found = nil;
    NSUInteger matches = 0;
    for (NSString* entry in entries) {
        if (![entry.pathExtension isEqualToString:@"app"]) continue;
        NSString* full = [mountPoint stringByAppendingPathComponent:entry];
        NSDictionary* attrs = [fm attributesOfItemAtPath:full error:nil];
        if ([attrs[NSFileType] isEqualToString:NSFileTypeSymbolicLink]) continue;  // skip Applications symlink
        NSString* bundleID = [NSBundle bundleWithPath:full].bundleIdentifier;
        if (![bundleID isEqualToString:kSPDFAppBundleID]) continue;
        found = full;
        ++matches;
    }
    if (matches != 1) {
        if (outError) *outError = spdf_make_error(@"The update disk image did not contain Shenzhen PDF.");
        return nil;
    }
    return found;
}

- (BOOL)ditto:(NSString*)src to:(NSString*)dst {
    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ditto"];
    task.arguments = @[ src, dst ];
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![task launchAndReturnError:nil]) return NO;
    [task waitUntilExit];
    return task.terminationStatus == 0;
}

- (void)detachMount:(NSString*)mountPoint {
    NSData* out = [self runTool:@"/usr/bin/hdiutil" arguments:@[ @"detach", mountPoint ]];
    if (!out) [self runTool:@"/usr/bin/hdiutil" arguments:@[ @"detach", @"-force", mountPoint ]];
}

- (void)stripQuarantine:(NSString*)appPath {
    [self runTool:@"/usr/bin/xattr" arguments:@[ @"-dr", @"com.apple.quarantine", appPath ]];
}

// Enumerate the install volume's per-user NSItemReplacementDirectory temp area
// and remove orphaned SPDF staging dirs (each can hold a full extracted .app +
// DMG) older than the lease ceiling. An interrupted update otherwise leaks tens
// of MB per attempt with no reclamation, and a lingering staged .app is added
// TOCTOU surface. Best-effort; never blocks an update.
- (void)sweepStaleStagingDirs {
    if (spdf_is_sandboxed()) return;
    NSFileManager* fm = NSFileManager.defaultManager;
    NSURL* bundleURL = NSBundle.mainBundle.bundleURL;
    NSURL* parentURL = bundleURL.URLByDeletingLastPathComponent;

    // NSItemReplacementDirectory dirs are created under the volume's hidden
    // .TemporaryItems area, resolved relative to the install target's parent.
    // Probe one (create:NO) to learn the container directory, then sweep
    // siblings of it that hold our staged ShenzhenPDF.app and are older than the
    // lease ceiling. A live update holds update.lock during its own staging, so
    // we never race an in-flight run (this runs before performNetworkCheck).
    NSError* err = nil;
    NSURL* probe = [fm URLForDirectory:NSItemReplacementDirectory
                             inDomain:NSUserDomainMask
                    appropriateForURL:parentURL
                               create:YES
                                error:&err];
    if (!probe) return;
    NSURL* container = probe.URLByDeletingLastPathComponent;
    [fm removeItemAtURL:probe error:nil];  // remove the throwaway probe itself

    NSDate* cutoff = [NSDate dateWithTimeIntervalSinceNow:-kSPDFLeaseStaleAfter];
    NSArray<NSURL*>* entries = [fm contentsOfDirectoryAtURL:container
                                includingPropertiesForKeys:@[ NSURLContentModificationDateKey ]
                                                   options:0
                                                     error:nil];
    for (NSURL* entry in entries) {
        NSString* staged = [entry.path stringByAppendingPathComponent:@"ShenzhenPDF.app"];
        NSString* stagedDmg = [entry.path stringByAppendingPathComponent:kSPDFAssetName];
        if (![fm fileExistsAtPath:staged] && ![fm fileExistsAtPath:stagedDmg]) continue;
        NSDate* mtime = nil;
        [entry getResourceValue:&mtime forKey:NSURLContentModificationDateKey error:nil];
        if (mtime && [mtime compare:cutoff] == NSOrderedDescending) continue;  // recent; leave it
        [fm removeItemAtURL:entry error:nil];
    }
}

- (void)consumePendingUpdateMarkerAndSweep {
    if (spdf_is_sandboxed()) return;

    NSFileManager* fm = NSFileManager.defaultManager;
    NSString* bundlePath = NSBundle.mainBundle.bundleURL.path;
    NSString* oldPath = [bundlePath stringByAppendingString:@".old"];
    NSString* running = [self runningVersion];

    __block NSString* pendingTag = nil;
    [self withLockedUpdateStore:^BOOL(NSMutableDictionary* update) {
      id pt = update[@"pendingTag"];
      if ([pt isKindOfClass:NSString.class] && [(NSString*)pt length]) pendingTag = pt;
      return NO;
    }];

    if (pendingTag.length == 0) {
        // No update in flight. Sweep any aged orphaned .old left by a prior run.
        if ([fm fileExistsAtPath:oldPath]) {
            NSDictionary* attrs = [fm attributesOfItemAtPath:oldPath error:nil];
            NSDate* mtime = attrs[NSFileModificationDate];
            if (!mtime || [mtime timeIntervalSinceNow] < -kSPDFLeaseStaleAfter)
                [fm removeItemAtPath:oldPath error:nil];
        }
        [self sweepStaleStagingDirs];
        return;
    }

    // Compare only the YY.M.DD primary key (tag may carry -BUILD; plist may not).
    BOOL versionMatches = NO;
    if (running.length) {
        NSArray<NSNumber*>* tagP = spdf_version_components(pendingTag);
        NSArray<NSNumber*>* runP = spdf_version_components(running);
        if (tagP.count >= 3 && runP.count >= 3)
            versionMatches = (tagP[0].longLongValue == runP[0].longLongValue &&
                              tagP[1].longLongValue == runP[1].longLongValue &&
                              tagP[2].longLongValue == runP[2].longLongValue);
    }

    if (versionMatches) {
        // Healthy: write update_ok, delete .old, clear pendingTag + lease.
        NSString* okTag = pendingTag;
        [self withLockedUpdateStore:^BOOL(NSMutableDictionary* update) {
          update[@"update_ok"] = okTag;
          [update removeObjectForKey:@"pendingTag"];
          [update removeObjectForKey:@"updateInProgress"];
          return YES;
        }];
        [fm removeItemAtPath:oldPath error:nil];
        [self sweepStaleStagingDirs];
        // State I: one-time success banner.
        dispatch_async(dispatch_get_main_queue(), ^{
          NSAlert* alert = [[NSAlert alloc] init];
          alert.messageText = [NSString stringWithFormat:@"You're now on Shenzhen PDF %@.", okTag];
          alert.informativeText = @"";
          [alert runModal];
        });
        return;
    }

    // pendingTag set but the running version does NOT match it. We are running
    // (so this bundle is functional); the most likely cause is the helper's
    // swap never took (we're the OLD binary still in place) or the new version
    // launched once, failed, and the user reopened the OLD bundle. Do NOT
    // destructively rename the currently-running working bundle. Instead reveal
    // the retained .old (so a user whose update half-applied has the prior good
    // copy to hand), remove it once revealed, and clear the lifecycle state.
    if ([fm fileExistsAtPath:oldPath]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [NSWorkspace.sharedWorkspace
              activateFileViewerSelectingURLs:@[ [NSURL fileURLWithPath:oldPath] ]];
        });
        // Leave .old on disk for the user to recover from; the aged-orphan sweep
        // (lease ceiling) reclaims it on a later clean launch.
    }
    [self withLockedUpdateStore:^BOOL(NSMutableDictionary* update) {
      [update removeObjectForKey:@"pendingTag"];
      [update removeObjectForKey:@"updateInProgress"];
      return YES;
    }];
    [self sweepStaleStagingDirs];
}

// ----- liveness lease ---------------------------------------------------------

- (BOOL)acquireLease {
    __block BOOL acquired = NO;
    [self withLockedUpdateStore:^BOOL(NSMutableDictionary* update) {
      NSDictionary* lease = update[@"updateInProgress"];
      if ([lease isKindOfClass:NSDictionary.class]) {
          pid_t pid = (pid_t)[lease[@"pid"] intValue];
          NSTimeInterval ts = [lease[@"timestamp"] doubleValue];
          BOOL alive = (pid > 0 && kill(pid, 0) == 0);
          BOOL recent = ([NSDate date].timeIntervalSince1970 - ts) < kSPDFLeaseStaleAfter;
          if (alive && recent && pid != getpid()) return NO;  // genuinely held
      }
      update[@"updateInProgress"] = @{@"pid" : @(getpid()), @"timestamp" : @([NSDate date].timeIntervalSince1970)};
      acquired = YES;
      return YES;
    }];
    return acquired;
}

- (BOOL)liveLeaseHeldByOther {
    __block BOOL held = NO;
    [self withLockedUpdateStore:^BOOL(NSMutableDictionary* update) {
      NSDictionary* lease = update[@"updateInProgress"];
      if ([lease isKindOfClass:NSDictionary.class]) {
          pid_t pid = (pid_t)[lease[@"pid"] intValue];
          NSTimeInterval ts = [lease[@"timestamp"] doubleValue];
          BOOL alive = (pid > 0 && kill(pid, 0) == 0);
          BOOL recent = ([NSDate date].timeIntervalSince1970 - ts) < kSPDFLeaseStaleAfter;
          if (alive && recent && pid != getpid()) held = YES;
      }
      return NO;
    }];
    return held;
}

- (void)releaseLease {
    [self withLockedUpdateStore:^BOOL(NSMutableDictionary* update) {
      if (update[@"updateInProgress"]) {
          [update removeObjectForKey:@"updateInProgress"];
          return YES;
      }
      return NO;
    }];
}

// ----- sibling quit + helper spawn --------------------------------------------

- (void)quitSiblingsForUpdate {
    // Post a distributed "quit for update" request rather than calling
    // [app terminate] directly. Each sibling observes this, sets
    // _terminateOnlyThisProcess=YES (so it does NOT re-broadcast terminate to
    // every other process — the N-squared cascade), writes its session
    // synchronously, and exits. The helper's bounded poll + forceTerminate
    // escalation (§5.8) is the backstop for any sibling that doesn't honour it.
    [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName:@"com.intuition.shenzhenpdf.QuitForUpdate"
                      object:nil
                    userInfo:nil
          deliverImmediately:YES];
}

- (void)spawnPostUpdateHelperStaged:(NSString*)stagedApp target:(NSString*)targetBundle {
    NSString* executable = NSBundle.mainBundle.executablePath;
    if (executable.length == 0) return;
    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:executable];
    task.arguments = @[ @"--post-update", stagedApp, targetBundle ];
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    [task launchAndReturnError:nil];
}

// ----- UI: progress panel -----------------------------------------------------

- (NSWindow*)mainWindow {
    return NSApp.keyWindow ?: NSApp.mainWindow ?: NSApp.windows.firstObject;
}

- (void)showProgressOnMain:(NSString*)tag assetSize:(long long)assetSize {
    dispatch_async(dispatch_get_main_queue(), ^{ [self buildProgressPanel:tag assetSize:assetSize]; });
}

- (void)buildProgressPanel:(NSString*)tag assetSize:(long long)assetSize {
    if (!_progressPanel) {
        _progressPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 460, 156)
                                                    styleMask:NSWindowStyleMaskTitled
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
        _progressPanel.releasedWhenClosed = NO;

        NSView* content = [[NSView alloc] initWithFrame:_progressPanel.contentView.bounds];
        content.translatesAutoresizingMaskIntoConstraints = NO;
        _progressPanel.contentView = content;

        _progressTitleLabel = [NSTextField labelWithString:@""];
        _progressTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _progressTitleLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
        [content addSubview:_progressTitleLabel];

        _progressDetailLabel = [NSTextField labelWithString:@""];
        _progressDetailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _progressDetailLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [content addSubview:_progressDetailLabel];

        _progressIndicator = [[NSProgressIndicator alloc] init];
        _progressIndicator.translatesAutoresizingMaskIntoConstraints = NO;
        _progressIndicator.style = NSProgressIndicatorStyleBar;
        _progressIndicator.indeterminate = NO;
        _progressIndicator.minValue = 0.0;
        [content addSubview:_progressIndicator];

        _progressCancelButton = [NSButton buttonWithTitle:@"Cancel"
                                                   target:self
                                                   action:@selector(cancelUpdate:)];
        _progressCancelButton.translatesAutoresizingMaskIntoConstraints = NO;
        [content addSubview:_progressCancelButton];

        [NSLayoutConstraint activateConstraints:@[
            [_progressTitleLabel.topAnchor constraintEqualToAnchor:content.topAnchor constant:16],
            [_progressTitleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:18],
            [_progressTitleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-18],
            [_progressDetailLabel.topAnchor constraintEqualToAnchor:_progressTitleLabel.bottomAnchor constant:8],
            [_progressDetailLabel.leadingAnchor constraintEqualToAnchor:_progressTitleLabel.leadingAnchor],
            [_progressDetailLabel.trailingAnchor constraintEqualToAnchor:_progressTitleLabel.trailingAnchor],
            [_progressIndicator.topAnchor constraintEqualToAnchor:_progressDetailLabel.bottomAnchor constant:14],
            [_progressIndicator.leadingAnchor constraintEqualToAnchor:_progressTitleLabel.leadingAnchor],
            [_progressIndicator.trailingAnchor constraintEqualToAnchor:_progressTitleLabel.trailingAnchor],
            [_progressCancelButton.topAnchor constraintEqualToAnchor:_progressIndicator.bottomAnchor constant:16],
            [_progressCancelButton.trailingAnchor constraintEqualToAnchor:_progressTitleLabel.trailingAnchor],
        ]];
    }

    _progressPanel.title = @"Software Update";
    _progressTitleLabel.stringValue = [NSString stringWithFormat:@"Downloading Shenzhen PDF %@", tag ?: @""];
    _progressDetailLabel.stringValue = @"Starting…";
    _progressIndicator.indeterminate = (assetSize <= 0);
    _progressIndicator.minValue = 0.0;
    _progressIndicator.maxValue = MAX(1.0, (double)assetSize);
    _progressIndicator.doubleValue = 0.0;
    _progressCancelButton.enabled = YES;
    if (_progressIndicator.indeterminate) [_progressIndicator startAnimation:nil];
    else [_progressIndicator stopAnimation:nil];
    [_progressPanel center];
    [_progressPanel makeKeyAndOrderFront:nil];
}

- (void)updateProgress:(double)written total:(double)total {
    if (!_progressPanel || _progressIndicator.indeterminate) return;
    _progressIndicator.doubleValue = written;
    double mbW = written / (1024.0 * 1024.0);
    double mbT = total / (1024.0 * 1024.0);
    _progressDetailLabel.stringValue = [NSString stringWithFormat:@"%.1f MB of %.1f MB", mbW, mbT];
    _progressIndicator.accessibilityValue = @(total > 0 ? written / total : 0.0);
}

- (void)setProgressIndeterminateOnMain:(NSString*)detail {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!self->_progressPanel) return;
      self->_progressIndicator.indeterminate = YES;
      [self->_progressIndicator startAnimation:nil];
      self->_progressDetailLabel.stringValue = detail ?: @"";
      NSAccessibilityPostNotificationWithUserInfo(
          self->_progressPanel, NSAccessibilityAnnouncementRequestedNotification,
          @{NSAccessibilityAnnouncementKey : detail ?: @""});
    });
}

- (void)dismissProgressOnMain {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self->_progressPanel orderOut:nil];
    });
}

- (void)cancelUpdate:(id)sender {
    (void)sender;
    _userCancelled = YES;
    [_downloadTask cancel];
    [_progressPanel orderOut:nil];
}

- (BOOL)confirmInstallNow {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Shenzhen PDF will close all windows and reopen them to finish updating.";
    alert.informativeText = @"";
    [alert addButtonWithTitle:@"Install Now"];
    [alert addButtonWithTitle:@"Cancel"];
    return [alert runModal] == NSAlertFirstButtonReturn;
}

// ----- UI: simple alerts ------------------------------------------------------

- (void)showUpToDate {
    NSString* version = [self runningVersion] ?: @"";
    dispatch_async(dispatch_get_main_queue(), ^{
      NSAlert* alert = [[NSAlert alloc] init];
      alert.messageText = @"You're up to date.";
      alert.informativeText = [NSString stringWithFormat:@"Shenzhen PDF %@ is the latest version.", version];
      [alert runModal];
    });
}

- (void)showErrorOnMain:(NSString*)detail {
    dispatch_async(dispatch_get_main_queue(), ^{
      id<SPDFUpdaterHostBridge> bridge = [self hostBridge];
      if ([bridge respondsToSelector:@selector(showError:detail:)])
          [bridge showError:@"Software Update" detail:detail];
      else
          [self showInfo:@"Software Update" detail:detail];
    });
}

- (void)showInfo:(NSString*)message detail:(NSString*)detail {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = message;
    alert.informativeText = detail ?: @"";
    [alert runModal];
}

- (void)showInfoOnMain:(NSString*)message detail:(NSString*)detail {
    dispatch_async(dispatch_get_main_queue(), ^{ [self showInfo:message detail:detail]; });
}

@end
