#import <Cocoa/Cocoa.h>

#import "SPDFMacPassword.h"

static int failures;

#define CHECK(condition, message)                                                                                       \
    do {                                                                                                                \
        if (!(condition)) {                                                                                             \
            fprintf(stderr, "FAIL: %s\n", message);                                                                   \
            failures++;                                                                                                 \
        }                                                                                                               \
    } while (0)

static NSString* temporary_file(void) {
    NSString* directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:directory
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
    NSString* path = [directory stringByAppendingPathComponent:@"source.pdf"];
    [@"first" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return path;
}

int main(void) {
    @autoreleasepool {
        SPDFPasswordCredentialStore* store = SPDFPasswordCredentialStore.sharedStore;
        [store removeAllCredentials];
        NSString* path = temporary_file();
        NSString* sourceIdentity = [store sourceIdentityTokenForSourcePath:path];
        NSString* noCredentialToken = [store cacheTokenForSourcePath:path];
        CHECK([store credentialForSourcePath:path] == nil, "fresh source unexpectedly has a credential");

        SPDFPasswordCredential* credential = [[SPDFPasswordCredential alloc] initWithPassword:@"private-secret"];
        [store setCredential:credential forSourcePath:path];
        CHECK([store credentialForSourcePath:path] == credential, "stored credential was not returned");
        NSString* credentialToken = [store cacheTokenForSourcePath:path];
        CHECK(![credentialToken isEqualToString:noCredentialToken], "credential did not invalidate worker cache key");
        CHECK([[store sourceIdentityTokenForSourcePath:path] isEqualToString:sourceIdentity],
              "storing a credential changed the source identity token");

        [NSThread sleepForTimeInterval:0.01];
        [@"source identity changed" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        CHECK(![[store sourceIdentityTokenForSourcePath:path] isEqualToString:sourceIdentity],
              "source mutation did not change the source identity token");
        CHECK([store credentialForSourcePath:path] == nil, "source mutation did not invalidate credential");
        CHECK(![[store cacheTokenForSourcePath:path] isEqualToString:credentialToken],
              "source mutation did not invalidate worker cache token");

        SPDFPasswordCredential* replacement = [[SPDFPasswordCredential alloc] initWithPassword:@"owner-secret"];
        [store setCredential:replacement forSourcePath:path];
        NSString* replacementToken = [store cacheTokenForSourcePath:path];
        NSString* replacementIdentity = [store sourceIdentityTokenForSourcePath:path];
        [store setCredential:credential forSourcePath:path];
        CHECK(![[store cacheTokenForSourcePath:path] isEqualToString:replacementToken],
              "credential replacement did not invalidate worker cache token");
        CHECK([[store sourceIdentityTokenForSourcePath:path] isEqualToString:replacementIdentity],
              "credential replacement changed the source identity token");

        [store invalidateCredentialForSourcePath:path];
        CHECK([store credentialForSourcePath:path] == nil, "explicit invalidation failed");
        [NSFileManager.defaultManager removeItemAtPath:path.stringByDeletingLastPathComponent error:nil];
        [store removeAllCredentials];
    }
    if (failures) return 1;
    puts("SPDF mac password-store tests passed");
    return 0;
}
