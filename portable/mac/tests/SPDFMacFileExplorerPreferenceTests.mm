#import <Cocoa/Cocoa.h>

#import "SPDFMacFileExplorerPreference.h"

static int failures;

#define CHECK(condition, message)                   \
    do {                                            \
        if (!(condition)) {                         \
            fprintf(stderr, "FAIL: %s\n", message); \
            failures++;                             \
        }                                           \
    } while (0)

static NSString* make_fixture(BOOL directory) {
    NSString* root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:root
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
    if (directory) return root;
    NSString* file = [root stringByAppendingPathComponent:@"document.pdf"];
    [@"fixture" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return file;
}

static void remove_fixture(NSString* path) {
    NSString* root = [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:NULL] &&
                             [path.pathExtension.lowercaseString isEqualToString:@"pdf"]
                         ? path.stringByDeletingLastPathComponent
                         : path;
    [NSFileManager.defaultManager removeItemAtPath:root error:nil];
}

static void test_identifiers(void) {
    CHECK([SPDFMacFileExplorerPreferenceIdentifier(SPDFMacFileExplorerSystem) isEqualToString:@"system"],
          "system identifier changed");
    CHECK([SPDFMacFileExplorerPreferenceIdentifier(SPDFMacFileExplorerShenzhenFiles)
              isEqualToString:@"shenzhen-files"],
          "Shenzhen Files identifier changed");
    CHECK(SPDFMacFileExplorerPreferenceFromIdentifier(@"shenzhen-files") == SPDFMacFileExplorerShenzhenFiles,
          "saved Shenzhen Files preference did not round-trip");
    CHECK(SPDFMacFileExplorerPreferenceFromIdentifier(@"unknown") == SPDFMacFileExplorerSystem,
          "unknown preference did not fall back to system");
    CHECK(SPDFMacFileExplorerPreferenceFromIdentifier(nil) == SPDFMacFileExplorerSystem,
          "missing preference did not preserve the system default");
}

static void test_persistence_and_menu(void) {
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    NSString* saved = [defaults stringForKey:@"SPDFFileExplorerPreference"];
    SPDFMacSetFileExplorerPreference(SPDFMacFileExplorerShenzhenFiles);
    CHECK(SPDFMacCurrentFileExplorerPreference() == SPDFMacFileExplorerShenzhenFiles,
          "Shenzhen Files preference was not persisted");
    SPDFMacSetFileExplorerPreference(SPDFMacFileExplorerSystem);
    CHECK(SPDFMacCurrentFileExplorerPreference() == SPDFMacFileExplorerSystem,
          "system preference was not persisted");

    NSMenu* settings = [[NSMenu alloc] initWithTitle:@"Settings"];
    SPDFMacInstallFileExplorerSettingsMenu(settings);
    CHECK(settings.numberOfItems == 1, "file-manager settings item was not installed");
    NSMenuItem* item = [settings itemAtIndex:0];
    CHECK([item.title isEqualToString:@"File Manager"], "file-manager settings title changed");
    CHECK(item.submenu.numberOfItems == 2, "file-manager submenu does not contain both choices");

    if (saved) [defaults setObject:saved forKey:@"SPDFFileExplorerPreference"];
    else [defaults removeObjectForKey:@"SPDFFileExplorerPreference"];
}

static void test_system_route(void) {
    NSString* path = make_fixture(NO);
    __block NSInteger lookupCount = 0;
    __block NSInteger launchCount = 0;
    __block NSInteger systemCount = 0;
    __block BOOL revealedDirectory = YES;

    BOOL accepted = SPDFMacRevealPathWithHandlers(
        path, SPDFMacFileExplorerSystem,
        ^NSURL*(NSString* bundleIdentifier) {
          (void)bundleIdentifier;
          lookupCount++;
          return nil;
        },
        ^(NSURL* applicationURL, NSArray<NSURL*>* URLs, void (^completion)(NSError*)) {
          (void)applicationURL;
          (void)URLs;
          (void)completion;
          launchCount++;
        },
        ^(NSURL* URL, BOOL isDirectory) {
          systemCount++;
          revealedDirectory = isDirectory;
          CHECK([URL.path isEqualToString:path], "system reveal received the wrong path");
        });
    CHECK(accepted, "valid system reveal was rejected");
    CHECK(lookupCount == 0 && launchCount == 0, "system route consulted Shenzhen Files");
    CHECK(systemCount == 1 && !revealedDirectory, "system file route was not selected exactly once");
    remove_fixture(path);
}

static void test_shenzhen_route(void) {
    NSString* path = make_fixture(YES);
    NSURL* appURL = [NSURL fileURLWithPath:@"/Applications/Shenzhen Files.app" isDirectory:YES];
    __block NSInteger systemCount = 0;
    __block NSInteger launchCount = 0;

    BOOL accepted = SPDFMacRevealPathWithHandlers(
        path, SPDFMacFileExplorerShenzhenFiles,
        ^NSURL*(NSString* bundleIdentifier) {
          CHECK([bundleIdentifier isEqualToString:SPDFMacShenzhenFilesBundleIdentifier],
                "unexpected Shenzhen Files bundle identifier");
          return appURL;
        },
        ^(NSURL* applicationURL, NSArray<NSURL*>* URLs, void (^completion)(NSError*)) {
          launchCount++;
          CHECK([applicationURL isEqual:appURL], "launcher received the wrong application");
          CHECK(URLs.count == 1 && [URLs.firstObject.path isEqualToString:path], "launcher received the wrong path");
          completion(nil);
        },
        ^(NSURL* URL, BOOL isDirectory) {
          (void)URL;
          (void)isDirectory;
          systemCount++;
        });
    CHECK(accepted && launchCount == 1, "Shenzhen Files route was not launched");
    CHECK(systemCount == 0, "successful Shenzhen Files launch also opened Finder");
    remove_fixture(path);
}

static void test_fallbacks(void) {
    NSString* path = make_fixture(NO);
    for (NSInteger mode = 0; mode < 2; ++mode) {
        __block NSInteger systemCount = 0;
        SPDFMacExplorerApplicationLookup lookup = ^NSURL*(NSString* bundleIdentifier) {
          (void)bundleIdentifier;
          return mode == 0 ? nil : [NSURL fileURLWithPath:@"/Applications/Shenzhen Files.app"];
        };
        SPDFMacExplorerApplicationLauncher launcher =
            ^(NSURL* applicationURL, NSArray<NSURL*>* URLs, void (^completion)(NSError*)) {
              (void)applicationURL;
              (void)URLs;
              NSError* error = [NSError errorWithDomain:@"test" code:1 userInfo:nil];
              completion(error);
            };
        BOOL accepted = SPDFMacRevealPathWithHandlers(path, SPDFMacFileExplorerShenzhenFiles, lookup, launcher,
                                                      ^(NSURL* URL, BOOL isDirectory) {
                                                        (void)URL;
                                                        (void)isDirectory;
                                                        systemCount++;
                                                      });
        CHECK(accepted && systemCount == 1, "Shenzhen Files failure did not fall back exactly once");
    }
    CHECK(!SPDFMacRevealPathWithHandlers(@"/definitely/missing", SPDFMacFileExplorerSystem, nil, nil,
                                        ^(NSURL* URL, BOOL isDirectory) {
                                          (void)URL;
                                          (void)isDirectory;
                                        }),
          "missing path was accepted");
    remove_fixture(path);
}

int main(void) {
    @autoreleasepool {
        test_identifiers();
        test_persistence_and_menu();
        test_system_route();
        test_shenzhen_route();
        test_fallbacks();
    }
    if (failures) return 1;
    puts("SPDF mac file-explorer preference tests passed");
    return 0;
}
