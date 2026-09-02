/* spdf_win_find_settings.h — the one setting the search track reads:
 * "searchJumpsToNearestResult".
 *
 * WHAT IT IS. macOS (26.7.9-1): when a search starts, the match the view jumps
 * to is the one NEAREST THE READER'S CURRENT POSITION rather than the first in
 * the document -- "search jumps to the nearest result" in the Settings menu,
 * ShenzhenPDFMac.mm:575 `_searchJumpsToNearestResult = YES` by default, read
 * back from settings at :1194 and consulted at :10653. GTK4 keeps the same key
 * with the same default (spdf_state_internal.h:68, spdf_state.c:550). The
 * nearest-match rule itself is spdf_win_search_nearest_match, already ported.
 *
 * WHERE IT COMES FROM. settings.yaml, through spdf_win_state_read_json -- the
 * existing read API, whose header says the file is "YAML on disk, JSON in
 * memory", so the value is a JSON boolean under that key. Windows has no
 * settings MODEL yet (windows-feature-matrix.md, "Settings persistence"), so
 * this reads the one key it needs, once, and caches the answer; a missing file,
 * a missing key or an unparseable value all mean the default. When a settings
 * struct arrives, this becomes a field read and the scanner goes away.
 *
 * THE SCANNER IS HEADER-ONLY AND PURE so a test can feed it JSON text without a
 * file, a state directory or a registry: the file IO is behind one function in
 * spdf_win_find_settings.cpp.
 */
#ifndef SPDF_WIN_FIND_SETTINGS_H
#define SPDF_WIN_FIND_SETTINGS_H

#include <string.h>

#if defined(_MSC_VER) && !defined(__cplusplus)
#define SPDF_WIN_FS_INLINE __inline
#else
#define SPDF_WIN_FS_INLINE inline
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define SPDF_WIN_FIND_SETTING_NEAREST "searchJumpsToNearestResult"

/* The value of a top-level JSON boolean member, or `fallback` when the key is
 * absent or its value is not `true`/`false`. The same shape as GTK4's
 * json_get_bool (spdf_state.c:200): find the quoted key, skip the colon and
 * whitespace, compare the literal. A key that appears inside a string value
 * cannot be confused with the member, because the member form requires the
 * quote-key-quote-colon sequence and settings.yaml's values are scalars. */
static SPDF_WIN_FS_INLINE int spdf_win_find_json_bool(const char* json, const char* key, int fallback) {
    size_t klen;
    const char* p;
    if (!json || !key || !*key) return fallback;
    klen = strlen(key);
    for (p = strchr(json, '"'); p; p = strchr(p + 1, '"')) {
        const char* v;
        if (strncmp(p + 1, key, klen) != 0 || p[1 + klen] != '"') continue;
        v = p + 2 + klen;
        while (*v == ' ' || *v == '\t' || *v == '\r' || *v == '\n') ++v;
        if (*v != ':') continue;
        ++v;
        while (*v == ' ' || *v == '\t' || *v == '\r' || *v == '\n') ++v;
        if (strncmp(v, "true", 4) == 0) return 1;
        if (strncmp(v, "false", 5) == 0) return 0;
        return fallback;
    }
    return fallback;
}

/* settings.yaml's answer, read once per process and cached; the default (1)
 * when the file has nothing to say. spdf_win_find_settings.cpp. */
int spdf_win_find_jumps_to_nearest(void);

#ifdef __cplusplus
}
#endif

#endif /* SPDF_WIN_FIND_SETTINGS_H */
