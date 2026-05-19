#include "sumatra_pdf_core.h"

#include "mupdf/fitz.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct spdf_document {
    fz_context *ctx;
    fz_document *doc;
    char *title;
    int page_count;
};

typedef struct outline_builder {
    spdf_outline_item *items;
    int count;
    int capacity;
} outline_builder;

static void set_error(char *err, size_t err_len, const char *message)
{
    if (!err || err_len == 0)
        return;
    if (!message)
        message = "Unknown error";
    snprintf(err, err_len, "%s", message);
}

static char *copy_string(const char *value)
{
    size_t len;
    char *copy;

    if (!value)
        value = "";
    len = strlen(value);
    copy = (char *)malloc(len + 1);
    if (!copy)
        return NULL;
    memcpy(copy, value, len + 1);
    return copy;
}

static const char *path_basename(const char *path)
{
    const char *last_slash;

    if (!path || !*path)
        return "Untitled";
    last_slash = strrchr(path, '/');
    return last_slash ? last_slash + 1 : path;
}

spdf_document *spdf_open(const char *path, char *err, size_t err_len)
{
    spdf_document *opened = NULL;
    fz_context *ctx = NULL;
    fz_document *doc = NULL;
    char title[512];

    set_error(err, err_len, "");
    if (!path || !*path) {
        set_error(err, err_len, "No document path was supplied.");
        return NULL;
    }

    ctx = fz_new_context(NULL, NULL, FZ_STORE_UNLIMITED);
    if (!ctx) {
        set_error(err, err_len, "Could not create MuPDF context.");
        return NULL;
    }

    fz_try(ctx) {
        fz_register_document_handlers(ctx);
        doc = fz_open_document(ctx, path);

        opened = (spdf_document *)calloc(1, sizeof(spdf_document));
        if (!opened)
            fz_throw(ctx, FZ_ERROR_SYSTEM, "Out of memory");

        opened->ctx = ctx;
        opened->doc = doc;
        opened->page_count = fz_count_pages(ctx, doc);

        title[0] = '\0';
        if (fz_lookup_metadata(ctx, doc, FZ_META_INFO_TITLE, title, sizeof(title)) <= 0 || !title[0])
            snprintf(title, sizeof(title), "%s", path_basename(path));
        opened->title = copy_string(title);
        if (!opened->title)
            fz_throw(ctx, FZ_ERROR_SYSTEM, "Out of memory");
    }
    fz_catch(ctx) {
        set_error(err, err_len, fz_caught_message(ctx));
        if (opened) {
            free(opened->title);
            free(opened);
        }
        if (doc)
            fz_drop_document(ctx, doc);
        fz_drop_context(ctx);
        return NULL;
    }

    return opened;
}

void spdf_close(spdf_document *doc)
{
    if (!doc)
        return;
    if (doc->doc)
        fz_drop_document(doc->ctx, doc->doc);
    if (doc->ctx)
        fz_drop_context(doc->ctx);
    free(doc->title);
    free(doc);
}

int spdf_page_count(spdf_document *doc)
{
    return doc ? doc->page_count : 0;
}

const char *spdf_title(spdf_document *doc)
{
    return doc && doc->title ? doc->title : "";
}

int spdf_page_size(spdf_document *doc, int page_index, float *width, float *height, char *err, size_t err_len)
{
    fz_page *page = NULL;
    fz_rect bounds;

    set_error(err, err_len, "");
    if (!doc || page_index < 0 || page_index >= doc->page_count) {
        set_error(err, err_len, "Page index is out of range.");
        return 0;
    }

    fz_try(doc->ctx) {
        page = fz_load_page(doc->ctx, doc->doc, page_index);
        bounds = fz_bound_page(doc->ctx, page);
        if (width)
            *width = bounds.x1 - bounds.x0;
        if (height)
            *height = bounds.y1 - bounds.y0;
        fz_drop_page(doc->ctx, page);
        page = NULL;
    }
    fz_catch(doc->ctx) {
        set_error(err, err_len, fz_caught_message(doc->ctx));
        if (page)
            fz_drop_page(doc->ctx, page);
        return 0;
    }

    return 1;
}

int spdf_render_page_rgba(spdf_document *doc, int page_index, float zoom, spdf_bitmap *out, char *err, size_t err_len)
{
    fz_pixmap *pix = NULL;
    unsigned char *dst = NULL;
    unsigned char *src;
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
    if (zoom <= 0.01f)
        zoom = 0.01f;

    fz_try(doc->ctx) {
        pix = fz_new_pixmap_from_page_number(doc->ctx, doc->doc, page_index, fz_scale(zoom, zoom), fz_device_rgb(doc->ctx), 1);
        width = fz_pixmap_width(doc->ctx, pix);
        height = fz_pixmap_height(doc->ctx, pix);
        comps = fz_pixmap_components(doc->ctx, pix);
        alpha = fz_pixmap_alpha(doc->ctx, pix);
        src_stride = fz_pixmap_stride(doc->ctx, pix);
        src = fz_pixmap_samples(doc->ctx, pix);
        stride = width * 4;

        dst = (unsigned char *)malloc((size_t)stride * (size_t)height);
        if (!dst)
            fz_throw(doc->ctx, FZ_ERROR_SYSTEM, "Out of memory");

        for (y = 0; y < height; ++y) {
            const unsigned char *row = src + (size_t)y * (size_t)src_stride;
            unsigned char *out_row = dst + (size_t)y * (size_t)stride;
            for (x = 0; x < width; ++x) {
                const unsigned char *px = row + (size_t)x * (size_t)comps;
                unsigned char *opx = out_row + (size_t)x * 4;
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
        if (pix)
            fz_drop_pixmap(doc->ctx, pix);
        return 0;
    }

    return 1;
}

void spdf_free_bitmap(spdf_bitmap *bitmap)
{
    if (!bitmap)
        return;
    free(bitmap->rgba);
    memset(bitmap, 0, sizeof(*bitmap));
}

int spdf_search_page(spdf_document *doc, int page_index, const char *needle, char *err, size_t err_len)
{
    fz_quad hits[128];
    int hit_marks[128];
    int count = 0;

    set_error(err, err_len, "");
    if (!needle || !*needle)
        return 0;
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

int spdf_search_page_rects(spdf_document *doc, int page_index, const char *needle, spdf_rect *rects, int rect_max, char *err, size_t err_len)
{
    fz_quad hits[256];
    int hit_marks[256];
    int max_hits;
    int count = 0;
    int i;

    set_error(err, err_len, "");
    if (!needle || !*needle)
        return 0;
    if (!doc || page_index < 0 || page_index >= doc->page_count) {
        set_error(err, err_len, "Page index is out of range.");
        return -1;
    }
    if (!rects || rect_max <= 0)
        return spdf_search_page(doc, page_index, needle, err, err_len);

    max_hits = rect_max < 256 ? rect_max : 256;
    fz_try(doc->ctx) {
        count = fz_search_page_number(doc->ctx, doc->doc, page_index, needle, hit_marks, hits, max_hits);
        if (count > max_hits)
            count = max_hits;
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

int spdf_select_page_text(spdf_document *doc, int page_index, float ax, float ay, float bx, float by, spdf_rect *rects, int rect_max, char **text_out, char *err, size_t err_len)
{
    fz_stext_page *text = NULL;
    fz_quad quads[256];
    fz_point a;
    fz_point b;
    int max_hits;
    int count = 0;
    int i;
    char *copied = NULL;

    set_error(err, err_len, "");
    if (text_out)
        *text_out = NULL;
    if (!doc || page_index < 0 || page_index >= doc->page_count) {
        set_error(err, err_len, "Page index is out of range.");
        return -1;
    }

    max_hits = rect_max < 256 ? rect_max : 256;
    if (!rects || max_hits <= 0)
        max_hits = 0;

    fz_try(doc->ctx) {
        text = fz_new_stext_page_from_page_number(doc->ctx, doc->doc, page_index, NULL);
        a = fz_make_point(ax, ay);
        b = fz_make_point(bx, by);
        if (max_hits > 0) {
            count = fz_highlight_selection(doc->ctx, text, a, b, quads, max_hits);
            if (count > max_hits)
                count = max_hits;
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
            if (!*text_out)
                fz_throw(doc->ctx, FZ_ERROR_SYSTEM, "Out of memory");
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
        if (copied)
            fz_free(doc->ctx, copied);
        if (text)
            fz_drop_stext_page(doc->ctx, text);
        if (text_out) {
            free(*text_out);
            *text_out = NULL;
        }
        return -1;
    }

    return count;
}

void spdf_free_string(char *text)
{
    free(text);
}

static int append_outline_item(outline_builder *builder, const char *title, int page_index, int level)
{
    spdf_outline_item *next_items;
    int next_capacity;

    if (builder->count == builder->capacity) {
        next_capacity = builder->capacity ? builder->capacity * 2 : 32;
        next_items = (spdf_outline_item *)realloc(builder->items, (size_t)next_capacity * sizeof(spdf_outline_item));
        if (!next_items)
            return 0;
        builder->items = next_items;
        builder->capacity = next_capacity;
    }

    builder->items[builder->count].title = copy_string(title && *title ? title : "Untitled");
    if (!builder->items[builder->count].title)
        return 0;
    builder->items[builder->count].page_index = page_index;
    builder->items[builder->count].level = level;
    builder->count++;
    return 1;
}

static void collect_outline(spdf_document *doc, outline_builder *builder, fz_outline *outline, int level)
{
    fz_outline *item;

    for (item = outline; item; item = item->next) {
        int page_index = -1;
        if (item->page.page >= 0)
            page_index = fz_page_number_from_location(doc->ctx, doc->doc, item->page);
        if (!append_outline_item(builder, item->title, page_index, level))
            fz_throw(doc->ctx, FZ_ERROR_SYSTEM, "Out of memory");
        if (item->down)
            collect_outline(doc, builder, item->down, level + 1);
    }
}

int spdf_load_outline(spdf_document *doc, spdf_outline *out, char *err, size_t err_len)
{
    fz_outline *outline = NULL;
    outline_builder builder;

    set_error(err, err_len, "");
    if (!out) {
        set_error(err, err_len, "No outline output was supplied.");
        return 0;
    }
    memset(out, 0, sizeof(*out));
    memset(&builder, 0, sizeof(builder));
    if (!doc)
        return 0;

    fz_try(doc->ctx) {
        outline = fz_load_outline(doc->ctx, doc->doc);
        if (outline)
            collect_outline(doc, &builder, outline, 0);
        if (outline)
            fz_drop_outline(doc->ctx, outline);
        outline = NULL;
    }
    fz_catch(doc->ctx) {
        set_error(err, err_len, fz_caught_message(doc->ctx));
        if (outline)
            fz_drop_outline(doc->ctx, outline);
        out->items = builder.items;
        out->count = builder.count;
        spdf_free_outline(out);
        return 0;
    }

    out->items = builder.items;
    out->count = builder.count;
    return 1;
}

void spdf_free_outline(spdf_outline *outline)
{
    int i;

    if (!outline)
        return;
    for (i = 0; i < outline->count; ++i)
        free(outline->items[i].title);
    free(outline->items);
    memset(outline, 0, sizeof(*outline));
}
