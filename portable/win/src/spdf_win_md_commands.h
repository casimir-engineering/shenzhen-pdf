/* spdf_win_md_commands.h -- what the A-/A+ pill and the image cache do to the
 * window: the Markdown commands, in the shape spdf_win_chrome_commands.h's
 * switch expects.
 *
 * Header-only and included by spdf_win_main.cpp AFTER `struct app` and
 * spdf_win_chrome_actions.h (it calls show_selected_tab and
 * spdf_win_tabs_app_remember) and BEFORE spdf_win_chrome_commands.h, which
 * dispatches to it. Same arrangement as the other chrome_*.h headers beside
 * it; not part of the port's public surface.
 *
 * WHY A TEXT-SIZE CHANGE IS A TAB RE-SHOW. The size is the em MuPDF laid the
 * document out at, so changing it means a new layout, and every handle open on
 * the document -- the canvas, its render workers, the thumbnail strip -- must
 * move to the new one together or their page numbers disagree.
 * show_selected_tab() is exactly that already: it destroys the canvas (and
 * with it the worker threads and their per-thread handles), reopens the tab's
 * document through the tabs hook (spdf_win_md_open_any, which reads the new
 * scale), and builds a fresh canvas that puts the reader back on the page it
 * was on. The reader's page is written back first so the reopened document
 * lands where they were, as a tab switch does. No new machinery, and a PDF tab
 * is untouched: the commands are inert on it.
 *
 * REMOTE IMAGES ARRIVE THE SAME WAY. When the background fetch has filled the
 * cache, its window message re-shows the tab; the converter now finds the
 * files and the placeholders become pictures. spdf_win_md_command_images_arrived
 * is that handler, and spdf_win_md_command_after_open starts the fetch after a
 * Markdown tab is shown -- both one call each from main.cpp.
 */
#ifndef SPDF_WIN_MD_COMMANDS_H
#define SPDF_WIN_MD_COMMANDS_H

#include "spdf_win_md.h"
#include "spdf_win_md_images.h"

/* WM_APP + 0x4D44 ("MD"): "remote images landed in the cache". Posted by the
 * fetch thread to the main window; main.cpp routes it to
 * spdf_win_md_command_images_arrived. */
#define SPDF_WIN_MD_WM_IMAGES_ARRIVED (WM_APP + 0x4D44)

/* Is the selected tab a Markdown document? The commands below are no-ops on
 * anything else, so a PDF reader never pays for them. */
static int spdf_win_md_selected_tab_is_markdown(app* a) {
    int index = a->tabs ? spdf_win_tabs_selected_index(a->tabs) : -1;
    const char* path = index >= 0 ? spdf_win_tabs_path(a->tabs, index) : a->path;
    return spdf_path_is_markdown(path);
}

/* Re-lay the selected Markdown tab out at the current options, keeping the
 * reader's page. Returns 1 when something was redrawn. */
static int spdf_win_md_command_reopen(app* a) {
    if (!a->canvas || !spdf_win_md_selected_tab_is_markdown(a)) return 0;
    spdf_win_tabs_app_remember(a->tabs, a->canvas);
    return show_selected_tab(a);
}

/* A- (direction -1) / A+ (+1). Persists the new size, then re-shows the tab.
 * At a limit nothing changes and nothing is redrawn. */
static int spdf_win_md_command_text_step(app* a, int direction) {
    if (!spdf_win_md_selected_tab_is_markdown(a)) return 0;
    if (!spdf_win_md_text_scale_step(direction)) return 0;
    spdf_win_md_save_settings();
    return spdf_win_md_command_reopen(a);
}

/* Call once a tab has been shown: if the open recorded https images that were
 * not in the cache, fetch them in the background; the completion message
 * re-shows the tab. Harmless on a PDF tab (nothing is pending). */
static void spdf_win_md_command_after_open(app* a, HWND window) {
    if (!spdf_win_md_selected_tab_is_markdown(a)) return;
    spdf_win_md_images_fetch_pending(window, SPDF_WIN_MD_WM_IMAGES_ARRIVED);
}

/* The SPDF_WIN_MD_WM_IMAGES_ARRIVED handler. */
static int spdf_win_md_command_images_arrived(app* a) {
    return spdf_win_md_command_reopen(a);
}

#endif /* SPDF_WIN_MD_COMMANDS_H */
