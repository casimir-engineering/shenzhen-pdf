/* The Win32 shell around spdf_win_paint().
 *
 * This layer is deliberately thin and deliberately DOWNSTREAM of the compose
 * layer. It owns an HWND, an ID2D1HwndRenderTarget and a message pump, and
 * the only thing it does with them is hand the render target to
 * spdf_win_paint(). Nothing about how a page is drawn lives here, which is
 * what keeps the headless probe drawing the same pixels as the window.
 *
 * It also knows nothing about documents. What to draw arrives through a
 * callback the caller supplies, so spdf_win_main.cpp owns the document and
 * this file owns the window, and neither includes the other's header.
 */
#ifndef SPDF_WIN_WINDOW_H
#define SPDF_WIN_WINDOW_H

#include "spdf_win_d2d.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct spdf_win_window spdf_win_window;

/* Called on the UI thread immediately before each paint, with the client area
 * in device pixels and the window's current DPI scale. Fill `scene` and
 * return non-zero; return 0 to paint an empty window. `scene` arrives zeroed
 * except for target_px_w/h and dpi_scale, which are already set and must not
 * be changed.
 *
 * Phase 1 renders synchronously inside this callback. That is a deliberate
 * limitation, not an oversight: it keeps Phase 1 free of any dependency on
 * the worker pool (T5) or the layout header (T3). The moment those land, this
 * callback becomes a lookup in the render cache instead. */
typedef int (*spdf_win_scene_fn)(void* user, spdf_win_scene* scene);

/* Process-wide; call once before creating a window. Asks for per-monitor v2
 * DPI awareness and degrades silently on a Windows too old to offer it. */
void spdf_win_enable_dpi_awareness(void);

/* client_px_w/h are the desired CLIENT area in device pixels at the window's
 * initial DPI. Returns NULL and fills err on failure. */
spdf_win_window* spdf_win_window_create(spdf_win_d2d* d2d, const wchar_t* title, int client_px_w, int client_px_h,
                                        spdf_win_scene_fn scene_fn, void* user, char* err, size_t err_len);
void spdf_win_window_destroy(spdf_win_window* window);

void spdf_win_window_show(spdf_win_window* window);
void spdf_win_window_invalidate(spdf_win_window* window);
float spdf_win_window_dpi_scale(const spdf_win_window* window);

/* Runs the message pump until the window closes. Returns WM_QUIT's exit code,
 * which is 0 for a normal close -- the value main() should return. */
int spdf_win_window_run(spdf_win_window* window);

#ifdef __cplusplus
}
#endif

#endif /* SPDF_WIN_WINDOW_H */
