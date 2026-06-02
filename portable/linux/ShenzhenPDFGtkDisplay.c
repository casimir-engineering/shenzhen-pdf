#include "ShenzhenPDFGtkDisplay.h"

#include <string.h>

typedef struct display_path_parts {
    char** items;
    int count;
} display_path_parts;

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

char* spdf_gtk_display_name_for_path(const char* path) {
    char* name = g_path_get_basename(path ? path : "");
    strip_known_document_extension(name);
    return name;
}

char* spdf_gtk_display_label_without_extension(const char* label) {
    char* text = g_strdup(label ? label : "");
    strip_known_document_extension(text);
    return text;
}

char* spdf_gtk_display_path_without_extension(const char* path) {
    char* text = g_strdup(path ? path : "");
    char* slash = strrchr(text, G_DIR_SEPARATOR);
    char* base = slash ? slash + 1 : text;
    char* dot = strrchr(base, '.');
    if (dot && dot > base) *dot = '\0';
    return text;
}

static void free_display_path_parts(display_path_parts* parts) {
    if (!parts) return;
    for (int i = 0; i < parts->count; ++i) g_free(parts->items[i]);
    g_free(parts->items);
    parts->items = NULL;
    parts->count = 0;
}

static display_path_parts display_parts_for_path(const char* path) {
    display_path_parts parts = {0};
    char* canonical = g_canonicalize_filename(path ? path : "", NULL);
    char** split = g_strsplit(canonical ? canonical : "", G_DIR_SEPARATOR_S, -1);
    for (int i = 0; split && split[i]; ++i) {
        if (!*split[i]) continue;
        parts.items = g_realloc(parts.items, (gsize)(parts.count + 1) * sizeof(char*));
        parts.items[parts.count++] = g_strdup(split[i]);
    }
    if (parts.count > 0) strip_known_document_extension(parts.items[parts.count - 1]);
    g_strfreev(split);
    g_free(canonical);
    return parts;
}

static char* display_candidate_from_parts(const display_path_parts* parts, int tail_length, int leading_count) {
    if (!parts || parts->count <= 0) return g_strdup("");
    tail_length = CLAMP(tail_length, 1, parts->count);
    int start = parts->count - tail_length;
    if (tail_length == 1) return g_strdup(parts->items[parts->count - 1]);
    if (tail_length == 2) return g_strjoin("/", parts->items[parts->count - 2], parts->items[parts->count - 1], NULL);

    int visible = CLAMP(leading_count, 1, tail_length - 2);
    GString* text = g_string_new(NULL);
    for (int i = 0; i < visible; ++i) {
        if (i > 0) g_string_append_c(text, '/');
        g_string_append(text, parts->items[start + i]);
    }
    g_string_append(text, "/.../");
    g_string_append(text, parts->items[parts->count - 1]);
    return g_string_free(text, FALSE);
}

static char* tab_base_title(const spdf_gtk_tab_title* tab) {
    if (!tab) return g_strdup("");
    if (tab->path && *tab->path) return spdf_gtk_display_name_for_path(tab->path);
    return spdf_gtk_display_label_without_extension(tab->title ? tab->title : "");
}

char* spdf_gtk_disambiguated_tab_title(const spdf_gtk_tab_title* tabs, int count, int index) {
    if (!tabs || index < 0 || index >= count) return g_strdup("");

    char* base = tab_base_title(&tabs[index]);
    gboolean has_duplicate = FALSE;
    int max_tail = 1;
    for (int i = 0; i < count; ++i) {
        if (i == index) continue;
        char* other_base = tab_base_title(&tabs[i]);
        if (g_ascii_strcasecmp(base, other_base) == 0) has_duplicate = TRUE;
        g_free(other_base);
    }
    if (!has_duplicate) return base;

    display_path_parts target = display_parts_for_path(tabs[index].path);
    for (int i = 0; i < count; ++i) {
        char* other_base = tab_base_title(&tabs[i]);
        if (g_ascii_strcasecmp(base, other_base) == 0) {
            display_path_parts parts = display_parts_for_path(tabs[i].path);
            max_tail = MAX(max_tail, parts.count);
            free_display_path_parts(&parts);
        }
        g_free(other_base);
    }

    for (int tail = 2; tail <= max_tail; ++tail) {
        int max_leading = tail <= 2 ? 1 : tail - 2;
        for (int leading = 1; leading <= max_leading; ++leading) {
            char* candidate = display_candidate_from_parts(&target, tail, leading);
            gboolean unique = TRUE;
            for (int i = 0; i < count; ++i) {
                if (i == index) continue;
                char* other_base = tab_base_title(&tabs[i]);
                if (g_ascii_strcasecmp(base, other_base) == 0) {
                    display_path_parts parts = display_parts_for_path(tabs[i].path);
                    char* other_candidate = display_candidate_from_parts(&parts, tail, leading);
                    if (g_ascii_strcasecmp(candidate, other_candidate) == 0) unique = FALSE;
                    g_free(other_candidate);
                    free_display_path_parts(&parts);
                }
                g_free(other_base);
                if (!unique) break;
            }
            if (unique) {
                g_free(base);
                free_display_path_parts(&target);
                return candidate;
            }
            g_free(candidate);
        }
    }

    g_free(base);
    free_display_path_parts(&target);
    return spdf_gtk_display_path_without_extension(tabs[index].path);
}
