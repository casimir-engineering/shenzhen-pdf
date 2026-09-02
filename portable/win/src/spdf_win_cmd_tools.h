#pragma once

/* COMMAND HANDLERS: power tools: OCR and translation.
 *
 * Header-only, included from spdf_win_chrome_commands.h only, after the app
 * struct, the chrome model and the input types are complete -- the same
 * arrangement as every other *_commands/*_actions header in this port. Owned
 * by the parity track of that name (portable/docs/windows-feature-matrix.md);
 * the other tracks have their own and none of them edits command_perform().
 *
 * Return 1 when the command was consumed, 0 to let it fall through. */

static int spdf_win_cmd_tools_perform(app* a, int command, const spdf_win_input* in) {
    (void)a;
    (void)command;
    (void)in;
    return 0;
}
