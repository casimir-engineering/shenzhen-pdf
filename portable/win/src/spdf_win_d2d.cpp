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

#include <dwrite.h>

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

struct spdf_win_d2d {
    ID2D1Factory* factory;
    IWICImagingFactory* wic;
    IDWriteFactory* dwrite; /* may be NULL: text is a nicety, never a blocker */
    bool co_initialized;

    /* One-entry page-texture cache. WM_PAINT fires far more often than the
     * page changes (every resize, every expose), and re-uploading a multi-MB
     * bitmap each time is exactly the sort of thing that shows up as a
     * stutter. Keyed on the target too, because an ID2D1Bitmap belongs to the
     * target that created it and dies with it. */
    ID2D1RenderTarget* cache_target;
    const unsigned char* cache_src;
    int cache_w;
    int cache_h;
    ID2D1Bitmap* cache_bitmap;
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
    safe_release(d2d->cache_bitmap);
    d2d->cache_target = NULL;
    d2d->cache_src = NULL;
    d2d->cache_w = 0;
    d2d->cache_h = 0;
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
    if (d2d->cache_bitmap && d2d->cache_target == target && d2d->cache_src == page->rgba &&
        d2d->cache_w == page->width && d2d->cache_h == page->height)
        return d2d->cache_bitmap;

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

    spdf_win_d2d_release_target(d2d, NULL);
    d2d->cache_bitmap = bitmap;
    d2d->cache_target = target;
    d2d->cache_src = page->rgba;
    d2d->cache_w = page->width;
    d2d->cache_h = page->height;
    return bitmap;
}

/* Places the page inside the target. EXACT is a 1:1 blit at the origin.
 * CONTAIN centres it with a margin and never scales ABOVE 1:1, because a page
 * rendered at the fit zoom is already the right number of pixels and blowing
 * it up would only add blur. */
static D2D1_RECT_F page_destination(const spdf_win_scene* scene, const spdf_bitmap* page) {
    float tw = (float)scene->target_px_w;
    float th = (float)scene->target_px_h;
    float pw = (float)page->width;
    float ph = (float)page->height;

    if (scene->fit == SPDF_WIN_FIT_EXACT) return D2D1::RectF(0.0f, 0.0f, pw, ph);

    float s = scene->dpi_scale > 0.0f ? scene->dpi_scale : 1.0f;
    float margin = 16.0f * s;
    float avail_w = tw - 2.0f * margin;
    float avail_h = th - 2.0f * margin;
    if (avail_w < 1.0f) avail_w = 1.0f;
    if (avail_h < 1.0f) avail_h = 1.0f;

    float scale = avail_w / pw;
    if (avail_h / ph < scale) scale = avail_h / ph;
    if (scale > 1.0f) scale = 1.0f;

    float w = pw * scale;
    float h = ph * scale;
    /* Whole-pixel placement: a half-pixel offset makes D2D resample a blit
     * that should have been exact. */
    float x = (float)(int)((tw - w) * 0.5f + 0.5f);
    float y = (float)(int)((th - h) * 0.5f + 0.5f);
    return D2D1::RectF(x, y, x + w, y + h);
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

    D2D1_COLOR_F background;
    if (scene->fit == SPDF_WIN_FIT_EXACT)
        background = D2D1::ColorF(1.0f, 1.0f, 1.0f); /* paper, so an oversized target still reads as a page */
    else if (scene->dark)
        background = D2D1::ColorF(0.129f, 0.129f, 0.137f);
    else
        background = D2D1::ColorF(0.878f, 0.878f, 0.886f);
    target->Clear(background);

    ID2D1Bitmap* texture = NULL;
    if (scene->page && scene->page->rgba && scene->page->width > 0 && scene->page->height > 0)
        texture = page_texture(d2d, target, scene->page);

    if (texture) {
        D2D1_RECT_F dest = page_destination(scene, scene->page);
        if (scene->fit == SPDF_WIN_FIT_CONTAIN) {
            /* A cheap one-band drop shadow -- not a gaussian, just enough to
             * separate paper from surround the way the mac app does. */
            float s = scene->dpi_scale > 0.0f ? scene->dpi_scale : 1.0f;
            ID2D1SolidColorBrush* shade = NULL;
            if (SUCCEEDED(target->CreateSolidColorBrush(D2D1::ColorF(0.0f, 0.0f, 0.0f, 0.10f), &shade))) {
                target->FillRectangle(D2D1::RectF(dest.left - 2.0f * s, dest.top, dest.right + 2.0f * s,
                                                  dest.bottom + 3.0f * s),
                                      shade);
                shade->Release();
            }
        }
        target->DrawBitmap(texture, dest, 1.0f,
                           scene->fit == SPDF_WIN_FIT_EXACT ? D2D1_BITMAP_INTERPOLATION_MODE_NEAREST_NEIGHBOR
                                                            : D2D1_BITMAP_INTERPOLATION_MODE_LINEAR,
                           NULL);
    } else {
        draw_message(d2d, target, scene);
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
