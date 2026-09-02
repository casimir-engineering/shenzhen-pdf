#pragma once

/* COMMAND HANDLERS: the shell: updater, default reader, about and shortcuts.
 *
 * Header-only, included from spdf_win_chrome_commands.h only, after the app
 * struct, the chrome model and the input types are complete -- the same
 * arrangement as every other *_commands/*_actions header in this port. Owned
 * by the parity track of that name (portable/docs/windows-feature-matrix.md);
 * the other tracks have their own and none of them edits command_perform().
 *
 * Return 1 when the command was consumed, 0 to let it fall through.
 *
 * WHAT EACH ONE DOES, and where the decision lives:
 *   ABOUT              spdf_win_about.h        version/build/core from the one
 *                                              header the .rc also reads
 *   SHORTCUTS (F1)     spdf_win_shortcuts.h    generated from spdf_win_menu_table()
 *   SET_DEFAULT_READER spdf_win_assoc.h        HKCU registration + the Settings
 *                                              page; the ONLY registry writer
 *                                              here, and only on this command
 *   CHECK_UPDATES      spdf_win_updater.h      the check now, result shown
 *
 * All four are modal against the main window and none of them touches the
 * document, so they need no chrome layout and no scene invalidation: the
 * window repaints itself when the dialog closes. */

#include "spdf_win_about.h"
#include "spdf_win_assoc.h"
#include "spdf_win_shortcuts.h"
#include "spdf_win_updater.h"

static int spdf_win_cmd_shell_perform(app* a, int command, const spdf_win_input* in) {
    void* hwnd = a && a->window ? spdf_win_window_native_handle(a->window) : NULL;
    int dark = a && (a->render_flags & SPDF_RENDER_DARK_THEME) != 0;
    (void)in;
    switch (command) {
        case SPDF_WIN_CMD_ABOUT: spdf_win_about_show(hwnd, dark); return 1;
        case SPDF_WIN_CMD_SHORTCUTS: spdf_win_shortcuts_show(hwnd, dark); return 1;
        case SPDF_WIN_CMD_SET_DEFAULT_READER: spdf_win_assoc_make_default(hwnd); return 1;
        case SPDF_WIN_CMD_CHECK_UPDATES: spdf_win_updater_check_interactive(hwnd); return 1;
        default: return 0;
    }
}
