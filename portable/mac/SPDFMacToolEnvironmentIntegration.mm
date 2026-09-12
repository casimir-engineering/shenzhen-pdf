#import "SPDFMacToolEnvironment.h"

// The app-facing half of SPDFMacToolEnvironment.h: the environment every
// external tool is launched with, and the background adoption that moves a
// machine still running its own copies onto the virtualenv. Split from the pure
// builders so those can be linked, and tested, without the whole app delegate.

@implementation ShenzhenMacDelegate (SPDFMacToolEnvironment)

- (NSDictionary<NSString*, NSString*>*)taskEnvironmentWithToolPaths:(NSArray<NSString*>*)toolPaths {
    return [self taskEnvironmentWithToolPaths:toolPaths extra:nil];
}

- (NSDictionary<NSString*, NSString*>*)taskEnvironmentWithToolPaths:(NSArray<NSString*>*)toolPaths
                                                              extra:(NSDictionary<NSString*, NSString*>*)extra {
    [self adoptToolsIntoPrivateEnvironment:toolPaths];
    return spdf_mac_tool_environment(NSProcessInfo.processInfo.environment, toolPaths, extra);
}

- (void)adoptToolsIntoPrivateEnvironment:(NSArray<NSString*>*)toolPaths {
    NSArray<NSString*>* packages = spdf_mac_tool_packages_to_adopt(toolPaths);
    if (!packages.count) return;

    // At most one adoption per package per session. argostranslate brings spacy,
    // stanza, onnxruntime and torch with it -- three quarters of a gigabyte --
    // so a second OCR or translation run while the first is still downloading
    // must not start it again. Once the files are on disk the check above is a
    // stat and nothing starts.
    static NSMutableSet<NSString*>* started;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      started = [NSMutableSet set];
    });
    NSMutableArray<NSString*>* pending = [NSMutableArray array];
    for (NSString* package in packages)
        if (![started containsObject:package]) [pending addObject:package];
    if (!pending.count) return;
    [started addObjectsFromArray:pending];

    // Detached and unwaited: the run this was called from starts in the same
    // breath. pip only creates the executables once an install has succeeded,
    // so until then discovery keeps finding the copy already on the machine,
    // and an adoption that fails or is killed leaves it exactly as it was.
    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    task.arguments = @[ @"-c", spdf_mac_tool_adoption_script(pending) ];
    task.environment = spdf_mac_tool_environment(NSProcessInfo.processInfo.environment, @[], nil);
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    [task launchAndReturnError:nil];
}

@end
