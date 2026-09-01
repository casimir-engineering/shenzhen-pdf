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

/* --- the window ---------------------------------------------------------- */

static int scene_for_window(void* user, spdf_win_scene* scene) {
    app* a = (app*)user;
    SpdfWinChromeLayout chrome_layout;
    if (!a->canvas) return 0; /* the last tab just closed; the pump is exiting */

    /* Chrome first, because it decides how big the canvas is. The model is
     * rebuilt per paint rather than cached: it is a few dozen bytes plus one
     * UTF-16 conversion per tab, and a cached copy is how a closed tab keeps
     * being drawn. `a->chrome_tabs` owns the titles the model borrows and must
     * therefore live as long as the paint, which is why it is a field on `app`
     * rather than a local here. */
    spdf_win_chrome_model_build(&a->chrome, &a->chrome_tabs, a->tabs, (a->render_flags & SPDF_RENDER_DARK_THEME) != 0,
                                a->show_sidebar, a->show_minimap, a->sidebar_w, a->minimap_w);
    scene->chrome = &a->chrome;
    spdf_win_chrome_layout(&a->chrome, scene->client_px_w ? scene->client_px_w : scene->target_px_w,
                           scene->client_px_h ? scene->client_px_h : scene->target_px_h, scene->dpi_scale,
                           &chrome_layout);

    /* The canvas is laid out against the CANVAS REGION, not the client area, so
     * fit-width fits the space the reader can actually see. spdf_win_paint()
     * translates the page rects into that region, so everything downstream keeps
     * working in canvas-local coordinates. */
    spdf_win_canvas_set_viewport(a->canvas, (unsigned)chrome_layout.canvas.w, (unsigned)chrome_layout.canvas.h,
                                 scene->dpi_scale);
    if (a->pending_page > 0) {
        spdf_win_canvas_scroll_to_page(a->canvas, a->pending_page);
        a->pending_page = -1;
    }
    if (spdf_win_canvas_build_scene(a->canvas, scene)) return 1;
    scene->message = a->status[0] ? a->status : NULL;
    return 1;
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

/* The keymap. Deliberately here and not in spdf_win_window.cpp: which key
 * pages forward is product policy, and the window has no business knowing a
 * document exists. */
static int key_for_window(app* a, const spdf_win_input* in) {
    float page_step = (float)in->view_px_h * 0.9f;
    float line = 60.0f;
    float cx = (float)in->view_px_w * 0.5f;
    float cy = (float)in->view_px_h * 0.5f;

    switch (in->key) {
        case VK_DOWN: return spdf_win_canvas_scroll_by(a->canvas, 0.0f, line);
        case VK_UP: return spdf_win_canvas_scroll_by(a->canvas, 0.0f, -line);
        case VK_RIGHT: return spdf_win_canvas_scroll_by(a->canvas, line, 0.0f);
        case VK_LEFT: return spdf_win_canvas_scroll_by(a->canvas, -line, 0.0f);
        case VK_NEXT:
        case VK_SPACE: return spdf_win_canvas_scroll_by(a->canvas, 0.0f, page_step);
        case VK_PRIOR: return spdf_win_canvas_scroll_by(a->canvas, 0.0f, -page_step);
        case VK_HOME: return spdf_win_canvas_scroll_to(a->canvas, 0.0f, 0.0f);
        case VK_END: return spdf_win_canvas_scroll_to(a->canvas, 0.0f, spdf_win_canvas_content_h(a->canvas));
        case VK_OEM_PLUS:
        case VK_ADD: spdf_win_canvas_zoom_at(a->canvas, 1.25f, cx, cy); return 1;
        case VK_OEM_MINUS:
        case VK_SUBTRACT: spdf_win_canvas_zoom_at(a->canvas, 0.8f, cx, cy); return 1;
        case '0':
            if (!(in->mods & SPDF_WIN_MOD_CTRL)) return 0;
            spdf_win_canvas_set_zoom_mode(a->canvas, SPDF_WIN_ZOOM_ACTUAL);
            return 1;
        case '1':
            if (!(in->mods & SPDF_WIN_MOD_CTRL)) return 0;
            spdf_win_canvas_set_zoom_mode(a->canvas, SPDF_WIN_ZOOM_FIT_WIDTH);
            return 1;
        case '2':
            if (!(in->mods & SPDF_WIN_MOD_CTRL)) return 0;
            spdf_win_canvas_set_zoom_mode(a->canvas, SPDF_WIN_ZOOM_FIT_PAGE);
            return 1;
        /* Ctrl+Tab / Ctrl+W. Where the reader is in the tab being left is
         * written back first, so returning to it lands on the same page. */
        case VK_TAB:
            if (!(in->mods & SPDF_WIN_MOD_CTRL)) return 0;
            spdf_win_tabs_app_remember(a->tabs, a->canvas);
            spdf_win_tabs_select_relative(a->tabs, (in->mods & SPDF_WIN_MOD_SHIFT) ? -1 : 1);
            return show_selected_tab(a);
        case 'W':
            if (!(in->mods & SPDF_WIN_MOD_CTRL)) return 0;
            if (!spdf_win_tabs_close_enabled(spdf_win_tabs_count(a->tabs), spdf_win_tabs_selected_index(a->tabs),
                                             a->canvas != NULL))
                return 0;
            spdf_win_tabs_close(a->tabs, spdf_win_tabs_selected_index(a->tabs), 0);
            if (spdf_win_tabs_count(a->tabs) == 0) PostQuitMessage(0);
            return show_selected_tab(a);
        default: return 0;
    }
}

static int input_for_window(void* user, const spdf_win_input* in) {
    app* a = (app*)user;
    if (!a->canvas) return 0;
    switch (in->kind) {
        case SPDF_WIN_INPUT_SCROLL: return spdf_win_canvas_scroll_by(a->canvas, in->dx, in->dy);
        case SPDF_WIN_INPUT_ZOOM: spdf_win_canvas_zoom_at(a->canvas, in->factor, in->x, in->y); return 1;
        case SPDF_WIN_INPUT_KEY: return key_for_window(a, in);
        default: return 0;
    }
}

/* Page 1 at 100%, shrunk to a comfortable share of the work area. Done before
 * the window exists, so it uses the system DPI; WM_DPICHANGED corrects
 * anything the real monitor disagrees with. */
static void initial_client_size(spdf_document* doc, int* out_w, int* out_h) {
    RECT work = {0, 0, 1280, 800};
    float page_w = 612.0f;
    float page_h = 792.0f;
    char err[128];

    spdf_page_size(doc, 0, &page_w, &page_h, err, sizeof(err)); /* already cached by the canvas */
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);

    float w = page_w + 2.0f * (float)SPDF_WIN_PAGE_MARGIN_H;
    float h = page_h + 2.0f * (float)SPDF_WIN_PAGE_MARGIN_V;
    float scale = 1.0f;
    if (w > (float)(work.right - work.left) * 0.80f) scale = (float)(work.right - work.left) * 0.80f / w;
    if (h > (float)(work.bottom - work.top) * 0.90f && (float)(work.bottom - work.top) * 0.90f / h < scale)
        scale = (float)(work.bottom - work.top) * 0.90f / h;
    *out_w = (int)(w * scale);
    *out_h = (int)(h * scale);
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
             L"         --fit MODE        width (default) | page | actual\n"
             L"         --zoom Z          device pixels per PDF point; overrides --fit\n"
             L"         --scroll-x X      viewport pixels, added to the top of <page>\n"
             L"         --scroll-y Y\n"
             L"         --dpi S           device pixels per logical pixel (default 1)\n"
             L"         --zoom-at X,Y     zoom about this viewport point after scrolling\n"
             L"         --zoom-factor F   how much to zoom there (default 2)\n"
             L"         --frames N        render N frames, a viewport apart; last is written\n"
             L"         --chrome          compose the tab strip, toolbar, sidebar and minimap too\n");
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
        if (!value) return usage();
        if (wcscmp(flag, L"--page") == 0) window_page = _wtoi(value);
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
            else if (wcscmp(value, L"page") == 0) opts.mode = SPDF_WIN_ZOOM_FIT_PAGE;
            else if (wcscmp(value, L"actual") == 0) opts.mode = SPDF_WIN_ZOOM_ACTUAL;
            else return usage();
        } else {
            return usage();
        }
        ++i; /* consumed the value */
    }

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
            int selected = spdf_win_tabs_selected_index(a.tabs);
            if (window_page > 0) a.pending_page = window_page;
            initial_client_size((spdf_document*)spdf_win_tabs_document(a.tabs, selected, err, sizeof(err)), &client_w,
                                &client_h);

            spdf_win_window* window = spdf_win_window_create(d2d, NULL, client_w, client_h, scene_for_window,
                                                            input_for_window, &a, err, sizeof(err));
            if (!window) {
                wchar_t message[400];
                _snwprintf_s(message, _TRUNCATE, L"Could not create the window: %hs", err);
                report(message, true);
                rc = 72;
            } else {
                /* Both before the show: no placeholder title, no light caption. */
                a.window = window;
                sync_window_title(&a);
                spdf_win_window_set_dark_frame(window, (a.render_flags & SPDF_RENDER_DARK_THEME) != 0);
                spdf_win_window_show(window);
                rc = spdf_win_window_run(window);
                a.window = NULL;
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
