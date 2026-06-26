#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runtime-gated GitHub-release self-updater for the non-sandboxed Developer ID
/// build. Every entry point early-returns when spdf_is_sandboxed() is YES, so the
/// one binary that also ships to the App Store never self-updates.
@interface SPDFUpdater : NSObject

+ (instancetype)shared;

/// Launch hook. Runs strictly after first paint, in the primary process only.
/// Sandbox gate -> autoUpdate gate -> flock'd 24h gate -> Background-QoS check.
- (void)scheduleDailyUpdateCheckIfNeeded;

/// Launch-time post-update health handshake (§5.9.6 / §5.10). Runs in the
/// primary process only, before scheduleDailyUpdateCheckIfNeeded. Under
/// update.lock: if pendingTag matches the now-running version, writes update_ok,
/// deletes <bundle>.app.old, clears the lease, and shows the one-time success
/// banner; if pendingTag is set but the running version does NOT match it (the
/// new version failed to come up), rolls <bundle>.app.old back into place and
/// reveals it in Finder. Always sweeps an aged orphaned .old / staging dirs.
- (void)consumePendingUpdateMarkerAndSweep;

/// The "Check for Updates…" menu path passes userInitiated=YES (bypasses the
/// 24h gate, ignores Skip/Later, surfaces both up-to-date and failure states).
/// The silent daily path passes NO.
- (void)checkForUpdatesUserInitiated:(BOOL)userInitiated;

@end

#ifdef __cplusplus
extern "C" {
#endif

/// YES on the sandboxed (App Store / TestFlight) build, NO on the Developer ID
/// build. Inspects the dynamic code-signing entitlements dict for
/// com.apple.security.app-sandbox, corroborated by APP_SANDBOX_CONTAINER_ID.
BOOL spdf_is_sandboxed(void);

/// Numeric per-field comparison of "YY.M.DD-BUILD" version strings split on
/// "[. -]". YY.M.DD is the primary key; -BUILD is a same-day tiebreaker.
/// Malformed input compares as ordered-same. Never lexical.
NSComparisonResult spdf_compare_versions(NSString* _Nullable a, NSString* _Nullable b);

/// Offline Security.framework verification of a signed DMG (isApp == NO) or an
/// extracted .app (isApp == YES). Requires the full Developer ID requirement
/// (Apple anchor + WWDR marker + Developer ID Application leaf marker) plus a
/// pinned Team ID 66LJ4BV7Q3. For an app it additionally asserts the
/// hardened-runtime flag and bundle id com.intuition.shenzhenpdf. For the DMG it
/// additionally requires a valid stapled notarization ticket. Returns NO and
/// fills *error on any failure. This is the sole anti-tamper trust boundary.
BOOL spdf_verify_signed_bundle(NSURL* url, BOOL isApp, NSError* _Nullable* _Nullable error);

/// Foundation-only swap/relaunch helper invoked from main()'s --post-update
/// short-circuit, running from the CURRENT trusted in-place binary. Polls until
/// siblings exit, swaps via move-aside two-rename, re-registers Launch Services,
/// relaunches, and rolls back on failure. Returns 0 on success.
int spdf_run_post_update_helper(NSString* stagedAppPath, NSString* targetBundlePath);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
