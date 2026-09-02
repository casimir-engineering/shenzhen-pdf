/* session_frame_test.c — the second half of portable/win/src/spdf_win_session.{h,cpp}:
 * the window's frame, the per-tab search text, and the detach hand-over.
 *
 * Split from session_test.c, which is at its 500-line cap; same subject, same
 * codec, same file shell, same scratch layout. Three claims:
 *
 *   1. THE FRAME ROUND-TRIPS as the mac schema spells it ("frame": {x, y,
 *      width, height}), a save with no frame keeps the one on disk, and a mac
 *      frame reads back through the same path.
 *   2. searchText ROUND-TRIPS per tab -- written only when there is a query,
 *      read back into the tab's view, and a mac tab's query lands in the right
 *      tab -- because "each tab remembers its query across relaunches" is the
 *      readme's promise and it was carried through untouched until now.
 *   3. DETACHING A TAB writes it as a NEW window under a fresh id with its
 *      whole view state, leaves the source window untouched in the file, and
 *      the new id restores to exactly that one tab -- which is the whole
 *      hand-over a second process needs.
 *
 * Exit code is the whole signal: 0 pass, 1 fail.
 */
/* spdf-test-sources: portable/win/src/spdf_win_session.cpp portable/win/src/spdf_win_tabs.cpp portable/win/src/spdf_win_state.c portable/win/src/spdf_win_paths.c portable/core/spdf_yaml.c portable/core/spdf_win_compat.c */
#ifndef _CRT_SECURE_NO_WARNINGS
#define _CRT_SECURE_NO_WARNINGS
#endif

#include "silent_failure_support.h" /* check, write_whole/read_whole, remove_file */

#include "../src/spdf_win_session.h"
#include "../src/spdf_win_state.h"

static void check_eq(int got, int want, const char* what) {
    if (got != want) {
        printf("FAIL: %s (got %d, want %d)\n", what, got, want);
        g_failures++;
    }
}

static char g_session_path[SPDF_WIN_PATH_MAX];

static const char* const kMacSessionYaml =
    "# ShenzhenPDF session \xe2\x80\x94 edit while the app is closed\n"
    "version: 2\n"
    "windows:\n"
    "  - frame:\n"
    "      height: 800\n"
    "      width: 1120\n"
    "      x: 100\n"
    "      y: 120\n"
    "    id: \"win-mac-1\"\n"
    "    selectedTab: 1\n"
    "    tabs:\n"
    "      - fitMode: 2\n"
    "        page: 12\n"
    "        path: \"/Users/r/a.pdf\"\n"
    "        searchText: \"budget \xe5\xbc\xa0\"\n"
    "        viewMode: 1\n"
    "        zoom: 1.25\n"
    "      - page: 1\n"
    "        path: \"/Users/r/b.pdf\"\n"
    "        viewMode: 1\n"
    "        zoom: 1\n";

static void test_frame_and_search_read_from_a_mac_file(void) {
    spdf_win_tabs* tabs = spdf_win_tabs_create();
    spdf_win_session_frame frame;
    char id[SPDF_WIN_SESSION_ID_MAX] = {0};

    remove_file(g_session_path);
    if (!write_whole(g_session_path, kMacSessionYaml)) {
        check(0, "seed a mac-written session.yaml");
        spdf_win_tabs_destroy(tabs);
        return;
    }
    check_eq((int)spdf_win_session_restore_ex(tabs, NULL, id, sizeof(id), &frame), SPDF_WIN_SESSION_RESTORED,
             "restore_ex restores");
    check_eq(frame.x, 100, "frame.x");
    check_eq(frame.y, 120, "frame.y");
    check_eq(frame.w, 1120, "frame.width");
    check_eq(frame.h, 800, "frame.height");
    check(strcmp(spdf_win_tabs_view_const(tabs, 0)->search_text, "budget \xe5\xbc\xa0") == 0,
          "the first tab's searchText lands in the first tab, UTF-8 intact");
    check(spdf_win_tabs_view_const(tabs, 1)->search_text[0] == '\0', "a tab with no searchText has none");
    spdf_win_tabs_destroy(tabs);
}

static void test_frame_round_trips_and_is_kept_when_unknown(void) {
    spdf_win_tabs* tabs = spdf_win_tabs_create();
    spdf_win_tabs* back = spdf_win_tabs_create();
    spdf_win_session_frame frame, got;
    char* yaml;

    remove_file(g_session_path);
    spdf_win_tabs_append(tabs, "C:\\docs\\one.pdf", NULL);
    spdf_win_tabs_select_deferred(tabs, 0);
    frame.x = -8;
    frame.y = 32;
    frame.w = 1400;
    frame.h = 900;
    check(spdf_win_session_save_ex(tabs, "win-A", &frame), "save with a frame");
    yaml = read_whole(g_session_path);
    /* The codec keeps emission order (the mac's sorted-key files read the same),
     * so the frame follows the id; its own keys are in the mac's order. */
    if (!yaml || strstr(yaml, "    frame:\n      height: 900\n      width: 1400\n      x: -8\n      y: 32\n") == NULL) {
        check(0, "the frame is written in the mac schema's shape and key order");
        printf("--- session.yaml ---\n%s--- end ---\n", yaml ? yaml : "(unreadable)");
    }
    free(yaml);

    /* A save that knows no geometry keeps the frame on disk. */
    spdf_win_tabs_view(tabs, 0)->page = 3;
    check(spdf_win_session_save(tabs, "win-A"), "save without a frame");
    check_eq((int)spdf_win_session_restore_ex(back, "win-A", NULL, 0, &got), SPDF_WIN_SESSION_RESTORED, "reads back");
    check_eq(got.w, 1400, "the frame survived a frameless save");
    check_eq(got.x, -8, "negative coordinates included");
    check_eq(spdf_win_tabs_view_const(back, 0)->page, 3, "and the page moved");
    spdf_win_tabs_destroy(back);
    spdf_win_tabs_destroy(tabs);
}

static void test_search_text_round_trips(void) {
    spdf_win_tabs* tabs = spdf_win_tabs_create();
    spdf_win_tabs* back = spdf_win_tabs_create();
    char* yaml;

    remove_file(g_session_path);
    spdf_win_tabs_append(tabs, "C:\\docs\\one.pdf", NULL);
    spdf_win_tabs_append(tabs, "C:\\docs\\two.pdf", NULL);
    spdf_win_tabs_select_deferred(tabs, 1);
    strcpy(spdf_win_tabs_view(tabs, 1)->search_text, "quote \"me\" \\ back");
    check(spdf_win_session_save(tabs, "win-S"), "save");
    yaml = read_whole(g_session_path);
    check(yaml && strstr(yaml, "searchText") != NULL, "a live query is written");
    /* Exactly one: the tab without a query gets no key at all. */
    check(yaml && strstr(strstr(yaml, "searchText") + 1, "searchText") == NULL, "and only for the tab that has one");
    free(yaml);
    check_eq((int)spdf_win_session_restore(back, "win-S", NULL, 0), SPDF_WIN_SESSION_RESTORED, "reads back");
    check(spdf_win_tabs_view_const(back, 0)->search_text[0] == '\0', "no query, no text");
    check(strcmp(spdf_win_tabs_view_const(back, 1)->search_text, "quote \"me\" \\ back") == 0,
          "the query comes back through the codec, escapes and all");
    spdf_win_tabs_destroy(back);
    spdf_win_tabs_destroy(tabs);
}

static void test_detach_hands_a_tab_to_a_new_window(void) {
    spdf_win_tabs* tabs = spdf_win_tabs_create();
    spdf_win_tabs* other = spdf_win_tabs_create();
    spdf_win_tabs* source = spdf_win_tabs_create();
    spdf_win_tab_view* v;
    spdf_win_session_frame frame, got;
    char new_id[SPDF_WIN_SESSION_ID_MAX] = {0};

    remove_file(g_session_path);
    spdf_win_tabs_append(tabs, "C:\\docs\\keep.pdf", NULL);
    spdf_win_tabs_append(tabs, "C:\\docs\\torn.pdf", "Torn Off");
    spdf_win_tabs_select_deferred(tabs, 0);
    v = spdf_win_tabs_view(tabs, 1);
    v->page = 41;
    v->zoom = 1.5;
    v->fit_mode = SPDF_WIN_TAB_FIT_CUSTOM;
    v->scroll_y = 300.25;
    v->has_scroll_origin = 1;
    strcpy(v->search_text, "torn");
    check(spdf_win_session_save(tabs, "win-src"), "the source window is on disk");

    frame.x = 40;
    frame.y = 40;
    frame.w = 1120;
    frame.h = 800;
    check(spdf_win_session_detach_tab(tabs, 1, &frame, new_id, sizeof(new_id)), "detach writes");
    check(new_id[0] != '\0' && strcmp(new_id, "win-src") != 0, "under a fresh id");
    /* The source model is untouched: closing the tab is the caller's, after
     * the hand-over has landed on disk. */
    check_eq(spdf_win_tabs_count(tabs), 2, "the source model still has both tabs");

    check_eq((int)spdf_win_session_restore_ex(other, new_id, NULL, 0, &got), SPDF_WIN_SESSION_RESTORED,
             "the new id restores");
    check_eq(spdf_win_tabs_count(other), 1, "to exactly one tab");
    check(strcmp(spdf_win_tabs_path(other, 0), "C:\\docs\\torn.pdf") == 0, "the torn-off one");
    check(strcmp(spdf_win_tabs_title(other, 0), "Torn Off") == 0, "with its title");
    check_eq(spdf_win_tabs_view_const(other, 0)->page, 41, "its page");
    check_eq(spdf_win_tabs_view_const(other, 0)->fit_mode, SPDF_WIN_TAB_FIT_CUSTOM, "its fit mode");
    check(spdf_win_tabs_view_const(other, 0)->zoom > 1.49 && spdf_win_tabs_view_const(other, 0)->zoom < 1.51,
          "its zoom");
    check(spdf_win_tabs_view_const(other, 0)->scroll_y > 300.0, "its scroll offset");
    check(strcmp(spdf_win_tabs_view_const(other, 0)->search_text, "torn") == 0, "and its query");
    check_eq(got.w, 1120, "the frame the caller gave it");

    check_eq((int)spdf_win_session_restore(source, "win-src", NULL, 0), SPDF_WIN_SESSION_RESTORED,
             "the source window is still in the file");
    check_eq(spdf_win_tabs_count(source), 2, "unchanged: the caller removes the tab and saves");

    check(!spdf_win_session_detach_tab(tabs, 7, NULL, new_id, sizeof(new_id)), "a bad index detaches nothing");
    spdf_win_tabs_destroy(source);
    spdf_win_tabs_destroy(other);
    spdf_win_tabs_destroy(tabs);
}

int main(int argc, char** argv) {
    char scratch[SPDF_WIN_PATH_MAX];
    char dir[SPDF_WIN_PATH_MAX];
    const char* base = argc > 1 ? argv[1] : NULL;

    printf("spdf_win_session frame/search/detach tests\n");
    if (!base || !*base) {
#if defined(_WIN32)
        base = getenv("TEMP");
#else
        base = getenv("TMPDIR");
#endif
    }
    if (!base || !*base) base = ".";
    if (!spdf_win_path_join(base, "spdf_session_frame_test", scratch, sizeof(scratch))) return 1;
    if (!spdf_win_path_join(scratch, "Rapha\xc3\xabl", dir, sizeof(dir))) return 1;
    if (!spdf_win_paths_ensure_dir(dir)) {
        printf("FAIL: could not create the scratch directory under %s\n", scratch);
        return 1;
    }
    spdf_win_paths_set_state_dir_override(dir);
    if (!spdf_win_paths_state_file(SPDF_WIN_STATE_SESSION, g_session_path, sizeof(g_session_path))) return 1;

    test_frame_and_search_read_from_a_mac_file();
    test_frame_round_trips_and_is_kept_when_unknown();
    test_search_text_round_trips();
    test_detach_hands_a_tab_to_a_new_window();

    remove_file(g_session_path);
    spdf_win_paths_set_state_dir_override(NULL);
    if (g_failures) {
        printf("%d failure(s)\n", g_failures);
        return 1;
    }
    printf("ok\n");
    return 0;
}
