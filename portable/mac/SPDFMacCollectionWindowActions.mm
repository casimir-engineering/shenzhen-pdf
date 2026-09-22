#import "SPDFMacCollectionSavePanel.h"
#import "SPDFMacCollectionAvailability.h"
#import "SPDFMacCollectionWindowPrivate.h"
@implementation SPDFMacCollectionWindow (Actions)
- (void)openOriginal:(id)sender {
    (void)sender; NSString* path = [self selectedDocument][@"path"];
    if (SPDFCollectionOriginalAvailable([self selectedDocument])) self.openHandler(path, NO);
    else [self locate:nil];
}
- (void)preview:(id)sender {
    (void)sender; NSDictionary* doc = [self selectedDocument], *version = [self selectedVersion];
    if (!doc || !version[@"id"]) return;
    self.details.stringValue = @"Preparing read-only preview…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError* error = nil;
        NSURL* URL = [self.store materializeVersionID:version[@"id"] documentID:doc[@"id"] error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (URL) self.openHandler(URL.path, YES); else [self showError:error];
            [self updateDetails];
        });
    });
}
- (void)history:(id)sender {
    (void)sender; NSDictionary* doc = [self selectedDocument];
    if (doc) [self showDocumentID:doc[@"id"] query:@""];
}
- (void)compareVersionWithPrevious:(BOOL)previous {
    NSDictionary* doc = [self selectedDocument], *version = [self selectedVersion];
    if (!doc || !version[@"id"]) return;
    if (!previous && !SPDFCollectionOriginalAvailable(doc)) { [self locate:nil]; return; }
    NSArray* versions = doc[@"versions"] ?: @[];
    NSUInteger index = [versions indexOfObjectPassingTest:^BOOL(NSDictionary* v, NSUInteger i, BOOL* stop) {
        (void)i; (void)stop; return [v[@"id"] isEqual:version[@"id"]];
    }];
    if (previous && (index == NSNotFound || index == 0)) {
        self.details.stringValue = @"This is the first protected version; there is no previous version."; return;
    }
    NSDictionary* older = previous ? versions[index - 1] : version;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError* error = nil;
        NSURL* oldURL = [self.store materializeVersionID:older[@"id"] documentID:doc[@"id"] error:&error];
        NSURL* newURL = previous ? [self.store materializeVersionID:version[@"id"] documentID:doc[@"id"] error:&error]
                                : [NSURL fileURLWithPath:doc[@"path"]];
        NSString* (^date)(NSDictionary*) = ^NSString*(NSDictionary* row) {
            return [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:[row[@"capturedAt"] doubleValue]]
                dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle];
        };
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!oldURL || !newURL) { [self showError:error]; return; }
            SPDFMacShowCollectionComparison(oldURL, newURL, [NSString stringWithFormat:@"%@ · %@",doc[@"title"],date(older)],
                [NSString stringWithFormat:@"%@ · %@",doc[@"title"],previous ? date(version) : @"Current original"],self.window);
        });
    });
}
- (void)compareCurrent:(id)sender { (void)sender; [self compareVersionWithPrevious:NO]; }
- (void)comparePrevious:(id)sender { (void)sender; [self compareVersionWithPrevious:YES]; }
- (void)locate:(id)sender {
    (void)sender; NSDictionary* doc = [self selectedDocument]; if (!doc) return;
    SPDFMacLocateCollectionOriginal(self.store, doc[@"id"], self.window, ^(NSString* path) {
        self.openHandler(path, NO);
    }, ^(NSString* path) {
        self.openHandler(path, NO); [self reload:nil];
    });
}
- (void)exportCopy:(id)sender {
    (void)sender; NSDictionary* doc = [self selectedDocument], *version = [self selectedVersion];
    if (!version[@"id"]) return;
    NSSavePanel* panel = [NSSavePanel savePanel]; SPDFCollectionConfigureSavePanel(panel, doc[@"path"]);
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError* error = nil;
            BOOL ok = [self.store exportVersionID:version[@"id"] documentID:doc[@"id"] toURL:panel.URL error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{ if (ok) self.openHandler(panel.URL.path, NO); else [self showError:error]; });
        });
    }];
}
- (NSArray<NSDictionary*>*)selectedRowsSnapshot {
    NSMutableArray* selected = [NSMutableArray array];
    [self.table.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL* stop) {
        (void)stop; if (index < self.rows.count) [selected addObject:self.rows[index]];
    }];
    return selected;
}
- (void)performMutation:(void (^)(NSError**))operation {
    if (self.mutationPending) return;
    self.mutationPending = YES; [self updateDetails];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSError* error = nil; operation(&error);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.mutationPending = NO; [self showError:error]; [self reload:nil];
        });
    });
}
- (void)keep:(id)sender {
    (void)sender; NSArray* rows = [self selectedRowsSnapshot];
    [self performMutation:^(NSError** error) {
        for (NSDictionary* row in rows) {
            NSDictionary* doc = row[@"document"], *version = row[@"version"];
            if (version[@"id"] && ![self.store setKeep:![version[@"keep"] boolValue]
                versionID:version[@"id"] documentID:doc[@"id"] error:error]) break;
        }
    }];
}
- (void)exclude:(id)sender {
    (void)sender; NSArray* rows = [self selectedRowsSnapshot];
    [self performMutation:^(NSError** error) {
        NSMutableSet* changed = [NSMutableSet set];
        for (NSDictionary* row in rows) {
            NSDictionary* doc = row[@"document"];
            if ([changed containsObject:doc[@"id"]]) continue;
            [changed addObject:doc[@"id"]];
            if (![self.store setExcluded:![doc[@"excluded"] boolValue] documentID:doc[@"id"] error:error]) break;
        }
    }];
}
- (void)deleteSelected:(id)sender {
    (void)sender;
    NSArray* rows = [self selectedRowsSnapshot]; if (!rows.count) return;
    BOOL versionsOnly = self.viewPicker.indexOfSelectedItem == 1 || self.viewPicker.indexOfSelectedItem == 3;
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = versionsOnly ? @"Delete selected versions permanently?" : @"Delete all history for selected documents?";
    alert.informativeText = [NSString stringWithFormat:@"%lu selected %@, including any kept versions. This cannot be undone. Original documents are kept. Exclude separately to prevent future capture.",
        rows.count,versionsOnly ? @"versions" : @"document histories"];
    [alert addButtonWithTitle:@"Cancel"]; [alert addButtonWithTitle:@"Delete Copies"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSAlertSecondButtonReturn) return;
        // Snapshot identities before showing the sheet; a background refresh or
        // a changed selection must never change what the confirmation deletes.
        [self performMutation:^(NSError** error) {
            for (NSDictionary* row in rows) if (![self.store deleteDocumentID:row[@"document"][@"id"]
                versionID:versionsOnly ? row[@"version"][@"id"] : nil error:error]) break;
        }];
    }];
}
- (void)changeEnabled:(id)sender {
    (void)sender; NSError* error = nil;
    BOOL updated = [self.store updateSettings:@{@"choice":self.enabled.state == NSControlStateValueOn ? @"enabled" : @"disabled"} error:&error];
    if (updated) [NSNotificationCenter.defaultCenter postNotificationName:@"SPDFCollectionSettingsChanged" object:self.store];
    [self showError:error]; [self reload:nil];
}
- (void)changeLimit:(id)sender {
    (void)sender; NSError* error = nil;
    double amount = 0;
    NSScanner* scanner = [NSScanner scannerWithString:self.limitField.stringValue];
    if (![scanner scanDouble:&amount] || !scanner.isAtEnd || !isfinite(amount) || amount < 0 || amount > 1e8) {
        [self showError:[NSError errorWithDomain:@"ShenzhenPDF.Collection" code:1 userInfo:@{
            NSLocalizedDescriptionKey:@"Enter a nonnegative storage limit in GB. Zero keeps all versions."}]];
        return;
    }
    [self.store updateSettings:@{@"storageLimitBytes":@((unsigned long long)(amount * 1e9))} error:&error];
    [self showError:error]; [self reload:nil];
}
- (void)changeLocation:(id)sender {
    (void)sender; NSOpenPanel* panel = [NSOpenPanel openPanel]; panel.title = @"Move Collection to Folder";
    panel.canChooseFiles = NO; panel.canChooseDirectories = YES; panel.canCreateDirectories = YES;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        NSURL* destination = [panel.URL URLByAppendingPathComponent:@"ShenzhenPDF Collection" isDirectory:YES];
        self.storage.stringValue = @"Moving protected copies…";
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError* error = nil; [self.store relocateToURL:destination error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{ [self showError:error]; [self reload:nil]; });
        });
    }];
}
@end
