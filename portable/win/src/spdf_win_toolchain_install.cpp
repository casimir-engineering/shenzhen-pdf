/* spdf_win_toolchain_install.cpp -- running one install-plan step with a live
 * log: the winget, pip, argospm and traineddata steps are a single streamed
 * command each; the Ghostscript step is the four-part sequence the header
 * describes (release API -> curl -> certutil against SHA512SUMS -> silent
 * install), because the winget catalogue on this machine has no Ghostscript.
 *
 * ELEVATION. CreateProcess cannot raise UAC: an installer whose manifest asks
 * for administrator fails with ERROR_ELEVATION_REQUIRED (740). The NSIS
 * installers (Ghostscript's; Tesseract's, behind winget) do ask. For the one
 * this file launches itself the fallback is ShellExecuteExW with the "runas"
 * verb, which shows the consent prompt and can capture no output -- so the
 * log says what is about to happen before the prompt appears. */
#include "spdf_win_toolchain.h"

#include <windows.h>

#include <shellapi.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void say(spdf_win_toolchain_line_fn cb, void* user, const char* fmt, ...) {
    char line[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(line, sizeof(line), fmt, ap);
    va_end(ap);
    if (cb) cb(line, user);
}

static int run_streamed(const char* cmd, void* cancel, spdf_win_toolchain_line_fn cb, void* user, char** stdout_out) {
    SpdfWinToolchainRun run;
    int rc;
    memset(&run, 0, sizeof(run));
    run.command_line = cmd;
    run.cancel = cancel;
    run.merge_stderr = stdout_out == NULL; /* captured runs keep stderr for the log only */
    run.on_line = stdout_out ? NULL : cb;
    run.user = user;
    run.stdout_out = stdout_out;
    say(cb, user, "> %s", cmd);
    rc = spdf_win_toolchain_run_capture(&run);
    if (rc == SPDF_WIN_TC_SPAWN_FAILED) say(cb, user, "Could not start: %s", run.error);
    else if (rc == SPDF_WIN_TC_CANCELLED) say(cb, user, "Cancelled.");
    else if (rc != 0) say(cb, user, "Exited with code %d.", rc);
    return rc;
}

static int ensure_dir_utf8(const char* dir) {
    wchar_t w[SPDF_WIN_TC_PATH];
    wchar_t* p;
    if (!MultiByteToWideChar(CP_UTF8, 0, dir, -1, w, SPDF_WIN_TC_PATH)) return 0;
    /* mkdir -p, one component at a time. */
    for (p = w + 3; *p; ++p) {
        if (*p == L'\\' || *p == L'/') {
            *p = 0;
            CreateDirectoryW(w, NULL);
            *p = L'\\';
        }
    }
    CreateDirectoryW(w, NULL);
    return GetFileAttributesW(w) != INVALID_FILE_ATTRIBUTES;
}

/* Run an installer that may need consent: CreateProcess first (silent when
 * the process is already elevated), ShellExecuteEx "runas" on 740. */
static int run_installer_maybe_elevated(const char* installer, const char* params, spdf_win_toolchain_line_fn cb,
                                        void* user) {
    char cmd[SPDF_WIN_TC_CMD];
    SpdfWinToolchainRun run;
    int rc;
    wchar_t wexe[SPDF_WIN_TC_PATH], wparams[SPDF_WIN_TC_CMD];
    SHELLEXECUTEINFOW sei;
    DWORD code = 1;

    snprintf(cmd, sizeof(cmd), "%s", "");
    spdf_win_toolchain_quote_arg(installer, cmd, sizeof(cmd));
    snprintf(cmd + strlen(cmd), sizeof(cmd) - strlen(cmd), " %s", params);
    memset(&run, 0, sizeof(run));
    run.command_line = cmd;
    run.merge_stderr = 1;
    run.on_line = cb;
    run.user = user;
    say(cb, user, "> %s", cmd);
    rc = spdf_win_toolchain_run_capture(&run);
    if (rc != SPDF_WIN_TC_SPAWN_FAILED || !strstr(run.error, "(740)")) return rc;

    say(cb, user, "The installer asks for administrator rights; Windows will now show a consent prompt.");
    if (!MultiByteToWideChar(CP_UTF8, 0, installer, -1, wexe, SPDF_WIN_TC_PATH) ||
        !MultiByteToWideChar(CP_UTF8, 0, params, -1, wparams, SPDF_WIN_TC_CMD))
        return SPDF_WIN_TC_SPAWN_FAILED;
    memset(&sei, 0, sizeof(sei));
    sei.cbSize = sizeof(sei);
    sei.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NO_CONSOLE | SEE_MASK_FLAG_NO_UI;
    sei.lpVerb = L"runas";
    sei.lpFile = wexe;
    sei.lpParameters = wparams;
    sei.nShow = SW_HIDE;
    if (!ShellExecuteExW(&sei) || !sei.hProcess) {
        say(cb, user, "Consent was refused or the installer could not start (%lu).", (unsigned long)GetLastError());
        return SPDF_WIN_TC_SPAWN_FAILED;
    }
    WaitForSingleObject(sei.hProcess, INFINITE);
    GetExitCodeProcess(sei.hProcess, &code);
    CloseHandle(sei.hProcess);
    if (code != 0) say(cb, user, "Installer exited with code %lu.", (unsigned long)code);
    return (int)code;
}

/* "gs10071w64.exe" -> "10.07.1": the installer's own default directory name,
 * so our per-user tree mirrors the machine-wide one. */
static void gs_version_from_asset(const char* url, char* out, size_t out_bytes) {
    const char* slash = strrchr(url, '/');
    const char* d = slash ? slash + 3 : url + 2; /* past "gs" */
    char digits[16];
    size_t n = 0;
    while (*d >= '0' && *d <= '9' && n < sizeof(digits) - 1) digits[n++] = *d++;
    digits[n] = '\0';
    if (n >= 4) snprintf(out, out_bytes, "%.*s.%.2s.%s", (int)(n - 3), digits, digits + n - 3, digits + n - 1);
    else snprintf(out, out_bytes, "%s", digits);
}

static int step_ghostscript(const SpdfWinToolchainStep* step, const SpdfWinToolchainRoots* roots, void* cancel,
                            spdf_win_toolchain_line_fn cb, void* user) {
    char curl[SPDF_WIN_TC_PATH], certutil[SPDF_WIN_TC_PATH], cmd[SPDF_WIN_TC_CMD];
    char asset[512], sums_url[512], expected[160], actual[160], version[32];
    char tmp[SPDF_WIN_TC_PATH], installer[SPDF_WIN_TC_PATH], target[SPDF_WIN_TC_PATH], params[SPDF_WIN_TC_PATH];
    char* json = NULL;
    char* sums = NULL;
    char* digest = NULL;
    const char* leaf;
    wchar_t wtmp[SPDF_WIN_TC_PATH];
    int rc;

    if (!spdf_win_toolchain_find(SPDF_WIN_TOOL_CURL, roots, curl, sizeof(curl)) ||
        !spdf_win_toolchain_find(SPDF_WIN_TOOL_CERTUTIL, roots, certutil, sizeof(certutil))) {
        say(cb, user, "curl.exe or certutil.exe is unavailable; cannot fetch Ghostscript.");
        return 0;
    }
    say(cb, user, "Looking up the latest Ghostscript release...");
    {
        const char* argv[4] = {curl, "-L", "-sS", SPDF_WIN_TC_GS_RELEASES_API};
        spdf_win_toolchain_join_argv(argv, 4, cmd, sizeof(cmd));
    }
    rc = run_streamed(cmd, cancel, cb, user, &json);
    if (rc != 0 || !json || !spdf_win_toolchain_gs_asset_url(json, asset, sizeof(asset))) {
        say(cb, user, "Could not find the 64-bit Windows installer in the release listing.");
        free(json);
        return 0;
    }
    free(json);
    leaf = strrchr(asset, '/') + 1;
    gs_version_from_asset(asset, version, sizeof(version));
    say(cb, user, "Installer: %s (Ghostscript %s)", asset, version);

    spdf_win_toolchain_gs_sums_url(asset, sums_url, sizeof(sums_url));
    {
        const char* argv[4] = {curl, "-L", "-sS", sums_url};
        spdf_win_toolchain_join_argv(argv, 4, cmd, sizeof(cmd));
    }
    rc = run_streamed(cmd, cancel, cb, user, &sums);
    if (rc != 0 || !sums || !spdf_win_toolchain_sums_lookup(sums, leaf, expected, sizeof(expected))) {
        say(cb, user, "Could not read the release's SHA512SUMS; not installing an unverified download.");
        free(sums);
        return 0;
    }
    free(sums);

    if (!GetTempPathW(SPDF_WIN_TC_PATH, wtmp) || !WideCharToMultiByte(CP_UTF8, 0, wtmp, -1, tmp, sizeof(tmp), NULL, NULL))
        return 0;
    snprintf(installer, sizeof(installer), "%s%s", tmp, leaf);
    say(cb, user, "Downloading %s (about 60 MB)...", leaf);
    spdf_win_toolchain_curl_cmd(curl, asset, installer, cmd, sizeof(cmd));
    if (run_streamed(cmd, cancel, cb, user, NULL) != 0) return 0;

    spdf_win_toolchain_certutil_cmd(certutil, installer, cmd, sizeof(cmd));
    rc = run_streamed(cmd, cancel, cb, user, &digest);
    if (rc != 0 || !digest || !spdf_win_toolchain_certutil_digest(digest, actual, sizeof(actual))) {
        say(cb, user, "certutil could not hash the download.");
        free(digest);
        return 0;
    }
    free(digest);
    if (strcmp(actual, expected) != 0) {
        say(cb, user, "SHA-512 MISMATCH: the download does not match the release's SHA512SUMS. Not installing.");
        say(cb, user, "  expected %s", expected);
        say(cb, user, "  actual   %s", actual);
        if (MultiByteToWideChar(CP_UTF8, 0, installer, -1, wtmp, SPDF_WIN_TC_PATH)) DeleteFileW(wtmp);
        return 0;
    }
    say(cb, user, "SHA-512 verified against the release's SHA512SUMS.");

    snprintf(target, sizeof(target), "%s\\gs%s", step->dest[0] ? step->dest : tmp, version);
    ensure_dir_utf8(step->dest[0] ? step->dest : tmp);
    snprintf(params, sizeof(params), "/S /D=%s", target);
    say(cb, user, "Installing silently into %s", target);
    rc = run_installer_maybe_elevated(installer, params, cb, user);
    if (rc == 0) say(cb, user, "Ghostscript %s installed.", version);
    return rc == 0;
}

int spdf_win_toolchain_run_step(const SpdfWinToolchainStep* step, const SpdfWinToolchainRoots* roots, void* cancel,
                                spdf_win_toolchain_line_fn on_line, void* user) {
    if (!step) return 0;
    say(on_line, user, "");
    say(on_line, user, "== %s", step->label);
    switch (step->kind) {
        case SPDF_WIN_TC_STEP_BLOCKED: say(on_line, user, "Cannot continue automatically."); return 0;
        case SPDF_WIN_TC_STEP_GHOSTSCRIPT: return step_ghostscript(step, roots, cancel, on_line, user);
        case SPDF_WIN_TC_STEP_TRAINEDDATA: {
            char dir[SPDF_WIN_TC_PATH];
            if (spdf_win_toolchain_dirname(step->dest, dir, sizeof(dir))) ensure_dir_utf8(dir);
            return run_streamed(step->command, cancel, on_line, user, NULL) == 0;
        }
        case SPDF_WIN_TC_STEP_PIP: {
            /* The plan said "python" when Python was not yet installed; the
             * winget step before this one may have changed that. */
            char cmd[SPDF_WIN_TC_CMD];
            const char* line = step->command;
            if (strncmp(line, "python -m pip", 13) == 0) {
                SpdfWinToolchainRoots fresh;
                char python[SPDF_WIN_TC_PATH], q[SPDF_WIN_TC_PATH];
                spdf_win_toolchain_roots_from_env(&fresh);
                if (spdf_win_toolchain_find(SPDF_WIN_TOOL_PYTHON, &fresh, python, sizeof(python))) {
                    spdf_win_toolchain_quote_arg(python, q, sizeof(q));
                    snprintf(cmd, sizeof(cmd), "%s%s", q, line + 6);
                    line = cmd;
                } else {
                    say(on_line, user, "Python is still not installed; pip cannot run. Open a new session after installing Python.");
                    return 0;
                }
            }
            return run_streamed(line, cancel, on_line, user, NULL) == 0;
        }
        case SPDF_WIN_TC_STEP_WINGET:
            if (!strstr(step->command, "--scope user"))
                say(on_line, user, "This installer is machine-wide; Windows may show a consent prompt.");
            /* fallthrough */
        case SPDF_WIN_TC_STEP_ARGOSPM:
        default: return run_streamed(step->command, cancel, on_line, user, NULL) == 0;
    }
}
