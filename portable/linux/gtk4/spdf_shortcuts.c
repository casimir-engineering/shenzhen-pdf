// spdf_shortcuts.c — the single registry of every GAction name in the GTK4
// shell, with accelerators (Mac map, Cmd→Ctrl) and the F1 cheat sheet, which
// is a GtkShortcutsWindow generated from the same table so the two can never
// drift apart.

#include <string.h>

#include "spdf_app.h"

// Entries with a NULL group are registered (and get accels) but stay out of
// the cheat sheet; entries with no accels are name-registry-only.
static const SpdfShortcutEntry k_shortcuts[] = {
    // --- Files
    {"win.open", {"<Control>o", NULL, NULL}, "Files", "Open a document"},
    {"win.new-tab", {"<Control>t", NULL, NULL}, "Files", "Open a document in a new tab"},
    {"win.close-tab", {"<Control>w", NULL, NULL}, "Files", "Close the current tab"},
    {"win.reopen-closed", {"<Control><Shift>t", NULL, NULL}, "Files", "Reopen the last closed tab"},
    {"win.save-as", {"<Control>s", NULL, NULL}, "Files", "Save a copy of the document"},
    {"win.print", {"<Control>p", NULL, NULL}, "Files", "Print the document"},
    {"win.properties", {"<Control>i", NULL, NULL}, "Files", "Show document properties"},
    {"app.quit", {"<Control>q", NULL, NULL}, "Files", "Quit Shenzhen PDF"},
    // --- Search
    {"win.search", {"<Control>f", NULL, NULL}, "Search", "Find in the current document"},
    {"win.find-next", {"<Control>g", NULL, NULL}, "Search", "Go to the next match"},
    {"win.find-prev", {"<Control><Shift>g", NULL, NULL}, "Search", "Go to the previous match"},
    {"win.palette", {"<Control>k", NULL, NULL}, "Search", "Favorites and command palette"},
    // --- View
    {"win.zoom-in", {"<Control>plus", "<Control>equal", "<Control>KP_Add"}, "View", "Zoom in"},
    {"win.zoom-out", {"<Control>minus", "<Control>KP_Subtract", NULL}, "View", "Zoom out"},
    {"win.zoom-actual", {"<Control>0", "<Control>KP_0", NULL}, "View", "Zoom to actual size"},
    {"win.fit-page", {"<Control>1", NULL, NULL}, "View", "Fit page"},
    {"win.fit-width", {"<Control>2", NULL, NULL}, "View", "Fit width"},
    {"win.rotate-cw", {"<Control>r", NULL, NULL}, "View", "Rotate page clockwise"},
    {"win.rotate-ccw", {"<Control><Shift>r", NULL, NULL}, "View", "Rotate page anticlockwise"},
    {"win.sidebar", {"F9", NULL, NULL}, "View", "Toggle the side panel"},
    {"win.presentation", {"F5", "<Control><Shift>f", NULL}, "View", "Presentation mode (Escape exits)"},
    // --- Navigation
    {"win.goto-page", {"<Control>l", NULL, NULL}, "Navigation", "Go to page"},
    {"win.prev-tab", {"<Control>Page_Up", NULL, NULL}, "Navigation", "Previous tab"},
    {"win.next-tab", {"<Control>Page_Down", NULL, NULL}, "Navigation", "Next tab"},
    {"win.tab-overview", {"<Control><Shift>o", NULL, NULL}, "Navigation", "Open the tab overview"},
    // --- Edit
    {"win.copy", {"<Control>c", NULL, NULL}, "Edit", "Copy selected document text"},
    // --- Favorites
    {"win.favorite-page", {"<Control>b", NULL, NULL}, "Favorites", "Favorite the current page"},
    {"win.favorite-document", {"<Control><Shift>b", NULL, NULL}, "Favorites", "Favorite the current document"},
    // --- Tools (menu-only)
    {"win.ocr", {NULL, NULL, NULL}, NULL, "OCR the document"},
    {"win.translate", {NULL, NULL, NULL}, NULL, "Translate the document"},
    {"win.open-in-browser", {NULL, NULL, NULL}, NULL, "Open in the default browser"},
    {"win.show-in-folder", {NULL, NULL, NULL}, NULL, "Show the document in its folder"},
    {"win.copy-path", {NULL, NULL, NULL}, NULL, "Copy the document path"},
    // --- Doc-view context menu (spdf_annot.c, menu-only)
    {"win.annot-add-comment", {NULL, NULL, NULL}, NULL, "Add a comment at the selection or click point"},
    {"win.annot-add-highlight", {NULL, NULL, NULL}, NULL, "Highlight the selection with a comment"},
    {"win.annot-edit-comment", {NULL, NULL, NULL}, NULL, "Edit the clicked comment"},
    {"win.annot-delete-comment", {NULL, NULL, NULL}, NULL, "Delete the clicked comment"},
    {"win.copy-page-pdf", {NULL, NULL, NULL}, NULL, "Copy the page as a single-page PDF"},
    {"win.save-page-pdf", {NULL, NULL, NULL}, NULL, "Save the page as a single-page PDF"},
    // --- Tab context menu
    {"win.tab-show-in-folder", {NULL, NULL, NULL}, NULL, "Show this tab's document in its folder"},
    {"win.tab-copy-path", {NULL, NULL, NULL}, NULL, "Copy this tab's document path"},
    {"win.tab-copy-title", {NULL, NULL, NULL}, NULL, "Copy this tab's title"},
    // --- Application
    {"app.open-recent", {NULL, NULL, NULL}, NULL, "Open a recently opened document"},
    {"app.about", {NULL, NULL, NULL}, NULL, "About Shenzhen PDF"},
    {"win.check-updates", {NULL, NULL, NULL}, NULL, "Check for updates"},
    // --- Help
    {"win.shortcuts", {"F1", NULL, NULL}, "Help", "Show this shortcut cheat sheet"},
};

const SpdfShortcutEntry* spdf_shortcuts_table(int* count) {
    if (count) *count = (int)G_N_ELEMENTS(k_shortcuts);
    return k_shortcuts;
}

void spdf_shortcuts_install(GtkApplication* app) {
    g_return_if_fail(GTK_IS_APPLICATION(app));
    for (guint i = 0; i < G_N_ELEMENTS(k_shortcuts); ++i) {
        const SpdfShortcutEntry* entry = &k_shortcuts[i];
        const char* accels[4] = {NULL, NULL, NULL, NULL};
        int n = 0;

        for (int a = 0; a < 3; ++a)
            if (entry->accels[a]) accels[n++] = entry->accels[a];
        if (n == 0) continue;
        gtk_application_set_accels_for_action(app, entry->action, accels);
    }
}

// ---------------------------------------------------------------------------
// F1 cheat sheet. GtkShortcutsWindow only has a builder-friendly API, so the
// UI definition is generated from the table above.

static void append_group_xml(GString* ui, const char* group) {
    char* escaped_group = g_markup_escape_text(group, -1);
    g_string_append_printf(ui,
                           "<child><object class='GtkShortcutsGroup'>"
                           "<property name='title'>%s</property>",
                           escaped_group);
    g_free(escaped_group);
    for (guint i = 0; i < G_N_ELEMENTS(k_shortcuts); ++i) {
        const SpdfShortcutEntry* entry = &k_shortcuts[i];
        GString* accels;
        char* escaped_title;
        char* escaped_accels;

        if (!entry->group || strcmp(entry->group, group) != 0 || !entry->accels[0]) continue;
        accels = g_string_new("");
        for (int a = 0; a < 3; ++a) {
            if (!entry->accels[a]) continue;
            if (accels->len) g_string_append_c(accels, ' ');
            g_string_append(accels, entry->accels[a]);
        }
        escaped_title = g_markup_escape_text(entry->title, -1);
        escaped_accels = g_markup_escape_text(accels->str, -1);
        g_string_append_printf(ui,
                               "<child><object class='GtkShortcutsShortcut'>"
                               "<property name='title'>%s</property>"
                               "<property name='accelerator'>%s</property>"
                               "</object></child>",
                               escaped_title, escaped_accels);
        g_free(escaped_accels);
        g_free(escaped_title);
        g_string_free(accels, TRUE);
    }
    g_string_append(ui, "</object></child>");
}

void spdf_shortcuts_present_window(GtkWindow* parent) {
    GString* ui;
    const char* seen_groups[16];
    int seen_count = 0;
    GtkBuilder* builder;
    GtkWindow* window;

    ui = g_string_new(
        "<?xml version='1.0' encoding='UTF-8'?><interface>"
        "<object class='GtkShortcutsWindow' id='shortcuts'>"
        "<property name='modal'>1</property>"
        "<child><object class='GtkShortcutsSection'>"
        "<property name='section-name'>shortcuts</property>"
        "<property name='max-height'>12</property>");
    for (guint i = 0; i < G_N_ELEMENTS(k_shortcuts); ++i) {
        const char* group = k_shortcuts[i].group;
        gboolean seen = FALSE;

        if (!group) continue;
        for (int s = 0; s < seen_count; ++s) {
            if (strcmp(seen_groups[s], group) == 0) {
                seen = TRUE;
                break;
            }
        }
        if (seen || seen_count == (int)G_N_ELEMENTS(seen_groups)) continue;
        seen_groups[seen_count++] = group;
        append_group_xml(ui, group);
    }
    g_string_append(ui, "</object></child></object></interface>");

    builder = gtk_builder_new_from_string(ui->str, -1);
    window = GTK_WINDOW(gtk_builder_get_object(builder, "shortcuts"));
    if (window) {
        if (parent) gtk_window_set_transient_for(window, parent);
        gtk_window_present(window);
    }
    g_object_unref(builder);
    g_string_free(ui, TRUE);
}
