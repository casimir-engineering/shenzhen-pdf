// spdf_tab.c — per-document tab model (contract struct in spdf_internal.h).
// A tab owns its core document, render service and doc view; the AdwTabPage
// owns the widget tree. The tab pointer rides on the page as object data
// ("spdf-tab") so window-level signal handlers can recover it.

#include <string.h>

#include "spdf_annot.h"
#include "spdf_minimap.h"
#include "spdf_search.h"
#include "spdf_watcher.h"
#include "spdf_window.h"

static char* display_name_for_path(const char* path) {
    char* base;
    char* dot;

    base = g_path_get_basename(path && *path ? path : "Untitled");
    dot = strrchr(base, '.');
    if (dot && dot != base && g_ascii_strcasecmp(dot, ".pdf") == 0) *dot = '\0';
    return base;
}

char* spdf_tab_display_name(const SpdfTab* tab) {
    const char* meta;

    if (!tab) return g_strdup("Untitled");
    meta = tab->doc ? spdf_title(tab->doc) : NULL;
    if (meta && *meta) {
        // GTK3 parity: labels drop a trailing ".pdf" even from metadata.
        char* copy = g_strdup(meta);
        char* dot = strrchr(copy, '.');
        if (dot && dot != copy && g_ascii_strcasecmp(dot, ".pdf") == 0) *dot = '\0';
        return copy;
    }
    return display_name_for_path(tab->path);
}

const char* spdf_tab_get_path(SpdfTab* tab) {
    return tab ? tab->path : NULL;
}

void spdf_tab_set_read_only_shadow(SpdfTab* tab, gboolean read_only) {
    if (!tab || tab->read_only_shadow == read_only) return;
    tab->read_only_shadow = read_only;
    if (!tab->page) return;
    if (read_only) {
        // Indicator slot for the orange read-only dot; the watcher module
        // flips this when it swaps a document for its shadow copy. Tooltip
        // ports the Mac dot tooltip (minus the macOS prompt wording).
        GIcon* icon = g_themed_icon_new("media-record-symbolic");
        adw_tab_page_set_indicator_icon(tab->page, icon);
        adw_tab_page_set_indicator_tooltip(tab->page,
                                           "Read-only file. You're viewing a local copy; changes to the "
                                           "original are picked up automatically. Editing will ask to "
                                           "save a copy.");
        g_object_unref(icon);
    } else {
        adw_tab_page_set_indicator_icon(tab->page, NULL);
    }
}

SpdfTab* spdf_tab_open(SpdfWindow* win, const char* path, char** error) {
    char err[512] = "";
    spdf_document* doc;
    SpdfTab* tab;
    GtkWidget* content;
    AdwTabView* view;
    char* title;
    char* tooltip;
    char* canonical;
    // --- read-only shadow copy (spdf_watcher.c, Wave C) ---------------------
    // A read-only source opens through a private working copy; the tab's
    // identity (path, title, session, recents) stays on the SOURCE, only
    // open/render use the copy.
    SpdfWatcherResolution shadow = {NULL, 0, 0.0};
    gboolean source_read_only;

    if (error) *error = NULL;
    if (!win || !path || !*path) {
        if (error) *error = g_strdup("No document path.");
        return NULL;
    }

    canonical = g_canonicalize_filename(path, NULL);
    source_read_only = spdf_watcher_resolve_open(canonical, &shadow);
    doc = spdf_open(shadow.working_path ? shadow.working_path : canonical, err, sizeof(err));
    if (!doc) {
        if (error) *error = g_strdup(err[0] ? err : "Could not open document.");
        g_free(shadow.working_path);
        g_free(canonical);
        return NULL;
    }

    tab = g_new0(SpdfTab, 1);
    tab->path = canonical;
    tab->working_path = shadow.working_path; // owned; NULL when writable
    tab->ro_copy_file_size = shadow.copy_file_size;
    tab->ro_copy_modified_at = shadow.copy_modified_at;
    tab->doc = doc;
    tab->win = win;
    tab->search_text = g_strdup("");
    tab->search_regex_multiline = TRUE; // GTK3/session default
    tab->find_match_index = -1;

    {
        char* render_error = NULL;
        tab->render = spdf_render_service_new(tab->working_path ? tab->working_path : tab->path, &render_error);
        if (!tab->render) {
            // The doc view tolerates a missing render service (blank canvas);
            // keep the tab usable for metadata/search rather than failing.
            g_warning("shenzhenpdf: no render service for %s: %s", tab->path,
                      render_error && *render_error ? render_error : "unknown error");
        }
        g_free(render_error);
    }
    tab->view = spdf_doc_view_new(tab);
    // --- search module (wave B): the doc view implements GtkScrollable, so
    // it gets its GtkScrolledWindow here; a GtkOverlay on top hosts the
    // scrollbar heat-map lane (and later overlay lanes from other modules).
    tab->scroller = gtk_scrolled_window_new();
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(tab->scroller), GTK_WIDGET(tab->view));
    tab->overlay = gtk_overlay_new();
    gtk_overlay_set_child(GTK_OVERLAY(tab->overlay), tab->scroller);
    tab->search = spdf_search_controller_new(tab);
    gtk_overlay_add_overlay(GTK_OVERLAY(tab->overlay), spdf_search_markers_new(tab));
    // --- minimap module (wave B): the strip takes real width on the RIGHT of
    // the page content (Mac trailing-edge placement: document — with its
    // scrollbar + heat-map lane — then the map), so the overlay and the strip
    // share a horizontal row. tab->overlay stays the page-content root.
    {
        GtkWidget* row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
        gtk_widget_set_hexpand(tab->overlay, TRUE);
        gtk_box_append(GTK_BOX(row), tab->overlay);
        tab->minimap = spdf_minimap_new(tab);
        gtk_box_append(GTK_BOX(row), tab->minimap);
        content = row;
    }

    view = spdf_window_get_tab_view(win);
    tab->page = adw_tab_view_append(view, content);
    g_object_set_data(G_OBJECT(tab->page), "spdf-tab", tab);
    title = spdf_tab_display_name(tab);
    adw_tab_page_set_title(tab->page, title);
    tooltip = g_markup_escape_text(tab->path, -1); // tab tooltip = full path
    adw_tab_page_set_tooltip(tab->page, tooltip);
    g_free(tooltip);
    g_free(title);
    if (source_read_only) spdf_tab_set_read_only_shadow(tab, TRUE); // orange dot (Wave C)
    spdf_annot_tab_attached(tab); // context menu, comment markers (Wave B)
    spdf_watcher_tab_attached(tab); // file monitor on tab->path (Wave C)
    return tab;
}

void spdf_tab_close(SpdfTab* tab) {
    if (!tab) return;
    if (tab->search) {
        // Cancels any in-flight search; late idle deliveries hold their own
        // controller refs and drop themselves on the generation check.
        spdf_search_controller_detach(tab->search);
        g_clear_object(&tab->search);
    }
    spdf_annot_tab_closing(tab); // comment cache + pending idle (Wave B)
    spdf_watcher_tab_detached(tab); // monitor + timers + shadow fields (Wave C)
    g_clear_pointer(&tab->render, spdf_render_service_free);
    if (tab->doc) {
        spdf_close(tab->doc);
        tab->doc = NULL;
    }
    g_free(tab->path);
    g_free(tab->search_text);
    tab->page = NULL;
    tab->view = NULL;
    tab->scroller = NULL; // owned by the page's widget tree, like view
    tab->overlay = NULL;
    tab->minimap = NULL;  // owned by the page's widget tree (spdf_minimap.c)
    tab->win = NULL;
    g_free(tab);
}
