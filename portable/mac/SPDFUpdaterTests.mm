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
    }
    if (gFailureCount > 0) {
        fprintf(stderr, "SPDFUpdaterTests: %d failure(s)\n", gFailureCount);
        return 1;
    }
    printf("SPDFUpdaterTests passed (6 cases)\n");
    return 0;
}
