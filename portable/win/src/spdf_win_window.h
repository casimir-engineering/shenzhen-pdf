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

    /* A MENU ITEM (or an accelerator the caller resolved to one) was chosen.
     * `key` carries the command, already stripped of SPDF_WIN_MENU_ID_BASE. The
     * window does not know what any of them mean -- exactly as it does not know
     * what a key means -- it only knows that WM_COMMAND's low word is a command
     * id and that spdf_win_main.cpp owns the map. */
    SPDF_WIN_INPUT_COMMAND = 7,

    /* One UTF-16 code unit the user TYPED, from WM_CHAR, in `key`. Separate from
     * SPDF_WIN_INPUT_KEY because the two answer different questions: a VK is a
     * key on the keyboard, a WM_CHAR is a character produced by the layout, the
     * dead keys and the IME. Typing "ü" is one WM_CHAR and no VK anybody could
     * name, and typing on a French layout produces different characters from the
     * same VKs -- so a text field that read VKs would work only on the layout it
     * was written on. Control characters below space arrive here too (Windows
     * sends WM_CHAR for Backspace, Tab, Return and Escape); a handler ignores
     * them and acts on the VK instead, which is where the caret keys are anyway.
     *
     * SURROGATE PAIRS arrive as two events. A handler that stores what it
     * receives is correct; one that inspects individual code units is not. */
    SPDF_WIN_INPUT_CHAR = 8,

    /* A file was dropped on the window. `text` is its path, valid only for the
     * duration of the call. One event per file, in the order Windows reports
     * them, so a caller that opens each in a new tab needs no array. */
    SPDF_WIN_INPUT_DROP_FILE = 9,

    /* THE POSITION QUERY: what is at (x, y)? Sent for WM_SETCURSOR, asking
     * which cursor belongs there, and for WM_NCHITTEST, asking whether the point
     * is the app's or the window manager's. The handler writes `cursor` and `nc`
     * and MUST return 0: both queries happen on every pointer move and must
     * never invalidate. A separate event rather than a value cached from the
     * last MOUSE_MOVE because Windows sends WM_SETCURSOR BEFORE WM_MOUSEMOVE, so
     * a cache would always answer for the previous position -- visible as a
     * resize cursor that lags a pixel behind a divider's edge. One event for
     * both questions because they are the same question -- "what is here" --
     * answered by the same routing, and a second kind would be a second switch
     * arm in the caller for no second decision. */
    SPDF_WIN_INPUT_CURSOR = 6
} spdf_win_input_kind;

/* A button-up whose `button` is SPDF_WIN_CB_NONE is a CANCELLED drag, not a
 * release: the capture was taken away (an Alt+Tab, a system modal), and a
 * handler that treats it as a release would finish a gesture the user abandoned.
 * The old code had the same hazard and solved it the same way -- see
 * WM_CAPTURECHANGED in spdf_win_window.cpp. */

/* These three bits are spdf_win_menu.h's SPDF_WIN_ACCEL_* bits, deliberately the
 * same numbers: an input's `mods` is handed straight to
 * spdf_win_menu_command_for_key() with no conversion, and two spellings of the
 * same three flags is one translation function away from a Shift that means
 * Ctrl. */
#define SPDF_WIN_MOD_CTRL 0x1u
#define SPDF_WIN_MOD_SHIFT 0x2u
#define SPDF_WIN_MOD_ALT 0x4u

typedef struct spdf_win_input {
    spdf_win_input_kind kind;
    float dx;
    float dy;
    float factor;
    float x; /* pointer position in client device pixels */
    float y;
    unsigned key;
    unsigned mods;
    /* SPDF_WIN_INPUT_DROP_FILE only: the dropped path, UTF-16, BORROWED and
     * valid only for the duration of the call. */
    const wchar_t* text;
    /* Which mouse button, as spdf_win_chrome_button. Mouse events only. */
    int button;
    /* THE ACCUMULATED CLICK COUNT for a multi-click series: 1, 2, 3, ...
     * MOUSE_DOWN only, and 0 on every other event.
     *
     * Accumulated HERE rather than by the caller because Win32 does not
     * accumulate it and the pieces needed to are all Win32: WM_LBUTTONDBLCLK is
     * the SECOND click of a double, a triple is an ordinary WM_LBUTTONDOWN
     * arriving within GetDoubleClickTime() and SM_CXDOUBLECLK of it, and the
     * timestamp that decides "within" is GetMessageTime(), not a clock the caller
     * has. What a count MEANS -- two selects a word, three selects a block -- is
     * still entirely the caller's, which is the same division this file already
     * states for the keymap. */
    unsigned click_count;
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
    /* SPDF_WIN_INPUT_CURSOR only: the window manager's view of (x, y), as
     * spdf_win_chrome_nc. Pre-set to SPDF_WIN_NC_CLIENT, so a handler that does
     * not care leaves every pixel the app's -- which is exactly the pre-caption
     * behaviour. WM_NCHITTEST turns it into HTCAPTION / HTMINBUTTON /
     * HTMAXBUTTON / HTCLOSE / HTCLIENT; see spdf_win_window_caption.h. */
    int nc;
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

/* Ask DWM to draw the border and system menu dark, so `--dark` does not leave
 * a light frame wrapped around a #121212 canvas. Idempotent; a Windows without
 * the attribute simply keeps its light frame.
 *
 * THE CAPTION ITSELF IS OURS NOW. The client area covers the caption
 * (WM_NCCALCSIZE in spdf_win_window_caption.h) and the tab strip is the title
 * bar, with the three caption buttons drawn by the chrome painter from
 * SpdfWinChromeModel::maximized / caption_hot / caption_pressed. The title is
 * no longer visible anywhere on the window -- macOS's titleVisibility = Hidden
 * -- but spdf_win_window_set_title() still matters: the taskbar and Alt-Tab
 * read it. */
void spdf_win_window_set_dark_frame(spdf_win_window* window, int dark);

/* Does the SYSTEM want dark? 1 dark, 0 light.
 *
 * macOS gets this for free -- the reading theme follows the system appearance,
 * and every AppKit control resolves itself. Windows has no equivalent: the app
 * shipped light unless `--dark` was passed, so on a machine set to dark it was
 * the only bright window on the desktop. Reported from actual use: "it does not
 * respect the system theme".
 *
 * Read from HKCU\...\Themes\Personalize\AppsUseLightTheme, which is the APP
 * theme rather than SystemUsesLightTheme (the taskbar's). A missing value means
 * light, which is what Windows itself assumes.
 *
 * Deliberately NOT in spdf_win_chrome_theme.h. That header's palette is
 * concrete sRGB on purpose, so the chrome is pixel-testable with no desktop; a
 * value read from the registry is unavailable in exactly the environment those
 * tests run in. This function is a WINDOW-layer question -- "what should the app
 * start as" -- and its answer is fed in as the initial state, not consulted
 * during paint.
 *
 * TWO THINGS THE CALLER MUST GET RIGHT, both learned the hard way:
 *
 * 1. ASK BEFORE THE CANVAS EXISTS. spdf_win_canvas takes its render flags AT
 *    CONSTRUCTION and has no setter -- the reading-theme button changes them by
 *    rebuilding the canvas over the same document. Applying the system theme
 *    after spdf_win_tabs_app_show() left the PAGES rendering light while the DWM
 *    caption and the minimap thumbnails, which read the flag later, went dark. A
 *    half-dark window is a worse bug than the one being fixed.
 *
 * 2. WINDOWED PATHS ONLY. --render-png and --render-window-png must not consult
 *    it: their output would start depending on a registry value on whichever
 *    machine runs them, so every pixel comparison in this port would quietly
 *    read the developer's personal setting. That is exactly what
 *    spdf_win_chrome_theme.h refuses to do for colours. --dark and --light both
 *    override, so a case can pin either. */
int spdf_win_system_prefers_dark(void);

/* Opt the process into dark menus and common controls, so a Win32 menu bar and
 * every TrackPopupMenu follow the system instead of staying light. Call once,
 * before any menu is created. Cosmetic and best-effort: on a Windows too old to
 * support it, nothing happens and the menus stay light. */
void spdf_win_enable_dark_menus(void);

/* THE MENU BAR. `hmenu` is an HMENU (spdf_win_menu_create()'s return), and the
 * window takes ownership: DestroyWindow destroys the menu with it.
 *
 * Here rather than inside spdf_win_window_create() because a menu bar is
 * PRODUCT POLICY -- which commands exist is the same kind of knowledge as which
 * key means "next page", and spdf_win_window.h's standing rule is that the
 * window owns neither. This file only hangs the handle on the HWND and turns the
 * WM_COMMAND that comes back into SPDF_WIN_INPUT_COMMAND.
 *
 * IT CHANGES THE CLIENT AREA. A menu bar comes out of the window's height, so
 * this is called BEFORE the window is shown and re-runs the sizing that
 * spdf_win_window_create() did -- otherwise the first document opens in a window
 * one menu bar shorter than every measurement in this port assumes.
 *
 * AND IT DOES NOT COMBINE WITH THE CLIENT-OWNED CAPTION: WM_NCCALCSIZE gives the
 * client the whole top of the frame, so a bar installed here would be painted
 * over the tab strip. Nothing calls this any more; see the note at its
 * definition in spdf_win_window_frame.h before bringing a menu bar back. */
void spdf_win_window_set_menu(spdf_win_window* window, void* hmenu);

/* The HWND, as void*, for the two things that genuinely need one: TrackPopupMenu
 * and IFileOpenDialog both take an owner window.
 *
 * THIS IS NOT A CRACK IN spdf_win_d2d.h's RULE. That rule is that
 * spdf_win_paint() must never require an HWND, which is what keeps the chrome
 * pixel-testable offscreen; it says nothing about a modal dialog, which has no
 * pixels in the render target at all. Nothing on the paint path may call this. */
void* spdf_win_window_native_handle(spdf_win_window* window);

/* Runs the message pump until the window closes. Returns WM_QUIT's exit code,
 * which is 0 for a normal close -- the value main() should return. */
int spdf_win_window_run(spdf_win_window* window);

#ifdef __cplusplus
}
#endif

#endif /* SPDF_WIN_WINDOW_H */
