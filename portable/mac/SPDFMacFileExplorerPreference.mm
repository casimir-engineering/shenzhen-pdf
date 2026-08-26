#import "SPDFMacFileExplorerPreference.h"

NSString* const SPDFMacShenzhenFilesBundleIdentifier = @"com.intuition.shenzhenfiles";

static NSString* const kSPDFSystemExplorerIdentifier = @"system";
static NSString* const kSPDFShenzhenFilesExplorerIdentifier = @"shenzhen-files";
static NSString* const kSPDFFileExplorerPreferenceDefaultsKey = @"SPDFFileExplorerPreference";

NSString* SPDFMacFileExplorerPreferenceIdentifier(SPDFMacFileExplorerPreference preference) {
    return preference == SPDFMacFileExplorerShenzhenFiles ? kSPDFShenzhenFilesExplorerIdentifier
                                                          : kSPDFSystemExplorerIdentifier;
}

SPDFMacFileExplorerPreference SPDFMacFileExplorerPreferenceFromIdentifier(NSString* identifier) {
    return [identifier isEqualToString:kSPDFShenzhenFilesExplorerIdentifier] ? SPDFMacFileExplorerShenzhenFiles
                                                                             : SPDFMacFileExplorerSystem;
}

static NSURL* spdf_shenzhen_files_application_url(void) {
    return [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:SPDFMacShenzhenFilesBundleIdentifier];
}

BOOL SPDFMacShenzhenFilesIsAvailable(void) {
    return spdf_shenzhen_files_application_url() != nil;
}

SPDFMacFileExplorerPreference SPDFMacCurrentFileExplorerPreference(void) {
    NSString* identifier = [NSUserDefaults.standardUserDefaults stringForKey:kSPDFFileExplorerPreferenceDefaultsKey];
    return SPDFMacFileExplorerPreferenceFromIdentifier(identifier);
}

void SPDFMacSetFileExplorerPreference(SPDFMacFileExplorerPreference preference) {
    NSString* identifier = SPDFMacFileExplorerPreferenceIdentifier(preference);
    [NSUserDefaults.standardUserDefaults setObject:identifier forKey:kSPDFFileExplorerPreferenceDefaultsKey];
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

- (BOOL)validateMenuItem:(NSMenuItem*)menuItem {
    SPDFMacFileExplorerPreference preference = SPDFMacCurrentFileExplorerPreference();
    if (menuItem.action == @selector(useSystemFileExplorer:)) {
        menuItem.state = preference == SPDFMacFileExplorerSystem ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    if (menuItem.action == @selector(useShenzhenFilesExplorer:)) {
        menuItem.state = preference == SPDFMacFileExplorerShenzhenFiles ? NSControlStateValueOn : NSControlStateValueOff;
        return SPDFMacShenzhenFilesIsAvailable();
    }
    return YES;
}

@end

void SPDFMacInstallFileExplorerSettingsMenu(NSMenu* settingsMenu) {
    if (!settingsMenu) return;
    SPDFMacFileExplorerMenuTarget* target = SPDFMacFileExplorerMenuTarget.sharedTarget;
    NSMenu* submenu = [[NSMenu alloc] initWithTitle:@"File Manager"];
    NSMenuItem* finder = [submenu addItemWithTitle:@"Finder" action:@selector(useSystemFileExplorer:) keyEquivalent:@""];
    finder.target = target;
    NSMenuItem* shenzhenFiles =
        [submenu addItemWithTitle:@"Shenzhen Files" action:@selector(useShenzhenFilesExplorer:) keyEquivalent:@""];
    shenzhenFiles.target = target;
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:@"File Manager" action:nil keyEquivalent:@""];
    item.submenu = submenu;
    [settingsMenu addItem:item];
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
    if (preference != SPDFMacFileExplorerShenzhenFiles || !lookup || !launcher) {
        systemReveal(fileURL, isDirectory);
        return YES;
    }

    NSURL* applicationURL = lookup(SPDFMacShenzhenFilesBundleIdentifier);
    if (!applicationURL) {
        systemReveal(fileURL, isDirectory);
        return YES;
    }

    launcher(applicationURL, @[ fileURL ], ^(NSError* error) {
      if (error) systemReveal(fileURL, isDirectory);
    });
    return YES;
}

BOOL SPDFMacRevealPath(NSString* path, SPDFMacFileExplorerPreference preference) {
    NSWorkspace* workspace = NSWorkspace.sharedWorkspace;
    return SPDFMacRevealPathWithHandlers(
        path, preference,
        ^NSURL*(NSString* bundleIdentifier) {
          return [workspace URLForApplicationWithBundleIdentifier:bundleIdentifier];
        },
        ^(NSURL* applicationURL, NSArray<NSURL*>* URLs, void (^completion)(NSError*)) {
          NSWorkspaceOpenConfiguration* configuration = [NSWorkspaceOpenConfiguration configuration];
          configuration.activates = YES;
          [workspace openURLs:URLs
              withApplicationAtURL:applicationURL
                     configuration:configuration
                 completionHandler:^(NSRunningApplication* application, NSError* error) {
                   (void)application;
                   if (completion) completion(error);
                 }];
        },
        ^(NSURL* URL, BOOL isDirectory) {
          if (isDirectory) [workspace openURL:URL];
          else [workspace activateFileViewerSelectingURLs:@[ URL ]];
        });
}

BOOL SPDFMacRevealPathUsingPreference(NSString* path) {
    return SPDFMacRevealPath(path, SPDFMacCurrentFileExplorerPreference());
}
