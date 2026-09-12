// The environment ocrmypdf and Argos Translate are launched in.
//
// Both are Python programs, and both broke on machines set up with conda,
// pyenv, an activated virtualenv or a python.org framework build. The app was
// handing them its own environment, so PYTHONHOME or VIRTUAL_ENV pointed the
// tool's interpreter at another installation's standard library; and the
// installers ran under `bash -lc`, so the dotfiles chose which python3 did the
// installing. This suite pins the scrub list, the PATH order, and the property
// that the Argos installer never asks the shell which python to use.

#import <Cocoa/Cocoa.h>

#import "../SPDFMacToolEnvironment.h"

static int gFailures;

static void Expect(BOOL condition, NSString* what) {
    if (condition) return;
    fprintf(stderr, "FAIL: %s\n", what.UTF8String);
    ++gFailures;
}

static BOOL ShellParses(NSString* script) {
    NSString* path = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[NSString stringWithFormat:@"spdf-env-%@.sh", NSUUID.UUID.UUIDString]];
    if (![script writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]) return NO;
    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    task.arguments = @[ @"-n", path ];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    [task launchAndReturnError:nil];
    [task waitUntilExit];
    BOOL ok = task.terminationStatus == 0;
    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    return ok;
}

int main(void) {
    @autoreleasepool {
        // --- What must never reach a child -----------------------------------
        for (NSString* key in @[
                 @"PYTHONHOME", @"PYTHONPATH", @"PYTHONSTARTUP", @"PYTHONUSERBASE", @"PYTHONEXECUTABLE",
                 @"__PYVENV_LAUNCHER__", @"VIRTUAL_ENV", @"CONDA_PREFIX", @"CONDA_DEFAULT_ENV", @"PYENV_ROOT",
                 @"PYENV_VERSION", @"PIP_TARGET", @"PIP_PREFIX", @"POETRY_ACTIVE", @"UV_PYTHON",
                 @"DYLD_LIBRARY_PATH", @"DYLD_INSERT_LIBRARIES", @"LD_LIBRARY_PATH", @"LD_PRELOAD",
                 @"TESSDATA_PREFIX"
             ])
            Expect(spdf_mac_tool_environment_key_is_banned(key),
                   [NSString stringWithFormat:@"%@ redirects an interpreter or loader and is dropped", key]);

        // --- What must still get through --------------------------------------
        for (NSString* key in @[ @"HOME", @"USER", @"TMPDIR", @"LANG", @"SSL_CERT_FILE", @"HTTPS_PROXY",
                                 @"HOMEBREW_PREFIX", @"PATH" ])
            Expect(!spdf_mac_tool_environment_key_is_banned(key),
                   [NSString stringWithFormat:@"%@ is the user's own setting and is kept", key]);

        // --- A machine mid-conda, launched from a terminal ---------------------
        NSDictionary* hostile = @{
            @"HOME" : NSHomeDirectory(),
            @"PATH" : @"/opt/miniconda3/bin:/usr/bin:/bin",
            @"PYTHONHOME" : @"/opt/miniconda3",
            @"PYTHONPATH" : @"/opt/miniconda3/lib/python3.11/site-packages",
            @"VIRTUAL_ENV" : @"/Users/someone/.venvs/work",
            @"CONDA_PREFIX" : @"/opt/miniconda3",
            @"TESSDATA_PREFIX" : @"/somewhere/else/tessdata",
            @"LANG" : @"C",
            @"HTTPS_PROXY" : @"http://proxy.example:3128"
        };
        NSDictionary* env = spdf_mac_tool_environment(hostile, @[ @"/opt/homebrew/bin/ocrmypdf" ], nil);
        for (NSString* key in @[ @"PYTHONHOME", @"PYTHONPATH", @"VIRTUAL_ENV", @"CONDA_PREFIX", @"TESSDATA_PREFIX" ])
            Expect(env[key] == nil, [NSString stringWithFormat:@"%@ does not survive the scrub", key]);
        Expect([env[@"HOME"] isEqual:hostile[@"HOME"]], @"HOME survives");
        Expect([env[@"HTTPS_PROXY"] isEqual:hostile[@"HTTPS_PROXY"]], @"a proxy setting survives: downloads need it");
        Expect([env[@"PYTHONIOENCODING"] isEqualToString:@"utf-8"], @"pipes are read as UTF-8 whatever the locale");
        Expect([env[@"LANG"] isEqualToString:@"en_US.UTF-8"], @"a non-UTF-8 locale is replaced");
        Expect([spdf_mac_tool_environment(@{@"LANG" : @"fr_FR.UTF-8"}, @[], nil)[@"LANG"]
                   isEqualToString:@"fr_FR.UTF-8"],
               @"a UTF-8 locale the user chose is left alone");

        // --- The extras a caller owns are applied after the scrub --------------
        NSDictionary* withTessdata =
            spdf_mac_tool_environment(hostile, @[], @{@"TESSDATA_PREFIX" : @"/ours"});
        Expect([withTessdata[@"TESSDATA_PREFIX"] isEqualToString:@"/ours"],
               @"the OCR path sets its own TESSDATA_PREFIX, and that one wins");

        // --- PATH order --------------------------------------------------------
        NSArray<NSString*>* dirs =
            spdf_mac_tool_search_directories(@[ @"/opt/homebrew/bin/ocrmypdf" ], @"/opt/miniconda3/bin:/usr/bin");
        Expect([dirs.firstObject isEqualToString:spdf_mac_tool_venv_bin_path()],
               @"the app's own virtualenv comes first");
        Expect([dirs containsObject:@"/opt/homebrew/bin"], @"the directory the resolved tool lives in is on PATH");
        Expect([dirs indexOfObject:@"/usr/bin"] < [dirs indexOfObject:@"/opt/miniconda3/bin"],
               @"an inherited directory ranks below the known prefixes, never above");
        Expect([NSSet setWithArray:dirs].count == dirs.count, @"no directory appears twice");

        // --- Discovery ---------------------------------------------------------
        NSArray<NSString*>* candidates =
            spdf_mac_tool_candidate_paths(@"argos-translate", @[ @"/opt/homebrew/bin/argos-translate" ]);
        Expect([candidates.firstObject
                   isEqualToString:[spdf_mac_tool_venv_bin_path()
                                       stringByAppendingPathComponent:@"argos-translate"]],
               @"the virtualenv copy is preferred over anything on the machine");
        Expect([candidates containsObject:@"/opt/homebrew/bin/argos-translate"],
               @"an existing working install is still found, so nobody is broken by this");
        Expect([candidates.lastObject hasSuffix:@".local/bin/argos-translate"], @"the pip --user path stays last");

        // --- Adopting a machine that already has the tools ----------------------
        // The installers only ran when a tool was MISSING, so a machine with
        // Argos from pipx or ocrmypdf from brew never saw any of this.
        Expect([spdf_mac_tool_pip_package_for_tool(@"ocrmypdf") isEqualToString:@"ocrmypdf"],
               @"ocrmypdf is a Python program and can move into the virtualenv");
        Expect([spdf_mac_tool_pip_package_for_tool(@"argos-translate") isEqualToString:@"argostranslate"] &&
                   [spdf_mac_tool_pip_package_for_tool(@"argospm") isEqualToString:@"argostranslate"],
               @"both Argos executables come from the one package");
        Expect(spdf_mac_tool_pip_package_for_tool(@"tesseract") == nil,
               @"tesseract is a C++ binary: it stays where the package manager put it");
        Expect(spdf_mac_tool_pip_package_for_tool(@"") == nil, @"and an empty name asks for nothing");

        // An empty bin directory this test owns: asking the real virtualenv would
        // make the answer depend on whether this machine had been adopted yet.
        NSString* emptyBin = [NSTemporaryDirectory()
            stringByAppendingPathComponent:[NSString stringWithFormat:@"spdf-bin-%@", NSUUID.UUID.UUIDString]];
        [NSFileManager.defaultManager createDirectoryAtPath:emptyBin
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:nil];
        NSArray<NSString*>* machineTools =
            @[ @"/opt/homebrew/bin/ocrmypdf", @"/opt/homebrew/bin/tesseract",
               [NSHomeDirectory() stringByAppendingPathComponent:@".local/bin/argos-translate"],
               [NSHomeDirectory() stringByAppendingPathComponent:@".local/bin/argospm"] ];
        NSArray<NSString*>* adopt = spdf_mac_tool_packages_to_adopt_in(machineTools, emptyBin);
        Expect([adopt containsObject:@"ocrmypdf"], @"a Homebrew ocrmypdf is adopted");
        Expect([adopt containsObject:@"argostranslate"], @"so is a pip --user Argos");
        Expect(adopt.count == 2, @"argos-translate and argospm ask for their package once, not twice");
        Expect(![adopt containsObject:@"tesseract"], @"and tesseract is never asked for");

        Expect([spdf_mac_tool_packages_to_adopt_in(@[ [emptyBin stringByAppendingPathComponent:@"ocrmypdf"] ],
                                                   emptyBin) count] == 0,
               @"a tool already running from the virtualenv is not adopted again");
        // And once pip has put it there, the adoption stops asking for it.
        NSString* installed = [emptyBin stringByAppendingPathComponent:@"ocrmypdf"];
        [NSFileManager.defaultManager createFileAtPath:installed
                                              contents:[NSData data]
                                            attributes:@{NSFilePosixPermissions : @(0755)}];
        Expect(![spdf_mac_tool_packages_to_adopt_in(machineTools, emptyBin) containsObject:@"ocrmypdf"],
               @"an adopted tool is not adopted a second time");
        Expect(spdf_mac_tool_packages_to_adopt_in(@[], emptyBin).count == 0, @"no tools, no work");
        [NSFileManager.defaultManager removeItemAtPath:emptyBin error:nil];

        NSString* adoption = spdf_mac_tool_adoption_script(@[ @"ocrmypdf", @"argostranslate" ]);
        Expect([adoption containsString:@"-m venv"], @"the adoption builds the environment if it is missing");
        Expect([adoption containsString:@"pip install --upgrade ocrmypdf"] &&
                   [adoption containsString:@"pip install --upgrade argostranslate"],
               @"and installs each package into it");
        Expect([adoption rangeOfString:@"command -v python3"].location == NSNotFound,
               @"by the same fixed-path Python as the installer");
        Expect([adoption rangeOfString:@"set -e"].location == NSNotFound &&
                   [adoption rangeOfString:@"exit"].location == NSNotFound,
               @"no set -e and no exit: this runs beside a live OCR run and must not affect it");
        Expect([adoption hasSuffix:@"true\n"], @"it always ends successfully");
        Expect([spdf_mac_tool_adoption_script(@[]) isEqualToString:@"true\n"],
               @"an empty adoption is a no-op, not an empty venv build");
        Expect(ShellParses(adoption), @"the adoption script parses");

        // --- The Argos installer ------------------------------------------------
        NSString* install = spdf_mac_tool_argos_install_script();
        Expect([install rangeOfString:@"command -v python3"].location == NSNotFound,
               @"it never asks the shell which python3: that answer is what differs between machines");
        Expect([install containsString:@"/usr/bin/python3"] && [install containsString:@"/opt/homebrew/bin/python3"],
               @"it probes fixed paths instead");
        Expect([install containsString:@"import venv"], @"and rejects a python that cannot build an environment");
        Expect([install containsString:@"-m venv"] && [install containsString:spdf_mac_tool_venv_path()],
               @"argostranslate goes into the app's own environment");
        Expect([install rangeOfString:@"pip install --user"].location == NSNotFound,
               @"never --user: that tree belongs to whichever python3 answered");
        Expect(ShellParses(install), @"the installer parses");

        if (gFailures == 0) puts("SPDFMacToolEnvironmentTests passed");
    }
    return gFailures == 0 ? 0 : 1;
}
