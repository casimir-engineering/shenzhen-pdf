/* Building the chrome model from the tab model. See spdf_win_chrome_model.h. */
#include "spdf_win_chrome_model.h"

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

    if (!tabs) return;

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
}
