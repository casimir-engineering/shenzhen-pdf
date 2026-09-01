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

/* Fills `model` and `store` from `tabs`. `store` must outlive the paint that
 * reads `model`. Safe with a NULL `tabs`, which yields a model with no tabs --
 * the state the window is in while the last tab is closing. */
void spdf_win_chrome_model_build(SpdfWinChromeModel* model, SpdfWinChromeTabStore* store, spdf_win_tabs* tabs, int dark,
                                 int show_sidebar, int show_minimap, float sidebar_w, float minimap_w);

#ifdef __cplusplus
}
#endif

#endif /* SPDF_WIN_CHROME_MODEL_H */
