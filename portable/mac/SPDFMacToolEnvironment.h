#import <Cocoa/Cocoa.h>

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

// The installer for Argos Translate: builds the app's virtualenv from a Python
// found at a FIXED path (never `command -v python3`, which is the ambiguity
// this whole file exists to remove) and installs argostranslate into it.
FOUNDATION_EXPORT NSString* spdf_mac_tool_argos_install_script(void);
