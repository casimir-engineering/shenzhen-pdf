#include "sumatra_pdf_core.h"

#include "mupdf/fitz.h"
#include "mupdf/pdf.h"

#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define SPDF_MUPDF_STORE_LIMIT ((size_t)256 * 1024 * 1024)
#define SPDF_MAX_RENDER_DIMENSION 32768
#define SPDF_MAX_RENDER_BYTES ((size_t)512 * 1024 * 1024)

typedef struct spdf_page_size_cache {
    float width;
    float height;
    int valid;
} spdf_page_size_cache;

struct spdf_document {
    fz_context* ctx;
    fz_document* doc;
    char* title;
    int page_count;
    spdf_page_size_cache* page_sizes;
};

typedef struct outline_builder {
    spdf_outline_item* items;
    int count;
    int capacity;
} outline_builder;

typedef struct comment_builder {
    spdf_comment_item* items;
    int count;
    int capacity;
} comment_builder;

static void set_error(char* err, size_t err_len, const char* message) {
    if (!err || err_len == 0) return;
    if (!message) message = "Unknown error";
    snprintf(err, err_len, "%s", message);
}

static char* copy_string(const char* value) {
    size_t len;
    char* copy;

    if (!value) value = "";
    len = strlen(value);
    copy = (char*)malloc(len + 1);
    if (!copy) return NULL;
    memcpy(copy, value, len + 1);
    return copy;
}

static const char* path_basename(const char* path) {
    const char* last_slash;

    if (!path || !*path) return "Untitled";
    last_slash = strrchr(path, '/');
    return last_slash ? last_slash + 1 : path;
}

spdf_document* spdf_open(const char* path, char* err, size_t err_len) {
    spdf_document* opened = NULL;
    fz_context* ctx = NULL;
    fz_document* doc = NULL;
    char title[512];

    set_error(err, err_len, "");
    if (!path || !*path) {
        set_error(err, err_len, "No document path was supplied.");
        return NULL;
    }

    ctx = fz_new_context(NULL, NULL, SPDF_MUPDF_STORE_LIMIT);
    if (!ctx) {
        set_error(err, err_len, "Could not create MuPDF context.");
        return NULL;
    }

    fz_try(ctx) {
        fz_register_document_handlers(ctx);
        doc = fz_open_document(ctx, path);

        opened = (spdf_document*)calloc(1, sizeof(spdf_document));
        if (!opened) fz_throw(ctx, FZ_ERROR_SYSTEM, "Out of memory");

        opened->ctx = ctx;
        opened->doc = doc;
        opened->page_count = fz_count_pages(ctx, doc);
        if (opened->page_count > 0) {
            opened->page_sizes =
                (spdf_page_size_cache*)calloc((size_t)opened->page_count, sizeof(spdf_page_size_cache));
            if (!opened->page_sizes) fz_throw(ctx, FZ_ERROR_SYSTEM, "Out of memory");
        }

        title[0] = '\0';
        if (fz_lookup_metadata(ctx, doc, FZ_META_INFO_TITLE, title, sizeof(title)) <= 0 || !title[0])
            snprintf(title, sizeof(title), "%s", path_basename(path));
        opened->title = copy_string(title);
        if (!opened->title) fz_throw(ctx, FZ_ERROR_SYSTEM, "Out of memory");
    }
    fz_catch(ctx) {
        set_error(err, err_len, fz_caught_message(ctx));
        if (opened) {
            free(opened->title);
            free(opened->page_sizes);
            free(opened);
        }
        if (doc) fz_drop_document(ctx, doc);
        fz_drop_context(ctx);
        return NULL;
    }

    return opened;
}

void spdf_close(spdf_document* doc) {
    if (!doc) return;
    if (doc->doc) fz_drop_document(doc->ctx, doc->doc);
    if (doc->ctx) fz_drop_context(doc->ctx);
    free(doc->title);
    free(doc->page_sizes);
    free(doc);
}

int spdf_page_count(spdf_document* doc) {
    return doc ? doc->page_count : 0;
}

const char* spdf_title(spdf_document* doc) {
    return doc && doc->title ? doc->title : "";
}

int spdf_page_size(spdf_document* doc, int page_index, float* width, float* height, char* err, size_t err_len) {
    fz_page* page = NULL;
    spdf_page_size_cache* cached;
    fz_rect bounds;

    set_error(err, err_len, "");
    if (!doc || page_index < 0 || page_index >= doc->page_count) {
        set_error(err, err_len, "Page index is out of range.");
        return 0;
    }
    cached = doc->page_sizes ? &doc->page_sizes[page_index] : NULL;
    if (cached && cached->valid) {
        if (width) *width = cached->width;
        if (height) *height = cached->height;
        return 1;
    }

    fz_try(doc->ctx) {
        page = fz_load_page(doc->ctx, doc->doc, page_index);
        bounds = fz_bound_page(doc->ctx, page);
        if (cached) {
            cached->width = bounds.x1 - bounds.x0;
            cached->height = bounds.y1 - bounds.y0;
            cached->valid = 1;
        }
        if (width) *width = bounds.x1 - bounds.x0;
        if (height) *height = bounds.y1 - bounds.y0;
        fz_drop_page(doc->ctx, page);
        page = NULL;
    }
    fz_catch(doc->ctx) {
        set_error(err, err_len, fz_caught_message(doc->ctx));
        if (page) fz_drop_page(doc->ctx, page);
        return 0;
    }

    return 1;
}

static int render_page_size_allowed(float page_width, float page_height, float zoom, char* err, size_t err_len) {
    double scaled_width;
    double scaled_height;

    if (!isfinite(page_width) || !isfinite(page_height) || page_width < 0.0f || page_height < 0.0f) {
        set_error(err, err_len, "Page has invalid dimensions.");
        return 0;
    }

    scaled_width = ceil((double)page_width * (double)zoom) + 2.0;
    scaled_height = ceil((double)page_height * (double)zoom) + 2.0;
    if (!isfinite(scaled_width) || !isfinite(scaled_height) || scaled_width > SPDF_MAX_RENDER_DIMENSION ||
        scaled_height > SPDF_MAX_RENDER_DIMENSION ||
        scaled_width * scaled_height * 4.0 > (double)SPDF_MAX_RENDER_BYTES) {
        set_error(err, err_len, "Rendered page would be too large.");
        return 0;
    }

    return 1;
}

static int render_pixmap_allocation_size(int width, int height, int comps, int src_stride, int* stride_out,
                                         size_t* byte_count_out, char* err, size_t err_len) {
    int stride;
    size_t byte_count;

    if (width <= 0 || height <= 0 || width > SPDF_MAX_RENDER_DIMENSION || height > SPDF_MAX_RENDER_DIMENSION) {
        set_error(err, err_len, "Rendered page has invalid dimensions.");
        return 0;
    }
    if (comps <= 0 || comps > 16 || src_stride <= 0 || (size_t)src_stride < (size_t)width * (size_t)comps) {
        set_error(err, err_len, "Rendered page has an invalid pixel layout.");
        return 0;
    }
    if (width > INT_MAX / 4) {
        set_error(err, err_len, "Rendered page is too wide.");
        return 0;
    }

    stride = width * 4;
    if ((size_t)height > ((size_t)-1) / (size_t)stride) {
        set_error(err, err_len, "Rendered page is too large.");
        return 0;
    }
    byte_count = (size_t)stride * (size_t)height;
    if (byte_count > SPDF_MAX_RENDER_BYTES) {
        set_error(err, err_len, "Rendered page is too large.");
        return 0;
    }

    *stride_out = stride;
    *byte_count_out = byte_count;
    return 1;
}

int spdf_render_page_rgba(spdf_document* doc, int page_index, float zoom, spdf_bitmap* out, char* err, size_t err_len) {
    fz_pixmap* pix = NULL;
    unsigned char* dst = NULL;
    unsigned char* src;
    size_t byte_count;
    float page_width;
    float page_height;
    int width;
    int height;
    int stride;
    int comps;
    int alpha;
    int src_stride;
    int y;
    int x;

    set_error(err, err_len, "");
    if (!out) {
        set_error(err, err_len, "No render output was supplied.");
        return 0;
    }
    memset(out, 0, sizeof(*out));

    if (!doc || page_index < 0 || page_index >= doc->page_count) {
        set_error(err, err_len, "Page index is out of range.");
        return 0;
    }
    if (!isfinite(zoom)) {
        set_error(err, err_len, "Zoom level is invalid.");
        return 0;
    }
    if (zoom <= 0.01f) zoom = 0.01f;
    if (!spdf_page_size(doc, page_index, &page_width, &page_height, err, err_len)) return 0;
    if (!render_page_size_allowed(page_width, page_height, zoom, err, err_len)) return 0;

    fz_try(doc->ctx) {
        pix = fz_new_pixmap_from_page_number(doc->ctx, doc->doc, page_index, fz_scale(zoom, zoom),
                                             fz_device_rgb(doc->ctx), 0);
        width = fz_pixmap_width(doc->ctx, pix);
        height = fz_pixmap_height(doc->ctx, pix);
        comps = fz_pixmap_components(doc->ctx, pix);
        alpha = fz_pixmap_alpha(doc->ctx, pix);
        src_stride = fz_pixmap_stride(doc->ctx, pix);
        src = fz_pixmap_samples(doc->ctx, pix);
        if (!src ||
            !render_pixmap_allocation_size(width, height, comps, src_stride, &stride, &byte_count, err, err_len))
            fz_throw(doc->ctx, FZ_ERROR_FORMAT, "%s", err && *err ? err : "Rendered page is too large.");

        dst = (unsigned char*)malloc(byte_count);
        if (!dst) fz_throw(doc->ctx, FZ_ERROR_SYSTEM, "Out of memory");

        for (y = 0; y < height; ++y) {
            const unsigned char* row = src + (size_t)y * (size_t)src_stride;
            unsigned char* out_row = dst + (size_t)y * (size_t)stride;
            for (x = 0; x < width; ++x) {
                const unsigned char* px = row + (size_t)x * (size_t)comps;
                unsigned char* opx = out_row + (size_t)x * 4;
                opx[0] = comps > 0 ? px[0] : 255;
                opx[1] = comps > 1 ? px[1] : opx[0];
                opx[2] = comps > 2 ? px[2] : opx[0];
                opx[3] = alpha ? px[comps - 1] : 255;
            }
        }

        fz_drop_pixmap(doc->ctx, pix);
        pix = NULL;

        out->width = width;
        out->height = height;
        out->stride = stride;
        out->rgba = dst;
    }
    fz_catch(doc->ctx) {
        set_error(err, err_len, fz_caught_message(doc->ctx));
        free(dst);
        if (pix) fz_drop_pixmap(doc->ctx, pix);
        return 0;
    }

    return 1;
}

void spdf_free_bitmap(spdf_bitmap* bitmap) {
    if (!bitmap) return;
    free(bitmap->rgba);
    memset(bitmap, 0, sizeof(*bitmap));
}

int spdf_search_page(spdf_document* doc, int page_index, const char* needle, char* err, size_t err_len) {
    fz_quad hits[128];
    int hit_marks[128];
    int count = 0;

    set_error(err, err_len, "");
    if (!needle || !*needle) return 0;
    if (!doc || page_index < 0 || page_index >= doc->page_count) {
        set_error(err, err_len, "Page index is out of range.");
        return -1;
    }

    fz_try(doc->ctx) {
        count = fz_search_page_number(doc->ctx, doc->doc, page_index, needle, hit_marks, hits, 128);
    }
    fz_catch(doc->ctx) {
        set_error(err, err_len, fz_caught_message(doc->ctx));
        return -1;
    }

    return count;
}

int spdf_search_page_rects(spdf_document* doc, int page_index, const char* needle, spdf_rect* rects, int rect_max,
                           char* err, size_t err_len) {
    fz_quad hits[256];
    int hit_marks[256];
    int max_hits;
    int count = 0;
    int i;

    set_error(err, err_len, "");
    if (!needle || !*needle) return 0;
    if (!doc || page_index < 0 || page_index >= doc->page_count) {
        set_error(err, err_len, "Page index is out of range.");
        return -1;
    }
    if (!rects || rect_max <= 0) return spdf_search_page(doc, page_index, needle, err, err_len);

    max_hits = rect_max < 256 ? rect_max : 256;
    fz_try(doc->ctx) {
        count = fz_search_page_number(doc->ctx, doc->doc, page_index, needle, hit_marks, hits, max_hits);
        if (count > max_hits) count = max_hits;
        for (i = 0; i < count; ++i) {
            fz_rect r = fz_rect_from_quad(hits[i]);
            rects[i].x0 = r.x0;
            rects[i].y0 = r.y0;
            rects[i].x1 = r.x1;
            rects[i].y1 = r.y1;
        }
    }
    fz_catch(doc->ctx) {
        set_error(err, err_len, fz_caught_message(doc->ctx));
        return -1;
    }

    return count;
}

static int append_regex_text(char** buffer, size_t* length, size_t* capacity, const char* text, size_t text_len) {
    char* grown;
    size_t needed;
    size_t new_capacity;

    if (text_len == 0) return 1;
    needed = *length + text_len + 1;
    if (needed > *capacity) {
        new_capacity = *capacity ? *capacity : 64;
        while (new_capacity < needed) new_capacity *= 2;
        grown = (char*)realloc(*buffer, new_capacity);
        if (!grown) return 0;
        *buffer = grown;
        *capacity = new_capacity;
    }
    memcpy(*buffer + *length, text, text_len);
    *length += text_len;
    (*buffer)[*length] = '\0';
    return 1;
}

static int append_regex_cstr(char** buffer, size_t* length, size_t* capacity, const char* text) {
    return append_regex_text(buffer, length, capacity, text, strlen(text));
}

static int regex_rest_is_empty(const char* text) {
    return !text || !*text;
}

static char* copy_multiline_regex_pattern(const char* pattern) {
    char* out = NULL;
    size_t out_len = 0;
    size_t out_cap = 0;
    int escaped = 0;
    int in_class = 0;
    size_t i;

    if (!append_regex_text(&out, &out_len, &out_cap, "", 0)) return NULL;
    for (i = 0; pattern[i]; ++i) {
        char c = pattern[i];
        if (escaped) {
            if (!append_regex_text(&out, &out_len, &out_cap, &c, 1)) goto fail;
            escaped = 0;
            continue;
        }
        if (c == '\\') {
            if (!append_regex_text(&out, &out_len, &out_cap, &c, 1)) goto fail;
            escaped = 1;
            continue;
        }
        if (in_class) {
            if (!append_regex_text(&out, &out_len, &out_cap, &c, 1)) goto fail;
            if (c == ']') in_class = 0;
            continue;
        }
        if (c == '[') {
            in_class = 1;
            if (!append_regex_text(&out, &out_len, &out_cap, &c, 1)) goto fail;
            continue;
        }
        if (c == '.') {
            char quantifier = pattern[i + 1];
            if (quantifier == '*' || quantifier == '+') {
                int lazy = pattern[i + 2] == '?';
                const char* rest = pattern + i + (lazy ? 3 : 2);
                if (regex_rest_is_empty(rest)) {
                    const char* capped = quantifier == '*' ? "[^]{0,254}" : "[^]{1,254}";
                    if (!append_regex_cstr(&out, &out_len, &out_cap, capped)) goto fail;
                    i += lazy ? 2 : 1;
                    continue;
                }
                if (!append_regex_cstr(&out, &out_len, &out_cap, "[^]")) goto fail;
                if (!append_regex_text(&out, &out_len, &out_cap, &quantifier, 1)) goto fail;
                if (!lazy && !append_regex_cstr(&out, &out_len, &out_cap, "?")) goto fail;
                if (lazy && !append_regex_cstr(&out, &out_len, &out_cap, "?")) goto fail;
                i += lazy ? 2 : 1;
                continue;
            }
            if (!append_regex_cstr(&out, &out_len, &out_cap, "[^]")) goto fail;
            continue;
        }
        if (!append_regex_text(&out, &out_len, &out_cap, &c, 1)) goto fail;
    }
    return out;

fail:
    free(out);
    return NULL;
}

static fz_search_options spdf_search_options(int regex) {
    fz_search_options options = FZ_SEARCH_IGNORE_CASE;

    if (regex) options |= FZ_SEARCH_REGEXP;
    if (regex) options |= FZ_SEARCH_KEEP_LINES | FZ_SEARCH_KEEP_PARAGRAPHS;
    return options;
}

int spdf_search_page_options(spdf_document* doc, int page_index, const char* needle, int regex, int regex_multiline,
                             char* err, size_t err_len) {
    int count = 0;
    char* multiline_needle = NULL;
    const char* search_needle = needle;

    if (!regex) return spdf_search_page(doc, page_index, needle, err, err_len);

    set_error(err, err_len, "");
    if (!needle || !*needle) return 0;
    if (!doc || page_index < 0 || page_index >= doc->page_count) {
        set_error(err, err_len, "Page index is out of range.");
        return -1;
    }
    if (regex_multiline) {
        multiline_needle = copy_multiline_regex_pattern(needle);
        if (!multiline_needle) {
            set_error(err, err_len, "Out of memory");
            return -1;
        }
        search_needle = multiline_needle;
    }

    fz_try(doc->ctx) {
        count = fz_match_page_number_cb(doc->ctx, doc->doc, page_index, search_needle, NULL, NULL,
                                        spdf_search_options(regex));
    }
    fz_catch(doc->ctx) {
        set_error(err, err_len, fz_caught_message(doc->ctx));
        free(multiline_needle);
        return -1;
    }

    free(multiline_needle);
    return count;
}

typedef struct search_rect_builder {
    spdf_rect* rects;
    int rect_max;
    int count;
} search_rect_builder;

static int append_match_rects(fz_context* ctx, void* opaque, int num_quads, fz_quad* quads, int chapter, int page) {
    search_rect_builder* builder = (search_rect_builder*)opaque;
    int i;

    (void)ctx;
    (void)chapter;
    (void)page;

    for (i = 0; i < num_quads && builder->count < builder->rect_max; ++i) {
        fz_rect r = fz_rect_from_quad(quads[i]);
        builder->rects[builder->count].x0 = r.x0;
        builder->rects[builder->count].y0 = r.y0;
        builder->rects[builder->count].x1 = r.x1;
        builder->rects[builder->count].y1 = r.y1;
        builder->count++;
    }
    return 0;
}

int spdf_search_page_rects_options(spdf_document* doc, int page_index, const char* needle, int regex,
                                   int regex_multiline, spdf_rect* rects, int rect_max, char* err, size_t err_len) {
    int count = 0;
    search_rect_builder builder;
    char* multiline_needle = NULL;
    const char* search_needle = needle;

    if (!regex) return spdf_search_page_rects(doc, page_index, needle, rects, rect_max, err, err_len);

    set_error(err, err_len, "");
    if (!needle || !*needle) return 0;
    if (!doc || page_index < 0 || page_index >= doc->page_count) {
        set_error(err, err_len, "Page index is out of range.");
        return -1;
    }
    if (!rects || rect_max <= 0)
        return spdf_search_page_options(doc, page_index, needle, regex, regex_multiline, err, err_len);
    if (regex_multiline) {
        multiline_needle = copy_multiline_regex_pattern(needle);
        if (!multiline_needle) {
            set_error(err, err_len, "Out of memory");
            return -1;
        }
        search_needle = multiline_needle;
    }

    fz_try(doc->ctx) {
        builder.rects = rects;
        builder.rect_max = rect_max;
        builder.count = 0;
        (void)fz_match_page_number_cb(doc->ctx, doc->doc, page_index, search_needle, append_match_rects, &builder,
                                      spdf_search_options(regex));
        count = builder.count;
    }
    fz_catch(doc->ctx) {
        set_error(err, err_len, fz_caught_message(doc->ctx));
        free(multiline_needle);
        return -1;
    }

    free(multiline_needle);
    return count;
}

int spdf_select_page_text(spdf_document* doc, int page_index, float ax, float ay, float bx, float by, spdf_rect* rects,
                          int rect_max, char** text_out, char* err, size_t err_len) {
    fz_stext_page* text = NULL;
    fz_quad quads[256];
    fz_point a;
    fz_point b;
    int max_hits;
    int count = 0;
    int i;
    char* copied = NULL;

    set_error(err, err_len, "");
    if (text_out) *text_out = NULL;
    if (!doc || page_index < 0 || page_index >= doc->page_count) {
        set_error(err, err_len, "Page index is out of range.");
        return -1;
    }

    max_hits = rect_max < 256 ? rect_max : 256;
    if (!rects || max_hits <= 0) max_hits = 0;

    fz_try(doc->ctx) {
        text = fz_new_stext_page_from_page_number(doc->ctx, doc->doc, page_index, NULL);
        a = fz_make_point(ax, ay);
        b = fz_make_point(bx, by);
        if (max_hits > 0) {
            count = fz_highlight_selection(doc->ctx, text, a, b, quads, max_hits);
            if (count > max_hits) count = max_hits;
            for (i = 0; i < count; ++i) {
                fz_rect r = fz_rect_from_quad(quads[i]);
                rects[i].x0 = r.x0;
                rects[i].y0 = r.y0;
                rects[i].x1 = r.x1;
                rects[i].y1 = r.y1;
            }
        }
        if (text_out) {
            copied = fz_copy_selection(doc->ctx, text, a, b, 0);
            *text_out = copy_string(copied ? copied : "");
            if (!*text_out) fz_throw(doc->ctx, FZ_ERROR_SYSTEM, "Out of memory");
        }
        if (copied) {
            fz_free(doc->ctx, copied);
            copied = NULL;
        }
        fz_drop_stext_page(doc->ctx, text);
        text = NULL;
    }
    fz_catch(doc->ctx) {
        set_error(err, err_len, fz_caught_message(doc->ctx));
        if (copied) fz_free(doc->ctx, copied);
        if (text) fz_drop_stext_page(doc->ctx, text);
        if (text_out) {
            free(*text_out);
            *text_out = NULL;
        }
        return -1;
    }

    return count;
}

void spdf_free_string(char* text) {
    free(text);
}

static int append_outline_item(outline_builder* builder, const char* title, int page_index, int level) {
    spdf_outline_item* next_items;
    int next_capacity;

    if (builder->count == builder->capacity) {
        next_capacity = builder->capacity ? builder->capacity * 2 : 32;
        next_items = (spdf_outline_item*)realloc(builder->items, (size_t)next_capacity * sizeof(spdf_outline_item));
        if (!next_items) return 0;
        builder->items = next_items;
        builder->capacity = next_capacity;
    }

    builder->items[builder->count].title = copy_string(title && *title ? title : "Untitled");
    if (!builder->items[builder->count].title) return 0;
    builder->items[builder->count].page_index = page_index;
    builder->items[builder->count].level = level;
    builder->count++;
    return 1;
}

static void collect_outline(spdf_document* doc, outline_builder* builder, fz_outline* outline, int level) {
    fz_outline* item;

    for (item = outline; item; item = item->next) {
        int page_index = -1;
        if (item->page.page >= 0) page_index = fz_page_number_from_location(doc->ctx, doc->doc, item->page);
        if (!append_outline_item(builder, item->title, page_index, level))
            fz_throw(doc->ctx, FZ_ERROR_SYSTEM, "Out of memory");
        if (item->down) collect_outline(doc, builder, item->down, level + 1);
    }
}

int spdf_load_outline(spdf_document* doc, spdf_outline* out, char* err, size_t err_len) {
    fz_outline* outline = NULL;
    outline_builder builder;

    set_error(err, err_len, "");
    if (!out) {
        set_error(err, err_len, "No outline output was supplied.");
        return 0;
    }
    memset(out, 0, sizeof(*out));
    memset(&builder, 0, sizeof(builder));
    if (!doc) return 0;

    fz_try(doc->ctx) {
        outline = fz_load_outline(doc->ctx, doc->doc);
        if (outline) collect_outline(doc, &builder, outline, 0);
        if (outline) fz_drop_outline(doc->ctx, outline);
        outline = NULL;
    }
    fz_catch(doc->ctx) {
        set_error(err, err_len, fz_caught_message(doc->ctx));
        if (outline) fz_drop_outline(doc->ctx, outline);
        out->items = builder.items;
        out->count = builder.count;
        spdf_free_outline(out);
        return 0;
    }

    out->items = builder.items;
    out->count = builder.count;
    return 1;
}

void spdf_free_outline(spdf_outline* outline) {
    int i;

    if (!outline) return;
    for (i = 0; i < outline->count; ++i) free(outline->items[i].title);
    free(outline->items);
    memset(outline, 0, sizeof(*outline));
}

static int append_comment_item(comment_builder* builder, const char* author, const char* text, const char* type,
                               int comment_index, int page_index, fz_rect bounds) {
    spdf_comment_item* next_items;
    char* author_copy;
    char* text_copy;
    char* type_copy;
    int next_capacity;

    if (builder->count == builder->capacity) {
        next_capacity = builder->capacity ? builder->capacity * 2 : 32;
        next_items = (spdf_comment_item*)realloc(builder->items, (size_t)next_capacity * sizeof(spdf_comment_item));
        if (!next_items) return 0;
        builder->items = next_items;
        builder->capacity = next_capacity;
    }

    author_copy = copy_string(author && *author ? author : "");
    text_copy = copy_string(text && *text ? text : "");
    type_copy = copy_string(type && *type ? type : "Annotation");
    if (!author_copy || !text_copy || !type_copy) {
        free(author_copy);
        free(text_copy);
        free(type_copy);
        return 0;
    }
    builder->items[builder->count].author = author_copy;
    builder->items[builder->count].text = text_copy;
    builder->items[builder->count].type = type_copy;
    builder->items[builder->count].index = comment_index;
    builder->items[builder->count].page_index = page_index;
    builder->items[builder->count].bounds.x0 = bounds.x0;
    builder->items[builder->count].bounds.y0 = bounds.y0;
    builder->items[builder->count].bounds.x1 = bounds.x1;
    builder->items[builder->count].bounds.y1 = bounds.y1;
    builder->count++;
    return 1;
}

static int annot_type_should_surface(enum pdf_annot_type type) {
    return type != PDF_ANNOT_LINK && type != PDF_ANNOT_POPUP && type != PDF_ANNOT_WIDGET && type != PDF_ANNOT_SCREEN;
}

static int comment_annotation_should_surface(const char* contents, const char* author, enum pdf_annot_type annot_type) {
    return (contents && *contents) || (author && *author) || annot_type_should_surface(annot_type);
}

static const char* dict_text_or_empty(fz_context* ctx, pdf_obj* obj, pdf_obj* key) {
    const char* text;

    if (!obj) return "";
    text = pdf_dict_get_text_string(ctx, obj, key);
    return text ? text : "";
}

static const char* comment_author_or_empty(fz_context* ctx, pdf_obj* annot_obj, pdf_obj* popup) {
    const char* author = dict_text_or_empty(ctx, annot_obj, PDF_NAME(T));

    if (!author || !*author) author = dict_text_or_empty(ctx, popup, PDF_NAME(T));
    return author;
}

static pdf_obj* popup_for_parent(fz_context* ctx, pdf_obj* annots, pdf_obj* parent) {
    int i;
    int count;

    if (!annots || !parent) return NULL;
    count = pdf_array_len(ctx, annots);
    for (i = 0; i < count; ++i) {
        pdf_obj* annot = pdf_array_get(ctx, annots, i);
        pdf_obj* subtype = pdf_dict_get(ctx, annot, PDF_NAME(Subtype));
        if (!pdf_name_eq(ctx, subtype, PDF_NAME(Popup))) continue;
        if (pdf_objcmp_resolve(ctx, pdf_dict_get(ctx, annot, PDF_NAME(Parent)), parent) == 0) return annot;
    }
    return NULL;
}

static void remove_popups_for_parent(fz_context* ctx, pdf_obj* annots, pdf_obj* parent) {
    int i;

    if (!annots || !parent) return;
    for (i = 0; i < pdf_array_len(ctx, annots);) {
        pdf_obj* annot = pdf_array_get(ctx, annots, i);
        pdf_obj* subtype = pdf_dict_get(ctx, annot, PDF_NAME(Subtype));
        if (pdf_name_eq(ctx, subtype, PDF_NAME(Popup)) &&
            pdf_objcmp_resolve(ctx, pdf_dict_get(ctx, annot, PDF_NAME(Parent)), parent) == 0) {
            pdf_array_delete(ctx, annots, i);
            continue;
        }
        i++;
    }
}

static fz_rect annot_bounds(fz_context* ctx, pdf_annot* annot) {
    fz_rect bounds = fz_empty_rect;
    int i;

    if (pdf_annot_has_quad_points(ctx, annot)) {
        int count = pdf_annot_quad_point_count(ctx, annot);
        for (i = 0; i < count; ++i)
            bounds = fz_union_rect(bounds, fz_rect_from_quad(pdf_annot_quad_point(ctx, annot, i)));
        if (!fz_is_empty_rect(bounds)) return bounds;
    }

    if (pdf_annot_has_ink_list(ctx, annot)) {
        int stroke;
        int stroke_count = pdf_annot_ink_list_count(ctx, annot);
        for (stroke = 0; stroke < stroke_count; ++stroke) {
            int vertex;
            int vertex_count = pdf_annot_ink_list_stroke_count(ctx, annot, stroke);
            for (vertex = 0; vertex < vertex_count; ++vertex)
                bounds = fz_include_point_in_rect(bounds, pdf_annot_ink_list_stroke_vertex(ctx, annot, stroke, vertex));
        }
        if (!fz_is_empty_rect(bounds)) return fz_expand_rect(bounds, 2);
    }

    if (pdf_annot_has_vertices(ctx, annot)) {
        int count = pdf_annot_vertex_count(ctx, annot);
        for (i = 0; i < count; ++i) bounds = fz_include_point_in_rect(bounds, pdf_annot_vertex(ctx, annot, i));
        if (!fz_is_empty_rect(bounds)) return fz_expand_rect(bounds, 2);
    }

    if (pdf_annot_has_line(ctx, annot)) {
        fz_point a;
        fz_point b;
        pdf_annot_line(ctx, annot, &a, &b);
        bounds = fz_include_point_in_rect(bounds, a);
        bounds = fz_include_point_in_rect(bounds, b);
        if (!fz_is_empty_rect(bounds)) return fz_expand_rect(bounds, 2);
    }

    return pdf_bound_annot(ctx, annot);
}

int spdf_load_comments(spdf_document* doc, spdf_comments* out, char* err, size_t err_len) {
    pdf_document* pdf = NULL;
    pdf_page* page = NULL;
    comment_builder builder;
    int i;

    set_error(err, err_len, "");
    if (!out) {
        set_error(err, err_len, "No comments output was supplied.");
        return 0;
    }
    memset(out, 0, sizeof(*out));
    memset(&builder, 0, sizeof(builder));
    if (!doc) return 0;

    fz_try(doc->ctx) {
        pdf = pdf_specifics(doc->ctx, doc->doc);
        if (pdf) {
            for (i = 0; i < doc->page_count; ++i) {
                pdf_annot* annot;
                pdf_obj* annots;
                page = pdf_load_page(doc->ctx, pdf, i);
                annots = pdf_dict_get(doc->ctx, page->obj, PDF_NAME(Annots));
                for (annot = pdf_first_annot(doc->ctx, page); annot; annot = pdf_next_annot(doc->ctx, annot)) {
                    pdf_obj* obj = pdf_annot_obj(doc->ctx, annot);
                    pdf_obj* popup = pdf_dict_get(doc->ctx, obj, PDF_NAME(Popup));
                    enum pdf_annot_type annot_type = pdf_annot_type(doc->ctx, annot);
                    const char* contents = pdf_annot_contents(doc->ctx, annot);
                    const char* author;
                    const char* type = pdf_string_from_annot_type(doc->ctx, annot_type);
                    fz_rect bounds;
                    if (!popup) popup = popup_for_parent(doc->ctx, annots, obj);
                    if (!contents || !*contents) contents = dict_text_or_empty(doc->ctx, popup, PDF_NAME(Contents));
                    author = comment_author_or_empty(doc->ctx, obj, popup);
                    if (!comment_annotation_should_surface(contents, author, annot_type)) continue;
                    bounds = annot_bounds(doc->ctx, annot);
                    if (!append_comment_item(&builder, author, contents, type, builder.count, i, bounds))
                        fz_throw(doc->ctx, FZ_ERROR_SYSTEM, "Out of memory");
                }
                pdf_drop_page(doc->ctx, page);
                page = NULL;
            }
        }
    }
    fz_catch(doc->ctx) {
        set_error(err, err_len, fz_caught_message(doc->ctx));
        if (page) pdf_drop_page(doc->ctx, page);
        out->items = builder.items;
        out->count = builder.count;
        spdf_free_comments(out);
        return 0;
    }

    out->items = builder.items;
    out->count = builder.count;
    return 1;
}

void spdf_free_comments(spdf_comments* comments) {
    int i;

    if (!comments) return;
    for (i = 0; i < comments->count; ++i) {
        free(comments->items[i].author);
        free(comments->items[i].text);
        free(comments->items[i].type);
    }
    free(comments->items);
    memset(comments, 0, sizeof(*comments));
}

static int point_in_rect(float x, float y, fz_rect rect) {
    float x0 = rect.x0 < rect.x1 ? rect.x0 : rect.x1;
    float x1 = rect.x0 < rect.x1 ? rect.x1 : rect.x0;
    float y0 = rect.y0 < rect.y1 ? rect.y0 : rect.y1;
    float y1 = rect.y0 < rect.y1 ? rect.y1 : rect.y0;
    return x >= x0 && x <= x1 && y >= y0 && y <= y1;
}

static int ascii_starts_with_case(const char* text, const char* prefix) {
    while (*prefix) {
        unsigned char a = (unsigned char)*text++;
        unsigned char b = (unsigned char)*prefix++;
        if (tolower(a) != tolower(b)) return 0;
    }
    return 1;
}

static int link_char_can_continue(char c) {
    if ((unsigned char)c <= 32) return 0;
    return strchr("<>\"'[]{}", c) == NULL;
}

static int link_trailing_punctuation(char c) {
    return c == '.' || c == ',' || c == ':' || c == ';' || c == '!' || c == '?' || c == ')' || c == ']';
}

static int line_link_prefix_length(const char* text) {
    if (ascii_starts_with_case(text, "http://")) return 7;
    if (ascii_starts_with_case(text, "https://")) return 8;
    if (ascii_starts_with_case(text, "mailto:")) return 7;
    if (ascii_starts_with_case(text, "ftp://")) return 6;
    if (ascii_starts_with_case(text, "file:")) return 5;
    if (ascii_starts_with_case(text, "www.")) return 4;
    return 0;
}

static char* copy_text_link_uri(const char* text, int start, int end) {
    int add_https = ascii_starts_with_case(text + start, "www.");
    size_t prefix_len = add_https ? strlen("https://") : 0;
    size_t link_len = (size_t)(end - start);
    char* uri = (char*)malloc(prefix_len + link_len + 1);

    if (!uri) return NULL;
    if (add_https) memcpy(uri, "https://", prefix_len);
    memcpy(uri + prefix_len, text + start, link_len);
    uri[prefix_len + link_len] = '\0';
    return uri;
}

static int text_line_link_at_point(fz_stext_line* line, float x, float y, spdf_link_target* out) {
    char text[2048];
    fz_rect rects[2048];
    int count = 0;
    int i;

    for (fz_stext_char* ch = line->first_char; ch && count < (int)(sizeof(text) - 1); ch = ch->next) {
        text[count] = ch->c > 0 && ch->c < 128 ? (char)ch->c : ' ';
        rects[count] = fz_rect_from_quad(ch->quad);
        count++;
    }
    text[count] = '\0';

    for (i = 0; i < count; ++i) {
        int end;
        int j;
        fz_rect link_rect = fz_empty_rect;
        int has_rect = 0;

        if (!line_link_prefix_length(text + i)) continue;
        end = i;
        while (end < count && link_char_can_continue(text[end])) end++;
        while (end > i && link_trailing_punctuation(text[end - 1])) end--;
        if (end <= i) continue;

        for (j = i; j < end; ++j) {
            if (fz_is_empty_rect(rects[j])) continue;
            link_rect = has_rect ? fz_union_rect(link_rect, rects[j]) : rects[j];
            has_rect = 1;
        }
        if (has_rect && point_in_rect(x, y, fz_expand_rect(link_rect, 2.0f))) {
            out->kind = SPDF_LINK_URI;
            out->uri = copy_text_link_uri(text, i, end);
            if (!out->uri) return -1;
            return 1;
        }
        i = end;
    }

    return 0;
}

static int text_link_at_point(spdf_document* doc, int page_index, float x, float y, spdf_link_target* out) {
    fz_stext_page* text = NULL;
    int result = 0;

    fz_var(text);
    fz_try(doc->ctx) {
        text = fz_new_stext_page_from_page_number(doc->ctx, doc->doc, page_index, NULL);
        for (fz_stext_block* block = text ? text->first_block : NULL; block && result == 0; block = block->next) {
            if (block->type == FZ_STEXT_BLOCK_TEXT) {
                for (fz_stext_line* line = block->u.t.first_line; line && result == 0; line = line->next)
                    result = text_line_link_at_point(line, x, y, out);
            }
        }
        if (text) fz_drop_stext_page(doc->ctx, text);
        text = NULL;
    }
    fz_catch(doc->ctx) {
        if (text) fz_drop_stext_page(doc->ctx, text);
        fz_rethrow(doc->ctx);
    }

    return result;
}

int spdf_link_at_point(spdf_document* doc, int page_index, float x, float y, spdf_link_target* out, char* err,
                       size_t err_len) {
    fz_page* page = NULL;
    fz_link* links = NULL;
    fz_link* link;

    set_error(err, err_len, "");
    if (!out) {
        set_error(err, err_len, "No link output was supplied.");
        return 0;
    }
    memset(out, 0, sizeof(*out));
    out->page_index = -1;
    out->zoom = 0.0f;

    if (!doc || page_index < 0 || page_index >= doc->page_count) {
        set_error(err, err_len, "Page index is out of range.");
        return -1;
    }

    fz_try(doc->ctx) {
        page = fz_load_page(doc->ctx, doc->doc, page_index);
        links = fz_load_links(doc->ctx, page);
        for (link = links; link; link = link->next) {
            if (!point_in_rect(x, y, link->rect)) continue;

            if (link->uri && fz_is_external_link(doc->ctx, link->uri)) {
                out->kind = SPDF_LINK_URI;
                out->uri = copy_string(link->uri);
                if (!out->uri) fz_throw(doc->ctx, FZ_ERROR_SYSTEM, "Out of memory");
            } else if (link->uri && *link->uri) {
                float target_x = 0.0f;
                float target_y = 0.0f;
                fz_location loc = fz_resolve_link(doc->ctx, doc->doc, link->uri, &target_x, &target_y);
                int target_page = loc.page >= 0 ? fz_page_number_from_location(doc->ctx, doc->doc, loc) : -1;
                if (target_page >= 0) {
                    out->kind = SPDF_LINK_INTERNAL;
                    out->page_index = target_page;
                    out->x = target_x;
                    out->y = target_y;
                } else {
                    out->kind = SPDF_LINK_URI;
                    out->uri = copy_string(link->uri);
                    if (!out->uri) fz_throw(doc->ctx, FZ_ERROR_SYSTEM, "Out of memory");
                }
            }
            break;
        }
        if (links) fz_drop_link(doc->ctx, links);
        links = NULL;
        fz_drop_page(doc->ctx, page);
        page = NULL;
        if (out->kind == SPDF_LINK_NONE && text_link_at_point(doc, page_index, x, y, out) < 0)
            fz_throw(doc->ctx, FZ_ERROR_SYSTEM, "Out of memory");
    }
    fz_catch(doc->ctx) {
        set_error(err, err_len, fz_caught_message(doc->ctx));
        if (links) fz_drop_link(doc->ctx, links);
        if (page) fz_drop_page(doc->ctx, page);
        spdf_free_link_target(out);
        return -1;
    }

    return out->kind != SPDF_LINK_NONE;
}

void spdf_free_link_target(spdf_link_target* target) {
    if (!target) return;
    free(target->uri);
    memset(target, 0, sizeof(*target));
}

static fz_rect rect_from_spdf_rect(spdf_rect rect) {
    fz_rect out;
    out.x0 = rect.x0 < rect.x1 ? rect.x0 : rect.x1;
    out.x1 = rect.x0 < rect.x1 ? rect.x1 : rect.x0;
    out.y0 = rect.y0 < rect.y1 ? rect.y0 : rect.y1;
    out.y1 = rect.y0 < rect.y1 ? rect.y1 : rect.y0;
    return out;
}

int spdf_add_highlight_comment(spdf_document* doc, int page_index, const spdf_rect* rects, int rect_count,
                               const char* text, const char* author, char* err, size_t err_len) {
    pdf_document* pdf = NULL;
    pdf_page* page = NULL;
    pdf_annot* annot = NULL;
    fz_quad* quads = NULL;
    fz_rect bounds = fz_empty_rect;
    const float yellow[3] = {1.0f, 0.86f, 0.08f};
    int i;

    set_error(err, err_len, "");
    if (!doc || page_index < 0 || page_index >= doc->page_count) {
        set_error(err, err_len, "Page index is out of range.");
        return 0;
    }
    if (!rects || rect_count <= 0) {
        set_error(err, err_len, "No selected text was supplied.");
        return 0;
    }

    fz_try(doc->ctx) {
        pdf = pdf_specifics(doc->ctx, doc->doc);
        if (!pdf) fz_throw(doc->ctx, FZ_ERROR_FORMAT, "Comments can only be added to PDF files.");
        page = pdf_load_page(doc->ctx, pdf, page_index);
        quads = (fz_quad*)fz_calloc(doc->ctx, (size_t)rect_count, sizeof(fz_quad));
        for (i = 0; i < rect_count; ++i) {
            fz_rect r = rect_from_spdf_rect(rects[i]);
            if (fz_is_empty_rect(r)) continue;
            quads[i] = fz_quad_from_rect(r);
            bounds = fz_is_empty_rect(bounds) ? r : fz_union_rect(bounds, r);
        }
        if (fz_is_empty_rect(bounds)) fz_throw(doc->ctx, FZ_ERROR_FORMAT, "No selected text was supplied.");

        annot = pdf_create_annot(doc->ctx, page, PDF_ANNOT_HIGHLIGHT);
        pdf_set_annot_quad_points(doc->ctx, annot, rect_count, quads);
        pdf_set_annot_color(doc->ctx, annot, 3, yellow);
        pdf_set_annot_opacity(doc->ctx, annot, 0.35f);
        if (text && *text) pdf_set_annot_contents(doc->ctx, annot, text);
        if (author && *author) pdf_set_annot_author(doc->ctx, annot, author);
        pdf_update_annot(doc->ctx, annot);
        fz_free(doc->ctx, quads);
        quads = NULL;
        pdf_drop_page(doc->ctx, page);
        page = NULL;
    }
    fz_catch(doc->ctx) {
        set_error(err, err_len, fz_caught_message(doc->ctx));
        if (quads) fz_free(doc->ctx, quads);
        if (page) pdf_drop_page(doc->ctx, page);
        return 0;
    }

    return 1;
}

int spdf_add_text_comment(spdf_document* doc, int page_index, float x, float y, const char* text, const char* author,
                          char* err, size_t err_len) {
    pdf_document* pdf = NULL;
    pdf_page* page = NULL;
    pdf_annot* annot = NULL;
    const float yellow[3] = {1.0f, 0.86f, 0.08f};

    set_error(err, err_len, "");
    if (!doc || page_index < 0 || page_index >= doc->page_count) {
        set_error(err, err_len, "Page index is out of range.");
        return 0;
    }

    fz_try(doc->ctx) {
        pdf = pdf_specifics(doc->ctx, doc->doc);
        if (!pdf) fz_throw(doc->ctx, FZ_ERROR_FORMAT, "Comments can only be added to PDF files.");
        page = pdf_load_page(doc->ctx, pdf, page_index);
        annot = pdf_create_annot(doc->ctx, page, PDF_ANNOT_TEXT);
        pdf_set_annot_rect(doc->ctx, annot, fz_make_rect(x, y, x + 24.0f, y + 24.0f));
        pdf_set_annot_color(doc->ctx, annot, 3, yellow);
        if (text && *text) pdf_set_annot_contents(doc->ctx, annot, text);
        if (author && *author) pdf_set_annot_author(doc->ctx, annot, author);
        pdf_update_annot(doc->ctx, annot);
        pdf_drop_page(doc->ctx, page);
        page = NULL;
    }
    fz_catch(doc->ctx) {
        set_error(err, err_len, fz_caught_message(doc->ctx));
        if (page) pdf_drop_page(doc->ctx, page);
        return 0;
    }

    return 1;
}

static void set_comment_text_and_author(fz_context* ctx, pdf_annot* annot, pdf_obj* popup, const char* text,
                                        const char* author);

int spdf_update_comment(spdf_document* doc, int comment_index, const char* text, const char* author, char* err,
                        size_t err_len) {
    pdf_document* pdf = NULL;
    pdf_page* page = NULL;
    int visible_index = 0;
    int found = 0;
    int i;

    set_error(err, err_len, "");
    if (!doc || comment_index < 0) {
        set_error(err, err_len, "Comment index is out of range.");
        return 0;
    }

    fz_try(doc->ctx) {
        pdf = pdf_specifics(doc->ctx, doc->doc);
        if (!pdf) fz_throw(doc->ctx, FZ_ERROR_FORMAT, "Comments can only be edited in PDF files.");
        for (i = 0; i < doc->page_count && !found; ++i) {
            pdf_annot* annot;
            pdf_obj* annots;
            page = pdf_load_page(doc->ctx, pdf, i);
            annots = pdf_dict_get(doc->ctx, page->obj, PDF_NAME(Annots));
            for (annot = pdf_first_annot(doc->ctx, page); annot; annot = pdf_next_annot(doc->ctx, annot)) {
                pdf_obj* obj = pdf_annot_obj(doc->ctx, annot);
                pdf_obj* popup = pdf_dict_get(doc->ctx, obj, PDF_NAME(Popup));
                enum pdf_annot_type annot_type = pdf_annot_type(doc->ctx, annot);
                const char* contents = pdf_annot_contents(doc->ctx, annot);
                const char* current_author;
                if (!popup) popup = popup_for_parent(doc->ctx, annots, obj);
                if (!contents || !*contents) contents = dict_text_or_empty(doc->ctx, popup, PDF_NAME(Contents));
                current_author = comment_author_or_empty(doc->ctx, obj, popup);
                if (!comment_annotation_should_surface(contents, current_author, annot_type)) continue;

                if (visible_index == comment_index) {
                    set_comment_text_and_author(doc->ctx, annot, popup, text, author);
                    found = 1;
                    break;
                }
                visible_index++;
            }
            pdf_drop_page(doc->ctx, page);
            page = NULL;
        }
        if (!found) fz_throw(doc->ctx, FZ_ERROR_FORMAT, "Comment was not found.");
    }
    fz_catch(doc->ctx) {
        set_error(err, err_len, fz_caught_message(doc->ctx));
        if (page) pdf_drop_page(doc->ctx, page);
        return 0;
    }

    return 1;
}

int spdf_delete_comment(spdf_document* doc, int comment_index, char* err, size_t err_len) {
    pdf_document* pdf = NULL;
    pdf_page* page = NULL;
    int visible_index = 0;
    int found = 0;
    int i;

    set_error(err, err_len, "");
    if (!doc || comment_index < 0) {
        set_error(err, err_len, "Comment index is out of range.");
        return 0;
    }

    fz_try(doc->ctx) {
        pdf = pdf_specifics(doc->ctx, doc->doc);
        if (!pdf) fz_throw(doc->ctx, FZ_ERROR_FORMAT, "Comments can only be deleted in PDF files.");
        for (i = 0; i < doc->page_count && !found; ++i) {
            pdf_annot* annot;
            pdf_obj* annots;
            page = pdf_load_page(doc->ctx, pdf, i);
            annots = pdf_dict_get(doc->ctx, page->obj, PDF_NAME(Annots));
            for (annot = pdf_first_annot(doc->ctx, page); annot; annot = pdf_next_annot(doc->ctx, annot)) {
                pdf_obj* obj = pdf_annot_obj(doc->ctx, annot);
                pdf_obj* popup = pdf_dict_get(doc->ctx, obj, PDF_NAME(Popup));
                enum pdf_annot_type annot_type = pdf_annot_type(doc->ctx, annot);
                const char* contents = pdf_annot_contents(doc->ctx, annot);
                const char* current_author;
                if (!popup) popup = popup_for_parent(doc->ctx, annots, obj);
                if (!contents || !*contents) contents = dict_text_or_empty(doc->ctx, popup, PDF_NAME(Contents));
                current_author = comment_author_or_empty(doc->ctx, obj, popup);
                if (!comment_annotation_should_surface(contents, current_author, annot_type)) continue;

                if (visible_index == comment_index) {
                    remove_popups_for_parent(doc->ctx, annots, obj);
                    pdf_delete_annot(doc->ctx, page, annot);
                    found = 1;
                    break;
                }
                visible_index++;
            }
            pdf_drop_page(doc->ctx, page);
            page = NULL;
        }
        if (!found) fz_throw(doc->ctx, FZ_ERROR_FORMAT, "Comment was not found.");
    }
    fz_catch(doc->ctx) {
        set_error(err, err_len, fz_caught_message(doc->ctx));
        if (page) pdf_drop_page(doc->ctx, page);
        return 0;
    }

    return 1;
}

static void set_comment_text_and_author(fz_context* ctx, pdf_annot* annot, pdf_obj* popup, const char* text,
                                        const char* author) {
    pdf_obj* obj = pdf_annot_obj(ctx, annot);

    if (!text) text = "";
    if (!author) author = "";

    pdf_dict_put_text_string(ctx, obj, PDF_NAME(Contents), text);
    pdf_dict_del(ctx, obj, PDF_NAME(RC));
    pdf_dict_put_text_string(ctx, obj, PDF_NAME(T), author);
    if (popup) {
        pdf_dict_put_text_string(ctx, popup, PDF_NAME(Contents), text);
        pdf_dict_del(ctx, popup, PDF_NAME(RC));
        pdf_dict_put_text_string(ctx, popup, PDF_NAME(T), author);
    }
    pdf_dirty_annot(ctx, annot);
    pdf_update_annot(ctx, annot);
}

static char* create_temp_save_path(fz_context* ctx, const char* path) {
    static const char temp_name[] = ".sumatra-save-XXXXXX";
    const char* slash = strrchr(path, '/');
    size_t dir_len = slash ? (size_t)(slash - path + 1) : 0;
    size_t temp_name_len = strlen(temp_name);
    char* temp_path;
    int fd;

    if (dir_len > ((size_t)-1) - temp_name_len - 1) fz_throw(ctx, FZ_ERROR_SYSTEM, "Temporary save path is too long");

    temp_path = (char*)malloc(dir_len + temp_name_len + 1);
    if (!temp_path) fz_throw(ctx, FZ_ERROR_SYSTEM, "Out of memory");
    if (dir_len) memcpy(temp_path, path, dir_len);
    memcpy(temp_path + dir_len, temp_name, temp_name_len + 1);

    fd = mkstemp(temp_path);
    if (fd < 0) {
        int saved_errno = errno;
        free(temp_path);
        fz_throw(ctx, FZ_ERROR_SYSTEM, "Could not create a temporary save file: %s", strerror(saved_errno));
    }
    if (close(fd) != 0) {
        int saved_errno = errno;
        remove(temp_path);
        free(temp_path);
        fz_throw(ctx, FZ_ERROR_SYSTEM, "Could not close a temporary save file: %s", strerror(saved_errno));
    }

    return temp_path;
}

int spdf_save_document(spdf_document* doc, const char* path, char* err, size_t err_len) {
    pdf_document* pdf = NULL;
    pdf_write_options options;
    char* temp_path = NULL;
    const char* save_path;
    int incremental;

    set_error(err, err_len, "");
    if (!doc || !path || !*path) {
        set_error(err, err_len, "No document path was supplied.");
        return 0;
    }

    fz_var(temp_path);
    fz_try(doc->ctx) {
        pdf = pdf_specifics(doc->ctx, doc->doc);
        if (!pdf) fz_throw(doc->ctx, FZ_ERROR_FORMAT, "Only PDF documents can be saved.");
        options = pdf_default_write_options;
        incremental = pdf_can_be_saved_incrementally(doc->ctx, pdf);
        options.do_incremental = incremental;
        options.do_compress = 1;
        options.do_compress_images = 1;
        options.do_compress_fonts = 1;
        save_path = path;
        if (!incremental) {
            temp_path = create_temp_save_path(doc->ctx, path);
            save_path = temp_path;
        }
        pdf_save_document(doc->ctx, pdf, save_path, &options);
    }
    fz_catch(doc->ctx) {
        set_error(err, err_len, fz_caught_message(doc->ctx));
        if (temp_path) {
            remove(temp_path);
            free(temp_path);
        }
        return 0;
    }

    if (temp_path) {
        if (rename(temp_path, path) != 0) {
            set_error(err, err_len, "Could not replace the original PDF after saving.");
            remove(temp_path);
            free(temp_path);
            return 0;
        }
        free(temp_path);
    }
    return 1;
}

static int stext_block_has_text(fz_stext_block* block) {
    for (; block; block = block->next) {
        if (block->type == FZ_STEXT_BLOCK_TEXT) {
            fz_stext_line* line;
            for (line = block->u.t.first_line; line; line = line->next) {
                fz_stext_char* ch;
                for (ch = line->first_char; ch; ch = ch->next) {
                    if (ch->c > 255 || (ch->c > 0 && !isspace((unsigned char)ch->c))) return 1;
                }
            }
        } else if (block->type == FZ_STEXT_BLOCK_STRUCT && block->u.s.down) {
            if (stext_block_has_text(block->u.s.down->first_block)) return 1;
        }
    }
    return 0;
}

int spdf_document_has_text(spdf_document* doc, int max_pages, char* err, size_t err_len) {
    fz_stext_page* text = NULL;
    int page_count;
    int i;

    set_error(err, err_len, "");
    if (!doc) return 0;

    page_count = doc->page_count;
    if (max_pages > 0 && max_pages < page_count) page_count = max_pages;

    fz_try(doc->ctx) {
        for (i = 0; i < page_count; ++i) {
            text = fz_new_stext_page_from_page_number(doc->ctx, doc->doc, i, NULL);
            if (text && stext_block_has_text(text->first_block)) {
                fz_drop_stext_page(doc->ctx, text);
                text = NULL;
                return 1;
            }
            if (text) {
                fz_drop_stext_page(doc->ctx, text);
                text = NULL;
            }
        }
    }
    fz_catch(doc->ctx) {
        set_error(err, err_len, fz_caught_message(doc->ctx));
        if (text) fz_drop_stext_page(doc->ctx, text);
        return -1;
    }

    return 0;
}
