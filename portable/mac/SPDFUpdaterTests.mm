#import <AppKit/AppKit.h>

#import "SPDFUpdater.h"

static int gFailureCount = 0;

static const char* order_name(NSComparisonResult r) {
    switch (r) {
        case NSOrderedAscending: return "Ascending";
        case NSOrderedSame: return "Same";
        case NSOrderedDescending: return "Descending";
    }
    return "?";
}

static void expect(NSString* label, NSComparisonResult actual, NSComparisonResult expected) {
    if (actual != expected) {
        fprintf(stderr, "FAIL %s: expected %s, got %s\n", label.UTF8String, order_name(expected),
                order_name(actual));
        ++gFailureCount;
    }
}

static void expectString(NSString* label, NSString* actual, NSString* expected) {
    if (![actual isEqualToString:expected]) {
        fprintf(stderr, "FAIL %s:\n  expected: %s\n  got:      %s\n", label.UTF8String,
                expected.UTF8String, actual.UTF8String);
        ++gFailureCount;
    }
}

static void expectDelay(NSString* label, NSTimeInterval actual, NSTimeInterval expected) {
    if (actual != expected) {
        fprintf(stderr, "FAIL %s: expected %.1f, got %.1f\n", label.UTF8String, expected, actual);
        ++gFailureCount;
    }
}

static void expectBool(NSString* label, BOOL actual, BOOL expected) {
    if (actual != expected) {
        fprintf(stderr, "FAIL %s: expected %d, got %d\n", label.UTF8String, expected, actual);
        ++gFailureCount;
    }
}

int main(int argc, char** argv) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        // 1. 26.6.25 > 26.6.4 (non-padded day; lexical would be wrong)
        expect(@"non-padded day", spdf_compare_versions(@"26.6.25", @"26.6.4"), NSOrderedDescending);

        // 2. 26.6.11 > 26.6.4 (multi-digit day)
        expect(@"multi-digit day", spdf_compare_versions(@"26.6.11", @"26.6.4"), NSOrderedDescending);

        // 3. 26.6.19-3 > 26.6.19-1 (build tiebreaker)
        expect(@"build tiebreaker", spdf_compare_versions(@"26.6.19-3", @"26.6.19-1"), NSOrderedDescending);

        // 4. 26.6.25-1 == 26.6.25-1 (no update)
        expect(@"equality", spdf_compare_versions(@"26.6.25-1", @"26.6.25-1"), NSOrderedSame);

        // 5. malformed input -> ordered-same / no update
        expect(@"malformed", spdf_compare_versions(@"not-a-version", @"26.6.25-1"), NSOrderedSame);

        // 6. downgrade feed: tag < highestVersionSeen -> no update, even when tag > running.
        //    running = 26.6.4, highestVersionSeen = 26.6.25, feed tag = 26.6.19.
        NSString* running = @"26.6.4-1";
        NSString* highestSeen = @"26.6.25-1";
        NSString* feedTag = @"26.6.19-3";
        BOOL isNewerThanRunning = (spdf_compare_versions(feedTag, running) == NSOrderedDescending);
        BOOL isDowngradeVsHighWater = (spdf_compare_versions(feedTag, highestSeen) == NSOrderedAscending);
        BOOL updateOffered = isNewerThanRunning && !isDowngradeVsHighWater;
        if (!(isNewerThanRunning && isDowngradeVsHighWater && !updateOffered)) {
            fprintf(stderr, "FAIL downgrade feed: newer=%d downgrade=%d offered=%d\n", isNewerThanRunning,
                    isDowngradeVsHighWater, updateOffered);
            ++gFailureCount;
        }

        // 7. Alert notes: bullets become "• " lines, breaks preserved, details
        //    below the first horizontal rule dropped.
        NSString* notes = spdf_format_release_notes_for_alert(
            @"- First **bold** highlight\n- Second `code` highlight\n\n---\n\n### Details\n- hidden detail\n");
        expectString(@"bullet formatting", notes, @"• First bold highlight\n• Second code highlight");

        // 8. Hard-wrapped continuation lines rejoin their bullet; blank runs collapse.
        notes = spdf_format_release_notes_for_alert(@"- A very long line\n  that was hard-wrapped\n\n\n- Next\n***\n- gone");
        expectString(@"continuation join", notes, @"• A very long line that was hard-wrapped\n• Next");

        // 9. Headers/quotes stripped; bidi override removed; newline kept.
        notes = spdf_format_release_notes_for_alert(@"## Heads up\n> quoted\nplain \u202Etricky");
        expectString(@"markdown + bidi strip", notes, @"Heads up\nquoted\nplain tricky");

        // 10. Over-cap bodies cut on a line boundary with an ellipsis line.
        NSMutableString* longBody = [NSMutableString string];
        for (int i = 0; i < 40; i++) [longBody appendFormat:@"- highlight number %d padded out\n", i];
        notes = spdf_format_release_notes_for_alert(longBody);
        if (notes.length > 502 || ![notes hasSuffix:@"\n…"] || [notes rangeOfString:@"…"].location != notes.length - 1) {
            fprintf(stderr, "FAIL line-boundary cap: len=%lu tail=%s\n", (unsigned long)notes.length,
                    [notes substringFromIndex:notes.length - MIN(notes.length, (NSUInteger)20)].UTF8String);
            ++gFailureCount;
        }

        // 11. nil / empty input.
        expectString(@"nil body", spdf_format_release_notes_for_alert(nil), @"");

        // --- spdf_daily_check_delay: pure fire/delay decision consumed under
        //     update.lock by every trigger (launch, hourly timer, day-change,
        //     wake). 0 = due now, >0 = seconds until the gate opens, -1 = never.
        NSTimeInterval now = 1800000000.0;  // arbitrary epoch instant

        // 12. Fresh install: no lastUpdateCheck stamp yet -> due immediately.
        expectDelay(@"fresh install due now", spdf_daily_check_delay(YES, NO, 0, now), 0);

        // 13. Checked recently (2h ago) -> gated for the remaining 22h.
        expectDelay(@"checked recently gated", spdf_daily_check_delay(YES, YES, now - 7200, now),
                    86400 - 7200);

        // 14. Long sleep past the gate (last check 30h ago) -> the wake catch-up
        //     trigger must fire the check immediately.
        expectDelay(@"long sleep past gate", spdf_daily_check_delay(YES, YES, now - 30 * 3600, now), 0);

        // 15. Day changed while asleep but only 40min since the last check: the
        //     rolling 24h gate stays closed (calendar-day triggers don't defeat it).
        expectDelay(@"day change inside window", spdf_daily_check_delay(YES, YES, now - 2400, now),
                    86400 - 2400);

        // 16. autoUpdate disabled -> never fires, even when long overdue.
        expectDelay(@"autoUpdate disabled", spdf_daily_check_delay(NO, YES, now - 30 * 3600, now), -1);

        // 17-21. The extracted bundle must match the complete release tag,
        // including the same-day build suffix. Missing/malformed values fail closed.
        expectBool(@"exact bundle tag", spdf_release_tag_matches_bundle_version(@"26.8.27-2", @"26.8.27", @"2"), YES);
        expectBool(@"same-day wrong build", spdf_release_tag_matches_bundle_version(@"26.8.27-2", @"26.8.27", @"1"), NO);
        expectBool(@"wrong date", spdf_release_tag_matches_bundle_version(@"26.8.27-2", @"26.8.26", @"2"), NO);
        expectBool(@"missing build", spdf_release_tag_matches_bundle_version(@"26.8.27-2", @"26.8.27", @""), NO);
        expectBool(@"malformed bundle tag", spdf_release_tag_matches_bundle_version(@"26.8.27-2", @"26.8.x", @"2"), NO);

        // 22-26. Relaunch health requires the complete date and build.
        expectBool(@"health exact tag", spdf_release_tag_matches_running_version(@"26.8.27-2", @"26.8.27-2"), YES);
        expectBool(@"health wrong build", spdf_release_tag_matches_running_version(@"26.8.27-2", @"26.8.27-1"), NO);
        expectBool(@"health missing build", spdf_release_tag_matches_running_version(@"26.8.27-2", @"26.8.27"), NO);
        expectBool(@"health wrong date", spdf_release_tag_matches_running_version(@"26.8.27-2", @"26.8.26-2"), NO);
        expectBool(@"health malformed", spdf_release_tag_matches_running_version(@"26.8.27-2", @"broken"), NO);

        // 27. The preview harness and production prompt share this exact alert
        // constructor, including release-note formatting and button order.
        NSAlert* alert = spdf_make_update_available_alert(@"26.8.27-2", @"26.7.17-1", @"- **Fast** update\n---\nHidden");
        expectString(@"alert title", alert.messageText, @"A new version of Shenzhen PDF is available");
        expectBool(@"alert formatted notes", [alert.informativeText containsString:@"• Fast update"], YES);
        expectString(@"alert primary action", alert.buttons.firstObject.title, @"Install and Relaunch");
    }
    if (gFailureCount > 0) {
        fprintf(stderr, "SPDFUpdaterTests: %d failure(s)\n", gFailureCount);
        return 1;
    }
    printf("SPDFUpdaterTests passed (27 cases)\n");
    return 0;
}
