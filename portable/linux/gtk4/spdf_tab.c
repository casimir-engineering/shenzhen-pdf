// spdf_tab.c — per-document tab model (contract struct in spdf_internal.h).
// A tab owns its core document, render service and doc view; the AdwTabPage
// owns the widget tree. The tab pointer rides on the page as object data
// ("spdf-tab") so window-level signal handlers can recover it.

#include <string.h>

#include "spdf_annot.h"
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
        // flips this when it swaps a document for its shadow copy.
        GIcon* icon = g_themed_icon_new("media-record-symbolic");
        adw_tab_page_set_indicator_icon(tab->page, icon);
        adw_tab_page_set_indicator_tooltip(tab->page, "Read-only shadow copy");
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

    if (error) *error = NULL;
    if (!win || !path || !*path) {
        if (error) *error = g_strdup("No document path.");
        return NULL;
    }

    doc = spdf_open(path, err, sizeof(err));
    if (!doc) {
        if (error) *error = g_strdup(err[0] ? err : "Could not open document.");
        return NULL;
    }

    tab = g_new0(SpdfTab, 1);
    tab->path = g_canonicalize_filename(path, NULL);
    tab->doc = doc;
    tab->win = win;
    tab->search_text = g_strdup("");

    {
        char* render_error = NULL;
        tab->render = spdf_render_service_new(tab->path, &render_error);
        if (!tab->render) {
            // The doc view tolerates a missing render service (blank canvas);
            // keep the tab usable for metadata/search rather than failing.
            g_warning("shenzhenpdf: no render service for %s: %s", tab->path,
                      render_error && *render_error ? render_error : "unknown error");
        }
        g_free(render_error);
    }
    tab->view = spdf_doc_view_new(tab);
    content = GTK_WIDGET(tab->view);

    view = spdf_window_get_tab_view(win);
    tab->page = adw_tab_view_append(view, content);
    g_object_set_data(G_OBJECT(tab->page), "spdf-tab", tab);
    title = spdf_tab_display_name(tab);
    adw_tab_page_set_title(tab->page, title);
    tooltip = g_markup_escape_text(tab->path, -1); // tab tooltip = full path
    adw_tab_page_set_tooltip(tab->page, tooltip);
    g_free(tooltip);
    g_free(title);
    if (tab->read_only_shadow) {
        tab->read_only_shadow = FALSE;
        spdf_tab_set_read_only_shadow(tab, TRUE);
    }
    spdf_annot_tab_attached(tab); // context menu, comment markers (Wave B)
    return tab;
}

void spdf_tab_close(SpdfTab* tab) {
    if (!tab) return;
    spdf_annot_tab_closing(tab); // comment cache + pending idle (Wave B)
    g_clear_pointer(&tab->render, spdf_render_service_free);
    if (tab->doc) {
        spdf_close(tab->doc);
        tab->doc = NULL;
    }
    g_free(tab->path);
    g_free(tab->search_text);
    tab->page = NULL;
    tab->view = NULL;
    tab->win = NULL;
    g_free(tab);
}
