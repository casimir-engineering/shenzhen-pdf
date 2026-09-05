/* spdf_win_chrome_content.h — what the sidebar and the minimap actually SHOW.
 *
 * The chrome painters were given geometry (spdf_win_chrome.h) and colours
 * (spdf_win_chrome_theme.h) but no content: the sidebar drew grey bars where
 * chapter titles go and the minimap drew grey lines where thumbnails go. This
 * header is the content layer, and it is deliberately a separate file from both
 * of them because content has a different lifetime from a frame: an outline is
 * loaded once per document and a thumbnail arrives from a worker thread
 * milliseconds or seconds after the frame that first wanted it.
 *
 * THREE RULES SHAPE EVERYTHING BELOW.
 *
 *   1. NOTHING HERE MAY RENDER ON THE PAINT PATH. A painter may only LOOK UP a
 *      thumbnail; producing one is a request to spdf_win_render.h's worker pool,
 *      and a page whose thumbnail has not arrived draws the placeholder. So
 *      every accessor is O(1)-ish and none of them can block. This is the
 *      standing speed rule, and it is why `thumb` returns an int rather than
 *      pixels-or-else.
 *
 *   2. NOTHING HERE MAY RUN ON THE LAUNCH PATH. The outline is loaded on the
 *      first paint that actually needs a chapter list -- not at open -- so
 *      --render-png, the probe, presentation mode and a hidden sidebar pay
 *      exactly nothing. The thumbnail service starts no threads until the first
 *      thumbnail is requested (spdf_win_render.h spawns workers lazily for the
 *      same reason).
 *
 *   3. THE PAINTERS TAKE THIS AS A PARAMETER. spdf_win_chrome_paint.h's ctx
 *      cannot carry it (that header belongs to another track), so
 *      spdf_win_chrome_paint_panels() resolves the provider ONCE at the top and
 *      threads it down as an argument. No drawing function reads it from ambient
 *      state -- see the note on spdf_win_chrome_content_current() for the exact
 *      shape of that seam and what is meant to replace it.
 *
 * C-compatible on purpose: no Direct2D types appear here, so
 * portable/win/tests/sidebar_rows_test.c can compile the row geometry, the
 * filter and the outline conversion as plain C with no render target in sight.
 */
#ifndef SPDF_WIN_CHROME_CONTENT_H
#define SPDF_WIN_CHROME_CONTENT_H

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include <windows.h>
#include <wchar.h>

#include "spdf_win_chrome.h"
#include "spdf_win_layout.h" /* SpdfWinPageSizePt */

#ifdef __cplusplus
extern "C" {
#endif

/* --- the sidebar's Chapters list ----------------------------------------
 *
 * macOS: a headerless NSTableView, rowHeight 25.0, one column 230.0 wide in a
 * 240 pt sidebar (ShenzhenPDFMac.mm:3149-3213). The cell's text field is inset
 * 8 leading and 6 trailing and centred vertically, systemFontOfSize:13, single
 * line, truncating TAIL (:16584-16597, :16620-16624). Nesting is expressed by
 * padding the title with level*3 SPACES with the level clamped to [0, 16]
 * (:16613-16619) -- so it is the string that is indented, not the cell, and
 * this port does the same thing for the same reason: an indent that lives in
 * the text survives truncation and selection highlighting for free.
 *
 * A row whose destination did not resolve (page_index < 0: a /Fit-less dest, a
 * missing target, an external URL -- all three are in the core's conformance
 * suite) is drawn in secondaryLabelColor rather than labelColor, which is
 * exactly macOS's `page >= 0 ? labelColor : secondaryLabelColor`. */

#define SPDF_WIN_SIDEBAR_ROW_H 25.0        /* :3160 rowHeight */
#define SPDF_WIN_SIDEBAR_COLUMN_W 230.0    /* :3166 single column width */
#define SPDF_WIN_SIDEBAR_INSET 8.0         /* panel edge -> column, in a 240 pt sidebar */
#define SPDF_WIN_SIDEBAR_CELL_LEADING 8.0  /* :16590 */
#define SPDF_WIN_SIDEBAR_CELL_TRAILING 6.0 /* :16591 */
#define SPDF_WIN_SIDEBAR_FONT_SIZE 13.0    /* :16622 systemFontOfSize:13 */
#define SPDF_WIN_SIDEBAR_INDENT_SPACES 3   /* :16619 level * 3 spaces */
#define SPDF_WIN_SIDEBAR_MAX_LEVEL 16      /* :16615 clamp */

/* Rows above the list, in points: the segmented control and the filter field
 * are both 24 pt with 8 pt around them, and 6 pt separates the field from the
 * first row. Transcribed from spdf_win_chrome_panels.cpp, which had them as
 * literals at its draw sites; they are here now so the hit-test and the paint
 * cannot disagree. */
#define SPDF_WIN_SIDEBAR_TOP_PAD 8.0
#define SPDF_WIN_SIDEBAR_CONTROL_H 24.0
#define SPDF_WIN_SIDEBAR_FIELD_H 24.0
#define SPDF_WIN_SIDEBAR_FIELD_GAP 6.0

typedef struct SpdfWinSidebarRow {
    const wchar_t* title;  /* UTF-16, already indented by level*3 spaces; borrowed */
    int page_index;        /* < 0 when the outline entry has no resolvable page */
    int level;             /* clamped [0, 16] */
    int outline_index;     /* position in spdf_load_outline order, for the click route */
} SpdfWinSidebarRow;

typedef struct SpdfWinSidebarContent {
    const SpdfWinSidebarRow* rows;
    int row_count;   /* rows AFTER filtering */
    int total_count; /* rows before filtering; 0 means the document has no outline */
    int loaded;      /* 0 while the outline has not been read yet */
    int selected_row;
    int hot_row;   /* -1 when nothing is hovered */
    float scroll_y; /* device px, 0 at the top of the list */
    const wchar_t* filter; /* the live filter text; NULL or empty means none */
} SpdfWinSidebarContent;

/* The sidebar's bands, in the panel's own device-pixel coordinates. One
 * function so the painter and the input router cannot drift: this is
 * spdf_win_chrome.h's rule 2 applied one level down. `filter` comes back empty
 * in Search mode, where macOS hides and disables the field (:3149-3157). */
typedef struct SpdfWinSidebarLayout {
    SpdfWinChromeRect sections;
    SpdfWinChromeRect filter;
    SpdfWinChromeRect list;
    float row_h;
} SpdfWinSidebarLayout;

static SPDF_WIN_CHROME_INLINE void spdf_win_sidebar_layout(SpdfWinChromeRect sidebar, int section, float dpi_scale,
                                                           SpdfWinSidebarLayout* out) {
    float s = dpi_scale > 0.0f ? dpi_scale : 1.0f;
    float y;

    if (!out) return;
    out->sections = spdf_win_chrome_zero();
    out->filter = spdf_win_chrome_zero();
    out->list = spdf_win_chrome_zero();
    out->row_h = spdf_win_chrome_px(SPDF_WIN_SIDEBAR_ROW_H, s);
    if (spdf_win_chrome_rect_empty(sidebar)) return;

    y = sidebar.y + spdf_win_chrome_px(SPDF_WIN_SIDEBAR_TOP_PAD, s);
    out->sections.x = sidebar.x + spdf_win_chrome_px(SPDF_WIN_SIDEBAR_INSET, s);
    out->sections.w = sidebar.w - 2.0f * spdf_win_chrome_px(SPDF_WIN_SIDEBAR_INSET, s);
    out->sections.y = y;
    out->sections.h = spdf_win_chrome_px(SPDF_WIN_SIDEBAR_CONTROL_H, s);
    y = out->sections.y + out->sections.h + spdf_win_chrome_px(SPDF_WIN_SIDEBAR_TOP_PAD, s);

    if (section != 2) {
        out->filter = out->sections;
        out->filter.y = y;
        out->filter.h = spdf_win_chrome_px(SPDF_WIN_SIDEBAR_FIELD_H, s);
        y = out->filter.y + out->filter.h + spdf_win_chrome_px(SPDF_WIN_SIDEBAR_FIELD_GAP, s);
    }

    out->list.x = sidebar.x + spdf_win_chrome_px(SPDF_WIN_SIDEBAR_INSET, s);
    out->list.w = sidebar.w - 2.0f * spdf_win_chrome_px(SPDF_WIN_SIDEBAR_INSET, s);
    out->list.y = y;
    out->list.h = spdf_win_chrome_max(0.0f, sidebar.y + sidebar.h - y);
    if (out->list.w < 0.0f) out->list.w = 0.0f;
}

/* One row's rect in panel coordinates, scroll included. Rows outside the list
 * viewport come back non-empty and simply do not intersect it, so the caller
 * clips rather than special-casing. */
static SPDF_WIN_CHROME_INLINE SpdfWinChromeRect spdf_win_sidebar_row_rect(const SpdfWinSidebarLayout* l, float scroll_y,
                                                                          int row) {
    SpdfWinChromeRect r;
    if (!l || row < 0 || l->row_h <= 0.0f) return spdf_win_chrome_zero();
    r.x = l->list.x;
    r.w = l->list.w;
    r.h = l->row_h;
    r.y = l->list.y - scroll_y + l->row_h * (float)row;
    return r;
}

/* Which row a point lands in, or -1. Used by the input router; the painter uses
 * the same arithmetic through spdf_win_sidebar_row_rect. */
static SPDF_WIN_CHROME_INLINE int spdf_win_sidebar_row_at(const SpdfWinSidebarLayout* l, float scroll_y, int row_count,
                                                          float x, float y) {
    int row;
    if (!l || row_count <= 0 || l->row_h <= 0.0f) return -1;
    if (!spdf_win_chrome_contains(l->list, x, y)) return -1;
    row = (int)floorf((y - l->list.y + scroll_y) / l->row_h);
    if (row < 0 || row >= row_count) return -1;
    return row;
}

/* How far the list can scroll, in device px. */
static SPDF_WIN_CHROME_INLINE float spdf_win_sidebar_max_scroll(const SpdfWinSidebarLayout* l, int row_count) {
    float content;
    if (!l || row_count <= 0) return 0.0f;
    content = l->row_h * (float)row_count;
    return spdf_win_chrome_max(0.0f, content - l->list.h);
}

/* The filter, macOS's semantics exactly (:9666-9670): an empty filter matches
 * everything, an empty title matches nothing, and otherwise it is a substring
 * test that ignores BOTH case and diacritics -- NSCaseInsensitiveSearch |
 * NSDiacriticInsensitiveSearch. FindNLSStringEx with LINGUISTIC_IGNORECASE |
 * NORM_IGNORENONSPACE is the Windows spelling of that same pair, which is why
 * this is not a hand-rolled towupper loop: "Zürich" must match "zurich" on both
 * platforms, and a chapter title is exactly where an accented or CJK name shows
 * up. The towupper loop is kept only as the fallback for a locale that cannot
 * do the linguistic compare at all. */
static SPDF_WIN_CHROME_INLINE int spdf_win_sidebar_ascii_fold_find(const wchar_t* hay, const wchar_t* needle) {
    size_t i, j;
    for (i = 0; hay[i]; ++i) {
        for (j = 0; needle[j]; ++j) {
            wchar_t a = hay[i + j];
            wchar_t b = needle[j];
            if (!a) return 0;
            if (a >= L'a' && a <= L'z') a = (wchar_t)(a - L'a' + L'A');
            if (b >= L'a' && b <= L'z') b = (wchar_t)(b - L'a' + L'A');
            if (a != b) break;
        }
        if (!needle[j]) return 1;
    }
    return 0;
}

static SPDF_WIN_CHROME_INLINE int spdf_win_sidebar_title_matches(const wchar_t* title, const wchar_t* filter) {
    int found;
    if (!filter || !filter[0]) return 1;
    if (!title || !title[0]) return 0;
    SetLastError(ERROR_SUCCESS);
    found = FindNLSStringEx(LOCALE_NAME_USER_DEFAULT, FIND_FROMSTART | LINGUISTIC_IGNORECASE | NORM_IGNORENONSPACE,
                            title, -1, filter, -1, NULL, NULL, NULL, 0);
    if (found >= 0) return 1;
    if (GetLastError() == ERROR_SUCCESS) return 0; /* a real "not found" */
    return spdf_win_sidebar_ascii_fold_find(title, filter);
}

/* --- the minimap's thumbnails -------------------------------------------
 *
 * `thumb` is the only accessor a painter gets, and it is a LOOKUP: it returns 0
 * for a page whose thumbnail is not in the store yet and the painter draws the
 * grey placeholder. `request` is how the store learns which pages are on screen
 * so its bounded window (spdf_win_minimap.h) can follow them and queue what is
 * missing on the render pool. Neither one renders. */
typedef struct SpdfWinMinimapThumb {
    int width;
    int height;
    int stride;
    const unsigned char* rgba; /* borrowed; valid until the next request/drain */
    unsigned revision;         /* bumped when these pixels are replaced, so a
                                * cached device bitmap knows to be rebuilt */
} SpdfWinMinimapThumb;

typedef struct SpdfWinMinimapContent {
    const SpdfWinPageSizePt* sizes; /* page_count entries, PDF points */
    int page_count;
    int current_page;       /* the page whose slot gets the grey outline; -1 for none */
    double scroll_fraction; /* [0,1], drives content_top and the viewport band */
    double doc_h;           /* document height and viewport height in the same */
    double doc_visible_h;   /* unit; only their RATIO is used */
    int (*thumb)(void* ctx, int page, SpdfWinMinimapThumb* out);
    void (*request)(void* ctx, int first, int last, double panel_w, double side_inset, int dark);
    void* ctx;
} SpdfWinMinimapContent;

/* Both panels' content in one value, because the panels painter resolves it
 * once per frame and hands each half to its own painter. */
typedef struct SpdfWinChromePanelsContent {
    const SpdfWinSidebarContent* sidebar;
    const SpdfWinMinimapContent* minimap;
} SpdfWinChromePanelsContent;

/* THE SEAM, AND WHY IT IS SHAPED LIKE THIS.
 *
 * The right home for this is the scene: spdf_win_scene already carries
 * `chrome`, and one more pointer beside it would let spdf_win_main.cpp hand the
 * painters the outline and thumbnail store it already has a document for, with
 * no global anywhere. That is a field on a struct owned by another track, so it
 * is REQUESTED rather than taken (see this change's report).
 *
 * Until then: `attach` installs a provider, and `current` returns it.
 * spdf_win_chrome_paint_panels() calls `current` ONCE, at the top of the frame,
 * and passes the result down as an argument -- so the drawing code itself is
 * still pure, still takes everything as parameters, and still needs no HWND. A
 * provider that was never attached falls back to the built-in one in
 * spdf_win_chrome_content.cpp, which finds the document on the process command
 * line. That fallback is a temporary bridge and says so at its definition. */
void spdf_win_chrome_content_attach(const SpdfWinChromePanelsContent* content);
const SpdfWinChromePanelsContent* spdf_win_chrome_content_current(void);

/* Tells the bridge WHICH document is selected and where the reader is in it.
 * Called once per paint from the app, which is the only thing that knows.
 *
 * Without this the bridge guesses from the process command line, so the panels
 * kept showing the LAUNCH document after a Ctrl+Tab -- the sidebar listed the
 * wrong outline and the minimap the wrong thumbnails, while the canvas beside
 * them showed the right pages. Passing the canvas's live current page also makes
 * the minimap's current-page outline and viewport box follow scrolling instead
 * of pinning to the page the window opened on.
 *
 * `utf8_path` NULL or empty means "no document" (the last tab is closing) and
 * releases everything. A repeated call with the same path is a string compare
 * and two stores, because it runs every frame. Does nothing at all once a real
 * provider has been attached. */
void spdf_win_chrome_content_set_document(const char* utf8_path, int current_page);

/* THE FILTER FIELD'S TEXT, UTF-16, copied. NULL or empty means no filter, which
 * shows every row.
 *
 * WHAT THIS REPLACED: SPDF_SIDEBAR_FILTER, one getenv read on the first sidebar
 * paint, documented as temporary at its definition because no keyboard input
 * reached this track. The field is typeable now and the environment variable is
 * gone.
 *
 * Cheap to call on every keystroke and no-op when nothing changed: it compares,
 * copies at most 127 units, and marks the row list stale. The rebuild happens on
 * the next spdf_win_chrome_content_current(), i.e. on the paint that needs it,
 * and re-filters the outline already in memory rather than reopening the
 * document. Does nothing once a real provider has been attached. */
void spdf_win_chrome_content_set_filter(const wchar_t* filter);

/* Releases the document handle, the outline strings, the thumbnail store and
 * the render service the built-in provider owns, joining the store's threads.
 * Idempotent, and safe with nothing ever having been opened.
 *
 * NOBODY CALLS IT YET, and that is deliberate rather than forgotten. Its place
 * is beside spdf_win_chrome_paint_shutdown() in spdf_win_d2d_destroy(), which is
 * another track's file; requesting one line there is better than installing an
 * atexit handler from here, which would run during CRT teardown and could turn a
 * blocked worker into a hang on exit -- and `close.exits_zero` currently passes
 * without it, because the process teardown reclaims the threads anyway. See this
 * change's report. */
void spdf_win_chrome_content_shutdown(void);

/* --- outline -> rows -----------------------------------------------------
 *
 * Header-only, and deliberately: portable/win/tests/sidebar_rows_test.c drives
 * these with hand-built outlines -- CJK, accented and malformed titles, the
 * cases a narrow conversion mangles silently on this machine's 1252 code page --
 * and it should not have to link the thumbnail store, the render pool and MuPDF
 * to do it. `titles`/`pages`/`levels` are the three parallel arrays
 * spdf_outline holds; `text_arena` receives the indented UTF-16 the rows point
 * into. Returns the number of rows written. */
/* UTF-8 in, UTF-16 out, and never anything narrower. A chapter title is exactly
 * where a CJK or accented name turns up, and this machine's ANSI code page is
 * 1252 -- so MultiByteToWideChar(CP_UTF8, ...) is not a stylistic choice, it is
 * the difference between "Überblick" and "Ãœberblick". Returns the number of
 * wchar_t written INCLUDING the terminator, or 0 on failure. */
static SPDF_WIN_CHROME_INLINE int spdf_win_sidebar_utf16_from_utf8(const char* utf8, wchar_t* out, int out_max) {
    int n;
    if (!out || out_max <= 0) return 0;
    if (!utf8 || !*utf8) {
        out[0] = 0;
        return 1;
    }
    n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, out, out_max);
    if (n > 0) return n;
    /* Malformed UTF-8 from a hostile or damaged document must not lose the row.
     * Without MB_ERR_INVALID_CHARS the conversion substitutes U+FFFD and cannot
     * fail for that reason, so reaching here means the buffer was too small; the
     * title is truncated rather than dropped. */
    n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
    if (n <= 0) {
        out[0] = 0;
        return 1;
    }
    if (MultiByteToWideChar(CP_UTF8, 0, utf8, out_max - 1, out, out_max - 1) <= 0) {
        out[0] = 0;
        return 1;
    }
    out[out_max - 1] = 0;
    return out_max;
}

static SPDF_WIN_CHROME_INLINE int spdf_win_sidebar_build_rows(const char* const* titles, const int* pages, const int* levels, int count,
                                const wchar_t* filter, SpdfWinSidebarRow* out_rows, int out_max, wchar_t* text_arena,
                                size_t arena_wchars) {
    int i;
    int written = 0;
    size_t used = 0;

    if (!out_rows || out_max <= 0 || !text_arena || arena_wchars == 0) return 0;
    for (i = 0; i < count; ++i) {
        wchar_t title[512];
        int level = levels ? levels[i] : 0;
        int indent;
        size_t need;
        wchar_t* dst;
        int k;

        if (written >= out_max) break;
        if (!spdf_win_sidebar_utf16_from_utf8(titles ? titles[i] : NULL, title, (int)(sizeof(title) / sizeof(title[0])))) continue;
        /* macOS substitutes "Untitled" for a missing title (:9876) and filters
         * on the UNINDENTED text, so the indent below cannot affect a match. */
        if (!title[0]) wcscpy_s(title, sizeof(title) / sizeof(title[0]), L"Untitled");
        if (!spdf_win_sidebar_title_matches(title, filter)) continue;

        if (level < 0) level = 0;
        if (level > SPDF_WIN_SIDEBAR_MAX_LEVEL) level = SPDF_WIN_SIDEBAR_MAX_LEVEL;
        indent = level * SPDF_WIN_SIDEBAR_INDENT_SPACES;
        need = (size_t)indent + wcslen(title) + 1;
        if (used + need > arena_wchars) break;
        dst = text_arena + used;
        for (k = 0; k < indent; ++k) dst[k] = L' ';
        wcscpy_s(dst + indent, need - (size_t)indent, title);
        used += need;

        out_rows[written].title = dst;
        out_rows[written].page_index = pages ? pages[i] : -1;
        out_rows[written].level = level;
        out_rows[written].outline_index = i;
        ++written;
    }
    return written;
}


#ifdef __cplusplus
}
#endif

#endif /* SPDF_WIN_CHROME_CONTENT_H */
