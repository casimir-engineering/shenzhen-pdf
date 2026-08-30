/* spdf_win_state.h — reading and writing ShenzhenPDF's persisted state on
 * Windows: settings, session, per-document state (the "recent files" store) and
 * favorites.
 *
 * There is exactly one on-disk format and exactly one codec for it:
 * portable/core/spdf_yaml.h. This module is a file-IO shell around that codec
 * and nothing else — no second serializer, no Windows-only schema. The contract
 * is copied from the two shipping frontends so a state file stays meaningful
 * across platforms:
 *
 *   read   file bytes -> spdf_json_from_yaml() -> JSON text the caller parses
 *   write  JSON text  -> spdf_yaml_from_json(text, spdf_state_header_for_file())
 *                     -> atomic temp+replace
 *
 * (mac: ShenzhenPDFMac.mm stateObjectFromFile:/writeStateObject:toFile:,
 *  GTK: portable/linux/gtk4/spdf_state.c read_state_file_as_json/
 *  write_state_file_from_json.) Both frontends keep JSON in memory and convert
 * only at the file boundary; a Win32 frontend does the same, so all three emit
 * byte-comparable YAML.
 *
 * Failure policy, also inherited: a missing, oversized or unparseable file is
 * not an error the user sees. It reads as "absent" and defaults apply, exactly
 * as the pre-YAML corrupt-JSON path behaved. Nothing here deletes or rewrites a
 * file it could not understand.
 *
 * Windows specifics: every file is opened through CreateFileW with an
 * extended-length ("\\?\") path built by spdf_win_paths.h, so a deep or
 * non-ASCII user profile works without depending on the machine's
 * LongPathsEnabled policy; replacement uses MoveFileExW with
 * MOVEFILE_REPLACE_EXISTING, because plain rename() fails on Windows whenever
 * the destination already exists — which for a settings file is every save
 * after the first.
 */
#ifndef SPDF_WIN_STATE_H
#define SPDF_WIN_STATE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Same cap the GTK frontend applies (SPDF_STATE_MAX_CONFIG_JSON_BYTES). A
 * state file larger than this is treated as absent rather than parsed. */
#define SPDF_WIN_STATE_MAX_BYTES (2 * 1024 * 1024)

/* The state file names, matching the mac and GTK schemas. bookmarks.yaml is
 * deliberately absent: it holds macOS security-scoped bookmarks, which have no
 * Windows counterpart. */
#define SPDF_WIN_STATE_SETTINGS "settings.yaml"
#define SPDF_WIN_STATE_SESSION "session.yaml"
#define SPDF_WIN_STATE_DOCUMENTS "documents.yaml"
#define SPDF_WIN_STATE_FAVORITES "favorites.yaml"

/* --- by absolute path ---------------------------------------------------- */

/* Read a YAML state file and return its contents as JSON text (malloc'd,
 * NUL-terminated, caller free()s). NULL when the file is missing, larger than
 * SPDF_WIN_STATE_MAX_BYTES, or not parseable as the supported YAML subset. */
char* spdf_win_state_read_json_at(const char* path);

/* Convert JSON text to YAML — carrying the standard header comment derived
 * from the file's stem — and write it atomically (temp file + replace). A
 * write whose bytes match what is already on disk is skipped and still reports
 * success, so the frontend's coalesced writer does not churn the disk on
 * unchanged state. Returns 1 on success, 0 when the JSON does not parse or the
 * file cannot be written. */
int spdf_win_state_write_json_at(const char* path, const char* json_text);

/* --- by file name, inside the resolved state directory ------------------- */

/* e.g. spdf_win_state_read_json(SPDF_WIN_STATE_SETTINGS). */
char* spdf_win_state_read_json(const char* name);
int spdf_win_state_write_json(const char* name, const char* json_text);

/* --- startup ------------------------------------------------------------- */

/* One-time JSON -> YAML migration of the four stems in dir, delegated whole to
 * spdf_state_migrate_dir() in the core so Windows cannot drift from the mac and
 * GTK migration semantics. Must run before anything reads state. Returns the
 * number of files migrated, or -1.
 *
 * The core's Windows behaviour here comes from portable/core/spdf_win_compat.c
 * (T1): the cross-process guard is LockFileEx rather than flock, and the file
 * opens route through _wfopen, so a non-ASCII state directory migrates
 * correctly. Link spdf_win_compat.c alongside spdf_yaml.c on Windows. */
int spdf_win_state_migrate(const char* dir);

/* Same, against the resolved state directory. */
int spdf_win_state_migrate_default(void);

/* --- cross-process session guard ----------------------------------------- */

/* ShenzhenPDF runs one process per window and merges session.yaml on write, so
 * the read-modify-write must be serialized. The mac and GTK apps take an
 * exclusive flock on "<state dir>/session.lock"; this is the Windows
 * equivalent, LockFileEx on a CreateFileW handle to the same file name.
 * Blocking. Returns NULL when the lock file cannot be opened. */
typedef struct spdf_win_state_session_lock spdf_win_state_session_lock;
spdf_win_state_session_lock* spdf_win_state_session_lock_acquire(const char* dir);
void spdf_win_state_session_lock_release(spdf_win_state_session_lock* lock);

#ifdef __cplusplus
}
#endif

#endif /* SPDF_WIN_STATE_H */
