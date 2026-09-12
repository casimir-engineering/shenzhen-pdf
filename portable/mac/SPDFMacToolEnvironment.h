#import <Cocoa/Cocoa.h>

#import "SPDFMacDelegatePrivate.h"

// The environment external tools run in.
//
// Shenzhen PDF shells out to two Python programs -- ocrmypdf and Argos
// Translate -- and both broke on machines whose Python was set up differently:
// conda, pyenv, a python.org framework build, an activated virtualenv, a
// `pip install --user` tree. The cause was always the same two leaks.
//
// First, the app handed those tools its OWN environment. A GUI app launched
// from a terminal, or on a machine with `launchctl setenv`, carries PYTHONHOME,
// PYTHONPATH, VIRTUAL_ENV, CONDA_PREFIX or __PYVENV_LAUNCHER__ -- variables
// that point an interpreter at ANOTHER installation's standard library.
// Homebrew's ocrmypdf has its own vendored interpreter; give it a PYTHONHOME
// belonging to conda and it fails to import its own modules.
//
// Second, the installers ran under `bash -lc`. A login shell sources the
// user's dotfiles, so whichever `python3` their conda/pyenv hook put first is
// the one that installed the tool -- and nothing guaranteed the app would find
// that same interpreter later.
//
// So: tools are launched with a scrubbed environment and a deterministic PATH,
// installers run without a login shell, and Argos is installed into a
// virtualenv the app owns rather than into whatever Python happens to answer.

// The virtualenv the app installs Python tools into, and the executables in it.
// Under Application Support, beside the tesseract data, so it is removable with
// the rest of the app's state and needs no administrator rights.
FOUNDATION_EXPORT NSString* spdf_mac_tool_venv_path(void);
FOUNDATION_EXPORT NSString* spdf_mac_tool_venv_bin_path(void);

// Where to look for `tool`, in order: the app's own virtualenv first, then the
// caller's fixed candidates, then ~/.local/bin. A PATH sweep still follows in
// the caller, so a machine that already had a working install keeps it.
FOUNDATION_EXPORT NSArray<NSString*>* spdf_mac_tool_candidate_paths(NSString* tool,
                                                                    NSArray<NSString*>* candidates);

// The PATH a tool and its own subprocesses see: the virtualenv, the directories
// the resolved tools live in, then the usual prefixes, then whatever the app
// inherited -- deduplicated, in that order.
FOUNDATION_EXPORT NSArray<NSString*>* spdf_mac_tool_search_directories(NSArray<NSString*>* toolPaths,
                                                                       NSString* inheritedPath);

// YES for a variable that redirects an interpreter or the dynamic loader at
// another installation. These are dropped rather than passed through.
FOUNDATION_EXPORT BOOL spdf_mac_tool_environment_key_is_banned(NSString* key);

// `inherited` scrubbed of those variables, with a deterministic PATH, UTF-8 I/O
// for the pipes the app reads, and `extra` applied last so a caller can set
// something it owns (TESSDATA_PREFIX) that the scrub would otherwise drop.
FOUNDATION_EXPORT NSDictionary<NSString*, NSString*>* spdf_mac_tool_environment(
    NSDictionary<NSString*, NSString*>* inherited, NSArray<NSString*>* toolPaths,
    NSDictionary<NSString*, NSString*>* extra);

// Moving a machine that ALREADY has these tools onto the virtualenv.
//
// The installers only ever ran when a tool was missing, so a machine that had
// Argos from `pipx`, from `pip install --user`, or ocrmypdf from a Python that
// has since changed underneath it, stayed on that copy forever: discovery found
// it, the installer never fired, and none of this applied to it. These adopt an
// existing install instead -- the packages are installed into the virtualenv in
// the background, and because pip only creates the executables at the END of a
// successful install, discovery keeps using the copy already on the machine
// until the new one is complete. A failed or abandoned adoption changes nothing.

// The pip package providing `tool`, or nil for one that is not a Python program:
// tesseract is a C++ binary and stays wherever the package manager put it.
FOUNDATION_EXPORT NSString* spdf_mac_tool_pip_package_for_tool(NSString* toolName);

// Which packages a set of resolved tool paths would need in order to run from
// the virtualenv. A tool already running from it is skipped, so this empties
// out once a machine has been adopted and the check costs a stat thereafter.
FOUNDATION_EXPORT NSArray<NSString*>* spdf_mac_tool_packages_to_adopt(NSArray<NSString*>* toolPaths);
// The same answer against an arbitrary bin directory. The result depends on
// what is installed, so a test that asked the real one would pass or fail
// depending on whether this machine had been adopted yet -- which is exactly
// what happened the first time the adoption ran here.
FOUNDATION_EXPORT NSArray<NSString*>* spdf_mac_tool_packages_to_adopt_in(NSArray<NSString*>* toolPaths,
                                                                         NSString* venvBinPath);

// Creates the virtualenv if it is missing and installs `packages` into it.
// Guarded throughout and ends in `true`: an adoption that cannot run must never
// take down the OCR or translation run that triggered it.
FOUNDATION_EXPORT NSString* spdf_mac_tool_adoption_script(NSArray<NSString*>* packages);

// The installer for Argos Translate: builds the app's virtualenv from a Python
// found at a FIXED path (never `command -v python3`, which is the ambiguity
// this whole file exists to remove) and installs argostranslate into it.
FOUNDATION_EXPORT NSString* spdf_mac_tool_argos_install_script(void);

@interface ShenzhenMacDelegate (SPDFMacToolEnvironment)
// The controlled environment for an external tool launch. Every NSTask that
// runs a tool goes through this, and it is also where a machine still on its
// own copies is put on the path to the virtualenv.
- (NSDictionary<NSString*, NSString*>*)taskEnvironmentWithToolPaths:(NSArray<NSString*>*)toolPaths;
- (NSDictionary<NSString*, NSString*>*)taskEnvironmentWithToolPaths:(NSArray<NSString*>*)toolPaths
                                                              extra:(NSDictionary<NSString*, NSString*>*)extra;
// Starts the background adoption for any of `toolPaths` not yet in the
// virtualenv. Returns immediately; at most one adoption per package per session.
- (void)adoptToolsIntoPrivateEnvironment:(NSArray<NSString*>*)toolPaths;
@end
