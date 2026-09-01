/* Direct2D compose layer. See spdf_win_d2d.h for the no-HWND contract.
 *
 * WHY THIS FILE IS C++ WHEN ITS HEADER IS C.
 * The Windows SDK's d2d1.h does not offer callable C bindings. Compiled as C
 * it auto-defines D2D_USE_C_DEFINITIONS, and that branch (d2d1.h:3571-3712 in
 * SDK 10.0.26100.0) contains nothing but `typedef interface ID2D1X ID2D1X;`
 * forward declarations -- no vtable structs, no ID2D1RenderTarget_* macros.
 * Measured, not assumed: compiling a C version of this file produced nine
 * `warning C4013: 'ID2D1RenderTarget_BeginDraw' undefined` diagnostics, i.e.
 * the calls silently degraded into implicit external functions that would
 * have failed to link. dwrite.h is worse -- it uses C++ inheritance
 * (`: public IUnknown`) with no C branch at all.
 * The alternative was hand-transcribing ~70 COM vtable slots in the right
 * order, where one wrong slot is a jump into an arbitrary function pointer.
 * windows-port-plan.md sec 3 already specifies "C++17 compiled with MSVC, the
 * core included as extern "C"", so this file follows the plan's technology
 * decision rather than its file-extension typo. The public header stays
 * C-includable so other tracks' C code is unaffected.
 *
 * ONE D2D CONSTRUCT IS STILL AVOIDED: ID2D1RenderTarget::GetSize/GetPixelSize.
 * The target's pixel size arrives through spdf_win_scene instead, from
 * whoever created the target. Keeps the window and headless paths honest
 * about agreeing on one number.
 */
#include "spdf_win_d2d.h"

#include "spdf_win_chrome_paint.h"

#include <dwrite.h>

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The guest build line (portable/win/guest-build.cmd) passes no libraries and
 * belongs to T0. Declaring the dependency here keeps this track from needing a
 * change in someone else's file. */
#pragma comment(lib, "d2d1.lib")
#pragma comment(lib, "dwrite.lib")
#pragma comment(lib, "windowscodecs.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "user32.lib")

/* Eight is comfortably more than any viewport can show at a usable zoom (the
 * slot margins alone put a floor under a page's on-screen height), so the LRU
 * below effectively never evicts something still on screen. */
#define SPDF_WIN_TEXTURE_SLOTS 8

struct spdf_win_d2d {
    ID2D1Factory* factory;
    IWICImagingFactory* wic;
    IDWriteFactory* dwrite; /* may be NULL: text is a nicety, never a blocker */
    bool co_initialized;

    /* Page-texture cache. WM_PAINT fires far more often than the pages change
     * (every resize, every expose, every scroll of one pixel), and re-uploading
     * multi-MB bitmaps each time is exactly the sort of thing that shows up as
     * a stutter. Keyed on the target too, because an ID2D1Bitmap belongs to the
     * target that created it and dies with it.
     *
     * It holds a handful of entries rather than one because the continuous
     * canvas draws every page the viewport touches -- a boundary between two
     * pages, or three short pages at a low zoom. It is deliberately NOT a byte
     * budget: that is spdf_win_canvas's job (T3's spdf_win_lru), and this is
     * only the GPU-side shadow of whatever that cache is already holding. */
    ID2D1RenderTarget* cache_target;
    struct {
        const unsigned char* src;
        int w;
        int h;
        unsigned long long used;
        ID2D1Bitmap* bitmap;
    } cache[SPDF_WIN_TEXTURE_SLOTS];
    unsigned long long use_counter;
};

template <class T>
static void safe_release(T*& p) {
    if (p) {
        p->Release();
        p = NULL;
    }
}

static void set_err(char* err, size_t err_len, const char* what, HRESULT hr) {
    if (err && err_len) _snprintf_s(err, err_len, _TRUNCATE, "%s failed (hr=0x%08lX)", what, (unsigned long)hr);
}

spdf_win_d2d* spdf_win_d2d_create(char* err, size_t err_len) {
    spdf_win_d2d* d2d;
    HRESULT hr;

    if (err && err_len) err[0] = '\0';
    d2d = (spdf_win_d2d*)calloc(1, sizeof(*d2d));
    if (!d2d) {
        set_err(err, err_len, "calloc", E_OUTOFMEMORY);
        return NULL;
    }

    /* WIC is COM, so someone must initialize it. Doing that here rather than
     * in main() means a console probe that only ever calls into this file
     * needs no ceremony. RPC_E_CHANGED_MODE means the caller already chose a
     * different apartment -- fine, use theirs and do not uninitialize it. */
    hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (SUCCEEDED(hr)) {
        d2d->co_initialized = true;
    } else if (hr != RPC_E_CHANGED_MODE) {
        set_err(err, err_len, "CoInitializeEx", hr);
        free(d2d);
        return NULL;
    }

    hr = D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, &d2d->factory);
    if (FAILED(hr)) {
        set_err(err, err_len, "D2D1CreateFactory", hr);
        spdf_win_d2d_destroy(d2d);
        return NULL;
    }

    hr = CoCreateInstance(CLSID_WICImagingFactory, NULL, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&d2d->wic));
    if (FAILED(hr)) {
        set_err(err, err_len, "CoCreateInstance(WICImagingFactory)", hr);
        spdf_win_d2d_destroy(d2d);
        return NULL;
    }

    /* Deliberately not fatal. A machine with a broken font stack should still
     * show the page; only the status line goes missing. */
    DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
                        reinterpret_cast<IUnknown**>(&d2d->dwrite));
    return d2d;
}

void spdf_win_d2d_destroy(spdf_win_d2d* d2d) {
    if (!d2d) return;
    spdf_win_d2d_release_target(d2d, NULL);
    safe_release(d2d->dwrite);
    safe_release(d2d->wic);
    safe_release(d2d->factory);
    if (d2d->co_initialized) CoUninitialize();
    free(d2d);
}

ID2D1Factory* spdf_win_d2d_factory(spdf_win_d2d* d2d) { return d2d ? d2d->factory : NULL; }
IWICImagingFactory* spdf_win_d2d_wic(spdf_win_d2d* d2d) { return d2d ? d2d->wic : NULL; }

void spdf_win_d2d_release_target(spdf_win_d2d* d2d, ID2D1RenderTarget* target) {
    if (!d2d) return;
    if (target && d2d->cache_target != target) return;
    for (int i = 0; i < SPDF_WIN_TEXTURE_SLOTS; ++i) {
        safe_release(d2d->cache[i].bitmap);
        d2d->cache[i].src = NULL;
        d2d->cache[i].w = 0;
        d2d->cache[i].h = 0;
        d2d->cache[i].used = 0;
    }
    d2d->cache_target = NULL;
}

/* The core hands back straight RGBA, top row first, with alpha pinned to 255
 * for every render that goes through fz_new_pixmap_from_page_number (see
 * copy_pixmap_to_bitmap in shenzhen_pdf_core.c). Direct2D wants BGRA with
 * premultiplied alpha. At alpha 255 premultiplied and straight are the same
 * bytes, so on the normal path this is a channel swap and nothing else; the
 * multiply is there for the region/alpha renders that will arrive later.
 * Returns a malloc'd tightly packed buffer the caller frees. */
static unsigned char* rgba_to_bgra(const spdf_bitmap* page) {
    if (page->width <= 0 || page->height <= 0) return NULL;

    size_t row_bytes = (size_t)page->width * 4u;
    unsigned char* out = (unsigned char*)malloc(row_bytes * (size_t)page->height);
    if (!out) return NULL;

    for (int y = 0; y < page->height; ++y) {
        const unsigned char* src = page->rgba + (size_t)y * (size_t)page->stride;
        unsigned char* dst = out + (size_t)y * row_bytes;
        for (int x = 0; x < page->width; ++x) {
            unsigned a = src[3];
            dst[0] = a == 255 ? src[2] : (unsigned char)((src[2] * a + 127) / 255);
            dst[1] = a == 255 ? src[1] : (unsigned char)((src[1] * a + 127) / 255);
            dst[2] = a == 255 ? src[0] : (unsigned char)((src[0] * a + 127) / 255);
            dst[3] = (unsigned char)a;
            src += 4;
            dst += 4;
        }
    }
    return out;
}

static ID2D1Bitmap* page_texture(spdf_win_d2d* d2d, ID2D1RenderTarget* target, const spdf_bitmap* page) {
    /* A target change invalidates every texture at once -- they belong to the
     * old one. Do that before looking anything up, not after. */
    if (d2d->cache_target && d2d->cache_target != target) spdf_win_d2d_release_target(d2d, NULL);

    int victim = 0;
    for (int i = 0; i < SPDF_WIN_TEXTURE_SLOTS; ++i) {
        if (d2d->cache[i].bitmap && d2d->cache[i].src == page->rgba && d2d->cache[i].w == page->width &&
            d2d->cache[i].h == page->height) {
            d2d->cache[i].used = ++d2d->use_counter;
            return d2d->cache[i].bitmap;
        }
        if (!d2d->cache[i].bitmap) victim = i;
        else if (d2d->cache[victim].bitmap && d2d->cache[i].used < d2d->cache[victim].used) victim = i;
    }

    unsigned char* bgra = rgba_to_bgra(page);
    if (!bgra) return NULL;

    /* 96 dpi so one bitmap pixel is one DIP, which is what makes the EXACT
     * path a true 1:1 blit. Real DPI scaling is applied by the caller when it
     * picks the render zoom, not here. */
    D2D1_BITMAP_PROPERTIES props = D2D1::BitmapProperties(
        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED), 96.0f, 96.0f);

    ID2D1Bitmap* bitmap = NULL;
    HRESULT hr = target->CreateBitmap(D2D1::SizeU((UINT32)page->width, (UINT32)page->height), bgra,
                                      (UINT32)(page->width * 4), &props, &bitmap);
    free(bgra);
    if (FAILED(hr)) return NULL;

    safe_release(d2d->cache[victim].bitmap);
    d2d->cache_target = target;
    d2d->cache[victim].bitmap = bitmap;
    d2d->cache[victim].src = page->rgba;
    d2d->cache[victim].w = page->width;
    d2d->cache[victim].h = page->height;
    d2d->cache[victim].used = ++d2d->use_counter;
    return bitmap;
}

/* One page on the continuous canvas: its separation from the gutter, then the
 * texture stretched over the slot the layout assigned it. Whole-pixel
 * placement, because a half-pixel offset makes D2D resample a blit that should
 * have been exact -- which at fit-width, where the texture is already the slot's
 * size, is the difference between the page's own pixels and a resampled copy of
 * them.
 *
 * `shade` and `border` are the two halves of SPDFMarkdownTheme's
 * drawsPaperShadow seam and exactly one of them is ever non-NULL; the caller
 * decides which, from the theme. */
static void draw_canvas_page(spdf_win_d2d* d2d, ID2D1RenderTarget* target, const spdf_win_scene* scene,
                             const spdf_win_page_draw* draw, ID2D1SolidColorBrush* shade,
                             ID2D1SolidColorBrush* paper, ID2D1SolidColorBrush* border) {
    float s = scene->dpi_scale > 0.0f ? scene->dpi_scale : 1.0f;
    float x = floorf(draw->dest_x + 0.5f);
    float y = floorf(draw->dest_y + 0.5f);
    D2D1_RECT_F dest = D2D1::RectF(x, y, x + floorf(draw->dest_w + 0.5f), y + floorf(draw->dest_h + 0.5f));

    if (shade)
        target->FillRectangle(D2D1::RectF(dest.left - 2.0f * s, dest.top, dest.right + 2.0f * s, dest.bottom + 3.0f * s),
                              shade);

    ID2D1Bitmap* texture = NULL;
    if (draw->bitmap && draw->bitmap->rgba && draw->bitmap->width > 0 && draw->bitmap->height > 0)
        texture = page_texture(d2d, target, draw->bitmap);

    /* No texture yet -- the page is queued, or the render failed. Paper, not a
     * hole: a blank slot of the right size keeps the strip's geometry legible
     * while a render is outstanding, which is the state the whole canvas will
     * live in once T5's async pipeline replaces the synchronous render. */
    if (!texture) {
        if (paper) target->FillRectangle(dest, paper);
    } else {
        target->DrawBitmap(texture, dest, 1.0f, D2D1_BITMAP_INTERPOLATION_MODE_LINEAR, NULL);
    }

    /* AFTER the page content, so the hairline stays crisp at the page edge, and
     * inset half a stroke so the stroke's centreline lands on a device-pixel
     * boundary -- SPDFMacDocumentViewTheme.mm:76-83 draws its
     * NSInsetRect(pageRect, 0.5, 0.5) / lineWidth 1.0 frame for the same two
     * reasons. The stroke is dpi-scaled like every other chrome metric here, so
     * it stays one logical pixel rather than thinning out on a 2x display,
     * which is what makes it a 1 pt border on macOS too. */
    if (border) {
        /* WHOLE device pixels, which is not the same as 1.0f * s.
         *
         * Measured on a 144-dpi display (s = 1.5) on 2026-09-01: a 1.5 px
         * stroke cannot land on the pixel grid whatever it is inset by, so it
         * covers one full row and half of the next. The window's GPU target
         * antialiases that half-covered row (#282828 against #1E1E1E paper)
         * while spdf_win_render_scene_to_png's SOFTWARE target snaps it away --
         * so the border blurred on screen AND the two compose paths stopped
         * agreeing, with a channel delta of 85 on the row inside the frame
         * where every other row matched exactly.
         *
         * Rounding to whole pixels fixes both: the border is crisp, and the
         * windowed and headless paths produce the same pixels, which is what
         * makes an offscreen pixel test evidence about the window.
         *
         * macOS never meets this case -- AppKit backing scales are 1x and 2x,
         * where a 1 pt lineWidth is already 1 or 2 whole pixels. Windows'
         * 125%/150%/175% steps are the reason this needs saying. */
        float w = floorf(s + 0.5f);
        D2D1_RECT_F frame;
        if (w < 1.0f) w = 1.0f;
        frame = D2D1::RectF(dest.left + w * 0.5f, dest.top + w * 0.5f, dest.right - w * 0.5f, dest.bottom - w * 0.5f);
        if (frame.right > frame.left && frame.bottom > frame.top)
            target->DrawRectangle(frame, border, w, NULL);
    }
}

static void draw_message(spdf_win_d2d* d2d, ID2D1RenderTarget* target, const spdf_win_scene* scene) {
    if (!d2d->dwrite || !scene->message || !scene->message[0]) return;

    float s = scene->dpi_scale > 0.0f ? scene->dpi_scale : 1.0f;
    IDWriteTextFormat* format = NULL;
    if (FAILED(d2d->dwrite->CreateTextFormat(L"Segoe UI", NULL, DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STYLE_NORMAL,
                                             DWRITE_FONT_STRETCH_NORMAL, 15.0f * s, L"en-us", &format)))
        return;
    format->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_CENTER);
    format->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER);

    /* DrawTextLayout, not DrawText: <windows.h> #defines DrawText to
     * DrawTextW/DrawTextA, which rewrites the vtable member name. Consistent
     * enough to work today, and a landmine the day someone includes headers in
     * a different order. */
    IDWriteTextLayout* layout = NULL;
    UINT32 len = (UINT32)wcslen(scene->message);
    if (SUCCEEDED(d2d->dwrite->CreateTextLayout(scene->message, len, format, (float)scene->target_px_w,
                                                (float)scene->target_px_h, &layout))) {
        ID2D1SolidColorBrush* brush = NULL;
        D2D1_COLOR_F ink = scene->dark ? D2D1::ColorF(0.75f, 0.75f, 0.76f) : D2D1::ColorF(0.35f, 0.35f, 0.37f);
        if (SUCCEEDED(target->CreateSolidColorBrush(ink, &brush))) {
            target->DrawTextLayout(D2D1::Point2F(0.0f, 0.0f), layout, brush, D2D1_DRAW_TEXT_OPTIONS_NONE);
            brush->Release();
        }
        layout->Release();
    }
    format->Release();
}

HRESULT spdf_win_paint(spdf_win_d2d* d2d, ID2D1RenderTarget* target, const spdf_win_scene* scene) {
    if (!d2d || !target || !scene) return E_POINTER;

    /* Everything downstream is in device pixels. */
    target->SetDpi(96.0f, 96.0f);
    target->BeginDraw();

    spdf_win_theme theme = spdf_win_theme_for(scene->dark);

    /* FIT_EXACT is the pixel-comparison path and has no chrome at all, so its
     * ground is the theme's own paper: an oversized target still reads as a
     * page rather than as a page on a gutter. */
    target->Clear(D2D1::ColorF(scene->fit == SPDF_WIN_FIT_EXACT ? theme.paper_rgb : theme.gutter_rgb));

    if (scene->fit == SPDF_WIN_FIT_EXACT) {
        ID2D1Bitmap* texture = NULL;
        if (scene->page && scene->page->rgba && scene->page->width > 0 && scene->page->height > 0)
            texture = page_texture(d2d, target, scene->page);
        if (texture)
            target->DrawBitmap(texture, D2D1::RectF(0.0f, 0.0f, (float)scene->page->width, (float)scene->page->height),
                               1.0f, D2D1_BITMAP_INTERPOLATION_MODE_NEAREST_NEIGHBOR, NULL);
        else
            draw_message(d2d, target, scene);
        return target->EndDraw();
    }

    /* CHROME. Drawn before the pages, and the pages are then clipped and
     * translated into the canvas region, so a page scrolled under the toolbar
     * cannot paint over it. Everything here goes through the same
     * ID2D1RenderTarget as the canvas, so the chrome is on the headless compose
     * path too -- which is what makes it pixel-testable at all, and the reason
     * the whole chrome layer is laid out by a pure header rather than from an
     * HWND. */
    SpdfWinChromeLayout chrome_layout;
    bool has_chrome = false;
    if (scene->chrome) {
        SpdfWinChromePaintCtx ctx;
        SpdfWinChromeTheme chrome_theme = spdf_win_chrome_theme_for(scene->dark);
        unsigned cw = scene->client_px_w ? scene->client_px_w : scene->target_px_w;
        unsigned ch = scene->client_px_h ? scene->client_px_h : scene->target_px_h;
        spdf_win_chrome_layout(scene->chrome, cw, ch, scene->dpi_scale, &chrome_layout);
        has_chrome = !spdf_win_chrome_rect_empty(chrome_layout.canvas);
        ctx.target = target;
        ctx.dwrite = d2d->dwrite;
        ctx.theme = &chrome_theme;
        ctx.model = scene->chrome;
        ctx.layout = &chrome_layout;
        ctx.dpi_scale = chrome_layout.dpi_scale;
        spdf_win_chrome_paint_all(ctx);

        if (has_chrome) {
            /* PushAxisAlignedClip, then a translate, so draw_canvas_page needs
             * no notion of the chrome at all: it keeps drawing at the canvas
             * coordinates the layout gave it. */
            target->PushAxisAlignedClip(spdf_win_chrome_d2d_rect(chrome_layout.canvas),
                                        D2D1_ANTIALIAS_MODE_ALIASED);
            target->SetTransform(D2D1::Matrix3x2F::Translation(chrome_layout.canvas.x, chrome_layout.canvas.y));
            /* The gutter under the pages is the canvas region's own, not the
             * whole client's: the Clear above painted the gutter everywhere,
             * and the chrome has since covered its own bands. */
        }
    }

    if (scene->pages && scene->page_count > 0) {
        /* Brushes for the whole strip rather than per page: a
         * CreateSolidColorBrush per page per frame is an allocation on the
         * scroll hot path, which architecture.md sec 9 says must stay O(1)-ish
         * per event.
         *
         * EXACTLY ONE of shade/border is created, from the theme. Light gets the
         * cheap one-band drop shadow -- not a gaussian, just enough to separate
         * paper from surround the way the mac app's blurred NSShadow does. Dark
         * gets the 1 px paperBorderColor frame instead, because black at 10%
         * over the #121212 gutter is not a separation at all: it is invisible on
         * three edges and the reason macOS made the same swap. */
        ID2D1SolidColorBrush* shade = NULL;
        ID2D1SolidColorBrush* paper = NULL;
        ID2D1SolidColorBrush* border = NULL;
        if (theme.draws_page_shadow) target->CreateSolidColorBrush(D2D1::ColorF(0.0f, 0.0f, 0.0f, 0.10f), &shade);
        if (theme.draws_page_border) target->CreateSolidColorBrush(D2D1::ColorF(theme.page_border_rgb), &border);
        target->CreateSolidColorBrush(D2D1::ColorF(theme.paper_rgb), &paper);
        for (int i = 0; i < scene->page_count; ++i)
            draw_canvas_page(d2d, target, scene, &scene->pages[i], shade, paper, border);
        safe_release(border);
        safe_release(paper);
        safe_release(shade);
    } else {
        draw_message(d2d, target, scene);
    }

    if (has_chrome) {
        target->SetTransform(D2D1::Matrix3x2F::Identity());
        target->PopAxisAlignedClip();
    }

    return target->EndDraw();
}

static HRESULT write_wic_png(spdf_win_d2d* d2d, IWICBitmap* bitmap, unsigned w, unsigned h, const wchar_t* path) {
    IWICStream* stream = NULL;
    IWICBitmapEncoder* encoder = NULL;
    IWICBitmapFrameEncode* frame = NULL;
    IWICBitmapSource* converted = NULL;
    IPropertyBag2* options = NULL;
    GUID format = GUID_WICPixelFormat32bppBGRA;

    HRESULT hr = d2d->wic->CreateStream(&stream);
    if (SUCCEEDED(hr)) hr = stream->InitializeFromFilename(path, GENERIC_WRITE);
    if (SUCCEEDED(hr)) hr = d2d->wic->CreateEncoder(GUID_ContainerFormatPng, NULL, &encoder);
    if (SUCCEEDED(hr)) hr = encoder->Initialize(stream, WICBitmapEncoderNoCache);
    if (SUCCEEDED(hr)) hr = encoder->CreateNewFrame(&frame, &options);
    if (SUCCEEDED(hr)) hr = frame->Initialize(options);
    if (SUCCEEDED(hr)) hr = frame->SetSize(w, h);
    if (SUCCEEDED(hr)) hr = frame->SetPixelFormat(&format);
    /* D2D can only draw into a premultiplied target, but a PNG's alpha is
     * straight. Convert rather than hand the encoder a format it has to guess
     * about. With an opaque page the two are byte-identical anyway. */
    if (SUCCEEDED(hr)) hr = WICConvertBitmapSource(GUID_WICPixelFormat32bppBGRA, bitmap, &converted);
    if (SUCCEEDED(hr)) hr = frame->WriteSource(converted, NULL);
    if (SUCCEEDED(hr)) hr = frame->Commit();
    if (SUCCEEDED(hr)) hr = encoder->Commit();

    safe_release(converted);
    safe_release(options);
    safe_release(frame);
    safe_release(encoder);
    safe_release(stream);
    return hr;
}

HRESULT spdf_win_render_scene_to_png(spdf_win_d2d* d2d, unsigned px_w, unsigned px_h, const spdf_win_scene* scene,
                                     const wchar_t* png_path) {
    if (!d2d || !scene || !png_path) return E_POINTER;
    if (px_w == 0 || px_h == 0) return E_INVALIDARG;

    IWICBitmap* bitmap = NULL;
    HRESULT hr = d2d->wic->CreateBitmap(px_w, px_h, GUID_WICPixelFormat32bppPBGRA, WICBitmapCacheOnLoad, &bitmap);
    if (FAILED(hr)) return hr;

    /* SOFTWARE, not DEFAULT. `prlctl exec` runs in the SYSTEM session: there
     * is no desktop and there may be no usable display adapter, and a target
     * that quietly wants a GPU is a target that fails only on the machine we
     * cannot see. */
    D2D1_RENDER_TARGET_PROPERTIES props = D2D1::RenderTargetProperties(
        D2D1_RENDER_TARGET_TYPE_SOFTWARE,
        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED), 96.0f, 96.0f);

    ID2D1RenderTarget* target = NULL;
    hr = d2d->factory->CreateWicBitmapRenderTarget(bitmap, props, &target);
    if (SUCCEEDED(hr)) {
        spdf_win_scene local = *scene;
        local.target_px_w = px_w;
        local.target_px_h = px_h;
        hr = spdf_win_paint(d2d, target, &local);
        spdf_win_d2d_release_target(d2d, target);
    }
    safe_release(target);

    if (SUCCEEDED(hr)) hr = write_wic_png(d2d, bitmap, px_w, px_h, png_path);
    safe_release(bitmap);
    return hr;
}
