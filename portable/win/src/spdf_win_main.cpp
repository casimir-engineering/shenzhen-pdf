/* ShenzhenPDF for Windows -- Phase 1 entry point.
 *
 *   ShenzhenPDF.exe [--dark] <file.pdf>
 *       Opens a window and shows page 1.
 *
 *   ShenzhenPDF.exe --render-png [--dark] <file.pdf> <page> <zoom> <out.png>
 *       Renders that page through the core and writes the compose layer's
 *       output 1:1 as a PNG. No window is created, no window class is
 *       registered, and nothing here touches user32 beyond the message box we
 *       never reach. This is the mode that makes the frontend verifiable from
 *       `prlctl exec`, which runs in the SYSTEM session with no desktop.
 *
 *   ShenzhenPDF.exe --render-window-png [--dark] <file.pdf> <page> <w> <h> <out.png>
 *       Same, but composes the WINDOW's scene -- surround, margin, shadow,
 *       fit-to-target scaling -- into a WIC bitmap of the given size. This is
 *       how the windowed appearance gets checked without a desktop.
 *
 * Phase 1 is page-1-only and synchronous on purpose (windows-port-plan.md sec
 * 4, risk 8): it depends on neither the layout header (T3) nor the worker
 * pool (T5), so it can be finished and proven while those are still being
 * written. Scrolling, tabs and a render queue belong to later phases and are
 * deliberately absent.
 */
#include "spdf_win_window.h"

#include <math.h>
#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "user32.lib")

/* Local, static, and small on purpose. T6 owns the shared UTF-8/UTF-16
 * helpers in spdf_win_paths.{h,c}; duplicating six lines here rather than
 * taking a cross-track build dependency for Phase 1 keeps this binary
 * buildable from its own three sources plus the core. Fold it into T6's
 * helper once the tracks converge. */
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
    int page_index;
    float page_w_pt;
    float page_h_pt;
    unsigned render_flags;

    spdf_bitmap bitmap;
    bool has_bitmap;
    float rendered_zoom;

    wchar_t status[512];
};

/* Fits the page inside `px_w` x `px_h` device pixels, leaving the same 16-dip
 * margin spdf_win_paint() reserves on each side, and never magnifying past
 * 1:1 at the current DPI. Returns points-to-pixels, which is what the core
 * calls zoom. */
static float fit_zoom(const app* a, unsigned px_w, unsigned px_h, float dpi_scale) {
    float s = dpi_scale > 0.0f ? dpi_scale : 1.0f;
    float avail_w = (float)px_w - 32.0f * s;
    float avail_h = (float)px_h - 32.0f * s;
    if (avail_w < 32.0f) avail_w = 32.0f;
    if (avail_h < 32.0f) avail_h = 32.0f;
    if (a->page_w_pt <= 0.0f || a->page_h_pt <= 0.0f) return s;

    float zoom = avail_w / a->page_w_pt;
    if (avail_h / a->page_h_pt < zoom) zoom = avail_h / a->page_h_pt;
    if (zoom > s) zoom = s; /* 100% at this display's scale is the ceiling */
    if (zoom < 0.02f) zoom = 0.02f;
    return zoom;
}

static bool render_at(app* a, float zoom) {
    char err[256] = {0};
    spdf_bitmap fresh;
    memset(&fresh, 0, sizeof(fresh));

    if (!spdf_render_page_rgba_opts(a->doc, a->page_index, zoom, a->render_flags, NULL, &fresh, err, sizeof(err))) {
        _snwprintf_s(a->status, _TRUNCATE, L"Could not render page %d: %hs", a->page_index + 1,
                     err[0] ? err : "unknown error");
        return false;
    }
    if (a->has_bitmap) spdf_free_bitmap(&a->bitmap);
    a->bitmap = fresh;
    a->has_bitmap = true;
    a->rendered_zoom = zoom;
    a->status[0] = L'\0';
    return true;
}

/* The window's pre-paint hook. Phase 1 renders synchronously right here; see
 * the note on spdf_win_scene_fn about what replaces this once T5 lands. */
static int scene_for_window(void* user, spdf_win_scene* scene) {
    app* a = (app*)user;
    float zoom = fit_zoom(a, scene->target_px_w, scene->target_px_h, scene->dpi_scale);

    /* Re-render only on a real zoom change. Without this every expose event
     * would re-rasterize the page, which is both slow and pointless -- and it
     * is why a plain window drag stays smooth even though rendering is
     * synchronous. The 0.5% band absorbs float noise from the fit math. */
    if (!a->has_bitmap || a->rendered_zoom <= 0.0f || fabsf(zoom - a->rendered_zoom) > a->rendered_zoom * 0.005f)
        render_at(a, zoom);

    scene->page = a->has_bitmap ? &a->bitmap : NULL;
    scene->dark = (a->render_flags & SPDF_RENDER_DARK_THEME) != 0;
    scene->message = a->status[0] ? a->status : NULL;
    return 1;
}

static void report(const wchar_t* text, bool interactive) {
    fwprintf(stderr, L"ShenzhenPDF: %s\n", text);
    if (interactive) MessageBoxW(NULL, text, L"ShenzhenPDF", MB_OK | MB_ICONERROR);
}

static bool open_document(app* a, const wchar_t* wpath, int page_number, bool interactive) {
    char err[256] = {0};
    wchar_t message[600];

    char* path = utf8_from_wide(wpath);
    if (!path) {
        report(L"That path could not be converted to UTF-8.", interactive);
        return false;
    }

    a->doc = spdf_open(path, err, sizeof(err));
    free(path);
    if (!a->doc) {
        _snwprintf_s(message, _TRUNCATE, L"Could not open %s\n\n%hs", wpath, err[0] ? err : "unknown error");
        report(message, interactive);
        return false;
    }

    int pages = spdf_page_count(a->doc);
    if (page_number < 1 || (pages > 0 && page_number > pages)) {
        _snwprintf_s(message, _TRUNCATE, L"Page %d is outside this document (%d pages).", page_number, pages);
        report(message, interactive);
        return false;
    }
    a->page_index = page_number - 1;

    /* The only metadata Phase 1 reads. Page 1's size is what decides the
     * initial window size and the fit zoom; anything else -- outline,
     * comments, text -- would be work the first frame does not need, and
     * launch time is the product's headline promise. */
    if (!spdf_page_size(a->doc, a->page_index, &a->page_w_pt, &a->page_h_pt, err, sizeof(err))) {
        _snwprintf_s(message, _TRUNCATE, L"Could not measure page %d: %hs", page_number, err[0] ? err : "unknown");
        report(message, interactive);
        return false;
    }
    return true;
}

static void close_document(app* a) {
    if (a->has_bitmap) spdf_free_bitmap(&a->bitmap);
    a->has_bitmap = false;
    if (a->doc) spdf_close(a->doc);
    a->doc = NULL;
}

static const wchar_t* file_name_of(const wchar_t* path) {
    const wchar_t* name = path;
    for (const wchar_t* p = path; *p; ++p)
        if (*p == L'\\' || *p == L'/') name = p + 1;
    return name;
}

/* Picks an initial client size: page 1 at 100%, shrunk to fit a comfortable
 * share of the work area. Done before the window exists, so it uses the
 * system DPI; WM_DPICHANGED corrects anything the real monitor disagrees
 * with. */
static void initial_client_size(const app* a, int* out_w, int* out_h) {
    RECT work = {0, 0, 1280, 800};
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    float max_w = (float)(work.right - work.left) * 0.80f;
    float max_h = (float)(work.bottom - work.top) * 0.90f;

    float w = a->page_w_pt + 32.0f;
    float h = a->page_h_pt + 32.0f;
    float scale = 1.0f;
    if (w > max_w) scale = max_w / w;
    if (h > max_h && max_h / h < scale) scale = max_h / h;

    *out_w = (int)(w * scale);
    *out_h = (int)(h * scale);
}

static int usage(void) {
    fwprintf(stderr,
             L"usage: ShenzhenPDF.exe [--dark] <file.pdf>\n"
             L"       ShenzhenPDF.exe --render-png [--dark] <file.pdf> <page> <zoom> <out.png>\n"
             L"       ShenzhenPDF.exe --render-window-png [--dark] <file.pdf> <page> <w> <h> <out.png>\n");
    return 64;
}

/* Both headless modes. `zoom` of 0 means "whatever the window would have
 * chosen for a target this size". Returns a process exit code. */
static int run_headless(app* a, spdf_win_d2d* d2d, const wchar_t* wpath, int page_number, spdf_win_fit fit, float zoom,
                        unsigned px_w, unsigned px_h, const wchar_t* out_png) {
    if (!open_document(a, wpath, page_number, false)) return 1;
    if (zoom <= 0.0f) zoom = fit_zoom(a, px_w, px_h, 1.0f);
    if (!render_at(a, zoom)) {
        report(a->status, false);
        return 1;
    }
    if (fit == SPDF_WIN_FIT_EXACT) {
        px_w = (unsigned)a->bitmap.width;
        px_h = (unsigned)a->bitmap.height;
    }

    spdf_win_scene scene;
    memset(&scene, 0, sizeof(scene));
    scene.page = &a->bitmap;
    scene.fit = fit;
    scene.dpi_scale = 1.0f;
    scene.dark = (a->render_flags & SPDF_RENDER_DARK_THEME) != 0;

    HRESULT hr = spdf_win_render_scene_to_png(d2d, px_w, px_h, &scene, out_png);
    if (FAILED(hr)) {
        wchar_t message[256];
        _snwprintf_s(message, _TRUNCATE, L"Compose to %s failed (hr=0x%08lX)", out_png, (unsigned long)hr);
        report(message, false);
        return 1;
    }
    wprintf(L"%s %ux%u\n", out_png, px_w, px_h);
    return 0;
}

int main(void) {
    int argc = 0;
    wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv) return 70;

    app a;
    memset(&a, 0, sizeof(a));
    a.render_flags = SPDF_RENDER_DEFAULT;

    int i = 1;
    bool headless_exact = i < argc && wcscmp(argv[i], L"--render-png") == 0;
    bool headless_window = i < argc && wcscmp(argv[i], L"--render-window-png") == 0;
    if (headless_exact || headless_window) ++i;
    for (; i < argc && argv[i][0] == L'-'; ++i) {
        if (wcscmp(argv[i], L"--dark") == 0)
            a.render_flags |= SPDF_RENDER_DARK_THEME | SPDF_RENDER_PRESERVE_IMAGES;
        else
            return usage();
    }

    int remaining = argc - i;
    if ((headless_exact && remaining != 4) || (headless_window && remaining != 5) ||
        (!headless_exact && !headless_window && remaining != 1))
        return usage();

    char err[256] = {0};
    spdf_win_d2d* d2d = spdf_win_d2d_create(err, sizeof(err));
    if (!d2d) {
        wchar_t message[400];
        _snwprintf_s(message, _TRUNCATE, L"Direct2D is unavailable: %hs", err[0] ? err : "unknown error");
        report(message, !headless_exact && !headless_window);
        return 71;
    }

    int rc;
    if (headless_exact) {
        /* EXACT has no target to fit to, so a missing or nonsense zoom means
         * 100% rather than run_headless's fit-to-target. */
        float zoom = (float)_wtof(argv[i + 2]);
        if (!(zoom > 0.0f)) zoom = 1.0f;
        rc = run_headless(&a, d2d, argv[i], _wtoi(argv[i + 1]), SPDF_WIN_FIT_EXACT, zoom, 0, 0, argv[i + 3]);
    } else if (headless_window) {
        /* zoom 0: let run_headless pick the same fit zoom the window would,
         * so this really is the windowed appearance and not a 100% render
         * shrunk down (which would be blurrier than what ships). */
        rc = run_headless(&a, d2d, argv[i], _wtoi(argv[i + 1]), SPDF_WIN_FIT_CONTAIN, 0.0f,
                          (unsigned)_wtoi(argv[i + 2]), (unsigned)_wtoi(argv[i + 3]), argv[i + 4]);
    } else {
        spdf_win_enable_dpi_awareness();
        if (!open_document(&a, argv[i], 1, true)) {
            rc = 1;
        } else {
            int client_w, client_h;
            initial_client_size(&a, &client_w, &client_h);

            wchar_t title[320];
            _snwprintf_s(title, _TRUNCATE, L"%s \x2014 ShenzhenPDF", file_name_of(argv[i]));

            spdf_win_window* window =
                spdf_win_window_create(d2d, title, client_w, client_h, scene_for_window, &a, err, sizeof(err));
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
