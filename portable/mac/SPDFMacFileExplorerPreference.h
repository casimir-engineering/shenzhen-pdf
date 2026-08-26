#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPDFMacFileExplorerPreference) {
    SPDFMacFileExplorerSystem = 0,
    SPDFMacFileExplorerShenzhenFiles = 1,
};

typedef NSURL* _Nullable (^SPDFMacExplorerApplicationLookup)(NSString* bundleIdentifier);
typedef void (^SPDFMacExplorerApplicationLauncher)(NSURL* applicationURL, NSArray<NSURL*>* URLs,
                                                    void (^completion)(NSError* _Nullable error));
typedef void (^SPDFMacSystemRevealHandler)(NSURL* URL, BOOL isDirectory);

FOUNDATION_EXPORT NSString* const SPDFMacShenzhenFilesBundleIdentifier;

NSString* SPDFMacFileExplorerPreferenceIdentifier(SPDFMacFileExplorerPreference preference);
SPDFMacFileExplorerPreference SPDFMacFileExplorerPreferenceFromIdentifier(NSString* _Nullable identifier);
BOOL SPDFMacShenzhenFilesIsAvailable(void);
SPDFMacFileExplorerPreference SPDFMacCurrentFileExplorerPreference(void);
void SPDFMacSetFileExplorerPreference(SPDFMacFileExplorerPreference preference);
void SPDFMacInstallFileExplorerSettingsMenu(NSMenu* settingsMenu);

// Returns NO only for an invalid path or missing handlers. A missing/failed
// Shenzhen Files launch falls back to the system file manager asynchronously.
BOOL SPDFMacRevealPathWithHandlers(NSString* path, SPDFMacFileExplorerPreference preference,
                                   SPDFMacExplorerApplicationLookup _Nullable lookup,
                                   SPDFMacExplorerApplicationLauncher _Nullable launcher,
                                   SPDFMacSystemRevealHandler systemReveal);
BOOL SPDFMacRevealPath(NSString* path, SPDFMacFileExplorerPreference preference);
BOOL SPDFMacRevealPathUsingPreference(NSString* path);

NS_ASSUME_NONNULL_END
