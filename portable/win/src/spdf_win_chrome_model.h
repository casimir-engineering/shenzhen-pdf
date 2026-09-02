/* spdf_win_chrome_model.h — build a chrome model from the app's tab state.
 *
 * Its own translation unit rather than a few lines in spdf_win_main.cpp for the
 * reason tools/file-size-limits.md gives: that file is at its 500-line cap and
 * the repo prefers extracting a focused file over raising one. It also keeps the
 * UTF-8-to-UTF-16 title conversion in one place, which is where the storage for
 * those titles has to live anyway.
 *
 * WHY A STORE. SpdfWinChromeModel borrows its title strings, because the painter
 * must not allocate. The tab model owns UTF-8 titles, and the strip needs UTF-16.
 * Something has to own the converted strings for the duration of a paint, and a
 * caller-provided store makes that ownership explicit and stack-allocatable
 * instead of hiding a malloc on the paint path.
 */
#ifndef SPDF_WIN_CHROME_MODEL_H
#define SPDF_WIN_CHROME_MODEL_H

#include "spdf_win_chrome.h"
#include "spdf_win_tabs.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Enough for any strip a human will use: the visible-tab capacity of a 5K-wide
 * window is well under 40, and beyond this the overflow menu is the answer
 * rather than more geometry. Tabs past the limit are not shown in the strip;
 * they remain in the tab model and reachable by Ctrl+Tab, so nothing is lost
 * but the drawing. */
#define SPDF_WIN_CHROME_MAX_TABS 64
#define SPDF_WIN_CHROME_MAX_TITLE 192

typedef struct SpdfWinChromeTabStore {
    SpdfWinChromeTab tabs[SPDF_WIN_CHROME_MAX_TABS];
    wchar_t titles[SPDF_WIN_CHROME_MAX_TABS][SPDF_WIN_CHROME_MAX_TITLE];
    int count;
} SpdfWinChromeTabStore;

/* Everything the window layer knows that the chrome must show, and that the tab
 * model does not carry.
 *
 * A STRUCT RATHER THAN A POSITIONAL LIST, and the reason is not taste. This began
 * as five trailing arguments; feeding the toolbar its real page number, page
 * count, zoom, DPI scale and fit mode, plus the hover state, would make eleven,
 * six of them ints and three of them floats. That is the shape of call site where
 * a dpi_scale ends up where a font size belongs and nothing complains --
 * spdf_win_chrome_paint.h says the same thing about SpdfWinChromePaintCtx, for
 * the same reason.
 *
 * Call spdf_win_chrome_model_inputs_init() first. It sets the macOS defaults --
 * both panels visible, nothing hovered, no document -- so a caller that only
 * cares about two fields writes two fields, and a field added here later cannot
 * silently arrive as zero at a caller that predates it. */
typedef struct SpdfWinChromeModelInputs {
    int dark;
    int show_sidebar;
    int show_minimap;
    float sidebar_w; /* points; 0 asks spdf_win_chrome.h for its default (240) */
    float minimap_w; /* points; 0 likewise (126.5) */
    /* Hover, from spdf_win_chrome_input.h's router. -1 is "nothing", which is
     * the value SpdfWinChromeModel documents; these drive the painter's existing
     * hover branches and nothing else. */
    int hot_tab;
    int hot_close;
    /* A tab reorder drag in progress, straight into the model's own two fields
     * (see SpdfWinChromeModel). Both -1 for none, which
     * spdf_win_chrome_model_inputs_init() sets. */
    int drag_tab;
    int drop_slot;
    /* THE TYPEABLE FIELDS. `page_text` is what the reader has typed into the
     * page field, borrowed and NULL when the field is not being edited; `focus`
     * is which field has the keyboard, as spdf_win_text_focus. The FIND field's
     * text does not come through here -- it lives in the process-wide find
     * session with the match count and the marks, which is where the model
     * builder already fetches it from (spdf_win_find_fill_model). */
    const wchar_t* page_text;
    int focus;
    /* The sidebar's list, for the input router: how many rows are showing after
     * filtering, and how far the list is scrolled. See the fields of the same
     * names on SpdfWinChromeModel. */
    int sidebar_row_count;
    float sidebar_scroll_y;
    /* Toolbar readouts. `page_index` is 0-BASED, as everywhere inside this port;
     * the toolbar adds the one. -1 with page_count 0 is "no document". */
    int page_index;
    int page_count;
    float zoom;           /* device pixels per PDF point, from spdf_win_canvas_zoom() */
    float zoom_dpi_scale; /* device pixels per logical pixel, to make a percentage */
    int fit_mode;         /* spdf_win_chrome_fit; the window maps the canvas's own enum */
} SpdfWinChromeModelInputs;

void spdf_win_chrome_model_inputs_init(SpdfWinChromeModelInputs* in);

/* Fills `model` and `store` from `tabs` and `in`. `store` must outlive the paint
 * that reads `model`. Safe with a NULL `tabs`, which yields a model with no tabs
 * -- the state the window is in while the last tab is closing -- and with a NULL
 * `in`, which yields the initialised defaults. */
void spdf_win_chrome_model_build(SpdfWinChromeModel* model, SpdfWinChromeTabStore* store, spdf_win_tabs* tabs,
                                 const SpdfWinChromeModelInputs* in);

/* --- the find query -----------------------------------------------------
 *
 * WHAT THIS REPLACED. The process-wide find session lives in
 * spdf_win_chrome_model.cpp (that file's own comment explains why it is there
 * and not in spdf_win_chrome_find.cpp or spdf_win_search.cpp), and until now the
 * query reached it through two environment variables -- SPDF_FIND_QUERY and
 * SPDF_FIND_REGEX -- because no keyboard input reached that track. Both were
 * documented as temporary at their definitions and both are GONE: this is the
 * setter the toolbar's search field calls, and it is the only way in.
 *
 * UTF-16 IN, because that is what WM_CHAR produces and what the toolbar draws.
 * The conversion to the UTF-8 the engine and the core want happens once, here,
 * rather than at every caller -- and rather than in the model builder, which
 * runs once per frame.
 *
 * STILL LAZY. A process that never types a query still creates no session, no
 * worker thread and no second document handle: spdf_win_find_shared() checks
 * this stored query exactly as it used to check the environment. `query` NULL or
 * empty cancels any live search and clears the toolbar's readout.
 *
 * The stored UTF-16 is what SpdfWinChromeModel::query then borrows, so it must
 * outlive a paint; it is a static buffer inside spdf_win_chrome_model.cpp. */
void spdf_win_find_set_query(const wchar_t* query, int regex);

#ifdef __cplusplus
}
#endif

#endif /* SPDF_WIN_CHROME_MODEL_H */
