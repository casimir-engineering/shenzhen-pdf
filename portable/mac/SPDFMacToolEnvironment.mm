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

// Finding a Python and building the virtualenv. Shared by the installer and by
// the adoption of a machine that already has the tools, because both need the
// same guarantee: a Python chosen by path, not by whatever a shell profile put
// first.
static NSString* spdf_venv_preamble(void) {
    return [NSString
        stringWithFormat:@"VENV=\"%@\"\n"
                          "PY=\"\"\n"
                          "for candidate in /opt/homebrew/bin/python3 /usr/local/bin/python3 "
                          "/usr/bin/python3; do\n"
                          "  if [ -x \"$candidate\" ] && \"$candidate\" -c 'import venv' >/dev/null 2>&1; "
                          "then PY=\"$candidate\"; break; fi\n"
                          "done\n",
                         spdf_mac_tool_venv_path()];
}

NSString* spdf_mac_tool_pip_package_for_tool(NSString* toolName) {
    if ([toolName isEqualToString:@"ocrmypdf"]) return @"ocrmypdf";
    if ([toolName isEqualToString:@"argos-translate"] || [toolName isEqualToString:@"argospm"])
        return @"argostranslate";
    return nil;  // tesseract, and anything else that is not a Python program.
}

NSArray<NSString*>* spdf_mac_tool_packages_to_adopt(NSArray<NSString*>* toolPaths) {
    return spdf_mac_tool_packages_to_adopt_in(toolPaths, spdf_mac_tool_venv_bin_path());
}

NSArray<NSString*>* spdf_mac_tool_packages_to_adopt_in(NSArray<NSString*>* toolPaths, NSString* bin) {
    NSMutableArray<NSString*>* packages = [NSMutableArray array];
    for (NSString* toolPath in toolPaths) {
        NSString* name = toolPath.lastPathComponent;
        NSString* package = spdf_mac_tool_pip_package_for_tool(name);
        if (!package || [packages containsObject:package]) continue;
        // Already running from the virtualenv, or already installed there:
        // nothing to adopt, and this is the stat that ends the work for good.
        if ([toolPath hasPrefix:[bin stringByAppendingString:@"/"]]) continue;
        if ([NSFileManager.defaultManager isExecutableFileAtPath:[bin stringByAppendingPathComponent:name]])
            continue;
        [packages addObject:package];
    }
    return packages;
}

NSString* spdf_mac_tool_adoption_script(NSArray<NSString*>* packages) {
    if (!packages.count) return @"true\n";
    NSMutableString* script = [spdf_venv_preamble() mutableCopy];
    // No `set -e` and no `exit`: this runs beside a live OCR or translation run
    // and must be incapable of affecting it.
    [script appendString:@"if [ -n \"$PY\" ]; then\n"
                          "  if [ ! -x \"$VENV/bin/python\" ]; then \"$PY\" -m venv \"$VENV\" || true; fi\n"
                          "  if [ -x \"$VENV/bin/python\" ]; then\n"
                          "    \"$VENV/bin/python\" -m pip install --upgrade pip >/dev/null 2>&1 || true\n"];
    for (NSString* package in packages)
        [script appendFormat:@"    \"$VENV/bin/python\" -m pip install --upgrade %@ || "
                              "echo \"Could not move %@ into the private environment; the existing "
                              "install keeps being used.\"\n",
                             package, package];
    [script appendString:@"  fi\nfi\ntrue\n"];
    return script;
}

NSString* spdf_mac_tool_argos_install_script(void) {
    // No `command -v python3`: that is the interpreter the user's dotfiles
    // chose, and it is the thing that differs between machines. The preamble
    // probes fixed paths instead, and `import venv` rejects a stub that cannot
    // build an environment.
    return [NSString
        stringWithFormat:@"set -e\n"
                          "%@"
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
                         spdf_venv_preamble()];
}
