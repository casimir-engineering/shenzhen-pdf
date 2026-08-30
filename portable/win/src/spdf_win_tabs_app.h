/* spdf_win_tabs_app.h — the four lines of glue between the tab/session model
 * and the app's one canvas.
 *
 * Header-only and included by exactly one translation unit
 * (spdf_win_main.cpp). It is a header rather than a .cpp for two reasons:
 * spdf_win_main.cpp is at its line cap and this work does not belong inside it,
 * and a new .cpp would have to be added to the app's source list, which lives
 * in another track's file. Nothing here is part of the port's public surface;
 * silent_failure_support.h and spdf_win_session_json.h are the same
 * arrangement.
 *
 * This is the ONLY place where the model layer and the Win32/Direct2D layer
 * meet. spdf_win_tabs.h and spdf_win_session.h own no Win32 and no Direct2D on
 * purpose, so that the close policy and the session schema can be tested
 * headlessly; that separation only holds if the glue lives outside them, which
 * is here.
 *
 * The shape it imposes on the frontend:
 *
 *   - The MODEL owns documents. spdf_win_tabs opens one through the hook below
 *     the first time a tab is shown, and closes it when the tab closes.
 *   - main.cpp owns ONE canvas, belonging to whichever tab is selected.
 *     Switching tabs destroys it and builds a new one over the new tab's
 *     document. A canvas per tab would be nicer to switch to and would hold
 *     every tab's page cache resident; one canvas is the version that keeps a
 *     restored fifteen-tab session honest about memory as well as about
 *     startup time.
 *   - Restoring a session costs paths and view state and NOTHING else. The
 *     document behind a tab is opened the first time that tab is shown, which
 *     for every tab but one is never.
 */
#ifndef SPDF_WIN_TABS_APP_H
#define SPDF_WIN_TABS_APP_H

#include "spdf_win_canvas.h"
#include "spdf_win_session.h"

/* The model's document hooks. The core allows one spdf_document per thread and
 * the canvas takes its own path for the render workers, so there is nothing to
 * share here: open and close, and that is all. */
static void* tabs_app_open_document(void* user, const char* path, char* err, size_t err_len) {
    (void)user;
    return spdf_open(path, err, err_len);
}

static void tabs_app_close_document(void* user, void* document) {
    (void)user;
    if (document) spdf_close((spdf_document*)document);
}

/* Write the reader's current place back into the selected tab, so a tab switch
 * and the session file both remember it. */
static void spdf_win_tabs_app_remember(spdf_win_tabs* tabs, spdf_win_canvas* canvas) {
    spdf_win_tab_view* view = spdf_win_tabs_view(tabs, spdf_win_tabs_selected_index(tabs));
    if (!view || !canvas) return;
    view->page = spdf_win_canvas_current_page(canvas);
    view->zoom = (double)spdf_win_canvas_zoom(canvas);
    view->custom_zoom = view->zoom;
    view->fit_mode = spdf_win_canvas_zoom_mode(canvas) == SPDF_WIN_ZOOM_FIT_WIDTH ? SPDF_WIN_TAB_FIT_WIDTH
                                                                                  : SPDF_WIN_TAB_FIT_CUSTOM;
    view->scroll_x = (double)spdf_win_canvas_scroll_x(canvas);
    view->scroll_y = (double)spdf_win_canvas_scroll_y(canvas);
    view->has_scroll_origin = 1;
}

/* Point the canvas at the selected tab, materialising that tab's document if
 * this is the first time it has been shown. Returns non-zero when there is
 * something to draw. */
static int spdf_win_tabs_app_show(spdf_win_tabs* tabs, spdf_win_canvas** canvas, unsigned render_flags,
                                  int* pending_page) {
    int index = spdf_win_tabs_selected_index(tabs);
    char err[256] = {0};
    spdf_document* doc = index < 0 ? NULL : (spdf_document*)spdf_win_tabs_document(tabs, index, err, sizeof(err));

    spdf_win_canvas_destroy(*canvas);
    *canvas = doc ? spdf_win_canvas_create(doc, spdf_win_tabs_path(tabs, index), render_flags, err, sizeof(err))
                  : NULL;
    /* The restored page is applied on the first paint, not here: the canvas
     * cannot place a page until it knows the viewport. */
    *pending_page = *canvas ? spdf_win_tabs_view(tabs, index)->page : -1;
    return *canvas != NULL;
}

/* Build the tab model for this window: last session's tabs as metadata, plus
 * the document the app was launched with, selected. */
static spdf_win_tabs* spdf_win_tabs_app_start(const char* utf8_path, char* window_id, size_t id_len) {
    spdf_win_tabs* tabs = spdf_win_tabs_create();
    int index;
    if (!tabs) return NULL;
    spdf_win_tabs_set_document_hooks(tabs, tabs_app_open_document, tabs_app_close_document, NULL);
    /* An UNREADABLE session leaves the model empty AND must not be saved over;
     * spdf_win_session_save() refuses on its own, so there is nothing to do
     * here but carry on with the launch document. */
    if (spdf_win_session_restore(tabs, NULL, window_id, id_len) != SPDF_WIN_SESSION_RESTORED)
        spdf_win_session_new_window_id(window_id, id_len);
    index = utf8_path ? spdf_win_tabs_index_of_path(tabs, utf8_path) : -1;
    if (index < 0 && utf8_path) index = spdf_win_tabs_append(tabs, utf8_path, NULL);
    if (index < 0) index = spdf_win_tabs_selected_index(tabs);
    if (index >= 0) spdf_win_tabs_select_deferred(tabs, index);
    return tabs;
}

static void spdf_win_tabs_app_finish(spdf_win_tabs* tabs, spdf_win_canvas* canvas, const char* window_id) {
    if (!tabs) return;
    spdf_win_tabs_app_remember(tabs, canvas);
    spdf_win_session_save(tabs, window_id);
    spdf_win_canvas_destroy(canvas);
    spdf_win_tabs_destroy(tabs);
}

#endif /* SPDF_WIN_TABS_APP_H */
