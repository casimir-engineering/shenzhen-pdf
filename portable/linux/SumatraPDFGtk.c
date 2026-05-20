#include <gtk/gtk.h>
#include <gio/gio.h>
#include <glib/gstdio.h>

#include "sumatra_pdf_core.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct favorite_item {
    char* path;
    char* title;
    int page_index;
    gboolean document;
} favorite_item;

typedef struct app_state {
    GtkApplication* app;
    GtkWidget* window;
    GtkWidget* open_in_browser;
    GtkWidget* show_in_folder;
    GtkWidget* ocr_button;
    GtkWidget* page_box;
    GtkWidget* scroll;
    GtkWidget* sidebar_container;
    GtkWidget* sidebar_tabs;
    GtkWidget* sidebar;
    GtkWidget* comments_sidebar;
    GtkWidget* page_entry;
    GtkWidget* page_count_label;
    GtkWidget* fit_mode;
    GtkWidget* continuous;
    GtkWidget* search_entry;
    GtkWidget* status;

    spdf_document* doc;
    spdf_outline outline;
    spdf_comments comments;
    char* path;
    char* config_dir;
    char* settings_path;
    char* session_path;
    char* favorites_path;
    favorite_item* favorites;
    int favorite_count;
    int favorite_capacity;
    char* restore_path;
    int restore_page_index;
    int page_index;
    double zoom;
    int fit_mode_id;
    gboolean continuous_mode;
    gboolean panning;
    gboolean suppress_restore_once;
    double pan_start_x;
    double pan_start_y;
    double pan_start_h;
    double pan_start_v;
    GThreadPool* render_pool;
    guint render_generation;
    gboolean render_error_shown;
} app_state;

typedef struct render_task {
    app_state* state;
    char* path;
    GtkWidget* image;
    guint generation;
    int page_index;
    double zoom;
} render_task;

typedef struct render_result {
    app_state* state;
    GtkWidget* image;
    GdkPixbuf* pixbuf;
    guint generation;
    int page_index;
    char err[1024];
} render_result;

typedef struct scroll_request {
    app_state* state;
    GtkWidget* widget;
    guint generation;
} scroll_request;

static void render_current_page(app_state* state, gboolean scroll_to_top);
static void open_path_at_page(app_state* state, const char* path, int page_index);

static char* json_escape(const char* text) {
    GString* out = g_string_new("");
    for (const unsigned char* p = (const unsigned char*)(text ? text : ""); *p; ++p) {
        if (*p == '"' || *p == '\\') g_string_append_c(out, '\\');
        if (*p == '\n')
            g_string_append(out, "\\n");
        else if (*p == '\r')
            g_string_append(out, "\\r");
        else if (*p == '\t')
            g_string_append(out, "\\t");
        else if (*p < 0x20)
            g_string_append_printf(out, "\\u%04x", (unsigned int)*p);
        else
            g_string_append_c(out, (char)*p);
    }
    return g_string_free(out, FALSE);
}

static char* json_get_string(const char* json, const char* key) {
    char pattern[96];
    char* pos;
    char* start;
    GString* out;

    snprintf(pattern, sizeof(pattern), "\"%s\"", key);
    pos = strstr(json, pattern);
    if (!pos) return NULL;
    pos = strchr(pos + strlen(pattern), ':');
    if (!pos) return NULL;
    pos++;
    while (*pos && isspace((unsigned char)*pos)) pos++;
    if (*pos != '"') return NULL;
    start = ++pos;
    out = g_string_new("");
    while (*start) {
        if (*start == '"') return g_string_free(out, FALSE);
        if (*start == '\\' && start[1]) {
            start++;
            if (*start == 'n')
                g_string_append_c(out, '\n');
            else if (*start == 'r')
                g_string_append_c(out, '\r');
            else if (*start == 't')
                g_string_append_c(out, '\t');
            else
                g_string_append_c(out, *start);
        } else {
            g_string_append_c(out, *start);
        }
        start++;
    }
    g_string_free(out, TRUE);
    return NULL;
}

static int json_get_int(const char* json, const char* key, int fallback) {
    char pattern[96];
    char* pos;

    snprintf(pattern, sizeof(pattern), "\"%s\"", key);
    pos = strstr(json, pattern);
    if (!pos) return fallback;
    pos = strchr(pos + strlen(pattern), ':');
    if (!pos) return fallback;
    return atoi(pos + 1);
}

static double json_get_double(const char* json, const char* key, double fallback) {
    char pattern[96];
    char* pos;

    snprintf(pattern, sizeof(pattern), "\"%s\"", key);
    pos = strstr(json, pattern);
    if (!pos) return fallback;
    pos = strchr(pos + strlen(pattern), ':');
    if (!pos) return fallback;
    return g_ascii_strtod(pos + 1, NULL);
}

static gboolean json_get_bool(const char* json, const char* key, gboolean fallback) {
    char pattern[96];
    char* pos;

    snprintf(pattern, sizeof(pattern), "\"%s\"", key);
    pos = strstr(json, pattern);
    if (!pos) return fallback;
    pos = strchr(pos + strlen(pattern), ':');
    if (!pos) return fallback;
    pos++;
    while (*pos && isspace((unsigned char)*pos)) pos++;
    if (strncmp(pos, "true", 4) == 0) return TRUE;
    if (strncmp(pos, "false", 5) == 0) return FALSE;
    return fallback;
}

static void init_config_paths(app_state* state) {
    state->config_dir = g_build_filename(g_get_user_config_dir(), "sumatrapdf", NULL);
    state->settings_path = g_build_filename(state->config_dir, "settings.json", NULL);
    state->session_path = g_build_filename(state->config_dir, "session.json", NULL);
    state->favorites_path = g_build_filename(state->config_dir, "favorites.json", NULL);
    g_mkdir_with_parents(state->config_dir, 0700);
}

static gboolean write_text_file(const char* path, const char* text) {
    GError* error = NULL;
    gboolean ok = g_file_set_contents(path, text, -1, &error);
    if (error) g_error_free(error);
    return ok;
}

static void show_error(GtkWindow* window, const char* title, const char* detail) {
    GtkWidget* dialog =
        gtk_message_dialog_new(window, GTK_DIALOG_MODAL, GTK_MESSAGE_WARNING, GTK_BUTTONS_CLOSE, "%s", title);
    gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(dialog), "%s", detail ? detail : "");
    gtk_dialog_run(GTK_DIALOG(dialog));
    gtk_widget_destroy(dialog);
}

static void free_favorites(app_state* state) {
    for (int i = 0; i < state->favorite_count; ++i) {
        g_free(state->favorites[i].path);
        g_free(state->favorites[i].title);
    }
    g_free(state->favorites);
    state->favorites = NULL;
    state->favorite_count = 0;
    state->favorite_capacity = 0;
}

static void strip_known_document_extension(char* text) {
    static const char* exts[] = {".pdf", ".xps", ".cbz", ".epub"};
    if (!text) return;

    for (gsize i = 0; i < G_N_ELEMENTS(exts); ++i) {
        gsize ext_len = strlen(exts[i]);
        char* match = NULL;
        for (char* cursor = text; *cursor; ++cursor) {
            if (g_ascii_strncasecmp(cursor, exts[i], ext_len) == 0) match = cursor;
        }
        if (!match) continue;
        char next = match[ext_len];
        if (next == '\0' || g_ascii_isspace(next) || next == '-') {
            memmove(match, match + ext_len, strlen(match + ext_len) + 1);
            return;
        }
    }
}

static char* display_name_for_path(const char* path) {
    char* name = g_path_get_basename(path ? path : "");
    strip_known_document_extension(name);
    return name;
}

static char* display_label_without_extension(const char* label) {
    char* text = g_strdup(label ? label : "");
    strip_known_document_extension(text);
    return text;
}

static char* display_path_without_extension(const char* path) {
    char* text = g_strdup(path ? path : "");
    char* slash = strrchr(text, G_DIR_SEPARATOR);
    char* base = slash ? slash + 1 : text;
    char* dot = strrchr(base, '.');
    if (dot && dot > base) *dot = '\0';
    return text;
}

static void add_favorite_item(app_state* state, const char* path, const char* title, int page_index,
                              gboolean document) {
    if (!path || !*path) return;
    if (state->favorite_count == state->favorite_capacity) {
        int capacity = state->favorite_capacity ? state->favorite_capacity * 2 : 16;
        state->favorites = g_realloc(state->favorites, (gsize)capacity * sizeof(favorite_item));
        state->favorite_capacity = capacity;
    }
    state->favorites[state->favorite_count].path = g_strdup(path);
    if (title && *title) {
        state->favorites[state->favorite_count].title = display_label_without_extension(title);
    } else {
        state->favorites[state->favorite_count].title = display_name_for_path(path);
    }
    state->favorites[state->favorite_count].page_index = page_index;
    state->favorites[state->favorite_count].document = document;
    state->favorite_count++;
}

static void save_settings(app_state* state) {
    GString* json = g_string_new("{\n");
    g_string_append_printf(json, "  \"fitMode\": %d,\n", state->fit_mode_id);
    g_string_append_printf(json, "  \"zoom\": %.4f,\n", state->zoom);
    g_string_append_printf(json, "  \"continuous\": %s\n", state->continuous_mode ? "true" : "false");
    g_string_append(json, "}\n");
    write_text_file(state->settings_path, json->str);
    g_string_free(json, TRUE);
}

static void save_session(app_state* state) {
    if (!state->doc && (!state->path || !*state->path)) return;

    char* path = json_escape(state->path ? state->path : "");
    GString* json = g_string_new("{\n");
    g_string_append_printf(json, "  \"path\": \"%s\",\n", path);
    g_string_append_printf(json, "  \"page\": %d\n", state->doc ? state->page_index + 1 : 0);
    g_string_append(json, "}\n");
    write_text_file(state->session_path, json->str);
    g_string_free(json, TRUE);
    g_free(path);
}

static void save_favorites(app_state* state) {
    GString* json = g_string_new("{\n  \"favorites\": [\n");
    for (int i = 0; i < state->favorite_count; ++i) {
        char* path = json_escape(state->favorites[i].path);
        char* title = json_escape(state->favorites[i].title);
        g_string_append_printf(json, "    { \"path\": \"%s\", \"title\": \"%s\", \"page\": %d, \"document\": %s }%s\n",
                               path, title, state->favorites[i].page_index + 1,
                               state->favorites[i].document ? "true" : "false",
                               i + 1 == state->favorite_count ? "" : ",");
        g_free(path);
        g_free(title);
    }
    g_string_append(json, "  ]\n}\n");
    write_text_file(state->favorites_path, json->str);
    g_string_free(json, TRUE);
}

static void load_settings(app_state* state) {
    char* json = NULL;
    gsize len = 0;
    if (!g_file_get_contents(state->settings_path, &json, &len, NULL)) return;
    state->fit_mode_id = json_get_int(json, "fitMode", state->fit_mode_id);
    if (state->fit_mode_id < 0 || state->fit_mode_id > 4) state->fit_mode_id = 2;
    state->zoom = json_get_double(json, "zoom", state->zoom);
    state->zoom = MAX(0.10, MIN(8.0, state->zoom));
    state->continuous_mode = json_get_bool(json, "continuous", state->continuous_mode);
    g_free(json);
}

static void load_session(app_state* state) {
    char* json = NULL;
    gsize len = 0;
    if (!g_file_get_contents(state->session_path, &json, &len, NULL)) return;
    g_free(state->restore_path);
    state->restore_path = json_get_string(json, "path");
    state->restore_page_index = MAX(0, json_get_int(json, "page", 1) - 1);
    g_free(json);
}

static void load_favorites(app_state* state) {
    char* json = NULL;
    char* pos;
    gsize len = 0;
    if (!g_file_get_contents(state->favorites_path, &json, &len, NULL)) return;
    pos = json;
    while ((pos = strstr(pos, "\"path\"")) != NULL) {
        char* end = strchr(pos, '}');
        char* object;
        char* path;
        char* title;
        int page_index;
        gboolean document;
        if (!end) break;
        object = g_strndup(pos, (gsize)(end - pos + 1));
        path = json_get_string(object, "path");
        title = json_get_string(object, "title");
        page_index = MAX(0, json_get_int(object, "page", 1) - 1);
        document = json_get_bool(object, "document", FALSE);
        add_favorite_item(state, path, title, page_index, document);
        g_free(path);
        g_free(title);
        g_free(object);
        pos = end + 1;
    }
    g_free(json);
}

static void free_pixbuf_pixels(guchar* pixels, gpointer data) {
    (void)data;
    g_free(pixels);
}

static gboolean path_has_pdf_extension(const char* path) {
    const char* dot = path ? strrchr(path, '.') : NULL;
    return dot && g_ascii_strcasecmp(dot, ".pdf") == 0;
}

static void update_controls(app_state* state) {
    int page_count = spdf_page_count(state->doc);
    char text[128];

    gtk_widget_set_sensitive(state->page_entry, state->doc != NULL);
    gtk_widget_set_sensitive(state->search_entry, state->doc != NULL);
    gtk_widget_set_sensitive(state->fit_mode, state->doc != NULL);
    gtk_widget_set_sensitive(state->continuous, state->doc != NULL);
    if (state->open_in_browser) gtk_widget_set_sensitive(state->open_in_browser, state->doc != NULL);
    if (state->show_in_folder)
        gtk_widget_set_sensitive(state->show_in_folder, state->doc != NULL && state->path != NULL);
    if (state->ocr_button)
        gtk_widget_set_sensitive(state->ocr_button, state->doc != NULL && path_has_pdf_extension(state->path));

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
    snprintf(text, sizeof(text), "Page %d of %d    Zoom %.0f%%", state->page_index + 1, page_count,
             state->zoom * 100.0);
    gtk_label_set_text(GTK_LABEL(state->status), text);
    char* title = display_label_without_extension(spdf_title(state->doc));
    gtk_window_set_title(GTK_WINDOW(state->window), title && *title ? title : "SumatraPDF");
    g_free(title);
}

static void clear_list_box(GtkWidget* list) {
    GList* children = gtk_container_get_children(GTK_CONTAINER(list));
    for (GList* it = children; it; it = it->next) gtk_widget_destroy(GTK_WIDGET(it->data));
    g_list_free(children);
}

static void add_sidebar_row(GtkWidget* list, const char* text, int page_index, int indent) {
    GtkWidget* row = gtk_list_box_row_new();
    GtkWidget* label = gtk_label_new(text);
    gtk_widget_set_margin_start(label, 8 + indent * 14);
    gtk_widget_set_margin_end(label, 8);
    gtk_widget_set_margin_top(label, 4);
    gtk_widget_set_margin_bottom(label, 4);
    gtk_label_set_xalign(GTK_LABEL(label), 0.0);
    gtk_label_set_ellipsize(GTK_LABEL(label), PANGO_ELLIPSIZE_END);
    g_object_set_data(G_OBJECT(row), "page-index", GINT_TO_POINTER(page_index));
    gtk_container_add(GTK_CONTAINER(row), label);
    gtk_container_add(GTK_CONTAINER(list), row);
}

static void rebuild_sidebar(app_state* state) {
    clear_list_box(state->sidebar);
    clear_list_box(state->comments_sidebar);

    if (!state->doc || (state->outline.count == 0 && state->comments.count == 0)) {
        if (state->sidebar_container) gtk_widget_hide(state->sidebar_container);
        return;
    }

    for (int i = 0; i < state->outline.count; ++i) {
        spdf_outline_item item = state->outline.items[i];
        add_sidebar_row(state->sidebar, item.title ? item.title : "Untitled", item.page_index, item.level);
    }

    for (int i = 0; i < state->comments.count; ++i) {
        spdf_comment_item item = state->comments.items[i];
        char text[512];
        const char* body = item.text && *item.text ? item.text : (item.type && *item.type ? item.type : "Comment");
        if (item.author && *item.author)
            snprintf(text, sizeof(text), "%s: %s", item.author, body);
        else
            snprintf(text, sizeof(text), "%s", body);
        add_sidebar_row(state->comments_sidebar, text, item.page_index, 0);
    }

    gtk_notebook_set_show_tabs(GTK_NOTEBOOK(state->sidebar_tabs),
                               state->outline.count > 0 && state->comments.count > 0);
    gtk_notebook_set_current_page(GTK_NOTEBOOK(state->sidebar_tabs), state->outline.count > 0 ? 0 : 1);
    gtk_widget_show_all(state->sidebar_container);
}

static GdkPixbuf* render_page_pixbuf_for_doc(spdf_document* doc, int page_index, double zoom, char* err,
                                             size_t err_len) {
    spdf_bitmap bitmap;
    if (!spdf_render_page_rgba(doc, page_index, (float)zoom, &bitmap, err, err_len)) return NULL;

    guchar* pixels = g_malloc((gsize)bitmap.stride * (gsize)bitmap.height);
    memcpy(pixels, bitmap.rgba, (size_t)bitmap.stride * (size_t)bitmap.height);
    GdkPixbuf* pixbuf = gdk_pixbuf_new_from_data(pixels, GDK_COLORSPACE_RGB, TRUE, 8, bitmap.width, bitmap.height,
                                                 bitmap.stride, free_pixbuf_pixels, NULL);
    spdf_free_bitmap(&bitmap);
    return pixbuf;
}

static GdkPixbuf* render_page_pixbuf(app_state* state, int page_index, char* err, size_t err_len) {
    return render_page_pixbuf_for_doc(state->doc, page_index, state->zoom, err, err_len);
}

static void clear_page_box(app_state* state) {
    GList* children = gtk_container_get_children(GTK_CONTAINER(state->page_box));
    for (GList* it = children; it; it = it->next) gtk_widget_destroy(GTK_WIDGET(it->data));
    g_list_free(children);
}

static void configure_page_image(GtkWidget* image) {
    gtk_widget_set_margin_start(image, 22);
    gtk_widget_set_margin_end(image, 22);
    gtk_widget_set_margin_top(image, 13);
    gtk_widget_set_margin_bottom(image, 13);
}

static GtkWidget* append_page_image(app_state* state, GdkPixbuf* pixbuf) {
    GtkWidget* image = gtk_image_new_from_pixbuf(pixbuf);
    configure_page_image(image);
    gtk_box_pack_start(GTK_BOX(state->page_box), image, FALSE, FALSE, 0);
    return image;
}

static GtkWidget* append_page_slot(app_state* state) {
    GtkWidget* image = gtk_image_new();
    configure_page_image(image);
    gtk_box_pack_start(GTK_BOX(state->page_box), image, FALSE, FALSE, 0);
    return image;
}

static void size_page_slot(GtkWidget* image, double zoom, float page_width, float page_height) {
    gtk_widget_set_size_request(image, MAX(1, (int)(page_width * zoom)), MAX(1, (int)(page_height * zoom)));
}

static gboolean render_finished_idle(gpointer data) {
    render_result* result = (render_result*)data;
    app_state* state = result->state;

    if (result->generation == state->render_generation) {
        if (result->pixbuf) {
            gtk_image_set_from_pixbuf(GTK_IMAGE(result->image), result->pixbuf);
            gtk_widget_show(result->image);
        } else if (!state->render_error_shown) {
            state->render_error_shown = TRUE;
            show_error(GTK_WINDOW(state->window), "Could not render page", result->err);
        }
    }

    if (result->pixbuf) g_object_unref(result->pixbuf);
    g_object_unref(result->image);
    g_free(result);
    return G_SOURCE_REMOVE;
}

static void render_worker(gpointer data, gpointer user_data) {
    (void)user_data;
    render_task* task = (render_task*)data;
    render_result* result = g_new0(render_result, 1);
    spdf_document* doc;

    result->state = task->state;
    result->image = task->image;
    result->generation = task->generation;
    result->page_index = task->page_index;

    doc = spdf_open(task->path, result->err, sizeof(result->err));
    if (doc) {
        result->pixbuf =
            render_page_pixbuf_for_doc(doc, task->page_index, task->zoom, result->err, sizeof(result->err));
        spdf_close(doc);
    }

    g_idle_add(render_finished_idle, result);
    g_free(task->path);
    g_free(task);
}

static void queue_page_render(app_state* state, GtkWidget* image, int page_index) {
    render_task* task;
    GError* error = NULL;

    if (!state->render_pool || !state->path) return;

    task = g_new0(render_task, 1);
    task->state = state;
    task->path = g_strdup(state->path);
    task->image = g_object_ref(image);
    task->generation = state->render_generation;
    task->page_index = page_index;
    task->zoom = state->zoom;

    if (!g_thread_pool_push(state->render_pool, task, &error)) {
        g_object_unref(task->image);
        g_free(task->path);
        g_free(task);
        if (!state->render_error_shown) {
            state->render_error_shown = TRUE;
            show_error(GTK_WINDOW(state->window), "Could not queue page render", error ? error->message : "");
        }
    }
    if (error) g_error_free(error);
}

static gboolean scroll_to_widget_idle(gpointer data) {
    scroll_request* request = (scroll_request*)data;
    app_state* state = request->state;

    if (request->generation == state->render_generation) {
        GtkAllocation allocation;
        GtkAdjustment* vadj = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(state->scroll));
        double upper = gtk_adjustment_get_upper(vadj);
        double page_size = gtk_adjustment_get_page_size(vadj);
        gtk_widget_get_allocation(request->widget, &allocation);
        gtk_adjustment_set_value(vadj,
                                 MAX(gtk_adjustment_get_lower(vadj), MIN((double)allocation.y, upper - page_size)));
    }

    g_object_unref(request->widget);
    g_free(request);
    return G_SOURCE_REMOVE;
}

static void scroll_to_rendered_page(app_state* state, GtkWidget* widget) {
    scroll_request* request = g_new0(scroll_request, 1);
    request->state = state;
    request->widget = g_object_ref(widget);
    request->generation = state->render_generation;
    g_idle_add(scroll_to_widget_idle, request);
}

static void open_path_at_page(app_state* state, const char* path, int page_index) {
    char err[1024];
    spdf_document* doc = spdf_open(path, err, sizeof(err));
    if (!doc) {
        show_error(GTK_WINDOW(state->window), "Could not open document", err);
        return;
    }

    spdf_free_outline(&state->outline);
    spdf_free_comments(&state->comments);
    spdf_close(state->doc);
    state->doc = doc;
    free(state->path);
    state->path = strdup(path);
    state->page_index = MAX(0, MIN(page_index, spdf_page_count(state->doc) - 1));
    gtk_combo_box_set_active(GTK_COMBO_BOX(state->fit_mode), state->fit_mode_id);
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(state->continuous), state->continuous_mode);
    spdf_load_outline(state->doc, &state->outline, err, sizeof(err));
    spdf_load_comments(state->doc, &state->comments, err, sizeof(err));
    rebuild_sidebar(state);
    render_current_page(state, TRUE);
    save_session(state);
}

static void open_path(app_state* state, const char* path) {
    open_path_at_page(state, path, 0);
}

static void open_clicked(GtkButton* button, gpointer user_data) {
    (void)button;
    app_state* state = (app_state*)user_data;
    GtkWidget* dialog =
        gtk_file_chooser_dialog_new("Open Document", GTK_WINDOW(state->window), GTK_FILE_CHOOSER_ACTION_OPEN, "_Cancel",
                                    GTK_RESPONSE_CANCEL, "_Open", GTK_RESPONSE_ACCEPT, NULL);

    if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT) {
        char* filename = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog));
        open_path(state, filename);
        g_free(filename);
    }
    gtk_widget_destroy(dialog);
}

static void render_current_page(app_state* state, gboolean scroll_to_top) {
    char err[1024];
    float page_width = 0;
    float page_height = 0;
    int start_page;
    int end_page;
    int page_count;

    if (!state->doc) return;

    if (!spdf_page_size(state->doc, state->page_index, &page_width, &page_height, err, sizeof(err))) {
        show_error(GTK_WINDOW(state->window), "Could not read page size", err);
        return;
    }

    if (state->fit_mode_id > 0) {
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

    state->render_generation++;
    state->render_error_shown = FALSE;
    clear_page_box(state);
    page_count = spdf_page_count(state->doc);
    start_page = state->continuous_mode ? 0 : state->page_index;
    end_page = state->continuous_mode ? page_count : state->page_index + 1;

    if (state->continuous_mode) {
        GtkWidget** slots = g_new0(GtkWidget*, page_count);
        GdkPixbuf* pixbuf;

        for (int i = start_page; i < end_page; ++i) {
            slots[i] = append_page_slot(state);
            size_page_slot(slots[i], state->zoom, page_width, page_height);
        }

        pixbuf = render_page_pixbuf(state, state->page_index, err, sizeof(err));
        if (!pixbuf) {
            g_free(slots);
            show_error(GTK_WINDOW(state->window), "Could not render page", err);
            return;
        }
        gtk_image_set_from_pixbuf(GTK_IMAGE(slots[state->page_index]), pixbuf);
        g_object_unref(pixbuf);
        gtk_widget_show_all(state->page_box);
        if (scroll_to_top) scroll_to_rendered_page(state, slots[state->page_index]);

        for (int distance = 1; distance < page_count; ++distance) {
            int next_page = state->page_index + distance;
            int previous_page = state->page_index - distance;
            if (next_page < page_count) queue_page_render(state, slots[next_page], next_page);
            if (previous_page >= 0) queue_page_render(state, slots[previous_page], previous_page);
        }
        g_free(slots);
    } else {
        for (int i = start_page; i < end_page; ++i) {
            GdkPixbuf* pixbuf = render_page_pixbuf(state, i, err, sizeof(err));
            if (!pixbuf) {
                show_error(GTK_WINDOW(state->window), "Could not render page", err);
                return;
            }
            append_page_image(state, pixbuf);
            g_object_unref(pixbuf);
        }
        gtk_widget_show_all(state->page_box);
    }

    if (scroll_to_top) {
        GtkAdjustment* vadj = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(state->scroll));
        gtk_adjustment_set_value(vadj, gtk_adjustment_get_lower(vadj));
    }

    update_controls(state);
}

static void page_entry_activate(GtkEntry* entry, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    int page_count = spdf_page_count(state->doc);
    int requested = atoi(gtk_entry_get_text(entry)) - 1;
    if (!state->doc) return;
    if (requested < 0) requested = 0;
    if (requested >= page_count) requested = page_count - 1;
    state->page_index = requested;
    render_current_page(state, TRUE);
    save_session(state);
}

static void previous_clicked(GtkButton* button, gpointer user_data) {
    (void)button;
    app_state* state = (app_state*)user_data;
    if (state->doc && state->page_index > 0) {
        state->page_index--;
        render_current_page(state, TRUE);
        save_session(state);
    }
}

static void next_clicked(GtkButton* button, gpointer user_data) {
    (void)button;
    app_state* state = (app_state*)user_data;
    if (state->doc && state->page_index + 1 < spdf_page_count(state->doc)) {
        state->page_index++;
        render_current_page(state, TRUE);
        save_session(state);
    }
}

static void zoom_in_clicked(GtkButton* button, gpointer user_data) {
    (void)button;
    app_state* state = (app_state*)user_data;
    if (!state->doc) return;
    state->fit_mode_id = 0;
    gtk_combo_box_set_active(GTK_COMBO_BOX(state->fit_mode), 0);
    state->zoom = MIN(8.0, state->zoom * 1.15);
    render_current_page(state, FALSE);
    save_settings(state);
}

static void zoom_out_clicked(GtkButton* button, gpointer user_data) {
    (void)button;
    app_state* state = (app_state*)user_data;
    if (!state->doc) return;
    state->fit_mode_id = 0;
    gtk_combo_box_set_active(GTK_COMBO_BOX(state->fit_mode), 0);
    state->zoom = MAX(0.10, state->zoom / 1.15);
    render_current_page(state, FALSE);
    save_settings(state);
}

static void fit_mode_changed(GtkComboBox* combo, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    state->fit_mode_id = gtk_combo_box_get_active(combo);
    render_current_page(state, FALSE);
    save_settings(state);
}

static void continuous_toggled(GtkToggleButton* button, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    state->continuous_mode = gtk_toggle_button_get_active(button);
    render_current_page(state, TRUE);
    save_settings(state);
}

static void sidebar_row_selected(GtkListBox* box, GtkListBoxRow* row, gpointer user_data) {
    (void)box;
    app_state* state = (app_state*)user_data;
    if (!row) return;
    int page = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(row), "page-index"));
    if (state->doc && page != state->page_index) {
        state->page_index = page;
        render_current_page(state, TRUE);
        save_session(state);
    }
}

static void find_next(GtkEntry* entry, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    const char* needle = gtk_entry_get_text(entry);
    char err[1024];
    int page_count;

    if (!state->doc || !needle || !*needle) return;

    page_count = spdf_page_count(state->doc);
    for (int offset = 0; offset < page_count; ++offset) {
        int page = (state->page_index + offset) % page_count;
        int hits = spdf_search_page(state->doc, page, needle, err, sizeof(err));
        if (hits > 0) {
            char status[160];
            state->page_index = page;
            render_current_page(state, TRUE);
            save_session(state);
            snprintf(status, sizeof(status), "Found %d match%s on page %d", hits, hits == 1 ? "" : "es", page + 1);
            gtk_label_set_text(GTK_LABEL(state->status), status);
            return;
        }
    }
    gtk_label_set_text(GTK_LABEL(state->status), "No matches");
}

static void open_in_browser(GtkWidget* widget, gpointer user_data) {
    (void)widget;
    app_state* state = (app_state*)user_data;
    GError* error = NULL;
    char* uri;

    if (!state->doc || !state->path) return;
    uri = g_filename_to_uri(state->path, NULL, &error);
    if (!uri) {
        show_error(GTK_WINDOW(state->window), "Could not build file URI", error ? error->message : "");
        if (error) g_error_free(error);
        return;
    }
    if (!gtk_show_uri_on_window(GTK_WINDOW(state->window), uri, GDK_CURRENT_TIME, &error)) {
        show_error(GTK_WINDOW(state->window), "Could not open in default browser", error ? error->message : "");
        if (error) g_error_free(error);
    }
    g_free(uri);
}

static gboolean reveal_file_with_file_manager(const char* uri) {
    GError* error = NULL;
    GDBusConnection* bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
    if (!bus) {
        if (error) g_error_free(error);
        return FALSE;
    }

    GVariantBuilder items;
    g_variant_builder_init(&items, G_VARIANT_TYPE("as"));
    g_variant_builder_add(&items, "s", uri);
    GVariant* result = g_dbus_connection_call_sync(
        bus, "org.freedesktop.FileManager1", "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1",
        "ShowItems", g_variant_new("(ass)", &items, ""), NULL, G_DBUS_CALL_FLAGS_NONE, -1, NULL, &error);
    g_object_unref(bus);
    if (result) {
        g_variant_unref(result);
        return TRUE;
    }
    if (error) g_error_free(error);
    return FALSE;
}

static gboolean open_directory_uri(app_state* state, const char* directory) {
    GError* error = NULL;
    char* uri = g_filename_to_uri(directory, NULL, &error);
    if (!uri) {
        if (error) g_error_free(error);
        return FALSE;
    }

    gboolean opened = gtk_show_uri_on_window(GTK_WINDOW(state->window), uri, GDK_CURRENT_TIME, &error);
    if (error) g_error_free(error);
    g_free(uri);
    return opened;
}

static gboolean spawn_xdg_open_directory(const char* directory) {
    GError* error = NULL;
    char* xdg_open = g_find_program_in_path("xdg-open");
    if (!xdg_open) return FALSE;

    char* argv[] = {xdg_open, (char*)directory, NULL};
    gboolean spawned = g_spawn_async(NULL, argv, NULL, G_SPAWN_DEFAULT, NULL, NULL, NULL, &error);
    if (error) g_error_free(error);
    g_free(xdg_open);
    return spawned;
}

static void show_in_folder(GtkWidget* widget, gpointer user_data) {
    (void)widget;
    app_state* state = (app_state*)user_data;
    GError* error = NULL;
    char* uri;
    char* directory;

    if (!state->doc || !state->path) return;

    uri = g_filename_to_uri(state->path, NULL, &error);
    if (!uri) {
        show_error(GTK_WINDOW(state->window), "Could not build file URI", error ? error->message : "");
        if (error) g_error_free(error);
        return;
    }
    if (reveal_file_with_file_manager(uri)) {
        g_free(uri);
        return;
    }
    g_free(uri);

    directory = g_path_get_dirname(state->path);
    if (open_directory_uri(state, directory) || spawn_xdg_open_directory(directory)) {
        g_free(directory);
        return;
    }

    show_error(GTK_WINDOW(state->window), "Could not show document in folder", "No file manager accepted the request.");
    g_free(directory);
}

typedef struct ocr_task {
    app_state* state;
    char* tool;
    char* path;
    char* tmp_path;
    int page_index;
    gboolean has_text;
} ocr_task;

typedef struct ocr_result {
    app_state* state;
    char* path;
    int page_index;
    gboolean success;
    char* message;
} ocr_result;

static void ocr_clicked(GtkButton* button, gpointer user_data);

typedef struct ocr_install_task {
    app_state* state;
    GtkWidget* dialog;
    GtkWidget* progress;
    GtkWidget* log;
    char* script;
} ocr_install_task;

typedef struct ocr_install_result {
    app_state* state;
    GtkWidget* dialog;
    GtkWidget* progress;
    GtkWidget* log;
    gboolean success;
    char* output;
} ocr_install_result;

static char* backup_path_for_pdf(const char* path) {
    char* dir = g_path_get_dirname(path);
    char* base = g_path_get_basename(path);
    char* dot = strrchr(base, '.');
    char* stem = dot ? g_strndup(base, (gsize)(dot - base)) : g_strdup(base);
    const char* ext = dot && dot[1] ? dot + 1 : "pdf";
    char* name = g_strdup_printf("%s_backup.%s", stem, ext);
    char* candidate = g_build_filename(dir, name, NULL);
    int index = 2;
    g_free(name);
    while (g_file_test(candidate, G_FILE_TEST_EXISTS)) {
        g_free(candidate);
        name = g_strdup_printf("%s_backup_%d.%s", stem, index++, ext);
        candidate = g_build_filename(dir, name, NULL);
        g_free(name);
    }
    g_free(stem);
    g_free(base);
    g_free(dir);
    return candidate;
}

static gboolean ocr_finished_idle(gpointer data) {
    ocr_result* result = (ocr_result*)data;
    app_state* state = result->state;
    if (state->ocr_button) gtk_widget_set_sensitive(state->ocr_button, state->doc != NULL);
    if (result->success) {
        open_path_at_page(state, result->path, result->page_index);
        gtk_label_set_text(GTK_LABEL(state->status), result->message ? result->message : "OCR complete.");
    } else {
        show_error(GTK_WINDOW(state->window), "OCR failed", result->message ? result->message : "");
        gtk_label_set_text(GTK_LABEL(state->status), "OCR failed.");
    }
    g_free(result->path);
    g_free(result->message);
    g_free(result);
    return G_SOURCE_REMOVE;
}

static gboolean block_dialog_delete(GtkWidget* widget, GdkEvent* event, gpointer user_data) {
    (void)widget;
    (void)event;
    (void)user_data;
    return TRUE;
}

static gboolean pulse_install_progress(gpointer data) {
    GtkProgressBar* progress = GTK_PROGRESS_BAR(data);
    if (!GPOINTER_TO_INT(g_object_get_data(G_OBJECT(progress), "ocr-install-running"))) return G_SOURCE_REMOVE;
    gtk_progress_bar_pulse(progress);
    return G_SOURCE_CONTINUE;
}

static char* ocr_install_script(void) {
    return g_strdup(
        "set -e\n"
        "if command -v ocrmypdf >/dev/null 2>&1 && command -v tesseract >/dev/null 2>&1; then exit 0; fi\n"
        "if ! command -v pkexec >/dev/null 2>&1; then echo 'pkexec is required for graphical package installation.'; "
        "exit 1; fi\n"
        "if command -v apt-get >/dev/null 2>&1; then\n"
        "  pkexec /bin/sh -c 'apt-get update && apt-get install -y ocrmypdf tesseract-ocr'\n"
        "elif command -v dnf >/dev/null 2>&1; then\n"
        "  pkexec dnf install -y ocrmypdf tesseract\n"
        "elif command -v pacman >/dev/null 2>&1; then\n"
        "  pkexec pacman -S --needed --noconfirm ocrmypdf tesseract\n"
        "elif command -v zypper >/dev/null 2>&1; then\n"
        "  pkexec zypper --non-interactive install ocrmypdf tesseract-ocr\n"
        "else\n"
        "  echo 'No supported package manager found (apt, dnf, pacman, zypper).'\n"
        "  exit 1\n"
        "fi\n"
        "command -v ocrmypdf >/dev/null 2>&1\n"
        "command -v tesseract >/dev/null 2>&1\n");
}

static void append_install_log(GtkWidget* log, const char* text) {
    GtkTextBuffer* buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(log));
    GtkTextIter end;
    gtk_text_buffer_get_end_iter(buffer, &end);
    gtk_text_buffer_insert(buffer, &end, text ? text : "", -1);
}

static gboolean ocr_install_finished_idle(gpointer data) {
    ocr_install_result* result = (ocr_install_result*)data;
    char* tool = NULL;
    char* tesseract = NULL;

    g_object_set_data(G_OBJECT(result->progress), "ocr-install-running", GINT_TO_POINTER(FALSE));
    gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(result->progress), result->success ? 1.0 : 0.0);
    append_install_log(result->log, result->output ? result->output : "");

    tool = g_find_program_in_path("ocrmypdf");
    tesseract = g_find_program_in_path("tesseract");
    if (result->success && tool && tesseract) {
        gtk_widget_destroy(result->dialog);
        if (result->state->ocr_button) gtk_widget_set_sensitive(result->state->ocr_button, TRUE);
        ocr_clicked(GTK_BUTTON(result->state->ocr_button), result->state);
    } else {
        append_install_log(result->log, "\nOCR installation failed. The package manager output is shown above.\n");
        if (result->state->ocr_button) gtk_widget_set_sensitive(result->state->ocr_button, result->state->doc != NULL);
        gtk_label_set_text(GTK_LABEL(result->state->status), "OCR installation failed.");
    }

    g_free(tool);
    g_free(tesseract);
    g_object_unref(result->dialog);
    g_object_unref(result->progress);
    g_object_unref(result->log);
    g_free(result->output);
    g_free(result);
    return G_SOURCE_REMOVE;
}

static gpointer ocr_install_worker(gpointer data) {
    ocr_install_task* task = (ocr_install_task*)data;
    ocr_install_result* result = g_new0(ocr_install_result, 1);
    gchar* stdout_text = NULL;
    gchar* stderr_text = NULL;
    GError* error = NULL;
    int status = 0;
    gchar* argv[] = {"/bin/sh", "-c", task->script, NULL};
    gboolean ok =
        g_spawn_sync(NULL, argv, NULL, G_SPAWN_DEFAULT, NULL, NULL, &stdout_text, &stderr_text, &status, &error);
    GString* output = g_string_new("");

    if (stdout_text) g_string_append(output, stdout_text);
    if (stderr_text) g_string_append(output, stderr_text);
    if (error && error->message) g_string_append_printf(output, "\n%s\n", error->message);

    result->state = task->state;
    result->dialog = task->dialog;
    result->progress = task->progress;
    result->log = task->log;
    result->success = ok && g_spawn_check_wait_status(status, &error);
    result->output = g_string_free(output, FALSE);

    if (error) g_error_free(error);
    g_free(stdout_text);
    g_free(stderr_text);
    g_free(task->script);
    g_free(task);
    g_idle_add(ocr_install_finished_idle, result);
    return NULL;
}

static void install_ocr_then_run(app_state* state) {
    GtkWidget* dialog = gtk_dialog_new();
    GtkWidget* content = gtk_dialog_get_content_area(GTK_DIALOG(dialog));
    GtkWidget* title = gtk_label_new("Installing OCRmyPDF and Tesseract");
    GtkWidget* progress = gtk_progress_bar_new();
    GtkWidget* scroll = gtk_scrolled_window_new(NULL, NULL);
    GtkWidget* log = gtk_text_view_new();
    ocr_install_task* task;

    gtk_window_set_title(GTK_WINDOW(dialog), "Installing OCR");
    gtk_window_set_transient_for(GTK_WINDOW(dialog), GTK_WINDOW(state->window));
    gtk_window_set_modal(GTK_WINDOW(dialog), TRUE);
    gtk_window_set_default_size(GTK_WINDOW(dialog), 640, 360);
    gtk_label_set_xalign(GTK_LABEL(title), 0.0);
    gtk_text_view_set_editable(GTK_TEXT_VIEW(log), FALSE);
    gtk_text_view_set_monospace(GTK_TEXT_VIEW(log), TRUE);
    gtk_widget_set_margin_start(title, 10);
    gtk_widget_set_margin_end(title, 10);
    gtk_widget_set_margin_top(title, 10);
    gtk_widget_set_margin_bottom(title, 6);
    gtk_widget_set_margin_start(progress, 10);
    gtk_widget_set_margin_end(progress, 10);
    gtk_widget_set_margin_bottom(progress, 8);
    gtk_container_add(GTK_CONTAINER(scroll), log);
    gtk_box_pack_start(GTK_BOX(content), title, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(content), progress, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(content), scroll, TRUE, TRUE, 0);
    g_signal_connect(dialog, "delete-event", G_CALLBACK(block_dialog_delete), NULL);
    append_install_log(log, "Preparing OCR installer...\n");
    gtk_widget_show_all(dialog);
    g_object_set_data(G_OBJECT(progress), "ocr-install-running", GINT_TO_POINTER(TRUE));
    g_timeout_add_full(G_PRIORITY_DEFAULT, 120, pulse_install_progress, g_object_ref(progress), g_object_unref);

    if (state->ocr_button) gtk_widget_set_sensitive(state->ocr_button, FALSE);
    task = g_new0(ocr_install_task, 1);
    task->state = state;
    task->dialog = g_object_ref(dialog);
    task->progress = g_object_ref(progress);
    task->log = g_object_ref(log);
    task->script = ocr_install_script();
    g_thread_unref(g_thread_new("install-ocr", ocr_install_worker, task));
}

static gpointer ocr_worker(gpointer data) {
    ocr_task* task = (ocr_task*)data;
    ocr_result* result = g_new0(ocr_result, 1);
    char jobs[32];
    gchar* stdout_text = NULL;
    gchar* stderr_text = NULL;
    GError* error = NULL;
    int status = 0;
    gboolean ok;

    snprintf(jobs, sizeof(jobs), "%u", MAX(1u, g_get_num_processors()));
    gchar* argv[] = {task->tool, "--jobs",       jobs, "--rotate-pages",
                     "--deskew", "--optimize",   "1",  task->has_text ? "--redo-ocr" : "--skip-text",
                     task->path, task->tmp_path, NULL};

    ok = g_spawn_sync(NULL, argv, NULL, G_SPAWN_DEFAULT, NULL, NULL, &stdout_text, &stderr_text, &status, &error);
    result->state = task->state;
    result->path = g_strdup(task->path);
    result->page_index = task->page_index;
    if (ok && g_spawn_check_wait_status(status, &error) && g_rename(task->tmp_path, task->path) == 0) {
        result->success = TRUE;
        result->message = g_strdup("OCR complete.");
    } else {
        const char* detail =
            error && error->message ? error->message : (stderr_text && *stderr_text ? stderr_text : stdout_text);
        result->message = g_strdup(detail ? detail : "OCRmyPDF exited with an error.");
        g_remove(task->tmp_path);
        if (error) g_error_free(error);
    }

    g_free(stdout_text);
    g_free(stderr_text);
    g_free(task->tool);
    g_free(task->path);
    g_free(task->tmp_path);
    g_free(task);
    g_idle_add(ocr_finished_idle, result);
    return NULL;
}

static void ocr_clicked(GtkButton* button, gpointer user_data) {
    (void)button;
    app_state* state = (app_state*)user_data;
    char err[1024];
    int has_text;
    char* tool;
    char* tesseract;
    char* backup = NULL;
    char* dir;
    char* base;
    char* tmp_path;
    ocr_task* task;

    if (!state->doc || !state->path || !path_has_pdf_extension(state->path)) return;
    tool = g_find_program_in_path("ocrmypdf");
    tesseract = g_find_program_in_path("tesseract");
    if (!tool || !tesseract) {
        GtkWidget* dialog = gtk_message_dialog_new(GTK_WINDOW(state->window), GTK_DIALOG_MODAL, GTK_MESSAGE_QUESTION,
                                                   GTK_BUTTONS_NONE, "Install OCR support?");
        gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(dialog),
                                                 "SumatraPDF can install OCRmyPDF and Tesseract, then continue OCR "
                                                 "automatically when installation finishes.");
        gtk_dialog_add_buttons(GTK_DIALOG(dialog), "_Install", GTK_RESPONSE_ACCEPT, "_Cancel", GTK_RESPONSE_CANCEL,
                               NULL);
        int response = gtk_dialog_run(GTK_DIALOG(dialog));
        gtk_widget_destroy(dialog);
        g_free(tool);
        g_free(tesseract);
        if (response == GTK_RESPONSE_ACCEPT) install_ocr_then_run(state);
        return;
    }
    g_free(tesseract);

    has_text = spdf_document_has_text(state->doc, 0, err, sizeof(err));
    if (has_text < 0) {
        show_error(GTK_WINDOW(state->window), "Could not inspect document text", err);
        g_free(tool);
        return;
    }

    if (has_text > 0) {
        GtkWidget* dialog = gtk_message_dialog_new(GTK_WINDOW(state->window), GTK_DIALOG_MODAL, GTK_MESSAGE_WARNING,
                                                   GTK_BUTTONS_NONE, "This PDF already contains selectable text.");
        gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(dialog),
                                                 "SumatraPDF will make a backup before OCR replaces it.");
        gtk_dialog_add_buttons(GTK_DIALOG(dialog), "_OCR and Backup", GTK_RESPONSE_ACCEPT, "_Cancel",
                               GTK_RESPONSE_CANCEL, NULL);
        int response = gtk_dialog_run(GTK_DIALOG(dialog));
        gtk_widget_destroy(dialog);
        if (response != GTK_RESPONSE_ACCEPT) {
            g_free(tool);
            return;
        }

        backup = backup_path_for_pdf(state->path);
        GFile* src = g_file_new_for_path(state->path);
        GFile* dst = g_file_new_for_path(backup);
        GError* copy_error = NULL;
        if (!g_file_copy(src, dst, G_FILE_COPY_NONE, NULL, NULL, NULL, &copy_error)) {
            show_error(GTK_WINDOW(state->window), "Could not create OCR backup", copy_error ? copy_error->message : "");
            if (copy_error) g_error_free(copy_error);
            g_object_unref(src);
            g_object_unref(dst);
            g_free(backup);
            g_free(tool);
            return;
        }
        g_object_unref(src);
        g_object_unref(dst);
    }

    dir = g_path_get_dirname(state->path);
    base = g_path_get_basename(state->path);
    char* tmp_name = g_strdup_printf(".%s.ocr-%u.pdf", base, g_random_int());
    tmp_path = g_build_filename(dir, tmp_name, NULL);
    g_free(tmp_name);
    task = g_new0(ocr_task, 1);
    task->state = state;
    task->tool = tool;
    task->path = g_strdup(state->path);
    task->tmp_path = tmp_path;
    task->page_index = state->page_index;
    task->has_text = has_text > 0;
    gtk_widget_set_sensitive(state->ocr_button, FALSE);
    gtk_label_set_text(GTK_LABEL(state->status), "OCR running...");
    g_thread_unref(g_thread_new("ocrmypdf", ocr_worker, task));
    g_free(base);
    g_free(dir);
    g_free(backup);
}

static void add_current_favorite(app_state* state, gboolean document) {
    char title[1024];
    char status[160];
    char* display_title;

    if (!state->doc || !state->path) return;
    display_title = display_label_without_extension(spdf_title(state->doc));
    if (document)
        snprintf(title, sizeof(title), "%s", display_title);
    else
        snprintf(title, sizeof(title), "%s - page %d", display_title, state->page_index + 1);
    g_free(display_title);
    add_favorite_item(state, state->path, title, document ? 0 : state->page_index, document);
    save_favorites(state);
    snprintf(status, sizeof(status), "Added %s favorite", document ? "document" : "page");
    gtk_label_set_text(GTK_LABEL(state->status), status);
}

static gboolean favorite_matches(favorite_item* favorite, const char* filter) {
    char* title;
    char* path;
    char* needle;
    gboolean matches;

    if (!filter || !*filter) return TRUE;
    title = g_utf8_strdown(favorite->title ? favorite->title : "", -1);
    path = g_utf8_strdown(favorite->path ? favorite->path : "", -1);
    needle = g_utf8_strdown(filter, -1);
    matches = strstr(title, needle) != NULL || strstr(path, needle) != NULL;
    g_free(title);
    g_free(path);
    g_free(needle);
    return matches;
}

static void add_list_separator(GtkWidget* list) {
    GtkWidget* row = gtk_list_box_row_new();
    GtkWidget* separator = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);
    gtk_widget_set_margin_start(separator, 8);
    gtk_widget_set_margin_end(separator, 8);
    gtk_widget_set_margin_top(separator, 2);
    gtk_widget_set_margin_bottom(separator, 4);
    gtk_container_add(GTK_CONTAINER(row), separator);
    gtk_container_add(GTK_CONTAINER(list), row);
}

static void rebuild_favorites_list(GtkListBox* list, app_state* state, const char* filter) {
    GList* children = gtk_container_get_children(GTK_CONTAINER(list));
    for (GList* it = children; it; it = it->next) gtk_widget_destroy(GTK_WIDGET(it->data));
    g_list_free(children);

    GtkWidget* fav_header = gtk_label_new("Favorites");
    gtk_label_set_xalign(GTK_LABEL(fav_header), 0.0);
    gtk_widget_set_margin_start(fav_header, 8);
    gtk_widget_set_margin_top(fav_header, 8);
    gtk_widget_set_margin_bottom(fav_header, 4);
    gtk_container_add(GTK_CONTAINER(list), fav_header);
    add_list_separator(GTK_WIDGET(list));

    for (int i = 0; i < state->favorite_count; ++i) {
        char text[1600];
        char* title;
        char* path;
        GtkWidget* row;
        GtkWidget* label;
        if (!favorite_matches(&state->favorites[i], filter)) continue;
        title = display_label_without_extension(state->favorites[i].title ? state->favorites[i].title : "Favorite");
        path = display_path_without_extension(state->favorites[i].path ? state->favorites[i].path : "");
        snprintf(text, sizeof(text), "%s%s\n%s", title, state->favorites[i].document ? "" : " (page favorite)", path);
        g_free(title);
        g_free(path);
        row = gtk_list_box_row_new();
        label = gtk_label_new(text);
        gtk_label_set_xalign(GTK_LABEL(label), 0.0);
        gtk_widget_set_margin_start(label, 8);
        gtk_widget_set_margin_end(label, 8);
        gtk_widget_set_margin_top(label, 6);
        gtk_widget_set_margin_bottom(label, 6);
        g_object_set_data(G_OBJECT(row), "favorite-index", GINT_TO_POINTER(i + 1));
        gtk_container_add(GTK_CONTAINER(row), label);
        gtk_container_add(GTK_CONTAINER(list), row);
    }

    if (state->doc && filter && *filter) {
        char err[1024];
        GtkWidget* doc_header = gtk_label_new("Open documents");
        gtk_label_set_xalign(GTK_LABEL(doc_header), 0.0);
        gtk_widget_set_margin_start(doc_header, 8);
        gtk_widget_set_margin_top(doc_header, 12);
        gtk_widget_set_margin_bottom(doc_header, 4);
        gtk_container_add(GTK_CONTAINER(list), doc_header);
        add_list_separator(GTK_WIDGET(list));

        for (int page = 0; page < spdf_page_count(state->doc); ++page) {
            int hits = spdf_search_page(state->doc, page, filter, err, sizeof(err));
            if (hits <= 0) continue;
            char text[1600];
            char* path = display_path_without_extension(state->path ? state->path : "Current document");
            GtkWidget* row = gtk_list_box_row_new();
            GtkWidget* label;
            snprintf(text, sizeof(text), "%s\nPage %d - %d match%s", path, page + 1, hits, hits == 1 ? "" : "es");
            g_free(path);
            label = gtk_label_new(text);
            gtk_label_set_xalign(GTK_LABEL(label), 0.0);
            gtk_widget_set_margin_start(label, 8);
            gtk_widget_set_margin_end(label, 8);
            gtk_widget_set_margin_top(label, 6);
            gtk_widget_set_margin_bottom(label, 6);
            g_object_set_data(G_OBJECT(row), "search-page", GINT_TO_POINTER(page + 1));
            gtk_container_add(GTK_CONTAINER(row), label);
            gtk_container_add(GTK_CONTAINER(list), row);
        }
    }
    gtk_widget_show_all(GTK_WIDGET(list));
}

static void favorites_search_changed(GtkEntry* entry, gpointer user_data) {
    GtkWidget* list = GTK_WIDGET(g_object_get_data(G_OBJECT(entry), "favorites-list"));
    app_state* state = (app_state*)user_data;
    rebuild_favorites_list(GTK_LIST_BOX(list), state, gtk_entry_get_text(entry));
}

static void favorites_row_activated(GtkListBox* list, GtkListBoxRow* row, gpointer user_data);

static void favorites_search_activate(GtkEntry* entry, gpointer user_data) {
    GtkWidget* list = GTK_WIDGET(g_object_get_data(G_OBJECT(entry), "favorites-list"));
    GtkListBoxRow* row = gtk_list_box_get_selected_row(GTK_LIST_BOX(list));
    if (!row ||
        (!g_object_get_data(G_OBJECT(row), "favorite-index") && !g_object_get_data(G_OBJECT(row), "search-page"))) {
        for (int i = 0; (row = gtk_list_box_get_row_at_index(GTK_LIST_BOX(list), i)) != NULL; ++i) {
            if (g_object_get_data(G_OBJECT(row), "favorite-index") || g_object_get_data(G_OBJECT(row), "search-page"))
                break;
        }
    }
    favorites_row_activated(GTK_LIST_BOX(list), row, user_data);
}

static void favorites_row_activated(GtkListBox* list, GtkListBoxRow* row, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    GtkWidget* dialog = GTK_WIDGET(g_object_get_data(G_OBJECT(list), "favorites-dialog"));
    int index;
    if (!row) return;
    int search_page = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(row), "search-page"));
    if (search_page > 0) {
        state->page_index = search_page - 1;
        render_current_page(state, TRUE);
        save_session(state);
        gtk_dialog_response(GTK_DIALOG(dialog), GTK_RESPONSE_ACCEPT);
        return;
    }
    index = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(row), "favorite-index")) - 1;
    if (index >= 0 && index < state->favorite_count) {
        favorite_item* favorite = &state->favorites[index];
        open_path_at_page(state, favorite->path, favorite->document ? 0 : favorite->page_index);
        gtk_dialog_response(GTK_DIALOG(dialog), GTK_RESPONSE_ACCEPT);
    }
}

static void show_favorites_dialog(app_state* state) {
    GtkWidget* dialog = gtk_dialog_new_with_buttons("Favorites", GTK_WINDOW(state->window), GTK_DIALOG_MODAL, "_Close",
                                                    GTK_RESPONSE_CLOSE, NULL);
    GtkWidget* content = gtk_dialog_get_content_area(GTK_DIALOG(dialog));
    GtkWidget* search = gtk_search_entry_new();
    GtkWidget* scroll = gtk_scrolled_window_new(NULL, NULL);
    GtkWidget* list = gtk_list_box_new();

    gtk_window_set_default_size(GTK_WINDOW(dialog), 560, 420);
    gtk_entry_set_placeholder_text(GTK_ENTRY(search), "Search favorites");
    gtk_widget_set_margin_start(search, 8);
    gtk_widget_set_margin_end(search, 8);
    gtk_widget_set_margin_top(search, 8);
    gtk_widget_set_margin_bottom(search, 8);
    gtk_container_add(GTK_CONTAINER(scroll), list);
    gtk_box_pack_start(GTK_BOX(content), search, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(content), scroll, TRUE, TRUE, 0);
    g_object_set_data(G_OBJECT(search), "favorites-list", list);
    g_object_set_data(G_OBJECT(list), "favorites-dialog", dialog);
    g_signal_connect(search, "search-changed", G_CALLBACK(favorites_search_changed), state);
    g_signal_connect(search, "activate", G_CALLBACK(favorites_search_activate), state);
    g_signal_connect(list, "row-activated", G_CALLBACK(favorites_row_activated), state);
    rebuild_favorites_list(GTK_LIST_BOX(list), state, "");
    gtk_widget_show_all(dialog);
    gtk_widget_grab_focus(search);
    gtk_dialog_run(GTK_DIALOG(dialog));
    gtk_widget_destroy(dialog);
}

static gboolean key_press(GtkWidget* widget, GdkEventKey* event, gpointer user_data) {
    (void)widget;
    app_state* state = (app_state*)user_data;
    gboolean ctrl = (event->state & GDK_CONTROL_MASK) != 0;
    gboolean shift = (event->state & GDK_SHIFT_MASK) != 0;

    if (!ctrl) return FALSE;
    if (event->keyval == GDK_KEY_f || event->keyval == GDK_KEY_F) {
        gtk_widget_grab_focus(state->search_entry);
        gtk_editable_select_region(GTK_EDITABLE(state->search_entry), 0, -1);
        return TRUE;
    }
    if (event->keyval == GDK_KEY_k || event->keyval == GDK_KEY_K) {
        show_favorites_dialog(state);
        return TRUE;
    }
    if (event->keyval == GDK_KEY_b || event->keyval == GDK_KEY_B) {
        add_current_favorite(state, shift);
        return TRUE;
    }
    return FALSE;
}

static void drag_data_received(GtkWidget* widget, GdkDragContext* context, gint x, gint y, GtkSelectionData* data,
                               guint info, guint time, gpointer user_data) {
    (void)widget;
    (void)x;
    (void)y;
    (void)info;
    app_state* state = (app_state*)user_data;
    gchar** uris = gtk_selection_data_get_uris(data);
    if (uris && uris[0]) {
        char* path = g_filename_from_uri(uris[0], NULL, NULL);
        if (path) {
            open_path(state, path);
            g_free(path);
        }
    }
    g_strfreev(uris);
    gtk_drag_finish(context, TRUE, FALSE, time);
}

static gboolean page_scroll_event(GtkWidget* widget, GdkEventScroll* event, gpointer user_data) {
    (void)widget;
    app_state* state = (app_state*)user_data;
    if (!state->doc) return FALSE;
    if (!state->continuous_mode || state->fit_mode_id == 3 || state->fit_mode_id == 4) {
        if (event->direction == GDK_SCROLL_DOWN || event->delta_y > 0)
            next_clicked(NULL, state);
        else if (event->direction == GDK_SCROLL_UP || event->delta_y < 0)
            previous_clicked(NULL, state);
        return TRUE;
    }
    return FALSE;
}

static gboolean page_button_press(GtkWidget* widget, GdkEventButton* event, gpointer user_data) {
    (void)widget;
    app_state* state = (app_state*)user_data;

    if (event->button == 3) {
        GtkWidget* menu = gtk_menu_new();
        GtkWidget* show_folder = gtk_menu_item_new_with_label("Show in Folder");
        gtk_widget_set_sensitive(show_folder, state->doc != NULL && state->path != NULL);
        g_signal_connect(show_folder, "activate", G_CALLBACK(show_in_folder), state);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), show_folder);
        gtk_widget_show_all(menu);
        gtk_menu_popup_at_pointer(GTK_MENU(menu), (GdkEvent*)event);
        return TRUE;
    }

    if (event->button != 2 || !state->doc) return FALSE;

    GtkAdjustment* hadj = gtk_scrolled_window_get_hadjustment(GTK_SCROLLED_WINDOW(state->scroll));
    GtkAdjustment* vadj = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(state->scroll));
    state->panning = TRUE;
    state->pan_start_x = event->x_root;
    state->pan_start_y = event->y_root;
    state->pan_start_h = gtk_adjustment_get_value(hadj);
    state->pan_start_v = gtk_adjustment_get_value(vadj);
    return TRUE;
}

static gboolean page_motion(GtkWidget* widget, GdkEventMotion* event, gpointer user_data) {
    (void)widget;
    app_state* state = (app_state*)user_data;
    if (!state->panning) return FALSE;

    GtkAdjustment* hadj = gtk_scrolled_window_get_hadjustment(GTK_SCROLLED_WINDOW(state->scroll));
    GtkAdjustment* vadj = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(state->scroll));
    gtk_adjustment_set_value(hadj, state->pan_start_h - (event->x_root - state->pan_start_x));
    gtk_adjustment_set_value(vadj, state->pan_start_v - (event->y_root - state->pan_start_y));
    return TRUE;
}

static gboolean page_button_release(GtkWidget* widget, GdkEventButton* event, gpointer user_data) {
    (void)widget;
    (void)event;
    app_state* state = (app_state*)user_data;
    state->panning = FALSE;
    return FALSE;
}

static void activate(GtkApplication* app, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    state->app = app;
    if (state->zoom <= 0.0) state->zoom = 1.0;

    state->window = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(state->window), "SumatraPDF");
    gtk_window_set_default_size(GTK_WINDOW(state->window), 1100, 780);

    GtkWidget* root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_container_add(GTK_CONTAINER(state->window), root);

    GtkWidget* menubar = gtk_menu_bar_new();
    GtkWidget* file_menu = gtk_menu_new();
    GtkWidget* file = gtk_menu_item_new_with_mnemonic("_File");
    GtkWidget* open_menu = gtk_menu_item_new_with_mnemonic("_Open...");
    state->open_in_browser = gtk_menu_item_new_with_mnemonic("Open in Default _Browser");
    state->show_in_folder = gtk_menu_item_new_with_mnemonic("Show in _Folder");
    GtkWidget* quit_menu = gtk_menu_item_new_with_mnemonic("_Quit");
    gtk_menu_item_set_submenu(GTK_MENU_ITEM(file), file_menu);
    gtk_menu_shell_append(GTK_MENU_SHELL(file_menu), open_menu);
    gtk_menu_shell_append(GTK_MENU_SHELL(file_menu), state->open_in_browser);
    gtk_menu_shell_append(GTK_MENU_SHELL(file_menu), state->show_in_folder);
    gtk_menu_shell_append(GTK_MENU_SHELL(file_menu), gtk_separator_menu_item_new());
    gtk_menu_shell_append(GTK_MENU_SHELL(file_menu), quit_menu);
    gtk_menu_shell_append(GTK_MENU_SHELL(menubar), file);
    gtk_box_pack_start(GTK_BOX(root), menubar, FALSE, FALSE, 0);

    GtkWidget* toolbar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    gtk_widget_set_margin_start(toolbar, 8);
    gtk_widget_set_margin_end(toolbar, 8);
    gtk_widget_set_margin_top(toolbar, 6);
    gtk_widget_set_margin_bottom(toolbar, 6);
    gtk_box_pack_start(GTK_BOX(root), toolbar, FALSE, FALSE, 0);

    GtkWidget* open = gtk_button_new_with_label("Open");
    GtkWidget* prev = gtk_button_new_with_label("<");
    GtkWidget* next = gtk_button_new_with_label(">");
    state->page_entry = gtk_entry_new();
    gtk_entry_set_width_chars(GTK_ENTRY(state->page_entry), 5);
    state->page_count_label = gtk_label_new("/ 0");
    GtkWidget* zoom_out = gtk_button_new_with_label("-");
    GtkWidget* zoom_in = gtk_button_new_with_label("+");
    state->fit_mode = gtk_combo_box_text_new();
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(state->fit_mode), "Custom");
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(state->fit_mode), "Actual");
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(state->fit_mode), "Fit width");
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(state->fit_mode), "Fit height");
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(state->fit_mode), "Fit page");
    gtk_combo_box_set_active(GTK_COMBO_BOX(state->fit_mode), state->fit_mode_id);
    state->continuous = gtk_check_button_new_with_label("Continuous");
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(state->continuous), state->continuous_mode);
    state->search_entry = gtk_search_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(state->search_entry), "Find");
    state->ocr_button = gtk_button_new_with_label("OCR");

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
    gtk_box_pack_start(GTK_BOX(toolbar), state->ocr_button, FALSE, FALSE, 0);

    GtkWidget* paned = gtk_paned_new(GTK_ORIENTATION_HORIZONTAL);
    gtk_box_pack_start(GTK_BOX(root), paned, TRUE, TRUE, 0);
    state->sidebar_container = gtk_notebook_new();
    state->sidebar_tabs = state->sidebar_container;
    gtk_widget_set_size_request(state->sidebar_container, 240, -1);
    state->sidebar = gtk_list_box_new();
    state->comments_sidebar = gtk_list_box_new();
    GtkWidget* chapters_scroll = gtk_scrolled_window_new(NULL, NULL);
    GtkWidget* comments_scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_container_add(GTK_CONTAINER(chapters_scroll), state->sidebar);
    gtk_container_add(GTK_CONTAINER(comments_scroll), state->comments_sidebar);
    gtk_notebook_append_page(GTK_NOTEBOOK(state->sidebar_tabs), chapters_scroll, gtk_label_new("Chapters"));
    gtk_notebook_append_page(GTK_NOTEBOOK(state->sidebar_tabs), comments_scroll, gtk_label_new("Comments"));
    gtk_paned_pack1(GTK_PANED(paned), state->sidebar_container, FALSE, FALSE);

    state->scroll = gtk_scrolled_window_new(NULL, NULL);
    GtkWidget* page_box = gtk_event_box_new();
    gtk_widget_add_events(page_box,
                          GDK_BUTTON_PRESS_MASK | GDK_BUTTON_RELEASE_MASK | GDK_POINTER_MOTION_MASK | GDK_SCROLL_MASK);
    gtk_event_box_set_visible_window(GTK_EVENT_BOX(page_box), FALSE);
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
    g_signal_connect(open_menu, "activate", G_CALLBACK(open_clicked), state);
    g_signal_connect(state->open_in_browser, "activate", G_CALLBACK(open_in_browser), state);
    g_signal_connect(state->show_in_folder, "activate", G_CALLBACK(show_in_folder), state);
    g_signal_connect_swapped(quit_menu, "activate", G_CALLBACK(g_application_quit), app);
    g_signal_connect(prev, "clicked", G_CALLBACK(previous_clicked), state);
    g_signal_connect(next, "clicked", G_CALLBACK(next_clicked), state);
    g_signal_connect(zoom_out, "clicked", G_CALLBACK(zoom_out_clicked), state);
    g_signal_connect(zoom_in, "clicked", G_CALLBACK(zoom_in_clicked), state);
    g_signal_connect(state->ocr_button, "clicked", G_CALLBACK(ocr_clicked), state);
    g_signal_connect(state->fit_mode, "changed", G_CALLBACK(fit_mode_changed), state);
    g_signal_connect(state->continuous, "toggled", G_CALLBACK(continuous_toggled), state);
    g_signal_connect(state->page_entry, "activate", G_CALLBACK(page_entry_activate), state);
    g_signal_connect(state->search_entry, "activate", G_CALLBACK(find_next), state);
    g_signal_connect(state->sidebar, "row-selected", G_CALLBACK(sidebar_row_selected), state);
    g_signal_connect(state->comments_sidebar, "row-selected", G_CALLBACK(sidebar_row_selected), state);
    g_signal_connect(page_box, "scroll-event", G_CALLBACK(page_scroll_event), state);
    g_signal_connect(page_box, "button-press-event", G_CALLBACK(page_button_press), state);
    g_signal_connect(page_box, "motion-notify-event", G_CALLBACK(page_motion), state);
    g_signal_connect(page_box, "button-release-event", G_CALLBACK(page_button_release), state);
    g_signal_connect(state->window, "key-press-event", G_CALLBACK(key_press), state);

    GtkTargetEntry drop_targets[] = {{"text/uri-list", 0, 0}};
    gtk_drag_dest_set(state->window, GTK_DEST_DEFAULT_ALL, drop_targets, 1, GDK_ACTION_COPY);
    g_signal_connect(state->window, "drag-data-received", G_CALLBACK(drag_data_received), state);

    gtk_widget_show_all(state->window);
    gtk_widget_hide(state->sidebar_container);
    update_controls(state);
    if (!state->suppress_restore_once && !state->doc && state->restore_path && *state->restore_path)
        open_path_at_page(state, state->restore_path, state->restore_page_index);
    state->suppress_restore_once = FALSE;
}

static void open_files(GtkApplication* app, GFile** files, gint n_files, const gchar* hint, gpointer user_data) {
    (void)hint;
    app_state* state = (app_state*)user_data;
    if (!state->window) {
        state->suppress_restore_once = TRUE;
        activate(app, user_data);
    }
    if (n_files > 0) {
        char* path = g_file_get_path(files[0]);
        if (path) {
            open_path(state, path);
            g_free(path);
        }
    }
}

int main(int argc, char** argv) {
    app_state state;
    int status;

    if (argc > 1 && strcmp(argv[1], "--version") == 0) {
        g_print("SumatraPDF portable gtk 0.5\n");
        return 0;
    }

    memset(&state, 0, sizeof(state));
    state.zoom = 1.0;
    state.fit_mode_id = 2;
    state.continuous_mode = TRUE;
    state.render_pool = g_thread_pool_new(render_worker, NULL, MAX(1, g_get_num_processors()), FALSE, NULL);
    init_config_paths(&state);
    load_settings(&state);
    load_session(&state);
    load_favorites(&state);
    GtkApplication* app = gtk_application_new("org.sumatrapdfreader.SumatraPDF", G_APPLICATION_HANDLES_OPEN);
    g_signal_connect(app, "activate", G_CALLBACK(activate), &state);
    g_signal_connect(app, "open", G_CALLBACK(open_files), &state);
    status = g_application_run(G_APPLICATION(app), argc, argv);

    save_settings(&state);
    save_session(&state);
    state.render_generation++;
    if (state.render_pool) g_thread_pool_free(state.render_pool, TRUE, TRUE);
    spdf_free_outline(&state.outline);
    spdf_free_comments(&state.comments);
    spdf_close(state.doc);
    free(state.path);
    g_free(state.config_dir);
    g_free(state.settings_path);
    g_free(state.session_path);
    g_free(state.favorites_path);
    g_free(state.restore_path);
    free_favorites(&state);
    g_object_unref(app);
    return status;
}
