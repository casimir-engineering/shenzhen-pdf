// Pure-logic tests for the command palette's filter (glib only, no GTK):
// fuzzy ranking semantics, Commands-section assembly from a fake action
// table, and the text-match snippet builder. The GTK half of the module is
// compiled out via SPDF_PALETTE_TESTING (same pattern as spdf_state_test.c).
#define SPDF_PALETTE_TESTING 1

#include "../spdf_palette.c"

// --- fuzzy score --------------------------------------------------------------

static void test_fuzzy_empty_query_matches_everything(void) {
    g_assert_cmpint(spdf_palette_fuzzy_score("", "Open a document"), ==, 0);
    g_assert_cmpint(spdf_palette_fuzzy_score(NULL, "Open a document"), ==, 0);
    g_assert_cmpint(spdf_palette_fuzzy_score("", ""), ==, 0);
}

static void test_fuzzy_non_subsequence_rejected(void) {
    g_assert_cmpint(spdf_palette_fuzzy_score("xyz", "Open a document"), ==, -1);
    // Order matters: a subsequence, not a bag of characters.
    g_assert_cmpint(spdf_palette_fuzzy_score("po", "Print"), ==, -1);
    g_assert_cmpint(spdf_palette_fuzzy_score("a", ""), ==, -1);
    g_assert_cmpint(spdf_palette_fuzzy_score("a", NULL), ==, -1);
}

static void test_fuzzy_case_insensitive(void) {
    int lower = spdf_palette_fuzzy_score("zoom", "Zoom in");
    g_assert_cmpint(lower, >, 0);
    g_assert_cmpint(spdf_palette_fuzzy_score("ZOOM", "Zoom in"), ==, lower);
    g_assert_cmpint(spdf_palette_fuzzy_score("Zoom", "zoom in"), ==, lower);
}

static void test_fuzzy_word_boundary_beats_mid_word(void) {
    // "op": word-boundary prefix of "Open…", mid-word inside "Copy…".
    int open_score = spdf_palette_fuzzy_score("op", "Open a document");
    int copy_score = spdf_palette_fuzzy_score("op", "Copy selected text");
    g_assert_cmpint(open_score, >, copy_score);
    g_assert_cmpint(copy_score, >=, 0);
}

static void test_fuzzy_consecutive_run_beats_scatter(void) {
    // Same characters, tight run vs. spread across words.
    int tight = spdf_palette_fuzzy_score("fit", "Fit page");
    int scattered = spdf_palette_fuzzy_score("fit", "Find in the current document");
    g_assert_cmpint(tight, >, scattered);
    g_assert_cmpint(scattered, >=, 0);
}

static void test_fuzzy_early_match_beats_late_match(void) {
    int early = spdf_palette_fuzzy_score("page", "Page setup");
    int late = spdf_palette_fuzzy_score("page", "Go to page");
    // Both hit "page" as a word run; the leading-skip penalty (capped at 3)
    // ranks the prefix match first.
    g_assert_cmpint(early, >, late);
}

static void test_fuzzy_exact_values_are_stable(void) {
    // Pin the documented arithmetic for one example: "op" on "Open a document"
    // = o(1+3 boundary) + p(1+2 run) = 7, no gaps, no lead.
    g_assert_cmpint(spdf_palette_fuzzy_score("op", "Open a document"), ==, 7);
    // "op" on "Copy" = o(1) + p(1+2 run) = 4, lead 1 => 3.
    g_assert_cmpint(spdf_palette_fuzzy_score("op", "Copy"), ==, 3);
}

// --- command filtering / section assembly --------------------------------------

static const SpdfPaletteCommand k_fake_table[] = {
    {"win.open", "Open a document", "<Control>o", TRUE},
    {"win.close-tab", "Close the current tab", "<Control>w", TRUE},
    {"win.print", "Print the document", "<Control>p", FALSE}, // disabled
    {"win.copy", "Copy selected document text", "<Control>c", TRUE},
    {"win.rotate-cw", "", "<Control>r", TRUE},                // no title
    {"app.quit", "Quit Shenzhen PDF", "<Control>q", TRUE},
};
#define FAKE_COUNT ((int)G_N_ELEMENTS(k_fake_table))

static void test_filter_empty_query_keeps_table_order(void) {
    SpdfPaletteMatch matches[FAKE_COUNT];
    int n = spdf_palette_filter_commands(k_fake_table, FAKE_COUNT, "", matches, FAKE_COUNT);

    // Everything enabled with a title, in table order, neutral score.
    g_assert_cmpint(n, ==, 4);
    g_assert_cmpint(matches[0].index, ==, 0);
    g_assert_cmpint(matches[1].index, ==, 1);
    g_assert_cmpint(matches[2].index, ==, 3);
    g_assert_cmpint(matches[3].index, ==, 5);
    for (int i = 0; i < n; ++i) g_assert_cmpint(matches[i].score, ==, 0);
}

static void test_filter_skips_disabled_even_when_matching(void) {
    SpdfPaletteMatch matches[FAKE_COUNT];
    int n = spdf_palette_filter_commands(k_fake_table, FAKE_COUNT, "print", matches, FAKE_COUNT);
    g_assert_cmpint(n, ==, 0); // "Print the document" is disabled
}

static void test_filter_ranks_by_score(void) {
    SpdfPaletteMatch matches[FAKE_COUNT];
    int n = spdf_palette_filter_commands(k_fake_table, FAKE_COUNT, "op", matches, FAKE_COUNT);

    // "Open a document" (boundary prefix) must outrank "Copy selected…" and
    // "Close the current tab" ('o'…'p' scattered).
    g_assert_cmpint(n, >=, 2);
    g_assert_cmpint(matches[0].index, ==, 0);
    for (int i = 1; i < n; ++i) g_assert_cmpint(matches[0].score, >=, matches[i].score);
}

static void test_filter_tie_keeps_table_order(void) {
    static const SpdfPaletteCommand twins[] = {
        {"win.a", "Same label", NULL, TRUE},
        {"win.b", "Same label", NULL, TRUE},
    };
    SpdfPaletteMatch matches[2];
    int n = spdf_palette_filter_commands(twins, 2, "same", matches, 2);

    g_assert_cmpint(n, ==, 2);
    g_assert_cmpint(matches[0].score, ==, matches[1].score);
    g_assert_cmpint(matches[0].index, ==, 0);
    g_assert_cmpint(matches[1].index, ==, 1);
}

static void test_filter_respects_out_max_and_bad_input(void) {
    SpdfPaletteMatch matches[2];
    int n = spdf_palette_filter_commands(k_fake_table, FAKE_COUNT, "", matches, 2);
    g_assert_cmpint(n, ==, 2);
    g_assert_cmpint(spdf_palette_filter_commands(NULL, 3, "", matches, 2), ==, 0);
    g_assert_cmpint(spdf_palette_filter_commands(k_fake_table, FAKE_COUNT, "", NULL, 2), ==, 0);
    g_assert_cmpint(spdf_palette_filter_commands(k_fake_table, FAKE_COUNT, "", matches, 0), ==, 0);
}

static void test_filter_no_match_returns_empty(void) {
    SpdfPaletteMatch matches[FAKE_COUNT];
    int n = spdf_palette_filter_commands(k_fake_table, FAKE_COUNT, "zzzz", matches, FAKE_COUNT);
    g_assert_cmpint(n, ==, 0);
}

// --- snippet builder -----------------------------------------------------------

static void test_snippet_short_line_returned_whole(void) {
    char* snippet = spdf_palette_snippet_from_line("USB3.1 Gen2 pinout", "gen2");
    g_assert_cmpstr(snippet, ==, "USB3.1 Gen2 pinout");
    g_free(snippet);
}

static void test_snippet_no_match_returns_null(void) {
    g_assert_null(spdf_palette_snippet_from_line("nothing to see here", "gasket"));
    g_assert_null(spdf_palette_snippet_from_line("", "x"));
    g_assert_null(spdf_palette_snippet_from_line("text", ""));
    g_assert_null(spdf_palette_snippet_from_line(NULL, "x"));
}

static void test_snippet_clips_long_line_with_ellipses(void) {
    const char* line =
        "The differential pair impedance must be held at 90 ohms across the flex, "
        "including the CABLINE-CA II Plus connector breakout region at both ends.";
    char* snippet = spdf_palette_snippet_from_line(line, "CABLINE");

    g_assert_nonnull(snippet);
    g_assert_nonnull(strstr(snippet, "CABLINE"));
    g_assert_true(g_str_has_prefix(snippet, "\xE2\x80\xA6")); // clipped on the left
    g_assert_true(g_str_has_suffix(snippet, "\xE2\x80\xA6")); // clipped on the right
    // 24 bytes of context each side plus the match and ellipses.
    g_assert_cmpuint(strlen(snippet), <=, strlen("CABLINE") + 2 * 24 + 2 * 3);
    g_free(snippet);
}

static void test_snippet_never_splits_utf8(void) {
    // Multibyte chars sit exactly where naive ±24-byte clipping would cut.
    const char* line = "ééééééééééééé needle ééééééééééééé"; // 2-byte chars both sides
    char* snippet = spdf_palette_snippet_from_line(line, "needle");

    g_assert_nonnull(snippet);
    g_assert_true(g_utf8_validate(snippet, -1, NULL));
    g_assert_nonnull(strstr(snippet, "needle"));
    g_free(snippet);
}

int main(int argc, char** argv) {
    g_test_init(&argc, &argv, NULL);
    g_test_add_func("/palette/fuzzy/empty-query", test_fuzzy_empty_query_matches_everything);
    g_test_add_func("/palette/fuzzy/non-subsequence", test_fuzzy_non_subsequence_rejected);
    g_test_add_func("/palette/fuzzy/case-insensitive", test_fuzzy_case_insensitive);
    g_test_add_func("/palette/fuzzy/word-boundary", test_fuzzy_word_boundary_beats_mid_word);
    g_test_add_func("/palette/fuzzy/consecutive-run", test_fuzzy_consecutive_run_beats_scatter);
    g_test_add_func("/palette/fuzzy/early-match", test_fuzzy_early_match_beats_late_match);
    g_test_add_func("/palette/fuzzy/exact-values", test_fuzzy_exact_values_are_stable);
    g_test_add_func("/palette/filter/empty-query-order", test_filter_empty_query_keeps_table_order);
    g_test_add_func("/palette/filter/skips-disabled", test_filter_skips_disabled_even_when_matching);
    g_test_add_func("/palette/filter/ranks-by-score", test_filter_ranks_by_score);
    g_test_add_func("/palette/filter/tie-order", test_filter_tie_keeps_table_order);
    g_test_add_func("/palette/filter/out-max", test_filter_respects_out_max_and_bad_input);
    g_test_add_func("/palette/filter/no-match", test_filter_no_match_returns_empty);
    g_test_add_func("/palette/snippet/short-line", test_snippet_short_line_returned_whole);
    g_test_add_func("/palette/snippet/no-match", test_snippet_no_match_returns_null);
    g_test_add_func("/palette/snippet/clipping", test_snippet_clips_long_line_with_ellipses);
    g_test_add_func("/palette/snippet/utf8", test_snippet_never_splits_utf8);
    return g_test_run();
}
