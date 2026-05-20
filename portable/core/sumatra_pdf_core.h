#ifndef SUMATRA_PDF_CORE_H
#define SUMATRA_PDF_CORE_H

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
    int page_index;
    spdf_rect bounds;
} spdf_comment_item;

typedef struct spdf_comments {
    spdf_comment_item* items;
    int count;
} spdf_comments;

spdf_document* spdf_open(const char* path, char* err, size_t err_len);
void spdf_close(spdf_document* doc);

int spdf_page_count(spdf_document* doc);
const char* spdf_title(spdf_document* doc);
int spdf_page_size(spdf_document* doc, int page_index, float* width, float* height, char* err, size_t err_len);

int spdf_render_page_rgba(spdf_document* doc, int page_index, float zoom, spdf_bitmap* out, char* err, size_t err_len);
void spdf_free_bitmap(spdf_bitmap* bitmap);

int spdf_search_page(spdf_document* doc, int page_index, const char* needle, char* err, size_t err_len);
int spdf_search_page_rects(spdf_document* doc, int page_index, const char* needle, spdf_rect* rects, int rect_max,
                           char* err, size_t err_len);
int spdf_select_page_text(spdf_document* doc, int page_index, float ax, float ay, float bx, float by, spdf_rect* rects,
                          int rect_max, char** text_out, char* err, size_t err_len);
void spdf_free_string(char* text);

int spdf_load_outline(spdf_document* doc, spdf_outline* out, char* err, size_t err_len);
void spdf_free_outline(spdf_outline* outline);
int spdf_load_comments(spdf_document* doc, spdf_comments* out, char* err, size_t err_len);
void spdf_free_comments(spdf_comments* comments);
int spdf_document_has_text(spdf_document* doc, int max_pages, char* err, size_t err_len);

#ifdef __cplusplus
}
#endif

#endif
