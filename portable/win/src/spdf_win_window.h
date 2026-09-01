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
/* For spdf_win_chrome_button and spdf_win_chrome_cursor, which the mouse events
 * below carry. Taking them from there rather than declaring a parallel pair here
 * is deliberate: two enums with the same meaning and independent numbering is
 * how a middle click becomes a left click at a layer boundary. It costs nothing
 * -- that header is pure, toolkit-free and header-only -- and it does not make
 * this file know about documents, which is the layering rule it actually has. */
#include "spdf_win_chrome_input.h"

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

/* Input, reduced to the three things a document canvas actually reacts to.
 *
 * The window translates Win32 messages into these and knows nothing else; the
 * caller maps them onto the canvas and knows no Win32. That split is what lets
 * the headless viewport probe drive the same canvas with the same numbers and
 * get the same pixels -- if wheel handling lived next to the scroll offset,
 * there would be no way to reproduce a scrolled frame without a desktop. */
typedef enum spdf_win_input_kind {
    /* dx/dy in device pixels, in CONTENT direction: positive dy means the
     * document moves up, i.e. the reader goes further down the document. */
    SPDF_WIN_INPUT_SCROLL = 0,
    /* Multiply the zoom by `factor`, keeping whatever is under (x, y) put. */
    SPDF_WIN_INPUT_ZOOM = 1,
    /* A raw VK_* in `key`. The caller owns the keymap: which key means
     * "next page" is product policy, not window plumbing. */
    SPDF_WIN_INPUT_KEY = 2,

    /* THE MOUSE, RAW. `button` says which, `x`/`y` where, in CLIENT device
     * pixels -- the space every rect in SpdfWinChromeLayout lives in.
     *
     * These deliberately do NOT say "pan". Drag-to-pan used to be resolved
     * inside this file, which was correct while the whole client area was
     * canvas; it is not correct now that the top 84 pt of it is chrome, because
     * "does this drag pan the document" became a question about where the
     * pointer is, and where anything is is the caller's knowledge. So the window
     * holds the CAPTURE and the caller holds the MEANING -- the same split this
     * file already states for the keymap, one device over. The caller is
     * expected to route these through spdf_win_chrome_input.h.
     *
     * MOUSE_MOVE is sent whether or not a button is down, because hover state is
     * what lights the tab strip's close boxes. A handler that changes nothing
     * must return 0, or every pixel of pointer travel costs a repaint. */
    SPDF_WIN_INPUT_MOUSE_DOWN = 3,
    SPDF_WIN_INPUT_MOUSE_UP = 4,
    SPDF_WIN_INPUT_MOUSE_MOVE = 5,

    /* WM_SETCURSOR, asking which cursor belongs at (x, y). The handler writes
     * `cursor` and MUST return 0: a cursor query happens on every pointer move
     * and must never invalidate. A separate event rather than a value cached
     * from the last MOUSE_MOVE because Windows sends WM_SETCURSOR BEFORE
     * WM_MOUSEMOVE, so a cache would always answer for the previous position --
     * visible as a resize cursor that lags a pixel behind a divider's edge. */
    SPDF_WIN_INPUT_CURSOR = 6
} spdf_win_input_kind;

/* A button-up whose `button` is SPDF_WIN_CB_NONE is a CANCELLED drag, not a
 * release: the capture was taken away (an Alt+Tab, a system modal), and a
 * handler that treats it as a release would finish a gesture the user abandoned.
 * The old code had the same hazard and solved it the same way -- see
 * WM_CAPTURECHANGED in spdf_win_window.cpp. */

#define SPDF_WIN_MOD_CTRL 0x1u
#define SPDF_WIN_MOD_SHIFT 0x2u

typedef struct spdf_win_input {
    spdf_win_input_kind kind;
    float dx;
    float dy;
    float factor;
    float x; /* pointer position in client device pixels */
    float y;
    unsigned key;
    unsigned mods;
    /* Which mouse button, as spdf_win_chrome_button. Mouse events only. */
    int button;
    /* Client area in device pixels at the moment of the event, so a handler
     * can express a page-sized scroll without asking the window anything.
     *
     * NOTE that this is the CLIENT area, not the canvas: the canvas is a
     * sub-rect of it now. A handler that wants the canvas divides the client
     * area with spdf_win_chrome_layout(), the same function the painter uses --
     * which is why dpi_scale is here too. */
    unsigned view_px_w;
    unsigned view_px_h;
    /* Device pixels per logical pixel, so a handler can lay the chrome out the
     * same way the painter did and hit-test against the rects that were actually
     * drawn. Without it a handler would have to guess, and a guessed DPI puts
     * every chrome edge in the wrong place at 150%. */
    float dpi_scale;

    /* --- written by the HANDLER, read by the window ---------------------- */
    /* SPDF_WIN_INPUT_CURSOR only: which cursor belongs at (x, y), as
     * spdf_win_chrome_cursor. Pre-set to SPDF_WIN_CC_ARROW, so a handler that
     * does not care leaves it alone. */
    int cursor;
} spdf_win_input;

/* Return non-zero when the view changed and needs repainting. Returning 0 for
 * a key the caller does not handle is what keeps unhandled keys from costing a
 * full repaint -- and for SPDF_WIN_INPUT_MOUSE_MOVE and _CURSOR, which arrive
 * on every pixel of pointer travel, it is what keeps the pointer from repainting
 * the window continuously.
 *
 * NON-CONST because the mouse and cursor events carry an answer back (see
 * `cursor` above). Nothing else in the struct may be modified. */
typedef int (*spdf_win_input_fn)(void* user, spdf_win_input* input);

/* Process-wide; call once before creating a window. Asks for per-monitor v2
 * DPI awareness and degrades silently on a Windows too old to offer it. */
void spdf_win_enable_dpi_awareness(void);

/* client_px_w/h are the desired CLIENT area in device pixels at the window's
 * initial DPI. Returns NULL and fills err on failure. */
spdf_win_window* spdf_win_window_create(spdf_win_d2d* d2d, const wchar_t* title, int client_px_w, int client_px_h,
                                        spdf_win_scene_fn scene_fn, spdf_win_input_fn input_fn, void* user, char* err,
                                        size_t err_len);
void spdf_win_window_destroy(spdf_win_window* window);

void spdf_win_window_show(spdf_win_window* window);
void spdf_win_window_invalidate(spdf_win_window* window);
float spdf_win_window_dpi_scale(const spdf_win_window* window);

/* THE TWO WINDOW-LEVEL HALVES OF THE READING THEME.
 *
 * Both live here rather than in spdf_win_paint() because both are properties of
 * an HWND, and spdf_win_d2d.h's load-bearing rule is that the compose path never
 * requires one -- the headless PNG probe and WM_PAINT must keep calling the
 * identical function. A title and an OS-drawn frame have no representation in a
 * WIC bitmap, so putting either behind the paint path would buy nothing and cost
 * every pixel test in the port.
 *
 * The title is UTF-16 in: the UTF-8 boundary belongs to whoever owns the
 * document, and this file is *W-only by rule (see the file header). */
void spdf_win_window_set_title(spdf_win_window* window, const wchar_t* title);

/* Ask DWM to draw the caption, border and system menu dark, so `--dark` does not
 * leave a light title bar wrapped around a #121212 canvas. Idempotent; a
 * Windows without the attribute simply keeps its light frame. */
void spdf_win_window_set_dark_frame(spdf_win_window* window, int dark);

/* Runs the message pump until the window closes. Returns WM_QUIT's exit code,
 * which is 0 for a normal close -- the value main() should return. */
int spdf_win_window_run(spdf_win_window* window);

#ifdef __cplusplus
}
#endif

#endif /* SPDF_WIN_WINDOW_H */
