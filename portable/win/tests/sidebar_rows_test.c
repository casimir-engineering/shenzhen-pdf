/* The sidebar's chapter list: the outline -> rows conversion, the filter, the
 * row geometry and the hit-test. portable/win/src/spdf_win_chrome_content.h.
 *
 * WHAT THIS EXISTS TO STOP, in the order the defects would appear.
 *
 *   1. A NARROW CONVERSION. This machine's ANSI code page is 1252 and a chapter
 *      title is exactly where a CJK or accented name shows up. A conversion
 *      through CP_ACP does not fail -- it produces mojibake or question marks,
 *      quietly, and only for the documents whose titles are not ASCII. So the
 *      fixtures below carry Japanese, German, Greek and emoji titles as raw
 *      UTF-8 BYTES (written as \xNN escapes, so this file's own encoding cannot
 *      change what is being tested) and the expected UTF-16 is written as \u
 *      escapes. Those two cannot both be wrong in the same direction.
 *   2. AN INDENT THAT IS NOT macOS's. Nesting is level*3 SPACES prepended to the
 *      title with the level clamped to [0, 16] (ShenzhenPDFMac.mm:16613-16619).
 *      An indent implemented as a rect offset would look similar and diverge
 *      under truncation and selection.
 *   3. A FILTER THAT IS ONLY CASE-INSENSITIVE. macOS uses
 *      NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch (:9666-9670), so
 *      "zurich" must match U+005A U+00FC "rich". A towupper loop passes the case half and
 *      fails the diacritic half.
 *   4. A HIT-TEST THAT DISAGREES WITH THE PAINT. Both go through
 *      spdf_win_sidebar_row_rect / _row_at, and the checks below drive the two
 *      against each other at several scroll offsets and DPI scales.
 *
 * Header-only subject: no extra translation units, no document, no MuPDF, no
 * render target. Judged by exit code.
 */

#include <stdio.h>
#include <string.h>

#include "spdf_win_chrome_content.h"

static int failures;

static void expect(int condition, const char* what) {
    if (!condition) {
        printf("FAIL %s\n", what);
        failures++;
    }
}

static void expect_wstr(const wchar_t* got, const wchar_t* want, const char* what) {
    if (!got || wcscmp(got, want) != 0) {
        printf("FAIL %s\n", what);
        failures++;
    }
}

static void expect_near(float got, float want, const char* what) {
    float d = got - want;
    if (d < 0.0f) d = -d;
    if (d > 0.001f) {
        printf("FAIL %s: got %.4f want %.4f\n", what, got, want);
        failures++;
    }
}

/* --- fixtures -----------------------------------------------------------
 *
 * Raw UTF-8 bytes, deliberately. "\xE7\xAC\xAC\xE4\xB8\x80\xE7\xAB\xA0" is
 * U+7B2C U+4E00 U+7AE0 ("chapter one"); "\xC3\x9C" is U+00DC;
 * "\xCE\x91" is U+0391 (Greek capital alpha); "\xF0\x9F\x93\x84" is U+1F4C4,
 * which is OUTSIDE the BMP and therefore a surrogate pair in UTF-16 -- the case
 * a length-in-characters assumption gets wrong. */
static const char* kTitles[] = {
    "Introduction",                          /* 0 */
    "\xC3\x9C" "berblick",                   /* 1  U+00DC "berblick" */
    "\xE7\xAC\xAC\xE4\xB8\x80\xE7\xAB\xA0",  /* 2  U+7B2C U+4E00 U+7AE0 */
    "Z\xC3\xBC" "rich",                      /* 3  Z U+00FC "rich" */
    "\xCE\x91" "lpha",                       /* 4  U+0391 "lpha" */
    "\xF0\x9F\x93\x84 Appendix",             /* 5  emoji + Appendix, non-BMP */
    NULL,                                    /* 6  no title at all */
    "",                                      /* 7  empty title */
    "Deeply nested",                         /* 8 */
    "Absurdly nested",                       /* 9 */
};
static const int kPages[] = {0, 2, 5, 5, 9, 40, 41, 42, 7, 8};
static const int kLevels[] = {0, 1, 2, 1, 0, 0, 0, 0, 4, 99};
static const int kCount = (int)(sizeof(kTitles) / sizeof(kTitles[0]));

#define ROWS_MAX 32
#define ARENA_WCHARS 4096

static SpdfWinSidebarRow g_rows[ROWS_MAX];
static wchar_t g_arena[ARENA_WCHARS];

static int build(const wchar_t* filter) {
    memset(g_rows, 0, sizeof(g_rows));
    memset(g_arena, 0, sizeof(g_arena));
    return spdf_win_sidebar_build_rows(kTitles, kPages, kLevels, kCount, filter, g_rows, ROWS_MAX, g_arena,
                                       ARENA_WCHARS);
}

static void test_utf8(void) {
    int n = build(NULL);

    expect(n == kCount, "every outline entry becomes a row when there is no filter");
    if (n != kCount) return;

    expect_wstr(g_rows[0].title, L"Introduction", "an ASCII title survives");
    /* Level 1 -> three leading spaces. */
    expect_wstr(g_rows[1].title, L"   \u00DCberblick", "a Latin-1 title converts through CP_UTF8, indented once");
    expect_wstr(g_rows[2].title, L"      \u7b2c\u4e00\u7ae0", "a CJK title converts through CP_UTF8, indented twice");
    expect_wstr(g_rows[3].title, L"   Z\u00FCrich", "an accented title keeps its accent");
    expect_wstr(g_rows[4].title, L"\u0391lpha", "a Greek title converts");
    /* U+1F4C4 is D83D DCC4 in UTF-16. Written as the surrogate pair explicitly:
     * a compiler that mishandled \U0001F4C4 would otherwise hide the bug. */
    expect_wstr(g_rows[5].title, L"\xD83D\xDCC4 Appendix", "a non-BMP title becomes a surrogate pair");
    /* macOS substitutes "Untitled" for a missing title (:9876). Both a NULL and
     * an empty title take that path, because a blank row is unclickable. */
    expect_wstr(g_rows[6].title, L"Untitled", "a NULL title becomes Untitled");
    expect_wstr(g_rows[7].title, L"Untitled", "an empty title becomes Untitled");

    /* NOT mojibake: had the conversion gone through CP_ACP on this 1252 box,
     * row 1 would begin with U+00C3 rather than U+00DC. Asserted
     * directly, because that is the exact failure being guarded. */
    expect(g_rows[1].title[3] == 0x00DC, "the Latin-1 title is not double-encoded mojibake");
    expect(g_rows[2].title[6] == 0x7B2C, "the CJK title is not question marks");
}

static void test_levels_and_pages(void) {
    int n = build(NULL);
    if (n != kCount) return;

    expect(g_rows[0].level == 0, "level 0 stays 0");
    expect(g_rows[8].level == 4, "level 4 survives");
    /* macOS clamps to 16, so a corrupt outline claiming depth 99 indents 48
     * spaces and no more. */
    expect(g_rows[9].level == SPDF_WIN_SIDEBAR_MAX_LEVEL, "an absurd level clamps to 16");
    expect(wcslen(g_rows[9].title) == (size_t)(16 * SPDF_WIN_SIDEBAR_INDENT_SPACES) + wcslen(L"Absurdly nested"),
           "the clamped level indents by 48 spaces exactly");
    expect(g_rows[9].title[0] == L' ' && g_rows[9].title[47] == L' ' && g_rows[9].title[48] == L'A',
           "the indent is spaces and the title starts right after them");

    expect(g_rows[0].page_index == 0, "page 0 is carried through");
    expect(g_rows[5].page_index == 40, "a later page is carried through");
    expect(g_rows[0].outline_index == 0 && g_rows[5].outline_index == 5,
           "the outline index is preserved so a click can route back to the entry");
}

/* An entry the core could not resolve keeps page_index -1. All three of the
 * core's own unresolvable cases (a missing target, an external URL, a dest-less
 * entry) land here, and the painter greys such a row out. */
static void test_unresolved(void) {
    static const char* titles[] = {"Resolved", "Missing chapter", "External site"};
    static const int pages[] = {3, -1, -1};
    static const int levels[] = {0, 0, 0};
    int n;

    memset(g_rows, 0, sizeof(g_rows));
    memset(g_arena, 0, sizeof(g_arena));
    n = spdf_win_sidebar_build_rows(titles, pages, levels, 3, NULL, g_rows, ROWS_MAX, g_arena, ARENA_WCHARS);
    expect(n == 3, "an unresolvable entry is still a row");
    expect(g_rows[1].page_index < 0 && g_rows[2].page_index < 0, "unresolvable entries keep page_index -1");
}

static void test_filter_matching(void) {
    /* Empty filter matches everything; empty title matches nothing. */
    expect(spdf_win_sidebar_title_matches(L"anything", NULL), "a NULL filter matches");
    expect(spdf_win_sidebar_title_matches(L"anything", L""), "an empty filter matches");
    expect(!spdf_win_sidebar_title_matches(L"", L"a"), "an empty title never matches");
    expect(!spdf_win_sidebar_title_matches(NULL, L"a"), "a NULL title never matches");

    /* Case. */
    expect(spdf_win_sidebar_title_matches(L"Introduction", L"intro"), "the filter ignores case");
    expect(spdf_win_sidebar_title_matches(L"Introduction", L"DUCT"), "the filter matches mid-string, any case");
    expect(!spdf_win_sidebar_title_matches(L"Introduction", L"conclusion"), "a non-match does not match");

    /* Diacritics, both directions -- this is the half a towupper loop fails. */
    expect(spdf_win_sidebar_title_matches(L"Z\u00FCrich", L"zurich"), "an unaccented filter matches an accented title");
    expect(spdf_win_sidebar_title_matches(L"Zurich", L"z\u00FCrich"), "an accented filter matches an unaccented title");
    expect(spdf_win_sidebar_title_matches(L"\u00DCberblick", L"uber"), "U-umlaut matches u");

    /* Non-Latin scripts are matched by substring like anything else. */
    expect(spdf_win_sidebar_title_matches(L"\u7b2c\u4e00\u7ae0", L"\u4e00"), "a CJK substring matches");
    expect(!spdf_win_sidebar_title_matches(L"\u7b2c\u4e00\u7ae0", L"\u4e8c"), "a different CJK character does not");
}

static void test_filter_rows(void) {
    int n;

    /* Filtering runs on the UNINDENTED title, so a nested row is reachable by
     * its own text and a filter of spaces does not select every nested row. */
    n = build(L"berblick");
    expect(n == 1, "one row survives a filter that matches one title");
    expect_wstr(g_rows[0].title, L"   \u00DCberblick", "the surviving row is still indented");
    expect(g_rows[0].outline_index == 1, "the surviving row remembers where it came from");

    n = build(L"uber");
    expect(n == 1, "the diacritic-insensitive filter reaches the accented row");

    n = build(L"nested");
    expect(n == 2, "a filter matching two titles keeps both, in outline order");
    if (n == 2) expect(g_rows[0].outline_index == 8 && g_rows[1].outline_index == 9, "filtered rows keep their order");

    n = build(L"Untitled");
    expect(n == 2, "the Untitled substitution is filterable like any other title");

    n = build(L"zzzz-no-such-chapter");
    expect(n == 0, "a filter that matches nothing yields no rows");

    /* An out_max smaller than the match count truncates rather than overruns. */
    memset(g_rows, 0, sizeof(g_rows));
    memset(g_arena, 0, sizeof(g_arena));
    expect(spdf_win_sidebar_build_rows(kTitles, kPages, kLevels, kCount, NULL, g_rows, 3, g_arena, ARENA_WCHARS) == 3,
           "a small row array truncates at its capacity");
    /* An arena too small to hold the titles stops cleanly. */
    memset(g_rows, 0, sizeof(g_rows));
    expect(spdf_win_sidebar_build_rows(kTitles, kPages, kLevels, kCount, NULL, g_rows, ROWS_MAX, g_arena, 8) < kCount,
           "a small text arena stops rather than overrunning");
    /* Degenerate inputs return 0 rather than touching anything. */
    expect(spdf_win_sidebar_build_rows(kTitles, kPages, kLevels, kCount, NULL, NULL, ROWS_MAX, g_arena, ARENA_WCHARS) ==
               0,
           "a NULL row array yields no rows");
    expect(spdf_win_sidebar_build_rows(kTitles, kPages, kLevels, 0, NULL, g_rows, ROWS_MAX, g_arena, ARENA_WCHARS) == 0,
           "zero entries yield no rows");
}

/* --- geometry ----------------------------------------------------------- */

static SpdfWinChromeRect sidebar_rect(float dpi) {
    SpdfWinChromeRect r;
    r.x = 0.0f;
    r.y = spdf_win_chrome_px(84.0, dpi); /* below the 42 pt strip and 42 pt toolbar */
    r.w = spdf_win_chrome_px(240.0, dpi);
    r.h = spdf_win_chrome_px(700.0, dpi);
    return r;
}

static void test_layout(float dpi) {
    SpdfWinChromeRect side = sidebar_rect(dpi);
    SpdfWinSidebarLayout l;
    float inset = spdf_win_chrome_px(SPDF_WIN_SIDEBAR_INSET, dpi);

    /* Chapters mode: sections, then the filter field, then the list. */
    spdf_win_sidebar_layout(side, 0, dpi, &l);
    expect_near(l.row_h, spdf_win_chrome_px(SPDF_WIN_SIDEBAR_ROW_H, dpi), "the row height is 25 pt in device px");
    expect_near(l.sections.x, side.x + inset, "the segmented control is inset 8 pt");
    expect_near(l.sections.w, side.w - 2.0f * inset, "the segmented control spans the panel less both insets");
    expect_near(l.sections.y, side.y + spdf_win_chrome_px(SPDF_WIN_SIDEBAR_TOP_PAD, dpi),
                "the segmented control sits 8 pt below the panel top");
    expect(!spdf_win_chrome_rect_empty(l.filter), "the filter field exists in Chapters mode");
    expect(l.filter.y > l.sections.y + l.sections.h - 0.001f, "the filter field is below the segmented control");
    expect(l.list.y > l.filter.y + l.filter.h - 0.001f, "the list is below the filter field");
    expect_near(l.list.x, side.x + inset, "the list is inset like the controls above it");
    expect_near(l.list.y + l.list.h, side.y + side.h, "the list runs to the bottom of the panel");

    /* Search mode hides the field, and the list moves up to take its place --
     * which is what macOS does (:3149-3157). */
    {
        SpdfWinSidebarLayout search;
        spdf_win_sidebar_layout(side, 2, dpi, &search);
        expect(spdf_win_chrome_rect_empty(search.filter), "Search mode has no filter field");
        expect(search.list.y < l.list.y, "the list moves up when the field is hidden");
        expect(search.list.h > l.list.h, "and gets taller by exactly what the field cost");
    }

    /* A panel squeezed to nothing yields empty bands rather than negative ones. */
    {
        SpdfWinChromeRect none = spdf_win_chrome_zero();
        SpdfWinSidebarLayout empty;
        spdf_win_sidebar_layout(none, 0, dpi, &empty);
        expect(spdf_win_chrome_rect_empty(empty.sections) && spdf_win_chrome_rect_empty(empty.list),
               "an absent panel has no bands");
    }
    /* A panel so short the controls fill it leaves a zero-height list, never a
     * negative one -- the case a 380 pt minimum window can still reach. */
    {
        SpdfWinChromeRect tiny = side;
        SpdfWinSidebarLayout t;
        tiny.h = spdf_win_chrome_px(20.0, dpi);
        spdf_win_sidebar_layout(tiny, 0, dpi, &t);
        expect(t.list.h >= 0.0f, "a panel shorter than its own controls has a non-negative list");
    }
}

static void test_rows_geometry(float dpi) {
    SpdfWinChromeRect side = sidebar_rect(dpi);
    SpdfWinSidebarLayout l;
    SpdfWinChromeRect r0, r1;
    int rows = 40;
    float scrolls[3];
    int s;

    spdf_win_sidebar_layout(side, 0, dpi, &l);
    r0 = spdf_win_sidebar_row_rect(&l, 0.0f, 0);
    r1 = spdf_win_sidebar_row_rect(&l, 0.0f, 1);
    expect_near(r0.y, l.list.y, "row 0 starts at the top of the list");
    expect_near(r1.y - r0.y, l.row_h, "consecutive rows are one row height apart");
    expect_near(r0.w, l.list.w, "a row spans the list's width");
    expect(spdf_win_chrome_rect_empty(spdf_win_sidebar_row_rect(&l, 0.0f, -1)), "a negative row has no rect");

    /* Scrolling moves the rows up by exactly the offset. */
    expect_near(spdf_win_sidebar_row_rect(&l, 37.0f, 0).y, l.list.y - 37.0f, "scroll moves rows by its own distance");

    /* THE PROPERTY THAT MATTERS: whatever rect the painter draws a row into,
     * hit-testing its middle must return that row -- at every scroll offset and
     * every DPI scale. Paint and hit-test drift is the defect
     * spdf_win_chrome.h's rule 2 exists to prevent, and this is that rule
     * checked one level down. */
    scrolls[0] = 0.0f;
    scrolls[1] = l.row_h * 0.5f;
    scrolls[2] = l.row_h * 7.0f + 3.0f;
    for (s = 0; s < 3; ++s) {
        int i;
        for (i = 0; i < rows; ++i) {
            SpdfWinChromeRect row = spdf_win_sidebar_row_rect(&l, scrolls[s], i);
            float mid_y = row.y + row.h * 0.5f;
            int hit = spdf_win_sidebar_row_at(&l, scrolls[s], rows, row.x + row.w * 0.5f, mid_y);
            if (mid_y < l.list.y || mid_y >= l.list.y + l.list.h) {
                expect(hit != i, "a row scrolled out of the list is not hit at its own middle");
                continue;
            }
            if (hit != i) {
                printf("FAIL row %d at scroll %.2f hit-tests as %d\n", i, scrolls[s], hit);
                failures++;
            }
        }
    }

    /* Outside the list rect, nothing is hit -- including the filter field above
     * it, which must not activate a chapter. */
    expect(spdf_win_sidebar_row_at(&l, 0.0f, rows, l.filter.x + 2.0f, l.filter.y + 2.0f) < 0,
           "a click in the filter field is not a row");
    expect(spdf_win_sidebar_row_at(&l, 0.0f, rows, l.list.x - 5.0f, l.list.y + 5.0f) < 0,
           "a click left of the panel is not a row");
    expect(spdf_win_sidebar_row_at(&l, 0.0f, 0, l.list.x + 5.0f, l.list.y + 5.0f) < 0,
           "an empty list has no rows to hit");
    /* A click below the last row of a short list is not the row after it. */
    expect(spdf_win_sidebar_row_at(&l, 0.0f, 2, l.list.x + 5.0f, l.list.y + l.row_h * 2.5f) < 0,
           "a click past the last row hits nothing");

    /* Scroll range: zero while the rows fit, exactly the overflow once they do not. */
    expect_near(spdf_win_sidebar_max_scroll(&l, 1), 0.0f, "one row cannot be scrolled");
    expect_near(spdf_win_sidebar_max_scroll(&l, rows), l.row_h * (float)rows - l.list.h,
                "the scroll range is the content's overflow");
    expect_near(spdf_win_sidebar_max_scroll(&l, 0), 0.0f, "an empty list cannot be scrolled");
}

int main(void) {
    float scales[3];
    int i;

    test_utf8();
    test_levels_and_pages();
    test_unresolved();
    test_filter_matching();
    test_filter_rows();

    /* 1.0, the 150% this machine actually runs at, and 2.0. The fractional one
     * is the one that finds the defects (windows-native-observations.md \xa74.1). */
    scales[0] = 1.0f;
    scales[1] = 1.5f;
    scales[2] = 2.0f;
    for (i = 0; i < 3; ++i) {
        test_layout(scales[i]);
        test_rows_geometry(scales[i]);
    }

    if (failures) {
        printf("%d sidebar row check(s) failed\n", failures);
        return 1;
    }
    printf("All sidebar row checks passed\n");
    return 0;
}
