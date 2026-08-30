/* spdf_win_state.c — see spdf_win_state.h for the contract.
 *
 * The YAML/JSON conversion is entirely portable/core's (spdf_yaml.h); the only
 * platform code here is opening, replacing and locking files. The POSIX branch
 * is not dead weight: it is what lets portable/win/tests/state_test.c drive the
 * real read/write/lock paths on macOS against the real codec, so the round-trip
 * is verified before a Windows toolchain exists.
 */
#include "spdf_win_state.h"

#include "spdf_win_paths.h"
#include "spdf_yaml.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* --- platform file IO ---------------------------------------------------- */

#if defined(_WIN32)

#include <windows.h>

/* Both halves of every path this module touches go through here: UTF-8 in,
 * extended-length UTF-16 out. Nothing below calls a narrow CRT file function,
 * because narrow CRT paths are interpreted in the process ANSI code page and
 * would mangle a non-ASCII profile name. */
static int widen_path(const char* utf8, wchar_t* out, size_t out_units) {
    char extended[SPDF_WIN_PATH_MAX];
    if (!spdf_win_path_to_extended(utf8, extended, sizeof(extended))) return 0;
    return spdf_win_utf16_from_utf8(extended, out, out_units) != SPDF_WIN_CONV_ERROR;
}

static char* read_file_limited(const char* path, size_t* len_out) {
    wchar_t wide[SPDF_WIN_PATH_MAX];
    HANDLE h;
    LARGE_INTEGER size;
    DWORD got = 0;
    char* data;

    if (len_out) *len_out = 0;
    if (!widen_path(path, wide, SPDF_WIN_PATH_MAX)) return NULL;
    h = CreateFileW(wide, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING,
                    FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return NULL;
    if (!GetFileSizeEx(h, &size) || size.QuadPart > SPDF_WIN_STATE_MAX_BYTES) {
        CloseHandle(h);
        return NULL;
    }
    data = (char*)malloc((size_t)size.QuadPart + 1);
    if (!data) {
        CloseHandle(h);
        return NULL;
    }
    if (size.QuadPart > 0 && (!ReadFile(h, data, (DWORD)size.QuadPart, &got, NULL) ||
                              got != (DWORD)size.QuadPart)) {
        CloseHandle(h);
        free(data);
        return NULL;
    }
    CloseHandle(h);
    data[(size_t)size.QuadPart] = 0;
    if (len_out) *len_out = (size_t)size.QuadPart;
    return data;
}

static int write_file_replacing(const char* path, const char* temp_path, const char* text,
                                size_t len) {
    wchar_t wide_temp[SPDF_WIN_PATH_MAX];
    wchar_t wide_dest[SPDF_WIN_PATH_MAX];
    HANDLE h;
    DWORD written = 0;

    if (!widen_path(temp_path, wide_temp, SPDF_WIN_PATH_MAX)) return 0;
    if (!widen_path(path, wide_dest, SPDF_WIN_PATH_MAX)) return 0;
    h = CreateFileW(wide_temp, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return 0;
    if ((len > 0 && (!WriteFile(h, text, (DWORD)len, &written, NULL) || written != (DWORD)len)) ||
        !FlushFileBuffers(h)) {
        CloseHandle(h);
        DeleteFileW(wide_temp);
        return 0;
    }
    CloseHandle(h);
    /* MOVEFILE_REPLACE_EXISTING is the whole point: a plain rename() fails on
     * Windows when the destination exists, which is every save after the
     * first. See windows-port-plan.md risk 3. */
    if (!MoveFileExW(wide_temp, wide_dest, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        DeleteFileW(wide_temp);
        return 0;
    }
    return 1;
}

static unsigned long current_pid(void) { return (unsigned long)GetCurrentProcessId(); }

struct spdf_win_state_session_lock {
    HANDLE handle;
};

static void* lock_file_exclusive(const char* path) {
    wchar_t wide[SPDF_WIN_PATH_MAX];
    OVERLAPPED ov;
    HANDLE h;
    struct spdf_win_state_session_lock* lock;

    if (!widen_path(path, wide, SPDF_WIN_PATH_MAX)) return NULL;
    h = CreateFileW(wide, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
                    OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return NULL;
    memset(&ov, 0, sizeof(ov));
    if (!LockFileEx(h, LOCKFILE_EXCLUSIVE_LOCK, 0, MAXDWORD, MAXDWORD, &ov)) {
        CloseHandle(h);
        return NULL;
    }
    lock = (struct spdf_win_state_session_lock*)malloc(sizeof(*lock));
    if (!lock) {
        UnlockFileEx(h, 0, MAXDWORD, MAXDWORD, &ov);
        CloseHandle(h);
        return NULL;
    }
    lock->handle = h;
    return lock;
}

static void unlock_file(void* opaque) {
    struct spdf_win_state_session_lock* lock = (struct spdf_win_state_session_lock*)opaque;
    OVERLAPPED ov;
    if (!lock) return;
    memset(&ov, 0, sizeof(ov));
    UnlockFileEx(lock->handle, 0, MAXDWORD, MAXDWORD, &ov);
    CloseHandle(lock->handle);
    free(lock);
}

#else /* POSIX */

#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

static char* read_file_limited(const char* path, size_t* len_out) {
    char native[SPDF_WIN_PATH_MAX];
    struct stat st;
    FILE* f;
    char* data;
    size_t got;

    if (len_out) *len_out = 0;
    if (!spdf_win_path_to_native(path, native, sizeof(native))) return NULL;
    if (stat(native, &st) != 0 || !S_ISREG(st.st_mode)) return NULL;
    if (st.st_size > SPDF_WIN_STATE_MAX_BYTES) return NULL;
    f = fopen(native, "rb");
    if (!f) return NULL;
    data = (char*)malloc((size_t)st.st_size + 1);
    if (!data) {
        fclose(f);
        return NULL;
    }
    got = fread(data, 1, (size_t)st.st_size, f);
    fclose(f);
    if (got != (size_t)st.st_size) {
        free(data);
        return NULL;
    }
    data[got] = 0;
    if (len_out) *len_out = got;
    return data;
}

static int write_file_replacing(const char* path, const char* temp_path, const char* text,
                                size_t len) {
    char native[SPDF_WIN_PATH_MAX];
    char native_temp[SPDF_WIN_PATH_MAX];
    FILE* f;
    int ok;

    if (!spdf_win_path_to_native(path, native, sizeof(native))) return 0;
    if (!spdf_win_path_to_native(temp_path, native_temp, sizeof(native_temp))) return 0;
    f = fopen(native_temp, "wb");
    if (!f) return 0;
    ok = (len == 0 || fwrite(text, 1, len, f) == len);
    if (fclose(f) != 0) ok = 0;
    if (!ok || rename(native_temp, native) != 0) {
        remove(native_temp);
        return 0;
    }
    return 1;
}

static unsigned long current_pid(void) { return (unsigned long)getpid(); }

struct spdf_win_state_session_lock {
    int fd;
};

static void* lock_file_exclusive(const char* path) {
    char native[SPDF_WIN_PATH_MAX];
    struct spdf_win_state_session_lock* lock;
    int fd;

    if (!spdf_win_path_to_native(path, native, sizeof(native))) return NULL;
    fd = open(native, O_CREAT | O_RDWR, 0600);
    if (fd < 0) return NULL;
    if (flock(fd, LOCK_EX) != 0) {
        close(fd);
        return NULL;
    }
    lock = (struct spdf_win_state_session_lock*)malloc(sizeof(*lock));
    if (!lock) {
        flock(fd, LOCK_UN);
        close(fd);
        return NULL;
    }
    lock->fd = fd;
    return lock;
}

static void unlock_file(void* opaque) {
    struct spdf_win_state_session_lock* lock = (struct spdf_win_state_session_lock*)opaque;
    if (!lock) return;
    flock(lock->fd, LOCK_UN);
    close(lock->fd);
    free(lock);
}

#endif

/* --- the codec boundary -------------------------------------------------- */

char* spdf_win_state_read_json_at(const char* path) {
    char* yaml;
    char* json;

    if (!path || !*path) return NULL;
    yaml = read_file_limited(path, NULL);
    if (!yaml) return NULL;
    json = spdf_json_from_yaml(yaml);
    free(yaml);
    /* NULL here is the "file is unreadable, use defaults" path, not an error to
     * report: identical to the mac and GTK behaviour for a corrupt state file. */
    return json;
}

int spdf_win_state_write_json_at(const char* path, const char* json_text) {
    char header[128];
    char temp_path[SPDF_WIN_PATH_MAX];
    char* yaml;
    char* existing;
    size_t yaml_len, existing_len = 0;
    int ok;

    if (!path || !*path || !json_text) return 0;
    /* Reduce to the bare file name first: spdf_state_header_for_file() splits
     * on '/' only, so a Windows path would yield a header comment built from
     * the whole "C:\Users\..." prefix instead of "settings". The mac frontend
     * passes a bare name here for the same reason. */
    spdf_state_header_for_file(spdf_win_path_basename(path), header, sizeof(header));
    yaml = spdf_yaml_from_json(json_text, header);
    if (!yaml) return 0;
    yaml_len = strlen(yaml);

    /* Skip a no-op save, as the mac app does, so the coalesced writer does not
     * rewrite settings.yaml on every scroll-driven state tick. */
    existing = read_file_limited(path, &existing_len);
    if (existing) {
        int same = existing_len == yaml_len && memcmp(existing, yaml, yaml_len) == 0;
        free(existing);
        if (same) {
            free(yaml);
            return 1;
        }
    }

    if (snprintf(temp_path, sizeof(temp_path), "%s.tmp.%lu", path, current_pid()) >=
        (int)sizeof(temp_path)) {
        free(yaml);
        return 0;
    }
    ok = write_file_replacing(path, temp_path, yaml, yaml_len);
    free(yaml);
    return ok;
}

char* spdf_win_state_read_json(const char* name) {
    char path[SPDF_WIN_PATH_MAX];
    if (!spdf_win_paths_state_file(name, path, sizeof(path))) return NULL;
    return spdf_win_state_read_json_at(path);
}

int spdf_win_state_write_json(const char* name, const char* json_text) {
    char path[SPDF_WIN_PATH_MAX];
    if (!spdf_win_paths_state_file(name, path, sizeof(path))) return 0;
    return spdf_win_state_write_json_at(path, json_text);
}

/* --- startup ------------------------------------------------------------- */

int spdf_win_state_migrate(const char* dir) {
    /* Stem list and order copied from the GTK frontend (spdf_state.c
     * migrate_stems); the mac app adds "bookmarks", which is App Sandbox only. */
    static const char* const stems[] = {"settings", "session", "documents", "favorites"};
    char native[SPDF_WIN_PATH_MAX];
    if (!dir || !*dir) return -1;
    /* spdf_state_migrate_dir() joins with a literal '/'. Win32 accepts that, so
     * on Windows this conversion is the identity and the mixed-separator result
     * opens fine; off Windows it is what lets the native test drive the real
     * core migration against a '\'-composed directory. The core opens the
     * legacy JSON itself, UTF-8-correctly, via spdf_compat_fopen(). */
    if (!spdf_win_path_to_native(dir, native, sizeof(native))) return -1;
    return spdf_state_migrate_dir(native, stems, (int)(sizeof(stems) / sizeof(stems[0])));
}

int spdf_win_state_migrate_default(void) {
    char dir[SPDF_WIN_PATH_MAX];
    if (!spdf_win_paths_state_dir(dir, sizeof(dir))) return -1;
    return spdf_win_state_migrate(dir);
}

/* --- cross-process session guard ----------------------------------------- */

spdf_win_state_session_lock* spdf_win_state_session_lock_acquire(const char* dir) {
    char path[SPDF_WIN_PATH_MAX];
    if (!spdf_win_path_join(dir, "session.lock", path, sizeof(path))) return NULL;
    return (spdf_win_state_session_lock*)lock_file_exclusive(path);
}

void spdf_win_state_session_lock_release(spdf_win_state_session_lock* lock) { unlock_file(lock); }
