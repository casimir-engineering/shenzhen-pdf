#pragma once

/* spdf_win_chrome_field_ui.h -- the toolbar's find group, which field has the
 * keyboard, and the sidebar's chapter rows.
 *
 * Split out of spdf_win_chrome_actions.h for the reason
 * tools/file-size-limits.md gives, and along the seam that appeared when the
 * chrome became typeable: the file next door decides what a point MEANS and
 * performs the commands that change the DOCUMENT, and this one holds the four
 * things that change what the CHROME is showing about it -- where the keyboard
 * is, what the query is, which match is current, and which chapter was clicked.
 *
 * Header-only and included from spdf_win_main.cpp after `struct app` and
 * spdf_win_chrome_scene.h and BEFORE spdf_win_chrome_actions.h, whose
 * chrome_perform() calls every function here. Same arrangement as
 * spdf_win_chrome_tabs_ui.h and spdf_win_chrome_canvas_ui.h beside it.
 */

/* GIVE A FIELD THE KEYBOARD. Returns 1 when the focus moved, which is a repaint
 * (the focus ring) even though nothing else changed.
 *
 * Taking focus SEEDS the page field from the current page, so a reader who
 * clicks it and types Return without touching anything else goes nowhere rather
 * than to page 0 -- and so the number they are about to overwrite is selected in
 * the ordinary sense of "the field shows what it is replacing". */
static int chrome_focus(app* a, int focus) {
    if (a->focus == focus) return 0;
    a->focus = focus;
    if (focus == SPDF_WIN_FOCUS_PAGE) {
        int page = a->canvas ? spdf_win_canvas_current_page(a->canvas) + 1 : 1;
        _snwprintf_s(a->page_text, _TRUNCATE, L"%d", page);
        a->page_caret = (int)wcslen(a->page_text);
    }
    return 1;
}

/* Hand the find bridge whatever is in the field now. One place, so the two
 * callers that change the query (a keystroke and the regex toggle) cannot
 * disagree about which of the two arguments is stale. */
static void chrome_find_push(app* a) {
    spdf_win_find_set_query(a->find_text[0] ? a->find_text : NULL, a->find_regex);
}

/* Step to the next/previous match and put the reader on its page.
 *
 * SCROLL_TO_PAGE, NOT TO THE RECT. spdf_win_find_current_target() reports the
 * match's rect as well as its page, and the canvas has no scroll-to-rect: it can
 * place a PAGE. So a match lands the reader on the right page with the highlight
 * visible, which is the whole of what is reachable today. A scroll that centres
 * the match itself is one canvas function away and is listed in this change's
 * report. */
static int chrome_find_step(app* a, int delta) {
    SpdfWinFindSession* s = spdf_win_find_shared();
    int page = -1;
    spdf_rect rect;
    if (!s || !a->canvas) return 0;
    if (spdf_win_find_step(s, delta) < 0) return 0;
    if (!spdf_win_find_current_target(s, &page, &rect) || page < 0) return 1;
    spdf_win_canvas_scroll_to_page(a->canvas, page);
    return 1;
}

/* A click on a chapter row. The row's page comes from the content provider,
 * which the router deliberately cannot reach -- resolving it on a mouse MOVE
 * would put an outline load on the pointer's path. On a CLICK it is already
 * warm, because the paint that drew the row resolved it. */
static int chrome_sidebar_row(app* a, int row) {
    const SpdfWinChromePanelsContent* content = spdf_win_chrome_content_current();
    const SpdfWinSidebarContent* sb = content ? content->sidebar : NULL;
    if (!a->canvas || !sb || !sb->rows || row < 0 || row >= sb->row_count) return 0;
    /* A row whose destination did not resolve (page_index < 0: a /Fit-less
     * dest, a missing target, an external URL) is drawn greyed and does
     * nothing, which is what macOS's own `page >= 0` branch does. */
    if (sb->rows[row].page_index < 0) return 0;
    return spdf_win_canvas_scroll_to_page(a->canvas, sb->rows[row].page_index);
}
