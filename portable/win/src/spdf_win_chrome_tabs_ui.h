#pragma once

/* spdf_win_chrome_tabs_ui.h -- the TAB STRIP's commands: select, close, open,
 * the overflow menu and drag-to-reorder.
 *
 * Split out of spdf_win_chrome_actions.h, which had grown past the 500-line cap
 * (tools/file-size-limits.md) as the strip's three inert controls became live.
 * The seam is a real one rather than a convenience: everything here changes the
 * SET OF OPEN DOCUMENTS or their order, while what is left next door changes the
 * one document the reader is looking at. They meet at exactly two functions --
 * show_selected_tab() and spdf_win_tabs_app_remember(), both of which belong to
 * spdf_win_main.cpp and spdf_win_tabs_app.h respectively.
 *
 * Header-only and included from spdf_win_main.cpp AFTER `struct app` and
 * spdf_win_chrome_scene.h, and BEFORE spdf_win_chrome_actions.h, which calls
 * every function here from chrome_perform(). Same arrangement as
 * spdf_win_tabs_app.h and spdf_win_headless_viewport.h beside it; not part of
 * the port's public surface.
 */

/* The Open dialog and the tab overflow popup. Both are MODAL Win32 calls made
 * from a click, which is why they are reachable from here and not from
 * spdf_win_chrome_input.h: deciding what a click means must stay pure, and
 * running a nested message loop is the opposite of pure. */
#include "spdf_win_menu.h"

/* Close a tab from the strip. prefer_most_recent_active is 0, matching
 * ShenzhenPDFMac.mm:9115 -- the close box and Ctrl+W both ask for the
 * DETERMINISTIC ADJACENT survivor, and only detaching a tab into its own window
 * asks for the most recently active one (:9300). Getting that argument backwards
 * would make the close box feel like a different app from Ctrl+W. */
static int chrome_close_tab(app* a, int index) {
    if (!a->tabs || index < 0) return 0;
    if (index == spdf_win_tabs_selected_index(a->tabs)) spdf_win_tabs_app_remember(a->tabs, a->canvas);
    spdf_win_tabs_close(a->tabs, index, 0);
    if (spdf_win_tabs_count(a->tabs) == 0) {
        PostQuitMessage(0);
        return 1;
    }
    return show_selected_tab(a);
}

static int chrome_select_tab(app* a, int index) {
    if (!a->tabs || index < 0 || index == spdf_win_tabs_selected_index(a->tabs)) return 0;
    spdf_win_tabs_app_remember(a->tabs, a->canvas);
    spdf_win_tabs_select_deferred(a->tabs, index);
    return show_selected_tab(a);
}

/* OPEN A DOCUMENT IN A NEW TAB. A path already open selects its tab instead of
 * opening a second one, which is spdf_win_tabs_app_start()'s own rule for the
 * launch document and the behaviour a reader expects from re-opening a file.
 *
 * The reader's place in the tab being left is written back FIRST, exactly as
 * every other tab switch in this file does, or returning to it lands on the page
 * it was opened at rather than the page it was left at. */
static int chrome_open_wide(app* a, const wchar_t* wpath) {
    char* utf8;
    int index;
    if (!a->tabs || !wpath || !wpath[0]) return 0;
    utf8 = utf8_from_wide(wpath);
    if (!utf8) return 0;
    index = spdf_win_tabs_index_of_path(a->tabs, utf8);
    if (index < 0) index = spdf_win_tabs_append(a->tabs, utf8, NULL);
    free(utf8);
    if (index < 0) return 0; /* at SPDF_WIN_TABS_MAX, or out of memory */
    if (index == spdf_win_tabs_selected_index(a->tabs)) return 0;
    spdf_win_tabs_app_remember(a->tabs, a->canvas);
    spdf_win_tabs_select_deferred(a->tabs, index);
    return show_selected_tab(a);
}

/* GIVE THE MOUSE BACK BEFORE OPENING ANYTHING MODAL.
 *
 * Both of the modal calls below can be reached from a WM_LBUTTONDOWN -- the
 * strip's `+` and its `...` -- and at that moment spdf_win_window.cpp is holding
 * the mouse CAPTURE, because a press might have been the start of a drag.
 * TrackPopupMenu will not track correctly against a live capture, and a file
 * dialog opened under one leaves the press hanging: the button comes up over
 * another window, so the WM_LBUTTONUP that would have ended the gesture never
 * arrives here.
 *
 * ReleaseCapture() answers both. It synchronously sends WM_CAPTURECHANGED, which
 * the window turns into a CANCELLED press (spdf_win_window.h's SPDF_WIN_CB_NONE
 * contract) -- the exact path an Alt+Tab or a system modal already takes, so the
 * drag state is cleared by the code that exists to clear it rather than by a
 * second copy here. */
static void chrome_release_capture(app* a) {
    HWND hwnd = a->window ? (HWND)spdf_win_window_native_handle(a->window) : NULL;
    if (hwnd && GetCapture() == hwnd) ReleaseCapture();
}

static int chrome_open_dialog(app* a) {
    wchar_t path[1024];
    if (!a->window) return 0;
    chrome_release_capture(a);
    if (!spdf_win_menu_open_dialog(spdf_win_window_native_handle(a->window), path,
                                   (int)(sizeof(path) / sizeof(path[0]))))
        return 0;
    return chrome_open_wide(a, path);
}

/* The strip's `...`. Every tab, not only the hidden ones: macOS's overflow list
 * is the whole document list, and a menu that showed only what is off-screen
 * would change contents as the window is resized.
 *
 * The titles are the ones the LAST PAINT converted (a->chrome_tabs), so the menu
 * says exactly what the strip says and no conversion happens on the click. */
static int chrome_tab_overflow(app* a, const SpdfWinChromeLayout* l) {
    const wchar_t* titles[SPDF_WIN_CHROME_MAX_TABS];
    SpdfWinTabRect r;
    POINT pt;
    void* hwnd = a->window ? spdf_win_window_native_handle(a->window) : NULL;
    float s = l->dpi_scale > 0.0f ? l->dpi_scale : 1.0f;
    int i, count = a->chrome_tabs.count, chosen;

    if (!hwnd || count <= 0) return 0;
    chrome_release_capture(a); /* see chrome_release_capture: a popup needs the mouse */
    for (i = 0; i < count; ++i) titles[i] = a->chrome_tabs.titles[i];
    /* Under the button's bottom-left corner, in the strip's own point space
     * converted back the way the painter converts it -- so the menu hangs off
     * the control that opened it at every DPI. */
    r = spdf_win_tabstrip_overflow_rect(l->tabstrip.w / s, count);
    pt.x = (LONG)(l->tabstrip.x + (float)r.x * s);
    pt.y = (LONG)(l->tabstrip.y + (float)(r.y + r.h) * s);
    ClientToScreen((HWND)hwnd, &pt);

    chosen = spdf_win_menu_tab_overflow(hwnd, titles, count, spdf_win_tabs_selected_index(a->tabs), pt.x, pt.y);
    if (chosen < 0) return 0;
    return chrome_select_tab(a, chosen);
}

/* --- TAB DRAG-TO-REORDER ------------------------------------------------
 *
 * BOTH HALVES ARE TRANSCRIBED, NOT DERIVED. spdf_win_tabstrip_drop_slot() is
 * macOS's spdf_tab_strip_drop_slot_for_x and spdf_win_tabstrip_move_index() is
 * its spdf_tab_strip_same_window_move_index -- including the part that is easy
 * to get wrong and hard to notice: BOTH gaps adjacent to the dragged tab
 * collapse to a no-op, because the slot indices past the source shift left by
 * one once the tab is lifted out. portable/docs/windows-port-plan.md 2.3's reuse
 * rule is the reason nothing here recomputes either: "re-deriving it would mean
 * re-deriving its bug fixes too".
 *
 * A slot is an insertion position among the VISIBLE tabs, so it is offset by the
 * visible window's start before it means anything to the tab model. */
static int chrome_drop_slot_at(const SpdfWinChromeLayout* l, const SpdfWinChromeModel* m, float client_x) {
    float s = l->dpi_scale > 0.0f ? l->dpi_scale : 1.0f;
    if (spdf_win_chrome_rect_empty(l->tabstrip)) return -1;
    return spdf_win_tabstrip_drop_slot(l->tabstrip.w / s, m->tab_count, m->selected_tab, (client_x - l->tabstrip.x) / s);
}

static int chrome_drop_tab(app* a, const SpdfWinChromeLayout* l, const SpdfWinChromeModel* m) {
    int start = 0, visible = 0, to;
    float s = l->dpi_scale > 0.0f ? l->dpi_scale : 1.0f;
    if (!a->tabs || a->drag_tab < 0 || a->drop_slot < 0) return 0;
    spdf_win_tabstrip_visible_range(l->tabstrip.w / s, m->tab_count, m->selected_tab, &start, &visible);
    to = spdf_win_tabstrip_move_index(start + a->drop_slot, a->drag_tab, m->tab_count);
    if (to == a->drag_tab) return 0;
    /* The tab model moves the TAB and lets the selection follow it, which is
     * what keeps the document the reader is looking at on screen through a
     * reorder (spdf_win_tabs.h: "The selection follows the TAB, not the
     * index"). */
    return spdf_win_tabs_move(a->tabs, a->drag_tab, to);
}
