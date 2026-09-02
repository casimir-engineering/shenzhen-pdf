#pragma once

/* spdf_win_watch_app.h -- the app's half of the file watcher: what a CHANGED or
 * a MISSING report does to a tab, and the launch sweep of orphaned copies.
 *
 * Header-only and included from spdf_win_main.cpp right after
 * spdf_win_session_app.h, whose show_selected_tab() it calls; the other half --
 * the hook that registers the watches -- is spdf_win_tabs_open.h, included
 * before `struct app`. Same arrangement as every glue header beside it; not
 * part of the port's public surface.
 *
 * WHY A RELOAD IS A TAB RE-SHOW. The canvas holds one document and the render
 * workers hold their own handles to its path (spdf_win_tabs_app.h), so a file
 * that changed on disk means every handle must move to the new bytes together.
 * show_selected_tab() is exactly that: the canvas (and its workers) go, the tab
 * model reopens the document through the open hook -- which for a read-only
 * source is where the shadow copy is refreshed -- and the new canvas is placed
 * at the page, zoom and exact offset remember() wrote back. File > Reload
 * (spdf_win_cmd_docs.h docs_reload) is the same sequence by hand. An
 * unselected tab is simply released: the next show reopens it.
 *
 * The callback runs on the UI thread, from the watcher's own message-only
 * window, so it is outside the input path that normally repaints -- hence the
 * explicit invalidate.
 */

#include "spdf_win_chrome_content.h" /* the panels reload their document */
#include "spdf_win_chrome_find.h"    /* the results describe pages that changed shape */

static void app_watch_repaint(app* a) {
    if (a->window) InvalidateRect((HWND)spdf_win_window_native_handle(a->window), NULL, FALSE);
}

static void app_on_watch(void* user, const char* path, int event) {
    app* a = (app*)user;
    int index = a && a->tabs ? spdf_win_tabs_index_of_path(a->tabs, path) : -1;
    spdf_win_tab_view* view = index < 0 ? NULL : spdf_win_tabs_view(a->tabs, index);
    if (!view) return;

    if (event == SPDF_WIN_WATCH_MISSING) {
        /* Gone for the whole grace period: the strip colours the tab red and
         * the document stays readable from the handles already open. A later
         * reappearance arrives as CHANGED and clears this. */
        view->missing = 1;
        app_watch_repaint(a);
        return;
    }
    if (event != SPDF_WIN_WATCH_CHANGED) return;
    view->missing = 0;
    if (index == spdf_win_tabs_selected_index(a->tabs)) {
        spdf_win_tabs_app_remember(a->tabs, a->canvas);
        spdf_win_canvas_destroy(a->canvas);
        a->canvas = NULL;
        spdf_win_tabs_release_document(a->tabs, index);
        show_selected_tab(a);
        /* The search's rects and the panels' handles describe the old file;
         * both rebuild on the next paint (the same two calls Rotate makes). */
        spdf_win_find_restart(spdf_win_find_shared());
        spdf_win_chrome_content_set_document(NULL, 0);
    } else {
        spdf_win_tabs_release_document(a->tabs, index);
    }
    app_watch_repaint(a);
}

/* THE LAUNCH SWEEP (the mac's deferred one): every shadow copy no live tab
 * renders from and nobody touched in the last minute is deleted.
 *
 * ON ITS OWN ONE-SHOT TIMER, ten seconds after the window is shown
 * (SPDF_WIN_WATCH_SWEEP_MS, armed in spdf_win_main.cpp). It used to ride the
 * first SESSION tick, which is thirty seconds, and that had it both ways: a
 * reader who opened a read-only document and closed the app inside half a
 * minute -- the commonest way to look at one file -- never swept at all, so
 * the copies piled up in %APPDATA%\ShenzhenPDF\ReadOnlyCopies indefinitely.
 * Ten seconds is far off the launch path (the first page lands at ~150 ms,
 * portable/docs/windows-launch-performance.md) and every restored tab has long
 * since had its binding primed, which is the one ordering this depends on.
 *
 * Still guarded by `swept`: the one-shot cannot fire twice, but the guard also
 * covers the session tick's old route if anyone re-adds it, and costs a
 * branch. */
#define SPDF_WIN_WATCH_SWEEP_MS 10000

static void app_watch_sweep_once(void* user) {
    app* a = (app*)user;
    static int swept;
    const char* refs[SPDF_WIN_TABS_MAX];
    int i, n = 0, count;
    if (!a || swept) return;
    swept = 1;
    count = a->tabs ? spdf_win_tabs_count(a->tabs) : 0;
    for (i = 0; i < count && n < SPDF_WIN_TABS_MAX; ++i) {
        const spdf_win_tab_view* v = spdf_win_tabs_view_const(a->tabs, i);
        if (v && v->read_only && v->working_path[0]) refs[n++] = v->working_path;
    }
    spdf_win_watcher_sweep_orphans(refs, n);
}
