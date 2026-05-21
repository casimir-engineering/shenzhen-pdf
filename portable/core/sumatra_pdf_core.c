#include "sumatra_pdf_core.h"

#include "mupdf/fitz.h"
#include "mupdf/pdf.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct spdf_document {
    fz_context* ctx;
    fz_document* doc;
    char* title;
    int page_count;
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

    ctx = fz_new_context(NULL, NULL, FZ_STORE_UNLIMITED);
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
    fz_rect bounds;

    set_error(err, err_len, "");
    if (!doc || page_index < 0 || page_index >= doc->page_count) {
        set_error(err, err_len, "Page index is out of range.");
        return 0;
    }

    fz_try(doc->ctx) {
        page = fz_load_page(doc->ctx, doc->doc, page_index);
        bounds = fz_bound_page(doc->ctx, page);
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

int spdf_render_page_rgba(spdf_document* doc, int page_index, float zoom, spdf_bitmap* out, char* err, size_t err_len) {
    fz_pixmap* pix = NULL;
    unsigned char* dst = NULL;
    unsigned char* src;
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
    if (zoom <= 0.01f) zoom = 0.01f;

    fz_try(doc->ctx) {
        pix = fz_new_pixmap_from_page_number(doc->ctx, doc->doc, page_index, fz_scale(zoom, zoom),
                                             fz_device_rgb(doc->ctx), 1);
        width = fz_pixmap_width(doc->ctx, pix);
        height = fz_pixmap_height(doc->ctx, pix);
        comps = fz_pixmap_components(doc->ctx, pix);
        alpha = fz_pixmap_alpha(doc->ctx, pix);
        src_stride = fz_pixmap_stride(doc->ctx, pix);
        src = fz_pixmap_samples(doc->ctx, pix);
        stride = width * 4;

        dst = (unsigned char*)malloc((size_t)stride * (size_t)height);
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
                               int page_index, fz_rect bounds) {
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

static const char* dict_text_or_empty(fz_context* ctx, pdf_obj* obj, pdf_obj* key) {
    const char* text;

    if (!obj) return "";
    text = pdf_dict_get_text_string(ctx, obj, key);
    return text ? text : "";
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
                    const char* author = pdf_annot_author(doc->ctx, annot);
                    const char* type = pdf_string_from_annot_type(doc->ctx, annot_type);
                    fz_rect bounds;
                    if (!popup) popup = popup_for_parent(doc->ctx, annots, obj);
                    if (!contents || !*contents) contents = dict_text_or_empty(doc->ctx, popup, PDF_NAME(Contents));
                    if (!author || !*author) author = dict_text_or_empty(doc->ctx, obj, PDF_NAME(T));
                    if (!author || !*author) author = dict_text_or_empty(doc->ctx, popup, PDF_NAME(T));
                    if ((!contents || !*contents) && (!author || !*author) && !annot_type_should_surface(annot_type))
                        continue;
                    bounds = annot_bounds(doc->ctx, annot);
                    if (!append_comment_item(&builder, author, contents, type, i, bounds))
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
