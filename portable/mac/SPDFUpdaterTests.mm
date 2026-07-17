#import <Foundation/Foundation.h>

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
    }
    if (gFailureCount > 0) {
        fprintf(stderr, "SPDFUpdaterTests: %d failure(s)\n", gFailureCount);
        return 1;
    }
    printf("SPDFUpdaterTests passed (11 cases)\n");
    return 0;
}
