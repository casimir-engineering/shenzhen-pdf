// The chapter list's nesting rules, tested without a table view: rows carry a
// level, and everything the reader sees -- which rows have a triangle, what a
// collapse hides, and what is remembered per file -- is derived from that.

#import <Foundation/Foundation.h>

#import "SPDFMacSidebarOutline.h"

static int gFailures;

static void Expect(const char* what, BOOL condition) {
    if (condition) return;
    fprintf(stderr, "FAIL: %s\n", what);
    ++gFailures;
}

static NSArray<NSNumber*>* Levels(NSArray<NSNumber*>* levels) { return levels; }

static NSString* VisibleString(NSArray<NSNumber*>* levels, NSSet<NSString*>* collapsed) {
    NSIndexSet* visible = spdf_sidebar_outline_visible_indexes(levels, collapsed);
    NSMutableString* out = [NSMutableString string];
    [visible enumerateIndexesUsingBlock:^(NSUInteger i, BOOL* stop) {
      (void)stop;
      if (out.length) [out appendString:@","];
      [out appendFormat:@"%lu", (unsigned long)i];
    }];
    return out;
}

int main(void) {
    @autoreleasepool {
        // A README-shaped outline: one H1, two H2s, the first with two H3s.
        //   0 Title          level 0   key 0
        //   1   Install      level 1   key 0.0
        //   2     macOS      level 2   key 0.0.0
        //   3     Linux      level 2   key 0.0.1
        //   4   Usage        level 1   key 0.1
        NSArray<NSNumber*>* doc = Levels(@[ @0, @1, @2, @2, @1 ]);

        // --- Which rows get a triangle ---------------------------------
        Expect("a row with a deeper row after it has children", spdf_sidebar_outline_has_children(doc, 0));
        Expect("a row whose next sibling is at its level has none", !spdf_sidebar_outline_has_children(doc, 2));
        Expect("the last row never has children", !spdf_sidebar_outline_has_children(doc, 4));

        // --- Keys are positional, so duplicate titles stay distinct -----
        Expect("the root's key", [spdf_sidebar_outline_key(doc, 0) isEqualToString:@"0"]);
        Expect("a child's key nests under its parent", [spdf_sidebar_outline_key(doc, 1) isEqualToString:@"0.0"]);
        Expect("siblings differ only in the last ordinal",
               [spdf_sidebar_outline_key(doc, 2) isEqualToString:@"0.0.0"] &&
                   [spdf_sidebar_outline_key(doc, 3) isEqualToString:@"0.0.1"]);
        Expect("a later sibling of a parent advances that parent's ordinal",
               [spdf_sidebar_outline_key(doc, 4) isEqualToString:@"0.1"]);

        // --- Expanded is the default -----------------------------------
        Expect("no collapsed keys shows every row", [VisibleString(doc, [NSSet set]) isEqualToString:@"0,1,2,3,4"]);

        // --- Collapsing hides descendants, not the row itself ----------
        Expect("collapsing a section hides its children but keeps it visible",
               [VisibleString(doc, [NSSet setWithObject:@"0.0"]) isEqualToString:@"0,1,4"]);
        Expect("collapsing the root hides everything below it",
               [VisibleString(doc, [NSSet setWithObject:@"0"]) isEqualToString:@"0"]);
        // The bug this guards: a collapsed subtree must stop hiding when the
        // list comes back up to its level, or the sections after it vanish too.
        Expect("a sibling after a collapsed section is still shown",
               [VisibleString(doc, [NSSet setWithObject:@"0.0"]) containsString:@"4"]);

        // --- Collapse all / expand all ---------------------------------
        NSSet<NSString*>* all = spdf_sidebar_outline_collapsible_keys(doc);
        Expect("only rows with children are collapsible", all.count == 2);
        Expect("collapse all leaves just the roots of each branch",
               [VisibleString(doc, all) isEqualToString:@"0"]);
        Expect("a leaf is never stored as collapsible", ![all containsObject:@"0.0.0"]);

        // --- A key from a document that has since changed --------------
        // Stale keys must not hide anything; the rows come back expanded.
        Expect("an unknown key hides nothing",
               [VisibleString(doc, [NSSet setWithObject:@"9.9.9"]) isEqualToString:@"0,1,2,3,4"]);

        // --- An outline that does not start at level 0 ------------------
        // A PDF outline can start deeper; nesting is relative, not absolute.
        NSArray<NSNumber*>* deep = Levels(@[ @2, @3, @3, @2 ]);
        Expect("a deeper-rooted outline still nests", spdf_sidebar_outline_has_children(deep, 0));
        Expect("collapsing its root hides its children",
               [VisibleString(deep, [NSSet setWithObject:spdf_sidebar_outline_key(deep, 0)]) isEqualToString:@"0,3"]);

        // --- Degenerate shapes -----------------------------------------
        Expect("an empty outline has no rows", [VisibleString(@[], [NSSet set]) isEqualToString:@""]);
        Expect("a flat outline has no triangles",
               spdf_sidebar_outline_collapsible_keys(Levels(@[ @0, @0, @0 ])).count == 0);
        // A level that jumps by more than one (H1 then H3) is still a child.
        Expect("a skipped level still nests", spdf_sidebar_outline_has_children(Levels(@[ @0, @2 ]), 0));

        if (gFailures == 0) fprintf(stderr, "SPDFMacSidebarOutlineTests passed\n");
    }
    return gFailures == 0 ? 0 : 1;
}
