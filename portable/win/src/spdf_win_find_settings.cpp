/* The file half of spdf_win_find_settings.h: one read of settings.yaml through
 * the existing state API, once, cached. See the header for what and why. */
#include "spdf_win_find_settings.h"

#include "spdf_win_state.h"

#include <stdlib.h>

namespace {
int g_read; /* 0 not yet, 1 read */
int g_nearest = 1;
} /* namespace */

int spdf_win_find_jumps_to_nearest(void) {
    if (!g_read) {
        /* The unchecked read is the right one here: this caller only populates
         * an in-memory value and never writes the file back, which is exactly
         * the case spdf_win_state.h reserves the plain form for. A locked or
         * unreadable file reads as the default, and nothing is lost by it. */
        char* json = spdf_win_state_read_json(SPDF_WIN_STATE_SETTINGS);
        g_nearest = spdf_win_find_json_bool(json, SPDF_WIN_FIND_SETTING_NEAREST, 1);
        free(json);
        g_read = 1;
    }
    return g_nearest;
}
