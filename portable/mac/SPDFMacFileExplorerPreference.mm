#import "SPDFMacFileExplorerPreference.h"

NSString* const SPDFMacShenzhenFilesBundleIdentifier = @"com.intuition.shenzhenfiles";

static NSString* const kSPDFSystemExplorerIdentifier = @"system";
static NSString* const kSPDFShenzhenFilesExplorerIdentifier = @"shenzhen-files";
static NSString* const kSPDFFileExplorerPreferenceDefaultsKey = @"SPDFFileExplorerPreference";
static NSString* const kSPDFSystemExplorerTitle = @"Finder";
static NSString* const kSPDFShenzhenFilesExplorerTitle = @"Shenzhen Files";
// Marks the derived choice while the preference is unset, so the checkmark
// never reads as a decision the user made.
static NSString* const kSPDFAutomaticTitleSuffix = @" (Automatic)";

NSString* SPDFMacFileExplorerPreferenceIdentifier(SPDFMacFileExplorerPreference preference) {
    switch (preference) {
        case SPDFMacFileExplorerShenzhenFiles:
            return kSPDFShenzhenFilesExplorerIdentifier;
        case SPDFMacFileExplorerSystem:
            return kSPDFSystemExplorerIdentifier;
        case SPDFMacFileExplorerUnset:
            break;
    }
    return nil;
}

SPDFMacFileExplorerPreference SPDFMacFileExplorerPreferenceFromIdentifier(NSString* identifier) {
    if ([identifier isEqualToString:kSPDFShenzhenFilesExplorerIdentifier]) return SPDFMacFileExplorerShenzhenFiles;
    if ([identifier isEqualToString:kSPDFSystemExplorerIdentifier]) return SPDFMacFileExplorerSystem;
    return SPDFMacFileExplorerUnset;
}

static NSURL* spdf_shenzhen_files_application_url(void) {
    return [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:SPDFMacShenzhenFilesBundleIdentifier];
}

BOOL SPDFMacShenzhenFilesIsAvailable(void) {
    return spdf_shenzhen_files_application_url() != nil;
}

SPDFMacFileExplorerPreference SPDFMacResolveFileExplorerPreference(SPDFMacFileExplorerPreference stored,
                                                                  BOOL shenzhenFilesAvailable) {
    // An explicit choice is never second-guessed; only an unset one derives.
    if (stored == SPDFMacFileExplorerShenzhenFiles || stored == SPDFMacFileExplorerSystem) return stored;
    return shenzhenFilesAvailable ? SPDFMacFileExplorerShenzhenFiles : SPDFMacFileExplorerSystem;
}

SPDFMacFileExplorerPreference SPDFMacStoredFileExplorerPreference(void) {
    NSString* identifier = [NSUserDefaults.standardUserDefaults stringForKey:kSPDFFileExplorerPreferenceDefaultsKey];
    return SPDFMacFileExplorerPreferenceFromIdentifier(identifier);
}

SPDFMacFileExplorerPreference SPDFMacCurrentFileExplorerPreference(void) {
    return SPDFMacResolveFileExplorerPreference(SPDFMacStoredFileExplorerPreference(),
                                                SPDFMacShenzhenFilesIsAvailable());
}

void SPDFMacSetFileExplorerPreference(SPDFMacFileExplorerPreference preference) {
    NSString* identifier = SPDFMacFileExplorerPreferenceIdentifier(preference);
    if (identifier)
        [NSUserDefaults.standardUserDefaults setObject:identifier forKey:kSPDFFileExplorerPreferenceDefaultsKey];
    else
        [NSUserDefaults.standardUserDefaults removeObjectForKey:kSPDFFileExplorerPreferenceDefaultsKey];
}

@interface SPDFMacFileExplorerMenuTarget : NSObject <NSMenuItemValidation>
@end

@implementation SPDFMacFileExplorerMenuTarget

+ (instancetype)sharedTarget {
    static SPDFMacFileExplorerMenuTarget* target;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ target = [SPDFMacFileExplorerMenuTarget new]; });
    return target;
}

- (void)useSystemFileExplorer:(id)sender {
    (void)sender;
    SPDFMacSetFileExplorerPreference(SPDFMacFileExplorerSystem);
}

- (void)useShenzhenFilesExplorer:(id)sender {
    (void)sender;
    SPDFMacSetFileExplorerPreference(SPDFMacFileExplorerShenzhenFiles);
}

- (void)applyStateToItem:(NSMenuItem*)menuItem
                    title:(NSString*)title
                  choice:(SPDFMacFileExplorerPreference)choice
                  stored:(SPDFMacFileExplorerPreference)stored
                resolved:(SPDFMacFileExplorerPreference)resolved {
    BOOL active = resolved == choice;
    BOOL derived = active && stored == SPDFMacFileExplorerUnset;
    menuItem.state = active ? NSControlStateValueOn : NSControlStateValueOff;
    menuItem.title = derived ? [title stringByAppendingString:kSPDFAutomaticTitleSuffix] : title;
}

- (BOOL)validateMenuItem:(NSMenuItem*)menuItem {
    SPDFMacFileExplorerPreference stored = SPDFMacStoredFileExplorerPreference();
    BOOL available = SPDFMacShenzhenFilesIsAvailable();
    SPDFMacFileExplorerPreference resolved = SPDFMacResolveFileExplorerPreference(stored, available);
    if (menuItem.action == @selector(useSystemFileExplorer:)) {
        [self applyStateToItem:menuItem
                         title:kSPDFSystemExplorerTitle
                        choice:SPDFMacFileExplorerSystem
                        stored:stored
                      resolved:resolved];
        return YES;
    }
    if (menuItem.action == @selector(useShenzhenFilesExplorer:)) {
        [self applyStateToItem:menuItem
                         title:kSPDFShenzhenFilesExplorerTitle
                        choice:SPDFMacFileExplorerShenzhenFiles
                        stored:stored
                      resolved:resolved];
        return available;
    }
    return YES;
}

@end

void SPDFMacInstallFileExplorerSettingsMenu(NSMenu* settingsMenu) {
    if (!settingsMenu) return;
    SPDFMacFileExplorerMenuTarget* target = SPDFMacFileExplorerMenuTarget.sharedTarget;
    NSMenu* submenu = [[NSMenu alloc] initWithTitle:@"File Manager"];
    NSMenuItem* finder = [submenu addItemWithTitle:kSPDFSystemExplorerTitle
                                            action:@selector(useSystemFileExplorer:)
                                     keyEquivalent:@""];
    finder.target = target;
    NSMenuItem* shenzhenFiles = [submenu addItemWithTitle:kSPDFShenzhenFilesExplorerTitle
                                                   action:@selector(useShenzhenFilesExplorer:)
                                            keyEquivalent:@""];
    shenzhenFiles.target = target;
    // Reflect the derived default before the menu is ever opened.
    [target validateMenuItem:finder];
    [target validateMenuItem:shenzhenFiles];
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:@"File Manager" action:nil keyEquivalent:@""];
    item.submenu = submenu;
    [settingsMenu addItem:item];
}

// Returns an existing containing folder for `path`, or nil.
static NSString* spdf_existing_parent_directory(NSString* path) {
    if (!path.length) return nil;
    NSString* directory = path.stringByStandardizingPath.stringByDeletingLastPathComponent;
    if (!directory.length) return nil;
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:directory isDirectory:&isDirectory]) return nil;
    return isDirectory ? directory : nil;
}

NSString* SPDFMacBrowseStartDirectory(NSString* documentPath, NSArray<NSString*>* recentPaths) {
    NSString* directory = spdf_existing_parent_directory(documentPath);
    if (directory) return directory;
    for (NSString* recent in recentPaths) {
        if (![recent isKindOfClass:NSString.class]) continue;
        directory = spdf_existing_parent_directory(recent);
        if (directory) return directory;
    }
    return NSHomeDirectory();
}

// Shared launch policy for reveal and browse: hand `fileURL` to Shenzhen Files
// when the resolved preference asks for it, and fall back to `fallback` when it
// is missing or the launch fails.
static void spdf_open_in_explorer(NSURL* fileURL, SPDFMacFileExplorerPreference preference,
                                  SPDFMacExplorerApplicationLookup lookup,
                                  SPDFMacExplorerApplicationLauncher launcher, void (^fallback)(void)) {
    if (preference != SPDFMacFileExplorerShenzhenFiles || !lookup || !launcher) {
        fallback();
        return;
    }
    NSURL* applicationURL = lookup(SPDFMacShenzhenFilesBundleIdentifier);
    if (!applicationURL) {
        fallback();
        return;
    }
    launcher(applicationURL, @[ fileURL ], ^(NSError* error) {
      if (error) fallback();
    });
}

BOOL SPDFMacRevealPathWithHandlers(NSString* path, SPDFMacFileExplorerPreference preference,
                                   SPDFMacExplorerApplicationLookup lookup,
                                   SPDFMacExplorerApplicationLauncher launcher,
                                   SPDFMacSystemRevealHandler systemReveal) {
    if (!path.length || !systemReveal) return NO;

    NSString* standardized = path.stringByStandardizingPath;
    if (!standardized.length) return NO;
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:standardized isDirectory:&isDirectory]) return NO;

    NSURL* fileURL = [NSURL fileURLWithPath:standardized isDirectory:isDirectory];
    spdf_open_in_explorer(fileURL, preference, lookup, launcher, ^{
      systemReveal(fileURL, isDirectory);
    });
    return YES;
}

BOOL SPDFMacBrowseDirectoryWithHandlers(NSString* path, SPDFMacFileExplorerPreference preference,
                                        SPDFMacExplorerApplicationLookup lookup,
                                        SPDFMacExplorerApplicationLauncher launcher,
                                        SPDFMacSystemBrowseHandler systemBrowse) {
    if (!path.length || !systemBrowse) return NO;

    NSString* standardized = path.stringByStandardizingPath;
    if (!standardized.length) return NO;
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:standardized isDirectory:&isDirectory]) return NO;
    // A file browses its containing folder — Shenzhen Files opens folders.
    if (!isDirectory) {
        standardized = standardized.stringByDeletingLastPathComponent;
        if (!standardized.length) return NO;
    }

    NSURL* directoryURL = [NSURL fileURLWithPath:standardized isDirectory:YES];
    spdf_open_in_explorer(directoryURL, preference, lookup, launcher, ^{
      systemBrowse(directoryURL);
    });
    return YES;
}

static SPDFMacExplorerApplicationLookup spdf_workspace_lookup(void) {
    return ^NSURL*(NSString* bundleIdentifier) {
      return [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:bundleIdentifier];
    };
}

static SPDFMacExplorerApplicationLauncher spdf_workspace_launcher(void) {
    return ^(NSURL* applicationURL, NSArray<NSURL*>* URLs, void (^completion)(NSError*)) {
      NSWorkspaceOpenConfiguration* configuration = [NSWorkspaceOpenConfiguration configuration];
      configuration.activates = YES;
      [NSWorkspace.sharedWorkspace openURLs:URLs
                       withApplicationAtURL:applicationURL
                              configuration:configuration
                          completionHandler:^(NSRunningApplication* application, NSError* error) {
                            (void)application;
                            if (completion) completion(error);
                          }];
    };
}

BOOL SPDFMacRevealPath(NSString* path, SPDFMacFileExplorerPreference preference) {
    return SPDFMacRevealPathWithHandlers(path, preference, spdf_workspace_lookup(), spdf_workspace_launcher(),
                                         ^(NSURL* URL, BOOL isDirectory) {
                                           NSWorkspace* workspace = NSWorkspace.sharedWorkspace;
                                           if (isDirectory) [workspace openURL:URL];
                                           else [workspace activateFileViewerSelectingURLs:@[ URL ]];
                                         });
}

BOOL SPDFMacRevealPathUsingPreference(NSString* path) {
    return SPDFMacRevealPath(path, SPDFMacCurrentFileExplorerPreference());
}

BOOL SPDFMacBrowseDirectory(NSString* path, SPDFMacFileExplorerPreference preference,
                            SPDFMacSystemBrowseHandler systemBrowse) {
    if (!systemBrowse) return NO;
    // The fallback may present a modal panel, and a failed launch reports back
    // on a background queue, so pin it to the main thread here.
    SPDFMacSystemBrowseHandler mainThreadBrowse = ^(NSURL* directoryURL) {
      if (NSThread.isMainThread) {
          systemBrowse(directoryURL);
          return;
      }
      dispatch_async(dispatch_get_main_queue(), ^{ systemBrowse(directoryURL); });
    };
    return SPDFMacBrowseDirectoryWithHandlers(path, preference, spdf_workspace_lookup(), spdf_workspace_launcher(),
                                              mainThreadBrowse);
}

BOOL SPDFMacBrowseDirectoryUsingPreference(NSString* path, SPDFMacSystemBrowseHandler systemBrowse) {
    return SPDFMacBrowseDirectory(path, SPDFMacCurrentFileExplorerPreference(), systemBrowse);
}
