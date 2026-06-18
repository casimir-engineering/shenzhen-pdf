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
    /* Destination point of the heading on its page, taken from the PDF outline
     * link (fz_outline.x/y). PDF destination coordinates are in PDF user space
     * (origin bottom-left, y increases UPWARD). has_dest is 0 when the outline
     * entry carries no usable point (e.g. /Fit-style dests, or non-finite
     * coordinates); callers must fall back to page-only attribution then.
     * Appended at the end of the struct so the Linux build, which ignores these
     * fields, is unaffected. */
    float dest_x;
    float dest_y;
    int has_dest;
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

/* Cooperative render cancellation. A token wraps a mupdf fz_cookie; canceling
 * sets the cookie's abort flag, which mupdf polls between content-stream tokens
 * and display-list nodes, stopping the render within milliseconds. A canceled
 * render returns 0 with err "Render canceled." -- callers must treat that as a
 * non-error cancellation, not a render failure. spdf_render_token_cancel() is
 * safe to call from any thread while a render using the token is running;
 * free() only after no render is using the token. Passing NULL keeps the
 * legacy non-cancelable behavior. */
typedef struct spdf_render_token spdf_render_token;

spdf_render_token* spdf_render_token_new(void);
void spdf_render_token_cancel(spdf_render_token* token); /* thread-safe: sets cookie.abort = 1 */
void spdf_render_token_free(spdf_render_token* token);

enum {
    SPDF_RENDER_DEFAULT = 0,
    SPDF_RENDER_USE_PAGE_LIST = 1 << 0 /* render by replaying a cached per-page display list */
};

/* How the LAST render on this document got its pixels (profiling aid). */
typedef struct spdf_render_stats {
    int used_list;   /* 1 if the render replayed a display list */
    int built_list;  /* 1 if that render had to build the list first */
    double build_ms; /* display-list build time for that render, 0 when not built */
} spdf_render_stats;

spdf_document* spdf_open(const char* path, char* err, size_t err_len);
void spdf_close(spdf_document* doc);

int spdf_page_count(spdf_document* doc);
const char* spdf_title(spdf_document* doc);
int spdf_set_page_size_cache(spdf_document* doc, int page_index, float width, float height);
int spdf_page_size(spdf_document* doc, int page_index, float* width, float* height, char* err, size_t err_len);

int spdf_render_page_rgba(spdf_document* doc, int page_index, float zoom, spdf_bitmap* out, char* err, size_t err_len);
int spdf_render_page_region_rgba(spdf_document* doc, int page_index, float zoom, spdf_rect region, spdf_bitmap* out,
                                 char* err, size_t err_len);
int spdf_render_page_rgba_opts(spdf_document* doc, int page_index, float zoom, unsigned flags,
                               spdf_render_token* token, spdf_bitmap* out, char* err, size_t err_len);
int spdf_render_page_region_rgba_opts(spdf_document* doc, int page_index, float zoom, spdf_rect region, unsigned flags,
                                      spdf_render_token* token, spdf_bitmap* out, char* err, size_t err_len);
void spdf_drop_page_list_cache(spdf_document* doc, int page_index); /* -1 = drop all cached page lists */
spdf_render_stats spdf_last_render_stats(const spdf_document* doc);
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
/* detect_text_links: when non-zero, also scan the page's structured text for
 * plain-text URLs (builds the full stext page — expensive on dense pages, so
 * pass 0 for hover/cursor hit-testing and 1 only when actually following a
 * link on click). */
int spdf_link_at_point(spdf_document* doc, int page_index, float x, float y, spdf_link_target* out,
                       int detect_text_links, char* err, size_t err_len);
void spdf_free_link_target(spdf_link_target* target);
int spdf_add_highlight_comment(spdf_document* doc, int page_index, const spdf_rect* rects, int rect_count,
                               const char* text, const char* author, char* err, size_t err_len);
int spdf_add_text_comment(spdf_document* doc, int page_index, float x, float y, const char* text, const char* author,
                          char* err, size_t err_len);
int spdf_update_comment(spdf_document* doc, int comment_index, const char* text, const char* author, char* err,
                        size_t err_len);
int spdf_delete_comment(spdf_document* doc, int comment_index, char* err, size_t err_len);
int spdf_rotate_page(spdf_document* doc, int page_index, int degrees, char* err, size_t err_len);
/* Remove every text-showing operation from every page (keeping images and
 * graphics) and rewrite the file at path (garbage-collected, so the old text
 * streams are dropped, not just orphaned) so the document can be re-OCR'd.
 * Returns 1 on success, 0 on failure (err is filled). */
int spdf_delete_all_text(spdf_document* doc, const char* path, char* err, size_t err_len);
int spdf_save_document(spdf_document* doc, const char* path, char* err, size_t err_len);
int spdf_document_has_text(spdf_document* doc, int max_pages, char* err, size_t err_len);
int spdf_save_translated_copy(spdf_document* doc, const char* path, const spdf_translated_line* lines, int line_count,
                              char* err, size_t err_len);
/* Write a standalone single-page PDF (the given page grafted into a fresh
 * document) to path. Backs the "Copy Page" clipboard action on both platforms.
 * Returns 1 on success, 0 on failure (err is filled). */
int spdf_save_single_page_pdf(spdf_document* doc, int page_index, const char* path, char* err, size_t err_len);

#ifdef __cplusplus
}
#endif

#endif
