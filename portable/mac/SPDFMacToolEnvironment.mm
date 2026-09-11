#import "SPDFMacToolEnvironment.h"

// Exact names and prefixes, checked against what conda, pyenv, virtualenv, uv,
// poetry and the python.org framework launcher actually export.
static NSArray<NSString*>* spdf_banned_prefixes(void) {
    return @[ @"PYTHON", @"PIP_", @"CONDA", @"PYENV", @"VIRTUAL_ENV", @"POETRY_", @"UV_", @"DYLD_" ];
}

static NSArray<NSString*>* spdf_banned_names(void) {
    // __PYVENV_LAUNCHER__ is set by the macOS framework build and makes a child
    // interpreter adopt the parent's prefix. TESSDATA_PREFIX is dropped because
    // the OCR path sets its own; a stale one points at another tesseract's data.
    return @[ @"__PYVENV_LAUNCHER__", @"TESSDATA_PREFIX", @"LD_LIBRARY_PATH", @"LD_PRELOAD" ];
}

NSString* spdf_mac_tool_venv_path(void) {
    return [NSHomeDirectory()
        stringByAppendingPathComponent:@"Library/Application Support/ShenzhenPDF/python"];
}

NSString* spdf_mac_tool_venv_bin_path(void) {
    return [spdf_mac_tool_venv_path() stringByAppendingPathComponent:@"bin"];
}

NSArray<NSString*>* spdf_mac_tool_candidate_paths(NSString* tool, NSArray<NSString*>* candidates) {
    if (!tool.length) return @[];
    NSMutableArray<NSString*>* paths =
        [@[ [spdf_mac_tool_venv_bin_path() stringByAppendingPathComponent:tool] ] mutableCopy];
    for (NSString* candidate in candidates)
        if (candidate.length && ![paths containsObject:candidate]) [paths addObject:candidate];
    NSString* userPath =
        [[NSHomeDirectory() stringByAppendingPathComponent:@".local/bin"] stringByAppendingPathComponent:tool];
    if (![paths containsObject:userPath]) [paths addObject:userPath];
    return paths;
}

NSArray<NSString*>* spdf_mac_tool_search_directories(NSArray<NSString*>* toolPaths, NSString* inheritedPath) {
    NSMutableArray<NSString*>* dirs = [NSMutableArray array];
    void (^add)(NSString*) = ^(NSString* dir) {
      if (dir.length && ![dirs containsObject:dir]) [dirs addObject:dir];
    };

    add(spdf_mac_tool_venv_bin_path());
    for (NSString* toolPath in toolPaths) add(toolPath.stringByDeletingLastPathComponent);
    add([NSHomeDirectory() stringByAppendingPathComponent:@".local/bin"]);
    for (NSString* dir in @[
             @"/opt/homebrew/bin", @"/opt/homebrew/sbin", @"/usr/local/bin", @"/usr/local/sbin", @"/opt/local/bin",
             @"/usr/bin", @"/bin", @"/usr/sbin", @"/sbin"
         ])
        add(dir);
    for (NSString* dir in [(inheritedPath ?: @"") componentsSeparatedByString:@":"]) add(dir);
    return dirs;
}

BOOL spdf_mac_tool_environment_key_is_banned(NSString* key) {
    if (!key.length) return NO;
    if ([spdf_banned_names() containsObject:key]) return YES;
    for (NSString* prefix in spdf_banned_prefixes())
        if ([key hasPrefix:prefix]) return YES;
    return NO;
}

NSDictionary<NSString*, NSString*>* spdf_mac_tool_environment(NSDictionary<NSString*, NSString*>* inherited,
                                                              NSArray<NSString*>* toolPaths,
                                                              NSDictionary<NSString*, NSString*>* extra) {
    NSMutableDictionary<NSString*, NSString*>* env = [NSMutableDictionary dictionary];
    for (NSString* key in inherited)
        if (!spdf_mac_tool_environment_key_is_banned(key)) env[key] = inherited[key];

    env[@"PATH"] = [spdf_mac_tool_search_directories(toolPaths, inherited[@"PATH"]) componentsJoinedByString:@":"];
    // The app reads these tools' stdout through a pipe, where Python would
    // otherwise pick an encoding from a locale a GUI process may not have.
    env[@"PYTHONIOENCODING"] = @"utf-8";
    NSString* lang = inherited[@"LANG"];
    if (![lang.uppercaseString containsString:@"UTF-8"]) env[@"LANG"] = @"en_US.UTF-8";

    for (NSString* key in extra) env[key] = extra[key];
    return env;
}

NSString* spdf_mac_tool_argos_install_script(void) {
    // No `command -v python3`: that is the interpreter the user's dotfiles
    // chose, and it is the thing that differs between machines. These three
    // paths are the ones macOS and Homebrew actually put a python3 at, and the
    // `import venv` probe rejects a stub that cannot build an environment.
    return [NSString
        stringWithFormat:@"set -e\n"
                          "VENV=\"%@\"\n"
                          "PY=\"\"\n"
                          "for candidate in /opt/homebrew/bin/python3 /usr/local/bin/python3 "
                          "/usr/bin/python3; do\n"
                          "  if [ -x \"$candidate\" ] && \"$candidate\" -c 'import venv' >/dev/null 2>&1; "
                          "then PY=\"$candidate\"; break; fi\n"
                          "done\n"
                          "if [ -z \"$PY\" ]; then echo 'No Python 3 with venv support was found. Install "
                          "Python 3 (or Homebrew) and try again.'; exit 1; fi\n"
                          "if [ ! -x \"$VENV/bin/python\" ]; then\n"
                          "  echo \"Creating a private Python environment with $PY...\"\n"
                          "  rm -rf \"$VENV\"\n"
                          "  \"$PY\" -m venv \"$VENV\"\n"
                          "else\n"
                          "  echo 'Using the existing private Python environment.'\n"
                          "fi\n"
                          "echo 'Installing Argos Translate...'\n"
                          "\"$VENV/bin/python\" -m pip install --upgrade pip >/dev/null 2>&1 || true\n"
                          "\"$VENV/bin/python\" -m pip install --upgrade argostranslate\n"
                          "test -x \"$VENV/bin/argos-translate\"\n"
                          "test -x \"$VENV/bin/argospm\"\n"
                          "echo 'Argos Translate installed.'\n",
                         spdf_mac_tool_venv_path()];
}
