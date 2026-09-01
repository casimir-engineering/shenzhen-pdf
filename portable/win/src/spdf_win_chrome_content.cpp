/* The content the sidebar and minimap show, and the temporary bridge that finds
 * it. See spdf_win_chrome_content.h for the three rules that shape this file. */
#include "spdf_win_chrome_content.h"

#include "spdf_win_chrome_thumbs.h"
#include "shenzhen_pdf_core.h"

#include <shellapi.h>
#include <stdlib.h>
#include <string.h>

#pragma comment(lib, "shell32.lib")

/* --- the temporary bridge ----------------------------------------------- */
/*
 * WHAT THIS IS AND WHAT REPLACES IT. The painters are reached only through
 * spdf_win_paint(), whose scene carries a SpdfWinChromeModel and nothing else --
 * no document, no path, no canvas. So until the model (or the scene) carries the
 * outline and the thumbnail store, this file finds the document the only way it
 * can from inside a paint: on the process command line, which is where
 * spdf_win_main.cpp got it too.
 *
 * It is honest about its limits and they are all listed in this change's report:
 * it opens a SECOND document handle (the render workers already do exactly that,
 * because the core allows one spdf_document per thread), it cannot know the
 * canvas's live scroll offset, and it takes the filter text from an environment
 * variable because no keyboard input reaches this track. Every one of those is a
 * field on a struct owned by another track, not a design.
 */

namespace {

struct Bridge {
    int tried;
    char* path;       /* UTF-8, owned */
    int launch_page;  /* from --page N or the --render-window-png positional */
    spdf_document* doc;

    /* Sidebar. */
    int outline_tried;
    spdf_outline outline;
    SpdfWinSidebarRow* rows;
    wchar_t* arena;
    wchar_t filter[128];
    SpdfWinSidebarContent sidebar;

    /* Minimap. */
    SpdfWinThumbStore* thumbs;
    SpdfWinPageSizePt* sizes;
    int size_count;
    SpdfWinMinimapContent minimap;

    SpdfWinChromePanelsContent content;
};

Bridge g_bridge;
const SpdfWinChromePanelsContent* g_attached;

char* utf8_dup_from_wide(const wchar_t* w) {
    int need;
    char* out;
    if (!w) return NULL;
    need = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    if (need <= 0) return NULL;
    out = (char*)malloc((size_t)need);
    if (!out) return NULL;
    if (WideCharToMultiByte(CP_UTF8, 0, w, -1, out, need, NULL, NULL) <= 0) {
        free(out);
        return NULL;
    }
    return out;
}

int file_exists(const wchar_t* path) {
    DWORD attr = GetFileAttributesW(path);
    return attr != INVALID_FILE_ATTRIBUTES && !(attr & FILE_ATTRIBUTE_DIRECTORY);
}

/* The first argument that names an existing file wins, and a `--page N` or a
 * numeric token straight after it sets the launch page. Both of the app's
 * argument forms fall out of that: `[--dark] [--page N] <file.pdf>` and
 * `--render-window-png <file.pdf> <page> <w> <h> <out.png>` -- in the second,
 * out.png does not exist yet, so the document is still the first match. */
void find_document(Bridge* b) {
    int argc = 0;
    wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    int i;

    if (!argv) return;
    for (i = 1; i < argc; ++i) {
        if (wcscmp(argv[i], L"--page") == 0 && i + 1 < argc) {
            b->launch_page = _wtoi(argv[i + 1]);
            ++i;
            continue;
        }
        if (argv[i][0] == L'-') continue;
        if (!file_exists(argv[i])) continue;
        b->path = utf8_dup_from_wide(argv[i]);
        if (i + 1 < argc && argv[i + 1][0] >= L'0' && argv[i + 1][0] <= L'9') b->launch_page = _wtoi(argv[i + 1]);
        break;
    }
    LocalFree(argv);
}

void ensure_path(Bridge* b) {
    if (b->tried) return;
    b->tried = 1;
    find_document(b);
}

/* Reads the filter text. No keyboard input reaches this track, so the only way
 * to exercise the filter in the real app today is the environment -- which is
 * enough to see it work and enough for a screenshot, and costs one getenv on the
 * first sidebar paint. */
void load_filter(Bridge* b) {
    size_t n = 0;
    b->filter[0] = 0;
    if (getenv_s(&n, NULL, 0, "SPDF_SIDEBAR_FILTER") != 0 || n == 0) return;
    if (n > sizeof(b->filter) / sizeof(b->filter[0])) n = sizeof(b->filter) / sizeof(b->filter[0]);
    {
        char narrow[256];
        size_t got = 0;
        if (getenv_s(&got, narrow, sizeof(narrow), "SPDF_SIDEBAR_FILTER") != 0 || got == 0) return;
        /* The environment block is ANSI here, so this one string -- and only
         * this one -- goes through CP_ACP by necessity. It is a debugging hook,
         * not document data; every title beside it is CP_UTF8. */
        MultiByteToWideChar(CP_ACP, 0, narrow, -1, b->filter, (int)(sizeof(b->filter) / sizeof(b->filter[0])));
    }
}

void ensure_outline(Bridge* b) {
    char err[256] = {0};
    const char** titles = NULL;
    int* pages = NULL;
    int* levels = NULL;
    size_t arena_wchars;
    int i;

    if (b->outline_tried) return;
    b->outline_tried = 1;
    b->sidebar.loaded = 1; /* whatever happens below, the answer is now known */
    ensure_path(b);
    if (!b->path) return;
    load_filter(b);
    b->sidebar.filter = b->filter[0] ? b->filter : NULL;

    b->doc = spdf_open(b->path, err, sizeof(err));
    if (!b->doc) return;
    if (!spdf_load_outline(b->doc, &b->outline, err, sizeof(err))) return;
    b->sidebar.total_count = b->outline.count;
    if (b->outline.count <= 0) return;

    titles = (const char**)malloc(sizeof(char*) * (size_t)b->outline.count);
    pages = (int*)malloc(sizeof(int) * (size_t)b->outline.count);
    levels = (int*)malloc(sizeof(int) * (size_t)b->outline.count);
    b->rows = (SpdfWinSidebarRow*)calloc((size_t)b->outline.count, sizeof(SpdfWinSidebarRow));
    arena_wchars = (size_t)b->outline.count * 320u;
    b->arena = (wchar_t*)calloc(arena_wchars, sizeof(wchar_t));
    if (titles && pages && levels && b->rows && b->arena) {
        for (i = 0; i < b->outline.count; ++i) {
            titles[i] = b->outline.items[i].title;
            pages[i] = b->outline.items[i].page_index;
            levels[i] = b->outline.items[i].level;
        }
        b->sidebar.rows = b->rows;
        b->sidebar.row_count = spdf_win_sidebar_build_rows(titles, pages, levels, b->outline.count,
                                                           b->sidebar.filter, b->rows, b->outline.count, b->arena,
                                                           arena_wchars);
    }
    free((void*)titles);
    free(pages);
    free(levels);

    /* macOS selects the first row whose page is the current page
     * (:10613-10620). The live page is not reachable from here, so the launch
     * page stands in -- see the report's model-field request. */
    b->sidebar.selected_row = -1;
    b->sidebar.hot_row = -1;
    for (i = 0; i < b->sidebar.row_count; ++i) {
        if (b->rows[i].page_index != b->launch_page) continue;
        b->sidebar.selected_row = i;
        break;
    }
}

/* `ctx` is the bridge for BOTH hooks: one owner, so a painter never has to know
 * which half of the store it is talking to. */
int bridge_thumb(void* ctx, int page, SpdfWinMinimapThumb* out) {
    return spdf_win_thumbs_lookup(((Bridge*)ctx)->thumbs, page, out);
}

void bridge_request(void* ctx, int first, int last, double panel_w, double side_inset, int dark) {
    Bridge* b = (Bridge*)ctx;
    spdf_win_thumbs_request(b->thumbs, b->sizes, b->size_count, first, last, panel_w, side_inset, dark);
}

void ensure_minimap(Bridge* b) {
    int count;

    ensure_path(b);
    if (!b->path) return;
    if (!b->thumbs) {
        b->thumbs = spdf_win_thumbs_new(b->path);
        if (!b->thumbs) return;
    }
    spdf_win_thumbs_note_paint_thread(b->thumbs);
    spdf_win_thumbs_drain(b->thumbs);
    count = spdf_win_thumbs_page_count(b->thumbs);
    if (count <= 0) return;
    if (count != b->size_count) {
        free(b->sizes);
        b->sizes = (SpdfWinPageSizePt*)calloc((size_t)count, sizeof(SpdfWinPageSizePt));
        b->size_count = b->sizes ? count : 0;
    }
    if (!b->sizes) return;
    spdf_win_thumbs_page_sizes(b->thumbs, b->sizes, b->size_count);

    b->minimap.sizes = b->sizes;
    b->minimap.page_count = b->size_count;
    b->minimap.current_page = b->launch_page < b->size_count ? b->launch_page : 0;
    /* No live scroll offset reaches this track. The launch page's position in
     * the document is the honest approximation, and the viewport band is sized
     * as one page of the document -- both replaced the moment the model carries
     * the canvas's scroll state. */
    b->minimap.scroll_fraction =
        b->size_count > 1 ? (double)b->minimap.current_page / (double)(b->size_count - 1) : 0.0;
    b->minimap.doc_h = (double)b->size_count;
    b->minimap.doc_visible_h = 1.0;
    b->minimap.thumb = bridge_thumb;
    b->minimap.ctx = b;
    b->minimap.request = bridge_request;
}

} /* namespace */

void spdf_win_chrome_content_attach(const SpdfWinChromePanelsContent* content) {
    g_attached = content;
}

void spdf_win_chrome_content_set_document(const char* utf8_path, int current_page) {
    Bridge* b = &g_bridge;

    /* A real provider outranks the bridge entirely. */
    if (g_attached) return;

    if (!utf8_path || !utf8_path[0]) {
        /* The last tab closed. Drop everything rather than keep drawing a
         * document that is no longer open. */
        if (b->path) spdf_win_chrome_content_shutdown();
        return;
    }

    if (b->path && strcmp(b->path, utf8_path) == 0) {
        /* Same document: only the position moved. This is the cheap path and it
         * runs every frame, so it must stay a string compare and two stores. */
        b->launch_page = current_page;
        if (b->minimap.page_count > 0)
            b->minimap.current_page = current_page < b->size_count ? current_page : 0;
        return;
    }

    /* A different document -- a tab switch, or the first paint. shutdown()
     * already releases the handle, the outline, the rows, the arena, the sizes
     * and the thumbnail store, and clears `tried`/`outline_tried`, so the next
     * frame rebuilds everything against the new path. Reusing it here rather
     * than open-coding a second teardown is what stops the two from drifting.
     *
     * Setting `tried` past find_document() is the point: the bridge no longer
     * guesses from the process command line once the app has told it which
     * document is selected. That guess is why the panels used to keep showing
     * the launch document after Ctrl+Tab. */
    spdf_win_chrome_content_shutdown();
    b->path = _strdup(utf8_path);
    b->tried = 1;
    b->launch_page = current_page;
}

const SpdfWinChromePanelsContent* spdf_win_chrome_content_current(void) {
    Bridge* b = &g_bridge;
    if (g_attached) return g_attached;
    ensure_outline(b);
    ensure_minimap(b);
    b->content.sidebar = &b->sidebar;
    b->content.minimap = b->minimap.page_count > 0 ? &b->minimap : NULL;
    return &b->content;
}

void spdf_win_chrome_content_shutdown(void) {
    Bridge* b = &g_bridge;
    spdf_win_thumbs_free(b->thumbs);
    b->thumbs = NULL;
    free(b->sizes);
    b->sizes = NULL;
    b->size_count = 0;
    if (b->outline.items) spdf_free_outline(&b->outline);
    free(b->rows);
    b->rows = NULL;
    free(b->arena);
    b->arena = NULL;
    if (b->doc) spdf_close(b->doc);
    b->doc = NULL;
    free(b->path);
    b->path = NULL;
    memset(&b->sidebar, 0, sizeof(b->sidebar));
    memset(&b->minimap, 0, sizeof(b->minimap));
    b->tried = 0;
    b->outline_tried = 0;
}
