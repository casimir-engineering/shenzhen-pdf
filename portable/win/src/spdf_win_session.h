/* spdf_win_session.h — the open set, across launches.
 *
 * Reads and writes the SAME session.yaml the mac and GTK apps do, through the
 * SAME codec (portable/core/spdf_yaml.c) and the same file shell
 * (spdf_win_state.h). THERE IS NO WINDOWS SERIALIZER HERE. What this file adds
 * over spdf_win_state is only the shape of the session document — which keys
 * mean what — and it takes that shape verbatim from the two shipping
 * frontends:
 *
 *   { "version": 2,
 *     "windows": [
 *       { "id": "<per-window session id>",
 *         "frame": { "x":…, "y":…, "width":…, "height":… },
 *         "selectedTab": 0,
 *         "tabs": [ { "path": "…", "title": "…", "page": 0, "zoom": 1.0000,
 *                     "customZoom": 1.0000, "fitMode": 4, "viewMode": 1,
 *                     "scrollX": 0.0000, "scrollY": 0.0000,
 *                     "hasScrollOrigin": false, … } ] } ] }
 *
 * (mac: ShenzhenPDFMac.mm -sessionWindowState/-loadSessionWindowState:, GTK:
 * portable/linux/gtk4/spdf_state.c session_window_to_json/parse_session_window.
 * `page` is 0-BASED, and "viewMode" is what tells the GTK reader so — its own
 * GTK3-era files were 1-based and carried no viewMode, and it migrates on that
 * key's absence. Omitting it would shift every restored page by one on Linux.)
 *
 * ---------------------------------------------------------------------------
 * WHAT THIS FILE REFUSES TO DO
 *
 * 1. It never opens a document. Restore is METADATA ONLY: paths and view
 *    state land in the tab model and nothing else happens. See spdf_win_tabs.h;
 *    the whole point is that a fifteen-tab session costs the same at launch as
 *    a one-tab session.
 *
 * 2. It never writes over a session it could not read. A session.yaml that is
 *    present but unreadable — antivirus lock, sharing violation, a permissions
 *    blip — reports SPDF_WIN_SESSION_UNREADABLE on restore, and a save in that
 *    state writes NOTHING and returns 0. This is the failure the state layer
 *    was already hardened against (spdf_win_state.h, "SILENT FAILURE IF
 *    WRONG"), and the session file is where it would hurt most: one unlucky
 *    half second at launch would otherwise replace every open document with an
 *    empty set, permanently.
 *
 * 3. It never discards another window's state, and it does not discard the
 *    parts of a tab it does not model. ShenzhenPDF runs one process per window
 *    and merges on write under session.lock; windows belonging to other
 *    processes are copied through byte for byte. Within OUR window, a tab's
 *    keys that this port has no feature for yet — searchText, showSidebar,
 *    readOnly, workingPath — are carried forward from the matching on-disk tab
 *    rather than dropped, so opening a mac user's session on Windows and
 *    quitting does not silently erase their find state.
 */
#ifndef SPDF_WIN_SESSION_H
#define SPDF_WIN_SESSION_H

#include "spdf_win_tabs.h"

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Same ceiling the GTK frontend applies (SPDF_STATE_MAX_SESSION_WINDOWS). */
#define SPDF_WIN_SESSION_MAX_WINDOWS 16

/* Room for the generated window id plus a NUL. */
#define SPDF_WIN_SESSION_ID_MAX 64

typedef enum spdf_win_session_status {
    /* At least one tab was restored into the model. */
    SPDF_WIN_SESSION_RESTORED = 0,
    /* Nothing usable on disk: no file, or content this build cannot parse.
     * Start with an empty set; saving over it is correct and expected. */
    SPDF_WIN_SESSION_ABSENT = 1,
    /* A session file IS there and could not be read. The model is left
     * untouched and MUST NOT be saved over it — see the header. */
    SPDF_WIN_SESSION_UNREADABLE = 2
} spdf_win_session_status;

/* An id for a window that has no session identity yet, in the same spirit as
 * the GTK frontend's "gtk-<pid>-<time>" and the mac app's per-window UUID:
 * unique across the concurrently running processes that share the file. */
void spdf_win_session_new_window_id(char* out, size_t out_len);

/* Populate `tabs` from session.yaml. `window_id` selects which window to
 * restore; NULL or "" takes the first one in the file, which is what a plain
 * launch wants.
 *
 * Restores paths, titles and view state, sets the persisted selection with
 * spdf_win_tabs_select_deferred() — so NO DOCUMENT IS OPENED — and, when
 * out_window_id is non-NULL, writes back the id of the window it restored so a
 * later save updates that same window rather than growing a new one.
 *
 * `tabs` is only appended to on success; on ABSENT or UNREADABLE it is left
 * exactly as it was. */
spdf_win_session_status spdf_win_session_restore(spdf_win_tabs* tabs, const char* window_id, char* out_window_id,
                                                 size_t out_len);

/* Merge `tabs` into session.yaml as the window `window_id`, under the
 * cross-process session lock. A model with no tabs REMOVES that window from
 * the file (the mac app's -removeSessionStateForCurrentWindow).
 *
 * Returns 1 on success, 0 when the state directory cannot be resolved, the
 * existing file is present but unreadable, or the write fails. A 0 means
 * nothing was written; retrying later is always safe. */
int spdf_win_session_save(const spdf_win_tabs* tabs, const char* window_id);

/* --- the window's frame ---------------------------------------------------
 *
 * "frame": { "x", "y", "width", "height" } on the window object -- the mac
 * writes its NSWindow frame in points, GTK its size in pixels; this port writes
 * the window's normal placement in screen device pixels
 * (spdf_win_window_get_frame). Cross-platform the numbers mean little (a mac
 * screen's y grows upward), which is why the restore clamps onto a monitor
 * before trusting them. `w`/`h` <= 0 means "no frame". */
typedef struct spdf_win_session_frame {
    int x, y, w, h;
} spdf_win_session_frame;

/* As spdf_win_session_restore(), and also reads the window's frame into
 * `out_frame` when there is one (else w = h = 0). NULL is allowed. */
spdf_win_session_status spdf_win_session_restore_ex(spdf_win_tabs* tabs, const char* window_id, char* out_window_id,
                                                    size_t out_len, spdf_win_session_frame* out_frame);

/* As spdf_win_session_save(), writing `frame` as the window's frame. NULL, or a
 * frame with w or h <= 0, keeps whatever frame the file already had for this
 * window -- so a save that knows nothing about geometry never moves a mac
 * user's window. */
int spdf_win_session_save_ex(const spdf_win_tabs* tabs, const char* window_id, const spdf_win_session_frame* frame);

/* --- detaching a tab into a new window -------------------------------------
 *
 * ONE PROCESS PER WINDOW, so tearing a tab off the strip means: write that tab
 * into session.yaml as a NEW window under a fresh id, remove it from this
 * window, and start a second ShenzhenPDF.exe that restores that id
 * (`--window <id>`). The file is the hand-over -- the same file the two
 * processes will keep merging into under session.lock from then on -- so
 * nothing else has to be invented for the second process to find its
 * document, its page and its zoom. macOS detaches in-process
 * (SPDFMacTabStripView.mm:788-836, -detachTabAtIndex:); GTK hands the page to a
 * fresh AdwTabView (spdf_window.c:391). Both keep the tab's whole view state,
 * and so does this.
 *
 * Writes the window under the lock and returns 1 with the new id in
 * `out_new_id`; the caller then closes the tab locally (with
 * prefer_most_recent_active, as :9300 does for a detach) and spawns the
 * process. 0 and nothing written for a bad index, an unreadable file or a
 * failed write -- the tab stays where it is. */
int spdf_win_session_detach_tab(const spdf_win_tabs* tabs, int index, const spdf_win_session_frame* frame,
                                char* out_new_id, size_t out_len);

#ifdef __cplusplus
}
#endif

#endif /* SPDF_WIN_SESSION_H */
