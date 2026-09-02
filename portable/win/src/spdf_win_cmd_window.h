#pragma once

/* COMMAND HANDLERS: windows, presentation and full screen, sessions and settings.
 *
 * Header-only, included from spdf_win_chrome_commands.h only, after the app
 * struct, the chrome model and the input types are complete -- the same
 * arrangement as every other *_commands/*_actions header in this port. Owned
 * by the parity track of that name (portable/docs/windows-feature-matrix.md);
 * the other tracks have their own and none of them edits command_perform().
 *
 * Return 1 when the command was consumed, 0 to let it fall through.
 *
 * WHAT IS CLAIMED HERE AND WHY. Presentation (F5) and Full Screen (F11) are
 * this track's own. New Window and Move Tab to New Window are the multi-window
 * half: one process per window, the session file as the hand-over
 * (spdf_win_session_detach_tab). Keep Image Colors is the setting the View
 * menu already ticks from SPDF_RENDER_PRESERVE_IMAGES. Print is claimed too,
 * ahead of command_perform()'s own case, because the scaling choice (Fit /
 * Actual Size / Custom) lives in settings.yaml and the switch next door passes
 * a hard-coded default; claiming it here is how the choice reaches the job and
 * persists without editing that file. Close Other Tabs is claimed for the
 * plainest reason: nothing claimed it, so the menu row did nothing at all.
 */

#include "spdf_win_settings.h"

/* The canvas rect for a client area, with no event to hand: what the launch
 * uses to place the restored view before the window has ever painted. Here
 * because chrome_layout_for_input() is defined in spdf_win_chrome_actions.h
 * and only spdf_win_main.cpp's main() calls this, after every include. */
static void app_canvas_viewport(app* a, unsigned client_w, unsigned client_h, float dpi_scale, unsigned* out_w,
                                unsigned* out_h) {
    spdf_win_input in;
    SpdfWinChromeModel model;
    SpdfWinChromeLayout l;
    memset(&in, 0, sizeof(in));
    in.view_px_w = client_w;
    in.view_px_h = client_h;
    in.dpi_scale = dpi_scale;
    chrome_layout_for_input(a, &in, &model, &l);
    if (out_w) *out_w = (unsigned)l.canvas.w;
    if (out_h) *out_h = (unsigned)l.canvas.h;
}

/* Settings > Keep Image Colors in Dark Theme. The setting is written whatever
 * the theme (the mac ticks it whatever the theme too); the render flag changes
 * only while dark, where it means anything, and the canvas is rebuilt over the
 * same document with the reader's place kept (chrome_rebuild_canvas). */
static int cmd_window_toggle_keep_image_colors(app* a) {
    spdf_win_settings* s = spdf_win_settings_shared();
    s->dark_theme_preserves_images = !s->dark_theme_preserves_images;
    spdf_win_settings_commit();
    if (!(a->render_flags & SPDF_RENDER_DARK_THEME)) {
        /* Not dark: nothing on screen changes, but the flag the menu ticks does. */
        if (s->dark_theme_preserves_images) a->render_flags |= SPDF_RENDER_PRESERVE_IMAGES;
        else a->render_flags &= ~(unsigned)SPDF_RENDER_PRESERVE_IMAGES;
        return 1;
    }
    if (s->dark_theme_preserves_images) a->render_flags |= SPDF_RENDER_PRESERVE_IMAGES;
    else a->render_flags &= ~(unsigned)SPDF_RENDER_PRESERVE_IMAGES;
    return chrome_rebuild_canvas(a);
}

/* File > Print..., with the scaling choice. Loaded from settings.yaml, shown as
 * a page in the print dialog (spdf_win_print_scaling.h), and written back when
 * the reader printed -- which is when a choice was made. */
static int cmd_window_print(app* a) {
    SpdfWinDocAction act;
    spdf_win_settings* s = spdf_win_settings_shared();
    spdf_win_print_choice choice;
    char err[512] = {0};
    spdf_win_print_status status;
    if (!doc_action_for(a, &act)) return 0;
    choice.mode = (spdf_win_print_scaling_mode)s->print_scaling_mode;
    choice.custom_scale = s->print_custom_scale;
    status = spdf_win_print_document_ex(act.hwnd, act.doc, act.path, &choice, err, sizeof(err));
    if (status == SPDF_WIN_PRINT_OK &&
        ((int)choice.mode != s->print_scaling_mode || choice.custom_scale != s->print_custom_scale)) {
        s->print_scaling_mode = (int)choice.mode;
        s->print_custom_scale = choice.custom_scale;
        spdf_win_settings_commit();
    }
    doc_action_report(a, err);
    return 1;
}

/* File > Close Other Tabs. The menu row existed with no handler anywhere, so
 * the item was drawn, enabled, and inert -- the reader's only way to clear a
 * crowded strip was N presses of Ctrl+W, each of which also moves the
 * selection.
 *
 * DESCENDING, COMPARING AGAINST THE ORIGINAL INDEX. spdf_win_tabs_close()
 * shifts every index ABOVE the closed one down by one and leaves the ones below
 * it alone, so a descending walk never revisits a tab that has moved. `keep`
 * itself shifts down as tabs to its left go, but it is only ever compared
 * against indices that are already known to be other tabs: those above it were
 * visited before any shift could reach it, and those below it are below it
 * whatever it has shifted to. The model half of that arithmetic is pinned in
 * portable/win/tests/tabs_test.c (test_close_others_keeps_the_selected_tab).
 *
 * NOT ONE chrome_close_tab() PER TAB. That function rebuilds the canvas and
 * writes session.yaml on every call, so routing twenty tabs through it would
 * throw the kept document's page cache away twenty times and hit the disk
 * twenty times to reach the same end state. The two things it does that MUST
 * happen per tab -- note the path for Reopen Last Closed Tab, and release the
 * watch and any shadow copy while the model still has the path -- are done per
 * tab here; the two that need happen once are done once, after.
 *
 * The kept tab's canvas is not rebuilt at all: it is the same document at the
 * same place, and only the strip's geometry changed. */
static int cmd_window_close_other_tabs(app* a) {
    int keep, i, closed = 0;
    if (!a->tabs) return 0;
    keep = spdf_win_tabs_selected_index(a->tabs);
    if (keep < 0) return 0;
    for (i = spdf_win_tabs_count(a->tabs) - 1; i >= 0; --i) {
        if (i == keep) continue;
        spdf_win_recents_note_closed(spdf_win_tabs_path(a->tabs, i));
        spdf_win_tabs_open_forget(a->tabs, i);
        spdf_win_tabs_close(a->tabs, i, 0);
        closed = 1;
    }
    if (!closed) return 0; /* one tab, or none: nothing to do and nothing to redraw */
    app_session_save(a);
    return 1;
}

static int spdf_win_cmd_window_perform(app* a, int command, const spdf_win_input* in) {
    (void)in;
    switch (command) {
        case SPDF_WIN_CMD_PRESENTATION:
            /* macOS refuses with no document (:13433 hasActiveDocument); a
             * presentation of nothing is a black screen with no way to know why. */
            if (!a->presentation && !a->canvas) return 0;
            return app_set_presentation(a, !a->presentation);
        case SPDF_WIN_CMD_FULLSCREEN: return app_toggle_fullscreen(a);
        case SPDF_WIN_CMD_NEW_WINDOW: return app_spawn_window(a, NULL);
        case SPDF_WIN_CMD_MOVE_TAB_TO_WINDOW:
            return a->tabs ? chrome_detach_tab(a, spdf_win_tabs_selected_index(a->tabs)) : 0;
        case SPDF_WIN_CMD_CLOSE_OTHER_TABS: return cmd_window_close_other_tabs(a);
        case SPDF_WIN_CMD_TOGGLE_KEEP_IMAGE_COLORS: return cmd_window_toggle_keep_image_colors(a);
        case SPDF_WIN_CMD_PRINT: return cmd_window_print(a);
        default: return 0;
    }
}
