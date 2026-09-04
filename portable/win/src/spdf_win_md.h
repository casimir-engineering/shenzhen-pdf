/* spdf_win_md.h -- Markdown on Windows: the open seam, the text size, the
 * settings key, and the process-wide options every document handle shares.
 *
 * THE ONE CALL. Every place the frontend opens a document by path --
 * spdf_win_main.cpp's open_document(), spdf_win_tabs_app.h's hook, the render
 * workers in spdf_win_render.c, the search worker, the thumbnail strip, the
 * print job -- calls spdf_open(path). Each of those becomes
 * spdf_win_md_open_any(path): a Markdown path goes to the core's
 * spdf_open_markdown() with THIS module's options, anything else goes to
 * spdf_open() exactly as before. One identifier per site, no other change,
 * which is what lets the eight sites (owned by other tracks) be patched
 * mechanically and stay behaviour-identical for every non-Markdown file.
 *
 * WHY THE OPTIONS ARE PROCESS-WIDE. The core allows one spdf_document per
 * thread, so a Markdown tab is open several times at once -- the canvas, its
 * render workers, the search worker, the thumbnail strip each hold a handle
 * opened from the same path. They MUST agree on the pagination, or a search
 * hit's page number would not be the page the canvas shows. Text size and the
 * remote-image cache are therefore module state read at open time, never per
 * handle, and a change to either bumps a generation so a long-lived worker
 * handle can tell it is stale (spdf_win_md_options_generation()).
 *
 * TEXT SIZE. The A-/A+ pill scales the body text; the value is persisted as
 * settings.yaml "markdownFontScale", the key macOS writes (ShenzhenPDFMac.mm
 * :1811), clamped to [0.5, 3.0] and stepped by 10%. Applying a change means
 * reopening the document at the new em -- the frontend calls
 * spdf_win_md_text_scale_step() and then re-shows the selected tab, the same
 * path a tab switch takes (show_selected_tab), which rebuilds the canvas and
 * its workers over a fresh handle.
 *
 * THE DARK THEME NEEDS NOTHING HERE. spdf_open_markdown lays out both
 * renditions and the core picks the dark one under SPDF_RENDER_DARK_THEME, the
 * flag the reader already toggles for PDFs; print, export and Copy Page pass
 * no flag and get the light rendition, satisfying spdf_win_export.h's rule
 * without a Markdown special case anywhere.
 *
 * Header-only C API (this is a .cpp module for the Win32 calls); pure parts
 * -- the settings JSON merge, the option assembly, the extension dispatch --
 * are exposed so portable/win/tests/md_win_test.c can pin them without a
 * window, a settings directory or a document.
 */
#ifndef SPDF_WIN_MD_H
#define SPDF_WIN_MD_H

#include "shenzhen_pdf_core.h"

#ifdef __cplusplus
extern "C" {
#endif

/* The settings.yaml key, byte for byte the macOS name. */
#define SPDF_WIN_MD_SETTINGS_KEY "markdownFontScale"
#define SPDF_WIN_MD_SCALE_MIN 0.5f
#define SPDF_WIN_MD_SCALE_MAX 3.0f
#define SPDF_WIN_MD_SCALE_STEP 0.1f

/* --- the open seam ---------------------------------------------------------- */

/* spdf_open() for everything but .md/.markdown, which open through
 * spdf_open_markdown() with the process options. Same contract as spdf_open:
 * NULL with err filled on failure. */
spdf_document* spdf_win_md_open_any(const char* utf8_path, char* err, size_t err_len);

/* --- options ---------------------------------------------------------------- */

/* The options the next open will use: text scale from this module, the dark
 * rendition on, the remote-image cache hooked up (spdf_win_md_images.h). */
void spdf_win_md_options(spdf_markdown_options* out);

/* Bumped on every change to the options. A worker that cached a handle
 * compares this with the value it saw at open and reopens on mismatch. */
unsigned spdf_win_md_options_generation(void);

/* Say the options changed for a reason this module does not own -- today the
 * per-fence language overrides in spdf_win_md_code.h. Same contract as a text
 * scale change: the next open paginates differently, so every handle has to be
 * remade, and the generation is how a long-lived one finds out. */
void spdf_win_md_bump_options(void);

/* --- text size -------------------------------------------------------------- */

float spdf_win_md_text_scale(void);
/* Clamp into [0.5, 3.0]; NaN or non-positive resets to 1.0. Bumps the
 * generation when the value actually changes. */
void spdf_win_md_set_text_scale(float scale);
/* One A+ (+1) or A- (-1) press: 10% of the base size, clamped. Returns 1 when
 * the scale changed, 0 at a limit -- the caller reopens only on 1. */
int spdf_win_md_text_scale_step(int direction);

/* --- persistence ------------------------------------------------------------- */

/* Read "markdownFontScale" from settings.yaml into the module (1.0 when the
 * file or key is absent). Returns 1 when a value was read. */
int spdf_win_md_load_settings(void);
/* Merge the current scale into settings.yaml, preserving every other key.
 * Refuses (returns 0) when the file exists but could not be read, exactly as
 * spdf_win_state_write_json does: never overwrite unknown contents. */
int spdf_win_md_save_settings(void);

/* Pure halves of the two calls above, for tests. `settings_json` is the
 * compact JSON spdf_win_state_read_json returns (NULL or "" = no file). */
float spdf_win_md_settings_scale(const char* settings_json);
/* The JSON with the key set to `scale` (two decimals, the macOS rounding):
 * replaced in place when present, appended when absent, "{...}" created from
 * nothing. Caller frees; NULL on allocation failure. */
char* spdf_win_md_settings_with_scale(const char* settings_json, float scale);

#ifdef __cplusplus
}
#endif

#endif /* SPDF_WIN_MD_H */
