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
#include "spdf_win_layout.h" /* SPDF_WIN_PAGE_MARGIN_* for the initial window size */
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
    wchar_t status[512];
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
    spdf_win_canvas_set_viewport(a->canvas, scene->target_px_w, scene->target_px_h, scene->dpi_scale);
    if (a->pending_page > 0) {
        spdf_win_canvas_scroll_to_page(a->canvas, a->pending_page);
        a->pending_page = -1;
    }
    if (spdf_win_canvas_build_scene(a->canvas, scene)) return 1;
    scene->message = a->status[0] ? a->status : NULL;
    return 1;
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

static const wchar_t* file_name_of(const wchar_t* path) {
    const wchar_t* name = path;
    for (const wchar_t* p = path; *p; ++p)
        if (*p == L'\\' || *p == L'/') name = p + 1;
    return name;
}

/* Page 1 at 100%, shrunk to a comfortable share of the work area. Done before
 * the window exists, so it uses the system DPI; WM_DPICHANGED corrects
 * anything the real monitor disagrees with. */
static void initial_client_size(app* a, int* out_w, int* out_h) {
    RECT work = {0, 0, 1280, 800};
    float page_w = 612.0f;
    float page_h = 792.0f;
    char err[128];

    spdf_page_size(a->doc, 0, &page_w, &page_h, err, sizeof(err)); /* already cached by the canvas */
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

/* Everything --render-window-png can be told. Defaults are the window's own:
 * fit-width, no extra scroll, 96 dpi. */
struct viewport_opts {
    spdf_win_zoom_mode mode;
    float zoom;      /* > 0 overrides the mode */
    float scroll_x;  /* added to the top of `page` */
    float scroll_y;
    float dpi_scale;
    float zoom_at_x; /* < 0 means "no zoom-at step" */
    float zoom_at_y;
    float zoom_factor;
    /* Render N frames, scrolling a viewport height between each. One
     * invocation is one process, so this is the only way to observe anything
     * that is supposed to happen BETWEEN frames -- notably whether the worker
     * pool had the next page ready. Only the last frame is written. */
    int frames;
};

/* One machine-readable block per frame, on stdout. The consumer is a script
 * that crops the macOS reference render to the same source rectangle, so the
 * numbers here are the interface: change them and the comparison silently
 * starts measuring something else. */
static void print_geometry(const char* label, spdf_win_canvas* canvas, const spdf_win_scene* scene) {
    printf("%s viewport=%ux%u zoom=%.6f scroll=%.4f,%.4f content=%.4f,%.4f page=%d cache=%zu sync=%d started=%llu\n",
           label, scene->target_px_w, scene->target_px_h, (double)spdf_win_canvas_zoom(canvas),
           (double)spdf_win_canvas_scroll_x(canvas), (double)spdf_win_canvas_scroll_y(canvas),
           (double)spdf_win_canvas_content_w(canvas), (double)spdf_win_canvas_content_h(canvas),
           spdf_win_canvas_current_page(canvas), spdf_win_canvas_cache_bytes(canvas),
           spdf_win_canvas_sync_renders(canvas), spdf_win_canvas_prefetched(canvas));
    for (int i = 0; i < scene->page_count; ++i) {
        const spdf_win_page_draw* d = &scene->pages[i];
        printf("%s draw page=%d dest=%.4f,%.4f size=%.4f,%.4f bitmap=%dx%d\n", label, d->page_index, (double)d->dest_x,
               (double)d->dest_y, (double)d->dest_w, (double)d->dest_h, d->bitmap ? d->bitmap->width : 0,
               d->bitmap ? d->bitmap->height : 0);
    }
}

static int run_viewport(app* a, spdf_win_d2d* d2d, const wchar_t* wpath, int page_index, unsigned px_w, unsigned px_h,
                        const viewport_opts* opts, const wchar_t* out_png) {
    spdf_win_scene scene;
    HRESULT hr;

    if (px_w == 0 || px_h == 0) {
        report(L"The viewport must have a non-zero width and height.", false);
        return 64;
    }
    if (!open_document(a, wpath, page_index, false)) return 1;

    spdf_win_canvas_set_viewport(a->canvas, px_w, px_h, opts->dpi_scale);
    if (opts->zoom > 0.0f) spdf_win_canvas_set_zoom_at(a->canvas, opts->zoom, 0.0f, 0.0f);
    else spdf_win_canvas_set_zoom_mode(a->canvas, opts->mode);
    /* Anchor on the page, then apply the offset. Expressing the scroll
     * relative to a page rather than in absolute canvas pixels is what makes a
     * case like "the boundary between page 0 and page 1" mean the same thing
     * at every zoom and on every document. */
    spdf_win_canvas_scroll_to_page(a->canvas, page_index);
    spdf_win_canvas_scroll_by(a->canvas, opts->scroll_x, opts->scroll_y);

    memset(&scene, 0, sizeof(scene));
    if (opts->zoom_at_x >= 0.0f) {
        /* Render the pre-zoom scene first so the anchor can be checked: the
         * document point under (zoom_at_x, zoom_at_y) is derivable from these
         * numbers, and must land back on the same viewport pixel afterwards. */
        spdf_win_canvas_build_scene(a->canvas, &scene);
        print_geometry("pre", a->canvas, &scene);
        spdf_win_canvas_zoom_at(a->canvas, opts->zoom_factor, opts->zoom_at_x, opts->zoom_at_y);
        memset(&scene, 0, sizeof(scene));
    }
    spdf_win_canvas_build_scene(a->canvas, &scene);
    print_geometry("frame", a->canvas, &scene);

    /* Extra frames, each a viewport further down, with the pool given a moment
     * to land its prefetch in between -- the wait a real reader's hand supplies
     * for free and a back-to-back loop does not. `sync=` on each frame is the
     * measurement: 0 means every visible page was already in the cache. */
    for (int frame = 1; frame < opts->frames; ++frame) {
        char label[32];
        spdf_win_canvas_scroll_by(a->canvas, 0.0f, (float)px_h);
        spdf_win_canvas_settle(a->canvas, 4000);
        memset(&scene, 0, sizeof(scene));
        spdf_win_canvas_build_scene(a->canvas, &scene);
        _snprintf_s(label, sizeof(label), _TRUNCATE, "frame%d", frame);
        print_geometry(label, a->canvas, &scene);
    }

    hr = spdf_win_render_scene_to_png(d2d, px_w, px_h, &scene, out_png);
    if (FAILED(hr)) {
        wchar_t message[256];
        _snwprintf_s(message, _TRUNCATE, L"Compose to %s failed (hr=0x%08lX)", out_png, (unsigned long)hr);
        report(message, false);
        return 1;
    }
    wprintf(L"wrote %s\n", out_png);
    return 0;
}

/* The 1:1 single-page path. Kept separate from the canvas because its whole
 * value is that nothing has touched the pixels between the core and the PNG. */
static int run_exact(app* a, spdf_win_d2d* d2d, const wchar_t* wpath, int page_index, float zoom,
                     const wchar_t* out_png) {
    spdf_bitmap bitmap;
    spdf_win_scene scene;
    char err[256] = {0};
    wchar_t message[400];
    HRESULT hr;

    if (!open_document(a, wpath, page_index, false)) return 1;
    memset(&bitmap, 0, sizeof(bitmap));
    if (!spdf_render_page_rgba_opts(a->doc, page_index, zoom, a->render_flags, NULL, &bitmap, err, sizeof(err))) {
        _snwprintf_s(message, _TRUNCATE, L"Could not render page %d: %hs", page_index, err[0] ? err : "unknown error");
        report(message, false);
        return 1;
    }

    memset(&scene, 0, sizeof(scene));
    scene.page = &bitmap;
    scene.fit = SPDF_WIN_FIT_EXACT;
    scene.dpi_scale = 1.0f;
    scene.dark = (a->render_flags & SPDF_RENDER_DARK_THEME) != 0;
    int px_w = bitmap.width;
    int px_h = bitmap.height;
    hr = spdf_win_render_scene_to_png(d2d, (unsigned)px_w, (unsigned)px_h, &scene, out_png);
    spdf_free_bitmap(&bitmap);
    if (FAILED(hr)) {
        _snwprintf_s(message, _TRUNCATE, L"Compose to %s failed (hr=0x%08lX)", out_png, (unsigned long)hr);
        report(message, false);
        return 1;
    }
    wprintf(L"wrote %s %dx%d\n", out_png, px_w, px_h);
    return 0;
}

/* --- command line -------------------------------------------------------- */

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
             L"         --frames N        render N frames, a viewport apart; last is written\n");
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
        spdf_win_enable_dpi_awareness();
        a.pending_page = window_page;
        if (!open_document(&a, argv[i], window_page, true)) {
            rc = 1;
        } else {
            int client_w, client_h;
            wchar_t title[320];
            initial_client_size(&a, &client_w, &client_h);
            _snwprintf_s(title, _TRUNCATE, L"%s \x2014 ShenzhenPDF", file_name_of(argv[i]));

            spdf_win_window* window = spdf_win_window_create(d2d, title, client_w, client_h, scene_for_window,
                                                            input_for_window, &a, err, sizeof(err));
            if (!window) {
                wchar_t message[400];
                _snwprintf_s(message, _TRUNCATE, L"Could not create the window: %hs", err);
                report(message, true);
                rc = 72;
            } else {
                spdf_win_window_show(window);
                rc = spdf_win_window_run(window);
                spdf_win_window_destroy(window);
            }
        }
    }

    close_document(&a);
    spdf_win_d2d_destroy(d2d);
    LocalFree(argv);
    return rc;
}
