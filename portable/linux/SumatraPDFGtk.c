#include <gtk/gtk.h>

#include "sumatra_pdf_core.h"

#include <stdlib.h>
#include <string.h>

typedef struct app_state {
    GtkApplication *app;
    GtkWidget *window;
    GtkWidget *page_box;
    GtkWidget *scroll;
    GtkWidget *sidebar;
    GtkWidget *page_entry;
    GtkWidget *page_count_label;
    GtkWidget *fit_mode;
    GtkWidget *continuous;
    GtkWidget *search_entry;
    GtkWidget *status;

    spdf_document *doc;
    spdf_outline outline;
    char *path;
    int page_index;
    double zoom;
    int fit_mode_id;
    gboolean continuous_mode;
    gboolean panning;
    double pan_start_x;
    double pan_start_y;
    double pan_start_h;
    double pan_start_v;
} app_state;

static void render_current_page(app_state *state, gboolean scroll_to_top);

static void show_error(GtkWindow *window, const char *title, const char *detail)
{
    GtkWidget *dialog = gtk_message_dialog_new(window, GTK_DIALOG_MODAL, GTK_MESSAGE_WARNING, GTK_BUTTONS_CLOSE, "%s", title);
    gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(dialog), "%s", detail ? detail : "");
    gtk_dialog_run(GTK_DIALOG(dialog));
    gtk_widget_destroy(dialog);
}

static void free_pixbuf_pixels(guchar *pixels, gpointer data)
{
    (void)data;
    g_free(pixels);
}

static void update_controls(app_state *state)
{
    int page_count = spdf_page_count(state->doc);
    char text[128];

    gtk_widget_set_sensitive(state->page_entry, state->doc != NULL);
    gtk_widget_set_sensitive(state->search_entry, state->doc != NULL);
    gtk_widget_set_sensitive(state->fit_mode, state->doc != NULL);
    gtk_widget_set_sensitive(state->continuous, state->doc != NULL);

    if (!state->doc) {
        gtk_entry_set_text(GTK_ENTRY(state->page_entry), "");
        gtk_label_set_text(GTK_LABEL(state->page_count_label), "/ 0");
        gtk_label_set_text(GTK_LABEL(state->status), "Ready");
        return;
    }

    snprintf(text, sizeof(text), "%d", state->page_index + 1);
    gtk_entry_set_text(GTK_ENTRY(state->page_entry), text);
    snprintf(text, sizeof(text), "/ %d", page_count);
    gtk_label_set_text(GTK_LABEL(state->page_count_label), text);
    snprintf(text, sizeof(text), "Page %d of %d    Zoom %.0f%%", state->page_index + 1, page_count, state->zoom * 100.0);
    gtk_label_set_text(GTK_LABEL(state->status), text);
    gtk_window_set_title(GTK_WINDOW(state->window), spdf_title(state->doc));
}

static void rebuild_sidebar(app_state *state)
{
    GList *children = gtk_container_get_children(GTK_CONTAINER(state->sidebar));
    for (GList *it = children; it; it = it->next)
        gtk_widget_destroy(GTK_WIDGET(it->data));
    g_list_free(children);

    if (!state->doc)
        return;

    for (int i = 0; i < spdf_page_count(state->doc); ++i) {
        char text[64];
        snprintf(text, sizeof(text), "Page %d", i + 1);
        GtkWidget *row = gtk_list_box_row_new();
        GtkWidget *label = gtk_label_new(text);
        gtk_widget_set_margin_start(label, 8);
        gtk_widget_set_margin_end(label, 8);
        gtk_widget_set_margin_top(label, 4);
        gtk_widget_set_margin_bottom(label, 4);
        gtk_label_set_xalign(GTK_LABEL(label), 0.0);
        g_object_set_data(G_OBJECT(row), "page-index", GINT_TO_POINTER(i));
        gtk_container_add(GTK_CONTAINER(row), label);
        gtk_container_add(GTK_CONTAINER(state->sidebar), row);
    }
    gtk_widget_show_all(state->sidebar);
}

static GdkPixbuf *render_page_pixbuf(app_state *state, int page_index, char *err, size_t err_len)
{
    spdf_bitmap bitmap;
    if (!spdf_render_page_rgba(state->doc, page_index, (float)state->zoom, &bitmap, err, err_len))
        return NULL;

    guchar *pixels = g_malloc((gsize)bitmap.stride * (gsize)bitmap.height);
    memcpy(pixels, bitmap.rgba, (size_t)bitmap.stride * (size_t)bitmap.height);
    GdkPixbuf *pixbuf = gdk_pixbuf_new_from_data(pixels, GDK_COLORSPACE_RGB, TRUE, 8,
        bitmap.width, bitmap.height, bitmap.stride, free_pixbuf_pixels, NULL);
    spdf_free_bitmap(&bitmap);
    return pixbuf;
}

static void clear_page_box(app_state *state)
{
    GList *children = gtk_container_get_children(GTK_CONTAINER(state->page_box));
    for (GList *it = children; it; it = it->next)
        gtk_widget_destroy(GTK_WIDGET(it->data));
    g_list_free(children);
}

static void append_page_image(app_state *state, GdkPixbuf *pixbuf)
{
    GtkWidget *image = gtk_image_new_from_pixbuf(pixbuf);
    gtk_widget_set_margin_start(image, 22);
    gtk_widget_set_margin_end(image, 22);
    gtk_widget_set_margin_top(image, 13);
    gtk_widget_set_margin_bottom(image, 13);
    gtk_box_pack_start(GTK_BOX(state->page_box), image, FALSE, FALSE, 0);
}

static void open_path(app_state *state, const char *path)
{
    char err[1024];
    spdf_document *doc = spdf_open(path, err, sizeof(err));
    if (!doc) {
        show_error(GTK_WINDOW(state->window), "Could not open document", err);
        return;
    }

    spdf_free_outline(&state->outline);
    spdf_close(state->doc);
    state->doc = doc;
    free(state->path);
    state->path = strdup(path);
    state->page_index = 0;
    state->zoom = 1.0;
    state->fit_mode_id = 2;
    state->continuous_mode = TRUE;
    gtk_combo_box_set_active(GTK_COMBO_BOX(state->fit_mode), state->fit_mode_id);
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(state->continuous), TRUE);
    spdf_load_outline(state->doc, &state->outline, err, sizeof(err));
    rebuild_sidebar(state);
    render_current_page(state, TRUE);
}

static void open_clicked(GtkButton *button, gpointer user_data)
{
    (void)button;
    app_state *state = (app_state *)user_data;
    GtkWidget *dialog = gtk_file_chooser_dialog_new("Open Document",
        GTK_WINDOW(state->window),
        GTK_FILE_CHOOSER_ACTION_OPEN,
        "_Cancel", GTK_RESPONSE_CANCEL,
        "_Open", GTK_RESPONSE_ACCEPT,
        NULL);

    if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT) {
        char *filename = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog));
        open_path(state, filename);
        g_free(filename);
    }
    gtk_widget_destroy(dialog);
}

static void render_current_page(app_state *state, gboolean scroll_to_top)
{
    char err[1024];
    float page_width = 0;
    float page_height = 0;
    int start_page;
    int end_page;

    if (!state->doc)
        return;

    if (state->fit_mode_id > 0 && spdf_page_size(state->doc, state->page_index, &page_width, &page_height, err, sizeof(err))) {
        GtkAllocation allocation;
        gtk_widget_get_allocation(state->scroll, &allocation);
        double width_zoom = page_width > 0 ? (allocation.width - 54.0) / page_width : state->zoom;
        double height_zoom = page_height > 0 ? (allocation.height - 54.0) / page_height : state->zoom;
        if (state->fit_mode_id == 1)
            state->zoom = 1.0;
        else if (state->fit_mode_id == 2 && allocation.width > 80 && page_width > 0)
            state->zoom = MAX(0.10, MIN(8.0, (allocation.width - 54.0) / page_width));
        else if (state->fit_mode_id == 3 && allocation.height > 80 && page_height > 0)
            state->zoom = MAX(0.10, MIN(8.0, height_zoom));
        else if (state->fit_mode_id == 4 && allocation.width > 80 && allocation.height > 80)
            state->zoom = MAX(0.10, MIN(8.0, MIN(width_zoom, height_zoom)));
    }

    clear_page_box(state);
    start_page = state->continuous_mode ? 0 : state->page_index;
    end_page = state->continuous_mode ? spdf_page_count(state->doc) : state->page_index + 1;
    for (int i = start_page; i < end_page; ++i) {
        GdkPixbuf *pixbuf = render_page_pixbuf(state, i, err, sizeof(err));
        if (!pixbuf) {
            show_error(GTK_WINDOW(state->window), "Could not render page", err);
            return;
        }
        append_page_image(state, pixbuf);
        g_object_unref(pixbuf);
    }
    gtk_widget_show_all(state->page_box);

    if (scroll_to_top) {
        GtkAdjustment *vadj = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(state->scroll));
        gtk_adjustment_set_value(vadj, gtk_adjustment_get_lower(vadj));
    }

    update_controls(state);
}

static void page_entry_activate(GtkEntry *entry, gpointer user_data)
{
    app_state *state = (app_state *)user_data;
    int page_count = spdf_page_count(state->doc);
    int requested = atoi(gtk_entry_get_text(entry)) - 1;
    if (!state->doc)
        return;
    if (requested < 0)
        requested = 0;
    if (requested >= page_count)
        requested = page_count - 1;
    state->page_index = requested;
    render_current_page(state, TRUE);
}

static void previous_clicked(GtkButton *button, gpointer user_data)
{
    (void)button;
    app_state *state = (app_state *)user_data;
    if (state->doc && state->page_index > 0) {
        state->page_index--;
        render_current_page(state, TRUE);
    }
}

static void next_clicked(GtkButton *button, gpointer user_data)
{
    (void)button;
    app_state *state = (app_state *)user_data;
    if (state->doc && state->page_index + 1 < spdf_page_count(state->doc)) {
        state->page_index++;
        render_current_page(state, TRUE);
    }
}

static void zoom_in_clicked(GtkButton *button, gpointer user_data)
{
    (void)button;
    app_state *state = (app_state *)user_data;
    if (!state->doc)
        return;
    state->fit_mode_id = 0;
    gtk_combo_box_set_active(GTK_COMBO_BOX(state->fit_mode), 0);
    state->zoom = MIN(8.0, state->zoom * 1.15);
    render_current_page(state, FALSE);
}

static void zoom_out_clicked(GtkButton *button, gpointer user_data)
{
    (void)button;
    app_state *state = (app_state *)user_data;
    if (!state->doc)
        return;
    state->fit_mode_id = 0;
    gtk_combo_box_set_active(GTK_COMBO_BOX(state->fit_mode), 0);
    state->zoom = MAX(0.10, state->zoom / 1.15);
    render_current_page(state, FALSE);
}

static void fit_mode_changed(GtkComboBox *combo, gpointer user_data)
{
    app_state *state = (app_state *)user_data;
    state->fit_mode_id = gtk_combo_box_get_active(combo);
    render_current_page(state, FALSE);
}

static void continuous_toggled(GtkToggleButton *button, gpointer user_data)
{
    app_state *state = (app_state *)user_data;
    state->continuous_mode = gtk_toggle_button_get_active(button);
    render_current_page(state, TRUE);
}

static void sidebar_row_selected(GtkListBox *box, GtkListBoxRow *row, gpointer user_data)
{
    (void)box;
    app_state *state = (app_state *)user_data;
    if (!row)
        return;
    int page = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(row), "page-index"));
    if (state->doc && page != state->page_index) {
        state->page_index = page;
        render_current_page(state, TRUE);
    }
}

static void find_next(GtkEntry *entry, gpointer user_data)
{
    app_state *state = (app_state *)user_data;
    const char *needle = gtk_entry_get_text(entry);
    char err[1024];
    int page_count;

    if (!state->doc || !needle || !*needle)
        return;

    page_count = spdf_page_count(state->doc);
    for (int offset = 0; offset < page_count; ++offset) {
        int page = (state->page_index + offset) % page_count;
        int hits = spdf_search_page(state->doc, page, needle, err, sizeof(err));
        if (hits > 0) {
            char status[160];
            state->page_index = page;
            render_current_page(state, TRUE);
            snprintf(status, sizeof(status), "Found %d match%s on page %d", hits, hits == 1 ? "" : "es", page + 1);
            gtk_label_set_text(GTK_LABEL(state->status), status);
            return;
        }
    }
    gtk_label_set_text(GTK_LABEL(state->status), "No matches");
}

static gboolean page_scroll_event(GtkWidget *widget, GdkEventScroll *event, gpointer user_data)
{
    (void)widget;
    app_state *state = (app_state *)user_data;
    if (!state->doc)
        return FALSE;
    if (!state->continuous_mode || state->fit_mode_id == 3 || state->fit_mode_id == 4) {
        if (event->direction == GDK_SCROLL_DOWN || event->delta_y > 0)
            next_clicked(NULL, state);
        else if (event->direction == GDK_SCROLL_UP || event->delta_y < 0)
            previous_clicked(NULL, state);
        return TRUE;
    }
    return FALSE;
}

static gboolean page_button_press(GtkWidget *widget, GdkEventButton *event, gpointer user_data)
{
    (void)widget;
    app_state *state = (app_state *)user_data;
    if (event->button != 2 && event->button != 3)
        return FALSE;

    GtkAdjustment *hadj = gtk_scrolled_window_get_hadjustment(GTK_SCROLLED_WINDOW(state->scroll));
    GtkAdjustment *vadj = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(state->scroll));
    state->panning = TRUE;
    state->pan_start_x = event->x_root;
    state->pan_start_y = event->y_root;
    state->pan_start_h = gtk_adjustment_get_value(hadj);
    state->pan_start_v = gtk_adjustment_get_value(vadj);
    return TRUE;
}

static gboolean page_motion(GtkWidget *widget, GdkEventMotion *event, gpointer user_data)
{
    (void)widget;
    app_state *state = (app_state *)user_data;
    if (!state->panning)
        return FALSE;

    GtkAdjustment *hadj = gtk_scrolled_window_get_hadjustment(GTK_SCROLLED_WINDOW(state->scroll));
    GtkAdjustment *vadj = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(state->scroll));
    gtk_adjustment_set_value(hadj, state->pan_start_h - (event->x_root - state->pan_start_x));
    gtk_adjustment_set_value(vadj, state->pan_start_v - (event->y_root - state->pan_start_y));
    return TRUE;
}

static gboolean page_button_release(GtkWidget *widget, GdkEventButton *event, gpointer user_data)
{
    (void)widget;
    (void)event;
    app_state *state = (app_state *)user_data;
    state->panning = FALSE;
    return FALSE;
}

static void activate(GtkApplication *app, gpointer user_data)
{
    app_state *state = (app_state *)user_data;
    state->app = app;
    state->zoom = 1.0;
    state->fit_mode_id = 2;
    state->continuous_mode = TRUE;

    state->window = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(state->window), "SumatraPDF");
    gtk_window_set_default_size(GTK_WINDOW(state->window), 1100, 780);

    GtkWidget *root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_container_add(GTK_CONTAINER(state->window), root);

    GtkWidget *toolbar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    gtk_widget_set_margin_start(toolbar, 8);
    gtk_widget_set_margin_end(toolbar, 8);
    gtk_widget_set_margin_top(toolbar, 6);
    gtk_widget_set_margin_bottom(toolbar, 6);
    gtk_box_pack_start(GTK_BOX(root), toolbar, FALSE, FALSE, 0);

    GtkWidget *open = gtk_button_new_with_label("Open");
    GtkWidget *prev = gtk_button_new_with_label("<");
    GtkWidget *next = gtk_button_new_with_label(">");
    state->page_entry = gtk_entry_new();
    gtk_entry_set_width_chars(GTK_ENTRY(state->page_entry), 5);
    state->page_count_label = gtk_label_new("/ 0");
    GtkWidget *zoom_out = gtk_button_new_with_label("-");
    GtkWidget *zoom_in = gtk_button_new_with_label("+");
    state->fit_mode = gtk_combo_box_text_new();
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(state->fit_mode), "Custom");
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(state->fit_mode), "Actual");
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(state->fit_mode), "Fit width");
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(state->fit_mode), "Fit height");
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(state->fit_mode), "Fit page");
    gtk_combo_box_set_active(GTK_COMBO_BOX(state->fit_mode), state->fit_mode_id);
    state->continuous = gtk_check_button_new_with_label("Continuous");
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(state->continuous), TRUE);
    state->search_entry = gtk_search_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(state->search_entry), "Find");

    gtk_box_pack_start(GTK_BOX(toolbar), open, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(toolbar), prev, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(toolbar), next, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(toolbar), state->page_entry, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(toolbar), state->page_count_label, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(toolbar), zoom_out, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(toolbar), zoom_in, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(toolbar), state->fit_mode, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(toolbar), state->continuous, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(toolbar), state->search_entry, FALSE, FALSE, 0);

    GtkWidget *paned = gtk_paned_new(GTK_ORIENTATION_HORIZONTAL);
    gtk_box_pack_start(GTK_BOX(root), paned, TRUE, TRUE, 0);
    state->sidebar = gtk_list_box_new();
    gtk_widget_set_size_request(state->sidebar, 220, -1);
    GtkWidget *sidebar_scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_container_add(GTK_CONTAINER(sidebar_scroll), state->sidebar);
    gtk_paned_pack1(GTK_PANED(paned), sidebar_scroll, FALSE, FALSE);

    state->scroll = gtk_scrolled_window_new(NULL, NULL);
    GtkWidget *page_box = gtk_event_box_new();
    gtk_widget_add_events(page_box, GDK_BUTTON_PRESS_MASK | GDK_BUTTON_RELEASE_MASK | GDK_POINTER_MOTION_MASK | GDK_SCROLL_MASK);
    gtk_widget_override_background_color(page_box, GTK_STATE_FLAG_NORMAL, &(GdkRGBA){0.58, 0.58, 0.58, 1.0});
    state->page_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_widget_set_halign(state->page_box, GTK_ALIGN_CENTER);
    gtk_container_add(GTK_CONTAINER(page_box), state->page_box);
    gtk_container_add(GTK_CONTAINER(state->scroll), page_box);
    gtk_paned_pack2(GTK_PANED(paned), state->scroll, TRUE, FALSE);

    state->status = gtk_label_new("Ready");
    gtk_label_set_xalign(GTK_LABEL(state->status), 0.0);
    gtk_widget_set_margin_start(state->status, 8);
    gtk_widget_set_margin_end(state->status, 8);
    gtk_box_pack_start(GTK_BOX(root), state->status, FALSE, FALSE, 3);

    g_signal_connect(open, "clicked", G_CALLBACK(open_clicked), state);
    g_signal_connect(prev, "clicked", G_CALLBACK(previous_clicked), state);
    g_signal_connect(next, "clicked", G_CALLBACK(next_clicked), state);
    g_signal_connect(zoom_out, "clicked", G_CALLBACK(zoom_out_clicked), state);
    g_signal_connect(zoom_in, "clicked", G_CALLBACK(zoom_in_clicked), state);
    g_signal_connect(state->fit_mode, "changed", G_CALLBACK(fit_mode_changed), state);
    g_signal_connect(state->continuous, "toggled", G_CALLBACK(continuous_toggled), state);
    g_signal_connect(state->page_entry, "activate", G_CALLBACK(page_entry_activate), state);
    g_signal_connect(state->search_entry, "activate", G_CALLBACK(find_next), state);
    g_signal_connect(state->sidebar, "row-selected", G_CALLBACK(sidebar_row_selected), state);
    g_signal_connect(page_box, "scroll-event", G_CALLBACK(page_scroll_event), state);
    g_signal_connect(page_box, "button-press-event", G_CALLBACK(page_button_press), state);
    g_signal_connect(page_box, "motion-notify-event", G_CALLBACK(page_motion), state);
    g_signal_connect(page_box, "button-release-event", G_CALLBACK(page_button_release), state);

    gtk_widget_show_all(state->window);
    update_controls(state);
}

static void open_files(GtkApplication *app, GFile **files, gint n_files, const gchar *hint, gpointer user_data)
{
    (void)hint;
    app_state *state = (app_state *)user_data;
    if (!state->window)
        activate(app, user_data);
    if (n_files > 0) {
        char *path = g_file_get_path(files[0]);
        if (path) {
            open_path(state, path);
            g_free(path);
        }
    }
}

int main(int argc, char **argv)
{
    app_state state;
    int status;

    if (argc > 1 && strcmp(argv[1], "--version") == 0) {
        g_print("SumatraPDF portable gtk 0.2\n");
        return 0;
    }

    memset(&state, 0, sizeof(state));
    GtkApplication *app = gtk_application_new("org.sumatrapdfreader.SumatraPDF", G_APPLICATION_HANDLES_OPEN);
    g_signal_connect(app, "activate", G_CALLBACK(activate), &state);
    g_signal_connect(app, "open", G_CALLBACK(open_files), &state);
    status = g_application_run(G_APPLICATION(app), argc, argv);

    spdf_free_outline(&state.outline);
    spdf_close(state.doc);
    free(state.path);
    g_object_unref(app);
    return status;
}
