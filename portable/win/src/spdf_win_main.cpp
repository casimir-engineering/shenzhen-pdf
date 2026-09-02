/* ShenzhenPDF for Windows -- entry point.
 *
 *   ShenzhenPDF.exe [--dark] [--page N] <file.pdf>
 *       Opens a window on the continuous scrolling canvas at fit-width.
 *
 *   ShenzhenPDF.exe --render-png [--dark] <file.pdf> <page> <zoom> <out.png>
 *       One page through the core, written 1:1 as a PNG. No window, no window
 *       class, nothing touched in user32. This is the byte-for-byte comparison
 *       path against the macOS renderer.
 *
 *   ShenzhenPDF.exe --render-window-png [options] <file.pdf> <page> <w> <h> <out.png>
 *       The WINDOW's viewport -- the continuous canvas, scrolled and zoomed --
 *       composed into a WIC bitmap of the given size and written as a PNG,
 *       with the geometry it used printed to stdout. This is how Phase 2 is
 *       verified: `prlctl exec` runs in the SYSTEM session with no desktop, so
 *       a scrolled frame that could only be produced by a real window would be
 *       a frame no agent could ever check.
 *
 * PAGE NUMBERS ARE 0-BASED EVERYWHERE. Phase 1 took a 1-based page here while
 * spdf_win_probe took a 0-based one, so the two tools disagreed about which
 * page they had rendered -- the quietest possible way for a pixel comparison
 * to compare the wrong pair of images and pass. The core's own API
 * (spdf_page_size, spdf_render_page_rgba_opts) is 0-based, so that is the one
 * that wins; a human-facing 1-based page indicator is a presentation concern
 * for whoever draws one.
 */
#include "spdf_win_canvas.h"
#include "spdf_win_chrome_model.h" /* the chrome model the window paints */
#include "spdf_win_layout.h" /* SPDF_WIN_PAGE_MARGIN_* for the initial window size */
#include "spdf_win_tabs_app.h" /* the tab model, the session, and the glue to this canvas */
#include "spdf_win_window.h"

#include <math.h>
#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "user32.lib")

/* Local, static and small on purpose. T6 owns the shared UTF-8/UTF-16 helpers
 * in spdf_win_paths.{h,c}; duplicating six lines here rather than taking a
 * cross-track build dependency keeps this binary buildable from its own
 * sources plus the core and T3's two files. */
static char* utf8_from_wide(const wchar_t* w) {
    if (!w) return NULL;
    int need = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    if (need <= 0) return NULL;
    char* out = (char*)malloc((size_t)need);
    if (!out) return NULL;
    if (WideCharToMultiByte(CP_UTF8, 0, w, -1, out, need, NULL, NULL) <= 0) {
        free(out);
        return NULL;
    }
    return out;
}

struct app {
    spdf_document* doc;
    char* path; /* UTF-8, owned; the render workers open their own handle to it */
    spdf_win_canvas* canvas;
    unsigned render_flags;
    /* Applied on the first paint, not at open: the canvas cannot place a page
     * until it knows how big the viewport is, and the viewport is not known
     * until the window has been laid out. -1 once it has been honoured. */
    int pending_page;
    /* Windowed: documents come from the model, and `doc`/`path` stay NULL. */
    spdf_win_tabs* tabs;
    spdf_win_window* window; /* set once the window exists; NULL on the headless paths */
    char window_id[SPDF_WIN_SESSION_ID_MAX];
    wchar_t status[512];
    /* Chrome. Both panels are VISIBLE BY DEFAULT, matching macOS
     * (ShenzhenPDFMac.mm:836-840) -- the widths are 0 here, which asks
     * spdf_win_chrome.h for its defaults (240 and 126.5). Not yet persisted:
     * session.yaml already carries showSidebar and minimapWidth and they are
     * still passed through untouched. */
    SpdfWinChromeModel chrome;
    SpdfWinChromeTabStore chrome_tabs; /* owns the UTF-16 titles `chrome` borrows */
    int show_sidebar;
    int show_minimap;
    float sidebar_w;
    float minimap_w;
    /* Hover, so the tab strip's close boxes light up. -1 for none, which is what
     * SpdfWinChromeModel documents; kept here rather than recomputed per paint
     * because the pointer's position is not something a paint can ask for. */
    int hot_tab;
    int hot_close;
    /* The gesture in progress, and where the pointer last was. The WINDOW holds
     * the capture; the app holds the meaning, because whether a drag pans the
     * document or resizes a panel depends on where it started -- see
     * spdf_win_chrome_actions.h. SPDF_WIN_CA_NONE when no button is down. */
    spdf_win_chrome_action drag;
    float drag_last_x;
    float drag_last_y;
    /* The tab being dragged to a new position and the insertion slot under the
     * pointer, or -1 for neither. Both go straight into the chrome model, whose
     * fields of the same names document them and say why the drop indicator is
     * not drawn yet. */
    int drag_tab;
    int drop_slot;
    /* THE THREE TYPEABLE FIELDS and which of them has the keyboard.
     *
     * Here rather than in the chrome model because they are the app's state,
     * not a description of a frame: the model is rebuilt from scratch every
     * paint (spdf_win_chrome_scene.h) and a query rebuilt every paint would be
     * an empty query. The model borrows the page text and the focus from these.
     *
     * The find query is ALSO pushed to the process-wide find session
     * (spdf_win_find_set_query) and the filter to the panel content bridge
     * (spdf_win_chrome_content_set_filter); those two calls are what replaced the
     * SPDF_FIND_QUERY / SPDF_FIND_REGEX / SPDF_SIDEBAR_FILTER environment
     * bridges. Each caret is an index into its own buffer, in wchar_t. */
    int focus; /* spdf_win_text_focus */
    wchar_t find_text[256];
    int find_caret;
    int find_regex;
    wchar_t page_text[16];
    int page_caret;
    wchar_t filter_text[128];
    int filter_caret;
    /* How many rows the sidebar's list drew last frame, so the input router can
     * work out which one a click landed on without resolving the content
     * provider on the pointer's path. */
    int sidebar_rows;
    /* The menu bar (an HMENU), owned by the window once it is installed. NULL on
     * every headless path, where nothing calls spdf_win_menu_create(). */
    void* menu;
    /* The scroll fraction the thumb had when a scroller drag was armed. A thumb
     * drag is absolute -- press position plus total pointer travel -- rather
     * than an accumulation of per-move deltas, so this is the only extra state
     * it needs, and drag_last_x/y stay pinned to the press for it. */
    float drag_scroll_pos;
};

static void report(const wchar_t* text, bool interactive) {
    fwprintf(stderr, L"ShenzhenPDF: %s\n", text);
    if (interactive) MessageBoxW(NULL, text, L"ShenzhenPDF", MB_OK | MB_ICONERROR);
}

static bool open_document(app* a, const wchar_t* wpath, int page_index, bool interactive) {
    char err[256] = {0};
    wchar_t message[600];

    a->path = utf8_from_wide(wpath);
    if (!a->path) {
        report(L"That path could not be converted to UTF-8.", interactive);
        return false;
    }
    a->doc = spdf_open(a->path, err, sizeof(err));
    if (!a->doc) {
        _snwprintf_s(message, _TRUNCATE, L"Could not open %s\n\n%hs", wpath, err[0] ? err : "unknown error");
        report(message, interactive);
        return false;
    }

    int pages = spdf_page_count(a->doc);
    if (page_index < 0 || page_index >= pages) {
        _snwprintf_s(message, _TRUNCATE, L"Page %d is outside this document (0-%d).", page_index, pages - 1);
        report(message, interactive);
        return false;
    }

    /* The canvas reads page 0's size and nothing else. Every other page is
     * measured when the viewport reaches it, so opening a 500-page document
     * costs the same as opening a 2-page one. The path goes with it so the
     * render workers can open their own handle -- the core allows one
     * spdf_document per thread, so they cannot borrow ours. */
    a->canvas = spdf_win_canvas_create(a->doc, a->path, a->render_flags, err, sizeof(err));
    if (!a->canvas) {
        _snwprintf_s(message, _TRUNCATE, L"Could not lay out %s: %hs", wpath, err[0] ? err : "unknown error");
        report(message, interactive);
        return false;
    }
    return true;
}

static void close_document(app* a) {
    spdf_win_canvas_destroy(a->canvas);
    a->canvas = NULL;
    if (a->doc) spdf_close(a->doc);
    a->doc = NULL;
    free(a->path);
    a->path = NULL;
}

/* macOS titles the window "<display name> - Shenzhen PDF", and the bare product
 * name with no document (ShenzhenPDFMac.mm:8615, :10582; :8985, :9168). Same two
 * strings here, so the two apps read alike in a task switcher -- and so the title
 * stops naming the launch document forever, which is what it did while
 * CreateWindowExW's argument was the only title a session ever got.
 *
 * The display name is the tab's own title, i.e. the path's last component. macOS
 * also strips a known extension (spdf_display_label_without_extension) and
 * disambiguates two tabs with the same leaf (SPDFMacSupport.mm:18-31, :82); both
 * are shared display-name helpers the tab strip needs too and neither exists on
 * Windows yet, so a Windows title still carries the ".pdf". */
static void sync_window_title(app* a) {
    wchar_t wide[288], title[320];
    int index = a->tabs ? spdf_win_tabs_selected_index(a->tabs) : -1;
    const char* name = index < 0 ? NULL : spdf_win_tabs_title(a->tabs, index);
    if (!a->window) return;
    /* MB_ERR_INVALID_CHARS: a title is cosmetic, so malformed UTF-8 degrades to the
     * product name rather than to U+FFFD confetti. */
    if (name && *name &&
        MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, name, -1, wide, (int)(sizeof(wide) / sizeof(wide[0]))) > 0)
        _snwprintf_s(title, _TRUNCATE, L"%s - Shenzhen PDF", wide);
    else
        _snwprintf_s(title, _TRUNCATE, L"Shenzhen PDF");
    spdf_win_window_set_title(a->window, title);
}

/* Point the canvas at the newly selected tab AND retitle the window: every
 * caller wants both, and doing only the first is the defect being fixed. */
static int show_selected_tab(app* a) {
    int shown = spdf_win_tabs_app_show(a->tabs, &a->canvas, a->render_flags, &a->pending_page);
    sync_window_title(a);
    return shown;
}

/* --- the window ---------------------------------------------------------- */

/* scene_for_window() -- the paint-time glue -- and the mouse routing. Both
 * depend on `struct app` and on show_selected_tab() above them, and both stay
 * out of this file because this file is at its 500-line cap and
 * tools/file-size-limits.md asks for an extracted file rather than a raised one.
 * Same arrangement as spdf_win_tabs_app.h and spdf_win_headless_viewport.h.
 *
 * The scene half comes FIRST: the input half calls two of its functions. */
#include "spdf_win_chrome_scene.h"
/* The tab strip's own commands -- select, close, open, the overflow menu and
 * drag-to-reorder -- which chrome_perform() next door calls. */
#include "spdf_win_chrome_tabs_ui.h"
/* What the pointer does over the PAGE: select text, follow a link, or pan. */
#include "spdf_win_chrome_canvas_ui.h"
/* The find group, which field has the keyboard, and the sidebar's rows. */
#include "spdf_win_chrome_field_ui.h"
#include "spdf_win_chrome_actions.h"
/* The keymap, the three typeable fields and the one command switch. LAST,
 * because it calls into all three above it. */
#include "spdf_win_chrome_commands.h"

/* THE WINDOW'S OPENING SIZE, AND ITS FLOOR.
 *
 * This used to derive the size from page 0 at 100% -- page width plus margins,
 * shrunk to fit the work area, with NO minimum. On golden.pdf that opens a
 * 244 x 286 window: narrower than its own caption buttons, and far narrower
 * than the 84 pt of chrome the window now has to hold. macOS never did this. It
 * opens every document window at a fixed 1120 x 800 and clamps a restored size
 * into [560 … min(2200, screenW − 40)] x [380 … min(1600, screenH − 40)]
 * (ShenzhenPDFMac.mm:2912-2938, :69-70, :189-196), so a small page gets a
 * normal window with a small page in it rather than a window the size of the
 * page. The constants live in spdf_win_chrome.h with the rest of the metrics.
 *
 * The floor is enforced twice, deliberately: here, so the window opens above it,
 * and in WM_GETMINMAXINFO, so the user cannot drag below it afterwards. Only the
 * second is load-bearing against a user; the first is what stops the app from
 * doing it to itself.
 *
 * Done before the window exists, so it uses the system DPI; WM_DPICHANGED
 * corrects anything the real monitor disagrees with. */
#define SPDF_WIN_RESTORE_MAX_W 2200.0f /* :189-196 */
#define SPDF_WIN_RESTORE_MAX_H 1600.0f
#define SPDF_WIN_SCREEN_INSET 40.0f

static float clamp_content(float want, float lo, float hi, float screen) {
    float top = screen - SPDF_WIN_SCREEN_INSET;
    if (top < hi) hi = top;
    if (hi < lo) hi = lo; /* a screen too small to satisfy both: the floor wins */
    if (want < lo) want = lo;
    if (want > hi) want = hi;
    return want;
}

static void initial_client_size(int* out_w, int* out_h) {
    RECT work = {0, 0, 1280, 800};
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    *out_w = (int)clamp_content((float)SPDF_WIN_CHROME_DEFAULT_CONTENT_W, (float)SPDF_WIN_CHROME_MIN_CONTENT_W,
                                SPDF_WIN_RESTORE_MAX_W, (float)(work.right - work.left));
    *out_h = (int)clamp_content((float)SPDF_WIN_CHROME_DEFAULT_CONTENT_H, (float)SPDF_WIN_CHROME_MIN_CONTENT_H,
                                SPDF_WIN_RESTORE_MAX_H, (float)(work.bottom - work.top));
}

/* --- headless ------------------------------------------------------------ */

#include "spdf_win_headless_viewport.h"

/* Depends on `app` and spdf_win_d2d above, so it is included here rather
 * than with the headers at the top. */
#include "spdf_win_headless.h"

static int usage(void) {
    fwprintf(stderr,
             L"usage: ShenzhenPDF.exe [--dark] [--page N] <file.pdf>\n"
             L"       ShenzhenPDF.exe --render-png [--dark] <file.pdf> <page> <zoom> <out.png>\n"
             L"       ShenzhenPDF.exe --render-window-png [opts] <file.pdf> <page> <w> <h> <out.png>\n"
             L"\n"
             L"  <page> is 0-BASED, matching the core API and spdf_win_probe.\n"
             L"  opts:  --dark            dark reading theme, images preserved\n"
             L"         --fit MODE        width (default) | height | page | actual\n"
             L"         --zoom Z          device pixels per PDF point; overrides --fit\n"
             L"         --scroll-x X      viewport pixels, added to the top of <page>\n"
             L"         --scroll-y Y\n"
             L"         --dpi S           device pixels per logical pixel (default 1)\n"
             L"         --zoom-at X,Y     zoom about this viewport point after scrolling\n"
             L"         --zoom-factor F   how much to zoom there (default 2)\n"
             L"         --frames N        render N frames, a viewport apart; last is written\n"
             L"         --chrome          compose the tab strip, toolbar, sidebar and minimap too\n"
             L"         --find Q          run a search for Q, so the frame shows the find chrome\n"
             L"         --find-regex      treat Q as a regular expression\n");
    return 64;
}

int main(void) {
    int argc = 0;
    wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv) return 70;

    app a;
    viewport_opts opts;
    int window_page = 0;
    memset(&a, 0, sizeof(a));
    memset(&opts, 0, sizeof(opts));
    a.render_flags = SPDF_RENDER_DEFAULT;
    /* Both side panels open, as macOS does for a new document
     * (ShenzhenPDFMac.mm:836-840). 0 width asks spdf_win_chrome.h for
     * its default. */
    a.show_sidebar = 1;
    a.show_minimap = 1;
    /* -1, not the 0 the memset left: 0 is a valid tab index, so a zeroed hover
     * state would draw the first tab hovered before the pointer has ever
     * entered the window. */
    a.hot_tab = -1;
    a.hot_close = -1;
    /* -1 for the same reason: 0 is a valid tab index and a valid drop slot, so a
     * zeroed drag state is a drag nobody started. */
    a.drag_tab = -1;
    a.drop_slot = -1;
    opts.mode = SPDF_WIN_ZOOM_FIT_WIDTH;
    opts.dpi_scale = 1.0f;
    opts.zoom_at_x = -1.0f;
    opts.zoom_factor = 2.0f;
    opts.frames = 1;

    int i = 1;
    bool exact = i < argc && wcscmp(argv[i], L"--render-png") == 0;
    bool viewport = i < argc && wcscmp(argv[i], L"--render-window-png") == 0;
    if (exact || viewport) ++i;

    for (; i < argc && argv[i][0] == L'-'; ++i) {
        const wchar_t* flag = argv[i];
        const wchar_t* value = i + 1 < argc ? argv[i + 1] : NULL;
        if (wcscmp(flag, L"--dark") == 0) {
            a.render_flags |= SPDF_RENDER_DARK_THEME | SPDF_RENDER_PRESERVE_IMAGES;
            continue;
        }
        /* Valueless, like --dark. Composes the window chrome into the headless
         * frame, so the whole window's pixels can be compared without a desktop. */
        if (wcscmp(flag, L"--chrome") == 0) {
            opts.chrome = 1;
            continue;
        }
        /* Valueless, like --chrome; pairs with --find below. */
        if (wcscmp(flag, L"--find-regex") == 0) {
            a.find_regex = 1;
            continue;
        }
        if (!value) return usage();
        /* THE HEADLESS ROUTE TO A LIVE SEARCH, and the reason it exists.
         *
         * SPDF_FIND_QUERY used to be the only way to see the find chrome in a
         * frame, and this change deletes it -- the field is typeable now, and a
         * debugging hook that bypasses the real control is a hook that keeps
         * working after the real control has broken. But the session on this
         * machine can be locked, and then `--render-window-png --chrome` is the
         * ONLY way anyone can look at the window at all, so deleting the bridge
         * without replacing it would take the find chrome out of the one
         * verification path this port has.
         *
         * So it is a FLAG rather than an environment variable, and it goes
         * through spdf_win_find_set_query() -- the same function a keystroke
         * calls, on the same buffer, with the same conversion. It exercises the
         * real path instead of going round it. */
        if (wcscmp(flag, L"--find") == 0) wcsncpy_s(a.find_text, value, _TRUNCATE);
        else if (wcscmp(flag, L"--page") == 0) window_page = _wtoi(value);
        else if (wcscmp(flag, L"--zoom") == 0) opts.zoom = (float)_wtof(value);
        else if (wcscmp(flag, L"--scroll-x") == 0) opts.scroll_x = (float)_wtof(value);
        else if (wcscmp(flag, L"--scroll-y") == 0) opts.scroll_y = (float)_wtof(value);
        else if (wcscmp(flag, L"--dpi") == 0) opts.dpi_scale = (float)_wtof(value);
        else if (wcscmp(flag, L"--zoom-factor") == 0) opts.zoom_factor = (float)_wtof(value);
        else if (wcscmp(flag, L"--frames") == 0) opts.frames = _wtoi(value);
        else if (wcscmp(flag, L"--zoom-at") == 0) {
            wchar_t* comma = NULL;
            opts.zoom_at_x = (float)wcstod(value, &comma);
            opts.zoom_at_y = comma && *comma == L',' ? (float)wcstod(comma + 1, NULL) : 0.0f;
        } else if (wcscmp(flag, L"--fit") == 0) {
            if (wcscmp(value, L"width") == 0) opts.mode = SPDF_WIN_ZOOM_FIT_WIDTH;
            else if (wcscmp(value, L"height") == 0) opts.mode = SPDF_WIN_ZOOM_FIT_HEIGHT;
            else if (wcscmp(value, L"page") == 0) opts.mode = SPDF_WIN_ZOOM_FIT_PAGE;
            else if (wcscmp(value, L"actual") == 0) opts.mode = SPDF_WIN_ZOOM_ACTUAL;
            else return usage();
        } else {
            return usage();
        }
        ++i; /* consumed the value */
    }

    /* After the whole parse, so --find-regex may come on either side of --find.
     * A no-op with no query: spdf_win_find_set_query(NULL) creates no session. */
    a.find_caret = (int)wcslen(a.find_text);
    chrome_find_push(&a);

    int remaining = argc - i;
    if ((exact && remaining != 4) || (viewport && remaining != 5) || (!exact && !viewport && remaining != 1))
        return usage();

    char err[256] = {0};
    spdf_win_d2d* d2d = spdf_win_d2d_create(err, sizeof(err));
    if (!d2d) {
        wchar_t message[400];
        _snwprintf_s(message, _TRUNCATE, L"Direct2D is unavailable: %hs", err[0] ? err : "unknown error");
        report(message, !exact && !viewport);
        return 71;
    }

    int rc;
    if (exact) {
        float zoom = (float)_wtof(argv[i + 2]);
        if (!(zoom > 0.0f)) zoom = 1.0f;
        rc = run_exact(&a, d2d, argv[i], _wtoi(argv[i + 1]), zoom, argv[i + 3]);
    } else if (viewport) {
        rc = run_viewport(&a, d2d, argv[i], _wtoi(argv[i + 1]), (unsigned)_wtoi(argv[i + 2]),
                          (unsigned)_wtoi(argv[i + 3]), &opts, argv[i + 4]);
    } else {
        char* launch_path = utf8_from_wide(argv[i]);
        spdf_win_enable_dpi_awareness();
        a.tabs = spdf_win_tabs_app_start(launch_path, a.window_id, sizeof(a.window_id));
        free(launch_path);
        if (!spdf_win_tabs_app_show(a.tabs, &a.canvas, a.render_flags, &a.pending_page)) {
            report(L"That document could not be opened.", true);
            rc = 1;
        } else {
            int client_w, client_h;
            if (window_page > 0) a.pending_page = window_page;
            initial_client_size(&client_w, &client_h);

            spdf_win_window* window = spdf_win_window_create(d2d, NULL, client_w, client_h, scene_for_window,
                                                            input_for_window, &a, err, sizeof(err));
            if (!window) {
                wchar_t message[400];
                _snwprintf_s(message, _TRUNCATE, L"Could not create the window: %hs", err);
                report(message, true);
                rc = 72;
            } else {
                /* All of these before the show: no placeholder title, no light
                 * caption, and no window that visibly grows a menu bar. */
                a.window = window;
                sync_window_title(&a);
                /* A NULL menu is not an error. spdf_win_menu_create() returning
                 * NULL means the shell would not give us an HMENU, and a viewer
                 * with no menu bar is still a viewer -- every command it lists
                 * also has an accelerator or a toolbar control. */
                a.menu = spdf_win_menu_create();
                spdf_win_window_set_menu(window, a.menu);
                chrome_sync_menu(&a);
                spdf_win_window_set_dark_frame(window, (a.render_flags & SPDF_RENDER_DARK_THEME) != 0);
                spdf_win_window_show(window);
                rc = spdf_win_window_run(window);
                a.window = NULL;
                /* DestroyWindow destroys the menu attached to the window, so
                 * there is nothing to free here -- only a pointer that must stop
                 * being followed. */
                a.menu = NULL;
                spdf_win_window_destroy(window);
            }
        }
        /* session.yaml, under the shared lock, then close what is still open. */
        spdf_win_tabs_app_finish(a.tabs, a.canvas, a.window_id);
        a.canvas = NULL; /* the model closed it; close_document() must not */
    }

    close_document(&a);
    spdf_win_d2d_destroy(d2d);
    LocalFree(argv);
    return rc;
}
