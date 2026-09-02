/* The per-page cursor-region cache and the click that follows a link. See
 * spdf_win_links.h for the layering, the provenance of the pure half, and the
 * reason hover and click ask the core two different questions.
 */
#include "spdf_win_links.h"

#include <stdlib.h>
#include <string.h>

struct spdf_win_links {
    int page;       /* the cached page, or -1 */
    int has_text;   /* text regions were built for it */
    spdf_rect links[SPDF_WIN_CURSOR_REGION_MAX_LINK_RECTS];
    int link_count;
    spdf_rect* text;
    int text_count;
    int text_capacity;
};

spdf_win_links* spdf_win_links_new(void) {
    spdf_win_links* links = (spdf_win_links*)calloc(1, sizeof(*links));
    if (links) links->page = -1;
    return links;
}

void spdf_win_links_free(spdf_win_links* links) {
    if (!links) return;
    free(links->text);
    free(links);
}

void spdf_win_links_invalidate(spdf_win_links* links) {
    if (!links) return;
    links->page = -1;
    links->has_text = 0;
    links->link_count = 0;
    links->text_count = 0;
}

/* --- building ------------------------------------------------------------- */

static void build_links(spdf_win_links* cache, spdf_document* doc, int page_index) {
    spdf_rect raw[SPDF_WIN_CURSOR_REGION_MAX_LINK_RECTS];
    char err[256];
    int count, i;

    cache->link_count = 0;
    /* detect_text_links = 0: hover runs on every mouse move and must not build
     * the page's structured text. spdf_page_link_rects's header says so. */
    count = spdf_page_link_rects(doc, page_index, 0, raw, (int)(sizeof(raw) / sizeof(raw[0])), err, sizeof(err));
    if (count < 0) return; /* an unreadable page has no links, not a crash */
    for (i = 0; i < count; ++i)
        spdf_win_cursor_region_append_rect(cache->links, &cache->link_count,
                                           (int)(sizeof(cache->links) / sizeof(cache->links[0])), &raw[i]);
}

static void build_text(spdf_win_links* cache, spdf_document* doc, int page_index) {
    spdf_text_lines lines;
    char err[256];
    int i;

    cache->text_count = 0;
    memset(&lines, 0, sizeof(lines));
    if (!spdf_extract_page_text_lines(doc, page_index, &lines, err, sizeof(err))) return;
    if (lines.count > cache->text_capacity) {
        spdf_rect* grown = (spdf_rect*)realloc(cache->text, sizeof(spdf_rect) * (size_t)lines.count);
        if (!grown) {
            spdf_free_text_lines(&lines);
            return;
        }
        cache->text = grown;
        cache->text_capacity = lines.count;
    }
    for (i = 0; i < lines.count; ++i)
        spdf_win_cursor_region_append_rect(cache->text, &cache->text_count, cache->text_capacity, &lines.items[i].bounds);
    spdf_free_text_lines(&lines);
}

int spdf_win_links_ensure_page(spdf_win_links* links, spdf_document* doc, int page_index, int want_text_regions) {
    if (!links || !doc || page_index < 0) return 0;
    if (links->page != page_index) {
        links->page = page_index;
        links->has_text = 0;
        links->text_count = 0;
        build_links(links, doc, page_index);
    }
    if (want_text_regions && !links->has_text) {
        build_text(links, doc, page_index);
        links->has_text = 1;
    }
    return 1;
}

/* --- asking --------------------------------------------------------------- */

SpdfWinCursorRegionKind spdf_win_links_region_at(spdf_win_links* links, spdf_document* doc, int page_index,
                                                 int want_text_regions, float x, float y) {
    if (!spdf_win_links_ensure_page(links, doc, page_index, want_text_regions)) return SPDF_WIN_CURSOR_REGION_NONE;
    return spdf_win_cursor_region_at_point(links->links, (unsigned)links->link_count, links->text,
                                           (unsigned)links->text_count, (double)x, (double)y,
                                           SPDF_WIN_CURSOR_LINK_HIT_PADDING);
}

int spdf_win_links_hit(spdf_win_links* links, spdf_document* doc, int page_index, float x, float y) {
    int i;
    if (!spdf_win_links_ensure_page(links, doc, page_index, 0)) return 0;
    for (i = 0; i < links->link_count; ++i)
        if (spdf_win_cursor_rect_contains(&links->links[i], (double)x, (double)y, SPDF_WIN_CURSOR_LINK_HIT_PADDING))
            return 1;
    return 0;
}

int spdf_win_links_target_at(spdf_document* doc, int page_index, float x, float y, spdf_link_target* out) {
    char err[256];
    int rc;

    if (!out) return -1;
    memset(out, 0, sizeof(*out));
    out->page_index = -1;
    if (!doc || page_index < 0) return -1;
    /* detect_text_links = 1 HERE and nowhere else: this runs once per click, so
     * it can afford the structured-text pass that turns a bare URL printed in
     * the page into a followable link. */
    rc = spdf_link_at_point(doc, page_index, x, y, out, 1, err, sizeof(err));
    if (rc < 0) return -1;
    return out->kind == SPDF_LINK_NONE ? 0 : 1;
}
