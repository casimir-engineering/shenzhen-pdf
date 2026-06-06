#ifndef SHENZHEN_PDF_CORE_H
#define SHENZHEN_PDF_CORE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct spdf_document spdf_document;

typedef struct spdf_bitmap {
    int width;
    int height;
    int stride;
    unsigned char* rgba;
} spdf_bitmap;

typedef struct spdf_outline_item {
    char* title;
    int page_index;
    int level;
} spdf_outline_item;

typedef struct spdf_outline {
    spdf_outline_item* items;
    int count;
} spdf_outline;

typedef struct spdf_rect {
    float x0;
    float y0;
    float x1;
    float y1;
} spdf_rect;

typedef struct spdf_comment_item {
    char* author;
    char* text;
    char* type;
    int index;
    int page_index;
    spdf_rect bounds;
} spdf_comment_item;

typedef struct spdf_comments {
    spdf_comment_item* items;
    int count;
} spdf_comments;

typedef struct spdf_text_line {
    char* text;
    spdf_rect bounds;
    float font_size;
} spdf_text_line;

typedef struct spdf_text_lines {
    spdf_text_line* items;
    int count;
    int image_backed;
} spdf_text_lines;

typedef enum spdf_translation_background {
    SPDF_TRANSLATION_BACKGROUND_NONE = -1,
    SPDF_TRANSLATION_BACKGROUND_AUTO = 0,
    SPDF_TRANSLATION_BACKGROUND_OPAQUE = 1
} spdf_translation_background;

typedef struct spdf_translated_line {
    int page_index;
    spdf_rect bounds;
    const char* text;
    float font_size;
    int opaque_background;
} spdf_translated_line;

typedef enum spdf_link_kind {
    SPDF_LINK_NONE = 0,
    SPDF_LINK_URI = 1,
    SPDF_LINK_INTERNAL = 2
} spdf_link_kind;

typedef struct spdf_link_target {
    spdf_link_kind kind;
    char* uri;
    int page_index;
    float x;
    float y;
    float zoom;
} spdf_link_target;

spdf_document* spdf_open(const char* path, char* err, size_t err_len);
void spdf_close(spdf_document* doc);

int spdf_page_count(spdf_document* doc);
const char* spdf_title(spdf_document* doc);
int spdf_set_page_size_cache(spdf_document* doc, int page_index, float width, float height);
int spdf_page_size(spdf_document* doc, int page_index, float* width, float* height, char* err, size_t err_len);

int spdf_render_page_rgba(spdf_document* doc, int page_index, float zoom, spdf_bitmap* out, char* err, size_t err_len);
int spdf_render_page_region_rgba(spdf_document* doc, int page_index, float zoom, spdf_rect region, spdf_bitmap* out,
                                 char* err, size_t err_len);
void spdf_free_bitmap(spdf_bitmap* bitmap);

int spdf_search_page(spdf_document* doc, int page_index, const char* needle, char* err, size_t err_len);
int spdf_search_page_rects(spdf_document* doc, int page_index, const char* needle, spdf_rect* rects, int rect_max,
                           char* err, size_t err_len);
int spdf_search_page_options(spdf_document* doc, int page_index, const char* needle, int regex, int regex_multiline,
                             char* err, size_t err_len);
int spdf_search_page_rects_options(spdf_document* doc, int page_index, const char* needle, int regex,
                                   int regex_multiline, spdf_rect* rects, int rect_max, char* err, size_t err_len);
int spdf_select_page_text(spdf_document* doc, int page_index, float ax, float ay, float bx, float by, spdf_rect* rects,
                          int rect_max, char** text_out, char* err, size_t err_len);
void spdf_free_string(char* text);
int spdf_extract_page_text_lines(spdf_document* doc, int page_index, spdf_text_lines* out, char* err, size_t err_len);
void spdf_free_text_lines(spdf_text_lines* lines);

int spdf_load_outline(spdf_document* doc, spdf_outline* out, char* err, size_t err_len);
void spdf_free_outline(spdf_outline* outline);
int spdf_load_comments(spdf_document* doc, spdf_comments* out, char* err, size_t err_len);
void spdf_free_comments(spdf_comments* comments);
int spdf_link_at_point(spdf_document* doc, int page_index, float x, float y, spdf_link_target* out, char* err,
                       size_t err_len);
void spdf_free_link_target(spdf_link_target* target);
int spdf_add_highlight_comment(spdf_document* doc, int page_index, const spdf_rect* rects, int rect_count,
                               const char* text, const char* author, char* err, size_t err_len);
int spdf_add_text_comment(spdf_document* doc, int page_index, float x, float y, const char* text, const char* author,
                          char* err, size_t err_len);
int spdf_update_comment(spdf_document* doc, int comment_index, const char* text, const char* author, char* err,
                        size_t err_len);
int spdf_delete_comment(spdf_document* doc, int comment_index, char* err, size_t err_len);
int spdf_rotate_page(spdf_document* doc, int page_index, int degrees, char* err, size_t err_len);
int spdf_save_document(spdf_document* doc, const char* path, char* err, size_t err_len);
int spdf_document_has_text(spdf_document* doc, int max_pages, char* err, size_t err_len);
int spdf_save_translated_copy(spdf_document* doc, const char* path, const spdf_translated_line* lines, int line_count,
                              char* err, size_t err_len);

#ifdef __cplusplus
}
#endif

#endif
