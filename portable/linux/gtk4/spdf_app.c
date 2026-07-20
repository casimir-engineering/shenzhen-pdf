// spdf_app.c — AdwApplication subclass. Owns the launch path (nothing
// synchronous or expensive before the first window is mapped), command-line
// documents (second instances forward here, so launches feel instant),
// multi-window session restore/capture through the spdf_state.c API, the
// recents list and the reopen-last-closed ring (10 entries, persisted state
// side, parity with GTK3 + Mac).

#include <glib-unix.h>
#include <string.h>

#include "spdf_app.h"
#include "spdf_minimap.h"
#include "spdf_watcher.h"
#include "spdf_window.h"

struct _SpdfApp {
    AdwApplication parent_instance;

    SpdfState* state; // lazy; see spdf_app_get_state()
    guint sigterm_id;
    guint sigint_id;
};

G_DEFINE_FINAL_TYPE(SpdfApp, spdf_app, ADW_TYPE_APPLICATION)

SpdfState* spdf_app_get_state(SpdfApp* app) {
    g_return_val_if_fail(SPDF_IS_APP(app), NULL);
    if (!app->state) {
        spdf_launch_mark("state-load-begin");
        app->state = spdf_state_load();
        spdf_launch_mark("state-load-end");
    }
    return app->state;
}

// ---------------------------------------------------------------------------
// Recents + reopen-last-closed ring (both live in spdf_state.c)

void spdf_app_remember_recent(SpdfApp* app, const char* path) {
    g_return_if_fail(SPDF_IS_APP(app));
    if (!path || !*path) return;
    spdf_state_add_recent(spdf_app_get_state(app), path);
    for (GList* it = gtk_application_get_windows(GTK_APPLICATION(app)); it; it = it->next)
        if (SPDF_IS_WINDOW(it->data)) spdf_window_refresh_recents(SPDF_WINDOW(it->data));
}

void spdf_app_remember_closed(SpdfApp* app, const char* path) {
    g_return_if_fail(SPDF_IS_APP(app));
    if (!path || !*path) return;
    spdf_state_remember_closed(spdf_app_get_state(app), path);
}

char* spdf_app_pop_closed(SpdfApp* app) {
    g_return_val_if_fail(SPDF_IS_APP(app), NULL);
    return spdf_state_pop_closed(spdf_app_get_state(app));
}

gboolean spdf_app_has_closed(SpdfApp* app) {
    g_return_val_if_fail(SPDF_IS_APP(app), FALSE);
    return spdf_state_closed_count(spdf_app_get_state(app)) > 0;
}

// ---------------------------------------------------------------------------
// Session capture. Each window is snapshotted into an owned SpdfSessionWindow
// and handed to the state module (merge-on-write keeps other processes'
// windows). Deliberately closed windows are removed instead (spdf_window.c
// calls spdf_app_forget_window via close-request).

static int fit_mode_id_for_view(SpdfDocView* view) {
    // settings/session schema: 0 custom, 1 actual, 2 width, 3 height, 4 page
    switch (spdf_doc_view_get_fit(view)) {
        case SPDF_FIT_PAGE: return 4;
        case SPDF_FIT_WIDTH: return 2;
        case SPDF_FIT_CUSTOM:
        default: return 0;
    }
}

static void snapshot_window(SpdfApp* app, SpdfWindow* win) {
    SpdfState* state = spdf_app_get_state(app);
    SpdfSessionWindow* snapshot;
    const SpdfSessionWindow* previous;
    SpdfTab* selected;
    int tabs;
    int width;
    int height;

    snapshot = spdf_session_window_new(spdf_window_get_session_id(win));
    if (!spdf_window_get_session_id(win)) spdf_window_set_session_id(win, snapshot->id);

    width = gtk_widget_get_width(GTK_WIDGET(win));
    height = gtk_widget_get_height(GTK_WIDGET(win));
    if (width <= 1 || height <= 1) gtk_window_get_default_size(GTK_WINDOW(win), &width, &height);
    snapshot->frame.width = width;
    snapshot->frame.height = height;
    // Wayland has no global window coordinates; keep the previously stored
    // origin (Mac/GTK3 files may carry one) instead of clobbering it.
    previous = spdf_state_session_window_by_id(state, snapshot->id);
    if (previous && previous->has_frame) {
        snapshot->frame.x = previous->frame.x;
        snapshot->frame.y = previous->frame.y;
    }
    snapshot->has_frame = TRUE;

    selected = spdf_window_current_tab(win);
    snapshot->selected_tab = 0;
    tabs = spdf_window_tab_count(win);
    for (int t = 0; t < tabs; ++t) {
        SpdfTab* tab = spdf_window_tab_at(win, t);
        SpdfSessionTab* session_tab;

        if (!tab || !tab->path || !*tab->path) continue;
        session_tab = spdf_session_window_add_tab(snapshot);
        session_tab->path = g_strdup(tab->path);
        if (tab->page) session_tab->title = g_strdup(adw_tab_page_get_title(tab->page));
        session_tab->search_text = g_strdup(tab->search_text ? tab->search_text : "");
        session_tab->search_regex = tab->search_regex;
        session_tab->search_regex_multiline = tab->search_regex_multiline;
        session_tab->find_match_index = tab->find_match_index;
        session_tab->read_only = tab->read_only_shadow;
        // --- watcher (Wave C): persist the shadow-copy binding so restore
        // reopens the same copy (Mac keys workingPath/roCopyFileSize/
        // roCopyModifiedAt; path above stays the SOURCE).
        session_tab->working_path = g_strdup(tab->working_path ? tab->working_path : "");
        session_tab->ro_copy_file_size = tab->ro_copy_file_size;
        session_tab->ro_copy_modified_at = tab->ro_copy_modified_at;
        // --- minimap module (wave B): per-tab visibility rides the session
        // like the Mac schema (documents.json keeps the per-document truth).
        session_tab->show_minimap = tab->show_minimap;
        session_tab->has_show_minimap = TRUE;
        if (tab->view) {
            session_tab->page = spdf_doc_view_current_page(tab->view);
            session_tab->zoom = spdf_doc_view_get_zoom(tab->view);
            session_tab->custom_zoom = session_tab->zoom;
            session_tab->fit_mode = fit_mode_id_for_view(tab->view);
            spdf_doc_view_get_scroll(tab->view, &session_tab->scroll_x, &session_tab->scroll_y);
            session_tab->has_scroll_origin = TRUE;
        }
        if (tab == selected) snapshot->selected_tab = (int)snapshot->tabs->len - 1;
    }
    if (snapshot->tabs->len == 0) {
        // Never persist tab-less windows: the session parser skips them on
        // read but the merge-on-write would keep the entry on disk forever.
        spdf_state_remove_session_window(state, snapshot->id);
        spdf_session_window_free(snapshot);
        return;
    }
    spdf_state_update_session_window(state, snapshot); // takes ownership
}

void spdf_app_save_session(SpdfApp* app) {
    SpdfState* state;
    GList* windows;
    GPtrArray* stale;
    guint stored;

    g_return_if_fail(SPDF_IS_APP(app));
    state = spdf_app_get_state(app);
    windows = g_list_copy(gtk_application_get_windows(GTK_APPLICATION(app)));
    windows = g_list_reverse(windows); // stable order: oldest window first
    for (GList* it = windows; it; it = it->next)
        if (SPDF_IS_WINDOW(it->data)) snapshot_window(app, SPDF_WINDOW(it->data));

    // GApplication uniqueness means no other process owns session windows, so
    // stored ids without a live window are leftovers from crashed/old runs —
    // prune them or every launch resurrects them forever.
    stale = g_ptr_array_new_with_free_func(g_free);
    stored = spdf_state_session_window_count(state);
    for (guint i = 0; i < stored; ++i) {
        const SpdfSessionWindow* sw = spdf_state_session_window(state, i);
        gboolean live = FALSE;

        if (!sw || !sw->id) continue;
        for (GList* it = windows; it && !live; it = it->next)
            if (SPDF_IS_WINDOW(it->data) &&
                g_strcmp0(spdf_window_get_session_id(SPDF_WINDOW(it->data)), sw->id) == 0)
                live = TRUE;
        if (!live) g_ptr_array_add(stale, g_strdup(sw->id));
    }
    for (guint i = 0; i < stale->len; ++i)
        spdf_state_remove_session_window(state, g_ptr_array_index(stale, i));
    g_ptr_array_unref(stale);
    g_list_free(windows);
    spdf_state_save_session(state);
}

void spdf_app_forget_window(SpdfApp* app, SpdfWindow* win) {
    const char* id;

    g_return_if_fail(SPDF_IS_APP(app));
    g_return_if_fail(SPDF_IS_WINDOW(win));
    id = spdf_window_get_session_id(win);
    if (!id) return;
    spdf_state_remove_session_window(spdf_app_get_state(app), id);
    spdf_state_save_session(spdf_app_get_state(app));
}

// ---------------------------------------------------------------------------
// Session restore. The selected tab of the first window opens synchronously
// so the first paint already shows the right document; everything else is
// restored from an idle handler after the window is mapped.

static void apply_session_geometry(SpdfWindow* win, const SpdfSessionWindow* stored) {
    GdkRectangle frame;
    GdkRectangle workarea = {0, 0, 0, 0}; // invalid => hard caps only; the
                                          // compositor places the window

    if (!stored->has_frame || stored->frame.width <= 0 || stored->frame.height <= 0) return;
    frame = stored->frame;
    spdf_state_clamp_geometry(&workarea, &frame);
    gtk_window_set_default_size(GTK_WINDOW(win), frame.width, frame.height);
}

static SpdfTab* open_session_tab(SpdfWindow* win, const SpdfSessionTab* stored) {
    SpdfTab* tab;

    if (!stored || !stored->path || !*stored->path) return NULL;
    // --- watcher (Wave C): a read_only entry reopens through its persisted
    // working copy (no source content read when the source is unchanged)
    // instead of the path directly; spdf_tab_open consumes the adoption.
    if (stored->read_only)
        spdf_watcher_prime_restore(stored->path, stored->working_path, stored->ro_copy_file_size,
                                   stored->ro_copy_modified_at);
    tab = spdf_window_open_path(win, stored->path, stored->page, FALSE);
    if (!tab) return NULL;
    if (stored->search_text && *stored->search_text) {
        g_free(tab->search_text);
        tab->search_text = g_strdup(stored->search_text);
    }
    // Search options restore into the tab fields only; the query re-runs
    // lazily on first search-bar open (spdf_search.c, GTK3 deferred find).
    tab->search_regex = stored->search_regex;
    tab->search_regex_multiline = stored->search_regex_multiline;
    tab->find_match_index = stored->find_match_index;
    // --- minimap module (wave B): a stored session value overrides the
    // documents.json / settings-default resolution done in spdf_minimap_new;
    // persist=FALSE keeps the restore from rewriting documents.json.
    if (stored->has_show_minimap) spdf_minimap_set_visible(tab, stored->show_minimap, FALSE);
    if (tab->view) {
        switch (stored->fit_mode) {
            case 4:
            case 3: spdf_doc_view_set_fit(tab->view, SPDF_FIT_PAGE); break;
            case 2: spdf_doc_view_set_fit(tab->view, SPDF_FIT_WIDTH); break;
            case 1: spdf_doc_view_set_zoom(tab->view, 1.0, FALSE, 0, 0); break;
            default:
                if (stored->zoom > 0.0) spdf_doc_view_set_zoom(tab->view, stored->zoom, FALSE, 0, 0);
                break;
        }
        if (stored->has_scroll_origin) spdf_doc_view_set_scroll(tab->view, stored->scroll_x, stored->scroll_y);
    }
    return tab;
}

typedef struct session_restore_request {
    SpdfApp* app;             // owned ref
    SpdfWindow* first_window; // owned ref, may be NULL
    int first_index;          // stored session index of first_window
    int first_selected;
} session_restore_request;

static gboolean session_restore_idle(gpointer user_data) {
    session_restore_request* req = user_data;
    SpdfApp* app = req->app;
    SpdfState* state = spdf_app_get_state(app);
    guint windows = spdf_state_session_window_count(state);

    if (req->first_window) {
        SpdfWindow* win = req->first_window;
        AdwTabView* view = spdf_window_get_tab_view(win);
        const SpdfSessionWindow* stored = spdf_state_session_window(state, (guint)req->first_index);
        AdwTabPage* first_page =
            view && adw_tab_view_get_n_pages(view) > 0 ? adw_tab_view_get_nth_page(view, 0) : NULL;

        if (stored && view) {
            for (guint t = 0; t < stored->tabs->len; ++t) {
                if ((int)t == req->first_selected) continue;
                open_session_tab(win, g_ptr_array_index(stored->tabs, t));
            }
            if (first_page) {
                if (req->first_selected > 0 && req->first_selected < adw_tab_view_get_n_pages(view))
                    adw_tab_view_reorder_page(view, first_page, req->first_selected);
                adw_tab_view_set_selected_page(view, first_page);
            }
        }
    }

    for (guint w = 0; w < windows; ++w) {
        const SpdfSessionWindow* stored = spdf_state_session_window(state, w);
        SpdfWindow* win;
        SpdfTab* selected_tab = NULL;

        if ((int)w == req->first_index) continue;
        if (!stored || stored->tabs->len == 0) continue; // stale empty entry
        win = spdf_window_new(ADW_APPLICATION(app));
        spdf_window_set_session_id(win, stored->id);
        apply_session_geometry(win, stored);
        for (guint t = 0; t < stored->tabs->len; ++t) {
            SpdfTab* tab = open_session_tab(win, g_ptr_array_index(stored->tabs, t));
            if ((int)t == stored->selected_tab) selected_tab = tab;
        }
        if (selected_tab && selected_tab->page)
            adw_tab_view_set_selected_page(spdf_window_get_tab_view(win), selected_tab->page);
        gtk_window_present(GTK_WINDOW(win));
    }

    spdf_launch_mark("session-restored");
    g_clear_object(&req->first_window);
    g_clear_object(&req->app);
    g_free(req);
    return G_SOURCE_REMOVE;
}

static void restore_session_or_open_empty(SpdfApp* app) {
    SpdfState* state = spdf_app_get_state(app);
    guint windows = spdf_state_session_window_count(state);
    SpdfWindow* win = spdf_window_new(ADW_APPLICATION(app));
    int first_index = -1;

    // Fast path: the first stored window that actually has tabs, so the
    // first paint already shows a document.
    for (guint w = 0; w < windows; ++w) {
        const SpdfSessionWindow* stored = spdf_state_session_window(state, w);
        if (stored && stored->tabs->len > 0) {
            first_index = (int)w;
            break;
        }
    }
    if (first_index < 0 && windows > 0 && spdf_state_session_window(state, 0)) first_index = 0;

    if (first_index >= 0) {
        const SpdfSessionWindow* stored = spdf_state_session_window(state, (guint)first_index);
        session_restore_request* req;
        int selected = CLAMP(stored->selected_tab, 0, MAX((int)stored->tabs->len - 1, 0));

        spdf_window_set_session_id(win, stored->id);
        apply_session_geometry(win, stored);
        if (stored->tabs->len > 0) open_session_tab(win, g_ptr_array_index(stored->tabs, (guint)selected));
        gtk_window_present(GTK_WINDOW(win));
        spdf_launch_mark("first-window-present");

        req = g_new0(session_restore_request, 1);
        req->app = g_object_ref(app);
        req->first_window = g_object_ref(win);
        req->first_index = first_index;
        req->first_selected = selected;
        g_idle_add(session_restore_idle, req);
        return;
    }
    gtk_window_present(GTK_WINDOW(win));
    spdf_launch_mark("first-window-present");
}

// ---------------------------------------------------------------------------
// Application actions

static SpdfWindow* ensure_window_for_documents(SpdfApp* app) {
    GtkWindow* active = gtk_application_get_active_window(GTK_APPLICATION(app));
    if (active && SPDF_IS_WINDOW(active)) return SPDF_WINDOW(active);
    return spdf_window_new(ADW_APPLICATION(app));
}

static void action_quit(GSimpleAction* action, GVariant* parameter, gpointer user_data) {
    SpdfApp* app = SPDF_APP(user_data);
    (void)action;
    (void)parameter;
    spdf_app_save_session(app);
    spdf_state_flush(spdf_app_get_state(app));
    g_application_quit(G_APPLICATION(app));
}

static void action_about(GSimpleAction* action, GVariant* parameter, gpointer user_data) {
    SpdfApp* app = SPDF_APP(user_data);
    GtkWindow* active = gtk_application_get_active_window(GTK_APPLICATION(app));
    AdwDialog* dialog = adw_about_dialog_new();

    (void)action;
    (void)parameter;
    g_object_set(dialog,
                 "application-name", SPDF_APP_DISPLAY_NAME,
                 "application-icon", SPDF_APP_ID,
                 "developer-name", "Intuition",
                 "version", "26.7.17",
                 NULL);
    adw_dialog_present(dialog, active ? GTK_WIDGET(active) : NULL);
}

static void action_open_recent(GSimpleAction* action, GVariant* parameter, gpointer user_data) {
    SpdfApp* app = SPDF_APP(user_data);
    const char* path = g_variant_get_string(parameter, NULL);
    SpdfWindow* win;

    (void)action;
    if (!path || !*path) return;
    win = ensure_window_for_documents(app);
    if (spdf_window_open_path(win, path, 0, TRUE)) gtk_window_present(GTK_WINDOW(win));
}

static const GActionEntry k_app_actions[] = {
    {"quit", action_quit, NULL, NULL, NULL, {0}},
    {"about", action_about, NULL, NULL, NULL, {0}},
    {"open-recent", action_open_recent, "s", NULL, NULL, {0}},
};

// ---------------------------------------------------------------------------
// GApplication vfuncs

static gboolean terminate_signal(gpointer user_data) {
    SpdfApp* app = SPDF_APP(user_data);
    app->sigterm_id = 0;
    app->sigint_id = 0;
    spdf_app_save_session(app);
    spdf_state_flush(spdf_app_get_state(app));
    g_application_quit(G_APPLICATION(app));
    return G_SOURCE_REMOVE;
}

static void spdf_app_startup(GApplication* app) {
    SpdfApp* self = SPDF_APP(app);

    spdf_launch_mark("startup-begin");
    G_APPLICATION_CLASS(spdf_app_parent_class)->startup(app);
    g_action_map_add_action_entries(G_ACTION_MAP(app), k_app_actions, G_N_ELEMENTS(k_app_actions), app);
    spdf_shortcuts_install(GTK_APPLICATION(app)); // hash inserts only; cheap
    self->sigterm_id = g_unix_signal_add(SIGTERM, terminate_signal, self);
    self->sigint_id = g_unix_signal_add(SIGINT, terminate_signal, self);
    spdf_launch_mark("startup-end");
}

static void spdf_app_activate(GApplication* app) {
    GtkWindow* active = gtk_application_get_active_window(GTK_APPLICATION(app));

    spdf_launch_mark("activate");
    if (active) {
        gtk_window_present(active);
        return;
    }
    restore_session_or_open_empty(SPDF_APP(app));
}

static int spdf_app_command_line(GApplication* app, GApplicationCommandLine* cmdline) {
    SpdfApp* self = SPDF_APP(app);
    int argc = 0;
    char** argv = g_application_command_line_get_arguments(cmdline, &argc);
    SpdfWindow* win = NULL;

    spdf_launch_mark("command-line");
    for (int i = 1; i < argc; ++i) {
        GFile* file;
        char* path;

        if (!argv[i] || !argv[i][0] || argv[i][0] == '-') continue;
        // Resolve against the invoker's cwd — this runs in the primary
        // instance even when a second process forwarded the arguments.
        file = g_application_command_line_create_file_for_arg(cmdline, argv[i]);
        path = g_file_get_path(file);
        if (path && *path) {
            if (!win) win = ensure_window_for_documents(self);
            spdf_window_open_path(win, path, 0, TRUE);
        }
        g_free(path);
        g_object_unref(file);
    }
    g_strfreev(argv);

    if (win) {
        // Launched with documents: skip session restore (GTK3 behavior).
        gtk_window_present(GTK_WINDOW(win));
        spdf_launch_mark("first-window-present");
    } else {
        g_application_activate(app);
    }
    return 0;
}

static void spdf_app_shutdown(GApplication* app) {
    SpdfApp* self = SPDF_APP(app);

    if (self->state) spdf_state_flush(self->state);
    if (self->sigterm_id) {
        g_source_remove(self->sigterm_id);
        self->sigterm_id = 0;
    }
    if (self->sigint_id) {
        g_source_remove(self->sigint_id);
        self->sigint_id = 0;
    }
    G_APPLICATION_CLASS(spdf_app_parent_class)->shutdown(app);
}

static void spdf_app_finalize(GObject* object) {
    SpdfApp* self = SPDF_APP(object);

    g_clear_pointer(&self->state, spdf_state_free);
    G_OBJECT_CLASS(spdf_app_parent_class)->finalize(object);
}

static void spdf_app_init(SpdfApp* self) {
    (void)self;
}

static void spdf_app_class_init(SpdfAppClass* klass) {
    GObjectClass* object_class = G_OBJECT_CLASS(klass);
    GApplicationClass* app_class = G_APPLICATION_CLASS(klass);

    object_class->finalize = spdf_app_finalize;
    app_class->startup = spdf_app_startup;
    app_class->activate = spdf_app_activate;
    app_class->command_line = spdf_app_command_line;
    app_class->shutdown = spdf_app_shutdown;
}

SpdfApp* spdf_app_new(void) {
    return g_object_new(SPDF_TYPE_APP,
                        "application-id", SPDF_APP_ID,
                        "flags", G_APPLICATION_HANDLES_COMMAND_LINE,
                        NULL);
}
