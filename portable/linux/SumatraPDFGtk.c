#include <gtk/gtk.h>
#include <cairo-pdf.h>
#include <gio/gio.h>
#include <glib/gstdio.h>

#include "sumatra_pdf_core.h"

#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_CONFIG_JSON_BYTES (2 * 1024 * 1024)
#define MAX_SESSION_TABS 64
#define MAX_FAVORITES 4096
#define MAX_RECENT_DOCUMENTS 10
#define MAX_CLOSED_DOCUMENTS 10
#define MAX_FIND_QUERY_BYTES 2048
#define MAX_FIND_MATCHES 20000
#define MAX_TRANSLATE_TEXT_BYTES (16 * 1024 * 1024)
#define MAX_PALETTE_SEARCH_PAGES 250
#define BACKGROUND_RENDER_RADIUS 3
#define BACKGROUND_RENDER_BATCH_LIMIT 6
#define RENDERED_PAGE_EVICT_RADIUS 10
#define DEFAULT_WINDOW_WIDTH 960
#define DEFAULT_WINDOW_HEIGHT 680
#define MIN_WINDOW_WIDTH 560
#define MIN_WINDOW_HEIGHT 380
#define MAX_WINDOW_WIDTH 4096
#define MAX_WINDOW_HEIGHT 3072
#define MINIMAP_WIDTH 112
#define MINIMAP_PRECISION_DRAG_PAGE_THRESHOLD 20
#define MINIMAP_PRECISE_PAGE_LIMIT 2000

typedef struct favorite_item {
    char* path;
    char* title;
    int page_index;
    gboolean document;
} favorite_item;

typedef struct document_tab {
    char* path;
    char* title;
    int page_index;
    double zoom;
    int fit_mode_id;
    gboolean continuous_mode;
    char* search_text;
    gboolean search_regex;
    gboolean search_regex_multiline;
    int find_match_index;
} document_tab;

typedef struct find_match {
    int page_index;
    gboolean has_rect;
    spdf_rect rect;
} find_match;

typedef struct comment_edit_result {
    char* author;
    char* text;
} comment_edit_result;

typedef struct app_state {
    GtkApplication* app;
    GtkWidget* window;
    GtkWidget* open_in_browser;
    GtkWidget* show_in_folder;
    GtkWidget* recently_opened_menu;
    GtkWidget* reopen_closed_menu_item;
    GtkWidget* show_sidebar_item;
    GtkWidget* show_minimap_item;
    GtkWidget* presentation_item;
    GtkWidget* translate_menu_item;
    GtkWidget* translate_button;
    GtkWidget* ocr_button;
    GtkWidget* menubar;
    GtkWidget* tab_strip;
    GtkWidget* toolbar;
    GtkWidget* side_panel_control;
    GtkWidget* side_panel_button;
    GtkWidget* minimap_control;
    GtkWidget* minimap_button;
    GtkWidget* marker_strip_control;
    GtkWidget* marker_strip_button;
    GtkWidget* toolbar_overflow_button;
    GtkWidget* toolbar_overflow_menu;
    GtkWidget* overflow_side_panel_item;
    GtkWidget* overflow_minimap_item;
    GtkWidget* overflow_marker_strip_item;
    GtkWidget* overflow_continuous_item;
    GtkWidget* overflow_search_regex_item;
    GtkWidget* overflow_search_regex_multiline_item;
    GtkWidget* overflow_translate_item;
    GtkWidget* overflow_fit_mode_items[5];
    GtkWidget* tab_bar;
    GtkWidget* new_tab_button;
    GtkWidget* page_box;
    GtkWidget* scroll;
    GtkWidget* main_paned;
    GtkWidget* sidebar_container;
    GtkWidget* sidebar_tabs;
    GtkWidget* sidebar;
    GtkWidget* comments_sidebar;
    GtkWidget* page_entry;
    GtkWidget* page_count_label;
    GtkWidget* fit_mode;
    GtkWidget* continuous;
    GtkWidget* search_entry;
    GtkWidget* search_regex_check;
    GtkWidget* search_regex_multiline_check;
    GtkWidget* search_regex_multiline_item;
    GtkWidget* find_prev_button;
    GtkWidget* find_next_button;
    GtkWidget* find_count_label;
    GtkWidget* find_markers;
    GtkWidget* minimap;
    GtkWidget* status;

    spdf_document* doc;
    spdf_outline outline;
    spdf_comments comments;
    char* path;
    char* config_dir;
    char* settings_path;
    char* session_path;
    char* favorites_path;
    char* search_text;
    char* comment_author;
    char* translate_source_language;
    char* translate_target_language;
    char* empty_view_message;
    favorite_item* favorites;
    int favorite_count;
    int favorite_capacity;
    int favorite_pending_delete;
    char* recent_paths[MAX_RECENT_DOCUMENTS];
    int recent_count;
    char* closed_paths[MAX_CLOSED_DOCUMENTS];
    int closed_count;
    document_tab* tabs;
    int tab_count;
    int tab_capacity;
    int selected_tab;
    int restore_selected_tab;
    char* restore_path;
    char* restore_search_text;
    int restore_page_index;
    int restore_find_match_index;
    find_match* find_matches;
    int find_match_count;
    int find_match_capacity;
    int find_match_index;
    guint find_debounce_id;
    int page_index;
    int sidebar_width;
    double zoom;
    int fit_mode_id;
    gboolean continuous_mode;
    gboolean show_sidebar;
    gboolean show_minimap;
    gboolean show_find_markers;
    gboolean presentation_mode;
    gboolean presentation_prev_continuous_mode;
    gboolean presentation_prev_show_sidebar;
    gboolean search_regex;
    gboolean search_regex_multiline;
    gboolean suppress_find_changed;
    gboolean switching_tabs;
    gboolean updating_sidebar_menu;
    gboolean updating_minimap_control;
    gboolean updating_marker_strip_control;
    gboolean updating_presentation_menu;
    gboolean updating_overflow_controls;
    gboolean translate_running;
    gboolean translate_install_running;
    gboolean window_fullscreen;
    gboolean panning;
    gboolean selecting;
    gboolean minimap_dragging;
    gboolean minimap_dragging_visible_rect;
    gboolean tab_dragging;
    gboolean clamping_horizontal;
    gboolean suppress_restore_once;
    double pan_start_x;
    double pan_start_y;
    double pan_start_h;
    double pan_start_v;
    double minimap_drag_offset_top;
    double minimap_drag_thumb_top;
    double minimap_drag_last_y;
    double minimap_drag_last_time;
    double tab_drag_start_x;
    double tab_drag_start_y;
    double presentation_prev_zoom;
    int presentation_prev_fit_mode_id;
    int window_width;
    int window_height;
    GtkPolicyType presentation_prev_hpolicy;
    GtkPolicyType presentation_prev_vpolicy;
    int selection_page_index;
    double selection_start_x;
    double selection_start_y;
    spdf_rect selection_rects[256];
    int selection_rect_count;
    char* selected_text;
    int context_page_index;
    int context_comment_index;
    int tab_drag_index;
    double context_page_x;
    double context_page_y;
    GThreadPool* render_pool;
    guint document_generation;
    guint render_generation;
    gboolean render_error_shown;
    guint sidebar_metadata_idle_id;
    guint background_render_idle_id;
    guint startup_restore_idle_id;
    guint deferred_find_idle_id;
    gboolean defer_find_until_idle;
} app_state;

typedef struct render_task {
    app_state* state;
    char* path;
    GtkWidget* image;
    guint generation;
    int page_index;
    double zoom;
    int display_scale;
    char* search_text;
    gboolean search_regex;
    spdf_rect* highlight_rects;
    int highlight_rect_count;
    spdf_rect* selection_rects;
    int selection_rect_count;
    gboolean has_active_rect;
    spdf_rect active_rect;
} render_task;

typedef struct render_result {
    app_state* state;
    GtkWidget* image;
    cairo_surface_t* surface;
    char* path;
    guint generation;
    int page_index;
    gboolean missing_file;
    char err[1024];
} render_result;

typedef struct scroll_request {
    app_state* state;
    GtkWidget* widget;
    guint generation;
} scroll_request;

typedef struct scroll_position_request {
    app_state* state;
    guint generation;
    double hvalue;
    double vvalue;
} scroll_position_request;

typedef struct page_point_scroll_request {
    app_state* state;
    guint generation;
    int page_index;
    double x;
    double y;
    gboolean has_point;
    gboolean preserve_horizontal;
} page_point_scroll_request;

typedef struct horizontal_clamp_request {
    app_state* state;
    guint generation;
} horizontal_clamp_request;

typedef struct generation_request {
    app_state* state;
    guint generation;
} generation_request;

typedef struct find_request {
    app_state* state;
    guint document_generation;
    int preferred_index;
    int preferred_page;
    gboolean reveal_match;
    gboolean preserve_scroll;
} find_request;

static void render_current_page(app_state* state, gboolean scroll_to_top);
static void open_path_at_page(app_state* state, const char* path, int page_index);
static void open_path(app_state* state, const char* path);
static void remember_recent_path(app_state* state, const char* path);
static void reopen_last_closed_document(app_state* state);
static void start_find_for_current_query(app_state* state, int preferred_index, int preferred_page,
                                         gboolean reveal_match, gboolean preserve_scroll);
static void update_controls(app_state* state);
static void update_sidebar_menu_items(app_state* state);
static void update_minimap_controls(app_state* state);
static void update_presentation_menu_item(app_state* state);
static void update_find_controls(app_state* state);
static void update_toolbar_overflow_menu_state(app_state* state);
static void update_tab_strip(app_state* state);
static void save_active_tab_state(app_state* state);
static void select_tab(app_state* state, int index);
static const char* current_search_text(app_state* state);
static void set_regex_multiline_widget_active(GtkWidget* widget, gboolean active);
static void set_presentation_mode(app_state* state, gboolean enable);
static void cancel_background_render(app_state* state);
static void cancel_deferred_sidebar_load(app_state* state);
static void evict_distant_page_surfaces(app_state* state);

static int clamp_int(int value, int min_value, int max_value) {
    if (value < min_value) return min_value;
    if (value > max_value) return max_value;
    return value;
}

static double clamp_double(double value, double min_value, double max_value) {
    if (value < min_value) return min_value;
    if (value > max_value) return max_value;
    return value;
}

static double smoothstep_double(double value) {
    value = clamp_double(value, 0.0, 1.0);
    return value * value * value * (value * (value * 6.0 - 15.0) + 10.0);
}

typedef struct translation_language {
    const char* code;
    const char* name;
} translation_language;

static const translation_language k_translation_languages[] = {
    {"zh", "Chinese (Simplified)"},
    {"en", "English"},
    {"fr", "French"},
    {"de", "German"},
    {"es", "Spanish"},
    {"it", "Italian"},
    {"pt", "Portuguese"},
    {"ru", "Russian"},
    {"ja", "Japanese"},
    {"ko", "Korean"},
    {"ar", "Arabic"},
    {"hi", "Hindi"},
    {"nl", "Dutch"},
    {"pl", "Polish"},
    {"tr", "Turkish"},
    {"vi", "Vietnamese"},
    {"id", "Indonesian"},
    {"uk", "Ukrainian"},
    {"cs", "Czech"},
};

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

static char* json_read_string_value(char** cursor) {
    char* pos = *cursor;
    GString* out;

    while (*pos && isspace((unsigned char)*pos)) pos++;
    if (*pos != '"') return NULL;
    pos++;
    out = g_string_new("");
    while (*pos) {
        if (*pos == '"') {
            *cursor = pos + 1;
            return g_string_free(out, FALSE);
        }
        if (*pos == '\\' && pos[1]) {
            pos++;
            if (*pos == 'n')
                g_string_append_c(out, '\n');
            else if (*pos == 'r')
                g_string_append_c(out, '\r');
            else if (*pos == 't')
                g_string_append_c(out, '\t');
            else
                g_string_append_c(out, *pos);
        } else {
            g_string_append_c(out, *pos);
        }
        pos++;
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

static char* json_find_key(const char* json, const char* key) {
    char pattern[96];
    snprintf(pattern, sizeof(pattern), "\"%s\"", key);
    return strstr(json, pattern);
}

static char* json_find_matching(const char* start, char open, char close) {
    int depth = 0;
    gboolean in_string = FALSE;
    gboolean escaped = FALSE;

    if (!start || *start != open) return NULL;
    for (char* pos = (char*)start; *pos; ++pos) {
        if (in_string) {
            if (escaped) {
                escaped = FALSE;
            } else if (*pos == '\\') {
                escaped = TRUE;
            } else if (*pos == '"') {
                in_string = FALSE;
            }
            continue;
        }

        if (*pos == '"') {
            in_string = TRUE;
        } else if (*pos == open) {
            depth++;
        } else if (*pos == close) {
            depth--;
            if (depth == 0) return pos;
        }
    }
    return NULL;
}

static char* json_get_array_contents(const char* json, const char* key) {
    char* pos = json_find_key(json, key);
    char* start;
    char* end;
    if (!pos) return NULL;
    pos = strchr(pos + strlen(key) + 2, ':');
    if (!pos) return NULL;
    start = strchr(pos, '[');
    if (!start) return NULL;
    end = json_find_matching(start, '[', ']');
    if (!end) return NULL;
    return g_strndup(start + 1, (gsize)(end - start - 1));
}

static gboolean read_limited_text_file(const char* path, char** contents, gsize* len) {
    GStatBuf st;
    gboolean ok;

    if (contents) *contents = NULL;
    if (len) *len = 0;
    if (!path) return FALSE;
    if (g_stat(path, &st) == 0 && st.st_size > MAX_CONFIG_JSON_BYTES) return FALSE;
    ok = g_file_get_contents(path, contents, len, NULL);
    if (ok && len && *len > MAX_CONFIG_JSON_BYTES) {
        g_free(contents ? *contents : NULL);
        if (contents) *contents = NULL;
        *len = 0;
        return FALSE;
    }
    return ok;
}

static char* dup_limited_utf8(const char* text, gsize max_bytes) {
    const char* end;
    gsize len;

    if (!text) return g_strdup("");
    len = strlen(text);
    if (len <= max_bytes) return g_strdup(text);

    end = text + max_bytes;
    while (end > text && (((const unsigned char*)end)[0] & 0xc0) == 0x80) end--;
    if (end == text) end = text + max_bytes;
    return g_strndup(text, (gsize)(end - text));
}

static gboolean find_query_too_long(const char* text) {
    return text && strlen(text) > MAX_FIND_QUERY_BYTES;
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

static void remove_favorite_item(app_state* state, int index) {
    if (index < 0 || index >= state->favorite_count) return;
    g_free(state->favorites[index].path);
    g_free(state->favorites[index].title);
    if (index + 1 < state->favorite_count) {
        memmove(&state->favorites[index], &state->favorites[index + 1],
                (gsize)(state->favorite_count - index - 1) * sizeof(favorite_item));
    }
    state->favorite_count--;
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

static document_tab* active_tab(app_state* state) {
    if (!state || state->selected_tab < 0 || state->selected_tab >= state->tab_count) return NULL;
    return &state->tabs[state->selected_tab];
}

static void free_document_tab(document_tab* tab) {
    if (!tab) return;
    g_free(tab->path);
    g_free(tab->title);
    g_free(tab->search_text);
    memset(tab, 0, sizeof(*tab));
}

static void free_document_tabs(app_state* state) {
    for (int i = 0; i < state->tab_count; ++i) free_document_tab(&state->tabs[i]);
    g_free(state->tabs);
    state->tabs = NULL;
    state->tab_count = 0;
    state->tab_capacity = 0;
    state->selected_tab = -1;
}

static void free_path_list(char** paths, int* count) {
    for (int i = 0; i < *count; ++i) g_free(paths[i]);
    memset(paths, 0, sizeof(char*) * (gsize)*count);
    *count = 0;
}

static void open_recent_menu_item(GtkWidget* widget, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    const char* path = (const char*)g_object_get_data(G_OBJECT(widget), "sumatra-recent-path");
    if (path && *path) open_path(state, path);
}

static void update_recent_menu(app_state* state) {
    GList* children;

    if (!state->recently_opened_menu) return;
    children = gtk_container_get_children(GTK_CONTAINER(state->recently_opened_menu));
    for (GList* it = children; it; it = it->next) gtk_widget_destroy(GTK_WIDGET(it->data));
    g_list_free(children);

    if (state->recent_count == 0) {
        GtkWidget* empty = gtk_menu_item_new_with_label("No Recent Documents");
        gtk_widget_set_sensitive(empty, FALSE);
        gtk_menu_shell_append(GTK_MENU_SHELL(state->recently_opened_menu), empty);
    } else {
        for (int i = 0; i < state->recent_count && i < MAX_RECENT_DOCUMENTS; ++i) {
            char* name = display_name_for_path(state->recent_paths[i]);
            char* label = g_strdup_printf("%d) %s", i + 1, name && *name ? name : state->recent_paths[i]);
            GtkWidget* item = gtk_menu_item_new_with_label(label);
            gtk_widget_set_tooltip_text(item, state->recent_paths[i]);
            g_object_set_data_full(G_OBJECT(item), "sumatra-recent-path", g_strdup(state->recent_paths[i]), g_free);
            g_signal_connect(item, "activate", G_CALLBACK(open_recent_menu_item), state);
            gtk_menu_shell_append(GTK_MENU_SHELL(state->recently_opened_menu), item);
            g_free(label);
            g_free(name);
        }
    }
    gtk_widget_show_all(state->recently_opened_menu);
}

static void remember_recent_path(app_state* state, const char* path) {
    if (!state || !path || !*path) return;
    for (int i = 0; i < state->recent_count; ++i) {
        if (g_strcmp0(state->recent_paths[i], path) != 0) continue;
        g_free(state->recent_paths[i]);
        if (i + 1 < state->recent_count) {
            memmove(&state->recent_paths[i], &state->recent_paths[i + 1],
                    (gsize)(state->recent_count - i - 1) * sizeof(char*));
        }
        state->recent_count--;
        break;
    }
    if (state->recent_count == MAX_RECENT_DOCUMENTS) {
        g_free(state->recent_paths[MAX_RECENT_DOCUMENTS - 1]);
        state->recent_count--;
    }
    if (state->recent_count > 0) {
        memmove(&state->recent_paths[1], &state->recent_paths[0], (gsize)state->recent_count * sizeof(char*));
    }
    state->recent_paths[0] = g_strdup(path);
    state->recent_count++;
    update_recent_menu(state);
}

static void remember_closed_path(app_state* state, const char* path) {
    if (!state || !path || !*path) return;
    if (state->closed_count == MAX_CLOSED_DOCUMENTS) {
        g_free(state->closed_paths[0]);
        memmove(&state->closed_paths[0], &state->closed_paths[1], (MAX_CLOSED_DOCUMENTS - 1) * sizeof(char*));
        state->closed_count--;
    }
    state->closed_paths[state->closed_count++] = g_strdup(path);
    if (state->reopen_closed_menu_item) gtk_widget_set_sensitive(state->reopen_closed_menu_item, TRUE);
}

static char* pop_closed_path(app_state* state) {
    char* path;

    if (!state || state->closed_count == 0) return NULL;
    path = state->closed_paths[state->closed_count - 1];
    state->closed_paths[state->closed_count - 1] = NULL;
    state->closed_count--;
    if (state->reopen_closed_menu_item)
        gtk_widget_set_sensitive(state->reopen_closed_menu_item, state->closed_count > 0);
    return path;
}

static void reopen_last_closed_document(app_state* state) {
    char* path = pop_closed_path(state);
    if (!path) return;
    open_path(state, path);
    g_free(path);
}

static int append_document_tab(app_state* state, const char* path, const char* title, int page_index, double zoom,
                               int fit_mode_id, gboolean continuous_mode, const char* search_text,
                               gboolean search_regex, gboolean search_regex_multiline, int find_match_index) {
    if (state->tab_count == state->tab_capacity) {
        int capacity = state->tab_capacity ? state->tab_capacity * 2 : 4;
        state->tabs = g_realloc(state->tabs, (gsize)capacity * sizeof(document_tab));
        memset(&state->tabs[state->tab_capacity], 0, (gsize)(capacity - state->tab_capacity) * sizeof(document_tab));
        state->tab_capacity = capacity;
    }

    document_tab* tab = &state->tabs[state->tab_count];
    tab->path = g_strdup(path ? path : "");
    tab->title = title && *title ? g_strdup(title) : display_name_for_path(path ? path : "");
    tab->page_index = MAX(0, page_index);
    tab->zoom = zoom > 0.0 ? zoom : 1.0;
    tab->fit_mode_id = fit_mode_id >= 0 && fit_mode_id <= 4 ? fit_mode_id : 2;
    tab->continuous_mode = continuous_mode;
    tab->search_text = dup_limited_utf8(search_text ? search_text : "", MAX_FIND_QUERY_BYTES);
    tab->search_regex = search_regex;
    tab->search_regex_multiline = search_regex_multiline;
    tab->find_match_index = find_match_index;
    return state->tab_count++;
}

static void set_tab_title(document_tab* tab, const char* title, const char* path) {
    char* fallback;
    if (!tab) return;
    fallback = display_name_for_path(path ? path : tab->path);
    g_free(tab->title);
    tab->title = title && *title ? display_label_without_extension(title) : fallback;
    if (title && *title) g_free(fallback);
}

static int find_tab_by_path(app_state* state, const char* path) {
    char* canonical_path;
    int result = -1;

    if (!path || !*path) return -1;
    canonical_path = g_canonicalize_filename(path, NULL);
    for (int i = 0; i < state->tab_count; ++i) {
        char* tab_path = state->tabs[i].path ? g_canonicalize_filename(state->tabs[i].path, NULL) : NULL;
        if (tab_path && strcmp(canonical_path, tab_path) == 0) {
            result = i;
            g_free(tab_path);
            break;
        }
        g_free(tab_path);
    }
    g_free(canonical_path);
    return result;
}

static void save_active_tab_state(app_state* state) {
    document_tab* tab = active_tab(state);
    if (!tab) return;

    if (state->path) {
        g_free(tab->path);
        tab->path = g_strdup(state->path);
    }
    if (state->doc) {
        set_tab_title(tab, spdf_title(state->doc), state->path);
    } else if (state->path && *state->path && (!tab->title || !*tab->title)) {
        set_tab_title(tab, NULL, state->path);
    }
    tab->page_index = state->doc ? state->page_index : tab->page_index;
    tab->zoom = state->presentation_mode ? state->presentation_prev_zoom : state->zoom;
    tab->fit_mode_id = state->presentation_mode ? state->presentation_prev_fit_mode_id : state->fit_mode_id;
    tab->continuous_mode = state->presentation_mode ? state->presentation_prev_continuous_mode : state->continuous_mode;
    g_free(tab->search_text);
    tab->search_text = g_strdup(current_search_text(state));
    tab->search_regex = state->search_regex;
    tab->search_regex_multiline = state->search_regex_multiline;
    tab->find_match_index = state->find_match_index;
}

static void save_settings(app_state* state) {
    char* author = json_escape(state->comment_author ? state->comment_author : "");
    char* translate_source = json_escape(state->translate_source_language ? state->translate_source_language : "zh");
    char* translate_target = json_escape(state->translate_target_language ? state->translate_target_language : "en");
    GString* json = g_string_new("{\n");
    g_string_append_printf(json, "  \"fitMode\": %d,\n",
                           state->presentation_mode ? state->presentation_prev_fit_mode_id : state->fit_mode_id);
    g_string_append_printf(json, "  \"zoom\": %.4f,\n",
                           state->presentation_mode ? state->presentation_prev_zoom : state->zoom);
    g_string_append_printf(
        json, "  \"continuous\": %s,\n",
        (state->presentation_mode ? state->presentation_prev_continuous_mode : state->continuous_mode) ? "true"
                                                                                                       : "false");
    g_string_append_printf(
        json, "  \"showSidebar\": %s,\n",
        (state->presentation_mode ? state->presentation_prev_show_sidebar : state->show_sidebar) ? "true" : "false");
    g_string_append_printf(json, "  \"showMinimap\": %s,\n", state->show_minimap ? "true" : "false");
    g_string_append_printf(json, "  \"showFindMarkers\": %s,\n", state->show_find_markers ? "true" : "false");
    g_string_append_printf(json, "  \"sidebarWidth\": %d,\n", state->sidebar_width);
    g_string_append_printf(json, "  \"windowWidth\": %d,\n",
                           clamp_int(state->window_width > 0 ? state->window_width : DEFAULT_WINDOW_WIDTH,
                                     MIN_WINDOW_WIDTH, MAX_WINDOW_WIDTH));
    g_string_append_printf(json, "  \"windowHeight\": %d,\n",
                           clamp_int(state->window_height > 0 ? state->window_height : DEFAULT_WINDOW_HEIGHT,
                                     MIN_WINDOW_HEIGHT, MAX_WINDOW_HEIGHT));
    g_string_append_printf(json, "  \"commentAuthor\": \"%s\",\n", author);
    g_string_append_printf(json, "  \"translateSourceLanguage\": \"%s\",\n", translate_source);
    g_string_append_printf(json, "  \"translateTargetLanguage\": \"%s\",\n", translate_target);
    g_string_append(json, "  \"recentlyOpened\": [\n");
    for (int i = 0; i < state->recent_count; ++i) {
        char* path = json_escape(state->recent_paths[i] ? state->recent_paths[i] : "");
        g_string_append_printf(json, "    \"%s\"%s\n", path, i + 1 == state->recent_count ? "" : ",");
        g_free(path);
    }
    g_string_append(json, "  ]\n");
    g_string_append(json, "}\n");
    write_text_file(state->settings_path, json->str);
    g_string_free(json, TRUE);
    g_free(translate_target);
    g_free(translate_source);
    g_free(author);
}

static const char* current_search_text(app_state* state) {
    if (state->search_text) return state->search_text;
    return state->restore_search_text ? state->restore_search_text : "";
}

static void save_session(app_state* state) {
    save_active_tab_state(state);

    GString* json = g_string_new("{\n");
    g_string_append_printf(json, "  \"selectedTab\": %d,\n", state->selected_tab);
    g_string_append(json, "  \"tabs\": [\n");
    for (int i = 0; i < state->tab_count; ++i) {
        document_tab* tab = &state->tabs[i];
        char* path = json_escape(tab->path ? tab->path : "");
        char* title = json_escape(tab->title ? tab->title : "");
        char* search = json_escape(tab->search_text ? tab->search_text : "");
        g_string_append_printf(json,
                               "    { \"path\": \"%s\", \"title\": \"%s\", \"page\": %d, \"zoom\": %.4f, "
                               "\"fitMode\": %d, \"continuous\": %s, \"searchText\": \"%s\", "
                               "\"searchRegex\": %s, \"searchRegexMultiline\": %s, \"findMatchIndex\": %d }%s\n",
                               path, title, tab->page_index + 1, tab->zoom, tab->fit_mode_id,
                               tab->continuous_mode ? "true" : "false", search, tab->search_regex ? "true" : "false",
                               tab->search_regex_multiline ? "true" : "false", tab->find_match_index,
                               i + 1 == state->tab_count ? "" : ",");
        g_free(search);
        g_free(title);
        g_free(path);
    }
    g_string_append(json, "  ]\n");
    g_string_append(json, "}\n");
    write_text_file(state->session_path, json->str);
    g_string_free(json, TRUE);
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
    char* comment_author;
    char* translate_source;
    char* translate_target;
    char* recent_array;
    gsize len = 0;
    if (!read_limited_text_file(state->settings_path, &json, &len)) return;
    state->fit_mode_id = json_get_int(json, "fitMode", state->fit_mode_id);
    if (state->fit_mode_id < 0 || state->fit_mode_id > 4) state->fit_mode_id = 2;
    state->zoom = json_get_double(json, "zoom", state->zoom);
    state->zoom = MAX(0.10, MIN(8.0, state->zoom));
    state->continuous_mode = json_get_bool(json, "continuous", state->continuous_mode);
    state->show_sidebar = json_get_bool(json, "showSidebar", state->show_sidebar);
    state->show_minimap = json_get_bool(json, "showMinimap", state->show_minimap);
    state->show_find_markers = json_get_bool(json, "showFindMarkers", state->show_find_markers);
    state->sidebar_width = MAX(140, MIN(560, json_get_int(json, "sidebarWidth", state->sidebar_width)));
    state->window_width =
        clamp_int(json_get_int(json, "windowWidth", state->window_width), MIN_WINDOW_WIDTH, MAX_WINDOW_WIDTH);
    state->window_height =
        clamp_int(json_get_int(json, "windowHeight", state->window_height), MIN_WINDOW_HEIGHT, MAX_WINDOW_HEIGHT);
    comment_author = json_get_string(json, "commentAuthor");
    if (comment_author) {
        g_strstrip(comment_author);
        g_free(state->comment_author);
        state->comment_author = comment_author;
    }
    translate_source = json_get_string(json, "translateSourceLanguage");
    if (translate_source) {
        g_strstrip(translate_source);
        if (*translate_source) {
            g_free(state->translate_source_language);
            state->translate_source_language = translate_source;
        } else {
            g_free(translate_source);
        }
    }
    translate_target = json_get_string(json, "translateTargetLanguage");
    if (translate_target) {
        g_strstrip(translate_target);
        if (*translate_target) {
            g_free(state->translate_target_language);
            state->translate_target_language = translate_target;
        } else {
            g_free(translate_target);
        }
    }
    recent_array = json_get_array_contents(json, "recentlyOpened");
    if (recent_array) {
        char* pos = recent_array;
        while (*pos && state->recent_count < MAX_RECENT_DOCUMENTS) {
            char* path;
            while (*pos && *pos != '"') pos++;
            if (!*pos) break;
            path = json_read_string_value(&pos);
            if (path && *path) {
                gboolean exists = FALSE;
                for (int i = 0; i < state->recent_count; ++i) {
                    if (g_strcmp0(state->recent_paths[i], path) == 0) exists = TRUE;
                }
                if (!exists) state->recent_paths[state->recent_count++] = g_strdup(path);
            }
            g_free(path);
        }
        g_free(recent_array);
    }
    g_free(json);
}

static void load_session(app_state* state) {
    char* json = NULL;
    gsize len = 0;
    if (!read_limited_text_file(state->session_path, &json, &len)) return;

    char* tabs = json_get_array_contents(json, "tabs");
    if (tabs) {
        char* pos = tabs;
        state->restore_selected_tab = json_get_int(json, "selectedTab", 0);
        while ((pos = strchr(pos, '{')) != NULL && state->tab_count < MAX_SESSION_TABS) {
            char* end = json_find_matching(pos, '{', '}');
            char* object;
            char* path;
            char* title;
            char* search_text;
            int page_index;
            double zoom;
            int fit_mode_id;
            gboolean continuous_mode;
            gboolean search_regex;
            gboolean search_regex_multiline;
            int find_match_index;
            if (!end) break;
            object = g_strndup(pos, (gsize)(end - pos + 1));
            path = json_get_string(object, "path");
            title = json_get_string(object, "title");
            search_text = json_get_string(object, "searchText");
            page_index = MAX(0, json_get_int(object, "page", 1) - 1);
            zoom = json_get_double(object, "zoom", state->zoom);
            fit_mode_id = json_get_int(object, "fitMode", state->fit_mode_id);
            continuous_mode = json_get_bool(object, "continuous", state->continuous_mode);
            search_regex = json_get_bool(object, "searchRegex", state->search_regex);
            search_regex_multiline = json_get_bool(object, "searchRegexMultiline", state->search_regex_multiline);
            find_match_index = json_get_int(object, "findMatchIndex", -1);
            if (path && *path)
                append_document_tab(state, path, title, page_index, zoom, fit_mode_id, continuous_mode, search_text,
                                    search_regex, search_regex_multiline, find_match_index);
            g_free(search_text);
            g_free(title);
            g_free(path);
            g_free(object);
            pos = end + 1;
        }
        g_free(tabs);
        g_free(json);
        return;
    }

    g_free(state->restore_path);
    g_free(state->restore_search_text);
    state->restore_path = json_get_string(json, "path");
    state->restore_search_text = json_get_string(json, "searchText");
    state->search_regex = json_get_bool(json, "searchRegex", state->search_regex);
    state->search_regex_multiline = json_get_bool(json, "searchRegexMultiline", state->search_regex_multiline);
    state->restore_page_index = MAX(0, json_get_int(json, "page", 1) - 1);
    state->restore_find_match_index = json_get_int(json, "findMatchIndex", -1);
    if (state->restore_path && *state->restore_path) {
        append_document_tab(state, state->restore_path, NULL, state->restore_page_index, state->zoom,
                            state->fit_mode_id, state->continuous_mode, state->restore_search_text, state->search_regex,
                            state->search_regex_multiline, state->restore_find_match_index);
        state->restore_selected_tab = 0;
    }
    g_free(json);
}

static void load_favorites(app_state* state) {
    char* json = NULL;
    char* pos;
    gsize len = 0;
    if (!read_limited_text_file(state->favorites_path, &json, &len)) return;
    pos = json;
    while ((pos = strstr(pos, "\"path\"")) != NULL && state->favorite_count < MAX_FAVORITES) {
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

static int display_scale_for_state(app_state* state) {
    int scale = state && state->window ? gtk_widget_get_scale_factor(state->window) : 1;
    return MAX(1, scale);
}

static gboolean path_has_pdf_extension(const char* path) {
    const char* dot = path ? strrchr(path, '.') : NULL;
    return dot && g_ascii_strcasecmp(dot, ".pdf") == 0;
}

static void clear_empty_view_message(app_state* state) {
    g_free(state->empty_view_message);
    state->empty_view_message = NULL;
}

static gboolean clear_text_selection(app_state* state) {
    gboolean had_selection =
        state->selected_text != NULL || state->selection_rect_count > 0 || state->selection_page_index >= 0;
    g_free(state->selected_text);
    state->selected_text = NULL;
    state->selection_page_index = -1;
    state->selection_rect_count = 0;
    state->selecting = FALSE;
    return had_selection;
}

static gboolean has_text_selection(app_state* state) {
    return state && state->selected_text && state->selected_text[0] != '\0' && state->selection_page_index >= 0 &&
           state->selection_rect_count > 0;
}

static spdf_rect* copy_selection_rects_for_page(app_state* state, int page_index, int* count_out) {
    spdf_rect* rects;
    int count;

    if (count_out) *count_out = 0;
    if (!state || state->selection_page_index != page_index || state->selection_rect_count <= 0) return NULL;

    count = MIN(state->selection_rect_count, (int)(sizeof(state->selection_rects) / sizeof(state->selection_rects[0])));
    rects = g_new(spdf_rect, count);
    memcpy(rects, state->selection_rects, (gsize)count * sizeof(spdf_rect));
    if (count_out) *count_out = count;
    return rects;
}

static gboolean widget_page_index(GtkWidget* widget, int* page_index) {
    int stored = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "page-index"));
    if (stored <= 0) return FALSE;
    if (page_index) *page_index = stored - 1;
    return TRUE;
}

static GtkWidget* page_widget_for_index(app_state* state, int page_index) {
    GtkWidget* result = NULL;
    GList* children;

    if (!state || !state->page_box) return NULL;
    children = gtk_container_get_children(GTK_CONTAINER(state->page_box));
    for (GList* it = children; it; it = it->next) {
        int child_page = -1;
        if (widget_page_index(GTK_WIDGET(it->data), &child_page) && child_page == page_index) {
            result = GTK_WIDGET(it->data);
            break;
        }
    }
    g_list_free(children);
    return result;
}

static gboolean page_widget_geometry(app_state* state, int page_index, double* x, double* y, double* width,
                                     double* height) {
    GtkWidget* page_widget = page_widget_for_index(state, page_index);
    GtkWidget* parent;
    GtkAllocation allocation;
    gint origin_x = 0;
    gint origin_y = 0;

    if (!page_widget || !state->page_box) return FALSE;
    parent = gtk_widget_get_parent(state->page_box);
    if (parent) gtk_widget_translate_coordinates(state->page_box, parent, 0, 0, &origin_x, &origin_y);
    gtk_widget_get_allocation(page_widget, &allocation);
    if (x) *x = (double)origin_x + allocation.x;
    if (y) *y = (double)origin_y + allocation.y;
    if (width) *width = allocation.width;
    if (height) *height = allocation.height;
    return allocation.width > 0 && allocation.height > 0;
}

static gboolean clamp_page_point(app_state* state, int page_index, double* x, double* y) {
    char err[256];
    float page_width = 0;
    float page_height = 0;

    if (!state || !state->doc) return FALSE;
    if (!spdf_page_size(state->doc, page_index, &page_width, &page_height, err, sizeof(err))) return FALSE;
    if (page_width <= 0 || page_height <= 0) return FALSE;
    if (x) *x = MAX(0.0, MIN(*x, (double)page_width));
    if (y) *y = MAX(0.0, MIN(*y, (double)page_height));
    return TRUE;
}

static gboolean page_point_from_widget_point(app_state* state, GtkWidget* widget, double widget_x, double widget_y,
                                             int* page_index, double* page_x, double* page_y) {
    gint box_x;
    gint box_y;
    GList* children;

    if (!state || !state->doc || !state->page_box) return FALSE;
    if (!gtk_widget_translate_coordinates(widget, state->page_box, (gint)widget_x, (gint)widget_y, &box_x, &box_y))
        return FALSE;

    children = gtk_container_get_children(GTK_CONTAINER(state->page_box));
    for (GList* it = children; it; it = it->next) {
        GtkWidget* child = GTK_WIDGET(it->data);
        GtkAllocation allocation;
        int child_page = -1;
        double x;
        double y;

        if (!widget_page_index(child, &child_page)) continue;
        gtk_widget_get_allocation(child, &allocation);
        if (box_x < allocation.x || box_x > allocation.x + allocation.width || box_y < allocation.y ||
            box_y > allocation.y + allocation.height)
            continue;

        x = ((double)box_x - allocation.x) / MAX(0.001, state->zoom);
        y = ((double)box_y - allocation.y) / MAX(0.001, state->zoom);
        clamp_page_point(state, child_page, &x, &y);
        if (page_index) *page_index = child_page;
        if (page_x) *page_x = x;
        if (page_y) *page_y = y;
        g_list_free(children);
        return TRUE;
    }
    g_list_free(children);
    return FALSE;
}

static gboolean page_point_for_page_from_widget_point(app_state* state, int page_index, GtkWidget* widget,
                                                      double widget_x, double widget_y, double* page_x,
                                                      double* page_y) {
    GtkWidget* page_widget;
    GtkAllocation allocation;
    gint box_x;
    gint box_y;
    double x;
    double y;

    if (!state || !state->doc || !state->page_box) return FALSE;
    page_widget = page_widget_for_index(state, page_index);
    if (!page_widget) return FALSE;
    if (!gtk_widget_translate_coordinates(widget, state->page_box, (gint)widget_x, (gint)widget_y, &box_x, &box_y))
        return FALSE;

    gtk_widget_get_allocation(page_widget, &allocation);
    x = ((double)box_x - allocation.x) / MAX(0.001, state->zoom);
    y = ((double)box_y - allocation.y) / MAX(0.001, state->zoom);
    clamp_page_point(state, page_index, &x, &y);
    if (page_x) *page_x = x;
    if (page_y) *page_y = y;
    return TRUE;
}

static void clamp_horizontal_scroll(app_state* state) {
    GtkAdjustment* hadj;
    GtkPolicyType hpolicy;
    GtkPolicyType vpolicy;
    double page_x = 0;
    double page_width = 0;
    double lower;
    double max_value;
    double viewport_width;
    double value;
    double target;
    GtkPolicyType desired_policy;

    if (!state || !state->scroll || state->clamping_horizontal) return;

    hadj = gtk_scrolled_window_get_hadjustment(GTK_SCROLLED_WINDOW(state->scroll));
    if (!hadj) return;

    if (state->presentation_mode) {
        gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(state->scroll), GTK_POLICY_NEVER, GTK_POLICY_NEVER);
        return;
    }

    if (!state->doc || !page_widget_geometry(state, state->page_index, &page_x, NULL, &page_width, NULL)) {
        gtk_scrolled_window_get_policy(GTK_SCROLLED_WINDOW(state->scroll), &hpolicy, &vpolicy);
        if (hpolicy != GTK_POLICY_AUTOMATIC)
            gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(state->scroll), GTK_POLICY_AUTOMATIC, vpolicy);
        return;
    }

    lower = gtk_adjustment_get_lower(hadj);
    viewport_width = gtk_adjustment_get_page_size(hadj);
    max_value = MAX(lower, gtk_adjustment_get_upper(hadj) - viewport_width);
    value = gtk_adjustment_get_value(hadj);
    target = value;

    if (viewport_width <= 1.0 || page_width <= 1.0) return;

    desired_policy = page_width <= viewport_width + 0.5 ? GTK_POLICY_NEVER : GTK_POLICY_AUTOMATIC;
    gtk_scrolled_window_get_policy(GTK_SCROLLED_WINDOW(state->scroll), &hpolicy, &vpolicy);
    if (hpolicy != desired_policy)
        gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(state->scroll), desired_policy, vpolicy);

    if (page_width <= viewport_width + 0.5) {
        target = page_x + page_width * 0.5 - viewport_width * 0.5;
    } else {
        double page_min = page_x;
        double page_max = page_x + page_width - viewport_width;
        target = MAX(page_min, MIN(value, page_max));
    }
    target = MAX(lower, MIN(target, max_value));

    if (fabs(value - target) > 0.5) {
        state->clamping_horizontal = TRUE;
        gtk_adjustment_set_value(hadj, target);
        state->clamping_horizontal = FALSE;
    }
}

static gboolean clamp_horizontal_idle(gpointer data) {
    horizontal_clamp_request* request = (horizontal_clamp_request*)data;
    if (request->generation == request->state->render_generation) clamp_horizontal_scroll(request->state);
    g_free(request);
    return G_SOURCE_REMOVE;
}

static void schedule_horizontal_clamp(app_state* state) {
    horizontal_clamp_request* request;
    if (!state || !state->scroll) return;
    request = g_new0(horizontal_clamp_request, 1);
    request->state = state;
    request->generation = state->render_generation;
    g_idle_add(clamp_horizontal_idle, request);
}

static void horizontal_scroll_changed(GtkAdjustment* adjustment, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    (void)adjustment;
    clamp_horizontal_scroll(state);
    if (state->minimap) gtk_widget_queue_draw(state->minimap);
}

static void update_controls(app_state* state) {
    int page_count = state->doc ? spdf_page_count(state->doc) : 0;
    char text[128];

    gtk_widget_set_sensitive(state->page_entry, state->doc != NULL);
    gtk_widget_set_sensitive(state->search_entry, state->doc != NULL);
    if (state->search_regex_check) gtk_widget_set_sensitive(state->search_regex_check, state->doc != NULL);
    if (state->search_regex_multiline_check)
        gtk_widget_set_sensitive(state->search_regex_multiline_check, state->doc != NULL && state->search_regex);
    if (state->search_regex_multiline_item)
        gtk_widget_set_sensitive(state->search_regex_multiline_item, state->doc != NULL);
    gtk_widget_set_sensitive(state->fit_mode, state->doc != NULL);
    gtk_widget_set_sensitive(state->continuous, state->doc != NULL);
    if (state->reopen_closed_menu_item)
        gtk_widget_set_sensitive(state->reopen_closed_menu_item, state->closed_count > 0);
    if (state->open_in_browser) gtk_widget_set_sensitive(state->open_in_browser, state->doc != NULL);
    if (state->show_in_folder)
        gtk_widget_set_sensitive(state->show_in_folder, state->doc != NULL && state->path != NULL);
    if (state->translate_menu_item)
        gtk_widget_set_sensitive(state->translate_menu_item,
                                 state->doc != NULL && path_has_pdf_extension(state->path) &&
                                     !state->translate_running && !state->translate_install_running);
    if (state->translate_button)
        gtk_widget_set_sensitive(state->translate_button, state->doc != NULL && path_has_pdf_extension(state->path) &&
                                                              !state->translate_running &&
                                                              !state->translate_install_running);
    if (state->ocr_button)
        gtk_widget_set_sensitive(state->ocr_button, state->doc != NULL && path_has_pdf_extension(state->path));
    update_find_controls(state);
    update_sidebar_menu_items(state);
    update_minimap_controls(state);
    update_presentation_menu_item(state);

    if (!state->doc) {
        gtk_entry_set_text(GTK_ENTRY(state->page_entry), "");
        gtk_label_set_text(GTK_LABEL(state->page_count_label), "/ 0");
        gtk_label_set_text(GTK_LABEL(state->status), state->empty_view_message ? state->empty_view_message : "Ready");
        clamp_horizontal_scroll(state);
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
    schedule_horizontal_clamp(state);
}

static void clear_find_results(app_state* state) {
    g_free(state->find_matches);
    state->find_matches = NULL;
    state->find_match_count = 0;
    state->find_match_capacity = 0;
    state->find_match_index = -1;
    if (state->find_markers) gtk_widget_queue_draw(state->find_markers);
    if (state->minimap) gtk_widget_queue_draw(state->minimap);
}

static gboolean append_find_match(app_state* state, int page_index, spdf_rect rect, gboolean has_rect) {
    if (state->find_match_count == state->find_match_capacity) {
        int capacity = state->find_match_capacity ? state->find_match_capacity * 2 : 64;
        find_match* matches = g_realloc(state->find_matches, (gsize)capacity * sizeof(find_match));
        if (!matches) return FALSE;
        state->find_matches = matches;
        state->find_match_capacity = capacity;
    }
    state->find_matches[state->find_match_count].page_index = page_index;
    state->find_matches[state->find_match_count].has_rect = has_rect;
    state->find_matches[state->find_match_count].rect = rect;
    state->find_match_count++;
    return TRUE;
}

static gboolean active_find_rect_for_page(app_state* state, int page_index, spdf_rect* rect) {
    if (!state || state->find_match_index < 0 || state->find_match_index >= state->find_match_count) return FALSE;
    find_match* match = &state->find_matches[state->find_match_index];
    if (match->page_index != page_index) return FALSE;
    if (!match->has_rect) return FALSE;
    if (rect) *rect = match->rect;
    return TRUE;
}

static void update_find_controls(app_state* state) {
    char text[64];
    gboolean has_query = state->doc && current_search_text(state)[0] != '\0';
    gboolean has_matches = has_query && state->find_match_count > 0;

    if (state->find_markers) {
        gtk_widget_set_visible(state->find_markers, state->doc && state->find_match_count > 0 &&
                                                        state->show_find_markers && !state->presentation_mode);
        gtk_widget_queue_draw(state->find_markers);
    }
    if (state->minimap) gtk_widget_queue_draw(state->minimap);
    if (state->marker_strip_button && !state->updating_marker_strip_control) {
        state->updating_marker_strip_control = TRUE;
        gtk_switch_set_active(GTK_SWITCH(state->marker_strip_button), state->show_find_markers);
        gtk_widget_set_sensitive(state->marker_strip_control ? state->marker_strip_control : state->marker_strip_button,
                                 state->doc && state->find_match_count > 0 && !state->presentation_mode);
        state->updating_marker_strip_control = FALSE;
    }
    update_toolbar_overflow_menu_state(state);

    if (state->find_prev_button) {
        gtk_widget_set_visible(state->find_prev_button, has_query);
        gtk_widget_set_sensitive(state->find_prev_button, has_matches);
    }
    if (state->find_next_button) {
        gtk_widget_set_visible(state->find_next_button, has_query);
        gtk_widget_set_sensitive(state->find_next_button, has_matches);
    }
    if (!state->find_count_label) return;
    gtk_widget_set_visible(state->find_count_label, has_query);

    if (!has_query) {
        gtk_label_set_text(GTK_LABEL(state->find_count_label), "");
    } else if (!has_matches) {
        gtk_label_set_text(GTK_LABEL(state->find_count_label), "0 / 0");
    } else {
        snprintf(text, sizeof(text), "%d / %d", state->find_match_index + 1, state->find_match_count);
        gtk_label_set_text(GTK_LABEL(state->find_count_label), text);
    }
}

static void set_search_entry_text(app_state* state, const char* text) {
    g_free(state->search_text);
    state->search_text = dup_limited_utf8(text ? text : "", MAX_FIND_QUERY_BYTES);
    if (!state->search_entry) return;
    state->suppress_find_changed = TRUE;
    gtk_entry_set_text(GTK_ENTRY(state->search_entry), state->search_text);
    state->suppress_find_changed = FALSE;
}

static void clear_list_box(GtkWidget* list) {
    if (!list) return;
    GList* children = gtk_container_get_children(GTK_CONTAINER(list));
    for (GList* it = children; it; it = it->next) gtk_widget_destroy(GTK_WIDGET(it->data));
    g_list_free(children);
}

static GtkWidget* add_sidebar_row(GtkWidget* list, const char* text, int page_index, int indent) {
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
    return row;
}

static void rebuild_sidebar(app_state* state) {
    int requested_page = 0;
    if (!state || !state->sidebar_container || !state->sidebar_tabs || !state->sidebar || !state->comments_sidebar) {
        update_sidebar_menu_items(state);
        return;
    }
    clear_list_box(state->sidebar);
    clear_list_box(state->comments_sidebar);

    if (state->presentation_mode || !state->show_sidebar || !state->doc ||
        (state->outline.count == 0 && state->comments.count == 0)) {
        if (state->sidebar_container) gtk_widget_hide(state->sidebar_container);
        update_sidebar_menu_items(state);
        return;
    }

    if (state->sidebar_tabs) requested_page = gtk_notebook_get_current_page(GTK_NOTEBOOK(state->sidebar_tabs));

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
        GtkWidget* row = add_sidebar_row(state->comments_sidebar, text, item.page_index, 0);
        if (item.index >= 0) g_object_set_data(G_OBJECT(row), "comment-index", GINT_TO_POINTER(item.index + 1));
    }

    gtk_notebook_set_show_tabs(GTK_NOTEBOOK(state->sidebar_tabs),
                               state->outline.count > 0 && state->comments.count > 0);
    if (state->outline.count == 0)
        requested_page = 1;
    else if (state->comments.count == 0 || requested_page < 0)
        requested_page = 0;
    gtk_notebook_set_current_page(GTK_NOTEBOOK(state->sidebar_tabs), requested_page);
    gtk_widget_show_all(state->sidebar_container);
    update_sidebar_menu_items(state);
}

static void update_sidebar_menu_items(app_state* state) {
    gboolean has_panel;
    gboolean sidebar_visible;

    if (!state) return;
    has_panel = state->doc && (state->outline.count > 0 || state->comments.count > 0);
    sidebar_visible = state->sidebar_container && gtk_widget_get_visible(state->sidebar_container);
    if (state->updating_sidebar_menu) return;
    state->updating_sidebar_menu = TRUE;
    if (state->show_sidebar_item) {
        gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(state->show_sidebar_item), sidebar_visible);
        gtk_menu_item_set_label(GTK_MENU_ITEM(state->show_sidebar_item),
                                sidebar_visible ? "Hide Side _Panel" : "Show Side _Panel");
        gtk_widget_set_sensitive(state->show_sidebar_item, has_panel && !state->presentation_mode);
    }
    if (state->side_panel_button) {
        gtk_switch_set_active(GTK_SWITCH(state->side_panel_button), sidebar_visible);
        gtk_widget_set_sensitive(state->side_panel_control ? state->side_panel_control : state->side_panel_button,
                                 has_panel && !state->presentation_mode);
    }
    state->updating_sidebar_menu = FALSE;
    update_toolbar_overflow_menu_state(state);
}

static void update_minimap_controls(app_state* state) {
    gboolean visible;

    if (!state) return;
    visible = state->doc && state->show_minimap && !state->presentation_mode;
    if (state->minimap) {
        gtk_widget_set_visible(state->minimap, visible);
        gtk_widget_queue_draw(state->minimap);
    }
    if (state->updating_minimap_control) return;
    state->updating_minimap_control = TRUE;
    if (state->show_minimap_item) {
        gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(state->show_minimap_item), visible);
        gtk_menu_item_set_label(GTK_MENU_ITEM(state->show_minimap_item), visible ? "Hide _Minimap" : "Show _Minimap");
        gtk_widget_set_sensitive(state->show_minimap_item, state->doc && !state->presentation_mode);
    }
    if (state->minimap_button) {
        gtk_switch_set_active(GTK_SWITCH(state->minimap_button), state->show_minimap);
        gtk_widget_set_sensitive(state->minimap_control ? state->minimap_control : state->minimap_button,
                                 state->doc && !state->presentation_mode);
    }
    state->updating_minimap_control = FALSE;
    update_toolbar_overflow_menu_state(state);
}

static void update_presentation_menu_item(app_state* state) {
    if (!state->presentation_item || state->updating_presentation_menu) return;
    state->updating_presentation_menu = TRUE;
    gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(state->presentation_item), state->presentation_mode);
    gtk_menu_item_set_label(GTK_MENU_ITEM(state->presentation_item),
                            state->presentation_mode ? "Exit Presentation Mode" : "Presentation Mode");
    gtk_widget_set_sensitive(state->presentation_item, state->doc != NULL);
    state->updating_presentation_menu = FALSE;
}

static spdf_rect* copy_find_rects_for_page(app_state* state, int page_index, int* count_out) {
    spdf_rect* rects;
    int count = 0;

    if (count_out) *count_out = 0;
    if (!state || !state->find_matches) return NULL;

    for (int i = 0; i < state->find_match_count; ++i) {
        if (state->find_matches[i].page_index == page_index && state->find_matches[i].has_rect) count++;
    }
    if (count <= 0) return NULL;

    rects = g_new(spdf_rect, count);
    count = 0;
    for (int i = 0; i < state->find_match_count; ++i) {
        if (state->find_matches[i].page_index == page_index && state->find_matches[i].has_rect)
            rects[count++] = state->find_matches[i].rect;
    }
    if (count_out) *count_out = count;
    return rects;
}

static void draw_find_highlight(cairo_t* cr, const spdf_rect* rect, double zoom) {
    double x = rect->x0 * zoom;
    double y = rect->y0 * zoom;
    double w = (rect->x1 - rect->x0) * zoom;
    double h = (rect->y1 - rect->y0) * zoom;
    cairo_rectangle(cr, x, y, w, h);
    cairo_fill(cr);
}

static cairo_surface_t* page_surface_from_pixbuf(GdkPixbuf* pixbuf, int display_scale) {
    int width = gdk_pixbuf_get_width(pixbuf);
    int height = gdk_pixbuf_get_height(pixbuf);
    cairo_surface_t* surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
    cairo_t* cr = cairo_create(surface);
    gdk_cairo_set_source_pixbuf(cr, pixbuf, 0, 0);
    cairo_paint(cr);
    cairo_destroy(cr);
    cairo_surface_set_device_scale(surface, display_scale, display_scale);
    return surface;
}

static cairo_surface_t* decorate_page_surface(spdf_document* doc, GdkPixbuf* pixbuf, int page_index, double render_zoom,
                                              int display_scale, const char* search_text, gboolean search_regex,
                                              const spdf_rect* highlight_rects, int highlight_rect_count,
                                              const spdf_rect* selection_rects, int selection_rect_count,
                                              const spdf_rect* active_rect) {
    gboolean has_search = search_text && *search_text && !search_regex && !find_query_too_long(search_text);
    gboolean has_highlights = highlight_rects && highlight_rect_count > 0;
    gboolean has_selection = selection_rects && selection_rect_count > 0;
    gboolean has_active = active_rect != NULL;
    int width;
    int height;
    cairo_surface_t* surface;
    cairo_t* cr;

    if (!pixbuf) return NULL;
    if (!has_search && !has_highlights && !has_selection && !has_active)
        return page_surface_from_pixbuf(pixbuf, display_scale);

    width = gdk_pixbuf_get_width(pixbuf);
    height = gdk_pixbuf_get_height(pixbuf);
    surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
    cr = cairo_create(surface);
    gdk_cairo_set_source_pixbuf(cr, pixbuf, 0, 0);
    cairo_paint(cr);

    if (has_search) {
        char search_err[256];
        spdf_rect rects[256];
        int count = spdf_search_page_rects(doc, page_index, search_text, rects, 256, search_err, sizeof(search_err));
        if (count > 0) {
            cairo_set_source_rgba(cr, 1.0, 0.84, 0.12, 0.34);
            for (int i = 0; i < count; ++i) {
                draw_find_highlight(cr, &rects[i], render_zoom);
            }
        }
    }

    if (has_highlights) {
        cairo_set_source_rgba(cr, 1.0, 0.84, 0.12, 0.34);
        for (int i = 0; i < highlight_rect_count; ++i) draw_find_highlight(cr, &highlight_rects[i], render_zoom);
    }

    if (has_selection) {
        cairo_set_source_rgba(cr, 0.40, 0.62, 0.86, 0.34);
        for (int i = 0; i < selection_rect_count; ++i) draw_find_highlight(cr, &selection_rects[i], render_zoom);
    }

    if (has_active) {
        double x = active_rect->x0 * render_zoom - 2.0;
        double y = active_rect->y0 * render_zoom - 2.0;
        double w = (active_rect->x1 - active_rect->x0) * render_zoom + 4.0;
        double h = (active_rect->y1 - active_rect->y0) * render_zoom + 4.0;
        cairo_set_source_rgba(cr, 0.94, 0.03, 0.02, 0.95);
        cairo_set_line_width(cr, 1.25);
        cairo_rectangle(cr, x, y, w, h);
        cairo_stroke(cr);
    }

    cairo_destroy(cr);
    cairo_surface_set_device_scale(surface, display_scale, display_scale);
    return surface;
}

static cairo_surface_t* render_page_surface_for_doc(spdf_document* doc, int page_index, double zoom, int display_scale,
                                                    const char* search_text, gboolean search_regex,
                                                    const spdf_rect* highlight_rects, int highlight_rect_count,
                                                    const spdf_rect* selection_rects, int selection_rect_count,
                                                    const spdf_rect* active_rect, char* err, size_t err_len) {
    spdf_bitmap bitmap;
    double render_zoom = zoom * display_scale;
    cairo_surface_t* surface;
    gsize byte_count;
    guchar* pixels;
    if (!spdf_render_page_rgba(doc, page_index, (float)render_zoom, &bitmap, err, err_len)) return NULL;

    byte_count = (gsize)bitmap.stride * (gsize)bitmap.height;
    pixels = g_try_malloc(byte_count);
    if (!pixels) {
        snprintf(err, err_len, "%s", "Could not allocate page bitmap.");
        spdf_free_bitmap(&bitmap);
        return NULL;
    }
    memcpy(pixels, bitmap.rgba, byte_count);
    GdkPixbuf* pixbuf = gdk_pixbuf_new_from_data(pixels, GDK_COLORSPACE_RGB, TRUE, 8, bitmap.width, bitmap.height,
                                                 bitmap.stride, free_pixbuf_pixels, NULL);
    spdf_free_bitmap(&bitmap);
    surface = decorate_page_surface(doc, pixbuf, page_index, render_zoom, display_scale, search_text, search_regex,
                                    highlight_rects, highlight_rect_count, selection_rects, selection_rect_count,
                                    active_rect);
    g_object_unref(pixbuf);
    return surface;
}

static cairo_surface_t* render_page_surface(app_state* state, int page_index, char* err, size_t err_len) {
    spdf_rect active_rect;
    spdf_rect* highlight_rects = NULL;
    spdf_rect* selection_rects = NULL;
    int highlight_rect_count = 0;
    int selection_rect_count = 0;
    cairo_surface_t* surface;
    const char* search_text = current_search_text(state);
    const char* render_search_text = search_text;
    gboolean has_active = active_find_rect_for_page(state, page_index, &active_rect);
    if (state->find_match_count > 0) {
        highlight_rects = copy_find_rects_for_page(state, page_index, &highlight_rect_count);
        render_search_text = NULL;
    } else if (state->search_regex) {
        highlight_rects = copy_find_rects_for_page(state, page_index, &highlight_rect_count);
    }
    selection_rects = copy_selection_rects_for_page(state, page_index, &selection_rect_count);
    surface = render_page_surface_for_doc(state->doc, page_index, state->zoom, display_scale_for_state(state),
                                          render_search_text, state->search_regex, highlight_rects,
                                          highlight_rect_count, selection_rects, selection_rect_count,
                                          has_active ? &active_rect : NULL, err, err_len);
    g_free(highlight_rects);
    g_free(selection_rects);
    return surface;
}

static void clear_page_box(app_state* state) {
    GList* children = gtk_container_get_children(GTK_CONTAINER(state->page_box));
    for (GList* it = children; it; it = it->next) gtk_widget_destroy(GTK_WIDGET(it->data));
    g_list_free(children);
}

static void show_empty_view_message(app_state* state, const char* message, const char* detail) {
    GtkWidget* box;
    GtkWidget* title;
    GtkWidget* subtitle;
    char* escaped_title;
    char* markup;

    clear_empty_view_message(state);
    state->empty_view_message = g_strdup(message ? message : "Ready");
    state->render_generation++;
    cancel_background_render(state);
    if (!state->page_box) return;

    clear_page_box(state);
    gtk_widget_set_halign(state->page_box, GTK_ALIGN_FILL);
    gtk_widget_set_valign(state->page_box, GTK_ALIGN_FILL);
    gtk_widget_set_hexpand(state->page_box, TRUE);
    gtk_widget_set_vexpand(state->page_box, TRUE);

    box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    title = gtk_label_new(NULL);
    subtitle = gtk_label_new(detail ? detail : "");
    escaped_title = g_markup_escape_text(message ? message : "", -1);
    markup = g_strdup_printf("<span size=\"large\" weight=\"bold\">%s</span>", escaped_title);

    gtk_widget_set_halign(box, GTK_ALIGN_CENTER);
    gtk_widget_set_valign(box, GTK_ALIGN_CENTER);
    gtk_widget_set_hexpand(box, TRUE);
    gtk_widget_set_vexpand(box, TRUE);
    gtk_label_set_markup(GTK_LABEL(title), markup);
    gtk_label_set_xalign(GTK_LABEL(title), 0.5);
    gtk_label_set_xalign(GTK_LABEL(subtitle), 0.5);
    gtk_label_set_ellipsize(GTK_LABEL(subtitle), PANGO_ELLIPSIZE_MIDDLE);
    gtk_widget_set_margin_start(box, 40);
    gtk_widget_set_margin_end(box, 40);
    gtk_widget_set_margin_top(box, 40);
    gtk_widget_set_margin_bottom(box, 40);
    gtk_widget_set_size_request(subtitle, 420, -1);

    gtk_box_pack_start(GTK_BOX(box), title, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(box), subtitle, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(state->page_box), box, TRUE, TRUE, 0);
    gtk_widget_show_all(state->page_box);

    g_free(markup);
    g_free(escaped_title);
}

static void show_missing_document(app_state* state, const char* path) {
    char* title;
    char* window_title;

    if (state->presentation_mode) set_presentation_mode(state, FALSE);
    cancel_deferred_sidebar_load(state);
    spdf_free_outline(&state->outline);
    spdf_free_comments(&state->comments);
    spdf_close(state->doc);
    state->doc = NULL;
    state->document_generation++;
    clear_find_results(state);
    clear_text_selection(state);
    if (state->find_markers) gtk_widget_hide(state->find_markers);
    free(state->path);
    state->path = strdup(path ? path : "");
    state->page_index = 0;
    rebuild_sidebar(state);
    show_empty_view_message(state, "File moved or deleted", path ? path : "");
    title = display_name_for_path(path ? path : "");
    window_title = g_strdup_printf("%s - Missing - SumatraPDF", title && *title ? title : "Missing file");
    gtk_window_set_title(GTK_WINDOW(state->window), window_title);
    gtk_label_set_text(GTK_LABEL(state->status), "File moved or deleted.");
    update_controls(state);
    if (!state->switching_tabs) {
        save_active_tab_state(state);
        update_tab_strip(state);
        save_session(state);
    }
    g_free(window_title);
    g_free(title);
}

static void configure_page_image(app_state* state, GtkWidget* image) {
    int horizontal_margin = state->presentation_mode ? 0 : 22;
    int vertical_margin = state->presentation_mode ? 0 : 13;
    gtk_widget_set_margin_start(image, horizontal_margin);
    gtk_widget_set_margin_end(image, horizontal_margin);
    gtk_widget_set_margin_top(image, vertical_margin);
    gtk_widget_set_margin_bottom(image, vertical_margin);
}

static GtkWidget* append_page_image(app_state* state, cairo_surface_t* surface, int page_index) {
    GtkWidget* image = gtk_image_new_from_surface(surface);
    configure_page_image(state, image);
    g_object_set_data(G_OBJECT(image), "page-index", GINT_TO_POINTER(page_index + 1));
    gtk_box_pack_start(GTK_BOX(state->page_box), image, FALSE, FALSE, 0);
    return image;
}

static GtkWidget* append_page_slot(app_state* state, int page_index) {
    GtkWidget* image = gtk_image_new();
    configure_page_image(state, image);
    g_object_set_data(G_OBJECT(image), "page-index", GINT_TO_POINTER(page_index + 1));
    gtk_box_pack_start(GTK_BOX(state->page_box), image, FALSE, FALSE, 0);
    return image;
}

static int page_render_state(GtkWidget* image) {
    return GPOINTER_TO_INT(g_object_get_data(G_OBJECT(image), "render-state"));
}

static void set_page_render_state(GtkWidget* image, int render_state) {
    g_object_set_data(G_OBJECT(image), "render-state", GINT_TO_POINTER(render_state));
}

static void size_page_slot(GtkWidget* image, double zoom, float page_width, float page_height) {
    gtk_widget_set_size_request(image, MAX(1, (int)(page_width * zoom)), MAX(1, (int)(page_height * zoom)));
}

static void cancel_deferred_sidebar_load(app_state* state) {
    if (state && state->sidebar_metadata_idle_id) {
        g_source_remove(state->sidebar_metadata_idle_id);
        state->sidebar_metadata_idle_id = 0;
    }
}

static gboolean load_sidebar_metadata_idle(gpointer data) {
    generation_request* request = (generation_request*)data;
    app_state* state = request->state;
    char err[1024];

    if (state->sidebar_metadata_idle_id) state->sidebar_metadata_idle_id = 0;
    if (request->generation == state->document_generation && state->doc) {
        spdf_free_outline(&state->outline);
        spdf_free_comments(&state->comments);
        spdf_load_outline(state->doc, &state->outline, err, sizeof(err));
        spdf_load_comments(state->doc, &state->comments, err, sizeof(err));
        rebuild_sidebar(state);
        update_controls(state);
    }
    return G_SOURCE_REMOVE;
}

static void schedule_deferred_sidebar_load(app_state* state) {
    generation_request* request;

    if (!state || !state->doc) return;
    cancel_deferred_sidebar_load(state);
    request = g_new0(generation_request, 1);
    request->state = state;
    request->generation = state->document_generation;
    state->sidebar_metadata_idle_id = g_idle_add_full(G_PRIORITY_LOW, load_sidebar_metadata_idle, request, g_free);
}

static gboolean render_finished_idle(gpointer data) {
    render_result* result = (render_result*)data;
    app_state* state = result->state;

    if (result->generation == state->render_generation) {
        gboolean stale_surface = result->surface && state->continuous_mode &&
                                 abs(result->page_index - state->page_index) > RENDERED_PAGE_EVICT_RADIUS;
        if (stale_surface) {
            set_page_render_state(result->image, 0);
        } else if (result->surface) {
            gtk_image_set_from_surface(GTK_IMAGE(result->image), result->surface);
            set_page_render_state(result->image, 2);
            gtk_widget_show(result->image);
            evict_distant_page_surfaces(state);
        } else if (result->missing_file) {
            show_missing_document(state, result->path);
        } else if (!state->render_error_shown) {
            set_page_render_state(result->image, 0);
            state->render_error_shown = TRUE;
            show_error(GTK_WINDOW(state->window), "Could not render page", result->err);
        }
    }

    if (result->surface) cairo_surface_destroy(result->surface);
    g_object_unref(result->image);
    g_free(result->path);
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
    result->path = g_strdup(task->path);

    if (task->generation != task->state->render_generation) {
        g_idle_add(render_finished_idle, result);
        g_free(task->path);
        g_free(task->search_text);
        g_free(task->highlight_rects);
        g_free(task->selection_rects);
        g_free(task);
        return;
    }

    if (!g_file_test(task->path, G_FILE_TEST_EXISTS)) {
        result->missing_file = TRUE;
        doc = NULL;
    } else {
        doc = spdf_open(task->path, result->err, sizeof(result->err));
        if (!doc && !g_file_test(task->path, G_FILE_TEST_EXISTS)) result->missing_file = TRUE;
    }
    if (doc) {
        result->surface = render_page_surface_for_doc(
            doc, task->page_index, task->zoom, task->display_scale, task->search_text, task->search_regex,
            task->highlight_rects, task->highlight_rect_count, task->selection_rects, task->selection_rect_count,
            task->has_active_rect ? &task->active_rect : NULL, result->err, sizeof(result->err));
        spdf_close(doc);
    }

    g_idle_add(render_finished_idle, result);
    g_free(task->path);
    g_free(task->search_text);
    g_free(task->highlight_rects);
    g_free(task->selection_rects);
    g_free(task);
}

static void queue_page_render(app_state* state, GtkWidget* image, int page_index) {
    render_task* task;
    GError* error = NULL;

    if (!state->render_pool || !state->path || page_render_state(image) != 0) return;

    task = g_new0(render_task, 1);
    task->state = state;
    task->path = g_strdup(state->path);
    task->image = g_object_ref(image);
    task->generation = state->render_generation;
    task->page_index = page_index;
    task->zoom = state->zoom;
    task->display_scale = display_scale_for_state(state);
    task->search_text = g_strdup(current_search_text(state));
    task->search_regex = state->search_regex;
    if (state->search_regex)
        task->highlight_rects = copy_find_rects_for_page(state, page_index, &task->highlight_rect_count);
    task->selection_rects = copy_selection_rects_for_page(state, page_index, &task->selection_rect_count);
    task->has_active_rect = active_find_rect_for_page(state, page_index, &task->active_rect);

    set_page_render_state(image, 1);
    if (!g_thread_pool_push(state->render_pool, task, &error)) {
        set_page_render_state(image, 0);
        g_object_unref(task->image);
        g_free(task->path);
        g_free(task->search_text);
        g_free(task->highlight_rects);
        g_free(task->selection_rects);
        g_free(task);
        if (!state->render_error_shown) {
            state->render_error_shown = TRUE;
            show_error(GTK_WINDOW(state->window), "Could not queue page render", error ? error->message : "");
        }
    }
    if (error) g_error_free(error);
}

static int queue_background_pages_near_current(app_state* state, int limit) {
    int queued = 0;
    int page_count;

    if (!state || !state->doc || !state->continuous_mode || limit <= 0) return 0;
    page_count = spdf_page_count(state->doc);
    for (int distance = 0; distance <= BACKGROUND_RENDER_RADIUS && queued < limit; ++distance) {
        int pages[2];
        int page_slots = 0;
        if (distance == 0) {
            pages[page_slots++] = state->page_index;
        } else {
            pages[page_slots++] = state->page_index + distance;
            pages[page_slots++] = state->page_index - distance;
        }

        for (int i = 0; i < page_slots && queued < limit; ++i) {
            GtkWidget* image;
            int page = pages[i];
            if (page < 0 || page >= page_count) continue;
            image = page_widget_for_index(state, page);
            if (!image || page_render_state(image) != 0) continue;
            queue_page_render(state, image, page);
            queued++;
        }
    }
    return queued;
}

static gboolean background_render_idle(gpointer data) {
    generation_request* request = (generation_request*)data;
    app_state* state = request->state;

    if (state->background_render_idle_id) state->background_render_idle_id = 0;
    if (request->generation == state->render_generation)
        queue_background_pages_near_current(state, BACKGROUND_RENDER_BATCH_LIMIT);
    return G_SOURCE_REMOVE;
}

static void schedule_background_render(app_state* state) {
    generation_request* request;

    if (!state || !state->doc || !state->continuous_mode) return;
    if (state->background_render_idle_id) return;
    request = g_new0(generation_request, 1);
    request->state = state;
    request->generation = state->render_generation;
    state->background_render_idle_id = g_idle_add_full(G_PRIORITY_LOW, background_render_idle, request, g_free);
}

static void cancel_background_render(app_state* state) {
    if (state && state->background_render_idle_id) {
        g_source_remove(state->background_render_idle_id);
        state->background_render_idle_id = 0;
    }
}

static void evict_distant_page_surfaces(app_state* state) {
    GList* children;

    if (!state || !state->doc || !state->continuous_mode || !state->page_box) return;
    children = gtk_container_get_children(GTK_CONTAINER(state->page_box));
    for (GList* it = children; it; it = it->next) {
        GtkWidget* image = GTK_WIDGET(it->data);
        int page = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(image), "page-index")) - 1;
        if (page < 0 || page_render_state(image) != 2) continue;
        if (abs(page - state->page_index) <= RENDERED_PAGE_EVICT_RADIUS) continue;
        gtk_image_clear(GTK_IMAGE(image));
        set_page_render_state(image, 0);
    }
    g_list_free(children);
}

static gboolean scroll_to_widget_idle(gpointer data) {
    scroll_request* request = (scroll_request*)data;
    app_state* state = request->state;

    if (request->generation == state->render_generation) {
        GtkAllocation allocation;
        GtkAdjustment* vadj = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(state->scroll));
        double upper = gtk_adjustment_get_upper(vadj);
        double page_size = gtk_adjustment_get_page_size(vadj);
        int page_index = -1;
        double page_y = 0.0;
        if (widget_page_index(request->widget, &page_index) &&
            page_widget_geometry(state, page_index, NULL, &page_y, NULL, NULL)) {
            gtk_adjustment_set_value(vadj, MAX(gtk_adjustment_get_lower(vadj), MIN(page_y, upper - page_size)));
        } else {
            gtk_widget_get_allocation(request->widget, &allocation);
            gtk_adjustment_set_value(vadj,
                                     MAX(gtk_adjustment_get_lower(vadj), MIN((double)allocation.y, upper - page_size)));
        }
        clamp_horizontal_scroll(state);
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

static gboolean restore_scroll_position_idle(gpointer data) {
    scroll_position_request* request = (scroll_position_request*)data;
    app_state* state = request->state;

    if (request->generation == state->render_generation && state->scroll) {
        GtkAdjustment* hadj = gtk_scrolled_window_get_hadjustment(GTK_SCROLLED_WINDOW(state->scroll));
        GtkAdjustment* vadj = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(state->scroll));
        gtk_adjustment_set_value(
            hadj, MAX(gtk_adjustment_get_lower(hadj),
                      MIN(request->hvalue, gtk_adjustment_get_upper(hadj) - gtk_adjustment_get_page_size(hadj))));
        gtk_adjustment_set_value(
            vadj, MAX(gtk_adjustment_get_lower(vadj),
                      MIN(request->vvalue, gtk_adjustment_get_upper(vadj) - gtk_adjustment_get_page_size(vadj))));
        clamp_horizontal_scroll(state);
    }

    g_free(request);
    return G_SOURCE_REMOVE;
}

static void render_current_page_preserving_scroll(app_state* state) {
    scroll_position_request* request = NULL;

    if (state->scroll) {
        GtkAdjustment* hadj = gtk_scrolled_window_get_hadjustment(GTK_SCROLLED_WINDOW(state->scroll));
        GtkAdjustment* vadj = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(state->scroll));
        request = g_new0(scroll_position_request, 1);
        request->state = state;
        request->hvalue = gtk_adjustment_get_value(hadj);
        request->vvalue = gtk_adjustment_get_value(vadj);
    }

    render_current_page(state, FALSE);
    if (request) {
        request->generation = state->render_generation;
        g_idle_add(restore_scroll_position_idle, request);
    }
}

static gboolean scroll_to_page_point_idle(gpointer data) {
    page_point_scroll_request* request = (page_point_scroll_request*)data;
    app_state* state = request->state;

    if (request->generation == state->render_generation && state->scroll) {
        GtkAdjustment* hadj = gtk_scrolled_window_get_hadjustment(GTK_SCROLLED_WINDOW(state->scroll));
        GtkAdjustment* vadj = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(state->scroll));
        double page_x = 0.0;
        double page_y = 0.0;
        double page_width = 0.0;
        double target_h;
        double target_v;
        double h_page = gtk_adjustment_get_page_size(hadj);
        double v_page = gtk_adjustment_get_page_size(vadj);

        if (page_widget_geometry(state, request->page_index, &page_x, &page_y, &page_width, NULL)) {
            if (request->preserve_horizontal) {
                target_h = gtk_adjustment_get_value(hadj);
            } else if (request->has_point) {
                target_h = page_x + request->x * state->zoom - h_page * 0.5;
                target_v = page_y + request->y * state->zoom - 20.0;
            } else {
                target_h = page_x + page_width * 0.5 - h_page * 0.5;
                target_v = page_y;
            }
            if (request->preserve_horizontal) {
                target_v = request->has_point ? page_y + request->y * state->zoom - 20.0 : page_y;
            }
            gtk_adjustment_set_value(
                hadj, MAX(gtk_adjustment_get_lower(hadj),
                          MIN(target_h, gtk_adjustment_get_upper(hadj) - gtk_adjustment_get_page_size(hadj))));
            gtk_adjustment_set_value(
                vadj, MAX(gtk_adjustment_get_lower(vadj),
                          MIN(target_v, gtk_adjustment_get_upper(vadj) - gtk_adjustment_get_page_size(vadj))));
            clamp_horizontal_scroll(state);
        }
    }

    g_free(request);
    return G_SOURCE_REMOVE;
}

static void scroll_to_page_point(app_state* state, int page_index, double x, double y, gboolean has_point) {
    page_point_scroll_request* request;
    if (!state || !state->scroll) return;
    request = g_new0(page_point_scroll_request, 1);
    request->state = state;
    request->generation = state->render_generation;
    request->page_index = page_index;
    request->x = x;
    request->y = y;
    request->has_point = has_point;
    g_idle_add(scroll_to_page_point_idle, request);
}

static void scroll_to_page_point_preserving_horizontal(app_state* state, int page_index, double y) {
    page_point_scroll_request* request;
    if (!state || !state->scroll) return;
    request = g_new0(page_point_scroll_request, 1);
    request->state = state;
    request->generation = state->render_generation;
    request->page_index = page_index;
    request->x = 0.0;
    request->y = y;
    request->has_point = TRUE;
    request->preserve_horizontal = TRUE;
    g_idle_add(scroll_to_page_point_idle, request);
}

static void open_path_at_page(app_state* state, const char* path, int page_index) {
    char err[1024];
    spdf_document* doc;

    if (!path || !g_file_test(path, G_FILE_TEST_EXISTS)) {
        show_missing_document(state, path);
        return;
    }

    doc = spdf_open(path, err, sizeof(err));
    if (!doc) {
        show_error(GTK_WINDOW(state->window), "Could not open document", err);
        return;
    }

    spdf_free_outline(&state->outline);
    spdf_free_comments(&state->comments);
    spdf_close(state->doc);
    state->doc = doc;
    clear_empty_view_message(state);
    clear_text_selection(state);
    free(state->path);
    state->path = strdup(path);
    state->page_index = MAX(0, MIN(page_index, spdf_page_count(state->doc) - 1));
    gtk_combo_box_set_active(GTK_COMBO_BOX(state->fit_mode), state->fit_mode_id);
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(state->continuous), state->continuous_mode);
    state->document_generation++;
    rebuild_sidebar(state);
    render_current_page(state, TRUE);
    schedule_deferred_sidebar_load(state);
    if (!state->switching_tabs) {
        save_active_tab_state(state);
        update_tab_strip(state);
        save_session(state);
    }
}

static void open_path_in_tab_at_page(app_state* state, const char* path, int page_index, gboolean clear_search) {
    int existing = find_tab_by_path(state, path);

    if (existing >= 0) {
        select_tab(state, existing);
        if (clear_search) {
            set_search_entry_text(state, "");
            clear_find_results(state);
        }
        if (state->doc) {
            state->page_index = MAX(0, MIN(page_index, spdf_page_count(state->doc) - 1));
            render_current_page(state, TRUE);
            save_active_tab_state(state);
            update_tab_strip(state);
            save_session(state);
        }
        if (state->doc && state->path) {
            remember_recent_path(state, state->path);
            save_settings(state);
        }
        return;
    }

    save_active_tab_state(state);
    if (state->tab_count == 0 ||
        (state->selected_tab >= 0 && state->selected_tab < state->tab_count && state->tabs[state->selected_tab].path &&
         state->tabs[state->selected_tab].path[0] != '\0')) {
        char* title = display_name_for_path(path);
        int index = append_document_tab(state, path, title, page_index, state->zoom, state->fit_mode_id,
                                        state->continuous_mode, "", FALSE, state->search_regex_multiline, -1);
        g_free(title);
        state->selected_tab = index;
    } else if (state->selected_tab < 0 && state->tab_count > 0) {
        state->selected_tab = 0;
    }

    if (clear_search) {
        set_search_entry_text(state, "");
        clear_find_results(state);
    }
    update_tab_strip(state);
    open_path_at_page(state, path, page_index);
    if (state->doc && state->path) {
        remember_recent_path(state, state->path);
        save_settings(state);
    }
}

static void open_path(app_state* state, const char* path) {
    int existing = find_tab_by_path(state, path);
    if (existing >= 0) {
        select_tab(state, existing);
        if (state->doc && state->path) {
            remember_recent_path(state, state->path);
            save_settings(state);
        }
        return;
    }
    open_path_in_tab_at_page(state, path, 0, TRUE);
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

static void tab_button_clicked(GtkButton* button, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    int index = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "tab-index")) - 1;
    select_tab(state, index);
}

static void cancel_deferred_find(app_state* state) {
    if (state && state->deferred_find_idle_id) {
        g_source_remove(state->deferred_find_idle_id);
        state->deferred_find_idle_id = 0;
    }
}

static gboolean deferred_find_idle(gpointer data) {
    find_request* request = (find_request*)data;
    app_state* state = request->state;

    if (state->deferred_find_idle_id) state->deferred_find_idle_id = 0;
    if (request->document_generation == state->document_generation && state->doc) {
        start_find_for_current_query(state, request->preferred_index, request->preferred_page, request->reveal_match,
                                     request->preserve_scroll);
    }
    return G_SOURCE_REMOVE;
}

static void schedule_deferred_find(app_state* state, int preferred_index, int preferred_page, gboolean reveal_match,
                                   gboolean preserve_scroll) {
    find_request* request;

    if (!state || !state->doc) return;
    cancel_deferred_find(state);
    request = g_new0(find_request, 1);
    request->state = state;
    request->document_generation = state->document_generation;
    request->preferred_index = preferred_index;
    request->preferred_page = preferred_page;
    request->reveal_match = reveal_match;
    request->preserve_scroll = preserve_scroll;
    state->deferred_find_idle_id = g_idle_add_full(G_PRIORITY_LOW, deferred_find_idle, request, g_free);
}

static void close_document_view(app_state* state) {
    cancel_deferred_sidebar_load(state);
    cancel_deferred_find(state);
    if (state->presentation_mode) set_presentation_mode(state, FALSE);
    spdf_free_outline(&state->outline);
    spdf_free_comments(&state->comments);
    spdf_close(state->doc);
    state->doc = NULL;
    state->document_generation++;
    free(state->path);
    state->path = NULL;
    clear_find_results(state);
    clear_text_selection(state);
    set_search_entry_text(state, "");
    if (state->find_markers) gtk_widget_hide(state->find_markers);
    rebuild_sidebar(state);
    show_empty_view_message(state, "Ready", "");
    update_controls(state);
}

static void tab_close_clicked(GtkButton* button, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    int index = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "tab-index")) - 1;
    gboolean was_selected;
    char* closed_path;

    if (index < 0 || index >= state->tab_count) return;
    was_selected = index == state->selected_tab;
    closed_path = g_strdup(state->tabs[index].path);
    remember_closed_path(state, closed_path);
    g_free(closed_path);
    if (was_selected) state->selected_tab = -1;
    free_document_tab(&state->tabs[index]);
    if (index + 1 < state->tab_count) {
        memmove(&state->tabs[index], &state->tabs[index + 1],
                (gsize)(state->tab_count - index - 1) * sizeof(document_tab));
    }
    state->tab_count--;
    if (!was_selected && state->selected_tab > index) state->selected_tab--;

    if (was_selected) {
        close_document_view(state);
        if (state->tab_count > 0) select_tab(state, MIN(index, state->tab_count - 1));
    } else {
        update_tab_strip(state);
    }
    save_session(state);
}

static void move_tab(app_state* state, int from_index, int to_index) {
    document_tab moving;
    int count;

    if (!state || from_index < 0 || to_index < 0 || from_index == to_index) return;
    count = state->tab_count;
    if (from_index >= count || to_index >= count) return;

    moving = state->tabs[from_index];
    if (from_index < to_index) {
        memmove(&state->tabs[from_index], &state->tabs[from_index + 1],
                (gsize)(to_index - from_index) * sizeof(document_tab));
    } else {
        memmove(&state->tabs[to_index + 1], &state->tabs[to_index],
                (gsize)(from_index - to_index) * sizeof(document_tab));
    }
    state->tabs[to_index] = moving;

    if (state->selected_tab == from_index)
        state->selected_tab = to_index;
    else if (from_index < state->selected_tab && state->selected_tab <= to_index)
        state->selected_tab--;
    else if (to_index <= state->selected_tab && state->selected_tab < from_index)
        state->selected_tab++;

    update_tab_strip(state);
    save_session(state);
}

static gboolean tab_handle_draw(GtkWidget* widget, cairo_t* cr, gpointer user_data) {
    (void)user_data;
    GtkAllocation allocation;
    GtkStyleContext* context;
    GdkRGBA color;
    double dot_size = 2.0;
    double gap_x = 4.0;
    double gap_y = 4.0;

    gtk_widget_get_allocation(widget, &allocation);
    context = gtk_widget_get_style_context(widget);
    gtk_style_context_get_color(context, gtk_style_context_get_state(context), &color);
    color.alpha *= 0.62;
    gdk_cairo_set_source_rgba(cr, &color);
    double start_x = floor(allocation.width * 0.5 - dot_size - gap_x * 0.5);
    double start_y = floor(allocation.height * 0.5 - dot_size - gap_y * 0.5);
    for (int column = 0; column < 2; ++column) {
        for (int row = 0; row < 2; ++row) {
            double x = start_x + column * (dot_size + gap_x);
            double y = start_y + row * (dot_size + gap_y);
            cairo_arc(cr, x + dot_size * 0.5, y + dot_size * 0.5, dot_size * 0.5, 0, G_PI * 2.0);
            cairo_fill(cr);
        }
    }
    return FALSE;
}

static int tab_index_for_bar_x(app_state* state, double x, int fallback_index) {
    GList* children;
    int target = fallback_index;

    if (!state || !state->tab_bar) return fallback_index;
    children = gtk_container_get_children(GTK_CONTAINER(state->tab_bar));
    for (GList* it = children; it; it = it->next) {
        GtkWidget* child = GTK_WIDGET(it->data);
        GtkAllocation allocation;
        int child_index = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(child), "tab-index")) - 1;
        if (child_index < 0) continue;
        gtk_widget_get_allocation(child, &allocation);
        if (x < allocation.x + allocation.width * 0.5) {
            target = child_index;
            break;
        }
        target = child_index;
    }
    g_list_free(children);
    return target;
}

static gboolean tab_handle_button_press(GtkWidget* widget, GdkEventButton* event, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    int index;

    if (!state || event->button != 1) return FALSE;
    index = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget), "tab-index")) - 1;
    if (index < 0 || index >= state->tab_count) return FALSE;
    state->tab_drag_index = index;
    state->tab_dragging = FALSE;
    state->tab_drag_start_x = event->x_root;
    state->tab_drag_start_y = event->y_root;
    gtk_grab_add(widget);
    return TRUE;
}

static gboolean tab_handle_motion(GtkWidget* widget, GdkEventMotion* event, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    double dx;
    double dy;

    (void)widget;
    if (!state || state->tab_drag_index < 0) return FALSE;
    dx = event->x_root - state->tab_drag_start_x;
    dy = event->y_root - state->tab_drag_start_y;
    if (!state->tab_dragging && hypot(dx, dy) < 3.0) return TRUE;
    state->tab_dragging = TRUE;
    return TRUE;
}

static gboolean tab_handle_button_release(GtkWidget* widget, GdkEventButton* event, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    gint bar_x = 0;
    gint bar_y = 0;
    int target;

    if (!state || event->button != 1 || state->tab_drag_index < 0) return FALSE;
    gtk_grab_remove(widget);
    if (gtk_widget_translate_coordinates(widget, state->tab_bar, (gint)event->x, (gint)event->y, &bar_x, &bar_y)) {
        target = tab_index_for_bar_x(state, (double)bar_x, state->tab_drag_index);
        move_tab(state, state->tab_drag_index, target);
    } else if (!state->tab_dragging) {
        select_tab(state, state->tab_drag_index);
    }
    state->tab_drag_index = -1;
    state->tab_dragging = FALSE;
    return TRUE;
}

static void update_tab_strip(app_state* state) {
    if (!state->tab_bar) return;

    GList* children = gtk_container_get_children(GTK_CONTAINER(state->tab_bar));
    for (GList* it = children; it; it = it->next) gtk_widget_destroy(GTK_WIDGET(it->data));
    g_list_free(children);

    for (int i = 0; i < state->tab_count; ++i) {
        document_tab* tab = &state->tabs[i];
        GtkWidget* frame = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
        GtkWidget* handle = gtk_event_box_new();
        GtkWidget* handle_icon = gtk_drawing_area_new();
        GtkWidget* button = gtk_button_new_with_label(tab->title && *tab->title ? tab->title : "Untitled");
        GtkWidget* close = gtk_button_new_with_label("x");
        char* tooltip = g_strdup(tab->path && *tab->path ? tab->path : tab->title);

        gtk_widget_set_tooltip_text(handle, "Drag to reorder tab");
        gtk_widget_set_tooltip_text(button, tooltip);
        gtk_widget_set_tooltip_text(close, "Close tab");
        gtk_widget_set_size_request(handle, 24, 28);
        gtk_widget_set_size_request(handle_icon, 18, 20);
        gtk_widget_set_size_request(button, 120, 28);
        gtk_widget_set_size_request(close, 28, 28);
        if (i == state->selected_tab) gtk_widget_set_sensitive(button, FALSE);
        g_object_set_data(G_OBJECT(frame), "tab-index", GINT_TO_POINTER(i + 1));
        g_object_set_data(G_OBJECT(handle), "tab-index", GINT_TO_POINTER(i + 1));
        g_object_set_data(G_OBJECT(button), "tab-index", GINT_TO_POINTER(i + 1));
        g_object_set_data(G_OBJECT(close), "tab-index", GINT_TO_POINTER(i + 1));
        gtk_container_add(GTK_CONTAINER(handle), handle_icon);
        g_signal_connect(handle_icon, "draw", G_CALLBACK(tab_handle_draw), NULL);
        g_signal_connect(handle, "button-press-event", G_CALLBACK(tab_handle_button_press), state);
        g_signal_connect(handle, "motion-notify-event", G_CALLBACK(tab_handle_motion), state);
        g_signal_connect(handle, "button-release-event", G_CALLBACK(tab_handle_button_release), state);
        gtk_widget_add_events(handle, GDK_BUTTON_PRESS_MASK | GDK_BUTTON_RELEASE_MASK | GDK_POINTER_MOTION_MASK);
        g_signal_connect(button, "clicked", G_CALLBACK(tab_button_clicked), state);
        g_signal_connect(close, "clicked", G_CALLBACK(tab_close_clicked), state);
        gtk_box_pack_start(GTK_BOX(frame), handle, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(frame), button, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(frame), close, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(state->tab_bar), frame, FALSE, FALSE, 0);
        g_free(tooltip);
    }

    gtk_widget_show_all(state->tab_bar);
}

static void select_tab(app_state* state, int index) {
    document_tab* tab;
    char* search_text;
    int preferred_find_index;
    int preferred_page_index;

    if (index < 0 || index >= state->tab_count) return;
    if (index == state->selected_tab && state->doc) return;

    save_active_tab_state(state);
    state->selected_tab = index;
    tab = active_tab(state);
    search_text = g_strdup(tab->search_text ? tab->search_text : "");
    preferred_find_index = tab->find_match_index;
    preferred_page_index = tab->page_index;
    state->switching_tabs = TRUE;
    state->zoom = tab->zoom > 0.0 ? tab->zoom : 1.0;
    state->fit_mode_id = tab->fit_mode_id >= 0 && tab->fit_mode_id <= 4 ? tab->fit_mode_id : 2;
    state->continuous_mode = tab->continuous_mode;
    state->search_regex = tab->search_regex;
    state->search_regex_multiline = tab->search_regex_multiline;
    set_search_entry_text(state, tab->search_text ? tab->search_text : "");
    if (state->fit_mode) gtk_combo_box_set_active(GTK_COMBO_BOX(state->fit_mode), state->fit_mode_id);
    if (state->continuous) gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(state->continuous), state->continuous_mode);
    if (state->search_regex_check)
        gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(state->search_regex_check), state->search_regex);
    set_regex_multiline_widget_active(state->search_regex_multiline_check, state->search_regex_multiline);
    set_regex_multiline_widget_active(state->search_regex_multiline_item, state->search_regex_multiline);
    clear_find_results(state);
    update_tab_strip(state);
    open_path_at_page(state, tab->path, preferred_page_index);
    state->switching_tabs = FALSE;
    if (search_text && *search_text) {
        if (state->defer_find_until_idle)
            schedule_deferred_find(state, preferred_find_index, preferred_page_index, FALSE, TRUE);
        else
            start_find_for_current_query(state, preferred_find_index, preferred_page_index, FALSE, TRUE);
    } else {
        clear_find_results(state);
    }
    update_find_controls(state);
    save_active_tab_state(state);
    update_tab_strip(state);
    save_session(state);
    g_free(search_text);
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
        double fit_padding = state->presentation_mode ? 0.0 : 54.0;
        double width_zoom = page_width > 0 ? (allocation.width - fit_padding) / page_width : state->zoom;
        double height_zoom = page_height > 0 ? (allocation.height - fit_padding) / page_height : state->zoom;
        if (state->fit_mode_id == 1)
            state->zoom = 1.0;
        else if (state->fit_mode_id == 2 && allocation.width > 80 && page_width > 0)
            state->zoom = MAX(0.10, MIN(8.0, width_zoom));
        else if (state->fit_mode_id == 3 && allocation.height > 80 && page_height > 0)
            state->zoom = MAX(0.10, MIN(8.0, height_zoom));
        else if (state->fit_mode_id == 4 && allocation.width > 80 && allocation.height > 80)
            state->zoom = MAX(0.10, MIN(8.0, MIN(width_zoom, height_zoom)));
    }

    state->render_generation++;
    cancel_background_render(state);
    state->render_error_shown = FALSE;
    gtk_widget_set_halign(state->page_box, GTK_ALIGN_CENTER);
    gtk_widget_set_valign(state->page_box, state->presentation_mode ? GTK_ALIGN_CENTER : GTK_ALIGN_START);
    gtk_widget_set_hexpand(state->page_box, FALSE);
    gtk_widget_set_vexpand(state->page_box, state->presentation_mode);
    clear_page_box(state);
    page_count = spdf_page_count(state->doc);
    start_page = state->continuous_mode ? 0 : state->page_index;
    end_page = state->continuous_mode ? page_count : state->page_index + 1;

    if (state->continuous_mode) {
        GtkWidget** slots = g_new0(GtkWidget*, page_count);
        cairo_surface_t* surface;

        for (int i = start_page; i < end_page; ++i) {
            float slot_width = page_width;
            float slot_height = page_height;
            char slot_err[256];
            if (!spdf_page_size(state->doc, i, &slot_width, &slot_height, slot_err, sizeof(slot_err)) ||
                slot_width <= 0 || slot_height <= 0) {
                slot_width = page_width;
                slot_height = page_height;
            }
            slots[i] = append_page_slot(state, i);
            size_page_slot(slots[i], state->zoom, slot_width, slot_height);
        }

        surface = render_page_surface(state, state->page_index, err, sizeof(err));
        if (!surface) {
            g_free(slots);
            show_error(GTK_WINDOW(state->window), "Could not render page", err);
            return;
        }
        gtk_image_set_from_surface(GTK_IMAGE(slots[state->page_index]), surface);
        set_page_render_state(slots[state->page_index], 2);
        cairo_surface_destroy(surface);
        gtk_widget_show_all(state->page_box);
        if (scroll_to_top) scroll_to_rendered_page(state, slots[state->page_index]);
        schedule_background_render(state);
        g_free(slots);
    } else {
        for (int i = start_page; i < end_page; ++i) {
            cairo_surface_t* surface = render_page_surface(state, i, err, sizeof(err));
            if (!surface) {
                show_error(GTK_WINDOW(state->window), "Could not render page", err);
                return;
            }
            append_page_image(state, surface, i);
            cairo_surface_destroy(surface);
        }
        gtk_widget_show_all(state->page_box);
    }

    if (scroll_to_top) {
        GtkAdjustment* vadj = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(state->scroll));
        gtk_adjustment_set_value(vadj, gtk_adjustment_get_lower(vadj));
    }

    if (state->presentation_mode && state->scroll) gtk_widget_grab_focus(state->scroll);
    update_controls(state);
}

static void window_scale_factor_changed(GObject* object, GParamSpec* pspec, gpointer user_data) {
    (void)object;
    (void)pspec;
    app_state* state = (app_state*)user_data;
    if (state->doc) render_current_page(state, FALSE);
}

static void clear_page_entry_focus(app_state* state) {
    if (state->page_entry && gtk_widget_has_focus(state->page_entry) && state->scroll)
        gtk_widget_grab_focus(state->scroll);
}

static void page_entry_activate(GtkEntry* entry, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    int page_count;
    int requested;
    if (!state->doc) return;
    page_count = spdf_page_count(state->doc);
    requested = atoi(gtk_entry_get_text(entry)) - 1;
    if (requested < 0) requested = 0;
    if (requested >= page_count) requested = page_count - 1;
    state->page_index = requested;
    clear_page_entry_focus(state);
    render_current_page(state, TRUE);
    save_session(state);
}

static void previous_clicked(GtkButton* button, gpointer user_data) {
    (void)button;
    app_state* state = (app_state*)user_data;
    if (state->doc && state->page_index > 0) {
        state->page_index--;
        clear_page_entry_focus(state);
        render_current_page(state, TRUE);
        save_session(state);
    }
}

static void next_clicked(GtkButton* button, gpointer user_data) {
    (void)button;
    app_state* state = (app_state*)user_data;
    if (state->doc && state->page_index + 1 < spdf_page_count(state->doc)) {
        state->page_index++;
        clear_page_entry_focus(state);
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
    save_session(state);
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
    save_session(state);
}

static void fit_mode_changed(GtkComboBox* combo, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    state->fit_mode_id = gtk_combo_box_get_active(combo);
    if (state->switching_tabs) return;
    update_toolbar_overflow_menu_state(state);
    render_current_page(state, FALSE);
    save_settings(state);
    save_session(state);
}

static void continuous_toggled(GtkToggleButton* button, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    state->continuous_mode = gtk_toggle_button_get_active(button);
    if (state->switching_tabs) return;
    update_toolbar_overflow_menu_state(state);
    render_current_page(state, TRUE);
    save_settings(state);
    save_session(state);
}

static void show_sidebar_toggled(GtkCheckMenuItem* item, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    gboolean has_panel;
    if (state->updating_sidebar_menu) return;
    has_panel = state->doc && (state->outline.count > 0 || state->comments.count > 0);
    if (!has_panel || state->presentation_mode) {
        update_sidebar_menu_items(state);
        return;
    }
    state->show_sidebar = gtk_check_menu_item_get_active(item);
    rebuild_sidebar(state);
    save_settings(state);
}

static void side_panel_switch_changed(GObject* object, GParamSpec* pspec, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    gboolean has_panel;
    (void)pspec;
    if (state->updating_sidebar_menu) return;
    has_panel = state->doc && (state->outline.count > 0 || state->comments.count > 0);
    if (!has_panel || state->presentation_mode) {
        update_sidebar_menu_items(state);
        return;
    }
    state->show_sidebar = gtk_switch_get_active(GTK_SWITCH(object));
    rebuild_sidebar(state);
    save_settings(state);
}

static void show_minimap_toggled(GtkCheckMenuItem* item, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    if (state->updating_minimap_control) return;
    if (!state->doc || state->presentation_mode) {
        update_minimap_controls(state);
        return;
    }
    state->show_minimap = gtk_check_menu_item_get_active(item);
    update_minimap_controls(state);
    save_settings(state);
}

static void minimap_switch_changed(GObject* object, GParamSpec* pspec, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    (void)pspec;
    if (state->updating_minimap_control) return;
    if (!state->doc || state->presentation_mode) {
        update_minimap_controls(state);
        return;
    }
    state->show_minimap = gtk_switch_get_active(GTK_SWITCH(object));
    update_minimap_controls(state);
    save_settings(state);
}

static void marker_strip_switch_changed(GObject* object, GParamSpec* pspec, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    (void)pspec;
    if (state->updating_marker_strip_control) return;
    state->show_find_markers = gtk_switch_get_active(GTK_SWITCH(object));
    update_find_controls(state);
    save_settings(state);
}

static void sync_view_controls_without_callbacks(app_state* state) {
    gboolean switching_tabs = state->switching_tabs;
    state->switching_tabs = TRUE;
    if (state->fit_mode) gtk_combo_box_set_active(GTK_COMBO_BOX(state->fit_mode), state->fit_mode_id);
    if (state->continuous) gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(state->continuous), state->continuous_mode);
    state->switching_tabs = switching_tabs;
    update_toolbar_overflow_menu_state(state);
}

static gboolean presentation_render_idle(gpointer user_data) {
    app_state* state = (app_state*)user_data;
    if (state->presentation_mode && state->doc) render_current_page(state, TRUE);
    return G_SOURCE_REMOVE;
}

static void set_presentation_mode(app_state* state, gboolean enable) {
    if (!state || enable == state->presentation_mode) return;
    if (enable && !state->doc) return;

    if (enable) {
        gtk_scrolled_window_get_policy(GTK_SCROLLED_WINDOW(state->scroll), &state->presentation_prev_hpolicy,
                                       &state->presentation_prev_vpolicy);
        state->presentation_prev_continuous_mode = state->continuous_mode;
        state->presentation_prev_fit_mode_id = state->fit_mode_id;
        state->presentation_prev_show_sidebar = state->show_sidebar;
        state->presentation_prev_zoom = state->zoom;
        state->presentation_mode = TRUE;
        state->continuous_mode = FALSE;
        state->fit_mode_id = 4;
        state->show_sidebar = FALSE;

        sync_view_controls_without_callbacks(state);
        if (state->menubar) gtk_widget_hide(state->menubar);
        if (state->tab_strip) gtk_widget_hide(state->tab_strip);
        if (state->toolbar) gtk_widget_hide(state->toolbar);
        if (state->status) gtk_widget_hide(state->status);
        if (state->find_markers) gtk_widget_hide(state->find_markers);
        if (state->minimap) gtk_widget_hide(state->minimap);
        gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(state->scroll), GTK_POLICY_NEVER, GTK_POLICY_NEVER);
        gtk_widget_grab_focus(state->scroll);
        rebuild_sidebar(state);
        gtk_window_fullscreen(GTK_WINDOW(state->window));
        render_current_page(state, TRUE);
        g_idle_add(presentation_render_idle, state);
    } else {
        state->presentation_mode = FALSE;
        state->continuous_mode = state->presentation_prev_continuous_mode;
        state->fit_mode_id = state->presentation_prev_fit_mode_id;
        state->show_sidebar = state->presentation_prev_show_sidebar;
        state->zoom = state->presentation_prev_zoom > 0.0 ? state->presentation_prev_zoom : state->zoom;

        sync_view_controls_without_callbacks(state);
        if (state->menubar) gtk_widget_show(state->menubar);
        if (state->tab_strip) gtk_widget_show(state->tab_strip);
        if (state->toolbar) gtk_widget_show(state->toolbar);
        if (state->status) gtk_widget_show(state->status);
        gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(state->scroll), state->presentation_prev_hpolicy,
                                       state->presentation_prev_vpolicy);
        gtk_window_unfullscreen(GTK_WINDOW(state->window));
        rebuild_sidebar(state);
        if (state->doc) render_current_page(state, TRUE);
        save_active_tab_state(state);
        save_session(state);
        save_settings(state);
    }
    update_presentation_menu_item(state);
    update_controls(state);
}

static void presentation_toggled(GtkCheckMenuItem* item, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    if (state->updating_presentation_menu) return;
    set_presentation_mode(state, gtk_check_menu_item_get_active(item));
}

static void sidebar_page_switched(GtkNotebook* notebook, GtkWidget* page, guint page_num, gpointer user_data) {
    (void)notebook;
    (void)page;
    (void)page_num;
    update_sidebar_menu_items((app_state*)user_data);
}

static void paned_position_changed(GObject* object, GParamSpec* pspec, gpointer user_data) {
    (void)pspec;
    app_state* state = (app_state*)user_data;
    int position = gtk_paned_get_position(GTK_PANED(object));
    if (position < 120) return;
    state->sidebar_width = position;
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

static void jump_to_find_match(app_state* state, int index) {
    char status[160];

    if (!state->doc || index < 0 || index >= state->find_match_count) return;
    state->find_match_index = index;
    state->page_index = state->find_matches[index].page_index;
    render_current_page(state, TRUE);
    save_session(state);
    update_find_controls(state);
    snprintf(status, sizeof(status), "Match %d of %d", state->find_match_index + 1, state->find_match_count);
    gtk_label_set_text(GTK_LABEL(state->status), status);
}

static void start_find_for_current_query(app_state* state, int preferred_index, int preferred_page,
                                         gboolean reveal_match, gboolean preserve_scroll) {
    const char* needle = current_search_text(state);
    char err[1024];
    char first_err[1024] = "";
    int page_count;
    int chosen_index = -1;
    gboolean failed = FALSE;
    gboolean capped = FALSE;

    if (state->find_debounce_id) {
        g_source_remove(state->find_debounce_id);
        state->find_debounce_id = 0;
    }
    cancel_deferred_find(state);

    clear_find_results(state);
    if (!state->doc || !needle || !*needle) {
        if (preserve_scroll)
            render_current_page_preserving_scroll(state);
        else
            render_current_page(state, FALSE);
        update_find_controls(state);
        save_session(state);
        return;
    }
    if (find_query_too_long(needle)) {
        clear_find_results(state);
        if (preserve_scroll)
            render_current_page_preserving_scroll(state);
        else
            render_current_page(state, FALSE);
        update_find_controls(state);
        save_session(state);
        gtk_label_set_text(GTK_LABEL(state->status), "Search query is too long.");
        return;
    }

    page_count = spdf_page_count(state->doc);
    for (int page = 0; page < page_count; ++page) {
        spdf_rect rects[256];
        int hits = spdf_search_page_rects_options(state->doc, page, needle, state->search_regex ? 1 : 0,
                                                  state->search_regex_multiline ? 1 : 0, rects, 256, err, sizeof(err));
        if (hits < 0) {
            snprintf(first_err, sizeof(first_err), "%s", err[0] ? err : "Search failed.");
            failed = TRUE;
            break;
        }
        if (hits == 0) continue;
        for (int i = 0; i < hits; ++i) {
            int match_index = state->find_match_count;
            if (state->find_match_count >= MAX_FIND_MATCHES) {
                capped = TRUE;
                break;
            }
            if (!append_find_match(state, page, rects[i], TRUE)) break;
            if (chosen_index < 0 && preferred_page >= 0 && page == preferred_page) chosen_index = match_index;
        }
        if (capped) break;
    }

    if (failed) {
        char status[256];
        if (preserve_scroll)
            render_current_page_preserving_scroll(state);
        else
            render_current_page(state, FALSE);
        save_session(state);
        update_find_controls(state);
        snprintf(status, sizeof(status), "%s search failed: %s", state->search_regex ? "Regex" : "Find", first_err);
        gtk_label_set_text(GTK_LABEL(state->status), status);
        return;
    }

    if (preferred_index >= 0 && preferred_index < state->find_match_count)
        chosen_index = preferred_index;
    else if (chosen_index < 0 && state->find_match_count > 0)
        chosen_index = 0;

    if (chosen_index >= 0) {
        if (reveal_match) {
            jump_to_find_match(state, chosen_index);
        } else {
            char status[192];
            state->find_match_index = chosen_index;
            if (preserve_scroll)
                render_current_page_preserving_scroll(state);
            else
                render_current_page(state, FALSE);
            save_session(state);
            update_find_controls(state);
            snprintf(status, sizeof(status), "%s%d matches for \"%s\"", capped ? "First " : "", state->find_match_count,
                     needle);
            gtk_label_set_text(GTK_LABEL(state->status), status);
        }
    } else {
        char status[192];
        if (preserve_scroll)
            render_current_page_preserving_scroll(state);
        else
            render_current_page(state, FALSE);
        save_session(state);
        update_find_controls(state);
        snprintf(status, sizeof(status), "No %smatches for \"%s\"", state->search_regex ? "regex " : "", needle);
        gtk_label_set_text(GTK_LABEL(state->status), status);
    }
}

static void find_step(app_state* state, gboolean forward) {
    int next;
    if (!state->doc || state->find_match_count <= 0) return;
    next = state->find_match_index;
    if (next < 0)
        next = forward ? 0 : state->find_match_count - 1;
    else
        next = (next + (forward ? 1 : -1) + state->find_match_count) % state->find_match_count;
    jump_to_find_match(state, next);
}

static void find_prev_clicked(GtkButton* button, gpointer user_data) {
    (void)button;
    find_step((app_state*)user_data, FALSE);
}

static void find_next_clicked(GtkButton* button, gpointer user_data) {
    (void)button;
    find_step((app_state*)user_data, TRUE);
}

static void find_activate(GtkEntry* entry, gpointer user_data) {
    (void)entry;
    app_state* state = (app_state*)user_data;
    if (state->find_match_count > 0)
        find_step(state, TRUE);
    else
        start_find_for_current_query(state, -1, -1, TRUE, FALSE);
}

static gboolean find_debounce_idle(gpointer user_data) {
    app_state* state = (app_state*)user_data;
    state->find_debounce_id = 0;
    start_find_for_current_query(state, -1, -1, TRUE, FALSE);
    return G_SOURCE_REMOVE;
}

static void find_search_changed(GtkEntry* entry, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    const char* text;
    char* limited;
    if (state->suppress_find_changed) return;
    cancel_deferred_find(state);
    text = gtk_entry_get_text(entry);
    limited = dup_limited_utf8(text, MAX_FIND_QUERY_BYTES);
    g_free(state->search_text);
    state->search_text = limited;
    if (strlen(text) != strlen(state->search_text)) {
        state->suppress_find_changed = TRUE;
        gtk_entry_set_text(entry, state->search_text);
        state->suppress_find_changed = FALSE;
        gtk_label_set_text(GTK_LABEL(state->status), "Search query truncated.");
    }
    if (state->find_debounce_id) g_source_remove(state->find_debounce_id);
    state->find_debounce_id = g_timeout_add(120, find_debounce_idle, state);
    save_session(state);
}

static void find_regex_toggled(GtkToggleButton* button, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    state->search_regex = gtk_toggle_button_get_active(button);
    if (state->switching_tabs) return;
    update_toolbar_overflow_menu_state(state);
    update_controls(state);
    start_find_for_current_query(state, -1, state->page_index, TRUE, FALSE);
}

static gboolean check_widget_active(GtkWidget* widget) {
    if (GTK_IS_CHECK_MENU_ITEM(widget)) return gtk_check_menu_item_get_active(GTK_CHECK_MENU_ITEM(widget));
    return gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(widget));
}

static void set_regex_multiline_widget_active(GtkWidget* widget, gboolean active) {
    if (!widget) return;
    if (GTK_IS_CHECK_MENU_ITEM(widget)) {
        if (gtk_check_menu_item_get_active(GTK_CHECK_MENU_ITEM(widget)) != active)
            gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(widget), active);
    } else if (gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(widget)) != active) {
        gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(widget), active);
    }
}

static void find_regex_multiline_toggled(GtkWidget* widget, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    gboolean active = check_widget_active(widget);

    state->search_regex_multiline = active;
    if (widget != state->search_regex_multiline_check)
        set_regex_multiline_widget_active(state->search_regex_multiline_check, active);
    if (widget != state->search_regex_multiline_item)
        set_regex_multiline_widget_active(state->search_regex_multiline_item, active);

    if (state->switching_tabs) return;
    update_toolbar_overflow_menu_state(state);
    start_find_for_current_query(state, -1, state->page_index, TRUE, FALSE);
}

static void overflow_button_activate(GtkMenuItem* item, gpointer user_data) {
    GtkWidget* button = GTK_WIDGET(user_data);
    (void)item;
    if (GTK_IS_BUTTON(button)) gtk_button_clicked(GTK_BUTTON(button));
}

static void overflow_continuous_toggled(GtkCheckMenuItem* item, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    if (state->updating_overflow_controls || !state->continuous) return;
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(state->continuous), gtk_check_menu_item_get_active(item));
}

static void overflow_search_regex_toggled(GtkCheckMenuItem* item, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    if (state->updating_overflow_controls || !state->search_regex_check) return;
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(state->search_regex_check), gtk_check_menu_item_get_active(item));
}

static void overflow_search_regex_multiline_toggled(GtkCheckMenuItem* item, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    if (state->updating_overflow_controls || !state->search_regex_multiline_check) return;
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(state->search_regex_multiline_check),
                                 gtk_check_menu_item_get_active(item));
}

static void overflow_marker_strip_toggled(GtkCheckMenuItem* item, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    if (state->updating_overflow_controls || state->updating_marker_strip_control) return;
    state->show_find_markers = gtk_check_menu_item_get_active(item);
    update_find_controls(state);
    save_settings(state);
}

static void overflow_minimap_toggled(GtkCheckMenuItem* item, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    if (state->updating_overflow_controls || state->updating_minimap_control) return;
    if (!state->doc || state->presentation_mode) {
        update_minimap_controls(state);
        return;
    }
    state->show_minimap = gtk_check_menu_item_get_active(item);
    update_minimap_controls(state);
    save_settings(state);
}

static void overflow_side_panel_toggled(GtkCheckMenuItem* item, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    gboolean has_panel;
    if (state->updating_overflow_controls || state->updating_sidebar_menu) return;
    has_panel = state->doc && (state->outline.count > 0 || state->comments.count > 0);
    if (!has_panel || state->presentation_mode) {
        update_sidebar_menu_items(state);
        return;
    }
    state->show_sidebar = gtk_check_menu_item_get_active(item);
    rebuild_sidebar(state);
    save_settings(state);
}

static void overflow_fit_mode_toggled(GtkCheckMenuItem* item, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    int fit_mode = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(item), "sumatra-fit-mode"));
    if (state->updating_overflow_controls || !gtk_check_menu_item_get_active(item) || !state->fit_mode) return;
    gtk_combo_box_set_active(GTK_COMBO_BOX(state->fit_mode), fit_mode);
}

static gboolean find_search_key_press(GtkWidget* widget, GdkEventKey* event, gpointer user_data) {
    (void)widget;
    app_state* state = (app_state*)user_data;

    if (event->keyval != GDK_KEY_Escape) return FALSE;
    if (current_search_text(state)[0] != '\0') {
        set_search_entry_text(state, "");
        start_find_for_current_query(state, -1, -1, TRUE, FALSE);
    }
    if (state->scroll) gtk_widget_grab_focus(state->scroll);
    return TRUE;
}

static void draw_find_marker(cairo_t* cr, double width, double height, int page_count, int page_index,
                             gboolean active) {
    double mark_height = 3.0;
    double y;

    if (page_count <= 0) return;
    y = ((double)page_index + 0.5) / (double)page_count * MAX(1.0, height - mark_height);
    y = MAX(0.0, MIN(y, height - mark_height));
    if (active)
        cairo_set_source_rgba(cr, 1.0, 0.45, 0.02, 0.95);
    else
        cairo_set_source_rgba(cr, 1.0, 0.86, 0.08, 0.90);
    cairo_rectangle(cr, 1.0, y, MAX(1.0, width - 2.0), mark_height);
    cairo_fill(cr);
}

static gboolean find_markers_draw(GtkWidget* widget, cairo_t* cr, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    GtkAllocation allocation;
    int page_count = state->doc ? spdf_page_count(state->doc) : 0;
    double width;
    double height;

    if (!state->doc || state->find_match_count <= 0 || page_count <= 0) return TRUE;

    gtk_widget_get_allocation(widget, &allocation);
    width = (double)allocation.width;
    height = (double)allocation.height;

    cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.08);
    cairo_rectangle(cr, 0.0, 0.0, width, height);
    cairo_fill(cr);

    for (int i = 0; i < state->find_match_count; ++i) {
        if (i == state->find_match_index) continue;
        draw_find_marker(cr, width, height, page_count, state->find_matches[i].page_index, FALSE);
    }
    if (state->find_match_index >= 0 && state->find_match_index < state->find_match_count) {
        draw_find_marker(cr, width, height, page_count, state->find_matches[state->find_match_index].page_index, TRUE);
    }

    return TRUE;
}

typedef struct minimap_layout {
    int page_count;
    double width;
    double height;
    double scale;
    double gap;
    double content_top;
    double content_height;
} minimap_layout;

static gboolean minimap_page_size(app_state* state, int page_index, double* width, double* height) {
    char err[256];
    float page_width = 612.0f;
    float page_height = 792.0f;
    int page_count;

    if (!state || !state->doc) return FALSE;
    page_count = spdf_page_count(state->doc);
    if (page_count > MINIMAP_PRECISE_PAGE_LIMIT && page_index != state->page_index) {
        if (!spdf_page_size(state->doc, state->page_index, &page_width, &page_height, err, sizeof(err)) ||
            page_width <= 0 || page_height <= 0) {
            page_width = 612.0f;
            page_height = 792.0f;
        }
    } else if (!spdf_page_size(state->doc, page_index, &page_width, &page_height, err, sizeof(err)) ||
               page_width <= 0 || page_height <= 0) {
        if (!spdf_page_size(state->doc, state->page_index, &page_width, &page_height, err, sizeof(err)) ||
            page_width <= 0 || page_height <= 0) {
            page_width = 612.0f;
            page_height = 792.0f;
        }
    }
    if (width) *width = page_width;
    if (height) *height = page_height;
    return TRUE;
}

static double minimap_scroll_fraction(app_state* state) {
    GtkAdjustment* vadj;
    int page_count;
    double max_value;
    double local = 0.0;

    if (!state || !state->doc || !state->scroll) return 0.0;
    page_count = spdf_page_count(state->doc);
    if (page_count <= 1) page_count = 1;
    vadj = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(state->scroll));
    if (!vadj) return 0.0;

    max_value = MAX(0.0, gtk_adjustment_get_upper(vadj) - gtk_adjustment_get_page_size(vadj));
    if (max_value > 0.0) local = gtk_adjustment_get_value(vadj) / max_value;
    local = MAX(0.0, MIN(local, 1.0));
    if (state->continuous_mode) return local;
    return MAX(0.0, MIN(((double)state->page_index + local) / (double)page_count, 1.0));
}

static gboolean minimap_measure(app_state* state, GtkWidget* widget, minimap_layout* layout) {
    GtkAllocation allocation;
    double widest = 1.0;
    double content_height = 0.0;
    double available;
    double offset = 0.0;

    if (!state || !state->doc || !widget || !layout) return FALSE;
    gtk_widget_get_allocation(widget, &allocation);
    if (allocation.width < 16 || allocation.height < 16) return FALSE;

    layout->page_count = spdf_page_count(state->doc);
    if (layout->page_count <= 0) return FALSE;
    layout->width = allocation.width;
    layout->height = allocation.height;
    layout->gap = 4.0;

    if (layout->page_count > MINIMAP_PRECISE_PAGE_LIMIT) {
        double page_width;
        double page_height;
        minimap_page_size(state, state->page_index, &page_width, &page_height);
        widest = MAX(widest, page_width);
        layout->scale = MAX(0.001, (layout->width - 18.0) / widest);
        content_height = (double)layout->page_count * MAX(1.0, page_height * layout->scale);
    } else {
        for (int i = 0; i < layout->page_count; ++i) {
            double page_width;
            double page_height;
            minimap_page_size(state, i, &page_width, &page_height);
            widest = MAX(widest, page_width);
        }

        layout->scale = MAX(0.001, (layout->width - 18.0) / widest);
        for (int i = 0; i < layout->page_count; ++i) {
            double page_width;
            double page_height;
            minimap_page_size(state, i, &page_width, &page_height);
            content_height += MAX(1.0, page_height * layout->scale);
        }
    }
    content_height += layout->gap * MAX(0, layout->page_count - 1);
    layout->content_height = MAX(1.0, content_height);

    available = MAX(1.0, layout->height - 16.0);
    if (layout->content_height > available)
        offset = minimap_scroll_fraction(state) * MAX(0.0, layout->content_height - available);
    layout->content_top =
        layout->content_height < available ? floor((layout->height - layout->content_height) * 0.5) : 8.0 - offset;
    return TRUE;
}

static void minimap_page_rect(app_state* state, minimap_layout* layout, int page_index, double* x, double* y,
                              double* width, double* height) {
    double page_y = 0.0;
    double page_width = 612.0;
    double page_height = 792.0;

    if (layout->page_count > MINIMAP_PRECISE_PAGE_LIMIT) {
        minimap_page_size(state, page_index, &page_width, &page_height);
        page_y = (double)page_index * (MAX(1.0, page_height * layout->scale) + layout->gap);
    } else {
        for (int i = 0; i <= page_index && i < layout->page_count; ++i) {
            minimap_page_size(state, i, &page_width, &page_height);
            if (i == page_index) break;
            page_y += MAX(1.0, page_height * layout->scale) + layout->gap;
        }
    }

    page_width = MAX(1.0, page_width * layout->scale);
    page_height = MAX(1.0, page_height * layout->scale);
    if (x) *x = floor((layout->width - page_width) * 0.5);
    if (y) *y = layout->content_top + page_y;
    if (width) *width = page_width;
    if (height) *height = page_height;
}

static void minimap_draw_placeholder(cairo_t* cr, double x, double y, double width, double height) {
    int lines;
    double line_y;

    if (width < 10.0 || height < 6.0) return;
    cairo_set_source_rgba(cr, 0.50, 0.50, 0.50, 0.24);
    lines = (int)MAX(2.0, MIN(16.0, floor(height / 7.0)));
    line_y = y + MAX(2.0, height * 0.08);
    for (int i = 0; i < lines; ++i) {
        double factor = i % 5 == 4 ? 0.56 : 0.78;
        double line_height = MAX(1.0, height * 0.018);
        cairo_rectangle(cr, x + width * 0.12, line_y, width * factor, line_height);
        cairo_fill(cr);
        line_y += MAX(3.0, height / (double)(lines + 2));
        if (line_y > y + height - 2.0) break;
    }
}

static void minimap_visible_rect(app_state* state, minimap_layout* layout, double* x, double* y, double* width,
                                 double* height) {
    GtkAdjustment* vadj;
    double rx = 5.0;
    double ry = 0.0;
    double rw = MAX(1.0, layout->width - 10.0);
    double rh = 12.0;

    if (!state || !state->scroll) return;
    vadj = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(state->scroll));
    if (state->continuous_mode && vadj) {
        double upper = MAX(1.0, gtk_adjustment_get_upper(vadj));
        rh = MAX(10.0, gtk_adjustment_get_page_size(vadj) / upper * layout->content_height);
        rh = MIN(layout->height - 2.0, rh);
        ry = layout->content_top + minimap_scroll_fraction(state) * MAX(0.0, layout->content_height - rh);
    } else {
        double page_x;
        double page_y;
        double page_width;
        double page_height;
        double local = 0.0;
        double page_widget_height = 0.0;
        minimap_page_rect(state, layout, state->page_index, &page_x, &page_y, &page_width, &page_height);
        if (vadj) {
            double max_value = MAX(0.0, gtk_adjustment_get_upper(vadj) - gtk_adjustment_get_page_size(vadj));
            if (max_value > 0.0) local = gtk_adjustment_get_value(vadj) / max_value;
            if (page_widget_geometry(state, state->page_index, NULL, NULL, NULL, &page_widget_height) &&
                page_widget_height > 1.0) {
                rh = MAX(10.0, gtk_adjustment_get_page_size(vadj) / page_widget_height * page_height);
            }
        }
        rh = MIN(page_height, rh);
        rx = page_x;
        rw = page_width;
        ry = page_y + MAX(0.0, MIN(local, 1.0)) * MAX(0.0, page_height - rh);
    }

    if (x) *x = MAX(1.0, rx);
    if (y) *y = MAX(1.0, MIN(ry, layout->height - 1.0));
    if (width) *width = MIN(rw, layout->width - 2.0);
    if (height) *height = MAX(1.0, MIN(rh, layout->height - MAX(1.0, ry) - 1.0));
}

static gboolean minimap_draw(GtkWidget* widget, cairo_t* cr, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    minimap_layout layout;
    double vx;
    double vy;
    double vw;
    double vh;

    if (!minimap_measure(state, widget, &layout)) return TRUE;

    cairo_set_source_rgb(cr, 0.94, 0.94, 0.94);
    cairo_rectangle(cr, 0.0, 0.0, layout.width, layout.height);
    cairo_fill(cr);
    cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.16);
    cairo_rectangle(cr, 0.0, 0.0, 1.0, layout.height);
    cairo_fill(cr);

    double page_top = layout.content_top;
    int start_page = 0;
    int end_page = layout.page_count;
    double uniform_step = 0.0;
    if (layout.page_count > MINIMAP_PRECISE_PAGE_LIMIT) {
        double page_width;
        double page_height;
        minimap_page_size(state, state->page_index, &page_width, &page_height);
        uniform_step = MAX(1.0, page_height * layout.scale) + layout.gap;
        start_page = (int)floor((-layout.content_top) / MAX(1.0, uniform_step)) - 1;
        end_page = (int)ceil((layout.height - layout.content_top) / MAX(1.0, uniform_step)) + 1;
        start_page = MAX(0, MIN(start_page, layout.page_count));
        end_page = MAX(start_page, MIN(end_page, layout.page_count));
        page_top = layout.content_top + (double)start_page * uniform_step;
    }
    for (int i = start_page; i < end_page; ++i) {
        double x;
        double y = page_top;
        double width;
        double height;
        double page_width;
        double page_height;
        minimap_page_size(state, i, &page_width, &page_height);
        width = MAX(1.0, page_width * layout.scale);
        height = MAX(1.0, page_height * layout.scale);
        x = floor((layout.width - width) * 0.5);
        if (y <= layout.height && y + height >= 0.0) {
            cairo_set_source_rgb(cr, 1.0, 1.0, 1.0);
            cairo_rectangle(cr, x, y, width, height);
            cairo_fill(cr);
            minimap_draw_placeholder(cr, x, y, width, height);
            cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, i == state->page_index ? 0.36 : 0.14);
            cairo_set_line_width(cr, i == state->page_index ? 1.5 : 1.0);
            cairo_rectangle(cr, x + 0.5, y + 0.5, MAX(1.0, width - 1.0), MAX(1.0, height - 1.0));
            cairo_stroke(cr);
        }
        page_top += uniform_step > 0.0 ? uniform_step : height + layout.gap;
    }

    minimap_visible_rect(state, &layout, &vx, &vy, &vw, &vh);
    cairo_set_source_rgba(cr, 0.18, 0.48, 0.86, 0.18);
    cairo_rectangle(cr, vx, vy, vw, vh);
    cairo_fill(cr);
    cairo_set_source_rgba(cr, 0.06, 0.36, 0.76, 0.95);
    cairo_set_line_width(cr, 1.3);
    cairo_rectangle(cr, vx + 0.5, vy + 0.5, MAX(1.0, vw - 1.0), MAX(1.0, vh - 1.0));
    cairo_stroke(cr);

    return TRUE;
}

static gboolean minimap_should_use_precision_drag(minimap_layout* layout) {
    return layout && layout->page_count >= MINIMAP_PRECISION_DRAG_PAGE_THRESHOLD;
}

static double minimap_precision_drag_base_scale(int page_count) {
    return clamp_double(20.0 / MAX(1, page_count), 0.28, 0.78);
}

static double minimap_event_time_seconds(guint32 event_time) {
    if (event_time > 0) return (double)event_time / 1000.0;
    return (double)g_get_monotonic_time() / 1000000.0;
}

static double minimap_drag_delta_time(app_state* state, double event_time) {
    double delta = event_time - state->minimap_drag_last_time;
    if (!isfinite(delta) || delta <= 0.0) delta = 1.0 / 60.0;
    return clamp_double(delta, 1.0 / 240.0, 1.0 / 20.0);
}

static double minimap_precision_catchup_blend(app_state* state, double delta_y, double distance_to_raw,
                                              double event_time) {
    double delta_t;
    double speed;
    double velocity_blend;
    double distance_blend;

    delta_t = minimap_drag_delta_time(state, event_time);
    speed = fabs(delta_y) / delta_t;
    velocity_blend = smoothstep_double((speed - 70.0) / (360.0 - 70.0));
    distance_blend = smoothstep_double((distance_to_raw - 6.0) / (24.0 - 6.0));
    return MAX(velocity_blend, distance_blend);
}

static void minimap_scroll_to_y(app_state* state, GtkWidget* widget, double widget_y) {
    minimap_layout layout;
    double unscrolled_y;
    double fraction;

    if (!state || !state->doc || !state->scroll || !minimap_measure(state, widget, &layout)) return;

    if (widget_y <= 0.0) {
        fraction = 0.0;
    } else if (widget_y >= layout.height - 1.0) {
        fraction = 1.0;
    } else {
        unscrolled_y = widget_y - layout.content_top;
        fraction = MAX(0.0, MIN(unscrolled_y / layout.content_height, 1.0));
    }

    if (state->continuous_mode) {
        GtkAdjustment* vadj = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(state->scroll));
        double max_value = MAX(0.0, gtk_adjustment_get_upper(vadj) - gtk_adjustment_get_page_size(vadj));
        double target = fraction * gtk_adjustment_get_upper(vadj) - gtk_adjustment_get_page_size(vadj) * 0.5;
        if (fraction <= 0.0)
            target = 0.0;
        else if (fraction >= 1.0)
            target = max_value;
        gtk_adjustment_set_value(vadj, MAX(0.0, MIN(target, max_value)));
        gtk_widget_queue_draw(widget);
        return;
    }

    unscrolled_y = fraction * layout.content_height;
    if (layout.page_count > MINIMAP_PRECISE_PAGE_LIMIT) {
        double page_width;
        double page_height;
        double step;
        int page_index;
        double page_y;
        minimap_page_size(state, state->page_index, &page_width, &page_height);
        step = MAX(1.0, page_height * layout.scale) + layout.gap;
        page_index = MAX(0, MIN((int)floor(unscrolled_y / MAX(1.0, step)), layout.page_count - 1));
        page_y = unscrolled_y - (double)page_index * step;
        if (state->page_index != page_index) {
            state->page_index = page_index;
            render_current_page(state, FALSE);
        }
        scroll_to_page_point_preserving_horizontal(
            state, page_index, page_height * MAX(0.0, MIN(page_y / MAX(1.0, page_height * layout.scale), 1.0)));
        save_session(state);
        return;
    }
    for (int i = 0; i < layout.page_count; ++i) {
        double page_width;
        double page_height;
        double mini_height;
        minimap_page_size(state, i, &page_width, &page_height);
        mini_height = MAX(1.0, page_height * layout.scale);
        if (i == layout.page_count - 1 || unscrolled_y <= mini_height) {
            double page_fraction = MAX(0.0, MIN(unscrolled_y / mini_height, 1.0));
            if (state->page_index != i) {
                state->page_index = i;
                render_current_page(state, FALSE);
            }
            scroll_to_page_point_preserving_horizontal(state, i, page_height * page_fraction);
            save_session(state);
            return;
        }
        unscrolled_y -= mini_height + layout.gap;
    }
}

static void minimap_scroll_to_top_fraction(app_state* state, GtkWidget* widget, double fraction) {
    minimap_layout layout;
    double unscrolled_y;

    if (!state || !state->doc || !state->scroll || !minimap_measure(state, widget, &layout)) return;
    fraction = clamp_double(fraction, 0.0, 1.0);

    if (state->continuous_mode) {
        GtkAdjustment* vadj = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(state->scroll));
        double max_value = MAX(0.0, gtk_adjustment_get_upper(vadj) - gtk_adjustment_get_page_size(vadj));
        gtk_adjustment_set_value(vadj, fraction * max_value);
        gtk_widget_queue_draw(widget);
        return;
    }

    unscrolled_y = fraction * layout.content_height;
    if (layout.page_count > MINIMAP_PRECISE_PAGE_LIMIT) {
        double page_width;
        double page_height;
        double step;
        int page_index;
        double page_y;
        minimap_page_size(state, state->page_index, &page_width, &page_height);
        step = MAX(1.0, page_height * layout.scale) + layout.gap;
        page_index = MAX(0, MIN((int)floor(unscrolled_y / MAX(1.0, step)), layout.page_count - 1));
        page_y = unscrolled_y - (double)page_index * step;
        if (state->page_index != page_index) {
            state->page_index = page_index;
            render_current_page(state, FALSE);
        }
        scroll_to_page_point_preserving_horizontal(
            state, page_index, page_height * MAX(0.0, MIN(page_y / MAX(1.0, page_height * layout.scale), 1.0)));
        save_session(state);
        return;
    }

    for (int i = 0; i < layout.page_count; ++i) {
        double page_width;
        double page_height;
        double mini_height;
        minimap_page_size(state, i, &page_width, &page_height);
        mini_height = MAX(1.0, page_height * layout.scale);
        if (i == layout.page_count - 1 || unscrolled_y <= mini_height) {
            double page_fraction = MAX(0.0, MIN(unscrolled_y / mini_height, 1.0));
            if (state->page_index != i) {
                state->page_index = i;
                render_current_page(state, FALSE);
            }
            scroll_to_page_point_preserving_horizontal(state, i, page_height * page_fraction);
            save_session(state);
            return;
        }
        unscrolled_y -= mini_height + layout.gap;
    }
}

static void minimap_drag_visible_rect_to_y(app_state* state, GtkWidget* widget, double widget_y, guint32 event_time) {
    minimap_layout layout;
    double vx;
    double vy;
    double vw;
    double vh;
    double min_top;
    double max_top;
    double thumb_height;
    double raw_top;
    double delta_y;
    double event_time_seconds;
    double precision_top;
    double catchup_blend;
    double center_y;

    if (!state || !state->doc || !state->scroll || !minimap_measure(state, widget, &layout)) return;
    if (!state->minimap_dragging_visible_rect || !minimap_should_use_precision_drag(&layout)) {
        minimap_scroll_to_y(state, widget, widget_y);
        return;
    }

    minimap_visible_rect(state, &layout, &vx, &vy, &vw, &vh);
    (void)vx;
    (void)vy;
    (void)vw;
    thumb_height = MIN(vh, MAX(1.0, layout.height - 2.0));
    min_top = 1.0;
    max_top = MAX(min_top, layout.height - thumb_height - 1.0);
    raw_top = widget_y - state->minimap_drag_offset_top;

    event_time_seconds = minimap_event_time_seconds(event_time);
    if (raw_top <= min_top) {
        state->minimap_drag_thumb_top = min_top;
        state->minimap_drag_last_y = widget_y;
        state->minimap_drag_last_time = event_time_seconds;
        minimap_scroll_to_top_fraction(state, widget, 0.0);
        return;
    }
    if (raw_top >= max_top) {
        state->minimap_drag_thumb_top = max_top;
        state->minimap_drag_last_y = widget_y;
        state->minimap_drag_last_time = event_time_seconds;
        minimap_scroll_to_top_fraction(state, widget, 1.0);
        return;
    }

    delta_y = widget_y - state->minimap_drag_last_y;
    precision_top = state->minimap_drag_thumb_top + delta_y * minimap_precision_drag_base_scale(layout.page_count);
    catchup_blend = minimap_precision_catchup_blend(state, delta_y, fabs(raw_top - precision_top), event_time_seconds);
    state->minimap_drag_thumb_top =
        clamp_double(precision_top + (raw_top - precision_top) * catchup_blend, min_top, max_top);
    state->minimap_drag_last_y = widget_y;
    state->minimap_drag_last_time = event_time_seconds;

    center_y = state->minimap_drag_thumb_top + thumb_height * 0.5;
    minimap_scroll_to_y(state, widget, center_y);
}

static gboolean minimap_button_press(GtkWidget* widget, GdkEventButton* event, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    minimap_layout layout;
    double vx;
    double vy;
    double vw;
    double vh;

    if (!state->doc || event->button != 1) return FALSE;
    state->minimap_dragging = TRUE;
    state->minimap_dragging_visible_rect = FALSE;
    if (minimap_measure(state, widget, &layout)) {
        minimap_visible_rect(state, &layout, &vx, &vy, &vw, &vh);
        if (event->x >= vx && event->x <= vx + vw && event->y >= vy && event->y <= vy + vh) {
            state->minimap_dragging_visible_rect = TRUE;
            state->minimap_drag_offset_top = event->y - vy;
            state->minimap_drag_thumb_top = vy;
            state->minimap_drag_last_y = event->y;
            state->minimap_drag_last_time = minimap_event_time_seconds(event->time);
        } else {
            minimap_scroll_to_y(state, widget, event->y);
        }
    } else {
        minimap_scroll_to_y(state, widget, event->y);
    }
    if (state->scroll) gtk_widget_grab_focus(state->scroll);
    return TRUE;
}

static gboolean minimap_motion(GtkWidget* widget, GdkEventMotion* event, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    if (!state->minimap_dragging) return FALSE;
    if (state->minimap_dragging_visible_rect)
        minimap_drag_visible_rect_to_y(state, widget, event->y, event->time);
    else
        minimap_scroll_to_y(state, widget, event->y);
    return TRUE;
}

static gboolean minimap_button_release(GtkWidget* widget, GdkEventButton* event, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    (void)widget;
    if (event->button == 1) {
        state->minimap_dragging = FALSE;
        state->minimap_dragging_visible_rect = FALSE;
        state->minimap_drag_offset_top = 0.0;
        state->minimap_drag_thumb_top = 0.0;
        state->minimap_drag_last_y = 0.0;
        state->minimap_drag_last_time = 0.0;
        return TRUE;
    }
    return FALSE;
}

static gboolean minimap_scroll_event(GtkWidget* widget, GdkEventScroll* event, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    GtkAdjustment* vadj;
    double delta;

    (void)widget;
    if (!state->doc) return FALSE;
    if (!state->continuous_mode) {
        if (event->direction == GDK_SCROLL_DOWN || event->delta_y > 0)
            next_clicked(NULL, state);
        else if (event->direction == GDK_SCROLL_UP || event->delta_y < 0)
            previous_clicked(NULL, state);
        return TRUE;
    }

    vadj = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(state->scroll));
    delta = event->delta_y != 0.0 ? event->delta_y * 42.0 : (event->direction == GDK_SCROLL_UP ? -42.0 : 42.0);
    gtk_adjustment_set_value(vadj, MAX(0.0, MIN(gtk_adjustment_get_value(vadj) + delta,
                                                gtk_adjustment_get_upper(vadj) - gtk_adjustment_get_page_size(vadj))));
    return TRUE;
}

static gboolean external_uri_scheme_allowed(const char* uri) {
    const char* colon;
    gsize len;
    if (!uri || !*uri) return FALSE;
    colon = strchr(uri, ':');
    if (!colon || colon == uri) return FALSE;
    for (const char* p = uri; p < colon; ++p) {
        if (!g_ascii_isalnum(*p) && *p != '+' && *p != '-' && *p != '.') return FALSE;
    }
    len = (gsize)(colon - uri);
    return (len == 4 && g_ascii_strncasecmp(uri, "http", len) == 0) ||
           (len == 5 && g_ascii_strncasecmp(uri, "https", len) == 0) ||
           (len == 6 && g_ascii_strncasecmp(uri, "mailto", len) == 0);
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

static void update_text_selection(app_state* state, int page_index, double end_x, double end_y, gboolean rerender) {
    char err[1024];
    spdf_rect rects[256];
    char* text = NULL;
    int count;

    if (!state || !state->doc || page_index < 0) return;

    count =
        spdf_select_page_text(state->doc, page_index, (float)state->selection_start_x, (float)state->selection_start_y,
                              (float)end_x, (float)end_y, rects, 256, &text, err, sizeof(err));
    g_free(state->selected_text);
    state->selected_text = NULL;
    state->selection_rect_count = 0;

    if (count > 0 && text && text[0] != '\0') {
        state->selection_page_index = page_index;
        state->selection_rect_count = MIN(count, 256);
        memcpy(state->selection_rects, rects, (gsize)state->selection_rect_count * sizeof(spdf_rect));
        state->selected_text = g_strdup(text);
    } else {
        state->selection_page_index = state->selecting ? page_index : -1;
    }

    if (text) spdf_free_string(text);
    if (count < 0) gtk_label_set_text(GTK_LABEL(state->status), err[0] ? err : "Could not select text.");
    if (rerender) render_current_page_preserving_scroll(state);
}

static gboolean open_link_at_page_point(app_state* state, int page_index, double page_x, double page_y, guint32 time) {
    char err[512];
    spdf_link_target target;
    int hit;

    if (!state || !state->doc || page_index < 0) return FALSE;
    hit = spdf_link_at_point(state->doc, page_index, (float)page_x, (float)page_y, &target, err, sizeof(err));
    if (hit <= 0) {
        if (hit < 0 && err[0]) gtk_label_set_text(GTK_LABEL(state->status), err);
        return FALSE;
    }

    if (target.kind == SPDF_LINK_URI && target.uri) {
        GError* error = NULL;
        if (!external_uri_scheme_allowed(target.uri)) {
            gtk_label_set_text(GTK_LABEL(state->status), "Blocked link with unsupported URI scheme.");
            spdf_free_link_target(&target);
            return TRUE;
        }
        if (!gtk_show_uri_on_window(GTK_WINDOW(state->window), target.uri, time ? time : GDK_CURRENT_TIME, &error)) {
            show_error(GTK_WINDOW(state->window), "Could not open link", error ? error->message : "");
            if (error) g_error_free(error);
        }
        spdf_free_link_target(&target);
        return TRUE;
    }

    if (target.kind == SPDF_LINK_INTERNAL && target.page_index >= 0) {
        int page_count = spdf_page_count(state->doc);
        gboolean has_point = isfinite(target.x) && isfinite(target.y);
        state->page_index = MAX(0, MIN(target.page_index, page_count - 1));
        render_current_page(state, FALSE);
        scroll_to_page_point(state, state->page_index, target.x, target.y, has_point);
        save_session(state);
        spdf_free_link_target(&target);
        return TRUE;
    }

    spdf_free_link_target(&target);
    return FALSE;
}

static gboolean link_at_page_point(app_state* state, int page_index, double page_x, double page_y) {
    char err[512];
    spdf_link_target target;
    int hit;
    gboolean has_link;

    if (!state || !state->doc || page_index < 0) return FALSE;
    hit = spdf_link_at_point(state->doc, page_index, (float)page_x, (float)page_y, &target, err, sizeof(err));
    if (hit <= 0) return FALSE;
    has_link =
        (target.kind == SPDF_LINK_URI && target.uri) || (target.kind == SPDF_LINK_INTERNAL && target.page_index >= 0);
    spdf_free_link_target(&target);
    return has_link;
}

static void set_page_link_cursor(GtkWidget* widget, gboolean over_link) {
    GdkWindow* window;

    if (!widget) return;
    window = gtk_widget_get_window(widget);
    if (!window) return;
    if (over_link) {
        GdkDisplay* display = gtk_widget_get_display(widget);
        GdkCursor* cursor = gdk_cursor_new_for_display(display, GDK_HAND2);
        gdk_window_set_cursor(window, cursor);
        g_object_unref(cursor);
    } else {
        gdk_window_set_cursor(window, NULL);
    }
}

static char* prompt_for_comment_text(app_state* state, const char* default_text) {
    GtkWidget* dialog;
    GtkWidget* content;
    GtkWidget* label;
    GtkWidget* scroll;
    GtkWidget* text_view;
    GtkTextBuffer* buffer;
    char* result = NULL;

    dialog = gtk_dialog_new_with_buttons("Add Comment", GTK_WINDOW(state->window), GTK_DIALOG_MODAL, "_Cancel",
                                         GTK_RESPONSE_CANCEL, "_Add", GTK_RESPONSE_ACCEPT, NULL);
    content = gtk_dialog_get_content_area(GTK_DIALOG(dialog));
    label = gtk_label_new("Enter the comment text.");
    scroll = gtk_scrolled_window_new(NULL, NULL);
    text_view = gtk_text_view_new();
    buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(text_view));

    gtk_label_set_xalign(GTK_LABEL(label), 0.0);
    gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(text_view), GTK_WRAP_WORD_CHAR);
    gtk_text_buffer_set_text(buffer, default_text ? default_text : "", -1);
    gtk_widget_set_size_request(scroll, 420, 130);
    gtk_widget_set_margin_start(label, 10);
    gtk_widget_set_margin_end(label, 10);
    gtk_widget_set_margin_top(label, 10);
    gtk_widget_set_margin_bottom(label, 6);
    gtk_widget_set_margin_start(scroll, 10);
    gtk_widget_set_margin_end(scroll, 10);
    gtk_widget_set_margin_bottom(scroll, 10);
    gtk_container_add(GTK_CONTAINER(scroll), text_view);
    gtk_box_pack_start(GTK_BOX(content), label, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(content), scroll, TRUE, TRUE, 0);
    gtk_dialog_set_default_response(GTK_DIALOG(dialog), GTK_RESPONSE_ACCEPT);
    gtk_widget_show_all(dialog);
    gtk_widget_grab_focus(text_view);
    {
        GtkTextIter start;
        GtkTextIter end;
        gtk_text_buffer_get_bounds(buffer, &start, &end);
        gtk_text_buffer_select_range(buffer, &start, &end);
    }

    if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT) {
        GtkTextIter start;
        GtkTextIter end;
        gtk_text_buffer_get_bounds(buffer, &start, &end);
        result = gtk_text_buffer_get_text(buffer, &start, &end, FALSE);
        g_strstrip(result);
        if (!result[0]) {
            g_free(result);
            result = NULL;
        }
    }
    gtk_widget_destroy(dialog);
    return result;
}

static void free_comment_edit_result(comment_edit_result* result) {
    if (!result) return;
    g_free(result->author);
    g_free(result->text);
    g_free(result);
}

static const char* fallback_comment_author(void) {
    const char* author = g_get_real_name();
    if (!author || !*author || strcmp(author, "Unknown") == 0) author = g_get_user_name();
    return author ? author : "";
}

static const char* current_comment_author(app_state* state) {
    return state && state->comment_author && state->comment_author[0] ? state->comment_author
                                                                      : fallback_comment_author();
}

static comment_edit_result* prompt_for_comment_editor(app_state* state, const char* title, const char* button_title,
                                                      const char* author, const char* text) {
    GtkWidget* dialog;
    GtkWidget* content;
    GtkWidget* author_label;
    GtkWidget* author_entry;
    GtkWidget* comment_label;
    GtkWidget* scroll;
    GtkWidget* text_view;
    GtkTextBuffer* buffer;
    comment_edit_result* result = NULL;

    dialog = gtk_dialog_new_with_buttons(title ? title : "Comment", GTK_WINDOW(state->window), GTK_DIALOG_MODAL,
                                         "_Cancel", GTK_RESPONSE_CANCEL, button_title ? button_title : "_Save",
                                         GTK_RESPONSE_ACCEPT, NULL);
    content = gtk_dialog_get_content_area(GTK_DIALOG(dialog));
    author_label = gtk_label_new("Author");
    author_entry = gtk_entry_new();
    comment_label = gtk_label_new("Comment");
    scroll = gtk_scrolled_window_new(NULL, NULL);
    text_view = gtk_text_view_new();
    buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(text_view));

    gtk_label_set_xalign(GTK_LABEL(author_label), 0.0);
    gtk_label_set_xalign(GTK_LABEL(comment_label), 0.0);
    gtk_entry_set_text(GTK_ENTRY(author_entry), author ? author : "");
    gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(text_view), GTK_WRAP_WORD_CHAR);
    gtk_text_buffer_set_text(buffer, text ? text : "", -1);
    gtk_widget_set_size_request(scroll, 420, 130);
    gtk_widget_set_margin_start(author_label, 10);
    gtk_widget_set_margin_end(author_label, 10);
    gtk_widget_set_margin_top(author_label, 10);
    gtk_widget_set_margin_bottom(author_label, 4);
    gtk_widget_set_margin_start(author_entry, 10);
    gtk_widget_set_margin_end(author_entry, 10);
    gtk_widget_set_margin_bottom(author_entry, 8);
    gtk_widget_set_margin_start(comment_label, 10);
    gtk_widget_set_margin_end(comment_label, 10);
    gtk_widget_set_margin_bottom(comment_label, 4);
    gtk_widget_set_margin_start(scroll, 10);
    gtk_widget_set_margin_end(scroll, 10);
    gtk_widget_set_margin_bottom(scroll, 10);
    gtk_container_add(GTK_CONTAINER(scroll), text_view);
    gtk_box_pack_start(GTK_BOX(content), author_label, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(content), author_entry, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(content), comment_label, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(content), scroll, TRUE, TRUE, 0);
    gtk_dialog_set_default_response(GTK_DIALOG(dialog), GTK_RESPONSE_ACCEPT);
    gtk_widget_show_all(dialog);
    gtk_widget_grab_focus(text_view);
    {
        GtkTextIter start;
        GtkTextIter end;
        gtk_text_buffer_get_bounds(buffer, &start, &end);
        gtk_text_buffer_select_range(buffer, &start, &end);
    }

    if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT) {
        GtkTextIter start;
        GtkTextIter end;
        char* result_text;
        char* result_author;

        gtk_text_buffer_get_bounds(buffer, &start, &end);
        result_text = gtk_text_buffer_get_text(buffer, &start, &end, FALSE);
        result_author = g_strdup(gtk_entry_get_text(GTK_ENTRY(author_entry)));
        g_strstrip(result_text);
        g_strstrip(result_author);
        if (result_text[0]) {
            result = g_new0(comment_edit_result, 1);
            result->author = result_author;
            result->text = result_text;
            result_author = NULL;
            result_text = NULL;
        }
        g_free(result_author);
        g_free(result_text);
    }
    gtk_widget_destroy(dialog);
    return result;
}

static void refresh_comments_after_edit(app_state* state, const char* success, const char* refresh_failure) {
    char err[1024];

    spdf_free_comments(&state->comments);
    if (spdf_load_comments(state->doc, &state->comments, err, sizeof(err)))
        gtk_label_set_text(GTK_LABEL(state->status), success);
    else
        gtk_label_set_text(GTK_LABEL(state->status), refresh_failure);
    rebuild_sidebar(state);
    render_current_page_preserving_scroll(state);
    update_controls(state);
    save_session(state);
}

static void add_comment_clicked(GtkMenuItem* item, gpointer user_data) {
    (void)item;
    app_state* state = (app_state*)user_data;
    gboolean has_selection = has_text_selection(state);
    int page_index = has_selection ? state->selection_page_index : state->context_page_index;
    char* comment;
    char err[1024];
    gboolean ok;

    if (!state->doc || !state->path || page_index < 0 || page_index >= spdf_page_count(state->doc)) return;

    comment = prompt_for_comment_text(state, has_selection ? state->selected_text : "");
    if (!comment) return;

    if (has_selection) {
        ok = spdf_add_highlight_comment(state->doc, page_index, state->selection_rects, state->selection_rect_count,
                                        comment, current_comment_author(state), err, sizeof(err));
    } else {
        ok = spdf_add_text_comment(state->doc, page_index, (float)state->context_page_x, (float)state->context_page_y,
                                   comment, current_comment_author(state), err, sizeof(err));
    }
    if (ok) ok = spdf_save_document(state->doc, state->path, err, sizeof(err));
    if (!ok) {
        show_error(GTK_WINDOW(state->window), "Could not add comment", err[0] ? err : "Unknown error");
        g_free(comment);
        return;
    }

    refresh_comments_after_edit(state, "Comment added.", "Comment added, but comments could not refresh.");
    g_free(comment);
}

static void set_comment_author_clicked(GtkMenuItem* item, gpointer user_data) {
    (void)item;
    app_state* state = (app_state*)user_data;
    GtkWidget* dialog;
    GtkWidget* content;
    GtkWidget* label;
    GtkWidget* entry;

    dialog = gtk_dialog_new_with_buttons("Set Author for Comments", GTK_WINDOW(state->window), GTK_DIALOG_MODAL,
                                         "_Cancel", GTK_RESPONSE_CANCEL, "_Save", GTK_RESPONSE_ACCEPT, NULL);
    content = gtk_dialog_get_content_area(GTK_DIALOG(dialog));
    label = gtk_label_new("New comments will use this author.");
    entry = gtk_entry_new();

    gtk_label_set_xalign(GTK_LABEL(label), 0.0);
    gtk_entry_set_text(GTK_ENTRY(entry), current_comment_author(state));
    gtk_widget_set_size_request(entry, 360, -1);
    gtk_widget_set_margin_start(label, 10);
    gtk_widget_set_margin_end(label, 10);
    gtk_widget_set_margin_top(label, 10);
    gtk_widget_set_margin_bottom(label, 6);
    gtk_widget_set_margin_start(entry, 10);
    gtk_widget_set_margin_end(entry, 10);
    gtk_widget_set_margin_bottom(entry, 10);
    gtk_box_pack_start(GTK_BOX(content), label, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(content), entry, FALSE, FALSE, 0);
    gtk_dialog_set_default_response(GTK_DIALOG(dialog), GTK_RESPONSE_ACCEPT);
    gtk_widget_show_all(dialog);
    gtk_widget_grab_focus(entry);

    if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT) {
        char* author = g_strdup(gtk_entry_get_text(GTK_ENTRY(entry)));
        g_strstrip(author);
        g_free(state->comment_author);
        state->comment_author = author;
        save_settings(state);
        gtk_label_set_text(GTK_LABEL(state->status), author[0] ? "Comment author saved." : "Comment author reset.");
    }
    gtk_widget_destroy(dialog);
}

static spdf_comment_item* comment_item_for_index(app_state* state, int comment_index) {
    if (!state || comment_index < 0) return NULL;
    for (int i = 0; i < state->comments.count; ++i) {
        if (state->comments.items[i].index == comment_index) return &state->comments.items[i];
    }
    return NULL;
}

static int comment_index_from_object(GObject* object) {
    int stored = GPOINTER_TO_INT(g_object_get_data(object, "comment-index"));
    return stored > 0 ? stored - 1 : -1;
}

static int comment_index_at_page_point(app_state* state, int page_index, double page_x, double page_y) {
    if (!state || page_index < 0) return -1;

    for (int i = 0; i < state->comments.count; ++i) {
        spdf_comment_item item = state->comments.items[i];
        double x0;
        double x1;
        double y0;
        double y1;

        if (item.page_index != page_index || item.index < 0) continue;
        x0 = MIN(item.bounds.x0, item.bounds.x1) - 3.0;
        x1 = MAX(item.bounds.x0, item.bounds.x1) + 3.0;
        y0 = MIN(item.bounds.y0, item.bounds.y1) - 3.0;
        y1 = MAX(item.bounds.y0, item.bounds.y1) + 3.0;
        if (x1 <= x0 || y1 <= y0) continue;
        if (page_x >= x0 && page_x <= x1 && page_y >= y0 && page_y <= y1) return item.index;
    }
    return -1;
}

static int comment_index_for_comment_action(GtkMenuItem* item, app_state* state) {
    int comment_index = item ? comment_index_from_object(G_OBJECT(item)) : -1;
    if (comment_index >= 0) return comment_index;
    return state ? state->context_comment_index : -1;
}

static void edit_comment_clicked(GtkMenuItem* item, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    int comment_index = comment_index_for_comment_action(item, state);
    spdf_comment_item* comment = comment_item_for_index(state, comment_index);
    comment_edit_result* result;
    const char* author;
    const char* text;
    char err[1024];
    gboolean ok;

    if (!state->doc || !state->path || !comment) return;

    author = comment->author && *comment->author ? comment->author : current_comment_author(state);
    text = comment->text && *comment->text ? comment->text : "";
    result = prompt_for_comment_editor(state, "Edit Comment", "_Save", author, text);
    if (!result) return;

    g_free(state->comment_author);
    state->comment_author = g_strdup(result->author ? result->author : "");
    ok = spdf_update_comment(state->doc, comment_index, result->text, result->author, err, sizeof(err));
    if (ok) ok = spdf_save_document(state->doc, state->path, err, sizeof(err));
    if (!ok) {
        show_error(GTK_WINDOW(state->window), "Could not edit comment", err[0] ? err : "Unknown error");
        free_comment_edit_result(result);
        return;
    }

    save_settings(state);
    refresh_comments_after_edit(state, "Comment updated.", "Comment updated, but comments could not refresh.");
    free_comment_edit_result(result);
}

static gboolean confirm_delete_comment(app_state* state) {
    GtkWidget* dialog;
    int response;

    dialog = gtk_message_dialog_new(GTK_WINDOW(state->window), GTK_DIALOG_MODAL, GTK_MESSAGE_WARNING, GTK_BUTTONS_NONE,
                                    "Delete comment?");
    gtk_message_dialog_format_secondary_text(
        GTK_MESSAGE_DIALOG(dialog), "This will remove the selected comment from the PDF and save the document.");
    gtk_dialog_add_buttons(GTK_DIALOG(dialog), "_Cancel", GTK_RESPONSE_CANCEL, "_Delete", GTK_RESPONSE_ACCEPT, NULL);
    gtk_dialog_set_default_response(GTK_DIALOG(dialog), GTK_RESPONSE_CANCEL);
    response = gtk_dialog_run(GTK_DIALOG(dialog));
    gtk_widget_destroy(dialog);
    return response == GTK_RESPONSE_ACCEPT;
}

static void delete_comment_clicked(GtkMenuItem* item, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    int comment_index = comment_index_for_comment_action(item, state);
    spdf_comment_item* comment = comment_item_for_index(state, comment_index);
    char err[1024];
    gboolean ok;

    if (!state->doc || !state->path || !comment) return;
    if (!confirm_delete_comment(state)) return;

    ok = spdf_delete_comment(state->doc, comment_index, err, sizeof(err));
    if (ok) ok = spdf_save_document(state->doc, state->path, err, sizeof(err));
    if (!ok) {
        show_error(GTK_WINDOW(state->window), "Could not delete comment", err[0] ? err : "Unknown error");
        return;
    }

    state->context_comment_index = -1;
    refresh_comments_after_edit(state, "Comment deleted.", "Comment deleted, but comments could not refresh.");
}

static gboolean comments_sidebar_button_press(GtkWidget* widget, GdkEventButton* event, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    GtkListBoxRow* row;
    int comment_index;
    GtkWidget* menu;
    GtkWidget* edit_comment;
    GtkWidget* delete_comment;

    if (event->button != 3) return FALSE;
    row = gtk_list_box_get_row_at_y(GTK_LIST_BOX(widget), (gint)event->y);
    if (!row) return FALSE;
    comment_index = comment_index_from_object(G_OBJECT(row));
    state->context_comment_index = comment_index;
    gtk_list_box_select_row(GTK_LIST_BOX(widget), row);

    menu = gtk_menu_new();
    edit_comment = gtk_menu_item_new_with_label("Edit Comment...");
    delete_comment = gtk_menu_item_new_with_label("Delete Comment...");
    gtk_widget_set_sensitive(edit_comment, state->doc != NULL && comment_index >= 0);
    gtk_widget_set_sensitive(delete_comment, state->doc != NULL && comment_index >= 0);
    if (comment_index >= 0) {
        g_object_set_data(G_OBJECT(edit_comment), "comment-index", GINT_TO_POINTER(comment_index + 1));
        g_object_set_data(G_OBJECT(delete_comment), "comment-index", GINT_TO_POINTER(comment_index + 1));
    }
    g_signal_connect(edit_comment, "activate", G_CALLBACK(edit_comment_clicked), state);
    g_signal_connect(delete_comment, "activate", G_CALLBACK(delete_comment_clicked), state);
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), edit_comment);
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), delete_comment);
    gtk_widget_show_all(menu);
    gtk_menu_popup_at_pointer(GTK_MENU(menu), (GdkEvent*)event);
    return TRUE;
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
static void translate_clicked(GtkButton* button, gpointer user_data);

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
    if (state->ocr_button)
        gtk_widget_set_sensitive(state->ocr_button, state->doc != NULL && path_has_pdf_extension(state->path));
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
        if (result->state->ocr_button)
            gtk_widget_set_sensitive(result->state->ocr_button,
                                     result->state->doc != NULL && path_has_pdf_extension(result->state->path));
        ocr_clicked(GTK_BUTTON(result->state->ocr_button), result->state);
    } else {
        append_install_log(result->log, "\nOCR installation failed. The package manager output is shown above.\n");
        if (result->state->ocr_button)
            gtk_widget_set_sensitive(result->state->ocr_button,
                                     result->state->doc != NULL && path_has_pdf_extension(result->state->path));
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

typedef struct translate_task {
    app_state* state;
    char* tool;
    char* path;
    char* input_text;
    char* from_lang;
    char* to_lang;
    char* output_path;
    char* tmp_pdf_path;
    GtkWidget* dialog;
    GtkWidget* progress;
    GtkWidget* log;
    GCancellable* cancellable;
    spdf_rect selection_bounds;
    int page_index;
    gboolean full_document;
    gboolean has_selection_bounds;
} translate_task;

typedef struct translate_line_meta {
    int page_index;
    spdf_rect bounds;
    float font_size;
} translate_line_meta;

typedef struct translate_result {
    app_state* state;
    char* output_path;
    GtkWidget* dialog;
    GtkWidget* progress;
    GtkWidget* log;
    gboolean success;
    gboolean canceled;
    char* message;
} translate_result;

typedef struct translate_progress_update {
    app_state* state;
    GtkWidget* progress;
    GtkWidget* log;
    double fraction;
    char* message;
} translate_progress_update;

typedef struct translate_install_task {
    app_state* state;
    GtkWidget* dialog;
    GtkWidget* progress;
    GtkWidget* log;
    char* script;
} translate_install_task;

typedef struct translate_install_result {
    app_state* state;
    GtkWidget* dialog;
    GtkWidget* progress;
    GtkWidget* log;
    gboolean success;
    char* output;
} translate_install_result;

static void translate_force_exit_subprocess(GCancellable* cancellable, gpointer user_data) {
    (void)cancellable;
    g_subprocess_force_exit(G_SUBPROCESS(user_data));
}

static gboolean subprocess_capture_utf8_with_cancel(char** argv, const char* input, char** output_out, char** error_out,
                                                    GCancellable* cancellable, GError** error) {
    GSubprocess* subprocess;
    gchar* stdout_text = NULL;
    gchar* stderr_text = NULL;
    gboolean ok;
    gulong cancel_id = 0;

    if (output_out) *output_out = NULL;
    if (error_out) *error_out = NULL;
    subprocess = g_subprocess_newv(
        (const gchar* const*)argv,
        G_SUBPROCESS_FLAGS_STDIN_PIPE | G_SUBPROCESS_FLAGS_STDOUT_PIPE | G_SUBPROCESS_FLAGS_STDERR_PIPE, error);
    if (!subprocess) return FALSE;

    if (cancellable)
        cancel_id = g_cancellable_connect(cancellable, G_CALLBACK(translate_force_exit_subprocess), subprocess, NULL);
    ok = g_subprocess_communicate_utf8(subprocess, input ? input : "", cancellable, &stdout_text, &stderr_text, error);
    if (cancellable && cancel_id) g_cancellable_disconnect(cancellable, cancel_id);
    if (output_out)
        *output_out = stdout_text;
    else
        g_free(stdout_text);
    if (error_out)
        *error_out = stderr_text;
    else
        g_free(stderr_text);
    ok = ok && g_subprocess_get_successful(subprocess);
    g_object_unref(subprocess);
    return ok;
}

static gboolean subprocess_capture_utf8(char** argv, const char* input, char** output_out, char** error_out,
                                        GError** error) {
    return subprocess_capture_utf8_with_cancel(argv, input, output_out, error_out, NULL, error);
}

static gboolean translate_progress_update_idle(gpointer data) {
    translate_progress_update* update = (translate_progress_update*)data;

    if (update->progress) {
        gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(update->progress), MAX(0.0, MIN(update->fraction, 1.0)));
        gtk_progress_bar_set_text(GTK_PROGRESS_BAR(update->progress), update->message ? update->message : "");
    }
    if (update->state && update->state->status && update->message)
        gtk_label_set_text(GTK_LABEL(update->state->status), update->message);
    if (update->log && update->message) {
        append_install_log(update->log, update->message);
        append_install_log(update->log, "\n");
    }
    if (update->progress) g_object_unref(update->progress);
    if (update->log) g_object_unref(update->log);
    g_free(update->message);
    g_free(update);
    return G_SOURCE_REMOVE;
}

static void queue_translate_progress(translate_task* task, double fraction, const char* message) {
    translate_progress_update* update;

    if (!task || !task->progress) return;
    update = g_new0(translate_progress_update, 1);
    update->state = task->state;
    update->progress = g_object_ref(task->progress);
    update->log = task->log ? g_object_ref(task->log) : NULL;
    update->fraction = fraction;
    update->message = g_strdup(message ? message : "");
    g_idle_add(translate_progress_update_idle, update);
}

static void translate_cancel_clicked(GtkButton* button, gpointer user_data) {
    GCancellable* cancellable = G_CANCELLABLE(user_data);
    GtkWidget* widget = GTK_WIDGET(button);

    if (cancellable) g_cancellable_cancel(cancellable);
    gtk_button_set_label(button, "Canceling...");
    gtk_widget_set_sensitive(widget, FALSE);
}

static const char* translation_suffix_for_target_language(const char* target_language) {
    if (!target_language || !*target_language) return "translated";
    if (g_strcmp0(target_language, "en") == 0) return "english";
    return target_language;
}

static char* translate_output_path_for_pdf(const char* path, const char* target_language) {
    char* dir = g_path_get_dirname(path);
    char* base = g_path_get_basename(path);
    char* dot = strrchr(base, '.');
    char* stem = dot ? g_strndup(base, (gsize)(dot - base)) : g_strdup(base);
    char* name = g_strdup_printf("%s_%s.pdf", stem, translation_suffix_for_target_language(target_language));
    char* output = g_build_filename(dir, name, NULL);
    g_free(name);
    g_free(stem);
    g_free(base);
    g_free(dir);
    return output;
}

static char* translate_temp_path_for_pdf(const char* path) {
    char* dir = g_path_get_dirname(path);
    char* base = g_path_get_basename(path);
    char* name = g_strdup_printf(".%s.translate-%u.pdf", base, g_random_int());
    char* output = g_build_filename(dir, name, NULL);
    g_free(name);
    g_free(base);
    g_free(dir);
    return output;
}

static spdf_rect union_public_rect(spdf_rect a, spdf_rect b) {
    spdf_rect r;
    r.x0 = MIN(a.x0, b.x0);
    r.y0 = MIN(a.y0, b.y0);
    r.x1 = MAX(a.x1, b.x1);
    r.y1 = MAX(a.y1, b.y1);
    return r;
}

static gboolean append_translate_meta(translate_line_meta** metas, int* count, int* capacity, int page_index,
                                      spdf_rect bounds, float font_size) {
    translate_line_meta* next;
    int next_capacity;

    if (*count == *capacity) {
        next_capacity = *capacity ? *capacity * 2 : 256;
        next = g_renew(translate_line_meta, *metas, next_capacity);
        if (!next) return FALSE;
        *metas = next;
        *capacity = next_capacity;
    }
    (*metas)[*count].page_index = page_index;
    (*metas)[*count].bounds = bounds;
    (*metas)[*count].font_size = font_size;
    (*count)++;
    return TRUE;
}

static char* extract_document_lines_for_translate(const char* path, translate_line_meta** metas_out,
                                                  int* meta_count_out, char** message_out) {
    spdf_document* doc;
    GString* text;
    translate_line_meta* metas = NULL;
    int meta_count = 0;
    int meta_capacity = 0;
    char err[1024];
    int page_count;

    if (metas_out) *metas_out = NULL;
    if (meta_count_out) *meta_count_out = 0;
    if (message_out) *message_out = NULL;

    doc = spdf_open(path, err, sizeof(err));
    if (!doc) {
        if (message_out) *message_out = g_strdup(err[0] ? err : "Could not open document for translation.");
        return NULL;
    }

    text = g_string_new("");
    page_count = spdf_page_count(doc);
    for (int page = 0; page < page_count; ++page) {
        spdf_text_lines lines;
        memset(&lines, 0, sizeof(lines));
        if (!spdf_extract_page_text_lines(doc, page, &lines, err, sizeof(err))) {
            if (message_out)
                *message_out = g_strdup_printf("Could not extract text from page %d: %s", page + 1,
                                               err[0] ? err : "Unknown error");
            spdf_free_text_lines(&lines);
            g_free(metas);
            g_string_free(text, TRUE);
            spdf_close(doc);
            return NULL;
        }
        for (int i = 0; i < lines.count; ++i) {
            if (!lines.items[i].text || !*lines.items[i].text) continue;
            if (!append_translate_meta(&metas, &meta_count, &meta_capacity, page, lines.items[i].bounds,
                                       lines.items[i].font_size)) {
                if (message_out) *message_out = g_strdup("Out of memory while preparing translation.");
                spdf_free_text_lines(&lines);
                g_free(metas);
                g_string_free(text, TRUE);
                spdf_close(doc);
                return NULL;
            }
            g_string_append(text, lines.items[i].text);
            g_string_append_c(text, '\n');
        }
        spdf_free_text_lines(&lines);
    }
    spdf_close(doc);

    if (meta_count == 0 || text->len == 0) {
        if (message_out)
            *message_out = g_strdup("No selectable document text was found. Run OCR first, then translate.");
        g_free(metas);
        g_string_free(text, TRUE);
        return NULL;
    }

    if (metas_out) *metas_out = metas;
    if (meta_count_out) *meta_count_out = meta_count;
    return g_string_free(text, FALSE);
}

static char* extract_full_document_text_for_translate(const char* path, char** message_out) {
    char* tool = g_find_program_in_path("pdftotext");
    char* output = NULL;
    char* stderr_text = NULL;
    GError* error = NULL;

    if (message_out) *message_out = NULL;
    if (tool) {
        char* argv[] = {tool, "-layout", (char*)path, "-", NULL};
        gboolean ok = subprocess_capture_utf8(argv, NULL, &output, &stderr_text, &error);
        if (ok && output && output[0] != '\0') {
            g_free(stderr_text);
            g_free(tool);
            return output;
        }
        if (message_out && stderr_text && *stderr_text) *message_out = g_strdup(stderr_text);
        g_clear_error(&error);
        g_free(output);
        g_free(stderr_text);
        output = NULL;
        stderr_text = NULL;
        g_free(tool);
    }

    tool = g_find_program_in_path("mutool");
    if (tool) {
        char* argv[] = {tool, "draw", "-F", "txt", "-o", "-", (char*)path, NULL};
        gboolean ok = subprocess_capture_utf8(argv, NULL, &output, &stderr_text, &error);
        if (ok && output && output[0] != '\0') {
            g_free(stderr_text);
            g_free(tool);
            return output;
        }
        if (message_out && !*message_out && stderr_text && *stderr_text) *message_out = g_strdup(stderr_text);
        g_clear_error(&error);
        g_free(output);
        g_free(stderr_text);
        g_free(tool);
    }

    if (message_out && !*message_out)
        *message_out = g_strdup(
            "Full-document translation needs a document text extraction API, pdftotext, or mutool. "
            "Select text and translate the selection, or install poppler-utils/mupdf-tools.");
    return NULL;
}

static gboolean pdf_next_line(cairo_t* cr, double* y, double page_height, double margin, double line_height) {
    *y += line_height;
    if (*y <= page_height - margin) return FALSE;
    cairo_show_page(cr);
    *y = margin;
    return TRUE;
}

static gboolean write_translated_text_pdf(const char* path, const char* source_path, const char* text,
                                          char** message_out) {
    const double page_width = 595.0;
    const double page_height = 842.0;
    const double margin = 48.0;
    const double line_height = 15.0;
    cairo_surface_t* surface;
    cairo_t* cr;
    cairo_status_t status;
    char* title;
    char* valid_text;
    char** paragraphs;
    double y = margin;

    if (message_out) *message_out = NULL;
    surface = cairo_pdf_surface_create(path, page_width, page_height);
    cr = cairo_create(surface);
    cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
    cairo_set_font_size(cr, 13.0);
    title = g_path_get_basename(source_path);
    cairo_move_to(cr, margin, y);
    cairo_show_text(cr, "Translated to English");
    y += line_height;
    cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL);
    cairo_set_font_size(cr, 9.0);
    cairo_move_to(cr, margin, y);
    cairo_show_text(cr, title ? title : "");
    y += line_height * 1.4;
    cairo_set_font_size(cr, 11.0);

    valid_text = g_utf8_make_valid(text ? text : "", -1);
    paragraphs = g_strsplit(valid_text, "\n", -1);
    for (int i = 0; paragraphs[i]; ++i) {
        char* paragraph = g_strstrip(paragraphs[i]);
        char** words;
        GString* line;

        if (!*paragraph) {
            pdf_next_line(cr, &y, page_height, margin, line_height);
            continue;
        }

        words = g_strsplit_set(paragraph, " \t\r", -1);
        line = g_string_new("");
        for (int word_index = 0; words[word_index]; ++word_index) {
            cairo_text_extents_t extents;
            char* candidate;
            if (!*words[word_index]) continue;
            candidate =
                line->len ? g_strdup_printf("%s %s", line->str, words[word_index]) : g_strdup(words[word_index]);
            cairo_text_extents(cr, candidate, &extents);
            if (line->len && extents.x_advance > page_width - margin * 2.0) {
                cairo_move_to(cr, margin, y);
                cairo_show_text(cr, line->str);
                pdf_next_line(cr, &y, page_height, margin, line_height);
                g_string_assign(line, words[word_index]);
            } else {
                g_string_assign(line, candidate);
            }
            g_free(candidate);
        }
        if (line->len) {
            cairo_move_to(cr, margin, y);
            cairo_show_text(cr, line->str);
            pdf_next_line(cr, &y, page_height, margin, line_height);
        }
        g_string_free(line, TRUE);
        g_strfreev(words);
    }

    cairo_destroy(cr);
    cairo_surface_finish(surface);
    status = cairo_surface_status(surface);
    cairo_surface_destroy(surface);
    g_strfreev(paragraphs);
    g_free(valid_text);
    g_free(title);

    if (status != CAIRO_STATUS_SUCCESS) {
        if (message_out) *message_out = g_strdup(cairo_status_to_string(status));
        return FALSE;
    }
    return TRUE;
}

static gboolean translate_finished_idle(gpointer data) {
    translate_result* result = (translate_result*)data;
    app_state* state = result->state;

    state->translate_running = FALSE;
    update_controls(state);
    if (result->success) {
        if (result->progress) gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(result->progress), 1.0);
        if (result->dialog) gtk_widget_destroy(result->dialog);
        open_path_in_tab_at_page(state, result->output_path, 0, TRUE);
        gtk_label_set_text(GTK_LABEL(state->status), result->message ? result->message : "Translation complete.");
    } else if (result->canceled) {
        if (result->dialog) gtk_widget_destroy(result->dialog);
        gtk_label_set_text(GTK_LABEL(state->status), "Translation canceled.");
    } else {
        if (result->progress) gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(result->progress), 0.0);
        if (result->dialog) gtk_widget_destroy(result->dialog);
        show_error(GTK_WINDOW(state->window), "Translation failed", result->message ? result->message : "");
        gtk_label_set_text(GTK_LABEL(state->status), "Translation failed.");
    }
    if (result->dialog) g_object_unref(result->dialog);
    if (result->progress) g_object_unref(result->progress);
    if (result->log) g_object_unref(result->log);
    g_free(result->output_path);
    g_free(result->message);
    g_free(result);
    return G_SOURCE_REMOVE;
}

static gpointer translate_worker(gpointer data) {
    translate_task* task = (translate_task*)data;
    translate_result* result = g_new0(translate_result, 1);
    char* input_text = NULL;
    char* translated = NULL;
    char* stderr_text = NULL;
    char* detail = NULL;
    translate_line_meta* metas = NULL;
    int meta_count = 0;
    int meta_capacity = 0;
    GError* error = NULL;

    result->state = task->state;
    result->output_path = g_strdup(task->output_path);
    result->dialog = task->dialog;
    result->progress = task->progress;
    result->log = task->log;

    queue_translate_progress(task, 0.02,
                             task->full_document ? "Extracting document text..." : "Preparing selection...");

    if (task->input_text) {
        input_text = g_strdup(task->input_text);
        if (!append_translate_meta(
                &metas, &meta_count, &meta_capacity, task->page_index, task->selection_bounds,
                MAX(8.0f, MIN(18.0f, (task->selection_bounds.y1 - task->selection_bounds.y0) * 0.8f)))) {
            result->message = g_strdup("Out of memory while preparing translation.");
            goto done;
        }
    } else {
        input_text = extract_document_lines_for_translate(task->path, &metas, &meta_count, &detail);
        if (!input_text) {
            char* fallback_detail = NULL;
            input_text = extract_full_document_text_for_translate(task->path, &fallback_detail);
            g_free(fallback_detail);
        }
    }

    if (!input_text || input_text[0] == '\0') {
        if (detail) {
            result->message = detail;
            detail = NULL;
        } else {
            result->message = g_strdup("No document text was available to translate.");
        }
        goto done;
    }
    if (strlen(input_text) > MAX_TRANSLATE_TEXT_BYTES) {
        result->message = g_strdup("The extracted text is too large to translate in this build.");
        goto done;
    }

    char* argv[] = {task->tool, "--from-lang", task->from_lang, "--to-lang", task->to_lang, NULL};
    if (meta_count > 1) {
        char** source_lines = g_strsplit(input_text, "\n", -1);
        GString* translated_joined = g_string_new("");
        int start = 0;
        while (start < meta_count) {
            int page = metas[start].page_index;
            int end = start + 1;
            GString* page_input = g_string_new("");
            char* page_translated = NULL;
            char* page_stderr = NULL;
            GError* page_error = NULL;
            char progress_text[160];
            while (end < meta_count && metas[end].page_index == page) end++;
            g_snprintf(progress_text, sizeof(progress_text), "Translating page %d (%d of %d text blocks)...", page + 1,
                       start, meta_count);
            queue_translate_progress(task, 0.05 + 0.85 * ((double)start / MAX(1, meta_count)), progress_text);
            for (int i = start; i < end; ++i) {
                g_string_append(page_input, source_lines && source_lines[i] ? source_lines[i] : "");
                g_string_append_c(page_input, '\n');
            }
            if (!subprocess_capture_utf8_with_cancel(argv, page_input->str, &page_translated, &page_stderr,
                                                     task->cancellable, &page_error) ||
                !page_translated || page_translated[0] == '\0') {
                const char* error_text = page_error && page_error->message ? page_error->message : NULL;
                const char* process_text = page_stderr && *page_stderr ? page_stderr : page_translated;
                if (g_error_matches(page_error, G_IO_ERROR, G_IO_ERROR_CANCELLED)) {
                    result->canceled = TRUE;
                    result->message = g_strdup("Translation canceled.");
                } else {
                    result->message = g_strdup_printf(
                        "Page %d: %s", page + 1,
                        error_text ? error_text
                                   : (process_text ? process_text : "Argos Translate exited with an error."));
                }
                if (page_error) g_error_free(page_error);
                g_free(page_translated);
                g_free(page_stderr);
                g_string_free(page_input, TRUE);
                g_string_free(translated_joined, TRUE);
                g_strfreev(source_lines);
                goto done;
            }
            char** page_output = g_strsplit(page_translated, "\n", -1);
            for (int i = start; i < end; ++i) {
                int local = i - start;
                g_string_append(translated_joined,
                                page_output && page_output[local] && page_output[local][0] ? page_output[local] : " ");
                g_string_append_c(translated_joined, '\n');
            }
            g_strfreev(page_output);
            g_free(page_translated);
            g_free(page_stderr);
            g_string_free(page_input, TRUE);
            start = end;
            g_snprintf(progress_text, sizeof(progress_text), "Translated page %d (%d of %d text blocks).", page + 1,
                       start, meta_count);
            queue_translate_progress(task, 0.05 + 0.85 * ((double)start / MAX(1, meta_count)), progress_text);
        }
        translated = g_string_free(translated_joined, FALSE);
        g_strfreev(source_lines);
    } else if (!subprocess_capture_utf8_with_cancel(argv, input_text, &translated, &stderr_text, task->cancellable,
                                                    &error) ||
               !translated || translated[0] == '\0') {
        const char* error_text = error && error->message ? error->message : NULL;
        const char* process_text = stderr_text && *stderr_text ? stderr_text : translated;
        if (g_error_matches(error, G_IO_ERROR, G_IO_ERROR_CANCELLED)) {
            result->canceled = TRUE;
            result->message = g_strdup("Translation canceled.");
        } else {
            result->message = g_strdup(
                error_text ? error_text : (process_text ? process_text : "Argos Translate exited with an error."));
        }
        goto done;
    }

    queue_translate_progress(task, 0.93, "Writing translated PDF...");
    if (meta_count > 0) {
        spdf_document* save_doc;
        spdf_translated_line* lines;
        char** output_lines;
        char err[1024];

        save_doc = spdf_open(task->path, err, sizeof(err));
        if (!save_doc) {
            result->message = g_strdup(err[0] ? err : "Could not reopen document to save translation.");
            goto done;
        }
        lines = g_new0(spdf_translated_line, meta_count);
        output_lines = g_strsplit(translated ? translated : "", "\n", -1);
        for (int i = 0; i < meta_count; ++i) {
            const char* line_text = output_lines && output_lines[i] && output_lines[i][0] ? output_lines[i] : " ";
            if (meta_count == 1) line_text = translated && translated[0] ? translated : " ";
            lines[i].page_index = metas[i].page_index;
            lines[i].bounds = metas[i].bounds;
            lines[i].font_size = metas[i].font_size;
            lines[i].opaque_background = SPDF_TRANSLATION_BACKGROUND_OPAQUE;
            lines[i].text = line_text;
        }
        if (!spdf_save_translated_copy(save_doc, task->tmp_pdf_path, lines, meta_count, err, sizeof(err))) {
            result->message = g_strdup(err[0] ? err : "Could not write translated PDF.");
            g_strfreev(output_lines);
            g_free(lines);
            spdf_close(save_doc);
            goto done;
        }
        g_strfreev(output_lines);
        g_free(lines);
        spdf_close(save_doc);
    } else if (!write_translated_text_pdf(task->tmp_pdf_path, task->path, translated, &detail)) {
        result->message = detail ? detail : g_strdup("Could not write translated PDF.");
        detail = NULL;
        goto done;
    }
    if (g_rename(task->tmp_pdf_path, task->output_path) != 0) {
        result->message = g_strdup("Could not move translated PDF into place.");
        g_remove(task->tmp_pdf_path);
        goto done;
    }

    result->success = TRUE;
    result->message =
        g_strdup(task->full_document ? "Translated document opened." : "Translated selection opened as a PDF.");
    queue_translate_progress(task, 1.0, "Translation complete.");

done:
    if (error) g_error_free(error);
    g_free(input_text);
    g_free(translated);
    g_free(stderr_text);
    g_free(detail);
    g_free(metas);
    g_free(task->tool);
    g_free(task->path);
    g_free(task->input_text);
    g_free(task->from_lang);
    g_free(task->to_lang);
    g_free(task->output_path);
    g_free(task->tmp_pdf_path);
    if (task->cancellable) g_object_unref(task->cancellable);
    g_free(task);
    g_idle_add(translate_finished_idle, result);
    return NULL;
}

static gboolean pulse_translate_install_progress(gpointer data) {
    GtkProgressBar* progress = GTK_PROGRESS_BAR(data);
    if (!GPOINTER_TO_INT(g_object_get_data(G_OBJECT(progress), "translate-install-running"))) return G_SOURCE_REMOVE;
    gtk_progress_bar_pulse(progress);
    return G_SOURCE_CONTINUE;
}

static char* translate_install_script(void) {
    return g_strdup(
        "set -e\n"
        "export PATH=\"$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH\"\n"
        "if command -v argos-translate >/dev/null 2>&1 && command -v argospm >/dev/null 2>&1; then exit 0; fi\n"
        "echo 'Installing Argos Translate...'\n"
        "if command -v pkexec >/dev/null 2>&1; then\n"
        "  if command -v apt-get >/dev/null 2>&1; then\n"
        "    pkexec /bin/sh -c 'apt-get update && apt-get install -y argos-translate' || true\n"
        "  elif command -v dnf >/dev/null 2>&1; then\n"
        "    pkexec dnf install -y argos-translate || true\n"
        "  elif command -v pacman >/dev/null 2>&1; then\n"
        "    pkexec pacman -S --needed --noconfirm argos-translate || true\n"
        "  elif command -v zypper >/dev/null 2>&1; then\n"
        "    pkexec zypper --non-interactive install argos-translate || true\n"
        "  fi\n"
        "fi\n"
        "if ! command -v argos-translate >/dev/null 2>&1 || ! command -v argospm >/dev/null 2>&1; then\n"
        "  if ! command -v python3 >/dev/null 2>&1; then echo 'python3 is required to install Argos Translate.'; exit "
        "1; "
        "fi\n"
        "  python3 -m pip --version >/dev/null 2>&1 || python3 -m ensurepip --user >/dev/null 2>&1 || true\n"
        "  python3 -m pip install --user --upgrade argostranslate || "
        "python3 -m pip install --user --break-system-packages --upgrade argostranslate\n"
        "fi\n"
        "command -v argos-translate >/dev/null 2>&1\n"
        "command -v argospm >/dev/null 2>&1\n"
        "echo 'Argos Translate installed. Install source-to-English language models with argospm if needed.'\n");
}

static gboolean translate_install_finished_idle(gpointer data) {
    translate_install_result* result = (translate_install_result*)data;
    char* tool = NULL;
    char* argospm = NULL;

    result->state->translate_install_running = FALSE;
    g_object_set_data(G_OBJECT(result->progress), "translate-install-running", GINT_TO_POINTER(FALSE));
    gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(result->progress), result->success ? 1.0 : 0.0);
    append_install_log(result->log, result->output ? result->output : "");

    tool = g_find_program_in_path("argos-translate");
    argospm = g_find_program_in_path("argospm");
    if (result->success && tool && argospm) {
        gtk_widget_destroy(result->dialog);
        update_controls(result->state);
        translate_clicked(GTK_BUTTON(result->state->translate_button), result->state);
    } else {
        append_install_log(result->log,
                           "\nArgos Translate installation failed. The package manager output is shown above.\n");
        gtk_label_set_text(GTK_LABEL(result->state->status), "Translation support installation failed.");
        update_controls(result->state);
    }

    g_free(tool);
    g_free(argospm);
    g_object_unref(result->dialog);
    g_object_unref(result->progress);
    g_object_unref(result->log);
    g_free(result->output);
    g_free(result);
    return G_SOURCE_REMOVE;
}

static gpointer translate_install_worker(gpointer data) {
    translate_install_task* task = (translate_install_task*)data;
    translate_install_result* result = g_new0(translate_install_result, 1);
    gchar* stdout_text = NULL;
    gchar* stderr_text = NULL;
    GError* error = NULL;
    char* argv[] = {"/bin/sh", "-c", task->script, NULL};
    gboolean ok = subprocess_capture_utf8(argv, NULL, &stdout_text, &stderr_text, &error);
    GString* output = g_string_new("");

    if (stdout_text) g_string_append(output, stdout_text);
    if (stderr_text) g_string_append(output, stderr_text);
    if (error && error->message) g_string_append_printf(output, "\n%s\n", error->message);

    result->state = task->state;
    result->dialog = task->dialog;
    result->progress = task->progress;
    result->log = task->log;
    result->success = ok;
    result->output = g_string_free(output, FALSE);

    if (error) g_error_free(error);
    g_free(stdout_text);
    g_free(stderr_text);
    g_free(task->script);
    g_free(task);
    g_idle_add(translate_install_finished_idle, result);
    return NULL;
}

static void install_translate_then_run(app_state* state) {
    GtkWidget* dialog = gtk_dialog_new();
    GtkWidget* content = gtk_dialog_get_content_area(GTK_DIALOG(dialog));
    GtkWidget* title = gtk_label_new("Installing Argos Translate");
    GtkWidget* progress = gtk_progress_bar_new();
    GtkWidget* scroll = gtk_scrolled_window_new(NULL, NULL);
    GtkWidget* log = gtk_text_view_new();
    translate_install_task* task;

    if (state->translate_install_running) return;
    state->translate_install_running = TRUE;
    gtk_window_set_title(GTK_WINDOW(dialog), "Installing Translation Support");
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
    append_install_log(log, "Preparing Argos Translate installer...\n");
    gtk_widget_show_all(dialog);
    g_object_set_data(G_OBJECT(progress), "translate-install-running", GINT_TO_POINTER(TRUE));
    g_timeout_add_full(G_PRIORITY_DEFAULT, 120, pulse_translate_install_progress, g_object_ref(progress),
                       g_object_unref);

    update_controls(state);
    task = g_new0(translate_install_task, 1);
    task->state = state;
    task->dialog = g_object_ref(dialog);
    task->progress = g_object_ref(progress);
    task->log = g_object_ref(log);
    task->script = translate_install_script();
    g_thread_unref(g_thread_new("install-translate", translate_install_worker, task));
}

static void populate_translation_language_combo(GtkComboBoxText* combo, const char* selected_code) {
    gboolean found = FALSE;

    for (gsize i = 0; i < G_N_ELEMENTS(k_translation_languages); ++i) {
        char* label = g_strdup_printf("%s (%s)", k_translation_languages[i].name, k_translation_languages[i].code);
        gtk_combo_box_text_append(combo, k_translation_languages[i].code, label);
        if (g_strcmp0(selected_code, k_translation_languages[i].code) == 0) found = TRUE;
        g_free(label);
    }
    if (selected_code && *selected_code && !found) {
        char* label = g_strdup_printf("Custom (%s)", selected_code);
        gtk_combo_box_text_append(combo, selected_code, label);
        g_free(label);
    }
    gtk_combo_box_set_active_id(GTK_COMBO_BOX(combo), selected_code && *selected_code ? selected_code : "zh");
    if (gtk_combo_box_get_active(GTK_COMBO_BOX(combo)) < 0) gtk_combo_box_set_active(GTK_COMBO_BOX(combo), 0);
}

static gboolean prompt_translate_languages(app_state* state, char** from_lang_out, char** to_lang_out) {
    GtkWidget* dialog = gtk_dialog_new_with_buttons("Translate", GTK_WINDOW(state->window), GTK_DIALOG_MODAL, "_Cancel",
                                                    GTK_RESPONSE_CANCEL, "_Translate", GTK_RESPONSE_ACCEPT, NULL);
    GtkWidget* content = gtk_dialog_get_content_area(GTK_DIALOG(dialog));
    GtkWidget* grid = gtk_grid_new();
    GtkWidget* from_label = gtk_label_new("From");
    GtkWidget* to_label = gtk_label_new("To");
    GtkWidget* from_combo = gtk_combo_box_text_new();
    GtkWidget* to_combo = gtk_combo_box_text_new();
    gboolean accepted = FALSE;

    if (from_lang_out) *from_lang_out = NULL;
    if (to_lang_out) *to_lang_out = NULL;
    gtk_label_set_xalign(GTK_LABEL(from_label), 0.0);
    gtk_label_set_xalign(GTK_LABEL(to_label), 0.0);
    populate_translation_language_combo(GTK_COMBO_BOX_TEXT(from_combo),
                                        state->translate_source_language ? state->translate_source_language : "zh");
    populate_translation_language_combo(GTK_COMBO_BOX_TEXT(to_combo),
                                        state->translate_target_language ? state->translate_target_language : "en");
    gtk_grid_set_row_spacing(GTK_GRID(grid), 8);
    gtk_grid_set_column_spacing(GTK_GRID(grid), 12);
    gtk_widget_set_margin_start(grid, 12);
    gtk_widget_set_margin_end(grid, 12);
    gtk_widget_set_margin_top(grid, 12);
    gtk_widget_set_margin_bottom(grid, 12);
    gtk_grid_attach(GTK_GRID(grid), from_label, 0, 0, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), from_combo, 1, 0, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), to_label, 0, 1, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), to_combo, 1, 1, 1, 1);
    gtk_widget_set_hexpand(from_combo, TRUE);
    gtk_widget_set_hexpand(to_combo, TRUE);
    gtk_box_pack_start(GTK_BOX(content), grid, FALSE, FALSE, 0);
    gtk_widget_show_all(dialog);
    if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT) {
        char* from_id = gtk_combo_box_text_get_active_text(GTK_COMBO_BOX_TEXT(from_combo));
        char* to_id = gtk_combo_box_text_get_active_text(GTK_COMBO_BOX_TEXT(to_combo));
        const char* from_active = gtk_combo_box_get_active_id(GTK_COMBO_BOX(from_combo));
        const char* to_active = gtk_combo_box_get_active_id(GTK_COMBO_BOX(to_combo));
        (void)from_id;
        (void)to_id;
        if (from_active && *from_active && to_active && *to_active && g_strcmp0(from_active, to_active) != 0) {
            if (from_lang_out) *from_lang_out = g_strdup(from_active);
            if (to_lang_out) *to_lang_out = g_strdup(to_active);
            g_free(state->translate_source_language);
            g_free(state->translate_target_language);
            state->translate_source_language = g_strdup(from_active);
            state->translate_target_language = g_strdup(to_active);
            save_settings(state);
            accepted = TRUE;
        }
        g_free(from_id);
        g_free(to_id);
    }
    gtk_widget_destroy(dialog);
    if (!accepted && from_lang_out) g_clear_pointer(from_lang_out, g_free);
    if (!accepted && to_lang_out) g_clear_pointer(to_lang_out, g_free);
    return accepted;
}

static void translate_clicked(GtkButton* button, gpointer user_data) {
    (void)button;
    app_state* state = (app_state*)user_data;
    char* tool;
    char* argospm;
    char* from_lang;
    char* to_lang;
    GtkWidget* dialog;
    GtkWidget* content;
    GtkWidget* title;
    GtkWidget* progress;
    GtkWidget* scroll;
    GtkWidget* log;
    GtkWidget* cancel_button;
    GCancellable* cancellable;
    translate_task* task;

    if (!state->doc || !state->path || !path_has_pdf_extension(state->path) || state->translate_running ||
        state->translate_install_running)
        return;

    tool = g_find_program_in_path("argos-translate");
    argospm = g_find_program_in_path("argospm");
    if (!tool || !argospm) {
        GtkWidget* dialog = gtk_message_dialog_new(GTK_WINDOW(state->window), GTK_DIALOG_MODAL, GTK_MESSAGE_QUESTION,
                                                   GTK_BUTTONS_NONE, "Install translation support?");
        gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(dialog),
                                                 "SumatraPDF can install Argos Translate, then continue the "
                                                 "translation flow when installation finishes.");
        gtk_dialog_add_buttons(GTK_DIALOG(dialog), "_Install", GTK_RESPONSE_ACCEPT, "_Cancel", GTK_RESPONSE_CANCEL,
                               NULL);
        int response = gtk_dialog_run(GTK_DIALOG(dialog));
        gtk_widget_destroy(dialog);
        g_free(tool);
        g_free(argospm);
        if (response == GTK_RESPONSE_ACCEPT) install_translate_then_run(state);
        return;
    }
    g_free(argospm);

    from_lang = NULL;
    to_lang = NULL;
    if (!prompt_translate_languages(state, &from_lang, &to_lang)) {
        g_free(tool);
        return;
    }

    dialog = gtk_dialog_new();
    content = gtk_dialog_get_content_area(GTK_DIALOG(dialog));
    title = gtk_label_new("Translating with Argos");
    progress = gtk_progress_bar_new();
    scroll = gtk_scrolled_window_new(NULL, NULL);
    log = gtk_text_view_new();
    cancel_button = gtk_dialog_add_button(GTK_DIALOG(dialog), "_Cancel", GTK_RESPONSE_CANCEL);
    cancellable = g_cancellable_new();

    gtk_window_set_title(GTK_WINDOW(dialog), "Translating");
    gtk_window_set_transient_for(GTK_WINDOW(dialog), GTK_WINDOW(state->window));
    gtk_window_set_modal(GTK_WINDOW(dialog), TRUE);
    gtk_window_set_default_size(GTK_WINDOW(dialog), 520, 240);
    gtk_label_set_xalign(GTK_LABEL(title), 0.0);
    gtk_progress_bar_set_show_text(GTK_PROGRESS_BAR(progress), TRUE);
    gtk_progress_bar_set_text(GTK_PROGRESS_BAR(progress), "Preparing translation...");
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
    g_signal_connect_data(cancel_button, "clicked", G_CALLBACK(translate_cancel_clicked), g_object_ref(cancellable),
                          (GClosureNotify)g_object_unref, 0);
    append_install_log(log, "Preparing translation...\n");
    gtk_widget_show_all(dialog);

    task = g_new0(translate_task, 1);
    task->state = state;
    task->tool = tool;
    task->path = g_strdup(state->path);
    task->dialog = g_object_ref(dialog);
    task->progress = g_object_ref(progress);
    task->log = g_object_ref(log);
    task->cancellable = cancellable;
    if (has_text_selection(state)) {
        spdf_rect bounds = state->selection_rects[0];
        for (int i = 1; i < state->selection_rect_count; ++i)
            bounds = union_public_rect(bounds, state->selection_rects[i]);
        task->input_text = g_strdup(state->selected_text);
        task->selection_bounds = bounds;
        task->has_selection_bounds = TRUE;
    }
    task->from_lang = from_lang;
    task->to_lang = to_lang;
    task->output_path = translate_output_path_for_pdf(state->path, task->to_lang);
    task->tmp_pdf_path = translate_temp_path_for_pdf(state->path);
    task->page_index = state->page_index;
    task->full_document = task->input_text == NULL;
    state->translate_running = TRUE;
    update_controls(state);
    gtk_label_set_text(GTK_LABEL(state->status),
                       task->full_document ? "Translating document..." : "Translating selection...");
    g_thread_unref(g_thread_new("translate", translate_worker, task));
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

static void install_palette_css(void) {
    static gboolean installed = FALSE;
    GtkCssProvider* provider;

    if (installed) return;
    provider = gtk_css_provider_new();
    gtk_css_provider_load_from_data(provider,
                                    ".sumatra-palette-header {"
                                    "  background-color: alpha(@theme_selected_bg_color, 0.16);"
                                    "  border-radius: 6px;"
                                    "}"
                                    ".sumatra-palette-delete-confirm {"
                                    "  color: #b00020;"
                                    "}",
                                    -1, NULL);
    gtk_style_context_add_provider_for_screen(gdk_screen_get_default(), GTK_STYLE_PROVIDER(provider),
                                              GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(provider);
    installed = TRUE;
}

static void install_toolbar_css(void) {
    static gboolean installed = FALSE;
    GtkCssProvider* provider;

    if (installed) return;
    provider = gtk_css_provider_new();
    gtk_css_provider_load_from_data(provider,
                                    ".sumatra-toolbar-switch-control {"
                                    "  padding: 1px 4px;"
                                    "  border-radius: 8px;"
                                    "}"
                                    ".sumatra-toolbar label,"
                                    ".sumatra-toolbar button,"
                                    ".sumatra-toolbar checkbutton {"
                                    "  font-weight: normal;"
                                    "}"
                                    ".sumatra-toolbar-overflow {"
                                    "  padding: 0 4px;"
                                    "  border-radius: 8px;"
                                    "  min-width: 30px;"
                                    "}"
                                    ".sumatra-toolbar-switch-control:disabled {"
                                    "  color: alpha(@theme_fg_color, 0.45);"
                                    "}"
                                    "switch.sumatra-toolbar-switch {"
                                    "  min-width: 34px;"
                                    "  min-height: 18px;"
                                    "  border-radius: 10px;"
                                    "  background-color: alpha(@theme_fg_color, 0.20);"
                                    "  border: 1px solid alpha(@theme_fg_color, 0.24);"
                                    "}"
                                    "switch.sumatra-toolbar-switch:checked {"
                                    "  background-color: rgba(255, 255, 255, 0.94);"
                                    "  border-color: rgba(255, 255, 255, 0.74);"
                                    "}"
                                    "switch.sumatra-toolbar-switch slider {"
                                    "  min-width: 14px;"
                                    "  min-height: 14px;"
                                    "  border-radius: 8px;"
                                    "  background-color: rgba(255, 255, 255, 0.96);"
                                    "}"
                                    "switch.sumatra-toolbar-switch:checked slider {"
                                    "  background-color: rgba(0, 0, 0, 0.86);"
                                    "}",
                                    -1, NULL);
    gtk_style_context_add_provider_for_screen(gdk_screen_get_default(), GTK_STYLE_PROVIDER(provider),
                                              GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(provider);
    installed = TRUE;
}

static gboolean toolbar_overflow_icon_draw(GtkWidget* widget, cairo_t* cr, gpointer user_data) {
    (void)user_data;
    GtkAllocation allocation;
    gtk_widget_get_allocation(widget, &allocation);
    GtkStyleContext* context = gtk_widget_get_style_context(widget);
    GdkRGBA color;
    gtk_style_context_get_color(context, gtk_style_context_get_state(context), &color);
    gdk_cairo_set_source_rgba(cr, &color);
    double dot_size = 3.0;
    double gap = 5.0;
    double x = floor((allocation.width - dot_size * 3.0 - gap * 2.0) * 0.5);
    double y = floor((allocation.height - dot_size) * 0.5);
    for (int i = 0; i < 3; ++i) {
        cairo_arc(cr, x + dot_size * 0.5 + i * (dot_size + gap), y + dot_size * 0.5, dot_size * 0.5, 0, G_PI * 2.0);
        cairo_fill(cr);
    }
    return FALSE;
}

static gboolean translate_icon_draw(GtkWidget* widget, cairo_t* cr, gpointer user_data) {
    (void)user_data;
    GtkAllocation allocation;
    GtkStyleContext* context;
    GdkRGBA color;
    double x;
    double y;
    double scale;

    gtk_widget_get_allocation(widget, &allocation);
    context = gtk_widget_get_style_context(widget);
    gtk_style_context_get_color(context, gtk_style_context_get_state(context), &color);
    gdk_cairo_set_source_rgba(cr, &color);
    x = floor((allocation.width - 18.0) * 0.5);
    y = floor((allocation.height - 18.0) * 0.5);
    scale = 18.0 / 24.0;
    cairo_save(cr);
    cairo_translate(cr, x, y);
    cairo_scale(cr, scale, scale);
    cairo_set_line_width(cr, 1.9);
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);

    cairo_new_sub_path(cr);
    cairo_arc(cr, 3.4, 3.4, 2.2, G_PI, G_PI * 1.5);
    cairo_arc(cr, 12.6, 3.4, 2.2, G_PI * 1.5, G_PI * 2.0);
    cairo_arc(cr, 12.6, 12.6, 2.2, 0.0, G_PI * 0.5);
    cairo_arc(cr, 3.4, 12.6, 2.2, G_PI * 0.5, G_PI);
    cairo_close_path(cr);
    cairo_stroke(cr);

    cairo_new_sub_path(cr);
    cairo_arc(cr, 11.4, 11.4, 2.2, G_PI, G_PI * 1.5);
    cairo_arc(cr, 20.6, 11.4, 2.2, G_PI * 1.5, G_PI * 2.0);
    cairo_arc(cr, 20.6, 20.6, 2.2, 0.0, G_PI * 0.5);
    cairo_arc(cr, 11.4, 20.6, 2.2, G_PI * 0.5, G_PI);
    cairo_close_path(cr);
    cairo_stroke(cr);

    cairo_move_to(cr, 4.0, 5.0);
    cairo_line_to(cr, 12.0, 5.0);
    cairo_move_to(cr, 8.0, 3.0);
    cairo_line_to(cr, 8.0, 5.0);
    cairo_move_to(cr, 5.8, 6.2);
    cairo_curve_to(cr, 6.8, 8.5, 8.8, 8.5, 10.2, 6.2);
    cairo_move_to(cr, 7.0, 8.0);
    cairo_line_to(cr, 9.7, 10.7);
    cairo_stroke(cr);

    cairo_move_to(cr, 12.6, 20.0);
    cairo_line_to(cr, 16.0, 11.8);
    cairo_line_to(cr, 19.4, 20.0);
    cairo_move_to(cr, 14.0, 17.0);
    cairo_line_to(cr, 18.0, 17.0);
    cairo_stroke(cr);

    cairo_move_to(cr, 15.9, 1.5);
    cairo_line_to(cr, 18.0, 1.5);
    cairo_curve_to(cr, 19.6, 1.5, 20.5, 2.4, 20.5, 4.0);
    cairo_line_to(cr, 20.5, 6.2);
    cairo_move_to(cr, 18.0, 5.0);
    cairo_line_to(cr, 20.5, 7.5);
    cairo_line_to(cr, 23.0, 5.0);
    cairo_move_to(cr, 8.1, 22.5);
    cairo_line_to(cr, 6.0, 22.5);
    cairo_curve_to(cr, 4.4, 22.5, 3.5, 21.6, 3.5, 20.0);
    cairo_line_to(cr, 3.5, 17.8);
    cairo_move_to(cr, 6.0, 19.0);
    cairo_line_to(cr, 3.5, 16.5);
    cairo_line_to(cr, 1.0, 19.0);
    cairo_stroke(cr);
    cairo_restore(cr);
    return FALSE;
}

static GtkWidget* toolbar_switch_control_new(const char* title, GtkWidget** switch_out) {
    GtkWidget* box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 5);
    GtkWidget* label = gtk_label_new(title);
    GtkWidget* toggle = gtk_switch_new();

    gtk_style_context_add_class(gtk_widget_get_style_context(box), "sumatra-toolbar-switch-control");
    gtk_style_context_add_class(gtk_widget_get_style_context(toggle), "sumatra-toolbar-switch");
    gtk_widget_set_valign(box, GTK_ALIGN_CENTER);
    gtk_widget_set_valign(label, GTK_ALIGN_CENTER);
    gtk_widget_set_valign(toggle, GTK_ALIGN_CENTER);
    gtk_box_pack_start(GTK_BOX(box), label, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(box), toggle, FALSE, FALSE, 0);
    *switch_out = toggle;
    return box;
}

static void toolbar_pack_item(GtkWidget* toolbar, GtkWidget* item, int overflow_priority, GtkWidget* mirror_item) {
    gtk_box_pack_start(GTK_BOX(toolbar), item, FALSE, FALSE, 0);
    if (overflow_priority > 0)
        g_object_set_data(G_OBJECT(item), "sumatra-overflow-priority", GINT_TO_POINTER(overflow_priority));
    if (mirror_item) g_object_set_data(G_OBJECT(item), "sumatra-overflow-mirror", mirror_item);
}

static int widget_preferred_width(GtkWidget* widget) {
    int min_width = 0;
    int nat_width = 0;
    gtk_widget_get_preferred_width(widget, &min_width, &nat_width);
    return MAX(min_width, nat_width);
}

static void update_toolbar_overflow_menu_state(app_state* state) {
    gboolean has_panel;
    gboolean sidebar_visible;

    if (!state || state->updating_overflow_controls) return;
    state->updating_overflow_controls = TRUE;
    has_panel = state->doc && (state->outline.count > 0 || state->comments.count > 0);
    sidebar_visible = state->sidebar_container && gtk_widget_get_visible(state->sidebar_container);
    if (state->overflow_side_panel_item) {
        gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(state->overflow_side_panel_item), sidebar_visible);
        gtk_widget_set_sensitive(state->overflow_side_panel_item, has_panel && !state->presentation_mode);
    }
    if (state->overflow_minimap_item) {
        gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(state->overflow_minimap_item),
                                       state->doc && state->show_minimap && !state->presentation_mode);
        gtk_widget_set_sensitive(state->overflow_minimap_item, state->doc && !state->presentation_mode);
    }
    if (state->overflow_marker_strip_item) {
        gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(state->overflow_marker_strip_item),
                                       state->show_find_markers);
        gtk_widget_set_sensitive(state->overflow_marker_strip_item,
                                 state->doc && state->find_match_count > 0 && !state->presentation_mode);
    }
    if (state->overflow_continuous_item) {
        gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(state->overflow_continuous_item), state->continuous_mode);
        gtk_widget_set_sensitive(state->overflow_continuous_item, state->doc != NULL);
    }
    if (state->overflow_search_regex_item) {
        gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(state->overflow_search_regex_item), state->search_regex);
        gtk_widget_set_sensitive(state->overflow_search_regex_item, state->doc != NULL);
    }
    if (state->overflow_search_regex_multiline_item) {
        gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(state->overflow_search_regex_multiline_item),
                                       state->search_regex_multiline);
        gtk_widget_set_sensitive(state->overflow_search_regex_multiline_item, state->doc && state->search_regex);
    }
    if (state->overflow_translate_item) {
        gtk_widget_set_sensitive(state->overflow_translate_item,
                                 state->doc != NULL && path_has_pdf_extension(state->path) &&
                                     !state->translate_running && !state->translate_install_running);
    }
    for (int i = 0; i < 5; ++i) {
        if (!state->overflow_fit_mode_items[i]) continue;
        gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(state->overflow_fit_mode_items[i]), state->fit_mode_id == i);
        gtk_widget_set_sensitive(state->overflow_fit_mode_items[i], state->doc != NULL);
    }
    state->updating_overflow_controls = FALSE;
}

static int compare_toolbar_items_by_priority(const void* a, const void* b) {
    GtkWidget* widget_a = *(GtkWidget* const*)a;
    GtkWidget* widget_b = *(GtkWidget* const*)b;
    int priority_a = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget_a), "sumatra-overflow-priority"));
    int priority_b = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(widget_b), "sumatra-overflow-priority"));
    return priority_b - priority_a;
}

static void toolbar_size_allocate(GtkWidget* toolbar, GtkAllocation* allocation, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    GList* children;
    GtkWidget** candidates;
    int candidate_count = 0;
    int total_width = 0;
    int visible_count = 0;
    int spacing;
    int overflow_width = 0;
    int hidden_count = 0;

    if (!state || !state->toolbar_overflow_button) return;
    children = gtk_container_get_children(GTK_CONTAINER(toolbar));
    candidates = g_new0(GtkWidget*, g_list_length(children));
    spacing = gtk_box_get_spacing(GTK_BOX(toolbar));

    for (GList* it = children; it; it = it->next) {
        GtkWidget* child = GTK_WIDGET(it->data);
        if (child == state->toolbar_overflow_button) continue;
        if (g_object_get_data(G_OBJECT(child), "sumatra-overflow-hidden")) {
            g_object_set_data(G_OBJECT(child), "sumatra-overflow-hidden", NULL);
            gtk_widget_show(child);
        }
    }
    gtk_widget_hide(state->toolbar_overflow_button);

    for (GList* it = children; it; it = it->next) {
        GtkWidget* child = GTK_WIDGET(it->data);
        int priority;
        if (child == state->toolbar_overflow_button || !gtk_widget_get_visible(child)) continue;
        priority = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(child), "sumatra-overflow-priority"));
        total_width += widget_preferred_width(child);
        visible_count++;
        if (priority > 0) candidates[candidate_count++] = child;
    }
    if (visible_count > 1) total_width += spacing * (visible_count - 1);

    if (total_width > allocation->width && candidate_count > 0) {
        overflow_width = widget_preferred_width(state->toolbar_overflow_button);
        total_width += overflow_width + spacing;
        qsort(candidates, (size_t)candidate_count, sizeof(GtkWidget*), compare_toolbar_items_by_priority);
        for (int i = 0; i < candidate_count && total_width > allocation->width; ++i) {
            GtkWidget* child = candidates[i];
            GtkWidget* mirror = GTK_WIDGET(g_object_get_data(G_OBJECT(child), "sumatra-overflow-mirror"));
            total_width -= widget_preferred_width(child) + spacing;
            g_object_set_data(G_OBJECT(child), "sumatra-overflow-hidden", GINT_TO_POINTER(TRUE));
            gtk_widget_hide(child);
            if (mirror) gtk_widget_show(mirror);
            hidden_count++;
        }
    }

    for (int i = 0; i < candidate_count; ++i) {
        GtkWidget* mirror = GTK_WIDGET(g_object_get_data(G_OBJECT(candidates[i]), "sumatra-overflow-mirror"));
        if (!mirror) continue;
        if (g_object_get_data(G_OBJECT(candidates[i]), "sumatra-overflow-hidden"))
            gtk_widget_show(mirror);
        else
            gtk_widget_hide(mirror);
    }
    if (hidden_count > 0)
        gtk_widget_show(state->toolbar_overflow_button);
    else
        gtk_widget_hide(state->toolbar_overflow_button);

    update_toolbar_overflow_menu_state(state);
    g_free(candidates);
    g_list_free(children);
}

static void add_palette_header(GtkListBox* list, const char* text) {
    GtkWidget* row = gtk_list_box_row_new();
    GtkWidget* capsule = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    GtkWidget* label = gtk_label_new(NULL);
    char* escaped = g_markup_escape_text(text ? text : "", -1);
    char* markup = g_strdup_printf("<b>%s</b>", escaped);

    gtk_list_box_row_set_selectable(GTK_LIST_BOX_ROW(row), FALSE);
    gtk_list_box_row_set_activatable(GTK_LIST_BOX_ROW(row), FALSE);
    gtk_style_context_add_class(gtk_widget_get_style_context(capsule), "sumatra-palette-header");
    gtk_label_set_xalign(GTK_LABEL(label), 0.0);
    gtk_widget_set_margin_start(capsule, 8);
    gtk_widget_set_margin_end(capsule, 8);
    gtk_widget_set_margin_top(capsule, 8);
    gtk_widget_set_margin_bottom(capsule, 4);
    gtk_widget_set_margin_start(label, 12);
    gtk_widget_set_margin_end(label, 12);
    gtk_widget_set_margin_top(label, 5);
    gtk_widget_set_margin_bottom(label, 5);
    gtk_label_set_markup(GTK_LABEL(label), markup);
    gtk_container_add(GTK_CONTAINER(capsule), label);
    gtk_container_add(GTK_CONTAINER(row), capsule);
    gtk_container_add(GTK_CONTAINER(list), row);
    g_free(markup);
    g_free(escaped);
}

static void favorites_delete_clicked(GtkButton* button, gpointer user_data);

static void rebuild_favorites_list(GtkListBox* list, app_state* state, const char* filter) {
    GList* children = gtk_container_get_children(GTK_CONTAINER(list));
    for (GList* it = children; it; it = it->next) gtk_widget_destroy(GTK_WIDGET(it->data));
    g_list_free(children);

    install_palette_css();
    add_palette_header(list, "Favorites");

    for (int i = 0; i < state->favorite_count; ++i) {
        char text[1600];
        char* title;
        char* path;
        GtkWidget* row;
        GtkWidget* box;
        GtkWidget* button;
        GtkWidget* label;
        gboolean armed = state->favorite_pending_delete == i;
        if (!favorite_matches(&state->favorites[i], filter)) continue;
        title = display_label_without_extension(state->favorites[i].title ? state->favorites[i].title : "Favorite");
        path = display_path_without_extension(state->favorites[i].path ? state->favorites[i].path : "");
        snprintf(text, sizeof(text), "%s%s\n%s", title, state->favorites[i].document ? "" : " (page favorite)", path);
        g_free(title);
        g_free(path);
        row = gtk_list_box_row_new();
        box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        button = gtk_button_new_with_label(armed ? "Confirm Delete" : "x");
        label = gtk_label_new(text);
        gtk_label_set_xalign(GTK_LABEL(label), 0.0);
        gtk_widget_set_hexpand(label, TRUE);
        gtk_widget_set_margin_start(box, 8);
        gtk_widget_set_margin_end(box, 8);
        gtk_widget_set_margin_top(box, 5);
        gtk_widget_set_margin_bottom(box, 5);
        gtk_widget_set_margin_start(label, 0);
        gtk_widget_set_margin_end(label, 8);
        gtk_widget_set_margin_top(label, 1);
        gtk_widget_set_margin_bottom(label, 1);
        gtk_widget_set_size_request(button, armed ? 118 : 30, 28);
        gtk_widget_set_tooltip_text(button, armed ? "Click again to delete this favorite" : "Delete favorite");
        if (armed) gtk_style_context_add_class(gtk_widget_get_style_context(button), "sumatra-palette-delete-confirm");
        g_object_set_data(G_OBJECT(button), "favorite-index", GINT_TO_POINTER(i + 1));
        g_object_set_data(G_OBJECT(button), "favorites-list", list);
        g_signal_connect(button, "clicked", G_CALLBACK(favorites_delete_clicked), state);
        g_object_set_data(G_OBJECT(row), "favorite-index", GINT_TO_POINTER(i + 1));
        gtk_box_pack_start(GTK_BOX(box), button, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(box), label, TRUE, TRUE, 0);
        gtk_container_add(GTK_CONTAINER(row), box);
        gtk_container_add(GTK_CONTAINER(list), row);
    }

    if (filter && strlen(filter) >= 2 && !find_query_too_long(filter)) {
        char err[1024];
        int searched_pages = 0;
        add_palette_header(list, "Open documents");

        for (int tab_index = 0; tab_index < state->tab_count; ++tab_index) {
            document_tab* tab = &state->tabs[tab_index];
            spdf_document* doc = NULL;
            gboolean borrowed_doc = FALSE;
            char* display_path;
            if (!tab->path || !*tab->path || !g_file_test(tab->path, G_FILE_TEST_EXISTS)) continue;

            if (tab_index == state->selected_tab && state->doc) {
                doc = state->doc;
                borrowed_doc = TRUE;
            } else {
                doc = spdf_open(tab->path, err, sizeof(err));
            }
            if (!doc) continue;

            display_path = tab->title && *tab->title ? display_label_without_extension(tab->title)
                                                     : display_path_without_extension(tab->path);
            for (int page = 0; page < spdf_page_count(doc) && searched_pages < MAX_PALETTE_SEARCH_PAGES; ++page) {
                int hits = spdf_search_page(doc, page, filter, err, sizeof(err));
                searched_pages++;
                if (hits <= 0) continue;
                char text[1600];
                GtkWidget* row = gtk_list_box_row_new();
                GtkWidget* label;
                snprintf(text, sizeof(text), "%s\nPage %d - %d match%s", display_path, page + 1, hits,
                         hits == 1 ? "" : "es");
                label = gtk_label_new(text);
                gtk_label_set_xalign(GTK_LABEL(label), 0.0);
                gtk_widget_set_margin_start(label, 8);
                gtk_widget_set_margin_end(label, 8);
                gtk_widget_set_margin_top(label, 6);
                gtk_widget_set_margin_bottom(label, 6);
                g_object_set_data(G_OBJECT(row), "search-page", GINT_TO_POINTER(page + 1));
                g_object_set_data_full(G_OBJECT(row), "search-path", g_strdup(tab->path), g_free);
                g_object_set_data_full(G_OBJECT(row), "search-text", g_strdup(filter), g_free);
                gtk_container_add(GTK_CONTAINER(row), label);
                gtk_container_add(GTK_CONTAINER(list), row);
            }
            g_free(display_path);
            if (!borrowed_doc) spdf_close(doc);
            if (searched_pages >= MAX_PALETTE_SEARCH_PAGES) break;
        }
    }
    gtk_widget_show_all(GTK_WIDGET(list));
}

static GtkListBoxRow* favorites_action_row_at(GtkListBox* list, int start_index, int step);

static void favorites_search_changed(GtkEntry* entry, gpointer user_data) {
    GtkWidget* list = GTK_WIDGET(g_object_get_data(G_OBJECT(entry), "favorites-list"));
    app_state* state = (app_state*)user_data;
    state->favorite_pending_delete = -1;
    rebuild_favorites_list(GTK_LIST_BOX(list), state, gtk_entry_get_text(entry));
    gtk_list_box_select_row(GTK_LIST_BOX(list), favorites_action_row_at(GTK_LIST_BOX(list), 0, 1));
}

static void favorites_row_activated(GtkListBox* list, GtkListBoxRow* row, gpointer user_data);

static gboolean favorites_row_is_action(GtkListBoxRow* row) {
    return row &&
           (g_object_get_data(G_OBJECT(row), "favorite-index") || g_object_get_data(G_OBJECT(row), "search-page"));
}

static GtkListBoxRow* favorites_action_row_at(GtkListBox* list, int start_index, int step) {
    GList* children = gtk_container_get_children(GTK_CONTAINER(list));
    int count = 0;
    GtkListBoxRow* result = NULL;
    for (GList* rows = children; rows; rows = rows->next) count++;
    if (count <= 0) {
        g_list_free(children);
        return NULL;
    }

    for (int offset = 0; offset < count; ++offset) {
        int index = start_index + offset * step;
        GtkListBoxRow* row;
        if (index < 0 || index >= count) continue;
        row = gtk_list_box_get_row_at_index(list, index);
        if (favorites_row_is_action(row)) {
            result = row;
            break;
        }
    }
    g_list_free(children);
    return result;
}

static GtkListBoxRow* favorites_row_for_favorite_index(GtkListBox* list, int favorite_index) {
    GtkListBoxRow* row;
    for (int i = 0; (row = gtk_list_box_get_row_at_index(list, i)) != NULL; ++i) {
        int index = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(row), "favorite-index")) - 1;
        if (index == favorite_index) return row;
    }
    return NULL;
}

static const char* favorites_current_filter(GtkListBox* list) {
    GtkWidget* search = GTK_WIDGET(g_object_get_data(G_OBJECT(list), "favorites-search"));
    return search ? gtk_entry_get_text(GTK_ENTRY(search)) : "";
}

static void favorites_delete_clicked(GtkButton* button, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    GtkListBox* list = GTK_LIST_BOX(g_object_get_data(G_OBJECT(button), "favorites-list"));
    int index = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "favorite-index")) - 1;
    const char* filter;
    GtkListBoxRow* row;

    if (!list || index < 0 || index >= state->favorite_count) return;
    filter = favorites_current_filter(list);
    if (state->favorite_pending_delete == index) {
        remove_favorite_item(state, index);
        state->favorite_pending_delete = -1;
        save_favorites(state);
        rebuild_favorites_list(list, state, filter);
        gtk_list_box_select_row(list, favorites_action_row_at(list, 0, 1));
        gtk_label_set_text(GTK_LABEL(state->status), "Favorite deleted.");
        return;
    }

    state->favorite_pending_delete = index;
    rebuild_favorites_list(list, state, filter);
    row = favorites_row_for_favorite_index(list, index);
    if (row) gtk_list_box_select_row(list, row);
}

static void favorites_search_activate(GtkEntry* entry, gpointer user_data) {
    GtkWidget* list = GTK_WIDGET(g_object_get_data(G_OBJECT(entry), "favorites-list"));
    GtkListBoxRow* row = gtk_list_box_get_selected_row(GTK_LIST_BOX(list));
    if (!favorites_row_is_action(row)) row = favorites_action_row_at(GTK_LIST_BOX(list), 0, 1);
    favorites_row_activated(GTK_LIST_BOX(list), row, user_data);
}

static gboolean favorites_search_key_press(GtkWidget* widget, GdkEventKey* event, gpointer user_data) {
    (void)user_data;
    GtkWidget* list = GTK_WIDGET(g_object_get_data(G_OBJECT(widget), "favorites-list"));
    GtkWidget* dialog = GTK_WIDGET(g_object_get_data(G_OBJECT(list), "favorites-dialog"));
    GtkListBox* box = GTK_LIST_BOX(list);
    GtkListBoxRow* selected = gtk_list_box_get_selected_row(box);

    if (event->keyval == GDK_KEY_Escape) {
        gtk_dialog_response(GTK_DIALOG(dialog), GTK_RESPONSE_CLOSE);
        return TRUE;
    }
    if (event->keyval == GDK_KEY_Down || event->keyval == GDK_KEY_Up) {
        int current = selected ? gtk_list_box_row_get_index(selected) : (event->keyval == GDK_KEY_Down ? -1 : 999999);
        int step = event->keyval == GDK_KEY_Down ? 1 : -1;
        GtkListBoxRow* row = favorites_action_row_at(box, current + step, step);
        if (row) {
            gtk_list_box_select_row(box, row);
            gtk_list_box_row_changed(row);
        }
        return TRUE;
    }
    return FALSE;
}

static void favorites_row_activated(GtkListBox* list, GtkListBoxRow* row, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    GtkWidget* dialog = GTK_WIDGET(g_object_get_data(G_OBJECT(list), "favorites-dialog"));
    int index;
    if (!row) return;
    int search_page = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(row), "search-page"));
    if (search_page > 0) {
        const char* search_text = (const char*)g_object_get_data(G_OBJECT(row), "search-text");
        const char* search_path = (const char*)g_object_get_data(G_OBJECT(row), "search-path");
        state->favorite_pending_delete = -1;
        if (search_path && *search_path) open_path_in_tab_at_page(state, search_path, search_page - 1, FALSE);
        set_search_entry_text(state, search_text ? search_text : "");
        start_find_for_current_query(state, -1, search_page - 1, TRUE, FALSE);
        gtk_dialog_response(GTK_DIALOG(dialog), GTK_RESPONSE_ACCEPT);
        return;
    }
    index = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(row), "favorite-index")) - 1;
    if (index >= 0 && index < state->favorite_count) {
        favorite_item* favorite = &state->favorites[index];
        state->favorite_pending_delete = -1;
        set_search_entry_text(state, "");
        clear_find_results(state);
        open_path_in_tab_at_page(state, favorite->path, favorite->document ? 0 : favorite->page_index, TRUE);
        gtk_dialog_response(GTK_DIALOG(dialog), GTK_RESPONSE_ACCEPT);
    }
}

static void show_favorites_dialog(app_state* state) {
    GtkWidget* dialog = gtk_dialog_new_with_buttons("Command", GTK_WINDOW(state->window), GTK_DIALOG_MODAL, "_Close",
                                                    GTK_RESPONSE_CLOSE, NULL);
    GtkWidget* content = gtk_dialog_get_content_area(GTK_DIALOG(dialog));
    GtkWidget* search = gtk_search_entry_new();
    GtkWidget* scroll = gtk_scrolled_window_new(NULL, NULL);
    GtkWidget* list = gtk_list_box_new();

    gtk_window_set_default_size(GTK_WINDOW(dialog), 560, 420);
    gtk_entry_set_placeholder_text(GTK_ENTRY(search), "Favorites and open documents");
    state->favorite_pending_delete = -1;
    gtk_widget_set_margin_start(search, 8);
    gtk_widget_set_margin_end(search, 8);
    gtk_widget_set_margin_top(search, 8);
    gtk_widget_set_margin_bottom(search, 8);
    gtk_container_add(GTK_CONTAINER(scroll), list);
    gtk_box_pack_start(GTK_BOX(content), search, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(content), scroll, TRUE, TRUE, 0);
    g_object_set_data(G_OBJECT(search), "favorites-list", list);
    g_object_set_data(G_OBJECT(list), "favorites-search", search);
    g_object_set_data(G_OBJECT(list), "favorites-dialog", dialog);
    g_signal_connect(search, "search-changed", G_CALLBACK(favorites_search_changed), state);
    g_signal_connect(search, "activate", G_CALLBACK(favorites_search_activate), state);
    g_signal_connect(search, "key-press-event", G_CALLBACK(favorites_search_key_press), state);
    g_signal_connect(list, "row-activated", G_CALLBACK(favorites_row_activated), state);
    rebuild_favorites_list(GTK_LIST_BOX(list), state, "");
    gtk_list_box_select_row(GTK_LIST_BOX(list), favorites_action_row_at(GTK_LIST_BOX(list), 0, 1));
    gtk_widget_show_all(dialog);
    gtk_widget_grab_focus(search);
    gtk_dialog_run(GTK_DIALOG(dialog));
    state->favorite_pending_delete = -1;
    gtk_widget_destroy(dialog);
}

static gboolean key_press(GtkWidget* widget, GdkEventKey* event, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    gboolean ctrl = (event->state & GDK_CONTROL_MASK) != 0;
    gboolean shift = (event->state & GDK_SHIFT_MASK) != 0;
    GtkWidget* focus = state->window ? gtk_window_get_focus(GTK_WINDOW(state->window)) : NULL;
    (void)widget;

    if (state->presentation_mode && event->keyval == GDK_KEY_Escape) {
        set_presentation_mode(state, FALSE);
        return TRUE;
    }
    if (!ctrl && event->keyval == GDK_KEY_F5) {
        set_presentation_mode(state, TRUE);
        return state->doc != NULL;
    }
    if (ctrl && (event->keyval == GDK_KEY_f || event->keyval == GDK_KEY_F)) {
        gtk_widget_grab_focus(state->search_entry);
        gtk_editable_select_region(GTK_EDITABLE(state->search_entry), 0, -1);
        return TRUE;
    }
    if (ctrl && (event->keyval == GDK_KEY_k || event->keyval == GDK_KEY_K)) {
        show_favorites_dialog(state);
        return TRUE;
    }
    if (ctrl && shift && (event->keyval == GDK_KEY_t || event->keyval == GDK_KEY_T)) {
        if (state->closed_count == 0) return FALSE;
        reopen_last_closed_document(state);
        return TRUE;
    }
    if (ctrl && (event->keyval == GDK_KEY_b || event->keyval == GDK_KEY_B)) {
        if (!state->doc || !state->path) return FALSE;
        add_current_favorite(state, shift);
        return TRUE;
    }

    if (state->presentation_mode && state->doc && !ctrl) {
        if (event->keyval == GDK_KEY_space || event->keyval == GDK_KEY_KP_Space) {
            next_clicked(NULL, state);
            return TRUE;
        }
        if (event->keyval == GDK_KEY_Left || event->keyval == GDK_KEY_Up) {
            previous_clicked(NULL, state);
            return TRUE;
        }
        if (event->keyval == GDK_KEY_Right || event->keyval == GDK_KEY_Down) {
            next_clicked(NULL, state);
            return TRUE;
        }
    }

    if (ctrl || !state->doc || (focus && GTK_IS_EDITABLE(focus))) return FALSE;
    if (state->presentation_mode && (event->keyval == GDK_KEY_space || event->keyval == GDK_KEY_KP_Space)) {
        next_clicked(NULL, state);
        return TRUE;
    }
    if (event->keyval == GDK_KEY_Left || event->keyval == GDK_KEY_Up || event->keyval == GDK_KEY_Right ||
        event->keyval == GDK_KEY_Down) {
        if (!state->continuous_mode) {
            if (event->keyval == GDK_KEY_Left || event->keyval == GDK_KEY_Up)
                previous_clicked(NULL, state);
            else
                next_clicked(NULL, state);
            return TRUE;
        }

        GtkAdjustment* adjustment = (event->keyval == GDK_KEY_Left || event->keyval == GDK_KEY_Right)
                                        ? gtk_scrolled_window_get_hadjustment(GTK_SCROLLED_WINDOW(state->scroll))
                                        : gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(state->scroll));
        double delta = (event->keyval == GDK_KEY_Left || event->keyval == GDK_KEY_Up) ? -54.0 : 54.0;
        double lower = gtk_adjustment_get_lower(adjustment);
        double upper = gtk_adjustment_get_upper(adjustment) - gtk_adjustment_get_page_size(adjustment);
        gtk_adjustment_set_value(adjustment, MAX(lower, MIN(gtk_adjustment_get_value(adjustment) + delta, upper)));
        if (event->keyval == GDK_KEY_Left || event->keyval == GDK_KEY_Right) clamp_horizontal_scroll(state);
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
    for (int i = 0; uris && uris[i]; ++i) {
        char* path = g_filename_from_uri(uris[i], NULL, NULL);
        if (path) {
            open_path(state, path);
            g_free(path);
        }
    }
    g_strfreev(uris);
    gtk_drag_finish(context, TRUE, FALSE, time);
}

static void vertical_scroll_changed(GtkAdjustment* adjustment, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    GList* children;
    int page = 0;
    int best_page = -1;
    double viewport_mid;
    double best_distance = 0.0;

    if (!state->doc || !state->continuous_mode || !state->page_box) return;
    viewport_mid = gtk_adjustment_get_value(adjustment) + gtk_adjustment_get_page_size(adjustment) * 0.5;
    children = gtk_container_get_children(GTK_CONTAINER(state->page_box));
    for (GList* it = children; it; it = it->next, ++page) {
        GtkAllocation allocation;
        double center;
        double distance;
        gtk_widget_get_allocation(GTK_WIDGET(it->data), &allocation);
        if (allocation.height <= 0) continue;
        center = allocation.y + allocation.height * 0.5;
        distance = center > viewport_mid ? center - viewport_mid : viewport_mid - center;
        if (best_page < 0 || distance < best_distance) {
            best_page = page;
            best_distance = distance;
        }
    }
    g_list_free(children);

    if (best_page >= 0 && best_page != state->page_index) {
        state->page_index = best_page;
        schedule_background_render(state);
        evict_distant_page_surfaces(state);
        clamp_horizontal_scroll(state);
        update_controls(state);
        save_active_tab_state(state);
        if (!state->switching_tabs) save_session(state);
    }
    if (state->minimap) gtk_widget_queue_draw(state->minimap);
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

static gboolean presentation_button_press(GtkWidget* widget, GdkEventButton* event, gpointer user_data) {
    (void)widget;
    app_state* state = (app_state*)user_data;

    if (state->presentation_mode && state->doc) {
        if (event->button == 1) {
            next_clicked(NULL, state);
            return TRUE;
        }
        if (event->button == 3) {
            previous_clicked(NULL, state);
            return TRUE;
        }
    }
    return FALSE;
}

static gboolean page_button_press(GtkWidget* widget, GdkEventButton* event, gpointer user_data) {
    app_state* state = (app_state*)user_data;

    if (presentation_button_press(widget, event, user_data)) return TRUE;

    if (event->button == 3) {
        GtkWidget* menu = gtk_menu_new();
        GtkWidget* edit_comment = gtk_menu_item_new_with_label("Edit Comment...");
        GtkWidget* delete_comment = gtk_menu_item_new_with_label("Delete Comment...");
        GtkWidget* add_comment = gtk_menu_item_new_with_label("Add Comment...");
        int page_index = -1;
        double page_x = 0.0;
        double page_y = 0.0;
        GtkWidget* show_folder = gtk_menu_item_new_with_label("Show in Folder");
        state->context_page_index = -1;
        state->context_comment_index = -1;
        if (page_point_from_widget_point(state, widget, event->x, event->y, &page_index, &page_x, &page_y)) {
            state->context_page_index = page_index;
            state->context_page_x = page_x;
            state->context_page_y = page_y;
            state->context_comment_index = comment_index_at_page_point(state, page_index, page_x, page_y);
        }
        gtk_widget_set_sensitive(edit_comment, state->doc != NULL && state->context_comment_index >= 0);
        gtk_widget_set_sensitive(delete_comment, state->doc != NULL && state->context_comment_index >= 0);
        if (state->context_comment_index >= 0) {
            g_object_set_data(G_OBJECT(edit_comment), "comment-index",
                              GINT_TO_POINTER(state->context_comment_index + 1));
            g_object_set_data(G_OBJECT(delete_comment), "comment-index",
                              GINT_TO_POINTER(state->context_comment_index + 1));
        }
        g_signal_connect(edit_comment, "activate", G_CALLBACK(edit_comment_clicked), state);
        g_signal_connect(delete_comment, "activate", G_CALLBACK(delete_comment_clicked), state);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), edit_comment);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), delete_comment);
        gtk_widget_set_sensitive(add_comment, state->doc != NULL && (has_text_selection(state) || page_index >= 0));
        g_signal_connect(add_comment, "activate", G_CALLBACK(add_comment_clicked), state);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), add_comment);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), gtk_separator_menu_item_new());
        gtk_widget_set_sensitive(show_folder, state->doc != NULL && state->path != NULL);
        g_signal_connect(show_folder, "activate", G_CALLBACK(show_in_folder), state);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), show_folder);
        gtk_widget_show_all(menu);
        gtk_menu_popup_at_pointer(GTK_MENU(menu), (GdkEvent*)event);
        return TRUE;
    }

    if (event->button == 1 && state->doc) {
        int page_index = -1;
        double page_x = 0.0;
        double page_y = 0.0;
        if (!page_point_from_widget_point(state, widget, event->x, event->y, &page_index, &page_x, &page_y))
            return FALSE;
        if (open_link_at_page_point(state, page_index, page_x, page_y, event->time)) return TRUE;
        if (clear_text_selection(state)) render_current_page_preserving_scroll(state);
        state->selecting = TRUE;
        state->selection_page_index = page_index;
        state->selection_start_x = page_x;
        state->selection_start_y = page_y;
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
    app_state* state = (app_state*)user_data;
    if (state->selecting) {
        double page_x = 0.0;
        double page_y = 0.0;
        if (page_point_for_page_from_widget_point(state, state->selection_page_index, widget, event->x, event->y,
                                                  &page_x, &page_y)) {
            update_text_selection(state, state->selection_page_index, page_x, page_y, FALSE);
        }
        return TRUE;
    }

    if (!state->panning) {
        int page_index = -1;
        double page_x = 0.0;
        double page_y = 0.0;
        gboolean over_link =
            page_point_from_widget_point(state, widget, event->x, event->y, &page_index, &page_x, &page_y) &&
            link_at_page_point(state, page_index, page_x, page_y);
        set_page_link_cursor(widget, over_link);
        return FALSE;
    }

    GtkAdjustment* hadj = gtk_scrolled_window_get_hadjustment(GTK_SCROLLED_WINDOW(state->scroll));
    GtkAdjustment* vadj = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(state->scroll));
    gtk_adjustment_set_value(hadj, state->pan_start_h - (event->x_root - state->pan_start_x));
    gtk_adjustment_set_value(vadj, state->pan_start_v - (event->y_root - state->pan_start_y));
    clamp_horizontal_scroll(state);
    return TRUE;
}

static gboolean page_leave(GtkWidget* widget, GdkEventCrossing* event, gpointer user_data) {
    (void)event;
    (void)user_data;
    set_page_link_cursor(widget, FALSE);
    return FALSE;
}

static gboolean page_button_release(GtkWidget* widget, GdkEventButton* event, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    if (event->button == 1 && state->selecting) {
        double page_x = 0.0;
        double page_y = 0.0;
        if (page_point_for_page_from_widget_point(state, state->selection_page_index, widget, event->x, event->y,
                                                  &page_x, &page_y)) {
            update_text_selection(state, state->selection_page_index, page_x, page_y, TRUE);
            if (!has_text_selection(state)) clear_text_selection(state);
        } else {
            clear_text_selection(state);
            render_current_page_preserving_scroll(state);
        }
        state->selecting = FALSE;
        return TRUE;
    }
    state->panning = FALSE;
    return FALSE;
}

static gboolean startup_restore_idle(gpointer user_data) {
    app_state* state = (app_state*)user_data;

    state->startup_restore_idle_id = 0;
    if (!state->window) return G_SOURCE_REMOVE;

    if (!state->suppress_restore_once && state->tab_count > 0) {
        int index = state->restore_selected_tab >= 0 ? state->restore_selected_tab : 0;
        state->defer_find_until_idle = TRUE;
        select_tab(state, MAX(0, MIN(index, state->tab_count - 1)));
        state->defer_find_until_idle = FALSE;
    } else if (!state->suppress_restore_once && !state->doc && state->restore_path && *state->restore_path) {
        open_path_in_tab_at_page(state, state->restore_path, state->restore_page_index, FALSE);
        if (state->restore_search_text && *state->restore_search_text) {
            set_search_entry_text(state, state->restore_search_text);
            schedule_deferred_find(state, state->restore_find_match_index, state->restore_page_index, FALSE, TRUE);
        }
    } else {
        update_tab_strip(state);
    }
    state->suppress_restore_once = FALSE;
    return G_SOURCE_REMOVE;
}

static gboolean window_configure_event(GtkWidget* widget, GdkEventConfigure* event, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    (void)widget;
    if (state->presentation_mode && state->doc) {
        g_idle_add(presentation_render_idle, state);
    } else if (!state->window_fullscreen) {
        state->window_width = clamp_int(event->width, MIN_WINDOW_WIDTH, MAX_WINDOW_WIDTH);
        state->window_height = clamp_int(event->height, MIN_WINDOW_HEIGHT, MAX_WINDOW_HEIGHT);
    }
    return FALSE;
}

static gboolean window_state_event(GtkWidget* widget, GdkEventWindowState* event, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    (void)widget;
    state->window_fullscreen = (event->new_window_state & GDK_WINDOW_STATE_FULLSCREEN) != 0;
    if (state->presentation_mode && state->window_fullscreen && state->doc) g_idle_add(presentation_render_idle, state);
    return FALSE;
}

static void activate(GtkApplication* app, gpointer user_data) {
    app_state* state = (app_state*)user_data;
    state->app = app;
    if (state->zoom <= 0.0) state->zoom = 1.0;

    state->window = gtk_application_window_new(app);
    gtk_widget_add_events(state->window, GDK_BUTTON_PRESS_MASK | GDK_KEY_PRESS_MASK);
    gtk_window_set_title(GTK_WINDOW(state->window), "SumatraPDF");
    gtk_window_set_default_size(GTK_WINDOW(state->window),
                                clamp_int(state->window_width, MIN_WINDOW_WIDTH, MAX_WINDOW_WIDTH),
                                clamp_int(state->window_height, MIN_WINDOW_HEIGHT, MAX_WINDOW_HEIGHT));

    GtkWidget* root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_container_add(GTK_CONTAINER(state->window), root);

    GtkAccelGroup* accel_group = gtk_accel_group_new();
    gtk_window_add_accel_group(GTK_WINDOW(state->window), accel_group);

    GtkWidget* menubar = gtk_menu_bar_new();
    GtkWidget* file_menu = gtk_menu_new();
    GtkWidget* file = gtk_menu_item_new_with_mnemonic("_File");
    GtkWidget* open_menu = gtk_menu_item_new_with_mnemonic("_Open...");
    state->reopen_closed_menu_item = gtk_menu_item_new_with_mnemonic("Reopen Last _Closed");
    GtkWidget* recently_opened = gtk_menu_item_new_with_mnemonic("Recently _Opened");
    state->recently_opened_menu = gtk_menu_new();
    state->open_in_browser = gtk_menu_item_new_with_mnemonic("Open in Default _Browser");
    state->show_in_folder = gtk_menu_item_new_with_mnemonic("Show in _Folder");
    GtkWidget* quit_menu = gtk_menu_item_new_with_mnemonic("_Quit");
    GtkWidget* edit_menu = gtk_menu_new();
    GtkWidget* edit = gtk_menu_item_new_with_mnemonic("_Edit");
    GtkWidget* set_comment_author = gtk_menu_item_new_with_mnemonic("Set _Author for Comments...");
    state->translate_menu_item = gtk_menu_item_new_with_mnemonic("_Translate...");
    state->search_regex_multiline_item = gtk_check_menu_item_new_with_mnemonic("Regex _Multiline");
    GtkWidget* view_menu = gtk_menu_new();
    GtkWidget* view = gtk_menu_item_new_with_mnemonic("_View");
    state->show_sidebar_item = gtk_check_menu_item_new_with_mnemonic("Show Side _Panel");
    state->show_minimap_item = gtk_check_menu_item_new_with_mnemonic("Show _Minimap");
    state->presentation_item = gtk_check_menu_item_new_with_mnemonic("_Presentation Mode");
    gtk_widget_add_accelerator(state->presentation_item, "activate", accel_group, GDK_KEY_F5, 0, GTK_ACCEL_VISIBLE);
    gtk_widget_add_accelerator(state->reopen_closed_menu_item, "activate", accel_group, GDK_KEY_t,
                               GDK_CONTROL_MASK | GDK_SHIFT_MASK, GTK_ACCEL_VISIBLE);
    gtk_widget_set_sensitive(state->reopen_closed_menu_item, state->closed_count > 0);
    g_object_unref(accel_group);
    gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(state->show_sidebar_item), state->show_sidebar);
    gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(state->show_minimap_item), state->show_minimap);
    gtk_menu_item_set_submenu(GTK_MENU_ITEM(file), file_menu);
    gtk_menu_item_set_submenu(GTK_MENU_ITEM(recently_opened), state->recently_opened_menu);
    gtk_menu_shell_append(GTK_MENU_SHELL(file_menu), open_menu);
    gtk_menu_shell_append(GTK_MENU_SHELL(file_menu), state->reopen_closed_menu_item);
    gtk_menu_shell_append(GTK_MENU_SHELL(file_menu), recently_opened);
    gtk_menu_shell_append(GTK_MENU_SHELL(file_menu), gtk_separator_menu_item_new());
    gtk_menu_shell_append(GTK_MENU_SHELL(file_menu), state->open_in_browser);
    gtk_menu_shell_append(GTK_MENU_SHELL(file_menu), state->show_in_folder);
    gtk_menu_shell_append(GTK_MENU_SHELL(file_menu), gtk_separator_menu_item_new());
    gtk_menu_shell_append(GTK_MENU_SHELL(file_menu), quit_menu);
    update_recent_menu(state);
    gtk_menu_shell_append(GTK_MENU_SHELL(menubar), file);
    gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(state->search_regex_multiline_item),
                                   state->search_regex_multiline);
    gtk_menu_item_set_submenu(GTK_MENU_ITEM(edit), edit_menu);
    gtk_menu_shell_append(GTK_MENU_SHELL(edit_menu), set_comment_author);
    gtk_menu_shell_append(GTK_MENU_SHELL(edit_menu), state->translate_menu_item);
    gtk_menu_shell_append(GTK_MENU_SHELL(edit_menu), gtk_separator_menu_item_new());
    gtk_menu_shell_append(GTK_MENU_SHELL(edit_menu), state->search_regex_multiline_item);
    gtk_menu_shell_append(GTK_MENU_SHELL(menubar), edit);
    gtk_menu_item_set_submenu(GTK_MENU_ITEM(view), view_menu);
    gtk_menu_shell_append(GTK_MENU_SHELL(view_menu), state->show_sidebar_item);
    gtk_menu_shell_append(GTK_MENU_SHELL(view_menu), state->show_minimap_item);
    gtk_menu_shell_append(GTK_MENU_SHELL(view_menu), gtk_separator_menu_item_new());
    gtk_menu_shell_append(GTK_MENU_SHELL(view_menu), state->presentation_item);
    gtk_menu_shell_append(GTK_MENU_SHELL(menubar), view);
    gtk_box_pack_start(GTK_BOX(root), menubar, FALSE, FALSE, 0);
    state->menubar = menubar;

    state->tab_strip = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    gtk_widget_set_margin_start(state->tab_strip, 8);
    gtk_widget_set_margin_end(state->tab_strip, 8);
    gtk_widget_set_margin_top(state->tab_strip, 4);
    gtk_widget_set_margin_bottom(state->tab_strip, 0);
    state->tab_bar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 2);
    gtk_widget_set_hexpand(state->tab_bar, TRUE);
    state->new_tab_button = gtk_button_new_with_label("+");
    gtk_widget_set_tooltip_text(state->new_tab_button, "Open document in a new tab");
    gtk_widget_set_size_request(state->new_tab_button, 32, 28);
    gtk_box_pack_start(GTK_BOX(state->tab_strip), state->tab_bar, TRUE, TRUE, 0);
    gtk_box_pack_start(GTK_BOX(state->tab_strip), state->new_tab_button, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(root), state->tab_strip, FALSE, FALSE, 0);

    install_toolbar_css();

    GtkWidget* toolbar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 5);
    gtk_widget_set_margin_start(toolbar, 8);
    gtk_widget_set_margin_end(toolbar, 8);
    gtk_widget_set_margin_top(toolbar, 6);
    gtk_widget_set_margin_bottom(toolbar, 6);
    gtk_style_context_add_class(gtk_widget_get_style_context(toolbar), "sumatra-toolbar");
    gtk_box_pack_start(GTK_BOX(root), toolbar, FALSE, FALSE, 0);
    state->toolbar = toolbar;

    GtkWidget* open = gtk_button_new_with_label("Open");
    GtkWidget* prev = gtk_button_new_with_label("<");
    GtkWidget* next = gtk_button_new_with_label(">");
    state->side_panel_control = toolbar_switch_control_new("Side panel", &state->side_panel_button);
    gtk_widget_set_tooltip_text(state->side_panel_control, "Show or hide the side panel");
    gtk_widget_set_tooltip_text(state->side_panel_button, "Show or hide the side panel");
    state->minimap_control = toolbar_switch_control_new("Map", &state->minimap_button);
    gtk_widget_set_tooltip_text(state->minimap_control, "Show or hide the minimap");
    gtk_widget_set_tooltip_text(state->minimap_button, "Show or hide the minimap");
    state->marker_strip_control = toolbar_switch_control_new("Markers", &state->marker_strip_button);
    gtk_widget_set_tooltip_text(state->marker_strip_control, "Show or hide the find marker strip");
    gtk_widget_set_tooltip_text(state->marker_strip_button, "Show or hide the find marker strip");
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
    gtk_widget_set_tooltip_text(state->continuous, "Continuous scrolling");
    GtkWidget* continuous_label = gtk_bin_get_child(GTK_BIN(state->continuous));
    if (GTK_IS_LABEL(continuous_label)) {
        gtk_label_set_ellipsize(GTK_LABEL(continuous_label), PANGO_ELLIPSIZE_END);
        gtk_label_set_single_line_mode(GTK_LABEL(continuous_label), TRUE);
    }
    gtk_widget_set_size_request(state->continuous, 104, -1);
    state->search_entry = gtk_search_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(state->search_entry), "Find");
    if (state->tab_count == 0 && state->restore_search_text) set_search_entry_text(state, state->restore_search_text);
    state->search_regex_check = gtk_check_button_new_with_label("Regex");
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(state->search_regex_check), state->search_regex);
    GtkWidget* regex_label = gtk_bin_get_child(GTK_BIN(state->search_regex_check));
    if (GTK_IS_LABEL(regex_label)) {
        gtk_label_set_ellipsize(GTK_LABEL(regex_label), PANGO_ELLIPSIZE_END);
        gtk_label_set_single_line_mode(GTK_LABEL(regex_label), TRUE);
    }
    gtk_widget_set_size_request(state->search_regex_check, 68, -1);
    state->search_regex_multiline_check = gtk_check_button_new_with_label("Multiline");
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(state->search_regex_multiline_check), state->search_regex_multiline);
    state->find_count_label = gtk_label_new("");
    state->find_prev_button = gtk_button_new_with_label("<");
    state->find_next_button = gtk_button_new_with_label(">");
    state->translate_button = gtk_button_new();
    GtkWidget* translate_icon = gtk_drawing_area_new();
    gtk_widget_set_size_request(translate_icon, 22, 20);
    gtk_container_add(GTK_CONTAINER(state->translate_button), translate_icon);
    gtk_widget_show(translate_icon);
    g_signal_connect(translate_icon, "draw", G_CALLBACK(translate_icon_draw), NULL);
    gtk_widget_set_tooltip_text(state->translate_button, "Translate selection or document");
    state->ocr_button = gtk_button_new_with_label("OCR");
    gtk_entry_set_width_chars(GTK_ENTRY(state->search_entry), 10);
    gtk_entry_set_max_width_chars(GTK_ENTRY(state->search_entry), 13);
    gtk_widget_set_margin_start(state->search_entry, 3);
    gtk_widget_set_margin_end(state->search_entry, 3);
    gtk_widget_set_size_request(state->search_entry, 96, -1);
    gtk_widget_set_hexpand(state->search_entry, FALSE);

    state->toolbar_overflow_button = gtk_menu_button_new();
    GtkWidget* overflow_icon = gtk_drawing_area_new();
    gtk_widget_set_size_request(overflow_icon, 22, 20);
    gtk_container_add(GTK_CONTAINER(state->toolbar_overflow_button), overflow_icon);
    gtk_widget_show(overflow_icon);
    g_signal_connect(overflow_icon, "draw", G_CALLBACK(toolbar_overflow_icon_draw), NULL);
    gtk_widget_set_tooltip_text(state->toolbar_overflow_button, "More toolbar actions");
    gtk_widget_set_no_show_all(state->toolbar_overflow_button, TRUE);
    gtk_widget_set_size_request(state->toolbar_overflow_button, 30, 26);
    gtk_style_context_add_class(gtk_widget_get_style_context(state->toolbar_overflow_button),
                                "sumatra-toolbar-overflow");
    state->toolbar_overflow_menu = gtk_menu_new();
    gtk_menu_button_set_popup(GTK_MENU_BUTTON(state->toolbar_overflow_button), state->toolbar_overflow_menu);
    state->overflow_side_panel_item = gtk_check_menu_item_new_with_label("Side panel");
    state->overflow_minimap_item = gtk_check_menu_item_new_with_label("Minimap");
    state->overflow_marker_strip_item = gtk_check_menu_item_new_with_label("Markers");
    state->overflow_continuous_item = gtk_check_menu_item_new_with_label("Continuous");
    state->overflow_search_regex_item = gtk_check_menu_item_new_with_label("Regex");
    state->overflow_search_regex_multiline_item = gtk_check_menu_item_new_with_label("Regex multiline");
    state->overflow_translate_item = gtk_menu_item_new_with_label("Translate...");
    GtkWidget* overflow_fit_menu = gtk_menu_new();
    GtkWidget* overflow_fit = gtk_menu_item_new_with_label("Fit mode");
    GSList* fit_group = NULL;
    const char* fit_labels[] = {"Custom", "Actual", "Fit width", "Fit height", "Fit page"};
    for (int i = 0; i < 5; ++i) {
        state->overflow_fit_mode_items[i] = gtk_radio_menu_item_new_with_label(fit_group, fit_labels[i]);
        fit_group = gtk_radio_menu_item_get_group(GTK_RADIO_MENU_ITEM(state->overflow_fit_mode_items[i]));
        g_object_set_data(G_OBJECT(state->overflow_fit_mode_items[i]), "sumatra-fit-mode", GINT_TO_POINTER(i));
        gtk_menu_shell_append(GTK_MENU_SHELL(overflow_fit_menu), state->overflow_fit_mode_items[i]);
    }
    gtk_menu_item_set_submenu(GTK_MENU_ITEM(overflow_fit), overflow_fit_menu);
    GtkWidget* overflow_ocr = gtk_menu_item_new_with_label("OCR");
    gtk_menu_shell_append(GTK_MENU_SHELL(state->toolbar_overflow_menu), state->overflow_side_panel_item);
    gtk_menu_shell_append(GTK_MENU_SHELL(state->toolbar_overflow_menu), state->overflow_minimap_item);
    gtk_menu_shell_append(GTK_MENU_SHELL(state->toolbar_overflow_menu), state->overflow_marker_strip_item);
    gtk_menu_shell_append(GTK_MENU_SHELL(state->toolbar_overflow_menu), overflow_fit);
    gtk_menu_shell_append(GTK_MENU_SHELL(state->toolbar_overflow_menu), state->overflow_continuous_item);
    gtk_menu_shell_append(GTK_MENU_SHELL(state->toolbar_overflow_menu), state->overflow_search_regex_item);
    gtk_menu_shell_append(GTK_MENU_SHELL(state->toolbar_overflow_menu), state->overflow_search_regex_multiline_item);
    gtk_menu_shell_append(GTK_MENU_SHELL(state->toolbar_overflow_menu), state->overflow_translate_item);
    gtk_menu_shell_append(GTK_MENU_SHELL(state->toolbar_overflow_menu), overflow_ocr);
    gtk_widget_show_all(state->toolbar_overflow_menu);
    gtk_widget_hide(state->toolbar_overflow_button);

    toolbar_pack_item(toolbar, open, 0, NULL);
    toolbar_pack_item(toolbar, prev, 0, NULL);
    toolbar_pack_item(toolbar, next, 0, NULL);
    toolbar_pack_item(toolbar, state->side_panel_control, 50, state->overflow_side_panel_item);
    toolbar_pack_item(toolbar, state->minimap_control, 55, state->overflow_minimap_item);
    toolbar_pack_item(toolbar, state->page_entry, 0, NULL);
    toolbar_pack_item(toolbar, state->page_count_label, 0, NULL);
    toolbar_pack_item(toolbar, zoom_out, 0, NULL);
    toolbar_pack_item(toolbar, zoom_in, 0, NULL);
    toolbar_pack_item(toolbar, state->fit_mode, 40, overflow_fit);
    toolbar_pack_item(toolbar, state->continuous, 70, state->overflow_continuous_item);
    gtk_box_pack_start(GTK_BOX(toolbar), state->search_entry, FALSE, FALSE, 0);
    toolbar_pack_item(toolbar, state->find_count_label, 88, NULL);
    toolbar_pack_item(toolbar, state->find_prev_button, 86, NULL);
    toolbar_pack_item(toolbar, state->find_next_button, 86, NULL);
    toolbar_pack_item(toolbar, state->search_regex_check, 84, state->overflow_search_regex_item);
    toolbar_pack_item(toolbar, state->search_regex_multiline_check, 82, state->overflow_search_regex_multiline_item);
    toolbar_pack_item(toolbar, state->translate_button, 62, state->overflow_translate_item);
    toolbar_pack_item(toolbar, state->ocr_button, 100, overflow_ocr);
    GtkWidget* toolbar_spacer = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_box_pack_start(GTK_BOX(toolbar), toolbar_spacer, TRUE, TRUE, 0);
    gtk_box_pack_start(GTK_BOX(toolbar), state->toolbar_overflow_button, FALSE, FALSE, 0);
    toolbar_pack_item(toolbar, state->marker_strip_control, 60, state->overflow_marker_strip_item);

    GtkWidget* paned = gtk_paned_new(GTK_ORIENTATION_HORIZONTAL);
    state->main_paned = paned;
    gtk_box_pack_start(GTK_BOX(root), paned, TRUE, TRUE, 0);
    state->sidebar_container = gtk_notebook_new();
    state->sidebar_tabs = state->sidebar_container;
    gtk_widget_set_size_request(state->sidebar_container, 180, -1);
    state->sidebar = gtk_list_box_new();
    state->comments_sidebar = gtk_list_box_new();
    gtk_widget_add_events(state->comments_sidebar, GDK_BUTTON_PRESS_MASK);
    GtkWidget* chapters_scroll = gtk_scrolled_window_new(NULL, NULL);
    GtkWidget* comments_scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_container_add(GTK_CONTAINER(chapters_scroll), state->sidebar);
    gtk_container_add(GTK_CONTAINER(comments_scroll), state->comments_sidebar);
    gtk_notebook_append_page(GTK_NOTEBOOK(state->sidebar_tabs), chapters_scroll, gtk_label_new("Chapters"));
    gtk_notebook_append_page(GTK_NOTEBOOK(state->sidebar_tabs), comments_scroll, gtk_label_new("Comments"));
    gtk_paned_pack1(GTK_PANED(paned), state->sidebar_container, FALSE, FALSE);

    GtkWidget* document_view = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    state->scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_widget_set_can_focus(state->scroll, TRUE);
    gtk_widget_add_events(state->scroll, GDK_BUTTON_PRESS_MASK | GDK_KEY_PRESS_MASK);
    g_signal_connect(gtk_scrolled_window_get_hadjustment(GTK_SCROLLED_WINDOW(state->scroll)), "value-changed",
                     G_CALLBACK(horizontal_scroll_changed), state);
    g_signal_connect(gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(state->scroll)), "value-changed",
                     G_CALLBACK(vertical_scroll_changed), state);
    state->find_markers = gtk_drawing_area_new();
    gtk_widget_set_size_request(state->find_markers, 8, -1);
    gtk_widget_set_tooltip_text(state->find_markers, "Find matches");
    state->minimap = gtk_drawing_area_new();
    gtk_widget_set_size_request(state->minimap, MINIMAP_WIDTH, -1);
    gtk_widget_set_tooltip_text(state->minimap, "Document minimap");
    gtk_widget_add_events(state->minimap,
                          GDK_BUTTON_PRESS_MASK | GDK_BUTTON_RELEASE_MASK | GDK_POINTER_MOTION_MASK | GDK_SCROLL_MASK);
    GtkWidget* page_box = gtk_event_box_new();
    gtk_widget_add_events(page_box, GDK_BUTTON_PRESS_MASK | GDK_BUTTON_RELEASE_MASK | GDK_POINTER_MOTION_MASK |
                                        GDK_LEAVE_NOTIFY_MASK | GDK_SCROLL_MASK);
    gtk_event_box_set_visible_window(GTK_EVENT_BOX(page_box), FALSE);
    gtk_widget_set_hexpand(page_box, TRUE);
    gtk_widget_set_vexpand(page_box, TRUE);
    state->page_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_widget_set_halign(state->page_box, GTK_ALIGN_CENTER);
    gtk_container_add(GTK_CONTAINER(page_box), state->page_box);
    gtk_container_add(GTK_CONTAINER(state->scroll), page_box);
    gtk_box_pack_start(GTK_BOX(document_view), state->scroll, TRUE, TRUE, 0);
    gtk_box_pack_start(GTK_BOX(document_view), state->find_markers, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(document_view), state->minimap, FALSE, FALSE, 0);
    gtk_paned_pack2(GTK_PANED(paned), document_view, TRUE, FALSE);
    gtk_paned_set_position(GTK_PANED(paned), state->sidebar_width);

    state->status = gtk_label_new("Ready");
    gtk_label_set_xalign(GTK_LABEL(state->status), 0.0);
    gtk_widget_set_margin_start(state->status, 8);
    gtk_widget_set_margin_end(state->status, 8);
    gtk_box_pack_start(GTK_BOX(root), state->status, FALSE, FALSE, 3);

    g_signal_connect(open, "clicked", G_CALLBACK(open_clicked), state);
    g_signal_connect(state->new_tab_button, "clicked", G_CALLBACK(open_clicked), state);
    g_signal_connect(open_menu, "activate", G_CALLBACK(open_clicked), state);
    g_signal_connect_swapped(state->reopen_closed_menu_item, "activate", G_CALLBACK(reopen_last_closed_document),
                             state);
    g_signal_connect(state->open_in_browser, "activate", G_CALLBACK(open_in_browser), state);
    g_signal_connect(state->show_in_folder, "activate", G_CALLBACK(show_in_folder), state);
    g_signal_connect(set_comment_author, "activate", G_CALLBACK(set_comment_author_clicked), state);
    g_signal_connect(state->translate_menu_item, "activate", G_CALLBACK(translate_clicked), state);
    g_signal_connect(state->search_regex_multiline_item, "toggled", G_CALLBACK(find_regex_multiline_toggled), state);
    g_signal_connect(state->show_sidebar_item, "toggled", G_CALLBACK(show_sidebar_toggled), state);
    g_signal_connect(state->show_minimap_item, "toggled", G_CALLBACK(show_minimap_toggled), state);
    g_signal_connect(state->presentation_item, "toggled", G_CALLBACK(presentation_toggled), state);
    g_signal_connect_swapped(quit_menu, "activate", G_CALLBACK(g_application_quit), app);
    g_signal_connect(prev, "clicked", G_CALLBACK(previous_clicked), state);
    g_signal_connect(next, "clicked", G_CALLBACK(next_clicked), state);
    g_signal_connect(state->side_panel_button, "notify::active", G_CALLBACK(side_panel_switch_changed), state);
    g_signal_connect(state->minimap_button, "notify::active", G_CALLBACK(minimap_switch_changed), state);
    g_signal_connect(state->marker_strip_button, "notify::active", G_CALLBACK(marker_strip_switch_changed), state);
    g_signal_connect(state->overflow_side_panel_item, "toggled", G_CALLBACK(overflow_side_panel_toggled), state);
    g_signal_connect(state->overflow_minimap_item, "toggled", G_CALLBACK(overflow_minimap_toggled), state);
    g_signal_connect(state->overflow_marker_strip_item, "toggled", G_CALLBACK(overflow_marker_strip_toggled), state);
    g_signal_connect(state->overflow_continuous_item, "toggled", G_CALLBACK(overflow_continuous_toggled), state);
    g_signal_connect(state->overflow_search_regex_item, "toggled", G_CALLBACK(overflow_search_regex_toggled), state);
    g_signal_connect(state->overflow_search_regex_multiline_item, "toggled",
                     G_CALLBACK(overflow_search_regex_multiline_toggled), state);
    for (int i = 0; i < 5; ++i)
        g_signal_connect(state->overflow_fit_mode_items[i], "toggled", G_CALLBACK(overflow_fit_mode_toggled), state);
    g_signal_connect(state->overflow_translate_item, "activate", G_CALLBACK(overflow_button_activate),
                     state->translate_button);
    g_signal_connect(overflow_ocr, "activate", G_CALLBACK(overflow_button_activate), state->ocr_button);
    g_signal_connect(zoom_out, "clicked", G_CALLBACK(zoom_out_clicked), state);
    g_signal_connect(zoom_in, "clicked", G_CALLBACK(zoom_in_clicked), state);
    g_signal_connect(state->ocr_button, "clicked", G_CALLBACK(ocr_clicked), state);
    g_signal_connect(state->translate_button, "clicked", G_CALLBACK(translate_clicked), state);
    g_signal_connect(state->fit_mode, "changed", G_CALLBACK(fit_mode_changed), state);
    g_signal_connect(state->continuous, "toggled", G_CALLBACK(continuous_toggled), state);
    g_signal_connect(state->page_entry, "activate", G_CALLBACK(page_entry_activate), state);
    g_signal_connect(state->search_entry, "activate", G_CALLBACK(find_activate), state);
    g_signal_connect(state->search_entry, "search-changed", G_CALLBACK(find_search_changed), state);
    g_signal_connect(state->search_entry, "key-press-event", G_CALLBACK(find_search_key_press), state);
    g_signal_connect(state->search_regex_check, "toggled", G_CALLBACK(find_regex_toggled), state);
    g_signal_connect(state->search_regex_multiline_check, "toggled", G_CALLBACK(find_regex_multiline_toggled), state);
    g_signal_connect(state->find_prev_button, "clicked", G_CALLBACK(find_prev_clicked), state);
    g_signal_connect(state->find_next_button, "clicked", G_CALLBACK(find_next_clicked), state);
    g_signal_connect(state->find_markers, "draw", G_CALLBACK(find_markers_draw), state);
    g_signal_connect(state->minimap, "draw", G_CALLBACK(minimap_draw), state);
    g_signal_connect(state->minimap, "button-press-event", G_CALLBACK(minimap_button_press), state);
    g_signal_connect(state->minimap, "motion-notify-event", G_CALLBACK(minimap_motion), state);
    g_signal_connect(state->minimap, "button-release-event", G_CALLBACK(minimap_button_release), state);
    g_signal_connect(state->minimap, "scroll-event", G_CALLBACK(minimap_scroll_event), state);
    g_signal_connect(state->sidebar, "row-selected", G_CALLBACK(sidebar_row_selected), state);
    g_signal_connect(state->comments_sidebar, "row-selected", G_CALLBACK(sidebar_row_selected), state);
    g_signal_connect(state->comments_sidebar, "button-press-event", G_CALLBACK(comments_sidebar_button_press), state);
    g_signal_connect(state->sidebar_tabs, "switch-page", G_CALLBACK(sidebar_page_switched), state);
    g_signal_connect(state->main_paned, "notify::position", G_CALLBACK(paned_position_changed), state);
    g_signal_connect(page_box, "scroll-event", G_CALLBACK(page_scroll_event), state);
    g_signal_connect(page_box, "button-press-event", G_CALLBACK(page_button_press), state);
    g_signal_connect(page_box, "motion-notify-event", G_CALLBACK(page_motion), state);
    g_signal_connect(page_box, "leave-notify-event", G_CALLBACK(page_leave), state);
    g_signal_connect(page_box, "button-release-event", G_CALLBACK(page_button_release), state);
    g_signal_connect(state->scroll, "key-press-event", G_CALLBACK(key_press), state);
    g_signal_connect(state->scroll, "button-press-event", G_CALLBACK(presentation_button_press), state);
    g_signal_connect(toolbar, "size-allocate", G_CALLBACK(toolbar_size_allocate), state);
    g_signal_connect(state->window, "key-press-event", G_CALLBACK(key_press), state);
    g_signal_connect(state->window, "button-press-event", G_CALLBACK(presentation_button_press), state);
    g_signal_connect(state->window, "notify::scale-factor", G_CALLBACK(window_scale_factor_changed), state);
    g_signal_connect(state->window, "configure-event", G_CALLBACK(window_configure_event), state);
    g_signal_connect(state->window, "window-state-event", G_CALLBACK(window_state_event), state);

    GtkTargetEntry drop_targets[] = {{"text/uri-list", 0, 0}};
    gtk_drag_dest_set(state->window, GTK_DEST_DEFAULT_ALL, drop_targets, 1, GDK_ACTION_COPY);
    g_signal_connect(state->window, "drag-data-received", G_CALLBACK(drag_data_received), state);

    gtk_widget_show_all(state->window);
    gtk_widget_hide(state->sidebar_container);
    update_controls(state);
    if (state->suppress_restore_once) {
        update_tab_strip(state);
        state->suppress_restore_once = FALSE;
    } else {
        state->startup_restore_idle_id = g_idle_add_full(G_PRIORITY_LOW, startup_restore_idle, state, NULL);
    }
}

static void open_files(GtkApplication* app, GFile** files, gint n_files, const gchar* hint, gpointer user_data) {
    (void)hint;
    app_state* state = (app_state*)user_data;
    if (!state->window) {
        state->suppress_restore_once = TRUE;
        free_document_tabs(state);
        g_free(state->restore_path);
        g_free(state->restore_search_text);
        state->restore_path = NULL;
        state->restore_search_text = NULL;
        activate(app, user_data);
    }
    for (int i = 0; i < n_files; ++i) {
        char* path = g_file_get_path(files[i]);
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
    state.show_sidebar = TRUE;
    state.show_minimap = TRUE;
    state.show_find_markers = TRUE;
    state.search_regex_multiline = TRUE;
    state.translate_source_language = g_strdup("zh");
    state.translate_target_language = g_strdup("en");
    state.sidebar_width = 260;
    state.window_width = DEFAULT_WINDOW_WIDTH;
    state.window_height = DEFAULT_WINDOW_HEIGHT;
    state.find_match_index = -1;
    state.restore_find_match_index = -1;
    state.selection_page_index = -1;
    state.context_page_index = -1;
    state.context_comment_index = -1;
    state.tab_drag_index = -1;
    state.selected_tab = -1;
    state.restore_selected_tab = -1;
    state.favorite_pending_delete = -1;
    state.render_pool = g_thread_pool_new(render_worker, NULL, MAX(1, MIN(2, g_get_num_processors())), FALSE, NULL);
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
    if (state.find_debounce_id) g_source_remove(state.find_debounce_id);
    if (state.sidebar_metadata_idle_id) g_source_remove(state.sidebar_metadata_idle_id);
    if (state.background_render_idle_id) g_source_remove(state.background_render_idle_id);
    if (state.startup_restore_idle_id) g_source_remove(state.startup_restore_idle_id);
    if (state.deferred_find_idle_id) g_source_remove(state.deferred_find_idle_id);
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
    g_free(state.restore_search_text);
    g_free(state.search_text);
    g_free(state.comment_author);
    g_free(state.translate_source_language);
    g_free(state.translate_target_language);
    g_free(state.selected_text);
    g_free(state.empty_view_message);
    clear_find_results(&state);
    free_favorites(&state);
    free_path_list(state.recent_paths, &state.recent_count);
    free_path_list(state.closed_paths, &state.closed_count);
    free_document_tabs(&state);
    g_object_unref(app);
    return status;
}
