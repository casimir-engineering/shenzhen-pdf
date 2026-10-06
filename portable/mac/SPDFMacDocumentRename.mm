#import "SPDFMacDocumentRename.h"
#import "SPDFMacMarkdownDelegatePrivate.h"
#import "SPDFMacCollectionIntegration.h"
#import "SPDFMacCollectionStore.h"
#import "SPDFMacCollectionTabIdentity.h"
#import "SPDFMacTabGroups.h"

@interface ShenzhenMacDelegate (DocumentRenameHost)
- (void)rememberActiveTabState;
- (void)repointActiveFileWatcher;
@end
@implementation ShenzhenMacDelegate (DocumentRename)
- (void)renameDocumentFromTab:(NSMenuItem*)sender {
    NSString* source=[sender.representedObject isKindOfClass:NSString.class] ? sender.representedObject : nil;
    NSInteger index=source ? [self indexOfTabForPath:source] : -1;
    if (index<0) return;
    SPDFDocumentTab* tab=_tabs[(NSUInteger)index];
    if (tab.missingFile || tab.unsavedPastedImage || SPDFTabIsCollectionCopy(tab)) return;
    NSAlert* alert=[NSAlert new]; alert.messageText=@"Rename Document";
    alert.informativeText=@"The file will be renamed in its current folder. Its format and version history will be preserved.";
    [alert addButtonWithTitle:@"Rename"]; [alert addButtonWithTitle:@"Cancel"];
    NSTextField* field=[[NSTextField alloc] initWithFrame:NSMakeRect(0,0,360,24)];
    field.stringValue=source.lastPathComponent.stringByDeletingPathExtension;
    alert.accessoryView=field; alert.window.initialFirstResponder=field;
    [alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse response) {
        if (response!=NSAlertFirstButtonReturn) return;
        NSString* destination=SPDFDocumentRenameDestination(source,field.stringValue);
        if (!destination) { [self showError:@"Invalid document name" detail:@"Enter a filename without slashes or colons."]; return; }
        if ([source isEqual:destination]) return;
        if ([self indexOfTabForPath:source]<0) return;
        NSError* error=nil;
        if (!SPDFRenameDocumentFile(source,destination,&error)) {
            [self showError:@"Could not rename document" detail:error.localizedDescription]; return;
        }
        [self rememberActiveTabState];
        for (SPDFDocumentTab* open in self->_tabs) if ([open.path isEqual:source]) {
            open.path=destination; open.title=destination.lastPathComponent;
            [open.cachedMarkdownSession relocateDocumentToURL:[NSURL fileURLWithPath:destination]];
            if ([open.group.lastUsedPath isEqual:source]) open.group.lastUsedPath=destination;
        }
        if ([self->_path isEqual:source]) self->_path=[destination copy];
        [self->_recentlyOpenedPaths removeObject:source]; [self rememberRecentlyOpenedPath:destination];
        [self repointActiveFileWatcher]; [self updateTabStrip]; [self updateControls];
        [self savePersistentState];
        // Relinking verifies bytes; large documents must not stall the rename UI.
        static dispatch_queue_t relinks; static dispatch_once_t once;
        dispatch_once(&once, ^{ relinks=dispatch_queue_create("com.shenzhenpdf.rename-history",DISPATCH_QUEUE_SERIAL); });
        dispatch_async(relinks, ^{
            SPDFMacCollectionStore* store=SPDFMacCollectionStore.defaultStore;
            NSString* identifier=[store documentForPath:source][@"id"];
            NSError* linkError=nil;
            BOOL linked=!identifier || [store linkDocumentID:identifier toPath:destination allowMismatch:YES error:&linkError];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self collectionRefreshHistory];
                if (!linked) [self showError:@"Document renamed; history link needs attention" detail:linkError.localizedDescription];
            });
        });
    }];
    [field selectText:nil];
}
@end
