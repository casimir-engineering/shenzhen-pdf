#import "SPDFMacCollectionIntegration.h"
#import "SPDFMacCollectionStore.h"
#import "SPDFMacCollectionAvailability.h"
#import "SPDFMacCollectionWindow.h"
#import "SPDFMacMarkdownDelegatePrivate.h"
#import <objc/runtime.h>
static char kCollectionManager, kCollectionPromptPending, kCollectionImported, kCollectionRecoveryPath, kCollectionSettingsObserver, kCollectionContinuity, kCollectionPendingSave;
@implementation ShenzhenMacDelegate (SPDFMacCollectionIntegration)
- (void)collectionObserveSettings {
    if (objc_getAssociatedObject(self, &kCollectionSettingsObserver)) return;
    __weak ShenzhenMacDelegate* weakSelf = self;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:@"SPDFCollectionSettingsChanged" object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification* note) {
            (void)note; ShenzhenMacDelegate* owner = weakSelf; if (!owner) return;
            objc_setAssociatedObject(owner, &kCollectionImported, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            for (SPDFDocumentTab* tab in owner->_tabs) [owner collectionDidOpenPath:tab.path];
        }];
    objc_setAssociatedObject(self, &kCollectionSettingsObserver, observer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)collectionRecordObservedChangeAtPath:(NSString*)path {
    SPDFMacCollectionStore* store = SPDFMacCollectionStore.defaultStore;
    if (!store.isEnabled) return;
    NSString* identifier = [store documentForPath:path][@"id"]; if (!identifier) return;
    NSMutableDictionary* pending = objc_getAssociatedObject(self, &kCollectionContinuity);
    if (!pending) { pending = [NSMutableDictionary dictionary]; objc_setAssociatedObject(self, &kCollectionContinuity, pending, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    pending[path] = identifier;
}
- (void)collectionClearObservedChangeAtPath:(NSString*)path {
    [objc_getAssociatedObject(self, &kCollectionContinuity) removeObjectForKey:path];
    [objc_getAssociatedObject(self, &kCollectionPendingSave) removeObjectForKey:path];
}
- (void)collectionDidSavePath:(NSString*)path {
    NSMutableDictionary* saves = objc_getAssociatedObject(self, &kCollectionPendingSave);
    NSString* identifier = saves[path]; [saves removeObjectForKey:path];
    if (identifier) {
        NSMutableDictionary* pending = objc_getAssociatedObject(self, &kCollectionContinuity);
        if (!pending) { pending = [NSMutableDictionary dictionary]; objc_setAssociatedObject(self, &kCollectionContinuity, pending, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        pending[path] = identifier;
    }
    [self collectionDidOpenPath:path];
}
- (void)collectionRecordPendingSaveAtPath:(NSString*)path {
    SPDFMacCollectionStore* store = SPDFMacCollectionStore.defaultStore;
    NSMutableDictionary* saves = objc_getAssociatedObject(self, &kCollectionPendingSave);
    if (!saves) { saves = [NSMutableDictionary dictionary]; objc_setAssociatedObject(self, &kCollectionPendingSave, saves, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    NSString* identifier = store.isEnabled ? [store documentForPath:path][@"id"] : nil;
    if (identifier) saves[path] = identifier; else [saves removeObjectForKey:path];
}
- (void)collectionDidOpenPath:(NSString*)path {
    if (!path.length) return;
    [self collectionObserveSettings];
    // Only called after a document has opened. Neither main nor empty launch instantiates the store.
    NSString* source = [path copy];
    NSMutableDictionary* pending = objc_getAssociatedObject(self, &kCollectionContinuity);
    NSString* continuingID = pending[source]; [pending removeObjectForKey:source];
    dispatch_async(dispatch_get_main_queue(), ^{
        SPDFMacCollectionStore* store = [SPDFMacCollectionStore defaultStore];
        if ([store isArchivePath:source]) {
            NSDictionary* info = [store archiveInfoForPath:source];
            NSInteger index = [self indexOfTabForPath:source];
            if (index >= 0) {
                SPDFDocumentTab* tab = self->_tabs[(NSUInteger)index]; tab.readOnly = YES;
                NSNumber* capturedAt = info[@"version"][@"capturedAt"];
                NSString* label = capturedAt ? [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:capturedAt.doubleValue]
                    dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle] : @"date unavailable";
                tab.collectionVersionLabel = [NSString stringWithFormat:@"Archived · %@ · %@ · Read-only", label, source.lastPathComponent.stringByDeletingPathExtension];
                tab.title = tab.collectionVersionLabel;
                [self updateTabStrip]; [self savePersistentState]; [self collectionRefreshHistory];
                if (index == self->_selectedTabIndex) {
                    self->_window.title = [tab.collectionVersionLabel stringByAppendingString:@" - Shenzhen PDF"];
                    self->_statusLabel.stringValue = [NSString stringWithFormat:@"Archived copy · Read-only · %@", label];
                }
            }
            return;
        }
        NSString* choice = [store settings][@"choice"];
        if ([choice isEqual:@"unset"] || !choice.length) {
            if (objc_getAssociatedObject(self, &kCollectionPromptPending)) return;
            if (self->_window.attachedSheet || !self->_window.visible) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    if ([self indexOfTabForPath:source] >= 0) [self collectionDidOpenPath:source];
                });
                return;
            }
            objc_setAssociatedObject(self, &kCollectionPromptPending, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSAlert* alert = [[NSAlert alloc] init];
            alert.messageText = @"Keep a local copy and history of documents you open?";
            alert.informativeText = @"You will continue using the originals. Copies stay on this Mac; change this in Settings.";
            [alert addButtonWithTitle:@"Keep Enabled"]; [alert addButtonWithTitle:@"Turn Off"];
            [alert beginSheetModalForWindow:self->_window completionHandler:^(NSModalResponse result) {
                NSError* error = nil;
                [store updateSettings:@{@"choice":result == NSAlertFirstButtonReturn ? @"enabled" : @"disabled"} error:&error];
                objc_setAssociatedObject(self, &kCollectionPromptPending, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                if (error) [self->_window presentError:error];
                else if (store.isEnabled) {
                    for (SPDFDocumentTab* tab in self->_tabs) [self collectionDidOpenPath:tab.path];
                }
            }];
            return;
        }
        if (!store.isEnabled) {
            [self collectionRecordUserOpenForPath:source document:[store documentForPath:source]];
            return;
        }
        if ([self->_path isEqual:source]) self->_statusLabel.stringValue = @"Collection: saving local copy…";
        NSUInteger userOpenCount = [self collectionConsumeUserOpenForPath:source];
        [store capturePath:source reason:continuingID ? @"Observed save" : @"Opened"
            continuingDocumentID:continuingID userOpenCount:userOpenCount
            completion:^(NSDictionary* doc, NSError* error, BOOL userOpenCountRecorded) {
            // Reading succeeded even when capture was excluded or could not save a new version.
            if (!userOpenCountRecorded)
                [self collectionRecordUserOpenCount:userOpenCount document:doc ?: [store documentForPath:source]];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (![self->_path isEqual:source]) return;
                [self collectionRefreshHistory];
                if (error) self->_statusLabel.stringValue = [NSString stringWithFormat:@"Collection: copy failed — %@", error.localizedDescription];
                else if (doc) self->_statusLabel.stringValue = @"Collection: protected local copy · Version History in the tab menu";
            });
        }];
        if (!objc_getAssociatedObject(self, &kCollectionImported)) {
            objc_setAssociatedObject(self, &kCollectionImported, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [store importRecentPaths:[self->_recentlyOpenedPaths copy]];
        }
    });
}
- (BOOL)collectionProtectPath:(NSString*)path operation:(NSString*)operation {
    SPDFMacCollectionStore* store = [SPDFMacCollectionStore defaultStore];
    if ([store isArchivePath:path]) {
        [self showError:@"Collection copies are read-only" detail:@"Use Save a Copy to create a separate editable document."];
        return NO;
    }
    while (YES) {
        NSError* error = nil;
        NSString* continuingID = [objc_getAssociatedObject(self, &kCollectionContinuity) objectForKey:path];
        if ([store ensureProtectedPath:path reason:@"Before edit" continuingDocumentID:continuingID error:&error]) {
            [self collectionRecordPendingSaveAtPath:path];
            return YES;
        }
        NSAlert* alert = [[NSAlert alloc] init];
        alert.messageText = @"The current version is not protected yet";
        alert.informativeText = [NSString stringWithFormat:@"%@\n\nBefore %@, Collection needs a durable copy. Reading is still available.", error.localizedDescription, operation ?: @"editing"];
        [alert addButtonWithTitle:@"Retry"]; [alert addButtonWithTitle:@"Cancel Edit"];
        [alert addButtonWithTitle:@"Continue Without History"];
        NSModalResponse result = [alert runModal];
        if (result == NSAlertSecondButtonReturn) { [self collectionClearObservedChangeAtPath:path]; return NO; }
        if (result == NSAlertThirdButtonReturn) { [self collectionRecordPendingSaveAtPath:path]; return YES; }
    }
}
- (void)installCollectionSettingsMenu:(NSMenu*)menu {
    NSMenuItem* item = [menu addItemWithTitle:@"Collection…" action:@selector(showCollectionManager:) keyEquivalent:@""];
    item.target = self;
}
- (void)addCollectionItemsToTabMenu:(NSMenu*)menu path:(NSString*)path {
    [menu addItem:NSMenuItem.separatorItem];
    NSArray* titles = @[@"Previous Version", @"Version History", @"Locate Original / Collection Recovery…"];
    NSArray* actions = @[@"showCollectionPreviousVersion:", @"showCollectionHistory:", @"showCollectionRecovery:"];
    for (NSUInteger i = 0; i < titles.count; i++) {
        NSMenuItem* item = [menu addItemWithTitle:titles[i] action:NSSelectorFromString(actions[i]) keyEquivalent:@""];
        item.target = self; item.representedObject = path;
    }
}
- (SPDFMacCollectionWindow*)collectionManager {
    [self collectionObserveSettings];
    SPDFMacCollectionWindow* manager = objc_getAssociatedObject(self, &kCollectionManager);
    if (!manager) {
        __weak ShenzhenMacDelegate* weakSelf = self;
        manager = [[SPDFMacCollectionWindow alloc] initWithStore:[SPDFMacCollectionStore defaultStore]
            open:^(NSString* path, BOOL archived) { [weakSelf collectionOpenPath:path archived:archived]; }];
        objc_setAssociatedObject(self, &kCollectionManager, manager, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return manager;
}
- (NSString*)collectionPathForSender:(id)sender {
    return [sender respondsToSelector:@selector(representedObject)] && [[sender representedObject] isKindOfClass:NSString.class]
        ? [sender representedObject] : _path;
}
- (void)showCollectionManager:(id)sender { (void)sender; [self showCollectionManagerForQuery:nil]; }
- (void)showCollectionManagerForQuery:(NSString*)query { [[self collectionManager] showDocumentID:nil query:query]; }
- (void)showCollectionPreviousVersion:(id)sender {
    SPDFMacCollectionStore* store = [SPDFMacCollectionStore defaultStore];
    NSString* path = [self collectionPathForSender:sender];
    NSDictionary* doc = [store documentForPath:path] ?: [store archiveInfoForPath:path][@"document"];
    NSArray* versions = [store versionsForDocumentID:doc[@"id"]];
    if (versions.count < 2) { [self showCollectionHistory:sender]; return; }
    NSDictionary* version = versions[versions.count - 2];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError* error = nil;
        NSURL* URL = [store materializeVersionID:version[@"id"] documentID:doc[@"id"] error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (URL) [self collectionOpenPath:URL.path archived:YES]; else [self->_window presentError:error];
        });
    });
}
- (void)collectionOpenPath:(NSString*)path archived:(BOOL)archived {
    [self openPath:path];
    if (archived) {
        SPDFDocumentTab* tab = [self selectedTab]; tab.readOnly = YES;
        tab.title = [NSString stringWithFormat:@"%@ · Collection copy", path.lastPathComponent.stringByDeletingPathExtension];
        [self updateTabStrip]; [self savePersistentState];
        _statusLabel.stringValue = @"Read-only Collection copy · the original document is unchanged";
    }
}
- (void)collectionPresentMissingPath:(NSString*)path {
    if ([objc_getAssociatedObject(self, &kCollectionRecoveryPath) isEqual:path]) return;
    if (![[SPDFMacCollectionStore defaultStore] documentForPath:path]) return;
    objc_setAssociatedObject(self, &kCollectionRecoveryPath, path, OBJC_ASSOCIATION_COPY_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(), ^{ if ([self->_path isEqual:path]) [self showCollectionRecovery:nil]; });
}
- (void)showCollectionRecovery:(id)sender {
    NSString* path = [self collectionPathForSender:sender];
    SPDFMacCollectionStore* store = [SPDFMacCollectionStore defaultStore];
    NSDictionary* doc = [store documentForPath:path] ?: [store archiveInfoForPath:path][@"document"];
    if (!doc) { [self showCollectionManager:nil]; return; }
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = SPDFCollectionOriginalAvailable(doc) ? @"Original document and protected history" : @"Original document unavailable";
    NSDictionary* latest = [doc[@"versions"] lastObject];
    NSString* date = latest[@"capturedAt"] ? [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:[latest[@"capturedAt"] doubleValue]]
        dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle] : @"None — the first capture did not complete";
    alert.informativeText = [NSString stringWithFormat:@"%@\n%@\n\nLatest protected copy: %@. Open it read-only, locate the original, or save a separate copy. The original tab is retained.", doc[@"title"], doc[@"path"], date];
    [alert addButtonWithTitle:@"Open Archived Copy"].enabled = latest[@"id"] != nil; [alert addButtonWithTitle:@"Locate Original…"];
    [alert addButtonWithTitle:@"Manage / Save a Copy…"]; [alert addButtonWithTitle:@"Retry Original"]; [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse result) {
        if (result == NSAlertFirstButtonReturn) {
            NSError* error = nil;
            NSURL* URL = [store materializeVersionID:doc[@"latestVersionID"] documentID:doc[@"id"] error:&error];
            if (URL) [self collectionOpenPath:URL.path archived:YES]; else [self->_window presentError:error];
        } else if (result == NSAlertSecondButtonReturn) {
            SPDFMacLocateCollectionOriginal(store, doc[@"id"], self->_window, ^(NSString* previewPath) {
                [self collectionOpenPath:previewPath archived:NO];
            }, ^(NSString* newPath) {
                NSInteger index = [self indexOfTabForPath:path];
                if (index >= 0) {
                    SPDFDocumentTab* tab = self->_tabs[(NSUInteger)index];
                    tab.path = newPath; tab.title = newPath.lastPathComponent.stringByDeletingPathExtension;
                    tab.missingFile = NO; tab.missingMessage = @"";
                    [self selectTabAtIndex:index]; [self loadSelectedTab]; [self savePersistentState];
                } else [self openPath:newPath];
            });
        } else if (result == NSAlertThirdButtonReturn) [[self collectionManager] showDocumentID:doc[@"id"] query:nil];
        else if (result == NSAlertThirdButtonReturn + 1) [self loadSelectedTab];
    }];
}
@end
