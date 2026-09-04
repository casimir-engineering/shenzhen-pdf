// Per-document tab state that has to survive a session write/read cycle.
// Keep-image-colors is the case this suite exists for: it used to be one global
// preference, and the contract now is that every open document carries its own
// choice, defaulting to on.

#import <Cocoa/Cocoa.h>

#import "SPDFMacModels.h"

static int gFailures;

static void Expect(const char* what, BOOL condition) {
    if (condition) return;
    fprintf(stderr, "FAIL: %s\n", what);
    ++gFailures;
}

static SPDFDocumentTab* TabWithPath(NSString* path) {
    SPDFDocumentTab* tab = [[SPDFDocumentTab alloc] init];
    tab.path = path;
    tab.title = path.lastPathComponent;
    return tab;
}

static NSDictionary* RoundTrip(SPDFDocumentTab* tab) {
    return spdf_dictionary_from_tab(tab, 7);
}

int main(void) {
    @autoreleasepool {
        // --- The default ------------------------------------------------
        // "Default being on" is the whole user-visible promise: a document
        // nobody has configured keeps its image colors in the dark theme.
        SPDFDocumentTab* fresh = TabWithPath(@"/tmp/fresh.pdf");
        Expect("a new document keeps image colors by default", fresh.preservesImageColors);

        // --- It is written, and read back --------------------------------
        NSDictionary* on = RoundTrip(fresh);
        Expect("the session records the choice", on[@"preservesImageColors"] != nil);
        Expect("the recorded choice is on", [on[@"preservesImageColors"] boolValue]);
        SPDFDocumentTab* restoredOn = spdf_tab_from_dictionary(on);
        Expect("restoring keeps it on", restoredOn != nil && restoredOn.preservesImageColors);

        fresh.preservesImageColors = NO;
        SPDFDocumentTab* restoredOff = spdf_tab_from_dictionary(RoundTrip(fresh));
        Expect("restoring keeps it off", restoredOff != nil && !restoredOff.preservesImageColors);

        // --- Per document, not per app -----------------------------------
        // The defect this guards: one document's choice leaking onto another,
        // which is exactly what a single global preference did.
        SPDFDocumentTab* keeps = TabWithPath(@"/tmp/datasheet.pdf");
        SPDFDocumentTab* recolors = TabWithPath(@"/tmp/scan.pdf");
        recolors.preservesImageColors = NO;
        SPDFDocumentTab* keepsBack = spdf_tab_from_dictionary(RoundTrip(keeps));
        SPDFDocumentTab* recolorsBack = spdf_tab_from_dictionary(RoundTrip(recolors));
        Expect("two documents restore their own opposite choices",
               keepsBack.preservesImageColors && !recolorsBack.preservesImageColors);

        // --- A session written before the setting was per document --------
        // No key at all: the tab must land on the documented default so the
        // caller can seed it with the launch default instead of inheriting a
        // stale NO from a zero-initialized field.
        NSMutableDictionary* legacy = [RoundTrip(keeps) mutableCopy];
        [legacy removeObjectForKey:@"preservesImageColors"];
        SPDFDocumentTab* legacyTab = spdf_tab_from_dictionary(legacy);
        Expect("a session with no stored choice defaults to on",
               legacyTab != nil && legacyTab.preservesImageColors);

        // --- Detaching a tab into its own window carries it ---------------
        // A dragged-out tab is rebuilt from spdf_copy_document_tab; losing the
        // flag there would silently recolor the document in the new window.
        SPDFDocumentTab* copied = spdf_copy_document_tab(recolors);
        Expect("copying a tab carries its choice", copied != nil && !copied.preservesImageColors);

        // --- The neighbouring per-document flags still round-trip ---------
        keeps.markdownLandscape = YES;
        keeps.showMinimap = NO;
        SPDFDocumentTab* neighbours = spdf_tab_from_dictionary(RoundTrip(keeps));
        Expect("orientation and minimap stay per document",
               neighbours.markdownLandscape && !neighbours.showMinimap && neighbours.hasMinimapPreference);

        // --- One writer, or the round-trip above proves nothing ----------
        // The defect this guards, which the assertions above missed entirely:
        // a tab's persisted fields had TWO writers -- this shared one and a
        // second copy inlined in the session save, "kept in sync" by hand.
        // preservesImageColors was added here and to the reader, tested through
        // both, and still never reached session.yaml. Source contract, in the
        // style of SPDFMacTabLifecycleTests: the coordinator must delegate.
        NSString* testPath = @(__FILE__);
        NSString* dir = testPath.stringByDeletingLastPathComponent;
        NSError* readError = nil;
        NSString* coordinator =
            [NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:@"../ShenzhenPDFMac.mm"]
                                      encoding:NSUTF8StringEncoding
                                         error:&readError];
        Expect("the coordinator source is readable", coordinator != nil);
        Expect("the session save uses the shared tab writer",
               [coordinator containsString:@"spdf_dictionary_from_tab(tab, _window.windowNumber)"]);
        // A field name that only a hand-rolled tab dictionary would contain.
        Expect("the coordinator no longer inlines a second tab dictionary",
               ![coordinator containsString:@"@(tab.hasScrollOrigin)"]);

        if (gFailures == 0) fprintf(stderr, "SPDFMacTabStateTests passed\n");
    }
    return gFailures == 0 ? 0 : 1;
}
