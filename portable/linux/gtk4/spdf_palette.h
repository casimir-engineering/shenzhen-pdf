// spdf_palette.c — the Ctrl+K command palette (Mac showPaletteWithTitle /
// GTK3 show_favorites_dialog parity): every runnable command from the
// spdf_shortcuts.c table, favorites, recents, and text search across all open
// documents; plus the favorite-page / favorite-document toggle actions.
//
// The filter/snippet helpers at the top are pure glib logic so they can be
// unit-tested without GTK (tests/palette_filter_test.c builds this header and
// spdf_palette.c with SPDF_PALETTE_TESTING, same pattern as spdf_state.c).
#pragma once

#ifdef SPDF_PALETTE_TESTING
#include <glib.h>
#else
#include "spdf_app.h"
#include "spdf_window.h"
#endif

G_BEGIN_DECLS

// Total pages searched across all open documents per palette query (same cap
// as the GTK3 MAX_PALETTE_SEARCH_PAGES and in the same spirit as the Mac
// 220-result cap).
#define SPDF_PALETTE_MAX_SEARCH_PAGES 250
// Text search starts at 2 query bytes (GTK3 parity).
#define SPDF_PALETTE_MIN_TEXT_QUERY_BYTES 2
// At most this many snippet fragments per matching page (Mac parity).
#define SPDF_PALETTE_MAX_SNIPPETS_PER_PAGE 3

// ---------------------------------------------------------------------------
// Pure filter logic (no GTK).

// Fuzzy match score of query against haystack. Returns -1 when the query is
// not a case-insensitive (ASCII) subsequence of haystack; otherwise a score
// >= 0, higher is better. Matching is greedy left-most; each matched byte
// scores +1, +3 more when it sits on a word boundary (start of string or
// preceded by a non-alphanumeric byte), +2 more when it immediately follows
// the previously matched byte (consecutive run). Skipped bytes between the
// first and last match subtract 1 each (capped at 8) and bytes skipped before
// the first match subtract 1 each (capped at 3), so tight, early, word-aligned
// matches outrank scattered ones. An empty query matches everything with 0.
int spdf_palette_fuzzy_score(const char* query, const char* haystack);

// One entry of the command section's input table (built from
// spdf_shortcuts_table() by the palette; faked directly by the tests).
typedef struct {
    const char* action; // detailed action name, e.g. "win.open"
    const char* title;  // human-readable label (fuzzy-matched)
    const char* accel;  // primary accelerator string, NULL when none
    gboolean enabled;   // live GAction enabled state
} SpdfPaletteCommand;

typedef struct {
    int index; // index into the input command array
    int score; // spdf_palette_fuzzy_score of the query against the title
} SpdfPaletteMatch;

// Filters and ranks commands for the palette's Commands section. Disabled
// entries and entries with no title are always skipped. An empty (or NULL)
// query keeps table order; otherwise results are sorted by score descending,
// ties by table order. Returns the number of matches written (at most
// out_max).
int spdf_palette_filter_commands(const SpdfPaletteCommand* commands, int count, const char* query,
                                 SpdfPaletteMatch* out, int out_max);

// Extracts a short display snippet around the first case-insensitive (ASCII)
// occurrence of query in line: up to 24 bytes of context on each side,
// clipped to UTF-8 boundaries, trimmed, with a leading/trailing ellipsis when
// clipped. Returns NULL when query does not occur in line. Caller frees.
char* spdf_palette_snippet_from_line(const char* line, const char* query);

#ifndef SPDF_PALETTE_TESTING
// ---------------------------------------------------------------------------
// Shell entry points (bodies of the win.palette / win.favorite-page /
// win.favorite-document actions registered in spdf_window.c).

void spdf_palette_open(SpdfWindow* win);
void spdf_palette_toggle_favorite_page(SpdfWindow* win);
void spdf_palette_toggle_favorite_document(SpdfWindow* win);
#endif

G_END_DECLS
