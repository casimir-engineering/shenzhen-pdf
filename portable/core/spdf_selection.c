#include "spdf_selection.h"

#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct selection_rect_builder {
    spdf_rect* items;
    int count;
    int capacity;
} selection_rect_builder;

static void selection_error(char* err, size_t err_len, const char* message) {
    if (err && err_len) snprintf(err, err_len, "%s", message ? message : "Unknown selection error");
}

static int valid_rect(fz_rect rect) {
    return isfinite(rect.x0) && isfinite(rect.y0) && isfinite(rect.x1) && isfinite(rect.y1) && rect.x1 > rect.x0 &&
           rect.y1 > rect.y0;
}

static int valid_quad(fz_quad quad) {
    return valid_rect(fz_rect_from_quad(quad));
}

static int append_rect(selection_rect_builder* builder, fz_rect rect) {
    spdf_rect* grown;
    int capacity;

    if (!valid_rect(rect)) return 0;
    if (builder->count == builder->capacity) {
        if (builder->capacity > INT_MAX / 2) return -1;
        capacity = builder->capacity ? builder->capacity * 2 : 32;
        if (capacity < builder->capacity || (size_t)capacity > SIZE_MAX / sizeof(spdf_rect)) return -1;
        grown = (spdf_rect*)realloc(builder->items, (size_t)capacity * sizeof(spdf_rect));
        if (!grown) return -1;
        builder->items = grown;
        builder->capacity = capacity;
    }
    builder->items[builder->count++] = (spdf_rect){rect.x0, rect.y0, rect.x1, rect.y1};
    return 1;
}

static int text_has_content(const char* text) {
    const unsigned char* p = (const unsigned char*)text;
    while (p && *p) {
        if (*p > 32) return 1;
        ++p;
    }
    return 0;
}

static char* copy_text(const char* text) {
    size_t len = text ? strlen(text) : 0;
    char* copied = (char*)malloc(len + 1);
    if (!copied) return NULL;
    if (len) memcpy(copied, text, len);
    copied[len] = 0;
    return copied;
}

static fz_stext_char* hit_blocks(fz_stext_block* first, fz_point point, fz_stext_block** block_out, int depth,
                                 int* depth_exceeded) {
    fz_stext_block* block;
    fz_stext_line* line;
    fz_stext_char* ch;

    if (depth > 64) {
        *depth_exceeded = 1;
        return NULL;
    }
    for (block = first; block; block = block->next) {
        if (block->type == FZ_STEXT_BLOCK_STRUCT && block->u.s.down) {
            ch = hit_blocks(block->u.s.down->first_block, point, block_out, depth + 1, depth_exceeded);
            if (ch) return ch;
        }
        if (block->type != FZ_STEXT_BLOCK_TEXT) continue;
        for (line = block->u.t.first_line; line; line = line->next) {
            for (ch = line->first_char; ch; ch = ch->next) {
                if (fz_is_unicode_whitespace(ch->c) || !valid_quad(ch->quad)) continue;
                if (fz_is_point_inside_quad(point, ch->quad)) {
                    if (block_out) *block_out = block;
                    return ch;
                }
            }
        }
    }
    return NULL;
}

static fz_stext_char* hit_character(fz_stext_page* page, fz_point point, fz_stext_block** block_out,
                                    int* depth_exceeded) {
    return hit_blocks(page->first_block, point, block_out, 0, depth_exceeded);
}

static void mark_unicode_flags(fz_stext_page* page, const spdf_text_selection* result, unsigned* flags) {
    fz_stext_block* block;
    fz_stext_line* line;
    fz_stext_char* ch;
    int i;

    if (!result->rects || !result->rect_count) return;
    for (block = page->first_block; block; block = block->next) {
        if (block->type != FZ_STEXT_BLOCK_TEXT) continue;
        for (line = block->u.t.first_line; line; line = line->next) {
            for (ch = line->first_char; ch; ch = ch->next) {
                fz_rect char_rect;
                if (!(ch->flags & (FZ_STEXT_UNICODE_IS_CID | FZ_STEXT_UNICODE_IS_GID))) continue;
                char_rect = fz_rect_from_quad(ch->quad);
                if (!valid_rect(char_rect)) continue;
                for (i = 0; i < result->rect_count; ++i) {
                    spdf_rect r = result->rects[i];
                    if (char_rect.x1 > r.x0 && char_rect.x0 < r.x1 && char_rect.y1 > r.y0 && char_rect.y0 < r.y1) {
                        *flags |= SPDF_SELECTION_UNICODE_INCOMPLETE;
                        return;
                    }
                }
            }
        }
    }
}

static void collect_highlights(fz_context* ctx, fz_stext_page* page, fz_point a, fz_point b,
                               spdf_text_selection* result) {
    selection_rect_builder builder = {0};
    fz_quad* quads = NULL;
    int capacity = 32;
    int count;
    int i;

    fz_var(quads);
    fz_var(builder.items);
    fz_try(ctx) {
        for (;;) {
            quads = (fz_quad*)fz_realloc_array(ctx, quads, capacity, fz_quad);
            count = fz_highlight_selection(ctx, page, a, b, quads, capacity);
            if (count < capacity) break;
            if (capacity > INT_MAX / 2) fz_throw(ctx, FZ_ERROR_LIMIT, "Selection geometry is too large");
            capacity *= 2;
        }
        for (i = 0; i < count; ++i) {
            if (append_rect(&builder, fz_rect_from_quad(quads[i])) < 0) fz_throw(ctx, FZ_ERROR_SYSTEM, "Out of memory");
            if (!valid_quad(quads[i])) result->flags |= SPDF_SELECTION_GEOMETRY_INCOMPLETE;
        }
        fz_free(ctx, quads);
        quads = NULL;
    }
    fz_catch(ctx) {
        fz_free(ctx, quads);
        free(builder.items);
        fz_rethrow(ctx);
    }
    result->rects = builder.items;
    result->rect_count = builder.count;
}

static void select_range(fz_context* ctx, fz_stext_page* page, fz_point a, fz_point b, spdf_text_selection* result) {
    char* mupdf_text = NULL;

    fz_var(mupdf_text);
    fz_try(ctx) {
        mupdf_text = fz_copy_selection(ctx, page, a, b, 0);
        result->text = copy_text(mupdf_text);
        if (!result->text) fz_throw(ctx, FZ_ERROR_SYSTEM, "Out of memory");
        collect_highlights(ctx, page, a, b, result);
        mark_unicode_flags(page, result, &result->flags);
        fz_free(ctx, mupdf_text);
    }
    fz_catch(ctx) {
        fz_free(ctx, mupdf_text);
        fz_rethrow(ctx);
    }
}

static void select_block(fz_context* ctx, fz_stext_block* block, spdf_text_selection* result) {
    selection_rect_builder builder = {0};
    fz_buffer* buffer = NULL;
    fz_stext_line* line;
    fz_stext_char* ch;
    unsigned char* extracted = NULL;
    int wrote_line = 0;

    fz_var(buffer);
    fz_var(extracted);
    fz_var(builder.items);
    fz_try(ctx) {
        buffer = fz_new_buffer(ctx, 256);
        for (line = block->u.t.first_line; line; line = line->next) {
            int line_has_text = 0;
            if (wrote_line) fz_append_byte(ctx, buffer, '\n');
            for (ch = line->first_char; ch; ch = ch->next) {
                int c = ch->c < 32 ? FZ_REPLACEMENT_CHARACTER : ch->c;
                fz_append_rune(ctx, buffer, c);
                line_has_text = 1;
                if (ch->flags & (FZ_STEXT_UNICODE_IS_CID | FZ_STEXT_UNICODE_IS_GID))
                    result->flags |= SPDF_SELECTION_UNICODE_INCOMPLETE;
                if (fz_is_unicode_whitespace(ch->c)) continue;
                if (!valid_quad(ch->quad)) {
                    result->flags |= SPDF_SELECTION_GEOMETRY_INCOMPLETE;
                    continue;
                }
                if (append_rect(&builder, fz_rect_from_quad(ch->quad)) < 0)
                    fz_throw(ctx, FZ_ERROR_SYSTEM, "Out of memory");
            }
            if (line_has_text) wrote_line = 1;
        }
        fz_terminate_buffer(ctx, buffer);
        fz_buffer_extract(ctx, buffer, &extracted);
        result->text = copy_text((const char*)extracted);
        if (!result->text) fz_throw(ctx, FZ_ERROR_SYSTEM, "Out of memory");
        result->rects = builder.items;
        result->rect_count = builder.count;
        builder.items = NULL;
        fz_free(ctx, extracted);
        extracted = NULL;
        fz_drop_buffer(ctx, buffer);
        buffer = NULL;
    }
    fz_catch(ctx) {
        fz_free(ctx, extracted);
        fz_drop_buffer(ctx, buffer);
        free(builder.items);
        fz_rethrow(ctx);
    }
}

void spdf_free_text_selection(spdf_text_selection* selection) {
    if (!selection) return;
    free(selection->text);
    free(selection->rects);
    memset(selection, 0, sizeof(*selection));
}

spdf_selection_status spdf_select_text(spdf_document* doc, int page_index, spdf_selection_granularity granularity,
                                       float ax, float ay, float bx, float by, spdf_text_selection* out, char* err,
                                       size_t err_len) {
    fz_context* ctx = NULL;
    fz_document* mupdf_doc = NULL;
    fz_stext_page* page = NULL;
    fz_stext_block* hit_block = NULL;
    fz_stext_options options = {0};
    fz_point a = fz_make_point(ax, ay);
    fz_point b = fz_make_point(bx, by);
    int no_hit = 0;
    int depth_exceeded = 0;

    selection_error(err, err_len, "");
    if (!out) {
        selection_error(err, err_len, "Selection output is required.");
        return SPDF_SELECTION_ERROR;
    }
    memset(out, 0, sizeof(*out));
    if (granularity < SPDF_SELECTION_RANGE || granularity > SPDF_SELECTION_BLOCK) {
        selection_error(err, err_len, "Selection granularity is invalid.");
        return SPDF_SELECTION_ERROR;
    }
    if (!spdf_selection_document_access(doc, page_index, &ctx, &mupdf_doc, err, err_len)) return SPDF_SELECTION_ERROR;

    options.flags = FZ_STEXT_ACCURATE_BBOXES | FZ_STEXT_USE_CID_FOR_UNKNOWN_UNICODE;
    if (granularity == SPDF_SELECTION_BLOCK) options.flags |= FZ_STEXT_SEGMENT | FZ_STEXT_PARAGRAPH_BREAK;
    fz_var(page);
    fz_try(ctx) {
        page = fz_new_stext_page_from_page_number(ctx, mupdf_doc, page_index, &options);
        if (granularity != SPDF_SELECTION_RANGE && !hit_character(page, a, &hit_block, &depth_exceeded)) {
            if (depth_exceeded) fz_throw(ctx, FZ_ERROR_LIMIT, "Structured text nesting is too deep");
            no_hit = 1;
        } else if (granularity == SPDF_SELECTION_WORD) {
            fz_stext_page isolated_page = *page;
            fz_stext_block isolated_block = *hit_block;
            isolated_block.prev = NULL;
            isolated_block.next = NULL;
            isolated_page.first_block = &isolated_block;
            isolated_page.last_block = &isolated_block;
            b = a;
            (void)fz_snap_selection(ctx, &isolated_page, &a, &b, FZ_SELECT_WORDS);
            select_range(ctx, &isolated_page, a, b, out);
        } else if (granularity == SPDF_SELECTION_BLOCK) {
            select_block(ctx, hit_block, out);
        } else {
            select_range(ctx, page, a, b, out);
        }
        fz_drop_stext_page(ctx, page);
        page = NULL;
    }
    fz_catch(ctx) {
        selection_error(err, err_len, fz_caught_message(ctx));
        fz_drop_stext_page(ctx, page);
        spdf_free_text_selection(out);
        return SPDF_SELECTION_ERROR;
    }

    if (no_hit) return SPDF_SELECTION_NONE;
    if (!text_has_content(out->text) || out->rect_count == 0) {
        unsigned flags = out->flags;
        spdf_free_text_selection(out);
        out->flags = flags;
        return SPDF_SELECTION_NONE;
    }
    return SPDF_SELECTION_OK;
}
