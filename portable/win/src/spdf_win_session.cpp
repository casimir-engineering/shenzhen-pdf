/* spdf_win_session.cpp — see spdf_win_session.h for the schema, its sources in
 * the two shipping frontends, and the three things this file refuses to do.
 *
 * The JSON marshalling this leans on lives in spdf_win_session_json.h, which
 * explains why hand-written scanning and formatting are the right answer here.
 * Nothing in either file writes YAML: the on-disk format has one codec and it
 * is the shared one.
 */
#include "spdf_win_session.h"

#include "spdf_win_compat.h" /* spdf_compat_getpid */
#include "spdf_win_paths.h"
#include "spdf_win_session_json.h"
#include "spdf_win_state.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* --- restore -------------------------------------------------------------- */

void spdf_win_session_new_window_id(char* out, size_t out_len) {
    static unsigned long sequence = 0;
    if (!out || out_len == 0) return;
    snprintf(out, out_len, "win-%ld-%llu-%lu", spdf_compat_getpid(), (unsigned long long)time(NULL), ++sequence);
}

static void apply_tab(spdf_win_tabs* tabs, const char* obj) {
    char* path = json_str(obj, "path");
    char* title;
    spdf_win_tab_view* view;
    int index;

    if (!path || !*path) {
        free(path);
        return;
    }
    title = json_str(obj, "title");
    index = spdf_win_tabs_append(tabs, path, title);
    free(path);
    free(title);
    if (index < 0) return;

    view = spdf_win_tabs_view(tabs, index);
    view->page = json_int(obj, "page", 0);
    /* A tab with no "viewMode" was written by a pre-multi-view GTK3 build,
     * whose pages were 1-based. Same migration the GTK reader performs. */
    if (!obj_value(obj, "viewMode", NULL)) view->page -= 1;
    if (view->page < 0) view->page = 0;
    view->zoom = json_num(obj, "zoom", 1.0);
    if (!(view->zoom > 0.0)) view->zoom = 1.0;
    view->custom_zoom = json_num(obj, "customZoom", view->zoom);
    if (!(view->custom_zoom > 0.0)) view->custom_zoom = view->zoom;
    view->fit_mode = json_int(obj, "fitMode", SPDF_WIN_TAB_FIT_PAGE);
    if (view->fit_mode < 0 || view->fit_mode > SPDF_WIN_TAB_FIT_PAGE) view->fit_mode = SPDF_WIN_TAB_FIT_PAGE;
    view->scroll_x = json_num(obj, "scrollX", 0.0);
    view->scroll_y = json_num(obj, "scrollY", 0.0);
    view->has_scroll_origin = obj_value(obj, "hasScrollOrigin", NULL)
                                  ? json_bool(obj, "hasScrollOrigin", 0)
                                  : (obj_value(obj, "scrollX", NULL) || obj_value(obj, "scrollY", NULL)) != 0;
    /* The tab's live query, restored into the find field on show. Truncated on
     * a character boundary if a mac file carries more than the field holds. */
    {
        char* search = json_str(obj, "searchText");
        if (search) {
            size_t n = strlen(search);
            if (n >= sizeof(view->search_text)) {
                n = sizeof(view->search_text) - 1;
                while (n > 0 && ((unsigned char)search[n] & 0xC0) == 0x80) --n;
            }
            memcpy(view->search_text, search, n);
            view->search_text[n] = '\0';
            free(search);
        }
    }
}

/* The window object to restore, or NULL. A root with "tabs" and no "windows"
 * is a pre-multi-window file and counts as one window. */
static const char* find_window(const char* root, const char* want_id) {
    const char* windows;
    const char* first = NULL;
    const char* end = NULL;
    const char* element;

    root = skip_ws(root);
    windows = obj_value(root, "windows", NULL);
    if (!windows || *windows != '[') return obj_value(root, "tabs", NULL) ? root : NULL;
    for (element = array_first(windows, &end); element; element = array_next(end, &end)) {
        if (*element != '{') continue;
        if (!first) first = element;
        if (want_id && *want_id) {
            char* id = json_str(element, "id");
            int hit = id && strcmp(id, want_id) == 0;
            free(id);
            if (hit) return element;
        }
    }
    return (want_id && *want_id) ? NULL : first;
}

spdf_win_session_status spdf_win_session_restore(spdf_win_tabs* tabs, const char* window_id, char* out_window_id,
                                                 size_t out_len) {
    return spdf_win_session_restore_ex(tabs, window_id, out_window_id, out_len, NULL);
}

spdf_win_session_status spdf_win_session_restore_ex(spdf_win_tabs* tabs, const char* window_id, char* out_window_id,
                                                    size_t out_len, spdf_win_session_frame* out_frame) {
    spdf_win_state_read_status status = SPDF_WIN_STATE_READ_ABSENT;
    char* json;
    const char* window;
    const char* tab_array;
    const char* end = NULL;
    const char* element;
    int before, added, selected;

    if (out_frame) memset(out_frame, 0, sizeof(*out_frame));
    if (!tabs) return SPDF_WIN_SESSION_ABSENT;
    json = spdf_win_state_read_json_checked(SPDF_WIN_STATE_SESSION, &status);
    if (status == SPDF_WIN_STATE_READ_FAILED) {
        free(json);
        return SPDF_WIN_SESSION_UNREADABLE;
    }
    if (!json) return SPDF_WIN_SESSION_ABSENT;

    before = spdf_win_tabs_count(tabs);
    window = find_window(json, window_id);
    tab_array = window ? obj_value(window, "tabs", NULL) : NULL;
    for (element = array_first(tab_array, &end); element; element = array_next(end, &end))
        if (*element == '{') apply_tab(tabs, element);

    added = spdf_win_tabs_count(tabs) - before;
    if (added > 0) {
        selected = json_int(window, "selectedTab", 0);
        if (selected < 0) selected = 0;
        if (selected >= added) selected = added - 1;
        /* DEFERRED on purpose: this is the whole lazy-restore promise. */
        spdf_win_tabs_select_deferred(tabs, before + selected);
        if (out_window_id && out_len > 0) {
            char* id = json_str(window, "id");
            if (id && *id) snprintf(out_window_id, out_len, "%s", id);
            else spdf_win_session_new_window_id(out_window_id, out_len);
            free(id);
        }
        if (out_frame) {
            const char* frame = obj_value(window, "frame", NULL);
            if (frame && *frame == '{') {
                out_frame->x = json_int(frame, "x", 0);
                out_frame->y = json_int(frame, "y", 0);
                out_frame->w = json_int(frame, "width", 0);
                out_frame->h = json_int(frame, "height", 0);
                if (out_frame->w <= 0 || out_frame->h <= 0) out_frame->w = out_frame->h = 0;
            }
        }
    }
    free(json);
    return added > 0 ? SPDF_WIN_SESSION_RESTORED : SPDF_WIN_SESSION_ABSENT;
}

/* --- save ----------------------------------------------------------------- */

/* Keys this port owns and rewrites. Everything else in an existing tab object
 * is carried through untouched — including "viewMode", so a markdown or
 * two-page view recorded by another frontend survives a Windows session. */
static int key_is_owned(const member* m) {
    static const char* const owned[] = {"path",    "title",   "page",    "zoom",            "customZoom",
                                        "fitMode", "scrollX", "scrollY", "hasScrollOrigin", "searchText"};
    size_t i;
    for (i = 0; i < sizeof(owned) / sizeof(owned[0]); ++i)
        if (key_is(m, owned[i])) return 1;
    return 0;
}

static const char* find_disk_tab(const char* window_obj, const char* path) {
    const char* tab_array = window_obj ? obj_value(window_obj, "tabs", NULL) : NULL;
    const char* end = NULL;
    const char* element;
    for (element = array_first(tab_array, &end); element; element = array_next(end, &end)) {
        char* candidate = json_str(element, "path");
        int hit = candidate && path && strcmp(candidate, path) == 0;
        free(candidate);
        if (hit) return element;
    }
    return NULL;
}

static void emit_tab(out_buf* out, const spdf_win_tabs* tabs, int index, const char* window_obj) {
    const char* path = spdf_win_tabs_path(tabs, index);
    const spdf_win_tab_view* view = spdf_win_tabs_view_const(tabs, index);
    const char* disk = find_disk_tab(window_obj, path);
    int has_view_mode = 0, ok;
    member m;

    buf_puts(out, "{\"path\":");
    emit_string(out, path);
    emit_key(out, "title");
    emit_string(out, spdf_win_tabs_title(tabs, index));
    emit_key(out, "page");
    emit_int(out, view->page);
    emit_key(out, "zoom");
    emit_fixed(out, view->zoom, 4);
    emit_key(out, "customZoom");
    emit_fixed(out, view->custom_zoom, 4);
    emit_key(out, "fitMode");
    emit_int(out, view->fit_mode);
    emit_key(out, "scrollX");
    emit_fixed(out, view->scroll_x, 4);
    emit_key(out, "scrollY");
    emit_fixed(out, view->scroll_y, 4);
    emit_key(out, "hasScrollOrigin");
    buf_puts(out, view->has_scroll_origin ? "true" : "false");
    /* Only when there is one: the mac writer omits the key for an empty query,
     * and a tab without a search must read back as a tab without a search. */
    if (view->search_text[0]) {
        emit_key(out, "searchText");
        emit_string(out, view->search_text);
    }

    for (ok = object_first(disk, &m); ok; ok = object_next(&m)) {
        if (key_is_owned(&m)) continue;
        if (key_is(&m, "viewMode")) has_view_mode = 1;
        buf_puts(out, ",\"");
        buf_put(out, m.key, m.key_len);
        buf_puts(out, "\":");
        buf_put(out, m.val, (size_t)(m.val_end - m.val));
    }
    /* Without this the GTK reader would treat our 0-based page as 1-based. */
    if (!has_view_mode) buf_puts(out, ",\"viewMode\":1");
    buf_puts(out, "}");
}

static void emit_window(out_buf* out, const spdf_win_tabs* tabs, const char* window_id, const char* disk_window,
                        const spdf_win_session_frame* frame) {
    const char* disk_frame_end = NULL;
    const char* disk_frame = disk_window ? obj_value(disk_window, "frame", &disk_frame_end) : NULL;
    int selected = spdf_win_tabs_selected_index(tabs);
    int i, count = spdf_win_tabs_count(tabs);

    buf_puts(out, "{\"id\":");
    emit_string(out, window_id);
    /* Our frame when the caller has one; else the frame already on disk, so a
     * save that knows no geometry never moves a mac user's window. */
    if (frame && frame->w > 0 && frame->h > 0) {
        buf_puts(out, ",\"frame\":{\"height\":");
        emit_int(out, frame->h);
        buf_puts(out, ",\"width\":");
        emit_int(out, frame->w);
        buf_puts(out, ",\"x\":");
        emit_int(out, frame->x);
        buf_puts(out, ",\"y\":");
        emit_int(out, frame->y);
        buf_puts(out, "}");
    } else if (disk_frame && disk_frame_end) {
        buf_puts(out, ",\"frame\":");
        buf_put(out, disk_frame, (size_t)(disk_frame_end - disk_frame));
    }
    buf_puts(out, ",\"selectedTab\":");
    emit_int(out, selected < 0 ? 0 : selected);
    buf_puts(out, ",\"tabs\":[");
    for (i = 0; i < count; ++i) {
        if (i) buf_puts(out, ",");
        emit_tab(out, tabs, i, disk_window);
    }
    buf_puts(out, "]}");
}

int spdf_win_session_save(const spdf_win_tabs* tabs, const char* window_id) {
    return spdf_win_session_save_ex(tabs, window_id, NULL);
}

int spdf_win_session_save_ex(const spdf_win_tabs* tabs, const char* window_id, const spdf_win_session_frame* frame) {
    char dir[SPDF_WIN_PATH_MAX];
    spdf_win_state_session_lock* lock;
    spdf_win_state_read_status status = SPDF_WIN_STATE_READ_ABSENT;
    char* existing;
    const char* disk_window = NULL;
    out_buf out;
    int written = 0, ok;

    if (!tabs || !window_id || !*window_id) return 0;
    if (!spdf_win_paths_state_dir(dir, sizeof(dir))) return 0;

    lock = spdf_win_state_session_lock_acquire(dir);
    existing = spdf_win_state_read_json_checked(SPDF_WIN_STATE_SESSION, &status);
    if (status == SPDF_WIN_STATE_READ_FAILED) {
        /* Present and unreadable. Write NOTHING: see the header. */
        free(existing);
        spdf_win_state_session_lock_release(lock);
        return 0;
    }

    memset(&out, 0, sizeof(out));
    buf_puts(&out, "{\"version\":2,\"windows\":[");
    if (existing) {
        const char* windows = obj_value(existing, "windows", NULL);
        const char* end = NULL;
        const char* element;
        for (element = array_first(windows, &end); element; element = array_next(end, &end)) {
            char* id = json_str(element, "id");
            int mine = id && strcmp(id, window_id) == 0;
            free(id);
            if (mine) {
                disk_window = element;
                continue;
            }
            if (written >= SPDF_WIN_SESSION_MAX_WINDOWS - 1) break;
            if (written++) buf_puts(&out, ",");
            buf_put(&out, element, (size_t)(end - element)); /* another process's window, verbatim */
        }
    }
    /* A window with no tabs is REMOVED from the file, matching the mac app's
     * -removeSessionStateForCurrentWindow when its last tab closes. */
    if (spdf_win_tabs_count(tabs) > 0) {
        if (written++) buf_puts(&out, ",");
        emit_window(&out, tabs, window_id, disk_window, frame);
    }
    buf_puts(&out, "]}");

    ok = !out.failed && out.data && spdf_win_state_write_json(SPDF_WIN_STATE_SESSION, out.data);
    free(out.data);
    free(existing);
    spdf_win_state_session_lock_release(lock);
    return ok;
}

/* --- detach --------------------------------------------------------------- */

int spdf_win_session_detach_tab(const spdf_win_tabs* tabs, int index, const spdf_win_session_frame* frame,
                                char* out_new_id, size_t out_len) {
    spdf_win_tabs* one;
    spdf_win_tab_view* view;
    const spdf_win_tab_view* source;
    char id[SPDF_WIN_SESSION_ID_MAX];
    int ok;

    if (!tabs || !out_new_id || out_len == 0) return 0;
    source = spdf_win_tabs_view_const(tabs, index);
    if (!source) return 0;
    /* A one-tab model, so the hand-over goes through the SAME emit path a
     * window's own save does -- one schema, one writer. No hooks: nothing may
     * open the document here, it is the other process's to open. */
    one = spdf_win_tabs_create();
    if (!one) return 0;
    if (spdf_win_tabs_append(one, spdf_win_tabs_path(tabs, index), spdf_win_tabs_title(tabs, index)) < 0) {
        spdf_win_tabs_destroy(one);
        return 0;
    }
    view = spdf_win_tabs_view(one, 0);
    *view = *source;
    spdf_win_tabs_select_deferred(one, 0);
    spdf_win_session_new_window_id(id, sizeof(id));
    ok = spdf_win_session_save_ex(one, id, frame);
    spdf_win_tabs_destroy(one);
    if (!ok) return 0;
    snprintf(out_new_id, out_len, "%s", id);
    return 1;
}
