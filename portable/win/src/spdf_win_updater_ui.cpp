/* spdf_win_updater_ui.cpp — the updater's timers, worker threads and dialogs:
 * the part that is wired to the app. Everything it decides with, it decides
 * through the pure functions in spdf_win_updater.h; this file schedules,
 * fetches, prompts and relaunches.
 *
 * THREADING, in one paragraph. The UI thread owns a MESSAGE-ONLY window
 * (HWND_MESSAGE) that this module creates for itself, so the app's own window
 * procedure never has to learn a timer id or a custom message: the two timers
 * fire into it, and the worker threads PostMessage their results to it. The
 * worker thread does the network and the file I/O and touches no window; the
 * UI thread shows every dialog. There is at most one worker at a time.
 *
 * WHAT RUNS WHEN.
 *   start_background(hwnd)   arms a 5 s one-shot and an hourly timer; returns
 *   5 s later                the relaunch health check (consume_pending), then
 *                            the daily gate, then -- if the gate opened -- a
 *                            silent check on a worker
 *   every hour               the daily gate again (a window kept open for days
 *                            keeps checking; a laptop asleep past the gate
 *                            catches up on the first tick after it wakes)
 *   Check for Updates...     a check that bypasses the gate and the snooze and
 *                            reports every outcome
 *
 * THE INSTALL is always on consent: the prompt offers Install Now / Later.
 * Install Now downloads the sidecar and the exe (bounded), checks the SHA-256,
 * verifies Authenticode against the pin, reads the staged exe's ProductVersion
 * and requires it to be the tag, stages it beside the running exe, swaps, and
 * records pendingTag. Then it asks to restart; Restart Now closes the window
 * (the session is saved by the normal quit path) and relaunches the exe from
 * an atexit handler, after that save. Any failure before the swap deletes the
 * download; a failure during the swap restores the working app.
 */
#include "spdf_win_updater.h"
#include "spdf_win_updater_internal.h"

#include "spdf_win_about_version.h"

#include <windows.h>
#include <commctrl.h>
#include <shlobj.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma comment(lib, "user32.lib")
#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "ole32.lib")

#define UPD_TIMER_FIRST 1
#define UPD_TIMER_CADENCE 2
#define UPD_MSG_CHECK_DONE (WM_APP + 0x51)
#define UPD_MSG_INSTALL_DONE (WM_APP + 0x52)

typedef struct check_outcome {
    int ok;                /* an HTTP outcome was obtained and parsed */
    int not_modified;      /* 304 */
    int available;
    int newer_but_missing_asset;
    int user_initiated;
    spdf_win_release_info release;
    char err[256];
} check_outcome;

typedef struct install_outcome {
    int ok;
    char tag[64];
    char err[512];
} install_outcome;

static struct {
    HWND main;
    HWND sink;
    HANDLE worker;
    volatile long cancel;
    int started;
    int relaunch_at_exit;
    wchar_t self_exe[MAX_PATH];
} g;

static const wchar_t* k_sink_class = L"SpdfWinUpdaterSink";

/* --- helpers ---------------------------------------------------------------- */

static void utf8_to_wide(const char* in, wchar_t* out, size_t cap) {
    if (!in || MultiByteToWideChar(CP_UTF8, 0, in, -1, out, (int)cap) <= 0) out[0] = L'\0';
}

/* A dialog with named buttons: TaskDialogIndirect (common controls 6, which
 * the manifest declares) falling back to MessageBox when it is unavailable.
 * Returns the index of the chosen button, or -1. */
static int ask(const wchar_t* title, const wchar_t* heading, const wchar_t* body, const wchar_t* const* buttons,
               int count, int question) {
    TASKDIALOGCONFIG cfg;
    TASKDIALOG_BUTTON tb[4];
    int pressed = 0;
    int i;

    memset(&cfg, 0, sizeof(cfg));
    cfg.cbSize = sizeof(cfg);
    cfg.hwndParent = g.main;
    cfg.dwFlags = TDF_ALLOW_DIALOG_CANCELLATION | TDF_POSITION_RELATIVE_TO_WINDOW | TDF_SIZE_TO_CONTENT;
    cfg.pszWindowTitle = title;
    cfg.pszMainInstruction = heading;
    cfg.pszContent = body;
    cfg.pszMainIcon = question ? TD_INFORMATION_ICON : TD_WARNING_ICON;
    for (i = 0; i < count && i < 4; ++i) {
        tb[i].nButtonID = 100 + i;
        tb[i].pszButtonText = buttons[i];
    }
    cfg.pButtons = tb;
    cfg.cButtons = (UINT)(count < 4 ? count : 4);
    cfg.nDefaultButton = 100;
    if (SUCCEEDED(TaskDialogIndirect(&cfg, &pressed, NULL, NULL))) return pressed >= 100 ? pressed - 100 : -1;
    /* No common controls 6 (a test binary, or a very old system): the first
     * two buttons become Yes/No, the rest is not offered. */
    {
        wchar_t text[4096];
        int rc;
        _snwprintf_s(text, _countof(text), _TRUNCATE, L"%s\n\n%s", heading, body ? body : L"");
        if (count <= 1) {
            MessageBoxW(g.main, text, title, MB_OK | (question ? MB_ICONINFORMATION : MB_ICONWARNING));
            return 0;
        }
        rc = MessageBoxW(g.main, text, title, MB_YESNO | MB_ICONQUESTION);
        return rc == IDYES ? 0 : 1;
    }
}

static void inform(const wchar_t* heading, const wchar_t* body, int warning) {
    const wchar_t* ok[] = {L"OK"};
    ask(L"Software Update", heading, body, ok, 1, !warning);
}

static const char* running_version(void) {
    return SPDF_WIN_RELEASE_TAG;
}

/* settings.yaml, read-only: %APPDATA%\ShenzhenPDF\settings.yaml. */
static char* read_settings_text(void) {
    wchar_t* roaming = NULL;
    wchar_t path[MAX_PATH];
    char* text = NULL;
    size_t len = 0;
    if (SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, NULL, &roaming) != S_OK || !roaming) return NULL;
    _snwprintf_s(path, _countof(path), _TRUNCATE, L"%s\\ShenzhenPDF\\settings.yaml", roaming);
    CoTaskMemFree(roaming);
    spdf_win_updater_read_file(path, &text, &len, 2 * 1024 * 1024);
    return text; /* NULL when absent: every reader treats that as the default */
}

/* --- store mutators ----------------------------------------------------------- */

static int mutator_claim_daily_slot(spdf_win_update_store* store, void* user) {
    int* claimed = (int*)user;
    long long now = spdf_win_updater_now_epoch();
    long long delay = spdf_win_updater_daily_check_delay(1, store->last_check != 0, store->last_check, now);
    if (delay != 0) return 0;
    /* Stamp BEFORE the network call: a crash or a 403 still consumes the
     * day's slot, so a broken server is asked once a day, not once a second. */
    store->last_check = now;
    *claimed = 1;
    return 1;
}

typedef struct store_snapshot {
    char etag[256];
    char highest_seen[64];
    char deferred_tag[64];
    long long remind_after;
} store_snapshot;

static int mutator_read_snapshot(spdf_win_update_store* store, void* user) {
    store_snapshot* s = (store_snapshot*)user;
    strncpy_s(s->etag, sizeof(s->etag), store->etag ? store->etag : "", _TRUNCATE);
    strncpy_s(s->highest_seen, sizeof(s->highest_seen), store->highest_seen ? store->highest_seen : "", _TRUNCATE);
    strncpy_s(s->deferred_tag, sizeof(s->deferred_tag), store->deferred_tag ? store->deferred_tag : "", _TRUNCATE);
    s->remind_after = store->remind_after;
    return 0;
}

typedef struct persist_args {
    const char* etag;
    const char* tag;
} persist_args;

static int mutator_persist_check(spdf_win_update_store* store, void* user) {
    persist_args* a = (persist_args*)user;
    int changed = 0;
    if (a->etag && *a->etag && (!store->etag || strcmp(store->etag, a->etag) != 0)) {
        free(store->etag);
        store->etag = _strdup(a->etag);
        changed = 1;
    }
    /* Advance the high-water mark on every 200, whatever the user chooses. */
    if (a->tag && *a->tag &&
        (!store->highest_seen || !*store->highest_seen || spdf_win_updater_compare_versions(a->tag, store->highest_seen) > 0)) {
        free(store->highest_seen);
        store->highest_seen = _strdup(a->tag);
        changed = 1;
    }
    return changed;
}

static int mutator_snooze(spdf_win_update_store* store, void* user) {
    free(store->deferred_tag);
    store->deferred_tag = _strdup((const char*)user);
    store->remind_after = spdf_win_updater_now_epoch() + SPDF_WIN_UPDATER_LATER_SNOOZE_SECONDS;
    return 1;
}

static int mutator_set_pending(spdf_win_update_store* store, void* user) {
    free(store->pending_tag);
    store->pending_tag = _strdup((const char*)user);
    return 1;
}

/* --- the check (worker) ---------------------------------------------------------- */

static DWORD WINAPI check_thread(LPVOID param) {
    check_outcome* out = (check_outcome*)param;
    store_snapshot snap;
    wchar_t dir[MAX_PATH];
    wchar_t body_path[MAX_PATH + 32];
    spdf_win_fetch_result fetch;
    char* body = NULL;
    size_t body_len = 0;

    memset(&snap, 0, sizeof(snap));
    spdf_win_updater_with_locked_store(mutator_read_snapshot, &snap);
    if (!spdf_win_updater_dir(dir, _countof(dir))) {
        strncpy_s(out->err, sizeof(out->err), "the updates folder could not be created", _TRUNCATE);
        goto done;
    }
    _snwprintf_s(body_path, _countof(body_path), _TRUNCATE, L"%s\\release.json", dir);
    /* The manual path omits the ETag so the server answers 200 and the whole
     * decision runs; the silent path sends it so a 304 costs nothing. */
    if (!spdf_win_updater_fetch(SPDF_WIN_UPDATER_RELEASES_LATEST_URL, body_path, out->user_initiated ? NULL : snap.etag,
                                1, SPDF_WIN_UPDATER_MAX_FEED_BYTES, SPDF_WIN_UPDATER_NET_TIMEOUT_MS, &g.cancel,
                                &fetch)) {
        strncpy_s(out->err, sizeof(out->err), fetch.err, _TRUNCATE);
        goto done;
    }
    if (fetch.status == 304) {
        out->ok = 1;
        out->not_modified = 1;
        goto done;
    }
    if (fetch.status != 200) {
        snprintf(out->err, sizeof(out->err), "the update server returned HTTP %d", fetch.status);
        goto done;
    }
    if (!spdf_win_updater_read_file(body_path, &body, &body_len, (size_t)SPDF_WIN_UPDATER_MAX_FEED_BYTES) ||
        !spdf_win_updater_parse_release(body, (long)body_len, SPDF_WIN_UPDATER_ASSET, SPDF_WIN_UPDATER_SIDECAR_SUFFIX,
                                        &out->release)) {
        strncpy_s(out->err, sizeof(out->err), "the update server response was malformed", _TRUNCATE);
        goto done;
    }
    {
        persist_args pa = {fetch.etag, out->release.tag};
        spdf_win_updater_with_locked_store(mutator_persist_check, &pa);
    }
    out->ok = 1;
    out->available = spdf_win_updater_release_available(&out->release, running_version(), snap.highest_seen);
    out->newer_but_missing_asset = !out->available && !out->release.draft && !out->release.prerelease &&
                                   spdf_win_updater_compare_versions(out->release.tag, running_version()) > 0 &&
                                   (!out->release.asset_url || !out->release.sidecar_url);
    /* The silent path honours "Later" (7 days) and skippedUpdateVersion. */
    if (out->available && !out->user_initiated) {
        char skipped[64];
        char* settings = read_settings_text();
        if (spdf_win_updater_setting_skipped(settings, skipped, sizeof(skipped)) &&
            strcmp(skipped, out->release.tag) == 0)
            out->available = 0;
        free(settings);
        if (out->available && snap.deferred_tag[0] && strcmp(snap.deferred_tag, out->release.tag) == 0 &&
            spdf_win_updater_now_epoch() < snap.remind_after)
            out->available = 0;
    }
done:
    DeleteFileW(body_path);
    free(body);
    PostMessageW(g.sink, UPD_MSG_CHECK_DONE, 0, (LPARAM)out);
    return 0;
}

/* --- the install (worker) ---------------------------------------------------------- */

static DWORD WINAPI install_thread(LPVOID param) {
    install_outcome* out = (install_outcome*)param;
    spdf_win_release_info* rel = (spdf_win_release_info*)((char*)out + sizeof(*out));
    wchar_t dir[MAX_PATH], tag_dir[MAX_PATH + 72], asset_path[MAX_PATH + 160], sidecar_path[MAX_PATH + 168];
    wchar_t staged[MAX_PATH + 8];
    wchar_t wtag[64];
    spdf_win_fetch_result fetch;
    char* sidecar_text = NULL;
    size_t sidecar_len = 0;
    char want_hex[65], got_hex[65];
    char product[128];
    char err[512];

    strncpy_s(out->tag, sizeof(out->tag), rel->tag, _TRUNCATE);
    utf8_to_wide(rel->tag, wtag, _countof(wtag));
    if (!spdf_win_updater_dir(dir, _countof(dir))) {
        strncpy_s(out->err, sizeof(out->err), "the updates folder could not be created", _TRUNCATE);
        goto done;
    }
    _snwprintf_s(tag_dir, _countof(tag_dir), _TRUNCATE, L"%s\\%s", dir, wtag);
    CreateDirectoryW(tag_dir, NULL);
    _snwprintf_s(asset_path, _countof(asset_path), _TRUNCATE, L"%s\\%hs", tag_dir, SPDF_WIN_UPDATER_ASSET);
    _snwprintf_s(sidecar_path, _countof(sidecar_path), _TRUNCATE, L"%s%hs", asset_path, SPDF_WIN_UPDATER_SIDECAR_SUFFIX);

    /* Free space, from the untrusted declared size clamped by the bounds. */
    {
        ULARGE_INTEGER free_bytes;
        if (GetDiskFreeSpaceExW(dir, &free_bytes, NULL, NULL) &&
            !spdf_win_updater_has_free_space((long long)free_bytes.QuadPart, rel->asset_size)) {
            strncpy_s(out->err, sizeof(out->err), "there is not enough free disk space to download the update", _TRUNCATE);
            goto done;
        }
    }
    if (!spdf_win_updater_fetch(rel->sidecar_url, sidecar_path, NULL, 0, SPDF_WIN_UPDATER_MAX_SIDECAR_BYTES,
                                SPDF_WIN_UPDATER_NET_TIMEOUT_MS, &g.cancel, &fetch) ||
        fetch.status != 200) {
        snprintf(out->err, sizeof(out->err), "the update's checksum could not be downloaded (%s)",
                 fetch.err[0] ? fetch.err : "HTTP error");
        goto done;
    }
    if (!spdf_win_updater_read_file(sidecar_path, &sidecar_text, &sidecar_len, 64 * 1024) ||
        !spdf_win_updater_parse_sha256_sidecar(sidecar_text, want_hex, sizeof(want_hex))) {
        strncpy_s(out->err, sizeof(out->err), "the update's checksum file was malformed", _TRUNCATE);
        goto done;
    }
    if (!spdf_win_updater_fetch(rel->asset_url, asset_path, NULL, 0, spdf_win_updater_download_ceiling(rel->asset_size),
                                SPDF_WIN_UPDATER_ASSET_TIMEOUT_MS, &g.cancel, &fetch) ||
        fetch.status != 200) {
        snprintf(out->err, sizeof(out->err), "the update could not be downloaded (%s)",
                 fetch.err[0] ? fetch.err : "HTTP error");
        goto done;
    }
    /* Integrity: declared size (when given), then the sidecar digest. Both are
     * heuristics against truncation and a stale CDN, never trust. */
    if (rel->asset_size > 0 && fetch.bytes != rel->asset_size) {
        strncpy_s(out->err, sizeof(out->err), "the downloaded update was incomplete", _TRUNCATE);
        goto done;
    }
    if (!spdf_win_updater_sha256_file(asset_path, got_hex, sizeof(got_hex)) || strcmp(got_hex, want_hex) != 0) {
        strncpy_s(out->err, sizeof(out->err), "the downloaded update does not match its published checksum", _TRUNCATE);
        goto done;
    }
    /* TRUST: Authenticode + the pin. This is the only gate that matters. */
    if (!spdf_win_updater_verify_pinned(asset_path, spdf_win_updater_pinned_thumbprint(), err, sizeof(err))) {
        snprintf(out->err, sizeof(out->err), "The update could not be verified and was not installed (%s).", err);
        goto done;
    }
    /* The right publisher's RIGHT build: the staged exe must say it is the tag. */
    if (!spdf_win_updater_file_product_version(asset_path, product, sizeof(product)) ||
        !spdf_win_updater_versions_match_release_target(rel->tag, product)) {
        snprintf(out->err, sizeof(out->err), "the downloaded file says it is version %s, not %s; it was not installed",
                 product[0] ? product : "(unknown)", rel->tag);
        goto done;
    }
    if (!spdf_win_updater_stage_beside(g.self_exe, asset_path, staged, _countof(staged), err, sizeof(err)) ||
        !spdf_win_updater_swap_exe(g.self_exe, staged, err, sizeof(err))) {
        strncpy_s(out->err, sizeof(out->err), err, _TRUNCATE);
        DeleteFileW(staged);
        goto done;
    }
    spdf_win_updater_with_locked_store(mutator_set_pending, (void*)rel->tag);
    out->ok = 1;
done:
    if (!out->ok) {
        DeleteFileW(asset_path); /* never keep a partial or unverified artifact */
        DeleteFileW(sidecar_path);
        RemoveDirectoryW(tag_dir);
    } else {
        DeleteFileW(asset_path); /* installed: the copy in updates\ has done its job */
        DeleteFileW(sidecar_path);
        RemoveDirectoryW(tag_dir);
    }
    free(sidecar_text);
    PostMessageW(g.sink, UPD_MSG_INSTALL_DONE, 0, (LPARAM)out);
    return 0;
}

/* --- the UI thread ------------------------------------------------------------------ */

static int worker_busy(void) {
    if (!g.worker) return 0;
    if (WaitForSingleObject(g.worker, 0) == WAIT_OBJECT_0) {
        CloseHandle(g.worker);
        g.worker = NULL;
        return 0;
    }
    return 1;
}

static void launch_check(int user_initiated) {
    check_outcome* out;
    if (worker_busy()) {
        if (user_initiated) inform(L"Already checking for updates.", NULL, 0);
        return;
    }
    out = (check_outcome*)calloc(1, sizeof(*out));
    if (!out) return;
    out->user_initiated = user_initiated;
    g.cancel = 0;
    g.worker = CreateThread(NULL, 0, check_thread, out, 0, NULL);
    if (!g.worker) free(out);
}

static void relaunch_at_exit(void) {
    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    wchar_t cmd[MAX_PATH + 4];
    if (!g.relaunch_at_exit || !g.self_exe[0]) return;
    /* After main() returned: the session is saved, the lock released. The new
     * process restores it. */
    memset(&si, 0, sizeof(si));
    si.cb = sizeof(si);
    _snwprintf_s(cmd, _countof(cmd), _TRUNCATE, L"\"%s\"", g.self_exe);
    if (CreateProcessW(g.self_exe, cmd, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
    }
}

static void begin_install(const spdf_win_release_info* rel) {
    /* The outcome and a deep copy of the release travel together to the
     * worker; the worker frees nothing, the completion handler frees all. */
    install_outcome* out;
    spdf_win_release_info* copy;
    if (worker_busy()) return;
    out = (install_outcome*)calloc(1, sizeof(*out) + sizeof(*copy));
    if (!out) return;
    copy = (spdf_win_release_info*)((char*)out + sizeof(*out));
    copy->tag = _strdup(rel->tag);
    copy->asset_url = rel->asset_url ? _strdup(rel->asset_url) : NULL;
    copy->sidecar_url = rel->sidecar_url ? _strdup(rel->sidecar_url) : NULL;
    copy->asset_size = rel->asset_size;
    g.cancel = 0;
    g.worker = CreateThread(NULL, 0, install_thread, out, 0, NULL);
    if (!g.worker) {
        spdf_win_release_info_clear(copy);
        free(out);
    }
}

static void on_check_done(check_outcome* out) {
    wchar_t heading[256];
    wchar_t body[4096];
    wchar_t wrun[64], wtag[64];

    utf8_to_wide(running_version(), wrun, _countof(wrun));
    if (!out->ok) {
        if (out->user_initiated) {
            wchar_t werr[256];
            utf8_to_wide(out->err, werr, _countof(werr));
            inform(L"Could not check for updates.", werr, 1);
        }
    } else if (out->not_modified || !out->available) {
        if (out->user_initiated) {
            if (out->newer_but_missing_asset) {
                utf8_to_wide(out->release.tag, wtag, _countof(wtag));
                _snwprintf_s(body, _countof(body), _TRUNCATE,
                             L"Shenzhen PDF %s has been released, but it has no Windows build yet. You have %s.", wtag,
                             wrun);
                inform(L"No Windows update available.", body, 0);
            } else {
                _snwprintf_s(body, _countof(body), _TRUNCATE, L"Shenzhen PDF %s is the latest version.", wrun);
                inform(L"You're up to date.", body, 0);
            }
        }
    } else {
        /* The highlights as a bulleted list -- the 26.7.17-1 fix -- under the
         * version line, then Install Now / Later. */
        char* notes = spdf_win_updater_format_notes(out->release.notes);
        wchar_t wnotes[3000];
        const wchar_t* buttons[] = {L"Install Now", L"Later"};
        int choice;
        utf8_to_wide(out->release.tag, wtag, _countof(wtag));
        utf8_to_wide(notes ? notes : "", wnotes, _countof(wnotes));
        free(notes);
        _snwprintf_s(heading, _countof(heading), _TRUNCATE, L"Shenzhen PDF %s is available.", wtag);
        _snwprintf_s(body, _countof(body), _TRUNCATE,
                     L"You have %s.%s%s\n\nThe update is downloaded, verified against Shenzhen PDF's publisher "
                     L"certificate, and installed; you will be asked to restart.",
                     wrun, wnotes[0] ? L"\n\n" : L"", wnotes);
        choice = ask(L"Software Update", heading, body, buttons, 2, 1);
        if (choice == 0) begin_install(&out->release);
        else spdf_win_updater_with_locked_store(mutator_snooze, (void*)out->release.tag);
    }
    spdf_win_release_info_clear(&out->release);
    free(out);
}

static void on_install_done(install_outcome* out) {
    spdf_win_release_info* copy = (spdf_win_release_info*)((char*)out + sizeof(*out));
    wchar_t heading[256], wtag[64];
    utf8_to_wide(out->tag, wtag, _countof(wtag));
    if (!out->ok) {
        wchar_t werr[512];
        utf8_to_wide(out->err, werr, _countof(werr));
        inform(L"The update was not installed.", werr, 1);
    } else {
        const wchar_t* buttons[] = {L"Restart Now", L"Later"};
        _snwprintf_s(heading, _countof(heading), _TRUNCATE, L"Update %s installed.", wtag);
        if (ask(L"Software Update", heading,
                L"Restart Shenzhen PDF to finish updating. Your windows and tabs will be restored.", buttons, 2, 1) == 0) {
            g.relaunch_at_exit = 1;
            atexit(relaunch_at_exit);
            if (g.main) PostMessageW(g.main, WM_CLOSE, 0, 0);
        }
        /* "Later": the new binary takes effect on the next launch, where the
         * health check confirms pendingTag. */
    }
    spdf_win_release_info_clear(copy);
    free(out);
}

static void health_check_then_daily(void) {
    char tag[64];
    int r = spdf_win_updater_consume_pending(g.self_exe, running_version(), tag, sizeof(tag));
    if (r == 1) {
        wchar_t body[256], wtag[64];
        utf8_to_wide(tag, wtag, _countof(wtag));
        _snwprintf_s(body, _countof(body), _TRUNCATE, L"You're now on Shenzhen PDF %s.", wtag);
        inform(body, NULL, 0);
    } else if (r == -1) {
        wchar_t body[1024], wtag[64], wrun[64];
        utf8_to_wide(tag, wtag, _countof(wtag));
        utf8_to_wide(running_version(), wrun, _countof(wrun));
        _snwprintf_s(body, _countof(body), _TRUNCATE,
                     L"The update to %s did not take: this is still Shenzhen PDF %s. The previous app is kept "
                     L"beside this one as\n%s.old\nfor recovery.",
                     wtag, wrun, g.self_exe);
        inform(L"The update did not complete.", body, 1);
    }
    /* Then the daily gate. */
    {
        char* settings = read_settings_text();
        int enabled = spdf_win_updater_setting_enabled(settings);
        int claimed = 0;
        free(settings);
        if (!enabled) return;
        spdf_win_updater_with_locked_store(mutator_claim_daily_slot, &claimed);
        if (claimed) launch_check(0);
    }
}

static LRESULT CALLBACK sink_proc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
    switch (msg) {
        case WM_TIMER:
            if (wparam == UPD_TIMER_FIRST) {
                KillTimer(hwnd, UPD_TIMER_FIRST);
                health_check_then_daily();
                return 0;
            }
            if (wparam == UPD_TIMER_CADENCE) {
                char* settings = read_settings_text();
                int claimed = 0;
                int enabled = spdf_win_updater_setting_enabled(settings);
                free(settings);
                if (enabled) {
                    spdf_win_updater_with_locked_store(mutator_claim_daily_slot, &claimed);
                    if (claimed) launch_check(0);
                }
                return 0;
            }
            break;
        case UPD_MSG_CHECK_DONE: on_check_done((check_outcome*)lparam); return 0;
        case UPD_MSG_INSTALL_DONE: on_install_done((install_outcome*)lparam); return 0;
        default: break;
    }
    return DefWindowProcW(hwnd, msg, wparam, lparam);
}

static int ensure_sink(void* hwnd) {
    WNDCLASSEXW cls;
    if (hwnd) g.main = (HWND)hwnd;
    if (g.sink) return 1;
    if (!g.self_exe[0]) spdf_win_updater_self_exe(g.self_exe, _countof(g.self_exe));
    memset(&cls, 0, sizeof(cls));
    cls.cbSize = sizeof(cls);
    cls.lpfnWndProc = sink_proc;
    cls.hInstance = GetModuleHandleW(NULL);
    cls.lpszClassName = k_sink_class;
    if (!RegisterClassExW(&cls) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return 0;
    g.sink = CreateWindowExW(0, k_sink_class, NULL, 0, 0, 0, 0, 0, HWND_MESSAGE, NULL, GetModuleHandleW(NULL), NULL);
    return g.sink != NULL;
}

void spdf_win_updater_start_background(void* hwnd) {
    if (g.started) return;
    if (!ensure_sink(hwnd)) return;
    g.started = 1;
    /* Nothing runs on the launch path: the first disk read is IDLE_DELAY_MS
     * away, and the network check is on a worker after that. */
    SetTimer(g.sink, UPD_TIMER_FIRST, SPDF_WIN_UPDATER_IDLE_DELAY_MS, NULL);
    SetTimer(g.sink, UPD_TIMER_CADENCE, SPDF_WIN_UPDATER_CADENCE_MS, NULL);
}

void spdf_win_updater_check_interactive(void* hwnd) {
    if (!ensure_sink(hwnd)) {
        inform(L"Could not check for updates.", L"The updater could not start.", 1);
        return;
    }
    launch_check(1);
}
