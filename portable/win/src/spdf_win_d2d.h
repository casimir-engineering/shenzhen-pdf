/* Direct2D compose layer for the Windows frontend.
 *
 * THE LOAD-BEARING RULE OF THIS FILE (windows-port-plan.md sec 3, risk 9):
 * nothing here may require an HWND. spdf_win_paint() takes an
 * ID2D1RenderTarget* and draws into it, and it does not care whether that
 * target is backed by a window or by a WIC bitmap in a session with no
 * desktop at all. The windowed path in spdf_win_window.cpp is a thin caller
 * of it; the headless path (spdf_win_render_scene_to_png, and T4's probe) is
 * another thin caller of the very same function.
 *
 * That is the entire reason Direct2D was chosen over WinUI/Qt: `prlctl exec`
 * runs in the SYSTEM session, so a compose path that needs a window is a
 * compose path no agent can ever verify.
 *
 * This header is C-safe on purpose. In a .c translation unit the Windows SDK
 * declares ID2D1RenderTarget and IWICImagingFactory as opaque interface
 * typedefs, which is all a C caller needs to hold a pointer and hand it back
 * to us -- so T4's spdf_win_probe.c can stay plain C even though the
 * implementation behind this header is C++. See spdf_win_d2d.cpp for why the
 * implementation cannot be C.
 */
#ifndef SPDF_WIN_D2D_H
#define SPDF_WIN_D2D_H

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef COBJMACROS
#define COBJMACROS
#endif

#include <windows.h>
#include <d2d1.h>
#include <wincodec.h>

#include "shenzhen_pdf_core.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Factories plus one cached page texture. Created once per process; holds no
 * window, no device, no swap chain. */
typedef struct spdf_win_d2d spdf_win_d2d;

typedef enum spdf_win_fit {
    /* Page blitted 1:1 into the top-left of the target, no background, no
     * chrome. This is the pixel-comparison path: the output PNG is expected
     * to be the core's own RGBA buffer, unresampled, so any difference
     * against the macOS reference render is a real difference. */
    SPDF_WIN_FIT_EXACT = 0,
    /* Page scaled down to fit the target with a margin and centred on the app
     * background, with a soft edge. This is what the window shows. */
    SPDF_WIN_FIT_CONTAIN = 1
} spdf_win_fit;

/* Everything a paint needs. Deliberately free of Win32 handles: the same
 * struct is filled by the window and by a console probe. */
typedef struct spdf_win_scene {
    /* Borrowed RGBA page pixels from spdf_render_page_rgba_opts(). NULL is
     * legal and means "nothing to show yet"; `message` is drawn instead. */
    const spdf_bitmap* page;
    spdf_win_fit fit;
    /* Size of the target in DEVICE PIXELS. Passed in rather than queried off
     * the target: ID2D1RenderTarget::GetSize returns a struct by value, and
     * the calling convention for that has been a portability trap between the
     * C and C++ bindings of every D3D-family header. Whoever created the
     * target already knows the number. */
    unsigned target_px_w;
    unsigned target_px_h;
    /* Device pixels per logical pixel (1.0 at 96 dpi, 2.0 on a 2x display).
     * Chrome metrics are multiplied by this; the page itself is already
     * rendered at the right zoom by the caller. */
    float dpi_scale;
    int dark; /* dark surround, to match the dark reading theme */
    /* UTF-16 status or error line, drawn centred when `page` is NULL. May be
     * NULL. A missing font degrades to no text, never to a failed paint. */
    const wchar_t* message;
} spdf_win_scene;

/* err/err_len may be NULL/0. Returns NULL on failure. */
spdf_win_d2d* spdf_win_d2d_create(char* err, size_t err_len);
void spdf_win_d2d_destroy(spdf_win_d2d* d2d);

/* Needed by spdf_win_window.cpp to build its HWND render target, and by any
 * headless caller that wants to make its own WIC target. */
ID2D1Factory* spdf_win_d2d_factory(spdf_win_d2d* d2d);
IWICImagingFactory* spdf_win_d2d_wic(spdf_win_d2d* d2d);

/* THE render entry point. Brackets its own BeginDraw/EndDraw and returns
 * EndDraw's HRESULT, so D2DERR_RECREATE_TARGET reaches the caller that owns
 * the target and can rebuild it. Never touches an HWND. */
HRESULT spdf_win_paint(spdf_win_d2d* d2d, ID2D1RenderTarget* target, const spdf_win_scene* scene);

/* Drop any cached device resources bound to `target` before it is released.
 * Cheap and idempotent; passing NULL drops the cache unconditionally. */
void spdf_win_d2d_release_target(spdf_win_d2d* d2d, ID2D1RenderTarget* target);

/* Headless composite: makes a WIC bitmap of the requested size, runs the very
 * same spdf_win_paint() into a SOFTWARE render target over it, and writes a
 * 32bpp BGRA PNG. No window, no GPU, no desktop session. The scene's
 * target_px_w/h are overridden with px_w/px_h. */
HRESULT spdf_win_render_scene_to_png(spdf_win_d2d* d2d, unsigned px_w, unsigned px_h, const spdf_win_scene* scene,
                                     const wchar_t* png_path);

#ifdef __cplusplus
}
#endif

#endif /* SPDF_WIN_D2D_H */
