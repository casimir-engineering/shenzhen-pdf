/* Building the chrome model from the tab model. See spdf_win_chrome_model.h. */
#include "spdf_win_chrome_model.h"

#include "spdf_win_chrome_find.h"

#include <string.h>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

namespace {

/* The tab model stores UTF-8; the strip draws UTF-16. MultiByteToWideChar with
 * CP_UTF8 rather than a narrow conversion, for the reason the whole port calls
 * *W APIs: this machine's ANSI code page is 1252, so a narrow round trip loses
 * every character outside it -- and a tab title is exactly where a CJK or
 * accented filename shows up. Gotcha 20.
 *
 * On failure the title is left empty rather than filled with replacement
 * characters: a blank tab reads as "no title", where mojibake reads as
 * corruption of the document. */
void widen_title(const char* utf8, wchar_t* out, int out_len) {
    out[0] = L'\0';
    if (!utf8 || !utf8[0] || out_len < 2) return;
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, -1, out, out_len) == 0) out[0] = L'\0';
}

/* macOS shows a tab's DISPLAY NAME, not its path: the leaf, with a known
 * extension stripped (spdf_display_label_without_extension,
 * SPDFMacSupport.mm:18-31). The tab model's title is already a leaf, so only the
 * extension needs handling.
 *
 * Only the formats this app opens are stripped. Trimming after the last dot
 * unconditionally would turn "Rev 2.1 schematic" into "Rev 2", which is worse
 * than showing an extension. */
void strip_known_extension(wchar_t* title) {
    static const wchar_t* known[] = {L".pdf",  L".xps", L".epub", L".mobi", L".fb2", L".cbz",
                                     L".cbr",  L".cb7", L".cbt",  L".md",   L".markdown"};
    size_t len = wcslen(title);
    size_t i;
    for (i = 0; i < sizeof(known) / sizeof(known[0]); ++i) {
        size_t k = wcslen(known[i]);
        if (len > k && _wcsicmp(title + (len - k), known[i]) == 0) {
            title[len - k] = L'\0';
            return;
        }
    }
}

} /* namespace */

void spdf_win_chrome_model_inputs_init(SpdfWinChromeModelInputs* in) {
    if (!in) return;
    memset(in, 0, sizeof(*in));
    /* Both side panels open, as macOS does for a new document
     * (ShenzhenPDFMac.mm:836-840); 0 width asks spdf_win_chrome.h for its own
     * default rather than repeating 240 and 126.5 here. */
    in->show_sidebar = 1;
    in->show_minimap = 1;
    in->hot_tab = -1;
    in->hot_close = -1;
    in->page_index = -1;
    in->zoom_dpi_scale = 1.0f;
    in->fit_mode = SPDF_WIN_CHROME_FIT_WIDTH; /* what the canvas opens at */
}

void spdf_win_chrome_model_build(SpdfWinChromeModel* model, SpdfWinChromeTabStore* store, spdf_win_tabs* tabs,
                                 const SpdfWinChromeModelInputs* in) {
    SpdfWinChromeModelInputs defaults;
    int count, i;

    if (!model || !store) return;
    memset(model, 0, sizeof(*model));
    memset(store, 0, sizeof(*store));
    if (!in) {
        spdf_win_chrome_model_inputs_init(&defaults);
        in = &defaults;
    }

    model->dark = in->dark;
    model->show_sidebar = in->show_sidebar;
    model->show_minimap = in->show_minimap;
    model->sidebar_w = in->sidebar_w;
    model->minimap_w = in->minimap_w;
    model->sidebar_section = 0; /* Chapters, as macOS opens */
    model->search_active = 0;
    model->hot_tab = in->hot_tab;
    model->hot_close = in->hot_close;
    model->selected_tab = -1;
    model->page_index = in->page_index;
    model->page_count = in->page_count;
    model->zoom = in->zoom;
    model->zoom_dpi_scale = in->zoom_dpi_scale;
    model->fit_mode = in->fit_mode;

    if (!tabs) {
        /* Still fill the find state: a model with no tabs is what the window
         * builds while the last tab closes, and leaving the counter showing a
         * previous document's total there would be a lie about a document that
         * is gone. With no path the session cancels and reports nothing. */
        spdf_win_find_fill_model(model, NULL);
        return;
    }

    count = spdf_win_tabs_count(tabs);
    if (count > SPDF_WIN_CHROME_MAX_TABS) count = SPDF_WIN_CHROME_MAX_TABS;

    for (i = 0; i < count; ++i) {
        widen_title(spdf_win_tabs_title(tabs, i), store->titles[i], SPDF_WIN_CHROME_MAX_TITLE);
        strip_known_extension(store->titles[i]);
        store->tabs[i].title = store->titles[i];
        /* read_only needs the SOURCE file's write permission, which the tab
         * model does not carry -- macOS reads it at open and shows an orange dot
         * (SPDFMacTabStripView.mm:585). Reported as absent rather than guessed:
         * a wrong dot is a claim about the user's file.
         *
         * `missing` likewise: the model has no per-tab existence flag, and
         * probing the filesystem here would put a stat on the paint path, which
         * the repo's speed rule forbids. Both belong in the tab model, set at
         * open and on a directory change. */
        store->tabs[i].read_only = 0;
        store->tabs[i].missing = 0;
    }
    store->count = count;

    model->tabs = store->tabs;
    model->tab_count = count;
    model->selected_tab = spdf_win_tabs_selected_index(tabs);
    if (model->selected_tab >= count) model->selected_tab = count > 0 ? count - 1 : -1;

    /* The find fields, from the shared session (spdf_win_chrome_find.h). Keyed
     * on the SELECTED tab's path, so a Ctrl+Tab re-targets the search at the
     * document the reader is now looking at rather than at the one the window
     * opened on -- the same defect spdf_win_chrome_content_set_document() exists
     * to prevent for the sidebar. Cheap on the steady path: a strcmp and a poll
     * that finds nothing, and with no query it does not even allocate a session.
     *
     * Here rather than in SpdfWinChromeModelInputs on purpose. Threading eight
     * more fields through the inputs struct would mean the window layer -- which
     * has no search state -- filling eight fields it would have to fetch from
     * this same session anyway, and the headless compose path would have to
     * repeat it. */
    spdf_win_find_fill_model(model, model->selected_tab >= 0 ? spdf_win_tabs_path(tabs, model->selected_tab) : NULL);
}

/* --- the find bridge -----------------------------------------------------
 *
 * The process-wide find session, the temporary query bridge, and the fill that
 * puts the result into the model. Here rather than in spdf_win_chrome_find.cpp
 * for a linking reason worth stating: that file is the toolbar's find PAINTER,
 * and everything it needs is inline in spdf_win_chrome_find.h. Keeping the
 * bridge out of it means a test that links the toolbar painter does not also
 * have to link the search engine, its worker thread and MuPDF behind it.
 * portable/win/tests/d2d_theme_test.c and overlay_paint_test.c are exactly that
 * test, and the difference to them is one source file instead of two.
 *
 * Here rather than in spdf_win_search.cpp for the other reason: that file is at
 * its size cap, and this half is a different thing anyway -- it reaches the
 * session only through the same public API a test does, so the engine's struct
 * stays private to its own translation unit.
 */

namespace {

SpdfWinFindSession* g_shared;
int g_shared_tried;

/* TEMPORARY, and documented as such at its definition -- the same pattern and
 * the same justification as spdf_win_chrome_content.cpp's SPDF_SIDEBAR_FILTER.
 * No keyboard input reaches this track yet (this change's report says exactly
 * what is needed from the input track), so the only way to exercise find in the
 * real app today is the environment. Costs one getenv per process.
 *
 *   SPDF_FIND_QUERY=<text>   the query
 *   SPDF_FIND_REGEX=1        treat it as a regular expression
 *
 * Delete both of these the moment the search field is typeable. */
const char* env_query(void) {
    static char buf[512];
    static int tried;
    size_t got = 0;
    if (tried) return buf[0] ? buf : NULL;
    tried = 1;
    if (getenv_s(&got, buf, sizeof(buf), "SPDF_FIND_QUERY") != 0 || got == 0) buf[0] = 0;
    return buf[0] ? buf : NULL;
}

int env_regex(void) {
    static int value = -1;
    char buf[16];
    size_t got = 0;
    if (value >= 0) return value;
    value = 0;
    if (getenv_s(&got, buf, sizeof(buf), "SPDF_FIND_REGEX") == 0 && got > 0 && buf[0] && buf[0] != '0') value = 1;
    return value;
}

} /* namespace */

SpdfWinFindSession* spdf_win_find_shared(void) {
    if (!g_shared_tried) {
        g_shared_tried = 1;
        /* Lazy for real: no query means no session, no thread and no document
         * handle, so a process that never searches pays one branch. */
        if (env_query()) g_shared = spdf_win_find_session_new();
    }
    return g_shared;
}

/* The scene builder's entry point, over the process-wide session. Here, beside
 * spdf_win_find_shared(), and NOT beside _apply_overlays_for() in
 * spdf_win_search_geometry.h: putting it there would make every consumer of the
 * engine also need this file's shared session, which is exactly the dependency
 * this split exists to avoid -- portable/win/tests/find_overlay_test.c links the
 * engine and nothing else. */
void spdf_win_find_apply_overlays(struct spdf_win_scene* scene) {
    spdf_win_find_apply_overlays_for(spdf_win_find_shared(), scene);
}

void spdf_win_find_fill_model(SpdfWinChromeModel* model, const char* utf8_path) {
    static wchar_t wide_query[512];
    SpdfWinFindSession* s;
    const char* query;

    if (!model) return;
    model->query = NULL;
    model->regex = 0;
    model->searching = 0;
    model->match_count = 0;
    model->match_index = -1;
    model->marks = NULL;
    model->mark_count = 0;
    model->active_mark = -1;

    s = spdf_win_find_shared();
    if (!s) return;
    query = env_query();
    spdf_win_find_set(s, utf8_path, query, env_regex());
    spdf_win_find_poll(s);

    /* The environment block is ANSI here, so this one string -- and only this
     * one -- goes through CP_ACP by necessity. It is a debugging hook, not
     * document data; every other string the chrome draws is CP_UTF8. */
    if (query && !wide_query[0])
        MultiByteToWideChar(CP_ACP, 0, query, -1, wide_query, (int)(sizeof(wide_query) / sizeof(wide_query[0])));
    model->query = query ? wide_query : NULL;
    model->regex = env_regex();
    model->searching = spdf_win_find_searching(s);
    model->match_count = spdf_win_find_match_count(s);
    model->match_index = spdf_win_find_match_index(s);
    model->marks = spdf_win_find_marks(s, &model->mark_count, &model->active_mark);
    /* macOS grows the sidebar's minimum and shows its Search section only while
     * a query is live (ShenzhenPDFMac.mm:3138-3144, :9603-9615). */
    model->search_active = model->query != NULL;

    spdf_win_find_note_paint_thread(s);
}
