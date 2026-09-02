/* find_settings_test.c -- the one JSON scanner the search track owns,
 * spdf_win_find_json_bool (spdf_win_find_settings.h), driven with the text
 * spdf_win_state_read_json hands back for settings.yaml and with the shapes
 * that could fool it: the key inside a string value, a key that is a prefix of
 * another, whitespace around the colon, a non-boolean value, no file at all.
 *
 * Header-only subject: no state directory, no registry, no file. Judged by exit
 * code.
 */
#include <stdio.h>
#include <string.h>

#include "spdf_win_find_settings.h"

static int failures;

static void expect(int condition, const char* what) {
    if (!condition) {
        printf("FAIL %s\n", what);
        failures++;
    }
}

int main(void) {
    const char* k = SPDF_WIN_FIND_SETTING_NEAREST;

    /* The shape the YAML->JSON codec produces (spdf_state.c writes it the same
     * way): one member per line, two-space indent. */
    expect(spdf_win_find_json_bool("{\n  \"markdownTheme\": \"dark\",\n  \"searchJumpsToNearestResult\": false,\n"
                                   "  \"minimapWidth\": 126.5\n}",
                                   k, 1) == 0,
           "false is read as false");
    expect(spdf_win_find_json_bool("{\"searchJumpsToNearestResult\":true}", k, 0) == 1, "true, no whitespace");
    expect(spdf_win_find_json_bool("{ \"searchJumpsToNearestResult\" \t:\n true }", k, 0) == 1,
           "whitespace around the colon");

    /* Absent key, absent file, empty object: the fallback, whichever it is. */
    expect(spdf_win_find_json_bool("{\"minimapWidth\": 126.5}", k, 1) == 1, "absent key -> fallback 1");
    expect(spdf_win_find_json_bool("{\"minimapWidth\": 126.5}", k, 0) == 0, "absent key -> fallback 0");
    expect(spdf_win_find_json_bool(NULL, k, 1) == 1, "no file -> fallback");
    expect(spdf_win_find_json_bool("", k, 1) == 1, "empty text -> fallback");
    expect(spdf_win_find_json_bool("{}", k, 1) == 1, "empty object -> fallback");

    /* A non-boolean value is not guessed at. */
    expect(spdf_win_find_json_bool("{\"searchJumpsToNearestResult\": \"yes\"}", k, 1) == 1, "string value -> fallback");
    expect(spdf_win_find_json_bool("{\"searchJumpsToNearestResult\": 1}", k, 0) == 0, "number -> fallback");

    /* The key as a VALUE elsewhere must not be mistaken for the member. */
    expect(spdf_win_find_json_bool("{\"lastCommand\": \"searchJumpsToNearestResult\", \"searchJumpsToNearestResult\": "
                                   "false}",
                                   k, 1) == 0,
           "key inside a string value is skipped, the real member is read");
    /* A longer key that begins with ours is a different key. */
    expect(spdf_win_find_json_bool("{\"searchJumpsToNearestResultX\": false}", k, 1) == 1, "prefix key is not ours");
    expect(spdf_win_find_json_bool("{\"xsearchJumpsToNearestResult\": false}", k, 1) == 1, "suffix key is not ours");
    /* A degenerate key. */
    expect(spdf_win_find_json_bool("{\"a\": true}", "", 0) == 0, "empty key -> fallback");
    expect(spdf_win_find_json_bool("{\"a\": true}", NULL, 1) == 1, "NULL key -> fallback");

    if (failures) {
        printf("%d find settings check(s) failed\n", failures);
        return 1;
    }
    printf("All find settings checks passed\n");
    return 0;
}
